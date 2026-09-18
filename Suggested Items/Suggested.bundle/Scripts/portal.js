tokenData = tokenData.hash;
let hashPairs = [];
for (let i = 0; i < 32; i++) {
     let hex = tokenData.slice((2 * i) + 2, (2 * i) + 4);
     hashPairs[i] = parseInt(hex, 16);
}
let w, h, r1, r2, steps, s, t;
let light, wall1, wall2, gh1, gs1, gb1, glow1, gh2, gs2, gb2, glow2, grange, glow;
let ph1, ps1, pb1, portal1, ph2, ps2, pb2, portal2, prange, portal;

function setup() {
     rectMode(CENTER);
     colorMode(HSB);
     noFill();
     noStroke();
     r1 = map(hashPairs[3], 0, 255, 4, 6);
     r2 = (11 + r1) / 2;
     light = color(100);
     wall1 = color(98);
     wall2 = color(96);
     grange = floor(map(hashPairs[4], 0, 255, 30, 180.9999999999));
     gh1 = floor(map(hashPairs[5], 0, 255, 0, 359.9999999999));
     gh2 = (gh1 + grange) % 360;
     if (hashPairs[6] > 127) {
          gh2 = floor(map(hashPairs[5], 0, 255, 0, 359.9999999999));
          gh1 = (gh2 + grange) % 360;
     }
     gs1 = gs2 = 25;
     gb1 = gb2 = 100;
     glow1 = color(gh1, gs1, gb1);
     glow2 = color(gh2, gs2, gb2);
     prange = floor(map(hashPairs[7], 0, 255, 15, 30.9999999999));
     ph1 = floor(map(hashPairs[8], 0, 255, 150, 330.9999999999)) % 360;
     ph2 = (ph1 + prange) % 360;
     if (hashPairs[9] > 127) {
          ph2 = floor(map(hashPairs[8], 0, 255, 150, 330.9999999999)) % 360;
          ph1 = (ph2 + prange) % 360;
     }
     ps1 = floor(map(hashPairs[10], 0, 255, 30, 50.9999999999));
     ps2 = 100;
     pb1 = 100;
     pb2 = floor(map(hashPairs[11], 0, 255, 40, 70.9999999999));
     if (hashPairs[12] > 127) {
          wall1 = color(96);
          wall2 = color(98);
          ps1 = 100;
          ps2 = floor(map(hashPairs[10], 0, 255, 30, 50.9999999999));
          pb1 = floor(map(hashPairs[11], 0, 255, 40, 70.9999999999));
          pb2 = 100;
     }
     portal1 = color(ph1, ps1, pb1);
     portal2 = color(ph2, ps2, pb2);
     t = 30;
     s = 20;
}

function draw() {
     w = window.innerWidth;
     h = window.innerHeight;
     smalldim = Math.floor(Math.min(w, h));
     createCanvas(w, h);
     background(lerpColor(wall1, wall2, millis() / (1000 * t) % 1));
     if (floor(millis() / (1000 * t)) % 2 > 0) {
          background(lerpColor(wall1, wall2, 1 - (millis() / (1000 * t) % 1)));
     }
     steps = s * floor(r2 - r1);
     glow = lerpColor(glow1, glow2, millis() / (1000 * t) % 1);
     if (floor(millis() / (1000 * t)) % 2 > 0) {
          glow = lerpColor(glow1, glow2, 1 - (millis() / (1000 * t) % 1));
     }
     colorMode(RGB);
     for (let i = 0; i < steps; i++) {
          fill(lerpColor(color(red(light), green(light), blue(light)), color(red(glow), green(glow), blue(glow)), lerp(0.1, 1, i / steps)));
          rect(w / 2, h / 2, lerp(r2, r1, i / steps) * w / 10, lerp(r2, r1, i / steps) * h / 10, smalldim / 120);
     }
     portal = lerpColor(color(red(portal1), green(portal1), blue(portal1)), color(red(portal2), green(portal2), blue(portal2)), millis() / (1000 * t) % 1);
     if (floor(millis() / (1000 * t)) % 2 > 0) {
          portal = lerpColor(color(red(portal1), green(portal1), blue(portal1)), color(red(portal2), green(portal2), blue(portal2)), 1 - (millis() / (1000 * t) % 1));
     }
     fill(portal);
     rect(w / 2, h / 2, r1 * w / 10, r1 * h / 10);
     colorMode(HSB);
     noFill();
     stroke(88);
     strokeWeight(smalldim / 600);
     rect(w / 2, h / 2, r2 * w / 10, r2 * h / 10);
     noStroke();
}