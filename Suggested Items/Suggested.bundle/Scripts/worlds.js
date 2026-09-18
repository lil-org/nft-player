// WORLDS - DECEMBER 8, 2021 - Kenny Vaden (c) License: CC-BY-NC-SA
p5.disableFriendlyErrors=true;

class Random {
  constructor() {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substr(0, 8, 16));
      let b = parseInt(uint128Hex.substr(8, 8, 16));
      let c = parseInt(uint128Hex.substr(16, 8, 16));
      let d = parseInt(uint128Hex.substr(24, 8, 16));
      return function () {
        a |= 0; b |= 0; c |= 0; d |= 0;
        var t = (((a + b) | 0) + d) | 0;
        d = (d + 1) | 0;
        a = b ^ (b >>> 9);
        b = (c + (c << 3)) | 0;
        c = (c << 21) | (c >>> 11);
        c = (c + t) | 0;
        return (t >>> 0) / 4294967296;
      };
    };
    this.prngA = new sfc32(tokenData.hash.substr(2,32));
    this.prngB = new sfc32(tokenData.hash.substr(34,32));
    for (let i = 0; i < 1e6; i += 2) { this.prngA(); this.prngB(); }
  }
  rnd_dec() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  rnd_num(a,b) { return a+(b-a)*this.rnd_dec(); }
  rnd_int(a,b) { return Math.floor(this.rnd_num(a,b+1)); }
  randVNoRep (numm) {
    for (var arr=[],i=0;i<numm;i++) { arr[i]=i+1; }
    var tm,cr,tp=arr.length;
    if (tp) while(--tp) { cr=this.rnd_int(0,tp); tm=arr[cr]; arr[cr]=arr[tp]; arr[tp]=tm; }
    return arr;
  }
}

function mk2DArr(c,r) {
  let arr=new Array(c);
  for (let i=0; i<arr.length; i++) { arr[i]=new Array(r); }
  return arr;
}

function hxtrgb(hx) {
  let hxx=hx.replace('#',''),bgi=parseInt(hxx,16);
  return( [(bgi>>16)&255,(bgi>>8)&255,bgi&255] );
}

function rgbthx (rgb) {
  let hx="#"+hex(rgb[0],2)+hex(rgb[1],2)+hex(rgb[2],2); return (hx);
}

function SplineR (pv,np) {
  let ip = new Array(2*pv.length);
  for (let i=0;i<pv.length;i++) { let a=i*2;ip[a]=i+1;let b=a+1;ip[b]=pv[i]; }
  let gg=getCurvePoints(ip),gk=new Array(0.5*gg.length-1);
  for (let i=0; i < gk.length; i++) { gk[i] = gg[(2*i+1)]; }
  let iw = Math.floor(gk.length / np);
  let outpt = new Array(np); for (let i=0; i < np; i++) { outpt[i] = gk[(i*iw)]; }
  outpt[np] = pv[pv.length-1]; outpt[0] = pv[0]; return outpt;
  // Epistemex (c) 2013-2014	License: MIT
  function getCurvePoints(points,tension,numOfSeg,close) {
    'use strict'; tension=(typeof tension==='number')?tension:0.75;
    numOfSeg = numOfSeg?numOfSeg:250;
    let pts,l=points.length,rPos=0,rLen=(l-2)*numOfSeg+2+(close?2*numOfSeg:0);
    let rs=new Float32Array(rLen),cache=new Float32Array((numOfSeg+2)*4),cachePtr=4;
    pts=points.slice(0);
    if (close) { pts.unshift(points[l-1]); pts.unshift(points[l-2]); pts.push(points[0],points[1]);	}
    else {pts.unshift(points[1]); pts.unshift(points[0]);	pts.push(points[l-2],points[l-1]); }
    cache[0]=1;
    for(let i=0;i<numOfSeg;i++) {
      let st=i/numOfSeg,st2=st*st,st3=st2*st,st23=st3*2,st32=st2*3;
      cache[cachePtr++]=st23-st32+1; cache[cachePtr++]=st32-st23;
      cache[cachePtr++]=st3-2*st2+st; cache[cachePtr++]=st3-st2;
    }
    cache[++cachePtr]=1; parse(pts,cache,l);
    if (close) {
      pts=[];pts.push(points[l-4],points[l-3],points[l-2],points[l-1]);
      pts.push(points[0],points[1],points[2],points[3]);
      parse(pts,cache,4);
    }
    function parse(pts,cache,l) {
      for (let j=2;j<l;j+=2) {
        let pt1=pts[j],pt2=pts[j+1],pt3=pts[j+2],pt4=pts[j+3],
        t1x=(pt3-pts[j-2])*tension,t1y=(pt4-pts[j-1])*tension,
        t2x=(pts[j+4]-pt1)*tension,t2y=(pts[j+5]-pt2)*tension;
        for (let t=0;t<numOfSeg;t++){
          let c=t<<2,c1=cache[c],c2=cache[c+1],c3=cache[c+2],c4=cache[c+3];
          rs[rPos++]=c1*pt1+c2*pt3+c3*t1x+c4*t2x;
          rs[rPos++]=c1*pt2+c2*pt4+c3*t1y+c4*t2y;
        }
      }
    }
    l=close?0:points.length-2,rs[rPos++]=points[l],rs[rPos]=points[l+1];
    return rs;
  }
}

