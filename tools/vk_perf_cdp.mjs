// VK/webview perf probe: drives Chrome over CDP with mobile emulation and
// collects renderer/DPR/canvas facts, boot timings, long tasks and frame
// deltas. Read-only: it never touches the game or the server.
//
// Usage:
//   node tools/vk_perf_cdp.mjs --url https://host/game/ --w 844 --h 390 --dpr 3 \
//        --seconds 12 --cpu 1 --tag game-mobile --out docs/qa-vk-perf-...
//
// Output: <out>/<tag>.json + <tag>-boot.png + <tag>-run.png

import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { join, resolve } from 'node:path';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, cur, i, arr) => {
    if (cur.startsWith('--')) acc.push([cur.slice(2), arr[i + 1]?.startsWith('--') ? '1' : arr[i + 1]]);
    return acc;
  }, [])
);

const URL_ = args.url;
const W = Number(args.w || 844);
const H = Number(args.h || 390);
const DPR = Number(args.dpr || 3);
const SECONDS = Number(args.seconds || 12);
const CPU = Number(args.cpu || 1);
const TAG = args.tag || 'run';
const OUT = resolve(args.out || 'docs/qa-vk-perf-2026-11-26');
const PORT = Number(args.port || 9333 + Math.floor(Math.random() * 200));
const CHROME = args.chrome || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const MOBILE = args.mobile !== '0';
const UA = args.ua || (MOBILE
  ? 'Mozilla/5.0 (Linux; Android 14; SM-A566B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36'
  : undefined);

mkdirSync(OUT, { recursive: true });
const profileDir = join(process.env.TEMP || '.', `vkperf-${TAG}-${Date.now()}`);

const chrome = spawn(CHROME, [
  ...(args.headed ? [] : ['--headless=new']),
  `--remote-debugging-port=${PORT}`,
  `--user-data-dir=${profileDir}`,
  '--no-first-run',
  '--no-default-browser-check',
  '--disable-features=Translate,OptimizationHints,MediaRouter',
  '--autoplay-policy=no-user-gesture-required',
  '--enable-unsafe-swiftshader',
  ...(args.angle ? [`--use-angle=${args.angle}`] : []),
  ...(args.gl ? [`--use-gl=${args.gl}`] : []),
  '--hide-scrollbars',
  'about:blank',
], { stdio: 'ignore' });

const cleanup = () => {
  try { chrome.kill(); } catch {}
  try { rmSync(profileDir, { recursive: true, force: true }); } catch {}
};

