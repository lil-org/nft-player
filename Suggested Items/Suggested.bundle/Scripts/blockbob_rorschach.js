let hash = tokenData.hash
console.log('this hash: ' + hash);

let seed = parseInt(tokenData.hash.slice(0, 16), 16);
let R;

const swatches = [
  ['#282837', '#f3f2f1'], // 0
  ['#00aeef', '#ec008c', '#fff200', '#3a3fb8', '#00a651', '#ed1c24'], // 1
  ['#ff0000', '#00ff00', '#0000ff', '#ffff00', '#00ffff', '#ff00ff'], // 2
  ['#0080ff', '#00ff80', '#ff0080', '#ff8000', '#8000ff'], // 3
  ['#a4978e', '#852c2a', '#c1403d', '#AC713A', '#553322'], // 4
  ['#244a6c', '#ffc13b', '#ff6e40', '#3498DB', '#567766'], // 5
  ['#0022ff', '#244a6c', '#0080ff', '#003388'], // 6
  ['#3fc1c9', '#fce38a', '#fc5185', '#a17f89'], // 7
  ['#7A654E', '#ee99aa', '#AC713A', '#1868ae', '#0080ff', '#443388'], // 8
];

let headSwatch;
let nonHeadSwatch;
let backgroundColor;
let bodyColor;
let leftArmColor;
let rightArmColor;
let headColor;

const headshapes = ['block', 'eater', 'lenser', 'doubler', 'plus', 'devo'];
let headShape;

let noiseScaleH;
let noiseScaleV;

let v;
let h;
const canvasGrid = 16;
const width = window.innerWidth;
const height = window.innerHeight;
const canvasSize = Math.min(width, height);
const pixelSize = canvasSize / canvasGrid;
const pixelSizeInt = Math.round(pixelSize);
const canvasCenterInt = Math.round(pixelSize * (canvasGrid / 2));

function setup() {
  R = new Random(seed);
  noiseSeed(seed);

  const randomHeadShapeIdx = R.random_int(0, headshapes.length - 1);
  const randomIsColoredHead = R.random_dec();
  const randomSwatchIdx = R.random_int(1, swatches.length - 1);
  const swatchRandomizer = R.random_dec();
  const randomScaleWeightedH = R.random_dec();
  const randomScaleWeightedV = R.random_dec();

  headShape = headshapes[randomHeadShapeIdx];

  headColor = weightedRandom({'colored':0.2, 'bw':0.8}, randomIsColoredHead);
  nonHeadSwatch = buildBackSwatch(swatches, randomSwatchIdx, swatchRandomizer);
  headSwatch = buildHeadSwatch(swatches, randomSwatchIdx, swatchRandomizer);

  backgroundColor = nonHeadSwatch[0];
  bodyColor = nonHeadSwatch[1];
  leftArmColor = nonHeadSwatch[2];
  rightArmColor = nonHeadSwatch[3];

  noiseScaleH = weightedRandom({1:0.4, 2:0.3, 3:0.2, 4:0.1}, randomScaleWeightedH);
  noiseScaleV = weightedRandom({1:0.4, 2:0.3, 3:0.2, 4:0.1}, randomScaleWeightedV);

  noLoop();
  createCanvas(canvasSize, canvasSize);
}

function draw() {
  background(backgroundColor);
  const headMatrix = createHeadMatrix();

  drawHead(headMatrix, headSwatch);
  drawNeck(bodyColor);
  drawBody(bodyColor);
  drawArms(leftArmColor, rightArmColor);
}

function createHeadMatrix() {
  let headMatrix =[];
  if (headShape == 'block') {
    const b1 = new createVector(4, 11);
    createMultiBlock(headMatrix, [b1]);
  } else if (headShape == 'eater') {
    const b1 = new createVector(4, 5);
    const b2 = new createVector(6, 4);
    const b3 = new createVector(4, 2);
    createMultiBlock(headMatrix, [b1, b2, b3]);
  } else if (headShape == 'lenser') {
    const b1 = new createVector(4, 2);
    const b2 = new createVector(6, 4);
    const b3 = new createVector(4, 5);
    createMultiBlock(headMatrix, [b1, b2, b3]);
  } else if (headShape == 'doubler') {
    const b1 = new createVector(5, 4);
    const b2 = new createVector(3, 3);
    const b3 = new createVector(5, 4);
    createMultiBlock(headMatrix, [b1, b2, b3]);
  } else if (headShape == 'plus') {
    const b1 = new createVector(3, 3);
    const b2 = new createVector(6, 5);
    const b3 = new createVector(3, 3);
    createMultiBlock(headMatrix, [b1, b2, b3]);
  } else if (headShape == 'devo') {
    const b1 = new createVector(2, 3);
    const b2 = new createVector(4, 4);
    const b3 = new createVector(6, 4);
    createMultiBlock(headMatrix, [b1, b2, b3]);
  }
  return headMatrix;
}

