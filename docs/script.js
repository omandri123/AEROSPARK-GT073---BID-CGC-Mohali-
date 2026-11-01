// BID Registration website.
// Validates the form, then POSTs the data to the Flask blockchain server (/add_block).

const form = document.getElementById("bidForm");
const submitBtn = document.getElementById("submitBtn");
const spinner = submitBtn.querySelector(".spinner");
const label = submitBtn.querySelector(".label");
const banner = document.getElementById("banner");
const result = document.getElementById("result");
const serverInput = document.getElementById("serverUrl");

const FIELDS = [
  "full_legal_name", "phone_number", "date_of_birth",
  "country_of_residence", "aadhaar", "proof_of_address", "dob_proof",
  "profile_photo",
];

// Remember the server URL in this browser (optional convenience).
try {
  const saved = localStorage.getItem("bid_server_url");
  if (saved) serverInput.value = saved;
} catch (_) { /* storage unavailable: ignore */ }

serverInput.addEventListener("change", () => {
  try { localStorage.setItem("bid_server_url", serverInput.value.trim()); } catch (_) {}
});

let currentBlockIndex = "";
const baseUrl = () => serverInput.value.trim().replace(/\/+$/, "");
const $ = (id) => document.getElementById(id);

// ---------- Input helpers ----------
$("phone_number").addEventListener("input", (e) => {
  e.target.value = e.target.value.replace(/\D/g, "").slice(0, 10);
});

$("aadhaar").addEventListener("input", (e) => {
  const digits = e.target.value.replace(/\D/g, "").slice(0, 12);
  e.target.value = digits.replace(/(\d{4})(?=\d)/g, "$1 ");
});

// ---------- Validation ----------
const rules = {
  full_legal_name: (v) => (v.trim().length >= 3 ? "" : "Enter your full legal name"),
  phone_number: (v) => (/^\d{10}$/.test(v) ? "" : "Phone number must be 10 digits"),
  date_of_birth: (v) => {
    if (!v) return "Select your date of birth";
    return new Date(v) > new Date() ? "Date of birth cannot be in the future" : "";
  },
  country_of_residence: (v) => (v ? "" : "Select a country"),
  aadhaar: (v) => (/^\d{4} \d{4} \d{4}$/.test(v) ? "" : "Aadhaar must be 12 digits"),
  proof_of_address: (v) => (v.trim().length >= 5 ? "" : "Enter your address proof"),
  dob_proof: (v) => (v ? "" : "Select a document"),
  profile_photo: () => (photoData ? "" : "Upload a profile photo"),
};

function validateField(name) {
  const el = $(name);
  const msg = rules[name](el.value);
  const box = el.closest(".field");
  box.classList.toggle("invalid", !!msg);
  form.querySelector(`.err[data-for="${name}"]`).textContent = msg;
  return !msg;
}

FIELDS.forEach((name) => {
  const el = $(name);
  el.addEventListener("blur", () => validateField(name));
  el.addEventListener("input", () => {
    if (el.closest(".field").classList.contains("invalid")) validateField(name);
  });
});

// ---------- Helpers ----------
function formatDob(iso) {           // 2004-08-15 -> 15-08-2004 (same as the app)
  const [y, m, d] = iso.split("-");
  return `${d}-${m}-${y}`;
}

function showBanner(msg) {
  banner.textContent = msg;
  banner.hidden = !msg;
}

function setLoading(on) {
  submitBtn.disabled = on;
  spinner.hidden = !on;
  label.textContent = on ? "Adding block..." : "Submit to blockchain";
}

// ---------- Demo data ----------
$("demoBtn").addEventListener("click", () => {
  $("full_legal_name").value = "Om Kumar Sharma";
  $("phone_number").value = "9876543210";
  $("date_of_birth").value = "2004-08-15";
  $("country_of_residence").value = "India";
  $("aadhaar").value = "1234 5678 9012";
  $("proof_of_address").value = "House 21, Sector 70, Mohali, Punjab 160071 (Electricity Bill)";
  $("dob_proof").value = "10th Marksheet - CBSE";
  setPhotoFromCanvas(makeDemoAvatar("OS"));
  FIELDS.forEach(validateField);
  showBanner("");
});

// ---------- Test connection ----------
$("testBtn").addEventListener("click", async () => {
  const out = $("testResult");
  out.className = "hint";
  out.textContent = "Testing...";
  try {
    const res = await fetch(`${baseUrl()}/validate`, { signal: AbortSignal.timeout(6000) });
    const data = await res.json();
    out.className = "hint ok";
    out.textContent = `Connected. Chain valid: ${data.valid}`;
  } catch (e) {
    out.className = "hint bad";
    out.textContent = "Cannot reach server. Check the URL and that Flask is running.";
  }
});

