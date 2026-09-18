// degenerative by ryley-o.eth — Art Blocks Studio Generator
//
// 37 of grandma's watercolor paintings, captured in diffvg painterly-stroke
// space. Each token is assigned one of 7 degenerative styles (tied to Christian
// themes of vanity, exile, transfiguration, etc.) by its mint hash — permanent.
// The artist sets a weekly "chaos factor" (0–100) for 52 weeks in Year 1.
// Each subsequent year repeats the same 52 values → 52 unique outputs per token.
//
// PostParam keys injected by DegenerativeHook on every read:
//   p0..p2  base64 chunks of painting binary data (~19 KB each, ~55 KB total)
//   week    current week-of-year (1–52) derived from block.timestamp on-chain
//   chaos   artist's chaos value for that week (0–100); 0 = pure painting
//
// URL params (all take priority over postparams/tokenData; work in production too):
//   ?render=true   pure painting, no chaos (thumbnail mode)
//   ?hash=0x...    override hash (32 bytes, 0x-prefixed)
//   ?week=N        override week-of-year (1-52)
//   ?chaos=N       override chaos value (0-100)

// ─── CONFIG ──────────────────────────────────────────────────────────────────

const NUM_PAINTINGS = 37;
const NUM_STYLES    = 7;

// Each token is assigned one style permanently at mint (from hash).
// Styles are tied to Christian themes of spiritual decay and grace.
const STYLES = [
  { id: 2, name: 'Erosion'       }, // Vanity        — strokes return to nothing
  { id: 9, name: 'Wander'        }, // Exile         — strokes drift from where they belong
  { id: 3, name: 'Palette Drift' }, // Transfiguration — colours remade into something other
  { id: 5, name: 'Chromatic'     }, // Refinement    — the similar are purged
  { id: 6, name: 'Flood'         }, // Wrath         — colour drowned, overwhelmed by deep water
  { id: 4, name: 'Bold'          }, // Revelation    — strokes harden into full presence
  { id: 8, name: 'Excess'        }, // Temptation    — strokes bloat, saturate, overwhelm
];

// Reflection prompts, keyed by style id — see lore.md for the design rules
// and reasoning behind each. Never addressed to "you"; general enough to
// apply to a person, a civilization, a belief, or a stroke of paint equally.
const REFLECTIONS = {
  2: { // Erosion
    low:    "What is a thing worth, before anyone notices it's gone?",
    medium: 'Does forgetting begin with an ending — or long before it?',
    high:   'If nothing remembers a thing, was it ever really there?',
  },
  9: { // Wander
    low:    'Can something be lost without ever leaving?',
    medium: 'How many small steps turn a path into a departure?',
    high:   "Is there a way home that doesn't first require knowing something left?",
  },
  3: { // Palette Drift
    low:    "Is a thing still itself once its color stops telling the truth about it?",
    medium: 'How would anyone tell the difference between becoming and disguising?',
    high:   'What survives, when only the shape stayed the same?',
  },
  5: { // Chromatic
    low:    'What is essential, and what was only ever repetition?',
    medium: 'Does fire choose what burns, or only reveal what was fireproof all along?',
    high:   'Once everything similar is gone, what is there left to compare it to?',
  },
  6: { // Flood
    low:    'Is a flood the disaster — or only proof that one was already underway?',
    medium: 'At what point does enough become too much, and does anyone notice it pass?',
    high:   'Which rises first: the water, or the reason for it?',
  },
  4: { // Bold
    low:    "What's hidden that isn't hiding on purpose?",
    medium: 'Is there mercy in not being fully seen?',
    high:   'What would be left, if nothing could stay unseen?',
  },
  8: { // Excess
    low:    'At what size does growth stop being health?',
    medium: 'Where is the edge of enough — and who moved it?',
    high:   "What happens to a thing once it's given everything it wanted?",
  },
};

// chaosValue 0 → no reflection (nothing degenerated this week to sit with).
function reflectionFor(styleId, chaosValue) {
  if (chaosValue <= 0) return null;
  const tier = chaosValue <= 33 ? 'low' : chaosValue <= 66 ? 'medium' : 'high';
  return REFLECTIONS[styleId]?.[tier] ?? null;
}

// ─── PRNG ─────────────────────────────────────────────────────────────────────

