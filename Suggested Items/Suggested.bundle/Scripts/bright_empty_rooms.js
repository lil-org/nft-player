var seed = parseInt(tokenData.hash.slice(0, 16), 16);

let projectNumber = Math.floor(parseInt(tokenData.tokenId) / 1000000);
let walletCount = parseInt(tokenData.tokenId) % 1000000;

let vertX = [0.59375, 0.40625, 0.59375, 0.40625, 0.59375, 0.40625];
let vertY = [0.75, 0.75, 0.5, 0.5, 0.25, 0.25];
let horiX = [0.75, 0.5, 0.25, 0.75, 0.5, 0.25];
let horiY = [0.59375, 0.59375, 0.59375, 0.40625, 0.40625, 0.40625];
let vertical;
let sixX, sixY;
let multiplyOn = false;

let mostShapeArr = [0, 0, 0, 0, 0, 0];
let shapesNames = ["Sun", "Shard", "Cargo", "Hive", "Pyramid", "Moon"];

p5.disableFriendlyErrors = true;

let rezs = [150, 200, 300];
let rezIndex = 2;

let lineThickness;
let lineDepth;
let lineLength;
let lineSpacing;
let depth = 255.0;

let displayRed = true;
let displayGreen = true;
let displayBlue = true;

let stillLifeDim = -1;
let stillLifeDepthNeg = 0;
let stillLifeDepthPos = 0;
let depthScalar = 1.0;
let speedScalar = 1.0;
let speeds = [0.25, 0.5, 1.0, 2.0, 0.0];
let speedIndex = 2;
let SEED = 0;
let lengthScalar = 1.3;

let combination = [];

let angle = 0.0;

let alphapix;
let overlay;
let cityNum;

let cla, cny, cberlin, ccdmx, clondon, ctokyo;
let s1, s2, s3, s4;
let sc;
let foregrounds = [];
let bColor = 246;

let shapes = [];

let gl;
let stillLifePO2 = 2;
let ext;
let pgl;
let viewDiagram = false;
let infoOverlay = false;
let viewMatrix;
let modelViewMatrix;
let dispMapTexture;

let CDMXSpin = 1;

const vertCode = `precision highp float;
uniform mat4 uViewMatrix;
uniform mat4 uProjectionMatrix;
uniform mat4 uModelViewMatrix;
uniform mat4 uModelViewProjectionMatrix;
uniform vec2 canvasSize;
uniform float stillLifeDim;
uniform float stillLifePO2;
uniform float stillLifeDepthNeg;
uniform float stillLifeDepthPos;
uniform float depthScalar;
uniform float lineThickness;
uniform float lineDepth;
uniform float lineLength;
uniform vec3 color;
uniform sampler2D displacementMap;
attribute vec3 coordinates;

float map(float value, float min1, float max1, float min2, float max2)
{
    return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}

struct Line
{
    vec3 start;
    vec3 end;
};

Line getLineFromDisplacementMap(int x_origin, int y_origin)
{
    Line l;

    vec2 imageCoords = vec2(x_origin, y_origin);
    imageCoords.x += .5;
    imageCoords.y += .5;

    vec2 samplePos = imageCoords.xy/stillLifePO2;
    vec4 dispMapColor = texture2D(displacementMap, samplePos);
    float maxEdge = max(canvasSize.x, canvasSize.y);

    float x = float(x_origin);
    float y = float(y_origin);
    float z = map(dot(dispMapColor.xyz, color), 0.0, 1.0, -stillLifeDepthNeg, stillLifeDepthPos);

    l.start.x = map(x, 0.0, stillLifeDim, -maxEdge / 2.0, maxEdge / 2.0);
    l.start.y = map(y, 0.0, stillLifeDim, -maxEdge / 2.0, maxEdge / 2.0);
    l.start.z = -z;

    l.end.x = map(x, 0.0, stillLifeDim, -maxEdge / 2.0, maxEdge / 2.0) - lineDepth;
    l.end.y = map(y, 0.0, stillLifeDim, -maxEdge / 2.0, maxEdge / 2.0) - lineDepth;
    l.end.z = -lineLength - z;

    return l;
}

void main()
{
    bool lineStart = false;
    if (coordinates.y == 0.0) lineStart = true;
    if (coordinates.y == 1.0) lineStart = true;
    if (coordinates.y == 2.0) lineStart = false;
    if (coordinates.y == 3.0) lineStart = true;
    if (coordinates.y == 4.0) lineStart = false;
    if (coordinates.y == 5.0) lineStart = false;

    int imageCoordsY = int(floor(coordinates.x / stillLifeDim));
    int imageCoordsX = int(floor(coordinates.x - float(imageCoordsY) * stillLifeDim));

    Line l = getLineFromDisplacementMap(imageCoordsX, imageCoordsY);

    vec3 vertexPosition;
    if (lineStart) {
        vertexPosition = l.start;
    } else {
        vertexPosition = l.end;
    }

    vec4 finalPos = vec4(vertexPosition, 1.0);
    finalPos = uModelViewProjectionMatrix * finalPos;

    vec4 projLineStart = uModelViewProjectionMatrix * vec4(l.start, 1.0);
    vec4 projLineEnd = uModelViewProjectionMatrix * vec4(l.end, 1.0);
    vec2 lineDirection = projLineStart.xy - projLineEnd.xy;
    lineDirection = vec2(-lineDirection.y, lineDirection.x);
    float maxEdge = max(canvasSize.x, canvasSize.y);
    lineDirection /= canvasSize / maxEdge;
    vec2 displacement = normalize(lineDirection);
    displacement /= canvasSize;
    displacement *= lineThickness;

    if (coordinates.y == 0.0) finalPos.xy -= displacement;
    if (coordinates.y == 2.0) finalPos.xy -= displacement;
    if (coordinates.y == 5.0) finalPos.xy -= displacement;
    if (coordinates.y == 1.0) finalPos.xy += displacement;
    if (coordinates.y == 3.0) finalPos.xy += displacement;
    if (coordinates.y == 4.0) finalPos.xy += displacement;

    finalPos.z = 0.0;

    gl_Position = finalPos;
}
`;

