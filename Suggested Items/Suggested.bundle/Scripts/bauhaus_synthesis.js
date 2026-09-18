


class Random {
  constructor(tokendata) {
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
    // seed prngA with first half of tokenData.hash
    this.prngA = new sfc32(tokenData.hash.substring(2, 34));
    // seed prngB with second half of tokenData.hash
    this.prngB = new sfc32(tokenData.hash.substring(34, 66));
    for (let i = 0; i < 1e6; i += 2) {
      this.prngA();
      this.prngB();
    }
  }
  // random number between 0 (inclusive) and 1 (exclusive)
  random_dec() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  // random number between a (inclusive) and b (exclusive)
  random_num(a, b) {
    return a + (b - a) * this.random_dec();
  }
  // random integer between a (inclusive) and b (inclusive)
  // requires a < b for proper probability distribution
  random_int(a, b) {
    return Math.floor(this.random_num(a, b + 1));
  }
  // random boolean with p as percent liklihood of true
  random_bool(p) {
    return this.random_dec() < p;
  }
  // random value in an array of items
  random_choice(list) {
    return list[this.random_int(0, list.length - 1)];
  }
}

let R = new Random();


let particles = [];
let dicke; // Die Dicke der Linien
let img;
let img1;
let img2;
let img3;
let img4;
//let wx;
//let hy;
let rx;

let frameCounter;
let frameX;
let frameY;
let frameH;
let frameB;

let rectMulti; 

let scaleFactor;

let zufall;

let choice = R.random_int(1, 3);

let triangleMode;
let rectangleMode;
let ellipseMode;
let brightMode;
let darkMode;
let grayMode;

function setup() {
  createCanvas(windowWidth, windowHeight);
  scaleFactor = windowHeight/700;
  

 
  noFill();
  background(0);
  dicke = R.random_num(0.1, 1.5); // Initialisierung der Linienstärke
  
  frameCounter = 0;
frameX = 0;
frameY = 0;
frameH = 0;
frameB = 0;
  
rectMulti = R.random_num(0.5,4);
}

function draw() {

  


//resizeCanvas(windowWidth, windowHeight);
//redraw();
 //translate(50,0);
 
 
   frameCounter++;
   console.log("Durchlaufende Frames: " + frameCounter);

   
  
   stroke(40);
   strokeWeight(15);
   noFill();
   rect(0,0,width,height);
   strokeWeight(1);
   rect(width / 2 - 250, height / 2 - 250, 500, 500);
 
  
  

  




   if (frameCounter <= R.random_num(400, 600)){
  
   strokeWeight(dicke);
   img = get(25,25,width-50,height-50);
   fill(R.random_num(0, 255), R.random_num(0, 255), R.random_num(0, 255), R.random_num(200, 250));
   noFill();
   stroke(R.random_num(0,5));
  
  

  // Bewegung und Zeichnen der Partikel
    for (let i = particles.length - 1; i >= 0; i--) {
    particles[i].move();
    particles[i].display();
  }
  // Neue Partikel hinzufügen
  if (frameCount % 15 === 0) {
    let newParticle = new Particle(1);
    particles.push(newParticle);  
  }

  // Begrenzen Sie die Anzahl der Partikel, um die Leistung zu verbessern
  if (particles.length > R.random_num(50, 1500)) {
    particles.splice(1, 2);

  
    }
   
     
     
    } else {
      stroke(0);
      strokeWeight(1);
     rect(0, height/2,width,0.1);
     rect(width/2,0,0.1,height);
      
      rect(width / 2 - 250, 0, 0.1, height);
     rect(width / 2 + 250, 0, 0.1, height);
      
      rect(0, height/2-250, width, 0.1);
      rect(0, height/2+250, width, 0.1);
      
      
      zufall = R.random_num(0,10);

      if (zufall <=5){
      brightMode = "Bright";
      filter(INVERT);
      }
      darkMode = "Dark";
      
if (zufall <=2){
      grayMode = true;
      filter(GRAY);
      
      }
     
      
     
    noLoop();
             
   }

}



 function windowResized() {
  // Passe die Bildgröße an, wenn das Fenster verändert wird
  resizeCanvas(windowWidth, windowHeight);
  //scaleFactor = windowHeight/850;
  redraw();
}

class Particle {
  constructor(x, y) {
    this.x = x;
    this.y = y;
    this.color = color(R.random_num(0,255), R.random_num(0,255), R.random_num(0,255), R.random_num(150,255));
    this.radius = random(100, 1300);
    this.speed = R.random_num(3,6);
    this.angle = R.random_num(0, TWO_PI * 2);
  }

  move() {
    // Bewegung basierend auf zufälliger Geschwindigkeit und Richtung
    this.x += cos(this.angle) * this.speed;
    this.y += sin(this.angle) * this.speed;

    // Randüberprüfung
    if (this.x < 0 || this.x > width || this.y < 0 || this.y > height) {
      // Wenn das Partikel den Rand erreicht, setze es zurück
      this.x = R.random_num(0, width);
      this.y = R.random_num(0,height);
      this.angle = R.random_num(0, TWO_PI);
    }
  }

  display() {
  image(img, width/2 - (width/1.5)/2, height/2 - (height/1.5)/2, width/1.5, height/1.5);

  // Zufällige Auswahl einer Form
 

  // Allmähliche Änderung der Farbe
  this.color.levels[0] = (this.color.levels[0] + random(0.1, 2)) % 256;
  this.color.levels[1] = (this.color.levels[1] + random(0.1, 2)) % 256;
  this.color.levels[2] = (this.color.levels[2] + random(0.1, 2)) % 256;

  // Zeichnen des aktuellen Partikels mit transparenter Farbe
  stroke(this.color.levels[0], this.color.levels[1], this.color.levels[2], this.color.levels[3]);

  // Abhängig von der zufälligen Wahl die entsprechende Form zeichnen
  if (choice === 1) {
    triangleMode = true;
    triangle(this.x, this.y, this.x, this.x, this.y, this.x);
  } else if (choice === 2) {
    rectangleMode = true;
    rect(this.x, this.y, this.radius * rectMulti, this.radius * rectMulti);
  } else if (choice === 3) {
    ellipseMode = true;
    //ellipse(this.x, this.y, this.radius/2, this.radius/4);
    triangle(this.x, this.y, this.x, this.x, this.y, this.x);
  }
}


 
}
