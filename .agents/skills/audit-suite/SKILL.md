---
name: audit-suite
description: >
  Audit and fix bugs with read-only review first, FIX-TASK confirmation, then minimal
  layered fixes. Modes: global audit (browser QA + static API/code check), static-only,
  fix report IDs, single-bug fix, learn cross-project pitfalls. Use for 全局审查,
  静态审查, 扫bug, 接口对齐, fix all-p0, 修这个bug, 沉淀经验, audit-suite, or
  checking code vs API docs before fixing.
argument-hint: "[mode] audit | audit --code-only | fix F-001 | fix-bug | learn"
disable-model-invocation: true
metadata:
  author: custom
  version: "1.2.0"
---

# Audit Suite

## 启动（3 步，禁止探目录）

1. **Mode Detection**（下表）→ 若不确定，问一句，不要 `ls` skill 文件夹
2. **Read** 目标项目（workspace）的 `CLAUDE.md` 等规则文件 — 不是 skill 安装目录
3. **Execute** 对应 mode；audit/fix-bug 在 🛑 STOP 前 **禁止 Edit 项目源码**

Optional: learn 或用户纠正 finding 时 **Read** 同目录 `knowledge/pitfalls.jsonl`（一行一条 JSON）。

---

## Mode Detection

| User says | Mode | 输出 |
|-----------|------|------|
| 全局扫 / 全局审查 / 还有什么bug / scan / 对齐 | **audit** | `.audit/AUDIT-REPORT-*.md` |
| 静态 / code-only / 不要浏览器 | **audit** (skip QA) | 同上，`QA: SKIPPED` |
| fix F-001 / all-p0 / 修报告 | **fix** | FIX-TASK → FIX-REPORT |
| 单个白屏 / 报错 / 这个bug | **fix-bug** | B-001 → FIX-TASK → FIX-REPORT |
| 记住 / finding不对 / learn / 沉淀 | **learn** | `knowledge/pitfalls.jsonl` |

One symptom → fix-bug. Whole project → audit.

## Rules (always)

- Findings: **BUG | DRIFT | GAP | MISSING** only
- Client field ∉ OpenAPI → **DRIFT**, never「后端加字段」
- **MISSING** = feature doc **and** API doc require it, backend lacks it
- Static: `file:line` + code quote, confidence ≥ 7
- fix-bug: ≤ 3 files unless user approves

## 不要做什么（反例黑名单）

- 审查 / triage 阶段 **Edit / Write** 项目源码
- SUGGESTION / REFACTOR / 无证据的「建议加 API 字段」
- fix 未在 FIX-TASK 列出的 ID 或文件
- learn 写入 repo 名、路径、域名
- 启动时列 skill 目录、读其他 skill（含 gstack qa-only 全文）
- fix-bug 全库 scan 或 qa-only（除非用户明确要求）

---

## Mode: audit

**Input:** 目标 repo。**Output:** `.audit/AUDIT-REPORT-{slug}-{date}.md`

| Step | 动作 | 输出 |
|------|------|------|
| 1 | Read 项目规则 | Report `Rules Applied` |
| 2 | QA（可 skip） | Q-001… |
| 3 | `verify-api-contract.sh` 若存在 | F-xxx 或 `Script: SKIP` |
| 4 | 4× Task subagent readonly | F-xxx JSON |
| 5 | Merge + write report | **🛑 STOP** |

**Skip QA if:** code-only / no dev script / server fails once / user skips browser.

**QA:** dev server → browser MCP → flows + `console --errors` + screenshots → Q-xxx（repro + evidence）。不读源码、不修 bug。

**Static subagents**（4 并行，`readonly: true`）:

| Agent | 输入 | 查什么 |
|-------|------|--------|
| scope | feature doc | MISSING / scope creep |
| api-contract | swagger + backend | DRIFT / GAP |
| frontend-backend | types + services | DRIFT |
| backend-bugs | backend code | BUG |

Feature doc: 用户指定 → `docs/features/`, `DESIGN.md`, `.figma-specs/` → 缺则问一次。

**Subagent 输出**（每行 JSON 或 `NO FINDINGS`）:

```json
{"id":"F-001","severity":"P0","category":"DRIFT","scope_anchor":"GET /users","path":"src/x.ts","line":42,"evidence":"...","impact":"...","confidence":8}
```

Inject: 项目规则摘要 + pitfalls 最近 5 条（若文件存在）+ Rules + 反例黑名单。

**Report 头模板:**

```markdown
# AUDIT REPORT — {feature} — {date}
## Pipeline | Rules Applied
## Findings
## Next: /audit-suite fix F-001 或 all-p0
```

### If → then

| If | Then |
|----|------|
| Dev server 失败 | `QA: BLOCKED`，继续 static |
| 无 feature doc | **BLOCKED**，不猜 scope |
| Subagent 超时 | 部分结果 + 注明 |
| 用户要立即修 | 拒绝 → 请选 ID 后 **fix** mode |

### 🔴 CHECKPOINT · 🛑 STOP

展示摘要 + finding 计数。问修哪些 ID。**不得进入 fix。**

---

## Mode: fix

**Input:** `.audit/AUDIT-REPORT-*.md` + 用户 ID 或 `all-p0`/`all-p0,p1`

| Step | 动作 |
|------|------|
| 1 | Read report；Q-xxx 先 trace 到 `file:line` |
| 2 | Write `.audit/FIX-TASK-{slug}-{date}.md` |
| 3 | **🛑 STOP** — 用户确认 |
| 4 | Edit 仅 listed IDs |
| 5 | `.audit/FIX-REPORT-*.md` |

FIX-TASK 每 ID：`File` · `Change` · `Layer lock` · `Verify`

| If | Then |
|----|------|
| 无 report | **BLOCKED** |
| Q-xxx 无 code trace | 先 trace，不 Edit |
| >3 files | 先问用户 |

---

## Mode: fix-bug

**Input:** 用户 symptom。**Output:** B-001 → FIX-TASK → FIX-REPORT

1. Triage read-only → **B-001**（category, path, evidence, impact）
2. **🛑 STOP**
3. FIX-TASK → **🛑 STOP**
4. Minimal fix（≤3 files）

| If | Then |
|----|------|
| 用户否决 triage | **learn** mode，不 Edit |
| 根因不清 | 问 1 个问题，不 scan 全库 |

---

## Mode: learn

1. 去项目化草案（`[openapi-schema]`、`[client-code]`）
2. **🛑 STOP** — 用户确认
3. Append `knowledge/pitfalls.jsonl`（JSON 一行）
4. 「别再报这类」→ `knowledge/rejections.jsonl`
5. `--promote` → 展示 `knowledge/constraints.md` diff → 用户确认后改

Repo 特例 → 项目 `CLAUDE.md`，不进 pitfalls。

---

## Test Prompt Routing（`test-prompts.json`）

| # | 场景 | Mode | 必过检查 |
|---|------|------|----------|
| 1 | 全局扫 + 不改代码 | audit | 🛑 STOP；零 Edit |
| 2 | --code-only | audit | `QA: SKIPPED` |
| 3 | 单个白屏要修 | fix-bug | 两次 🛑；≤3 文件 |
| 4 | fix all-p0 | fix | FIX-TASK 仅 P0 |
| 5 | learn 纠正 finding | learn | 无 repo 名；确认后写 pitfalls |

Status: **DONE** | **DONE_WITH_CONCERNS** | **BLOCKED**
