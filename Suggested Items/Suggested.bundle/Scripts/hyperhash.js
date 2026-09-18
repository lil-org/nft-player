let hashPairs = [];

for (let j = 0; j < 32; j++) {
     hashPairs.push(tokenData.hash.slice(2 + (j * 2), 4 + (j * 2)));
}

let decPairs = hashPairs.map(x => {
     return parseInt(x, 16);
});

let mainShader;
let a_Particles = 6;
let particles = [];

//inputParameters
let layers = 4;
let layerData = [];
let colorBase = 0;
let colorRange = 0;
let colorFrequency = 0;
let colorSpeed = 0;
let rotationspeeds = [];
let mirror = 0;
let warp = 0;
let phase = 0;
let volume = 0;
let timer = 0;
let checkFrameTime = 0;
let rare = 0;

function preload() {
     randomFromHash();
     mainShader = getShader(this._renderer);
}

function setup() {

     createCanvas(windowWidth, windowHeight, WEBGL);
     shader(mainShader);
     mainShader.setUniform("colorBase", colorBase);
     mainShader.setUniform("colorRange", colorRange);
     mainShader.setUniform("colorFrequency", colorFrequency);
     mainShader.setUniform("colorSpeed", colorSpeed);
     mainShader.setUniform("mirror", mirror);
     mainShader.setUniform("warp", warp);
     mainShader.setUniform("phase", phase);
     mainShader.setUniform("rare", rare);
     setupParticles();

}

function draw() {

     var data = [];

     for (let p of particles) {
          p.move();
          data.push(p.x, p.y);
     }

     mainShader.setUniform('resolution', [width / 1000, height / 1000])
     mainShader.setUniform("data", data);
     mainShader.setUniform("time", phase + millis() / 1000.0);
     rect(0, 0, width, height);

}

function randomFromHash() {
     layers = round(map(decPairs[0], 0, 255, 1, 3));
     colorBase = map(decPairs[1 + layers + 1], 0, 255, 0.0, 1.0);
     colorRange = map(decPairs[1 + layers + 2], 0, 255, 0.0, 0.35);
     if (decPairs[1 + layers + 2] % 50 == 1) {
          colorRange = 1.5;
     }
     colorFrequency = map(decPairs[1 + layers + 3], 0, 255, 1.0, 10.0);
     colorSpeed = map(decPairs[1 + layers + 4], 0, 255, 0.1, 1.0);
     phase = map(decPairs[1 + layers + 5], 0, 255, 0.0, 1.0);
     timer += phase;
     warp = round(map(decPairs[1 + layers + 6], 0, 255, 1.0, 9.0));
     mirror = round(map(decPairs[1 + layers + 7], 0, 255, 0.0, 5.0));
     if (decPairs[1 + layers + 8] % 25 == 3) {
          rare = 1;
     }
     layerData = [];
     let count = 0;
     for (let i = 0; i < layers; i++) {


          let ranParticles = round(map(decPairs[1 + i], 0, 255, 1, 6));
          let ranSpeed = map(decPairs[1 + i], 0, 255, 0.05, 0.5);
          rotationspeeds.push(ranSpeed);

          layerData.push(ranParticles)
          count += layerData[i];
     }
     a_Particles = count;


}

function Particle(x, y, id, dis, t, l, m) {

     this.xOrg = x;
     this.yOrg = y;
     this.x = x;
     this.y = y;
     this.id = id;
     this.dis = dis;
     this.theta = t;
     this.layer = l;
     this.mul = m;
     this.move = function() {

          timer = millis() / 1000.0;
          timer *= rotationspeeds[this.layer];
          this.x = (this.mul * (this.layer + 1) * cos(this.theta + PI / 2 + timer));
          this.y = (this.mul * (this.layer + 1) * sin(this.theta + PI / 2 + timer));

     }
}

