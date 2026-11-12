import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## irLoop → Constrained Horn Clause (CHC) bridge.
##
## Converts an `irLoop` with an unresolved static bound into a Z3 Spacer
## (CHC / SMT-LIB2 HORN ) script so such loops can be verified via the
## inductive route (`vpInductiveLoop`) instead of being honestly skipped
## (`vpBmcSkipped`).
##
## Scope (conservative by design — §0.9 Anti-Theater):
##   * Only `lkFor` loops are handled. `lkWhile` returns none.
##   * Only loops carrying an index plus at least one accumulator are handled
##     (`loopVars.len >= 2`). `loopVars[0]` is the index; `loopVars[^1]` is the
##     result accumulator (same convention as `genTerminationRef`). The state
##     relation is n-ary — one BitVec argument per loop variable.
##   * The loop body must not itself contain a nested loop.
##   * Every emitted rule must be a *meaningful* property check — `error`
##     is reachable iff the function postcondition is violated at loop exit.
##
## Encoding (n-ary state relation tracks each loop variable):
##   (declare-rel state (BV64 BV64 ... BV64))   # one arg per loopVar
##   init      : (state init0 init1 ... initn)
##   trans     : state(v0,v1,...,vn) /\ cond(v..)  =>  state(next0,next1,...,nextn)
##               where next0 = step expr (index advances) and
##                     nexti = irExprToSmt(loopBody) over the current state
##                     for each accumulator variable (i >= 1)
##   property  : state(v0,...,vn) /\ not cond /\ not post(result:=loopVars[^1])  =>  error
##
## `(query error)` returns `unsat` iff `error` is unreachable, i.e. the
## postcondition holds on every legal loop exit. `runZ3CheckViaIR` treats
## `unsat` as "property holds" — consistent with the standard BMC route.
##
## P0.3.4/P0.3.5: The domain-level `VerificationModel` bridge
## (`buildChcFromVerificationModel` / `buildChcFromLoop`) lowers an `irLoop`
## into a transition system first (via `lowerLoopToTransition`) and emits a CHC
## script from that model, decoupling loop lowering from CHC emission.
##
## LEGACY PATH — alternative-projection, not the semantic reference.
## This module implements the pre-VerificationModel CHC encoder
## (buildChcTransitionSystem / buildChcProperty / irLoopToHornScript).
## It is non-default and only reachable via explicit bpAllowFallback
## policy in the IR pipeline runner. The canonical path uses the
## VerificationModel-derived encoder (buildChcFromLoop → runZ3CheckViaIR
## → evidenceVerdict).

import std/algorithm
import std/options
import std/sequtils
import std/strutils
import core/axiom_pragmas
import core/trusted/axiom_ir
import core/trusted/ir_tree_ops
import core/trusted/ir_to_smt
import core/trusted/private/chc_types
import core/trusted/private/chc_build_result
import core/trusted/private/transition_formula_builder
import core/trusted/private/verification_obligations
import core/trusted/private/semantic_identity
import core/trusted/solver_invocation
import core/trusted/private/loop_transition_lowering
import core/trusted/symbol_table_types
import core/trusted/verification_model_types
import ir_state_sort
import verification/obligation/obligation_ir

## Legacy marker — this encoder is non-default and only reachable
## via explicit bpAllowFallback policy in the IR pipeline runner.
## It is the alternative-projection (pre-VerificationModel) path,
## not the semantic reference.
type
  LegacyChcBackend* = enum
    lcbLegacyChc  ## Pre-VerificationModel CHC encoder (buildChcTransitionSystem)

const
  hornPrelude = "(set-logic HORN)\n" &
    "(set-option :fp.engine spacer)\n" &
    "(set-option :fp.spacer.ground_pobs false)\n" &
    solverOptionsPayload(pinnedDeterminismOptions())
  bv64 = "(_ BitVec 64)"

func emitVarDeclarations(vars: seq[string]; exclude: openArray[string] = []): string {.raises: [].} =
  var lines: seq[string] = @[]
  for v in vars:
    if v notin exclude:
      lines.add("(declare-var " & v & " " & bv64 & ")")
  lines.join("\n")

