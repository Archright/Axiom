Stage B is complete. All verification passed.

## End state (verbatim)

**Branch**: `followup/libp2p-bytesview-slice` @ `98b8b7069` — verified before starting, **unchanged** (no commit, no push).

```
$ git status --porcelain
 M config/spec/nim_libp2p_bytesview_slice.json
 M docs/spec/nim_libp2p_bytesview_slice_contract.md
 M src/cli/axiom_engine.nim
?? tests/unit/test_libp2p_bytesview_binding.nim
```
Nothing else. `config/trusted_writer_set.json` and `data/architecture_debt.json` untouched; nim-libp2p untouched (`git -C <subject> status --porcelain` empty, module sha256 still `b205c969…e5ee`).

**Compile check** — `nim c --hints:off -d:allowMissingZ3 --nimcache:/tmp/ax_stageb_nc_main -o:/tmp/ax_stageb_check src/cli/main.nim` → `MAIN_BUILD_EXIT=0`, no `Error:` lines. (Engine module standalone also compiles, exit 0.) Decision-binding violation count unchanged at **45** — my new procs add **zero** new violations.

**Unit test** — `nim c -r tests/unit/test_libp2p_bytesview_binding.nim` → **37 [OK] / 0 [FAILED]**, tail:

```
[Suite] bytesview slice replay — the ORIGINAL template's length decides
  [OK] compositeReplayShape is empty for the stamped binding (template owns the harness)
  [OK] dry-run: the observed length is evaluated against the adopted law concretely
  [OK] end-to-end: replay against the ORIGINAL template — e = 3 agrees
  [OK] end-to-end: the observation decides — a law-satisfying subject disagrees
bytesview slice binding tests done (state dir: /tmp/ax_libp2p_bv_test_state)
```
Suites: 17 loader/fail-closed · 6 pin · 9 synthesis · 4 replay (the end-to-end replay compiles the stamped harness against the **byte-exact pinned subject** and observes the template's real length 2 where the law demands 3 → `rvAgree`; a counterfactual twin subject → `rvDisagree`).

## Change inventory

`src/cli/axiom_engine.nim` (+736):
- 1801–1832 lane header comment (fail-closed contracts: presence-optional / malformed-fail-closed / Zero-Footprint)
- 1834 `NimLibp2pBytesviewSliceOverlayPath*` · 1838 `BvSliceLenDefectCarrierName*` · 1844 `BvSliceLenControlCarrierName*` · 1851 `BvSliceLenDefectLawName*` · 1856 `BvSliceLenControlLawName*` · 1861 `BvSliceLenReplayHarnessTemplate*`
- 1874 `stripBvOuterParens` · 1894 `parseBvArithBody` (closed grammar: `<var>` | `<var> ± <INT>`) · 1921 `parseBvNamedDefClause`
- 1943 `type NimLibp2pBytesviewSliceDomain*` · 1973 `validateBvSubjectPin` · 2002 `validateBvOwnership` · 2024 `validateBvCarriers`
- 2075 fwd-decl · 2081 `loadNimLibp2pBytesviewSliceOverlayDomain*` · 2096 `validateNimLibp2pBytesviewSliceOverlayNode*` (6-clause validation; law bodies are **data**)
- 2197 `overlayDeclaresLibp2pBytesviewSubject*` · 2209 `libp2pBytesviewCarrierTargetRouting*` · 2236 `verifyLibp2pBytesviewSubjectPin*` (**real** sha256-of-bytes check, sidecar-style)
- 3130–3308 `synthesizeNimLibp2pBytesviewSliceCandidate*` (dedupe → resolver bytes → `makeCarrier` → β-splice exactly-once + free-var guard → completeness bits → `saveEvidenceArtifact` + dual-write → `measureClaimCarrierParseBoundComponents` → `replayHarnessTemplate` → census records → wave-facing defect / own-name control → logInfo)
- 4566 `PreparedRun.libp2pSliceOverlay*` · 4827–4858 loader block in `prepareProofRun` (absent→inert log, present-but-invalid→`err`, pin check) · 4966 isEligible branch · 5010 canonical-target routing · 5032 bare-carrier-target routing

`config/spec/nim_libp2p_bytesview_slice.json`: `canonicalSpecIR` 4→6 clauses (`bvSliceLenLaw1(e) == e`, `bvSliceLenActual(e) == (e - 1)`, `bvSliceLenLaw0(e) == (e + 1)`, `bvSliceLenControl(e) == (e + 1)`) + description/caveat note that the law is data.

`docs/spec/nim_libp2p_bytesview_slice_contract.md`: §1 claim restated as the 6-clause data form + closed-grammar rule; §3 carrier/law descriptions; **new §3.1 "Engine wiring — the `ax prove` lane"** (element→binding→contract table); §4 replay-post clarification.

`tests/unit/test_libp2p_bytesview_binding.nim` (new, 648 lines): 4 suites, ad-hoc style of `test_toml_d2_agent_binding.nim` (not in `TESTS_FAST_UNIT`, like the d2/sidecar tests).

## Judgment calls to review

1. **Target routing goes one step beyond a strict d2 mirror.** d2 routes only canonical `module::fn` targets, and the pipeline's refusal machinery fires only for canonical targets — so a bare `--target bvSliceLenActual` would have been a silent no-op. I therefore added the bare carrier-name route (unambiguous: the carrier exists in one module) with a fail-closed synthesis error. Both forms now reach the synthesizer; the canonical form is the d2 path verbatim.
2. **The test embeds a byte-exact copy** of the pinned `bytesview.nim` (24 lines, Apache-2.0/MIT) as a fixture so the pin test and the replay observe the *subject's own* template. The subject tree is never written; the digest is re-measured at runtime so a drifted copy fails loudly.
3. **No solver/pipeline suite in the test** (z3 4.13.3 is present locally, so the parent may add it) — the contract's control-UNSAT check belongs to the smoke run.

## Notes for the smoke run

- Subject root `<workspace>/nim-libp2p`; the pin check will verify the module bytes there (verified matching).
- The shared d2 dep-root resolver scans the subject tree and *will* fire on nim-libp2p (it imports `stew`/`results`); all four packages are in the local nimble store (stew-0.5.0, results-0.5.1, serialization-0.5.4, faststreams-0.5.2), so it resolves; the harness itself only imports `bytesview.nim` (no imports). A missing package would fail the replay closed with `subject dep resolution failed` — that is the shared d2 mechanism, not this lane.
- The defect obligation `(e - 1) == e` is violated for every `e ∈ 1..5` (BV64), so the model is any in-domain witness; the domain preconditions are asserted as semantic facts for synthesized claims, so the witness stays in `1..5` and the replay's `bv.toOpenArray(1, e)` stays in range.