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
    // seed prngA with first half of tokenData.hash
    this.prngA = new sfc32(tokenData.hash.substr(2, 32));
    // seed prngB with second half of tokenData.hash
    this.prngB = new sfc32(tokenData.hash.substr(34, 32));
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
}
let R = new Random();

// define and preload stream shader
let stream;
let vertexShader = `
attribute vec3 aPosition;
attribute vec2 aTexCoord;
varying vec2 pos;

void main() {
  // copy the texcoords
  pos = aTexCoord;
  vec4 positionVec4 = vec4(aPosition, 1.0);
  positionVec4.xy = positionVec4.xy * 2.0 - 1.0;
  gl_Position = positionVec4;
}
`;
let fragmentShader = `
#ifdef GL_ES
precision highp float;
#endif

varying vec2 pos;
uniform sampler2D texture;

// multiplier to scale to screen size
uniform vec2 M;
// ratios of screen dims to base dims
uniform vec2 Sxy;
// pixel density of display
uniform float D;
// screen values to calculate offsets later
uniform float OFFSETX;
uniform float OFFSETY;

// stream function
uniform float psiMult;
uniform float psiOffset;
uniform bool useDivergenceInPsi;
// velocity potential
uniform float phiMult;
uniform float phiOffset;
uniform bool useVorticityInPhi;

const int maxElements = 14;
uniform int activeElements;
uniform float elementsX[14];
uniform float elementsY[14];
uniform float vortexStrengths[14];
uniform float divergences[14];

uniform int paletteIndex;
uniform bool limitHueMatlab;

uniform float hueStaticOffset;
uniform bool migraine;
uniform float saturation;

// gets stream and velocity potential function values
// @dev all calculations in base coordinates
vec2 getPsiPhi(vec2 bc) {
  float psi = 0.0;
  float phi = 0.0;
  // flow elements
  for (int i = 0; i < maxElements; i++) {
    if (i >= activeElements) {
      break;
    }
    float r = distance(bc, vec2(elementsX[i], elementsY[i]));
    float theta = atan((bc.y - (elementsY[i])), (bc.x - (elementsX[i])));
    // vorticity
    psi = psi + (1.0 * vortexStrengths[i]) * log(r);
    if (useVorticityInPhi) {
      phi = phi + vortexStrengths[i] * theta;
    } else {
      if (vortexStrengths[i] < 0.0) {
        phi = phi + theta;
      } else {
        phi = phi - theta;
      }
    }
    // divergence (source/sink)
    if (useDivergenceInPsi) {
      psi = psi + divergences[i] * theta;
    } else {
      // already added theta in vorticity section
    }
    phi = phi - divergences[i] * log(r);
  }
  // uniform flow not utilized in this project
  return vec2(psi, phi);
}
// gets velocity magnitude
// @dev all calculations in base coordinates
float getVelocityMagnitude(vec2 bc) {
  float u = 0.0;
  float v = 0.0;
  // flow elements
  for (int i = 0; i < maxElements; i++) {
    if (i >= activeElements) {
      break;
    }
    float r = distance(bc, vec2(elementsX[i], elementsY[i]));
    float theta = atan((bc.y - (elementsY[i])), (bc.x - (elementsX[i])));
    // vorticity
    float vTheta = vortexStrengths[i] / r;
    u = u + vTheta * cos(theta);
    v = v + vTheta * sin(theta);
    // divergence (source/sink)
    float vR = divergences[i] / r;
    u = u + vR * cos(theta + 3.14159 / 2.0);
    v = v + vR * sin(theta + 3.14159 / 2.0);
  }
  // uniform flow not utilized in this project
  return sqrt(u * u + v * v);
}

// standard shader rgb2hsv and hsv2rgb functions
vec3 rgb2hsv(vec3 c) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void main() {
  // get virtual screen texture at pos
  vec2 uv = pos;
  vec4 screenCol = texture2D(texture, uv);
  // translate from pos to intermediate coordinates independent of pixel density
  vec2 ic = gl_FragCoord.xy / (M) / vec2(D);
  float noiseOffset = 0.0;
  // scale from intermediate to base coordinates
  vec2 bc = vec2(ic);
  bc.x = bc.x - 0.5 - (OFFSETX / (Sxy.y)) + sin(noiseOffset) * noiseOffset;
  bc.y = bc.y + 0.5 - (OFFSETY / (Sxy.x)) + cos(noiseOffset) * noiseOffset;

  // calculate stream function and velocity potential in base coordinates
  vec2 psiPhi = getPsiPhi(bc);
  float psi = psiPhi.x;
  float phi = psiPhi.y;

  // initialize variables
  float i;
  float j; 
  vec3 flowFieldColor;
  vec3 particleColor;
  // assign colors based on palette
  if (paletteIndex == 0) {
    // Inclusion
    i = sin(psi * psiMult + psiOffset);
    j = cos(phi * phiMult + phiOffset);
    flowFieldColor = vec3(j - i, j - i, i - j);
    vec3 flowFieldHSV = rgb2hsv(flowFieldColor);
    flowFieldHSV = vec3(flowFieldHSV.r, 1.3 - abs(j) / 2.0, flowFieldHSV.b);
    flowFieldColor = hsv2rgb(flowFieldHSV);
    float limit = 0.5;
    if (flowFieldHSV.b < limit) {
      flowFieldHSV.g = 0.0;
      flowFieldHSV.b = limit;
    } else {
      flowFieldHSV.b = limit + 3.0 * (flowFieldHSV.b - limit);
    }
    particleColor = hsv2rgb(vec3(flowFieldHSV.r, flowFieldHSV.g, flowFieldHSV.b));
  } else if (paletteIndex == 1) {
    // Rainbow
    i = cos(psi * psiMult + psiOffset / 4.0) * 0.2;
    j = cos(phi * phiMult + phiOffset / 4.0) * 0.2;
    flowFieldColor = hsv2rgb(vec3(fract((i + j) / 2.0 * 3.1415926535), saturation, 1.0));
    particleColor = hsv2rgb(vec3(fract((i + j) / 2.0 * 3.1415926535), 0.3, 1.0));
  } else if (paletteIndex == 2) {
    // Skip
    i = cos(psi * psiMult / 2.0 + psiOffset);
    j = sin(phi * phiMult + phiOffset);
    flowFieldColor = vec3(cos(psi * psiMult / 2.0), j, i);
    vec3 flowFieldHSV = rgb2hsv(flowFieldColor);
    float s = saturation;
    if (migraine) {
      if (i > 0.75) {
        s = (3.0 + saturation) - (4.0 * i);
      }
    }
    flowFieldHSV = vec3(fract(flowFieldHSV.r + cos(psi * psiMult)), s, 1.0);
    flowFieldColor = hsv2rgb(flowFieldHSV);
    particleColor = hsv2rgb(vec3(flowFieldHSV.r, min(s, 0.3), 1.0));
  } else if (paletteIndex == 3) {
    // Form
    i = cos(psi * psiMult + 0.34 * psiOffset);
    j = cos(phi * phiMult + phiOffset);
    float i2 = cos(psi * psiMult + 0.44 * psiOffset + fract(j));
    flowFieldColor = vec3(0, -i + j, -i);
    vec3 flowFieldHSV = rgb2hsv(flowFieldColor);
    float v = 1.0 - j;
    float h = flowFieldHSV.r + i;
    float s = saturation;
    if (j < 0.0) {
      v = 0.7 - 0.5 + 0.5 * i2;
      s = 0.2 + 0.5 - 0.5 * i2;
      h = fract(0.5 * j + 0.25 * i + psiOffset * 0.11);
    }
    flowFieldHSV = vec3(h, s, v);
    flowFieldColor = hsv2rgb(flowFieldHSV);
    if (j < 0.0) {
      flowFieldHSV.g = saturation - 0.2;
      flowFieldHSV.b = 1.0;
    }
    particleColor = hsv2rgb(flowFieldHSV);
  } else if (paletteIndex == 4) {
    // Overload
    i = cos(psi * psiMult + 0.94 * psiOffset);
    j = cos(phi * phiMult + phiOffset);
    flowFieldColor = vec3(0, -i + j, -i);
    vec3 flowFieldHSV = rgb2hsv(flowFieldColor);
    float v = 1.0 - j;
    if (j > 0.0) {
      v = abs(i + j);
    } else {
      v = 1.0;
    }
    flowFieldHSV = vec3(flowFieldHSV.r + i, saturation, v);
    flowFieldColor = hsv2rgb(flowFieldHSV);
    if (j < 0.0) {
      flowFieldHSV.g = saturation - 0.2;
      flowFieldHSV.b = 1.0;
    }
    particleColor = hsv2rgb(flowFieldHSV);
  } else if (paletteIndex == 5) {
    // Step
    i = cos(psi * 6.0 + psiOffset / 10.0) * 0.2;
    j = cos(phi + phiOffset / 10.0);
    flowFieldColor = vec3(i, j + 0.85, 0.0);
    vec3 flowFieldHSV = rgb2hsv(flowFieldColor);
    flowFieldHSV.r = flowFieldHSV.r + cos(psi * psiMult + psiOffset / 10.0);
    flowFieldHSV.g = flowFieldHSV.g * 0.75;
    flowFieldHSV.b = flowFieldHSV.b * 0.5;
    flowFieldColor = hsv2rgb(flowFieldHSV);
    particleColor = hsv2rgb(vec3(flowFieldHSV.r, flowFieldHSV.g - 0.1, flowFieldHSV.b + 0.1));
  } else {
    // Monochromatic
    i = cos(psi * psiMult + 0.94 * psiOffset);
    j = cos(phi * phiMult + phiOffset);
    float k = cos(phi * phiMult + phiOffset + 3.14);
    flowFieldColor = vec3(1.0, 0, 0);
    vec3 flowFieldHSV = rgb2hsv(flowFieldColor);
    float v;
    if (j > 0.0) {
      v = abs(i + j) + fract(0.5 * j + 0.25 * i + 0.5 + psiOffset * 0.11);
    } else {
      v = abs(k);
    }
    float actualStaticOffset = floor(hueStaticOffset * 6.0) / 6.0;
    if (abs(actualStaticOffset - 0.5) < 0.01) {
      actualStaticOffset = 0.6666;
    }
    if (abs(actualStaticOffset - 0.8333) < 0.01) {
      actualStaticOffset = 0.0;
    }
    flowFieldHSV = vec3(fract(actualStaticOffset), 0.7, v);
    flowFieldColor = hsv2rgb(flowFieldHSV);
    if (j < 0.0) {
      flowFieldHSV.g = saturation - 0.2;
      flowFieldHSV.b = 1.0;
    }
    particleColor = hsv2rgb(flowFieldHSV);
  } 
  // POST PROCESSING
  // Remap hue from red to blue only, emulating default MATLAB contour plot behavior
  if (limitHueMatlab) {
    vec3 flowFieldHSV = rgb2hsv(flowFieldColor);
    if (flowFieldHSV.r > 0.5) {
      flowFieldHSV.r = 0.5 - (flowFieldHSV.r - 0.5);
    }
    flowFieldHSV.r = flowFieldHSV.r * 0.666 / 0.500;
    flowFieldColor = hsv2rgb(flowFieldHSV);
    vec3 particleHSV = rgb2hsv(particleColor);
    if (particleHSV.r > 0.5) {
      particleHSV.r = 0.5 - (particleHSV.r - 0.5);
    }
    particleHSV.r = particleHSV.r * 0.666 / 0.500;
    particleColor = hsv2rgb(particleHSV);
  }

  // DRAW
  if (screenCol.r < 0.05) {
    // DRAW FLOW FIELD
    gl_FragColor = vec4(flowFieldColor, 1.0);
  } else {
    // DRAW PARTICLE
    gl_FragColor = vec4(mix(particleColor, flowFieldColor, 1.0 - (screenCol.r+screenCol.g) / 2.0), 1.0);
  }
}
`;
const TARGET_FRAME_RATE = 60;

