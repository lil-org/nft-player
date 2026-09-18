tokenData = tokenData.hashes[0];

int[] hashPairs = new int[254];
for (int i = 0; i < 63; i++) {
     Sting hex = tokenData.substring(i + 2, i + 4);
     hashPairs[i] = unhex(hex);
}
for (int i = 0; i < 32; i++) {
     Sting hex = concat(tokenData.substring(i + 2, i + 3), tokenData.substring(i + 34, i + 35));
     hashPairs[i + 63] = unhex(hex);
}
for (int i = 0; i < 64; i++) {
     Sting hex = concat(tokenData.substring(i + 2, i + 3), tokenData.substring(65 - i, 66 - i));
     hashPairs[i + 95] = unhex(hex);
}
for (int i = 0; i < 63; i++) {
     Sting hex = concat(tokenData.substring(65 - i, 66 - i), tokenData.substring(64 - i, 65 - i));
     hashPairs[i + 159] = unhex(hex);
}
for (int i = 0; i < 32; i++) {
     Sting hex = concat(tokenData.substring(65 - i, 66 - i), tokenData.substring(33 - i, 34 - i));
     hashPairs[i + 222] = unhex(hex);
}
int margin;
int grid;
int unit;
int rmin;
int rmax;
int r;
int[] xreps = new int[10];
int[] yreps = new int[10];
int hue;
int chue;
int vmin;
int vmax;
int valuerange;
int rarity;
int c;
color c1;
color c2;
color c3;
int s;
int step;
int orientation;
int i;
int j;
int xa;
int ya;
int xb;
int yb;
int x1;
int y1;
int x2;
int y2;
void setup() {
     size(Math.floor(Math.min(window.innerWidth, window.innerHeight) / 72) * 72, Math.floor(Math.min(window.innerWidth, window.innerHeight) / 72) * 72);
     margin = 0;
     rectMode(CORNERS);
     colorMode(HSB, 359, 100, 100, 1);
     noStroke();
     grid = 36;
     unit = width / grid;
     rmin = 20;
     rmax = 40;
     xreps = {
          -7,
          -6,
          -5,
          -4,
          -3,
          3,
          4,
          5,
          6,
          7
     };
     yreps = {
          -7,
          -6,
          -5,
          -4,
          -3,
          3,
          4,
          5,
          6,
          7
     };
     vmin = 70;
     vmax = 90;
}void draw() {
     background(0, 0, 100);
     hue = round(map(hashPairs[0], 0, 255, 0, 359));
     chue = hue + 180;
     if (chue > 359) {
          chue = chue - 360;
     }
     ahue1 = hue + 15;
     if (ahue1 > 359) {
          ahue1 = ahue1 - 360;
     }
     ahue2 = hue + 30;
     if (ahue2 > 359) {
          ahue2 = ahue2 - 360;
     }
     valuerange = round(map(hashPairs[1], 0, 255, vmin, vmax));
     c = floor(map(hashPairs[2], 0, 255, 0, 2.9999999999));
     rarity = hashPairs[3];
     if (c == 0) {
          c1 = color(hue, 100, 100);
          c2 = color(hue, 100 - valuerange, 100);
          c3 = color(hue, 100, 100 - valuerange);
     }
     if (c == 1) {
          c1 = color(hue, 100 - valuerange, 100);
          c2 = color(hue, 100, 100 - valuerange);
          c3 = color(hue, 100, 100);
     }
     if (c == 2) {
          c1 = color(hue, 100, 100 - valuerange);
          c2 = color(hue, 100, 100);
          c3 = color(hue, 100 - valuerange, 100);
     }
     if (rarity > 226) {
          valuerange = vmax;
          c1 = color(hue, 100 - valuerange, 100);
          c2 = color(hue, 100 - valuerange / 2, 100);
          c3 = color(hue, 100, 100);
     }
     if (rarity > 239) {
          valuerange = vmax;
          c1 = color(hue, 100, 100 - valuerange);
          c2 = color(hue, 100, 100 - valuerange / 2);
          c3 = color(hue, 100, 100);
     }
     if (rarity > 252) {
          c1 = color(hue, 100, 100 - valuerange);
          c2 = color(hue, 100, 100);
          c3 = color(chue, 100, 100);
     }
     background(c1);
     r = round(map(hashPairs[4], 0, 255, rmin, rmax));
     for (i = 0; i < r; i++) {
          s = floor(map(hashPairs[i + 5], 0, 255, 0, 1.9999999999));
          if (s == 0) {
               fill(c2);
               step = 0;
          }
          if (s == 1) {
               fill(c3);
               step = 1;
          }
          xa = 2 * round(map(hashPairs[i + 45], 0, 255, 0, (width / (2 * unit)) - 1)) + step + 1;
          ya = 2 * round(map(hashPairs[i + 85], 0, 255, 0, (height / (2 * unit)) - 1)) + step + 1;
          if (i == 0) {
               fill(c2);
               step = 0;
               xa = 1;
               ya = 2 * round(map(hashPairs[i + 85], 0, 255, 0, (height / (2 * unit)) - 1)) + step + 1;
          }
          if (i == 1) {
               fill(c2);
               step = 0;
               xa = 2 * round(map(hashPairs[i + 45], 0, 255, 0, (width / (2 * unit)) - 1)) + step + 1;
               ya = 1;
          }
          if (i == 2) {
               fill(c3);
               step = 1;
               xa = width / unit;
               ya = 2 * round(map(hashPairs[i + 85], 0, 255, 0, (height / (2 * unit)) - 1)) + step + 1;
          }
          if (i == 3) {
               fill(c3);
               step = 1;
               xa = 2 * round(map(hashPairs[i + 45], 0, 255, 0, (width / (2 * unit)) - 1)) + step + 1;
               ya = height / unit;
          }
          xb = xa + 2 * xreps[round(map(hashPairs[i + 125], 0, 255, 0, 9))];
          if (xb < 1 || xb > width / unit - 1) {
               xb = xa - 2 * xreps[round(map(hashPairs[i + 125], 0, 255, 0, 9))];
          }
          yb = ya + 2 * yreps[round(map(hashPairs[i + 165], 0, 255, 0, 9))];
          if (yb < 1 || yb > height / unit - 1) {
               yb = ya - 2 * xreps[round(map(hashPairs[i + 165], 0, 255, 0, 9))];
          }
          x1 = xa;
          x2 = xb;
          y1 = ya;
          y2 = yb;
          if (xa > xb) {
               x1 = xb;
               x2 = xa;
          }
          if (ya > yb) {
               y1 = yb;
               y2 = ya;
          }
          if (x2 > (width / unit) - 1) {
               x2 = (width / unit) - 1;
          }
          if (y2 > (height / unit) - 1) {
               y2 = (height / unit) - 1;
          }
          orientation = floor(map(hashPairs[i + 205], 0, 255, 0, 1.9999999999));
          if (orientation == 0) {
               for (j = 0; x1 + 2 * j < x2; j++) {
                    rect(((x1 + 2 * j) * unit) + margin, (y1 * unit) + margin, ((x1 + ((2 * j) + 1)) * unit) + margin, (y2 * unit) + margin);
               }
          }
          if (orientation > 0) {
               for (j = 0; y1 + 2 * j < y2; j++) {
                    rect((x1 * unit) + margin, ((y1 + 2 * j) * unit) + margin, (x2 * unit) + margin, ((y1 + ((2 * j) + 1)) * unit) + margin);
               }
          }
     }
     noLoop();
}