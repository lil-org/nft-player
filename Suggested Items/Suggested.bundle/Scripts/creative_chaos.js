/*
Title:Creative Chaos
Artist: Buitrago
Description:
"Creative Chaos" is an expression of generative art in code. With each execution, this program brings to life seemingly chaotic yet surprisingly beautiful graphic patterns. Each creation is unique, the result of a meticulous dance between random elements and graphic structures. This piece embodies the idea that innovation and originality often emerge from chaos, where unexpected ideas and surprising connections flourish. "Creative Chaos" reminds us that the human mind finds beauty in disorder and that creativity thrives when chaos and imagination intertwine.

*/

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

let colores1=[];
let complexity=Math.floor(R.random_dec()*11);
let dotcomplexity=Math.floor(R.random_dec()*11);
let dotcomplexityRnd=R.random_dec();
let complexityRnd=R.random_dec();

let dotazar = Math.floor(R.random_dec()*dotcomplexity);

let backgroundFactor=R.random_dec();


 colores1.push( ["#B32202", "#FF481F", "#FF3305", "#00B372", "#05FFA5"])//0
colores1.push( ["#8A2BE2", "#4B0082", "#9400D3", "#9932CC", "#FF00FF"])//1
colores1.push( ["#3D182B", "#AD0626", "#FF005A", "#FF9800", "#FFCE00"])//2
colores1.push( ["#FF5678", "#FF7598", "#FF979D", "#FFB4BF", "#FFB9DF"])//3
colores1.push( ["#f26b7a", "#f0f2dc", "#d9eb52", "#8ac7de", "#87796f"])//4
colores1.push( ["#651366", "#a71a5b", "#e7204e", "#f76e2a", "#f0c505"])//5
colores1.push( ["#c7003f", "#f90050", "#f96a00", "#faab00", "#daf204"])//6
colores1.push( ["#333237", "#fb8351", "#ffad64", "#e9e2da", "#add4d3"])//7
colores1.push( ["#fa3419", "#f3e1b6", "#7cbc9a", "#23998e", "#1d5e69"])//8
colores1.push( ["#1f1f20", "#2b4c7e", "#567ebb", "#606d80", "#dce0e6"])//9
colores1.push( ["#f2e7d2", "#f79eb1", "#ae8fba", "#4c5e91", "#473469"])//10
colores1.push( ["#0780d2", "#92dbf2", "#11588c", "#62869c", "#a4bdcd"])//11
colores1.push( ["#f35809", "#f0dd89", "#7e2c09", "#a08256", "#b4ac74"])//12
colores1.push( ["#04569a", "#ed936b", "#043f7b", "#ae5657", "#b8cddd"])//13
colores1.push( ["#3d44bf", "#eda5f7", "#4d0b78", "#79509d", "#a19db8"])//14
colores1.push( ["#1f74d5", "#84bff4", "#44236f", "#845798", "#d5bdde"])//15
colores1.push( ["#75616b", "#bfcff7", "#dce4f7", "#f8f3bf", "#d34017"])//16

 

let numeroDePaleta=Math.floor(R.random_dec() * colores1.length);

let paletaSeleccionada =colores1[numeroDePaleta]

let colorElegido = paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)];


let randomFondo1=R.random_dec();

let randomFondo2=R.random_dec();

let randomFondo3=R.random_dec();


let colorDotFactor= R.random_dec();

 let primosHasta37 = [2,2,3,3,5,5,7,11,13];
let numeroPrimoSeleccionado = primosHasta37[Math.floor(R.random_dec()* primosHasta37.length)];

let cells = numeroPrimoSeleccionado; //nb 

let marginFactor;
if(cells===2||cells===3){
  marginFactor=0.2;
}else if(cells===5||cells===7){
  marginFactor=0.18
}else{
  marginFactor=0.15
}

