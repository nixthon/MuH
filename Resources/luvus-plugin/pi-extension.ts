// installed by MuH / Luvus Integration
// LUVUS_INTEGRATION_ID=pi
// LUVUS_INTEGRATION_VERSION=1.3.2
// @ts-nocheck

import net from "node:net";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn, spawnSync } from "node:child_process";

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

function shouldKeepAuthority(reason?: string): boolean {
  // Session replacement immediately starts a new TUI instance that re-reports.
  // Any other reason (quit, signals, missing reason) means this Pi is gone.
  return reason === "reload" || reason === "new" || reason === "resume" || reason === "fork";
}

function sendCliRelease(): boolean {
  try {
    const res = spawnSync(luvusBin, ["agent", "release", paneId!, "--source", source], {
      stdio: "ignore",
      timeout: 2000,
    });
    return res.status === 0;
  } catch {
    return false;
  }
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
    const params: Record<string, unknown> = {
      pane: paneId,
      source,
      agent: "pi",
      status: state,
      ttl_s: LEASE_TTL_SECONDS,
    };
    if (message) params.message = message;
    // Luvus 0.13.1 rejects unknown parameter `session`; the field is `session_id`.
    if (currentSessionId) params.session_id = currentSessionId;

    const delivered = await sendRequest({
      id: `pi:report:${paneId}:${requestId}`,
      method: "agent.report",
      params,
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
    // Shutdown races process.exit(); a detached CLI child would be killed.
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
    const wasRoot = rootSession;
    rootSession = false;
    stopHeartbeat();
    await reportChain.catch(() => {});
    if (!wasRoot) return;

    // Reload/session replacement immediately establishes a fresh authority.
    // Ctrl+C / Ctrl+D / SIGTERM / /quit all tear the interactive Pi down.
    if (!shouldKeepAuthority(event?.reason)) {
      await releaseState();
    }
  });
}
