let R, w, h, sc, dx, dy;
let p1, p2, p3, p4, n1, n2, n3, n4;
let p1rgb, p2rgb, p3rgb, p4rgb, prgb;
let cols, rows, acols, arows, cparam, rparam;
let blend, gaps, gaxis, gmap, cstarts, csizes, lcdim, lrdim, angles, cdata;
let mx, my, cw, ch;
let pc, grid, colgap, rowgap;
let a1, a2, a3, a4, r, g, b;
let sel, ci, hues, maxarc;
let phase = 'blend';
let plotqs, pi, plotqi, plott;
let plotmode = 'draw';
let tfx, tfy, ttx, tty, tlen, talong;
let plotskip = false;
let complete = false;
let baseips = 1;
let tmult = 2;
let pmult = 1;
let angs = [22.5, 67.5, 112.5, 157.5];
let curve = 1.4;
let spacing = 1 / 30;
let lw = 1 / 32;
let la = 128;
let threshold = 60;
let opacity = 0.46;
let phsb = [45, 3, 99];
let pw = 12;
let ph = 9;
let iw = 10;
let ih = 7;
let grids = [
  [3, 23], [4, 17], [5, 14], [6, 13], [7, 10], [8, 9], 
  [9, 8], [10, 7], [13, 6], [14, 5], [17, 4], [23, 3]
];
let pencils = [
  { hsb: [359, 78, 85], name: "070 Scarlet" },
  { hsb: [10, 79, 97], name: "060 Vermilion" },
  { hsb: [19, 80, 100], name: "040 Reddish Orange" },
  { hsb: [33, 97, 100], name: "030 Orange" },
  { hsb: [38, 99, 100], name: "300 Fast Orange" },
  { hsb: [45, 100, 100], name: "020 Golden Yellow" },
  { hsb: [50, 100, 100], name: "010 Yellow" },
  { hsb: [54, 77, 97], name: "250 Canary Yellow" },
  { hsb: [59, 68, 94], name: "240 Lemon Yellow" },
  { hsb: [71, 65, 90], name: "470 Spring Green" },
  { hsb: [95, 60, 88], name: "230 Yellow Green" },
  { hsb: [163, 100, 69], name: "201 Veronese Green" },
  { hsb: [180, 100, 73], name: "191 Turquoise Green" },
  { hsb: [189, 100, 81], name: "171 Turquoise Blue" },
  { hsb: [200, 93, 88], name: "161 Light Blue" },
  { hsb: [205, 100, 75], name: "370 Gentian Blue" },
  { hsb: [209, 100, 63], name: "260 Blue" },
  { hsb: [236, 69, 56], name: "140 Ultramarine" },
  { hsb: [243, 51, 56], name: "130 Royal Blue" },
  { hsb: [261, 54, 48], name: "120 Violet" },
  { hsb: [297, 46, 54], name: "110 Lilac" },
  { hsb: [325, 61, 66], name: "100 Purple Violet" },
  { hsb: [343, 80, 79], name: "080 Carmine" },
  { hsb: [352, 77, 88], name: "280 Ruby Red" },
];