// --- COORDINATE SYSTEMS ---
// base coordinate system is 1000 x 1000
var BASE_SIZE = 1000;
// translate to window size
var WIDTH = window.innerWidth;
var HEIGHT = window.innerHeight;
var DIM = Math.min(WIDTH, HEIGHT);
var S = DIM / BASE_SIZE;
var SX = WIDTH / BASE_SIZE;
var SY = HEIGHT / BASE_SIZE;
// we center the base coordinate system on the screen
var OFFSETX = (WIDTH - DIM) / 2;
var OFFSETY = (HEIGHT - DIM) / 2;

// utility functions to return window coordinate from base coordinate
function M(value) {
  return value * S;
}
function Mx(x) {
  return x * S + OFFSETX;
}
function My(y) {
  return y * S + OFFSETY;
}

// --- DEFAULT CONFIGURATION ---
const CONFIG = {
  backCol: [0, 0, 0],
  numParticles: [350, 1000],
  probabilityNoParticles: 0.1,
  // a multiplier that applies to the particle velocities only
  numElements: [2, 4],
  numStaticElements: [2, 3],
  // note: vortex strength is circulation / 2PI
  vortexStrengthRange: [-23, 23],
  vortexStrengthMultiplier: 1,
  allowZeroVortexStrength: true,
  useVorticityInPhi: false,
  // source/sink
  probabilityElementsMayDiverge: 0.9,
  probabilityElementHasDivergence: 1.0,
  divergenceRange: [-10, 10],
  divergenceStrengthMultiplier: 1,
  allowZeroDivergence: false,
  useDivergenceInPsi: false,
  // other
  phiMult: [1, 1],
  // element positioning
  elementBorder: 0.1,
  // particles
  particleVelocityMult: 6,
  maxParticleSpeed: 10,
  particleFrameChanceOfRespawn: 0.01,
  respawnRadiusIncrement: 0.05,
  respawnRadiusDecrement: 0.03,
  particleStrokeWeights: [1, 3, 5],
  particleStrokeWeightProbabilities: [0.15, 0.75, 0.1],
  backgroundAlpha: [10, 40],
};

