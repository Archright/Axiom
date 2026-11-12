import std/[unittest, options, tables, strutils, os, tempfiles]
import core/trusted/verification_model_types
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/verification_result_types
import core/trusted/candidate_evidence
import core/types/solver_types
import verification/counterexample_validator
import verification/solver_adapter
import verification/batch_uap/ir_pipeline_runner

let bv64 = irTypeBitVec64()

proc makeModel(): VerificationModel =
  var sem = VMSemantic()
  sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
  sem.initExprs.add(irEq(irLit(0), irLit(0)))
  let iVar = irVar("i", bv64)
  var upd = ParallelUpdate()
  upd.addAssignment("i", irAdd(iVar, irLit(1)))
  sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), upd)
  sem.initObligation(irLe(iVar, irLit(11)), okImplicitSafety, SymbolOrigin(kind: sokImplicit))
  sem.logicalDomain = ldBitVec
  var st = SymbolTable()
  st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
  VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: ""))

suite "CounterexampleValidator — finalizeVerdict":
  test "cvConfirmed -> vsDisproved, model copied":
    let candidate = makeCandidateCounterexample("(model (define-fun i () Int 5))", smBMC, pkSpacer)
    let result = finalizeVerdict(candidate, cvConfirmed)
    check result.status == vsDisproved
    check result.model == "(model (define-fun i () Int 5))"
    check result.solverStatus == solverSat

  test "cvSpurious -> stays rkCandidateCounterexample, vsInconclusive":
    let candidate = makeCandidateCounterexample("(model (define-fun i () Int 5))", smBMC, pkSpacer)
    let result = finalizeVerdict(candidate, cvSpurious)
    check result.status == vsInconclusive
    check result.reason == rkCandidateCounterexample
    check result.model == "(model (define-fun i () Int 5))"

  test "cvUnresolved -> stays rkCandidateCounterexample, vsInconclusive":
    let candidate = makeCandidateCounterexample("(model (define-fun i () Int 5))", smBMC, pkSpacer)
    let result = finalizeVerdict(candidate, cvUnresolved)
    check result.status == vsInconclusive
    check result.reason == rkCandidateCounterexample
    check result.model == "(model (define-fun i () Int 5))"

suite "CounterexampleValidator — validateCounterexample trivial post":
  test "trivially-true postcondition yields cvSpurious (no real counterexample)":
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initExprs.add(irEq(irLit(0), irLit(0)))
    let iVar = irVar("i", bv64)
    var upd = ParallelUpdate()
    upd.addAssignment("i", irAdd(iVar, irLit(1)))
    sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), upd)
    sem.logicalDomain = ldBitVec
    var st = SymbolTable()
    st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
    let model = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: ""))
    let ce = candidateEvidence(cesSolver, @[("state", "(>= i 0)")], provenance="solver:sosSat", fingerprint="", model="(model (define-fun i () Int 5))")
    let validator = newCounterexampleValidator(z3Path = "z3", timeoutMs = 5000)
    let verdict = validator.validateCounterexample(model, ce, "z3", 5000)
    check verdict == cvSpurious

  test "empty candidate evidence yields cvUnresolved":
    let model = makeModel()
    let ce = CandidateEvidence()
    let validator = newCounterexampleValidator(z3Path = "z3", timeoutMs = 5000)
    let verdict = validator.validateCounterexample(model, ce, "z3", 5000)
    check verdict == cvUnresolved

  test "I3: solver SAT + validation confirmed -> vsDisproved":
    let model = makeModel()
    let ce = candidateEvidence(cesSolver, @[("state", "(>= i 0)")], provenance="solver:sosSat", fingerprint="", model="(model (define-fun i () Int 5))")
    let validator = newCounterexampleValidator(z3Path = "z3", timeoutMs = 5000)
    let verdict = validator.validateCounterexample(model, ce, "z3", 5000)
    let candidateResult = makeCandidateCounterexample("(model (define-fun i () Int 5))", smBMC, pkSpacer)
    let finalResult = finalizeVerdict(candidateResult, verdict)
    if verdict == cvConfirmed:
      check finalResult.status == vsDisproved
      check finalResult.model == "(model (define-fun i () Int 5))"
    else:
      check finalResult.status == vsInconclusive
      check finalResult.reason == rkCandidateCounterexample

