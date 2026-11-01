// Minimal QR Code encoder (byte mode, error correction level M, versions 1-10).
// Self-contained: no libraries and no internet needed.
// Usage: const qr = QR.encode("text");  qr.size, qr.get(x, y) -> true if dark
//        QR.draw(canvas, "text", pixelsPerModule)

const QR = (() => {
  // Error-correction level M: [EC codewords per block, [[blocks, data codewords per block], ...]]
  const EC = {
    1: [10, [[1, 16]]],
    2: [16, [[1, 28]]],
    3: [26, [[1, 44]]],
    4: [18, [[2, 32]]],
    5: [24, [[2, 43]]],
    6: [16, [[4, 27]]],
    7: [18, [[4, 31]]],
    8: [22, [[2, 38], [2, 39]]],
    9: [22, [[3, 36], [2, 37]]],
    10: [26, [[4, 43], [1, 44]]],
  };
  const ALIGN = {
    1: [], 2: [6, 18], 3: [6, 22], 4: [6, 26], 5: [6, 30],
    6: [6, 34], 7: [6, 22, 38], 8: [6, 24, 42], 9: [6, 26, 46], 10: [6, 28, 50],
  };

  const dataCodewords = (v) => EC[v][1].reduce((s, [n, k]) => s + n * k, 0);
  const bit = (x, i) => ((x >>> i) & 1) !== 0;

  // ----- Reed-Solomon over GF(256) -----
  function gfMul(x, y) {
    let z = 0;
    for (let i = 7; i >= 0; i--) {
      z = (z << 1) ^ ((z >>> 7) * 0x11d);
      z ^= ((y >>> i) & 1) * x;
    }
    return z;
  }
  function rsDivisor(degree) {
    const result = new Array(degree).fill(0);
    result[degree - 1] = 1;
    let root = 1;
    for (let i = 0; i < degree; i++) {
      for (let j = 0; j < result.length; j++) {
        result[j] = gfMul(result[j], root);
        if (j + 1 < result.length) result[j] ^= result[j + 1];
      }
      root = gfMul(root, 0x02);
    }
    return result;
  }
  function rsRemainder(data, divisor) {
    const result = divisor.map(() => 0);
    for (const b of data) {
      const factor = b ^ result.shift();
      result.push(0);
      divisor.forEach((coef, i) => { result[i] ^= gfMul(coef, factor); });
    }
    return result;
  }

  // ----- Build the final codeword sequence (data + EC, interleaved) -----
  function buildCodewords(bytes, version) {
    const total = dataCodewords(version);
    const bits = [];
    const push = (val, len) => { for (let i = len - 1; i >= 0; i--) bits.push((val >>> i) & 1); };
    push(0b0100, 4);                       // byte mode
    push(bytes.length, version < 10 ? 8 : 16);
    bytes.forEach((b) => push(b, 8));
    push(0, Math.min(4, total * 8 - bits.length)); // terminator
    while (bits.length % 8) bits.push(0);
    for (let pad = 0xec; bits.length < total * 8; pad ^= 0xec ^ 0x11) push(pad, 8);

    const data = [];
    for (let i = 0; i < bits.length; i += 8) {
      let v = 0;
      for (let j = 0; j < 8; j++) v = (v << 1) | bits[i + j];
      data.push(v);
    }

    const [ecLen, groups] = EC[version];
    const divisor = rsDivisor(ecLen);
    const dataBlocks = [];
    const ecBlocks = [];
    let pos = 0;
    for (const [count, size] of groups) {
      for (let i = 0; i < count; i++) {
        const block = data.slice(pos, pos + size);
        pos += size;
        dataBlocks.push(block);
        ecBlocks.push(rsRemainder(block, divisor));
      }
    }
    const out = [];
    const maxLen = Math.max(...dataBlocks.map((b) => b.length));
    for (let i = 0; i < maxLen; i++) dataBlocks.forEach((b) => { if (i < b.length) out.push(b[i]); });
    for (let i = 0; i < ecLen; i++) ecBlocks.forEach((b) => out.push(b[i]));
    return out;
  }

  // ----- Matrix construction -----
  function encode(text, forceMask) {
    const bytes = Array.from(new TextEncoder().encode(String(text)));
    let version = 0;
    for (let v = 1; v <= 10; v++) {
      const need = 4 + (v < 10 ? 8 : 16) + bytes.length * 8;
      if (need <= dataCodewords(v) * 8) { version = v; break; }
    }
    if (!version) throw new Error("Text is too long for this QR encoder");

    const size = 17 + version * 4;
    const modules = Array.from({ length: size }, () => new Array(size).fill(false));
    const isFunc = Array.from({ length: size }, () => new Array(size).fill(false));
    const setFunc = (x, y, dark) => {
      if (x < 0 || y < 0 || x >= size || y >= size) return;
      modules[y][x] = dark;
      isFunc[y][x] = true;
    };

    // timing
    for (let i = 0; i < size; i++) { setFunc(6, i, i % 2 === 0); setFunc(i, 6, i % 2 === 0); }
    // finder patterns (with separators)
    const finder = (cx, cy) => {
      for (let dy = -4; dy <= 4; dy++) for (let dx = -4; dx <= 4; dx++) {
        const dist = Math.max(Math.abs(dx), Math.abs(dy));
        setFunc(cx + dx, cy + dy, dist !== 2 && dist !== 4);
      }
    };
    finder(3, 3); finder(size - 4, 3); finder(3, size - 4);
    // alignment patterns
    const al = ALIGN[version];
    for (let i = 0; i < al.length; i++) for (let j = 0; j < al.length; j++) {
      if ((i === 0 && j === 0) || (i === 0 && j === al.length - 1) || (i === al.length - 1 && j === 0)) continue;
      for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++)
        setFunc(al[i] + dx, al[j] + dy, Math.max(Math.abs(dx), Math.abs(dy)) !== 1);
    }

    function drawFormat(mask) {
      const data = (0 << 3) | mask; // EC level M = 00
      let rem = data;
      for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
      const bits = ((data << 10) | rem) ^ 0x5412;
      for (let i = 0; i <= 5; i++) setFunc(8, i, bit(bits, i));
      setFunc(8, 7, bit(bits, 6)); setFunc(8, 8, bit(bits, 7)); setFunc(7, 8, bit(bits, 8));
      for (let i = 9; i < 15; i++) setFunc(14 - i, 8, bit(bits, i));
      for (let i = 0; i < 8; i++) setFunc(size - 1 - i, 8, bit(bits, i));
      for (let i = 8; i < 15; i++) setFunc(8, size - 15 + i, bit(bits, i));
      setFunc(8, size - 8, true); // always-dark module
    }
    function drawVersion() {
      if (version < 7) return;
      let rem = version;
      for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
      const bits = (version << 12) | rem;
      for (let i = 0; i < 18; i++) {
        const a = size - 11 + (i % 3);
        const b = Math.floor(i / 3);
        setFunc(a, b, bit(bits, i));
        setFunc(b, a, bit(bits, i));
      }
    }
    drawFormat(0);
    drawVersion();

    // place data in the zigzag pattern
    const codewords = buildCodewords(bytes, version);
    let k = 0;
    for (let right = size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < size; vert++) {
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          const upward = ((right + 1) & 2) === 0;
          const y = upward ? size - 1 - vert : vert;
          if (!isFunc[y][x] && k < codewords.length * 8) {
            modules[y][x] = bit(codewords[k >>> 3], 7 - (k & 7));
            k++;
          }
        }
      }
    }

    // masking
    function applyMask(mask) {
      for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        let inv;
        switch (mask) {
          case 0: inv = (x + y) % 2 === 0; break;
          case 1: inv = y % 2 === 0; break;
          case 2: inv = x % 3 === 0; break;
          case 3: inv = (x + y) % 3 === 0; break;
          case 4: inv = (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0; break;
          case 5: inv = ((x * y) % 2) + ((x * y) % 3) === 0; break;
          case 6: inv = (((x * y) % 2) + ((x * y) % 3)) % 2 === 0; break;
          default: inv = (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
        }
        if (!isFunc[y][x] && inv) modules[y][x] = !modules[y][x];
      }
    }
    function penalty() {
      let score = 0;
      const runPenalty = (get) => {
        for (let a = 0; a < size; a++) {
          let run = 1;
          for (let b = 1; b < size; b++) {
            if (get(a, b) === get(a, b - 1)) run++;
            else { if (run >= 5) score += run - 2; run = 1; }
          }
          if (run >= 5) score += run - 2;
          // finder-like pattern 1:1:3:1:1 with 4 light modules on a side
          for (let b = 0; b + 10 < size; b++) {
            const s = [];
            for (let t = 0; t < 11; t++) s.push(get(a, b + t) ? 1 : 0);
            const str = s.join("");
            if (str === "10111010000" || str === "00001011101") score += 40;
          }
        }
      };
      runPenalty((r, c) => modules[r][c]);
      runPenalty((c, r) => modules[r][c]);
      for (let y = 0; y < size - 1; y++) for (let x = 0; x < size - 1; x++) {
        const c = modules[y][x];
        if (c === modules[y][x + 1] && c === modules[y + 1][x] && c === modules[y + 1][x + 1]) score += 3;
      }
      let dark = 0;
      modules.forEach((row) => row.forEach((c) => { if (c) dark++; }));
      const total = size * size;
      score += (Math.ceil(Math.abs(dark * 20 - total * 10) / total) - 1) * 10;
      return score;
    }
    let best = 0, bestScore = Infinity;
    for (let m = 0; m < 8; m++) {
      if (forceMask !== undefined && m !== forceMask) continue;
      applyMask(m);
      drawFormat(m);
      const p = penalty();
      if (p < bestScore) { bestScore = p; best = m; }
      applyMask(m); // undo
    }
    applyMask(best);
    drawFormat(best);

    return { size, version, get: (x, y) => modules[y][x] };
  }

  // Draw onto a canvas with a 4-module quiet zone.
  function draw(canvas, text, scale = 6) {
    const qr = encode(text);
    const quiet = 4;
    const px = (qr.size + quiet * 2) * scale;
    canvas.width = px;
    canvas.height = px;
    const ctx = canvas.getContext("2d");
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, px, px);
    ctx.fillStyle = "#0f172a";
    for (let y = 0; y < qr.size; y++) for (let x = 0; x < qr.size; x++) {
      if (qr.get(x, y)) ctx.fillRect((x + quiet) * scale, (y + quiet) * scale, scale, scale);
    }
    return qr;
  }

  return { encode, draw };
})();

if (typeof module !== "undefined") module.exports = QR;