function setup() {
  R = new Random(tokenData.hash);
  colorMode(HSB);
  let retry = true;
  while (retry) {
    let avail = [];
    for (let i = 0; i < pencils.length; i++) {
      avail.push(i);
    }
    let picked = [];
    for (let i = 0; i < 4; i++) {
      let idx = R.random_int(0, avail.length - 1);
      picked.push(avail.splice(idx, 1)[0]);
    }
    sel = [];
    for (let i = 0; i < picked.length; i++) {
      let m = pencils[picked[i]];
      sel.push({ c: color(m.hsb[0], m.hsb[1], m.hsb[2]), name: m.name, mi: picked[i] });
    }
    sel.sort(function(a, b) {
      return hue(a.c) - hue(b.c);
    });
    let rot = R.random_int(0, 3);
    for (let i = 0; i < rot; i++) {
      sel.push(sel.shift());
    }
    if (R.random_bool(0.5)) {
      sel.reverse();
    }
    ci = [];
    for (let i = 0; i < sel.length; i++) {
      ci.push(sel[i].mi);
    }
    retry = false;
    let nm = pencils.length;
    for (let i = 0; i < ci.length; i++) {
      let j = (i + 1) % ci.length;
      let d = abs(ci[i] - ci[j]);
      if (d === 1 || d === nm - 1) {
        retry = true;
      }
    }
    hues = [];
    for (let i = 0; i < sel.length; i++) {
      hues.push(round(hue(sel[i].c)));
    }
    hues.sort(function(a, b) {
      return a - b;
    });
    maxarc = 360 - hues[hues.length - 1] + hues[0];
    for (let i = 1; i < hues.length; i++) {
      let arc = hues[i] - hues[i - 1];
      if (arc > maxarc) {
        maxarc = arc;
      }
    }
    if (maxarc > 210) {
      retry = true;
    }
  }
  p1 = sel[0].c;
  p2 = sel[1].c;
  p3 = sel[2].c;
  p4 = sel[3].c;
  n1 = sel[0].name;
  n2 = sel[1].name;
  n3 = sel[2].name;
  n4 = sel[3].name;
  p1rgb = [red(p1), green(p1), blue(p1)];
  p2rgb = [red(p2), green(p2), blue(p2)];
  p3rgb = [red(p3), green(p3), blue(p3)];
  p4rgb = [red(p4), green(p4), blue(p4)];
  pc = color(phsb[0], phsb[1], phsb[2]);
  prgb = [red(pc), green(pc), blue(pc)];
  grid = grids[R.random_int(0, grids.length - 1)];
  cols = grid[0];
  rows = grid[1];
  mx = (pw - iw) / 2;
  my = (ph - ih) / 2;
  cw = iw / cols;
  ch = ih / rows;
  colgap = false;
  rowgap = false;
  for (let i = 1; i <= 3; i++) {
    if ((cols - i) % (i + 1) === 0 && (cols - i) / (i + 1) >= 3) {
      colgap = true;
    }
    if ((rows - i) % (i + 1) === 0 && (rows - i) / (i + 1) >= 3) {
      rowgap = true;
    }
  }
  if (colgap && (!rowgap || cw > ch || (cw === ch && R.random_bool(0.5)))) {
    acols = activeIdx(cols);
    arows = [];
    for (let i = 0; i < rows; i++) {
      arows.push(i);
    }
    gaps = true;
    gaxis = 'cols';
  } else if (rowgap) {
    acols = [];
    for (let i = 0; i < cols; i++) {
      acols.push(i);
    }
    arows = activeIdx(rows);
    gaps = true;
    gaxis = 'rows';
  } else {
    acols = [];
    for (let i = 0; i < cols; i++) {
      acols.push(i);
    }
    arows = [];
    for (let i = 0; i < rows; i++) {
      arows.push(i);
    }
    gaps = false;
  }
  if (gaps) {
    let gidx;
    if (gaxis === 'cols') {
      gidx = acols;
    } else {
      gidx = arows;
    }
    gmap = [];
    let grp = 0;
    for (let i = 0; i < gidx.length; i++) {
      if (i > 0 && gidx[i] !== gidx[i - 1] + 1) {
        grp++;
      }
      gmap.push(grp);
    }
    cstarts = [];
    csizes = [];
    let prev = -1;
    for (let i = 0; i < gmap.length; i++) {
      let cl = gmap[i];
      if (cl !== prev) {
        cstarts[cl] = i;
        csizes[cl] = 0;
        prev = cl;
      }
      csizes[cl]++;
    }
  }
  let ngaps = 0;
  if (gaps) {
    ngaps = gmap[gmap.length - 1];
  }
  let smallgrp = false;
  if (gaps) {
    let total;
    if (gaxis === 'cols') {
      total = cols;
    } else {
      total = rows;
    }
    if ((total - ngaps) / (ngaps + 1) <= 3) {
      smallgrp = true;
    }
  }
  if (smallgrp || R.random_bool(0.5)) {
    blend = 'continuous';
  } else {
    let tr = ['repeat', 'reflect', 'inverse', 'rotate'];
    if (ngaps === 1) {
      let f = [];
      for (let i = 0; i < tr.length; i++) {
        if (tr[i] !== 'inverse') {
          f.push(tr[i]);
        }
      }
      tr = f;
    }
    if (ngaps === 2) {
      let f = [];
      for (let i = 0; i < tr.length; i++) {
        if (tr[i] !== 'reflect' && tr[i] !== 'rotate') {
          f.push(tr[i]);
        }
      }
      tr = f;
    }
    blend = tr[R.random_int(0, tr.length - 1)];
  }
  if (gaxis === 'cols') {
    lcdim = csizes[0];
    lrdim = arows.length;
  } else if (gaxis === 'rows') {
    lcdim = acols.length;
    lrdim = csizes[0];
  } else {
    lcdim = acols.length;
    lrdim = arows.length;
  }
  cparam = blendParams(acols, blend);
  rparam = blendParams(arows, blend);
  angs = scramble(angs);
  angles = { p1: angs[0], p2: angs[1], p3: angs[2], p4: angs[3] };
  cdata = {};
  cdata.p1 = buildCells('p1');
  cdata.p2 = buildCells('p2');
  cdata.p3 = buildCells('p3');
  cdata.p4 = buildCells('p4');
  console.log('P1: ' + n1);
  console.log('P2: ' + n2);
  console.log('P3: ' + n3);
  console.log('P4: ' + n4);
  window.$features = { P1: n1, P2: n2, P3: n3, P4: n4 };
  if (windowWidth / windowHeight > pw / ph) {
    sc = windowHeight / ph;
  } else {
    sc = windowWidth / pw;
  }
  w = windowWidth;
  h = windowHeight;
  dx = (w - pw * sc) / 2;
  dy = (h - ph * sc) / 2;
  createCanvas(w, h);
  colorMode(RGB);
  strokeWeight(lw * sc);
  strokeCap(SQUARE);
  noLoop();
}

