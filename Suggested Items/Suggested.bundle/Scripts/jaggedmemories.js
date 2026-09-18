/*
 * variables
 */

let debugMode = false;
const DEFAULT_HEIGHT = 1920;
const DEFAULT_WIDTH = 1080;
const MAX_HEIGHT = 3840;
const MAX_WIDTH = 2160;
let R;
let WIDTH, HEIGHT;
let hash;
let hashPairs = [];
let decPairs = [];
let mainCanvas;
let nSeed;
let rSeed;
let canvasScale;
let saveBoolean = false;
let params, features;
let graphics, centerPosition, centerAngle;

/*
 * setup p5.js
 */
function setup() {
  params = setupParams();

  setupCanvas();
  frameRate(60);

  if (debugMode) {
    let features = structuredClone(params);
    delete features.Colors;
    delete features.LineColors;
    delete features.LineDiagonals;
    delete features.LineParams;
    print("================================================");
    print("features");
    print(features);
    print("================================================");
    // return features;
  }
}

/*
 * draw p5.js
 */
function draw() {
  clear();
  drawPattern();
  if (debugMode) {
    // imageMode(CORNER);
    // image(graphics, 0, 0, 100, 100);
  }
}

function drawPattern() {
  graphics.clear();
  let offset = graphics.width / 20;
  let margin = offset / 1;
  let cellSize = params.Cells;
  let d = int(
    (graphics.width - offset * 2 - margin * (cellSize - 1)) / cellSize
  );
  for (let j = 0; j < cellSize; j++) {
    for (let i = 0; i < cellSize; i++) {
      let index = j * cellSize + i;
      let lineParam = params.LineParams[index];
      let lineDiagonal = lineParam.LineDiagonal;
      let x = int(offset + i * (d + margin));
      let y = int(offset + j * (d + margin));
      if (lineDiagonal) {
        drawFreqLine(x, y, x + d, y + d, lineParam, graphics);
      } else {
        drawFreqLine(x + d, y, x, y + d, lineParam, graphics);
      }
    }
  }

  clear();
  blendMode(BLEND);
  switch (params.BlendMode) {
    case "ADD":
      background(0, 0, 10);
      blendMode(ADD);
      break;
    case "BLEND":
      background(0, 0, 0);
      blendMode(BLEND);
      break;
    case "BURN":
      background(0, 0, 92);
      blendMode(BURN);
      break;
  }

  for (let i = 0; i < params.Iteration; i++) {
    let eachLayer = graphics.get();
    eachLayer.resize(
      (layerScale = int(
        map(
          sin(
            ((i * 360) / params.Iteration) * map(params.Cells, 4, 13, 1, 3) +
              2 * frameCount
          ),
          -1,
          1,
          WIDTH / 50,
          WIDTH / 4
        )
      )),
      layerScale
    );
    push();
    translate(WIDTH / 2, HEIGHT / 2);
    translate(centerPosition.x, centerPosition.y);
    switch (params.Position) {
      case "Planet":
        break;
      case "Satellite":
        translate(
          (cos(+(i / params.Iteration) * 360) * WIDTH) / 8,
          (sin(+(i / params.Iteration) * 360) * HEIGHT) / 8
        );
        break;
      case "Comet":
        translate(
          (cos(frameCount * 1 + (i / params.Iteration) * 360) * WIDTH) / 8,
          (sin((frameCount * 2) / 3 + (i / params.Iteration) * 360) * HEIGHT) /
            8
        );
        break;
    }

    rotate(
      ((i * 360) / params.Iteration) * 1.5 +
        360 / params.Iteration / 2 +
        (frameCount / 2) * (params.Rotation == "Clockwise" ? 1 : -1)
    );
    scale((m = tan(((i * 90) / params.Iteration + frameCount / 5) % 90)));
    let nx = sin((i * 90) / params.Iteration + frameCount / 5) * 100;
    let ny = cos((i * 90) / params.Iteration + frameCount / 6) * 100;
    if (params.Distortion == "On") {
      shearY(10 * sin((i / params.Iteration) * 360 + frameCount / 2));
    }
    imageMode(CENTER);
    image(eachLayer, nx, ny, width, width);
    if (params.BlendMode == "BURN") {
      image(eachLayer, nx, ny, width, width);
    }
    pop();
  }
}

