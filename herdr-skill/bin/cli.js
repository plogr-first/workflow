#!/usr/bin/env node

/**
 * plogr CLI — Unified Plogr & Herdr Terminal Launcher
 *
 * Typing `plogr` in any terminal (CMD, PowerShell, Git Bash) seamlessly
 * brings up the Herdr multiplexed terminal for the active project/session,
 * or dispatches workflows and real-time HUD dashboards.
 *
 * Usage:
 *   plogr                        # Instantly launch/attach Herdr multiplexed terminal
 *   plogr init                   # Initialize project dispatch profile & install skills
 *   plogr hud                    # Launch real-time TrueColor glowing HUD dashboard
 *   plogr status                 # Print current workflow status snapshot
 *   plogr popup                  # Open full multiline dashboard popup
 *   plogr task [prompt]          # Dispatch a task workflow
 *   plogr bugfix [prompt]        # Dispatch a bugfix workflow
 *   plogr parallel [matrix.json] # Dispatch a matrix parallel worktree workflow
 *   plogr prune                  # Auto-prune and clean up merged/stale worktrees
 *   plogr attach [session]       # Attach to a specific Herdr session
 *   plogr [herdr-command...]     # Pass through directly to herdr CLI
 */

"use strict";

const { spawn, execSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const scriptsDir = path.join(__dirname, "..", "scripts");
const initScript = path.join(scriptsDir, "Initialize-HerdrProject.ps1");
const workflowScript = path.join(scriptsDir, "Start-HerdrWorkflow.ps1");
const parallelScript = path.join(scriptsDir, "Start-HerdrParallelWorkflow.ps1");
const hudScript = path.join(__dirname, "hud.js");

// ── Find Herdr Executable ──────────────────────────────────────────
function findHerdr() {
  const candidates = [
    process.platform === "win32" ? "herdr.exe" : "herdr",
    path.join(process.env.LOCALAPPDATA || "", "Programs", "Herdr", "bin", "herdr.exe"),
    path.join(process.env.USERPROFILE || "", "AppData", "Local", "Programs", "Herdr", "bin", "herdr.exe")
  ];

  for (const candidate of candidates) {
    if (!candidate) continue;
    if (fs.existsSync(candidate)) return candidate;
    try {
      const checkCmd = process.platform === "win32" ? `where ${candidate} 2>nul` : `command -v ${candidate} 2>/dev/null`;
      const out = execSync(checkCmd, { encoding: "utf8", timeout: 3000 }).trim();
      if (out) return out.split(/\r?\n/)[0];
    } catch {}
  }
  return "herdr";
}

// ── Find PowerShell Host ──────────────────────────────────────────
function findPowerShell() {
  const candidates = process.platform === "win32" ? ["pwsh.exe", "powershell.exe"] : ["pwsh"];
  for (const cmd of candidates) {
    try {
      const checkCmd = process.platform === "win32" ? `where ${cmd} 2>nul` : `command -v ${cmd} 2>/dev/null`;
      const result = execSync(checkCmd, { encoding: "utf8", timeout: 3000 });
      if (result.trim()) return cmd;
    } catch {}
  }
  return "powershell.exe";
}

// ── Read Project Profile ──────────────────────────────────────────
function getProjectProfile(cwd = process.cwd()) {
  const profilePath = path.join(cwd, "herdr", "dispatch-profile.json");
  if (fs.existsSync(profilePath)) {
    try {
      // Windows PowerShell 5.1 commonly writes UTF-8 JSON with a BOM.
      // Strip it before parsing so status/show/task work with initialized profiles.
      const raw = fs.readFileSync(profilePath, "utf8").replace(/^\uFEFF/, "");
      return JSON.parse(raw);
    } catch {}
  }
  return null;
}

// ── Show Help Banner ──────────────────────────────────────────────
function showHelp() {
  console.log(`
\x1b[1;38;2;56;189;248m╔═════════════════════════════════════════════════════════════════════════╗
║  🚀 PLOGR WORKFLOW — HERDR COMPOSITE TERMINAL MULTIPLEXER               ║
╚═════════════════════════════════════════════════════════════════════════╝\x1b[0m

\x1b[1;37m用法 (Usage):\x1b[0m
  \x1b[36mplogr\x1b[0m                        快速启动/连接到当前项目的 Herdr 复合终端
  \x1b[36mplogr init\x1b[0m                   初始化项目 Dispatch 档案并安装 AI 技能
  \x1b[36mplogr change\x1b[0m                 \x1b[1;32m[懒人命令]\x1b[0m 终端交互式菜单修改各环节 Agent (按数字一键切换)
  \x1b[36mplogr change <role> <agent>\x1b[0m  \x1b[1;32m[单项修改]\x1b[0m 极速修改单项 (例: plogr change task claude)
  \x1b[36mplogr change preset <name>\x1b[0m   \x1b[1;32m[一键预设]\x1b[0m 一键应用预设 (all-claude, all-codex, cost-saver, balanced)
  \x1b[36mplogr show / agents\x1b[0m          查看当前各环节 (Task/Bugfix/Verifier/Research) 的 Agent 配置
  \x1b[36mplogr hud\x1b[0m                    在终端启动 24-bit 炫彩流光实时动态看板 (HUD)
  \x1b[36mplogr status\x1b[0m                 瞬时打印当前工作流状态单行快照
  \x1b[36mplogr popup\x1b[0m                  全屏浮动看板模式
  \x1b[36mplogr task [提示词]\x1b[0m           发起常规功能研发工作流 (Task Flow)
  \x1b[36mplogr bugfix [提示词]\x1b[0m         发起根因诊断与返工修复工作流 (Bugfix Flow)
  \x1b[36mplogr parallel [矩阵JSON]\x1b[0m     发起矩阵式并行多 Worktree 沙盒工作流
  \x1b[36mplogr attach [Session]\x1b[0m       连接到指定的 Herdr 隔离会话
  \x1b[36mplogr <herdr指令...>\x1b[0m         直接透明透传执行原生 Herdr 指令 (如 pane split)

\x1b[1;37m快捷参数 (Init Flags):\x1b[0m
  --root-cause <agent>        根因分析 Agent (claude, codex, opencode, gemini, cursor)
  --task <agent>              任务实现 Agent (codex, claude, opencode, gemini, cursor)
  --verification <agent>      代码验收 Agent (codex, claude, opencode, gemini, cursor)
  --research <agent>          深度调研 Agent (claude, codex, opencode, gemini, cursor)
  --session <name>            指定绑定的 Herdr 物理隔离 Session 名称
`);
}

// ── Lazy Agent Configuration Helpers ──────────────────────────────
const readline = require("readline");

function askQuestion(query) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => rl.question(query, (ans) => {
    rl.close();
    resolve(ans.trim());
  }));
}

