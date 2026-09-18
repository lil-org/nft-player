// VIVOTECA
// bustavo x The Generative Art Museum
// September, 2025
const alternateColorIndex = parseInt(tokenData.hash.slice(2, 10), 16) % 4;
const seed = parseInt(tokenData.hash.slice(0, 16), 16);
const hashPairs = [];
for (let j = 0; j < 32; j++) {hashPairs.push(tokenData.hash.slice(2 + (j * 2), 4 + (j * 2)))};
const decPairs = hashPairs.map(x => {return parseInt(x, 16)});
let rColor = decPairs[28];
let gColor = decPairs[29];
let bColor = decPairs[30];
const aColors = [{'rc': 255, 'gc': 0, 'bc': 200},{'rc': 255, 'gc': 0, 'bc': 50},{'rc': 0, 'gc': 255, 'bc': 255},{'rc': 255, 'gc': 255, 'bc': 0},{'rc': 255, 'gc': 255, 'bc': 0}];
let alternateColor, highlightColor, mainColor, strokeColor, luminance;
let noiseLevels = [1000,2500,5000,10000];
let noiseLevel = noiseLevels[parseInt(tokenData.hash.slice(2, 10), 16) % 4];
let pg, pg2, pg3, pg4, pgbg;
let tilePool = [];
let tileIndex = 0;
let spherePool = [];
let sphereIndex = 0;
let sphere_no_repeat = 1.0;
let pointPool = [];
let pointIndex = 0;
let sq_x = 2.0;
let sq_y = 0.5;
let step = sq_y;
let torus_size = 0.53;
let torus_width = 0.0;
let torus_height = 0.0;
let animate_bg = false;
let tilesPerFrame = 300;
let reload_bg = true;
let force_reload_highglights = false;
let loadSpheres = false;
let shouldShufflePoints = true;
let startFrame = 0;
let x_noise = 0.001;
let y_noise = 0.0008;
let small_screen = false;
let min_noise = 8600;
let saw_min_noise = 0;

function setup() {
  createCanvas(windowWidth, windowHeight);
  pg = createGraphics(width, height); 
  pg2 = createGraphics(width, height); 
  pg3 = createGraphics(width, height); 
  pg4 = createGraphics(width, height); 
  pgbg = createGraphics(width, height); 
  pgbg.background(0);
  randomSeed(seed);
  noiseSeed(seed);
  noiseDetail(3);
  luminance = 0.2126 * rColor + 0.7152 * gColor + 0.0722 * bColor;
  const min_lum = 60.0;

  if (luminance < min_lum) {
    const adjustment = (min_lum - luminance) / (255.0 - luminance);
    rColor = Math.round(rColor + adjustment * (255.0 - rColor));
    gColor = Math.round(gColor + adjustment * (255.0 - gColor));
    bColor = Math.round(bColor + adjustment * (255.0 - bColor));
  }  

  highlightColor = color(aColors[alternateColorIndex]['rc'],aColors[alternateColorIndex]['gc'],aColors[alternateColorIndex]['bc']);
  alternateColor = color(max(rColor*0.5,0),max(gColor*0.5,0),max(bColor*0.5,0));
  strokeColor = color(2,2,2);  
  torus_width = width * 0.2;
  torus_height = height * 0.2;
  small_screen = (width < 1000 || height < 1000) ? true : false;

  pg3.drawingContext.shadowBlur = 10;
  pg3.drawingContext.shadowColor = highlightColor;
  pg4.drawingContext.shadowBlur = 10;
  pg4.drawingContext.shadowColor = highlightColor;
  
  if ( small_screen ) {
    noiseLevel = 3000;
    sq_x = 4.0;
    sq_y = 1.0;
    step = sq_y;
    torus_width = width * 0.25;
    torus_height = height * 0.25;
    
    if ( torus_height > torus_width ) {
      torus_height = torus_width;
    } else if ( torus_width > torus_height ) {
      torus_width = torus_height;
    }
  }
  
  generate();
}

