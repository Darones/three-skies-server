"""Regenerate server/web and the thin VK/OK shells from the single build.

Kept for compatibility. `tools/web_export.py` already performs the same steps,
so a normal release needs only one command: `python tools/web_export.py`.
"""

from web_export import OUT_DIR, prepare_server_web, write_platform_shells


def main() -> None:
    packs = sorted(OUT_DIR.glob("index_*.pck"))
    if len(packs) != 1:
        raise SystemExit(
            f"expected one index_*.pck in {OUT_DIR}, found {len(packs)}; "
            "run tools/web_export.py first"
        )
    prepare_server_web(packs[0])
    write_platform_shells()


if __name__ == "__main__":
    main()
