import fs from 'node:fs';
const file = process.argv[2];
const j = JSON.parse(fs.readFileSync(file, 'utf8'));
const blocks = j.shader.blocks;
const stat = (pred) => {
  const sel = blocks.filter(pred);
  const sum = sel.reduce((a, b) => a + b.ms, 0);
  return { n: sel.length, sumMs: Math.round(sum), avg: sel.length ? Math.round(sum / sel.length) : 0 };
};
const flags = ['IN_SHADOW_PASS', 'USE_RADIANCE_MAP', 'USE_INSTANCING', 'LIGHT_RIM_USED', 'DO_SIDE_CHECK', 'TANGENT_USED', 'COLOR_USED', 'UV_USED', 'SHADER_IS_SRGB'];
console.log('links', j.shader.links, 'blocked ms', j.shader.linkBlockMs, 'blocks>30ms', blocks.length);
for (const f of flags) {
  const s = stat((b) => b.tag.includes(f) || b.tag.includes(',' + f + ',') || b.tag.endsWith(f));
  console.log(String(f).padEnd(20), s);
}
const shadow = stat((b) => b.tag.includes('IN_SHADOW_PASS'));
console.log('shadow share of blocked time: ' + Math.round(100 * shadow.sumMs / j.shader.linkBlockMs) + '%');
// unique tag count and duplicate groups
const groups = new Map();
for (const b of blocks) {
  const k = b.tag;
  if (!groups.has(k)) groups.set(k, []);
  groups.get(k).push(b.ms);
}
const dupes = [...groups.entries()].filter(([, v]) => v.length > 1).sort((a, b) => b[1].length - a[1].length);
console.log('unique variants', groups.size, 'duplicated groups', dupes.length, 'dupe links', dupes.reduce((a, [, v]) => a + v.length, 0));
console.log('top dupe counts', dupes.slice(0, 5).map(([, v]) => v.length));
console.log('timeline (blocks > 500ms):');
for (const b of blocks.filter((x) => x.ms > 500).sort((a, b) => a.at - b.at)) {
  console.log(String(Math.round(b.at)).padStart(7), String(Math.round(b.ms)).padStart(5) + 'ms', b.tag.slice(0, 90));
}