// ---------- Submit ----------
form.addEventListener("submit", async (e) => {
  e.preventDefault();
  showBanner("");

  const allOk = FIELDS.map(validateField).every(Boolean);
  if (!allOk) {
    showBanner("Please fix the highlighted fields.");
    const firstBad = form.querySelector(".field.invalid input, .field.invalid select, .field.invalid textarea");
    if (firstBad) firstBad.focus();
    return;
  }

  const payload = {
    full_legal_name: $("full_legal_name").value.trim(),
    phone_number: $("phone_number").value,
    date_of_birth: formatDob($("date_of_birth").value),
    country_of_residence: $("country_of_residence").value,
    aadhaar: $("aadhaar").value,
    proof_of_address: $("proof_of_address").value.trim(),
    dob_proof: $("dob_proof").value,
    profile_photo: photoData,           // base64 JPEG, encrypted by the server
  };

  setLoading(true);
  try {
    const res = await fetch(`${baseUrl()}/add_block`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(10000),
    });

    if (!res.ok) {
      let msg = await res.text();
      try { msg = JSON.parse(msg).error || msg; } catch (_) { /* plain text */ }
      throw new Error(`Server error ${res.status}: ${msg}`);
    }

    const data = await res.json();
    showResult(data);
  } catch (err) {
    if (err.name === "TimeoutError" || err instanceof TypeError) {
      showBanner(`Could not reach the blockchain server at ${baseUrl()}. Check the URL (Server settings) and that Flask is running.`);
    } else {
      showBanner(err.message);
    }
  } finally {
    setLoading(false);
  }
});

// ---------- Result ----------
function showResult(data) {
  $("bidValue").textContent = data.BID;
  $("blockIndex").textContent = data.index;
  $("blockTime").textContent = new Date().toLocaleString();
  form.hidden = true;
  result.hidden = false;
  toast("Block added to the blockchain");
  // QR code of the BID (generated in the browser, works offline)
  try {
    QR.draw($("qrCanvas"), data.BID, 8);
    $("qrBox").hidden = false;
  } catch (err) {
    $("qrBox").hidden = true;
    console.error("QR generation failed", err);
  }
  currentBlockIndex = data.index;
  if (photoData) {
    $("resultPhoto").src = "data:image/jpeg;base64," + photoData;
    $("photoNote").textContent = data.photo
      ? `Photo encrypted (AES) and fingerprinted. SHA-256: ${data.photo.sha256.slice(0, 16)}...`
      : "Photo stored.";
    $("resultPhotoRow").hidden = false;
  } else {
    $("resultPhotoRow").hidden = true;
  }
  result.scrollIntoView({ behavior: "smooth", block: "center" });
}

$("copyBtn").addEventListener("click", async () => {
  const btn = $("copyBtn");
  const text = $("bidValue").textContent;
  try {
    await navigator.clipboard.writeText(text);
  } catch (_) {
    // Fallback for non-secure contexts (plain http)
    const range = document.createRange();
    range.selectNodeContents($("bidValue"));
    const sel = getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    document.execCommand("copy");
  }
  const txt = btn.querySelector("span");
  txt.textContent = "Copied!";
  toast("BID copied to clipboard");
  setTimeout(() => (txt.textContent = "Copy BID"), 1500);
});

$("againBtn").addEventListener("click", () => {
  form.reset();
  clearPhoto();
  FIELDS.forEach((n) => {
    $(n).closest(".field").classList.remove("invalid");
    form.querySelector(`.err[data-for="${n}"]`).textContent = "";
  });
  result.hidden = true;
  form.hidden = false;
  showBanner("");
});

// ---------- Toast ----------
function toast(message) {
  const box = document.getElementById("toasts");
  const el = document.createElement("div");
  el.className = "toast";
  el.textContent = message;
  box.appendChild(el);
  setTimeout(() => el.remove(), 3000);
}

// ---------- Animated blockchain network background ----------
(function network() {
  const canvas = document.getElementById("net");
  const ctx = canvas.getContext("2d");
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let nodes = [];

  function resize() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
    const count = Math.min(70, Math.floor(window.innerWidth / 25));
    nodes = Array.from({ length: count }, () => ({
      x: Math.random() * canvas.width,
      y: Math.random() * canvas.height,
      vx: (Math.random() - 0.5) * 0.4,
      vy: (Math.random() - 0.5) * 0.4,
      r: Math.random() * 2 + 1,
    }));
  }

  function frame() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (let i = 0; i < nodes.length; i++) {
      const a = nodes[i];
      if (!reduce) {
        a.x += a.vx; a.y += a.vy;
        if (a.x < 0 || a.x > canvas.width) a.vx *= -1;
        if (a.y < 0 || a.y > canvas.height) a.vy *= -1;
      }
      ctx.beginPath();
      ctx.arc(a.x, a.y, a.r, 0, Math.PI * 2);
      ctx.fillStyle = "#0284c7";
      ctx.fill();
      for (let j = i + 1; j < nodes.length; j++) {
        const b = nodes[j];
        const d = Math.hypot(a.x - b.x, a.y - b.y);
        if (d < 110) {
          ctx.beginPath();
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(b.x, b.y);
          ctx.strokeStyle = `rgba(2,132,199,${0.15 - d / 700})`;
          ctx.stroke();
        }
      }
    }
    if (!reduce) requestAnimationFrame(frame);
  }

  resize();
  frame();
  window.addEventListener("resize", () => { resize(); if (reduce) frame(); });
})();

