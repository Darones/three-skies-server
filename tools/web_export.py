import argparse
import re
import shutil
import subprocess
import time
from pathlib import Path

from patch_chunk_loader import patch as patch_chunk_loader
from vk_perf_web_export_patch import patch_web_shell

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "project.godot"
BACKUP = ROOT / "project.godot.web_backup"
OUT_DIR = ROOT / "build" / "web"
SERVER_WEB = ROOT / "server" / "web"
PRESET_NAME = "Web Standalone"
PLATFORM_SHELLS = ("web-vk", "web-ok")
RESET_SCRIPT = (
    '<script>\n'
    "\t\t(function(){try{if(new URLSearchParams(location.search).has('reset'))"
    "{localStorage.removeItem('three_skies_player_id');"
    "localStorage.removeItem('three_skies_nickname');}}catch(e){}})();\n"
    "\t\t</script>\n"
    "\t\t"
)


def set_method(text: str, method: str) -> str:
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    section = ""
    in_rendering = False
    seen = {"renderer/rendering_method": False, "renderer/rendering_method.mobile": False}

    def flush_missing() -> None:
        for key, present in seen.items():
            if not present:
                out.append(f'{key}="{method}"\n')

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_rendering:
                flush_missing()
            section = stripped[1:-1]
            in_rendering = section == "rendering"
            out.append(line)
            continue
        if in_rendering:
            for key in seen:
                if stripped.startswith(key + "="):
                    eol = "\r\n" if line.endswith("\r\n") else "\n"
                    indent = line[: len(line) - len(line.lstrip())]
                    out.append(f'{indent}{key}="{method}"{eol}')
                    seen[key] = True
                    break
            else:
                out.append(line)
            continue
        out.append(line)
    if in_rendering:
        flush_missing()
    return "".join(out)


PACK_CACHE_BYPASS = "cache: 'no-store'"
PACK_CACHE_REVALIDATE = "cache: 'no-cache'"


def verify_pack_cache() -> None:
    """Fail the export if the PCK loader bypasses the HTTP cache again.

    The pack keeps the name index.pck across deploys, so `cache: 'no-store'`
    made every launch download all ~49 MB again. `cache: 'no-cache'` lets the
    browser revalidate each range: the server sends a strong ETag per file and
    answers 304 while the pack is unchanged (no body), 200/206 after a
    redeploy. See patch_chunk_loader.py and staticGameHandlerWithFallback.
    """
    for path in (OUT_DIR / "index.html", SERVER_WEB / "index.html"):
        if not path.exists():
            continue
        html = path.read_text(encoding="utf-8")
        if PACK_CACHE_BYPASS in html:
            raise SystemExit(
                f"{path}: PCK loader still bypasses the cache ({PACK_CACHE_BYPASS})"
            )
        if PACK_CACHE_REVALIDATE in html:
            print("PACK_CACHE revalidate", path.relative_to(ROOT))
        else:
            print("PACK_CACHE skipped", path.relative_to(ROOT))


def bust_pck() -> None:
    pck = OUT_DIR / "index.pck"
    if not pck.exists():
        print("PCK_BUST skipped")
        return
    stamp = time.strftime("%Y%m%d_%H%M%S")
    new_name = f"index_{stamp}.pck"
    pck.rename(OUT_DIR / new_name)
    html_path = OUT_DIR / "index.html"
    html = html_path.read_text(encoding="utf-8")
    html = html.replace('"index.pck":', f'"{new_name}":')
    html = html.replace(
        '"executable":"index",',
        f'"executable":"index","mainPack":"{new_name}",',
    )
    html_path.write_text(html, encoding="utf-8", newline="")
    print("PCK_BUST", new_name)


