# nim-check: skip (include fragment — not an independent translation unit; verified via parent build)
axiomLayer "domain"
# ---------------------------------------------------------------------------
# Function definition → SMT-LIB2 define-fun
# ---------------------------------------------------------------------------
## NOTE: This module uses ORIGINAL (non-canonical) IR for SMT-LIB2 generation.
## Canonicalization is for hash computation only (see axiom_ir.canonicalizeIR).

func irFuncDefToSmt*(f: IRFuncDef): string {.raises: [].} =
  ## Convert IR function definition to SMT-LIB2 (define-fun[-rec] ...) form.
  ## Uses resolveRecCalls to correctly emit self-recursive references.
  let resolvedBody = resolveRecCalls(f.body, f.name)
  elaborateSorts(resolvedBody)
  let funKeyword = if f.isRecursive: "define-fun-rec" else: "define-fun"
  var s = "(" & funKeyword & " " & f.name & " ("
  for i, p in f.params:
    if i > 0: s.add(" ")
    s.add("(" & p.name & " " & irTypeToSmt(p.ty) & ")")
  s.add(") " & irTypeToSmt(f.retType) & "\n  ")
  s.add(irExprToSmt(resolvedBody))
  s.add(")")
  s

# ---------------------------------------------------------------------------
# Overflow check assertions — standard SMT-LIB2 (no Z3-specific extensions)
# ---------------------------------------------------------------------------
#
# Z3 4.x does NOT have built-in bvadd_no_overflow / bvmul_no_overflow
# predicates in its SMT-LIB2 parser.  We define them via (define-fun)
# using only standard QF_BV operations.
#
# Two-argument predicates:
#   no_overflow_add(a, b)  — signed a+b has no positive overflow
#   no_underflow_add(a, b) — signed a+b has no negative underflow
#   no_overflow_mul(a, b)  — signed a*b has no overflow (with MIN_INT edge fix)
#   no_underflow_mul(a, b) — equivalent to no_overflow_mul for signed two's complement
#
# Reference:
#   - Z3 SMT-LIB2 bitvector theory: standard QF_BV operations only
#   - Signed overflow detection: sign-of-operand vs sign-of-result comparison
#   - bvsdiv multiplication check with MIN_INT*-1 edge case exclusion

const bvZero64 = "#x0000000000000000"
const bvMinInt64 = "#x8000000000000000"
const bvMinusOne = "#xFFFFFFFFFFFFFFFF"

const bvU64Max65* = "(_ bv18446744073709551615 65)"
  ## 2^64−1 at the 65-bit zero-extend sort. Decimal `bv` literals ONLY:
  ## SMT-LIB hex literal width is 4× the hex-digit count, so no hex notation
  ## exists for a 65-bit value (17 hex digits = 68 bits = 2^65−1).

