
let hashPairs = [];

for (let j = 0; j < 32; j++) {
     hashPairs.push(tokenData.hash.slice(2 + (j * 2), 4 + (j * 2)));
}

let decPairs = hashPairs.map(x => {
     return parseInt(x, 16);
});

let mainShader;

let dataLength;
dataLength = decPairs.length;

function preload() {

	mainShader = getShader(this._renderer);
	
}

function setup() {
	
	
	let size = windowWidth;
	if(windowWidth>windowHeight){
		size =windowHeight;
	}
	
	createCanvas(size, size, WEBGL);
	shader(mainShader);

}


function draw() {
 
	var data = [];

	for(let i=0; i< decPairs.length; i++){
		let target =0;
		let power =0.05;
		let lerper = 0.005;
		if( i== 0){
				target = decPairs[0] - decPairs[decPairs.length-1];
		}else{
			 target = decPairs[i] - decPairs[i-1];
		}
		let superTarget = lerp(decPairs[i],decPairs[i] + (target*power), lerper);
		
		decPairs[i] = superTarget ;

		data.push(decPairs[i]);
	}

	mainShader.setUniform("data", data);
    mainShader.setUniform("time",(millis()/40000.0));
	rect(0, 0, width, height);
  
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

		uniform float data[${dataLength}];
	
		const float WIDTH = ${windowWidth}.0;
		const float HEIGHT = ${windowHeight}.0;

		uniform vec2 resolution;
		
		uniform float time;
		
		vec3 hsb2rgb( in vec3 c ){
				vec3 rgb = clamp(abs(mod(c.x*6.0+vec3(0.0,4.0,2.0),
																 6.0)-3.0)-1.0,
												 0.0,
												 1.0 );
				rgb = rgb*rgb*(3.0-2.0*rgb);
				return c.z * mix(vec3(1.0), rgb, c.y);
		}


		float mapr(float value, float min1, float max1, float min2, float max2) {
  		 return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
		}

		float hashNoise(int index){
			float noiseVal;
			
			for (int i=0; i<32; i++) {
				 if (i==index) {
						noiseVal = data[i];
						break;
				 }
			}
			return noiseVal;
		}

		void main() {
			
			float rel = WIDTH/HEIGHT;
			vec2 st = vTexCoord.xy;
			if(st.x >0.5){
				st.x = 1.-st.x;
			}
			if(st.y >0.5){
				st.y = 1.-st.y;
			}
			
			float phaser = sin(2.*pi*time*0.01)*2.2;
		 
		    int valIntX = int(floor((st.x*2.)*31.));
			int valIntY = int(floor((st.y*2.)*31.));
			float hashNoiseValX = abs(hashNoise(valIntX))/255.;
			float hashNoiseValY = abs(hashNoise(valIntY))/255.;
			
			float hashVal= fract( ((hashNoiseValX+hashNoiseValY) /2.)+time) ;
			vec3 rgb = hsb2rgb(vec3(hashVal,1.,1.));
		
			float timer = time*40./600.;
			gl_FragColor = vec4((rgb*(1.-timer)) + timer, 1.0);

		}
	`;
	
	return new p5.Shader(_renderer, vert, frag);
}