class Random{constructor(){this.useA=!1;let a=function(e){let f=parseInt(e.substr(0,8),16),g=parseInt(e.substr(8,8),16),h=parseInt(e.substr(16,8),16),i=parseInt(e.substr(24,8),16);return function(){f|=0,g|=0,h|=0,i|=0;let a=0|(0|f+g)+i;return i=0|i+1,f=g^g>>>9,g=0|h+(h<<3),h=h<<21|h>>>11,h=0|h+a,(a>>>0)/4294967296}};this.prngA=new a(tokenData.hash.substr(2,32)),this.prngB=new a(tokenData.hash.substr(34,32));for(let a=0;1e6>a;a+=2)this.prngA(),this.prngB()}random_dec(){return this.useA=!this.useA,this.useA?this.prngA():this.prngB()}}function fr(a){return flr(R()*a)}function afr(b){return b[fr(b.length)]}function abs(a){return Math.abs(a)}function flr(a){return Math.floor(a)}function cae(a,b){canvas.addEventListener(a,b)}const urlParams=new URLSearchParams(window.location.search);let fO="false"==urlParams.get("flourish"),reactive="true"==urlParams.get("reactive"),hideUI="true"==urlParams.get("hideui"),rnd=new Random,R=function(){return rnd.random_dec()},tt=function(){return .5<R()},cx=function(){return fr(th)-fv},sdF=function(){return fr(450)+50+"."},segF=function(){return afr(segSa)};var D_S=1e3;let cDiv=document.createElement("div");cDiv.style.width=window.innerWidth+"px",cDiv.style.height=window.innerHeight+"px";var DIM=Math.max(window.innerWidth,window.innerHeight);document.body.style.backgroundColor="#000000";var bVL=.1,M=DIM/1000,tick=0;let tS=0,tS2=0,atk=0,arsdc=0,sfo=!1,palettes=[[[249,222,89],[232,166,40],[249,131,101],[195,49,36],[161,223,251]],[[255,109,105],[254,204,80],[11,231,251],[1,11,139],[30,5,33]],[[233,255,136],[254,10,183],[229,1,133],[17,16,16],[208,204,209]],[[179,231,220],[166,180,1],[239,246,123],[213,1,2],[108,1,2]],[[0,123,0],[36,224,184],[255,204,81],[255,139,118],[255,48,49]],[[169,67,0],[255,176,0],[255,223,0],[91,155,55],[21,61,2]],[[161,5,50],[255,111,169],[255,208,204],[0,183,204],[0,95,129]],[[95,165,90],[1,180,188],[246,213,31],[250,137,37],[250,84,87]],[[99,26,17],[187,96,47],[239,216,131],[203,130,20],[68,64,101]],[[48,4,61],[142,31,81],[229,64,89],[222,131,127],[253,179,106]],[[255,251,196],[182,190,246],[53,30,191],[16,1,93],[10,0,48]],[[140,7,20],[252,64,124],[27,78,136],[5,8,30],[250,240,228]],[[0,0,63],[1,0,142],[144,1,245],[254,0,234],[255,1,120]],[[8,44,68],[114,234,245],[254,230,226],[255,169,76],[254,44,137]],[[1,99,141],[171,206,204],[255,242,205],[255,0,76],[97,13,75]],[[34,125,172],[68,57,136],[159,0,82],[255,63,32],[255,190,0]],[[129,237,247],[0,164,192],[2,116,143],[247,1,16],[110,5,22]],[[255,254,1],[255,134,6],[232,59,54],[96,5,56],[70,10,64]],[[51,51,51],[204,204,204],[48,48,48],[221,221,221],[0,0,0]],[[215,0,95],[215,215,0],[38,38,38],[175,0,95],[0,255,255]],[[85,255,255],[255,85,255],[255,255,85],[170,0,0],[0,0,170]],[[170,0,170],[170,0,0],[255,255,85],[170,85,0],[0,170,0]],[[170,0,0],[170,0,0],[255,85,85],[255,255,85],[85,85,255]],[[255,85,85],[85,255,85],[255,255,85],[85,85,85],[85,255,255]],[[0,0,0],[255,85,255],[85,255,255],[255,0,255],[255,255,255]],[[0,0,0],[0,170,0],[170,0,0],[170,85,0],[0,85,0]],[[116,2,17],[208,169,160],[143,58,96],[195,90,102],[36,0,4]],[[175,212,204],[133,186,106],[26,119,73],[11,46,47],[1,18,28]],[[0,18,68],[0,80,134],[49,143,181],[176,202,199],[247,214,191]],[[140,66,25],[243,149,88],[238,200,176],[241,236,231],[247,217,109]],[[218,210,216],[20,54,66],[15,139,141],[236,154,41],[168,32,26]],[[191,135,9],[234,197,125],[185,187,222],[128,116,144],[82,56,87]],[[44,48,57],[107,54,56],[254,108,58],[254,219,209],[158,172,183]],[[61,82,32],[183,203,153],[119,143,210],[42,55,89],[67,29,50]],[[91,91,91],[195,214,211],[217,201,167],[248,233,214],[244,163,142]]],th=2e3,fv=500,cX=cx(),cY=cx(),c2X=cx(),c2Y=cx(),c3X=cx(),c3Y=cx(),c4X=cx(),c4Y=cx(),c5X=cx(),c5Y=cx(),c6X=cx(),c6Y=cx(),segAa=[5,10,20,50,100,200,250,fv],segC=afr(segAa),segD=afr(segAa),segV0=tt(),segV1=tt(),segV2=tt(),segV3=tt(),co=tt(),ofX=.6<R(),ofY=.6<R(),oXYa=[250,fv,th],oXY={x:afr(oXYa),y:afr(oXYa)},sprA=["5.","10.","20."],spr=afr(sprA),y0=fr(750)+250,y1=fr(750)+250,v12=flr((y0+y1)/2),segSa=[">","<"],segSc0=segF(),segSc1=segF(),segSc2=segF(),segSc3=segF(),irOp=.5<R()?"-":"+",dA=["d",`((st.y + ${y0}.) + d3)/(d/1000.)`,`(((st.x + ${y1}.)/d6) ${irOp} ((st.y + ${v12}.)/.5))`],dI=fr(dA.length),dC=dA[dI],sD=sdF(),sD2=sdF(),sD3=sdF(),sD4=sdF(),sD5=sdF(),sD6=sdF(),pId=flr(R()*palettes.length),palette=palettes[pId],currentPercent=R()*fv+fv,clrs=["c0","c1","c2","c3","c4"],clrsI=["c0","c1","c2","c3","c4"],pA=[],gls=["2","4","6","8","10","12","16"],cOs="",inc=.7<R(),rvA=["100.","200.","250.","500.","1000."],rvV=afr(rvA),rvV2=afr(rvA),iM=!1;2===dI&&(inc=!1),1===dI;let clrsS=fr(15)+15;for(let a=0;a<clrsS;a++)clrsI.push(afr(clrs));for(let a=0;a<clrsI.length;a++)pA.push(currentPercent),currentPercent+=R()*fv+fv;let sT=R();.2>sT?clrsI.sort():.5>sT?clrsI.reverse():.8>sT?clrsI=shuffle(clrsI):sT;let pct,clrsC=clrsI.length,loopCap=10*(200*(50+clrsC));for(let a=0;a<clrsI.length;a++)pct=Math.floor(1e3*(pA[a]/currentPercent))/1e3,cOs+=(0<a?"else if ":"if ")+"(idx < loopPoint * "+pct+") {\n",cOs+="  gloss = "+afr(gls)+".;\n",cOs+="  cIn = "+a+".;\n",cOs+="  c = "+clrsI[a]+";\n",cOs+="}\n";cOs+="else {\n",cOs+="  gl_FragColor = vec4(0.,0.,0.,1.);",cOs+="  return;",cOs+="}\n";let cnA=["cn","cn2","cn3","cn4","cn5","cn6"],cns="";for(let a,b=6;-1<b;b--){a=[];for(let c=0;6>c;c++)b!=c&&a.push(cnA[c]);a=shuffle(a),a.unshift(cnA[(6-b)%6]),cns+="rng = "+fr(6e3)+4e3+".;",cns+="cM = rng * 6.;",cns+="cnP = mod(tick,cM);";for(let b=0;6>b;b++)cns+=(0<b?"else ":"")+(5>b?"if (cnP <= "+(0<b?b+1+". * ":"")+"rng) {\n":"{\n"),cns+="  cnC = "+a[b]+";\n",cns+="  cnD = "+a[(b+1)%6]+";\n",cns+="  p = 1. - ((("+(0<b?b+1+". * ":"")+"rng) - cnP) / rng);\n",cns+="}\n";cns+="  p = 1. - (1. - p) * (1. - p);\n",cns+=a[b]+" = mix(cnC,cnD,p);\n"}let oCB=.9<R(),oCBH=R(),c="";for(let a=0;5>a;a++)c+="vec3 c"+a+" = "+(oCB?"":"rgb2hsv(")+"vec3("+(oCB?oCBH:palette[a][0]+"./255.")+","+(oCB?".8":palette[a][1]+"./255.")+","+(oCB?a/6+.2:palette[a][2]+"./255.")+(oCB?"":")")+");\n";const canvas=document.getElementsByTagName("canvas")[0];canvas.width=DIM,canvas.height=DIM,cDiv.style.position="absolute",cDiv.style.overflow="hidden",canvas.parentElement.appendChild(cDiv),canvas.style.left="50%",canvas.style.top="50%",canvas.style.position="relative",canvas.style.transform="translate(-50%,-50%)",cDiv.appendChild(canvas);const yCul=flr(abs(canvas.offsetTop-DIM/2)/M),xCul=flr(abs(canvas.offsetLeft-DIM/2)/M);let cft,msx,msy,clp,aud,gp,gpA,gpAO,tCa,cD=!0,hl=/\bHeadlessChrome/.test(navigator.userAgent),lft=0,dh=!1,sd=!1,mxyS={x:500,y:500,ip:null},mxyD={x:0,y:0},mxy2={x:0,y:0},mxy2O=0,sstT=0,sstD=0,drg=.97,ac=1.1,k={m:!1,l:!1,r:!1,u:!1,d:!1,sp:!1},ipt=!1,drgO={x:!1,y:!1},audE=reactive,audDP=0,audD=Array(50).fill(0),clkT=0,clkC=0,clkCC=0,att=!0,arsF=!1,fT=18e4,pT=Date.now(),aFT=Date.now(),sqFT=Date.now(),fR=!1,lm={x:0,y:0},tTick=0,sdTA=!1,fd=!1,afv=0,sqfv=0,mdt=0,te={x:0,y:0},pte={x:0,y:0},sq1FT=!1,tra=3.14159/180,sqr="";for(let a,b=0;4>b;b++)a=xCul+55+30*b,sqr+=`(clkC - float(`+(b+1)+`) >= 0. && st.x > float(${xCul}) + float(${a}) && st.x < float(${xCul}) + float(${a+25}))`+(3>b?" || ":")")+"\n";let sqr2="";for(let a,b=0;4>b;b++)a=xCul+55+30*b,sqr2+=`(clkC - float(`+(b+1)+`) >= 0. && st.x > float(${xCul}) + float(${a}) + 23. && st.x < float(${xCul}) + float(${a+25}))`+(3>b?" || ":")")+"\n";const gl=canvas.getContext("webgl"),positionsData=new Float32Array([1,1,-1,1,1,-1,-1,-1]),indices=new Uint16Array([0,1,2,1,2,3]),textureData=new Float32Array([1,1,0,1,1,0,0,0]);var texture=gl.createTexture();const targetTexture=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,targetTexture),texBind();const targetTexture2=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,targetTexture2),texBind();const bT=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,bT),texBind();const cT=gl.createTexture();gl.bindTexture(gl.TEXTURE_2D,cT),texBind();function texBind(){gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,DIM,DIM,0,gl.RGBA,gl.UNSIGNED_BYTE,null),gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR),gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR),gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE),gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE)}const fb=gl.createFramebuffer();gl.bindFramebuffer(gl.FRAMEBUFFER,fb);const indexBuffer=gl.createBuffer();var attachmentPoint=gl.COLOR_ATTACHMENT0,level=0;gl.framebufferTexture2D(gl.FRAMEBUFFER,attachmentPoint,gl.TEXTURE_2D,targetTexture,level);var aDt={},bDt={},bDta={},compositeData={},fDt={};function compileShader(a,b){var c=gl.createShader(b);if(gl.shaderSource(c,a),gl.compileShader(c),!gl.getShaderParameter(c,gl.COMPILE_STATUS))throw"Shader compile failed with: "+gl.getShaderInfoLog(c);return c}function glAB(a,b){gl.activeTexture(a),gl.bindTexture(gl.TEXTURE_2D,b)}function glD(){gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer),gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,indices,gl.STATIC_DRAW),gl.drawElements(gl.TRIANGLES,indices.length,gl.UNSIGNED_SHORT,0)}function drawArt(){gl.useProgram(aPg),gl.bindFramebuffer(gl.FRAMEBUFFER,fb),gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,targetTexture,level),gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(aDt.positionAttribute,2,gl.FLOAT,!1,8,0),gl.enableVertexAttribArray(aDt.positionAttribute),gl.uniform1f(aDt.tickSet,tick),gl.uniform2f(aDt.mxy2,mxy2.x,mxy2.y),gl.uniform4f(aDt.ad0,amplitudes[1]/2,0,0,0),glAB(gl.TEXTURE0,texture),glD()}function blurArt(a,b){gl.useProgram(blPg),gl.bindFramebuffer(gl.FRAMEBUFFER,fb),gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,b,level);var c=gl.FLOAT;gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(bDt.positionAttribute,2,c,!1,0,0),gl.enableVertexAttribArray(bDt.positionAttribute),gl.uniform3f(bDt.d,mxyD.x,mxyD.y,audE?amplitudes[14]/16:0),gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.vertexAttribPointer(bDt.textureAttribute,2,c,!1,0,0),gl.enableVertexAttribArray(bDt.textureAttribute),glAB(gl.TEXTURE0,a),glD()}function blendArt(a,b){gl.useProgram(bldPg),gl.bindFramebuffer(gl.FRAMEBUFFER,fb),gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,b,level);var c=gl.FLOAT;gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(bDta.positionAttribute,2,c,!1,0,0),gl.enableVertexAttribArray(bDta.positionAttribute),glAB(gl.TEXTURE0,a),gl.uniform1i(bDta.freshTexture,0),glAB(gl.TEXTURE1,cT),gl.uniform1i(bDta.cT,1),gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.vertexAttribPointer(bDta.textureAttribute,2,c,!1,0,0),gl.enableVertexAttribArray(bDta.textureAttribute),glD()}function compositeArt(a){gl.useProgram(compositeProgram),gl.bindFramebuffer(gl.FRAMEBUFFER,fb),gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,cT,level);var b=gl.FLOAT;gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(bDta.positionAttribute,2,b,!1,0,0),gl.enableVertexAttribArray(bDta.positionAttribute),gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.vertexAttribPointer(bDta.textureAttribute,2,b,!1,0,0),gl.enableVertexAttribArray(bDta.textureAttribute),glAB(gl.TEXTURE0,a),glD()}function renderFinal(a){gl.useProgram(fPg),gl.bindFramebuffer(gl.FRAMEBUFFER,null);var b=gl.FLOAT;gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(bDta.positionAttribute,2,b,!1,0,0),gl.enableVertexAttribArray(bDta.positionAttribute),gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.vertexAttribPointer(bDta.textureAttribute,2,b,!1,0,0),gl.enableVertexAttribArray(bDta.textureAttribute),hideUI||(gl.uniform1f(fDt.sst,-nAmp),gl.uniform1f(fDt.sqfv,sqfv),gl.uniform1f(fDt.afv,afv),gl.uniform1f(fDt.iM,iM?1:0),gl.uniform1f(fDt.clkC,clkCC)),glAB(gl.TEXTURE0,a),glD()}let blurFSS=`
precision highp float;
varying highp vec2 vTextureCoord;
uniform sampler2D u_texture;
uniform vec3 d;
uniform float M;

void main() {

  vec2 resultCoords = vec2(vTextureCoord.x, vTextureCoord.y);

  float a = texture2D(u_texture, resultCoords).a;
  float dv = max(abs(d.y),abs(d.x));
  vec2 dnorm = normalize(d.xy);

  float r = texture2D(u_texture, resultCoords - (d.xy * .005)).r;
  float g = texture2D(u_texture, resultCoords).g;
  float b = texture2D(u_texture, resultCoords + (d.xy * .005)).b;

  float dvD = dv/200.;

  vec3 c = vec3(r,g,b);
  
  vec2 d2 = vec2(dvD * float(0), -dvD * float(0));
  vec2 d3 = vec2(dvD * float(0), dvD * float(0));
  for (int i = 1; i < 11; i++) {
    d2 += vec2(dvD * float(i), -dvD * float(i));
    d3 += vec2(dvD * float(i), dvD * float(i));
  }
  c += texture2D(u_texture, resultCoords + d2).rgb * (dvD + d.z);
  c += texture2D(u_texture, resultCoords - d2).rgb * (dvD + d.z);
  c += texture2D(u_texture, resultCoords + d3).rgb * (dvD + d.z);
  c += texture2D(u_texture, resultCoords - d3).rgb * (dvD + d.z);
  

  gl_FragColor = vec4(c,1.);
}
`,blurFragmentShader=compileShader("\nprecision highp float;\nvarying highp vec2 vTextureCoord;\nuniform sampler2D u_texture;\nuniform vec3 d;\nuniform float M;\n\nvoid main() {\n\n  vec2 resultCoords = vec2(vTextureCoord.x, vTextureCoord.y);\n\n  float a = texture2D(u_texture, resultCoords).a;\n  float dv = max(abs(d.y),abs(d.x));\n  vec2 dnorm = normalize(d.xy);\n\n  float r = texture2D(u_texture, resultCoords - (d.xy * .005)).r;\n  float g = texture2D(u_texture, resultCoords).g;\n  float b = texture2D(u_texture, resultCoords + (d.xy * .005)).b;\n\n  float dvD = dv/200.;\n\n  vec3 c = vec3(r,g,b);\n  \n  vec2 d2 = vec2(dvD * float(0), -dvD * float(0));\n  vec2 d3 = vec2(dvD * float(0), dvD * float(0));\n  for (int i = 1; i < 11; i++) {\n    d2 += vec2(dvD * float(i), -dvD * float(i));\n    d3 += vec2(dvD * float(i), dvD * float(i));\n  }\n  c += texture2D(u_texture, resultCoords + d2).rgb * (dvD + d.z);\n  c += texture2D(u_texture, resultCoords - d2).rgb * (dvD + d.z);\n  c += texture2D(u_texture, resultCoords + d3).rgb * (dvD + d.z);\n  c += texture2D(u_texture, resultCoords - d3).rgb * (dvD + d.z);\n  \n\n  gl_FragColor = vec4(c,1.);\n}\n",gl.FRAGMENT_SHADER),blendFSS=`
precision highp float;
varying highp vec2 vTextureCoord;
uniform sampler2D freshTexture;
uniform sampler2D compTexture;
void main() {
  vec3 blend0 = texture2D(freshTexture, vTextureCoord).rgb;
  vec3 blend1 = texture2D(compTexture, vTextureCoord).rgb;
  vec3 compBlend = mix(blend0,blend1,.9);
  gl_FragColor = vec4(compBlend ,1.);
}
`,blendFragmentShader=compileShader(blendFSS,gl.FRAGMENT_SHADER),finalFSS=`
precision highp float;
varying highp vec2 vTextureCoord;
uniform sampler2D u_texture;
uniform float sst;
uniform float afv;
uniform float sqfv;
uniform float clkC;
uniform float iM;

void main() {
  vec3 c0 = (vec3(${palette[0][0]}. / 255. ,${palette[0][1]}. / 255. ,${palette[0][2]}.  / 255.));
  vec3 c1 = (vec3(${palette[1][0]}. / 255. ,${palette[1][1]}. / 255. ,${palette[1][2]}. / 255. ));
  vec3 c2 = (vec3(${palette[2][0]}. / 255. ,${palette[2][1]}. / 255. ,${palette[2][2]}. / 255. ));
  vec3 c3 = (vec3(${palette[3][0]}. / 255. ,${palette[3][1]}. / 255. ,${palette[3][2]}.  / 255.));
  vec3 c4 = (vec3(${palette[4][0]}. / 255. ,${palette[4][1]}. / 255. ,${palette[4][2]}.  / 255.));
  

float M = float(${M});
vec3 bar = texture2D(u_texture, vTextureCoord).rgb;
vec2 st = (gl_FragCoord.xy / M);
float v;
if (sst > 0.) {
  v = 500. + (1000. - float(${yCul}) - 515.) * sst;
}
else if (sst < 0.) {
  v = 500. + (float(${yCul}) - 485.) * abs(sst);
}

gl_FragColor = vec4(bar,1.);

if (sst != 0. && afv != 0.) {
  if (st.x > float(${xCul}) + 25. && st.x < float(${xCul}) + 50. && ((st.y > 500. && st.y < v) || (st.y < 500. && st.y > v))) {
    gl_FragColor = vec4(mix(bar,vec3(1.,1.,1.),afv),1.);
    if (st.x > float(${xCul}) + 48. && st.x < float(${xCul}) + 50. && ((st.y > 500. && st.y < v) || (st.y < 500. && st.y > v))) {
      gl_FragColor = vec4(mix(bar,vec3(0.,0.,0.),afv),1.);
    }
  }
}

if (iM == 1. && st.x > 441. && st.x < 559. && st.y > float(${yCul}) + 13. && st.y < float(${yCul}) + 62. ) {
  gl_FragColor = vec4(mix(bar,vec3(0.,0.,0.),sqfv),1.);
  
  if (st.x > 443. && st.x < 557. && st.y > float(${yCul}) + 15. && st.y < float(${yCul}) + 60. ) {

    gl_FragColor = vec4(mix(bar,vec3(1.,1.,1.),sqfv),1.);


    if ((st.x > 450.5 && st.x < 479.5 && st.y > float(${yCul}) + 23. && st.y < float(${yCul}) + 52.) || 
    (st.x > 485.5 && st.x < 514.5 && st.y > float(${yCul}) + 23. && st.y < float(${yCul}) + 52.) || 
    (st.x > 520.5 && st.x < 549.5 && st.y > float(${yCul}) + 23. && st.y < float(${yCul}) + 52.)) {
      gl_FragColor = vec4(mix(bar,vec3(0.,0.,0.),sqfv),1.);
    }

    if (st.x > 452.5 && st.x < 477.5 && st.y > float(${yCul}) + 25. && st.y < float(${yCul}) + 50.) {
      gl_FragColor = vec4(bar,1.);
      if (clkC > 0. && clkC <= 3.) {
        gl_FragColor = vec4(mix(bar,vec3(1.,1.,1.),sqfv),1.);
        if (st.x > 452.5 + 8. && st.x < 477.5 - 8. && st.y > float(${yCul}) + 25. + 8. && st.y < float(${yCul}) + 50. - 8.) {
          gl_FragColor = vec4(mix(bar,vec3(0.,0.,0.),sqfv),1.);
        }
      }
    }
    if (st.x > 487.5 && st.x < 512.5 && st.y > float(${yCul}) + 25. && st.y < float(${yCul}) + 50.) {
      gl_FragColor = vec4(bar,1.);
      if (clkC > 1. && clkC <= 3.) {
        gl_FragColor = vec4(mix(bar,vec3(1.,1.,1.),sqfv),1.);
        if (st.x > 487.5 + 8. && st.x < 512.5 - 8. && st.y > float(${yCul}) + 25. + 8. && st.y < float(${yCul}) + 50. - 8.) {
          gl_FragColor = vec4(mix(bar,vec3(0.,0.,0.),sqfv),1.);
        }
      }
    }
    if (st.x > 522.5 && st.x < 547.5 && st.y > float(${yCul}) + 25. && st.y < float(${yCul}) + 50.) {
      gl_FragColor = vec4(bar,1.);
      if (clkC == 3.) {
        gl_FragColor = vec4(mix(bar,vec3(1.,1.,1.),sqfv),1.);
        if (st.x > 522.5 + 8. && st.x < 547.5 - 8. && st.y > float(${yCul}) + 25. + 8. && st.y < float(${yCul}) + 50. - 8.) {
          gl_FragColor = vec4(mix(bar,vec3(0.,0.,0.),sqfv),1.);
        }
      }
    }
  }
}

}
`,finalFragmentShader=compileShader(finalFSS,gl.FRAGMENT_SHADER),baseVertexString=`
attribute vec2 position;
attribute vec2 texcoord;
varying highp vec2 vTextureCoord;
void main() {
  gl_Position = vec4(position, 0.0, 1.0);
  vTextureCoord = texcoord;
}
`,baseVertShader=compileShader(baseVertexString,gl.VERTEX_SHADER),compFragmentShaderString=`
precision highp float;
varying highp vec2 vTextureCoord;
uniform sampler2D u_texture;
void main() {
  gl_FragColor = texture2D(u_texture, vTextureCoord);
}
`,compFragmentShader=compileShader(compFragmentShaderString,gl.FRAGMENT_SHADER),artFragmentString=`
precision highp float;
uniform float tick;
uniform vec2 mxy2;
uniform vec4 ad0;
uniform vec4 ad1;
uniform vec4 ad2;
uniform vec4 ad3;

vec3 hsv2rgb(vec3 c)
{
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
vec3 rgb2hsv(vec3 c)
{
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));

    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

void main()
{
  ${c}
  vec3 c5 = vec3(0.,0.,0.);

  float w = float(${DIM});
  float M = float(${M});
  vec2 st0 = (gl_FragCoord.xy / M);
  vec2 st = (gl_FragCoord.xy / M);
  


  if (st.x < float(${xCul}) || st.x > 1000. - float(${xCul}) || st.y <  float(${yCul}) || st.y > 1000. - float(${yCul})) {
    return;
  }

  if (${segV2} && st.x ${segSc0} 500.) {
    st.x = 1000. - st.x;
  }

  if (${segV0} && mod(st.x, ${segC}.) ${segSc1} (${segC}./2.)) {
    st.x = (st.x + (${segC}./2.)) - ${segC}.;
  }

  if (${segV3} && st.y ${segSc2} 500.) {
    st.y = 1000. - st.y;
  }

  if (${segV1} && mod(st.y, ${segD}.) ${segSc3} (${segD}./2.)) {
    st.y = (st.y + (${segD}./2.)) - ${segD}.;
  }
  
  if(${ofX}){
    st.x = abs((${oXY.y}. - st.y) - (${oXY.x}. - st.x));
  }
  if(${ofY}){
    st.y = abs((${oXY.x}. - st.x) - (${oXY.y}. - st.y));
  }

  
  st0.y += 2. * mxy2.y;

  vec2 cn = vec2(${cX}. + (ad0.x - .5) * 200.,${cY}. + (ad0.y - .5) * 200.);
  vec2 cn2 = vec2(${c2X}. + (ad0.y - .5) * 200.,${c2Y}. + (ad0.z - .5) * 200.);
  vec2 cn3 = vec2(${c3X}. + (ad0.z - .5) * 200.,${c3Y}. + (ad0.w - .5) * 200.);
  vec2 cn4 = vec2(${c4X},${c4Y});
  vec2 cn5 = vec2(${c5X},${c5Y});
  vec2 cn6 = vec2(${c6X},${c6Y});

  vec2 cnC;
  vec2 cnD;
  float p;
  float rng;
  float cM;
  float cnP;

  ${cns}

  cn = (cn + mxy2);
  
  float d = floor(distance(cn,st));
  float d2 = floor(distance(cn2,st));
  float d3 = floor(distance(cn3,st));
  float d4 = floor(distance(cn4,st));
  float d5 = floor(distance(cn5,st));
  float d6 = floor(distance(cn6,st));
  
  float d0 = (distance(cn,st0));
  float d02 = (distance(cn2,st0));
  float d03 = (distance(cn3,st0));
  float d04 = (distance(cn4,st0));
  float d05 = (distance(cn5,st0));
  float d06 = (distance(cn6,st0));


  d = (d + d2 + d3 + d4 + d5 + d6) / (1. + mxy2.y);  
  d0 = (d0 + d02 + d03 + d04 + d05 + d06) / (1. + mxy2.y);

  d = (d+d02)/2.;
  d2 = (d2+d03)/2.;
  d3 = (d3+d04)/2.;
  d4 = (d4+d05)/2.;
  d5 = (d5+d06)/2.;
  d6 = (d6+d0)/2.;

  d = (d+d2)/2.;
  d2 = (d2+d3)/2.;
  d3 = (d3+d4)/2.;
  d4 = (d4+d5)/2.;
  d5 = (d5+d6)/2.;
  d6 = (d6+d)/2.;

  if (${co}) {
    d = floor(d/${sD}) * ${sD} + mxy2.y;
    d2 = floor(d2/${sD}) * ${sD} + mxy2.y;
    d3 = floor(d3/${sD}) * ${sD} + mxy2.y;
    d4 = floor(d4/${sD}) * ${sD} + mxy2.y;
    d5 = floor(d5/${sD}) * ${sD} + mxy2.y;
    d6 = floor(d6/${sD}) * ${sD} + mxy2.y;
  }
  
  if (${inc}) {
    st.x = abs(${dC} - st0.x) / ${spr} + (mxy2.y);
  }
  else {
    st.x = abs(${dC} - st.x) / ${spr} + (mxy2.y);
  }
  
  float idx = (${dC}  * 2.) / (100. * 20.);
  idx += floor(${dC} / 100.) + abs(st.x - st.y) * (5. + (mxy2.y * 10.));
  idx *= mod(abs(st.x - st.y), .5 + (mxy2.y/4.));
  idx += floor(st.x/(10. + mxy2.y)) * d6;
  idx += st.x + st.y + mxy2.y;

  idx *= 10.;
  idx *= 1.1;
  
  if (${dC} < 500.) {
  }

  float s0 = floor((st.x + 100.) / 100.);
  float s1 = floor((st.y + 50.) / 50.);
  float s2 = floor((${dC} + 50.) / 50.);
  idx += (s0 - s1) * ((1. - (ad0.y + ad0.z)/2.) * 1000.);
  idx -= s2 * 50.;


  idx /= (st.x / st.y - ${dC}) * .001;
  if (${dI} == 1) {
    idx += (tick * 20.);
  }
  if (${dI} == 2) {
    idx += (tick * 60.);
  }
  else {
    if (${co}) {
      idx += (tick * floor(40. - ${clrsC}. / 5.));
    }
    else {
      idx += (tick * 20.);
    }
  }

  vec3 c;
  float cIn;
  float idxO = 40.;
  
  idxO = 200.;

  float loopCap = 100. + ${clrsC}.;
  float loopPoint = loopCap * idxO * 5.;

  loopPoint += (ad0.z + ad0.w)/2. * (loopPoint/2.);
  

  idx = mod(abs(idx),loopPoint);

  float gloss = 0.;
  ${cOs}
  
  c.z += (cIn/(${clrsC}.)) * 1.75;
  c.z -= mod(abs(st.y - st.x),1.4) * .15;
  gloss *= 3.5 + abs(ad0.x * 10.);
  if (mod((idx/500.),mod((abs(st.x - st.y) * 500.),500.)) >= 50.) {
    gl_FragColor = vec4(hsv2rgb(vec3(c.x,c.y,c.z * abs(-1. - mod((${dC} - 500.),5.)) * (st.y + 1000.)/500.)) - d * d2/200. / gloss/20.,1.);
  }
  else {
    gl_FragColor = vec4(hsv2rgb(vec3(c.x,c.y,c.z * abs(-1. - mod((${dC} - 500.),5.)) * (st.x + 1000.)/500.)) - d * d2/200. / gloss/20.,1.);
  }
  gl_FragColor += vec4(hsv2rgb(vec3(c.x + ((st.y - st.x) * .15),c.y,c.z + ((${dC} + (st.x/10.))/10.) * .0001)),0.);
  gl_FragColor *= vec4(.1,.1,.1,1.);
  gl_FragColor *= vec4(hsv2rgb(vec3(c.x + (mod(${dC},100. + mxy2.y)/50.),c.y - (mod(${dC},100.)/50.),c.z * 1.8)),1.);
  
}
`;var artFragmentShader=compileShader(artFragmentString,gl.FRAGMENT_SHADER);function cpr(a){let b=gl.createProgram();return gl.attachShader(b,baseVertShader),gl.attachShader(b,a),gl.linkProgram(b),b}function gPP(a,b){if(!gl.getProgramParameter(a,gl.LINK_STATUS))throw console.error(gl.getProgramInfoLog(aPg)),new Error("Failed to link "+b+" program")}const aPg=cpr(artFragmentShader),blPg=cpr(blurFragmentShader),bldPg=cpr(blendFragmentShader),compositeProgram=cpr(compFragmentShader),fPg=cpr(finalFragmentShader);gPP(aPg,"art"),gPP(blPg,"blur"),gPP(bldPg,"blend"),gPP(compositeProgram,"composite"),gPP(fPg,"final");const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.bufferData(gl.ARRAY_BUFFER,positionsData,gl.STATIC_DRAW);var texcoordBuffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.bufferData(gl.ARRAY_BUFFER,textureData,gl.STATIC_DRAW),aDt.positionAttribute=gl.getAttribLocation(aPg,"position"),aDt.mxy=gl.getUniformLocation(aPg,"mxy"),aDt.mxy2=gl.getUniformLocation(aPg,"mxy2"),aDt.ad0=gl.getUniformLocation(aPg,"ad0"),aDt.tickSet=gl.getUniformLocation(aPg,"tick"),bDt.positionAttribute=gl.getAttribLocation(blPg,"position"),bDt.textureAttribute=gl.getAttribLocation(blPg,"texcoord"),bDt.d=gl.getUniformLocation(blPg,"d"),bDta.positionAttribute=gl.getAttribLocation(bldPg,"position"),bDta.textureAttribute=gl.getAttribLocation(bldPg,"texcoord"),bDta.cT=gl.getUniformLocation(bldPg,"compTexture"),bDta.freshTexture=gl.getUniformLocation(bldPg,"freshTexture"),fDt.positionAttribute=gl.getAttribLocation(fPg,"position"),fDt.textureAttribute=gl.getAttribLocation(fPg,"texcoord"),fDt.positionAttribute=gl.getAttribLocation(fPg,"position"),fDt.sst=gl.getUniformLocation(fPg,"sst"),fDt.afv=gl.getUniformLocation(fPg,"afv"),fDt.sqfv=gl.getUniformLocation(fPg,"sqfv"),fDt.clkC=gl.getUniformLocation(fPg,"clkC"),fDt.iM=gl.getUniformLocation(fPg,"iM");const keys={KeyM:"m",Space:"sp",ArrowLeft:"l",ArrowRight:"r",ArrowUp:"u",ArrowDown:"d",KeyA:"l",KeyD:"r",KeyW:"u",KeyS:"d"};function tCD(){iM?imclk():(cD?tTick=tick:tick=tTick,cD=!cD,iM=!cD,iM&&(clkC=0,clkCC=audE?3-clkC:clkC,sqfv=1))}function frR(){fR=!1,tS=0,pT=Date.now()}function draw(){if(cft=Date.now(),cD||gp)if(hl)drawArt(),blendArt(targetTexture,bT),compositeArt(bT),renderFinal(cT),tick++;else if(100>cft-lft){if(cD||gpC(),cD){if(tCa=(cft-lft)/16,audE){const c=analyser.getValue(),d=atk;for(let e=0;e<amplitudes.length;e++){const f=amplitudes[e],a=-100,g=-50,h=Math.max(a,Math.min(g,c[e])),i=inverseLerp(a,g,h),b=1e-4+(1.99-1e-4)*(-sstT+1)/2;amplitudes[e]=(amplitudes[e]+spring(f,i,250,d))/2*b}for(let a=0;a<amplitudes.length-1;a++)amplitudes[a]=(amplitudes[a]+amplitudes[a+1])/2,amplitudes[a]=flr(1e3*amplitudes[a])/1e3}audE||fO||fR||!(cft-pT>=fT)||(fR=!0),fR&&(lm.x=2*Math.sin(tS*tra),lm.y=-.25*Math.sin(tS*tra),mxyD.x=lm.x,mxyD.y=lm.y,360<=tS?frR():tS+=tCa/2),cD&&(handleInput(),drawArt(),0!=mxyD.x||0!=mxyD.y?(blurArt(targetTexture,targetTexture2),blendArt(targetTexture2,bT)):blendArt(targetTexture,bT),compositeArt(bT)),renderFinal(cT),aud=0,audE&&(aud=3*(amplitudes[1]+amplitudes[3]+amplitudes[7]+amplitudes[10]),0!=amplitudes[2]&&(mxyD.x=2*(amplitudes[1]+amplitudes[2]+amplitudes[5]+amplitudes[9])),0==audD[0]?audD.fill(0):(audD[audDP]=amplitudes[1],audDP++,audDP%=audD.length),0!=amplitudes[0]&&(mxy2.y=mxy2O-average(audD,0,50))),sq1FT&&(sq1FT=!1)}sdTA&&(2<=tS/60?(sdTA=!1,fd=!0,aFT=Date.now(),tS=0):tS+=tCa),fd&&(0>=afv?(tS=0,fd=!1):(afv=lerp(1,0,tS/60),tS+=tCa)),(!sfo||cD)&&(atk+=tCa,tick+=(0>mxyD.x?-1:1)*abs(mxyD.x)**2+aud+tCa,atk=atk>loopCap?0:atk,tick=tick>loopCap?0:tick)}(iM||3==clkCC)&&(renderFinal(cT),1<=arsdc/60?(sfo=!0,arsdc=0,tS2=0):arsdc+=tCa,sfo&&(0>=sqfv?(sfo=!1,iM=!1,clkC=0,clkCC=clkC):(sqfv=lerp(1,0,tS2/30),tS2+=tCa))),lft=cft,requestAnimationFrame(draw)}function d(a){a.preventDefault(),mdt=Date.now(),mxyD={x:0,y:0},deltaX=0,deltaY=0,sd=!0,dh=!1,fd=!1,null!=a.touches&&(a=a.touches[0]),audE&&(sdTA=!1),msx=a.clientX,msy=a.clientY,msx=(msx-canvas.offsetLeft)/DIM*D_S+500,msy=(msy-canvas.offsetTop)/DIM*D_S+500,pte.x=msx,pte.y=msy,mxyS={x:msx,y:msy,ip:"m"}}function u(a){a.preventDefault(),null==a.touches?(msy=a.clientY,msy=(msy-canvas.offsetTop)/DIM*D_S+500):(msy=te.y,msy=(msy-canvas.offsetTop)/DIM*D_S+500),dv=0,sd=!1,audE&&(sdTA=!0,tS=0,aFT=Date.now()),dh?cD=!0:200>Date.now()-mdt&&tCD()}function m(a){a.preventDefault(),null!=a.touches&&(a=a.touches[0]),msx=a.clientX,msy=a.clientY,msx=(msx-canvas.offsetLeft)/DIM*D_S+500,msy=(msy-canvas.offsetTop)/DIM*D_S+500,te.x=msx,te.y=msy,audE||!sd||cD||(cD=!0),sd&&0!=msx-mxyS.x&&0!=msy-mxyS.Y&&(dh=!0),!audE&&sd?mxyD={x:(msx-mxyS.x)/100,y:(msy-mxyS.y)/100}:audE&&sd&&cD&&(afv=1,clp=(nAmp+te.y-pte.y)/1e3,-1<clp&&1>clp&&(sstD+=te.y-pte.y,aDlt((te.y-pte.y)/1e3),sstT=clamp(sstD/1e3,-1,1))),pte.x=msx,pte.y=msy}cae("touchstart",d),cae("mousedown",d),cae("touchend",u),cae("mouseup",u),cae("touchmove",m),cae("mousemove",m),document.addEventListener("keyup",a=>{k[keys[a.code]]=!1,!audE||k.d&&k.u||(sdTA=!0,sT=0,aFT=Date.now())}),document.addEventListener("keydown",a=>{"Space"!==a.code||k.sp||(tCD(),k.sp=!0);let b=!1;a.code in keys&&!k[keys[a.code]]&&(b=!0,k[keys[a.code]]=!0)}),window.addEventListener("gamepadconnected",a=>{gp=a.gamepad,gp.buttonStates=[],gp.an=!1;for(let b=0;b<gp.buttons.length;b++)gp.buttonStates.push(!1)}),window.addEventListener("gamepaddisconnected",a=>{gp==a.gamepad&&(gp=null)});function clamp(a,b,c){return a>c?c:a<b?b:a}function shuffle(a){for(let b,c=a.length;0!=c;)b=flr(R()*c),c--,[a[c],a[b]]=[a[b],a[c]];return a}function imclk(){reactive||(frR(),clkC++,clkCC=audE?3-clkC:clkC,sfo=!1,arsdc=0,sqfv=1,3==clkC&&(clkC=0,audE=!audE,cD=!0,audE?(Tone.context.resume(),mxy2O=mxy2.y):(afv=0,sdTA=!1,fd=!1,amplitudes.fill(0),pT=Date.now())))}function gpC(){if(gp)for(let a=0;a<gp.buttons.length;a++)gp.buttons[a].pressed&&!gp.buttonStates[a]?(gp.buttonStates[a]=!0,tCD()):gp.buttons[a].pressed||(gp.buttonStates[a]=!1)}let nAmp=0;function aDlt(a){nAmp=Math.min(Math.max(nAmp+a,-1),1)}function handleInput(){gp&&(!audE&&(.1>Math.max(abs(gp.axes[0]),abs(gp.axes[2]))&&.1>Math.max(abs(gp.axes[1]),abs(gp.axes[3]))?(ipt=!1,gp.an=!1):(ipt=!0,gp.an=!0,mxyD.x+=(abs(gp.axes[0])>abs(gp.axes[2])?gp.axes[0]:gp.axes[2])/100,mxyD.y+=(abs(gp.axes[1])>abs(gp.axes[3])?gp.axes[1]:gp.axes[3])/100)),gpC()),audE?(cD&&(k.u||k.d)&&(sdTA=!1,fd=!1,afv=1,clp=(nAmp+(k.u?-2:k.d?2:0))/500,-1<clp&&1>clp&&(aDlt((k.u?-2:k.d?2:0)/500),sstD+=k.u?-2:k.d?2:0,sstT=clamp(sstD/500,-1,1))),gp&&(gpA=flr(100*(abs(gp.axes[1])>abs(gp.axes[3])?gp.axes[1]:gp.axes[3]))/100,.2<abs(gpA)?(sdTA=!1,fd=!1,afv=1,clp=(nAmp+gpA)/250,-1<clp&&1>clp&&(sstD+=gpA,aDlt(gpA/250),sstT=clamp(sstD/250,-1,1))):!(sd||k.l||k.r||k.u||k.d)&&!sdTA&&(sdTA=!0,tS=0,aFT=Date.now()))):(k.l&&(mxyD.x+=-.01),k.r&&(mxyD.x+=.01),k.u&&(mxyD.y+=-.01),k.d&&(mxyD.y+=.01));audE||(ipt=sd||k.l||k.r||k.u||k.d,drgO.x=!k.l&&!k.r,drgO.y=!k.u&&!k.d,(gp&&gp.an||ipt)&&fR&&frR(),(gp&&gp.an||ipt||fR)&&(mxy2.x+=mxyD.x/1e3,mxy2.y+=mxyD.y/1e3),(gp&&!gp.an||!gp)&&!sd&&(drgO.x||drgO.y)&&(mxyD.x*=drgO.x?drg:1,mxyD.y*=drgO.y?drg:1,drgO.x&&.05>abs(mxyD.x)&&(mxyD.x=0),drgO.y&&.05>abs(mxyD.y)&&(mxyD.y=0)),mxyD.x=clamp(mxyD.x,-5,5),mxyD.y=clamp(mxyD.y,-5,5))}let analyser=new Tone.Analyser("fft",16);amplitudes=Array(analyser.size).fill(0);const fft=new Tone.FFT,mic=new Tone.UserMedia().connect(fft);mic.open().then(()=>{fft.connect(analyser)}).catch(()=>{});function lerp(a,b,c){return a*(1-c)+b*c}function inverseLerp(a,b,c){return 1e-10>abs(a-b)?0:(c-a)/(b-a)}function spring(c,a,b,d){return lerp(c,a,1-Math.exp(-b*d))}function average(a,b,c){if(c<=b)return 0;let d=0;for(let e=b;e<c;e++)d+=a[e];return d/(c-b)}requestAnimationFrame(draw);