function drawFreqLine(x1, y1, x2, y2, lineParam, target) {
  let d = dist(x1, y1, x2, y2);
  let a = atan2(y2 - y1, x2 - x1);
  let h1 = lineParam.FreqA;
  let h2 = lineParam.FreqB;
  let f1 = map(sin(x1 + y1 * width + frameCount * h1), -1, 1, 0, 1);
  let f2 = map(cos(x2 + y2 * width + frameCount * h2), -1, 1, 0, 1);

  target.drawingContext.setLineDash[d];
  target.drawingContext.lineDashOffset =
    ((max(f1, f2) * d + frameCount) / 10) % (d * 2);

  f1 = easeInOutCirc(f1);
  f2 = easeInOutCirc(f2);
  let s1 = d * f1;
  let s2 = d * f2;
  let strokeColor = lineParam.Color.lineColor;
  let pointColor = lineParam.Color.pointColor;
  target.strokeCap(SQUARE);

  if (lineParam.Type == "Line") {
    let t = dist(s1, 0, s2, 0) / d;
    target.push();
    target.translate(x1, y1);
    target.rotate(a);

    target.strokeCap(PROJECT);
    target.noFill();
    target.stroke(strokeColor);

    target.strokeWeight((d / 50) * max(1 - f2, 1 - f1) * sqrt(2));
    target.line(s1, 0, s2, 0);
    // line(0, 0, d*t, 0);

    if (lineParam.Point == "Circle") {
      target.stroke(pointColor);
      target.strokeWeight((d / 10) * (1 - f1) * sqrt(2));
      target.point(s1, 0);
      target.strokeWeight((d / 10) * (1 - f2) * sqrt(2));
      target.point(s2, 0);
    } else if (lineParam.Point == "Square") {
      target.push();
      target.translate(s1, 0);
      target.rotate(45 + f1 * 360);
      target.rectMode(CENTER);
      target.fill(strokeColor);
      target.noStroke();
      target.rect(0, 0, ((d / 5) * (1 - f1)) / sqrt(2));
      target.pop();

      target.push();
      target.translate(s2, 0);
      target.rotate(45 + f2 * 360);
      target.rectMode(CENTER);
      target.fill(strokeColor);
      target.noStroke();
      target.rect(0, 0, ((d / 5) * (1 - f1)) / sqrt(2));
      target.pop();
    }
    target.pop();
  } else if (lineParam.Type == "Arc") {
    let a1 = 90 * f1;
    let a2 = 90 - 90 * f2;
    let d2 = d / sqrt(2);
    target.push();
    target.translate(min(x1, x2) + d2 / 2, min(y1, y2) + d2 / 2);
    target.rotate(lineParam.Angle);
    target.translate(-d2 / 2, -d2 / 2);
    target.noFill();
    target.stroke(strokeColor);
    target.strokeWeight((d / 50) * max(1 - f2, 1 - f1) * sqrt(2));
    if (abs(a1 - a2) > 0.1) {
      target.arc(0, 0, d2 * 2, d2 * 2, min(a1, a2), max(a1, a2));
    }
    if (lineParam.Point == "Circle") {
      target.stroke(pointColor);
      target.strokeWeight((d / 10) * (1 - f1) * sqrt(2));
      target.point(cos(a1) * d2, sin(a1) * d2);
      target.strokeWeight((d / 10) * (1 - f2) * sqrt(2));
      target.point(cos(a2) * d2, sin(a2) * d2);
    } else if (lineParam.Point == "Square") {
      target.push();
      target.translate(cos(a1) * d2, sin(a1) * d2);
      target.rotate(45 + f1 * 360);
      target.rectMode(CENTER);
      target.fill(strokeColor);
      target.noStroke();
      target.rect(0, 0, ((d / 5) * (1 - f1)) / sqrt(2));
      target.pop();

      target.push();
      target.translate(cos(a2) * d2, sin(a2) * d2);
      target.rotate(45 + f2 * 360);
      target.rectMode(CENTER);
      target.fill(strokeColor);
      target.noStroke();
      target.rect(0, 0, ((d / 5) * (1 - f1)) / sqrt(2));
      target.pop();
    }
    target.pop();
  }
}

function setupParams() {
  hash = tokenData.hash;
  if (debugMode) {
    // hash = "0x622fb6114b74ada47abf7a4721f697623f8c33c89adbe098367416c808cd8447";
  }
  R = new Random();
  if (debugMode) {
    print("================================================");
    print("debugMode", debugMode);
    print("hash", hash);
    print("================================================");
  }
  for (let j = 0; j < 32; j++) {
    hashPairs.push(hash.slice(2 + j * 2, 4 + j * 2));
  }
  decPairs = hashPairs.map((x) => {
    return parseInt(x, 16);
  });

  let params = getParams(decPairs);
  if (debugMode) {
    print(params);
    print("================================================");
    print("Palette : ", params.Palette);
    print("Colors : ", params.Colors);
    print("Cells : ", params.Cells);
    print("Iteration : ", params.Iteration);
    print("Position : ", params.Position);
    print("LineType : ", params.LineType);
    print("PointType : ", params.PointType);
    print("Distortion : ", params.Distortion);
    print("Rotation : ", params.Rotation);
    print("BlendMode : ", params.BlendMode);
    print("================================================");
  }
  return params;
}

