#!/usr/bin/env bash
# ==============================================================================
# MuH / Herdr Integration Initializer
# 
# Usage:
#   Local:   bash setup-herdr.sh
#   Remote:  ssh <user@host> 'bash -s' < setup-herdr.sh
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# 0. Ensure Full PATH in Non-interactive SSH Shells
# ------------------------------------------------------------------------------
# When invoked via `ssh host 'bash -s'`, SSH doesn't load ~/.zshrc or ~/.bash_profile.
# We explicitly probe common user paths and source profiles if available.
if [ -f "$HOME/.profile" ]; then (source "$HOME/.profile" 2>/dev/null) && source "$HOME/.profile" 2>/dev/null || true; fi
if [ -f "$HOME/.bash_profile" ]; then (source "$HOME/.bash_profile" 2>/dev/null) && source "$HOME/.bash_profile" 2>/dev/null || true; fi
if [ -f "$HOME/.bashrc" ]; then (source "$HOME/.bashrc" 2>/dev/null) && source "$HOME/.bashrc" 2>/dev/null || true; fi

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/bin:/usr/local/bin:$HOME/.pixi/bin:$HOME/.pixi/envs/default/bin:$HOME/.pixi/envs/nodejs/bin:$HOME/.asdf/shims:$HOME/.fnm/current/bin:$PATH"

# Probe herdr binary location
if ! command -v herdr >/dev/null 2>&1; then
    for candidate in "$HOME/.local/bin/herdr" "$HOME/.cargo/bin/herdr" "$HOME/bin/herdr" "/usr/local/bin/herdr"; do
        if [ -x "$candidate" ]; then
            export PATH="$(dirname "$candidate"):$PATH"
            break
        fi
    done
fi

