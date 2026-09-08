#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本: sudo bash $0"
  exit 1
fi

WIN_EFI_PART="/dev/nvme0n1p1"
POP_EFI_DIR="/boot/efi"

echo "==> 1. 挂载 Windows EFI 分区并拷贝引导文件..."
MNT_DIR=$(mktemp -d /tmp/win-efi-XXXXXX)
mount "$WIN_EFI_PART" "$MNT_DIR"

if [ -d "$MNT_DIR/EFI/Microsoft" ]; then
  mkdir -p "$POP_EFI_DIR/EFI"
  cp -r "$MNT_DIR/EFI/Microsoft" "$POP_EFI_DIR/EFI/"
  echo "  [✓] 成功拷贝 Windows 引导文件到 Pop!_OS EFI 分区！"
else
  echo "  [✗] 警告: 未在 $WIN_EFI_PART 找到 EFI/Microsoft 目录！"
fi

umount "$MNT_DIR"
rmdir "$MNT_DIR"

echo "==> 2. 配置 systemd-boot 开机菜单等待时间 (5 秒)..."
LOADER_CONF="$POP_EFI_DIR/loader/loader.conf"
mkdir -p "$POP_EFI_DIR/loader"

if [ -f "$LOADER_CONF" ]; then
  if grep -q "^timeout" "$LOADER_CONF"; then
    sed -i 's/^timeout .*/timeout 5/' "$LOADER_CONF"
  else
    echo "timeout 5" >> "$LOADER_CONF"
  fi
else
  cat << 'EOF' > "$LOADER_CONF"
timeout 5
console-mode max
EOF
fi

echo "==> 3. 当前 loader.conf 内容："
cat "$LOADER_CONF"

echo ""
echo "=========================================================="
echo "  [✓] 配置成功！"
echo "  下次开机会自动出现启动菜单并倒计时 5 秒。"
echo "  按键盘上下键可随时在 Pop!_OS 和 Windows 之间切换。"
echo "=========================================================="