// ---------- Download the QR code as a PNG ----------
$("qrDownloadBtn").addEventListener("click", () => {
  $("qrCanvas").toBlob((blob) => {
    if (!blob) return;
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `BID-QR-block-${currentBlockIndex}.png`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    toast("QR code downloaded");
  }, "image/png");
});

// ---------- Profile photo ----------
// The photo is cropped to a square, shrunk and re-encoded as JPEG in the browser.
// This keeps it tiny (so it can be shared phone-to-phone) and removes hidden metadata.
const MAX_PHOTO_BYTES = 18 * 1024;
let photoData = null;                   // base64 JPEG (no "data:" prefix)

const b64Bytes = (b64) =>
  Math.floor((b64.length * 3) / 4) - (b64.endsWith("==") ? 2 : b64.endsWith("=") ? 1 : 0);

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = () => { URL.revokeObjectURL(url); reject(new Error("This file could not be read as an image")); };
    img.src = url;
  });
}

function squareToJpeg(source, srcW, srcH) {
  const side = Math.min(srcW, srcH);
  const sx = (srcW - side) / 2;
  const sy = (srcH - side) / 2;
  const canvas = document.createElement("canvas");
  const ctx = canvas.getContext("2d");
  for (const size of [192, 160, 128, 96]) {
    canvas.width = size;
    canvas.height = size;
    ctx.fillStyle = "#ffffff";          // JPEG has no transparency
    ctx.fillRect(0, 0, size, size);
    ctx.drawImage(source, sx, sy, side, side, 0, 0, size, size);
    for (const q of [0.82, 0.7, 0.6, 0.5, 0.4]) {
      const b64 = canvas.toDataURL("image/jpeg", q).split(",")[1];
      if (b64Bytes(b64) <= MAX_PHOTO_BYTES) return { b64, size };
    }
  }
  throw new Error("This photo is too detailed to shrink enough. Try a simpler one.");
}

function showPhoto(b64, note) {
  photoData = b64;
  $("avatarImg").src = "data:image/jpeg;base64," + b64;
  $("avatarImg").hidden = false;
  $("avatar").classList.add("has-photo");
  $("avatar").querySelector(".avatar-ic").style.display = "none";
  $("photoBtn").textContent = "Change photo";
  $("photoClear").hidden = false;
  const info = $("photoInfo");
  info.className = "hint ok";
  info.textContent = note;
  $("profile_photo").closest(".field").classList.remove("invalid");
  form.querySelector('.err[data-for="profile_photo"]').textContent = "";
}

function clearPhoto() {
  photoData = null;
  $("avatarImg").hidden = true;
  $("avatarImg").removeAttribute("src");
  $("avatar").classList.remove("has-photo");
  $("avatar").querySelector(".avatar-ic").style.display = "";
  $("photoBtn").textContent = "Choose photo";
  $("photoClear").hidden = true;
  $("profile_photo").value = "";
  const info = $("photoInfo");
  info.className = "hint";
  info.textContent = "JPEG or PNG. It is cropped to a square, shrunk, and stored encrypted.";
}

function setPhotoFromCanvas(canvas) {
  const out = squareToJpeg(canvas, canvas.width, canvas.height);
  showPhoto(out.b64, `Ready: ${out.size}x${out.size}, ${(b64Bytes(out.b64) / 1024).toFixed(1)} KB. Encrypted when submitted.`);
}

function makeDemoAvatar(initials) {
  const c = document.createElement("canvas");
  c.width = c.height = 192;
  const g = c.getContext("2d");
  const grad = g.createLinearGradient(0, 0, 192, 192);
  grad.addColorStop(0, "#0284c7");
  grad.addColorStop(1, "#2563eb");
  g.fillStyle = grad;
  g.fillRect(0, 0, 192, 192);
  g.fillStyle = "#ffffff";
  g.font = "700 76px system-ui, sans-serif";
  g.textAlign = "center";
  g.textBaseline = "middle";
  g.fillText(initials, 96, 100);
  return c;
}

$("photoBtn").addEventListener("click", () => $("profile_photo").click());
$("photoClear").addEventListener("click", () => { clearPhoto(); validateField("profile_photo"); });

$("profile_photo").addEventListener("change", async (e) => {
  const file = e.target.files[0];
  if (!file) return;
  const info = $("photoInfo");
  try {
    if (!file.type.startsWith("image/")) throw new Error("Please choose an image file (JPEG or PNG)");
    if (file.size > 15 * 1024 * 1024) throw new Error("That file is too big. Choose a photo under 15 MB");
    const img = await loadImage(file);
    const out = squareToJpeg(img, img.naturalWidth, img.naturalHeight);
    showPhoto(out.b64, `Ready: ${out.size}x${out.size}, ${(b64Bytes(out.b64) / 1024).toFixed(1)} KB. Encrypted when submitted.`);
  } catch (err) {
    clearPhoto();
    info.className = "hint bad";
    info.textContent = err.message;
  }
});
