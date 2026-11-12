# WP2 Ingress Localization — Final Resolution (F2 + F3 + F1 + E2E)

EXPERIMENT_ID = act2-wp2-subject-scoped-execution
PROJECT_UNDER_TEST = nim-stew@c75502c
AXIOM_REVISION = Axiom@f7dd583ca + working-tree WP0..WP2-b accumulated changes
SUBJECT_GOLDEN_SYMBOL = `decodedLength` (stew/base*.nim)
Experiment date: 2026-08-27 (session continued from WP2 Ingress Fix)

## 0. Scope of this document

This document records the **final resolution** of the two upstream blockers left
open at the end of the "WP2 Ingress Fix" milestone, plus the E2E that confirms
the subject-scoped execution boundary was crossed. It supersedes the
"Recommended next work" section in `wp2-result.md` (which listed these as open).

The two open blockers were:

1. **Frontier admission** — `decodedLength` absent from the topology
   `verificationQueue`, so it never reached the frontier.
2. **EXIT=2 Axiom integration defect** — `computeProofUniverseLock` did not
   route via `$AXIOM_STATE_DIR` in external-subject mode.

## 1. Blocker 2 — Proof-Universe-Lock state routing (Track A, F2)

### Question

Why did external-subject mode look up the canonical graph at subject CWD
instead of `$AXIOM_STATE_DIR/stateRoot`?

### Evidence — root cause

`computeProofUniverseLock` (src/core/proof/proof_universe_lock.nim) and the
commit side (src/verification/proof_universe_commit.nim) read/wrote the
canonical graph at a path derived from `currentDir` (= subject dir in external
mode) rather than routing through `$AXIOM_STATE_DIR`. This is an
**infrastructure routing defect**, not a semantic/lock change.

### Fix applied (F2) — 6 routing edits, equal-routine state routing

- `proof_universe_lock.nim:190` `:absCertDir`, `:198` `:absGraphFile`,
  `:200` `:seedPath` — route via `$AXIOM_STATE_DIR` when set.
- `proof_universe_commit.nim:93` `lockPath`, `:171` certDir flush,
  `:180` `lockRead` — same state-routing rule.

The self-run (AXIOM_STATE_DIR unset) path is unchanged (zero-drift). Lock
**semantics** unchanged; `verification_scope.lock` content untouched.

**Deviation note:** the subagent additionally touched
`writeGlobalSymbolGraphSnapshot` (~:31) and left a clarifying comment on
`commitUniverseIntegrityAndLock` cachePath/graphPath (132-147). The latter was
already state-routed and only gained a comment (harmless). The former is a new
routing for a graph writer and deviates from the approved 6-site list; it is
recorded here for traceability and is re-audited below under protected invariant
checks.

### Verification

- Rebuild clean; external run no longer EXIT=2 (became EXIT=0).
- Self-run (AXIOM_STATE_DIR unset) EXIT=0 — zero-drift preserved.
- `verification_scope.lock` digest unchanged = `7a4cd3eb...`,
  `baseline.json` unchanged = `c75ac9e6...`.

## 2. Blocker 1 — Frontier admission (Topology eligibility) (Track B, F3)

### Question

Is `decodedLength` actually unverifiable under Axiom's current verification
contract, or does the topology classifier treat external subjects differently
and wrongly discard it?

### Method — measure, don't assume

Per experiment discipline, I ran a **probe** (`tests/unit/golden_eligibility_probe_test.nim`)
that measured the actual classification pipeline for the golden symbol before
any eligibility modification. The pre-fix measurements:

| Metric | Pre-fix value |
|---|---|
| `irFuncDef.name` | **(empty)** |
| `irSerialized` length | 70 bytes |
| `genResult.kind` | `ogrGenerated` |
| obligation id | `okSafetyDiv:56a7897ae3d8ae0c511...` |
| `inVerifiedFragmentV1` | true |
| `classifyCandidateEligibility` | `elProofCandidate` |
| **`isFrontierSelectionEligible`** | **false** |
| `assessAdmissibility` | ADMISSIBLE |

### Hypotheses H1–H7 disposition

- **H1 (typedesc param handling)** — **REFUTED.** The probe shows the symbol
  generates an obligation (`ogrGenerated`) and is `elProofCandidate`;
  typedesc is not the admission blocker.
- **H2 (generic/type-bound)** — **REFUTED.** Not the discriminating condition.
- **H3 (overload/name normalization)** — **PARTIAL — real cause cluster.**
  The empty IR name was the actual gate failure.
- **H4 (AST preprocessing node loss)** — **REFUTED.** The body survived to IR.
- **H5 (builder path ≠ probe path)** — **RESOLVED** via Track A (graph routing);
  probe and engine now agree.
