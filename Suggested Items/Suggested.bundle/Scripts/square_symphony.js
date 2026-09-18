// CC BY-NC-SA 4.0
let R;
let objs = [];
let minSideLength;
let palettes = [
  ["#E12A2A", "#F0871D", "#2E3F93", "#E1ECF4", "#882585", "#de5d5d", "#289D4D"],
  [
    "#fcff4b",
    "#ffad05",
    "#fdfffa",
    "#5995ed",
    "#4ecdc4",
    "#F30100",
    "#70d6ff",
    "#ff70a6",
  ],
  ["#de183c", "#ffd35c", "#fd4a8e", "#08a9e5", "#7209b7", "#f0f0f0", "#f5822a"],
  [
    "#e4572e",
    "#17bebb",
    "#ffc914",
    "#76b041",
    "#05569b",
    "#5594d0",
    "#fffef4",
    "#b00000",
  ],
];
let colors = [];
let bgCol;
let spd = 1;
let offset = 0;
let objCount;
let rects = [];
let paletteOption;
let spdOption;
let offsetOption;
let gridOption;
let backgroundOption;

function setup() {
  createCanvas(windowWidth, windowHeight);
  rectMode(CENTER);
  R = new Random();
  colors = R.random_choice(palettes);

  if (R.random_dec() < 0.3) {
    spd = R.random_dec() < 0.5 ? 0.5 : 2;
  }
  if (R.random_dec() < 0.5) {
    gridOption = true;
  } else {
    gridOption = false;
  }

  if (R.random_dec() < 0.4) {
    offsetOption = true;
  } else {
    offsetOption = false;
  }

  if (R.random_dec() < 0.7) {
    bgCol = "#121212";
    backgroundOption = "Black";
  } else {
    bgCol = "#0b0f30";
    backgroundOption = "Navy";
  }

  INIT();

  if (palettes[0] == colors) {
    paletteOption = "Forest";
  } else if (palettes[1] == colors) {
    paletteOption = "Seaside";
  } else if (palettes[2] == colors) {
    paletteOption = "Bubblegum";
  } else if (palettes[3] == colors) {
    paletteOption = "Firecracker";
  }

  if (spd == 1) {
    spdOption = "Middle";
  } else if (spd < 1) {
    spdOption = "Low";
  } else {
    spdOption = "High";
  }

  console.log("ColorPalette", paletteOption);
  console.log("Speed", spdOption);
  console.log("Offset", offsetOption);
  console.log("Grid", gridOption);
  console.log("Background", backgroundOption);
}

function draw() {
  background(0);
  fill(bgCol);
  noStroke();
  rect(width / 2, height / 2, minSideLength);
  for (let i of objs) {
    i.run();
  }
  drawGrid(gridOption);
}

function drawGrid(bl) {
  if (bl) {
    noFill();
    stroke(255);
    strokeWeight(minSideLength * 0.001);
    for (let i of rects) {
      let x = i[0];
      let y = i[1];
      let w = i[2];
      square(x + w / 2, y + w / 2, w);
    }
  }
}

function divideSquare() {
  R = new Random();
  let gridCount = int(R.random_num(20, 33));
  let gridW = minSideLength / gridCount;
  let gridH = minSideLength / gridCount;
  let emp = gridCount * gridCount;
  let grids = [];

  for (let j = 0; j < gridCount; j++) {
    let arr = [];
    for (let i = 0; i < gridCount; i++) {
      arr[i] = false;
    }
    grids[j] = arr;
  }

  while (emp > 0) {
    let w = int(R.random_num(1, 5));
    let h = w;
    let x = int(R.random_num(0, gridCount - w + 1));
    let y = int(R.random_num(0, gridCount - h + 1));
    let lap = true;
    for (let j = 0; j < h; j++) {
      for (let i = 0; i < w; i++) {
        if (grids[x + i][y + j]) {
          lap = false;
          break;
        }
      }
    }

    if (lap) {
      for (let j = 0; j < h; j++) {
        for (let i = 0; i < w; i++) {
          grids[x + i][y + j] = true;
        }
      }
      let xx = x * gridW + (width - minSideLength) / 2;
      let yy = y * gridH + (height - minSideLength) / 2;
      let ww = w * gridW;
      let hh = h * gridH;
      rects.push([xx, yy, ww - offset, hh - offset]);
      emp -= w * h;
    }
  }
  for (let i = 0; i < rects.length; i++) {
    objCount++;
    objs.push(new Objct(rects[i][0], rects[i][1], rects[i][2]));
  }
}

