import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## Obligation SMT Lowering — pure primitive that turns a type-complete
## IRExpr proposition into an executable SMT-LIB2 script with
## declare-fun declarations for free variables.
##
## Design:
## - No provenance or state in the context struct.
## - Self-contained lowering for the supported constructs
##   (irLit, irVar, irLet, boAnd, boEq, boGe, boLt, boSub, uoNot,
##    irCall "len") — fail-closed for all else.
## - Reuses recomputeTyp and elaborateSorts from axiom_ir_helpers.
## - Fail-closed: unsupported constructs → empty + lostInformation + errorMsg.
## - Deterministic: free vars sorted, declare-funs in canonical order.
## - Follows the repo convention: (assert (not <term>)) then (check-sat)
##   so that unsat = the proposition is valid (no counterexample).

import core/trusted/axiom_ir
import core/trusted/axiom_ir_helpers
import core/trusted/axiom_pragmas
import core/trusted/ir_elaborate_sorts
import core/trusted/semantic_fact_types
import core/logic/smt_logic
import std/algorithm
import std/options
import std/strutils

# ---------------------------------------------------------------------------
# Context — minimal, no provenance or state
# ---------------------------------------------------------------------------

type
  SmtLoweringContext* = object
    logic*: SmtLogic
    rlimit*: int
    obligationKind*: string
    ## WP4-j.2 INV-1: semantic facts to assert alongside the proposition.
    ## Facts are projected from compile-time literal bindings and
    ## asserted as (assert <fact-term>) before the negated proposition.
    semanticFacts*: seq[SemanticFact] = @[]
    ## Source bindings the translator read out of the subject's declaration
    ## region, carried verbatim (`IRFuncDef.recordedBindings`). Which of them
    ## become SMT `let`s is decided here from `lossFree` + the proposition's own
    ## free vars, never by the caller: a binding whose defining expression lost
    ## something is not a fact about the program and must not be asserted as one.
    sourceBindings*: seq[IRBinding] = @[]
    ## DEBT#465 body-binding restoration (form 2): the subject funcDef the
    ## proposition's `result` refers to. When the caller carries it and the
    ## proposition reads `result`, the lowerer emits a
    ## `(define-fun <name>_impl (params) ret <body>)` plus a
    ## `(let ((result (<name>_impl params))) ...)` query wrapper — the classic
    ## emitter's BMC form (ir_to_smt_chunk3) — instead of declaring `result`
    ## as an unconstrained 0-ary constant. Absent (the default), the historical
    ## declare-fun form is emitted unchanged.
    funcDef*: Option[IRFuncDef] = none(IRFuncDef)

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------

type
  SmtLoweringResult* = object
    obligationKind*: string
    symbolicOperands*: seq[string]
    referencedIrNodes*: int
    smtTerm*: string
    smtScript*: string
    empty*: bool
    lostInformation*: bool
    errorMsg*: string

# ---------------------------------------------------------------------------
# Free-variable collection
# ---------------------------------------------------------------------------

func collectFreeVars*(e: IRExpr): seq[string] =
  ## Walk the IRExpr tree and collect all irVar variable names.
  ## Returns a sorted, deduplicated seq for deterministic ordering.
  ## Binders are NOT tracked here: an irLet body's bound names are collected as
  ## if they were free.  boundLetNames restores the scoping for the chain that
  ## wraps the proposition; names bound by an inner irLet stay over-collected
  ## and produce a dead (shadowed) declare-fun, which Z3 accepts.
  if e == nil: return @[]
  case e.kind
  of irVar:
    result = @[e.varName]
  of irLit, irFloatLit, irStringLit:
    result = @[]
  of irBinOp:
    result = collectFreeVars(e.binLhs)
    result.add collectFreeVars(e.binRhs)
  of irUnaryOp:
    result = collectFreeVars(e.unaryArg)
  of irIf:
    result = collectFreeVars(e.ifCond)
    result.add collectFreeVars(e.ifThen)
    result.add collectFreeVars(e.ifElse)
  of irLet:
    result = collectFreeVars(e.letVal)
    result.add collectFreeVars(e.letBody)
  of irCase:
    result = collectFreeVars(e.caseScrutinee)
    for br in e.caseBranches:
      result.add collectFreeVars(br.body)
    if e.caseDefault != nil:
      result.add collectFreeVars(e.caseDefault)
  of irCall:
    for a in e.callArgs:
      result.add collectFreeVars(a)
  of irRecCall:
    for a in e.recArgs:
      result.add collectFreeVars(a)
  of irLoop:
    for init in e.loopInits:
      result.add collectFreeVars(init)
    result.add collectFreeVars(e.loopCond)
    if e.loopStep != nil:
      result.add collectFreeVars(e.loopStep)
    result.add collectFreeVars(e.loopBody)
    for inv in e.loopInvariants:
      result.add collectFreeVars(inv)
    if e.loopVariant != nil:
      result.add collectFreeVars(e.loopVariant)
  of irCast:
    result = collectFreeVars(e.castExpr)
  # Deduplicate and sort
  result = result.sorted
  var deduped: seq[string]
  for i, v in result:
    if i == 0 or v != result[i - 1]:
      deduped.add v
  result = deduped

func boundLetNames*(e: IRExpr): seq[string] =
  ## Names bound by the irLet chain that wraps this expression.
  ## Only those binders have the whole term in scope, so only those are the
  ## names an enclosing declare-fun would shadow.  Inner irLets bind below the
  ## chain and are deliberately not reported (see collectFreeVars).
  var cur = e
  while cur != nil and cur.kind == irLet:
    result.add cur.letName
    cur = cur.letBody