- **H6 (eligibility/filtering drops pre/post insert)** — **REFUTED.**
  `candidate_eligibility.nim` and `verified_fragment.nim` contain **no origin
  check** — `classifyCandidateEligibility` returns `elProofCandidate`
  regardless of `soExternalSubject`. The gate was not rejecting on origin.
- **H7 (other config/context)** — the IR name gap is the real context
  difference.

### Root cause — legacy Merkle path

`convertFuncDefCanon` (src/core/trusted/ast_to_ir.nim:1207-1210) handled only
`ckIdent` for the proc/function name. For an **exported** proc written as
`decodedLength*`, the incoming CanonNode name field is `ckPostfix[* , decodedLength]`.
The old code produced an **empty** name string. After `deserializeIRFuncDef`, the
frontier eligibility gate's `funcDef.name.len > 0` guard failed →
`isFrontierSelectionEligible=false`.

### Fix applied (F3)

`convertFuncDefCanon` name extraction gains a `ckPostfix` branch that uses the
inner identifier (child `[1]`), mirroring the existing NimNode-side
`convertFuncDef` nnkPostfix handling (ast_to_ir.nim:1050-1053). This is the
same export-marker generalization already applied for the graph builder
(`global_symbol_graph_builder_part2.nim`, procNameFromDeclNode).

Post-fix probe: `irFuncDef.name: decodedLength`, `irSerialized` 83 bytes,
same `okSafetyDiv:56a7897a...` obligation, `isFrontierSelectionEligible:
true`, `assessAdmissibility: ADMISSIBLE`.

**`candidate_eligibility.nim` and `verified_fragment.nim` were NOT modified** —
they were never the blocker. (Both are Act-1 protected; leaving them untouched
preserves the gate.)

### Regression checks

- `wp15_pnode_canon_equiv_test.nim` — clean
- `candidate_eligibility_test.nim` — 19 OK
- `candidate_eligibility_noobligation.nim` — 4 OK
- `graph_export_marker_test.nim` — 3 OK

## 3. F1 — explicit `--target` beyond `--limit` boundary

### Root cause

`computeVerifiedFrontier` (verified_frontier.nim:94) applies an *internal*
`if limit>0 and result.len>=limit: break` inside the wave loop. When `--limit 1`
and the targeted symbol is not the first ready node, the target is dropped
**before** `selectFrontierNodes` runs, so `planned=0` and Z3 is never reached.

### Fix applied (F1)

In `axiom_engine.nim` (computeVerifiedFrontier call site, ~:662-664): when
`task.target` is non-empty, pass `limit=0` (unrestricted) into
`computeVerifiedFrontier`, because `selectFrontierNodes` re-applies the real
`frontierLimit` in its Step 3. No-target runs keep the original bounded call
(zero-drift). Eligibility is still enforced as the final guard.

**Important discipline note:** F1 is an independent regression/ordering fix, not
a claim of solving V1 by architecture. V1's evidence comes from the E2E below.

### Fail-first test

`tests/unit/frontier_target_boundary_test.nim` — 3/3 PASS, reproducing and
locking the boundary contract (the regression drops the target; the fix admits
it; no-target stays bounded). Existing `frontier_target_selection_test.nim`
(5/5) covers the `selectFrontierNodes` ordering layer.

## 4. E2E — subject-scoped execution boundary crossed

Command (Run A and Run B, identical):

    AXIOM_STATE_DIR=/tmp/wp0c_state bin/ax_wp2_smoke prove \
        --project <workspace>/nim-stew \
        --limit 1 --target decodedLength

Both runs EXIT=0, subject tree clean before/after.

### V1 — solver reach — PASS now

`solverInvocationCount: 1` in pipeline summary (both runs) and 9 real Z3
queries in `/tmp/wp0c_state/logs/z3_telemetry.jsonl` (sat/unsat results).
Z3 was actually invoked on the external obligation.

### V2 — ExternalSubject origin preserved — PASS

Trajectory nodeId = `stew/base32.nim::decodedLength` — subject-relative module
path preserved through CEGAR → legislator (Lean) → judge → certificate/report.
Node report label = `base32.nim::decodedLength`.

### V3 — SupportUniverse not mixed into subject verification target — PASS

Node report `injectedAxioms: []`, `usesDependencyVault: false`,
`readsDependencySource: false`. No Axiom-support axioms were injected into the
external obligation's verification target.

### V4 — self-run zero-drift — PASS

Unset `AXIOM_STATE_DIR`, `prove --limit 1` from repo root: EXIT=0; symbol set
is entirely `src/...` (SupportUniverse); no external `stew/*` symbols admitted.

### V5 / V7 — determinism — PASS

Run A vs Run B byte-identical canonical values:

