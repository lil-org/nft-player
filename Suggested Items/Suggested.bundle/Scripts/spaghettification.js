function setup() {
     switch (createCanvas(dim, dim), colorMode(HSB, 360, 100, 100, 100), angleMode(DEGREES), ellipseMode(CENTER), rectMode(CENTER), mkP(arg.h, arg.s, arg.v, 1), arg.c) {
          case 0:
          default:
               mkP(mod(arg.h + 180 + 5, 360), arg.s + 5, arg.v - 5, 1), mkP(mod(arg.h + 180 - 5, 360), arg.s - 5, arg.v + 5, 1);
               break;
          case 1:
               mkP(mod(arg.h - 30, 360), arg.s, arg.v, 1), mkP(mod(arg.h + 30, 360), arg.s, arg.v, 1);
               break;
          case 2:
               mkP(mod(arg.h - 120, 360), arg.s, arg.v, 1), mkP(mod(arg.h + 120, 360), arg.s, arg.v, 1)
     }
     for (pts = [], rt = int(360 / arg.n), t = 0; t < arg.n; t++) T[t] = new Tube(t * rt + R.bt(-18, 18) + parseInt(mpp(rns[7], 0, 30))), pts.push([T[t].xT, T[t].yT]);
     E = new EventHorizon(pts), draw()
}

function draw() {
     for (noStroke(), E.tck(), noFill(), stroke(sCol), strokeWeight(.1 * width), rect(.5 * width, .5 * height, width, height, .1 * width), noStroke(), t = 0; t < T.length; t++) T[t].tck()
}

function mkP(t, s, h, r) {
     for (i = -cP; i < cP; i++) P.push([t + i * int(cP / 16), s - i * arg.d * int(cP / 8), h + i * arg.d * int(cP / 8) + h / 2, r])
}

function mpd(t, s, h, i, r) {
     return (t - s) / (h - s) * (r - i) + i
}

function mpp(t, s, h) {
     return mpd(t, 0, 255, s, h)
}