# ---------------------------------------------------------------------------
# Source bindings → nested SMT `let`
# ---------------------------------------------------------------------------
## Axiom does not implement binding semantics. A recorded binding's right-hand
## side is a *source-local fact* — the translator read this expression out of
## the subject and observed no loss inside it. Turning that fact into an SMT
## term is a different question: what `let` MEANS once emitted is SMT-LIB
## 2.7 §3.6.1's business, and Axiom never re-implements it by substituting the
## text. What this section decides is only WHICH names get a `let` and in WHAT
## ORDER the `let`s nest — a question about well-formedness, not about meaning.

type
  BindingNestVerdict* = enum
    bnvPlaced       ## every admitted binding has a position in the nest
    bnvRepeatedName ## two admitted bindings share a name, so neither selects a
                     ## single meaning — the ambiguity rule S also rejects
    bnvCycle        ## the admitted bindings cannot be ordered: each depends on
                     ## one that cannot be placed before it

  BindingNest* = object
    order*: seq[IRBinding]
      ## Outermost first. `order[0]` is the `let` closest to the script root.
    verdict*: BindingNestVerdict
    detail*: string  ## empty on bnvPlaced; names the offending binding otherwise

func admitBindings*(bindings: seq[IRBinding];
                    neededNames: seq[string]): seq[IRBinding] {.axiomDecision, raises: [].} =
  ## The bindings eligible to become `let`s.
  ##
  ## Two conditions, both about faithfulness to the subject:
  ##  - `lossFree`: the translator recorded that nothing inside the defining
  ##    expression was replaced by a placeholder, so the RHS is a fact about
  ##    this program and not about the translation that read it.
  ##  - the script's symbol universe names it. A binding nobody mentions costs
  ##    nothing and proves nothing; carrying it would only add surface the solver
  ##    has to be right about.
  ##
  ## Source order is preserved because `recordBinding` appends in translation
  ## order, which is what makes the emitted nest a deterministic function of
  ## the IR.
  for b in bindings:
    if b.lossFree and b.name in neededNames:
      result.add b

func firstRepeatedName(admitted: seq[IRBinding]): string {.raises: [].} =
  for i in 0 ..< admitted.len:
    for j in i + 1 ..< admitted.len:
      if admitted[i].name == admitted[j].name:
        return admitted[i].name
  ""

func bindingAwaitsUnplaced(b: IRBinding; names, placed: seq[string]): bool =
  ## Whether `b`'s right-hand side still names an admitted binding that has not
  ## been placed outside it yet.
  for n in collectFreeVars(b.value):
    if n in names and n notin placed:
      return true
  false

func planBindingNest*(bindings: seq[IRBinding];
                      neededNames: seq[string]): BindingNest {.axiomDecision, raises: [].} =
  ## Decide the SMT-LIB 3.6.1 nesting order for the admitted bindings.
  ##
  ## SMT-LIB 2.7 §3.6.1 defines `let` as *simultaneous*, so siblings cannot see
  ## each other and the emitter must nest one node per binding. Measured on
  ## Z3 4.13.3, merging them into one parallel group makes the solver answer
  ## `(error "… unknown constant bytesCount")` and still print a result on
  ## stdout, so the wrong form is indistinguishable from an answer unless the
  ## exit code is inspected.
  ##
  ## Order: a binding whose RHS names another admitted binding must sit OUTSIDE
  ## it, so that name is in scope for the RHS. Placement is a topological sort
  ## with source order as the tie-break, which keeps the script reproducible. A
  ## source-order forward reference is still placed correctly by that sort; a
  ## genuine cycle — including a binding that reads its own name — has no valid
  ## nest and is refused rather than emitted in some arbitrary order.
  result = BindingNest(order: @[], verdict: bnvPlaced, detail: "")
  let admitted = admitBindings(bindings, neededNames)
  if admitted.len == 0:
    return result

  let repeated = firstRepeatedName(admitted)
  if repeated.len > 0:
    return BindingNest(order: @[], verdict: bnvRepeatedName,
                       detail: "binding name '" & repeated & "' is recorded twice")

  var admittedNames: seq[string]
  for b in admitted:
    admittedNames.add b.name

  var remaining = admitted
  var placed: seq[string] = @[]
  while remaining.len > 0:
    var pick = -1
    for i in 0 ..< remaining.len:
      if remaining[i].name in collectFreeVars(remaining[i].value):
        return BindingNest(order: @[], verdict: bnvCycle,
                           detail: "binding '" & remaining[i].name & "' reads its own name")
      if not bindingAwaitsUnplaced(remaining[i], admittedNames, placed):
        pick = i
        break
    if pick < 0:
      return BindingNest(order: @[], verdict: bnvCycle,
                         detail: "binding '" & remaining[0].name &
                                 "' depends on a binding that cannot be placed before it")
    result.order.add remaining[pick]
    placed.add remaining[pick].name
    remaining.delete(pick)

func nestUnderBindings(bindings: seq[IRBinding]; body: IRExpr): IRExpr =
  ## Wrap `body` in one irLet node per binding, outermost first, so the existing
  ## irLet term lowering and the existing bound-name subtraction both apply
  ## unchanged instead of being re-derived here.
  result = body
  for i in countdown(bindings.high, 0):
    let b = bindings[i]
    result = IRExpr(kind: irLet, letName: b.name, letVal: b.value,
                    letBody: result, isCompileTime: b.isCompileTime)