function loadProfileSafe(cwd = process.cwd()) {
  const profilePath = path.join(cwd, "herdr", "dispatch-profile.json");
  if (!fs.existsSync(profilePath)) {
    const defaultProfile = {
      schema_version: 4,
      project_root: cwd,
      herdr_session: { name: path.basename(cwd).toLowerCase().replace(/[^a-z0-9_-]/g, "-") || "default" },
      task_agent: { kind: "codex" },
      root_cause_agent: { kind: "claude" },
      verification_agent: { kind: "claude" },
      research_agent: { kind: "gemini" },
      mattpocock_skills: {},
      git: { repository: false, has_commit: false, target_branch: "main", push_policy: "manual" }
    };
    const herdrDir = path.join(cwd, "herdr");
    if (!fs.existsSync(herdrDir)) fs.mkdirSync(herdrDir, { recursive: true });
    fs.writeFileSync(profilePath, JSON.stringify(defaultProfile, null, 2), "utf8");
    return { path: profilePath, data: defaultProfile };
  }
  try {
    const raw = fs.readFileSync(profilePath, "utf8").replace(/^\uFEFF/, "");
    return { path: profilePath, data: JSON.parse(raw) };
  } catch (err) {
    console.error(`\x1b[31m✗ 读取 profile 失败: ${err.message}\x1b[0m`);
    process.exit(1);
  }
}

function saveProfileSafe(profilePath, data) {
  const tmp = `${profilePath}.tmp.${Date.now()}`;
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2), "utf8");
  fs.renameSync(tmp, profilePath);
}

function printAgentsTable(profile) {
  console.log(`\n\x1b[1;38;2;56;189;248m┌───────────────────────┬──────────────────────────┬─────────────────────────────┐\x1b[0m`);
  console.log(`\x1b[1;38;2;56;189;248m│\x1b[1;37m 工作流阶段 (Role)     \x1b[1;38;2;56;189;248m│\x1b[1;37m 当前 Agent (Kind)        \x1b[1;38;2;56;189;248m│\x1b[1;37m 模型/配置 (Model)           \x1b[1;38;2;56;189;248m│\x1b[0m`);
  console.log(`\x1b[1;38;2;56;189;248m├───────────────────────┼──────────────────────────┼─────────────────────────────┤\x1b[0m`);
  
  const roles = [
    { key: "task_agent", label: "1. 功能开发 (Task)", name: "task" },
    { key: "root_cause_agent", label: "2. 缺陷诊断 (Bugfix)", name: "bugfix" },
    { key: "verification_agent", label: "3. 独立验收 (Verifier)", name: "verifier" },
    { key: "research_agent", label: "4. 技术调研 (Research)", name: "research" },
  ];

  for (const r of roles) {
    const entry = profile[r.key] || { kind: "codex" };
    const kind = entry.kind || "codex";
    const model = entry.model || "(默认 / default)";
    console.log(`\x1b[1;38;2;56;189;248m│\x1b[0m ${r.label.padEnd(21)} \x1b[1;38;2;56;189;248m│\x1b[0m \x1b[32m${kind.padEnd(24)}\x1b[0m \x1b[1;38;2;56;189;248m│\x1b[0m \x1b[33m${model.padEnd(27)}\x1b[0m \x1b[1;38;2;56;189;248m│\x1b[0m`);
  }
  console.log(`\x1b[1;38;2;56;189;248m└───────────────────────┴──────────────────────────┴─────────────────────────────┘\x1b[0m`);
}

function normalizeRoleKey(roleStr) {
  const r = (roleStr || "").toLowerCase().replace(/[^a-z0-9_-]/g, "");
  if (['task', 'task_agent', 'implement'].includes(r)) return 'task_agent';
  if (['bugfix', 'bug', 'root-cause', 'root_cause', 'rootcause', 'root_cause_agent'].includes(r)) return 'root_cause_agent';
  if (['verifier', 'verify', 'verification', 'verification_agent', 'audit'].includes(r)) return 'verification_agent';
  if (['research', 'research_agent', 'investigate'].includes(r)) return 'research_agent';
  return null;
}

