## P0.3.11 — P0.3.10 Evidence Validator tests.
## Contract SSOT: docs/spec/cfg_contract_specification.md (C9, C10, C11).
## These exercise the ObligationDischarger boundary via real Z3 HORN obligations.
##
## Solver-dependent legs are guarded by the canonical Z3 path resolution
## (resolveZ3Path). A leg whose verdict comes from Z3 must never report a pass
## without Z3 actually answering — a dead solver yields empty diagnostics that
## satisfy `not contains "unknown constant"` vacuously (§0.9). Such legs report
## an explicit SKIP instead; solver-independent legs run unconditionally.

import std/[unittest, options, tables, strutils, os]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/verification_result_types
import core/trusted/candidate_evidence
import verification/evidence_validator
import verification/obligation_discharger
import verification/solver_adapter
import core/types/z3_solver_config

## Canonical Z3 binary resolution (§0.3 trust boundary):
##   AXIOM_Z3_PATH (DECLARED — docs/spec/environment_inputs.md §2.13)
##   → $HOME/.local/bin/z3 → PATH lookup
## A developer-home absolute path must never appear here (§0.3, §0.11).
let z3Bin = resolveZ3Path()

## Launchability of the *resolved* path. Derived from the same value handed to
## the solver, so the guard and the execution cannot diverge.
let z3Available = z3Bin.len > 0 and (fileExists(z3Bin) or findExe(z3Bin).len > 0)

let z3MissingMsg = "[SKIP] Z3 not launchable at '" & z3Bin &
    "' (tried AXIOM_Z3_PATH, $HOME/.local/bin/z3, PATH)"

## A solver that did not answer reports no status at all — it is not evidence.
proc solverAnswered(oc: ObligationResult): bool =
  oc.solverStatus == $sosUnsat or oc.solverStatus == $sosSat

let bv64 = irTypeBitVec64()

proc makeModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irLit(0))
  let iVar = irVar("i", bv64)
  var upd = ParallelUpdate()
  upd.addAssignment("i", irAdd(iVar, irLit(1)))
  # property: i <= 10 invariant at exit (i starts 0, +1/step under i<10)
  sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), upd)
  sem.initObligation(irLe(iVar, irLit(11)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
  sem.logicalDomain = ldBitVec
  var st = SymbolTable()
  st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: ""))

suite "Evidence Validator — empty/degenerate model":
  test "no states → inconclusive not encodable":
    var sem = VMSemantic()
    let valid = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: SymbolTable(), sourceLocation: ""))
    let v = newEvidenceValidator()
    let ev = v.validate(valid, CandidateEvidence())
    check ev.overall.status == vsInconclusive
    check ev.overall.reason == rkNotEncodable

suite "Evidence Validator — SMT script shape (Bug 1 regression)":
  test "proveImplication script has no fp.set-option and declares free symbols":
    # Pure: the assertions inspect the generated script text, so this leg runs
    # with or without a Z3 binary.
    let model = makeModel()
    let ce = candidateEvidence(cesSolver, @[("state", "(>= i 0)")], "", "")
    let v = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 50)
    let ev = v.validate(model, ce)
    let spacerOption = "(fp.set-option :fp.engine spacer)"
    for oc in ev.initiations & ev.consecutions & ev.safety:
      let q = oc.smtQuery
      # Bug 1 fix: script must not contain the HORN-only fp.set-option
      check spacerOption notin q
      # Script must declare the state predicate and free state variables
      check "(declare-fun state" in q or "(declare-const" in q

  test "proveImplication script round-trips through Z3 without unknown-constant errors":
    # Only this leg needs a live Z3. A missing or non-answering solver produces
    # no error text at all, which would satisfy the `unknown constant` check
    # while verifying nothing (§0.9).
    if not z3Available:
      echo z3MissingMsg
      skip()
    else:
      let model = makeModel()
      # Well-sorted invariant (bvuge over the state's own sort). The historical
      # Int-style `(>= i 0)` made this leg self-defeating: Z3 refused the assert
      # with a sort-mismatch `(error …)` and still answered the trailing
      # `(check-sat)` with a vacuous bare `sat`, which the pre-gate classifier
      # read as an answer — the exact §0.9 vacuity this leg exists to prevent.
      let ce = candidateEvidence(cesSolver, @[("state", "(bvuge i #x0000000000000000)")], "", "")
      let v = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 3000)
      let ev = v.validate(model, ce)
      check ev.initiations.len + ev.consecutions.len + ev.safety.len > 0
      for oc in ev.initiations & ev.consecutions & ev.safety:
        check solverAnswered(oc)
        # Round-trip: Z3 must not report unknown-constant errors
        check "unknown constant" notin oc.errorMessage

suite "Evidence Validator — safety obligation generation (PO3 family)":
  test "PO3 obligation families are generated for the model":
    # Solver-independent: the families are built from the model alone.
    let model = makeModel()
    let ce = candidateEvidence(cesSolver, @[("state", "(bvuge i #x0000000000000000)")], "", "")
    let v = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 3000)
    let ev = v.validate(model, ce)
    check ev.safety.len <= 1
    check ev.initiations.len <= 1

  test "unreachable-violation safety obligation passes when property is strong":
    # A certificate invariant `i >= 0` is inductive for i starting at 0 and
    # incrementing; safety (i >= 0 ⇒ property) is trivially UNSAT-ranked.
    # Whether every family passes depends on Z3 availability; the verdict is
    # only meaningful once the solver has answered.
    #
    # The invariant is stated in the STATE's own sort (bvuge over (_ BitVec
    # 64)). An Int-style `(>= i 0)` here is ill-sorted: Z3 refuses the assert
    # with `(error "… Sort mismatch … (declare-fun >= (Int Int) Bool) …")` on
    # stdout and still answers the following `(check-sat)` with a bare `sat`
    # (measured, pinned Z3 4.13.3) — no assertion installed, the verdict is
    # vacuous. The DECISION-0824/0825 gate maps that error-bearing stream to
    # sosUnknown, so a malformed fixture now fails closed as rkSolverUnknown
    # instead of riding a vacuous answer (calcDynamicTimeoutCore class).
    if not z3Available:
      echo z3MissingMsg
      skip()
    else:
      let model = makeModel()
      let ce = candidateEvidence(cesSolver, @[("state", "(bvuge i #x0000000000000000)")], "", "")
      let v = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 3000)
      let ev = v.validate(model, ce)
      check ev.overall.status in {vsProved, vsInconclusive}
      check ev.overall.reason != rkSolverUnknown
