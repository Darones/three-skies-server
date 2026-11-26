"""Extra files/steps for the web build, applied by tools/web_export.py.

Both helpers are idempotent and only touch build/web (the server/web snapshot
is made afterwards, so the same files land on the game server).

patch_perf_probe  copies tools/vk_perf_diag.js and adds its <script> tag. The
                  probe does nothing unless the page is opened with ?perf=1,
                  so the normal game is byte-for-byte unaffected.
patch_dpr_clamp   caps window.devicePixelRatio on phones/VK before Godot boots.
                  Godot's adaptive canvas policy sizes the backing store as
                  CSS x DPR; on a 844x390 phone at DPR 3 that is 2532x1170 for
                  a HUD that is drawn at 960x540. 1.5 keeps text crisp and
                  removes ~75% of the pixels. Desktop is untouched, and
                  ?dpr=native or ?dpr=<1..3> overrides it for measurements.
"""

import shutil

PERF_MARKER = "vk_perf_diag.js"
DPR_MARKER = "TS_DPR_CLAMP"

DPR_SCRIPT = """		<script>
		/* TS_DPR_CLAMP: phones/VK pay DPR 2.5-4 for a 960x540 HUD. */
		(function () {
			var match = /[?&]dpr=([^&]+)/.exec(window.location.search || '');
			var requested = match ? match[1] : '';
			var nativeDpr = window.devicePixelRatio || 1;
			var cap = 0;
			var phone = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent || '') ||
				(navigator.maxTouchPoints > 0 && Math.min(screen.width, screen.height) <= 900);
			if (requested === 'native' || requested === '0') {
				cap = 0;
			} else if (requested && !isNaN(parseFloat(requested))) {
				cap = Math.max(1, Math.min(3, parseFloat(requested)));
			} else if (phone) {
				cap = 1.5;
			}
			var applied = nativeDpr;
			if (cap > 0 && nativeDpr > cap) {
				applied = cap;
				try {
					Object.defineProperty(window, 'devicePixelRatio', {
						configurable: true,
						get: function () { return applied; }
					});
				} catch (e) {
					try { window.devicePixelRatio = applied; } catch (e2) {}
				}
			}
			window.__tsDpr = { native: nativeDpr, applied: applied, capped: applied < nativeDpr };
		})();
		</script>
"""


def _insert_before_engine(out_dir, block, marker):
    html_path = out_dir / "index.html"
    if not html_path.exists():
        print("PERF_SHELL skipped: no index.html")
        return False
    html = html_path.read_text(encoding="utf-8")
    if marker in html:
        return False
    needle = '<script src="index.js"></script>'
    if needle not in html:
        print("PERF_SHELL skipped: index.js script not found")
        return False
    html = html.replace(needle, block + "\t\t" + needle, 1)
    html_path.write_text(html, encoding="utf-8", newline="")
    return True


def patch_perf_probe(out_dir, root):
    """Ship the ?perf=1 overlay with the build (inert without the query)."""
    src = root / "tools" / "vk_perf_diag.js"
    if not src.exists():
        print("PERF_PROBE skipped: tools/vk_perf_diag.js missing")
        return
    shutil.copy2(src, out_dir / PERF_MARKER)
    block = '<script src="vk_perf_diag.js"></script>\n'
    if _insert_before_engine(out_dir, block, PERF_MARKER):
        print("PERF_PROBE patched")


def patch_dpr_clamp(out_dir, root):
    """Clamp the canvas backing store on phones/VK before the engine starts."""
    if _insert_before_engine(out_dir, DPR_SCRIPT, DPR_MARKER):
        print("DPR_CLAMP patched")


def patch_web_shell(out_dir, root):
    patch_dpr_clamp(out_dir, root)
    patch_perf_probe(out_dir, root)
