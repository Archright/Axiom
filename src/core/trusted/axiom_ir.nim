import core/trusted/layer_declaration
axiomLayer "trusted.core.ir"

{.push raises: [].}
## Axiom Core IR — minimal, pure-functional intermediate representation.
##
## Sits between Nim AST and SMT-LIB2 / Lean 4 output.
## Both backends derive from this single normalization point,
## eliminating semantic divergence.
##
## Design: all types are value-like (ref only where sharing is needed),
## all procs are `func` (no side effects), variant-object expression tree.

import std/strutils
import std/options
import std/tables
import core/parsers/safe_parsers
import core/results
import core/gate/hash_types
import core/trusted/axiom_ir_types
import core/trusted/symbol_table_types
export axiom_ir_types

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------
# IRType / IRTypeKind + constructors live in axiom_ir_types (leaf) to break
# the axiom_ir ↔ symbol_table_types import cycle. Re-exported above.

type
  BinOpKind* = enum
    ## Bit-vector arithmetic (wrapping / signed)
    boAdd          ## bvadd
    boSub          ## bvsub
    boMul          ## bvmul
    boDiv          ## bvsdiv (signed)
    boRem          ## bvsrem (signed, Nim `mod` / `%`)
    boRemU         ## bvurem (unsigned, Nim `%%`)  — SemanticProfileV1 modulo(aa)
    ## Bit-vector shift (UNSUPPORTED in SemanticProfileV1 — spShiftUnsupported)
    boShl          ## bvshl (unsupported in V1)
    boShr          ## bvlshr (unsupported in V1)
    ## Sentinel for unknown/unsupported operators
    boUnsupported  ## explicit unsupported marker
    ## Bit-vector comparison (signed)
    boLt           ## bvslt
    boLe           ## bvsle
    boGt           ## bvsgt
    boGe           ## bvsge
    ## Boolean / equality
    boAnd          ## logical and
    boOr           ## logical or
    boEq           ## equality (uninterpreted)
    ## Unsigned comparison — operator-resident signedness: the producer's
    ## unsigned intent survives the IR (domain premise [0, 2^64) rides with
    ## the type-derived range machinery — rust_certified_subset.md §4 boLtU)
    boLtU          ## bvult / BitVec.ult — append-only wire ordinal 16

  UnaryOpKind* = enum
    uoNot          ## boolean not
    uoBvNot        ## bvnot (bitwise)
    uoBvNeg        ## bvneg (arithmetic negate)

# ---------------------------------------------------------------------------
# Expressions (variant object)
# ---------------------------------------------------------------------------

  LoopKind* = enum
    lkFor   ## Finite execution: loopCond = (loopIdx < loopEnd)
    lkWhile ## Conditional execution: loopCond = user-defined condition

  IRExprKind* = enum
    irLit          ## Integer literal
    irFloatLit     ## Float literal (fixed-point scaled to int64 during SMT encoding)
    irVar          ## Variable reference
    irLet          ## Let-binding: let name = val in body
    irIf           ## If-then-else
    irCase         ## Case / pattern match (on BitVec64 value)
    irCall         ## Named function call
    irBinOp        ## Binary operation
    irUnaryOp      ## Unary operation
    irRecCall      ## Self-recursive call (no function name needed)
    irLoop         ## Loop with state-passing frame
    irStringLit    ## String literal
    irCast         ## Explicit type coercion (e.g. BV64→Bool)

  CaseBranch* = object
    pattern*: int64       ## Match value
    body*: IRExpr         ## Branch expression

  IRExpr* {.acyclic.} = ref object
    typ*: IRType  ## Construction-time type (recomputeTyp backfills for deserialized)
    case kind*: IRExprKind
    of irLit:
      litVal*: int64
        ## signed domain [−2^63, 2^63−1] — the canonical signed reading
      litU64*: uint64
        ## u64 domain [2^63, 2^64−1] — the ONLY carrier for values ≥ 2^63;
        ## nonzero ⟺ the u64-domain representation is active (a value ≥ 2^63
        ## is never reinterpreted into `litVal`)
    of irFloatLit:
      floatVal*: float64    ## Raw float value; scaled to int64 during SMT encoding
    of irVar:
      varName*: string
      varType*: IRType
    of irLet:
      letName*: string
      letVal*: IRExpr
      letBody*: IRExpr
      isCompileTime*: bool
    of irIf:
      ifCond*: IRExpr
      ifThen*: IRExpr
      ifElse*: IRExpr
    of irCase:
      caseScrutinee*: IRExpr
      caseBranches*: seq[CaseBranch]
      caseDefault*: IRExpr   ## Optional default branch (nil = exhaustive)
    of irCall:
      callName*: string
      callArgs*: seq[IRExpr]
    of irBinOp:
      binOp*: BinOpKind
      binLhs*: IRExpr
      binRhs*: IRExpr
    of irUnaryOp:
      unaryOp*: UnaryOpKind
      unaryArg*: IRExpr
    of irRecCall:
      recArgs*: seq[IRExpr]
    of irLoop:
      loopKind*: LoopKind
      loopVars*: seq[string]       ## State variables captured by the loop
      loopInits*: seq[IRExpr]      ## Initial values for each state variable
      loopCond*: IRExpr            ## Execution condition
      loopStep*: IRExpr            ## Index increment expression (For only, nil for While)
      loopBody*: IRExpr            ## Loop body returning next state tuple
      loopInvariants*: seq[IRExpr] ## OPTIONAL: future k-induction invariants
      loopVariant*: IRExpr         ## OPTIONAL: well-founded metric for while-loop termination (nil = fallback to fuel)
    of irStringLit:
      stringVal*: string
    of irCast:
      castExpr*: IRExpr
      castFrom*: IRType
      castTo*: IRType

