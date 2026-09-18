let time;
let posn11=[];let posn12=[]; let posn21=[]; let posn22=[];
let mg1,mg2;
let eWH;let w1,w2;
let cvGWH;let cvPWH;let ecvp=.1;
let oWm=150;let sa;let r1,r2;let ESC;
let trcA;let XtrcA;let trcD;let XtrcD;let initmsA;let duradaA=20;let initmsO;let duradaO=20;
let clrs=[];
let ptt=[["#102C42","#144251","#164B5B","#2C7063","#DDD0A3"],["#FFEDBF","#F7803C","#F54828","#2E0D23","#F8E4C1"],["#212C32","#496C7F","#B4C1B7","#ECE1C5","#F0D2AE"],["#FFFFFF","#2D1E94","#190D69","#0A0241","#06022E"],["#CBDCEE","#CEFF9D","#E6FC51","#FBDD25","#000000"],["#2E2833","#C96E4D","#E68F3D","#D5B06F","#8DC5B5"],["#00B7FF","#000000","#FFFFFF","#E4E4E4","#00435E"],["#127965","#F7E229","#FBF1CC","#FACF6E","#FE6421"]];
let ptt2=[["#b16040","#cda461","#2c7063","#164b5b","#b16040"],["#086d83","#38b2ba","#FFEDBF","#f54828","#2e0d23"],["#b8b2a0","#6f4621","#c89261","#4d5d68","#b8b2a0"],["#b4c15c","#d6ee27","#82b401","#10046f","#3d22fb"],["#032351","#cbdcee","#1b209d","#151f2c","#ceff9d"],["#076353","#5f9d82","#481546","#593678","#9b461a"],["#e41679","#ff055e","#1b2843","#e4e4e4","#e43d05"],["#01225e","#040fa3","#fd423d","#fbf1cc","#ec1544"]];
let nptt;let llv;let blb;let cs;let R;let fl;
setup=()=>{
R=new Random();
mF=Math.floor;mC=Math.cos;mS=Math.sin;cg=createGraphics;mX=Math.max;mN=Math.min;cv=createVector;
let llenc = createCanvas(eWH=1500,eWH);
llenc.id("llenc");
document.getElementById('llenc').style.imageRendering = "crisp-edges"
pixelDensity(1);noCursor();frameRate(20);

ESC=1;time=0;trcA=.0;trcD=.0;cs=[];
mg1=mF(eWH*.55);mg2=mF(eWH*.7);pd=pixelDensity();
oWH=(mN(windowWidth,windowHeight))/pd
resizeCanvas(oWH,oWH);
llv=R.random_num(0,4294967295);
nptt=mF(R.random_num(0,8));
for(var i=0;i<8;i++) clrs[i]=ptt[nptt][i];
gs=oWH/eWH;sa=mF(eWH/oWm);

cvGWH=mF(eWH);cvPWH=mF(ecvp*eWH);
pgf=cg(eWH,eWH);pgb=cg(eWH,eWH);pgbl=cg(eWH,eWH);pgp=cg(eWH,eWH);pgal=cg(eWH,eWH);pga=cg(eWH,eWH);pgo=cg(eWH,eWH);
pgb.blendMode(DIFFERENCE);pgbl.blendMode(DIFFERENCE);pgb.noStroke();

pgbn1=cg(cvGWH,cvGWH);pgbn2=cg(cvGWH,cvGWH);pgbnMix=cg(cvGWH,cvGWH);
pgbnMix.blendMode(ADD);blb=new BlobDetection(cvGWH,cvGWH);
pgbn1.stroke(0);pgbn1.strokeWeight(2);pgbn1.fill(128);pgbn2.stroke(0);pgbn2.strokeWeight(2);pgbn2.fill(128);

pgfbn1=cg(cvPWH,cvPWH);pgfbn2=cg(cvPWH,cvPWH);pgfbnMix=cg(cvPWH,cvPWH);pgfbnMixTh=cg(cvPWH,cvPWH);pgfbnMixTh2=cg(cvPWH,cvPWH);	
pgfbn1.scale(ecvp);pgfbn2.scale(ecvp);pgfbnMix.blendMode(ADD);pgfbn1.noStroke();pgfbn1.fill(128);pgfbn2.noStroke();pgfbn2.fill(128);

noiseSeed(llv);
XtrcA=mF(R.random_num(12,17));XtrcD=mF(R.random_num(328,438));if(R.random_dec()<.5) XtrcA=-XtrcA;if(R.random_dec()<.5) XtrcD=-XtrcD;
r1=mF(R.random_num(8,15));r2=mF(R.random_num(10,17));
lfr=R.random_dec();fl=0;if(lfr>0.6)fl=1;if(lfr>0.8)fl=2;if(lfr>0.92)fl=3;

let u=2.;let k=2.;let s=2.;
pgf.clear();pgf.background(0);let c2=color(clrs[2]);c2.setAlpha(45);pgf.fill(c2);pgf.noStroke();
for(i=0;i<200000;i++){u=R.random_dec()*eWH;k=R.random_dec()*eWH;s=noise(u*.01,k*.01,8)*eWH*.002;pgf.rect(u,k,s,s);}
cleL(pgal,eWH*.8,eWH*.2,98);
pgo.clear();for(i=0;i<R.random_num(18,36);i++) cleA(pgo,R.random_dec()*eWH,R.random_dec()*eWH,R.random_num(8,16),mF(5.*R.random_dec()));
pga.clear();cleT(pga,eWH*.8,eWH*.2,98);
}

