@echo off
set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"
set "PYTHON=%APP_DIR%\python\python.exe"
if not exist "%PYTHON%" (
    echo [ERROR] Python not found at %PYTHON%
    echo [INFO]  Please run 安装依赖.bat first to set up the Python environment.
    pause
    exit /b 1
)
echo [INFO] Grok2API starting on http://localhost:8000 ...
start "" "http://localhost:8000"
cd /d "%APP_DIR%"
"%PYTHON%" -m granian --interface asgi --host 0.0.0.0 --port 8000 --workers 1 --log-level info app.main:app
pause