function mkPRNG(seed) {
  let s = seed >>> 0;
  return function () {
    s = (s + 0x6D2B79F5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = t + Math.imul(t ^ (t >>> 7), 61 | t) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// ─── HASH / TOKEN UTILITIES ───────────────────────────────────────────────────

function hashSeed32(hash) {
  return parseInt(hash.slice(2, 10), 16) >>> 0;
}

function styleForWeek(hs32, week) {
  // Hash the token seed with the week number → random style, repeatable per token+week
  return Math.floor(mkPRNG((hs32 ^ (week * 0x9E3779B9)) >>> 0)() * NUM_STYLES);
}

function paintingIdxFromTokenId(tokenId) {
  return parseInt(tokenId) % 1_000_000 % NUM_PAINTINGS;
}

// ─── DATE UTILITIES (wall-clock fallback) ──────────────────────────────────────
//
// On-chain, the hook injects `week` from block.timestamp. This fallback covers
// any case where that postparam isn't present yet — most commonly local dev,
// but also a safety net if the hook hasn't run for some reason.

function weekOfYear(date) {
  const start = new Date(date.getFullYear(), 0, 1);
  const doy   = Math.ceil((date - start) / 86_400_000); // 1-366
  return Math.min(52, Math.ceil(doy / 7));               // 1-52
}

// ─── BITREADER ────────────────────────────────────────────────────────────────

class BitReader {
  constructor(bytes) {
    this.bytes = bytes;
    this.pos   = 0;
  }
  readBits(n) {
    let v = 0;
    for (let i = 0; i < n; i++) {
      const byte = this.bytes[this.pos >> 3];
      const bit  = (byte >> (7 - (this.pos & 7))) & 1;
      v = (v << 1) | bit;
      this.pos++;
    }
    return v;
  }
}

// ─── DECODER ─────────────────────────────────────────────────────────────────
//
// Binary format (paths_strokes_bitpacked2):
//   1 byte  canvas width  (257 + byte)
//   1 byte  canvas height (257 + byte)
//   2 bytes stroke count  (big-endian uint16)
//   per stroke (162 bits, bit-packed):
//     9 bits  middle X   [-100, 600]
//     9 bits  middle Y   [-100, 600]
//     7 bits  scale X    [0, 127]
//     7 bits  scale Y    [0, 127]
//     10×2×5 bits  10 control points normalised to 32×32 grid
//     4×6 bits     stroke RGBA colour [0, 1]
//     6 bits  stroke width [1.0, 4.0]

function hexToBytes(hex) {
  const b = new Uint8Array(hex.length >> 1);
  for (let i = 0; i < hex.length; i += 2)
    b[i >> 1] = parseInt(hex.substr(i, 2), 16);
  return b;
}

function b64ToBytes(b64) {
  const s = atob(b64);
  const b = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) b[i] = s.charCodeAt(i);
  return b;
}

function chunkedB64ToBytes(params) {
  const chunks = [];
  let total = 0;
  for (let i = 0; ; i++) {
    const c = params['p' + i];
    if (!c) break;
    const bytes = b64ToBytes(c);
    chunks.push(bytes);
    total += bytes.length;
  }
  if (!total) return null;
  const out = new Uint8Array(total);
  let off = 0;
  for (const c of chunks) { out.set(c, off); off += c.length; }
  return out;
}

function decodeStrokes(bytes) {
  const r = new BitReader(bytes);
  const cw = 257 + r.readBits(8);
  const ch = 257 + r.readBits(8);
  const n  = (r.readBits(8) << 8) | r.readBits(8);

  const paths = [];
  for (let i = 0; i < n; i++) {
    const mxB = r.readBits(9), myB = r.readBits(9);
    const sxB = r.readBits(7), syB = r.readBits(7);
    const mx = -100 + (mxB / 511) * 700;
    const my = -100 + (myB / 511) * 700;
    const sx = sxB || 1, sy = syB || 1;

    const pts = [];
    for (let j = 0; j < 10; j++) {
      const nx = r.readBits(5), ny = r.readBits(5);
      pts.push([mx + sx * (2 * nx / 31 - 1),
                my + sy * (2 * ny / 31 - 1)]);
    }
    const sc = [0, 0, 0, 0];
    for (let j = 0; j < 4; j++) sc[j] = r.readBits(6) / 63;
    const sw = 1.0 + (r.readBits(6) / 63) * 3.0;

    paths.push({ points: pts, stroke_color: sc, stroke_width: sw });
  }
  return { canvas: { width: cw, height: ch }, paths };
}

// ─── HELPERS ─────────────────────────────────────────────────────────────────

function cloneData(d) { return JSON.parse(JSON.stringify(d)); }

// ─── COLOUR UTILITIES ─────────────────────────────────────────────────────────

function rgbToHsl(r, g, b) {
  const max = Math.max(r, g, b), min = Math.min(r, g, b);
  let h, s;
  const l = (max + min) / 2;
  if (max === min) { h = s = 0; } else {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
      case g: h = ((b - r) / d + 2) / 6; break;
      default: h = ((r - g) / d + 4) / 6;
    }
  }
  return { h: h * 360, s, l };
}

function hslToRgb(h, s, l) {
  h /= 360;
  if (s === 0) return { r: l, g: l, b: l };
  const hue2rgb = (p, q, t) => {
    if (t < 0) t += 1; if (t > 1) t -= 1;
    if (t < 1/6) return p + (q - p) * 6 * t;
    if (t < 1/2) return q;
    if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
    return p;
  };
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s;
  const p = 2 * l - q;
  return { r: hue2rgb(p, q, h + 1/3), g: hue2rgb(p, q, h), b: hue2rgb(p, q, h - 1/3) };
}

function rgbToLab(r, g, b) {
  // sRGB → linear
  const lin = v => v > 0.04045 ? Math.pow((v + 0.055) / 1.055, 2.4) : v / 12.92;
  const lr = lin(r) * 100, lg = lin(g) * 100, lb = lin(b) * 100;
  let x = (lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375) / 95.047;
  let y = (lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750) / 100.0;
  let z = (lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041) / 108.883;
  const f = v => v > 0.008856 ? Math.cbrt(v) : 7.787 * v + 16/116;
  x = f(x); y = f(y); z = f(z);
  return { L: 116 * y - 16, a: 500 * (x - y), b: 200 * (y - z) };
}

function colorDistanceLab(lab1, lab2) {
  return Math.sqrt((lab1.L-lab2.L)**2 + (lab1.a-lab2.a)**2 + (lab1.b-lab2.b)**2);
}

function perceptualDist(r1, g1, b1, r2, g2, b2) {
  return colorDistanceLab(rgbToLab(r1, g1, b1), rgbToLab(r2, g2, b2));
}

// ─── PALETTE GENERATION (for Mode 3) ─────────────────────────────────────────

const HARMONY_TYPES = ['complementary','triadic','analogous','split-complementary','tetradic'];

function generatePalette(seed) {
  const R   = mkPRNG(seed);
  const bh  = R() * 360;
  const ht  = HARMONY_TYPES[Math.floor(R() * HARMONY_TYPES.length)];
  const bs  = 0.45 + R() * 0.45;
  const bl  = 0.35 + R() * 0.30;

  let hues;
  switch (ht) {
    case 'complementary':      hues = [bh, (bh+180)%360]; break;
    case 'triadic':            hues = [bh, (bh+120)%360, (bh+240)%360]; break;
    case 'analogous':          hues = [(bh+330)%360, bh, (bh+30)%360, (bh+60)%360]; break;
    case 'split-complementary':hues = [bh, (bh+150)%360, (bh+210)%360]; break;
    default:                   hues = [bh, (bh+90)%360, (bh+180)%360, (bh+270)%360];
  }

  const palette = hues.map(h => {
    const s = Math.max(0.25, Math.min(0.95, bs + (R()-0.5)*0.35));
    const l = Math.max(0.15, Math.min(0.85, bl + (R()-0.5)*0.35));
    const c = hslToRgb(h, s, l);
    return [c.r, c.g, c.b];
  });

  while (palette.length < 4) {
    const base = palette[Math.floor(R() * palette.length)];
    const hsl  = rgbToHsl(...base);
    const nl   = R() > 0.5
      ? Math.min(0.9, hsl.l + 0.2 + R()*0.15)
      : Math.max(0.1, hsl.l - 0.2 - R()*0.15);
    const c = hslToRgb(hsl.h, hsl.s, nl);
    palette.push([c.r, c.g, c.b]);
  }

  return palette.slice(0, 4);
}

function closestPaletteColor(r, g, b, palette) {
  let best = palette[0], bestD = Infinity;
  for (const p of palette) {
    const d = perceptualDist(r, g, b, p[0], p[1], p[2]);
    if (d < bestD) { bestD = d; best = p; }
  }
  return best;
}

// ─── RENDERING ────────────────────────────────────────────────────────────────

function renderStrokes(ctx, data, cw, ch) {
  const sx = cw / data.canvas.width, sy = ch / data.canvas.height;
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, cw, ch);
  ctx.save();
  ctx.scale(sx, sy);
  for (const p of data.paths) {
    if (p.deleted) continue;
    const [r, g, b, a] = p.stroke_color;
    ctx.beginPath();
    const pts = p.points;
    ctx.moveTo(pts[0][0], pts[0][1]);
    ctx.bezierCurveTo(pts[1][0],pts[1][1], pts[2][0],pts[2][1], pts[3][0],pts[3][1]);
    ctx.bezierCurveTo(pts[4][0],pts[4][1], pts[5][0],pts[5][1], pts[6][0],pts[6][1]);
    ctx.bezierCurveTo(pts[7][0],pts[7][1], pts[8][0],pts[8][1], pts[9][0],pts[9][1]);
    ctx.strokeStyle = `rgba(${Math.round(r*255)},${Math.round(g*255)},${Math.round(b*255)},${a})`;
    ctx.lineWidth   = p.stroke_width * 2 * 1.2;
    ctx.lineCap     = 'round';
    ctx.lineJoin    = 'round';
    ctx.stroke();
  }
  ctx.restore();
}

