// By Ruben Alexander
// https://twitter.com/RubenAlexand3r

p5.disableFriendlyErrors = true;

function random_hash() {
  let chars = "0123456789abcdef";
  let result = '0x';
  for (let i = 64; i > 0; --i) result += chars[Math.floor(Math.random() * chars.length)];
  return result;
}

class Random {
  constructor(seed) {
    this.seed = seed
  }
  random_dec() {
    this.seed ^= this.seed << 13
    this.seed ^= this.seed >> 17
    this.seed ^= this.seed << 5
    return ((this.seed < 0 ? ~this.seed + 1 : this.seed) % 1000) / 1000
  }
  random_between(a, b) {
    return a + (b - a) * this.random_dec()
  }
  random_int(a, b) {
    return Math.floor(this.random_between(a, b+1))
  }
  random_choice(x) {
    return x[Math.floor(this.random_between(0, x.length * 0.99))]
  }
}


var seed = parseInt(tokenData.hash.slice(0, 16), 16);
var r = new Random(seed);

class Petal {
  constructor(){
		this.x = width/2;
    this.y = height/2;
    this.diameter = 1;
		let speed = r.random_between(2,3);
    this.xSpeed = r.random_between(-1*speed,speed);
    this.ySpeed = r.random_between(-1*speed,speed);
		this.color = color(10,20,30);
		this.randomizer = 0;
		this.rate = -1*floor(r.random_between(0,10));
		let z = floor(r.random_between(0,6));
		let arr = [0,0,0,0,0,0];
		if (z == 0) {
			arr=[125,15,12,10,5,3];
		} else if (z == 1) {
			arr=[15,125,14,4,10,2];
		} else if (z == 2) {
			arr=[15,12,154,3,2,10];
		} else if (z == 3) {
			arr=[15,152,154,3,20,10];
		} else if (z == 4) {
			arr=[125,12,154,30,2,10];
		} else if (z == 5) {
			arr=[125,121,154,30,24,20];
		} else if (z == 6) {
			arr=[12,11,15,3,2,2];
		}
			this.r = floor(r.random_between(0,arr[0]));
			this.g = floor(r.random_between(0,arr[1]));
			this.b = floor(r.random_between(0,arr[2]));
			this.modr = -1*floor(r.random_between(0,arr[3]));
			this.modg = -1*floor(r.random_between(0,arr[4]));
			this.modb = -1*floor(r.random_between(0,arr[5]));
		
  }

	reduceDiameter() {
		let val = r.random_between(1,2);
		let decay = -0.15; 
		this.randomizer += r.random_between(0,val)-r.random_between(0,val);
		this.x += this.randomizer;
		this.randomizer += r.random_between(0,val)-r.random_between(0,val);
		this.y += this.randomizer;
		this.diameter = 100*exp(decay*frameCount/5); 
		
		if (this.diameter < 1) {
			this.diameter = 0;
		}
	}
	
	getColor(){
		var a = [this.r, this.g,  this.b];
		return a;
	}

  createPetal() {
    noStroke();
    circle(this.x,this.y,this.diameter);
  }
	
	adjustColor(i) {
		let x = r.random_between(0,i);
		let amp = 255;
		let base = 255;
		if (x < i/3) {
			base = r.random_between(0,150);
		} else if (x >= i/3 && x < 2*i/3) {
			base = r.random_between(150,200);
		} else {
			base = r.random_between(200,255);
		}
			
		this.r += amp*exp(this.rate*frameCount/10)- this.modr;
		this.r = this.r % base;
		this.g += amp*exp(this.rate*frameCount/10)- this.modg;
		this.g = this.g % base;
		this.b += amp*exp(this.rate*frameCount/10)- this.modb;
		this.b = this.b % base;
		this.color = color(this.r,this.g,this.b);
		fill(this.color);
		let c=color(this.r,this.g,this.b);
		return c
	}
	
	setBaseColor(r,g,b) {
		this.r = r;
		this.g = g;									 
		this.b = b;
	}
	
  movePetal() {
		if (this.diamteter < 10) {
			this.x+=(this.xSpeed*.001);
			this.y+=(this.ySpeed*.001);
			this.randomizer *= .1;
		} else {
			this.x+=this.xSpeed-this.randomizer;
			this.y+=this.ySpeed-this.randomizer;
		}
  }
}

var petal = [];
var c;
var DIM = 0;

function setup() {
	DIM = Math.min(window.innerWidth, window.innerHeight);	
	createCanvas(DIM,DIM);
	document.body.style.overflow = 'hidden';
	
	let red = floor(r.random_between(0,100));
	let green = floor(r.random_between(0,100));
	let blue = floor(r.random_between(0,100));
	let _max = floor(r.random_between(100,200));
	
	for(let i = 0;i<_max;i++){
    petal.push(new Petal());
		petal[i].setBaseColor(red,green,blue);
  }
	
	DIM *= 0.7;
	DIM = floor(DIM);
	
}

function draw() {
	translate(width/2,height/2)
	scale(DIM/600);
	translate(-width/2,-height/2)
	
  for(let i = 0;i<petal.length;i++) {
    petal[i].createPetal();
		if (i==0) {
    	c = petal[i].adjustColor(i);
			if (frameCount == 1) { 
				background(c);
			}
		} else {
			petal[i].setBaseColor(c[0],c[1],c[2]);
		}
		petal[i].movePetal();
		petal[i].reduceDiameter();	
  }
}

