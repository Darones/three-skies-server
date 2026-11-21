"""Copy the HTML5 build into server/web for the RelaxDev Docker image.

GitHub Pages is not reachable at a usable speed from Russia. The game server
already runs on RelaxDev, so the same origin serves the game, REST and WS.

The export uses a timestamped PCK name for GitHub Pages cache busting. On our
own server the PCK is served with Cache-Control: no-cache, so a fixed
index.pck keeps the repository small and the HTML simple.
"""

import shutil
from pathlib import Path

from patch_chunk_loader import patch as patch_chunk_loader

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "build" / "web"
DST = ROOT / "server" / "web"


def main() -> None:
    html_path = SRC / "index.html"
    if not html_path.exists():
        raise SystemExit(f"missing {html_path}; run tools/web_export.py first")
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

    total = 0
    for source in SRC.iterdir():
        if not source.is_file():
            continue
        if source == pack:
            target = DST / "index.pck"
        else:
            target = DST / source.name
        shutil.copy2(source, target)
        total += target.stat().st_size

    html = html.replace(str(pack.name), "index.pck")
    (DST / "index.html").write_text(html, encoding="utf-8", newline="")
    patch_chunk_loader(DST / "index.html")
    print(f"SERVER_WEB {DST} files={len(list(DST.iterdir()))} bytes={total}")
    print(f"PCK {pack.name} -> index.pck")


if __name__ == "__main__":
    main()
