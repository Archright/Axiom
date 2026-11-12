# Technical Debt Report: Tautology Injection Pipeline
> **Note (2026-05-25):** CONTEXT.md was merged into AGENTS.md §0-§1. References to "CONTEXT.md" below refer to the pre-merge structure. See AGENTS.md for current SSOT.

**Report ID**: TD-2026-05-TAUTOLOGY  
**Date**: 2026-05-04  
**Status**: ACTIVE — ASI 1.0000 enforcement SUSPENDED pending root-cause remediation  
**Severity**: ARCHITECTURAL (proven vacuous-proof paths exist in the execution graph)  
**Affected Systems**: Proof synthesis, certificate management, static rule engine, SMT gateway, Lean replay, ASI calculation  

---

## 1. Executive Summary

The 2026-05-02 fundamental audit rejected 1,588 tautology proofs and collapsed ASI from `1.0000` to `0.0000`. This report documents **verified execution paths** where vacuous proofs are generated, normalized, or promoted to `verified` status.

**Key Finding**: There are at least **three independently confirmed paths** where a meaningless proposition (`True`, `n = n`, `x = x`) passes the Lean 4 kernel and is promoted to `verifiedKey` by the healing orchestrator.

**Policy Decision**: The ASI `1.0000` hard gate is **suspended** until all confirmed paths are severed and validated through BDD scenarios.

---

## 2. Verified Execution Paths (Experimental Evidence)

### Path A — Smart Search Induction Tautology → Verified Promotion

**Code**: `src/core/smart_search.nim:194-203`
```nim
func emitInductionProposition*(fnName: string): string {.nosideeffect.} =
  "∀ (n : Nat), n = n"

func emitPatternMatchingProposition*(fnName: string): string {.nosideeffect.} =
  "∀ (x : α), x = x"
```

**Execution**: `heal.nim:99-115`
1. `selectInferenceStrategy(tryAttempt)` selects `isStructuralInduction` or `isPatternMatching`.
2. `generateSemanticHintWithStrategy` returns a `SemanticHint` containing the self-equality proposition.
3. `saveHint` is invoked with the tautological proposition.
4. If `saveErr.len == 0`, the status is set to `verifiedKey` and the loop breaks.

**Experimental Verification**:
```bash
$ cat << 'EOF' > /tmp/test_induction.lean
theorem foo (h_sys : ∀ (n : Nat), n = n) :
  ∀ (n : Nat), n = n := by
  exact h_sys
EOF
$ lean /tmp/test_induction.lean
# Exit code: 0
```

**Verdict**: **CONFIRMED** — The Lean 4 kernel accepts `n = n`. The `heal.nim` orchestrator promotes it to `verifiedKey` if `saveHint` passes.

---

### Path B — Submit CLI Fallback Tautology

**Code**: `src/cli/commands/submit.nim:64-72`
```nim
proc sanitizeTheoremSource(source: string): string {.raises: [].} =
  var theoremSrc = extractLeanTheoremFromSource(source)
  theoremSrc = theoremSrc.strip()
  let tokens = tokenizeLowered(theoremSrc)
  if "theorem" notin tokens and "lemma" notin tokens and "def" notin tokens:
    theoremSrc = "theorem generated_theorem : True := by\n  trivial\n" & theoremSrc
  theoremSrc
```

**Execution**: `submit.nim:166`
```nim
var theoremSource = sanitizeTheoremSource(leanstralRes.theoremSource)
```

**Experimental Verification**:
```bash
$ cat << 'EOF' > /tmp/test_trivial.lean
theorem generated_theorem : True := by
  trivial
EOF
$ lean /tmp/test_trivial.lean
# Exit code: 0
```

**Verdict**: **CONFIRMED** — When Leanstral returns malformed output, the CLI prepends a tautology theorem that passes the Lean kernel.

---

### Path C — SMT Gateway Vacuous Default

**Code**: `src/core/gateway.nim:547-552`
```nim
func buildInjectedSmtlib2*(request: AxiomProofRequest): string =
  let ownFormula =
    if request.expectedSmtlib2.len > 0:
      request.expectedSmtlib2
    else:
      "(assert true)"
```

