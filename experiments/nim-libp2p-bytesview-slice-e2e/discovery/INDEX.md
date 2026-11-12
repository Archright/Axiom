# Discovery index — nim-libp2p BytesView `toOpenArray` slice (investigation chain)

> **Status**: raw session agent outputs preserved **verbatim** (byte-identical copies, sha256-pinned below).
> **Source**: kimi-code session `wd_axiom_c1df10cfaf23/session_aa9f2e48-8114-442c-9899-328c54e02be3/agents/main/tasks/<agent>/output.log`.
> **Created**: 2026-10-22 · **Experiment ID**: `nim-libp2p-bytesview-slice-e2e`
> **Note**: these records are the *investigation chain*, not the acceptance run. The canonical d1/d2 runs land **after** PR-A; their evidence is recorded in [`../ACCEPTANCE.md`](../ACCEPTANCE.md), [`../FREEZE.md`](../FREEZE.md), [`../INTEGRITY.md`](../INTEGRITY.md) and `docs/evidence/nim_libp2p_bytesview_slice_2026-10-22.md`.

## Records

| # | agent | question | key finding |
|---|---|---|---|
| 01 | `agent-i3wikkui` | read-only survey of nim-libp2p — toolchain, purity, contradiction candidates | C2: `bytesview.toOpenArray` yields `e-2b+1`, inclusive law wants `e-b+1`; Nim pinned 2.2.10 |
| 02 | `agent-n217p23j` | how `ax prove` reaches an external subject | external path = `--project` + `AXIOM_STATE_DIR` + a `soExplicit` overlay; VKD unaffected |
| 03 | `agent-gnppig6z` | prior art + product contract for external-repo verification | 5 existing overlays, **no** nim-libp2p overlay; `productization_contract` §10 is the only authority |
| 04 | `agent-qls909lj` | re-verify the C2 facts (body, call sites, intent, git history) | inclusive intent holds; the only `b>0` test is a same-commit snapshot, not an oracle |
| 05 | `agent-neih9viz` | replay forms + engine wiring checklist | subject is a `template` ⇒ stamped-harness path only; 14 touchpoints; scope-lock seeding |
| 06 | `agent-g9ct01sk` | landing path, permissions, ruleset | merge queue + `--auto` arming; two-PR discipline; zero required human reviews |
| 07 | `agent-dmil9xkr` | contracts of `derive_checker_closure` / `axiom-gate commit` / `debt_engine` | commit-first → derive → pin; `git add -u` sweeps **every** dirty tracked file; resolved runbook sequence |
| 08 | `agent-kn4koshi` | PR #938 / #911 / #912 / #947 archaeology | contract→feature→rotation order; TWS diff = one blob sha; #947 = the docs-only precedent |
| 09 | `agent-dy61wesc` | does any non-defect leg execute the subject | no — the subject runs only on a confirmed disproof; control = solver-level injection guard |
| 10 | `agent-x5whbl7w` | `bin/ax` build identity + staleness | 4-step build; `SourceCoherence` (`BuildSourceHash`) is load-bearing; `engineBuild` ≠ "unmeasured" |
| 11 | `agent-vyq7cmx2` | Stage A — overlay + contract creation | 2 files; blob sha256 typo fixed (`…dd8…`→`…dd0…`); the `b=1` algebra clause corrected |
| 12 | `agent-3qsjhlfa` | Stage B — engine wiring + unit test | `axiom_engine.nim` +736; 4 suites / 37 [OK]; `canonicalSpecIR` 4→6 clauses |
| 13 | `agent-2x15fwme` | why the run exited 0 despite `clDisproved` | template ⇒ fatal pre-sieve swallowed `vsDisproved`; payload persists in `unitEvidenceRefs` |
| 14 | `agent-2onqm98u` | implement the P4 disproof carve-out | `cached.blocked and not disproofCarveOut`; 2 new orchestrator cases green |
| 15 | `agent-nqjowmqi` | staging sweep, pin kinds, d2 pin strength | `git add -u` sweeps dirty tracked files; `perf_latest.json` trap; d2 pin is format-only |

## Verbatim copies — sha256 pins