function zspline(fcz,nc,macro) {
  let cl=Array(nc*(fcz.length-1));
  for (let i=0;i<fcz.length-1;i++) {
    for (let j=0;j<nc+1;j++) {
      let awt=(j+1)/nc; if (macro===1) { awt=1-((j+1)/nc); }
      let ak=hxtrgb(fcz[i]),bk=hxtrgb(fcz[i+1]),lst=Array(3);
      for (let k=0;k<3;k++) { lst[k]=Math.round(ak[k]*awt+bk[k]*(1-awt)); }
      cl[(i*nc+j)]=rgbthx(lst);
    }
  }
  cl[0]=fcz[0]; cl[cl.length-1]=fcz[fcz.length-1];
  let kl=new Array(nc); for (let j=0;j<nc;j++) { kl[j]=cl[j*(fcz.length-1)];}
  kl[0]=cl[0]; kl[kl.length-1]=cl[cl.length-1];
  return kl;
}

function HSM (Mtx,cols,rows,Nits) {
  for (let k=0;k<Nits;k++) {
    for (let j=0;j<rows;j++) {
      for (let g=1;g<cols;g++) { Mtx[g][j]=Mtx[g-1][j]*.3 + Mtx[g][j]*.7; }
      for (let i=0;i<(cols-1);i++) { Mtx[i][j]=Mtx[i+1][j]*.3+Mtx[i][j]*.7; }
    }
  }
  return Mtx;
}

function VSM (Mtx,cols,rows,Nits) {
  for (let k=0;k<Nits;k++) {
    for (let i=0;i<cols;i++) {
      for (let g=1;g<rows;g++) { Mtx[i][g]=Mtx[i][g-1]*.3+Mtx[i][g]*.7; }
      for (let j=0;j<rows-1;j++) { Mtx[i][j]=Mtx[i][j+1]*.3+Mtx[i][j]*.7; }
    }
  }
  return Mtx;
}

function getCol(matrix,col) {
  let kll=[]; for (let i=0;i<matrix.length;i++) { kll.push(matrix[col][i]); }
  return kll;
}

