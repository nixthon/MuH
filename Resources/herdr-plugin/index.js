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
    } catch (_) {
      // socket write failed, fallback to CLI
    }
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

/**
 * Main execution function.
 */
function run() {
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

  setOuterWindowTitle(title, socketPath, herdrBin);
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
run();

module.exports = {
  formatAgentStatusSymbols,
  getHostname,
  STATUS_CONFIG,
  MAX_INDICATORS,
};
