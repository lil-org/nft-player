let hashPairs = [];
for (let j = 0; j < 32; j++) {hashPairs.push(tokenData.hash.slice(2 + (j * 2), 4 + (j * 2)));}
let decPairs = hashPairs.map(x => {return parseInt(x, 16);});
let gp;
let comp =[0,197,0,175,12,213,43,128,43,43,174,0,0,213,213,0,0,0,213,15,43,171,128,154,213,23,252,99,213,128,213,170,128,213,146,213,99,2,216,177,111,128,128,235,174,213,128,0,43,137,213,213,0,210,3,213,0,185,213,213,128,43,102,213,235,188,148,133,0,59,233,0,65,0,213,128,172,128,213,190,0,0,0,0,0,128,213,0,118,154,129,227,213,145,43,158,238,0,117,43,199,62,86,53,204,78,6,0,43,0,0,0,129,213,0,77,48,16,43,128,0,213,191,0,213,128,89,43,0,211,116,43,128,43,241,128,107,128,43,226,128,0,133,213,224,43,139,101,43,57,128,195,162,128,83,1,128,100,128,43,43,128,178,43,69,43,0,220,73,0,43,88,79,139,52,230,43,133,174,43,213,22,158,104,46,198,213,128,0,128,167,128,168,130,0,43,213,43,213,128,43,128,39,128,128,28,30,81,43,0,128,43,213,44,232,0,0,87,43,0,70,128,173,62,70,90,155,9,128,128,0,72,128,0,0,181,213,0,0,0,94,58,105,128,128,34,213,43,128,43,213,0,5,43,213,168,0,93,128,151,0,213,169,163,0,251,0,0,223,43,213,128,128,43,89,93,62,242,0,213,226,212,166,0,128,205,231,95,128,144,149,230,249,128,233,128,161,228,213,157,75,157,11,213,213,43,43,230,128,0,95,0,0,213,213,213,128,128,72,43,128,128,43,172,0,0,206,43,0,173,128,0,170,113,150,157,128,0,128,108,0,128,231,157,185,148,106,202,189,128,205,166,43,128,165,213,0,213,25,203,195,128,128,176,33,173,0,86,189,33,213,180,213,128,213,0,43,225,213,128,128,103,128,0,176,213,213,83,0,63,163,10,0,0,43,211,95,128,88,67,0,128,128,128,213,1,213,244,82,0,128,129,110,213,128,103,39,192,213,57,108,109,43,0,197,0,100,2,0,213,175,213,0,128,128,0,72,76,0,0,146,213,173,0,100,43,201,128,213,128,213,128,213,0,157,57,128,182,21,118,196,128,218,128,196,74,213,128,128,73,175,128,128,108,121,213,58,128,34,29,43,89,59,180,135,91,128,107,179,180,114,174,128,227,43,0,43,213,131,154,128,128,90,213,128,92,0,213,0,213,183,213,128,0,43,43,213,128,0,152,97,20,33,43,128,0,43,0,91,191,101,118,26,128,250,128,238,45,0,128,27,76,163,135,128,165,0,179,128,43,56,107,128,213,56,106,0,194,191,147,128,128,0,128,128,205,0,40,128,128,0,213,0,153,0,96,213,43,128,164,0,0,0,190,43,0,128,213,128,193,65,161,234,213,43,0,248,182,0,0,128,0,128,0,0,128,128,102,21,124,150,128,106,159,43,43,176,152,128,133,165,19,149,128,1,133,0,0,128,0,80,213,116,163,213,18,169,0,64,128,213,68,192,249,128,43,128,128,253,213,94,59,0,183,213,128,143,0,128,18,43,26,128,203,137,240,198,213,193,212,152,150,204,215,158,124,0,85,30,128,13,213,128,213,60,213,121,43,128,152,213,0,0,101,213,226,235,0,65,0,10,239,120,213,0,213,115,0,213,182,0,213,43,0,43,213,6,136,188,65,112,175,150,43,128,56,213,131,103,169,56,186,135,35,141,113,213,159,176,6,128,213,206,128,128,17,240,34,22,6,180,0,97,128,43,128,43,0,0,43,213,128,209,128,128,0,42,213,128,180,43,60,42,43,77,32,0,0,0,21,43,91,128,46,0,128,53,128,128,145,128,177,33,49,224,250,107,128,93,42,142,52,201,8,66,30,232,166,97,171,0,43,103,163,116,138,128,213,84,144,250,213,211,115,52,0,0,42,128,43,39,144,213,213,0,213,213,0,213,175,251,128,43,183,0,143,155,43,70,103,43,177,0,43,157,209,221,82,128,242,43,0,43,38,195,160,56,196,43,213,135,150,213,128,213,95,43,10,81,203,9,186,128,114,99,66,213,22,0,2,213,177,18,128,183,213,213,213,128,101,0,109,213,252,128,43,85,206,43,239,88,128,8,40,78,237,0,0,239,0,213,132,128,8,43,213,67,173,145,80,128,213,196,0,178,213,116,213,92,128,215,128,217,142,148,50,44,203,2,107,102,213,173,170,213,43,89,111,186,213,43,141,0,128,143,70,213,0,89,251,192,0,83,145,166,128,240,128,139,193,95,0,151,128,119,233,43,118,180,148,196,172,81,189,172,148,42,96,155,101,43,50,213,157,8,114,170,128,192,230,213,128,213,43,160,82,0,128,0,213,43,43,128,75,128,101,43,154,192,0,128,128,56,128,213,53,61,189,128,199,29,0,128,236,154,43,156,190,38,213,23,213,128,0,213,213,36,213,213,213,138,99,50,44,137,0,43,173,164,254,173,128,124,92,47,116,223,57,177,76,128,15,45,213,128,43,43,128,128,213,128,0,213,76,128,0,128,128,99,148,128,0,148,142,128,213,138,43,200,235,43,57,213,149,36,47,136,213,187,224,127,0,11,202,213,236,161,128,145,116,18,129,187,128,128,136,132,0,170,128,193,54,241,213,128,157,128,213,179,143,0,0,213,86,128,172,3,128,0,216,213,213,128,0,213,150,204,165,209,58,161,213,128,128,138,149,213,213,213,213,213,43,43,213,128,0,179,128,224,43,79,238,36,43,77,136,72,48,107,151,142,3,118,213,43,196,246,205,128,0,128,70,3,128,134,213,119,6,243,46,43,0,142,43,213,136,226,241,214,191,31,212,0,27,43,254,43,43,145,43,42,43,128,207,0,128,177,126,14,128,0,106,173,104,147,43,227,128,243,188,106,213,133,56,213,231,185,43,194,43,213,29,187,251,103,0,50,194,43,49,128,0,183,128,128,128,213,210,213,160,0,0,70,50,213,71,0,128,147,43,38,213,128,90,213,141,128,213,53,192,213,168,2,128,236,191,68,183,95,174,220,73,0,213,66,11,183,23,148,77,73,174,187,128,128,43,39,128,213,250,128,180,0,128,0,128,13,247,128,128,0,191,42,0,163,193,169,86,43,156,23,55,179,173,43,43,213,0,69,75,43,213,213,128,0,149,213,213,171,213,134,93,249,128,159,0,43,213,4,128,213,113,128,213,70,71,213,0,47,143,25,0,243,128,0,213,190,0,128,235,185,0,0,90,213,0,0,103,48,111,213,128,0,192,0,151,107,0,168,198,213,186,71,128,128,67,0,213,43,19,154,213,235,0,77,213,213,213,204,128,147,0,213,21,125,213,128,196,213,0,128,128,128,215,128,190,174,128,128,128,213,128,210,213,128,128,203,187,213,160,213,0,167,128,1,213,146,128,198,209,128,43,0,213,0,128,213,156,213,0,25,0,213,237,213,213,213,213,92,0,213,213,213,128,213,199,224,201,81,213,128,119,180,98,128,170,66,213,43,128,159,72,128,128,213,200,43,90,61,107,43,215,144,43,219,43,144,176,188,213,128,53,241,213,213,23,172,113,213,34,214,84,227,213,43,213,69,128,165,129,0,67,182,177,213,213,25,128,246,140,213,128,251,226,128,211,213,43,0,179,14,105,43,128,245,128,52,128,213,213,213,0,0,121,197,224,61,104,128,128,128,254,222,6,0,172,162,19,170,243,128,254,213,250,30,43,43,199,43,213,213,0,45,0,0,233,154,213,2,18,209,34,194,0,238,128,0,124,183,194,63,128,137,222,213,43,128,213,0,128,213,128,194,187,0,83,196,128,195,128,43,128,196,0,111,213,213,189,128,31,148,43,87,43,43,43,128,213,213,43,43,248,100,18,241,0,0,206,42,65,79,52,166,57,43,0,125,168,245,128,213,49,0,77,0,0,212,98,43,239,43,213,128,190,43,0,230,0,128,0,213,128,35,202,174,199,210,177,68,73,155,128,236,12,192,5,175,135,0,128,161,7,15,90,40,107,105,73,14,182,128,71,110,88,252,62,18,40,43,23,128,0,25,180,12,213,43,28,128,174,176,5,99,213,43,128,91,0,128,213,128,128,0,0,43,0,128,134,0,78,213,148,41,120,43,209,189,83,0,43,203,43,97,43,213,252,43,3,140,25,213,14,0,60,123,176,136,81,86,244,56,121,29,137,0,128,0,0,111,0,0,213,182,0,185,213,0,43,181,0,43,43,128,0,0,0,175,0,211,47,16,133,128,213,212,67,206,173,214,109,53,0,233,213,182,43,153,213,254,14,9,44,111,16,43,23,181,165,5,79,50,247,226,253,15,213,43,128,19,213,0,213,0,14,9,45,213,95,0,250,110,153,0,128,133,0,88,43,0,238,128,74,0,213,148,123,74,201,165,32,243,48,176,213,213,213,0,125,0,196,128,213,185,213,43,107,64,43,0,140,236,230,234,106,16,0,231,7,43,43,213,213,213,111,213,10,0,0,195,134,33,55,177,0,128,128,213,0,128,43,128,153,92,0,128,43,132,195,29,43,0,213,47,128,168,152,45,122,13,51,128,0,201,65,213,46,213,23,13,128,231,91,220,54,80,16,109,15,193,43,213,43,43,128,128,43,128,17,43,120,253,121,16,105,128,46,213,201,138,110,252,101,248,110,27,200,46,110,70,37,114,90,43,72,70,12,192,131,251,213,93,213,43,3,75,43,185,221,43,213,57,27,94,128,170,17,233,91,3,154,62,203,93,17,213,43,0,133,43,213,213,106,253,128,43,95,157,89,183,2,4,210,191,43,172,28,92,43,128,231,59,114,128,128,31,213,132,180,213,191,3,244,78,128,43,0,213,145,209,213,150,175,213,238,92,207,0,168,48,147,198,122,171,93,128,200,23,83,142,234,155,190,140,178,213,213,0,213,0,0,232,14,151,24,213,128,210,188,212,213,132,128,177,13,128,43,138,79,18,43,172,43,200,173,128,0,213,201,129,12,128,213,0,213,166,134,166,43,128,229,86,183,211,213,28,195,82,23,18,191,94,15,31,43,128,213,128,43,213,213,128,213,213,213,213,235,43,200,128,43,18,52,128,113,213,0,0,129,128,0,0,43,96,201,89,0,185,128,199,0,179,66,107,128,213,148,3,116,128,0,167,202,189,0,185,43,43,10,83,245,204,56,160,87,160,167,128,187,0,128,133,236,0,213,19,213,248,100,213,128,128,89,230,213,105,246,0,213,114,55,128,43,113,0,206,112,206,213,213,0,18,0,0,207,213,177,133,19,213,151,0,213,230,137,126,213,187,232,128,213,254,144,166,128,38,77,213,12,158,128,151,213,0,0,213,240,0,128,128,0,213,91,158,128,43,181,186,44,0,129,139,70,128,128,128,213,43,7,0,54,91,43,167,104,213,62,16,70,253,4,90,172,43,243,128,43,213,165,43,43,11,37,139,0,0,207,161,219,111,32,175,128,41,182,128,138,110,128,232,128,135,43,87,213,213,134,70,77,207,43,78,73,180,0,0,125,128,152,213,85,201,0,141,0,106,71,213,240,128,213,61,208,213,0,43,213,207,151,152,213,213,99,141,5,213,240,213,128,0,213,49,157,55,43,60,43,4,123,246,213,1,231,152,128,197,213,155,55,187,118,249,213,129,213,148,27,128,84,213,128,128,248,202,106,128,187,43,1,43,128,167,213,128,154,57,213,97,86,205,152,128,189,186,213,213,16,192,230,213,213,128,173,66,174,0,131,49,0,86,36,37,90,213,137,132,27,92,164,35,193,3,213,186,82,46,206,176,95,43,141,54,0,213,0,88,213,128,150,229,172,213,213,128,128,144,194,213,0,213,8,43,190,43,103,191,42,51,161,43,213,213,193,128,230,213,0,213,213,213,0,40,43,47,206,0,128,1,0,193,128,128,7,186,213,0,0,128,189,155,128,128,31,213,43,128,159,43,128,98,214,128,128,187,213,128,213,128,127,0,149,128,43,128,111,151,0,43,213,185,213,67,128,133,213,128,167,128,233,128,203,128,205,213,213,0,64,21,128,8,146,34,12,170,212,198,128,205,5,214,237,213,128,101,0,213,171,213,130,91,165,0,128,128,179,43,200,213,128,213,10,2,43,72,149,0,177,65,43,156,0,43,212,140,43,75,213,206,148,0,0,213,62,212,43,128,206,213,0,128,34,0,9,128,136,197,128,242,98,177,149,202,17,213,102,128,134,109,213,128,245,43,79,43,78,0,128,120,119,128,202,190,213,0,0,220,128,0,135,148,128,46,213,54,213,128,213,213,137,128,202,213,213,210,0,0,61,213,194,120,43,43,109,0,43,85,213,0,155,146,25,154,0,65,213,208,171,87,202,238,0,196,156,213,99,128,126,128,212,128,198,128,128,128,223,229,0,43,6,166,177,178,28,128,128,213,185,235,43,6,128,103,0,145,128,213,213,90,60,128,23,128,0,12,137,64,213,254,43,9,243,199,83,178,33,89,43,43,84,43,153,210,1,43,51,128,188,213,161,213,162,188,0,214,176,128,109,57,208,43,1,182,33,169,200,155,0,213,114,199,13,80,167,43,0,128,213,128,213,128,22,22,121,171,213,92,213,128,21,0,37,213,61,159,213,196,198,226,128,213,180,14,213,128,7,216,69,205,128,128,26,128,0,30,128,180,154,213,95,182,138,213,191,213,229,0,0,128,166,213,70,140,174,102,43,128,213,217,213,128,213,239,16,175,184,213,100,120,128,124,146,226,244,128,128,0,98,241,197,68,43,224,201,188,43,212,43,128,128,152,43,108,47,0,0,213,235,51,81,43,124,43,200,46,43,213,145,0,0,0,128,0,128,158,128,0,43,209,60,76,0,250,43,69,213,128,147,223,213,137,0,213,128,101,61,50,128,213,213,25,213,0,213,190,43,213,128,44,213,117,188,98,128,180,0,128,157,154,225,62,0,144,43,156,43,48,0,43,185,124,43,0,0,68,154,0,0,143,128,247,213,91,0,43,213,93,244,164,247,59,148,36,219,213,213,43,43,145,8,57,183,15,186,213,43,128,190,229,85,67,43,161,43,205,128,106,100,128,0,213,253,128,213,59,108,27,213,133,128,128,19,78,251,43,43,162,43,0,213,128,94,0,213,2,213,213,196,61,149,128,213,128,68,0,164,43,43,213,33,105,213,128,87,83,43,213,213,178,168,97,43,74,76,68,170,128,128,152,196,35,202,84,123,128,177,226,128,0,104,213,165,213,0,7,213,213,43,89,128,213,0,213,29,213,198,248,149,213,213,43,213,213,128,213,173,100,170,93,192,74,132,244,0,77,255,13,177,208,50,128,43,13,145,213,213,43,213,162,213,213,243,202,179,43,149,146,213,173,96,57,31,0,213,152,128,132,0,0,85,213,213,23,149,14,213,184,211,0,43,49,5,0,114,122,0,0,89,197,71,128,96,128,213,0,237,0,75,181,109,43,36,43,15,112,2,213,40,0,190,135,10,214,70,43,79,230,43,213,8,96,140,192,222,43,78,213,43,100,213,82,128,87,89,43,48,128,43,113,155,192,42,226,128,158,172,101,250,144,7,148,213,213,0,214,128,174,128,43,117,26,89,128,128,143,224,165,128,193,128,128,43,247,128,184,0,54,245,240,97,193,108,58,171,15,213,109,128,163,53,202,76,213,0,0,43,225,128,43,172,118,3,42,122,175,43,0,23,128,128,0,0,111,35,128,128,43,150,49,128,128,64,213,134,249,43,0,43,233,200,33,81,128,141,43,43,43,153,128,136,229,128,146,43,128,80,128,108,212,160,100,128,43,67,188,43,119,112,213,43,1,50,74,128,249,239,128,0,0,128,128,164,43,0,128,190,213,43,128,0,0,153,245,209,81,92,128,210,156,207,213,84,128,71,20,213,55,195,196,191,192,128,128,213,143,0,128,0,185,213,158,222,245,55,183,74,29,140,6,205,128,0,80,43,93,128,213,43,169,213,128,0,0,100,43,90,213,0,0,6,128,195,148,140,130,128,99,43,13,147,0,236,54,96,128,77,182,101,0,0,128,128,213,43,128,171,112,86,59,242,64,43,205,0,250,213,105,213,213,70,64,246,160,128,128,82,0,128,128,128,0,213,58,153,43,128,213,128,213,0,213,0,157,128,0,182,29,72,147,43,0,128,0,222,43,219,151,43,1,128,108,128,43,128,32,49,224,44,92,0,193,128,0,127,57,38,210,153,243,167,128,18,213,213,0,0,128,50,128,148,90,213,0,65,0,213,0,213,128,213,156,244,213,128,0,43,170,14,0,235,39,0,110,43,43,213,213,0,0,187,43,121,0,213,0,0,98,213,69,43,213,163,43,75,128,213,128,114,213,178,85,212,128,43,68,128,145,0,0,130,128,128,72,0,43,0,146,139,125,0,128,0,213,186,128,128,43,200,0,0,227,0,128,194,128,128,173,36,213,213,169,128,107,213,45,161,128,146,42,128,213,0,69,85,160,253,213,172,129,176,43,128,128,43,110,213,212,163,213,21,213,195,213,178,213,158,128,128,213,0,213,251,0,0,128,77,0,0,213,128,0,213,0,213,213,163,0,251,128,0,254,159,191,29,232,208,128,107,180,213,213,213,43,75,161,135,128,128,128,92,115,78,156,43,0,66,164,70,179,0,0,177,128,128,213,166,76,0,243,43,0,128,141,0,0,203,213,0,213,213,59,4,98,213,182,43,213,128,213,128,43,6,25,0,128,163,213,128,128,0,128,32,225,101,197,128,47,128,128,223,128,136,173,43,88,128,43,102,128,128,43,128,128,7,128,131,113,128,0,43,101,143,149,128,128,0,209,43,128,0,179,0,5,104,0,128,0,213,98,43,128,128,249,128,115,145,43,226,0,128,213,43,0,61,130,98,0,57,0,194,128,119,112,128,231,173,213,0,128,128,128,128,213,43,82,0,30,43,43,0,62,161,103,208,97,133,213,43,156,64,158,43,60,245,43,128,0,121,250,128,0,213,128,128,128,130,231,0,65,0,213,81,172,128,213,190,0,128,0,0,128,128,156,183,43,89,68,101,43,106,128,36,225,213,213,173,199,129,43,0,178,73,225,128,50,128,0,0,129,213,0,61,78,213,43,133,213,213,138,128,213,128,182,11,0,197,0,155,254,213,0,174,59,7,25,128,128,213,137,128,128,0,213,213,43,171,128,16,174,43,28,43,213,75,0,213,0,175,84,43,176,250,236,174,156,128,147,252,128,213,128,128,43,137,213,213,0,210,0,82,213,185,194,12,134,75,102,0];
let cS = 64;let rS = 1024;let pg;let pg2;let pg3;let shdr;let shdr2;let scaler = 0.02;let xDis = 4.2;let yDis = 10.2;let offset = 800;let offset2 = 0;let timr=0;let dur =450;let totalt=0;let flip = 0;let colr = 0;let x1 =0;let x2 =0;let x3 =0;let y1 =0;let y2 =0;let y3 =0;let z1 =0;let z2 =0;let z3 =0;let hue =0;let rot =0;let sharpness=1.0;let lava = 0;
let ordroverview = [84.71,5.135 ,42.018,37.00, 41.977,22.019, 43.03,11.07, 82.978,48, 13,85.0379, 62,50.032, 8.989,85.009, 69.988,33.01, 41.9859,43.98399];
let destroverview = [84.976,5.11, 12,7, 60,4, 96,69, 49,96.986, 48,92, 40,38.002, 6,75, 93,17.0059, 31, 28.0039];
let chaosoverview = [7.998,95.0339, 53,49.01, 22,33, 51,48, 25,79, 3,83, 60,43, 92,90.0234, 29.998,65.0059, 20,46];
let creationoverview  = [41,7.317, 77,73, 91,28, 34,63, 98,68, 92,89, 9,69, 20,53, 6.984,57, 84,52,];
let overviewstyles =[ordroverview,destroverview,chaosoverview,creationoverview];
let orderNeutral = [74.988,19, 71.0379,44, 66.003,29.0139,  43.014,68.002, 58.9799,61.024, 15.9899,48.0120, 64.982,16.02199, 46.979,20.0239,66.92,26.0099, 363.975,993.016 ];
let destructioneutral = [98.99,26.005, 80,28.002,  15,14.016, 55.012,44.004, -646,163,-473.004,712.998];
let creationneutral = [24,30, 35,88.94, 47.983,51.006, 55.994,64.0039, 9,30, 66.994,46.01, 83, 51.0120, 79.01199,97.00399, 40.9959,89.002,85.994,79.0039,75.996,81.0119, 50.002,8.026, 518.0119,262.986, -383,87];
let chaosneutral = [7,57, 35.9959,43.998, 79.99,43.995, 60.9939,77.0059, 48,97.0119, 63.9919,26.0059, 58.986,25.0039,39,43.018, 62.9859,44.02,993,389.9859, -439,123 ];
let neutralstyles =[orderNeutral,destructioneutral,creationneutral,chaosneutral];
let orderzoom = [-158.9799,119.958, -559.998,353.02, -546.0079,294.9899, -243.008,531, -163, 279.979, 378.9859,978.966, -669.0059,-33.98799, -718.0119,855.9620, 138.998,-61.008];
let creationzoom = [71,197.018, 63.99,274, 852,903, -102,111, 653,426, 224.002,836, 671.00399,667, 955,693, -618.996,16.002];
let destructionzoom = [814,187,37,313.004, 598,2, -101,752, 439,508.002, -728.002,730.996, 958,994, -925,-18, -595.994,534.002,663,47];
let chaoszoom = [930.0119,121.99, 170,-29, -655,108,508.004];
let zoomstyles =[orderzoom,destructionzoom,creationzoom,chaoszoom];let styles = [overviewstyles,neutralstyles,zoomstyles];let feature = "none";
function preload() {shdr =  getShader(this._renderer);shdr2 =  getShader(this._renderer); shdr3 =  getShader(this._renderer);}

