//"use strict";
let N = 20;
let Nrand = 100;
let R;
let dx=0.0,dy=0.0,dz=0.0;
let dxc=0.0,dyc=0.0,dzc=0.0;
let dxp=0.0,dyp=0.0,dzp=0.0;
let xc=0,yc=0,zc=1;
let TWO_PI=6.28318530718;

let pals = [];
pals.push([[359, 31, 56], [353, 19, 97], [6,20,96], [22, 21, 92], [20, 16, 98], [28, 21, 99], [6,20,96], [347,13,96]]);
pals.push([[208,49,38], [205,41,59], [192,29,45], [190,14,64], [220, 9, 78], [12, 4, 45], [167,16,81], [180,7,100]]);
pals.push([[222,86,22], [208,88,29], [203,61,57], [215, 49, 74], [211,68, 93], [236,100,24], [195,85,45]]);
pals.push([[4,100,34],[1,96,84],[26,92,94],[34,58,89],[48,100,99],[21,100,84],[8,100,17]]);
pals.push([[43,35,28],[46,39,42],[41,27,90],[39,46,49],[39,83,90],[46,6,96],[46,15,97]]);
pals.push([[209, 92, 15], [197, 98, 24], [195, 79, 37], [190, 42, 64], [189, 62, 90]]);
pals.push([[331,21,31], [265,23,40], [335,26,76], [163,32,22], [210, 24, 29], [180,31, 97], [49,30,63], [180,23,90], [170,13,48]]);
pals.push([[26, 71, 17],[26, 78, 23],[42, 68, 60], [40, 46, 60], [42, 76, 74], [37, 62, 74]]);
pals.push([[102,41,55], [123,37,63], [94,27,65], [121,30,69], [91, 26, 67], [125,37, 63]]);
pals.push([[115,52,17], [98,51,40],[78,58,54],[91,67,84],[6,54,38]]);
pals.push([[349, 83, 69],[250, 44, 66],[191, 44, 66],[27, 82, 72],[45, 85, 70],[0, 100, 79]])
pals.push([[221, 20, 21],[199, 26, 38],[190, 10, 81],[220, 0, 100],[190, 0, 100],[205, 30, 43],[183, 20, 100],[215, 43, 36],[185, 0, 100],[200, 0, 100]])
let header = `#version 300 es
precision highp float;`;

