#!/usr/bin/env node

/**
 * plogr-workflow CLI — npx plogr-workflow
 *
 * Thin Node.js launcher that invokes Initialize-HerdrProject.ps1 via
 * pwsh.exe (preferred) or powershell.exe, transparently forwarding
 * stdin/stdout/stderr so the interactive Clack-style menus work.
 *
 * Usage:
 *   npx plogr-workflow                                   # interactive mode
 *   npx plogr-workflow --help                            # show help
 *   npx plogr-workflow --root-cause claude --task codex  # automation mode
 */

"use strict";

const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");

// ── Locate the PowerShell initializer script ──────────────────────
const scriptsDir = path.join(__dirname, "..", "scripts");
const initScript = path.join(scriptsDir, "Initialize-HerdrProject.ps1");

if (!fs.existsSync(initScript)) {
  console.error(`\x1b[31m✗ Initializer script not found: ${initScript}\x1b[0m`);
  console.error(
    "  This usually means the herdr-init package is corrupted. Reinstall with:"
  );
  console.error("  npx plogr-workflow@latest");
  process.exit(1);
}

// ── Find a PowerShell host ────────────────────────────────────────
function findPowerShell() {
  const candidates =
    process.platform === "win32"
      ? ["pwsh.exe", "powershell.exe"]
      : ["pwsh"];

  for (const cmd of candidates) {
    try {
      const result = require("child_process").execSync(
        process.platform === "win32"
          ? `where ${cmd} 2>nul`
          : `command -v ${cmd} 2>/dev/null`,
        { encoding: "utf8", timeout: 5000 }
      );
      if (result.trim()) return cmd;
    } catch {
      // not found, try next
    }
  }
  return null;
}

const psHost = findPowerShell();
if (!psHost) {
  console.error("\x1b[31m✗ PowerShell (pwsh or powershell) not found.\x1b[0m");
  console.error(
    "  herdr-init requires PowerShell 5.1+ or PowerShell 7+ (pwsh)."
  );
  console.error("  Install from: https://github.com/PowerShell/PowerShell");
  process.exit(1);
}

// ── Map CLI arguments to PowerShell parameters ────────────────────
// npx herdr-init --root-cause claude --task codex --skip-skills-install
// → pwsh -File Init.ps1 -RootCauseKind claude -TaskKind codex -SkipSkillsInstall

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

const cliArgs = process.argv.slice(2);
let i = 0;
while (i < cliArgs.length) {
  const arg = cliArgs[i];
  if (argMap[arg]) {
    const psFlag = argMap[arg];
    // Switch parameters (no value)
    if (
      ["-SkipGitInit", "-SkipSkillsInstall", "-Help"].includes(psFlag)
    ) {
      psArgs.push(psFlag);
      i++;
    } else {
      // Value parameters
      psArgs.push(psFlag);
      if (i + 1 < cliArgs.length) {
        psArgs.push(cliArgs[i + 1]);
        i += 2;
      } else {
        console.error(`\x1b[31m✗ Missing value for ${arg}\x1b[0m`);
        process.exit(1);
      }
    }
  } else if (arg.startsWith("-")) {
    // Pass unknown flags through
    psArgs.push(arg);
    i++;
  } else {
    // Positional — treat as project root
    psArgs.push("-ProjectRoot", arg);
    i++;
  }
}

// ── Launch PowerShell with full stdio inheritance ─────────────────
const child = spawn(psHost, psArgs, {
  stdio: "inherit",
  windowsHide: false,
});

child.on("error", (err) => {
  console.error(`\x1b[31m✗ Failed to start ${psHost}: ${err.message}\x1b[0m`);
  process.exit(1);
});

child.on("exit", (code) => {
  process.exit(code ?? 1);
});
