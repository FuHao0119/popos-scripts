#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本: sudo bash $0"
  exit 1
fi

REFIND_CONF="/boot/efi/EFI/refind/refind.conf"

if [ ! -f "$REFIND_CONF" ]; then
  echo "未找到 $REFIND_CONF"
  exit 1
fi

echo "=================================================="
echo "          正在精简 rEFInd 启动菜单图标            "
echo "=================================================="

# 1. 禁用直接扫描内核文件（避免同一个系统显示多个 vmlinuz 内核图标）
if grep -q "^scan_all_linux_kernels" "$REFIND_CONF"; then
  sed -i 's/^scan_all_linux_kernels .*/scan_all_linux_kernels false/' "$REFIND_CONF"
elif grep -q "^#scan_all_linux_kernels" "$REFIND_CONF"; then
  sed -i 's/^#scan_all_linux_kernels .*/scan_all_linux_kernels false/' "$REFIND_CONF"
else
  echo "scan_all_linux_kernels false" >> "$REFIND_CONF"
fi

# 2. 忽略遗留的 Fedora、Ubuntu 目录以及重复的 Boot 目录
if grep -q "^dont_scan_dirs" "$REFIND_CONF"; then
  sed -i 's|^dont_scan_dirs .*|dont_scan_dirs EFI/fedora,EFI/ubuntu,EFI/Boot|' "$REFIND_CONF"
elif grep -q "^#dont_scan_dirs" "$REFIND_CONF"; then
  sed -i 's|^#dont_scan_dirs .*|dont_scan_dirs EFI/fedora,EFI/ubuntu,EFI/Boot|' "$REFIND_CONF"
else
  echo "dont_scan_dirs EFI/fedora,EFI/ubuntu,EFI/Boot" >> "$REFIND_CONF"
fi

# 3. 忽略多余的 shim 和 fallback 文件
if grep -q "^dont_scan_files" "$REFIND_CONF"; then
  sed -i 's|^dont_scan_files .*|dont_scan_files shimx64.efi,shim.efi,MokManager.efi,bootx64.efi|' "$REFIND_CONF"
elif grep -q "^#dont_scan_files" "$REFIND_CONF"; then
  sed -i 's|^#dont_scan_files .*|dont_scan_files shimx64.efi,shim.efi,MokManager.efi,bootx64.efi|' "$REFIND_CONF"
else
  echo "dont_scan_files shimx64.efi,shim.efi,MokManager.efi,bootx64.efi" >> "$REFIND_CONF"
fi

# 4. 精简底部工具栏图标（只保留重启、关机、固件设置）
if grep -q "^showtools" "$REFIND_CONF"; then
  sed -i 's|^showtools .*|showtools reboot,shutdown,firmware|' "$REFIND_CONF"
elif grep -q "^#showtools" "$REFIND_CONF"; then
  sed -i 's|^#showtools .*|showtools reboot,shutdown,firmware|' "$REFIND_CONF"
else
  echo "showtools reboot,shutdown,firmware" >> "$REFIND_CONF"
fi

echo "  [✓] 优化完成！"
echo "  多余的内核副本与残留引导项已被成功隐藏。"
echo "=================================================="