const fragCode = `precision highp float;
uniform vec3 color;
void main() {
    gl_FragColor = vec4(color, 1.0);
}
`;

let triangle_buffer;
let numTris;

function setupGeometry() {
  let triangles = [];
  numTris = 0;
  for (let y = 0; y < rezs[rezIndex]; y += 1) {
    for (let x = 0; x < rezs[rezIndex]; x += 1) {
      triangles.push(x + y * stillLifeDim, 0, 0);
      triangles.push(x + y * stillLifeDim, 1, 0);
      triangles.push(x + y * stillLifeDim, 2, 0);
      triangles.push(x + y * stillLifeDim, 3, 0);
      triangles.push(x + y * stillLifeDim, 4, 0);
      triangles.push(x + y * stillLifeDim, 5, 0);
      numTris += 6;
    }
  }
  triangle_buffer = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, triangle_buffer);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(triangles), gl.STATIC_DRAW);
  gl.bindBuffer(gl.ARRAY_BUFFER, null);
}

function setupShapes() {
  let sss = 0.3;
  shapes = [];
  let currSet = all_sets[walletCount];
  mostShapeArr = [0, 0, 0, 0, 0, 0];
  if (vertical) {
    sixX = vertX;
    sixY = vertY;
  } else {
    sixX = horiX;
    sixY = horiY;
  }
  let currShapesArr = [];
  for (let currCombo = 0; currCombo < currSet.length; currCombo++) {
    setupCombination(currSet[currCombo]);
    for (let i = 0; i < combination.length; i++) {
      currShapesArr.push(
        new VShape(
          -stillLifeDim * sixX[currCombo],
          -stillLifeDim * sixY[currCombo],
          stillLifeDim * sss,
          combination[i]
        )
      );
    }
    shapes.push(currShapesArr);
    currShapesArr = [];
  }
  theDetails();
}

function theDetails() {
  let maxSide = max(width, height);
  if (maxSide < 400) {
    depthScalar = map(maxSide, 50, 400, 0.05, 0.3);
  } else {
    depthScalar = map(maxSide, 400, 3840, 0.3, 2.0);
  }
  stillLifeDepthNeg = 255.0 / 4;
  stillLifeDepthPos = 255.0 / 4;
  lengthScalar = 1.0;
  let cityDigit = mostShapeArr.indexOf(Math.max(...mostShapeArr)) + 1;
  if (cityDigit == 1) {
    tokyoParams();
  } else if (cityDigit == 2) {
    berlinParams();
  } else if (cityDigit == 3) {
    londonParams();
  } else if (cityDigit == 4) {
    nycParams();
  } else if (cityDigit == 5) {
    cdmxParams();
  } else {
    laParams();
  }
}

let shaderProgram;

function setupShaders() {
  let vertShader = gl.createShader(gl.VERTEX_SHADER);
  gl.shaderSource(vertShader, vertCode);
  gl.compileShader(vertShader);

  const vertError = gl.getShaderInfoLog(vertShader);
  if (vertError.length > 0) {
    throw vertError;
  }

  let fragShader = gl.createShader(gl.FRAGMENT_SHADER);
  gl.shaderSource(fragShader, fragCode);
  gl.compileShader(fragShader);

  const fragError = gl.getShaderInfoLog(fragShader);
  if (fragError.length > 0) {
    throw fragError;
  }

  shaderProgram = gl.createProgram();
  gl.attachShader(shaderProgram, vertShader);
  gl.attachShader(shaderProgram, fragShader);
  gl.linkProgram(shaderProgram);
}

function createDisplacementMapTexture() {
  dispMapTexture = gl.createTexture();
  while (stillLifePO2 < stillLifeDim) {
    stillLifePO2 *= 2;
  }
}

function transferDisplacementMap() {
  let img = alphapix.get();
  img.loadPixels();

  let uvTexture = Array(stillLifePO2 * stillLifePO2 * 4).fill(255);

  const randomStuff = new Uint8Array(uvTexture);
  for (let x = 0; x < stillLifeDim; ++x) {
    for (let y = 0; y < stillLifeDim; ++y) {
      const index1 = 4 * (y * stillLifePO2 + x);
      const index2 = 4 * (y * stillLifeDim + x);
      randomStuff[index1 + 0] = img.pixels[index2 + 0];
      randomStuff[index1 + 1] = img.pixels[index2 + 1];
      randomStuff[index1 + 2] = img.pixels[index2 + 2];
    }
  }

  gl.bindTexture(gl.TEXTURE_2D, dispMapTexture);
  gl.texImage2D(
    gl.TEXTURE_2D,
    0,
    gl.RGBA,
    stillLifePO2,
    stillLifePO2,
    0,
    gl.RGBA,
    gl.UNSIGNED_BYTE,
    randomStuff
  );
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
  gl.bindTexture(gl.TEXTURE_2D, null);

  gl.activeTexture(gl.TEXTURE2);
  gl.bindTexture(gl.TEXTURE_2D, dispMapTexture);

  const displaceMapLocation = gl.getUniformLocation(
    shaderProgram,
    "displacementMap"
  );
  gl.uniform1i(displaceMapLocation, 2);
}

function setMatrices() {
  const viewMatrix = this._renderer._curCamera.cameraMatrix;
  const projectionMatrix = this._renderer.uPMatrix;
  const modelViewMatrix = this._renderer.uMVMatrix;
  const modelViewProjectionMatrix = modelViewMatrix.copy();
  modelViewProjectionMatrix.mult(projectionMatrix);

  gl.uniformMatrix4fv(
    gl.getUniformLocation(shaderProgram, "uViewMatrix"),
    false,
    viewMatrix.mat4
  );
  gl.uniformMatrix4fv(
    gl.getUniformLocation(shaderProgram, "uProjectionMatrix"),
    false,
    projectionMatrix.mat4
  );
  gl.uniformMatrix4fv(
    gl.getUniformLocation(shaderProgram, "uModelViewMatrix"),
    false,
    modelViewMatrix.mat4
  );
  gl.uniformMatrix4fv(
    gl.getUniformLocation(shaderProgram, "uModelViewProjectionMatrix"),
    false,
    modelViewProjectionMatrix.mat4
  );
}

