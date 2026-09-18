let seed = parseInt(tokenData.hash.slice(0, 16), 16);  // ADD FOR LIVE NET

let r;
let maxdim;
let fs = new Array(3);

let bgcolor = 96;
let bgdir = -1;

let dead = false;
let checkForDeath = true;
let zombie = false;
let now;
let death;

let numElements = 0;
let strokeDim = 1;

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  colorMode(HSB, 360, 100, 100);
  pixelDensity(pixelDensity());
  maxdim = max(width, height);
  
  if (maxdim >= 1440) {
    strokeDim = map(maxdim, 1440, 3160, 1.5, 4.0);
  } else {
    strokeDim = map(maxdim, 300, 1440, 0.2, 1.5);
  }

  numElements = 700;
  
  death = new Date(2052, 9, 20, 23, 44, 0, 0);
  
  strokeWeight(strokeDim);
  
  r = new RND();

  now = Date.now();
  imdead();
  newFields();
  if (dead) {
    instantDeath();
  }
}

function draw() {
  if (checkForDeath && !zombie) {
    now = Date.now();
    imdead();
  }
  if (dead) {
    bgcolor -= 0.1;
    if (bgcolor < 10) {
      bgcolor = 10;
    }
  }
  background(0, 0, bgcolor);
  fs[0].display();
  fs[1].display();
  fs[2].display();
}

function imdead() {
  let diff = now - death;
  if (diff > 0) {
    dead = true;
  } else {
    dead = false;
  }
}

function instantDeath() {
  bgcolor = 10;
  noLoop();
}

function revive() {
  dead = false;
  zombie = true;
  bgcolor = 96;
  bgdir = -1;
  fs[0].revive();
  fs[1].revive();
  fs[2].revive();
}

function keyPressed() {
  if (key == ' ') {
    bgcolor += 5 * bgdir;
    if (bgcolor >= 100 || bgcolor <= 0) {
      bgdir *= -1;
    }
  } else if (key == 'n' || key == 'N') {
    newFields();
  } else if (key == 'd' || key == 'D') {
    print(now - death);
  } 
  if (dead) {
    if (key == 'r' || key == 'R') {
      revive();
      loop();
    }
  }
}

function newFields() {
  let ang1 = r.rb(0, TWO_PI);
  let ang2 = ang1 + r.rb(-QUARTER_PI/3, QUARTER_PI/3);
  let ang3 = ang1 + r.rb(-QUARTER_PI/3, QUARTER_PI/3);
  let d1 = new FieldData(ang1);
  let d2 = new FieldData(ang2);
  let d3 = new FieldData(ang3);
  fs[0] = new Field(d1);
  fs[1] = new Field(d2);
  fs[2] = new Field(d3);
}

class FieldData {
  constructor(angle) {
    this.angle = angle;
    this.color1 = r.rb(0, 360);
    this.color2 = r.rb(0, 360);
    this.whichPalette = r.rb(0, 1);
    this.speed = r.rb(-0.0005, 0.0005);
    this.density = r.rb(0.1, 0.4);
    this.densityTest = new Array(numElements);
    for (let i = 0; i < this.densityTest.length; i++) {
      this.densityTest[i] = r.rb(0, 1);
    }
  }
}

class Element {
  constructor(_x1, _y1, _x2, _y2, _h, _s, _b, _sp) {
    this.x1 = _x1;
    this.y1 = _y1;
    this.x2 = _x2;
    this.y2 = _y2;
    this.off = 0.0;
    this.h = _h;
    this.s = _s;
    this.b = _b;
    this.supress = _sp;
    this.deadSaturation = this.s;
    this.startSaturation = this.s;
    this.jit = 1.0;
    if (dead) {
      this.jit = 0.0;
      this.deadSaturation = 0.0;
    }
  }
  
  revive() {
    this.jit = 1.0;
    this.deadSaturation = this.startSaturation;
  }

  jitter() {
    if (dead) {
      this.jit -= 0.001;
      if (this.jit <= 0) {
        this.jit = 0;
      }
    }
    this.off = r.rb(-this.jit, this.jit);
  }