| # | file | sha256 | bytes |
|---|---|---|---|
| 01 | `01_nim_libp2p_full_survey.md` | `aa57aec08b88f9ecf2e5831b5538422ffa355341606385fd8e3def88e3dc1275` | 26148 |
| 02 | `02_ax_prove_mechanics.md` | `560da27b3a407e1a5b02c26d08f1efe06326121383031d772dfdb57780547bec` | 17532 |
| 03 | `03_prior_art_product_contract.md` | `a2a3f7af5c88aa3d44afe0f369a744c3603869b2b55d48d5273dc5901855f43b` | 13794 |
| 04 | `04_c2_fact_reverification.md` | `605f1c7a518290e28c77bd0574980997ad5839af9e1dfed0bf42d6c43e5d22bc` | 10590 |
| 05 | `05_replay_forms_wiring_checklist.md` | `e379e4b5f1b92dfe68d8145036b0cd386f6f3b48447ee0c0ceafbb35fe5f9de9` | 21454 |
| 06 | `06_landing_path_permissions.md` | `a5ad6d82ed5ed23f845366c2db71233d325fad04944114f0f6e2e7bba1fef8e6` | 17468 |
| 07 | `07_tool_contracts_runbook.md` | `25e57cfc54561e223e53b00c4fc37c6414ca8becfe9bc2d9d80ed09ac04db7e9` | 14714 |
| 08 | `08_pr938_archaeology.md` | `b9ef5848ed414e584a13ef737f9dcb1262a5537d69177b82386e187959161e2b` | 11496 |
| 09 | `09_control_leg_replay_semantics.md` | `5f5c09342519f627c5d2d61a67c2f6fb6e1c198fad1829b3a4f476132fa228e4` | 9591 |
| 10 | `10_binax_build_identity.md` | `07be4274bf93564c2515aa64681bbe41e562c765a016a6a268e907ba2940e0c5` | 11921 |
| 11 | `11_stageA_overlay_contract.md` | `669077f6ff55ba866c49e998b4051f93cce03301f331d353e140f0e941d7a885` | 4561 |
| 12 | `12_stageB_wiring_unittest.md` | `2a044b06ebd20d314b4dc62cc191314241a75ee2a42fa901045b342eeea93513` | 6023 |
| 13 | `13_exit0_root_cause_trace.md` | `cca80a8455a823975fb82ed12f647f28d281bfc6ec062c669529b36f9f693d24` | 9015 |
| 14 | `14_loop_driver_carveout_fix.md` | `a70db6715ae24abd4c275b1ac2e4aa1c81fa64117e44a41e4fa5e6fd47cb8e8d` | 7288 |
| 15 | `15_p0_staging_hash_reverify.md` | `3d5049b15b93c93c0f0b29e9ab3e0c5667f98124965b5f814ecd0a2a133f8950` | 6617 |

## Record-name ↔ content correction (renamed, contents untouched)

All 15 files above are byte-identical copies of the source session logs; the sha256 column
is the authority. Three destination names did not describe the payload that the mapped source
log actually contains, and were **renamed in the 2026-10-22 finalize pass** so that each
filename states what the record contains:

| before | after | payload |
|---|---|---|
| `07_binax_build_identity.md` | `07_tool_contracts_runbook.md` | three-tool contract report (`derive_checker_closure`, `axiom-gate commit`, `debt_engine`) + the resolved runbook sequence — source `agent-dmil9xkr` |
| `10_p0_staging_hash_reverify.md` | `10_binax_build_identity.md` | the `bin/ax` build-identity report (build recipes, `SourceCoherence`, `engineBuild` admissibility) — source `agent-x5whbl7w` |
| `15_p0_staging_hash_reverify_addendum.md` | `15_p0_staging_hash_reverify.md` | the staging / hash / pin-kind report (`git add -u` sweep, `perf_latest.json` trap, the two pin kinds, the d2 format-only pin) — source `agent-nqjowmqi` |

The rename is a filename change only: no record content was edited, re-ordered, re-titled or
summarised, and every sha256 above is unchanged from the pre-rename value. The staging /
hash / pin-kind report was produced by a further session agent (`agent-nqjowmqi`) that the
original copy list did not name; it is preserved here as record **15** rather than dropped, so
the chain stays complete.