function mod(t, s) {
     return (t % s + s) % s
}
for (seed = parseInt(tokenData.hash.slice(0, 16), 16), hs = [], j = 0; j < 32; j++) hs.push(tokenData.hash.slice(2 + 2 * j, 4 + 2 * j));
rns = hs.map(t => parseInt(t, 16));
class Random {
     constructor(t) {
          this.seed = t
     }
     dec() {
          return this.seed ^= this.seed << 13, this.seed ^= this.seed >> 17, this.seed ^= this.seed << 5, (this.seed < 0 ? 1 + ~this.seed : this.seed) % 1e3 / 1e3
     }
     bt(t, s) {
          return t + (s - t) * this.dec()
     }
     ch(t) {
          return t[Math.floor(this.bt(0, .99 * t.length))]
     }
}
R = new Random(seed), arg = {
     h: parseInt(mpp(rns[1], 0, 360)),
     s: parseInt(mpp(rns[2], 80, 60)),
     v: parseInt(mpp(rns[2], 35, 45)),
     x: mpp(rns[3], -.125, .125),
     y: mpp(rns[4], -.125, .125),
     d: R.ch([-1, 1]),
     r: parseInt(mpp(rns[5], 30, 60)),
     i: mpp(rns[6], .1, .3),
     c: R.ch([0, 1, 2]),
     n: R.ch([3, 4, 5]),
     bSc: mpp(rns[8], .15, .3),
     tSc: mpp(rns[10], 4, 12),
     cyb: mpp(rns[16], 0, 100),
     blw: mpp(rns[17], 0, 100)
}, arg.cyb <= 6 ? (arg.s = 130, arg.v = 30) : arg.blw <= 4 && (arg.s = 0, arg.v = 50), P = [], T = [], E = null, cP = 30, cS = 256, dim = Math.min(window.innerWidth, window.innerHeight), sCol = [arg.h, arg.s - 20, arg.v - 20, 100];
class EventHorizon {
     constructor(t) {
          this.vrt = [];
          let s = 0,
               h = 0;
          for (let i = 0; i < t.length; i++) {
               let r = t[i][0] + width * -arg.x / 3,
                    e = t[i][1] + height * -arg.y / 3;
               this.vrt.push([r, e]), s += r, h += e
          }
          this.cX = Math.round(s / this.vrt.length), this.cY = Math.round(h / this.vrt.length), this.oX = width / 4 * R.bt(-.1, .1), this.oY = height / 4 * R.bt(-.1, .1);
          for (let t = 0; t < this.vrt.length; t++) this.vrt[t][0] -= this.cX, this.vrt[t][1] -= this.cY;
          this.phV = 0, this.phS = 0, this.osc = sin(Math.PI / this.fq * 2)
     }
     tck() {
          this.phV += arg.i, this.phV > this.osc && (this.phV -= this.osc), this.phS -= arg.i, this.phS < -this.osc && (this.phS += this.osc);
          let t = 24;
          for (let s = t; s > 0; s--) {
               fill(arg.h + mpd(s, t, 0, -60, 180), arg.s + mpd(s, t, 0, -40, 40), arg.v + mpd(s, t, 0, 30, -60), 100);
               let h = 1.65 * width * mpd(-s / t * (s / t) * (s / t) * (s / t) + 1, 0, 1, 1, arg.bSc),
                    i = mpd(sin(Math.PI / 1 * 2 * (this.phV + 4 * s - 1)), -1, 1, .9, 1.1);
               ellipse(this.cX + this.oX, this.cY + this.oY, h * i, h * i)
          }
          for (let s = t = 8; s >= 0; s--) {
               s == t ? fill(arg.h + 30, arg.s - 20, arg.v + 50, 100) : fill(mpd(s, 0, t, arg.h - 30, arg.h + 30), mpd(s, 0, t, arg.s + 40, arg.s - 40), mpd(s, 0, t, -20, arg.v + 20), 100);
               let h = mpd(sin(Math.PI / 1 * 2 * (this.phS + 4 * s - 1)), -1, 1, 1.1, .9);
               beginShape();
               for (let i = 0; i < this.vrt.length; i++) s == t ? vertex(this.cX + 1.025 * this.vrt[i][0] * h, this.cY + 1.025 * this.vrt[i][1] * h) : vertex(this.cX + this.vrt[i][0] * mpd(s, 0, t, .1, h), this.cY + this.vrt[i][1] * mpd(s, 0, t, .1, h));
               endShape()
          }
     }
}
class Tube {
     constructor(t) {
          this.wSc = arg.tSc + R.bt(-arg.tSc / 4, arg.tSc / 2), this.wFq = (mpp(rns[11], .6, 1) + R.bt(-.05, .05)) * arg.d, this.wSp = (mpp(rns[12], .4, .6) + R.bt(-.05, .05)) * arg.d, this.wPh = sin(Math.PI / this.wFq * 2) * R.bt(.2, .8) + R.bt(-.5, .5), this.wRt = mpd(arg.i, .05, .25, .4, 1);
          let s = Math.round(R.bt(0, 1)) * cP * 2 + 2 * cP,
               h = 1 === arg.d ? arg.r : -arg.r,
               i = R.bt(0, R.bt(-.1, .1));
          this.segments = new Array(cS);
          for (let r = 0; r < cS; r++) {
               let e = r / cS * (r / cS),
                    n = -e * e + 1,
                    a = Math.round(cP / 5),
                    c = mpd(r, 0, cS, 0, 2 * cP - a - 1),
                    g = Math.round(R.bt(c, c + a)),
                    d = mpd(n, 1, .99, -30, 100);
               this.segments[r] = new Segment(r, [P[g + s][0], P[g + s][1], P[g + s][2], d], width * mpd(n, 0, 1, 1.2, .01), mpd(r, 0, cS, 0, 1), mpd(e, 0, 1, -.05, 2), t, h, i)
          }
          let r = mpp(rns[9], .25, .35) + i;
          this.xT = width * r * sin(t) + (width / 2 + width * arg.x), this.yT = width * r * cos(t) + (height / 2 + height * arg.y)
     }
     tck() {
          this.wPh += this.wSp * this.wRt;
          let t = sin(Math.PI / this.wFq * 2);
          this.wPh > t && (this.wPh -= t);
          for (let t = 0; t < this.segments.length; t++) this.segments[t].tck(this.wPh, this.wSc, this.wFq);
          for (let t = 0; t < this.segments.length; t++) this.segments[t].dO();
          for (let t = 0; t < this.segments.length; t++) this.segments[t].dF()
     }
}
class Segment {
     constructor(t, s, h, i, r, e, n, a) {
          this.x = 0, this.y = 0, this.ix = t, this.cl = s, this.sz = h, this.sc = i, this.rd = r, this.rt = e, this.sp = n, this.xT = width * (r + a) * sin(e) + (width / 2 + width * arg.x), this.yT = width * (r + a) * cos(e) + (height / 2 + height * arg.y)
     }
     tck(t, s, h) {
          let i = s * sin(Math.PI / h * 2 * (this.ix + t));
          this.x = this.sc * (width * this.rd * sin(this.rt + this.sp + i) + .5 * width) + (1 - this.sc) * this.xT, this.y = this.sc * (width * this.rd * cos(this.rt + this.sp + i) + .5 * width) + (1 - this.sc) * this.yT
     }
     dO() {
          fill([sCol[0], sCol[1], sCol[2], this.cl[3]]), ellipse(this.x, this.y, this.sz + .25 * width * this.sc * this.sc, this.sz + .25 * width * this.sc * this.sc)
     }
     dF() {
          fill(this.cl), ellipse(this.x, this.y, this.sz, this.sz)
     }
}