function setup() {
  let arRnd=R.random_dec();//factor random de aspectratio
  
  let aspectRatioFactor;
  if(arRnd<0.25){
    aspectRatioFactor=2/3;
  }else if(arRnd<0.5){
    aspectRatioFactor=1;
  }else if(arRnd<0.75) {
    aspectRatioFactor=3/4;
  }else{
    aspectRatioFactor=9/16;
  }
aspectRatioFactor=1;
  let canvasHeight= windowHeight;
 // canvasHeight=2160;
  let canvasWidth= canvasHeight*aspectRatioFactor;
  createCanvas(canvasWidth, canvasHeight);
  
  if (backgroundFactor<0.3){
    background(colorElegido);
    fill(255,200)
    rect(0,0,width,height);
   } else{
           background(255,251,230); // Color de fondo del lienzo
        }
 
  let margin = canvasWidth*marginFactor;
  
  let sub_cells = 2;
  let cellDim = (width - 2 * margin) / cells;
  
  let cellDim_2 = cellDim / sub_cells;
  let cellDim_3 = cellDim_2 / sub_cells;
  
  let cellRows, cellHeightFactor;
  
  if(aspectRatioFactor===2/3){
    cellRows=(width*3/2-3*margin)/cellDim;
    cellHeightFactor=1.5;
  }else if (aspectRatioFactor===1){
    cellRows=cells;
    cellHeightFactor=1;
  }else if (aspectRatioFactor ===3/4){
    cellRows=(width*4/3-margin*8/3)/cellDim;
    cellHeightFactor=4/3;
  }else{
    cellRows=(width*16/9-margin*32/9)/cellDim;
    cellHeightFactor=16/9;
  }

  // Dibuja la grilla
  stroke(0); // Color de los bordes de las celdas
  noFill(); // Sin relleno en las celdas

  for (let i = 0; i < cells; i++) {
    for (let j = 0; j < cellRows; j++) {
     
      let x = margin + i * cellDim;
      let y = margin*cellHeightFactor + j * cellDim;
       
      
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
                  
                   if (randomFondo3<0.3){
                        
                     noStroke();
                           fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)] )
                          rect(x_3,y_3,cellDim_3,cellDim_3)
                     
                          }
                  draw(x_3, y_3, cellDim_3);
                  //dots(x_3,y_3,cellDim_3);
                }
              }
            }
            else {
              if (randomFondo2<0.3){
                
                  noStroke();
                   fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)]);
                    rect(x_2,y_2,cellDim_2,cellDim_2)
               
                      }else{
                        fill(0);
              rect(x_2,y_2,cellDim_2,cellDim_2)
                      }
              
              draw2(x_2, y_2, cellDim_2);
            }
          }
        }
      }
      else {
        if (randomFondo1<0.3){
          
    noStroke();
     fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)] );
  rect(x,y,cellDim,cellDim);
          
  }
        
        draw(x, y, cellDim);
        dots(x,y,cellDim);
      }
    }
  }
  
  
}

