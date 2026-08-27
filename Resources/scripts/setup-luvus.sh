#!/usr/bin/env bash
# ==============================================================================
# MuH / Luvus Integration Initializer
# 
# Usage:
#   Local:   bash setup-luvus.sh
#   Remote:  ssh <user@host> 'bash -s' < setup-luvus.sh
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 0. Ensure Full PATH in Non-interactive and Interactive Shells
# ------------------------------------------------------------------------------
if [ -f "$HOME/.profile" ]; then (source "$HOME/.profile" 2>/dev/null) && source "$HOME/.profile" 2>/dev/null || true; fi
if [ -f "$HOME/.bash_profile" ]; then (source "$HOME/.bash_profile" 2>/dev/null) && source "$HOME/.bash_profile" 2>/dev/null || true; fi
if [ -f "$HOME/.bashrc" ]; then (source "$HOME/.bashrc" 2>/dev/null) && source "$HOME/.bashrc" 2>/dev/null || true; fi
if [ -f "$HOME/.zshenv" ]; then (source "$HOME/.zshenv" 2>/dev/null) && source "$HOME/.zshenv" 2>/dev/null || true; fi

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/bin:/usr/local/bin:$HOME/.pixi/bin:$HOME/.pixi/envs/default/bin:$HOME/.pixi/envs/nodejs/bin:$HOME/.asdf/shims:$HOME/.fnm/current/bin:$PATH"

