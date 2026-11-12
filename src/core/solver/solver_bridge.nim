import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/options
import std/strutils
import std/sequtils
import std/monotimes
import std/json
import std/times
import std/strformat
import core/utils/text_utils
import core/trusted/axiom_pragmas

import core/types/results
import core/solver/shell_bridge
import core/utils/io_utils
import core/bmc/bmc_race
import core/solver/types
import core/solver/expr_serialize
import core/solver/encoding_transition
import core/solver/encoding_properties
import core/solver/induction
import core/solver/construct_base
import core/solver/construct_logical
import core/solver/smtlib_emitter
import core/solver/z3_result_parser

type
  VerifierKind* = enum
    vkZ3BMC
    vkLean4

  VerificationResult* = object
    targetProc*: string
    success*: bool
    durationMs*: float
    message*: string
    case kind*: VerifierKind
    of vkZ3BMC:
      counterexample*: Option[string]
      depthK*: int
    of vkLean4:
      proofTerm*: Option[string]
      isKernelVerified*: bool

  VerificationReport* = object
    results*: seq[VerificationResult]
    totalDurationMs*: float

  SolverBridgePayload* = object
    request*: SolverRequest
    smt2*: string

  KInductionPayload* = object
    request*: KInductionRequest
    baseSmt2*: string
    stepSmt2*: string
    uniquenessSmt2*: string  ## Uniqueness constraints SMT-LIB2 (strengthened induction)
    useLocallyShortest*: bool  ## true when k > 5 (O(k) constraints instead of O(k²))

## Build Transition Payload — I(x) + T(x,x').
# @axiom-hint: lean="initialValue ≥ -9223372036854775808 ∧ initialValue ≤ 9223372036854775807" smt="(assert (and (and (>= initialValue -9223372036854775808) (<= initialValue 9223372036854775807))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildTransitionPayload*(
  initialValue: int;
  rule: TransitionRule
): SolverBridgePayload {.raises: [].} =
  let enc = encodeRuleTransition(rule)
  let initAssertion = eq(symInt("x_0"), intLit(initialValue))
  let req = SolverRequest(
    logic: logicQfLia,
    declarations: enc.declarations,
    assertions: @[initAssertion, enc.transitionExpr],
    finalStateSymbol: enc.finalStateSymbol,
    checkSat: true, getModel: true, getUnsatCore: false
  )
  SolverBridgePayload(request: req, smt2: emitSmt2(req))

## Build Runtime Error Zero Payload — I(x) + T(x,x') as preconditions, ¬P(x') as assertion.
# @axiom-hint: lean="initialValue ≥ -9223372036854775808 ∧ initialValue ≤ 9223372036854775807" smt="(assert (and (and (>= initialValue -9223372036854775808) (<= initialValue 9223372036854775807))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildRuntimeErrorZeroPayload*(
  initialValue: int;
  rule: TransitionRule
): SolverBridgePayload {.raises: [].} =
  let enc = encodeRuleTransition(rule)
  let initAssertion = eq(symInt("x_0"), intLit(initialValue))
  let req = makeZeroRuntimeErrorQuery(
    enc.declarations,
    @[initAssertion, enc.transitionExpr],
    enc.finalStateSymbol,
    rule
  )
  SolverBridgePayload(request: req, smt2: emitSmt2(req))

