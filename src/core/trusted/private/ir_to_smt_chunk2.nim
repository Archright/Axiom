# nim-check: skip (include fragment — not an independent translation unit; verified via parent build)
axiomLayer "domain"
# ---------------------------------------------------------------------------
# Type → SMT-LIB2 sort
# ---------------------------------------------------------------------------

func irTypeToSmt*(t: IRType): string {.axiomImpl, raises: [].} =
  ## Map IRType to SMT-LIB2 sort string (sort-aware).
  ## For irtList, recurse into the element type to emit an Array sort.
  case t.kind
  of irtBitVec64: "(_ BitVec 64)"
  of irtBool:     "Bool"
  of irtList:     "(Array (_ BitVec 64) " & irTypeToSmt(t.elemType) & ")"
  of irtString:   "String"
  of irtEnum:     "(_ BitVec 64)"
  of irtVariant:  "(_ BitVec 64)"

# ---------------------------------------------------------------------------
# Literal helpers
# ---------------------------------------------------------------------------

func bvLiteral*(val: int64): string {.inline, axiomImpl, raises: [].} =
  ## Convert int64 to SMT-LIB2 bitvector hex literal (#x...).
  "#x" & toHex(val, 16)

func bvLiteralU64Hex*(val: uint64): string {.inline, axiomImpl, raises: [].} =
  ## u64-domain literal → its 16-digit bit-pattern hex (BV64 context: the
  ## signness is operator-resident, so the bit pattern IS the semantics).
  "#x" & toHex(cast[int64](val), 16)

func isU64DomainLit*(e: IRExpr): bool {.inline, raises: [].} =
  ## True when the literal node carries the u64-domain representation
  ## (nonzero `litU64` ⟺ active — the two-part form's disjoint domains).
  e != nil and e.kind == irLit and e.litU64 != 0'u64

func containsU64Lit*(e: IRExpr): bool {.raises: [].} =
  ## Subtree scan: does any literal node carry the u64-domain representation?
  ## Width-64 predicate forms are the only producers of such literals, so
  ## this marks the enclosing conjunction as a width-64 lowering context.
  if e == nil:
    return false
  case e.kind
  of irLit: isU64DomainLit(e)
  of irBinOp: containsU64Lit(e.binLhs) or containsU64Lit(e.binRhs)
  of irUnaryOp: containsU64Lit(e.unaryArg)
  of irLet: containsU64Lit(e.letVal) or containsU64Lit(e.letBody)
  of irIf:
    containsU64Lit(e.ifCond) or containsU64Lit(e.ifThen) or
      containsU64Lit(e.ifElse)
  of irCall, irRecCall:
    for a in e.callArgs:
      if containsU64Lit(a):
        return true
    false
  of irCast: containsU64Lit(e.castExpr)
  else: false

func unsignedCmpSym*(op: BinOpKind): string {.inline, raises: [].} =
  ## The unsigned variant of a comparison — signness is operator-resident,
  ## and the width-64 policy is unsigned end to end.
  case op
  of boLt: "bvult"
  of boLe: "bvule"
  of boGt: "bvugt"
  of boGe: "bvuge"
  else: ""

