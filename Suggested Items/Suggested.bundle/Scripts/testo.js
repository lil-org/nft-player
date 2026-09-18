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
let finalPs = []
let angleBoundaryOptions = [0.3, 0.5, 1, 2, 3]
let charsPerLineOptions = [5, 10, 20, 30, 40, 50, 100]
let maxLengthOptions = [200, 500, 1000, 2000, 3000]
let contOptions = [20, 50, 100, 200]
let angContOptions = [10, 20, 50, 100, 200, 400, 500]
let enlargementOptions = [0.5, 1, 2, 3, 5, 10]

let angleBoundary = rng.rC(angleBoundaryOptions)
let coherentBoundary = rng.rB(0, 1) > 0.5
let maxCharsPerLine = rng.rC(charsPerLineOptions)
let coherentLines = rng.rB(0, 1) > 0.5
let charMaxLength = rng.rC(maxLengthOptions)
let coherentCharLength = rng.rB(0, 1) > 0.5
let cont = rng.rC(contOptions)
let coherentCont = rng.rB(0, 1) > 0.5
let angCont = rng.rC(angContOptions)
let coherentAngCont = rng.rB(0, 1) > 0.5
let charEnlargement = rng.rC(enlargementOptions)
let coherentEnlargement = rng.rB(0, 1) > 0.5
let yOver = rng.rB(0, 1) > 0.5
let coherentYOver = rng.rB(0, 1) > 0.5
let xOver = rng.rB(0, 1) > 0.5
let coherentXOver = rng.rB(0, 1) > 0.5
let allConnected = rng.rB(0, 1) > 0.8
let horizontalConnection = rng.rB(0, 1) > 0.5
let endWordThreshold = rng.rC([0.6, 0.8, 0.9, 0.95, 0.99])

let lineHeight = rng.rC([0.01, 0.02, 0.04, 0.05, 0.1, 0.2])
let charDist = rng.rC([0.01, 0.02, 0.05])
let horMargin = rng.rC([0.05, 0.1, 0.2])
let verMargin = rng.rC([0.05, 0.1, 0.2])
let deduplicateDistanceCheck = rng.rC([0.0005, 0.001, 0.002])

let newWordProb = {
  1: 0.01,
  2: 0.1,
  3: 0.2,
  4: 0.3,
  5: 0.5,
  6: 0.6,
  7: 0.7,
  8: 0.8,
  9: 0.9,
  10: 1
}
let size = 'live'
let sizes = {
  '3h': {xin: 16.5, yin: 11.7, width: '420mm', height: '297mm'},
  '4h': {xin: 11.7, yin: 8.3, width: '297mm', height: '210mm'},
  '5h': {xin: 8.3, yin: 5.8, width: '210mm', height: '148.5mm'},
  '6h': {xin: 5.8, yin: 4.1, width: '148.5mm', height: '105mm'},
  '1015h': {xin: 5.91, yin: 3.94, width: '150mm', height: '100mm'},
  'xsh': {xin: 5.2, yin: 3.35, width: '132mm', height: '85mm'},
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
  
  for (let i=verMargin; i<(1.001-verMargin); i+=lineHeight) {
    for (let j=horMargin; j<(1.001-horMargin); j+=charDist) {
      initialPoints.push({
        x: 0,
        y: i,
        angleBoundary: coherentBoundary ? angleBoundary : rng.rC(angleBoundaryOptions),
        maxCharsPerLine: coherentLines ? maxCharsPerLine : rng.rC(charsPerLineOptions),
        charMaxLength: coherentCharLength ? charMaxLength : rng.rC(maxLengthOptions),
        cont: coherentCont ? cont : rng.rC(contOptions),
        angCont: coherentAngCont ? angCont : rng.rC(angContOptions),
        charEnlargement: coherentEnlargement ? charEnlargement : rng.rC(enlargementOptions),
        yOver: coherentYOver ? yOver : rng.rB(0, 1) > 0.5,
        xOver: coherentXOver ? xOver : rng.rB(0, 1) > 0.5,
        lastCharProb: rng.rB(0, 1),
        s: j,
      })
    }
  }

  for (const p of initialPoints) {
    tempPs = []
    a = rng.rB(0, TWO_PI)
    aInc = rng.rB(-p.angleBoundary, p.angleBoundary)
    x = p.x
    y = p.y
    for (let i = 0; i<p.charMaxLength; i++) {
      if (i%p.angCont === 0) {
        a = rng.rB(0, TWO_PI)
      }
      if (i%p.cont === 0) {
        aInc = rng.rB(-p.angleBoundary, p.angleBoundary)
      }
      a += aInc
      found = false
      for (const prevP of tempPs) {
        if (distance(x, y, prevP.x, prevP.y) < deduplicateDistanceCheck) {
          found = true
        }
        if (found) {
          break
        }
      }
      if (!found) {
        tempPs.push({
          x: x,
          y: y,
          maxCharsPerLine: p.maxCharsPerLine,
          lastCharProb: p.lastCharProb,
          s: p.s,
        })
      }
      x += cos(a)*(0.001)*p.charEnlargement
      y += sin(a)*(0.001)*p.charEnlargement
      if (Math.abs(y-p.y) > (p.yOver ? lineHeight : lineHeight/2) || Math.abs(x-p.x) > charDist*(xOver ? 1 : 0.5)) {
        break
      }
      if (x > horMargin) {
        break
      }
      if (x < -horMargin) {
        break
      }
      if (y > 1-verMargin) {
        break
      }
      if (y < verMargin) {
        break
      }
    }
    ps.push(tempPs)
  }
}

function draw() {
  let g = document.createElementNS(ns, 'g');
  g.setAttribute('id', 'g');
  if (allConnected) {
    let path = document.createElementNS(ns, 'path');
    let d = `M ${(ps[0][0].x/aspectRatioCorrection + ps[0][0].s)*w} ${(ps[0][0].y)*h}`
    for (let j=0; j<ps.length; j++) {
      for (let i=0; i<ps[j].length-1; i++) {
        d += `L ${(ps[j][i].x/aspectRatioCorrection + ps[j][i].s)*w} ${(ps[j][i].y)*h}`
      }
    }
    path.setAttribute(
      'd', d
    );
    g.appendChild(path);
  } else {
    let currentCharCount = 0
    let path = document.createElementNS(ns, 'path');
    let d = `M ${(ps[0][0].x/aspectRatioCorrection + ps[0][0].s)*w} ${(ps[0][0].y)*h}`
    for (let j=0; j<ps.length; j++) {
      for (let i=0; i<ps[j].length-1; i++) {
        d += `L ${(ps[j][i].x/aspectRatioCorrection + ps[j][i].s)*w} ${(ps[j][i].y)*h}`
      }
      path.setAttribute(
        'd', d
      );
      currentCharCount++
      if (j < ps.length-1 && 
        (ps[j][0].lastCharProb < newWordProb[currentCharCount] || Math.abs(ps[j][0].y - ps[j+1][0].y) > lineHeight/2)) {
        g.appendChild(path);
        path = document.createElementNS(ns, 'path');
        d = `M ${(ps[j+1][0].x/aspectRatioCorrection + ps[j+1][0].s)*w} ${(ps[j+1][0].y)*h}`
        currentCharCount = 0
      }
    }
  }

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
    downloadLink.download = 'testo_' + size + '_' + tokenData.hash + '.svg';
    document.body.appendChild(downloadLink);
    downloadLink.click();
    document.body.removeChild(downloadLink);
  }
}