function setup() {
	  
			let stylepicker = map(decPairs[16], 0, 255, 0, 100); 
			if(stylepicker<=15){stylepicker =0;}
			if(stylepicker>15 && stylepicker<=40){stylepicker =1;}
			if(stylepicker>35 && stylepicker<=100){stylepicker =2;}
			let rd = round(map(decPairs[17], 0, 255, 0, (styles[stylepicker].length)-1));
			let rd2 = round(map(decPairs[18], 0, 255, 0, (styles[stylepicker][rd].length/2)-1));
			xDis = styles[stylepicker][rd][rd2*2];
			yDis = styles[stylepicker][rd][rd2*2+1];
			xDis += map(decPairs[19], 0, 255, -0.015, 0.015); 
			yDis += map(decPairs[20], 0, 255, -0.015, 0.015); 
			if(stylepicker == 0){scaler = 0.05;}
			if(stylepicker == 1){scaler = 0.03;}
			if(stylepicker == 2){scaler = 0.02;}
			colr = map(decPairs[3], 0, 255, 0.0,100.0); 
			if(colr <= 3){colr =0;feature = "Swamp";}
			if(colr <= 6 && colr > 3){colr =1;feature = "Purple Haze";}
			if(colr <= 9 && colr > 6){colr =2;feature = "1987";}
			if(colr <= 12 && colr > 9){colr =3;feature = "Deep Ocean";}
			if(colr <= 22 && colr > 12){colr =4;feature = "Hue Changer";}
			if(colr <= 23 && colr > 22){colr =5;feature = "Black and White";}
			if(colr <= 86 && colr > 23){colr =6;feature = "Random";}
			if(colr <= 88 && colr > 86){colr =13;feature = "Original";}
			if(colr <= 90 && colr > 88){colr =7;feature = "Virgin";}
			if(colr <= 92 && colr > 90){colr =8;feature = "Candy";}
			if(colr <= 94 && colr > 92){colr =9;feature = "Storm";}
			if(colr <= 96 && colr > 94){colr =10;feature = "Ethereal";}
			if(colr <= 98 && colr > 96){colr =11;feature = "70s";}
			if(colr <= 100 && colr > 98){colr =12;feature = "Ooze";}
			offset2 += map(decPairs[4], 0, 255, 0,6.14);
			x1 = map(decPairs[5], 0, 255, 0.25, 0.65);
			x2 = map(decPairs[6], 0, 255, 0.25, 0.65);
			x3 = map(decPairs[7], 0, 255, 0.25, 0.65);
			y1 = map(decPairs[8], 0, 255, 0.25, 0.65);
			y2 = map(decPairs[9], 0, 255, 0.25, 0.65);
			y3 = map(decPairs[10], 0, 255, 0.25, 0.65);
			z1 = map(decPairs[11], 0, 255, 0.25, 0.65);
			z2 = map(decPairs[12], 0, 255, 0.25, 0.65);
			z3 = map(decPairs[13], 0, 255, 0.25, 0.65);
			hue = map(decPairs[14], 0, 255, 0.0, 1.0);
			rot = map(decPairs[15], 0, 255, 0.0, 1.0);
			if(windowHeight > 2200){sharpness = 1.1;}else{sharpness = 0.5;}
			let canvas = createCanvas(windowWidth, windowHeight, WEBGL);
			gp = createGraphics(cS, cS, WEBGL);
			pg = createGraphics(windowWidth, windowHeight, WEBGL);
			pg.shader(shdr);
			pg2 = createGraphics(windowWidth, windowHeight, WEBGL);
			pg2.shader(shdr2);
			pg3 = createGraphics(windowWidth, windowHeight, WEBGL);
			pg3.shader(shdr3);
			shdr3.setUniform('start',  2);	
			decomp();

}

