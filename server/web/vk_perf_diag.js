/* VK/webview performance probe for three-skies.
 *
 * Self-contained, no dependencies, inert unless the page is opened with
 * ?perf=1 (or window.__TS_PERF is set before this file loads). The normal
 * game never pays for it: without the query the file returns before it
 * touches any prototype or adds a DOM node.
 *
 * Collapsed panel (two lines):
 *   FPS 44.7  p95 16.9ms  1266x585  dpr1.5/3  SH 133/64.6s  40MB
 *   ANGLE-D3D11 | longtasks 12 34.6s max 2.4s | heap 40MB
 * Tap it to expand: renderer/vendor/GL, canvas vs CSS, cpu/mem, shader
 * worst link, boot timings, VK Bridge, clamp state.
 *
 * Why shader links: the Web build uses the Compatibility renderer, so every
 * new material variant is linked by the driver on the main thread.
 * gl.getProgramParameter(LINK_STATUS) blocks until the driver is done, which
 * is the visible freeze. On Windows/ANGLE-D3D11 one link measured ~2.3 s.
 *
 * Usage in a real VK session:
 *   1) open the game URL with &perf=1 (the VK shell forwards query params),
 *   2) the panel shows the summary; tap it to expand,
 *   3) send a screenshot and/or the "[VKPERF]" console lines (every 5 s),
 *   4) window.__vkperfReport() returns the same data as a JSON string.
 */