**Experimental Verification**:
```bash
$ z3 /tmp/test_assert_true.smt2
sat
```

**Verdict**: **CONFIRMED** — When no SMT formula is provided, the gateway injects `(assert true)`, which Z3 evaluates as `sat` (satisfiable by all models). Whether this propagates to a `certGreen` verdict depends on the solver result interpretation logic in `gateway.nim`, which requires additional tracing to confirm.

---

## 3. The 518 Symbolic Warning Context (Confirmed)

**Code**: `src/verification/gate_rules.nim:577-620`

The `applySymbolicInvariantGate` procedure emits `missing-loop-invariant` with `severity: agWarning` and **explicitly preserves ASI**:

```nim
# Phase 4: missing-loop-invariant is a warning to avoid ASI collapse.
# ... Only semantic-hallucination (proven-but-wrong) is blocking.
let violation = SymbolicInvariantViolation(
  ...
  severity: agWarning,
  ...
)
result.violations.add(violation)
# Warning: no certificate demotion, ASI preserved
```

**ASI Calculation**: `src/verification/analyzer.nim:209-225`
```nim
func computeArchitectureStabilityIndex(...): float =
  let coverage = certifiedFunctions.float / totalFunctions.float
  let score = coverage * (1.0 - retryPenalty)
```

`certifiedFunctions` is `summary.verifiedFunctions`, which counts every `certGreen` certificate regardless of whether it has a verified loop invariant. The `symbolicInvariantGate.blockingFailures` is **not** incremented for `missing-loop-invariant`, so it cannot trigger the `blockingFailure` flag.

**Verdict**: **CONFIRMED** — The 518 `missing-loop-invariant` warnings are `agWarning`-only. The functions remain `certGreen` and inflate ASI. The audit trail even records `demotionKind = "certRed"` for these warnings, but the actual certificate object is **never demoted**.

---

## 4. Additional Suspected Paths (Code Verified, Execution Pending)

### Path D — Certificate CLI Normalization of Fraud
**Code**: `src/cli/certificate_cli.nim:269-270`
```nim
if tactics[i].strip() == "exact True.intro":
  tactics[i] = "trivial"
```
**Status**: Code confirmed. This normalizes a banned vacuous proof into an "acceptable" equivalent instead of rejecting it.

### Path E — Static Rule Caching of Vacuous Constraints
**Code**: `src/verification/proof_summarizer.nim:44-54`
```nim
func normalizeSmtConstraint*(constraint: string): string {.raises: [].} =
  ...
  if not isSmtAssertLine(normalized):
    return "(assert true)"
  ...
  if assertionLines.len == 0:
    "(assert true)"
```
**Status**: Code confirmed. Called from `summarizeSuccessfulProof`, which is invoked from `heal_leanstral.nim:127` after `verifyRes.verified` is true. If a Lean proof succeeds but has no extractable SMT assertions, the static rule stores `(assert true)`.

### Path F — Universal Mapper Vacuity
**Code**: `src/translator/universal_mapper.nim:115, 343`
```nim
smt: "(assert true)"
```
**Status**: Code confirmed. Used for `external_input` and `mapGenericNode` (noop) transitions.

---

## 5. Root Cause Refinement

The original claim of "eight independent layers" is **retracted**. The confirmed and suspected paths share a **single root cause pattern**:

> **When real data (invariant, theorem, SMT formula) is missing or malformed, the system falls back to a trivially-true default instead of failing.**

This pattern manifests in:
1. **Smart search** — No AST-derived proposition → emit `n = n`.
2. **Submit CLI** — No theorem token in output → prepend `True := by trivial`.
3. **SMT gateway** — No expected SMT formula → inject `(assert true)`.
4. **Proof summarizer** — No extractable assertions → normalize to `(assert true)`.
5. **Certificate loader** — Encounters `exact True.intro` → normalizes to `trivial`.
6. **Symbolic gate** — No verified invariant → warning only, preserve ASI.

---

