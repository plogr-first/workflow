# Provider contract

Default provider is Ollama at `http://127.0.0.1:11434`, model `nomic-embed-text`.

Install and prepare once:

```powershell
ollama pull nomic-embed-text
```

The scripts call `POST /api/embed` and require a numeric embedding vector. If the service, model, or response is unavailable, they return a structured `unavailable` result. They do not use lexical or keyword fallback.
