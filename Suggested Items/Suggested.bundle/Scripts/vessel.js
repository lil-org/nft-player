
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
    this.prngA = new sfc32(tokenData.hash.substring(2, 34));
    this.prngB = new sfc32(tokenData.hash.substring(34, 66));
    for (let i = 0; i < 1e6; i += 2) {
      this.prngA();
      this.prngB();
    }
  }
  random_dec() {
    this.useA = !this.useA;
    return this.useA ? this.prngA() : this.prngB();
  }
  random_num(a, b) {
    return a + (b - a) * this.random_dec();
  }
  random_int(a, b) {
    return Math.floor(this.random_num(a, b + 1));
  }
  random_bool(p) {
    return this.random_dec() < p;
  }
  random_choice(list) {
    return list[this.random_int(0, list.length - 1)];
  }
}


let R;

const fs = `
#ifdef GL_ES
	precision highp float;
#endif
varying vec2 vTexCoord;
varying vec4 vVertexColor;
uniform float wv1x;
uniform float wv2x;
uniform float wv3x;

uniform float wv1y;
uniform float wv2y;
uniform float wv3y;

uniform vec3 c0;
uniform vec3 c1;
uniform vec3 c2;
uniform vec3 c3;
uniform vec3 c4;

void main ()
{
    vec2 uv = vTexCoord;
    uv = uv - vec2(.5,.5);
    uv = uv * 2.0;
    float d = length(uv);

    vec3 ro = vec3(0,0,-3); // ray origin
    vec3 rd = normalize(vec3(uv,1));
    float t = 0.0;
    for(int i=0;i<10;i++) {
      vec3 p = ro+(rd*t);
      float g = cos(wv1x*p.x) *  cos(wv1y*p.y) *  cos(wv1x*p.z);
      g += cos(wv2x*p.x) *  cos(wv2y*p.y) *  cos(wv2x*p.z);
      g += cos(wv3x*p.x) *  cos(wv3y*p.y)  *  cos(wv3x*p.z);
      g /= 6.0;    
      g = abs(g);
      t += (g);
      if(g < .001) break;
      if(g > 2.0) break;
    }
    
    if(t<0.5) {
        gl_FragColor = vec4( c0*t, 1.0);
    } else if(t>0.5 && t<0.7)  {
        gl_FragColor = vec4(c1*t, 1.0);
    } else if(t>0.7 && t<0.8)  {
        gl_FragColor = vec4(c2*t, 1.0);
    } else if(t>0.8 && t<1.0)  {
       gl_FragColor = vec4(c3*t, 1.0);
    } else {
       gl_FragColor = vec4(c4*t, 1.0);
    }
    
}
`
const vs = `
attribute vec3 aPosition;
attribute vec2 aTexCoord;
attribute vec4 aVertexColor;
uniform mat4 uProjectionMatrix;
uniform mat4 uModelViewMatrix;
varying vec2 vTexCoord;
varying vec4 vVertexColor;
void main ()
{
	vTexCoord = aTexCoord;
    vVertexColor = aVertexColor;
 	vec4 position = vec4( aPosition, 1.0 );
	gl_Position = uProjectionMatrix * uModelViewMatrix * position;
}
`;
let pals = [["#69d2e7","#a7dbd8","#e0e4cc","#f38630","#fa6900"],["#fe4365","#fc9d9a","#f9cdad","#c8c8a9","#83af9b"],["#ecd078","#d95b43","#c02942","#542437","#53777a"],["#556270","#4ecdc4","#c7f464","#ff6b6b","#c44d58"],["#774f38","#e08e79","#f1d4af","#ece5ce","#c5e0dc"],["#e8ddcb","#cdb380","#036564","#033649","#031634"],["#490a3d","#bd1550","#e97f02","#f8ca00","#8a9b0f"],["#594f4f","#547980","#45ada8","#9de0ad","#e5fcc2"],["#00a0b0","#6a4a3c","#cc333f","#eb6841","#edc951"],["#e94e77","#d68189","#c6a49a","#c6e5d9","#f4ead5"],["#3fb8af","#7fc7af","#dad8a7","#ff9e9d","#ff3d7f"],["#d9ceb2","#948c75","#d5ded9","#7a6a53","#99b2b7"],["#ffffff","#cbe86b","#f2e9e1","#1c140d","#cbe86b"],["#efffcd","#dce9be","#555152","#2e2633","#99173c"],["#343838","#005f6b","#008c9e","#00b4cc","#00dffc"],["#413e4a","#73626e","#b38184","#f0b49e","#f7e4be"],["#ff4e50","#fc913a","#f9d423","#ede574","#e1f5c4"],["#99b898","#fecea8","#ff847c","#e84a5f","#2a363b"],["#655643","#80bca3","#f6f7bd","#e6ac27","#bf4d28"],["#00a8c6","#40c0cb","#f9f2e7","#aee239","#8fbe00"],["#351330","#424254","#64908a","#e8caa4","#cc2a41"],["#554236","#f77825","#d3ce3d","#f1efa5","#60b99a"],["#5d4157","#838689","#a8caba","#cad7b2","#ebe3aa"],["#8c2318","#5e8c6a","#88a65e","#bfb35a","#f2c45a"],["#fad089","#ff9c5b","#f5634a","#ed303c","#3b8183"],["#ff4242","#f4fad2","#d4ee5e","#e1edb9","#f0f2eb"],["#f8b195","#f67280","#c06c84","#6c5b7b","#355c7d"],["#d1e751","#ffffff","#000000","#4dbce9","#26ade4"],["#1b676b","#519548","#88c425","#bef202","#eafde6"],["#5e412f","#fcebb6","#78c0a8","#f07818","#f0a830"],["#bcbdac","#cfbe27","#f27435","#f02475","#3b2d38"],["#452632","#91204d","#e4844a","#e8bf56","#e2f7ce"],["#eee6ab","#c5bc8e","#696758","#45484b","#36393b"],["#f0d8a8","#3d1c00","#86b8b1","#f2d694","#fa2a00"],["#2a044a","#0b2e59","#0d6759","#7ab317","#a0c55f"],["#f04155","#ff823a","#f2f26f","#fff7bd","#95cfb7"],["#b9d7d9","#668284","#2a2829","#493736","#7b3b3b"],["#bbbb88","#ccc68d","#eedd99","#eec290","#eeaa88"],["#b3cc57","#ecf081","#ffbe40","#ef746f","#ab3e5b"],["#a3a948","#edb92e","#f85931","#ce1836","#009989"],["#300030","#480048","#601848","#c04848","#f07241"],["#67917a","#170409","#b8af03","#ccbf82","#e33258"],["#aab3ab","#c4cbb7","#ebefc9","#eee0b7","#e8caaf"],["#e8d5b7","#0e2430","#fc3a51","#f5b349","#e8d5b9"],["#ab526b","#bca297","#c5ceae","#f0e2a4","#f4ebc3"],["#607848","#789048","#c0d860","#f0f0d8","#604848"],["#b6d8c0","#c8d9bf","#dadabd","#ecdbbc","#fedcba"],["#a8e6ce","#dcedc2","#ffd3b5","#ffaaa6","#ff8c94"],["#3e4147","#fffedf","#dfba69","#5a2e2e","#2a2c31"],["#fc354c","#29221f","#13747d","#0abfbc","#fcf7c5"],["#cc0c39","#e6781e","#c8cf02","#f8fcc1","#1693a7"],["#1c2130","#028f76","#b3e099","#ffeaad","#d14334"],["#a7c5bd","#e5ddcb","#eb7b59","#cf4647","#524656"],["#dad6ca","#1bb0ce","#4f8699","#6a5e72","#563444"],["#5c323e","#a82743","#e15e32","#c0d23e","#e5f04c"],["#edebe6","#d6e1c7","#94c7b6","#403b33","#d3643b"],["#fdf1cc","#c6d6b8","#987f69","#e3ad40","#fcd036"],["#230f2b","#f21d41","#ebebbc","#bce3c5","#82b3ae"],["#b9d3b0","#81bda4","#b28774","#f88f79","#f6aa93"],["#3a111c","#574951","#83988e","#bcdea5","#e6f9bc"],["#5e3929","#cd8c52","#b7d1a3","#dee8be","#fcf7d3"],["#1c0113","#6b0103","#a30006","#c21a01","#f03c02"],["#000000","#9f111b","#b11623","#292c37","#cccccc"],["#382f32","#ffeaf2","#fcd9e5","#fbc5d8","#f1396d"],["#e3dfba","#c8d6bf","#93ccc6","#6cbdb5","#1a1f1e"],["#f6f6f6","#e8e8e8","#333333","#990100","#b90504"],["#1b325f","#9cc4e4","#e9f2f9","#3a89c9","#f26c4f"],["#a1dbb2","#fee5ad","#faca66","#f7a541","#f45d4c"],["#c1b398","#605951","#fbeec2","#61a6ab","#accec0"],["#5e9fa3","#dcd1b4","#fab87f","#f87e7b","#b05574"],["#951f2b","#f5f4d7","#e0dfb1","#a5a36c","#535233"],["#8dccad","#988864","#fea6a2","#f9d6ac","#ffe9af"],["#2d2d29","#215a6d","#3ca2a2","#92c7a3","#dfece6"],["#413d3d","#040004","#c8ff00","#fa023c","#4b000f"],["#eff3cd","#b2d5ba","#61ada0","#248f8d","#605063"],["#ffefd3","#fffee4","#d0ecea","#9fd6d2","#8b7a5e"],["#cfffdd","#b4dec1","#5c5863","#a85163","#ff1f4c"],["#9dc9ac","#fffec7","#f56218","#ff9d2e","#919167"],["#4e395d","#827085","#8ebe94","#ccfc8e","#dc5b3e"],["#a8a7a7","#cc527a","#e8175d","#474747","#363636"],["#f8edd1","#d88a8a","#474843","#9d9d93","#c5cfc6"],["#046d8b","#309292","#2fb8ac","#93a42a","#ecbe13"],["#f38a8a","#55443d","#a0cab5","#cde9ca","#f1edd0"],["#a70267","#f10c49","#fb6b41","#f6d86b","#339194"],["#ff003c","#ff8a00","#fabe28","#88c100","#00c176"],["#ffedbf","#f7803c","#f54828","#2e0d23","#f8e4c1"],["#4e4d4a","#353432","#94ba65","#2790b0","#2b4e72"],["#0ca5b0","#4e3f30","#fefeeb","#f8f4e4","#a5b3aa"],["#4d3b3b","#de6262","#ffb88c","#ffd0b3","#f5e0d3"],["#fffbb7","#a6f6af","#66b6ab","#5b7c8d","#4f2958"],["#edf6ee","#d1c089","#b3204d","#412e28","#151101"],["#9d7e79","#ccac95","#9a947c","#748b83","#5b756c"],["#fcfef5","#e9ffe1","#cdcfb7","#d6e6c3","#fafbe3"],["#9cddc8","#bfd8ad","#ddd9ab","#f7af63","#633d2e"],["#30261c","#403831","#36544f","#1f5f61","#0b8185"],["#aaff00","#ffaa00","#ff00aa","#aa00ff","#00aaff"],["#d1313d","#e5625c","#f9bf76","#8eb2c5","#615375"],["#ffe181","#eee9e5","#fad3b2","#ffba7f","#ff9c97"],["#73c8a9","#dee1b6","#e1b866","#bd5532","#373b44"],["#805841","#dcf7f3","#fffcdd","#ffd8d8","#f5a2a2"],["#379f7a","#78ae62","#bbb749","#e0fbac","#1f1c0d"],["#caff42","#ebf7f8","#d0e0eb","#88abc2","#49708a"],["#c2412d","#d1aa34","#a7a844","#a46583","#5a1e4a"],["#75616b","#bfcff7","#dce4f7","#f8f3bf","#d34017"],["#111625","#341931","#571b3c","#7a1e48","#9d2053"],["#82837e","#94b053","#bdeb07","#bffa37","#e0e0e0"],["#7e5686","#a5aad9","#e8f9a2","#f8a13f","#ba3c3d"],["#312736","#d4838f","#d6abb1","#d9d9d9","#c4ffeb"],["#395a4f","#432330","#853c43","#f25c5e","#ffa566"],["#fde6bd","#a1c5ab","#f4dd51","#d11e48","#632f53"],["#84b295","#eccf8d","#bb8138","#ac2005","#2c1507"],["#058789","#503d2e","#d54b1a","#e3a72f","#f0ecc9"],["#6da67a","#77b885","#86c28b","#859987","#4a4857"],["#bed6c7","#adc0b4","#8a7e66","#a79b83","#bbb2a1"],["#261c21","#6e1e62","#b0254f","#de4126","#eb9605"],["#efd9b4","#d6a692","#a39081","#4d6160","#292522"],["#e21b5a","#9e0c39","#333333","#fbffe3","#83a300"],["#f2e3c6","#ffc6a5","#e6324b","#2b2b2b","#353634"],["#c75233","#c78933","#d6ceaa","#79b5ac","#5e2f46"],["#793a57","#4d3339","#8c873e","#d1c5a5","#a38a5f"],["#512b52","#635274","#7bb0a8","#a7dbab","#e4f5b1"],["#11644d","#a0b046","#f2c94e","#f78145","#f24e4e"],["#59b390","#f0ddaa","#e47c5d","#e32d40","#152b3c"],["#fdffd9","#fff0b8","#ffd6a3","#faad8e","#142f30"],["#b5ac01","#ecba09","#e86e1c","#d41e45","#1b1521"],["#c7fcd7","#d9d5a7","#d9ab91","#e6867a","#ed4a6a"],["#11766d","#410936","#a40b54","#e46f0a","#f0b300"],["#595643","#4e6b66","#ed834e","#ebcc6e","#ebe1c5"],["#f1396d","#fd6081","#f3ffeb","#acc95f","#8f9924"],["#331327","#991766","#d90f5a","#f34739","#ff6e27"],["#efeecc","#fe8b05","#fe0557","#400403","#0aabba"],["#bf496a","#b39c82","#b8c99d","#f0d399","#595151"],["#b7cbbf","#8c886f","#f9a799","#f4bfad","#f5dabd"],["#ffb884","#f5df98","#fff8d4","#c0d1c2","#2e4347"],["#e5eaa4","#a8c4a2","#69a5a4","#616382","#66245b"],["#e0eff1","#7db4b5","#ffffff","#680148","#000000"],["#b1e6d1","#77b1a9","#3d7b80","#270a33","#451a3e"],["#e4ded0","#abccbd","#7dbeb8","#181619","#e32f21"],["#e9e0d1","#91a398","#33605a","#070001","#68462b"],["#fc284f","#ff824a","#fea887","#f6e7f7","#d1d0d7"],["#ffab07","#e9d558","#72ad75","#0e8d94","#434d53"],["#6da67a","#99a66d","#a9bd68","#b5cc6a","#c0de5d"],["#311d39","#67434f","#9b8e7e","#c3ccaf","#a51a41"],["#cfb590","#9e9a41","#758918","#564334","#49281f"],["#5cacc4","#8cd19d","#cee879","#fcb653","#ff5254"],["#44749d","#c6d4e1","#ffffff","#ebe7e0","#bdb8ad"],["#807462","#a69785","#b8faff","#e8fdff","#665c49"],["#e7edea","#ffc52c","#fb0c06","#030d4f","#ceecef"],["#ccf390","#e0e05a","#f7c41f","#fc930a","#ff003d"],["#2b222c","#5e4352","#965d62","#c7956d","#f2d974"],["#cc5d4c","#fffec6","#c7d1af","#96b49c","#5b5847"],["#e4e4c5","#b9d48b","#8d2036","#ce0a31","#d3e4c5"],["#e3e8cd","#bcd8bf","#d3b9a3","#ee9c92","#fe857e"],["#360745","#d61c59","#e7d84b","#efeac5","#1b8798"],["#ec4401","#cc9b25","#13cd4a","#7b6ed6","#5e525c"],["#eb9c4d","#f2d680","#f3ffcf","#bac9a9","#697060"],["#f2e8c4","#98d9b6","#3ec9a7","#2b879e","#616668"],["#f5dd9d","#bcc499","#92a68a","#7b8f8a","#506266"],["#fff3db","#e7e4d5","#d3c8b4","#c84648","#703e3b"],["#041122","#259073","#7fda89","#c8e98e","#e6f99d"],["#8d7966","#a8a39d","#d8c8b8","#e2ddd9","#f8f1e9"],["#c6cca5","#8ab8a8","#6b9997","#54787d","#615145"],["#1d1313","#24b694","#d22042","#a3b808","#30c4c9"],["#4b1139","#3b4058","#2a6e78","#7a907c","#c9b180"],["#2d1b33","#f36a71","#ee887a","#e4e391","#9abc8a"],["#f0ffc9","#a9da88","#62997a","#72243d","#3b0819"],["#429398","#6b5d4d","#b0a18f","#dfcdb4","#fbeed3"],["#9d9e94","#c99e93","#f59d92","#e5b8ad","#d5d2c8"],["#95a131","#c8cd3b","#f6f1de","#f5b9ae","#ee0b5b"],["#322938","#89a194","#cfc89a","#cc883a","#a14016"],["#540045","#c60052","#ff714b","#eaff87","#acffe9"],["#79254a","#795c64","#79927d","#aeb18e","#e3cf9e"],["#452e3c","#ff3d5a","#ffb969","#eaf27e","#3b8c88"],["#2b2726","#0a516d","#018790","#7dad93","#bacca4"],["#027b7f","#ffa588","#d62957","#bf1e62","#572e4f"],["#fa6a64","#7a4e48","#4a4031","#f6e2bb","#9ec6b8"],["#fb6900","#f63700","#004853","#007e80","#00b9bd"],["#f06d61","#da825f","#c4975c","#a8ab7b","#8cbf99"],["#23192d","#fd0a54","#f57576","#febf97","#f5ecb7"],["#f6d76b","#ff9036","#d6254d","#ff5475","#fdeba9"],["#a3c68c","#879676","#6e6662","#4f364a","#340735"],["#a32c28","#1c090b","#384030","#7b8055","#bca875"],["#80a8a8","#909d9e","#a88c8c","#ff0d51","#7a8c89"],["#6d9788","#1e2528","#7e1c13","#bf0a0d","#e6e1c2"],["#373737","#8db986","#acce91","#badb73","#efeae4"],["#e6b39a","#e6cba5","#ede3b4","#8b9e9b","#6d7578"],["#280904","#680e34","#9a151a","#c21b12","#fc4b2a"],["#4b3e4d","#1e8c93","#dbd8a2","#c4ac30","#d74f33"],["#161616","#c94d65","#e7c049","#92b35a","#1f6764"],["#234d20","#36802d","#77ab59","#c9df8a","#f0f7da"],["#a69e80","#e0ba9b","#e7a97e","#d28574","#3b1922"],["#641f5e","#676077","#65ac92","#c2c092","#edd48e"],["#e6eba9","#abbb9f","#6f8b94","#706482","#703d6f"],["#26251c","#eb0a44","#f2643d","#f2a73d","#a0e8b7"],["#fdcfbf","#feb89f","#e23d75","#5f0d3b","#742365"],["#ff7474","#f59b71","#c7c77f","#e0e0a8","#f1f1c1"],["#4f364c","#5e405f","#6b6b6b","#8f9e6f","#b1cf72"],["#230b00","#a29d7f","#d4cfa5","#f8ecd4","#aabe9b"],["#d4f7dc","#dbe7b4","#dbc092","#e0846d","#f51441"],["#62a07b","#4f8b89","#536c8d","#5c4f79","#613860"]]
let colors = []
let hexPalette = []
let bgClr;
function hexToRgb(hex) {
  hex = hex.replace('#', '');
  var bigint = parseInt(hex, 16);
  var r = (bigint >> 16) & 255;
  var g = (bigint >> 8) & 255;
  var b = bigint & 255;
  return [r / 255, g / 255, b / 255];
}

