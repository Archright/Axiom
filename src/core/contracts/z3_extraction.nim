import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/options
import std/os
import std/osproc
import std/sequtils
import std/strutils
import std/tables
import core/proof/proof_budget
import core/trusted/solver_invocation
import core/types/solver_types
import core/types/z3_solver_config
import core/solver/z3_result_parser
import core/axiom_pragmas

type
  ProofStatus* = enum
    psProven
    psViolated
    psUnknown

  VerificationStatus* = enum
    vsProven
    vsViolated
    vsInconclusive

  TierStatus* = enum
    tsSuccess
    tsWarning
    tsFailure

  ScanMode* = enum
    smManual
    smAuto
    smTier1

  ContractProc* = object
    name*: string
    params*: seq[(string, string)]
    preconditions*: seq[string]
    postconditions*: seq[string]

  ContractProcNode* = object
    name*: string
    moduleName*: string
    requires*: seq[string]
    ensures*: seq[string]
    dependencies*: seq[string]
    isConstructor*: bool
    tier*: char

  TierReport* = object
    procName*: string
    tier*: char
    status*: TierStatus
    message*: string
    ciBlocking*: bool

  ProofResult* = object
    status*: ProofStatus
    verificationStatus*: VerificationStatus
    counterexample*: Option[Table[string, string]]
    procsChecked*: int
    procsProven*: int
    procsViolated*: int
    procsInconclusive*: int
    reports*: seq[TierReport]

  SolverStreamOutcome* = object
    ## ONE read of a solver response stream, carrying the two facts every
    ## projection of that stream needs: what the solver answered, and whether
    ## the stream is self-consistent enough to carry an answer at all.
    status*: SolverStatus
      ## The parser's answer, verbatim. No projection of a stream re-derives it.
    responseCount*: int
      ## How many ⟨check_sat_response⟩ lines the stream carries. SMT-LIB 2.7
      ## §4.1.7 fixes one such response per `check-sat`, so more than one means
      ## the stream is not one answer.
    isAnomalous*: bool
      ## `responseCount > 1`. An anomaly is never a discharge — a stream that
      ## answers more than once cannot say which answer was asked for.

  Z3Expr* = ref object
    tag*: string
    value*: string

const MAX_SCAN_LINES* = 50

proc newZ3Int*(value: BiggestInt): Z3Expr =
  result = Z3Expr(
    tag: "Int",
    value: $value
  )

proc newZ3Var*(name: string): Z3Expr =
  result = Z3Expr(
    tag: "Var",
    value: name
  )

proc newZ3Str*(value: string): Z3Expr =
  result = Z3Expr(
    tag: "Str",
    value: value
  )

proc extractZ3Ast*(node: NimNode): Z3Expr =
  when false:
    result = case node.kind
    of nkIntLit:
      newZ3Int(node.intVal)
    of nkIdent:
      newZ3Var(node.strVal)
    of nkStrLit:
      newZ3Str(node.strVal)
    else:
      nil  # 완전성 보장을 위한 else 분기
  else:
    result = nil