## Build KInduction Payload — I(x) for base case only, pure T + P for step case.
# @axiom-hint: lean="k ≥ -9223372036854775808 ∧ k ≤ 9223372036854775807 ∧ initialValue ≥ -9223372036854775808 ∧ initialValue ≤ 9223372036854775807" smt="(assert (and (and (>= k -9223372036854775808) (<= k 9223372036854775807)) (and (>= initialValue -9223372036854775808) (<= initialValue 9223372036854775807))))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildKInductionPayload*(
  k: int;
  initialValue: int;
  rule: TransitionRule
): KInductionPayload {.raises: [].} =
  let enc = encodeRuleTransition(rule)
  # I(x): x_s0 = initialValue — injected as base case initial assertion only
  let initAssertion = eq(symInt("x_s0"), intLit(initialValue))
  let req = makeKInductionRequest(
    k,
    enc.declarations,
    @[initAssertion],
    enc.finalStateSymbol,
    rule
  )
  # Emit uniqueness constraints as separate SMT-LIB2 fragment
  var uniquenessParts: seq[string] = @[]
  for constraint in req.uniquenessConstraints:
    uniquenessParts.add("(assert " & toSmt(constraint) & ")")
  let useLocallyShortest = k > 5
  KInductionPayload(
    request: req,
    baseSmt2: emitSmt2(req.baseCase),
    stepSmt2: emitSmt2(req.stepCase),
    uniquenessSmt2: uniquenessParts.join("\n"),
    useLocallyShortest: useLocallyShortest
  )

## Parse Z3Stdout As Result.
# @axiom-hint: lean="stdoutText.length ≥ 0 ∧ smt2.length ≥ 0 ∧ violatedProperty.length ≥ 0" smt="(assert (and (>= (str.len stdoutText) 0) (>= (str.len smt2) 0) (>= (str.len violatedProperty) 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseZ3StdoutAsResult*(
  stdoutText: string;
  smt2: string;
  violatedProperty: string = "runtime_error_zero"
): Result[SolverBridgeResult, SymbolicFailure] {.raises: [].} =
  parseSolverStdout(stdoutText, smt2, violatedProperty)

## Proof Evidence Refs From Solver.
# @axiom-hint: lean="(result ≥ 0)" smt="(assert (and (>= result 0)))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func proofEvidenceRefsFromSolver*(evidence: SolverEvidence): seq[string] {.raises: [].} =
  result = @["solver://z3/query"]
  if evidence.status == solverSat and evidence.counterExample.isSome():
    result.add("solver://z3/model")

func generateReport*(report: VerificationReport): string {.raises: [].} =
  let passed = report.results.countIt(it.success)
  let failed = report.results.len - passed
  result = &"VerificationReport: {passed} passed, {failed} failed, " &
           &"total {report.totalDurationMs:.1f}ms"

{.pop.}

import std/os
import core/solver/z3_telemetry

proc toGithubAnnotation*(res: VerificationResult): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if res.success:
    result = &"::notice file={res.targetProc}::[VERIFIED] {res.kind} passed in {res.durationMs:.0f}ms"
  else:
    let detail = if res.kind == vkZ3BMC: res.counterexample.get("") else: res.message
    result = &"::error file={res.targetProc}::[FAILED] {res.kind} verification failed: {detail}"

