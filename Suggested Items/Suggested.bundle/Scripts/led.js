tokenData = tokenData.hash

let R, w, h, sd, g, u, r, c, cr;
let h1, h2, h3, h4, hues, p1, p2, p3, p4;

function setup() {
	R = new Random();
	w = window.innerWidth;
	h = window.innerHeight;
	sd = Math.min(w, h);
	g = 12 * R.random_int(3, 25);
	u = sd/g;
	r = Math.floor(h/u);
	c = Math.floor(w/u);
	cr = R.random_int(0, 1);
	colorMode(HSB);
	h1 = h2 = h3 = h4 = 0;
	h1 = R.random_num(0, 59);
	h2 = R.random_num(60, 179);
	h3 = R.random_num(180, 239);
	h4 = R.random_num(240, 359);
	hues = [h1, h2, h3, h4];
	hues = scramble(hues);
	p1 = color(hues[0], 100, 100);
	p2 = color(hues[1], 100, 100);
	p3 = color(hues[2], 100, 100);
	p4 = color(hues[3], 100, 100);
	createCanvas(w, h);
	rectMode(CENTER);
	noStroke();
	colorMode(RGB);
}

function draw() {
	background(0, 0, 0);
	push();
	translate((w - ((c + 1) * u))/2, (h - ((r + 1) * u))/2);
	if (cr == 1) {
		r = Math.floor(r * 1.155);
	}
	for (let j = 0; j < r + 1; j++) {
		for (let i = 0; i < c + 1; i++) {
			let a = lerpColor(p1, p2, i/c);
			let b = lerpColor(p4, p3, i/c);
			if (i % 3 == 0) {
				fill(color(red(lerpColor(a, b, j/r)), 0, 0));
				stroke(color(red(lerpColor(a, b, j/r)), 0, 0));
			}
			if (i % 3 == 1) {
				fill(color(0, green(lerpColor(a, b, j/r)), 0));
				stroke(color(0, green(lerpColor(a, b, j/r)), 0));
			}
			if (i % 3 == 2) {
				fill(color(0, 0, blue(lerpColor(a, b, j/r))));
				stroke(color(0, 0, blue(lerpColor(a, b, j/r))));
			}
			if (cr == 0) {
				strokeWeight(1);
				square((i * u) + u/2, (j * u) + u/2, u);
			} else {
				noStroke();
				if (j % 2 == 0) {
					circle((i * u) + u/2, (j * u) + u/2 - j * (u - (u/2 * sqrt(3))), u);
				} else {
					circle((i * u) + u, (j * u) + u/2 - j * (u - (u/2 * sqrt(3))), u);
				}
			}
		}
	}
	pop();
	noLoop();
}

function scramble(arr) {
	let newarr = [];
	let length = arr.length;
	for (let i = 0; i < length; i++) {
		let choice = Math.floor(map(R.random_dec(), 0, 1, 0, arr.length));
		newarr.push(arr[choice]);
		arr.splice(choice, 1);
	}
	return(newarr);
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