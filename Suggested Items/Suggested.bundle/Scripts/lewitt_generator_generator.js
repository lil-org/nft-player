let hash = tokenData.hash;
let rawParams = setupParametersFromTokenData(tokenData);
let seed = generateSeedFromTokenData(tokenData);

let params = {
     palette: mapParam(rawParams[0], 0, 142),
     warpType: mapParam(rawParams[1], 0, 100),
     warpDepth: mapParam(rawParams[2], 0.15, 0.5),
     bdAlpha: mapParam(rawParams[3], 128, 255),
     bdType: mapParam(rawParams[4], 0, 100),
     squareWall: rawParams[5] > 200,
     viewAngleX: parseInt(mapParam(rawParams[6], 3, 8)),
     viewAngleZ: parseInt(mapParam(rawParams[7], 3, 12))
}

let DIM, DIMW, M;
const DEFAULT_SIZE = 1080;

const maxPts = 51;
const minPts = 12;
const curveSegments = 24;

let numPts;
let ptsA = [];
let curves = [];
let nodes = [];

let warpType, warpDepth;

let palette = [];
palette[9] = ["#F5DEBD", "#F5F0E1", "#F5DEBD", "#F9FAF2", "#2F8A65", "#009C68", "#FFB808", "#FF08D6"];
palette[8] = ["#FAF1F0", "#C6E8B7", "#FFFFF5", "#F9FAF2", "#104875", "#21425C", "#3DCCC5", "#95CC3D"];
palette[7] = ["#D9D1C7", "#D9D1C7", "#8C8681", "#8C8681", "#F2EDE4", "#FCF7ED", "#2F3540", "#252A33"];
palette[6] = ["#000000", "#000000", "#000000", "#000000", "#A5FFFF", "#00FF00", "#F702FF", "#0FAAFF"];
palette[5] = ["#BF1717", "#BF1717", "#F23054", "#052440", "#0487D9", "#0A5A8C", "#D9D630", "#FFFFFF"];
palette[4] = ["#DACD99", "#F5D6AE", "#D2D6C5", "#000000", "#00BA7C", "#0A8C72", "#665880", "#5D9AA1"];
palette[3] = ["#DCF2CB", "#F3FEB0", "#FF5C64", "#FEA443", "#2E215C", "#56485C", "#DCF2CB", "#F3FEB0"];
palette[2] = ["#F279B2", "#F26FA4", "#FF8A8A", "#F2D16D", "#000000", "#262626", "#FFFFFF", "#FFFFFF"];
palette[1] = ["#F2FBFF", "#8AB7DE", "#FAEDCF", "#FF9673", "#F76A2D", "#FC5666", "#35509C", "#60E0CD"];
palette[0] = ["#2C89F5", "#3385D6", "#D6AFFA", "#94CDF2", "#FCF5E6", "#FFFFFF", "#00113D", "#002FA7"];

let pn;
let bdAlpha, bdType;
let bgCol;
let bdCol1, bdCol2;
let geomCol1, geomCol2;
let wallCol1, wallCol2, wallMod;


