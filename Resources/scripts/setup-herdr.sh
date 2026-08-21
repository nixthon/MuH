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
    for candidate in "$HOME/.nvm/versions/node"/*"/bin/node" "$HOME/.fnm/current/bin/node" "$HOME/.asdf/shims/node" "$HOME/.pixi/bin/node" "$HOME/.local/bin/node" "/usr/local/bin/node"; do
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
command = ["node", "index.js"]

[[events]]
on = "pane.agent_status_changed"
command = ["node", "index.js"]

[[events]]
on = "pane.agent_detected"
command = ["node", "index.js"]

[[events]]
on = "pane.created"
command = ["node", "index.js"]

[[events]]
on = "pane.closed"
command = ["node", "index.js"]

[[events]]
on = "workspace.focused"
command = ["node", "index.js"]

[[events]]
on = "tab.focused"
command = ["node", "index.js"]

[[actions]]
id = "sync"
title = "Sync status title"
contexts = ["workspace"]
command = ["node", "index.js"]
MUH_PLUGIN_MANIFEST
# END GENERATED PLUGIN MANIFEST

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

const STATUS_CONFIG = {
  blocked: { weight: 1, symbol: '×' }, // 阻塞 / 需要确认
  done:    { weight: 2, symbol: '✓' }, // 完成待查看
  working: { weight: 3, symbol: '◐' }, // 正在执行
  idle:    { weight: 4, symbol: '○' }, // 空闲
  unknown: { weight: 5, symbol: '·' }, // 未知
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

  // 2. 超过 5 个只截取前 5 个最关键的状态符号
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
 * Fetches the current agent list from Herdr.
 */
function fetchAgentList(herdrBin) {
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
  } catch (err) {
    // ignore
  }
  return [];
}

/**
 * Sets the outer terminal title via socket or CLI fallback.
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

function setOuterWindowTitle(title, socketPath, herdrBin) {
  if (!socketPath) {
    return Promise.resolve(setOuterWindowTitleViaCLI(title, herdrBin));
  }

  return new Promise(resolve => {
    let connected = false;
    let settled = false;
    const client = net.createConnection(socketPath);

    const finish = result => {
      if (settled) return;
      settled = true;
      client.destroy();
      resolve(result);
    };

    client.setTimeout(1000, () => {
      if (!connected) {
        finish(setOuterWindowTitleViaCLI(title, herdrBin));
      } else {
        finish(false);
      }
    });

    client.once('connect', () => {
      connected = true;
      const req = {
        id: 'muh-status-title-set',
        method: 'client.window_title.set',
        params: { title },
      };
      client.end(JSON.stringify(req) + '\n', () => finish(true));
    });

    client.once('error', () => {
      if (!connected) {
        finish(setOuterWindowTitleViaCLI(title, herdrBin));
      } else {
        finish(false);
      }
    });
  });
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
    return;
  }

  const herdrBin = process.env.HERDR_BIN_PATH || 'herdr';
  const socketPath = process.env.HERDR_SOCKET_PATH;
  const hostname = getHostname();

  const agents = fetchAgentList(herdrBin);
  const statuses = agents.map(a => a.agent_status || a.status || 'unknown');

  const symbols = formatAgentStatusSymbols(statuses);
  const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;

  if (isDryRun) {
    console.log(`[StatusTitle DryRun] Agents: ${statuses.join(', ')}`);
    console.log(`[StatusTitle DryRun] Title: "${title}"`);
    return;
  }

  return setOuterWindowTitle(title, socketPath, herdrBin);
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

chmod +x "$PLUGIN_DIR/index.js"
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
if ! node "$PLUGIN_DIR/index.js"; then
    warn "Initial status synchronization failed; the plugin is registered and will retry on Herdr events."
fi

printf "\n${COLOR_GREEN}${COLOR_BOLD}✔ Herdr setup for MuH completed successfully!${COLOR_NC}\n\n"
