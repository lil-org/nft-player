let w, h, numc, c1, c2, c3, c4, c5, possibles, mw, mh, m, margeW, margeH, quantiW, quantiH, pMin, pMax, q, len, seed, r;
let cMontseny = ["#ABD16A", "#61BC47", "#245E2C", "#FEF2F2", "#F03E3C"],
     cSalines = ["#70CC96", "#98D9A3", "#0D0C0A", "#B25D2B", "#E5BF00"],
     cIbiza = ["#000000", "#347460", "#44C3B2", "#8EDBD0", "#E52E2E"],
     cAltafulla = ["#EBA26E", "#C45F43", "#40373D", "#E3CC98", "#67987B"],
     cIndustria = ["#A0A6AD", "#696F80", "#2B3038", "#FFD900", "#FFEA81"],
     cOlivos = ["#44564A", "#DCCBAD", "#142D27", "#6C7860", "#E05848"],
     cMallorca = ["#DCCBAD", "#44564A", "#142D27", "#6C7860", "#E05848"],
     cTortilla = ["#E8E8B0", "#F5BB0C", "#FFD745", "#ED7343", "#26403F"],
     cPaella = ["#F5BB0C", "#FFD745", "#26403F", "#EAD8AF", "#ED5311"],
     cMenorca = ["#75AE9D", "#B42339", "#381B2F", "#D1754C", "#DBBD3B"],
     cLaBarca = ["#FA4A2F", "#088B83", "#2B2B2B", "#000000", "#F2AC72"],
     cBarraca = ["#088B83", "#2B2B2B", "#000000", "#F2AC72", "#FA4A2F"],
     cMar = ["#FAFAFA", "#F9D401", "#F99F00", "#0E376F", "#3A6BA5"],
     cPalamos = ["#E8D5B9", "#E8D5B9", "#0E2430", "#FC3A51", "#F5B349"],
     cBuganvilea = ["#EEF0C6", "#616621", "#9FA619", "#FF027F", "#272225"],
     cAlzines = ["#727E66", "#44564A", "#142D27", "#DCCBAD", "#C6A882"],
     cPuigpedros = ["#CCCEBD", "#982D03", "#010101", "#898D6C", "#A8AA92"],
     cBeget = ["#00B284", "#D1DFB2", "#1C1F1E", "#005A3F", "#00835E"],
     cTots = [cMontseny, cMallorca, cIbiza, cAltafulla, cIndustria, cOlivos, cSalines, cPaella, cTortilla, cMenorca, cLaBarca, cBarraca, cMar, cPalamos, cBuganvilea, cAlzines, cPuigpedros, cBeget];
let p0 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 11, 12],
     p1 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12],
     p2 = [2, 3],
     p3 = [2, 3, 4, 11, 12],
     p4 = [2, 3, 10, 12],
     p5 = [2, 3, 4, 10, 11, 12],
     p6 = [2, 5, 11],
     p7 = [2, 4, 10],
     p8 = [3, 4, 10, 11, 12],
     p9 = [4, 6, 7, 8, 12],
     p10 = [4, 8],
     p11 = [5, 10],
     p12 = [6, 7, 8, 12],
     p13 = [4, 10, 12],
     p14 = [4, 10, 11, 12],
     p15 = [3],
     p16 = [7],
     p17 = [3, 7],
     p18 = [3, 6, 7],
     p19 = [3, 7, 11],
     p20 = [3, 7, 12],
     p21 = [5, 8],
     p22 = [4, 5, 8],
     p23 = [0, 1, 2, 4, 5, 8],
     p24 = [0, 1, 2, 4, 5, 8, 12],
     p25 = [0, 1, 2, 4, 5, 6, 8],
     p26 = [11, 12],
     p27 = [2, 11, 12],
     p28 = [4, 7, 8],
     p29 = [4, 5, 7, 8],
     p30 = [3, 4, 5, 7, 8];
let trossos = [],
     f16 = 1 / 6,
     f26 = 2 / 6,
     f166 = .6 * f16,
     f1635 = .35 * f16,
     f165 = .5 * f16,
     f1625 = .25 * f16,
     ang = 3.14159265359 / 6;
