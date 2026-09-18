let hash = tokenData.hash;
let id = tokenData.tokenId;
let hashPairs = [];
for (let i = 0; i < 32; i++) {
    let hex = hash.slice((2 * i) + 2, (2 * i) + 4);
    hashPairs[i] = parseInt(hex, 16);
}
let canv, img, margin, factor, orientation, grid, unit;
let hw, vw, hx, vx, order, loc;
let ch1, cs1, cb1, ch2, cs2, cb2, wh, ws, wb, c1, c2, w, g;
let t1, t2, t3, t4;
let night = false;
let x1 = [1, 6, 11, 16];
let x2 = [1, 8, 9, 16];
let x3 = [1, 2, 15, 16];
let x4 = [1, 2, 8, 9, 15, 16]
let hext = [x1, x2];
let vext = [x1, x2, x3, x4];
let hwin = [];
let vwin = [];
let w0 = [16];
let w1 = [3, 5, 5, 3];
let w2 = [2, 5, 5, 4];
let w3 = [2, 2, 3, 2, 3, 2, 2];
let w4 = [2, 8, 6];
let w5 = [4, 8, 4];
let w6 = [2, 4, 4, 4, 2];
let w7 = [3, 2, 6, 2, 3];
let w8 = [8, 8];
let w9 = [5, 3, 3, 5];
let w10 = [6, 4, 6];
let w11 = [3, 7, 6];
let w12 = [3, 3, 4, 3, 3];

function setup() {
    colorMode(HSB);
    hx = hext[floor(map(hashPairs[1], 0, 255, 0, hext.length - 0.0000000001))];
    vx = vext[floor(map(hashPairs[2], 0, 255, 0, vext.length - 0.0000000001))];
    if (hx == x1) {
        hwin = [w0, w1, w2, w3];
    }
    if (hx == x2) {
        hwin = [w0, w4, w5, w6, w7];
    }
    if (hx == x4) {
        hwin = [w0, w11, w12];
    }
    if (vx == x1) {
        vwin = [w0, w1, w3];
    }
    if (vx == x2) {
        vwin = [w0, w5, w6, w7];
    }
    if (vx == x3) {
        vwin = [w1, w8, w9, w10];
    }
    if (vx == x4) {
        vwin = [w0, w12];
    }
    hw = hwin[floor(map(hashPairs[3], 0, 255, 0, hwin.length - 0.0000000001))];
    vw = vwin[floor(map(hashPairs[4], 0, 255, 0, vwin.length - 0.0000000001))];
    order = hashPairs[5];
    if (hashPairs[6] < 15) {
        night = true;
    }
    orientation = Math.floor(map(hashPairs[7], 0, 255, 1, 3.999999999));
    factor = Math.floor(map(hashPairs[8], 0, 255, 1, 3.999999999));
    if (id % 1000000 < 12) {
        orientation = 3;
    }
    if (id % 1000000 < 7) {
        orientation = 1;
    }
    if (id % 1000000 < 3) {
        orientation = 2;
    }
    if (orientation == 1) {
        canv = Math.min(window.innerWidth, window.innerHeight);
        createCanvas(canv, canv);
        img = canv * 7 / 9;
        margin = canv * 1 / 9;
    }
    if (orientation == 2) {
        canv = Math.min(window.innerWidth / 16, window.innerHeight / 9);
        createCanvas(16 * canv, 9 * canv);
        img = 7 * canv;
        margin = canv;
    }
    if (orientation == 3) {
        canv = Math.min(window.innerWidth / 9, window.innerHeight / 16);
        createCanvas(9 * canv, 16 * canv);
        img = 7 * canv;
        margin = canv;
    }
    grid = 16 * factor;
    unit = img / grid;
}

