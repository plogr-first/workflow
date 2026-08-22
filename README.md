# Portable Plogr workflow

此仓库包含项目级 Herdr/Plogr workflow 和已注册的 skills。克隆后无需 `npx`、无需安装全局 skill：

```powershell
git clone https://github.com/plogr-first/workflow.git
cd workflow
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\herdr-skill\scripts\Initialize-HerdrProject.ps1 -ProjectRoot . -HerdrSessionName default
```

初始化器只写入项目受管目录（`.agents/skills`、各 agent 的 skill 镜像、`herdr/` profile 和 registry），会保留项目已有的 `CLAUDE.md`、`AGENTS.md`、业务源码及其他用户 skill。完成后可从项目根目录使用 `plogr init` 语义对应的本地初始化器和 `.agents/project-skills.json` 注册清单；运行前仅需本机已有 Git、Herdr 以及所选 Agent CLI。

> Windows 上请使用 `.cmd` 形式的 Agent launcher（例如 `codex.cmd`）。无扩展名 npm shim 不能作为 `Start-Process` 的 Win32 目标。
