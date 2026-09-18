var seed = parseInt(tokenData.hash.slice(0, 16), 16);
let projectNumber = Math.floor(parseInt(tokenData.tokenId) / 1000000);
let mintNumber = parseInt(tokenData.tokenId) % 1000000;

p5.disableFriendlyErrors = true;

let rezs = [150, 200, 300];
let cIndex = 1;

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

let index = 0;
let laIndex = 771;
let combination = [];

let angle = 0.0;

let alphapix;

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
  for (let y = 0; y < rezs[cIndex]; y += 1) {
    for (let x = 0; x < rezs[cIndex]; x += 1) {
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
  let sss = 0.72; 
  shapes = [];
  for (let i = 0; i < combination.length; i++) {
    shapes.push(
      new VShape(
        -stillLifeDim / 2,
        -stillLifeDim / 2,
        stillLifeDim * sss,
        combination[i]
      )
    );
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
  stillLifeDepthNeg = 255.0;
  stillLifeDepthPos = 255.0;
  lengthScalar = 1.0;
  if (index < 155) {
    tokyoParams();
  } else if (index < 309) {
    berlinParams();
  } else if (index < 463) {
    londonParams();
  } else if (index < 617) {
    nycParams();
  } else if (index < laIndex) {
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
  gl.uniform3f(gl.getUniformLocation(shaderProgram, "color"), 1, 0, 0);
  if (displayRed) {
    gl.drawArrays(gl.TRIANGLES, 0, numTris);
  }

  translate(lineSpacing, 0.0, 0.1);
  setMatrices();
  gl.uniform3f(gl.getUniformLocation(shaderProgram, "color"), 0, 1, 0);
  if (displayGreen) {
    gl.drawArrays(gl.TRIANGLES, 0, numTris);
  }
  
  translate(lineSpacing, 0.0, 0.1);
  setMatrices();
  gl.uniform3f(gl.getUniformLocation(shaderProgram, "color"), 0, 0, 1);
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
      let c = int(comb[i]) - 1;
      combination.push(c);
    }
  }
}

function defineColors() {
  let aaa = 254;
  ctokyo = color(227, 143, 53, aaa); // Orange
  cberlin = color(53, 155, 227, aaa);  // Blue
  clondon = color(231, 71, 71, aaa); // Red
  cny = color(166, 79, 206, aaa); // Lavender
  ccdmx = color(76, 205, 82, aaa); // Green 
  cla = color(238, 211, 30, aaa); // Yellow
  foregrounds = [ctokyo, cberlin, clondon, cny, ccdmx, cla];
  s1 = color(255, 226, 204);
  s2 = color(204, 255, 226);
  s3 = color(225, 204, 226);
  s4 = color(164, 204, 255);  
  sc = [s1, s2, s3, s4];
}

function windowResized() {
  resizeCanvas(windowWidth, windowHeight);
  theDetails();
}

function setup() {
  createCanvas(windowWidth, windowHeight, WEBGL);
  
  r = new RND(seed);
  
  defineRez();
  
  if (mintNumber >= 924) {
    index = int(random(0, 924));
  } else {
    index = mintNumber;
  }
  
  defineColors();
  imageMode(CENTER);
  gl = document.getElementById("defaultCanvas0").getContext("webgl");
  stillLifeDim = rezs[cIndex];
  alphapix = createGraphics(stillLifeDim, stillLifeDim, WEBGL);
  pgl = alphapix._renderer.GL;
  pgl.disable(gl.DEPTH_TEST);
  setupShaders();  
  doIt();
}

function defineRez() {
  cIndex = 1;
}

function doIt() {
  stillLifeDim = rezs[cIndex];
  alphapix.resizeCanvas(stillLifeDim, stillLifeDim);
  setupCombination(allCombinations[index]);
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
  alphapix.vertex(-alphapix.width/2, -alphapix.height/2);
  alphapix.fill(c2);
  alphapix.vertex(alphapix.width/2, -alphapix.height/2);
  alphapix.fill(c3);
  alphapix.vertex(alphapix.width/2, alphapix.height/2);
  alphapix.fill(c4);
  alphapix.vertex(-alphapix.width/2, alphapix.height/2);
  alphapix.endShape();
}

function createStillLife() {
  createGround();
  alphapix.blendMode(MULTIPLY); 
  for (let i = 0; i < shapes.length; i++) {
    shapes[i].move();
    shapes[i].display(alphapix);
  }
}

function draw() {
  let scaleFactor = max(width, height) / 1200.0;
  if (cIndex == 2) {
    lineThickness = 1.66 * scaleFactor;
    lineLength = 3.0 * lengthScalar * scaleFactor;
  } else if (cIndex == 0) {
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
    rect(0, 0, -stillLifeDim/2, -stillLifeDim/2);
    image(alphapix, 0, 0);
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
    this.x = xin;
    this.y = yin;
    this.unit = stillLifeDim;
    this.rx = this.x + (this.unit - this.rdia) / 2;
    this.ry = this.y + (this.unit - this.rdia) / 2;
    this.cx = this.x + this.unit / 2;
    this.cy = this.y + this.unit / 2;

    this.cindex = win;
    this.sindex = win;

    this.movex = 0;
    this.movey = 0;
    
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

  move() {
    this.movex += this.movexval * speedScalar;
    this.movey += this.moveyval * speedScalar;
    this.scale = (this.targetScale - this.scale) * 0.05 + this.scale;
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
    pg.scale(this.scale);
    pg.translate(this.cx, this.cy);
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
    pg.scale(this.scale);
    pg.beginShape();
    pg.translate(this.cx, this.cy);
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
    pg.scale(this.scale);
    pg.translate(this.rx + this.rdia / 2, this.ry + this.rdia / 2);
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
    pg.scale(this.scale);
    pg.translate(this.rx + this.rdia / 2, this.ry + this.rdia / 2);
    pg.rotateY(this.movey);
    pg.rotateX(this.movex);
    pg.noStroke();
    pg.fill(foregrounds[this.cindex]);
    pg.beginShape();
    pg.vertex(this.hexx, -this.hexy);
    pg.vertex(this.hexx*2, 0);
    pg.vertex(this.hexx, this.hexy);
    pg.vertex(-this.hexx, this.hexy);
    pg.vertex(-this.hexx*2, 0);
    pg.vertex(-this.hexx, -this.hexy);
    pg.endShape();
    pg.pop();
  }
    
  sCDMX(pg) {
    pg.push();
    pg.scale(this.scale);
    pg.translate(this.rx + this.rdia / 2, this.ry + this.rdia / 2.66);
    pg.rotateY(this.movey);
    pg.rotateX(this.movex);
    pg.rotateZ(CDMXSpin/1000.0);
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
    pg.scale(this.scale);
    pg.translate(this.cx, this.cy);
    pg.rotate(this.moonAngle);
    pg.rotateX(this.movex);
    pg.rotateY(this.movey);
    pg.rotateZ(CDMXSpin/1000.0);
    pg.arc(0, 0, this.mdia, this.mdia, 0.7, TWO_PI - 0.7, CHORD);
    pg.pop();
  }

}

function tokyoParams() {
  displayRed = true;
  displayGreen = true;
  displayBlue = true;
  bColor = 246;
  lengthScalar = 0.8;
}

function berlinParams() {
  displayRed = false;
  displayGreen = true;
  displayBlue = true;
  bColor = 15;
  lengthScalar = 0.5;
  if (index === 155) {
    stillLifeDepthNeg = 350.0;
    stillLifeDepthPos = 150.0;
  }
}

function londonParams() {
  displayRed = true;
  displayGreen = false;
  displayBlue = true;
  bColor = 246;
  lengthScalar = 0.5;
}

function nycParams() {
  displayRed = false;
  displayGreen = false;
  displayBlue = true;
  bColor = 246;
  lengthScalar = 0.7;
  if (index === 463) {
    stillLifeDepthNeg = 400.0;
    stillLifeDepthPos = 100.0;
  }
}

function cdmxParams() {
  displayRed = false;
  displayGreen = true;
  displayBlue = false;
  bColor = 51;
  lengthScalar = 0.7;
  if (index === 617) {
    stillLifeDepthNeg = 500.0;
    stillLifeDepthPos = 0.0;
  }
}

function laParams() {
  displayRed = true;
  displayGreen = true;
  displayBlue = true;
  bColor = 26;
  lengthScalar = 0.8;
}

function keyPressed() {
  if (key == '=' || key == '+') {
    for (let i = 0; i < shapes.length; i++) {
      shapes[i].upScale();
    }
  } else if (key == '-' || key == '_') {
    for (let i = 0; i < shapes.length; i++) {
      shapes[i].downScale();
    }
  } else if (key == 'd' || key == 'D') {
    viewDiagram = !viewDiagram;
  } else if (key == ' ') {
    bColor -= 26;
    if (bColor <= 0) {
      bColor = 255;
    }
  } else if (key == 'r' || key == 'R') {
    displayRed = !displayRed;
  } else if (key == 'g' || key == 'G') {
    displayGreen = !displayGreen;
  } else if (key == 'b' || key == 'B'){
    displayBlue = !displayBlue;
  } else if (key == '1') {
    tokyoParams();
  } else if (key == '2') {
    berlinParams();
  } else if (key == '3') {
    londonParams();
  } else if (key == '4') {
    nycParams();
  } else if (key == '5') {
    cdmxParams();
  } else if (key == '6') {
    laParams();
  } else if (keyCode == UP_ARROW) {
    stillLifeDepthNeg += 26;
    stillLifeDepthPos += 26;
  } else if (keyCode == DOWN_ARROW) {
    stillLifeDepthNeg -= 26;
    stillLifeDepthPos -= 26;
  } else if (key == 's' || key == 'S') {
    speedIndex++;
    speedIndex = speedIndex % speeds.length;
    speedScalar = speeds[speedIndex];
  } else if (key == '0') {
    lengthScalar += 0.2;
  } else if (key == '9') {
    if (lengthScalar > 0.4) {
      lengthScalar -= 0.2;
    }
  } else if (key == 't' || key == 'T') {
    cIndex++;
    if (cIndex >= rezs.length) {
      cIndex = 0;
    }
    doIt();
  } else if (key == 'p' || key == 'P') {
    saveCanvas(nf(index,3) + '-' + allCombinations[index] + "-" + frameCount + ".png", 0, 0, width, height);
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
}let allCombinations = [
  999999,
  100000, 110000, 120000, 130000, 140000, 111000, 112000, 113000, 114000, 115000, 116000, 123000,
  124000, 134000, 111100, 111200, 111300, 111400, 111500, 111600, 112200, 113300, 112300, 112400,
  112500, 112600, 113400, 113500, 113600, 114500, 114600, 115600, 123400, 123500, 124500, 111110,
  111120, 111130, 111140, 111150, 111160, 111220, 111330, 111440, 111550, 111660, 111230, 111240,
  111250, 111260, 111340, 111350, 111360, 111450, 111460, 111560, 112230, 112240, 113320, 112250,
  112260, 114420, 113340, 113350, 114430, 113360, 112340, 112350, 112360, 112450, 112460, 112560,
  113450, 113460, 113560, 114560, 123450, 111111, 111112, 111113, 111114, 111115, 111116, 111122,
  111133, 111144, 111155, 111166, 111123, 111124, 111125, 111126, 111134, 111135, 111136, 111145,
  111146, 111156, 111222, 111333, 111223, 111224, 111225, 111226, 111332, 111442, 111552, 111662,
  111334, 111335, 111336, 111443, 111553, 111663, 111445, 111446, 111554, 111664, 111556, 111665,
  111234, 111235, 111236, 111245, 111246, 111256, 111345, 111346, 111356, 111456, 112233, 112244,
  112255, 113344, 113355, 112234, 112235, 113324, 112236, 112245, 113325, 114423, 112246, 113326,
  112256, 114426, 115524, 114435, 113356, 112345, 112346, 112356, 112456, 113456, 200000, 220000,
  230000, 240000, 250000, 222000, 221000, 223000, 224000, 225000, 226000, 234000, 235000, 245000,
  222200, 222100, 222300, 222400, 222500, 222600, 223300, 224400, 221300, 221400, 221500, 221600,
  223400, 223500, 223600, 224500, 224600, 225600, 234500, 234600, 235600, 222220, 222210, 222230,
  222240, 222250, 222260, 222110, 222330, 222440, 222550, 222660, 222130, 222140, 222150, 222160,
  222340, 222350, 222360, 222450, 222460, 222560, 223340, 223350, 224430, 223360, 223310, 225530,
  224450, 224460, 225540, 224410, 221340, 221350, 221360, 221450, 221460, 221560, 223450, 223460,
  223560, 224560, 234560, 222222, 222221, 222223, 222224, 222225, 222226, 222211, 222233, 222244,
  222255, 222266, 222213, 222214, 222215, 222216, 222234, 222235, 222236, 222245, 222246, 222256,
  222333, 222444, 222113, 222114, 222115, 222116, 222331, 222441, 222551, 222661, 222334, 222335,
  222336, 222443, 222553, 222663, 222445, 222446, 222554, 222664, 222556, 222665, 222134, 222135,
  222136, 222145, 222146, 222156, 222345, 222346, 222356, 222456, 223344, 223355, 223366, 224455,
  223345, 223346, 224435, 223314, 223356, 224436, 225534, 223315, 224413, 223316, 226634, 225536,
  225513, 224415, 224416, 221345, 221346, 221356, 221456, 223456, 300000, 330000, 340000, 350000,
  360000, 333000, 331000, 332000, 334000, 335000, 336000, 345000, 346000, 356000, 333300, 333100,
  333200, 333400, 333500, 333600, 334400, 335500, 336600, 331200, 331400, 331500, 331600, 332400,
  332500, 332600, 334500, 334600, 335600, 345600, 314500, 333330, 333310, 333320, 333340, 333350,
  333360, 333110, 333220, 333440, 333550, 333660, 333120, 333140, 333150, 333160, 333240, 333250,
  333260, 333450, 333460, 333560, 334450, 334460, 335540, 334410, 334420, 336640, 335560, 335510,
  336650, 335520, 331240, 331250, 331260, 331450, 331460, 331560, 332450, 332460, 332560, 334560,
  314560, 333333, 333331, 333332, 333334, 333335, 333336, 333311, 333322, 333344, 333355, 333366,
  333312, 333314, 333315, 333316, 333324, 333325, 333326, 333345, 333346, 333356, 333444, 333555,
  333666, 333112, 333114, 333115, 333116, 333221, 333441, 333551, 333661, 333224, 333225, 333226,
  333442, 333552, 333662, 333445, 333446, 333554, 333664, 333556, 333665, 333124, 333125, 333126,
  333145, 333146, 333156, 333245, 333246, 333256, 333456, 334455, 334466, 334456, 334415, 335546,
  334416, 335514, 334425, 336645, 334426, 335524, 331145, 334412, 331146, 336624, 335526, 335512,
  336625, 331245, 331246, 331256, 331456, 332456, 400000, 440000, 450000, 460000, 444000, 441000,
  442000, 443000, 445000, 446000, 456000, 415000, 416000, 426000, 444400, 444100, 444200, 444300,
  444500, 444600, 445500, 446600, 441100, 441200, 441300, 441500, 441600, 442300, 442500, 442600,
  443500, 443600, 445600, 415600, 425600, 444440, 444410, 444420, 444430, 444450, 444460, 444110,
  444220, 444330, 444550, 444660, 444120, 444130, 444150, 444160, 444230, 444250, 444260, 444350,
  444360, 444560, 445560, 445510, 446650, 445520, 441150, 446610, 445530, 441160, 446620, 446630,
  441230, 441250, 441260, 441350, 441360, 441560, 442350, 442360, 442560, 443560, 412560, 444444,
  444441, 444442, 444443, 444445, 444446, 444411, 444422, 444433, 444455, 444466, 444412, 444413,
  444415, 444416, 444423, 444425, 444426, 444435, 444436, 444456, 444555, 444666, 444111, 444112,
  444113, 444115, 444116, 444221, 444331, 444551, 444661, 444223, 444225, 444226, 444332, 444552,
  444662, 444335, 444336, 444553, 444663, 444556, 444665, 444123, 444125, 444126, 444135, 444136,
  444156, 444235, 444236, 444256, 444356, 445566, 441155, 441166, 445516, 446615, 445526, 441156,
  445512, 446625, 445536, 445513, 446635, 441125, 446612, 442256, 445523, 441136, 446623, 441235,
  441236, 441256, 441356, 442356, 500000, 550000, 560000, 510000, 555000, 551000, 552000, 553000,
  554000, 556000, 516000, 526000, 512000, 513000, 555500, 555100, 555200, 555300, 555400, 555600,
  556600, 551100, 552200, 551200, 551300, 551400, 551600, 552300, 552400, 552600, 553400, 553600,
  554600, 512600, 513600, 555550, 555510, 555520, 555530, 555540, 555560, 555110, 555220, 555330,
  555440, 555660, 555120, 555130, 555140, 555160, 555230, 555240, 555260, 555340, 555360, 555460,
  556610, 551160, 556620, 556630, 551120, 552260, 556640, 551130, 552210, 551140, 551230, 551240,
  551260, 551340, 551360, 551460, 552340, 552360, 552460, 553460, 512360, 555555, 555551, 555552,
  555553, 555554, 555556, 555511, 555522, 555533, 555544, 555566, 555512, 555513, 555514, 555516,
  555523, 555524, 555526, 555534, 555536, 555546, 555666, 555111, 555222, 555112, 555113, 555114,
  555116, 555221, 555331, 555441, 555661, 555223, 555224, 555226, 555332, 555442, 555662, 555334,
  555336, 555443, 555663, 555446, 555664, 555123, 555124, 555126, 555134, 555136, 555146, 555234,
  555236, 555246, 555346, 551166, 552266, 553366, 556612, 551126, 556613, 551136, 552216, 556614,
  556623, 551146, 556624, 551123, 553316, 556634, 552246, 551134, 552214, 551234, 551236, 551246,
  551346, 552346, 600000, 660000, 610000, 620000, 666000, 661000, 662000, 663000, 664000, 665000,
  612000, 613000, 623000, 666600, 666100, 666200, 666300, 666400, 666500, 661100, 662200, 661200,
  661300, 661400, 661500, 662300, 662400, 662500, 663400, 663500, 664500, 612300, 612400, 613400,
  666660, 666610, 666620, 666630, 666640, 666650, 666110, 666220, 666330, 666440, 666550, 666120,
  666130, 666140, 666150, 666230, 666240, 666250, 666340, 666350, 666450, 661120, 661130, 662210,
  661140, 661150, 663310, 662230, 662240, 663320, 662250, 661230, 661240, 661250, 661340, 661350,
  661450, 662340, 662350, 662450, 663450, 612340, 666666, 666661, 666662, 666663, 666664, 666665,
  666611, 666622, 666633, 666644, 666655, 666612, 666613, 666614, 666615, 666623, 666624, 666625,
  666634, 666635, 666645, 666111, 666222, 666112, 666113, 666114, 666115, 666221, 666331, 666441,
  666551, 666223, 666224, 666225, 666332, 666442, 666552, 666334, 666335, 666443, 666553, 666445,
  666554, 666123, 666124, 666125, 666134, 666135, 666145, 666234, 666235, 666245, 666345, 661122,
  661133, 662244, 661123, 661124, 662213, 661125, 661134, 662214, 663312, 661135, 662215, 661145,
  663314, 663315, 664413, 662235, 662245, 661234, 661235, 661245, 661345, 662345, 612345
];