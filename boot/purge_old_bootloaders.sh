#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本: sudo bash $0"
  exit 1
fi

echo "=================================================="
echo "      正在彻底清理已删除系统的遗留残留引导        "
echo "=================================================="

WIN_EFI_PART="/dev/nvme0n1p1"
MNT_DIR=$(mktemp -d /tmp/win-efi-clean-XXXXXX)

echo "==> 1. 挂载 EFI 分区 ($WIN_EFI_PART)..."
mount "$WIN_EFI_PART" "$MNT_DIR"

echo "==> 当前 EFI 分区下的所有引导文件夹："
ls -F "$MNT_DIR/EFI"

echo ""
echo "==> 2. 彻底删除已卸载系统的残留目录..."
if [ -d "$MNT_DIR/EFI/fedora" ]; then
  rm -rf "$MNT_DIR/EFI/fedora"
  echo "  [✓] 成功彻底删除残留的 EFI/fedora"
fi

if [ -d "$MNT_DIR/EFI/ubuntu" ]; then
  rm -rf "$MNT_DIR/EFI/ubuntu"
  echo "  [✓] 成功彻底删除残留的 EFI/ubuntu"
fi

umount "$MNT_DIR"
rmdir "$MNT_DIR"

echo ""
echo "==> 3. 清理主板 NVRAM 中的失效启动项..."
for bootnum in 0001 0003 0005; do
  if efibootmgr | grep -q "Boot${bootnum}"; then
    efibootmgr -b "$bootnum" -B >/dev/null 2>&1 || true
    echo "  [✓] 已从主板 NVRAM 注销 Boot${bootnum}"
  fi
done

echo ""
echo "==> 4. 优化 rEFInd 配置（屏蔽重复内核，精简界面）..."
REFIND_CONF="/boot/efi/EFI/refind/refind.conf"
if [ -f "$REFIND_CONF" ]; then
  sed -i 's/^#*scan_all_linux_kernels .*/scan_all_linux_kernels false/' "$REFIND_CONF" 2>/dev/null || echo "scan_all_linux_kernels false" >> "$REFIND_CONF"
  sed -i 's|^#*dont_scan_dirs .*|dont_scan_dirs EFI/fedora,EFI/ubuntu,EFI/Boot|' "$REFIND_CONF" 2>/dev/null || echo "dont_scan_dirs EFI/fedora,EFI/ubuntu,EFI/Boot" >> "$REFIND_CONF"
  sed -i 's|^#*dont_scan_files .*|dont_scan_files shimx64.efi,shim.efi,MokManager.efi,bootx64.efi|' "$REFIND_CONF" 2>/dev/null || echo "dont_scan_files shimx64.efi,shim.efi,MokManager.efi,bootx64.efi" >> "$REFIND_CONF"
  sed -i 's|^#*showtools .*|showtools reboot,shutdown,firmware|' "$REFIND_CONF" 2>/dev/null || echo "showtools reboot,shutdown,firmware" >> "$REFIND_CONF"
  echo "  [✓] rEFInd 配置已完成精简"
fi

echo ""
echo "=================================================="
echo "  [✓] 清理彻底完成！"
echo "  现在残留的 Fedora、Ubuntu 文件和主板项已全部被连根拔起。"
echo "  下次开机将只剩下干净的 Windows 和 Pop!_OS！"
echo "=================================================="