function setup() {

     cnv = createCanvas(window.innerWidth, window.innerHeight, WEBGL);
     resizeCanvas(cnv.elt.offsetWidth, cnv.elt.offsetHeight);
     noiseSeed(seed);
     curveDetail(16);

     DIM = Math.min(cnv.elt.width, cnv.elt.height);
     DIMW = DIM;
     M = DIM / DEFAULT_SIZE;

     ortho(-cnv.elt.width * 2 / 3, cnv.elt.width * 2 / 3, -cnv.elt.height * 2 / 3, cnv.elt.height * 2 / 3, -999999, 999999);

     if (params.palette > 140) {
          pn = 0;
     } else if (params.palette > 125) {
          pn = 7;
     } else if (params.palette > 120) {
          pn = 6;
     } else if (params.palette > 110) {
          pn = 9;
     } else if (params.palette > 100) {
          pn = 8;
     } else if (params.palette > 80) {
          pn = 5;
     } else if (params.palette > 60) {
          pn = 4;
     } else if (params.palette > 40) {
          pn = 3;
     } else if (params.palette > 20) {
          pn = 2;
     } else {
          pn = 1;
     }


     if (params.bdType < 25) {
          bdType = "SQUARE";
     } else if (params.bdType < 50) {
          bdType = "DIAMOND";
     } else if (params.bdType < 75) {
          bdType = "CIRCLE";
     } else {
          bdType = "FULL";
     }

     if (params.warpType < 17) {
          warpType = "2MOUNDS";
     } else if (params.warpType < 27) {
          warpType = "SADDLE";
     } else if (params.warpType < 43) {
          warpType = "EGGCARTON";
     } else if (params.warpType < 63) {
          warpType = "NOISE";
     } else if (params.warpType < 84) {
          warpType = "MOUND";
     } else {
          warpType = "WAVES";
     }


     warpDepth = params.warpDepth;

     bgCol = color(palette[pn][0]);
     bdCol1 = color(palette[pn][1]);
     bdCol2 = color(palette[pn][2]);
     bleedCol = color(palette[pn][3]);
     geomCol = color(palette[pn][4]);
     geomCol2 = color(palette[pn][5]);
     wallCol1 = color(palette[pn][6]);
     wallCol2 = color(palette[pn][7]);

     numPts = int(rndMap(minPts, maxPts));

     for (var n = 0; n < numPts; n++) {
          ptsA[n] = placeFiftyPointsAtRandom();
     }

     if (pn == 6) {
          bdAlpha = 0;
     } else {
          bdAlpha = 128;
     }

     for (var q = 0; q < numPts; q++) {
          nodes[q] = new Node(q, ptsA, curveSegments, geomCol, geomCol2);
     }

     connectAll();
     warpAll(warpType)
     background(255);
     backdrop(bdType);

     push();

     rotateX(PI / params.viewAngleX);
     rotateZ(PI / params.viewAngleZ);

     var sandwichDist = DIM / 8;

     if (params.squareWall) {
          wallMod = 2;
     } else {
          wallMod = 1;
     }

     push();
     translate(0, 0, -sandwichDist);
     strokeWeight(M * 1.5);
     noFill();
     wall();
     pop();

     push();
     translate(0, 0, sandwichDist);
     if (numPts < 20) {
          strokeWeight(M * 3);
     } else if (numPts < 35) {
          strokeWeight(M * 2);
     } else {
          strokeWeight(M * 1);
     }

     noFill();
     renderAll();

     pop();
}


function draw() {}


function renderAll() {

     for (var j = 0; j < numPts; j++) {
          for (var k = (j + 1); k < numPts; k++) {
               nodes[j].render(k);
          }
     }
}

function connectAll() {
     for (var j = 0; j < numPts; j++) {
          for (var k = (j + 1); k < numPts; k++) {
               nodes[j].connectTo(k);
          }
     }
}

function warpAll(warpMode) {
     for (var j = 0; j < numPts; j++) {
          for (var k = (j + 1); k < numPts; k++) {
               nodes[j].warp(k, warpMode, warpDepth, 0);
          }
     }
}

