---
name: herdr
description: "Use when the user explicitly invokes /herdr or asks to launch, coordinate, receive results from, or repair Claude, OpenCode, Gemini, or Codex agents through Herdr. Provides fast background-agent dispatch, full-access launch profiles, durable project-local handoffs, worktree decision and safe integration, OpenCode Zen/Go model selection, completion notifications, and collection of multiple agent results. Requires HERDR_ENV=1."
---

# /herdr — 通用 Herdr Agent 派遣

## 快速派遣硬规则

普通 `/herdr` 派遣必须直接调用 `scripts/Start-HerdrAgent.ps1`。**不要**在启动前通过 shell 读取 `references/herdr-core.md`、运行 `herdr agent`、`herdr pane list`、`opencode models`、环境变量 echo 或脚本源码查看；启动脚本内部已完成最少必要的等待、模型解析与状态记录。

只有脚本返回明确错误，才读取 `references/herdr-core.md` 和对应 `failure.json` 做诊断。核心参考用于异常恢复，不能成为每次启动的前置步骤。

将 `/herdr` 视为 Herdr 的通用、快速子 Agent 入口。适用于调研、实现任务、修复 bug 与验收。**先读取并遵守 [Herdr 核心控制规则](references/herdr-core.md)**；本 Skill 只在其基础上补充快速派遣、完全访问配置、交接与回收。随后运行 `scripts/Start-HerdrAgent.ps1`；不要手拼 pane ID 或靠 UI 焦点猜测目标。

## 0. 前置检查

1. 确认 `$env:HERDR_ENV -eq '1'`；不满足则停止。
2. 运行 `herdr agent`，仅使用当前 CLI 列出的 kind。
3. Windows 上对每个首次使用的 CLI 运行 `Start-Process <tool> --version`。若报 `%1 不是有效的 Win32 应用程序`，停止派遣并执行“Windows npm shim 修复”。
4. 默认在调用方所在项目创建交接目录。不得把 Cookie、Token、密码或原始凭据写入交接文件。

## 1. 固定交接命名

每次派遣必须创建唯一目录：

```text
<project>\herdr\<category>\YYYY-MM-DD\HHmmss--<agent-name>--<slug>\
```

- `<category>` 只能为：`research`、`task`、`bugfix`。
- `<agent-name>`：`[a-z][a-z0-9_-]{0,31}`，例如 `fix_api`。
- `<slug>`：小写 ASCII、数字、连字符，例如 `cookie-validation`。
- 文件名固定：`brief.md`（派遣输入）、`status.json`（启动记录）、`result.md`（Agent 完整结论）、`verification.md`（主 Agent 的独立验收，按需创建）。

禁止将结果仅留在 TUI 回复中：长结果必须写入 `result.md`。

## 1.5 Task / bugfix 的 Worktree 决策、验收与合并

此节优先于 `references/herdr-core.md` 中“未明确请求则不创建 worktree”的通用默认值。对 `task`、`bugfix`，即使用户没有提到 worktree，也必须由执行 Agent 在**写代码前**做一次最小 Git 决策；`research` 默认只读，不创建 worktree。

1. 记录并检查：仓库是否为 Git、当前目标分支、`git status --short`、已有 worktree，以及是否有其他 Agent/用户可能同时改动相同文件。
2. 需要隔离时必须创建独立分支和 worktree，典型条件：目标工作树已有非本任务改动、存在并发实现 Agent、修改范围可能重叠，或需要保持主工作树可继续使用。分支名使用 `herdr/<category>/<agent>-<slug>-<timestamp>`；不得在共享主工作树直接改动。
3. 仅当目标工作树干净、无冲突且任务确实很小并且不存在并发/重叠写入风险时，才可决定不使用 worktree。不能因为“用户没说”而跳过判断。
4. 在 worktree 完成修改后，先在该 worktree 验证；再回到目标工作树，重新确认干净和目标分支未意外变化，合并该任务分支；随后在**合并后的目标工作树**再次运行适用验证。不得把“分支内测试通过”当作最终完成。
5. 合并出现冲突、目标工作树不干净、目标分支变化导致无法安全合并，或验证失败时：停止，不强行 `reset`、`checkout -- .`、`clean`、stash 或覆盖他人改动；在 `result.md` 写清阻塞与可复现处理步骤，并发送“需要处理”通知，不得宣称任务完成。
6. `result.md` 必须额外写明：是否使用 worktree、判定依据、worktree 路径、分支、提交 SHA、合并命令/结果、合并后验证结果；未使用时必须写明不使用的依据。安全合并成功后可移除该 worktree；保留可追溯提交 SHA。

## 2. 一条命令后台派遣