function applyPreset(profile, presetName) {
  const p = (presetName || "").toLowerCase();
  if (p === 'all-claude' || p === 'claude') {
    profile.task_agent = { kind: 'claude' };
    profile.root_cause_agent = { kind: 'claude' };
    profile.verification_agent = { kind: 'claude' };
    profile.research_agent = { kind: 'claude' };
  } else if (p === 'all-codex' || p === 'codex') {
    profile.task_agent = { kind: 'codex' };
    profile.root_cause_agent = { kind: 'codex' };
    profile.verification_agent = { kind: 'codex' };
    profile.research_agent = { kind: 'codex' };
  } else if (p === 'all-gemini' || p === 'gemini') {
    profile.task_agent = { kind: 'gemini' };
    profile.root_cause_agent = { kind: 'gemini' };
    profile.verification_agent = { kind: 'gemini' };
    profile.research_agent = { kind: 'gemini' };
  } else if (p === 'cost-saver' || p === 'deepseek') {
    profile.task_agent = { kind: 'opencode', model: 'deepseek-coder' };
    profile.root_cause_agent = { kind: 'opencode', model: 'deepseek-coder' };
    profile.verification_agent = { kind: 'opencode', model: 'deepseek-coder' };
    profile.research_agent = { kind: 'opencode', model: 'deepseek-chat' };
  } else if (p === 'balanced') {
    profile.task_agent = { kind: 'codex' };
    profile.root_cause_agent = { kind: 'claude' };
    profile.verification_agent = { kind: 'claude' };
    profile.research_agent = { kind: 'gemini' };
  } else {
    throw new Error(`未知预设: "${presetName}"。可用预设: balanced, all-claude, all-codex, all-gemini, cost-saver`);
  }
}

