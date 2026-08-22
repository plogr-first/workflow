# Troubleshooting

Use this file only after a launcher/workflow script returns an explicit error. Read that handoff folder's `failure.json` first.

- `HERDR_ENV is not 1`: dispatch must originate from a Herdr-managed pane. `npx plogr-workflow` is an exception and can run from an ordinary project terminal.
- `%1 is not a valid Win32 application`: run `scripts/Repair-HerdrWindowsLauncher.ps1 -Tool <opencode|codex|gemini>`, then retry the launcher.
- Missing profile: run `npx plogr-workflow` from the project root; do not invent profile values.
- Missing result/outcome: inspect the Agent handoff; the watcher will issue one completion reminder. For formal workflows, let the monitor control the next prompt.
- Safe merge failure: leave target tree untouched; record `blocked` with the branch, base SHA, conflict/error, and replay command.
