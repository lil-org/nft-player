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
    this.prngA = new sfc32(tokenData.hash.substr(2, 32));
    this.prngB = new sfc32(tokenData.hash.substr(34, 32));
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

  random_choice(list) {
    return list[this.random_int(0, list.length - 1)];
  }
  random_p(...args) {
    // No arguments: return a random decimal between 0 and 1
    if (args.length === 0) {
      return this.random_dec();
    }

    // One argument: check if it's a number or an array
    if (args.length === 1) {
      if (Array.isArray(args[0])) {
        // If it's an array, return a random element from the array
        return args[0][this.random_int(0, args[0].length - 1)];
      } else {
        // If it's a number, return a random number between 0 and the number (exclusive)
        return this.random_num(0, args[0]);
      }
    }

    // Two arguments: return a random number between the first and second argument (exclusive of the second argument)
    if (args.length === 2) {
      return this.random_num(args[0], args[1]);
    }

    // If more than two arguments, or invalid argument types, return undefined or throw an error
    return undefined;
  }
}
let R;
// Function to generate a random gradient color
function randomGradientColor() {
  const color1 = color(R.random_p(255), R.random_p(255), R.random_p(255));
  const color2 = color(R.random_p(255), R.random_p(255), R.random_p(255));
  return { color1, color2 };
}
// Initialize variables
let symbols = []; // Array to store symbols
let gradientColors = []; // Array to store gradient colors
let numGradients = 0; // Number of gradients
let numRows = 0; // Number of rows in the grid
let numCols = 0; // Number of columns in the grid
let symbolIndex = 0; // Index for iterating through symbols
const drawInterval = 100; // Interval for drawing symbols
let animateValue = 1000; // Start animation value at 1000
let targetValue; // Target value for symbols
let str; // Stroke weight for symbols
let alignSymbols; // Set to true for perfect alignment, false for random
let useSolidColors = []; // Set to true for solid colors, false for gradients
let colorsUsed = [];
let selectedWeight;
// Options for target values
const targetValueOptions = [90, 60, 30];

// Options for stroke width
const stroptions = [
  { str: 0.4, probability: 0.1 }, // BALANCED
  { str: 0.8, probability: 0.2 }, // BOLD
  { str: 1, probability: 0.05 }, // ULTRABOLD
];

// Options for color usage (solid or gradient)
const colorOptions = [
  { useSolidColors: true, probability: 0.1 }, // FLAT
  { useSolidColors: false, probability: 0.9 }, // BLEND
];
// Options for font weight
const weightOptions = [
  { weight: 100, probability: 0.1, title: "SKINNY" }, // THICK
  { weight: 300, probability: 0.85, title: "STANDARD" }, // STANDARD
  { weight: 600, probability: 0.05, title: "CHUNKY" }, // SLIM
];

// Options for the number of gradients "BLENDS"
const gradientOptions = [
  { numGradients: 1, probability: 0.05 }, // ONE
  { numGradients: 2, probability: 0.1 }, // TWO
  { numGradients: 3, probability: 0.15 }, // THREE
  { numGradients: 4, probability: 0.2 }, // FOUR
  { numGradients: 5, probability: 0.25 }, // FIVE
  { numGradients: 6, probability: 0.3 }, // SIX
  { numGradients: 7, probability: 0.35 }, // SEVEN
  { numGradients: 8, probability: 0.4 }, // EIGHT
  { numGradients: 9, probability: 0.45 }, // NINE
];

// Options for the number of rows in the grid // "MARKS"
const rowOptions = [
  { numRows: 1, probability: 0.1 }, // MIN
  { numRows: 2, probability: 0.2 }, // MED
  { numRows: 3, probability: 0.3 }, // MAX
  { numRows: 4, probability: 0.35 }, // SUPERMAX
];

// Options for the number of columns in the grid "LINE"
const colOptions = [
  { numCols: 7, probability: 0.1 }, // TIGHT
  { numCols: 9, probability: 0.2 }, // MID
  { numCols: 11, probability: 0.4 }, // WIDE
];

// Options for cell size percentage
const cellSizeProbabilities = [
  { sizePercentage: 5, probability: 0.1 }, //
];

// Setup function - runs once at the start
function setup() {
  R = new Random();
  str = selectRandomOption(stroptions).str; // Initialize stroke weight
  createCanvas(windowWidth, windowWidth); // Create a canvas that fills the window
  pixelDensity(2); // Sets the pixel density to 2

  alignSymbols = R.random_choice([true, false]);
  targetValue = R.random_choice(targetValueOptions); // Initialize target value
  const selectedColorOption = selectRandomOption(colorOptions);
  selectedWeight = selectRandomOption(weightOptions);
  useSolidColors = selectedColorOption.useSolidColors; // Use solid colors based on probability
  blendMode(SCREEN); // Set blending mode to SCREEN
  textFont("Arial"); // Set text font
  background(0); // Set background color to black
  generateSymbols(); // Generate the symbols
  shuffle(symbols, true); // Shuffle the symbols randomly
}

