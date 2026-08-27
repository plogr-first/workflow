# Provider contract

# Provider contract

The project supplies an embedding endpoint and model in its own profile. The Skill does not install, start, or select a provider. The endpoint must expose a JSON embedding operation and return a numeric vector.

`Build-KnowledgeIndex.ps1` accepts `-Endpoint` and `-Model` explicitly. `Search-Knowledge.ps1` reads the values persisted in the index. If they are missing or unavailable, the scripts return `unavailable`; they never use lexical or keyword fallback.
