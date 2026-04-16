@echo off
set "APP_DIR=%~dp0"
if "%APP_DIR:~-1%"=="\" set "APP_DIR=%APP_DIR:~0,-1%"
set "PYTHON=%APP_DIR%\python\python.exe"

echo ============================================================
echo  Grok2API - 依赖安装脚本
echo ============================================================
echo.

if not exist "%PYTHON%" (
    echo [ERROR] 未找到内置 Python：%PYTHON%
    echo.
    echo [提示] 请按以下步骤操作：
    echo   1. 下载 Python 3.13 Windows embeddable 版：
    echo      https://www.python.org/downloads/windows/
    echo      选择 "Windows embeddable package (64-bit)"
    echo   2. 解压到本目录下的 python\ 文件夹
    echo   3. 重新运行本脚本
    echo.
    pause
    exit /b 1
)

echo [INFO] 检测 Python 版本...
"%PYTHON%" --version
echo.

REM 启用 site-packages（Python embeddable 默认不启用）
echo [INFO] 启用 site-packages...
for %%f in ("%APP_DIR%\python\python3*._pth") do (
    powershell -Command "(Get-Content '%%f') -replace '#import site', 'import site' | Set-Content '%%f'" 2>nul
)

REM 检查 pip 是否可用
echo [INFO] 检查 pip ...
"%PYTHON%" -m pip --version >nul 2>&1
if errorlevel 1 (
    echo [INFO] pip 未安装，正在引导安装...
    REM 先尝试 ensurepip
    "%PYTHON%" -m ensurepip --upgrade >nul 2>&1
    if errorlevel 1 (
        echo [INFO] ensurepip 不可用，正在下载 get-pip.py ...
        powershell -Command "Invoke-WebRequest -Uri 'https://bootstrap.pypa.io/get-pip.py' -OutFile '%APP_DIR%\get-pip.py'" 2>nul
        if not exist "%APP_DIR%\get-pip.py" (
            echo [ERROR] 下载 get-pip.py 失败，请检查网络连接。
            pause
            exit /b 1
        )
        "%PYTHON%" "%APP_DIR%\get-pip.py" --no-warn-script-location
        del "%APP_DIR%\get-pip.py" 2>nul
    )
    "%PYTHON%" -m pip --version >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] pip 安装失败，请手动安装 pip 后重试。
        pause
        exit /b 1
    )
)
echo [INFO] pip 可用。
echo.

REM 升级 pip 本身
echo [INFO] 升级 pip ...
"%PYTHON%" -m pip install --upgrade pip --no-warn-script-location -q
echo.

REM 安装项目依赖
echo [INFO] 安装项目依赖（requirements.txt）...
"%PYTHON%" -m pip install -r "%APP_DIR%\requirements.txt" --no-warn-script-location
if errorlevel 1 (
    echo.
    echo [ERROR] 依赖安装失败，请检查网络连接或 requirements.txt。
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  [SUCCESS] 依赖安装完成！
echo  现在可以运行 启动.bat 来启动 Grok2API。
echo ============================================================
echo.
pause
