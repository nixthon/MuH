// installed by MuH / Luvus Integration
// LUVUS_INTEGRATION_ID=pi
// LUVUS_INTEGRATION_VERSION=1.0.0
// @ts-nocheck

import net from "node:net";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { spawn } from "node:child_process";

const EXTENSION_VERSION = "1.0.0";
const LUVUS_ENV = process.env.LUVUS_ENV;
const rawSocketPath = process.env.LUVUS_SOCKET_PATH;
const paneId = process.env.LUVUS_PANE_ID;
const luvusBin = process.env.LUVUS_BIN_PATH || "luvus";
const source = "pi";

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
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return null;
}

function enabled(): boolean {
  return (LUVUS_ENV === "1" || !!process.env.LUVUS_PANE_ID) && !!paneId;
}

function sendSocketRequest(socketPath: string, request: unknown, timeoutMs = 500): Promise<boolean> {
  return new Promise((resolve) => {
    let done = false;
    let timer: ReturnType<typeof setTimeout> | undefined;

    const finish = (ok: boolean) => {
      if (done) return;
      done = true;
      if (timer) clearTimeout(timer);
      try {
        socket.destroy();
      } catch (_) {}
      resolve(ok);
    };

    const socket = net.createConnection(socketPath);
    socket.on("error", () => finish(false));
    socket.on("connect", () => {
      socket.write(`${JSON.stringify(request)}\n`);
    });
    socket.on("data", () => finish(true));
    socket.on("end", () => finish(false));

    timer = setTimeout(() => finish(false), timeoutMs);
    timer.unref?.();
  });
}

function sendCliReport(status: string, message?: string): void {
  try {
    const args = ["agent", "report", paneId!, "--source", source, "--agent", "pi", "--status", status];
    if (message) {
      args.push("--message", message);
    }
    const child = spawn(luvusBin, args, {
      stdio: "ignore",
      detached: true,
    });
    child.unref();
  } catch (_) {}
}

function sendCliRelease(): void {
  try {
    const child = spawn(luvusBin, ["agent", "release", paneId!, "--source", source], {
      stdio: "ignore",
      detached: true,
    });
    child.unref();
  } catch (_) {}
}

type AgentState = "working" | "blocked" | "done" | "idle";

let reportSeq = Date.now();
let currentSessionId: string | undefined;

function updateSessionRef(ctx: any): void {
  try {
    const id = ctx?.sessionManager?.getSessionId?.();
    if (typeof id === "string" && id.length > 0) {
      currentSessionId = id;
    }
  } catch (_) {}
}

async function reportState(state: AgentState, message?: string): Promise<void> {
  if (!enabled()) return;

  reportSeq += 1;
  const socketPath = resolveSocketPath();

  if (socketPath) {
    const req = {
      id: `pi:report:${reportSeq}`,
      method: "agent.report",
      params: {
        pane: paneId,
        source,
        agent: "pi",
        status: state,
        message: message || undefined,
        session: currentSessionId || undefined,
      },
    };
    const ok = await sendSocketRequest(socketPath, req, 500);
    if (ok) return;
  }

  // CLI fallback
  sendCliReport(state, message);
}

async function releaseState(): Promise<void> {
  if (!enabled()) return;

  reportSeq += 1;
  const socketPath = resolveSocketPath();

  if (socketPath) {
    const req = {
      id: `pi:release:${reportSeq}`,
      method: "agent.release",
      params: {
        pane: paneId,
        source,
      },
    };
    const ok = await sendSocketRequest(socketPath, req, 500);
    if (ok) return;
  }

  // CLI fallback
  sendCliRelease();
}

export default function (pi: any) {
  if (!enabled()) {
    return;
  }

  let agentActive = false;
  let blockedCount = 0;
  let blockedMessage: string | undefined;
  let lastState: AgentState | undefined;

  function evaluateState(): { state: AgentState; message?: string } {
    if (blockedCount > 0) {
      return { state: "blocked", message: blockedMessage };
    }
    if (agentActive) {
      return { state: "working" };
    }
    return { state: "idle" };
  }

  function publishState(force = false) {
    const current = evaluateState();
    if (!force && current.state === lastState) {
      return;
    }
    lastState = current.state;
    void reportState(current.state, current.message);
  }

  // Blocked events (confirmations / user choices)
  pi.events?.on?.("herdr:blocked", (data: any) => {
    if (!data?.active) {
      blockedCount = Math.max(0, blockedCount - 1);
      if (blockedCount === 0) blockedMessage = undefined;
      publishState();
      return;
    }
    blockedCount += 1;
    blockedMessage = data.label || "Awaiting user confirmation";
    publishState();
  });

  // Session lifecycle
  pi.on("session_start", async (event: any, ctx: any) => {
    updateSessionRef(ctx);
    agentActive = ctx?.isIdle?.() === false;
    publishState(true);
  });

  pi.on("session_shutdown", async () => {
    void releaseState();
  });

  // Prompt / turn execution lifecycle
  pi.on("before_agent_start", (_event: any, ctx: any) => {
    updateSessionRef(ctx);
    agentActive = true;
    publishState();
  });

  pi.on("agent_start", (_event: any, ctx: any) => {
    updateSessionRef(ctx);
    agentActive = true;
    publishState();
  });

  pi.on("turn_start", (_event: any, ctx: any) => {
    updateSessionRef(ctx);
    agentActive = true;
    publishState();
  });

  pi.on("agent_end", (_event: any, ctx: any) => {
    updateSessionRef(ctx);
    agentActive = false;
    publishState();
  });

  pi.on("agent_settled", (_event: any, ctx: any) => {
    updateSessionRef(ctx);
    agentActive = false;
    publishState();
  });
}
