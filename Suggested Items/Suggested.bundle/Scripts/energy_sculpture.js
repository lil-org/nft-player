let hashPairs = [];

for (let j = 0; j < 32; j++) {
     hashPairs.push(tokenData.hash.slice(2 + (j * 2), 4 + (j * 2)));
}

let decPairs = hashPairs.map(x => {
     return parseInt(x, 16);
});

let mainShader;
let timer = 0;

let morph;
let delayAmount;
let speed;
let hueC;
let dimLayerOne;
let dimLayerTwo;
let bounceSpeed; //range1-6
let morphSpeeds;
let plotTime; //1-6
let phase = 0;

function preload() {

     randomFromHash();
     mainShader = getShader(this._renderer);
}


function setup() {

     createCanvas(windowWidth, windowHeight, WEBGL);
     shader(mainShader);

     mainShader.setUniform("speed", speed);
     mainShader.setUniform("delayAmount", delayAmount);
     mainShader.setUniform("hueC", hueC);
     mainShader.setUniform("dimLayerOne", dimLayerOne);
     mainShader.setUniform("dimLayerTwo", dimLayerTwo);
     mainShader.setUniform("bounceSpeed", bounceSpeed);
     mainShader.setUniform("morphSpeeds", morphSpeeds);
     mainShader.setUniform("plotTime", plotTime);

}

function draw() {

     mainShader.setUniform("time", phase + millis() / 1000.0);
     rect(0, 0, width, height);

}

function randomFromHash() {

     phase = map(decPairs[0], 0, 255, 0, 100);
     //phase =  map(random(0,255), 0, 255, 0, 100);
     let ranDelay = round(map(decPairs[0], 0, 255, 1, 3));
     //let ranDelay = round(map(random(0,255), 0, 255, 1, 3));
     if (ranDelay == 1) {
          delayAmount = 0.02;
     }
     if (ranDelay == 2) {
          delayAmount = 0.08;
     }
     if (ranDelay == 3) {
          delayAmount = 0.12;
     }

     let ranSpeed = round(map(decPairs[1], 0, 255, 1, 3));
     //let ranSpeed = round(map(random(0,255), 0, 255, 1, 3));
     if (ranSpeed == 1) {
          speed = 0.1;
     }
     if (ranSpeed == 2) {
          speed = 0.3;
     }
     if (ranSpeed == 3) {
          speed = 0.6;
     }

     //print(speed);
     let ranColor = map(decPairs[2], 0, 255, 0, 1);
     //let ranColor = map(random(0,255), 0, 255, 0, 1);

     hueC = ranColor;

     let ranDim = round(map(decPairs[3], 0, 255, 0, 1));
     //let ranDim = round(map(random(0,255), 0, 255, 0, 1));

     if (ranDim == 0) {
          // let dimOne = round(map(random(0,255), 0, 255, 0, 9));
          let dimOne = round(map(decPairs[0], 0, 255, 0, 9));
          //let dimTwo = round(map(random(0,255), 0, 255, 0, 9));
          let dimTwo = round(map(decPairs[1], 0, 255, 0, 9));
          dimLayerOne = [dimOne, dimOne, dimOne];
          dimLayerTwo = [dimTwo, dimTwo, dimTwo];
     }
     if (ranDim == 1) {

          dimLayerOne = [round(map(decPairs[0], 0, 255, 0, 9)), round(map(decPairs[1], 0, 255, 0, 9)), round(map(decPairs[2], 0, 255, 0, 9))];
          dimLayerTwo = [round(map(decPairs[3], 0, 255, 0, 9)), round(map(decPairs[4], 0, 255, 0, 9)), round(map(decPairs[5], 0, 255, 0, 9))];

     }

     let ranBounce = round(map(decPairs[4], 0, 255, 1, 6));
     //let ranBounce = round(map(random(0,255), 0, 255, 1, 6));

     bounceSpeed = ranBounce; //range1-6
     morphSpeeds = [round(map(decPairs[0], 0, 255, 1, 6)), round(map(decPairs[1], 0, 255, 1, 6)), round(map(decPairs[2], 0, 255, 1, 6))];
     let ranPlot = round(map(decPairs[5], 0, 255, 1, 6))
     plotTime = ranPlot; //1-6

}

