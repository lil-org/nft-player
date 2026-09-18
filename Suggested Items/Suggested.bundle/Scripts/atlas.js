"use strict";
let N = 30;
let Nrand = 100;
let R;
let dx=0.0,dy=0.0,dz=0.0;
let dxc=0.0,dyc=0.0,dzc=0.0;
let dxp=0.0,dyp=0.0,dzp=0.0;
let xc=0,yc=0,zc=1;
let TWO_PI=6.28318530718;
let feat=[];

var GET = {};
var query = window.location.search.substring(1).split("&");
for (var i = 0, max = query.length; i < max; i++)
{
    if (query[i] === "")
        continue;
    var param = query[i].split("=");
    GET[decodeURIComponent(param[0])] = decodeURIComponent(param[1] || "");
}
let pals = [];
pals.push([[359,31,38],[353,19,66],[6,20,65],[22,21,63],[20,16,67],[28,21,67],[6,20,65],[347,13,65]]);
pals.push([[208,49,37],[205,41,57],[192,29,44],[190,14,62],[220,9,76],[12,4,44],[167,16,79],[180,7,98]]);
pals.push([[222,86,28],[208,88,36],[203,61,72],[215,49,94],[211,68,118],[236,100,30],[195,85,57]]);
pals.push([[4,100,29],[1,96,73],[26,92,82],[34,58,77],[48,100,86],[21,100,73],[8,100,14]]);
pals.push([[43,35,24],[46,39,37],[41,27,80],[39,46,43],[39,83,80],[46,6,85],[46,15,86]]);
pals.push([[209,92,20],[197,98,32],[195,79,50],[190,42,87],[189,62,122]]);
pals.push([[331,21,35],[265,23,45],[335,26,86],[163,32,24],[210,24,32],[180,31,110],[49,30,71],[180,23,102],[170,13,54]]);
pals.push([[26,81,10],[26,78,28],[42,68,73],[40,46,73],[42,76,90],[37,62,90]]);
pals.push([[102,41,54],[123,37,61],[94,27,63],[121,30,67],[91,26,65],[125,37,61]]);
pals.push([[115,52,22],[98,51,53],[78,58,72],[91,67,112],[6,54,51]]);
pals.push([[349,83,61],[250,44,58],[191,44,58],[27,82,64],[45,85,62],[0,100,70]]);
pals.push([[221,20,18],[199,26,33],[190,10,70],[220,0,87],[190,0,87],[205,30,37],[183,20,87],[215,43,31],[185,0,87],[200,0,87]]);
pals.push([[0,0,20],[0,0,15],[0,0,10],[210,20,20],[210,20,30],[90,50,40],[120,50,50],[180,50,75],[180,70,90],[210,70,95]]);
pals.push([[140,60,20],[140,60,30],[140,60,40],[140,60,50],[140,60,60],[220,50,70],[200,60,75],[200,60,85],[210,60,50],[220,60,35]]);
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
const int N = 30;
const float Nf =20.;
const int Nrand =100;
const float Nrandf =100.;
const float dn =0.1;
const int Nx =512;
const float Nxf =512.;
const float PI =3.1415926;
const int numOctaves = 9;
in vec2 u;

layout(location = 0) out vec4 cout;
layout(location = 1) out vec4 cout2;
uniform vec2 res;
uniform float t; // frame number
uniform float tr; // relative frame number wrt period \in [0,1]
uniform highp sampler2D img;
uniform highp sampler2D img00;
uniform highp sampler2D img2;
uniform highp sampler2D img02;
uniform float kp[N];
uniform float kl[N];
uniform float rand[Nrand];
uniform vec3 dxy;
uniform vec3 rc;
uniform float mult;

vec2 hash2( in vec2 x ) {
  int ii = int(mod(x.x+res.x*x.y,Nrandf)); //counter into array of random #s
  int i2 = int(mod(x.y-res.y*x.x,Nrandf)); //counter into array of random #s
  return vec2(rand[ii],rand[i2]);
}
float ddot ( in vec2 x, in vec2 y ) { return x.x+y.x + x.y*y.y; }
vec3 noise( in vec2 p ) {
    vec2 i = floor( p );
    vec2 f = fract( p );
    vec2 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    vec2 du = 30.0*f*f*(f*(f-2.0)+1.0);
    vec2 ga = hash2( i + vec2(0.0,0.0) );
    vec2 gb = hash2( i + vec2(1.0,0.0) );
    vec2 gc = hash2( i + vec2(0.0,1.0) );
    vec2 gd = hash2( i + vec2(1.0,1.0) );
    float va = ddot( ga, f );
    float vb = ddot( gb, f - vec2(1.0,0.0) );
    float vc = ddot( gc, f - vec2(0.0,1.0) );
    float vd = ddot( gd, f - vec2(1.0,1.0) );
    return vec3( va + u.x*(vb-va) + u.y*(vc-va) + u.x*u.y*(va-vb-vc+vd),   // value
                 ga + u.x*(gb-ga) + u.y*(gc-ga) + u.x*u.y*(ga-gb-gc+gd) +  // derivatives
                 du * (u.yx*(va-vb-vc+vd) + vec2(vb,vc) - va));
}

vec3 fbm( in vec2 x, in float H, in int numoct )
{
    float G = exp(-2.*H);float f = 1.0;float a = 1.0;vec3 t = vec3(0.);
    for( int i=0; i<numoct; i++ )
    { t += a*noise(f*x);f *= 2.0;a *= G; }
    return t;
}

