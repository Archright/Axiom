import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/options
import core/trusted/axiom_pragmas
import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/symbol_table_types
import core/trusted/verification_model_types

func lowerLoopToTransition*(loopExpr: IRExpr; symbolTable: SymbolTable;
                            contract: ContractInfo = ContractInfo()): Option[VerificationModel] {.axiomDecision(id = "DECISION-0026", reason = "Loop-to-VerificationModel transition lowering controls the domain model shape for downstream CHC verification", adr = "docs/spec/cfg_contract_specification.md", introduced = "v32"), raises: [].} =
  if loopExpr == nil or loopExpr.kind != irLoop:
    return none(VerificationModel)
  if loopExpr.loopInits.len != loopExpr.loopVars.len:
    return none(VerificationModel)

  var sem = VMSemantic()

  for i, v in loopExpr.loopVars:
    let init = loopExpr.loopInits[i]
    let origin = if symbolTable.hasSymbol(v):
      symbolTable.getSymbol(v).origin
    else:
      SymbolOrigin(kind: sokImplicit)
    sem.initState(v, init.typ, origin)
    sem.initExprs.add(init)

  if loopExpr.loopCond != nil:
    let guardNode = NodeId(1)
    let bodyNode = NodeId(2)
    sem.initTransition(guardNode, bodyNode, loopExpr.loopCond, ParallelUpdate())

  if loopExpr.loopStep != nil and loopExpr.loopVars.len > 0:
    var update = ParallelUpdate()
    update.addAssignment(loopExpr.loopVars[0], loopExpr.loopStep)
    let guardNode = NodeId(1)
    let bodyNode = NodeId(2)
    if sem.transitions.len > 0:
      sem.transitions[^1] = Transition(source: guardNode, target: bodyNode, guard: loopExpr.loopCond, update: update)

  case loopExpr.loopKind
  of lkFor:
    sem.loopFacts = some(LoopFacts(kind: lfkBounded, counterName: loopExpr.loopVars[0]))
  of lkWhile:
    sem.loopFacts = some(LoopFacts(kind: lfkUnknown))

  sem.exitGuard = some(loopExpr.loopCond)
  sem.logicalDomain = ldBitVec
  # The function return value (`result` in postconditions) maps to the LAST loop
  # variable, mirroring the legacy buildChcProperty substitution
  # `("result", loopVars[^1])`. Explicit contract so buildSafeties can emit a
  # well-formed CHC error rule (result ∈ declared state vars).
  if loopExpr.loopVars.len > 0:
    sem.resultStateName = some(loopExpr.loopVars[^1])

  if contract.postConditions.len > 0:
    var nonNil: seq[IRExpr] = @[]
    for p in contract.postConditions:
      if p != nil:
        nonNil.add(p)
    if nonNil.len == 1:
      sem.property = some(nonNil[0])
    elif nonNil.len > 1:
      var conj = nonNil[0]
      for i in 1 ..< nonNil.len:
        conj = irBinOp(boAnd, conj, nonNil[i])
      sem.property = some(conj)

  let model = VerificationModel(
    semantic: sem,
    metadata: VMMetadata(
      functionExit: NodeId(0),
      symbolMap: symbolTable,
      sourceLocation: "",
      resultStateName: sem.resultStateName
    )
  )
  some(model)

{.pop.}