function draw() {
  background(prgb[0], prgb[1], prgb[2]);
  if (phase === 'anim') {
    let dt = deltaTime / 1000;
    if (dt <= 0) {
      dt = 1 / 60;
    }
    if (dt > 1 / 15) {
      dt = 1 / 15;
    }
    if (plotskip) {
      plotskip = false;
      dt = 0;
    }
    let drem = baseips * pmult * dt;
    let trem = baseips * pmult * tmult * dt;
    let active = true;
    while (active && phase === 'anim') {
      let q = plotqs[pi];
      let n = q.length;
      if (plotmode === 'draw') {
        if (plotqi >= n || drem <= 0) {
          active = false;
        } else {
          let l = q[plotqi];
          let len = dist(l.x1, l.y1, l.x2, l.y2);
          let remain = (1 - plott) * len;
          if (drem >= remain) {
            drem -= remain;
            plott = 0;
            let ln = null;
            if (plotqi + 1 < n) {
              ln = q[plotqi + 1];
            } else if (pi + 1 < plotqs.length) {
              ln = plotqs[pi + 1][0];
              plotqi = n;
            }
            if (ln) {
              plotmode = 'transit';
              setupTransit(l.x2, l.y2, ln.x1, ln.y1);
            } else {
              plotqi = n;
              plotmode = 'home_out';
              setupTransit(l.x2, l.y2, 0, ph);
            }
          } else {
            plott += drem / len;
            drem = 0;
          }
        }
      } else if (plotmode === 'transit' || plotmode === 'home_in' || plotmode === 'home_out') {
        if (trem <= 0) {
          active = false;
        } else {
          let remain = tlen - talong;
          if (trem >= remain) {
            trem -= remain;
            talong = tlen;
            if (plotmode === 'transit') {
              if (plotqi >= n) {
                pi++;
                plotqi = 0;
              } else {
                plotqi++;
              }
              plotmode = 'draw';
              plott = 0;
            } else if (plotmode === 'home_in') {
              plotmode = 'draw';
              plott = 0;
            } else {
              phase = 'done';
              complete = true;
              noLoop();
            }
          } else {
            talong += trem;
            trem = 0;
          }
        }
      }
    }
  }
  if (phase === 'blend') {
    noStroke();
    for (let j = 0; j < arows.length; j++) {
      for (let i = 0; i < acols.length; i++) {
        let nx = cparam[i];
        let ny = rparam[j];
        if ((blend === 'inverse' || blend === 'rotate') && gaps) {
          let grp;
          if (gaxis === 'cols') {
            grp = gmap[i];
          } else {
            grp = gmap[j];
          }
          if (grp % 2 === 1) {
            if (gaxis === 'cols') {
              ny = 1 - ny;
            } else {
              nx = 1 - nx;
            }
          }
        }
        a1 = opacity * (1 - pow(1 - (1 - nx) * (1 - ny), curve));
        a2 = opacity * (1 - pow(1 - nx * (1 - ny), curve));
        a3 = opacity * (1 - pow(1 - nx * ny, curve));
        a4 = opacity * (1 - pow(1 - (1 - nx) * ny, curve));
        r = prgb[0];
        g = prgb[1];
        b = prgb[2];
        r = lerp(r, p1rgb[0], a1);
        g = lerp(g, p1rgb[1], a1);
        b = lerp(b, p1rgb[2], a1);
        r = lerp(r, p2rgb[0], a2);
        g = lerp(g, p2rgb[1], a2);
        b = lerp(b, p2rgb[2], a2);
        r = lerp(r, p3rgb[0], a3);
        g = lerp(g, p3rgb[1], a3);
        b = lerp(b, p3rgb[2], a3);
        r = lerp(r, p4rgb[0], a4);
        g = lerp(g, p4rgb[1], a4);
        b = lerp(b, p4rgb[2], a4);
        fill(r, g, b);
        rect((mx + acols[i] * cw) * sc + dx, (my + arows[j] * ch) * sc + dy, cw * sc + 1, ch * sc + 1);
      }
    }
  }
  if (phase === 'anim' || phase === 'done') {
    let crgbs = [p1rgb, p2rgb, p3rgb, p4rgb];
    noFill();
    for (let li = 0; li < pi; li++) {
      let q = plotqs[li];
      let rgb = crgbs[li];
      stroke(rgb[0], rgb[1], rgb[2], la);
      for (let qi = 0; qi < q.length; qi++) {
        let l = q[qi];
        line(l.x1 * sc + dx, l.y1 * sc + dy, l.x2 * sc + dx, l.y2 * sc + dy);
      }
    }
    let q = plotqs[pi];
    let n = q.length;
    let rgb = crgbs[pi];
    stroke(rgb[0], rgb[1], rgb[2], la);
    let through = plotqi;
    if (plotmode === 'draw' || plotmode === 'home_in') {
      through = plotqi - 1;
    }
    for (let qi = 0; qi <= through && qi < n; qi++) {
      let l = q[qi];
      line(l.x1 * sc + dx, l.y1 * sc + dy, l.x2 * sc + dx, l.y2 * sc + dy);
    }
    if (plotmode === 'draw' && plotqi < n) {
      let l = q[plotqi];
      let xb = lerp(l.x1, l.x2, plott);
      let yb = lerp(l.y1, l.y2, plott);
      line(l.x1 * sc + dx, l.y1 * sc + dy, xb * sc + dx, yb * sc + dy);
    }
    if (phase === 'anim') {
      let tx, ty;
      let showtip = false;
      if (plotmode === 'draw') {
        if (plotqi < n) {
          let l = q[plotqi];
          tx = lerp(l.x1, l.x2, plott);
          ty = lerp(l.y1, l.y2, plott);
          showtip = true;
        }
      } else {
        let u = talong / tlen;
        tx = lerp(tfx, ttx, u);
        ty = lerp(tfy, tty, u);
        showtip = true;
      }
      if (showtip) {
        noStroke();
        if (plotmode === 'draw') {
          fill(rgb[0], rgb[1], rgb[2]);
        } else {
          fill(128);
        }
        circle(tx * sc + dx, ty * sc + dy, lw * sc);
      }
    }
  }
}

