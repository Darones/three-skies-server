import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "project.godot"
BACKUP = ROOT / "project.godot.web_backup"
OUT_DIR = ROOT / "build" / "web"


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


def main() -> None:
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
                "Web",
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

    print("FILES")
    total = 0
    for p in sorted(OUT_DIR.iterdir()):
        size = p.stat().st_size
        total += size
        print(f"  {p.name}: {size}")
    print(f"TOTAL {total}")


if __name__ == "__main__":
    main()
