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
let R = new Random();
const randomSelection = getRandomPaletteAndBackground();

let fullPalete = randomSelection.colors;
let backgroundColour = randomSelection.background;
let revertedPalete = reverseArray(fullPalete);

function reverseArray(arr) {
  let reversed = [];
  for (let i = arr.length - 1; i >= 0; i--) {
    reversed.push(arr[i]);
  }
  return reversed;
}

let circleWidth = 13;
let amountOfCircles = 13;
let middleCircle = circleWidth / 2;
let radOffset = circleWidth * 2; // 30
let middleRainbow = (amountOfCircles * circleWidth) / 2; // 7 * 15 + 30
let quarterCircleComplete = false;
let rectComplete = false;
let pointIndex = 0; // Index of the point that we are currently drawing.
let points = []; // Points of the quarter circle.

let gridWidth = 4;
let gridHeight = 8;
let margin = 100; // Margin x and y pixel amount

// Keypressed
let showGrains = true;

let amountToRemove = R.random_int(5, 13);

let gridCoord;

// Save image
function keyPressed() {
  if (key == "s" || key == "S") {
    saveCanvas("rainbow_test", "png");
  }
}

function setup() {
  // pixelDensity(1);
  let cnv = createCanvas(1080, 1920);

  renderContent();

  cnv.style("width", "auto"); // Adjusts the display width
  cnv.style("height", "100%"); // Adjusts the display height
}

function renderContent() {
  background(backgroundColour);

  gridCoord = calculateGridCoordinates(gridWidth, gridHeight, margin);

  let randCoord = removeRandomElements(gridCoord, amountToRemove);

  // Sort coordinates by x and then by y
  randCoord.sort((a, b) => a.x - b.x || a.y - b.y);

  // Set start and ending points
  let startPoint = randCoord[0];
  if (startPoint.y > 1400) {
    startPoint = { x: 210, y: 1282.5 };
  }
  const endPoint = randCoord[randCoord.length - 1];

  // Find path for drawing
  const path = findPath(startPoint, endPoint, [startPoint], randCoord);

  // Draw path
  drawPathAndCurves(path);
  // cnv.style("width", "auto"); // Adjusts the display width
  // cnv.style("height", "100%"); // Adjusts the display height
}
function grains(s) {
  loadPixels();

  const d = pixelDensity();
  const pixelsCount = 4 * (width * d) * (height * d);

  for (let i = 0; i < pixelsCount; i += 4) {
    const grainAmount = R.random_num(-s, s);
    pixels[i] += grainAmount;
    pixels[i + 1] += grainAmount;
    pixels[i + 2] += grainAmount;
    pixels[i + 3] = 255; // Full opacity
  }

  updatePixels();
}

/**
 * Function to draw RAINBOWS in X and Y axis and also RAINBOW curves
 * @param {array} coordinates path to be drawn
 */
