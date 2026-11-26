"""Patch a Godot web export so the main PCK is fetched with Range requests.

RelaxDev's edge proxy drops a single response larger than about 20 MB with
ERR_HTTP2_PROTOCOL_ERROR. The PCK is ~49 MB, so the loader would stop at the
splash screen. Fetch it in 10 MB ranges and hand the merged buffer to the
engine instead of the single response.

The merge buffer is allocated once and each chunk is copied into it. The old
loader kept every 10 MB chunk alive and then allocated another 49 MB buffer,
which could push an iPhone tab over Safari's memory limit ("Load failed").
Chunks also retry three times, and a proxy that ignores Range (HTTP 200) is
accepted as a full pack instead of failing with a size mismatch.

No 1-byte probe: on iOS/VK webview a probe Range request was unreliable and the
engine reported "Load failed". The real size is taken from the Content-Range
of the first chunk, so a cached index.html with an old fileSizes value cannot
truncate or overrun the pack either.

On failure a readable DOM overlay shows the exact reason and a retry button
instead of only the engine's "Load failed" dialog.

Ranges are fetched with cache: 'no-cache', not 'no-store'. The server sends a
strong ETag for the pack, so re-launching an unchanged build revalidates each
range to a bodyless 304 instead of downloading 49 MB again, while a redeployed
pack gets a new ETag and is downloaded fresh.
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
					while (box.firstChild) {
						box.removeChild(box.firstChild);
					}
					const text = document.createElement('div');
					text.textContent = 'Не удалось загрузить игру: ' + message;
					box.appendChild(text);
					const retry = document.createElement('button');
					retry.textContent = 'Повторить';
					retry.style.marginTop = '12px';
					retry.style.padding = '10px 22px';
					retry.style.border = '2px solid #ffb3b3';
					retry.style.borderRadius = '10px';
					retry.style.background = '#5b1d24';
					retry.style.color = '#ffffff';
					retry.style.font = '18px system-ui, sans-serif';
					retry.onclick = function () { window.location.reload(); };
					box.appendChild(retry);
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
				let merged = new Uint8Array(total);
				let filled = 0;
				let next = 0;
				function loadNext() {
					if (next >= total) {
						return Promise.resolve();
					}
					const start = next;
					const end = Math.min(start + PACK_RANGE_CHUNK, total) - 1;
					function fetchChunk(attempt) {
						return fetch(mainPack, {
							credentials: 'same-origin',
							// A redeploy swaps index.pck in place, so no stored
							// range may be trusted blindly: no-cache makes the
							// browser revalidate every chunk. The server answers
							// 304 while the pack is unchanged (no body, the
							// cached 49 MB stays on disk) and 200/206 with new
							// bytes after a deploy, so an old pack can never be
							// merged with fresh ranges ("Game data is
							// incomplete"). no-store would re-download all of it
							// on every launch.
							cache: 'no-cache',
							headers: { 'Range': 'bytes=' + start + '-' + end },
						}).then(function (response) {
							if (response.status === 200) {
								// A proxy ignored Range and sent the whole pack.
								return response.arrayBuffer().then(function (buffer) {
									merged = new Uint8Array(buffer);
									filled = merged.byteLength;
									total = filled;
									next = total;
									if (bar) {
										bar.max = total;
										bar.value = total;
									}
								});
							}
							if (response.status !== 206) {
								throw new Error('HTTP ' + response.status + ' (range)');
							}
							const contentRange = response.headers.get('Content-Range') || '';
							const match = /\\/(\\d+)$/.exec(contentRange);
							if (match) {
								const real = parseInt(match[1], 10);
								if (real > 0 && real !== total) {
									const resized = new Uint8Array(real);
									resized.set(merged.subarray(0, filled));
									merged = resized;
									total = real;
									if (bar) {
										bar.max = total;
									}
								}
							}
							return response.arrayBuffer();
						}).then(function (buffer) {
							if (next >= total) {
								return;
							}
							const chunk = new Uint8Array(buffer);
							const expected = end - start + 1;
							if (chunk.byteLength !== expected) {
								throw new Error('чанк ' + chunk.byteLength + '/' + expected);
							}
							if (filled + chunk.byteLength > merged.byteLength) {
								throw new Error('переполнение PCK');
							}
							merged.set(chunk, filled);
							filled += chunk.byteLength;
							next = end + 1;
							if (bar) {
								bar.max = total;
								bar.value = Math.min(filled, total);
							}
						}).catch(function (err) {
							if (attempt < 3) {
								return new Promise(function (resolve) {
									setTimeout(resolve, 600 * attempt);
								}).then(function () {
									return fetchChunk(attempt + 1);
								});
							}
							throw err;
						});
					}
					return fetchChunk(1).then(loadNext);
				}
				return loadNext().then(function () {
					if (filled !== total) {
						throw new Error('данные неполные: ' + filled + '/' + total);
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
