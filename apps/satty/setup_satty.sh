#!/usr/bin/env bash
# ==============================================================================
# Satty Screenshot & Annotation Tool for Pop!_OS 24.04 (COSMIC Desktop / Wayland)
# (Pop!_OS 24.04 COSMIC 原生 Wayland 高性能区域截图、标注与快捷键一键部署方案)
#
# 背景与痛点：
# 1. Pop!_OS 24.04 默认搭载基于 Rust/Smithay 构建的全新 COSMIC 桌面环境 (cosmic-comp)，
#    传统的截图工具（如 Flameshot、ksnip）在原生 Wayland 环境下存在各种兼容性与体验问题。
# 2. 社区常用的 Wayland 原生截图方案为 grim + slurp + satty，但在 COSMIC 桌面下存在三大坑点：
#    - 【协议不匹配】：Pop!_OS 官方源自带的 grim 为 1.4.0 版本，仅支持旧版 wlr-screencopy 协议，
#      而 cosmic-comp 仅实现了更新的 ext-image-copy-capture-v1 标准，导致报错
#      "compositor doesn't support wlr-screencopy-unstable-v1" 无法截图。
#    - 【后台非 TTY 管道挂起】：当通过系统全局快捷键唤起脚本时，标准输入 (stdin) 为非 TTY 管道。
#      slurp 默认认为有外界预设选区矩形传入，进而卡死在 read() 等待 EOF，屏幕无任何反应。
#    - 【子进程缺失显示环境变量】：cosmic-comp 直接 Spawn 启动的快捷键子进程未继承
#      WAYLAND_DISPLAY 环境变量，Wayland 客户端默认尝试连接不存在的 wayland-0 导致启动失败。
#
# 解决方案：
# 1. 自动检测并升级 grim 至 >= 1.5.0 版本（支持 ext-image-copy-capture-v1）。
# 2. 部署与 GLIBC 2.39 完美匹配的 Satty 现代标注工具（支持画笔、箭头、文字、矩形、马赛克高斯模糊等）。
# 3. 部署 satty-screenshot 智能包装器，自动探测活动 Wayland 套接字、隔离 stdin (/dev/null)
#    彻底杜绝挂起，并提供防重入保护与全屏模式支持。
# 4. 优化中文字体配置（Noto Sans CJK SC），支持 Enter / Ctrl+C 复制即退、Esc 取消。
# 5. 自动无缝写入 COSMIC 自定义快捷键绑定 (Super+Shift+S 及 Ctrl+Alt+A)。
# ==============================================================================

set -eo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SATTY_VERSION="v0.20.1"
SATTY_TARBALL="satty-x86_64-unknown-linux-gnu.tar.gz"
SATTY_URL="https://github.com/Satty-org/Satty/releases/download/${SATTY_VERSION}/${SATTY_TARBALL}"
DEBIAN_GRIM_DEB_URL="http://ftp.debian.org/debian/pool/main/g/grim/grim_1.5.0+ds-1_amd64.deb"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

require_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        else
            log_error "本操作需要管理员权限，请安装 sudo 或以 root 身份运行。"
            exit 1
        fi
    else
        SUDO=""
    fi
}

uninstall() {
    log_info "正在卸载 Satty 截图与相关配置..."
    require_sudo

    $SUDO rm -f /usr/bin/satty-screenshot /usr/local/bin/satty-screenshot /usr/local/bin/satty
    rm -f "${HOME}/.local/bin/satty-screenshot" "${HOME}/.local/bin/satty"
    rm -f "${HOME}/.local/share/applications/satty.desktop" "${HOME}/.local/share/applications/satty-screenshot.desktop"
    rm -f "${HOME}/.local/share/icons/hicolor/scalable/apps/satty.svg"

    log_warn "若需恢复旧版 grim，可执行: sudo apt-get --reinstall install -y grim"
    log_success "Satty 脚本与可执行文件已移除。"
    exit 0
}

if [[ "$1" == "--uninstall" || "$1" == "--restore" ]]; then
    uninstall
fi

log_info "=== 开始安装配置 Satty 截图与标注工具 (COSMIC Wayland 专版) ==="
require_sudo

# 1. 安装基础依赖组件 (slurp, wl-clipboard)
log_info "正在检查并安装依赖工具 (slurp, wl-clipboard)..."
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq slurp wl-clipboard

# 2. 检查并确保 grim 支持 ext-image-copy-capture-v1 (>= 1.5.0)
log_info "检查 grim 版本与 COSMIC 协议兼容性..."
NEED_GRIM_UPDATE=false
if ! command -v grim >/dev/null 2>&1; then
    NEED_GRIM_UPDATE=true
