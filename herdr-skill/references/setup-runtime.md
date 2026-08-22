# Setup and runtime

Run `plogr init` at a project root to select task, verification, and research profiles. It writes `herdr/dispatch-profile.json` and registers the bundled project skills without invoking `npx skills`.

The init wrapper is installed by `scripts/Install-HerdrInitCommand.ps1` for PowerShell/CMD and the current WSL Bash account. It forwards non-`init` commands to the official Herdr executable. Re-run the installer after changing wrapper logic; open a new terminal after installation.

Initialization also binds the project to one named persistent Herdr session and records a verified official mattpocock engineering manifest (`research`, `implement`, `diagnosing-bugs`, `code-review`, and `tdd`). Each recorded skill has an exact `SKILL.md` hash match against the official source snapshot. After a restart, run `herdr resume`; it uses this binding and never searches other sessions. When multiple workflows are unfinished, select one by workflow ID or explicitly pass `--all`.

By default, init runs `git init` only if the project is not already a repository, and creates a minimal `.gitignore` for `herdr/` and `.worktrees/`. It never makes a baseline commit or creates/publishes a remote without explicit direction. If an existing repository has remotes, interactive init offers post-merge submission (`manual`, `after_merge` using `gh` / git push, or `create_pr` using `gh pr create`); select it only for a remote you intend to publish to. With `push_policy: after_merge` or `create_pr`, the monitor performs the actual push/PR creation using the GitHub CLI (`gh`) after a verified local merge and records any failure without rolling the merge back.

Known full-access profiles are encapsulated by the launcher:

- claude: `--dangerously-skip-permissions`
- gemini: `--yolo`
- codex: `--dangerously-bypass-approvals-and-sandbox`
- opencode: `--auto`

OpenCode model IDs are resolved from `opencode models`; use a profile or an explicit exact model ID. For a custom Herdr kind, init verifies a supported kind and executable, and records user-supplied full-access arguments.
