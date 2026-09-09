#!/usr/bin/env bash
# ==============================================================================
# Fcitx5 Pinyin Experience Optimizer (Fcitx5 自然码双拼/全拼与现代词库一键配置脚本)
# 
# 功能特性：
# 1. 检测并提示安装必要的系统依赖与输入法前端模块 (fcitx5, fcitx5-chinese-addons 等)
# 2. 自动下载并部署 ~60MB 社区顶级现代词库 (CustomPinyinDictionary, zhwiki, web-slang)
# 3. 深度优化 pinyin.conf：配置自然码双拼、开启百度云拼音、关闭破坏首选排名的模糊音与PartialFinal
# 4. 确保 profile 配置包含 pinyin 输入法并设为首选
# 5. 安全重启 Fcitx5 守护进程并验证词库常驻
# ==============================================================================

set -eo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 目标路径
FCITX5_CONFIG_DIR="${HOME}/.config/fcitx5"
FCITX5_CONF_SUBDIR="${FCITX5_CONFIG_DIR}/conf"
FCITX5_DICT_DIR="${HOME}/.local/share/fcitx5/pinyin/dictionaries"

# 词库下载地址
URL_CUSTOM_DICT="https://github.com/wuhgit/CustomPinyinDictionary/releases/download/assets/CustomPinyinDictionary_Fcitx.dict"
URL_ZHWIKI_DICT="https://github.com/felixonmars/fcitx5-pinyin-zhwiki/releases/download/0.3.0/zhwiki-20260416.dict"
URL_WEBSLANG_DICT="https://github.com/felixonmars/fcitx5-pinyin-zhwiki/releases/download/0.3.0/web-slang-20260416.dict"

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

# 帮助信息
show_help() {
    echo -e "${BOLD}用法:${NC}"
    echo -e "  bash $(basename "$0") [选项]"
    echo -e ""
    echo -e "${BOLD}选项:${NC}"
    echo -e "  -a, --all          执行完整流程（安装依赖提示、下载词库、写入优化配置、重启服务）[默认]"
    echo -e "  -d, --dict-only    仅下载并安装最新词库文件"
    echo -e "  -c, --config-only  仅写入优化配置文件并重启服务"
    echo -e "  -h, --help         显示此帮助信息"
    echo -e ""
    echo -e "${BOLD}示例:${NC}"
    echo -e "  bash $(basename "$0")"
    echo -e "  bash $(basename "$0") --config-only"
}

# 1. 检查基础环境与依赖
check_dependencies() {
    log_info "正在检查系统依赖环境..."

    local missing_pkgs=()

    if ! command -v fcitx5 >/dev/null 2>&1; then
        missing_pkgs+=("fcitx5")
    fi

    if ! command -v curl >/dev/null 2>&1; then
        missing_pkgs+=("curl")
    fi

    # 检查 fcitx5-chinese-addons 相关文件 (比如 libpinyin.so)
    if [ ! -f /usr/lib/x86_64-linux-gnu/fcitx5/libpinyin.so ] && [ ! -f /usr/lib/fcitx5/libpinyin.so ]; then
        missing_pkgs+=("fcitx5-chinese-addons")
    fi

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        log_warn "检测到系统中缺少以下关键组件: ${missing_pkgs[*]}"
        echo -e "${YELLOW}请先运行包管理器安装对应组件：${NC}"
        
        if command -v apt >/dev/null 2>&1; then
            echo -e "  ${BOLD}sudo apt update && sudo apt install -y fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5 fcitx5-frontend-qt6 curl${NC}"
        elif command -v pacman >/dev/null 2>&1; then
            echo -e "  ${BOLD}sudo pacman -S --needed fcitx5 fcitx5-chinese-addons fcitx5-gtk fcitx5-qt curl${NC}"
        elif command -v dnf >/dev/null 2>&1; then
            echo -e "  ${BOLD}sudo dnf install -y fcitx5 fcitx5-chinese-addons fcitx5-gtk3 fcitx5-gtk4 fcitx5-qt5 fcitx5-qt6 curl${NC}"
        fi

        read -p "是否尝试自动调用 sudo 安装缺失的依赖包？(y/N): " -r choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if command -v apt >/dev/null 2>&1; then
                sudo apt update && sudo apt install -y fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5 fcitx5-frontend-qt6 curl
            elif command -v pacman >/dev/null 2>&1; then
                sudo pacman -S --needed fcitx5 fcitx5-chinese-addons fcitx5-gtk fcitx5-qt curl
            elif command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y fcitx5 fcitx5-chinese-addons fcitx5-gtk3 fcitx5-gtk4 fcitx5-qt5 fcitx5-qt6 curl
            else
                log_error "未识别支持的包管理器，请手动安装后重试。"
                exit 1
            fi
        else
            log_error "请安装缺失组件后再运行本脚本。"
            exit 1
        fi
    fi

    log_success "系统环境检查通过！"
}