function getDynamicOpenCodeModels() {
  const models = [];
  // 1. Try running `opencode models`
  try {
    const raw = execSync("opencode models", { encoding: "utf8", timeout: 3000, stdio: ["ignore", "pipe", "ignore"] });
    const lines = raw.replace(/\x1b\[[0-9;]*m/g, "").split(/\r?\n/);
    for (const line of lines) {
      const trimmed = line.trim();
      if (trimmed && trimmed.includes("/") && !trimmed.startsWith("-")) {
        if (!models.includes(trimmed)) models.push(trimmed);
      }
    }
  } catch {}

  // 2. Try parsing config files
  const os = require("os");
  const configPaths = [
    path.join(os.homedir(), ".config", "opencode", "opencode.jsonc"),
    path.join(os.homedir(), ".config", "opencode", "opencode.json"),
    path.join(os.homedir(), ".opencode", "opencode.json"),
    path.join(os.homedir(), ".opencode", "opencode.jsonc"),
    path.join(process.env.APPDATA || "", "opencode", "opencode.json"),
    path.join(process.env.LOCALAPPDATA || "", "opencode", "opencode.json")
  ];

  for (const cfg of configPaths) {
    if (fs.existsSync(cfg)) {
      try {
        const raw = fs.readFileSync(cfg, "utf8");
        const clean = raw.replace(/(^|\s)\/\/.*$/gm, "");
        const data = JSON.parse(clean);
        if (data.provider) {
          for (const prov of Object.keys(data.provider)) {
            const pVal = data.provider[prov];
            if (pVal && pVal.models) {
              for (const m of Object.keys(pVal.models)) {
                const fullId = `${prov}/${m}`;
                if (!models.includes(fullId)) models.push(fullId);
              }
            }
          }
        }
      } catch {}
    }
  }

  // 3. Fallback defaults if empty
  const defaults = [
    "opencode-go/deepseek-v4-flash",
    "opencode-go/gpt-5.6-luna",
    "opencode-go/qwen3.8-max",
    "opencode-go/kimi-k2.7-code",
    "opencode-go/glm-5.3",
    "opencode-go/deepseek-v4-pro",
    "opencode-go/grok-4.5",
    "opencode-go/mimo-v2.5",
    "opencode-go/minimax-m3",
    "pixel/gpt-5.6-sol",
    "pixel/gpt-5.6-Terra",
    "pixel/gpt-5.6-Luna",
    "opencode/deepseek-v4-flash-free",
    "opencode/hy3-free",
    "opencode/big-pickle",
    "deepseek/deepseek-chat",
    "deepseek/deepseek-reasoner",
    "anthropic/claude-3-7-sonnet",
    "openai/o3-mini",
    "google/gemini-2.5-pro"
  ];
  for (const d of defaults) {
    if (!models.includes(d)) models.push(d);
  }
  return models;
}

function resolveOpenCodeModel(input, models = []) {
  if (!input) return null;
  const aliases = {
    'zen': 'opencode/deepseek-v4-flash-free',
    'zen-free': 'opencode/deepseek-v4-flash-free',
    'go': 'opencode-go/deepseek-v4-flash',
    'go-flash': 'opencode-go/deepseek-v4-flash',
    'flash': 'opencode-go/deepseek-v4-flash',
    'go-pro': 'opencode-go/deepseek-v4-pro',
    'sol': 'pixel/gpt-5.6-sol',
    'terra': 'pixel/gpt-5.6-Terra',
    'luna': 'pixel/gpt-5.6-Luna',
    'glm': 'opencode-go/glm-5.3',
    'glm-5.3': 'opencode-go/glm-5.3',
    'qwen': 'opencode-go/qwen3.8-max',
    'qwen3.8': 'opencode-go/qwen3.8-max',
    'kimi': 'opencode-go/kimi-k2.7-code',
    'kimi-code': 'opencode-go/kimi-k2.7-code',
    'grok': 'opencode-go/grok-4.5',
    'mimo': 'opencode-go/mimo-v2.5',
    'minimax': 'opencode-go/minimax-m3'
  };
  const key = input.trim().toLowerCase();
  if (aliases[key]) return aliases[key];
  if (/^\d+$/.test(key)) {
    const idx = parseInt(key, 10) - 1;
    if (idx >= 0 && idx < models.length) return models[idx];
  }
  const exact = models.find(m => m.toLowerCase() === key);
  if (exact) return exact;
  const normal = key.replace(/[^a-z0-9]/g, '');
  const fuzzy = models.filter(m => m.toLowerCase().replace(/[^a-z0-9]/g, '').includes(normal));
  if (fuzzy.length === 1) return fuzzy[0];
  return input.trim();
}

async function runInteractiveChange() {
  const { path: profilePath, data: profile } = loadProfileSafe();
  printAgentsTable(profile);

  console.log(`\x1b[1;36m⚙️  请选择要修改的环节或预设:\x1b[0m`);
  console.log(`   \x1b[1;33m1\x1b[0m) 功能开发 (Task Agent)       - 当前: \x1b[32m${profile.task_agent?.kind || 'codex'}\x1b[0m`);
  console.log(`   \x1b[1;33m2\x1b[0m) 缺陷诊断 (Bugfix Agent)     - 当前: \x1b[32m${profile.root_cause_agent?.kind || 'codex'}\x1b[0m`);
  console.log(`   \x1b[1;33m3\x1b[0m) 独立验收 (Verifier Agent)   - 当前: \x1b[32m${profile.verification_agent?.kind || 'codex'}\x1b[0m`);
  console.log(`   \x1b[1;33m4\x1b[0m) 技术调研 (Research Agent)   - 当前: \x1b[32m${profile.research_agent?.kind || 'codex'}\x1b[0m`);
  console.log(`   \x1b[1;33m5\x1b[0m) 一键应用预设方案 (Presets: All-Claude / All-Codex / Cost-Saver / Balanced)`);
  console.log(`   \x1b[1;33m0\x1b[0m) 退出 (Exit)\n`);

  const choice = await askQuestion(`\x1b[1;37m输入编号 (0-5) [默认 0]: \x1b[0m`);
  if (!choice || choice === '0') {
    console.log(`\x1b[90m已取消修改。\x1b[0m\n`);
    process.exit(0);
  }

  if (choice === '5') {
    console.log(`\n\x1b[1;36m🎯 请选择预设方案:\x1b[0m`);
    console.log(`   \x1b[1;33m1\x1b[0m) \x1b[1;37mbalanced\x1b[0m    - 黄金组合 (Task: Codex, Bugfix: Claude, Verifier: Claude, Research: Gemini)`);
    console.log(`   \x1b[1;33m2\x1b[0m) \x1b[1;37mall-claude\x1b[0m  - 全链路使用 Claude Code`);
    console.log(`   \x1b[1;33m3\x1b[0m) \x1b[1;37mall-codex\x1b[0m   - 全链路使用 OpenAI Codex`);
    console.log(`   \x1b[1;33m4\x1b[0m) \x1b[1;37mall-gemini\x1b[0m  - 全链路使用 Gemini CLI`);
    console.log(`   \x1b[1;33m5\x1b[0m) \x1b[1;37mcost-saver\x1b[0m  - 极致性价比 (全链路 OpenCode + DeepSeek-Coder)`);
    
    const pChoice = await askQuestion(`\x1b[1;37m输入预设编号 (1-5): \x1b[0m`);
    const presetMap = { '1': 'balanced', '2': 'all-claude', '3': 'all-codex', '4': 'all-gemini', '5': 'cost-saver' };
    const pName = presetMap[pChoice];
    if (pName) {
      applyPreset(profile, pName);
      saveProfileSafe(profilePath, profile);
      console.log(`\n\x1b[32m✔ 已成功应用预设: \x1b[1;37m${pName}\x1b[0m`);
      printAgentsTable(profile);
    }
    process.exit(0);
  }

  const roleMap = { '1': 'task_agent', '2': 'root_cause_agent', '3': 'verification_agent', '4': 'research_agent' };
  const targetKey = roleMap[choice];
  if (!targetKey) {
    console.error(`\x1b[31m无效的选择: ${choice}\x1b[0m`);
    process.exit(1);
  }

  console.log(`\n\x1b[1;36m🤖 请选择 Agent 引擎:\x1b[0m`);
  console.log(`   \x1b[1;33m1\x1b[0m) \x1b[1;37mclaude\x1b[0m    (Claude Code)`);
  console.log(`   \x1b[1;33m2\x1b[0m) \x1b[1;37mcodex\x1b[0m     (OpenAI Codex)`);
  console.log(`   \x1b[1;33m3\x1b[0m) \x1b[1;37mopencode\x1b[0m  (OpenCode / Go / Zen / Custom Models)`);
  console.log(`   \x1b[1;33m4\x1b[0m) \x1b[1;37mgemini\x1b[0m    (Gemini CLI)`);
  console.log(`   \x1b[1;33m5\x1b[0m) \x1b[1;37mcursor\x1b[0m    (Cursor Agent)`);

  const aChoice = await askQuestion(`\x1b[1;37m输入编号或直接输入名称 (1-5) [默认 1]: \x1b[0m`) || '1';
  const agentMap = { '1': 'claude', '2': 'codex', '3': 'opencode', '4': 'gemini', '5': 'cursor' };
  const selectedAgent = agentMap[aChoice] || aChoice.toLowerCase();

  let selectedModel = null;
  if (selectedAgent === 'opencode') {
    console.log(`\n\x1b[1;36m⚡ 正在动态读取 OpenCode 模型列表 (含 Go / Zen / 自定义模型)...\x1b[0m`);
    const dynamicModels = getDynamicOpenCodeModels();
    
    console.log(`\n\x1b[1;38;2;56;189;248m┌─────────────────────────────────────────────────────────────────────────────┐\x1b[0m`);
    console.log(`\x1b[1;38;2;56;189;248m│\x1b[1;37m 可用 OpenCode 模型列表 (按数字或输入模型名称选择):                          \x1b[1;38;2;56;189;248m│\x1b[0m`);
    console.log(`\x1b[1;38;2;56;189;248m├─────────────────────────────────────────────────────────────────────────────┤\x1b[0m`);
    
    for (let i = 0; i < dynamicModels.length; i++) {
      const m = dynamicModels[i];
      let tag = "\x1b[90m[OpenCode 兼容]\x1b[0m";
      if (m.startsWith("opencode-go/")) tag = "\x1b[36m[Go 高速专区]\x1b[0m";
      else if (m.startsWith("opencode/")) tag = "\x1b[32m[Zen/Free 专区]\x1b[0m";
      else if (m.startsWith("pixel/")) tag = "\x1b[35m[Pixel 自定义]\x1b[0m";
      else if (m.startsWith("deepseek/")) tag = "\x1b[33m[DeepSeek 官方]\x1b[0m";
      else if (m.startsWith("anthropic/")) tag = "\x1b[34m[Claude 官方]\x1b[0m";

      const numStr = (i + 1).toString().padStart(2, " ");
      console.log(`\x1b[1;38;2;56;189;248m│\x1b[0m \x1b[1;33m${numStr}\x1b[0m) \x1b[1;37m${m.padEnd(42)}\x1b[0m ${tag.padEnd(26)} \x1b[1;38;2;56;189;248m│\x1b[0m`);
    }
    console.log(`\x1b[1;38;2;56;189;248m└─────────────────────────────────────────────────────────────────────────────┘\x1b[0m`);
    console.log(`\x1b[90m💡 快捷别名支持: go, zen, sol, terra, luna, qwen, kimi, glm, flash\x1b[0m\n`);

    const mInput = await askQuestion(`\x1b[1;37m输入模型编号 (1-${dynamicModels.length}) 或别名/名称 [默认 1 (${dynamicModels[0]})]: \x1b[0m`);
    selectedModel = resolveOpenCodeModel(mInput || "1", dynamicModels);
  }

  if (!profile[targetKey]) profile[targetKey] = {};
  profile[targetKey].kind = selectedAgent;
  if (selectedModel) {
    profile[targetKey].model = selectedModel;
  } else {
    delete profile[targetKey].model;
  }

  saveProfileSafe(profilePath, profile);
  console.log(`\n\x1b[32m✔ 已成功修改 \x1b[1;37m${targetKey}\x1b[0;32m 为 \x1b[1;37m${selectedAgent}${selectedModel ? ' (' + selectedModel + ')' : ''}\x1b[0m`);
  printAgentsTable(profile);
  process.exit(0);
}

// ── Ensure Global plogr Command In System PATH ────────────────────
function installGlobalPlogr() {
  try {
    const isWin = process.platform === "win32";
    const userHome = process.env.USERPROFILE || process.env.HOME || "";
    const localAppData = process.env.LOCALAPPDATA || path.join(userHome, "AppData", "Local");
    const appData = process.env.APPDATA || path.join(userHome, "AppData", "Roaming");

    const targetDirs = [];

    // 1. npm global bin directory
    try {
      const npmPrefix = execSync("npm prefix -g", { encoding: "utf8", timeout: 2000 }).trim();
      if (npmPrefix) {
        targetDirs.push(isWin ? npmPrefix : path.join(npmPrefix, "bin"));
      }
    } catch {}

    if (isWin) {
      targetDirs.push(
        path.join(appData, "npm"),
        path.join(localAppData, "Programs", "Herdr", "bin"),
        path.join(userHome, ".local", "bin"),
        path.join(userHome, "bin")
      );
    } else {
      targetDirs.push(
        path.join(userHome, ".local", "bin"),
        path.join(userHome, "bin"),
        "/usr/local/bin"
      );
    }

    const currentCliPath = path.resolve(__dirname, "cli.js").replace(/\\/g, "/");

    const launcherJs = `#!/usr/bin/env node
"use strict";
const fs = require("fs");
const localCli = "${currentCliPath}";
if (fs.existsSync(localCli)) {
  require(localCli);
} else {
  console.error("plogr 本地 CLI 不存在。请从仓库运行其 herdr-skill/bin/cli.js；此工作流只使用仓库内运行时。");
  process.exit(1);
}
`;

    const cmdContent = `@ECHO off
node "%~dp0plogr-cli.js" %*
`;

    const ps1Content = `#!/usr/bin/env pwsh
$cli = Join-Path $PSScriptRoot 'plogr-cli.js'
if ($MyInvocation.ExpectingInput) {
  $input | & node $cli $args
} else {
  & node $cli $args
}
exit $LASTEXITCODE
`;

    const shContent = `#!/usr/bin/env sh
basedir=$(dirname "$0")
if [ -f "$basedir/plogr-cli.js" ]; then
  exec node "$basedir/plogr-cli.js" "$@"
else
  echo "plogr 本地 CLI 不存在。请从仓库运行 herdr-skill/bin/cli.js；此工作流只使用仓库内运行时。" >&2
  exit 1
fi
`;

    for (const dir of targetDirs) {
      if (!dir) continue;
      try {
        if (!fs.existsSync(dir)) {
          fs.mkdirSync(dir, { recursive: true });
        }
        if (fs.existsSync(dir)) {
          fs.writeFileSync(path.join(dir, "plogr-cli.js"), launcherJs, "utf8");
          if (isWin) {
            fs.writeFileSync(path.join(dir, "plogr.cmd"), cmdContent, "utf8");
            fs.writeFileSync(path.join(dir, "plogr.ps1"), ps1Content, "utf8");
          }
          const shPath = path.join(dir, "plogr");
          fs.writeFileSync(shPath, shContent, { encoding: "utf8", mode: 0o755 });
        }
      } catch {}
    }
  } catch {}
}

// Automatically ensure global `plogr` is registered across all user environments
installGlobalPlogr();

// ── Execution Entry ───────────────────────────────────────────────
const cliArgs = process.argv.slice(2);
const firstArg = cliArgs[0] ? cliArgs[0].toLowerCase() : null;

// Determine if CLI was invoked as `plogr-workflow` vs `plogr`
const scriptBase = path.basename(process.argv[1] || "", path.extname(process.argv[1] || "")).toLowerCase();
const isWorkflowInvoked = scriptBase.includes("plogr-workflow") || 
  process.env.npm_lifecycle_event === "plogr-workflow" || 
  process.env.npm_package_name === "plogr-workflow" ||
  (Boolean(process.env._) && process.env._.includes("plogr-workflow"));

// 1. Help
if (['help', '--help', '-h'].includes(firstArg)) {
  showHelp();
  process.exit(0);
}

// 2. Change / Set / Show / Agents Configuration Subcommands
if (['change', 'set', 'config', 'show', 'agents', 'preset'].includes(firstArg)) {
  const subArgs = cliArgs.slice(1);
  
  if (firstArg === 'show' || firstArg === 'agents') {
    const { data: profile } = loadProfileSafe();
    printAgentsTable(profile);
    process.exit(0);
  }

  if (firstArg === 'change' || firstArg === 'config') {
    if (subArgs.length === 0) {
      runInteractiveChange();
      return;
    }
  }

  const { path: profilePath, data: profile } = loadProfileSafe();

  // Check if applying preset: plogr change preset <name> OR plogr preset <name> OR plogr change <preset-name>
  const isPresetCmd = firstArg === 'preset' || subArgs[0] === 'preset' || ['all-claude', 'all-codex', 'all-gemini', 'cost-saver', 'deepseek', 'balanced'].includes((subArgs[0] || "").toLowerCase());
  if (isPresetCmd) {
    let presetName = firstArg === 'preset' ? subArgs[0] : (subArgs[0] === 'preset' ? subArgs[1] : subArgs[0]);
    if (!presetName) {
      console.error(`\x1b[31m✗ 缺少预设名称。\x1b[0m`);
      console.error(`\x1b[36m💡 可用预设: balanced, all-claude, all-codex, all-gemini, cost-saver\x1b[0m\n`);
      process.exit(1);
    }
    try {
      applyPreset(profile, presetName);
      saveProfileSafe(profilePath, profile);
      console.log(`\n\x1b[32m✔ 已成功应用预设: \x1b[1;37m${presetName}\x1b[0m`);
      printAgentsTable(profile);
      process.exit(0);
    } catch (err) {
      console.error(`\x1b[31m✗ ${err.message}\x1b[0m\n`);
      process.exit(1);
    }
  }

  // Single role modification: plogr change <role> <agent> [model] OR plogr set <role> <agent> [model]
  const roleArg = subArgs[0];
  const agentArg = subArgs[1];
  const modelArg = subArgs[2] || null;

  const targetKey = normalizeRoleKey(roleArg);
  if (!targetKey) {
    console.error(`\x1b[31m✗ 未知的环节: "${roleArg}"。\x1b[0m`);
    console.error(`\x1b[36m💡 支持的环节: task (开发), bugfix (诊断), verifier (验收), research (调研)\x1b[0m`);
    console.error(`\x1b[90m   示例: plogr change task claude\x1b[0m\n`);
    process.exit(1);
  }

  if (!agentArg) {
    console.error(`\x1b[31m✗ 缺少 Agent 引擎名称。\x1b[0m`);
    console.error(`\x1b[36m💡 支持的引擎: claude, codex, opencode, gemini, cursor\x1b[0m`);
    console.error(`\x1b[90m   示例: plogr change ${roleArg} claude\x1b[0m\n`);
    process.exit(1);
  }

  let finalKind = agentArg.toLowerCase();
  let finalModel = modelArg;

  const dynamicModels = getDynamicOpenCodeModels();
  const directResolvedModel = resolveOpenCodeModel(agentArg, dynamicModels);

  if (['claude', 'codex', 'gemini', 'cursor'].includes(finalKind)) {
    // Standard non-opencode agents
  } else if (finalKind === 'opencode') {
    if (finalModel) {
      finalModel = resolveOpenCodeModel(finalModel, dynamicModels) || finalModel;
    }
  } else if (directResolvedModel && directResolvedModel !== agentArg) {
    finalKind = 'opencode';
    finalModel = directResolvedModel;
  } else if (directResolvedModel && (directResolvedModel.includes('/') || dynamicModels.includes(directResolvedModel))) {
    finalKind = 'opencode';
    finalModel = directResolvedModel;
  }

  if (!profile[targetKey]) profile[targetKey] = {};
  profile[targetKey].kind = finalKind;
  if (finalModel) {
    profile[targetKey].model = finalModel;
  } else {
    delete profile[targetKey].model;
  }

  saveProfileSafe(profilePath, profile);
  console.log(`\n\x1b[32m✔ 已成功将 \x1b[1;37m${targetKey}\x1b[0;32m 修改为 \x1b[1;37m${finalKind}${finalModel ? ' (' + finalModel + ')' : ''}\x1b[0m`);
  printAgentsTable(profile);
  process.exit(0);
}

// 3. HUD Subcommands (hud, status, popup)
if (['status', 'hud', 'popup'].includes(firstArg)) {
  const hudArgs = [hudScript, ...cliArgs.slice(1)];
  if (firstArg === 'hud' && !hudArgs.includes('--live')) hudArgs.push('--live');
  if (firstArg === 'popup' && !hudArgs.includes('--popup')) hudArgs.push('--popup');
  
  const child = spawn(process.execPath, hudArgs, {
    stdio: 'inherit',
    windowsHide: false
  });
  child.on('exit', (code) => process.exit(code ?? 0));
  return;
}

// 3. Workflow Task / Bugfix / Research Subcommands
if (['task', 'bugfix', 'research'].includes(firstArg)) {
  if (process.env.HERDR_ENV !== '1') {
    console.error(`\x1b[33m⚠️ 提示: 当前未处于 Herdr 复合终端环境中 (HERDR_ENV != 1)。\x1b[0m`);
    console.error(`\x1b[36m💡 请先在当前项目目录运行 \x1b[1;37mplogr\x1b[0;36m 启动/连接 Herdr 复合终端，然后在 Herdr 窗格中派发工作流。\x1b[0m\n`);
  }

  const psHost = findPowerShell();
  const prompt = cliArgs.slice(1).join(" ") || "General task execution";
  const autoSlug = (cliArgs[1] || firstArg).toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 16).replace(/^-|-$/g, "") || `${firstArg}-${Date.now().toString(36)}`;
  const psArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    workflowScript,
    "-Mode",
    firstArg,
    "-Slug",
    autoSlug,
    "-Prompt",
    prompt
  ];

  const child = spawn(psHost, psArgs, {
    stdio: 'inherit',
    windowsHide: false
  });
  child.on('exit', (code) => process.exit(code ?? 0));
  return;
}