vec4 laplacian(in sampler2D img, in vec2 uv, in float dx, in vec2 dt) {
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
    float sin1 = rand[42];
    vec2 dt = 1./res; //rc.z/res;
    float tfac = exp(1.+kl[6]*sin(t*kp[13]));
    vec2 uc = -rc.xy + u*rc.z;       // world space
    uc = u; // always simulate the entire world
    vec2 uv = u; // no resampling
    vec2 uc2 = uc;
    uc2.x*=1.+sin1*(40.*kl[14]-1.);
    uc2.y*=1.+(1.-sin1)*(40.*kl[15]-1.);
    vec3 ff = 1.9*(0.4+0.6*kp[9])*fbm(-(.3+.4*kl[11])*uc2+kl[16]+t/16.*vec2(kl[16]-.5,kl[17]-.5)+kl[18]*fbm((.3+.5*kl[12])*uc2,.7,4).yz,0.5,4);
    vec3 f2 = 1.1*(0.4+0.6*kp[10])*fbm(uc2+fbm(-0.6*uc2,0.7,5).yz,0.7,4);
sin1 = .5+clamp(kl[16]*200.*ff.y,-.5,.5);
float cos1 = 1.-sin1;
float sin2 = .5+clamp(100.*ff.z+40.*(kl[8]-.5),-.5,.5);
float sss = -1.+2.*round(fract(uc.y*res.y/8.));
float sss2 = -1.+2.*round(fract(uc.x*res.x/19./(.3+kl[2])));
sss = sin2*sss+(1.-sin2)*sss2;
uv.x+=.2*(1.+2.*kp[16])*cos1*(.3*tr*(1.-tr)*(1.-tr)*(ff.x*ff.x) + (1.-tr)*(1.-tr)*1.*(kl[0]-.5))*rand[0]*sss*17./res.x/2.*(round(fract(uc.y*res.y/2.))-.5);
uv.y+=.2*(1.+2.*kp[17])*sin1*(.3*tr*(1.-tr)*(1.-tr)*(ff.x*ff.x) + (1.-tr)*(1.-tr)*1.*(kl[0]-.5))*rand[0]*sss*17./res.y/2.*(round(fract(uc.x*res.x/2.))-.5);
float r2 = (uc.x-.5)*(uc.x-.5)+(uc.y-.5)*(uc.y-.5);
float sx = cos((uc.x-.5)*kl[7]*2.+kl[9]);
float sy = cos((uc.y-.5)*kl[8]/2.+kl[10]);
float x0 = .5+.5*cos(t/3.2321);
float y0 = .5+.5*sin(t/2.);
float rfac = (uc.x-x0)*(uc.x-x0)+(uc.y-y0)*(uc.y-y0);
rfac = exp(kp[17]*sin(5.*kp[18]*rfac));
   vec4 cc,cc2;
   vec4 lp,lpb,cv,cu,cvb,cub;
   vec4 lp2,lpb2,cv2,cu2,cvb2,cub2;
   float aa,bb,aa2,bb2;
   vec2 ex = vec2(1.,0.); vec2 ey = vec2(0.,1.);
     cc = texture(img,uv);
     aa = cc.x/256. + cc.y;
     bb = cc.z/256. + cc.w;
     lp = laplacian(img,uv,(kp[0]*2.-1.)*f2.x*(1.-aa),dt);
     lpb = laplacian(img,uv,(kp[1]*2.-1.)*ff.x*bb,dt);
     cv= texture(img, uv + ey*dt);
     cu= texture(img, uv + ex*dt);
     cvb= texture(img, uv - ey*dt);
     cub= texture(img, uv - ex*dt);
     cc2 = texture(img2,uv);
     aa2 = cc2.x/256. + cc2.y;
     bb2 = cc2.z/256. + cc2.w;
     lp2 = laplacian(img2,uv,(kp[0]*2.-1.)*f2.x*(1.-aa2),dt);
     lpb2 = laplacian(img2,uv,(kp[1]*2.-1.)*ff.x*bb2,dt);
     cv2= texture(img2, uv + ey*dt);
     cu2= texture(img2, uv + ex*dt);
     cvb2= texture(img2, uv - ey*dt);
     cub2= texture(img2, uv - ex*dt);
   float da = rfac*(1.-aa)*(1.-bb)*(lp.x+256.*lp.y)/256. + (1.+2.*kp[11])*( -aa*bb*bb + kl[10]*aa2*aa + 0.015*(1.+kp[17])*(1.-aa))*ff.x*ff.x ;
   float db = rfac*(1.+kp[7])*(0.02+ff.x*ff.x)*aa*0.5*(lpb.z+256.*lpb.w)/256. + (1.+2.*kp[11])*( aa*bb*bb - 0.04*(1.+1.*kp[6])*bb)*ff.x*ff.x;
   float da2 = 1.2*(1.-kp[17])*(1.+kp[7])*(0.02+f2.x*f2.x)*bb2*0.5*(lpb2.x+256.*lpb2.y)/256. + 3.*( bb*aa2*aa2 - 0.04*(1.+1.*kp[8])*aa2)*f2.x*f2.x;
float db2 = 1.2*(1.-kp[18])*(1.+kp[7])*(0.02+f2.x*f2.x)*aa2*0.5*(lpb2.z+256.*lpb2.w)/256. + 3.*( kl[10]*aa2*aa + 0.*aa2*bb2*bb2 - 0.04*(1.+1.*kp[9])*bb2)*f2.x*f2.x;
float dda=sin(3.*(1.+kp[2]*(ff.x-1.))*aa*1.57)*kp[15]*0.18*((cu.x/256.+cu.y-cub.x/256.-cub.y)*ff.y + (cv.x/256.+cv.y-cvb.x/256.-cvb.y)*ff.z);
float ddb=sin(3.*(1.+kp[3]*(f2.x-1.))*bb*1.57)*kp[16]*0.18*((cu.z/256.+cu.w-cub.z/256.-cub.w)*f2.y + (cv.z/256.+cv.w-cvb.z/256.-cvb.w)*f2.z);
float dda2=sin(5.*(1.+kp[2]*(ff.x-1.))*aa2*1.57)*kp[15]*0.18*((cu2.x/256.+cu2.y-cub2.x/256.-cub2.y)*ff.y + (cv2.x/256.+cv2.y-cvb2.x/256.-cvb2.y)*ff.z);
float ddb2=sin(5.*(1.+kp[3]*(f2.x-1.))*bb2*1.57)*kp[16]*0.18*((cu2.z/256.+cu2.w-cub2.z/256.-cub2.w)*f2.y + (cv2.z/256.+cv2.w-cvb2.z/256.-cvb2.w)*f2.z);
da += tfac*dda;
db += tfac*ddb;
da2 += tfac*dda2*(1.-dda2);
db2 += tfac*ddb2*(1.-ddb2);
vec2 dtt = vec2((2.*kl[28]-1.)*sy,sx);
da*=  (1.+kl[17])*2000.*dtt.x/mult;
db*=  (1.+kl[17])*2000.*dtt.x/mult;
da2*= 800.*dtt.y/mult;
db2*= 800.*dtt.y/mult;
da+=aa*256.*256.;
db+=bb*256.*256.;
da2+=aa2*256.*256.;
db2+=bb2*256.*256.;
float yn = floor(da/256.); // get leading part of da and rescale
float xn = (da-yn*256.);
float wn = floor(db/256.);
float zn = (db-wn*256.);
float yn2 = floor(da2/256.);
float xn2 = (da2-yn2*256.);
float wn2 = floor(db2/256.);
float zn2 = (db2-wn2*256.);
cout = vec4(xn,yn,zn,wn)/256.;
cout2 = vec4(xn2,yn2,zn2,wn2)/256.;
uc.x += 10.*ff.y*ff.z*uc.y;
cout*= 1.-kl[16]*.2*exp(-100.*(uc.x-.2-.6*kp[16])*(uc.x-.2-.6*kp[16]))-kl[17]*.2*exp(-100.*(uc.x-.2-.6*kp[17])*(uc.x-.2-.6*kp[17]))-kl[18]*.2*exp(-100.*(uc.x-.2-.6*kp[18])*(uc.x-.2-.6*kp[18]))-kl[19]*.2*exp(-100.*(uc.x-.2-.6*kp[19])*(uc.x-.2-.6*kp[19]));
}`;

var src_colp = header+`
const int N = 30;
const float Nf =20.;
const int Nrand =100;
const float Nrandf =100.;
const float dn =0.1;
const int Nx =512;
const float Nxf =512.;
const float PI =3.1415926;
const int numOctaves = 4; //8;

in vec2 u;
out vec4 cc;

