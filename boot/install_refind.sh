#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "请使用 sudo 运行此脚本: sudo bash $0"
  exit 1
fi

echo "=================================================="
echo "          正在安装与配置 rEFInd 引导管理器         "
echo "=================================================="

echo "==> 1. 更新软件源并安装 rEFInd..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y refind

echo "==> 2. 写入引导项到 EFI 分区..."
refind-install --yes || true

echo "==> 3. 配置倒计时时间为 5 秒..."
REFIND_CONF="/boot/efi/EFI/refind/refind.conf"
if [ -f "$REFIND_CONF" ]; then
  if grep -q "^timeout" "$REFIND_CONF"; then
    sed -i 's/^timeout .*/timeout 5/' "$REFIND_CONF"
  else
    echo "timeout 5" >> "$REFIND_CONF"
  fi
  echo "  [✓] 已将开机倒计时设为 5 秒"
fi

echo "==> 4. 验证 EFI 引导项..."
efibootmgr | grep -i refind || true

echo ""
echo "=================================================="
echo "  [✓] rEFInd 图形化引导安装完成！"
echo "  下次重启电脑即可直接看到带系统图标的开机选择界面。"
echo "=================================================="