function setUniforms() {
  gl.uniform2f(
    gl.getUniformLocation(shaderProgram, "canvasSize"),
    width,
    height
  );
  gl.uniform1f(
    gl.getUniformLocation(shaderProgram, "stillLifeDim"),
    stillLifeDim
  );
  gl.uniform1f(
    gl.getUniformLocation(shaderProgram, "stillLifePO2"),
    stillLifePO2
  );
  gl.uniform1f(
    gl.getUniformLocation(shaderProgram, "depthScalar"),
    depthScalar
  );
  gl.uniform1f(
    gl.getUniformLocation(shaderProgram, "stillLifeDepthNeg"),
    stillLifeDepthNeg * depthScalar
  );
  gl.uniform1f(
    gl.getUniformLocation(shaderProgram, "stillLifeDepthPos"),
    stillLifeDepthPos * depthScalar
  );
  gl.uniform1f(
    gl.getUniformLocation(shaderProgram, "lineThickness"),
    lineThickness
  );
  gl.uniform1f(gl.getUniformLocation(shaderProgram, "lineLength"), lineLength);
  gl.uniform1f(gl.getUniformLocation(shaderProgram, "lineDepth"), lineDepth);
}

function beginLinesShader() {
  gl.useProgram(shaderProgram);
  gl.bindBuffer(gl.ARRAY_BUFFER, triangle_buffer);

  transferDisplacementMap();
  setUniforms();

  const coord = gl.getAttribLocation(shaderProgram, "coordinates");
  gl.vertexAttribPointer(coord, 3, gl.FLOAT, false, 0, 0);
  gl.enableVertexAttribArray(coord);

  gl.enable(gl.BLEND);
  gl.disable(gl.DEPTH_TEST);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  gl.viewport(0, 0, canvas.width, canvas.height);
}

function endLinesShader() {
  gl.useProgram(null);
}

function drawLines() {
  beginLinesShader();

  setMatrices();
  gl.uniform3f(gl.getUniformLocation(shaderProgram, "color"), 1, 1, 0);
  if (displayRed) {
    gl.drawArrays(gl.TRIANGLES, 0, numTris);
  }

  translate(lineSpacing, 0.0, 0.1);
  setMatrices();
  gl.uniform3f(gl.getUniformLocation(shaderProgram, "color"), 0, 1, 1);
  if (displayGreen) {
    gl.drawArrays(gl.TRIANGLES, 0, numTris);
  }

  translate(lineSpacing, 0.0, 0.1);
  setMatrices();
  gl.uniform3f(gl.getUniformLocation(shaderProgram, "color"), 1, 0, 1);
  if (displayBlue) {
    gl.drawArrays(gl.TRIANGLES, 0, numTris);
  }
  endLinesShader();
}

function setupTransform() {
  ortho();
  scale(1.45);
  rotateY(0.33);
  rotateX(-0.33);
}

function setupCombination(code) {
  combination = [];
  let comb = str(code);
  for (let i = 0; i < comb.length; i++) {
    let char = comb[i];
    if (char != "0") {
      mostShapeArr[char - 1] += 1;
      let c = int(comb[i]) - 1;
      combination.push(c);
    }
  }
}

function defineColors() {
  let aaa = 254;
  ctokyo = color(227, 143, 53, aaa);
  cberlin = color(53, 155, 227, aaa);
  clondon = color(231, 71, 71, aaa);
  cny = color(166, 79, 206, aaa);
  ccdmx = color(76, 205, 82, aaa);
  cla = color(238, 211, 30, aaa);
  foregrounds = [ctokyo, cberlin, clondon, cny, ccdmx, cla];
  s1 = color(255, 226, 204);
  s2 = color(204, 255, 226);
  s3 = color(225, 204, 226);
  s4 = color(164, 204, 255);
  sc = [s1, s2, s3, s4];
}

function changeAspectRatio() {
  if (vertical) {
    sixX = horiX;
    sixY = horiY;
  } else {
    sixX = vertX;
    sixY = vertY;
  }
  vertical = !vertical;
  for (let i = 0; i < shapes.length; i++) {
    for (let j = 0; j < shapes[i].length; j++) {
      shapes[i][j].changeXandY(
        -stillLifeDim * sixX[i],
        -stillLifeDim * sixY[i]
      );
    }
  }
}

function allCenter() {
  for (let i = 0; i < shapes.length; i++) {
    for (let j = 0; j < shapes[i].length; j++) {
      shapes[i][j].changeXandY(-stillLifeDim * 0.5, -stillLifeDim * 0.5);
      shapes[i][j].changeScale(3.0);
    }
  }
}

function allRandom() {
  for (let i = 0; i < shapes.length; i++) {
    for (let j = 0; j < shapes[i].length; j++) {
      shapes[i][j].changeXandY(
        -stillLifeDim * r.rb(0, 1),
        -stillLifeDim * r.rb(0, 1)
      );
      shapes[i][j].changeScale(1.5);
    }
  }
}