uniform vec2 res;
uniform vec2 L;
uniform float t; // frame number
uniform highp sampler2D img;
uniform highp sampler2D img2;
uniform highp sampler2D imgp;
uniform highp sampler2D img2p;
uniform highp sampler2D pal;
uniform float rand[Nrand];
uniform vec2 mouse;
uniform vec3 dxy;
uniform vec3 rc;
uniform float kl[N];
vec2 hash2( in vec2 x ) {
  int ii = int(mod(x.x+res.x*x.y,Nrandf)); //counter into array of random #s
  int i2 = int(mod(x.y-res.y*x.x,Nrandf));
  return vec2(rand[ii],rand[i2]);
}
float ddot ( in vec2 x, in vec2 y ) { return x.x+y.x + x.y*y.y; }
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

vec3 fbm( in vec2 x, in float H)
{
    float G = exp(-2.*H);
    float f = 1.0;
    float a = 1.0;
    vec3 t = vec3(0.0);
    for( int i=0; i<numOctaves; i++ )
    {
        t += a*noise(f*x);
        f *= 2.0;
        a *= G;
    }
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
  float lum = rand[45];
  float sqr = rand[46];
  sqr=1.-rc.z*(1.-sqr);
  float horiz = rand[48];
  float eclipa = rand[67];
  float eclipt = rand[68];
  float cres   = rand[69];
  float esc    = rand[88];
  float x0 = (1.+eclipa*cos(eclipt+t*0.02))/2.;
  float y0 = (1.+eclipa*sin(eclipt+t*0.02))/2.;

  float sin1 = rand[42];
vec2 uv = (u+dxy.xy-vec2(0.5))*(1.+dxy.z)+vec2(0.5); // screen space
vec2 uc = -rc.xy + u*rc.z;       // world space

float RR0,r2;
if (esc>0.) {
  vec4 lpo = laplacian(imgp,uc+kl[28]*.5/res,0.);
  vec2 uc0 = uc + 2.*kl[6]*0.06*lpo.yw; //+dxy.xy-vec2(0.5))*(1.+dxy.z)+vec2(0.5); // mouse in screen space
  vec2 mmouse = uc0; // + mouse;
  r2 = (uc.x-uc0.x)*(uc.x-uc0.x)*L.x*L.x+(uc.y-uc0.y)*(uc.y-uc0.y)*L.y*L.y;
  RR0 = .2*L.y;
  float lam = sqrt(r2)/RR0;
  vec2 u2 = uc + (uc-mmouse)*clamp(0.3*1./(1.-lam),-100.,100.);
  u2 = (u2+rc.xy)/rc.z;
  uv = (u2+dxy.xy-vec2(0.5))*(1.+dxy.z)+vec2(0.5); // screen space
  uc = -rc.xy + u2*rc.z;       // world space
}
float fx = .5+(fract(uc.x*res.x)-.5)*1.43;
float fy = .5+(fract(uc.y*res.y)-.5)*1.43;
fx += horiz*(.5-fx);
float fxn = (fx-.5)*.7 + .5;  //properly normalized to [0,1]
float fyn = (fy-.5)*.7 + .5;
float sss = 1.;
cc = texture(img,uc); // in [0,1]
vec4 cco = texture(imgp,uc);
vec4 cc2 = texture(img2,uc);
vec4 cco2 = texture(img2p,uc);
vec4 ccx = texture(img,uc+1.*vec2(1./res.x,0.));
vec4 ccy = texture(img,uc+1.*vec2(0.,1./res.y));
float aa = (cc.x+256.*cc.y)/256.;
float bb = (cc.z+256.*cc.w)/256.;
float aao = (cco.x+256.*cco.y)/256.;
float bbo = (cco.z+256.*cco.w)/256.;
float aa2 = (cc2.x+256.*cc2.y)/256.;
float bb2 = (cc2.z+256.*cc2.w)/256.;
float hyp = sqrt(.01 + (ccx.z/256.+ccx.w-bb)*(ccx.z/256.+ccx.w-bb) + (ccy.z/256.+ccy.w-bb)*(ccy.z/256.+ccy.w-bb));
float ct = (ccx.z/256.+ccx.w-bb)/hyp;
float st = (ccy.z/256.+ccy.w-bb)/hyp;
float fx2 = x0+(fx-x0)*ct+(fy-y0)*st;
float fy2 = y0-(fx-x0)*st+(fy-y0)*ct;
float r22 = (fx2-x0)*(fx2-x0)+(fy2-y0)*(fy2-y0)-0.2;
float rxmy = abs((fx-.5)*ct+(fy-.5)*st)-0.1;//*ff.x;
hyp = sqrt(.01 + (ccx.z/256.+ccx.w-bbo)*(ccx.z/256.+ccx.w-bbo) + (ccy.z/256.+ccy.w-bbo)*(ccy.z/256.+ccy.w-bbo));
float cto = (ccx.z/256.+ccx.w-bbo)/hyp;
float sto = (ccy.z/256.+ccy.w-bbo)/hyp;
float rx = abs(fx-x0);
float ry = abs(fy-y0);
vec2 dx = floor(3.*vec2(kl[22],kl[23]))/res;
vec4 ccu = texture(img,uc+dx);
vec4 ccd = texture(img,uc-dx);
float rxn = abs(fxn-.5);
float ryn = abs(fyn-.5);
// add curvature
vec2 duc = 3.*(1.-rand[45])*(1.-rand[46])*vec2((kl[21]-.5)*fxn*(1.-fxn)*((fyn-.5)*(fyn-.5)), (kl[22]-.5)*fyn*(1.-fyn)*((fxn-.5)*(fxn-.5)));
uc+=duc/res;
vec2 uc2 = uc;
uc2.x*=1.+sin1*(40.*kl[14]-1.);
uc2.y*=1.+(1.-sin1)*(40.*kl[15]-1.);
vec3 ff = .5*fbm(-(.3+.4*kl[11])*uc2+kl[16]+t/16.*vec2(kl[16]-.5,kl[17]-.5)+fbm((.3+.5*kl[12])*uc2,.7).yz,0.5);
vec3 f2 = fbm(uc2+fbm(-0.6*uc2,0.7).yz,0.5);
r2 = 1.1*sqrt((fx-.5)*(fx-.5)+(fy-.5)*(fy-.5))-.42*(1.-(1.-lum)*(1.-horiz)*(.2-.3*aa*aa));
float drr = clamp((min(abs(rx-rx),abs(rx+ry))-.1*ff.x)*20.,0.,1.); // rounded squares
float drrmix = clamp(mix(1.-aa-ff.y-bb,3.*(bb+aa-ff.x),rand[40]),0.,1.);
drrmix*=4.*(1.-drrmix);
drr += .7*(1.-drr);
 vec4 lp = laplacian(img,uc,0.9*ff.x*aa);
 vec4 lp2= laplacian(img2,uc,0.9*ff.x*aa2);

aao=0.12*(lp.x+lp.y*256.);
bbo=0.12*(lp.z+lp.w*256.);
float aao2=0.12*(lp2[0]+lp2[1]*256.);
float bbo2=0.12*(lp2[2]+lp2[3]*256.);
ff.z *= 1. + 3.*uc.x*(1.-uc.x);
ff.y *= 1. + 3.*uc.x*(1.-uc.x);
float px = 20.*bb*aa+1.4*(aa)*ff.x+1.4*(bb)*f2.x;
float pxo = 20.*bbo*aao+1.4*(aao)*ff.x+1.4*(bbo)*f2.x;
vec4 cc_hsl = texture(pal,vec2(5.*px*px,kl[5]*uc.y+ff.z*bb));
vec4 cco_hsl = texture(pal,vec2(5.*pxo*pxo,kl[5]*uc.y+ff.z*bbo));
vec4 cc2_hsl = texture(pal,vec2(1.-2.*bb2*aa2-0.4*(aa2)*ff.x-0.4*(bb2)*f2.x,1.-ff.y*bb));
vec4 cco2_hsl = texture(pal,vec2(1.-2.*bbo2*aao2-0.4*(aao2)*ff.x-0.4*(bbo2)*f2.x,1.-ff.y*bbo));
cc_hsl.z = pow(cc_hsl.z,1.7);
cco_hsl.z = pow(cco_hsl.z,1.4);
cc_hsl.rgb -= (.1+.7*kl[13])*(cc_hsl.rgb-cco_hsl.rgb);
cc_hsl.x += .15*drrmix;
cc_hsl.x *= 1.+(cc_hsl.x-1.)*kl[7];  // colour modulation
cc_hsl.x += 0.1*((fx-.5)*aa2+(fy-.5)*bb2);
cc_hsl.x = fract(cc_hsl.x);
cc_hsl.z *= 0.9+3.*bb+kl[4]*aa*aa2+kl[2]*bb2/(1.+bb2)+kl[3]*aa*bb; // multiply lightness by particle number
cc_hsl.y *= (1.15-.1*ff.x*ff.x*bb); //*(1.-f2.x*f2.x); // multiply sat by 1-particle number
cc_hsl.y = pow(cc_hsl.y,.7);
cc_hsl.z*=1.4 - 0.3*rand[45]-2.*kl[4]*uc.x*(2.-3.*uc.x)*(x0-rx)*(y0-ry);
cc_hsl=clamp(cc_hsl,0.01,1.);
// hsl to rgb:
vec3 rgb = clamp( abs(mod(cc_hsl.x*6.0+vec3(0.0,4.0,2.0),6.0)-3.0)-1.0, 0.0, 1.0 );
rgb = cc_hsl.z + cc_hsl.y * (rgb-0.5)*(1.0-abs(2.0*cc_hsl.z-1.0));
cc = vec4(pow(rgb.r,(kl[9]-.1*lum-.4*bbo2)*.6),pow(rgb.g,(kl[11]-.1*lum-.3*aao2)*.6),pow(rgb.b,(kl[10]-.1*lum-.1*aa*bb)*.6),1.);
cc.rgb=clamp(cc.rgb,0.01,1.);
cc.rgb *= cc.rgb*(3.-2.*cc.rgb);
cc.rgb *= .6+.4*cc.rgb*(3.-2.*cc.rgb);
cc.xyz*=exp(-.3*abs(st*cto-sto*ct));
vec4 ccoo = vec4(cc.bgr,1.);
cc = mix(cc,ccoo,clamp(20.*(0.1+0.3*ff.x*ff.x)*0.03*(aao*aao*bbo*bbo),0.001,0.99));
r2 += lum*((2.*kl[7]-1.)*r2*r2*r2-r2); // very trippy
r2 *= 1.+rand[46]*(r2-1.); // round squares
r2+=1.;
r2*= 4.*r2*r2-6.*r2+3.;
r2-=1.3;
cc.rgb = 1.-cc.rgb; // = kl[19]*(1.-cc.rgb) + (1.-kl[19])*cc.rgb;
drr *= (1.-rand[47]) + rand[47]*r2*.5; // rand[47] = rcorr
vec3 cc_bg = vec3(rand[39],rand[40],rand[41]);
cc_bg *= 1.-.05*drr*(rx+ry-.67+.3*f2.y)*(1.+cc.rgb)*(1.+lum);
cc_bg *= .7+.3*sqrt(rc.z); //rc.z;
aa = sin(10.*fx*aao*kl[27]);
bb = sin(10.*fy*bbo*kl[28]);
fx2 += kl[3]*(fx-fx2);
fy2 += kl[4]*(fy-fy2);
RR0 = .8-kl[2]*.4; //.7; //.95/2.;
float rfac = 1. + (kl[29]-.5)*(-.2+.4*clamp(0.5+(1.-2.*cres)*(RR0*RR0-(fx2-aa*x0)*(fx2-aa*x0)-(fy2-bb*y0)*(fy2-bb*y0))/(0.01*0.05*(1.+9.*eclipa/0.02)), .5-.25*cres, 1.));
cc.r *= rfac*(1.-2.*kl[19])+2.*kl[19];
cc.g *= kl[19] + rfac*(1.-kl[19]);
cc.b *= rfac;
cc.rgb = mix(cc.rgb, cc_bg, clamp(clamp(1.-rc.z,.6,1.)*drr*r2,-0.5,1.)); //.-r2));
// glow:
cc.rgb *= 1.+0.2*(1.-lum)*(1.-sqr)*(-0.7+pow(max(.32,(fxn-.5)*(fxn-.5)+(fyn-.5)*(fyn-.5)),2.));
cc=clamp(cc,0.001,.999);

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
    prngA = new sfc32(tokenData.hash.substr(2, 32));
    prngB = new sfc32(tokenData.hash.substr(34, 32));
    for (let i = 0; i < 1e6; i += 2) {
      prngA();
      prngB();
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
if (GET.hash) { tokenData.hash = GET.hash; }
let mintn = tokenData.tokenId%1000000;
let hashlist = [
  "0xa13b49485299cc1d0a337166703adaa84d16afdd7f967817d97cb12a12261002",
  "0x646d6cae9d01d922825bd8f5f40fdb820299b3582fedac9b4a540972ef885f44",
  "0x3f4f04b90d31bee7e4750fda24cecbb9c674344aaddcf2de91e4e1a377ba35f1",
  "0x90b70525cb642187a6e0f56018a42ec3f419b2f7c544a12184c331b2797812de",
  "0x26e0b3f96a81f1c56858d6011a8f60681498cffda232093f4dc1b24ae80d01ec",
  "0x49abdd5f90e662835b83e7eb4fe993de9866a0d0b4d9f701fff94338a0489d49",
  "0x1a9f7d7cb6ca528846d9b6387a8988d8f67b5d36de0a991a36cb9292672294b7",
  "0x22c5d01cd9df91ebe1aaaadb92facd9bbb618625e963da7c1c3ec6c862b19955",
  "0x6b8bfb011ceaf50891a20ed882870f0d49d53c8e633a4f546e14e844ab993bc1",
  "0x2296bca26af467663a989ab9d733d90f22f8994bc72ec46801128fe77ae8722d"
];
(mintn>0)&&(mintn<11)&&(tokenData.hash=hashlist[mintn-1]);
R = new Random();

let C,D,body,gl,Shader;
document.body.style.backgroundColor = "#030303";
console.log("Atlas by Eric De Giuli");
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

let simp,colp,vs,fs;
let Lx,Ly,Nx,Ny;
let hgt = rnd();
let Nm = (hgt<.15) ? 30 : (hgt<0.4) ? 60 : (hgt<0.6) ? 90 : (hgt<0.75) ? 120 : 240;
const head = /\bHeadlessChrome\//.test(navigator.userAgent);
let PI = 3.1415926;

let pal,pj;
let palp = [11,4,8,3,4,3,4,4,3,3,6,2,4,3,6,10,6,5,5,3];
const pinv = [0.7,1,1,1,0,1,0,1,1,1,1,1,0,1,0.5,0.5,0.5,0,0.4,1]; // prob of inv
const plum = [0,0,1,0.4,0,1,0,1,0,0,0.4,1,0,0.4,0,0,0.4,0,0.4,1]; // prob of lum
palp = vecscl(palp,1/97);
let cumpal = []; cumpal[0]=0;
for (let i=1; i<palp.length; i++) { cumpal[i]=cumpal[i-1]+palp[i-1]; }
let st = 1;
pj=1;
let palr = rnd();
while (st<palp.length && cumpal[st]<palr) { st++; } st--;

let pj2 = Math.floor(11*rnd());
let kl = new Float32Array(N);
for (let i=0; i<N; i++) { kl[i]=rnd(); }
kl[7]*=kl[7]*(3-2*kl[7]);
kl[19]*=kl[19];//*(3-2*kl[19]);
kl[28]*=kl[28]*(2-kl[28]);
kl[29]*=kl[29]*(3-2*kl[29]);
kl[5] = 1-kl[5]*kl[5];
kl[15]=1.-kl[15]*kl[15];//*kl[15];
let lum=0,inv=0,sqr = 0;
let starch = 1;
let rcorr = rnd();
sqr=rnd();sqr*=sqr;
let horiz = (rnd()<.2) ? 1 : 0;
let eclipa = rnd()<0.2 ? 0.1*Math.exp(rnd()) : 0;
let eclipt = 6.2*rnd();
let cres = 1; eclipa = Math.max(0.1,eclipa); eclipa*=3;
let anim=0;
let esc = rnd()<.22 ? 1 : 0;
inv = rnd()<pinv[st] ? 1 : 0;
lum = rnd()<plum[st] ? 1 : 0;
kl[9]=0.9;
kl[11]=0.9;//+.1;
kl[10]=0.9;//-.1;
switch(st) {
  case 0: pj=6;pj2=7; horiz=0; (!inv)&&(kl[7]=-1-.5*kl[7]); kl[29]=.5; break;
  case 1: pj=11;pj2=7; kl[10]-=.4; kl[7]*=-2/3; Nm*=2; Nm=Math.min(240,Nm); break;
  case 2: pj=1;pj2=5; kl[10]-=.1; kl[7]/=3; (kl[0]<.2)&&(Nm=15); break;
  case 3: pj=1;pj2=0; kl[9]-=.1; kl[10]-=.15; kl[29]*=.5; Nm=Math.max(90,Nm); horiz=0; kl[7]*=-1; kl[2]*=2;kl[3]*=2;kl[4]*=2; break;
  case 4: pj=3;pj2=9; kl[29]*=.5; kl[7]=-1; kl[3]=.95; Nm=Math.min(120,Nm);  horiz=0; break;
  case 5: pj=6;pj2=0; kl[9]-=.2; kl[29]*=.5; kl[7]=inv ? 0 : -1; esc=1; Nm*=2; break;
  case 6: pj=4;pj2=7; sqr=0; Nm/=2; Nm=Math.max(30,Nm); kl[19]=1.5; kl[29]=1; horiz=0; break; // nocturne
  case 7: pj=11;pj2=5; kl[10]-=.1; kl[7]=0; break;
  case 8: pj=11;pj2=4; kl[9]-=.2;kl[10]-=.2;kl[11]-=.2;kl[7]=-1; sqr*=sqr; horiz=0; Nm=Math.max(Nm/2,30); break;
  case 9: pj=11;pj2=0; kl[10]-=.2; sqr = 1-sqr*sqr; kl[7]=-1; Nm=Math.min(Nm,90); break;
  case 10: pj=0;pj2=0; Nm=Math.max(90,Nm); horiz=0; kl[29]= lum ? 0 : .5; break;
  case 11: pj=3;pj2=3; horiz=1; kl[3]=.97; kl[5]=0.1; kl[7]=1; rcorr=0; break;
  case 12: pj=2;pj2=3; kl[7]=1; horiz=0; break;
  case 13: pj=2;pj2=10; sqr/=2; kl[7]*=-1; kl[29]=.5; Nm = Math.min(90,Nm); horiz=0; break;
  case 14: pj=10;pj2=8; kl[9]-=.1*(1-2*inv); kl[10]-=.1; kl[7]*=-.8; horiz=0; break;
  case 15: pj=10;pj2=4; sqr/=2; kl[2]=1-kl[2]*kl[2]; (!inv)&&(kl[19]=2); (inv==1)&&(Nm=Math.max(60,Nm)); horiz=0; kl[29]*=0.5; break;
  case 16: pj=6;pj2=10; (!inv)&&(lum=0); (lum)&&(kl[29]=0); break;
  case 17: pj=7;pj2=12; kl[10]-=.2; kl[4]=0; kl[13]=1; kl[7]=-0.2; kl[19]=1; Nm=Math.max(30,Nm/2); break;
  case 18: pj=12;pj2=3; kl[29]=.5; esc=0; (inv)&&(lum=horiz=0); break;
  case 19: pj=12;pj2=6; kl[29]*=.5; esc=1; lum=1;kl[7]=0;horiz=0; Nm=Math.max(Nm,90);
}


(!lum)&&(esc=0);
(esc)&&(Nm=Math.max(15,Nm/2));

(Nm<=20)&&(horiz=sqr=0);
(starch==0)&&(lum=1);
(lum==1)&&(rcorr=1-rcorr*rcorr*rcorr);
(lum)&&(horiz=sqr=0);
(horiz)&&(kl[21]=kl[29]=.5);
(kl[15]<.3)&&(kl[29]=0.5);

(lum&&Nm>100)&&(Nm/=2);
if (GET.N) { Nm=GET.N; }
if (innerWidth>innerHeight) {
  Ny = Nm;
  Nx = Math.floor(Nm*innerWidth/innerHeight);
} else {
  Nx = Nm;
  Ny = Math.floor(Nm*innerHeight/innerWidth);
}
if (GET.a) { Ny=Nm;Nx=Math.floor(GET.a*Ny); }

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

let kp,km,rand,randp,randn;
rand = []; for (let i=0; i<Nrand; i++) { rand[i]=rnd(); }
randp = []; for (let i=0; i<Nrand; i++) { randp[i]=rnd(); }
randn = []; for (let i=0; i<Nrand; i++) { randn[i]=rnd(); }
let k0=1;
kp = new Float32Array(N);
km = new Float32Array(N);
for (let i=0; i<N; i++) { kp[i]=k0*rnd(); }
kp[11]*=kp[11];
for (let i=0; i<N; i++) { km[i]=k0*rnd(); }

let bg_h = (lum*.5+ pal[0]/255)%1;
let bg_s = .5;//.65; //pal[1]/255*1.2;
let bg_l = Math.pow(pal[2]/255,.75);
let bg_r = Math.max(0,Math.min(1, Math.abs(bg_h*6.0-3.0)-1.0));
let bg_g = Math.max(0,Math.min(1, Math.abs((bg_h*6.0+4.0)%6-3.0)-1.0));
let bg_b = Math.max(0,Math.min(1, Math.abs((bg_h*6.0+2.0)%6-3.0)-1.0));
bg_r = bg_l + bg_s*(bg_r-.5)*(1-Math.abs(2.0*bg_l-1.0));
bg_g = bg_l + bg_s*(bg_g-.5)*(1-Math.abs(2.0*bg_l-1.0));
bg_b = bg_l + bg_s*(bg_b-.5)*(1-Math.abs(2.0*bg_l-1.0));
 bg_b = Math.pow(bg_b,.4+.3*kp[0]);

function setrand() {
  rand[0] = km[16]*3;
  rand[2] = km[17]*3;
  rand[37] = km[0];
  rand[38] = kp[4];
  rand[39] = bg_r;
  rand[40] = bg_g;
  rand[41] = bg_b;
  rand[42] = km[5] < .77 ? 1 : 0;
  rand[43] = km[6];
  rand[44] = km[7];
  rand[45] = lum;
  rand[46] = sqr;
  rand[47] = rcorr;
  rand[48] = horiz;
  rand[67] = eclipa;
  rand[68] = eclipt;
  rand[69] = cres;
  rand[88] = esc;

}
setrand();

let nx = 2+Math.floor(3*rnd());
let ny = 2+Math.floor(3*rnd());
let rr = rnd();
let n4 = Math.floor(Math.exp(4*rnd()));
let rbg = Math.floor(19*rnd());
let rbgarr = [0,1,2,3,4,6,6,7,8,8,9,9,11,12,13,14,15,15,16];
rbg=rbgarr[rbg];
(rbg==1)&&(Nm=Math.min(60,Nm));
function ff1(x,r) { return r*2*kl[20]*2*Math.sin(x*rr*2*PI+kl[0])*Math.sin(x*rr*2*PI+kl[0]); }
function ff2(x,r) { return r*2*kl[21]*2*Math.cos(x*rr*2*PI+kl[1])*Math.cos(x*rr*2*PI+kl[1]); }
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
      case 1: r2 = .25*Math.sin(2*x/Nx*nx*PI)*Math.sin(2*y/Ny*ny*PI)*Math.sin(25*r2)-0.5*rr; break;
      case 2: r2 = Math.sin(y*x/Nx*nx*PI)*Math.sin(y/Ny*ny*PI)*Math.sin(25*r2)-0.5*rr; break;
      case 3: r2 = Math.sin(y*x/Nx*nx*PI)*Math.sin(y/Ny*ny*PI)*Math.sin(2*(x-Nx/2)/(y-Ny/2)+1*(y-Ny/2)/(x-Nx/2))>0.5*rr; break;
      case 4: r2 = 1+Math.sin(Math.sin(x/Nx*n4)*y/Ny*nx*PI)*Math.sin(y/Ny*ny*PI)*Math.sin(2*(x-Nx/2)/(y-Ny/2)+1*(y-Ny/2)/(x-Nx/2))-0.5*rr;
      (r2!=r2)&&(r2=1); break;
      case 5: r2 = Math.sin(Math.sin(x/Nx*n4*PI)*y/Ny*(1-y/Ny)*ny*PI)*Math.sin(x/Nx*nx*PI)-0.6*rr; break;
      case 6: r2 = Math.sin(Math.sin(y/Ny*n4*PI)*x/Nx*(1-x/Nx)*nx*PI)*Math.sin(y/Ny*ny*PI)-0.6*rr; break;
      case 7: r2 = Math.sin(30*x/Nx*nx*PI)*Math.sin(x/Nx*nx*PI)>0.6*rr; break;
      case 8: r2 = Math.sin(30*x/Nx*nx*PI)*Math.sin(y/Ny*ny*PI)>0.6*rr; break;
      case 9: r2 *= .7*(Math.sin(20*(x/Nx-0.5)*nx)+Math.sin(2*(y/Ny-0.5))); break;
      case 10: r2 = 1+r2*Math.sin(20*r2*nx)-.3*rr; break;
      case 11: r2 = -1+Math.sin(r2*nx*Math.tan(n4*x/Nx+9*y/Ny))-.6*rr; break;
      case 12: th = Math.atan2(y-Ny/2,x-Nx/2); r2*=1+0.2*Math.cos(nx*th)*(1+0.6*Math.sin(nx/ny+3*nx*th)*(1+0.6*Math.cos(5*nx*th))); r2*=.72; break;
      case 14: r2=0.2+.8*rr; break;
      case 15: r2 = 10*Math.max(x/Nx/3,(1-x/Nx)/3); break;
      case 16: r2 = 10*Math.max(y/Ny/3,(1-y/Ny)/3); break;
    }
    tex0[4*i]   = Math.floor(255*ff1(r2,rnd()));
    tex0[4*i+1] = Math.floor(255*ff2(r2,rnd()) );
    tex0[4*i+2] = Math.floor(255*ff2(r2,rnd()) );
    tex0[4*i+3] = Math.floor(255*ff1(r2,rnd()) );
  }
}

