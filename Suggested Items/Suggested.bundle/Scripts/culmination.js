tokenData = tokenData.hash

let R, w, h, sd, threshold, threshold1, threshold2, cap, curb1, curb2, delay, sync, syncdir, gradient, r, c, mu, m, su, s, rw, rh, rdiff, tf, t, x, y;
let bg, h1, h2, h3, h4, c1, c2, c3, c4, f1, f2, f3, f4;

function setup() {
  colorMode(HSB);
  R = new Random();
  w = window.innerWidth;
  h = window.innerHeight;
  sd = Math.min(w, h);
  createCanvas(w, h, WEBGL);
  noStroke();
  fill(0);
  threshold1 = 45;
  threshold2 = 15;
  cap = 120;
  curb1 = 70;
  curb2 = 170;
  delay = 5;
  sync = R.random_bool(0.085);
  if (R.random_bool(0.5)) {
    syncdir = "v";
  } else {
    syncdir = "h";
  }
  gradient = R.random_bool(0.5);
  if (R.random_bool(0.5)) {
    bg = 0;
  } else {
    bg = 100;
  }
  r = Math.ceil(Math.pow(2, R.random_int(0, 6)));
  c = Math.ceil(Math.pow(2, R.random_int(0, 6)));
  while ((r > 1 && r < 5) && (c > 1 && c < 5)) {
    r = Math.ceil(Math.pow(2, R.random_int(0, 6)));
    c = Math.ceil(Math.pow(2, R.random_int(0, 6)));
  }
  mu = R.random_int(0, 5);
  if ((r == 1 & c < 3) || (r < 3 & c == 1)) {
    mu = R.random_int(1, 5);
  }
  m = mu * sd / 32;
  su = R.random_int(2, 4);
  if (m > 0) {
    s = Math.min(su * Math.min((w - (2 * m)) / c, (h - (2 * m)) / r) / 8, m);
  } else {
    s = su * Math.min((w - (2 * m)) / c, (h - (2 * m)) / r) / 8;
  }
  if (mu == 0 && (r > 1 && c > 1)) {
    m = s;
  }
  if (r < 5 || c < 5) {
    gradient = true;
  }
  if (r == 1 && c == 1) {
    sync = true;
  }
  if (r == 1 && c > 4 && syncdir == "h") {
    gradient = false;
    sync = true;
  }
  if (c == 1 && r > 4 && syncdir == "v") {
    gradient = false;
    sync = true;
  }
  if (gradient && r == 1 && (c > 1 && c < 5)) {
    syncdir = "v";
    if (sync) {
      bg = 100;
    }
  }
  if (gradient && c == 1 && (r > 1 && r < 5)) {
    syncdir = "h";
    if (sync) {
      bg = 100;
    }
  }
  if (!gradient && r == 1 && c != 1) {
    syncdir = "h";
  }
  if (!gradient && c == 1 && r != 1) {
    syncdir = "v";
  }
  if (sync || r < 2 || c < 2) {
    threshold = threshold1 + threshold2;
  } else {
    threshold = threshold1;
  }
  h1 = h2 = h3 = h4 = 0;
  while (
    huediff(h1, h2) < threshold || huediff(h1, h2) > cap || 
    huediff(h1, h3) < threshold || huediff(h1, h3) > cap || 
    huediff(h2, h4) < threshold1 || huediff(h2, h4) > cap || 
    huediff(h3, h4) < threshold1 || huediff(h3, h4) > cap || 
    huediff(h1, h4) < threshold1 || huediff(h2, h3) < threshold1
  ) {
    h1 = R.random_int(curb2, curb1 + 360) % 360;
    h2 = R.random_int(curb2, curb1 + 360) % 360;
    h3 = R.random_int(curb2, curb1 + 360) % 360;
    h4 = R.random_int(curb2, curb1 + 360) % 360;
  }
  tf = 0;
  while (Math.abs(tf) < 1) {
    tf = 3 - R.random_num(0, 6);
  }
  if (sync) {
    if (syncdir == "v") {
      h2 = h1;
      h4 = h3;
    } else {
      h3 = h1;
      h4 = h2;
    }
  }
  rw = (w - 2 * m - (c - 1) * s) / c;
  rh = (h - 2 * m - (r - 1) * s) / r;
  if (r == 1 && c == 1) {
    rdiff = Math.max(rw, rh) - Math.min(rw, rh);
    rw = Math.min(rw, rh);
    rh = rw;
  }
  background(bg);
}

