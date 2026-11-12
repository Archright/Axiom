# OBSERVATION — §6c v2 skReport cross-path relocation (runs 1–4)

- EXPERIMENT_ID: rust-skreport-relocation-2026-11-01
- Written: 2026-11-01, branch `work/rust-report-repro-2026-11-01` (Axiom4, uncommitted working tree). Observed facts only — machine outputs recorded verbatim or by sha256; no post-hoc rewrite of earlier campaign evidence (`serde-json-claim-2026-10-31` untouched). Governing contract: `docs/spec/productization_contract.md` §6c v2 (same working tree).
- Comparison consumer used: `tests/skreport_compare_tool.nim` (compiled `build/skreport_compare_tool`; originally written as `tools/debug/skreport_compare_tool.nim`, relocated at pre-push gate enforcement — see §7). This is a DEBUG driver over the production implementation `src/core/utils/skreport_comparison.nim`; it is NOT a production CLI surface. Re-measured anchors are compare-time refutation material, NOT proof of production-time provenance; production-time binding rests solely on the lane's digest chain (payload.identityBundleDigest ↔ sidecar.binding.payloadSha256), both recomputed mechanically by compareSkReports.

## §1 Runs (all `bin/ax prove`, exit 0, ~14–15 s wall; bin/ax provenance OK at run time: `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-7266682232559372922)`)

Common per run: `CARGO_NET_OFFLINE=true`, `GITHUB_TOKEN=$(gh auth token)` (value never printed), Cargo.lock protocol (place `experiments/serde-json-claim-2026-10-31/inputs/Cargo.lock` sha `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` → run → out sha identical → remove → find-based manifest diff empty). Subject HEAD `8c535a260ce561eaab4111aafc29038eb9f77ff3` everywhere; state lock base `0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e` (byte copy of `state_d1/data/verification_scope.lock` unless noted).

| run | subject root | state/vault | variant | exit |
|---|---|---|---|---|
| A | `<workspace>/json` (original) | `/tmp/axiom-e2e/state_a` / `vault_a` | none (positive left) | 0 |
| B | `/tmp/axiom-e2e/json_b` (`cp -a` copy, manifests content-identical) | `state_b` / `vault_b` | relocated subject (positive right) | 0 |
| C | `/tmp/axiom-e2e/json_c` (copy; `src/error.rs` +1 comment line) | `state_c` / `vault_c` | source negative | 0 |
| D | `/tmp/axiom-e2e/json_b` | `state_d` / `vault_d` | scope negative: state lock rewritten `jq -S .` — semantically identical, bytes differ (`ea0d86dd00f5b9d4259490011a3bb75e74818a58fa996e40acf86c773bcd8eec`) | 0 |

Sidecars produced by the lane (production authority) at `<state>/.axiom/rust-lane/<sha256Hex(projectAbs)[0..15]>/skreport-identity.json`:

| run | lane dir hash | sidecar sha256 |
|---|---|---|
| A | `1398235db249fc8b` | `b89bbfbbd866cb7baca40ef8767312bcfcd19dd636753d20efdb631123c918f5` |
| B | `70577173745b7c6d` | `8738484dc8a6acdd89a7e8e8e647b60ed8ff22f5c4663c35dc97d5da9d09f659` |
| C | `6bf6bae6e09eb291` | `0ab6d6152f78b980e1e9545f101f88ff19312a1a03bf9f8443abc8ae77259b6e` |
| D | `70577173745b7c6d` | `ca6376c95240e5ad5344229283df9554313fff032829e012bfb1b81c9a5f5b54` |

Payloads (trajectory `skReport` `extra`, canonical `jq -S` extracted): payload_a `0d7c6da1068ffa42343b23a705f50d14730d6e32274a9dfbe0e0f1ccaf369541`, payload_b `a1bb521012b25070363a4b7ae44a117fab410a05b0495d3df7c09fe9e43185b5`, payload_c `d65b941bb90bca885f97020d45294ef4815dcae622c0a87a973ccd58bc8d67e4`, payload_d `fb0da18ef4906efbfe61aa4307a7e470da0f8c0bee56edf2833720e707d77def`.

## §2 Positive (A vs B, re-measured anchors via production primitives)

