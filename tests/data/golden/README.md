# Golden Samples — Legacy Script I/O Collection

**Phase**: S0-5 — Legacy Script I/O Sample Collection

## Purpose

These golden samples document the expected I/O contract for every legacy Python and
shell script in the Axiom-core repository. They serve as:

1. **Regression anchors** — if a script's output shape changes, the sample can be
   updated and the delta reviewed.
2. **Migration targets** — when scripts are ported to Nim (per the Language Ban policy
   in AGENTS.md §1), these samples define the behavioral contract the Nim replacement
   must satisfy.
3. **Agent reference** — agents can read the samples to understand what each script
   does without parsing shell/Python source.

## Schema

Each `.sample.json` file follows this structure:

```json
{
  "script": "<relative path to script>",
  "description": "<what the script does>",
  "inputSample": { ... },
  "outputSample": { ... },
  "exitCode": 0
}
```

- `inputSample`: Representative CLI args, env vars, or stdin for the script.
- `outputSample`: Expected stdout/stderr shape and content on success.
- `exitCode`: Expected exit code (0 = success, nonzero = expected failure).

## Inventory

### Shell Scripts (15)

| # | Script | Description |
|---|--------|-------------|
| 1 | `tools/analyze_goal_shapes.sh` | GoalShape evolution analysis from JSONL logs |
| 2 | `tools/verify_symbol.sh` | Compiler-in-the-loop atomic mutation check |
| 3 | `tools/hooks/kimi_pre_tool_use.nim` | PreToolUse hook blocking direct interpreter invocation |
| 4 | `tools/ci/auto_convert_proc_to_func.sh` | Shell wrapper for proc→func Python pipeline |
| 5 | `tools/ci/prune_stubs.sh` | Automated deprecated stub pruning |
| 6 | `tools/ci/track_raises_coverage.sh` | `{.raises: [].}` annotation coverage tracker |
| 7 | `tools/ci/detect_proc_to_func_per_routine.sh` | Incremental proc→func eligibility detection |
| 8 | `tools/ci/hotspot_ranker.sh` | Debt decay hotspot deficit guard |
| 9 | `tools/ci/prune_dead_modules.sh` | Dead module pruner with triple validation |
| 10 | `tools/ci/ratchet_check.sh` | Touched-file legacy violation checker |
| 11 | `tools/ci/nimtry_snapshot.sh` | Nimtry violation snapshot capture |
| 12 | `tools/ci/verify_stubs.sh` | Forwarding stub integrity verification |
| 13 | `tools/ci/ratchet_shrink.sh` | Weekly ratchet ceiling reduction |
| 14 | `tools/ci/split_large_file.sh` | Split .nim into _core and _io modules |
| 15 | `tools/ci/bottom_up_func_promoter.sh` | Leaf-first proc→func conversion |

### Python Scripts (12)

| # | Script | Description |
|---|--------|-------------|
| 16 | `tools/restructure_agents.py` | AGENTS.md section restructure utility |
| 17 | `tools/cst_nim_parser.py` | tree-sitter-nim CST parser core |
| 18 | `tools/generate_agents_docs.py` | Generate docs/agents/*.md from policy lock |
| 19 | `tools/ci/annotation_hygiene_gate.py` | Effect annotation hygiene gate |
| 20 | `tools/ci/validate_effect_hints.py` | Effect hints validation against compiler |
| 21 | `tools/ci/bypass_expiry_gate.py` | Temporary bypass expiry checker |
| 22 | `tools/ci/forbidden_pattern_gate.py` | Forbidden pattern detection in core |
| 23 | `tools/ci/validate_gate_exceptions.py` | Gate exceptions JSON schema validator |
| 24 | `tools/ci/sync_domain_layout.py` | Sync domain DAG to policy lock |
| 25 | `tools/ci/nimtry_dashboard.py` | Nimtry violation trend dashboard |
| 26 | `tools/ci/auto_convert_proc_to_func.py` | Compiler-driven proc→func pipeline |
| 27 | `tools/ci/pbt_seed_parser.py` | PBT seed/test/status output parser |

## Notes

- All paths are relative to the project root.
- Samples represent the **happy path** (exit code 0). Error-path samples may be
  added in future phases.
- `tools/.venv_cst/` is a Python virtual environment and is excluded from this
  inventory (not a project script).