func width64ComparisonSmt(e: IRExpr; logic: SmtLogic): string {.raises: [].} =
  ## Width-64 comparison lowering. Unsigned operators (the signed policy does
  ## NOT apply — at p ≥ 2^63 a signed reading falsifies the premise → vacuous
  ## emission). The discharged caller-obligation shape — a `boAdd` on the
  ## non-literal side — lowers as the 65-bit zero-extend form against the
  ## width-accurate decimal constant (a BV64-native comparison is unsound:
  ## a wrapped `bvadd` cannot witness the mathematical overflow). The SMT
  ## operand order follows the IR operand order.
  let litSideIsLhs = isU64DomainLit(e.binLhs)
  if not litSideIsLhs and not isU64DomainLit(e.binRhs):
    # Context-only comparison (e.g. the `0 ≤ p` arm of a range premise): no
    # u64-domain literal to bound against — unsigned operators over ordinary
    # BV64 operands.
    return "(" & unsignedCmpSym(e.binOp) & " " &
      irExprToSmt(e.binLhs, logic = logic, u64Ctx = true) & " " &
      irExprToSmt(e.binRhs, logic = logic, u64Ctx = true) & ")"
  let litVal = if litSideIsLhs: e.binLhs.litU64 else: e.binRhs.litU64
  let other = if litSideIsLhs: e.binRhs else: e.binLhs
  if other != nil and other.kind == irBinOp and other.binOp == boAdd:
    let zext = "(bvadd ((_ zero_extend 1) " &
      irExprToSmt(other.binLhs, logic = logic, u64Ctx = true) &
      ") ((_ zero_extend 1) " &
      irExprToSmt(other.binRhs, logic = logic, u64Ctx = true) & "))"
    let bound = "(_ bv" & $litVal & " 65)"
    if litSideIsLhs:
      "(" & unsignedCmpSym(e.binOp) & " " & bound & " " & zext & ")"
    else:
      "(" & unsignedCmpSym(e.binOp) & " " & zext & " " & bound & ")"
  else:
    let litSmt = bvLiteralU64Hex(litVal)
    if litSideIsLhs:
      "(" & unsignedCmpSym(e.binOp) & " " & litSmt & " " &
        irExprToSmt(e.binRhs, logic = logic, u64Ctx = true) & ")"
    else:
      "(" & unsignedCmpSym(e.binOp) & " " &
        irExprToSmt(e.binLhs, logic = logic, u64Ctx = true) & " " & litSmt & ")"

func boolLiteral*(val: bool): string {.inline, axiomImpl, raises: [].} =
  ## Convert bool to SMT-LIB2 boolean literal.
  if val: "true" else: "false"

const FloatScaleFactor* = 100  ## Fixed-point scaling: float_val * 100 → int

func floatLiteral*(val: float64): string {.inline, axiomImpl, raises: [].} =
  ## Fixed-point Q16.16: float 5.0 → scaled int 500 → bvLiteral(500).
  ## Precision: 2 decimal places (FloatScaleFactor = 100).
  bvLiteral(int64(val * FloatScaleFactor))

# ---------------------------------------------------------------------------
# Expression → SMT-LIB2 s-expression
# ---------------------------------------------------------------------------

const stringCallMap = {
  "len":      "str.len",
  "substr":   "str.substr",
  "charAt":   "str.at",
  "contains": "str.contains",
  "prefix":   "str.prefixof",
  "suffix":   "str.suffixof",
  "concat":   "str.++",
  "indexOf":  "str.indexof",
}.toTable

