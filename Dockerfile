# ============================================================
# Sky Shards — Dockerfile for RelaxDev deployment
# ============================================================
# Сборка:  docker build -t sky-shards-server .
# Запуск:  docker run -p 9080:9080 --rm sky-shards-server
# ============================================================

FROM ubuntu:22.04

LABEL maintainer="sky-shards-team"
LABEL description="Sky Shards Matchmaking Server"

# Системные зависимости
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    unzip \
    ca-certificates \
    libgl1-mesa-glx \
    libegl1 \
    libopenal1 \
    libogg0 \
    libvorbis0a \
    libpulse0 \
    libfontconfig1 \
    fontconfig \
    && rm -rf /var/lib/apt/lists/*

# Переменные — поменяй VERSION если нужна другая версия Godot
ARG GODOT_VERSION=4.7.2
ARG GODOT_ARCH=x86_64

# Скачиваем Godot Headless (консольная версия без рендеринга)
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${GODOT_ARCH}.zip" \
    -O /tmp/godot.zip \
    && mkdir -p /opt/godot \
    && unzip -q /tmp/godot.zip -d /opt/godot \
    && rm /tmp/godot.zip \
    && chmod +x /opt/godot/Godot_*

# Рабочая директория проекта
WORKDIR /app

# Копируем весь проект
COPY . /app/

# Отладка: показываем файлы при сборке
RUN echo "--- ФАЙЛЫ В /app ---" && ls -la /app
RUN echo "--- ФАЙЛЫ В /app/server ---" && ls -la /app/server

# Запускаем сервер в headless режиме
# --headless — без рендеринга, только логика
# --display-driver headless — явный headless-драйвер (без X11/Wayland)
# --audio-driver Dummy — без аудио-зависимостей
# --path — корень проекта
CMD ["/opt/godot/Godot_v4.7.2-stable_linux.x86_64", "--headless", "--display-driver", "headless", "--audio-driver", "Dummy", "--path", "/app", "res://server/server_main.tscn"]
