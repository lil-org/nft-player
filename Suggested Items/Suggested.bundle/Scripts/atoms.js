var seed = parseInt(tokenData.hash.slice(0, 16), 16);

p5.disableFriendlyErrors = true;

let pg;

let A, B;
let A1, A2, A3, A4;
let B1, B2, B3, B4;
let D1, D2;

let xx, yy;

let imageDim = 400;
let imageLength = imageDim * imageDim;
let signalHeight;
let numBlocks = imageDim/4;

let lastBlockTime = 0;
let blockDelay = 375;

let dotsDensity = 36;

let signalIndex = imageDim * 4;
let blockIndex = 0;

let drawSignals = true;
let drawImage = true;
let drawBlocks = true;
let drawDots = true;

let angle = 0.0;
let angleSpeed = 0.01;

let newImgData = [];

let boff = 0;

let ratio = 0.0;

// Features
let weirdo = false;
let doubleWaves = false;
let wave1 = -1;
let wave2 = -1;

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  colorMode(HSB, 360, 100, 100);
  
  r = new RND(seed);
  
  // BEGIN features
  if (r.rb(0, 1) > 0.95) {
    weirdo = true;
  }
  if (r.rb(0, 1) > 0.6) {
    doubleWaves = true;
  }
  wave1 = int(r.rb(1, 3));
  wave2 = int(r.rb(1, 3));
  // END features
  
  generateRandImage();
  rectMode(CENTER);
  imageMode(CENTER);
  setDimensions();
  frameRate(30);
}

function draw() {
  if (weirdo) {
    background(newImgData[blockIndex], 80, 100);
  } else {
    background(6, 15, 23+boff);
  }

  if (drawBlocks) { blocks(); }
  if (drawSignals) { signals(); }
  if (drawDots) { dots(); }
  
  if (drawImage) {
    image(pg, A2, B2, D1, D1);
  }
  signalIndex += 4;
  blockIndex += 2;
  if (signalIndex > pg.pixels.length) {
    signalIndex = imageDim * 4;
  }
  if (blockIndex > newImgData.length) {
    blockIndex = 0;
  }
}

function generateRandImage() {
  pg = createGraphics(imageDim, imageDim);
  pg.colorMode(HSB, 360, 100, 100);
  pg.loadPixels();
  waves(pg, wave1, 1);
  if (doubleWaves) {
    waves(pg, wave2, 2);
  }
  pg.updatePixels();
}

function waves(p, wtype, round) {
  let speed1 = r.rb(0.00001, 0.0005);
  let angle1 = 0;
  let speed2 = r.rb(0.00001, 0.0005);
  let angle2 = 0;
  let s = 80.0;
  let b = 100.0;
  let wscale = r.rb(0.5, 2.0);
  
  let imgIndexTemp = 0;

  p.colorMode(HSB, 360, 100, 100);
  p.loadPixels();
  for (let x = 0; x < p.width; x++) {
    for (let y = 0; y < p.height; y++) {
      
      let angle3 = map(y, 0, p.height, 0, TWO_PI*wscale);
      
      if (wtype == 1) {
        let h1 = map(sin(angle1), -1, 1, 0, 1);
        let h2 = map(sin(angle2+angle3), -1, 1, 0, 1);
        let hc = (h1 * h2) * 360;
        if (round == 1) {
          newImgData[imgIndexTemp] = hc;
          p.set(x, y, color(hc, s, b));
        } else { 
          let w = (newImgData[imgIndexTemp] + hc)/2;
          newImgData[imgIndexTemp] = w;
          p.set(x, y, color(w, s, b));
        }
      } else if (wtype == 2) {
        let h1 = map(sin(angle1+angle3), -1, 1, 0, 1);
        let h2 = map(sin(angle2)+sin(angle3), -1, 1, 0, 1);
        let hc = (h1 * h2) * 360;
        if (round == 1) {
          newImgData[imgIndexTemp] = hc;
          p.set(x, y, color(hc, s, b));
        } else {
          let w = (newImgData[imgIndexTemp] + hc)/2;
          newImgData[imgIndexTemp] = w;
          p.set(x, y, color(w, s, b));
        }
      }
      imgIndexTemp++;
      angle1 += speed1;
      angle2 += speed2;
    }
  }
  p.updatePixels();
}