function allGrid() {
  for (let i = 0; i < shapes.length; i++) {
    for (let j = 0; j < shapes[i].length; j++) {
      shapes[i][j].changeXandY(
        -stillLifeDim * sixX[i],
        -stillLifeDim * sixY[i]
      );
      shapes[i][j].changeScale(1.0);
    }
  }
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  if (windowWidth > windowHeight && vertical) {
    changeAspectRatio();
  } else if (windowHeight > windowWidth && !vertical) {
    changeAspectRatio();
  }
}

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  if (windowWidth > windowHeight) {
    vertical = false;
  } else if (windowHeight > windowWidth) {
    vertical = true;
  }

  r = new RND(seed);

  defineColors();
  imageMode(CENTER);
  gl = document.getElementById("defaultCanvas0").getContext("webgl");
  stillLifeDim = rezs[rezIndex];
  alphapix = createGraphics(stillLifeDim, stillLifeDim, WEBGL);
  pgl = alphapix._renderer.GL;
  pgl.disable(gl.DEPTH_TEST);

  overlay = createGraphics(1200, 1200);

  setupShaders();
  doIt();
}

function doIt() {
  stillLifeDim = rezs[rezIndex];
  alphapix.resizeCanvas(stillLifeDim, stillLifeDim);
  setupShapes();
  setupGeometry();
  createDisplacementMapTexture();
  createStillLife();
}

function createGround() {
  if (speedIndex != 4) {
    angle += 0.0005;
  }
  let ss = map(sin(angle), -1, 1, 0, 1);
  let c1 = lerpColor(sc[0], sc[1], ss);
  let c2 = lerpColor(sc[1], sc[2], ss);
  let c3 = lerpColor(sc[2], sc[3], ss);
  let c4 = lerpColor(sc[3], sc[1], ss);
  alphapix.background(255);
  alphapix.blendMode(BLEND);
  alphapix.beginShape();
  alphapix.fill(c1);
  alphapix.vertex(-alphapix.width / 2, -alphapix.height / 2);
  alphapix.fill(c2);
  alphapix.vertex(alphapix.width / 2, -alphapix.height / 2);
  alphapix.fill(c3);
  alphapix.vertex(alphapix.width / 2, alphapix.height / 2);
  alphapix.fill(c4);
  alphapix.vertex(-alphapix.width / 2, alphapix.height / 2);
  alphapix.endShape();
}

function createStillLife() {
  createGround();
  if (multiplyOn) {
    alphapix.blendMode(MULTIPLY);
  } else {
    alphapix.blendMode(BLEND);
  }
  for (let i = 0; i < shapes.length; i++) {
    for (let j = 0; j < shapes[i].length; j++) {
      shapes[i][j].move();
      shapes[i][j].display(alphapix);
    }
  }
}

function makeOverlay() {
  push();
  switch (cityNum) {
    case 1:
      overlay.background(128, 255, 128);
      break;
    case 2:
      overlay.background(204, 204, 255);
      break;
    case 3:
      overlay.background(255, 255, 0);
      break;
    case 4:
      overlay.background(255, 0, 255);
      break;
    case 5:
      overlay.background(0, 255, 255);
      break;
    case 6:
      overlay.background(255, 191, 64);
      break;
    default:
      overlay.background(0);
  }

  const totalShapes = mostShapeArr.reduce((a, b) => a + b, 0);
  const mostUsed = Math.max(...mostShapeArr);
  const indices = mostShapeArr.reduce((result, element, index) => {
    if (element == mostUsed) {
      result.push(index);
    }
    return result;
  }, []);

  let totalLinesPx = 568 + 36 + indices.length * 44;
  let lineCoord = (1200 - totalLinesPx) / 2;

  fill(0, 0, 0);
  noStroke();
  overlay.textAlign(CENTER, TOP);
  overlay.textFont("Arial", 36);

  overlay.text("Wallet:", 600, lineCoord);
  lineCoord += 44;
  overlay.text(all_wallets[walletCount], 600, lineCoord);
  lineCoord += 72;

  overlay.text("Sets:", 600, lineCoord);
  lineCoord += 44;
  overlay.text(all_sets[walletCount].join(" "), 600, lineCoord);
  lineCoord += 72;

  overlay.text(totalShapes.toString() + " Total Shapes: ", 600, lineCoord);
  for (let i = 0; i < mostShapeArr.length; i++) {
    lineCoord += 44;
    if (mostShapeArr[i] == 1) {
      overlay.text(
        mostShapeArr[i].toString() + " " + shapesNames[i],
        600,
        lineCoord
      );
    } else {
      overlay.text(
        mostShapeArr[i].toString() + " " + shapesNames[i] + "s",
        600,
        lineCoord
      );
    }
  }
  lineCoord += 72;

  overlay.text("Most Used Shape:", 600, lineCoord);
  if (indices.length > 1) {
    for (let iShape = 0; iShape < indices.length; iShape++) {
      lineCoord += 44;
      if (mostUsed > 1) {
        overlay.text(
          mostUsed.toString() +
            " " +
            shapesNames[indices[iShape]].toString() +
            "s",
          600,
          lineCoord
        );
      } else {
        overlay.text(
          mostUsed.toString() + " " + shapesNames[indices[iShape]].toString(),
          600,
          lineCoord
        );
      }
    }
  } else {
    lineCoord += 44;
    overlay.text(
      mostUsed.toString() + " " + shapesNames[indices[0]].toString() + "s",
      600,
      lineCoord
    );
  }
  pop();
}

function draw() {
  let scaleFactor = max(width, height) / 1200.0;
  if (rezIndex == 2) {
    lineThickness = 1.66 * scaleFactor;
    lineLength = 3.0 * lengthScalar * scaleFactor;
  } else if (rezIndex == 0) {
    lineThickness = 3.33 * scaleFactor;
    lineLength = 8.0 * lengthScalar * scaleFactor;
  } else {
    lineThickness = 2.22 * scaleFactor;
    lineLength = 12.0 * lengthScalar * scaleFactor;
  }

  lineDepth = 2 * scaleFactor;
  lineSpacing = 2.22 * scaleFactor;
  createStillLife();
  background(bColor);

  push();
  setupTransform();
  drawLines();
  pop();

  if (viewDiagram) {
    fill(255);
    noStroke();
    rect(0, 0, -stillLifeDim / 2, -stillLifeDim / 2);
    image(alphapix, 0, 0);
  }

  if (infoOverlay) {
    push();
    makeOverlay();
    rectMode(CENTER);
    fill(255);
    noStroke();
    rect(0, 0, max(width, height) / 3, max(width, height) / 3);
    image(overlay, 0, 0, max(width, height) / 3, max(width, height) / 3);
    pop();
  }

  if (speedIndex != 4) {
    CDMXSpin++;
  }
}

