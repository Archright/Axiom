# WP4-i getBitsBE same-anchor replay — runs record

## Command (reproducible)
```
export AXIOM_STATE_DIR=/tmp/wpi_replay/state
bin/ax prove \
  --project <workspace>/nim-stew-clean-c75502c \
  --target 'stew/bitops2.nim::getBitsBE' \
  --limit 1
```
- Working dir: `.`
- Fresh state dir seeded with the repo's `data/verification_scope.lock`.
- Binary: `bin/ax` rebuilt post-WP4-i-fix (Phase C; build exit 0; audit 0 violations from touched files).
- Exit code: 0.

## Pre-fix vs post-fix Sieve-Gate delta (same anchor, same command shape)
| Aspect | Pre-fix (WP4-h-3 replay) | Post-fix (this run) |
|---|---|---|
| Refactor task rule | `structural_ast (topology)` | `structural_ast (io_boundary)` |
| Guard context | `Failed to parse source: Failed to parse Nim source` | `Missing preconditions: has_loop` |
| Parse failure payload | none (silent empty-source nil path) | n/a — source loaded and parsed |
| solverInvocationCount | 0 | 0 |
| obligationAttemptedCount | 0 | 0 |
| obligationGeneratedCount (IR pipeline) | 13 | 13 |
| UAP results | 0 (requests=1) | 0 (requests=1) |
| Node status / tier | pre_sieved / unknown | pre_sieved / unknown |
| verifiedRatio | 0.0000 (0/40) | 0.0000 (0/40) |

## Interpretation (honest)
- The WP4-i Phase C fix moved the boundary one stage deeper: external source
  ingress now loads and parses (the conflated "Failed to parse Nim source"
  hard-reject is gone; the sieve rule changed from the empty-source fallback
  `topology` to a content-derived `io_boundary`, proving real content flow).
- The pipeline now stops at the structural healing pattern-precondition check:
  the selected pattern requires `has_loop`; the anchor is loop-free →
  `erGuardHardReject` with `Missing preconditions: has_loop`. This is a
  strategy-selection mismatch (sieve chose a loop-oriented healing pattern for a
  loop-free bit-manipulation function), NOT a parse failure and NOT a type gap.
- The 13 generated intrinsic obligations (WP4-h-3 typed ProofIR) are still never
  ATTEMPTED because the node dies in the structural healing path before any
  obligation is sent to a solver. Z3/Lean/KAA/Trust remain unreached for this
  anchor via `prove`.

## Artifacts
- `prove_getBitsBE_postfix_run1.log` — full post-fix replay log.
- Pre-fix comparison log: `../../act2-wp4h3-proofir/runs/prove_getBitsBE_run1.log`.
- Trajectory + telemetry preserved in `/tmp/wpi_replay/state/logs/`
  (`ax_prove_trajectory.jsonl`, `z3_telemetry.jsonl`).
- Corpus (Phase A) and implementation notes (Phase C): `../canonical/`,
  `../probe/`.