func irExprToSmt*(e: IRExpr, indent: int = 0, logic: SmtLogic = slQfBv,
                  u64Ctx: bool = false): string {.raises: [].} =
  ## Convert IR expression tree to SMT-LIB2 s-expression string.
  ## `logic` selects sort-aware emission (e.g. QF_AUFBV seq_len/select).
  ## `u64Ctx` marks a width-64 lowering context — entered at and/or nodes
  ## whose subtree carries a u64-domain literal — under which comparisons
  ## lower unsigned (the signed policy falsifies premises at p ≥ 2^63).
  case e.kind
  of irLit:
    # Two-part literal form: nonzero `litU64` ⟺ u64-domain active (the bit
    # patterns coincide; the form is the domain evidence).
    if e.litU64 != 0'u64: bvLiteralU64Hex(e.litU64) else: bvLiteral(e.litVal)
  of irFloatLit:
    floatLiteral(e.floatVal)
  of irVar:
    e.varName
  of irLet:
    "(let ((" & e.letName & " " &
      irExprToSmt(e.letVal, logic = logic, u64Ctx = u64Ctx) & ")) " &
      irExprToSmt(e.letBody, logic = logic, u64Ctx = u64Ctx) & ")"
  of irIf:
    "(ite " & irExprToSmt(e.ifCond, logic = logic, u64Ctx = u64Ctx) & " " &
      irExprToSmt(e.ifThen, logic = logic, u64Ctx = u64Ctx) & " " &
      irExprToSmt(e.ifElse, logic = logic, u64Ctx = u64Ctx) & ")"
  of irCase:
    # Desugar case/match into nested (ite (= scrutinee pattern) body ...) form.
    # For variant types, use dynamic bit extraction based on tagBitWidth.
    let scrutSmt = irExprToSmt(e.caseScrutinee, logic = logic, u64Ctx = u64Ctx)
    let scrutTyp = if e.caseScrutinee != nil: e.caseScrutinee.typ else: nil
    let isVariant = scrutTyp != nil and scrutTyp.kind == irtVariant
    let scrutComp = if isVariant:
                      let tagHigh = 63
                      let tagLow = 64 - scrutTyp.tagBitWidth
                      "((_ extract " & $tagHigh & " " & $tagLow & ") " & scrutSmt & ")"
                    else: scrutSmt
    if e.caseBranches.len == 0:
      if e.caseDefault != nil:
        return irExprToSmt(e.caseDefault, logic = logic, u64Ctx = u64Ctx)
      return scrutSmt
    var smt = ""
    let hasDefault = e.caseDefault != nil
    let lastIdx = e.caseBranches.len - 1
    for i in countdown(lastIdx, 0):
      let br = e.caseBranches[i]
      # For variant types, patterns are tag ordinals (8-bit); for enums/BV64, full 64-bit.
      let pat = if isVariant: bvLiteral(br.pattern)
                else: bvLiteral(br.pattern)
      let body = irExprToSmt(br.body, logic = logic, u64Ctx = u64Ctx)
      if i == lastIdx and not hasDefault:
        # Last branch with no default: unconditional fallback.
        smt = body
      else:
        let elsePart = if smt.len > 0: smt
                       elif hasDefault: irExprToSmt(e.caseDefault, logic = logic, u64Ctx = u64Ctx)
                       else: body
        smt = "(ite (= " & scrutComp & " " & pat & ") " &
              body & " " & elsePart & ")"
    # Domain constraint: for enum-typed scrutinees, assert value ≤ max ordinal.
    # For variant-typed scrutinees, extract tag bits and assert ≤ max tag ordinal.
    if scrutTyp != nil and scrutTyp.kind == irtEnum and
        scrutTyp.enumOrdinals.len > 0:
      var maxOrd = scrutTyp.enumOrdinals[0]
      for o in scrutTyp.enumOrdinals:
        if o > maxOrd: maxOrd = o
      smt = "(ite (bvule " & scrutSmt & " (_ bv" & $maxOrd & " 64)) " & smt & " #x0000000000000000)"
    elif isVariant and scrutTyp.variantOrdinals.len > 0:
      var maxOrd = scrutTyp.variantOrdinals[0]
      for o in scrutTyp.variantOrdinals:
        if o > maxOrd: maxOrd = o
      let tagWidth = scrutTyp.tagBitWidth
      let tagHigh = 63
      let tagLow = 64 - tagWidth
      smt = "(ite (bvule ((_ extract " & $tagHigh & " " & $tagLow & ") " & scrutSmt & ") (_ bv" & $maxOrd & " " & $tagWidth & ")) " & smt & " #x0000000000000000)"
    smt
  of irCall:
    # QF_AUFBV sort-aware sequence/array operations.
    if logic == slQfAufbv and e.callName == "len" and e.callArgs.len == 1:
      "(seq_len " & irExprToSmt(e.callArgs[0], logic = logic, u64Ctx = u64Ctx) & ")"
    elif logic == slQfAufbv and e.callName == "[]" and e.callArgs.len >= 2:
      "(select " & irExprToSmt(e.callArgs[0], logic = logic, u64Ctx = u64Ctx) & " " &
        irExprToSmt(e.callArgs[1], logic = logic, u64Ctx = u64Ctx) & ")"
    # min/max special cases: emit (ite (bvslt ...) a b) / (ite (bvsgt ...) a b)
    elif e.callName == "min" and e.callArgs.len == 2:
      let a = irExprToSmt(e.callArgs[0], logic = logic, u64Ctx = u64Ctx)
      let b = irExprToSmt(e.callArgs[1], logic = logic, u64Ctx = u64Ctx)
      "(ite (bvslt " & a & " " & b & ") " & a & " " & b & ")"
    elif e.callName == "max" and e.callArgs.len == 2:
      let a = irExprToSmt(e.callArgs[0], logic = logic, u64Ctx = u64Ctx)
      let b = irExprToSmt(e.callArgs[1], logic = logic, u64Ctx = u64Ctx)
      "(ite (bvsgt " & a & " " & b & ") " & a & " " & b & ")"
    elif e.callName == "and" and e.callArgs.len == 2:
      # Sort-aware: Bool → and, BV64 → bvand
      let a0 = irExprToSmt(e.callArgs[0], logic = logic, u64Ctx = u64Ctx)
      let a1 = irExprToSmt(e.callArgs[1], logic = logic, u64Ctx = u64Ctx)
      if e.callArgs[0].typ != nil and e.callArgs[0].typ.kind == irtBitVec64:
        "(bvand " & a0 & " " & a1 & ")"
      else:
        "(and " & a0 & " " & a1 & ")"
    elif e.callName == "or" and e.callArgs.len == 2:
      # Sort-aware: Bool → or, BV64 → bvor
      let a0 = irExprToSmt(e.callArgs[0], logic = logic, u64Ctx = u64Ctx)
      let a1 = irExprToSmt(e.callArgs[1], logic = logic, u64Ctx = u64Ctx)
      if e.callArgs[0].typ != nil and e.callArgs[0].typ.kind == irtBitVec64:
        "(bvor " & a0 & " " & a1 & ")"
      else:
        "(or " & a0 & " " & a1 & ")"
    elif e.callName == "opCastToBool" and e.callArgs.len == 1:
      # BV64→Bool: true iff argument ≠ 0
      let argSmt = irExprToSmt(e.callArgs[0], logic = logic, u64Ctx = u64Ctx)
      "(not (= " & argSmt & " #x0000000000000000))"
    elif e.callName == "opCastToBv64" and e.callArgs.len == 1:
      # Bool→BV64: 1 if true, 0 if false
      let argSmt = irExprToSmt(e.callArgs[0], logic = logic, u64Ctx = u64Ctx)
      "(ite " & argSmt & " #x0000000000000001 #x0000000000000000)"
    else:
      let mappedName = stringCallMap.getOrDefault(e.callName, e.callName)
      var s = "(" & mappedName
      for a in e.callArgs:
        s.add(" " & irExprToSmt(a, logic = logic, u64Ctx = u64Ctx))
      s.add(")")
      s
  of irBinOp:
    # Width-64 context entry: an and/or subtree carrying a u64-domain literal
    # sets the context for its whole subtree (design closure — the `0 ≤ p`
    # range arm carries no u64 literal of its own, yet must lower unsigned).
    let childCtx = u64Ctx or containsU64Lit(e)
    if childCtx and e.binOp in {boLt, boLe, boGt, boGe}:
      width64ComparisonSmt(e, logic)
    else:
      let lhsSmt = irExprToSmt(e.binLhs, logic = logic, u64Ctx = childCtx)
      let rhsSmt = irExprToSmt(e.binRhs, logic = logic, u64Ctx = childCtx)
      let lhsTyp = if e.binLhs != nil: e.binLhs.typ else: nil
      let rhsTyp = if e.binRhs != nil: e.binRhs.typ else: nil
      let sym = binOpSmt(e.binOp, lhsTyp, rhsTyp)
      "(" & sym & " " & lhsSmt & " " & rhsSmt & ")"
  of irUnaryOp:
    # Defensive sort coercion: (not <bv64>) is invalid SMT-LIB2.
    # If elaborateSorts was not called upstream, auto-coerce here.
    if e.unaryOp == uoNot and e.unaryArg.typ != nil and
        e.unaryArg.typ.kind == irtBitVec64:
      let argSmt = irExprToSmt(e.unaryArg, logic = logic, u64Ctx = u64Ctx)
      "(not (= " & argSmt & " #x0000000000000000))"
    else:
      "(" & unaryOpSymbol(e.unaryOp) & " " &
        irExprToSmt(e.unaryArg, logic = logic, u64Ctx = u64Ctx) & ")"
  of irRecCall:
    # Fallback: self-recursive calls should be resolved by resolveRecCalls()
    # before emission. This emits a valid s-expression with a placeholder name.
    var s = "(__self__"
    for a in e.recArgs:
      s.add(" " & irExprToSmt(a, logic = logic, u64Ctx = u64Ctx))
    s.add(")")
    s
  of irLoop:
    const N = irLoopBmcBound
    case e.loopKind
    of lkFor:
      # For-loop: loopVars[0] is the index, loopVars[1..^1] are state accumulators.
      #   loopStep updates the index; loopBody updates the state.
      buildBmcMatrixFor(e.loopVars, e.loopInits, e.loopStep, e.loopBody, 0, N,
                        logic = logic, u64Ctx = u64Ctx)
    of lkWhile:
      # While-loop: all loopVars are state variables; loopBody updates them.
      # Wrap each iteration in (ite cond body prev) to model conditional execution.
      buildBmcMatrixWhile(e.loopVars, e.loopInits, e.loopCond, e.loopBody, 0, N,
                          logic = logic, u64Ctx = u64Ctx)
  of irCast:
    let innerSmt = irExprToSmt(e.castExpr, logic = logic, u64Ctx = u64Ctx)
    if e.castTo.kind == irtBool:
      "(not (= " & innerSmt & " #x0000000000000000))"
    elif e.castTo.kind == irtBitVec64:
      "(ite " & innerSmt & " #x0000000000000001 #x0000000000000000)"
    else:
      innerSmt
  of irStringLit:
    "\"" & e.stringVal.replace("\\", "\\\\").replace("\"", "\\\"") & "\""