function draw() {
	let t = millis()/1000.0;
	let d = t-timr;
	timr = t;
	totalt +=d;
	t = totalt+offset;
	if(t >= dur+offset){totalt =0;}
  shdr.setUniform("time",t);shdr.setUniform("xDis", xDis);shdr.setUniform("yDis", yDis);shdr.setUniform("scaler", scaler);shdr.setUniform("rot", rot);shdr.setUniform("lava", lava);shdr2.setUniform("time",t);shdr2.setUniform("xDis", xDis);shdr2.setUniform("yDis", yDis);shdr2.setUniform("scaler", scaler);shdr2.setUniform("rot", rot);shdr2.setUniform("lava", lava);shdr3.setUniform("time", t);shdr3.setUniform("colr", colr);shdr3.setUniform("offset",offset2);shdr3.setUniform("x1", x1);shdr3.setUniform("x2", x2);shdr3.setUniform("x3", x3);shdr3.setUniform("y1", y1);shdr3.setUniform("y2", y2);shdr3.setUniform("y3", y3);shdr3.setUniform("z1", z1);shdr3.setUniform("z2", z2);shdr3.setUniform("z3", z3);shdr3.setUniform("hue", hue);shdr3.setUniform("sharpness", sharpness);
	render();
	
}

function keyPressed() {
	let inc = 0.002;
  if (key == 'w') {yDis  -= inc;} else if (key == 'a') {xDis -= inc;} else if (key == 's') {yDis  += inc;} else if (key == 'd') {xDis += inc;}
	else if (key == 'l') {switch(lava){case 0:lava = 1;break;case 1:lava = 0;break;}}
}