func generateOverflowDefines*(): seq[string] {.axiomImpl, raises: [].} =
  ## Generate SMT-LIB2 (define-fun) declarations for overflow predicates.
  ## These must be emitted before any assertions that reference them.
  ## The width-64 define carries the zero_extend INSIDE it: the sound
  ## no-overflow encoding is a 65-bit zero-extend of both operands followed
  ## by an unsigned `bvule` against the width-accurate constant (a BV64-native
  ## comparison is unsound — a wrapped `bvadd` cannot witness the mathematical
  ## overflow), and the signed comparison policy does NOT apply (at p ≥ 2^63
  ## a signed reading falsifies the premises → vacuous emission).
  @[
    "(define-fun no_overflow_add ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool\n" &
    "  (let ((sum (bvadd a b)))\n" &
    "    (not (or\n" &
    "      (and (bvsgt a " & bvZero64 & ") (bvsgt b " & bvZero64 & ") (bvslt sum " & bvZero64 & "))\n" &
    "      (and (bvslt a " & bvZero64 & ") (bvslt b " & bvZero64 & ") (bvsgt sum " & bvZero64 & "))))))",
    "(define-fun no_underflow_add ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool\n" &
    "  (let ((sum (bvadd a b)))\n" &
    "    (not (and (bvslt a " & bvZero64 & ") (bvslt b " & bvZero64 & ") (bvsgt sum " & bvZero64 & ")))))",
    "(define-fun no_overflow_add_u64 ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool\n" &
    "  (bvule (bvadd ((_ zero_extend 1) a) ((_ zero_extend 1) b)) " & bvU64Max65 & "))",
    "(define-fun no_overflow_mul ((_a (_ BitVec 64)) (_b (_ BitVec 64))) Bool\n" &
    "  (let ((p (bvmul _a _b)))\n" &
    "    (and (or (= _a " & bvZero64 & ") (= _b " & bvZero64 & ") (= (bvsdiv p _a) _b))\n" &
    "         (not (and (= _a " & bvMinInt64 & ") (= _b " & bvMinusOne & ")))\n" &
    "         (not (and (= _a " & bvMinusOne & ") (= _b " & bvMinInt64 & "))))))",
    "(define-fun no_underflow_mul ((_a (_ BitVec 64)) (_b (_ BitVec 64))) Bool\n" &
    "  (let ((p (bvmul _a _b)))\n" &
    "    (and (or (= _a " & bvZero64 & ") (= _b " & bvZero64 & ") (= (bvsdiv p _a) _b))\n" &
    "         (not (and (= _a " & bvMinInt64 & ") (= _b " & bvMinusOne & ")))\n" &
    "         (not (and (= _a " & bvMinusOne & ") (= _b " & bvMinInt64 & "))))))",
    "(define-fun no_overflow_sub ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool\n" &
    "  (let ((diff (bvsub a b)))\n" &
    "    (not (and (bvsgt a " & bvZero64 & ") (bvslt b " & bvZero64 & ") (bvslt diff " & bvZero64 & ")))))",
    "(define-fun no_underflow_sub ((a (_ BitVec 64)) (b (_ BitVec 64))) Bool\n" &
    "  (let ((diff (bvsub a b)))\n" &
    "    (not (and (bvslt a " & bvZero64 & ") (bvsgt b " & bvZero64 & ") (bvsgt diff " & bvZero64 & ")))))"
  ]

func generateOverflowAssertions*(e: AnnotatedExpr): seq[string] {.axiomImpl, raises: [].} =
  ## Generate SMT-LIB2 overflow/underflow/wrap assertions for an annotated expression.
  ##
  ## References the define-fun helpers from `generateOverflowDefines()`:
  ## - oNoOverflow on boAdd → no_overflow_add + no_underflow_add
  ## - oNoOverflow on boMul → no_overflow_mul
  ## - oNoUnderflow         → *_no_underflow variants
  ## - oNoWrap              → unsigned wrap guard (bvuge)
  if e.overflow == ocNone or e.expr.kind != irBinOp:
    return @[]
  let lhs = irExprToSmt(e.expr.binLhs)
  let rhs = irExprToSmt(e.expr.binRhs)
  case e.expr.binOp
  of boAdd:
    case e.overflow
    of oNoOverflow:
      @["(assert (no_overflow_add " & lhs & " " & rhs & "))",
        "(assert (no_underflow_add " & lhs & " " & rhs & "))"]
    of oNoOverflowU64:
      @["(assert (no_overflow_add_u64 " & lhs & " " & rhs & "))"]
    of oNoUnderflow:
      @["(assert (no_underflow_add " & lhs & " " & rhs & "))"]
    of oNoWrap:
      @["(assert (bvuge (bvadd " & lhs & " " & rhs & ") " & lhs & "))"]
    of ocNone: @[]
  of boMul:
    case e.overflow
    of oNoOverflow:
      @["(assert (no_overflow_mul " & lhs & " " & rhs & "))"]
    of oNoOverflowU64:
      # 130-bit zero-extend: the product of two 65-bit values needs the
      # width-accurate sort (a 65-bit bvmul would wrap — unsound)
      @["(assert (bvule (bvmul ((_ zero_extend 66) " & lhs & ") ((_ zero_extend 66) " &
        rhs & ")) (_ bv18446744073709551615 130)))"]
    of oNoUnderflow:
      @["(assert (no_underflow_mul " & lhs & " " & rhs & "))"]
    of oNoWrap:
      @["(assert (bvuge (bvmul " & lhs & " " & rhs & ") " & lhs & "))"]
    of ocNone: @[]
  of boSub:
    case e.overflow
    of oNoOverflow:
      @["(assert (no_overflow_sub " & lhs & " " & rhs & "))",
        "(assert (no_underflow_sub " & lhs & " " & rhs & "))"]
    of oNoOverflowU64:
      # 65-bit zero-extend: ≤ 2^64−1 ⟺ no borrow (the width-64 sub
      # None-condition), sound against the 65-bit unsigned wrap
      @["(assert (bvule (bvsub ((_ zero_extend 1) " & lhs & ") ((_ zero_extend 1) " &
        rhs & ")) " & bvU64Max65 & "))"]
    of oNoUnderflow:
      @["(assert (no_underflow_sub " & lhs & " " & rhs & "))"]
    of oNoWrap:
      @["(assert (bvuge (bvsub " & lhs & " " & rhs & ") " & lhs & "))"]
    of ocNone: @[]
  else: @[]

