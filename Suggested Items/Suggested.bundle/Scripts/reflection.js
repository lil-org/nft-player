tokenData = tokenData.hash;
let hashPairs = [];
for (let i = 0; i < 32; i++) {
  let hex = tokenData.slice((2 * i) + 2, (2 * i) + 4);
  hashPairs[i] = parseInt(hex, 16);
}
let col, row, frame, curve, sa, sb, sc, sd, ha, hb, hc, hd, ra, rb, rc, rd, s, rotation;
let w, h, smalldim, m, c, t, ta, tb, tc, td, x, y;
let ca, cb, cc, cd;

function setup() {
  w = window.innerWidth;
  h = window.innerHeight;
  smalldim = Math.floor(Math.min(w, h));
  createCanvas(w, h, WEBGL);
  background(0);
  noStroke();
  smooth();
  colorMode(HSB);
  rectMode(CORNER);
  angleMode(DEGREES);
  col = Math.floor(map(hashPairs[1], 0, 255, 1, 7));
  row = Math.floor(map(hashPairs[2], 0, 255, 1, 7));
  frame = Math.floor(map(hashPairs[3], 0, 255, 2, 4.999999999));
  curve = Math.floor(map(hashPairs[4], 0, 255, 0, 10.999999999)) / 10;
  sa = map(hashPairs[5], 0, 255, 1, 6);
  sb = map(hashPairs[6], 0, 255, 1, 6);
  sc = map(hashPairs[7], 0, 255, 1, 6);
  sd = map(hashPairs[8], 0, 255, 1, 6);
  ha = map(hashPairs[9], 0, 255, 0, 360);
  hb = map(hashPairs[10], 0, 255, 0, 360);
  hc = map(hashPairs[11], 0, 255, 0, 360);
  hd = map(hashPairs[12], 0, 255, 0, 360);
  rotation = Math.floor(map(hashPairs[13], 0, 255, 0, 3.999999999));
}