let R,SQ;
R = new Random();
function precalcs () {
  let SQB=[],KLR=[],STW=[],RTS=[],XV=[],YV=[];
  let randC=R.rnd_int(1,100);
  let ftx=R.rnd_num(.4,.6), bdraw=R.rnd_int(60,90), klmt=R.rnd_int(7,20);
  let fcz=[],bgc=0,lsc=0,rs=0,spd=0,xr=0,yr=0,ncirc=0,nsq=0;
  if (randC===1) { // GHOST
    fcz=[rgbthx(color(240)),rgbthx(color(250)),rgbthx(color(255))];
    bgc="#d50909",ccr="#000000",ftx=1,klmt=0,bdraw=1;
  }
  if (randC===2) { // SAV
    fcz=["#4555a3","#3351b3","#286d5b","#37ab6e","#fe723d","#fe723d","#c77e6d"];
    bgc="#0587d3",ccr="#fffef4",ftx=R.rnd_num(.75,.85),bdraw=R.rnd_int(60,80);
  }
  if (randC===3) { // BLEACHED
    fcz=["#ffcfcf","#ffe0a8","#ffffb4","#8fa99b","#b0b0ec"];
    bgc="#FFFFFF",ccr="#000000",ftx=R.rnd_num(.65,.85),bdraw=R.rnd_int(60,75);
  }
  if ((randC>3)&&(randC<=6)) { // WESTERN
    fcz=["#503D2E","#314c6a","#058789","#D54B1A","#E3A72F","#F0ECC9"];
    bgc="#FFFFFF",ccr="#000000",ftx=R.rnd_num(.65,.8),bdraw=R.rnd_int(50,75);
  }
  if ((randC>6)&&(randC<=9)) { // FLORO
    fcz=["#4762ff","#4762ff","#ff3574","#ff5950","#f1b700","#aaff00","#00aaff","#6b3eff","#6b3eff"];
    bgc="#c000e8",ccr="#000000",ftx=R.rnd_num(.75,.85),bdraw=R.rnd_int(60,80);
  }
  if ((randC>9)&&(randC<=12)) { // SANDSTONE
    fcz=["#595643","#4E6B66","#ED834E","#EBCC6E","#EBE1C5"];
    bgc="#FFFEDF",ccr="#000000",ftx=R.rnd_num(.6,.9),bdraw=R.rnd_int(40,80);
  }
  if ((randC>12)&&(randC<=15)) { // TAN
    fcz=["#3E4147","#FFFEDF","#DFBA69","#5A2E2E","#2A2C31"];
    bgc="#EFEECC",ccr="#000000",ftx=R.rnd_num(.6,.9),bdraw=R.rnd_int(40,80);
  }
  if ((randC>15)&&(randC<=18)) { // REDRUM
    fcz=["#ECD078","#D95B43","#C02942","#542437","#53777A"]; klmt=0;
    bgc="#AC2005",ccr="#000000",ftx=R.rnd_num(.65,.9),bdraw=R.rnd_int(60,80);
  }
  if ((randC>18)&&(randC<=22)) { // WAVES
    fcz=["#FFFEDF","#FFFEDF","#BCC499","#92A68A","#7B8F8A","#506266","#354336"];
    bgc="#F5DD9D",ccr="#000000",ftx=R.rnd_num(.55,.75),bdraw=R.rnd_int(10,30);
  }
  if ((randC>22)&&(randC<=27)) { // BLUE
    fcz=["#44749D","#C6D4E1","#FFFFFF","#EBE7E0","#BDB8AD"];klmt = R.rnd_int(15,20);
    bgc="#314c6a",ccr="#000000",ftx=R.rnd_num(.25,.35),bdraw=R.rnd_int(60,90);
  }
  if ((randC>27)&&(randC<=31)) { // MALBEC
    fcz=["#C60052","#FF714B","#ACFFE9","#ACFFE9"];klmt = R.rnd_int(10,20);
    bgc="#540045",ccr="#280904",ftx=R.rnd_num(.75,.95),bdraw=R.rnd_int(50,70);
  }
  if ((randC>31)&&(randC<=50)) { // DESERT
    fcz=["#84B295","#ECCF8D","#BB8138","#AC2005","#2C1507"];
    bgc="#2F4F4FFF",ccr="#000000",ftx=R.rnd_num(.6,.9),bdraw=R.rnd_int(40,80);
  }
  if ((randC>50)&&(randC<=62)) { // NIGHTSWIM
    fcz=["#F2B118","#9EB2DA","#797EA2","#7783B2","#525C76","#485773","#2C1507","#211709"];
    bgc="#000000",ccr="#F2B118",ftx=R.rnd_num(.6,.7),bdraw=R.rnd_int(60,80);
  }
  if ((randC>62)&&(randC<=77)) { // HCD
    fcz=["#ecd891","#828751","#354336","#39579d","#82a2d5","#bccbe0"];
    bgc="#F2B118",ccr="#000000",ftx=R.rnd_num(.65,.9),bdraw = R.rnd_int(40,70);
  }
  if ((randC>77)&&(randC<=84)) { // KIAWAH
    fcz=["#314c6a","#84aace","#888984","#e2e4e3","#96826a"], klmt=R.rnd_int(5,8);
    bgc="#344f6d",ccr="#fe833a",ftx=R.rnd_num(.55,.75),bdraw = R.rnd_int(30,60);
  }
  if ((randC>84)&&(randC<=90)) { // OG(OldGuitarist)
    fcz=["#2d4762","#357d8b","#276574","#bacfbc","#7d5a3e","#a98a53"],klmt=10;
    bgc="#1e374d",ccr="#b2beba",ftx=R.rnd_num(.7,.85),bdraw=R.rnd_int(35,60);
  }
  if ((randC>90)&&(randC<=95)) { // ARROWBEAR
    fcz=["#2c1a0f","#50311c","#885e36","#b9976c","#d5c0a3"], klmt=0;
    bgc="#f9f6ed",ccr="#251710",ftx=R.rnd_num(.8,.9),bdraw=R.rnd_int(25,50);
  }
  if ((randC>95)&&(randC<=100)) { // FIREFALL
    fcz=["#5e1f1f","#8d130e","#c60d1b","#d78a30","#f4d984"],klmt=R.rnd_int(8,12);
    bgc="#ffb900",ccr="#000000",ftx=R.rnd_num(.65,.72),bdraw=R.rnd_int(60,75);
  }
  let macro=R.rnd_int(0,1),nLn=R.rnd_int(15,16);
  if (macro===1) { nLn=R.rnd_int(20,25); }
  let cols=nLn,rows=nLn,xsm=2+(nLn-11);
  if (macro===1) { xsm=2+(nLn-16) }
  let insc=R.rnd_num(1,10),unsc=R.rnd_num(1,4);
  let fcs=zspline(fcz,100,macro),fc=fcs[1];
  let szdet = Math.min(window.innerWidth,window.innerHeight*2);
  let wd=szdet, ht=szdet*.5, M=wd/4000;
  let crxx=wd*R.rnd_num(.25,.75),cryy=ht*R.rnd_num(.2,.8);
  let crr = ht*R.rnd_num(.65,.95);
  let xsp=1.5*(wd/cols),ysp=1.25*(ht/rows);
  let xgrid=mk2DArr(cols,rows),ygrid=mk2DArr(cols,rows);
  let unz,inz;
  for (let j=0;j<rows;j++) {
    unz = R.rnd_num((-1*unsc),unsc)*xsp;
    for (let i=0;i<cols;i++) {
      inz = R.rnd_num((-1*insc),insc)*xsp;
      xgrid[i][j]=(i-1.5)*xsp+unz+inz;
      ygrid[i][j]=(j-.75)*ysp+R.rnd_num(-0.1,0.1)*ysp;
    }
  }
  xgrid=HSM(xgrid,cols,rows,xsm);
  xgrid=VSM(xgrid,cols,rows,xsm);
  let iws=R.randVNoRep(cols);
  let hk=0,ik=0,nk=0,x1=0,x2=0,y1=0,y2=0,sklr=0;
  for (let iw=0; iw<iws.length; iw++) {
    let ih=iws[iw]-1;
    let xvc=getCol(xgrid,ih),yvc=getCol(ygrid,ih);
    let scf=R.rnd_num(.85,1.10); nk=R.rnd_int(0,2);
    if (macro===1) { nk=R.rnd_int(4,6); }
    let kspc = R.rnd_num(20,150)*M*((ih+1)/(iws.length+1));
    if (R.rnd_int(1,10)>4) {
      let xvt=SplineR(xvc,20),yvt=SplineR(yvc,20);
      if (macro===1) { xvt=SplineR(xvc,60),yvt=SplineR(yvc,60); }
      for (let kk=0;kk<ih+nk;kk++) {
        let sww=M*R.rnd_num(1.5,5);
        sklr = R.rnd_int(1,80);
        sklr=rgbthx([sklr,sklr,sklr,255]);
        if ((klmt!==0)&&(R.rnd_int(1,klmt)===1)) { sklr = '#ffed8b'; }
        for (let j=1; j<yvt.length; j++) {
          lsc=1; let rkk=kk*kspc;
          x1=xvt[j]+rkk;x2=xvt[j-1]+rkk;y1=yvt[j];y2=yvt[j-1];
          if (((x1>0)&&(x1<wd))||((x2>0)&&(x2<wd))) {
            if (((y1>0)&&(y1<ht))||((y2>0)&&(y2<ht))) {
              SQB[hk] = new p5.Vector(lsc,0);
              XV[hk] = new p5.Vector(x1,x2);
              YV[hk] = new p5.Vector(y1,y2);
              KLR[hk] = new p5.Vector(sklr,sklr);
              STW[hk] = new p5.Vector(sww);
              RTS[hk] = new p5.Vector(0,0);
              hk+=1;
            }
          }
        }
      }
    }
    nk=R.rnd_int(2,6);
    let nspln=R.rnd_int(rows,20),pk=nLn*0.4;
    if (macro===1) { nspln=R.rnd_int(rows,24); pk=nLn*0.8; }
    let xvs=SplineR(xvc,nspln);
    let yvs=SplineR(yvc,nspln);
    let rws=R.randVNoRep(yvs.length-1);
    kspc=R.rnd_num(-200,200)*M;
    let jj,xq,yq,mm,rxx,ryy,rr;
    let clim=30; if (macro===1) { clim=60; }
    let sqlim=700; if (macro===1) { sqlim=2750; }
    let xlw=-.05*wd,xup=wd*1.05,ylw=-.05*ht,yup=ht*1.05;
    for (let hh=0;hh<yvs.length-1;hh++) {
      let jj=rws[hh];
      x1=xvs[jj],x2=xvs[jj-1],y1=yvs[jj],y2=yvs[jj-1];
      let dst=dist(x1,y1,x2,y2);
      for (let kk=0;kk<nk;kk++) {
        let rtst=R.rnd_int(1,100);
        let spwt=(nspln/R.rnd_int(80,100));
        let rkk=kk*spwt*dst*2;
        let lny=R.rnd_num(1.4,1.9);
        let sww=M*R.rnd_num(1.85,2.25)*lny;
        let tex=round(ftx*R.rnd_int(230,254))+1;
        let plthrsh=4; if (macro===1) { plthrsh=0; }
        if ((rtst >= 4)&&(R.rnd_int(1,10)>plthrsh)&&(nsq<sqlim)) {
          lsc=2;
          ik=Math.round(R.rnd_num((-.9*pk),(.9*pk))+99*(ih/cols));
          while (ik<1||ik>99) { ik=Math.round(R.rnd_num((-.9*pk),(.9*pk))+99*(ih/cols)); }
          ryy = R.rnd_num(.90,1.75)*dst*scf;
          rxx = spwt*ryy*R.rnd_num(.5,.75);
          xq=rkk+(x1+x2)*.5+R.rnd_num(0,.2*dst);
          yq=(y1+y2)*.5+R.rnd_num(0,.2*dst);
          mm=atan2((x2-x1),(y1-y2));
          if (R.rnd_int(1,100)<=bdraw) {fc=R.rnd_int(1,40);} else if (randC===1) {fc=R.rnd_int(225,255);} else {fc=fcs[ik];}
          sklr=R.rnd_int(1,50);
          sklr=rgbthx([sklr,sklr,sklr,255]);
          if ((klmt!==0)&&(R.rnd_int(1,klmt)===1)) { sklr='#ffed8b'; }
          let rsc=R.rnd_num(1.7,2.4);
          if (macro===1) { rsc=rsc*.7; }
          if (((xq>xlw)&&(xq<xup))&&((yq>ylw)&&(yq<yup))) {
            nsq+=1;
            SQB[hk] = new p5.Vector(lsc,tex);
            XV[hk] = new p5.Vector(xq,rxx);
            YV[hk] = new p5.Vector(yq,ryy);
            KLR[hk] = new p5.Vector(sklr,fc);
            STW[hk] = new p5.Vector(sww);
            RTS[hk] = new p5.Vector(mm,rsc);
            hk+=1;
          }
        } else if ((rtst < 4)&&(ncirc<clim)) {
          lsc=3; ncirc+=1;
          let gs=R.rnd_num(140,190);
          rr=M*(Math.pow(gs,R.rnd_num(1.2,1.35)))*scf;
          xq=(x1+x2+rkk)*.5+R.rnd_num(0,.2*dst);
          yq=(y1+y2)*.5+R.rnd_num(0,.2*dst);
          let ncc = round(rr/(45*M))
          for (let jo=0;jo<ncc;jo++) {
            let plthrsh=4; if (macro===1) { plthrsh=1; }
            if (R.rnd_int(1,10)>plthrsh) {
              rs = rr*(1-(jo/(ncc+2)));
              if (macro===1) { rs = rs*.8; }
              xr=R.rnd_num(-.026,.026)*rs; yr=R.rnd_num(-.026,.026)*rs;
              spd = R.rnd_int(-2,2);
              ik=Math.round(R.rnd_num((-.75*pk),(.75*pk))+99*(ih/cols));
              while (ik<1||ik>99) { ik=Math.round(R.rnd_num((-.75*pk),(.75*pk))+99*(ih/cols)); }
              if (randC===1) { fc=R.rnd_int(155,255);
              } else if (R.rnd_int(1,100)<=bdraw) { fc=R.rnd_int(1,40);
              } else {fc = fcs[ik];}
              sklr=R.rnd_int(1,60);
              sklr=rgbthx([sklr,sklr,sklr,255]);
              let lny=R.rnd_num(1.4,1.9);
              let sww=M*R.rnd_num(1.85,2.25)*lny;
              if ((klmt!==0)&&(R.rnd_int(1,klmt)===1)) { sklr='#ffed8b'; }
              if (((xq>xlw)&&(xq<xup))&&((yq>ylw)&&(yq<yup))) {
                SQB[hk] = new p5.Vector(lsc,tex);
                XV[hk] = new p5.Vector(xq,xr);
                YV[hk] = new p5.Vector(yq,yr);
                KLR[hk] = new p5.Vector(sklr,fc);
                STW[hk] = new p5.Vector(sww);
                RTS[hk] = new p5.Vector(spd,rs);
                hk+=1;
              }
            }
          }
        }
      }
    }
  }
  SQ={SQB,XV,YV,KLR,STW,RTS,hk,bgc,crxx,cryy,crr,ccr,wd,ht,M,macro};
  return(SQ)
}