async function waitVersion() {
  for (let i = 0; i < 100; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/json/version`);
      if (r.ok) return r.json();
    } catch {}
    await sleep(100);
  }
  throw new Error('Chrome CDP did not start');
}

let ws;
let msgId = 0;
const pending = new Map();
const listeners = [];
let sessionEvents = [];

function send(method, params = {}) {
  const id = ++msgId;
  ws.send(JSON.stringify({ id, method, params }));
  return new Promise((res, rej) => pending.set(id, { res, rej, method }));
}

async function evaluate(expression, awaitPromise = true) {
  const r = await send('Runtime.evaluate', {
    expression, returnByValue: true, awaitPromise, userGesture: true,
  });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || ''));
  return r.result?.value;
}

const INIT_SCRIPT = `
(() => {
  if (window.__vkperf) return;
  const P = window.__vkperf = {
    t0: performance.now(),
    longtasks: [], resources: [], errors: [], marks: [],
    frames: [], fpsSamples: [],
  };
  try {
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) P.longtasks.push({ start: +e.startTime.toFixed(1), dur: +e.duration.toFixed(1) });
    }).observe({ entryTypes: ['longtask'] });
  } catch (e) { P.errors.push('longtask: ' + e); }
  try {
    new PerformanceObserver((list) => {
      for (const e of list.getEntries()) {
        if (e.initiatorType === 'fetch' || e.initiatorType === 'other' || e.name.match(/\\.(wasm|pck|js)$/)) {
          P.resources.push({
            name: e.name.split('/').pop().split('?')[0],
            start: +e.startTime.toFixed(0),
            dur: +e.duration.toFixed(0),
            transfer: e.transferSize, encoded: e.encodedBodySize, decoded: e.decodedBodySize,
            type: e.initiatorType,
          });
        }
      }
    }).observe({ entryTypes: ['resource'] });
  } catch (e) { P.errors.push('resource: ' + e); }
  window.addEventListener('error', (e) => P.errors.push(String(e.message)));
  window.addEventListener('unhandledrejection', (e) => P.errors.push('rejection: ' + String(e.reason)));
  // Count real rAF callbacks: one per Godot main-loop iteration.
  const raf = window.requestAnimationFrame.bind(window);
  window.__vkperfRaf = true;
  window.requestAnimationFrame = function (cb) {
    return raf(function (ts) {
      P.frames.push(ts);
      if (P.frames.length > 6000) P.frames.splice(0, 3000);
      return cb(ts);
    });
  };
  // Count WebGL program links. In the Compatibility renderer every new
  // material variant links a program on the main thread; getProgramParameter
  // (LINK_STATUS) blocks until the driver finishes, which is the visible freeze.
  try {
    const G = (window.WebGL2RenderingContext || window.WebGLRenderingContext);
    if (G && G.prototype) {
      P.shader = { links: 0, linkBlockMs: 0, blocks: [], compileMs: 0, compiles: 0 };
      const origLink = G.prototype.linkProgram;
      const origGet = G.prototype.getProgramParameter;
      const origCompile = G.prototype.compileShader;
      const origSource = G.prototype.shaderSource;
      G.prototype.shaderSource = function (s, src2) {
        const r = origSource.call(this, s, src2);
        if (typeof src2 === 'string' && src2.indexOf('void fragment') !== -1) P.shader._lastFrag = src2;
        return r;
      };
      G.prototype.linkProgram = function (p) {
        P.shader.links++;
        P.shader._t = performance.now();
        return origLink.call(this, p);
      };
      G.prototype.getProgramParameter = function (p, pname) {
        const t0 = performance.now();
        const r = origGet.call(this, p, pname);
        if (this.LINK_STATUS !== undefined && pname === this.LINK_STATUS) {
          const dt = performance.now() - t0;
          P.shader.linkBlockMs += dt;
          if (dt > 30) {
            let tag = '';
            try {
              const sh = this.getAttachedShaders(p) || [];
              const defs = new Set();
              for (const s of sh) {
                const src = this.getShaderSource(s) || '';
                const lines = src.split(String.fromCharCode(10));
                for (const ln of lines) {
                  const m = /^#define[ \t]+([A-Za-z0-9_]+)(?:[ \t]+([01]))?[ \t]*$/.exec(ln);
                  if (m && m[2] !== '0') defs.add(m[1]);
                }
                if (src.indexOf('void fragment') !== -1) tag += 'F';
                else if (src.indexOf('void vertex') !== -1) tag += 'V';
                if (src.indexOf('light()') !== -1 || src.indexOf('frag_color') !== -1) tag += 'L';
              }
              tag += ' ' + [...defs].sort().join(',');
            } catch (e) {}
            P.shader.blocks.push({ ms: +dt.toFixed(1), at: +t0.toFixed(0), tag });
          }
        }
        return r;
      };
      G.prototype.compileShader = function (s) {
        const t0 = performance.now();
        const r = origCompile.call(this, s);
        P.shader.compileMs += performance.now() - t0;
        P.shader.compiles++;
        return r;
      };
    }
  } catch (e) { P.errors.push('shader-hook: ' + e); }
  // A canvas observer records backing-store size changes (DPR / resize policy).
  document.addEventListener('DOMContentLoaded', () => {
    const c = document.getElementById('canvas');
    if (!c) return;
    P.canvas0 = { w: c.width, h: c.height, cssW: c.clientWidth, cssH: c.clientHeight };
  });
})();
`;

function summarizeFrames(frames) {
  if (!frames.length) return null;
  const deltas = [];
  for (let i = 1; i < frames.length; i++) {
    const d = frames[i] - frames[i - 1];
    if (d > 0 && d < 2000) deltas.push(d);
  }
  if (!deltas.length) return null;
  const sorted = [...deltas].sort((a, b) => a - b);
  const q = (p) => +sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * p))].toFixed(2);
  const mean = deltas.reduce((a, b) => a + b, 0) / deltas.length;
  let over50 = 0, over100 = 0;
  for (const d of deltas) { if (d > 50) over50++; if (d > 100) over100++; }
  return {
    n: deltas.length,
    meanMs: +mean.toFixed(2),
    fpsMean: +(1000 / mean).toFixed(1),
    p50: q(0.5), p95: q(0.95), p99: q(0.99), max: +sorted[sorted.length - 1].toFixed(1),
    over50msPct: +(100 * over50 / deltas.length).toFixed(1),
    over100msPct: +(100 * over100 / deltas.length).toFixed(1),
  };
}

const PROBE_JS = `(() => {
  const c = document.getElementById('canvas');
  const gl2 = document.createElement('canvas').getContext('webgl2');
  let gl = null, dbg = null, vendor = null, renderer = null, version = null, maxTex = null, exts = [];
  try {
    gl = gl2 || document.createElement('canvas').getContext('webgl');
    dbg = gl && gl.getExtension('WEBGL_debug_renderer_info');
    vendor = dbg ? gl.getParameter(dbg.UNMASKED_VENDOR_WEBGL) : (gl ? gl.getParameter(gl.VENDOR) : null);
    renderer = dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : (gl ? gl.getParameter(gl.RENDERER) : null);
    version = gl ? gl.getParameter(gl.VERSION) : null;
    maxTex = gl ? gl.getParameter(gl.MAX_TEXTURE_SIZE) : null;
    exts = gl ? gl.getSupportedExtensions() : [];
  } catch (e) {}
  const nav = navigator;
  return {
    href: location.href,
    ua: nav.userAgent,
    platform: nav.platform,
    dpr: window.devicePixelRatio,
    inner: [innerWidth, innerHeight],
    outer: [outerWidth, outerHeight],
    screen: [screen.width, screen.height, screen.availWidth, screen.availHeight],
    orientation: (screen.orientation && screen.orientation.type) || null,
    hardwareConcurrency: nav.hardwareConcurrency,
    deviceMemory: nav.deviceMemory ?? null,
    webgl2: !!gl2,
    glVendor: vendor, glRenderer: renderer, glVersion: version, maxTexture: maxTex,
    glExtensions: exts,
    canvas: c ? { w: c.width, h: c.height, cssW: c.clientWidth, cssH: c.clientHeight,
      rectW: +c.getBoundingClientRect().width.toFixed(1), rectH: +c.getBoundingClientRect().height.toFixed(1) } : null,
    canvasStyle: c ? { width: c.style.width, height: c.style.height } : null,
    visualViewport: window.visualViewport ? {
      w: +visualViewport.width.toFixed(1), h: +visualViewport.height.toFixed(1), scale: visualViewport.scale,
    } : null,
    vkBridge: typeof window.vkBridge,
    vkInit: typeof window.__tsVKInit,
    mem: performance.memory ? {
      usedMB: +(performance.memory.usedJSHeapSize / 1048576).toFixed(1),
      totalMB: +(performance.memory.totalJSHeapSize / 1048576).toFixed(1),
      limitMB: +(performance.memory.jsHeapSizeLimit / 1048576).toFixed(1),
    } : null,
    crossOriginIsolated: window.crossOriginIsolated,
    sharedArrayBuffer: typeof SharedArrayBuffer,
    wasm: typeof WebAssembly,
    fpsCounterInstalled: !!window.requestAnimationFrame,
    canvases: Array.from(document.querySelectorAll('canvas')).map((x) => ({ id: x.id, w: x.width, h: x.height })),
    loadState: document.readyState,
    loaderHidden: !document.getElementById('status') || document.getElementById('status').style.visibility === 'hidden',
    statusText: (document.getElementById('status-notice') || {}).textContent || '',
    frameCount: window.__vkperf ? window.__vkperf.frames.length : -1,
  };
})()`;

async function main() {
  const version = await waitVersion();
  const t = await fetch(`http://127.0.0.1:${PORT}/json/new?about:blank`, { method: 'PUT' }).then((r) => r.json());
  ws = new WebSocket(t.webSocketDebuggerUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) {
      const { res, rej, method } = pending.get(m.id);
      pending.delete(m.id);
      m.error ? rej(new Error(method + ': ' + m.error.message)) : res(m.result);
    } else if (m.method) {
      for (const l of listeners) l(m);
      sessionEvents.push(m);
    }
  };

  const consoleLines = [];
  const netRequests = new Map();
  listeners.push((m) => {
    if (m.method === 'Runtime.consoleAPICalled') {
      const text = (m.params.args || []).map((a) => a.value ?? a.description ?? a.type).join(' ');
      consoleLines.push({ t: Date.now(), type: m.params.type, text: String(text).slice(0, 500) });
    }
    if (m.method === 'Runtime.exceptionThrown') {
      consoleLines.push({ t: Date.now(), type: 'exception', text: (m.params.exceptionDetails?.exception?.description || m.params.exceptionDetails?.text || '').slice(0, 800) });
    }
    if (m.method === 'Log.entryAdded') {
      consoleLines.push({ t: Date.now(), type: 'log:' + m.params.entry.level, text: String(m.params.entry.text).slice(0, 500) });
    }
    if (m.method === 'Network.requestWillBeSent') {
      netRequests.set(m.params.requestId, { url: m.params.request.url, start: m.params.timestamp });
    }
    if (m.method === 'Network.responseReceived') {
      const r = netRequests.get(m.params.requestId);
      if (r) { r.status = m.params.response.status; r.mime = m.params.response.mimeType; r.headers = m.params.response.headers; }
    }
    if (m.method === 'Network.loadingFinished') {
      const r = netRequests.get(m.params.requestId);
      if (r) { r.end = m.params.timestamp; r.bytes = m.params.encodedDataLength; }
    }
    if (m.method === 'Network.loadingFailed') {
      const r = netRequests.get(m.params.requestId);
      if (r) { r.failed = m.params.errorText; r.end = m.params.timestamp; }
    }
  });

  await Promise.all([
    send('Page.enable'), send('Runtime.enable'), send('Log.enable'),
    send('Network.enable'), send('Performance.enable'), send('Emulation.setFocusEmulationEnabled', { enabled: true }),
  ]);

  await send('Emulation.setDeviceMetricsOverride', {
    width: W, height: H, deviceScaleFactor: DPR, mobile: MOBILE,
    screenOrientation: { type: W > H ? 'landscapePrimary' : 'portraitPrimary', angle: W > H ? 90 : 0 },
  });
  await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
  if (UA) await send('Emulation.setUserAgentOverride', { userAgent: UA, platform: 'Linux armv8l' });
  if (CPU > 1) await send('Emulation.setCPUThrottlingRate', { rate: CPU });

  await send('Page.addScriptToEvaluateOnNewDocument', { source: INIT_SCRIPT });
  if (args.inject) {
    const injectSrc = readFileSync(resolve(args.inject), 'utf8');
    await send('Page.addScriptToEvaluateOnNewDocument', { source: injectSrc });
  }

  const navStart = Date.now();
  await send('Page.navigate', { url: URL_ });

  // Boot: wait until the loader is gone or 90 s pass; record the moment.
  let boot = null;
  for (let i = 0; i < 180; i++) {
    await sleep(500);
    const s = await evaluate(`(() => {
      const st = document.getElementById('status');
      return {
        ready: !!document.querySelector('canvas') && (!st || getComputedStyle(st).display === 'none' || st.style.visibility === 'hidden'),
        canvas: (() => { const c = document.getElementById('canvas'); return c ? [c.width, c.height, c.clientWidth, c.clientHeight] : null; })(),
        frames: window.__vkperf ? window.__vkperf.frames.length : -1,
      };
    })()`).catch(() => null);
    if (s && s.ready) { boot = { ms: Date.now() - navStart, canvas: s.canvas }; break; }
  }

  const shot1 = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(join(OUT, `${TAG}-boot.png`), Buffer.from(shot1.data, 'base64'));

  if (args.cpuprofile) {
    await send('Profiler.enable');
    await send('Profiler.setSamplingInterval', { interval: 250 });
    await send('Profiler.start');
  }

  // Sample frames for SECONDS; report per-second FPS so a throttle curve shows.
  const fpsSeries = [];
  for (let i = 0; i < SECONDS; i++) {
    const f0 = await evaluate('window.__vkperf ? window.__vkperf.frames.length : -1');
    await sleep(1000);
    const f1 = await evaluate('window.__vkperf ? window.__vkperf.frames.length : -1');
    fpsSeries.push(f1 - f0);
  }

  let cpuTop = null;
  if (args.cpuprofile) {
    const prof = await send('Profiler.stop');
    const nodes = prof.profile.nodes || [];
    const byId = new Map(nodes.map((n) => [n.id, n]));
    const self = new Map();
    let total = 0;
    const deltas = prof.profile.timeDeltas || [];
    (prof.profile.samples || []).forEach((id, i) => {
      const d = (deltas[i] || 0) / 1000;
      total += d;
      const n = byId.get(id);
      if (!n) return;
      const cf = n.callFrame;
      const key = `${cf.functionName || '(anon)'} @ ${(cf.url || '').split('/').slice(-1)[0]}:${cf.lineNumber}`;
      self.set(key, (self.get(key) || 0) + d);
    });
    cpuTop = [...self.entries()]
      .sort((a, b) => b[1] - a[1])
      .slice(0, 30)
      .map(([k, v]) => ({ fn: k, ms: +v.toFixed(0), pct: +(100 * v / total).toFixed(1) }));
    cpuTop.totalSampledMs = +total.toFixed(0);
  }

  const probe = await evaluate(PROBE_JS);
  const perf = await send('Performance.getMetrics');
  const frames = await evaluate('window.__vkperf ? window.__vkperf.frames.slice() : []');
  const longtasks = await evaluate('window.__vkperf ? window.__vkperf.longtasks.slice() : []');
  const resources = await evaluate('window.__vkperf ? window.__vkperf.resources.slice() : []');
  const pageErrors = await evaluate('window.__vkperf ? window.__vkperf.errors.slice() : []');
  const shader = await evaluate(`(() => { const s = window.__vkperf && window.__vkperf.shader; if (!s) return null;
    return { links: s.links, linkBlockMs: +s.linkBlockMs.toFixed(0), compiles: s.compiles,
      compileMs: +s.compileMs.toFixed(0), blocks: s.blocks, tagVer: 'active-defines' }; })()`);

  const shot2 = await send('Page.captureScreenshot', { format: 'png' });
  writeFileSync(join(OUT, `${TAG}-run.png`), Buffer.from(shot2.data, 'base64'));

  const metrics = Object.fromEntries((perf.metrics || []).map((m) => [m.name, m.value]));
  const net = [...netRequests.values()]
    .filter((r) => r.end)
    .map((r) => ({
      url: r.url.split('/').slice(-1)[0].split('?')[0],
      status: r.status, mime: r.mime, bytes: r.bytes,
      ms: +((r.end - r.start) * 1000).toFixed(0),
      ce: r.headers?.['content-encoding'] || r.headers?.['Content-Encoding'] || null,
    }))
    .sort((a, b) => b.bytes - a.bytes)
    .slice(0, 25);

  const cpu = metrics.CumulativeTaskTime ? +metrics.CumulativeTaskTime.toFixed(2) : null;
  const out = {
    tag: TAG, url: URL_, viewport: { W, H, DPR, mobile: MOBILE }, cpuThrottle: CPU,
    chrome: version.Browser, bootMs: boot?.ms ?? null, bootCanvas: boot?.canvas ?? null,
    probe, fpsSeries, frameStats: summarizeFrames(frames),
    shader, cpuTop,
    longtasks: longtasks.slice(0, 60),
    longTaskTotalMs: +longtasks.reduce((a, b) => a + b.dur, 0).toFixed(0),
    resources, net, console: consoleLines.slice(0, 120), pageErrors,
    metrics: {
      TaskDuration: metrics.TaskDuration, ScriptDuration: metrics.ScriptDuration,
      LayoutDuration: metrics.LayoutDuration, RecalcStyleDuration: metrics.RecalcStyleDuration,
      JSHeapUsedMB: metrics.JSHeapUsedSize ? +(metrics.JSHeapUsedSize / 1048576).toFixed(1) : null,
      Nodes: metrics.Nodes, Documents: metrics.Documents,
    },
  };
  writeFileSync(join(OUT, `${TAG}.json`), JSON.stringify(out, null, 2));
  console.log(JSON.stringify({
    tag: TAG, bootMs: out.bootMs, canvas: out.probe.canvas, dpr: out.probe.dpr,
    glRenderer: out.probe.glRenderer, hc: out.probe.hardwareConcurrency, dm: out.probe.deviceMemory,
    fpsMean: out.frameStats?.fpsMean, p95: out.frameStats?.p95, over50: out.frameStats?.over50msPct,
    fpsSeries, longTaskTotalMs: out.longTaskTotalMs, heapMB: out.metrics.JSHeapUsedMB,
    shader: out.shader ? { links: out.shader.links, linkBlockMs: out.shader.linkBlockMs, compiles: out.shader.compiles, compileMs: out.shader.compileMs, blocks: out.shader.blocks.length, worst: out.shader.blocks.slice().sort((a,b)=>b.ms-a.ms).slice(0,5) } : null,
    cpuTop: out.cpuTop,
    resources: out.resources.map((r) => [r.name, r.transfer, r.dur]),
    topNet: out.net.slice(0, 4).map((n) => [n.url, n.bytes, n.ms, n.ce]),
  }, null, 1));
}

main().then(() => { cleanup(); process.exit(0); }).catch((e) => {
  console.error('FAIL', e);
  cleanup();
  process.exit(1);
});