class VShape {
  constructor(xin, yin, uin, win) {
    this.scale = 1.0;
    this.targetScale = 1.0;
    this.scaleStep = 0.2;

    this.dia = uin * 0.75;
    this.mdia = uin * 0.8;
    this.rdia = uin * 0.66;
    this.ddia = uin * 0.55;

    this.tdia = uin * 0.8;
    this.tdia2 = uin * 0.7;

    this.hu = uin * 0.5;
    this.qr1 = uin * 0.3;
    this.qr2 = uin * 0.2;
    this.sr = uin * 0.4;
    this.unit = stillLifeDim;
    this.x = xin;
    this.y = yin;
    this.rx = this.x + (this.unit - this.rdia) / 2;
    this.ry = this.y + (this.unit - this.rdia) / 2;
    this.cx = this.x + this.unit / 2;
    this.cy = this.y + this.unit / 2;

    this.cindex = win;
    this.sindex = win;

    this.movex = r.rb(0, TWO_PI);
    this.movey = r.rb(0, TWO_PI);

    this.hexx = uin * 0.2;
    this.hexy = uin * 0.346;

    this.moonAngle = r.rb(0, TWO_PI);

    this.moveyval = r.rb(0.0005, 0.002);
    this.movexval = r.rb(0.0005, 0.002);
    if (r.rb(1) > 0.5) {
      this.moveyval *= -1;
    }
    if (r.rb(1) > 0.5) {
      this.movexval *= -1;
    }
  }

  resetScale() {
    this.targetScale = 1.0;
  }

  upScale() {
    this.targetScale += this.scaleStep;
  }

  downScale() {
    this.targetScale -= this.scaleStep;
    this.targetScale = max(0.0, this.targetScale);
  }

  changeScale(newScale) {
    this.targetScale = newScale;
  }

  move() {
    this.movex += this.movexval * speedScalar;
    this.movey += this.moveyval * speedScalar;
    this.scale = (this.targetScale - this.scale) * 0.05 + this.scale;
  }

  changeXandY(xin, yin) {
    this.x = xin;
    this.y = yin;
    this.rx = this.x + (this.unit - this.rdia) / 2;
    this.ry = this.y + (this.unit - this.rdia) / 2;
    this.cx = this.x + this.unit / 2;
    this.cy = this.y + this.unit / 2;
  }

  display(pg) {
    if (this.sindex == 0) {
      this.sTokyo(pg);
    } else if (this.sindex == 1) {
      this.sBerlin(pg);
    } else if (this.sindex == 2) {
      this.sLondon(pg);
    } else if (this.sindex == 3) {
      this.sNYC(pg);
    } else if (this.sindex == 4) {
      this.sCDMX(pg);
    } else if (this.sindex == 5) {
      this.sLA(pg);
    }
  }

  sTokyo(pg) {
    pg.noStroke();
    pg.push();
    pg.translate(this.cx, this.cy);
    pg.scale(this.scale);
    pg.rotateY(this.movey);
    pg.rotateX(this.movex);
    pg.fill(foregrounds[this.cindex]);
    pg.ellipse(0, 0, this.dia, this.dia);
    pg.pop();
  }

  sBerlin(pg) {
    pg.noStroke();
    pg.fill(foregrounds[this.cindex]);
    pg.push();
    pg.beginShape();
    pg.translate(this.cx, this.cy);
    pg.scale(this.scale);
    pg.rotateX(this.movex);
    pg.rotateY(this.movey);
    pg.vertex(-this.qr1, -this.hu);
    pg.vertex(this.qr1, -this.qr2);
    pg.vertex(this.qr1, this.hu);
    pg.vertex(-this.qr1, this.qr2);
    pg.endShape();
    pg.pop();
  }

  sLondon(pg) {
    pg.push();
    pg.translate(this.rx + this.rdia / 2, this.ry + this.rdia / 2);
    pg.scale(this.scale);
    pg.rotateY(this.movey);
    pg.rotateX(this.movex);
    pg.noStroke();
    pg.fill(foregrounds[this.cindex]);
    pg.beginShape();
    pg.vertex(-this.rdia / 2, -this.rdia / 2);
    pg.vertex(this.rdia / 2, -this.rdia / 2);
    pg.vertex(this.rdia / 2, this.rdia / 2);
    pg.vertex(-this.rdia / 2, this.rdia / 2);
    pg.endShape();
    pg.pop();
  }

  sNYC(pg) {
    pg.push();
    pg.translate(this.rx + this.rdia / 2, this.ry + this.rdia / 2);
    pg.scale(this.scale);
    pg.rotateY(this.movey);
    pg.rotateX(this.movex);
    pg.noStroke();
    pg.fill(foregrounds[this.cindex]);
    pg.beginShape();
    pg.vertex(this.hexx, -this.hexy);
    pg.vertex(this.hexx * 2, 0);
    pg.vertex(this.hexx, this.hexy);
    pg.vertex(-this.hexx, this.hexy);
    pg.vertex(-this.hexx * 2, 0);
    pg.vertex(-this.hexx, -this.hexy);
    pg.endShape();
    pg.pop();
  }

  sCDMX(pg) {
    pg.push();
    pg.translate(this.rx + this.rdia / 2, this.ry + this.rdia / 2.66);
    pg.scale(this.scale);
    pg.rotateY(this.movey);
    pg.rotateX(this.movex);
    pg.rotateZ(CDMXSpin / 1000.0);
    pg.noStroke();
    pg.fill(foregrounds[this.cindex]);
    pg.beginShape();
    pg.vertex(0, -this.tdia / 2);
    pg.vertex(this.tdia / 2, this.tdia2 / 2);
    pg.vertex(-this.tdia / 2, this.tdia2 / 2);
    pg.endShape();
    pg.pop();
  }