function drawPathAndCurves(path) {
  console.log(path);
  // First Point
  const startPointDirection =
    path[0].x === path[1].x
      ? path[0].y < path[1].y
        ? "up"
        : "down"
      : path[0].x < path[1].x
      ? "left"
      : "right";

  let newPoint;

  newPoint = { x: 0, y: path[0].y };

  const point0 = path[0];

  directionX = newPoint.x < point0.x ? true : false;
  drawCirclesX(
    newPoint.x - middleRainbow - circleWidth,
    newPoint.y,
    point0.x,
    point0.y,
    directionX
  );
  drawLeftDown(point0.x, point0.y, "left");

  // [] Draw y starting line
  // [] avoid curves when it comes to the right
  for (let i = 1; i < path.length - 1; i++) {
    // Draw path
    const point0 = path[i - 1];
    const point1 = path[i];
    const point2 = path[i + 1];

    let directionX, directionY;

    if (i === 1) {
      const point0 = path[0];
      const point1 = path[1];
      directionY = point0.y < point1.y ? true : false;
      drawCirclesY(point0.x, point0.y, point1.x, point1.y, directionY);
      // drawSegment(point0.x, point0.y, point1.x, point1.y); // This assumes you have a function to draw a segment between two points.
    }

    function calculateDistance(point1, point2) {
      let xDist = point2.x - point1.x;
      let yDist = point2.y - point1.y;
      return Math.sqrt(Math.pow(xDist, 2) + Math.pow(yDist, 2));
    }

    if (calculateDistance(point1, point2) > 10) {
      if (point1.x == point2.x) {
        directionY = point1.y < point2.y ? true : false;
        drawCirclesY(point1.x, point1.y, point2.x, point2.y, directionY);
      } else if (point1.y == point2.y) {
        directionX = point1.x < point2.x ? true : false;
        drawCirclesX(point1.x, point1.y, point2.x, point2.y, directionX);
      }
    }

    // Draw curves

    let inDirection, outDirection;

    // Calculate the direction of the curves using the last coordinate and the next coordinate as reference.
    if (point0.x === point1.x) {
      // vertical incoming
      inDirection = point0.y < point1.y ? "up" : "down";
    } else {
      // horizontal incoming
      inDirection = point0.x < point1.x ? "left" : "right";
    }

    if (point1.x === point2.x) {
      // vertical outgoing
      outDirection = point1.y < point2.y ? "down" : "up";
    } else {
      // horizontal outgoing
      outDirection = point1.x < point2.x ? "right" : "left";
    }

    let directionPair = inDirection + "-" + outDirection;

    let validPairs = ["up-right", "right-down", "down-left", "left-up"];

    if (!validPairs.includes(directionPair)) {
      // Swap inDirection and outDirection to match the validPairs
      directionPair = outDirection + "-" + inDirection;
    }

    // Only valid directions are passed up to this point
    switch (directionPair) {
      case "up-right":
        drawUpRight(point1.x, point1.y, inDirection);
        break;
      case "right-down":
        drawDownRight(point1.x, point1.y, inDirection);
        break;
      case "down-left":
        drawLeftDown(point1.x, point1.y, inDirection);
        break;
      case "left-up":
        drawLeftUp(point1.x, point1.y, inDirection);
        break;
      // Default just in case
      default:
        console.log(`No curve defined for direction pair ${directionPair}`);
    }
  }
  // Ending Point
  const endPointDirection =
    path[path.length - 1].x === path[path.length - 2].x
      ? path[path.length - 1].y < path[path.length - 2].y
        ? "up"
        : "down"
      : path[path.length - 1].x < path[path.length - 2].x
      ? "left"
      : "right";

  let endEdgePoint;
  if (endPointDirection === "up" || endPointDirection === "down") {
    endEdgePoint = { x: path[path.length - 1].x, y: height };
  } else {
    endEdgePoint = { x: width, y: path[path.length - 1].y };
  }

  const lastPoint = path[path.length - 2];
  if (endEdgePoint.x === lastPoint.x) {
    directionY = endEdgePoint.y > lastPoint.y ? true : false;
    drawCirclesY(
      lastPoint.x,
      lastPoint.y,
      endEdgePoint.x,
      endEdgePoint.y + middleRainbow + circleWidth + middleCircle,
      directionY
    );
  } else if (endEdgePoint.y === lastPoint.y) {
    directionX = endEdgePoint.x > lastPoint.x ? true : false;
    drawCirclesX(
      lastPoint.x,
      lastPoint.y,
      endEdgePoint.x + middleRainbow + circleWidth,
      endEdgePoint.y,
      directionX
    );
  }
}

/**
 * Draw a path avoiding "T" patterns as it draws,
 * this makes the calculation so that the drawing does not pass through the same point twice.
 * @param {object} starting point of drawing
 * @param {object} ending point of drawing
 * @param {array} path of coordinates to be calculated
 */
function findPath(currentPoint, endPoint, path, coord) {
  let randCoord = coord;
  // Base case: we've reached the end
  if (currentPoint === endPoint) {
    return path;
  }

  // Recursive case: try each neighbor that hasn't been visited yet
  const neighbors = getNeighbors(currentPoint, path, randCoord);
  for (const neighbor of neighbors) {
    if (!path.includes(neighbor)) {
      const newPath = [...path, neighbor];
      const result = findPath(neighbor, endPoint, newPath, randCoord);
      if (result) {
        return result;
      }
    }
  }

  // No valid path was found
  return null;
}

/**
 * Calculates neighboring points that have not yet been visited to avoid drawing the same point twice.
 * @param {object} point
 * @param {array} path
 * @returns {array}
 */
function getNeighbors(point, path, randCoord) {
  // For simplicity, we'll say two points are neighbors if they share either x or y coordinate
  // and the move is not a 180 degree turn
  return randCoord.filter((p) => {
    const prevPoint = path[path.length - 2];
    if (prevPoint) {
      const backtracking =
        (prevPoint.x === p.x && prevPoint.y !== point.y) ||
        (prevPoint.y === p.y && prevPoint.x !== point.x);
      if (backtracking) {
        return false;
      }
    }
    return p.x === point.x || p.y === point.y;
  });
}

