let w,h,pix=1,s,c,pg,pg2,img,sh,f,g,k,frameMod,pgStr,hyperMeter,blurShader,blurShader2,seed,contChooser,celColChooser,onOffChooser,sqChooser,sqTriChooser,borderStr,monoChooser,darkSat,darkHue,contStr,uOctave,monoStr,coun=0,shaderChooser,shaderChooser2,rect1X,rect1Y,rect1W,rect1H,rect2X,rect2Y,border,triChooser,blockChooser,blockColor,blockColor2,sqStr,stopCount=1,fr,dirC,durC,bgMult,eW,minDim,R,seedCounter1,seedCounter2,seedCounter3,theVertex=`
#ifdef GL_ES
precision highp float;
#endif
attribute vec3 aPosition;
attribute vec2 aTexCoord;
varying vec2 vTexCoord;
void main() {
  vTexCoord = aTexCoord;
  vec4 positionVec4 = vec4(aPosition, 1.0);
  positionVec4.xy = positionVec4.xy * 2.0 - 1.0;
  gl_Position = positionVec4;
}
`,b1Frag=`
precision highp float;
#define PI 3.14159265359
varying vec2 vTexCoord;
uniform sampler2D uTexture0;
uniform float u_time;
uniform vec2 uResolution;
uniform float u_octave;
uniform float u_fbmAmp;
uniform float u_roundness;
uniform float u_angleC;
highp float random(vec2 co)
{
    highp float a = 12.9898;
    highp float b = 78.233;
    highp float c = 43758.5453;
    highp float dt= dot(co.xy ,vec2(a,b));
    highp float sn= mod(dt,3.14);
    return fract(sin(sn) * c);
}
float noise (in vec2 st) {
    vec2 i = floor(st);
    vec2 fu = fract(st);
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    vec2 u = fu * fu * (3.0 - 2.0 * fu);
    return mix(a, b, u.x) +
            (c - a)* u.y * (1.0 - u.x) +
            (d - b) * u.x * u.y;
}
#define OCTAVES 4
float fbm (in vec2 st) {
    // Initial values
    float value = 0.0;
    float amplitude = 0.25;
    float frequency = 0.1;
    for (int i = 0; i < OCTAVES; i++) {
        value += amplitude* noise(st);
        st *= u_octave + u_time/100.0;
        amplitude *= .45;
    }
    return value;
}
float fbm6( in vec2 p )
{
    vec2 q = vec2( fbm( p + vec2(0.0,u_roundness) ),fbm( p + vec2(0.0,2.0) ) );
    vec2 r = vec2( fbm( p + 4.0*q + vec2(4.0,3.0)),fbm( p + 4.0*q + vec2(u_angleC * 4.0,0.0)));
    return fbm( p + u_fbmAmp* r ); // 2.0, 6.0
}
void main() {
  vec2 st = gl_FragCoord.xy/uResolution.xy;
  vec2 uv = vTexCoord;
  uv.y = 1.0 - uv.y;
  vec2 texelSize = 1.0 / uResolution;
  vec2 offset;
  float scale = 0.1;
  float offset2 = 0.1;
  float angle;
  angle = noise(st + uv * 0.2) * PI * 2.0; //0.01 0.4
  float radius = offset2;
  st *= scale;
  st *= radius * vec2(fract(angle *  st.x), fract(angle / st.y));
  offset = texelSize  * vec2(4.0,4.0) - fbm6(uv) + 0.18;
  vec4 color = vec4(0.0);
  float div;
  color += texture2D(uTexture0, uv + vec2(offset.y, st.y)); 
  color += texture2D(uTexture0, uv + vec2(-offset.y, st.y)); 
  color += texture2D(uTexture0, uv + vec2(-offset.x, st.x)); 
  color += texture2D(uTexture0, uv + vec2(offset.x, st.x));
  color += texture2D(uTexture0, uv + vec2(offset.y, -st.y)); 
  color += texture2D(uTexture0, uv + vec2(-offset.y, -st.y)); 
  color += texture2D(uTexture0, uv + vec2(-offset.x, -st.x)); 
  color += texture2D(uTexture0, uv + vec2(offset.x, -st.x)); 
  div = 8.0;
  color /= div;           
  gl_FragColor = color;
}
`,b2Frag=`
precision highp float;
#define PI 3.14159265359
varying vec2 vTexCoord;
uniform sampler2D uTexture0;
uniform float u_time;
uniform vec2 uResolution;
uniform float u_octave;
uniform float u_fbmAmp;
uniform float u_roundness;
uniform float u_angleC;
highp float random(vec2 co)
{
    highp float a = 12.9898;
    highp float b = 78.233;
    highp float c = 43758.5453;
    highp float dt= dot(co.xy ,vec2(a,b));
    highp float sn= mod(dt,3.14);
    return fract(sin(sn) * c);
}
float noise (in vec2 st) {
    vec2 i = floor(st);
    vec2 fu = fract(st);
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    vec2 u = fu * fu * (3.0 - 2.0 * fu);
    return mix(a, b, u.x) +
            (c - a)* u.y * (1.0 - u.x) +
            (d - b) * u.x * u.y;
}
#define OCTAVES 4
float fbm (in vec2 st) {
    // Initial values
    float value = 0.0;
    float amplitude = 0.25;
    float frequency = 0.1;
    for (int i = 0; i < OCTAVES; i++) {
        value += amplitude* noise(st);
        st *= u_octave + u_time/100.0;
        amplitude *= .45;
    }
    return value;
}
float fbm6( in vec2 p ){
    vec2 q = vec2( fbm( p + vec2(0.0,u_roundness) ),fbm( p + vec2(0.0,2.0) ) );
    vec2 r = vec2( fbm( p + 4.0*q + vec2(4.0,3.0)),fbm( p + 4.0*q + vec2(u_angleC * 4.0,0.0)));
    return fbm( p + u_fbmAmp* r );
}
void main() {
  vec2 st = gl_FragCoord.xy/uResolution.xy;
  vec2 uv = vTexCoord;
  uv.y = 1.0 - uv.y;
  vec2 texelSize = 1.0 / uResolution;
  vec2 offset;
  float scale = 0.1;
  float offset2 = 0.1;
  float angle;
  angle = noise(st + uv * 0.2) * PI * 2.0; //0.01 0.4
  float radius = offset2;
  st *= scale;
  st *= radius * vec2(fract(angle *  st.x), fract(angle / st.y));
  offset = texelSize  * vec2(4.0,4.0) - fbm6(uv) + 0.18;
  vec4 color = vec4(0.0);
  float div;
  color += texture2D(uTexture0, uv + vec2(offset.y, st.y)); 
  color += texture2D(uTexture0, uv + vec2(-offset.y, st.y)); 
  color += texture2D(uTexture0, uv + vec2(-offset.x, st.x)); 
  color += texture2D(uTexture0, uv + vec2(offset.x, st.x)); 
  color += texture2D(uTexture0, uv + vec2(offset.y, -st.y)); 
  color += texture2D(uTexture0, uv + vec2(-offset.y, -st.y)); 
  color += texture2D(uTexture0, uv + vec2(-offset.x, -st.x)); 
  color += texture2D(uTexture0, uv + vec2(offset.x, -st.x)); 
  div = 8.0;
  color /= div;      
  gl_FragColor = color;
}
`,pixFrag=`
#ifdef GL_ES
precision highp float;  
#endif
uniform vec2 resolution;
uniform sampler2D pg;
uniform sampler2D pg2;
uniform sampler2D img;
uniform float ak;
uniform float dirX;
uniform float dirY;
uniform float pgC;
uniform float dur;
uniform float onOff;
uniform float celCol;
uniform float contC;
uniform float satOn;
vec3 rgb2hsv(vec3 c) {
  vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
  vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
  vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
  float d = q.x - min(q.w, q.y);
  float e = 1.0e-10;
  return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
  vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
  vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
  return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
void main() {
    vec2 uv = gl_FragCoord.xy / resolution;
    uv.y = 1. - uv.y;
    vec2 offset;
    vec2 pgCol;
    if(pgC == 1.){
     offset = vec2(texture2D(pg2, uv).r * ak) * vec2(1./resolution.x, 1./resolution.y);
     pgCol = vec2(texture2D(pg, uv) );
    }else if(pgC == 2.){
     offset = vec2(texture2D(pg, uv).r * ak) * vec2(1./resolution.x, 1./resolution.y);
     pgCol = vec2(texture2D(pg2, uv) ) ;
    }else if(pgC == 3.){
     offset = vec2(texture2D(pg2, uv).r * ak) * vec2(1./resolution.x, 1./resolution.y);
     pgCol = vec2(texture2D(pg2, uv) - texture2D(pg, uv));
    }
    if(pgCol.x < .1) offset.x *= -1.;
    else offset.x *= dirX;
    if(pgCol.y < .1) offset.y *= -1.;
    else  offset.y *= dirY;
    vec3 c = texture2D(img, uv+offset).rgb;
    if(dur == 1.0){
    if(onOff == 0.){
    c += texture2D(img, uv+offset).rgb;
    c -= texture2D(img, uv-offset).rgb;
    }
    }
    if(celCol > 0.65){
      if(c.r + c.g + c.b < .1) c = vec3(0.0);
    }else if(celCol > 0.45){
      if(c.r + c.g + c.b < .1) c = vec3(0.0);
      else if(c.r + c.g + c.b < 0.2) c = vec3(200., 127., 0.)/255.;//Yellow
    }else if(celCol > 0.15){
      if(c.r + c.g + c.b < .1) c = vec3(0.0);
      else if(c.r + c.g + c.b < 0.2) c = vec3(10., 127., 255.)/255.;//Blue
    }else{
      if(c.r + c.g + c.b < .1) c = vec3(0.0);
      else if(c.r + c.g + c.b < 0.2) c = vec3(36., 120., 36.)/255.;//Green
    }
    if(dur == 1.0){
    if(onOff == 1.){
    c += texture2D(img, uv+offset).rgb;
    c -= texture2D(img, uv-offset).rgb;
    }
    }
    if(satOn == 1.0){
    vec3 hsv = rgb2hsv(c.rgb);
    hsv.y *= 1.01;
    c.rgb = hsv2rgb(hsv);
    }
    if(contC < 0.45){
    c.rgb = ((c.rgb - vec3(0.5)) * 1.05 + vec3(0.5));
    }
    gl_FragColor = vec4(c, 1.);
  }
`;function setup(){noiseSeed(seed=99999999*(R=new Random).random_dec()),randomSeed(seed),w=windowWidth,h=windowHeight,bgMult=w>1500?2:w>1e3?1.5:1,c=createCanvas(w,h,WEBGL),pixelDensity(pix),(f=createGraphics(w,h)).pixelDensity(pix),f.colorMode(HSB,360,100,100,1),f.background(0,0,10),f.rectMode(CENTER),(pg=createGraphics(w,h)).pixelDensity(pix),pg.noStroke(),(pg2=createGraphics(w,h)).pixelDensity(pix),pg2.noStroke(),(g=createGraphics(w,h,WEBGL)).pixelDensity(pix),g.colorMode(HSB,360,100,100,1),g.background(0,0,80),(k=createGraphics(w,h,WEBGL)).colorMode(HSB,360,100,100,1),k.background(30,8,90),k.pixelDensity(pix),(img=createGraphics(w,h)).pixelDensity(pix),img.imageMode(CENTER),img.colorMode(HSB,360,100,100,1),img.rectMode(CENTER),sh=createShader(theVertex,pixFrag),blurShader=g.createShader(theVertex,b1Frag),blurShader2=k.createShader(theVertex,b2Frag),pgCh=random([1,2,3,1,2]);let e=[20,50,100,100,20,50];frameMod=e[floor(random(e.length))],minDim=min(width,height),s=random([minDim/20,minDim/20,minDim/10,minDim/10,minDim/3.33,minDim/5]),pgCh=random([1,2,3,1,2]),onOffChooser=random([0,1,0,0]),celColChooser=random(1),contChooser=R.random_dec(),shaderChooser=random(1),shaderChooser2=random(1),triChooser=random(1),blockChooser=R.random_dec(),sqTriChooser=R.random_dec(),dirC=random(1),durC=random(1),monoChooser=R.random_dec(),celColChooser=1,monoChooser<.25&&(monoStr="mono",contChooser=0),contChooser<.45&&(contStr="cont"),"mono"==monoStr&&(dirC=random([1,1,0,1,1])),pgStr=255,hyperMeter=random([4,8,8,8,12,12,8,8,4,4])/2,frameRate(fr=random([30,25,25,25,30,25])),sqChooser=random(1),darkHue=random([0,180,40,220,90,150,200,280,320]),darkSat="mono"==monoStr?0:80,eW=min(width,height)/8;for(let o=0;o<3e4;o++){let r=random(width),t=random(height);noise(.01*r,.01*t),f.noFill(),f.stroke(0,0,90,1),f.strokeWeight(random(.5,1)),f.ellipse(r,t,random(eW)),f.noFill(),f.stroke(darkHue,darkSat,10,1),f.ellipse(r+random(-10,10),t+random(-10,10),random(eW))}noiseSeed(seed),randomSeed(seed),shader(sh),sh.setUniform("resolution",[w*pix,h*pix]),sh.setUniform("pg",pg),sh.setUniform("pg2",pg2),sh.setUniform("img",f),sh.setUniform("ak",random([1,10,5,20])),sh.setUniform("dirX",random([-1,1,0,0])),sh.setUniform("dirY",random([-1,1,0,0])),sh.setUniform("pgC",pgCh),sh.setUniform("onOff",onOffChooser),sh.setUniform("celCol",celColChooser),sh.setUniform("contC",contChooser),sh.setUniform("satOn",1),img.image(f,w/2,h/2),uSqr=0,roundInt=4,uAmp=random(.25,.35),uOctave=round(random(1,2.5),roundInt),uFbmAmp=round(random(30,80),roundInt),uAngleC=round(random(1),roundInt),uAmp2=random(.25,.35),uOctave2=round(random(1,2.5),roundInt),uFbmAmp2=round(random(30,80),roundInt),uAngleC2=round(random(1),roundInt),sqChooser<.5?(rect1X=width/2,rect1Y=random([height/4,height-height/4]),rect1W=width,rect1H=height/random(1.9,2.1),sqStr="yatay",sqTriChooser<.5&&(rect1X=width/2,rect1Y=height/8,rect1W=width,rect1H=height/3.333,rect2X=width/2,rect2Y=height-height/8)):(rect1X=random([width/4,width-width/4]),rect1Y=height/2,rect1W=width/random(1.9,2.1),rect1H=height,sqStr="dikey",sqTriChooser<.5&&(rect1X=width/8,rect1Y=height/2,rect1W=width/3.333,rect1H=height,rect2X=width-width/8,rect2Y=height/2)),blockColor=255,blockColor2=255,0==(border=random([1,1,1,1,1,1]))&&(borderStr="no"),seedCounter1=0,seedCounter2=0,seedCounter3=0}function draw(){let e=(random(w/s)^frameCount/s)*s,o=(random(h/s)^frameCount/s)*s;if(pg.fill(random([0,127,255]),random([0,127,255]),0),pg.rect(e^o,o,2*s,2*s),pg2.fill(random([20,50,100]),2*random([20,50,100]),0),yamuk(e^o,o,2*s,2*s),1==border&&(pg2.push(),pg2.fill(blockColor),blockChooser>.4?(yamuk(rect1X,rect1Y,rect1W,rect1H),sqTriChooser<.5&&(pg2.fill(blockColor2),yamuk(rect2X,rect2Y,rect1W,rect1H))):blockChooser>.2?pg2.ellipse(width/2,height/2,height/1.25):tri(),pg2.pop()),blurShader.setUniform("uTexture0",pg),blurShader.setUniform("u_time",millis()/1e3),blurShader.setUniform("uResolution",[width*pix,height*pix]),blurShader.setUniform("u_amp",uAmp),blurShader.setUniform("u_octave",uOctave),blurShader.setUniform("u_fbmAmp",uFbmAmp),blurShader.setUniform("u_angleC",uAngleC),blurShader.setUniform("u_sqr",uSqr),g.noStroke(),g.shader(blurShader),g.translate(-width/2,-height/2),g.rect(0,0,width,height),blurShader2.setUniform("uTexture0",pg2),blurShader2.setUniform("u_time",millis()/1e3),blurShader2.setUniform("uResolution",[width*pix,height*pix]),blurShader2.setUniform("u_amp",uAmp2),blurShader2.setUniform("u_octave",uOctave2),blurShader2.setUniform("u_fbmAmp",uFbmAmp2),blurShader2.setUniform("u_angleC",uAngleC2),blurShader2.setUniform("u_sqr",uSqr),k.noStroke(),k.shader(blurShader2),k.translate(-width/2,-height/2),k.rect(0,0,width,height),img.image(c,w/2,h/2),frameCount%frameMod==0){let r=random([minDim/40,minDim/25,minDim/10,minDim/40,minDim/25,minDim/100,minDim/10,minDim/10,minDim/5]);blockColor=random([0,255,255,255]),blockColor2=random([0,255,255,255]);for(let t=0;t<h;t+=r)for(let $=0;$<w;$+=r)pg.fill(random([0,127,86]),random([0,127,86]),0),pg.rect($,t,2*r,2*r);if(1==(seedCounter1+=1)){let i=99999999*R.random_dec();noiseSeed(i),randomSeed(i),seedCounter1=0}if(sh.setUniform("ak",random([1,10,5,15,10,5,10,10,5,1])),dirC<.15&&(sh.setUniform("dirX",random([-1,1,0,0])),sh.setUniform("dirY",random([-1,1,0,0]))),"cont"==contStr){for(let u=0;u<10/bgMult;u++)for(let l=0;l<width;l++){let n=random(width),a=random(height),_=noise(.01*n,.01*a)/50;img.noFill(),img.stroke(darkHue,random([0,darkSat]),random([10,90,90,0]),2*_),img.strokeWeight(random(.5,1)),img.ellipse(n,a,random(100))}if(1==(seedCounter2+=1)){let m=99999999*R.random_dec();noiseSeed(m),randomSeed(m),seedCounter2=0}"mono"==monoStr?sh.setUniform("dur",random([1,0,0])):sh.setUniform("dur",random([1,0,0,0]))}else sh.setUniform("dur",random([1,0,0,0,0,0,0]))}if(frameCount%(frameMod*hyperMeter)==0){sh.setUniform("dirX",random([-1,1,0,0,0])),sh.setUniform("dirY",random([-1,1,0,0,0])),sh.setUniform("satOn",random([1,0,0]));for(let v=0;v<10/bgMult;v++)for(let d=0;d<1*width;d++){let p=random(width),x=random(height),b=noise(.01*p,.01*x)/50;img.noFill(),img.stroke(darkHue,random([0,darkSat]),random([0,100,100,90,0]),2*b),img.strokeWeight(random(.5,1)),img.ellipse(p,x,random(100))}if(1==(seedCounter3+=1)){let C=99999999*R.random_dec();noiseSeed(C),randomSeed(C),seedCounter3=0}"cont"==contStr?sh.setUniform("dur",1):sh.setUniform("dur",random([1,0,0,0]))}if(mouseIsPressed&&1==(coun+=1)){blockColor=255,blockColor2=255,sh.setUniform("dur",1),sh.setUniform("celCol",celColChooser),sh.setUniform("dirX",random([-1,1,0,0])),sh.setUniform("dirY",random([-1,1,0,0]));for(let y=0;y<5;y++)for(let S=0;S<1*width;S++){let D=random(width),U=random(height),T=noise(.01*D,.01*U)/50;img.noFill(),img.stroke(darkHue,darkSat,random([0,100,100,90]),2*T),img.strokeWeight(random(.5,1)),img.ellipse(D,U,random(100))}coun=0}shaderChooser2<.65?sh.setUniform("pg",g):sh.setUniform("pg",pg),sh.setUniform("img",img),shaderChooser<.65?sh.setUniform("pg2",k):blockChooser>.2?sh.setUniform("pg2",pg2):sh.setUniform("pg2",k),sh.setUniform("time",millis()),quad(-1,-1,1,-1,1,1,-1,1)}function yamuk(e,o,r,t){pg2.beginShape(),pg2.noStroke();let $=min(r,t)/7;pg2.vertex(e-r/2+random(-$,$),o-t/2+random(-$,$)),pg2.vertex(e-r/4+random(-$,$),o-t/2+random(-$,$)),pg2.vertex(e+random(-$,$),o-t/2+random(-$,$)),pg2.vertex(e+r/4+random(-$,$),o-t/2+random(-$,$)),pg2.vertex(e+r/2+random(-$,$),o-t/2+random(-$,$)),pg2.vertex(e+r/2+random(-$,$),o-t/4+random(-$,$)),pg2.vertex(e+r/2+random(-$,$),o+random(-$,$)),pg2.vertex(e+r/2+random(-$,$),o+t/4+random(-$,$)),pg2.vertex(e+r/2+random(-$,$),o+t/2+random(-$,$)),pg2.vertex(e+r/4+random(-$,$),o+t/2+random(-$,$)),pg2.vertex(e+random(-$,$),o+t/2+random(-$,$)),pg2.vertex(e-r/4+random(-$,$),o+t/2+random(-$,$)),pg2.vertex(e-r/2+random(-$,$),o+t/2+random(-$,$)),pg2.vertex(e-r/2+random(-$,$),o+t/4+random(-$,$)),pg2.vertex(e-r/2+random(-$,$),o+random(-$,$)),pg2.vertex(e-r/2+random(-$,$),o-t/4+random(-$,$)),pg2.endShape()}function yamukF(e,o,r,t){f.beginShape(),f.noStroke();let $=r/2;f.vertex(e-r/2+random(-$,$),o-t/2+random(-$,$)),f.vertex(e+r/2+random(-$,$),o-t/2+random(-$,$)),f.vertex(e+r/2+random(-$,$),o+t/2+random(-$,$)),f.vertex(e-r/2+random(-$,$),o+t/2+random(-$,$)),f.endShape()}function tri(){pg2.beginShape(),pg2.noStroke(),triChooser<.5?(pg2.vertex(0,0),pg2.vertex(width,0),pg2.vertex(width,height)):(pg2.vertex(0,0),pg2.vertex(0,height),pg2.vertex(width,0)),pg2.endShape()}function keyPressed(){" "==key&&((stopCount+=1)%2==0?frameRate(0):frameRate(fr)),"s"==key&&saveCanvas("AestheticsOfFailure_DistCollective","png")}class Random{constructor(){this.useA=!1;let e=function(e){let o=parseInt(e.substr(0,8),16),r=parseInt(e.substr(8,8),16),t=parseInt(e.substr(16,8),16),$=parseInt(e.substr(24,8),16);return function(){t|=0;let e=((o|=0)+(r|=0)|0)+($|=0)|0;return $=$+1|0,o=r^r>>>9,r=t+(t<<3)|0,t=(t=t<<21|t>>>11)+e|0,(e>>>0)/4294967296}};this.prngA=new e(tokenData.hash.substr(2,32)),this.prngB=new e(tokenData.hash.substr(34,32));for(let o=0;o<1e6;o+=2)this.prngA(),this.prngB()}random_dec(){return this.useA=!this.useA,this.useA?this.prngA():this.prngB()}}