def patch_vk_bridge() -> None:
    # The single build serves VK and OK as well as standalone, so its shell
    # always ships VK Bridge. Adapter selection happens at runtime in
    # scripts/platform/platform.gd.
    bridge_src = ROOT / "tools" / "vk-bridge.min.js"
    if not bridge_src.exists():
        print("VK_BRIDGE skipped")
        return
    shutil.copy2(bridge_src, OUT_DIR / "vk-bridge.min.js")
    html_path = OUT_DIR / "index.html"
    html = html_path.read_text(encoding="utf-8")
    if "vk-bridge.min.js" in html:
        return
    needle = '<script src="index.js"></script>'
    if needle not in html:
        print("VK_BRIDGE index.js script not found")
        return
    block = (
        '<script src="vk-bridge.min.js"></script>\n'
        "\t\t<script>\n"
        "\t\t\twindow.__tsVKInit = window.vkBridge\n"
        "\t\t\t\t? window.vkBridge.send('VKWebAppInit').catch(function () {})\n"
        "\t\t\t\t: Promise.resolve();\n"
        "\t\t</script>\n"
        "\t\t"
    )
    html = html.replace(needle, block + needle, 1)
    html_path.write_text(html, encoding="utf-8", newline="")
    print("VK_BRIDGE patched")


def patch_reset_script() -> None:
    html_path = OUT_DIR / "index.html"
    html = html_path.read_text(encoding="utf-8")
    if "three_skies_player_id');localStorage.removeItem('three_skies_nickname')" in html:
        return
    needle = '<script src="vk-bridge.min.js"></script>'
    if needle not in html:
        return
    html = html.replace(needle, RESET_SCRIPT + needle, 1)
    html_path.write_text(html, encoding="utf-8", newline="")
    print("RESET_SCRIPT patched")


def patch_splash() -> None:
    splash = ROOT / "ui" / "splash.jpg"
    if not splash.exists():
        print("SPLASH skipped")
        return
    shutil.copy2(splash, OUT_DIR / "index_splash.jpg")
    html_path = OUT_DIR / "index.html"
    html = html_path.read_text(encoding="utf-8")
    html = html.replace('src="index.png"', 'src="index_splash.jpg"')
    html = html.replace("background-color: #242424;", "background-color: #070a12;")
    html = html.replace("background-color: black;", "background-color: #070a12;")
    html_path.write_text(html, encoding="utf-8", newline="")
    (OUT_DIR / "index.png").unlink(missing_ok=True)
    print("SPLASH patched")


LEGAL_MARKER = "SINGLE_PCK_LEGAL_V3"
LEGAL_CSS = """
		/* SINGLE_PCK_LEGAL_V3: the 12+ badge on the initial loader. The legal
		   documents are already provided by the VK/OK cabinet, so the loader
		   carries no consent line and no outbound links. The platform shells
		   (/game-vk/, /game-ok/) are bare redirects and never get this block. */
		#age-rating {
			position: fixed;
			top: 14px;
			right: 20px;
			z-index: 6;
			color: #ffffff;
			font-family: 'Noto Sans', 'Droid Sans', Arial, sans-serif;
			font-size: 22px;
			font-weight: 700;
			line-height: 1;
			text-shadow: 0 1px 3px rgba(0, 0, 0, 0.95), 1px 0 2px rgba(0, 0, 0, 0.9);
			pointer-events: none;
		}
"""

LEGAL_HTML = """		<div id="age-rating">12+</div>
"""
LEGAL_SCRIPT_NEEDLE = "getElementById('age-rating')"

LEGAL_SCRIPT = """		<script>
		(function () {
			function sync() {
				var status = document.getElementById('status');
				var age = document.getElementById('age-rating');
				var hidden = true;
				if (status) {
					hidden = status.hidden || getComputedStyle(status).display === 'none';
				}
				if (age) age.style.display = hidden ? 'none' : '';
			}
			var status = document.getElementById('status');
			if (status && window.MutationObserver) {
				new MutationObserver(sync).observe(status, { attributes: true, attributeFilter: ['style', 'class', 'hidden'] });
			}
			window.setInterval(sync, 100);
			sync();
		})();
		</script>
"""


def patch_legal_overlay() -> None:
    html_path = OUT_DIR / "index.html"
    html = html_path.read_text(encoding="utf-8")
    if LEGAL_MARKER in html:
        # Already v3: only the 12+ badge, no consent line. Re-runs are no-ops.
        return
    if "</style>" not in html:
        print("LEGAL skipped: no style tag")
        return
    html = html.replace("</style>", LEGAL_CSS + "\t\t</style>", 1)
    if '<div id="status">' in html:
        html = html.replace('<div id="status">', LEGAL_HTML + '<div id="status">', 1)
    elif "</body>" in html:
        html = html.replace("</body>", LEGAL_HTML + "\t</body>", 1)
    # Insert the hide/show observer only if the page has no copy yet, so a
    # re-run never stacks a second interval.
    if LEGAL_SCRIPT_NEEDLE not in html and "</body>" in html:
        html = html.replace("</body>", LEGAL_SCRIPT + "\t</body>", 1)
    html_path.write_text(html, encoding="utf-8", newline="")
    print("LEGAL patched v3")


