let hashString = tokenData.hash;
let seed=parseInt(hashString.slice(0,16),16);



var num; //
let particle = [];

var t;


let dim;
let multiplier;
let xp;
let xp1;
let xp2;
let xp3;
let constrast_set;

function setup() {

     dim = windowHeight > windowWidth ? windowWidth : windowHeight;
     multiplier = dim / 3600;
     cnv = createCanvas(dim, dim);
     xp = map(rnd(), 0, 1, 0, 1); //trails
     xp1 = map(rnd(), 0, 1, 0, 1); //Background

     


     num = 3000
     if (this.xp <= 0.15) {
          num = 1500
     } else if (this.xp > 0.15 & this.xp <= 0.30) {
          num = 1500

     } else if (this.xp > 0.3 & this.xp <= 0.45) {
          num = 1500
     } else if (this.xp > 0.45 & this.xp <= 0.5) {
          num = floor(3000 / 4)

     }


     if (xp1 >= 0.95) {
       
          background(50);
     } else {
          background(255);
     }
     strokeWeight(multiplier);

     if (xp > 0.45) {
          t = new Target(new createVector(dim / 2, dim / 2));
     } else if (xp <= 0.15) {
          t = new Target(new createVector(dim / 2, dim));

     } else if (xp > 0.15 & xp <= 0.3) {
          t = new Target(new createVector(dim, dim / 2));

     } else if (xp > 0.3 & xp <= 0.45) {
          t = new Target(new createVector(0, dim / 2));
     }


     for (let i = 0; i < num; i++) {

          particle.push(new Particle(new createVector(map(rnd(), 0, 1, 50 * multiplier, dim - (50 * multiplier)), map(rnd(), 0, 1, 50 * multiplier, dim - (50 * multiplier))), xp));

     }
}

function draw() {


     t.move();

     t.update();

     t.Border_lock();
     for (let i = 0; i < num; i++) {
          particle[i].seek(t.location);
          particle[i].update();
          //particle[i].display();

     }
     if (xp > 0.45 & xp < 0.5) {
          if (frameCount == 750) {

               noLoop();

          }
     } else {
          if (frameCount == 1000) {

               noLoop();

          }
     }


}




class Target {
     constructor(position) {

          this.location = position.copy();
          this.velocity = createVector(0, 0);
          this.acceleration = new createVector(map(rnd(), 0, 1, -10 * multiplier, 10 * multiplier), map(rnd(), 0, 1, -10 * multiplier, 10 * multiplier));
          this.maxspeed = map(rnd(), 0, 1, 50 * multiplier, 100 * multiplier);
     }


     move() {
          this.velocity.add(this.acceleration);
          this.velocity.limit(this.maxspeed);
          this.location.add(this.velocity);
          this.acceleration.mult(0);
     }

     update() {
          var f = createVector(map(rnd(), 0, 1, -15 * multiplier, 15 * multiplier), map(rnd(), 0, 1, -15 * multiplier, 15 * multiplier));
          this.acceleration.add(f);

     }


     Border_lock() {

          if (this.location.x > width) {
               this.location.x = width;
               this.velocity.x *= -1;
          } else if (this.location.x < 0) {

               this.location.x = 0;
               this.velocity.x *= -1;

          }

          if (this.location.y > height) {
               this.location.y = height;
               this.velocity.y *= -1;

          } else if (this.location.y < 0) {
               this.location.y = 0;
               this.velocity.y *= -1;

          }

     }



}

function Particle(lo, x) {


     this.location = lo;
     this.velocity = createVector(map(rnd(), 0, 1, 10 * multiplier, 2 * dim / 10 * multiplier), map(rnd(), 0, 1, -dim / 10 * multiplier, dim / 10 * multiplier));
     this.acceleration = createVector(0, 0);
     this.maxspeed = map(rnd(), 0, 1, 10 * multiplier, 100 * multiplier);
     this.maxforce = map(rnd(), 0, 1, 0 * multiplier, 10 * multiplier);
     this.xp = x;
}

Particle.prototype.update = function() {
     var l1 = this.location.copy();
     this.velocity.add(this.acceleration);
     this.velocity.limit(this.maxspeed);
     this.location.add(this.velocity);
     this.acceleration.mult(0);
     var l2 = this.location.copy();
     if (xp1 >= 0.95) {
          stroke(255, 10);
     } else {
          stroke(0, 10);
     }
     line(l1.x, l1.y, l2.x, l2.y);
     if (this.xp <= 0.20) { //Mirror from bottom
          line(dim - l1.x, l1.y, dim - l2.x, l2.y);
     } else if (this.xp > 0.20 & this.xp <= 0.40) { //Mirror from Side

          line(dim - l1.x, dim - l1.y, dim - l2.x, dim - l2.y);

     } else if (this.xp > 0.4 & this.xp <= 0.6) { //Water from left
          line(l1.x, dim - l1.y, l2.x, dim - l2.y);

     } else if (this.xp > 0.6 & this.xp <= 0.7) { //4way
          line(dim - l1.x, l1.y, dim - l2.x, l2.y);
          line(dim - l1.x, dim - l1.y, dim - l2.x, dim - l2.y);
          line(l1.x, dim - l1.y, l2.x, dim - l2.y);
     }


}



Particle.prototype.applyForce = function(force) {
     this.acceleration.add(force);

}


Particle.prototype.seek = function(target) {

     var desired = p5.Vector.sub(target, this.location);
     desired.normalize();
     desired.mult(this.maxspeed);
     var steer = p5.Vector.sub(desired, this.velocity);
     steer.limit(this.maxforce);
     this.acceleration.add(steer);
}

function rnd() {


     seed ^= seed << 13;

     seed ^= seed >> 17;

     seed ^= seed << 5;

     return (((seed < 0) ? ~seed + 1 : seed) % 1000) / 1000;
}