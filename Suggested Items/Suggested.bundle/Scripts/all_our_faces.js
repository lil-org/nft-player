// tokenData.hash="0x990226aaee5fd315cd31f3bb70b821d484ebf9c1f837000f163f33cb941a4d91"

const hashPairs = [];
for (let j = 0; j < 32; j++) {
  hashPairs.push(tokenData.hash.slice(2 + (j * 2), 4 + (j * 2)));
}

//string of 64 character divided in 32 pairs
const dcP = hashPairs.map(x => {
	//convert to decimal	
	return parseInt(x, 16);
});

const seed = parseInt(tokenData.hash.slice(2, 10), 16);

class Random {
    constructor() {
      this.useA = false;
      let sfc32 = function (uint128Hex) {
        let a = parseInt(uint128Hex.substring(0, 8), 16);
        let b = parseInt(uint128Hex.substring(8, 16), 16);
        let c = parseInt(uint128Hex.substring(16, 24), 16);
        let d = parseInt(uint128Hex.substring(24, 32), 16);
        return function () {
          a |= 0; b |= 0; c |= 0; d |= 0;
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
      this.prngA = new sfc32(tokenData.hash.substring(2, 32));
      // seed prngB with second half of tokenData.hash
      this.prngB = new sfc32(tokenData.hash.substring(34, 64));
      for (let i = 0; i < 1e6; i += 2) {
        this.prngA();
        this.prngB();
      }
    }
    // random number between 0 (inclusive) and 1 (exclusive)
    r_dec() {
      this.useA = !this.useA;
      return this.useA ? this.prngA() : this.prngB();
    }
    // random number between a (inclusive) and b (exclusive)
    r_num(a, b) {
      return a + (b - a) * this.r_dec();
    }
    // random integer between a (inclusive) and b (inclusive)
    // requires a < b for proper probability distribution
    r_int(a, b) {
      return Math.floor(this.r_num(a, b + 1));
    }
    // random boolean with p as percent liklihood of true
    r_bool(p) {
      return this.r_dec() < p;
    }
    // random value in an array of items
    r_choice(list) {
      return list[this.r_int(0,list.length - 1)];
    }
  }
  
let R = new Random(seed);

let chosenPalette = [];
let palettes = [];
let rectangleCount = 0;

// Define the minimum area for splitting rectangles
// The leastArea variable determines the minimum area required for a rectangle to be split.
// If the area of a rectangle is smaller than leastArea, the recursion stops and the shapes are drawn.
const leastArea = R.r_int(1, 60)*32;

palettes = [
    {"name": "Bogota", "colors": ["#ffffff", "#000000", "#ff87ff", "#ec00ff", "#aabbe2", "#0000ff", "#ff8d29", "#468500", "#cee9c8", "#3511d6", "#7a2ada", "#ff0000", "#c6ec26", "#ffcd38", "#f9dac3"]},
    {"name": "Tokyo", "colors": ["#ffcd38", "#7a2bdb", "#29369f", "#ff88fe", "#000000"]},
    {"name": "New York", "colors": ["#000000", "#ffffff"]},
    {"name": "Moscow", "colors": ["#ff0000", "#000000"]},
    {"name": "Cairo", "colors": ["#ff0000", "#ff8d29", "#ffffff", "#000000"]},
    {"name": "Berlin", "colors": ["#000000", "#848484", "#bbbbbb", "#ffffff"]},
    {"name": "Mumbai", "colors": ["#ffcd38", "#ff88fe", "#ff0000"]},
    {"name": "Sydney", "colors": ["#ff88fe", "#0000ff", "#ffffff", "#ffcd38"]},
    {"name": "Rio de Janeiro", "colors": ["#ff88fe", "#0000ff", "#f66a04", "#ffcd38"]},
    {"name": "Venice", "colors": ["#ff0000", "#aabbe2", "#ffffff", "#3511d6"]},
    {"name": "Bangkok", "colors": ["#ff87ff", "#7a2ada", "#000000", "#ec00ff"]},
    {"name": "Los Angeles", "colors": ["#c6ec26", "#000000", "#ffffff", "#ffcd38"]},
    {"name": "Vienna", "colors": ["#ff87ff", "#ffcd38", "#ff0000", "#ffffff"]},
    {"name": "Helsinki", "colors": ["#3511d6", "#aabbe2", "#000000", "#ffffff"]},
    {"name": "Barcelona", "colors": ["#F3F2DA", "#4E8D7C", "#2535a5", "#EA97AD"]},
    {"name": "Stockholm", "colors": ["#ffffff", "#bbbbbb", "#D2E603", "#EFF48E"]},
    {"name": "Budapest", "colors": ["#000000", "#ffcd38", "#aabbe2", "#ffffff"]},
    {"name": "Shanghai", "colors": ["#000000", "#ff0000", "#ff87ff", "#0000ff"]},
    {"name": "Dubai", "colors": ["#ffcd38", "#0000ff", "#000000", "#ff8d29"]},
    {"name": "London", "colors": ["#ff87ff", "#468500", "#000000", "#ffffff"]},
    {"name": "Beijing", "colors": ["#000000", "#ffcd38", "#000000", "#ffffff"]},
    {"name": "Seoul", "colors": ["#c6ec26", "#3511d6", "#aabbde"]},
    {"name": "Istanbul", "colors": ["#f9dac3", "#ff0000", "#000000", "#ffffff"]},
    {"name": "Lisbon", "colors": ["#ffffff", "#ec00ff", "#468500"]},
    {"name": "Athens", "colors": ["#ff0000", "#ffcd38", "#ffffff", "#0000ff", "#468500"]},
    {"name": "Rome", "colors": ["#3511d6", "#eb87ff", "#ffcd38", "#aabbde", "#ff0000"]},
    {"name": "Paris", "colors": ["#3511d6", "#eb87ff", "#ffcd38", "#aabbde"]},
    {"name": "Miami", "colors": ["#ffcd38", "#e998a7", "#e45c63", "#f3bcc4", "#9aad8d"]},
    {"name": "San Francisco", "colors": ["#4b9889", "#11927a", "#f4cb85", "#385c55", "#efe5c1"]},
    {"name": "Melbourne", "colors": ["#7e4f83", "#969cd2", "#e8b8ce", "#f4c0ad", "#d388c5", "#ef998c"]},
    {"name": "Montreal", "colors": ["#6c81c2", "#f3b8d2", "#b59dba", "#ffcd38", "#ffffff", "#e76046"]},
    {"name": "Madrid", "colors": ["#e3923d", "#915062", "#5c372b", "#e36448", "#d7c787", "#dd83a5", "#324378", "#ffffff"]},
    {"name": "Amsterdam", "colors": ["#398257", "#ffcd38", "#ffffff", "#edb978", "#dd7f6e", "#3b529a"]},
    {"name": "Cancun", "colors": ["#ffffff", "#f3b5e1", "#ef986c", "#d1c65e", "#766662", "#91a07a", "#f3b440", "#ffcd38", "#b3dad2"]},
    {"name": "Kyoto", "colors": ["#ac5e9d", "#54104e", "#c4a5bd", "#ffffff", "#ad3275", "#ecb0a4", "#cf513f", "#ff0000"]},
    {"name": "Dublin", "colors": ["#232f6d", "#bf9dc5", "#696da5", "#405c9b"]},
    {"name": "Oslo", "colors": ["#405c9b", "#f8d886", "#3c878a", "#eec78b"]},
    {"name": "Brussels", "colors": ["#474883", "#c53432", "#000000", "#ffffff", "#e5bfd4"]},
    {"name": "Mexico City", "colors": ["#e8723f", "#b53e73", "#ffcd38", "#9ec9d2", "#408e5a", "#dea9b7", "#2e68bb", "#34489e"]}

]

let rectang = [];
let paleta = palettes[dcP[0]%palettes.length];
let useMargin = dcP[1]/255>0.3?true:false;
let applyTransformation = dcP[2]%2>0?true:false;
let strokeOutlineColor = (dcP[3] % 2 === 0) ? "#000000" : "#ffffff";
let shouldValueChange = dcP[4]%2>0?true:false; //shouldValueChange helps to determine if a shape is painted consitenly
let consistentShapeValue = shouldValueChange ? 0 : R.r_int(1,7);
let globalRotation = dcP[6] % 4 - 2;
let modstrokeWeightValue = dcP[3] % 5;
let calculatedStrokeWeight; // Declare variable to store the stroke weight

if (modstrokeWeightValue == 0) {
    calculatedStrokeWeight = 3 * R.r_num(0.9, 1.1);
} else if (modstrokeWeightValue == 1) {
    calculatedStrokeWeight = 4 * R.r_num(0.85, 1.15);
} else if (modstrokeWeightValue == 2) {
    calculatedStrokeWeight = 5 * R.r_num(0.85, 1.15);
} else if (modstrokeWeightValue == 3) {
    calculatedStrokeWeight = 6 * R.r_num(0.85, 1.15);
} else if (modstrokeWeightValue == 4) {
    calculatedStrokeWeight = 7 * R.r_num(0.85, 1.15);
} else if (modstrokeWeightValue == 5) {
    calculatedStrokeWeight = R.r_int(7, 9);
} else {
    calculatedStrokeWeight = 5;
}

let withTexture = dcP[5] % 10 < 9 ? true : false; // true 90% of the time and false 10% of the time.

function getCanvasDimensions() {
    // Calculate the window's current aspect ratio
    let windowRatio = innerWidth / innerHeight;
    let canvasWidth, canvasHeight;

    // 1. Check if the window is in a wide landscape mode (ratio greater than 16:9)
    if (windowRatio > 1.77) {
        // Set canvas dimensions based on window width while maintaining 16:9 ratio
        canvasWidth = innerWidth;
        canvasHeight = innerWidth * 9 / 16;

        // If the calculated height is greater than the window height
        // adjust both dimensions while maintaining the 16:9 ratio
        if (canvasHeight > innerHeight) {
            canvasHeight = innerHeight;
            canvasWidth = canvasHeight * 16 / 9;
        }
    }
    // 2. Check if the window is in a tall portrait mode (ratio less than 9:16)
    else if (windowRatio < 0.56) {
        // Set canvas dimensions based on window height while maintaining 9:16 ratio
        canvasHeight = innerHeight;
        canvasWidth = innerHeight * 9 / 16;

        // If the calculated width is greater than the window width
        // adjust both dimensions while maintaining the 9:16 ratio
        if (canvasWidth > innerWidth) {
            canvasWidth = innerWidth;
            canvasHeight = canvasWidth * 16 / 9;
        }
    }
    // 3. For aspect ratios in between (close to square), set the canvas to 1:1 ratio
    else {
        // Set canvas dimensions to be square based on the smallest dimension of the window
        canvasWidth = Math.min(innerWidth, innerHeight);
        canvasHeight = canvasWidth;
    }
    let menor=canvasWidth<canvasHeight?canvasWidth:canvasHeight;

    // Return the calculated canvas dimensions
    return {
        width: canvasWidth,
        height: canvasHeight,
        menor: menor
    };
}

let chosenPaletteIndex = R.r_int(0, palettes.length - 1);
chosenPalette = palettes[chosenPaletteIndex].colors;

backgroundColor = R.r_choice(chosenPalette);

let dimensions = getCanvasDimensions();
let ladoMenor=dimensions.menor;

ensureVisibility();
// Use margins by reducing the initial rectangle size and moving its position
const margin = useMargin ? 5 : 0; // Let's say we want a 5% margin on each side

splitRect(margin, margin, 100 - 2 * margin, 100 - 2 * margin, leastArea, 0);

function drawElements() {
    let un = ladoMenor/100;
    rectMode(CENTER);
    background(backgroundColor);

    // Isolate the transformation
    push();  // Push the current drawing state
    
    if (applyTransformation && !useMargin) {
        // Move to the center of the canvas
        translate(width / 2, height / 2);
    
        // Apply the transformations
        scale(1.42);
        rotate(0.1 * globalRotation);
    
        // Move back
        translate(-width / 2, -height / 2);
    }

    // The following code will now be affected by the transformation
    strokeJoin(ROUND);
    for (let r=0;r<rectang.length;r++){
        let el=rectang[r];
        stroke(el.strokeOutlineColor);
        // circle(el.centerX*un,el.centerY*un,5)
        fill(el.rectFillColorB);
        rect(el.centerX*un,el.centerY*un,el.shapeWidth*un,el.shapeHeight*un);
        drawShape(  el.centerX*un, el.centerY*un, 
                    el.shapeWidth*un, el.shapeHeight*un, 
                    el.randomShapeValue,
                    el.offset*un, 
                    el.rectFillColorA, el.rectFillColorB,
                    el.withTexture, el.bgtextureData, el.fgtextureData);
    }

    pop();  // Pop back to the previous drawing state
}

function setup() {
    noiseSeed(seed + 2);
    noiseDetail(10, .1);
    
    // This code regenerates the texture colors, so keep it in the setup 
    // to ensure it's only run once and not during a resize
    for (let r = 0; r < rectang.length; r++){
        let el = rectang[r];
        el.rectFillColorB = getColorFromNoise(el.centerX, el.centerY, chosenPalette);
    }
    
    createCanvas(ladoMenor, ladoMenor);
    
    // Call the function that draws elements
    drawElements();

    // circle(el.centerX*un,el.centerY*un,5) 
}


// A recursive function that splits a rectangle into smaller rectangles
// based on certain conditions and then draws a shape inside them using vertex
function splitRect(posX, posY, rectWidth, rectHeight, leastArea, depth) {
    let area = rectWidth * rectHeight;
	
	// Check if the rectangle should be split further or if we should draw in it
    // Conditions: 
    // 1. If the area is larger than the leastArea and a random check passes
    // 2. OR if we're still in the first 3 depths of recursion
    if ((area > leastArea && R.r_bool(0.83)) || depth < 3) { 
		// Determine if we're splitting vertically or horizontally based on rectangle dimensions      
        if (rectHeight < rectWidth) {
			// Calculate the width of the first sub-rectangle after splitting
            let randWidth = R.r_num(0.14, 0.58) * rectWidth;
            // Recursively split the rectangle into two horizontally
			splitRect(posX, posY, randWidth, rectHeight, leastArea, depth + 1);
            splitRect(posX + randWidth, posY, rectWidth - randWidth, rectHeight, leastArea, depth + 1);
        }
        else {
			// Calculate the height of the first sub-rectangle after splitting
            let randHeight = R.r_num(0.21, 0.91) * rectHeight;
            // Recursively split the rectangle into two vertically
            splitRect(posX, posY, rectWidth, randHeight, leastArea, depth + 1);
            splitRect(posX, posY + randHeight, rectWidth, rectHeight - randHeight, leastArea, depth + 1);
        }
    } else {
	    
        let weightedShapes = [1,1,1,2,2,3,4,4,4,4,5,6,6,7,7];
        randomShapeValue = R.r_choice(weightedShapes); 
		randomShapeValue = shouldValueChange ? randomShapeValue: consistentShapeValue;
			
		rectang.push({"centerX": posX + rectWidth / 2, 
			"centerY": posY + rectHeight / 2, 
			"shapeWidth": rectWidth - 1, 
			"shapeHeight": rectHeight - 1, 
			"randomShapeValue": randomShapeValue,
			"strokeOutlineColor": strokeOutlineColor,
			"calculatedStrokeWeight": calculatedStrokeWeight,
            "rectFillColorA":R.r_choice(chosenPalette),
            "rectFillColorB":R.r_choice(chosenPalette),
            "offset":Math.min(rectWidth, rectHeight) * R.r_num(0.09, 0.75),
            "withTexture":withTexture,
            "bgtextureData":R.r_dec(),
            "fgtextureData":R.r_dec()    
		}); 		
    }
}

 
function windowResized() {
    dimensions = getCanvasDimensions();
    ladoMenor = dimensions.menor;
    resizeCanvas(ladoMenor, ladoMenor);
    drawElements();
}



keyPressed=()=>{
	if (key === 's') {
	  save(tokenData.hash);
	}
}


// Function to draw a shape based on the provided parameters
function drawShape(centerX, centerY, shapeWidth, shapeHeight, randomShapeValue, offset, colorA, colorB, withTexture, bgtextureData, fgtextureData) {
    
	rectangleCount += 1;
    let widthOffset = shapeWidth - offset;
    let heightOffset = shapeHeight - offset;
    strokeWeight(calculatedStrokeWeight*dimensions.menor*.0005);
    // Assuming R.r_choice picks a random value from an array.
	// randomShapeValue = 7;

    // Draw the main rectangle
    drawBackgroundRect(centerX, centerY, shapeWidth, shapeHeight, colorA);
    
    drawRandomShape(centerX, centerY, shapeWidth, shapeHeight, withTexture, bgtextureData)

    if (randomShapeValue != 6) {
        // Draw the secondary rectangle
        drawBackgroundRect(centerX + (shapeWidth - widthOffset) / 2, centerY + (shapeHeight - heightOffset) / 2, widthOffset, heightOffset, colorB);

        // Draw additional shapes outside of the two rectangles
        drawRandomShape(centerX, centerY, shapeWidth, shapeHeight, withTexture, fgtextureData)
    }
 
    // Check if both strokeOutlineColor and fillColorA are black
    if (strokeOutlineColor === '#000000' && colorA === '#000000') {
        colorA = '#ffffff';  // Change fillColorA to white
    }

    // Check if both strokeOutlineColor and fillColorB are black
    if (strokeOutlineColor === '#000000' && colorB === '#000000') {
        colorB = '#ffffff';  // Change fillColorB to white
    }

    // Check if both strokeOutlineColor and fillColorA are white
    if (strokeOutlineColor === '#ffffff' && colorA === '#ffffff') {
        colorA = '#000000';  // Change fillColorA to black
    }

    // Check if both strokeOutlineColor and fillColorB are white
    if (strokeOutlineColor === '#ffffff' && colorB === '#ffffff') {
        colorB = '#000000';  // Change fillColorB to black
    }

	switch (randomShapeValue) {
		case 1:            
			// Draw the first additional shape (upper-left)
			fill(colorA);
            beginShape();
			vertex(centerX - (shapeWidth / 2) + offset, centerY + shapeHeight / 2);
			vertex(centerX - (shapeWidth / 2), centerY + (shapeHeight / 2) - offset);
			vertex(centerX - (shapeWidth / 2), centerY - shapeHeight / 2);
			vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2) + offset);
			endShape(CLOSE);

			// Draw the second additional shape (lower-right)
			fill(colorB);
			beginShape();
                vertex(centerX + (shapeWidth / 2), centerY - (shapeHeight / 2) + offset);
                vertex(centerX + (shapeWidth / 2) - offset, centerY - (shapeHeight / 2));
                fill(colorB);
                vertex(centerX - (shapeWidth / 2), centerY - shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2) + offset);
			endShape(CLOSE);
			break;
		