## 6. Remediation Roadmap (ASI Gate Suspended)

### Phase A — Sever Verified Paths (Immediate)
- [ ] `smart_search.nim:194-203`: Reject `n = n` and `x = x`. Require AST-derived variable dependencies. If none found, return `none(SemanticHint)`.
- [ ] `submit.nim:70`: Remove `True := by trivial` fallback. Return `unverifiable` when Leanstral output is malformed.
- [ ] `gate_rules.nim:610`: Change `missing-loop-invariant` severity from `agWarning` to `agBlocking` or introduce a non-zero ASI penalty.

### Phase B — Remove Vacuous Defaults (Short-term)
- [ ] `gateway.nim:552`: Remove `(assert true)` default. Return `solverUnknown`.
- [ ] `proof_summarizer.nim:51, 54`: Reject non-SMT input instead of normalizing to `(assert true)`.
- [ ] `certificate_cli.nim:269`: Reject `exact True.intro` with `certRed` instead of normalizing to `trivial`.

### Phase C — Close Gate Bypasses (Medium-term)
- [ ] `heal.nim`: Route all static strategy hints through `Semantic Integrity Gate` before `saveHint`.
- [ ] `lean_lsp.nim`: Make negative mutation test mandatory in the default compiler verification path.

### Phase D — Re-enable ASI Hard Gate (Post-remediation)
- [ ] All Phase A–C changes must pass `prek` gates and BDD scenarios.
- [ ] `ax prove` must confirm no new fingerprint mismatches.
- [ ] `ax heal --limit N` must confirm no new `unverifiable` nodes caused by structural changes.
- [ ] Only then may the ASI `1.0000` hard gate be reactivated.

---

## 7. Verification Criteria for Closure

This technical debt is considered resolved when **all** of the following are proven:

1. `emitInductionProposition` and `emitPatternMatchingProposition` no longer exist, or return `none(SemanticHint)` when no real dependency is found.
2. `sanitizeTheoremSource` rejects malformed output instead of prepending `True := by trivial`.
3. `buildInjectedSmtlib2` does not emit `(assert true)` as a default.
4. `normalizeSmtConstraint` rejects non-standard input instead of returning `(assert true)`.
5. `missing-loop-invariant` either demotes the certificate or applies a non-zero ASI penalty.
6. BDD scenarios cover each confirmed path (A–F).
7. `ax report --calculate-asi` can return `1.0000` without symbolic warnings being ignored or tautologies being counted as verified.

---

## 8. Related Documents

- `CONTEXT.md` — Phase 6 status, ASI policy, Wave 1.5–6.1 architecture decisions
- `GUARDIAN.md` — §0 No-Downgrade, §13 No Non-Deterministic Architecture, §14 Architecture Red Lines
- `docs/history/2026_05_refactoring.md` — 2026-05-02 audit results
- `docs/spec/uap_logic.md` — `invariant := True` fallback prohibition
- `.agents/skills/axiom-healing.md` — Zero-Vacuity hint quality gate

---

## 9. Audit Trail

| Date | Event |
|------|-------|
| 2026-05-02 | Fundamental audit rejects 1,588 tautology proofs; ASI drops to `0.0000` |
| 2026-05-04 | Root-cause investigation completed; 3 execution paths experimentally confirmed |
| 2026-05-04 | Original "8 independent layers" claim retracted; single fallback pattern identified |
| 2026-05-04 | ASI `1.0000` hard gate formally suspended; this report published |
| 2026-05-04 | **10 source files patched** to sever all confirmed vacuous-proof paths |
| 2026-05-04 | `ax prove` passes; `ax heal --limit 5` runs without ASI regression or new mismatchFunctions |
| 2026-05-04 | BDD scenario `tests/features/vacuity_ban.feature` created with 9 executable scenarios |

---

*This document is the single source of truth for the tautology technical debt. Claims marked "CONFIRMED" are backed by direct code inspection and/or live execution (Lean 4.29.0, Z3 4.13.3). Claims marked "suspected" require additional tracing to confirm reachability in the full pipeline.*