// 4. Parallel Workflow Subcommand
if (firstArg === 'parallel') {
  if (process.env.HERDR_ENV !== '1') {
    console.error(`\x1b[33m⚠️ 提示: 当前未处于 Herdr 复合终端环境中 (HERDR_ENV != 1)。\x1b[0m`);
    console.error(`\x1b[36m💡 请先在当前项目目录运行 \x1b[1;37mplogr\x1b[0;36m 启动/连接 Herdr 复合终端，然后在 Herdr 窗格中派发工作流。\x1b[0m\n`);
  }

  const psHost = findPowerShell();
  const matrixArg = cliArgs[1] || '[]';
  const autoSlug = `matrix-${Date.now().toString(36)}`;
  const psArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    parallelScript,
    "-Slug",
    autoSlug,
    "-MatrixJson",
    matrixArg
  ];

  const child = spawn(psHost, psArgs, {
    stdio: 'inherit',
    windowsHide: false
  });
  child.on('exit', (code) => process.exit(code ?? 0));
  return;
}

// ── Scan Active Worktrees (Protection from Pruning) ───────────────
function getActiveWorktrees(projectRoot) {
  const active = new Set();
  const herdrDir = path.join(projectRoot, "herdr");
  if (!fs.existsSync(herdrDir)) return active;

  function scan(dir) {
    try {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const e of entries) {
        const full = path.join(dir, e.name);
        if (e.isDirectory()) {
          scan(full);
        } else if (e.isFile() && e.name === "workflow.json") {
          try {
            const wf = JSON.parse(fs.readFileSync(full, "utf8"));
            if (["executing", "candidate", "verifying", "repairing"].includes(wf.state)) {
              if (wf.task?.worktree_path) {
                active.add(path.resolve(wf.task.worktree_path).toLowerCase());
              }
              if (Array.isArray(wf.matrix)) {
                for (const m of wf.matrix) {
                  if (m.worktree_path) active.add(path.resolve(m.worktree_path).toLowerCase());
                }
              }
              if (wf.slug) {
                const intPath = path.resolve(path.join(projectRoot, ".worktrees", `wf-${wf.slug}-integration`));
                active.add(intPath.toLowerCase());
              }
            }
          } catch {}
        }
      }
    } catch {}
  }
  scan(herdrDir);
  return active;
}

