tokenData = tokenData.hash;
let hashPairs = [];
for (let i = 0; i < 32; i++) {
     let hex = tokenData.slice((2 * i) + 2, (2 * i) + 4);
     hashPairs[i] = parseInt(hex, 16);
}
let seed = parseInt(tokenData.slice(30, 46), 16);
let ra, ga, ba, sa, rb, gb, bb, sb, bg, bgv;
let r, unit, orientation, wp, short, long, w, h, angle, lock, nudge;
let order = [];
let single, bw, transparency, outlines, anglelock, nonudge, darkmode, rev, linear = false;
let g = 0;

function setup() {
     smalldim = Math.floor(Math.min(window.innerWidth, window.innerHeight));
     createCanvas(smalldim, smalldim);
     rectMode(CENTER);
     angleMode(DEGREES);
     colorMode(RGB);
     background(255);
     noFill();
     noStroke();
}

function draw() {
     ra = hashPairs[0];
     ga = hashPairs[1];
     ba = hashPairs[2];
     sa = saturate(color(ra, ga, ba));
     ra = red(sa);
     ga = green(sa);
     ba = blue(sa);
     rb = hashPairs[3];
     gb = hashPairs[4];
     bb = hashPairs[5];
     sb = saturate(color(rb, gb, bb));
     rb = red(sb);
     gb = green(sb);
     bb = blue(sb);
     for (let i = 0; i < 8; i++) {
          if (abs(hue(color(ra, ga, ba)) - hue(color(rb, gb, bb))) < 60 || abs(hue(color(ra, ga, ba)) - hue(color(rb, gb, bb))) > 300) {
               rb = hashPairs[6 + (i * 3)];
               gb = hashPairs[7 + (i * 3)];
               bb = hashPairs[8 + (i * 3)];
               sb = saturate(color(rb, gb, bb));
               rb = red(sb);
               gb = green(sb);
               bb = blue(sb);
          }
     }
     r = floor(map(hashPairs[31], 0, 255, 6, 12.9999999999));
     if (hashPairs[0] == 2 || hashPairs[0] == 20 || hashPairs[0] == 200) {
          r = 20;
     }
	wp = (((floor(map(hashPairs[1], 0, 255, 0, 5.9999999999))) * .25) + .25);
     unit = smalldim / (r + 2);
     short = unit * wp;
     long = smalldim - (2 * unit);
     orientation = floor(map(hashPairs[30], 0, 255, 0, 1.9999999999));
     if (orientation == 0) {
          w = short;
          h = long;
     }
     if (orientation == 1) {
          w = long;
          h = short;
     }
     if (hashPairs[29] > 224) {
          anglelock = true;
          lock = floor(map(rnd(), 0, 1, -5, 6));
     }
     if (hashPairs[28] > 192) {
          nonudge = true;
     }
     if (hashPairs[27] < 112) {
          darkmode = true;
     }
     if (hashPairs[26] < 128 && (wp > .75 && !anglelock) && !darkmode) {
          transparency = true;
     }
     if (hashPairs[26] > 224) {
          outlines = true;
     }
     if (hashPairs[25] < 36 && (wp < 1.25 || transparency || outlines)) {
          single = true;
     }
     if (hashPairs[25] > 232 && (wp < 1.25 || transparency || outlines)) {
          bw = true;
     }
     for (let i = 1; i < r + 1; i++) {
          order.push(i);
     }
     if (hashPairs[24] > 224) {
          rev = true;
          order = reverse(order);
     } else if (hashPairs[24] < 64 || wp > .75 && !transparency && !outlines && !single && !bw) {
          linear = true;
     } else {
          order = scramble(order);
     }
     if (darkmode) {
          bg = color(24);
          bgv = 24;
     } else {
          bg = color(232);
          bgv = 232;
     }
     background(bg);
     if (single) {
          rb = ra;
          gb = ga;
          bb = ba;
     }
     if (bw) {
          ra = ga = ba = rb = gb = bb = 256 - bgv;
     }
     for (let i = 0; i < r; i++) {
          fill((ra * (r - i) / r) + (rb * i / r), (ga * (r - i) / r) + (gb * i / r), (ba * (r - i) / r) + (bb * i / r));
          stroke((ra * (r - i) / r) + (rb * i / r), (ga * (r - i) / r) + (gb * i / r), (ba * (r - i) / r) + (bb * i / r));
          strokeWeight(unit / 36);
          if (single || bw) {
               stroke(bg);
               strokeWeight(unit / 20);
          }
          if (transparency && !darkmode) {
               fill((ra * (r - i) / r) + (rb * i / r), (ga * (r - i) / r) + (gb * i / r), (ba * (r - i) / r) + (bb * i / r), 64);
               noStroke();
          }
          if (outlines) {
               noFill();
               stroke((ra * (r - i) / r) + (rb * i / r), (ga * (r - i) / r) + (gb * i / r), (ba * (r - i) / r) + (bb * i / r));
               strokeWeight(unit / 18);
          }
          angle = floor(map(rnd(), 0, 1, -5, 6));
          if (anglelock && (wp < 1.25 || transparency)) {
               angle = lock;
          }
          nudge = floor(map(rnd(), 0, 1, -unit / 4, (unit / 4) + 1));
          if (nonudge) {
               nudge = 0;
          }
          push();
          if (orientation == 0) {
               translate(unit * (order[i] + 0.5), (smalldim / 2) + nudge);
          }
          if (orientation == 1) {
               translate((smalldim / 2) + nudge, unit * (order[i] + 0.5));
          }
          rotate(angle);
          if (floor(map(rnd(), 0, 1, 0, 255)) > 0 || order[i] == 1 || order[i] == r) {
               rect(0, 0, w, h);
          } else {
               g++;
          }
          pop();
     }
     noLoop();
}

function saturate(c) {
     let hc = hue(c);
     colorMode(HSB);
     let satc = color(hc, 85, 85);
     colorMode(RGB);
     let rc = red(satc);
     let gc = green(satc);
     let bc = blue(satc);
     return color(rc, gc, bc);
}

function scramble(arr) {
     let newarr = [];
     let length = arr.length;
     for (let i = 0; i < length; i++) {
          let choice = floor(map(rnd(), 0, 1, 0, arr.length));
          newarr.push(arr[choice]);
          arr.splice(choice, 1);
     }
     return (newarr);
}

function rnd() {
     seed ^= seed << 13;
     seed ^= seed >> 17;
     seed ^= seed << 5;
     return (((seed < 0) ? ~seed + 1 : seed) % 1000) / 1000;
}