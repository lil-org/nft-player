let tokenId = tokenData.tokenId;
tokenData = tokenData.hash;
let R, w, h, grid, u, margin;
let heights, rows, rh, wh1, wh2, s, b, n, y, divider, dividers;
let h1, h2, h3, h4, h5, h6, p1, p2, p3, p4, p5, p6, rindex, cr, crows, ftemp, f, harmony, anything, c;

function setup() {
  colorMode(HSB);
  R = new Random();
  w = window.innerWidth;
  h = window.innerHeight;
  if (w / h > 4 / 5) {
    w = 4 / 5 * h;
  } else {
    h = 5 / 4 * w;
  }
  createCanvas(w, h);
  grid = 64;
  u = h / (grid + 16);
  margin = h / 10;
  heights = [1, 2, 3, 4, 6, 8, 12];
  rows = [];
  dividers = [];
  wh1 = 345;
  wh2 = 55;
  s = 53;
  b = 98;
  n = 0;
  y = 0;
  c = 0;
  while (n < grid) {
    rh = heights[R.random_int(0, heights.length - 1)];
    if (n + rh < grid) {
      rows.push(rh);
      dividers.push(Math.pow(2, R.random_int(0, Math.log2(grid) - 2)));
    } else {
      rh = grid - n;
      rows.push(rh);
      dividers.push(Math.pow(2, R.random_int(0, Math.log2(grid) - 2)));
    }
    n = n + rh;
  }
  rindex = [];
  for (let i = 0; i < rows.length; i++) {
    rindex.push(i);
  }
  rindex = scramble(rindex);
  if (R.random_bool(5 / 100)) {
    harmony = "Monochromatic";
  } else {
    if (R.random_bool(10 / 95)) {
      harmony = "Anything Goes";
    } else {
      if (R.random_bool(20 / 85)) {
        harmony = "Complementary";
      } else {
        harmony = "Analogous";
      }
    }
  }
  cr = R.random_int(3, Math.max(3, Math.floor(rows.length / 2.7)));
  if (harmony == "Complementary") {
    cr = cr - 1;
  }
  if (harmony == "Monochromatic") {
    cr = cr - 2;
  }
  crows = [];
  for (let i = 0; i < cr; i++) {
    crows.push(rindex[i]);
  }
  crows.sort((a, b) => a - b);
  h1 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  h2 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  h3 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  h4 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  h5 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  h6 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  while (abs(((h2 + 20) % 360) - ((h1 + 20) % 360)) < ((360 - wh1) + wh2) / 2) {
    h2 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  }
  while (abs(((h3 + 20) % 360) - ((h2 + 20) % 360)) < ((360 - wh1) + wh2) / 2) {
    h3 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  }
  while (abs(((h4 + 20) % 360) - ((h3 + 20) % 360)) < ((360 - wh1) + wh2) / 2) {
    h4 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  }
  while (abs(((h5 + 20) % 360) - ((h4 + 20) % 360)) < ((360 - wh1) + wh2) / 2) {
    h5 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  }
  while (abs(((h6 + 20) % 360) - ((h5 + 20) % 360)) < ((360 - wh1) + wh2) / 2) {
    h6 = (R.random_int(0, (360 - wh1) + wh2) + wh1) % 360;
  }
  if (R.random_bool(0.5)) {
    h1 = (h1 + 180) % 360;
    h2 = (h2 + 180) % 360;
  }
  if (harmony == "Anything Goes") {
    if (R.random_bool(0.5)) {
      h1 = (h1 + 180) % 360;
    }
    if (R.random_bool(0.5)) {
      h2 = (h2 + 180) % 360;
    }
    if (R.random_bool(0.5)) {
      h3 = (h3 + 180) % 360;
    }
    if (R.random_bool(0.5)) {
      h4 = (h4 + 180) % 360;
    }
    if (R.random_bool(0.5)) {
      h5 = (h5 + 180) % 360;
    }
    if (R.random_bool(0.5)) {
      h6 = (h6 + 180) % 360;
    }
  }
  p1 = color(h1, s, b);
  p2 = color(h2, s, b);
  p3 = color(h3, s, b);
  p4 = color(h4, s, b);
  p5 = color(h5, s, b);
  p6 = color(h6, s, b);
  if (harmony == "Complementary") {
    p2 = color((h1 + 180) % 360, s, b);
  }
  anything = [p1, p2, p3, p4, p5, p6];
}