// 5. Prune Worktrees Subcommand (`plogr prune`)
if (firstArg === 'prune') {
  const projectRoot = process.cwd();
  console.log(`\x1b[36m🧹 Scanning and pruning stale Git worktrees in ${projectRoot}...\x1b[0m`);
  try {
    const activeWorktrees = getActiveWorktrees(projectRoot);
    const wtDir = path.join(projectRoot, '.worktrees');
    if (fs.existsSync(wtDir)) {
      const entries = fs.readdirSync(wtDir);
      for (const entry of entries) {
        const fullWtPath = path.join(wtDir, entry);
        const normPath = path.resolve(fullWtPath).toLowerCase();
        
        // Protect active worktrees from deletion
        if (activeWorktrees.has(normPath)) {
          console.log(`\x1b[33m  🛡️ 跳过活跃沙盒 (正在执行任务): ${entry}\x1b[0m`);
          continue;
        }

        try {
          execSync(`git -C "${projectRoot}" worktree remove --force "${fullWtPath}"`, { stdio: 'ignore' });
        } catch {}
        if (fs.existsSync(fullWtPath)) {
          try {
            if (process.platform === 'win32') {
              execSync(`cmd /c "rmdir /s /q \"${fullWtPath}\""`, { stdio: 'ignore' });
            } else {
              fs.rmSync(fullWtPath, { recursive: true, force: true });
            }
          } catch {}
        }
      }
    }
    execSync(`git -C "${projectRoot}" worktree prune`, { stdio: 'ignore' });
    console.log(`\x1b[32m✨ All merged & orphaned Git worktrees have been cleanly pruned.\x1b[0m`);
  } catch (err) {
    console.error(`\x1b[31mFailed to prune worktrees: ${err.message}\x1b[0m`);
  }
  return;
}

