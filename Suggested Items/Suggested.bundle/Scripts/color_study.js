tokenData = tokenData.hash;
let hashPairs = [];
for (let i = 0; i < 32; i++) {
	let hex = tokenData.slice((2 * i) + 2, (2 * i) + 4);
	hashPairs[i] = parseInt(hex, 16);
}
let seed = parseInt(tokenData.slice(36, 52), 16);
let smalldim;
let divs = [3, 4, 4, 5, 5, 6, 6, 6, 8, 8, 8, 10, 10, 10, 12, 12, 12, 15, 15, 15, 20, 20, 20, 24, 24, 24, 30, 30, 30, 40, 40, 60, 60, 120];
let hdiv, vdiv, w, h;
let ra, ga, ba;
let rb, gb, bb;
let rc, gc, bc;
let rd, gd, bd;
let r, g, b;
let albers, rndcolor, complementary, blackcorner, tinted, saturated, secondchance, hline, vline, squares, circles = false;
let corner;

function setup() {
	smalldim = Math.floor(Math.min(window.innerWidth, window.innerHeight));
	createCanvas(smalldim, smalldim);
	colorMode(RGB);
	background(255);
	noFill();
	noStroke();
}

function draw() {
	hdiv = divs[floor(map(hashPairs[0], 0, 255, 0, divs.length - .0000000001))];
	vdiv = divs[floor(map(hashPairs[1], 0, 255, 0, divs.length - .0000000001))];
	if (hdiv == 3 || hdiv == 4) {
		vdiv = divs[floor(map(hashPairs[1], 0, 255, 8, divs.length - .0000000001))];
	}
	if (vdiv == 3 || vdiv == 4) {
		hdiv = divs[floor(map(hashPairs[0], 0, 255, 8, divs.length - .0000000001))];
	}
	w = smalldim / hdiv;
	h = smalldim / vdiv;
	ra = hashPairs[2];
	ga = hashPairs[3];
	ba = hashPairs[4];
	rb = hashPairs[5];
	gb = hashPairs[6];
	bb = hashPairs[7];
	rc = hashPairs[8];
	gc = hashPairs[9];
	bc = hashPairs[10];
	rd = hashPairs[11];
	gd = hashPairs[12];
	bd = hashPairs[13];
	if (ra < 64 && ga < 64 && ba < 64) {
		let ea = easeblack(color(ra, ga, ba));
		ra = red(ea);
		ga = green(ea);
		ba = blue(ea);
	}
	if (rb < 64 && gb < 64 && bb < 64) {
		let eb = easeblack(color(rb, gb, bb));
		rb = red(eb);
		gb = green(eb);
		bb = blue(eb);
	}
	if (rc < 64 && gc < 64 && bc < 64) {
		let ec = easeblack(color(rc, gc, bc));
		rc = red(ec);
		gc = green(ec);
		bc = blue(ec);
	}
	if (rd < 64 && gd < 64 && bd < 64) {
		let ed = easeblack(color(rd, gd, bd));
		rd = red(ed);
		gd = green(ed);
		bd = blue(ed);
	}
	for (let i = 0; i < 61; i++) {
		let hexquad = tokenData.slice(i + 2, i + 6);
		if (hexquad == 'a1be' || hexquad == 'a1b3') {
			albers = true;
		}
	}
	if (hashPairs[14] > 250 && !albers) {
		rndcolor = true;
	}
	if (hashPairs[14] > 244 && !rndcolor && !albers) {
		complementary = true;
	}
	if (hashPairs[15] > 248 && !rndcolor && !albers) {
		blackcorner = true;
	}
	if (hashPairs[15] > 225 && !blackcorner && !rndcolor && !albers) {
		tinted = true;
	}
	if (hashPairs[15] > 202 && !tinted && !blackcorner && !rndcolor && !albers) {
		saturated = true;
	}
	if (complementary) {
		let ha = hue(color(ra, ga, ba));
		let cha = ha + 180;
		if (cha > 359) {
			cha = ha - 180;
		}
		let ma = pushhue(color(ra, ga, ba), ha);
		ra = red(ma);
		ga = green(ma);
		ba = blue(ma);
		let mb = pushhue(color(rb, gb, bb), cha);
		rb = red(mb);
		gb = green(mb);
		bb = blue(mb);
		let mc = pushhue(color(rc, gc, bc), cha);
		rc = red(mc);
		gc = green(mc);
		bc = blue(mc);
		let md = pushhue(color(rd, gd, bd), ha);
		rd = red(ma);
		gd = green(ma);
		bd = blue(ma);
	}
	if (blackcorner) {
		corner = floor(map(hashPairs[16], 0, 255, 1, 4.9999999999))
		if (corner == 1) {
			ra = ga = ba = 0
		};
		if (corner == 2) {
			rb = gb = bb = 0
		};
		if (corner == 3) {
			rc = gc = bc = 0
		};
		if (corner == 4) {
			rd = gd = bd = 0
		};
	}
	if (tinted) {
		let ta = lighten(color(ra, ga, ba));
		ra = red(ta);
		ga = green(ta);
		ba = blue(ta);
		let tb = lighten(color(rb, gb, bb));
		rb = red(tb);
		gb = green(tb);
		bb = blue(tb);
		let tc = lighten(color(rc, gc, bc));
		rc = red(tc);
		gc = green(tc);
		bc = blue(tc);
		let td = lighten(color(rd, gd, bd));
		rd = red(td);
		gd = green(td);
		bd = blue(td);
	}
	if (saturated) {
		let sa = saturate(color(ra, ga, ba));
		ra = red(sa);
		ga = green(sa);
		ba = blue(sa);
		let sb = saturate(color(rb, gb, bb));
		rb = red(sb);
		gb = green(sb);
		bb = blue(sb);
		let sc = saturate(color(rc, gc, bc));
		rc = red(sc);
		gc = green(sc);
		bc = blue(sc);
		let sd = saturate(color(rd, gd, bd));
		rd = red(sd);
		gd = green(sd);
		bd = blue(sd);
	}
	let rdif = Math.max(ra, rb, rc, rd) - Math.min(ra, rb, rc, rd);
	let gdif = Math.max(ga, gb, gc, gd) - Math.min(ga, gb, gc, gd);
	let bdif = Math.max(ba, bb, bc, bd) - Math.min(ba, bb, bc, bd);
	let rgbdif = rdif + gdif + bdif;
	let ha = hue(color(ra, ga, ba));
	let hb = hue(color(rb, gb, bb));
	let hc = hue(color(rc, gc, bc));
	let hd = hue(color(rd, gd, bd));
	let hamod = ha;
	let hbmod = hb;
	let hcmod = hc;
	let hdmod = hd;
	if (ha < 180) {
		hamod = ha + 360;
	}
	if (hb < 180) {
		hbmod = hb + 360;
	}
	if (hc < 180) {
		hcmod = hc + 360;
	}
	if (hd < 180) {
		hdmod = hd + 360;
	}
	let hdif = Math.max(ha, hb, hc, hd) - Math.min(ha, hb, hc, hd);
	let hmoddif = Math.max(hamod, hbmod, hcmod, hdmod) - Math.min(hamod, hbmod, hcmod, hdmod);
	if (((rgbdif < 200) && !rndcolor) || (((hdif < 70) || (hmoddif < 60)) && (tinted || saturated))) {
		secondchance = true;
	}
	if (secondchance) {
		ra = hashPairs[17];
		ga = hashPairs[18];
		ba = hashPairs[19];
		rb = hashPairs[20];
		gb = hashPairs[21];
		bb = hashPairs[22];
		rc = hashPairs[23];
		gc = hashPairs[24];
		bc = hashPairs[25];
		rd = hashPairs[26];
		gd = hashPairs[27];
		bd = hashPairs[28];
		if (complementary) {
			let ha = hue(color(ra, ga, ba));
			let cha = ha + 180;
			if (cha > 359) {
				cha = ha - 180;
			}
			let ma = pushhue(color(ra, ga, ba), ha);
			ra = red(ma);
			ga = green(ma);
			ba = blue(ma);
			let mb = pushhue(color(rb, gb, bb), cha);
			rb = red(mb);
			gb = green(mb);
			bb = blue(mb);
			let mc = pushhue(color(rc, gc, bc), cha);
			rc = red(mc);
			gc = green(mc);
			bc = blue(mc);
			let md = pushhue(color(rd, gd, bd), ha);
			rd = red(ma);
			gd = green(ma);
			bd = blue(ma);
		}
		if (blackcorner) {
			corner = floor(map(hashPairs[16], 0, 255, 1, 4.9999999999))
			if (corner == 1) {
				ra = ga = ba = 0
			};
			if (corner == 2) {
				rb = gb = bb = 0
			};
			if (corner == 3) {
				rc = gc = bc = 0
			};
			if (corner == 4) {
				rd = gd = bd = 0
			};
		}
		if (tinted) {
			let ta = lighten(color(ra, ga, ba));
			ra = red(ta);
			ga = green(ta);
			ba = blue(ta);
			let tb = lighten(color(rb, gb, bb));
			rb = red(tb);
			gb = green(tb);
			bb = blue(tb);
			let tc = lighten(color(rc, gc, bc));
			rc = red(tc);
			gc = green(tc);
			bc = blue(tc);
			let td = lighten(color(rd, gd, bd));
			rd = red(td);
			gd = green(td);
			bd = blue(td);
		}
		if (saturated) {
			let sa = saturate(color(ra, ga, ba));
			ra = red(sa);
			ga = green(sa);
			ba = blue(sa);
			let sb = saturate(color(rb, gb, bb));
			rb = red(sb);
			gb = green(sb);
			bb = blue(sb);
			let sc = saturate(color(rc, gc, bc));
			rc = red(sc);
			gc = green(sc);
			bc = blue(sc);
			let sd = saturate(color(rd, gd, bd));
			rd = red(sd);
			gd = green(sd);
			bd = blue(sd);
		}
	}
	if (hdiv == vdiv && !albers) {
		if (hashPairs[29] > 127) {
			circles = true;
		}
	}
	if (hashPairs[30] > 191 && !circles) {
		hline = true;
	}
	if (hashPairs[31] > 191 && !circles) {
		vline = true;
	}
	for (let j = 0; j < vdiv; j++) {
		for (let i = 0; i < hdiv; i++) {
			r = ((hdiv - i - 1) / (hdiv - 1)) * ((vdiv - j - 1) / (vdiv - 1)) * ra + ((i) / (hdiv - 1)) * ((vdiv - j - 1) / (vdiv - 1)) * rb + ((hdiv - i - 1) / (hdiv - 1)) * ((j) / (vdiv - 1)) * rc + ((i) / (hdiv - 1)) * ((j) / (vdiv - 1)) * rd;
			g = ((hdiv - i - 1) / (hdiv - 1)) * ((vdiv - j - 1) / (vdiv - 1)) * ga + ((i) / (hdiv - 1)) * ((vdiv - j - 1) / (vdiv - 1)) * gb + ((hdiv - i - 1) / (hdiv - 1)) * ((j) / (vdiv - 1)) * gc + ((i) / (hdiv - 1)) * ((j) / (vdiv - 1)) * gd;
			b = ((hdiv - i - 1) / (hdiv - 1)) * ((vdiv - j - 1) / (vdiv - 1)) * ba + ((i) / (hdiv - 1)) * ((vdiv - j - 1) / (vdiv - 1)) * bb + ((hdiv - i - 1) / (hdiv - 1)) * ((j) / (vdiv - 1)) * bc + ((i) / (hdiv - 1)) * ((j) / (vdiv - 1)) * bd;
			if (rndcolor) {
				r = floor(map(rnd(), 0, 1, 0, 256));
				g = floor(map(rnd(), 0, 1, 0, 256));
				b = floor(map(rnd(), 0, 1, 0, 256));
			}
			fill(r, g, b);
			noStroke();
			if (circles) {
				circle(i * w + (w / 2), j * h + (h / 2), w);
			} else {
				stroke(r, g, b);
				strokeWeight(1);
				rect(i * w, j * h, w, h);
			}
		}
	}
	if (vline) {
		for (let i = 0; i < hdiv + 1; i++) {
			strokeWeight(smalldim / 300);
			stroke(255);
			line(i * w, 0, i * w, smalldim);
		}
	}
	if (hline) {
		for (let j = 0; j < vdiv + 1; j++) {
			strokeWeight(smalldim / 300);
			stroke(255);
			line(0, j * h, smalldim, j * h);
		}
	}
	if (albers) {
		for (let i = 0; i < 4; i++) {
			noStroke();
			fill(((3 - i) * ra / 3) + (i * rd / 3), ((3 - i) * ga / 3) + (i * gd / 3), ((3 - i) * ba / 3) + (i * bd / 3));
			rect(i * smalldim / 10, 3 * i * smalldim / 20, (5 - i) * smalldim / 5, (5 - i) * smalldim / 5);
		}
	}
	noLoop();
}

