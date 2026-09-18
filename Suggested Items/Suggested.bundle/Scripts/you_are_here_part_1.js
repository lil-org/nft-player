var
  grid,
  totalLayers,
  chaosFactor,
  strokeWidth,
  backgroundColor,
  hereColor,
  signed = false,
  strokeColor;

var
  currentLayer = 1,
  gridArray = [],
  here,
  hereSegment,
  whereAreYou = true,
  R,
  posNeg,
  whichSig,
  hereColorBlockType1,
  hereColorBlockType2,
  hereColorBlockType3;

var jsonInstructions = {}
jsonInstructions.layers = []

// seed
const hash = tokenData.hash;
const invocation = Number(tokenData.tokenId) % 1_000_000;

function setup() {
  createCanvas(1000,1000);
  pixelDensity(2.5);
  colorMode(HSB, 360, 100, 100);
  
  // resize canvas element in html
  var canvasElement = document.querySelector("canvas");
  canvasElement.style.cssText = '';
  if (canvasElement.parentElement.offsetWidth >= canvasElement.parentElement.offsetHeight) {
    canvasElement.style.width = "auto";
    canvasElement.style.height = "100%";
  } else {
    canvasElement.style.width = "100%";
    canvasElement.style.height = "auto";
  }

  R = new Random();
    
  // number of grid cells
  grid = Math.floor(R.random_num(3,11));
  
  // layers
  totalLayers = Math.floor(R.random_num(1,21));
  
  // chaos number
  chaosFactor = Math.floor(R.random_num(-6,6));
  
  //styling
  strokeWidth = R.random_num(4,7.5);
  jsonInstructions.strokeWidth = strokeWidth;
  
  // colorway
  var colorway = floor(R.random_num(1,8)); // 1 - 7
  if (colorway == 1) { // white
    backgroundColor = "rgba(248,248,248,1)";
    strokeColor = 0;
    hereColor = R.random_num(300,380);
    if (hereColor > 360) { hereColor -= 360; }
  } else if (colorway == 2) { // blue
    backgroundColor = "HSB(220,55%,84%)";
    strokeColor = 255;
    hereColor = R.random_num(0,43);
    if (hereColor > 360) { hereColor -= 360; }
  } else if (colorway == 3) { // orange
    backgroundColor = "HSB(32,62%,100%)";
    strokeColor = 255;
    hereColor = R.random_num(180,280);
    if (hereColor > 360) { hereColor -= 360; }
  } else if (colorway == 4) { // green
    backgroundColor = "HSB(140,30%,85%)";
    strokeColor = 255;
    hereColor = R.random_num(0,54);
    if (hereColor > 360) { hereColor -= 360; }
  } else if (colorway == 5) { // white with blue/purple
    backgroundColor = "rgba(248,248,248,1)";
    strokeColor = 0;
    hereColor = R.random_num(180,280);
    if (hereColor > 360) { hereColor -= 360; }
  } else if (colorway == 6) { // black
    backgroundColor = "HSB(0,0%,13%)";
    strokeColor = 255;
    hereColor = R.random_num(155,245);
    if (hereColor > 360) { hereColor -= 360; }
  } else if (colorway == 7) { // yellow
    backgroundColor = "HSB(50,46%,100%)";
    strokeColor = 0;
    hereColor = R.random_num(194,342);
    if (hereColor > 360) { hereColor -= 360; }
  }

  // here cell
  here = Math.floor(R.random_num(1,grid*grid+1));
  posNeg = R.random_num(-1,1);
  hereSegment = Math.floor(R.random_num(1,7));

  // signature
  if (R.random_num(0,1) > .96) {
    signed = true;
    whichSig = R.random_num(0,1);
  }
  
  // here color blocks
  hereColorBlockType1 = R.random_num(0,1);
  hereColorBlockType2 = R.random_num(0,1);
  hereColorBlockType3 = R.random_num(0,1);

  // set up grid
  for (var i = 0; i < grid*grid; i++) {
    gridArray[i] = R.random_num(0,1);
  }
  
  // create shape
  shapePoint1x = R.random_num(0,1),shapePoint1y = R.random_num(0,1),
  shapePoint2x = R.random_num(0,1),shapePoint2y = R.random_num(0,1),
  shapePoint3x = R.random_num(0,1),shapePoint3y = R.random_num(0,1),
  shapePoint4x = R.random_num(0,1),shapePoint4y = R.random_num(0,1),
  shapePoint5x = R.random_num(0,1),shapePoint5y = R.random_num(0,1);
  
  jsonInstructions.definitions = {};

  jsonInstructions.definitions.shape = [
    {"x":0,"y":0},
    {"x":shapePoint1x,"y":shapePoint1y},
    {"x":shapePoint2x,"y":shapePoint2y},
    {"x":shapePoint3x,"y":shapePoint3y},
    {"x":shapePoint4x,"y":shapePoint4y},
    {"x":shapePoint5x,"y":shapePoint5y},
    {"x":1,"y":1}
  ]

  jsonInstructions.definitions.NWSEline = [
    {"x":0,"y":0},
    {"x":1,"y":1}
  ]

  jsonInstructions.definitions.NWSEline_here = [
    {"x":.5,"y":.5},
    {"x":1,"y":1}
  ]

  jsonInstructions.definitions.SWNEline = [
    {"x":0,"y":1},
    {"x":1,"y":0}
  ]

  jsonInstructions.definitions.SWNEline_here = [
    {"x":0,"y":1},
    {"x":.5,"y":.5}
  ]

  jsonInstructions.definitions.circle = [
    {"x":.5,"y":.5,"d":.6}
  ]
  
  // background
  background(backgroundColor);

  // match background color in body element of html
  var backgroundColor_hex = backgroundColor.replace("HSB(","").replace(")","").replaceAll("%","").split(",");
  canvasElement.parentElement.style.backgroundColor = backgroundColor.indexOf("rgb") > -1 ? backgroundColor : hsbToHex(backgroundColor_hex[0],backgroundColor_hex[1],backgroundColor_hex[2]);

  // RAINBOW/GOLD //
  /*
  strokeColor = "hsb(50,96%,71%)";
  drawRainbowGradient(width,height);
  */
  // END RAINBOW/GOLD
  
  this.focus(); // focus so key listener works right away
  
  var hereColorBlockRandom = R.random_num(0,1);
  if (hereColorBlockRandom > .5) { hereColorBlock(hereColor,hereColorBlockType1); }
  
}