# ---------------------------------------------------------------------------
# Function definitions
# ---------------------------------------------------------------------------

  IRFuncParam* = object
    name*: string
    ty*: IRType
    constraint*: Option[IRExpr]  ## precondition predicate (refinement type)

  IRBinding* = object
    ## One `let`/`var`/`const` binding the translator read out of a source
    ## declaration section, kept only when the binding is trustworthy enough to
    ## carry meaning: `lossFree` states that nothing inside `value` was replaced
    ## by a placeholder during conversion.
    ##
    ## `anchor` is provenance, not identity. The canonical AST adapter carries no
    ## source location, so the translator records the traversal position of the
    ## declaring statement instead; a caller that has a real location can compare
    ## against it without the IR claiming to own one.
    name*: string
    value*: IRExpr
    anchor*: string
    isCompileTime*: bool
    lossFree*: bool

  IRFuncDef* = object
    name*: string
    params*: seq[IRFuncParam]
    retType*: IRType
    body*: IRExpr
    isRecursive*: bool
    preConditions*: seq[IRExpr]  ## function-level preconditions
    postConditions*: seq[IRExpr]  ## function-level postconditions
    symbolTable*: SymbolTable     ## symbol table for params/lets/loop state
    ## WP4-j.2 translation evidence (metadata — intentionally excluded from
    ## serializeIRFuncDef/canonicalizeIR, hence from computeIrDigest).
    ## true default: a hand-constructed IRFuncDef has no source to lose from.
    translationLossFree*: bool = true
    bindingUniverseComplete*: bool = false  ## assembled by the external materializer from binding correspondence and opacity
    ## Scoped translation evidence — same exclusion as the two fields above.
    ## `translationLossFree` is one bit for a whole function, so a loss in one
    ## unreachable statement makes a perfectly faithful binding region look
    ## unfaithful. These three fields carry the same observation at the
    ## granularity a caller actually certifies.
    recordedBindings*: seq[IRBinding] = @[]
      ## Every `let`/`var`/`const` binding the translator read, loss-free or not.
      ## Order is the translator's own traversal order, which is deterministic.
    propositionRegionLossFree*: bool = false
      ## No loss was recorded inside any guard/loop condition, and no statement
      ## form was dropped whole. A dropped statement is not a coarser observation
      ## of the function — its subtree is never traversed, so a binding inside it
      ## is absent from `recordedBindings` rather than marked lossy, and name
      ## uniqueness over the survivors would then certify a shadowed name.
      ## false default: nobody has certified this region, and unverifiable is not
      ## loss-free.
    lossOutsideBindingRegions*: bool = false
      ## The function lost something outside every region this channel certifies.
      ## The bindings and guards are then faithful while the obligation SET may
      ## not be complete: the lost statement can hide another guard. This is a
      ## coverage statement, never a rejection reason.

  IRFuncDecl* = object
    ## 외부 함수 선언 — SMT (declare-fun ...)의 메타데이터
    name*: string
    paramTypes*: seq[IRType]
    retType*: IRType

  IRModule* = object
    ## 모듈 수준 IR 컨테이너 — 종속성 매니페스트 포함
    name*: string
    functions*: seq[IRFuncDef]
    externalDeclarations*: seq[IRFuncDecl]  ## 외부 함수 사전 선언
    recursiveGroup*: seq[IRFuncDef]          ## 재귀 함수 정의 그룹

# ---------------------------------------------------------------------------
# Overflow annotation (embedded in IR for ir_to_smt.nim)
# ---------------------------------------------------------------------------

  OverflowCheck* = enum
    ocNone            ## No overflow check
    oNoOverflow       ## Assert no signed overflow on this operation
    oNoUnderflow      ## Assert no signed underflow
    oNoWrap           ## Assert no unsigned wrap
    oNoOverflowU64    ## Assert no width-64 unsigned overflow — the 65-bit
                      ## zero-extend + bvule form (signed policy inapplicable:
                      ## at p ≥ 2^63 a signed reading falsifies the premises →
                      ## vacuous emission)

  AnnotatedExpr* = object
    expr*: IRExpr
    overflow*: OverflowCheck
    widthBits*: int = 0
      ## semantic width the annotation was derived from (64 → the width-64
      ## encoding branch); 0 = width-agnostic (the narrow/signed policy)

# ---------------------------------------------------------------------------
# Builtin function registry (metadata for known builtins)
# ---------------------------------------------------------------------------

type
  BuiltinMeta* = object
    arity*: int
    retType*: IRType

func irBuiltins*(): Table[string, BuiltinMeta] {.inline.} =
  ## Registry of known builtin functions and their metadata.
  ## Returns a fresh Table each call (IRType is a ref, cannot be const).
  {"opCastToBool": BuiltinMeta(arity: 1, retType: irTypeBool()),
   "opCastToBv64": BuiltinMeta(arity: 1, retType: irTypeBitVec64()),
   "min":          BuiltinMeta(arity: 2, retType: irTypeBitVec64()),
   "max":          BuiltinMeta(arity: 2, retType: irTypeBitVec64()),
   "and":          BuiltinMeta(arity: 2, retType: irTypeBool()),
   "or":           BuiltinMeta(arity: 2, retType: irTypeBool()),
  }.toTable

func isIrBuiltin*(name: string): bool {.inline.} =
  ## Check if a function name is a known builtin.
  name in ["opCastToBool", "opCastToBv64", "min", "max", "and", "or"]

# ---------------------------------------------------------------------------
# Canonical IR serialization (deterministic, for digest computation)
# ---------------------------------------------------------------------------
# serializeIRType lives in axiom_ir_types (leaf), re-exported above.

# Forward declaration for mutual recursion with serializeExprSeq.
func serializeIRExpr*(e: IRExpr): string {.raises: [].}

func serializeExprSeq*(es: seq[IRExpr]): string {.raises: [].} =
  ## Serialize a sequence of expressions with unambiguous delimiters.
  var s = "["
  for i, e in es:
    if i > 0: s.add(",")
    s.add(serializeIRExpr(e))
  s.add("]")
  s

func escapeSLITPayload(payload: string): string {.raises: [].} =
  ## Backslash-escape the two characters that would otherwise make a
  ## `SLIT(payload)` text ambiguous: the escape character itself, and the `)`
  ## that terminates the node.
  ##
  ## `SLIT` carries no length prefix and no quoting, so without this the first
  ## `)` inside any payload ends the node early and the remaining payload text
  ## is re-read as IR syntax. Escaping belongs here, at the serializer, because
  ## this is the only point where the payload's true boundaries are still known;
  ## every consumer — IR round-trip, Lean parity, gate digests — reads the
  ## emitted text verbatim.
  result = newStringOfCap(payload.len)
  for ch in payload:
    case ch
    of '\\': result.add("\\\\")
    of ')': result.add("\\)")
    else: result.add(ch)

