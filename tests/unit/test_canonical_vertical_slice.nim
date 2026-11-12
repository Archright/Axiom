## P0.3 — Canonical Vertical Slice (domain level): VerificationModel →
## Semantic Kernel → Canonical CHC → Z3(Spacer) → Candidate Evidence →
## EvidenceValidator → ValidatedEvidence → vsProved.
##
## Every stage uses the REAL canonical compiler and validator — no
## legacy bridge (buildChcFromVerificationModel), no manufactured passes.
## If any link in the chain fails to prove, the test honestly FAILs or
## returns Inconclusive (§0.9 Anti-Theater).
##
## Solver-dependent legs are guarded by the canonical Z3 path resolution
## (resolveZ3Path). A leg whose verdict comes from Z3 must never report a pass
## without Z3 actually running — `status != vsProved` in particular is
## satisfied by a dead solver and would certify nothing. When Z3 is not
## launchable the leg reports an explicit SKIP and asserts nothing (§0.9).

import std/options
import std/os
import std/strutils
import std/unittest
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/verification_model_types
import core/trusted/symbol_table_types
import core/trusted/private/canonical_chc_compiler
import core/trusted/verification_result_types
import core/trusted/candidate_evidence
import verification/solver_adapter
import verification/invariant_synthesizer
import verification/evidence_validator
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

let bv64 = irTypeBitVec64()

proc accumulatorModel(): VerificationModel =
  ## x = 0 ; while (x < 10) { x = x + 1 } ; assert x >= 10
  var sem = VMSemantic()
  sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irLit(0))
  var up = ParallelUpdate()
  up.addAssignment("x", irAdd(irVar("x", bv64), irLit(1)))
  sem.initTransition(NodeId(1), NodeId(2), irLt(irVar("x", bv64), irLit(10)), up)
  sem.property = some(irGe(irVar("x", bv64), irLit(10)))
  sem.exitGuard = some(irLt(irVar("x", bv64), irLit(10)))
  var st = SymbolTable()
  st.addSymbol("x", SymbolOrigin(kind: sokLoopIndex), bv64)
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st))

suite "Canonical Vertical Slice (VM → Kernel → Canonical CHC → Spacer)":
  test "canonical compiler emits a well-typed non-vacuous HORN script":
    let cm = canonicalize(accumulatorModel(), defaultEncodingConfig())
    let script = serialize(toCHCAst(cm))
    check script.contains("(set-logic HORN)")
    check script.contains("(declare-rel state")
    check script.contains("error")
    check script.contains("(query error)")
    check script.contains("(check-sat)")
    check script.contains("(rule (state")
    check not script.contains("bv2int")

  test "canonical script genuinely proves (sosUnsat)":
    if not z3Available:
      echo z3MissingMsg
      skip()
    else:
      let cm = canonicalize(accumulatorModel(), defaultEncodingConfig())
      let script = serialize(toCHCAst(cm))
      let adapter = newSolverAdapter(z3Path = z3Bin, timeoutMs = 10000, printCertificate = true)
      let outcome = adapter.solve(script)
      check outcome.status == sosUnsat

suite "Anti-Theater Vertical Slice (Synthesizer + EvidenceValidator via canonical model)":
  test "synthesizer candidate yields vsProved (genuine inductive invariant)":
    if not z3Available:
      echo z3MissingMsg
      skip()
    else:
      let model = accumulatorModel()
      let ce = synthesizeCandidateEvidence(model)
      let validator = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 8000)
      let val = validator.validate(model, ce)
      check val.overall.status == vsProved

  test "tampered invariant (upper bound 5) → NOT Proved":
    if not z3Available:
      echo z3MissingMsg
      skip()
    else:
      let model = accumulatorModel()
      let ce = candidateEvidence(cesSynthesizer, @[("state", "(and (bvuge x #x0000000000000000) (bvule x #x0000000000000005))")], provenance = "axiom:interval", fingerprint = "")
      let validator = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 8000)
      let val = validator.validate(model, ce)
      check val.overall.status != vsProved
      # "Not proved" must be a counterexample Z3 actually found. `rkSolverUnknown`
      # means the solver returned no verdict at all and would satisfy `!=` vacuously.
      check val.overall.reason == rkCandidateCounterexample

  test "empty evidence → vsInconclusive (C20 gate)":
    if not z3Available:
      echo z3MissingMsg
      skip()
    else:
      let model = accumulatorModel()
      let ce = CandidateEvidence()
      let validator = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 8000)
      let val = validator.validate(model, ce)
      check val.overall.status == vsInconclusive
      # A dead solver also yields vsInconclusive — pin that a verdict was reached.
      check val.overall.reason != rkSolverUnknown

  test "tampered property (x >= 20) → NOT Proved":
    if not z3Available:
      echo z3MissingMsg
      skip()
    else:
      var sem = VMSemantic()
      sem.initState("x", bv64, SymbolOrigin(kind: sokLoopIndex))
      sem.initExprs.add(irLit(0))
      var up = ParallelUpdate()
      up.addAssignment("x", irAdd(irVar("x", bv64), irLit(1)))
      sem.initTransition(NodeId(1), NodeId(2), irLt(irVar("x", bv64), irLit(10)), up)
      sem.property = some(irGe(irVar("x", bv64), irLit(20)))
      sem.exitGuard = some(irLt(irVar("x", bv64), irLit(10)))
      var st = SymbolTable()
      st.addSymbol("x", SymbolOrigin(kind: sokLoopIndex), bv64)
      let model = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st))
      let ce = synthesizeCandidateEvidence(model)
      let validator = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 8000)
      let val = validator.validate(model, ce)
      check val.overall.status != vsProved
      check val.overall.reason == rkCandidateCounterexample

  test "raw solver unsat with empty cert → not a silent Proved":
    if not z3Available:
      echo z3MissingMsg
      skip()
    else:
      let cm = canonicalize(accumulatorModel(), defaultEncodingConfig())
      let script = serialize(toCHCAst(cm))
      let adapter = newSolverAdapter(z3Path = z3Bin, timeoutMs = 8000, printCertificate = true)
      let outcome = adapter.solve(script)
      # This leg is named for the raw solver verdict — assert it, so a solver
      # that never answered cannot reach the empty-certificate branch vacuously.
      check outcome.status == sosUnsat
      let ce = toCandidateEvidence(outcome)
      if ce.isEmpty():
        let validator = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 8000)
        let val = validator.validate(accumulatorModel(), ce)
        check val.overall.status == vsInconclusive
      else:
        let validator = newEvidenceValidator(z3Path = z3Bin, timeoutMs = 8000)
        let val = validator.validate(accumulatorModel(), ce)
        check val.overall.status in {vsProved, vsInconclusive}