// RAINBOW
/*function drawRainbowGradient(w, h) {
  for (let y = 0; y < h; y++) {
    // Map the current x position to a hue value between 0 and 360
    //const hueValue = map(x, 0, w, 0, 360);
    stroke(y/2%360, 100, 100);
    line(0, y, w, y);
  }
}*/
// END RAINBOW

function draw() {
  
  // loop or stop
  if (currentLayer > totalLayers) {
  
    // final
    var hereColorBlockRandom = R.random_num(0,1);
    if (hereColorBlockRandom > .5) { hereColorBlock(hereColor,hereColorBlockType2,true); }
    hereColorBlockRandom = R.random_num(0,1);
    if (hereColorBlockRandom > .75) { hereColorBlock(hereColor,hereColorBlockType3,true); }
    if (signed) { signWork(); }
    noLoop();
  
  } else {

    drawLayer();
    currentLayer += 1;
    
  }
}

function keyTyped() {
  
  if (key === 'i') {
    saveJSON(jsonInstructions, 'instructions-'+invocation+'.json');
  }
  
  if (key === 's') {
    save('you-are-here-'+invocation+'.png');
  }
  
}

function drawLayer() {
  
  // univeral offset for this layer
  var
    offsetX = chaosFactor*R.random_num(1,2),
    offsetY = chaosFactor*R.random_num(1,2);
  
  // color for this layer
  var thisColor = color(0,0,strokeColor);
  var thisAlpha = R.random_num(.45,.9);
  thisColor.setAlpha(thisAlpha);
  stroke(thisColor);
  strokeCap(ROUND);
  strokeWeight(strokeWidth);
  noFill();  
  
  // instructions
  var layerInstructions = {}
  layerInstructions.layer = currentLayer;
  layerInstructions.alpha = thisAlpha;
  layerInstructions.offsetX = offsetX;
  layerInstructions.offsetY = offsetY;
  layerInstructions.rows = [];
  
  var gridLoopX = 1;
  var gridLoopY = 0;
  for (var gridLoop = 0; gridLoop < (grid*grid); gridLoop++) {

    if (gridLoop%grid < 1) {
      gridLoopY++;
      gridLoopX = 1;
      
      //instructions
      if (!rowInstructions) {
        var rowInstructions = {}  
      } else {
        layerInstructions.rows.push(rowInstructions);
        rowInstructions = {}
      }
      rowInstructions.row = gridLoopY;
      rowInstructions.columns = [];
      if (!columnInstructions) {
        var columnInstructions = {}
      } else {
        columnInstructions = {}
      }
      columnInstructions.column = gridLoopX;
      // end instructions
    } else {
      gridLoopX++;
      
      // instructions
      if (!columnInstructions) {
        var columnInstructions = {}
      } else {
        columnInstructions = {}
      }
      columnInstructions.column = gridLoopX;
      // end instructions
    }

    // you are here color
    var forcePrint = false;
    var hereCell = false;
    if (gridLoop+1 === here && currentLayer == totalLayers && whereAreYou) {

      hereColor += (chaosFactor*posNeg);

      var hereColorColor = color(hereColor,100,100);
      hereColorColor.setAlpha(1);
      stroke(hereColorColor);
      strokeCap(SQUARE);
      strokeWeight(strokeWidth*2);
      whereAreYou = false;
      forcePrint = true;
      hereCell = true;

      columnInstructions.here = true;
    }
    
    var printThisLayer = R.random_num(0,1);
    if (forcePrint || currentLayer < 2 || printThisLayer > .9) { // print or skip
      
      if (gridArray[gridLoop] > .9) { // CIRCLE
        
        ellipse((width/(grid+1)*gridLoopX)+offsetX,(height/(grid+1)*gridLoopY)+offsetY,width/(grid+1)*.6,width/(grid+1)*.6);
        
        columnInstructions.type = "circle";

      } else if (gridArray[gridLoop] > .25) { // LINE
      
        var
          centerCellX = (width/(grid+1)*gridLoopX)+offsetX,
          centerCellY = (height/(grid+1)*gridLoopY)+offsetY,
          cellSize = width/(grid+1);
  
        if (hereCell) {
          if (gridArray[gridLoop] > .625) {
            line(centerCellX,centerCellY,centerCellX+(cellSize/2),centerCellY+(cellSize/2));
            columnInstructions.type = "NW - SE line";
          } else {
            line(centerCellX,centerCellY,centerCellX-(cellSize/2),centerCellY+(cellSize/2));
            columnInstructions.type = "SW - NE line";
          }
        } else {
          if (gridArray[gridLoop] > .625) {

            // prevent x shape in final output
            if (currentLayer == 1 && (
                (gridLoopX > 1 && rowInstructions.columns[(gridLoopX - 1)-1].type == "SW - NE line")
                && (gridLoopY > 1 && layerInstructions.rows[(gridLoopY - 1)-1].columns[gridLoopX - 1].type == "SW - NE line")
                && ((gridLoopY > 1 && layerInstructions.rows[(gridLoopY - 1)-1].columns[(gridLoopX - 1)-1].type == "NW - SE line")
                  || (gridLoopY > 1 && layerInstructions.rows[(gridLoopY - 1)-1].columns[(gridLoopX - 1)-1].type == "Shape"))
              ) || (currentLayer > 1 && (
                (gridLoopX > 1 && jsonInstructions.layers[0].rows[gridLoopY - 1].columns[(gridLoopX - 1)-1].type == "SW - NE line")
                && (gridLoopY > 1 && jsonInstructions.layers[0].rows[(gridLoopY - 1)-1].columns[gridLoopX - 1].type == "SW - NE line")
                && ((gridLoopY > 1 && jsonInstructions.layers[0].rows[(gridLoopY - 1)-1].columns[(gridLoopX - 1)-1].type == "NW - SE line")
                  || (gridLoopY > 1 && jsonInstructions.layers[0].rows[(gridLoopY - 1)-1].columns[(gridLoopX - 1)-1].type == "Shape"))
              ))
            ) {
              // don't draw NW - SE line
              line(centerCellX+(cellSize/2),centerCellY-(cellSize/2),centerCellX-(cellSize/2),centerCellY+(cellSize/2));
              columnInstructions.type = "SW - NE line";
            } else {
              line(centerCellX-(cellSize/2),centerCellY-(cellSize/2),centerCellX+(cellSize/2),centerCellY+(cellSize/2));
              columnInstructions.type = "NW - SE line";
            }
          } else {
            line(centerCellX+(cellSize/2),centerCellY-(cellSize/2),centerCellX-(cellSize/2),centerCellY+(cellSize/2));
            columnInstructions.type = "SW - NE line";
          }
        }
        
      } else { // SHAPE

        var
          centerCellX = (width/(grid+1)*gridLoopX)+offsetX,
          centerCellY = (height/(grid+1)*gridLoopY)+offsetY,
          cellSize = width/(grid+1);
  
        var
          cellStartX = centerCellX-(cellSize*.5),
          cellEndX = centerCellX+(cellSize*.5),
          cellStartY = centerCellY-(cellSize*.5),
          cellEndY = centerCellY+(cellSize*.5);

        if (currentLayer == 1 && (
            (gridLoopX > 1 && rowInstructions.columns[(gridLoopX - 1)-1].type == "SW - NE line")
            && (gridLoopY > 1 && layerInstructions.rows[(gridLoopY - 1)-1].columns[gridLoopX - 1].type == "SW - NE line")
            && ((gridLoopY > 1 && layerInstructions.rows[(gridLoopY - 1)-1].columns[(gridLoopX - 1)-1].type == "NW - SE line")
              || (gridLoopY > 1 && layerInstructions.rows[(gridLoopY - 1)-1].columns[(gridLoopX - 1)-1].type == "Shape"))
          ) || (currentLayer > 1 && (
            (gridLoopX > 1 && jsonInstructions.layers[0].rows[gridLoopY - 1].columns[(gridLoopX - 1)-1].type == "SW - NE line")
            && (gridLoopY > 1 && jsonInstructions.layers[0].rows[(gridLoopY - 1)-1].columns[gridLoopX - 1].type == "SW - NE line")
            && ((gridLoopY > 1 && jsonInstructions.layers[0].rows[(gridLoopY - 1)-1].columns[(gridLoopX - 1)-1].type == "NW - SE line")
              || (gridLoopY > 1 && jsonInstructions.layers[0].rows[(gridLoopY - 1)-1].columns[(gridLoopX - 1)-1].type == "Shape"))
          ))
        ) {
          // don't draw shape
          if (hereCell) {
            line(centerCellX,centerCellY,centerCellX-(cellSize/2),centerCellY+(cellSize/2));
          } else {
            line(centerCellX+(cellSize/2),centerCellY-(cellSize/2),centerCellX-(cellSize/2),centerCellY+(cellSize/2));
          }
          columnInstructions.type = "SW - NE line";
        } else {        
          drawShape(cellStartX,cellEndX,cellStartY,cellEndY,hereCell,thisColor,hereColorColor);
          columnInstructions.type = "Shape";
          if (columnInstructions.here) { columnInstructions.hereSegment = hereSegment; }
        }

      }
      strokeWeight(strokeWidth);
      
      if (!columnInstructions.type) { columnInstructions.type = "None"; }
      
    }
    strokeCap(ROUND);
    
    // splatter
    noiseSeed(invocation);
    if (R.random_num(0,1) > .96) {
      for(var i=0;i<2000;i++) {
        noStroke();
        thisColor.setAlpha(noise(i)-.25);
        fill(thisColor);
        ellipse(R.random_num(0,width),R.random_num(0,height),1,1);
      }
    }
    // reset fill and stroke
    stroke(thisColor);
    thisColor.setAlpha(thisAlpha);
    noFill();
    
    rowInstructions.columns.push(columnInstructions);
    
    if (gridLoop == (grid*grid) - 1) { layerInstructions.rows.push(rowInstructions); } // add last row
    
  }
  
  // instructions
  jsonInstructions.layers.push(layerInstructions);
   
}

