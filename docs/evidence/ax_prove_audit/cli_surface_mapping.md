# CLI Surface Audit: ax prove

## 1. Dispatch Chain

```
[Shell] ax prove --full src/
    │
    ▼
src/cli/main.nim:runMain()
    │
    ▼
src/cli/main.nim:runCli(args)
    │
    ▼
src/cli/action_plan_cli.nim:planAxActions(args)
    │
    ├── parsedSubcommand = "prove" → axSubcommandProve
    │
    ▼
src/cli/action_plan_cli.nim:158 ── shouldUseAxProofShortcut(subArgs)
    │
    ├─ TRUE (for --full, --heal, --retry-failed, positional args, etc.)
    │   │
    │   ▼
    │   cliRunAxProofShortcut ──► src/cli/action_interpreter_cli.nim:45
    │       │
    │       ▼
    │       runAxProveShortcutCli(action.args)
    │           │
    │           ▼
    │           analyzeTopologySourceRoot(sourceRoot, ...)
    │           persistAxProofState(statePath, reportJson)
    │           [NO UAP INVOCATION]
    │
    └─ FALSE (only when --payload-file is present)
        │
        ▼
        cliCommandVerify ──► normalizeAxVerifyAliasArgs("prove", subArgs)
            │
            ▼
            @["workflow"] & args
            │
            ▼
        src/cli/symbolic_cli.nim:59 ── cmdVerifyWorkflow(args)
            │
            ▼
        src/cli/verify_workflow_cli.nim:424 ── cmdVerifyWorkflow(args)
            │
            ▼
        src/cli/verify_workflow_cli.nim:452 ── runBatchUapOrchestration(...)
            │
            ▼
        src/verification/batch_uap_orchestrator.nim:60 ── runBatchUapOrchestration(...)
            │
            ▼
        src/verification/batch_uap_orchestrator.nim:145 ── runUniversalAcceptancePipeline(...)
            │
            ▼
        [4-Layer Persona Pipeline Executes]
```

## 2. Disconnect Analysis

### The Critical Gate: `shouldUseAxProofShortcut`

**Location**: `src/cli/ax_workflow_shortcuts.nim:58`

```nim
func shouldUseAxProofShortcut*(args: seq[string]): bool {.nosideeffect.} =
  if args.anyIt(it == "--payload-file"):
    return false
  if args.len == 0:
    return true
  args.anyIt(it == "--limit") or args.anyIt(it == "--state-file") or
    args.anyIt(it == "--vault-dir") or args.anyIt(it == "--jobs" or it == "-j") or
    args.anyIt(it == "--json") or args.anyIt(not isCliOptionToken(it)) or
    args.anyIt(it == "--full" or it == "--retry-failed" or it == "--heal" or
      it == "--formal-only" or it == "--single-thread" or it == "--require-perfect-asi" or
      it == "--continue-on-error" or it == "--graph-cache" or it == "--no-graph-cache")
```

### The Paradox

| Flag | User Intent | `shouldUseAxProofShortcut` | Actual Behavior |
|---|---|---|---|
| `--full` | "Run full pipeline re-run" | `true` | Topology scan only |
| `--heal` | "Enter self-healing mode" | `true` | Topology scan only |
| `--retry-failed` | "Retry vacuous/unverifiable" | `true` | Topology scan only |
| (positional arg, e.g., `src/`) | "Prove this directory" | `true` | Topology scan only |
| `--payload-file` | "Provide workflow payload" | `false` | **UAP pipeline runs** |

### Root Cause

The shortcut path (`cliRunAxProofShortcut`) was designed for fast topology-only operations, but its predicate (`shouldUseAxProofShortcut`) is **overly broad**. It captures the flags intended for the full pipeline (`--full`, `--heal`) and routes them to the topology-only shortcut.

There is **no branch inside `runAxProveShortcutCli`** that checks `flags.executionMode` and escalates to `runBatchUapOrchestration`.

### Impact

- **User-visible**: `ax prove --full src/` performs a topology scan and exits. No verification, no proof, no BMC, no CEGAR, no Lean.
- **Specification breach**: Notion spec v0.3.7 promises a 4-layer pipeline for `ax prove`. The CLI surface makes this promise unreachable for standard invocations.

## 3. Flag Consumption Audit

### `parseAxProveFlags` parses but does not drive behavior

`src/cli/cli_surface_generated.nim:16` correctly parses:
- `--full` → `executionMode = evFull`
- `--retry-failed` → `executionMode = evRetryFailed`
- `--heal` → `executionMode = evHeal`

However, `src/cli/wf_runners.nim:138` (`runAxProveShortcutCli`) never reads `flags.executionMode`.

### `buildIntegratedHealArgs` is dead code for `ax prove`

`src/cli/wf_runners.nim:42` defines `buildIntegratedHealArgs` which maps `executionMode` to CLI flags, but this function is **never called** by `runAxProveShortcutCli`.

## 4. Indirect Invocation Paths

### No subprocess bridge
`runAxProveShortcutCli` does not spawn `ax verify workflow` or `ax integrity uap` as a subprocess.

### No state-file trigger
`persistAxProofState` writes a JSON file, but there is no background watcher or subsequent command that reads this file to auto-trigger UAP.

### No heal bridge
`runAxProveShortcutCli` does not call `runAxHealCli` or any healing subsystem.

## 5. Verdict

| Criterion | Status | Evidence |
|---|---|---|
| `ax prove` reaches UAP engine | **FAIL** | `shouldUseAxProofShortcut` returns `true` for all standard flags, routing to shortcut path |
| `--full` triggers full pipeline | **FAIL** | Parsed but ignored; topology scan only |
| `--heal` triggers self-healing | **FAIL** | Parsed but ignored; topology scan only |
| CLI help text accuracy | **FAIL** | Help promises "full pipeline re-run" but implementation delivers topology scan |
| `--payload-file` bypass works | **PASS** | Only known path to UAP from `ax prove` |

**Severity**: Critical — the primary user-facing command for verification is structurally disconnected from the verification engine.