// returns a choice from choices based on probabilities (which must sum to 1)
function getWeightedChoice(choices, probabilities) {
  let x = R.random_dec();
  let i = 0;
  let sum_ = 0.0;
  while (i < probabilities.length - 1) {
    sum_ += probabilities[i];
    if (x < sum_) {
      break;
    }
    i++;
  }
  return choices[i];
}

// --- COLOR PALETTES ---
PALETTES = [
  {
    name: "Inclusion",
    index: 0,
    psiMult: [1, 1],
    psiOffsetMultiplier: [1.0, 1.0],
    phiOffsetMultiplier: "equal",
    // require divergence
    probabilityElementsMayDiverge: 1.0,
  },
  {
    name: "Rainbow",
    index: 1,
    psiMult: [0.1, 0.1],
    psiOffsetMultiplier: [0.1, 0.4],
    phiOffsetMultiplier: "equal",
    saturation: [0.75, 0.85],
    numStaticElements: [4, 4],
    noParticles: false,
    maxParticleSpeed: 5.0,
  },
  {
    name: "Skip",
    index: 2,
    psiMult: [0.05, 0.1],
    psiOffsetMultiplier: [0.2, 0.25],
    phiOffsetMultiplier: "equal",
    // require divergence
    probabilityElementsMayDiverge: 1.0,
    hueStaticOffset: [0.0, 1.0],
    probabilityMigraine: 0.1,
    saturation: [0.75, 0.85],
    limitHueMatlab: true,
    maxParticleSpeed: 5.0,
  },
  {
    name: "Form",
    index: 3,
    psiMult: [0.05, 0.1],
    psiOffsetMultiplier: [0.2, 0.6],
    phiOffsetMultiplier: "equal",
    // require divergence
    probabilityElementsMayDiverge: 1.0,
    maxParticleSpeed: 5.0,
    saturation: [0.5, 0.8],
    probabilityHighFlowElements: 0.15,
    highFlowElementsRange: [5, 14],
    limitHueMatlab: true,
  },
  {
    name: "Overload",
    index: 4,
    psiMult: [0.05, 0.1],
    psiOffsetMultiplier: [0.04, 0.2],
    phiOffsetMultiplier: "equal",
    // require divergence
    probabilityElementsMayDiverge: 1.0,
    maxParticleSpeed: 5.0,
    saturation: [0.5, 0.8],
    probabilityHighFlowElements: 0.15,
    highFlowElementsRange: [5, 14],
  },
  {
    name: "Step",
    index: 5,
    psiMult: [0.03, 0.03],
    psiOffsetMultiplier: [0.5, 0.5],
    phiOffsetMultiplier: [1, 1],
    noParticles: false,
    alwaysParticles: true,
    particleVelocityMult: 20.0,
    maxParticleSpeed: 30.0,
    // require divergence
    probabilityElementsMayDiverge: 1.0,
    saturation: [0.75, 0.85],
    limitHueMatlab: true,
  },
  {
    name: "Monochromatic",
    index: 6,
    psiMult: [0.05, 0.1],
    psiOffsetMultiplier: [0.04, 0.2],
    phiOffsetMultiplier: "equal",
    // require divergence
    probabilityElementsMayDiverge: 1.0,
    maxParticleSpeed: 5.0,
    hueStaticOffset: [0.0, 1.0],
    probabilityHighFlowElements: 0.2,
    highFlowElementsRange: [5, 14],
  },
];

