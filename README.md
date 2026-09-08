# Pop!_OS 24.04 实用运维与调优脚本合集 (popos-scripts)

本项目收集并整理了在 **Pop!_OS 24.04 LTS (COSMIC Desktop / Wayland)** 环境下日常使用、硬件调优、双系统引导维护以及应用适配的实用脚本与配置。

---

## 目录结构

```text
popos-scripts/
├── clipboard/          # QQ / 微信 Linux 原生版 Wayland 剪贴板图片粘贴桥接守护进程
│   ├── qq-clip-bridge.c
│   ├── wlr-data-control-unstable-v1-client-protocol.h
│   ├── wlr-data-control-unstable-v1-protocol.c
│   ├── qq-clip-bridge.service
│   └── Makefile
├── graphics/           # 显卡调度与独显性能调用
│   └── prime-run
├── boot/               # 双系统引导维护与 EFI 清理脚本
│   ├── setup_dualboot.sh
│   ├── purge_old_bootloaders.sh
│   ├── install_refind.sh
│   ├── clean_refind_menu.sh
│   └── uninstall_refind.sh
├── apps/               # 常用软件性能与体验优化配置
│   ├── firefox/
│   │   └── user.js     # Intel 核显 VA-API 4K 硬件解码加速
│   └── flameshot/
│       └── flameshot   # Flameshot 截图工具启动包装器
├── .gitignore
└── README.md
```

---

## 模块说明与使用指南

### 1. 剪贴板守护进程 (`clipboard/`)
- **解决痛点**：在 Wayland (COSMIC) 环境下，使用系统截图工具（如 Flameshot、系统自带截图）复制图片后，Linux 原生版 QQ 和微信无法直接通过 `Ctrl + V` 粘贴图片的问题。
- **技术原理**：通过 Wayland 的 `wlr-data-control` 协议在后台静默监听剪贴板图片事件，实时将图片转存至临时目录，并合成 QQ/微信能够识别的富文本（RichEdit）与 MIME 类型。
- **编译与安装**：
  ```bash
  cd clipboard
  make
  make install
  ```
  该命令会自动编译二进制文件安装至 `~/.local/bin/qq-clip-bridge`，并配置注册用户级 Systemd 开机自启服务 (`qq-clip-bridge.service`)。

---

### 2. 独显调度工具 (`graphics/`)
- **脚本**：`prime-run`
- **解决痛点**：在双显卡混合模式（Hybrid Mode）下，默认由低功耗核显渲染桌面。当需要运行大型 3D 游戏、建模软件或高负载计算时，一键指定调用 NVIDIA 独立显卡。
- **使用方法**：
  ```bash
  prime-run <程序名>
  # 示例：
  prime-run blender
  # Steam 启动选项中可填写：
  prime-run %command%
  ```

---

### 3. 双系统引导维护 (`boot/`)
专门针对 Pop!_OS（使用 `systemd-boot`）与 Windows 11 双系统环境编写的维护脚本：

- **`setup_dualboot.sh`**：
  解决开机直接跳过菜单秒进 Pop!_OS 的问题。自动同步 Windows EFI 引导文件到 Pop!_OS 分区，并开启 5 秒开机菜单倒计时。
- **`purge_old_bootloaders.sh`**：
  安全挂载 EFI 分区，彻底删除以前重装遗留的 Fedora、Ubuntu 等“幽灵”引导文件夹，并同步清理主板 BIOS (NVRAM) 中的失效启动项。
- **`install_refind.sh`**：
  一键安装与配置 rEFInd 图形化大图标多系统引导工具。
- **`clean_refind_menu.sh`**：
  优化 rEFInd 配置，屏蔽多余的 Linux 内核副本及冗余工具图标。
- **`uninstall_refind.sh`**：
  彻底干净卸载 rEFInd，清理残留 EFI 文件夹并还原 Pop!_OS 原生极简启动菜单。

---

### 4. 应用性能优化 (`apps/`)

- **Firefox Intel VA-API 硬件视频加速 (`apps/firefox/user.js`)**：
  - **解决痛点**：Linux 版 Firefox 默认使用 CPU 软解视频，导致观看 B站、YouTube 视频时 CPU 占用飙升至 50% 以上、笔记本发热风扇狂转。
  - **优化效果**：强制开启 Intel Iris Xe 核显专用媒体硬件解码器（支持 H.264、H.265、VP9、AV1 4K/8K），CPU 占用降至 1%~3%，功耗和发热大幅降低。
  - **部署方法**：将 `user.js` 复制到你的 Firefox 用户配置目录中并重启浏览器：
    ```bash
    cp apps/firefox/user.js ~/.config/mozilla/firefox/*.default-release/
    ```
- **Flameshot 启动包装器 (`apps/flameshot/flameshot`)**：
  Flameshot Flatpak 版本的命令行调用包装脚本。

---

## 许可证
本项目代码与脚本均采用 [MIT License](LICENSE) 授权开源。
