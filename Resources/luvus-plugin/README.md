# MuH Status Title Module for Luvus

This module connects [Luvus](https://github.com/RizRiyz/luvus) sessions with **MuH (Multiplexing Host Manager)**.

## Components & Versions

- **Status Title Module**: `v0.1.2` (`luvus-module.toml` & `index.js`)
- **Pi Detection Manifest**: `v1.0.0` (`pi-manifest.toml` -> `~/.luvus/manifests/pi.toml`)
- **Pi Native Extension**: `v1.3.0` (`pi-extension.ts` -> `~/.pi/agent/extensions/luvus-agent-state.ts`)

## How It Works

1. **Pi Native Integration (`v1.0.0`)**: Listens to Pi agent lifecycle events (`agent_start`, `herdr:blocked`, `agent_settled`, `session_shutdown`) and reports state via Unix Socket JSON-RPC (`agent.report` / `agent.release`).
2. **Pi Detection Manifest (`v1.0.0`)**: Declares `[identity]` and state detection rules for Luvus v0.13.1+ process & screen scanners.
3. **Status Title Module (`v0.1.1`)**:
   - Listens to Luvus pane and workspace events.
   - Queries live agents via Unix Socket JSON-RPC (`$LUVUS_SOCKET_PATH`).
   - Aggregates and sorts all living agent vital signs by priority:
     - 🔴 **`×` (blocked)**: Priority 1 (human confirmation/attention required).
     - 🟢 **`✓` (done)**: Priority 2 (completed tasks awaiting review).
     - 🟡 **`◐` (working)**: Priority 3 (active execution/thinking).
     - 🟢 **`○` (idle)**: Priority 4 (ready/idle standby agent).
   - Formats title strictly: 1 symbol = 1 living agent (e.g. `dev2: ◐○`); 0 agents = `dev2: idle`.
   - Strictly resolves local controlling PTY while filtering out all SSH tunnels to prevent cross-host title pollution.
   - Writes OSC 0 sequence to outer host PTY, captured by MuH's native Ghostty engine.
