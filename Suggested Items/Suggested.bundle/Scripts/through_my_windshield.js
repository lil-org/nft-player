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
let myShader;
let timer = 0;
let timerInc = .002;
let colorIndex = 0
let wave1x;
let wave1y;
let wave2x;
let wave2y;
let wave3x;
let wave3y;
let wave4x;
let wave4y;
let wave5x;
let wave5y;

let vave1;
let vave2;
let vave3;
let vave4;
let vave5;

let water1x;
let water2x;
let water3x;
let water4x;
let water5x;
let water1y;
let water2y;
let water3y;
let water4y;
let water5y;

let palette = [];
let _palette = [];


let myModels = [];
let windowWidth2 = 0
let windowHeight2 = 0;

function createMesh() {
  for (let i = 0; i < 1; i++) {
    let myModel = new p5.Geometry();
    let vertices = [];
    let faces = [];
    let uvs = [];
    let grid = [];
    let count = 0;
    myModel.gid = "uniqueName" + i;
    for (let y = 0; y <= windowHeight; y += 100) {
      let row = [];
      for (let x = 0; x <= windowWidth; x += 100) {
        const u = map(x, 0, windowWidth, 0, 1);
        const v = map(y, 0, windowHeight, 0, 1);

        uvs.push(u, v);
        vertices.push(new p5.Vector(x, y, 0));
        row.push(count);
        count++
      }
      grid.push(row);
    }
    for (let i = 0; i < grid.length - 1; i++) {
      for (j = 0; j < grid[i].length; j++) {
        if (grid[i][j] && grid[i + 1][j] && grid[i][j + 1] && grid[i + 1][j + 1]) {
          const v1 = grid[i][j];
          const v2 = grid[i][j + 1];
          const v3 = grid[i + 1][j + 1];
          const v4 = grid[i + 1][j];

          faces.push([v1, v3, v2]);
          faces.push([v1, v3, v4]);
        }
      }
    }
    myModel.vertices = vertices;
    myModel.faces = faces;
    myModel.uvs = uvs;
    myModels.push({ model: myModel })

  }
}
const lerpp = p5.Vector.lerp;
let rects = []


const vs = `
  attribute vec3 aPosition;
  attribute vec2 aTexCoord;
  uniform mat4 uProjectionMatrix;
  uniform mat4 uModelViewMatrix;
  varying vec2 vTexCoord;
  uniform float timer;
  void main ()
  {
      vTexCoord = aTexCoord;
      vec2 uv = vTexCoord;
      vec4 position = vec4(aPosition, 1.0 );
      gl_Position = uProjectionMatrix * uModelViewMatrix * position;
  }
  `;

const fs = `
  precision mediump float;
  varying vec2 vTexCoord;
  uniform float wave1x;
  uniform float wave1y;
  uniform float wave2x;
  uniform float wave2y;
  uniform float wave3x;
  uniform float wave3y;
  uniform float wave4x;
  uniform float wave4y;
  uniform float wave5x;
  uniform float wave5y;
  uniform float timerfrag;
  uniform float vave1;
  uniform float vave2;
  uniform float vave3;
  uniform float vave4;
  uniform float vave5;
  uniform float water1x;
  uniform float water2x;
  uniform float water3x;
  uniform float water4x;
  uniform float water5x;
  uniform float water1y;
  uniform float water2y;
  uniform float water3y;
  uniform float water4y;
  uniform float water5y;
  uniform vec3 rgb;
  uniform vec3 rgb2;
  uniform float range1;
  uniform float range2;
  uniform int direction;
  void main() {
    // now because of the varying vTexCoord, we can access the current texture coordinate
    vec2 uv = vTexCoord;

    float d = cos(wave1x*uv.x)*cos(wave1y*uv.y);
    d += cos(wave2x*uv.x)*cos(wave2y*uv.y);
    d += cos(wave3x*uv.x)*cos(wave3y*uv.y);
    d += cos(wave4x*uv.x)*cos(wave4y*uv.y);
    d += cos(wave5x*uv.x)*cos(wave5y*uv.y);

    d = cos(water1x*uv.x)*cos(water1y*uv.y);
    d += cos(water2x*uv.x)*cos(water2y*uv.y);
    d += cos(water3x*uv.x)*cos(water3y*uv.y);
    d += cos(water4x*uv.x)*cos(water4y*uv.y);
    if(direction == 0){
      d += cos(water5x*uv.x*timerfrag)*cos(water5y*uv.y);
    }
    if(direction == 1){
      d += cos(water5x*uv.x)*cos(water5y*uv.y*timerfrag);
    }
    if(direction == 2){
      d += cos(water5x*uv.x*timerfrag)*cos(water5y*uv.y*timerfrag);
    }

    d /= 10.0;
    d = abs(d);
    
    float d2 = cos(vave1*uv.x)*cos(vave1*uv.y);
    d2 += cos(vave2*uv.x)*cos(vave2*uv.y);
    d2 += cos(vave3*uv.x)*cos(vave3*uv.y);
    d2 += cos(vave4*uv.x)*cos(vave4*uv.y);
    d2 += cos(vave5*uv.x)*cos(vave5*uv.y);
    d2 /= 5.0;
    d2 = abs(d2);

    if(d > range1 && d < range2){
      gl_FragColor = vec4(rgb,1.0);
      if(d >= range1+.02 && d <= range2-.02){
        if(d2<.1){
          gl_FragColor = vec4(rgb2,1.0);
        }
      }
      if(d > range1+.01 && d < range1+.02){
        // gl_FragColor = vec4(rgb,1.0);
        gl_FragColor = vec4(rgb2,1.0);
        //gl_FragColor = vec4(rgb2,1.0);
       }
    } else {
      discard;
    }
  }
`
function hexToRgb(hex) {
  hex = hex.replace('#', '');

  var bigint = parseInt(hex, 16);

  var r = (bigint >> 16) & 255;
  var g = (bigint >> 8) & 255;
  var b = bigint & 255;

  return [r / 255, g / 255, b / 255];
}
let points = [];
let _RADIUS_ = 400

