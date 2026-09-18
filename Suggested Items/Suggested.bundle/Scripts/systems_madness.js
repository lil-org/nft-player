// 
// åπ∆®£w °ı• ß|ªπ†°n and Claudia Hart 2023
//

let bodiesEmerge;
let flowerGraphics;
let theViewFromThisRoom;

const movementFromTheirFlesh = `precision highp float;varying vec2 vPos;attribute vec3 aPosition;attribute vec2 aTexCoord;uniform mat4 uModelViewMatrix;uniform mat4 uProjectionMatrix;varying vec2 vTexCoord;void main(void) {vPos = (gl_Position = vec4(aPosition,1.0)).xy;vec4 positionVec4 = vec4(aPosition, 1.0);gl_Position = uProjectionMatrix * uModelViewMatrix * positionVec4;vTexCoord = aTexCoord;}`;
const movementFromTheirSkin = `precision highp float;varying vec2 vTexCoord;uniform sampler2D theWall;uniform sampler2D theFigureInTheWall;varying vec2 vPos;uniform float w;uniform float h;uniform vec2 u_resolution;uniform vec2 u_mouse;uniform float u_time;uniform float noiseSeed;uniform float noiseAmount;uniform float lookingBackAtMe;uniform float lookingBackAtHerself;const mat2 m = mat2( 0.80,  0.60, -0.60,  0.80 );float hash( float n ){return fract(sin(n)*43758.5453);}float noise( in vec2 x ){vec2 p = floor(x);vec2 f = fract(x);f = f*f*(3.0-2.0*f);float n = p.x + p.y*57.0;return mix(mix( hash(n+  0.0), hash(n+  1.0),f.x),mix( hash(n+ 57.0), hash(n+ 58.0),f.x),f.y);}float fbm( vec2 p ){float f = 0.0;f += 0.50000*noise( p ); p = m*p*2.02;f += 0.25000*noise( p ); p = m*p*2.03;f += 0.12500*noise( p ); p = m*p*2.01;f += 0.06250*noise( p ); p = m*p*2.04;f += 0.03125*noise( p );return f/0.984375;}float noisey(vec2 p) {return fract(sin(dot(p.xy, vec2(12.9898, 78.233))) * 43758.5453);}vec2 radialNoise(vec2 texCoord, float frequency, float amplitude, float time) {vec2 center = vec2(0.5, 0.5);vec2 offset = texCoord - center;float distance = length(offset);float noiseValue = noise(vec2(distance * frequency + time, time));vec2 noiseVector = vec2(cos(noiseValue), sin(noiseValue));return noiseVector * amplitude * (1.0 - distance);}vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }vec2 mod289(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }vec3 permute(vec3 x) { return mod289(((x*34.0)+1.0)*x); }float snoise(vec2 v) {const vec4 C = vec4(0.211324865405187,0.366025403784439,-0.577350269189626,0.024390243902439);vec2 i = floor(v + dot(v, C.yy) );vec2 x0 = v - i + dot(i, C.xx);vec2 i1;i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);vec4 x12 = x0.xyxy + C.xxzz;x12.xy -= i1;i = mod289(i);vec3 p = permute( permute( i.y + vec3(0.0, i1.y, 1.0 ))+ i.x + vec3(0.0, i1.x, 1.0 ));vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);m = m*m ;m = m*m ;vec3 x = 2.0 * fract(p * C.www) - 1.0;vec3 h = abs(x) - 0.5;vec3 ox = floor(x + 0.5);vec3 a0 = x - ox;m *= 1.79284291400159 - 0.85373472095314 * ( a0*a0 + h*h );vec3 g;g.x  = a0.x  * x0.x  + h.x  * x0.y;g.yz = a0.yz * x12.xz + h.yz * x12.yw;return 130.0 * dot(m, g);}void main() {vec2 u_resolution = vec2(w,h);vec2 st = gl_FragCoord.xy/u_resolution.xy;vec2 uv = vTexCoord;vec2 uv_2 = vTexCoord;vec2 q = gl_FragCoord.xy/u_resolution.xy*.5;vec2 p = -1.0 + 0.650 * q;p.x *= u_resolution.x/u_resolution.y;vec2 pos = vec2(st.x*0.7 + (u_time*0.18), st.y*0.17 + (u_time*.18));vec3 dist = vec3(snoise(pos)*u_mouse.y);vec2 distorter = vec2(dist.rg) * vec2(0.01);float r = length( p * 0.45);vec3 col = vec3(0.64,0.25,0.0 );float f = fbm( 7.0*p );col = mix(col, vec3(1.0,1.0,1.0),f);f = smoothstep( .19, 0.92, r );col = mix( col, vec3(0.0), f+1.0 );float r2 = length( uv * 200.0);vec3 col2 = vec3(0.0,0.0,0.0 );float f2 = fbm( 20.0*-p );col2 = mix(-col2, vec3(-0.6,0.6,0.6),f2);f2 = smoothstep( .19, 0.92, r2 );col2 = mix( col2, -vec3(0.0),f2+0.5);vec4 distortedFlower = texture2D(theWall, fract(uv)+distorter)+vec4(col2,0.30);vec4 distortedBackground = texture2D(theFigureInTheWall, fract(uv_2)+distorter);vec4 flowerBackground = distortedFlower * distortedFlower.a + distortedBackground * (1.0 - distortedFlower.a);gl_FragColor = vec4(col,1.0)+flowerBackground;}`;

