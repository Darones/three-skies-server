#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Генерирует 9 иконок товаров боевого магазина через GigaChat и готовит WebP 256x256.

Запуск из корня проекта:
    python tools/generate_shop_icons.py
    python tools/generate_shop_icons.py --only wind_boots
    python tools/generate_shop_icons.py --force
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
GENERATOR = Path.home() / ".config" / "gigachat" / "generate_image.py"
RAW_DIR = ROOT / "generated_images" / "shop" / "raw"
OUT_DIR = ROOT / "assets" / "ui" / "shop"
CONTACT = ROOT / "generated_images" / "shop" / "contact_sheet.jpg"

STYLE = (
    "Ты художник игровых иконок для тёмного фэнтези. Рисуй одну квадратную иконку предмета: "
    "предмет крупным планом по центру, фон — глубокий почти чёрный синий, живопись от края до края, "
    "без текста, без надписей, без букв, без рамок, без карточек товара, без подложек, без белой студии, "
    "без серого фона и белых полей. Стиль: детализированная цифровая живопись, золотое и бирюзовое "
    "свечение, высокий контраст, чистый читаемый силуэт."
)

ITEMS = [
    (
        "life_amulet",
        "Игровая иконка предмета «Амулет Жизни»: золотой амулет на тонкой цепи с крупным "
        "рубиновым камнем в форме капли, вокруг тёплое красно-золотое свечение, символ жизненной силы.",
    ),
    (
        "revival_talisman",
        "Игровая иконка предмета «Талисман Возрождения»: изумрудный талисман-флакон с живой "
        "зелёной энергией и маленьким золотым листом, мягкое зелёное свечение, символ регенерации. "
        "Фон глубокий тёмно-синий, без белой студии и серого.",
    ),
    (
        "titan_shell",
        "Игровая иконка предмета «Панцирь Титана»: массивный каменный наплечник-панцирь из "
        "сине-серого камня с золотыми рунами, толстые пластины, символ несокрушимой защиты. "
        "Фон глубокий тёмно-синий, камень освещён золотыми рунами, без серой студии.",
    ),
    (
        "power_glove",
        "Игровая иконка предмета «Перчатка Силы»: тяжёлая боевая перчатка-гаунтлет из тёмной "
        "стали с золотыми пластинами и оранжевым свечением в кулаке, символ грубой силы. "
        "Без надписи и без букв, фон глубокий тёмно-синий.",
    ),
    (
        "vampire_fang",
        "Игровая иконка предмета «Клык Вампира»: окровавленный костяной клык-кинжал с багровым "
        "свечением и каплей крови, символ вампиризма. Фон глубокий тёмно-синий.",
    ),
    (
        "agility_mark",
        "Игровая иконка предмета «Знак Ловкости»: серебряный медальон-руна в виде молнии и "
        "птичьего пера, бирюзовое свечение, символ скорости и ловкости. Фон глубокий тёмно-синий, "
        "без белой студии.",
    ),
    (
        "wind_boots",
        "Игровая иконка предмета «Сапоги Ветра»: пара лёгких кожаных сапог с серебряными "
        "крылышками у пятки, вокруг зелёно-бирюзовые вихри ветра, символ скорости бега. "
        "Фон глубокий тёмно-синий, без белой студии.",
    ),
    (
        "hourglass",
        "Игровая иконка предмета «Песочные Часы»: золотые песочные часы с светящимся синим "
        "песком и парящими осколками времени, сине-фиолетовое свечение, символ ускорения навыков.",
    ),
    (
        "cleansing_charm",
        "Игровая иконка предмета «Оберег Очищения»: синий кристалл в серебряной оправе на "
        "короткой цепи, вокруг чистый бело-голубой свет, разгоняющий фиолетовую порчу, символ очищения.",
    ),
]


