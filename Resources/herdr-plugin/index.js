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
const path = require('node:path');
const fs = require('node:fs');

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
  const raw = process.env.HERDR_HOSTNAME || os.hostname() || 'herdr';
  return raw.split('.')[0];
}

/**
 * Probe default Herdr Unix socket path if not provided in environment.
 */
function resolveSocketPath() {
  if (process.env.HERDR_SOCKET_PATH && fs.existsSync(process.env.HERDR_SOCKET_PATH)) {
    return process.env.HERDR_SOCKET_PATH;
  }
  const home = os.homedir();
  const candidates = [
    path.join(home, '.config', 'herdr', 'herdr.sock'),
    path.join(home, '.local', 'share', 'herdr', 'herdr.sock'),
    path.join(home, '.herdr', 'herdr.sock'),
    path.join('/tmp', `herdr-${process.getuid?.() || 1000}`, 'herdr.sock'),
    path.join('/tmp', 'herdr.sock'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      return c;
    }
  }
  return null;
}

/**
 * Fetches agent list and updates terminal title via direct Unix Socket JSON-RPC.
 * Returns true on success, false on failure (which triggers CLI fallback).
 */
function syncViaSocket(socketPath, hostname) {
  return new Promise((resolve) => {
    let settled = false;
    let buffer = '';
    let stage = 'fetch'; // 'fetch' -> 'set' -> 'done'

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
      // Step 1: Request agent list
      const req = {
        id: 'muh-agent-list',
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
          if (stage === 'fetch' && resp.id === 'muh-agent-list') {
            const agents = resp.result?.agents && Array.isArray(resp.result.agents) ? resp.result.agents : [];
            const statuses = agents.map(a => a.agent_status || a.status || 'unknown');
            const symbols = formatAgentStatusSymbols(statuses);
            const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;

            stage = 'set';
            const setReq = {
              id: 'muh-title-set',
              method: 'client.window_title.set',
              params: { title },
            };
            client.write(JSON.stringify(setReq) + '\n');
          } else if (stage === 'set' && resp.id === 'muh-title-set') {
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
 * CLI Fallback: Fetches the current agent list from Herdr.
 */
function fetchAgentListCLI(herdrBin) {
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

/**
 * CLI Fallback: Sets the outer terminal title via Herdr CLI.
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
  const herdrBin = process.env.HERDR_BIN_PATH || 'herdr';

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
                resResolve(parsed.result?.agents || []);
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
      agents = fetchAgentListCLI(herdrBin);
    }
    const statuses = agents.map(a => a.agent_status || a.status || 'unknown');
    const symbols = formatAgentStatusSymbols(statuses);
    const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;
    console.log(`[StatusTitle DryRun] Agents: ${statuses.join(', ')}`);
    console.log(`[StatusTitle DryRun] Title: "${title}"`);
    return true;
  }

  // 1. Primary path: Native Unix Socket JSON-RPC
  if (socketPath) {
    const ok = await syncViaSocket(socketPath, hostname);
    if (ok) return true;
  }

  // 2. Fallback path: CLI subprocess
  const agents = fetchAgentListCLI(herdrBin);
  const statuses = agents.map(a => a.agent_status || a.status || 'unknown');
  const symbols = formatAgentStatusSymbols(statuses);
  const title = symbols ? `${hostname}: ${symbols}` : `${hostname}: idle`;
  return setOuterWindowTitleViaCLI(title, herdrBin);
}

/**
 * Self tests to verify sorting and formatting logic.
 */
function runSelfTests() {
  console.log('Running status formatting tests...');

  const testCases = [
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
