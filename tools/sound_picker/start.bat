@echo off
setlocal
set "PORT=%~1"
if "%PORT%"=="" set "PORT=8090"
cd /d "%~dp0"

where python >nul 2>nul
if not errorlevel 1 (
	set "PY=python"
) else (
	where py >nul 2>nul
	if errorlevel 1 (
		echo Python 3 not found.
		echo Install Python 3 or run: npx serve -l %PORT%
		pause
		exit /b 1
	)
	set "PY=py -3"
)

echo Sound Picker: http://localhost:%PORT%/
start "Sound Picker Server" cmd /k %PY% -m http.server %PORT%
timeout /t 1 /nobreak >nul
start "" "http://localhost:%PORT%/"
endlocal