let mycanvas;
let bgColor = 'black'
let windowWidthOff = 0;
let windowHeightOff = 0;
let windowWidthOff2 = 0;
let windowHeightOff2 = 0;
let niceColorPalettes = [
  ['#000814', '001d3d', '#003566', '#ffc300', '#ffd60a'],//bumblebee
  ['#e0218a', '#FFB2E3', '#FDD0E8', '#FFFFFF', '#0F110C'],//dreamhouse
  ['#5603AD', '#CCF5AC', '#79BEEE', '#F472AE', '#F3D9FF'],//daydream
  ['#04E762', '#FBF5F3', '#DC0073', '#008BF8', '#0F0E0E'],//earth + sky
  ['#Ff595e', '#ffca3a', '#8ac926', '#1982c4', '#6a4c93'],//unicorn
  ['#D8f3dc', '#b7e4c7', '#95d5b2', '#74c69d', '#52b788'],//cucumber
  ['#E6CCB2', '#DDB892', '#B08968', '#7F5539', '#9C6644'],//sand
  ['#2d00f7', '#8900f2', '#b100e8', '#e500a4', '#f20089'],//berry blast
]
const _COLORS_ = [
  ["Bumblebee", 0],
  ["Dreamhouse", 1],
  ["Day Dream", 2],
  ["Earth x Sky", 3],
  ["Unicorn", 4],
  ["Cucumber", 5],
  ["Sand", 6],
  ["Berry Blast", 7]
];
const random_choice_color = R.random_choice(_COLORS_);

const _DIRECTION_ = [
  ["Horizontal", 0],
  ["Vertical", 1],
  ["Both", 2]
];
const random_choice_direction = R.random_choice(_DIRECTION_);

const _SPEED_ = [
  ["Low", 0],
  ["High", 1],
];
const random_choice_speed = R.random_choice(_SPEED_);

const _PALETTE_MIX_ = ["A", "B", "C", "D", "E"];
const random_choice_palette_mix = R.random_choice(_PALETTE_MIX_);

