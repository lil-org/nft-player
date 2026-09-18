class Random{constructor(){this.useA=!1;let a=function(e){let f=parseInt(e.substr(0,8),16),g=parseInt(e.substr(8,8),16),h=parseInt(e.substr(16,8),16),i=parseInt(e.substr(24,8),16);return function(){f|=0,g|=0,h|=0,i|=0;let a=0|(0|f+g)+i;return i=0|i+1,f=g^g>>>9,g=0|h+(h<<3),h=h<<21|h>>>11,h=0|h+a,(a>>>0)/4294967296}};this.prngA=new a(tokenData.hash.substr(2,32)),this.prngB=new a(tokenData.hash.substr(34,32));for(let a=0;1e6>a;a+=2)this.prngA(),this.prngB()}random_dec(){return this.useA=!this.useA,this.useA?this.prngA():this.prngB()}}function fr(a){return flr(R()*a)}function frMM(a,b){return flr(R()*(b-a))+a}function rMM(a,b){return R()*(b-a)+a}function afr(b){return b[fr(b.length)]}function abs(a){return Math.abs(a)}function flr(a){return Math.floor(a)}function cae(a,b){canvas.addEventListener(a,b)}let rnd=new Random,R=function(){return rnd.random_dec()};var D_S=1e3;let cDiv=document.createElement("div");cDiv.style.width=window.innerWidth+"px",cDiv.style.height=window.innerHeight+"px";var DIM=Math.max(window.innerWidth,window.innerHeight);document.body.style.backgroundColor="#000000";var M=DIM/1000,tick=0;let x0=rMM(-.5,1.5),y0=rMM(-.5,.5),x1=rMM(-.5,.5),y1=rMM(-.5,.5),mOff0=frMM(2,80),mOff1=frMM(2,80),xF=.5<R(),xF1=.5<R(),yF=.5<R(),yF1=.5<R(),fl0=.5<R(),fl1=.5<R(),sspr0=frMM(10,500),sspr1=frMM(10,500),divA=[50,100,200,333,500,666,1e3],divV0=afr(divA),divV1=afr(divA),cncpA=[`mod(d,float(${divV0})) * (float(${mOff0})/float(${sspr0}))`,`mod(st.x,float(${divV0})) * (float(${mOff0})/float(${sspr0}))`,`d/float(${sspr0})`,`st.x/float(${sspr0})`],cncpB=[`mod(d2,float(${divV0})) * (float(${mOff0})/float(${sspr1}))`,`mod(st.y,float(${divV1})) * (float(${mOff1})/float(${sspr1}))`,`d2/float(${sspr1})`,`st.y/float(${sspr1})`],cncpAV=afr(cncpA),cncpBV=afr(cncpB),aM0=[`(1000. + d2 + d)/10.`,`(1000. + d)/10.`,`1000. - st.x`,`abs(500. - st.x)`,`abs(st.x - st.y)`],aM0V=afr(aM0),aM1=[`1000. - st.y - d2`,`(1000. + d2)/10.`,`1000. - st.y`,`abs(500. - st.y)`,`abs(st.y - st.x)`],aM1V=afr(aM1),lsA=[`abs(float(${x0}) - resultCoords.x) * p;`,`abs(float(${y0}) - resultCoords.y) * p;`,`abs(float(${x0}) + float(${y0}) - resultCoords.x - resultCoords.y) * p;`,`abs(float(${y0}) + float(${x0}) - resultCoords.y - resultCoords.x) * p;`,`distance(resultCoords,vec2(float(${x0}),float(${y0}))) * p`,`distance(resultCoords,vec2(float(${x0}),float(${y0}))) * distance(resultCoords,vec2(float(${x1}),float(${y1}))) * p`],lsAV=afr(lsA),mvOA=[`abs(1000. - d) + 1000. - mod(st.y,1000.)`,`abs(st.x - d) + 1000. - mod(d,1000.)`,`abs(st.x - d) + 1000. - abs(st.y - d)`,`abs(st.y - d) + 1000. - mod(d,1000.)`,`abs(1000. - d + d2) + 1000. - mod(st.x,1000.)`,`abs(1000. - d + d2) + 1000. - mod(st.x - st.y,1000.)`,`abs(1000. - st.x) + 1000. - mod((st.x / st.y) * 1000.,1000.)`,`abs(1000. - st.y) + 1000. - mod((st.x / st.y) * 1000.,1000.)`,`abs(1000. - d) + 1000. - mod((st.x / st.y) * 1000.,1000.)`,`abs(1000. - d + st.x) + 1000. - mod((st.x / st.y) * 1000.,1000.)`,`abs(1000. - d + st.y) + 1000. - mod((st.x / st.y) * 1000.,1000.)`],mvOAV=afr(mvOA),bldD0=R(),bldD1=R(),bldT=frMM(1,4),palettes=[[[255,109,105],[254,204,80],[11,231,251],[1,11,139],[30,5,33]],[[233,255,136],[254,10,183],[229,1,133],[17,16,16],[208,204,209]],[[161,5,50],[255,111,169],[255,208,204],[0,183,204],[0,95,129]],[[99,26,17],[187,96,47],[239,216,131],[203,130,20],[68,64,101]],[[48,4,61],[142,31,81],[229,64,89],[222,131,127],[253,179,106]],[[255,251,196],[182,190,246],[53,30,191],[16,1,93],[10,0,48]],[[140,7,20],[252,64,124],[27,78,136],[5,8,30],[250,240,228]],[[0,0,63],[1,0,142],[144,1,245],[254,0,234],[255,1,120]],[[8,44,68],[114,234,245],[254,230,226],[255,169,76],[254,44,137]],[[1,99,141],[171,206,204],[255,242,205],[255,0,76],[97,13,75]],[[34,125,172],[68,57,136],[159,0,82],[255,63,32],[255,190,0]],[[129,237,247],[0,164,192],[2,116,143],[247,1,16],[110,5,22]],[[255,254,1],[255,134,6],[232,59,54],[96,5,56],[70,10,64]],[[51,51,51],[204,204,204],[48,48,48],[221,221,221],[0,0,0]],[[215,0,95],[215,215,0],[38,38,38],[175,0,95],[0,255,255]],[[0,0,0],[255,85,255],[85,255,255],[255,0,255],[255,255,255]],[[116,2,17],[208,169,160],[143,58,96],[195,90,102],[36,0,4]],[[175,212,204],[133,186,106],[26,119,73],[11,46,47],[1,18,28]],[[0,18,68],[0,80,134],[49,143,181],[176,202,199],[247,214,191]],[[140,66,25],[243,149,88],[238,200,176],[241,236,231],[247,217,109]],[[191,135,9],[234,197,125],[185,187,222],[128,116,144],[82,56,87]],[[44,48,57],[107,54,56],[254,108,58],[254,219,209],[158,172,183]],[[91,91,91],[195,214,211],[217,201,167],[248,233,214],[244,163,142]],[[204,119,34],[0,0,0],[227,66,52],[255,255,255],[227,38,54]]],pId=flr(R()*palettes.length),palette=palettes[pId],fv=500,currentPercent=R()*fv+fv,clrs=["c0","c1","c2","c3","c4"],clrsI=["c0","c1","c2","c3","c4"],pA=[],gls=["2","4","6","8","10","12","16"],cOs="",clrsS=fr(15)+15;for(let a=0;a<clrsS;a++)clrsI.push(afr(clrs));for(let a=0;a<clrsI.length;a++)pA.push(currentPercent),currentPercent+=R()*fv+fv;let sT=R();.2>sT?clrsI.sort():.5>sT?clrsI.reverse():.8>sT?clrsI=shuffle(clrsI):sT;let pct,clrsC=clrsI.length,loopCap=10*(200*(50+clrsC));for(let a=0;a<clrsI.length;a++)pct=Math.floor(1e3*(pA[a]/currentPercent))/1e3,cOs+=(0<a?"else if ":"if ")+"(idx < loopPoint * "+pct+") {\n",cOs+="  gloss = "+afr(gls)+".;\n",cOs+="  cIn = "+a+".;\n",cOs+="  c = "+clrsI[a]+";\n",cOs+="}\n";cOs+="else {\n",cOs+="  gl_FragColor = vec4(0.,0.,0.,1.);",cOs+="  return;",cOs+="}\n";let c="";for(let a=0;5>a;a++)c+="vec3 c"+a+" = rgb2hsv(vec3("+palette[a][0]+"./255.,"+palette[a][1]+"./255.,"+palette[a][2]+"./255.));\n";let crgb="";for(let a=0;5>a;a++)crgb+="vec3 c"+a+" = vec3("+palette[a][0]+"./255.,"+palette[a][1]+"./255.,"+palette[a][2]+"./255.);\n";let stOSx=fr(-1e3,1e3),stOSy=fr(-1e3,1e3);const canvas=document.createElement('canvas');document.body.appendChild(canvas);canvas.width=DIM,canvas.height=DIM,cDiv.style.position="absolute",cDiv.style.overflow="hidden",canvas.parentElement.appendChild(cDiv),canvas.style.left="50%",canvas.style.top="50%",canvas.style.position="relative",canvas.style.transform="translate(-50%,-50%)",cDiv.appendChild(canvas);const yCul=flr(abs(canvas.offsetTop-DIM/2)/M),xCul=flr(abs(canvas.offsetLeft-DIM/2)/M);let cft,cD=!0,hl=/\bHeadlessChrome/.test(navigator.userAgent),lft=0;const gl=canvas.getContext("webgl"),positionsData=new Float32Array([1,1,-1,1,1,-1,-1,-1]),indices=new Uint16Array([0,1,2,1,2,3]),textureData=new Float32Array([1,1,0,1,1,0,0,0]),base=gl.createTexture();texBind(base);const blended=gl.createTexture();texBind(blended);const composited=gl.createTexture();texBind(composited);const reprocessed=gl.createTexture();texBind(reprocessed);const drawn=gl.createTexture();texBind(drawn);function texBind(a){gl.bindTexture(gl.TEXTURE_2D,a),gl.texImage2D(gl.TEXTURE_2D,0,gl.RGBA,DIM,DIM,0,gl.RGBA,gl.UNSIGNED_BYTE,null),gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MIN_FILTER,gl.LINEAR),gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_MAG_FILTER,gl.LINEAR),gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_S,gl.CLAMP_TO_EDGE),gl.texParameteri(gl.TEXTURE_2D,gl.TEXTURE_WRAP_T,gl.CLAMP_TO_EDGE)}const fb=gl.createFramebuffer();gl.bindFramebuffer(gl.FRAMEBUFFER,fb);const indexBuffer=gl.createBuffer();var attachmentPoint=gl.COLOR_ATTACHMENT0,level=0,type=gl.FLOAT;function compileShader(a,b){var c=gl.createShader(b);if(gl.shaderSource(c,a),gl.compileShader(c),!gl.getShaderParameter(c,gl.COMPILE_STATUS))throw"Shader compile failed with: "+gl.getShaderInfoLog(c);return c}function glAB(a,b){gl.activeTexture(a),gl.bindTexture(gl.TEXTURE_2D,b)}function glD(){gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER,indexBuffer),gl.bufferData(gl.ELEMENT_ARRAY_BUFFER,indices,gl.STATIC_DRAW),gl.drawElements(gl.TRIANGLES,indices.length,gl.UNSIGNED_SHORT,0)}let baseVertexString=`
attribute vec2 position;
attribute vec2 texcoord;
varying highp vec2 vTextureCoord;
void main() {
  gl_Position = vec4(position, 0.0, 1.0);
  vTextureCoord = texcoord;
}
`,baseVertShader=compileShader("\nattribute vec2 position;\nattribute vec2 texcoord;\nvarying highp vec2 vTextureCoord;\nvoid main() {\n  gl_Position = vec4(position, 0.0, 1.0);\n  vTextureCoord = texcoord;\n}\n",gl.VERTEX_SHADER);function cpr(a){let b=gl.createProgram();return gl.attachShader(b,baseVertShader),gl.attachShader(b,a),gl.linkProgram(b),b}let fsn0=`precision highp float;
uniform float tick;

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

vec2 wrapAround(vec2 point) {
  return mod(point, vec2(1000.,1000.));
}

void main()
{
    ${c}

    float w = float(${DIM});
    float M = float(${M});
    vec2 st0 = floor((gl_FragCoord.xy / M));
    vec2 st = floor(gl_FragCoord.xy / M);

    st.x = floor(st.x/1.);
    st.y = floor(st.y/1.);

    float j = floor(st.x/w);
    float i = floor(st.y/w);

    if (st0.x < float(${xCul}) || st0.x > 1000. - float(${xCul}) || st0.y < float(${yCul}) || st0.y > 1000. - float(${yCul})) {
    return;
    }

    vec2 cn = vec2(500.,500.);
    cn = wrapAround(vec2(cn.x + float(${stOSx}),cn.y + float(${stOSy})));
    vec2 cn2 = vec2(700.,500.);
    vec2 cn3 = vec2(-200.,500.);
    vec2 cn4 = vec2(800.,200.);
    vec2 cnC;
    vec2 cnD;
    float p;
    float rng;
    float cM;
    float cnP;

    float d = (distance(cn,st));
    float d2 = (distance(cn2,st));
    float d3 = (distance(cn3,st));
    float d4 = (distance(cn4,st));
    float d0 = (distance(cn,st0));

    float tp;
    float dur = 2000.;
    float phase = mod((tick),dur);
    if (phase < (dur/2.)) {
    tp = phase / (dur/2.);
    }
    else {
    tp = (dur - phase) / (dur/2.);
    }

    tp = tp < 0.5 ? 2. * tp * tp : 1. - pow(-2. * tp + 2., 2.) / 2.;

   float a = ${cncpAV};
   float b = ${cncpBV};
    a += ${aM0V};
    b += ${aM1V};

  float idx = st.y * d;
  idx += (a * (1. - tp) + b * tp) * ${mvOAV};
 idx /= 2000.;
  idx += (tick * .75);
  idx = floor(idx);

  vec3 c;
  float cIn;
  float idxO = 200.;

  float loopCap = 100. + ${clrsC}.;
  float loopPoint = loopCap * 16.;
  idx = mod(abs(idx),loopPoint);

  float gloss = 0.;
  ${cOs}
  gl_FragColor = vec4(hsv2rgb(vec3(c.x + (mod(d - (st.x/100.),1000.)/2000.),c.y,c.z)),1.);
  gl_FragColor = vec4(hsv2rgb(vec3(c.x + (mod(floor(st0.x/500.) * 1.,1000.)/1000.),c.y,c.z - abs((500. - st0.x)/1000.))),1.);


  if (st.x < 500.) {
  }

  gl_FragColor = vec4(hsv2rgb(vec3(c.x,c.y,c.z)),1.);
  
}`;var spg0=compileShader(fsn0,gl.FRAGMENT_SHADER);const cspg0=cpr(spg0);let so0={positionAttribute:gl.getAttribLocation(cspg0,"position"),textureAttribute:gl.getAttribLocation(cspg0,"texcoord"),tick:gl.getUniformLocation(cspg0,"tick")};function rf0(){gl.useProgram(cspg0),gl.bindFramebuffer(gl.FRAMEBUFFER,fb),gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,drawn,level),gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(so0.positionAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so0.positionAttribute),gl.uniform1f(so0.tick,tick),glAB(gl.TEXTURE0,base),glD()}let fsn1=`precision highp float;
varying highp vec2 vTextureCoord;
uniform sampler2D u_texture;

void main() {
  ${crgb}
  vec2 resultCoords = vec2(vTextureCoord.x, vTextureCoord.y);
  
  gl_FragColor = texture2D(u_texture, resultCoords);

  float d0 = length(gl_FragColor.rgb - c0);
  float md = sqrt(3.0);
  float p = (md - d0) / md;

  if (p > .95) {
    resultCoords.y = 1. - resultCoords.y;
  }

  d0 = length(gl_FragColor.rgb - c1);
  p = (md - d0) / md;
if (float(${bldT}) == 1. && mod(  floor(  distance(resultCoords,vec2(${bldD0},${bldD1})) * (8. * p)   )   ,2.  ) == 0. &&  p >= .95) {
  resultCoords.x = 1. - resultCoords.x;
 }
 if (float(${bldT}) == 2. && mod(  floor(  abs(resultCoords.x - ${bldD0}) * (8. * p)   )   ,2.  ) == 0. &&  p >= .95) {
  resultCoords.x = 1. - resultCoords.x;
 }
 if (float(${bldT}) == 3. && mod(  floor(  abs(resultCoords.y - ${bldD1}) * (10. * p)   )   ,2.  ) == 0. &&  p >= .95) {
  resultCoords.x = 1. - resultCoords.x;
 }


    gl_FragColor = texture2D(u_texture, resultCoords);
    gl_FragColor.xyz *= ${lsAV};

  if (p > .95) {
    gl_FragColor *= 10.;
  }

  d0 = length(gl_FragColor.rgb - c1);
  p = (md - d0) / md;

  if (p >= .95) {
    gl_FragColor *= .2;
  }
  gl_FragColor.w = 1.;
}`;var spg1=compileShader(fsn1,gl.FRAGMENT_SHADER);const cspg1=cpr(spg1);let so1={positionAttribute:gl.getAttribLocation(cspg1,"position"),textureAttribute:gl.getAttribLocation(cspg1,"texcoord")};function rf1(){gl.useProgram(cspg1),gl.bindFramebuffer(gl.FRAMEBUFFER,fb),gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,reprocessed,level),gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(so1.positionAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so1.positionAttribute),gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.vertexAttribPointer(so1.textureAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so1.textureAttribute),glAB(gl.TEXTURE0,drawn),glD()}let fsn2=`precision highp float;
varying highp vec2 vTextureCoord;

uniform sampler2D tx0;
uniform sampler2D tx1;


void main() {
  vec3 blend0 = texture2D(tx0, vTextureCoord).rgb;
  vec3 blend1 = texture2D(tx1, vTextureCoord).rgb;
  vec3 compBlend = mix(blend0,blend1,.95);
  gl_FragColor = vec4(compBlend ,1.);
}`;var spg2=compileShader("precision highp float;\nvarying highp vec2 vTextureCoord;\n\nuniform sampler2D tx0;\nuniform sampler2D tx1;\n\n\nvoid main() {\n  vec3 blend0 = texture2D(tx0, vTextureCoord).rgb;\n  vec3 blend1 = texture2D(tx1, vTextureCoord).rgb;\n  vec3 compBlend = mix(blend0,blend1,.95);\n  gl_FragColor = vec4(compBlend ,1.);\n}",gl.FRAGMENT_SHADER);const cspg2=cpr(spg2);let so2={positionAttribute:gl.getAttribLocation(cspg2,"position"),textureAttribute:gl.getAttribLocation(cspg2,"texcoord"),tx0:gl.getUniformLocation(cspg2,"tx0"),tx1:gl.getUniformLocation(cspg2,"tx1")};function rf2(){gl.useProgram(cspg2),gl.bindFramebuffer(gl.FRAMEBUFFER,fb),gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,blended,level),gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(so2.positionAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so2.positionAttribute),gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.vertexAttribPointer(so2.textureAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so2.textureAttribute),gl.uniform1i(so2.tx0,0),gl.uniform1i(so2.tx1,1),glAB(gl.TEXTURE0,reprocessed),glAB(gl.TEXTURE1,composited),glD()}let fsn3=`precision highp float;
varying highp vec2 vTextureCoord;
uniform sampler2D u_texture;



void main() {
  vec2 resultCoords = vec2(vTextureCoord.x, vTextureCoord.y);
  gl_FragColor = texture2D(u_texture, resultCoords);
}`;var spg3=compileShader("precision highp float;\nvarying highp vec2 vTextureCoord;\nuniform sampler2D u_texture;\n\n\n\nvoid main() {\n  vec2 resultCoords = vec2(vTextureCoord.x, vTextureCoord.y);\n  gl_FragColor = texture2D(u_texture, resultCoords);\n}",gl.FRAGMENT_SHADER);const cspg3=cpr(spg3);let so3={positionAttribute:gl.getAttribLocation(cspg3,"position"),textureAttribute:gl.getAttribLocation(cspg3,"texcoord")};function rf3(){gl.useProgram(cspg3),gl.bindFramebuffer(gl.FRAMEBUFFER,fb),gl.framebufferTexture2D(gl.FRAMEBUFFER,gl.COLOR_ATTACHMENT0,gl.TEXTURE_2D,composited,level),gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(so3.positionAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so3.positionAttribute),gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.vertexAttribPointer(so3.textureAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so3.textureAttribute),glAB(gl.TEXTURE0,blended),glD()}let fsn4=`precision highp float;
varying highp vec2 vTextureCoord;
uniform sampler2D u_texture;

uniform float tick;


void main() {
  vec2 resultCoords = vec2(vTextureCoord.x, vTextureCoord.y);
  vec2 resultCoords0 = vec2(vTextureCoord.x, vTextureCoord.y);

  float tp;
  float dur = 2000.;
  float phase = mod((tick),dur);
  if (phase < (dur/2.)) {
    tp = phase / (dur/2.);
  }
  else {
    tp = (dur - phase) / (dur/2.);
  }

  tp = tp < 0.5 ? 2. * tp * tp : 1. - pow(-2. * tp + 2., 2.) / 2.;



  float rsx = resultCoords.x;

  if (abs(resultCoords.x + .25 - resultCoords.y) <= .75) {
  }

  if (${xF} && abs(resultCoords.x) <= .5) {
    resultCoords.x = 1. - resultCoords.x;
  }
  else if (${xF1} && abs(resultCoords.x - resultCoords.y + .5) <= .5) {
    resultCoords.x = 1. - resultCoords.x;
  }

  if (${yF} && abs(resultCoords.y) >= .5) {
    resultCoords.y = 1. - resultCoords.y;
  }
  else if (${yF1} && abs(resultCoords.y - resultCoords.x + .5) <= .5) {
    resultCoords.y = 1. - resultCoords.y;
  }

  gl_FragColor = texture2D(u_texture, resultCoords);
  
  float a = abs(.5 - resultCoords.y);
  float b = abs(.5 - resultCoords.x);

  float intV = (a * (1. - tp) + b * tp);
  
  vec4 color2 = texture2D(u_texture, vec2(resultCoords.x + .1,resultCoords.y + .1));
  color2 += texture2D(u_texture, vec2(1. - resultCoords0.x,1. - resultCoords0.y));
  gl_FragColor = mix(gl_FragColor,color2,intV);
  gl_FragColor.xyz *= 3.2 + intV;
  gl_FragColor.xyz *= .3;
  gl_FragColor.w = 1.;
}`;var spg4=compileShader(fsn4,gl.FRAGMENT_SHADER);const cspg4=cpr(spg4);let so4={positionAttribute:gl.getAttribLocation(cspg4,"position"),textureAttribute:gl.getAttribLocation(cspg4,"texcoord"),tick:gl.getUniformLocation(cspg4,"tick")};function rf4(){gl.useProgram(cspg4),gl.bindFramebuffer(gl.FRAMEBUFFER,null),gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.vertexAttribPointer(so4.positionAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so4.positionAttribute),gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.vertexAttribPointer(so4.textureAttribute,2,type,!1,0,0),gl.enableVertexAttribArray(so4.textureAttribute),gl.uniform1f(so4.tick,tick),glAB(gl.TEXTURE0,composited),glD()}const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer),gl.bufferData(gl.ARRAY_BUFFER,positionsData,gl.STATIC_DRAW);var texcoordBuffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,texcoordBuffer),gl.bufferData(gl.ARRAY_BUFFER,textureData,gl.STATIC_DRAW);function render(){rf0(),rf1(),rf2(),rf3(),rf4()}function draw(){cft=Date.now(),cD&&(hl?(render(),tick++):100>cft-lft&&(cD&&(tCa=(cft-lft)/16,render()),tick+=tCa)),lft=cft,requestAnimationFrame(draw)}function clamp(a,b,c){return a>c?c:a<b?b:a}function shuffle(a){for(let b,c=a.length;0!=c;)b=flr(R()*c),c--,[a[c],a[b]]=[a[b],a[c]];return a}function average(a,b,c){if(c<=b)return 0;let d=0;for(let e=b;e<c;e++)d+=a[e];return d/(c-b)}requestAnimationFrame(draw);