let provokingCrawlingUp = 0, provokingCrawlingUpAndLeft = 1,provokingCrawlingUpLeft = 2,provokingCrawlingDownAndLeft = 3,provokingCrawlingDown = 4,provokingCrawlingDownAndRight = 5,provokingCrawlingRight = 6,provokingCrawlingUpAndRight = 7;
let sittingWithMyself;
let iWasMoving = 2,throughSpace = 5,aFaintFigureMovingBackAndFourth,aFaintFigureMovingUpAndDown;

let aForm = [
                  {aCrawlingColor:['e16c58','f89c2b','db391e','db391e','84372a','7c0a0a','7c0a0a'], grotesque:'ffd59a', wavesOfRed:230, wavesOfDarkRed:230, wavesOfLightGreen:120, wavesOfDarkGreen:160, wavesOfLightBlue:110, wavesOfDarkBlue:120, wavesFading:.02, convolution:'a9b55b', distraction:'ff5fe3',aCenter:'7c0a0a', outlines:'7c0a0a', aFigure:2, lookingBackAtMe:1.0, lookingBackAtHerself:0.0, hallucinations:4.0}, //1
                  {aCrawlingColor:['e5cd00','867800','f35a1b','f38533','4E3620','a99700','4E3620'], grotesque:'e03500', wavesOfRed:240, wavesOfDarkRed:255, wavesOfLightGreen:200, wavesOfDarkGreen:220, wavesOfLightBlue:120, wavesOfDarkBlue:140, wavesFading:.04, convolution:'837c51', distraction:'fff4d8',aCenter:'fff4d8', outlines:'fff4d8', aFigure:0, lookingBackAtMe:3.0, lookingBackAtHerself:2.0, hallucinations:0.0}, //3
                  {aCrawlingColor:['57ca8f','f68d40','f68d40','35778E','4cc1e9','f43628','ff7a30'], grotesque:'b5dafb', wavesOfRed:250, wavesOfDarkRed:255, wavesOfLightGreen:110, wavesOfDarkGreen:140, wavesOfLightBlue:70, wavesOfDarkBlue:90, wavesFading:.02, convolution:'867c51', distraction:'f4effd',aCenter:'f43628', outlines:'f4effd', aFigure:9, lookingBackAtMe:4.0, lookingBackAtHerself:2.0, hallucinations:2.0}, //4
                  {aCrawlingColor:['c1acd1','c9ac8f','f85d52','bf927e','cac145','c5afd5','f4ee9f'], grotesque:'9e744a', wavesOfRed:200, wavesOfDarkRed:255, wavesOfLightGreen:110, wavesOfDarkGreen:150, wavesOfLightBlue:50, wavesOfDarkBlue:100, wavesFading:.02, convolution:'befa07', distraction:'ff230a',aCenter:'feefc1', outlines:'fe430f', aFigure:3, lookingBackAtMe:5.0, lookingBackAtHerself:2.0, hallucinations:30.0}, //6
                  {aCrawlingColor:['ffeab0','f9a498','ce333e','ea3d5e','951b12','ffeab0','611b1d'], grotesque:'c0a6e3', wavesOfRed:215, wavesOfDarkRed:255, wavesOfLightGreen:120, wavesOfDarkGreen:130, wavesOfLightBlue:30, wavesOfDarkBlue:60, wavesFading:.02, convolution:'0a6845', distraction:'d1d649',aCenter:'7b696f', outlines:'d1d649', aFigure:4, lookingBackAtMe:3.0, lookingBackAtHerself:2.0, hallucinations:0.0}, //7
                  {aCrawlingColor:['bc5b2b','744E48','68342F','636200','8D674E','513934','823B30'], grotesque:'513c37', wavesOfRed:40, wavesOfDarkRed:55, wavesOfLightGreen:40, wavesOfDarkGreen:55, wavesOfLightBlue:30, wavesOfDarkBlue:50, wavesFading:.04, convolution:'837c51', distraction:'ff6d3c',aCenter:'513934', outlines:'837c51', aFigure:1, lookingBackAtMe:3.0, lookingBackAtHerself:2.0, hallucinations:20.0}, //8
                  {aCrawlingColor:['b02529','d9d56a','eb9c2a','b55b91','b02529','e3633d','b02529'], grotesque:'020101', wavesOfRed:160, wavesOfDarkRed:170, wavesOfLightGreen:160, wavesOfDarkGreen:165, wavesOfLightBlue:160, wavesOfDarkBlue:165, wavesFading:.04, convolution:'857c51', distraction:'8c8c8c',aCenter:'B68D81', outlines:'8c8c8c', aFigure:6, lookingBackAtMe:4.0, lookingBackAtHerself:2.0, hallucinations:5.0}, //9
                  {aCrawlingColor:['dc4056','B4677C','BD7D80','91332E','AB5B64','f23c54','682E46'], grotesque:'9c9054', wavesOfRed:215, wavesOfDarkRed:255, wavesOfLightGreen:50, wavesOfDarkGreen:80, wavesOfLightBlue:80, wavesOfDarkBlue:120, wavesFading:.02, convolution:'682E46', distraction:'6c3fa3',aCenter:'95010f', outlines:'6c3fa3', aFigure:7, lookingBackAtMe:6.0, lookingBackAtHerself:2.0, hallucinations:10.0}, //10
                  {aCrawlingColor:['3E652D','af75b3','27c9ba','1E3E21','7D7480','c9bc48','af75b3'], grotesque:'c4d19a', wavesOfRed:250, wavesOfDarkRed:255, wavesOfLightGreen:180, wavesOfDarkGreen:230, wavesOfLightBlue:205, wavesOfDarkBlue:215, wavesFading:.04, convolution:'857c51', distraction:'27c9ba',aCenter:'1E3E21', outlines:'27c9ba', aFigure:8, lookingBackAtMe:3.0, lookingBackAtHerself:2.0, hallucinations:40.0}, //11
                  {aCrawlingColor:['99020f','ff5015','7d60e2','c64d44','ffb87e','cc3025','513e94'], grotesque:'3adfdc', wavesOfRed:220, wavesOfDarkRed:255, wavesOfLightGreen:40, wavesOfDarkGreen:180, wavesOfLightBlue:110, wavesOfDarkBlue:250, wavesFading:.02, convolution:'00aa2c', distraction:'00aa2c',aCenter:'8a0a33', outlines:'d20648', aFigure:5, lookingBackAtMe:3.0, lookingBackAtHerself:2.0, hallucinations:2.0}, //12
];

