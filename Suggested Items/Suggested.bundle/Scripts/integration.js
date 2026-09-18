class Random {
  constructor() {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substring(0, 8), 16);
      let b = parseInt(uint128Hex.substring(8, 16), 16);
      let c = parseInt(uint128Hex.substring(16, 24), 16);
      let d = parseInt(uint128Hex.substring(24, 32), 16);
      return function () {
        a |= 0;
        b |= 0;
        c |= 0;
        d |= 0;
        let t = (((a + b) | 0) + d) | 0;
        d = (d + 1) | 0;
        a = b ^ (b >>> 9);
        b = (c + (c << 3)) | 0;
        c = (c << 21) | (c >>> 11);
        c = (c + t) | 0;
        return (t >>> 0) / 4294967296;
      };
    };
    this.prngA = new sfc32(tokenData.hash.substring(2, 34));
    this.prngB = new sfc32(tokenData.hash.substring(34, 66));
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
    
let R = new Random();
let w =2500;
let h = 2500;
let pd=2;

let cl = [];
let num, pal, bgName, speed;
let walkers = [];
let walkers2 = [];
let walkers3 = [];
let walkers4 = [];
let walkers5 = [];

let numWalkers = R.random_int(25, 270);
let numWalkers2 = R.random_int(25, 270);
let numWalkers3 = R.random_int(25, 270);
let numWalkers4 = R.random_int(25, 270);
let numWalkers5 = R.random_int(25, 270);

var velHash = R.random_num(0,10);
if (velHash > 6) xVel = 4.2, yVel=4.2, speed ="Standard";
else if (velHash > 4) xVel = 6.8, yVel=6.8, speed ="Ultra Fast";
else bd = xVel = 5.5, yVel=5.5,  speed ="Fast";

