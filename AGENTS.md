# AGENTS.md

> 本文档为面向 AI 编码 Agent（如 Pi、Codex、Claude Code、Cursor 等）的项目背景与工程指南。

---

## 📌 项目概述 (Project Overview)

**MuH (Multiplexing Host Manager)** 是一款超轻量、高性能的 macOS 原生多机 Agent 终端管理器。
- **定位**：顶层 Host 容器（1 Host = 1 个内嵌 Ghostty 终端，运行远程/本地 Herdr）。
- **通信机制**：通过纯 PTY 终端标题通道（OSC 0）无感知穿透 SSH 回传 Agent 生命体征状态，实现侧边栏全景看板与 macOS 原生系统通知/音效提醒。
- **技术栈**：
  - **平台**：macOS 14.0+
  - **语言**：Swift 5.9+
  - **UI 架构**：SwiftUI + AppKit 混编（零 SPM 外部依赖，原生极速构建）
  - **工程管理**：[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`project.yml`)
  - **终端核心**：内嵌 `libghostty` (C API Bridging) GPU 加速渲染引擎
  - **多路复用与 Agent 管理**：单机内部 pane/tab 调度与 Agent 状态维护委托给 [Luvus](https://github.com/RizRiyz/luvus) 或 [Herdr](https://github.com/herdr/herdr)

---

## 🛠 常用命令速查 (Essential Commands)

### 1. 工程生成与配置
```bash
# 每次修改 project.yml 或新增/删除源文件后重新生成 .xcodeproj
xcodegen generate
```

### 2. 运行单元测试
```bash
# 执行全部 Swift 单元测试 (XCTest)
xcodebuild test -scheme MuH -destination "platform=macOS"
```

### 3. 本地调试与一键重启
```bash
# 清理缓存、重新生成工程、编译 Debug 版并启动
./restart.sh
```

### 4. Release 编译与本地安装
```bash
# 1. 生成工程
xcodegen generate

# 2. 编译 Release
xcodebuild -project MuH.xcodeproj -scheme MuH -configuration Release -derivedDataPath ./build/DerivedData build

# 3. 安装到 /Applications
rm -rf /Applications/MuH.app
cp -R ./build/DerivedData/Build/Products/Release/MuH.app /Applications/MuH.app
find /Applications/MuH.app -type d -exec chmod 755 {} +
find /Applications/MuH.app -type f -exec chmod 644 {} +
chmod 755 /Applications/MuH.app/Contents/MacOS/MuH
[ -f /Applications/MuH.app/Contents/Resources/setup-herdr.sh ] && chmod 755 /Applications/MuH.app/Contents/Resources/setup-herdr.sh
[ -f /Applications/MuH.app/Contents/Resources/setup-luvus.sh ] && chmod 755 /Applications/MuH.app/Contents/Resources/setup-luvus.sh
rm -rf ./build
```

### 5. Herdr / Luvus 插件与远程部署维护
```bash
# 运行 Herdr 插件逻辑单元测试 (验证符号排序与截断算法)
node Resources/herdr-plugin/index.js --test

# 运行 Luvus 模块逻辑单元测试
node Resources/luvus-plugin/index.js --test

# 模拟运行 Herdr / Luvus 插件
node Resources/herdr-plugin/index.js --dry-run
node Resources/luvus-plugin/index.js --dry-run

# 修改 Resources/herdr-plugin/ 或 Resources/luvus-plugin/ 后重新生成嵌入式远程安装脚本
./scripts/generate-setup-herdr.sh
./scripts/generate-setup-luvus.sh

# 向远程主机一键部署 Herdr 或 Luvus 状态插件
ssh <user@host> 'bash -s' < Resources/scripts/setup-herdr.sh
ssh <user@host> 'bash -s' < Resources/scripts/setup-luvus.sh
```

### 6. Vendor 维护
```bash
# 重新编译 Vendor/ghostty (需要 Zig 0.16.x)
./scripts/build-vendor.sh
```

---

## 🔌 Herdr 插件体系 (Herdr Status Title Plugin)

MuH 的多机全景监控依赖于运行在各机器 Herdr 实例上的状态标题同步插件。

### 1. 插件结构与配置
- **插件 ID**：`muh.status-title`
- **源文件目录**：`Resources/herdr-plugin/`
  - `herdr-plugin.toml`：声明插件元数据、启动触发器与订阅的 Herdr 事件（如 `pane.agent_status_changed`、`pane.agent_detected`、`pane.created`、`pane.closed`、`workspace.focused` 等）；
  - `index.js`：Node.js 运行时脚本，调用 Herdr RPC / CLI 获取当前 Agent 列表并格式化输出标题；
  - `README.md`：插件独立说明。

### 2. 状态符号与优先级规则
插件聚合当前机器上所有 Agent 的生命体征，按严重/关注度优先级排序，并截取前 10 个关键状态符号：
- <font color="#f87171">🔴 **`×` (blocked)**</font>：阻塞 / 需要人类介入确认（优先级最高，排在最前）；
- <font color="#4ade80">🟢 **`✓` (done)**</font>：任务完成待查看；
- <font color="#fbbf24">🟡 **`◐` (working)**</font>：正在执行中；
- <font color="#94a3b8">⚪ **`○` (idle)**</font>：空闲就绪；
- <font color="#94a3b8">⚪ **`·` (unknown)**</font>：未知状态。

**格式示例**：`dev2: ×✓✓◐` 或 `prod-node1: idle`。

### 3. PTY OSC 0 标题穿透通道
1. 插件通过 Unix Socket RPC (`client.window_title.set`) 或 Herdr CLI (`herdr terminal title set`) 将格式化后的标题设为 Herdr 终端标题；
2. 标题搭载在标准终端 **OSC 0** 控制序列中流出；
3. SSH 连接将 PTY 输出原样传输到本地 Mac；
4. MuH 的 Ghostty 引擎捕获 `onTitleChanged`，解析主机名与状态符号，驱动侧边栏指示符与智能系统通知。

### 4. 远程安装与同步工作流
- 源码修改必须在 `Resources/herdr-plugin/` 中进行；
- 每次修改后运行 `./scripts/generate-setup-herdr.sh`，脚本会将插件的 TOML 清单和 JS 源码以 Here-Doc 形式自动嵌入到 `Resources/scripts/setup-herdr.sh` 中；
- 用户在新建主机或添加远程服务器时，只需执行 `setup-herdr.sh` 即可完成零依赖免包管理器安装。

---

## 📂 项目结构与模块划分 (Codebase Structure)

```text
MuH/
├── App/                         # 应用入口与全局窗口体系
│   ├── MuHApp.swift             # App 主入口与菜单快捷键定义
│   ├── ContentView.swift        # 主界面容器（侧边栏 + 终端/设置卡片）
│   ├── WindowAccessor.swift     # NSWindow 样式与全屏 safe area 配置
│   └── WindowHelper.swift       # 标题栏双击缩放/最大化与拖拽支持组件
├── Sidebar/                     # 侧边栏与主机列表
│   ├── SidebarView.swift        # 侧边栏根视图（顶部拖拽区、列表、Footer）
│   ├── HostListView.swift       # NSView 列表视图（拖拽排序、重命名、悬浮、空白区交互）
│   ├── SidebarListBridge.swift  # SwiftUI 与 HostListView 的桥接
│   └── SidebarResizeHandle.swift# 侧边栏宽度拖拽调节分割线
├── Terminal/                    # 终端卡片容器
│   ├── TerminalBridge.swift     # SwiftUI 与 TerminalContainerView 桥接
│   └── TerminalContainerView.swift # 维护各 Host 对应的 Ghostty 终端实例与复用
├── Ghostty/                     # libghostty 终端核心封装
│   ├── GhosttyBridge.swift      # libghostty 全局生命周期与回调分发
│   ├── GhosttyTerminalView.swift# 终端 NSView（Metal 渲染、输入事件派发、选词、链接）
│   ├── CopyToastHUD.swift       # 自动复制提示 HUD
│   ├── LinkHintTooltip.swift    # ⌘+Click 链接悬停提示
│   └── ghostty-bridging-header.h# C Bridging Header
├── Models/                      # 数据模型与存储
│   ├── HostItem.swift           # Host 数据结构
│   ├── HostStore.swift          # Host 列表管理与持久化 (UserDefaults)
│   └── HostTitleStore.swift     # PTY 标题缓存与 Agent 状态解析
├── Notifications/               # 智能提醒管理
│   └── NotificationManager.swift# macOS 原生横幅通知与 14 款系统提示音调度
├── Settings/                    # 设置面板
│   ├── SettingsView.swift       # 设置根视图与 Tab 切换
│   ├── SettingsTabBarView.swift # 设置顶部可拖拽 TabBar
│   ├── SettingsConfigStore.swift# Ghostty 配置文件读写与解析
│   ├── ThemeCatalog.swift       # Ghostty 主题目录枚举
│   └── Sections/                # 外观、字体、终端、提醒各个子模块
├── Theme/                       # 设计系统与样式
│   ├── DesignTokens.swift       # 间距、字号、圆角、行高规范 (DT)
│   ├── AppTheme.swift           # 语义化颜色与主题结构
│   ├── ThemeManager.swift       # 主题状态管理与动态刷新
│   └── GhosttyConfigReader.swift# Ghostty 配置解析工具
├── Localization/                # 国际化支持
│   ├── L10n.swift               # 强类型多语言定义
│   ├── LanguageStore.swift      # 语言状态管理
│   └── Localizable.xcstrings    # 中英文 String Catalog
├── Resources/                   # 资源与外部集成
│   ├── herdr-plugin/            # Herdr 状态插件源码 (TOML + JS)
│   ├── scripts/                 # setup-herdr.sh 远程自包含安装脚本
│   └── logo.png                 # 项目 Logo
├── scripts/                     # 自动化构建与代码生成脚本
│   ├── build-vendor.sh          # 编译 libghostty 静态库
│   └── generate-setup-herdr.sh  # 将 herdr-plugin 打包嵌入 setup-herdr.sh
└── Vendor/                      # 静态二进制依赖
    └── ghostty/                 # libghostty.a、头文件与 Ghostty 资源
```

---

## 📐 核心设计原则与编码规范 (Guidelines & Patterns)

1. **工程维护**：
   - 依赖项与编译配置统一在 `project.yml` 中管理。
   - 新增、移动或删除 Swift 文件后，务必运行 `xcodegen generate`。
   - 保持零外部 SPM 依赖，优先使用系统原生 AppKit / SwiftUI 机制。

2. **窗口与交互规范**：
   - MuH 采用无边框全尺寸设计（`.windowStyle(.hiddenTitleBar)` + `fullSizeContentView`）。
   - 为避免与 Ghostty 终端内的文本选择手势冲突，保持 `window.isMovableByWindowBackground = false`。
   - 自定义标题栏、侧边栏顶部、工作区列表空白区域统一使用 `WindowHelper` / `WindowDraggableArea` 提供平滑窗口拖拽与系统级双击缩放/最大化（遵循 `AppleActionOnDoubleClick` 偏好）。
   - 终端内部 (`GhosttyTerminalView`) 拥有独占的鼠标与键盘输入处理，不得被外层手势抢占。

3. **GUI 启动与环境要求**：
   - Dock/Finder 启动时 GUI launchd 环境缺少 `LANG` 与 `TERM`，`Info.plist` 中已通过 `LSEnvironment` 显式注入 `LANG=en_US.UTF-8` 与 `TERM=xterm-256color`，修改启动逻辑时需保留该配置。
   - 打包与发布脚本需确保 App Bundle 权限为 `755/644`，避免 `umask 077` 引起权限异常。

4. **PTY 状态通道规范**：
   - Agent 状态通过标准终端 OSC 0 标题传递（例如 `[×]`, `[✓]`, `[◐]` 等 Herdr 状态前缀）。
   - `HostTitleStore` 负责去重与抑制会话初始冗余提示，`NotificationManager` 负责在状态演变（阻塞 / 全部完成）时调度系统横幅与音效。

5. **设计规范 (Design Tokens)**：
   - UI 样式严格遵循 `DT` (`DesignTokens.swift`) 中的间距、圆角与字体规范。
   - 侧边栏宽度支持 150pt ~ 360pt 拖拽调整，持久化保存于 `muh.sidebar.width`。