function shuffleColors(array) {
  var c1 = array[0];
  var c2 = array[1];
  var c3 = array[2];
  var c4 = array[3];
  var c5 = array[4];
  var _array = [c1, c2, c3, c4, c5]
  if (random_choice_palette_mix === "A") {
    _array = [c2, c3, c4, c5, c1]
  } else if (random_choice_palette_mix === "B") {
    _array = [c3, c4, c5, c1, c2]
  } else if (random_choice_palette_mix === "C") {
    _array = [c4, c5, c1, c2, c3]
  } else if (random_choice_palette_mix === "D") {
    _array = [c5, c1, c2, c3, c4]
  }
  return _array;
}
function setup() {
  windowWidth2 = windowWidth / 2;
  windowHeight2 = windowHeight / 2;
  windowWidthOff = windowWidth * .04;
  windowHeightOff = windowHeight * .04;
  windowWidthOff2 = windowWidthOff / 2;
  windowHeightOff2 = windowHeightOff / 2;
  mycanvas = createCanvas(windowWidth, windowHeight, WEBGL);

  createMesh();

  console.log(random_choice_color[0])
  console.log(random_choice_direction[0])
  console.log(random_choice_speed[0])
  console.log(random_choice_palette_mix);

  colorIndex = random_choice_color[1]//R.random_int(0, niceColorPalettes.length - 1);
  wave1x = (R.random_num(50, 200));
  wave1y = (R.random_num(50, 200));
  wave2x = (R.random_num(1, 100));
  wave2y = (R.random_num(1, 100));
  wave3x = (R.random_num(1, 50));
  wave3y = (R.random_num(1, 50));
  wave4x = (R.random_num(1, 60));
  wave4y = (R.random_num(1, 60));
  wave5x = (R.random_num(10, 100));
  wave5y = (R.random_num(10, 100));

  vave1 = (R.random_num(windowWidth2, windowWidth2 + windowWidth2 / 2));
  vave2 = (R.random_num(2, 40));
  vave3 = (R.random_num(2, 50));
  vave4 = (R.random_num(2, 60));
  vave5 = (R.random_num(2, 10));

  water1x = (R.random_num(1, 10));
  water2x = (R.random_num(1, 20));
  water3x = (R.random_num(1, 30));
  water4x = (R.random_num(1, 40));

  water1y = (R.random_num(1, 10));
  water2y = (R.random_num(1, 20));
  water3y = (R.random_num(1, 30));
  water4y = (R.random_num(1, 40));

  if (random_choice_speed[0] === 'Low') {
    water5x = (R.random_num(10, 100));
    water5y = (R.random_num(10, 100));
  }

  if (random_choice_speed[0] === 'High') {
    water5x = (R.random_num(400, 800));
    water5y = (R.random_num(400, 800));
  }
  console.log(water5x, water5y)
  myShader = createShader(vs, fs);
  _palette = shuffleColors(niceColorPalettes[colorIndex]);
  palette = _palette.map((clr) => (hexToRgb(clr)));
  noStroke();
  // renderArt()

}
const HSBToRGB = (h, s, b) => {
  const k = (n) => (n + h / 60) % 6;
  const f = (n) => b * (1 - s * Math.max(0, Math.min(k(n), 4 - k(n), 1)));
  return [f(5), f(3), f(1)];
};

const ranges = [[0, .2], [.2, .4], [.4, .6], [.6, 8], [.8, 1]];
const layers = 5
function renderArt() {
  background(0);
  //stroke(_palette[1])
  timer += timerInc;
  if (timer > 2 || timer < 0) {
    timerInc *= -1;
  }

  for (let i = 0; i < layers; i++) {
    push();
    shader(myShader);
    myShader.setUniform('timer', 1);
    myShader.setUniform('timerfrag', timer);

    myShader.setUniform('wave1x', wave1x);
    myShader.setUniform('wave1y', wave1y);
    myShader.setUniform('wave2x', wave2x);
    myShader.setUniform('wave2y', wave2y);
    myShader.setUniform('wave3x', wave3x);
    myShader.setUniform('wave3y', wave3y);
    myShader.setUniform('wave4x', wave4x);
    myShader.setUniform('wave4y', wave4y);
    myShader.setUniform('wave5x', wave5x);
    myShader.setUniform('wave5y', wave5y);

    myShader.setUniform('vave1', vave1);
    myShader.setUniform('vave2', vave2);
    myShader.setUniform('vave3', vave3);
    myShader.setUniform('vave4', vave4);
    myShader.setUniform('vave5', vave5);

    myShader.setUniform('water1x', water1x);
    myShader.setUniform('water2x', water2x);
    myShader.setUniform('water3x', water3x);
    myShader.setUniform('water4x', water4x);
    myShader.setUniform('water5x', water5x);

    myShader.setUniform('water1y', water1y);
    myShader.setUniform('water2y', water2y);
    myShader.setUniform('water3y', water3y);
    myShader.setUniform('water4y', water4y);
    myShader.setUniform('water5y', water5y);

    myShader.setUniform('direction', random_choice_direction[1]);

    myShader.setUniform('rgb', palette[4 - i]);
    myShader.setUniform('rgb2', palette[i]);

    myShader.setUniform('range1', ranges[i][0]);
    myShader.setUniform('range2', ranges[i][1]);

    scale(3)

    translate(-windowWidth2, -windowHeight2, i * -2);
    model(myModels[0].model)
    pop();
  }
  push();
  ambientLight(_palette[0])
  translate(-windowWidth2, 0, 0)
  plane(windowWidthOff, windowHeight)
  pop();

  push();
  ambientLight(_palette[0])
  translate(windowWidth2, 0, 0)
  plane(windowWidthOff, windowHeight)
  pop();

  push();
  ambientLight(_palette[0])
  translate(0, -windowHeight2, 0)
  plane(windowWidth, windowHeightOff)
  pop();

  push();
  ambientLight(_palette[0])
  translate(0, windowHeight2, 0)
  plane(windowWidth, windowHeightOff)
  pop();
}
function draw() {
  renderArt()

}
function keyTyped() {
  if (key === 's') {
    // photo.save('photo', 'png');
    saveCanvas(mycanvas, 'myCanvas', 'jpg');

  }
}