# Probe node binary location
if ! command -v node >/dev/null 2>&1; then
    for candidate in "$HOME/.nvm/versions/node"/*"/bin/node" "$HOME/.fnm/current/bin/node" "$HOME/.asdf/shims/node" "$HOME/.pixi/bin/node" "$HOME/.pixi/envs/nodejs/bin/node" "$HOME/.local/bin/node" "/usr/local/bin/node" "/opt/homebrew/bin/node"; do
        if [ -x "$candidate" ]; then
            export PATH="$(dirname "$candidate"):$PATH"
            break
        fi
    done
fi

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
printf "${COLOR_BOLD}   MuH ➔ Herdr Agent Status Initializer  ${COLOR_NC}\n"
printf "${COLOR_BOLD}========================================${COLOR_NC}\n\n"

# ------------------------------------------------------------------------------
# 1. Environment & Dependency Checks
# ------------------------------------------------------------------------------
info "Checking environment dependencies..."

# Check Herdr
if ! command -v herdr >/dev/null 2>&1; then
    err "Herdr is not installed or not in PATH!"
    printf "Please install Herdr first (e.g., cargo install herdr or download from GitHub releases).\n\n"
    exit 1
fi

HERDR_BIN=$(command -v herdr)
HERDR_VERSION=$(herdr --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")
ok "Found Herdr at $HERDR_BIN (v${HERDR_VERSION})"

# Check Node.js
if ! command -v node >/dev/null 2>&1; then
    err "Node.js is not installed or not in PATH!"
    printf "Herdr plugins require Node.js runtime. Please install Node.js (v18+ recommended).\n\n"
    exit 1
fi

NODE_BIN=$(command -v node)
NODE_VERSION=$(node -v 2>&1 || echo "unknown")
ok "Found Node.js at $NODE_BIN (${NODE_VERSION})"

# ------------------------------------------------------------------------------
# 2. Configure ~/.config/herdr/config.toml
# ------------------------------------------------------------------------------
info "Configuring Herdr settings..."

HERDR_CONFIG_DIR="$HOME/.config/herdr"
HERDR_CONFIG_FILE="$HERDR_CONFIG_DIR/config.toml"

mkdir -p "$HERDR_CONFIG_DIR"

if [ -f "$HERDR_CONFIG_FILE" ]; then
    update_ui_config() {
        local tmp mode
        tmp=$(mktemp "${HERDR_CONFIG_FILE}.XXXXXX")
        mode=$(stat -c '%a' "$HERDR_CONFIG_FILE" 2>/dev/null || stat -f '%Lp' "$HERDR_CONFIG_FILE")
        awk '
            function finish_section() {
                if (section == "ui" && !wrote_ui) {
                    print "status_indicators = \"symbols\""
                    wrote_ui = 1
                }
                if (section == "ui.toast" && !wrote_toast) {
                    print "delivery = \"terminal\""
                    wrote_toast = 1
                }
            }
            BEGIN { section = ""; found_ui = 0; found_toast = 0; wrote_ui = 0; wrote_toast = 0 }
            /^\[ui\][[:space:]]*$/ {
                finish_section()
                section = "ui"; found_ui = 1; print; next
            }
            /^\[ui\.toast\][[:space:]]*$/ {
                finish_section()
                section = "ui.toast"; found_toast = 1; print; next
            }
            /^\[ui\.toast\./ {
                finish_section()
                if (!found_toast) {
                    print ""
                    print "[ui.toast]"
                    print "delivery = \"terminal\""
                    found_toast = 1; wrote_toast = 1
                }
                section = ""; print; next
            }
            /^\[/ {
                finish_section()
                section = ""; print; next
            }
            {
                if (section == "ui" && $0 ~ /^[[:space:]]*status_indicators[[:space:]]*=/) {
                    if (!wrote_ui) { print "status_indicators = \"symbols\""; wrote_ui = 1 }
                    next
                }
                if (section == "ui.toast" && $0 ~ /^[[:space:]]*delivery[[:space:]]*=/) {
                    if (!wrote_toast) { print "delivery = \"terminal\""; wrote_toast = 1 }
                    next
                }
                print
            }
            END {
                finish_section()
                if (!found_ui) {
                    print ""
                    print "[ui]"
                    print "status_indicators = \"symbols\""
                }
                if (!found_toast) {
                    print ""
                    print "[ui.toast]"
                    print "delivery = \"terminal\""
                }
            }
        ' "$HERDR_CONFIG_FILE" > "$tmp"
        chmod "$mode" "$tmp"
        mv "$tmp" "$HERDR_CONFIG_FILE"
    }

    update_ui_config
    ok "Updated status indicators and terminal notification delivery in config.toml"
else
    cat << 'EOF' > "$HERDR_CONFIG_FILE"
onboarding = false

[ui]
status_indicators = "symbols"
show_agent_labels_on_pane_borders = true

[ui.toast]
delivery = "terminal"
EOF
    ok "Created ~/.config/herdr/config.toml with status_indicators = \"symbols\""
fi

# ------------------------------------------------------------------------------
# 3. Deploy MuH Status-Title Plugin
# ------------------------------------------------------------------------------
info "Installing MuH status-title plugin..."

PLUGIN_DIR="$HERDR_CONFIG_DIR/plugins/status-title"
mkdir -p "$PLUGIN_DIR"

# BEGIN GENERATED PLUGIN MANIFEST
cat << 'MUH_PLUGIN_MANIFEST' > "$PLUGIN_DIR/herdr-plugin.toml"
id = "muh.status-title"
name = "MuH Status Title"
version = "0.1.0"
min_herdr_version = "0.8.0"
description = "Sync aggregated agent status indicators to outer terminal window title for MuH"
platforms = ["linux", "macos", "windows"]

[[startup]]
command = ["bash", "run.sh"]

[[events]]
on = "pane.agent_status_changed"
command = ["bash", "run.sh"]

[[events]]
on = "pane.agent_detected"
command = ["bash", "run.sh"]

[[events]]
on = "pane.created"
command = ["bash", "run.sh"]

[[events]]
on = "pane.closed"
command = ["bash", "run.sh"]

[[events]]
on = "pane.exited"
command = ["bash", "run.sh"]

[[events]]
on = "workspace.focused"
command = ["bash", "run.sh"]

[[events]]
on = "workspace.closed"
command = ["bash", "run.sh"]

[[events]]
on = "workspace.updated"
command = ["bash", "run.sh"]

[[events]]
on = "tab.focused"
command = ["bash", "run.sh"]

[[events]]
on = "tab.closed"
command = ["bash", "run.sh"]

[[actions]]
id = "sync"
title = "Sync status title"
contexts = ["workspace"]
command = ["bash", "run.sh"]
MUH_PLUGIN_MANIFEST
# END GENERATED PLUGIN MANIFEST

# BEGIN GENERATED PLUGIN RUNNER
cat << 'MUH_PLUGIN_RUNNER' > "$PLUGIN_DIR/run.sh"
#!/usr/bin/env bash
# ==============================================================================
# MuH Status Title Runner
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
MUH_PLUGIN_RUNNER
# END GENERATED PLUGIN RUNNER

# BEGIN GENERATED PLUGIN INDEX
cat << 'MUH_PLUGIN_INDEX' > "$PLUGIN_DIR/index.js"
#!/usr/bin/env node

/**
 * MuH Status Title Plugin for Herdr
 *
 * Aggregates agent status in the active Herdr workspace/session, sorts them by priority
 * (Blocked and Done first, Working and Idle last), limits to 10 indicators, and writes
 * the formatted title (e.g. "dev2: ×✓✓◐") to the outer terminal title via OSC 0.
 */