// ─── MODE 2: EROSION (random deletion) ────────────────────────────────────────

function applyErosion(origData, pct, seed) {
  if (!pct) return cloneData(origData);
  const data = cloneData(origData);
  const n = data.paths.length;
  const toDelete = Math.floor((pct / 100) * (n - 1));
  const R = mkPRNG(seed + 77777);
  const idx = Array.from({ length: n }, (_, i) => i);
  for (let i = n - 1; i > 0; i--) {
    const j = Math.floor(R() * (i + 1));
    [idx[i], idx[j]] = [idx[j], idx[i]];
  }
  for (let i = 0; i < toDelete; i++) data.paths[idx[i]].deleted = true;
  return data;
}

// ─── MODE 3: PALETTE DRIFT ────────────────────────────────────────────────────

function applyPaletteDrift(origData, pct, seed) {
  if (!pct) return cloneData(origData);
  const data = cloneData(origData);
  const n = data.paths.length;
  const palette = generatePalette(seed + 12300);
  const R = mkPRNG(seed + 12345);

  if (pct === 100) {
    const keepIdx = Math.floor(R() * n);
    for (let i = 0; i < n; i++) {
      if (i !== keepIdx) { data.paths[i].deleted = true; continue; }
      const [r, g, b, a] = data.paths[i].stroke_color;
      const c = closestPaletteColor(r, g, b, palette);
      data.paths[i].stroke_color = [c[0], c[1], c[2], a];
    }
    return data;
  }

  const touched = new Array(n).fill(0);
  let touchedCount = 0;
  const target = Math.floor((pct / 100) * n);
  const avail  = Array.from({ length: n }, (_, i) => i);
  let iters = 0;

  while (touchedCount < target && avail.length && iters < n * 10) {
    iters++;
    const ri = Math.floor(R() * avail.length);
    const si = avail[ri];
    const path = data.paths[si];
    if (touched[si] === 0) {
      const [r, g, b, a] = path.stroke_color;
      const c = closestPaletteColor(r, g, b, palette);
      path.stroke_color = [c[0], c[1], c[2], a];
      touched[si] = 1; touchedCount++;
    } else if (touched[si] === 1) {
      path.deleted = true; touched[si] = 2;
      avail.splice(ri, 1);
    }
  }
  return data;
}

// ─── MODE 9: WANDER (frozen movement — each stroke displaced to a unique position) ──

function applyWander(origData, pct, seed, animProgress) {
  if (!pct) return cloneData(origData);
  const frozenT   = mkPRNG(seed + 13579)() * 20;
  const movParams = buildMovementParams(origData, seed);
  const working   = cloneData(origData);
  const n         = working.paths.length;
  const toMove    = Math.floor((pct / 100) * n);
  const R         = mkPRNG(seed + 97531);
  const idx       = Array.from({ length: n }, (_, i) => i);
  for (let i = n - 1; i > 0; i--) {
    const j = Math.floor(R() * (i + 1));
    [idx[i], idx[j]] = [idx[j], idx[i]];
  }
  const norm = animProgress !== undefined ? animProgress : 1;
  applyMovement(working, origData, movParams, frozenT, norm * 100, new Set(idx.slice(0, toMove)));
  return working;
}

// ─── MODE 5: CHROMATIC (colour-similarity deletion) ───────────────────────────

function applyChromatic(origData, pct, seed) {
  if (!pct) return cloneData(origData);
  const data = cloneData(origData);
  const n = data.paths.length;
  const R = mkPRNG(seed + 55555);
  const anchorIdx = Math.floor(R() * n);
  const [ar, ag, ab] = origData.paths[anchorIdx].stroke_color;
  const ranked = origData.paths.map((p, i) => {
    if (i === anchorIdx) return { i, d: Infinity };
    const [r, g, b] = p.stroke_color;
    return { i, d: perceptualDist(ar, ag, ab, r, g, b) };
  }).sort((a, b) => a.d - b.d);
  const toDelete = Math.floor((pct / 100) * (n - 1));
  for (let i = 0; i < toDelete; i++) data.paths[ranked[i].i].deleted = true;
  return data;
}

// ─── MODE 6: FLOOD (colour overwhelmed by a deep seeded hue) ─────────────────
// Strokes furthest from the flood colour are converted first — maximum contrast
// changes are visible even at low chaos; near-flood strokes are added last.

function applyFlood(origData, pct, seed) {
  if (!pct) return cloneData(origData);
  const data   = cloneData(origData);
  const n      = data.paths.length;
  const R      = mkPRNG(seed + 33311);
  const floodH = R() * 360;
  const floodS = 0.55 + R() * 0.35;
  const floodL = 0.10 + R() * 0.25;
  const { r: fr, g: fg, b: fb } = hslToRgb(floodH, floodS, floodL);
  const ranked = origData.paths
    .map((path, i) => {
      const [r, g, b] = path.stroke_color;
      return { i, d: perceptualDist(r, g, b, fr, fg, fb) };
    })
    .sort((a, b) => b.d - a.d); // furthest first
  const toFlood = Math.floor((pct / 100) * n);
  for (let k = 0; k < toFlood; k++) {
    const path = data.paths[ranked[k].i];
    path.stroke_color = [fr, fg, fb, path.stroke_color[3]];
  }
  return data;
}

// ─── WANDER / BOLD SHARED HELPERS ────────────────────────────────────────────
// buildMovementParams + applyMovement are used by applyWander (mode 9).

function buildMovementParams(data, seed) {
  const R = mkPRNG(seed + 54321);
  const params = { strokes: [] };
  for (const path of data.paths) {
    let cx = 0, cy = 0;
    for (const pt of path.points) { cx += pt[0]; cy += pt[1]; }
    cx /= path.points.length;
    cy /= path.points.length;
    params.strokes.push({
      phaseX:   R() * Math.PI * 2,
      phaseY:   R() * Math.PI * 2,
      freqX:    0.5 + R() * 1.5,
      freqY:    0.5 + R() * 1.5,
      phaseRot: R() * Math.PI * 2,
      freqRot:  0.3 + R() * 0.7,
      cx, cy,
      points: path.points.map(() => ({
        phaseX: R() * Math.PI * 2,
        phaseY: R() * Math.PI * 2,
        freqX:  1.0 + R() * 2.0,
        freqY:  1.0 + R() * 2.0,
      })),
    });
  }
  return params;
}

