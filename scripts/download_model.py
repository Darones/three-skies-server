#!/usr/bin/env python3
"""
Скачивание готовой 3D-модели через GigaChat API.
Принимает file_id как аргумент и сохраняет FBX в assets/models/.
"""

import sys
import os
import uuid
import requests

# ============================================================
#  ВСТАВЬ_КЛЮЧ_СЮДА  — замени на свой ключ GigaChat
# ============================================================
CREDENTIALS = "MDFhMGM0OGItYzlhNC03ODExLWE0M2MtN2JlOGFjMzhmMzhlOmMxYjk1YjhhLTQ0NTAtNDY4OS04MTIwLWM5Mzk2ZjBmMzk3MA=="
CERT_PATH = r"C:\myGames3D\three-skies\certs\Russian_Trusted_Root_CA.cer"

GIGACHAT_BASE = "https://api.giga.chat/v1"
GIGACHAT_FILES = f"{GIGACHAT_BASE}/files"

# OAuth-эндпоинт Сбера для получения токена
GIGACHAT_AUTH = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth"

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR  = os.path.join(PROJECT_DIR, "assets", "models")


def get_access_token() -> str:
    """Получаем JWT-токен через OAuth Сбера."""
    resp = requests.post(
        GIGACHAT_AUTH,
        headers={
            "Authorization": f"Bearer {CREDENTIALS}",
            "RqUID": str(uuid.uuid4()),
            "Content-Type": "application/x-www-form-urlencoded",
        },
        data={"scope": "GIGACHAT_API_PERS"},
        verify=CERT_PATH,
    )
    resp.raise_for_status()
    data = resp.json()
    return data["access_token"]


def download_model(file_id: str, token: str, filename: str = None) -> str:
    """Скачиваем FBX-файл модели через /files/{file_id}/content."""
    url = f"{GIGACHAT_FILES}/{file_id}/content"
    resp = requests.get(url, headers={"Authorization": f"Bearer {token}"}, verify=CERT_PATH)
    resp.raise_for_status()

    if filename is None:
        filename = f"{file_id}.fbx"

    os.makedirs(MODELS_DIR, exist_ok=True)
    filepath = os.path.join(MODELS_DIR, filename)
    with open(filepath, "wb") as f:
        f.write(resp.content)

    return filepath


# ============================================================
#  MAIN
# ============================================================
def main():
    if len(sys.argv) < 2:
        print("Использование:")
        print("  python download_model.py <file_id> [имя_файла.fbx]")
        sys.exit(1)

    file_id = sys.argv[1]
    filename = sys.argv[2] if len(sys.argv) > 2 else None

    print(f"ID модели: {file_id}")
    print("Получение токена…")
    token = get_access_token()
    print("Токен получен.")

    print("Скачивание модели…")
    filepath = download_model(file_id, token, filename)
    print(f"Готово!  {filepath}")


if __name__ == "__main__":
    main()