function activeIdx(n) {
  let valid = [];
  for (let i = 1; i <= 3; i++) {
    if ((n - i) % (i + 1) === 0 && (n - i) / (i + 1) >= 3) {
      valid.push(i);
    }
  }
  let ng = valid[R.random_int(0, valid.length - 1)];
  let skip = {};
  for (let i = 0; i < ng; i++) {
    skip[(i + 1) * (n - ng) / (ng + 1) + i] = true;
  }
  let indices = [];
  for (let i = 0; i < n; i++) {
    if (!skip[i]) {
      indices.push(i);
    }
  }
  return indices;
}

function blendParams(idx, mode) {
  let n = idx.length;
  let params = [];
  if (n <= 1) {
    for (let i = 0; i < n; i++) {
      params.push(0.5);
    }
  } else if (mode === 'continuous') {
    for (let i = 0; i < n; i++) {
      params.push(i / (n - 1));
    }
  } else {
    let groups = [];
    let cur = [idx[0]];
    for (let i = 1; i < idx.length; i++) {
      if (idx[i] !== idx[i - 1] + 1) {
        groups.push(cur);
        cur = [];
      }
      cur.push(idx[i]);
    }
    groups.push(cur);
    for (let i = 0; i < groups.length; i++) {
      let grp = groups[i];
      for (let j = 0; j < grp.length; j++) {
        let t = 0.5;
        if (grp.length > 1) {
          t = j / (grp.length - 1);
        }
        if ((mode === 'reflect' || mode === 'rotate') && i % 2 === 1) {
          params.push(1 - t);
        } else {
          params.push(t);
        }
      }
    }
  }
  return params;
}