let aDividedMind = 6,tryingToCombine;
let whatAmISeeing;
let aMovement;
let myFlowerWasBlooming;
let intoMyThoughts;
let womenCreepingOutOfTheWall = 28.3;
let aNewFlower = [];

function setup() {
  console.log('yellow wallpaper v1.0')
  pixelDensity(3.0);
  createCanvas(windowWidth, windowHeight,WEBGL);
  intoMyThoughts = new Random();
  aMovement = intoMyThoughts.random_dec()
  lookingBackAtMe = intoMyThoughts.random_int(1,6);
  whatAmISeeing = intoMyThoughts.random_int(0,9);
  myFlowerWasBlooming = intoMyThoughts.random_int(0,9);
  console.log(whatAmISeeing);
  theWall = createGraphics(windowWidth,windowHeight);
  theViewFromThisRoom = createGraphics(windowWidth,windowHeight);
  bodiesEmerge = createShader(movementFromTheirFlesh, movementFromTheirSkin);
  bgNoise();
  aFlowerInTheMoonlight();
  for(let i=0;i<aNewFlower.length;i++){
    aNewFlower[i].display();
  }
}
function draw() {
  if (/\bHeadlessChrome/.test(navigator.userAgent)) { 
    womenCreepingOutOfTheWall = aForm[whatAmISeeing].hallucinations;
  } else{
    womenCreepingOutOfTheWall = (mouseX-windowWidth/2)/18;
  }
  bodiesEmerge.setUniform("u_resolution", [width, height]);
  bodiesEmerge.setUniform("u_time", millis() / 10000.0);
  bodiesEmerge.setUniform("u_mouse", [mouseX, womenCreepingOutOfTheWall]);
  bodiesEmerge.setUniform('w', windowWidth/2)
  bodiesEmerge.setUniform('h', windowHeight/2)
  bodiesEmerge.setUniform('theWall', theWall);
  bodiesEmerge.setUniform('theFigureInTheWall', theViewFromThisRoom);
  bodiesEmerge.setUniform('noiseSeed', frameCount/100);
  bodiesEmerge.setUniform('noiseAmount', 0.05);
  bodiesEmerge.setUniform('lookingBackAtMe', lookingBackAtMe);
  bodiesEmerge.setUniform('lookingBackAtHerself', aForm[whatAmISeeing].lookingBackAtHerself);
  shader(bodiesEmerge);
  noStroke();
  plane(width, height);
}
function aFlowerInTheMoonlight(){
let space = intoMyThoughts.random_num(width/10,width/3.5);
let offset_a = intoMyThoughts.random_num(1.0,3.0);
let offset_b = intoMyThoughts.random_num(1.0,2.0);
let scale_a = intoMyThoughts.random_num(0.5,2.0);
let scale_b = intoMyThoughts.random_num(0.5,2.0);
let move_a = intoMyThoughts.random_num(1.0,3.0);
let move_b = intoMyThoughts.random_num(1.0,3.0);
    if(myFlowerWasBlooming == 0 || myFlowerWasBlooming == 5){     
      for(let x = 0; x < width+50; x+=space*offset_a){
        for(let y = 0; y < height+50; y+=space*offset_b){
          let a = new Chrysanthemum(x,y,0,space/width*scale_a);
          let b = new Chrysanthemum(x+space/move_a,y+space/move_b,0,space/width*scale_b);
          aNewFlower.push(a);
          aNewFlower.push(b);
        }
      }
    } else if (myFlowerWasBlooming == 1 || myFlowerWasBlooming == 6){
      for(let x = 0; x < width+50; x+=space*offset_a){
        for(let y = 0; y < height+50; y+=space*offset_b){
          let a = new Hydrangea(x,y,0,space/width*scale_a*1.5);
          let b = new Hydrangea(x+space/move_a,y+space/move_b,0,space/width*scale_b*1.5);
          aNewFlower.push(a);
          aNewFlower.push(b);
        }
      }
    } else if (myFlowerWasBlooming == 2 || myFlowerWasBlooming == 7){
      for(let x = 0; x < width+50; x+=space*offset_a){
        for(let y = 0; y < height+50; y+=space*offset_b){
          let a = new PoetsNarcissus(x,y,0,space/width*scale_a);
          let b = new PoetsNarcissus(x+space/move_a,y+space/move_b,0,space/width*scale_b);
          aNewFlower.push(a);
          aNewFlower.push(b);
        }
      }
    } else if (myFlowerWasBlooming == 3 || myFlowerWasBlooming == 8){
      for(let x = 0; x < width+50; x+=space*offset_a){
        for(let y = 0; y < height+50; y+=space*offset_b){
          let a = new Poppy(x,y,0,space/width*scale_a);
          let b = new Poppy(x+space/move_a,y+space/move_b,0,space/width*scale_b);
          aNewFlower.push(a);
          aNewFlower.push(b);
        }
      }
    } else if (myFlowerWasBlooming == 4 || myFlowerWasBlooming == 9){
      for(let x = 0; x < width+50; x+=space*offset_a){
        for(let y = 0; y < height+50; y+=space*offset_b){
          let a = new Foxglove(x,y,0,space/width*scale_a);
          let b = new Foxglove(x+space/move_a,y+space/move_b,0,space/width*scale_b);
          aNewFlower.push(a);
          aNewFlower.push(b);
        }
      }
    }
}
function bgNoise(){
  aFaintFigureMovingBackAndFourth = width / 2;
  aFaintFigure= height / 2;
  theViewFromThisRoom.background("#"+aForm[whatAmISeeing].grotesque);
  for (let j = 0; j < 200; j++){
    theViewFromThisRoom.noStroke();
    theViewFromThisRoom.fill('rgba('+intoMyThoughts.random_int(aForm[whatAmISeeing].wavesOfRed,aForm[whatAmISeeing].wavesOfDarkRed)+','+intoMyThoughts.random_int(aForm[whatAmISeeing].wavesOfLightGreen,aForm[whatAmISeeing].wavesOfDarkGreen)+','+intoMyThoughts.random_int(aForm[whatAmISeeing].wavesOfLightBlue,aForm[whatAmISeeing].wavesOfDarkBlue)+', '+aForm[whatAmISeeing].wavesFading+')');
    for (let i = 0; i <= width; i++) {
        sittingWithMyself = intoMyThoughts.random_int(0, 8);
      if (sittingWithMyself == provokingCrawlingUp) {aFaintFigure-= iWasMoving;
      } else if (sittingWithMyself == provokingCrawlingUpAndLeft) {aFaintFigureMovingBackAndFourth += iWasMoving;aFaintFigure-= iWasMoving;
      } else if (sittingWithMyself == provokingCrawlingUpLeft) {aFaintFigureMovingBackAndFourth += iWasMoving;
      } else if (sittingWithMyself == provokingCrawlingDownAndLeft) {aFaintFigureMovingBackAndFourth += iWasMoving;aFaintFigure+= iWasMoving;
      } else if (sittingWithMyself == provokingCrawlingDown) {aFaintFigure+= iWasMoving;
      } else if (sittingWithMyself == provokingCrawlingDownAndRight) {aFaintFigureMovingBackAndFourth -= iWasMoving;aFaintFigure+= iWasMoving;
      } else if (sittingWithMyself == provokingCrawlingRight) {aFaintFigureMovingBackAndFourth -= iWasMoving;
      } else if (sittingWithMyself == provokingCrawlingUpAndRight) {aFaintFigureMovingBackAndFourth -= iWasMoving;aFaintFigure-= iWasMoving;
      }
      if (aFaintFigureMovingBackAndFourth > width) aFaintFigureMovingBackAndFourth = 0;
      if (aFaintFigureMovingBackAndFourth < 0) aFaintFigureMovingBackAndFourth = width;
      if (aFaintFigure< 0) aFaintFigure= height;
      if (aFaintFigure> height) aFaintFigure= 0;
      theViewFromThisRoom.ellipse(aFaintFigureMovingBackAndFourth + iWasMoving / 2, aFaintFigure+ iWasMoving / 2, throughSpace, throughSpace);
    }
  }
}
function windowResized() {
  if (/\bHeadlessChrome/.test(navigator.userAgent)) { 
    // we are in the headless context
    womenCreepingOutOfTheWall = 2.0;
    resizeCanvas(2400, 2400);
    bodiesEmerge.setUniform("u_mouse", [0.0, 0.0]);
    noStroke();
    plane(2400, 2400);
  } else{
    resizeCanvas(windowWidth, windowHeight);
    bodiesEmerge.setUniform("u_mouse", [0.0, 0.0]);
    setup();
  }
}
class Random {
    constructor() {
      this.useA = false;
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
      this.prngA = new sfc32(tokenData.hash.substr(2, 32));
      this.prngB = new sfc32(tokenData.hash.substr(34, 32));
      for (let i = 0; i < 1e6; i += 2) {
        this.prngA();
        this.prngB();
      }
    }
    random_dec() {
      this.useA = !this.useA;
      return this.useA ? this.prngA() : this.prngB();
    }
    random_num(a, b) {
      return a + (b - a) * this.random_dec();
    }
    random_int(a, b) {
      return Math.floor(this.random_num(a, b + 1));
    }
    random_bool(p) {
      return this.random_dec() < p;
    }
    random_choice(list) {
      return list[this.random_int(0, list.length - 1)];
    }
  }
