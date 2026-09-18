let maskGraphics;
let finalGraphics;
let numRuns = 0;
let isSingleRun = false;
let run = 0;
let endRotation = 0;
let noDraw = false;
let isCircle = false;
let isBig = false;
let numBackgroundBisections;
let numMaskBisections;
let colorPalette = [];
let curatedPalette = -1;
let isCurated = false;
let curatedPaletteName = "N/A";
let specialPaletteNames = [
  "ACK Flowers", 
  "Grant", 
  "TRAILMIX", 
  "XCOPY Waster", 
  "Fidenza Luxe", 
  "totty BAYC #1586", 
  "totty focus", 
  "totty CryptoPunk #3169", 
  "Homer", 
  "RAB1D", 
  "Digital Zone 0", 
  "Bongdoe"
];
let specialPalettes = [
  ["#c937aa", "#014528", "#045339", "#0d5047","#ac34b6"],
  ["#ca3f44", "#f3ecd0", "#b2baca", "#b77c4b", "#a5b257"],
  ["#585453", "#31473d", "#f70805", "#1f1f1f", "#26312b"],
  ["#ff0066", "#4c5868", "#000000", "#ffffff", "#e981dc"],
  ["#533e2e", "#2aa490", "#89b1ba", "#b7d5cb", "#e6bf9b", "#d64532"],
  ["#ed1c24", "#f5979e", "#3cfcff", "#17e6b7", "#e3c8a1"],
  ["#d7d7ff", "#8686bf", "#0d1b1e", "#36083e", "#cecece"],
  ["#0e0d10", "#40210b", "#723302", "#000000", "#638596"],
  ["#f9da03", "#15201e", "#334d48", "#68c9fd", "#ffffff"],
  ["#982fa9", "#d766ec", "#542fd7", "#5d7ced", "#7538d5"],
  ["#aaadb0", "#bdc2c5", "#5b78ae", "#7392c5", "#607db2"],
  ["#20262a", "#194259", "#483b49", "#cb14a6", "#0d8070"] 
];
 let R;


function setup() {
  R = new Random();
  createCanvas(window.innerHeight, window.innerHeight);
  angleMode(DEGREES);
  maskGraphics = createGraphics(window.innerHeight, window.innerHeight);
  finalGraphics = createGraphics(window.innerHeight, window.innerHeight);
  maskGraphics.noStroke();
  maskGraphics.background(0);
  
  // VARIABLES
  numRuns = R.random_int(2, 7);
  if (R.random_dec() > 0.95) {
    numRuns = 0;
  }
  isSingleRun = numRuns == 0;
  isCircle = R.random_dec() > 0.7;
  isBig = R.random_dec() > 0.842;
  isCurated = R.random_dec() > 0.985;
  if (isCurated) {
    curatedPalette = R.random_int(0, specialPalettes.length - 1);
    curatedPaletteName = specialPaletteNames[curatedPalette];
    console.log("curatedPaletteName " + curatedPaletteName);
  }
  if (isBig && numRuns != 0) {
    numRuns = 1;
  }
  numBackgroundBisections = R.random_int(0, 3);
  numMaskBisections = R.random_int(3, 10);
  endRotation = R.random_choice([0, 90, 180, 270]);
  generateColorPalette(curatedPalette); // in colorPalette
  
  // skip draw method if we already drew what we need to
  if (isSingleRun) {
    // numBackgroundBisections and isCircle don't matter here
    noDraw = true;
    drawMainArt();
    image(finalGraphics, 0, 0);
  }
}

function draw() {
  if (noDraw) {
    return;
  }

  if (isBig) {
    makeCircleOrSquareBigMask(isCircle);
  } else {
    makeCircleOrSquareRepMask(isCircle);  
  }
  
  run++;
  if (isBig || run >= numRuns) {
    noLoop();
    applyMask();
  }
}

function makeCircleOrSquareBigMask(isCircle=false) {
  if (isCircle) {
    maskGraphics.ellipse(width / 2, height / 2, 15*width/16, 15*height/16);
    return;
  }
  maskGraphics.rect(width / 16, height / 16, 14*width / 16, 14*height / 16);

}

