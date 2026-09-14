#!/usr/bin/env bash
# ==============================================================================
# WeChat IME Position Fix for Wayland / COSMIC Desktop
# (修复 Linux 原生微信在 Wayland / COSMIC 桌面下输入法候选框固定左上方不跟随光标的问题)
#
# 背景与原理：
# 1. Pop!_OS 24.04 (COSMIC Desktop) 默认环境变量中配置了 QT_QPA_PLATFORM=wayland;xcb，
#    导致官方 Linux 微信优先以原生 Wayland 客户端启动。
# 2. 微信内置基于旧版 fcitx-qt5 的输入法模块，在计算光标位置时调用了 mapToGlobal()。
# 3. 在 Wayland 协议的安全隔离限制下，客户端无法获取屏幕全局绝对坐标，mapToGlobal()
#    退化返回窗口内相对坐标 (如 +323+506)。
# 4. 微信将该相对坐标误作为屏幕绝对坐标通过 D-Bus 发送给 Fcitx5，导致候选框被钉死在
#    屏幕左上方固定像素位置，且拖拽微信窗口时候选框也完全不会跟随。
# 5. 本脚本通过在用户级启动配置中屏蔽 WAYLAND_DISPLAY 并强制 QT_QPA_PLATFORM=xcb，
#    使微信以纯 X11 (XWayland) 顶层窗口运行。在此模式下，mapToGlobal() 能正确通过
#    X11 XTranslateCoordinates 换算真实屏幕坐标，Fcitx5 候选框即可完美贴合打字光标。
# ==============================================================================

set -eo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DESKTOP_FILE="${HOME}/.local/share/applications/wechat.desktop"
WRAPPER_SCRIPT="${HOME}/.local/bin/wechat"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

uninstall() {
    log_info "正在恢复微信默认启动配置..."
    rm -f "${DESKTOP_FILE}" "${WRAPPER_SCRIPT}"
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
    fi
    log_success "已还原微信启动项配置为系统默认。"
    exit 0
}

if [[ "$1" == "--uninstall" || "$1" == "--restore" ]]; then
    uninstall
fi

log_info "开始配置 Linux 微信输入法光标跟随补丁..."

# 1. 确保目录存在
mkdir -p "${HOME}/.local/share/applications"
mkdir -p "${HOME}/.local/bin"

# 2. 写入用户级 wechat.desktop 启动项
cat > "${DESKTOP_FILE}" <<'EOF'
[Desktop Entry]
Name=wechat
Name[zh_CN]=微信
Exec=env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=xcb /opt/wechat/wechat %U
StartupNotify=true
Terminal=false
Icon=/usr/share/icons/hicolor/256x256/apps/wechat.png
Type=Application
Categories=Utility;
Comment=Wechat Desktop
Comment[zh_CN]=微信桌面版
EOF
log_success "已写入用户级桌面启动项：${DESKTOP_FILE}"

# 3. 写入命令行包装脚本 ~/.local/bin/wechat
cat > "${WRAPPER_SCRIPT}" <<'EOF'
#!/bin/sh
exec env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=xcb /opt/wechat/wechat "$@"
EOF
chmod +x "${WRAPPER_SCRIPT}"
log_success "已创建终端调用包装脚本：${WRAPPER_SCRIPT}"

# 4. 更新桌面数据库
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${HOME}/.local/share/applications" >/dev/null 2>&1 || true
fi

log_success "微信输入法光标跟随配置完成！"
echo ""
if pgrep -x wechat >/dev/null 2>&1; then
    log_warn "检测到微信当前正在运行。请彻底退出微信后重新打开，以使新配置生效！"
else
    log_info "现在可直接从 Dock / 应用菜单或终端启动微信使用。"
fi