WEB_META_MARKER = "TS_WEB_META_V1"
WEB_GAME_URL = "https://three-skies-server.relaxdev.ru/game/"
WEB_IMAGE_URL = WEB_GAME_URL + "og-image.jpg"
# Icon files live in ui/ next to logo.png and splash.jpg. The exporter copies
# them under their own names, so /game/favicon.png and friends stay stable.
ICON_ASSETS = (
    "favicon.png",
    "apple-touch-icon.png",
    "favicon.ico",
    "og-image.jpg",
)
META_DESCRIPTION = (
    "«Небесные осколки» — бесплатная командная игра 3v3 за Оболочку: "
    "собирайте небесные осколки, качайте героя и ведите команду к победе. "
    "Играется в браузере на компьютере и телефоне."
)
OG_DESCRIPTION = (
    "Командная игра 3v3 за Оболочку: собирайте небесные осколки и ведите "
    "команду к победе. Бесплатно в браузере."
)
WEB_META_BLOCK = f"""\t\t<!-- {WEB_META_MARKER}:start
\t\t     Language, description, Open Graph and real icons. Written by
\t\t     tools/web_export.py after the export; a re-run replaces this block. -->
\t\t<meta name="description" content="{META_DESCRIPTION}">
\t\t<meta name="theme-color" content="#070a12">
\t\t<meta property="og:site_name" content="Небесные осколки">
\t\t<meta property="og:type" content="website">
\t\t<meta property="og:locale" content="ru_RU">
\t\t<meta property="og:title" content="Небесные осколки">
\t\t<meta property="og:description" content="{OG_DESCRIPTION}">
\t\t<meta property="og:url" content="{WEB_GAME_URL}">
\t\t<meta property="og:image" content="{WEB_IMAGE_URL}">
\t\t<meta property="og:image:type" content="image/jpeg">
\t\t<meta property="og:image:width" content="1200">
\t\t<meta property="og:image:height" content="630">
\t\t<meta property="og:image:alt" content="Небесные осколки: герои 3v3 у небесного осколка">
\t\t<meta name="twitter:card" content="summary_large_image">
\t\t<link rel="icon" type="image/png" sizes="64x64" href="/game/favicon.png">
\t\t<link rel="icon" type="image/x-icon" sizes="32x32" href="/game/favicon.ico">
\t\t<link rel="apple-touch-icon" sizes="180x180" href="/game/apple-touch-icon.png">
\t\t<!-- {WEB_META_MARKER}:end -->
"""
WEB_META_BLOCK_RE = re.compile(
    r"[ \t]*<!--\s*TS_WEB_META_V1:start\b.*?<!--\s*TS_WEB_META_V1:end\s*-->[ \t]*\r?\n?",
    re.S,
)
# Godot exports a placeholder icon pair (index.icon.png / index.apple-touch-icon.png)
# that renders as an empty grey square. Both are dropped when our links go in.
GD_PLACEHOLDER_ICONS_RE = re.compile(
    r"[ \t]*<link\b[^>]*(?:index\.icon\.png|index\.apple-touch-icon\.png)[^>]*>[ \t]*\r?\n?",
    re.I,
)


def _set_html_lang(html: str, lang: str) -> str:
    """Force the <html> language attribute, adding it when the export has none."""
    match = re.search(r"<html\b[^>]*>", html, re.I)
    if not match:
        return html
    tag = match.group(0)
    if re.search(r"\blang\s*=", tag, re.I):
        tag = re.sub(
            r"\blang\s*=\s*([\"'])[^\"']*\1", f'lang="{lang}"', tag, count=1, flags=re.I
        )
    else:
        tag = tag[:-1].rstrip() + f' lang="{lang}">'
    return html[: match.start()] + tag + html[match.end() :]