draw=()=>{
push();scale(gs,gs);
if(ESC==1){
time +=.01;
creaOna();pgb.clear();ona1(pgb,1);ona2(pgb,1);pgfbn1.clear();ona1(pgfbn1,2);pgfbn2.clear();ona2(pgfbn2,2);

pgfbnMix.clear();pgfbnMix.background(0);pgfbnMix.image(pgfbn1,0,0);pgfbnMix.image(pgfbn2,0,0);
pgfbnMixTh.copy(pgfbnMix, 0,0,cvPWH,cvPWH, 0,0,cvPWH,cvPWH);pgfbnMixTh.filter(THRESHOLD,.8);
pgfbnMixTh2.copy(pgfbnMix, 0,0,cvPWH,cvPWH, 0,0,cvPWH,cvPWH);pgfbnMixTh2.filter(THRESHOLD,.1);

bw1=false;w1=0;
for(let i=0;i<cvPWH;i+=3){for(let j=0;j<cvPWH;j+=3){let bright=brightness(pgfbnMixTh.get(i,j));if(bright>10) w1++;}}
if(w1>90)bw1=true;w2=0;
if(bw1){for(let i=0;i<cvPWH;i+=3){for(let j=0;j<cvPWH;j+=3){let bright=brightness(pgfbnMixTh2.get(i,j));if(bright>10) w2++;}}}
if((w2>920)&&bw1) ESC=2;
if(fl==0)image(pgf,0,0);image(pgb,0,0);image(pga,0,0);image(pgo,0,0);
if(fl==1){push();scale(-1,1);image(pgf,-eWH,0);image(pgb,-eWH,0);image(pga,-eWH,0);image(pgo,-eWH,0);pop();}
if(fl==2){push();scale(1,-1);image(pgf,0,-eWH);image(pgb,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
if(fl==3){push();rotate(radians(90));image(pgf,0,-eWH);image(pgb,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
}
if(ESC==2){
pgbn1.clear();ona1(pgbn1,2);pgbn2.clear();ona2(pgbn2,2);
pgbnMix.clear();pgbnMix.background(0);pgbnMix.image(pgbn1,0,0);pgbnMix.image(pgbn2,0,0);
pgbnMix.filter(THRESHOLD,.95);pgbnMix.loadPixels();
blb.computeBlobs(pgbnMix.pixels);
let nn=0;
for(let n=0;n<blb.getBlobNb();n++){b=blb.getBlob(n);
if(b){let bw=(b.xMax-b.xMin)*eWH;let bh=(b.yMax-b.yMin)*eWH;if(bw>70 && bh>70){let punts=[];let rp=mF(mX(bw,bh)*.02);
for(let i=0;i<rp;i++) cs.push(new Crtll(nn,b.xMin*eWH,b.yMin*eWH,R.random_num(8,11),R.random_num(4,6),true,punts));nn++;}
else{if(bw>10 && bh>10){let punts=[];for(let m=0;m<=b.getEdgeNb();m++){eA=b.getEdgeVertexA(m);eB=b.getEdgeVertexB(m);if(eA && eB) punts.push(createVector((eA.x-b.xMin)*eWH,(eA.y-b.yMin)*eWH));}
cs.push(new Crtll(nn,b.xMin*eWH,b.yMin*eWH,bw,bh,false,punts));nn++;}}}
}
var ord=cs.sort((a,b)=>b.area-a.area);cs=[];
for(let i=0;i<ord.length;i++){cs.push(new Crtll(ord[i].id,ord[i].x,ord[i].y,ord[i].w,ord[i].h,ord[i].esD,ord[i].shape));}
document.getElementById('llenc').style.imageRendering = "auto"
ESC=3;
}
if(ESC==3){pgbl.clear();ona1(pgbl,4);ona2(pgbl,4);ona1(pgbl,5);ona2(pgbl,5);ESC=4;}
if(ESC==4){
let lf=0;
pgp.clear();cs.forEach(c=>{c.update();c.d();if(c.vida<99)lf++;});
if(fl==0)image(pgf,0,0);image(pgb,0,0);image(pgp,0,0);image(pga,0,0);image(pgo,0,0);
if(fl==1){push();scale(-1,1);image(pgf,-eWH,0);image(pgb,-eWH,0);image(pgp,-eWH,0);image(pga,-eWH,0);image(pgo,-eWH,0);pop();}
if(fl==2){push();scale(1,-1);image(pgf,0,-eWH);image(pgb,0,-eWH);image(pgp,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
if(fl==3){push();rotate(radians(90));image(pgf,0,-eWH);image(pgb,0,-eWH);image(pgp,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
if(lf>cs.length*.6){ESC=5;initmsA=frameCount;}
}
if(ESC==5){
let ta=map(frameCount-initmsA,0,duradaA,0.,1.);trcA=XtrcA*easeInQuad(ta);
if(ta>=.4){initmsO=frameCount;ESC=6;}
pga.clear();cleT(pga,eWH*.8,eWH*.2,98);
pgb.clear();ona1(pgb,3);ona2(pgb,3);
pgp.clear();cs.forEach(c=>{c.d();});
if(fl==0)image(pgf,0,0);image(pgbl,0,0);image(pgal,0,0);image(pgb,0,0);image(pgp,0,0);image(pga,0,0);image(pgo,0,0);
if(fl==1){push();scale(-1,1);image(pgf,-eWH,0);image(pgbl,-eWH,0);image(pgal,-eWH,0);image(pgb,-eWH,0);image(pgp,-eWH,0);image(pga,-eWH,0);image(pgo,-eWH,0);pop();}
if(fl==2){push();scale(1,-1);image(pgf,0,-eWH);image(pgbl,0,-eWH);image(pgal,0,-eWH);image(pgb,0,-eWH);image(pgp,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
if(fl==3){push();rotate(radians(90));image(pgf,0,-eWH);image(pgbl,0,-eWH);image(pgal,0,-eWH);image(pgb,0,-eWH);image(pgp,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
}
if(ESC==6){
let fia=false;let ta=map(frameCount-initmsA,0,duradaA,0.,1.);
trcA=XtrcA*easeInQuad(ta);
if(ta>=1.){trcA=XtrcA;fia=true;}
let fiO=false;let tO=map(frameCount-initmsO,0,duradaO,0.,1.);
trcD=XtrcD*easeInQuad(tO);
if(tO>=1.){trcD=XtrcD;fiO=true;}
pga.clear();cleT(pga,eWH*.8,eWH*.2,98);
pgb.clear();ona1(pgb,3);ona2(pgb,3);
pgp.clear();cs.forEach(c=>{c.d();});
if(fl==0)image(pgf,0,0);image(pgbl,0,0);image(pgal,0,0);image(pgb,0,0);image(pgp,0,0);image(pga,0,0);image(pgo,0,0);
if(fl==1){push();scale(-1,1);image(pgf,-eWH,0);image(pgbl,-eWH,0);image(pgal,-eWH,0);image(pgb,-eWH,0);image(pgp,-eWH,0);image(pga,-eWH,0);image(pgo,-eWH,0);pop();}
if(fl==2){push();scale(1,-1);image(pgf,0,-eWH);image(pgbl,0,-eWH);image(pgal,0,-eWH);image(pgb,0,-eWH);image(pgp,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
if(fl==3){push();rotate(radians(90));image(pgf,0,-eWH);image(pgbl,0,-eWH);image(pgal,0,-eWH);image(pgb,0,-eWH);image(pgp,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
if(fia&&fiO) ESC=7;
}
if(ESC==7){
pgp.drawingContext.shadowOffsetX=3;pgp.drawingContext.shadowOffsetY=3;pgp.drawingContext.shadowBlur=9;
pgp.clear();cs.forEach(c=>{c.d();});
if(fl==0)image(pgf,0,0);image(pgbl,0,0);image(pgal,0,0);image(pgb,0,0);image(pgp,0,0);image(pga,0,0);image(pgo,0,0);
if(fl==1){push();scale(-1,1);image(pgf,-eWH,0);image(pgbl,-eWH,0);image(pgal,-eWH,0);image(pgb,-eWH,0);image(pgp,-eWH,0);image(pga,-eWH,0);image(pgo,-eWH,0);pop();}
if(fl==2){push();scale(1,-1);image(pgf,0,-eWH);image(pgbl,0,-eWH);image(pgal,0,-eWH);image(pgb,0,-eWH);image(pgp,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
if(fl==3){push();rotate(radians(90));image(pgf,0,-eWH);image(pgbl,0,-eWH);image(pgal,0,-eWH);image(pgb,0,-eWH);image(pgp,0,-eWH);image(pga,0,-eWH);image(pgo,0,-eWH);pop();}
noLoop();
}
pop();
}

creaOna=()=>{
noiseSeed(llv);
randomSeed(llv);
let v1=random(.002)*random(1);let v2=1.3*random(.002)*random(1);let ds1=time*random(-1,1);let ds2=time*random(-1,1);let a1=1.0;let a2=.8;
for(var r=0;r<r1;r++){
posn11[r]=[];posn12[r]=[];var p=0;
for(var i=-mg1;i<mg1;i+=sa){
let dy1=noise(ds1+i*v1,2.88,0);let dy2=noise(ds1+i*v1,2.87,0);let a=noise(ds2+i*v2,2.89);dy1=(dy1-a)*a1*3000;dy2=(dy2-a)*a2*3000;yy=288*mS(i*.005);
posn11[r][p]=cv(i,yy+dy1);posn12[r][p]=cv(i,yy+dy2);p++;
}a1 -=.15;a2 -=.1;
}
v1=v2=random(.002)*random(1);ds1=time*random(-1,1);ds2=time*random(-1,1);a1=1.0;a2=.8;
for(var r=0;r<r2;r++){
posn21[r]=[];posn22[r]=[];var p=0;
for(var i=-mg2; i<mg2; i+=sa){
let dy1=noise(ds1+i*v1,3,0);let dy2=noise(ds1+i*v1,3,0);let a=noise(ds2+i*v2,3);dy1=(dy1-a)*a1*2888;dy2=(dy2-a)*a2*2889;yy=277*mS(i*.005);
posn21[r][p]=cv(i, yy+dy1);posn22[r][p]=cv(i, yy+dy2);p++;
}a1 -=.14;a2 -=.095;
}
}
ona1=(pg,t)=>{
for(var r=0;r<r1;r++){
pg.push();pg.translate(eWH*.5,eWH*.5);
if((t==1)||(t==3)){let cc=clrs[(r+2)%5];pg.fill(cc);}
if(t==4){pg.noStroke();let cf=color(clrs[(r+2)%5]);cf.setAlpha(30);pg.fill(cf);}
if(t==5){let cs=clrs[(r+2)%5];pg.stroke(cs);pg.noFill();pg.strokeWeight(1);pg.drawingContext.setLineDash([4,7]);}
pg.beginShape();
for(var i=0;i<posn11[r].length;i++){
if(t==3){let p=torca(posn11[r][i].x, posn11[r][i].y);pg.curveVertex(p.x,p.y);}
else pg.curveVertex(posn11[r][i].x,posn11[r][i].y);
}
let l=posn12[r].length;
for(var i=0;i<l;i++){
if(t==3){let p=torca(posn12[r][(l-i)-1].x,posn12[r][(l-i)-1].y);pg.curveVertex(p.x,p.y);}
else pg.curveVertex(posn12[r][(l-i)-1].x,posn12[r][(l-i)-1].y);
}
pg.endShape(CLOSE);
pg.pop();
}
}
ona2=(pg,t)=>{
for(var r=0;r<r2;r++){
pg.push();pg.translate(eWH*.5,eWH*.5);pg.rotate(radians(38));
if((t==1)||(t==3)){let cc=clrs[r%5];pg.fill(cc);}
if(t==4){pg.noStroke();let cf=color(clrs[r%5]);cf.setAlpha(30);pg.fill(cf);}
if(t==5){let cs=clrs[r%5];pg.stroke(cs);pg.noFill();pg.strokeWeight(1);pg.drawingContext.setLineDash([4,7]);}
pg.beginShape();
for(var i=0;i<posn21[r].length;i++){
if(t==3){let p=torca(posn21[r][i].x,posn21[r][i].y);pg.curveVertex(p.x,p.y);}
else pg.curveVertex(posn21[r][i].x,posn21[r][i].y);
}
let l=posn22[r].length;
for(var i=0;i<l;i++){
if(t==3){let p=torca(posn22[r][l-i-1].x,posn22[r][l-i-1].y);pg.curveVertex(p.x,p.y);}
else pg.curveVertex(posn22[r][l-i-1].x,posn22[r][l-i-1].y);
}
pg.endShape(CLOSE);
pg.pop();
}
}
class Crtll{
constructor(id,x,y,sw,sh,bd,p) {
this.id=id;
if(R.random_dec()<.5) this.cf=ptt2[nptt][(this.id)%5]
else this.cf=ptt[nptt][(this.id)%5]
this.x=x;this.y=y;this.vx=R.random_num(-23, 23);this.vy=R.random_num(-23, 23);
this.vida=R.random_num(200,350);this.vida0=this.vida;
this.w=sw;this.h=sh;this.area=sw*sh;this.gir0=R.random_num(-45,45);this.gir=0;
this.esD=bd;this.shape=[];if(!bd){for(let i=0;i<p.length;i++) this.shape[i]=p[i].copy();}
}
d(){
pgp.drawingContext.shadowColor=color(this.cf);
pgp.noStroke();pgp.fill(this.cf);  
pgp.push();
pgp.translate(this.x,this.y);pgp.rotate(radians(this.gir));
if(this.esD){pgp.beginShape();pgp.vertex(-this.w,0);pgp.vertex(0,-this.h);pgp.vertex(this.w,0);pgp.vertex(0,this.h);pgp.endShape(CLOSE);}
else{pgp.beginShape();for(let i=0;i<this.shape.length;i+=4)pgp.curveVertex(this.shape[i].x, this.shape[i].y);pgp.endShape();}
pgp.pop();
}
update(){if(this.vida>0){let a=map(this.vida,this.vida0,0, 1.,0.);this.vx *= easeInOutSine(a);this.vy *= easeInOutSine(a);if(this.vida>this.vida0*.7) this.gir=this.gir0+a*60;this.x += this.vx;this.y += this.vy;this.vida -=3;}}
}

torca=(x,y)=>{let magicn=.001;let ang=noise(magicn*x,magicn*y)*trcA;let df=noise(magicn*x,magicn*y)*trcD;return createVector(x+mC(ang)*df,y+mS(ang)*df);}

cleT=(pg, x, y, s)=>{let cc = color(ptt2[nptt][0]);cc.setAlpha(10);pg.fill(cc);pg.noStroke();
for(i=0;i<s;i+=3){let d = map(i,0,s,s,s*2.8);cleO(pg,d,6,x,y);}pg.fill(ptt2[nptt][1]);cleO(pg,s,11,x,y);pg.fill(ptt2[nptt][2]);cleO(pg,s*.68,14,x,y);pg.fill(ptt2[nptt][3]);cleO(pg,s*.45,18,x,y);pg.fill(ptt2[nptt][4]);cleO(pg,s*.18,23,x,y);
}
cleO=(pgt,m,st,x,y)=>{pgt.beginShape();for(let i=0;i<360;i+=st){let xx=x+m*.5*mC(radians(i));let yy=y+m*.5*mS(radians(i));let p=torca(xx, yy);pgt.curveVertex(p.x, p.y);}pgt.endShape(CLOSE);}
cleA=(pg,x,y,s,ic)=>{let cc=color(clrs[ic]);cc.setAlpha(20);pg.fill(cc);pg.noStroke();for(i=0;i<s;i+=3){let d=map(i,0,s,s,s*2.8);pg.circle(x,y,d);}cc.setAlpha(255);pg.fill(cc);pg.circle(x,y,s);pg.fill(clrs[(ic+2)%5]);pg.circle(x,y,s*.68);pg.fill(clrs[(ic+3)%5]);pg.circle(x,y,s*.45);pg.fill(clrs[(ic+6)%5]);pg.circle(x,y,s*.18);}
cleL=(pg,x,y,s)=>{pg.noFill();pg.strokeWeight(2);pg.stroke(ptt2[nptt][0]);pg.drawingContext.setLineDash([5,7]);pg.circle(x,y,s*2.8);pg.stroke(ptt2[nptt][1]);pg.circle(x,y,s);pg.stroke(ptt2[nptt][2]);pg.circle(x,y,s*.68);pg.stroke(ptt2[nptt][3]);pg.circle(x,y,s*.45);pg.stroke(ptt2[nptt][4]);pg.circle(x,y,s*.18);pg.drawingContext = [];}
easeInOutSine=(x)=>{return -(mC(Math.PI*x)-1)*.5;}
easeInQuad=(x)=>{return x*x;}

class Random{
constructor(){
this.useA=false;let sfc32=function(uint128Hex){
let a=parseInt(uint128Hex.substring(0,8),16);let b=parseInt(uint128Hex.substring(8,16),16);let c=parseInt(uint128Hex.substring(16,24),16);let d=parseInt(uint128Hex.substring(24,32),16);
return function(){a |= 0;b |= 0;c |= 0;d |= 0;
let t=(((a+b)|0)+d)|0;d=(d+1)|0;a=b^(b>>>9);b=(c+(c<<3))|0;c=(c<<21)|(c>>>11);c=(c+t)|0;
return (t>>>0)/4294967296;};
};
this.prngA=new sfc32(tokenData.hash.substring(2,34));this.prngB=new sfc32(tokenData.hash.substring(34,66));
for (let i=0;i<1e6;i+=2){this.prngA();this.prngB();}
}
random_dec(){this.useA=!this.useA;return this.useA?this.prngA():this.prngB();}
random_num(a,b){return a+(b-a)*this.random_dec();}
}
const MetaballsTable={
edgeCut:[[-1,-1,-1,-1,-1],[0,3,-1,-1,-1],[0,1,-1,-1,-1],[3,1,-1,-1,-1],[1,2,-1,-1,-1],[1,2,0,3,-1],[0,2,-1,-1,-1],[3,2,-1,-1,-1],[3,2,-1,-1,-1],[0,2,-1,-1,-1],[1,2,0,3,-1],[1,2,-1,-1,-1],[3,1,-1,-1,-1],[0,1,-1,-1,-1],[0,3,-1,-1,-1],[-1,-1,-1,-1,-1]],
edgeOffsetInfo:[[0,0,0],[1,0,1],[0,1,0],[0,0,1]],edgeToCompute:[0,3,1,2,0,3,1,2,2,1,3,0,2,1,3,0],neightborVoxel:[0,10,9,3,5,15,12,6,6,12,12,5,3,9,10,0],
computeNeighborTable:function(){
for (let i=0;i<16;i++){
let n=0,iEdge;this.neightborVoxel[i]=0;
while((iEdge=this.edgeCut[i][n++])!=-1){switch (iEdge){case 0:this.neightborVoxel[i] |= (1<<3);break;case 1:this.neightborVoxel[i] |= (1<<0);break;case 2:this.neightborVoxel[i] |= (1<<2);break;case 3:this.neightborVoxel[i] |= (1<<1);break;}}
}}};

class Metaballs2D{
constructor(isovalue,resx,resy){
this.isovalue=isovalue;this.resx=resx;this.resy=resy;this.stepx=1./(this.resx-1);
this.stepy=1./(this.resy-1);this.nbGridValue=this.resx*this.resy;this.gridValue=Array(this.nbGridValue);this.nbVoxel=this.nbGridValue;this.voxel=Array(this.nbVoxel);this.nbEdgeVrt=2*this.nbVoxel;this.edgeVrt=Array(this.nbEdgeVrt);this.lineToDraw=Array(2*this.nbVoxel);this.nbLineToDraw=0;let n=0,index,x,y;
for(x=0;x<resx;x++)
for(y=0;y<resy;y++){index=2*n;this.voxel[x+this.resx*y]=index;this.edgeVrt[index]=createVector(x*this.stepx,y*this.stepy);this.edgeVrt[index+1]=createVector(x*this.stepx,y*this.stepy);n++;}    
}

computeIsovalue(){}  
computeMesh(){
this.computeIsovalue();let x,y,squareIndex,n;let iEdge;let offx,offy,offAB;
let toCompute;let offset;let t;let vx,vy;let edgeOffsetInfo=[];this.nbLineToDraw=0;vx=0.0;
for(x=0;x<this.resx-1;x++){vy = 0.0;
for(y=0;y<this.resy-1;y++){offset=x+resx*y;squareIndex=getSquareIndex(x,y);n=0;
while((iEdge = MetaballsTable.edgeCut[squareIndex][n++])!=-1){
edgeOffsetInfo = MetaballsTable.edgeOffsetInfo[iEdge];offx=edgeOffsetInfo[0];offy=edgeOffsetInfo[1];offAB=edgeOffsetInfo[2];this.lineToDraw[nbLineToDraw++]=this.voxel[(x+offx)+resx*(y+offy)]+offAB;
}
toCompute=MetaballsTable.edgeToCompute[squareIndex];
if(toCompute>0){
if((toCompute & 1)>0){t=(this.isovalue-this.gridValue[offset])/(this.gridValue[offset+1]-this.gridValue[offset]);this.edgeVrt[this.voxel[offset]].x=vx*(1.0-t)+t*(vx+stepx);}
if((toCompute & 2)>0){t=(this.isovalue-this.gridValue[offset])/(this.gridValue[offset+resx]-this.gridValue[offset]);this.edgeVrt[this.voxel[offset]+1].y=vy*(1.0-t)+t*(vy+stepy);}
}
vy += stepy;}vx += stepx;}
this.nbLineToDraw /= 2;}  
}

class BlobDetection extends Metaballs2D{
static 
static(){}
constructor(resx,resy){
super(0,resx,resy);
this.gridVisited=Array(this.nbGridValue);
this.blob= Array();
for (let i=0;i<5000;i++)
this.blob.push(new Blob(this));
this.blobNumber=0;this.blobWidthMin=0;this.blobHeightMin=0;this.coeff=3.*255.;
}
getBlob(n){if (n<this.blob.length)return this.blob[n];return null;}
setThreshold(value){if(value<0.)value=0.;if(value>1.)value=1.;this.isovalue=value*this.coeff;}  
computeIsovalue(){
let pixel,r,g,b;let x,y;let offset,offsetPix;let coeff=0.;r=0;g=0;b=0;
for(y=0;y<this.resy;y++)
for(x=0;x<this.resx;x++){offset=(x+this.resx*y);offsetPix=4*offset;this.gridValue[offset]=this.pixels[offsetPix]+this.pixels[offsetPix+1]+this.pixels[offsetPix+2];}
}  
computeBlobs(pixels,filter){
this.pixels=pixels;
for(let i=0;i<this.nbGridValue;i++)this.gridVisited[i]=false;
this.computeIsovalue();
let x,y,squareIndex,n;let iEdge;let offx,offy,offAB;let toCompute;let offset;let t;let vx,vy;
this.nbLineToDraw=0;this.blobNumber=0;vx=0.;
for(x=0;x<this.resx-1;x++){vy=0.;
for(y=0;y<this.resy-1;y++){offset=x+this.resx*y;if(this.gridVisited[offset]==true) continue;
squareIndex=this.getSquareIndex(x,y);
if(squareIndex>0 && squareIndex<15){if(this.blobNumber<500){this.findBlob(this.blobNumber,x,y,filter);this.blobNumber++;}}
vy+=this.stepy;}
vx += this.stepx;}
this.nbLineToDraw/=2;this.blobNumber+=1;}
computeEdgeVertex(iBlob,x,y){let offset=x+this.resx*y;if(this.gridVisited[offset]==true) return;
this.gridVisited[offset]=true;let iEdge,offx,offy,offAB;let edgeOffsetInfo=[];let squareIndex=this.getSquareIndex(x,y);let vx=x*this.stepx;let vy=y*this.stepy;let n=0;let blob=this.blob[iBlob];
while((iEdge=MetaballsTable.edgeCut[squareIndex][n++])!=-1){
edgeOffsetInfo =MetaballsTable.edgeOffsetInfo[iEdge];offx=edgeOffsetInfo[0];offy=edgeOffsetInfo[1];offAB=edgeOffsetInfo[2];
if(blob.nbLine<5000)this.lineToDraw[this.nbLineToDraw++]=blob.line[blob.nbLine++]=this.voxel[(x+offx)+this.resx*(y+offy)]+offAB;
else return;}
let toCompute=MetaballsTable.edgeToCompute[squareIndex];
let t=0.;
let value=0.;
if(toCompute>0){
if((toCompute & 1)>0){t=(this.isovalue-this.gridValue[offset])/(this.gridValue[offset+1]-this.gridValue[offset]); 
value=vx*(1.0-t)+t*(vx+this.stepx);this.edgeVrt[this.voxel[offset]].x=value;
if(value<blob.xMin)blob.xMin=value;if(value>blob.xMax)blob.xMax=value;}
if((toCompute & 2)>0){t=(this.isovalue-this.gridValue[offset])/(this.gridValue[offset+this.resx]-this.gridValue[offset]); 
value=vy*(1.0-t)+t*(vy+this.stepy);this.edgeVrt[this.voxel[offset]+1].y=value;
if(value<blob.yMin)blob.yMin=value;if(value>blob.yMax)blob.yMax=value;}
}
let neighborVoxel=MetaballsTable.neightborVoxel[squareIndex];    
if(x<this.resx-2 && (neighborVoxel & (1<<0))>0) this.computeEdgeVertex(iBlob,x+1,y);
if(x>0 && (neighborVoxel & (1<<1))>0) this.computeEdgeVertex(iBlob,x-1,y);
if(y<this.resy-2 && (neighborVoxel & (1<<2))>0) this.computeEdgeVertex(iBlob,x,y+1);
if(y>0 && (neighborVoxel & (1<<3))>0) this.computeEdgeVertex(iBlob,x,y-1);
}
findBlob(iBlob,x,y,filter){
let blob=this.blob[iBlob];blob.id=iBlob;blob.xMin=Infinity;blob.xMax=-Infinity;blob.yMin=Infinity;blob.yMax=-Infinity;blob.nbLine=0;
this.computeEdgeVertex(iBlob,x,y);{
if(blob.xMin>=Infinity || blob.xMax<=-Infinity || blob.yMin>=Infinity || blob.yMax<=-Infinity)this.blobNumber--;    
else blob.update();}
}  
getSquareIndex(x,y){
let squareIndex=0;let offy=this.resx*y;let offy1=this.resx*(y+1);
if(this.posDiscrimination==false){if(this.gridValue[x+offy]<this.isovalue)squareIndex |= 1;if(this.gridValue[x+1+offy]<this.isovalue)squareIndex |= 2;if(this.gridValue[x+1+offy1]<this.isovalue)squareIndex |= 4;if(this.gridValue[x+offy1]<this.isovalue)squareIndex |= 8;}
else{if(this.gridValue[x+offy]>this.isovalue)squareIndex |= 1;if(this.gridValue[x+1+offy]>this.isovalue)squareIndex |= 2;if(this.gridValue[x+1+offy1]>this.isovalue)squareIndex |= 4;if(this.gridValue[x+offy1]>this.isovalue)squareIndex |= 8;}
return squareIndex;}
getEdgeVertex(index){return this.edgeVrt[index];}  
getBlobNb(){return this.blobNumber;}
}

class Blob{
constructor(parent){this.parent=parent;this.pos=createVector();this.dim=createVector();this.line=Array(5000);this.xMin=this.xMax=this.yMin=this.yMax=0;}
getEdgeVertexA(iEdge){
if(iEdge*2<this.parent.nbLineToDraw*2)
return this.parent.getEdgeVertex(this.line[iEdge*2]);
return null;}
getEdgeVertexB(iEdge){
if((iEdge*2+1)<this.parent.nbLineToDraw*2)
return this.parent.getEdgeVertex(this.line[iEdge*2+1]);
return null;}    
getEdgeNb(){return this.nbLine;}
update(){this.dim.set(this.xMax-this.xMin,this.yMax-this.yMin);this.pos.set(0.5*(this.xMax+this.xMin),0.5*(this.yMax+this.yMin));this.nbLine /= 2;}
}