let renderer;
let canS;
let canSBy2;
let canSBy4;
let canSBy10;

let canS2;

let flowers = []
let allVertices = []
let yPos = 0
let zPos = 0

function rotateByX(x,y,z,pi) {
  const xr = x
  const yr = y*cos(pi) - z*sin(pi)
  const zr = y*sin(pi) + z*cos(pi) 
  return [xr,yr,zr]  
}
function rotateBy(x,y,pi) {
  const xr = x*cos(pi) - y*sin(pi);
  const yr = x*sin(pi) + y*cos(pi);
  return [xr,yr]
}
function initFlower() {
  const seg = TWO_PI/60;
  const points = [];
  const circles = []
  circles.push([width*0.2, 1])
  circles.push([width*0.01, R.random_choice([-1,-2,-3,-4,2,3,4])])
  circles.push([width*0.01, R.random_choice([-1,-2,-3,-4,2,3,4])])
  circles.push([width*0.01, R.random_choice([-1,-2,-3,-4,2,3,4])])
  
  for(let pi=0;pi<=TWO_PI+seg;pi+=seg) {
    let x = 0;
    let y = 0;
    let R = 0 
    const v = map(pi, 0, TWO_PI, 0,1)
    for(const [r,p] of circles) {
      x += r*cos(pi*p)
      y += r*sin(pi*p)
      R+=r;
    }
    const [xr, yr] = rotateBy(x,y,HALF_PI)
    points.push([xr,yr,v, R,R/4, pi])
  }
  const maxAngle = R.random_choice([QUARTER_PI, HALF_PI, QUARTER_PI+HALF_PI, PI])
  return [points, maxAngle];
}