function draw(x, y, cellDim) {
  let azar = Math.floor(R.random_dec()*complexity);
  
  switch(azar) {
    case 0:
      if (complexityRnd<0.5){
        drawPattern1(x, y, cellDim);
      }else {
        drawPattern2(x, y, cellDim);
      }
      
      break;
    case 1:
     if (complexityRnd<0.165){
        drawPattern1(x, y, cellDim);
      }else if (complexityRnd<0.33){
        drawPattern2(x, y, cellDim);
      }else if (complexityRnd<0.495){
        drawPattern3(x, y, cellDim);
      }else if (complexityRnd<0.66){
        drawPattern4(x, y, cellDim);
      }else if (complexityRnd<0.825){
        drawPattern5(x, y, cellDim);
      }else {
        drawPattern6(x, y, cellDim);
      }
      
      break;
    case 2:
      if (complexityRnd<0.165){
        draw2Pattern6(x, y, cellDim);
      }else if (complexityRnd<0.33){
        drawPattern1(x, y, cellDim);
      }else if (complexityRnd<0.495){
        drawPattern2(x, y, cellDim);
      }else if (complexityRnd<0.66){
        drawPattern3(x, y, cellDim);
      }else if (complexityRnd<0.825){
        drawPattern4(x, y, cellDim);
      }else {
        drawPattern5(x, y, cellDim);
      }
      
      break;
      case 3:
      if (complexityRnd<0.165){
        drawPattern5(x, y, cellDim);
      }else if (complexityRnd<0.33){
        drawPattern6(x, y, cellDim);
      }else if (complexityRnd<0.495){
        drawPattern1(x, y, cellDim);
      }else if (complexityRnd<0.66){
        drawPattern2(x, y, cellDim);
      }else if (complexityRnd<0.825){
        drawPattern3(x, y, cellDim);
      }else {
        drawPattern6(x, y, cellDim);
      }
      
      break;
      case 4:
      if (complexityRnd<0.165){
        drawPattern4(x, y, cellDim);
      }else if (complexityRnd<0.33){
         drawPattern5(x, y, cellDim);
      }else if (complexityRnd<0.495){
        drawPattern6(x, y, cellDim);
      }else if (complexityRnd<0.66){
        drawPattern1(x, y, cellDim);
      }else if (complexityRnd<0.825){
        drawPattern2(x, y, cellDim);
      }else {
        drawPattern3(x, y, cellDim);
      }
      
      break;
     
    default:
      if (complexityRnd<0.165){
        drawPattern3(x, y, cellDim);
      }else if (complexityRnd<0.33){
        drawPattern4(x, y, cellDim);
      }else if (complexityRnd<0.495){
        drawPattern5(x, y, cellDim);
      }else if (complexityRnd<0.66){
        drawPattern6(x, y, cellDim);
      }else if (complexityRnd<0.825){
        drawPattern1(x, y, cellDim);
      }else {
        drawPattern2(x, y, cellDim);
      }
      
      break;
      
  }
}
function draw2(x, y, cellDim) {
  let azar = Math.floor(R.random_dec()*complexity);
  
  switch(azar) {
    case 0:
      if (complexityRnd<0.165){
        draw2Pattern1(x, y, cellDim);
      }else if (complexityRnd<0.33){
        draw2Pattern2(x, y, cellDim);
      }else if (complexityRnd<0.495){
        draw2Pattern3(x, y, cellDim);
      }else if (complexityRnd<0.66){
        draw2Pattern4(x, y, cellDim);
      }else if (complexityRnd<0.825){
        draw2Pattern5(x, y, cellDim);
      }else {
        draw2Pattern6(x, y, cellDim);
      }
      
      break;
    case 1:
     if (complexityRnd<0.165){
        draw2Pattern1(x, y, cellDim);
      }else if (complexityRnd<0.33){
        draw2Pattern2(x, y, cellDim);
      }else if (complexityRnd<0.495){
        draw2Pattern3(x, y, cellDim);
      }else if (complexityRnd<0.66){
        draw2Pattern4(x, y, cellDim);
      }else if (complexityRnd<0.825){
        draw2Pattern5(x, y, cellDim);
      }else {
        draw2Pattern6(x, y, cellDim);
      }
      
      break;
    case 2:
      if (complexityRnd<0.165){
        draw2Pattern6(x, y, cellDim);
      }else if (complexityRnd<0.33){
        draw2Pattern1(x, y, cellDim);
      }else if (complexityRnd<0.495){
        draw2Pattern2(x, y, cellDim);
      }else if (complexityRnd<0.66){
        draw2Pattern3(x, y, cellDim);
      }else if (complexityRnd<0.825){
        draw2Pattern4(x, y, cellDim);
      }else {
        draw2Pattern5(x, y, cellDim);
      }
      
      break;
      case 3:
      if (complexityRnd<0.165){
        draw2Pattern5(x, y, cellDim);
      }else if (complexityRnd<0.33){
        draw2Pattern6(x, y, cellDim);
      }else if (complexityRnd<0.495){
        draw2Pattern1(x, y, cellDim);
      }else if (complexityRnd<0.66){
        draw2Pattern2(x, y, cellDim);
      }else if (complexityRnd<0.825){
        draw2Pattern3(x, y, cellDim);
      }else {
        draw2Pattern6(x, y, cellDim);
      }
      
      break;
      case 4:
      if (complexityRnd<0.165){
        draw2Pattern4(x, y, cellDim);
      }else if (complexityRnd<0.33){
         draw2Pattern5(x, y, cellDim);
      }else if (complexityRnd<0.495){
        draw2Pattern6(x, y, cellDim);
      }else if (complexityRnd<0.66){
        draw2Pattern1(x, y, cellDim);
      }else if (complexityRnd<0.825){
        draw2Pattern2(x, y, cellDim);
      }else {
        draw2Pattern3(x, y, cellDim);
      }
      
      break;
     
    default:
      if (complexityRnd<0.165){
        draw2Pattern3(x, y, cellDim);
      }else if (complexityRnd<0.33){
        draw2Pattern4(x, y, cellDim);
      }else if (complexityRnd<0.495){
        draw2Pattern5(x, y, cellDim);
      }else if (complexityRnd<0.66){
        draw2Pattern6(x, y, cellDim);
      }else if (complexityRnd<0.825){
        draw2Pattern1(x, y, cellDim);
      }else {
        draw2Pattern2(x, y, cellDim);
      }
      
      break;
      
  }
}