PALETTE_PROBABILITIES = [
  0.0, // 0 Inclusion (only token #21)
  0.2, // 1 Rainbow
  0.1, // 2 Skip
  0.2, // 3 Form
  0.3, // 4 Overload
  0.1, // 5 Step
  0.1, // 6 Monochromatic
];
// determine the color palette
let paletteRand = R.random_dec();
let paletteIndex = 0;
let _sum = 0;
while (paletteRand > _sum) {
  _sum += PALETTE_PROBABILITIES[paletteIndex];
  paletteIndex++;
}
// token #21 is always Inclusion
if (tokenData.tokenId % 1_000_000 == 21) {
  paletteIndex = 1; // Inclusion's index plus 1
}
let PALETTE = PALETTES[paletteIndex - 1];
console.log("Flows: Token ID = ", tokenData.tokenId.toString());
console.log("Flows: Palette = ", PALETTE.name);

// helper function to get a palette override or default scalar value
function getPaletteOrDefault(propName) {
  return PALETTE[propName] !== undefined ? PALETTE[propName] : CONFIG[propName];
}

// helper function to get random value between two points
function randInterp(range, useParabolic) {
  let interpDec = R.random_dec();
  if (useParabolic) {
    interpDec = interpDec * interpDec;
  }
  return range[0] + interpDec * (range[1] - range[0]);
}

