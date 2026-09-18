let seed = tokenData.tokenId
let unit;
let i, j;
let h1, h2, h3, h4;
let c;
let windows;
let display = false;

function setup () {
  let dim = Math.min(window.innerWidth/16, window.innerHeight/9);
  createCanvas(dim * 16, dim * 9);
  unit = width / 16;
  rectMode(CORNER);
  colorMode(HSB, 359, 100, 100, 1);
  background(0, 0, 100);
  noFill();
  noStroke();
}

function draw () {
  background(0, 0, 100);
  h1 = floor(map(rnd(), 0, 1, 0, 360));
  h2 = floor(map(rnd(), 0, 1, 0, 360));
  h3 = floor(map(rnd(), 0, 1, 0, 360));
  h4 = floor(map(rnd(), 0, 1, 0, 360));
  for (let i = 0; i < 9; i++) {
    for (let j = 0; j < 16; j++) {
      fill(h4, 100, 100, (1 - 0.066666667 * j) * (1 - 0.125 * i));
      rect((15 - j) * unit, (8 - i) * unit, unit, unit);
    }
  }
  for (let i = 0; i < 9; i++) {
    for (let j = 0; j < 16; j++) {
      fill(h3, 100, 100, (1 - 0.066666667 * j) * (1 - 0.125 * i) );
      rect(j * unit, (8 - i) * unit, unit, unit);
    }
  }
  for (let i = 0; i < 9; i++) {
    for (let j = 0; j < 16; j++) {
      fill(h2, 100, 100, (1 - 0.066666667 * j) * (1 - 0.125 * i) );
      rect((15 - j) * unit, i * unit, unit, unit);
    }
  }
  for (let i = 0; i < 9; i++) {
    for (let j = 0; j < 16; j++) {
      fill(h1, 100, 100, (1 - 0.066666667 * j) * (1 - 0.125 * i) );
      rect(j * unit, i * unit, unit, unit);
    }
  }
  c = floor(map(rnd(), 0, 1, 1, 5));
  if (c == 1) {
   fill(0, 0, 100, 0);
  }
  if (c == 2) {
   fill(240, 100, 50, 0.25);
  }
  if (c == 3) {
   fill(0, 0, 60, 0.4);
  }
  if (c == 4) {
   fill(0, 15, 100, 0.4);
  }
  rect(0, 0, width, height);
  windows = floor(map(rnd(), 0, 1, 1, 10));
  noFill();
  stroke(0, 0, 0);
  strokeWeight(unit * 0.0625);
  if (windows == 1) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, unit, 0.25 * unit);
        rect(j * unit, i * unit + 0.25 * unit, unit, 0.75 * unit);
      }
    }
  }
  if (windows == 2) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, unit, 0.25 * unit);
        rect(j * unit, i * unit + 0.25 * unit, unit, 0.5 * unit);
        rect(j * unit, i * unit + 0.75 * unit, unit, 0.25 * unit);
      }
    }
  }
  if (windows == 3) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, unit, 0.25 * unit);
        rect(j * unit, i * unit + 0.25 * unit, 0.5 * unit, 0.75 * unit);
        rect(j * unit + 0.5 * unit, i * unit + 0.25 * unit, 0.5 * unit, 0.75 * unit);
      }
    }
  }
  if (windows == 4) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, unit, 0.25 * unit);
        rect(j * unit, i * unit + 0.25 * unit, 0.5 * unit, 0.5 * unit);
        rect(j * unit + 0.5 * unit, i * unit + 0.25 * unit, 0.5 * unit, 0.5 * unit);
        rect(j * unit, i * unit + 0.75 * unit, unit, 0.25 * unit);
      }
    }
  }
  if (windows == 5) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, 0.25 * unit, unit);
        rect(j * unit + 0.25 * unit, i * unit, 0.5 * unit, unit);
        rect(j * unit + 0.75 * unit, i * unit, 0.25 * unit, unit);
      }
    }
  }
  if (windows == 6) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, unit, 0.25 * unit);
        rect(j * unit, i * unit + 0.25 * unit, 0.25 * unit, 0.75 * unit);
        rect(j * unit + 0.25 * unit, i * unit + 0.25 * unit, 0.5 * unit, 0.75 * unit);
        rect(j * unit + 0.75 * unit, i * unit + 0.25 * unit, 0.25 * unit, 0.75 * unit);
      }
    }
  }
  if (windows == 7) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, 0.25 * unit, unit);
        rect(j * unit + 0.25 * unit, i * unit, 0.5 * unit, 0.5 * unit);
        rect(j * unit + 0.25 * unit, i * unit + 0.5 * unit, 0.5 * unit, 0.5 * unit);
        rect(j * unit + 0.75 * unit, i * unit, 0.25 * unit, unit);
      }
    }
  }
  if (windows == 8) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, 0.25 * unit, unit);
        rect(j * unit + 0.25 * unit, i * unit, 0.5 * unit, 0.25 * unit);
        rect(j * unit + 0.25 * unit, i * unit + 0.25 * unit, 0.5 * unit, 0.5 * unit);
        rect(j * unit + 0.25 * unit, i * unit + 0.75 * unit, 0.5 * unit, 0.25 * unit);
        rect(j * unit + 0.75 * unit, i * unit, 0.25 * unit, unit);
      }
    }
  }
  if (windows == 9) {
    for (let i = 0; i < 9; i++) {
      for (let j = 0; j < 16; j++) {
        rect(j * unit, i * unit, unit, 0.25 * unit);
        rect(j * unit, i * unit + 0.25 * unit, 0.25 * unit, 0.5 * unit);
        rect(j * unit + 0.25 * unit, i * unit + 0.25 * unit, 0.5 * unit, 0.5 * unit);
        rect(j * unit + 0.75 * unit, i * unit + 0.25 * unit, 0.25 * unit, 0.5 * unit);
        rect(j * unit, i * unit + 0.75 * unit, unit, 0.25 * unit);
      }
    }
  }
  noLoop();
}

function rnd() {
	seed ^= seed << 13;
	seed ^= seed >> 17;
	seed ^= seed << 5;
	return (((seed < 0) ? ~seed + 1 : seed) % 1000) / 1000;
}

function mouseClicked() {
	if (display == false) {
		noStroke();
		fill(0, 0, 0, .2);
		rect(0, 0, width, height);
		fill(0, 0, 100);
		textSize(width/64);
		text("Window: " + windows, width/32, 1.5 * width/32);
		let cond;
		if (c == 1) {cond = "Clear";}
		if (c == 2) {cond = "Night";}
		if (c == 3) {cond = "Cloudy";}
		if (c == 4) {cond = "Morning";}
		text("Condition: " + cond, width/32, 2.5 * width/32);
		text("Reflection 1: " + (h1-180), width/32, 3.5 * width/32);
		text("Reflection 2: " + (h2-180), width/32, 4.5 * width/32);
		text("Reflection 3: " + (h3-180), width/32, 5.5 * width/32);
		text("Reflection 4: " + (h4-180), width/32, 6.6 * width/32);
	}
	if (display == true) {
		seed = tokenData.tokenId;
		setup();
		redraw();
	}
	if (display == false) {
		display = true;
	}
	else {
		display = false;
	}
}