function dots(x, y, cellDim) {
  
  
  switch(dotazar) {
    case 0:
      if (dotcomplexityRnd<0.165){
        dotsPattern1(x, y, cellDim);
       }else if (dotcomplexityRnd<0.33){
        dotsPattern2(x, y, cellDim);
        }else if (dotcomplexityRnd<0.495){
        dotsPattern3(x, y, cellDim);
       }else if (dotcomplexityRnd<0.66){
        dotsPattern4(x, y, cellDim);
        }else if (dotcomplexityRnd<0.825){
        dotsPattern5(x, y, cellDim);
       }else {
        dotsPattern6(x, y, cellDim);
       }
      
      break;
    case 1:
     if (dotcomplexityRnd<0.165){
        dotsPattern1(x, y, cellDim);
      }else if (dotcomplexityRnd<0.33){
        dotsPattern2(x, y, cellDim);
      }else if (dotcomplexityRnd<0.495){
        dotsPattern3(x, y, cellDim);
      }else if (dotcomplexityRnd<0.66){
        dotsPattern4(x, y, cellDim);
      }else if (dotcomplexityRnd<0.825){
        dotsPattern5(x, y, cellDim);
      }else {
        dotsPattern6(x, y, cellDim);
      }
      
      break;
    case 2:
      if (dotcomplexityRnd<0.165){
        dotsPattern6(x, y, cellDim);
        }else if (dotcomplexityRnd<0.33){
        dotsPattern1(x, y, cellDim);
        }else if (dotcomplexityRnd<0.495){
        dotsPattern2(x, y, cellDim);
        }else if (dotcomplexityRnd<0.66){
        dotsPattern3(x, y, cellDim);
        }else if (dotcomplexityRnd<0.825){
        dotsPattern4(x, y, cellDim);
        }else {
        dotsPattern5(x, y, cellDim);
       }
      
      break;
      case 3:
      if (dotcomplexityRnd<0.165){
        dotsPattern5(x, y, cellDim);
       }else if (dotcomplexityRnd<0.33){
        dotsPattern6(x, y, cellDim);
        }else if (dotcomplexityRnd<0.495){
         dotsPattern1(x, y, cellDim);
        }else if (dotcomplexityRnd<0.66){
        dotsPattern2(x, y, cellDim);
       }else if (dotcomplexityRnd<0.825){
        dotsPattern3(x, y, cellDim);
        }else {
        dotsPattern6(x, y, cellDim);
       }
      
      break;
      case 4:
      if (dotcomplexityRnd<0.165){
        dotsPattern4(x, y, cellDim);
       }else if (dotcomplexityRnd<0.33){
         dotsPattern5(x, y, cellDim);
        }else if (dotcomplexityRnd<0.495){
        dotsPattern6(x, y, cellDim);
       }else if (dotcomplexityRnd<0.66){
        dotsPattern1(x, y, cellDim);
       }else if (dotcomplexityRnd<0.825){
        dotsPattern2(x, y, cellDim);
       }else {
        dotsPattern3(x, y, cellDim);
       }
      
      break;
     
    default:
      if (dotcomplexityRnd<0.165){
        dotsPattern3(x, y, cellDim);
       }else if (dotcomplexityRnd<0.33){
        dotsPattern4(x, y, cellDim);
        }else if (dotcomplexityRnd<0.495){
        dotsPattern5(x, y, cellDim);
       }else if (dotcomplexityRnd<0.66){
        dotsPattern6(x, y, cellDim);
       }else if (dotcomplexityRnd<0.825){
        dotsPattern1(x, y, cellDim);
       }else {
        dotsPattern2(x, y, cellDim);
       }
      
      break;
      
  }
}