- A/B sidecar `identity` sections: byte-identical after `jq -S` (`diff` empty — includes the structured `rejection` record: rule `path_absolute`, index 1, crateName `serde_json`, contentSha256 `30c7e046bfa6c6cf17498e5dac35232b89cb62a2116ba976bfd749bdc763c143`, skeletonSha256 `404f3d7b99accf2b8d4fdce9b825620269bbfa4e57908351d8bb982e36926cb3`).
- Both payloads embed the SAME `identityBundleDigest` `9e0d3448946cf7710af466d317a1f360dc8b49e651ba2378e083decd0652ff90` — recomputed from each side's own sidecar by the comparison (pair-binding check passed both ways).
- Payload canonical diff: exactly one hunk — `targets[0].reason`, differing only in the recorded offending absolute path span (state dir + lane dir + charon-target build hash: A `c7a61223a9390745`, B `22c7cbbd5d22a5e8`). Both sidecars' `binding.rejection.rawPath` record their OWN full span; `binding.payloadSha256` differs accordingly (payloads differ) — the position-dependent half of the chain.
- Verdict record (`comparisons/compare_positive.json`, sha256 `8a87002d3936a9d85999b10efe7e726295f288c28f9e2d18cf1fd3ec6f9e1241`):

```json
{"verdict":"equal","axes":{"identity":"equal","structure":"equal","reason":"equal"}}
```

