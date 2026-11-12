import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import ../../core/trusted/axiom_pragmas
import core/gateway/gateway
import core/solver/types
import core/trusted/solver_invocation
import core/types/domain_types
import core/types/results
import core/utils/constants
import std/options
import std/strutils

## Project the lines that stand outside every s-expression.
##
## Only such a line can be a ⟨check_sat_response⟩. A bare `unsat` nested in an
## `(error …)` message, in an unsat core, or in a `(get-proof …)` payload is part
## of some other command's output; reading it as this invocation's answer is
## how a refused proof got recorded as a discharge.
func topLevelResponseLines(raw: string): string {.raises: [], axiom: ["(assert (and (>= depth 0) (= depth 0)))", "depth ≥ 0 ∧ (depth = 0)"].} =
  var depth = 0
  for line in raw.splitLines():
    if depth == 0:
      let trimmed = line.strip()
      if trimmed.len > 0:
        result.add trimmed
        result.add '\n'
    for ch in line:
      if ch == '(':
        inc depth
      elif ch == ')' and depth > 0:
        dec depth

func parseStatusLine*(raw: string): SolverStatus {.raises: [], axiom: ["(assert (and solverSat solverUnsat solverUnknown (=> (= depth 0) (not (= result solverVacuousContradiction)))))", "solverSat ∧ solverUnsat ∧ solverUnknown ∧ depth = 0 → result ≠ solverVacuousContradiction"].} =
  ## First response wins, exactly as `classifySolverVerdict` reads one
  ## invocation: a script issues one `(check-sat)`, so whatever the solver prints
  ## afterwards is elaboration of that answer, never a second answer to weigh.
  ## A stdout with no response is `solverUnknown` — silence is not a discharge
  ## (docs/spec/evidence_calculus.md I6).
  case classifySolverVerdict(topLevelResponseLines(raw))
  of svSat: solverSat
  of svUnsat: solverUnsat
  of svUnknown: solverUnknown

## Normalize Binding Value.
func normalizeBindingValue*(raw: string): string {.raises: [], axiom: ["(assert (and (= (str.len t) 0) (> firstSpace 0) t digits flat (=> (> firstSpace 0) (= result digits))))", "t.length = 0 ∧ firstSpace > 0 ∧ t ∧ digits ∧ flat ∧ firstSpace > 0 → result = digits"].} =
  let t = raw.strip()
  if t.len == 0:
    return ""
  if t == "true" or t == "false":
    return t
  if t.startsWith("(_ bv") and t.endsWith(")"):
    let remain = t["(_ bv".len ..< t.len - 1].strip()
    let firstSpace = remain.find(' ')
    if firstSpace > 0:
      let digits = remain[0 ..< firstSpace].strip()
      if digits.len > 0 and digits.allCharsInSet(Digits):
        return digits
  if t.startsWith("(- "):
    let noParens = t.replace("(", "").replace(")", "").strip()
    if noParens.len > 2 and noParens[0] == '-' and noParens[1] == ' ':
      let inner = noParens[2 .. ^1].strip()
      if inner.len > 0 and inner.allCharsInSet(Digits):
        return "-" & inner
  let flat = t.replace(")", "").strip()
  if flat.len > 1 and flat[0] == '-' and flat[1 .. ^1].allCharsInSet(Digits):
    return flat
  if flat.allCharsInSet(Digits):
    return flat
  t
func countChar(raw: string; needle: char): int {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated (= ch needle) (>= raw 0) (= ch needle)))", "ast_parse_failed_isolated ∧ ch = needle ∧ (raw ≥ 0) ∧ ch = needle"].} =
  for ch in raw:
    if ch == needle:
      inc result