function draw() {
  if (frameCount > startFrame) {
    if (animate_bg)
      tilesPerFrame = 50.0;

    for (let i=0; i<tilesPerFrame; i++) {
      if (tileIndex >= tilePool.length) {
        if (animate_bg) {
          animate_bg = false;
        } else {
          reload_bg = false;
          animate_bg = true;
        }
        force_reload_highglights = saw_min_noise < parseFloat(tilePool.length)*0.1 ? true : false;
        min_noise = force_reload_highglights ? min_noise*0.8 : min_noise;
        saw_min_noise = 0;
        tileIndex = 0;
        startFrame = frameCount + 0;
        loadSpheres = true;
        break;
      }

      const { dx, dy, displace, x_off, y_off, sphere } = tilePool[tileIndex];
      const torus_tile = new TorusTile(width / 2 + x_off,height / 2 + y_off,torus_width,torus_height,dy,dx,displace,sphere);
      torus_tile.display();
      tileIndex++;
    }
  }

  if (!reload_bg) {
    if ( pointPool.length > 0 )
      tilesPerFrame = ( frameRate() > 60 ) ? tilesPerFrame*1.2 : tilesPerFrame*0.8 < 10 ? 10 : tilesPerFrame*0.8;
    
    if (pointPool._sinceCompact == null) {
      pointPool._sinceCompact = 0;
      pointPool._compactEvery = 50000;
    }

    for (let i = 0; i < tilesPerFrame; i++) {
      if (pointIndex >= pointPool.length) {
        if (pointIndex > 0) {
          pointPool.splice(0, pointIndex);
          pointIndex = 0;
          pointPool._sinceCompact = 0;
        }
        break;
      }

      const p = pointPool[pointIndex];

      if (p) {
        const px = p.px, py = p.py;
        let lay = (random() > 0.12) ? pg4 : pg3;
        lay.stroke(aColors[alternateColorIndex]['rc'],aColors[alternateColorIndex]['gc'],aColors[alternateColorIndex]['bc'],5.0+(abs(cos(radians(frameCount*0.1))*15.0)));
        lay.fill(aColors[alternateColorIndex]['rc'],aColors[alternateColorIndex]['gc'],aColors[alternateColorIndex]['bc'],5.0+(abs(cos(radians(frameCount*0.1))*15.0)));
        lay.strokeWeight(small_screen ? 0.2 : 0.4);
        lay.ellipse(px, py, 1, 1);
      }

      pointPool[pointIndex] = null;
      pointIndex++;
      pointPool._sinceCompact++;

      if (pointPool._sinceCompact >= pointPool._compactEvery) {
        pointPool.splice(0, pointIndex);
        pointIndex = 0;
        pointPool._sinceCompact = 0;
        break;
      }
    }
  }
  
  if (loadSpheres) {
    for (let i = 0; i < 1; i++) {
      if (sphereIndex >= spherePool.length) {
        if ( shouldShufflePoints ) {
          shuffle(pointPool,true);
          shouldShufflePoints = false;
        }
        break;
      }
      
      let sphere = spherePool[sphereIndex];
      sphere.display();
      sphereIndex++;
    }  
  }
        
  translate(width/2, height/2);
  rotate(radians(sin(radians(frameCount*1.0)*0.75)));
  scale(1.08+cos(radians(frameCount*0.3))*0.05,1.08+cos(radians(frameCount*0.3))*0.05);
  translate(-width/2,-height/2);
  image(pgbg,0,0,width,height);
  image(pg,0,0,width,height);
  translate(width/2, height/2);
  translate(cos(radians(frameCount*0.1))*20.0,sin(radians(frameCount*0.1))*20.0);
  translate(-width/2,-height/2);
  image(pg4,0,0,width,height);
  image(pg3,0,0,width,height);
  translate(width/2, height/2);
  rotate(radians(cos(radians(frameCount*0.5))*3.0));
  translate(-width/2,-height/2);
  image(pg2,0,0,width,height);
}

function generate() {
  for (let dx=180.0; dx<=360.0; dx+=sq_x) {
    for (let dy=0.0; dy<=360.0-sq_y; dy+=sq_y) {
      const displace = random() < 0.001;
      const sphere = random() < 0.0005;
      const willShift = displace && sq_x < 350.0;
      const x_off = willShift ? random(-width * 0.1, width * 0.1) : (sphere && random() < 0.5) ? randomGaussian(0, torus_width) : 0.0;
      const y_off = willShift ? random(-height * 0.1, height * 0.1) : (sphere && random() < 0.5) ? randomGaussian(0, torus_height) : 0.0;
      tilePool.push({ dx, dy, displace, x_off, y_off, sphere });
    }
  }  
  tilePool = noiseShuffle(tilePool, 0.03);
}

function noiseShuffle(pool, { scale = 0.05, z = 0, seed = 12345 } = {}) {
  return pool.map((o, i) => ({...o, __k: noise(o.dx * scale, o.dy * scale, z) + i * 1e-12 })).sort((a, b) => a.__k - b.__k).map(({ __k, ...o }) => o);
}