		case 2:
			fill(colorA);          
			beginShape();
                vertex(centerX - (shapeWidth / 2) + offset, centerY + shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2), centerY - shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2) + offset);
			endShape(CLOSE);

			fill(colorB);       
			beginShape();
                vertex(centerX + (shapeWidth / 2), centerY - (shapeHeight / 2) + offset);
                vertex(centerX + (shapeWidth / 2) - offset, centerY - (shapeHeight / 2));
                fill(colorB);
                vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2) + offset);
			endShape(CLOSE);
			break;

		case 3:		
            fill(colorA);
			beginShape();
                vertex(centerX - (shapeWidth / 2) + offset, centerY + shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2), centerY - shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2) + offset);
			endShape(CLOSE);

			fill(colorB);
			beginShape();
                vertex(centerX + (shapeWidth / 2), centerY - (shapeHeight / 2) + offset);
                vertex(centerX + (shapeWidth / 2) - offset, centerY - (shapeHeight / 2));
                vertex(centerX - (shapeWidth / 2), centerY - shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2) + offset);
			endShape(CLOSE);
			break;

		case 4:			
            fill(colorA);          
			beginShape();
                vertex(centerX - (shapeWidth / 2) + offset, centerY + shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2), centerY - shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2) + offset);
			endShape(CLOSE);

			fill(colorB);           
			beginShape();
                vertex(centerX + (shapeWidth / 2), centerY - (shapeHeight / 2) + offset);
                vertex(centerX - (shapeWidth / 2), centerY - shapeHeight / 2);
                vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2) + offset);
			endShape(CLOSE);			
			break;

		case 5:
			// First trapezoid
			beginShape();
                vertex(centerX + (shapeWidth - widthOffset) / 2, centerY + (shapeHeight - heightOffset) / 2);
                fill(colorA);
                vertex(centerX + (shapeWidth - widthOffset) / 2, centerY + heightOffset / 2);
                vertex(centerX + widthOffset / 2, centerY + heightOffset / 2);
                vertex(centerX + widthOffset / 2, centerY + (shapeHeight - heightOffset) / 2);
                fill(colorB);
			endShape(CLOSE);

			// Second trapezoid
			fill(colorA);
                beginShape();
                vertex(centerX + (shapeWidth - widthOffset) / 2, centerY + (shapeHeight - heightOffset) / 2);
                if (shouldColorSection(dcP[27])) fill(colorA);
                vertex(centerX + (shapeWidth - widthOffset) / 2, centerY - heightOffset / 2);
                if (shouldColorSection(dcP[28])) fill(colorB);
                vertex(centerX + widthOffset / 2, centerY - heightOffset / 2);
                fill(colorB);
                vertex(centerX + widthOffset / 2, centerY + (shapeHeight - heightOffset) / 2);
			endShape(CLOSE);
			break;

		case 6:        
        // Draw the first additional shape (upper-right)
        fill(colorA);
        beginShape();
            vertex(centerX + (shapeWidth / 2) - offset, centerY + shapeHeight / 2);
            vertex(centerX + (shapeWidth / 2), centerY + (shapeHeight / 2) - offset);
            vertex(centerX + (shapeWidth / 2), centerY - shapeHeight / 2);
            vertex(centerX + (shapeWidth / 2) - offset, centerY - (shapeHeight / 2) + offset);
        endShape(CLOSE);

        // Draw the second additional shape (lower-left)
        fill(colorB);
        beginShape();
            vertex(centerX - (shapeWidth / 2), centerY - (shapeHeight / 2) + offset);
            vertex(centerX - (shapeWidth / 2) + offset, centerY - (shapeHeight / 2));
            fill(colorA);
            vertex(centerX + (shapeWidth / 2), centerY - shapeHeight / 2);
            vertex(centerX + (shapeWidth / 2) - offset, centerY - (shapeHeight / 2) + offset);
        endShape(CLOSE);
        break;

        case 7:
            // First trapezoid (mirrored to the left)
            beginShape();
                vertex(centerX - (shapeWidth - widthOffset) / 2, centerY + (shapeHeight - heightOffset) / 2);
                if (shouldColorSection(dcP[20])) fill(colorA);
                vertex(centerX - (shapeWidth - widthOffset) / 2, centerY + heightOffset / 2);
                if (shouldColorSection(dcP[21])) fill(colorB);
                vertex(centerX - widthOffset / 2, centerY + heightOffset / 2);
                if (shouldColorSection(dcP[22])) fill(colorA);
                vertex(centerX - widthOffset / 2, centerY + (shapeHeight - heightOffset) / 2);
                if (shouldColorSection(dcP[23])) fill(colorB);
            endShape(CLOSE);

            // Second trapezoid (mirrored to the left)
            fill(colorA);
            beginShape();
                vertex(centerX - (shapeWidth - widthOffset) / 2, centerY + (shapeHeight - heightOffset) / 2);
                if (shouldColorSection(dcP[24])) fill(colorB);
                vertex(centerX - (shapeWidth - widthOffset) / 2, centerY - heightOffset / 2);
                if (shouldColorSection(dcP[25])) fill(colorA);
                vertex(centerX - widthOffset / 2, centerY - heightOffset / 2);
                if (shouldColorSection(dcP[26])) fill(colorB);
                vertex(centerX - widthOffset / 2, centerY + (shapeHeight - heightOffset) / 2);
            endShape(CLOSE);
            break;
	}
    //  square(centerX + (shapeWidth - widthOffset) / 2, centerY + (shapeHeight - heightOffset) / 2, 15);  
    noFill(0);
	strokeWeight(calculatedStrokeWeight*dimensions.menor*.0005);
	rect(centerX, centerY, shapeWidth, shapeHeight);     
}