// drawShape function - draw a random shape with 5 lines
var
  shapePoint1x,
  shapePoint2x,
  shapePoint3x,
  shapePoint4x,
  shapePoint5x;
function drawShape(startX,endX,startY,endY,hereCell=false,thisColor,hereColor) {

  var
    shapePoint1xx = startX+shapePoint1x*(endX-startX),
    shapePoint1yy = startY+shapePoint1y*(endY-startY),
    shapePoint2xx = startX+shapePoint2x*(endX-startX),
    shapePoint2yy = startY+shapePoint2y*(endY-startY),
    shapePoint3xx = startX+shapePoint3x*(endX-startX),
    shapePoint3yy = startY+shapePoint3y*(endY-startY),
    shapePoint4xx = startX+shapePoint4x*(endX-startX),
    shapePoint4yy = startY+shapePoint4y*(endY-startY),
    shapePoint5xx = startX+shapePoint5x*(endX-startX),
    shapePoint5yy = startY+shapePoint5y*(endY-startY);
  
  var
    shapePoint1xx_inverted = startX+shapePoint1y*(endX-startX),
    shapePoint1yy_inverted = startY+shapePoint1x*(endY-startY),
    shapePoint2xx_inverted = startX+shapePoint2y*(endX-startX),
    shapePoint2yy_inverted = startY+shapePoint2x*(endY-startY),
    shapePoint3xx_inverted = startX+shapePoint3y*(endX-startX),
    shapePoint3yy_inverted = startY+shapePoint3x*(endY-startY),
    shapePoint4xx_inverted = startX+shapePoint4y*(endX-startX),
    shapePoint4yy_inverted = startY+shapePoint4x*(endY-startY),
    shapePoint5xx_inverted = startX+shapePoint5y*(endX-startX),
    shapePoint5yy_inverted = startY+shapePoint5x*(endY-startY);

  if (hereCell) {
    var colorLine = hereSegment;
  }
  var inverted = R.random_num(0,1);
  if (inverted > .1) {
    if (hereCell && colorLine === 1) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(startX,startY,shapePoint1xx,shapePoint1yy);
    if (hereCell && colorLine === 2) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint1xx,shapePoint1yy,shapePoint2xx,shapePoint2yy);
    if (hereCell && colorLine === 3) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint2xx,shapePoint2yy,shapePoint3xx,shapePoint3yy);
    if (hereCell && colorLine === 4) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint3xx,shapePoint3yy,shapePoint4xx,shapePoint4yy);
    if (hereCell && colorLine === 5) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint4xx,shapePoint4yy,shapePoint5xx,shapePoint5yy);
    if (hereCell && colorLine === 6) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint5xx,shapePoint5yy,endX,endY);
  } else { // inverted <= .1
    if (hereCell && colorLine === 1) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(startX,startY,shapePoint1xx_inverted,shapePoint1yy_inverted);
    if (hereCell && colorLine === 2) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint1xx_inverted,shapePoint1yy_inverted,shapePoint2xx_inverted,shapePoint2yy_inverted);
    if (hereCell && colorLine === 3) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint2xx_inverted,shapePoint2yy_inverted,shapePoint3xx_inverted,shapePoint3yy_inverted);
    if (hereCell && colorLine === 4) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint3xx_inverted,shapePoint3yy_inverted,shapePoint4xx_inverted,shapePoint4yy_inverted);
    if (hereCell && colorLine === 5) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint4xx_inverted,shapePoint4yy_inverted,shapePoint5xx_inverted,shapePoint5yy_inverted);
    if (hereCell && colorLine === 6) { stroke(hereColor);strokeWeight(strokeWidth*2);strokeCap(SQUARE); } else { stroke(thisColor);strokeWeight(strokeWidth);strokeCap(ROUND); }
    line(shapePoint5xx_inverted,shapePoint5yy_inverted,endX,endY);
  }
  
}

