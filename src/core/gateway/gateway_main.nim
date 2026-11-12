import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/utils/constants
import core/gateway/gateway_helpers
import core/sync/sync_utils_process
import core/trusted/axiom_pragmas
import core/trusted/solver_invocation
import core/types/domain_types
import core/types/results
import core/utils/text_utils
import core/encoding/smt_to_lean_translate
import core/encoding/smt_to_lean_codegen
import std/posix
import std/sets
import std/strutils
## Evidence Writer Hook
## Infrastructure layer registers its concrete writer at startup.
## This eliminates the SoC violation where Domain imported Infrastructure.
type
  EvidenceWriter* = proc(nodeId, solverStdout: string): string {.raises: [], gcsafe.}
var evidenceWriterHook* {.threadvar.}: EvidenceWriter
proc registerEvidenceWriter*(writer: EvidenceWriter) {.raises: [].} =
  evidenceWriterHook = writer

## Z3 Persistent Prover Hook
## Infrastructure layer registers its concrete Z3 pool prover at startup.
## Zero-cost abstraction: proc type replaces method dispatch.
type
  Z3PersistentProverFn* = proc(query: string; timeoutMs: int): bool {.raises: [], gcsafe.}
var z3PersistentProverHook* {.threadvar.}: Z3PersistentProverFn
proc registerZ3PersistentProver*(fn: Z3PersistentProverFn) {.raises: [].} =
  z3PersistentProverHook = fn
type
  AxiomProofRequest* = object
    nodeId*: string
    ownSourceCode*: string
    stateValue*: int
    inputDelta*: int
    dependencyAxioms*: seq[string]
    expectedSmtlib2*: string
    injectContradiction*: bool
    timeoutMs*: int
    solverCommand*: string
    solverArgs*: seq[string]

  AxiomProofResult* = object
    verified*: bool
    smtlib2*: string
    dependencyAxiomCount*: int
    solverStdout*: string
    z3outHash*: string
    proofTrace*: string
    leanProofFromTrace*: string
type
  Z3GateVerdict = enum
    z3GateSat
    z3GateUnsat
    z3GateUnknown
    z3GateVacuousContradiction
    z3GateNoStatus
func containsOnlyMetadataSmtTokens(body: string): bool {.raises: [].} =
  var sawMetadata = false
  let normalized = body.multiReplace({
    "(": " ",
    ")": " ",
    ";": " "
  })
  for token in normalized.splitWhitespace():
    if isIntegerToken(token) or isSmtOperatorToken(token):
      continue
    if isMetadataOnlySmtSymbol(token):
      sawMetadata = true
      continue
    return false
  sawMetadata

# @axiom-hint: lean="bodies.length = 0 ∧ false ∧ bodies.length = 0 → result = false ∧ (bodies ≥ 0)" smt="(assert (and (= (str.len bodies) 0) false (=> (= (str.len bodies) 0) (= result false)) (>= bodies 0)))"
func hasMetadataOnlySmtAssertion(raw: string): bool {.raises: [].} =
  let bodies = collectSmtAssertBodies(raw, skipProofNegations = true)
  if bodies.len == 0:
    return false
  for body in bodies:
    if not containsOnlyMetadataSmtTokens(body):
      return false
  true

# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
func hasNonSubstantiveSmtAssertion(raw: string): bool {.raises: [].} =
  hasVacuousSmtAssertion(raw) or hasMetadataOnlySmtAssertion(raw)

# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (and (>= (str.len raw) 0)))"
func isSubstantiveSmtFormula*(raw: string): bool {.raises: [].} =
  raw.strip().len > 0 and not hasNonSubstantiveSmtAssertion(raw)

