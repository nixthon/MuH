# MuH Status Title Module for Luvus

This module connects [Luvus](https://github.com/RizRiyz/luvus) sessions with **MuH (Multiplexing Host Manager)**.

## How It Works

1. Listens to `pane.agent_status_changed`, `pane.created`, `pane.closed`, and `workspace.*` events emitted by Luvus.
2. Queries the live agent list via Unix Socket JSON-RPC (`$LUVUS_SOCKET_PATH`) or CLI fallback (`luvus agent list`).
3. Aggregates and sorts all living agent vital signs by priority:
   - 🔴 **`×` (blocked)**: Highest priority (requires human confirmation/attention).
   - 🟢 **`✓` (done)**: Completed tasks awaiting review.
   - 🟡 **`◐` (working)**: Active task execution.
   - 🟢 **`○` (idle)**: Living agent in ready/idle standby state.
4. Formats the title string:
   - 1 symbol = 1 living agent (e.g. `dev2: ◐○` for 1 working + 1 idle agent).
   - When 0 agents are alive, outputs `dev2: idle` with zero symbols.
   - Writes directly to the host TTY as an OSC 0 terminal title sequence.
5. MuH's native Ghostty engine intercepts OSC 0, updating the sidebar dashboard and triggering notifications.