func emitStateVarDeclarations(stateNames: openArray[string]; sortStrs: openArray[string]): string {.raises: [].} =
  ## The Z3 fixedpoint engine requires every free symbol in a rule to be bound
  ## via `(declare-var ...)` — without it the relation args are rejected as
  ## "unknown constant" and the solver answers vacuously (spurious mercy
  ## unsat). Emit one declare-var per state variable using its CHC sort.
  var lines: seq[string] = @[]
  for i, st in stateNames:
    let sort = if i < sortStrs.len: sortStrs[i] else: bv64
    lines.add("(declare-var " & st & " " & sort & ")")
  lines.join("\n")

func nestedLoop(e: IRExpr): bool {.raises: [].} =
  if e == nil: return false
  case e.kind
  of irLoop: return true
  of irBinOp: result = nestedLoop(e.binLhs) or nestedLoop(e.binRhs)
  of irUnaryOp: result = nestedLoop(e.unaryArg)
  of irIf: result = nestedLoop(e.ifCond) or nestedLoop(e.ifThen) or nestedLoop(e.ifElse)
  of irCall:
    for a in e.callArgs:
      if nestedLoop(a): return true
  of irRecCall:
    for a in e.recArgs:
      if nestedLoop(a): return true
  of irLet:
    result = nestedLoop(e.letVal) or nestedLoop(e.letBody)
  of irCase:
    if nestedLoop(e.caseScrutinee): return true
    for b in e.caseBranches:
      if nestedLoop(b.body): return true
    result = nestedLoop(e.caseDefault)
  of irCast:
    result = nestedLoop(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    discard

func loopSimpleFor*(loopExpr: IRExpr): bool {.raises: [].} =
  if loopExpr == nil or loopExpr.kind != irLoop: return false
  if loopExpr.loopKind != lkFor: return false
  if loopExpr.loopVars.len < 1: return false
  if loopExpr.loopStep == nil or loopExpr.loopCond == nil: return false
  if loopExpr.loopInits.len < 1: return false
  if loopExpr.loopBody == nil: return false
  if nestedLoop(loopExpr.loopBody): return false
  result = true

func unsignedProjection(smt: string): string {.raises: [].} =
  result = smt
    .replace("bvslt", "bvult")
    .replace("bvsle", "bvule")
    .replace("bvsge", "bvuge")
    .replace("bvsgt", "bvugt")

proc buildChcTransitionSystem*(loopExpr: IRExpr; symbolTable: SymbolTable; useIntSort: bool = true): ChcModelResult {.axiomDecision(
     id = "DECISION-0021",
     reason = "CHC transition system construction — always generates init+trans rules independent of postconditions",
     adr = "docs/spec/loop_bmc_soundness.md",
     introduced = "v33"), raises: [].} =
  if not loopSimpleFor(loopExpr):
    return ChcModelResult(kind: cmNotEncodable, notEncodableReason: "loopSimpleFor rejected")

  var sortStrs: seq[string] = @[]
  var initSmts: seq[string] = @[]
  for i, v in loopExpr.loopVars:
    let initSmt = irExprToSmt(loopExpr.loopInits[i])
    let sortKind = mapIrTypeToChcSort(loopExpr.loopInits[i].typ, useIntSort)
    sortStrs.add(toChcSortStr(sortKind))
    if useIntSort and sortKind == cskInt:
      initSmts.add(toIntSort(initSmt))
    else:
      initSmts.add(initSmt)

  let idxStep = unsignedProjection(irExprToSmt(loopExpr.loopStep))
  let condSmt = unsignedProjection(irExprToSmt(loopExpr.loopCond))
  let bodySmt = irExprToSmt(loopExpr.loopBody)

  var nextSmts: seq[string] = @[]
  for i, v in loopExpr.loopVars:
    if i == 0:
      if useIntSort and sortStrs[0] == "Int":
        nextSmts.add(toIntSort(idxStep))
      else:
        nextSmts.add(idxStep)
    else:
      if useIntSort and sortStrs[i] == "Int":
        nextSmts.add(toIntSort(bodySmt))
      else:
        nextSmts.add(bodySmt)

  var declVars: seq[string] = @[]
  for s in symbolTable.allSymbols():
    if s.name notin loopExpr.loopVars and s.name notin ["result", "_loop_result"]:
      declVars.add(s.name)

  let stateVars = loopExpr.loopVars.join(" ")
  let stateRel = "(declare-rel state (" & sortStrs.join(" ") & "))"
  let initRule = "(rule (state " & initSmts.join(" ") & "))"
  let transRule = "(rule (=> (and (state " & stateVars & ") " & condSmt & ") " &
    "(state " & nextSmts.join(" ") & ")))"

  ChcModelResult(
    kind: cmBuilt,
    prelude: hornPrelude,
    stateRel: stateRel,
    initRule: initRule,
    transRule: transRule,
    stateVars: stateVars,
    condSmt: condSmt,
    declVars: declVars,
    sortStrs: sortStrs,
    loopVars: loopExpr.loopVars
  )

func buildChcProperty*(funcDef: IRFuncDef; loopExpr: IRExpr; model: ChcModelResult; symbolTable: SymbolTable): ChcPropertyResult {.axiomDecision(
     id = "DECISION-0022",
     reason = "CHC property construction — generates error rule + query only when postcondition exists",
     adr = "docs/spec/loop_bmc_soundness.md",
     introduced = "v33"), raises: [].} =
  if model.kind != cmBuilt:
    return ChcPropertyResult(kind: cpNoProperty)

  var declVars = model.declVars
  for s in symbolTable.allSymbols():
    if s.name notin declVars and s.name notin model.loopVars and s.name notin ["result", "_loop_result"]:
      declVars.add(s.name)
  let excluded = ["result", "_loop_result"]

  let postSubst = [("result", model.loopVars[^1])]
  var postSmt = ""
  for post in funcDef.postConditions:
    if post == nil: continue
    let ps = unsignedProjection(irExprToSmt(ir_tree_ops.substVarsInExpr(post, postSubst)))
    if postSmt.len == 0:
      postSmt = ps
    else:
      postSmt = "(and " & postSmt & " " & ps & ")"
  if postSmt.len == 0:
    return ChcPropertyResult(kind: cpNoProperty)

  if model.loopVars.len == 1 and postSmt.contains("result"):
    return ChcPropertyResult(kind: cpNoProperty)

  let postDeclarations = emitVarDeclarations(declVars, excluded)
  let propertyRule = "(rule (=> (and (state " & model.stateVars & ") " &
    "(not " & model.condSmt & ") " & "(not " & postSmt & ")) error))"
  let queryCmd = "(query error)"

  ChcPropertyResult(
    kind: cpBuilt,
    propertyRule: propertyRule,
    queryCmd: queryCmd,
    postDeclarations: postDeclarations
  )

proc irLoopToHornScript*(funcDef: IRFuncDef; loopExpr: IRExpr; useIntSort: bool = true): Option[string] {.axiomDecision(
     id = "DECISION-0015",
     reason = "irLoop to CHC/Spacer bridge proves unresolved-bound for-loops inductively instead of honoring the vpBmcSkipped skip; sound encoding threads idx+result accumulator through the CHC state",
     adr = "docs/spec/loop_bmc_soundness.md",
     introduced = "v32"), raises: [].} =
  let model = buildChcTransitionSystem(loopExpr, funcDef.symbolTable, useIntSort)
  if model.kind != cmBuilt:
    return none(string)
  let property = buildChcProperty(funcDef, loopExpr, model, funcDef.symbolTable)
  if property.kind != cpBuilt:
    return none(string)

  var lines: seq[string] = @[]
  lines.add(model.prelude)
  if property.postDeclarations.len > 0:
    lines.add(property.postDeclarations)
  lines.add(model.stateRel)
  lines.add("(declare-rel error ())")
  lines.add(model.initRule)
  lines.add(model.transRule)
  lines.add(property.propertyRule)
  lines.add(property.queryCmd)
  lines.add("(check-sat)")
  some(lines.join("\n"))

proc buildChcFromVerificationModel*(vm: VerificationModel; symbolTable: SymbolTable): ChcBuildResult {.axiomDecision(
     id = "DECISION-0023",
     reason = "Domain VerificationModel → CHC/Spacer script; emits init/trans/obligation rules from the lowered transition system, classifying each non-encodable case explicitly (C12/C13)",
     adr = "docs/spec/loop_bmc_soundness.md",
     introduced = "v34"), raises: [].} =
  ## Emit a complete CHC SMT-LIB2 script from a domain `VerificationModel`.
  ## Returns (C13 classification, never a bare "" / none):
  ##   * `cbInvalidModel(cimDegenerateStateArity)` when state arity is
  ##     degenerate (`states.len == 0` or init arity mismatch)
  ##   * `cbInvalidModel(cimNilStateType)` when a `StateVar` carries nil `irType`
  ##   * `cbNotApplicable(cnaNoObligations)` when there are no obligations — a
  ##     query with no `error` reachability rule would vacuously return `unsat`
  ##     and prove nothing (§0.9 Anti-Theater). This is a semantics gap, not a
  ##     capability gap, so it is NOT `Unsupported`.
  ##
  ## Encoding mirrors `buildChcTransitionSystem`: one Int-sort state argument
  ## per `StateVar`, init rule from `initExprs`, one transition rule per
  ## `Transition` (unassigned state variables persist by name), and one error
  ## rule per obligation — obligation predicates are checked at the `exitGuard`
  ## boundary (or on every reachable state when no exit guard is present).
  let sem = vm.semantic
  if sem.states.len == 0 or sem.states.len != sem.initExprs.len:
    return chcBuildInvalidModel([$cimDegenerateStateArity])
  # P2: obligations come from the backend-agnostic Obligation Model — semantic
  # obligations OR a derived exit-safety property. Without either, the query
  # would be vacuous (§0.9 Anti-Theater) and is classified NotApplicable.
  let derived = buildObligations(vm)
  if derived.safeties.len == 0 and sem.obligations.len == 0:
    return chcBuildNotApplicable(cnaNoObligations)
  for st in sem.states:
    if st.irType == nil:
      return chcBuildInvalidModel([$cimNilStateType & ":" & st.name])

  let useIntSort = false
  var sortStrs: seq[string] = @[]
  var initSmts: seq[string] = @[]
  for i, st in sem.states:
    let sortKind = mapIrTypeToChcSort(st.irType, useIntSort)
    sortStrs.add(toChcSortStr(sortKind))
    let initSmt = irExprToSmt(sem.initExprs[i])
    if useIntSort and sortKind == cskInt:
      initSmts.add(toIntSort(initSmt))
    else:
      initSmts.add(initSmt)

  var stateVarParts: seq[string] = @[]
  for st in sem.states:
    stateVarParts.add(st.name)
  let stateVars = stateVarParts.join(" ")

  var declVars: seq[string] = @[]
  let stateNames = sem.states.mapIt(it.name)
  for s in symbolTable.allSymbols():
    if s.name notin stateNames and s.name notin ["result", "_loop_result"]:
      declVars.add(s.name)
  declVars.sort()
  var transPairs: seq[(string, string)] = @[]
  for tr in sem.transitions:
    let trGuardKey = guardSmt(tr)
    let trGuardSmt = if tr.guard != nil:
      unsignedProjection(irExprToSmt(tr.guard))
    else:
      "true"
    # Post-state comes from the SEMANTIC KERNEL (C5.1) — a local ParallelUpdate
    # re-implementation here would let CHC and Evidence diverge (§C5.1).
    var builder = newTransitionFormulaBuilder(
      sem.states.mapIt(it.name))
    var fresh = 0
    let formula = buildTransitionFormula(builder, tr, fresh)
    var nextSmts: seq[string] = @[]
    for i, st in sem.states:
      let postArg = formula.postArgs[i].nextSmt
      if useIntSort and sortStrs[i] == "Int":
        nextSmts.add(toIntSort(postArg))
      else:
        nextSmts.add(postArg)
    let rule = "(rule (=> (and (state " & stateVars & ") " & trGuardSmt & ") " &
      "(state " & nextSmts.join(" ") & ")))"
    var updateParts: seq[string] = @[]
    for a in tr.update.assignments:
      updateParts.add(a.symbol & "=" & unsignedProjection(irExprToSmt(a.expr)))
    updateParts.sort()
    for h in tr.update.havocs:
      updateParts.add("havoc:" & h)
    updateParts.sort()
    let updateKey = updateParts.join(";")
    let identity = transitionIdentityOf(tr, trGuardKey, updateKey)
    transPairs.add((canonicalKey(identity), rule))
  transPairs.sort(proc(a, b: (string, string)): int = cmp(a[0], b[0]))
  var transRules: seq[string] = @[]
  for p in transPairs:
    transRules.add(p[1])

  var obPairs: seq[(string, string)] = @[]
  # P2: error rules derive from the Obligation Model's SAFETY family (which
  # covers both semantic obligations and the derived exit property). This makes
  # the canonical CHC path non-vacuous for property-carrying models.
  for ob in derived.safeties:
    if ob.propertySmt.len == 0: continue
    let obPredSmt = unsignedProjection(ob.propertySmt)
    var condParts = @["(state " & stateVars & ")"]
    if sem.exitGuard.isSome and sem.exitGuard.get != nil:
      var exitGuardIr = sem.exitGuard.get
      if sem.resultStateName.isSome:
        exitGuardIr = ir_tree_ops.substVarsInExpr(exitGuardIr, @[("result", sem.resultStateName.get)])
      condParts.add("(not " & unsignedProjection(irExprToSmt(exitGuardIr)) & ")")
    condParts.add("(not " & obPredSmt & ")")
    let rule = "(rule (=> (and " & condParts.join(" ") & ") error))"
    let key = "safety:" & obPredSmt
    obPairs.add((key, rule))
  obPairs.sort(proc(a, b: (string, string)): int = cmp(a[0], b[0]))
  var obRules: seq[string] = @[]
  for p in obPairs:
    obRules.add(p[1])

  var lines: seq[string] = @[]
  lines.add(hornPrelude)
  let varDecls = emitVarDeclarations(declVars, stateNames)
  if varDecls.len > 0:
    lines.add(varDecls)
  lines.add("(declare-rel state (" & sortStrs.join(" ") & "))")
  lines.add("(declare-rel error ())")
  let stateDecls = emitStateVarDeclarations(stateNames, sortStrs)
  if stateDecls.len > 0:
    lines.add(stateDecls)
  lines.add("(rule (state " & initSmts.join(" ") & "))")
  for r in transRules: lines.add(r)
  for r in obRules: lines.add(r)
  lines.add("(query error)")
  lines.add("(check-sat)")
  chcBuildSuccess(lines.join("\n"))

proc buildChcFromLoop*(loopExpr: IRExpr; symbolTable: SymbolTable;
                       contract: ContractInfo = ContractInfo()): ChcBuildResult {.axiomDecision(
     id = "DECISION-0024",
     reason = "irLoop → VerificationModel → CHC bridge; lowerLoopToTransition builds the domain transition system, buildChcFromVerificationModel emits the script, classifying every non-success explicitly (C13)",
     adr = "docs/spec/loop_bmc_soundness.md",
     introduced = "v34"), raises: [].} =
  ## Bridge from an `irLoop` directly to a CHC script.
  ##   1. `lowerLoopToTransition` — lower the loop into a `VerificationModel`.
  ##   2. `buildChcFromVerificationModel` — emit the CHC script with explicit
  ##      success/failure classification.
  ##   3. Returns `cbNotApplicable` / `cbUnsupported` / `cbInvalidModel`
  ##      (never a bare "" / none) so the caller can observe and record the
  ##      backend outcome (§0.9 Anti-Theater, C13).
  let lowered = lowerLoopToTransition(loopExpr, symbolTable, contract)
  if lowered.isNone:
    return chcBuildUnsupported(cusNotLoop)
  buildChcFromVerificationModel(lowered.get, symbolTable)

# ---------------------------------------------------------------------------
# P4: Obligation-IR consumer overload — emits 1:1 property rules from obligations
# ---------------------------------------------------------------------------

func buildChcFromObligations*(
  loopExpr: IRExpr;
  obligations: seq[VerificationObligation];
  symbolTable: SymbolTable;
  useIntSort: bool = true
): ChcBuildResult {.raises: [].} =
  ## Convert an `irLoop` + explicit obligation list into a CHC SMT-LIB2 script.
  ## Each obligation is emitted as a dedicated error-rule property (1:1 mapping).
  ## The legacy `cpNoProperty` short-circuit (loopVars==1 ∧ post references result)
  ## does NOT apply here — obligations are explicit and every obligation becomes a
  ## property regardless of loopVar count or result reference.
  if not loopSimpleFor(loopExpr):
    return chcBuildUnsupported(cusNotLoop)
  if obligations.len == 0:
    return chcBuildNotApplicable(cnaNoObligations)

  var sortStrs: seq[string] = @[]
  var initSmts: seq[string] = @[]
  for i, v in loopExpr.loopVars:
    let initSmt = irExprToSmt(loopExpr.loopInits[i])
    let sortKind = mapIrTypeToChcSort(loopExpr.loopInits[i].typ, useIntSort)
    sortStrs.add(toChcSortStr(sortKind))
    if useIntSort and sortKind == cskInt:
      initSmts.add(toIntSort(initSmt))
    else:
      initSmts.add(initSmt)

  let idxStep = unsignedProjection(irExprToSmt(loopExpr.loopStep))
  let condSmt = unsignedProjection(irExprToSmt(loopExpr.loopCond))
  let bodySmt = irExprToSmt(loopExpr.loopBody)

  var nextSmts: seq[string] = @[]
  for i, v in loopExpr.loopVars:
    if i == 0:
      if useIntSort and sortStrs[0] == "Int":
        nextSmts.add(toIntSort(idxStep))
      else:
        nextSmts.add(idxStep)
    else:
      if useIntSort and sortStrs[i] == "Int":
        nextSmts.add(toIntSort(bodySmt))
      else:
        nextSmts.add(bodySmt)

  var declVars: seq[string] = @[]
  for s in symbolTable.allSymbols():
    if s.name notin loopExpr.loopVars and s.name notin ["result", "_loop_result"]:
      declVars.add(s.name)

  let stateVars = loopExpr.loopVars.join(" ")
  let stateRel = "(declare-rel state (" & sortStrs.join(" ") & "))"
  let initRule = "(rule (state " & initSmts.join(" ") & "))"
  let transRule = "(rule (=> (and (state " & stateVars & ") " & condSmt & ") " &
    "(state " & nextSmts.join(" ") & ")))"

  # C7 count preservation: every obligation emits exactly one property rule.
  doAssert obligations.len > 0, "buildChcFromObligations requires ≥1 obligation"
  var propertyRules: seq[string] = @[]
  for obl in obligations:
    let predSmt = unsignedProjection(obl.predicate)
    var condParts = @["(state " & stateVars & ")"]
    condParts.add("(not " & condSmt & ")")
    condParts.add("(not " & predSmt & ")")
    propertyRules.add("(rule (=> (and " & condParts.join(" ") & ") error))")

  # Verify C7: input obligation count == output property rule count.
  if propertyRules.len != obligations.len:
    return chcBuildObligationMismatch()

  var lines: seq[string] = @[]
  lines.add(hornPrelude)
  let varDecls = emitVarDeclarations(declVars, loopExpr.loopVars)
  if varDecls.len > 0:
    lines.add(varDecls)
  lines.add(stateRel)
  lines.add("(declare-rel error ())")
  lines.add(initRule)
  lines.add(transRule)
  for pr in propertyRules:
    lines.add(pr)
  lines.add("(query error)")
  lines.add("(check-sat)")

  chcBuildSuccess(lines.join("\n"))

{.pop.}
