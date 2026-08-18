# Setup and runtime

Run `herdr init` at a project root to select task, verification, and research profiles. It writes `herdr/dispatch-profile.json` and then runs `npx skills@latest add mattpocock/skills`.

The init wrapper is installed by `scripts/Install-HerdrInitCommand.ps1` for PowerShell/CMD and the current WSL Bash account. It forwards non-`init` commands to the official Herdr executable. Re-run the installer after changing wrapper logic; open a new terminal after installation.

Known full-access profiles are encapsulated by the launcher:

- claude: `--dangerously-skip-permissions`
- gemini: `--yolo`
- codex: `--dangerously-bypass-approvals-and-sandbox`
- opencode: `--auto`

OpenCode model IDs are resolved from `opencode models`; use a profile or an explicit exact model ID. For a custom Herdr kind, init verifies a supported kind and executable, and records user-supplied full-access arguments.