# ---------------------------------------------------------------------------
# Sort inference
# ---------------------------------------------------------------------------

func inferVarSort*(varName: string, typ: IRType): string =
  ## Given a type-complete IRExpr variable, produce its SMT-LIB2 sort string.
  ## BitVec64 → (_ BitVec 64), Bool → Bool.
  ## Other types fall back to (_ BitVec 64) as a safe default for this slice.
  if typ == nil:
    return "(_ BitVec 64)"
  case typ.kind
  of irtBitVec64:
    "(_ BitVec 64)"
  of irtBool:
    "Bool"
  of irtList:
    "(Array (_ BitVec 64) " & inferVarSort(varName, typ.elemType) & ")"
  of irtString:
    "String"
  of irtEnum:
    "(_ BitVec 64)"
  of irtVariant:
    "(_ BitVec 64)"

# ---------------------------------------------------------------------------
# Canonical declare-fun ordering
# ---------------------------------------------------------------------------

type
  SmtFuncSig* = object
    ## Signature of an uninterpreted function symbol.  SMT-LIB2 declares these
    ## as (declare-fun <name> (<argSorts...>) <retSort>); argSorts.len == 0
    ## degenerates to the plain constant declaration for a free variable.
    funcName*: string
    argSorts*: seq[string]
    retSort*: string

func sortFuncSigs*(sigs: seq[SmtFuncSig]): seq[SmtFuncSig] =
  ## Insertion sort by name so the declaration block stays a deterministic
  ## function of the input set regardless of the collector's traversal order.
  for cur in sigs:
    var j = result.len
    while j > 0 and result[j - 1].funcName > cur.funcName:
      dec j
    result.insert(cur, j)

func smtDeclareFuns*(varNames: seq[string], varSorts: seq[string];
                      funcSigs: seq[SmtFuncSig] = @[]): string =
  ## Emit one declaration per var, in canonical (sorted) order by var name,
  ## then one declaration per uninterpreted function symbol sorted by name.
  ## varNames and varSorts must have the same length.
  var lines: seq[string]
  for i in 0 ..< varNames.len:
    lines.add("(declare-fun " & varNames[i] & " () " & varSorts[i] & ")")
  for sig in sortFuncSigs(funcSigs):
    var argList: seq[string]
    for a in sig.argSorts:
      argList.add a
    lines.add("(declare-fun " & sig.funcName & " (" & argList.join(" ") & ") " &
              sig.retSort & ")")
  lines.join("\n")

func logicAdmitsUninterpreted*(logic: SmtLogic): bool =
  ## Whether `logic` may declare uninterpreted function symbols or the Array
  ## sort.  Measured on Z3 4.13.3: QF_BV answers
  ## "logic does not support uninterpreted functions" and
  ## "unknown sort 'Array'" — and still prints a result on stdout, so an
  ## ill-sorted script is indistinguishable from a real answer unless the exit
  ## code is inspected.  Only QF_AUFBV admits both.
  logic == slQfAufbv

# ---------------------------------------------------------------------------
# Node counting (for referencedIrNodes)
# ---------------------------------------------------------------------------

