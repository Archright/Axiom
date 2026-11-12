import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/trusted/axiom_pragmas
import std/os


const
  DefaultLedgerPath = ".axiom/cache/pipeline_state.ledger"

proc checkEnvVars*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Pre-flight gate for CI environment variable validation.
  ## Checks required environment variables and fails fast if missing.
  ## Returns true if all required vars are present, false otherwise.
  ##
  ## Required variables:
  ##   - AXIOM_LLM_API_KEY (required for Leanstral LLM calls)
  ##
  ## Optional variables:
  ##   - AXIOM_STATE_LEDGER_PATH (defaults to .axiom/cache/pipeline_state.ledger)
  ##
  ## Context-aware behavior:
  ##   - AXIOM_ENV=ci: Fail-Closed (missing vars → exit 1)
  ##   - AXIOM_ENV=dev (default): Soft-Skip (missing vars → warning, continue)
  ##
  ## Usage: AXIOM_ENV=dev make ci-local

  let envMode = getEnv("AXIOM_ENV", "dev")
  let isCiMode = (envMode == "ci")

  var allPresent = true

  let llmKey = getEnv("AXIOM_LLM_API_KEY")
  if llmKey.len == 0:
    if isCiMode:
      echo "[FAIL] AXIOM_LLM_API_KEY is not set"
      echo "       Required for Leanstral LLM calls (docs/spec/legislator_llm_only_policy.md)"
      allPresent = false
    else:
      echo "[SKIP] AXIOM_LLM_API_KEY is not set (dev mode - soft skip)"
  else:
    echo "[OK]   AXIOM_LLM_API_KEY is set"

  let ledgerPath = getEnv("AXIOM_STATE_LEDGER_PATH", DefaultLedgerPath)
  if ledgerPath.len == 0:
    echo "[WARN] AXIOM_STATE_LEDGER_PATH using default: " & DefaultLedgerPath
  else:
    echo "[OK]   AXIOM_STATE_LEDGER_PATH is set: " & ledgerPath

  return allPresent

proc runCheckAndExit*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run environment variable check and exit with appropriate code.
  ## Use this as the main entry point for CLI execution.
  let allPresent = checkEnvVars()
  if not allPresent:
    quit(1)

{.pop.}