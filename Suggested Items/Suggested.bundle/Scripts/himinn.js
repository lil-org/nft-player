wF=0.1;wF2=0.1;setup=()=>{pixelDensity(1),pI=parseInt,mF=Math.floor,H=tokenData.hash,n=noise,pN=mF(pI(tokenData.tokenId)/1e6),mN=pI(tokenData.tokenId)%(1e6*pN);
S=Uint32Array.from([0,1,s=t=2,3].map(i=>pI(H.substr(i*8+2,8),16)));R=_=>(t=S[3],S[3]=S[2],S[2]=S[1],S[1]=s=S[0],t^=t<<11,S[0]^=(t^t>>>8)^(s>>>19),S[0]/2**32);'tx piter'
rN=(f,N)=>map(R(1),0,1,f,N);sC=[1,2,3,4,5,6,7,8],g1=rN(0,9.2),g=1;if(g1<=0.4){g=3};if(g1>0.4&&g1<1.7){g=4};if(g1>=1.7&&g1<2.8){g=0};if(g1>=2.8&&g1<=3.9){g=7};if(g1>5.5&&g1<=6.7){g=6};if(g1>6.7&&g1<8.1){g=2};if(g1>=8.1){g=5};
T=0<mN,sN=sC[g];dZ=hZ=sS=cS=!1;if(.93<R(1)&&T){hZ=!0};if(sN==6){sS=!0};if((sN==3||sN==4||sN==5)&&R(1)>0.3){dZ=!0}
f1=mF(rN(0,17)),f2=mF(rN(0,10)),f3=mF(rN(0,3));3==sN&&(--f2,--f3),f2<1&&(f2=0),f3<1&&(f3=0),tC=f1+f2+f3;if(.92<R(1)&&T&&1!=sN&&6!=sN&&tC>17){cS=!0};
o=map,sT=stroke,cL=color,K=noStroke,seed=S[3],oW=windowWidth,oH=.5625*oW,wH=windowHeight,noiseSeed(seed),oH>wH&&(oW=1.77*wH,oH=.5625*oW),iW=1600,iH=900,createCanvas(iW,iH),nxS=oW/iW,nyS=oH/iH,iG=createGraphics(iW,iH),iG.colorMode(HSB,360,100,100,100),iG.e=iG.ellipse,iG.noStroke();
ds2=100,r8=550,b8=98;for(h5=0,1==sN?(dT=.2,b1=63,b2=58,b3=50,b7=148,h1=rN(186,188),dS=rN(0,8),b5=80,gD=25,h3=25,h4=b6=b4=45,h5=14,b8=90):
2==sN?(dT=.2,b1=87,b2=89,h1=rN(194,196),b3=83,b4=89,b5=95,b6=70,b7=0,dS=20,h3=190,h4=196,gD=10,h5=210):
3==sN?(dT=.1,h5=260,b1=36,b2=40,h1=rN(212.9,215.1),b4=75,b5=93,b6=50,b7=110,dS=45,b3=80,gD=15,h3=195,h4=205,r8=750,sG=120):
4==sN?(dT=.1,b1=50,b2=45,b3=50,b7=148,h1=rN(10,20),dS=10,b5=95,gD=h3=25,h4=b6=b4=45,sG=140):
5==sN?(dT=.1,h5=280,b1=65,b2=60,h1=rN(222,228),b4=75,b5=90,b6=50,b7=110,dS=20,b3=80,gD=17,h3=310,h4=318,ds2=86,r8=750,sG=170):
7==sN?(dT=.2,b1=84,b2=86,h1=rN(203,206),b3=82,b4=88,b5=95,b6=70,b7=0,dS=15,h3=200,h4=220,gD=27,h5=10):
8==sN?(dT=.2,b1=87,b2=88,h1=rN(201,203),b3=82,b4=87,b5=94,b6=70,b7=0,dS=10,h3=200,h4=220,gD=15,h5=300):
6==sN&&(dT=.2,b1=78,b2=80,h1=208,b3=85,b4=88,b5=92,h5=0,b6=65,b7=0,dS=18,h3=220,h4=240,gD=32,r8=700,s1=0,s2=25,b8=rN(90,95)),
h2=h1+8,hZ&&(ds2=55,dS-=5),4==sN&&(gD=1),i=0;i<18e3;i++)
r1=rN(-10,1500),r2=rN(-10,890),r3=rN(75,150),r4=rN(75,150),h11=h1,h22=h2,.945<R(1)&&(r4+=rN(0,100)),ds1=o(abs(r2-iH),0,iH,dS,ds2),
4==sN&&(ds1=o(abs(r2-iH),0,iH,0,5)),4==sN&&(hD=o(r2,-10,890,h1,h1+60),b1=hD,b2=hD),
i<16e3&&.4<R(1)&&r8<r2&&(h11=h3,h22=h4),iG.noStroke(),iG.fill(rN(h11,h22),ds1,rN(b1,b2),rN(0,50)),iG.rect(r1,r2,r3,r4);
if(sS)for(F=rN(2.5,7),i=0;i<700;i++)
xR=rN(1.01,1.25),r1=rN(50,1550),r2=rN(iH/xR,iH+15),r3=rN(75,140),r4=rN(25,45),.945<R(1)&&(r3+=rN(10,75)),ds1=o(abs(r2-iH),0,iH,dS,100),hst=o(abs(r2-iH),0,iH/F,s1,s2),iG.noStroke(),iG.fill(hst,ds1+10,rN(65,95),rN(3,9)),iG.e(r1,r2,r3,r4);
c=[],r6=20,lC=3600,cR=2.6,cR2=0,4==sN&&(r6=25,b1=98),tp1=12,cS&&(lC=1400,r6=8,cR=3,cR2=200,tp1=0);
for(iG.fill(h5,20,b3,tp1),4==sN&&iG.fill(45,0,90,tp1),i=0;i<f1;i++)a=rN(175,375),rX=a/2,rY=rX*rN(.3,.7),x=rN(a/1.5,iW-a/1.5),y=rN(650,775),c.push([a,rX,x,y,rY]),iG.e(x,y,rX+5,rY+5);for(j=0;j<f2;j++)a=rN(325,425),rX=a/2,rZ=rN(.3,.8),rY=rX*rZ,x=rN(a,iW-a),y=rN(450,535),c.push([a,rX,x,y,rY]),iG.e(x,y,rX,rY);for(k=0;k<f3;k++)a=rN(425,525),rX=a/2,rZ=rN(.4,.7),rY=rX*rZ,x=rN(a,iW-a),y=rN(225,350),c.push([a,rX,x,y,rY]),iG.e(x,y,rX,rY);
tD=0;C=c.length;for(l=0;l<lC;l++){dX =mF(rN(10,1590));dY =mF(rN(10,1590));dR=mF(rN(75,200));dRY=dR*rN(.3,.8);dY+=cR2;r5=r6;gD1=gD;if(r5<16){dY+=200};if(dY>703){r5-=rN(4,8)}if(dY>937){r5-=rN(4,8)}
for(m=0;m<C;m++){h=c[m][2];k=c[m][3];rX=c[m][1];rY=c[m][4];d2=((dX-h)**2)/(rX**2)+((dY-k)**2)/(rY**2);if(d2<rN(.8,1.3)){if(dY>(iH/3.5+rN(cR,-cR))){b1=b3;dR-=rN(0,25)}else if(dY>iH/2+rN(15,-15)){b1=b4;dR-=rN(0,25);}else{b1=b5};if(dY<400){dR*=1.1;dRY*=1.1}else if(dY>600){dR*=.84;dRY*=.84};if(R(1)>.89&&dY>iH/3){b1 = b5};if(R(1)>.8&&m<lC/1.25){b1=b6;gD1+=2;dRY*=.8};h6=h5+20;iG.fill(rN(h5,h6),rN(0,gD1),rN(b1,b8),rN(0,r5));iG.e(dX-rN(-10,10), dY,dR,dRY);tD+=1}}}
image(iG,0,0,iW,iH);loadPixels();bA=[],wA=[],dA=[],dA2=[],tH=3.1;wT=70;
for(y=0;y<iH;y++){for(x=0;x<iW;x++){iX=(x+(y)*(iW))*4,r=pixels[iX+0],g=pixels[iX+1],b=pixels[iX+2],lP=((x-1)+(y)*(iW))*4,rL=pixels[lP+0],gL=pixels[lP+1],bL=pixels[lP+2],tP=((x)+(y-1)*(iW))*4,rTop=pixels[tP+0],gTop=pixels[tP+1],bTop=pixels[tP+2],val=rN(0,100);
if(val<tH){cS1=(1)*o(n(wF),0,2.5,10,50),tT=mF(rN(13,21)),rR=rN(0,tT),rZ=0.5+(cS1/0.9),r2=rN(1,2),r7=R(1),aL=rN(10,58),bA.push([x,y,r,g,b,cS1,tT,rR,r2,r7,aL]);wF+= rN(.1,.2);}
dF=abs((r+g+b)/3-(rL+gL+bL)/3);dF2=abs((r+g+b)/3-(rTop+gTop+bTop)/3);val2=rN(0,100);tT=7;if((dF>1.3&&r>150&&val2<dT)||(dF2>1.3&&r>150&&val2<dT)){cS1=o(val2,0,1,1,2),lT=o(val2,0,1,50,250),bD=o(val,0,100,0,1),r2=o(val,1,100,1.4,1.9);
if(sN==3||sN==5){lT-=20};rR=o(val2,0,100,0,tT),dA.push([x,y,r,g,b,cS1,lT,rR,r2])}
if((b<b7&&val2<dT)||(b<b7&&val2<dT)){cS1 = o(val2,0,1,1,2),lT3=o(val2,0,1,15,85),bD=o(val,0,100,0,1),r2=o(val,1,100,1.4,1.9),rR=o(val2,0,100,0,tT),dA2.push([x,y,r,g,b,cS1,lT3,rR,r2]);}
if((val2<.00095&&val2>.0001)&&(sN==4||sN==5||sN==3)&&(r<sG&&g<sG&b<sG)&&(dZ==1)&&y>99&&x>99&&x<iW-99&&y<iH-99){cS5=o(val,0,100,.9,1.4),lT4=o(val,0,100,25,50),bD=o(val,0,100,0,1),r2=o(val,1,100,1.4,1.9),rR=o(val,0,100,0,tT);dA2.push([x,y,255,255,255,cS5,lT4,rR,r2]);cS6=cS5*.7,dA2.push([x,y,253,253,253,cS6,lT4,rR,r2-.5])}
val3 = rN(0,100);if(val3 <wT && (x<5||x>iW-5||y<5||y>iH-5)){cS1=o(n(wF2),0,1,1,3),tT=mF(rN(7,15)),rR=rN(0,tT),rZ=0.5+(cS1/0.9),r2=rN(1.6,2),r7=R(1),wA.push([x,y,255,255,255,cS1,tT,rR,r2,r7]);wF2+=rN(.1,.2);}}}
clear(),resizeCanvas(oW,oH)};draw=()=>{noiseSeed(seed),scale(nxS),l=fill,v=cos,u=sin,colorMode(RGB),background(255),dB(),noLoop()}
dB=()=>{for(i=0;i<bA.length;i++){x=bA[i][0],y=bA[i][1],r=bA[i][2],b=bA[i][3],g=bA[i][4],cS1=bA[i][5],tT=bA[i][6],rR=bA[i][7],r2=bA[i][8],r7=bA[i][9],aL=bA[i][10],l(cL(r,b,g,aL));mB(x,y,0.5,tT,cS1,2,rR,r2,r7)}dD()}
dD=()=>{for(j=0;j<dA.length;j++){x=dA[j][0],y=dA[j][1],r=dA[j][2],b=dA[j][3],g=dA[j][4],cS1=dA[j][5],lt2=dA[j][6],rR=dA[j][7],r2=dA[j][8],l(cL(r,b,g,lt2)),mB(x,y,0.5,7,cS1,3,rR,r2,.5);}dD2()}
dD2=()=>{for(j=0;j<dA2.length;j++){x=dA2[j][0];y=dA2[j][1];r=dA2[j][2]-15;b=dA2[j][3]-15;g=dA2[j][4]-15;cS1=dA2[j][5];lt3=dA2[j][6];rR=dA2[j][7];r2=dA2[j][8];l(cL(r,b,g,lt3));mB(x,y,0.5,7,cS1,3,rR,r2,0.5)}dW()}
dW=()=>{for(j=0;j<wA.length;j++){x=wA[j][0];y=wA[j][1];r=wA[j][2];b=wA[j][3];g=wA[j][4];cS1=wA[j][5];tT=wA[j][6];rR2=wA[j][7];r22=wA[j][8];r72=wA[j][9];l(cL(255,255,255));mB(x,y,0.5,tT,cS1,5,rR2,r22,r72)}}
mB=(bX,bY,r,pts,cS1,tst,rR,r22,r7)=>{beginShape();r+=(cS1/0.9);r2=r*r22;for(p=0+rR;p<pts+1+rR;p++){K();aG=(p*TWO_PI)/pts;x1=r*v(aG);y1=r2*u(aG);x2=x1*v(r7)-y1*u(r7);y2=y1*v(r7)+x1*u(r7);x3=bX+x2;y3=bY+y2;vertex(x3,y3)}endShape()}