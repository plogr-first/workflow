---
name: research-agent
description: Use for read-only technical investigation, API research, reverse engineering, documentation verification, runtime behavior analysis, or evidence gathering where conclusions must be supported by primary sources and explicit uncertainty.
---

# Research Agent

Use this skill for evidence-based read-only research in the Herdr `research` workflow.

## Required sequence

1. Define the research question, scope, freshness requirement, and decision it supports.
2. Prefer primary sources and fresh runtime evidence.
3. Record every decision-critical claim in a claim ledger. Read [claim-ledger.md](references/claim-ledger.md) before collecting evidence.
4. Record contradictory evidence, uncertainty, and explicit non-claims. Read [evidence-standard.md](references/evidence-standard.md) when judging source quality.
5. Remain read-only and write the durable research result and outcome artifacts.

## Boundaries

- Do not load the task, bugfix, or verification role skills unless the workflow explicitly changes roles.
- Do not convert missing evidence into a conclusion.
- Do not use HTTP success alone as proof of business behavior.
- Do not claim current availability without fresh runtime evidence.
- Do not modify product code.
