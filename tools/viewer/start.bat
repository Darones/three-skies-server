@echo off
rem Запускает локальный сервер тюнера и открывает страницу.
cd /d C:\myGames3D\three-skies
start "three-skies-viewer" cmd /c python "C:\myGames3D\three-skies\tools\viewer\server.py"
timeout /t 2 >nul
start http://127.0.0.1:8000/tools/viewer/index.html
