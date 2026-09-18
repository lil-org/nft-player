var r_period_reset
var g_period_reset
var b_period_reset
var r_period
var g_period
var b_period
const sync_probs = [0.01, 0.05, 0.1, 0.5]
var all_period_sync_prob
var WIDTH = window.innerWidth
var HEIGHT = window.innerHeight
var img
var x_offset = 0
var y_offset = 0
var r_incr = 0.0
var r_value = 0
var g_incr = 0.0
var g_value = 0
var b_incr = 0.0
var b_value = 0
var R
var timey = 0
var drawWait = 1
function setup() {
 createCanvas(WIDTH, HEIGHT)
 noStroke()
 R = new Random() 
 make_parameters()
 update_incrs()
 img = createImage(1000,1000)
 img.loadPixels()
 
 if (WIDTH > HEIGHT)
   x_offset = Math.floor((WIDTH - HEIGHT) / 2)
 else if (HEIGHT > WIDTH)
   y_offset = Math.floor((HEIGHT - WIDTH) / 2)
  background(0);
}
function draw() {
  if (millis() - timey >= drawWait) {
   var y = 0
   for (var j = 0; j < 1000000; j++) {
     if (j % 1000 == 0)
       y = Math.floor(j / 1000)
     var x = int(j % 1000)
     pixel_i = int((y * 1000 + x) * 4)
     img.pixels[pixel_i] = Math.round(r_value)
     img.pixels[pixel_i + 1] = Math.round(g_value)
     img.pixels[pixel_i + 2] = Math.round(b_value)
     img.pixels[pixel_i + 3] = 255
     increment_rbg(j)
   }
   img.updatePixels()
   if (WIDTH > HEIGHT)
     image(img, x_offset, y_offset, HEIGHT, HEIGHT)
   else
     image(img, x_offset, y_offset, WIDTH, WIDTH)
 
   if (R.random_bool(all_period_sync_prob)) sync_periods()
   timey = millis()
  
   if (drawWait == 1)
     drawWait = 5000
   else if (drawWait == 5000)
     drawWait = 500
 }
}
function make_parameters() {
 r_period_reset = Math.floor(1000 / Math.floor(R.random_num(1, 6)))
 g_period_reset = Math.floor(1000 / Math.floor(R.random_num(1, 6)))
 b_period_reset = Math.floor(1000 / Math.floor(R.random_num(1, 6)))
 r_period = r_period_reset
 g_period = g_period_reset
 b_period = b_period_reset
 all_period_sync_prob = sync_probs[Math.floor(R.random_num(0, 4))]
}
function increment_rbg(mega_i) {
 r_value = 255 - abs(255 - (mega_i % r_period) * r_incr)
 if (Math.floor(r_value) <= 0) {
   if (R.random_bool(0.0001)) {
     r_period = random_period(r_period)
     update_incrs()
   } else if (R.random_bool(0.01)) {
     if (R.random_bool) {
       r_incr *= 1.0 + 0.001
     } else {
       r_incr *= 1.0 - 0.001
     }
   }
 }
 g_value = 255 - abs(255 - (mega_i % g_period) * g_incr)
 if (Math.floor(g_value) <= 0) {
   if (R.random_bool(0.0001)) {
     g_period = random_period(g_period)
     update_incrs()
   } else if (R.random_bool(0.01)) {
     if (R.random_bool) {
       g_incr *= 1.0001
     } else {
       g_incr *= 0.9999
     }
   }
 }
 b_value = 255 - abs(255 - (mega_i % b_period) * b_incr)
 if (Math.floor(b_value) <= 0) {
   b_value = 0
   b_incr *= -1
   if (R.random_bool(0.0001)) {
     b_period = random_period(b_period)
     update_incrs()
   } else if (R.random_bool(0.01)) {
     if (R.random_bool) {
       b_incr *= 1.0001
     } else {
       b_incr *= 0.9999
     }
   }
 }
}
function random_period(curr_period) {
 var p = curr_period
 p += R.random_num(-2, 2)
 if (p < 10) p = 10
 return p
}
function sync_period(which) {
 if (which == "r") r_period = r_period_reset
 else if (which == "g") g_period = g_period_reset
 if (which == "b") b_period = b_period_reset
 update_incrs()
}
function sync_periods() {
 r_period = r_period_reset
 g_period = g_period_reset
 b_period = b_period_reset
 update_incrs()
}
function update_incrs() {
 if (r_period < 10) r_period = 10
 if (g_period < 10) g_period = 10
 if (b_period < 10) b_period = 10
 r_incr = 255 / (r_period * 0.5)
 g_incr = 255 / (g_period * 0.5)
 b_incr = 255 / (b_period * 0.5)
}
class Random {
 constructor() {
   this.useA = false
   var sfc32 = function (uint128Hex) {
     var a = parseInt(uint128Hex.substr(0, 8), 16)
     var b = parseInt(uint128Hex.substr(8, 8), 16)
     var c = parseInt(uint128Hex.substr(16, 8), 16)
     var d = parseInt(uint128Hex.substr(24, 8), 16)
     return function () {
       a |= 0
       b |= 0
       c |= 0
       d |= 0
       var t = (((a + b) | 0) + d) | 0
       d = (d + 1) | 0
       a = b ^ (b >>> 9)
       b = (c + (c << 3)) | 0
       c = (c << 21) | (c >>> 11)
       c = (c + t) | 0
       return (t >>> 0) / 4294967296
     }
   }
   this.prngA = new sfc32(tokenData.hash.substr(2, 32))
   this.prngB = new sfc32(tokenData.hash.substr(34, 32))
   for (var i = 0; i < 1e6; i += 2) {
     this.prngA()
     this.prngB()
   }
 }
 random_dec() {
   this.useA = !this.useA
   return this.useA ? this.prngA() : this.prngB()
 }
 random_num(a, b) {
   return a + (b - a) * this.random_dec()
 }
 random_bool(p) {
   return this.random_dec() < p
 }
}
