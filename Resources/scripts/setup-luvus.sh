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
# 0. Ensure Full PATH in Non-interactive SSH Shells
# ------------------------------------------------------------------------------
if [ -f "$HOME/.profile" ]; then (source "$HOME/.profile" 2>/dev/null) && source "$HOME/.profile" 2>/dev/null || true; fi
if [ -f "$HOME/.bash_profile" ]; then (source "$HOME/.bash_profile" 2>/dev/null) && source "$HOME/.bash_profile" 2>/dev/null || true; fi
if [ -f "$HOME/.bashrc" ]; then (source "$HOME/.bashrc" 2>/dev/null) && source "$HOME/.bashrc" 2>/dev/null || true; fi

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
    for candidate in "$HOME/.nvm/versions/node"/*"/bin/node" "$HOME/.fnm/current/bin/node" "$HOME/.asdf/shims/node" "$HOME/.pixi/bin/node" "$HOME/.pixi/envs/nodejs/bin/node" "$HOME/.local/bin/node" "/usr/local/bin/node" "/opt/homebrew/bin/node"; do
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
# 1. Environment & Dependency Checks (Auto-install Luvus if missing)
# ------------------------------------------------------------------------------
info "Checking environment dependencies..."

LUVUS_BIN=$(probe_luvus || true)

if [ -z "$LUVUS_BIN" ]; then
    info "Luvus is not installed. Installing Luvus automatically via official installer..."
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
    ok "Successfully installed Luvus!"
fi

LUVUS_VERSION=$("$LUVUS_BIN" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")
ok "Found Luvus at $LUVUS_BIN (v${LUVUS_VERSION})"

# ------------------------------------------------------------------------------
# 2. Reinforce Non-Interactive SSH Compatibility & PATH
# ------------------------------------------------------------------------------
# Ensure luvus is accessible in standard non-interactive SSH paths
mkdir -p "$HOME/.local/bin"
if [ -d "$HOME/.cargo/bin" ] && [ "$LUVUS_BIN" != "$HOME/.cargo/bin/luvus" ]; then
    ln -sf "$LUVUS_BIN" "$HOME/.cargo/bin/luvus" 2>/dev/null || true
fi
if [ -d "$HOME/bin" ] && [ "$LUVUS_BIN" != "$HOME/bin/luvus" ]; then
    ln -sf "$LUVUS_BIN" "$HOME/bin/luvus" 2>/dev/null || true
fi

# Ensure ~/.bashrc or ~/.bash_profile has ~/.local/bin in PATH
ensure_path_in_file() {
    local file="$1"
    if [ -f "$file" ]; then
        if ! grep -Eq '(^|:|\$HOME/|~/)(\.local/bin|\.cargo/bin)' "$file"; then
            printf '\n# Added by MuH / Luvus installer for SSH compatibility\nexport PATH="$HOME/.local/bin:$HOME/.cargo/bin:$HOME/bin:$PATH"\n' >> "$file"
        fi
    fi
}
ensure_path_in_file "$HOME/.bashrc"
ensure_path_in_file "$HOME/.bashrc.local"
ensure_path_in_file "$HOME/.profile"
ensure_path_in_file "$HOME/.zshrc"

# Check Node.js
NODE_BIN=$(probe_node || true)
if [ -z "$NODE_BIN" ]; then
    err "Node.js is not installed or not in PATH!"
    printf "The MuH status module requires Node.js runtime. Please install Node.js (v18+ recommended).\n\n"
    exit 1
fi

NODE_VERSION=$("$NODE_BIN" -v 2>&1 || echo "unknown")
ok "Found Node.js at $NODE_BIN (${NODE_VERSION})"

# ------------------------------------------------------------------------------
# 3. Configure ~/.config/luvus/config.toml
# ------------------------------------------------------------------------------
info "Configuring Luvus settings..."

LUVUS_CONFIG_DIR="$HOME/.config/luvus"
LUVUS_CONFIG_FILE="$LUVUS_CONFIG_DIR/config.toml"

mkdir -p "$LUVUS_CONFIG_DIR"

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
version = "0.1.0"
min_luvus_version = "0.8.3"
description = "Sync aggregated agent status indicators to outer terminal window title for MuH"
platforms = ["linux", "macos", "windows"]

[[startup]]
command = ["bash", "run.sh"]

[[events]]
on = "pane.agent_status_changed"
command = ["bash", "run.sh"]

[[events]]
on = "pane.created"
command = ["bash", "run.sh"]

[[events]]
on = "pane.closed"
command = ["bash", "run.sh"]

[[events]]
on = "workspace.created"
command = ["bash", "run.sh"]

[[events]]
on = "workspace.closed"
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
    path.join(home, '.local', 'share', 'luvus', 'luvus.sock'),
    path.join(home, '.config', 'luvus', 'luvus.sock'),
    path.join('/tmp', `luvus-${process.getuid?.() || 1000}`, 'luvus.sock'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return null;
}

/**
 * Finds the controlling PTY device of the outer terminal session.
 */