func serializeIRExpr*(e: IRExpr): string {.raises: [].} =
  ## Deterministic canonical serialization of an IRExpr.
  if e == nil: return "NIL"
  case e.kind
  of irLit:
    if e.litU64 != 0'u64: "LU(" & $e.litU64 & ")"
    else: "L(" & $e.litVal & ")"
  of irFloatLit:
    "FL(" & $e.floatVal & ")"
  of irVar:
    "V(" & e.varName & ":" & serializeIRType(e.varType) & ")"
  of irLet:
    if e.isCompileTime:
      "CLET(" & e.letName & "=" & serializeIRExpr(e.letVal) &
        "|" & serializeIRExpr(e.letBody) & ")"
    else:
      "LET(" & e.letName & "=" & serializeIRExpr(e.letVal) &
        "|" & serializeIRExpr(e.letBody) & ")"
  of irIf:
    "IF(" & serializeIRExpr(e.ifCond) & "?" &
      serializeIRExpr(e.ifThen) & ":" & serializeIRExpr(e.ifElse) & ")"
  of irCase:
    var s = "CASE(" & serializeIRExpr(e.caseScrutinee) & "{"
    for i, br in e.caseBranches:
      if i > 0: s.add(",")
      s.add($br.pattern & "=>" & serializeIRExpr(br.body))
    if e.caseDefault != nil:
      s.add("|D=>" & serializeIRExpr(e.caseDefault))
    s.add("})")
    s
  of irCall:
    "CALL(" & e.callName & "," & serializeExprSeq(e.callArgs) & ")"
  of irBinOp:
    "BIN(" & $e.binOp & "," & serializeIRExpr(e.binLhs) &
      "," & serializeIRExpr(e.binRhs) & ")"
  of irUnaryOp:
    "UN(" & $e.unaryOp & "," & serializeIRExpr(e.unaryArg) & ")"
  of irRecCall:
    "REC(" & serializeExprSeq(e.recArgs) & ")"
  of irLoop:
    var s = "LOOP(" & $e.loopKind & ",["
    for i, v in e.loopVars:
      if i > 0: s.add(",")
      s.add(v)
    s.add("],[")
    for i, init in e.loopInits:
      if i > 0: s.add(",")
      s.add(serializeIRExpr(init))
    s.add("],")
    s.add(serializeIRExpr(e.loopCond))
    s.add(",")
    if e.loopStep != nil:
      s.add(serializeIRExpr(e.loopStep))
    else:
      s.add("NIL")
    s.add(",")
    s.add(serializeIRExpr(e.loopBody))
    s.add(",[")
    for i, inv in e.loopInvariants:
      if i > 0: s.add(",")
      s.add(serializeIRExpr(inv))
    s.add("],")
    if e.loopVariant != nil:
      s.add(serializeIRExpr(e.loopVariant))
    else:
      s.add("NIL")
    s.add(")")
    s
  of irStringLit:
    "SLIT(" & escapeSLITPayload(e.stringVal) & ")"
  of irCast:
    "CAST(" & serializeIRExpr(e.castExpr) & "," &
      serializeIRType(e.castFrom) & "->" & serializeIRType(e.castTo) & ")"

func serializeParams*(ps: seq[IRFuncParam]): string {.raises: [].} =
  ## Serialize function parameters.
  ## Format: [name:TYPE|CONSTRAINT,...] where |CONSTRAINT is only present when set.
  var s = "["
  for i, p in ps:
    if i > 0: s.add(",")
    s.add(p.name & ":" & serializeIRType(p.ty))
    if p.constraint.isSome:
      s.add("|" & serializeIRExpr(p.constraint.get))
  s.add("]")
  s

func serializeIRFuncDef*(f: IRFuncDef): string {.raises: [].} =
  ## Deterministic canonical serialization of an IRFuncDef.
  result = "FUNC(" & f.name & "(" & serializeParams(f.params) & "):" &
    serializeIRType(f.retType) & "=" & serializeIRExpr(f.body) &
    ",rec=" & $f.isRecursive
  if f.preConditions.len > 0:
    result &= ",preconds=" & serializeExprSeq(f.preConditions)
  if f.postConditions.len > 0:
    result &= ",postconds=" & serializeExprSeq(f.postConditions)
  result.add(")")

# ---------------------------------------------------------------------------
# IR canonical normalization pass (deterministic hashing)
# ---------------------------------------------------------------------------

func hasLocalBindings(e: IRExpr): bool {.raises: [].} =
  if e == nil: return false
  case e.kind
  of irLet, irLoop: true
  of irIf: hasLocalBindings(e.ifCond) or hasLocalBindings(e.ifThen) or hasLocalBindings(e.ifElse)
  of irCase:
    if hasLocalBindings(e.caseScrutinee): return true
    for br in e.caseBranches:
      if hasLocalBindings(br.body): return true
    hasLocalBindings(e.caseDefault)
  of irCall:
    for a in e.callArgs:
      if hasLocalBindings(a): return true
    false
  of irBinOp: hasLocalBindings(e.binLhs) or hasLocalBindings(e.binRhs)
  of irUnaryOp: hasLocalBindings(e.unaryArg)
  of irRecCall:
    for a in e.recArgs:
      if hasLocalBindings(a): return true
    false
  of irCast: hasLocalBindings(e.castExpr)
  of irLit, irFloatLit, irVar, irStringLit: false

func isCommutativeBinOp(k: BinOpKind): bool {.inline.} =
  k in {boAdd, boMul, boEq, boAnd, boOr}