let hashC = R.random_int(0, 27);
if (hashC > 26) cl[0]='#333333', cl[1]='#777777' ,cl[2]='#fca311', cl[3]='#aaaaaa', cl[4]='#44313d', pal="Coffee Break";
else if (hashC > 25) cl[0]='#db524c', cl[1]='#ff9a26' ,cl[2]='#ca2c5d', cl[3]='#336647', cl[4]='#1c3d28', pal="Bali";
else if (hashC > 24) cl[0]='#111419', cl[1]='#2f4423' ,cl[2]='#e4e19e', cl[3]='#f8c037', cl[4]='#605d94', pal="Summer Nights";
else if (hashC > 23) cl[0]='#7db457', cl[1]='#ce3d7e' ,cl[2]='#f481ce', cl[3]='#f9c5f3', cl[4]='#10202f', pal="Ice Cream";
else if (hashC > 22) cl[0]='#534c46', cl[1]='#aab0ac' ,cl[2]='#ffad01', cl[3]='#d91902', cl[4]='#4e252b', pal="Lombok";
else if (hashC > 21) cl[0]='#fe4236', cl[1]='#ff7d65' ,cl[2]='#d5a902', cl[3]='#8bb911', cl[4]='#2f6005', pal="80's Fun";
else if (hashC > 20) cl[0]='#c2ab1d', cl[1]='#51a62d' ,cl[2]='#ebef74', cl[3]='#e9de2a', cl[4]='#2a5124', pal="Sage";
else if (hashC > 19) cl[0]='#232740', cl[1]='#4a517b' ,cl[2]='#d7eaf8', cl[3]='#ffcb2a', cl[4]='#e69c33', pal="Mirage";
else if (hashC > 18) cl[0]='#532d1a', cl[1]='#a55733' ,cl[2]='#ca9760', cl[3]='#29e2e5', cl[4]='#485d3c', pal="Distopia";
else if (hashC > 17) cl[0]='#93cb9a', cl[1]='#f0b7bd' ,cl[2]='#f3e88e', cl[3]='#99e3ec', cl[4]='#50b4c3', pal="St Kilda";
else if (hashC > 16) cl[0]='#768290', cl[1]='#a8b2b3' ,cl[2]='#9d7f67', cl[3]='#863522', cl[4]='#2d1b0d', pal="Karma";
else if (hashC > 15) cl[0]='#5bc0eb', cl[1]='#fde74c' ,cl[2]='#9bc53d', cl[3]='#e55934', cl[4]='#fa7921', pal="Luminous";
else if (hashC > 14) cl[0]='#ff00c1', cl[1]='#9600ff' ,cl[2]='#4900ff', cl[3]='#00b8ff', cl[4]='#00fff9', pal="Neon";
else if (hashC > 13) cl[0]='#0b3954', cl[1]='#bfd7ea', cl[2]='#ff6663', cl[3]='#e0ff4f', cl[4]='#cccccc', pal="Spark";
else if (hashC > 12) cl[0]='#d81159', cl[1]='#8f2d56' ,cl[2]='#218380', cl[3]='#fbb13c', cl[4]='#73d2de', pal="Marrakesh";
else if (hashC > 11) cl[0]='#2b2d42', cl[1]='#edf2f4' ,cl[2]='#ef233c', cl[3]='#d90429', cl[4]='#b2c2c9', pal="Cadets";
else if (hashC > 10) cl[0]='#da8c2f', cl[1]='#d7bc8a', cl[2]='#d16a65', cl[3]='#8fdccd', cl[4]='#51c8be', pal="Popsicle";
else if (hashC > 9) cl[0]='#d72638', cl[1]='#3f88c5', cl[2]='#f49d37', cl[3]='#5a576c', cl[4]='#f22b29', pal="Retro";
else if (hashC > 8) cl[0]='#2e294e', cl[1]='#efbcd5', cl[2]='#be97c6', cl[3]='#8661c1', cl[4]='#4b5267', pal="Evening";
else if (hashC > 7) cl[0]='#E3E8EA', cl[1]='#222222', cl[2]='#9BA8AE', cl[3]='#707A7E', cl[4]='#495054', pal="Monochrome";
else if (hashC > 6) cl[0]='#b9e3c6', cl[1]='#59c9a5', cl[2]='#d81e5b', cl[3]='#23395b', cl[4]='#fffd98', pal="Dali";
else if (hashC > 5) cl[0]='#242323', cl[1]='#3a4e48', cl[2]='#6a7b76', cl[3]='#8b9d83', cl[4]='#beb0a7', pal="Metro";
else if (hashC > 4) cl[0]='#5E585F', cl[1]='#7D53DE', cl[2]='#78E3FD', cl[3]='#34F6F2', cl[4]='#D1F5FF', pal="Blue Neon";
else if (hashC > 3) cl[0]='#582936', cl[1]='#8c2f39', cl[2]='#b23a48', cl[3]='#fcb9b2', cl[4]='#fed0bb', pal="Reds";
else if (hashC > 2) cl[0]='#c1edcc', cl[1]='#b0c0bc', cl[2]='#a7a7a9', cl[3]='#797270', cl[4]='#453f3c', pal="Cabin Fever";
else if (hashC > 1) cl[0]='#bb216a', cl[1]='#ea42a1' ,cl[2]='#c3cced', cl[3]='#89a3bc', cl[4]='#325f89', pal="Passion";
else cl[0]='#780116', cl[1]='#f7b538', cl[2]='#db7c26', cl[3]='#d8572a', cl[4]='#c32f27', pal="Flames";

let bgHash = R.random_int(0, 10);
if (bgHash > 2) bg=('#000000'), bgName="Black";
else bg=('#ffffff'), bgName="White";

function setup() {
  let container = createDiv('');
  container.id('canvasContainer');
  container.style('width', '100%');
  container.style('height', '100vh');
  container.style('display', 'flex');
  container.style('justify-content', 'center');
  container.style('align-items', 'center');
  let canvas = createCanvas(w, h);
  canvas.parent(container);
  canvas.width = window.innerWidth * 2;
  canvas.height = window.innerHeight * 2;
  canvas.style("max-width", "100%");
  canvas.style("max-height", "100%");
  canvas.style("object-fit", "scale-down");
  randomize(cl);
  pixelDensity(pd);
  background(bg);
  strokeWeight(4);
  createWalkers(numWalkers);
  createWalkers2(numWalkers2);
  createWalkers3(numWalkers3);
  createWalkers4(numWalkers4);
  createWalkers5(numWalkers5);
}

