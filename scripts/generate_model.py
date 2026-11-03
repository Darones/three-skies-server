#!/usr/bin/env python3
"""
Генерация 3D-модели через GigaChat API (text2model3d).
Принимает текстовый запрос и сохраняет результат в assets/models/.

Использует официальный Python SDK gigachat.
Установка: pip install gigachat
"""

import sys
import os
import json

# ============================================================
#  ВСТАВЬ_КЛЮЧ_СЮДА  — замени на свой ключ GigaChat
# ============================================================
CREDENTIALS = "MDFhMGM0OGItYzlhNC03ODExLWE0M2MtN2JlOGFjMzhmMzhlOmMxYjk1YjhhLTQ0NTAtNDY4OS04MTIwLWM5Mzk2ZjBmMzk3MA=="

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELS_DIR  = os.path.join(PROJECT_DIR, "assets", "models")


def generate_model(prompt: str) -> dict:
    """Запускаем генерацию 3D-модели через text2model3d. Возвращаем ответ."""
    from gigachat import GigaChat
    from gigachat.models import Chat, Messages, MessagesRole, Function

    with GigaChat(
        credentials=CREDENTIALS,
        verify_ssl_certs=False,
        base_url="https://api.giga.chat/v1",
    ) as chat:
        chat_payload = Chat(
            model="GigaChat-3-Ultra",
            messages=[Messages(role=MessagesRole.USER, content=prompt)],
            function_call="auto",
            functions=[Function(name="text2model3d")],
        )
        response = chat.chat(chat_payload)
        return response


def extract_file_id(response) -> str:
    """Извлекаем file_id из ответа API."""
    choices = response.choices if hasattr(response, "choices") else []
    if not choices:
        # Попытка преобразовать в dict
        try:
            resp_dict = response.model_dump()
        except Exception:
            resp_dict = response.dict()
        choices = resp_dict.get("choices", [])

    if not choices:
        raise ValueError(f"Нет choices в ответе: {response}")

    message = choices[0].get("message", {})
    func_call = message.get("function_call", {})
    arguments = func_call.get("arguments", "")

    try:
        data = json.loads(arguments)
        file_id = data.get("file_id") or data.get("model_id") or data.get("id")
        if file_id:
            return file_id
    except (json.JSONDecodeError, AttributeError):
        pass

    text = message.get("content", "")
    if "data-model-id" in text:
        start = text.find("data-model-id=") + len('data-model-id="')
        end = text.find('"', start)
        if end > start:
            return text[start:end]

    raise ValueError(f"Не удалось извлечь file_id: {arguments[:300]}")


def download_file(file_id: str, filename: str) -> str:
    """Скачиваем файл модели через /files/{file_id}/content."""
    from gigachat import GigaChat

    with GigaChat(
        credentials=CREDENTIALS,
        verify_ssl_certs=False,
        base_url="https://api.giga.chat/v1",
    ) as chat:
        # SDK не имеет прямого метода для скачивания файлов,
        # используем requests для этого
        import requests
        url = f"https://api.giga.chat/v1/files/{file_id}/content"
        # Получаем токен через SDK
        token = chat.authorize()
        resp = requests.get(url, headers={"Authorization": f"Bearer {token}"})
        resp.raise_for_status()

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
        print("  python generate_model.py \"описание модели\" [имя_файла.fbx]")
        sys.exit(1)

    prompt = sys.argv[1]
    filename = sys.argv[2] if len(sys.argv) > 2 else "generated_model.fbx"

    print(f"Запрос: {prompt}")
    print("Отправка запроса на генерацию…")
    response = generate_model(prompt)
    print("Запрос отправлен, извлекаем file_id…")
    file_id = extract_file_id(response)
    print(f"file_id: {file_id}")

    print("Скачивание модели…")
    filepath = download_file(file_id, filename)
    print(f"Готово!  {filepath}")


if __name__ == "__main__":
    main()