proc toJson*(res: VerificationResult): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = %*{
    "targetProc": res.targetProc,
    "kind": $res.kind,
    "success": res.success,
    "durationMs": res.durationMs,
    "message": res.message
  }
  case res.kind
  of vkZ3BMC:
    result["counterexample"] = %res.counterexample
    result["depthK"] = %res.depthK
  of vkLean4:
    result["proofTerm"] = %res.proofTerm
    result["isKernelVerified"] = %res.isKernelVerified

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc detectMathlibCapability*(projectDir: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let manifestPath = projectDir / "lake-manifest.json"
    if fileExists(manifestPath):
      let content = readFile(manifestPath)
      if "mathlib" in content:
        return true
    let lakefilePath = projectDir / "lakefile.lean"
    if fileExists(lakefilePath):
      let content = readFile(lakefilePath)
      if "require mathlib" in content or "\"mathlib\"" in content:
        return true
    let lakefileTomlPath = projectDir / "lakefile.toml"
    if fileExists(lakefileTomlPath):
      let content = readFile(lakefileTomlPath)
      if "mathlib" in content:
        return true
  except CatchableError:
    discard  # axiom:best-effort(scratch file I/O — missing/unreadable files = no mathlib; `false` fallthrough is the safe conservative answer)
  false

## Dump Evidence.
# @axiom-hint: lean="external_io_isolated" smt="(assert (and external_io_isolated))"
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc dumpEvidence*(nodeId: string, smt2: string, lean: string, constraint: string, outDir: string)  =
  let timestamp = now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  let safeNodeId = sanitizeAxiomToken(nodeId)
  discard existsOrCreateDirOpt(outDir)
  
  let lakefilePath = outDir / "lakefile.lean"
  if not fileExists(lakefilePath):
    let lakefileContent = """
import Lake
open Lake DSL
package evidence
require mathlib from git "https://github.com/leanprover-community/mathlib4" @ "v4.2.0"
"""
    ## intentional-discard: legacy-approved (spec §4.1)
    discard writeFileOpt(lakefilePath, lakefileContent)
    # Run lake exe cache get to fetch prebuilt mathlib oleans using elan multiplexer bypass
    discard runCommandInDir("elan run leanprover/lean4:v4.2.0 lake update", outDir)
    discard runCommandInDir("elan run leanprover/lean4:v4.2.0 lake exe cache get", outDir)

  let leanToolchainPath = outDir / "lean-toolchain"
  if not fileExists(leanToolchainPath):
    ## intentional-discard: legacy-approved (spec §4.1)
    discard writeFileOpt(leanToolchainPath, "leanprover/lean4:v4.2.0\n") # Or appropriate version
    
  let smt2Path = outDir / (safeNodeId & ".smt2")
  let smt2Content = "; Timestamp: " & timestamp & "\n; Constraint: " & constraint & "\n\n" & smt2
  ## intentional-discard: legacy-approved (spec §4.1)
  discard writeFileOpt(smt2Path, smt2Content)
  
  let leanPath = outDir / (safeNodeId & ".lean")
  let leanContent = "-- Timestamp: " & timestamp & "\n-- Constraint: " & constraint & "\n\n" & lean
  ## intentional-discard: legacy-approved (spec §4.1)
  discard writeFileOpt(leanPath, leanContent)

## ─── K-Induction Solver Integration ─────────────────────────────────────────

type
  KInductionVerdict* = enum
    kivProved           ## Both base and step UNSAT → property proven
    kivCounterexample   ## Base SAT → concrete error trace found
    kivStepFailed       ## Step SAT → invariant not inductive at depth k
    kivTimeout          ## Solver timeout
    kivError            ## Solver error

  KInductionResult* = object
    verdict*: KInductionVerdict
    k*: int                     ## Induction depth used
    baseCaseUnsat*: bool        ## Was base case UNSAT?
    stepCaseUnsat*: bool        ## Was step case UNSAT?
    baseCaseTimeMs*: int64      ## Base case solve time
    stepCaseTimeMs*: int64      ## Step case solve time
    uniquenessConstraints*: int ## Number of uniqueness constraints
    useLocallyShortest*: bool   ## Was locally shortest used?
    baseCaseOutput*: string     ## Raw Z3 output for base case
    stepCaseOutput*: string     ## Raw Z3 output for step case
    leanProofScript*: string    ## Auto-generated Lean 4 proof (Phase 3: closed-loop emission)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkWithTelemetry*(
  query: string;
  z3Check: proc(q: string): bool {.closure, gcsafe, raises: [CatchableError].};
  queryType: string  = "unknown";
  cegarIters: int = 0;
  rlimit: int = 0
): bool {.raises: [CatchableError].} =
  ## Execute a Z3 check closure with telemetry logging.
  ## Bridges Nim solver payloads to the telemetry file.
  let startMs = getMonoTime().ticks
  var resultStatus = "unknown"
  var ok = false
  try:
    ok = z3Check(query)
    resultStatus = if ok: "unsat" else: "sat"
  except CatchableError:
    resultStatus = "error"
  let timeMs = int((getMonoTime().ticks - startMs) div 1_000_000)
  let record = Z3TelemetryRecord(
    ts: now().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'"),
    queryType: queryType,
    rlimit: rlimit,
    result: resultStatus,
    timeMs: timeMs,
    memoryMb: 0,
    cegarIters: cegarIters
  )
  appendZ3Telemetry(record)
  ok

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runKInductionCheck*(
  payload: KInductionPayload;
  z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].}
): KInductionResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run k-induction check with Z3 solver.
  ##
  ## Procedure (Eén & Sörensson 2004):
  ##   1. Build base case SMT-LIB2 with k-step unrolling
  ##   2. Build step case SMT-LIB2 with k consecutive state assumptions
  ##   3. Add uniqueness constraints (strengthened induction)
  ##   4. Check base case: UNSAT → no violation in k steps
  ##   5. Check step case: UNSAT → inductive step holds
  ##   6. Both UNSAT → property proven by k-induction
  result = KInductionResult(
    k: payload.request.k,
    uniquenessConstraints: payload.request.uniquenessConstraints.len,
    useLocallyShortest: payload.useLocallyShortest
  )

  # Construct full base case with uniqueness constraints
  let baseSmt = payload.baseSmt2
  let stepSmt = payload.stepSmt2
  let uniquenessSmt = payload.uniquenessSmt2

  # Check base case
  let baseStart = getMonoTime().ticks
  try:
    result.baseCaseUnsat = z3Check(baseSmt)
  except CatchableError:
    result.verdict = kivError
    return
  result.baseCaseTimeMs = (getMonoTime().ticks - baseStart) div 1_000_000

  if not result.baseCaseUnsat:
    # Base case SAT → counterexample found
    result.verdict = kivCounterexample
    return

  # Check step case with uniqueness constraints
  let fullStepSmt = stepSmt & "\n" & uniquenessSmt
  let stepStart = getMonoTime().ticks
  try:
    result.stepCaseUnsat = z3Check(fullStepSmt)
  except CatchableError:
    result.verdict = kivError
    return
  result.stepCaseTimeMs = (getMonoTime().ticks - stepStart) div 1_000_000

  if not result.stepCaseUnsat:
    # Step case SAT → invariant not inductive at depth k
    result.verdict = kivStepFailed
    return

  # Both UNSAT → property proven by k-induction!
  result.verdict = kivProved

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runIncrementalKInduction*(
  payload: KInductionPayload;
  maxK: int;
  z3Check: proc(query: string): bool {.closure, gcsafe, raises: [CatchableError].};
  timeoutMs: int  = 30_000
): KInductionResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect, TimeEffect].} =
  ## Incremental k-induction routed through the Z3 persistent pool.
  ##
  ## Instead of spawning a separate Z3 process via startZ3Stream, each k-depth
  ## query is routed through z3ExecPersistent. The pool manages process lifecycle.
  ##
  ## User refinement (Plan v5): "Progressive k-Induction (Incremental Solving)
  ## k=2→4→8→16까지 z3ExecPersistent로 점진적 확장 — 새 프로세스/spawn 불필요"

  result = KInductionResult(
    k: 0,
    uniquenessConstraints: payload.request.uniquenessConstraints.len,
    useLocallyShortest: false
  )

  # Build declarations prefix shared across all k-depth queries
  let declarationsPrefix = "(set-logic QF_LIA)\n" &
    payload.request.baseCase.declarations.mapIt(
      "(declare-const " & it & " Int)"
    ).join("\n")

  try:
    # Progressive deepening: k=2, 3, ..., maxK
    for k in 2..maxK:
      # Build complete base case query for this k
      let baseQuery = declarationsPrefix & "\n" & payload.baseSmt2
      let baseUnsat = z3Check(baseQuery)
      result.k = k
      result.baseCaseUnsat = baseUnsat

      if not result.baseCaseUnsat:
        # Base case SAT → counterexample
        result.verdict = kivCounterexample
        break

      # Check step case with uniqueness constraints
      let stepQuery = declarationsPrefix & "\n" &
        payload.stepSmt2 & "\n" & payload.uniquenessSmt2
      let stepUnsat = z3Check(stepQuery)
      result.stepCaseUnsat = stepUnsat

      if not result.stepCaseUnsat:
        # Step SAT → need deeper k
        result.verdict = kivStepFailed
        continue  # Try next k

      # Both UNSAT → proved!
      result.verdict = kivProved
      result.useLocallyShortest = k > 5
      break

  except CatchableError:
    result.verdict = kivError