// 6. Initialize / Configuration Mode:
// Triggered if:
//  - Invoked via the local `plogr-workflow` launcher (with or without arguments)
//  - Explicitly called as `plogr init`
//  - Flags like `--root-cause`, `--task`, `--session` are passed
const isInit = isWorkflowInvoked || firstArg === 'init' || (Boolean(firstArg) && firstArg.startsWith('-'));
if (isInit) {
  const psHost = findPowerShell();
  const initArgs = firstArg === 'init' ? cliArgs.slice(1) : cliArgs;
  
  const argMap = {
    "--root-cause": "-RootCauseKind",
    "--task": "-TaskKind",
    "--verification": "-VerificationKind",
    "--research": "-ResearchKind",
    "--root-cause-model": "-RootCauseOpenCodeModel",
    "--task-model": "-TaskOpenCodeModel",
    "--verification-model": "-VerificationOpenCodeModel",
    "--research-model": "-ResearchOpenCodeModel",
    "--session": "-HerdrSessionName",
    "--push-policy": "-PushPolicy",
    "--push-remote": "-PushRemote",
    "--project": "-ProjectRoot",
    "--skill-agents": "-SkillTargetAgents",
    "--skip-git-init": "-SkipGitInit",
    "--skip-skills-install": "-SkipSkillsInstall",
    "--help": "-Help",
    "-h": "-Help",
  };

  const psArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    initScript,
  ];

  let i = 0;
  while (i < initArgs.length) {
    const arg = initArgs[i];
    if (argMap[arg]) {
      const psFlag = argMap[arg];
      if (["-SkipGitInit", "-SkipSkillsInstall", "-Help"].includes(psFlag)) {
        psArgs.push(psFlag);
        i++;
      } else {
        psArgs.push(psFlag);
        if (i + 1 < initArgs.length) {
          psArgs.push(initArgs[i + 1]);
          i += 2;
        } else {
          console.error(`\x1b[31m✗ Missing value for ${arg}\x1b[0m`);
          process.exit(1);
        }
      }
    } else if (arg.startsWith("-")) {
      psArgs.push(arg);
      i++;
    } else {
      psArgs.push("-ProjectRoot", arg);
      i++;
    }
  }

  const child = spawn(psHost, psArgs, {
    stdio: "inherit",
    windowsHide: false,
  });

  child.on("exit", (code) => process.exit(code ?? 1));
  return;
}

