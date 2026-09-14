# MuH (Multiplexing Host Manager)

<p align="center">
  <b>English</b> | <a href="README_zh.md">简体中文</a>
</p>

<p align="center">
  <strong>Ultra-lightweight, high-performance macOS native multi-host terminal manager for AI Agent workflows</strong><br>
  <em>Tightly integrated with Herdr & Luvus to monitor vitals and alerts across dozens of AI agents on multiple machines</em>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0+-blue?logo=apple" alt="Platform" />
  <img src="https://img.shields.io/badge/Terminal%20Engine-Ghostty%20(libghostty)-orange" alt="Ghostty Engine" />
  <img src="https://img.shields.io/badge/Multiplexer-Herdr%20%7C%20Luvus-green" alt="Multiplexer Integration" />
  <img src="https://img.shields.io/badge/Version-v0.1.6-brightgreen" alt="Version" />
  <img src="https://img.shields.io/badge/License-MIT-purple" alt="License" />
</p>

<p align="center">
  <img src="docs/screenshot.png" alt="MuH Interface Preview" width="880" style="border-radius: 8px; box-shadow: 0 8px 24px rgba(0,0,0,0.2);" />
</p>

---

## 💡 Why MuH?

In the era of **Agentic Coding**, developers frequently orchestrate multiple AI agents running in parallel across **multiple machines** (e.g., local Mac for frontend, a remote GPU server `dev1` fine-tuning models, and a cloud VPS `dev2` executing integration test suites).

**Pain points of existing developer toolchains:**
- **Single-Host Multiplexers (Tmux / standalone Herdr / Luvus)**: Scoped strictly to a single machine. You are forced to juggle disparate terminal tabs and manually guess which machine's agent is blocked on human input or finished its work.
- **Traditional GUI Terminals (iTerm2 / Warp / Ghostty)**: Lack semantic agent awareness. The sidebar displays raw process names or hostnames, giving zero visibility into agent vitals.
- **Web Dashboards & Observability Consoles**: Require exposing ports on every remote host, configuring reverse proxies, and setting up auth tunnels. Heavy maintenance overhead and completely detached from local, keyboard-driven terminal workflows.

**MuH provides a brand-new paradigm:**
> **Concept: 1 Host = 1 Embedded Ghostty Terminal running Herdr or Luvus.**

MuH serves as the top-level macOS host container. Through an ultra-simple **PTY terminal title stream (OSC 0)**, agent vitals penetrate SSH tunnels naturally and aggregate into the left sidebar in real time, backed by native macOS banner notifications and alert chimes!

---

## ✨ Key Features

### 1. 🌐 Multi-Machine Agent Overview (Real-Time Vitals)
* **Number of Symbols = Number of Living Agents**: The sidebar renders live vital signs for each host, strictly ordered by semantic priority:
  * 🔴 **`×`** **Blocked / Requires Human Confirmation** (`blocked`, prioritized first)
  * 🟢 **`✓`** **Completed & Pending Review** (`done`)
  * 🟡 **`◐`** **Actively Working** (`working`)
  * 🟢 **`○`** **Living Agent on Ready/Idle Standby** (`idle`)
  * When **0 agents are alive** on a host, MuH displays a clean `hostname: idle` status (zero symbols).
* **Click-to-Focus**: Selecting any host instantly and smoothly brings up that machine's full terminal workspace.

### 2. ⚡️ Pure PTY Penetration with Zero Network Configuration
* Status payloads travel over standard terminal window title escape sequences (OSC 0).
* **Zero extra open ports, zero reverse proxies, and automatic SSH tunneling**. If SSH connects, agent vitals stream back to your Mac with millisecond latency.

