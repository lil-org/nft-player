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
let finalPs = []
let angleBoundaryOptions = [0.3, 0.5, 1, 2, 3]
let charsPerLineOptions = [5, 10, 20, 30, 40, 50]
let maxLengthOptions = [200, 500, 1000, 2000, 3000]
let contOptions = [20, 50, 100]
let angContOptions = [10, 20, 50, 100, 200, 400]

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

let horMargin = rng.rC([0.05, 0.1])
let deduplicateDistanceCheck = rng.rC([0.0005, 0.001, 0.002])
let numChars = rng.rI(2, 21)
let charEnlargementFactor = numChars < 5 ? rng.rC([20, 50, 100]) : rng.rC([5, 10, 20])
let charEnlargement = charEnlargementFactor/numChars
if (charEnlargement < 1) {
  charEnlargement = 1
}

let initialPointsY = []
for (let i=1; i<numChars; i++) {
  initialPointsY.push(i/numChars)
}
let lineHeight = 1/numChars*2-0.01
let bouncyX = rng.rB(0, 1) > 0.5
let bouncyY = rng.rB(0, 1) > 0.5
let breakX = rng.rB(0, 1) > 0.5
let breakY = rng.rB(0, 1) > 0.5
let minPoints = numChars < 5 ? rng.rC([100, 200, 500]) : rng.rC([50, 100, 200])
let xOver = rng.rC([1, 2])

console.log('angleBoundary ' + angleBoundary)
console.log('coherentBoundary ' + coherentBoundary)
console.log('maxCharsPerLine ' + maxCharsPerLine)
console.log('coherentLines ' + coherentLines)
console.log('charMaxLength ' + charMaxLength)
console.log('coherentCharLength ' + coherentCharLength)
console.log('cont ' + cont)
console.log('coherentCont ' + coherentCont)
console.log('angCont ' + angCont)
console.log('coherentAngCont ' + coherentAngCont)
console.log('charEnlargement ' + charEnlargement)
console.log('lineHeight ' + lineHeight)
console.log('horMargin ' + horMargin)
console.log('deduplicateDistanceCheck ' + deduplicateDistanceCheck)
console.log('numChars ' + numChars)
console.log('bouncyX ' + bouncyX)
console.log('bouncyY ' + bouncyY)
console.log('breakX ' + breakX)
console.log('breakY ' + breakY)
console.log('charEnlargementFactor ' + charEnlargementFactor)
console.log('xOver ' + xOver)

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

  // initial char points (lines configuration really)
  for (const i of initialPointsY) {
    initialPoints.push({
      x: 0,
      y: i,
      angleBoundary: coherentBoundary ? angleBoundary : rng.rC(angleBoundaryOptions),
      maxCharsPerLine: coherentLines ? maxCharsPerLine : rng.rC(charsPerLineOptions),
      charMaxLength: coherentCharLength ? charMaxLength : rng.rC(maxLengthOptions),
      cont: coherentCont ? cont : rng.rC(contOptions),
      angCont: coherentAngCont ? angCont : rng.rC(angContOptions),
      charEnlargement: charEnlargement,
    })
  }
  for (const p of initialPoints) {
    // compute full character per each line
    tempPs = []
    a = rng.rB(0, TWO_PI)
    aInc = rng.rB(-p.angleBoundary, p.angleBoundary)
    x = p.x
    y = p.y
    yLimit = lineHeight
    xLimit = (1-2*horMargin)/(p.maxCharsPerLine+1)/xOver
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
        })
      }
      x += cos(a)*(0.001)*p.charEnlargement
      y += sin(a)*(0.001)*p.charEnlargement
      if (y > p.y+yLimit) {
        y = p.y+yLimit
        if (bouncyY) {
          a += PI
        }
        if (breakY && tempPs.length > minPoints) {
          break
        }
      }
      if (y > 0.99) {
        y = 0.99
        if (bouncyY) {
          a += PI
        }
        if (breakY && tempPs.length > minPoints) {
          break
        }
      }
      if (y < p.y-yLimit) {
        y = p.y-yLimit
        if (bouncyY) {
          a += PI
        }
        if (breakY && tempPs.length > minPoints) {
          break
        }
      }
      if (y < 0.01) {
        y = 0.01
        if (bouncyY) {
          a += PI
        }
        if (breakY && tempPs.length > minPoints) {
          break
        }
      }
      if (x > xLimit) {
        x = xLimit
        if (bouncyX) {
          a += PI
        }
        if (breakX && tempPs.length > minPoints) {
          break
        }
      }
      if (x > horMargin) {
        x = horMargin
        if (bouncyX) {
          a += PI
        }
        if (breakX && tempPs.length > minPoints) {
          break
        }
      }
      if (x < -xLimit) {
        x = -xLimit
        if (bouncyX) {
          a += PI
        }
        if (breakX && tempPs.length > minPoints) {
          break
        }
      }
      if (x < -horMargin) {
        x = -horMargin
        if (bouncyX) {
          a += PI
        }
        if (breakX && tempPs.length > minPoints) {
          break
        }
      }
    }
    ps.push(tempPs)
  }
  console.log(ps)
}

function draw() {
  let g = document.createElementNS(ns, 'g');
  g.setAttribute('id', 'g');
  // each row
  for (let j=0; j<ps.length; j++) {
    // each char within row
    for (let k=1; k<ps[j][0].maxCharsPerLine+1; k++) {
      let charToDraw = ps[j].slice(0, k/(ps[j][0].maxCharsPerLine)*ps[j].length)
      let horAdjustment = horMargin+(1-2*horMargin)/ps[j][0].maxCharsPerLine*k
      if (charToDraw && charToDraw.length > 0) {
        let path = document.createElementNS(ns, 'path');
        let d = `M ${(charToDraw[0].x/aspectRatioCorrection+horAdjustment)*w} ${(charToDraw[0].y)*h}`
        // each point within char
        for (let i=1; i<charToDraw.length-1; i++) {
          d += `L ${(charToDraw[i].x/aspectRatioCorrection+horAdjustment)*w} ${(charToDraw[i].y)*h}`
        }
        path.setAttribute(
          'd', d
        );
        g.appendChild(path);
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
    downloadLink.download = 'carattere_' + size + '_' + tokenData.hash + '.svg';
    document.body.appendChild(downloadLink);
    downloadLink.click();
    document.body.removeChild(downloadLink);
  }
}
