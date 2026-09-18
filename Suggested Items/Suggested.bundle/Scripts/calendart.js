let rndColor, rndDensityIndex, scaling_factor, stroke_weight, frame, bg, rotation, canvas_size, canvas_stroke, corner_radius, R, colors = [],
     density = [],
     events = [],
     stroke_unit = 25,
     corner_scale = 50;
features = ["Palette:Standard", "Frame:Matching", "Background:Matching", "Chaos:None", "Rotation:None", "Opacity:Solid"];
var seed = parseInt(tokenData.hash.slice(0, 16), 16);

function setup() {
     canvas_size = Math.min(windowWidth, windowHeight), canvas_stroke = canvas_size / stroke_unit, cornerRadius = canvas_size / corner_scale, createCanvas(canvas_size, canvas_size), initColors(), R = new Random(seed)
}

function draw() {
     var e;
     rndColor = R.random_int(0, 5), rndColor1 = R.random_int(0, 5), rndColor2 = R.random_int(0, 5);
     let t = R.random_between(0, 1);
     switch (rndColor) {
          case 0:
               features[0] = "Palette:Modern";
               break;
          case 1:
               features[0] = "Palette:Retro";
               break;
          case 2:
               features[0] = "Palette:Feeling Grey";
               break;
          case 3:
               features[0] = "Palette:Regatta";
               break;
          case 4:
               features[0] = "Palette:Energy";
               break;
          case 5:
               features[0] = "Palette:Coffee Shop"
     }
     t < .02 ? (features[0] = "Palette:Whiteout", rndColor = 7) : t > .02 && t < .04 && (features[0] = "Palette:Blackout", rndColor = 6);
     var r = (e = colors[rndColor])[rndColor1],
          n = e[rndColor2];
     let a = R.random_between(0, 1);
     bg = 0, "#000000" != r.toString() && "#FFFFFF" != r.toString() ? a < .2 && (features[2] = "Background: Dark Mode", r = "#1F2124") : (features[2] = "Background: Dark Mode", r = "#1F2124"), background(r), noFill();
     var o = R.random_between(0, 1);
     o > .2 ? (features[1] = "Frame:Matching", stroke(n)) : o < .1 ? (features[1] = "Frame:None", noStroke()) : o > .1 && o < .2 && (features[1] = "Frame:White", stroke("#FFFFFF")), strokeWeight(canvas_stroke), rect(0, 0, width, height), "#1F2124" == r.toString() ? stroke("#1F2124") : "#FFFFFF" == r.toString() ? stroke("#000000") : stroke("#FFFFFF"), "#1F2124" == r.toString() && "#000000" == n.toString() && stroke("#FFFFFF"), rectMode(CENTER), initDensity(), translate(width / 2, height / 2);
     let s = R.random_between(0, 1);
     s < .2 ? (features[3] = "Chaos:Quiet", rndDensityIndex = 3) : s > .2 && s < .5 ? (features[3] = "Chaos:The Usual", rndDensityIndex = 0) : s > .5 && s < .8 ? (features[3] = "Chaos:Busy", rndDensityIndex = 1) : (features[3] = "Chaos:Jam Packed", rndDensityIndex = 2), rows = density[rndDensityIndex][0], cols = density[rndDensityIndex][1], scaling_factor = density[rndDensityIndex][2], stroke_weight = density[rndDensityIndex][3], scale(scaling_factor), translate(-width / 2, -height / 2), strokeWeight(stroke_weight * (canvas_size / 800)), createCalendarGrid(rows, cols);
     let d = R.random_between(0, 1);
     for (let e = 0; e < events.length; e++) calEvent(events[e].x, events[e].y, events[e].w, events[e].h, rndColor, R.random_int(0, 5), R.random_int(1, 11), R.random_int(1, 11), d, cornerRadius);
     noLoop()
}

function createCalendarGrid(e, t) {
     let r = width / t,
          n = height / e;
     for (let a = 0; a < e; a++)
          for (let o = 0; o < t; o++) {
               let s = a * r + r / t,
                    d = o * n + n / e;
               events.push({
                    x: s,
                    y: d,
                    w: r,
                    h: n
               })
          }
}

function calEvent(e, t, r, n, a, o, s, d, i, c) {
     let l = r / 10 * (s - 5),
          F = n / 10 * (d - 5),
          h = r + 1.5 * l,
          f = n + 1.5 * F;
     var u = colors[a];
     alphaColor = color(u[o]), i < .05 ? (features[5] = "Opacity:Translucent", alphaColor.setAlpha(128 + 128 * sin(millis() / 1e3)), fill(alphaColor)) : fill(u[o]), h != f && (h > f ? rect(e + l, t - F, h, f, c) : rect(e - l, t + F, h, f, c))
}

function initColors() {
     colors[0] = ["#EDD552", "#5475E5", "#71C164", "#C75F5F", "#EA983F", "#8E5BBF"], colors[1] = ["#999cff", "#ffad45", "#cca5ac", "#9fe1e7", "#51b748", "#a4bdfc"], colors[2] = ["#E2E2E2", "#CECECE", "#B9B9B9", "#A5A5A5", "#7D7D7D", "#545454"], colors[3] = ["#D64045", "#DCDCDC", "#9Ed8DB", "#467599", "#1d3354", "#BDDADC"], colors[4] = ["#93b7be", "#B9E3F2", "#d5c7bc", "#785964", "#454545", "#F1B555"], colors[5] = ["#0d3b66", "#faf0ca", "#f4d35e", "#ee964b", "#f95738", "#5F4F55"], colors[6] = ["#000000", "#000000", "#000000", "#000000", "#000000", "#000000"], colors[7] = ["#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF", "#FFFFFF"]
}

function initDensity() {
     density[0] = [8, 8, .65, 3.5], density[1] = [10, 10, .7, 3], density[2] = [16, 16, .7, 2.5], density[3] = [7, 7, .65, 4]
}

function rnd_dec() {
     return seed ^= seed << 13, seed ^= seed >> 17, ((seed ^= seed << 5) < 0 ? 1 + ~seed : seed) % 1e3 / 1e3
}

function rnd_num(e, t) {
     return e + (t - e) * rnd_dec()
}

function random_hash() {
     let e = "0123456789abcdef",
          t = "0x";
     for (let r = 64; r > 0; --r) t += e[Math.floor(Math.random() * e.length)];
     return t
}
class Random {
     constructor(e) {
          this.seed = e
     }
     random_dec() {
          return this.seed ^= this.seed << 13, this.seed ^= this.seed >> 17, this.seed ^= this.seed << 5, (this.seed < 0 ? 1 + ~this.seed : this.seed) % 1e3 / 1e3
     }
     random_between(e, t) {
          return e + (t - e) * this.random_dec()
     }
     random_int(e, t) {
          return Math.floor(this.random_between(e, t + 1))
     }
     random_choice(e) {
          return e[Math.floor(this.random_between(0, .99 * e.length))]
     }
}