# ---------------------------------------------------------------------------
# BMC matrix builders
# ---------------------------------------------------------------------------

func buildBmcMatrixFor(
    loopVars: seq[string], loopInits: seq[IRExpr],
    loopStep: IRExpr, loopBody: IRExpr,
    k: int, maxBound: int, logic: SmtLogic = slQfBv,
    u64Ctx: bool = false): string {.raises: [].} =
  if k == maxBound:
    return genTerminationRef(loopVars, k)

  let prev = buildSubstMap(loopVars, k)
  let inner = buildBmcMatrixFor(loopVars, loopInits, loopStep, loopBody, k+1,
                                maxBound, logic, u64Ctx)

  let stepBind = block:
    var ss = "(let ("
    for i, v in loopVars:
      if i > 0: ss.add(") (")
      if i == 0:
        if loopStep != nil:
          ss.add(v & "_" & $(k+1) & " " & irExprToSmt(substVarsInExpr(loopStep, prev), logic = logic, u64Ctx = u64Ctx))
        else:
          ss.add(v & "_" & $(k+1) & " " & v & "_" & $k)
      else:
        if loopBody != nil:
          ss.add(v & "_" & $(k+1) & " " & irExprToSmt(substVarsInExpr(loopBody, prev), logic = logic, u64Ctx = u64Ctx))
        else:
          ss.add(v & "_" & $(k+1) & " " & v & "_" & $k)
    ss.add("))")
    ss

  if k == 0:
    let initBind = block:
      var ss = "(let ("
      for i, v in loopVars:
        if i > 0: ss.add(") (")
        ss.add(v & "_0 " & irExprToSmt(loopInits[i], logic = logic, u64Ctx = u64Ctx))
      ss.add("))")
      ss
    initBind & "\n  " & stepBind & "\n  " & inner & ")"
  else:
    stepBind & "\n  " & inner & ")"