function getParams(decPairs) {
  const colorOjbect = colorScheme[decPairs[1] % colorScheme.length];
  let blendModeChoices = ["ADD", "BLEND", "BURN"];
  let cellSize = (decPairs[2] % 10) + 4;
  let iteration = constrain(decPairs[3] % 20, 6, 20);
  let lineColors = [];
  for (let i = 0; i < cellSize * cellSize; i++) {
    lineColors.push(R.random_choice(colorOjbect.colors));
  }
  let lineDiagonals = [];
  for (let i = 0; i < cellSize * cellSize; i++) {
    lineDiagonals.push(R.random_bool(0.5));
  }
  let distortion = decPairs[4] % 4 == 0 ? "On" : "Off";
  let position = decPairs[5] % 11 > 5 ? "Planet" : "Satellite";
  position = decPairs[5] % 11 == 0 ? "Comet" : position;

  let rotation = decPairs[6] % 2 == 0 ? "Clockwise" : "Counterclockwise";

  let blendModeChoice = R.random_choice(blendModeChoices);
  let lineParams = [];
  const lineType = R.random_choice(["Line", "Arc", "Mix"]);
  const pointType = R.random_choice(["Square", "Circle", "Mix"]);
  for (let i = 0; i < cellSize * cellSize; i++) {
    let freqA = (R.random_num(1, 5) / 2) * (R.random_bool(0.5) ? -1 : 1);
    let freqB = (R.random_num(1, 5) / 2) * (R.random_bool(0.5) ? -1 : 1);
    let lineDiagonal = R.random_bool(0.5);
    let strokeColor = R.random_choice(colorOjbect.colors);
    let c1 = R.random_choice(colorOjbect.colors);
    let c2 = R.random_choice(colorOjbect.colors);
    while (c1 == c2) {
      c2 = R.random_choice(colorOjbect.colors);
    }
    strokeColor = {
      lineColor: c1,
      pointColor: c2,
    };

    let type;
    if (lineType == "Arc") {
      type = "Arc";
    } else if (lineType == "Line") {
      type = "Line";
    } else {
      type = R.random_choice(["Line", "Arc"]);
    }
    let pType;
    if (pointType == "Square") {
      pType = "Square";
    } else if (pointType == "Circle") {
      pType = "Circle";
    } else {
      pType = R.random_choice(["Square", "Circle"]);
    }
    lineParams.push({
      Color: strokeColor,
      LineDiagonal: lineDiagonal,
      FreqA: freqA,
      FreqB: freqB,
      Type: type,
      Point: pType,
      Angle: R.random_choice([0, 90, 180, 270]),
    });
  }
  centerAngle = R.random_num(0, 360);
  return {
    Palette: colorOjbect.name,
    Colors: colorOjbect.colors,
    Cells: cellSize,
    Iteration: iteration,
    Position: position,
    LineType: lineType,
    PointType: pointType,
    Distortion: distortion,
    Rotation: rotation,
    LineColors: lineColors,
    LineDiagonals: lineDiagonals,
    LineParams: lineParams,
    BlendMode: blendModeChoice,
  };
}

function setupCanvas() {
  pixelDensity(1);
  WIDTH = windowWidth;
  HEIGHT = windowHeight;
  canvasScale = HEIGHT / DEFAULT_HEIGHT;
  mainCanvas = createCanvas(WIDTH, HEIGHT);
  let w = constrain(
    max(WIDTH, HEIGHT) / 4,
    max(WIDTH, HEIGHT) / 2,
    MAX_HEIGHT / 2
  );

  graphics = createGraphics(w, w);
  colorMode(HSB, 360, 100, 100, 100);
  angleMode(DEGREES);
  graphics.colorMode(HSB, 360, 100, 100, 100);
  graphics.angleMode(DEGREES);
  noSmooth();
  centerPosition = createVector(0, 0);
  if (decPairs[6] % 10 < 3) {
    centerPosition.add(
      p5.Vector.fromAngle(centerAngle).mult(min(WIDTH, HEIGHT) / 10)
    );
  }
}