function createWalkers(num) {
    for (let i = 0; i < num; i++) {
      let pos = createVector(
          (R.random_int(208, 2291)),
          (R.random_int(208, 2291))
      );
      walkers.push(
        new Walker(pos, createVector(0, 0))
      );
    }
}

function createWalkers2(num) {
    for (let i = 0; i < num; i++) {
      let pos = createVector(
        (R.random_int(R.random_int(1146, 1771), 2291)),
        (R.random_int(208, R.random_int(937,1563)))
      );
      walkers2.push(
        new Walker(pos, createVector(0, 0))
      );
    }
}

function createWalkers3(num) {
    for (let i = 0; i < num; i++) {
      let pos = createVector(
        (R.random_int(208, R.random_int(937,1563))),
        (R.random_int(R.random_int(1146, 1771), 2291))
      );
      walkers3.push(
        new Walker(pos, createVector(0, 0))
      );
    }
}

function createWalkers4(num) {
    for (let i = 0; i < num; i++) {
      let pos = createVector(
        (R.random_int(R.random_int(1146, 1771), 2291)),
        (R.random_int(R.random_int(1146, 1771), 2291))
      );
      walkers4.push(
        new Walker(pos, createVector(0, 0))
      );
    }
}

function createWalkers5(num) {
    for (let i = 0; i < num; i++) {
      let pos = createVector(
        (R.random_int(208, R.random_int(937,1563))),
        (R.random_int(208, R.random_int(937,1563)))
      );
      walkers5.push(
        new Walker(pos, createVector(0, 0))
      );
    }
}

function draw() {
    if (frameCount >1200) {
      for (let i = walkers.length-1; i >=0; i--) {
      walkers.splice(i,1);
      }
      for (let i = walkers2.length-1; i >=0; i--) {
      walkers2.splice(i,1);
      }
      for (let i = walkers3.length-1; i >=0; i--) {
      walkers3.splice(i,1);
      }
      for (let i = walkers4.length-1; i >=0; i--) {
      walkers4.splice(i,1);
      }
      for (let i = walkers5.length-1; i >=0; i--) {
      walkers5.splice(i,1);
    }

    } else
    {
    }
    walkers.forEach(
        walker => {
            if (!walker.isOut()) {
                walker.utVelocity();
                walker.move();
                stroke(cl[0]);
                walker.draw();
            }
        }
    );

    walkers2.forEach(
        walker2 => {
            if (!walker2.isOut()) {
                walker2.utVelocity();
                walker2.move();
                stroke(cl[1]);
                walker2.draw();
            }
        }
    );

    walkers3.forEach(
        walker3 => {
            if (!walker3.isOut()) {
                walker3.utVelocity();
                walker3.move();
                stroke(cl[2]);
                walker3.draw();
            }
        }
    );

    walkers4.forEach(
        walker4 => {
            if (!walker4.isOut()) {
                walker4.utVelocity();
                walker4.move();
                stroke(cl[3]);
                walker4.draw();
            }
        }
    );

    walkers5.forEach(
        walker5 => {
            if (!walker5.isOut()) {
                walker5.utVelocity();
                walker5.move();
                stroke(cl[4]);
                walker5.draw();
            }
        }
    );
}

class Walker {
    constructor(pos, v) {
        this.pos = pos;
        this.prevPos = pos;
        this.v = v;
    }
    isOut() {
        return (
            this.pos.x < 0.5 || this.pos.x > width || this.pos.y < 0.5 || this.pos.y > height
        );
    }
    utVelocity() {
        this.prevPos = createVector(this.pos.x, this.pos.y);
        this.v.x += xVel*Math.sin(this.pos.x/6);
        this.v.y += yVel*Math.sin(this.pos.y/6);
    }
    move() {
        this.pos = p5.Vector.add(this.pos, this.v);
    }
    draw() {
        point(this.prevPos.x, this.prevPos.y, this.pos.x, this.pos.y);
        this.prevPos = createVector(this.pos.x, this.pos.y);
    }
}

function randomize (arr)
{
    for (let i = arr.length - 1; i > 0; i--)
    {
        let j = Math.floor(R.random_dec() * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
    }
}

function keyPressed() {
	if (key == "s" | key == "S") save('Integration.jpg'); 
}