def patch_meta_and_icons() -> None:
    """Icons, `<html lang="ru">`, description and Open Graph for the export.

    VK/OK moderation and link previews read the head of /game/index.html: it
    used to say lang="en", had no description and showed Godot's empty grey
    placeholder icon. The icons are copied from ui/ as-is, so a rebuild never
    needs Pillow. Runs after export and before prepare_server_web, which is
    what puts the files into server/web. Every step is idempotent: our block
    carries start/end markers and is replaced, never stacked.
    """
    for name in ICON_ASSETS:
        source = ROOT / "ui" / name
        if not source.exists():
            print("META_ICON missing", name)
            continue
        shutil.copy2(source, OUT_DIR / name)

    html_path = OUT_DIR / "index.html"
    if not html_path.exists():
        print("META skipped: no index.html")
        return
    html = html_path.read_text(encoding="utf-8")
    html = _set_html_lang(html, "ru")
    html = GD_PLACEHOLDER_ICONS_RE.sub("", html)
    html = WEB_META_BLOCK_RE.sub("", html)
    close = html.rfind("</head>")
    if close == -1:
        print("META skipped: no </head>")
        html_path.write_text(html, encoding="utf-8", newline="")
        return
    # Insert at the start of the </head> line so the block keeps its indent
    # even when the export puts </head> on a whitespace-only line.
    line_start = html.rfind("\n", 0, close) + 1
    if html[line_start:close].strip():
        line_start, tail = close, ""
    else:
        tail = html[line_start:close]
    html = html[:line_start] + WEB_META_BLOCK + tail + html[close:]
    print("META patched")
    html_path.write_text(html, encoding="utf-8", newline="")


def copy_editor_page() -> None:
    editor = ROOT / "ui_editor.html"
    if not editor.exists():
        print("EDITOR skipped")
        return
    shutil.copy2(editor, OUT_DIR / "ui_editor.html")
    layout_file = ROOT / "ui_layout.json"
    if layout_file.exists():
        shutil.copy2(layout_file, OUT_DIR / "ui_layout.json")
    web_layout_file = ROOT / "ui_layout_web.json"
    if web_layout_file.exists():
        shutil.copy2(web_layout_file, OUT_DIR / "ui_layout_web.json")
    editor_bg = ROOT / "editor-bg"
    if editor_bg.is_dir():
        target_bg = OUT_DIR / "editor-bg"
        if target_bg.exists():
            shutil.rmtree(target_bg)
        shutil.copytree(editor_bg, target_bg)
    for source_name, target_name in (
        ("Philosopher-Regular.ttf", "philosopher.ttf"),
        ("Philosopher-Bold.ttf", "philosopher_bold.ttf"),
    ):
        source = ROOT / "assets" / "fonts" / source_name
        if source.exists():
            shutil.copy2(source, OUT_DIR / target_name)
    print("EDITOR copied")


def copy_payment_icon() -> None:
    # VK/OK require a non-empty photo_url in the order box. Serve the shard
    # icon from the game server, not raw.githubusercontent (OK CSP blocks it).
    icon = ROOT / "ui" / "icons" / "sky_shard.png"
    if not icon.exists():
        print("PAYMENT_ICON skipped")
        return
    shutil.copy2(icon, OUT_DIR / "shard.png")
    print("PAYMENT_ICON copied")


def prepare_server_web(pack: Path) -> None:
    """Copy the single build into server/web as one index.pck."""
    SERVER_WEB.mkdir(parents=True, exist_ok=True)
    for old in SERVER_WEB.iterdir():
        if old.is_file():
            old.unlink()
        elif old.is_dir():
            shutil.rmtree(old)

    html = (OUT_DIR / "index.html").read_text(encoding="utf-8")
    total = 0
    for source in OUT_DIR.iterdir():
        target = SERVER_WEB / ("index.pck" if source == pack else source.name)
        if source.is_dir():
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(source, target)
            continue
        if not source.is_file():
            continue
        shutil.copy2(source, target)
        total += target.stat().st_size
    html = html.replace(pack.name, "index.pck")
    (SERVER_WEB / "index.html").write_text(html, encoding="utf-8", newline="")
    patch_chunk_loader(SERVER_WEB / "index.html")
    verify_pack_cache()
    print(f"SERVER_WEB {SERVER_WEB} files={len(list(SERVER_WEB.iterdir()))} bytes={total}")
    print(f"PCK {pack.name} -> index.pck")


