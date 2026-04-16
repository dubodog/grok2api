#!/bin/bash
# ============================================================
# build_windows_package.sh
#
# 在 macOS / Linux 上构建 Windows 可独立部署包。
# 运行后生成 python/ 目录，包含 Python 3.13 运行时和全部依赖。
# 将整个项目目录拷贝到 Windows，双击 启动.bat 即可启动，无需安装任何依赖。
#
# 用法：
#   bash build_windows_package.sh
#
# 依赖（本机需要）：
#   - Python 3.x（pip 可用即可）
#   - unzip
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 配置 ─────────────────────────────────────────────────────
# 如需更换版本，从 https://www.python.org/downloads/windows/ 查找对应版本号
PYTHON_VERSION="3.13.3"
PYTHON_ZIP="python-${PYTHON_VERSION}-embed-amd64.zip"
PYTHON_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/${PYTHON_ZIP}"

PYTHON_DIR="${SCRIPT_DIR}/python"
WHEELS_DIR="/tmp/grok2api_wheels_$$"
REQUIREMENTS="${SCRIPT_DIR}/requirements.txt"
# ─────────────────────────────────────────────────────────────

echo "============================================================"
echo " Grok2API - Windows 离线部署包构建脚本"
echo " Python 版本：${PYTHON_VERSION}"
echo "============================================================"
echo ""

