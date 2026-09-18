// Find a non-minified and better commented version of this script online at the artist's website. Copyright Matthew Costanza 2021
let hV, hb, binL, tkB, shape, shapeI, sRef, sIRef, pattB, pBRef, pattI, pIRef, isS, midPs, recP, recS, pal, ar, cW, cH, minD, s, col, arm, w, b, a, v, g, r, p;
let binP = 0;
let gR = 0.618;
let def = 0.382;
let allPattP = [];
let allSP = [];
let showShape = true;
calculateFeatures(tokenData);
setDim();

function calculateFeatures(tD) {
  tkB = tD.tokenId % 2;
  hV = cHVal(tD.hash);
  hb = cHBin(hV);
  binL = hb.length;
  w = "#ffffff";
  b = "#000000";
  a = "#275bb2";
  v = "#43AA8B";
  g = "#fcd612";
  r = "#b10b0b";
  p = "#f368cb";
  shape = gV(1, 9);
  if (shape < 4) {
    ar = 1;
  } else if (shape < 7) {
    ar = 2;
  } else {
    ar = 3;
  }
  shapeI = gV(1, 5);
  pattB = gV(1, 100);
  if (pattB > 62) { 
    pattB = 1;
  } else if (pattB > 42) { 
    pattB = 2;
  } else if (pattB > 22) { 
    pattB = 3;
  } else if (pattB > 2) { 
    pattB = 4;
  } else { 
    pattB = 5;
  }
  pattI = gV(1, 11);
  if (pattI < 4 && pattB == 2) {
    pattB = 1;
  } 
  midPs = gV(1,6);
  midPs = 2 ** midPs - 1;
  if (midPs == 1 && (pattB == 2 || pattI == 7 || pattI == 8)) {
    midPs = 3;
  }
  if (midPs < 5 && pattI == 9) {
    midPs = 5;
  }
  recP = gV(0, 5);
  rP = 2 ** recP;
  recS = gV(0, 3);
  if ((shape == 6 || shape == 9) && shapeI == 1) {
    rS = 1;
  } else if (shapeI == 4) {
    rS = 2;
  } else if ((shape == 6 || shape == 9) && shapeI == 3) {
    rS = Math.min((3 ** recS), 5);
  } else {
    rS = 3 ** recS;
  }
  pal = gV(0, 19); 
  let cols = [
    [w, b, v, w], 
    [w, b, a, w], 
    [w, b, r, w], 
    [w, b, p, w], 
    [w, b, g, w], 
    [w, b, r, g],
    [w, b, a, g],
    [w, b, v, g],
    [b, w, v, g],
    [b, w, a, g],
    [b, g, w, g], 
    [b, w, b, w],
    [a, r, w, g],
    [a, g, w, g], 
    [a, w, v, w],
    [a, w, b, w],
    [r, w, b, g],
    [r, w, a, w],
    [v, w, a, w],
    [g, b, w, b]
  ];
  col = cols[pal];
  if (shapeI == 5 && col[1] == col[3]) {
    shapeI = 2;
  }
  if (rS == 1 && (shapeI == 3 || shapeI == 5)) {
    shapeI = 2;
  }
  if (shapeI == 2 && rS > 1) {
    rS = 1;
  }
  if (pattB == 5 && pattI == 11) {
    if (shapeI == 2 || shapeI == 1) {
      isS = "Portal";
    } else {
      isS = "Truth";
    }
  } else {
    isS = "Yes";
  }

  function cHVal(TH) {
    let h = [];
    for (let i = 0; i < (TH.length - 2) / 2; i++) {
      h.push(parseInt(TH.slice(2 + i * 2, 4 + i * 2), 16));
    }
    return h;
  }
  
  function cHBin(H) {
    let b = '';
    for (let i = 0; i < H.length - 1; i++) {
      let t = H[i].toString(2);
      b = b + t;
    }
    return b;
  }
  
  function gV(min, max) {
    max = max + 0.999; 
    let x = Math.floor((hV[0] * (max - min)) / 255 + min);
    hV.shift();
    return x;
  }  
}

