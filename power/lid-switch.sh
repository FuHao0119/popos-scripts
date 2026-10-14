#!/bin/bash
# ==============================================================================
# 盒盖策略一键切换脚本 (适用于 Pop!_OS / COSMIC)
#
# 在两种盒盖行为之间切换 /etc/systemd/logind.conf 的 HandleLidSwitch 策略：
#   挂机模式 : 三项全部设为 ignore  → 合盖不挂起、不断网，适合后台跑 agent / 挂机下载
#   日常模式 : 三项全部注释掉       → 回到系统默认(合盖即挂起断网)，省电
#
# 用法:
#   ./lid-switch.sh              交互切换（默认：检测当前模式并切到另一边）
#   ./lid-switch.sh keepawake    直接切到「挂机模式」
#   ./lid-switch.sh default      直接切到「日常模式」
# ==============================================================================

set -uo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

LOGIND_CONF="/etc/systemd/logind.conf"
KEYS=(HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked)

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}          盒盖策略一键切换 (Lid Switch)       ${NC}"
echo -e "${BLUE}==============================================${NC}"

# ------------------------------------------------------------------------------
# 前置检查：配置文件必须存在
# ------------------------------------------------------------------------------
if [ ! -f "$LOGIND_CONF" ]; then
    echo -e "${RED}错误：找不到 $LOGIND_CONF，退出${NC}"
    exit 1
fi

# 请求 sudo 权限（只需要输入一次密码）
sudo -v || { echo -e "${RED}获取管理员权限失败，退出${NC}"; exit 1; }

# ------------------------------------------------------------------------------
# 判定当前模式：三项全部为 active 的 ignore → 挂机模式；否则 → 日常模式
# ------------------------------------------------------------------------------
current_mode() {
    for k in "${KEYS[@]}"; do
        grep -qE "^${k}=ignore$" "$LOGIND_CONF" || return 1
    done
    return 0
}

if current_mode; then
    CUR="keepawake"
    echo -e "当前模式：${YELLOW}挂机模式${NC}（合盖不挂起、不断网）"
else
    CUR="default"
    echo -e "当前模式：${YELLOW}日常模式${NC}（合盖即挂起断电，系统默认）"
fi

# ------------------------------------------------------------------------------
# 确定目标模式
# ------------------------------------------------------------------------------
if [ $# -ge 1 ]; then
    case "$1" in
        keepawake|ignore) TARGET="keepawake" ;;
        default|suspend)  TARGET="default" ;;
        *)
            echo -e "${RED}未知参数：$1${NC}"
            echo "可用参数：keepawake（挂机模式）| default（日常模式）| 无参数则交互切换"
            exit 1
            ;;
    esac
else
    if [ "$CUR" = "keepawake" ]; then TARGET="default"; else TARGET="keepawake"; fi
fi

if [ "$CUR" = "$TARGET" ]; then
    echo -e "${GREEN}✓ 已经处于目标模式，无需切换${NC}"
    exit 0
fi

# ------------------------------------------------------------------------------
# 应用变更
# ------------------------------------------------------------------------------
if [ "$TARGET" = "keepawake" ]; then
    echo -e "\n${YELLOW}[1/3] 切换到挂机模式：合盖保持运行、网络不掉线...${NC}"
    # 先取消注释（已注释的行恢复为 active）
    sudo sed -i -E 's/^#(HandleLidSwitch(ExternalPower|Docked)?=.*)$/\1/' "$LOGIND_CONF"
    # 强制三项的值都为 ignore
    sudo sed -i -E 's/^(HandleLidSwitch(ExternalPower|Docked)?)=.*/\1=ignore/' "$LOGIND_CONF"
    # 配置文件里完全没有的键补写在末尾
    for k in "${KEYS[@]}"; do
        grep -qE "^${k}=" "$LOGIND_CONF" || echo "${k}=ignore" | sudo tee -a "$LOGIND_CONF" >/dev/null
    done
else
    echo -e "\n${YELLOW}[1/3] 切换到日常模式：合盖即挂起断网（恢复系统默认）...${NC}"
    # 把 active 的三项注释掉（已是注释的保持不变，避免出现 ##）
    sudo sed -i -E 's/^(HandleLidSwitch(ExternalPower|Docked)?=.*)$/#\1/' "$LOGIND_CONF"
fi

# ------------------------------------------------------------------------------
# 重新加载 logind 使配置即时生效
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[2/3] 重新加载 systemd-logind...${NC}"
if ! sudo systemctl reload systemd-logind 2>/dev/null; then
    sudo systemctl restart systemd-logind
fi
echo -e "${GREEN}✓ logind 已重新加载${NC}"

# ------------------------------------------------------------------------------
# 校验实际生效值
# ------------------------------------------------------------------------------
echo -e "${YELLOW}[3/3] 校验当前生效值...${NC}"
ALL_OK=1
for k in "${KEYS[@]}"; do
    RAW=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
          org.freedesktop.login1.Manager "$k" 2>/dev/null | awk '{print $2}')
    printf "  %-30s %s\n" "$k" "$RAW"
    if [ "$TARGET" = "keepawake" ]; then
        [ "$RAW" = '"ignore"' ] || ALL_OK=0
    else
        # 日常模式下三项回落到系统默认：Docked 默认就是 ignore；
        # HandleLidSwitchExternalPower 未显式配置时属性返回空串（表示沿用默认），属正常
        case "$k" in
            HandleLidSwitch)        [ "$RAW" = '"suspend"' ] || ALL_OK=0 ;;
            HandleLidSwitchDocked)  [ "$RAW" = '"ignore"' ] || ALL_OK=0 ;;
            *)                      [ "$RAW" = '"suspend"' ] || [ "$RAW" = '""' ] || ALL_OK=0 ;;
        esac
    fi
done

echo -e "${BLUE}==============================================${NC}"
if [ $ALL_OK -eq 1 ]; then
    if [ "$TARGET" = "keepawake" ]; then
        echo -e "${GREEN}✓ 已切换到挂机模式${NC}"
        echo -e "合盖后系统继续运行、网络保持连接，可放心后台跑 agent / 挂机下载。"
    else
        echo -e "${GREEN}✓ 已切换到日常模式${NC}"
        echo -e "合盖即挂起并断网（系统默认行为），日常携带更省电。"
    fi
else
    echo -e "${RED}⚠ 校验未完全通过，请检查上方生效值${NC}"
    echo -e "可手动执行：systemd-analyze cat-config systemd/logind.conf"
    exit 1
fi
echo -e "${BLUE}==============================================${NC}"