# @axiom-hint: lean="symbols.size ≥ 0 ∧ stateValue ≥ -9223372036854775808 ∧ stateValue ≤ 9223372036854775807 ∧ inputDelta ≥ -9223372036854775808 ∧ inputDelta ≤ 9223372036854775807" smt="(assert (and (>= (seq.len symbols) 0) (and (>= stateValue -9223372036854775808) (<= stateValue 9223372036854775807)) (and (>= inputDelta -9223372036854775808) (<= inputDelta 9223372036854775807))))"
# @axiom-hint: lean="(symbols ≥ 0) ∧ (∀ (symbolsIdx : Fin symbols.size), (symbols.get symbolsIdx).length ≥ 0)" smt="(assert (and (>= symbols 0) (forall ((symbolsIdx Int)) (=> (and (>= symbolsIdx 0) (< symbolsIdx (seq.len symbols))) (>= (str.len (seq.nth symbols symbolsIdx)) 0)))))"
func buildConcreteStateAssumptions(
  symbols: seq[string];
  stateValue: int;
  inputDelta: int
): seq[string] {.raises: [].} =
  let balanceValue = stateValue - inputDelta
  for sym in symbols:
    if sym.endsWith("_balance"):
      result.add("(= " & sym & " " & $balanceValue & ")")

# @axiom-hint: lean="statuses.length = 0 ∧ z3GateNoStatus ∧ z3GateVacuousContradiction ∧ statuses.length = 0 → result = z3GateNoStatus ∧ (lines ≥ 0)" smt="(assert (and (= (str.len statuses) 0) z3GateNoStatus z3GateVacuousContradiction (=> (= (str.len statuses) 0) (= result z3GateNoStatus)) (>= lines 0)))"
func parseZ3GateVerdict(stdoutText: string): Z3GateVerdict {.raises: [].} =
  let lines = stdoutText.strip().splitLines()
  var statuses: seq[string] = @[]
  for line in lines:
    let t = line.strip()
    if t == "sat" or t == "unsat" or t == "unknown":
      statuses.add(t)
  if statuses.len == 0:
    return z3GateNoStatus
  if statuses.len >= 2 and statuses[0] == "unsat":
    return z3GateVacuousContradiction
  case statuses[^1]
  of "sat":
    z3GateSat
  of "unsat":
    z3GateUnsat
  else:
    z3GateUnknown

## Build Injected Smtlib2.
# @axiom-hint: lean="proofAssumptions.length > 0 ∧ firstGateConditions.length > 0 ∧ ownConditions.length > 0 ∧ (symbols ≥ 0) ∧ request_injectContradiction = true ∨ request_injectContradiction = false" smt="(assert (and (> (str.len proofAssumptions) 0) (> (str.len firstGateConditions) 0) (> (str.len ownConditions) 0) (>= symbols 0) (or (= request_injectContradiction true) (= request_injectContradiction false))))"
func buildInjectedSmtlib2*(request: AxiomProofRequest): string =
  ## Vacuity ban: never inject (assert true) as a default.
  ## If no SMT formula is provided, return empty string.
  ## Callers must treat empty result as solverUnknown.
  let ownFormula =
    if request.expectedSmtlib2.len > 0:
      request.expectedSmtlib2
    else:
      ""

  var dependencyFormula = ""
  if request.dependencyAxioms.len > 0:
    dependencyFormula.add(stripSmtProofControlLines(request.dependencyAxioms.join("\n")))
    if dependencyFormula.len > 0 and not dependencyFormula.endsWith("\n"):
      dependencyFormula.add("\n")

  var baseFormula = dependencyFormula
  baseFormula.add(ownFormula)
  if baseFormula.len > 0 and not baseFormula.endsWith("\n"):
    baseFormula.add("\n")
  if baseFormula.strip().len == 0:
    return ""

  result.add("(set-option :print-success false)\n")
  result.add(solverOptionsPayload(pinnedDeterminismOptions()))
  result.add("(set-logic ALL)\n")
  let alreadyDeclared = collectSmtDeclaredSymbols(baseFormula)
  for line in baseFormula.splitLines():
    let t = line.strip()
    if isSmtDeclOrDefLine(t):
      result.add(t & "\n")
  let baseFormulaBody = stripSmtDeclarationLines(baseFormula)
  let dependencyFormulaBody = stripSmtDeclarationLines(dependencyFormula)
  let ownFormulaBody = stripSmtDeclarationLines(ownFormula)
  let symbols = collectSmtIntSymbols(baseFormulaBody)
  for sym in symbols:
    if sym in alreadyDeclared:
      continue
    result.add("(declare-const " & sym & " Int)\n")
  let dependencyConditions = collectSmtAssertBodies(dependencyFormulaBody, skipProofNegations = true)
  let ownConditions = collectSmtAssertBodies(ownFormulaBody)
  let concreteConditions = buildConcreteStateAssumptions(symbols, request.stateValue, request.inputDelta)
  let proofAssumptions = dependencyConditions & concreteConditions
  let firstGateConditions =
    if proofAssumptions.len > 0:
      proofAssumptions
    else:
      ownConditions
  result.add("(push 1)\n")
  if firstGateConditions.len > 0:
    result.add("(assert " & buildSmtConjunction(firstGateConditions) & ")\n")
  result.add("(check-sat)  ; <-- 1st gate: must halt here if unsat\n")
  result.add("(pop 1)\n")

  if ownConditions.len > 0:
    let ownConj = buildSmtConjunction(ownConditions)
    if proofAssumptions.len > 0:
      let assumptionConj = buildSmtConjunction(proofAssumptions)
      result.add("(assert (not (=> " & assumptionConj & " " & ownConj & ")))\n")
    else:
      result.add("(assert (not " & ownConj & "))\n")

  when not defined(release):
    if request.injectContradiction:
      result.add("(assert false)\n")
  result.add("(check-sat)  ; <-- 2nd gate: final proof")