function setDim() {
  binP = 0;
  let winW = window.innerWidth;
  let winH = window.innerHeight;
  minD = Math.min(winW, winH);
  if (ar == 1) {
    arm = 1;
    cW = minD;
    cH = minD;
  } else if (ar == 2) {
    arm = gR;
    if (winW / winH >= gR) {
      cH = winH;
      cW = Math.floor(gR * cH);
    } else {
      cW = winW;
      cH = Math.floor(cW / gR);
    }
  } else if (ar == 3) {
    arm = 1 / gR;
    if (winH / winW >= gR) {
      cW = winW;
      cH = Math.floor(gR * cW);
    } else {
      cH = winH;
      cW = Math.floor(cH / gR);
    }
  }
  u = (Math.max(cW, cH)) / 300;
}
function windowResized() {
  allPattP = [];
  allSP = [];
  setDim()
  resizeCanvas(cW, cH);
}

function getBin() {
  let b = hb[binP];
  binP = (binP + 1 != binL) ? binP + 1 : 0;
  return b;
}

function keyPressed() {
  if (key === 's') {
    saveCanvas('FOCUS-' + `${tokenData.tokenId}` + '_hash-' + `${tokenData.hash}` + '_RecursionFactor-' + `${rP}` + '_midpoints-' + `${midPs}` + '_shape-' + `${showShape}`, 'png')
  } else if (key === 'h') {
    if (showShape == true) {
      showShape = false;
    } else {
      showShape = true;
    }
    windowResized()
  } else if (keyCode === RIGHT_ARROW) {
    midPs +=2;
    windowResized();
  } else if (keyCode === LEFT_ARROW) {
    midPs > 1 ? midPs -= 2 : midPs = 1;
    windowResized();
  } else if (keyCode === UP_ARROW) {
    rP += 1;
    windowResized();
  } else if (keyCode === DOWN_ARROW) {  
    rP > 1 ? rP -= 1 : rP = 1;
    windowResized();
  } 
}