var src_vert = header+`
in vec2 a;
out vec2 u;
void main() {
  gl_Position = vec4(a,0.,1.);
  u = a/2. +vec2(.5,.5);
}`;
var src_simp = header+`
const int N =20;
const float Nf =20.;
const int Nrand =100;
const float Nrandf =100.;
const float dn =0.1;
const int Nx =512;
const float Nxf =512.;
const float PI =3.1415926;
const int numOctaves =8;

in vec2 u;
out vec4 cout;

uniform vec2 res;
uniform int t; // frame number
uniform highp sampler2D img;
uniform highp sampler2D img00;
uniform float kp[N];
uniform float rand[Nrand];
uniform vec3 dxy;
uniform vec3 rc;

vec2 hash2( in vec2 x ) {
  int ii = int(mod(x.x+res.x*x.y,Nrandf)); //counter into array of random #s
  int i2 = int(mod(x.y-res.y*x.x,Nrandf)); //counter into array of random #s
  return vec2(rand[ii],rand[i2]);
}
float ddot ( in vec2 x, in vec2 y ) { return x.x+y.x + x.y*y.y; }
// returns 3D value noise (in .x)  and its derivatives (in .yz)
vec3 noise( in vec2 p ) {
    vec2 i = floor( p );
    vec2 f = fract( p );

    vec2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du = 30.0*f*f*(f*(f-2.0)+1.0);

    vec2 ga = hash2( i + vec2(0.0,0.0) );
    vec2 gb = hash2( i + vec2(1.0,0.0) );
    vec2 gc = hash2( i + vec2(0.0,1.0) );
    vec2 gd = hash2( i + vec2(1.0,1.0) );

    float va = ddot( ga, f - vec2(0.0,0.0) );
    float vb = ddot( gb, f - vec2(1.0,0.0) );
    float vc = ddot( gc, f - vec2(0.0,1.0) );
    float vd = ddot( gd, f - vec2(1.0,1.0) );

    return vec3( va + u.x*(vb-va) + u.y*(vc-va) + u.x*u.y*(va-vb-vc+vd),   // value
                 ga + u.x*(gb-ga) + u.y*(gc-ga) + u.x*u.y*(ga-gb-gc+gd) +  // derivatives
                 du * (u.yx*(va-vb-vc+vd) + vec2(vb,vc) - va));
}

vec3 fbm( in vec2 x, in float H ) {
    float G = exp(-2.*H);float f = 1.0;float a = 1.0;vec3 t = vec3(0.);
    for( int i=0; i<numOctaves; i++ )
    { t += a*noise(f*x);f *= 2.0;a *= G; }
    return t;
}

vec4 laplacian(in sampler2D img, in vec2 uv, in float dx) {
  vec2 dt = 1./res;
  vec4 rg = texture(img, uv + vec2(-1., -1.)*dt)*(0.05+dx);
  rg += texture(img, uv + vec2(0., -1.)*dt)*(0.2-dx);
  rg += texture(img, uv + vec2(1., -1.)*dt)*(0.05+dx);
  rg += texture(img, uv + vec2(-1., 0.)*dt)*(0.2-dx);
  rg -= texture(img, uv + vec2(0., 0.)*dt);
  rg += texture(img, uv + vec2(1., 0.)*dt)*(0.2-dx);
  rg += texture(img, uv + vec2(-1., 1.)*dt)*(0.05+dx);
  rg += texture(img, uv + vec2(0., 1.)*dt)*(0.2-dx);
  rg += texture(img, uv + vec2(1., 1.)*dt)*(0.05+dx);
  return rg;
}

void main(void) //( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 dt = rc.z/res;
    vec2 uv = (u+dxy.xy-vec2(0.5))*(1.+dxy.z)+vec2(0.5);
    vec2 uc = -rc.xy + u*rc.z; // global coords
    vec3 ff = (0.4+0.6*kp[9])*fbm(uc+fbm(0.8*uc,0.7).yz,0.7);
    vec3 f2 = (0.4+0.6*kp[10])*fbm(-uc+fbm(-0.8*uc,0.7).yz,0.7);
    vec4 cc;
vec4 lp,lp2,cv,cu,cv2,cu2;
float aa,bb;
   if ((uv.x>1. || uv.x<0. || uv.y>1. || uv.y<0.)) {
  cc = texture(img00,uc);
  aa = cc.x/256. + cc.y;
  bb = cc.z/256. + cc.w;
  lp = laplacian(img00,uc,(kp[0]*2.-1.)*f2.x*(1.-aa));
  lp2 = laplacian(img00,uc,(kp[1]*2.-1.)*ff.x*bb);
  cv= texture(img00, uc + vec2(0., 1.)*dt);
  cu= texture(img00, uc + vec2(1., 0.)*dt);
  cv2= texture(img00, uc + vec2(0., -1.)*dt);
  cu2= texture(img00, uc + vec2(-1., 0.)*dt);

} else {
  uc=uv;
  cc = texture(img,uc);
  aa = cc.x/256. + cc.y;
  bb = cc.z/256. + cc.w;
  lp = laplacian(img,uc,(kp[0]*2.-1.)*f2.x*(1.-aa));
  lp2 = laplacian(img,uc,(kp[1]*2.-1.)*ff.x*bb);
  cv= texture(img, uc + vec2(0., 1.)*dt);
  cu= texture(img, uc + vec2(1., 0.)*dt);
  cv2= texture(img, uc + vec2(0., -1.)*dt);
  cu2= texture(img, uc + vec2(-1., 0.)*dt);
}

float da = 1.2*(1.-kp[15])*(1.-bb)*(lp.x+256.*lp.y)/256. + 3.*( -aa*bb*bb + 0.015*(1.+kp[17])*(1.-aa))*ff.x*ff.x ;
float db = 1.2*(1.-kp[16])*(1.+kp[7])*(0.02+ff.x*ff.x)*aa*0.5*(lp2.z+256.*lp2.w)/256. + 3.*( aa*bb*bb - 0.04*(1.+1.*kp[6])*bb)*ff.x*ff.x;
float dda=sin(3.*(1.+kp[2]*(ff.x-1.))*aa*1.57)*kp[15]*0.18*((cu.x/256.+cu.y-cu2.x/256.-cu2.y)*ff.y + (cv.x/256.+cv.y-cv2.x/256.-cv2.y)*ff.z);
float ddb=sin(3.*(1.+kp[3]*(f2.x-1.))*bb*1.57)*kp[16]*0.18*((cu.z/256.+cu.w-cu2.z/256.-cu2.w)*f2.y + (cv.z/256.+cv.w-cv2.z/256.-cv2.w)*f2.z);

uv += 2.*f2.yz;
float uv2 = .003+uv.x*uv.x+uv.y*uv.y;
uv2 = (cu.x/256.+cu.y-cu2.x/256.-cu2.y)*uv.y/uv2 - (cv.x/256.+cv.y-cv2.x/256.-cv2.y)*uv.x/uv2;
dda += kp[12]*0.04*uv2;
ddb += kp[13]*0.04*uv2;

da += dda*(1.-dda);
db += ddb*(1.-ddb);
da*=46000.;
db*=46000.;

da+=aa*256.*256.;
db+=bb*256.*256.;

float yn = floor(da/256.);
float xn = (da-yn*256.);
float wn = floor(db/256.);
float zn = (db-wn*256.);

cout = vec4(xn,yn,zn,wn)/256.;
}`;