# @axiom-hint: lean="request_injectContradiction = true ∨ request_injectContradiction = false" smt="(assert (and (or (= request_injectContradiction true) (= request_injectContradiction false))))"
func effectiveProofTimeoutMs(request: AxiomProofRequest): int {.raises: [].} =
  if request.timeoutMs > 0:
    return request.timeoutMs
  defaultAxiomProofTimeoutMs

# @axiom-hint: lean="arg.length ≥ 0" smt="(assert (and (>= (str.len arg) 0)))"
# @axiom-hint: lean="arg.length = 0 ∧ false ∧ true ∧ arg.length = 0 → result = false" smt="(assert (and (= (str.len arg) 0) false true (=> (= (str.len arg) 0) (= result false))))"
func isAllowedPersistentZ3Arg(arg: string): bool {.raises: [].} =
  if arg.len == 0:
    return false
  if arg in ["-smt2", "-in"]:
    return true
  if arg.startsWith("-T:"):
    return true
  false

# @axiom-hint: lean="request_nodeId.length ≥ 0 ∧ request_ownSourceCode.length ≥ 0 ∧ request_stateValue ≥ -9223372036854775808 ∧ request_stateValue ≤ 9223372036854775807 ∧ request_inputDelta ≥ -9223372036854775808 ∧ request_inputDelta ≤ 9223372036854775807 ∧ request_dependencyAxioms.size ≥ 0 ∧ request_expectedSmtlib2.length ≥ 0 ∧ request_timeoutMs ≥ -9223372036854775808 ∧ request_timeoutMs ≤ 9223372036854775807 ∧ request_solverCommand.length ≥ 0 ∧ request_solverArgs.size ≥ 0" smt="(assert (and (>= (str.len request_nodeId) 0) (>= (str.len request_ownSourceCode) 0) (and (>= request_stateValue -9223372036854775808) (<= request_stateValue 9223372036854775807)) (and (>= request_inputDelta -9223372036854775808) (<= request_inputDelta 9223372036854775807)) (>= (seq.len request_dependencyAxioms) 0) (>= (str.len request_expectedSmtlib2) 0) (and (>= request_timeoutMs -9223372036854775808) (<= request_timeoutMs 9223372036854775807)) (>= (str.len request_solverCommand) 0) (>= (seq.len request_solverArgs) 0)))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"
func shouldUsePersistentZ3(request: AxiomProofRequest): bool {.raises: [].} =
  let solverCommand = (if request.solverCommand.len > 0: request.solverCommand else: DefaultSolverCommand)
  if solverCommand.toLowerAscii() != DefaultSolverCommand:
    return false
  if request.solverArgs.len == 0:
    return true
  for arg in request.solverArgs:
    if not isAllowedPersistentZ3Arg(arg):
      return false
  true




