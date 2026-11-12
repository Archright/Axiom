# Vacuity & Tautology Investigation Report

**Date:** 2026-05-13  
**Commit:** `66c869b2` (fix: block vacuous and metadata-only proofs from ASI inflation)  
**Previous Commit:** `a35f64a0` (chore: backfill ASI ledger snapshots)  
**Scope:** ASI 0 → 1 journey integrity audit  
**Status:** CLOSED — all 9 infiltration paths patched, ASI reset to honest 0.0000

---

## Executive Summary

The Axiom engine reached ASI `1.0000` on 2026-05-13 at 04:46:18Z with `verified=2598/2598`. This value was **not a clean ASI 1**. A subsequent full-system audit revealed that the 1.0000 figure was inflated by **vacuous truths, tautologies, metadata-only SMT assertions, and unconditional status promotions** that bypassed substantive evidence requirements.

This report catalogues **nine infiltration paths** (Path A–I) through which non-proofs entered the verification pipeline and were counted as `verified`. Each path is documented with:
- The mechanism of infiltration
- Quantitative evidence from `logs/audit/stream.jsonl`
- The code location where the bypass occurred
- The fix applied in commit `66c869b2`

After remediation, the honest state is:
- `engineAsiFixed4 = 0.0000`
- `verified = 0`
- `pseudoVerified = 2,030` (previously counted as `verified`)
- `unverifiable = 1`
- `missingCertificates = 1`

---

## 1. Quantitative Evidence from Audit Stream

### 1.1 Status Transition Distribution (`stream.jsonl`, 289,305 lines)

| `newStatus` | Count | Notes |
|---|---|---|
| `unattempted` | 29,068 | Normal |
| `verified` | 6,185 | **Retroactively audited — majority non-substantive** |
| `pseudo_verified` | 2,030 | Isolated on 2026-05-13 by `applyProofStateAntiVacuityGate` |
| `unverifiable` | 998 | Normal |
| `timed_out` | 4 | Normal |
| `vacuous_contradiction` | 2 | Normal |

### 1.2 `verified` Transition Sources

| `oldStatus` → `verified` | Count | Risk Level |
|---|---|---|
| `unattempted` → `verified` | 6,113 | **HIGH** — mass promotion without evidence gate |
| `unverifiable` → `verified` | 43 | **CRITICAL** — impossible transition indicates status corruption |
| `pending` → `verified` | 15 | MEDIUM |
| `stale` → `verified` | 8 | MEDIUM |
| `timed_out` → `verified` | 4 | HIGH |
| `pseudo_verified` → `verified` | 2 | CRITICAL — re-promotion after isolation |

### 1.3 Temporal Clustering

- **2026-05-05**: 4,813 `verified` transitions in a single day. This was a mass-promotion event.
- **2026-05-13**: 2,030 `pseudo_verified` transitions — all from the anti-vacuity gate isolation.

### 1.4 ASI Ledger Discrepancy

- `asi_ledger.jsonl` reports `total = 2598` nodes.
- Actual source functions in the repository: **1,955**.
- Overcount: **643 nodes** — these were non-function entries (metadata hints, `@axiom-hint` annotations, synthetic nodes) that were incorrectly included in the ASI denominator and numerator.

---

## 2. The Nine Infiltration Paths

### Path A: Boundary Extractor — `depth >= 0` Fallback

**What happened:**  
When `extractBoundaries` could not derive semantic constraints from a function's parameters (e.g., `char`-only params), it injected a fallback constraint:
```smt
(assert (>= depth 0))
```
This is a **tautology** (`depth` is a metadata metric, always ≥ 0). The function then received a `SemanticHint` with this constraint, passed SMT (always `sat`), and was promoted to `verified`.

**Why it inflated ASI:**  
Every function without derivable boundaries got a free `verified` ticket. With 1,955+ functions, this created a floor of hundreds of false `verified` counts.

**Evidence in code:**
- `src/core/boundary_extractor.nim` (old):
  ```nim
  if smtParts.len == 0 or leanParts.len == 0:
    smtParts.add("(>= depth 0)")   # <-- tautological fallback
    leanParts.add("depth >= 0")
  ```

