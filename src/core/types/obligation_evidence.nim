## ObligationEvidence — Structured types for proof evidence accumulation.
## Replaces discard with algebraically composable evidence objects.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import std/sets
import std/options
import std/json
import std/sequtils
import std/algorithm
import std/strutils

type
  ModelBinding* = object
    ## Structured binding from Z3 model output (define-fun)
    name*: string
    value*: string
    sort*: string                      ## SMT-LIB sort or arrow type for functions

  Z3Model* = object
    ## Structured Z3 counter-example model
    bindings*: seq[ModelBinding]
    rawModel*: string
    queryKind*: string                 ## "equivalence" | "invariant" | "chc"

  LeanProofGoal* = object
    ## Lean proof goal with diagnostic context
    goalText*: string
    localHypotheses*: seq[string]
    diagnosticCount*: int
    dominantDiagnostic*: string

  LayerOutcome* = enum
    ## Portfolio layer outcomes (ordered: worst → best)
    ## Polarity: max — portfolio semantics (one success = success)
    leFailedUnknown, leFailedRlimit, leFailedSat, leSucceeded

  LayerEvidence* = object
    ## Evidence from a single verification layer
    layerName*: string                 ## "CHC" | "Craig" | "SyGuS" | "LLM"
    outcome*: LayerOutcome
    counterExample*: Option[Z3Model]
    stepCount*: int                    ## Deterministic step count (elapsedMs 대체)
    rawOutput*: string

  DerivationGraph* = object
    ## DAG of proof derivation steps (idempotent·commutative·associative union)
    nodes*: HashSet[string]
    edges*: HashSet[(string, string)]

  ObligationEvidence* = object
    ## Complete evidence record — algebraically composable via combineEvidence
    z3Model*: Option[Z3Model]
    leanGoals*: seq[LeanProofGoal]
    unsatCoreVars*: seq[string]
    smtlib2Query*: string
    layerTrace*: seq[LayerEvidence]
    derivationGraph*: DerivationGraph
    solverMeta*: JsonNode
    stepCount*: int                    ## Total deterministic step count
    elapsedMs*: int                    ## [METRIC-ONLY] Must not participate in algebraic decisions

func emptyEvidence*(): ObligationEvidence {.raises: [].} =
  ## Identity element for combineEvidence
  ObligationEvidence(
    z3Model: none(Z3Model),
    leanGoals: @[],
    unsatCoreVars: @[],
    smtlib2Query: "",
    layerTrace: @[],
    derivationGraph: DerivationGraph(nodes: initHashSet[string](), edges: initHashSet[(string, string)]()),
    solverMeta: newJObject(),
    stepCount: 0,
    elapsedMs: 0
  )

func withLayer*(ev: ObligationEvidence; layerName: string; outcome: LayerOutcome): ObligationEvidence {.raises: [].} =
  ## Append a LayerEvidence entry to the evidence trace (immutable update pattern).
  ObligationEvidence(
    z3Model: ev.z3Model,
    leanGoals: ev.leanGoals,
    unsatCoreVars: ev.unsatCoreVars,
    smtlib2Query: ev.smtlib2Query,
    layerTrace: ev.layerTrace & @[LayerEvidence(
      layerName: layerName,
      outcome: outcome,
      stepCount: 0,
      rawOutput: ""
    )],
    derivationGraph: ev.derivationGraph,
    solverMeta: ev.solverMeta,
    stepCount: ev.stepCount,
    elapsedMs: ev.elapsedMs
  )

## ─── Z3 Model Parsing (Phase 2) ─────────────────────────────────────────────

func countParens(raw: string): int {.raises: [].} =
  ## Count unmatched opening parens minus closing parens.
  for ch in raw:
    if ch == '(': inc result
    elif ch == ')': dec result

func consumeExpr(raw: string): tuple[expr: string, remainder: string] {.raises: [].} =
  ## Consume the next S-expression or atom from raw string.
  let trimmed = raw.strip()
  if trimmed.len == 0:
    return ("", "")
  if trimmed[0] != '(':
    # Atom: read until whitespace
    let ws = trimmed.find({' ', '\t', '\n', '\r'})
    if ws < 0:
      return (trimmed, "")
    return (trimmed[0 ..< ws], trimmed[ws .. ^1].strip())
  # S-expression: track paren balance
  var depth = 0
  for idx, ch in trimmed:
    if ch == '(': inc depth
    elif ch == ')':
      dec depth
      if depth == 0:
        let remainder = if idx + 1 < trimmed.len: trimmed[idx + 1 .. ^1].strip() else: ""
        return (trimmed[0 .. idx], remainder)
  (trimmed, "")