  sLA(pg) {
    pg.noStroke();
    pg.fill(foregrounds[this.cindex]);
    pg.push();
    pg.translate(this.cx, this.cy);
    pg.scale(this.scale);
    pg.rotate(this.moonAngle);
    pg.rotateX(this.movex);
    pg.rotateY(this.movey);
    pg.rotateZ(CDMXSpin / 1000.0);
    pg.arc(0, 0, this.mdia, this.mdia, 0.7, TWO_PI - 0.7, CHORD);
    pg.pop();
  }
}function tokyoParams() {
  displayRed = true;
  displayGreen = true;
  displayBlue = true;
  bColor = 246;
  lengthScalar = 0.8;
  cityNum = 1;
}

function berlinParams() {
  displayRed = false;
  displayGreen = true;
  displayBlue = true;
  bColor = 15;
  lengthScalar = 0.5;
  cityNum = 2;
}

function londonParams() {
  displayRed = true;
  displayGreen = false;
  displayBlue = true;
  bColor = 246;
  lengthScalar = 0.5;
  cityNum = 3;
}

function nycParams() {
  displayRed = false;
  displayGreen = false;
  displayBlue = true;
  bColor = 246;
  lengthScalar = 0.7;
  cityNum = 4;
}

function cdmxParams() {
  displayRed = false;
  displayGreen = true;
  displayBlue = false;
  bColor = 51;
  lengthScalar = 0.7;
  cityNum = 5;
}

function laParams() {
  displayRed = true;
  displayGreen = true;
  displayBlue = true;
  bColor = 26;
  lengthScalar = 0.8;
  cityNum = 6;
}