function generateFlower(name, points,maxAngle, minY, maxY, isFlexible, isZigzag, twist, isEven) {
  let vertices = []
  let uvs = []
  let faces = []
  const grid = []
  const numSteps = 40;
  let index = 0;
  const p1 = R.random_choice([-1,-2,-3,-4,1,2,3,4])
  const p2 = R.random_choice([-1,-2,-3,-4,1,2,3,4])
  
  for(let i=1;i<=4;i++) {
    const u = map(i,1, 4,  0, 1)
    const row = []
    for(const [p1,p2, v, R,R2, angle] of points) {
      let s = map(i,1, 4,  5, 4)
      row.push(index)
      uvs.push(u, v)
      vertices.push(new p5.Vector(p1*s,minY,p2*s))
      
      index++
    }
    grid.push(row)
  }
  let minAngle = 0
  if(isEven) {
    minAngle = -maxAngle
  }
  for(let i=1;i<=numSteps;i++) {
    const y = map(i,1, numSteps,  minY, maxY)
    let pi = map(i,1, numSteps,  0, maxAngle)
    const u = map(i,1, numSteps,  0, 1)
    let spi = map(i,1, numSteps,  minAngle, maxAngle)
    let sf = abs(cos(spi) + cos(spi*p1) + cos(spi*p2))/2
    let s = 2+ sf
        spi = spi*twist

    let yy = 0
    if(isFlexible ) { 
      pi = 0;    
    }
    if(isZigzag) {
      if(sf < 1)  { s = 1.5 + sf; }
    } else {
      if(sf > 1)  { s = 0.5 + sf; }
    }
    const row = []
    for(const [p1,p2, v, R,R2, angle] of points) {
     if(isFlexible) {  yy = (R2*cos(angle*2)+(R2)*cos(angle*4)); }  
      const [xr, yr] = rotateBy(p1,p2,spi);
      row.push(index)
      uvs.push(u, v)
      const cord = rotateByX(xr*s,y+yy,yr*s, pi )
      vertices.push(new p5.Vector(cord[0],cord[1],cord[2]))
      
      index++
    }
    
    grid.push(row)
  }
  

  
  for(var roo=0;roo<grid.length;roo++) {
    for(var pt=0;pt<grid[roo].length;pt++) {
      let v1;
      if(grid[roo][pt] !== undefined) {
        v1 = grid[roo][pt]
      }
      let v2;
      if(grid[roo][pt+1] !== undefined) {
        v2 = grid[roo][pt+1]
      }
      let v3;
      if(grid[roo+1] !== undefined && grid[roo+1][pt+1]  !== undefined) {
        v3 = grid[roo+1][pt+1]
      }
      let v4;
      if(grid[roo+1]  !== undefined && grid[roo+1][pt]  !== undefined) {
        v4 = grid[roo+1][pt]
      }

      if(typeof(v1) === "number" && typeof(v2) === "number" && typeof(v3) === "number" && typeof(v4) === "number") {
        faces.push([v1,v3,v2])
        faces.push([v1,v4,v3])
      }
    }
  }
  const flower = new p5.Geometry();
  flower.gid = "flower_model_"+name;
  flower.vertices = vertices;
  flower.faces = faces;
  flower.uvs = uvs;
  
  return flower
  
}
let shaderProgram;
let wv1x;
let wv2x;
let wv3x;
let wv1y;
let wv2y;
let wv3y;
let wvP;
let isMulti = false;

