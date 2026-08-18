# Setup and runtime

Run `herdr init` at a project root to select task, verification, and research profiles. It writes `herdr/dispatch-profile.json` and then runs `npx skills@latest add mattpocock/skills`.

The init wrapper is installed by `scripts/Install-HerdrInitCommand.ps1` for PowerShell/CMD and the current WSL Bash account. It forwards non-`init` commands to the official Herdr executable. Re-run the installer after changing wrapper logic; open a new terminal after installation.

Initialization also binds the project to one named persistent Herdr session and records a real mattpocock skill capability manifest (`implement`, `investigate`, `review`, `qa`, debugging, testing, and worktree skills). After a restart, run `herdr resume`; it uses this binding and never searches other sessions. When multiple workflows are unfinished, select one by workflow ID or explicitly pass `--all`.

By default, init runs `git init` only if the project is not already a repository, and creates a minimal `.gitignore` for `herdr/` and `.worktrees/`. It never makes a baseline commit or creates/publishes a remote. If an existing repository has exactly one remote, interactive init offers post-merge pushing; select it only for a remote you intend to publish to. With `push_policy: after_merge`, the monitor performs the actual push after a verified local merge and records any failure without rolling the merge back.

Known full-access profiles are encapsulated by the launcher:

- claude: `--dangerously-skip-permissions`
- gemini: `--yolo`
- codex: `--dangerously-bypass-approvals-and-sandbox`
- opencode: `--auto`

OpenCode model IDs are resolved from `opencode models`; use a profile or an explicit exact model ID. For a custom Herdr kind, init verifies a supported kind and executable, and records user-supplied full-access arguments.
