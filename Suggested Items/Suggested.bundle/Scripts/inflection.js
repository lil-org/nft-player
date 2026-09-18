tokenData = tokenData.hash;
let hashPairs = [];
for (let i = 0; i < 32; i++) {
	let hex = tokenData.slice((2 * i) + 2, (2 * i) + 4);
	hashPairs[i] = parseInt(hex, 16);
}

let w, h, ld, sd, hp, bw, of, r, t, tr;
let h1, h2, h3, h4, h5, h6;
let s1, s2, s3, s4, s5, s6;
let c1, c2, c3, c4, c5, c6;

function setup() {
	w = window.innerWidth;
	h = window.innerHeight;
	createCanvas(w, h, WEBGL);
	background(0);
	noStroke();
	smooth();
	colorMode(HSB);
	angleMode(DEGREES);
	ld = Math.max(w, h);
	sd = Math.min(w, h);
	hp = Math.sqrt(ld ** 2 + sd ** 2)/2;
	of = map(hashPairs[2], 0, 255, 0.05, 0.1);
	bw = map(hashPairs[3], 0, 255, 0.01, (2 * of) - 0.0015);
	r = 5 * ((Math.floor(map(hashPairs[4], 0, 255, 0, 35.999999999))) - 17);
	h1 = 15 * (Math.floor(map(hashPairs[5], 0, 255, 0, 24)));
	h2 = 15 * (Math.floor(map(hashPairs[6], 0, 255, 0, 24)));
	h3 = 15 * (Math.floor(map(hashPairs[7], 0, 255, 0, 24)));
	h4 = 15 * (Math.floor(map(hashPairs[8], 0, 255, 0, 24)));
	h5 = 15 * (Math.floor(map(hashPairs[9], 0, 255, 0, 24)));
	h6 = 15 * (Math.floor(map(hashPairs[10], 0, 255, 0, 24)));
	h7 = 15 * (Math.floor(map(hashPairs[11], 0, 255, 0, 24)));
	s1 = 100 * (Math.floor(map(hashPairs[12], 0, 255, 0.9, 1.9)));
	s2 = 100 * (Math.floor(map(hashPairs[13], 0, 255, 0.9, 1.9)));
	s3 = 100 * (Math.floor(map(hashPairs[14], 0, 255, 0.9, 1.9)));
	s4 = 100 * (Math.floor(map(hashPairs[15], 0, 255, 0.9, 1.9)));
	s5 = 100 * (Math.floor(map(hashPairs[16], 0, 255, 0.9, 1.9)));
	s6 = 100 * (Math.floor(map(hashPairs[17], 0, 255, 0.9, 1.9)));
	s7 = 100 * (Math.floor(map(hashPairs[18], 0, 255, 0.9, 1.9)));
	tr = map(hashPairs[19], 0, 255, 1, 5);
}

function draw() {
	t = frameCount/(3 * tr);
	c1 = color((h1 + t) % 360, s1, 100);
	c2 = color((h2 + t) % 360, s2, 100);
	c3 = color((h3 + t) % 360, s3, 100);
	c4 = color((h4 + t) % 360, s4, 100);
	c5 = color((h5 + t) % 360, s5, 100);
	c6 = color((h6 + t) % 360, s6, 100);
	c7 = color((h7 + t) % 360, s7, 100);
	push();
	rotate(r);
	drawSegment(c1, c2, -1, -0.5);
	drawSegment(c2, c3, -0.5, -0.25);
	drawSegment(c3, c4, -0.25, 0);
	drawSegment(c4, c5, 0, 0.25);
	drawSegment(c5, c6, 0.25, 0.5);
	drawSegment(c6, c7, 0.5, 1);
	for (let i = 0; i < 10; i++) {
		let k = (2 * i) - 9;
		push();
		translate(k * of * 2 * hp, 0);
		drawBreak(bw);
		pop();
	}
	pop();
}

function drawSegment(p1, p2, a, b) {
	beginShape();
	fill(p1);
	vertex(-hp, a * hp);
	vertex(hp, a * hp);
	fill(p2);
	vertex(hp, b * hp);
	vertex(-hp, b * hp);
	endShape();
}

function drawBreak(w) {
	beginShape();
	fill(0);
	vertex(-hp * w, -hp);
	vertex(hp * w, -hp);
	vertex(hp * w, hp);
	vertex(-hp * w, hp);
	endShape();
}