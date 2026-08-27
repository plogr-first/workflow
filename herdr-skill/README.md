# Plogr Workflow

Plogr Workflow 是一个基于 Herdr 的持久化多 Agent 编排器：为每个项目注册真实的项目级 Skills，按角色启动 Agent，并以 `result.md`、`outcome.json` 和 Git worktree 作为可验证交接凭证。

## 安装

无需克隆仓库，在目标项目目录执行：

```powershell
npx -y plogr-workflow@latest init
```

也可以全局安装：

```powershell
npm install -g plogr-workflow
plogr init
```

初始化会：

- 生成 `herdr/dispatch-profile.json`；
- 注册 `.agents/skills` 以及已选择 Agent 的 `.claude/skills`、`.codex/skills`、`.opencode/skills`、`.gemini/skills`、`.cursor/skills`；
- 写入 `.agents/project-skills.json` 完整 SHA256 清单；
- 追加工作流指针到 `AGENTS.md` 与 `CLAUDE.md`。已有内容保留，重复 init 不会重复追加。

## 常用命令

```powershell
plogr show                         # 查看角色配置
plogr task "实现一个功能"           # 功能开发流程
plogr bugfix "描述可复现故障"        # audit -> diagnosis -> repair -> review
plogr parallel '<matrix-json>'     # worktree 矩阵并行流程
plogr status                       # 状态快照
plogr hud                          # 实时 HUD
```

角色由 `plogr init` 选择：root-cause、task、verification、research。Task Agent 决定是否拆分 implement subagents；Verifier 只在候选交接具备持久化证据后唤醒。

## 语义知识检索（可选）

项目初始化默认关闭 embedding 检索。启用时由项目自行提供 embedding provider：

```powershell
& .agents/skills/knowledge-retrieval/scripts/Build-KnowledgeIndex.ps1 -Endpoint $env:EMBEDDING_ENDPOINT -Model $env:EMBEDDING_MODEL
& .agents/skills/knowledge-retrieval/scripts/Search-Knowledge.ps1 -Context "当前任务描述"
```

配置位于 `herdr/dispatch-profile.json` 的 `knowledge_retrieval` 节点。索引不存在或 embedding 服务不可用时会明确返回 `unavailable`，不会退化为关键词匹配；本包不安装或依赖 Ollama。

## 发布与迭代

源码位于 GitHub：<https://github.com/plogr-first/workflow>；npm 包：<https://www.npmjs.com/package/plogr-workflow>。

更新代码后递增版本并发布：

```powershell
npm version minor
git push origin main --follow-tags
npm publish --access public
```

## 验证

```powershell
npm run test:contract
npm test
```

完整测试使用本地 mock Herdr，不触碰用户业务代码。