### 3. 🔌 Deep Integration with Herdr & Luvus Multiplexers
* **Clean separation of concerns**: MuH manages top-level **multi-host orchestration and macOS-native alerting**; single-machine pane/tab scheduling and agent lifecycle monitoring are delegated to [Herdr](https://github.com/herdr/herdr) or [Luvus](https://github.com/RizRiyz/luvus) (0.13.1+).
* **Native support for modern agent runtimes**: Includes status synchronization plugins with lifecycle-safe heartbeats and automatic dead-agent cleanup.

### 4. 🧭 Explicit Host Lifecycle Management
* **Session Hosts (SSH / Herdr / Luvus)**:
  * Left-click selects the host without triggering heavy background SSH connections.
  * Connect and disconnect lifecycles are explicitly controlled via the right-click context menu.
  * Disconnected state frees underlying resources and displays an elegant centered placeholder.
* **Local Shell Hosts**:
  * Instant click-to-launch behavior, with a right-click "Restart" option to quickly recover dead shells.

### 5. 🔔 Native macOS Notifications & Sound Alerts
* **Event-Driven Alerts**: Whenever a remote agent enters `blocked` (🔴 `×`) or all tasks are `done` (🟢 `✓`), MuH dispatches native macOS banners and plays distinct audio alerts.
* **Click-to-Jump**: Clicking a notification from any full-screen app or desktop immediately activates MuH and focuses the exact source host.
* **14 Built-In Audio Chimes**: Includes classic macOS sounds (`Glass`, `Ping`, `Hero`, `Pop`, `Bottle`, etc.) with one-click preview in Settings.

### 6. 🚀 Peak Performance & Native macOS Craftsmanship
* **GPU-Accelerated Ghostty Core**: Embedded `libghostty` rendering engine delivers buttery-smooth, hardware-accelerated terminal graphics.
* **Draggable & Resizable Sidebar**: Width freely resizable from 150pt to 360pt, with double-click reset and persistent geometry preferences.
* **Card-Based Visual Layout**: Terminal render canvases are wrapped in distinct cards with polished borders, subtle shadows, and Menlotype monospace font alignment.
* **Zero SPM Dependencies**: Pure Swift / SwiftUI + XcodeGen architecture for sub-second clean compilation.

---

## 🛠 Quick Start

### 1. Download & Install

Download the latest pre-built binary `MuH-v0.1.6-macOS.zip` from [Releases](https://github.com/tangxijin/MuH/releases):

```bash
# Extract and move to Applications
unzip MuH-v0.1.6-macOS.zip
mv MuH.app /Applications/
```

> **Gatekeeper Notice for First Launch**:
> If macOS displays an unidentified developer warning:
> Go to **System Settings** ➔ **Privacy & Security** ➔ Click **Open Anyway**, or run:
> ```bash
> xattr -cr /Applications/MuH.app
> ```

---

### 2. One-Command Remote Setup (Status Sync Plugin)

MuH includes self-contained remote bootstrap scripts requiring no package manager setup:

#### Option A: Using Herdr
```bash
ssh <user@host> 'bash -s' < Resources/scripts/setup-herdr.sh
```

#### Option B: Using Luvus
```bash
ssh <user@host> 'bash -s' < Resources/scripts/setup-luvus.sh
```

*(You can also click "Copy Setup Command" in MuH Settings (`⌘,`) ➔ Notifications)*

---

### 3. Build from Source (Developers)

```bash
# 1. Clone repository
git clone https://github.com/tangxijin/MuH.git
cd MuH

# 2. Ensure XcodeGen and compatible Zig 0.16.x are installed (first time only)
./scripts/build-vendor.sh

# 3. Generate project, compile Debug build, and run
./restart.sh
```

---

## ⌨️ Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `⌘ + ,` | Open / close Settings |
| `⌘ + N` | Create new Host (defaults to `~` local shell) |
| `⌘ + 1` ~ `⌘ + 9` | Fast-switch to Host 1 through 9 |
| `⌘ + C` / `⌘ + V` | Terminal copy / paste (copy-on-select supported with HUD toast) |
| `⌘ + A` | Select all terminal text |
| `⌘ + Click` | Open hovered URLs directly in browser |

---

## 🙏 Acknowledgments

MuH is inspired by the open-source project **[mux0](https://github.com/10xChengTu/mux0)** and adopts core UI design patterns and Ghostty C Bridging structures from it. Heartfelt thanks to the creators and contributors of `mux0`!

Building on that foundation, MuH introduces a new paradigm for multi-machine AI agent workflows:
- Decouples local pane/tab multiplexing to **Herdr** and **Luvus**;
- Pioneers pure PTY OSC 0 escape code aggregation for cross-host agent vitals;
- Integrates native macOS notification dispatching, audio chime management, host lifecycle controls, and zero-dependency remote bootstrap tooling.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).
