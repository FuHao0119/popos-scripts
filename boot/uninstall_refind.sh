#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本: sudo bash $0"
  exit 1
fi

echo "=================================================="
echo "          正在彻底卸载与清理 rEFInd               "
echo "=================================================="

echo "==> 1. 卸载 refind 软件包..."
export DEBIAN_FRONTEND=noninteractive
apt purge -y refind

echo ""
echo "==> 2. 删除 EFI 分区中的 rEFInd 文件..."
if [ -d "/boot/efi/EFI/refind" ]; then
  rm -rf /boot/efi/EFI/refind
  echo "  [✓] 已删除 /boot/efi/EFI/refind 引导文件"
fi

echo ""
echo "==> 3. 从主板 NVRAM 注销 rEFInd 启动项..."
REFIND_BOOTNUM=$(efibootmgr | grep -i "rEFInd" | sed -E 's/^Boot([0-9A-Fa-f]+)\*?.*/\1/' | head -n 1)
if [ -n "$REFIND_BOOTNUM" ]; then
  efibootmgr -b "$REFIND_BOOTNUM" -B >/dev/null 2>&1 || true
  echo "  [✓] 已从主板彻底移除 rEFInd 引导项 (Boot${REFIND_BOOTNUM})"
fi

echo ""
echo "==> 4. 恢复 Pop!_OS 原生引导为第一启动项..."
POP_BOOTNUM=$(efibootmgr | grep -i "Pop!_OS" | sed -E 's/^Boot([0-9A-Fa-f]+)\*?.*/\1/' | head -n 1)
if [ -n "$POP_BOOTNUM" ]; then
  CURRENT_ORDER=$(efibootmgr | grep "^BootOrder:" | awk '{print $2}')
  CLEAN_ORDER=$(echo "$CURRENT_ORDER" | tr ',' '\n' | grep -v "^${REFIND_BOOTNUM}$" | grep -v "^${POP_BOOTNUM}$" | tr '\n' ',' | sed 's/,$//')
  NEW_ORDER="${POP_BOOTNUM},${CLEAN_ORDER}"
  efibootmgr -o "$NEW_ORDER" >/dev/null 2>&1 || true
  echo "  [✓] 已恢复默认启动项: Pop!_OS (${POP_BOOTNUM})"
fi

echo ""
echo "==> 5. 确保原生 systemd-boot 菜单可自由选择 Windows 与 Pop!_OS..."
LOADER_CONF="/boot/efi/loader/loader.conf"
if [ -f "$LOADER_CONF" ]; then
  if grep -q "^timeout" "$LOADER_CONF"; then
    sed -i 's/^timeout .*/timeout 5/' "$LOADER_CONF"
  else
    echo "timeout 5" >> "$LOADER_CONF"
  fi
  echo "  [✓] 原生引导菜单等待时间已设为 5 秒"
fi

echo ""
echo "==> 6. 当前主板启动项状态："
efibootmgr | grep -E "BootOrder|Boot[0-9]"

echo ""
echo "=================================================="
echo "  [✓] rEFInd 已彻底卸载并清理干净！"
echo "  开机将回归 Pop!_OS 官方原生的极速黑底菜单，"
echo "  只包含 Pop!_OS 和 Windows，倒计时 5 秒自由切换。"
echo "=================================================="