# ---------------------------------------------------------------------------
# Overflow obligations — goal form (obligation_semantics.md §3.8)
# ---------------------------------------------------------------------------
# `generateOverflowAssertions` above is the legacy assumption-style emission
# (assert-wrapped, unit-test pinned, NOT used by the verification pipeline).
# The pipeline uses the goal form below: each checked-arithmetic node
# (boAdd/boSub/boMul — exactly the ops Nim raises OverflowDefect on) yields a
# side condition that is conjoined with the postcondition inside the negated
# BMC query. The solver must therefore DERIVE every no-overflow condition from
# the asserted preconditions; if it cannot, the query is sat and the function
# is NOT verified — overflow can never be silently assumed.

func overflowPredicate*(e: AnnotatedExpr): string {.axiomImpl, raises: [].} =
  ## The no-overflow side condition of one annotated node as a raw SMT term
  ## (no `assert` wrapper). Empty when the node carries no annotation.
  if e.overflow == ocNone or e.expr == nil or e.expr.kind != irBinOp:
    return ""
  let lhs = irExprToSmt(e.expr.binLhs)
  let rhs = irExprToSmt(e.expr.binRhs)
  case e.expr.binOp
  of boAdd:
    case e.overflow
    of oNoOverflow:
      "(and (no_overflow_add " & lhs & " " & rhs & ") (no_underflow_add " &
        lhs & " " & rhs & "))"
    of oNoOverflowU64:
      "(no_overflow_add_u64 " & lhs & " " & rhs & ")"
    of oNoUnderflow: "(no_underflow_add " & lhs & " " & rhs & ")"
    of oNoWrap: "(bvuge (bvadd " & lhs & " " & rhs & ") " & lhs & ")"
    of ocNone: ""
  of boMul:
    case e.overflow
    of oNoOverflow: "(no_overflow_mul " & lhs & " " & rhs & ")"
    of oNoOverflowU64:
      "(bvule (bvmul ((_ zero_extend 66) " & lhs & ") ((_ zero_extend 66) " &
        rhs & ")) (_ bv18446744073709551615 130))"
    of oNoUnderflow: "(no_underflow_mul " & lhs & " " & rhs & ")"
    of oNoWrap: "(bvuge (bvmul " & lhs & " " & rhs & ") " & lhs & ")"
    of ocNone: ""
  of boSub:
    case e.overflow
    of oNoOverflow:
      "(and (no_overflow_sub " & lhs & " " & rhs & ") (no_underflow_sub " &
        lhs & " " & rhs & "))"
    of oNoOverflowU64:
      "(bvule (bvsub ((_ zero_extend 1) " & lhs & ") ((_ zero_extend 1) " &
        rhs & ")) " & bvU64Max65 & ")"
    of oNoUnderflow: "(no_underflow_sub " & lhs & " " & rhs & ")"
    of oNoWrap: "(bvuge (bvsub " & lhs & " " & rhs & ") " & lhs & ")"
    of ocNone: ""
  else: ""