- Notes verbatim (truncated to essentials): `identity: left/right re-measurement — all 4 anchors match the recorded declarations` (subject.commit, subject.moduleSha256, subject.sourceFingerprint, scope.rustTargetsSha256 — measured NOW by the tool from each side's still-present world); `reason: leaf[1] differs only by the producer-recorded offending path (skeleton digests match, structured rejection identity equal) — promoted to equal by the §6c v2 rejection rule; both raw reasons preserved below`.

## §3 Negatives (same tool, same §6c rules)

| control | record | verdict | distinguishing note |
|---|---|---|---|
| source (C vs A) | `compare_neg_source.json` `b33671d3…3dabdd` | **not_equal** (identity) | `identity: bundle section 'subject' differs` — each side's own anchors still match their own declarations (internally consistent, different subject) |
| scope (D vs A) | `compare_neg_scope.json` `0e1c54c9…4fa425` | **not_equal** (identity) | `identity: bundle section 'scope' differs` — lock bytes bound, not semantics |
| sidecar absent (A vs B, right sidecar removed) | `compare_neg_nosidecar.json` `45f08fbe…ad25c` | **unknown** | `identity: sidecar absent (right) — an all-or-nothing production gap is fail-closed, never equal` |

Claim-axis and error-class-axis negatives are NOT produced by real runs here: the single declared spec + the single organic rejection class of this subject cannot yield a second claim or a different rejection content without fabricating inputs. Those axes are covered by gateway fixtures (`tests/gateway/skreport_comparison_feature_test.nim`, 28/28 [OK]: claim change → not_equal, scope-lock change → not_equal, toolchain change → not_equal, error-kind change → not_equal, tampered binding → unknown, measured-but-not-declared → unknown, promotion-refusal cases → unknown). This split is recorded as a coverage boundary, not equivalence.

## §4 Toolchain/build facts at run time

- `make build` → `✅ Build successful` (after converting the one new `src/core` proc to `func` — architecture_invariants ratchet `procCount <= 950` held at 950).
- `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-7266682232559372922)`, exit 0.
- `agent_preflight` → `[SUCCESS] Agent Pre-flight Guard: Workspace 무결성 검증 통과.`; `[decision-binding] WARN: 48 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached` (pre-existing WARN count, unchanged by this work).
- `tests/unit/test_rust_input_contract.nim` → 34 [OK] (covers the new structured `RustFileTableRejection` propagation incl. "table violation surfaces through the pipeline").
- `ax prove --json` is NOT a prove flag (`unknown option: --json`, exit 3) — the report document's durable observable is the trajectory `extra`; JSON stdout rendering via `usesAxShortcutJsonFlag` belongs to other shortcuts. Runs therefore used the d1 command shape verbatim.

## §5 ADDENDUM — independent-audit defects F1–F4 fixed (2026-11-01, run 5)

An independent read-only security audit (agent-1zt50m37, this session) reproduced four defects against the draft; each was fixed strictly red→green with gateway business negative tests / unit negatives. The §1–§4 records above are PRE-FIX observations, preserved verbatim; the records under `comparisons/post-audit-fix/` are the post-fix re-verdicts over the SAME preserved §1 artifacts (payloads/sidecars re-loaded from `artifacts/`, no re-run of the lane — measured anchors omitted, the production-time measurement stands).

| defect | hole (pre-fix) | fix | red evidence | green evidence |
|---|---|---|---|---|
| F1 | `structuralDiff` exempted `identityBundleDigest` at EVERY object depth — a nested difference was invisible (audit repro: equal) | exemption restricted to the document root (`path == "$"`); `reason` keys stay exempt at any depth (a nested string reason leaf is the reason axis's jurisdiction by contract) | `skreport_comparison_feature_test.nim` "F1 audit" [FAILED] pre-fix | [OK] 31/31, nested diff → not_equal |
| F2 | reason axis `break`ed after the first differing pair — later genuine differences unexamined | all differing pairs examined; every unpromoted difference → reason unknown with a per-leaf note | "F2 audit" [FAILED] pre-fix (promoted leaf[0] concealed an unpromoted leaf[1] → equal) | [OK] → unknown |
| F3 | `binding.rejection.reasonLeaf` never read — promotion accepted ANY string leaf pair despite contract §6c rule 3 pinning the pair to `targets[0].reason` | promotion additionally requires the pair's document position == `axiomSkReportRejectionReasonLeaf` (new constant, single definition used by lane writer + comparator) on BOTH sides AND both records naming exactly that leaf — position/record incoherence, absence, or side divergence fails the promotion closed | "F3 audit" [FAILED] pre-fix (bogus/absent/off-leaf records still equal) | [OK] → unknown; live positive pair (records `targets[0].reason`, leaf at `targets[0].reason`) still promotes: `comparisons/post-audit-fix/compare_positive.json` `99a8880d53927d0db4433af59bfba62c21085d739f45570791e74b565d249aac` verdict equal with note "leaf[1] at targets[0].reason … pair bound to the recorded rejection leaf" |
| F4 | `resolveLaneModule` preferred repoRoot over projectAbs — a lock module path existing as DISTINCT files in both trees bound the identity to the repo's file | ambiguous binding (both joins exist, distinct normalized paths) → `""` (identity bundle gaps, fail closed); unambiguous single-owner and same-file cases unchanged | `tests/unit/test_lane_module_resolution.nim` (new, registered in Makefile TESTS_FAST_UNIT) ambiguous case [FAILED] pre-fix | [OK] 5/5 |

Hardened in passing (behavior-neutral today, audit G7): `claimBindsTarget` now checks each side against ITS OWN identity section (deep-equality precedence unchanged).

Post-fix re-verdicts over the preserved §1 artifacts (`comparisons/post-audit-fix/`): positive A vs B → **equal** (identity/structure/reason; `5705d2d4…`/`b09928e9…`/`4fd23483…` for the negatives) — source → not_equal, scope → not_equal, sidecar absent → unknown. The verdicts are UNCHANGED from pre-fix: the real campaign pairs satisfy the stricter rules organically.

Post-fix gates: `make build` → ✅ (procCount ratchet held at 950 after converting the new leaf-path walker to a pure `func`); `bin/ax --check-provenance` → OK (new BuildSourceHash); `agent_preflight` → SUCCESS (WARN 48 unchanged); `test_rust_input_contract` → 34/34.

Boundary statement (audit-informed, unchanged duty of honesty): the §6c verdict rests on the LANE's production-time digest chain and records — a self-consistent, mechanically re-checkable binding, NOT a cryptographic authentication of production (audit G2/G3: finish-time measurement TOCTOU and the unconsumed-LLBC binding remain open design gaps; G2 requires a local write between measurement and consumption to exploit, below this campaign's threat floor, recorded as hypothesis-grade). The debug tool's re-measured anchors are compare-time refutation material only. equal remains a CONDITIONAL verdict.

Known remaining audit items NOT fixed here (recorded, safe-direction or out of scope): G1 (scope hash binds whole lock bytes — deliberate byte binding, observed as not_equal on semantically-identical locks), G4 (symlink identity follows links), G5 (concurrent sidecar last-writer-wins — fails closed), G6 (measured-anchor walk is two-level; deeper anchors are compared at their canonical path and non-object sections are skipped), and the production-consumer absence (the comparison surface is still the tests-tree driver only).

## §6 ADDENDUM — re-audit closure (2026-11-01, run 6)

The independent re-audit (agent-kzm8hsqm) re-executed the F1–F4 probes against the fixed code: all four blocked (19/19 expectations), B-series forgery attempts fail closed (B1 fragment tamper → not_equal, B2 pair swap → unknown, B3i/ii unilateral forgery → unknown; B4a fully self-consistent bilateral forgery → equal — the contract's DECLARED conditional-verdict limit, not a defect). Test counts reproduced: gateway 31/31→32/32, unit 5/5, input-contract 34/34.

Closure items executed on the FINAL code (re-audit had left them unexecuted):

| item | result |
|---|---|
| `make build` | ✅ Build successful |
| `bin/ax --check-provenance` | `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-5777535592290072339)`, exit 0 |
| `agent_preflight` | `[SUCCESS] Agent Pre-flight Guard: Workspace 무결성 검증 통과.` (decision-binding WARN 48, escalation threshold unreached — unchanged) |
| positive A/B re-verdict AFTER gates | **equal** (identity/structure/reason) over `artifacts/payload_{a,b}.json` + `skreport-identity.{a,b}.json` |

Newly documented latent surface (re-audit §3, execution-confirmed): a difference living ONLY under a nested volatile-NAMED key (`summary.path` repro) is outside every axis → equal. Contract-compliant by §6c rule 2 (the §6/R3 canonicalizer mandate); now written into the contract (§6c rule 2 "범위·한계" — latent for honest lane payloads, reachable via consumer-supplied/forged inputs, removal requires a §6 canonicalizer amendment FIRST), pinned by a gateway fixture ("documented §6/R3 boundary … 32nd case"), and recorded in the comparison module header. Rule 3 wording also updated to pin the F2 (all differing pairs examined) and F3 (position/record coherence) mechanics.

Honest residuals (unchanged): production consumer absent (debug-tool-only surface); `verify-contract-release-e2e-full` never run; G1/G4/G5/G6 unfixed; claim/error-class negatives are fixture coverage, not real-path runs; lane sidecar-production path is compile-verified only in these sessions (post-audit-fix re-verdicts reuse preserved artifacts, no lane re-run).

## §7 ADDENDUM — driver relocation at pre-push gate enforcement (2026-11-01, run 7)

The first commit attempt placed the comparison driver at `tools/debug/skreport_compare_tool.nim`. The pre-push `layer_enforcement_gate` (rebuilt fresh by its pre-push freshness stamp — the pre-commit run had reused a stale binary, which is why the commit itself passed) rejected the placement fail-closed:

- `tools/debug/skreport_compare_tool.nim:33/34` imports `verification/extraction_provenance` + `verification/rust_replay_adapter` — denied by rule tools/ (forbidden prefix `verification/`), the anchor re-measurement primitives.

Fix chosen: **relocation, not rule weakening**. The driver is non-production verification-harness code (compare-time anchor re-measurement consumes the lane's verification primitives directly — sanctioned under `tests/`, forbidden under `tools/`; the layer gate deliberately scans `src`+`tools` only). Precedents for verification-importing drivers/tests: `tests/verify_trajectory.nim` (driver at tests/ root), `tests/unit/test_rust_replay_adapter.nim`, `tests/verification/*`. The layer rule and its scan scope are untouched — `bin/layer_enforcement_gate --strict` → **PASS, 0 violations in 1615 files** after the move. Rejected alternatives: layer_rules.nim whitelist widening (TCB change + TWS closure re-anchor), hand-adding pairs to `src/gate/architecture_policy.lock` (nimtry-owned auto-generated ground truth), lane-API substitution (measureSkReportIdentity is all-or-nothing — different semantics from the tool's per-anchor-optional re-measure), dropping measured anchors (weakens the §6c refutation evidence).

Relocation re-verification (same preserved §1 artifacts, same §6c rules, binary recompiled from `tests/skreport_compare_tool.nim`):

| pair | verdict (pre-relocation, §5/§6) | verdict (relocated binary) |
|---|---|---|
| A vs B positive | equal (identity/structure/reason) | **equal** (identity/structure/reason) — identical note set |
| C vs A source | not_equal (identity) | **not_equal** (identity) |
| D vs A scope | not_equal (identity) | **not_equal** (identity) |
| A vs B sidecar-absent | unknown | **unknown** |

The §1–§6 records were produced with the pre-relocation binary (same comparator implementation `src/core/utils/skreport_comparison.nim` — the driver is a thin loader; only its path/header changed). No verdict changed.

Additional relocation at the same pre-push enforcement: `identityBindingDigest` moved from `src/core/utils/skreport_comparison.nim` to `src/core/utils/canonical_projection.nim` (both the lane and the checker closure already import canonical_projection; the lane no longer imports skreport_comparison). Checker closure membership is unchanged (missing-from-pin=0, pin-only=0); only the 6 pre-existing members' values drifted, rotated via the standard `reanchor_pin --ref 6a34a0aeb --write` + chore(pin) commit path. Re-verdicts after both relocations: identical (§7 table above).

## §8 ACCEPTANCE — cold re-execution at pinned mergeCommit.oid (2026-11-01, run 8)

PR #1162 MERGED as mergeCommit.oid `9461231936383e87b84fe69b6a79b5df6c7b3b30` (GitHub native merge commit, mergedAt 2026-11-01T10:12:32Z). `git rev-list --parents -n 1` observed locally: `9461231936383e87b84fe69b6a79b5df6c7b3b30 18e5602b7e6c9a22ee9800826b6cf31a7e4125b9 6f03b54d82c3e1cfffba3c2b5a6fb75d6bc6efdf` — parent1 is the prior main tip (an intervening PR had landed before ours; the merge queue merged on top of it), parent2 is our pinned head `6f03b54d82c3e1cfffba3c2b5a6fb75d6bc6efdf` exactly as `--match-head-commit` demanded.

- Engine identity (recorded separately from the evidence merge): branch `repro/skreport-4` pinned at the merge oid; `make build` ✅; `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (1581309748423241377)` (differs from the pre-merge build hash because the merge commit includes the intervening PR's code — expected for a canonical-main build). Comparator driver recompiled from `tests/skreport_compare_tool.nim` at the same oid.
- Runs (fresh `AXIOM_STATE_DIR`/`AXIOM_PROVE_VAULT_DIR` under `/tmp/axiom-accept4`, `CARGO_NET_OFFLINE=true`, `GITHUB_TOKEN` via `gh auth token` never printed, Cargo.lock `1bc62b1a…061b2e4` place→run→remove with in/out sha identical ×4): A(original subject) rc=0 14.2 s · B(`/tmp` copy) rc=0 13.6 s · C(copy + 1 comment in `src/error.rs`) rc=0 13.8 s · D(B path, `jq -S .` re-serialized lock) rc=0 13.8 s. State locks: A/B/C byte-copies of the preserved `0c1f4abc…` lock; D `ea0d86dd…` — both digests identical to the §1 pre-merge values (deterministic serialization).
- Subject invariance: per-subject pre/post manifests diff empty (A; B+D; C each) — the lane left no residue beyond the documented place/remove lock protocol.
- Cold artifact digests differ from §1 pre-merge values in exactly the position-dependent halves (state-dir path and charon-target build hash inside `targets[0].reason`, sidecar `binding.rawPath`/`payloadSha256`) — the designed volatile surface. The position-independent binding half is reproduced exactly: payload A and B both embed `identityBundleDigest` `9e0d3448946cf7710af466d317a1f360dc8b49e651ba2378e083decd0652ff90` — byte-identical to the §2 pre-merge value, recomputed from each side's own cold sidecar.
- Verdicts (records in `acceptance/`, digests in `acceptance/run_facts.txt`) — all four identical to §5/§6/§7, same axis breakdown:
  - positive A vs B (anchors re-measured NOW from each side's still-present world, all 4 matching per side): **equal** — `{"identity":"equal","structure":"equal","reason":"equal"}`, reason axis promoted by the §6c v2 rejection rule (leaf[1] differs only by the producer-recorded offending path; skeleton digests match; structured rejection identity equal; raw reasons preserved in the record).
  - source C vs A: **not_equal** (identity) — structure/reason equal, difference confined to the identity axis.
  - scope D vs A: **not_equal** (identity).
  - sidecar-absent (right): **unknown** (fail-closed, never equal).
- Terminal Outcome for the ④ slice: the cross-path reproducibility comparison is operational end-to-end on canonical main — proposal → machine adjudication (equal + three fail-closed negatives) → evidence preservation → GitHub merge → pinned-SHA cold reproduction with identical verdicts. Coverage boundaries stated in §3/§6 (claim/error-class axes via gateway fixtures only; equal is a conditional verdict, not a tamper-proof signature) remain unchanged and are not widened by this acceptance.
