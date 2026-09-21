# Pop!_OS 24.04 实用运维与调优脚本合集 (popos-scripts)

本项目收集并整理了在 **Pop!_OS 24.04 LTS (COSMIC Desktop / Wayland)** 环境下日常使用、硬件调优、双系统引导维护以及应用适配的实用脚本与配置。

---

## 目录结构

```text
popos-scripts/
├── power/              # 移动续航与电源深度调优（外出极度节电与日常全性能一键切换）
│   ├── go-out-powersave.sh
│   └── restore-power.sh
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
│   ├── fcitx5/
│   │   └── setup_fcitx5.sh # Fcitx5 自然码双拼、现代词库与体验一键调优
│   ├── firefox/
│   │   └── user.js     # Intel 核显 VA-API 4K 硬件解码加速
│   ├── flameshot/
│   │   └── flameshot   # Flameshot 截图工具启动包装器
│   ├── satty/          # Satty 截图与标注工具在 COSMIC Wayland 下的完整方案与踩坑修复
│   │   ├── setup_satty.sh    # 一键安装、升级 grim 1.5.0、配置快捷键与防挂起脚本
│   │   ├── satty-screenshot  # 智能启动包装器（自动嗅探 Wayland 套接字、隔离 stdin 防死锁）
│   │   └── config.toml       # 预设中文字体回退、Enter 复制即退、截图存储路径优化配置
│   └── wechat/
│       └── fix-wechat-ime.sh # Linux 官方微信输入法候选框固定左上方/不跟随光标修复脚本
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

- **Fcitx5 拼音输入体验与现代词库调优 (`apps/fcitx5/setup_fcitx5.sh`)**：
  - **解决痛点**：默认 Fcitx5 词库极度匮乏，打常用现代词和口语短语无法整词首选命中；在自然码双拼下因开启模糊音与不完整元音导致候选严重乱序；默认关闭云拼音。
  - **优化效果**：一键部署 ~60MB 社区顶级现代词库（包含数百万生活词汇、成语俗语、中文维基百科名词、网络流行语），关闭干扰首选项的模糊规则，开启百度云拼音并置于第 2 位，配置自然码双拼并重载生效。
  - **使用方法**：
    ```bash
    cd apps/fcitx5
    ./setup_fcitx5.sh
    ```
- **Firefox Intel VA-API 硬件视频加速 (`apps/firefox/user.js`)**：
  - **解决痛点**：Linux 版 Firefox 默认使用 CPU 软解视频，导致观看 B站、YouTube 视频时 CPU 占用飙升至 50% 以上、笔记本发热风扇狂转。
  - **优化效果**：强制开启 Intel Iris Xe 核显专用媒体硬件解码器（支持 H.264、H.265、VP9、AV1 4K/8K），CPU 占用降至 1%~3%，功耗和发热大幅降低。
  - **部署方法**：将 `user.js` 复制到你的 Firefox 用户配置目录中并重启浏览器：
    ```bash
    cp apps/firefox/user.js ~/.config/mozilla/firefox/*.default-release/
    ```
- **Flameshot 启动包装器 (`apps/flameshot/flameshot`)**：
  Flameshot Flatpak 版本的命令行调用包装脚本。
- **Satty 现代截图与标注工具部署 (`apps/satty/setup_satty.sh`)**：
  - **解决痛点**：在 Pop!_OS 24.04 (COSMIC Desktop / Wayland) 环境下，传统截图工具（如 Flameshot / ksnip）体验欠佳，而 Wayland 原生的 `grim` + `slurp` + `satty` 组合在 COSMIC 下存在三大隐蔽坑点：
    1. **协议不兼容**：官方源自带的 `grim 1.4.0` 仅支持旧版 `wlr-screencopy` 协议，而 COSMIC 合成器 (`cosmic-comp`) 仅实现了更新的 `ext-image-copy-capture-v1` 标准，导致直接报错 `compositor doesn't support wlr-screencopy-unstable-v1` 无法截图；
    2. **快捷键管道死锁挂起**：通过桌面全局快捷键唤起时，标准输入（stdin）为非交互式管道，`slurp` 默认会一直卡在 `read()` 等待外界输入预设矩形（`anon_pipe_read`），导致屏幕毫无反应且后台堆积大量卡死进程；
    3. **合成器后台无环境变量**：`cosmic-comp` 直接 Spawn 启动的快捷键子进程未继承 `WAYLAND_DISPLAY` 环境变量，导致子进程尝试连接默认错误的 `wayland-0` 套接字失败退出。
  - **优化与修复原理**：
    1. 自动升级 `grim` 至 >= 1.5.0 版本，打通 `ext-image-copy-capture-v1` 协议支持；
    2. 部署与 Pop!_OS 24.04 (GLIBC 2.39) 兼容的 `satty` (v0.20.1) 现代标注程序（支持画笔、箭头、矩形、文字、马赛克高斯模糊等）；
    3. 编写 `satty-screenshot` 包装器，自动嗅探 `/run/user/$UID/wayland-*` 挂载真实的活动 `WAYLAND_DISPLAY`，并在非 TTY 下重定向 `slurp < /dev/null` 彻底解决挂起，增加防重入互斥与 `--full` 全屏截图支持；
    4. 自动写入 `~/.config/satty/config.toml`，配置 `Noto Sans CJK SC` 中文字体回退、按 `Enter` 或 `Ctrl+C` 复制即退、保存路径设为 `~/Pictures/Screenshots/`；
    5. 自动向 COSMIC 自定义快捷键注入 `Super + Shift + S` 与 `Ctrl + Alt + A`。
  - **使用方法**：
    ```bash
    cd apps/satty
    ./setup_satty.sh
    ```
    *注：若需彻底卸载，可执行 `./setup_satty.sh --uninstall`。*
- **Linux 微信输入法候选框位置修复 (`apps/wechat/fix-wechat-ime.sh`)**：
  - **解决痛点**：在 Pop!_OS 24.04 (COSMIC Desktop / Wayland) 环境下使用原生 Linux 官方微信打字时，Fcitx5 输入法候选词框无法跟随打字光标，而是死死固定在屏幕左上方固定点（如 `+323+506` 区域），无论把微信窗口拖动到屏幕何处，候选框都完全不会跟随。
  - **根本原因剖析**：
    1. 系统环境默认配置了 `QT_QPA_PLATFORM=wayland;xcb`，导致微信优先作为原生 Wayland 客户端启动；
    2. 微信内置的 `fcitx-qt5` 插件在计算光标位置时调用了 `mapToGlobal()`；
    3. 在 Wayland 协议的安全隔离限制下，普通客户端无法获取屏幕全局坐标，`mapToGlobal()` 失败退化，返回了输入框在微信窗口内部的局部相对坐标（如 `323, 506`）；
    4. 微信把此局部坐标误当成全局屏幕坐标通过 D-Bus 发送给 Fcitx5，导致 Fcitx5 将候选窗口硬编码绘制在屏幕物理像素 `(323, 506)` 处。由于输入框相对于微信窗口左上角的偏移是恒定不变的，导致候选框呈现出“永远死死钉在左上方”的现象。
  - **修复原理**：启动微信时清空 `WAYLAND_DISPLAY` 并强制 `QT_QPA_PLATFORM=xcb`，使微信彻底作为真正的 X11 (XWayland) 顶层窗口运行。此时 `mapToGlobal()` 能通过 X11 的 `XTranslateCoordinates` 正确换算真实的全局屏幕坐标，Fcitx5 候选框即可实时跟随窗口移动并精准贴合打字光标。
  - **使用方法**：
    ```bash
    cd apps/wechat
    ./fix-wechat-ime.sh
    ```
    *注：若需还原为系统默认配置，可执行 `./fix-wechat-ime.sh --uninstall`。*

---

### 5. 移动续航与电源深度调优 (`power/`)
- **解决痛点**：搭载 Intel 12代标压酷睿（如 i5-12500H）+ NVIDIA 独显的高刷游戏本在 Linux (Pop!_OS / COSMIC) 环境下离电功耗极高（常态待机高达 20W~26W），导致 50Wh 左右电池轻度使用仅能坚持 1~1.5 小时。
- **技术原理**：
  1. **显卡与显示**：一键切换至 `integrated` 纯核显模式切断独显供电，并将 2.5K 屏幕刷新率从 165Hz 瞬时无缝切至 60Hz。
  2. **处理器深度节能**：调用 `system76-power` 将配置文件切至 `battery`（禁用 CPU Turbo 睿频），设置 CPU EPP (Energy Performance Preference) 为 `power` 模式抑制瞬时升频与电压尖峰。
  3. **架构漏电压制**：通过内核 SMT 控制接口关闭大核超线程，保留 4 个性能大核物理核心 + 8 个能效小核（共 12 物理核心），大幅削减空闲漏电同时确保多任务依然充沛流畅。
  4. **总线与外设休眠**：将长江存储 PC300 等 NVMe 固态硬盘与所有 PCI 设备电源控制切至 `auto` 开启 APST，启用 PCIe ASPM `powersave` 策略打通 CPU Package 深睡眠状态（C8/C10），并断开未插线的有线网卡。
- **使用方法**：
  - **出门前一键开启极致节电**：
    ```bash
    ./power/go-out-powersave.sh
    ```
    *注：若显卡模式从混合模式切至纯核显，建议按提示重启一次电脑以彻底切断 RTX 独显供电。整机离电功耗可降至 9W~11W，轻度使用续航提升至 3.5~4 小时。*
  - **回家插电一键恢复全性能模式**：
    ```bash
    ./power/restore-power.sh
    ```
    *注：屏幕瞬时切回 165Hz 高刷、恢复 Balanced 平衡模式与全部 16 线程；显卡模式切回 hybrid（重启后独显恢复满血工作）。*

---

## 许可证
本项目代码与脚本均采用 [MIT License](LICENSE) 授权开源。
