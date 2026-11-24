import argparse
import shutil
import subprocess
import time
from pathlib import Path

from patch_chunk_loader import patch as patch_chunk_loader

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "project.godot"
BACKUP = ROOT / "project.godot.web_backup"
OUT_DIR = ROOT / "build" / "web"
PRESET_NAMES = {
    "standalone": "Web Standalone",
    "vk": "Web VK",
}
OUTPUT_DIRS = {
    # `build/web` stays the production standalone folder used by the deploy.
    "standalone": ROOT / "build" / "web",
    "vk": ROOT / "build" / "web-vk",
}


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
    # The exported index.png is the default boot splash and is no longer
    # referenced by the patched HTML; keep the build small.
    (OUT_DIR / "index.png").unlink(missing_ok=True)
    print("SPLASH patched")


def copy_editor_page() -> None:
    editor = ROOT / "ui_editor.html"
    if not editor.exists():
        print("EDITOR skipped")
        return
    shutil.copy2(editor, OUT_DIR / "ui_editor.html")
    for source_name, target_name in (
        ("Philosopher-Regular.ttf", "philosopher.ttf"),
        ("Philosopher-Bold.ttf", "philosopher_bold.ttf"),
    ):
        source = ROOT / "assets" / "fonts" / source_name
        if source.exists():
            shutil.copy2(source, OUT_DIR / target_name)
    print("EDITOR copied")


def main() -> None:
    global OUT_DIR
    parser = argparse.ArgumentParser(description="Export a platform-specific web build.")
    parser.add_argument(
        "--platform",
        choices=tuple(PRESET_NAMES),
        default="standalone",
        help="standalone (no SDK) or vk (VK Bridge shell, adapters still stubbed)",
    )
    args = parser.parse_args()
    OUT_DIR = OUTPUT_DIRS[args.platform]
    preset = PRESET_NAMES[args.platform]
    print("PLATFORM", args.platform, "PRESET", preset, "OUT", OUT_DIR)

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
                preset,
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
    if args.platform == "vk":
        patch_vk_bridge()
    else:
        print("VK_BRIDGE not included in standalone build")
    patch_splash()
    copy_editor_page()

    print("FILES")
    total = 0
    for p in sorted(OUT_DIR.iterdir()):
        size = p.stat().st_size
        total += size
        print(f"  {p.name}: {size}")
    print(f"TOTAL {total}")


if __name__ == "__main__":
    main()
