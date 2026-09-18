
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

let selectedPaletteIndex; // Index der ausgewählten Farbpalette
let scaleValue;
let numColumns, numRows;
let zOffsetValue = 0;
let flowField = [];
let particles = [];
let colorPalettes = []; // Array für alle Farbpaletten
let numDivisions = 1;
let numFields = 1;
let alpha;
let anzahlPartikel;
let speedPartikel;
let größePartikel;
let anzahlRinge;
let farbSättigung;
let transparenz;
let displayStroke;
let displayStrokeWeight;
let noiseX;
let noiseY;
let typ;
let splitt = false;
let startEllipse = false;
let startRect = false;
let startBezier1 = false;
let startBezier2 = false;
let startArc = false;
let startTriangle = false;
let noiseStep = 10.0001; // Kleinere Schrittweite für mehr Details
let noiseScale = 110.5; // Größere Skala für einen längeren Fluss
let seed;
let hasDrawn = false;
let grainSize = 0.5; // Größe des Grain-Effekts
let grainDensity = 0.15; // Dichte des Grain-Effekts (0.0 - 1.0)
let maxWin;
let saveCounter = 0; // Zähler für gespeicherte Bilder
let grainR;
let grainG;
let grainB;
let grainA;
let numFields2 = 1;
let grainColor;
let grainOF = false;
let triangleRan = 4;
let triangleRan2 = 1;
let triangleRan3 = 1;
let angleRand = 4;

let test = "hhjkhjkh"

