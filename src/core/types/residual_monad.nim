## ResidualMonad[T] — Evidence-preserving monad for verification pipeline.
## Replaces discard-based information loss with algebraic evidence accumulation.
## Note: `bind` is a Nim keyword; we use `chainResidual` as the monadic bind name.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import std/sets
import std/sequtils
import std/algorithm
import std/tables
import std/options
import std/strutils
import core/types/obligation_evidence

type
  ResidualMonad*[T] = object
    value*: T
    obligation*: ObligationEvidence

# LayerOutcome merge — portfolio semantics (max)
# polarity: max (portfolio — one success = success)
# invariant_pipeline.nim: CHC→Craig→SyGuS→LLM first-success-wins
func joinOutcome(a, b: LayerOutcome): LayerOutcome {.inline, raises: [].} =
  if a > b: a else: b

func combineEvidence*(a, b: ObligationEvidence): ObligationEvidence {.raises: [CatchableError].} =
  ## True lattice join: idempotent, commutative, associative

  # 1. smtlib2Query: block-level dedup + sort
  let aQueries = if a.smtlib2Query.len > 0: a.smtlib2Query.split("\n---\n") else: @[]
  let bQueries = if b.smtlib2Query.len > 0: b.smtlib2Query.split("\n---\n") else: @[]
  var allQueries = aQueries & bQueries
  allQueries.sort(proc(x, y: string): int = cmp(x, y))
  var mergedQueries: seq[string]
  for q in allQueries:
    if mergedQueries.len == 0 or mergedQueries[^1] != q:
      mergedQueries.add(q)
  let cleanQuery = mergedQueries.join("\n---\n")

  # 2. leanGoals: deduplicate by goalText, sort
  var goalMap = initTable[string, LeanProofGoal]()
  for g in a.leanGoals:
    goalMap[g.goalText] = g
  for g in b.leanGoals:
    goalMap[g.goalText] = g
  var mergedGoals = toSeq(goalMap.values)
  mergedGoals.sort(proc(x, y: LeanProofGoal): int = cmp(x.goalText, y.goalText))

  # 3. unsatCoreVars: dedup + sort
  var allVars = a.unsatCoreVars & b.unsatCoreVars
  allVars.sort(proc(x, y: string): int = cmp(x, y))
  var cleanVars: seq[string]
  for v in allVars:
    if cleanVars.len == 0 or cleanVars[^1] != v:
      cleanVars.add(v)

  # 4. layerTrace: Table-based map-reduce
  var traceTable = initTable[string, LayerEvidence]()
  for trace in a.layerTrace:
    traceTable[trace.layerName] = trace
  for trace in b.layerTrace:
    if traceTable.hasKey(trace.layerName):
      let existing = traceTable[trace.layerName]
      traceTable[trace.layerName] = LayerEvidence(
        layerName: trace.layerName,
        outcome: joinOutcome(existing.outcome, trace.outcome),
        stepCount: max(existing.stepCount, trace.stepCount),
        rawOutput: if existing.rawOutput.len >= trace.rawOutput.len: existing.rawOutput else: trace.rawOutput,
        counterExample: (
          if existing.counterExample.isNone: trace.counterExample
          elif trace.counterExample.isNone: existing.counterExample
          else:
            let eModel = existing.counterExample.get
            let tModel = trace.counterExample.get
            if eModel.queryKind < tModel.queryKind or
               (eModel.queryKind == tModel.queryKind and eModel.rawModel <= tModel.rawModel):
              trace.counterExample
            else:
              existing.counterExample
        )
      )
    else:
      traceTable[trace.layerName] = trace
  var cleanLayerTrace = toSeq(traceTable.values)
  cleanLayerTrace.sort(proc(x, y: LayerEvidence): int = cmp(x.layerName, y.layerName))

  # 5. z3Model: deterministic total order
  let mergedZ3 = block:
    if a.z3Model.isNone: b.z3Model
    elif b.z3Model.isNone: a.z3Model
    else:
      let aM = a.z3Model.get
      let bM = b.z3Model.get
      if aM.queryKind < bM.queryKind or
         (aM.queryKind == bM.queryKind and aM.rawModel <= bM.rawModel):
        b.z3Model
      else:
        a.z3Model

  ObligationEvidence(
    z3Model: mergedZ3,
    leanGoals: mergedGoals,
    unsatCoreVars: cleanVars,
    smtlib2Query: cleanQuery,
    layerTrace: cleanLayerTrace,
    derivationGraph: mergeGraphs(a.derivationGraph, b.derivationGraph),
    solverMeta: mergeSolverMeta(a.solverMeta, b.solverMeta),
    stepCount: max(a.stepCount, b.stepCount),
    elapsedMs: max(a.elapsedMs, b.elapsedMs)
  )

func pureResidual*[T](value: T): ResidualMonad[T] {.raises: [].} =
  ResidualMonad[T](value: value, obligation: emptyEvidence())

func chainResidual*[T, U](
    m: ResidualMonad[T],
    f: proc(x: T): ResidualMonad[U] {.raises: [CatchableError].}
): ResidualMonad[U] {.raises: [CatchableError].} =
  ## Monadic bind — chain evidence-producing computations
  let next = f(m.value)
  ResidualMonad[U](
    value: next.value,
    obligation: combineEvidence(m.obligation, next.obligation)
  )

func mapResidual*[T, U](
    m: ResidualMonad[T],
    f: proc(x: T): U {.raises: [].}
): ResidualMonad[U] {.raises: [].} =
  ResidualMonad[U](value: f(m.value), obligation: m.obligation)

func `>>=`*[T, U](
    m: ResidualMonad[T],
    f: proc(x: T): ResidualMonad[U] {.raises: [CatchableError].}
): ResidualMonad[U] {.raises: [CatchableError].} =
  chainResidual(m, f)

func extractObligations*[T](m: ResidualMonad[T]): ObligationEvidence {.raises: [].} =
  m.obligation

func hasResidual*[T](m: ResidualMonad[T]): bool {.raises: [].} =
  m.obligation.z3Model.isSome or
  m.obligation.leanGoals.len > 0 or
  m.obligation.layerTrace.len > 0

{.pop.}