function setup() {
  R = new Random();
    canS = windowWidth;

    if (windowHeight < windowWidth) {
      canS = windowHeight;
    }
    canSBy2 = canS/2;
    canSBy4 = canS/4;
    canSBy10 = canS/10;
    canS2 = canS*2;
    zPos = -(canS+canS)
	  renderer = createCanvas( canS, canS, WEBGL );
    shaderProgram  = createShader(vs, fs);  
      wv1x = R.random_num(10, 40);
      wv2x = R.random_num(10, 40);
      wv3x = R.random_num(10, 40);

      wv1y = R.random_num(10, 40);
      wv2y = R.random_num(10, 40);
      wv3y = R.random_num(10, 40);
  
      console.log(wv1x, wv2x, wv3x, wv1y, wv2y, wv3y)
  
      const isFlexible = R.random_choice([true, false])
      const isZigzag = R.random_choice([true, false])
      const twist = R.random_choice([0, 1])
      const isEven = R.random_choice([true, false,false])
      if(!isFlexible) { 
        isMulti = R.random_choice([true, false,false])
      }
      
      let [points, maxAngle] = initFlower()

      let minY = height
      yPos = 0
      
      if(isFlexible) {
        minY = height
        zPos = -(canS+canS)
        yPos = canSBy10
      } else {
        minY = height*2
        yPos = -(canS-canSBy4)
        zPos = -(canS+canS+canSBy2)
        maxAngle = R.random_choice([PI, -PI, (QUARTER_PI+HALF_PI), -(QUARTER_PI+HALF_PI)]) 
      }
  
      const flower = generateFlower('name', points, maxAngle, minY, -minY, isFlexible, isZigzag, twist, isEven)
      flowers.push(flower)
    
    strokeWeight(canS*.002)
    zPos -= canSBy10
  
  hexPalette =  R.random_choice(pals)
    colors = hexPalette.map((hex => hexToRgb(hex)))
    const bg = R.random_choice(colors)
  bgClr = color(bg[0]*255,bg[1]*255,bg[2]*255);
  bgClr.setAlpha(20);
  noStroke();

}
let rotatey = 0;
let stopAnim = false
function shd(zpi) {
  push()
  rotateZ(zpi)
  shader(shaderProgram);
  shaderProgram.setUniform('wv1x', wv1x);
  shaderProgram.setUniform('wv2x', wv2x);
  shaderProgram.setUniform('wv3x', wv3x);
  shaderProgram.setUniform('wv1y', wv1y);
  shaderProgram.setUniform('wv2y', wv2y);
  shaderProgram.setUniform('wv3y', wv3y);
  shaderProgram.setUniform('c0', colors[0]);
  shaderProgram.setUniform('c1', colors[1]);
  shaderProgram.setUniform('c2', colors[2]);
  shaderProgram.setUniform('c3', colors[3]);
  shaderProgram.setUniform('c4', colors[4]);
  translate(0,yPos,zPos)
  rotateY(rotatey)
  model(flowers[0])
  pop()
}
function draw() {
  background("#fbfbfb");
   orbitControl()
    if(!stopAnim) {
      rotatey = -HALF_PI - (millis()*.0001);
    }
    shd(0);
  
    if(isMulti) {
      shd(PI);
    }
}

function keyTyped() {
  if (key === 's') { saveCanvas(renderer, `img`, 'png'); }
  if (key === ' ') { stopAnim = !stopAnim }
}