def generate_one(item_id: str, prompt: str, force: bool, model: str) -> Path | None:
    raw = RAW_DIR / f"{item_id}.jpg"
    if raw.exists() and not force:
        print(f"[skip] {item_id}: raw already exists")
        return raw
    cmd = [
        sys.executable,
        str(GENERATOR),
        prompt,
        "--style",
        STYLE,
        "--out",
        str(raw),
    ]
    if model:
        cmd.extend(["--model", model])
    print(f"[gen] {item_id} ...")
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", timeout=300)
    if result.returncode != 0:
        print(f"[fail] {item_id}: exit {result.returncode}")
        print(result.stdout[-1500:])
        print(result.stderr[-1500:])
        return None
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        print(f"[fail] {item_id}: bad json")
        print(result.stdout[-1500:])
        return None
    if not payload.get("ok"):
        print(f"[fail] {item_id}: {payload.get('error')}")
        return None
    print(f"[ok] {item_id}: {payload.get('path')}")
    return Path(payload["path"])


def square_crop(img: Image.Image) -> Image.Image:
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    return img.crop((left, top, left + side, top + side))


def darken_background(img: Image.Image) -> Image.Image:
    """Оставляет яркие/насыщенные пиксели предмета, фон уводит в тёмный синий."""
    arr = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    lum = arr[..., 0] * 0.2126 + arr[..., 1] * 0.7152 + arr[..., 2] * 0.0722
    sat = arr.max(axis=2) - arr.min(axis=2)
    keep = np.clip((np.maximum(lum, sat * 1.45) - 0.06) / 0.38, 0.0, 1.0) ** 0.85
    bg = np.array([0.018, 0.032, 0.062], dtype=np.float32)
    # Радиальная виньетка и подавление светлой студии по краям.
    h, w = keep.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = (w - 1) / 2.0, (h - 1) / 2.0
    r = np.sqrt(((xx - cx) / cx) ** 2 + ((yy - cy) / cy) ** 2) / 1.4142
    edge = np.clip((r - 0.24) / 0.45, 0.0, 1.0)
    keep *= 1.0 - 0.8 * edge * (sat < 0.13)
    white_bg = (lum > 0.82) & (sat < 0.10) & (edge > 0.18)
    keep[white_bg] = 0.0
    out = bg + (arr - bg) * keep[..., None]
    vignette = np.clip(1.0 - 0.55 * r ** 2, 0.45, 1.0)
    out *= vignette[..., None]
    border = np.clip((r - 0.40) / 0.30, 0.0, 1.0)
    out *= (1.0 - 0.85 * border)[..., None]
    return Image.fromarray(np.clip(out * 255.0, 0, 255).astype(np.uint8))


def process_one(item_id: str, raw: Path) -> Path:
    img = Image.open(raw).convert("RGB")
    img = square_crop(img)
    img = darken_background(img)
    img = img.resize((256, 256), Image.LANCZOS)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"{item_id}.webp"
    img.save(out, "WEBP", quality=90, method=6)
    print(f"[webp] {out} {out.stat().st_size} B")
    return out


def make_contact_sheet() -> None:
    if not OUT_DIR.exists():
        return
    thumbs = []
    for item_id, _ in ITEMS:
        p = OUT_DIR / f"{item_id}.webp"
        if p.exists():
            thumbs.append(Image.open(p).convert("RGB").resize((200, 200), Image.LANCZOS))
    if not thumbs:
        return
    cols = 3
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 210 + 10, rows * 210 + 10), (8, 14, 24))
    for index, thumb in enumerate(thumbs):
        x = 10 + (index % cols) * 210
        y = 10 + (index // cols) * 210
        sheet.paste(thumb, (x, y))
    CONTACT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(CONTACT, "JPEG", quality=92)
    print(f"[sheet] {CONTACT}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="", help="id одного предмета или список через запятую")
    parser.add_argument("--force", action="store_true", help="перегенерировать выбранные raw")
    parser.add_argument("--model", default="", help="модель GigaChat (по умолчанию из скрипта)")
    args = parser.parse_args()

    only_ids = {part.strip() for part in args.only.split(",") if part.strip()}
    selected = [item for item in ITEMS if not only_ids or item[0] in only_ids]
    if not selected:
        print(f"unknown item: {args.only}")
        return 1

    failed = []
    for item_id, prompt in selected:
        raw = generate_one(item_id, prompt, args.force, args.model)
        if raw is None or not raw.exists():
            failed.append(item_id)
            continue
        process_one(item_id, raw)
    make_contact_sheet()
    if failed:
        print("FAILED:", ", ".join(failed))
        return 1
    print("DONE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