function easeblack(c) {
	let rc = red(c) + (.15 * (255 - red(c)));
	let gc = green(c) + (.15 * (255 - green(c)));
	let bc = blue(c) + (.15 * (255 - blue(c)));
	return color(rc, gc, bc);
}

function pushhue(c, h) {
	let sac = saturation(c) + (.4 * (100 - saturation(c)));
	let brc = brightness(c) + (.4 * (100 - brightness(c)));
	colorMode(HSB);
	let shc = color(h, sac, brc);
	colorMode(RGB);
	let rc = red(shc);
	let gc = green(shc);
	let bc = blue(shc);
	return color(rc, gc, bc);
}

function saturate(c) {
	let hc = hue(c);
	colorMode(HSB);
	let satc = color(hc, 100, 100);
	colorMode(RGB);
	let rc = red(satc);
	let gc = green(satc);
	let bc = blue(satc);
	return color(rc, gc, bc);
}

function lighten(c) {
	let hc = hue(c);
	colorMode(HSB);
	let lic = color(hc, 37, 100);
	colorMode(RGB);
	let rc = red(lic);
	let gc = green(lic);
	let bc = blue(lic);
	return color(rc, gc, bc);
}

function rnd() {
	seed ^= seed << 13;
	seed ^= seed >> 17;
	seed ^= seed << 5;
	return (((seed < 0) ? ~seed + 1 : seed) % 1000) / 1000;
}