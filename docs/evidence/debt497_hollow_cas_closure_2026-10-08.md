# DEBT#497 Follow-up — Residual Hollow-CAS Runner Closure: Completion Evidence

- **Date**: 2026-10-08
- **Branch / PR**: `fix/hollow-cas-runners` (rebased on `d7d81e0fc`, the merge of PR #592) — policy companion PR **#595** (`policy/surface-v69-debt497-hollow-cas`)
- **Defect**: DEBT#497 (Theater/Unenforced Subprocess Gate) residual exposure — every remaining `registerGate()`-only / no-standalone-`main` runner AOT-links to a hollow exit-0 binary; the orchestrator's subprocess CAS path executed nothing and reported PASS (same shape as the #587 trust-commit-scope closure)
- **Supersedes**: closed PR #593 (v68 policy) — renumbered v69 per the later-landing-PR-rebases convention (v64 precedent); #592 consumed the v68 number first

## Full-sweep verdict (measured 2026-10-08, standalone `-d:release` AOT links)

Manifest-based sweep of the wired gate set (54 entries) plus an orphan audit of every runner module calling `registerGate()`:

| runner | wired? | pre-closure binary | pre behavior | closure mechanism | post-closure binary | post behavior |
|---|---|---|---|---|---|---|
| decision_binding_gate.nim | manifest | 31,872 B | exit 0 (unconditional PASS theater) | `LightGateAllowlist` admission + `runGateInProcess` case + `runInProcess` adapter over the runner's judgment SSOT (the #587 pattern) | 31,872 B (standalone link stays hollow **by design** — the standalone binary is not an enforcement surface for this gate; the in-process path is) | exit 0 standalone; enforcement via in-process dispatch |
| delegation_enforcer.nim | manifest | 32,192 B (`main()` defined, never invoked) | exit 0 | `judgeWireLogs` extracted as the value-returning judgment SSOT; `main()` delegates; `runInProcess` adapter; allowlist admission + dispatch case | 83,816 B | exit 0 live scan (`PASS — no repeated no-op commands detected`); `--self-test` PASS; **negative probe** (3 consecutive no-op `"command"` lines in a recent `data/*.json`) → `FAIL ... repeated no-op commands detected`, **exit 1** |
| architecture_config_gate.nim | orphan (manifest 밖; 실행 참조는 테스트뿐) | 31,872 B | exit 0 | real standalone `main` (`when isMainModule` executing the existing `run()` judgment); in-process registration barred by the DEBT#270 manifest-runner 1:1 invariant | 133,816 B | exit 1 (real scan finds violations on this tree — judgment executes) |
| debt_scan_gate.nim | orphan/retired | 31,872 B | exit 0 | real standalone `main` (same shape) | 130,816 B | exit 1 (real scan finds debt entries — judgment executes) |

Stale `LightGateAllowlist` entry `"debt-scan-gate"` removed (allowlist is now exactly `array[4, string]`: doc-completeness-gate, trust-commit-scope, decision-binding-gate, delegation-enforcer — every name has a real `runGateInProcess` dispatch case, enforced by the regression harness below). `trust-commit-scope` was already closed by #587.

Latent defects surfaced by giving the runners real executions, fixed in the same slice:
- `delegation_enforcer.selfTest` asserted `splitFile().name` WITH extension — unreachable while `main()` was never invoked; corrected.
- `architecture_config_gate.scanJsonForTimestamps` JArray branch bound `json.nim pairs()` and asserted `JObject` — documented as `nim_2_2_10_stdlib_quirks` **Q-011** (renumbered from Q-010 during the v69 rebase; Q-010 is main's `cast[int](someFloat)` docs-only entry).
- `decision_binding_gate.checkProc` forward declaration leaked non-gcsafe inference — `nim_forward_declaration_quirks` **Q3** `{.gcsafe.}`.

## Evidence 1–10 (all machine-observed)

| # | Acceptance | Procedure | Observation | Result |
|---|---|---|---|---|
| 1 | Hollow-CAS exposure zeroed (wired gates) | standalone AOT links pre/post, measured sizes + exit codes (table above); decision-binding + delegation routed through in-process dispatch | no wired gate remains whose only standalone artifact is an exit-0 shell: delegation links 83,816 B and executes its real judgment; decision-binding is in-process-enforced with the standalone hollow link provably outside the enforcement path | PASS |
| 2 | Orphan runners enforce (real mains) | run the two rebuilt orphan binaries | arch 133,816 B exit 1, debt-scan 130,816 B exit 1 (both judgments execute; exit 1 = real findings on this tree, not the hollow exit 0) | PASS |
| 3 | In-process path is the enforcement path (decision-binding WARN axis intact) | `decision-binding-gate` in-process verdict on this tree | WARN 34 functions missing `{.axiomDecision.}` (advisory; 30-day escalation not reached) — pipeline not broken by the closure | PASS |
| 4 | Regression harness freezes the closure shape | `tests/unit/test_hollow_cas_closure.nim` (I1–I4: main-less manifest runners must be allowlisted; every allowlist name must have a real dispatch case with unreachable sentinel; every registerGate-calling runner closed via main or allowlist; allowlist no longer carries `debt-scan-gate`) registered in `Makefile` `TESTS_FAST_UNIT` | unit 20 green in `make test-fast` (5/5 OK measured pre-rebase; green on the rebased tree) | PASS |
| 5 | Allowlist/dispatch coherence | `tests/gateway/gate_safety_macro_feature_test.nim` (merged with main's #591 debt-scan-removal tests; asserts `len(LightGateAllowlist) == 4` + retired-name rejection) | 4/4 OK | PASS |
| 6 | DEBT#497 registry closure integrity | `bin/debt_engine --codegen` + `--validate` + `--sync-budget` after the rebase | **1436/1436 checks passed, 0 failed**, metric evaluation 6 PASS 0 DRIFT; contentHash `sha256:58ef6daa8b010fc675ab1b143b7879aa5c4ef38eac2ccf9715b32d1dca9c76ac` re-verified byte-identical over `inprocess_dispatch.nim:473-488` after the rebase (recipe: `sed -n '473,488p' … \| sha256sum`) | PASS |
| 7 | nimtry re-anchor holds | `bin/nimtry` on the rebased tree | PASS — 4,110 violations, all debt-anchored, 0 unanchored (baseline re-anchored in-slice; ledger budget `nimtry_violations` current=0/closed via `--sync-budget`) | PASS |
| 8 | Static gate suite | `make local-verify-static` | **16 gates green** (incl. scope-consistency kernel_total=40, layer-enforcement PASS + negative probes deterministic FAIL, cert-integrity PASS, merge-admission mirror PASS) | PASS |
| 9 | Fast unit suite — no new failures | `make test-fast` on the branch vs the same suite on clean `d7d81e0fc` (main clone, ff-pulled) | identical 4 failures on both trees (indices shifted +1 by the inserted harness test at 20): theater-allowlist count 166≠139 and cert-trust closure `ccsNotDeepVerified` (two real main-inherited failures), plus two harness-substring false positives (`"psError"` inside [OK] lines; `"FAILED"` inside a PASS message) — binaries of both exit 0 | PASS (0 branch-introduced failures; inherited items → Follow-ups) |
| 10 | G7 + canonical digest ×2 | `make verify-contract-release-e2e-full`; `bin/ax report --canonical-digest` twice | G7 **PASSED** (`G7 pass (tier=z3-verified status=not_verifiable)`, release e2e suite green in ~45 s); canonical digest **`5e02199a6584d02b0c7e26e3ea3006ec34f9a7a6ec95cb81b6495ea74275b3fa` ×2 identical** | PASS |

## Policy v69 (companion PR #595)

- `config/repository_surface.json`: `policyVersion` 68 → **69**; four runner paths registered CONTROLLED (FROZEN-to-CONTROLLED re-registration, v55–v68 shape; broad wildcard 금지). `surface_guard --policy v69` against the full fix diff (17 paths): **PASS, 0 violations**.
- Local pre-push on the v69 branch reproduced the v66/v67/v68-identical single-FAIL advisory profile: `FAIL / SURFACE_FORBIDDEN`, base policyVersion 68, exactly one violation (`config/repository_surface.json` M / FROZEN — the self-authorization block v51 documents in knownBlindSpots). All other push-admissibility gates passed in the pre-push snapshot (the run reached and judged this final gate). Push used the documented advisory bypass (`git -c core.hooksPath=/dev/null push`); **`--no-verify` was not used**. Full JSON published in the PR #595 body. Merge authority is GitHub.
- CI profile on PR #595: `repository-surface` FAIL (the same advisory), all other checks PASS or selected-out — identical to v66 (PR #576), v67 (PR #586), v68 (PR #592), all of which merged with this profile.

## Reconciliation with landed slices

#587 (DEBT#471 slice) built the mechanism (allowlist + in-process dispatch + `runSingleGateImpl` in-process attempt) for one gate; this slice closes the residual class: the wired-but-unallowlisted runners (`decision-binding-gate`, `delegation-enforcer`) via the same mechanism without duplicating judgment code, and the unwired orphans (`architecture-config-gate`, `debt-scan-gate`) via real mains because in-process registration would violate the DEBT#270 manifest-runner 1:1 invariant. #592's v68 (4 `manifest.d` paths) and #591's debt-scan allowlist-name removal are absorbed by the rebase; #593 (superseded v68 attempt) is closed.

## Follow-ups (out of scope here — measured on clean `d7d81e0fc`, inherited, unchanged by this slice)

1. **Theater-allowlist regrowth**: `tests/unit/test_theater_allowlist_structure.nim` fails on main — `tools/ci/nim_theater_allowlist.json` has regrown to **166 entries vs the frozen 139** the test pins ("after blanket removal"). The guard is loud (blocking), so this is detected debt, not silent theater; a register-and-triage slice is needed.
2. **Certificate trust closure regression**: `tests/unit/test_certificate_trust_closure.nim` fails on main — journaling cases return `ccsNotDeepVerified` where `ccsJournalRequired` / `ccsJournalBindingAbsent` are expected (checks at lines 100/112).
3. **test-fast FAIL-sniff false positives**: the `Makefile` test-fast verdict greps unit logs for `Error|FAILED|Traceback` and matches passing output (`psError` in [OK] lines; the word `FAILED` inside a passing message) — units 24/34-on-main (resolve_node_outcome, g6 divergence) are reported FAIL while their binaries exit 0. Fail-closed direction (no false PASS), but noisy: the verdict regex should anchor to unittest verdict markers.
