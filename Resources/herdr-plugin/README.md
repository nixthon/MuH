# MuH Status Title Plugin for Herdr

Herdr 插件：实时聚合当前 Herdr 会话中的 Agent 状态指示符（1 个符号 = 1 个存活 Agent，`×` 阻塞、`✓` 完成、`◐` 运行中、`○` 待命空闲），并按严重优先级排序截断（最多 10 个），通过标准终端 OSC 0 窗口标题回传给 MuH（当 0 个 Agent 存活时输出 `dev2: idle`）。

## 特性

- **零网络开销**：无需开启任何独立 HTTP / WebSocket 服务或额外端口，直接复用 PTY / SSH 数据流。
- **智能排序**：关键状态（阻塞需要人工介入、完成待查看）优先前置排在最左侧。
- **跨平台**：支持 macOS / Linux。

## 安装与启用

### 自动安装（推荐）
在目标机器上直接运行：
```bash
bash setup-herdr.sh
```
或通过 SSH 远程初始化：
```bash
ssh <user@host> 'bash -s' < setup-herdr.sh
```

### 手动安装
```bash
herdr plugin link /path/to/MuH/Resources/herdr-plugin
```

验证安装：
```bash
herdr plugin list
```
输出应包含 `muh.status-title` 且处于 `enabled` 状态。

## 测试

手动触发一次状态同步：
```bash
herdr plugin action invoke muh.status-title.sync
```