func canonicalizeExpr(e: IRExpr; renameMap: var Table[string, string];
                      counter: var int): IRExpr {.raises: [].} =
  if e == nil: return nil
  result = IRExpr(typ: e.typ, kind: e.kind)
  case e.kind
  of irLit:
    result.litVal = e.litVal
    result.litU64 = e.litU64
  of irFloatLit:
    result.floatVal = e.floatVal
  of irVar:
    result.varName = renameMap.getOrDefault(e.varName, e.varName)
    result.varType = e.varType
  of irLet:
    let newName = "v" & $counter
    inc counter
    result.letName = newName
    renameMap[e.letName] = newName
    result.letVal = canonicalizeExpr(e.letVal, renameMap, counter)
    result.letBody = canonicalizeExpr(e.letBody, renameMap, counter)
    result.isCompileTime = e.isCompileTime
  of irIf:
    result.ifCond = canonicalizeExpr(e.ifCond, renameMap, counter)
    result.ifThen = canonicalizeExpr(e.ifThen, renameMap, counter)
    result.ifElse = canonicalizeExpr(e.ifElse, renameMap, counter)
  of irCase:
    result.caseScrutinee = canonicalizeExpr(e.caseScrutinee, renameMap, counter)
    result.caseBranches = @[]
    for br in e.caseBranches:
      result.caseBranches.add(CaseBranch(pattern: br.pattern,
        body: canonicalizeExpr(br.body, renameMap, counter)))
    result.caseDefault = canonicalizeExpr(e.caseDefault, renameMap, counter)
  of irCall:
    result.callName = e.callName
    result.callArgs = @[]
    for a in e.callArgs:
      result.callArgs.add(canonicalizeExpr(a, renameMap, counter))
  of irBinOp:
    result.binOp = e.binOp
    let lhs = canonicalizeExpr(e.binLhs, renameMap, counter)
    let rhs = canonicalizeExpr(e.binRhs, renameMap, counter)
    if isCommutativeBinOp(e.binOp) and
       not hasLocalBindings(lhs) and not hasLocalBindings(rhs):
      if serializeIRExpr(lhs) > serializeIRExpr(rhs):
        result.binLhs = rhs
        result.binRhs = lhs
      else:
        result.binLhs = lhs
        result.binRhs = rhs
    else:
      result.binLhs = lhs
      result.binRhs = rhs
  of irUnaryOp:
    result.unaryOp = e.unaryOp
    result.unaryArg = canonicalizeExpr(e.unaryArg, renameMap, counter)
  of irRecCall:
    result.recArgs = @[]
    for a in e.recArgs:
      result.recArgs.add(canonicalizeExpr(a, renameMap, counter))
  of irLoop:
    result.loopKind = e.loopKind
    result.loopVars = @[]
    for v in e.loopVars:
      let newName = "v" & $counter
      inc counter
      result.loopVars.add(newName)
      renameMap[v] = newName
    result.loopInits = @[]
    for init in e.loopInits:
      result.loopInits.add(canonicalizeExpr(init, renameMap, counter))
    result.loopCond = canonicalizeExpr(e.loopCond, renameMap, counter)
    result.loopStep = canonicalizeExpr(e.loopStep, renameMap, counter)
    result.loopBody = canonicalizeExpr(e.loopBody, renameMap, counter)
    result.loopInvariants = @[]
    for inv in e.loopInvariants:
      result.loopInvariants.add(canonicalizeExpr(inv, renameMap, counter))
    result.loopVariant = canonicalizeExpr(e.loopVariant, renameMap, counter)
  of irStringLit:
    result.stringVal = e.stringVal
  of irCast:
    result.castExpr = canonicalizeExpr(e.castExpr, renameMap, counter)
    result.castFrom = e.castFrom
    result.castTo = e.castTo

func canonicalizeIR*(f: IRFuncDef): IRFuncDef {.raises: [].} =
  ## Produces a canonical form of the IR function definition for deterministic hashing.
  ## - Alpha-renames local variables to v0, v1, v2... (declaration order)
  ## - Sorts commutative operand pairs by serialized string
  ## - Does NOT affect external declarations, params, or SMT-LIB2 generation
  result = f
  var renameMap: Table[string, string]
  var counter = 0
  result.body = canonicalizeExpr(f.body, renameMap, counter)
  result.preConditions = @[]
  for pc in f.preConditions:
    result.preConditions.add(canonicalizeExpr(pc, renameMap, counter))
  result.postConditions = @[]
  for pc in f.postConditions:
    result.postConditions.add(canonicalizeExpr(pc, renameMap, counter))

# ---------------------------------------------------------------------------
# IR digest (deterministic SHA-256 for audit trail)
# ---------------------------------------------------------------------------

func computeIrDigest*(f: IRFuncDef): string {.raises: [].} =
  ## Compute a deterministic SHA-256 digest of the IR structure.
  ## Same IR → same canonical string → same hash (deterministic).
  let canonical = canonicalizeIR(f)
  sha256Hex(serializeIRFuncDef(canonical))

# ---------------------------------------------------------------------------
# Type backfill for deserialized IRExpr trees
# ---------------------------------------------------------------------------

func recomputeTyp*(e: IRExpr) {.raises: [].} =
  ## Backfill typ on IRExpr tree. nil-safe, idempotent. Always recurses into
  ## children even when the current node already has typ set — mixed trees
  ## (deserialized leaves reused by the inline pass under typed structural
  ## nodes) otherwise keep untyped leaves forever (DEBT-quirk: see
  ## docs/spec/axiom_ir_recompute_typ_inline_pass_quirk.md).
  if e == nil: return
  case e.kind
  of irLit:      e.typ = irTypeBitVec64()
  of irFloatLit: e.typ = irTypeBitVec64()
  of irVar:
    if e.varType != nil: e.typ = e.varType
  of irStringLit: e.typ = irTypeString()
  of irBinOp:
    recomputeTyp(e.binLhs)
    recomputeTyp(e.binRhs)
    if e.binOp in {boEq, boLt, boLe, boGt, boGe}:
      e.typ = irTypeBool()
    else:
      e.typ = e.binLhs.typ
  of irUnaryOp:
    recomputeTyp(e.unaryArg)
    if e.unaryOp == uoNot: e.typ = irTypeBool()
    else: e.typ = e.unaryArg.typ
  of irIf:
    recomputeTyp(e.ifCond)
    recomputeTyp(e.ifThen)
    recomputeTyp(e.ifElse)
    if e.ifThen != nil and e.ifThen.typ != nil: e.typ = e.ifThen.typ
    else: e.typ = irTypeBitVec64()
  of irCall:
    for a in e.callArgs: recomputeTyp(a)
    # Check if this is a builtin with known return type
    if isIrBuiltin(e.callName):
      let builtins = irBuiltins()
      e.typ = builtins.getOrDefault(e.callName).retType
    elif e.typ == nil:
      e.typ = irTypeBitVec64()  # Default for unknown functions
  of irRecCall:
    for a in e.recArgs: recomputeTyp(a)
    e.typ = irTypeBitVec64()
  of irLet:
    recomputeTyp(e.letVal)
    recomputeTyp(e.letBody)
    if e.letBody != nil and e.letBody.typ != nil: e.typ = e.letBody.typ
    else: e.typ = irTypeBitVec64()
  of irCase:
    recomputeTyp(e.caseScrutinee)
    for br in e.caseBranches: recomputeTyp(br.body)
    recomputeTyp(e.caseDefault)
    if e.caseBranches.len > 0 and e.caseBranches[0].body != nil and e.caseBranches[0].body.typ != nil:
      e.typ = e.caseBranches[0].body.typ
    elif e.caseDefault != nil and e.caseDefault.typ != nil:
      e.typ = e.caseDefault.typ
    else: e.typ = irTypeBitVec64()
  of irLoop:
    for v in e.loopInits: recomputeTyp(v)
    recomputeTyp(e.loopCond)
    recomputeTyp(e.loopStep)
    recomputeTyp(e.loopBody)
    for v in e.loopInvariants: recomputeTyp(v)
    recomputeTyp(e.loopVariant)
    e.typ = irTypeBitVec64()
  of irCast:
    recomputeTyp(e.castExpr)
    if e.castTo != nil: e.typ = e.castTo
    else: e.typ = irTypeBitVec64()