function drawPattern1(x, y, cellDim) { //curvas
  push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
  

  //CURVAS GRUESAS
  noFill();
    stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  arc(+size/2,-size/2,size,size,HALF_PI,PI) //Superior derecho
  arc(-size/2,+size/2,size,size,PI+HALF_PI,0) //inferior izquierdo
  
 //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
     
  /*
   //CIRCULOS EN CRUZ +
 fill(0);
  
 ellipse(0,0+size/2,size/3,size/3);
  ellipse(0+size/2,0,size/3,size/3);
  ellipse(0,-size/2, size/3, size/3);
  ellipse(0-size/2,0, size/3, size/3);
     
*/
  
   pop();
}//curvas
function drawPattern2(x, y, cellDim) {
  push();
  let size=cellDim;
 
 translate(x+size/2,y+size/2)
 rotate(0);
  

  //CURVAS GRUESAS
  noFill();
    stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  arc(+size/2,-size/2,size,size,HALF_PI,PI) //Superior derecho
  arc(-size/2,+size/2,size,size,PI+HALF_PI,0) //inferior izquierdo
  
 //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)] )
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
   
  
  
  
  /*
   fill(255,251,230);
//CIRCULOS EN CRUZ +
 fill(0);
  
 ellipse(0,0+size/2,size/3,size/3);
  ellipse(0+size/2,0,size/3,size/3);
  ellipse(0,-size/2, size/3, size/3);
  ellipse(0-size/2,0, size/3, size/3);
  */
  
  pop();
  
}//curvas
function drawPattern3(x, y, cellDim) {
   push();
  let size=cellDim;
  
 translate(x+size/2,y+size/2)
 rotate(0);
    
  //CURVAS GRUESAS
  noFill();
    stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0+size/2,0)
  
 
 //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)] )
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
   
  
  
  
  /*
   //CIRCULOS EN CRUZ +
 fill(0);
  ellipse(0-size/2,0, size/3, size/3);//ARRIBA
  ellipse(0+size/2,0,size/3,size/3);//ABAJO
  
  ellipse(0,0+size/2,size/3,size/3); //IZQUIERDO
  ellipse(0,-size/2, size/3, size/3); // DERECHO

 */
  
  pop();
}//horizontal
function drawPattern4(x, y, cellDim) {
  push();
  let size=cellDim;
  
 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
    
  //CURVAS GRUESAS
  noFill();
    stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0+size/2,0)
 
 //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
     
  pop();
}//vertical
function drawPattern5(x, y, cellDim) {
  push();
  let size=cellDim;
  
 translate(x+size/2,y+size/2)
 rotate(0);
    
  //CURVAS GRUESAS
  noFill();
    stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0,0)
 
 //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
  
  //CIRCULOS EN CRUZ
   fill(0);
ellipse(0+size/2,0,size/3,size/3);//DERECHO
  
     
  
  /*
    //CIRCULOS EN CRUZ +
 fill(0);
  ellipse(0-size/2,0, size/3, size/3);//IZQUIERDO
  
  ellipse(0,0+size/2,size/3,size/3); //ABAJO
   ellipse(0,-size/2, size/3, size/3); // ARRIBA

 */
  
  pop();
}//horizontal con punto
function drawPattern6(x, y, cellDim) {
  push();
  let size=cellDim;
  
 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
    
  //CURVAS GRUESAS
  noFill();
    stroke(0);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0,0)
 
 //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
  
  //CIRCULOS EN CRUZ
   fill(0);
ellipse(0+size/2,0,size/3,size/3);//DERECHO
  
     
  
  /*
    //CIRCULOS EN CRUZ +
 fill(0);
  ellipse(0-size/2,0, size/3, size/3);//IZQUIERDO
  
  ellipse(0,0+size/2,size/3,size/3); //ABAJO
   ellipse(0,-size/2, size/3, size/3); // ARRIBA

 */
  
  pop();
}//vertical con punto

