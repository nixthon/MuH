#!/usr/bin/env bash
# ==============================================================================
# MuH / Herdr Integration Initializer
# 
# Usage:
#   Local:   bash setup-herdr.sh
#   Remote:  ssh <user@host> 'bash -s' < setup-herdr.sh
# ==============================================================================

set -e

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

HERDR_VERSION=$(herdr --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")
ok "Found Herdr version: v${HERDR_VERSION}"

# Check Node.js
if ! command -v node >/dev/null 2>&1; then
    err "Node.js is not installed or not in PATH!"
    printf "Herdr plugins require Node.js runtime. Please install Node.js (v18+ recommended).\n\n"
    exit 1
fi

NODE_VERSION=$(node -v 2>&1 || echo "unknown")
ok "Found Node.js version: ${NODE_VERSION}"

# ------------------------------------------------------------------------------
# 2. Configure ~/.config/herdr/config.toml
# ------------------------------------------------------------------------------
info "Configuring Herdr settings..."

HERDR_CONFIG_DIR="$HOME/.config/herdr"
HERDR_CONFIG_FILE="$HERDR_CONFIG_DIR/config.toml"

mkdir -p "$HERDR_CONFIG_DIR"

if [ -f "$HERDR_CONFIG_FILE" ]; then
    if grep -q 'status_indicators' "$HERDR_CONFIG_FILE"; then
        ok "status_indicators already configured in config.toml"
    else
        printf "\n[ui]\nstatus_indicators = \"symbols\"\n" >> "$HERDR_CONFIG_FILE"
        ok "Added status_indicators = \"symbols\" to existing config.toml"
    fi
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

# Write manifest
cat << 'EOF' > "$PLUGIN_DIR/herdr-plugin.toml"
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
EOF

# Write index.js script
cat << 'EOF' > "$PLUGIN_DIR/index.js"
#!/usr/bin/env node

/**
 * MuH Status Title Plugin for Herdr
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

function formatAgentStatusSymbols(statuses) {
  if (!statuses || statuses.length === 0) return '';
  const sorted = statuses.slice().sort((a, b) => {
    const wa = STATUS_CONFIG[a]?.weight ?? 99;
    const wb = STATUS_CONFIG[b]?.weight ?? 99;
    return wa - wb;
  });
  const top = sorted.slice(0, MAX_INDICATORS);
  return top.map(status => STATUS_CONFIG[status]?.symbol ?? '·').join('');
}

function getHostname() {
  const raw = process.env.HERDR_HOSTNAME || os.hostname() || 'herdr';
  return raw.split('.')[0];
}

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
  } catch (_) {}
  return [];
}

function setOuterWindowTitle(title, socketPath, herdrBin) {
  if (socketPath) {
    try {
      const client = net.connect(socketPath);
      const req = {
        id: 'muh-status-title-set',
        method: 'client.window_title.set',
        params: { title },
      };
      client.write(JSON.stringify(req) + '\n');
      client.end();
      return true;
    } catch (_) {}
  }

  try {
    spawnSync(herdrBin, ['terminal', 'title', 'set', title], {
      encoding: 'utf8',
      stdio: ['ignore', 'ignore', 'ignore'],
      timeout: 3000,
    });
    return true;
  } catch (_) {
    return false;
  }
}

function run() {
  const herdrBin = process.env.HERDR_BIN_PATH || 'herdr';
  const socketPath = process.env.HERDR_SOCKET_PATH;
  const hostname = getHostname();

  const agents = fetchAgentList(herdrBin);
  const statuses = agents.map(a => a.agent_status || a.status || 'unknown');
  const symbols = formatAgentStatusSymbols(statuses);
  const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;

  setOuterWindowTitle(title, socketPath, herdrBin);
}

run();
EOF

chmod +x "$PLUGIN_DIR/index.js"
ok "Plugin files installed to $PLUGIN_DIR"

# ------------------------------------------------------------------------------
# 4. Link & Activate Plugin in Herdr
# ------------------------------------------------------------------------------
info "Linking plugin into Herdr..."
herdr plugin link "$PLUGIN_DIR" >/dev/null 2>&1 || true

# Verify link
if herdr plugin list 2>&1 | grep -q 'muh.status-title'; then
    ok "Plugin muh.status-title successfully registered and enabled!"
else
    warn "Plugin registered, please ensure herdr server is running."
fi

# Run initial sync test
info "Running initial status synchronization..."
node "$PLUGIN_DIR/index.js" || true

printf "\n${COLOR_GREEN}${COLOR_BOLD}✔ Herdr setup for MuH completed successfully!${COLOR_NC}\n\n"