var src_colp = header+`
const int N =20;
const float Nf =20.;
const int Nrand =100;
const float Nrandf =100.;
const float dn =0.1;
const int Nx =512;
const float Nxf =512.;
const float PI =3.1415926;
const int numOctaves =8;

in vec2 u;
out vec4 cc;

uniform vec2 res;
uniform vec2 L;
uniform int t; // frame number
uniform highp sampler2D img;
uniform highp sampler2D img2;
uniform sampler2D pal; // palette
uniform float rand[Nrand];
uniform vec3 dxy;
uniform vec3 rc;

vec2 hash2( in vec2 x ) {
  int ii = int(mod(x.x+res.x*x.y,Nrandf));
  int i2 = int(mod(x.y-res.y*x.x,Nrandf));
  return vec2(rand[ii],rand[i2]);
}
float ddot ( in vec2 x, in vec2 y ) { return x.x+y.x + x.y*y.y; }
// returns 3D value noise (in .x)  and its derivatives (in .yz)
vec3 noise( in vec2 p ) {
    vec2 i = floor( p );
    vec2 f = fract( p );

    vec2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du = 30.0*f*f*(f*(f-2.0)+1.0);

    vec2 ga = hash2( i + vec2(0.0,0.0) );
    vec2 gb = hash2( i + vec2(1.0,0.0) );
    vec2 gc = hash2( i + vec2(0.0,1.0) );
    vec2 gd = hash2( i + vec2(1.0,1.0) );

    float va = ddot( ga, f - vec2(0.0,0.0) );
    float vb = ddot( gb, f - vec2(1.0,0.0) );
    float vc = ddot( gc, f - vec2(0.0,1.0) );
    float vd = ddot( gd, f - vec2(1.0,1.0) );

    return vec3( va + u.x*(vb-va) + u.y*(vc-va) + u.x*u.y*(va-vb-vc+vd),   // value
                 ga + u.x*(gb-ga) + u.y*(gc-ga) + u.x*u.y*(ga-gb-gc+gd) +  // derivatives
                 du * (u.yx*(va-vb-vc+vd) + vec2(vb,vc) - va));
}
vec3 fbm( in vec2 x, in float H ) {
    float G = exp(-2.*H);float f = 1.0;float a = 1.0;vec3 t = vec3(0.);
    for( int i=0; i<numOctaves; i++ )
    { t += a*noise(f*x);f *= 2.0;a *= G; }
    return t;
}
vec4 laplacian(in sampler2D img, in vec2 uv, in float dx) {
  vec2 dt = 1./res;
  vec4 rg = texture(img, uv + vec2(-1., -1.)*dt)*(0.05+dx);
  rg += texture(img, uv + vec2(0., -1.)*dt)*(0.2-dx);
  rg += texture(img, uv + vec2(1., -1.)*dt)*(0.05+dx);
  rg += texture(img, uv + vec2(-1., 0.)*dt)*(0.2-dx);
  rg -= texture(img, uv + vec2(0., 0.)*dt);
  rg += texture(img, uv + vec2(1., 0.)*dt)*(0.2-dx);
  rg += texture(img, uv + vec2(-1., 1.)*dt)*(0.05+dx);
  rg += texture(img, uv + vec2(0., 1.)*dt)*(0.2-dx);
  rg += texture(img, uv + vec2(1., 1.)*dt)*(0.05+dx);
  return rg;
}
// from http://www.java-gaming.org/index.php?topic=35123.0
vec4 cubic(float v){
    vec4 n = vec4(1.0, 2.0, 3.0, 4.0) - v;
    vec4 s = n*n*n;
    float x = s.x;
    float y = s.y - 4.0 * s.x;
    float z = s.z - 4.0 * s.y + 6.0 * s.x;
    float w = 6.0 - x - y - z;
    return vec4(x, y, z, w)*(1./6.);
}
vec4 textureBicubic(in sampler2D img, in vec2 uv){
    vec2 dt = 1./res;
    uv = uv/dt - 0.5;
    vec2 fxy = fract(uv);
    uv -= fxy;

    vec4 xc = cubic(fxy.x);
    vec4 yc = cubic(fxy.y);

    vec4 c = uv.xxyy + vec2 (-0.5, +1.5).xyxy;

    vec4 s = vec4(xc.xz + xc.yw, yc.xz + yc.yw);
    vec4 offset = c + vec4 (xc.yw, yc.yw) / s;

    offset *= dt.xxyy;

    vec4 sample0 = vec4(texture(img, offset.xz));
    vec4 sample1 = vec4(texture(img, offset.yz));
    vec4 sample2 = vec4(texture(img, offset.xw));
    vec4 sample3 = vec4(texture(img, offset.yw));

    float sx = s.x / (s.x + s.y);
    float sy = s.z / (s.z + s.w);

    return mix(mix(sample3, sample2, sx), mix(sample1, sample0, sx), sy);
}
void main(void)
{
vec2 uv = (u+dxy.xy)*(1.+dxy.z); //vTexCoord.xy;
vec2 uc = -rc.xy + u*rc.z;
if (L.x>L.y) {
  uv.y = 0.5 + (L.y/L.x)*(uv.y-0.5);
  uc.y = 0.5 + (L.y/L.x)*(uc.y-0.5);
} else {
  uv.x = 0.5 + (L.x/L.y)*(uv.x-0.5);
  uc.x = 0.5 + (L.x/L.y)*(uc.x-0.5);
}

    vec3 ff = .5*fbm(uc+fbm(0.8*uc,0.7).yz,0.7);
    vec3 f2 = fbm(-uc+fbm(-0.8*uc,0.7).yz,0.7);

   cc = textureBicubic(img,uv);
   vec4 cco = textureBicubic(img2,uv);

    float aa = (cc.x+256.*cc.y)/256.;
    float bb = (cc.z+256.*cc.w)/256.;
float aao = (cco.x+256.*cco.y)/256.;
float bbo = (cco.z+256.*cco.w)/256.;

vec4 lpo = laplacian(img2,uv,3.*0.3*ff.x*aao);
vec4 lp = laplacian(img,uv,3.*0.3*ff.x*aa);

aao=4.*0.03*(lp[0]+lp[1]*256.-lpo[0]-lpo[1]*256.);
bbo=4.*0.03*(lp[2]+lp[3]*256.-lpo[2]-lpo[3]*256.);

vec4 cc_hsl = texture(pal,vec2(clamp(2.*bb*aa+0.4*(aa)*ff.x+0.4*(bb)*f2.x,0.,1.),clamp(ff*bb,0.,1.)));
vec4 cco_hsl = texture(pal,vec2(clamp(2.*bbo*aao+0.4*(aao)*ff.x+0.4*(bbo)*f2.x,0.,1.),clamp(ff*bbo,0.,1.)));
cc_hsl -= 0.5*(cc_hsl-cco_hsl);

cc_hsl.x += 0.3*ff.x*(1.-f2.x) + 0.01*f2.x*bb + rc.x*rc.y;
cc_hsl.x = mod(cc_hsl.x,1.);
cc_hsl.z *= 0.2+(3.*bb+6.*aa*bb);
cc_hsl.y *= (1.1-ff.x*bb)*(1.-f2.x*f2.x);
vec3 rgb = clamp( abs(mod(cc_hsl.x*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0, 0.0, 1.0 );
rgb = cc_hsl.z + cc_hsl.y * (rgb-0.5)*(1.0-abs(2.0*cc_hsl.z-1.0));
rgb *= .75+.32*rgb*(3.-2.*rgb);
cc = vec4(pow(rgb[0],0.9), pow(rgb[1],0.9), pow(rgb[2],0.85), 1.);
vec4 ccoo = vec4(.4+.3*aao-f2.x,.1*(aao+bbo),1.-bbo,1.);
cc = mix(cc,ccoo,clamp(2.*ff.x*bbo*aao,-0.5,1.));
cc=clamp(cc,0.,1.);
}`;
let useA,prngA,prngB;
class Random {
  constructor() {
    useA = false;
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
    prngA = new sfc32(tokenData.hash.substr(2, 32));
    // seed prngB with second half of tokenData.hash
    prngB = new sfc32(tokenData.hash.substr(34, 32));
    for (let i = 0; i < 1e6; i += 2) {
       prngA(); prngB();
    }
  }
  random_dec() {
    useA = !useA;
    return useA ? prngA() : prngB();
  }
}
function rnd() { return R.random_dec() }

