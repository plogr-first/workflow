# Execution Topology

Before editing or dispatching, record the dependency graph in progress tracking and `result.md`.

## Serial chain

Sequence work when a downstream task depends on an upstream contract, schema, interface, or behavior. Typical chain: API/schema → backend behavior → generated client/types → UI integration → end-to-end checks.

## Parallel batch

Parallelize only genuinely independent scopes with separate files, contracts, and checks. Give each subagent a narrow scope, worktree, acceptance check, and handoff path.

## Decision record

State why each item is serial or parallel. If dependencies are uncertain, keep the work serial until the contract is confirmed.