function shouldColorSection(offset, probability = 0.5) {
    return noise(offset) < probability;
}

// Function to draw a background rectangle with given parameters
function drawBackgroundRect(centerX, centerY, shapeWidth, shapeHeight, color) {
    fill(color);
    rect(centerX, centerY, shapeWidth, shapeHeight);
}

//Function to use the noise-based color
function getColorFromNoise(x, y, chosenPalette) {
    // Get a noise value based on the x and y coordinates
    let noiseValue = noise(x * dcP[13]/255, y * dcP[13]/255); // The multipliers can be adjusted for more or less granularity in the noise

    // Map the noise value (which is between 0 and 1) to an index in the chosenPalette
    let paletteIndex = Math.floor(noiseValue * chosenPalette.length);

    // Ensure the index is within bounds
    paletteIndex = Math.min(paletteIndex, chosenPalette.length - 1);

    return chosenPalette[paletteIndex];
}

function drawRandomShape(centerX, centerY, width, height, withTexture, textureData) {
    // Check the rule
    if (!withTexture) {
        return; 
    }

    r=textureData

    if (r < 0.1) {
        drawWaves(centerX, centerY, width, height, textureData);
    } else if (r < 0.2) {
        drawSmallSquares(centerX, centerY, width, height, textureData);
    } else if (r < 0.3) {
        drawCircles(centerX, centerY, width, height, textureData);
    } else if (r < 0.5) {
        drawRectgs(centerX, centerY, width, height, textureData);
    } else if (r < 0.75) {
        drawWaves(centerX, centerY, width, height, textureData);
    } 
}