function draw() {
  background(0, 0, 100);
  noFill();
  stroke(0, 0, 15);
  strokeWeight(u / 10);
  for (let i = 0; i < rows.length; i++) {
    divider = dividers[i];
    if (crows.includes(i)) {
      if (cr > 1) {
        colorMode(RGB);
        ftemp = lerpColor(p1, p2, crows.indexOf(i) / (cr - 1));
        colorMode(HSB);
        f = color(hue(ftemp), s, b);
        if (harmony == "Monochromatic") {
          f = p1;
        }
        if (harmony == "Complementary" && i % 2 == 1) {
          f = p1;
        }
        if (harmony == "Complementary" && i % 2 == 0) {
          f = p2;
        }
        if (harmony == "Complementary" && crows.indexOf(i) == 0) {
          f = p1;
        }
        if (harmony == "Complementary" && crows.indexOf(i) == cr - 1) {
          f = p2;
        }
        if (harmony == "Anything Goes") {
          f = anything[c % anything.length];
          c++;
        }
      } else {
        f = p1;
      }
      fill(f);
    }
    for (let j = 0; j < 3 * grid / (4 * divider); j++) {
      rect((j * u * divider) + margin, y * u + margin, u * divider, rows[i] * u);
    }
    y = y + rows[i];
    noFill();
  }
  noLoop();
}

function scramble(arr) {
  let newarr = [];
  let length = arr.length;
  for (let i = 0; i < length; i++) {
    let choice = R.random_int(0, arr.length - 1);
    newarr.push(arr[choice]);
    arr.splice(choice, 1);
  }
  return (newarr);
}

function keyTyped() {
  if (key === 's') {
    let d = 2;
    pixelDensity(d);
    w = 24 * 300/d;
    h = 30 * 300/d;
    u = h / (grid + 16);
    margin = h / 10;
    y = 0;
    c = 0;
    resizeCanvas(w, h, true);
    redraw();
    saveCanvas(tokenId, 'png');
    setup();
    redraw();
  }
}

class Random {
  constructor() {
    this.useA = false;
    let sfc32 = function(uint128Hex) {
      let a = parseInt(uint128Hex.substr(0, 8), 16);
      let b = parseInt(uint128Hex.substr(8, 8), 16);
      let c = parseInt(uint128Hex.substr(16, 8), 16);
      let d = parseInt(uint128Hex.substr(24, 8), 16);
      return function() {
        a |= 0;
        b |= 0;
        c |= 0;
        d |= 0;
        let t = (((a + b) | 0) + d) | 0;
        d = (d + 1) | 0;
        a = b ^ (b >>> 9);
        b = (c + (c << 3)) | 0;
        c = (c << 21) | (c >>> 11);
        c = (c + t) | 0;
        return (t >>> 0) / 4294967296;
      };
    };
    this.prngA = new sfc32(tokenData.substr(2, 32));
    this.prngB = new sfc32(tokenData.substr(34, 32));
    for (let i = 0; i < 1e6; i += 2) {
      this.prngA();
      this.prngB();
    }
  }
  random_dec() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  random_num(a, b) {
    return a + (b - a) * this.random_dec();
  }
  random_int(a, b) {
    return Math.floor(this.random_num(a, b + 1));
  }
  random_bool(p) {
    return this.random_dec() < p;
  }
  random_choice(list) {
    return list[this.random_int(0, list.length - 1)];
  }
}