func buildBmcMatrixWhile(
    loopVars: seq[string], loopInits: seq[IRExpr],
    loopCond: IRExpr, loopBody: IRExpr,
    k: int, maxBound: int, logic: SmtLogic = slQfBv,
    u64Ctx: bool = false): string {.raises: [].} =
  if k == maxBound:
    return genTerminationRef(loopVars, k)

  let prev = buildSubstMap(loopVars, k)
  let inner = buildBmcMatrixWhile(loopVars, loopInits, loopCond, loopBody, k+1,
                                  maxBound, logic, u64Ctx)
  let condStr = irExprToSmt(substVarsInExpr(loopCond, prev), logic = logic, u64Ctx = u64Ctx)

  let stepBind = block:
    var ss = "(let ("
    for i, v in loopVars:
      if i > 0: ss.add(") (")
      if loopBody != nil:
        ss.add(v & "_" & $(k+1) & " (ite " & condStr & " " &
               irExprToSmt(substVarsInExpr(loopBody, prev), logic = logic, u64Ctx = u64Ctx) & " " &
               v & "_" & $k & ")")
      else:
        ss.add(v & "_" & $(k+1) & " (ite " & condStr & " " &
               v & "_" & $k & " " & v & "_" & $k & ")")
    ss.add("))")
    ss

  if k == 0:
    let initBind = block:
      var ss = "(let ("
      for i, v in loopVars:
        if i > 0: ss.add(") (")
        ss.add(v & "_0 " & irExprToSmt(loopInits[i], logic = logic, u64Ctx = u64Ctx))
      ss.add("))")
      ss
    initBind & "\n  " & stepBind & "\n  " & inner & ")"
  else:
    stepBind & "\n  " & inner & ")"