function draw2Pattern1(x, y, cellDim) {
  push();
  let size=cellDim;
 
 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
  

  //CURVAS GRUESAS
  noFill();
    stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  arc(+size/2,-size/2,size,size,HALF_PI,PI) //Superior derecho
  arc(-size/2,+size/2,size,size,PI+HALF_PI,0) //inferior izquierdo
  
  //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)] )
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
   
  

/*

  
  
  noStroke();
 fill(255,251,230);
  
 ellipse(0,0+size/2,size/6,size/6);
  ellipse(0+size/2,0,size/6,size/6);
  ellipse(0,-size/2, size/6, size/6);
  ellipse(0-size/2,0, size/6, size/6);

  */
  
  pop();
}//curvas
function draw2Pattern2(x, y, cellDim) {
  push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(0);
  
   

  //CURVAS GRUESAS
  noFill();
    stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  arc(+size/2,-size/2,size,size,HALF_PI,PI) //Superior derecho
  arc(-size/2,+size/2,size,size,PI+HALF_PI,0) //inferior izquierdo
  
  //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)] )
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)

  
  pop();
  
}//curvas
function draw2Pattern3(x, y, cellDim) {
   push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(0);
    
  //CURVAS GRUESAS
  noFill();
    stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0+size/2,0)
  
  //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)] )
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
   
    
  pop();
} //horizontal
function draw2Pattern4(x, y, cellDim) {
  push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
    
  //CURVAS GRUESAS
  noFill();
    stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0+size/2,0)
  
  
  //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
   
  pop();
} //vertical
function draw2Pattern5(x, y, cellDim) {
  push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(0);
    
  //CURVAS GRUESAS
  noFill();
    stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0,0)
 
 //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
  
  //CIRCULOS EN CRUZ
   fill(255,251,230);
ellipse(0+size/2,0,size/3,size/3);//DERECHO
  

  pop();
}//horizontal con punto
function draw2Pattern6(x, y, cellDim) {
  push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
    
  //CURVAS GRUESAS
  noFill();
    stroke(255,251,230);
  strokeWeight(size/3);
  strokeCap(ROUND);
  line(0-size/2,0,0,0)
 
 //CIRCULOS ESQUINAS
  noStroke();
  fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
   
  ellipse(size/2,size/2,size*2/3,size*2/3)
  ellipse(-size/2,-size/2,size*2/3,size*2/3)
  ellipse(-size/2,+size/2,size*2/3,size*2/3)
  ellipse(+size/2,-size/2,size*2/3,size*2/3)
  
  //CIRCULOS EN CRUZ
   fill(255,251,230);
ellipse(0+size/2,0,size/3,size/3);//DERECHO
  

  pop();
}//vertical con punto