// Draw function - runs continuously to animate
function draw() {
  if (symbolIndex < symbols.length) {
    const { x, y, angle, sizePercentage, color, targetValue } =
      symbols[symbolIndex];
    drawSymbol(x, y, angle, sizePercentage, color, targetValue); // Call drawSymbol after updating animateValue
    symbolIndex++;
  }
}

// Function to randomly select an option based on probability
function selectRandomOption(options) {
  let totalProbability = options.reduce(
    (total, option) => total + option.probability,
    0
  );
  let randomValue = R.random_num(0, totalProbability);
  let cumulativeProbability = 0;
  for (let option of options) {
    cumulativeProbability += option.probability / totalProbability;
    if (randomValue < cumulativeProbability) {
      return option;
    }
  }
  return options[options.length - 1];
}

// Function to generate symbols
function generateSymbols() {
  const selectedGradientOption = selectRandomOption(gradientOptions);
  numGradients = selectedGradientOption.numGradients;

  const selectedRowOption = selectRandomOption(rowOptions);
  numRows = selectedRowOption.numRows;

  const selectedColOption = selectRandomOption(colOptions);
  numCols = selectedColOption.numCols;

  const selectedSizePercentage = selectRandomOption(cellSizeProbabilities);
  const cellSizePercentage = selectedSizePercentage.sizePercentage;

  gradientColors = [];
  for (let i = 0; i < numGradients; i++) {
    gradientColors.push(randomGradientColor());
  }

  generateFullGridSymbols(cellSizePercentage);
}
function countUniqueColors(colorArray) {
  const uniqueColors = new Set(colorArray);
  return uniqueColors.size;
}
// Function to generate symbols in a full grid
function generateFullGridSymbols(cellSizePercentage) {
  const minGridWidthPercentage = 50;

  const minCols = ceil(
    ((minGridWidthPercentage / cellSizePercentage) * 100) / 100
  );
  const maxCols = floor(
    ((width / ((width * cellSizePercentage) / 100)) * 100) / 100
  );

  const angleIncrements = PI / 1;
  const possibleAngles = [
    0,
    angleIncrements,
    2 * angleIncrements,
    3 * angleIncrements,
    4 * angleIncrements,
    5 * angleIncrements,
    6 * angleIncrements,
    7 * angleIncrements,
  ];

  const gridWidth = numCols * ((width * cellSizePercentage) / 100);
  const gridHeight = numRows * ((height * cellSizePercentage) / 100);
  const cellWidth = (width * cellSizePercentage) / 100;
  const cellHeight = (height * cellSizePercentage) / 100;

  const startX = (width - gridWidth) / 2 + cellWidth / 2;
  const startY = (height - gridHeight) / 2.1 + cellHeight / 2.1;

  for (let i = 0; i < numRows; i++) {
    for (let j = 0; j < numCols; j++) {
      let x;
      let y;

      if (alignSymbols) {
        // Calculate x and y for perfect alignment // GAP
        x = j * cellWidth + startX;
        y = i * cellHeight + startY;
      } else {
        // OVERLAP
        // Calculate x and y with random variation for random alignment
        x = j * cellWidth + startX;
        y = i * cellHeight + startY + R.random_int(-10, 10);
      }

      const angle = R.random_choice(possibleAngles);
      const sizePercentage = cellSizePercentage;
      const depth = R.random_int(0, 4);
      const color = useSolidColors
        ? randomSolidColor()
        : getRandomGradientColor();
      const targetValue =
        R.random_p() < 0.2
          ? targetValueOptions[0]
          : R.random_choice(targetValueOptions);
      if (useSolidColors) {
        colorsUsed.push(color);
      } else {
        colorsUsed.push(color.color1);
        colorsUsed.push(color.color2);
      }

      symbols.push({ x, y, angle, sizePercentage, depth, color, targetValue });
    }
  }
}

// Function to generate a random solid color
function randomSolidColor() {
  return color(R.random_p(255), R.random_p(255), R.random_p(255));
}

// Function to get a random gradient color from the array
function getRandomGradientColor() {
  return gradientColors[Math.floor(R.random_int(0, gradientColors.length - 1))];
}

// Function to draw a symbol
function drawSymbol(x, y, angle, sizePercentage, color, targetValue) {
  push();
  translate(x, y);
  rotate(angle);
  textSize((width * sizePercentage) / selectedWeight.weight);
  textAlign(CENTER, CENTER);

  for (let i = 0; i < (width * sizePercentage) / targetValue; i++) {
    let c = useSolidColors
      ? color
      : lerpColor(
          color.color1,
          color.color2,
          map(i, 2, (width * sizePercentage) / 200, 0, numGradients - 2)
        );
    stroke(c);
    strokeWeight(str);
    text("®", 0, i - (width * sizePercentage) / 400);
  }

  pop();
}