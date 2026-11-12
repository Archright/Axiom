# DEBT#493 Closure — passFilenames subprocess fallback delivered files nobody read

- **Date**: 2026-10-07
- **Branch**: `fix/debt493-passfilenames`
- **Debt**: DEBT#493 (Theater/Vacuous Check, high/high) — `src/gate/orchestrator/hook/executor.nim` `runSingleGateImpl`
- **Disposition**: FIXED (delivery unified on positional argv; stdin misdelivery removed)

## 1. Reproduction (pre-fix)

Worktree fixture `tmp/debt493_repro/violator.nim` — exactly one forbidden import (`import core/bmc/bmc_runner`; `core/bmc/` is in `InternalPaths`, `gate_consts.nim:19`).

| # | Command shape (the exact argv/stdin `runSingleGateImpl` produced) | Result |
|---|---|---|
| A | `echo 'tmp/debt493_repro/violator.nim' \| ./bin/import_encapsulation_gate "$PWD" test 1 --stdin-files` | **exit 0**, `[GUARD] All imports properly encapsulated. ✅` — vacuous PASS |
| B | `./bin/import_encapsulation_gate "$PWD" test 1 tmp/debt493_repro/violator.nim` (real filename on argv) | **exit 1**, `tmp/debt493_repro/violator.nim:1: import core/bmc/bmc_runner` reported |

Mechanism: `import_encapsulation_gate` takes every argv token from position 4 on as a filename and never reads stdin; `readFile("--stdin-files")` raises and is swallowed by `except CatchableError: discard` (`checkFile`, import_encapsulation_gate.nim:82-83) → zero violations → PASS. The real violating filenames went to a stdin nobody drained.

## 2. Protocol census — all 14 `passFilenames = true` gates (topology_spec.nim)

Only `quality_gate_runner` implements the `--stdin-files` + stdin protocol (`quality_gate_runner.nim:115-119`). The other 13 consume trailing positional argv tokens after their template (or safely ignore them):

| gate | binary's argv contract | verdict under unified argv delivery |
|---|---|---|
| binary-artifact-gate | params 1.. = files | consumes correctly |
| conflict-marker-gate | args[0]=repoRoot, args[3..]=files | consumes correctly |
| core-invariant-gate | params 1.. = files | consumes correctly |
| debt-integrity-gate | repoRoot=getCurrentDir(); only `--update-baseline` flag | trailing tokens ignored (safe) |
| documentation-first-gate | params 1.. = files | consumes correctly |
| effect-inference-gate | params 4.. = files | consumes correctly |
| hotspot-gate | args[0]=repoRoot, args[3]=baseline(.json), files 4.. | consumes correctly |
| hotspot-coverage-gate | args[0]=repoRoot (template already `[$repoRoot,$mode,$maxJobs]`) | trailing tokens ignored (safe) |
| import-encapsulation-gate | params 4.. = files | consumes correctly |
| language-ban-gate | params 1.. = files — source comment: "passFilenames mode: orchestrator provides staged file paths as args" | consumes correctly (documents the intended design) |
| mcp-tool-usage-gate | repoRoot=findRepoRoot(); argv only for `--self-test` | trailing tokens ignored (safe) |
| nim-check | params 4.. = files (or `@response-file`) | consumes correctly |
| quality-gate-runner | `--stdin-files` protocol OR bare argv tokens (catch-all) | consumes correctly |
| sorry-audit-gate | `paramStr(1)` = repoRoot; trailing tokens ignored | **template was empty → fixed** (below) |

## 3. Fix (option (a): unify on the delivery form gates actually consume)

1. `src/gate/orchestrator/hook/executor.nim` (CONTROLLED, v60) — removed the literal ` --stdin-files` argv token and the stdin file-list write; `passFilenames` gates now receive `quoteShell`-quoted positional file tokens appended after `argsTemplate` substitution (same quoting discipline as the template args, per Nim osproc/`quoteShell` semantics — shell-mediated invocation requires per-token quoting).
   - Fail-closed: a change-set exceeding exec ARG_MAX (measured `getconf ARG_MAX` = 2097152) now fails exec loudly (E2BIG → nonzero exit → gate FAIL) instead of passing vacuously.
