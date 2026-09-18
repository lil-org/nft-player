function setup() {
	
R9=new Random();
//noprotect
myasratx=13;
myasraty=10;
myox=3900;
myoy=3000;
sc=1;
iphone=iOS();
if (iphone===true) {sc=0.3;}
myox=floor(myox*sc);
myoy=floor(myoy*sc);

gg=min((window.innerWidth*myasraty)/myasratx,window.innerHeight);
mywidth=floor((gg*myasratx)/myasraty);
myheight=floor(gg);
createCanvas(mywidth,myheight);

pg=createGraphics(floor(myox),floor(myoy),WEBGL);
pixelDensity(1);
pg.pixelDensity(1);
pg.strokeWeight(0);

pg.setAttributes('alpha',false);

cld=(floor(R9.random_dec()*4+R9.random_dec()*4)*50)+300;
mycl=R9.random_int(4,8);

const mclname=["0","1","2","3","Wild Red","Wild Yellow","6","7","Wild Blue","9",]; 
const myseaname=["0","Light","2","Pink","Light Blue","5","Dark","White","None"];
if (mycl==6) {mycl=8;}
if (mycl==7) {mycl=5;}

myback2=1;
mysea=R9.random_int(1,7);
roo=R9.random_int(2,8);
roo=roo*roo/2;

birddensity=R9.random_int(0,3);

seatype="Light";
if (R9.random_dec()>0.75) {seatype="Diamond";}
if (R9.random_dec()>0.5) {seatype="Wavy";}
layer1="Wide";
nx=5000;
ny=2000;
if (R9.random_dec()>0.5) {
layer1="Circular";
nx=3000;
ny=3000;
}

roty=0;
stroker=1;
stroker2=0;
seashift=0;
seashift2=R9.random_dec()*0.000003-0.0000015;
if (R9.random_dec()>0.8) {
seashift=1;
seashift2=R9.random_dec()*0.000003-0.0000015;
}
if (seashift2<0.0000008 && seashift2>0) { seashift2 = 0.0000008; }
if (seashift2>-0.0000008 && seashift2<0) { seashift2 = -0.0000008; }
if (R9.random_dec()>0.9) {seashift2=0;}
stt=0;
yp=0.98;
cloudburst="Standard";
strokername="Light";
if (R9.random_dec()>0.3) {
strokername="Dark Clouds";
stroker2=1;
if (R9.random_dec()>0.4) {
stt=1;
strokername="Maroon";
if (mysea==4) {mysea=1;}
} 
if (R9.random_dec()>0.8  && mycl != 4) {
stt=3;
strokername="Burnt Orange";
yp=yp-0.01;
if (mysea==4) {mysea=1;}
}
if (R9.random_dec()>0.9) {
stt=2;
strokername="Ocean";
}
if (birddensity>1) {birddensity=birddensity-1;}
if (mysea==5) {mysea=1;}
if (mysea==2) {mysea=7;}
if (mysea==3 && mycl!=8) {mysea=6;}
if (mysea==4 && mycl!=8) {mysea=1;}
if (R9.random_dec()>0.63) {roty=1;}
if (R9.random_dec()>0.7 && mycl != 4) {
strokername="Red Shift";
stroker2=2;
yp=yp-0.01;
if (mysea==4) {mysea=7;}
}
if (R9.random_dec()>0.78 && mycl != 8) {
strokername="Blue Shift";
stroker2=3;
}
} else {
yp=yp-0.03;
if (R9.random_dec()>0.63) {roty=1;}
if (mycl==4 || R9.random_dec()>0.67) {mycl=5;}
stroker=1;
strokername="Strange Clouds";
if (R9.random_dec()>0.7) {
seashift=1;
seashift2=R9.random_dec()*0.000002+0.000001;
if (R9.random_dec()>0.5) {seashift2=-seashift2;}
if (mysea==0) {
mysea=6;
seatype="Light";
}
}
if (mysea==2) {mysea=7;}
if (mysea==5) {mysea=1;}
if (mysea==3 && mycl!=8) {mysea=1;}
if (mysea==4 && mycl!=8) {mysea=1;}
}
if (roty==1 && mysea==0) {
mysea=6;
seatype="Light";
}
if (R9.random_dec()>0.9) {cloudburst="Loose";}
if (R9.random_dec()>0.5 && roty==0) {
cloudburst="Quantum";
seatype="Wavy";
yp=yp-0.01;
}
if (mysea==6) {
mysea=7;
}
seashift3=1.3;
if (R9.random_dec()>0.2) {
seashift3=0.9;
}

skylight=R9.random_int(1,4);
if (skylight>3) {
if (cloudburst != "Standard" || roty==1) {
skylight=skylight+5;
} else {
skylight=R9.random_int(1,3);
}
}

skylight= 2**skylight;
skyburst=0;
if (skylight<6 && R9.random_dec()>0.5) {skyburst=1;}
if (skylight==8) {skylight=3;}
if (R9.random_dec()>0.5) {skylight=-skylight;}
if (skyburst==1) {
nx=nx/2;
ny=ny/2;
sburst="Yes";
} else { sburst="No";}

lg1=0;
lgname="Clouds over Light";
lgb=86;
if (R9.random_dec()>0.25 || stroker2==0) {
lg1=1;
lgname="Challenging Light";
lgb=56;}
if (R9.random_dec()>0.9 && skyburst==0) {
lg1=2;
lgname="Growing Light";
lgb=33;}
rotyname="No";
if (roty==1) { 
rotyname="Yes";
if (birddensity>0) {birddensity=birddensity-1};
yp=yp-0.02;}

if (stroker2==0) {lgb=24;}
qusname="No";
qus=1;
qus2=340;
if ((cloudburst=="Quantum" && R9.random_dec()>0.4) || (roty==0 && R9.random_dec()>0.6)) {
qus=1.3;
qus2=3000;
qusname="Yes";
if (birddensity==0) {birddensity=1;}
}

if (birddensity==2 && R9.random_dec()>0.6) {birddensity=3;}

aqname="No";
aqno=50;
if (cloudburst=="Quantum" && R9.random_dec()>0.75) {
aqname="Yes";
aqno=4;
yp=yp-0.01;
}

hzf="No";
hzfno=24;
hzfno2=12;
hzfmod=3;
if (qus==1) {
if (strokername=="Ocean") {hzf="Yes"; }
if (strokername=="Dark Clouds" && R9.random_dec()>0.4) {hzf="Yes"; }
if (strokername=="Maroon" && R9.random_dec()>0.9) {hzf="Yes"; }
if (strokername=="Strange Clouds" && R9.random_dec()>0.3) {
hzf="Yes"; 
hzfmod=2;}
if (hzf=="Yes"  && R9.random_dec()>0.75 && strokername!="Dark Clouds") { 
hzf="Strong"; 
hzfno=12;
hzfno2=20;
}}

lh=0;
if ((stroker2!=1 || stt==3) && roty==1 && R9.random_dec()>0.3) {lh=1;}
if (qus==1.3  && R9.random_dec()>0.4) {lh=1;}

rh=2;
ref=R9.random_int(1,4);
if (roty==1) {ref=3;}
if (ref==1) {refsty="Angled";}
if (ref==2) {refsty="Direct";}
if (ref==3) {refsty="None"; rh=0;}
if (ref>3) {refsty="None"; rh=0;}


lht="Middle";
if (lh==1) {lht="Low";}

const features={ "MainStyle": strokername,"CloudBurst": cloudburst,"CloudDensity": cld,"ReflectionStyle": refsty,"Horizon": lht,"Explosion": rotyname,"Quantum Seperation": qusname,"Diamond Clouds": aqname,"LightvClouds": lgname,"SeaLight": myseaname[mysea],"SeaStyle": seatype,"BackColorFlow": mclname[mycl],"Horizon Noise":hzf,"SkyBurst": sburst,"BirdDensity": birddensity};
n=5;
if (roty==1) {n=1;}
if (cloudburst=="Quantum") {n=8;}

windy=(R9.random_dec()*20-10)*sc;
if (windy>0 && windy<5*sc) {windy=5*sc;}
if (windy>-5*sc && windy<0) {windy=-5*sc;}
loopy=0
xr=64
xg=64
xb=64
xrtot=0
xgtot=0
xbtot=0
xrtot2=0
xgtot2=0
xbtot2=0
xtot=0
yox=R9.random_dec()*myox-myox/2;
yoy=R9.random_dec()*myoy-myoy/2;
if (mycl==4) {
if (Math.abs(skylight)<10) {xr=140;} else {xr=92;}
r27=2.98;
g27=2.995;
b27=2.995;
}
if (mycl==5) {
xr=96;
xg=76;
r27=2.98;
g27=2.985;
b27=2.995;
}
if (mycl==8) {
xb=108;
r27=2.99;
g27=2.975;
b27=2.95;
}
pg.translate(0,0,-6000*sc);
myxt=0;
myyt=0;
yoot=0;
qr=[];
qg=[];
qb=[];
ix=R9.random_dec()*R9.random_dec()*1700+700;
iy=R9.random_dec()*R9.random_dec()*1100+400;
hzm=R9.random_dec()*1000+200;
if (lh==1) {
	hzm=hzm/2;
	seashift2=seashift2/1.4;
}
sx2=R9.random_int(1,2);
wind2=((R9.random_dec()*6)+93)/100;
}