// here color block
function hereColorBlock(hereColor,hereColorBlockType,onTop=false) {
  noStroke();
  var hereColor = color(hereColor,100,100);
  hereColor.setAlpha(.0625);
  fill(hereColor);

  if (hereColorBlockType > .8) { // left side full height
    
    rect(0,0,R.random_num(10,width*.5),height);
  
  } else if (hereColorBlockType > .6) { // lines
    
    var hcbs = R.random_num(0,width*.5);
    var hcbw = R.random_num(width*.25,width*.5);
    for (var hcbi = hcbs; hcbi<hcbw; hcbi++) {
      if (R.random_num(0,1) >.5) {
        rect(hcbi,0,1,height);
      }
    }
  
  } else if (hereColorBlockType > .4) { // circle
    
    var ellipseSize = R.random_num(120,420);
    ellipse(width*.5,height*.5,width-ellipseSize,height-ellipseSize);
  
  } else if (hereColorBlockType > .2) { // grid of circles
    
    if (R.random_num(0,1) > .9 && !onTop) { fill(0); } // chance for all black dots

    var gridLoopX = 1;
    var gridLoopY = 0;
    for (var gridLoop = 0; gridLoop < (grid*grid); gridLoop++) {

      if (gridLoop%grid < 1) {
        gridLoopY++;
        gridLoopX = 1;
      } else {
        gridLoopX++;
      }
      
      var
          centerCellX = (width/(grid+1)*gridLoopX),
          centerCellY = (height/(grid+1)*gridLoopY),
          cellSize = width/(grid+1);
      
      ellipse(centerCellX,centerCellY,40,40);
    }
  
  } else if (hereColorBlockType > .1) { // triangle

    beginShape();
    vertex(width,0);
    vertex(width*.5,height*.5);
    vertex(width,height);
    endShape();

  } else if (hereColorBlockType > .05) { // triangles grid

    
    var gridLoopX = 1;
    var gridLoopY = 0;
    for (var gridLoop = 0; gridLoop < (grid*grid); gridLoop++) {

      if (gridLoop%grid < 1) {
        gridLoopY++;
        gridLoopX = 1;
      } else {
        gridLoopX++;
      }
      
      var
          centerCellX = (width/(grid+1)*gridLoopX),
          centerCellY = (height/(grid+1)*gridLoopY),
          cellSize = width/(grid+1);

      beginShape();
      vertex(centerCellX-(cellSize*.5),centerCellY+(cellSize*.5));
      vertex(centerCellX+(cellSize*.5),centerCellY-(cellSize*.5));
      vertex(centerCellX+(cellSize*.5),centerCellY+(cellSize*.5));
      endShape(); 
      
    }

  } else if (hereColorBlockType > .025) { // single grid-style triangle

    beginShape();
    vertex(0,height);
    vertex(width,0);
    vertex(width,height);
    endShape();

  } else if (hereColorBlockType > .0125) { // lines from top

    for (var hcbi = 0; hcbi<width; hcbi++) {
      rect(hcbi,0,1,R.random_num(0,hcbi));
    }

  } else { // waves

    var wavesNum = R.random_num(2,8);
    for (var hcbi = 0; hcbi<wavesNum; hcbi++) {
      beginShape();
      vertex(0,height);
      vertex(width,height);
      vertex(width,height*(R.random_num(.5,1)));
      vertex(0,height*(R.random_num(.5,1)));
      endShape();
    }

  }
  
}