func validateExprTypes*(e: IRExpr): bool {.raises: [].} =
  if e == nil: return true
  if e.typ == nil: return false
  case e.kind
  of irVar:
    if e.varType == nil: return false
  of irCall:
    for a in e.callArgs:
      if not validateExprTypes(a): return false
  of irRecCall:
    for a in e.callArgs:
      if not validateExprTypes(a): return false
  of irBinOp:
    if not validateExprTypes(e.binLhs): return false
    if not validateExprTypes(e.binRhs): return false
  of irUnaryOp:
    if not validateExprTypes(e.unaryArg): return false
  of irIf:
    if not validateExprTypes(e.ifCond): return false
    if not validateExprTypes(e.ifThen): return false
    if not validateExprTypes(e.ifElse): return false
  of irCase:
    if not validateExprTypes(e.caseScrutinee): return false
    for br in e.caseBranches:
      if not validateExprTypes(br.body): return false
    if not validateExprTypes(e.caseDefault): return false
  of irLet:
    if not validateExprTypes(e.letVal): return false
    if not validateExprTypes(e.letBody): return false
  of irLit, irFloatLit, irStringLit: discard
  of irLoop:
    for init in e.loopInits:
      if not validateExprTypes(init): return false
    if not validateExprTypes(e.loopCond): return false
    if not validateExprTypes(e.loopStep): return false
    if not validateExprTypes(e.loopBody): return false
    for inv in e.loopInvariants:
      if not validateExprTypes(inv): return false
    if not validateExprTypes(e.loopVariant): return false
  of irCast:
    if not validateExprTypes(e.castExpr): return false
  true

func validateIrTypes*(f: IRFuncDef): bool {.raises: [].} =
  if f.retType == nil: return false
  for p in f.params:
    if p.ty == nil: return false
  validateExprTypes(f.body)

# ---------------------------------------------------------------------------
# IR deserialization (round-trip partner for serialize functions)
# ---------------------------------------------------------------------------
# Format reference (serializeIRFuncDef output):
#   FUNC(add([x:BV64,y:BV64]):BV64=BIN(boAdd,V(x:BV64),V(y:BV64)),rec=false)
#
# Sentinel: deserializeIRFuncDef returns IRFuncDef(name: "") on parse failure.
# {.raises: [].} guaranteed — no exceptions, empty result on failure.

const parseAbortedPos = high(int)
  ## Stream position meaning "this input is irrecoverably malformed". No index
  ## expression below may run against it, so `parseIRExpr` / `parseIRType`
  ## re-check it on entry.

func parseAborted(pos: int): bool {.inline, raises: [].} =
  pos == parseAbortedPos

func abortParse(pos: var int) {.raises: [].} =
  ## Fail closed on input the parser cannot consume. Every list/mapping loop
  ## below calls this when an iteration leaves `pos` where it found it: a loop
  ## that cannot advance re-enters at the identical offset forever, which is the
  ## hang this exists to prevent.
  ##
  ## Aborting must not degrade to `nil`. `deserializeIRFuncDef` callers such as
  ## `crossValidate` → `irToSmtScript` dereference the body without a nil check,
  ## so a nil body is a SIGSEGV, not a rejection. Callers check
  ## `funcDef.name.len == 0`; that sentinel is the only legal failure value.
  pos = parseAbortedPos

func skipWs(s: string; pos: var int) {.raises: [].} =
  while pos < s.len and s[pos] in {' ', '\t', '\n', '\r'}:
    inc pos

func expect(s: string; pos: var int; ch: char): bool {.raises: [].} =
  skipWs(s, pos)
  if pos < s.len and s[pos] == ch:
    inc pos
    return true
  false

func parseIdent(s: string; pos: var int): string {.raises: [].} =
  skipWs(s, pos)
  result = ""
  while pos < s.len and (s[pos].isAlphaNumeric or s[pos] in {'_', '-'}):
    result.add(s[pos])
    inc pos

func parseAlphaIdent(s: string; pos: var int): string {.raises: [].} =
  ## Parse identifier starting with alpha (for variable names).
  skipWs(s, pos)
  result = ""
  while pos < s.len and (s[pos].isAlphaNumeric or s[pos] == '_'):
    result.add(s[pos])
    inc pos

func parseInt64(s: string; pos: var int): int64 {.raises: [].} =
  skipWs(s, pos)
  var neg = false
  if pos < s.len and s[pos] == '-':
    neg = true
    inc pos
  var digits = ""
  while pos < s.len and s[pos].isDigit:
    digits.add(s[pos])
    inc pos
  if digits.len == 0: return 0
  let parsedDigits = safeParseInt(digits)
  if parsedDigits.isErr:
    return 0
  result = parsedDigits.get
  if neg: result = -result

