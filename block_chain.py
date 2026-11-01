import base64
import binascii
import hashlib
import json
import os
import time

from cryptography.fernet import Fernet, InvalidToken
from flask import Flask, request, jsonify

app = Flask(__name__)

# Profile photos: kept small so they can also be sent phone-to-phone.
MAX_PHOTO_BYTES = 24 * 1024            # decoded image size limit
app.config["MAX_CONTENT_LENGTH"] = 256 * 1024   # whole request limit
STORAGE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "storage")
os.makedirs(STORAGE_DIR, exist_ok=True)


# Allow the website (a browser, on another origin) to call this server.
@app.after_request
def add_cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
    return response

# ---------------------------------------------------------------------------
# Encryption key (AES via Fernet). Created once and saved in secret.key.
# SHA-256 is a HASH (one-way) -> used for block IDs / chain linking.
# Fernet is real ENCRYPTION (reversible) -> used to protect the personal data.
# ---------------------------------------------------------------------------
KEY_FILE = "secret.key"


def load_key():
    if os.path.exists(KEY_FILE):
        with open(KEY_FILE, "rb") as f:
            return f.read()
    key = Fernet.generate_key()
    with open(KEY_FILE, "wb") as f:
        f.write(key)
    return key


fernet = Fernet(load_key())


def hashgenerator(data):
    return hashlib.sha256(data.encode()).hexdigest()


# ---------------------------------------------------------------------------
# Profile photo handling.
# The image is ENCRYPTED (Fernet/AES) and saved as storage/<sha256>.enc.
# Only its SHA-256 fingerprint + metadata go into the block, so the block hash
# also protects the photo: if the file is changed, the fingerprint no longer
# matches and the photo is refused.
# ---------------------------------------------------------------------------
def detect_image_type(raw):
    if raw.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if raw.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    return None


