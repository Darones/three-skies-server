@echo off
rem Запускает локальный сервер и открывает просмотрщик анимаций.
cd /d C:\myGames3D\three-skies
start "three-skies-viewer" cmd /c python -m http.server 8000 --bind 127.0.0.1 --directory C:\myGames3D\three-skies
timeout /t 2 >nul
start http://127.0.0.1:8000/tools/viewer/index.html