// initialize the configuration details
const potentialParticles = PALETTE.numParticlesOverride
  ? R.random_int(...PALETTE.numParticlesOverride)
  : R.random_int(...CONFIG.numParticles);
const NUM_PARTICLES = PALETTE.noParticles
  ? 0
  : R.random_bool(CONFIG.probabilityNoParticles) && !PALETTE.alwaysParticles
  ? 0
  : potentialParticles;
CONFIG.particleStrokeWeightProbabilities = getPaletteOrDefault(
  "particleStrokeWeightProbabilities"
);
if (NUM_PARTICLES > 0) {
  CONFIG.particleStrokeWeight = getWeightedChoice(
    CONFIG.particleStrokeWeights,
    CONFIG.particleStrokeWeightProbabilities
  );
  const PARTICLE_SIZE_LABELS = {
    1: "Small",
    3: "Normal",
    5: "Large",
  };
  console.log(
    "Flows: Particle Size = ",
    PARTICLE_SIZE_LABELS[CONFIG.particleStrokeWeight]
  );
}
CONFIG.particleVelocityMult = getPaletteOrDefault("particleVelocityMult");
CONFIG.maxParticleSpeed = getPaletteOrDefault("maxParticleSpeed");
CONFIG.probabilityElementsMayDiverge = getPaletteOrDefault(
  "probabilityElementsMayDiverge"
);
CONFIG.particleFrameChanceOfRespawn = getPaletteOrDefault(
  "particleFrameChanceOfRespawn"
);
CONFIG.elementsMayDiverge = R.random_bool(CONFIG.probabilityElementsMayDiverge);
CONFIG.vortexStrengthRange = getPaletteOrDefault("vortexStrengthRange");
CONFIG.divergenceRange = getPaletteOrDefault("divergenceRange");
CONFIG.psiMult = randInterp(PALETTE.psiMult, true);
CONFIG.phiMult = randInterp(CONFIG.phiMult, true);
CONFIG.useVorticityInPhi = getPaletteOrDefault("useVorticityInPhi");
CONFIG.useDivergenceInPsi = getPaletteOrDefault("useDivergenceInPsi");
CONFIG.backgroundAlpha = randInterp(CONFIG.backgroundAlpha, true);
CONFIG.psiOffsetMultiplier = randInterp(PALETTE.psiOffsetMultiplier, false);
if (PALETTE.phiOffsetMultiplier == "equal") {
  CONFIG.phiOffsetMultiplier = CONFIG.psiOffsetMultiplier;
} else {
  CONFIG.phiOffsetMultiplier = randInterp(PALETTE.phiOffsetMultiplier, false);
}
CONFIG.hueStaticOffset =
  PALETTE.hueStaticOffset != undefined
    ? randInterp(PALETTE.hueStaticOffset, false)
    : 0.0;
