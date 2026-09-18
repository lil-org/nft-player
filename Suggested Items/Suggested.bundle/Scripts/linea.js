console.log(tokenData.hash)
class R {
  constructor(seed) {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substr(0, 8), 16);
      let b = parseInt(uint128Hex.substr(8, 8), 16);
      let c = parseInt(uint128Hex.substr(16, 8), 16);
      let d = parseInt(uint128Hex.substr(24, 8), 16);
      return function () {
        a |= 0; b |= 0; c |= 0; d |= 0;
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
    this.prngA = new sfc32(seed.substr(2, 32));
    // seed prngB with second half of tokenData.hash
    this.prngB = new sfc32(seed.substr(34, 32));
    for (let i = 0; i < 1e6; i += 2) {
      this.prngA();
      this.prngB();
    }
  }
  // random number between 0 (inclusive) and 1 (exclusive)
  rD() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  // random number between a (inclusive) and b (exclusive)
  rB(a, b) {
    return a + (b - a) * this.rD();
  }
  // random integer between a (inclusive) and b (inclusive)
  // requires a < b for proper probability distribution
  rI(a, b) {
    return Math.floor(this.rB(a, b + 1));
  }
  // random value in an array of items
  rC(list) {
    return list[this.rI(0, list.length - 1)];
  }
}

function distance(x1, y1, x2, y2) {
  const dx = x2 - x1;
  const dy = y2 - y1;
  return Math.sqrt(dx*dx + dy*dy);
}

const rng = new R(tokenData.hash)
let initialPoints = []
let ps = []

let inverted = rng.rB(0, 1) > 0.5
let horMargin = rng.rC([0.05, 0.1, 0.2, 0.3])
let maxY = rng.rC([0.1, 0.2])
let lineHeight = rng.rC([0.02, 0.05, 0.1, 0.2])
let verticalMargin = rng.rC([0.05, 0.1, 0.2])
let coherentLines = rng.rB(0, 1) > 0.8

let xControl = rng.rC([0.02, 0.05, 0.1, 0.2])
let yControl = rng.rC([0.02, 0.05, 0.1, 0.2])
let xMin = rng.rC([0.001, 0.002, 0.003, 0.01, 0.02, 0.05])
let xMax = rng.rC([0.001, 0.002, 0.003, 0.01, 0.02, 0.05])
let yBoundary = rng.rC(verticalMargin === 0.5 ? [0.05, 0.1, 0.2, 0.4, 0.5] : [0.001, 0.002, 0.003, 0.01, 0.02, 0.05, 0.1])
let backThreshold = rng.rC([0.5, 0.6, 0.7, 0.8, 0.9])
let maxIterations = rng.rC([1000, 10000, 50000, 100000])
let lineDirection = rng.rC(['l', 'r'])
let lineTypes = rng.rC([
  ['b', 'c', 'l'],
  ['b', 'c'],
  ['c', 'l'],
  ['b', 'l'],
  ['b'],
  ['c'],
  ['l'],
])
let pointDistanceCheck = rng.rC([0.003, 0.005, 0.01, 0.05])

let size = 'live'
let sizes = {
  '3h': {xin: 16.5, yin: 11.7, width: '420mm', height: '297mm'},
  '4h': {xin: 11.7, yin: 8.3, width: '297mm', height: '210mm'},
  '5h': {xin: 8.3, yin: 5.8, width: '210mm', height: '148.5mm'},
  '6h': {xin: 5.8, yin: 4.1, width: '148.5mm', height: '105mm'},
  '1015h': {xin: 5.91, yin: 3.94, width: '150mm', height: '100mm'},
  'xsh': {xin: 5.2, yin: 3.35, width: '132mm', height: '85mm'},
  'bch': {xin: 3.35, yin: 2.165355, width: '85mm', height: '55mm'},
  '3v': {xin: 11.7, yin: 16.5, width: '297mm', height: '420mm'},
  '4v': {xin: 8.3, yin: 11.7, width: '210mm', height: '297mm'},
  '5v': {xin: 5.8, yin: 8.3, width: '148.5mm', height: '210mm'},
  '6v': {xin: 4.1, yin: 5.8, width: '105mm', height: '148.5mm'},
  '1015v': {xin: 3.94, yin: 5.91, width: '100mm', height: '150mm'},
  'xsv': {xin: 3.35, yin: 5.2, width: '85mm', height: '132mm'},
  'live': {}
}
let dpi = 100;
let ns = 'http://www.w3.org/2000/svg';
let svg = document.createElementNS(ns, 'svg');
let strokeW, xin, yin, w, h, aspectRatioCorrection