def store_photo(b64):
    """Validate, encrypt and save a photo. Returns the metadata for the block."""
    if not isinstance(b64, str):
        raise ValueError("Profile photo must be sent as base64 text")
    if b64.startswith("data:") and "," in b64:
        b64 = b64.split(",", 1)[1]
    try:
        raw = base64.b64decode(b64, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError("Profile photo is not valid base64")
    if not raw:
        raise ValueError("Profile photo is empty")
    if len(raw) > MAX_PHOTO_BYTES:
        raise ValueError(f"Profile photo is too large ({len(raw) // 1024} KB, max {MAX_PHOTO_BYTES // 1024} KB)")
    mime = detect_image_type(raw)
    if mime is None:
        raise ValueError("Profile photo must be a JPEG or PNG image")

    digest = hashlib.sha256(raw).hexdigest()
    with open(os.path.join(STORAGE_DIR, digest + ".enc"), "wb") as f:
        f.write(fernet.encrypt(raw))
    return {"sha256": digest, "size": len(raw), "mime": mime}


def load_photo(meta):
    """Decrypt a stored photo and check it against the fingerprint in the block."""
    digest = str(meta.get("sha256", ""))
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise ValueError("Invalid photo record")
    path = os.path.join(STORAGE_DIR, digest + ".enc")
    if not os.path.exists(path):
        raise FileNotFoundError("Photo file is missing on the server")
    try:
        with open(path, "rb") as f:
            raw = fernet.decrypt(f.read())
    except InvalidToken:
        raise ValueError("Photo file is corrupted or tampered with")
    if hashlib.sha256(raw).hexdigest() != digest:
        raise ValueError("Photo failed the SHA-256 integrity check")
    return raw


class Block:
    def __init__(self, index, data, hash, prev_hash, timestamp=None):
        self.index = index
        self.data = data  # encrypted string (or "Genesis Block")
        self.hash = hash
        self.prev_hash = prev_hash
        self.timestamp = timestamp or time.time()

    def compute_hash(self):
        return hashgenerator(f"{self.index}{self.timestamp}{self.data}{self.prev_hash}")


class BlockChain:
    def __init__(self):
        hashlast = hashgenerator("gen_last")
        hashstart = hashgenerator("gen_start")
        genesis = Block(0, "Genesis Block", hashstart, hashlast)
        self.chain = [genesis]

    def add_block(self, data):
        prev_hash = self.chain[-1].hash
        plaintext = json.dumps(data, sort_keys=True)
        encrypted = fernet.encrypt(plaintext.encode()).decode()

        new_block = Block(len(self.chain), encrypted, "", prev_hash)
        new_block.hash = new_block.compute_hash()
        self.chain.append(new_block)
        return new_block

    def is_valid(self):
        for i in range(1, len(self.chain)):
            cur, prev = self.chain[i], self.chain[i - 1]
            if cur.prev_hash != prev.hash:
                return False
            if cur.hash != cur.compute_hash():
                return False
        return True

    def find(self, block_hash):
        for b in self.chain:
            if b.hash == block_hash:
                return b
        return None


blockchain = BlockChain()


def print_block(block, photo=None):
    print("\n" + "=" * 70)
    print(f" NEW BLOCK #{block.index}")
    print("=" * 70)
    print(f" Timestamp : {time.ctime(block.timestamp)}")
    print(f" Prev Hash : {block.prev_hash}")
    print(f" Hash (BID): {block.hash}")
    print(f" Encrypted : {block.data[:120]}...")
    if photo:
        print(f" Photo     : encrypted ({photo['size']} bytes, {photo['mime']})")
        print(f" Photo hash: {photo['sha256']}")
    print(f" Chain valid: {blockchain.is_valid()}")
    print("=" * 70 + "\n")


@app.route("/add_block", methods=["POST"])
def add_block():
    data = request.get_json(silent=True)
    if not data or not isinstance(data, dict):
        return jsonify({"error": "No data provided"}), 400

    photo_meta = None
    photo = data.pop("profile_photo", None)
    if photo:
        try:
            photo_meta = store_photo(photo)
        except ValueError as e:
            return jsonify({"error": str(e)}), 400
        data["profile_photo"] = photo_meta   # only the fingerprint goes in the block

    block = blockchain.add_block(data)
    print_block(block, photo_meta)

    return jsonify({
        "message": "Block added successfully",
        "BID": block.hash,
        "index": block.index,
        "photo": photo_meta,
    }), 200


@app.errorhandler(413)
def too_large(_e):
    return jsonify({"error": "Request too large. Use a smaller photo."}), 413


@app.route("/get_chain", methods=["GET"])
def get_chain():
    chain_data = [
        {
            "index": b.index,
            "data": b.data,
            "hash": b.hash,
            "prev_hash": b.prev_hash,
            "timestamp": b.timestamp,
        }
        for b in blockchain.chain
    ]
    return jsonify({"length": len(chain_data), "chain": chain_data}), 200


@app.route("/validate", methods=["GET"])
def validate():
    return jsonify({"valid": blockchain.is_valid()}), 200


@app.route("/decrypt/<block_hash>", methods=["GET"])
def decrypt(block_hash):
    """Demo only: shows the original data of a block (needs the server key)."""
    block = blockchain.find(block_hash)
    if block is None or block.index == 0:
        return jsonify({"error": "Block not found"}), 404
    original = json.loads(fernet.decrypt(block.data.encode()).decode())
    return jsonify({"BID": block.hash, "data": original}), 200


ALLOWED_FIELDS = [
    "full_legal_name",
    "phone_number",
    "date_of_birth",
    "country_of_residence",
    "aadhaar",
    "proof_of_address",
    "dob_proof",
    "profile_photo",
]


@app.route("/get_data", methods=["POST"])
def get_data():
    """Used by the app. Body: {"bid": "<hash>", "fields": ["full_legal_name", ...]}
    Returns ONLY the requested fields of that block (decrypted)."""
    body = request.get_json(silent=True) or {}
    bid = body.get("bid")
    fields = body.get("fields")

    if not bid or not isinstance(fields, list) or not fields:
        return jsonify({"error": "Send 'bid' and a non-empty 'fields' list"}), 400

    block = blockchain.find(bid)
    if block is None or block.index == 0:
        return jsonify({"error": "BID not found"}), 404

    original = json.loads(fernet.decrypt(block.data.encode()).decode())
    result = {
        f: original[f]
        for f in fields
        if f in ALLOWED_FIELDS and f in original and f != "profile_photo"
    }

    # The photo is only decrypted when it is explicitly requested.
    if "profile_photo" in fields and isinstance(original.get("profile_photo"), dict):
        try:
            raw = load_photo(original["profile_photo"])
        except FileNotFoundError as e:
            return jsonify({"error": str(e)}), 404
        except ValueError as e:
            return jsonify({"error": str(e)}), 409
        result["profile_photo"] = base64.b64encode(raw).decode()

    return jsonify({"BID": bid, "data": result}), 200


@app.route("/decrypt_all", methods=["GET"])
def decrypt_all():
    """Demo only: decrypts every block in the chain (needs the server key)."""
    result = []
    for b in blockchain.chain:
        if b.index == 0:
            data = "Genesis Block"
        else:
            try:
                data = json.loads(fernet.decrypt(b.data.encode()).decode())
            except Exception:
                data = "UNABLE TO DECRYPT (wrong key or tampered data)"
        result.append({
            "index": b.index,
            "hash": b.hash,
            "prev_hash": b.prev_hash,
            "timestamp": b.timestamp,
            "data": data,
        })
    return jsonify({"length": len(result), "chain": result}), 200


if __name__ == "__main__":
    # debug=False so the chain is not created twice by the reloader
    app.run(host="0.0.0.0", port=5000, debug=False)