function vecscl(v,k) { let w=[]; for (let i=0; i<v.length; i++) { w[i] = v[i]*k; } return w }
function clamp(x) { return Math.max(0,Math.min(1,x)); }
function dot2(x,y) { return x[0]*y[0]+x[1]*y[1]; }

R = new Random();

let C,D,body,gl,Shader;
document.body.style.backgroundColor = "#030303";
console.log("Calian by Eric De Giuli");
C=({body}=D=document).createElement('canvas');
body.appendChild(C);
gl=C.getContext('webgl2');

Shader=(typ,src)=>{
  const s =gl.createShader(typ);
  gl.shaderSource(s,src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
                console.error(`Error compiling ${typ === gl.VERTEX_SHADER ? "vertex" : "fragment"} shader "${src}":`);
                console.log(gl.getShaderInfoLog(s));
            }
  return s;
}
var GET = {};
var query = window.location.search.substring(1).split("&");
for (var i = 0, max = query.length; i < max; i++)
{
    if (query[i] === "")
        continue;
    var param = query[i].split("=");
    GET[decodeURIComponent(param[0])] = decodeURIComponent(param[1] || "");
}
let simp,colp,vs,fs;
let Lx,Ly,Nx,Ny;
Nx = 512;if (GET.N) { Nx=GET.N; }
Ny=Nx;
const head = /\bHeadlessChrome\//.test(navigator.userAgent);

let PI = 3.1415926;

let pal,pj,inv;
let palp = [3,5,3,4,1,2,4,4,1,3,2,2,4,2,3,3];
palp = vecscl(palp,1/46);
let cumpal = []; cumpal[0]=0;
for (let i=1; i<palp.length; i++) { cumpal[i]=cumpal[i-1]+palp[i-1]; }
let st = 1;
pj=1;
let palr = rnd();
while (st<palp.length && cumpal[st]<palr) { st++; } st--;
let pj2 = Math.floor(11*rnd());
(tokenData.tokenId%1000000==0)&&(st=1);
inv=0;
switch(st) {
  case 0: pj=6;pj2=7; break; // embers in half light
  case 1: pj=11;pj2=7; break; // liquid circuit
  case 2: pj=1;pj2=5; break; // alpenglow
  case 3: pj=1;pj2=0; break; // zabriskie point
  case 4: pj=3;pj2=9; break; // aurum
  case 5: pj=6;pj2=0; break; // tunguska
  case 6: pj=5;pj2=7; break; // nocturne
  case 7: pj=11;pj2=5; break; // kind of blue
  case 8: pj=11;pj2=4; break; // inferno
  case 9: pj=11;pj2=0; break; // constellation
  case 10: pj=0;pj2=0;inv=1; break; // white heat
  case 11: pj=3;pj2=3;inv=1; break; // calanque
  case 12: pj=2;pj2=0; break; // bouquet
  case 13: pj=2;pj2=10; break; // spectral
  case 14: pj=10;pj2=8; break; // the forest path to the spring
  case 15: pj=10;pj2=4; break; // abalone
}
pal = new Uint8Array(10*4*2);
for (let k=0; k<11; k++) { // which colour in palette
  for (let k2=0; k2<2; k2++) { // which palette
  let pp = (k2==0) ? pj : pj2;
  let kk = Math.min(k,pals[pp].length-1);
  pal[3*k+3*10*k2]   = pals[pp][kk][0];
  pal[3*k+3*10*k2+1] = pals[pp][kk][1];
  pal[3*k+3*10*k2+2] = pals[pp][kk][2];
  if (inv) { pal[3*k+3*10*k2] = (pal[3*k+3*10*k2]+180)%360; } //invert colour
}
}