function setupParticles() {
     let count = 0;

     for (let j = 0; j < layers; j++) {

          let mul = 0.3 / layerData.length;
          for (let o = 0; o < layerData[j]; o++) {
               count += 1;
               let theta = map(o, 0, layerData[j], -PI, PI);
               let x = (mul * (j + 1) * cos(theta + PI / 2));
               let y = (mul * (j + 1) * sin(theta + PI / 2));
               particles.push(new Particle(x, y, count, mul * (j + 1), theta, j, mul));
          }

     }

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
		#define pi 3.14159265359

		uniform vec2 data[${a_Particles}];
	
		const float WIDTH = ${windowWidth}.0;
		const float HEIGHT = ${windowHeight}.0;

		uniform vec2 resolution;
		
		uniform float time;
		uniform float colorBase;
		uniform float colorRange;
		uniform float colorFrequency;
		uniform float colorSpeed;
		uniform float warp;
		uniform float mirror;
		uniform float volume;
		uniform float rare;


		mat2 rotate2d(float _angle){
    		return mat2(cos(_angle),-sin(_angle),
                sin(_angle),cos(_angle));
		}

		vec3 hsv2rgb(vec3 c) {
				vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
				vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
				return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
		}

		float comPower(vec2 pos, float amp1, float amp2){
			
			float dis = 0.0; 
	
			for (int i = 0; i < ${a_Particles}; i++) {
				vec2 particle = data[i];
				float d = distance(pos, particle);
				float d1 = 1.-smoothstep(0.0,0.17,fract(d*2. -time*0.05));
				dis = max(d1,dis);
			}

			float disL = fract(dis*10. );
			disL = step(0.5,disL)-step(0.56,disL);
			disL *= smoothstep(0.0,0.8,dis);
			return dis+disL*0.1;
		}

		vec2 kaleido(vec2 uv,float warp)
		{

		    float r = length(uv);
		    float angle = atan(uv.y, uv.x);
		    
		    float slices = warp;
		    float slice = 6.28 / slices;

		    angle = mod(angle, slice);
		    angle = abs(angle - 0.5 * slice);
		   
		    
		    uv = vec2(cos(angle), sin(angle)) * r;
				return uv;
		}

		float drawLine (vec2 p1, vec2 p2, vec2 uv,float a)
		{
			float scaler = sin(time*0.1);

		    float r = 0.;
		    float one_px = 1. /WIDTH; 

		    float d = distance(p1, p2);

		    float duv = distance(p1, uv);

		    float rel = clamp(duv / d, 0., 1.);
		    vec2 lerp = mix(p1, p2, rel);
		    float disLerp = distance(lerp, uv);
		    float blur = 1.-smoothstep(0.0,a,disLerp);

		    return blur;
		}

		float particle(vec2 pos){
			float dis = 0.0; 
			float l = 0.;
			for (int i = 0; i < ${a_Particles}; i++) {
				vec2 particle = data[i];
				vec2 particle2 = vec2(0.,0.);
				if(i<${a_Particles}-1){
					particle2 = data[i+1];
				}else{
					particle2 = data[0];
				}
				
				float d = distance(pos, particle);
				d = 1.-smoothstep(0.,0.1,d);
				dis = max(d,dis);
				float lt = 0.003;
				l += drawLine(particle,particle2 ,pos,lt);
				l += drawLine(particle,vec2(0.) ,pos,lt);
				
			}

			return (dis*0.5) + (l);//(dis *l)
		}

		float rand(vec2 co){
    		return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
		}

		void main() {
			
			float rel = WIDTH/HEIGHT;
			vec2 st = vTexCoord.xy - 0.5;
			st.x *=rel;

			if(mirror == 0.){	
				st.x = abs(st.x);
			}
			if(mirror == 1.){	
				st.y = abs(st.y);
			}	

			if(mirror == 2.){
				st.x = abs(st.x);	
				st.y = abs(st.y);
			}	
			if(mirror == 3.){
			st = kaleido(st,warp);

			}	

			float dis = 1.-distance(st,vec2(0.));

		  st = rotate2d( sin(time*0.2+dis*2.)* (1.-dis) ) * st; //

			float comPow = comPower(st,1.,1.);
			
			float fade = smoothstep(0.4,0.7,dis);
		  
			float outdis = step(0.598,dis);
			outdis -= step(0.6,dis);
			vec3 outerLayer = vec3(outdis);
			
			vec3 par = vec3(particle(st));
			
			float flowSine = (sin(dis*5.+time)+1.)/2.;
			flowSine *= 0.2;
			flowSine += 0.05;
			vec3 dot = vec3(1.-step(0.003,1.-dis));
			float colorSine = (1.+sin(time*colorSpeed+(dis*colorFrequency)))/2.;
			colorSine = colorBase+(colorSine*colorRange);
			vec3 gradient = hsv2rgb(vec3(colorSine,1.0,0.8));
			vec3 powerBack = (vec3(comPow)*gradient*0.7) + (gradient*(0.3)) + (gradient*par +par*0.3*(volume*15.)); 

			vec3 comb = 0.3+(powerBack*0.7 );
		
			if(rare == 0.){
				gl_FragColor = vec4(comb, 1.0);
			}else{
				gl_FragColor = vec4(vec3((comb.x+comb.y+comb.z)/3.), 1.0);
			}
		  
			
		}
	`;

     return new p5.Shader(_renderer, vert, frag);
}