func parseIRType*(s: string; pos: var int): IRType {.raises: [].} =
  if parseAborted(pos): return IRType(kind: irtBitVec64)
  skipWs(s, pos)
  if pos + 4 <= s.len and s[pos ..< pos + 4] == "BV64":
    pos += 4
    return IRType(kind: irtBitVec64)
  if pos + 4 <= s.len and s[pos ..< pos + 4] == "BOOL":
    pos += 4
    return IRType(kind: irtBool)
  if pos + 4 <= s.len and s[pos ..< pos + 4] == "LIST":
    pos += 4
    if not expect(s, pos, '('): return IRType(kind: irtBitVec64)
    let elem = parseIRType(s, pos)
    discard expect(s, pos, ')')
    return IRType(kind: irtList, elemType: elem)
  if pos + 3 <= s.len and s[pos ..< pos + 3] == "STR":
    pos += 3
    return IRType(kind: irtString)
  if pos + 4 <= s.len and s[pos ..< pos + 4] == "ENUM":
    pos += 4
    if not expect(s, pos, '('): return IRType(kind: irtBitVec64)
    let name = parseIdent(s, pos)
    discard expect(s, pos, ',')
    if not expect(s, pos, '['): return IRType(kind: irtBitVec64)
    var values: seq[string]
    while pos < s.len and s[pos] != ']':
      let before = pos
      let v = parseIdent(s, pos)
      if v.len > 0: values.add(v)
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',': inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, ']')
    discard expect(s, pos, ',')
    if not expect(s, pos, '['): return IRType(kind: irtBitVec64)
    var ordinals: seq[int64]
    while pos < s.len and s[pos] != ']':
      let before = pos
      let o = parseInt64(s, pos)
      ordinals.add(o)
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',': inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, ']')
    discard expect(s, pos, ')')
    return irTypeEnum(name, values, ordinals)
  if pos + 7 <= s.len and s[pos ..< pos + 7] == "VARIANT":
    pos += 7
    if not expect(s, pos, '('): return IRType(kind: irtBitVec64)
    let name = parseIdent(s, pos)
    discard expect(s, pos, ',')
    if not expect(s, pos, '['): return IRType(kind: irtBitVec64)
    var tags: seq[string]
    while pos < s.len and s[pos] != ']':
      let before = pos
      let v = parseIdent(s, pos)
      if v.len > 0: tags.add(v)
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',': inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, ']')
    discard expect(s, pos, ',')
    if not expect(s, pos, '['): return IRType(kind: irtBitVec64)
    var ordinals: seq[int64]
    while pos < s.len and s[pos] != ']':
      let before = pos
      let o = parseInt64(s, pos)
      ordinals.add(o)
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',': inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, ']')
    discard expect(s, pos, ',')
    if not expect(s, pos, '['): return IRType(kind: irtBitVec64)
    var payloadTypes: seq[IRType]
    while pos < s.len and s[pos] != ']':
      let before = pos
      let pt = parseIRType(s, pos)
      payloadTypes.add(pt)
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',': inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, ']')
    discard expect(s, pos, ')')
    return irTypeVariant(name, tags, ordinals, payloadTypes)
  IRType(kind: irtBitVec64)  # fallback

# Forward declarations for mutual recursion within parseIRExpr.
func parseBinOpKind*(s: string; pos: var int): BinOpKind {.raises: [].}
func parseUnaryOpKind*(s: string; pos: var int): UnaryOpKind {.raises: [].}
func parseIRExprSeq*(s: string; pos: var int): seq[IRExpr] {.raises: [].}