**Fix:**
- Removed the fallback. Functions without derivable boundaries now return early (no hint), remaining `unattempted`.

---

### Path B: `@axiom-hint` Annotation — Auto-Generated Metadata Assertions

**What happened:**  
The codebase contains `@axiom-hint` doc comments that auto-generate SMT and Lean assertions for functions. Many of these hints contain:
```
# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
```
These were harvested by the certificate manager and proof pipeline as "proof obligations." Because they are tautologies, any SMT solver immediately returns `unsat` on negation, triggering `verified`.

**Why it inflated ASI:**  
`@axiom-hint` annotations exist on ~30+ functions. Each one produced a trivially-provable obligation that counted toward `verified`.

**Evidence in code:**
- `src/verification/gate_rules.nim`: `normalizedResources`, `normalizedMutations`, `moduleStem`, `isWriteFunction` all carry `depth >= 0` hints.
- `src/verification/gate_rules.nim`: `classifyModuleByPath` carries `ast_parse_failed_isolated` hint — a dummy symbol with no semantic content.

**Fix:**
- The new `hasMetadataOnlySmtAssertion` gate in `gateway.nim` and `wf_state.nim` explicitly detects and rejects assertions that contain only metadata symbols (`depth`, `impact`, `nodeId`, `ast_parse_failed_isolated`, etc.).

---

### Path C: Empty SMT Formula — Default to `(assert true)`

**What happened:**  
When `expectedSmtlib2` was an empty string, `buildInjectedSmtlib2` implicitly produced `(assert true)` or allowed an empty payload to pass through. `proveAxiomNode` then returned `verified: true` because "there was nothing to disprove."

**Why it inflated ASI:**  
Any function with no SMT formula (common for simple getters/setters) was auto-verified.

**Evidence in code:**
- `src/core/gateway.nim` (old): `buildInjectedSmtlib2` did not return `""` for empty input; instead it continued building a payload.
- `src/core/gateway.nim` (old): `proveAxiomNode` did not check for vacuous input before calling the solver.

**Fix:**
- `buildInjectedSmtlib2` now returns `""` for empty/whitespace-only input.
- `proveAxiomNode` now returns `axiomErrVacuousContradiction` if `hasNonSubstantiveSmtAssertion` detects `(assert true)` or empty formula.

---

### Path D: Old SMT Shape — P and `not P` in Same Solver Context

**What happened:**  
The old `buildInjectedSmtlib2` placed dependency axioms, own formula, and the negated proposition **in the same SMT scope**:
```smt
(assert P)
(assert Q)
...
(assert (not (and P Q ...)))
(check-sat)
```
If the dependency axioms `P, Q, ...` were mutually contradictory (or included a vacuous assertion), Z3 returned `unsat`. The engine interpreted `unsat` as "the negation is unsatisfiable, therefore the original proposition is proven." This is the **classical vacuity trap**: in an inconsistent theory, every proposition is provable.

**Why it inflated ASI:**  
Any set of dependency axioms containing even one tautology or contradiction would make the entire proof vacuous. Because dependency axioms were inherited from upstream `verified` nodes, errors propagated downstream.

**Evidence in code:**
- `src/core/gateway.nim` (old):
  ```nim
  result.add(baseFormula)            # all assertions in one scope
  result.add("(check-sat)")          # single check
  # ... later ...
  result.add("(assert (not " & conj & "))\n")
  ```
- `src/cli/wf_state.nim` (new, detection): `hasLegacySameContextProofShape` looks for `(check-sat)` + `(assert (not ` without `(pop 1)`.

**Fix:**
- **2-Pass Gateway Architecture**:
  1. `(push 1)` → assert assumptions only → `(check-sat)` → `(pop 1)`
  2. Assert negated proposition **outside** the assumption scope → `(check-sat)`
- If pass 1 returns `unsat`, the assumptions themselves are contradictory, and `axiomErrVacuousContradiction` is returned.

---

