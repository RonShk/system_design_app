// Draws the 1024×1024 app icon (three connected nodes on a dark teal field) as a PNG, with no dependencies.
import fs from 'node:fs';
import zlib from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const N = 1024;
const px = Buffer.alloc(N * N * 3);
const bg = [18, 62, 58], line = [120, 214, 190], node = [240, 250, 247], hub = [255, 196, 87];
const nodes = [[512, 300, 92, hub], [270, 720, 80, node], [754, 720, 80, node]];
const edges = [[0, 1], [0, 2], [1, 2]];
const distSeg = (x, y, ax, ay, bx, by) => {
  const dx = bx - ax, dy = by - ay;
  const t = Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)));
  return Math.hypot(x - (ax + t * dx), y - (ay + t * dy));
};
const mix = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
for (let y = 0; y < N; y++) {
  for (let x = 0; x < N; x++) {
    const g = (x + y) / (2 * N);
    let c = mix(bg, [10, 40, 48], g);
    for (const [a, b] of edges) {
      const d = distSeg(x, y, nodes[a][0], nodes[a][1], nodes[b][0], nodes[b][1]);
      c = mix(c, line, Math.max(0, Math.min(1, 15 - d)));
    }
    for (const [cx, cy, r, col] of nodes) {
      const d = Math.hypot(x - cx, y - cy);
      c = mix(c, bg, Math.max(0, Math.min(1, r + 16 - d)));
      c = mix(c, col, Math.max(0, Math.min(1, r - d)));
    }
    px.set(c, (y * N + x) * 3);
  }
}
const raw = Buffer.alloc(N * (N * 3 + 1));
for (let y = 0; y < N; y++) px.copy(raw, y * (N * 3 + 1) + 1, y * N * 3, (y + 1) * N * 3);
const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc = (buf) => { let c = 0xffffffff; for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const c = Buffer.alloc(4); c.writeUInt32BE(crc(td));
  return Buffer.concat([len, td, c]);
};
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(N, 0); ihdr.writeUInt32BE(N, 4); ihdr[8] = 8; ihdr[9] = 2;
const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
const out = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../ios/SystemDesignTrainer/Assets.xcassets/AppIcon.appiconset/icon-1024.png');
fs.writeFileSync(out, png);
console.log('wrote', out, png.length, 'bytes');