# ---------------------------------------------------------------------------
# C20 one-state bool entry bindings (P4 witness re-validation)
# ---------------------------------------------------------------------------

proc d2Gate(c: IRExpr): IRExpr =
  ## The code's actual single-line string gate {8, 16, 31, 127} (overlay
  ## canonicalSpecIR clause 8) — a bool predicate on the byte parameter.
  irOr(irEq(c, irLit(8)),
    irOr(irEq(c, irLit(16)),
      irOr(irEq(c, irLit(31)), irEq(c, irLit(127)))))

proc d2Forbid(c: IRExpr): IRExpr =
  ## The adopted forbid set: c <= 8 or (10 <= c and c <= 31) or c == 127.
  irOr(irLe(c, irLit(8)),
    irOr(irAnd(irLe(irLit(10), c), irLe(c, irLit(31))),
      irEq(c, irLit(127))))

suite "CounterexampleValidator — C20 one-state bool entry bindings":

  test "valid bool witness accepted: C20 bool initExprs are entry equalities (cvConfirmed -> vsDisproved)":
    ## The P4 bool-binding defect, regression-pinned end-to-end through the
    ## REAL constructor (lowerPostconditionModel, precedent:
    ## test_bug_verdict_projection.nim): the C20 one-state contract model
    ## binds `result` to the actual bool body. Under the pre-fix bare
    ## reading that binding was asserted as a CONDITION — forcing the gate
    ## true, excluding every defect witness (c=7), UNSAT → cvSpurious → no
    ## promotion. The model-discriminated equality reading admits the
    ## witness; finalizeVerdict promotes to vsDisproved with the model
    ## carried (DECISION-0311/0312 chain).
    let cVar = irVar("c", bv64)
    let body = d2Gate(cVar)
    # The adopted claim (β-spliced): result == forbid reads as
    # gate(c) == forbid(c) — the property has no free `result`.
    let claim = irEq(d2Gate(cVar), d2Forbid(cVar))
    var fd = IRFuncDef(
      name: "d2BoolWitnessCarrier",
      params: @[IRFuncParam(name: "c", ty: bv64)],
      retType: irTypeBool(),
      body: body)
    fd.postConditions = @[claim]
    let model = lowerPostconditionModel(fd, contractFromFuncDef(fd))
    check model.isSome
    # C20 shape pins: parameter + result states, identity transition, result marker.
    check model.get.semantic.states.len == 2
    check model.get.semantic.states[0].name == "c"
    check model.get.semantic.states[1].name == "result"
    check model.get.semantic.states[1].irType.kind == irtBool
    check model.get.semantic.transitions.len == 1
    check model.get.semantic.transitions[0].guard == nil
    check model.get.semantic.transitions[0].update.assignments.len == 0
    check model.get.semantic.transitions[0].update.havocs.len == 0
    check model.get.semantic.resultStateName == some("result")
    # The witness the BMC lane would have captured (c=7: gate=false,
    # forbid=true → the claim is refuted).
    let ce = candidateEvidence(cesSolver,
      @[("c", "#x0000000000000007")],
      provenance = "solver:sosSat", fingerprint = "",
      model = "(model (define-fun c () (_ BitVec 64) #x0000000000000007))")
    let validator = newCounterexampleValidator(z3Path = "z3", timeoutMs = 5000)
    let verdict = validator.validateCounterexample(model.get, ce, "z3", 5000)
    check verdict == cvConfirmed
    let final = finalizeVerdict(makeCandidateCounterexample(ce.model, smBMC, pkSpacer), verdict)
    check final.status == vsDisproved
    check final.model == ce.model

  test "CHC condition no-confusion: decisive false bool condition under a guarded transition stays a bare condition (cvSpurious)":
    ## A bool initExpr on a GUARDED model is a CHC entry CONDITION, not an
    ## entry binding: the decisive false condition makes the precondition
    ## unsatisfiable → cvSpurious. Under a type-only equality reading this
    ## script would be ill-sorted (`(= i <Bool>)` over a BitVec state) and
    ## fail closed as cvUnresolved — this test pins the model-discriminated
    ## bare reading for non-C20 models.
    var sem = VMSemantic()
    sem.initState("i", bv64, SymbolOrigin(kind: sokLoopIndex))
    sem.initExprs.add(irEq(irLit(0), irLit(1)))  # decisive false condition
    let iVar = irVar("i", bv64)
    var upd = ParallelUpdate()
    upd.addAssignment("i", irAdd(iVar, irLit(1)))
    sem.initTransition(NodeId(1), NodeId(2), irLt(iVar, irLit(10)), upd)
    sem.property = some(irLe(iVar, irLit(11)))  # non-trivial negated postcondition
    sem.logicalDomain = ldBitVec
    var st = SymbolTable()
    st.addSymbol("i", SymbolOrigin(kind: sokLoopIndex), bv64)
    let model = VerificationModel(semantic: sem, metadata: VMMetadata(functionExit: NodeId(0), symbolMap: st, sourceLocation: ""))
    let ce = candidateEvidence(cesSolver, @[("state", "(>= i 0)")], provenance="solver:sosSat", fingerprint="", model="(model (define-fun i () Int 5))")
    let validator = newCounterexampleValidator(z3Path = "z3", timeoutMs = 5000)
    let verdict = validator.validateCounterexample(model, ce, "z3", 5000)
    check verdict == cvSpurious