function easeInOutExpo(x) {
  return x === 0
    ? 0
    : x === 1
    ? 1
    : x < 0.5
    ? Math.pow(2, 20 * x - 10) / 2
    : (2 - Math.pow(2, -20 * x + 10)) / 2;
}

function INIT() {
  objs = [];
  rects = [];
  minSideLength = min(width, height) * 0.95;
  objCount = 0;
  if (offsetOption) {
    offset = minSideLength * 0.008;
  }
  divideSquare();
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  INIT();
}

class Objct {
  constructor(x, y, w) {
    let rnd = int(R.random_num(0, 8) + 1);
    if (rnd == 1) this.mtn = new Motion01(x + w / 2, y + w / 2, w);
    else if (rnd == 2) this.mtn = new Motion02(x + w / 2, y + w / 2, w);
    else if (rnd == 3) this.mtn = new Motion03(x + w / 2, y + w / 2, w);
    else if (rnd == 4) this.mtn = new Motion04(x + w / 2, y + w / 2, w);
    else if (rnd == 5) this.mtn = new Motion05(x + w / 2, y + w / 2, w);
    else if (rnd == 6) this.mtn = new Motion06(x + w / 2, y + w / 2, w);
    else if (rnd == 7) this.mtn = new Motion07(x + w / 2, y + w / 2, w);
    else if (rnd == 8) this.mtn = new Motion08(x + w / 2, y + w / 2, w);
  }

  run() {
    this.mtn.show();
    this.mtn.move();
  }
}

class Motion01 {
  constructor(x, y, w) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.n = int(R.random_num(3, 8));
    this.sw = w / this.n;
    this.t = -int(R.random_num(0, 10));
    this.t1 = int(R.random_num(50, 120));
    this.tStep = R.random_num(0.5, 1) * spd;
    this.soc = int(R.random_num(0, 2));
    this.ang = int(R.random_num(0, 4)) * (TAU / 4);
    this.col1 = this.col2 = 0;
    while (this.col1 == this.col2) {
      this.col1 = R.random_choice(colors);
      this.col2 = R.random_choice(colors);
    }
  }

  show() {
    push();
    translate(this.x, this.y);
    rotate(this.ang);
    noFill();
    strokeWeight(0);
    strokeCap(SQUARE);
    rect(0, 0, this.w);
    drawingContext.setLineDash([this.w / this.n, this.w / this.n]);
    strokeWeight(this.sw);
    stroke(this.col2);

    for (let i = 0; i < this.n; i++) {
      let yy = map(
        i,
        0,
        this.n - 1,
        -this.w / 2 + this.sw / 2,
        this.w / 2 - this.sw / 2
      );
      let zr = this.soc * ((i % 2) * this.sw);
      drawingContext.lineDashOffset = zr + this.t * 0.5;
      line(-this.w / 2, yy, this.w / 2, yy);
    }
    pop();
  }

  move() {
    this.t += this.tStep;
  }
}

class Motion02 extends Motion01 {
  constructor(x, y, w) {
    super(x, y, w);
    this.cx = 0;
    this.cd = w * 0.5;
  }

  show() {
    push();
    translate(this.x, this.y);
    rotate(this.ang);
    noFill();
    stroke(0);
    strokeWeight(0);
    rect(0, 0, this.w);
    drawingContext.clip();
    noStroke();
    fill(this.col2);
    circle(this.cx, 0, this.cd);
    circle(this.cx - this.w, 0, this.cd);
    pop();
  }

  move() {
    this.t += this.tStep;
    if (0 < this.t && this.t < this.t1) {
      let nrm = norm(this.t, 0, this.t1 - 1);
      this.cx = lerp(0, this.w, easeInOutExpo(nrm));
    }
    if (this.t > this.t1) {
      this.t = 0;
      this.cx = 0;
    }
  }
}

class Motion03 extends Motion01 {
  constructor(x, y, w) {
    super(x, y, w);
    this.t2 = this.t1 + 50;
    this.d = this.w * 0.3;
    this.sd = this.d;
    this.sd0 = this.d;
    this.sd1 = this.d * 4.5;
    this.sw = this.d;
  }

  show() {
    push();
    translate(this.x, this.y);
    rotate(this.ang);
    noFill();
    stroke(0);
    strokeWeight(0);
    rect(0, 0, this.w);
    drawingContext.clip();
    noStroke();
    fill(this.col2);
    circle(0, 0, this.d);
    if (this.t < this.t1) {
      noFill();
      stroke(this.col2);
      strokeWeight(this.sw);
      circle(0, 0, this.sd - this.sw);
    }
    pop();
  }