function createMultiBlock(headMatrix, blocks) {
  let offsetY = 0;
  for (i in blocks) {
    createMatrixBlock(0, offsetY, blocks[i].x, blocks[i].y + offsetY, headMatrix);
    offsetY += blocks[i].y;
  }
  return headMatrix;
}

function createMatrixBlock(x, y, width, height, matrix) {
  for (v = y; v < height; v++) {
    matrix.push([]);
    for (h = x; h < width; h++) {
      const colorIndex = customNoise(h, v, noiseScaleH, noiseScaleV);
      matrix[v].push(colorIndex);
    }
  }
}

function drawHead(matrix, binarySwatch) {
  const vOffset = 1;
  for (v = 0; v < matrix.length; v++) {
    for (h = 0; h < matrix[v].length; h++) {
      drawBlock(h, v + vOffset, binarySwatch[matrix[v][h]]);
      drawBlock(-(h + 1), v + vOffset, binarySwatch[matrix[v][h]]);
    }
  }
}

function drawBlock(h, v, color) {
  const x = canvasCenterInt + h * pixelSizeInt;
  const y = canvasCenterInt - canvasGrid / 2 * pixelSizeInt + (pixelSizeInt + v * pixelSizeInt);
  fill(color);
  noStroke();
  rect(x, y, pixelSizeInt, pixelSizeInt);
}

function drawNeck (bodyColor) {
  fill(bodyColor);
  noStroke();
  rect(
    canvasCenterInt - pixelSizeInt,
    canvasCenterInt + pixelSizeInt * 5,
    pixelSizeInt * 2,
    pixelSizeInt
  );
}

function drawBody (bodyColor) {
  const bleed = pixelSizeInt;
  fill(bodyColor);
  noStroke();
  rect(
    canvasCenterInt - pixelSizeInt * 4,
    canvasCenterInt + pixelSizeInt * 6,
    pixelSizeInt * 8,
    pixelSizeInt * 2 + bleed
  );
}

function drawArms(leftArmColor, rightArmColor) {
  const bleed = pixelSizeInt;
  noStroke();
  fill(leftArmColor);
  rect(
    canvasCenterInt - 6 * pixelSizeInt,
    canvasCenterInt + pixelSizeInt * 7,
    pixelSizeInt,
    pixelSizeInt + bleed
  );
  fill(rightArmColor);
  rect(
    canvasCenterInt + 5 * pixelSizeInt,
    canvasCenterInt + pixelSizeInt * 7,
    pixelSizeInt,
    pixelSizeInt + bleed
  );
}

function buildBackSwatch (swatches, randomSwatchIdx, randomDecimal) {
  if (headColor == 'colored') {
    const backgroundColorIndex = round(randomDecimal);
    const fullbodyColorIndex = 1 - backgroundColorIndex;
    const backgroundColor = swatches[0][backgroundColorIndex];
    const fullbodyColor = swatches[0][fullbodyColorIndex];
    swatch = [backgroundColor, fullbodyColor, fullbodyColor, fullbodyColor];
  } else {
    const swatchSelected = swatches[randomSwatchIdx];
    swatch = swatchSelected.concat(swatches[0]);
    randomizeArray(swatch, randomDecimal);
    swatch.length = 4;
  }
  return swatch;
}

function buildHeadSwatch(swatches, randomSwatchIdx, randomDecimal) {
  if (headColor == 'colored') {
    const swatchSelected = swatches[randomSwatchIdx];
    headSwatch = randomizeArray(swatchSelected, randomDecimal);
    headSwatch.length = 2;
  } else {
    headSwatch = swatches[0];
  }
  return headSwatch;
};

function randomizeArray(array, randomDecimal) {
  let currentIndex = array.length;
  let randomIndex;

  while (0 !== currentIndex) {
    randomIndex = Math.floor(randomDecimal * currentIndex);
    currentIndex--;
    [array[currentIndex], array[randomIndex]] = [
      array[randomIndex], array[currentIndex]];
  }
  return array;
}

class Random {
  constructor(seed) {
    this.seed = seed
  }
  random_dec() {
    this.seed ^= this.seed << 13
    this.seed ^= this.seed >> 17
    this.seed ^= this.seed << 5
    return ((this.seed < 0 ? ~this.seed + 1 : this.seed) % 1000) / 1000
  }
  random_num(a, b) {
    return a+(b-a)*this.random_dec()
  }
  random_int(a, b) {
    return Math.floor(this.random_num(a, b+1))
  }
}

function customNoise (h, v, noiseScaleH, noiseScaleV) {
  return Math.round(noise(h/noiseScaleH, v/noiseScaleV));
}

function weightedRandom(prob, randomDecimal) {
  let i, sum=0, r=randomDecimal;
  const keys = Object.keys(prob);

  for (i = 0; i < keys.length; i++) {
    sum += prob[keys[i]];
    if (r <= sum) return keys[i];
  }
}