function buildCells(corner) {
  let theta = angles[corner] * PI / 180;
  let sa = sin(theta);
  let ca = cos(theta);
  let cells = [];
  for (let j = 0; j < arows.length; j++) {
    for (let i = 0; i < acols.length; i++) {
      let nx = cparam[i];
      let ny = rparam[j];
      if ((blend === 'inverse' || blend === 'rotate') && gaps) {
        let grp;
        if (gaxis === 'cols') {
          grp = gmap[i];
        } else {
          grp = gmap[j];
        }
        if (grp % 2 === 1) {
          if (gaxis === 'cols') {
            ny = 1 - ny;
          } else {
            nx = 1 - nx;
          }
        }
      }
      let wt;
      if (corner === 'p1') {
        wt = (1 - nx) * (1 - ny);
      } else if (corner === 'p2') {
        wt = nx * (1 - ny);
      } else if (corner === 'p3') {
        wt = nx * ny;
      } else {
        wt = (1 - nx) * ny;
      }
      if (wt > 0) {
        let cx = mx + acols[i] * cw;
        let cy = my + arows[j] * ch;
        let d0 = -cx * sa + cy * ca;
        let d1 = -(cx + cw) * sa + cy * ca;
        let d2 = -cx * sa + (cy + ch) * ca;
        let d3 = -(cx + cw) * sa + (cy + ch) * ca;
        let dmin = min(d0, d1, d2, d3);
        let pspan = max(d0, d1, d2, d3) - dmin;
        let nlines = max(1, round((1 - pow(1 - wt, curve)) * pspan / spacing));
        let step = pspan / nlines;
        let xmin = cx;
        let xmax = cx + cw;
        let ymin = cy;
        let ymax = cy + ch;
        let ls = [];
        let tdist = 0;
        for (let k = 0; k < nlines; k++) {
          let dd = dmin + step / 2 + k * step;
          let tl = (xmin + dd * sa) / ca;
          let tr = (xmax + dd * sa) / ca;
          let tt = (ymin - dd * ca) / sa;
          let tb = (ymax - dd * ca) / sa;
          let tlo = max(min(tl, tr), min(tt, tb));
          let thi = min(max(tl, tr), max(tt, tb));
          let x1 = -dd * sa + tlo * ca;
          let y1 =  dd * ca + tlo * sa;
          let x2 = -dd * sa + thi * ca;
          let y2 =  dd * ca + thi * sa;
          if (x1 > x2) {
            [x1, y1, x2, y2] = [x2, y2, x1, y1];
          }
          ls.push({ x1: x1, y1: y1, x2: x2, y2: y2 });
          tdist += dist(x1, y1, x2, y2);
        }
        ls.reverse();
        let cl = 0;
        let lc = i;
        let lr = j;
        if (gaxis === 'cols') {
          cl = gmap[i];
          lc = i - cstarts[cl];
        } else if (gaxis === 'rows') {
          cl = gmap[j];
          lr = j - cstarts[cl];
        }
        if (cl % 2 === 1) {
          if (blend === 'reflect') {
            if (gaxis === 'cols') {
              lc = lcdim - 1 - lc;
            } else {
              lr = lrdim - 1 - lr;
            }
          } else if (blend === 'inverse') {
            if (gaxis === 'cols') {
              lr = lrdim - 1 - lr;
            } else {
              lc = lcdim - 1 - lc;
            }
          } else if (blend === 'rotate') {
            lc = lcdim - 1 - lc;
            lr = lrdim - 1 - lr;
          }
        }
        cells.push({ col: acols[i], row: arows[j], lines: ls, distance: tdist, cluster: cl, lc: lc, lr: lr });
      }
    }
  }
  return cells;
}