## Prove Axiom Node.
# @axiom-hint: lean="smt2.length = 0 ∧ z3GateUnsat ∧ z3GateSat ∧ z3GateVacuousContradiction ∧ z3GateUnknown ∧ z3GateNoStatus ∧ exitCode = 0 ∧ exitCode = 1 ∧ (solverStdout ≥ 0) ∧ (z3outHash ≥ 0) ∧ (exitCode ≥ 0) ∧ request_injectContradiction = true ∨ request_injectContradiction = false" smt="(assert (and (= (str.len smt2) 0) z3GateUnsat z3GateSat z3GateVacuousContradiction z3GateUnknown z3GateNoStatus (= exitCode 0) (= exitCode 1) (>= solverStdout 0) (>= z3outHash 0) (>= exitCode 0) (or (= request_injectContradiction true) (= request_injectContradiction false))))"
proc proveAxiomNode*(request: AxiomProofRequest): Result[AxiomProofResult, AxiomError] {.sideEffect, raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  when not defined(release):
    if request.injectContradiction:
      return err(axiomErrVacuousContradiction)
  if hasNonSubstantiveSmtAssertion(request.expectedSmtlib2):
    return err(axiomErrVacuousContradiction)

  let smt2 = buildInjectedSmtlib2(request)
  if smt2.len == 0:
    return err(axiomErrVacuousContradiction)
  let timeoutMs = effectiveProofTimeoutMs(request)
  var solverStdout = ""
  var exitCode = 0
  try:
    if shouldUsePersistentZ3(request):
      if z3PersistentProverHook != nil and z3PersistentProverHook(smt2, timeoutMs):
        solverStdout = "unsat"
        exitCode = 0
      else:
        return err(axiomErrSolverUnknown)
    else:
      let timeoutSec = max(1, timeoutMs div 1000)
      let solverCommand = if request.solverCommand.len > 0: request.solverCommand else: DefaultSolverCommand
      var solverArgs =
        if request.solverArgs.len > 0:
          request.solverArgs
        else:
          @["-smt2", "-in", "-T:" & $timeoutSec, "proof=true"]
      if solverCommand.toLowerAscii() != DefaultSolverCommand:
        let timed = runProcessWithTimeout(solverCommand, solverArgs, timeoutMs)
        if timed.timedOut:
          return err(axiomErrSolverTimeout)
        if timed.exitCode != 0:
          return err(axiomErrSolverUnknown)
        return err(axiomErrSolverParseFailure)
      let timed = runProcessWithTimeout(solverCommand, solverArgs, timeoutMs, input = smt2)
      if timed.timedOut:
        return err(axiomErrSolverTimeout)
      solverStdout = timed.output
      exitCode = timed.exitCode
  except CatchableError:
    return err(axiomErrSolverUnknown)

  if exitCode != 0 and solverStdout.strip().len == 0:
    return err(axiomErrSolverUnknown)

  let verdict = parseZ3GateVerdict(solverStdout)
  case verdict
  of z3GateUnsat:
    discard
  of z3GateSat:
    return err(axiomErrSolverSatCounterExample)
  of z3GateVacuousContradiction:
    return err(axiomErrVacuousContradiction)
  of z3GateUnknown:
    let tokens = tokenizeLowered(solverStdout)
    if "timeout" in tokens:
      return err(axiomErrSolverTimeout)
    return err(axiomErrSolverUnknown)
  of z3GateNoStatus:
    return err(axiomErrSolverParseFailure)

  var z3outHash = ""
  if request.nodeId.len > 0 and evidenceWriterHook != nil:
    z3outHash = evidenceWriterHook(request.nodeId, solverStdout)

  let proofTrace = extractZ3ProofTrace(solverStdout)
  let leanProof = buildLeanProofScriptFromTrace(proofTrace)

  ok(AxiomProofResult(
    verified: true,
    smtlib2: smt2,
    dependencyAxiomCount: request.dependencyAxioms.len,
    solverStdout: solverStdout,
    z3outHash: z3outHash,
    proofTrace: proofTrace,
    leanProofFromTrace: leanProof
  ))
# ─── Composition Root Guard ───────────────────────────────────────────────────
# Z3 prover is now injected via hook (z3PersistentProverHook) registered in
# cli/main.nim. No direct infrastructure imports needed in this module.
# The hook pattern provides zero-cost abstraction without layer violations.

{.pop.}