class Chrysanthemum{
    constructor(_xpos,_ypos,_rot,_size){
      this.xpos = _xpos;
      this.ypos = _ypos;
      this.rot = _rot;
      this.size = _size;
    }
    display(){
      theWall.push();
        theWall.translate(this.xpos,this.ypos);
        theWall.scale(this.size); 
        theWall.stroke("#"+aForm[whatAmISeeing].convolution);
        theWall.noFill();
        theWall.bezier(0,0,30,50,10,height/4,30,height/3);
        for(let i = 3; i < 30; i++){
            theWall.fill("#"+aForm[whatAmISeeing].aCrawlingColor[intoMyThoughts.random_int(0,6)]);
            theWall.rotate(2.3*i);
            theWall.strokeWeight(3);
            theWall.stroke("#"+aForm[whatAmISeeing].grotesque);
            theWall.bezier(0,-height/100,height/6,height/11,0,height/1.7,0,0);
          }
        theWall.stroke("#"+aForm[whatAmISeeing].grotesque);
        theWall.fill("#"+aForm[whatAmISeeing].aCenter);
        theWall.ellipse(0,0,windowHeight/20);
        theWall.pop();
    }
  }
class Hydrangea{
    constructor(_xpos,_ypos,_rot,_size){
      this.xpos = _xpos;
      this.ypos = _ypos;
      this.rot = _rot;
      this.size = _size;
    }
    display(){
      theWall.push();
      theWall.translate(this.xpos,this.ypos);
      theWall.scale(this.size); 
      theWall.stroke("#"+aForm[whatAmISeeing].convolution);
      theWall.strokeWeight(8);
      theWall.noFill();
      theWall.bezier(0,0,height/10,height/10,height/100,height/6,height/50,height/4);
      let aFirstMoonlitFigure = [-width/10,-width/4,-width/0,-width/6,-width/9,-width/15];
      let aSecondMoonlitFigure = [-width/10,-width/4,-width/4,-width/4.5,-width/5,-width/6];
      let aThirdMoonlitFigure = [-width/12,-width/10,-width/15,-width/20,-width/40,0];
      let aFourthMoonlitFigure = [width/3,width/3,width/4,width/4,width/4.5,width/6];
      let aFifthMoonlitFigure = [5,2,1,1,2,0];
      let aSixthMoonlitFigure = [8,11,14,14,10,10];
      for(let i = 0; i < 6; i++){
        theWall.fill("#"+aForm[whatAmISeeing].aCrawlingColor[intoMyThoughts.random_int(0,6)]);
        theWall.noStroke();
        theWall.push()
        theWall.stroke("#"+aForm[whatAmISeeing].grotesque);
        theWall.strokeWeight(2)
        theWall.rotate(PI / 1.5)
        theWall.bezier(0,0,
                aFirstMoonlitFigure[i],aSecondMoonlitFigure[i],
                aThirdMoonlitFigure[i],aFourthMoonlitFigure[i],
                aFifthMoonlitFigure[i],aSixthMoonlitFigure[i]
                );
        theWall.pop();
        }
        theWall.pop();
    }
  }
