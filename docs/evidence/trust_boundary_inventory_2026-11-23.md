# Trust Boundary Inventory (2026-11-23)

## 1. Header

This document is the canonical inventory of Axiom's trust boundary at main `3054bc00f6170d194ecea42ab21e39f92d7c4268`, measured 2026-11-23. It covers all 36 issues that were open on `Archright/Axiom` at that measurement: for each one it records what the body claims, which of the four tags apply, and which of the five verdicts the body's own evidence supports. Two rules govern how it must be read. First, an issue may carry MULTIPLE tags and MULTIPLE verdicts: a defect can be confirmed while its fix is stale, and a policy block can sit on top of an unmeasured defect, so no row is reduced to a single label. Second, a row describes one issue; it is not a merge decision and it is not proof that anything was fixed. Thirteen rows (#367, #220, #246, #223, #247, #349, #346, #347, #348, #383, #384, #385, #386) carry verdicts measured earlier in this investigation and copied unchanged; every other row is read from the issue body only, and says so when the code was not inspected.

## 2. Verdict vocabulary

| verdict | meaning |
|---|---|
| `VERIFIED` | Observed fact confirmed by evidence at a named commit. |
| `POLICY_APPROVED` | The authority holder approved the change. |
| `POLICY_BLOCKED` | No approval exists, or the change conflicts with standing policy. |
| `UNKNOWN` | Evidence or authority could not be observed. |
| `STALE` | Was valid, but the subject SHA or policy SHA has since moved, so the earlier green cannot be reused. |

These five may never be collapsed into a single green check: a passing check states that one of them holds at one commit, never that the other four do. No issue in this inventory is `POLICY_APPROVED`; not one of the 36 bodies records an approval.

## 3. Tag taxonomy

| tag | definition |
|---|---|
| `VERDICT` | Can cause a false or misleading PASS in a verdict (certificate, admission, readiness). |
| `EVIDENCE` | A trust claim is not bound to its subject, or cannot be independently re-verified. |
| `AUTHORITY` | Changes who may decide, or what may be trusted. |
| `GOVERNANCE` | Process, language, or documentation policy that does not change verdict or evidence semantics. |

## 4. Inventory of all 36 open issues (oldest first)

Rows are ordered by issue number, which is also creation order for this set. `created` is the UTC creation date. Descriptions are capped at 18 words; `not inspected` means the relevant code was not read in this pass, so the verdict stays `UNKNOWN` even where the body asserts a defect.

| # | created | tags | verdict | what the body says the defect/decision is | decision authority | follow-up relation |
|---|---|---|---|---|---|---|
| 188 | 2026-11-18 | EVIDENCE, VERDICT | UNKNOWN | Admission bundle omits certificate body, theorem and axiom set; certGreen re-verifiable only inside producer state; not inspected | none (engineering task) | related to #119, #145 |
| 219 | 2026-11-20 | EVIDENCE | UNKNOWN | Only 394 of 2,134 LLBC decls addressable by --target; skipped decls invisible in run summary; not inspected | none (engineering task) | related to #226, #228 |
| 220 | 2026-11-20 | VERDICT | VERIFIED | ax prove exits 0 with zero certificates; CI cannot distinguish 0% verified from success | none (engineering task) | — |
| 222 | 2026-11-20 | GOVERNANCE | UNKNOWN | Installed axiom v0.3.7 has no Rust lane; --project silently falls through to the Nim scanner; not inspected | none (engineering task) | — |
| 223 | 2026-11-20 | EVIDENCE, VERDICT | VERIFIED | signatureHash validated only as 64-hex; never compared with the signature extracted from LLBC | none (engineering task) | — |
| 224 | 2026-11-20 | EVIDENCE, AUTHORITY | UNKNOWN | Three Rust trust-boundary rows are exists:false; certificates claim lean-verified over IR, not Rust source; not inspected | none (engineering task) | related to #188, #119 |
| 226 | 2026-11-20 | EVIDENCE | UNKNOWN | No whole-crate mode; --target accepts exactly one match, so multi-candidate runs lose claim identity; not inspected | none (engineering task) | related to #219, #220, #229 |
| 228 | 2026-11-20 | EVIDENCE | UNKNOWN | Full serde_json sweep certifies 1 of 2,134 decls; 384 rejected by the canonicalizer subset; not inspected | none (engineering task) | related to #219, #220, #226, #229 |
| 229 | 2026-11-20 | GOVERNANCE | UNKNOWN | 394-candidate sweep hits 3500s timeout with no trajectory; LLBC reparsed and subject rehashed per candidate; not inspected | none (engineering task) | related to #219, #226, #228 |
| 239 | 2026-11-20 | EVIDENCE | UNKNOWN | Aeneas whole-crate serde_json translation crashes in SymbolicToPureTypes; function-level is_escape translates and proves; external tool, not re-measured | none (engineering task) | — |
| 246 | 2026-11-20 | EVIDENCE, VERDICT | VERIFIED | Theorem and Lean source can be swapped after attestation removal; kernel replay still PASSes with replayMatched=true | none (engineering task) | fix PASS at unmerged 66f82b2 is STALE; collision decision in #386 |
| 247 | 2026-11-20 | EVIDENCE | VERIFIED | Rust-lane certificate needs producer journal; ax cert export fails CERT_INVENTORY_MISMATCH for missing manifest | none (engineering task) | excluded from #238; sibling of #246 |
| 253 | 2026-11-20 | EVIDENCE, AUTHORITY | UNKNOWN | --sign cannot distinguish re-executed observation from consistently forged one; digest is integrity, not provenance; not inspected | none (engineering task) | residual gap of #188 |
| 346 | 2026-11-22 | VERDICT, GOVERNANCE | UNKNOWN | Panic termination under --panics:on exits 1, the contract VERIFICATION_FAILED state; probe quoted, code not inspected | human-architect (@Archright/architect) | — |
| 347 | 2026-11-22 | GOVERNANCE | UNKNOWN | Per-call timeoutMs never reaches Z3; fixed :timeout 60000 and :rlimit 30000000 bound every query; not inspected | human-architect (@Archright/architect) | — |
| 348 | 2026-11-22 | EVIDENCE, GOVERNANCE | UNKNOWN | Two canonical digests exist; decide whether eligibleTargets is identity while unitEvidenceRefs stays evidence; not inspected | human-architect (@Archright/architect) | — |
| 349 | 2026-11-22 | GOVERNANCE | VERIFIED | Z3 telemetry records result:error for unsat queries because whole-stream classification rejects the (get-model) error line | human-architect (@Archright/architect) | — |
| 350 | 2026-11-22 | GOVERNANCE | UNKNOWN | Fail-closed perf checker runs in make test; no GitHub workflow invokes it; the budget is prose; not inspected | human-architect (@Archright/architect) | — |
| 351 | 2026-11-22 | GOVERNANCE | UNKNOWN | 263 ms Lean pre-flight probe writes no receipt; decide whether it provides unique assurance; not inspected | human-architect (@Archright/architect) | — |
| 352 | 2026-11-22 | EVIDENCE | UNKNOWN | Exported declarations indexed under "*" (nkPostfix); bare exported names miss in index and reference walk; not inspected | human-architect (@Archright/architect) | — |
| 354 | 2026-11-22 | GOVERNANCE | UNKNOWN | Two debt ratchets: nimtry 4381, decision-binding 1 file of headroom; re-anchor or keep; not inspected | human-architect (@Archright/architect) | — |
| 355 | 2026-11-22 | GOVERNANCE | UNKNOWN | Land four measured slices from perf/z3-lane-attribution with rotation separation; not landed at main; not inspected | human-architect (@Archright/architect) | supersedes PR #331; boundary cites #3, #4, #7 (merged PRs) |
| 356 | 2026-11-22 | GOVERNANCE, AUTHORITY | POLICY_BLOCKED | Frozen script-scan fails docs-only PR #318 on 626 pre-existing Hangul lines; exemption vs wontfix; awaiting owner decision | human-architect (@Archright/architect) | blocks PR #318; #238, #293, #301, #326 declared unrelated |
| 357 | 2026-11-22 | GOVERNANCE, AUTHORITY | POLICY_BLOCKED | Translate FROZEN AGENTS.md and align its Korean policy markers; human-architect approval not recorded | human-architect (@Archright/architect) | — |
| 358 | 2026-11-22 | GOVERNANCE, AUTHORITY | POLICY_BLOCKED | Delete data/i18n/ko.json and its toolchain cache-closure entry; approval not recorded | human-architect (@Archright/architect) | — |
| 359 | 2026-11-22 | GOVERNANCE, VERDICT | POLICY_BLOCKED | Extend publication-integrity with tree mode, NLID dimension, escape decoding; approval not recorded | human-architect (@Archright/architect) | — |
| 360 | 2026-11-22 | AUTHORITY | POLICY_BLOCKED | Remove ruleset write and bypass capability from agent credentials; admin action not recorded | repository-admin | — |
| 361 | 2026-11-22 | GOVERNANCE | POLICY_BLOCKED | English-only policy for issues, PR text, reviews and commits; .github templates need approval | human-architect (@Archright/architect) | — |
| 362 | 2026-11-22 | GOVERNANCE | POLICY_BLOCKED | Translate remaining FROZEN prose in .github, config/policy, src/gate; per-batch approval not recorded | human-architect (@Archright/architect) | — |
| 367 | 2026-11-22 | VERDICT, EVIDENCE | VERIFIED | Axiom probe exit status discarded; a failed #print axioms leaves empty observedAxiomSet and still PASSes | human-architect (@Archright/architect) | out of scope: #347, #349, #351; pre-flight probe tracked in #351 |
| 368 | 2026-11-22 | EVIDENCE | UNKNOWN | Merkle cache persists hasAxiomImpl=false because enrichment runs after cache write; warm runs never enrich; not inspected | human-architect (@Archright/architect) | out of scope: #353 (closed NOT_WORTH_IT) |
| 373 | 2026-11-22 | GOVERNANCE | POLICY_BLOCKED | CONTRIBUTING.md needs a source-origin declaration on a trustSurface path; agent cannot merge it | human-architect (@Archright/architect) | coupled to PR #372; root entry reserved by PR #365 |
| 383 | 2026-11-23 | AUTHORITY, EVIDENCE | POLICY_BLOCKED | Decide the next admission epoch so admission-check.yml, epoch_manifest and trustedAdmissionWorkflowSha move together | human-architect (@Archright/architect) | reopens PR #333 after option 1 or 2 |
| 384 | 2026-11-23 | VERDICT, AUTHORITY | POLICY_BLOCKED | Decide whether certificate-mint.yml may advance; DEBT#554 fail-open path stays open while frozen | human-architect (@Archright/architect) | reopens PR #293 |
| 385 | 2026-11-23 | AUTHORITY | POLICY_BLOCKED | Decide whether trustedWriterJobs may join TrustedWriterSet; the out-of-tree App rejects the new field | human-architect (@Archright/architect) | reopens PR #301 |
| 386 | 2026-11-23 | AUTHORITY, EVIDENCE, VERDICT | POLICY_BLOCKED | Choose between #238 subject-relative identity and main DECISION-0830; five collisions, 303 commits behind | human-architect (@Archright/architect) | decides PR #238 (close or re-derive); decides #218 reading |

Authority mapping note: where a body names an owner role outside the four-value set (`product-contract owner`, `architecture owner`, `policy owner (debt budget)`, `architect`), the row records `human-architect (@Archright/architect)`, the sole architect recorded in #383-#386. `app-owner` is recorded for no row because the App's owner is out-of-tree and unestablished (section 6).

## 5. Three protection lists do not agree

Measured at `3054bc00f6170d194ecea42ab21e39f92d7c4268` on 2026-11-23:

| list | size | enforced on the GitHub merge path? |
|---|---|---|
| `config/policy/merge_admission.json` `trustSurface` | 39 | no - the only evaluator is `src/cli/merge_cli.nim` `loadTrustSurface` (a local `ax merge` predicate) |
| `config/policy/trust_surface_manifest.json` `paths` | 18 | yes - the `axiom-admission-verifier` App compares `blob(G) == blob(B_mg)` |
| `.github/CODEOWNERS` | 109 lines, covers 38 of 39 | no - ruleset 27097366 has `require_code_owner_review: false` |

- 27 of the 39 `trustSurface` entries have no manifest coverage (`.github/actions/setup-axiom-toolchain/**` is covered by the manifest's concrete `action.yml`).
- 7 manifest entries are absent from the 39: `config/policy/trust_surface_manifest.json`, `config/policy/epoch_manifest.json`, `config/repository_surface.json`, `.github/workflows/admission-gate-v2.yml`, `.github/actions/setup-axiom-toolchain/action.yml`, `tools/surface_guard.nim`, `tests/ci/test_vs0_admission_aggregate_fail_closed.nim`.
- No drift gate compares the three lists; `manifest_touched` appears in zero source files.
- Two union members have no CODEOWNERS owner: `tools/ci/publication_script_eval.nim` and `tests/ci/test_vs0_admission_aggregate_fail_closed.nim`.
- `.github/CODEOWNERS` is itself FROZEN under `.github/**` with no exact CONTROLLED entry, so `bin/surface_guard` judges its modification `SURFACE_FORBIDDEN` (measured, policyVersion 108).

## 6. Authority preflight

| layer | owner | measured basis |
|---|---|---|
| Trust Policy | human-architect (@Archright/architect) | `config/policy/merge_admission.json` `trustSurface` holds 39 entries at 3054bc00; the sole architect is recorded in #383-#386, whose bodies name no other human decision holder |
| Repository Administration | repository-admin | `gh api repos/Archright/Axiom` returned `permissions.admin: true` for the authenticated owner on 2026-11-23; #383-#386 record the same admin bit as mechanical authority only |
| Admission App | UNKNOWN - not measured | `axiom-admission-verifier` appId 5795152 is named at `config/policy/merge_admission.json:60-70` and `.github/workflows/admission-check.yml:37`; its source, owner and accepted schema are not in this tree |
| GitHub enforcement | repository-admin | ruleset `27097366` read live 2026-11-23: active, branch target, 7 required contexts, `bypass_actors: []`, `require_code_owner_review: false`; ruleset `27525972` (`main-admission`) also has an empty bypass list |

Ownership here means who may decide, not who has decided: no layer recorded an approval in any of the 36 bodies.

## 7. What this document does NOT claim

It does not assert that closing an issue equals resolving it, and it does not record any issue as fixed: a `VERIFIED` row says a defect was observed, not that a remedy landed. `POLICY_BLOCKED` means the change cannot land in its current form, not that the policy decision was made - for #383-#386 the App verdicts are pinned to their head SHAs, and writing this document moved no epoch, no manifest pin and no accepted schema. Where a row says `UNKNOWN`, neither the code nor the authority was observed in this pass, so the row is neither green nor red.