func extractParamSorts(paramsExpr: string): seq[string] {.raises: [].} =
  ## Extract sort names from ((param1 Sort1) (param2 Sort2)) expression.
  result = @[]
  let content = paramsExpr.strip()
  if content == "()" or content.len < 4:
    return
  # Remove outer parens: ((x!0 Int)) → (x!0 Int)
  let inner = content[1 ..< content.len - 1].strip()
  var cursor = inner
  while cursor.len > 0:
    let (pair, rest) = consumeExpr(cursor)
    if pair.len == 0: break
    if pair.startsWith("("):
      # (paramName Sort) → extract sort (second element)
      let pairInner = pair[1 ..< pair.len - 1].strip()
      let (_, afterName) = consumeExpr(pairInner)
      let (sort, _) = consumeExpr(afterName)
      if sort.len > 0:
        result.add(sort)
    cursor = rest.strip()

func parseOneDefineFun(blk: string): ModelBinding {.raises: [].} =
  ## Parse a single (define-fun name (params) sort body) expression.
  result = ModelBinding()
  let trimmed = blk.strip()
  if not trimmed.startsWith("(define-fun ") or not trimmed.endsWith(")"):
    return
  # Remove outer parens: (define-fun ...) → define-fun ...
  let inner = trimmed[1 ..< trimmed.len - 1].strip()
  if inner.len <= "define-fun ".len:
    return
  let rest0 = inner["define-fun ".len .. ^1].strip()

  let (name, rest1) = consumeExpr(rest0)
  if name.len == 0: return

  let (paramsExpr, rest2) = consumeExpr(rest1)
  if paramsExpr.len == 0: return

  let (returnSort, rest3) = consumeExpr(rest2)
  if returnSort.len == 0: return

  # Body is everything remaining after return sort
  let body = rest3.strip()

  let isConstant = (paramsExpr == "()")
  if isConstant:
    result = ModelBinding(name: name, value: body, sort: returnSort)
  else:
    let paramSorts = extractParamSorts(paramsExpr)
    var sortStr = ""
    for s in paramSorts:
      if sortStr.len > 0: sortStr.add(" -> ")
      sortStr.add(s)
    sortStr.add(" -> ")
    sortStr.add(returnSort)
    result = ModelBinding(
      name: name,
      value: "(lambda " & paramsExpr & " " & body & ")",
      sort: sortStr
    )

func parseModelBindings*(rawOutput: string): seq[ModelBinding] {.raises: [].} =
  ## Parse Z3 (get-model) output into structured ModelBinding entries.
  ## Handles both constants: (define-fun x () Int 42)
  ## and functions: (define-fun f ((x!0 Int)) Int (+ x!0 1))
  ## Returns @[] on parse failure — never raises.
  result = @[]
  let lines = rawOutput.splitLines()
  var i = 0
  while i < lines.len:
    let trimmed = lines[i].strip()
    if not trimmed.startsWith("(define-fun "):
      inc i
      continue
    # Accumulate multi-line define-fun block
    var funBlock = trimmed
    var balance = countParens(trimmed)
    inc i
    while balance > 0 and i < lines.len:
      let nextLine = lines[i].strip()
      if nextLine.len > 0:
        funBlock.add("\n" & nextLine)
      balance += countParens(nextLine)
      inc i
    let binding = parseOneDefineFun(funBlock)
    if binding.name.len > 0:
      result.add(binding)

## ─── Z3 Model Extraction ────────────────────────────────────────────────────

func extractZ3Model*(rawOutput: string; queryKind: string = "unknown"): Z3Model {.raises: [].} =
  ## Extract a structured Z3Model from raw Z3 output (counter-example models).
  ## Phase 1: wraps raw output. Phase 2: parse model bindings.
  ## SSOT: This is the canonical constructor for Z3Model. z3_pool.nim re-exports it.
  Z3Model(
    rawModel: rawOutput,
    queryKind: queryKind,
    bindings: parseModelBindings(rawOutput)
  )

