# Semantic index contract

# Semantic index contract

The project profile supplies an embedding endpoint and model. The endpoint must expose a JSON embedding operation and return a numeric vector.

`Build-KnowledgeIndex.ps1` accepts `-Endpoint` and `-Model` explicitly. `Search-Knowledge.ps1` reads the values persisted in the index. If they are missing or unavailable, the scripts return `unavailable`; they never use lexical or keyword fallback.