function setup() {
  createCanvas(cW, cH);
  angleMode(DEGREES);
}function draw() {
  background(col[0]);
  strokeWeight(u * 0.8);
  stroke(col[1]);
  let m = 2 * u;
  let tEC = cH * def * gR;
  let wEC = cW * def * gR;
  let hH = cH / 2;
  let hW = cW / 2;
  pattSides = [
    [[m, m], [cW - m, m]],
    [[cW - m, m], [cW - m, cH - m]],
    [[cW - m, cH - m], [m, cH - m]],
    [[m, cH - m], [m, m]]
  ];
  let recFP = [
    [[m, m], [cW - m, m]],
    [[cW - m, m], [cW - m, cH - m]],
    [[cW - m, cH - m], [m, cH - m]],
    [[m, cH - m], [m, m]]
  ];
  let cenP = [
    [[hW, hH], [hW, hH]],
    [[hW, hH], [hW, hH]],
    [[hW, hH], [hW, hH]],
    [[hW, hH], [hW, hH]],
  ];
  allPattP.push(buildQuad(pattSides));
  if (rP == 1) {
    allPattP.push(buildQuad(cenP));
  }
  for (let i = 1; i < rP; i++) {
    rectRecurser(recFP, cW / 1.3, cH / 1.3, rP);
    allPattP.push(buildQuad(recFP));
  }

  let shapeSides = [];
  let wCalc = (cW - cW * def) / 2;
  let hCalc = (cH - cH * def) / 2;
  if (shape == 1 || shape == 4 || shape == 7) {
    shapeSides = [
      [[wCalc, hCalc], [cW - wCalc, hCalc]],
      [[cW - wCalc, hCalc], [cW - wCalc, cH - hCalc]],
      [[cW - wCalc, cH - hCalc], [wCalc, cH - hCalc]],
      [[wCalc, cH - hCalc], [wCalc, hCalc]]
    ];
  }
  if (shape == 2 || shape == 5 || shape == 8) {
    shapeSides = [
      [[wCalc, hH], [hW, hCalc]],
      [[hW, hCalc], [cW - wCalc, hH]],
      [[cW - wCalc, hH], [hW, cH - hCalc]],
      [[hW, cH - hCalc], [wCalc, hH]]
    ];
  }
  if (shape != 3 && shape != 6 && shape != 9) {
    for (let i = 1; i <= rS; i++) {
      allSP.push(buildQuad(shapeSides));
      if (shape == 1 || shape == 4 || shape == 7) {
        rectRecurser(shapeSides, cW / 1.66, cH / 1.66, rS);
      }
      if (shape == 2 || shape == 5 || shape == 8) {
        diamRecurser(shapeSides, cW / 1.66, rS);
      }
    }
  }
  if (shape == 3) { 
    let cP = (midPs + 1) * 4;
    let radi = cW * def /2;
    for (let i = 1; i <= rS; i++) {
      let points = [];
      points.push(circumP(cP,radi));
      allSP.push(points);
      radi = radi - radi / 4;
    }
  }
  function circumP(cP, radi) {
    let ps = [];
    for (let i = 0; i < cP; i++) {
      let x = (radi * Math.cos((2 * Math.PI * i) / cP)) + hW;
      let y = (radi * Math.sin((2 * Math.PI * i) / cP)) + hH;
      ps.push([x, y]);
    }
    return ps;
  }
  if (shape == 6 || shape == 9) {
    let cP = midPs + 1;
    let side1 = [];
    let side2 = [];
    for (let i = 0; i <= cP; i++) {
      let t = i / cP;
      if (shape == 6) {
        side1.push(getCurvePoints(cW + wEC, 0, hW, hCalc, hW, cH - hCalc, cW + wEC, cH, t));
        side2.push(getCurvePoints(-wEC, cH, hW, cH - hCalc, hW, hCalc, -wEC, 0, t));
      } else {
        side1.push(getCurvePoints(0, cH + tEC, wCalc, hH, cW - wCalc, hH, cW, cH + tEC, t));
        side2.push(getCurvePoints(cW, - tEC, cW - wCalc, hH, wCalc, hH, 0, - tEC, t));
      }
      function getCurvePoints(c1x, c1y, x1, y1, x2, y2, c2x, c2y, t) {
        x = curvePoint(c1x, x1, x2, c2x, t);
        y = curvePoint(c1y, y1, y2, c2y, t);
        let p = [x, y];
        return p;
      }
    }
    allSP.push([side1, side2]);
    for (let i = 1; i < rS; i++) {
      let lastSet = allSP.length -1;
      let newSet = [];
      for (let crv = 0; crv <2; crv ++){
        let newPs = [];
        for (let v = 0; v < allSP[lastSet][crv].length; v++) {
          let oldP = allSP[lastSet][crv][v];
          let newX, newY;
          if (shape == 6) {
            newY = ((oldP[1] - hH)) * .88 + hH;
            newX = oldP[0];
          } else {
            newX = ((oldP[0] - hW)) * .88 + hW;
            newY = oldP[1];
          }
          newPs.push([newX,newY]);
        }
        newSet.push(newPs);
      }
    allSP.push(newSet);
    }
  }

  function rectRecurser(ss, xLim, yLim, r) {
    let xD = (xLim - ss[0][0][0]) / r;
    let yD = (yLim - ss[0][0][1]) / r;
    ss[0][0][0] += xD;
    ss[0][0][1] += yD;
    ss[0][1][0] -= xD;
    ss[0][1][1] += yD;
    ss[1][0][0] -= xD;
    ss[1][0][1] += yD;
    ss[1][1][0] -= xD;
    ss[1][1][1] -= yD;
    ss[2][0][0] -= xD;
    ss[2][0][1] -= yD;
    ss[2][1][0] += xD;
    ss[2][1][1] -= yD;
    ss[3][0][0] += xD;
    ss[3][0][1] -= yD;
    ss[3][1][0] += xD;
    ss[3][1][1] += yD;
  }

  function diamRecurser(ss, xLim, r) {
    let xD = (xLim - ss[0][0][0])/r;
    ss[0][0][0] += xD;
    ss[0][1][1] += xD;
    ss[1][0][1] += xD;
    ss[1][1][0] -= xD;
    ss[2][0][0] -= xD;
    ss[2][1][1] -= xD;
    ss[3][0][1] -= xD;
    ss[3][1][0] += xD;
  }

  function buildQuad(qSides) {
    rectMode(CENTER);
    let allP = [];
    let sideP = [];
    for (let side = 0; side < 4; side++) {
      sideP = lineBreaker(qSides[side][0], qSides[side][1]);
      allP.push(sideP);
    }
    return allP;
    function lineBreaker(p1, p2) {
      let lineP = [[...p1]];
      for (let i = 1; i < midPs + 2; i++) {
        lineP.push(getPoint(p1, p2, i / (midPs + 1)));
      }
      lineP.push([...p2]);
      return lineP;
      function getPoint(p1, p2, t) {
        let newX = t * (p2[0] - p1[0]) + p1[0];
        let newY = t * (p2[1] - p1[1]) + p1[1];
        let point = [newX, newY];
        return point;
      }
    }
  }  drawStyle(allPattP, pattI, true);

  let cMem = col[2];
  if (showShape == true) {
    if (shapeI == 1) {
      noFill();
    } else { 
      fill(col[3]);
    }
    if (shape == 1) {
      rect(hW, hH, cW * def, cH * def);
    } 
    if (shape == 4) {
      rect(hW, hH, tEC, cH * def);
    } 
    if (shape == 7) {
      rect(hW, hH, cW * def, wEC);
    } 
    if (shape == 2 || shape == 5 || shape == 8) {
      quad(hW, hCalc, cW - wCalc, hH, hW, cH - hCalc, wCalc, hH);
    } 
    if (shape == 3) {
      circle(hW, hH, cW * def);
    } 
    if (shape == 6) {
      if (shapeI != 1) {
        strokeWeight(u * 2);
        stroke(col[3]);
        line(hW, hCalc + 2 * u, hW, cH - hCalc - 2 * u);
        strokeWeight(u * 0.8);
        stroke(col[1]);
      }
      dTE(0);
    } 
    if (shape == 9) {
      if (shapeI != 1) {
        strokeWeight(u * 2);
        stroke(col[3]);
        line(wCalc + 2 * u, hH, cW - wCalc - 2 * u, hH);
        strokeWeight(u * 0.8);
        stroke(col[1]);
      }
      dWE(0);
    }
    if (shapeI == 5) {
      drawStyle(allSP, 4, false);
    }
    if (rS == 2) {
      if (col[0] != col[3]) {
      col[2] = col[0];
      }
    }
    if (shapeI == 1 || shapeI == 3 || rS == 2) {
      if (shapeI !=1) {
        noStroke();
      } else {
        noFill();
      }
      if (shape != 3 && shape != 6 && shape != 9) {
        for (let i = 1; i < allSP.length; i++) {
          if (shapeI != 1) {
            fill(col[3 - (i % 2)]);
          }
          quad(allSP[i][0][0][0], allSP[i][0][0][1], allSP[i][1][0][0], allSP[i][1][0][1], allSP[i][2][0][0], allSP[i][2][0][1], allSP[i][3][0][0], allSP[i][3][0][1]);
        }
      } else if (shape == 3) {
        let rr = cW * def;
        for (let i = 1; i < rS; i++) {
          rr = rr - rr / 4;
          if (shapeI != 1) {
            fill(col[3 - (i % 2)]);
          }
          circle(hW, hH, rr);
        }
      } else {
        let fdist = Math.max(Math.abs(allSP[0][0][0][0] - allSP[0][1][0][0]), Math.abs(allSP[0][0][0][1] - allSP[0][1][0][1])) / 4;
        rr = 0;
        let fMem;
        for (let i = 1; i < rS; i++) {
          rr = rr - fdist;
          fMem = col[3 - (i % 2)];
          fill(fMem);
          strokeWeight(u * 2);
          stroke(fMem);  
          if (shape == 6) {
            line(hW, hCalc + 2 * u, hW, cH - hCalc - 2 * u);
            strokeWeight(u * 0.8);
            stroke(col[3]);
            dTE(rr);
          }
          if (shape == 9) {           
            line(wCalc + 2 * u, hH, cW - wCalc - 2 * u, hH);
            strokeWeight(u * 0.8);
            stroke(col[3]);
            dWE(rr);
          }
        }
        stroke(col[1]);
        noFill();
        if (shape == 9) {
          dWE(0);
        }
        if (shape == 6) {
          dTE(0);
        }    
      }
    }
    function dTE(v) {
      curve(cW + wEC + v, 0, hW, hCalc, hW, cH - hCalc, cW + wEC + v, cH);
      curve(-wEC - v, 0, hW, hCalc, hW, cH - hCalc, -wEC - v, cH);
    }
    function dWE(v) {
      curve(0, cH + tEC + v, wCalc, hH, cW - wCalc, hH, cW, cH + tEC + v);
      curve(0, - tEC - v, wCalc, hH, cW - wCalc, hH, cW, - tEC - v);
    }
  } 

  function drawStyle(allP, m, patt) {
    strokeJoin(BEVEL);
    fill(col[2]);
    let dir;
    for (let i = 0; i < allP.length; i++) { 
      let ls;
      if (ar == 2) {
        ls = 1;
      } else {
        ls = 0;
      } 
      let size = Math.max((Math.abs(allP[i][ls][0][0] - allP[i][ls][allP[i][ls].length - 1][0])), Math.abs((allP[i][ls][0][1] - allP[i][ls][allP[i][ls].length - 1][1]))) / 110; 
      if (patt == true && m < 4 ) {
        fill(col[0]);
        rect(hW, hH, allP[i][0][allP[i][0].length - 1][0] - allP[i][0][0][0], allP[i][1][allP[i][1].length - 1][1] - allP[i][1][0][1]);
        dir = getBin();
        fill(col[2]);
      }
      for (let j = 0; j < allP[i].length; j++) {
        if (patt == true && pattB == 1) {
          line(allP[i][j][0][0], allP[i][j][0][1], allP[i][j][allP[i][j].length -1][0], allP[i][j][allP[i][j].length - 1][1]);
        }
        for (let k = 0; k < allP[i][j].length; k++) {
          let aPx = allP[i][j][k][0];
          let aPy = allP[i][j][k][1];  
          if (m == 1 && k + 1 < allP[i][j].length && (j < 2)) { 
              line(aPx, aPy, allP[i][j + 2][allP[i][j].length - k - 2][0], allP[i][j + 2][allP[i][j].length - k - 2][1]);
          }
          if (m == 2 && j == dir && k + 1 < allP[i][j].length) {
            if (dir == 0) {
              line(aPx, aPy, allP[i][j + 2][allP[i][j].length - k - 2][0], allP[i][j + 2][allP[i][j].length - k - 2][1]);
            } else {
              line(aPx, aPy, allP[i][j + 2][allP[i][j].length - k - 2][0], allP[i][j + 2][allP[i][j].length - k - 2][1]);
            }
          } 
          if (m == 3) {
            let len, leg2;
            let p1 = [allP[i][j][0][0], allP[i][j][0][1]];
            let p2 = [allP[i][j][allP[i][j].length - 1][0], allP[i][j][allP[i][j].length - 1][1]];
            let md = j % 2;
            let leg = Math.min(Math.abs(allP[i][j][k][md] - p1[md]), Math.abs(p2[md] - allP[i][j][k][md]));
            if (j == 0) {
              leg2 = leg / arm;
              len = Math.min(aPy + leg2, hH);
              line(aPx, aPy, aPx, len);
            } else if (j == 1) {
              leg2 = leg * arm;
              len = Math.max(aPx - leg2, hW);
              line(aPx, aPy, len, aPy);
            } else if (j == 2) {
              leg2 = leg / arm;
              len = Math.max(aPy - leg2, hH);
              line(aPx, aPy, aPx, len);
            } else if (j == 3) {
              leg2 = leg * arm;
              len = Math.min(aPx + leg2, hW);
              line(aPx, aPy, len, aPy);
            }
          }
          if (m == 4 && i + 1 < allP.length) {
            line(aPx, aPy, allP[i+1][j][k][0], allP[i+1][j][k][1]);
          }
          if (m == 5 && i + 1 < allP.length && k + 2 < allP[i][j].length) {
            line(aPx, aPy, allP[i+1][j][k+1][0], allP[i+1][j][k+1][1]);
          }
          if (m == 6 && i + 1 < allP.length && getBin() == 1) {
            line(aPx, aPy, allP[i + 1][j][k][0], allP[i + 1][j][k][1]);
          } 
          if (m == 7 && i + 1 < allP.length && k + 2 < allP[i][j].length && (k % 2 == 0)) {
            quad(aPx, aPy, allP[i][j][k+1][0], allP[i][j][k+1][1], allP[i+1][j][k+1][0], allP[i+1][j][k+1][1], allP[i+1][j][k][0], allP[i+1][j][k][1]);
          } 
          if (m == 8 && i + 1 < allP.length && k + 2 < allP[i][j].length && (k % 2 == i % 2)) {
            quad(aPx, aPy, allP[i][j][k+1][0], allP[i][j][k+1][1], allP[i+1][j][k+1][0], allP[i+1][j][k+1][1], allP[i+1][j][k][0], allP[i+1][j][k][1]);
          } 
          if (m == 9 && i + 1 < allP.length && k + 2 < allP[i][j].length && (k % 2 == i % 2) && getBin() == 1) {
            quad(aPx, aPy, allP[i][j][k+1][0], allP[i][j][k+1][1], allP[i+1][j][k+1][0], allP[i+1][j][k+1][1], allP[i+1][j][k][0], allP[i+1][j][k][1]);
          }
          if (m == 10 && i + 1 < allP.length && k + 2 < allP[i][j].length) {
            if (tkB == 0) {
              quad(aPx, aPy, allP[i][j][k+1][0], allP[i][j][k+1][1], allP[i+1][j][k][0], allP[i+1][j][k][1], aPx, aPy);
            } else {
              quad(aPx, aPy, allP[i][j][k+1][0], allP[i][j][k+1][1], allP[i+1][j][k+1][0], allP[i+1][j][k+1][1], aPx, aPy);
            }
          }
          if (patt == true) {
            noFill();
            if (pattB == 3) {
              let fS = size;
              if (u * 0.8 > size) {
                noStroke();
                fill(col[1]);
                fS = size + 0.8 * u;
              }
              circle(aPx, aPy, fS);
            }
            if (pattB == 4) {
              rect(aPx, aPy, size);
            }
            if (pattB == 2 && k % 2 == 1 && k + 1 < allP[i][j].length) {
              line(aPx, aPy, allP[i][j][k + 1][0], allP[i][j][k + 1][1]);
            }
            stroke(col[1]);
            fill(col[2]);
          }
        }
      }
    }
  }

  if (isS == "Portal") {
    stroke(col[1]);
    let bW, bSY;
    if (shape == 1 || shape == 4 || shape == 7) {
      bW = cW * def + 2*u;
      bSY = allSP[0][2][0][1]; 
    } else if (shape == 3) {
      bW = 40 * u; 
      bSY = hW + (cW * def /2);
    } else if (shape == 9) {
      bW = 15 * u; 
      bSY = allSP[0][1][(allSP[0][1].length - 1)/2][1];
    } else if (shape == 6) {
      bW = 2*u; 
      bSY = allSP[0][1][0][1];
    } else {
      bW = Math.abs(allSP[0][0][0][0] - allSP[0][2][0][0]) / 10;
      bSY = allSP[0][3][0][1];
    }
    let space = 4 * u;
    let bX1 = (hW) - (bW/2);
    let bX2 = (hW) + (bW/2);
    let yG = (cH - bSY);
    xD = bX1/(yG/space);
    line(bX1, bSY + space, bX2, bSY + space);
    for (let c = 2; c < yG / space; c++) {
      bX1 = bX1 - xD;
      bX2 = bX2 + xD;
      let xD1 = getBin() * space/2  * ((getBin() * 2) - 1);
      let xD2 = getBin() * space/2  * ((getBin() * 2) - 1);
      line(bX1 - xD1, bSY + c * space, bX2 + xD2, bSY + c * space);
    } 
  }
  col[2] = cMem;
  noLoop();
}