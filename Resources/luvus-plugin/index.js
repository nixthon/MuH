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
 * Writes OSC 0 title escape sequence directly to host terminal PTYs (non-blocking).
 */
function writeTerminalTitle(title) {
  const osc = `\x1b]0;${title}\x07`;
  let successCount = 0;

  // 1. Direct target TTY from environment or parent tree
  const ttyPath = findTargetTTY();
  if (ttyPath) {
    try {
      const fd = fs.openSync(ttyPath, fs.constants.O_WRONLY | fs.constants.O_NONBLOCK);
      fs.writeSync(fd, osc);
      fs.closeSync(fd);
      successCount++;
    } catch (_) {}
  }

  // 2. Broadcast non-blockingly to all active user PTYs (/dev/pts/* on Linux, /dev/ttys* on macOS)
  try {
    const ptsDir = '/dev/pts';
    if (fs.existsSync(ptsDir)) {
      const entries = fs.readdirSync(ptsDir);
      for (const entry of entries) {
        if (/^\d+$/.test(entry)) {
          const pty = path.join(ptsDir, entry);
          try {
            const fd = fs.openSync(pty, fs.constants.O_WRONLY | fs.constants.O_NONBLOCK);
            fs.writeSync(fd, osc);
            fs.closeSync(fd);
            successCount++;
          } catch (_) {}
        }
      }
    }
  } catch (_) {}

  // 3. Fallback to process.stdout
  try {
    process.stdout.write(osc);
    successCount++;
  } catch (_) {}

  return successCount > 0;
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
    process.exit(result === false ? 1 : 0);
  })
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });

module.exports = {
  formatAgentStatusSymbols,
  getHostname,
  findTargetTTY,
  STATUS_CONFIG,
  MAX_INDICATORS,
};