else
    # 检查是否包含 ext_image_copy_capture 协议支持
    if ! strings "$(command -v grim)" 2>/dev/null | grep -q "ext_image_copy_capture"; then
        NEED_GRIM_UPDATE=true
    fi
fi

if [ "$NEED_GRIM_UPDATE" = true ]; then
    log_warn "检测到系统自带 grim 版本过旧（不支持 COSMIC 的 ext-image-copy-capture 协议），正在升级至 1.5.0..."
    TMP_DIR=$(mktemp -d)
    curl -sL "${DEBIAN_GRIM_DEB_URL}" -o "${TMP_DIR}/grim.deb" || {
        log_error "下载 grim 1.5.0 安装包失败，请检查网络连接。"
        rm -rf "${TMP_DIR}"
        exit 1
    }
    dpkg-deb -x "${TMP_DIR}/grim.deb" "${TMP_DIR}/extracted"
    $SUDO cp "${TMP_DIR}/extracted/usr/bin/grim" /usr/bin/grim
    $SUDO cp "${TMP_DIR}/extracted/usr/bin/grim" /usr/local/bin/grim
    $SUDO chmod 755 /usr/bin/grim /usr/local/bin/grim
    if [ -f "${TMP_DIR}/extracted/usr/share/man/man1/grim.1.gz" ]; then
        $SUDO cp "${TMP_DIR}/extracted/usr/share/man/man1/grim.1.gz" /usr/share/man/man1/grim.1.gz || true
    fi
    rm -rf "${TMP_DIR}"
    log_success "grim 1.5.0 已成功安装并部署。"
else
    log_success "grim 已支持 ext-image-copy-capture 协议，无需更新。"
fi

# 3. 安装 Satty 二进制文件
log_info "检查 Satty 主程序..."
NEED_SATTY_INSTALL=false
if ! command -v satty >/dev/null 2>&1; then
    NEED_SATTY_INSTALL=true
else
    # 验证当前可执行文件是否能正常运行
    if ! satty --version >/dev/null 2>&1; then
        NEED_SATTY_INSTALL=true
    fi
fi

if [ "$NEED_SATTY_INSTALL" = true ]; then
    log_info "正在下载并部署 Satty (${SATTY_VERSION})..."
    TMP_DIR=$(mktemp -d)
    curl -sL "${SATTY_URL}" -o "${TMP_DIR}/${SATTY_TARBALL}" || {
        log_error "下载 Satty 失败，请检查网络连接。"
        rm -rf "${TMP_DIR}"
        exit 1
    }
    mkdir -p "${TMP_DIR}/extracted"
    tar -xzf "${TMP_DIR}/${SATTY_TARBALL}" --no-same-owner -C "${TMP_DIR}/extracted"
    
    $SUDO cp "${TMP_DIR}/extracted/satty" /usr/local/bin/satty
    $SUDO chmod 755 /usr/local/bin/satty
    mkdir -p "${HOME}/.local/bin"
    cp "${TMP_DIR}/extracted/satty" "${HOME}/.local/bin/satty"
    chmod +x "${HOME}/.local/bin/satty"

    if [ -f "${TMP_DIR}/extracted/assets/satty.svg" ]; then
        $SUDO cp "${TMP_DIR}/extracted/assets/satty.svg" /usr/share/icons/hicolor/scalable/apps/satty.svg 2>/dev/null || true
        mkdir -p "${HOME}/.local/share/icons/hicolor/scalable/apps"
        cp "${TMP_DIR}/extracted/assets/satty.svg" "${HOME}/.local/share/icons/hicolor/scalable/apps/satty.svg"
    fi

    if [ -f "${TMP_DIR}/extracted/satty.desktop" ]; then
        $SUDO cp "${TMP_DIR}/extracted/satty.desktop" /usr/share/applications/satty.desktop 2>/dev/null || true
        mkdir -p "${HOME}/.local/share/applications"
        cp "${TMP_DIR}/extracted/satty.desktop" "${HOME}/.local/share/applications/satty.desktop"
    fi
    rm -rf "${TMP_DIR}"
    log_success "Satty 主程序部署完成。"
else
    log_success "Satty 已就绪 ($(satty --version 2>&1 | head -n 1))。"
fi