2. `src/gate/topology_spec.nim` (CONTROLLED, v52) — `sorry-audit-gate` gained `argsTemplate = @["$repoRoot"]`: its binary reads repoRoot from `paramStr(1)`; under the old shape the first argv token was `--stdin-files`, so it "scanned" a nonexistent root and reported `findings: []`.
3. `src/gate/manifest.d/sorry-audit-gate.json` — regenerated projection (`nim c -o:bin/sync_topology tools/sync_topology.nim && bin/sync_topology`; 0 other projections changed). FROZEN-absorbed path re-authorised CONTROLLED by the v62 policy PR (precedent v55–v61: policy PR → consuming body PR).

Not touched: gate runner binaries (§-1 `import_encapsulation_gate.nim` untouched; `quality_gate_runner.nim` stdin branch remains valid manual CLI surface).

## 4. Post-fix measurement

E2E through the real fallback (`AXIOM_INPROCESS_DISPATCH=off`, rebuilt `bin/gate_hook`, harness calling `dispatchGate` → `runSingleGateImpl`):

| # | Scenario | Result |
|---|---|---|
| 1 | import-encapsulation-gate, violating file delivered on argv | **ok=false**, violation `tmp/debt493_repro/violator.nim:1: import core/bmc/bmc_runner` reported |
| 2 | import-encapsulation-gate, clean file | **ok=true** (no false positive) |
| 3 | sorry-audit-gate (argsTemplate fix), real repoRoot + trailing token | **scans the real root** — reports 1 pre-existing finding (see §6) |

Binary-level protocol battery (post-fix shapes):

- conflict_marker_gate `"$PWD" test 1 <conflict fixture>` → **exit 1**, markers reported; clean file → exit 0
- nim_check_gate `"$PWD" incremental 1 <syntax-error fixture>` → **exit 1**, FAIL
- sorry_audit_gate `"$PWD"` → exit 0 with real-root JSON scan; `sorry_audit_gate --stdin-files` (old shape) → exit 0 with `findings: []` (vacuous — the masked state)

Registry hash re-binding integrity: the pre-fix `contentHash` was re-derived from `git show HEAD:src/gate/orchestrator/hook/executor.nim` with the exact `extractProcText` algorithm (`src/core/audit/content_hash.nim`) → `sha256:d22cc167…56ea7`, byte-identical to the registry value before rebinding; post-fix hash `sha256:efd85478…a84ac` bound at `executor.nim:106-224`.

## 5. Registry ritual (all in-worktree)

- `bin/debt_engine --codegen` → `src/generated/debt_constants.nim` + `docs/DEBT_REGISTRY.md` regenerated
- `bin/debt_engine --regen-arch` → executor.nim canonical hash updated (1 entry in `data/architecture_debt.json`)
- `bin/debt_engine --sync-budget` → 3 BUDGET records reconciled: `debt_registry_open` 47→46, `debt_registry_closed` 176→177, `effect_violations` 90→89
- `bin/debt_engine --validate` → **1411 checks, 1411 passed, 0 failed; metrics 6 PASS / 0 DRIFT**

## 6. Newly unmasked observation (registered, not fixed here)

`sorry_audit_gate` `scanContent` skips only `--` line comments, so the word "sorry" inside `/- -/` block comments matches: `proofs/IR/Denotation.lean:22` ("NO native_decide, NO sorry, NO trustCompiler.") is a doc-comment false positive that the broken delivery masked (the gate never scanned a real root under subprocess dispatch). No CI/hook stage currently runs the `gsCI` gate battery, so this is latent for manual `gate_hook ci` runs. Follow-up candidates: scanner block-comment handling, or comment rewording; plus `src/gate/process_selector.nim` (`spawnManaged`/`writeStdin` stdin-injection facility, header still describing the removed design) has no importers.

## 7. Verification summary

