#!/bin/bash
# ==============================================================================
# 恢复高性能/日常插电模式脚本 (适用于 七彩虹 P15 / Pop!_OS COSMIC)
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}       正在恢复日常/插电高性能模式            ${NC}"
echo -e "${BLUE}==============================================${NC}"

# 请求 sudo 权限（只需要输入一次密码）
sudo -v || { echo "获取管理员权限失败，退出"; exit 1; }

# ------------------------------------------------------------------------------
# 1. 恢复屏幕刷新率为 165Hz 高刷
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[1/6] 恢复屏幕刷新率为 165Hz 高刷...${NC}"
if [ -z "$WAYLAND_DISPLAY" ]; then
    for sock in /run/user/$(id -u)/wayland-*; do
        if [ -S "$sock" ]; then
            export WAYLAND_DISPLAY=$(basename "$sock")
            break
        fi
    done
fi
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

if command -v cosmic-randr >/dev/null 2>&1; then
    cosmic-randr mode eDP-1 2560 1440 --refresh 165 2>/dev/null
    echo -e "${GREEN}✓ 屏幕已成功恢复 165Hz 高刷新率${NC}"
else
    echo "未找到 cosmic-randr，跳过屏幕刷新率调节"
fi

# ------------------------------------------------------------------------------
# 2. 恢复系统电源模式为 Balanced (恢复 CPU 睿频加速)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[2/6] 切换系统电源配置为 Balanced (平衡模式)...${NC}"
system76-power profile balanced >/dev/null 2>&1
echo -e "${GREEN}✓ 已恢复 Balanced 模式 (重新允许 CPU Turbo 睿频)${NC}"

# ------------------------------------------------------------------------------
# 3. 恢复 CPU 能量偏好 (EPP) 为 balance_performance
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[3/6] 恢复 CPU 能量性能偏好 (EPP)...${NC}"
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    if [ -f "$f" ]; then
        echo "balance_performance" | sudo tee "$f" >/dev/null
    fi
done
echo -e "${GREEN}✓ CPU EPP 已恢复 balance_performance (响应更迅速)${NC}"

# ------------------------------------------------------------------------------
# 4. 恢复大核超线程 (恢复全部 16 线程)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[4/6] 恢复大核超线程 (恢复 16 线程全核心)...${NC}"
if [ -f /sys/devices/system/cpu/smt/control ]; then
    echo "on" | sudo tee /sys/devices/system/cpu/smt/control >/dev/null
    echo -e "${GREEN}✓ SMT 已开启：全部 12 核心 16 线程均已就绪${NC}"
else
    for cpu in 1 3 5 7; do
        if [ -f "/sys/devices/system/cpu/cpu$cpu/online" ]; then
            echo 1 | sudo tee "/sys/devices/system/cpu/cpu$cpu/online" >/dev/null
        fi
    done
    echo -e "${GREEN}✓ 所有超线程核心已恢复在线${NC}"
fi

# ------------------------------------------------------------------------------
# 5. 恢复 PCIe ASPM 策略为默认 + 恢复有线网卡
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[5/6] 恢复 PCIe 总线设置与网卡...${NC}"
if [ -f /sys/module/pcie_aspm/parameters/policy ]; then
    echo "default" | sudo tee /sys/module/pcie_aspm/parameters/policy >/dev/null
fi

if ip link show enp3s0 >/dev/null 2>&1; then
    sudo ip link set enp3s0 up 2>/dev/null
fi
echo -e "${GREEN}✓ PCIe ASPM 策略已恢复为 default，有线网卡已启用${NC}"

# ------------------------------------------------------------------------------
# 6. 恢复显卡模式为 hybrid (混合显卡模式)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[6/6] 检查并配置显卡模式...${NC}"
CURRENT_GFX=$(system76-power graphics 2>/dev/null)
NEED_REBOOT=0

if [ "$CURRENT_GFX" != "hybrid" ]; then
    echo "当前显卡模式为 [$CURRENT_GFX]，正在恢复为混合模式 [hybrid]..."
    system76-power graphics hybrid >/dev/null 2>&1
    NEED_REBOOT=1
    echo -e "${GREEN}✓ 显卡模式已配置为 hybrid (混合显卡)${NC}"
else
    echo -e "${GREEN}✓ 显卡当前已是 hybrid (混合显卡) 模式${NC}"
fi

echo -e "\n${BLUE}==============================================${NC}"
echo -e "${GREEN}       恢复完成！笔记本已回到全性能状态       ${NC}"
echo -e "${BLUE}==============================================${NC}"

if [ $NEED_REBOOT -eq 1 ]; then
    echo -e "${YELLOW}【重要提示】${NC}"
    echo -e "显卡模式已切回【hybrid 混合显卡】，RTX 3050 独显需要【重启系统】后恢复工作。"
    echo -e "如需运行大型游戏或 GPU 渲染加速，请重启电脑生效。"
else
    echo -e "显卡已处于混合显卡状态，无需重启，已即可享受 165Hz 全性能体验！"
fi