function drawSmallSquares(centerX, centerY, widthOffset, heightOffset, textureData) {
    let un=dimensions.menor/1000;
    let littleSquareSize = floor(textureData*3+3)*un;
    strokeWeight(littleSquareSize*.25)
    let gap = floor(textureData*6+14)*un;

    let x1 = centerX - widthOffset / 2;
    let y1 = centerY - heightOffset / 2;

    push();
        drawingContext.clip();

        let i = 0;

        for (let y = y1; y < y1 + heightOffset; y += littleSquareSize + gap) {
            for (let x = x1; x < x1 + widthOffset; x += littleSquareSize + gap) {
                let texColor=chosenPalette[floor(i*i*textureData*1982*2*3)%chosenPalette.length];
                fill(texColor);
                square(x, y, dimensions.menor*.01); 
                i++;
            }
        }

    pop();
    strokeWeight(calculatedStrokeWeight*dimensions.menor*.0005);
}

function drawCircles(centerX, centerY, widthOffset, heightOffset, textureData) {
    let n = floor(textureData*1982)%14+6;
    let s = max(widthOffset, heightOffset) / n;
    let sw = min(widthOffset, heightOffset)*.05;
    strokeWeight(calculatedStrokeWeight*dimensions.menor*.0003);
    // Define the clip region
    push();
        drawingContext.clip();

        // Fill the rectangle with little circles
        for (let i = 0; i < n; i++) {
            for (let j = 0; j < n; j++) {
                let px = i * s + centerX - widthOffset / 2 + s / 2;
                let py = j * s + centerY - heightOffset / 2 + s / 2;
                let xx = floor(i+7*textureData*j*textureData)%2;
                if (xx == 0) {
                    let texColor=chosenPalette[floor(textureData*1982+textureData*j)%chosenPalette.length];
                    fill(texColor);  // Choose a color from our palette
                    let cr = .5*(s * abs(cos(textureData*sin(j)*10.2)+sin(i*97)))+.15;
                    strokeWeight(cr*.20)
                    circle(px, py, cr);
                } else if (xx == 1) {
                    let cr = s * 0.45;
                    strokeWeight(cr*.20);
                    circle(px, py, cr);
                }
            }
        }
    pop();
    strokeWeight(calculatedStrokeWeight*dimensions.menor*.0005);
}