function draw() {
  m = frame * smalldim / 80;
  c = curve * (Math.min((w - m) / (2 * col), (h - m) / (2 * row)) - m / 2);
  t = millis() / 350
  ta = sa * t;
  tb = sb * t;
  tc = sc * t;
  td = sd * t;
  s = 100;
  if (hashPairs[19] > 217) {
    s = 55;
  }
  ca = color((ha + ta) % 360, s, 100);
  cb = color((hb + tb) % 360, s, 100);
  cc = color((hc + tc) % 360, s, 100);
  cd = color((hd + td) % 360, s, 100);
  if (hashPairs[14] > 127) {
    ca = color(360 - ((ha + ta) % 360), s, 100);
  }
  if (hashPairs[15] > 127) {
    cb = color(360 - ((hb + tb) % 360), s, 100);
  }
  if (hashPairs[16] > 127) {
    cc = color(360 - ((hc + tc) % 360), s, 100);
  }
  if (hashPairs[17] > 127) {
    cd = color(360 - ((hd + td) % 360), s, 100);
  }
  if (hashPairs[18] > 237) {
    cd = cc = cb = ca;
  } else if (hashPairs[18] > 205) {
    cb = ca;
    cd = cc = color((hue(ca) + 180) % 360, s, 100);
  } else if (hashPairs[18] > 160) {
    cb = ca;
    cd = cc;
  } else if (hashPairs[18] > 102) {
    ca = color((ha + (7 * t)) % 360, s, 100);
    if (hashPairs[14] > 127) {
      ca = color(360 - ((ha + (7 * t)) % 360), s, 100);
    }
    cb = color((hue(ca) + 45) % 360, s, 100);
    cc = color((hc + (7 * t)) % 360, s, 100);
    if (hashPairs[14] > 127) {
      cc = color(360 - ((hc + (7 * t)) % 360), s, 100);
    }
    cd = color((hue(cc) + 45) % 360, s, 100);
  }
  beginShape();
  if (rotation == 0) {
    fill(ca);
    vertex(-w / 2 + m / 2 + 1, -h / 2 + m / 2 + 1);
    fill(cb);
    vertex(w / 2 - m / 2 - 1, -h / 2 + m / 2 + 1);
    fill(cc);
    vertex(w / 2 - m / 2 - 1, h / 2 - m / 2 - 1);
    fill(cd);
    vertex(-w / 2 + m / 2 + 1, h / 2 - m / 2 - 1);
  } else if (rotation == 1) {
    fill(ca);
    vertex(w / 2 - m / 2 - 1, -h / 2 + m / 2 + 1);
    fill(cb);
    vertex(w / 2 - m / 2 - 1, h / 2 - m / 2 - 1);
    fill(cc);
    vertex(-w / 2 + m / 2 + 1, h / 2 - m / 2 - 1);
    fill(cd);
    vertex(-w / 2 + m / 2 + 1, -h / 2 + m / 2 + 1);
  } else if (rotation == 2) {
    fill(ca);
    vertex(w / 2 - m / 2 - 1, h / 2 - m / 2 - 1);
    fill(cb);
    vertex(-w / 2 + m / 2 + 1, h / 2 - m / 2 - 1);
    fill(cc);
    vertex(-w / 2 + m / 2 + 1, -h / 2 + m / 2 + 1);
    fill(cd);
    vertex(w / 2 - m / 2 - 1, -h / 2 + m / 2 + 1);
  } else {
    fill(ca);
    vertex(-w / 2 + m / 2 + 1, h / 2 - m / 2 - 1);
    fill(cb);
    vertex(-w / 2 + m / 2 + 1, -h / 2 + m / 2 + 1);
    fill(cc);
    vertex(w / 2 - m / 2 - 1, -h / 2 + m / 2 + 1);
    fill(cd);
    vertex(w / 2 - m / 2 - 1, h / 2 - m / 2 - 1);
  }
  endShape();
  fill(0);
  x = -w / 2 + m / 2;
  y = -h / 2 + m / 2;
  for (let j = 0; j < row; j++) {
    for (let i = 0; i < col; i++) {
      x = -w / 2 + m / 2 + i * (w / col - m / col);
      y = -h / 2 + m / 2 + j * (h / row - m / row);
      push();
      aframe(x, y);
      x = -w / 2 + m / 2 + (i + 1) * (w / col - m / col);
      y = -h / 2 + m / 2 + j * (h / row - m / row);
      bframe(x, y);
      rotate(180);
      x = -w / 2 + m / 2 + i * (w / col - m / col);
      y = -h / 2 + m / 2 + j * (h / row - m / row);
      aframe(x, y);
      x = -w / 2 + m / 2 + (i + 1) * (w / col - m / col);
      y = -h / 2 + m / 2 + j * (h / row - m / row);
      bframe(x, y);
      pop();
    }
  }
}

function aframe(x, y) {
  beginShape();
  vertex(x, y);
  vertex(x + (w - m) / (2 * col), y);
  vertex(x + (w - m) / (2 * col), y + m / 2);
  quadraticVertex(x + m / 2, y + m / 2, x + m / 2 + c, y + m / 2);
  quadraticVertex(x + m / 2, y + m / 2, x + m / 2, y + m / 2 + c);
  vertex(x + m / 2, y + (h - m) / (2 * row));
  vertex(x, y + (h - m) / (2 * row));
  endShape(CLOSE);
}

function bframe(x, y) {
  beginShape();
  vertex(x, y);
  vertex(x - (w - m) / (2 * col), y);
  vertex(x - (w - m) / (2 * col), y + m / 2);
  quadraticVertex(x - m / 2, y + m / 2, x - (m / 2 + c), y + m / 2);
  quadraticVertex(x - m / 2, y + m / 2, x - m / 2, y + m / 2 + c);
  vertex(x - m / 2, y + (h - m) / (2 * row));
  vertex(x, y + (h - m) / (2 * row));
  endShape(CLOSE);
}