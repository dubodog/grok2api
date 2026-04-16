@echo off
chcp 65001 >nul
set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"
set "PYTHON=%APP_DIR%\python\python.exe"

if not exist "%PYTHON%" (
    echo [ERROR] Python not found at %PYTHON%
    pause & exit /b 1
)

echo [INFO] Fixing missing Windows-specific packages...
echo [INFO] This requires a one-time internet connection.
echo.

set "TMPSCRIPT=%TEMP%\grok2api_fix_deps.py"

:: Write the fix script to a temp file
(
echo import urllib.request, zipfile, os, json, pathlib, sys
echo.
echo SITE_PACKAGES = pathlib.Path(r"%APP_DIR%\python\Lib\site-packages"^)
echo SITE_PACKAGES.mkdir(parents=True, exist_ok=True^)
echo.
echo MISSING = ["win32-setctime"]
echo.
echo for pkg in MISSING:
echo     print(f"[INFO] Installing {pkg} from PyPI..."^)
echo     try:
echo         url = f"https://pypi.org/pypi/{pkg}/json"
echo         with urllib.request.urlopen(url, timeout=30^) as r:
echo             data = json.loads(r.read(^)^)
echo         latest = data["info"]["version"]
echo         wheel_info = next(
echo             (f for f in data["releases"][latest]
echo              if "none-any" in f["filename"] or f["packagetype"] == "bdist_wheel"^),
echo             None
echo         ^)
echo         if not wheel_info:
echo             print(f"[ERROR] No wheel found for {pkg}"^)
echo             continue
echo         fname = wheel_info["filename"]
echo         dl_url = wheel_info["url"]
echo         print(f"[INFO] Downloading {fname}..."^)
echo         tmp = pathlib.Path(os.environ.get("TEMP", "."^)^) / fname
echo         urllib.request.urlretrieve(dl_url, tmp^)
echo         with zipfile.ZipFile(tmp^) as z:
echo             z.extractall(SITE_PACKAGES^)
echo         tmp.unlink(^)
echo         print(f"[OK]   {pkg} installed successfully."^)
echo     except Exception as e:
echo         print(f"[ERROR] Failed to install {pkg}: {e}"^)
echo         sys.exit(1^)
echo.
echo print(^)
echo print("[SUCCESS] All missing packages installed!"^)
echo print("[INFO]    Please run 启动.bat to start Grok2API."^)
) > "%TMPSCRIPT%"

"%PYTHON%" "%TMPSCRIPT%"
if errorlevel 1 (
    del "%TMPSCRIPT%" 2>nul
    echo.
    echo [ERROR] Fix failed. Please check network and retry.
    pause & exit /b 1
)

del "%TMPSCRIPT%" 2>nul
echo.
pause