- Reproduction: pre-fix vacuous PASS observed (A), control FAIL observed (B) — matches the registry description exactly
- Post-fix: real delivery observed end-to-end through `dispatchGate` (§4)
- No-regression: `make test-fast` fails 5 units (indices 19/21/22/24/34 → `test_theater_allowlist_structure`, `test_vkd_determinism`, `test_certificate_trust_closure`, `resolve_node_outcome_test`, `test_g6_runtime_reference_divergence`) — **identical on main HEAD 2c30c55b1** (re-run on a detached HEAD worktree: all exit 1; plus `gate_dsl_v2_test` exit 1 on HEAD, source byte-identical). Zero new failures attributable to this change.
- Changed-surface tests green with the fix: `tests/unit/gate_hook_scheduler_test.nim`, `tests/unit/manifest_parser_test.nim`, `tests/unit/topology_types_test.nim`, `tests/gateway/manifest_parser_test.nim` (all exit 0)
- Debt validation: `--validate` 1411/1411 green after ritual; `check-debt` green inside `test-fast`

## 8. Rebase addendum — re-ritual on the post-v63 base (2026-10-07, succession session)

The commit was rebased from base `2c30c55b1` (pre-v62) onto main `70b8f2515` (successively: #556 v63 — the `src/gate/manifest.d/sorry-audit-gate.json` re-authorisation this fix consumes — then #555 v64 ratchet-authority, both merged by the time of this push). The full projection ritual was re-run per base hop and re-measured; §5's numbers are the pre-rebase record and are superseded by the following:

- **Reproduction re-confirmed** on freshly built binaries: (A) old-shape `... import_encapsulation_gate "$PWD" test 1 --stdin-files` + filename on stdin → **exit 0 vacuous PASS**; (B) real filename on argv → **exit 1 with violation reported**.
- **Post-fix E2E re-measured** (rebuilt `bin/gate_hook` 19:17, `AXIOM_INPROCESS_DISPATCH=off`): [1] violating file on argv → `ok=false` + violation line reported; [2] clean file → `ok=true`; [3] `sorry-audit-gate` `argsTemplate=@["$repoRoot"]`, whole-root scan, 1 pre-existing doc-comment false positive (`proofs/IR/Denotation.lean:22`, §6).
- **nimtry re-anchor (v18 precedent)**: the fix shrinks `runSingleGateImpl` 102 → 98 effective SLOC, which invalidated the baseline's exact-count anchor → `bin/nimtry src/` exit 1 with 1 "new" violation. `bin/nimtry --update-baseline src/` re-anchored: diff confined to 19 lines, all `executor.nim` entries (the 102→98 SLOC detail + its rehashed id + +2 line-number shifts below the edit point), `total_violations` 4091 unchanged, no new violations. A second re-anchor on the #555 hop converged the baseline with that PR's own rewrite (`coverage_ratchet_gate.nim` runCoverageRatchet 57→107 SLOC detail + `env_types.nim` line shifts — pre-existing anchored debt of the ratchet track, 18 diff lines). Post-re-anchor `bin/nimtry src/` → exit 0.
- **Registry ritual on the new base**: `--codegen` / `--regen-arch` (0 entries updated) / `--sync-budget` (3 BUDGET records reconciled: `debt_registry_open` 48→47, `debt_registry_closed` 176→177, `nimtry_violations` 2→0 after the re-anchor) / `--validate` → **1418 checks, 1418 passed, 0 failed; metrics 6 PASS / 0 DRIFT, exit 0** (main grew the check count 1411→1418 and added DEBT#494 in the interim).
- **Manifest projection drift re-check**: `sync_topology` rebuilt + re-run → all projections `unchanged`.
- **No-regression on the new base**: `make test-fast` fails exactly the same 5 units (19/21/22/24/34) — no new failures; changed-surface tests (`gate_hook_scheduler_test`, `manifest_parser_test` ×2, `topology_types_test`) all exit 0.
- Local tool observation (pre-existing, not this change's): `bin/build_all_gates --release` currently fails its per-gate post-build run step for all 80 gates ("arguments can only be given if the '--run' option is selected" — nim CLI argv usage inside the pool worker); the identical 80 binaries build green via `make gate-runners`, so this is a builder invocation quirk, registered here for follow-up.
