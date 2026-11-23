"""Patch a Godot web export so the main PCK is fetched with Range requests.

RelaxDev's edge proxy drops a single response larger than about 20 MB with
ERR_HTTP2_PROTOCOL_ERROR. The PCK is 45.9 MB, so the loader would stop at the
splash screen. Fetch it in 10 MB ranges and hand the merged buffer to the
engine instead of the single response.

No 1-byte probe: on iOS/VK webview a probe Range request was unreliable and the
engine reported "Load failed". The real size is taken from the Content-Range
of the first chunk, so a cached index.html with an old fileSizes value cannot
truncate or overrun the pack either.

On failure a readable DOM overlay shows the exact reason instead of only the
engine's "Load failed" dialog.
"""

import sys
from pathlib import Path

MARKER = "PACK_RANGE_CHUNK"
SCRIPT = """
	// __MARKER__ __VALUE__
	window.__packRangeChunk = 'start';
	(function () {
		try {
			const PACK_RANGE_CHUNK = 10 * 1024 * 1024;
			if (typeof GODOT_CONFIG === 'undefined' || !GODOT_CONFIG.mainPack) {
				return;
			}
			const mainPack = GODOT_CONFIG.mainPack;
			const originalPreloadFile = engine.preloadFile.bind(engine);
			function showPackError(message) {
				try {
					let box = document.getElementById('pack-load-error');
					if (!box) {
						box = document.createElement('div');
						box.id = 'pack-load-error';
						box.style.position = 'fixed';
						box.style.left = '50%';
						box.style.top = '18%';
						box.style.transform = 'translateX(-50%)';
						box.style.maxWidth = '80%';
						box.style.padding = '14px 20px';
						box.style.background = 'rgba(42,13,18,0.96)';
						box.style.color = '#ffb3b3';
						box.style.border = '2px solid #ff6b6b';
						box.style.borderRadius = '14px';
						box.style.font = '18px system-ui, sans-serif';
						box.style.textAlign = 'center';
						box.style.zIndex = '999999';
						document.body.appendChild(box);
					}
					box.textContent = 'Не удалось загрузить игру: ' + message;
				} catch (ignored) {}
				if (window.console) {
					console.error('[PACK] ' + message);
				}
			}
			engine.preloadFile = function (file, path) {
				if (file !== mainPack || typeof fetch !== 'function') {
					return originalPreloadFile(file, path);
				}
				let total = (GODOT_CONFIG.fileSizes && GODOT_CONFIG.fileSizes[mainPack]) || 0;
				if (!total) {
					return originalPreloadFile(file, path);
				}
				const bar = document.getElementById('status-progress');
				if (bar) {
					bar.max = total;
					bar.value = 0;
				}
				const parts = [];
				let next = 0;
				function loadNext() {
					if (next >= total) {
						return Promise.resolve();
					}
					const start = next;
					const end = Math.min(start + PACK_RANGE_CHUNK, total) - 1;
					next = end + 1;
					return fetch(mainPack, {
						credentials: 'same-origin',
						// A redeploy swaps index.pck in place. Without no-store
						// the browser can merge a cached old PCK with fresh
						// ranges ("Game data is incomplete").
						cache: 'no-store',
						headers: { 'Range': 'bytes=' + start + '-' + end },
					}).then(function (response) {
						if (!response.ok) {
							throw new Error('HTTP ' + response.status);
						}
						const contentRange = response.headers.get('Content-Range') || '';
						const match = /\\/(\\d+)$/.exec(contentRange);
						if (match) {
							const real = parseInt(match[1], 10);
							if (real > 0 && real !== total) {
								total = real;
								if (bar) {
									bar.max = total;
								}
							}
						}
						return response.arrayBuffer();
					}).then(function (buffer) {
						parts.push(new Uint8Array(buffer));
						if (bar) {
							bar.max = total;
							bar.value = Math.min(next, total);
						}
						return loadNext();
					});
				}
				return loadNext().then(function () {
					let size = 0;
					for (const part of parts) {
						size += part.byteLength;
					}
					if (size !== total) {
						throw new Error('данные неполные: ' + size + '/' + total);
					}
					const merged = new Uint8Array(size);
					let offset = 0;
					for (const part of parts) {
						merged.set(part, offset);
						offset += part.byteLength;
					}
					return originalPreloadFile(merged.buffer, path);
				}).catch(function (err) {
					showPackError(err && err.message ? err.message : err);
					throw err;
				});
			};
			window.__packRangeChunk = 'patched';
		} catch (err) {
			window.__packRangeChunk = 'error: ' + (err && err.message ? err.message : err);
		}
	})();
"""


def patch(html_path: Path) -> bool:
    html = html_path.read_text(encoding="utf-8")
    if MARKER in html:
        return False
    anchor = "const engine = new Engine(GODOT_CONFIG);"
    if anchor not in html:
        raise SystemExit(f"{html_path}: engine initialization not found")
    block = SCRIPT.replace("__MARKER__", MARKER).replace("__VALUE__", "mainPack")
    html = html.replace(anchor, anchor + "\n" + block, 1)
    html_path.write_text(html, encoding="utf-8", newline="")
    return True


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: patch_chunk_loader.py <index.html> [...]")
    for name in sys.argv[1:]:
        path = Path(name)
        print(("PATCHED " if patch(path) else "ALREADY ") + str(path))


if __name__ == "__main__":
    main()