let baro = !1,
     barcs = !1,
     bbuit = !1,
     bcreu = !1;

function setup() {
     w = window.innerWidth, h = window.innerHeight, createCanvas(w, h)
     seed = parseInt(tokenData.hash.slice(0, 16), 16), r = new RND(seed), quantiW = 12, quantiH = 7;
     let s = r.rb(0, 1);
     s > .83 ? (quantiW = 6, quantiH = 3) : s < .1 && (quantiW = 9, quantiH = 5)
     s = r.rb(0, 1), s > .98 ? baro = !0 : s > .94 ? barcs = !0 : s > .87 ? bcreu = !0 : s > .77 && (bbuit = !0, s = r.rb(0, 1), s > .35 && (baro = !0))
     pMin = .89, pMax = .93, 12 == quantiW && (s = r.rb(0, 1), s > .88 && (pMin = .49, pMax = .63))
     mw = int(w / (quantiW + 1)), mh = int(h / (quantiH + 1)), m = min(mw, mh), margeW = w - m * (quantiW + 1), margeW *= .5, margeH = h - m * (quantiH + 1), margeH *= .5
     numc = int(r.rb(0, 18)), c1 = cTots[numc][0], c2 = cTots[numc][1], c3 = cTots[numc][2], c4 = cTots[numc][3], c5 = cTots[numc][4], creaTrossos()
     q = r.rb(0, 195), possibles = q > 185 ? p30 : q > 175 ? p29 : q > 170 ? p28 : q > 165 ? p27 : q > 160 ? p26 : q > 155 ? p25 : q > 150 ? p24 : q > 145 ? p23 : q > 140 ? p22 : q > 135 ? p21 : q > 130 ? p20 : q > 125 ? p19 : q > 115 ? p18 : q > 110 ? p17 : q > 107 ? p16 : q > 105 ? p15 : q > 100 ? p14 : q > 95 ? p13 : q > 85 ? p12 : q > 80 ? p11 : q > 75 ? p10 : q > 65 ? p9 : q > 60 ? p8 : q > 55 ? p7 : q > 45 ? p6 : q > 40 ? p5 : q > 33 ? p4 : q > 30 ? p3 : q > 20 ? p2 : q > 10 ? p1 : p0, len = possibles.length, assignaTrosset()
}

function draw() {
     background(c1), push(), translate(margeW, margeH);
     for (let s = 0; s < trossos.length; s++) push(), translate(trossos[s].x, trossos[s].y), scale(2 * trossos[s].w, 2 * trossos[s].w), trosset(trossos[s].id), pop();
     pop(), noLoop()
}
class Trosset {
     constructor(s, t, c) {
          this.x = s, this.y = t, this.w = c, this.id = 0
     }
}

function creaTrossos() {
     for (let s = 0; s < quantiW; s++)
          for (let t = 0; t < quantiH; t++) trossos.push(new Trosset(s * m, t * m, m));
     for (let s = trossos.length - 1; s >= 0; s--) {
          let t = r.rb(pMin, pMax);
          r.rb(0, 1) > t && (trossos.push(new Trosset(trossos[s].x, trossos[s].y, .5 * trossos[s].w)), trossos.push(new Trosset(trossos[s].x + .5 * trossos[s].w, trossos[s].y, .5 * trossos[s].w)), trossos.push(new Trosset(trossos[s].x, trossos[s].y + .5 * trossos[s].w, .5 * trossos[s].w)), trossos.push(new Trosset(trossos[s].x + .5 * trossos[s].w, trossos[s].y + .5 * trossos[s].w, .5 * trossos[s].w)), trossos.splice(s, 1))
     }
}

function assignaTrosset() {
     for (let s = 0; s < trossos.length; s++) trossos[s].id = possibles[int(r.rb(0, len))]
}