function setup() {

//////////////   seed = int($fx.rand()*9999999); //fxrand must be used to generate randomness on fxhash.  Making this a seed allows you to keep using p5 random and noise function (see below). Seeding also allows you to resize the canvas or change pixel densities and (hopefully) get the same output.
  
    restart();
   createCanvas(windowWidth / 1.3, windowHeight / 1.1);
   //createCanvas(2000 / 1.3, 2000 / 1.1);
    maxWin = min(windowWidth, windowHeight);
  
    background(222,184,135);
    grainA = 222;
    grainG = 184;
    grainB = 135;
    grainA = 65;
    addGrainEffect();
    
    alpha = 255;//////////////// $fx.getParam('transparenz');//floor(random(180, 255)); 

    initialize();
    generateColorPalettes();
    selectedPaletteIndex = floor(R.random_num(0,colorPalettes.length));   
}

    function initialize() {
        
             let v = R.random_choice([1,2,3,5,6,7,8]);
             
             ////////////////////////////////////////////////////////////
             if (v === 1) {
             typ = "Ethereal";
             splitt = false;
             grainOF = true;
             anzahlPartikel = R.random_num(maxWin*0.022, maxWin*0.080);
             speedPartikel = 4;
             größePartikel = maxWin*0.600;
             anzahlRinge = 0.96;
             farbSättigung = 0.000001;
             displayStroke = 0;
             displayStrokeWeight = 0;// maxWin*0.00007;
             alpha = 120;
             transparenz = floor(alpha/255*100);
             startEllipse = false;
             startRect = false;
             startBezier1 = true;
             startBezier2 = true;
             startArc = false;
             startTriangle = false;
             numFields = 1; //random([1]);
             angleRand = R.random_num(1, 360);
             
             //////////////////////////////////////////////////////////////  
               
         } else if (v === 2) {
             splitt = true;
             grainOF = false;
             typ = "Expressions";
             anzahlPartikel = 50;
             speedPartikel = 0.1;
             größePartikel = maxWin *0.6;
             anzahlRinge = 0.96;
             farbSättigung = 1;
             displayStroke = R.random_choice([0,255]);
             displayStrokeWeight = R.random_num(0,maxWin*0.0002);
             alpha = 235;
             transparenz = floor(alpha/255*100);
             startEllipse = false;
             startRect = true;
             startBezier1 = true;
             startBezier2 = true;
             startArc = false;
             startTriangle = true;
             numFields = 1; //random([1]);
             ///////////////////////////////////////////////////////////////////
           
         } else if (v === 3) {
             splitt = false;
             grainOF = false;
             typ = "Interactions";
             anzahlPartikel = R.random_choice([(maxWin * 0.05),(maxWin * 0.1),(maxWin * 0.15),(maxWin * 0.2),(maxWin * 0.3),(maxWin * 0.4),(maxWin * 0.6),(maxWin * 0.8)]);
             speedPartikel = 0.1;
             größePartikel = maxWin * 0.5;
             anzahlRinge = 0.96;
             farbSättigung = 0.0001;
             displayStroke = R.random_choice([0,255]);
             displayStrokeWeight = 0.1;
             alpha = 160;
             transparenz = floor(alpha/255*100);
             startEllipse = false;
             startRect = false;
             startBezier1 = false;
             startBezier2 = false;
             startArc = false;
             startTriangle = true;
             numFields = 1; //random([1]);
             triangleRan = R.random_choice([90, 180]);
             triangleRan2 = R.random_num(0,3);
             triangleRan3 = 0;
             angleRand = 0;
             /////////////////////////////////////////////////////////////////
           
         } else if (v === 4) {
             splitt = true;
             grainOF = false;
             typ = "Exploring Artistry";
             anzahlPartikel = floor(R.random_num(maxWin*0.003,maxWin*0.006));
             speedPartikel = 0.1;// random([0.1]);
             größePartikel = 0.7 * maxWin;
             anzahlRinge = 0.7;
             farbSättigung = 1;
             displayStroke = R.random_choice([0,220]);
             displayStrokeWeight = maxWin*0.0002;
             alpha = floor(R.random_num(160, 255)); 
             transparenz = floor(alpha/255*100);
             numFields = random([1]);
             startEllipse = true;
             startRect = false;
             startBezier1 = false;
             startBezier2 = true;
             startArc = false;
             startTriangle = false;
             //////////////////////////////////////////////////////////////////
           
         } else if (v === 5) {
           splitt = false;
             grainOF = false;
             typ = "Abstraction";
             anzahlPartikel = 10;//floor(random(10,15));
             speedPartikel = 0.1;//random([0.1]);
             größePartikel = 3.5 * maxWin;
             anzahlRinge =  R.random_choice([0.8, 0.81, 0.82, 0.83, 0.84, 0.85, 0.86, 0.87, 0.88, 0.89, 0.90]);
             farbSättigung = 0.8;
             displayStroke = 0;
             displayStrokeWeight = maxWin*0.0005;
             alpha = 255; 
             transparenz = floor(alpha/255*100);
             numFields = 1; //random([2]);
             startEllipse = false;
             startRect = true;
             startBezier1 = false;
             startBezier2 = true;
             startArc = false;
             startTriangle = true;
             ////////////////////////////////////////////////////////////////
           
         } else if (v === 6) {
           splitt = true;
             grainOF = false;
             typ = "Variety";
             anzahlPartikel = floor(R.random_num(maxWin*0.05,maxWin*0.1));
             speedPartikel = 0.1;//random([5]);
             größePartikel = random([maxWin*0.04,maxWin*0.08,maxWin*0.16,maxWin*0.32,maxWin*0.64,maxWin*1.25,maxWin*2.55,maxWin*3.55]);
             anzahlRinge =  R.random_choice([0.8, 0.81, 0.82, 0.83, 0.84, 0.85, 0.86, 0.87, 0.88, 0.89, 0.90]);
             farbSättigung = 0.01;
             displayStroke = 255;
             displayStrokeWeight = maxWin*0.00007;
             alpha = 25; 
             transparenz = floor(alpha/255*100);
             numFields = random(20,80);
             startEllipse = true;
             startRect = true;
             startBezier1 = true;
             startBezier2 = true;
             startArc = true;
             startTriangle = true;
             ////////////////////////////////////////////////////////////////////
           
         } else if (v === 7) {
            splitt = true;
             grainOF = false;
             typ = "Aesthetics";
             anzahlPartikel = floor(R.random_num(maxWin*0.022, maxWin*0.080));
             speedPartikel = 1;
             größePartikel = maxWin*0.600;
             anzahlRinge = 0.38;
             farbSättigung = 0.000001;
             displayStroke = 0;
             displayStrokeWeight = 0.1;// maxWin*0.00007;
             alpha = 100;
             transparenz = floor(alpha/255*100);
             startEllipse = false;
             startRect = false;
             startBezier1 = false;
             startBezier2 = true;
             startArc = false;
             startTriangle = false;
             numFields = 1; //random([1]);
             angleRand = R.random_num(90, 360);
             //////////////////////////////////////////////////////////////////
           
         } else if (v === 8) {
             splitt = true;
             grainOF = false;
             typ = "Creation";
             anzahlPartikel = floor(R.random_num(maxWin*0.022, maxWin*0.080));
             speedPartikel = R.random_num(1,10);
             größePartikel = maxWin*0.600;
             anzahlRinge = 0.96;
             farbSättigung = 0.000001;
             displayStroke = 0;
             displayStrokeWeight = 0;// maxWin*0.00007;
             alpha = 100;
             transparenz = floor(alpha/255*100);
             startEllipse = false;
             startRect = false;
             startBezier1 = true;
             startBezier2 = true;
             startArc = false;
             startTriangle = false;
             numFields = 1; //random([1]);
             angleRand = R.random_num(1, 180);
         }
             ///////////////////////////////////////////////////////////////////////
      
     
     
         scaleValue = 3;
         colorMode(RGB);
         generateColorPalettes();
         selectedPaletteIndex = floor(random(colorPalettes.length));
         
         numColumns = floor(width / scaleValue);
         numRows = floor(height / scaleValue);
         flowField = new Array(numColumns * numRows);
         calculateFlowField();
     
         particles = []; // Vorherige Partikel löschen
         for (let i = 0; i < anzahlPartikel; i++) {
             particles.push(new Particle());  
         }
     }
     