CONFIG.migraine =
  PALETTE.probabilityMigraine != undefined
    ? R.random_bool(PALETTE.probabilityMigraine)
    : false;
CONFIG.saturation =
  PALETTE.saturation != undefined ? randInterp(PALETTE.saturation, false) : 0.0;

// --- ELEMENT CONFIGS ---
const ELEMENTS = [];
// populate vortex arrays
let NUM_ELEMENTS = R.random_int(...CONFIG.numElements);
if (PALETTE.probabilityHighFlowElements != undefined) {
  if (R.random_bool(PALETTE.probabilityHighFlowElements)) {
    NUM_ELEMENTS = R.random_int(...PALETTE.highFlowElementsRange);
  }
}
CONFIG.numStaticElements = getPaletteOrDefault("numStaticElements");
let NUM_STATIC_ELEMENTS = Math.min(
  NUM_ELEMENTS,
  R.random_int(...CONFIG.numStaticElements)
);
if (CONFIG.elementsMayDiverge) {
  NUM_STATIC_ELEMENTS = NUM_ELEMENTS;
}
console.log("Flows: Num Flow Elements = ", NUM_ELEMENTS.toString());

// utility function to get target time in seconds since start.
// assumes that TARGET_FRAME_RATE is set, and ensures that project's
// display is never a function of display actual frame rate
function time_() {
  try {
    return frameCount / TARGET_FRAME_RATE;
  } catch (error) {
    return 0;
  }
}

class Element {
  constructor(isStatic) {
    this.initialize();
    this.isStatic = isStatic;
  }

  // sets vorticity, divergene, and initial position of element
  initialize() {
    this.respawn();
    // assign vorticity
    let _vortexStrength = 0;
    while (_vortexStrength === 0) {
      _vortexStrength = R.random_int(...CONFIG.vortexStrengthRange);
      if (CONFIG.allowZeroVortexStrength) {
        break;
      }
    }
    this.vortexStrength = _vortexStrength * CONFIG.vortexStrengthMultiplier;
    // assign divergence
    let _divergence = 0;
    if (
      CONFIG.elementsMayDiverge &&
      R.random_bool(CONFIG.probabilityElementHasDivergence)
    ) {
      while (_divergence === 0) {
        _divergence = R.random_int(...CONFIG.divergenceRange);
        if (CONFIG.allowZeroDivergence) {
          break;
        }
      }
    }
    this.divergence = _divergence * CONFIG.divergenceStrengthMultiplier;
  }

  _getRandomValidPosition() {
    return R.random_int(
      BASE_SIZE * CONFIG.elementBorder,
      BASE_SIZE * (1 - CONFIG.elementBorder)
    );
  }

  // changes position of element
  respawn() {
    this.x = this._getRandomValidPosition();
    this.y = this._getRandomValidPosition();
  }

  // operates in base coordinates
  getVelocity(_atPosition) {
    // get radial distance from vortex to point
    const r = pointDistance(this.x, this.y, _atPosition[0], _atPosition[1]);
    if (r === 0) {
      // avoid divide by zero, very, very edge case, return zero velocity
      return [0, 0];
    }
    // calc theta, 90 degrees
    const theta =
      Math.PI / 2 + pointAngle(this.x, this.y, _atPosition[0], _atPosition[1]);
    // --- Vorticity ---
    const v_theta = this.getVortexStrength() / r;
    // return velocity in cartesian reference frame, with particle gamma multiplier
    let vx = v_theta * Math.cos(theta) * CONFIG.particleVelocityMult;
    let vy = v_theta * Math.sin(theta) * CONFIG.particleVelocityMult;
    // --- Source/Sink ---
    const v_r = this.getDivergence() / r;
    vx += v_r * Math.cos(theta + Math.PI / 2) * CONFIG.particleVelocityMult;
    vy += v_r * Math.sin(theta + Math.PI / 2) * CONFIG.particleVelocityMult;
    // --- Uniform Flow not utilized in this project ---
    return [vx, vy];
  }