  move() {
    if (0 < this.t && this.t < this.t1) {
      let nrm = norm(this.t, 0, this.t1);
      this.sd = lerp(this.sd0, this.sd1, easeInOutExpo(nrm));
      this.sw = lerp(this.d, 0, nrm);
    }
    if (this.t > this.t2) {
      this.t = 0;
      this.sd = this.sd0;
    }
    this.t += this.tStep;
  }
}

class Motion04 extends Motion01 {
  constructor(x, y, w) {
    super(x, y, w);
    this.d = this.w * 0.3;
    this.rad = this.w * 0.3;
    this.circles = [];
    this.cNum = 6;
    for (let i = 0; i < this.cNum; i++) {
      this.circles.push({
        a: 0,
        d: map(i, 0, this.cNum - 1, this.d, this.d * 0.2),
      });
    }
    this.t1 = int(R.random_num(120, 200));
    this.cols = [];
    for (let i = 0; i < colors.length; i++) {
      this.cols.push(colors[i]);
    }
    shuffle(this.cols, true);
  }

  show() {
    push();
    translate(this.x, this.y);
    rotate(this.ang);
    noStroke();
    fill(this.col1);
    for (let c of this.circles) {
      circle(this.rad * cos(c.a), this.rad * sin(c.a), c.d);
    }
    pop();
  }

  move() {
    if (0 < this.t && this.t < this.t1) {
      let nrm = norm(this.t, 0, this.t1);
      for (let i = 0; i < this.cNum; i++) {
        let c = this.circles[i];
        c.a = lerp(
          0,
          TAU,
          pow(easeInOutExpo(nrm), map(i, 0, this.cNum - 1, 0.7, 5))
        );
      }
    }
    if (this.t > this.t1) {
      this.t = 0;
      for (let i = 0; i < this.cNum; i++) {
        let c = this.circles[i];
        c.a = 0;
      }
    }
    this.t += this.tStep;
  }
}

class Motion05 extends Motion01 {
  constructor(x, y, w) {
    super(x, y, w);
    this.cells = [];
    this.size = this.w / this.n;
    this.tmp = R.random_num(0.02, 0.05);
    let cols = [];
    for (let i = 0; i < colors.length; i++) {
      cols.push(colors[i]);
    }
    for (let i = 0; i < this.n; i++) {
      for (let j = 0; j < this.n; j++) {
        let x = i * this.size + this.x - this.w / 2;
        let y = j * this.size + this.y - this.w / 2;
        this.cells.push({
          x: x,
          y: y,
          c: R.random_choice(cols),
          t: int(R.random_num(0, 1000)),
        });
      }
    }
    this.rnd = int(R.random_num(0, 2));
  }

  show() {
    noStroke();
    for (let i of this.cells) {
      fill(i.c);
      if (this.rnd == 0)
        circle(
          i.x + this.size / 2,
          i.y + this.size / 2,
          this.size * sin(this.t * this.tmp + i.t) * 0.75
        );
      else
        square(
          i.x + this.size / 2,
          i.y + this.size / 2,
          this.size * sin(this.t * this.tmp + i.t) * 0.75
        );
    }
  }
}

class Motion06 extends Motion01 {
  constructor(x, y, w) {
    super(x, y, w);
    this.wt = int(R.random_num(1, 5));
    this.cols = [];
    for (let i = 0; i < colors.length; i++) {
      this.cols.push(colors[i]);
    }
    shuffle(this.cols, true);
  }

  show() {
    let amp = this.w / this.n;
    push();
    translate(this.x, this.y);
    rotate(this.ang);
    strokeWeight(0);
    stroke(0);
    noFill();
    rect(0, 0, this.w);
    drawingContext.clip();
    noFill();
    strokeWeight(this.w * 0.02);
    for (let j = -1; j < this.n + 1; j++) {
      let yy = map(j, 0, this.n, -this.w / 2, this.w / 2);
      stroke(this.cols[floor((j + 1) % this.cols.length)]);
      beginShape();
      for (let i = -1; i <= this.w + 1; i++) {
        let xx = i - this.w / 2;
        let n = norm(i, 0, this.w);
        vertex(xx, yy + amp * sin(n * this.wt * PI + this.t * 0.1));
      }
      endShape();
    }
    pop();
  }
}