function drawWaves(centerX, centerY, widthOffset, heightOffset, textureData) {

    let ss = int(max(widthOffset, heightOffset) * 5.5);
    let noiseFactor = noise(centerX * 0.01, centerY * 0.01);
    let steppedNoise = floor(noiseFactor * 10) / 10;
    let sinFactor = Math.sin(textureData * PI);
    let steppedSin = floor(sinFactor * 10) / 10;
    let combinedFactor = steppedNoise * steppedSin;
    let amp = ss * (0.02 + combinedFactor * 0.03) + textureData * 0.05;
    let wn = floor(textureData*5+25);     
    let f = floor(textureData*1982)%9+7; 

    push(); // Save the current state of the drawing settings

    // Move the drawing to the rectangle's center
    translate(centerX, centerY);

    // Rotate the entire pattern
    rotate(PI/floor(textureData*8));
    drawingContext.clip();

    // Draw waves
    for (let j = 0; j < wn; j++) {
        let yy = map(j, 0, wn - 1, -ss / 2, ss / 2);                    
        let texColor=chosenPalette[floor(textureData*1982+textureData*j)%chosenPalette.length];
        fill(texColor);  // Choose a color from our palette
        beginShape();
        vertex(-ss / 2, ss / 2);
        for (let i = 0; i < ss; i++) {
            let xx = map(i, 0, ss - 1, -ss, ss);
            let t = map(i, 0, ss - 1, 0, TAU * f);
            let texColor1=chosenPalette[floor(textureData*1982+textureData*j*22)%chosenPalette.length];
            fill(texColor1);  // Choose a color from our palette
            vertex(xx, yy + amp * sin(t));
        }
        vertex(ss / 2, ss / 2);
        endShape();
    }

    pop(); 
    
}

