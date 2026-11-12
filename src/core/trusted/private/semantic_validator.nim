import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/[options, sets, tables]
import core/trusted/axiom_ir
import core/trusted/symbol_table_types
import core/trusted/verification_model_types

type
  SemanticValidationResult* = object
    valid*: bool
    errors*: seq[string]

func collectIrVars(e: IRExpr; acc: var HashSet[string]) {.raises: [].} =
  if e == nil: return
  case e.kind
  of irVar:
    acc.incl(e.varName)
  of irLet:
    collectIrVars(e.letVal, acc)
    collectIrVars(e.letBody, acc)
  of irIf:
    collectIrVars(e.ifCond, acc)
    collectIrVars(e.ifThen, acc)
    collectIrVars(e.ifElse, acc)
  of irCase:
    collectIrVars(e.caseScrutinee, acc)
    for br in e.caseBranches:
      collectIrVars(br.body, acc)
    collectIrVars(e.caseDefault, acc)
  of irCall:
    for arg in e.callArgs:
      collectIrVars(arg, acc)
  of irBinOp:
    collectIrVars(e.binLhs, acc)
    collectIrVars(e.binRhs, acc)
  of irUnaryOp:
    collectIrVars(e.unaryArg, acc)
  of irRecCall:
    for arg in e.recArgs:
      collectIrVars(arg, acc)
  of irLoop:
    collectIrVars(e.loopCond, acc)
    collectIrVars(e.loopStep, acc)
    collectIrVars(e.loopBody, acc)
    for inv in e.loopInvariants:
      collectIrVars(inv, acc)
    collectIrVars(e.loopVariant, acc)
  of irCast:
    collectIrVars(e.castExpr, acc)
  of irLit, irFloatLit, irStringLit:
    discard

func validateSemantic*(model: VerificationModel): SemanticValidationResult {.raises: [].} =
  var errors: seq[string]

  # Layer 1: Symbol Resolution
  var declaredNamesInit: HashSet[string]
  for s in model.semantic.states:
    declaredNamesInit.incl(s.name)
  let declaredNames: HashSet[string] = declaredNamesInit

  var symbolNamesInit: HashSet[string]
  for sym in model.metadata.symbolMap.symbols:
    symbolNamesInit.incl(sym.name)
  let symbolNames: HashSet[string] = symbolNamesInit

  proc checkSymbolResolution(name: string) {.raises: [].} =
    if not model.metadata.symbolMap.hasSymbol(name):
      errors.add("unresolved symbol: " & name)

  proc checkIrVarsForResolution(e: IRExpr) {.raises: [].} =
    var vars = initHashSet[string]()
    collectIrVars(e, vars)
    for v in vars:
      checkSymbolResolution(v)

  for stateInit in model.semantic.initExprs:
    checkIrVarsForResolution(stateInit)

  for trans in model.semantic.transitions:
    checkIrVarsForResolution(trans.guard)
    for assign in trans.update.assignments:
      checkIrVarsForResolution(assign.expr)
    for havoc in trans.update.havocs:
      checkSymbolResolution(havoc)

  for obl in model.semantic.obligations:
    checkIrVarsForResolution(obl.predicate)

  if model.semantic.exitGuard.isSome:
    checkIrVarsForResolution(model.semantic.exitGuard.get)

  if model.semantic.property.isSome:
    checkIrVarsForResolution(model.semantic.property.get)

  # Layer 2: Scope Validation — no duplicate symbol names in states
  var stateNameCount: Table[string, int]
  for s in model.semantic.states:
    if stateNameCount.hasKey(s.name):
      errors.add("duplicate symbol: " & s.name)
    else:
      stateNameCount[s.name] = 1

  # No duplicate in symbolMap
  var symNameCount: Table[string, int]
  for sym in model.metadata.symbolMap.symbols:
    if symNameCount.hasKey(sym.name):
      errors.add("duplicate symbol: " & sym.name)
    else:
      symNameCount[sym.name] = 1

  # Layer 3: Type Validation
  for stateInit in model.semantic.initExprs:
    if not validateExprTypes(stateInit):
      errors.add("type validation failed")
      break

  for trans in model.semantic.transitions:
    if not validateExprTypes(trans.guard):
      errors.add("type validation failed")
      break
    for assign in trans.update.assignments:
      if not validateExprTypes(assign.expr):
        errors.add("type validation failed")
        break
    if errors.len > 0 and errors[^1] == "type validation failed":
      break

  for obl in model.semantic.obligations:
    if not validateExprTypes(obl.predicate):
      errors.add("type validation failed")
      break

  if model.semantic.exitGuard.isSome:
    if not validateExprTypes(model.semantic.exitGuard.get):
      errors.add("type validation failed")

  if model.semantic.property.isSome:
    if not validateExprTypes(model.semantic.property.get):
      errors.add("type validation failed")

  # Layer 4: Def-Use Validation
  proc checkDefUse(name: string) {.raises: [].} =
    if not declaredNames.contains(name) and not symbolNames.contains(name):
      errors.add("use of undeclared variable: " & name)

  proc checkIrVarsForDefUse(e: IRExpr) {.raises: [].} =
    var vars = initHashSet[string]()
    collectIrVars(e, vars)
    for v in vars:
      checkDefUse(v)

  for stateInit in model.semantic.initExprs:
    checkIrVarsForDefUse(stateInit)

  for trans in model.semantic.transitions:
    checkIrVarsForDefUse(trans.guard)
    for assign in trans.update.assignments:
      checkIrVarsForDefUse(assign.expr)
    for havoc in trans.update.havocs:
      checkDefUse(havoc)

  for obl in model.semantic.obligations:
    checkIrVarsForDefUse(obl.predicate)

  if model.semantic.exitGuard.isSome:
    checkIrVarsForDefUse(model.semantic.exitGuard.get)

  if model.semantic.property.isSome:
    checkIrVarsForDefUse(model.semantic.property.get)

  # Layer 5: Assignment Validation
  for trans in model.semantic.transitions:
    for assign in trans.update.assignments:
      if not declaredNames.contains(assign.symbol):
        errors.add("assignment to non-state symbol: " & assign.symbol)
    for havoc in trans.update.havocs:
      if not declaredNames.contains(havoc):
        errors.add("assignment to non-state symbol: " & havoc)

  result = SemanticValidationResult(valid: errors.len == 0, errors: errors)

{.pop.}