func parseIRExpr*(s: string; pos: var int): IRExpr {.raises: [].} =
  if parseAborted(pos): return nil
  skipWs(s, pos)
  if pos >= s.len: return nil

  # LU(val) — u64-domain literal [2^63, 2^64−1]; ≥ 2^64 and < 2^63 abort
  # (domain violation — the signed domain travels only via L(...))
  if pos + 2 < s.len and s[pos] == 'L' and s[pos + 1] == 'U' and
      s[pos + 2] == '(':
    pos += 3
    skipWs(s, pos)
    var acc: uint64 = 0
    var digits = 0
    while pos < s.len and s[pos].isDigit:
      let d = uint64(s[pos].ord - '0'.ord)
      if acc > (high(uint64) - d) div 10:
        abortParse(pos)
        return nil
      acc = acc * 10 + d
      inc digits
      inc pos
    if digits == 0 or acc < 0x8000000000000000'u64:
      abortParse(pos)
      return nil
    discard expect(s, pos, ')')
    return IRExpr(kind: irLit, litU64: acc)

  # L(val)
  if pos + 1 < s.len and s[pos] == 'L' and s[pos + 1] == '(':
    pos += 2
    let val = parseInt64(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irLit, litVal: val)

  # V(name:Type)
  if pos + 1 < s.len and s[pos] == 'V' and s[pos + 1] == '(':
    pos += 2
    let name = parseAlphaIdent(s, pos)
    discard expect(s, pos, ':')
    let ty = parseIRType(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irVar, varName: name, varType: ty)

  # CLET(name=val|body) — isCompileTime=true let-binding
  if pos + 4 < s.len and s[pos ..< pos + 4] == "CLET" and s[pos + 4] == '(':
    pos += 5
    let name = parseAlphaIdent(s, pos)
    discard expect(s, pos, '=')
    let val = parseIRExpr(s, pos)
    discard expect(s, pos, '|')
    let body = parseIRExpr(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irLet, letName: name, letVal: val, letBody: body, isCompileTime: true)

  # LET(name=val|body)
  if pos + 3 < s.len and s[pos ..< pos + 3] == "LET" and s[pos + 3] == '(':
    pos += 4
    let name = parseAlphaIdent(s, pos)
    discard expect(s, pos, '=')
    let val = parseIRExpr(s, pos)
    discard expect(s, pos, '|')
    let body = parseIRExpr(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irLet, letName: name, letVal: val, letBody: body, isCompileTime: false)

  # IF(cond?then:else)
  if pos + 2 < s.len and s[pos ..< pos + 2] == "IF" and s[pos + 2] == '(':
    pos += 3
    let cond = parseIRExpr(s, pos)
    discard expect(s, pos, '?')
    let thenE = parseIRExpr(s, pos)
    discard expect(s, pos, ':')
    let elseE = parseIRExpr(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irIf, ifCond: cond, ifThen: thenE, ifElse: elseE)

  # CASE(scrutinee{branches...})
  if pos + 4 < s.len and s[pos ..< pos + 4] == "CASE" and s[pos + 4] == '(':
    pos += 5
    let scrutinee = parseIRExpr(s, pos)
    discard expect(s, pos, '{')
    var branches: seq[CaseBranch]
    var defaultExpr: IRExpr = nil
    while pos < s.len and s[pos] != '}':
      skipWs(s, pos)
      let before = pos
      if pos < s.len and s[pos] == '|':
        # Default branch: |D=>expr
        inc pos  # skip |
        discard parseIdent(s, pos)
        discard expect(s, pos, '=')
        discard expect(s, pos, '>')
        defaultExpr = parseIRExpr(s, pos)
      else:
        # Regular branch: pattern=>expr
        let pattern = parseInt64(s, pos)
        discard expect(s, pos, '=')
        discard expect(s, pos, '>')
        let body = parseIRExpr(s, pos)
        branches.add(CaseBranch(pattern: pattern, body: body))
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',':
        inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, '}')
    discard expect(s, pos, ')')
    return IRExpr(kind: irCase, caseScrutinee: scrutinee,
                  caseBranches: branches, caseDefault: defaultExpr)

  # CALL(name,args)
  if pos + 4 < s.len and s[pos ..< pos + 4] == "CALL" and s[pos + 4] == '(':
    pos += 5
    let name = parseIdent(s, pos)
    discard expect(s, pos, ',')
    let args = parseIRExprSeq(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irCall, callName: name, callArgs: args)

  # BIN(op,lhs,rhs)
  if pos + 3 < s.len and s[pos ..< pos + 3] == "BIN" and s[pos + 3] == '(':
    pos += 4
    let op = parseBinOpKind(s, pos)
    discard expect(s, pos, ',')
    let lhs = parseIRExpr(s, pos)
    discard expect(s, pos, ',')
    let rhs = parseIRExpr(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irBinOp, binOp: op, binLhs: lhs, binRhs: rhs)

  # UN(op,arg)
  if pos + 2 < s.len and s[pos ..< pos + 2] == "UN" and s[pos + 2] == '(':
    pos += 3
    let op = parseUnaryOpKind(s, pos)
    discard expect(s, pos, ',')
    let arg = parseIRExpr(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irUnaryOp, unaryOp: op, unaryArg: arg)

  # REC(args)
  if pos + 3 < s.len and s[pos ..< pos + 3] == "REC" and s[pos + 3] == '(':
    pos += 4
    let args = parseIRExprSeq(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irRecCall, recArgs: args)

  # LOOP(kind,[vars],[inits],cond,step,body,[invariants])
  if pos + 4 < s.len and s[pos ..< pos + 4] == "LOOP" and s[pos + 4] == '(':
    pos += 5  # skip LOOP(
    let kindStr = parseIdent(s, pos)
    let loopKind = if kindStr == "lkFor": lkFor else: lkWhile
    discard expect(s, pos, ',')
    # Parse loopVars
    if not expect(s, pos, '['): return nil
    var loopVars: seq[string] = @[]
    while pos < s.len and s[pos] != ']':
      let before = pos
      let v = parseAlphaIdent(s, pos)
      if v.len > 0: loopVars.add(v)
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',':
        inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, ']')
    discard expect(s, pos, ',')
    # Parse loopInits
    if not expect(s, pos, '['): return nil
    var loopInits: seq[IRExpr] = @[]
    while pos < s.len and s[pos] != ']':
      let before = pos
      let init = parseIRExpr(s, pos)
      if init != nil: loopInits.add(init)
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',':
        inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, ']')
    discard expect(s, pos, ',')
    let loopCond = parseIRExpr(s, pos)
    discard expect(s, pos, ',')
    var loopStep: IRExpr = nil
    if pos + 3 <= s.len and s[pos ..< pos + 3] == "NIL":
      pos += 3
    else:
      loopStep = parseIRExpr(s, pos)
    discard expect(s, pos, ',')
    let loopBody = parseIRExpr(s, pos)
    discard expect(s, pos, ',')
    if not expect(s, pos, '['): return nil
    var loopInvariants: seq[IRExpr] = @[]
    while pos < s.len and s[pos] != ']':
      let before = pos
      let inv = parseIRExpr(s, pos)
      if inv != nil: loopInvariants.add(inv)
      skipWs(s, pos)
      if pos < s.len and s[pos] == ',':
        inc pos
      if pos == before:
        abortParse(pos)
        break
    discard expect(s, pos, ']')
    discard expect(s, pos, ',')
    # Parse variant (optional: NIL means no variant)
    var loopVariant: IRExpr = nil
    if pos + 3 <= s.len and s[pos ..< pos + 3] == "NIL":
      pos += 3
    else:
      loopVariant = parseIRExpr(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irLoop, loopKind: loopKind, loopVars: loopVars,
      loopInits: loopInits, loopCond: loopCond, loopStep: loopStep,
      loopBody: loopBody, loopInvariants: loopInvariants,
      loopVariant: loopVariant)

  # FL(val) — float literal
  if pos + 1 < s.len and s[pos] == 'F' and s[pos + 1] == 'L':
    pos += 2
    let startPos = pos
    while pos < s.len and s[pos] != ')':
      inc pos
    let floatStr = s[startPos ..< pos]
    let val = safeParseFloat(floatStr).getOrDefault(0.0)
    discard expect(s, pos, ')')
    return IRExpr(kind: irFloatLit, floatVal: val)

  # SLIT(content) — content is backslash-escaped by serializeIRExpr, so only an
  # UNESCAPED `)` terminates the node. Scanning naively to the first `)` was the
  # ambiguity that let a payload like `(_ BitVec 64)` truncate itself and leave
  # the stream pointing into the middle of a foreign token.
  if pos + 4 < s.len and s[pos ..< pos + 4] == "SLIT" and s[pos + 4] == '(':
    pos += 5
    var strVal = ""
    var closed = false
    while pos < s.len:
      if s[pos] == '\\' and pos + 1 < s.len:
        strVal.add(s[pos + 1])
        pos += 2
      elif s[pos] == ')':
        closed = true
        inc pos
        break
      else:
        strVal.add(s[pos])
        inc pos
    if not closed:
      abortParse(pos)
      return nil
    return IRExpr(kind: irStringLit, stringVal: strVal)

  # CAST(expr,from->to)
  if pos + 4 < s.len and s[pos ..< pos + 4] == "CAST" and s[pos + 4] == '(':
    pos += 5
    let castExpr = parseIRExpr(s, pos)
    discard expect(s, pos, ',')
    let castFrom = parseIRType(s, pos)
    discard expect(s, pos, '-')
    discard expect(s, pos, '>')
    let castTo = parseIRType(s, pos)
    discard expect(s, pos, ')')
    return IRExpr(kind: irCast, castExpr: castExpr,
                  castFrom: castFrom, castTo: castTo)

  nil

func parseBinOpKind*(s: string; pos: var int): BinOpKind {.raises: [].} =
  skipWs(s, pos)
  let ident = parseIdent(s, pos)
  case ident
  of "boAdd": boAdd
  of "boSub": boSub
  of "boMul": boMul
  of "boDiv": boDiv
  of "boRem": boRem
  of "boRemU": boRemU
  of "boShl": boShl
  of "boShr": boShr
  of "boUnsupported": boUnsupported
  of "boLt": boLt
  of "boLe": boLe
  of "boGt": boGt
  of "boGe": boGe
  of "boAnd": boAnd
  of "boOr": boOr
  of "boEq": boEq
  of "boLtU": boLtU
  else: boUnsupported  # fallback

func parseUnaryOpKind*(s: string; pos: var int): UnaryOpKind {.raises: [].} =
  skipWs(s, pos)
  let ident = parseIdent(s, pos)
  case ident
  of "uoNot": uoNot
  of "uoBvNot": uoBvNot
  of "uoBvNeg": uoBvNeg
  else: uoNot  # fallback