function drawRectgs(centerX, centerY, widthOffset, heightOffset, textureData) {
    let n1 = floor(textureData*5+5);
    let n2 = round(n1 * (heightOffset / widthOffset));
    let ww = widthOffset / n1;
    let hh = heightOffset / n2;
    let bk = min(ww, hh) * 0.1;

    strokeWeight(bk*.5);

    // Calculate starting coordinates (top-left of the main rectangle)
    let startX = centerX - widthOffset / 2 + bk ;
   
    let startY = centerY - heightOffset / 2 + bk;


    strokeWeight(bk);
    // Define the clip region
    push();
    drawingContext.clip();
    
    // Draw the background rectangle
    // Choose a color from our palette      
    let texBgColor=chosenPalette[floor(textureData*1982+textureData)%chosenPalette.length];
    fill(texBgColor);

    // Draw the inner rectangles
    for (let i = 0; i < n1; i++) {
        for (let j = 0; j < n2; j++) {
            let px = startX + i * (ww + bk);
            let py = startY + j * (hh + bk);
            let texColorIndex = floor(noise(i * 0.1, j * 0.1, textureData*5) * chosenPalette.length);
            let texColor=chosenPalette[texColorIndex];
            fill(texColor);
            rect(px, py, ww - bk, hh - bk);
        }
    }
    pop();

    strokeWeight(calculatedStrokeWeight*dimensions.menor*.0005);
}

function shuffleArr(array) {
    for (let i = array.length - 1; i > 0; i--) {
        // Generate a random index between 0 and i (inclusive)
        let j = Math.floor(Math.random() * (i + 1));
        
        // Swap elements at indices i and j
        let temp = array[i];
        array[i] = array[j];
        array[j] = temp;
    }
    return array;
}

// Ensure there's at least one non-black item on the canvas
function ensureVisibility() {
   
	if (chosenPalette.includes(backgroundColor) && chosenPalette.includes('#000000')) {
	  let blackCount = 0;
	  for (let color of chosenPalette) {
		if (color === '#000000') blackCount++;
	  }
	  
	  if (blackCount === chosenPalette.length) {
		// All colors in the palette are black, add a white (or any non-black color) to avoid a full black screen
		chosenPalette.push('#ffff00');
	  }
	}

    // Adjusting the stroke color based on the background color
    if (backgroundColor === '#000000' && strokeOutlineColor === '#000000') {
        strokeOutlineColor = '#ffffff';  // Set the stroke color to white if background is black
    } else if (backgroundColor === '#ffffff' && strokeOutlineColor === '#ffffff') {
        strokeOutlineColor = '#000000';  // Set the stroke color to black if background is white
    }
}
 