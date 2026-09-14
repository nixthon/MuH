# MuH (Multiplexing Host Manager)

<p align="center">
  <a href="README.md">English</a> | <b>简体中文</b>
</p>

<p align="center">
  <strong>超轻量、高性能的 macOS 原生多机 Agent 终端管理器</strong><br>
  <em>搭配 Herdr / Luvus，让多台机器上的数十个 AI Agent 生命体征与提醒尽收眼底</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0+-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Terminal%20Engine-Ghostty%20(libghostty)-orange" alt="Ghostty Engine" />
  <img src="https://img.shields.io/badge/Multiplexer-Herdr%20%7C%20Luvus-green" alt="Multiplexer Integration" />
  <img src="https://img.shields.io/badge/Version-v0.1.6-brightgreen" alt="Version" />
  <img src="https://img.shields.io/badge/License-MIT-purple" alt="License" />
</p>

<p align="center">
  <img src="docs/screenshot.png" alt="MuH 界面预览" width="880" style="border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,0.2);" />
</p>

---

## 💡 为什么需要 MuH？

在 AI 编码（Agentic Coding）时代，开发者常常需要在**多台机器**上并行调度多个 AI Agent（例如：本地 Mac 运行前端、GPU 工作站 `dev1` 进行模型微调、云主机 `dev2` 运行自动化测试）。

**传统工具在多机开发下的痛点：**
- **单机 Multiplexer（Tmux / 单机 Herdr / Luvus）**：作用域仅限单台机器内部，无法跨机器聚合全局状态。开发者必须反复切换终端标签，肉眼排查究竟是哪台机器上的 Agent 阻塞报错、哪台刚刚完成任务。
- **传统 GUI 终端（iTerm2 / Warp / Ghostty）**：缺乏 Agent 语义感知，侧边栏只能展示生硬的主机名或进程名，无法感知机器内部 Agent 的生命体征。
- **Web 看板 / 监控面板**：需要为每台机器开放公网端口、配置复杂的反向代理与鉴权，运维负担沉重，且与本地键盘驱动的终端操作严重割裂。

**MuH (Multiplexing Host Manager) 带来了全新解决方案：**
> **定位：1 Host = 1 个内嵌 Ghostty 终端（运行远程或本地的 Herdr / Luvus）。**

MuH 作为 macOS 顶层 Host 容器，通过极简的 **PTY 终端标题通道（OSC 0）** 无感知穿透 SSH 回传各机器内部 Agent 的实时生命体征，聚合在左侧边栏，并提供 macOS 原生的智能横幅与声音提醒！

---

## ✨ 核心特性

### 1. 🌐 多机 Agent 全景看板（生命体征一目了然）
* **符号数量 = 存活 Agent 数量**：侧边栏实时呈现各 Host 的 Agent 状态符号，严格遵循语义与优先级规则：
  * <font color="#f87171">🔴 **`×`**</font> **阻塞 / 需要人类介入确认**（`blocked`，高优排在最前）
  * <font color="#4ade80">🟢 **`✓`**</font> **任务完成待查看**（`done`）
  * <font color="#fbbf24">🟡 **`◐`**</font> **正在执行中**（`working`）
  * <font color="#4ade80">🟢 **`○`**</font> **活着但处于待命空闲状态的 Agent**（`idle`）
  * 当 Host 上 **0 个 Agent 存活**时，自动显示纯净文本 `hostname: idle`（零符号）。
* **一键直达**：点击任意 Host，终端瞬间平滑切换至该机器的操作界面。

### 2. ⚡️ 纯 PTY 穿透，零网络开销与零额外配置
* 状态数据直接搭载在标准的 PTY 终端窗口标题（OSC 0）控制序列中流出。
* **零额外开放端口、零反向代理、自然穿透 SSH**。只要 SSH 能连通，状态就能 100% 毫秒级回传到本地 Mac。

