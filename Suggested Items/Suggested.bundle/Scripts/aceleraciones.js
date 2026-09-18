let rectSize;
let currentFrame = 0;
let numLines;
let flowField;
let lines = []; // Array to store line coordinates

let beige = '#FFFBEE';
let red = '#FC2659';
let orange = '#FF7A00';
let yellow = '#FFD600';
let lightgreen = '#91E409';
let green = '#26AA72';
let lightblue = '#0ECECE';
let blue = '#0075FF';
let purple = '#6425E9';
let pink = '#FA00FF';
let black = '#000000';

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
  // random boolean with p as percent liklihood of true
  random_bool(p) {
    return this.random_dec() < p;
  }
  // random value in an array of items
  random_choice(list) {
    return list[this.random_int(0, list.length - 1)];
  }


}

let R = new Random(tokenData.hash);
  
let paletteNight = R.random_choice([beige, red, yellow, lightgreen, green, lightblue, blue, purple, pink, orange]); //enum
let paletteDay = R.random_choice([black, red, yellow, lightgreen, green, lightblue, blue, purple, pink, orange]); //enum
//let scale = R.random_bool(.5); //boolean
let length = R.random_int(5,420); //number
let numlines = R.random_int(1,420); //number
let weight = R.random_int(1,15);
let aura = R.random_int(0,5); //number
let direction = R.random_int(0,420) //number

function setup() {
  createCanvas(windowWidth, windowHeight);
  rectMode(CENTER);
  calculateSizes();
  createFlowField();
  frameRate(15);
  //noLoop();
}

function draw() {

  if (aura > 0) {
      background(black);
      fill(paletteNight);
      rect(width / 2, height / 2, rectSize1, rectSize2);

      
      numLines = floor(numlines); // Random number of lines between 3 and 10


      for (let i = 0; i < numLines; i++) {
        drawRandomStrokedLine();
      }

      stroke(paletteNight);
      strokeWeight(3);
      noFill();
      rect(width / 2, height / 2, rectSize1, rectSize2);
      
  } else {
      background(beige);
      fill(paletteDay);
      rect(width / 2, height / 2, rectSize1, rectSize2);

        numLines = floor(numlines); // Random number of lines between 3 and 10


      for (let i = 0; i < numLines; i++) {
        drawRandomStrokedLine();
      }

      stroke(paletteDay);
      strokeWeight(windowHeight*0.01);
      noFill();
      rect(width / 2, height / 2, rectSize1, rectSize2);

  }

}

function drawRandomStrokedLine() {

if (aura > 0) {
    stroke(black);
    strokeWeight(weight);
    strokeCap(SQUARE);
  } else {
    stroke(beige);
    strokeWeight(weight);
    strokeCap(SQUARE);

  }

  let stepSize = length; // Adjust the step size for longer lines
  let angle = flowField.getFlowDirection(width / 2, height / 2);
  angle += map(noise(width * 0.01, height * 0.01), 0, 1, -PI / 4, PI / 4); // Add curvature using Perlin noise

  let startX, startY, endX, endY;
  let attempts = 0;
  let maxAttempts = 100; // Limit the number of attempts to avoid infinite loops

  // Loop until we find a non-overlapping starting point for the line
  while (attempts < maxAttempts) {
    startX = random(width);
    startY = random(height);

    endX = startX + cos(angle) * stepSize;
    endY = startY + sin(angle) * stepSize;

    let overlapping = false;
    for (let j = 0; j < lines.length; j++) {
      let lineStart = lines[j];
      let lineEnd = lines[j + 1];
      if (lineStart && lineEnd) {
        let intersection = checkLineIntersection(startX, startY, endX, endY, lineStart.x, lineStart.y, lineEnd.x, lineEnd.y);
        if (intersection) {
          overlapping = true;
          break;
        }
      }
    }

    if (!overlapping) {
      break; // Exit the loop if the line is not overlapping
    }

    attempts++;
  }

  // Draw the line and add its coordinates to the lines array
  strokeWeight((windowWidth*weight)*0.001);
  line(startX, startY, endX, endY);
  lines.push({ x: startX, y: startY }, { x: endX, y: endY });
}

// Function to check if two line segments intersect
function checkLineIntersection(x1, y1, x2, y2, x3, y3, x4, y4) {
  let ua, ub, denominator;
  denominator = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1);
  if (denominator == 0) {
    return false; // Lines are parallel or coincident
  }
  ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / denominator;
  ub = ((x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3)) / denominator;
  if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
    // Intersection point falls within the line segments
    return true;
  }
  return false;
}

function calculateSizes() {
  rectSize1 = min(width, height) * 0.5;
  rectSize2 = min(width, height) * 0.65;
}

function createFlowField() {
  flowField = new FlowField(20); // Adjust the grid resolution as needed
}

class FlowField {
  constructor(resolution) {
    this.resolution = resolution;
    this.cols = ceil(width / this.resolution);
    this.rows = ceil(height / this.resolution);
    this.field = this.createField();
  }

  createField() {
    let field = [];
    noiseSeed(direction);

    for (let y = 0; y < this.rows; y++) {
      let row = [];
      for (let x = 0; x < this.cols; x++) {
        let angle = map(noise(x * 0.1, y * 0.1), 0, 1, 0, TWO_PI);
        row.push(angle);
      }
      field.push(row);
    }

    return field;
  }

  getFlowDirection(x, y) {
    let col = floor(x / this.resolution);
    let row = floor(y / this.resolution);
    let angle = direction // this.field[row][col]; 
    return angle;
  }

}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  calculateSizes(); 

  }