let kp,km,kv,kw,kl,rand;
rand = []; for (let i=0; i<Nrand; i++) { rand[i]=rnd(); }
let k0=1;
let kl0=0.001;
kp = new Float32Array(N);
km = new Float32Array(N);
kl = new Float32Array(N);

switch(st) {
  case 0: kp = [0.66, 0.95, 0.94, 0.037, 0.89, 0.26, 0.90, 0.94, 0.65, 0.76, 0.54, 0.11, 0.50, 0.66, 0.96, 0.74, 0.91, 0.33, 0.15, 0.85]; break;
  case 1: kp = [0.97, 0.01, 0.89, 0.08, 0.78, 0.98, 0.16, 0.80, 0.53, 0.91, 0.40, 0.54, 0.84, 0.44, 0.14, 0.75, 0.45, 0.33, 0.47, 0.95]; break;
  case 2: kp = [0.72, 0.85, 0.51, 0.08, 0.98, 0.29, 0.91, 0.19, 0.69, 0.24, 0.99, 0.32, 0.84, 0.03, 0.97, 0.14, 0.09, 0.04, 0.08, 0.26]; break;
  case 3: kp = [0.14, 0.95, 0.24, 0.09, 0.05, 0.18, 0.96, 0.04, 0.47, 0.18, 0.13, 0.38, 0.21, 0.85, 0.66, 0.05, 0.15, 0.23, 0.25, 0.48]; break;
  case 4: kp = [0.58, 0.02, 0.03, 0.84, 0.43, 0.40, 0.95, 0.76, 0.15, 0.55, 0.04, 0.49, 0.49, 0.55, 0.52, 0.07, 0.22, 0.16, 0.31, 0.37]; break;
  case 5: kp = [0.21, 0.10, 0.21, 0.13, 0.07, 0.42, 0.26, 0.77, 0.28, 0.67, 0.79, 0.10, 0.28, 0.20, 0.04, 0.21, 0.35, 0.125, 0.75, 0.87]; break;
  case 6: kp = [0.40, 0.28, 0.88, 0.36, 0.92, 0.96, 0.79, 0.24, 0.99, 0.73, 0.68, 0.03, 0.09, 0.52, 0.11, 0.29, 0.95, 0.01, 0.01, 0.62]; break;
  case 7: kp = [0.10, 0.27, 0.31, 0.05, 0.40, 0.24, 0.67, 0.00, 0.02, 0.92, 0.75, 0.11, 0.40, 0.55, 0.97, 0.45, 0.12, 0.15, 0.54, 0.56]; break;
  case 8: kp = [0.17, 0.81, 0.64, 0.19, 0.52, 0.27, 0.59, 0.11, 0.65, 0.87, 0.36, 0.17, 0.66, 0.10, 0.95, 0.08, 0.50, 0.43, 0.92, 0.13]; break;
  case 9: kp = [0.59, 0.56, 0.03, 0.14, 0.58, 0.05, 0.80, 0.00, 0.09, 0.75, 0.80, 0.55, 0.07, 0.27, 0.46, 0.08, 0.35, 0.01, 0.17, 0.63]; break;
  case 10: kp = [0.021, 0.68, 0.20, 0.04, 0.46, 0.40, 0.30, 0.76, 0.19, 0.20, 0.78, 0.50, 0.10, 0.58, 0.61, 0.13, 0.25, 0.39, 0.63, 0.38]; break;
  case 11: kp = [0.11, 0.18, 0.02, 0.15, 0.49, 0.90, 0.73, 0.77, 0.69, 0.93, 0.95, 0.76, 0.78, 0.32, 0.13, 0.70, 0.07, 0.04, 0.30, 0.76]; break;
  case 12: kp = [0.15, 0.27, 0.17, 0.11, 0.61, 0.44, 0.65, 0.21, 0.82, 0.79, 0.40, 0.33, 0.43, 0.22, 0.02, 0.07, 0.50, 0.13, 0.95, 0.34]; break;
  case 13: kp = [0.89, 0.46, 0.48, 0.30, 0.38, 0.18, 0.13, 0.68, 0.20, 0.87, 0.92, 0.56, 0.06, 0.25, 0.32, 0.10, 0.05, 0.11, 0.31, 0.55]; break;
  case 14: kp = [0.90, 0.025, 0.064, 0.439, 0.208, 0.154, 0.261, 0.085, 0.268, 0.917, 0.780, 0.709, 0.087, 0.068, 0.684, 0.057, 0.480, 0.282, 0.174, 0.819]; break;
  case 15: kp = [0.81, 0.79, 0.38, 0.80, 0.19, 0.22, 0.39, 0.047, 0.82, 0.98, 0.90, 0.28, 0.12, 0.24, 0.12, 0.69, 0.62, 0.20, 0.99, 0.71]; break;
}

for (let i=0; i<N; i++) { km[i]=k0*rnd(); }
for (let i=0; i<N; i++) { kl[i]=kl0*rnd(); }

if (km[0]<0.15*k0 && st!=10 && st!=3 && st!=1) { kp[15]=0.69;kp[16]=1.34; }