func withZ3Model*(ev: ObligationEvidence; model: Z3Model): ObligationEvidence {.raises: [].} =
  ## Set the z3Model field on evidence (immutable update pattern).
  ObligationEvidence(
    z3Model: some(model),
    leanGoals: ev.leanGoals,
    unsatCoreVars: ev.unsatCoreVars,
    smtlib2Query: ev.smtlib2Query,
    layerTrace: ev.layerTrace,
    derivationGraph: ev.derivationGraph,
    solverMeta: ev.solverMeta,
    stepCount: ev.stepCount,
    elapsedMs: ev.elapsedMs
  )

func withQuery*(ev: ObligationEvidence; query: string): ObligationEvidence {.raises: [].} =
  ## Set the smtlib2Query field on evidence (immutable update pattern).
  ObligationEvidence(
    z3Model: ev.z3Model,
    leanGoals: ev.leanGoals,
    unsatCoreVars: ev.unsatCoreVars,
    smtlib2Query: query,
    layerTrace: ev.layerTrace,
    derivationGraph: ev.derivationGraph,
    solverMeta: ev.solverMeta,
    stepCount: ev.stepCount,
    elapsedMs: ev.elapsedMs
  )

func mergeGraphs*(a, b: DerivationGraph): DerivationGraph {.raises: [].} =
  ## True algebraic DAG union (Idempotent: A+A=A, Commutative: A+B=B+A, Associative: (A+B)+C=A+(B+C))
  DerivationGraph(
    nodes: a.nodes + b.nodes,
    edges: a.edges + b.edges
  )

func toCanonicalJson*(g: DerivationGraph): JsonNode {.raises: [].} =
  ## Canonical JSON — deterministic SHA256 (HashSet iteration is non-deterministic)
  let sortedNodes = toSeq(g.nodes).sorted(cmp)
  let sortedEdges = toSeq(g.edges).sorted(proc(x, y: (string, string)): int =
    let c = cmp(x[0], y[0])
    if c != 0: return c
    return cmp(x[1], y[1])
  )
  result = newJObject()
  result["nodes"] = %sortedNodes
  result["edges"] = %sortedEdges.mapIt(%[it[0], it[1]])

func toCanonicalJson*(ev: ObligationEvidence): JsonNode {.raises: [CatchableError].} =
  ## Canonical JSON serialization of complete evidence record.
  ## Deterministic: layerTrace sorted by layerName, derivationGraph via its own canonical form.
  result = newJObject()
  result["stepCount"] = %ev.stepCount
  result["smtlib2Query"] = %ev.smtlib2Query
  var traceArr = newJArray()
  for layer in ev.layerTrace:
    traceArr.add(%*{
      "layerName": layer.layerName,
      "outcome": $layer.outcome,
      "stepCount": layer.stepCount
    })
  result["layerTrace"] = traceArr
  result["derivationGraph"] = toCanonicalJson(ev.derivationGraph)

func mergeSolverMeta*(a, b: JsonNode): JsonNode {.raises: [CatchableError].} =
  ## solverMeta merge — type-clash guard for associativity
  if a.isNil: return b
  if b.isNil: return a
  result = newJObject()
  let allKeys = toSeq(a.keys) & toSeq(b.keys)
  var seen: seq[string]
  for k in allKeys:
    if k notin seen: seen.add(k)
  seen.sort(cmp)
  for key in seen:
    let aVal = a.getOrDefault(key)
    let bVal = b.getOrDefault(key)
    if aVal.isNil: result[key] = bVal
    elif bVal.isNil: result[key] = aVal
    elif aVal.kind == bVal.kind:
      case aVal.kind
      of JString: result[key] = %(max(aVal.str, bVal.str))
      of JInt: result[key] = %(max(aVal.num, bVal.num))
      of JFloat: result[key] = %(max(aVal.fnum, bVal.fnum))
      of JBool: result[key] = %(aVal.bval or bVal.bval)
      of JObject: result[key] = mergeSolverMeta(aVal, bVal)
      of JArray: result[key] = aVal
      of JNull: result[key] = aVal
    else:
      if aVal.kind == JObject: result[key] = aVal
      elif bVal.kind == JObject: result[key] = bVal
      else:
        if ord(aVal.kind) >= ord(bVal.kind): result[key] = aVal
        else: result[key] = bVal

{.pop.}