# 4. 安装 satty-screenshot 启动脚本
log_info "正在配置 satty-screenshot 包装脚本..."
mkdir -p "${HOME}/.local/bin"
cp "${SCRIPT_DIR}/satty-screenshot" "${HOME}/.local/bin/satty-screenshot"
chmod +x "${HOME}/.local/bin/satty-screenshot"
$SUDO cp "${SCRIPT_DIR}/satty-screenshot" /usr/bin/satty-screenshot
$SUDO cp "${SCRIPT_DIR}/satty-screenshot" /usr/local/bin/satty-screenshot
$SUDO chmod 755 /usr/bin/satty-screenshot /usr/local/bin/satty-screenshot
log_success "已安装 /usr/bin/satty-screenshot 及 ~/.local/bin/satty-screenshot。"

# 5. 配置 Satty 用户首选项 (config.toml)
log_info "配置 Satty 首选项 (~/.config/satty/config.toml)..."
mkdir -p "${HOME}/.config/satty" "${HOME}/Pictures/Screenshots"
if [ -f "${SCRIPT_DIR}/config.toml" ]; then
    cp "${SCRIPT_DIR}/config.toml" "${HOME}/.config/satty/config.toml"
    log_success "已应用优化配置：中文字体回退、Enter/Ctrl+C 复制即退、保存至 ~/Pictures/Screenshots/。"
fi

# 6. 配置桌面菜单快捷图标
mkdir -p "${HOME}/.local/share/applications"
cat << 'DESKTOP_EOF' > "${HOME}/.local/share/applications/satty-screenshot.desktop"
[Desktop Entry]
Name=Satty 截图
Comment=Wayland 区域截图与标注工具
Exec=/usr/bin/satty-screenshot
Terminal=false
Type=Application
Icon=satty
Categories=Utility;Graphics;
StartupNotify=false
DESKTOP_EOF

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
fi

# 7. 配置 COSMIC 快捷键
COSMIC_CUSTOM_SHORTCUTS="${HOME}/.config/cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom"
log_info "检查 COSMIC 自定义快捷键配置..."
mkdir -p "$(dirname "${COSMIC_CUSTOM_SHORTCUTS}")"

python3 -c "
import os

path = '$COSMIC_CUSTOM_SHORTCUTS'
content = ''
if os.path.exists(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

needs_super = 'Super' not in content or 'Shift' not in content or '\"s\"' not in content or 'satty' not in content
needs_ctrl = 'Ctrl' not in content or 'Alt' not in content or '\"a\"' not in content or 'satty' not in content

if not os.path.exists(path) or not content.strip().startswith('{'):
    new_content = '''{
    (
        modifiers: [
            Super,
            Shift,
        ],
        key: \"s\",
    ): Spawn(\"/usr/bin/satty-screenshot\"),
    (
        modifiers: [
            Ctrl,
            Alt,
        ],
        key: \"a\",
    ): Spawn(\"/usr/bin/satty-screenshot\"),
}
'''
    with open(path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print('已自动创建 COSMIC 自定义快捷键配置。')
elif needs_super or needs_ctrl:
    insert_pos = content.rfind('}')
    if insert_pos != -1:
        additions = '''    (
        modifiers: [
            Super,
            Shift,
        ],
        key: \"s\",
    ): Spawn(\"/usr/bin/satty-screenshot\"),
    (
        modifiers: [
            Ctrl,
            Alt,
        ],
        key: \"a\",
    ): Spawn(\"/usr/bin/satty-screenshot\"),
'''
        new_content = content[:insert_pos] + additions + content[insert_pos:]
        with open(path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print('已向现有 COSMIC 快捷键中注入 satty 截图快捷键。')
else:
    print('COSMIC 快捷键中已配置 satty-screenshot。')
"

log_success "=== Satty 截图与标注工具部署完成！==="
echo ""
echo -e "${GREEN}快捷键使用说明：${NC}"
echo -e "  - 区域截图快捷键：${YELLOW}Super + Shift + S${NC} 或 ${YELLOW}Ctrl + Alt + A${NC}"
echo -e "  - 全屏截图命令：  ${YELLOW}/usr/bin/satty-screenshot --full${NC}"
echo -e "  - 常用标注操作："
echo -e "    * 鼠标左键拖拽选区"
echo -e "    * 按 Enter 或 Ctrl + C 复制并退出"
echo -e "    * 按 Ctrl + S 保存至 ~/Pictures/Screenshots/"
echo -e "    * 按 Esc 取消退出"
echo -e "    * 工具快捷键：r (矩形) / z (箭头) / t (文字) / u (马赛克模糊)"