function orbb (ccr,crxx,cryy,crr,alph) {
  let clr=color(ccr); clr.setAlpha(alph)
  push(); fill(clr); noStroke(); circle(crxx,cryy,crr); pop();
  if (crxx+crr>SQ.wd) { push(); fill(clr); noStroke(); circle(crxx-SQ.wd,cryy,crr); pop(); }
  if (crxx-crr<0) { push(); fill(clr); noStroke(); circle(crxx+SQ.wd,cryy,crr); pop(); }
}

function setup() {
  rectMode(CENTER); angleMode(RADIANS);
  precalcs();
  if (SQ.macro===1) { noLoop() }
  if (SQ.macro===0) { frameRate(30) }
  createCanvas(SQ.wd,SQ.ht);
}

let ngL=0,ngLV=0,ngLA=0;
function draw() {
  ngLA = map(mouseX, 0, width, -.02, .02);
  ngLV = constrain(ngLV, -.04, .04);
  background(SQ.bgc);
  SQ.crxx+=ngLV*SQ.M*150;
  if (SQ.crxx>(SQ.wd+SQ.crr)) { SQ.crxx = SQ.crr; }
  if (SQ.crxx<-1*SQ.crr) { SQ.crxx = SQ.wd-SQ.crr; }
  orbb(ccr,SQ.crxx,SQ.cryy,SQ.crr,255);
  for (let NF=5, pp=1;pp<(1+NF);pp++) {
    let blr=(1+(Math.abs(ngLV*.6)/pp))*SQ.crr,alf=180/NF;
    orbb(ccr,SQ.crxx,SQ.cryy,blr,alf);
  }
  for (let j=0;j<SQ.hk;j++) {
    push();
    stroke(SQ.KLR[j].x);
    strokeWeight(SQ.STW[j].x);
    if (SQ.SQB[j].x>1) {
      clr=color(SQ.KLR[j].y); clr.setAlpha(SQ.SQB[j].y); fill(clr);
      translate(SQ.XV[j].x,SQ.YV[j].x);
    }
    if (SQ.SQB[j].x===2) {
      rotate(SQ.RTS[j].x); scale(SQ.RTS[j].y);
      rect(0,0,SQ.XV[j].y,SQ.YV[j].y);
    } else if (SQ.SQB[j].x===3) {
      rotate(SQ.RTS[j].x*ngL);
      circle(SQ.XV[j].y,SQ.YV[j].y,SQ.RTS[j].y);
    } else if (SQ.SQB[j].x===1) {
      line(SQ.XV[j].x,SQ.YV[j].x,SQ.XV[j].y,SQ.YV[j].y);
    }
    pop();
  }
  push();noFill();stroke(0);strokeWeight(20*SQ.M);rect(0.5*SQ.wd,0.5*SQ.ht,SQ.wd,SQ.ht); pop();
  ngLV += ngLA; ngL += ngLV; ngL = (ngL % (2*PI));
}