def _redirect_shell(always_ok: bool) -> str:
    marker = "true" if always_ok else "false"
    return f"""<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Небесные осколки</title>
</head>
<body style="margin:0;background:#070a12;color:#e8ecf5;font-family:system-ui,sans-serif">
<p style="padding:24px">Открываем игру…</p>
<script>
(function () {{
  var search = window.location.search || "";
  var hash = window.location.hash || "";
  var addOK = {marker};
  var fromOK = String(document.referrer || "").indexOf("ok.ru") !== -1;
  if ((addOK || fromOK) && search.indexOf("vk_client=ok") === -1) {{
    search += (search ? "&" : "?") + "vk_client=ok";
  }}
  // Preserve every launcher param, including vk_user_id/sign/vk_ts in the
  // query or the hash. The single build detects VK/OK from them at runtime.
  window.location.replace("/game/" + search + hash);
}})();
</script>
<noscript><p style="padding:24px"><a style="color:#f2c35c" href="/game/">Открыть игру</a></p></noscript>
</body>
</html>
"""


def write_platform_shells() -> None:
    """Write thin redirect shells for the old VK/OK URLs.

    The shells contain no PCK: they only forward to /game/ and preserve the
    launch params. `/game-ok/` always marks itself as OK; `/game-vk/` marks
    itself as OK only when the parent frame is ok.ru, because the OK app uses
    the same URL.
    """
    for name in PLATFORM_SHELLS:
        always_ok = name == "web-ok"
        for root in (ROOT / "build" / name, ROOT / "server" / name):
            if root.exists():
                shutil.rmtree(root)
            root.mkdir(parents=True, exist_ok=True)
            (root / "index.html").write_text(
                _redirect_shell(always_ok), encoding="utf-8", newline=""
            )
        print("SHELL", name, "always_ok=" + str(always_ok))


def main() -> None:
    parser = argparse.ArgumentParser(description="Export the single universal web build.")
    parser.add_argument(
        "--platform",
        default="standalone",
        help="kept for compatibility; every value produces the same single build",
    )
    args = parser.parse_args()
    if args.platform != "standalone":
        print("SINGLE_BUILD: --platform", args.platform, "is ignored")
    print("PLATFORM single PRESET", PRESET_NAME, "OUT", OUT_DIR)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    if BACKUP.exists():
        BACKUP.unlink()
    shutil.copy2(PROJECT, BACKUP)
    try:
        original = PROJECT.read_text(encoding="utf-8")
        modified = set_method(original, "gl_compatibility")
        if modified == original:
            raise SystemExit("renderer settings were not found")
        PROJECT.write_text(modified, encoding="utf-8", newline="")
        print("RENDERER", [ln.strip() for ln in modified.splitlines() if "rendering_method" in ln])

        for old in OUT_DIR.iterdir():
            if old.is_file():
                old.unlink()
        result = subprocess.run(
            [
                "godot_console",
                "--headless",
                "--path",
                str(ROOT),
                "--export-release",
                PRESET_NAME,
                str(OUT_DIR / "index.html"),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=1800,
        )
        print("EXPORT_EXIT", result.returncode)
        print(result.stdout[-6000:])
        print(result.stderr[-6000:])
        if result.returncode != 0:
            raise SystemExit(result.returncode)
    finally:
        shutil.copy2(BACKUP, PROJECT)
        BACKUP.unlink()
        print("RESTORED project.godot")

    bust_pck()
    patch_chunk_loader(OUT_DIR / "index.html")
    patch_vk_bridge()
    patch_reset_script()
    patch_splash()
    patch_legal_overlay()
    # Diagnostics + phone DPR cap must be in place before prepare_server_web
    # copies build/web to server/web. The probe is inert without ?perf=1.
    patch_web_shell(OUT_DIR, ROOT)
    copy_editor_page()
    copy_payment_icon()
    # Meta, Open Graph and the real icons must be in place before
    # prepare_server_web copies build/web to server/web.
    patch_meta_and_icons()

    packs = sorted(OUT_DIR.glob("index_*.pck"))
    if len(packs) != 1:
        raise SystemExit(f"expected one index_*.pck in {OUT_DIR}, found {len(packs)}")
    prepare_server_web(packs[0])
    write_platform_shells()

    print("FILES")
    total = 0
    for p in sorted(OUT_DIR.iterdir()):
        size = p.stat().st_size
        total += size
        print(f"  {p.name}: {size}")
    print(f"TOTAL {total}")


if __name__ == "__main__":
    main()