function findTargetTTY() {
  // 1. Direct environment variable
  if (process.env.SSH_TTY && fs.existsSync(process.env.SSH_TTY)) return process.env.SSH_TTY;
  if (process.env.TTY && fs.existsSync(process.env.TTY)) return process.env.TTY;

  // 2. Direct /dev/tty check
  try {
    const fd = fs.openSync('/dev/tty', 'w');
    fs.closeSync(fd);
    return '/dev/tty';
  } catch (_) {}

  // 3. Ancestor process walk to find controlling TTY
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

  // 4. Scan active luvus processes with a valid TTY
  try {
    const out = execSync('ps -eo tty=,comm=', { encoding: 'utf8' });
    const lines = out.split('\n');
    for (const line of lines) {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 2) {
        const [tty, comm] = parts;
        if (comm.toLowerCase().includes('luvus') && tty && tty !== '?' && tty !== '??') {
          const ttyPath = tty.startsWith('/dev/') ? tty : `/dev/${tty}`;
          if (fs.existsSync(ttyPath)) return ttyPath;
        }
      }
    }
  } catch (_) {}

  return null;
}

/**
 * Writes OSC 0 title escape sequence directly to host terminal PTY.
 */
function writeTerminalTitle(title) {
  const osc = `\x1b]0;${title}\x07`;
  const ttyPath = findTargetTTY();
  if (ttyPath) {
    try {
      fs.writeFileSync(ttyPath, osc);
      return true;
    } catch (err) {
      console.error(`[muh.status-title] failed writing to ${ttyPath}: ${err.message}`);
    }
  }

  // Fallback to process.stdout
  try {
    process.stdout.write(osc);
    return true;
  } catch (_) {
    return false;
  }
}

/**
 * Fetches agent list and updates terminal title via direct Unix Socket JSON-RPC.
 * Returns true on success, false on failure (which triggers CLI fallback).
 */
function syncViaSocket(socketPath, hostname) {
  return new Promise((resolve) => {
    let settled = false;
    let buffer = '';

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

  if (isTest) {
    runSelfTests();
    return true;
  }

  const hostname = getHostname();
  const socketPath = resolveSocketPath();
  const luvusBin = process.env.LUVUS_BIN_PATH || 'luvus';

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
    console.log(`[Luvus StatusTitle DryRun] Target TTY: ${targetTTY || 'none'}`);
    console.log(`[Luvus StatusTitle DryRun] Agents: ${statuses.join(', ')}`);
    console.log(`[Luvus StatusTitle DryRun] Title: "${title}"`);
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
 * Self tests to verify sorting and formatting logic.
 */
function runSelfTests() {
  console.log('Running Luvus status formatting tests...');

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
  findTargetTTY,
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
module_list_output=$("$LUVUS_BIN" module list 2>&1 || true)
if echo "$module_list_output" | grep -Fq 'muh.status-title'; then
    ok "Module muh.status-title is already registered in Luvus."
    "$LUVUS_BIN" module enable "muh.status-title" >/dev/null 2>&1 || true
else
    if ! link_output=$("$LUVUS_BIN" module link "$MODULE_DIR" 2>&1); then
        err "Failed to register module:"
        printf '%s\n' "$link_output"
        exit 1
    fi
fi

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