function applyMovement(workingData, origData, movParams, t, pct, selected) {
  const norm   = pct / 100;
  const cMin   = Math.min(origData.canvas.width, origData.canvas.height);
  const movMag = cMin * 0.07875 * Math.pow(norm, 1.5);
  const rotMag = 14 * (Math.PI / 180) * Math.pow(norm, 1.5);
  const SPEED  = 1.5;
  for (let si = 0; si < workingData.paths.length; si++) {
    if (selected && !selected.has(si)) continue;
    const path = workingData.paths[si];
    const orig = origData.paths[si];
    const sp   = movParams.strokes[si];
    const dx   = Math.sin(t * SPEED * sp.freqX + sp.phaseX) * movMag * 0.6;
    const dy   = Math.cos(t * SPEED * sp.freqY + sp.phaseY) * movMag * 0.6;
    const rot  = Math.sin(t * SPEED * sp.freqRot + sp.phaseRot) * rotMag;
    const cos  = Math.cos(rot), sin = Math.sin(rot);
    for (let pi = 0; pi < path.points.length; pi++) {
      const [ox, oy] = orig.points[pi];
      const pp  = sp.points[pi];
      const pdx = Math.sin(t * SPEED * pp.freqX + pp.phaseX) * movMag * 0.25;
      const pdy = Math.cos(t * SPEED * pp.freqY + pp.phaseY) * movMag * 0.25;
      const vx = ox - sp.cx, vy = oy - sp.cy;
      path.points[pi][0] = sp.cx + vx * cos - vy * sin + dx + pdx;
      path.points[pi][1] = sp.cy + vx * sin + vy * cos + dy + pdy;
    }
  }
}

// ─── MODE 4: BOLD (random strokes → full opacity) ────────────────────────────

function applyBold(origData, pct, seed) {
  if (!pct) return cloneData(origData);
  const data = cloneData(origData);
  const n    = data.paths.length;
  const toBold = Math.floor((pct / 100) * n);
  const R    = mkPRNG(seed + 44444);
  const idx  = Array.from({ length: n }, (_, i) => i);
  for (let i = n - 1; i > 0; i--) {
    const j = Math.floor(R() * (i + 1));
    [idx[i], idx[j]] = [idx[j], idx[i]];
  }
  for (let i = 0; i < toBold; i++) data.paths[idx[i]].stroke_color[3] = 1.0;
  return data;
}

// ─── MODE 8: EXCESS (compounding width + saturation) ─────────────────────────

function applyExcess(origData, pct, seed) {
  if (!pct) return cloneData(origData);
  const data = cloneData(origData);
  const n    = data.paths.length;
  const R    = mkPRNG(seed + 88888);

  const anchorIdx = Math.floor(R() * n);
  const [ar, ag, ab] = origData.paths[anchorIdx].stroke_color;
  const dists = origData.paths.map((p, i) => {
    const [r, g, b] = p.stroke_color;
    return { i, d: perceptualDist(ar, ag, ab, r, g, b) };
  });
  const maxD = Math.max(...dists.map(s => s.d)) || 1;
  const sims  = dists.map(s => ({ i: s.i, sim: 0.1 + 0.9 * (1 - s.d / maxD) }));
  const total = sims.reduce((s, x) => s + x.sim, 0);
  let cumul = 0;
  const cdf = sims.map(s => { cumul += s.sim / total; return { i: s.i, cp: cumul }; });

  const visits = new Array(n).fill(0);
  const numV   = Math.floor((pct / 100) * n * 5);
  for (let k = 0; k < numV; k++) {
    const rv = R();
    for (const c of cdf) { if (rv <= c.cp) { visits[c.i]++; break; } }
  }

  for (let si = 0; si < n; si++) {
    const v = visits[si]; if (!v) continue;
    const path = data.paths[si];
    const orig = origData.paths[si];

    path.stroke_width = orig.stroke_width * Math.pow(1.20, v);

    const [r, g, b, a] = orig.stroke_color;
    const hsl = rgbToHsl(r, g, b);
    let ns = hsl.s; for (let k = 0; k < v; k++) ns += (1 - ns) * 0.12;
    ns = Math.min(0.99, ns);
    let na = a; for (let k = 0; k < v; k++) na += (1 - na) * 0.18;
    na = Math.min(1, na);
    const { r: nr, g: ng, b: nb } = hslToRgb(hsl.h, ns, hsl.l);
    path.stroke_color = [nr, ng, nb, na];

    const snapStr = Math.min(0.95, v * 0.15);
    let cx = 0, cy = 0;
    for (const pt of orig.points) { cx += pt[0]; cy += pt[1]; }
    cx /= orig.points.length; cy /= orig.points.length;

    for (let pi = 0; pi < path.points.length; pi++) {
      const [ox, oy] = orig.points[pi];
      const dx = ox - cx, dy = oy - cy;
      const dist = Math.hypot(dx, dy);
      if (dist < 1) continue;
      const angle    = Math.atan2(dy, dx);
      const snapped  = Math.round(angle / (Math.PI/4)) * (Math.PI/4);
      const newAngle = angle + (snapped - angle) * snapStr;
      path.points[pi][0] = cx + Math.cos(newAngle) * dist;
      path.points[pi][1] = cy + Math.sin(newAngle) * dist;
    }
  }
  return data;
}

// ─── CANVAS SETUP ─────────────────────────────────────────────────────────────

const canvas = document.querySelector('canvas');
const ctx    = canvas.getContext('2d');

function sizeCanvas(paintW, paintH) {
  const vw = window.innerWidth, vh = window.innerHeight;
  const paintAspect = paintW / paintH;
  let cw, ch;
  if (vw / vh > paintAspect) { ch = vh; cw = vh * paintAspect; }
  else                        { cw = vw; ch = vw / paintAspect; }
  // Backing store at device pixel density (capped — diminishing returns
  // past 3x, and it's real memory/paint cost): CSS size stays in logical
  // pixels via canvas.style, only the drawing surface itself gets denser.
  // renderStrokes() always draws at whatever canvas.width/height actually
  // are, so this alone is enough — no separate ctx.scale() needed.
  const dpr = Math.min(window.devicePixelRatio || 1, 3);
  canvas.width  = Math.floor(cw * dpr);
  canvas.height = Math.floor(ch * dpr);
  canvas.style.width  = Math.floor(cw) + 'px';
  canvas.style.height = Math.floor(ch) + 'px';
}

// ─── MAIN ─────────────────────────────────────────────────────────────────────