/**
 * Remove some random elements from the grid array to be drawn after
 * @param {array} gridCoord Grid coordinates
 * @returns {array}
 */
function removeRandomElements(gridCoord, amount) {
  // Determine how many elements to remove
  let newArr = gridCoord;

  for (let i = 0; i < amount; i++) {
    // Choose a random index to remove
    const index = Math.floor(R.random_num(0, newArr.length));

    // Remove the element at the chosen index
    newArr.splice(index, 1);
  }

  // Return the modified newArray
  return newArr;
}

// *****  GRID COORDINATES FUNCTIONS *****
//  *****************************************

/**
 * Calculate grid coordinates using canvas size as reference
 * @returns middle point of each grid to use it as coordinates
 */

// pass gridWidth and gridHeight as parameters to make grids variables

function calculateGridCoordinates(gridAmountWidth, gridAmountHeight, margin) {
  let coordinates = [];

  let gridW = (width - 2 * margin) / gridAmountWidth;
  let gridH = (height - 2 * margin) / gridAmountHeight;

  // Calculate midpoints
  for (let i = 0; i < gridAmountWidth; i++) {
    for (let j = 0; j < gridAmountHeight; j++) {
      let midX = margin + i * gridW + gridW / 2;
      let midY = margin + j * gridH + gridH / 2;
      coordinates.push({ x: midX, y: midY });
    }
  }
  return coordinates;
}

// ***** RAINBOW TRIGONOMETRIC FUNCTIONS *****
//  *****************************************

function calculateQuarterCirclePoints(
  radius,
  centerX,
  centerY,
  cosMultiplier,
  sinMultiplier
) {
  let numPoints = 1000; // Number of points to calculate. Increase for more precision.
  let angleStep = HALF_PI / numPoints;
  let points = []; // Array to hold point objects

  for (let i = 0; i <= numPoints; i++) {
    let angle = angleStep * i;
    let x = centerX + radius * cosMultiplier * cos(angle);
    let y = centerY + radius * sinMultiplier * sin(angle);

    // Add the point object to the array
    points.push({
      x: x,
      y: y,
    });
  }
  return points;
}

// ***** DRAWING FUNCTIONS *****
//  *****************************************

function drawFirstPointY(startX, startY, endX, endY, colorDirection) {
  let middleStartX = startX - middleRainbow;
  let middleEndX = endX - middleRainbow;

  for (let i = 0; i < fullPalete.length; i++) {
    // circleWidth * i add the distance between each circle to not overlap
    strokeWeight(circleWidth);
    stroke(colorDirection ? revertedPalete[i] : fullPalete[i]);
    if (colorDirection) {
      line(
        middleStartX + circleWidth * i + middleCircle,
        startY,
        middleEndX + circleWidth * i + middleCircle,
        endY
      );
    } else {
      line(
        middleStartX + circleWidth * i + middleCircle,
        startY,
        middleEndX + circleWidth * i + middleCircle,
        endY
      );
    }
  }
}

// Draw Straigh Line Rainbow function
function drawCirclesX(startX, startY, endX, endY, colorDirection) {
  let middleStartY = startY - middleRainbow;
  let middleEndY = endY - middleRainbow;
  for (let i = 0; i < fullPalete.length; i++) {
    // circleWidth * i add the distance between each circle to not overlap
    strokeWeight(circleWidth);
    stroke(colorDirection ? fullPalete[i] : revertedPalete[i]);

    if (colorDirection) {
      line(
        startX + middleRainbow + circleWidth,
        middleStartY + circleWidth * i + middleCircle,
        endX - middleRainbow - circleWidth,
        middleEndY + circleWidth * i + middleCircle
      );
    } else {
      line(
        startX - middleRainbow - circleWidth,
        middleStartY + circleWidth * i + middleCircle,
        endX + middleRainbow + circleWidth,
        middleEndY + circleWidth * i + middleCircle
      );
    }

    // circle(x, y + circleWidth * i, circleWidth);
  }
}

function drawCirclesY(startX, startY, endX, endY, colorDirection) {
  let middleStartX = startX - middleRainbow;
  let middleEndX = endX - middleRainbow;

  for (let i = 0; i < fullPalete.length; i++) {
    // circleWidth * i add the distance between each circle to not overlap
    strokeWeight(circleWidth);
    stroke(colorDirection ? revertedPalete[i] : fullPalete[i]);
    if (colorDirection) {
      line(
        middleStartX + circleWidth * i + middleCircle,
        startY + middleRainbow + circleWidth + middleCircle,
        middleEndX + circleWidth * i + middleCircle,
        endY - middleRainbow - circleWidth
      );
    } else {
      line(
        middleStartX + circleWidth * i + middleCircle,
        startY - middleRainbow - circleWidth,
        middleEndX + circleWidth * i + middleCircle,
        endY + middleRainbow + circleWidth
      );
    }
  }
}