function draw() {
loopy=loopy+1;
if (loopy>3 && loopy<50 && hzf!="No") {
pg.strokeWeight(R9.random_dec()*R9.random_dec()*R9.random_dec()*5000*sc);
for (a=1; a<hzfno2; a++) {
if (a%hzfmod==1) {c=color(240,230,210,32);} else {c=color(0,0,0,32);}
pg.stroke(c)
pg.fill(c)
pg.ellipse(R9.random_dec()*myox*4-myox*2,0,R9.random_dec()*myox/30,R9.random_dec()*myoy*2/hzfno, 50);
}
}

if (loopy<52) {
mytransx=(R9.random_dec()*1000-500)*sc;
if (strokername=="Dark Clouds" && cloudburst!="Quantum") {
mytransy=-100*sc;
} else {mytransy=0;}
myxt=myxt+mytransx;
if (Math.abs(myxt)>2300) {
myxt=myxt-mytransx;
mytransx=0;
}

pg.translate(mytransx,mytransy,5*sc);
yoo=2*PI;
lgs=0;
if (lg1==0 && (loopy<3 || loopy%20==1)) {lgs=1;}
if (lg1==1 && loopy%9==1) {lgs=1;}
if (lg1==2 && loopy%5==1) {lgs=1;}
if (lgs==1) {
xr2=xr;
xg2=xg;
xb2=xb;
ccrot2=0
pg.blendMode(SCREEN);
ef=0.1*sc;
yoot2a=yoot-(floor(yoot/(2*PI)))*2*PI;
if (loopy>2 && loopy<45 && R9.random_dec()>0.8 && cloudburst!="Quantum") {
yoot3a=PI/2 - yoot2a+R9.random_dec()*0.06-0.02;
pg.rotateX(yoot3a);
yoot=yoot+yoot3a;
ef=0.06*sc;
}
if (loopy>44 || roty==1) {
if (Math.abs(yoot2a-PI/2)<0.2) {ef=0;}
}
for (a=0; a<floor(myoy*1.29); a+= 4*sc) {
for (b=0; b<lgb; b++) {
roo=roo+0.0002;
myxt2= (R9.random_dec()*80-40)*sc;
myyt2= (R9.random_dec()*80-41)*sc;
if (Math.abs(myxt)>2500*sc) {myxt2=-myxt*0.04;}
if (Math.abs(myyt)>2000*sc) {myyt2=-myyt*0.04;}
if ((myyt)>100*sc) {myyt2=-20*sc;}
myxt=myxt+myxt2;
myyt=myyt+myyt2;
pg.translate(myxt2,myyt2,0);
xr2=xr2+(R9.random_dec()*6-r27)*roo/18;
xg2=xg2+(R9.random_dec()*6-g27)*roo/18;
xb2=xb2+(R9.random_dec()*6-b27)*roo/18;
if (xr2<-32) {xr2=0;}
if (xr2>270) {xr2=240;}
if (xg2<-32) {xg2=0;}
if (xg2>245) {xg2=215;}
if (xb2<-32) {xb2=0;}
if (xb2>260) {xb2=230;}
if ((xb2+xg2+xr2)<200) {
xg2=xg2+5;
xb2=xb2+5;
xr2=xr2+5;
}
if ((xb2+xg2+xr2)>550) {
xg2=xg2-5;
xb2=xb2-5;
xr2=xr2-5;
}
if (xg2>(xb2) && xg2>(xr2)) {xg2=xg2-0.1;}
if (xr2>(xb2) && xr2>(xg2)) {xr2=xr2-0.2;}
if (xb2>(xr2+20) && xb2>(xg2+20)) {
		xr2=xr2+0.02;
		xg2=xg2+0.02;
}
if (xg2>(xb2) && xg2>(xr2) && stroker2==0) {xg2=xg2-0.1;}
if ((xr2+xb2)>(xg2*5)  && stroker2==0) {xg2=xg2+0.3;}
if (skyburst==1) {c=color(xr2/130,xg2/130,xb2/130,8+loopy/6)
} else {c=color(xr2/96,xg2/96,xb2/96,40+loopy/2)}
cc2=color(xr2+R9.random_dec()*64-64,xg2+R9.random_dec()*64-64,xb2+R9.random_dec()*64-32,96);
pg.stroke(cc2);

pg.fill(c);
pg.strokeWeight(ef);
ccrot=R9.random_dec()*0.01;
ccrot2=ccrot2+ccrot;
pg.rotate(ccrot/skylight);
if (skyburst==1) {
pg.ellipse(R9.random_dec()*myox*7-myoy*2.5,(b*skylight*sc),R9.random_dec()*nx*sc,R9.random_dec()*ny*sc,50);
} else {
pg.ellipse(R9.random_dec()*myox*7-myoy*2.5,((myoy/2)-a)*3+(R9.random_dec()*200-100)*sc+(skylight*4*R9.random_dec()-skylight/2)*sc,R9.random_dec()*sc*nx/1.8,R9.random_dec()*sc*ny/1.8,50);
}
	
xrtot=xrtot+xr2;
xgtot=xgtot+xg2;
xbtot=xbtot+xb2;
xtot=xtot+1;
if (stroker2==0 && roo>10) {roo=10;}
}
}
pg.reset();
yoot=0;
pg.translate(0,-200*sc + (lh*2500+hzm)*sc,-8500*sc);
pg.blendMode(BLEND);
myxt=0;
myyt=-200*sc;
xrtot2=xrtot/xtot;
xgtot2=xgtot/xtot;
xbtot2=xbtot/xtot;
}
if (loopy<51) {
yoo8=R9.random_dec()*yoo;
yoot=yoot+yoo8;
yoswing=R9.random_dec()*0.01-0.005;
yoot2=yoot-(floor(yoot/(2*PI)))*2*PI;
mlog=0;
if (roty==1 || qus==1.3) {
if (yoot2<((PI/2)) && yoot2>((PI/2)-0.35)) { 
yoo8=yoo8-0.4;
yoot=yoot-0.4;
mlog=1;}
if (yoot2<((3*PI/2)) && yoot2>((3*PI/2)-0.35)) { 
yoo8=yoo8-0.4;
yoot=yoot-0.4;
mlog=2;}
if (yoot2<((PI/2)+0.25) && yoot2>((PI/2))) { 
yoo8=yoo8+0.4;
yoot=yoot+0.4;
mlog=3;}
if (yoot2<((3*PI/2)+0.25) && yoot2>((3*PI/2))) { 
yoo8=yoo8+0.4;
yoot=yoot+0.4;
mlog=4;}}
if (roty==1) {pg.rotateY(yoo8);
} else {pg.rotateX(yoo8);}
yoot=yoot+yoswing;
pg.rotateY(yoswing);
pg.rotateX(yoswing);
yox=R9.random_dec()*myox-myox/2;
yoy=R9.random_dec()*myoy-myoy/2;

pg.strokeWeight(0);
mover=(250-loopy)*sc;
yp1=1;
if (R9.random_dec()>wind2) {windy=-windy;}
for (q=10; q<(cld); q+=1) {
if (R9.random_dec()>yp) {yp1=5;}
yp1=yp1-1;
cyox=0;
cyoy=0;
t1=0;
while ((Math.abs(cyox+windy*2*loopy)<ix*sc && Math.abs(cyoy) < iy*sc) || (Math.abs(cyox) < 300*sc) || ((Math.abs(cyoy) < 1500*sc) && t1<4)) {
yox=yox +(windy*(loopy+20)/50)+ (R9.random_dec().toFixed(6)*mover*4.8*qus - mover*2.4*qus)*(500)/800;
if (roty==1 || qus==1.3) {yox = (100+((abs(yoy)+3000*sc)/(4000*sc)))/101*yox;} else {
yox=(100+((abs(yoy)+10000*sc)/(11000*sc)))/101*yox;}
if (yox<-myox*3.6) {yox=-myox*3.6;}
if (yox>myox*3.6) {yox=myox*3.6;}
yoy=yoy+(R9.random_dec().toFixed(6)*mover*2.6-mover*1.3)*(400 +lh*240+hzm/12)/800;
if (yoy<-myoy*5.2) {yoy=-myoy*5.2;}
if (yoy>myoy*5.2) {yoy=myoy*5.2;}
if (Math.abs(yoy)>myoy*4.5) {yoy=yoy*0.99;}
if (yoy<(qus2-roty*200)*sc && yoy>0)  {yoy=yoy+(50+qus2/10)*sc;}
if (yoy>-(qus2-roty*200)*sc && yoy<0)  {yoy=yoy-(50-qus2/10)*sc;}
cyoy=yoy;
cyox=yox;
t1=t1+1;
}
xr=xr+(R9.random_dec()*6-r27)*roo/30;
if (xr>280) {xr=255}
if (xr<-16) {xr=0}
if (mycl==6) {
xg=xr;
xb=xr;
} else {
xg=xg+(R9.random_dec()*6-g27)*roo/30;
if (xg>235) {xg=215}
if (xg<-16) {xg=0}
xb=xb+(R9.random_dec()*6-b27)*roo/30;
if (xb>280) {xb=255}
if (xb<-16) {xb=0}
}
if ((xb+xg+xr)<200) {
xg=xg+4;
xb=xb+4;
xr=xr+4;
}
if ((xb+xg+xr)<300) {
xg=xg+2;
xb=xb+2;
xr=xr+2;
}
if ((xb+xg+xr)>600) {
xg=xg-5;
xb=xb-5;
xr=xr-5;
}
if (xg>(xb+20) && xg>(xr+20)) {xg=xg-2;}
xtot7=xr+xg+xb;
maxi=Math.max(xr,xg,xb)/255;
mini=Math.min(xr,xg,xb)/255;
difi=maxi-mini;
mysat=0;

if (xtot7>382.5 && difi>0) {
mysat=difi/(2-maxi-mini);
} else {
mysat=difi/(maxi+mini);}
if (mysat>0.6) {
if (xg>xr && xg>xb && xr<xb) {xg=xg-1;}
if (xg>xr && xg>xb && xb<xr) {xg=xg-1;}
if (xr>xg && xr>xb && xg<xb) {xr=xr-1;}
if (xr>xg && xr>xb && xb<xg) {xr=xr-1;}
if (xb>xg && xb>xr && xr<xg) {xb=xb-1;}
if (xb>xg && xb>xr && xg<xr) {xb=xb-1;}
}

rx=(R9.random_dec()*(750-q/2)*4)*sc;
ry=(R9.random_dec()*(750-q/2)*4)*sc;
c=color(xr,xg,xb,64);
cs=color(xr-128*R9.random_dec()+64,xg-128*R9.random_dec()+64,xb-128*R9.random_dec()+64,21);

pg.stroke(cs);
pg.fill(c);
pg.strokeWeight(1*sc);
bls=0.94;
c=color(xr+32,xg+32,xb+32,1+q/16);
if (R9.random_dec()>0.997) {
pg.strokeWeight(R9.random_dec()*40*sc);
cs=color(240,230,210,6+q/16);
} else {
if (stroker2==1) {
if (stt==0) {
if (R9.random_dec()>0.003) { 
cs=color(0,0,0,n+(q/5)); 
} else {
cs=color(240,230,210,6+q/16);
}}
if (stt==1) {cs=color(xr/2,0,0,5+n+q/6);}
if (stt==2) {cs=color(xr*0.15,xg*0.25,xb*0.35+xg*0.2,n+q/7);}
if (stt==3) {cs=color((xr+xg/2)/1.5 ,(xr+xg/4)/4,0,5+n+q/7);}
}
if (stroker2==0) {
xotot=(xrtot2+xgtot2+xbtot2)/3;
if (sx2==1) {
cs=color((xr)*1.5,(xg+xr+xb)*0.5,xb*1.5,n+q/16);
} else {
cs=color((xr)*1.16,(xg+xr+xb)*0.38,xb*1.16,n+q/16);
}
bls=0.98;
}
if (stroker2==2) {
cs=color(130+xr/5,10+xg/5,40+xb/5,n+q/8);
bls=0.98;
}
if (stroker2==3) {
cs=color(10+xr/5,30+xg/5,120+xb/5,n+q/8);
bls=0.98;
}
}
pg.stroke(cs);
pg.fill(c);
if (cloudburst=="Loose") {fno=12+roty*3;
} else {
if (cloudburst=="Quantum") {
fno=13+roty*3;
} else {
fno=16;}}
for (f=1; f<fno; f++) {
pg.rotate(R9.random_dec()*0.0001-0.00005);
if (R9.random_dec()>0.95) {c=color(240,230,210,6+q/6);}
if (R9.random_dec()>0.99 && stroker2>0) {cs=color(128-R9.random_dec()*64,128-R9.random_dec()*64,128-R9.random_dec()*64,6+q/16);}
if (R9.random_dec()>0.99 && stroker2>0) {cs=color(R9.random_dec()*96,R9.random_dec()*96,R9.random_dec()*96,6+q/16);}
if (R9.random_dec()>bls && stroker2>0) {cs=color(R9.random_dec()*64,R9.random_dec()*64,R9.random_dec()*64,5+q/12);}
if (yp1>1) {cs=color(220+R9.random_dec()*128-64,210+R9.random_dec()*128-64,180+R9.random_dec()*128-64,q/32);}
if (R9.random_dec()>0.995 && stroker2>0) {c=color(0,0,0,6+q/7);}
if (R9.random_dec()>0.99 || f==1) {c=color(xr-48,xg-48,xb-48,6+q/8);}
pg.fill(c);
pg.stroke(cs);
pg.strokeWeight(250*sc);
fgox=1000*sc;
fgoy=1000*sc;
while ((fgox*fgox+fgoy*fgoy)>100000*sc*sc) {
fgox=(R9.random_dec()* 1000-500)*sc;
fgoy=(R9.random_dec()* 1000-500)*sc;
}

if (cloudburst=="Standard") {
pg.fill(cs);
if (roty==1) {pg.strokeWeight((240-q/20)*sc);
} else {pg.strokeWeight((300-q/10)*sc);}

if (((Math.abs(fgoy+yoy))>(600*sc) && roty==1) || (Math.abs(fgoy+yoy)>0)) {
pg.ellipse(yox+fgox,yoy+fgoy,(3*sc+rx/5),(3*sc+ry/7),50);}
}
if (cloudburst=="Quantum") {
fgox=(R9.random_dec()*600-300)*sc;
fgoy=(R9.random_dec()*500-250)*sc;
pg.strokeWeight(1*sc);
pg.fill(cs);
pg.ellipse(yox+fgox,yoy+fgoy,((rx+1000*sc)*qus/(4)),((ry+1000*sc)/(5*qus)),aqno);
}
if (cloudburst=="Loose") {
if (roty==1) {
pg.strokeWeight((240)*sc);
} else {
pg.strokeWeight((300)*sc);}
pg.ellipse(yox+R9.random_dec()*(900-450)*sc,yoy+R9.random_dec()*(900-450)*sc,(3*sc+rx*0.17),(3*sc+ry*0.13),50);
}
}
c=color(255,255,255,1);
pg.fill(c);
if (R9.random_dec()>0.95) {pg.strokeWeight(0);}
}
}

if (loopy==51) {
pg.reset();
pg.translate(0,(460*lh+hzm/4.5)*sc,0);
pg.rotateX(seashift3);
pg.strokeWeight(0);
if (mysea!=1) {mystroke2=90;} else {mystroke2=110;}
seau = R9.random_dec()*150000+150000;
if (mysea==8) {seau=0;}
for (a=1; a<seau; a++) {
pg.strokeWeight(0);
if (seashift==1) {pg.rotateX(-0.000005);}
if (seashift=2) {pg.rotate(seashift2);}
if (mysea==1) {
xt=(xrtot2+xgtot2+xbtot2)/2.7;
c=color(R9.random_dec()*32+(xrtot2+xt)/2-32,R9.random_dec()*32+(xgtot2+xt)/2-32,R9.random_dec()*32+(xbtot2+xt)/2-32,mystroke2);}
if (mysea==3) {
xt=(xrtot2*2+xgtot2+xbtot2*4)/5;
c=color(R9.random_dec()*32+xt-16,R9.random_dec()*32+xt-32,R9.random_dec()*32+xt+16,mystroke2);
}
if (mysea==4) {
xt=(xrtot2+xgtot2*2+xbtot2*4)/5;
c=color(R9.random_dec()*32+xt-16,R9.random_dec()*32+xt,R9.random_dec()*32+xt,mystroke2);
}
if (mysea==6) {c=color(20+R9.random_dec()*32,30+R9.random_dec()*32,48+R9.random_dec()*32,mystroke2);}
if (mysea==7) {c=color(R9.random_dec()*32+180,R9.random_dec()*32+170,R9.random_dec()*32+150,mystroke2);}
pg.fill(c);
ddp=(R9.random_dec()*1000*R9.random_dec())*sc;
if (seatype=="Light") {pg.ellipse((R9.random_dec()*10000-5000)*sc,ddp*3,ddp/3,ddp/10,50);}
if (seatype=="Wavy") {pg.ellipse((R9.random_dec()*10000-5000)*sc,ddp*3,ddp/2,ddp/18,50);}
if (seatype=="Diamond") {pg.ellipse((R9.random_dec()*10000-5000)*sc,ddp*3,ddp/3,ddp/8,4);}
}
pg.rotateX(-seashift3*2);
pg.strokeWeight(0);
pg.rotateX(seashift3);
goplatform();
}
}
if (loopy>51 && loopy <57) {
pg.reset();
goblur2();
if (loopy==53) {gobirds();}
}
if (loopy==55) {noLoop();}
img2=createImage(mywidth,myheight);
img2.copy(pg,floor(-myox/2),floor(-myoy/2),myox,myoy,0,0,mywidth,myheight);
image(img2,0,0,mywidth,myheight);
}