dzp=dzc;
let loc_a,loc_ac,loc_img,loc_img00,loc_img2,loc_img02,loc_res,loc_t,loc_tr,loc_rand,loc_palc,loc_kp,loc_km,loc_kl,loc_klc,loc_kv,loc_kw,loc_imgc,loc_imgc2,loc_imgcp,loc_imgc2p,loc_resc,loc_Lc,loc_tc,loc_randc,loc_aavg,loc_bavg,loc_dxy,loc_dxyc,loc_rc,loc_rcc;

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
loc_img2=gul(simp,'img2');
loc_img02=gul(simp,'img02');
loc_res=gul(simp,'res');
loc_t  =gul(simp,'t');
loc_tr  =gul(simp,'tr');
loc_rand =gul(simp,'rand');
loc_kp =gul(simp,'kp');
loc_km =gul(simp,'km');
loc_kl =gul(simp,'kl');
loc_dxy =gul(simp,'dxy');
loc_rc  =gul(simp,'rc');
let loc_mult  =gul(simp,'mult');

gl.uniform1i(loc_img,0);
gl.uniform1i(loc_img00,1);
gl.uniform1i(loc_img2,2);
gl.uniform1i(loc_img02,3);
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
loc_imgcp=gul(colp,'imgp');
loc_imgc2=gul(colp,'img2');
loc_imgc2p=gul(colp,'img2p');
loc_palc=gul(colp,'pal');
loc_resc=gul(colp,'res');
loc_Lc=gul(colp,'L');
loc_tc  =gul(colp,'t');
loc_randc  =gul(colp,'rand');
loc_dxyc  =gul(colp,'dxy');
loc_rcc  =gul(colp,'rc');
loc_klc =gul(colp,'kl');
let loc_mousec=gul(colp,'mouse');

gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1.0, 1.0, 1.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, -1.0]),gl.STATIC_DRAW);

gl.uniform1i(loc_imgc,0);
gl.uniform1i(loc_imgcp,2);
gl.uniform1i(loc_imgc2,3);
gl.uniform1i(loc_imgc2p,4);
gl.uniform2f(loc_resc,Nx,Ny);

loc_ac = gl.getAttribLocation(colp, "a"); //'a');
gl.activeTexture(gl.TEXTURE0);
gl.vertexAttribPointer(loc_ac, 2, gl.FLOAT, false, 0, 0);
gl.enableVertexAttribArray(loc_ac);

let M=1;
var isMobile = window.matchMedia("(hover: none)").matches; // no hovering
let dpr=1;
function resize_render() {
  let w=innerWidth, h=innerHeight, dpr=devicePixelRatio;
  C.width  = M*w*dpr|0;
  C.height = M*h*dpr|0;
  if (head || f1==0) {
Lx = Math.floor(C.width);
Ly = Math.floor(C.height);
  } else {//if (f1==1 || isMobile) {
    C.requestFullscreen();
    Lx = C.width; Ly=C.height;
  }
  C.style.width = w+'px';
  C.style.height = h+'px';
   gl.viewport((C.width-Lx)/2,(C.height-Ly)/2,Lx,Ly);
  render();
}

   function texset(wrap=gl.CLAMP_TO_EDGE,fil=gl.NEAREST) { //NEAREST) {
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, wrap);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, wrap);
   gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, fil);
   gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, fil);
}
let tex00,tex02,texA,texB,texA2,texB2,texC,fbA,fbB;

