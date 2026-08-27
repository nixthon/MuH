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

const MODULE_VERSION = '0.1.1';

const STATUS_CONFIG = {
  blocked: { weight: 1, symbol: '×' }, // 🔴 阻塞 / 需要人类介入确认
  done:    { weight: 2, symbol: '✓' }, // 🟢 任务完成待查看
  working: { weight: 3, symbol: '◐' }, // 🟡 正在执行中
  idle:    { weight: 4, symbol: '○' }, // 🟢 存活空闲待命 (绿色圆圈)
  unknown: { weight: 5, symbol: '·' }, // 未知状态
};

const MAX_INDICATORS = 10;

/**
 * Formats a list of agent status strings into a concise symbols string.
 * - blocked (×): 🔴 阻塞需确认
 * - done (✓): 🟢 完成待查看
 * - working (◐): 🟡 正在执行
 * - idle (○): 🟢 存活空闲待命 (绿色圆圈)
 * 
 * Rules:
 * - Each symbol represents one living agent in the session.
 * - When agent count is 0 (no agents in session), returns '' so title formats as "hostname: idle" (zero symbols).
 * - When agents are present, sorted by priority (blocked > done > working > idle) and capped at MAX_INDICATORS (10).
 * 
 * @param {string[]} statuses Array of agent status strings (e.g. ['blocked', 'working', 'done', 'idle'])
 * @returns {string} Combined symbols string (e.g. "×✓◐○")
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
    path.join(home, '.luvus', 'luvus.sock'),
    path.join(home, '.luvus', 'luvus-client.sock'),
    path.join(home, '.local', 'share', 'luvus', 'luvus.sock'),
    path.join(home, '.config', 'luvus', 'luvus.sock'),
    path.join('/tmp', `luvus-${process.getuid?.() || 1000}`, 'luvus.sock'),
    path.join('/tmp', 'luvus.sock'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return null;
}

/**
 * Checks if a command line string represents an interactive Luvus TUI client process.
 * Strictly excludes SSH clients, remote tunnels, wrappers, shells, editors, daemons,
 * and one-off subcommands (e.g. `ssh -t host luvus`, `luvus server`, `luvus module ...`).
 *
 * @param {string} cmd Full command line string from ps
 * @param {string} [currentSession] Optional targeted session name (e.g. "default", "docs")
 * @returns {boolean}
 */
function isInteractiveLuvusClient(cmd, currentSession = '') {
  if (!cmd || typeof cmd !== 'string') return false;

  const trimmed = cmd.trim();
  if (!trimmed) return false;

  const tokens = trimmed.split(/\s+/);
  if (tokens.length === 0) return false;

  const binPath = tokens[0];
  const binName = path.basename(binPath).toLowerCase();

  // 1. Strictly exclude SSH clients, remote wrappers, editors, interpreters, shells
  const forbiddenBins = new Set([
    'ssh', 'sshd', 'mosh', 'mosh-client', 'mosh-server', 'scp', 'sftp',
    'grep', 'egrep', 'rg', 'ag', 'ps', 'top', 'htop', 'btop',
    'vim', 'nvim', 'vi', 'nano', 'emacs', 'cat', 'less', 'more',
    'node', 'bash', 'zsh', 'sh', 'fish', 'dash', 'tmux', 'screen'
  ]);
  if (forbiddenBins.has(binName)) {
    return false;
  }

  // 2. The executable must be "luvus"
  if (binName !== 'luvus') {
    return false;
  }

  // 3. Inspect arguments to filter out non-TUI subcommands
  const subcommands = tokens.slice(1);
  const nonTuiSubcommands = new Set([
    'server', 'module', 'agent', 'pane', 'tab', 'workspace', 'task', 'lease',
    'files', 'git', 'diff', 'worktree', 'theme', 'bar', 'ui', 'integration',
    'skill', 'wait', 'search', 'events', 'uhp', 'doctor', 'update', 'ping', 'help'
  ]);

  let hasSessionFlag = false;
  let sessionName = '';

  for (let i = 0; i < subcommands.length; i++) {
    const arg = subcommands[i];
    if (arg === '--session' || arg === '-s') {
      hasSessionFlag = true;
      sessionName = subcommands[i + 1] || '';
      i++;
      continue;
    }
    if (arg.startsWith('--session=')) {
      hasSessionFlag = true;
      sessionName = arg.slice(10);
      continue;
    }
    if (arg.startsWith('-')) {
      continue;
    }

    // Positional subcommand argument
    if (arg === 'attach') {
      // `luvus attach <pane>` launches fullscreen TUI for a single pane, valid client
      break;
    }
    if (nonTuiSubcommands.has(arg)) {
      return false;
    }
    // Any unrecognized positional argument is assumed not to be an interactive TUI launcher
    return false;
  }

  // 4. Session matching
  const targetSession = currentSession || process.env.LUVUS_SESSION || '';
  if (targetSession && targetSession !== 'default') {
    if (hasSessionFlag && sessionName && sessionName !== targetSession) {
      return false;
    }
  } else {
    // Default session: client should not target a different named session
    if (hasSessionFlag && sessionName && sessionName !== 'default') {
      return false;
    }
  }

  return true;
}

/**
 * Finds the controlling PTY device of the outer terminal session.
 * Strictly resolves to the single TTY belonging to this Luvus session to prevent
 * cross-talk across hosts/tabs.
 */