function draw() {
  
  
 
    if (!hasDrawn) {
        
    for (const particle of particles) {
        particle.follow(flowField);
        particle.update();
        particle.edges();
        particle.display();
    }

    let allParticlesDead = particles.every(particle => particle.size < 1);
    if (allParticlesDead) {
        //divideScreen();
    if (splitt){
       applyEffectsToFields();
    }
      
      if (grainOF) {
      grainA = 200;//222;
      grainG = 200;//184;
      grainB = 200;//135;
      grainA = 60;//45;
      addGrainEffect();
      }
     

      /////////////////////////////$fx.preview();
      hasDrawn = true;

      stroke(80,80,80, 50);
      strokeWeight(0.115*maxWin);
      noFill();
      rect(0, 0, width, height);
      noStroke();
      
      stroke(253,245,230);
      strokeWeight(0.11*maxWin);
      noFill();
      rect(0, 0, width, height);
      noStroke(); 
      
      
    }
      
  } 
     
}

function calculateFlowField() {
    for (let y = 0; y < numRows; y++) {
        for (let x = 0; x < numColumns; x++) {
            const index = x + y * numColumns;
            const angle = angleRand;//R.random_dec(TWO_PI); // Konstanter horizontaler Winkel
            flowField[index] = p5.Vector.fromAngle(angle).setMag(1);
        }
    }
  
}




// Beispiel für eine benutzerdefinierte Winkelfunktion
function customAngleFunction(x, y) {
    return atan2(y - height / 2, x - width / 2); // Winkel vom Zentrum aus
}




function divideScreen() {
    for (let i = 0; i < numFields; i++) {
        for (let j = 0; j < numFields; j++) {
            let x = width / numFields * i;
            let y = height / numFields * j;
            let w = R.random_num(width / numFields / 2, width / numFields * 1.5);
            let h = R.random_num(height / numFields / 2, height / numFields * 1.5);
        }
    }
}

function applyEffectsToFields() {
    for (let i = 0; i < numFields; i++) {
        for (let j = 0; j < numFields; j++) {
            let x = width / numFields * i;
            let y = height / numFields * j;
            let w = width / numFields;
            let h = height / numFields;
          
            let chosenPalette = colorPalettes[selectedPaletteIndex]; 

            // Zufälligen Effekt auswählen und auf das Feld anwenden
            let effectChoice = R.random_dec(50);
            if (effectChoice === 0) {

                
                // Effekt 1: Horizontal spiegeln
                push();
                translate(x, y + h /2);
                scale(1, -1);
                image(get(x, y, w, h /2), 0, -h / 2);
                pop();
            } else {
                // Effekt 2: Vertikal spiegeln
                push();
                translate(x + w / 2, y-1);
                scale(-1, 1);
                image(get(x, y, w / 2, h), -w / 2, 0);
                pop();
            }
        }
    }
    
}