# ---------------------------------------------------------------------------
# Error-bearing solver streams must never mint SAT (DECISION-0824/0825/0826)
#
# calcDynamicTimeoutCore incident: Z3 answers a refused command with
# `(error …)` on STDOUT and still answers the following `(check-sat)` with a
# real verdict line, exiting non-zero. Measured on the pinned Z3 4.13.3
# (~/.local/bin/z3), the transcript below is the verbatim stdout of
#   (declare-fun calcDynamicTimeoutCore () (_ BitVec 32))
#   (assert (= calcDynamicTimeoutCore elapsedTicks))
#   (check-sat)
# run as `z3 -smt2 <file>` from /tmp: exit code 1, stderr empty. The
# pre-fix classifier skipped the `(error …)` line and minted `sosSat` from
# the trailing bare token — an internal tool failure recorded as a proof
# obligation answer.
#
# The fakes below are deterministic sh scripts emitting those measured
# transcripts, so these assertions do not depend on a solver being present.
# ---------------------------------------------------------------------------

proc writeFakeZ3(name: string; body: string): string =
  let path = getTempDir() / ("axiom_fake_z3_" & $getCurrentProcessId() & "_" & name & ".sh")
  writeFile(path, "#!/bin/sh\n" & body)
  setFilePermissions(path, {fpUserRead, fpUserWrite, fpUserExec})
  path

let incidentStreamZ3 = writeFakeZ3("errthensat",
  "cat > /dev/null\n" &
  "printf '(error \"line 3 column 34: unknown constant elapsedTicks\")\\nsat\\n'\n" &
  "exit 1\n")
let cleanSatZ3 = writeFakeZ3("cleansat",
  "cat > /dev/null\n" &
  "printf 'sat\\n(\\n  (define-fun x () (_ BitVec 8)\\n    #xfa)\\n)\\n'\n" &
  "exit 0\n")
let cleanUnsatZ3 = writeFakeZ3("cleanunsat",
  "cat > /dev/null\n" &
  "printf 'unsat\\n(error \"line 6 column 10: model is not available\")\\n'\n" &
  "exit 1\n")
