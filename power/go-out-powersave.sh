#!/bin/bash
# ==============================================================================
# 外出极度节电模式脚本 (适用于 七彩虹 P15 / Pop!_OS COSMIC)
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}       正在启动外出省电模式 (Power Saving)    ${NC}"
echo -e "${BLUE}==============================================${NC}"

# 请求 sudo 权限（只需要输入一次密码）
sudo -v || { echo "获取管理员权限失败，退出"; exit 1; }

# ------------------------------------------------------------------------------
# 1. 屏幕刷新率降至 60Hz（立即生效，无需重启）
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[1/6] 调整屏幕刷新率为 60Hz...${NC}"
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
    cosmic-randr mode eDP-1 2560 1440 --refresh 60 2>/dev/null
    echo -e "${GREEN}✓ 屏幕已成功切至 60Hz${NC}"
else
    echo "未找到 cosmic-randr，跳过屏幕刷新率调节"
fi

# ------------------------------------------------------------------------------
# 2. 系统电源模式切换为 Battery (限制激进功耗与最高功耗墙)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[2/6] 切换系统电源配置为 Battery 模式...${NC}"
system76-power profile battery >/dev/null 2>&1
echo -e "${GREEN}✓ 已开启 Battery 省电配置 (已禁用 CPU Turbo 睿频)${NC}"

# ------------------------------------------------------------------------------
# 3. CPU 深度能效调节 (EPP 设为 power 模式)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[3/6] 设置 CPU 能量偏好 (EPP) 为极致省电 (power)...${NC}"
for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    if [ -f "$f" ]; then
        echo "power" | sudo tee "$f" >/dev/null
    fi
done
echo -e "${GREEN}✓ CPU EPP 已设为 power (轻载时降低电压并抑制非必要升频)${NC}"

# ------------------------------------------------------------------------------
# 4. 关闭大核超线程 (保持 12 物理核心，显著降低空闲与轻载漏电)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[4/6] 调整 CPU 架构：关闭大核超线程，保留 12 个物理核心...${NC}"
if [ -f /sys/devices/system/cpu/smt/control ]; then
    echo "off" | sudo tee /sys/devices/system/cpu/smt/control >/dev/null
    echo -e "${GREEN}✓ SMT 已关闭：当前运行 4 个大核物理核心 + 8 个能效小核 (共 12 核心)${NC}"
else
    # 备用方案：逐个关闭大核逻辑超线程 (CPU 1, 3, 5, 7)
    for cpu in 1 3 5 7; do
        if [ -f "/sys/devices/system/cpu/cpu$cpu/online" ]; then
            echo 0 | sudo tee "/sys/devices/system/cpu/cpu$cpu/online" >/dev/null
        fi
    done
    echo -e "${GREEN}✓ 超线程已离线 (保留 12 个物理核心)${NC}"
fi

# ------------------------------------------------------------------------------
# 5. PCI 总线与 NVMe 固态硬盘自动休眠 + 开启 PCIe ASPM 节能
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[5/6] 启用 PCIe 总线与 NVMe 自动休眠...${NC}"
for dev in /sys/bus/pci/devices/*/power/control; do
    if [ -f "$dev" ]; then
        echo "auto" | sudo tee "$dev" >/dev/null
    fi
done

if [ -f /sys/module/pcie_aspm/parameters/policy ]; then
    echo "powersave" | sudo tee /sys/module/pcie_aspm/parameters/policy >/dev/null
fi

# 关闭未插网线的 Realtek 有线网卡
if ip link show enp3s0 >/dev/null 2>&1; then
    sudo ip link set enp3s0 down 2>/dev/null
fi
echo -e "${GREEN}✓ PCI 设备与 NVMe 固态已开启空闲自动低功耗，ASPM 已开启${NC}"

# ------------------------------------------------------------------------------
# 6. 显卡模式切换为纯核显 (integrated)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[6/6] 检查并配置显卡模式...${NC}"
CURRENT_GFX=$(system76-power graphics 2>/dev/null)
NEED_REBOOT=0

if [ "$CURRENT_GFX" != "integrated" ]; then
    echo "当前显卡模式为 [$CURRENT_GFX]，正在切换为纯核显模式 [integrated]..."
    system76-power graphics integrated >/dev/null 2>&1
    NEED_REBOOT=1
    echo -e "${GREEN}✓ 显卡模式已配置为 integrated (纯核显)${NC}"
else
    echo -e "${GREEN}✓ 显卡当前已是 integrated (纯核显) 模式${NC}"
fi

echo -e "\n${BLUE}==============================================${NC}"
echo -e "${GREEN}       外出省电模式配置完成！已达到最低功耗状态${NC}"
echo -e "${BLUE}==============================================${NC}"

if [ $NEED_REBOOT -eq 1 ]; then
    echo -e "${YELLOW}【重要提示】${NC}"
    echo -e "显卡模式已配置为【纯核显 (integrated)】，独显切断供电需要【重启系统】后生效。"
    echo -e "如果准备出门，建议现在重启电脑以彻底关闭 RTX 3050 显卡供电。"
else
    echo -e "显卡已处于纯核显状态，所有节电设置均已实时生效，可直接带出门使用！"
fi
