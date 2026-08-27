<!-- plogr-workflow:managed -->
# Agent Skills

This file is a progressive-disclosure skill index.

## Universal skill

Read this local skill before taking action:

- [Karpathy Guidelines](./.agents/skills/karpathy-guidelines/SKILL.md)

## Master Orchestrator skill

Trigger with /plogr (or /herdr) to dispatch durable multi-agent workflows:

- [Plogr Multi-Agent Orchestrator](./.agents/skills/plogr/SKILL.md)

## Conditional skills

Load only the skill matching the active task:

- Feature implementation: [Task Agent](./.agents/skills/task-agent/SKILL.md)
- Bug diagnosis or repair: [Bugfix Agent](./.agents/skills/bugfix-agent/SKILL.md)
- Read-only investigation: [Research Agent](./.agents/skills/research-agent/SKILL.md)
- Candidate validation or integration: [Verification Agent](./.agents/skills/verification-agent/SKILL.md)
- Knowledge retrieval: [Knowledge Retrieval](./.agents/skills/knowledge-retrieval/SKILL.md)

Do not load all skills at once. After loading a skill, read its `references/` files only when the current phase requires them. Do not load unrelated role skills.

