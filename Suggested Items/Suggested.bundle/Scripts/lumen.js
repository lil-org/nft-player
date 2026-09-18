let hash = tokenData.hash;
            
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
                          let R = new Random();

            p5.disableFriendlyErrors = true;
            let t = 0.0;
            let pg;
            let runners = null;
            let finalCol;
            let palette = [ 
                 [['#e2e6ec', '#FF0000', '#00FF00', '#0000FF']],
                 [['#006dff',  '#00FF00', '#e2e6ec']],
                 [['#EB79F1', '#e2e6ec', '#d8ff00', '#78fffa']],
                 [['#00f0ff', '#e2e6ec', '#00FF00']],
                 [['#c6c7d5', '#cbff00', '#0000f4']],
                 [['#b084f7', '#cbff00', '#f4f1ee']],
                 [['#1db83c', '#cbff00', '#f4f1ee', '#e93326']],
                 [['#29ff00', '#d4d9dc', '#0000f4']],
                 [['#d7fe52', '#ed6ef7', '#eb4e4d', '#50b4ff', '#ffffff']],
                 [[ '#ff1500', '#bec544', '#ffffff']],
                 [['#b084f7','#ff5110', '#ffffff', '#5cf5ff']],
                 [['#00e000','#8000ff', '#fd0400']],
                [['#acff00', '#e2e6ec', '#00d8ff']],
                [[ '#0000ff', '#bec544', '#ffffff']],
                [['#ccff08', '#1d9eff', '#ebebeb']],
                [['#b084f7','#ccff08', '#ffffff', '#5cf5ff']],
                [['#00adcb', '#e2e6ec', '#ff5217']]
            ];
            
            let palette1;
            let palettePicker;
            let colorPicker;
            let numSystems;
            let canvas;
            let density = 1;
            let xx = false;
            let rainbow = false;
            let strokeSize;
            
            function setup() {
                canvas = createCanvas(windowWidth, windowHeight);
                let pgX = int(1920/4);
                let pgY = int(2020/4);
                pg = createGraphics(pgX, pgY, WEBGL);
                pg.colorMode(HSB, 360, 100, 100);
                start();
            }
            
            function draw() {        
                    background(0);
                    pg.clear();
                    pgShow();
                    imageMode(CENTER);
                    image(pg, windowWidth/2, windowHeight/2, windowWidth > windowHeight ? windowWidth : windowHeight, windowWidth < windowHeight ? windowHeight : windowWidth);
            }
    
            function windowResized() {
                resizeCanvas(windowWidth, windowHeight);
            }
            
            function pgShow(){
                t++;
                if(t==1){
                            for(let i=0; i<numSystems; i++){
                                colorPicker = floor(map(R.random_dec(), 0, 1, 0, palette[palettePicker][0].length));
                                if(i==2){
                                    finalCol = color(palette[palettePicker][0][palette[palettePicker][0].length-1]);
                                }else if(i==3){
                                    finalCol = color(palette[palettePicker][0][palette[palettePicker][0].length-2]);
                                }else{
                                    finalCol = color(palette[palettePicker][0][colorPicker]);
                                }
                                palette1[i] = finalCol;
                                runners.push(new ParticleSystem(palette1[i], i, pg.width, pg.height));
                            }
                }
            
                for(let i=0; i<runners.length; i++){
                    let p = runners[i];
                    p.addParticle();
                    p.display();
                }
            }
            
            function start(){
                t = 0.0;
                frameRate(30);
                noCursor();
                noiseSeed(4);
                runners = [];
                pg.noStroke();
                pg.colorMode(HSB, 360, 100, 100, 100);
                pg.rectMode(CENTER);
            
                canvas.imageSmoothingEnabled = false;
                canvas.style["image-rendering"] = "pixelated";
                pixelDensity(1);
                pg.pixelDensity(1);
                pg.noSmooth();
                noSmooth();
            
                palette1 = [];
                palettePicker = floor(map(R.random_dec(), 0, 1, 0, palette.length));
            
                   if(R.random_dec()<0.65){
                       density = 1;
                   }else{
                       density = 2;
                   }

                   if(density == 1){
                        numSystems = floor(R.random_num(24,30));
                   }else if(density == 2){
                        numSystems = floor(R.random_num(40,50));
                   }
        
                   if(R.random_dec()<0.15){
                    xx = true;
                   }else{
                    xx = false;
                   }
                   
                   if(R.random_dec()<0.05 && xx==false){
                    rainbow = true;
                   }else{
                    rainbow = false;
                   }
            
                   strokeSize = R.random_num(5, 30);
            
                console.log('the passage is open');
            }

            let ParticleSystem = function(tempCor, tempIndex, tempW, tempH) {
              this.particles = [];
              this.cor = tempCor;
              this.index = tempIndex;
              this.w = tempW;
              this.h = tempH;
              this.centerStart = R.random_num(8,20);
              this.maxSize = R.random_num(tempW/2, tempW);
              this.maxSize = R.random_num(tempW/2, tempW);
            
              if(density == 1){
                  this.dist = this.centerStart + this.index * R.random_num(10, 13);
              }else if(density == 2){
                  this.dist = this.centerStart + this.index * R.random_num(8, 10);
              }
              
              if(density == 1){
                  if(R.random_dec() < 0.9){
                      this.index<2 ? this.segments = floor(R.random_num(4, 14)) : this.segments = floor(R.random_num(4, 30)); 
                  }else{
                      this.index<2 ? this.segments = floor(R.random_num(4, 14)) : this.segments = floor(R.random_num(10, 30)); 
                  }
              }else if(density == 2){
                  this.index<3 ? this.segments = floor(R.random_num(4, 12)) : this.segments = floor(R.random_num(4, 50));
              }

              if(density == 1){
                  this.index<6 ? this.size = R.random_num(0.15, 0.3) : this.size = R.random_num(0.3, 0.7);  
              }else if(density == 2){
                  this.index<6 ? this.size = R.random_num(0.15, 0.3) : this.size = R.random_num(0.3, 0.7);
              }
              
              this.rot = R.random_num(0, 360);
              this.rotDiff = R.random_num(0.5, 1);
            
              if (density == 1){
                  this.dotSize = R.random_dec()<0.1 ? R.random_num(15, 30) : R.random_num(4, 15);
              }else if(density == 2){
                  this.dotSize = R.random_dec()<0.05 ? R.random_num(6, 14) : R.random_num(2, 15);
              }
              
              if(xx == true){
                  this.dotSize = R.random_num(10, 35);
                  this.index<3 ? this.segments = floor(R.random_num(4, 12)) : this.segments = floor(R.random_num(10, 20));
              }
        
              this.theShape;
              R.random_dec() > 0.5 ? this.theShape = "line" : this.theShape = "dot";
            
              if(this.index>0){
                  let p = runners[this.index-1];
                  if(p.theShape == "line"){
                      this.theShape = "dot";
                  }else{
                      this.theShape = "line";
                  }
              }
            };
            
            ParticleSystem.prototype.addParticle = function() {
              if(t==1){
                  for(let i = 0; i < this.segments; i++){
                      this.j = i * 360/this.segments;
              
                      this.xx = this.dist * cos(radians(this.j));
                      this.yy = this.dist * sin(radians(this.j));
                      
                      this.particles.push(new Particle(this.xx, this.yy, this.cor, i, this.index, this.size, this.theShape, this.dotSize, this.segments));
                      
                  }
              }
            }
            
            ParticleSystem.prototype.display = function() {
              pg.push();
              pg.rotate(radians(this.rot + t*this.rotDiff));
              let len = this.particles.length;
                  for(let i = 0; i < len; i++){
                      let particle = this.particles[i];
                          particle.force();
                          particle.update();
                          particle.display();
                  }
              pg.pop();
            
            }
            
            let Particle = function (x, y, tempCor, tempObjIndex, tempSysIndex, tempSize, tempShape, tempDotSize, tempSegments) {
              this.loc = createVector(0, 0);
              this.vel = createVector(0, 0);
              this.acc = createVector(0, 0);
              this.destiny = createVector(x, y);
              this.segments = tempSegments;
              this.cor = tempCor;
              this.index = tempObjIndex;
              this.sysIndex = tempSysIndex;
              this.theShape = tempShape;
              this.size = tempSize;
              this.dotSize = tempDotSize;
            }
            
            Particle.prototype.update = function() {
              this.vel.add(this.acc);
              this.loc.add(this.vel);
              this.vel.limit(3);
              this.acc.mult(0);
              this.vel.mult(0.9);
            }
            
            Particle.prototype.force = function () {
                  this.p = p5.Vector.sub(this.destiny, this.loc);
                  this.d = this.loc.dist(this.destiny);
                  this.p.normalize();
              if(this.d > 10){
                  this.p.mult(2);
                  this.applyForce(this.p);
              }else{
                  this.p.mult(0.05);
                  this.applyForce(this.p);
              }
            }
            
            Particle.prototype.applyForce = function(f) {
              this.acc.add(f);
            }
            
            Particle.prototype.display = function() {
                                  this.m = this.destiny.mag(0, 0);
                                  this.d = this.loc.dist(this.destiny);
                                  this.finalDotSize = map(this.d, 0, this.m, this.dotSize, 0);
            
                  if(this.theShape == "line"){
                      if(rainbow){
                          pg.fill(360);
                      }else{
                          pg.fill(this.cor);
                      }
                      
                      pg.push();
                      pg.translate(this.loc.x, this.loc.y);
                      pg.rotate(radians(this.index * (360/this.segments)+90));
                      pg.rect(0, 0, 1, strokeSize*this.size);
                      pg.pop();
            
                  }else{
                      if(rainbow){
                          this.finalCol = map(sin(radians(t + this.index*4 + this.sysIndex*4)), -1, 1, 0, 360);
                          pg.fill(this.finalCol, 100, 100);
                      }else{
                          pg.fill(this.cor);
                      }
                      pg.ellipse(this.loc.x, this.loc.y, this.finalDotSize, this.finalDotSize);
                  }
            
            }