func consumeLeadingExpr(raw: string): tuple[expr: string, remainder: string] {.raises: [], axiom: ["(assert (and (= (str.len trimmed) 0) (< firstSpace 0) (= depth 0) (< (+ idx 1) (str.len trimmed)) (>= trimmed 0)))", "trimmed.length = 0 ∧ firstSpace < 0 ∧ depth = 0 ∧ idx + 1 < trimmed.length ∧ (trimmed ≥ 0)"].} =
  let trimmed = raw.strip()
  if trimmed.len == 0:
    return ("", "")
  if trimmed[0] != '(':
    let firstSpace = trimmed.find({' ', '\t', '\n', '\r'})
    if firstSpace < 0:
      return (trimmed, "")
    return (trimmed[0 ..< firstSpace], trimmed[firstSpace .. ^1].strip())
  var depth = 0
  for idx, ch in trimmed:
    if ch == '(':
      inc depth
    elif ch == ')':
      dec depth
      if depth == 0:
        let remainder =
          if idx + 1 < trimmed.len: trimmed[idx + 1 .. ^1].strip()
          else: ""
        return (trimmed[0 .. idx], remainder)
  (trimmed, "")
func parseDefineFunBlock(rawBlock: string): tuple[name: string, value: string] {.raises: [], axiom: ["(assert (and (<= firstSpace 0) (>= cursor 0)))", "firstSpace ≤ 0 ∧ (cursor ≥ 0)"].} =
  let trimmed = rawBlock.strip()
  if not trimmed.startsWith("(define-fun "):
    return ("", "")
  let remain = trimmed["(define-fun ".len .. ^1].strip()
  let firstSpace = remain.find({' ', '\t', '\n', '\r'})
  if firstSpace <= 0:
    return ("", "")
  let name = remain[0 ..< firstSpace].strip()
  var cursor = remain[firstSpace .. ^1].strip()
  let argsExpr = consumeLeadingExpr(cursor)
  if argsExpr.expr.len == 0:
    return (name, "")
  cursor = argsExpr.remainder
  let returnTypeExpr = consumeLeadingExpr(cursor)
  if returnTypeExpr.expr.len == 0:
    return (name, "")
  cursor = returnTypeExpr.remainder
  if cursor.endsWith(")"):
    cursor = cursor[0 ..< cursor.len - 1].strip()
  (name, normalizeBindingValue(cursor))

## Parse Model Bindings.
func parseModelBindings*(raw: string): seq[SolverBinding] {.raises: [], axiom: ["(assert (and (> (str.len nextLine) 0) (< i (str.len lines)) (and (> balance 0) (< i (str.len lines))) (>= result 0) (and (>= i 0) (< i lines))))", "nextLine.length > 0 ∧ i < lines.length ∧ balance > 0 ∧ i < lines.length ∧ (result ≥ 0) ∧ ((i ≥ 0) ∧ (i < lines))"].} =
  result = @[]
  let lines = raw.splitLines()
  var i = 0
  while i < lines.len:
    let trimmed = lines[i].strip()
    if not trimmed.startsWith("(define-fun "):
      inc i
      continue
    var funBlock = trimmed
    var balance = countChar(trimmed, '(') - countChar(trimmed, ')')
    inc i
    while balance > 0 and i < lines.len:
      let nextLine = lines[i].strip()
      if nextLine.len > 0:
        funBlock.add("\n" & nextLine)
      else:
        funBlock.add("\n")
      balance += countChar(nextLine, '(') - countChar(nextLine, ')')
      inc i
    let parsed = parseDefineFunBlock(funBlock)
    if parsed.name.len > 0 and parsed.value.len > 0:
      result.add(SolverBinding(name: parsed.name, value: parsed.value))

## Parse Unsat Core.
func parseUnsatCore*(raw: string): seq[string] {.raises: [], axiom: ["(assert (and (= (str.len inner) 0) (> (str.len item) 0) (> (str.len result) 0) result (=> (> (str.len result) 0) (= result result))))", "inner.length = 0 ∧ item.length > 0 ∧ result.length > 0 ∧ result ∧ result.length > 0 → result = result"].} =
  let lines = raw.splitLines()
  for idx in countdown(lines.high, 0):
    let trimmed = lines[idx].strip()
    if trimmed.len < 2 or not trimmed.startsWith("(") or not trimmed.endsWith(")"):
      continue
    if trimmed.startsWith("(model") or trimmed.startsWith("(define-fun ") or trimmed.startsWith("(error"):
      continue
    let inner = trimmed[1 ..< trimmed.len - 1].strip()
    if inner.len == 0:
      return @[]
    for item in inner.splitWhitespace():
      if item.len > 0:
        result.add(item)
    if result.len > 0:
      return result