function draw() {
    background(100);
    strokeWeight(unit / 4);
    ch1 = map(hashPairs[9], 0, 255, 15, 25);
    cs1 = map(hashPairs[10], 0, 255, 30, 60);
    cb1 = map(hashPairs[11], 0, 255, 60, 70);
    c1 = color(ch1, cs1, cb1);
    ch2 = map(hashPairs[12], 0, 255, 25, 35);
    cs2 = map(hashPairs[13], 0, 255, 0, 25);
    cb2 = map(hashPairs[14], 0, 255, 75, 90);
    c2 = color(ch2, cs2, cb2);
    if (hashPairs[15] < 25) {
        c1 = c2 = color(ch2, 8, cb2);
    }
    if (hashPairs[16] > 177) {
        c2 = c1;
    }
    wh = (hue(c1) + hue(c2)) / 2 + 180;
    ws = 30;
    wb = map(hashPairs[17], 0, 255, 85, 95);
    w = color(wh, ws, wb);
    g = color(0);
    if (hashPairs[18] < 192) {
        g = color(wh, 15, wb - 24);
    }
    if (hashPairs[18] < 128) {
        g = color(wh, 45, wb - 11);
    }
    if (hashPairs[18] < 64) {
        g = color(wh, 15, wb + 5);
    }

    if (hashPairs[19] < 15) {
        c1 = c2 = color(100);
    }
    if (night) {
        c1 = color(hue(c1) + 225, 20, lightness(c1) / 1.6);
        c2 = color(hue(c2) + 225, 20, lightness(c2) / 1.6);
        w = color((hue(c1) + hue(c2)) / 2 - 200, 10, wb);
        g = color(0);
    }
    fill(w);
    noStroke();
    rect(margin, margin, img, img);
    noFill();
    stroke(g);
    loc = 0;
    for (let f = 0; f < factor; f++) {
        for (let i = 0; i < hw.length; i++) {
            rect(margin, loc + margin, img, unit * hw[i]);
            loc = loc + unit * hw[i];
        }
    }
    loc = 0;
    for (let f = 0; f < factor; f++) {
        for (let i = 0; i < vw.length; i++) {
            rect(loc + margin, margin, unit * vw[i], img);
            loc = loc + unit * vw[i];
        }
    }
    stroke(0);
    if (order < 128) {
        fill(c2);
        loc = 0;
        for (let f = 0; f < factor; f++) {
            for (let i = 0; i < hx.length; i++) {
                rect(margin, unit * (hx[i] - 1) + margin + (f * img / factor), img, unit);
            }
        }
        fill(c1);
        for (let f = 0; f < factor; f++) {
            for (let i = 0; i < vx.length; i++) {
                rect(unit * (vx[i] - 1) + margin + (f * img / factor), margin, unit, img);
            }
        }
    } else {
        fill(c2);
        for (let f = 0; f < factor; f++) {
            for (let i = 0; i < vx.length; i++) {
                rect(unit * (vx[i] - 1) + margin + (f * img / factor), margin, unit, img);
            }
        }
        fill(c1);
        for (let f = 0; f < factor; f++) {
            for (let i = 0; i < hx.length; i++) {
                rect(margin, unit * (hx[i] - 1) + margin + (f * img / factor), img, unit);
            }
        }
    }
    if (orientation == 2) {
        fill(w);
        noStroke();
        rect(margin + img, margin, img, img);
        noFill();
        stroke(g);
        loc = 0;
        for (let f = 0; f < factor; f++) {
            for (let i = 0; i < hw.length; i++) {
                rect(margin + img, loc + margin, img, unit * hw[i]);
                loc = loc + unit * hw[i];
            }
        }
        loc = 0;
        for (let f = 0; f < factor; f++) {
            for (let i = 0; i < vw.length; i++) {
                rect(loc + margin + img, margin, unit * vw[i], img);
                loc = loc + unit * vw[i];
            }
        }
        stroke(0);
        if (order < 128) {
            fill(c2);
            loc = 0;
            for (let f = 0; f < factor; f++) {
                for (let i = 0; i < hx.length; i++) {
                    rect(margin + img, unit * (hx[i] - 1) + margin + (f * img / factor), img, unit);
                }
            }
            fill(c1);
            for (let f = 0; f < factor; f++) {
                for (let i = 0; i < vx.length; i++) {
                    rect(unit * (vx[i] - 1) + margin + (f * img / factor) + img, margin, unit, img);
                }
            }
        } else {
            fill(c2);
            for (let f = 0; f < factor; f++) {
                for (let i = 0; i < vx.length; i++) {
                    rect(unit * (vx[i] - 1) + margin + (f * img / factor) + img, margin, unit, img);
                }
            }
            fill(c1);
            for (let f = 0; f < factor; f++) {
                for (let i = 0; i < hx.length; i++) {
                    rect(margin, unit * (hx[i] - 1) + margin + (f * img / factor), 2 * img, unit);
                }
            }
        }
    }
    if (orientation == 3) {
        fill(w);
        noStroke();
        rect(margin, margin + img, img, img);
        noFill();
        stroke(g);
        loc = 0;
        for (let f = 0; f < factor; f++) {
            for (let i = 0; i < hw.length; i++) {
                rect(margin, loc + margin + img, img, unit * hw[i]);
                loc = loc + unit * hw[i];
            }
        }
        loc = 0;
        for (let f = 0; f < factor; f++) {
            for (let i = 0; i < vw.length; i++) {
                rect(loc + margin, margin + img, unit * vw[i], img);
                loc = loc + unit * vw[i];
            }
        }
        stroke(0);
        if (order < 128) {
            fill(c2);
            loc = 0;
            for (let f = 0; f < factor; f++) {
                for (let i = 0; i < hx.length; i++) {
                    rect(margin, unit * (hx[i] - 1) + margin + (f * img / factor) + img, img, unit);
                }
            }
            fill(c1);
            for (let f = 0; f < factor; f++) {
                for (let i = 0; i < vx.length; i++) {
                    rect(unit * (vx[i] - 1) + margin + (f * img / factor), margin, unit, 2 * img);
                }
            }
        } else {
            fill(c2);
            for (let f = 0; f < factor; f++) {
                for (let i = 0; i < vx.length; i++) {
                    rect(unit * (vx[i] - 1) + margin + (f * img / factor), margin + img, unit, img);
                }
            }
            fill(c1);
            for (let f = 0; f < factor; f++) {
                for (let i = 0; i < hx.length; i++) {
                    rect(margin, unit * (hx[i] - 1) + margin + (f * img / factor) + img, img, unit);
                }
            }
        }
    }
    noLoop();
}

function mouseClicked() {
    if (id % 1000000 < 12) {
        if (!night) {
            night = true;
        } else {
            night = false;
        }
        redraw();
    }
}