// Curve functions
function drawUpRight(x, y, inDirection) {
  for (let i = 0; i < fullPalete.length; i++) {
    //NOTE - Use the x and y values of the las position before drawing

    let color = inDirection == "right" ? revertedPalete : fullPalete;

    let points = calculateQuarterCirclePoints(
      circleWidth * i + radOffset,
      x + middleRainbow + circleWidth + middleCircle,
      y - middleRainbow - circleWidth - middleCircle,
      -1,
      1
    );
    for (let point of points) {
      noStroke();
      fill(color[i]);
      circle(point.x, point.y, circleWidth);
    }
  }
}

function drawLeftDown(x, y, inDirection) {
  for (let i = 0; i < revertedPalete.length; i++) {
    //NOTE - Use the x and y values of the las position before drawing

    let color = inDirection == "left" ? revertedPalete : fullPalete;

    let points = calculateQuarterCirclePoints(
      circleWidth * i + radOffset,
      x - middleRainbow - circleWidth - middleCircle,
      y + middleRainbow + circleWidth + middleCircle,
      1,
      -1
    );
    for (let point of points) {
      noStroke();
      fill(color[i]);
      circle(point.x, point.y, circleWidth);
    }
  }
}

function drawLeftUp(x, y, inDirection) {
  for (let i = 0; i < fullPalete.length; i++) {
    //NOTE - Use the x and y values of the las position before drawing

    let color = inDirection == "up" ? revertedPalete : fullPalete;

    let points = calculateQuarterCirclePoints(
      circleWidth * i + radOffset,
      x - middleRainbow - circleWidth - middleCircle,
      y - middleRainbow - circleWidth - middleCircle,
      1,
      1
    );
    for (let point of points) {
      noStroke();
      fill(color[i]);
      circle(point.x, point.y, circleWidth);
    }
  }
}

function drawDownRight(x, y, inDirection) {
  for (let i = 0; i < fullPalete.length; i++) {
    //NOTE - Use the x and y values of the las position before drawing

    let color = inDirection == "down" ? revertedPalete : fullPalete;

    let points = calculateQuarterCirclePoints(
      circleWidth * i + radOffset,
      x + middleRainbow + circleWidth + middleCircle,
      y + middleRainbow + circleWidth + middleCircle,
      -1,
      -1
    );
    for (let point of points) {
      noStroke();
      fill(color[i]);
      circle(point.x, point.y, circleWidth);
    }
  }
}