function compareCellsPackOrder(a, b) {
  let d = a.distance - b.distance;
  if (d !== 0) {
    return d;
  }
  if (a.row !== b.row) {
    return a.row - b.row;
  }
  return a.col - b.col;
}

function compareBatchesPackOrder(a, b) {
  let ca = a.cells[a.cells.length - 1];
  let cb = b.cells[b.cells.length - 1];
  let d = cb.distance - ca.distance;
  if (d !== 0) {
    return d;
  }
  if (ca.row !== cb.row) {
    return ca.row - cb.row;
  }
  return ca.col - cb.col;
}

function pack(cells, cmp) {
  let batches = [];
  if (cells.length > 0) {
    let pool = cells.slice().sort(cmp);
    while (pool.length > 0) {
      let anchor = pool.pop();
      let group = [anchor];
      let total = anchor.distance;
      while (pool.length > 0 && total + pool[0].distance <= threshold) {
        let c = pool.shift();
        group.push(c);
        total += c.distance;
      }
      group.sort(cmp);
      batches.push({ cells: group, distance: total });
    }
  }
  return batches;
}

function buildPlotQueue(corner) {
  let cells = cdata[corner];
  let batches;
  if (blend === 'continuous') {
    batches = pack(cells, compareCellsPackOrder);
    batches.sort(compareBatchesPackOrder);
  } else {
    let clusters = {};
    let ids = [];
    for (let i = 0; i < cells.length; i++) {
      let cl = cells[i].cluster;
      if (!clusters[cl]) {
        clusters[cl] = [];
        ids.push(cl);
      }
      clusters[cl].push(cells[i]);
    }
    ids.sort(function(a, b) {
      return a - b;
    });
    let lookups = [];
    for (let ci = 0; ci < ids.length; ci++) {
      let lk = new Array(lcdim * lrdim);
      let clist = clusters[ids[ci]];
      for (let k = 0; k < clist.length; k++) {
        let c = clist[k];
        lk[c.lr * lcdim + c.lc] = c;
      }
      lookups.push(lk);
    }
    let template = pack(clusters[ids[0]], function(a, b) {
      let d = a.distance - b.distance;
      if (d !== 0) {
        return d;
      }
      if (a.lr !== b.lr) {
        return a.lr - b.lr;
      }
      return a.lc - b.lc;
    });
    batches = [];
    for (let ti = 0; ti < template.length; ti++) {
      let tcells = template[ti].cells;
      for (let ci = 0; ci < ids.length; ci++) {
        let bcells = [];
        let tot = 0;
        for (let k = 0; k < tcells.length; k++) {
          let t = tcells[k];
          let c = lookups[ci][t.lr * lcdim + t.lc];
          bcells.push(c);
          tot += c.distance;
        }
        batches.push({ cells: bcells, distance: tot });
      }
    }
  }
  let queue = [];
  for (let bi = 0; bi < batches.length; bi++) {
    let batch = batches[bi];
    for (let cj = 0; cj < batch.cells.length; cj++) {
      let ls = batch.cells[cj].lines;
      for (let k = 0; k < ls.length; k++) {
        let l = ls[k];
        let swap = (l.y1 < l.y2) || (l.y1 === l.y2 && l.x1 > l.x2);
        if (swap) {
          queue.push({ x1: l.x2, y1: l.y2, x2: l.x1, y2: l.y1 });
        } else {
          queue.push({ x1: l.x1, y1: l.y1, x2: l.x2, y2: l.y2 });
        }
      }
    }
  }
  return queue;
}

