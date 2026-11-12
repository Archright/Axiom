> **Status: Legacy (2026-11-06).** The Leanstral/Mistral HTTP API provisioning
> described in Option B is retired: the shared API key was revoked and the
> provisioning block was removed from `.envrc` (credential purge, SAL 1.0
> publication preparation). This document is retained as a historical setup
> reference; it does not describe a currently provisioned integration.

# LLM API Setup Guide for Axiom Phase 4

## Overview
Axiom's VC pipeline uses LLM to generate Lean 4 tactics. The system supports multiple backends via environment variables.

## Option A: CLI Tool (Recommended for Local Development)

### Supported CLI Tools
- **Kimi Code CLI**: `AXIOM_LLM_CMD="kimi"`
- **OpenCode**: `AXIOM_LLM_CMD="opencode run"`
- **Ollama**: `AXIOM_LLM_CMD="ollama run deepseek-r1"`

### Setup
1. Install your preferred CLI tool
2. Set environment variable:
   ```bash
   export AXIOM_LLM_CMD="kimi"
   ```
3. Test: `echo "test" | kimi` (should return response)

### Priority
1. `AXIOM_LLM_CMD` env var
2. Auto-detect PATH: `kimi` -> `opencode` -> `ollama`
3. Disable LLM (pure Fast-Path only)

## Option B: HTTP REST API

### Supported APIs
- **Mistral AI**: `https://api.mistral.ai/v1/chat/completions`
- **OpenAI**: `https://api.openai.com/v1/chat/completions`
- **Ollama Local**: `http://localhost:11434/v1/chat/completions`

### Setup
1. Get API key from provider
2. Set environment variables:
   ```bash
   export AXIOM_LLM_API_URL="https://api.mistral.ai/v1/chat/completions"
   export AXIOM_LLM_API_KEY="your-api-key-here"
   export AXIOM_LLM_MODEL="mistral-large-latest"  # optional
   ```
3. Test: `curl -H "Authorization: Bearer $AXIOM_LLM_API_KEY" $AXIOM_LLM_API_URL`

### Priority
1. `AXIOM_LLM_API_URL` + `AXIOM_LLM_API_KEY` env vars
2. Fallback to CLI tool (`AXIOM_LLM_CMD`)
3. Disable LLM (pure Fast-Path only)

## Option C: Leanstral AI (Axiom Default)

### Setup

1. **API Key**: Stored in `~/.leanstral_api_key` (mode 600):
   ```bash
   echo "your-api-key-here" > ~/.leanstral_api_key
   chmod 600 ~/.leanstral_api_key
   ```

2. **Environment** (auto-loaded via `.envrc`):
   ```bash
   export AXIOM_LLM_API_URL="https://api.leanstral.ai/v1/chat/completions"
   export AXIOM_LLM_API_KEY="$(cat ~/.leanstral_api_key)"
   export AXIOM_LLM_MODEL="labs-leanstral-2603"
   export AXIOM_LLM_CMD=""  # Empty disables CLI fallback → forces HTTP API
   ```

3. **Test connectivity**:
   ```bash
   curl -s -X POST "$AXIOM_LLM_API_URL" \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer $AXIOM_LLM_API_KEY" \
     -d '{"model":"labs-leanstral-2603","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}'
   ```

### Fallback Behavior

- If `AXIOM_LLM_API_URL` is empty or curl returns HTTP error → falls back to CLI tool (`AXIOM_LLM_CMD`)
- If CLI tool also unavailable → pure Fast-Path (`by simp`)

### Expected Response (healthy)

```json
{"choices":[{"message":{"content":"Hello!"}}]}
```

### No API Key?

Without a valid key, `queryViaHttpRest` returns `none(string)` and the pipeline
falls through to Fast-Path (`by simp`). No crash — just reduced verification power.

## Environment Variable Reference

| Variable | Description | Default | Required |
|-----------|-------------|---------|----------|
| `AXIOM_LLM_CMD` | CLI command for stdin/stdout pipe | `"kimi"` | No |
| `AXIOM_LLM_API_URL` | HTTP API endpoint (OpenAI-compatible) | None | No |
| `AXIOM_LLM_API_KEY` | API key for HTTP REST | None | No* |
| `AXIOM_LLM_MODEL` | Model name for API calls | `"labs-leanstral-2603"` | No |

*Required if `AXIOM_LLM_API_URL` is set.

## Troubleshooting

### "LLM backend not available" error
- Check environment variables: `echo $AXIOM_LLM_CMD`
- Verify CLI tool in PATH: `which kimi`
- Verify API key: `echo $AXIOM_LLM_API_KEY`

### Tactic generation fails
- Check `AXIOM_LLM_CMD` points to correct executable
- Verify API endpoint is OpenAI-compatible
- Check network connection for HTTP API

### Pipeline falls back to "by simp"
- This is normal behavior (Fast-Path)
- Check if LLM backend is properly configured
- Check logs for LLM invocation errors
