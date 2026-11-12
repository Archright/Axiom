# Compile-Time Purity Tester

## Overview

The `proc_to_func_tester` tool uses the Nim compiler itself to determine which `proc` declarations
can safely be converted to `func`. This eliminates agent-based heuristic classification — the
compiler is the single source of truth for side-effect detection.

## How It Works (O(1) Batch)

1. Scans `src/` for all `.nim` files
2. Identifies `proc` declarations (excluding already-annotated and already-`func`)
3. Creates shadow files (`*_shadow.nim`) in the same directory with `proc` → `func` substitution
4. Runs `nim check --errorMax:0` on ALL shadow files in a single invocation
5. Parses compiler errors: "can have side effects" → classified as `io`
6. Procs without errors → classified as `pure` (safe for `func` conversion)
7. Cleans up shadow files

## Usage

```bash
nim c -o:bin/proc_to_func_tester tools/proc_to_func_tester.nim
./bin/proc_to_func_tester > purity_report.json
```

## Output Format

```json
[
  {"file": "src/sieve/sieve_rules.nim", "line": 48, "proc": "hasLoopInAst", "result": "pure"},
  {"file": "src/gate/orchestrator_hook.nim", "line": 103, "proc": "runSingleGate", "result": "io", "reason": "can have side effects"}
]
```

## Key Design Decisions

- **Agent-free**: No heuristic classification. The compiler decides.
- **O(1) batch**: Single `nim check` invocation for all files (not per-proc).
- **Same-directory shadows**: Shadow files are created next to originals to preserve relative imports.
- **Error cascading is intentional**: If proc A calls I/O proc B, and both are converted to `func`,
  the compiler flags BOTH. This is correct — A transitively depends on I/O.

## Related Tools

- `src/gate/runners/effect_inference_gate.nim` — Pre-commit gate for axiomEffect completeness
- `src/gate/runners/discarded_write_audit_gate.nim` — Pre-commit gate for intentional-discard comments