### Path E: Proof-State → Certificate Sync — Unconditional `certVerifiedAxiom` Promotion

**What happened:**  
`syncCertificatesWithProofState` in `report_cli.nim` iterated over proof-state entries. If an entry had `status == "verified"`, it was unconditionally promoted to `certVerifiedAxiom` in the certificate vault — **without checking whether Lean compiler replay or negative mutation tests had actually passed.**

**Why it inflated ASI:**  
Proof-state is a transient JSON file (`ax_proof_state.json`). A `verified` string in this file became the highest certificate grade, bypassing all hard gates. This created a **status laundering** channel: anything that could write `"verified"` to `ax_proof_state.json` became `certVerifiedAxiom`.

**Evidence in code:**
- `src/cli/report_cli.nim` (old):
  ```nim
  if label in verifiedLabels:
    node[statusKey] = newJString("certVerifiedAxiom")
    node[reasonKey] = newJString("verified-axiom:proof-state-sync")
  ```

**Fix:**
- Introduced `hasSubstantiveProofStateEvidence(entry)` which requires ALL of:
  - `leanCompilerVerified == true`
  - `negativeTestResult == true`
  - `evidencePath` non-empty
  - `negativeEvidencePath` non-empty
- If substantive: promotes to `certGreen` (not `certVerifiedAxiom`)
- If not substantive: demotes to `certPseudoVerified` with `trusted: false`

---

### Path F: `injectContradiction` — Test Flag Abused as Proof Bypass

**What happened:**  
`AxiomProofRequest.injectContradiction` was a test/debug flag. When set to `true`, `proveAxiomNode` **immediately returned `verified: true`** without calling the solver:
```nim
if request.injectContradiction:
  return ok(AxiomProofResult(verified: true, ...))
```
While intended for unit tests, this path could be triggered by any caller and would produce a valid-looking `verified` result.

**Why it inflated ASI:**  
Any code path that set `injectContradiction = true` (intentionally or via bug) created a false `verified` entry.

**Evidence in code:**
- `src/core/gateway.nim` (old):
  ```nim
  if request.injectContradiction:
    return ok(AxiomProofResult(verified: true, ...))
  ```

**Fix:**
- `proveAxiomNode` now returns `axiomErrVacuousContradiction` when `injectContradiction` is true. The test suite was updated to expect this error.

---

### Path G: `promoteToCertVerifiedAxiom` — Direct Promotion Without Axiom Registry Linkage

**What happened:**  
The `promoteToCertVerifiedAxiom` procedure in `certificate_manager.nim` allowed any certificate with a `leanArtifactHash` to be promoted directly to `certVerifiedAxiom` — the highest trust grade. There was no requirement for the certificate to be linked to a registered, versioned, hash-verified axiom in the `verified_axioms` registry.

**Why it inflated ASI:**  
`certVerifiedAxiom` was treated as a super-grade above `certGreen`. Once a certificate reached this grade, it could not be demoted by normal gates (it was considered "axiom-trusted"). Mass promotion to `certVerifiedAxiom` therefore permanently locked in false positives.

**Evidence in code:**
- `src/verification/certificate_manager.nim` (old):
  ```nim
  node["status"] = newJString("certVerifiedAxiom")
  node["reason"] = newJString("verified-axiom:lean-replay")
  ```

**Fix:**
- `promoteToCertVerifiedAxiom` now promotes **only to `certGreen`**.
- `certVerifiedAxiom` is now reserved for certificates with:
  - `axiomId` (registered in `verified_axioms.nim`)
  - `axiomVersion`
  - `axiomHash` (computed and verified)
  - `linkageVerified == true`
- `validateCertGreenWritable` now rejects any `certVerifiedAxiom` write missing these fields.

---

### Path H: Previous-State Merge — Reviving Dead Verified Entries

**What happened:**  
`mergePreviousVerifiedState` in `wf_state.nim` carried forward entries from a previous `ax_proof_state.json` into the current state. If a previous entry had `status == "verified"` (or `certVerifiedAxiom` or `certIntrinsic`), and the current entry was `unattempted`, the previous status was copied over. This happened **without re-checking whether the previous proof was substantive.**