class PoetsNarcissus{
    constructor(_xpos,_ypos,_rot,_size){
      this.xpos = _xpos;
      this.ypos = _ypos;
      this.rot = _rot;
      this.size = _size;
    }

    display(){
        theWall.push();
        theWall.translate(this.xpos,this.ypos);
        theWall.scale(this.size);
        theWall.push();
        theWall.stroke("#"+aForm[whatAmISeeing].convolution);
        theWall.strokeWeight(6);
        theWall.noFill();
        theWall.bezier(0,0,30,50,10,height/4,30,height/3);
        theWall.pop();
        theWall.push()
        for(let i = 0; i < 6; i++){
          theWall.rotate(1.1);
          theWall.fill('#'+aForm[whatAmISeeing].aCrawlingColor[intoMyThoughts.random_int(0,6)]);
          theWall.stroke("#"+aForm[whatAmISeeing].grotesque);
          theWall.strokeWeight(2);
          theWall.beginShape();
          theWall.curveVertex(0,0);
          theWall.curveVertex(0,0);
          theWall.curveVertex(height/8,height/15);
          theWall.curveVertex(height/5, height/4);
          theWall.curveVertex(height/5.5, height/5);
          theWall. curveVertex(0, -height/80);
          theWall.curveVertex(0,0);
          theWall.endShape();
        }
        theWall.pop();
        theWall.push();
        theWall.fill("#"+aForm[whatAmISeeing].aCrawlingColor[intoMyThoughts.random_int(0,6)]);
        theWall.stroke("#"+aForm[whatAmISeeing].outlines);
        theWall.strokeWeight(2);
        theWall.ellipse(0,0,height/20);
        theWall.pop();
        theWall.pop();
    }
  }