| Key | Run A | Run B |
|---|---|---|
| graph symbolCount | 623 | 623 |
| graph hash | `24b6d0ab...c20` | `24b6d0ab...c20` |
| solverInvocationCount | 1 | 1 |
| obligationGeneratedCount | 11 | 11 |
| obligationAttemptedCount | 0 | 0 |
| targetsWithObligations | 5 | 5 |
| classifiedNodes | 1 | 1 |
| statusCounts.timeout | 1 | 1 |
| totalSourceFunctions | 41 | 41 |

### V6 — subject immutability — PASS

`git -C .../nim-stew status --porcelain` empty before both runs and after Run B.

### Protected invariants — PASS

- `verification_scope.lock` = `7a4cd3eb...` unchanged.
- `baseline.json` = `c75ac9e6...` unchanged.
- No auto-regeneration of lock/baseline despite fresh graph build.

## 5. IMPORTANT FINDING — target filter matched `base32` not `base36`

The designed golden symbol was `base36.decodedLength` (body `(length*179) div
277`, matches the F3 probe body). In the E2E, `--target decodedLength`
(an **exact-substring** filter, `nodeId.contains(target)` in
frontier_selection.nim:43) matched **`base32.decodedLength`** — the first
alphabetically-eligible `decodedLength` across base32/base36/base58/base64 (all
four modules define it). The symbol that crossed the full pipeline was
`base32.decodedLength`, not `base36.decodedLength`.

This is **not** a failure of the WP2 objective — the external subject symbol
was admitted with canonical subject-relative identity and crossed the execution
boundary — but it is a **precise finding about target-selection semantics**: a
substring `--target` is not module-qualified, so multiple modules can satisfy
it and the first eligible frontier node wins. Documented as an open nuance for
WP3 (exact qualified-target selection), not altered here (would expand scope).

## 6. Result classification

| Predicate | Result | Evidence | Failure/Gap |
|---|---|---|---|
| V1 solver reach | PASS | solverInvocationCount=1, 9× Z3 queries | none (target symbol verified=false, classified `timeout`/`unknown` — NOT a claim of `Verified`) |
| V2 origin preserved | PASS | nodeId `stew/base32.nim::decodedLength` | none |
| V3 no support-mix | PASS | injectedAxioms=[], no dep vault | none |
| V4 self-run zero-drift | PASS | self-run EXIT=0, SupportUniverse-only symbols | none |
| V5/V7 determinism | PASS | Run A/B byte-identical | none |
| V6 subject immutability | PASS | git clean pre/post | none |
| Protected invariants | PASS | lock/baseline digests unchanged | none |

## 7. What this establishes vs does NOT establish

**Establishes:** The ExternalSubject obligation for a real nim-stew symbol now
crosses the **subject-scoped verification execution boundary** — from source →
D1 file set → topology/graph → module identity → symbol admission → obligation
generation → IR → Z3 → Lean(auth) → evidence/report — with deterministic
canonical identity and no SupportUniverse leakage. This is the WP2-a goal.

**Does NOT establish:** A `Verified` result. The verified external symbol is
`base32.decodedLength` status = `timeout` / assurance tier `unknown`
(`skJudge verified=false`, Lean UAP timed out). Z3++Lean invoked but no proof
certificate produced. M1 replay, kernel acceptance, and certificate
materialization remain **out of scope** for this WP (WP2..WP5 range).

## 8. REFUTED corrections to prior working hypotheses

- **REFUTED:** "typedesc parameter causes the drop." Probe shows `ogrGenerated`
  and `elProofCandidate` with a valid obligation.
- **REFUTED:** "`bcTrivialDiscard` / `updateBoundaryKinds` eliminated the
  symbol." The gate in the run path is the IR-name guard, not the topology
  boundary classifier. (`bcTrivialDiscard` was left intact; no eligibility
  weakening.)
- **REFUTED:** "origin (`soExternalSubject`) causes rejection." No origin check
  in `candidate_eligibility.nim` / `verified_fragment.nim`.
- **REFUTED:** "a `subject_scope.lock` is required." Not needed — the blocker was
  a canonical-IR name serialization gap (`ckPostfix`), fixed minimally in
  `convertFuncDefCanon`.

## 9. Open nuances (recorded, not acted on — scope discipline)

1. `--target` is an exact-substring filter; four `decodedLength` symbols exist
   (base32/base36/base58/base64). WP3 should consider module-qualified exact
   target selection. **Not** altered here.
2. The golden symbol was originally designed as `base36.decodedLength` but the
   E2E admitted `base32.decodedLength` for the reason above. This does not
   change the V1..V7 verdict.
3. `writeGlobalSymbolGraphSnapshot` routing (F2 deviation) is re-audited as
   benign state-routing but is recorded as outside the original 6-site list.