## Parse Z3 Proof Trace.
## Extracts the (proof ...) s-expression from Z3 output when :produce-proofs is enabled.
func parseZ3ProofTrace*(raw: string): string {.raises: [], axiom: ["(assert (and (>= (str.len raw) 0) (< proofStart 0) (> (str.len nextLine) 0) (and (> balance 0) (< i (str.len lines))) (= proofStart i) (>= lines 0) (>= proofStart 0)))", "raw.length ≥ 0 ∧ proofStart < 0 ∧ nextLine.length > 0 ∧ balance > 0 ∧ i < lines.length ∧ proofStart = i ∧ (lines ≥ 0) ∧ (proofStart ≥ 0)"].} =
  let lines = raw.splitLines()
  var proofStart = -1
  for i, line in lines:
    let trimmed = line.strip()
    if trimmed.startsWith("(proof"):
      proofStart = i
      break
  if proofStart < 0:
    return ""
  var proofBlock = lines[proofStart].strip()
  var balance = countChar(proofBlock, '(') - countChar(proofBlock, ')')
  var i = proofStart + 1
  while balance > 0 and i < lines.len:
    let nextLine = lines[i].strip()
    if nextLine.len > 0:
      proofBlock.add("\n" & nextLine)
    else:
      proofBlock.add("\n")
    balance += countChar(nextLine, '(') - countChar(nextLine, ')')
    inc i
  proofBlock

## Parse Solver Stdout.
func parseSolverStdout*(
  stdoutText: string;
  smt2: string;
  violatedProperty: string = "runtime_error_zero"
): Result[SolverBridgeResult, SymbolicFailure] {.raises: [], axiom: ["(assert (and (= status solverSat) (= status solverUnknown) (= status solverUnsat) (> (str.len unsatCore) 0) (>= evidence 0)))", "status = solverSat ∧ status = solverUnknown ∧ status = solverUnsat ∧ unsatCore.length > 0 ∧ (evidence ≥ 0)"].} =
  let status = parseStatusLine(stdoutText)
  if status == solverUnknown and stdoutText.strip().len == 0:
    return err(SymbolicFailure(
      code: axiomErrSolverParseFailure,
      message: "Solver output is empty",
      solverStatus: none(SolverStatus),
      counterExample: none(SolverCounterExample),
      smt2: some(smt2)
    ))
  var evidence = SolverEvidence(
    solverName: DefaultSolverCommand,
    logic: logicQfLia,
    status: status,
    queryHash: "",
    smt2: smt2,
    modelText: stdoutText,
    unsatCoreText: "",
    counterExample: none(SolverCounterExample)
  )

  if status == solverSat:
    let bindings = parseModelBindings(stdoutText)
    evidence.counterExample = some(SolverCounterExample(
      violatedProperty: violatedProperty,
      trace: @[],
      bindings: bindings
    ))
    return err(SymbolicFailure(
      code: axiomErrSolverSatCounterExample,
      message: "Counter-example exists",
      solverStatus: some(status),
      counterExample: evidence.counterExample,
      smt2: some(smt2)
    ))

  if status == solverUnknown:
    return err(SymbolicFailure(
      code: axiomErrSolverUnknown,
      message: "Solver could not reach a conclusion",
      solverStatus: some(status),
      counterExample: none(SolverCounterExample),
      smt2: some(smt2)
    ))

  if status == solverUnsat:
    let unsatCore = parseUnsatCore(stdoutText)
    evidence.unsatCoreText =
      if unsatCore.len > 0:
        "(" & unsatCore.join(" ") & ")"
      else:
        ""
    evidence.unsatCoreLabels = unsatCore
    # Extract proof trace when available (produce-proofs enabled)
    evidence.proofTrace = parseZ3ProofTrace(stdoutText)

  ok(SolverBridgeResult(evidence: evidence))
# @axiom-hint: lean="solverSat ∧ solverUnsat ∧ solverUnknown ∧ depth = 0 → result ≠ solverVacuousContradiction" smt="(assert (and solverSat solverUnsat solverUnknown (=> (= depth 0) (not (= result solverVacuousContradiction)))))"
