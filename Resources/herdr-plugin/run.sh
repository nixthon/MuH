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
