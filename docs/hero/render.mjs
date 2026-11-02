// node render.mjs out.gif [fps]   |   node render.mjs --stills dir t1 t2 ...
import puppeteer from 'puppeteer-core';
import gifenc from 'gifenc';
import fs from 'node:fs';
import path from 'node:path';
const { GIFEncoder, quantize, applyPalette } = gifenc;

const here = path.dirname(new URL(import.meta.url).pathname);
const browser = await puppeteer.launch({
  executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  headless: true,
});
const page = await browser.newPage();
await page.goto('file://' + path.join(here, 'scene.html'));
await page.evaluate(() => document.fonts.ready);
const { W, H, DUR } = await page.evaluate(() => ({ W, H, DUR }));

if (process.argv[2] === '--stills') {
  const dir = process.argv[3];
  fs.mkdirSync(dir, { recursive: true });
  for (const t of process.argv.slice(4)) {
    const url = await page.evaluate(t => png(t), +t);
    fs.writeFileSync(path.join(dir, `t${t}.png`), Buffer.from(url.split(',')[1], 'base64'));
  }
  await browser.close();
  process.exit(0);
}

const out = process.argv[2] ?? 'hero.gif';
const fps = +(process.argv[3] ?? 25);
const grab = async t => new Uint8Array(Buffer.from(await page.evaluate(t => frame(t), t), 'base64'));

// One shared palette (from sample frames) so unchanged pixels can be made transparent.
const samples = [];
for (const t of [0.2, 1.4, 3.1, 4.3, 5.4, 7.6, 8.05, 8.9]) samples.push(await grab(t));
const all = new Uint8Array(samples.reduce((n, s) => n + s.length, 0));
let o = 0; for (const s of samples) { all.set(s, o); o += s.length; }
const palette = quantize(all, 255);
while (palette.length < 255) palette.push([0, 0, 0]);
palette.push([255, 0, 255]);               // index 255 = transparent
const TRANSPARENT = 255;

const gif = GIFEncoder();
const n = Math.round(DUR * fps), delay = 1000 / fps;
let prev = null, pending = null;
const flush = () => {
  if (!pending) return;
  gif.writeFrame(pending.idx, W, H, {
    palette: pending.first ? palette : undefined,
    delay: Math.round(pending.delay),
    transparent: !pending.first, transparentIndex: TRANSPARENT,
    dispose: 1, repeat: 0,
  });
};
for (let i = 0; i < n; i++) {
  const full = applyPalette(await grab(i / fps), palette);
  if (!prev) { pending = { idx: full, delay, first: true }; prev = full; continue; }
  const diff = new Uint8Array(full.length);
  let changed = 0;
  for (let k = 0; k < full.length; k++) {
    if (full[k] === prev[k]) diff[k] = TRANSPARENT; else { diff[k] = full[k]; changed++; }
  }
  if (changed === 0) { pending.delay += delay; continue; }
  flush();
  pending = { idx: diff, delay, first: false };
  prev = full;
}
flush();
gif.finish();
fs.writeFileSync(out, gif.bytes());
console.log(`${out}: ${n} frames @ ${fps}fps, ${(fs.statSync(out).size / 1024).toFixed(0)} KB`);
await browser.close();
