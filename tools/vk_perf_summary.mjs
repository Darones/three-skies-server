import fs from 'node:fs';
const dir = 'docs/qa-vk-perf-2026-11-26/';
const rows = fs.readdirSync(dir).filter((f) => f.endsWith('.json') && f.startsWith('ch-'));
const out = [];
for (const f of rows) {
  const j = JSON.parse(fs.readFileSync(dir + f, 'utf8'));
  if (!j.shader) { out.push({ f, note: 'no shader data', bootMs: j.bootMs, canvas: j.probe?.canvas }); continue; }
  const blocks = j.shader.blocks || [];
  const rad = blocks.filter((b) => b.tag.includes('USE_RADIANCE_MAP'));
  const non = blocks.filter((b) => !b.tag.includes('USE_RADIANCE_MAP'));
  const sum = (a) => a.reduce((x, b) => x + b.ms, 0);
  out.push({
    f,
    bootMs: j.bootMs,
    canvas: j.probe.canvas.w + 'x' + j.probe.canvas.h,
    links: j.shader.links,
    blockedMs: j.shader.linkBlockMs,
    blocks: blocks.length,
    worstMs: Math.max(0, ...blocks.map((b) => b.ms)),
    radiance: { n: rad.length, sumMs: Math.round(sum(rad)), avg: Math.round(sum(rad) / Math.max(1, rad.length)) },
    noRadiance: { n: non.length, sumMs: Math.round(sum(non)), avg: Math.round(sum(non) / Math.max(1, non.length)) },
  });
}
console.table(out);