func countIrNodes*(e: IRExpr): int =
  ## Count all IRExpr nodes in the tree (including the root).
  if e == nil: return 0
  result = 1
  case e.kind
  of irBinOp:
    result += countIrNodes(e.binLhs)
    result += countIrNodes(e.binRhs)
  of irUnaryOp:
    result += countIrNodes(e.unaryArg)
  of irIf:
    result += countIrNodes(e.ifCond)
    result += countIrNodes(e.ifThen)
    result += countIrNodes(e.ifElse)
  of irLet:
    result += countIrNodes(e.letVal)
    result += countIrNodes(e.letBody)
  of irCase:
    result += countIrNodes(e.caseScrutinee)
    for br in e.caseBranches:
      result += countIrNodes(br.body)
    if e.caseDefault != nil:
      result += countIrNodes(e.caseDefault)
  of irCall:
    for a in e.callArgs:
      result += countIrNodes(a)
  of irRecCall:
    for a in e.recArgs:
      result += countIrNodes(a)
  of irLoop:
    for init in e.loopInits:
      result += countIrNodes(init)
    result += countIrNodes(e.loopCond)
    if e.loopStep != nil:
      result += countIrNodes(e.loopStep)
    result += countIrNodes(e.loopBody)
    for inv in e.loopInvariants:
      result += countIrNodes(inv)
    if e.loopVariant != nil:
      result += countIrNodes(e.loopVariant)
  of irCast:
    result += countIrNodes(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit:
    discard

# ---------------------------------------------------------------------------
# Helper: find the IRType of a variable by name in a tree
# ---------------------------------------------------------------------------

func findVarTypeInTree*(e: IRExpr, name: string): IRType =
  ## Walk the IRExpr tree to find the type of a variable by name.
  ## Returns nil if the variable is not found.
  if e == nil: return nil
  if e.kind == irVar and e.varName == name:
    return e.varType
  case e.kind
  of irBinOp:
    let l = findVarTypeInTree(e.binLhs, name)
    if l != nil: return l
    return findVarTypeInTree(e.binRhs, name)
  of irUnaryOp:
    return findVarTypeInTree(e.unaryArg, name)
  of irIf:
    let c = findVarTypeInTree(e.ifCond, name)
    if c != nil: return c
    let t = findVarTypeInTree(e.ifThen, name)
    if t != nil: return t
    return findVarTypeInTree(e.ifElse, name)
  of irLet:
    let v = findVarTypeInTree(e.letVal, name)
    if v != nil: return v
    return findVarTypeInTree(e.letBody, name)
  of irCase:
    let s = findVarTypeInTree(e.caseScrutinee, name)
    if s != nil: return s
    for br in e.caseBranches:
      let b = findVarTypeInTree(br.body, name)
      if b != nil: return b
    if e.caseDefault != nil:
      return findVarTypeInTree(e.caseDefault, name)
  of irCall:
    for a in e.callArgs:
      let a = findVarTypeInTree(a, name)
      if a != nil: return a
    return nil
  of irRecCall:
    for a in e.recArgs:
      let a = findVarTypeInTree(a, name)
      if a != nil: return a
    return nil
  of irLoop:
    for init in e.loopInits:
      let i = findVarTypeInTree(init, name)
      if i != nil: return i
    let c = findVarTypeInTree(e.loopCond, name)
    if c != nil: return c
    if e.loopStep != nil:
      let s = findVarTypeInTree(e.loopStep, name)
      if s != nil: return s
    let b = findVarTypeInTree(e.loopBody, name)
    if b != nil: return b
    for inv in e.loopInvariants:
      let iv = findVarTypeInTree(inv, name)
      if iv != nil: return iv
    if e.loopVariant != nil:
      return findVarTypeInTree(e.loopVariant, name)
    return nil
  of irCast:
    return findVarTypeInTree(e.castExpr, name)
  of irLit, irFloatLit, irVar, irStringLit:
    return nil

# ---------------------------------------------------------------------------
# Uninterpreted function symbols
# ---------------------------------------------------------------------------

func exprSortType*(e: IRExpr): IRType =
  ## The IRType that fixes the SMT sort of a term.  irVar keeps its type in
  ## varType; every other node derives it from typ.
  if e == nil: return nil
  if e.kind == irVar and e.varType != nil: return e.varType
  e.typ

func smtFuncSigFor*(e: IRExpr): SmtFuncSig {.axiomDecision.} =
  ## Signature of the uninterpreted symbol an irCall node applies.
  ## Only `len` is admitted: it is left uninterpreted because the repo's sole
  ## array-length emitter (seq_len in ir_to_smt_chunk2) is defined on Seq, and
  ## Z3 rejects it on Array.  Leaving `len` uninterpreted over-approximates
  ## length, which can only make a proof harder to discharge — never turn an
  ## unsat into a sat.  Every other callee — and `len` at the wrong arity —
  ## yields an empty retSort, the sentinel funcSigUnsupported rejects.
  case e.callName
  of "len":
    if e.callArgs.len != 1:
      return SmtFuncSig(funcName: e.callName, argSorts: @[], retSort: "")
    SmtFuncSig(funcName: e.callName,
               argSorts: @[inferVarSort(e.callName, exprSortType(e.callArgs[0]))],
               retSort: inferVarSort(e.callName, e.typ))
  else:
    SmtFuncSig(funcName: e.callName, argSorts: @[], retSort: "")

func funcSigUnsupported*(sig: SmtFuncSig): bool =
  ## A signature the emitter cannot use: an unsupported callee (empty retSort)
  ## or a `len` applied to the wrong arity.
  sig.retSort.len == 0 or (sig.funcName == "len" and sig.argSorts.len != 1)

func sameSmtFuncSig*(a, b: SmtFuncSig): bool =
  a.funcName == b.funcName and a.retSort == b.retSort and a.argSorts == b.argSorts

func collectFuncSigs*(e: IRExpr; sigs: var seq[SmtFuncSig]; conflict: var string) =
  ## Gather the uninterpreted symbols used anywhere in the tree, first
  ## occurrence in traversal order wins.  Two occurrences that would need
  ## different signatures make the script ill-sorted, so that is reported as a
  ## conflict instead of being silently reconciled.
  if e == nil: return
  case e.kind
  of irCall:
    let sig = smtFuncSigFor(e)
    var seen = false
    for s in sigs:
      if s.funcName == sig.funcName:
        seen = true
        if not sameSmtFuncSig(s, sig) and conflict.len == 0:
          conflict = sig.funcName & " used with conflicting signatures"
    if not seen:
      sigs.add sig
    for a in e.callArgs:
      collectFuncSigs(a, sigs, conflict)
  of irBinOp:
    collectFuncSigs(e.binLhs, sigs, conflict)
    collectFuncSigs(e.binRhs, sigs, conflict)
  of irUnaryOp:
    collectFuncSigs(e.unaryArg, sigs, conflict)
  of irIf:
    collectFuncSigs(e.ifCond, sigs, conflict)
    collectFuncSigs(e.ifThen, sigs, conflict)
    collectFuncSigs(e.ifElse, sigs, conflict)
  of irLet:
    collectFuncSigs(e.letVal, sigs, conflict)
    collectFuncSigs(e.letBody, sigs, conflict)
  of irCase:
    collectFuncSigs(e.caseScrutinee, sigs, conflict)
    for br in e.caseBranches:
      collectFuncSigs(br.body, sigs, conflict)
    collectFuncSigs(e.caseDefault, sigs, conflict)
  of irRecCall:
    for a in e.recArgs:
      collectFuncSigs(a, sigs, conflict)
  of irLoop:
    for init in e.loopInits:
      collectFuncSigs(init, sigs, conflict)
    collectFuncSigs(e.loopCond, sigs, conflict)
    collectFuncSigs(e.loopStep, sigs, conflict)
    collectFuncSigs(e.loopBody, sigs, conflict)
    for inv in e.loopInvariants:
      collectFuncSigs(inv, sigs, conflict)
    collectFuncSigs(e.loopVariant, sigs, conflict)
  of irCast:
    collectFuncSigs(e.castExpr, sigs, conflict)
  of irLit, irFloatLit, irVar, irStringLit:
    discard

# ---------------------------------------------------------------------------
# Logic selection — the caller's decision, made visible
# ---------------------------------------------------------------------------

func declaresUninterpretedSymbol(e: IRExpr): bool {.raises: [].} =
  var sigs: seq[SmtFuncSig]
  var conflict: string
  collectFuncSigs(e, sigs, conflict)
  sigs.len > 0

func declaresArraySort(e: IRExpr): bool {.raises: [].} =
  ## Whether any free variable of `e` takes an Array sort.  Read through the
  ## same inferVarSort the declaration block uses, so this cannot disagree with
  ## what the script will actually declare.
  for name in collectFreeVars(e):
    if inferVarSort(name, findVarTypeInTree(e, name)).startsWith("(Array"):
      return true
  false

func selectLoweringLogic*(declared: SmtLogic; proposition: IRExpr): SmtLogic
    {.axiomDecision, raises: [].} =
  ## The CALLER's answer to: may this script declare `declared`, or must the
  ## declaration widen?  It never narrows — a logic that already admits
  ## uninterpreted symbols and the Array sort is returned untouched.
  ##
  ## `(set-logic ...)` states what the whole script is, and the pipeline is what
  ## composes the script, so the pipeline owns the declaration.  The lowerer
  ## still refuses a script its declared logic cannot carry — that is the
  ## invariant, and it is checked there so a caller that gets this wrong fails
  ## closed instead of shipping an ill-sorted script.  This proc exists so that
  ## widening is a decision with a stated reason, not a side effect of noticing
  ## an Array sort halfway through emission.
  ##
  ## QF_AUFBV admits every QF_BV term and adds exactly the two things QF_BV
  ## lacks, so widening cannot change the meaning of a script QF_BV already
  ## carried; it only reaches scripts QF_BV would have refused.
  if logicAdmitsUninterpreted(declared):
    return declared
  if declaresUninterpretedSymbol(proposition) or declaresArraySort(proposition):
    return slQfAufbv
  declared

# ---------------------------------------------------------------------------
# Simple SMT term lowering for the supported slice
# ---------------------------------------------------------------------------

func smtTermFor*(e: IRExpr; logic: SmtLogic): string {.axiomDecision.} =
  ## Lower a type-complete IRExpr to an SMT-LIB2 s-expression string.
  ## Supports only the constructs needed for this slice:
  ## irLit, irVar, irLet, boAnd, boEq, boGe, boLt, boSub, boAdd, boMul, boDiv,
  ## uoNot, irCall "len".
  ## All other constructs fail closed.
  if e == nil:
    return ""
  case e.kind
  of irLit:
    # int64 literal → SMT bitvector hex literal
    "#x" & toHex(e.litVal, 16)
  of irVar:
    e.varName
  of irLet:
    # SMT-LIB2 §3.6.1 binds let simultaneously, so a binding's right-hand side
    # cannot see its siblings.  irLet nests one node per binding, which is why
    # the nesting comes for free — but never merge siblings into one let group:
    # Z3 rejects the result with "unknown constant <name>".
    let valSmt = smtTermFor(e.letVal, logic)
    let bodySmt = smtTermFor(e.letBody, logic)
    if valSmt.len == 0 or bodySmt.len == 0:
      return ""
    "(let ((" & e.letName & " " & valSmt & ")) " & bodySmt & ")"
  of irBinOp:
    let lhsSmt = smtTermFor(e.binLhs, logic)
    let rhsSmt = smtTermFor(e.binRhs, logic)
    if lhsSmt.len == 0 or rhsSmt.len == 0:
      # A failed operand would otherwise be spliced in as an empty token and
      # yield a script that parses while meaning something else.
      return ""
    case e.binOp
    of boEq:
      "(= " & lhsSmt & " " & rhsSmt & ")"
    of boAnd:
      "(and " & lhsSmt & " " & rhsSmt & ")"
    of boOr:
      "(or " & lhsSmt & " " & rhsSmt & ")"
    of boGe:
      # Signed comparisons: Nim int64 comparisons are signed, and the IR marks
      # boGe/boLt as signed in axiom_ir (bvsge/bvslt).
      "(bvsge " & lhsSmt & " " & rhsSmt & ")"
    of boLt:
      "(bvslt " & lhsSmt & " " & rhsSmt & ")"
    of boLtU:
      # Unsigned strict comparison — operator-resident semantics; the u64
      # domain premise (aoTypeDerived) makes this the exact unsigned order.
      "(bvult " & lhsSmt & " " & rhsSmt & ")"
    of boSub:
      "(bvsub " & lhsSmt & " " & rhsSmt & ")"
    of boAdd:
      # bv64 add — bit-exact wrap; the coincidence-domain contract discharges
      # overflow inside the verified domain (base36 sizing contract §4.1).
      "(bvadd " & lhsSmt & " " & rhsSmt & ")"
    of boMul:
      # bv64 mul — bit-exact wrap, same coincidence-domain reasoning as boAdd.
      "(bvmul " & lhsSmt & " " & rhsSmt & ")"
    of boDiv:
      # Nim `div` truncates toward zero; SMT bvsdiv truncates toward zero —
      # bit-exact on the whole bv64 range (no domain restriction needed).
      "(bvsdiv " & lhsSmt & " " & rhsSmt & ")"
    else:
      # Unsupported binop → fail closed
      return ""
  of irUnaryOp:
    let argSmt = smtTermFor(e.unaryArg, logic)
    if argSmt.len == 0:
      return ""
    case e.unaryOp
    of uoNot:
      "(not " & argSmt & ")"
    else:
      # Unsupported unary op → fail closed
      return ""
  of irIf:
    # v1.3 bool-expression row: the collapsed Switch's ite. The condition is
    # a Bool term (comparison/combinator), the branches are BV64 values —
    # well-sorted by construction (the producer coerces bool branches to
    # 0/1). SMT-LIB2 `ite` is the exact image.
    let condSmt = smtTermFor(e.ifCond, logic)
    let thenSmt = smtTermFor(e.ifThen, logic)
    let elseSmt = smtTermFor(e.ifElse, logic)
    if condSmt.len == 0 or thenSmt.len == 0 or elseSmt.len == 0:
      return ""
    "(ite " & condSmt & " " & thenSmt & " " & elseSmt & ")"
  of irCall:
    let sig = smtFuncSigFor(e)
    if funcSigUnsupported(sig):
      return ""
    let argSmt = smtTermFor(e.callArgs[0], logic)
    if argSmt.len == 0:
      return ""
    "(" & sig.funcName & " " & argSmt & ")"
  else:
    # Unsupported construct → fail closed
    return ""

# ---------------------------------------------------------------------------
# Body binding — `define-fun <name>_impl` (DEBT#465 restoration, form 2)
# ---------------------------------------------------------------------------
## The classic emitter checks postconditions against the subject's actual body
## by emitting `(define-fun <name>_impl (params) ret <body>)` and querying
## `(assert (let ((result (<name>_impl params))) (not <query>)))`
## (ir_to_smt_chunk3:323-383). The typed path ports exactly that form: without
## it the proposition's `result` is an unconstrained 0-ary constant, which
## makes every postcondition query sat (DEBT#465 psFail regression). The
## binding is a refusal, never a silent drop: a body the typed term lowerer
## cannot express yields none and the caller keeps the classic emitter's
## script instead of a SAT one.

type
  ImplBinding = object
    defLine*: string    ## `(define-fun <name>_impl ((p sort) ...) ret <body>)`
    letPair*: string    ## `(result (<name>_impl p1 .. pn))` — the let pair

func planImplBinding(funcDef: IRFuncDef; logic: SmtLogic;
                     declaredUniverse: seq[string]): Option[ImplBinding] {.axiomDecision, raises: [].} =
  ## Plan the define-fun impl binding for `funcDef`'s body, or none when the
  ## binding cannot be emitted honestly: empty name/body, a parameter named
  ## `result` (it would shadow the let-bound query name), an impl symbol that
  ## collides with the script's universe, or a body construct the typed term
  ## lowerer does not support. Deterministic: the emitted text is a pure
  ## function of the funcDef and the logic.
  if funcDef.name.len == 0 or funcDef.body == nil:
    return none(ImplBinding)
  for p in funcDef.params:
    if p.name == "result":
      return none(ImplBinding)
  let implName = funcDef.name & "_impl"
  if implName in declaredUniverse:
    return none(ImplBinding)
  let bodySmt = smtTermFor(funcDef.body, logic)
  if bodySmt.len == 0:
    return none(ImplBinding)
  var defLine = "(define-fun " & implName & " ("
  var implCall = "(" & implName
  for i, p in funcDef.params:
    if i > 0:
      defLine.add(" ")
      implCall.add(" ")
    defLine.add("(" & p.name & " " & inferVarSort(p.name, p.ty) & ")")
    implCall.add(" " & p.name)
  defLine.add(") " & inferVarSort(implName, funcDef.retType) & "\n  " & bodySmt & ")")
  implCall.add(")")
  some(ImplBinding(defLine: defLine, letPair: "(result " & implCall & ")"))

# ---------------------------------------------------------------------------
# Main lowering primitive
# ---------------------------------------------------------------------------

func lowerObligationToSmt*(proposition: IRExpr,
                            context: SmtLoweringContext): SmtLoweringResult =
  ## Pure primitive: lower a type-complete IRExpr proposition to an
  ## executable SMT-LIB2 script with declare-fun declarations for free vars.
  ##
  ## Convention: (assert (not <term>)) then (check-sat).
  ## unsat = the proposition is valid (no counterexample).
  ## sat   = a counterexample exists.
  ##
  ## Fail-closed: unsupported constructs → empty + lostInformation + errorMsg.
  ## Never silently drop.
  if proposition == nil:
    return SmtLoweringResult(
      obligationKind: context.obligationKind,
      empty: true,
      lostInformation: true,
      errorMsg: "lowerObligationToSmt: nil proposition")

  # ── Source bindings → nested SMT `let` ────────────────────────────────────
  # The proposition names a binding (`bytesCount`) as a plain free variable; the
  # expression that defines it lives in IRFuncDef.recordedBindings, outside the
  # proposition, so nothing else can see it.  Planning the nest BEFORE anything
  # is typed means a dependency cycle or an ambiguous name refuses the whole
  # lowering rather than producing a script that reads one meaning and means
  # another.
  let nest = planBindingNest(context.sourceBindings, collectFreeVars(proposition))
  if nest.verdict != bnvPlaced:
    return SmtLoweringResult(
      obligationKind: context.obligationKind,
      empty: true,
      lostInformation: true,
      errorMsg: "lowerObligationToSmt: cannot order source bindings — " & nest.detail)

  let scoped = nestUnderBindings(nest.order, proposition)
  let boundNames = boundLetNames(scoped)

  # A fact is asserted at script scope, outside the `let` nest.  Asserting
  # `x == k` about a top-level free constant when the subject says `x` is a
  # let-bound name constrains a symbol the subject never quantified — that is a
  # proof about the wrong program, in the direction that manufactures `unsat`.
  # Refuse rather than emit it.
  for fact in context.semanticFacts:
    for name in collectFreeVars(fact.proposition):
      if name in boundNames:
        return SmtLoweringResult(
          obligationKind: context.obligationKind,
          empty: true,
          lostInformation: true,
          errorMsg: "lowerObligationToSmt: fact references let-bound name '" & name &
                    "', which is asserted outside the let scope")

  # Backfill types and elaborate sorts (idempotent, nil-safe).
  recomputeTyp(scoped)
  elaborateSorts(scoped)

  # INV-1: Free-var collection extended with semantic facts.
  # fvFacts = union of free vars from each fact proposition.
  var fvFacts: seq[string]
  for fact in context.semanticFacts:
    fvFacts.add collectFreeVars(fact.proposition)
  let fvProp = collectFreeVars(scoped)
  # Deduplicate the combined free-var universe (manual dedup, sorted).
  var allFreeVars = fvProp & fvFacts
  allFreeVars = allFreeVars.sorted
  var deduped: seq[string]
  for i, v in allFreeVars:
    if i == 0 or v != allFreeVars[i - 1]:
      deduped.add v
  allFreeVars = deduped

  # Drop names the irLet chain already binds.  An SMT `let` shadows a
  # same-named declare-fun, so keeping them would leave a dead declaration that
  # misstates the script's own symbol universe.  Subtracting after the union
  # also covers a let-bound name that a fact proposition references.  collectFreeVars
  # reads through the nest, so a binding's own right-hand side contributes the
  # names it reads (`bytes` above) without a second pass here.
  var declaredVars: seq[string]
  for v in allFreeVars:
    if v notin boundNames:
      declaredVars.add v
  allFreeVars = declaredVars

  # ── DEBT#465 body binding (form 2) ────────────────────────────────────────
  # When the caller carries the subject funcDef and the proposition reads
  # `result` (not already bound by the source-binding nest), plan the
  # `define-fun <name>_impl` binding. Refusal is fail-closed: a body outside
  # the typed slice must NOT degrade into an unconstrained `result` — that is
  # exactly the sat-everywhere regression this block prevents. The caller
  # keeps the classic emitter's script when this refuses.
  var impl = none(ImplBinding)
  var paramSorts: seq[(string, string)]
  if context.funcDef.isSome and "result" in allFreeVars and "result" notin boundNames:
    let fd = context.funcDef.get
    impl = planImplBinding(fd, context.logic, allFreeVars)
    if impl.isNone:
      return SmtLoweringResult(
        obligationKind: context.obligationKind,
        empty: true,
        lostInformation: true,
        errorMsg: "lowerObligationToSmt: 'result' requires body binding but the " &
                  "subject body is not expressible in the typed define-fun impl form")
    # A body free variable that is neither a parameter nor already declared
    # would make the define-fun body reference an unknown constant.
    var paramNames: seq[string]
    for p in fd.params:
      paramNames.add p.name
    for bv in collectFreeVars(fd.body):
      if bv notin paramNames and bv notin allFreeVars:
        return SmtLoweringResult(
          obligationKind: context.obligationKind,
          empty: true,
          lostInformation: true,
          errorMsg: "lowerObligationToSmt: subject body reads undeclared symbol '" &
                    bv & "'")
    # Facts are asserted at script scope, outside the let wrapper: a fact that
    # reads `result` would constrain the bare name, not the impl application —
    # a proof about the wrong program.
    for fact in context.semanticFacts:
      if "result" in collectFreeVars(fact.proposition):
        return SmtLoweringResult(
          obligationKind: context.obligationKind,
          empty: true,
          lostInformation: true,
          errorMsg: "lowerObligationToSmt: fact references let-bound 'result' " &
                    "(define-fun impl wrapper)")
    # The query applies the impl to the parameters, so every parameter joins
    # the script's symbol universe even when the proposition never reads it.
    # A parameter the proposition does read must agree with the tree-inferred
    # sort — a disagreement would be an ill-sorted script, not a proof.
    for p in fd.params:
      let paramSort = inferVarSort(p.name, p.ty)
      if p.name in allFreeVars:
        let treeSort = inferVarSort(p.name, findVarTypeInTree(scoped, p.name))
        if treeSort != paramSort:
          return SmtLoweringResult(
            obligationKind: context.obligationKind,
            empty: true,
            lostInformation: true,
            errorMsg: "lowerObligationToSmt: parameter '" & p.name &
                      "' sort disagrees between funcDef and proposition (" &
                      paramSort & " vs " & treeSort & ")")
      else:
        allFreeVars.add p.name
      paramSorts.add((p.name, paramSort))
    # `result` is let-bound by the wrapper now; declaring it as a 0-ary
    # constant would misstate the script's own symbol universe.
    let ri = allFreeVars.find("result")
    if ri >= 0:
      allFreeVars.delete(ri)
    allFreeVars.sort()
    var merged: seq[string]
    for i, v in allFreeVars:
      if i == 0 or v != allFreeVars[i - 1]:
        merged.add v
    allFreeVars = merged

  # Infer sorts for each free var (extended universe).
  var varSorts: seq[string]
  for name in allFreeVars:
    var paramSort = ""
    for (pn, ps) in paramSorts:
      if pn == name:
        paramSort = ps
        break
    if paramSort.len > 0:
      varSorts.add paramSort
    else:
      let vtyp = findVarTypeInTree(scoped, name)
      varSorts.add inferVarSort(name, vtyp)

  # Uninterpreted function symbols used by the proposition or any fact: each
  # needs an n-ary declare-fun, which the 0-ary emission above cannot express.
  var funcSigs: seq[SmtFuncSig]
  var sigConflict: string
  collectFuncSigs(scoped, funcSigs, sigConflict)
  for fact in context.semanticFacts:
    collectFuncSigs(fact.proposition, funcSigs, sigConflict)
  if impl.isSome:
    # The define-fun body's own uninterpreted symbols join the script's
    # universe — an uncollected body symbol would be an unknown constant.
    collectFuncSigs(context.funcDef.get.body, funcSigs, sigConflict)
  if sigConflict.len > 0:
    return SmtLoweringResult(
      obligationKind: context.obligationKind,
      empty: true,
      lostInformation: true,
      errorMsg: "lowerObligationToSmt: " & sigConflict)
  for sig in funcSigs:
    if funcSigUnsupported(sig):
      return SmtLoweringResult(
        obligationKind: context.obligationKind,
        empty: true,
        lostInformation: true,
        errorMsg: "lowerObligationToSmt: unsupported call '" & sig.funcName & "'")

  # The declared logic is the caller's authority, so a script that needs
  # uninterpreted symbols or the Array sort must fail closed rather than be
  # emitted under a logic that rejects them — Z3 would answer on stdout anyway.
  var needsUninterpreted = funcSigs.len > 0
  for s in varSorts:
    if s.startsWith("(Array"):
      needsUninterpreted = true
  if impl.isSome and declaresArraySort(context.funcDef.get.body):
    needsUninterpreted = true
  if needsUninterpreted and not logicAdmitsUninterpreted(context.logic):
    return SmtLoweringResult(
      obligationKind: context.obligationKind,
      empty: true,
      lostInformation: true,
      errorMsg: "lowerObligationToSmt: logic " & smtLogicName(context.logic) &
                " cannot declare uninterpreted symbols or Array; require QF_AUFBV")

  # A binding whose defining expression cannot be lowered is a refusal, not a
  # detail.  Emitting the proposition with the binding silently dropped would
  # turn `bytesCount` back into an unconstrained constant and prove a statement
  # the subject never made.
  for b in nest.order:
    if smtTermFor(b.value, context.logic).len == 0:
      return SmtLoweringResult(
        obligationKind: context.obligationKind,
        empty: true,
        lostInformation: true,
        errorMsg: "lowerObligationToSmt: source binding '" & b.name &
                  "' is not expressible in SMT-LIB2")

  # Lower the scoped proposition to an SMT term.
  let smtTerm = smtTermFor(scoped, context.logic)

  # Fail-closed: if lowering produced an empty term, the construct was unsupported.
  if smtTerm.len == 0:
    return SmtLoweringResult(
      obligationKind: context.obligationKind,
      empty: true,
      lostInformation: true,
      errorMsg: "lowerObligationToSmt: unsupported IRExpr kind in proposition")

  # Build symbolic operands (free var names).
  let symbolicOperands = allFreeVars

  # Count referenced IR nodes.
  let nodeCount = countIrNodes(scoped)

  # Assemble the SMT script.
  # Convention: (assert (not <term>)) then (check-sat).
  # unsat = proposition is valid; sat = counterexample exists.
  var lines: seq[string]
  lines.add("(set-logic " & smtLogicName(context.logic) & ")")
  lines.add("(set-option :rlimit " & $context.rlimit & ")")
  # declare-funs from extended universe (dedup) plus uninterpreted symbols.
  if allFreeVars.len > 0 or funcSigs.len > 0:
    lines.add(smtDeclareFuns(allFreeVars, varSorts, funcSigs))
  # DEBT#465: the define-fun impl body binding — the proposition's `result`
  # is substituted by `(<name>_impl params)` through the let wrapper below,
  # never left an unconstrained constant.
  if impl.isSome:
    lines.add(impl.get.defLine)
  # Fact asserts: (assert <fact-term>) for each semantic fact,
  # in canonical (already sorted) order. Fail-closed on empty term.
  for fact in context.semanticFacts:
    let factTerm = smtTermFor(fact.proposition, context.logic)
    if factTerm.len == 0:
      return SmtLoweringResult(
        obligationKind: context.obligationKind,
        empty: true,
        lostInformation: true,
        errorMsg: "lowerObligationToSmt: fact proposition unsupported")
    lines.add("(assert " & factTerm & ")")
  if impl.isSome:
    lines.add("(assert (let (" & impl.get.letPair & ") (not " & smtTerm & ")))")
  else:
    lines.add("(assert (not " & smtTerm & "))")
  lines.add("(check-sat)")
  let smtScript = lines.join("\n")

  SmtLoweringResult(
    obligationKind: context.obligationKind,
    symbolicOperands: symbolicOperands,
    referencedIrNodes: nodeCount,
    smtTerm: smtTerm,
    smtScript: smtScript,
    empty: false,
    lostInformation: false,
    errorMsg: "")

{.pop.}
