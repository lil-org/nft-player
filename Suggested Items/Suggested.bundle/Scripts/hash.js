class Random {
  constructor() {
    this.useA = false;
    let sfc32 = function (uint128Hex) {
      let a = parseInt(uint128Hex.substring(0, 8), 16);
      let b = parseInt(uint128Hex.substring(8, 16), 16);
      let c = parseInt(uint128Hex.substring(16, 24), 16);
      let d = parseInt(uint128Hex.substring(24, 32), 16);
      return function () {
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
    // seed prngA with first half of tokenData.hash
    this.prngA = new sfc32(tokenData.hash.substring(2, 34));
    // seed prngB with second half of tokenData.hash
    this.prngB = new sfc32(tokenData.hash.substring(34, 66));
    for (let i = 0; i < 1e6; i += 2) {
      this.prngA();
      this.prngB();
    }
  }
  // random number between 0 (inclusive) and 1 (exclusive)
  random_dec() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  // random number between a (inclusive) and b (exclusive)
  random_num(a, b) {
    return a + (b - a) * this.random_dec();
  }
  // random integer between a (inclusive) and b (inclusive)
  // requires a < b for proper probability distribution
  random_int(a, b) {
    return Math.floor(this.random_num(a, b + 1));
  }
  // random boolean with p as percent liklihood of true
  random_bool(p) {
    return this.random_dec() < p;
  }
  // random value in an array of items
  random_choice(list) {
    return list[this.random_int(0, list.length - 1)];
  }
}

let R = new Random();


let WIDTH;
let HEIGHT;
const aspectRatio = 1;
const DEFAULT_SIZE = 2000;
let margin;

let rowCount = 400;
let colCount = 400;

let cellWidth = 0;
let cellHeight = 0;

let cellWidth2 = 0;
let cellHeight2 = 0;

let startAngle = 0;
let endAngle = 0;
let _endAngle = 0;
let angleInc = 0;

let points = [];

const _COLORS_ = [
  [["#40ffdc", "#00a9d4", "#1c3166", "#240047", "#1c0021"], "Blues"],
  [["#0d0f36", "#294380", "#69d2cd", "#b9f1d6", "#f1f6ce"], "Ocean flow"],
  [["#13141a", "#a90448", "#fb3640", "#fda543", "#17c69b"], "Retro"],
  [["#185b63", "#c0261c", "#ba460d", "#c59538", "#404040"], "Teal Orange"],
  [["#243757", "#3a5f6f", "#dad5b7", "#c2b79b", "#665e52"], "Snowy night"],
  [["#e1c78c", "#eda011", "#db6516", "#7a6949", "#adad8e"], "Sunny woods"],
  [["#e0d1ed", "#f0b9cf", "#e63c80", "#c70452", "#4b004c"], "Moonlit cherry"],
  [["#bd2a33", "#d6aa26", "#93a31c", "#408156", "#30374f"], "Hibiscus"],
  [["#fcbf6b", "#e58634", "#657a38", "#afab50", "#a9ccb9"], "Olive"],
  [["#f2eabc", "#54736e", "#194756", "#080000", "#ff3b58"], "Wine and night"],
  [["#079ea6", "#1e0c42", "#f0077b", "#f5be58", "#e3e0b3"], "Beach day"],
  [["#484848", "#006465", "#0f928c", "#00c9d2", "#beee3b"], "Plantation dreams"],
  [["#5b1d99", "#0074b4", "#00b34c", "#ffd41f", "#fc6e3d"], "Tulips"],
  [["#f0f0f0", "#d8d8d8", "#c0c0a8", "#604848", "#484848"], "Moonlight"],
  [["#02031a", "#021b2b", "#b10c43", "#ff0841", "#ebdfcc"], "Vintage rose"],
  [["#181419", "#4a073c", "#9e0b41", "#cc3e18", "#f0971c"], "Halloween"],
  [["#7a5b3e", "#fafafa", "#fa4b00", "#cdbdae", "#1f1f1f"], "Eruption"],
  [["#d1e751", "#ffffff", "#000000", "#4dbce9", "#26ade4"], "Beach house"],
  [["#aaff00", "#ffaa00", "#ff00aa", "#aa00ff", "#00aaff"], "Neon"],
  [["#ff4e50", "#fc913a", "#f9d423", "#ede574", "#e1f5c4"], "Magma"],
  [["#ffffff", "#cbe86b", "#f2e9e1", "#1c140d", "#cbe86b"], "Meadeow"],
  [["#3e4147", "#fffedf", "#dfba69", "#5a2e2e", "#2a2c31"], "Gold graphite"],
  [["#e8d5b7", "#0e2430", "#fc3a51", "#f5b349", "#e8d5b9"], "Dawn"],
  [["#000000", "#8f1414", "#e50e0e", "#f3450f", "#fcac03"], "Fullmoon Lantern"],
  [["#413249", "#ccc591", "#e2b24c", "#eb783f", "#ff426a"], "Spring Lantern"],
  [["#eddbc4", "#a3c9a7", "#ffb353", "#ff6e4a", "#5c5259"], "Boho charm"],
  [["#3b234a", "#523961", "#baafc4", "#c3bbc9", "#d4c7bf"], "Lavender"],
  [["#383939", "#149c68", "#38c958", "#aee637", "#fffedb"], "Algae"],
  [["#000000", "#111111", "#222222", "#333333", "#ffffff"], "Grayscale"]
];
let pal;
function setup() {
  HEIGHT = windowHeight;
  WIDTH = windowWidth;
  if (HEIGHT < WIDTH ) {
      WIDTH = HEIGHT ;
  } else {
      HEIGHT = WIDTH ;
  }
  createCanvas(WIDTH, HEIGHT);
  
  pal = R.random_choice(_COLORS_)[0];
  const scaleFactor = Math.min(windowWidth / DEFAULT_SIZE, windowHeight / (DEFAULT_SIZE / aspectRatio));
  console.log(scaleFactor);
  margin=100*scaleFactor;
  
  cellWidth = WIDTH/rowCount;
  cellHeight = HEIGHT/colCount;

 cellHeight *= 10;
  
  cellWidth2 = cellWidth/2;
  cellHeight2 = cellHeight/2;
  
  background('#ebe5d8');
 
noStroke();
//startAngle = R.random_dec()
   //endAngle = R.random_dec()
  const div = R.random_num(1,10)
  angleInc = R.random_dec()/div
  for(let row = 40;row<rowCount-40;row++){
  fill(R.random_choice(pal));
   for(let col = 40;col<colCount-40;col++){
      let x = map(col,0,rowCount,0,WIDTH);
      let y = map(row,0,colCount,0,HEIGHT);
      endAngle+=angleInc;
      if(endAngle >= TWO_PI) {
        endAngle = 0
      }
    
      if(row%3===0){
        arc(x+cellWidth2,y+cellHeight2, cellWidth, cellHeight, startAngle,endAngle);
        
      }
     
    } 
  }

}

function draw() {
  
}