function backdrop(bdType) {
     var nBd = 128;
     rectMode(CENTER);
     push();
     noStroke();

     if (bdType == "CIRCLE") {
          push();
          translate(0, 0, -DIM);
          for (var bdk = 0; bdk < cnv.elt.height * 2; bdk += 2) {
               var tempCol = lerpColor(bdCol1, bdCol2, bdk / cnv.elt.height);

               fill(tempCol);
               rectMode(CENTER);
               rect(0, bdk - cnv.elt.height, cnv.elt.width * 2, 2);
          }

          var tempCol = color(bdCol2);

          fill(tempCol);
          ellipse(0, 0, DIM * 1.5, DIM * 1.5, 48);
          pop();
     } else if (bdType == "DIAMOND") {
          push();

          translate(0, 0, -DIM);
          for (var bdk = -cnv.elt.height; bdk < cnv.elt.height; bdk += 2) {
               var t = map(bdk, -cnv.elt.height, cnv.elt.height, 0, 1);
               var val = DIM * 5;
               var tempCol = lerpColor(bdCol1, bdCol2, t);

               fill(tempCol);
               rectMode(CENTER);
               rect(0, bdk, cnv.elt.width * 2, 2);
          }
          rotateZ(-PI / 4);

          for (var bdk = 0; bdk < DIM; bdk += 2) {
               var t = map(bdk, -cnv.elt.height, cnv.elt.height, 0, 1);
               var tempCol = lerpColor(bdCol1, bdCol2, bdk / DIM);


               fill(tempCol);
               rectMode(CENTER);
               rect(0, bdk - DIM / 2, DIM, 2);
          }
          pop();
     } else if (bdType == "SQUARE") {

          push();

          translate(0, 0, -DIM);

          for (var bdk = -cnv.elt.height; bdk < cnv.elt.height; bdk += 2) {
               var t = map(bdk, -cnv.elt.height, cnv.elt.height, 0, 1);
               var val = DIM * 5;
               var tempCol = lerpColor(bdCol1, bdCol2, t);
               if (pn != 7) {

               }
               fill(tempCol);
               rectMode(CENTER);
               rect(0, bdk, cnv.elt.width * 2, 2);
          }

          for (var bdk = 0; bdk < DIM; bdk += 2) {
               var tempCol = lerpColor(bdCol1, bdCol2, bdk / DIM);

               fill(tempCol);
               rectMode(CENTER);
               rect(0, bdk - DIM / 2, DIM, 2);
          }

          pop();
     } else if (bdType = "FULL") {
          push();

          translate(0, 0, -DIM * 3);

          for (var bdk = -cnv.elt.height; bdk < cnv.elt.height; bdk += 2) {
               var t = map(bdk, -cnv.elt.height, cnv.elt.height, 0, 1);
               var val = DIM * 5;
               var tempCol = lerpColor(bdCol1, bdCol2, t);

               fill(tempCol);
               rectMode(CENTER);
               rect(0, bdk, cnv.elt.width * 2, 2);
          }
          pop();
     }
}

function placeFiftyPointsAtRandom() {

     return createVector((rnd() - 0.5) * DIMW, (rnd() - 0.5) * DIM);
}

function wall() {

     var xVal, yVal, wallZ;

     for (var xx = -DIMW / 2; xx < DIMW / 2; xx += M * 7) {
          var t = map(xx, -DIMW / 2, DIMW / 2, 0, 1);
          var tempCol = lerpColor(wallCol1, wallCol2, t);

          stroke(tempCol);

          for (var yy = -DIM / wallMod; yy < DIM / wallMod; yy += M * 4) {

               if (warpType == "MOUND") {
                    xVal = map(xx, 0, DIMW, TWO_PI, 0);
                    yVal = map(yy, 0, DIM, TWO_PI, 0);
                    wallZ = -(cos(xVal) + cos(yVal)) * DIM * params.warpDepth;
               } else if (warpType == "2MOUNDS") {
                    xVal = map(xx, 0, DIMW, 0, TWO_PI * 2) + PI;
                    yVal = map(yy, 0, DIM, 0, TWO_PI);
                    wallZ = (cos(xVal) + cos(yVal)) * DIM * params.warpDepth * 0.5;
               } else if (warpType == "NOISE") {
                    noiseDetail(2, 0.2);
                    // var xNoise = xx / 800;
                    // var yNoise = yy / 800;
                    // wallZ = noise(xx * 0.02, yy * 0.02) * DIM * params.warpDepth / 1.3;
                    xVal = map(xx, 0, DIM, 0, 1200);
                    yVal = map(yy, 0, DIM, 0, 1200);
                    wallZ = noise(xVal * .02, yVal * .02) * DIM * params.warpDepth / 1.3;
               } else if (warpType == "WAVES") {
                    xVal = map(xx, 0, DIMW, 0, TWO_PI * 4);
                    yVal = map(yy, 0, DIM, 0, TWO_PI * 4);
                    wallZ = cos(xVal) * DIM * params.warpDepth * 0.25;
               } else if (warpType == "EGGCARTON") {
                    xVal = map(xx, -DIMW / 2, DIMW / 2, 0, PI * 11);
                    yVal = map(yy, -DIM / 2, DIM / 2, 0, PI * 11);
                    wallZ = (cos(xVal) * cos(yVal)) * DIM * params.warpDepth * 0.25;
               } else if (warpType == "SADDLE") {
                    xVal = map(xx, 0, DIMW / 2, 0, sqrt(DIMW));
                    yVal = map(yy, 0, DIM / 2, 0, sqrt(DIM));
                    wallZ = (sq(xVal) - sq(yVal)) * 2 * params.warpDepth;
               }

               if (warpType == "NOISE") {
                    if (abs(xx) < DIMW / 2 && abs(yy) < DIM / 2) {
                         point(xx, yy, wallZ);
                    }
               } else {
                    point(xx, yy, wallZ);
               }
          }
     }
}