function getRandomPaletteAndBackground() {
  const palettes = [
    {
      name: "RAINBOW",
      colors: [
        "#ee1c25",
        "#ef4822",
        "#f16623",
        "#f9a122",
        "#ffde17",
        "#becc36",
        "#71bf44",
        "#4da291",
        "#0188c9",
        "#616fb4",
        "#824fa0",
        "#a859a3",
        "#ce63a7",
      ],
      backgrounds: ["#E4E4E4", "#101010"],
    },
    {
      name: "WOODSTOCK",
      colors: [
        "#372B77",
        "#29438C",
        "#1A5BA2",
        "#0C73B7",
        "#118497",
        "#169678",
        "#1BA758",
        "#65BF54",
        "#AFD650",
        "#F9EE4C",
        "#EFB054",
        "#E4725B",
        "#DA3463",
      ],
      backgrounds: ["#E4E4E4", "#101010"],
    },
    {
      name: "IRIDESCENCE",
      colors: [
        "#1a00ff",
        "#0038ff",
        "#006fff",
        "#00a7ff",
        "#00b3ca",
        "#00bc8b",
        "#00c743",
        "#00d755",
        "#9ee567",
        "#fff375",
        "#ff9393",
        "#ff5e9d",
        "#fe0475",
      ],
      backgrounds: ["#E4E4E4", "#101010"],
    },
    {
      name: "SUNSET",
      colors: [
        "#00a4f2",
        "#00c2e8",
        "#00d2e3",
        "#00ded2",
        "#79e9c1",
        "#c3f5ad",
        "#d9f164",
        "#ebed00",
        "#ffcd00",
        "#ffb100",
        "#ff9300",
        "#ff5900",
        "#ff0037",
      ],
      backgrounds: ["#E4E4E4", "#101010"],
    },
    {
      name: "SUNDOWN",
      colors: [
        "#602F4F",
        "#874B61",
        "#A07677",
        "#AE9D92",
        "#A6BDAF",
        "#93CCC3",
        "#7BC7DF",
        "#39B6D1",
        "#00A1D3",
        "#0E7FC1",
        "#125CA7",
        "#284086",
        "#1B204B",
      ],
      backgrounds: ["#101010"],
    },
    {
      name: "ICEWORLD",
      colors: [
        "#f7fcfd",
        "#f2fafc",
        "#edf7f9",
        "#edf7f9",
        "#e8f6f9",
        "#e0f3f4",
        "#dbf1f2",
        "#d3edf1",
        "#cbeaf1",
        "#c3e7f1",
        "#bbe4ef",
        "#ace0ef",
        "#a0dcee",
      ],
      backgrounds: ["#daecf1", "#101010"],
    },
    {
      name: "CHROME",
      colors: [
        "#414042",
        "#58595B",
        "#6D6E71",
        "#818284",
        "#949598",
        "#A7A9AB",
        "#BCBEC0",
        "#A7A9AB",
        "#949598",
        "#818284",
        "#6D6E71",
        "#58595B",
        "#414042",
      ],
      backgrounds: ["#343435"],
    },
    {
      name: "PEPE",
      colors: [
        "#FF0000",
        "#FF0000",
        "#df0821",
        "#ca0e37",
        "#951b6d",
        "#5f29a4",
        "#2A37DB",
        "#2d57b5",
        "#31768f",
        "#349569",
        "#35a25a",
        "#37B543",
        "#37B543",
      ],
      backgrounds: ["#E4E4E4", "#101010"],
    },
    {
      name: "VOID",
      colors: [
        "#151515",
        "#1b1b1b",
        "#262626",
        "#303030",
        "#3a3a3a",
        "#444444",
        "#4e4e4e",
        "#5a5a5a",
        "#636363",
        "#6d6d6d",
        "#757575",
        "#7d7d7d",
        "#838383",
      ],
      backgrounds: ["#101010"],
    },
    {
      name: "BIPOLAR",
      colors: [
        "#151515",
        "#1b1b1b",
        "#262626",
        "#303030",
        "#3a3a3a",
        "#444444",
        "#4e4e4e",
        "#ef1462",
        "#fbad3d",
        "#fbee00",
        "#3ac242",
        "#0075bd",
        "#392a7b",
      ],
      backgrounds: ["#101010"],
    },
    {
      name: "WE ARE SO BACK",
      colors: [
        "#d8e2d7",
        "#cce0cb",
        "#c1e0be",
        "#b6dfb1",
        "#a9dfa4",
        "#9ddc98",
        "#92dc8a",
        "#84db7c",
        "#76d970",
        "#67d960",
        "#58d850",
        "#47d740",
        "#2fd52d",
      ],
      backgrounds: ["#E4E4E4"],
    },
    {
      name: "IT'S OVER",
      colors: [
        "#e6d8d6",
        "#e8caca",
        "#e9bdbd",
        "#eab1af",
        "#eaa4a4",
        "#ed9696",
        "#ec8a8a",
        "#ed7c7c",
        "#ee6062",
        "#ee4344",
        "#ee3138",
        "#ed1d26",
        "#e11722",
      ],
      backgrounds: ["#E4E4E4"],
    },
    {
      name: "BANDERSNATCH",
      colors: [
        "#70c6bd",
        "#5ec0b5",
        "#54b9ac",
        "#4dabb2",
        "#469db8",
        "#3d8bb9",
        "#3579bc",
        "#3969af",
        "#4c5aa5",
        "#59489d",
        "#673594",
        "#502d7d",
        "#392467",
      ],
      backgrounds: ["#1c142f"],
    },
  ];

  // Randomly select a palette
  const paletteNames = Object.keys(palettes);
  const randomIndex = R.random_int(0, palettes.length - 1);
  const randomPaletteName = paletteNames[randomIndex];
  const selectedPalette = palettes[randomPaletteName];

  // Randomly select a background from the chosen palette
  const randomBackground =
    selectedPalette.backgrounds[
      Math.floor(R.random_dec() * selectedPalette.backgrounds.length)
    ];
  console.log("->>>>>>>>", selectedPalette);
  return {
    name: randomPaletteName,
    colors: selectedPalette.colors,
    background: randomBackground,
  };
}