func collectOverflowGoalsWalk(e: IRExpr; widthBits: int; acc: var seq[string]) {.raises: [].} =
  ## Pre-order walk: one overflow predicate per checked-arithmetic node.
  ## `widthBits` selects the annotation width (0 = the narrow/signed policy,
  ## 64 = the width-64 zero-extend branch) — the goal collection itself is
  ## form-agnostic.
  if e == nil:
    return
  case e.kind
  of irBinOp:
    let pred = overflowPredicate(annotateOverflow(e, widthBits))
    if pred.len > 0:
      acc.add(pred)
    collectOverflowGoalsWalk(e.binLhs, widthBits, acc)
    collectOverflowGoalsWalk(e.binRhs, widthBits, acc)
  of irUnaryOp:
    collectOverflowGoalsWalk(e.unaryArg, widthBits, acc)
  of irIf:
    collectOverflowGoalsWalk(e.ifCond, widthBits, acc)
    collectOverflowGoalsWalk(e.ifThen, widthBits, acc)
    collectOverflowGoalsWalk(e.ifElse, widthBits, acc)
  of irLet:
    collectOverflowGoalsWalk(e.letVal, widthBits, acc)
    collectOverflowGoalsWalk(e.letBody, widthBits, acc)
  of irCase:
    collectOverflowGoalsWalk(e.caseScrutinee, widthBits, acc)
    for br in e.caseBranches:
      collectOverflowGoalsWalk(br.body, widthBits, acc)
    if e.caseDefault != nil:
      collectOverflowGoalsWalk(e.caseDefault, widthBits, acc)
  of irCall:
    for a in e.callArgs:
      collectOverflowGoalsWalk(a, widthBits, acc)
  of irRecCall:
    for a in e.recArgs:
      collectOverflowGoalsWalk(a, widthBits, acc)
  of irLoop:
    for i in e.loopInits:
      collectOverflowGoalsWalk(i, widthBits, acc)
    collectOverflowGoalsWalk(e.loopCond, widthBits, acc)
    if e.loopStep != nil:
      collectOverflowGoalsWalk(e.loopStep, widthBits, acc)
    collectOverflowGoalsWalk(e.loopBody, widthBits, acc)
    for inv in e.loopInvariants:
      collectOverflowGoalsWalk(inv, widthBits, acc)
    if e.loopVariant != nil:
      collectOverflowGoalsWalk(e.loopVariant, widthBits, acc)
  of irCast:
    collectOverflowGoalsWalk(e.castExpr, widthBits, acc)
  else:
    discard  # irLit, irFloatLit, irVar, irStringLit — leaves

func collectOverflowGoals*(f: IRFuncDef): seq[string] {.raises: [].} =
  ## Overflow obligations of `f`'s body as raw SMT terms. Arithmetic inside
  ## preconditions is not walked: preconditions are solver input, not goals.
  collectOverflowGoalsWalk(f.body, 0, result)

func collectOverflowGoals*(f: IRFuncDef; widthBits: int): seq[string] {.raises: [].} =
  ## Width-aware overload: width-64 subjects emit the zero-extend `bvule`
  ## goal forms (the signed policy is inapplicable at width 64).
  collectOverflowGoalsWalk(f.body, widthBits, result)

# ---------------------------------------------------------------------------
# Complete SMT-LIB2 script
# ---------------------------------------------------------------------------

const maxTokenLen* = 64

func generateStringAxioms*(varNames: seq[string]): seq[string] {.raises: [].} =
  for v in varNames:
    result.add("(assert (>= (str.len " & v & ") 0))")
    result.add("(assert (<= (str.len " & v & ") " & $maxTokenLen & "))")