# Probe luvus binary location
probe_luvus() {
    if command -v luvus >/dev/null 2>&1; then
        command -v luvus
        return 0
    fi
    for candidate in "$HOME/.local/bin/luvus" "$HOME/.cargo/bin/luvus" "$HOME/bin/luvus" "/usr/local/bin/luvus" "/opt/homebrew/bin/luvus"; do
        if [ -x "$candidate" ]; then
            export PATH="$(dirname "$candidate"):$PATH"
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

# Probe node binary location
probe_node() {
    if command -v node >/dev/null 2>&1; then
        command -v node
        return 0
    fi
    for candidate in \
        "$HOME/.pixi/bin/node" \
        "$HOME/.pixi/envs/nodejs/bin/node" \
        "$HOME/.pixi/envs/default/bin/node" \
        "$HOME/.nvm/versions/node"/*"/bin/node" \
        "$HOME/.fnm/current/bin/node" \
        "$HOME/.asdf/shims/node" \
        "$HOME/.local/bin/node" \
        "/usr/local/bin/node" \
        "/opt/homebrew/bin/node"; do
        if [ -x "$candidate" ]; then
            export PATH="$(dirname "$candidate"):$PATH"
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_CYAN='\033[0;36m'
COLOR_BOLD='\033[1m'
COLOR_NC='\033[0m' # No Color

info()  { printf "${COLOR_CYAN}[INFO]${COLOR_NC} %s\n" "$*"; }
ok()    { printf "${COLOR_GREEN}[OK]${COLOR_NC} %s\n" "$*"; }
warn()  { printf "${COLOR_YELLOW}[WARN]${COLOR_NC} %s\n" "$*"; }
err()   { printf "${COLOR_RED}[ERROR]${COLOR_NC} %s\n" "$*"; }

printf "\n${COLOR_BOLD}========================================${COLOR_NC}\n"
printf "${COLOR_BOLD}   MuH ➔ Luvus Agent Status Initializer  ${COLOR_NC}\n"
printf "${COLOR_BOLD}========================================${COLOR_NC}\n\n"

# ------------------------------------------------------------------------------
# 1. Environment & Dependency Checks (Auto-install/Upgrade Luvus to v0.13.1)
# ------------------------------------------------------------------------------
info "Checking environment dependencies..."

TARGET_LUVUS_VERSION="0.13.1"
LUVUS_BIN=$(probe_luvus || true)

need_install=0
if [ -z "$LUVUS_BIN" ]; then
    need_install=1
else
    CURRENT_VERSION=$("$LUVUS_BIN" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "0.0.0")
    if [ "$CURRENT_VERSION" != "$TARGET_LUVUS_VERSION" ]; then
        info "Luvus version is v${CURRENT_VERSION}. Target is v${TARGET_LUVUS_VERSION}."
        need_install=1
    fi
fi

if [ "$need_install" = "1" ]; then
    info "Installing / Upgrading Luvus to v${TARGET_LUVUS_VERSION} via official installer..."
    export LUVUS_VERSION="v${TARGET_LUVUS_VERSION}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://luvus.dev/install.sh | sh
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- https://luvus.dev/install.sh | sh
    else
        err "Neither curl nor wget found! Please install curl or wget first."
        exit 1
    fi

    # Re-probe after installation
    export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/bin:/usr/local/bin:$PATH"
    LUVUS_BIN=$(probe_luvus || true)
    if [ -z "$LUVUS_BIN" ]; then
        err "Luvus installation completed but executable could not be located on PATH."
        exit 1
    fi
    ok "Successfully installed/upgraded Luvus!"
fi

LUVUS_VERSION=$("$LUVUS_BIN" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")
ok "Found Luvus at $LUVUS_BIN (v${LUVUS_VERSION})"

# ------------------------------------------------------------------------------
# 2. Reinforce Non-Interactive SSH Compatibility & Shell PATH Injection (bash/zsh)
# ------------------------------------------------------------------------------
info "Configuring non-interactive shell PATH compatibility..."

mkdir -p "$HOME/.local/bin"
if [ -d "$HOME/.cargo/bin" ] && [ "$LUVUS_BIN" != "$HOME/.cargo/bin/luvus" ]; then
    ln -sf "$LUVUS_BIN" "$HOME/.cargo/bin/luvus" 2>/dev/null || true
fi
if [ -d "$HOME/bin" ] && [ "$LUVUS_BIN" != "$HOME/bin/luvus" ]; then
    ln -sf "$LUVUS_BIN" "$HOME/bin/luvus" 2>/dev/null || true
fi

# Ensure all relevant shell rc files export the full toolchain PATH
PATH_INJECTION='export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/bin:/usr/local/bin:$HOME/.pixi/bin:$HOME/.pixi/envs/default/bin:$HOME/.pixi/envs/nodejs/bin:$HOME/.asdf/shims:$HOME/.fnm/current/bin:$PATH"'

ensure_shell_path() {
    local rcfile="$1"
    if [ ! -f "$rcfile" ]; then
        touch "$rcfile" 2>/dev/null || return 0
    fi
    if ! grep -Fq '.pixi/bin' "$rcfile" 2>/dev/null; then
        printf '\n# Added by MuH / Luvus installer\n%s\n' "$PATH_INJECTION" >> "$rcfile"
        ok "Injected toolchain PATH into $rcfile"
    else
        ok "PATH already configured in $rcfile"
    fi
}

# Bash & POSIX shells
ensure_shell_path "$HOME/.bashrc"
ensure_shell_path "$HOME/.profile"
[ -f "$HOME/.bash_profile" ] && ensure_shell_path "$HOME/.bash_profile"
[ -f "$HOME/.bashrc.local" ] && ensure_shell_path "$HOME/.bashrc.local"

# Zsh (critical: .zshenv is read for all non-interactive SSH commands)
ensure_shell_path "$HOME/.zshenv"
[ -f "$HOME/.zshrc" ] && ensure_shell_path "$HOME/.zshrc"

# Check Node.js
NODE_BIN=$(probe_node || true)
if [ -z "$NODE_BIN" ]; then
    err "Node.js is not installed or not found on PATH!"
    printf "The MuH status module requires Node.js runtime (v18+ recommended).\n\n"
    exit 1
fi

NODE_VERSION=$("$NODE_BIN" -v 2>&1 || echo "unknown")
ok "Found Node.js at $NODE_BIN (${NODE_VERSION})"

# ------------------------------------------------------------------------------
# 3. Configure ~/.config/luvus/config.toml & Agent Detection Manifests
# ------------------------------------------------------------------------------
info "Configuring Luvus settings and agent manifests..."

LUVUS_CONFIG_DIR="$HOME/.config/luvus"
LUVUS_CONFIG_FILE="$LUVUS_CONFIG_DIR/config.toml"
LUVUS_MANIFESTS_DIR="$HOME/.luvus/manifests"

mkdir -p "$LUVUS_CONFIG_DIR" "$LUVUS_MANIFESTS_DIR"

if [ -f "$LUVUS_CONFIG_FILE" ]; then
    ok "Luvus config file exists at $LUVUS_CONFIG_FILE"
else
    cat << 'EOF' > "$LUVUS_CONFIG_FILE"
[layout]
show_titles = true
agent_title = false
files_show_hidden = false
EOF
    ok "Created default ~/.config/luvus/config.toml"
fi

# Deploy Pi agent detection manifest
# BEGIN GENERATED PI MANIFEST
cat << 'MUH_PI_MANIFEST' > "$LUVUS_MANIFESTS_DIR/pi.toml"
# MuH Agent Detection Manifest for Pi (pi-coding-agent)
# VERSION: 1.0.0
# Placed in ~/.luvus/manifests/pi.toml so Luvus can accurately identify
# Pi coding agent instances and monitor their working/blocked/idle states.

agent = "pi"

[identity]
distinct = [
  "pi-coding-agent",
  "@earendil-works/pi-coding-agent",
  "pi-subagents",
  "PI_CODING_AGENT",
  "PI_SESSION_DIR"
]
ambiguous = ["pi"]

# ── Working State Rules ───────────────────────────────────────────────────────
# When Pi is streaming tokens, thinking, running tools, or shows interrupt hints.

[[rule]]
state = "working"
priority = 200
region = "screen"
any = [
  "ctrl+c to interrupt",
  "ctrl-c to interrupt",
  "ctrl+c to cancel",
  "ctrl-c to cancel",
  "esc to cancel",
  "esc to interrupt",
  "thinking...",
  "thinking ("
]

# Animated spinners during inference / tool execution
[[rule]]
state = "working"
priority = 190
region = "screen"
any = [
  "◐", "◑", "◒", "◓",
  "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"
]

# ── Blocked State Rules ───────────────────────────────────────────────────────
# When Pi requires human confirmation, tool approval, or user question answers.

[[rule]]
state = "blocked"
priority = 300
region = "screen"
any = [
  "select an option",
  "do you want to proceed",
  "(type to add feedback)",
  "press enter to continue",
  "confirm? [y/n]",
  "allow this command",
  "approve tool execution"
]
MUH_PI_MANIFEST
# END GENERATED PI MANIFEST
ok "Installed Pi agent detection manifest to $LUVUS_MANIFESTS_DIR/pi.toml"

# Deploy Pi native extension for Luvus if ~/.pi/agent/extensions exists or pi is installed
PI_EXTENSIONS_DIR="$HOME/.pi/agent/extensions"
if [ -d "$HOME/.pi" ] || command -v pi >/dev/null 2>&1; then
    mkdir -p "$PI_EXTENSIONS_DIR"
    # BEGIN GENERATED PI EXTENSION
cat << 'MUH_PI_EXTENSION' > "$PI_EXTENSIONS_DIR/luvus-agent-state.ts"
// installed by MuH / Luvus Integration
// LUVUS_INTEGRATION_ID=pi
// LUVUS_INTEGRATION_VERSION=1.3.1
// @ts-nocheck

import net from "node:net";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";

const LUVUS_ENV = process.env.LUVUS_ENV;
const rawSocketPath = process.env.LUVUS_SOCKET_PATH;
const paneId = process.env.LUVUS_PANE_ID;
const rawLuvusBin = process.env.LUVUS_BIN_PATH;
const source = "pi";

const LEASE_TTL_SECONDS = 45;
const HEARTBEAT_INTERVAL_MS = 15000;

type AgentState = "working" | "blocked" | "idle";

function enabled(): boolean {
  return LUVUS_ENV === "1" && !!paneId;
}

function resolveLuvusBin(): string {
  const configured = rawLuvusBin?.trim();
  if (!configured) return "luvus";

  // Linux appends this marker to /proc/<pid>/exe after an in-place upgrade.
  // The replacement executable remains available at the original path.
  const normalized = configured.replace(/ \(deleted\)$/, "");
  try {
    fs.accessSync(normalized, fs.constants.X_OK);
    return normalized;
  } catch {
    return "luvus";
  }
}

const luvusBin = resolveLuvusBin();

function resolveSocketPath(): string | null {
  if (rawSocketPath && fs.existsSync(rawSocketPath)) {
    return rawSocketPath;
  }

  const home = os.homedir();
  const candidates = [
    path.join(home, ".luvus", "luvus.sock"),
    path.join(home, ".local", "share", "luvus", "luvus.sock"),
    path.join("/tmp", `luvus-${process.getuid?.() || 1000}`, "luvus.sock"),
    path.join("/tmp", "luvus.sock"),
  ];

  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

function sendSocketRequest(
  socketPath: string,
  request: Record<string, unknown>,
  timeoutMs: number,
): Promise<boolean> {
  return new Promise((resolve) => {
    let settled = false;
    let buffer = "";

    const socket = net.createConnection(socketPath);
    const timeout = setTimeout(() => finish(false), timeoutMs);

    function finish(delivered: boolean): void {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      socket.destroy();
      resolve(delivered);
    }

    socket.on("error", () => finish(false));
    socket.on("connect", () => socket.write(`${JSON.stringify(request)}\n`));
    socket.on("data", (chunk) => {
      buffer += chunk.toString();
      const newline = buffer.indexOf("\n");
      if (newline < 0) return;

      try {
        const response = JSON.parse(buffer.slice(0, newline));
        finish(response?.id === request.id && !response?.error);
      } catch {
        finish(false);
      }
    });
    socket.on("end", () => finish(false));
  });
}

async function sendRequest(request: Record<string, unknown>): Promise<boolean> {
  const socketPath = resolveSocketPath();
  if (!socketPath) return false;
  if (await sendSocketRequest(socketPath, request, 500)) return true;
  return sendSocketRequest(socketPath, request, 1500);
}

function spawnDetached(args: string[]): void {
  try {
    const child = spawn(luvusBin, args, { stdio: "ignore", detached: true });
    // spawn() reports lookup/exec failures asynchronously, outside try/catch.
    child.once("error", () => {});
    child.unref();
  } catch {}
}

function sendCliReport(state: AgentState, message?: string): void {
  const args = [
    "agent", "report", paneId!,
    "--source", source,
    "--kind", "pi",
    "--status", state,
    "--ttl", String(LEASE_TTL_SECONDS),
  ];
  if (message) args.push("--message", message);
  spawnDetached(args);
}

function sendCliRelease(): void {
  spawnDetached(["agent", "release", paneId!, "--source", source]);
}

export default function (pi: any) {
  if (!enabled()) return;

  // All mutable state is instance-local. Reloaded extension instances must not
  // share timers or queues with the runtime being shut down.
  let rootSession = false;
  let agentActive = false;
  let blockedCount = 0;
  let blockedMessage: string | undefined;
  let currentSessionId: string | undefined;
  let lastState: AgentState | undefined;
  let lastMessage: string | undefined;
  let heartbeatTimer: ReturnType<typeof setInterval> | undefined;
  let requestSequence = Date.now() * 1000;
  let reportChain: Promise<void> = Promise.resolve();

  function nextRequestSequence(): number {
    requestSequence += 1;
    return requestSequence;
  }

  function updateSessionRef(ctx: any): void {
    try {
      const id = ctx?.sessionManager?.getSessionId?.();
      currentSessionId = typeof id === "string" && id.length > 0 ? id : undefined;
    } catch {
      currentSessionId = undefined;
    }
  }

  async function sendReport(
    state: AgentState,
    message: string | undefined,
    requestId: number,
  ): Promise<void> {
    const delivered = await sendRequest({
      id: `pi:report:${paneId}:${requestId}`,
      method: "agent.report",
      params: {
        pane: paneId,
        source,
        agent: "pi",
        status: state,
        ttl_s: LEASE_TTL_SECONDS,
        message,
        session: currentSessionId,
      },
    });

    if (!delivered) sendCliReport(state, message);
  }

  function queueReport(state: AgentState, message?: string): Promise<void> {
    const requestId = nextRequestSequence();
    reportChain = reportChain
      .catch(() => {})
      .then(() => sendReport(state, message, requestId));
    return reportChain;
  }

  function desiredState(): { state: AgentState; message?: string } {
    if (blockedCount > 0) {
      return { state: "blocked", message: blockedMessage };
    }
    return { state: agentActive ? "working" : "idle" };
  }

  function publishState(force = false): Promise<void> {
    if (!rootSession) return Promise.resolve();

    const next = desiredState();
    if (!force && next.state === lastState && next.message === lastMessage) {
      return Promise.resolve();
    }

    lastState = next.state;
    lastMessage = next.message;
    return queueReport(next.state, next.message);
  }

  function stopHeartbeat(): void {
    if (!heartbeatTimer) return;
    clearInterval(heartbeatTimer);
    heartbeatTimer = undefined;
  }

  function startHeartbeat(): void {
    stopHeartbeat();
    heartbeatTimer = setInterval(() => {
      void publishState(true);
    }, HEARTBEAT_INTERVAL_MS);
  }

  async function releaseState(): Promise<void> {
    const requestId = `pi:release:${paneId}:${Date.now()}`;
    const delivered = await sendRequest({
      id: requestId,
      method: "agent.release",
      params: { pane: paneId, source },
    });
    if (!delivered) sendCliRelease();
  }

  pi.events?.on?.("herdr:blocked", (data: any) => {
    if (!rootSession) return;

    if (!data?.active) {
      blockedCount = Math.max(0, blockedCount - 1);
      if (blockedCount === 0) blockedMessage = undefined;
    } else {
      blockedCount += 1;
      blockedMessage = data.label || "Awaiting user confirmation";
    }
    void publishState();
  });

  pi.on("session_start", async (_event: any, ctx: any) => {
    // Headless Pi children inherit the pane environment. Only the interactive
    // root owns this pane's Luvus authority.
    if (ctx?.mode !== "tui") return;

    rootSession = true;
    updateSessionRef(ctx);
    agentActive = ctx?.isIdle?.() === false;
    startHeartbeat();
    await publishState(true);
  });

  pi.on("before_agent_start", async (_event: any, ctx: any) => {
    if (!rootSession) return;
    updateSessionRef(ctx);
    agentActive = true;
    await publishState();
  });

  pi.on("agent_start", async (_event: any, ctx: any) => {
    if (!rootSession) return;
    updateSessionRef(ctx);
    agentActive = true;
    await publishState();
  });

  pi.on("agent_settled", async (_event: any, ctx: any) => {
    if (!rootSession || ctx?.isIdle?.() !== true) return;
    updateSessionRef(ctx);
    agentActive = false;
    await publishState();
  });

  pi.on("session_shutdown", async (event: any) => {
    if (!rootSession) return;

    rootSession = false;
    stopHeartbeat();
    await reportChain.catch(() => {});

    // Reload/session replacement immediately establishes a fresh authority.
    // Explicit release is only needed when the interactive Pi really exits.
    if (event?.reason === "quit") {
      await releaseState();
    }
  });
}
MUH_PI_EXTENSION
    # END GENERATED PI EXTENSION
    ok "Installed Pi native extension to $PI_EXTENSIONS_DIR/luvus-agent-state.ts"
fi

# ------------------------------------------------------------------------------
# 4. Deploy MuH Status-Title Module
# ------------------------------------------------------------------------------
info "Installing MuH status-title module..."

MODULE_DIR="$LUVUS_CONFIG_DIR/modules/status-title"
mkdir -p "$MODULE_DIR"

# BEGIN GENERATED MODULE MANIFEST
cat << 'MUH_MODULE_MANIFEST' > "$MODULE_DIR/luvus-module.toml"
id = "muh.status-title"
name = "MuH Status Title"
version = "0.1.6"
min_luvus_version = "0.8.3"
description = "Sync aggregated agent status indicators to outer terminal window title for MuH"
platforms = ["linux", "macos", "windows"]

[[startup]]
command = ["bash", "run.sh"]

[[events]]
on = "pane.agent_status_changed"
command = ["bash", "run.sh"]

[[events]]
on = "agent.authority_reported"
command = ["bash", "run.sh"]

[[events]]
on = "agent.authority_released"
command = ["bash", "run.sh"]

[[events]]
on = "pane.created"
command = ["bash", "run.sh"]

[[events]]
on = "pane.closed"
command = ["bash", "run.sh"]

[[events]]
on = "pane.moved"
command = ["bash", "run.sh"]

[[events]]
on = "pane.focused"
command = ["bash", "run.sh"]

[[events]]
on = "pane.renamed"
command = ["bash", "run.sh"]

[[events]]
on = "tab.created"
command = ["bash", "run.sh"]

[[events]]
on = "tab.closed"
command = ["bash", "run.sh"]

[[events]]
on = "tab.moved"
command = ["bash", "run.sh"]

[[events]]
on = "tab.renamed"
command = ["bash", "run.sh"]

[[events]]
on = "workspace.created"
command = ["bash", "run.sh"]

[[events]]
on = "workspace.closed"
command = ["bash", "run.sh"]

[[events]]
on = "workspace.moved"
command = ["bash", "run.sh"]

[[events]]
on = "session.created"
command = ["bash", "run.sh"]

[[events]]
on = "session.updated"
command = ["bash", "run.sh"]

[[actions]]
id = "sync"
title = "Sync status title"
contexts = ["workspace"]
command = ["bash", "run.sh"]
MUH_MODULE_MANIFEST
# END GENERATED MODULE MANIFEST

# BEGIN GENERATED MODULE RUNNER
cat << 'MUH_MODULE_RUNNER' > "$MODULE_DIR/run.sh"
#!/usr/bin/env bash
# ==============================================================================
# MuH Status Title Runner for Luvus
# Robust launcher that probes Node.js and full user PATH in minimal environments.
# ==============================================================================

set -euo pipefail

# Ensure standard user paths are present even when spawned with minimal environment
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/bin:/usr/local/bin:$HOME/.pixi/bin:$HOME/.pixi/envs/nodejs/bin:$HOME/.pixi/envs/default/bin:$HOME/.asdf/shims:$HOME/.fnm/current/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INDEX_JS="$SCRIPT_DIR/index.js"

# Probe node binary
NODE_BIN=""
if command -v node >/dev/null 2>&1; then
    NODE_BIN="$(command -v node)"
else
    for candidate in \
        "$HOME/.pixi/bin/node" \
        "$HOME/.pixi/envs/nodejs/bin/node" \
        "$HOME/.local/bin/node" \
        "/usr/local/bin/node" \
        "/opt/homebrew/bin/node" \
        "$HOME/.nvm/versions/node"/*"/bin/node" \
        "$HOME/.fnm/current/bin/node" \
        "$HOME/.asdf/shims/node"; do
        if [ -x "$candidate" ]; then
            NODE_BIN="$candidate"
            break
        fi
    done
fi

if [ -n "$NODE_BIN" ]; then
    exec "$NODE_BIN" "$INDEX_JS" "$@"
else
    echo "[muh.status-title] node runtime not found" >&2
    exit 1
fi
MUH_MODULE_RUNNER
# END GENERATED MODULE RUNNER

# BEGIN GENERATED MODULE INDEX
cat << 'MUH_MODULE_INDEX' > "$MODULE_DIR/index.js"
#!/usr/bin/env node

/**
 * MuH Status Title Module for Luvus
 *
 * Aggregates agent status in the active Luvus session, sorts them by priority
 * (Blocked and Done first, Working and Idle last), limits to 10 indicators, and writes
 * the formatted title (e.g. "dev2: ×✓✓◐") to the outer terminal title via OSC 0 directly to the host TTY.
 */

const { execSync, spawnSync } = require('node:child_process');
const os = require('node:os');
const net = require('node:net');
const path = require('node:path');
const fs = require('node:fs');

const MODULE_VERSION = '0.1.6';

const STATUS_CONFIG = {
  blocked: { weight: 1, symbol: '×' }, // 🔴 阻塞 / 需要人类介入确认
  done:    { weight: 2, symbol: '✓' }, // 🟢 任务完成待查看
  working: { weight: 3, symbol: '◐' }, // 🟡 正在执行中
  idle:    { weight: 4, symbol: '○' }, // 🟢 存活空闲待命 (绿色圆圈)
  unknown: { weight: 5, symbol: '·' }, // 未知状态
};

const MAX_INDICATORS = 10;

/**
 * Formats a list of agent status strings into a concise symbols string.
 * - blocked (×): 🔴 阻塞需确认
 * - done (✓): 🟢 完成待查看
 * - working (◐): 🟡 正在执行
 * - idle (○): 🟢 存活空闲待命 (绿色圆圈)
 * 
 * Rules:
 * - Each symbol represents one living agent in the session.
 * - When agent count is 0 (no agents in session), returns '' so title formats as "hostname: idle" (zero symbols).
 * - When agents are present, sorted by priority (blocked > done > working > idle) and capped at MAX_INDICATORS (10).
 * 
 * @param {string[]} statuses Array of agent status strings (e.g. ['blocked', 'working', 'done', 'idle'])
 * @returns {string} Combined symbols string (e.g. "×✓◐○")
 */
function formatAgentStatusSymbols(statuses) {
  if (!statuses || statuses.length === 0) {
    return '';
  }

  // 1. 按照优先级排序：Blocked(1) > Done(2) > Working(3) > Idle(4) > Unknown(5)
  const sorted = statuses.slice().sort((a, b) => {
    const wa = STATUS_CONFIG[a]?.weight ?? 99;
    const wb = STATUS_CONFIG[b]?.weight ?? 99;
    return wa - wb;
  });

  // 2. 截取前 MAX_INDICATORS 个最关键的状态符号
  const top = sorted.slice(0, MAX_INDICATORS);

  // 3. 映射为对应符号并拼接
  return top.map(status => STATUS_CONFIG[status]?.symbol ?? '·').join('');
}

/**
 * Resolves short hostname (e.g. "dev2" from "dev2.internal.net").
 */
function getHostname() {
  const raw = process.env.LUVUS_HOSTNAME || process.env.HERDR_HOSTNAME || os.hostname() || 'luvus';
  return raw.split('.')[0];
}

/**
 * Probe default Luvus Unix socket path if not provided in environment.
 */
function resolveSocketPath() {
  if (process.env.LUVUS_SOCKET_PATH && fs.existsSync(process.env.LUVUS_SOCKET_PATH)) {
    return process.env.LUVUS_SOCKET_PATH;
  }
  const home = os.homedir();
  const candidates = [
    path.join(home, '.luvus', 'luvus.sock'),
    path.join(home, '.luvus', 'luvus-client.sock'),
    path.join(home, '.local', 'share', 'luvus', 'luvus.sock'),
    path.join(home, '.config', 'luvus', 'luvus.sock'),
    path.join('/tmp', `luvus-${process.getuid?.() || 1000}`, 'luvus.sock'),
    path.join('/tmp', 'luvus.sock'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return null;
}

/**
 * Resolves a usable Luvus executable after an in-place Linux upgrade.
 */
function resolveLuvusBin(configured = process.env.LUVUS_BIN_PATH) {
  const candidate = configured?.trim();
  if (!candidate) return 'luvus';

  const normalized = candidate.replace(/ \(deleted\)$/, '');
  try {
    fs.accessSync(normalized, fs.constants.X_OK);
    return normalized;
  } catch (_) {
    return 'luvus';
  }
}

/**
 * Checks if a command line string represents an interactive Luvus TUI client process.
 * Strictly excludes SSH clients, remote tunnels, wrappers, shells, editors, daemons,
 * and one-off subcommands (e.g. `ssh -t host luvus`, `luvus server`, `luvus module ...`).
 *
 * @param {string} cmd Full command line string from ps
 * @param {string} [currentSession] Optional targeted session name (e.g. "default", "docs")
 * @returns {boolean}
 */
function isInteractiveLuvusClient(cmd, currentSession = '') {
  if (!cmd || typeof cmd !== 'string') return false;

  const trimmed = cmd.trim();
  if (!trimmed) return false;

  const tokens = trimmed.split(/\s+/);
  if (tokens.length === 0) return false;

  const binPath = tokens[0];
  const binName = path.basename(binPath).toLowerCase();

  // 1. Strictly exclude SSH clients, remote wrappers, editors, interpreters, shells
  const forbiddenBins = new Set([
    'ssh', 'sshd', 'mosh', 'mosh-client', 'mosh-server', 'scp', 'sftp',
    'grep', 'egrep', 'rg', 'ag', 'ps', 'top', 'htop', 'btop',
    'vim', 'nvim', 'vi', 'nano', 'emacs', 'cat', 'less', 'more',
    'node', 'bash', 'zsh', 'sh', 'fish', 'dash', 'tmux', 'screen'
  ]);
  if (forbiddenBins.has(binName)) {
    return false;
  }

  // 2. The executable must be "luvus"
  if (binName !== 'luvus') {
    return false;
  }

  // 3. Inspect arguments to filter out non-TUI subcommands
  const subcommands = tokens.slice(1);
  const nonTuiSubcommands = new Set([
    'server', 'module', 'agent', 'pane', 'tab', 'workspace', 'task', 'lease',
    'files', 'git', 'diff', 'worktree', 'theme', 'bar', 'ui', 'integration',
    'skill', 'wait', 'search', 'events', 'uhp', 'doctor', 'update', 'ping', 'help'
  ]);

  let hasSessionFlag = false;
  let sessionName = '';

  for (let i = 0; i < subcommands.length; i++) {
    const arg = subcommands[i];
    if (arg === '--session' || arg === '-s') {
      hasSessionFlag = true;
      sessionName = subcommands[i + 1] || '';
      i++;
      continue;
    }
    if (arg.startsWith('--session=')) {
      hasSessionFlag = true;
      sessionName = arg.slice(10);
      continue;
    }
    if (arg.startsWith('-')) {
      continue;
    }

    // Positional subcommand argument
    if (arg === 'attach') {
      // `luvus attach <pane>` launches fullscreen TUI for a single pane, valid client
      break;
    }
    if (nonTuiSubcommands.has(arg)) {
      return false;
    }
    // Any unrecognized positional argument is assumed not to be an interactive TUI launcher
    return false;
  }

  // 4. Session matching
  const targetSession = currentSession || process.env.LUVUS_SESSION || '';
  if (targetSession && targetSession !== 'default') {
    if (hasSessionFlag && sessionName && sessionName !== targetSession) {
      return false;
    }
  } else {
    // Default session: client should not target a different named session
    if (hasSessionFlag && sessionName && sessionName !== 'default') {
      return false;
    }
  }

  return true;
}

/**
 * Finds the controlling PTY device of the outer terminal session.
 * Strictly resolves to the single TTY belonging to this Luvus session to prevent
 * cross-talk across hosts/tabs.
 */
function findTargetTTY() {
  // 1. Direct /dev/tty check (only if this process has a controlling terminal)
  try {
    const fd = fs.openSync('/dev/tty', 'w');
    fs.closeSync(fd);
    return '/dev/tty';
  } catch (_) {}

  // 2. Ancestor process walk to find a controlling TTY
  let curPid = process.pid;
  for (let i = 0; i < 6; i++) {
    try {
      const out = execSync(`ps -p ${curPid} -o ppid=,tty=`, { encoding: 'utf8' }).trim();
      const parts = out.split(/\s+/);
      if (parts.length >= 2) {
        const ppid = parseInt(parts[0], 10);
        const tty = parts[1];
        if (tty && tty !== '?' && tty !== '??') {
          const ttyPath = tty.startsWith('/dev/') ? tty : `/dev/${tty}`;
          if (fs.existsSync(ttyPath)) return ttyPath;
        }
        if (!ppid || ppid <= 1) break;
        curPid = ppid;
      } else {
        break;
      }
    } catch (_) {
      break;
    }
  }

  // 3. Module processes are launched by the background Luvus server. Find the
  // live interactive client instead of trusting the server's inherited SSH_TTY.
  try {
    const currentSession = process.env.LUVUS_SESSION || '';
    const out = execSync('ps -eo pid=,tty=,args=', { encoding: 'utf8' });
    const lines = out.split('\n');
    for (const line of lines) {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 3) {
        const [pid, tty, ...cmdParts] = parts;
        const cmd = cmdParts.join(' ');
        if (tty && tty !== '?' && tty !== '??') {
          if (isInteractiveLuvusClient(cmd, currentSession)) {
            const ttyPath = tty.startsWith('/dev/') ? tty : `/dev/${tty}`;
            if (fs.existsSync(ttyPath)) return ttyPath;
          }
        }
      }
    }
  } catch (_) {}

  // 4. Last-resort environment fallback. A daemonized Luvus server can retain
  // an SSH_TTY that points to an older connection, so this must remain last.
  if (process.env.SSH_TTY && fs.existsSync(process.env.SSH_TTY)) return process.env.SSH_TTY;
  if (process.env.TTY && fs.existsSync(process.env.TTY)) return process.env.TTY;

  return null;
}

/**
 * Writes OSC 0 title escape sequence strictly to the target host terminal PTY.
 * No global broadcasting to ensure zero cross-host interference.
 */
function writeTerminalTitle(title) {
  const osc = `\x1b]0;${title}\x07`;

  // 1. Direct target TTY belonging to this session
  const ttyPath = findTargetTTY();
  if (ttyPath) {
    try {
      const fd = fs.openSync(ttyPath, fs.constants.O_WRONLY | fs.constants.O_NONBLOCK);
      fs.writeSync(fd, osc);
      fs.closeSync(fd);
      return true;
    } catch (_) {}
  }

  // 2. Fallback to process.stdout if connected to a TTY
  try {
    if (process.stdout.isTTY) {
      process.stdout.write(osc);
      return true;
    }
  } catch (_) {}

  return false;
}

/**
 * Fetches agent list and updates terminal title via direct Unix Socket JSON-RPC.
 * Returns true on success, false on failure (which triggers CLI fallback).
 */
function syncViaSocket(socketPath, hostname) {
  return new Promise((resolve) => {
    let settled = false;
    let buffer = '';

    const client = net.createConnection(socketPath);

    const hardTimer = setTimeout(() => {
      finish(false);
    }, 500);

    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(hardTimer);
      try {
        client.destroy();
      } catch (_) {}
      resolve(result);
    };

    client.setTimeout(500, () => finish(false));
    client.on('error', () => finish(false));
    client.on('close', () => finish(false));

    client.on('connect', () => {
      // Step 1: Request agent list over UHP
      const req = {
        id: '1',
        method: 'agent.list',
        params: {},
      };
      client.write(JSON.stringify(req) + '\n');
    });

    client.on('data', (chunk) => {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() ?? '';

      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        try {
          const resp = JSON.parse(trimmed);
          if (resp.id === '1') {
            const agents = Array.isArray(resp.result?.agents)
              ? resp.result.agents
              : (Array.isArray(resp.agents) ? resp.agents : []);

            const statuses = agents.map(a => a.status || a.agent_status || 'unknown');
            const symbols = formatAgentStatusSymbols(statuses);
            const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;

            writeTerminalTitle(title);
            finish(true);
            return;
          }
        } catch (_) {
          finish(false);
          return;
        }
      }
    });
  });
}

/**
 * CLI Fallback: Fetches the current agent list from Luvus CLI.
 */
function fetchAgentListCLI(luvusBin) {
  try {
    const res = spawnSync(luvusBin, ['agent', 'list'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 3000,
    });
    if (res.status === 0 && res.stdout) {
      const parsed = JSON.parse(res.stdout);
      if (Array.isArray(parsed.agents)) {
        return parsed.agents;
      }
      if (Array.isArray(parsed.result?.agents)) {
        return parsed.result.agents;
      }
    }
  } catch (_) {}
  return [];
}

/**
 * Main execution function.
 */
async function run() {
  const args = process.argv.slice(2);
  const isTest = args.includes('--test');
  const isDryRun = args.includes('--dry-run');
  const isVersion = args.includes('--version') || args.includes('-v');

  if (isVersion) {
    console.log(`muh.status-title v${MODULE_VERSION}`);
    return true;
  }

  if (isTest) {
    runSelfTests();
    return true;
  }

  const hostname = getHostname();
  const socketPath = resolveSocketPath();
  const luvusBin = resolveLuvusBin();

  if (isDryRun) {
    let agents = [];
    if (socketPath) {
      // dry-run with socket
      try {
        const res = await new Promise(resResolve => {
          const client = net.createConnection(socketPath);
          client.setTimeout(1500, () => { client.destroy(); resResolve(null); });
          client.on('error', () => resResolve(null));
          client.on('connect', () => {
            client.write(JSON.stringify({ id: 'dry-run', method: 'agent.list', params: {} }) + '\n');
          });
          let buf = '';
          client.on('data', chunk => {
            buf += chunk.toString();
            if (buf.includes('\n')) {
              try {
                const parsed = JSON.parse(buf.split('\n')[0]);
                client.destroy();
                resResolve(parsed.agents || parsed.result?.agents || []);
              } catch (_) {
                client.destroy();
                resResolve(null);
              }
            }
          });
        });
        if (res) agents = res;
      } catch (_) {}
    }
    if (agents.length === 0) {
      agents = fetchAgentListCLI(luvusBin);
    }
    const statuses = agents.map(a => a.status || a.agent_status || 'unknown');
    const symbols = formatAgentStatusSymbols(statuses);
    const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;
    const targetTTY = findTargetTTY();
    console.log(`[Luvus StatusTitle v${MODULE_VERSION} DryRun] Target TTY: ${targetTTY || 'none'}`);
    console.log(`[Luvus StatusTitle v${MODULE_VERSION} DryRun] Agents: ${statuses.join(', ')}`);
    console.log(`[Luvus StatusTitle v${MODULE_VERSION} DryRun] Title: "${title}"`);
    return true;
  }

  // 1. Primary path: Native Unix Socket JSON-RPC
  if (socketPath) {
    const ok = await syncViaSocket(socketPath, hostname);
    if (ok) return true;
  }

  // 2. Fallback path: CLI subprocess
  const agents = fetchAgentListCLI(luvusBin);
  const statuses = agents.map(a => a.status || a.agent_status || 'unknown');
  const symbols = formatAgentStatusSymbols(statuses);
  const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;
  return writeTerminalTitle(title);
}

/**
 * Self tests to verify sorting, formatting, and client filtering logic.
 */
function runSelfTests() {
  console.log('Running Luvus status formatting and client filter tests...');

  const formattingTestCases = [
    {
      name: '0 agents (empty array) emits empty symbols string for hostname: idle',
      input: [],
      expected: '',
    },
    {
      name: 'Single agent idle (green circle)',
      input: ['idle'],
      expected: '○',
    },
    {
      name: 'Two agents idle (two green circles)',
      input: ['idle', 'idle'],
      expected: '○○',
    },
    {
      name: 'Single agent working',
      input: ['working'],
      expected: '◐',
    },
    {
      name: 'Two blocked and two done',
      input: ['done', 'blocked', 'done', 'blocked'],
      expected: '××✓✓',
    },
    {
      name: 'Mixed states with working, blocked, done, and idle',
      input: ['idle', 'working', 'blocked', 'done'],
      expected: '×✓◐○',
    },
    {
      name: 'More than 10 agents: blocked and done stay in front',
      input: ['idle', 'working', 'done', 'idle', 'blocked', 'done', 'working', 'idle', 'working', 'done', 'idle', 'blocked'],
      expected: '××✓✓✓◐◐◐○○',
    },
    {
      name: '12 blocked agents truncated to 10',
      input: Array(12).fill('blocked'),
      expected: '××××××××××',
    },
  ];

  let passed = 0;
  for (const tc of formattingTestCases) {
    const actual = formatAgentStatusSymbols(tc.input);
    if (actual === tc.expected) {
      console.log(`  ✓ ${tc.name}: "${actual}"`);
      passed++;
    } else {
      console.error(`  ✗ ${tc.name}: expected "${tc.expected}", got "${actual}"`);
    }
  }

  const clientFilterTestCases = [
    {
      name: 'SSH command should NEVER be matched as local luvus client',
      cmd: 'ssh -t dq-wy-inf1 luvus',
      expected: false,
    },
    {
      name: 'SSH command with path should NEVER be matched',
      cmd: '/usr/bin/ssh -t dev2 luvus',
      expected: false,
    },
    {
      name: 'Pure luvus command is interactive TUI client',
      cmd: 'luvus',
      expected: true,
    },
    {
      name: 'Luvus with binary path is interactive client',
      cmd: '/Users/test/.local/bin/luvus',
      expected: true,
    },
    {
      name: 'Luvus attach is interactive client',
      cmd: 'luvus attach 4',
      expected: true,
    },
    {
      name: 'Luvus server is daemon, NOT interactive client',
      cmd: 'luvus server',
      expected: false,
    },
    {
      name: 'Luvus module run is one-off CLI, NOT interactive client',
      cmd: 'luvus module run muh.status-title sync',
      expected: false,
    },
    {
      name: 'Luvus agent list is CLI command, NOT interactive client',
      cmd: 'luvus agent list',
      expected: false,
    },
    {
      name: 'Mosh client is NOT luvus client',
      cmd: 'mosh-client user@remote',
      expected: false,
    },
    {
      name: 'Matching specific session',
      cmd: 'luvus --session docs',
      session: 'docs',
      expected: true,
    },
    {
      name: 'Mismatching specific session',
      cmd: 'luvus --session other',
      session: 'docs',
      expected: false,
    },
  ];

  for (const tc of clientFilterTestCases) {
    const actual = isInteractiveLuvusClient(tc.cmd, tc.session || '');
    if (actual === tc.expected) {
      console.log(`  ✓ [Filter] ${tc.name}: ${actual}`);
      passed++;
    } else {
      console.error(`  ✗ [Filter] ${tc.name}: expected ${tc.expected}, got ${actual}`);
    }
  }

  const binaryTestCases = [
    {
      name: 'Linux deleted marker resolves to replacement executable',
      input: `${process.execPath} (deleted)`,
      expected: process.execPath,
    },
    {
      name: 'Missing configured executable falls back to PATH lookup',
      input: path.join(os.tmpdir(), 'muh-luvus-definitely-missing'),
      expected: 'luvus',
    },
  ];

  for (const tc of binaryTestCases) {
    const actual = resolveLuvusBin(tc.input);
    if (actual === tc.expected) {
      console.log(`  ✓ [Binary] ${tc.name}: "${actual}"`);
      passed++;
    } else {
      console.error(`  ✗ [Binary] ${tc.name}: expected "${tc.expected}", got "${actual}"`);
    }
  }

  const total = formattingTestCases.length + clientFilterTestCases.length + binaryTestCases.length;
  console.log(`Test results: ${passed}/${total} passed.`);
  if (passed !== total) {
    process.exit(1);
  }
}

// Run immediately
run()
  .then(result => {
    process.exit(result === false ? 1 : 0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });

module.exports = {
  MODULE_VERSION,
  formatAgentStatusSymbols,
  getHostname,
  resolveLuvusBin,
  findTargetTTY,
  isInteractiveLuvusClient,
  STATUS_CONFIG,
  MAX_INDICATORS,
};
MUH_MODULE_INDEX
# END GENERATED MODULE INDEX

chmod +x "$MODULE_DIR/index.js" "$MODULE_DIR/run.sh"
ok "Module files installed to $MODULE_DIR"

# ------------------------------------------------------------------------------
# 5. Link & Activate Module in Luvus
# ------------------------------------------------------------------------------
info "Linking module into Luvus..."

# Ensure Luvus background daemon is started so CLI IPC can communicate
if ! "$LUVUS_BIN" server status >/dev/null 2>&1; then
    "$LUVUS_BIN" server start >/dev/null 2>&1 || true
    sleep 1
fi

# Reload manifests if server is running
node -e '
const net = require("net");
const c = net.createConnection(process.env.HOME + "/.luvus/luvus.sock");
c.on("connect", () => {
  c.write(JSON.stringify({id: "setup-reload", method: "server.reload_agent_manifests", params: {}}) + "\n");
});
c.on("data", () => { c.destroy(); process.exit(0); });
c.on("error", () => process.exit(0));
setTimeout(() => process.exit(0), 1000);
' 2>/dev/null || true

module_list_output=$("$LUVUS_BIN" module list 2>&1 || true)
if echo "$module_list_output" | grep -Fq 'muh.status-title'; then
    info "Refreshing existing muh.status-title module registration..."
    if ! unlink_output=$("$LUVUS_BIN" module unlink "muh.status-title" 2>&1); then
        err "Failed to unlink the existing module registration:"
        printf '%s\n' "$unlink_output"
        exit 1
    fi
fi

if ! link_output=$("$LUVUS_BIN" module link "$MODULE_DIR" 2>&1); then
    # If server was starting up, retry once
    "$LUVUS_BIN" server start >/dev/null 2>&1 || true
    sleep 1
    if ! link_output=$("$LUVUS_BIN" module link "$MODULE_DIR" 2>&1); then
        err "Failed to register module:"
        printf '%s\n' "$link_output"
        exit 1
    fi
fi

"$LUVUS_BIN" module enable "muh.status-title" >/dev/null 2>&1 || true

# Verify link
module_list_output=$("$LUVUS_BIN" module list 2>&1 || true)
if echo "$module_list_output" | grep -Fq 'muh.status-title'; then
    ok "Module muh.status-title successfully verified in Luvus!"
else
    err "Module registration could not be verified."
    printf '%s\n' "$module_list_output"
    exit 1
fi

# Run initial sync test
info "Running initial status synchronization..."
if ! bash "$MODULE_DIR/run.sh"; then
    warn "Initial status synchronization failed; the module is registered and will retry on Luvus events."
fi

printf "\n${COLOR_GREEN}${COLOR_BOLD}✔ Luvus setup for MuH completed successfully!${COLOR_NC}\n\n"
