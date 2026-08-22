# Merge Safety

Before merging, confirm the target tree is clean, still at the expected base, and unrelated changes are preserved. Use normal Git integration only; never force reset, clean, stash, or overwrite. After merging, run applicable post-merge checks and record the merge SHA. The workflow monitor owns any configured push or PR action.