(async function main() {
  const query   = new URLSearchParams(window.location.search);
  const isRender= query.get('render') === 'true';
  const isDev   = window.location.hostname === 'localhost' ||
                  window.location.hostname === '127.0.0.1' ||
                  window.location.protocol === 'file:';

  // ── Token data ────────────────────────────────────────────────────────────
  const pmpDep  = (tokenData.externalAssetDependencies || [])
                    .find(d => d.dependency_type === 'ONCHAIN');
  const params  = (pmpDep && pmpDep.data) ? pmpDep.data : {};

  // ?hash= takes priority over tokenData.hash — useful for previewing how any
  // hash would style a token without needing a different minted token to look at.
  const hashOverride = query.get('hash');
  const hash = /^0x[0-9a-fA-F]{64}$/.test(hashOverride || '') ? hashOverride : tokenData.hash;

  const paintingIdx = paintingIdxFromTokenId(tokenData.tokenId);
  const hs32        = hashSeed32(hash);

  // week and chaos come from the hook (block.timestamp on-chain), with
  // ?week=/?chaos= URL params taking priority — useful for previewing any
  // week/chaos combination on a live, already-minted token.
  // Falls back to wall-clock week if postparams aren't present yet (local dev,
  // or before the hook has run).
  const weekOverride  = parseInt(query.get('week'));
  const chaosOverride = parseInt(query.get('chaos'));
  const week  = Number.isFinite(weekOverride)  ? Math.min(52, Math.max(1, weekOverride))
              : params.week   ? parseInt(params.week)
              : weekOfYear(new Date());
  const chaos = Number.isFinite(chaosOverride) ? Math.min(100, Math.max(0, chaosOverride))
              : params.chaos  ? parseInt(params.chaos)
              : 0;

  const styleIdx   = styleForWeek(hs32, week);
  const style      = STYLES[styleIdx];
  const weekSeed   = (hs32 ^ Math.imul(week, 0x9E3779B9)) >>> 0;
  const chaosValue = isRender ? 0 : chaos;

  if (isRender) console.log('degenerative — render=true, setting chaos to 0%');
  console.log(
    `degenerative — painting #${paintingIdx}  ·  week ${week}  ·  chaos ${chaosValue}%  ·  style ${style.name}\n` +
    `hash ${hash}`
  );

  const reflection = reflectionFor(style.id, chaosValue);
  if (reflection) console.log(`degenerative —\n${reflection}`);

  console.log(
    'degenerative — commands:\n' +
    '  s  →  export a ~4000px-wide HD PNG\n' +
    '  p  →  export 300dpi print-quality tiles (36" wide) + a stitching tool'
  );

  // ── Set features synchronously (required by Art Blocks spec) ─────────────
  const chaosLabel = chaosValue === 0   ? 'None'
                   : chaosValue <= 20  ? 'Trace'
                   : chaosValue <= 40  ? 'Low'
                   : chaosValue <= 60  ? 'Medium'
                   : chaosValue <= 80  ? 'High'
                   : chaosValue < 100  ? 'Extreme'
                   :                     'Total';

  window.$features = {
    'Painting': paintingIdx,
    'Style':    isRender ? 'Origin' : style.name,
    'Chaos':    isRender ? 'None'   : chaosLabel,
    'Week':     isRender ? 0        : week,
  };

  // ── Initial canvas size (will resize once painting loads) ─────────────────
  canvas.width  = window.innerWidth;
  canvas.height = window.innerHeight;

  // ── Load painting data ────────────────────────────────────────────────────
  let strokeData = null;
  const hasPostParams = !!(params.p0);

  if (hasPostParams) {
    try {
      const bytes = chunkedB64ToBytes(params);
      if (bytes) strokeData = decodeStrokes(bytes);
    } catch (e) { console.error('decode error', e); }
  }

  if (!strokeData && isDev) {
    // Dev fallback: fetch hex directly from ganvg/diffvg output directory
    try {
      const pad = String(paintingIdx).padStart(2, '0');
      const url = `../ganvg/diffvg/apps/painterly-out/_${pad}/paths_strokes_bitpacked2.hex`;
      const hex = await fetch(url).then(r => {
        if (!r.ok) throw new Error(r.statusText);
        return r.text();
      });
      strokeData = decodeStrokes(hexToBytes(hex.trim()));
    } catch (e) { console.warn('dev fetch failed:', e); }
  }

  if (!strokeData) {
    // No data yet — show a holding state
    ctx.fillStyle = '#0a0a0a';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = '#555';
    ctx.font = `${Math.min(canvas.width, canvas.height) * 0.035}px monospace`;
    ctx.textAlign = 'center';
    ctx.fillText('awaiting initialization', canvas.width/2, canvas.height/2);
    return;
  }

  // ── Size canvas to painting aspect ratio ──────────────────────────────────
  sizeCanvas(strokeData.canvas.width, strokeData.canvas.height);

  // Dispatch: apply the token's fixed style at a given chaos percentage.
  // animProgress (0–1) is only used by wander to lerp stroke positions into place.
  function applyStyle(pct, animProgress) {
    switch (style.id) {
      case 2: return applyErosion(strokeData, pct, weekSeed);
      case 9: return applyWander(strokeData, pct, weekSeed, animProgress);
      case 3: return applyPaletteDrift(strokeData, pct, weekSeed);
      case 5: return applyChromatic(strokeData, pct, weekSeed);
      case 6: return applyFlood(strokeData, pct, weekSeed);
      case 4: return applyBold(strokeData, pct, weekSeed);
      case 8: return applyExcess(strokeData, pct, weekSeed);
      default: return strokeData;
    }
  }

  // The fully-settled stroke data for the current token/week — identical to
  // what the canvas shows once its settle animation finishes. Used for export.
  function getFinalData() {
    return (isRender || chaosValue === 0) ? strokeData : applyStyle(chaosValue, 1);
  }

  // ── Render ────────────────────────────────────────────────────────────────
  if (isRender || chaosValue === 0) {
    renderStrokes(ctx, strokeData, canvas.width, canvas.height);
  } else {
    // Cubic ease-in-out: slow start, fast middle, slow finish.
    function easeInOut(t) {
      return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2;
    }

    // Animate from pure painting → final degenerated state.
    // Viewer experiences the degeneration unfolding before the piece settles.
    const ANIM_MS   = 2200;
    const animStart = performance.now();
    const isWander  = style.id === 9;

    (function frame(now) {
      const t            = Math.min(1, (now - animStart) / ANIM_MS);
      const animProgress = easeInOut(t);
      const pct          = isWander ? chaosValue : animProgress * chaosValue;
      const data         = pct >= 0.1 ? applyStyle(pct, animProgress) : strokeData;
      renderStrokes(ctx, data, canvas.width, canvas.height);
      if (t < 1) requestAnimationFrame(frame);
    })(performance.now());
  }

  // Re-fit and redraw on any viewport size change — window resize on the
  // web, or the containing WKWebView's frame changing (device rotation, the
  // companion app's fullscreen toggle) in the iOS app. Always redraws the
  // settled state; a resize mid-intro-animation just jumps to final rather
  // than trying to preserve animation progress across the resize.
  window.addEventListener('resize', () => {
    sizeCanvas(strokeData.canvas.width, strokeData.canvas.height);
    renderStrokes(ctx, getFinalData(), canvas.width, canvas.height);
  });

  // ── High-resolution export (hotkeys) ──────────────────────────────────────
  //
  // Strokes are vector data (control points + width + color), not a bitmap —
  // re-rendering at a larger target resolution costs no quality vs. the
  // on-screen canvas, same as re-rendering an SVG at higher DPI.
  //
  // A single browser <canvas> caps out around 268M px (Chrome/Firefox; Safari
  // is historically tighter), so the print export still *renders* in tiles —
  // each safely small — never holding the full print-resolution image in a
  // canvas at once. But the tiles' raw pixels can be composited into one
  // plain typed array (no canvas-size limit applies to an ArrayBuffer) and
  // encoded to a single PNG file entirely in-browser: PNG's compressed data
  // *is* a zlib stream, and `CompressionStream('deflate')` is a native
  // browser API that produces exactly that — so this needs no bundled zlib,
  // just a couple dozen lines of PNG chunk framing (reusing the CRC-32 below,
  // the same algorithm PNG and ZIP both use). Where that's unsupported (or
  // the in-memory composite is too large for the device), this falls back to
  // the original tiles-plus-external-stitch-tool flow further down.
  //
  //   s — download a ~4000px-wide PNG
  //   p — download a single 300dpi print-quality PNG (36" wide), stitched
  //       client-side; falls back to per-tile downloads + a stitch tool if
  //       the browser or device can't manage it

  const EXPORT_HD_WIDTH   = 4000;
  const EXPORT_PRINT_DPI  = 300;
  const EXPORT_PRINT_INCH = 36;
  const EXPORT_TILE_SIZE  = 4096; // well under every browser's canvas cap

  // The tile stitcher (a tiny Node + sharp script) is embedded verbatim as
  // static text and zipped client-side — no network fetch, no new script
  // dependency. It downloads alongside the tiles so a collector never needs
  // this repo to reassemble their print, only Node.js.
  const STITCH_TOOL_SRC = "#!/usr/bin/env node\n//\n// Reassembles the print-quality tiles downloaded by sketch.js's 'p' export\n// hotkey into a single full-resolution PNG. Runs outside the browser (no\n// canvas-size cap) using sharp/libvips, which streams the composite instead\n// of holding the whole image in memory at once.\n//\n// Usage:\n//   node stitch-print-tiles.mjs <tilesDir> <stamp> [outFile]\n//\n//   tilesDir   directory containing \"<stamp>-manifest.json\" and its tiles\n//              (e.g. ~/Downloads, if that's where the browser saved them)\n//   stamp      e.g. \"degenerative-p12-w30\" (printed to the console by the\n//              'p' export, and the prefix of every downloaded tile filename)\n//   outFile    optional output path (default: \"<tilesDir>/<stamp>-full.png\")\n\nimport sharp from 'sharp';\nimport { readFileSync, existsSync } from 'node:fs';\nimport { join } from 'node:path';\n\nconst [, , tilesDir, stamp, outFileArg] = process.argv;\n\nif (!tilesDir || !stamp) {\n  console.error('usage: node stitch-print-tiles.mjs <tilesDir> <stamp> [outFile]');\n  process.exit(1);\n}\n\nconst manifestPath = join(tilesDir, `${stamp}-manifest.json`);\nif (!existsSync(manifestPath)) {\n  console.error(`manifest not found: ${manifestPath}`);\n  process.exit(1);\n}\n\nconst manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));\nconst outFile = outFileArg || join(tilesDir, `${stamp}-full.png`);\n\nconsole.log(`stitching ${manifest.tiles.length} tiles into ${manifest.fullWidth}×${manifest.fullHeight}px ...`);\n\nconst composites = manifest.tiles.map((t) => {\n  const tilePath = join(tilesDir, t.file);\n  if (!existsSync(tilePath)) {\n    console.error(`missing tile: ${tilePath}`);\n    process.exit(1);\n  }\n  return { input: tilePath, left: t.x, top: t.y };\n});\n\nawait sharp({\n  create: {\n    width: manifest.fullWidth,\n    height: manifest.fullHeight,\n    channels: 3,\n    background: { r: 255, g: 255, b: 255 },\n  },\n})\n  .composite(composites)\n  .png()\n  .toFile(outFile);\n\nconsole.log(`done: ${outFile}`);\n";
  const STITCH_TOOL_PACKAGE_JSON = "{\n  \"name\": \"degenerative-tools\",\n  \"version\": \"1.0.0\",\n  \"type\": \"module\",\n  \"scripts\": {\n    \"stitch\": \"node stitch-print-tiles.mjs\"\n  },\n  \"dependencies\": {\n    \"sharp\": \"^0.33.5\"\n  }\n}\n";
  const STITCH_TOOL_README = "degenerative — print tile stitcher\n===================================\n\nThe 'p' hotkey exported a set of print-resolution PNG tiles plus a\nmanifest describing how they fit together. This tool reassembles them\ninto one full-resolution PNG. It runs outside the browser (via Node.js)\nbecause the final image is larger than any browser canvas can hold.\n\nRequires Node.js: https://nodejs.org (any recent version)\n\nSteps:\n  1. Unzip this folder next to your downloaded tiles (or move the tiles\n     and the '<stamp>-manifest.json' file into this folder).\n  2. npm install\n  3. node stitch-print-tiles.mjs <folder-with-tiles> <stamp>\n\n     e.g. node stitch-print-tiles.mjs ~/Downloads degenerative-p12-w30\n\nProduces '<stamp>-full.png' at full print resolution.\n";

  let stitchToolSent = false; // only bundle the zip once per page session

  function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

  function downloadBlob(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a   = document.createElement('a');
    a.href = url; a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 2000);
  }

  function downloadCanvas(canvasEl, filename) {
    return new Promise((resolve) => {
      canvasEl.toBlob((blob) => { downloadBlob(blob, filename); resolve(); }, 'image/png');
    });
  }

  // ── Minimal in-browser ZIP writer (STORE method, no compression) ─────────
  // Only needs to bundle a few small text files, so skipping DEFLATE keeps
  // this to a couple dozen lines with zero external dependency.

  let crc32Table = null;
  function crc32(bytes) {
    if (!crc32Table) {
      crc32Table = new Uint32Array(256);
      for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
        crc32Table[n] = c >>> 0;
      }
    }
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) crc = crc32Table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  function buildZip(files) {
    const enc = new TextEncoder();
    const DOS_DATE = 0x5C21, DOS_TIME = 0x0000; // fixed placeholder date (2026-01-01)
    const localParts = [], centralParts = [];
    let offset = 0;

    for (const f of files) {
      const nameBytes = enc.encode(f.name);
      const data      = enc.encode(f.content);
      const crc       = crc32(data);

      const local = new DataView(new ArrayBuffer(30));
      local.setUint32(0, 0x04034b50, true);
      local.setUint16(4, 20, true);
      local.setUint16(6, 0, true);
      local.setUint16(8, 0, true); // STORE
      local.setUint16(10, DOS_TIME, true);
      local.setUint16(12, DOS_DATE, true);
      local.setUint32(14, crc, true);
      local.setUint32(18, data.length, true);
      local.setUint32(22, data.length, true);
      local.setUint16(26, nameBytes.length, true);
      local.setUint16(28, 0, true);
      localParts.push(new Uint8Array(local.buffer), nameBytes, data);

      const central = new DataView(new ArrayBuffer(46));
      central.setUint32(0, 0x02014b50, true);
      central.setUint16(4, 20, true);
      central.setUint16(6, 20, true);
      central.setUint16(8, 0, true);
      central.setUint16(10, 0, true);
      central.setUint16(12, DOS_TIME, true);
      central.setUint16(14, DOS_DATE, true);
      central.setUint32(16, crc, true);
      central.setUint32(20, data.length, true);
      central.setUint32(24, data.length, true);
      central.setUint16(28, nameBytes.length, true);
      central.setUint16(30, 0, true);
      central.setUint16(32, 0, true);
      central.setUint16(34, 0, true);
      central.setUint16(36, 0, true);
      central.setUint32(38, 0, true);
      central.setUint32(42, offset, true);
      centralParts.push(new Uint8Array(central.buffer), nameBytes);

      offset += 30 + nameBytes.length + data.length;
    }

    const centralStart = offset;
    const centralSize   = centralParts.reduce((s, p) => s + p.length, 0);

    const eocd = new DataView(new ArrayBuffer(22));
    eocd.setUint32(0, 0x06054b50, true);
    eocd.setUint16(8, files.length, true);
    eocd.setUint16(10, files.length, true);
    eocd.setUint32(12, centralSize, true);
    eocd.setUint32(16, centralStart, true);

    const allParts = [...localParts, ...centralParts, new Uint8Array(eocd.buffer)];
    const total = allParts.reduce((s, p) => s + p.length, 0);
    const out = new Uint8Array(total);
    let pos = 0;
    for (const p of allParts) { out.set(p, pos); pos += p.length; }
    return out;
  }

  // Brief, self-dismissing on-canvas note — purely a UI affordance, never
  // part of the deterministic render (drawn as a DOM overlay, not onto the
  // artwork's own canvas pixels).
  function showToast(message, durationMs = 5000) {
    const el = document.createElement('div');
    el.textContent = message;
    el.style.cssText = [
      'position: fixed', 'left: 50%', 'bottom: 8%', 'transform: translateX(-50%)',
      'max-width: 90vw', 'padding: 12px 20px', 'border-radius: 10px',
      'background: rgba(0,0,0,0.75)', 'color: #fff',
      'font: 13px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
      'text-align: center', 'white-space: pre-line', 'z-index: 1000',
      'opacity: 0', 'transition: opacity 0.4s ease', 'pointer-events: none',
    ].join(';');
    document.body.appendChild(el);
    requestAnimationFrame(() => { el.style.opacity = '1'; });
    setTimeout(() => {
      el.style.opacity = '0';
      setTimeout(() => el.remove(), 500);
    }, durationMs);
  }

  function downloadStitchTool() {
    if (stitchToolSent) return;
    stitchToolSent = true;
    const zipBytes = buildZip([
      { name: 'README.txt',              content: STITCH_TOOL_README },
      { name: 'package.json',            content: STITCH_TOOL_PACKAGE_JSON },
      { name: 'stitch-print-tiles.mjs',  content: STITCH_TOOL_SRC },
    ]);
    downloadBlob(new Blob([zipBytes], { type: 'application/zip' }), 'degenerative-stitch-tool.zip');
  }

  // Shared by the keyboard export path and the exposed window.* API (used by
  // the iOS companion app via WKWebView's evaluateJavaScript — see
  // ios/Degenerative). Pure rendering, no download/DOM side effects, so both
  // callers can decide what to do with the resulting canvas.
  function renderHDCanvas(width) {
    const data = getFinalData();
    const w = width || EXPORT_HD_WIDTH;
    const h = Math.round(w * strokeData.canvas.height / strokeData.canvas.width);
    const off = document.createElement('canvas');
    off.width = w; off.height = h;
    renderStrokes(off.getContext('2d'), data, w, h);
    return off;
  }

  function printManifest() {
    const fullW = Math.round(EXPORT_PRINT_INCH * EXPORT_PRINT_DPI);
    const fullH = Math.round(fullW * strokeData.canvas.height / strokeData.canvas.width);
    const cols  = Math.ceil(fullW / EXPORT_TILE_SIZE);
    const rows  = Math.ceil(fullH / EXPORT_TILE_SIZE);
    return { fullWidth: fullW, fullHeight: fullH, tileSize: EXPORT_TILE_SIZE, rows, cols, dpi: EXPORT_PRINT_DPI };
  }

  function renderPrintTileCanvas(row, col) {
    const data = getFinalData();
    const { fullWidth, fullHeight } = printManifest();
    const tileW = Math.min(EXPORT_TILE_SIZE, fullWidth - col * EXPORT_TILE_SIZE);
    const tileH = Math.min(EXPORT_TILE_SIZE, fullHeight - row * EXPORT_TILE_SIZE);
    const off = document.createElement('canvas');
    off.width = tileW; off.height = tileH;
    const offCtx = off.getContext('2d');
    offCtx.translate(-col * EXPORT_TILE_SIZE, -row * EXPORT_TILE_SIZE);
    renderStrokes(offCtx, data, fullWidth, fullHeight);
    return off;
  }

  async function exportHD() {
    const canvas = renderHDCanvas(EXPORT_HD_WIDTH);
    console.log(`degenerative — exporting HD PNG (${canvas.width}×${canvas.height}px)...`);
    await downloadCanvas(canvas, `degenerative-p${paintingIdx}-w${week}-${canvas.width}px.png`);
    console.log('degenerative — HD export complete.');
  }

  // ── Zero-dependency PNG encoder ────────────────────────────────────────────
  // Just enough of the PNG spec to write one image: signature + IHDR + IDAT
  // (optionally split across chunks, which the spec explicitly allows — kept
  // small here for compatibility with naive readers) + IEND. Compression is
  // the browser's own zlib deflate (PNG's IDAT payload *is* a zlib stream —
  // no format translation needed), and the CRC-32 in each chunk footer is the
  // same algorithm as the ZIP writer above, so `crc32` is shared verbatim.

  async function deflateZlib(bytes) {
    const cs = new CompressionStream('deflate');
    const writer = cs.writable.getWriter();
    const reader = cs.readable.getReader();

    const chunks = [];
    let total = 0;
    const readAll = (async () => {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        chunks.push(value);
        total += value.length;
      }
    })();

    const STEP = 8 * 1024 * 1024; // write in slices so the reader can drain concurrently
    for (let i = 0; i < bytes.length; i += STEP) {
      await writer.write(bytes.subarray(i, i + STEP));
    }
    await writer.close();
    await readAll;

    const out = new Uint8Array(total);
    let pos = 0;
    for (const c of chunks) { out.set(c, pos); pos += c.length; }
    return out;
  }

  function pngChunk(type, data) {
    const chunk = new Uint8Array(8 + data.length + 4);
    const view = new DataView(chunk.buffer);
    view.setUint32(0, data.length, false);
    chunk.set(new TextEncoder().encode(type), 4);
    chunk.set(data, 8);
    view.setUint32(8 + data.length, crc32(chunk.subarray(4, 8 + data.length)), false);
    return chunk;
  }

  function encodePNG(width, height, idatBytes) {
    const sig = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);

    const ihdrData = new Uint8Array(13);
    const ihdrView = new DataView(ihdrData.buffer);
    ihdrView.setUint32(0, width, false);
    ihdrView.setUint32(4, height, false);
    ihdrData[8] = 8;  // bit depth
    ihdrData[9] = 2;  // color type: truecolor (RGB, no alpha — the render always fills an opaque white background)
    ihdrData[10] = 0; // compression method (only value defined by the spec)
    ihdrData[11] = 0; // filter method (only value defined by the spec)
    ihdrData[12] = 0; // interlace: none

    const parts = [sig, pngChunk('IHDR', ihdrData)];
    const IDAT_CHUNK_MAX = 1 << 20; // ~1MB per chunk, for max reader compatibility
    for (let i = 0; i < idatBytes.length; i += IDAT_CHUNK_MAX) {
      parts.push(pngChunk('IDAT', idatBytes.subarray(i, i + IDAT_CHUNK_MAX)));
    }
    parts.push(pngChunk('IEND', new Uint8Array(0)));

    const total = parts.reduce((s, p) => s + p.length, 0);
    const out = new Uint8Array(total);
    let pos = 0;
    for (const p of parts) { out.set(p, pos); pos += p.length; }
    return out;
  }

  // Renders every print tile (each a safely small canvas, as before), but
  // instead of downloading them individually, copies each tile's raw pixels
  // directly into one full-resolution scanline buffer (filter byte + RGB per
  // row, i.e. already in the shape PNG's IDAT wants) and encodes that to a
  // single PNG client-side. No canvas ever holds the full print resolution —
  // only a plain typed array does, which has no canvas-style dimension cap.
  // Pure compositing + encoding, no download/DOM side effects — shared by the
  // 'p' hotkey (below) and the native-app data-URL API (bottom of file), same
  // split as renderHDCanvas/exportHD.
  async function buildPrintPNGBytes(onProgress) {
    const { fullWidth, fullHeight, rows, cols } = printManifest();
    const totalTiles = rows * cols;

    const rowBytes = fullWidth * 3 + 1; // 1 filter byte + RGB per pixel
    const raw = new Uint8Array(rowBytes * fullHeight); // filter bytes default to 0 (None)

    let tileNum = 0;
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const off = renderPrintTileCanvas(r, c);
        const offCtx = off.getContext('2d');
        const { data, width: tw, height: th } = offCtx.getImageData(0, 0, off.width, off.height);
        const x0 = c * EXPORT_TILE_SIZE;
        const y0 = r * EXPORT_TILE_SIZE;

        for (let y = 0; y < th; y++) {
          const srcRow = y * tw * 4;
          const dstRow = (y0 + y) * rowBytes + 1 + x0 * 3;
          for (let x = 0; x < tw; x++) {
            const s = srcRow + x * 4, d = dstRow + x * 3;
            raw[d] = data[s]; raw[d + 1] = data[s + 1]; raw[d + 2] = data[s + 2];
          }
        }

        tileNum++;
        if (onProgress) onProgress(tileNum, totalTiles);
        await sleep(0); // yield to the event loop between tiles
      }
    }

    const idat = await deflateZlib(raw);
    return { bytes: encodePNG(fullWidth, fullHeight, idat), fullWidth, fullHeight };
  }

  async function exportPrintStitched() {
    const stamp = `degenerative-p${paintingIdx}-w${week}`;

    showToast('Stitching a print-quality PNG in the browser…\nThis can take a little while for large prints.');
    console.log(`degenerative — stitching a single ${EXPORT_PRINT_DPI}dpi print PNG in-browser...`);

    const { bytes, fullWidth, fullHeight } = await buildPrintPNGBytes((tileNum, totalTiles) => {
      console.log(`degenerative — tile ${tileNum}/${totalTiles} composited`);
    });

    console.log(`degenerative — compressed. downloading ${fullWidth}×${fullHeight}px PNG...`);
    const filename = `${stamp}-${fullWidth}x${fullHeight}.png`;
    await downloadBlob(new Blob([bytes], { type: 'image/png' }), filename);

    console.log(`degenerative — print export complete: single ${fullWidth}×${fullHeight}px PNG downloaded (${filename}), stitched entirely in-browser.`);
  }

  // Fallback for browsers without CompressionStream, or if the in-browser
  // stitch fails (e.g. the device can't spare a few hundred MB for the full
  // composite) — same output resolution, reassembled outside the browser.
  async function exportPrintTiles() {
    const { fullWidth, fullHeight, rows, cols } = printManifest();
    const stamp = `degenerative-p${paintingIdx}-w${week}`;

    console.log(
      `degenerative — exporting ${EXPORT_PRINT_DPI}dpi print PNG ` +
      `(${fullWidth}×${fullHeight}px, ${rows * cols} tiles). ` +
      `Your browser may ask permission to download multiple files — allow it and press 'p' again if it stops partway.`
    );
    showToast('Exporting print-quality tiles…\nSee the browser console for stitching instructions.');

    const manifest = { ...printManifest(), tiles: [] };

    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const off = renderPrintTileCanvas(r, c);
        const file = `${stamp}-tile-r${r}-c${c}.png`;
        manifest.tiles.push({ row: r, col: c, x: c * EXPORT_TILE_SIZE, y: r * EXPORT_TILE_SIZE, width: off.width, height: off.height, file });
        await downloadCanvas(off, file);
        await sleep(350); // space out downloads so browsers don't throttle/block them
      }
    }

    downloadBlob(new Blob([JSON.stringify(manifest, null, 2)], { type: 'application/json' }), `${stamp}-manifest.json`);
    await sleep(350);
    downloadStitchTool();

    console.log(`degenerative — print export complete: ${rows * cols} tiles + manifest + stitch tool downloaded.`);
    console.log(`degenerative — to assemble: unzip degenerative-stitch-tool.zip, npm install, then:`);
    console.log(`degenerative —   node stitch-print-tiles.mjs <folder with the downloaded tiles> ${stamp}`);
  }

  async function exportPrint() {
    if (typeof CompressionStream === 'function') {
      try {
        await exportPrintStitched();
        return;
      } catch (err) {
        console.warn('degenerative — in-browser PNG stitching failed, falling back to tiled export:', err);
      }
    } else {
      console.log('degenerative — this browser lacks CompressionStream, falling back to tiled export.');
    }
    await exportPrintTiles();
  }

  window.addEventListener('keydown', (e) => {
    if (e.key === 's' || e.key === 'S') exportHD();
    if (e.key === 'p' || e.key === 'P') exportPrint();
  });

  // ── External export API (native apps, e.g. the iOS companion) ────────────
  // Read-only rendering entry points — no downloads/DOM side effects, safe
  // to call via WKWebView's evaluateJavaScript. Not used by the web page
  // itself (that still goes through the keyboard shortcuts above).
  window.degenerativeExportHDDataURL = function (width) {
    return renderHDCanvas(width).toDataURL('image/png');
  };
  window.degenerativeExportManifest = function () {
    return JSON.stringify(printManifest());
  };
  window.degenerativeExportTileDataURL = function (row, col) {
    return renderPrintTileCanvas(row, col).toDataURL('image/png');
  };
  // Same in-browser stitch as the 'p' hotkey, but returns the single
  // full-resolution PNG as a data URL instead of triggering a download —
  // callers on an unsupported browser should keep using the manifest/tile
  // API above and composite natively instead (as the iOS app already does).
  window.degenerativeExportPrintPNGDataURL = async function () {
    if (typeof CompressionStream !== 'function') {
      throw new Error('CompressionStream unsupported — use degenerativeExportManifest/TileDataURL instead');
    }
    const { bytes } = await buildPrintPNGBytes();
    let binary = '';
    const CHUNK = 0x8000;
    for (let i = 0; i < bytes.length; i += CHUNK) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK));
    }
    return 'data:image/png;base64,' + btoa(binary);
  };
})();