function trosset(s) {
     0 == s ? trossetL() : 1 == s ? trossetR() : 2 == s ? trossetH() : 3 == s ? trossetV() : 4 == s ? trossetP() : 5 == s ? trossetX() : 6 == s ? trossetM() : 7 == s ? trossetVV() : 8 == s ? trossetXX() : 9 == s ? trossetLL() : 10 == s ? trossetPP() : 11 == s ? trossetMN() : 12 == s && trossetMS()
}

function trossetL() {
     fons(), arcsD(c3, f16), bbuit && arcsD(c1, f165), bcreu && creu(c5, f1625), punts5C()
}

function trossetR() {
     fons(), arcsE(c3, f16), bbuit && arcsE(c1, f165), bcreu && creu(c5, f1625), punts4Q()
}

function trossetH() {
     fons(), liniaH(), punts2V(), baro && punts2Vs(), barcs && punts2Vb(), punts4Q(), punts3H()
}

function trossetV() {
     liniaV(), punts2H(), baro && punts2Hs(), barcs && punts2Hb(), punts3V(), punts1NO()
}

function trossetP() {
     fons(), punts2H(), baro && punts2Hs(), barcs && punts2Hb(), punts2V(), baro && punts2Vs(), barcs && punts2Vb(), punts1CO(), bcreu && creu(c1, f1635)
}

function trossetX() {
     arcsD(c2, f16), bbuit && arcsD(c1, f165), arcsE(c3, f16), bbuit && arcsE(c1, f165), punts4D(), punts1SE(), bcreu && creu(c5, f1625)
}

function trossetM() {
     fons(), liniaH(), liniaV(), punts3H(), punts5C()
}

function trossetVV() {
     liniaH(), punts2V(), baro && punts2Vs(), barcs && punts2Vb(), punts3H(), punts1SE()
}

function trossetXX() {
     arcsE(c2, f16), bbuit && arcsE(c1, f165), arcsD(c3, f16), bbuit && arcsD(c1, f165), punts4D(), punts1NO(), bcreu && creu(c5, f1625)
}

function trossetLL() {
     fons(), arcsD(c2, f16), bbuit && arcsD(c1, f165), punts2H(), baro && punts2Hs(), barcs && punts2Hb(), punts1CO(), bcreu && creu(c1, f1635)
}

function trossetPP() {
     fons(), punts2H(), baro && punts2Hs(), barcs && punts2Hb(), punts2V(), baro && punts2Vs(), barcs && punts2Vb(), punts3V()
}

function trossetMN() {
     migFonsN(), liniaH(), puntN(), puntS(), baro && puntSs2(), barcs && puntSb2(), punts1NO(), bcreu && creu(c5, f1625)
}

function trossetMS() {
     migFonsS(), liniaH(), puntN(), baro && puntNs2(), barcs && puntNb2(), puntS(), punts3H()
}

function fons() {
     fill(c2), noStroke(), square(.25, .25, .5), fill(c1), circle(.25, .25, f26), circle(.75, .25, f26), circle(.75, .75, f26), circle(.25, .75, f26)
}

function migFonsN() {
     fill(c2), noStroke(), rect(.25, .25, .5, .25), fill(c1), circle(.25, .25, f26), circle(.75, .25, f26)
}

function migFonsS() {
     fill(c2), noStroke(), rect(.25, .5, .5, .25), fill(c1), circle(.75, .75, f26), circle(.25, .75, f26)
}

function arcsE(s, t) {
     strokeWeight(t), stroke(s), noFill(), arc(.75, .75, .5, .5, radians(180), radians(270)), arc(.25, .25, .5, .5, radians(0), radians(90))
}

function arcsD(s, t) {
     strokeWeight(t), stroke(s), noFill(), arc(.75, .25, .5, .5, radians(90), radians(180)), arc(.25, .75, .5, .5, radians(270), radians(360))
}

function liniaH() {
     strokeWeight(f16), stroke(c3), line(.25, .5, .75, .5)
}

function liniaV() {
     strokeWeight(f16), stroke(c3), line(.5, .25, .5, .75)
}

function punts2V() {
     fill(c4), noStroke(), circle(.5, .25, f16), circle(.5, .75, f16)
}