let nx = 2+Math.floor(8*rnd());
let ny = 2+Math.floor(8*rnd());
let rr = rnd();
let n4 = Math.floor(Math.exp(4*rnd()));
let rbg = Math.floor(15*rnd());
// initial conditions
const tex0 = new Uint8Array(Nx*Ny*4);
let th;
for (let x = 0; x < Nx; x++) {
  for (let y = 0; y < Ny; y++) {
      let i = x+Nx*y;
      let r2 = (x-Nx/2)**2+(y-Ny/2)**2;
      r2/=(Nx*Nx+Ny*Ny)/4;
        switch(rbg) {
        case 0: r2 = Math.sin(x/nx)*Math.sin(y/ny)*Math.sin(25*r2)>.1+.5*rr; break;
        case 1: r2 = Math.sin(x/Nx*nx*PI)*Math.sin(y/Ny*ny*PI)*Math.sin(25*r2)>0.5*rr; break;
        case 2: r2 = Math.sin(y*x/Nx*nx*PI)*Math.sin(y/Ny*ny*PI)*Math.sin(25*r2)>0.5*rr; break;
        case 3: r2 = Math.sin(y*x/Nx*nx*PI)*Math.sin(y/Ny*ny*PI)*Math.sin(2*(x-Nx/2)/(y-Ny/2)+1*(y-Ny/2)/(x-Nx/2))>0.5*rr; break;
  case 4: r2 = Math.sin(Math.sin(x/Nx*n4)*y/Ny*nx*PI)*Math.sin(y/Ny*ny*PI)*Math.sin(2*(x-Nx/2)/(y-Ny/2)+1*(y-Ny/2)/(x-Nx/2))>0.5*rr; break;
  case 5: r2 = Math.sin(Math.sin(x/Nx*n4*PI)*y/Ny*(1-y/Ny)*ny*PI)*Math.sin(x/Nx*nx*PI)>0.6*rr; break;
  case 6: r2 = Math.sin(Math.sin(y/Ny*n4*PI)*x/Nx*(1-x/Nx)*nx*PI)*Math.sin(y/Ny*ny*PI)>0.6*rr; break;
  case 7: r2 = Math.sin(30*x/Nx*nx*PI)*Math.sin(x/Nx*nx*PI)>0.6*rr; break;
  case 8: r2 = Math.sin(30*x/Nx*nx*PI)*Math.sin(y/Ny*ny*PI)>0.6*rr; break;
  case 9: r2 *= .7*(Math.sin(20*(x/Nx-0.5)*nx)+Math.sin(2*(y/Ny-0.5))); break;
  case 10: r2 = r2*Math.sin(20*r2*nx)>.3*rr; break;
  case 11: r2 = Math.sin(r2*nx*Math.tan(n4*x/Nx+9*y/Ny))>.6*rr; break;
  case 12: th = Math.atan2(y-Ny/2,x-Nx/2); r2*=1+0.2*Math.cos(nx*th)*(1+0.6*Math.sin(nx/ny+3*nx*th)*(1+0.6*Math.cos(5*nx*th))); r2*=.72; break;
  case 13: th = Math.atan2(y+(.3+.4*km[3])*Ny,x-.5*Nx); r2 = Math.sin(10*nx*(x-y)/Nx*PI)*Math.sin((y+x)/Ny*ny*PI+th*ny*nx)>(.2+km[2]*.8)*rr; break;
  case 14: r2=0.6+.4*rr;
  }
      tex0[4*i]   = Math.floor(rnd()*255*(r2));
      tex0[4*i+1] = Math.floor(rnd()*255*(1-r2) );
      tex0[4*i+2] = Math.floor(rnd()*255*(1-r2) );
      tex0[4*i+3] = Math.floor(rnd()*255*(r2) );
    }
  }

dzc=0;
dzp=dzc;

let loc_a,loc_ac,loc_img,loc_img00,loc_res,loc_t,loc_rand,loc_palc,loc_kp,loc_km,loc_kl,loc_kv,loc_kw,loc_imgc,loc_imgc2,loc_resc,loc_Lc,loc_tc,loc_randc,loc_aavg,loc_bavg,loc_dxy,loc_dxyc,loc_rc,loc_rcc;

function thrower(prog) {
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
      console.log(`Link failed:\n${gl.getProgramInfoLog(prog)}`);
      console.log(`VS LOG:\n${gl.getShaderInfoLog(vs)}`);
      console.log(`FS LOG:\n${gl.getShaderInfoLog(fs)}`);
      throw 'AARG DED';
  }
}

simp = gl.createProgram(); // simulation program
vs = Shader(gl.VERTEX_SHADER, src_vert);
fs = Shader(gl.FRAGMENT_SHADER, src_simp);
gl.attachShader(simp, vs);
gl.attachShader(simp, fs);
gl.linkProgram(simp);
gl.useProgram(simp);
thrower(simp);

function gul(pr,lab) { return gl.getUniformLocation(pr,lab); }

loc_img=gul(simp,'img');
loc_img00=gul(simp,'img00');
loc_res=gul(simp,'res');
loc_t  =gul(simp,'t');
loc_rand =gul(simp,'rand');
loc_kp =gul(simp,'kp');
loc_km =gul(simp,'km');
loc_kl =gul(simp,'kl');
loc_dxy =gul(simp,'dxy');
loc_rc  =gul(simp,'rc');

gl.uniform1i(loc_img,0);
gl.uniform1i(loc_img00,1);
gl.uniform2f(loc_res,Nx,Ny);

loc_a = gl.getAttribLocation(simp, "a");
gl.activeTexture(gl.TEXTURE0);
gl.vertexAttribPointer(loc_a, 2, gl.FLOAT, false, 0, 0);
gl.enableVertexAttribArray(loc_a);

colp = gl.createProgram(); // colour program
vs = Shader(gl.VERTEX_SHADER, src_vert);
fs = Shader(gl.FRAGMENT_SHADER, src_colp);
gl.attachShader(colp, vs);
gl.attachShader(colp, fs);
gl.linkProgram(colp);
gl.useProgram(colp);
thrower(colp);