function dots() {
  let rr = D1/imageDim;
  push();
  translate(A1, B1);
  scale(rr);
  rotateY(angle);
  let yyy = 0;
  let xx = -imageDim/2;
  let yy = -imageDim/2
  for (let i = 0; i < imageLength; i += dotsDensity) {
    stroke(119, 100, 100);
    if (i % imageDim == 0) {
      yyy += dotsDensity/2;
    }
    if (i > 0) {
      point(xx + (i%imageDim), yy + i/imageDim, newImgData[i] - 180);
    }
  }
  
  pop();
  
  angle += angleSpeed;
}

function signals() {
  if (height < width) {
    push();
    translate(0, B2);
    stroke(255);
    strokeWeight(1);
    for (let i = 0; i < pg.width; i++) {
      let curr = signalIndex - (i*4);
      let x = map(i, 0, pg.width, -width / 2, width / 2);
      let ry = map(pg.pixels[curr], 0, 255, -signalHeight/2, signalHeight/2);
      let gy = map(pg.pixels[curr+1], 0, 255, -signalHeight/2, signalHeight/2);
      let by = map(pg.pixels[curr+2], 0, 255, -signalHeight/2, signalHeight/2);
      if (i > 0) {
        point(x*2, ry-signalHeight);
        point(x*2, gy);
        point(x*2, by+signalHeight);
      }
    }
    pop();
  } else {
    push();
    translate(A2, 0);
    stroke(255);
    strokeWeight(1);
    for (let i = 0; i < pg.height; i++) {
      let curr = signalIndex - (i*4);
      let y = map(i, 0, pg.height, -height / 2, height / 2);
      let ry = map(pg.pixels[curr], 0, 255, -signalHeight/2, signalHeight/2);
      let gy = map(pg.pixels[curr+1], 0, 255, -signalHeight/2, signalHeight/2);
      let by = map(pg.pixels[curr+2], 0, 255, -signalHeight/2, signalHeight/2);
      if (i > 0) {
        point(ry-signalHeight, y*2);
        point(gy, y*2);
        point(by+signalHeight, y*2);
      }
    }
    pop();
  }
}

function blocks() {
  noStroke();
  for (let i = 0; i < numBlocks; i+=3) {
    let idx = (blockIndex + ((numBlocks-1) - i));
    fill(newImgData[idx], 80, 100);
    if (width >= height) {
      xx = map(i, 0, numBlocks, A4, A3);
      yy = map(i, 0, numBlocks, B4, B3);
    } else {
      xx = map(i, 0, numBlocks, A3, A4);
      yy = map(i, 0, numBlocks, B3, B4);
    }
    square(xx, yy, D2);
  }
}

function setDimensions() {
  A = width/2;
  B = height/2;
  ratio = A/B;
  //print(ratio);
  if (width > height) {
    A1 = A * -0.5625;
    A2 = A1;
    A3 = A * 0.1875;
    A4 = A * 0.5;
    B1 = B * -0.389;
    B2 = B * 0.389;
    B3 = B * 0.278;
    B4 = B * -0.278;
    D1 = B * 0.6;
    D2 = B * 1.1;
  } else {
    A1 = A * -0.389;
    A2 = A * 0.389;
    A3 = A * -0.278;
    A4 = A * 0.278;
    B1 = B * 0.5625;
    B2 = B1;
    B3 = B * -0.1873;
    B4 = B * -0.5;
    D1 = A * 0.6;
    D2 = A * 1.1;
  }
  if (ratio > 0.8 && ratio < 1.0) {
    let d = map(ratio, 0.8, 1.0, 1.0, 0.7)
    D1 = D1 * d;
    D2 = D2 * d;
  } else if (ratio >= 1.0 && ratio < 1.2) {
    let d = map(ratio, 1.0, 1.2, 0.7, 1.0)
    D1 = D1 * d;
    D2 = D2 * d;
  }
  signalHeight = D1 / 4.0;
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  setDimensions();
}

function keyPressed() {
  if (key == ' ') {
    generateRandImage();
  } else if (key == 'b' || key == 'B') {
    boff += 20;
    if (boff > 80) {
      boff = -23;
    }
  } else if (key == 's' || key == 'S') {
    drawSignals = !drawSignals;
  } else if (key == 't' || key == 'T') {
    drawDots = !drawDots;
  } else if (key == 'i' || key == 'I') {
    drawImage = !drawImage;
  }
}

class RND {
  constructor(seed) {
    this.seed = seed;
  }
  rd() {
    this.seed ^= this.seed << 13;
    this.seed ^= this.seed >> 17;
    this.seed ^= this.seed << 5;
    return ((this.seed < 0 ? ~this.seed + 1 : this.seed) % 1000) / 1000;
  }
  rb(a, b) {
    return a + (b - a) * this.rd();
  }
}