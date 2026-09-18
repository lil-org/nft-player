let tokenId = tokenData.tokenId;
tokenData = tokenData.hash
let R, w, h, grid, u, margin;
let heights, rows, rh, n, y, divider;
let p1, p2, progression, peek;
let c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, colors, alpha;
let br, bx, by, bw, brh, bh, bshapes;

function setup() {
    colorMode(HSB);
    R = new Random();
    w = window.innerWidth;
    h = window.innerHeight;
    if (w / h > 9 / 17) {
        w = 9 / 17 * h;
    } else {
        h = 17 / 9 * w;
    }
    createCanvas(w, h);
    grid = 64;
    u = w / 36;
    margin = 2 * u;
    heights = [1, 2, 4, 8, 16];
    rows = [1, 2, 4, 8];
    n = 15;
    y = 0;
    bshapes = [];
    c1 = color(359, 100, 100);
    c2 = color(18, 100, 100);
    c3 = color(27, 100, 100);
    c4 = color(34, 100, 98);
    c5 = color(41, 99, 97);
    c6 = color(49, 99, 96);
    c7 = color(57, 99, 94);
    c8 = color(65, 99, 87);
    c9 = color(87, 87, 87);
    c10 = color(113, 77, 86);
    c11 = color(154, 100, 83);
    c12 = color(178, 100, 79);
    c13 = color(194, 100, 95);
    c14 = color(199, 95, 96);
    c15 = color(207, 91, 96);
    c16 = color(215, 87, 96);
    c17 = color(223, 82, 97);
    c18 = color(231, 77, 97);
    c19 = color(245, 80, 98);
    colors = [c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19];
    p1 = R.random_int(0, colors.length - 1);
    p2 = R.random_int(0, colors.length - 1);
    while (Math.abs(p2 - p1) < 3 || Math.abs(p2 - p1) > 6) {
        p2 = R.random_int(0, colors.length - 1);
    }
    progression = [];
    alpha = [0.5, 0.25];
    while (n < grid) {
        rh = heights[R.random_int(0, heights.length - 1)];
        while (n + rh > grid) {
            rh = heights[R.random_int(0, heights.length - 1)];
        }
        rows.push(rh);
        n = n + rh;
    }
    rows = scramble(rows);
    if (rows[0] !== 1 && rows[0] !== 2) {
        for (let i = 1; i < rows.length; i++) {
            if (rows[i] === 1 || rows[i] === 2) {
                let temp = rows[i];
                rows.splice(i, 1);
                rows.unshift(temp);
                break;
            }
        }
    }
    for (let i = 0; i < rows.length; i++) {
        progression.push(Math.round(lerp(p1, p2, i / (rows.length - 1))));
    }
    peek = R.random_int(1, rows.length - 2);
    while (rows[peek] > 15) {
        peek = R.random_int(1, rows.length - 2);
    }
    for (let i = 0; i < rows.length; i++) {
        br = i;
        bx = R.random_int(1, 16 / rows[br] - 2) * rows[br];
        by = 0;
        for (let i = 0; i < br; i++) {
            by = rows[i] + by;
        }
        bw = rows[br];
        brh = R.random_int(3, Math.min(Math.ceil(rows.length), rows.length - br));
        bh = 0;
        for (let i = br; i < br + brh; i++) {
            bh = rows[i] + bh;
        }
        if (rows[i] < 4) {
            bshapes.push({
                br: br,
                bx: bx,
                by: by,
                bw: bw,
                bh: bh
            });
        }
    }
    if (bshapes[bshapes.length - 1].bh == null) {
        bshapes[bshapes.length - 1].bh = 64 - bshapes[bshapes.length - 1].by;
    } else {
        if (bshapes[bshapes.length - 2].bh == null) {
            bshapes[bshapes.length - 2].bh = 64 - bshapes[bshapes.length - 2].by;
        } else {
            bshapes[bshapes.length - 3].bh = 64 - bshapes[bshapes.length - 3].by;
        }
    }
    for (let i = 0; i < 17 - bshapes.length; i++) {
        br = R.random_int(0, rows.length - 3);
        while (rows[br] > 2) {
            br = R.random_int(0, rows.length - 3);
        }
        bx = R.random_int(1, 16 / rows[br] - 2) * rows[br];
        by = 0;
        for (let i = 0; i < br; i++) {
            by = rows[i] + by;
        }
        bw = rows[br];
        brh = R.random_int(3, Math.min(Math.ceil(rows.length), rows.length - br));
        bh = 0;
        for (let i = br; i < br + brh; i++) {
            bh = rows[i] + bh;
        }
        bshapes.push({
            br: br,
            bx: bx,
            by: by,
            bw: bw,
            bh: bh
        });
    }
    bshapes.sort((a, b) => a.bw - b.bw);
}

function draw() {
    background(0, 0, 100);
    stroke(0, 0, 25);
    strokeWeight(u / 3.75);
    for (let i = 0; i < rows.length; i++) {
        fill(hue(colors[progression[i]]), saturation(colors[progression[i]]), brightness(colors[progression[i]]), alpha[R.random_int(0, alpha.length - 1)]);
        if (i == peek) {
            fill(hue(colors[progression[i]]), saturation(colors[progression[i]]), brightness(colors[progression[i]]), 0);
        }
        divider = rows[i];
        for (let j = 0; j < 1 * grid / (2 * divider); j++) {
            rect((j * u * divider) + margin, y * u + margin, u * divider, rows[i] * u);
        }
        y = y + rows[i];
    }
    for (let i = 0; i < bshapes.length; i++) {
        fill(colors[progression[bshapes[i].br]]);
        rect(bshapes[i].bx * u + margin, bshapes[i].by * u + margin, bshapes[i].bw * u, bshapes[i].bh * u);
        rect(w - margin - (bshapes[i].bx * u) - (bshapes[i].bw * u), bshapes[i].by * u + margin, bshapes[i].bw * u, bshapes[i].bh * u);
    }
    for (let i = 1; i < 9; i++) {
        line(margin, margin + (i * 8 * u), w - margin, margin + (i * 8 * u));
    }
    noLoop();
}

function scramble(arr) {
    let newarr = [];
    let length = arr.length;
    for (let i = 0; i < length; i++) {
        let choice = R.random_int(0, arr.length - 1);
        newarr.push(arr[choice]);
        arr.splice(choice, 1);
    }
    return (newarr);
}

function keyTyped() {
    if (key === 's') {
        w = 9 * 300;
        h = 17 * 300;
        u = w / 36;
        margin = 2 * u;
        y = 0;
        resizeCanvas(w, h, true);
        redraw();
        saveCanvas(tokenId, 'png');
        setup();
        redraw();
    }
}

class Random {
    constructor() {
        this.useA = false;
        let sfc32 = function(uint128Hex) {
            let a = parseInt(uint128Hex.substr(0, 8), 16);
            let b = parseInt(uint128Hex.substr(8, 8), 16);
            let c = parseInt(uint128Hex.substr(16, 8), 16);
            let d = parseInt(uint128Hex.substr(24, 8), 16);
            return function() {
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
        this.prngA = new sfc32(tokenData.substr(2, 32));
        this.prngB = new sfc32(tokenData.substr(34, 32));
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