function shadow() {

     for (var i = 0; i < numPts; i++) {
          for (var j = 0; j < i; j++) {
               line(ptsA[i].x, ptsA[i].y, ptsA[j].x, ptsA[j].y);
          }
     }
}

function rnd() {
     seed ^= seed << 13
     seed ^= seed >> 17
     seed ^= seed << 5

     let result = (((seed < 0) ? ~seed + 1 : seed) % 1000) / 1000
     return result
}

function rndMap(min, max) {
     return map(rnd(), 0, 1, min, max + 1);
}

function generateSeedFromTokenData(token) {

     return parseInt(tokenData.hash.slice(0, 16), 16);
}

function setupParametersFromTokenData(token) {
     let hashPairs = []
     for (let j = 0; j < 32; j++) {
          hashPairs.push(tokenData.hash.slice(2 + (j * 2), 4 + (j * 2)));
     }
     return hashPairs.map(x => {
          return parseInt(x, 16);
     })
}

function mapd(n, start1, stop1, start2, stop2) {
     return ((n - start1) / (stop1 - start1)) * (stop2 - start2) + start2;
}

function mapParam(n, start, stop) {
     return mapd(n, 0, 255, start, stop);
}

function random_hash() {
     let chars = "0123456789abcdef";
     let result = '0x';
     for (let i = 64; i > 0; --i) result += chars[Math.floor(Math.random() * chars.length)];
     return result;
}

class Node {

     constructor(pt, allpts, nSlices, col1, col2) {
          this.pt = pt;
          this.allpts = allpts;
          this.nSlices = nSlices;
          this.col1 = color(col1);
          this.col2 = color(col2);

          this.connections = [];
          this.cols = [];
     }

     connectTo(to) {
          this.to = to;
          this.connections[this.to] = [];
          var thisCol = color(this.col1);
          var targetCol = color(this.col2);
          var t = this.to / numPts;
          this.cols[this.to] = lerpColor(thisCol, targetCol, t);
          let h = sqrt(sq(abs(this.allpts[this.pt].x - this.allpts[this.to].x)) + sq(abs(this.allpts[this.pt].y - this.allpts[this.to].y)));
          let unit = h / this.nSlices;


          for (var p = 0; p <= this.nSlices; p++) {
               var f = p / this.nSlices;
               var dx = this.allpts[this.to].x - this.allpts[this.pt].x;
               var dy = this.allpts[this.to].y - this.allpts[this.pt].y;

               var fx = this.allpts[this.pt].x + f * dx;
               var fy = this.allpts[this.pt].y + f * dy;
               this.connections[this.to][p] = createVector(fx, fy, 0);
          }
     }