func parseIRExprSeq*(s: string; pos: var int): seq[IRExpr] {.raises: [].} =
  if not expect(s, pos, '['): return @[]
  result = @[]
  while pos < s.len and s[pos] != ']':
    let before = pos
    let e = parseIRExpr(s, pos)
    if e != nil:
      result.add(e)
    skipWs(s, pos)
    if pos < s.len and s[pos] == ',':
      inc pos
    if pos == before:
      abortParse(pos)
      break
  discard expect(s, pos, ']')

func parseIRParams*(s: string; pos: var int): seq[IRFuncParam] {.raises: [].} =
  if not expect(s, pos, '['): return @[]
  result = @[]
  while pos < s.len and s[pos] != ']':
    skipWs(s, pos)
    let before = pos
    let name = parseAlphaIdent(s, pos)
    discard expect(s, pos, ':')
    let ty = parseIRType(s, pos)
    var constraint: Option[IRExpr] = none(IRExpr)
    if pos < s.len and s[pos] == '|':
      inc pos  # skip |
      constraint = some(parseIRExpr(s, pos))
    if name.len > 0:
      result.add(IRFuncParam(name: name, ty: ty, constraint: constraint))
    skipWs(s, pos)
    if pos < s.len and s[pos] == ',':
      inc pos
    if pos == before:
      abortParse(pos)
      break
  discard expect(s, pos, ']')

func deserializeIRFuncDef*(s: string): IRFuncDef {.raises: [].} =
  ## Deserialize an IRFuncDef from canonical string form.
  ## Returns IRFuncDef(name: "") on parse failure (sentinel).
  ## Round-trip: deserializeIRFuncDef(serializeIRFuncDef(f)) == f
  ## Backward compatible: missing preconds → empty seq, missing |CONSTRAINT → none
  var pos = 0
  let prefix = parseIdent(s, pos)
  if prefix != "FUNC": return IRFuncDef()
  if not expect(s, pos, '('): return IRFuncDef()
  let name = parseIdent(s, pos)
  if name.len == 0: return IRFuncDef()
  if not expect(s, pos, '('): return IRFuncDef(name: "")
  let params = parseIRParams(s, pos)
  if not expect(s, pos, ')'): return IRFuncDef(name: "")
  if not expect(s, pos, ':'): return IRFuncDef(name: "")
  let retType = parseIRType(s, pos)
  if not expect(s, pos, '='): return IRFuncDef(name: "")
  let body = parseIRExpr(s, pos)
  # An aborted parse may have left a half-built tree, and an unconsumed input
  # position leaves `body` nil. Neither is a legal result: callers branch on
  # `name.len == 0`, while `crossValidate` → `irToSmtScript` has no nil-body
  # check to save it. The sentinel is the only value a caller can survive.
  if parseAborted(pos) or body == nil: return IRFuncDef(name: "")
  var isRec = false
  var preConditions: seq[IRExpr] = @[]
  var postConditions: seq[IRExpr] = @[]
  while expect(s, pos, ','):
    let key = parseIdent(s, pos)
    if key == "rec":
      if expect(s, pos, '='):
        let val = parseIdent(s, pos)
        isRec = val == "true"
    elif key == "preconds":
      if expect(s, pos, '='):
        preConditions = parseIRExprSeq(s, pos)
    elif key == "postconds":
      if expect(s, pos, '='):
        postConditions = parseIRExprSeq(s, pos)
  discard expect(s, pos, ')')  # consume final closing paren of FUNC(...)
  IRFuncDef(name: name, params: params, retType: retType,
            body: body, isRecursive: isRec, preConditions: preConditions,
            postConditions: postConditions)

func hasFloatLit*(e: IRExpr): bool =
  if e == nil: return false
  case e.kind
  of irFloatLit: true
  of irLit, irVar, irStringLit: false
  of irLet: hasFloatLit(e.letVal) or hasFloatLit(e.letBody)
  of irIf: hasFloatLit(e.ifCond) or hasFloatLit(e.ifThen) or hasFloatLit(e.ifElse)
  of irCase:
    if hasFloatLit(e.caseScrutinee): return true
    for br in e.caseBranches:
      if hasFloatLit(br.body): return true
    hasFloatLit(e.caseDefault)
  of irCall:
    for a in e.callArgs:
      if hasFloatLit(a): return true
    false
  of irBinOp: hasFloatLit(e.binLhs) or hasFloatLit(e.binRhs)
  of irUnaryOp: hasFloatLit(e.unaryArg)
  of irRecCall:
    for a in e.recArgs:
      if hasFloatLit(a): return true
    false
  of irLoop:
    for a in e.loopInits:
      if hasFloatLit(a): return true
    if hasFloatLit(e.loopCond): return true
    if e.loopStep != nil and hasFloatLit(e.loopStep): return true
    if hasFloatLit(e.loopBody): return true
    for a in e.loopInvariants:
      if hasFloatLit(a): return true
    if e.loopVariant != nil and hasFloatLit(e.loopVariant): return true
    false
  of irCast: hasFloatLit(e.castExpr)

func hasStringLit*(e: IRExpr): bool =
  if e == nil: return false
  case e.kind
  of irStringLit: true
  of irLit, irFloatLit, irVar: false
  of irLet: hasStringLit(e.letVal) or hasStringLit(e.letBody)
  of irIf: hasStringLit(e.ifCond) or hasStringLit(e.ifThen) or hasStringLit(e.ifElse)
  of irCase:
    if hasStringLit(e.caseScrutinee): return true
    for br in e.caseBranches:
      if hasStringLit(br.body): return true
    hasStringLit(e.caseDefault)
  of irCall:
    for a in e.callArgs:
      if hasStringLit(a): return true
    false
  of irBinOp: hasStringLit(e.binLhs) or hasStringLit(e.binRhs)
  of irUnaryOp: hasStringLit(e.unaryArg)
  of irRecCall:
    for a in e.recArgs:
      if hasStringLit(a): return true
    false
  of irLoop:
    for a in e.loopInits:
      if hasStringLit(a): return true
    if hasStringLit(e.loopCond): return true
    if e.loopStep != nil and hasStringLit(e.loopStep): return true
    if hasStringLit(e.loopBody): return true
    for a in e.loopInvariants:
      if hasStringLit(a): return true
    if e.loopVariant != nil and hasStringLit(e.loopVariant): return true
    false
  of irCast: hasStringLit(e.castExpr)

func isBmcSkippable*(f: IRFuncDef): bool =
  if f.retType.kind == irtString:
    return true
  for p in f.params:
    if p.ty.kind == irtString:
      return true
  hasFloatLit(f.body) or hasStringLit(f.body)

{.pop.}
