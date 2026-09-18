let sh, DIM, BFSZ, subVal, cnv, colChc, ogSt = false, pxDens;
let cols = [[[0,0,0],[255,255,255]],
  [[255,255,255],[0,0,0]],
  [[143,201,255],[255,255,255]],
  [[144,82,54],[255,255,255]],
  [[233,189,150],[255,255,255]],
  [[82,134,88],[255,255,255]],
  [[12,68,152],[255,255,255]],
  [[192,65,56],[255,255,255]]];
function iDim(){
  BFSZ = DIM = min(window.innerWidth, window.innerHeight);
  if (DIM > 4000){BFSZ = 4000;}
  pxDens = min(2, displayDensity());
  if (DIM > 2000){pxDens = min(1, displayDensity());}
  subVal = (~~max(6 / pxDens, 6)).toFixed(1);
  pixelDensity(pxDens);
}
let chkLar = () => (DIM > 2400)? noLoop() : loop();
let hPr = [];
for (let j=0; j<32; j++){
    hPr.push(tokenData.hash.slice(2+(j*2), 4+(j*2)));
    }
let hData = hPr.map(x=>{
    return parseInt(x,16);
});
let ks = new Array(12).fill(0);
let amps = new Array(12).fill(0);
function chlGen(){
  let numOfPairs = round(map(hData[0], 0, 255, 5, 12));
  let amp = 0.0;
  let k = 0.0;
  for (let i = 0; i < numOfPairs; i++){
    amp = map(hData[i], 0, 255, -0.8, 0.8);
    k = map(hData[i+1], 0, 255, 1, 13);
    amps[i] = amp;
    ks[i] = k;
  }
}
function setup(){
  iDim();
  var frg = `#ifdef GL_FRAGMENT_PRECISION_HIGH
precision highp float;
#else
precision mediump float;
#endif
#define PI2 1.57079632679489661923
#define SUBSAMP ${subVal}
#define C_LYRS 12
uniform float u_amps[12];uniform float u_ks[12];uniform vec3 u_strCol;uniform vec3 u_bgCol;uniform vec2 u_res;uniform vec2 u_mouse;uniform float u_pxDens; float map(float value){return (value -0.5)*2.0;}float chladni(vec2 st, vec2 n_mouse){float sum = 0.0;float x = map(st.x);float y = map(st.y);float PI2X = PI2*x;float PI2Y = PI2*y;for (int i = 0; i < C_LYRS; i++) {float amp = u_amps[i] + n_mouse.x;float k = u_ks[i] + n_mouse.y;sum += amp * (cos(PI2X * k) * cos(PI2Y * k ));}if (abs(sum) < 0.1) {return 1.0;} else {return 0.0;}} vec3 colAvg(vec2 st, vec2 n_mouse, vec3 stroke, vec3 bg) {float sum = 0.0;for (float xAdd = 0.0; xAdd < SUBSAMP; xAdd += 1.0) {for (float yAdd = 0.0; yAdd < SUBSAMP; yAdd += 1.0) {float x = st.x + (-0.5 + xAdd / SUBSAMP) / u_res.x;float y = st.y + (-0.5 + yAdd / SUBSAMP) / u_res.y;vec2 pos = vec2(x, y);sum += chladni(pos, n_mouse);}}float avg = sum / SUBSAMP / SUBSAMP;return mix(bg, stroke, avg);} void main() {vec2 st = gl_FragCoord.xy/u_res.xy;vec2 n_mouse = u_mouse / u_res;vec3 colAA;colAA = colAvg(st, n_mouse, u_strCol, u_bgCol);gl_FragColor = vec4(colAA, 1.0);}`
  var vt = `attribute vec3 aPosition;void main() {vec4 positionVec4 = vec4(aPosition, 1.0);positionVec4.xy = positionVec4.xy * 2.0 - 1.0;gl_Position = positionVec4;}`
  if (hData[29] < 127 ) {
    colChc = cols[0];
  } else if (hData[29] < 171) {
    colChc = cols[1];
  } else if (hData[29] > 247) {
    colChc = cols[7];
  } else { colChc = cols[(hData[29] % 5)+2]; }
  chlGen();
  shBuf = createGraphics(BFSZ,BFSZ, WEBGL);
  cnv = createCanvas(DIM,DIM, WEBGL);
  sh = shBuf.createShader(vt, frg);
  noStroke();
  noLoop();
  cnv.mouseOver(chkLar);
  cnv.mouseOut(noLoop);
  cnv.mouseClicked(togLp);
  cnv.touchMoved(chkLar);
  cnv.touchEnded(togLp);
}
function draw(){
  shStr = colChc[1].map(x => x / 255);
  shBg = colChc[0].map(i => i / 255);
  if (ogSt){mouseX = mouseY = 0.0;}
  background(colChc[0]);
  shBuf.shader(sh);
  sh.setUniform("u_pxDens", pxDens);
  sh.setUniform("u_ks", ks);
  sh.setUniform("u_amps", amps);
  sh.setUniform("u_strCol", shStr);
  sh.setUniform("u_bgCol", shBg);
  sh.setUniform("u_res", [BFSZ*pxDens, BFSZ*pxDens]);
  sh.setUniform("u_mouse", [map(mouseX, 0, BFSZ*pxDens, 0, (BFSZ/2)*pxDens), map(mouseY, 0, BFSZ*pxDens, BFSZ*pxDens, 0)]);
  shBuf.rect(0,0,BFSZ,BFSZ);
  translate(-DIM/2, -DIM/2);
  texture(shBuf);
  rect(0,0,DIM,DIM);
  noFill();
  strokeWeight(DIM/20);
  stroke(colChc[1]);
  rect(0,0,DIM,DIM);
}
function togLp(){
  ogSt = !ogSt;
  if (ogSt) {
    redraw();
    noLoop();
  } else { chkLar(); }
}