  getVortexStrength() {
    return this.vortexStrength;
  }

  getDivergence() {
    return this.divergence;
  }
}

// populate global elements array
for (let i = 0; i < NUM_ELEMENTS; i++) {
  const _isStatic = i < NUM_STATIC_ELEMENTS;
  ELEMENTS.push(new Element(_isStatic));
}

// shift view to geometric center of all flow elements
let centerX = 0;
let centerY = 0;
for (let i = 0; i < NUM_ELEMENTS; i++) {
  centerX += ELEMENTS[i].x;
  centerY += ELEMENTS[i].y;
}
centerX /= NUM_ELEMENTS;
centerY /= NUM_ELEMENTS;
for (let i = 0; i < NUM_ELEMENTS; i++) {
  ELEMENTS[i].x -= centerX - BASE_SIZE / 2;
  ELEMENTS[i].y -= centerY - BASE_SIZE / 2;
}

// returns distance between two points
const pointDistance = (x1, y1, x2, y2) => {
  return Math.sqrt(Math.pow(x2 - x1, 2) + Math.pow(y2 - y1, 2));
};

// returns angle in radians between two points
const pointAngle = (x1, y1, x2, y2) => {
  return Math.atan2(y2 - y1, x2 - x1);
};

// returns velocity [u, v] at a point due to all flow elements.
// operates in base coordinates
function getVelocityAtPoint(_position) {
  let v = [0, 0];
  for (let i = 0; i < NUM_ELEMENTS; i++) {
    const elV = ELEMENTS[i].getVelocity(_position);
    v[0] += elV[0];
    v[1] += elV[1];
  }
  return v;
}

// updates position of all non-static vortices.
// operates in base coordinates
function updateElementPositions() {
  DxDy = [];
  for (let i = 0; i < NUM_ELEMENTS; i++) {
    const DxDyi = [0, 0];
    if (!ELEMENTS[i].isStatic) {
      // calculate velocity at element due to all other elements
      for (let j = 0; j < NUM_ELEMENTS; j++) {
        if (i != j) {
          const elV = ELEMENTS[j].getVelocity([ELEMENTS[i].x, ELEMENTS[i].y]);
          DxDyi[0] += elV[0];
          DxDyi[1] += elV[1];
        }
      }
    }
    DxDy.push(DxDyi);
  }
  // update positions
  for (let i = 0; i < NUM_ELEMENTS; i++) {
    ELEMENTS[i].x += DxDy[i][0];
    ELEMENTS[i].y += DxDy[i][1];
  }
}

class Particle {
  constructor() {
    this.respawn(true);
  }

  beginRespawn() {
    this.isRespawning = true;
  }

  respawn(instantCreate) {
    // restart line end point
    this.xlast = undefined;
    this.ylast = undefined;
    this.ulast = undefined;
    this.vlast = undefined;
    // update position
    this.x = R.random_dec() * 1.88 * BASE_SIZE - BASE_SIZE * 0.44;
    this.y = R.random_dec() * 1.88 * BASE_SIZE - BASE_SIZE * 0.44;
    // update velocity
    const vel = getVelocityAtPoint([this.x, this.y]);
    this.u = vel[0];
    this.v = vel[1];
    if (instantCreate) {
      this._radiusMultiplier = 1.0;
    }
    this.isRespawning = false;
  }

  updatePosition() {
    const vel = getVelocityAtPoint([this.x, this.y]);
    // check if particle is moving too fast
    if (Math.sqrt(vel[0] ** 2 + vel[1] ** 2) > CONFIG.maxParticleSpeed) {
      this._radiusMultiplier = 0.0;
      this.respawn(false);
    } else {
      // update previous position and velocity
      this.xlast = this.x;
      this.ylast = this.y;
      this.ulast = this.u;
      this.vlast = this.v;
      this.x += vel[0];
      this.y += vel[1];
      this.u = vel[0];
      this.v = vel[1];
    }
  }