tex00 = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, tex00);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, tex0.subarray(0, Nx*Ny*4));
texset(gl.REPEAT,gl.LINEAR);
tex02 = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, tex02);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, 255-tex0.subarray(0, Nx*Ny*4));
texset(gl.REPEAT,gl.LINEAR);

texA = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texA);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, tex0.subarray(0, Nx*Ny*4));
fbA = gl.createFramebuffer();
gl.bindFramebuffer(gl.FRAMEBUFFER, fbA);
gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texA, 0);
texset();

texB = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texB);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
fbB = gl.createFramebuffer();
gl.bindFramebuffer(gl.FRAMEBUFFER, fbB);
gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texB, 0);
texset();

texA2 = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texA2);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, 255-tex0.subarray(0, Nx*Ny*4));
gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, texA2, 0);
texset();

texB2 = gl.createTexture();
gl.bindTexture(gl.TEXTURE_2D, texB2);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, Nx, Ny, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT1, gl.TEXTURE_2D, texB2, 0);
texset();

texC = gl.createTexture(); //colormap
gl.bindTexture(gl.TEXTURE_2D, texC);
gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGB, 10, 2, 0, gl.RGB, gl.UNSIGNED_BYTE, pal);
texset(gl.REPEAT,gl.LINEAR);
//texset(gl.CLAMP_TO_EDGE,gl.LINEAR);