function get_noise(x,y,type) {
  if ( type == 1 ) {
    var p = noise(x*x_noise,y*y_noise)*200.0;
    p *= abs(tan(noiseLevel/radians(p*30.0)))*0.125;
    p = (sq ? round(p / 10.0) * 10.0 : p);
  } else if ( type == 2 ) {
    var p = noise(x*x_noise,y*y_noise)*200.0;
    p *= cos(radians(p*p*0.005));
    p = (sq ? round(p / 5.0) * 5.0 : p);
  } else if ( type == 3 ) {
    var p = noise(x*0.006,y*0.0001);
    p = map(p,0.0,1.0,-1.0,1.0);
    p *= 100.0;
    var g = tan(radians(p*0.3));
    p *= exp(-g*g);
  }
  p = (p == 0.0 ? random() : p)
  return p;
}

class Sphere {
  constructor(x, y, w, h, yawDeg = 0, pitchDeg = 0, rollDeg = 0) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.yaw = yawDeg;
    this.pitch = pitchDeg;
    this.roll = rollDeg;
  }

  _sphereXY(latDeg, lonDeg) {
    const phi = radians(latDeg - 270.0);
    const lam = radians(lonDeg);
    let x = cos(phi) * cos(lam);
    let y = sin(phi);
    let z = cos(phi) * sin(lam);
    const ry = radians(this.yaw);
    const rx = radians(this.pitch);
    const rz = radians(this.roll);

    {
      const c = cos(ry), s = sin(ry);
      const nx = c * x + s * z;
      const nz = -s * x + c * z;
      x = nx; z = nz;
    }
    {
      const c = cos(rx), s = sin(rx);
      const ny = c * y - s * z;
      const nz = s * y + c * z;
      y = ny; z = nz;
    }
    {
      const c = cos(rz), s = sin(rz);
      const nx = c * x - s * y;
      const ny = s * x + c * y;
      x = nx; y = ny;
    }

    const X = this.x + this.w * x;
    const Y = this.y + this.h * y;
    return [X, Y];
  }

  display(layer=pg3) {
    sq_x = round(max((min(200.0,width*0.25) / this.w), 5.0) / 3.0) * 3.0;
    sq_y = round(max((min(200.0,width*0.25) / this.h), 5.0) / 3.0) * 3.0;
    step = sq_y;
    
    for (let dx=180.0; dx<=360.0; dx+=sq_y) {
      for (let dy=0.0; dy<360.0; dy+=sq_x) {
        let [xx0, yy0] = this._sphereXY(dx, dy);
        var noise = get_noise(xx0, yy0, 2)*50 / get_noise(xx0, yy0, 1)*50;
        var max_points = width*0.08;
        for ( var n=0; n<=max_points; n++ ) {
          let px = xx0+cos(radians(dy))*this.w+random(-noise,noise)*random(0.01,0.04);
          let py = yy0+sin(radians(dy))*this.h+random(-noise,noise)*random(0.01,0.04);
          
          if ( px > 0 && px < width && py > 0 && py < height )
            pointPool.push({ px, py });
        }
                  
        layer.beginShape();

        if (noise < 15000) {
          layer.fill(rColor, gColor, bColor);
          if (noise > min_noise) {
            layer.drawingContext.shadowBlur = small_screen ? 65 : 50;
            layer.drawingContext.shadowColor = highlightColor;
            layer.fill(highlightColor);
          }
        } else {
          layer.drawingContext.shadowBlur = 0;
          layer.drawingContext.shadowColor = 0;
          layer.fill(0);
        }
        
        layer.stroke(0);
        layer.strokeWeight(0.4);
        
        for (let lon=dy; lon<dy+sq_x; lon+=step) {
          let [xx, yy] = this._sphereXY(dx, lon);
          const p = get_noise(xx, yy, 3) * 0.1;
          layer.vertex(xx + p, yy + p);
        }
        for (let lat=dx; lat<dx+sq_y; lat+=step) {
          let [xx, yy] = this._sphereXY(lat, dy + sq_x);
          const p = get_noise(xx, yy, 3) * 0.1;
          layer.vertex(xx + p, yy + p);
        }
        for (let lon=dy+sq_x; lon>dy; lon-=step) {
          let [xx, yy] = this._sphereXY(dx + sq_y, lon);
          const p = get_noise(xx, yy, 3) * 0.1;
          layer.vertex(xx + p, yy + p);
        }
        for (let lat=dx+sq_y; lat>dx; lat-=step) {
          let [xx, yy] = this._sphereXY(lat, dy);
          const p = get_noise(xx, yy, 3) * 0.1;
          layer.vertex(xx + p, yy + p);
        }
        
        layer.endShape(CLOSE);
        layer.drawingContext.shadowBlur = 0;
      }
    }
    
    sq_x = small_screen ? 4.0 : 2.0;
    sq_y = small_screen ? 1.0 : 0.5;
    step = sq_y;
  }
}