  draw() {
    if (this.xlast != undefined) {
      screen.strokeWeight(
        M(CONFIG.particleStrokeWeight * this._radiusMultiplier)
      );
      screen.curve(
        Mx(this.xlast - this.ulast),
        My(this.ylast - this.vlast),
        Mx(this.xlast),
        My(this.ylast),
        Mx(this.x),
        My(this.y),
        Mx(this.x + this.u),
        My(this.y + this.v)
      );
    }
    if (R.random_dec() < CONFIG.particleFrameChanceOfRespawn) {
      this.beginRespawn();
    }
  }

  frameChecks() {
    if (this.isRespawning) {
      this._radiusMultiplier -= CONFIG.respawnRadiusDecrement;
      if (this._radiusMultiplier <= 0) {
        this.respawn(false);
      }
    } else if (this._radiusMultiplier < 1.0) {
      this._radiusMultiplier = Math.min(
        1.0,
        this._radiusMultiplier + CONFIG.respawnRadiusIncrement
      );
    }
  }
}

const PARTICLES = [];
for (let i = 0; i < NUM_PARTICLES; i++) {
  PARTICLES.push(new Particle());
}

function setup() {
  // create WEBGL canvas
  createCanvas(WIDTH, HEIGHT, WEBGL);
  stream = createShader(vertexShader, fragmentShader);
  // create off-screen screen buffer
  screen = createGraphics(WIDTH, HEIGHT);
  // define screen defaults
  screen.background(0);
  screen.stroke(255);
  screen.strokeWeight(M(CONFIG.particleStrokeWeight));
  // set pixel density to display density for animated piece
  let density = displayDensity();
  pixelDensity(density);

  // set active shader
  shader(stream);

  // set shader resolution-related uniforms
  stream.setUniform("M", [M(1), M(1)]);
  stream.setUniform("Sxy", [SX, SY]);
  stream.setUniform("D", density);
  stream.setUniform("WIDTH", WIDTH);
  stream.setUniform("HEIGHT", HEIGHT);
  stream.setUniform("OFFSETX", OFFSETX);
  stream.setUniform("OFFSETY", OFFSETY);
  // set shader vortex-related uniforms
  stream.setUniform("activeElements", ELEMENTS.length);
  stream.setUniform("useVorticityInPhi", CONFIG.useVorticityInPhi);
  stream.setUniform("useDivergenceInPsi", CONFIG.useDivergenceInPsi);
  frameRate(TARGET_FRAME_RATE);

  stream.setUniform("paletteIndex", PALETTE.index);
  stream.setUniform("limitHueMatlab", PALETTE.limitHueMatlab || false);

  // other constants
  stream.setUniform("hueStaticOffset", CONFIG.hueStaticOffset);
  stream.setUniform("migraine", CONFIG.migraine);
  stream.setUniform("saturation", CONFIG.saturation);
}

function draw() {
  // update vortex positions and assign in shader
  updateElementPositions();

  // define vortex positions in shader, in base coordinates
  stream.setUniform("elementsX", [...ELEMENTS.map((_el) => _el.x)]);
  stream.setUniform("elementsY", [...ELEMENTS.map((_el) => _el.y)]);
  stream.setUniform("vortexStrengths", [
    ...ELEMENTS.map((_el) => _el.getVortexStrength()),
  ]);
  stream.setUniform("divergences", [
    ...ELEMENTS.map((_el) => _el.getDivergence()),
  ]);

  // set multipliers and offsets
  stream.setUniform("psiMult", CONFIG.psiMult);
  stream.setUniform("phiMult", CONFIG.phiMult);
  stream.setUniform("phiOffset", -time_() * CONFIG.phiOffsetMultiplier);
  stream.setUniform("psiOffset", -time_() * CONFIG.psiOffsetMultiplier);

  // draw background
  screen.background(0, CONFIG.backgroundAlpha);

  for (let i = 0; i < NUM_PARTICLES; i++) {
    PARTICLES[i].updatePosition();
    PARTICLES[i].frameChecks();
    PARTICLES[i].draw();
  }
  // Give the shader a surface to draw on;
  stream.setUniform("texture", screen);
  rect(-WIDTH / 2, -HEIGHT / 2, WIDTH, HEIGHT);
}