function setup() {
  if (size === 'live') {
    sizes[size] = {
      xin: windowWidth * 0.0104166667,
      yin: windowHeight * 0.0104166667,
      width: windowWidth * 0.2645833333 + 'mm',
      height: windowHeight * 0.2645833333 + 'mm'
    }
  }
  xin = sizes[size].xin
  yin = sizes[size].yin
  aspectRatioCorrection = (sizes[size].xin/sizes[size].yin)
  width = sizes[size].width
  height = sizes[size].height
  strokeW = Math.max(xin, yin)/11.7
  w = xin * dpi;
  h = yin * dpi;
  noCanvas();
  svg.setAttribute('width', windowWidth);
  svg.setAttribute('height', windowHeight);
  svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
  svg.setAttribute('style', 'background-color:#fff;fill:none;stroke-width:' + strokeW + ';stroke:#0f0f0f');
  let bounds = document.createElementNS(ns, 'path');
  bounds.setAttribute('d', `M 0 0 M ${w} ${h}`);
  svg.appendChild(bounds);
  for (let i=verticalMargin; i<1.001-verticalMargin; i+=lineHeight) {
    if (coherentLines) {
      initialPoints.push({
        y: i, yOrigin: i,
        xControl: xControl,
        yControl: yControl,
        xMin: xMin,
        xMax: xMax,
        yBoundary: yBoundary,
        backThreshold: backThreshold,
        lineTypes: lineTypes,
        maxIterations: maxIterations,
        lineDirection: lineDirection
      })
    } else {
      initialPoints.push({
        y: i, yOrigin: i,
        xControl: rng.rC([0.01, 0.05, 0.1, 0.2]),
        yControl: rng.rC([0.01, 0.05, 0.1, 0.2]),
        xMin: rng.rC([0.001, 0.002, 0.003, 0.01, 0.02, 0.05]),
        xMax: rng.rC([0.001, 0.002, 0.003, 0.01, 0.02, 0.05]),
        yBoundary: rng.rC(verticalMargin === 0.5 ? [0.05, 0.1, 0.2, 0.4, 0.5] : [0.001, 0.002, 0.003, 0.01, 0.02, 0.05, 0.1]),
        backThreshold: rng.rC([0.5, 0.6, 0.7, 0.8, 0.9]),
        lineTypes: rng.rC([
          ['b', 'c', 'l'],
          ['b', 'c'],
          ['c', 'l'],
          ['b', 'l'],
          ['b'],
          ['c'],
          ['l'],
        ]),
        maxIterations: rng.rC([1000, 10000, 50000, 100000]),
        lineDirection: coherentLines ? lineDirection : rng.rC(['l', 'r'])
      })
    }
  }
  for (const p of initialPoints) {
    let xPos
    let endPos
    if (p.lineDirection === 'l') {
      xPos = 1-horMargin
      endPos = horMargin
    } else if (p.lineDirection === 'r') {
      xPos = horMargin
      endPos = 1-horMargin
    }
    let yPos = p.y
    let xCon = xPos
    let yCon = yPos
    let counter = 0
    while ((p.lineDirection === 'r' ? (xPos < endPos) : (xPos > endPos)) && counter < p.maxIterations) {
      let found = false
      for (let i = ps.length-1; i>=0 && !found; i--) {
        if (distance(xPos, yPos, ps[i].x, ps[i].y) < pointDistanceCheck) found = true
      }
      if (!found) {
        ps.push({
          x: xPos,
          y: yPos,
          s: rng.rC(p.lineTypes),
          xc: xCon,
          yc: yCon,
        })
      }
      let backProb = rng.rB(0, 1) > p.backThreshold ? -1 : 1
      if (p.lineDirection === 'l') {
        xPos -= rng.rB(p.xMin, p.xMax) * backProb
      } else if (p.lineDirection === 'r') {
        xPos += rng.rB(p.xMin, p.xMax) * backProb
      }
      yPos += rng.rB(-p.yBoundary, p.yBoundary)
      if (yPos > p.yOrigin+p.yBoundary) yPos = rng.rC([p.yOrigin+p.yBoundary, p.yOrigin])
      if (yPos < p.yOrigin-p.yBoundary) yPos = rng.rC([p.yOrigin-p.yBoundary, p.yOrigin])
      if (verticalMargin !== 0.5) {
        if (yPos > 1-verticalMargin) yPos = 1-verticalMargin
        if (yPos < verticalMargin) yPos = verticalMargin
      } else {
        if (yPos > 0.99) yPos = 0.99
        if (yPos < 0.01) yPos = 0.01
      }
      if (xPos < horMargin) xPos = horMargin
      if (xPos > 1-horMargin) xPos = 1-horMargin
      xCon = xPos + rng.rB(-p.xControl, p.xControl)
      yCon = yPos + rng.rB(-p.yControl, p.yControl)
      if (verticalMargin !== 0.5) {
        if (yCon > 1-verticalMargin) yCon = 1-verticalMargin
        if (yCon < verticalMargin) yCon = verticalMargin
      } else {
        if (yCon > 0.99) yCon = 0.99
        if (yCon < 0.01) yCon = 0.01
      }
      if (xCon < horMargin) xCon = horMargin
      if (xCon > 1-horMargin) xCon = 1-horMargin
      counter++
    }
  }
}

