#!/usr/bin/env node

/**
 * plogr-workflow HUD — Real-time TrueColor ANSI Glowing Pipeline HUD
 *
 * Runs as a standalone TUI status watcher or in a dedicated 1-line Herdr pane.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const projectRoot = process.argv[2] || process.cwd();
const isLive = process.argv.includes('--live') || process.argv.includes('-l') || process.argv.includes('--watch');
const isPopup = process.argv.includes('--popup');

function findActiveWorkflow(root) {
  if (root && root.endsWith('.json') && fs.existsSync(root)) {
    try { return JSON.parse(fs.readFileSync(root, 'utf8')); } catch { return null; }
  }
  const herdrDir = path.join(root, 'herdr');
  if (!fs.existsSync(herdrDir)) return null;

  function scanDir(dir) {
    let results = [];
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const e of entries) {
      const full = path.join(dir, e.name);
      if (e.isDirectory()) {
        results = results.concat(scanDir(full));
      } else if (e.isFile() && e.name === 'workflow.json') {
        results.push(full);
      }
    }
    return results;
  }

  const allWf = scanDir(herdrDir);
  if (!allWf.length) return null;

  allWf.sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);

  for (const wfPath of allWf) {
    try {
      const data = JSON.parse(fs.readFileSync(wfPath, 'utf8'));
      if (['executing', 'candidate', 'verifying', 'repairing'].includes(data.state)) {
        return data;
      }
    } catch {}
  }

  try {
    return JSON.parse(fs.readFileSync(allWf[0], 'utf8'));
  } catch {
    return null;
  }
}

function getGlowColor(offset = 0) {
  const t = Date.now() / 350.0 + offset;
  const r = Math.floor(146 + 90 * Math.sin(t));
  const g = Math.floor(130 + 59 * Math.sin(t + 2.094));
  const b = Math.floor(200 + 48 * Math.sin(t + 4.188));
  return [r, g, b];
}

function renderHud(wf) {
  const esc = '\x1b';
  const reset = `${esc}[0m`;
  const green = `${esc}[38;2;34;197;94m`;
  const gray = `${esc}[38;2;100;116;139m`;
  const [r, g, b] = getGlowColor(0);
  const glow = `${esc}[1;38;2;${r};${g};${b}m`;

  if (!wf) {
    return `${glow} 🚀 PLOGR${reset} ${gray}❯❯ [ ○ 空闲 IDLE ] • 暂无活跃工作流${esc}[K`;
  }

  const state = wf.state || 'idle';
  const mode = wf.mode || 'task';
  const repairRound = wf.repair_round || 0;
  const matrix = Array.isArray(wf.matrix) ? wf.matrix : (wf.matrix ? [wf.matrix] : null);

  // Matrix Parallel View
  if (matrix && matrix.length > 0) {
    const badges = matrix.map((m, idx) => {
      const isDone = ['candidate', 'merged', 'done'].includes(m.status);
      if (isDone) {
        return `${green}[✔ ${m.id}]${reset}`;
      }
      const [mr, mg, mb] = getGlowColor(idx * 1.5);
      const mGlow = `${esc}[1;38;2;${mr};${mg};${mb}m`;
      return `${mGlow}⟪⚙️ ${m.id} (${m.agent || 'Agent'})⟫${reset}`;
    });

    const verIcon = state === 'verifying' ? `${glow}⟪🛡️ VERIFIER 验收中⟫${reset}` : (state === 'merged' ? `${green}[✔ VERIFIER]${reset}` : `${gray}[○ VERIFIER]${reset}`);
    const mergeIcon = state === 'merged' ? `${green}[✨ MERGED]${reset}` : `${gray}[○ MERGE]${reset}`;

    return `${glow} 🚀 PLOGR${reset} ${gray}❯❯ [✔ INIT] ══▶${reset} ${glow}⟪⚡ 并行(${matrix.length}): ${badges.join(' ')} ⟫${reset} ${gray}══▶${reset} ${verIcon} ${gray}┄▷${reset} ${mergeIcon}${esc}[K`;
  }

  // Linear Pipeline View
  const auditNode = mode === 'bugfix'
    ? (state === 'executing' && wf.next_role === 'task' && repairRound === 0 ? `${glow}⟪🔍 ROOT-CAUSE 诊断中⟫${reset}` : `${green}[✔ ROOT-CAUSE]${reset}`)
    : `${green}[✔ INIT]${reset}`;

  const taskNode = (state === 'executing' || state === 'repairing')
    ? `${glow}⟪⚙️ TASK (${wf.task?.active_agent_name || 'Agent'}${repairRound > 0 ? ` 修复轮次:${repairRound}` : ''})⟫${reset}`
    : (['verifying', 'merged', 'passed'].includes(state) ? `${green}[✔ TASK]${reset}` : `${gray}[○ TASK]${reset}`);

  const verifierNode = state === 'verifying'
    ? `${glow}⟪🛡️ VERIFIER (5重门禁独立验收)⟫${reset}`
    : (['merged', 'passed'].includes(state) ? `${green}[✔ VERIFIER]${reset}` : `${gray}[○ VERIFIER]${reset}`);

  const mergedNode = (state === 'merged' || state === 'passed')
    ? `${green}⟪✨ MERGED 已合入主分支⟫${reset}`
    : (state === 'blocked' ? `${esc}[1;38;2;239;68;68m⟪⛔ BLOCKED 熔断阻断⟫${reset}` : `${gray}[○ MERGE]${reset}`);

  const a1 = ['executing', 'verifying', 'merged', 'passed'].includes(state) ? `${green}──▶${reset}` : `${gray}┄▷${reset}`;
  const a2 = ['verifying', 'merged', 'passed'].includes(state) ? `${green}──▶${reset}` : (['executing', 'repairing'].includes(state) ? `${glow}══▶${reset}` : `${gray}┄▷${reset}`);
  const a3 = ['merged', 'passed'].includes(state) ? `${green}──▶${reset}` : (state === 'verifying' ? `${glow}══▶${reset}` : `${gray}┄▷${reset}`);

  return `${glow} 🚀 PLOGR${reset} ${gray}❯❯${reset} ${auditNode} ${a1} ${taskNode} ${a2} ${verifierNode} ${a3} ${mergedNode}${esc}[K`;
}

function runLoop() {
  process.stdout.write('\x1b[?25l'); // Hide cursor
  const interval = setInterval(() => {
    const wf = findActiveWorkflow(projectRoot);
    const line = renderHud(wf);
    process.stdout.write(`\r${line}`);
  }, 120);

  process.on('SIGINT', () => {
    clearInterval(interval);
    process.stdout.write('\x1b[?25h\n'); // Restore cursor
    process.exit(0);
  });

  process.on('exit', () => {
    process.stdout.write('\x1b[?25h\n');
  });
}

function runOnce() {
  const wf = findActiveWorkflow(projectRoot);
  console.log(renderHud(wf));
}

if (isLive || isPopup) {
  runLoop();
} else {
  runOnce();
}