     render(rTo) {

          var myCol = color(this.cols[rTo]);
          stroke(myCol);
          fill(0, 0, 0, 0);
          var c1x, c1y, c1z, p1x, p1y, p1z, p2x, p2y, p2z, c2x, c2y, c2z;
          var start = this.connections[rTo][0].copy();
          var last = this.connections[rTo].length - 1;
          var end = this.connections[rTo][last].copy();

          curve(start.x, start.y, start.z, start.x, start.y, start.z, this.connections[rTo][1].x, this.connections[rTo][1].y, this.connections[rTo][1].z, this.connections[rTo][1].x, this.connections[rTo][1].y, this.connections[rTo][1].z);

          for (var k = 1; k < this.connections[rTo].length - 2; k++) {
               c1x = this.connections[rTo][k - 1].x;
               c1y = this.connections[rTo][k - 1].y;
               c1z = this.connections[rTo][k - 1].z;
               p1x = this.connections[rTo][k].x;
               p1y = this.connections[rTo][k].y;
               p1z = this.connections[rTo][k].z;
               p2x = this.connections[rTo][k + 1].x;
               p2y = this.connections[rTo][k + 1].y;
               p2z = this.connections[rTo][k + 1].z;
               c2x = this.connections[rTo][k + 2].x;
               c2y = this.connections[rTo][k + 2].y;
               c2z = this.connections[rTo][k + 2].z;
               curve(c1x, c1y, c1z, p1x, p1y, p1z, p2x, p2y, p2z, c2x, c2y, c2z);
          }

          curve(this.connections[rTo][last - 2].x, this.connections[rTo][last - 2].y, this.connections[rTo][last - 2].z, this.connections[rTo][last - 1].x, this.connections[rTo][last - 1].y, this.connections[rTo][last - 1].z, end.x, end.y, end.z, end.x, end.y, end.z);
     }


     warp(index, mode, modeVar1, modeVar2) {
          var xVal, yVal;
          for (var k = 0; k < this.connections[index].length; k++) {

               if (mode == "MOUND") {
                    xVal = map(this.connections[index][k].x, 0, DIMW, TWO_PI, 0);
                    yVal = map(this.connections[index][k].y, 0, DIM, TWO_PI, 0);
                    this.connections[index][k].z = -(cos(xVal) + cos(yVal)) * DIM * params.warpDepth;
               } else if (mode == "2MOUNDS") {
                    xVal = map(this.connections[index][k].x, 0, DIMW, 0, TWO_PI * 2) + PI;
                    yVal = map(this.connections[index][k].y, 0, DIM, 0, TWO_PI);
                    this.connections[index][k].z = (cos(xVal) + cos(yVal)) * DIM * params.warpDepth * 0.5;
               } else if (mode == "NOISE") {
                    noiseDetail(2, 0.2);
                    xVal = map(this.connections[index][k].x, 0, DIM, 0, 1200);
                    yVal = map(this.connections[index][k].y, 0, DIM, 0, 1200);
                    this.connections[index][k].z = noise(xVal * .02, yVal * .02) * DIM * params.warpDepth / 1.3;
               } else if (mode == "WAVES") {
                    xVal = map(this.connections[index][k].x, 0, DIMW, 0, TWO_PI * 4);
                    yVal = map(this.connections[index][k].y, 0, DIM, 0, TWO_PI * 4);
                    this.connections[index][k].z = cos(xVal) * DIM * params.warpDepth * 0.25;
               } else if (mode == "EGGCARTON") {
                    xVal = map(this.connections[index][k].x, -DIMW / 2, DIMW / 2, 0, PI * 11);
                    yVal = map(this.connections[index][k].y, -DIM / 2, DIM / 2, 0, PI * 11);
                    this.connections[index][k].z = (cos(xVal) * cos(yVal)) * DIM * params.warpDepth * 0.25;
               } else if (mode == "SADDLE") {
                    xVal = map(this.connections[index][k].x, 0, DIMW / 2, 0, sqrt(DIM));
                    yVal = map(this.connections[index][k].y, 0, DIM / 2, 0, sqrt(DIM));
                    this.connections[index][k].z = (sq(xVal) - sq(yVal)) * 2 * params.warpDepth;
               }
          }
     }
}