gl.useProgram(colp);
gl.uniform1i(loc_palc, 1); //texture 1
// and assign uniforms
gl.useProgram(simp);
gl.uniform1fv(loc_km,km);
gl.uniform1fv(loc_kl,kl);
gl.uniform1fv(loc_rand,rand);

gl.useProgram(colp);
gl.uniform1fv(loc_randc,rand);

let prevt=performance.now(); //0;
let frm=30;
if (GET.frm) { frm=GET.frm; }
let dt = 1000/frm;
let tmult=1,init=1;
let running=true;
let periodic=0;
let flip=0;
let count=0;
let dxycount=0;
let TT = 60+Math.floor(1000*Math.exp(kl[0]-1));//240;
let om0 = 10*0.01;
let time0 = prevt;
let time;
function render() {
  if (running) {
    let wgt = count/TT;
    time=performance.now(); // ms
    if (time-prevt>dt) {
      count++;
      gl.viewport(0,0,Nx,Ny);
    gl.useProgram(simp);
    gl.uniform1f(loc_mult,tmult);
    if (count%TT==0) {
      for (let i=0; i<Nrand; i++) { randp[i]=randn[i]; randn[i]=.5*rnd()+.5*rand[i]; }
      setrand();
      count=0;
    }

    let wgtfac = wgt*wgt*(1-Math.exp(-4*kl[1]*wgt));
    if (count%TT==0) {
      for (let i=0; i<Nrand; i++) { rand[i]=randp[i]+(randn[i]-randp[i])*wgtfac; }
      setrand();
      gl.uniform1fv(loc_rand,rand);
    }
    let dx1=0,dy1=0,dz1=0;
    if (dxycount==0) {
      dx=dxc-dxp;
      dy=dyc-dyp;
      dz=dzc-dzp;
      zc *= Math.exp(2*dz);      //zc += dz;
      xc -= (.5+(2*dx-0.5)*(1+2*dz))*zc;
      yc -= (.5+(2*dy-0.5)*(1+2*dz))*zc;
      // imposing max(uc.x)<=1, i.e. -xc+zc <= 1, i.e. xc >= zc-1, i.e. dxc >= zc-1-xc
      // imposing min(uc.x)>=0, i.e. -xc    >= 0, i.e. xc <= 0, i.e. dxc <= -xc
      // we need to impose this again because inequalities may fail because zc changed
      xc=Math.max(zc-1,Math.min(0,xc));
      yc=Math.max(zc-1,Math.min(0,yc));
      // // if truncated, fix dx,dxc,dy,dyc
      dx = (-.5/(1+dz)+.5)/2; dxc = dxp+dx;
      dy = (-.5/(1+dz)+.5)/2; dyc = dyp+dy;
      (zc==1)&&(dxc=dyc=0);
      kp[6]*=Math.sin(count/TT*2*PI);
      kp[7]*=Math.sin(count/TT*2*PI);
    }
    gl.uniform1fv(loc_kp,kp);
    //    for (let i=0; i<Nrand; i++) { rand[i]*=0.99; }
    if (dx!=0 || dy!=0 || dz!=0) {
      dxycount++;
    }
    gl.uniform3fv(loc_dxy,[dx, dy, dz]);
    gl.uniform3fv(loc_rc,[xc, yc, zc]);
    gl.uniform1f(loc_t,time/1000.);
    gl.uniform1f(loc_tr,count/TT);
    for (let j=0; j<2; j++) {
      flip = !flip;
      gl.bindFramebuffer(gl.FRAMEBUFFER, (flip ? fbB : fbA));
      gl.activeTexture(gl.TEXTURE0);
      gl.bindTexture(gl.TEXTURE_2D, (flip ? texA : texB));
      gl.activeTexture(gl.TEXTURE1);
      gl.bindTexture(gl.TEXTURE_2D, tex00);
      gl.activeTexture(gl.TEXTURE2);
      gl.bindTexture(gl.TEXTURE_2D, (flip ? texA2 : texB2));
      gl.activeTexture(gl.TEXTURE3);
      gl.bindTexture(gl.TEXTURE_2D, tex02);
      gl.drawBuffers([ gl.COLOR_ATTACHMENT0,gl.COLOR_ATTACHMENT1 ]);
      gl.drawArrays(gl.TRIANGLES, 0, 6);
    }
    // flip = !flip;
    gl.viewport((C.width-Lx)/2,(C.height-Ly)/2,Lx,Ly);
    gl.useProgram(colp);
    gl.uniform1f(loc_tc,time/1000);
    gl.uniform2f(loc_Lc,Lx,Ly);
    gl.uniform2f(loc_mousec,mousex,mousey);
    gl.uniform1fv(loc_klc,kl);
    gl.uniform3fv(loc_dxyc,[dx-dx1, dy-dy1, dz-dz1]);
    gl.uniform3fv(loc_rcc,[xc, yc, zc]);
    dxycount=0;dx=0;dy=0;dz=0;dxp=dxc;dyp=dyc;dzp=dzc;
    if (count>12) { init=0; }
if (!init) {
  gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  gl.activeTexture(gl.TEXTURE0);
  gl.bindTexture(gl.TEXTURE_2D, (flip ? texB : texA));
  gl.activeTexture(gl.TEXTURE1);
  gl.bindTexture(gl.TEXTURE_2D, texC);    //color map
  gl.activeTexture(gl.TEXTURE2);
  gl.bindTexture(gl.TEXTURE_2D, tex00); //(flip ? texA : texB));  // previous
  gl.activeTexture(gl.TEXTURE3);
  gl.bindTexture(gl.TEXTURE_2D, (flip ? texB2 : texA2));
  gl.activeTexture(gl.TEXTURE4);
  gl.bindTexture(gl.TEXTURE_2D, tex02); //(flip ? texA2 : texB2)); // previous
  //if (dz==0)
  gl.drawArrays(gl.TRIANGLES, 0, 6);

}
  }

  prevt=time-(time-prevt)%dt;
  }
  if (savescr==1) {
    savescr=2;
    resize_render();
  }
  if (savescr==2) {
    savescr=0;
    var tC = document.createElement("canvas");
    tC.width = Lx; tC.height = Ly;
    var ctx = tC.getContext("2d", { preserveDrawingBuffer: true });
    const pixels = new Uint8Array(4);
    gl.readPixels(0,0,1,1,gl.RGBA, gl.UNSIGNED_BYTE, pixels);
    ctx.setTransform(1,0,0,-1,0,gl.height);
    const sync = gl.fenceSync(gl.SYNC_GPU_COMMANDS_COMPLETE, 0);gl.flush();gl.clientWaitSync(sync, 0, gl.TIMEOUT_IGNORED);gl.deleteSync(sync);
    C.toBlob((blob) => { saveBlob(blob, `Atlas-${tokenData.tokenId}.png`); });
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
  if (e.keyCode>=49&&e.keyCode<=56) tmult=1+e.keyCode-49; //1-8
  if (e.keyCode==77) anim=!anim; //m = anim/!anim
  if (e.keyCode==88) dzc-=0.03; //x = zoom in
  if (e.keyCode==90) dzc=Math.min(0,dzc+0.03); //z = zoom out
  if (e.keyCode==70) { f1=(f1+1)%3; resize_render(); } // f
  if (e.keyCode==80) { savescr=1; Lx = C.width; Ly = C.height; } //p = print screen
  return false;
}
document.body.style.cursor = "none";

function handler(e) {
  if (running) {
    var scroll = (e.deltaY || -1*e.wheelDelta || 10*e.detail);
    var isTouchPad = e.wheelDeltaY ? e.wheelDeltaY === -3 * e.deltaY : e.deltaMode === 0;
    dzc=Math.min(0,dzc+.5*Math.max(-0.1,Math.min(0.1,scroll/Ly*2*(1+3*isTouchPad))));
  }
    e.stopPropagation();
    e.preventDefault();
    return false;
}
gl.canvas.addEventListener("mousewheel", handler, false);
gl.canvas.addEventListener("DOMMouseScroll", handler, false);

const delta = 6;
let startx;
let starty;
let startdist=0;
let mousedown=0;
let mousex=.5;
let mousey=.5;

function handler_down(e) {
  if (running) {
    mousedown=1;
    startx = (e.clientX || (e.touches && e.touches[0].clientX));
    starty = (e.clientY || (e.touches && e.touches[0].clientY));
    if (e.touches && e.touches.length === 2) {
      e.preventDefault();
      startx = startx/2 + e.touches[1].clientX / 2;
      starty = starty/2 + e.touches[1].clientY / 2;
      startdist = Math.sqrt((e.touches[0].clientX-e.touches[1].clientX)**2+(e.touches[0].clientY-e.touches[1].clientY)**2);
    }
  }
}
gl.canvas.addEventListener("mousedown", handler_down, false);
gl.canvas.addEventListener("touchstart", handler_down, false);

function handler_move(e) {
  mousex = e.clientX/Lx*2;
  mousey = 1-e.clientY/Ly*2;
  if (running && mousedown) {
    const sx = (e.clientX || (e.touches && e.touches[0].clientX));
    const sy = (e.clientY || (e.touches && e.touches[0].clientY));
    e.preventDefault();
    if (e.touches && e.touches.length === 2) {
      e.preventDefault(); // Prevent page scroll
      let scale = 100;
      const deltaDistance = Math.sqrt((e.touches[0].clientX-e.touches[1].clientX)**2+(e.touches[0].clientY-e.touches[1].clientY)**2);
      if (startdist!=0) {
        scale = 100*(1-deltaDistance/startdist);
      }
      dzc=Math.min(0,dzc+.5*Math.max(-0.25,Math.min(0.25,1.3*scale/Ly)));
    } else {
      dxc-=(sx-startx)/Lx*Math.exp(0.2-0.1*dzc);
      dyc+=(sy-starty)/Ly*Math.exp(0.2-0.1*dzc);
      // imposing max(uc.x)<=1, i.e. -xc+zc <= 1, i.e. xc >= zc-1, i.e. dxc >= zc-1-xc
      // imposing min(uc.x)>=0, i.e. -xc    >= 0, i.e. xc <= 0, i.e. dxc <= -xc
      dxc=Math.max(-1-xc+zc,Math.min(-xc,dxc));
      dyc=Math.max(-1-yc+zc,Math.min(-yc,dyc));
      startx = sx;starty = sy;
    }
  }
}
gl.canvas.addEventListener("mousemove", handler_move, false);
gl.canvas.addEventListener("touchmove", handler_move, false);
gl.canvas.addEventListener('ondragstart', function (e) { e.preventDefault(); return false; });
gl.canvas.addEventListener('mouseleave', function (e) {  mousedown=0; });
gl.canvas.addEventListener('mouseup', function (e) {  mousedown=0; });
gl.canvas.addEventListener('touchend', function (e) {  mousedown=0; });
gl.canvas.addEventListener('dblclick', function (e) {  running = !running; });

resize_render();