使用脚本。它创建交接目录、分割当前 pane、以 `--no-focus` 启动 Agent、写入 brief/status，并下发“写 result.md + Herdr 通知”的任务。脚本不会等待完成，因此不需要持续盯 pane。

```powershell
& 'C:\Users\Lenovo\.codex\skills\herdr\scripts\Start-HerdrAgent.ps1' `
  -Kind opencode -Name audit_api -Category research -Slug api-contract `
  -Prompt '只读审计当前 API 合同与实现差异。' `
  -OpenCodeModel 'opencode/deepseek-v4-flash-free'
```

`-Access full` 是默认值，并将以下完整访问参数传给各 Agent。只有用户明确要求只读/计划模式时才使用 `-Access plan`。OpenCode 在本机 Herdr/Windows 组合下已实测 `agent prompt` 可能不触发生命周期，脚本对 OpenCode 自动改用 `pane send-text` + `enter` 的已验证回退：

| Kind | 完全访问启动参数 | 计划/只读参数 |
|---|---|---|
| `claude` | `--dangerously-skip-permissions` | `--permission-mode plan` |
| `opencode` | `--auto`（自动批准未被显式拒绝的权限） | 不传 `--auto`，沿用交互审批 |
| `gemini` | `--yolo` | `--approval-mode plan` |
| `codex` | `--dangerously-bypass-approvals-and-sandbox` | `-s workspace-write -a on-request` |

完整访问仅在用户已明确授权的隔离环境中使用；不要静默降级为只读。

## 3. OpenCode 模型选择

每次启动前先查询真实可用模型：

```powershell
opencode models
```

脚本先执行 `opencode models`，实际输出是唯一权威。它支持精确 ID、大小写/连字符忽略形式，以及下面的快捷别名：

```text
zen | zen-free | deepseek-v4-flash-free
  -> opencode/deepseek-v4-flash-free

go | go-flash | deepseek-v4-flash
  -> opencode-go/deepseek-v4-flash
```

已实测可由 Herdr 启动的模型：

```text
opencode/deepseek-v4-flash-free    # OpenCode Zen
opencode-go/deepseek-v4-flash      # OpenCode Go
```

示例：

```powershell
# Zen：短名称可用
... -Kind opencode -OpenCodeModel zen ...
# Go：短名称可用
... -Kind opencode -OpenCodeModel go ...
```

如果输入如 `deepseek-v4-flash` 同时匹配多个模型，脚本会拒绝启动并列出候选项；不要静默猜测。

## 4. 完成提醒与多 Agent 收集

Agent 完成时必须：

1. 写完整 `result.md`；
2. 在最终 TUI 回复中只给“结论摘要 + 结果路径”；
3. 执行：

```powershell
herdr notification show "Herdr: <agent-name> 已完成" --body "<category>/<folder>/result.md" --sound done
```

通知是 UI 提醒，**不会自动将完整报告注入主 Agent 对话**。每次派遣均有后台交接监控：它确认 `result.md` 存在才发送“交接已就绪”；若 Agent 返回却未写结果，则自动催交一次，仍失败才发送“交接违规”。主 Agent 不必轮询：在用户下一次询问或收到完成通知后，逐个执行：

```powershell
herdr agent get <agent-name>
herdr agent read <agent-name> --source detection --lines 120
Get-Content '<absolute-result-path>' -Raw
```

多个 Agent 可同时完成：每个拥有独立目录、独立通知和独立 `result.md`。逐个读取并在 `verification.md` 记录独立验收；`idle` 仅表示就绪/完成，不等于工作正确。

## 5. 返工与清理

返工必须复用同名、仍存活的 Agent：

```powershell
herdr agent prompt <agent-name> '根据 verification.md 的失败项修复，并覆写 result.md。' --wait --timeout 120000
```

不要另起会话丢失上下文。仅关闭由本次派遣创建且已完成的 pane；不要关闭用户已有 pane、tab、workspace 或 Herdr server。

## Windows npm shim 修复

Herdr 内部以 `Start-Process -FilePath <tool>` 启动。npm 的无扩展名 Unix shim 或 `.ps1` shim 可能被错误解析，报 `%1 不是有效的 Win32 应用程序`。对受影响工具（`opencode`、`codex`、`gemini`）执行：

```powershell
& 'C:\Users\Lenovo\.codex\skills\herdr\scripts\Repair-HerdrWindowsLauncher.ps1' -Tool opencode
```

该脚本会先备份 shim 为 `.sh` / `.ps1.disabled`，再用 Herdr 同款 `Start-Process` 验证。npm 重装/升级后如错误复现，重新运行此修复并验证。
