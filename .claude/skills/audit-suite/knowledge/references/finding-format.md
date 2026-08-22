# Finding Format

## ID Prefixes

| Prefix | Source |
|--------|--------|
| Q-xxx | qa-only runtime |
| F-xxx | Static audit |
| B-xxx | Ad-hoc bug (fix mode) |
| X-xxx | Merged finding |

## Static Finding

```markdown
### [P0|P1|P2] F-001 — Title
- **Category**: BUG | DRIFT | GAP | MISSING
- **Scope anchor**: [feature-doc §X] | [GET /path] | [project rule]
- **Location**: `path/file.ext:42`
- **Evidence**: verbatim code block
- **Impact**: user/system effect
- **Confidence**: N/10
- **Fix direction**: one line (fix modes only)
```

## Report Path (target project)

`.audit/AUDIT-REPORT-{slug}-{YYYY-MM-DD}.md`

QA artifacts: `.gstack/qa-reports/` (gstack qa-only)