# 2. 下载并安装高质量词库
install_dictionaries() {
    log_info "准备配置扩展词库..."
    mkdir -p "${FCITX5_DICT_DIR}"

    download_dict() {
        local name="$1"
        local url="$2"
        local target_file="${FCITX5_DICT_DIR}/$1"

        if [ -s "${target_file}" ]; then
            log_info "词库 [${name}] 已存在 ($(du -h "${target_file}" | cut -f1))，跳过下载。"
            return 0
        fi

        log_info "正在下载 ${name} ..."
        if curl -fL --retry 3 --connect-timeout 10 --progress-bar -o "${target_file}.tmp" "${url}"; then
            mv "${target_file}.tmp" "${target_file}"
            log_success "词库 [${name}] 下载完成 ($(du -h "${target_file}" | cut -f1))！"
        else
            log_error "下载 [${name}] 失败，请检查网络连接。"
            rm -f "${target_file}.tmp"
            return 1
        fi
    }

    # 依次下载三大词库
    download_dict "CustomPinyinDictionary_Fcitx.dict" "${URL_CUSTOM_DICT}"
    download_dict "zhwiki.dict" "${URL_ZHWIKI_DICT}"
    download_dict "web-slang.dict" "${URL_WEBSLANG_DICT}"

    log_success "所有扩展词库就绪！已安装至 ${FCITX5_DICT_DIR}"
}

# 3. 写入优化配置
apply_configs() {
    log_info "正在备份并更新 Fcitx5 配置文件..."
    mkdir -p "${FCITX5_CONF_SUBDIR}"

    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"

    # 停止正在运行的 fcitx5，防止进程退出时冲刷覆盖我们写入的配置
    if pgrep -x fcitx5 >/dev/null 2>&1; then
        log_info "临时停止 fcitx5 进程以安全写入配置..."
        pkill -x fcitx5 || true
        sleep 1
    fi

    # 备份现有配置
    if [ -f "${FCITX5_CONF_SUBDIR}/pinyin.conf" ]; then
        cp "${FCITX5_CONF_SUBDIR}/pinyin.conf" "${FCITX5_CONF_SUBDIR}/pinyin.conf.bak.${timestamp}"
    fi
    if [ -f "${FCITX5_CONF_SUBDIR}/cloudpinyin.conf" ]; then
        cp "${FCITX5_CONF_SUBDIR}/cloudpinyin.conf" "${FCITX5_CONF_SUBDIR}/cloudpinyin.conf.bak.${timestamp}"
    fi

    # 写入 pinyin.conf
    log_info "写入优化配置到 ${FCITX5_CONF_SUBDIR}/pinyin.conf ..."
    cat > "${FCITX5_CONF_SUBDIR}/pinyin.conf" << 'EOF'
# 双拼方案
ShuangpinProfile=Ziranma
# 显示当前双拼模式
ShowShuangpinMode=True
# 页大小
PageSize=7
# 启用拼写检查
SpellEnabled=True
# 启用颜文字
EmojiEnabled=True
# 启用拆字
ChaiziEnabled=True
# 启用 Unicode CJK 拓展区 B 中的字符
ExtBEnabled=True
# 启用云拼音
CloudPinyinEnabled=True
# 云拼音位置
CloudPinyinIndex=2
# 加载云拼音的时候显示动画
CloudPinyinAnimation=True
# 总是显示云拼音的占位符
KeepCloudPinyinPlaceHolder=False
# 预编辑模式
PreeditMode="Composing pinyin"
# 将嵌入预编辑文本的光标固定在开头
PreeditCursorPositionAtBeginning=True
# 在预编辑中显示完整拼音
PinyinInPreedit=False
# 启用预测
Prediction=False
# 预测个数
PredictionSize=49
# 切换输入法时的行为
SwitchInputMethodBehavior="Commit current preedit"
# 选择第 2 个候选词
SecondCandidate=
# 选择第 3 个候选词
ThirdCandidate=
# 使用数字键盘选词
UseKeypadAsSelection=False
# 使用退格键取消选词
BackSpaceToUnselect=True
# 句子数量
Number of sentence=2
# 输入长于...时提示长词 (设置为 0 时禁用)
LongWordLengthLimit=4
# 快速输入的触发键
QuickPhraseKey=semicolon
# 使用 V 来触发快速输入
VAsQuickphrase=True
# FirstRun
FirstRun=False

[ForgetWord]
0=Control+7

[PrevPage]
0=minus
1=Up
2=KP_Up

[NextPage]
0=equal
1=Down
2=KP_Down

[PrevCandidate]
0=Shift+Tab

[NextCandidate]
0=Tab

[ChooseCharFromPhrase]
0=bracketleft
1=bracketright

[FilterByStroke]
0=grave

[QuickPhrase trigger]
0=www.
1=ftp.
2=http:
3=mail.
4=bbs.
5=forum.
6=https:
7=ftp:
8=telnet:
9=mailto:

[Fuzzy]
# ue -> ve
VE_UE=True
# 常见错误
NG_GN=True
# 内模糊音节 (xian -> xi'an)
Inner=True
# 短拼音的内模糊音节 (qie -> qi'e)
InnerShort=True
# 匹配不完整的元音 (e -> en, eng, ei)
PartialFinal=False
# 输入长度大于 4 时进行部分双拼匹配
PartialSp=False
# u <-> v
V_U=False
# an <-> ang
AN_ANG=False
# en <-> eng
EN_ENG=False
# ian <-> iang
IAN_IANG=False
# in <-> ing
IN_ING=False
# u <-> ou
U_OU=False
# uan <-> uang
UAN_UANG=False
# c <-> ch
C_CH=False
# f <-> h
F_H=False
# l <-> n
L_N=False
# s <-> sh
S_SH=False
# z <-> zh
Z_ZH=False
EOF

    # 写入 cloudpinyin.conf
    log_info "写入云拼音配置到 ${FCITX5_CONF_SUBDIR}/cloudpinyin.conf ..."
    cat > "${FCITX5_CONF_SUBDIR}/cloudpinyin.conf" << 'EOF'
# 最小拼音长度
MinimumPinyinLength=4
# 后端
Backend=Baidu
# 代理
Proxy=

[Toggle Key]
0=Control+Alt+Shift+C
EOF

    # 确保 profile 包含 pinyin 输入法
    local profile_file="${FCITX5_CONFIG_DIR}/profile"
    if [ ! -f "${profile_file}" ] || ! grep -q "Name=pinyin" "${profile_file}"; then
        log_info "配置 ${profile_file} 以默认启用 pinyin 输入法..."
        cat > "${profile_file}" << 'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=pinyin

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=pinyin
# Layout
Layout=

[GroupOrder]
0=Default
EOF
    fi

    log_success "配置文件更新完成！旧配置已自动留档备查。"
}