function getShader(_renderer) {
     const vert = `
        attribute vec3 aPosition;
        attribute vec2 aTexCoord;

        varying vec2 vTexCoord;

        void main() {
            vTexCoord = aTexCoord;

            vec4 positionVec4 = vec4(aPosition, 1.0);
            positionVec4.xy = positionVec4.xy * 2.0 - 1.0;

            gl_Position = positionVec4;
        }
    `;

     const frag = `
        precision highp float;

        varying vec2 vTexCoord;

        const float WIDTH = ${windowWidth}.0;
        const float HEIGHT = ${windowHeight}.0;
        
        #define PI 3.14159265359
        #define TWO_PI 6.28318530718
        uniform float time;
        
        #define size 0.55
        #define lineSize 0.175
        #define blur 0.2
        #define grid 2.3
        #define grid2 3.3
        #define morph 3.3
        
        uniform float delayAmount; 
        uniform float speed;
        uniform float hueC;
        uniform vec3 dimLayerOne;
        uniform vec3 dimLayerTwo;
        uniform float bounceSpeed;
        uniform vec3 morphSpeeds;
        uniform float plotTime;

        float impulse( float k, float x )
        {
    float h = k*x;
    return h*exp(1.0-h);
        }

        float plot(float dis){
    float pct = smoothstep(dis,dis+blur,0.5)-smoothstep(lineSize+dis,lineSize+dis+blur,0.5);     
    return   pct ;
        }

        vec3 wooper(vec2 st, float timeCheck){
    
    vec3 color = vec3(0.0);
    vec2 pos = vec2(0.5)-abs(st);

    float r = length(pos)*2.0;
    float a = atan(pos.y,pos.x);
    
    float gridSine = 5.+ (grid2*sin(timeCheck/bounceSpeed * PI));

    r = fract(impulse(r,gridSine)*grid);
    
    float morphSine = 0.2 + ( 1.+sin(timeCheck/morphSpeeds.x * PI) /2.)*morph;
    float morphSine2 = 0.2 + ( 1.+sin(timeCheck/morphSpeeds.y * PI) /2.)*morph;
    float morphSine3 = 0.2 + ( 1.+sin(timeCheck/morphSpeeds.z * PI) /2.)*morph;
    
    float f = ( size*cos(a*dimLayerOne.x + timeCheck/plotTime) + size*cos(a*dimLayerTwo.x + timeCheck*plotTime))/2.;
    float p = plot(1.-smoothstep(f,f+0.9,r*morphSine));
    
    float f2 = ( size*cos(a*dimLayerOne.y + timeCheck/plotTime) + size*cos(a*dimLayerTwo.y + timeCheck*plotTime))/2.;
    float p2 = plot(1.-smoothstep(f2,f2+0.9,r*morphSine2));
    
    float f3 = ( size*cos(a*dimLayerOne.z + timeCheck/plotTime) + size*cos(a*dimLayerTwo.z + timeCheck*plotTime))/2.;
    float p3 = plot(1.-smoothstep(f3,f3+0.9,r*morphSine3));
    
    color.r = p;
    color.g = p2 *st.x;
    color.b = p3;
 
    return(color);
        }

        vec3 powerParticle(vec2 st){
  
    st.y += ((st.x*0.05)*sin(time/10.*PI)+(st.x*0.1)*sin(time/12.*PI))/2.;
    st.x += ((st.y*0.05)*sin(time/10.*PI) + (st.y*0.1)*sin(time/12.*PI))/2.;
    
    vec2 pos = vec2(0.25+0.25*sin(time))-abs(st);

    float r = length(pos);
    float d = distance(st,vec2(0.5))* (sin(time/8.));
    d = distance(vec2(.5),st);
    vec3 colorNew = vec3(0);
   
    float delay = delayAmount;
    float timerChecker = time * speed ;
    for(int i=0;i<10;i++) {
     
      vec3 colorCheck = wooper(st, timerChecker+ float(i)*delay)* (1.-(float(i)/10.0));
      colorNew+= colorCheck ;
    }
    
    return(colorNew);
        }

        vec3 rgb2hsb( in vec3 c ){
                vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
                vec4 p = mix(vec4(c.bg, K.wz),
                                         vec4(c.gb, K.xy),
                                         step(c.b, c.g));
                vec4 q = mix(vec4(p.xyw, c.r),
                                         vec4(c.r, p.yzx),
                                         step(p.x, c.r));
                float d = q.x - min(q.w, q.y);
                float e = 1.0e-10;
                return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)),
                                        d / (q.x + e),
                                        q.x);
        }

        //  Function from Iñigo Quiles
        //  https://www.shadertoy.com/view/MsS3Wc
        vec3 hsb2rgb( in vec3 c ){
                vec3 rgb = clamp(abs(mod(c.x*6.0+vec3(0.0,4.0,2.0),
                                                                 6.0)-3.0)-1.0,
                                                 0.0,
                                                 1.0 );
                rgb = rgb*rgb*(3.0-2.0*rgb);
                return c.z * mix(vec3(1.0), rgb, c.y);
        }
        
        void main() {
            
                        float rel = WIDTH/HEIGHT;
            vec2 st = vTexCoord.xy ;
                        st.x -= 0.5;
            st.x *=rel;
                        st.x += 0.5;
            vec3 powerColor = powerParticle(st);

            vec3 hue = rgb2hsb(powerColor);
            hue.x = hueC;
            hue.y = 0.3;
            float d = 1.-distance(vec2(.5),st);//*2.;

            float d1 = smoothstep(-0.2,1.,d);

            d = smoothstep(0.5,1.0,d);

            vec3 back = vec3(d1,0.,0.);
            vec3 backHue = rgb2hsb(back);
            backHue.x = hueC;
                        
                        gl_FragColor  = vec4(hsb2rgb(backHue)*0.5 +(hsb2rgb(hue)*d) +(powerColor*d*0.4),1.0);
        }
    `;

     return new p5.Shader(_renderer, vert, frag);
}