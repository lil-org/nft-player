let tokenId = tokenData.tokenId;
tokenData = tokenData.hash;
let R, w, h, m, col, row, rw, rh, rad;
let colors, newarr, harmony, ha, har;
let h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11, hues, index, bh, bh2, bh3;
let wt, g, bk;
let pg;

function setup() {
	w = window.innerWidth;
	h = window.innerHeight;
	if (h/w > 1.5) {
		h = 1.5 * w;
		createCanvas(w, h);
	} else {
		w = h/1.5;
		createCanvas(w, h);
	}
	m = w/12;
	colorMode(HSB);
	rectMode(CORNER);
	smooth();
	pixelDensity(2);
	R = new Random();
	col = R.random_int(1, 4);
	row = R.random_int(1, 6 - col);
	if (col == 1) {
		row = R.random_int(3, 6);
	}
	if (col == 2) {
		row = R.random_int(2, 4);
	}
	if (col == 3 && row == 3) {
		col = 4;
		row = 6;
	}
	rw = (w - (col + 1) * m)/col;
	rh = (h - (row + 1) * m)/row;
	rad = Math.min(rw, rh)/2;
	h1 = color(0, 93, 99);
	h2 = color(15, 94, 100);
	h3 = color(30, 95, 100);
	h4 = color(45, 97, 100);
	h5 = color(60, 100, 100);
	h6 = color(182, 62, 92);
	h7 = color(194, 72, 92);
	h8 = color(204, 81, 91);
	h9 = color(214, 76, 82);
	h10 = color(229, 71, 72);
	h11 = color(115, 72, 74);
	wt = color(200, 0, 100);
	g = color(330, 1, 65);
	bk = color(345, 11, 14);
	background(wt);
	fill(wt);
	stroke(bk);
	strokeWeight(m/2.04);
	colors = [];
	har = [1, 1, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 6];
	ha = har[R.random_int(0, har.length - 1)];
	hues = [h1, h2, h3, h4, h5, h6, h7, h8, h9, h10];
	if (ha == 1) {
		hues = [h1, h2, h3, h4, h5, h6, h7, h8, h9, h10, h11];
	}
	index = R.random_int(0, hues.length - 1);
	bh = hues[index];
	if (ha == 1) {
		colors.push(bh);
		harmony = [bh, g, wt];
	}
	if (ha == 2) {
		if (index < 5) {
			bh = h1;
			bh2 = h3;
			bh3 = h5;
		} else {
			bh = h6;
			bh2 = h8;
			bh3 = h10;
		}
		colors.push(bh);
		colors.push(bh2);
		colors.push(bh3);
		harmony = [bh, bh2, bh3, g, wt];
	}
	if (ha == 3) {
		if (index < 5) {
			bh2 = hues[index + 5];
		} else {
			bh2 = hues[index - 5];
		}
		colors.push(bh);
		colors.push(bh2);
		harmony = [bh, bh2, g, wt];
	}
	if (ha == 4) {
		if (index < 5 ) {
			index = R.random_int(1, 3);
			bh = hues[index];
			bh2 = hues[index + 4];
			bh3 = hues[index + 6];
			colors.push(bh);
			colors.push(bh2);
			colors.push(bh3);
		}	else {
			index = R.random_int(6, 8);
			bh = hues[index];
			bh2 = hues[index - 4];
			bh3 = hues[index - 6];
			colors.push(bh);
			colors.push(bh2);
			colors.push(bh3);
		}
		harmony = [bh, bh2, bh3, g, wt];
	}
	if (ha == 5) {
		harmony = [h1, h3, h5, h6, h8, h10, h11, g, wt];
	}
	if (ha == 6) {
		harmony = [g, wt];
	}
	let l = colors.length;
	for (let i = 0; i < row * col - l; i++) {
		colors.push(harmony[R.random_int(0, harmony.length - 1)]);
	}
	let newarr = [];
  	l = colors.length;
  	for (let i = 0; i < l; i++) {
  		let choice = R.random_int(0, colors.length - 1);
    	newarr.push(colors[choice]);
    	colors.splice(choice, 1);
  	}
  	colors = newarr;
}

function draw() {
	for (let j = 0; j < col; j++) {
		for (let i = 0; i < row; i++) {
			let x = m + (((w - (col + 1) * m)/col) + m) * j;
			let y = m + (((h - (row + 1) * m)/row) + m) * i;
			fill(colors[i + (j * row)]);
			if (row/col == 1.5) {
				circle(x + rw/2, y + rh/2, rw);
			} else {
				rect(x, y, rw, rh, rad);
			}
		}
	}
	noLoop();
}

function keyTyped() {
  if (key === 's') {
		w = 4800;
		h = 7200;
		m = w/12;
		rw = (w - (col + 1) * m)/col;
		rh = (h - (row + 1) * m)/row;
		rad = Math.min(rw, rh)/2;
		strokeWeight(m/2.04);
		resizeCanvas(w, h, true);
		background(wt);
		redraw();
		saveCanvas(tokenId, 'png');
		setup();
		redraw();
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