loc_imgc=gul(colp,'img');
loc_imgc2=gul(colp,'img2');
loc_palc=gul(colp,'pal');
loc_resc=gul(colp,'res');
loc_Lc=gul(colp,'L');
loc_tc  =gul(colp,'t');
loc_randc  =gul(colp,'rand');
loc_dxyc  =gul(colp,'dxy');
loc_rcc  =gul(colp,'rc');

gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1.0, 1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0]),gl.STATIC_DRAW);

gl.uniform1i(loc_imgc,0);
gl.uniform1i(loc_imgc2,2);
gl.uniform2f(loc_resc,Nx,Ny);

loc_ac = gl.getAttribLocation(colp, "a"); //'a');
gl.activeTexture(gl.TEXTURE0);
gl.vertexAttribPointer(loc_ac, 2, gl.FLOAT, false, 0, 0);
gl.enableVertexAttribArray(loc_ac);
let M=1;
var isMobile = window.matchMedia("(hover: none)").matches; // no hovering
function resize_render() {
  let w=innerWidth, h=innerHeight, dpr=devicePixelRatio;
  C.width  = M*w*dpr|0;
  C.height = M*h*dpr|0;
  if (head || f1==1) {
    Lx = Math.min(C.width,C.height); Ly=Lx;
  } else if (f1==2 || isMobile) {
    Lx = C.width; Ly=C.height;
    if (Lx>Ly) { Lx=Math.min(Lx,2.5*Ly); }
    if (Ly>Lx) { Ly=Math.min(Ly,2.5*Lx); }
  } else {
    Lx = Math.min(3*Nx,C.width);
    Ly = Math.min(3*Ny,C.height);
  }
  C.style.width = w+'px';
  C.style.height = h+'px';
  gl.viewport((C.width-Lx)/2,(C.height-Ly)/2,Lx,Ly);
  render();
}

function texset(wrap) {
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
   gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
   gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
}
let tex00,texA,texB,texC,fbA,fbB;
let wrap = gl.REPEAT;

tex00 = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, tex00);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, tex0.subarray(0, Nx*Ny*4));
texset(wrap);

texA = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texA);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, tex0.subarray(0, Nx*Ny*4));
fbA = gl.createFramebuffer();
gl.bindFramebuffer(gl.FRAMEBUFFER, fbA);
gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texA, 0);
texset(wrap);

texB = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texB);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
fbB = gl.createFramebuffer();
gl.bindFramebuffer(gl.FRAMEBUFFER, fbB);
gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texB, 0);
texset(wrap);

texC = gl.createTexture(); //colormap
gl.bindTexture(gl.TEXTURE_2D, texC);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, 10, 2, 0, gl.RGB, gl.UNSIGNED_BYTE, pal);
texset(wrap);
gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAX_LEVEL, 0);

gl.useProgram(colp);
gl.uniform1i(loc_palc, 1); //texture 1

// and assign uniforms
gl.useProgram(simp);
gl.uniform1fv(loc_km,km);
gl.uniform1fv(loc_kl,kl);
gl.uniform1fv(loc_rand,rand);

gl.useProgram(colp);
gl.uniform1fv(loc_randc,rand);

let prevt=performance.now();
let dt = 1000/60;

let running=true;
let periodic=0;
let anim=0;
let flip=0;
let count=0;
let dxycount=0;
let TT = 120;
let om0 = 0.01, A=0.002;
function render() {
  if (running) {
    count++;
    let time=performance.now();
    if (time-prevt>dt) {

    gl.viewport(0,0,Nx,Ny);
    gl.useProgram(simp);
    if (count%TT==0) {
      for (let i=0; i<Nrand; i++) { rand[i]=.7*rnd()+.3*rand[i]; }
      gl.uniform1fv(loc_rand,rand);
    }

    if (dxycount==0) {
      dx=dxc-dxp;
      dy=dyc-dyp;
      dz=dzc-dzp;
      zc *= 1+2*dz;
      xc -= (.5+(2*dx-0.5)*(1+2*dz))*zc;
      yc -= (.5+(2*dy-0.5)*(1+2*dz))*zc;
      kp[0]+= dx/3;
      kp[1]+= dy/3;
      kp[15]*=Math.exp(dx/3);
      kp[16]*=Math.exp(dy/3);
    }
    gl.uniform1fv(loc_kp,kp);

    if (dx!=0 || dy!=0 || dz!=0) {
      dxycount++;
    }
    gl.uniform3fv(loc_dxy,[dx, dy, dz]);
    gl.uniform3fv(loc_rc,[xc, yc, zc]);
    gl.uniform1i(loc_t,time);
    for (let j=0; j<2; j++) {
      flip = !flip;
      gl.bindFramebuffer(gl.FRAMEBUFFER, (flip ? fbB : fbA));
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, (flip ? texA : texB));
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, tex00);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    }
    gl.viewport((C.width-Lx)/2,(C.height-Ly)/2,Lx,Ly);
    gl.useProgram(colp);

    gl.uniform1i(loc_tc,time);
    gl.uniform2f(loc_Lc,Lx,Ly);
    gl.uniform3fv(loc_dxyc,[dx, dy, dz]);
    gl.uniform3fv(loc_rcc,[xc, yc, zc]);
    if (dxycount>=1) {
      dxycount=0;
      dx=0;dy=0;dz=0;
      dxp=dxc;dyp=dyc;dzp=dzc;
    }

    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, (flip ? texB : texA));
    gl.activeTexture(gl.TEXTURE1);
    gl.bindTexture(gl.TEXTURE_2D, texC);    //color map
    gl.activeTexture(gl.TEXTURE2);
    gl.bindTexture(gl.TEXTURE_2D, (flip ? texA : texB));
    if (dz==0) gl.drawArrays(gl.TRIANGLES, 0, 6);
    }
    prevt=time-(time-prevt)%dt;
  }