function draw() {
  translate(-w / 2 + m, -h / 2 + m);
  if (millis() < (delay * 1000)) {
    t = 0;
  } else {
    t = (millis() - (delay * 1000)) / 200;
  }
  c1 = color((((h1 + (t * tf)) % 360) + 360) % 360, 100, 100);
  c2 = color((((h2 + (t * tf)) % 360) + 360) % 360, 100, 100);
  c3 = color((((h3 + (t * tf)) % 360) + 360) % 360, 100, 100);
  c4 = color((((h4 + (t * tf)) % 360) + 360) % 360, 100, 100);
  c1 = color((((h1 + (t * tf)) % 360) + 360) % 360, 100, 100);
  c2 = color((((h2 + (t * tf)) % 360) + 360) % 360, 100, 100);
  c3 = color((((h3 + (t * tf)) % 360) + 360) % 360, 100, 100);
  c4 = color((((h4 + (t * tf)) % 360) + 360) % 360, 100, 100);
  if (hue(c1) > curb1 && hue(c1) < curb2) {
    c1 = curb(c1);
  }
  if (hue(c2) > curb1 && hue(c2) < curb2) {
    c2 = curb(c2);
  }
  if (hue(c3) > curb1 && hue(c3) < curb2) {
    c3 = curb(c3);
  }
  if (hue(c4) > curb1 && hue(c4) < curb2) {
    c4 = curb(c4);
  }
  if (r == 1 || c == 1 || !gradient) {
    for (let i = 0; i < r; i++) {
      for (let j = 0; j < c; j++) {
        x = j * (rw + s);
        y = i * (rh + s);
        colorMode(RGB);
        if (r == 1 && c == 1) {
          f1 = c1;
          f2 = c2;
          f3 = c3;
          f4 = c4;
        } else if (r == 1) {
          f1 = f2 = f3 = f4 = lerpColor(c1, c2, j / (c - 1));
          if (gradient) {
            f3 = f4 = lerpColor(c3, c4, j / (c - 1));
          }
        } else if (c == 1) {
          f1 = f2 = f3 = f4 = lerpColor(c1, c3, i / (r - 1));
          if (gradient) {
            f2 = f4 = lerpColor(c2, c4, i / (r - 1));
          }
        } else {
          f1 = f2 = f3 = f4 = lerpColor(lerpColor(c1, c2, j / (c - 1)), lerpColor(c3, c4, j / (c - 1)), i / (r - 1));
        }
        colorMode(HSB);
        if (r == 1 && c == 1) {
          push();
          if (sd == h) {
            translate(rdiff / 2, 0);
          } else {
            translate(0, rdiff / 2);
          }
        }
        beginShape();
        fill(f1);
        vertex(x, y);
        fill(f2);
        vertex(x + rw, y);
        fill(f4);
        vertex(x + rw, y + rh);
        fill(f3);
        vertex(x, y + rh);
        endShape(CLOSE);
        if (r == 1 && c == 1) {
          pop();
        }
      }
    }
  } else {
    for (let i = 0; i < r + 1; i++) {
      for (let j = 0; j < c + 1; j++) {
        x = j * (rw + s);
        y = i * (rh + s);
        colorMode(RGB);
        f1 = lerpColor(lerpColor(c1, c2, j / c), lerpColor(c3, c4, j / c), i / r);
        f2 = lerpColor(lerpColor(c1, c2, (j + 1) / c), lerpColor(c3, c4, (j + 1) / c), i / r);
        f3 = lerpColor(lerpColor(c1, c2, j / c), lerpColor(c3, c4, j / c), (i + 1) / r);
        f4 = lerpColor(lerpColor(c1, c2, (j + 1) / c), lerpColor(c3, c4, (j + 1) / c), (i + 1) / r);
        colorMode(HSB);
        if (i < r && j < c) {
          beginShape();
          fill(f1);
          vertex(x, y);
          fill(f2);
          vertex(x + rw, y);
          fill(f4);
          vertex(x + rw, y + rh);
          fill(f3);
          vertex(x, y + rh);
          endShape(CLOSE);
        }
      }
    }
  }
}

function curb(c) {
  let a = color(curb1, 100, 100);
  let b = color(curb2, 100, 100);
  colorMode(RGB);
  let cc = lerpColor(a, b, (hue(c) - curb1) / (curb2 - curb1));
  colorMode(HSB);
  return cc;
}

function huediff(hue1, hue2) {
  if (Math.abs(hue1 - hue2) > 180) {
    return 360 - Math.abs(hue1 - hue2);
  } else {
    return Math.abs(hue1 - hue2);
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