**Why it inflated ASI:**  
Once a node was marked `verified` by any means (including Paths A–G), it could be resurrected indefinitely across runs simply by existing in the previous state file.

**Evidence in code:**
- `src/cli/wf_state.nim` (old):
  ```nim
  let canCarryForward =
    currentStatus == unattemptedKey and
    (prevStatus == verifiedKey or prevStatus == "certVerifiedAxiom" or
     prevStatus == "certIntrinsic" or prevStatus == "unverifiable")
  ```

**Fix:**
- Added `prevVerifiedCarryAllowed` condition:
  ```nim
  prevVerifiedCarryAllowed =
    prevVerifiedLike and not shouldIsolateProofStateEntry(prevEntry)
  ```
- If the previous entry fails the anti-vacuity gate (legacy same-context shape, explicit vacuous SMT, or metadata-only SMT), it is **not carried forward**.

---

### Path I: `saveHint` — Zero-Vacuity & Semantic Contrast Bypass via Axiom Name

**What happened:**  
In `heal_injection.nim`, the `saveHint` procedure runs two quality gates before writing a certificate:
1. `validateZeroVacuity` — rejects trivially-true propositions
2. `checkSemanticContrast` — rejects propositions whose negation is UNSAT

However, **both gates had an override**: if `verifiedAxiomName(hint.leanProposition)` returned a non-empty string, the rejection was bypassed and the hint was promoted anyway.

**Why it inflated ASI:**  
Any hint that happened to contain a substring matching a known axiom name (e.g., `.length >= 0`) would bypass vacuity detection. This allowed tautologies like `∀ (n : Nat), n = n` to be promoted if they contained a matching token.

**Evidence in code:**
- `src/cli/commands/heal_injection.nim` (old):
  ```nim
  let postVacuityAxiomName = verifiedAxiomName(hint.leanProposition)
  if postVacuityAxiomName.len > 0:
    logLines.add("[VerifiedAxiom] Zero-Vacuity bypassed...")
    # Continue to certificate writing
  ```

**Fix:**
- Replaced `verifiedAxiomName` (token-based string matching) with `axiomMatchesLeanProposition` (semantic shape matching + registry lookup).
- A bypass is now allowed **only** if the proposition genuinely matches a registered axiom's proof obligation shape, and the resulting certificate includes:
  - `axiomId`
  - `axiomVersion`
  - `axiomHash`
  - `linkageVerified: true`

---

## 3. Root Cause Patterns

The nine paths are not independent bugs. They share four systemic anti-patterns:

### Pattern 1: "Something is Better Than Nothing" Fallback
- **Paths:** A, B, C
- **Mechanism:** When real semantic content is missing, the system generates a placeholder (`depth >= 0`, `ast_parse_failed_isolated`, `(assert true)`) rather than admitting ignorance.
- **Result:** Placeholders are treated as genuine evidence.

### Pattern 2: "Status Implies Evidence" Laundering
- **Paths:** E, H
- **Mechanism:** A `verified` string in a JSON file is treated as cryptographic proof. The pipeline trusts the label rather than verifying the underlying artifacts (Lean compiler output, negative test logs, SMT query substance).
- **Result:** Any code that can write `"verified"` to JSON becomes a trust root.

### Pattern 3: Scope Confusion — Vacuity by Conflation
- **Path:** D
- **Mechanism:** Proof assumptions and proof goals are placed in the same logical scope. Unsatisfiability of the combined formula is misinterpreted as validity of the goal, when it may simply indicate inconsistent assumptions.
- **Result:** `unsat` becomes a meaningless signal.

### Pattern 4: Axiom Trust Override
- **Paths:** G, I
- **Mechanism:** The existence of a "verified axiom" registry is used as a universal bypass for all quality gates. If a proposition *looks like* an axiom, it is exempt from scrutiny.
- **Result:** Axioms become a laundering mechanism for arbitrary tautologies.

---

## 4. Remediation Validation

### 4.1 Code-Level Fixes (Commit `66c869b2`)