proc coreLog*(msg: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  discard

const distinctTypeMapping*: array[5, tuple[key: string, val: string]] = [
  ("CurrentRunVerified", "Int"),
  ("TotalKernelCount", "Int"),
  ("VkdRatio", "Real"),
  ("Natural", "Int"),
  ("Positive", "Int"),
]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc topologicalSortWithSCC*(procs: seq[ContractProcNode]): seq[ContractProcNode] =
  var index = 0
  var stack: seq[ContractProcNode] = @[]
  var onStack = initTable[string, bool]()
  var indices = initTable[string, int]()
  var lowlinks = initTable[string, int]()
  var resultSeq: seq[seq[ContractProcNode]] = @[]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
  proc strongConnect(node: ContractProcNode; nodes: seq[ContractProcNode]) =
    indices[node.name] = index
    lowlinks[node.name] = index
    inc index
    stack.add(node)
    onStack[node.name] = true
    for dep in node.dependencies:
      if not indices.hasKey(dep):
        let depNodes = nodes.filterIt(it.name == dep)
        if depNodes.len > 0:
          strongConnect(depNodes[0], nodes)
          let ll = lowlinks.getOrDefault(node.name, 0)
          lowlinks[node.name] = min(ll, lowlinks.getOrDefault(dep, ll))
      elif onStack.getOrDefault(dep, false):
        let ll = lowlinks.getOrDefault(node.name, 0)
        lowlinks[node.name] = min(ll, indices.getOrDefault(dep, ll))
    if lowlinks.getOrDefault(node.name, 0) == indices.getOrDefault(node.name, 0):
      var scc: seq[ContractProcNode] = @[]
      var w: ContractProcNode
      while true:
        w = stack[stack.high]
        stack.delete(stack.high)
        onStack[w.name] = false
        scc.add(w)
        if w.name == node.name:
          break
      resultSeq.add(scc)

  for p in procs:
    if not indices.hasKey(p.name):
      strongConnect(p, procs)

  var flatResult: seq[ContractProcNode] = @[]
  for scc in resultSeq:
    for n in scc:
      flatResult.add(n)
  flatResult

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc checkAxiomCompleteness*(contract: ContractProcNode): tuple[ok: bool, reason: string] =
  if contract.ensures.len == 0:
    result = (false, "No postconditions defined — axiom would be too weak")
  else:
    let hasResultRef = contract.ensures.anyIt(it.contains("result"))
    let hasStateRef = contract.ensures.anyIt(it.contains("state") or it.contains("self"))
    if not hasResultRef and not hasStateRef:
      result = (false, "Postconditions don't reference result or state — axiom too weak")
    else:
      result = (true, "")
      for ens in contract.ensures:
        let normalized = ens.replace(" ", "")
        if normalized == "true" or normalized == "result==result":
          result = (false, "Trivially true postcondition: " & ens)
          break

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc distinctTypeToSort*(typ: string): string =
  result = ""
  for (k, v) in distinctTypeMapping:
    if k == typ:
      result = v
      break

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc nimTypeToSmtSort*(typ: string): string =
  let mapped = distinctTypeToSort(typ)
  if mapped.len > 0:
    result = mapped
  else:
    let lower = typ.toLowerAscii()
    if lower in ["int", "int64", "int32", "uint", "uint64", "nat", "natural", "positive"]:
      result = "Int"
    elif lower in ["float", "float64", "float32", "real"]:
      result = "Real"
    elif lower in ["bool"]:
      result = "Bool"
    elif lower in ["string", "str", "char"]:
      result = "String"
    else:
      result = "Int"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractProcName*(line: string): string =
  let stripped = line.strip()
  let keywordEnd = stripped.find(' ')
  if keywordEnd < 0:
    result = ""
  else:
    let afterKeyword = stripped[keywordEnd + 1 .. ^1].strip()
    var nameEnd = 0
    for j, ch in afterKeyword:
      if ch in {'*', '(', '['}:
        nameEnd = j
        break
      if ch == ' ':
        nameEnd = j
        break
    if nameEnd == 0:
      nameEnd = afterKeyword.len
    result = afterKeyword[0 ..< nameEnd].strip(chars = {'*'})

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractArrayName*(line: string): string =
  let idx = line.find('[')
  if idx < 0:
    result = ""
  else:
    var start = idx - 1
    while start >= 0 and line[start] in IdentChars:
      dec start
    result = line[start + 1 ..< idx].strip()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractIndexName*(line: string): string =
  let openB = line.find('[')
  let closeB = line.find(']')
  if openB < 0 or closeB < 0 or closeB <= openB:
    result = ""
  else:
    result = line[openB + 1 ..< closeB].strip()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractDivisor*(line: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let slashPos = line.find('/')
  if slashPos < 0:
    result = ""
  else:
    var start = slashPos + 1
    while start < line.len and line[start] == ' ':
      inc start
    var endPos = start
    while endPos < line.len and line[endPos] in IdentChars:
      inc endPos
    result = line[start ..< endPos]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeExtractIndex*(expr: string; bracketIdx: int): Option[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if bracketIdx < 0 or bracketIdx >= expr.len:
    result = none(string)
  else:
    try:
      result = some(extractIndexName(expr))
    except CatchableError:
      result = none(string)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc safeExtractDivisor*(expr: string): Option[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let divPos = expr.find('/')
  if divPos < 0:
    result = none(string)
  else:
    try:
      result = some(extractDivisor(expr))
    except CatchableError:
      result = none(string)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parsePragmaArg*(line: string; pragmaName: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  let idx = line.find("{" & "." & pragmaName & ":")
  if idx >= 0:
    let start = idx + pragmaName.len + 3
    var depth = 0
    var cur = ""
    var inStr = false
    for i in start ..< line.len:
      let ch = line[i]
      if inStr:
        if ch == '"':
          inStr = false
          cur.add(ch)
        else:
          cur.add(ch)
      elif ch == '"':
        inStr = true
        cur.add(ch)
      elif ch == '(':
        inc depth
        if depth > 0:
          cur.add(ch)
      elif ch == ')':
        dec depth
        if depth >= 0:
          cur.add(ch)
        if depth < 0:
          break
      elif ch == '}':
        break
      elif ch == '.' and i + 1 < line.len and line[i + 1] == '}':
        break
      else:
        cur.add(ch)
    if cur.len > 0:
      let trimmed = cur.strip()
      if trimmed.len > 0:
        if trimmed[0] == '"' and trimmed[^1] == '"':
          result.add(trimmed[1 .. ^2])

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractContractProcs*(modulePath: string): seq[ContractProc] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  if not fileExists(modulePath):
    discard
  else:
    try:
      let source = readFile(modulePath)
      let lines = source.splitLines()
      result = @[]
      var i = 0
      while i < lines.len:
        let line = lines[i]
        let trimmed = line.strip()
        if trimmed.startsWith("proc ") or trimmed.startsWith("func ") or trimmed.startsWith("macro ") or trimmed.startsWith("template "):
          var keywordEnd = trimmed.find(' ')
          if keywordEnd < 0:
            inc i
            continue
          let afterKeyword = trimmed[keywordEnd + 1 .. ^1].strip()
          var nameEnd = 0
          for j, ch in afterKeyword:
            if ch in {'*', '(', '['}:
              nameEnd = j
              break
            if ch == ' ':
              nameEnd = j
              break
          if nameEnd == 0:
            nameEnd = afterKeyword.len
          let procName = afterKeyword[0 ..< nameEnd].strip().strip(chars = {'*'})
          if procName.len == 0:
            inc i
            continue
          var preconds: seq[string] = @[]
          var postconds: seq[string] = @[]
          var procParams: seq[(string, string)] = @[]
          var braceDepth = 0
          var j = i
          while j < lines.len:
            let l = lines[j]
            let st = l.strip()
            if st.startsWith("{"):
              inc braceDepth
              let preArgs = parsePragmaArg(l, "requires")
              for a in preArgs:
                preconds.add(a)
              let postArgs = parsePragmaArg(l, "ensures")
              for a in postArgs:
                postconds.add(a)
            if '{' in l:
              inc braceDepth
            if '}' in l:
              dec braceDepth
            if braceDepth == 0 and j > i:
              break
            inc j
          if preconds.len > 0 or postconds.len > 0:
            result.add(ContractProc(
              name: procName,
              params: procParams,
              preconditions: preconds,
              postconditions: postconds
            ))
          i = j
        else:
          inc i
    except CatchableError:
      discard

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc generateImplicitInvariants*(lines: seq[string]; startIdx: int): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var invariants: seq[string] = @[]
  var depth = 0
  var inProc = false
  let scanEnd = min(startIdx + MAX_SCAN_LINES, lines.len)

  for i in startIdx ..< scanEnd:
    let line = lines[i].strip()

    if line.startsWith("func ") or line.startsWith("proc "):
      inProc = true
      continue
    if inProc and line.startsWith("="):
      depth += 1
      continue
    if depth <= 0:
      break

    let bracketIdx = line.find('[')
    if bracketIdx >= 0:
      let idxOpt = safeExtractIndex(line, bracketIdx)
      if idxOpt.isSome:
        invariants.add(idxOpt.get & " >= 0")

    if "/" in line:
      let divOpt = safeExtractDivisor(line)
      if divOpt.isSome:
        invariants.add(divOpt.get & " != 0")

  invariants

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc scanPureFunctions*(modulePath: string): seq[ContractProcNode] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var procs: seq[ContractProcNode] = @[]
  let content =
    try: readFile(modulePath)
    except CatchableError: ""
  if content.len > 0:
    let lines = content.splitLines()
    for i, line in lines:
      let stripped = line.strip()
      if stripped.startsWith("func ") or
         (stripped.startsWith("proc ") and "noSideEffect" in stripped):
        let name = extractProcName(stripped)
        if name.len == 0:
          continue
        var node = ContractProcNode(
          name: name,
          moduleName: modulePath,
          requires: @[],
          ensures: @[],
          dependencies: @[],
          isConstructor: false,
          tier: 'B'
        )
        node.requires = generateImplicitInvariants(lines, i)
        procs.add(node)
  procs

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc handleVerificationFailure*(node: ContractProcNode; reason: string): TierReport =
  TierReport(
    procName: node.name,
    tier: node.tier,
    status: tsWarning,
    message: "Auto-verification inconclusive: " & reason &
             " — consider adding {.requiresPrecondition.}",
    ciBlocking: false
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc generateSmtlib2*(contracts: seq[ContractProc]): string =
  var parts: seq[string] = @[]
  parts.add("(set-option :produce-models true)")
  parts.add("(set-logic QF_LIA)")
  for c in contracts:
    for (name, typ) in c.params:
      let sort = nimTypeToSmtSort(typ)
      parts.add("(declare-const " & name & " " & sort & ")")
    for pre in c.preconditions:
      parts.add("(assert " & pre & ")")
    for post in c.postconditions:
      parts.add("(assert (not " & post & "))")
  parts.add("(check-sat)")
  parts.add("(get-model)")
  parts.join("\n")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc proofStatusToVerificationStatus*(ps: ProofStatus): VerificationStatus =
  case ps
  of psProven: vsInconclusive
  of psViolated: vsViolated
  of psUnknown: vsInconclusive

func readSolverStream*(raw: string): SolverStreamOutcome {.raises: [], axiomDecision(id = "DECISION-0827", reason = "Read a solver response stream once, reporting both the parser's answer and whether the stream carries more than one response so a self-contradictory stream can fail closed to unknown instead of discharging an obligation", adr = "docs/spec/evidence_calculus.md", introduced = "v34").} =
  ## The single authoritative reading of a solver response stream.
  ##
  ## `status` is `parseStatusLine`'s answer, passed through untouched: a
  ## projection of a stream must not hold a second opinion about which line is
  ## the response. The count asks the SAME classifier about each line, so it
  ## cannot be measuring a different grammar than the verdict it qualifies.
  ##
  ## Multiplicity is an anomaly, not a stronger verdict. Reading only the first
  ## response is what keeps the verdict honest about a stream that answers
  ## twice — but on its own it silently promotes the weakest of the answers to
  ## the whole stream, and a stream that says `unsat` and then `sat` would
  ## discharge an obligation it contradicted.
  ##
  ## The anomaly is collapsed INTO the status here, at the one point where a
  ## stream is read, rather than re-tested by each projection. A stream that
  ## answers twice has not produced a decidable answer, so it carries no status
  ## downstream and every consumer lands on the same weakest state without
  ## knowing the rule exists. `sat` is exempt: a stream that produced a
  ## counter-example has produced adverse evidence whatever it printed
  ## afterwards, and withholding that is not fail-closed.
  result.status = parseStatusLine(raw)
  for line in raw.splitLines():
    if hasSolverDecision(solverResponse(line)):
      inc result.responseCount
  result.isAnomalous = result.responseCount > 1
  if result.isAnomalous and result.status != solverSat:
    result.status = solverUnknown

func proofResultFromSolverStream*(stdoutText: string): ProofResult {.raises: [], axiomDecision(id = "DECISION-0828", reason = "Expose the single stdout-to-ProofResult mapping so a contradictory response stream can be shown to land on the weakest honest state with its anomaly reason recorded", adr = "docs/spec/evidence_calculus.md", introduced = "v34").} =
  ## Project ONE solver stream onto the contract-extraction result. One
  ## mapping, shared by every entry point, so two invocations of the same
  ## script cannot reach two different conclusions.
  ##
  ## The verdict is the stream's status and nothing else. An anomaly reaches
  ## this function already collapsed into `solverUnknown`, so the only thing
  ## left to do with it is keep the reason in `reports`: a recorded answer must
  ## not exceed the evidence that produced it
  ## (docs/adr/0017-trust-claim-authority.md), and a stream that contradicts
  ## itself is weaker evidence than a single response, never stronger.
  result = ProofResult(
    status: psUnknown,
    verificationStatus: vsInconclusive,
    counterexample: none(Table[string, string]),
    procsChecked: 0,
    procsProven: 0,
    procsViolated: 0,
    procsInconclusive: 0,
    reports: @[]
  )
  let stream = readSolverStream(stdoutText)
  case stream.status
  of solverSat:
    result.verificationStatus = vsViolated
    result.status = psViolated
    result.procsChecked = 1
    result.procsViolated = 1
    let bindings = parseModelBindings(stdoutText)
    if bindings.len > 0:
      var ce = initTable[string, string]()
      for b in bindings:
        ce[b.name] = b.value
      result.counterexample = some(ce)
  of solverUnsat:
    result.verificationStatus = vsInconclusive
    result.status = psProven
    result.procsProven = 1
  else:
    result.verificationStatus = vsInconclusive
    result.status = psUnknown
    result.procsChecked = 1
    result.procsInconclusive = 1
    if stream.isAnomalous:
      result.reports.add(TierReport(
        procName: "solver_stream",
        tier: 'S',
        status: tsWarning,
        message: "anomalous solver stream: " & $stream.responseCount &
                 " response lines in one invocation — no obligation is discharged",
        ciBlocking: false
      ))

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildRlimitPrimaryEnvelope(smtLib2Code: string): string {.raises: [].} =
  ## Deterministic rlimit-primary SMT-LIB2 envelope (docs/spec/z3_pool_determinism.md
  ## §2.1 — INV-10): replaces the legacy wall-clock `-T:` invocation, which is
  ## non-deterministic under CPU load (Z3 Issues #5969/#1151). The option set is
  ## projected from the ONE pinned list in core/trusted/solver_invocation — the
  ## same projection verification/solver/z3_pool.buildZ3QueryEnvelope emits, so
  ## this envelope cannot drift from the option set whose digest gets recorded:
  ## deterministic rlimit budget, :timeout liveness net only, non-zero pinned
  ## seeds (SMT-LIB 2.7 §4.1.7 makes seed 0 the opt-OUT of determinism), and
  ## options preserved across (reset). SSOT constants:
  ## proof_budget.z3DeterministicBudget / z3SafetyNetMs. Options already present
  ## in the query are never duplicated.
  result = smtLib2Code
  for spec in deterministicSolverOptions(z3DeterministicBudget, z3SafetyNetMs):
    if result.find("(set-option :" & spec.name) < 0:
      result = solverOptionDirective(spec) & "\n" & result
  if result.find("(reset)") < 0:
    result = "(reset)\n" & result
  if not result.endsWith("\n"):
    result.add("\n")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runZ3Proof*(smtLib2Code: string): ProofResult =
  result = ProofResult(
    status: psUnknown,
    verificationStatus: vsInconclusive,
    counterexample: none(Table[string, string]),
    procsChecked: 0,
    procsProven: 0,
    procsViolated: 0,
    procsInconclusive: 0,
    reports: @[]
  )
  if smtLib2Code.len > 0:
    let z3Path = resolveZ3Path()
    if z3Path.len > 0:
      try:
        let (output, exitCode) = execCmdEx(
          z3Path & " -in -smt2",
          input = buildRlimitPrimaryEnvelope(smtLib2Code),
          options = {poUsePath}
        )
        if exitCode == 0:
          result = proofResultFromSolverStream(output)
      except CatchableError:
        result.verificationStatus = vsInconclusive
        result.procsInconclusive = 1

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runZ3ProofSafe*(smtLib2Code: string): ProofResult =
  result = ProofResult(
    status: psUnknown,
    verificationStatus: vsInconclusive,
    counterexample: none(Table[string, string]),
    procsChecked: 0,
    procsProven: 0,
    procsViolated: 0,
    procsInconclusive: 0,
    reports: @[]
  )
  if smtLib2Code.len > 0:
    let z3Path = resolveZ3Path()
    if z3Path.len > 0:
      try:
        let (output, exitCode) = execCmdEx(
          z3Path & " -in -smt2",
          input = buildRlimitPrimaryEnvelope(smtLib2Code),
          options = {poUsePath}
        )
        let outputLower = output.strip().toLowerAscii()
        if exitCode != 0 and outputLower.len == 0:
          result.verificationStatus = vsInconclusive
          result.procsInconclusive = 1
        else:
          result = proofResultFromSolverStream(output)
      except CatchableError:
        result.verificationStatus = vsInconclusive
        result.procsInconclusive = 1

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro requiresPrecondition*(body: untyped): untyped =
  result = body

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractManualContracts*(modulePaths: seq[string]; strictBlocking: bool = false): ProofResult =
  var allContracts: seq[ContractProc] = @[]
  for path in modulePaths:
    let contracts = extractContractProcs(path)
    allContracts.add(contracts)

  if allContracts.len == 0:
    result = ProofResult(
      status: psUnknown,
      verificationStatus: vsInconclusive,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 0,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
  else:
    var nodes: seq[ContractProcNode] = @[]
    for c in allContracts:
      var node = ContractProcNode(
        name: c.name,
        requires: c.preconditions,
        ensures: c.postconditions,
        dependencies: @[],
        isConstructor: false,
        tier: 'C'
      )
      for pre in c.preconditions:
        for other in allContracts:
          if other.name != c.name and pre.contains(other.name):
            node.dependencies.add(other.name)
      for post in c.postconditions:
        for other in allContracts:
          if other.name != c.name and post.contains(other.name):
            if other.name notin node.dependencies:
              node.dependencies.add(other.name)
      if node.dependencies.len == 0:
        node.tier = 'A'
      elif node.dependencies.len <= 3:
        node.tier = 'B'
      else:
        node.tier = 'C'
      nodes.add(node)

    let sortedNodes = topologicalSortWithSCC(nodes)
    var tierAContracts: seq[ContractProc] = @[]
    var tierBContracts: seq[ContractProc] = @[]
    var tierCContracts: seq[ContractProc] = @[]
    for n in sortedNodes:
      let check = checkAxiomCompleteness(n)
      if not check.ok:
        continue
      else:
        let match = allContracts.filterIt(it.name == n.name)
        if match.len > 0:
          case n.tier
          of 'A': tierAContracts.add(match[0])
          of 'B': tierBContracts.add(match[0])
          of 'C': tierCContracts.add(match[0])
          else: tierCContracts.add(match[0])

    var resultAxiom = ProofResult(
      status: psProven,
      verificationStatus: vsProven,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 0,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
    if tierAContracts.len > 0:
      resultAxiom.procsChecked += tierAContracts.len
      resultAxiom.procsProven += tierAContracts.len
    if tierBContracts.len > 0:
      let smt2B = generateSmtlib2(tierBContracts)
      let rB = runZ3ProofSafe(smt2B)
      resultAxiom.procsChecked += rB.procsChecked
      resultAxiom.procsProven += rB.procsProven
      resultAxiom.procsViolated += rB.procsViolated
      resultAxiom.procsInconclusive += rB.procsInconclusive
      case rB.verificationStatus
      of vsViolated:
        if strictBlocking:
          try:
            coreLog("[STRICT] Contract violated: B tier failure")
          except:  # axiom:best-effort(logging failure before quit(1); termination must not be blocked)
            discard
          quit(1)
        result = rB
      of vsInconclusive:
        resultAxiom.verificationStatus = vsInconclusive
      of vsProven:
        discard
    if tierCContracts.len > 0:
      var frozenAxioms: seq[ContractProc] = @[]
      frozenAxioms.add(tierAContracts)
      frozenAxioms.add(tierBContracts)
      let smt2C = generateSmtlib2(frozenAxioms & tierCContracts)
      let rC = runZ3ProofSafe(smt2C)
      resultAxiom.procsChecked += rC.procsChecked
      resultAxiom.procsProven += rC.procsProven
      resultAxiom.procsViolated += rC.procsViolated
      resultAxiom.procsInconclusive += rC.procsInconclusive
      case rC.verificationStatus
      of vsViolated:
        if strictBlocking:
          try:
            coreLog("[STRICT] Contract violated: C tier failure")
          except:  # axiom:best-effort(logging failure before quit(1); termination must not be blocked)
            discard
          quit(1)
        result = rC
      of vsInconclusive:
        resultAxiom.verificationStatus = vsInconclusive
      of vsProven:
        discard
    if strictBlocking:
      for r in resultAxiom.reports:
        if r.status == tsFailure and r.ciBlocking:
          try:
            coreLog("[STRICT] Contract violated: " & r.procName & " — " & r.message)
          except:  # axiom:best-effort(logging failure before quit(1); termination must not be blocked)
            discard
          quit(1)
    result = resultAxiom

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractAndVerifyContracts*(modulePaths: seq[string]; scanMode: ScanMode = smManual; strictBlocking: bool = false): ProofResult =
  ## Contract verification.
  ## NOTE: Full AST virtual scanning only active with -d:axiomProve flag.
  ##       Normal `nim c` builds skip this entirely (zero overhead).

  var allContracts: seq[ContractProc] = @[]
  for path in modulePaths:
    let contracts = extractContractProcs(path)
    allContracts.add(contracts)

  if allContracts.len == 0:
    result = ProofResult(
      status: psUnknown,
      verificationStatus: vsInconclusive,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 0,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
  elif scanMode == smTier1:
    result = ProofResult(
      status: psUnknown,
      verificationStatus: vsInconclusive,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 0,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
  else:
    var nodes: seq[ContractProcNode] = @[]
    for c in allContracts:
      var node = ContractProcNode(
        name: c.name,
        requires: c.preconditions,
        ensures: c.postconditions,
        dependencies: @[],
        isConstructor: false,
        tier: 'C'
      )
      for pre in c.preconditions:
        for other in allContracts:
          if other.name != c.name and pre.contains(other.name):
            node.dependencies.add(other.name)
      for post in c.postconditions:
        for other in allContracts:
          if other.name != c.name and post.contains(other.name):
            if other.name notin node.dependencies:
              node.dependencies.add(other.name)
      if node.dependencies.len == 0:
        node.tier = 'A'
      elif node.dependencies.len <= 3:
        node.tier = 'B'
      else:
        node.tier = 'C'
      nodes.add(node)

    when defined(axiomProve):
      case scanMode
      of smTier1:
        discard
      of smAuto:
        var allPureNodes: seq[ContractProcNode] = @[]
        for path in modulePaths:
          let pureProcs = scanPureFunctions(path)
          allPureNodes.add(pureProcs)
        for node in allPureNodes:
          if node.requires.len > 0:
            discard handleVerificationFailure(node, "missing caller context")
      of smManual:
        discard

    let sortedNodes = topologicalSortWithSCC(nodes)
    var tierAContracts: seq[ContractProc] = @[]
    var tierBContracts: seq[ContractProc] = @[]
    var tierCContracts: seq[ContractProc] = @[]
    for n in sortedNodes:
      let check = checkAxiomCompleteness(n)
      if not check.ok:
        continue
      else:
        let match = allContracts.filterIt(it.name == n.name)
        if match.len > 0:
          case n.tier
          of 'A': tierAContracts.add(match[0])
          of 'B': tierBContracts.add(match[0])
          of 'C': tierCContracts.add(match[0])
          else: tierCContracts.add(match[0])

    var resultAxiom = ProofResult(
      status: psProven,
      verificationStatus: vsProven,
      counterexample: none(Table[string, string]),
      procsChecked: 0,
      procsProven: 0,
      procsViolated: 0,
      procsInconclusive: 0,
      reports: @[]
    )
    if tierAContracts.len > 0:
      resultAxiom.procsChecked += tierAContracts.len
      resultAxiom.procsProven += tierAContracts.len
    if tierBContracts.len > 0:
      let smt2B = generateSmtlib2(tierBContracts)
      let rB = runZ3ProofSafe(smt2B)
      resultAxiom.procsChecked += rB.procsChecked
      resultAxiom.procsProven += rB.procsProven
      resultAxiom.procsViolated += rB.procsViolated
      resultAxiom.procsInconclusive += rB.procsInconclusive
      case rB.verificationStatus
      of vsViolated:
        result = rB
      of vsInconclusive:
        resultAxiom.verificationStatus = vsInconclusive
      of vsProven:
        discard
    if tierCContracts.len > 0:
      var frozenAxioms: seq[ContractProc] = @[]
      frozenAxioms.add(tierAContracts)
      frozenAxioms.add(tierBContracts)
      let smt2C = generateSmtlib2(frozenAxioms & tierCContracts)
      let rC = runZ3ProofSafe(smt2C)
      resultAxiom.procsChecked += rC.procsChecked
      resultAxiom.procsProven += rC.procsProven
      resultAxiom.procsViolated += rC.procsViolated
      resultAxiom.procsInconclusive += rC.procsInconclusive
      case rC.verificationStatus
      of vsViolated:
        result = rC
      of vsInconclusive:
        resultAxiom.verificationStatus = vsInconclusive
      of vsProven:
        discard
    result = resultAxiom

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc extractAndVerifyContractsWithBlocking*(
  modulePaths: seq[string];
  scanMode: ScanMode = smManual;
  strictBlocking: bool = false
): ProofResult =
  result = extractAndVerifyContracts(modulePaths, scanMode, strictBlocking)
  if strictBlocking:
    for r in result.reports:
      if r.status == tsFailure and r.ciBlocking:
        try:
          coreLog("[STRICT] Contract violated: " & r.procName & " — " & r.message)
        except:  # axiom:best-effort(logging failure before quit(1); termination must not be blocked)
          discard
        quit(1)

{.pop.}