func irToSmtScript*(f: IRFuncDef, includeOverflowDefines: bool = false,
                    logic: SmtLogic = slQfBv): string {.raises: [].} =
  ## Generate a complete, self-contained SMT-LIB2 script.
  ##
  ## `logic` parameterizes the `(set-logic ...)` command (default QF_BV — zero
  ## change to existing behavior). The overflow helper define-fun
  ## declarations are emitted after set-logic so that assertions produced
  ## by `generateOverflowAssertions` are valid (only valid under QF_BV).
  ##
  ## Output:
  ##   (set-logic QF_BV)
  ##   (set-option :rlimit 500000)
  ##   [overflow define-fun helpers if requested]
  ##   (declare-fun <external> (<param-types>) <ret-type>) ...  ← Phase 4: external calls
  ##   (declare-fun <param> () <sort>) ...
  ##   (define-fun <name>_impl ((<param> <sort>) ...) <ret-sort> <body>)
  ##   [precondition asserts]
  ##   (assert (let ((result (<name>_impl <param> ...))) (not <postCond>)))
  ##   (check-sat)
  ## No abstract `declare-fun <name>` is emitted (QF_BV forbids uninterpreted
  ## functions of arity > 0); postconditions bind `result` to the impl call.
  ## AGENT-L: Defense-in-depth Defect guard — {.raises: []} blocks CatchableError
  ## but NOT Defect-derived exceptions (IndexDefect, NilAccessDefect, etc.).
  try:
    # Defense-in-depth: backfill typ on deserialized IR trees (CAS cache path).
    # parseIRExpr does NOT set typ; recomputeTyp is idempotent and nil-safe.
    # Preconditions/postconditions are serialized alongside the body and
    # deserialize with nil types too — without backfill, binOpSmt would emit
    # bvand/bvor for logical boAnd/boOr on deserialized spec exprs (sort error).
    recomputeTyp(f.body)
    elaborateSorts(f.body)
    for pre in f.preConditions:
      recomputeTyp(pre)
      elaborateSorts(pre)
    for post in f.postConditions:
      recomputeTyp(post)
      elaborateSorts(post)
    if not validateIrTypes(f):
      return ""
    var lines: seq[string]
    lines.add("(set-logic " & smtLogicName(logic) & ")")
    lines.add("(set-option :rlimit " & $z3DeterministicBudget & ")")
    if includeOverflowDefines:
      for d in generateOverflowDefines():
        lines.add(d)
    # Phase 4.5: QF_AUFBV UF preamble — declare seq_len over Array sort.
    # ir_to_smt_chunk2.nim emits (seq_len <arr>) for len calls under
    # QF_AUFBV. QF_AUFBV permits UFs (unlike QF_BV), but Z3 requires an
    # explicit sort signature; without this declaration the Array-sort
    # argument triggers a sort mismatch. QF_BV forbids arity>0 UFs, so the
    # declaration is emitted only for QF_AUFBV.
    if logic == slQfAufbv:
      lines.add("(declare-fun seq_len ((Array (_ BitVec 64) (_ BitVec 64))) (_ BitVec 64))")
    # Phase 5: Emit declarations for external function calls in the body.
    # Without these, Z3 rejects undefined functions (e.g. clamp, clampMax).
    # For enum-returning functions, emit define-fun with bit masking instead
    # of declare-fun, so Z3 knows the return value is bounded.
    let module = buildIRModule(@[f])
    for decl in module.externalDeclarations:
      if decl.retType.kind == irtEnum and decl.retType.enumOrdinals.len > 0:
        var maxOrd = decl.retType.enumOrdinals[0]
        for o in decl.retType.enumOrdinals:
          if o > maxOrd: maxOrd = o
        let tagBitWidth = computeTagBitWidth(maxOrd)
        let tagHigh = 63
        let tagLow = 64 - tagBitWidth
        let zeroExtendBits = 64 - tagBitWidth
        var defLine = "(define-fun " & decl.name & " ("
        for i, pt in decl.paramTypes:
          if i > 0: defLine &= " "
          defLine &= "(" & ("_p" & $i) & " " & irTypeToSmt(pt) & ")"
        defLine &= ") " & irTypeToSmt(decl.retType)
        if zeroExtendBits > 0:
          defLine &= " ((_ zero_extend " & $zeroExtendBits & ") ((_ extract " & $tagHigh & " " & $tagLow & ") _p0)))"
        else:
          defLine &= " ((_ extract " & $tagHigh & " " & $tagLow & ") _p0))"
        lines.add(defLine)
      else:
        var declLine = "(declare-fun " & decl.name & " ("
        for i, pt in decl.paramTypes:
          if i > 0: declLine &= " "
          declLine &= irTypeToSmt(pt)
        declLine &= ") " & irTypeToSmt(decl.retType) & ")"
        lines.add(declLine)
    for p in f.params:
      lines.add("(declare-fun " & p.name & " () " & irTypeToSmt(p.ty) & ")")
    # Generate string axioms for any string-typed parameters
    var strParams: seq[string]
    for p in f.params:
      if p.ty.kind == irtString:
        strParams.add(p.name)
    if strParams.len > 0:
      for a in generateStringAxioms(strParams):
        lines.add(a)
    # Step 1: Define implementation function (f_impl)
    let implName = f.name & "_impl"
    var implDef = "(define-fun " & implName & " ("
    for i, p in f.params:
      if i > 0: implDef &= " "
      implDef &= "(" & p.name & " " & irTypeToSmt(p.ty) & ")"
    implDef &= ") " & irTypeToSmt(f.retType) & "\n  "
    implDef &= irExprToSmt(f.body, logic = logic)
    implDef &= ")"
    lines.add(implDef)

    # Step 2: Domain constraints
    for dc in collectDomainConstraints(f):
      lines.add(dc)

    # Step 3: Precondition assertions (Task 34)
    for pre in f.preConditions:
      if pre != nil:
        lines.add("(assert " & irExprToSmt(pre, logic = logic) & ")")

    # Step 4: BMC call expression — `(<name>_impl <params>)`.
    # NOTE: no abstract `(declare-fun <name> ...)` is emitted. QF_BV forbids
    # uninterpreted functions (Z3: "logic does not support uninterpreted
    # functions"), so the postcondition is checked directly against the
    # define-fun implementation via the `result` let-binding in Step 6 —
    # identical semantics, no UF declaration.
    var implCall = "(" & implName
    for p in f.params:
      implCall.add(" " & p.name)
    implCall.add(")")

    # Step 5: Vacuous guard — no postconditions AND no overflow goals → skip.
    # Overflow obligations (§3.8) are checked jointly with the postcondition
    # query; a body without postconditions still gets a goals-only query.
    let overflowGoals = if includeOverflowDefines: collectOverflowGoals(f)
                        else: @[]

    # Step 6: BMC negation — the postcondition AND every overflow obligation
    # must be derived by the solver from the asserted preconditions (Step 3);
    # any unprovable conjunct makes the query sat, i.e. NOT verified.
    var postConj = ""
    for pc in f.postConditions:
      if pc == nil: continue
      let pcSmt = irExprToSmt(pc, logic = logic)
      if postConj.len == 0:
        postConj = pcSmt
      else:
        postConj = "(and " & postConj & " " & pcSmt & ")"
    var query = postConj
    for g in overflowGoals:
      query = if query.len == 0: g
              else: "(and " & query & " " & g & ")"
    if query.len == 0:
      return ""
    if postConj.len > 0:
      # Bind `result` to the implementation's return value so postconditions
      # (which reference `irVar("result")` from contract_synthesis) resolve.
      lines.add("(assert (let ((result " & implCall & ")) (not " & query & ")))")
    else:
      lines.add("(assert (not " & query & "))")
    lines.add("(check-sat)")
    lines.join("\n")
  except CatchableError:
    ""

# ---------------------------------------------------------------------------
# P4: Obligation-IR consumer overload — explicit obligations → SMT assertions
# ---------------------------------------------------------------------------

func irToSmtWithObligations*(f: IRFuncDef, obligations: seq[VerificationObligation];
                               logic: SmtLogic = slQfBv): string {.raises: [].} =
  ## Generate SMT-LIB2 assertions for each obligation's predicate.
  ## Unlike `irToSmtScript`, this function does NOT gate on postConditions.len==0.
  ## Each obligation is emitted as a standalone `(assert <predicate>)` line.
  ## An empty obligations list returns `""` — the caller (P3 pipeline) routes
  ## explicitly based on the generator's 4-way result.
  if obligations.len == 0:
    return ""
  var lines: seq[string]
  lines.add("(set-logic " & smtLogicName(logic) & ")")
  lines.add("(set-option :rlimit " & $z3DeterministicBudget & ")")
  for obl in obligations:
    lines.add("(assert " & obl.predicate & ")")
  lines.add("(check-sat)")
  lines.join("\n")