function draw() {

  let g = document.createElementNS(ns, 'g');
  g.setAttribute('id', 'g');
  let path = document.createElementNS(ns, 'path');
  let d = `M ${(ps[0].x)*w} ${(ps[0].y)*h}`

  for (let i=0; i<ps.length-1; i++) {
    if (ps[i].s === 'b') {
      d += `C ${(ps[i].xc)*w} ${(ps[i].yc)*h} ${(ps[i+1].xc)*w} ${(ps[i+1].yc)*h} ${(ps[i+1].x)*w} ${(ps[i+1].y)*h}`
    }
    if (ps[i].s === 'c') {
      d += `Q ${(ps[i].xc)*w} ${(ps[i].yc)*h} ${(ps[i+1].x)*w} ${(ps[i+1].y)*h}`
    }
    if (ps[i].s === 'l') {
      d += `L ${(ps[i+1].x)*w} ${(ps[i+1].y)*h}`
    }
  }

  path.setAttribute(
    'd', d
  );
  g.appendChild(path);
  svg.appendChild(g);
  document.body.appendChild(svg);
  noLoop()
}


function keyPressed() {
  if (keyCode === 83) {
    svg.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    var svgData = svg.outerHTML;
    var preface = '<?xml version="1.0" standalone="no"?>\r\n';
    var svgBlob = new Blob([preface, svgData], {type:"image/svg+xml;charset=utf-8"});
    var svgUrl = URL.createObjectURL(svgBlob);
    var downloadLink = document.createElement("a");
    downloadLink.href = svgUrl;
    downloadLink.download = 'linea_' + size + '_' + tokenData.hash + '.svg';
    document.body.appendChild(downloadLink);
    downloadLink.click();
    document.body.removeChild(downloadLink);
  }
}