class Motion07 extends Motion01 {
  constructor(x, y, w) {
    super(x, y, w);
    this.ex = 0;
    this.ey = 0;
    this.ew = this.w * 0.2;
    this.rnd = 1000;
    this.init();
  }

  init() {
    this.t1 = int(R.random_num(40, 100));
    this.prnd = this.rnd;
    while (this.rnd == this.prnd) {
      this.rnd = int(R.random_num(0, 6));
    }
    this.ex0 = this.ex;
    this.ey0 = this.ey;
    if (this.rnd == 0) {
      this.ex1 = 0;
      this.ey1 = 0;
    } else if (this.rnd == 1) {
      this.ex1 = this.ew * 0.3;
      this.ey1 = 0;
    } else if (this.rnd == 2) {
      this.ex1 = -this.ew * 0.3;
      this.ey1 = 0;
    } else if (this.rnd == 3) {
      this.ex1 = 0;
      this.ey1 = this.ew * 0.3;
    } else if (this.rnd == 4) {
      this.ex1 = 0;
      this.ey1 = -this.ew * 0.3;
    } else if (this.rnd == 5) {
      this.ex1 = this.ex0;
      this.ey1 = this.ey0;
    }
  }

  show() {
    push();
    translate(this.x, this.y);
    rotate(this.ang);
    noStroke();
    fill(this.col1);
    circle(this.w * 0.28, 0, this.w * 0.35);
    circle(-this.w * 0.28, 0, this.w * 0.35);
    fill(this.col2);
    circle(this.w * 0.28 + this.ex, this.ey, this.ew);
    circle(-this.w * 0.28 + this.ex, this.ey, this.ew);
    if (this.rnd == 5) {
      fill(bgCol);
      rect(0, -this.w * 0.3 + this.tn, this.w, -0 + this.tn * 2);
    }
    pop();
  }

  move() {
    this.t += this.tStep;
    if (0 < this.t && this.t < this.t1) {
      let nrm = norm(this.t, 0, this.t1 - 1);
      this.ex = lerp(this.ex0, this.ex1, easeInOutExpo(nrm));
      this.ey = lerp(this.ey0, this.ey1, easeInOutExpo(nrm));
      if (this.rnd == 5)
        this.tn = lerp(0, this.w * 0.3, sin(easeInOutExpo(nrm) * PI));
    }
    if (this.t > this.t1) {
      this.t = 0;
      this.init();
    }
  }
}

class Motion08 extends Motion01 {
  constructor(x, y, w) {
    super(x, y, w);
    this.rad = this.w * 0.35;
    this.pom = R.random_dec() < 0.5 ? -1 : 1;
  }

  show() {
    push();
    translate(this.x, this.y);
    rotate(this.ang);
    fill(this.col1);
    for (let i = 0; i < 12; i++) {
      let a = map(i, 0, 12, 0, TAU);
      circle(this.rad * cos(a), this.rad * sin(a), this.w * 0.05);
    }
    let a = this.t * 0.02 * this.pom;
    stroke(this.col2);
    strokeWeight(this.w * 0.04);
    line(0, 0, this.rad * cos(a), this.rad * sin(a));
    line(
      0,
      0,
      this.w * 0.2 * cos(a / TAU / 2),
      this.w * 0.2 * sin(a / TAU / 2)
    );
    pop();
  }
}

class Random {
  constructor() {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substr(0, 8), 16);
      let b = parseInt(uint128Hex.substr(8, 8), 16);
      let c = parseInt(uint128Hex.substr(16, 8), 16);
      let d = parseInt(uint128Hex.substr(24, 8), 16);
      return function () {
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
    // seed prngA with first half of tokenData.hash
    this.prngA = new sfc32(tokenData.hash.substr(2, 32));
    // seed prngB with second half of tokenData.hash
    this.prngB = new sfc32(tokenData.hash.substr(34, 32));
    for (let i = 0; i < 1e6; i += 2) {
      this.prngA();
      this.prngB();
    }
  }
  // random number between 0 (inclusive) and 1 (exclusive)
  random_dec() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  // random number between a (inclusive) and b (exclusive)
  random_num(a, b) {
    return a + (b - a) * this.random_dec();
  }
  // random integer between a (inclusive) and b (inclusive)
  // requires a < b for proper probability distribution
  random_int(a, b) {
    return Math.floor(this.random_num(a, b + 1));
  }
  // random boolean with p as percent liklihood of true
  random_bool(p) {
    return this.random_dec() < p;
  }
  // random value in an array of items
  random_choice(list) {
    return list[this.random_int(0, list.length - 1)];
  }
}