function ensurePlotqs() {
  if (!plotqs) {
    plotqs = [
      buildPlotQueue('p1'),
      buildPlotQueue('p2'),
      buildPlotQueue('p3'),
      buildPlotQueue('p4'),
    ];
  }
}

function setupTransit(fx, fy, tx, ty) {
  tfx = fx;
  tfy = fy;
  ttx = tx;
  tty = ty;
  tlen = dist(tfx, tfy, ttx, tty);
  talong = 0;
}

function resetAnimState() {
  ensurePlotqs();
  pi = 0;
  plotqi = 0;
  plott = 0;
  plotmode = 'home_in';
  setupTransit(0, ph, plotqs[0][0].x1, plotqs[0][0].y1);
  plotskip = true;
  pmult = 1;
  complete = false;
}

function scramble(arr) {
  let shuffled = arr.slice();
  for (let i = shuffled.length - 1; i > 0; i--) {
    let j = R.random_int(0, i);
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}

function mousePressed() {
  if (phase === 'blend') {
    if (!plotqs) {
      resetAnimState();
      phase = 'anim';
      loop();
    } else if (complete) {
      phase = 'done';
      noLoop();
      redraw();
    } else {
      plotskip = true;
      phase = 'anim';
      loop();
    }
  } else {
    phase = 'blend';
    noLoop();
    redraw();
  }
}

function keyPressed() {
  if (key === 'r' || key === 'R') {
    resetAnimState();
    if (phase !== 'blend') {
      phase = 'anim';
      loop();
    }
  } else if (key === 'c' || key === 'C') {
    ensurePlotqs();
    pi = plotqs.length - 1;
    plotqi = plotqs[pi].length;
    plotmode = 'draw';
    complete = true;
    if (phase !== 'blend') {
      phase = 'done';
      noLoop();
      redraw();
    }
  } else {
    let n = parseInt(key, 10);
    if (n === 0 && phase === 'anim') {
      noLoop();
    } else if (n >= 1 && n <= 9) {
      pmult = round(pow(1.6, n - 1));
      if (phase === 'anim') {
        loop();
      }
    }
  }
}

class Random {
  constructor(token) {
    this.useA = false;
    let sfc32 = function(uint128Hex) {
      let a = parseInt(uint128Hex.substr(0, 8), 16);
      let b = parseInt(uint128Hex.substr(8, 8), 16);
      let c = parseInt(uint128Hex.substr(16, 8), 16);
      let d = parseInt(uint128Hex.substr(24, 8), 16);
      return function() {
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
    this.prngA = new sfc32(token.substr(2, 32));
    this.prngB = new sfc32(token.substr(34, 32));
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
}