class Poppy{
    constructor(_xpos,_ypos,_rot,_size){
      this.xpos = _xpos;
      this.ypos = _ypos;
      this.rot = _rot;
      this.size = _size;
    }

    display(){
      theWall.push();
      theWall.translate(this.xpos,this.ypos);
      theWall.scale(this.size);
      theWall.push();
      theWall.stroke("#"+aForm[whatAmISeeing].convolution);
      theWall.strokeWeight(6);
      theWall.noFill();
      theWall.bezier(0,0,30,50,10,height/4,30,height/3);
      theWall.pop();
      for(let sheLovesMe = 3; sheLovesMe < 8; sheLovesMe++){
        theWall.fill("#"+aForm[whatAmISeeing].aCrawlingColor[intoMyThoughts.random_int(0,6)]);
        theWall.push();
        theWall.stroke("#"+aForm[whatAmISeeing].grotesque);
        theWall.strokeWeight(3);
        theWall.rotate(PI/2.5*sheLovesMe);
        theWall.bezier(0,0,height/3,width/20,0,-width/3,0,0);
        theWall.pop();
      }
      theWall.push();
      theWall.stroke("#"+aForm[whatAmISeeing].outlines);
      theWall.strokeWeight(3);
      theWall.fill("#"+aForm[whatAmISeeing].aCenter);
      theWall.ellipse(0,0,width/20);
      theWall.pop();
      theWall.pop();
    }
  }