  display() {
    if (dead) {
      this.deadSaturation -= 0.1;
      if (this.deadSaturation <= 0) {
        this.deadSaturation = 0;
      }
    }
    if (!this.supress) {
      if (dead) {
        stroke(this.h, this.deadSaturation, this.b);
      } else {
        stroke(this.h, this.s, this.b);
      }
      line(this.x1 + this.off, this.y1, this.x2 + this.off, this.y2);
    }
  }
}

class Field {
  constructor(fd) {
    this.num = numElements;
    this.angle = fd.angle;
    this.speed = fd.speed;
    this.density = fd.density;
    this.densityTest = fd.densityTest;
    this.whichPalette = fd.whichPalette;
    this.color1 = fd.color1;
    this.color2 = fd.color2;
    this.count = 0;
    this.elements = [this.num];
    this.show = true;
    this.pnums = [];
    this.rndColor = 0;
    this.createColor();
    let index = 0;
    for (let i = 0; i < numElements; i++) {
      let tx = map(i, 0, numElements - 1, -maxdim, maxdim); // ALT
      let h = this.pnums[index];
      let s = this.pnums[index + 1];
      let b = this.pnums[index + 2];
      this.elements[i] = new Element(
        tx,
        -maxdim,
        tx,
        maxdim,
        h,
        s,
        b,
        this.show
      );
      index += 3;
      if (this.densityTest[i] > this.density) {
        this.show = false;
      } else {
        this.show = true;
      }
    }
  }
  
  revive() {
    for (let i = 0; i < numElements; i++) {
      this.elements[i].revive(); 
    }
  }

  display() {
    push();
    rotate(this.angle);
    for (let i = 0; i < numElements; i++) {
      this.elements[i].jitter();
      this.elements[i].display();
    }
    if (!dead) {
      this.angle += this.speed;
    }
    pop();
  }

  createColor() {
    if (this.whichPalette > 0.66) {
      this.rndColor = 1;
    } else {
      this.rndColor = 0;
    }
    this.createPalette();
  }
  
  createPalette() {
    let index = 0;
    let start = this.color1;
    let microStart = this.color2;
    for (let x = 0; x < numElements; x++) {
      if (this.rndColor == 0) {
        let xx = map(x, 0, numElements, 0, 720);
        let h = map(x, 0, numElements, start, (start + xx) % 360);
        let s = map(x, 0, numElements, 30, 90);
        let b = 85;
        this.pnums[index] = h;
        this.pnums[index + 1] = s;
        this.pnums[index + 2] = b;
        index += 3;
      } else if (this.rndColor == 1) {
        let stop = start + map(x, 0, numElements, 0, 360);
        if (stop > 360) {
          stop = stop - 360;
        }
        this.pnums[index] = stop;
        this.pnums[index + 1] = map(x, 0, numElements, 30, 90);
        this.pnums[index + 2] = 85;
        index += 3;
      }
    }
  }
}

class RND {
  constructor() {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substr(0, 8), 16);
      let b = parseInt(uint128Hex.substr(8, 8), 16);
      let c = parseInt(uint128Hex.substr(16, 8), 16);
      let d = parseInt(uint128Hex.substr(24, 8), 16);
      return function () {
        a |= 0; b |= 0; c |= 0; d |= 0;
        let t = (((a + b) | 0) + d) | 0;
        d = (d + 1) | 0;
        a = b ^ (b >>> 9);
        b = (c + (c << 3)) | 0;
        c = (c << 21) | (c >>> 11);
        c = (c + t) | 0;
        return (t >>> 0) / 4294967296;
      };
    };
    this.prngA = new sfc32(tokenData.hash.substr(2, 32));
    this.prngB = new sfc32(tokenData.hash.substr(34, 32));
    for (let i = 0; i < 1e6; i += 2) {
      this.prngA();
      this.prngB();
    }
  }
  random_dec() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  rb(a, b) {
    return a + (b - a) * this.random_dec();
  }
}