function dotsPattern1(x, y, cellDim) {
  push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
  
  //CIRCULOS ESQUINAS
  
  if (colorDotFactor<0.5){
    noStroke();
  fill(0)
  }else{
    noStroke();
     fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
  }
    
  ellipse(size/2,size/2,size/3,size/3)
  ellipse(-size/2,-size/2,size/3,size/3)
  ellipse(-size/2,+size/2,size/3,size/3)
  ellipse(+size/2,-size/2,size/3,size/3)
   
   
  pop();
}//puntos de esquinas
function dotsPattern2(x, y, cellDim) {
  push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(HALF_PI);
  

let gl= size/10
  
  //CIRCULOS ESQUINAS
 
  stroke(0);
    strokeWeight(gl)
     noFill();
  let dotRnd=Math.floor();
  if(dotRnd<0.1){
     
  }else if(dotRnd<0.5){
    ellipse(size/2,size/2,size/3,size/3);
  ellipse(-size/2,-size/2,size/3,size/3);
  ellipse(-size/2,+size/2,size/3,size/3);
  ellipse(+size/2,-size/2,size/3,size/3);
  }else if(dotRnd<0.6){
    ellipse(size/2,size/2,size/3,size/3);
  ellipse(-size/2,-size/2,size/3,size/3);
  }else if(dotRnd<0.7){
    ellipse(-size/2,+size/2,size/3,size/3);
  ellipse(+size/2,-size/2,size/3,size/3);
  }else if(dotRnd<0.8){
    ellipse(size/2,size/2,size/3,size/3);
     ellipse(-size/2,+size/2,size/3,size/3);
  }else{
    ellipse(-size/2,-size/2,size/3,size/3);
     ellipse(+size/2,-size/2,size/3,size/3);
  }
  
   
   
  pop();
  
}//sin relleno
function dotsPattern3(x, y, cellDim) {
   push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(0);
  


  
  //CIRCULOS ESQUINAS
  
  if (colorDotFactor<0.5){
    noStroke();
  fill(0)
  }else{
    noStroke();
     fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
  }
    
 // ellipse(size/2,size/2,size/3,size/3)//DERECHA ABAJO
  //ellipse(-size/2,-size/2,size/3,size/3) //IZQUIERDA ARRIBA
  ellipse(-size/2,+size/2,size/3,size/3) //IZQUIREDA  ABAJO
  ellipse(+size/2,-size/2,size/3,size/3) //DERECHA ARRIBA
   
   
  pop();
} //diagonal 1
function dotsPattern4(x, y, cellDim) {
   push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(0);
  


  
  //CIRCULOS ESQUINAS
  
  if (colorDotFactor<0.5){
    noStroke();
  fill(0)
  }else{
    noStroke();
     fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
  }
    
  ellipse(size/2,size/2,size/3,size/3)//DERECHA ABAJO
  ellipse(-size/2,-size/2,size/3,size/3) //IZQUIERDA ARRIBA
 // ellipse(-size/2,+size/2,size/3,size/3) //IZQUIREDA  ABAJO
  //ellipse(+size/2,-size/2,size/3,size/3) //DERECHA ARRIBA
   
   
  pop();
} //diagonal 2
function dotsPattern5(x, y, cellDim) {
   push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(0);
  


  
  //CIRCULOS ESQUINAS
  
  if (colorDotFactor<0.5){
    noStroke();
  fill(0)
  }else{
    noStroke();
     fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
  }
    
 // ellipse(size/2,size/2,size/3,size/3)//DERECHA ABAJO
  ellipse(-size/2,-size/2,size/3,size/3) //IZQUIERDA ARRIBA
 // ellipse(-size/2,+size/2,size/3,size/3) //IZQUIREDA  ABAJO
  ellipse(+size/2,-size/2,size/3,size/3) //DERECHA ARRIBA
   
   
  pop();
}//arriba
function dotsPattern6(x, y, cellDim) {
   push();
  let size=cellDim;

 translate(x+size/2,y+size/2)
 rotate(0);
    
  //CIRCULOS ESQUINAS
  
  if (colorDotFactor<0.5){
    noStroke();
  fill(0)
  }else{
    noStroke();
     fill(paletaSeleccionada[Math.floor(R.random_dec() * paletaSeleccionada.length)])
  }
    
  ellipse(size/2,size/2,size/3,size/3)//DERECHA ABAJO
 // ellipse(-size/2,-size/2,size/3,size/3) //IZQUIERDA ARRIBA
  ellipse(-size/2,+size/2,size/3,size/3) //IZQUIREDA  ABAJO
  //ellipse(+size/2,-size/2,size/3,size/3) //DERECHA ARRIBA
   
   
  pop();
}//abajo








let backgroundFactorText;
if (backgroundFactor<0.3){
backgroundFactorText="Colorful";
}else{
  backgroundFactorText="Default";
}


let randomFondo1Text,randomFondo2Text,randomFondo3Text;
if(randomFondo1<0.3){
  randomFondo1Text="Colorful";
}else{
  randomFondo1Text="Default";
}


if(randomFondo2<0.3){
  randomFondo2Text="Colorful";
}else{
  randomFondo2Text="Default";
}


if(randomFondo3<0.3){
  randomFondo3Text="Colorful";
}else{
  randomFondo3Text="Default";
}

let colorDotFactorText;
if(colorDotFactor<0.5){
  colorDotFactorText="Black";
}else{
  colorDotFactorText="Colorful";
}

if (dotazar>=5){
  dotazar=5;
}