// 7. Launch / Attach Herdr Composite Terminal (`plogr` with no args or `plogr attach`)
if (!firstArg || firstArg === 'attach') {
  const profile = getProjectProfile();
  
  // If project is not initialized yet and user types `plogr`, guide them to initialize
  if (!profile && !firstArg) {
    console.log(`\x1b[33mℹ️ 当前项目尚未配置 Herdr Dispatch 档案，正在启动交互式终端选配向导...\x1b[0m\n`);
    const psHost = findPowerShell();
    const psArgs = [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      initScript,
    ];
    const child = spawn(psHost, psArgs, {
      stdio: "inherit",
      windowsHide: false,
    });
    child.on("exit", (code) => {
      if (code === 0) {
        console.log(`\n\x1b[32m✨ 初始化完成！正在启动并连接到 Herdr 工作终端...\x1b[0m`);
        const updatedProfile = getProjectProfile();
        const boundSession = updatedProfile?.herdr_session?.name || (typeof updatedProfile?.herdr_session === 'string' ? updatedProfile.herdr_session : null);
        const herdrBin = findHerdr();
        const herdrArgs = boundSession ? ['--session', boundSession] : [];
        const herdrChild = spawn(herdrBin, herdrArgs, { stdio: 'inherit', windowsHide: false });
        herdrChild.on('exit', (c) => process.exit(c ?? 0));
      } else {
        process.exit(code ?? 1);
      }
    });
    return;
  }

  const herdrBin = findHerdr();
  const boundSession = profile?.herdr_session?.name || (typeof profile?.herdr_session === 'string' ? profile.herdr_session : null);
  const targetSession = (firstArg === 'attach' && cliArgs[1]) ? cliArgs[1] : boundSession;

  const herdrArgs = [];
  if (targetSession) {
    herdrArgs.push('--session', targetSession);
  }

  // If in attach mode, use `session attach`
  if (firstArg === 'attach' && targetSession) {
    herdrArgs.length = 0;
    herdrArgs.push('session', 'attach', targetSession);
  }

  const child = spawn(herdrBin, herdrArgs, {
    stdio: 'inherit',
    windowsHide: false
  });

  child.on('error', (err) => {
    console.error(`\x1b[31m✗ 无法启动 Herdr 复合终端 (${herdrBin}): ${err.message}\x1b[0m`);
    console.error(`\x1b[33m💡 请确保已安装 Herdr: powershell -ExecutionPolicy Bypass -c "irm https://herdr.dev/install.ps1 | iex"\x1b[0m`);
    process.exit(1);
  });

  child.on('exit', (code) => process.exit(code ?? 0));
  return;
}

// 8. Fallback: Transparent Pass-Through to Native Herdr CLI
const herdrBin = findHerdr();
const child = spawn(herdrBin, cliArgs, {
  stdio: 'inherit',
  windowsHide: false
});

child.on('error', (err) => {
  console.error(`\x1b[31m✗ 无法执行 Herdr 指令: ${err.message}\x1b[0m`);
  process.exit(1);
});

child.on('exit', (code) => process.exit(code ?? 0));