class Particle {
    constructor() {
        this.position = createVector(R.random_num(0,width), R.random_num(0,height));
        this.velocity = createVector(R.random_num(0,width), R.random_num(0,height));
        this.acceleration = createVector(R.random_num(0,360), R.random_num(0,360));
        this.maxSpeedValue = speedPartikel;
        this.size = größePartikel;
        this.currentColor = getRandomColor();
        this.targetColor = this.currentColor;
    }

    update() {
        this.velocity.add(this.acceleration);
        this.velocity.limit(this.maxSpeedValue);
        this.position.add(this.velocity);
        this.acceleration.mult(0);
        this.size *= anzahlRinge;

        let newColor = getRandomColor();
      
        this.currentColor = lerpColor(this.currentColor, newColor, farbSättigung);
    }

    applyForce(force) {
        this.acceleration.add(force);
    }

    follow(vectors) {
        const x = floor(this.position.x / scaleValue);
        const y = floor(this.position.y / scaleValue);
        const index = x + y * numColumns;
        const force = vectors[index];
        this.applyForce(force);
    }

    display() {
        fill(this.currentColor);
        stroke(displayStroke);
        strokeWeight(displayStrokeWeight);
      
      if (startEllipse){
       ellipse(this.position.x, this.position.y, this.size, this.size);
      }
        
      if (startRect){
        rect(this.position.x, this.position.y, this.size, this.size);
        }
        
      if (startBezier1){
        bezier(this.position.x - this.size / 2/R.random_num(0.5,0.6), this.position.y,
               this.position.x - this.size / 4/R.random_num(0.5,0.6), this.position.y - this.size / 2/R.random_num(0.5,0.6),
               this.position.x + this.size / 4/R.random_num(0.5,0.6), this.position.y + this.size / 2,
               this.position.x + this.size / 2, this.position.y);
        }
      
       if (startBezier2){
      //Zusätzliche Bézierkurve
       bezier(this.position.x, this.position.y - this.size / 2/R.random_num(-0.9,0.9),
               this.position.x - this.size / 2/R.random_num(-0.9,0.9), this.position.y - this.size / 2/R.random_num(-0.9,0.9),
               this.position.x + this.size / 2/0.1, this.position.y + this.size / 2,
               this.position.x, this.position.y + this.size / 2);
         
     
         }
      
      if (startArc){
              arc(this.position.x, this.position.y, this.size * 1.5, this.size * 1.5, PI, TWO_PI);
      }
      if (startTriangle){
     let triangleSize = this.size ;//* maxWin * 0.00018;
let triangleHeight = triangleSize * Math.sqrt(3);

// Winkel für die Rotation in Radiant
let rotationAngle = Math.PI / triangleRan; // Hier können Sie den Rotationswinkel nach Bedarf ändern

       
        
// Ursprüngliche Positionen der Dreieckspunkte
let x1 = this.position.x - triangleSize / 2/triangleRan2;
let y1 = this.position.y + this.size / 2;
let x2 = this.position.x + triangleSize / 2;
let y2 = this.position.y + this.size / 2;
let x3 = this.position.x;
let y3 = this.position.y - triangleHeight / 2;

// Rotationszentrum - in diesem Fall verwenden wir den Schwerpunkt des Dreiecks
let centerX = (x1 + x2 + x3) / 3;
let centerY = (y1 + y2 + y3) / 3;

// Rotationsformel anwenden
let rotatedX1 = centerX + (x1 - centerX) * Math.cos(rotationAngle) - (y1 - centerY) * Math.sin(rotationAngle);
let rotatedY1 = centerY + (x1 - centerX) * Math.sin(rotationAngle) + (y1 - centerY) * Math.cos(rotationAngle);

let rotatedX2 = centerX + (x2 - centerX) * Math.cos(rotationAngle) - (y2 - centerY) * Math.sin(rotationAngle);
let rotatedY2 = centerY + (x2 - centerX) * Math.sin(rotationAngle) + (y2 - centerY) * Math.cos(rotationAngle);

let rotatedX3 = centerX + (x3 - centerX) * Math.cos(rotationAngle) - (y3 - centerY) * Math.sin(rotationAngle);
let rotatedY3 = centerY + (x3 - centerX) * Math.sin(rotationAngle) + (y3 - centerY) * Math.cos(rotationAngle);

// Dreieck zeichnen
triangle(rotatedX1, rotatedY1, rotatedX2, rotatedY2, rotatedX3, rotatedY3);
}
        
    }