function punts2Vs() {
     stroke(c5), noFill(), strokeWeight(.03), circle(.5, .25, f165), circle(.5, .75, f165)
}

function punts2Vb() {
     push(), translate(.5, .25), arcs3(f16, c5), fill(c1), circle(0, 0, f165), pop(), push(), translate(.5, .75), arcs3(f16, c5), fill(c1), circle(0, 0, f165), pop()
}

function puntN() {
     fill(c4), noStroke(), circle(.5, .25, f16)
}

function puntNs2() {
     stroke(c5), noFill(), strokeWeight(.03), circle(.5, .25, f165)
}

function puntNb2() {
     push(), translate(.5, .25), arcs3(f16, c5), fill(c1), circle(0, 0, f165), pop()
}

function puntS() {
     fill(c4), noStroke(), circle(.5, .75, f16)
}

function puntSs2() {
     stroke(c5), noFill(), strokeWeight(.03), circle(.5, .75, f165)
}

function puntSb2() {
     push(), translate(.5, .75), arcs3(f16, c5), fill(c1), circle(0, 0, f165), pop()
}

function punts2H() {
     fill(c4), noStroke(), circle(.25, .5, f16), circle(.75, .5, f16)
}

function punts2Hs() {
     stroke(c5), noFill(), strokeWeight(.03), circle(.25, .5, f165), circle(.75, .5, f165)
}

function punts2Hb() {
     push(), translate(.25, .5), arcs3(f16, c5), fill(c1), circle(0, 0, f165), pop(), push(), translate(.75, .5), arcs3(f16, c5), fill(c1), circle(0, 0, f165), pop()
}

function punts5C() {
     fill(c5), noStroke(), circle(.75 + f166 * cos(radians(45)), .25 + f166 * sin(radians(45)), f1635), circle(.75 + f166 * cos(radians(90)), .25 + f166 * sin(radians(90)), f1635), circle(.75 + f166 * cos(radians(135)), .25 + f166 * sin(radians(135)), f1635), circle(.75 + f166 * cos(radians(180)), .25 + f166 * sin(radians(180)), f1635), circle(.75 + f166 * cos(radians(225)), .25 + f166 * sin(radians(225)), f1635)
}

function punts1NO() {
     fill(c5), noStroke(), circle(.25, .25, f166)
}

function punts1SE() {
     fill(c5), noStroke(), circle(.75, .75, f166)
}

function punts1CO() {
     fill(c5), noStroke(), circle(.5, .5, f16)
}

function punts4Q() {
     fill(c5), noStroke(), circle(.25, .25, f165), circle(.75, .25, f165), circle(.75, .75, f165), circle(.25, .75, f165)
}

function punts4D() {
     fill(c5), noStroke(), circle(.25, .5, f1635), circle(.75, .5, f1635), circle(.5, .25, f1635), circle(.5, .75, f1635)
}

function punts3H() {
     fill(c5), noStroke(), circle(lerp(.25, .75, .25), .5, f1635), circle(lerp(.25, .75, .5), .5, f1635), circle(lerp(.25, .75, .75), .5, f1635)
}

function punts3V() {
     fill(c5), noStroke(), circle(.5, lerp(.25, .75, .25), f1635), circle(.5, lerp(.25, .75, .5), f1635), circle(.5, lerp(.25, .75, .75), f1635)
}

function arcs3(s, t) {
     fill(t), noStroke();
     for (let t = 0; t < 3; t++) {
          let c = t * ang * 2;
          arc(0, 0, s, s, c, c + ang)
     }
}

function creu(s, t) {
     stroke(s), noFill(), strokeWeight(.03), line(.5 - t, .5 + t, .5 + t, .5 - t), line(.5 - t, .5 - t, .5 + t, .5 + t)
}

class RND {
     constructor(s) {
          this.seed = s
     }
     rd() {
          return this.seed ^= this.seed << 13, this.seed ^= this.seed >> 17, this.seed ^= this.seed << 5, (this.seed < 0 ? 1 + ~this.seed : this.seed) % 1e3 / 1e3
     }
     rb(s, t) {
          return s + (t - s) * this.rd()
     }
}