function mouseWheel(event) {
 scaler += event.delta/50000.0;
}

function hslToRgb(h, s, l) {var r, g, b;if (s == 0) {r = g = b = l; } else {function hue2rgb(p, q, t) {if (t < 0) t += 1;if (t > 1) t -= 1;if (t < 1/6) return p + (q - p) * 6 * t;if (t < 1/2) return q;if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;return p;}var q = l < 0.5 ? l * (1 + s) : l + s - l * s;var p = 2 * l - q;r = hue2rgb(p, q, h + 1/3);g = hue2rgb(p, q, h);b = hue2rgb(p, q, h - 1/3);}return [ r * 255, g * 255, b * 255 ];}
function rgbToHsl(r, g, b) {r /= 255, g /= 255, b /= 255;var max = Math.max(r, g, b), min = Math.min(r, g, b);var h, s, l = (max + min) / 2;if (max == min) {h = s = 0; } else {var d = max - min;s = l > 0.5 ? d / (2 - max - min) : d / (max + min);switch (max) {case r: h = (g - b) / d + (g < b ? 6 : 0); break;case g: h = (b - r) / d + 2; break;case b: h = (r - g) / d + 4; break;}h /= 6;}return [ h, s, l ];}
function decomp(){gp.loadPixels();for(let x = 0; x < cS; x++){for(let y = 0; y < cS; y++){let com =comp[cS * x + y]/255.0;let color = hslToRgb(com,1.0,0.5);var index = (cS * y + x) * 4;gp.pixels[index+0]= color[0];gp.pixels[index+1]= color[1];gp.pixels[index+2]= color[2];gp.pixels[index+3]= 255;}  }updatePixelsGL(gp);}
function updatePixelsGL(buf){const img = new p5.Image(buf.width, buf.height);img.loadPixels();for(let i =0; i<buf.pixels.length; i++){img.pixels[i] = buf.pixels[i];}img.updatePixels();buf.image(img, -buf.width/2, -buf.height/2);}