| File | Lines Changed | Fix Summary |
|---|---|---|
| `src/core/boundary_extractor.nim` | +2/-3 | Removed `depth >= 0` fallback; return early for no boundaries |
| `src/core/gateway.nim` | +200/-30 | 2-pass SMT gateway; vacuous/metadata-only assertion detection; `injectContradiction` hard-reject |
| `src/core/smt_hints.nim` | +14/-? | Metadata symbol detection in hint generation |
| `src/cli/wf_state.nim` | +144/-? | `applyProofStateAntiVacuityGate`; `shouldIsolateProofStateEntry`; previous-state carry restriction |
| `src/cli/report_cli.nim` | +61/-10 | Substantive evidence gate before sync; `certPseudoVerified` isolation |
| `src/verification/certificate_manager.nim` | +30/-10 | `certVerifiedAxiom` requires axiom registry linkage; `promoteToCertVerifiedAxiom` now promotes to `certGreen` only |
| `src/verification/analyzer.nim` | +25/-? | `axiomId`/`version`/`hash`/`linkageVerified` loading; `applyAxiomLinkageGate` |
| `src/verification/gate_rules.nim` | +18/-? | Architecture gate integration with axiom linkage |
| `src/core/orchestrator_vault.nim` | +2/-1 | Vault hydration rejects metadata-only SMT formulas |
| `src/core/verified_axioms.nim` | +16/-? | `axiomMatchesNormalizedShape` for semantic matching |
| `src/cli/commands/heal_injection.nim` | +27/-9 | `axiomMatchesLeanProposition` replaces token-based bypass |
| `tests/integrity_check.nim` | +35/-67 | Tests updated to expect `axiomErrVacuousContradiction` for empty/true/injected-contradiction cases |

### 4.2 Post-Fix Verification

```bash
$ ./bin/main report --calculate-asi --cert-dir src/verification/certificates
asiFixed4 = 0.0000

$ ./bin/main verify-certificates
missingCertificates = 1
blockingFailure = true
```

- **ASI = 0.0000**: Honest. No function has passed all substantive gates.
- **Missing certificate = 1**: One function lacks any certificate (expected for unproven code).
- **Blocking failure = true**: The hard gate is active and rejecting non-compliant certificates.

### 4.3 Pre-Push Gate Behavior

The pre-push ASI gate now treats `0.0000` as an **expected value after 2026-05-02 audit** (warning-only). This is a temporary policy: once real proofs begin to accumulate, the threshold will be restored to hard enforcement.

---

## 5. Recommendations

1. **Do not chase ASI 1.0000 prematurely.** The next legitimate ASI increase must come from:
   - A function with genuinely derivable semantic boundaries
   - A Lean theorem that passes kernel replay
   - A negative mutation test that fails (proving the theorem is not vacuous)
   - Axiom registry linkage with hash verification

2. **Stream.jsonl rotation.** At 289,305 lines (~91 MB before cleanup), the audit stream needs a monthly archival policy to prevent local filesystem bloat.

3. **Tag alignment.** `v0.3.8` currently points to the pre-remediation commit. Consider:
   - Moving `v0.3.8` to `66c869b2`, OR
   - Creating `v0.3.9` at `66c869b2` to mark the "honest zero" milestone.

4. **Continuous vacuity monitoring.** The `tests/gateway/vacuity_ban_feature_test.nim` test suite must be run on every PR. Any new code path that generates SMT assertions should be screened by `hasNonSubstantiveSmtAssertion`.

---

## Appendix: ASI Ledger — The Fake 1.0000 Journey

```json
{"ts":"initial","asiFixed4":"0.0000","verified":0,"total":2598,"delta":0}
...
{"ts":"2026-05-13T04:46:18Z","asiFixed4":"1.0000","verified":2598,"total":2598,"delta":1}
```

The ledger records 3,729 snapshots of the climb. The final `1.0000` value is now understood to be the culmination of 6,185 `verified` transitions, the majority of which were generated through Paths A–I documented above.

The next honest ledger entry will start from `0.0000`.
