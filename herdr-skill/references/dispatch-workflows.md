# Herdr dispatch workflows

Use exactly one of these flows. The main dispatcher owns state transitions and reads every `result.md`; a terminal state is never inferred from an agent being `idle`.

## Shared protocol

- Every agent gets a unique handoff folder and must write `result.md`.
- State names: `candidate`, `passed`, `fix_required`, `blocked`, `merged`.
- The verification agent reports only reproducible P0/P1 blockers and at most five items. Each item names the acceptance rule, file/command evidence, and the smallest expected repair.
- A verifier must not make speculative style suggestions a condition of passing. Standards findings that are already enforced by lint/format tools are not duplicated.
- The dispatcher permits one repair round. It reuses the same execution agent and same worktree. The verifier then rechecks the reported changes and all affected gates. A second unresolved failure is `blocked`, not an infinite loop.
- Never hide a failed gate by changing the acceptance rule. Never force a merge, reset, clean, stash, or overwrite unrelated work.

## 1. Deep research

Dispatch using `-Profile research` and category `research`.

### Research-agent contract

1. Define the precise question, scope, freshness date, and decision the research should support.
2. Prefer primary evidence: official documentation, source repositories, standards, first-party APIs, live reproducible behaviour, or original data. Secondary articles may only provide leads.
3. Write a claim ledger: each decision-critical claim has source URL/path, exact excerpt or captured evidence, access date, and confidence.
4. Include contradictory evidence, unresolved points, and explicit non-claims. Do not turn missing evidence into a conclusion.
5. Save one Markdown report in the handoff folder or the repo's established research location; do not modify product code.

### Research verification gate

The verification agent audits decision-critical claims, source provenance, and scope coverage. Pass only if every decisive claim is backed by appropriate primary evidence or explicitly marked uncertain. It may request one repair round for missing/mismatched evidence. It never requests prose polishing as a blocker.

## 2. Task dispatch

Dispatch implementation using `-Profile task` and category `task`.

### Execution-agent contract

1. Read the provided task brief and define observable acceptance checks before editing.
2. Inspect the current Git tree and decide whether an isolated worktree is required. Use one for dirty shared trees, concurrent work, or overlap risk.
3. Implement the smallest complete change. Use the project's test conventions; follow `implement`, `tdd`, and `codebase-design` principles where they fit the established seams.
4. Run focused tests/type checks, then the relevant full validation. Commit the candidate change on its task branch.
5. Report the worktree path, branch, base commit, candidate SHA, changed files, commands/results, and remaining limitations. Mark `candidate`; do not merge the candidate branch.

### Verification gate

The verification agent evaluates the candidate branch/worktree on four independent gates:

1. **Outcome:** all stated acceptance checks pass against the requested behaviour.
2. **Regression:** relevant automated checks pass; a changed behavioural path has a meaningful regression check, or the absence of a valid seam is documented.
3. **Spec/scope:** the diff fulfills the brief without omitted requirements or unrequested scope expansion.
4. **Standards/integration:** the diff complies with repository rules, no P0/P1 review finding remains, and Git integration can be performed safely.

On pass, the verification agent merges into the intended target only after confirming the target worktree is clean and still at the expected base. It then reruns the applicable post-merge validation and reports `merged` with the merge SHA. If it cannot safely merge, it reports `blocked`; it does not force integration.

## 3. Bugfix

Dispatch diagnosis and repair using `-Profile task` and category `bugfix`; use `-Profile verification` for the gate.

### Bugfix execution-agent contract

Follow `diagnosing-bugs` before editing:

1. Build and run a narrow, red-capable feedback loop for the user-reported symptom. Record the command, observed failure, and the real code path it exercises.
2. Minimise the reproduction and form 3–5 falsifiable hypotheses. Test one variable at a time.
3. Add a regression test at the correct seam where possible, make it red, fix the cause, then make it green.
4. Re-run the original reproduction, clean temporary instrumentation, commit the candidate branch, and report `candidate`.

If no red-capable loop can be built, report `blocked` with the attempted paths and the exact missing artifact/access. Do not ship a guess-based patch.

### Bugfix verification gate

The verifier independently runs the original reproduction and regression test, confirms the specific symptom is gone, checks no debug instrumentation remains, then applies the four task gates. It merges only after a pass and safe target-tree check.