### 3. 🔌 深度集成 Herdr & Luvus 多路复用器
* **分工明确**：MuH 专注于**跨机器全局管理与原生通知**；单机内部的多 Pane / Tab 调度与 Agent 监控委托给 [Herdr](https://github.com/herdr/herdr) 或 [Luvus](https://github.com/RizRiyz/luvus) (0.13.1+)。
* **原生支持 Pi Agent 等现代工具**：配套提供状态标题同步插件，内置生命周期安全心跳与自动资源释放机制。

### 4. 🧭 明确的主机生命周期控制
* **会话型 Host（SSH / Herdr / Luvus）**：
  * 左键单击仅用于选中查看，避免误触直接拉起重型 SSH 链接；
  * 由右键菜单「连接 / 断开」显式控制生命周期；
  * 断开后终端区显示居中占位提示，彻底释放后台进程资源。
* **本机型 Host（普通 Shell）**：
  * 保持点击即开，右键提供「重启」选项，方便快速重置或救活已退出的 Shell。

### 5. 🔔 macOS 原生智能系统通知与声音提醒
* **精准事件驱动**：当任意远程机器的 Agent 遇到阻塞（`×`）或所有任务完成（`✓`）时，MuH 发送 macOS 原生系统横幅通知并播放清脆音效。
* **点击通知秒切 Host**：在任何全屏应用或桌面下点击通知，MuH 自动置顶并精准切换至对应的主机终端。
* **14 款经典提示音**：内置 `Glass`, `Ping`, `Hero`, `Pop`, `Bottle` 等系统音效，支持在设置面板中一键试听与配置。

### 6. 🚀 极致性能与现代 macOS 桌面美学
* **Ghostty GPU 加速**：内嵌 `libghostty` 原生渲染引擎，享受极致流畅的 Metal 级硬件加速终端体验。
* **可自由拖拽侧边栏**：支持 150pt ~ 360pt 宽度自由拖拽，双击分界线快速恢复默认宽度，偏好自动持久化。
* **物理卡片设计**：终端区采用独立沉浸式卡片容器设计，配合精致边框与平滑圆角，层次分明。
* **零 SPM 外部依赖**：纯原生 Swift / SwiftUI + XcodeGen 架构，极速秒级编译。

---

## 🛠 快速上手

### 1. 下载与安装

前往 [Releases 页面](https://github.com/tangxijin/MuH/releases) 下载最新的 `MuH-v0.1.6-macOS.zip`：

```bash
# 解压并将应用移动到 Applications 目录
unzip MuH-v0.1.6-macOS.zip
mv MuH.app /Applications/
```

> **首次打开提示无法验证开发者？**
> 在系统「系统设置」➔「隐私与安全性」中点击「仍要打开」，或在终端执行：
> ```bash
> xattr -cr /Applications/MuH.app
> ```

---

### 2. 远程主机一键部署状态同步插件

MuH 提供了自包含、免包管理器的远程一键部署脚本，无需在远程机器手动安装额外包依赖：

#### 方案 A：使用 Herdr
```bash
ssh <user@host> 'bash -s' < Resources/scripts/setup-herdr.sh
```

#### 方案 B：使用 Luvus
```bash
ssh <user@host> 'bash -s' < Resources/scripts/setup-luvus.sh
```

*(也可以在 MuH 的「设置 (`⌘,`) ➔ 提醒」中一键拷贝远程安装命令)*

---

### 3. 从源码编译（开发者）

```bash
# 1. 克隆仓库
git clone https://github.com/tangxijin/MuH.git
cd MuH

# 2. 确保安装了 XcodeGen 和兼容的 Zig 0.16.x（首次需编译 libghostty）
./scripts/build-vendor.sh

# 3. 生成工程、构建 Debug 版并启动
./restart.sh
```

---

## ⌨️ 常用快捷键

| 快捷键 | 功能 |
| :--- | :--- |
| `⌘ + ,` | 打开 / 关闭设置面板 |
| `⌘ + N` | 新建 Host（默认 `~` 本地终端） |
| `⌘ + 1` ~ `⌘ + 9` | 快速切换到第 1 ~ 9 个 Host |
| `⌘ + C` / `⌘ + V` | 终端复制 / 粘贴（支持选中文本自动复制带浮动 HUD） |
| `⌘ + A` | 终端全选 |
| `⌘ + 鼠标点击` | 终端链接悬停提示与点击直达 |

---

## 🙏 致谢与致敬 (Acknowledgments)

本项目深受开源项目 **[mux0](https://github.com/10xChengTu/mux0)** 的启发，并复用了其部分优秀的 UI 设计模式与 Ghostty C Bridge 核心基础代码。在此向 `mux0` 的作者与贡献者们致以诚挚的感谢！

在此基础上，MuH 进行了针对多机 AI Agent 场景的全面革新：
- 将内部复杂的分屏/标签多路复用全面解耦并委托给 **Herdr** 与 **Luvus**；
- 首创基于纯 PTY OSC 0 终端标题的多机 Agent 生命体征聚合与穿透通道；
- 引入了完整的 macOS 原生事件通知系统、声音管理、会话生命周期控制与自包含远程免依赖部署。

---

## 📄 开源许可证

本项目采用 [MIT License](LICENSE) 许可证。