function goblur2() {

img=createImage(myox,myoy);
img.copy(pg,floor(-myox/2),floor(-myoy/2),myox,myoy,0,0,myox,myoy);
img.loadPixels();
var w=img.width;
var h=img.height;
liner=(loopy-52)*2;
doblur=0;
if (loopy<54) { doblur=1; }
blursize=loopy-42;
for (var x=liner+40*sc; x< w-40*sc; x+= ceil(9*sc)) {
for (var y=liner+40*sc; y< (h-40*sc); y+= ceil(9*sc)) {
if (doblur==0) {
if (loopy==54 && y<h/1.7) {doblur=1;}
if (loopy==55 && roty==0 && y<h/3.6) { doblur=1; }
if (roty==1 && y<h/2 && (x<(2*w/7) || x>(5*w/7))) {
doblur=1; 
}
} 
if (doblur==1) {
r1=0;
g1=0;
b1=0;
for (qx=-2; qx<3; qx++) {
for (qy=-2; qy<3; qy++) {
myib=(qx+2)+(qy+2)*5+1;
qr[myib]=((x +qx + w) % w + w*((y +qy+h) % h))*4;
r1=r1+img.pixels[qr[myib]];
g1=g1+img.pixels[qr[myib]+1];
b1=b1+img.pixels[qr[myib]+2];
}
}
r1=r1/25;
b1=b1/25;
g1=g1/25;
greyer=r1+g1+b1;
maxi=Math.max(r1, g1, b1) / 255;
mini=Math.min(r1, g1, b1) / 255;
difi=maxi-mini;
mysat=0;

cb=color(r1,g1,b1,152);
pg.fill(cb);
pg.strokeWeight(0);
if (y<h/2) {
pg.ellipse(x+2*sc-myox/2, y+2*sc-myoy/2,floor(blursize*sc),floor(blursize*sc));}

cb=color(r1,g1,b1,rh);
h7=0;
if (ref==1 || ref==4) {
x7=(myoy/2-y)*(x/myox);
h7=h/2;
}
if (ref==2 || ref==5) {
x7=0;
h7=h/2;
}
pg.fill(cb);
if (y<h7 && rh>0) {pg.ellipse(-myox/2 +x+x7, myoy/2-(y+2),floor(blursize*10*sc),floor(blursize*sc/2));}
}
}
}
}

