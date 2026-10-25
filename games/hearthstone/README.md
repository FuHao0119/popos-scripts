# 国服炉石传说运行教程 (Pop!_OS / Ubuntu)

在 Linux 下通过 **Lutris + Wine 运行国服战网客户端**，进而安装并游玩国服《炉石传说》。
本教程基于 [Wine游戏助手 (winegame.net)](https://winegame.net/games/battlenet) 的国服成熟配方（「02. 国服（纯64位wine+DXVK）」，2026-04 更新），适配 Pop!_OS 26.04 + NVIDIA 混合显卡笔记本，已在实机上验证。

## 目录

- [原理](#原理)
- [前置条件](#前置条件)
- [快速开始（一键）](#快速开始一键)
- [手动分步教程](#手动分步教程)
- [安装完成后：开始玩炉石](#安装完成后开始玩炉石)
- [常见问题与踩坑](#常见问题与踩坑)
- [卸载方法](#卸载方法)
- [参考来源](#参考来源)

---

## 原理

- 《炉石传说》本体是 Unity 游戏，但**国服登录走网易账号体系**，必须通过国服版战网客户端（`Battle.net-Setup-CN.exe`，网易代理）登录和启动，所以思路是：Wine 跑国服战网 → 战网下载炉石 → 战网启动炉石。
- 国服战网在新版客户端里用 WebView 渲染登录页，直接用发行版自带 Wine 会**登录按钮不显示**。winegame 的配方通过「关闭战网硬件加速」的预写配置 + 专用 Wine 构建解决。
- 使用 winegame 自建的 `wine-tkg-ntsync-10.13-wow64` 运行器：
  - **纯 64 位 wow64 模式**（Windows 32 on Windows 64），不需要安装任何 32 位系统库；
  - **NTsync**（内核 NT 同步原语，Pop!_OS 内核已内置 `/dev/ntsync`），显著降低游戏卡顿；
  - 配 DXVK（D3D→Vulkan 转译），NVIDIA/AMD 独显直出。
- 国内网络环境下，运行器和运行库均从 winegame 国内镜像下载，速度快。

## 前置条件

| 项目 | 要求 | 检查命令 |
|------|------|----------|
| 发行版 | Pop!_OS 22.04+ / Ubuntu 22.04+（本教程实测 26.04） | `cat /etc/os-release` |
| Lutris | 0.5.x（apt 源里的即可） | `lutris --version` |
| 显卡驱动 | NVIDIA 专有驱动或 Mesa，Vulkan 可用 | `vulkaninfo --summary` |
| 内核 | ≥ 6.14 可启用 NTsync（非必需） | `ls /dev/ntsync` |
| 浏览器 | Firefox / Chrome 任一（网易登录页需要） | `command -v firefox` |
| 磁盘 | ≥ 15GB（战网 + 炉石） | `df -h ~` |

安装 Lutris（如未安装）：

```bash
sudo apt install lutris
```

## 快速开始（一键）

```bash
cd games/hearthstone
./setup_hearthstone_cn.sh check    # 先检查环境
./setup_hearthstone_cn.sh install  # 下载运行器(72MB)+运行库，然后弹出 Lutris 安装向导
```

脚本做完自动部分后，会弹出 Lutris 图形窗口，继续按 [手动分步教程](#手动分步教程) 第 3~5 步点击即可。

## 手动分步教程

如果你想了解每一步在做什么，或想手动操作：

### 第 1 步：安装专用 Wine 运行器

```bash
RUNNERS=~/.local/share/lutris/runners/wine
mkdir -p "$RUNNERS" && cd "$RUNNERS"
curl -fLO https://file.winegame.net/runners/wine/wine-10.13/wine-10.13-staging-tkg-ntsync-amd64-wow64.tar.xz
tar xJf wine-10.13-staging-tkg-ntsync-amd64-wow64.tar.xz
mv wine-10.13-staging-tkg-ntsync-amd64-wow64 wine-tkg-ntsync-10.13-wow64-x86_64
./wine-tkg-ntsync-10.13-wow64-x86_64/bin/wine --version
# 应输出: wine-10.13.r0.ga8a6d7b0 ( TkG Staging NTsync )
```

> 目录名必须与 Lutris 脚本里的 `wine: version:` 字段完全一致，否则 Lutris 找不到运行器。

### 第 2 步：预下载运行库（可选但推荐）

```bash
curl -fsSL -o /tmp/wineinit.sh https://file.winegame.net/games/common/wineinit.sh
WINE="$RUNNERS/wine-tkg-ntsync-10.13-wow64-x86_64/bin/wine" bash /tmp/wineinit.sh win64
```

Gecko 会从 winegame 镜像下载；若镜像上没有 `wine-mono-10.1.0-x86.msi`（404），从官方源补齐并校验：

```bash
curl -fL -o ~/.cache/wine/wine-mono-10.1.0-x86.msi \
  https://dl.winehq.org/wine/wine-mono/10.1.0/wine-mono-10.1.0-x86.msi
sha256sum ~/.cache/wine/wine-mono-10.1.0-x86.msi
# 预期: c88c2431890bc32cacec8d7ea70e53a5ae4b95c8c55ca6e75ef8db0e4ccf1070
```

### 第 3 步：调起 Lutris 安装向导

```bash
lutris -i battlenet-cn-lutris.yml
```

在弹出的窗口中**选择安装目录**（默认 `~/Games/…` 即可），Lutris 会自动完成：下载国服战网安装器（暴雪官方国内 CDN）→ 创建 64 位 Wine 前缀 → 安装中文字体 → 写入战网配置（关闭硬件加速，**这一步是登录按钮不显示的修复关键**）→ 写入炉石启动修复 → 注册表调整。

### 第 4 步：完成战网安装

自动步骤跑完后会弹出**国服战网安装程序**：

- 一定安装到**默认路径**（`C:\Program Files (x86)\Battle.net`），改路径会导致脚本判定安装失败；
- **不用登录**，装完直接关闭安装程序；
- Lutris 收尾后，游戏列表出现「**暴雪战网国服**」条目。

### 第 5 步：登录并安装炉石

双击「暴雪战网国服」→ 登录**网易邮箱账号** → 左侧游戏列表找到《炉石传说》→ 安装（默认装到同一前缀的 `C:\Program Files (x86)\Hearthstone`）→ 安装完点「游玩」。

## 安装完成后：开始玩炉石

以后每次玩的流程：启动 Lutris → 双击「暴雪战网国服」→ 登录 → 炉石「游玩」。
建议在战网设置里关闭「自动更新」，避免突然更新时打断体验。

## 常见问题与踩坑

以下均来自 winegame 脚本作者备注与实测：

1. **首次启动战网界面点不动**：按一次 `Alt+Tab` 即可恢复。打开战网设置后看不到设置窗口，`Alt+Tab` 再 `Shift+Alt+Tab` 就能找到。
2. **启动时弹出 ESync 相关英文对话框**：勾选「强行启动」，下次启动不会再弹（脚本已配 esync，fd 上限默认足够）。
3. **网易登录页面打不开**：确认系统装有 Firefox 或 Chrome；若都没有，建一个 `/usr/bin/firefox` 软链指向现有浏览器。
4. **战网安装卡 45%**：换用 winegame 的「0c. 使用预装好的战网wine容器」脚本（[winegame.net/games/battlenet](https://winegame.net/games/battlenet) 页面选 0c）。
5. **显卡不支持 Vulkan（如老旧核显）**：换用「0b. 国服（使用OpenGL）」脚本。
6. **炉石启动后黑屏/闪退**：确认 `options.txt` 已写入（脚本自动完成）；仍不行可在战网里对炉石做「扫描修复」。
7. **NVIDIA 混合显卡**：本方案 DXVK 走 Vulkan，一般自动落在独显上；如需强制，可在 Lutris「系统选项 → 环境变量」加 `DRI_PRIME=1` 或用 `prime-run` 前缀。
8. **Wayland 会话**：实测 Pop!_OS COSMIC Wayland 下可正常运行；战网窗口若出现残影，在 Lutris「显示选项」里关掉「开启虚拟桌面」即可。

## 卸载方法

```bash
# 1. 删除游戏前缀（战网 + 炉石全在里面，注意备份截图等数据）
rm -rf ~/Games/blizzard-battlenet-02-64winedxvk   # 目录名以 Lutris 实际安装位置为准

# 2. Lutris 里右键「暴雪战网国服」→ 移除（保留或删除数据均可选）

# 3. 删除运行器（可选）
rm -rf ~/.local/share/lutris/runners/wine/wine-tkg-ntsync-10.13-wow64-x86_64

# 4. 删除运行库缓存（可选，其他 Wine 应用可能共用）
rm -rf ~/.cache/wine
```

## 参考来源

- [Wine游戏助手：暴雪战网客户端（国服脚本维护页）](https://winegame.net/games/battlenet) —— 本目录 YAML 的来源，含 0b/0c 等备选方案
- [Reddit r/linux_gaming: The Ultimate Guide of Getting Hearthstone to Work](https://www.reddit.com/r/linux_gaming/comments/vb2smd/the_ultimate_guide_of_getting_hearthstone_to_work/) —— Lutris 跑炉石的通用思路
- [Arch Linux 中文论坛：使用 Lutris 完美运行战网](https://forum.archlinuxcn.org/t/topic/17112) —— 实战经验帖

> **免责声明**：本教程使用非官方渠道的第三方 Wine 构建与社区脚本运行战网客户端。Wine 方式游玩战网游戏在社区已长期实践，但理论上存在账号风险，请自行斟酌。《炉石传说》版权归暴雪娱乐/网易所有。