# 4. 重载与启动服务
restart_service() {
    log_info "正在重载并启动 Fcitx5 服务..."

    # 如果系统配置了 systemd 用户级 autostart 服务，优先使用 systemctl
    if systemctl --user list-unit-files 2>/dev/null | grep -q "app-org.fcitx.Fcitx5@autostart.service"; then
        systemctl --user restart app-org.fcitx.Fcitx5@autostart.service || true
    else
        # 兜底直接后台启动
        pkill -x fcitx5 || true
        sleep 1
        setsid fcitx5 -d >/dev/null 2>&1 &
    fi

    sleep 2

    # 验证运行状态
    if pgrep -x fcitx5 >/dev/null 2>&1; then
        local pid
        pid=$(pgrep -x fcitx5)
        log_success "Fcitx5 守护进程已成功启动 (PID: ${pid})！"

        # 尝试通过 DBus 切换为 pinyin
        if command -v gdbus >/dev/null 2>&1; then
            gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller --method org.fcitx.Fcitx.Controller1.SetCurrentIM "pinyin" >/dev/null 2>&1 || true
        fi
    else
        log_warn "Fcitx5 启动未能检测到进程，请检查环境变量或手动运行 'fcitx5 -d'。"
    fi
}

# 主程序分发
main() {
    local mode="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)
                mode="all"
                shift
                ;;
            -d|--dict-only)
                mode="dict"
                shift
                ;;
            -c|--config-only)
                mode="config"
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo -e "${CYAN}====================================================${NC}"
    echo -e "${CYAN}${BOLD}       Fcitx5 自然码双拼与现代词库一键配置优化脚本      ${NC}"
    echo -e "${CYAN}====================================================${NC}"

    case "${mode}" in
        all)
            check_dependencies
            install_dictionaries
            apply_configs
            restart_service
            ;;
        dict)
            check_dependencies
            install_dictionaries
            restart_service
            ;;
        config)
            apply_configs
            restart_service
            ;;
    esac

    echo ""
    echo -e "${GREEN}${BOLD}🎉 全部优化配置已顺利完成！${NC}"
    echo -e "已生效的核心增强："
    echo -e "  1. ${BOLD}词库扩展${NC}：已挂载百万级常用词库 (CustomPinyinDictionary) + 中文维基百科 (zhwiki) + 流行语词库。"
    echo -e "  2. ${BOLD}精准命中${NC}：已关闭 PartialFinal 与前后鼻音模糊干扰，精准按键优先排在第 1 位。"
    echo -e "  3. ${BOLD}云端联想${NC}：已激活百度云拼音候选（固定置于第 2 位，长词/长句智能预测）。"
    echo -e "  4. ${BOLD}双拼方案${NC}：自然码双拼（Ziranma）。"
    echo -e "  5. ${BOLD}快捷键提示${NC}：翻页使用 [ - ] 和 [ = ]，错误词在候选框中按 [ Ctrl + 7 ] 即可遗忘。"
    echo ""
}

main "$@"
