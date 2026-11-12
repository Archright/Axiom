import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/options
import core/trusted/axiom_pragmas
import core/trusted/axiom_ir
import core/trusted/symbol_table_types

type
  LogicalDomain* = enum
    ldBitVec
    ldInt
    ldBool
    ldArray

  LoopFactKind* = enum
    lfkUnknown
    lfkBounded
    lfkUnbounded

  LoopFacts* = object
    kind*: LoopFactKind
    counterName*: string
    lowerBound*: Option[int64]
    upperBound*: Option[int64]

  NodeId* = distinct uint32

  CFGNodeKind* = enum
    cnkEntry
    cnkExit
    cnkCondition
    cnkBlock
    cnkMerge
    cnkReturn
    cnkBreak
    cnkContinue

  CFGNode* = object
    id*: NodeId
    kind*: CFGNodeKind
    successors*: seq[NodeId]
    predecessors*: seq[NodeId]

  FunctionCFG* = object
    entry*: NodeId
    normalExit*: NodeId
    returnExits*: seq[NodeId]
    nodes*: seq[CFGNode]

  StateVar* = object
    name*: string
    irType*: IRType
    origin*: SymbolOrigin

  AbstractionKind* = enum
    akExact
    akOverApproximation
    akUnsupported

  Assignment* = object
    symbol*: string
    expr*: IRExpr

  ParallelUpdate* = object
    assignments*: seq[Assignment]
    havocs*: seq[string]

  Transition* = object
    source*: NodeId
    target*: NodeId
    guard*: IRExpr
    update*: ParallelUpdate

  ObligationKind* = enum
    okUserContract
    okImplicitSafety
    okDerivedSafety

  Obligation* = object
    origin*: SymbolOrigin
    predicate*: IRExpr
    kind*: ObligationKind
    source*: string

  ContractInfo* {.axiomDecision(
    id = "DECISION-0610",
    reason = "Shallow semantic contract context threaded into CHC lowering; postConditions feed VMSemantic.property",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v37"
  ).} = object
    preConditions*: seq[IRExpr]     # P1: preserved, NOT consumed (future precondition/assumption semantics)
    postConditions*: seq[IRExpr]    # P1: → VMSemantic.property (the single exit property)

  VMSemantic* = object
    states*: seq[StateVar]
    initExprs*: seq[IRExpr]
    transitions*: seq[Transition]
    property*: Option[IRExpr]
    exitGuard*: Option[IRExpr]
    obligations*: seq[Obligation]
    loopFacts*: Option[LoopFacts]
    logicalDomain*: LogicalDomain
    resultStateName*: Option[string]  ## Name of the state var that holds the function
                                     ## return value (post `result` substitution target).

  VMMetadata* = object
    functionExit*: NodeId
    symbolMap*: SymbolTable
    sourceLocation*: string
    resultStateName*: Option[string]  ## Name of the state var that holds the function
                                       ## return value, threaded from VMSemantic so
                                       ## the metadata layer can reference it without
                                       ## crossing into the semantic domain.

  VerificationModel* = object
    semantic*: VMSemantic
    metadata*: VMMetadata

func initState*(vm: var VMSemantic; name: string; irType: IRType; origin: SymbolOrigin) =
  vm.states.add(StateVar(name: name, irType: irType, origin: origin))

func initTransition*(vm: var VMSemantic; source, target: NodeId; guard: IRExpr; update: ParallelUpdate) =
  vm.transitions.add(Transition(source: source, target: target, guard: guard, update: update))

func initObligation*(vm: var VMSemantic; predicate: IRExpr; kind: ObligationKind; origin: SymbolOrigin; source: string = "") =
  vm.obligations.add(Obligation(origin: origin, predicate: predicate, kind: kind, source: source))

func hasAnyObligation*(vm: VMSemantic): bool =
  vm.obligations.len > 0

func addAssignment*(update: var ParallelUpdate; symbol: string; expr: IRExpr) =
  update.assignments.add(Assignment(symbol: symbol, expr: expr))

func addHavoc*(update: var ParallelUpdate; symbol: string) =
  update.havocs.add(symbol)

func `==`*(a, b: NodeId): bool {.borrow.}
func `$`*(a: NodeId): string {.borrow.}

{.pop.}