function keyPressed() {
  if (key == "=" || key == "+") {
    for (let i = 0; i < shapes.length; i++) {
      for (let j = 0; j < shapes[i].length; j++) {
        shapes[i][j].upScale();
      }
    }
  } else if (key == "-" || key == "_") {
    for (let i = 0; i < shapes.length; i++) {
      for (let j = 0; j < shapes[i].length; j++) {
        shapes[i][j].downScale();
      }
    }
  } else if (key == "d" || key == "D") {
    viewDiagram = !viewDiagram;
  } else if (key == " ") {
    bColor -= 26;
    if (bColor <= 0) {
      bColor = 255;
    }
  } else if (key == "r" || key == "R") {
    displayRed = !displayRed;
  } else if (key == "g" || key == "G") {
    displayGreen = !displayGreen;
  } else if (key == "b" || key == "B") {
    displayBlue = !displayBlue;
  } else if (key == "1") {
    tokyoParams();
  } else if (key == "2") {
    berlinParams();
  } else if (key == "3") {
    londonParams();
  } else if (key == "4") {
    nycParams();
  } else if (key == "5") {
    cdmxParams();
  } else if (key == "6") {
    laParams();
  } else if (keyCode == UP_ARROW) {
    stillLifeDepthNeg += 26;
    stillLifeDepthPos += 26;
  } else if (keyCode == DOWN_ARROW) {
    stillLifeDepthNeg -= 26;
    stillLifeDepthPos -= 26;
  } else if (key == "s" || key == "S") {
    speedIndex++;
    speedIndex = speedIndex % speeds.length;
    speedScalar = speeds[speedIndex];
  } else if (key == "0") {
    lengthScalar += 0.2;
  } else if (key == "9") {
    if (lengthScalar > 0.4) {
      lengthScalar -= 0.2;
    }
  } else if (key == "t" || key == "T") {
    rezIndex++;
    if (rezIndex >= rezs.length) {
      rezIndex = 0;
    }
    doIt();
  } else if (key == "p" || key == "P") {
    saveCanvas(
      nf(walletCount, 3) + "-" + walletCount + "-" + frameCount + ".png",
      0,
      0,
      width,
      height
    );
  } else if (key == "e" || key == "E") {
    allCenter();
  } else if (key == "w" || key == "W") {
    allRandom();
  } else if (key == "q" || key == "Q") {
    allGrid();
  } else if (key == "x" || key == "X") {
    multiplyOn = !multiplyOn;
  } else if (key == "i" || key == "I") {
    infoOverlay = !infoOverlay;
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

let all_wallets = [
  "0x015Dba998332771212F9d6D3536eCFa95a1cF8e6",
  "0x0871E6872f0CdEb32eb013648a76575B4d2dBa80",
  "0x0D13A6950A3d2B982EcD6Eb130FAF20cFDacD928",
  "0x113d754Ff2e6Ca9Fd6aB51932493E4F9DabdF596",
  "0x113d754Ff2e6Ca9Fd6aB51932493E4F9DabdF596",
  "0x113d754Ff2e6Ca9Fd6aB51932493E4F9DabdF596",
  "0x113d754Ff2e6Ca9Fd6aB51932493E4F9DabdF596",
  "0x113d754Ff2e6Ca9Fd6aB51932493E4F9DabdF596",
  "0x113d754Ff2e6Ca9Fd6aB51932493E4F9DabdF596",
  "0x113d754Ff2e6Ca9Fd6aB51932493E4F9DabdF596",
  "0x146D745139d417B8b5A1190cC73b34D7D37A9bBa",
  "0x1F5743DF7C907a74C8cC28Fe0E27c575830AC6A6",
  "0x222f6Df5B750Eb55234DA53d370bB2e8F5a1651d",
  "0x231595E3673a10e846803194f4982E1CF3389161",
  "0x231595E3673a10e846803194f4982E1CF3389161",
  "0x23787626349Cc170bFC512E5b5E3D3F44e00D02D",
  "0x255EeFD8307B3878be1E620FBd6A0ffA193B1CC5",
  "0x2586319850DEfD14dBFa93fE588780FDEA0d4336",
  "0x269D89631ba588a6994bF5A0DccB2A86573781fC",
  "0x27Ae95688aEDef0a38AbEb9f5d4d494Fc7CeB4c8",
  "0x27Eb78C1Eade6fc040d25b94E7acf6BBe0689F0A",
  "0x2B85f187f13e8fc5DB2dEC5027889e9Dfd0bC348",
  "0x2E23433769DB1505230A97EF9a7327E0224e480F",
  "0x2E23433769DB1505230A97EF9a7327E0224e480F",
  "0x2E23433769DB1505230A97EF9a7327E0224e480F",
  "0x32c5299093a3F9D412EA0EB7a2B3D757810f795B",
  "0x3a9139477D5cf400F843407D0Be1ABf9e130FE5C",
  "0x415398D5d063677E210F7E66087898A1719D0FD3",
  "0x457ee5f723C7606c12a7264b52e285906F91eEA6",
  "0x457ee5f723C7606c12a7264b52e285906F91eEA6",
  "0x484585fe5B976C2AFAC0f2c912447059EF41bf78",
  "0x49C7B3cDA921DEe28B0493f60d4AfA57663ebEF2",
  "0x4c40Ce702C4A1A7A231f513A27748ed1Ec258bAF",
  "0x4d6703cE6cC2Af54114f878E2f2500506b67484B",
  "0x4dE89162f766eeb2B0ed7DEc561F91f87DD50dc9",
  "0x51e5152bcd6ebeA8Aa64578C8Ba51E9C6d0bf435",
  "0x51ec5e1b8B3C4C6baE49619e657F94C4AD577b45",
  "0x5772e36143277356fCB562a124613C99f3502aE7",
  "0x598A0aD5e6229dBca38186e9441D73e15Cad652a",
  "0x5a5617BA16Beba3d04ae3C6b1e9d522c1856763C",
  "0x5aA7652ff7A493bAa40F50121b6D3040Da02997F",
  "0x616eb98d0BbE7581bd78c6BE56Ea6D349Cb72229",
  "0x685e34c6A94F330fa494D708b652261140b55aBA",
  "0x6B69edF4667FFbdF0Aa7D52e99F9e7Fce8174AbA",
  "0x75256A46E98Eb0F9c4eefc197eb3DD88d559a771",
  "0x7614114828F5B2dA4C6A6366EeaE91912Cb376Bf",
  "0x76b1F80D532c7496a95e8b4714dF239e29922302",
  "0x778379CA63D4C7A1dc0B20555bD4fB077CB9748a",
  "0x77DA0BD38461d28eE1299dbA1343288Cbe113Ab3",
  "0x789a5b918B997B5A2FEc160ceaa12765f5Ff43Ec",
  "0x7925Edf88700d82Fe3779cc98F8B8b686b6Ac82a",
  "0x7bd5Bbda0a483A62dcA7d8Ba72D53fd278069c02",
  "0x7EaBFE610657218bB4FD5620ED699B14dE305412",
  "0x7EaBFE610657218bB4FD5620ED699B14dE305412",
  "0x7EaBFE610657218bB4FD5620ED699B14dE305412",
  "0x80222ae86eA5F27435D3cc8616a9dfE19e01b95A",
  "0x8553f6Ca1993e502285fFa2053442c7ae921E2ae",
  "0x8AcF08a19c2858a1C9aF39b0e52b0a253bEA3717",
  "0x8cd40E173cA339AB333086300e26EB8538aA9866",
  "0x8Dbbca57Ea56290Efa14D835bBfd34fAF1d89753",
  "0x909a9160d4cd76505cee7F90E862A39541949f7f",
  "0x911657c57B58567922a5712AeC5878502Dcd779b",
  "0x9257C525A955497Ff54450Ca7C0E4359A0b44909",
  "0x953BB3AA4671b859298D98F70890b510176aDD63",
  "0x99e73A69536f7365fD4f2F2e5391f5dAa484b99b",
  "0x99fc8AD516FBCC9bA3123D56e63A35d05AA9EFB8",
  "0x9E174789337b6650fdBb77883f77FD99c2aF2f10",
  "0xa0D62722c4B8624D8005883ECAaAd491f0C212DE",
  "0xa3f81f0a82F2aF7549Ca9Dd10FA5e1D64d2Ea949",
  "0xa5430730f12F1128bf10dfBa38c8e00bc4d90Eea",
  "0xa9C538EA7cEc8e2e2dD9E869a36Af086F657708b",
  "0xaa3c0FAa24E67eBe9B73Fe3efaf9D06F9Ba57622",
  "0xaef7cDf5C0cE911E3491213A71bfC96cb28D5148",
  "0xB96E81f80b3AEEf65CB6d0E280b15FD5DBE71937",
  "0xbBA493459a48798b73522772AD31f2fdD854B534",
  "0xbCE555FfE94290912240c9036C37F49DC5cC2cb8",
  "0xC665A60F22dDa926B920DEB8FFAC0EF9D8a17460",
  "0xCc9B2b1f639F477371A5d784a389965041d7a33e",
  "0xda3c325aB45b30AeB476B026FE6A777443cA04f3",
  "0xe0D209b7324d982BACb757F724EbE00a9792aC28",
  "0xe3f663418251186888935dC1C4979FA3A3dA1bAC",
  "0xe3f663418251186888935dC1C4979FA3A3dA1bAC",
  "0xE4C6c46645988bBafd8ef6B4d1b60D969cC857C3",
  "0xE5CA890A0eF2F128EB3267e4711c6bf3306Ec024",
  "0xE6d4eA6c516b487f36e3F782f7043D7216a9C5bB",
  "0xeE74258438bcd2882fe907C91a5371dc5dD5b0eE",
  "0xeeA6486288645A2F8aA45FB00fbF5ba6a829a208",
  "0xEEF66e0feaD02bD972b77bFcf421eCb3D4699169",
  "0xf3860788D1597cecF938424bAABe976FaC87dC26",
];
let all_sets = [
  [111222, 222660, 345600, 446600, 555200, 666110],
  [111114, 223366, 333311, 444661, 555520, 612400],
  [111260, 222331, 333316, 444136, 551120, 661340],
  [111110, 222220, 333330, 444440, 555550, 666660],
  [111111, 222211, 331000, 444113, 551160, 610000],
  [111134, 222234, 333552, 444160, 552400, 612340],
  [111145, 222400, 333556, 444225, 555223, 661235],
  [111460, 223460, 335560, 444420, 555246, 666225],
  [112256, 225600, 340000, 444446, 555540, 666334],
  [123450, 222450, 350000, 444660, 555664, 666644],
  [111345, 235600, 356000, 444300, 551000, 613000],
  [111200, 222100, 335526, 444435, 555126, 661122],
  [140000, 222245, 333300, 445500, 551230, 663315],
  [111236, 221300, 335600, 416000, 555553, 662500],
  [112200, 222140, 336650, 444230, 556600, 666124],
  [111122, 245000, 346000, 445523, 555111, 666222],
  [115524, 224600, 334000, 441300, 553000, 666624],
  [111443, 235000, 335000, 415000, 556000, 661300],
  [113344, 222460, 333340, 445560, 555442, 662340],
  [112246, 222236, 333120, 441136, 513000, 661350],
  [111660, 222216, 335500, 444423, 555666, 666450],
  [113326, 221346, 333345, 442350, 555522, 661345],
  [111112, 222110, 331246, 441125, 551130, 666230],
  [111300, 222134, 333221, 444150, 551166, 666625],
  [113350, 222260, 335540, 446623, 556620, 666630],
  [113300, 221400, 333100, 443500, 551400, 666100],
  [111140, 223344, 336640, 445510, 551240, 666613],
  [111330, 222550, 333240, 444120, 555110, 666650],
  [112346, 222333, 333224, 444350, 552360, 666553],
  [111166, 222221, 333310, 444456, 555116, 666114],
  [120000, 224450, 333554, 460000, 555334, 623000],
  [114423, 222156, 314500, 444552, 555332, 666220],
  [124000, 221000, 333000, 444000, 552000, 666000],
  [111230, 224430, 332560, 445530, 552200, 612000],
  [111334, 224435, 334460, 444555, 553460, 666125],
  [112300, 223314, 333126, 441560, 555234, 661150],
  [111240, 224455, 333456, 444335, 552216, 666500],
  [111246, 222215, 335510, 444450, 555130, 661134],
  [111000, 222000, 336000, 441000, 555000, 661100],
  [112350, 222356, 333344, 446650, 555226, 661120],
  [111446, 222255, 333146, 444336, 555236, 666250],
  [111450, 221360, 333356, 446610, 551140, 666200],
  [111256, 223450, 335512, 444360, 555134, 666440],
  [124500, 222300, 331600, 426000, 526000, 666445],
  [114560, 222213, 331245, 444415, 555240, 666551],
  [111456, 222160, 333450, 441160, 551360, 665000],
  [111120, 223350, 333140, 441600, 555300, 661240],
  [123400, 222145, 334415, 444100, 552460, 666145],
  [111234, 223356, 336600, 441200, 551134, 666443],
  [111156, 222446, 333551, 444416, 555663, 663314],
  [111550, 221450, 333350, 446000, 512000, 662215],
  [111124, 222223, 333333, 444455, 555552, 666645],
  [111130, 221350, 331145, 443600, 555443, 612300],
  [114420, 222444, 333331, 444413, 556613, 662230],
  [114500, 222551, 336624, 446635, 556634, 666224],
  [113340, 221460, 333325, 442560, 551234, 661245],
  [111556, 222600, 333160, 445566, 513600, 666350],
  [111123, 224410, 333124, 444112, 555346, 666331],
  [111335, 223400, 333600, 444332, 555512, 666612],
  [111133, 222553, 333400, 445536, 555330, 663450],
  [111333, 223316, 333666, 444410, 556612, 661130],
  [114426, 223000, 334466, 446620, 551460, 666622],
  [123000, 240000, 335520, 456000, 510000, 620000],
  [111146, 222335, 333555, 441236, 555662, 613400],
  [113325, 222334, 333116, 444330, 552300, 663500],
  [110000, 230000, 360000, 440000, 560000, 661000],
  [111336, 222235, 331260, 444412, 555221, 666123],
  [123500, 224436, 345000, 441156, 555224, 666235],
  [114600, 224500, 331200, 444250, 554600, 663000],
  [111116, 222233, 333322, 444666, 555551, 666150],
  [112240, 222115, 331240, 444662, 555136, 661133],
  [113456, 222556, 333360, 444443, 551340, 666550],
  [111224, 222116, 333315, 444422, 555544, 666130],
  [100000, 200000, 300000, 400000, 500000, 600000],
  [111560, 223560, 336625, 444663, 552214, 661200],
  [111552, 222244, 333332, 444556, 555222, 666134],
  [113460, 222250, 336645, 444436, 555524, 661450],
  [111350, 222136, 333125, 444425, 555260, 662200],
  [113500, 224000, 333200, 444200, 555600, 662300],
  [134000, 224415, 331146, 444600, 555400, 662245],
  [111665, 222665, 333335, 444466, 555523, 666113],
  [113400, 222222, 333326, 444441, 555554, 666634],
  [111664, 234600, 334456, 442500, 555660, 666335],
  [111663, 221600, 333225, 441500, 555556, 666234],
  [115600, 222445, 333246, 442600, 551300, 663400],
  [112235, 222146, 333560, 442256, 552340, 666623],
  [111160, 222440, 333334, 444411, 512360, 662450],
  [111250, 222210, 334400, 444500, 555114, 660000],
  [112000, 220000, 330000, 450000, 555560, 666330],
];