const { spawnSync } = require('node:child_process');
const os = require('node:os');
const net = require('node:net');
const path = require('node:path');
const fs = require('node:fs');

const STATUS_CONFIG = {
  blocked: { weight: 1, symbol: '×' }, // 🔴 阻塞 / 需要确认
  done:    { weight: 2, symbol: '✓' }, // 🟢 完成待查看
  working: { weight: 3, symbol: '◐' }, // 🟡 正在执行
  idle:    { weight: 4, symbol: '○' }, // ⚪️ 空闲
  unknown: { weight: 5, symbol: '·' }, // ⚪️ 未知
};

const MAX_INDICATORS = 10;

/**
 * Formats a list of agent status strings into a concise symbols string.
 * @param {string[]} statuses Array of agent status strings (e.g. ['blocked', 'working', 'done'])
 * @returns {string} Combined symbols string (e.g. "×✓◐")
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
  const raw = process.env.HERDR_HOSTNAME || os.hostname() || 'herdr';
  return raw.split('.')[0];
}

/**
 * Probe default Herdr Unix socket path if not provided in environment.
 */
function resolveSocketPath() {
  if (process.env.HERDR_SOCKET_PATH && fs.existsSync(process.env.HERDR_SOCKET_PATH)) {
    return process.env.HERDR_SOCKET_PATH;
  }
  const home = os.homedir();
  const candidates = [
    path.join(home, '.config', 'herdr', 'herdr.sock'),
    path.join(home, '.local', 'share', 'herdr', 'herdr.sock'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return null;
}

/**
 * Fetches agent list and updates terminal title via direct Unix Socket JSON-RPC.
 * Returns true on success, false on failure (which triggers CLI fallback).
 */
function syncViaSocket(socketPath, hostname) {
  return new Promise((resolve) => {
    let settled = false;
    let buffer = '';
    let stage = 'fetch'; // 'fetch' -> 'set' -> 'done'

    const finish = (result) => {
      if (settled) return;
      settled = true;
      try {
        client.destroy();
      } catch (_) {}
      resolve(result);
    };

    const client = net.createConnection(socketPath);
    client.setTimeout(2000, () => finish(false));

    client.on('error', () => finish(false));

    client.on('connect', () => {
      // Step 1: Request agent list
      const req = {
        id: 'muh-agent-list',
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
          if (stage === 'fetch' && resp.id === 'muh-agent-list') {
            const agents = resp.result?.agents && Array.isArray(resp.result.agents) ? resp.result.agents : [];
            const statuses = agents.map(a => a.agent_status || a.status || 'unknown');
            const symbols = formatAgentStatusSymbols(statuses);
            const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;

            stage = 'set';
            const setReq = {
              id: 'muh-title-set',
              method: 'client.window_title.set',
              params: { title },
            };
            client.write(JSON.stringify(setReq) + '\n');
          } else if (stage === 'set' && resp.id === 'muh-title-set') {
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
 * CLI Fallback: Fetches the current agent list from Herdr.
 */
function fetchAgentListCLI(herdrBin) {
  try {
    const res = spawnSync(herdrBin, ['agent', 'list'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      timeout: 3000,
    });
    if (res.status === 0 && res.stdout) {
      const parsed = JSON.parse(res.stdout);
      if (parsed.result?.agents && Array.isArray(parsed.result.agents)) {
        return parsed.result.agents;
      }
    }
  } catch (_) {}
  return [];
}

/**
 * CLI Fallback: Sets the outer terminal title via Herdr CLI.
 */
function setOuterWindowTitleViaCLI(title, herdrBin) {
  try {
    const res = spawnSync(herdrBin, ['terminal', 'title', 'set', title], {
      encoding: 'utf8',
      stdio: ['ignore', 'ignore', 'ignore'],
      timeout: 3000,
    });
    return res.status === 0;
  } catch (_) {
    return false;
  }
}

/**
 * Main execution function.
 */
async function run() {
  const args = process.argv.slice(2);
  const isTest = args.includes('--test');
  const isDryRun = args.includes('--dry-run');

  if (isTest) {
    runSelfTests();
    return true;
  }

  const hostname = getHostname();
  const socketPath = resolveSocketPath();
  const herdrBin = process.env.HERDR_BIN_PATH || 'herdr';

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
                resResolve(parsed.result?.agents || []);
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
      agents = fetchAgentListCLI(herdrBin);
    }
    const statuses = agents.map(a => a.agent_status || a.status || 'unknown');
    const symbols = formatAgentStatusSymbols(statuses);
    const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;
    console.log(`[StatusTitle DryRun] Agents: ${statuses.join(', ')}`);
    console.log(`[StatusTitle DryRun] Title: "${title}"`);
    return true;
  }

  // 1. Primary path: Native Unix Socket JSON-RPC
  if (socketPath) {
    const ok = await syncViaSocket(socketPath, hostname);
    if (ok) return true;
  }

  // 2. Fallback path: CLI subprocess
  const agents = fetchAgentListCLI(herdrBin);
  const statuses = agents.map(a => a.agent_status || a.status || 'unknown');
  const symbols = formatAgentStatusSymbols(statuses);
  const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;
  return setOuterWindowTitleViaCLI(title, herdrBin);
}

/**
 * Self tests to verify sorting and formatting logic.
 */
function runSelfTests() {
  console.log('Running status formatting tests...');

  const testCases = [
    {
      name: 'Empty agents',
      input: [],
      expected: '',
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
      name: 'Mixed states with working and idle',
      input: ['idle', 'working', 'blocked', 'done'],
      expected: '×✓◐○',
    },
    {
      name: 'More than 10 agents: blocked and done stay in front',
      input: ['idle', 'working', 'done', 'idle', 'blocked', 'done', 'working', 'idle', 'working', 'done', 'idle', 'blocked'],
      // Sorted: blocked(2), done(3), working(3), idle(4)
      // Top 10: blocked(2), done(3), working(3), idle(2) -> ××✓✓✓◐◐◐○○
      expected: '××✓✓✓◐◐◐○○',
    },
    {
      name: '12 blocked agents truncated to 10',
      input: Array(12).fill('blocked'),
      expected: '××××××××××',
    },
  ];

  let passed = 0;
  for (const tc of testCases) {
    const actual = formatAgentStatusSymbols(tc.input);
    if (actual === tc.expected) {
      console.log(`  ✓ ${tc.name}: "${actual}"`);
      passed++;
    } else {
      console.error(`  ✗ ${tc.name}: expected "${tc.expected}", got "${actual}"`);
    }
  }

  console.log(`Test results: ${passed}/${testCases.length} passed.`);
  if (passed !== testCases.length) {
    process.exit(1);
  }
}

// Run immediately
run()
  .then(result => {
    if (result === false) process.exitCode = 1;
  })
  .catch(() => {
    process.exitCode = 1;
  });

module.exports = {
  formatAgentStatusSymbols,
  getHostname,
  STATUS_CONFIG,
  MAX_INDICATORS,
};
MUH_PLUGIN_INDEX
# END GENERATED PLUGIN INDEX

chmod +x "$PLUGIN_DIR/index.js" "$PLUGIN_DIR/run.sh"
ok "Plugin files installed to $PLUGIN_DIR"

# ------------------------------------------------------------------------------
# 4. Link & Activate Plugin in Herdr
# ------------------------------------------------------------------------------
info "Linking plugin into Herdr..."
if ! link_output=$(herdr plugin link "$PLUGIN_DIR" 2>&1); then
    err "Failed to register plugin:"
    printf '%s\n' "$link_output"
    exit 1
fi

# Verify link
if herdr plugin list 2>&1 | grep -q 'muh.status-title'; then
    ok "Plugin muh.status-title successfully registered and enabled!"
else
    err "Plugin registration could not be verified."
    exit 1
fi

# Run initial sync test
info "Running initial status synchronization..."
if ! bash "$PLUGIN_DIR/run.sh"; then
    warn "Initial status synchronization failed; the plugin is registered and will retry on Herdr events."
fi

printf "\n${COLOR_GREEN}${COLOR_BOLD}✔ Herdr setup for MuH completed successfully!${COLOR_NC}\n\n"
