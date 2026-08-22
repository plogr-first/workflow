# Project Rules Discovery

Read from **target project root** (workspace being audited), not the skill install path.

## Search Order

1. `CLAUDE.md`
2. `AGENTS.md` / `agents.md`
3. `.cursor/rules/` (all `.md`, `.mdc`)
4. `rules.md`
5. Architecture docs referenced by the above

## Report Header

```markdown
## Rules Applied
- Project: CLAUDE.md (found|missing), ...
- Skill knowledge: constraints, pitfalls N, rejections M
```

## Precedence

Project rules > `knowledge/constraints.md` > `knowledge/pitfalls.jsonl`

Summarize long rule files; inject relevant sections into subagent prompts.