function calculateCanvasSize() {
  const aspectRatioWidth = 9;
  const aspectRatioHeight = 16;
  let canvasWidth, canvasHeight;
  if (windowWidth * (aspectRatioHeight / aspectRatioWidth) <= windowHeight) {
    canvasWidth = windowWidth;
    canvasHeight = windowWidth * (aspectRatioHeight / aspectRatioWidth);
  } else {
    canvasHeight = windowHeight;
    canvasWidth = windowHeight * (aspectRatioWidth / aspectRatioHeight);
  }
  if (canvasHeight > MAX_HEIGHT) {
    canvasHeight = MAX_HEIGHT;
    canvasWidth = canvasHeight * (aspectRatioWidth / aspectRatioHeight);
  }
  if (saveBoolean) {
    canvasWidth = MAX_WIDTH;
    canvasHeight = MAX_HEIGHT;
  }
  return {
    width: canvasWidth,
    height: canvasHeight,
  };
}

/**
 * color palette for drawing
 */
const colorScheme = [
  {
    name: "Benedictus",
    colors: ["#F27EA9", "#366CD9", "#5EADF2", "#636E73", "#F2E6D8"],
  },
  {
    name: "Cross",
    colors: ["#D962AF", "#58A6A6", "#8AA66F", "#F29F05", "#F26D6D"],
  },
  {
    name: "Demuth",
    colors: ["#222940", "#D98E04", "#F2A950", "#BF3E21", "#F2F2F2"],
  },
  {
    name: "Hiroshige",
    colors: ["#1B618C", "#55CCD9", "#F2BC57", "#F2DAAC", "#F24949"],
  },
  {
    name: "Hokusai",
    colors: ["#074A59", "#F2C166", "#F28241", "#F26B5E", "#F2F2F2"],
  },
  {
    name: "Indigo",
    colors: ["#023059", "#459DBF", "#87BF60", "#D9D16A", "#F2F2F2"],
  },
  {
    name: "Java",
    colors: ["#632973", "#02734A", "#F25C05", "#F29188", "#F2E0DF"],
  },
  {
    name: "Kandinsky",
    colors: ["#8D95A6", "#0A7360", "#F28705", "#D98825", "#F2F2F2"],
  },
  {
    name: "Monet",
    colors: ["#4146A6", "#063573", "#5EC8F2", "#8C4E03", "#D98A29"],
  },
  {
    name: "Nizami",
    colors: ["#034AA6", "#72B6F2", "#73BFB1", "#F2A30F", "#F26F63"],
  },
  {
    name: "Renoir",
    colors: ["#303E8C", "#F2AE2E", "#F28705", "#D91414", "#F2F2F2"],
  },
  {
    name: "VanGogh",
    colors: ["#424D8C", "#84A9BF", "#C1D9CE", "#F2B705", "#F25C05"],
  },
  {
    name: "RiverSide",
    colors: ["#906FA6", "#025951", "#252625", "#D99191", "#F2F2F2"],
  },
];

/**
 * Random Generator Class
 */
class Random {
  constructor() {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substr(0, 8), 16);
      let b = parseInt(uint128Hex.substr(8, 8), 16);
      let c = parseInt(uint128Hex.substr(16, 8), 16);
      let d = parseInt(uint128Hex.substr(24, 8), 16);
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
    this.prngA = new sfc32(hash.substr(2, 32));
    // seed prngB with second half of tokenData.hash
    this.prngB = new sfc32(hash.substr(34, 32));
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

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  WIDTH = windowWidth;
  HEIGHT = windowHeight;
  let w = constrain(
    max(WIDTH, HEIGHT) / 4,
    max(WIDTH, HEIGHT) / 2,
    MAX_HEIGHT / 2
  );
  centerPosition = createVector(0, 0);
  if (decPairs[6] % 10 < 3) {
    centerPosition.add(
      p5.Vector.fromAngle(centerAngle).mult(min(WIDTH, HEIGHT) / 10)
    );
  }
  graphics.width = w;
  graphics.height = w;
}

function easeInOutCirc(x) {
  return x < 0.5
    ? (1 - Math.sqrt(1 - Math.pow(2 * x, 2))) / 2
    : (Math.sqrt(1 - Math.pow(-2 * x + 2, 2)) + 1) / 2;
}

function easeInOutElastic(x) {
  const c5 = (2 * Math.PI) / 4.5;
  return x === 0
    ? 0
    : x === 1
    ? 1
    : x < 0.5
    ? -(Math.pow(2, 20 * x - 10) * Math.sin((20 * x - 11.125) * c5)) / 2
    : (Math.pow(2, -20 * x + 10) * Math.sin((20 * x - 11.125) * c5)) / 2 + 1;
}