# ── 选取可用的本机 Python（需要 SSL 正常） ──────────────────────
# 优先用 uv 管理的或 Homebrew 的新版本，避开 pyenv 旧版 openssl 问题
find_python() {
    for candidate in \
        "/usr/local/bin/python3.13" \
        "/usr/local/bin/python3.12" \
        "/usr/local/bin/python3.11" \
        "/opt/homebrew/bin/python3.13" \
        "/opt/homebrew/bin/python3.12" \
        "/opt/homebrew/bin/python3.11" \
        "$(uv python find 2>/dev/null)" \
        "python3" \
        "python"; do
        [ -z "$candidate" ] && continue
        if "$candidate" -c "import ssl, urllib.request" 2>/dev/null; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

HOST_PYTHON=$(find_python) || {
    echo "[ERROR] 未找到带 SSL 支持的 Python，请确认本机已安装 Python 3.x（Homebrew / uv 均可）。"
    exit 1
}
echo "[INFO] 使用本机 Python：${HOST_PYTHON} ($(${HOST_PYTHON} --version 2>&1))"

HOST_PIP="${HOST_PYTHON} -m pip"

if ! $HOST_PIP --version &>/dev/null; then
    echo "[ERROR] pip 不可用，请运行：${HOST_PYTHON} -m ensurepip"
    exit 1
fi

if ! command -v unzip &>/dev/null; then
    echo "[ERROR] 需要 unzip，请先安装（macOS: brew install unzip）"
    exit 1
fi

if [ ! -f "$REQUIREMENTS" ]; then
    echo "[ERROR] 未找到 requirements.txt：$REQUIREMENTS"
    exit 1
fi

# ── Step 1: 下载 Python embeddable ───────────────────────────
echo ""
echo "[1/4] 下载 Python ${PYTHON_VERSION} Windows embeddable..."
if [ -d "${PYTHON_DIR}" ]; then
    echo "      已存在 python/ 目录，先清除..."
    rm -rf "${PYTHON_DIR}"
fi
mkdir -p "${PYTHON_DIR}"

TMP_ZIP="/tmp/${PYTHON_ZIP}"
# 用 Python urllib 下载；VPN/代理环境下 SSL 握手常被中断，
# 先尝试正常 SSL，失败后自动回退到宽松 SSL（忽略证书校验）。
"${HOST_PYTHON}" - <<PYEOF
import urllib.request, ssl, sys

url  = "${PYTHON_URL}"
dest = "${TMP_ZIP}"

def download(url, dest, ctx=None):
    req = urllib.request.Request(url, headers={"User-Agent": "Python-urllib/3"})
    open_kwargs = {"context": ctx} if ctx else {}
    with urllib.request.urlopen(req, **open_kwargs) as resp:
        total = int(resp.headers.get("Content-Length", 0))
        done  = 0
        with open(dest, "wb") as f:
            while True:
                chunk = resp.read(1 << 16)   # 64 KB
                if not chunk:
                    break
                f.write(chunk)
                done += len(chunk)
                if total:
                    pct = min(100, done * 100 // total)
                    sys.stdout.write(f"\r      {pct:3d}%  {done/1048576:.1f} MB")
                    sys.stdout.flush()
    print()

print(f"      下载中：{url}")
# ── 尝试 1：正常 SSL ──────────────────────────────────────────
try:
    download(url, dest)
except Exception as e1:
    print(f"\n      [WARN] 正常 SSL 失败（{type(e1).__name__}: {e1}）")
    print(      "      [INFO] VPN/代理环境，切换为宽松 SSL 模式重试...")
    # ── 尝试 2：宽松 SSL（跳过证书校验，适合代理/VPN 拦截场景） ──
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode    = ssl.CERT_NONE
    try:
        download(url, dest, ctx)
    except Exception as e2:
        print(f"\n      [ERROR] 下载失败：{e2}")
        print(          "      请检查网络，或手动下载后放至 /tmp/${PYTHON_ZIP}")
        sys.exit(1)
PYEOF

echo "      解压中..."
unzip -q "${TMP_ZIP}" -d "${PYTHON_DIR}"
rm -f "${TMP_ZIP}"
echo "      Python ${PYTHON_VERSION} 解压完成。"

# ── Step 2: 配置 ._pth（启用 site-packages + 项目根目录） ────
echo ""
echo "[2/4] 配置 sys.path..."
PTH_FILE=$(ls "${PYTHON_DIR}"/python3*._pth 2>/dev/null | head -1)
if [ -z "$PTH_FILE" ]; then
    echo "[ERROR] 未找到 ._pth 文件，Python 包结构异常。"
    exit 1
fi

# 覆写 ._pth 文件：
#   python313.zip  - 标准库（压缩包）
#   .              - python/ 目录本身
#   ..             - 项目根目录（app.main 等模块可直接 import）
#   import site    - 启用 site-packages
PTH_BASENAME=$(basename "$PTH_FILE" ._pth)
cat > "$PTH_FILE" <<PTH_EOF
${PTH_BASENAME}.zip
.
..
import site
PTH_EOF

mkdir -p "${PYTHON_DIR}/Lib/site-packages"
echo "      sys.path 配置完成。"

# ── Step 3: 跨平台下载 Windows wheels ────────────────────────
echo ""
echo "[3/4] 下载 Windows 依赖包（win_amd64 / cp313）..."
echo "      （使用本机 pip 跨平台下载，不影响本机环境）"
mkdir -p "${WHEELS_DIR}"

# 注意：pip 在非 Windows 宿主机上跨平台下载时，不会自动解析
# "sys_platform == 'win32'" 这类条件依赖（如 loguru 依赖的 win32-setctime）。
# 解决方案：将所有 Windows 专属包直接写入 requirements.txt，绕过条件判断。
# 在项目目录外运行，避开 .python-version 的 pyenv 干扰
(cd /tmp && $HOST_PIP download \
    --platform win_amd64 \
    --implementation cp \
    --python-version 3.13 \
    --only-binary :all: \
    -r "${REQUIREMENTS}" \
    -d "${WHEELS_DIR}")

WHEEL_COUNT=$(ls "${WHEELS_DIR}"/*.whl 2>/dev/null | wc -l | tr -d ' ')
echo "      下载完成，共 ${WHEEL_COUNT} 个 wheel 文件（含传递依赖）。"

# ── Step 4: 解压 wheels 到 site-packages ─────────────────────
echo ""
echo "[4/4] 安装依赖包到 python/Lib/site-packages/ ..."
for wheel in "${WHEELS_DIR}"/*.whl; do
    pkg_name=$(basename "$wheel" | cut -d- -f1)
    echo "      [+] ${pkg_name}"
    unzip -o -q "$wheel" -d "${PYTHON_DIR}/Lib/site-packages/"
done

# 清理临时 wheel 文件
rm -rf "${WHEELS_DIR}"

PYTHON_SIZE=$(du -sh "${PYTHON_DIR}" | cut -f1)

echo ""
echo "============================================================"
echo " [SUCCESS] 构建完成！"
echo ""
echo " python/ 目录大小：${PYTHON_SIZE}"
echo " 包含 ${WHEEL_COUNT} 个依赖包（含传递依赖）"
echo ""
echo " 部署步骤："
echo "   1. 将整个 grok2api/ 目录复制到 Windows 机器"
echo "   2. 双击 启动.bat"
echo "   无需安装 Python，无需联网，开箱即用。"
echo "============================================================"