    edges() {
        if (this.position.x > width) {
            this.position.x = 0;
        } else if (this.position.x < 0) {
            this.position.x = width;
        }
        if (this.position.y > height) {
            this.position.y = 0;
        } else if (this.position.y < 0) {
            this.position.y = height;
        }
    }
}

// Funktion zum Generieren der Farbpaletten
function generateColorPalettes() {
    
    // Farbpalette 0 Vintage 1950er Jahre
    let colorPalette1 = [
     
        color(128,173,215, alpha),    // DarkBlue
        color(10,189,160, alpha),// CadetBlue1
        color(235,242,234, alpha),   // SaddleBrown
        color(212,220,169, alpha),  // Brown
        color(50,50,50, alpha),  
      
        
    ];
    colorPalettes.push(colorPalette1);


    // Farbpalette 1 Retro
    let colorPalette2 = [
        
        color(192,51,77, alpha),       // Gelb
        color(214,97,143, alpha), // Black
        color(243,212,160, alpha), // Black
        color(241,147,27, alpha), // Black
        color(143,113,91, alpha), // Black
       color(0,0,0, alpha), 
       color(255,255,255, alpha), 
      
        
        
    ];
    colorPalettes.push(colorPalette2);

    // Weitere Farbpaletten definieren...

    // Farbpalette 2 70er Jahre
    let colorPalette3 = [
        
        color(31,22,65, alpha), // Cyan
        color(1,33,114, alpha), // DarkOrange
        color(4,134,219, alpha), // Purple
        color(5,172,211, alpha),  // RedOrange
        color(187,191,149, alpha),    // DarkGreen
     color(0,0,0, alpha), 
       color(255,255,255, alpha), 
     
     
    ];
    colorPalettes.push(colorPalette3);

    // Farbpalette 3 Skyline
    let colorPalette4 = [
        
        color(82,46,117, alpha),      // DarkBlue
        color(2,8,15, alpha),  // CadetBlue1
        color(82,89,31, alpha),    // SaddleBrown
        color(163,118,93, alpha),   // Brown
        color(113,78,61, alpha),   // DarkOliveGreen1
      color(0,0,0, alpha), 
       color(255,255,255, alpha),  
      
    ];
    colorPalettes.push(colorPalette4);

    // Farbpalette 4 Summer Blue
    let colorPalette5 = [
        
        color(213,11,83, alpha), // White
        color(244,243,244, alpha), // Gray
        color(168,130,193, alpha),   // Magenta
        color(130,76,167, alpha),   // Orange
        color(185,196,6, alpha),      // Blue
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
      
    ];
    colorPalettes.push(colorPalette5);

    // Farbpalette 5 Refreshing
    let colorPalette6 = [
        
        color(0,61,115, alpha), // Pink
        color(8,120,164, alpha),     // Lime
        color(30,207,214, alpha),     // Maroon
        color(237,209,112, alpha),   // Yellow
        color(192,86,64, alpha),    // Aqua
      color(0,0,0, alpha), 
       color(255,255,255, alpha),  
      
    ];
    colorPalettes.push(colorPalette6);

    // Farbpalette 6 Aquamarine
    let colorPalette7 = [
        
        color(85,217,192, alpha),   // DarkMagenta
        color(199,246,236, alpha),    // RedOrange
        color(16,112,80, alpha), // Gray
        color(2,35,28, alpha),   // Yellow
        color(77,216,173, alpha),    // Aqua
      color(0,0,0, alpha), 
       color(255,255,255, alpha),  
      
    ];
    colorPalettes.push(colorPalette7);

    // Farbpalette 7 Sunset
    let colorPalette8 = [
        
        color(88,42,32, alpha),   // Gold
        color(190,112,82, alpha),     // Green
        color(241,222,209, alpha),     // Blue
        color(242,192,131, alpha), // Pink
        color(148,153,166, alpha),    // Purple
      color(0,0,0, alpha), 
       color(255,255,255, alpha),   
    ];
    colorPalettes.push(colorPalette8);

    // Farbpalette 8 kaleidoscope
    let colorPalette9 = [
       
        color(90,163,130, alpha),   // Tomato
        color(120,214,172, alpha),   // Orange
        color(189,167,40, alpha),   // Gold
        color(112,67,7, alpha),   // Teal
        color(247,177,120, alpha),    // MidnightBlue
      color(0,0,0, alpha), 
       color(255,255,255, alpha),   
      
    ];
    colorPalettes.push(colorPalette9);

    // Farbpalette 9 Fruity
    let colorPalette10 = [
        
        color(217,220,216, alpha),     // DarkRed
        color(155,167,71, alpha), // LightPink
        color(242,157,75, alpha),   // SpringGreen
        color(213,112,48, alpha),     // Blue
        color(139,40,31, alpha),     // RedOrange
      color(0,0,0, alpha), 
       color(255,255,255, alpha),  
      
      
    ];
    colorPalettes.push(colorPalette10);
  
  // Farbpalette 10 Mediterran
    let colorPalette11 = [
       
        color(140,0,4, alpha),     // DarkRed
        color(200,0,10, alpha), // LightPink
        color(232,167,53, alpha),   // SpringGreen
        color(226,196,153, alpha),     // Blue
      color(0,0,0, alpha), 
       color(255,255,255, alpha),   

     
      
    ];
    colorPalettes.push(colorPalette11);
  
  // Farbpalette 11 Random
    let colorPalette12 = [
        
        color(0,0,0, alpha), 
       color(255,255,255, alpha), 
        
        

    ];
    colorPalettes.push(colorPalette12);
  ///////////////////////////////////////////////////////////////////////
  // Farbpalette 12 Random
    let colorPalette13 = [
        color(249,136,102, alpha), 
        color(255,66,14, alpha), 
        color(128,189,158, alpha), 
        color(137,218,89, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
       
    ];
    colorPalettes.push(colorPalette13);
  
  // Farbpalette 13 Random
    let colorPalette14 = [
        color(70,33,26, alpha), 
        color(105,61,61, alpha), 
        color(186,85,54, alpha), 
        color(164,56,32, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha),    
      
    ];
    colorPalettes.push(colorPalette14);
  
  // Farbpalette 14 Random
    let colorPalette15 = [
        color(80,81,96, alpha), 
        color(104,130,158, alpha), 
        color(174,189,56, alpha), 
        color(89,130,52, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha),   
       
    ];
    colorPalettes.push(colorPalette15);
  
  // Farbpalette 15 Random
    let colorPalette16 = [
        color(46,70,0, alpha), 
        color(72,107,0, alpha), 
        color(162,197,35, alpha), 
        color(125,68,39, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
      
    ];
    colorPalettes.push(colorPalette16);
  
  // Farbpalette 16 Random
    let colorPalette17 = [
        color(2,28,30, alpha), 
        color(0,68,69, alpha), 
        color(44,120,115, alpha), 
        color(111,185,143, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha),  
        
         
    ];
   colorPalettes.push(colorPalette17);
  
  // Farbpalette 17 Random
    let colorPalette18 = [
        color(55,94,151, alpha), 
        color(251,101,66, alpha), 
        color(255,187,0, alpha), 
        color(63,104,28, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha),  
        
        
    ];
   colorPalettes.push(colorPalette18);
  
  // Farbpalette 18 Random
    let colorPalette19 = [
        color(152,219,198, alpha), 
        color(91,200,172, alpha), 
        color(230,215,42, alpha), 
        color(241,141,158, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
        
        
    ];
   colorPalettes.push(colorPalette19);
  
  // Farbpalette 19 Random
    let colorPalette20 = [
        color(50,72,81, alpha), 
        color(134,172,65, alpha), 
        color(52,103,92, alpha), 
        color(125,163,161, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
        
         
    ];
   colorPalettes.push(colorPalette20);
  
  // Farbpalette 20 Random
    let colorPalette21 = [
        color(0,0,0, alpha), 
        color(255,255,255, alpha), 
        color(0,0,0, alpha), 
        color(0,0,0, alpha), 
       color(255,255,255, alpha), 
       
        
        
    ];
   colorPalettes.push(colorPalette21);
  
  // Farbpalette 21 Random
    let colorPalette22 = [
        color(76,181,245, alpha), 
        color(183,184,182, alpha), 
        color(52,103,92, alpha), 
        color(179,193,0, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
        
        
    ];
   colorPalettes.push(colorPalette22);
  
  // Farbpalette 22 Random
    let colorPalette23 = [
        color(255,255,255, alpha), 
        color(0,0,0, alpha), 
        color(255,255,255, alpha), 
        color(0,0,0, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
         
    ];
   colorPalettes.push(colorPalette23);
  
  // Farbpalette 23 Random
    let colorPalette24 = [
        color(244,204,112, alpha), 
        color(222,122,34, alpha), 
        color(32,148,139, alpha), 
        color(106,177,135, alpha), 
     color(0,0,0, alpha), 
       color(255,255,255, alpha),  
        
         
    ];
   colorPalettes.push(colorPalette24);
  
  // Farbpalette 24 Random
    let colorPalette25 = [
        color(141,35,15, alpha), 
        color(30,67,76, alpha), 
        color(155,79,15, alpha), 
        color(201,158,16, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha),   
        
        
    ];
   colorPalettes.push(colorPalette25);
  
  // Farbpalette 25 Random
    let colorPalette26 = [
        color(241,241,242, alpha), 
        color(188,186,190, alpha), 
        color(161,214,226, alpha), 
        color(25,149,173, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha),   
        
       
    ];
   colorPalettes.push(colorPalette26);
  
  // Farbpalette 26 Random
    let colorPalette27 = [
        color(154,158,171, alpha), 
        color(93,83,94, alpha), 
        color(236,150,164, alpha), 
        color(223,225,102, alpha), 
     color(0,0,0, alpha), 
       color(255,255,255, alpha), 
        
        
    ];
   colorPalettes.push(colorPalette27);
  
  // Farbpalette 27 Random
    let colorPalette28 = [
        color(1,26,39, alpha), 
        color(6,56,82, alpha), 
        color(240,129,15, alpha), 
        color(230,223,68, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
        
      
    ];
   colorPalettes.push(colorPalette28);
  
  // Farbpalette 28 Random
    let colorPalette29 = [
        color(54,50,55, alpha), 
        color(45,66,98, alpha), 
        color(115,96,91, alpha), 
        color(208,150,131, alpha), 
     color(0,0,0, alpha), 
       color(255,255,255, alpha), 
        
         
    ];
   colorPalettes.push(colorPalette29);
  
  // Farbpalette 29 Random
    let colorPalette30 = [
        color(15,27,7, alpha), 
        color(255,255,255, alpha), 
        color(92,130,26, alpha), 
        color(198,209,102, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha), 
        
         
    ];
   colorPalettes.push(colorPalette30);
  
  // Farbpalette 30 Random
    let colorPalette31 = [
        color(0,41,60, alpha), 
        color(30,101,109, alpha), 
        color(241,243,206, alpha), 
        color(246,42,0, alpha), 
      color(0,0,0, alpha), 
       color(255,255,255, alpha),  
        
         
    ];
   colorPalettes.push(colorPalette31);
  
}

// Funktion zur Auswahl einer zufälligen Farbe aus der ausgewählten Farbpalette
function getRandomColor() {
    const chosenPalette = colorPalettes[selectedPaletteIndex];
    const colorIndex = floor(R.random_num(0,chosenPalette.length));
    return chosenPalette[colorIndex];
  
}




function restart(){
     
    randomSeed(seed);
    noiseSeed(seed);
   
}

function windowResized() {
   
   restart();
   resizeCanvas(windowWidth, windowHeight);
  
   numColumns = floor(width / scaleValue);
   numRows = floor(height / scaleValue);
   flowField = new Array(numColumns * numRows);
   calculateFlowField();

   particles = []; // Vorherige Partikel löschen
   for (let i = 0; i < anzahlPartikel; i++) {
       particles.push(new Particle());

   }
   hasDrawn = false
  }


  function addGrainEffect() {
    for (let y = 0; y < height; y += grainSize) {
      for (let x = 0; x < width; x += grainSize) {
        if (R.random_dec(1) < grainDensity) {
          grainColor = color(grainA,grainG,grainB,grainA); // Zufällige RGB-Werte
         
          fill(grainColor);
          noStroke();
          rect(x, y, grainSize, grainSize);
        }
      }
    }
  }

  function keyPressed() {
    if (key === 's' || key === 'S') {
      // Wenn die Taste 's' oder 'S' gedrückt wurde, speichere den Bildschirminhalt
      saveCanvas('myCanvas' + saveCounter, 'png'); // Speichert das Canvas als PNG-Datei
      saveCounter++; // Inkrementiere den Zähler für den Dateinamen
    }
  }




