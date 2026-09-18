let seed = parseInt(tokenData.hash.slice(0, 16), 16);
let hashPairs = [];
for (let j = 0; j < 32; j++) {
     hashPairs.push(tokenData.hash.slice(2 + (j * 2), 4 + (j * 2)));
}
let rvs = hashPairs.map(x => {
     return parseInt(x, 16) % 20;
});

let palette_choices = [
     ["#FF0000", "#00A08A", "#F2AD00", "#F98400", "#5BBCD6"],
     ["#E6A0C4", "#C6CDF7", "#D8A499", "#7294D4"],
     ["#B0305C", "#EB564B", "#73275C"],
     ["#363636", "#E8175D"],
     ["#EEEEEE", "#CC0E74"],
     ["#FFFFEB", "#C2C2D1"],
     ["#5d54a4", "#d789d7", "#9d65c9"],
     ["#000003", "#FF0033"]
];

var DEFAULT_SIZE = 500;
var WIDTH = window.innerWidth;
var HEIGHT = window.innerHeight;
var DIM = Math.min(WIDTH, HEIGHT);
var M = DIM / DEFAULT_SIZE;
var PI = 3.141592653589793;
var HPI = PI / 2;
var QPI = PI / 4;

let rv0 = rvs[0];
let rv1 = rvs[1];
let rv2 = rvs[2];
let rv3 = rvs[3];
let rv4 = rvs[4];
let rv5 = rvs[5];
let rv6 = rvs[6];

let cp_r = rnd_outcome(rv0, [19, 18, 17, 16, 14, 12, 8], [7, 6, 5, 4, 3, 2, 1], 0);
let bg_r = rnd_outcome(rv1, [10], [0], 1);
let pal = palette_choices[cp_r];
if (bg_r == 0) {
     var bg = pal[0];
     var fg = pal.slice(1);
} else {
     var bg = pal[pal.length - 1];
     var fg = pal.slice(0, pal.length - 1);
}

var pie_count = rnd_outcome(rv2, [19, 18, 17, 16, 14, 12], [4, 5, 6, 8, 14, 12], 10);
var C = M * 10 / pie_count
var pie_space = 11 * C
var stk_weight = 2 * C
var stk_color = rnd_outcome(rv3, [10], ["#EEEEEE"], "#000003");
var pie_number = rnd_outcome(rv4, [10], [2], 1);

if (rv5 == 19) {
     if (rv6 == 19) {
          bg = "#303a52"
          fg = ["#283149", "#1b2232"]
          stk_color = "#a7ff83"
     }
}
if (rv5 == 18) {
     if (rv6 == 18) {
          bg = "#1eafed"
          fg = ["#eef2f5", "#FFFFFF"]
          stk_color = "#000000"
     }
}

let spacing = DIM / pie_count;
let size = spacing - pie_space;

let objects = []
for (let x = spacing; x + (spacing / 2) < DIM; x += spacing) {
     for (let y = spacing; y + (spacing / 2) < DIM; y += spacing) {
          let start = rnd_between(0, HPI);
          let end_1 = rnd_between(start + QPI, start + PI);
          let end_2 = start + QPI;

          let pie_1 = {
               color: rnd_choice(fg),
               x: x,
               y: y,
               size: size,
               start: start,
               end: end_1
          };
          let pie_2 = {
               color: rnd_choice(fg),
               x: x,
               y: y,
               size: size,
               start: start,
               end: end_2
          };
          let stk_1 = {
               color: stk_color,
               weight: stk_weight,
               x: x,
               y: y,
               size: size - 10 * C,
               start: start,
               end: end_1 / 2
          };
          let stk_2 = {
               color: stk_color,
               weight: stk_weight,
               x: x,
               y: y,
               size: size + 5 * C,
               start: start,
               end: end_1 * 2
          };

          let object = {
               pie_1: pie_1,
               pie_2: pie_2,
               stk_1: stk_1,
               stk_2: stk_2
          };

          objects.push(object);
     }
}

function setup() {
     createCanvas(DIM, DIM);
}

function draw() {
     background(bg);
     let pct = (mouseX + (DIM - mouseY)) / (2 * DIM);
     pct = pct < 0 ? 0 : pct;
     pct = pct > 1 ? 1 : pct;

     for (let i = 0; i < objects.length; i++) {
          let object = objects[i];
          let p1 = object.pie_1;
          let p2 = object.pie_2;
          let s1 = object.stk_1;
          let s2 = object.stk_2;

          let p1_add = (p1.end - p1.start) * pct;
          let p2_add = (p2.end - p2.start) * pct;
          let s1_sub = (s1.end - s2.start) * pct;

          pie(p1.color, p1.x, p1.y, p1.size, p1.start, p1.end + p1_add);
          if (pie_number == 2) {
               pie(p2.color, p2.x, p2.y, p2.size, p2.start, p2.end + p2_add);
          }
          stk(s1.color, s1.weight, s1.x, s1.y, s1.size, s1.start - s1_sub, s1.end);
          stk(s2.color, s2.weight, s2.x, s2.y, s2.size, s2.start, s2.end);
     }
}

function pie(color, x, y, size, start, end) {
     noStroke();
     fill(color);
     arc(x, y, size, size, start, end);
}

function stk(color, weight, x, y, size, start, end) {
     strokeWeight(weight);
     stroke(color);
     noFill();
     arc(x, y, size, size, start, end);
}

function rnd_dec() {
     seed ^= seed << 13;
     seed ^= seed >> 17;
     seed ^= seed << 5;
     return (((seed < 0) ? ~seed + 1 : seed) % 1000) / 1000;
}

function rnd_between(a, b) {
     return a + (b - a) * rnd_dec();
}

function rnd_choice(choices) {
     return choices[Math.floor(rnd_between(0, choices.length * 0.99))];
}

function rnd_outcome(input, values, outcome, fallback) {
     var zip = (a, b) => a.map((x, i) => [x, b[i]]);
     for (let [a, b] of zip(values, outcome))
          if (input >= a) {
               return b;
          }
     return fallback;
}