function findTargetTTY() {
  // 1. Direct environment variable
  if (process.env.SSH_TTY && fs.existsSync(process.env.SSH_TTY)) return process.env.SSH_TTY;
  if (process.env.TTY && fs.existsSync(process.env.TTY)) return process.env.TTY;

  // 2. Direct /dev/tty check (only if valid character device)
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

  // 4. Scan the foreground luvus client process attached to a TTY for this session
  try {
    const currentSession = process.env.LUVUS_SESSION || '';
    const out = execSync('ps -eo pid=,tty=,args=', { encoding: 'utf8' });
    const lines = out.split('\n');
    for (const line of lines) {
      const parts = line.trim().split(/\s+/);
      if (parts.length >= 3) {
        const [pid, tty, ...cmdParts] = parts;
        const cmd = cmdParts.join(' ');
        if (tty && tty !== '?' && tty !== '??') {
          if (isInteractiveLuvusClient(cmd, currentSession)) {
            const ttyPath = tty.startsWith('/dev/') ? tty : `/dev/${tty}`;
            if (fs.existsSync(ttyPath)) return ttyPath;
          }
        }
      }
    }
  } catch (_) {}

  return null;
}

/**
 * Writes OSC 0 title escape sequence strictly to the target host terminal PTY.
 * No global broadcasting to ensure zero cross-host interference.
 */
function writeTerminalTitle(title) {
  const osc = `\x1b]0;${title}\x07`;

  // 1. Direct target TTY belonging to this session
  const ttyPath = findTargetTTY();
  if (ttyPath) {
    try {
      const fd = fs.openSync(ttyPath, fs.constants.O_WRONLY | fs.constants.O_NONBLOCK);
      fs.writeSync(fd, osc);
      fs.closeSync(fd);
      return true;
    } catch (_) {}
  }

  // 2. Fallback to process.stdout if connected to a TTY
  try {
    if (process.stdout.isTTY) {
      process.stdout.write(osc);
      return true;
    }
  } catch (_) {}

  return false;
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
  const isVersion = args.includes('--version') || args.includes('-v');

  if (isVersion) {
    console.log(`muh.status-title v${MODULE_VERSION}`);
    return true;
  }

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
    console.log(`[Luvus StatusTitle v${MODULE_VERSION} DryRun] Target TTY: ${targetTTY || 'none'}`);
    console.log(`[Luvus StatusTitle v${MODULE_VERSION} DryRun] Agents: ${statuses.join(', ')}`);
    console.log(`[Luvus StatusTitle v${MODULE_VERSION} DryRun] Title: "${title}"`);
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
 * Self tests to verify sorting, formatting, and client filtering logic.
 */
function runSelfTests() {
  console.log('Running Luvus status formatting and client filter tests...');

  const formattingTestCases = [
    {
      name: '0 agents (empty array) emits empty symbols string for hostname: idle',
      input: [],
      expected: '',
    },
    {
      name: 'Single agent idle (green circle)',
      input: ['idle'],
      expected: '○',
    },
    {
      name: 'Two agents idle (two green circles)',
      input: ['idle', 'idle'],
      expected: '○○',
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
      name: 'Mixed states with working, blocked, done, and idle',
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
  for (const tc of formattingTestCases) {
    const actual = formatAgentStatusSymbols(tc.input);
    if (actual === tc.expected) {
      console.log(`  ✓ ${tc.name}: "${actual}"`);
      passed++;
    } else {
      console.error(`  ✗ ${tc.name}: expected "${tc.expected}", got "${actual}"`);
    }
  }

  const clientFilterTestCases = [
    {
      name: 'SSH command should NEVER be matched as local luvus client',
      cmd: 'ssh -t dq-wy-inf1 luvus',
      expected: false,
    },
    {
      name: 'SSH command with path should NEVER be matched',
      cmd: '/usr/bin/ssh -t dev2 luvus',
      expected: false,
    },
    {
      name: 'Pure luvus command is interactive TUI client',
      cmd: 'luvus',
      expected: true,
    },
    {
      name: 'Luvus with binary path is interactive client',
      cmd: '/Users/test/.local/bin/luvus',
      expected: true,
    },
    {
      name: 'Luvus attach is interactive client',
      cmd: 'luvus attach 4',
      expected: true,
    },
    {
      name: 'Luvus server is daemon, NOT interactive client',
      cmd: 'luvus server',
      expected: false,
    },
    {
      name: 'Luvus module run is one-off CLI, NOT interactive client',
      cmd: 'luvus module run muh.status-title sync',
      expected: false,
    },
    {
      name: 'Luvus agent list is CLI command, NOT interactive client',
      cmd: 'luvus agent list',
      expected: false,
    },
    {
      name: 'Mosh client is NOT luvus client',
      cmd: 'mosh-client user@remote',
      expected: false,
    },
    {
      name: 'Matching specific session',
      cmd: 'luvus --session docs',
      session: 'docs',
      expected: true,
    },
    {
      name: 'Mismatching specific session',
      cmd: 'luvus --session other',
      session: 'docs',
      expected: false,
    },
  ];

  for (const tc of clientFilterTestCases) {
    const actual = isInteractiveLuvusClient(tc.cmd, tc.session || '');
    if (actual === tc.expected) {
      console.log(`  ✓ [Filter] ${tc.name}: ${actual}`);
      passed++;
    } else {
      console.error(`  ✗ [Filter] ${tc.name}: expected ${tc.expected}, got ${actual}`);
    }
  }

  const total = formattingTestCases.length + clientFilterTestCases.length;
  console.log(`Test results: ${passed}/${total} passed.`);
  if (passed !== total) {
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
  MODULE_VERSION,
  formatAgentStatusSymbols,
  getHostname,
  findTargetTTY,
  isInteractiveLuvusClient,
  STATUS_CONFIG,
  MAX_INDICATORS,
};
