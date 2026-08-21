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

// 4. Workflow Task / Bugfix Subcommands
if (['task', 'bugfix'].includes(firstArg)) {
  const psHost = findPowerShell();
  const prompt = cliArgs.slice(1).join(" ") || "General task execution";
  const psArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    workflowScript,
    "-Category",
    firstArg,
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
  const psHost = findPowerShell();
  const matrixArg = cliArgs[1] || '[]';
  const psArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    parallelScript,
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
