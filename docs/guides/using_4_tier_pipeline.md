# Using the 4-Tier Verification Pipeline

## Local Development Setup

### Option A: Ollama (Free, Local)

```bash
ollama pull qwen2.5-coder:1.5b
ollama serve
```

### Option B: Anthropic Claude API

```bash
export AXIOM_LLM_API_KEY="your-api-key"
```

## Configuration

- `AXIOM_GATE_L2=1`: Skip L1 Gate (use L2 full verification)
- `data/tactic_cache.json`: Tactic cache location

## Performance Expectations

- Document/config changes: 0.00s (L1 Short-Circuit)
- Simple code changes: < 0.01s (L1 Pure AST)
- Inductive theorems: < 0.1s (Tier 1.5)
- Complex theorems: 1-3s (Tier 2 with cache)
