(() => {
     "use strict";
     const e = (e, t, n) => ((e, t, n, s, i) => (e - 0) / 255 * (i - s) + s)(e, 0, 0, t, n),
          t = e => {
               let t = 0,
                    n = 0,
                    s = 0;
               4 == e.length ? (t = "0x" + e[1] + e[1], n = "0x" + e[2] + e[2], s = "0x" + e[3] + e[3]) : 7 == e.length && (t = "0x" + e[1] + e[2], n = "0x" + e[3] + e[4], s = "0x" + e[5] + e[6]), t /= 255, n /= 255, s /= 255;
               let i = Math.min(t, n, s),
                    a = Math.max(t, n, s),
                    o = a - i,
                    l = 0,
                    h = 0,
                    c = 0;
               return l = 0 == o ? 0 : a == t ? (n - s) / o % 6 : a == n ? (s - t) / o + 2 : (t - n) / o + 4, l = Math.round(60 * l), l < 0 && (l += 360), c = (a + i) / 2, h = 0 == o ? 0 : o / (1 - Math.abs(2 * c - 1)), h = +(100 * h).toFixed(1), c = +(100 * c).toFixed(1), {
                    h: l,
                    s: h,
                    l: c
               }
          },
          n = (e, t) => {
               let n = 0;
               return t.find((t => (n += t.chance, n >= e))) || t[t.length - 1]
          },
          s = (e, t, n) => Math.max(t, Math.min(n, e)),
          i = ["#C51F33", "#F38316", "#F9B807", "#FBD46A", "#2D5638", "#418052", "#58B271", "#9ED78E", "#1B325F", "#2A4DA8", "#2B94E1", "#92C7D3", "#E84A62", "#ED7889", "#F3A5B0", "#0E0F0D", "#E5E5E5"];
     class a {
          constructor(e = 0, t = 0, n = 0) {
               return this.x = e, this.y = t, this.z = n, this
          }
          clone() {
               return new a(this.x, this.y, this.z)
          }
          add(e) {
               return this.x += e.x, this.y += e.y, this.z += e.z, this
          }
          addVectors(e, t) {
               return this.x = e.x + t.x, this.y = e.y + t.y, this.z = e.z + t.z, this
          }
          subVectors(e, t) {
               return this.x = e.x - t.x, this.y = e.y - t.y, this.z = e.z - t.z, this
          }
          multiplyScalar(e) {
               return isFinite(e) ? (this.x *= e, this.y *= e, this.z *= e) : (this.x = 0, this.y = 0, this.z = 0), this
          }
          length() {
               return Math.sqrt(this.x * this.x + this.y * this.y + this.z * this.z)
          }
     }
     const o = a;
     let l = (e => {
               let t = [];
               for (let n = 0; n < 32; n++) t.push(e.hash.slice(2 + 2 * n, 4 + 2 * n));
               return t.map((e => parseInt(e, 16)))
          })(tokenData),
          h = (c = tokenData, parseInt(c.hash.slice(0, 8), 16));
     var c;
     let r = new class {
          constructor(e) {
               this.seed = e
          }
          random() {
               return this.seed ^= this.seed << 13, this.seed ^= this.seed >> 17, this.seed ^= this.seed << 5, (this.seed < 0 ? 1 + ~this.seed : this.seed) % 1e3 / 1e3
          }
     }(h);
     const d = "AlgoRhythms#" + ~~tokenData.tokenId.substr(tokenData.tokenId.length - 4);
     let u, y, m, x, w, v, g, p, b, C, k, f;
     const z = 2 * Math.PI / 3,
          T = .5 * Math.PI / 3,
          M = .015,
          F = 1200;
     let S, P, A, D = .1,
          E = 0,
          I = 0,
          G = 0,
          B = 0,
          $ = 0,
          N = 0,
          O = 0,
          L = {
               startTime: -1,
               value: 0
          },
          R = !1,
          W = 0,
          H = [],
          j = [],
          q = r.random() < .5;
     const V = [{
               name: "Procedural",
               chance: .97,
               value: 0
          }, {
               name: "Full",
               chance: .002,
               value: 1
          }, {
               name: "Line",
               chance: .01,
               value: 2
          }, {
               name: "Diagonal",
               chance: .008,
               value: 3
          }, {
               name: "X",
               chance: .004,
               value: 4
          }, {
               name: "Plus",
               chance: .006,
               value: 5
          }],
          J = [{
               name: "Full",
               chance: .1,
               value: 0
          }, {
               name: "Tall",
               chance: .35,
               value: 1
          }, {
               name: "Medium",
               chance: .35,
               value: 2
          }, {
               name: "Short",
               chance: .2,
               value: 3
          }],
          Q = [{
               name: "None",
               chance: .4,
               value: 0
          }, {
               name: "Small",
               chance: .3,
               value: .0075
          }, {
               name: "Big",
               chance: .3,
               value: .02
          }],
          U = [{
               name: "Solid",
               chance: .3,
               value: 0
          }, {
               name: "Tube",
               chance: .3,
               value: 1
          }, {
               name: "Mix",
               chance: .4,
               value: 2
          }],
          X = [{
               name: "Color",
               chance: .6,
               value: 0
          }, {
               name: "Wireframe",
               chance: .05,
               value: 1
          }, {
               name: "Black Outline",
               chance: .25,
               value: 2
          }, {
               name: "White Outline",
               chance: .1,
               value: 3
          }],
          Y = [{
               name: "Sine",
               chance: .4,
               value: "sine",
               index: 0
          }, {
               name: "Square",
               chance: .2,
               value: "square",
               index: 1
          }, {
               name: "Sawtooth",
               chance: .3,
               value: "sawtooth",
               index: 2
          }, {
               name: "Triangle",
               chance: .1,
               value: "triangle",
               index: 3
          }],
          K = [{
               name: "Adagio (60bpm)",
               chance: .25,
               value: 60
          }, {
               name: "Moderato (90bpm)",
               chance: .6,
               value: 90
          }, {
               name: "Allegro (120bpm)",
               chance: .15,
               value: 120
          }],
          Z = [{
               name: "Procedural",
               chance: .98,
               value: 0
          }, {
               name: "Lined",
               chance: .01,
               value: 1
          }, {
               name: "Diagonal",
               chance: .006,
               value: 2
          }, {
               name: "Circled",
               chance: .004,
               value: 3
          }],
          _ = n(e(l[5], 0, 1), [{
               chance: .02,
               scales: {
                    A: ["A"],
                    B: ["B"],
                    C: ["C"],
                    D: ["D"],
                    E: ["E"],
                    F: ["F"],
                    G: ["G"]
               }
          }, {
               chance: .03,
               scales: {
                    "Third & Sixth": ["A", "F"]
               }
          }, {
               chance: .05,
               scales: {
                    Quartal: ["G", "C", "F"],
                    Minor9: ["D", "D#", "A#"]
               }
          }, {
               chance: .1,
               scales: {
                    "Ritsu (Japanese)": ["A", "B", "C", "E"],
                    "Balinese (Indonesian)": ["B", "C", "F#", "G"],
                    "Major Pentatonic-4": ["F#", "G#", "A#", "C#"]
               }
          }, {
               chance: .15,
               scales: {
                    "Major Pentatonic": ["C", "D", "E", "G", "A"],
                    "Minor Pentatonic": ["A", "C", "D", "E", "G"],
                    "Han Iwato": ["G", "G#", "C", "D", "F"],
                    "Yamatebala Wofe (Ethiopia)": ["F#", "G#", "B", "C#", "E"]
               }
          }, {
               chance: .25,
               scales: {
                    "Major Blues from C": ["C", "D", "D#", "E", "G", "A"],
                    Satie: ["A", "B", "C", "D#", "E", "F#"],
                    "C# Aeolian": ["C#", "D#", "E", "F#", "G#", "A"],
                    "Minor Pentatonic+A": ["G", "A", "A#", "C", "D", "F"],
                    "Whole Tone": ["C#", "D#", "F", "G", "A", "B"]
               }
          }, {
               chance: .4,
               scales: {
                    "Harmonic Minor": ["C#", "D#", "E", "F#", "G#", "A", "C"],
                    "Hungarian Minor": ["A#", "C", "C#", "E", "F", "G", "G#"],
                    "Spanish minor": ["G", "G#", "A#", "C", "C#", "E", "F"],
                    "E Aeolian": ["E", "F#", "G", "A", "B", "C", "D#"],
                    "Todi That (Indian)": ["B", "C", "D", "F", "F#", "G", "A#"],
                    "Hijazkar (Middle Eastern)": ["A", "A#", "C#", "D", "E", "F", "G#"]
               }
          }]),
          ee = Object.keys(_.scales)[~~e(l[6], 0, Object.keys(_.scales).length - .01)],
          te = ~~e(l[10], 1, 4.99),
          ne = ~~e(l[11], 1, 4 - Math.max(0, te - 2) + .99),
          se = [],
          ie = t(i.splice(~~(r.random() * i.length), 1)[0]);
     for (let e = 0; e < _.scales[ee].length; e++) {
          const e = t(i.splice(~~(r.random() * i.length), 1)[0]);
          se.push(e)
     }
     function ae() {
          x = window.innerWidth, w = window.innerHeight, p = window.devicePixelRatio, g = Math.min(x, w), v = .36 * g, b = 2 * g / F, C = 1 * g / F, k = .5 * g / F, f = 80 * g / F, u.width = ~~(x * p), u.height = ~~(w * p), u.style.width = `${x}px`, u.style.height = `${w}px`
     }

     function oe(e) {
          if ("s" == e.key) {
               var t = u.toDataURL("image/png");
               const e = document.createElement("a");
               e.download = `${d}.png`, e.href = t, e.click()
          }
     }

     function le() {
          if (!R) {
               R = !0;
               for (let e = 0; e < H.length; e++) H[e].block.highlight.value = 0;
               L.startTime = E, "running" !== Tone.context.state && Tone.context.resume(), Tone.start(), Tone.Transport.start()
          }
     }
     class he {
          constructor(e, t, n, s) {
               this.coords = e, this.coords2d = ce(this.coords), this.screenCoords = t, this.level = s, this.capacity = n, this.points = [], this.divided = !1, this.baseCenter = this.getCenter(), this.center = this.baseCenter.clone(), this.on = 1 != m.musicRests || r.random() > .2, this.holey = 2 == ~~m.blocksType ? r.random() > .5 : ~~m.blocksType, this.stroke = !this.on, this.noteIndex = 0, this.octaveIndex = 0, this.height = 0, this.playing = !1, this.startTime = 0, this.highlight = {
                    value: 0
               }
          }
          setNotes() {
               if (this.divided) this.nw.setNotes(), this.ne.setNotes(), this.sw.setNotes(), this.se.setNotes();
               else {
                    const e = ~~(16 * (this.center.x + .5)),
                         t = ~~(16 * (this.center.z + .5));
                    if (0 == W) this.noteIndex = 0;
                    else if (0 == m.musicPattern) this.noteIndex = ~~(r.random() * m.musicScale.length);
                    else if (1 == m.musicPattern) this.noteIndex = q ? e % m.musicScale.length : t % m.musicScale.length;
                    else if (2 == m.musicPattern) this.noteIndex = q ? (e + t) % m.musicScale.length : Math.abs(e - t) % m.musicScale.length;
                    else {
                         const n = new o(e - 8, t - 8, 0);
                         this.noteIndex = ~~n.length() % m.musicScale.length
                    }
                    this.octaveIndex = ~~(r.random() * m.musicOctaveCount), this.height = 1 - this.octaveIndex / m.musicOctaveCount, this.center = this.getCenter(), this.updateColor(), W++
               }
          }
          updateLastNote() {
               this.divided ? this.se.updateLastNote() : (this.noteIndex = 0, this.octaveIndex = 0, this.updateColor())
          }
          updateColor() {
               const e = m.palette.colors[this.noteIndex % m.palette.colors.length];
               this.color = `hsl(${e.h}, ${e.s}%, ${e.l+6}%)`, this.lightColor = `hsl(${e.h}, ${e.s}%, ${e.l+12}%)`, this.darkColor = `hsl(${e.h}, ${e.s}%, ${e.l}%)`
          }
          addNote() {
               if (this.divided) this.nw.addNote(), this.ne.addNote(), this.sw.addNote(), this.se.addNote();
               else {
                    let e = "2n + 2n";
                    this.level >= 1 && (e = `${Math.pow(2,this.level)}n`), O = Tone.Time(e).toSeconds();
                    const t = `${m.musicScale[this.noteIndex]}${m.musicStartingOctave+this.octaveIndex}`;
                    this.on ? (H.push({
                         time: N,
                         note: t,
                         duration: e,
                         block: this
                    }), j.push({
                         note: m.musicScale[this.noteIndex],
                         octave: m.musicStartingOctave + this.octaveIndex,
                         level: this.level,
                         duration: e
                    })) : j.push({
                         note: "rest",
                         duration: e
                    }), N += O
               }
          }
          getCenter() {
               const e = (new o).subVectors(this.coords[6], this.coords[0]).multiplyScalar(.5),
                    t = (new o).addVectors(this.coords[0], e);
               return t.x = Math.min(this.coords[6].x - 0, Math.max(this.coords[0].x + 0, t.x)), t.y = Math.max(this.coords[6].y + 0, Math.min(this.coords[0].y - 0, t.y)), t.z = Math.max(this.coords[6].z + 0, Math.min(this.coords[0].z - 0, t.z)), t
          }
          insert(e) {
               if (!(e.x >= this.screenCoords.x * x && e.x < (this.screenCoords.x + this.screenCoords.w) * x && e.y >= this.screenCoords.y * w && e.y < (this.screenCoords.y + this.screenCoords.h) * w)) return !1;
               if (this.level + 1 <= 4)
                    if (this.divided) {
                         if (this.nw.insert(e)) return !0;
                         if (this.ne.insert(e)) return !0;
                         if (this.sw.insert(e)) return !0;
                         if (this.se.insert(e)) return !0
                    } else this.subdivide()
          }
          subdivide() {
               const e = this.level + 1;
               e > $ && ($ = e);
               const {
                    ne: t,
                    nw: n,
                    se: s,
                    sw: i
               } = function(e, t) {
                    const n = v * (m.blocksMargin / v),
                         s = [new o(e[0].x, e[0].y, t.z - n), new o(t.x - n, e[1].y, t.z - n), new o(t.x - n, e[2].y, e[3].z), new o(e[3].x, e[3].y, e[3].z), new o(e[4].x, e[4].y, t.z - n), new o(t.x - n, e[5].y, t.z - n), new o(t.x - n, e[6].y, e[6].z), new o(e[7].x, e[7].y, e[7].z)],
                         i = [new o(t.x + n, e[0].y, t.z - n), new o(e[1].x, e[1].y, t.z - n), new o(e[2].x, e[2].y, e[2].z), new o(t.x + n, e[3].y, e[3].z), new o(t.x + n, e[4].y, t.z - n), new o(e[5].x, e[5].y, t.z - n), new o(e[6].x, e[6].y, e[6].z), new o(t.x + n, e[7].y, e[7].z)],
                         a = [new o(e[0].x, e[0].y, e[0].z), new o(t.x - n, e[1].y, e[1].z), new o(t.x - n, e[2].y, t.z + n), new o(e[3].x, e[3].y, t.z + n), new o(e[4].x, e[4].y, e[4].z), new o(t.x - n, e[5].y, e[5].z), new o(t.x - n, e[6].y, t.z + n), new o(e[7].x, e[7].y, t.z + n)];
                    return {
                         nw: s,
                         ne: i,
                         se: [new o(t.x + n, e[0].y, e[0].z), new o(e[1].x, e[1].y, e[1].z), new o(e[2].x, e[2].y, t.z + n), new o(t.x + n, e[3].y, t.z + n), new o(t.x + n, e[4].y, e[4].z), new o(e[5].x, e[5].y, e[5].z), new o(e[6].x, e[6].y, t.z + n), new o(t.x + n, e[7].y, t.z + n)],
                         sw: a
                    }
               }(this.coords, this.center), a = function(e) {
                    const t = .5 * e.w,
                         n = .5 * e.h;
                    return {
                         nw: {
                              x: e.x,
                              y: e.y,
                              w: t,
                              h: n
                         },
                         ne: {
                              x: e.x + t,
                              y: e.y,
                              w: t,
                              h: n
                         },
                         se: {
                              x: e.x + t,
                              y: e.y + n,
                              w: t,
                              h: n
                         },
                         sw: {
                              x: e.x,
                              y: e.y + n,
                              w: t,
                              h: n
                         }
                    }
               }(this.screenCoords);
               this.ne = new he(t, a.ne, this.capacity, e), this.nw = new he(n, a.nw, this.capacity, e), this.se = new he(s, a.se, this.capacity, e), this.sw = new he(i, a.sw, this.capacity, e), this.divided = !0
          }
          update() {
               var e;
               if (this.playing)
                    if (this.divided) this.ne.update(), this.nw.update(), this.sw.update(), this.se.update();
                    else {
                         let t = s(E - this.startTime, 0, .5) / .5,
                              n = (e = t, 1 + 4 * Math.pow(e - 1, 3) + 3 * Math.pow(e - 1, 2));
                         this.highlight.value = n, t >= 1 && (this.playing = !1)
                    }
          }
          draw(e) {
               this.divided ? (this.nw.draw(e), this.ne.draw(e), this.sw.draw(e), this.se.draw(e)) : (e.strokeStyle = 1 == m.blocksStyle ? this.darkColor : m.palette.stroke, this.on && this.drawCube(e, m.blocksStyle >= 1, 1 == m.blocksStyle))
          }
          drawCube(e, t = !1, n = !1) {
               const s = ce(this.coords, this.highlight.value, this.height);
               if (e.fillStyle = n ? m.palette.background : this.darkColor, e.beginPath(), e.moveTo(s[1].x - 1, s[2].y), e.lineTo(s[2].x, s[2].y), e.lineTo(s[6].x, s[6].y), e.lineTo(s[5].x, s[5].y), e.lineTo(s[5].x - 1, s[5].y - 1), e.closePath(), e.fill(), t && e.stroke(), e.fillStyle = n ? m.palette.background : this.color, e.beginPath(), e.lineTo(s[1].x, s[0].y), e.lineTo(s[0].x, s[0].y), e.lineTo(s[4].x, s[4].y), e.lineTo(s[5].x, s[5].y), e.closePath(), e.fill(), t && e.stroke(), e.fillStyle = n ? m.palette.background : this.lightColor, e.beginPath(), e.moveTo(s[0].x, s[0].y), e.lineTo(s[1].x, s[1].y), e.lineTo(s[2].x, s[2].y), e.lineTo(s[3].x, s[3].y), e.closePath(), e.fill(), t && e.stroke(), e.beginPath(), e.moveTo(s[0].x, s[0].y), e.lineTo(s[3].x, s[3].y), e.lineTo(s[2].x, s[2].y), e.lineTo(s[6].x, s[6].y), e.lineTo(s[5].x, s[5].y), e.lineTo(s[4].x, s[4].y), e.closePath(), t && (e.lineWidth = b, e.stroke(), e.lineWidth = C), this.holey) {
                    const s = [];
                    s[0] = this.coords[0].clone().add(new o(M, 0, -.015)), s[1] = this.coords[1].clone().add(new o(-.015, 0, -.015)), s[2] = this.coords[2].clone().add(new o(-.015, 0, M)), s[3] = this.coords[3].clone().add(new o(M, 0, M));
                    const i = ce(s, this.highlight.value, this.height);
                    e.lineWidth = k, e.fillStyle = n ? m.palette.background : this.color, e.beginPath(), e.lineTo(i[1].x, i[1].y), e.lineTo(i[2].x, i[2].y), e.lineTo(i[3].x, i[3].y), e.fill(), t && e.stroke(), e.fillStyle = n ? m.palette.background : this.darkColor, e.beginPath(), e.moveTo(i[0].x, i[0].y), e.lineTo(i[1].x, i[1].y), e.lineTo(i[3].x, i[3].y), e.closePath(), e.fill(), t && e.stroke(), e.lineWidth = C
               }
          }
     }

     function ce(e, t = 0, n = 0) {
          const s = [];
          for (let a = 0; a < e.length; a++) s[a] = (i = e[a].clone().multiplyScalar(v), new o(i.x * Math.cos(T) + i.z * Math.cos(T + z) + i.y * Math.cos(T - z), i.x * Math.sin(T) + i.z * Math.sin(T + z) + i.y * Math.sin(T - z), 0)), s[a].y -= t * f, s[a].y += L.value * f, a >= 4 ? s[a].y -= n * (m.blocksHeight * (v / 4)) * .5 : s[a].y += m.blocksHeight * (v / 4) * .5;
          var i;
          return s
     }

     function re() {
          I = Date.now(), G = I - B, B = I, E += G / 1e3, requestAnimationFrame(re),
               function() {
                    if (R) {
                         let e = s(E - L.startTime, 0, D) / D;
                         if (L.value = e, L.value >= 1) {
                              let e = !0;
                              for (let t = 0; t < H.length; t++) H[t].block.playing && (e = !1);
                              e && (Tone.Transport.stop(), R = !1)
                         }
                    }
                    y.save(), y.scale(p, p), y.clearRect(0, 0, x, w), y.globalCompositeOperation = "source-over", y.save(), y.translate(.5 * x, .5 * w);
                    for (let e = 0; e < H.length; e++) H[e].block.update();
                    S.draw(y), y.restore(), y.globalCompositeOperation = "destination-over", y.fillStyle = m.palette.background, y.fillRect(0, 0, x, w), y.restore()
               }()
     }
     window.onload = function() {
          document.title = d,
               function() {
                    u = document.createElement("canvas"), y = u.getContext("2d"), document.body.appendChild(u), ae(), m = {
                         subdivisionsCount: ~~e(l[0], 0, 100),
                         subdivisionsPattern: n(e(l[12], 0, 1), V).value,
                         blocksHeight: n(e(l[1], 0, 1), J).value,
                         blocksMargin: n(e(l[2], 0, 1), Q).value,
                         blocksType: n(e(l[3], 0, 1), U).value,
                         blocksStyle: n(e(l[4], 0, 1), X).value,
                         musicScale: _.scales[ee],
                         musicOscillator: n(e(l[7], 0, 1), Y).value,
                         musicBpm: n(e(l[8], 0, 1), K).value,
                         musicRests: e(l[9], 0, 1) < .25,
                         musicStartingOctave: te,
                         musicOctaveCount: ne,
                         musicPattern: n(e(l[13], 0, 1), Z).value,
                         palette: {
                              background: `hsl(${ie.h}, ${ie.s}%, ${ie.l}%)`,
                              stroke: "#0E0F0D",
                              colors: se
                         }
                    }, 3 == m.blocksStyle && (m.palette.stroke = "#FFFFFF");
                    const t = [new o(-.5, .5, .5), new o(.5, .5, .5), new o(.5, .5, -.5), new o(-.5, .5, -.5), new o(-.5, -.5, .5), new o(.5, -.5, .5), new o(.5, -.5, -.5), new o(-.5, -.5, -.5)];
                    S = new he(t, {
                         x: 0,
                         y: 0,
                         w: 1,
                         h: 1
                    }, 1, 0);
                    let s = m.subdivisionsCount;
                    0 != m.subdivisionsPattern ? s = 1e3 : 0 != m.musicPattern && (s = 100);
                    for (let e = 0; e < s; e++) {
                         let e, t;
                         if (m.subdivisionsPattern <= 1) e = r.random() * x, t = r.random() * w;
                         else if (2 == m.subdivisionsPattern || 5 == m.subdivisionsPattern)(5 == m.subdivisionsPattern ? r.random() < .5 : q) ? (e = .1 * r.random() - .05 + .5 * x, t = r.random() * w) : (e = r.random() * x, t = .1 * r.random() - .05 + .5 * w);
                         else {
                              let n = 4 == m.subdivisionsPattern ? r.random() < .5 : q,
                                   s = r.random();
                              n ? (e = s * x, t = s * w) : (e = s * x, t = w - s * w)
                         }
                         S.insert(new o(e, t, 0))
                    }
                    S.setNotes(), S.updateLastNote(), P = new Tone.PolySynth(Tone.MonoSynth, {
                         volume: -8,
                         oscillator: {
                              type: `${m.musicOscillator}8`,
                              modulationFrequency: .2
                         },
                         envelope: {
                              attack: .01,
                              decay: .3,
                              sustain: .2,
                              release: .4
                         },
                         filterEnvelope: {
                              attack: .001,
                              decay: .7,
                              sustain: .1,
                              release: .8,
                              baseFrequency: 300
                         }
                    }).toDestination(), Tone.Transport.bpm.value = m.musicBpm, S.addNote(), A = new Tone.Part(((e, t) => {
                         P.triggerAttackRelease(t.note, t.duration, e), t.block.startTime = E, t.block.playing = !0
                    }), H).start(0), D = N, document.addEventListener("click", le), document.addEventListener("touchstart", le), document.addEventListener("keydown", oe), window.addEventListener("resize", ae)
               }(), re()
     }
})();