(function () {
  'use strict';
  if (window.__vkperfDiag) return;
  var on = window.__TS_PERF === true ||
    /(^|[?&])perf=1(&|$)/.test(window.location.search || '');
  if (!on) return;
  window.__vkperfDiag = true;

  var t0 = performance.now();
  var frameTimes = [];
  var deltas = [];
  var lastFrame = 0;
  var longTasks = { n: 0, ms: 0, max: 0 };
  var shader = { links: 0, blockMs: 0, worst: 0, blocks: 0 };
  var boot = { firstFrameMs: null, loaderHiddenMs: null };
  var errors = [];

  try {
    new PerformanceObserver(function (list) {
      list.getEntries().forEach(function (e) {
        longTasks.n++; longTasks.ms += e.duration;
        if (e.duration > longTasks.max) longTasks.max = e.duration;
      });
    }).observe({ entryTypes: ['longtask'] });
  } catch (e) { errors.push('longtask:' + e); }

  try {
    var G = window.WebGL2RenderingContext || window.WebGLRenderingContext;
    if (G && G.prototype) {
      var p = G.prototype;
      var get = p.getProgramParameter;
      var link = p.linkProgram;
      p.linkProgram = function (prog) { shader.links++; return link.call(this, prog); };
      p.getProgramParameter = function (prog, pname) {
        var s = performance.now();
        var r = get.call(this, prog, pname);
        if (this.LINK_STATUS !== undefined && pname === this.LINK_STATUS) {
          var dt = performance.now() - s;
          shader.blockMs += dt;
          if (dt > 30) shader.blocks++;
          if (dt > shader.worst) shader.worst = dt;
        }
        return r;
      };
    }
  } catch (e) { errors.push('shader:' + e); }

  // GL facts come from a throwaway context so the game's own state is untouched.
  var gl = null;
  try {
    var probe = document.createElement('canvas');
    gl = probe.getContext('webgl2') || probe.getContext('webgl');
  } catch (e) {}
  var dbg = gl && gl.getExtension('WEBGL_debug_renderer_info');
  var glInfo = {
    renderer: dbg ? gl.getParameter(dbg.UNMASKED_RENDERER_WEBGL) : (gl ? gl.getParameter(gl.RENDERER) : 'none'),
    vendor: dbg ? gl.getParameter(dbg.UNMASKED_VENDOR_WEBGL) : (gl ? gl.getParameter(gl.VENDOR) : 'none'),
    version: gl ? gl.getParameter(gl.VERSION) : 'none',
    webgl2: !!(window.WebGL2RenderingContext && probe.getContext('webgl2')),
    maxTex: gl ? gl.getParameter(gl.MAX_TEXTURE_SIZE) : 0,
  };

  function gpuToken(name) {
    var s = String(name || '').toLowerCase();
    if (s.indexOf('angle') !== -1) {
      if (s.indexOf('d3d11') !== -1) return 'ANGLE-D3D11';
      if (s.indexOf('vulkan') !== -1) return 'ANGLE-Vulkan';
      if (s.indexOf('metal') !== -1) return 'ANGLE-Metal';
      if (s.indexOf('opengl') !== -1) return 'ANGLE-GL';
      return 'ANGLE';
    }
    if (s.indexOf('swiftshader') !== -1) return 'SwiftShader';
    if (s.indexOf('adreno') !== -1) return 'Adreno';
    if (s.indexOf('mali') !== -1) return 'Mali';
    if (s.indexOf('apple') !== -1) return 'Apple';
    if (s.indexOf('radeon') !== -1 || s.indexOf('amd') !== -1) return 'AMD';
    if (s.indexOf('nvidia') !== -1 || s.indexOf('geforce') !== -1) return 'NVIDIA';
    if (s.indexOf('intel') !== -1) return 'Intel';
    return 'GPU';
  }

  function dps() {
    if (window.__tsDpr && window.__tsDpr.native) return window.__tsDpr;
    return { native: window.devicePixelRatio || 1, applied: window.devicePixelRatio || 1, capped: false };
  }

  function nowFps() {
    if (frameTimes.length < 2) return 0;
    var span = frameTimes[frameTimes.length - 1] - frameTimes[0];
    return span > 0 ? (frameTimes.length - 1) * 1000 / span : 0;
  }

  function p95() {
    if (deltas.length < 20) return 0;
    var d = deltas.slice().sort(function (a, b) { return a - b; });
    return d[Math.min(d.length - 1, Math.floor(d.length * 0.95))];
  }

  var panel = document.createElement('div');
  panel.id = 'vkperf';
  panel.style.cssText = [
    'position:fixed', 'left:8px', 'top:8px', 'z-index:2147483000',
    'font:11px/1.35 ui-monospace,Menlo,Consolas,monospace',
    'color:#c8ffd0', 'background:rgba(4,8,14,.82)', 'border:1px solid rgba(120,200,140,.45)',
    'border-radius:6px', 'padding:6px 8px', 'max-width:96vw', 'white-space:pre',
    'pointer-events:auto', 'user-select:text', 'text-shadow:0 1px 2px #000',
  ].join(';');
  var head = document.createElement('div');
  var rest = document.createElement('div');
  rest.style.display = 'none';
  panel.appendChild(head);
  panel.appendChild(rest);
  var open = false;
  panel.addEventListener('click', function () {
    open = !open;
    rest.style.display = open ? 'block' : 'none';
    render(true);
  });

  function snapshot() {
    var c = document.getElementById('canvas');
    var mem = performance.memory ? performance.memory.usedJSHeapSize / 1048576 : null;
    var st = document.getElementById('status');
    var dpr = dps();
    return {
      url: location.href,
      ua: navigator.userAgent,
      renderer: glInfo.renderer,
      gpu: gpuToken(glInfo.renderer),
      vendor: glInfo.vendor,
      glVersion: glInfo.version,
      webgl2: glInfo.webgl2,
      maxTexture: glInfo.maxTex,
      dpr: dpr.applied,
      dprNative: dpr.native,
      dprCapped: dpr.capped,
      screen: [screen.width, screen.height],
      inner: [innerWidth, innerHeight],
      canvas: c ? [c.width, c.height, c.clientWidth, c.clientHeight] : null,
      hardwareConcurrency: navigator.hardwareConcurrency,
      deviceMemory: navigator.deviceMemory == null ? null : navigator.deviceMemory,
      crossOriginIsolated: !!window.crossOriginIsolated,
      vkBridge: typeof window.vkBridge,
      fps: +nowFps().toFixed(1),
      frameP95Ms: +p95().toFixed(1),
      longTasks: { n: longTasks.n, totalMs: Math.round(longTasks.ms), maxMs: Math.round(longTasks.max) },
      shaderLinks: shader.links,
      shaderBlockMs: Math.round(shader.blockMs),
      shaderWorstMs: Math.round(shader.worst),
      heapMB: mem == null ? null : +mem.toFixed(1),
      bootFirstFrameMs: boot.firstFrameMs,
      bootLoaderHiddenMs: boot.loaderHiddenMs,
      elapsedS: +((performance.now() - t0) / 1000).toFixed(1),
      loaderVisible: !!(st && getComputedStyle(st).display !== 'none' && st.style.visibility !== 'hidden'),
      errors: errors.slice(0, 3),
    };
  }

  function render(force) {
    var r = snapshot();
    var c = r.canvas || [0, 0, 0, 0];
    var dprText = r.dprCapped
      ? 'dpr' + r.dpr + '/' + r.dprNative
      : 'dpr' + r.dpr;
    head.textContent =
      'FPS ' + r.fps + '  p95 ' + r.frameP95Ms + 'ms  ' + c[0] + 'x' + c[1] +
      '  ' + dprText + '  SH ' + r.shaderLinks + '/' + (r.shaderBlockMs / 1000).toFixed(1) + 's' +
      '  ' + (r.heapMB == null ? 'heap n/a' : r.heapMB + 'MB') + '\n' +
      r.gpu + ' | LT ' + r.longTasks.n + ' ' + (r.longTasks.totalMs / 1000).toFixed(1) + 's' +
      ' (max ' + (r.longTasks.maxMs / 1000).toFixed(1) + 's)';
    if (open || force) {
      rest.textContent = [
        'renderer ' + r.renderer,
        'vendor ' + r.vendor,
        'gl ' + r.glVersion + '  webgl2=' + r.webgl2 + '  maxTex=' + r.maxTexture,
        'canvas ' + (r.canvas || []).join(' / ') + '  css ' + innerWidth + 'x' + innerHeight,
        'dpr ' + r.dpr + ' (native ' + r.dprNative + ', capped=' + r.dprCapped + ')',
        'cpu ' + r.hardwareConcurrency + '  mem ' + r.deviceMemory + 'GB  heap ' + r.heapMB + 'MB',
        'fps ' + r.fps + '  p95 ' + r.frameP95Ms + 'ms  elapsed ' + r.elapsedS + 's',
        'longtasks ' + r.longTasks.n + ' ' + r.longTasks.totalMs + 'ms max ' + r.longTasks.maxMs + 'ms',
        'shader links ' + r.shaderLinks + '  block ' + (r.shaderBlockMs / 1000).toFixed(1) + 's' +
          '  worst ' + r.shaderWorstMs + 'ms',
        'boot first-frame ' + r.bootFirstFrameMs + 'ms  loader-hidden ' + r.bootLoaderHiddenMs + 'ms',
        'vkBridge ' + r.vkBridge + '  coi ' + r.crossOriginIsolated,
        'tap to collapse',
      ].join('\n');
    }
    return r;
  }

  var lastPaint = 0;
  function tick(ts) {
    requestAnimationFrame(tick);
    if (lastFrame > 0) {
      var dt = ts - lastFrame;
      if (dt > 0 && dt < 2000) {
        deltas.push(dt);
        if (deltas.length > 240) deltas.shift();
      }
    }
    lastFrame = ts;
    if (boot.firstFrameMs == null) boot.firstFrameMs = Math.round(performance.now());
    frameTimes.push(ts);
    while (frameTimes.length > 2 && ts - frameTimes[0] > 1000) frameTimes.shift();
    if (boot.loaderHiddenMs == null) {
      var st = document.getElementById('status');
      if (st && (getComputedStyle(st).display === 'none' || st.style.visibility === 'hidden')) {
        boot.loaderHiddenMs = Math.round(performance.now());
      }
    }
    // 4 Hz is plenty for a screenshot and keeps the probe off the frame budget.
    if (ts - lastPaint >= 250) {
      lastPaint = ts;
      render(false);
    }
  }

  function report() { return JSON.stringify(render(true)); }

  function boot2() {
    document.body.appendChild(panel);
    render(true);
    requestAnimationFrame(tick);
    window.__vkperfReport = report;
    setInterval(function () {
      try { console.log('[VKPERF] ' + JSON.stringify(snapshot())); } catch (e) {}
    }, 5000);
    console.log('[VKPERF] probe armed ' + location.href);
  }

  if (document.body) boot2();
  else document.addEventListener('DOMContentLoaded', boot2);
})();
