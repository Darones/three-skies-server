"""Copy the VK HTML5 build into server/web-vk for the RelaxDev Docker image.

The VK build has its own PCK (the `vk` export feature tag selects VKAdapter).
Only index.html and index.pck differ from the standalone export; the server
falls back to server/web for the shared JS/WASM assets.
"""

import shutil
from pathlib import Path

from patch_chunk_loader import patch as patch_chunk_loader

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "build" / "web-vk"
DST = ROOT / "server" / "web-vk"
RESET_SCRIPT = (
    '<script>\n'
    "\t\t(function(){try{if(new URLSearchParams(location.search).has('reset'))"
    "{localStorage.removeItem('three_skies_player_id');"
    "localStorage.removeItem('three_skies_nickname');}}catch(e){}})();\n"
    "\t\t</script>\n"
    "\t\t"
)


def inject_reset_script(html: str) -> str:
    if "three_skies_player_id');localStorage.removeItem('three_skies_nickname')" in html:
        return html
    needle = '<script src="vk-bridge.min.js"></script>'
    if needle not in html:
        return html
    return html.replace(needle, RESET_SCRIPT + needle, 1)


def main() -> None:
    html_path = SRC / "index.html"
    if not html_path.exists():
        raise SystemExit(f"missing {html_path}; run tools/web_export.py --platform vk first")
    html = html_path.read_text(encoding="utf-8")
    packs = sorted(SRC.glob("index_*.pck"))
    if len(packs) != 1:
        raise SystemExit(f"expected one index_*.pck in {SRC}, found {len(packs)}")
    pack = packs[0]

    DST.mkdir(parents=True, exist_ok=True)
    for old in DST.iterdir():
        if old.is_file():
            old.unlink()
        elif old.is_dir():
            shutil.rmtree(old)

    # index.js/index.wasm/splash/fonts are identical to the standalone build;
    # the server serves them from server/web at runtime. Ship only the files
    # that really differ, so the deployment branch does not gain another copy
    # of the 39 MB WASM.
    total = 0
    for source in [html_path, pack]:
        target = DST / ("index.pck" if source == pack else source.name)
        shutil.copy2(source, target)
        total += target.stat().st_size

    html = html.replace(str(pack.name), "index.pck")
    html = inject_reset_script(html)
    (DST / "index.html").write_text(html, encoding="utf-8", newline="")
    patch_chunk_loader(DST / "index.html")
    print(f"SERVER_WEB_VK {DST} files={len(list(DST.iterdir()))} bytes={total}")
    print(f"PCK {pack.name} -> index.pck")


if __name__ == "__main__":
    main()
