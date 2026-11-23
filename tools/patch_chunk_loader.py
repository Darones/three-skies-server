"""Patch a Godot web export so the main PCK is fetched with Range requests.

RelaxDev's edge proxy drops a single response larger than about 20 MB with
ERR_HTTP2_PROTOCOL_ERROR. The PCK is 45.9 MB, so the loader would stop at the
splash screen. Fetch it in 10 MB ranges and hand the merged buffer to the
engine instead of the single response.

The first request is a 1-byte range probe: it returns the real size in
Content-Range. A cached index.html after a redeploy may still carry the old
fileSizes value, and trusting it produced "Game data is incomplete" on
VK/iOS. The server size always wins.
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
			engine.preloadFile = function (file, path) {
				if (file !== mainPack || typeof fetch !== 'function') {
					return originalPreloadFile(file, path);
				}
				const declared = (GODOT_CONFIG.fileSizes && GODOT_CONFIG.fileSizes[mainPack]) || 0;
				const bar = document.getElementById('status-progress');
				// Ask the server for the real size first. A cached index.html
				// may carry an old fileSizes value after a redeploy; trusting
				// it truncated the pack or read past its end.
				return fetch(mainPack, {
					credentials: 'same-origin',
					cache: 'no-store',
					headers: { 'Range': 'bytes=0-0' },
				}).then(function (probe) {
					if (!probe.ok && probe.status !== 206) {
						throw new Error('Failed to load game data: ' + probe.status);
					}
					const range = probe.headers.get('Content-Range') || '';
					const match = /\\/(\\d+)$/.exec(range);
					const total = match ? parseInt(match[1], 10) : declared;
					if (!total) {
						return originalPreloadFile(file, path);
					}
					return probe.arrayBuffer().then(function () {
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
									throw new Error('Failed to load game data: ' + response.status);
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
								throw new Error('Game data is incomplete: ' + size + '/' + total);
							}
							const merged = new Uint8Array(size);
							let offset = 0;
							for (const part of parts) {
								merged.set(part, offset);
								offset += part.byteLength;
							}
							return originalPreloadFile(merged.buffer, path);
						});
					});
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
