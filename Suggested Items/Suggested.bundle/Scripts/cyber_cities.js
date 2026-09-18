
let seed = parseInt(tokenData.hash.slice(0, 16), 16);

class Palette {
  constructor(colors, repeat=3) {
    this.c = colors;
    this.repeat = repeat;
    this.i = 0;
    this.u = 0;
  }
  increment() {
    if (this.i === this.c.length-1) {
      this.i = 0;
    } else {
      this.i += 1;
    }
  }
  usage() {
    if (this.u % this.repeat === 0) {
      this.increment();
    }
    this.u += 1;
  }
  color() {
    this.usage();
    return this.c[this.i];
  }
}

class Ship {
  constructor() {
    this.objects = [];
    this.dyn = false;
    this.push = 0;
    this.speed = 0;
  }
  draw() {
    for (let o of this.objects) {
      if (this.dyn) {
        this.push = this.push+this.speed;
        push();
        translate(this.push, 0);
      }
      fill(o.c);
      stroke("#000003");
      strokeWeight(o.sw);
      rect(o.x, o.y, o.xs, o.ys);
      if (this.dyn) {
        pop();
        if (this.push > DIM) {
          this.push = -1*DIM*2;
        }
      }
    }
  }
}

var DEFAULT_SIZE = 1000;
var WIDTH = window.innerWidth;
var HEIGHT = window.innerHeight;
var DIM = Math.min(WIDTH, HEIGHT);
var M = DIM / DEFAULT_SIZE;

var PALS = [["#F72585", "#B5179E", "#7209B7", "#4361EE", "#4361EE", "#4895EF", "#4CC9F0"],
["#FF184C", "#FF184C", "#0A9CF5"],
["#E92EFB", "#FF2079", "#440BD4", "#04005E"],
["#08F7FE", "#09FBD3", "#FE53BB", "#F5D300"],
["#D9EB4B", "#00A9FE", "#FD6BB6", "#EF0888"],
["#3B27BA", "#E847AE", "#13CA91", "#FF9472"],
["#E96D5E", "#EEEEEE", "#FFE69D", "#6A7E6A", "#393F5F"],
["#63345E", "#FD8090", "#B7C1DE", "#06569C", "#092047"]];

var PAL_C = rnd_choice([0,1,1,2,2,2,3,3,3,4,4,4,5,5,5,6,6,6,7,7,7]);
var PAL = PALS[PAL_C];
var REP = rnd_choice([2,3,3,3,3,4,5,6,7,8,9,10,15,20,30,50,100]);
var P1 = new Palette(PAL, REP);
var max_h = rnd_between(10, 50)*M;
var max_w = rnd_between(10, 50)*M;
var dyn_true = rnd_between(0, 1) > 0.5;
var dyn_thresh = rnd_between(0.5, 1);
var Ships = [];

function setup() {
  createCanvas(DIM, DIM);
  background("#000003");
  frameRate(30);
  rr(0, 0, DIM, DIM);
  for (let ship of Ships) {
    ship.draw();
  }
}

function draw() {
  background("#000003");
  for (let ship of Ships) {
    ship.draw();
  }
}

function rr(x, y, w, h) {
  if (rnd_between(0, 0.55) > 0.5) {
    rect_partition(x, y, x+w, y+h);
  }
  let sw = rnd_between(0, 0.7) > 0.5;
  let sl = rnd_between(0.1, 0.8);
  if (sw && w > max_w) {
    rr(x, y, w * sl, h);
    rr(x + (w * sl), y, w * (1 - sl), h);
  } else if (h > max_h) {
    rr(x, y, w, h * sl);
    rr(x, y + (h * sl), w, h * (1 - sl));
  }
}
function rescale(e, t, r, i, a) {
  return ((e - t) / (r - t)) * (a - i) + i;
}
function range(start, stop, step) {
    var a = [start], b = start;
    while (b < stop) {
        a.push(b += step || 1);
    }
    return (b > stop) ? a.slice(0,-1) : a;
}
function rect_partition(x1, y1, x2, y2) {
  let ship = new Ship();
  let sw = rnd_between(1, 15)*M;
  let dyn = rnd_choice([false,true,true]);
  let step = 15*M;
  let breaks = range(x1, x2, step).slice(rnd_between(1,5));
  ship.objects.push({x:x1, y:y1, xs:(x2-x1), ys:(y2-y1), c:P1.color(), sw:sw, dyn:dyn, tl:0});
  let height = y2-y1;
  for (let xm of breaks) {
    ship.objects.push({x:x1, y:y1, xs:(xm-x1), ys:(y2-y1), c:P1.color(), sw:sw, dyn:dyn, tl:0});
    x1 = xm;
  }
  if (height < 25*M && sw < 5*M && dyn_true && rnd_between(0, 1) < dyn_thresh) {
    ship.dyn = true;
    ship.speed = (1-rescale(height, 0, 25*M, 0.7, 0.9))*M;
  }
  Ships.push(ship);
}
function rnd_dec() {
  seed ^= seed << 13
  seed ^= seed >> 17
  seed ^= seed << 5
  return ((seed < 0 ? ~seed + 1 : seed) % 1000) / 1000
}
function rnd_between(a, b) {
  return a + (b - a) * rnd_dec()
}
function rnd_choice(choices) {
  return choices[Math.floor(rnd_between(0, choices.length * 0.99))]
}