class TorusTile {
  constructor(x,y,w,h,r,rx,displace,sphere) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.start_r = r;
    this.start_x = rx;
    this.displace = displace;
    this.sphere = sphere;
  }
  
  displayTile(layer,stroke_color,fillColor,r,rr,step,loops,alternate) {
    layer.beginShape();
    layer.stroke(stroke_color);
    layer.strokeWeight(0.4);
    layer.fill(fillColor);

    if ( animate_bg && alternate && !this.displace ) {
      layer.fill(alternateColor);
    }

    if (loops > 1 ) {
      for ( var n=1.0; n<=loops; n++ ) { 
        for ( var rrr=rr; rrr<rr+sq_x; rrr+=step ) {
          var xx = this.x + sin(radians(r))*((this.w+((n-1)*10.0))) + ((sin(radians(rrr))*(this.w+((n-1)*10.0))*torus_size));
          var yy = this.y + cos(radians(r))*((this.h+((n-1)*10.0))) + ((cos(radians(rrr))*(this.h+((n-1)*10.0))*torus_size));
          var p = get_noise(xx,yy,3) * max(0,(1.0 - (n/10)));
          xx += p;
          yy += p;
          layer.vertex(xx,yy);
                    
          if ( xx < -layer.width*0.1 || xx > layer.width*1.1 || yy < -layer.height*0.1 || yy > layer.height*1.1 )
            break;
        }
        for ( var rrr=r; rrr<r+sq_y; rrr+=step ) {
          var xx = this.x + sin(radians(rrr))*((this.w+((n)*10.0))) + ((sin(radians(rr+sq_x))*(this.w+((n)*10.0))*torus_size));
          var yy = this.y + cos(radians(rrr))*((this.h+((n)*10.0))) + ((cos(radians(rr+sq_x))*(this.h+((n)*10.0))*torus_size));
          var p = get_noise(xx,yy,3) * max(0,(1.0 - (n/10)));
          xx += p;
          yy += p;
          layer.vertex(xx,yy);

          if ( xx < -layer.width*0.1 || xx > layer.width*1.1 || yy < -layer.height*0.1 || yy > layer.height*1.1 )
            break;
        }
        for ( var rrr=rr+sq_x; rrr>rr; rrr-=step ) {
          var xx = this.x + sin(radians(r+sq_y))*((this.w+((n-1)*10.0))) + ((sin(radians(rrr))*(this.w+((n-1)*10.0))*torus_size));
          var yy = this.y + cos(radians(r+sq_y))*((this.h+((n-1)*10.0))) + ((cos(radians(rrr))*(this.h+((n-1)*10.0))*torus_size));
          var p = get_noise(xx,yy,3) * max(0,(1.0 - (n/10)));
          xx += p;
          yy += p;
          layer.vertex(xx,yy);

          if ( xx < -layer.width*0.1 || xx > layer.width*1.1 || yy < -layer.height*0.1 || yy > layer.height*1.1 )
            break;
        }
        for ( var rrr=r+sq_y; rrr>r; rrr-=step ) {
          var xx = this.x + sin(radians(rrr))*((this.w+((n)*10.0))) + ((sin(radians(rr))*(this.w+((n)*10.0))*torus_size));
          var yy = this.y + cos(radians(rrr))*((this.h+((n)*10.0))) + ((cos(radians(rr))*(this.h+((n)*10.0))*torus_size));
          var p = get_noise(xx,yy,3) * max(0,(1.0 - (n/10)));
          xx += p;
          yy += p;
          layer.vertex(xx,yy);

          if ( xx < -layer.width*0.1 || xx > layer.width*1.1 || yy < -layer.height*0.1 || yy > layer.height*1.1 )
            break;
        }
      }
    } else {
      for ( var rrr=rr; rrr<rr+sq_x; rrr+=step ) {
        var xx = this.x + sin(radians(r))*this.w + ((sin(radians(rrr))*this.w*torus_size));
        var yy = this.y + cos(radians(r))*this.h + ((cos(radians(rrr))*this.h*torus_size));
        var p = get_noise(xx,yy,3);
        xx += p;
        yy += p;
        layer.vertex(xx,yy);
      }
      for ( var rrr=r; rrr<r+sq_y; rrr+=step ) {
        var xx = this.x + sin(radians(rrr))*this.w + ((sin(radians(rr+sq_x))*this.w*torus_size));
        var yy = this.y + cos(radians(rrr))*this.h + ((cos(radians(rr+sq_x))*this.h*torus_size));
        var p = get_noise(xx,yy,3);
        xx += p;
        yy += p;
        layer.vertex(xx,yy);
      }
      for ( var rrr=rr+sq_x; rrr>rr; rrr-=step ) {
        var xx = this.x + sin(radians(r+sq_y))*this.w + ((sin(radians(rrr))*this.w*torus_size));
        var yy = this.y + cos(radians(r+sq_y))*this.h + ((cos(radians(rrr))*this.h*torus_size));
        var p = get_noise(xx,yy,3);
        xx += p;
        yy += p;
        layer.vertex(xx,yy);
      }
      for ( var rrr=r+sq_y; rrr>r; rrr-=step ) {
        var xx = this.x + sin(radians(rrr))*this.w + ((sin(radians(rr))*this.w*torus_size));
        var yy = this.y + cos(radians(rrr))*this.h + ((cos(radians(rr))*this.h*torus_size));
        var p = get_noise(xx,yy,3);
        xx += p;
        yy += p;
        layer.vertex(xx,yy);
      }
    }
    
    layer.endShape(CLOSE);
  }
  
  display() {
    for ( var r=this.start_r; r<=this.start_r+step; r+=step) {
      for ( var rr=r+this.start_x; rr>=r+this.start_x-sq_x; rr-=sq_x) {
        var noise = get_noise(this.x + sin(radians(r))*this.w + ((sin(radians(rr))*this.w*torus_size)),this.y + cos(radians(r))*this.h + ((cos(radians(rr))*this.h*torus_size)),2)*50 / get_noise(this.x + sin(radians(r))*this.w + ((sin(radians(rr))*this.w*torus_size)),this.y + cos(radians(r))*this.h + ((cos(radians(rr))*this.h*torus_size)),1)*50;
        if ( abs(noise) < 15000 ) {
          if ( this.start_x > 190 && this.start_x < 350 ) {
            if ( reload_bg && this.sphere && (sphere_no_repeat >= 1.0 || this.displace)) {
              let sx = this.x + sin(radians(r))*this.w + ((sin(radians(rr))*this.w*torus_size));
              let sy = this.y + cos(radians(r))*this.h + ((cos(radians(rr))*this.h*torus_size));
              
              if ( sx > 0 && sx < width && sy > 0 && sy < height ) {
                sphere_no_repeat = 0.0;
                let max_w = width > height ? height : width;
                let sphere_d = small_screen ?  randomGaussian(max_w*0.06,max_w*0.02) : randomGaussian(max_w*0.03,max_w*0.01);
                const sphere = new Sphere(sx,sy,sphere_d,sphere_d,r,random(-45,45.0),random(360.0),random(360.0));
                spherePool.push(sphere);
              }
            } else if ( reload_bg && this.sphere && sphere_no_repeat < 1.0) {
              sphere_no_repeat += 0.1;
            }
          }         
          if ( this.start_x < 360.0 ) {
            if ( this.displace ) {
              this.displayTile(pg2,strokeColor,highlightColor,r,rr,0.1,1,true);
            } else {
              if ( abs(noise) > min_noise ) {
                saw_min_noise ++;
                if ( this.start_x > 185 && this.start_x < 350 && (reload_bg || force_reload_highglights ) ) {
                  if ( (random(1.0) < 0.3 && !force_reload_highglights) || (random(1.0) < 0.3 && force_reload_highglights)) {
                    pg.drawingContext.shadowBlur = 20;
                  } else {
                    pg.drawingContext.shadowBlur = 0;
                  }
                  pg.drawingContext.shadowColor = color(aColors[alternateColorIndex]['rc'],aColors[alternateColorIndex]['gc'],aColors[alternateColorIndex]['bc'],int(min(140.0,90.0*Math.pow(3360.0/width,0.50))));
                  this.displayTile(pg,strokeColor,highlightColor,r,rr,0.1,1,false);
                }
                if ( this.start_x > 180 ) {
                  pg.drawingContext.shadowBlur = 0;
                }
              } else {
                this.displayTile(pg,strokeColor,color(rColor,gColor,bColor),r,rr,0.1,1,true);
              }
            }
          } else if ( this.start_x == 360.0 && reload_bg ) {
            this.displayTile(pgbg,color(10,10,10,3),color(rColor,gColor,bColor,5),r,rr,0.1,100,true);
          }
        } else if ( this.start_x == 360.0 && reload_bg ) {
          this.displayTile(pgbg,color(10,10,10,3),color(rColor,gColor,bColor,5),r,rr,0.1,100,true);
        }
      }
    }
  }
}