# ---------------------------------------------------------------------------
# Domain constraint collection (top-level assertions for Z3)
# ---------------------------------------------------------------------------

func collectExprDomainConstraints*(e: IRExpr, res: var seq[string]) {.raises: [].} =
  ## Walk IR tree and collect domain constraint assertions for enum/variant typed irCase scrutinees.
  if e == nil: return
  case e.kind
  of irCase:
    let scrutTyp = if e.caseScrutinee != nil: e.caseScrutinee.typ else: nil
    if scrutTyp != nil and scrutTyp.kind == irtEnum and scrutTyp.enumOrdinals.len > 0:
      var maxOrd = scrutTyp.enumOrdinals[0]
      for o in scrutTyp.enumOrdinals:
        if o > maxOrd: maxOrd = o
      res.add("(assert (bvule " & irExprToSmt(e.caseScrutinee) & " (_ bv" & $maxOrd & " 64)))")
    elif scrutTyp != nil and scrutTyp.kind == irtVariant and scrutTyp.variantOrdinals.len > 0:
      var maxOrd = scrutTyp.variantOrdinals[0]
      for o in scrutTyp.variantOrdinals:
        if o > maxOrd: maxOrd = o
      let tagWidth = scrutTyp.tagBitWidth
      let tagHigh = 63
      let tagLow = 64 - tagWidth
      res.add("(assert (bvule ((_ extract " & $tagHigh & " " & $tagLow & ") " & irExprToSmt(e.caseScrutinee) & ") (_ bv" & $maxOrd & " " & $tagWidth & ")))")
    for br in e.caseBranches:
      collectExprDomainConstraints(br.body, res)
    collectExprDomainConstraints(e.caseDefault, res)
  of irCall:
    for a in e.callArgs:
      collectExprDomainConstraints(a, res)
  of irRecCall:
    for a in e.callArgs:
      collectExprDomainConstraints(a, res)
  of irBinOp:
    collectExprDomainConstraints(e.binLhs, res)
    collectExprDomainConstraints(e.binRhs, res)
  of irUnaryOp:
    collectExprDomainConstraints(e.unaryArg, res)
  of irIf:
    collectExprDomainConstraints(e.ifCond, res)
    collectExprDomainConstraints(e.ifThen, res)
    collectExprDomainConstraints(e.ifElse, res)
  of irLet:
    collectExprDomainConstraints(e.letVal, res)
    collectExprDomainConstraints(e.letBody, res)
  of irLoop:
    for init in e.loopInits:
      collectExprDomainConstraints(init, res)
    collectExprDomainConstraints(e.loopBody, res)
    for inv in e.loopInvariants:
      collectExprDomainConstraints(inv, res)
    collectExprDomainConstraints(e.loopVariant, res)
  of irCast:
    collectExprDomainConstraints(e.castExpr, res)
  else: discard

func collectDomainConstraints*(f: IRFuncDef): seq[string] {.raises: [].} =
  ## Collect all domain constraint assertions from a function's IR body.
  result = @[]
  collectExprDomainConstraints(f.body, result)


