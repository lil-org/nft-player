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
 
}

let R = new Random();

//Title: Mental Entanglement

//Description: This artwork, titled 'Mental Entanglement,' is a visual reflection of the intricacy and complexity of our thought processes. The ever-changing patterns and shapes represent the ceaseless activity of our minds, where thoughts intertwine and overlap in a labyrinth of ideas. Through a combination of geometric forms and curves, the artwork captures the duality of our thoughts: clarity and confusion, order and chaos. 'Mental Entanglement' invites the viewer to explore the mental landscape and discover the beauty in the complexity of our thoughts.

let cells = 3+Math.floor(R.random_dec()*19);

let complexity =2+ Math.floor(R.random_dec()*5);


let colores1=[]


colores1.push(["#000000","#FFFBE6"]);//2


let numeroDePaleta=Math.floor(R.random_dec() * colores1.length);
numeroDePaleta=0


let paletaSeleccionada =colores1[numeroDePaleta]
let colorElegido1 = paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)];
let colorElegido2;
do {
  colorElegido2 = paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)];
} while (colorElegido2 === colorElegido1);

let colorElegidoText, colorElegido2Text;
if (colorElegido1=="#000000"){
colorElegidoText= 'Black';
colorElegido2Text='Beige';
} else{
  colorElegidoText= 'Beige';
colorElegido2Text='Black';
}


function setup() {
  let canvasSize= windowHeight
  createCanvas(canvasSize, canvasSize);
 background(colorElegido1);
  
  let margin = canvasSize*0.08;
  
  let sub_cells = 2;
  let cellDim = (width - 2 * margin) / cells;
  let cellDim_2 = cellDim / sub_cells;
  let cellDim_3 = cellDim_2 / sub_cells;
  


  // Dibuja la grilla
  stroke(0); // Color de los bordes de las celdas
  noFill(); // Sin relleno en las celdas

  for (let i = 0; i < cells; i++) {
    for (let j = 0; j < cells; j++) {
     
      let x = margin + i * cellDim;
      let y = margin + j * cellDim;
       
      
      if(R.random_dec()>0.5) {
        for (let k = 0; k < sub_cells; k++) {
          for (let l = 0; l < sub_cells; l++) {
            
            let x_2 = x + k * cellDim_2;
            let y_2 = y + l * cellDim_2;
           
            
            if(R.random_dec()>0.5) {
              for (let m = 0; m < sub_cells; m++) {
                for (let n = 0; n < sub_cells; n++) {
                  
                  let x_3 = x_2 + m * cellDim_3;
                  let y_3 = y_2 + n * cellDim_3;
                  
                  draw(x_3, y_3, cellDim_3);
                }
              }
            }
            else {
              noStroke();
              fill(colorElegido2);
              rect(x_2,y_2,cellDim_2+1,cellDim_2+1)
              draw2(x_2, y_2, cellDim_2);
            }
          }
        }
      }
      else {
        fill(0,255,0)
        
        draw(x, y, cellDim);
      }
    }
  }
}

function draw(x, y, cellDim) {
  let azar = Math.floor(R.random_dec()*complexity);
  
  switch(azar) {
    case 0:
      
      drawPattern1(x, y, cellDim);
      break;
    case 1:
      drawPattern2(x, y, cellDim);
      break;
    case 2:
      drawPattern3(x, y, cellDim);
      break;
     
    default:
      drawPattern4(x, y, cellDim);
      break;
      
  }
}
function draw2(x, y, cellDim) {
  let azar = Math.floor(R.random_dec()*complexity);
  
  switch(azar) {
    case 0:
      draw2Pattern1(x, y, cellDim);
      break;
    case 1:
      draw2Pattern2(x, y, cellDim);
      break;
    case 2:
      draw2Pattern3(x, y, cellDim);
      break;
     
    default:
      draw2Pattern4(x, y, cellDim);
      break;
      
  }
}

function drawPattern1(x, y, cellDim) { //curvas
  push();
  let size=cellDim;
noStroke();
  //fill(255,251,230);
 // rect(x,y,size,size) //rectángulo de fondo

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
  

  //CURVAS GRUESAS
  noFill();
  stroke(colorElegido2);
  //  stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  arc(+size/2,-size/2,size,size,HALF_PI,PI) //Superior derecho
  arc(-size/2,+size/2,size,size,PI+HALF_PI,0) //inferior izquierdo

  pop();
}//curvas
function drawPattern2(x, y, cellDim) {
  push();
  let size=cellDim;
noStroke();
  //fill(255,251,230);
  //rect(x,y,size,size) //rectángulo de fondo

 translate(x+size/2,y+size/2)
 rotate(0);
  

  //CURVAS GRUESAS
  noFill();
     stroke(colorElegido2);
  //  stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  arc(+size/2,-size/2,size,size,HALF_PI,PI) //Superior derecho
  arc(-size/2,+size/2,size,size,PI+HALF_PI,0) //inferior izquierdo

  pop();
  
}//curvas
function drawPattern3(x, y, cellDim) {
   push();
  let size=cellDim;
noStroke();
 

 translate(x+size/2,y+size/2)
 rotate(0);
    
  //CURVAS GRUESAS
  noFill();
    stroke(colorElegido2);
  //  stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0+size/2,0)

  pop();
}//horizontal
function drawPattern4(x, y, cellDim) {
  push();
  let size=cellDim;
noStroke();
 

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
    
  //CURVAS GRUESAS
  noFill();
     stroke(colorElegido2);
  //  stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0+size/2,0)

  pop();
}//vertical

function draw2Pattern1(x, y, cellDim) {
  push();
  let size=cellDim;
noStroke();
  //fill(255,251,230);
 // rect(x,y,size,size) //rectángulo de fondo

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
  

  //CURVAS GRUESAS
  noFill();
 stroke(colorElegido1);
  //   stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  arc(+size/2,-size/2,size,size,HALF_PI,PI) //Superior derecho
  arc(-size/2,+size/2,size,size,PI+HALF_PI,0) //inferior izquierdo
    
  pop();
}//curvas
function draw2Pattern2(x, y, cellDim) {
  push();
  let size=cellDim;
noStroke();
  //fill(255,251,230);
  //rect(x,y,size,size) //rectángulo de fondo

 translate(x+size/2,y+size/2)
 rotate(0);
  
   

  //CURVAS GRUESAS
  noFill();
    stroke(colorElegido1);
  //   stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  arc(+size/2,-size/2,size,size,HALF_PI,PI) //Superior derecho
  arc(-size/2,+size/2,size,size,PI+HALF_PI,0) //inferior izquierdo
  
    
  pop();
  
}//curvas
function draw2Pattern3(x, y, cellDim) {
   push();
  let size=cellDim;
noStroke();
 

 translate(x+size/2,y+size/2)
 rotate(0);
    
  //CURVAS GRUESAS
  noFill();
    stroke(colorElegido1);
  //   stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0+size/2,0)
  
    pop();
} //horizontal
function draw2Pattern4(x, y, cellDim) {
  push();
  let size=cellDim;
noStroke();
 

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
    
  //CURVAS GRUESAS
  noFill();
    stroke(colorElegido1);
  //   stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0+size/2,0)
    
  pop();
} //vertical


