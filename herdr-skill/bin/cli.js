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
      return JSON.parse(fs.readFileSync(profilePath, "utf8"));
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
  \x1b[36mplogr hud\x1b[0m                    在终端启动 24-bit 炫彩流光实时动态看板 (HUD)
  \x1b[36mplogr status\x1b[0m                 瞬时打印当前工作流状态单行快照
  \x1b[36mplogr popup\x1b[0m                  全屏浮动看板模式
  \x1b[36mplogr task [提示词]\x1b[0m           发起常规功能研发工作流 (Task Flow)
  \x1b[36mplogr bugfix [提示词]\x1b[0m         发起根因诊断与返工修复工作流 (Bugfix Flow)
  \x1b[36mplogr parallel [矩阵JSON]\x1b[0m     发起矩阵式并行多 Worktree 沙盒工作流
  \x1b[36mplogr attach [Session]\x1b[0m       连接到指定的 Herdr 隔离会话
  \x1b[36mplogr <herdr指令...>\x1b[0m         直接透明透传执行原生 Herdr 指令 (如 pane split)

\x1b[1;37m快捷参数 (Init Flags):\x1b[0m
  --root-cause <agent>        根因分析 Agent (claude, codex, opencode)
  --task <agent>              任务实现 Agent (codex, claude, opencode)
  --verification <agent>      代码验收 Agent (codex, claude, opencode)
  --research <agent>          深度调研 Agent (claude, codex, opencode)
  --session <name>            指定绑定的 Herdr 物理隔离 Session 名称
`);
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
const { spawn } = require("child_process");

const localCli = "${currentCliPath}";
if (fs.existsSync(localCli)) {
  require(localCli);
} else {
  const child = spawn("npx", ["plogr-workflow", ...process.argv.slice(2)], {
    stdio: "inherit",
    shell: true
  });
  child.on("exit", (code) => process.exit(code ?? 0));
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
  exec npx plogr-workflow "$@"
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

// 1. Help
if (['help', '--help', '-h'].includes(firstArg)) {
  showHelp();
  process.exit(0);
}

// 2. HUD Subcommands (hud, status, popup)
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

// 3. Launch / Attach Herdr Composite Terminal (Default `plogr` with no args or `plogr attach`)
if (!firstArg || firstArg === 'attach') {
  const herdrBin = findHerdr();
  const profile = getProjectProfile();
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

// 4. Workflow Task / Bugfix / Research Subcommands
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

// 5. Parallel Workflow Subcommand
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

// 5.5. Prune Worktrees Subcommand (`plogr prune`)
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

// 6. Initialize / Configuration Mode (`plogr init` or flags like `--root-cause`)
const isInit = firstArg === 'init' || firstArg?.startsWith('-');
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

// 7. Fallback: Transparent Pass-Through to Native Herdr CLI
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
