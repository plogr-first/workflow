---
name: knowledge-retrieval
description: Progressive-disclosure project knowledge retrieval Skill. Use when a workflow agent needs prior project decisions, pitfalls, case cards, architecture knowledge, or evidence from .knowledge.
---

# Knowledge Retrieval

Use this skill before acting on prior project knowledge when the project profile enables `knowledge_retrieval`.

1. Read `herdr/dispatch-profile.json` and verify `knowledge_retrieval.enabled`.
2. Run `scripts/Search-Knowledge.ps1` with the current role, phase, task, relevant paths, error text, and workflow state.
3. Read only the returned source files and apply only evidence-backed results.
4. If the script returns `unavailable`, record that state in `progress.json`/`result.md`; do not replace it with keyword matching.
5. When a durable case is learned, add a redacted Markdown card under `.knowledge/cards/`, then rebuild the index with the provider configured by the project.

Read [references/provider-contract.md](references/provider-contract.md) only when configuring or troubleshooting the embedding provider.