//  requestAnimationFrame(render.bind());
    if (savescr==1) {
    savescr=2;
    resize_render();
  }
  if (savescr==2) {
    savescr=0;
    var tC = document.createElement("canvas");
    tC.width = Lx; tC.height = Ly;
    var ctx = tC.getContext("2d");
    ctx.setTransform(1,0,0,-1,0,gl.height);
    ctx.drawImage(C,-(C.width-Lx)/2,-(C.height-Ly)/2);
    tC.toBlob((blob) => { saveBlob(blob, `Calian-${tokenData.tokenId}.png`); });
  }
  requestAnimationFrame(render);
}

const saveBlob = (function() {
  const a = document.createElement('a');
  document.body.appendChild(a);
  a.style.display = 'none';
  return function saveData(blob, fileName) {
     const url = window.URL.createObjectURL(blob);
     a.href = url;
     a.download = fileName;
     a.click();
  };
}());

// resize event
let tid=0;
onresize => {
  clearTimeout(tid);
  tid=setTimeout(resize_render,150)
};

let f1=0,savescr=0;
// keyboard event
onkeyup=e=>{
  if (e.key==' ') { // spacebar
    running = !running;
  }
  if ( window !== window.parent ) {
      // iframe
      if (e.keyCode==65) dxc-=0.01; //a = left
      if (e.keyCode==68) dxc+=0.01; //d = right
      if (e.keyCode==87) dyc+=0.01; //w = up
      if (e.keyCode==83) dyc-=0.01; //s = down
  } else {
      // not iframe
      if (e.keyCode==37) dxc-=0.01; //left
      if (e.keyCode==39) dxc+=0.01; //right
      if (e.keyCode==38) dyc+=0.01; //up
      if (e.keyCode==40) dyc-=0.01; //down
  }
  if (e.keyCode==88) dzc-=0.03; //x = in
  if (e.keyCode==90) dzc=Math.min(0,dzc+0.03); //z = out
  if (e.keyCode==70) { f1=(f1+1)%3; resize_render(); } // f
  if (e.keyCode==80) { savescr=1; Lx = Ly = min(C.width,C.height); } //p = print screen
  //   dzc+=e.deltaY/Ly;
  return false;
  //e.stopPropagation(); e.preventDefault();
}

function handler(e) {
    var scroll = (e.deltaY || -1*e.wheelDelta || 10*e.detail);
    var isTouchPad = e.wheelDeltaY ? e.wheelDeltaY === -3 * e.deltaY : e.deltaMode === 0;
    dzc=Math.min(0,dzc+.5*Math.max(-0.03,Math.min(0.03,scroll/Ly*(1+3*isTouchPad))));
    e.stopPropagation();
    e.preventDefault();
    return false;
}
gl.canvas.addEventListener("mousewheel", handler, false);
gl.canvas.addEventListener("DOMMouseScroll", handler, false);

const delta = 6;
let startx;
let starty;
let startdist;
let mousedown=0;

function handler_down(e) {
  if (running) {
    mousedown=1;
    startx = (e.clientX || (e.touches && e.touches[0].clientX));
    starty = (e.clientY || (e.touches && e.touches[0].clientY));
    if (e.touches && e.touches.length === 2) {
      e.preventDefault();
      startx = startx/2 + e.touches[1].clientX / 2;
      starty = starty/2 + e.touches[1].clientY / 2;
      startdist = (e.touches[0].clientX-e.touches[1].clientX)**2+(e.touches[0].clientY-e.touches[1].clientY)**2;
    }
  }
}
gl.canvas.addEventListener("mousedown", handler_down, false);
gl.canvas.addEventListener("touchstart", handler_down, false);
function handler_move(e) {
  if (running && mousedown) {
    const sx = (e.clientX || (e.touches && e.touches[0].clientX));
    const sy = (e.clientY || (e.touches && e.touches[0].clientY));
    e.preventDefault();
    if (e.touches && e.touches.length === 2) {
      e.preventDefault(); // Prevent page scroll
      let scale;
      const deltaDistance = (e.touches[0].clientX-e.touches[1].clientX)**2+(e.touches[0].clientY-e.touches[1].clientY)**2;
      scale = -100*(deltaDistance / startdist-1);
      dzc=Math.min(0,dzc+.5*Math.max(-0.05,Math.min(0.05,scale/Ly)));
    } else {
      dxc-=(sx-startx)/Lx*Math.exp(-0.1*dzc);
      dyc+=(sy-starty)/Ly*Math.exp(-0.1*dzc);
      startx = sx;
      starty = sy;
    }
  }
}gl.canvas.addEventListener("mousemove", handler_move, false);
gl.canvas.addEventListener("touchmove", handler_move, false);
gl.canvas.addEventListener('mouseleave', function (e) {
  mousedown=0;
});
gl.canvas.addEventListener('mouseup', function (e) {
  mousedown=0;
});
gl.canvas.addEventListener('touchend', function (e) {
  mousedown=0;
});
gl.canvas.addEventListener('dblclick', function (e) {
    running = !running;
});
resize_render();