function makeCircleOrSquareRepMask(isCircle=false) {
  let cols = R.random_int(2,10);
  let rows = R.random_int(2,15);
  let initialDiameter = height / 8;
  let xPadding = initialDiameter + R.random_dec(0, initialDiameter);
  let yPadding = initialDiameter/2;
  let randPadding = R.random_num(1, yPadding);
  
  let startX = R.random_int(0, maskGraphics.width - cols * initialDiameter);
  let startY = R.random_int(0, maskGraphics.height - rows * initialDiameter);

  let currentY = startY;
  let prevX = 0;
  
  for (let i=0; i<rows; i++) {
    let heightEllipse = initialDiameter * (rows - i) / rows; // decrease height as you go down rows
    
    for (let j=0; j<cols; j++) {
      let x = startX + j * xPadding;
      let y = currentY + yPadding/2;
      let widthEllipse = initialDiameter; // constant width for all ovals
      
      if (isCircle) {
        maskGraphics.ellipse(x, y, widthEllipse, heightEllipse);
      } else {
        maskGraphics.rect(x, y, widthEllipse, heightEllipse);
      }
      prevX = x;
    }
    
    prevX = 0;
    currentY += heightEllipse + randPadding;
  }
}

function applyMask() {
  drawMainArt();
  
  // Apply the offscreen graphics buffer as an alpha mask onto the final art graphics
  finalGraphics.blendMode(BLEND);
  maskGraphics.loadPixels();
  finalGraphics.loadPixels();
  for (let i = 0; i < finalGraphics.pixels.length; i += 4) {
    finalGraphics.pixels[i+3] = maskGraphics.pixels[i];
  }
  finalGraphics.updatePixels();
  
  // Set background and then apply final art to canvas
  background(13,27,30);
  randomBisection(0, 0, width, height, numBackgroundBisections, true);
  
  // rotate final graphics
  imageMode(CENTER);
  translate(window.innerHeight/2, window.innerHeight/2);
  rotate(endRotation);
  
  image(finalGraphics, 0, 0);  // Draw the final art onto the canvas
}

function drawMainArt() {
  randomBisection(0, 0, width, height, numMaskBisections);
}

// -----BISECTION GRADIENT LOGIC-----

function randomBisection(x, y, w, h, depth, only=false) {
  if (depth === 0) {
    drawGradient(x, y, w, h, only);
  } else {
    if (R.random_dec() < 0.5) {
      // Split vertically
      let split = R.random_num(0.3, 0.7);
      randomBisection(x, y, w * split, h, depth - 1, only);
      randomBisection(x + w * split, y, w * (1 - split), h, depth - 1, only);
    } else {
      // Split horizontally
      let split = R.random_num(0.3, 0.7);
      randomBisection(x, y, w, h * split, depth - 1, only);
      randomBisection(x, y + h * split, w, h * (1 - split), depth - 1, only);
    }
  }
}

function generateColorPalette(curatedPalette) {
  if (curatedPalette != -1) {
    palette = specialPalettes[curatedPalette];
    for (let i = 0; i < palette.length; i++) {
      colorPalette.push(color(palette[i]));
    }
    return;
  }
  let numColors = R.random_int(2,6);
  for (let i = 0; i < numColors; i++) {
    colorPalette.push(color(R.random_int(0, 255), R.random_int(0, 255), R.random_int(0, 255)));
  }
}

function drawGradient(x, y, w, h, only=false) {
  let c1 = colorPalette[R.random_int(0, colorPalette.length - 1)];
  let c2 = colorPalette[R.random_int(0, colorPalette.length - 1)];

  for (let i = y; i < y + h; i++) {
    let inter = map(i, y, y + h, 0, 1);
    let c = lerpColor(c1, c2, inter);
    if (only) {
      stroke(c);
      line(x, i, x + w, i);
    } else {
      finalGraphics.stroke(c);
      finalGraphics.line(x, i, x + w, i);
    }
  }
}

class Random {
  constructor() {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substring(0, 8), 16);
      let b = parseInt(uint128Hex.substring(8, 16), 16);
      let c = parseInt(uint128Hex.substring(16, 24), 16);
      let d = parseInt(uint128Hex.substring(24, 32), 16);
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
    this.prngA = new sfc32(tokenData.hash.substring(2, 34));
    // seed prngB with second half of tokenData.hash
    this.prngB = new sfc32(tokenData.hash.substring(34, 66));
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
  // random value in an array of items
  random_choice(list) {
    return list[this.random_int(0, list.length - 1)];
  }
}

