// Eodach by Akira Ishi
// 12/08/2023

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
let R = new Random();

const scaleRatio = 1 / 1;
function setupCanvas() {
  const height2 = round(min(windowWidth, windowHeight * scaleRatio) / scaleRatio);
  const width2 = round(height2 * scaleRatio);
  createCanvas(width2, height2);
  noStroke();
}
function setup() {
  setupCanvas()
  colorMode(HSB,360, 100, 100, 255)
  noLoop()
  noFill()
  randValue2 = R.random_dec()
  randValue3 = R.random_dec()
  if (randValue2 <= 0.4) {
    strFull=true
  } else {
    strFull=false
  } 
 if (randValue3 <= 0.25) {
    transla=true
  } else {
    transla=false
  } 

  a=color(0, R.random_int(60,70), R.random_int(69,79))  
  b=color(120, R.random_int(60,70),R.random_int(29,35))
  c=color(240, R.random_int(60,70), R.random_int(28,34))
  d=color(49, R.random_int(60,70), R.random_int(85,95))
  g=color(280, R.random_int(60,70), R.random_int(29,35))
  h=color(0, R.random_int(60,70), R.random_int(29,35))
  i=color(131, R.random_int(55,60),R.random_int(25,30))
  e=color(0, 0, 10)
  f=color(0,10,100)
  colorsz = [a, b, c,d, f,g,h,i];
  colorszb = [a, b, c,d,e,f,g,h,i]; 
  do {
  bgColor = colorsz[floor(R.random_dec() * colorsz.length)];
  colorszba = colorszb.filter(color => {
    if (color === bgColor) {
        return false;
    }
    if (strFull) {
      if (bgColor === i && (color === b || color === g||color === h|| color === c|| color === e|| color === f|| color === a)) {
          return false;
      } else if (bgColor === d && (color === b || color === i|| color === a|| color === c|| color === h|| color === f|| color === e)) {
          return false;
      } else if (bgColor === g && (color === h || color === c|| color === i|| color === b|| color === e|| color === f)) {
          return false;
      } else if (bgColor === a && (color === b|| color === i|| color === f || color === h || color === g|| color === e)) {
          return false;
      } else if (bgColor === b && (color === h || color === a || color === i|| color === g|| color === e|| color === d)) {
          return false;
      } else if (bgColor === c && (color === h|| color === i|| color === e || color === g|| color === f)) {
          return false;
      } else if (bgColor === f ) {
          return false;
      } else if (bgColor === h && (color === a|| color === b|| color === i|| color === c|| color === g|| color === e)) {
        return false;
    }
    } else 
    if (bgColor === c && (color === e|| color ===g|| color === i)) {
        return false;
     } else if (bgColor === a && ( color === g|| color === h||color === b||color === f)) {
        return false;
    } else if (bgColor === f && ( color === d||color === h||color === i)) {
        return false;
    } else if (bgColor === b && (color === e|| color === g|| color === d|| color === i||color === f)) {
        return false;
    } else if (bgColor === g && (color === h|| color === c|| color === e||color === f)) {
        return false;        
    } else if (bgColor === d && (color === e|| color === g|| color === h|| color === b|| color === a|| color === f)) {
        return false;
    } else if (bgColor === i && (color === c|| color === e|| color === h|| color === b|| color === g|| color === d)) {
        return false;
    } else if (bgColor === h && (color === a|| color === e|| color === g|| color === c||color === f||color === d)) {
        return false;
    }
    return true;
    });
    } while (colorszba.length === 0); 
  strColor = colorszba[floor(R.random_dec() * colorszba.length)];;
  randValue = R.random_dec();
  if (randValue <= 0.4) {
      rotationAngle = PI/4;
  } else {
      rotationAngle = R.random_dec()*TWO_PI;
  }
  if (strFull){
    strFullValue=color(strColor);
    divisionFactor = R.random_num(1.85, 1.925)
    initialRadius = R.random_int(850,1000); 
      strokeW=R.random_num(0.9,1.1)
  strokeWa=R.random_num(0.9,1.1)
  } else {
  strFullValue = color(e)
  strokeW=R.random_num(0.9,1.3) 
  strokeWa=R.random_num(0.9,1.3)
      if (bgColor === f){
    divisionFactor = R.random_num(1.845, 1.88);
  } else {
    divisionFactor = R.random_num(1.845, 1.925);
  }    
  initialRadius = R.random_int(850,1100); 
  }
  if (transla){
    transl=2
  } else { 
  transl=R.random_num(1.5,3)
  } 
  scaleS=R.random_num(1.2,1.4)
}

function draw() {  
  background(bgColor)
  translate(width / transl, height / transl); 
  rotate(rotationAngle); 
  scale(scaleS*(width/800))
  drawEllipse(0, 0, initialRadius); 

}

function drawEllipse(x, y, radius) {
  ellipse(x, y, radius, radius);
  if(radius >8) {
   strokeWeight(strokeW)
   stroke(strFullValue)
    drawEllipse(x + radius / divisionFactor, y, radius / divisionFactor);
    drawEllipse(x - radius / divisionFactor, y, radius / divisionFactor);
    strokeWeight(strokeWa)    
    drawEllipse(x, y + radius / divisionFactor, radius / divisionFactor);
    if (strFull){
      stroke(strFullValue)
    } else {
     stroke(strColor)
    }
    drawEllipse(x, y - radius / divisionFactor, radius / divisionFactor);
  }
}
function windowResized() {
  setupCanvas();
  redraw()
}