class Foxglove{
    constructor(_xpos,_ypos,_rot,_size){
      this.xpos = _xpos;
      this.ypos = _ypos;
      this.rot = _rot;
      this.size = _size;
    }
    display(){
      theWall.push();
      theWall.translate(this.xpos,this.ypos);
      theWall.scale(this.size);
      theWall.push();
      theWall.translate(0,height/-10);
      theWall.stroke("#"+aForm[whatAmISeeing].convolution);
      theWall.strokeWeight(18);
      theWall.noFill();
      theWall.bezier(0,height/-8,0,height/5.5,height/80,height/6,height/80,height/1.9);
      theWall.pop();
      let sheLovesMe = 0;
      theWall.push();
      for(let i = 0; i < aDividedMind; i++){
          theWall.fill("#"+aForm[whatAmISeeing].aCrawlingColor[intoMyThoughts.random_int(0,6)]);
          theWall.strokeWeight(4);
          theWall.stroke("#"+aForm[whatAmISeeing].grotesque);
          theWall.push();
          theWall.translate(0,(sheLovesMe*height/13)-height/5);
          theWall.rotate(0.1);
          theWall.bezier(0,0,(height/90)*sheLovesMe,(height/10)*sheLovesMe,(height/10)*sheLovesMe,(height/40)*sheLovesMe,0,0);
          theWall.pop();
          sheLovesMe++
      }
      theWall.pop();
      let sheLovesMeNot = 0;
      theWall.push();
        for(let i = 0; i < aDividedMind; i++){
            theWall.fill("#"+aForm[whatAmISeeing].aCrawlingColor[intoMyThoughts.random_int(0,6)]);
            theWall.strokeWeight(4);
            theWall.stroke("#"+aForm[whatAmISeeing].grotesque);
            theWall. push()
            theWall.translate(0,(sheLovesMeNot*height/14)-height/5);
            theWall. rotate(0.1)
            theWall.bezier(0,0,0*sheLovesMeNot,(height/10)*sheLovesMeNot,-(height/15)*sheLovesMeNot,(height/40)*sheLovesMeNot,0,0);
            theWall.pop()
            sheLovesMeNot++
      }
      theWall.pop();
      theWall.pop();
    }
  }