// signature
function signWork() {

  //var whichSig = R.random_num(0,1);
  if (whichSig > .5) {
    
    // truedrew signature
    var signature = createGraphics(156,68);

    signature.scale(.45);
    signature.noFill();

    signature.stroke("hsb(50,96%,71%)");//("rgba(127,127,127,1)");
    signature.strokeWeight(1.8);
    signature.strokeCap(ROUND);
    signature.beginShape();
    signature.vertex(1.753,30.22);
    signature.bezierVertex(0.7609999999999999,29.557,3.891,29.159,4.973,28.657);
    signature.bezierVertex(10.327,26.174,15.646,23.613,20.977,21.081);
    signature.bezierVertex(35.73,14.075,50.841,7.601,66.192,2);
    signature.endShape();
    
    signature.strokeCap(ROUND);
    signature.beginShape();
    signature.vertex(34.329,14.074);
    signature.bezierVertex(34.329,-2.426,33.266,47.074,31.772000000000002,63.504);
    signature.vertex(36.033,34.528);
    signature.bezierVertex(36.008,34.525,38.453,60.053,36.033,64.168);
    signature.bezierVertex(30.630000000000003,73.35300000000001,39.636,40.89900000000001,48.249,34.62200000000001);
    signature.bezierVertex(53.397000000000006,30.870000000000008,50.335,39.123000000000005,48.817,40.967000000000006);
    signature.bezierVertex(46.592,43.668000000000006,43.217,58.751000000000005,49.29,53.89300000000001);
    signature.bezierVertex(52.918,50.99000000000001,54.178,45.78200000000001,55.161,41.48800000000001);
    signature.bezierVertex(57.086,33.09100000000001,56.071,42.151,59.185,41.401);
    signature.bezierVertex(60.392,40.254000000000005,67.548,42.254000000000005,68.087,43.622);
    signature.bezierVertex(68.685,47.52,60.787000000000006,48.546,59.47,44.992);
    signature.bezierVertex(57.708,48.349999999999994,59.321999999999996,50.199999999999996,59.089999999999996,46.089);
    signature.bezierVertex(58.95399999999999,54.554,55.080999999999996,52.434,53.31399999999999,43.311);
    signature.bezierVertex(50.998999999999995,36.362,60.36899999999999,36.256,62.120999999999995,43);
    signature.bezierVertex(67.253,49.2,65.698,52.138,65.246,NaN);
    signature.bezierVertex(159.611,NaN,NaN,NaN,68.31299999999999,NaN);
    signature.bezierVertex(82.88099999999999,NaN,86.21099999999998,NaN,79.97999999999999,NaN);
    signature.bezierVertex(102.957,NaN,114.54399999999998,NaN,NaN,NaN);
    signature.endShape();
    
    signature.strokeCap(ROUND);
    signature.beginShape();
    signature.vertex(82.907,25.153);
    signature.bezierVertex(78.11,22.34,72.71,20.18,79.64,16.11);
    signature.bezierVertex(89.952,10.053999999999998,105.218,7.199999999999999,115.86099999999999,13.979);
    signature.bezierVertex(139.862,29.264,98.74399999999999,61.619,83.19099999999999,64.83);
    signature.bezierVertex(77.41899999999998,66.02199999999999,90.57699999999998,49.16,91.19299999999998,48.306);
    signature.bezierVertex(92.64899999999999,46.288999999999994,107.64599999999999,22.086,111.31599999999999,26.951999999999998);
    signature.bezierVertex(115.99399999999999,33.156,111.29399999999998,47.786,109.84799999999998,54.462);
    signature.bezierVertex(108.05499999999998,62.738,112.82499999999999,51.565000000000005,114.96099999999998,49.063);
    signature.bezierVertex(117.54699999999998,46.036,124.05399999999999,42.809000000000005,125.33099999999999,38.978);
    signature.bezierVertex(126.48799999999999,35.507000000000005,120.17999999999999,44.773,119.69599999999998,48.401);
    signature.bezierVertex(119.27299999999998,51.577000000000005,120.86099999999999,55.291000000000004,124.00499999999998,51.668000000000006);
    signature.bezierVertex(124.85599999999998,50.68800000000001,129.38899999999998,42.507000000000005,129.78099999999998,44.566);
    signature.bezierVertex(130.676,49.262,133.96399999999997,60.902,137.40399999999997,50.294000000000004);
    signature.bezierVertex(138.55599999999995,46.74400000000001,137.80799999999996,45.961000000000006,141.42899999999997,45.418000000000006);
    signature.bezierVertex(145.79099999999997,44.763000000000005,150.20099999999996,43.910000000000004,154.49699999999999,43.050000000000004);
    signature.endShape();

    image(signature, width-(156*.5), height-(68*.6));
    
  } else {
    
    // drew thomas signature
    var signature = createGraphics(111,72);
    
    signature.scale(.5);
    signature.noFill();
    
    signature.stroke("hsb(50,96%,71%)");//("rgba(127,127,127,1)");
    signature.strokeWeight(2)
    signature.strokeCap(ROUND);
    signature.beginShape();
    signature.vertex(2.005,62.7);
    signature.bezierVertex(2.145,52.651,3.8869999999999996,42.260000000000005,6.227,32.533);
    signature.bezierVertex(8.451,23.293,11.102,13.187000000000001,16.505000000000003,5.200000000000003);
    signature.bezierVertex(21.070000000000004,-1.5479999999999974,22.321,3.7100000000000026,22.783,9.811000000000003);
    signature.bezierVertex(23.978,25.584000000000003,23.463,42.387,21.227,58.033);
    signature.bezierVertex(20.953,59.953,18.017,71.85300000000001,18.172,69.7);
    signature.bezierVertex(18.344,67.283,25.375,42.256,30.005000000000003,50.589);
    signature.bezierVertex(30.741000000000003,51.914,35.038000000000004,63.719,37.06,56.978);
    signature.bezierVertex(38.765,51.297000000000004,40.092,51.902,43.45,54.7);
    signature.bezierVertex(44.955000000000005,55.955000000000005,56.973,52.412000000000006,58.45,51.978);
    signature.bezierVertex(75.28200000000001,47.028,91.44,44.145,109.005,44.145);
    signature.endShape();
    
    image(signature, width-(111*.6), height-(72*.6));

  }

}

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

function hsbToHex(h, s, b) {
    s /= 100;
    b /= 100;

    let k = (n) => (n + h / 60) % 6;
    let f = (n) => b - b * s * Math.max(Math.min(k(n), 4 - k(n), 1), 0);

    let r = Math.round(f(5) * 255);
    let g = Math.round(f(3) * 255);
    let bb = Math.round(f(1) * 255);

    return "#" + [r, g, bb].map(x => x.toString(16).padStart(2, '0')).join('');
}