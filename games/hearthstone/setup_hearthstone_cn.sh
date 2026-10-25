#!/usr/bin/env bash
# ==============================================================================
# 国服炉石传说一键准备脚本 (Pop!_OS / Ubuntu + Lutris)
#
# 功能特性：
# 1. 检查 Lutris 是否安装，缺失时给出安装提示
# 2. 自动下载并部署 wine-tkg-ntsync-10.13-wow64 运行器（来自 winegame.net 国内镜像）
#    纯64位 wow64 模式，不需要 32 位库；带 NTsync（内核 >= 6.14 且有 /dev/ntsync 时自动启用）
# 3. 预下载 Wine Gecko / Mono 运行库与中文字体（走 winegame 国内镜像，Mono 镜像缺失时回退官方源）
# 4. 调起 Lutris 图形安装向导完成国服战网安装（需要用户在界面中点击）
#
# 用法：
#   ./setup_hearthstone_cn.sh check    # 仅检查环境，不做任何修改
#   ./setup_hearthstone_cn.sh install  # 部署运行器与运行库，并调起 Lutris 安装向导
#
# 原理与详细教程见同目录 README.md
# ==============================================================================

set -eo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[信息]${NC} $*"; }
warn()  { echo -e "${YELLOW}[警告]${NC} $*"; }
error() { echo -e "${RED}[错误]${NC} $*"; }

# ---- 可调参数 ---------------------------------------------------------------
RUNNER_VERSION="wine-tkg-ntsync-10.13-wow64-x86_64"
RUNNER_URL="https://file.winegame.net/runners/wine/wine-10.13/wine-10.13-staging-tkg-ntsync-amd64-wow64.tar.xz"
RUNNER_DIR="${HOME}/.local/share/lutris/runners/wine/${RUNNER_VERSION}"
WINEINIT_URL="https://file.winegame.net/games/common/wineinit.sh"
MONO_VERSION="10.1.0"
MONO_SHA256="c88c2431890bc32cacec8d7ea70e53a5ae4b95c8c55ca6e75ef8db0e4ccf1070"
YAML_FILE="$(cd "$(dirname "$0")" && pwd)/battlenet-cn-lutris.yml"
# -----------------------------------------------------------------------------

check_env() {
    local ok=1
    if command -v lutris >/dev/null 2>&1; then
        info "Lutris 已安装: $(lutris --version 2>/dev/null || echo '未知版本')"
    else
        warn "未安装 Lutris，请执行: sudo apt install lutris"
        ok=0
    fi
    if [ -e /dev/ntsync ]; then
        info "检测到 /dev/ntsync，NTsync 同步原语可用（降低卡顿）"
    else
        warn "未检测到 /dev/ntsync（不影响安装，仅少一项优化）"
    fi
    if [ -d "${RUNNER_DIR}" ]; then
        info "Wine 运行器已存在: ${RUNNER_DIR}"
    else
        warn "Wine 运行器未安装（install 时会自动下载，约 72MB）"
    fi
    if [ $ok -eq 1 ]; then
        info "环境检查通过"
    fi
    return 0
}

install_runner() {
    if [ -x "${RUNNER_DIR}/bin/wine" ]; then
        info "运行器已存在，跳过下载"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d /tmp/wine-runner.XXXXXX.tar.xz)"
    info "下载 Wine 运行器 (72MB，来自 winegame.net 国内镜像)..."
    curl -fL --retry 3 -o "${tmp}" "${RUNNER_URL}"
    mkdir -p "$(dirname "${RUNNER_DIR}")"
    tar xJf "${tmp}" -C "$(dirname "${RUNNER_DIR}")"
    rm -f "${tmp}"
    # 归档内目录名是 wine-10.13-staging-tkg-ntsync-amd64-wow64，重命名为 Lutris 版本名
    if [ -d "$(dirname "${RUNNER_DIR}")/wine-10.13-staging-tkg-ntsync-amd64-wow64" ]; then
        rm -rf "${RUNNER_DIR}"
        mv "$(dirname "${RUNNER_DIR}")/wine-10.13-staging-tkg-ntsync-amd64-wow64" "${RUNNER_DIR}"
    fi
    info "运行器版本: $("${RUNNER_DIR}/bin/wine" --version)"
}

prefetch_runtime() {
    local cache_dir="${HOME}/.cache/wine"
    mkdir -p "${cache_dir}"
    info "预下载 Gecko / Mono / 中文字体（wineinit.sh，国内镜像）..."
    local tmp_sh
    tmp_sh="$(mktemp /tmp/wineinit.XXXXXX.sh)"
    curl -fsSL -o "${tmp_sh}" "${WINEINIT_URL}"
    WINE="${RUNNER_DIR}/bin/wine" bash "${tmp_sh}" win64 || warn "wineinit 部分下载失败，继续（可稍后重跑）"
    rm -f "${tmp_sh}"

    # winegame 镜像可能尚未收录最新 Mono，回退 winehq 官方源并校验 sha256
    local mono_file="${cache_dir}/wine-mono-${MONO_VERSION}-x86.msi"
    if [ ! -f "${mono_file}" ] || [ "$(sha256sum "${mono_file}" | awk '{print $1}')" != "${MONO_SHA256}" ]; then
        info "从 winehq 官方源下载 wine-mono-${MONO_VERSION}..."
        curl -fL --retry 3 -o "${mono_file}" \
            "https://dl.winehq.org/wine/wine-mono/${MONO_VERSION}/wine-mono-${MONO_VERSION}-x86.msi"
        if [ "$(sha256sum "${mono_file}" | awk '{print $1}')" = "${MONO_SHA256}" ]; then
            info "Mono sha256 校验通过"
        else
            error "Mono sha256 校验失败！请手动检查 ${mono_file}"
            exit 1
        fi
    else
        info "Mono 已缓存，跳过"
    fi
}

launch_installer() {
    if [ ! -f "${YAML_FILE}" ]; then
        error "找不到安装脚本 ${YAML_FILE}"
        exit 1
    fi
    info "调起 Lutris 安装向导，请在弹出的窗口中操作："
    echo    "  1. 选择安装目录（默认即可，一路继续）"
    echo    "  2. 弹出战网安装程序后：按默认路径安装，不要登录，装完直接关闭"
    echo    "  3. 完成后 Lutris 列表会出现「暴雪战网国服」条目"
    lutris -i "${YAML_FILE}"
}

case "${1:-}" in
    check)
        check_env
        ;;
    install)
        check_env
        install_runner
        prefetch_runtime
        launch_installer
        ;;
    *)
        echo -e "${BOLD}用法: $0 {check|install}${NC}"
        echo "  check   仅检查环境"
        echo "  install 部署运行器与运行库，并调起 Lutris 安装向导"
        exit 1
        ;;
esac