function goplatform() {
pg.reset()
for (pl=1; pl<1400; pl++) {
xplat=(R9.random_dec()*16000-8000)*sc;
cplat=color(255,255,255,8);
pg.fill(cplat);
pg.rect(xplat,-2000*sc,1*sc,4000*sc);
}
cplat=color(255,255,255,128);
pg.noFill();
pg.stroke(cplat);
pg.strokeWeight(8*sc);
cplat=color(0,0,0,16);
pg.stroke(cplat);
pg.strokeWeight(30*sc);
for (glit=1; glit < 6000; glit++) {
cglit=color(200+R9.random_dec()*55,200+R9.random_dec()*55,255,48);
pg.strokeWeight(1*sc);
pg.stroke(cglit);
pg.ellipse(R9.random_dec()*myox-myox/2,R9.random_dec()*myoy-myoy/2,(R9.random_dec()*7+1)*sc,(R9.random_dec()*7+1)*sc);
}
}

function gobirds() {
birdno=(birddensity*4)+3;
if (birdno<6) { birdno=1; }
pg.reset();
pg.translate(0,0,400*sc);
birdsx=[];
birdsy=[];
for (p=1; p<birdno; p++) {
kx1=0;
kx2=0;
kx3=0;
kx4=0;
ky1=0;
ky2=0;
ky3=0;
ky4=0;
kx1=(floor(R9.random_dec()*100)+floor(R9.random_dec()*2) *300);
ky1=(floor(R9.random_dec()*100)+floor(R9.random_dec()*2) *300);
kx4=400-kx1;
ky4=400-ky1;

xdirect=kx4-kx1;
ydirect=ky4-ky1;
adirect=floor((xdirect*100)/ydirect)/100;

if (adirect>0.3 && adirect<4) {
kx2=(kx1+kx4)/2+30+(R9.random_dec()*70);
ky2=(ky1+ky4)/2-30-(R9.random_dec()*70);
kx3=(kx1+kx4)/2-30-(R9.random_dec()*70);
ky3=(ky1+ky4)/2+30+(R9.random_dec()*70);
} else {
kx2=(kx1+kx4)/2+30+(R9.random_dec()*70);
ky2=(ky1+ky4)/2+30+(R9.random_dec()*70);
kx3=(kx1+kx4)/2-30-(R9.random_dec()*70);
ky3=(ky1+ky4)/2-30-(R9.random_dec()*70);
}
bsz=(R9.random_dec()*R9.random_dec()*0.35+0.15)*sc;
birdspace=0;
while (birdspace==0) {
birdx=(R9.random_dec()*2700-1350)*sc;
birdabs=Math.abs(birdx);
birdy=(R9.random_dec()*(2000*sc-birdabs)-(2300*sc-birdabs)/2);
birdsx[p]=birdx;
birdsy[p]=birdy;
birdspace=1;
for (p2=0; p2<p; p2++) {
if (Math.abs(birdx-birdsx[p2])<100*sc && Math.abs(birdy-birdsy[p2])<100*sc) {birdspace=0;}
}
if (birdy>0 && bsz<0.3*sc) {birdspace=0;}
}
c2=color(32,32,32,192);
if (R9.random_dec()>0.6) {c2=color(230,216,190,192);}

kx1a=kx1*bsz+birdx;
kx2a=kx2*bsz+birdx;
kx3a=kx3*bsz+birdx;
kx4a=kx4*bsz+birdx;
ky1a=ky1*bsz+birdy;
ky2a=ky2*bsz+birdy;
ky3a=ky3*bsz+birdy;
ky4a=ky4*bsz+birdy;
pg.strokeWeight(sc);
pg.stroke(c2);
pg.fill(c2);
pg.beginShape();
pg.vertex(kx1a,ky1a); 
pg.bezierVertex(kx1a,ky1a,kx3a,ky3a,kx2a,ky2a);
pg.bezierVertex(kx2a,ky2a,kx1a,ky1a,kx3a,ky3a);
pg.bezierVertex(kx3a,ky3a,kx1a,ky1a,kx4a,ky4a);
pg.endShape();

for (bc=17; bc<24; bc++) {
bdcx=kx4a+(kx1a-kx4a)*bc/32+(kx3a-kx2a)/16;
bdcy=ky4a+(ky1a-ky4a)*bc/32+(ky3a-ky2a)/16;
pg.ellipse(bdcx,bdcy,32*bsz);
}
}
c2=color(230,216,190,192);
pg.strokeWeight(sc);
pg.translate(0,0,-400*sc);
}