let unsupportedZ3 = writeFakeZ3("unsupported",
  "cat > /dev/null\n" &
  "printf 'unsupported\\n'\n" &
  "exit 0\n")
let verdictThenErrorZ3 = writeFakeZ3("verdictthenerror",
  "cat > /dev/null\n" &
  "printf 'sat\\n(error \"line 5 column 18: Invalid function declaration: unknown sort '\\''NopeSort'\\''\")\\n'\n" &
  "exit 1\n")

suite "solver_adapter.solve — error-bearing stream gate (DECISION-0824/0825/0826)":

  test "error-then-sat stream classifies UNKNOWN, never SAT":
    let outcome = newSolverAdapter(z3Path = incidentStreamZ3, timeoutMs = 5000).solve(
      "(check-sat)")
    check outcome.status == sosUnknown
    check outcome.status != sosSat
    check outcome.modelBindings.len == 0

  test "clean sat stream classifies SAT with the model carried (regression)":
    let outcome = newSolverAdapter(z3Path = cleanSatZ3, timeoutMs = 5000).solve(
      "(check-sat)")
    check outcome.status == sosSat
    check outcome.modelBindings.len > 0

  test "clean unsat stream still classifies UNSAT — the (get-model) refusal after unsat is byte-identical":
    ## Real measured shape: solve() appends `(get-model)`, Z3 answers
    ## `unsat`, refuses the `(get-model)` with `(error "model is not
    ## available")` and exits 1 — the UNSAT mint is deliberately NOT gated,
    ## so this transcript stays sosUnsat.
    let outcome = newSolverAdapter(z3Path = cleanUnsatZ3, timeoutMs = 5000).solve(
      "(check-sat)")
    check outcome.status == sosUnsat

  test "unsupported-token stream classifies UNKNOWN":
    let outcome = newSolverAdapter(z3Path = unsupportedZ3, timeoutMs = 5000).solve(
      "(check-sat)")
    check outcome.status == sosUnknown
    check outcome.status != sosSat

  test "verdict-then-error with a non-zero exit classifies UNKNOWN (DECISION-0826)":
    let outcome = newSolverAdapter(z3Path = verdictThenErrorZ3, timeoutMs = 5000).solve(
      "(check-sat)")
    check outcome.status == sosUnknown

suite "P4 cvConfirmed eligibility — error-bearing model script":

  test "error-then-sat discharge is never cvConfirmed-eligible":
    ## The exact P4 promotion chain: validateCounterexample discharges its
    ## witness script through solver_adapter.solve. Under the pre-fix
    ## classifier the fake's `(error …)` + `sat` stream was `sosSat` →
    ## parseSolverStatus → solverSat → cvConfirmed → vsDisproved: a false
    ## disproof minted from a tool failure. The gate maps the same stream to
    ## sosUnknown → solverUnknown → cvUnresolved (DECISION-0311 case arm),
    ## and toCandidateEvidence yields the empty C20 candidate that
    ## validateCounterexample fails closed on first.
    let model = makeModel()
    let ce = candidateEvidence(cesSolver, @[("state", "(>= i 0)")],
      provenance = "solver:sosSat", fingerprint = "",
      model = "(model (define-fun i () Int 5))")
    check not ce.isEmpty() and ce.model.len > 0  # the discharger IS reached
    let validator = newCounterexampleValidator(z3Path = incidentStreamZ3, timeoutMs = 5000)
    let verdict = validator.validateCounterexample(model, ce, incidentStreamZ3, 5000)
    check verdict == cvUnresolved
    # Evidence-level eligibility: the same outcome through the S4 capture
    # boundary carries no model and no invariants — the empty candidate that
    # can never promote.
    let outcome = newSolverAdapter(z3Path = incidentStreamZ3, timeoutMs = 5000).solve(
      "(check-sat)")
    check outcome.status == sosUnknown
    check toCandidateEvidence(outcome).isEmpty()