function render(){if(flip == 0){shdr.setUniform('imgTex', gp);shdr.setUniform('prevTex',  pg2);pg.rect(0,0,width, height);shdr3.setUniform('imgTex',  pg);pg3.rect(0,0,width, height);image(pg3, -width/2, -height/2);	}if(flip == 1){shdr2.setUniform('imgTex', gp);shdr2.setUniform('prevTex',  pg);pg2.rect(0,0,width, height);shdr3.setUniform('imgTex',  pg2);pg3.rect(0,0,width, height);image(pg3, -width/2, -height/2);};switch (flip) {case 0:flip = 1;break;case 1:flip = 0;break;}}
function getShader(_renderer) {
	const vert = `precision highp float;attribute vec3 aPosition;attribute vec2 aTexCoord;varying vec2 vUV;void main() {vUV = aTexCoord;vec4 position = vec4(aPosition, 1.0);position.xy = position.xy * 2.0 - 1.0;gl_Position = position;}`;
	const frag = `
		#define pi 3.14159265359
		precision highp float;varying vec2 vUV;const float WIDTH = ${windowWidth}.0;const float HEIGHT = ${windowHeight}.0;uniform sampler2D imgTex;uniform sampler2D prevTex;uniform float time;uniform float offset;uniform float scaler;uniform float xDis;uniform float yDis;uniform float start;uniform float colr;uniform float x1;uniform float x2;uniform float x3;uniform float y1;uniform float y2;uniform float y3;uniform float z1;uniform float z2;uniform float z3;uniform float hue;uniform float sharpness;uniform float rot;uniform float lava;
		float step_w = 1.0/WIDTH;
		float step_h = 1.0/HEIGHT;

		vec3 generator (in vec2 st) {float ran = fract(sin(dot(st.xy,vec2(12.9898,78.233)))* 43758.5453123);vec2 ranUV = vec2(ran,ran);vec3 col = texture2D(imgTex , ranUV).xyz;return col;}
		vec3 generate (in vec2 st) {vec2 i = floor(st);vec2 f = fract(st);vec3 a = generator(i);vec3 b = generator(i + vec2(1.0, 0.0));vec3 c = generator(i + vec2(0.0, 1.0));vec3 d = generator(i + vec2(1.0, 1.0));vec2 u = smoothstep(0.,1.,f);return mix(a, b, vec3(u.x)) +(c - a)* u.y * (1.0 - vec3(u.x)) +(d - b) * vec3(u.x * u.y);}
		vec3 rgb2hsv(vec3 c){vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));float d = q.x - min(q.w, q.y);float e = 1.0e-10;return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);}
		vec3 hsv2rgb(vec3 c){vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);}
		vec3 levelRange(vec3 color, float minInput, float maxInput){return min(max(color - vec3(minInput), vec3(0.0)) / (vec3(maxInput) - vec3(minInput)), vec3(1.0));}
		float blendSoftLight(float base, float blend) {return (blend<0.5)?(2.0*base*blend+base*base*(1.0-2.0*blend)):(sqrt(base)*(2.0*blend-1.0)+2.0*base*(1.0-blend));}vec3 blendSoftLight(vec3 base, vec3 blend) {return vec3(blendSoftLight(base.r,blend.r),blendSoftLight(base.g,blend.g),blendSoftLight(base.b,blend.b));}vec3 blendSoftLight(vec3 base, vec3 blend, float opacity) {return (blendSoftLight(base, blend) * opacity + base * (1.0 - opacity));}
    float blendLinearBurn(float base, float blend) {return max(base+blend-1.0,0.0);}vec3 blendLinearBurn(vec3 base, vec3 blend) {return max(base+blend-vec3(1.0),vec3(0.0));}vec3 blendLinearBurn(vec3 base, vec3 blend, float opacity) {return (blendLinearBurn(base, blend) * opacity + base * (1.0 - opacity));}
		float blendLinearDodge(float base, float blend) {return min(base+blend,1.0);}vec3 blendLinearDodge(vec3 base, vec3 blend) {return min(base+blend,vec3(1.0));}vec3 blendLinearDodge(vec3 base, vec3 blend, float opacity) {return (blendLinearDodge(base, blend) * opacity + base * (1.0 - opacity));}
    float blendLinearLight(float base, float blend) {return blend<0.5?blendLinearBurn(base,(2.0*blend)):blendLinearDodge(base,(2.0*(blend-0.5)));}vec3 blendLinearLight(vec3 base, vec3 blend) {return vec3(blendLinearLight(base.r,blend.r),blendLinearLight(base.g,blend.g),blendLinearLight(base.b,blend.b));}vec3 blendLinearLight(vec3 base, vec3 blend, float opacity) {return (blendLinearLight(base, blend) * opacity + base * (1.0 - opacity));}
		mat2 rotate2d(float _angle){return mat2(cos(_angle),-sin(_angle),sin(_angle),cos(_angle));}
		vec3 channelMixer(vec3 r, vec3 g, vec3 b, vec3 c){vec3 col = vec3(0.);col.x = (r.x*c.x) + (r.y*c.y)  + (r.z*c.z);col.y = (g.x*c.x) + (g.y*c.y)  + (g.z*c.z);col.z = (b.x*c.x) + (b.y*c.y)  + (b.z*c.z);return col;}
		float Gaussian (float x, float sigma){return exp(-(x*x) / (2.0 * sigma*sigma));}
		const int   filterSize    = 15; const float textureSize = HEIGHT;const int   halfFilterSize = filterSize / 2;const float pixelSizeX = (1.0 / WIDTH);const float pixelSizeY = (1.0 / HEIGHT);
		vec3 BlurredPixel (in vec2 uv,float sigma ){float total = 0.0;vec3 ret = vec3(0);for (int iy = 0; iy < filterSize; iy++){float fy = Gaussian (float(iy) - float(halfFilterSize), sigma);float offsety = float(iy-halfFilterSize) * pixelSizeY;for (int ix = 0; ix < filterSize; ix++){float fx = Gaussian (float(ix) - float(halfFilterSize), sigma);float offsetx = float(ix-halfFilterSize) * pixelSizeX;float f = fx*fy;total += f;ret += texture2D(imgTex, uv + vec2(offsetx, offsety)).rgb * f;}}return ret / total;}

		vec3 calcCol(vec2 uv,vec2 st, float offX, float offY, float tim){
				uv.y = 1.0 - uv.y;
				float dis= distance(uv,vec2(0.5));
				if(lava == 1.0){uv.y += time*0.05;}
				uv -= vec2(0.5);uv= rotate2d(2.*pi*rot) * uv;uv += vec2(0.5);
				uv -= vec2(0.5);uv *= scaler;uv += vec2(0.5);
				uv.x += xDis + offX;uv.y += yDis + offY;
				vec3 n = 0.5* generate(uv*vec2(2.));n += 0.25* generate(uv*vec2(8.));n += 0.125* generate(uv*vec2(16.));n += 0.0625* generate(uv*vec2(32.));n += 0.03125* generate(uv*vec2(64.));n += 0.015625* generate(uv*vec2(128.));
				uv = st;uv.y = 1.0 - uv.y;uv.x += sin(2.0*pi*n.x+(time*n.z*tim))*n.y*0.1;uv.y += cos(2.0*pi*n.x+(time*n.z*tim))*n.y*0.1;
				vec3 n2 = 0.5* generate(uv*vec2(2.));n2 += 0.25* generate(uv*vec2(8.));n2 += 0.125* generate(uv*vec2(16.));n2 += 0.0625* generate(uv*vec2(32.));n2 += 0.03125* generate(uv*vec2(64.));n2 += 0.015625* generate(uv*vec2(128.));
				uv = st;uv.y = 1.0 - uv.y;int indexX = int(uv.x * WIDTH);int indexY = int(uv.y * HEIGHT);vec2 cor = vec2( (float(indexX) + 0.5) / float(WIDTH), (float(indexY) + 0.5) / HEIGHT );
				vec2 uv2 = vUV;uv2.y = 1.0 - uv2.y;uv2.x += sin(2.0*pi*n.x+(time*n.z*tim))*n.y*0.012;uv2.x = mod(uv2.x,1.0);uv2.y += cos(2.0*pi*n.x+(time*n.z*tim))*n.y*0.012;uv2.y = mod(uv2.y,1.0);
				indexX = int(uv2.x * WIDTH);indexY = int(uv2.y * HEIGHT);cor = vec2( (float(indexX) + 0.5) / WIDTH, (float(indexY) + 0.5) / HEIGHT );
				vec3 adder = mix(n2, texture2D(prevTex, cor).xyz,0.9);
				return adder;
				
		}
		void main() {
		
		float rel = 0.0; 
		vec2 st = vUV;
		if(WIDTH >= HEIGHT){rel = WIDTH/HEIGHT;rel = (rel-1.0)/2.0;st.x = mix(-rel,1.0+rel,st.x);}else{rel = HEIGHT/WIDTH;rel = (rel-1.0)/2.0;st.y = mix(-rel,1.0+rel,st.y);}
		vec2 uv = st;
		
		if(start == 0.){gl_FragColor = vec4(calcCol(uv,st,0.,0.,1.0) ,1.0);}
		
		if(start == 2.){
		  uv = vUV;uv.y = 1.0 - uv.y;int indexX = int(uv.x * WIDTH);int indexY = int(uv.y * HEIGHT);vec2 cor = vec2( (float(indexX) + 0.5) / WIDTH, (float(indexY) + 0.5) / HEIGHT );
      vec4 data = texture2D(imgTex,cor);
			float relH = HEIGHT/1024.;
			vec3 noise = generate(st*5000.*relH );
			vec2 uvs = st;uvs.x += sin((time*0.05)+offset)*0.3;uvs.y += cos((time*0.1)+offset)*0.3;
			
			float dis= distance(uvs,vec2(0.5));dis = smoothstep(0.7, 0.0, dis);  dis = smoothstep(0.0, 1.2, dis);  
			vec3 sharp = 1.-BlurredPixel(uv,5.);vec3 sharpm =mix(data.xyz,sharp,0.5);data.xyz = blendLinearLight(data.xyz, sharpm, sharpness);
			data.xyz = levelRange(data.xyz,0.15,0.85);
			data.xyz = blendSoftLight(data.xyz,noise, 0.35);
			
			if(colr == 0.){data.xyz = channelMixer(vec3(0.56,0.58,-0.33),vec3(0.26,0.83,0.13),vec3(0.21,-0.15,0.64),data.xyz);}
			if(colr == 1.){data.xyz = channelMixer(vec3(0.18,0.26,1.14),vec3(0.05,0.63,0.51),vec3(0.73,0.46,0.17),data.xyz);}
			if(colr == 2.){data.xyz = channelMixer(vec3(0.64,0.58,-0.21),vec3(0.35,0.78,0.12),vec3(0.01,0.01,1.0),data.xyz);}
			if(colr == 3.){data.xyz = channelMixer(vec3(0.15,0.55,0.0),vec3(0.1,0.99,0.26),vec3(0.21,0.35,0.91),data.xyz);}
			if(colr == 4.){data.xyz = channelMixer(vec3(0.38,0.60,0.48),vec3(0.08,0.69,0.48),vec3(0.13,0.07,0.91),data.xyz);data.xyz= rgb2hsv(data.xyz);data.xyz = hsv2rgb(vec3(fract(data.xyz.x+hue),data.xyz.y,data.xyz.z));}
			if(colr == 6.){data.xyz = channelMixer(vec3(x1,x2,x3),vec3(y1,y2,y3),vec3(z1,z2,z3),data.xyz);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.99);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.65);data.xyz = blendSoftLight(data.xyz,vec3(dis), 0.35);}
			if(colr == 7.){data.xyz = channelMixer(vec3(0.571,0.49,0.383),vec3(0.513,0.52,0.45),vec3(0.362,0.533,0.508),data.xyz);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.99);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.65);data.xyz = blendSoftLight(data.xyz,vec3(dis), 0.35);}
			if(colr == 8.){data.xyz = channelMixer(vec3(0.54,0.613,0.574),vec3(0.298,0.328,0.485),vec3(0.491,0.25,0.538),data.xyz);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.99);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.65);data.xyz = blendSoftLight(data.xyz,vec3(dis), 0.35);}
			if(colr == 9.){data.xyz = channelMixer(vec3(0.424,0.507,0.375),vec3(0.26,0.516,0.632),vec3(0.271,0.612,0.562),data.xyz);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.99);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.65);data.xyz = blendSoftLight(data.xyz,vec3(dis), 0.35);}
			if(colr == 10.){data.xyz = channelMixer(vec3(0.468,0.508,0.297),vec3(0.519,0.367,0.648),vec3(0.631,0.319,0.3613),data.xyz);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.99);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.65);data.xyz = blendSoftLight(data.xyz,vec3(dis), 0.35);}
			if(colr == 11.){data.xyz = channelMixer(vec3(0.505,0.552,0.253),vec3(0.3284,0.447,0.381),vec3(0.2703,0.259,0.631),data.xyz);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.99);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.65);data.xyz = blendSoftLight(data.xyz,vec3(dis), 0.35);}
			if(colr == 12.){data.xyz = channelMixer(vec3(0.389,0.314,0.571),vec3(0.438,0.629,0.595),vec3(0.508,0.273,0.366),data.xyz);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.99);data.xyz = blendSoftLight(data.xyz,data.xyz, 0.65);data.xyz = blendSoftLight(data.xyz,vec3(dis), 0.35);}
			float bw = 0.6;
			if(colr != 6.){data.xyz = blendSoftLight(data.xyz,vec3(dis), 0.6);}
			
		  vec3 bandw = channelMixer(vec3(0.0,0.0,0.0),vec3(0.0,0.75,0.0),vec3(0.0,0.0,1.5),data.xyz);bandw = channelMixer(vec3(bw),vec3(bw),vec3(bw),bandw);vec3 mixr = blendSoftLight(data.xyz, bandw, 0.7);gl_FragColor = vec4(mixr ,1.0); 
			if(colr == 5.){gl_FragColor = vec4(bandw,1.0);}

		}
		
	}
	`;
	
	return new p5.Shader(_renderer, vert, frag);
}