function keyTyped() {
if (key=="s") {
pgs=createGraphics(myox,myoy);
pgs.image(pg,0,0);
saveCanvas(pgs,"Seasky","jpg");
}
}

function windowResized() {
gg=min((windowWidth*myasraty)/myasratx,windowHeight);
mywidth=(gg*myasratx)/myasraty;
myheight=gg;
resizeCanvas(floor((gg*myasratx)/myasraty),floor(gg));
}

class Random {
  constructor() {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substr(0,8),16);
      let b = parseInt(uint128Hex.substr(8,8),16);
      let c = parseInt(uint128Hex.substr(16,8),16);
      let d = parseInt(uint128Hex.substr(24,8),16);
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
    this.prngA = new sfc32(tokenData.hash.substr(2,32));
    this.prngB = new sfc32(tokenData.hash.substr(34,32));
    for (let i = 0; i < 1e6; i += 2) {
      this.prngA();
      this.prngB();
    }
  }
  random_dec() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  random_num(a,b) {
    return a + (b - a) * this.random_dec();
  }
  random_int(a,b) {
    return Math.floor(this.random_num(a,b+1));
  }
  random_bool(p) {
    return this.random_dec() < p;
  }
  random_choice(list) {
    return list[this.random_int(0,list.length - 1)];
  }
}

function iOS() {
  return ['iPad Simulator','iPhone Simulator','iPod Simulator','iPad','iPhone','iPod'].includes(navigator.platform)
}