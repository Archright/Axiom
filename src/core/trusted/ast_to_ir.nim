import core/trusted/layer_declaration
axiomLayer "trusted.core.ast-to-ir"

{.push raises: [].}
import core/trusted/axiom_ir_helpers
import core/trusted/type_manifest_registry
import shared/canonical_ast
import std/macros
import std/sets
import std/strutils
import std/tables
export axiom_ir_helpers

type
  IrContext* = object
    typeEnv*: Table[string, IRType]
    unsignedParams*: HashSet[string]
      ## Parameters whose SOURCE type is uint-family — the original-type
      ## signedness record (IRType collapses int/uint to irtBitVec64). The
      ## `<` refinement consults this; aliases and untyped subexpressions are
      ## not determinable here and keep boLt (status quo).
    funcName*: string
    lossySeen*: bool = false
    exprLoss*: int = 0    ## expression-level losses — a construct replaced by a placeholder
    regionDrops*: int = 0 ## statement forms dropped whole — the subtree is never traversed
    guardLoss*: int = 0   ## losses recorded while a guard/loop condition was open
    guardDepth*: int = 0  ## open guard regions; loss inside one fabricates a branch
    bindings*: seq[IRBinding] = @[]

func initIrContext*(funcName: string, params: seq[IRFuncParam]): IrContext =
  result.funcName = funcName
  result.typeEnv = initTable[string, IRType]()
  result.unsignedParams = initHashSet[string]()
  for p in params:
    result.typeEnv[p.name] = p.ty

# ---------------------------------------------------------------------------
# Unsigned-ness discrimination (operator-resident signedness contract —
# rust_certified_subset.md §4 boLtU note)
# ---------------------------------------------------------------------------

func stripGensym*(s: string): string {.inline.} =
  ## Strip Nim gensym suffix (everything after backtick).
  ## "a`gensym48" → "a", "x`gensym2" → "x"
  let idx = s.find('`')
  if idx >= 0: s[0 ..< idx]
  else: s

const nimUintTypeNames* = ["uint", "uint8", "uint16", "uint32", "uint64"]
  ## Source-level unsigned integer type names. A type ALIAS resolves to a
  ## different symbol name and is NOT determinably unsigned here — such
  ## operands keep boLt (status quo), never a guessed boLtU.

func nimTypeNodeIsUnsigned*(typeNode: NimNode): bool {.raises: [].} =
  ## True iff the param type node NAMES a uint-family type directly.
  case typeNode.kind
  of nnkIdent, nnkSym:
    typeNode.strVal in nimUintTypeNames
  else:
    false

func canonTypeNodeIsUnsigned*(typeNode: CanonNode): bool {.raises: [].} =
  ## Canon mirror of nimTypeNodeIsUnsigned (ckIdent name match).
  typeNode.kind == ckIdent and typeNode.name in nimUintTypeNames

func nimOperandIsUnsigned(n: NimNode; ctx: IrContext): bool {.inline, raises: [].} =
  ## Determinable unsigned-ness of an infix operand BY ORIGINAL SOURCE FORM
  ## ONLY: an unsigned literal node, or an ident/sym naming a uint-family
  ## parameter. Subexpressions and aliases are not determinable → false.
  case n.kind
  of nnkUIntLit, nnkUInt64Lit, nnkUInt32Lit, nnkUInt16Lit, nnkUInt8Lit:
    true
  of nnkIdent, nnkSym:
    ctx.unsignedParams.contains(stripGensym(n.strVal))
  else:
    false

func canonOperandIsUnsigned(n: CanonNode; ctx: IrContext): bool {.inline, raises: [].} =
  ## Canon mirror of nimOperandIsUnsigned.
  case n.kind
  of ckUIntLit, ckUInt64Lit, ckUInt32Lit, ckUInt16Lit, ckUInt8Lit:
    true
  of ckIdent, ckSym:
    ctx.unsignedParams.contains(stripGensym(n.name))
  else:
    false

# ---------------------------------------------------------------------------
# Loss accounting
# ---------------------------------------------------------------------------
## `lossySeen` is one bit for a whole function, which cannot distinguish two
## losses that mean opposite things to a caller: a construct this IR cannot spell
## (the surrounding structure survives, only the leaf is a placeholder) and a
## statement form this IR has no arm for (the subtree is never traversed, so a
## binding inside it is simply absent). The counters below keep both, so a caller
## can certify a lexical region instead of the function.
##
## A counter rather than a loss-site list: attribution needs no stack discipline
## because the loss sites are always inside a conversion of exactly the
## sub-expression the caller just bracketed, and a snapshot taken before and
## after that conversion isolates it — a loss deeper in the recursion is still a
## loss inside the bracket.

func markLoss(ctx: var IrContext) {.raises: [].} =
  ctx.lossySeen = true
  inc ctx.exprLoss
  if ctx.guardDepth > 0: inc ctx.guardLoss

func markGuardLoss(ctx: var IrContext) {.raises: [].} =
  ## A loss that fabricates a branch decision — an unreadable case ordinal, whose
  ## wildcard fallback is what decides the branch. Counted as a guard loss even
  ## when no guard region is open, because the fabricated decision is itself the
  ## guard: assuming it would be assuming something the source never said.
  markLoss(ctx)
  inc ctx.guardLoss

func markRegionDrop(ctx: var IrContext) {.raises: [].} =
  ## No translation arm for this statement form. The bindings below it are not
  ## recorded as lossy — they are absent, and their absence is not evidence.
  ctx.lossySeen = true
  inc ctx.regionDrops

func openGuard(ctx: var IrContext) {.raises: [].} =
  ## Bracket a conversion whose result decides whether a branch is taken; a loss
  ## recorded before the matching closeGuard fabricated that decision.
  inc ctx.guardDepth

func closeGuard(ctx: var IrContext) {.raises: [].} =
  dec ctx.guardDepth

func recordBinding(ctx: var IrContext; name, anchor: string;
                   value: IRExpr; lossMark: int; isCompileTime: bool) {.raises: [].} =
  ## `lossMark` is `exprLoss` sampled before `value` was converted; an unchanged
  ## count means the placeholder substitution happened nowhere inside it.
  ctx.bindings.add(IRBinding(name: name, value: value, anchor: anchor,
                             isCompileTime: isCompileTime,
                             lossFree: ctx.exprLoss == lossMark))

func traversesSubtreeAsExpression(k: CanonKind): bool {.raises: [].} =
  ## True when the expression converter will descend into this kind's children.
  ##
  ## The body converter's fallback keeps an unrecognised statement's VALUE and
  ## converts it as if it were the trailing expression. For a statement whose
  ## kind the expression converter also understands, that visit reaches every
  ## sub-expression, so the statement hides no declaration. For any other kind
  ## the visit stops at the node itself, and a `let` inside it — a block's, a
  ## loop body's — is absent from the IR rather than recorded as lossy.
  k in {ckIntLit, ckInt64Lit, ckInt32Lit, ckInt16Lit, ckInt8Lit,
        ckUIntLit, ckUInt64Lit, ckUInt32Lit, ckUInt16Lit, ckUInt8Lit,
        ckFloatLit, ckFloat64Lit, ckFloat32Lit, ckFloat128Lit,
        ckStrLit, ckRStrLit, ckTripleStrLit, ckCharLit, ckNilLit,
        ckIdent, ckSym, ckDotExpr, ckBracketExpr, ckInfix, ckPrefix,
        ckCall, ckIfExpr, ckElifExpr, ckElseExpr, ckCaseStmt,
        ckStmtList, ckStmtListExpr, ckReturnStmt, ckEmpty}

func traversesSubtreeAsExpression(k: NimNodeKind): bool {.raises: [].} =
  ## NimNode mirror of the predicate above.
  k in {nnkCharLit, nnkIntLit..nnkInt64Lit,
        nnkUIntLit..nnkUInt64Lit,
        nnkFloatLit..nnkFloat128Lit, nnkStrLit, nnkRStrLit, nnkTripleStrLit,
        nnkNilLit, nnkIdent, nnkSym, nnkDotExpr, nnkBracketExpr, nnkInfix,
        nnkPrefix, nnkCall, nnkPar, nnkIfExpr, nnkElifExpr, nnkElseExpr,
        nnkCaseStmt, nnkStmtListExpr, nnkReturnStmt, nnkEmpty}

# ---------------------------------------------------------------------------
# Type mapping — CanonNode core + NimNode wrapper (M3)
# ---------------------------------------------------------------------------
# Hybrid boundary: convertTypeCanon operates on read-only CanonNode values.
# convertType (NimNode) is the entry point that converts to CanonNode first,
# then delegates to convertTypeCanon.  NimNode is still needed for getTypeImpl()
# calls on nnkSym nodes (type resolution requires compiler symbol tables).

func convertTypeCanon*(n: CanonNode): IRType =
  ## Maps canonical type nodes to IR types.
  ## int → irtBitVec64, bool → irtBool
  case n.kind
  of ckIdent:
    case n.name
    of "int", "int8", "int16", "int32", "int64",
       "uint", "uint8", "uint16", "uint32", "uint64":
      irTypeBitVec64()
    of "bool":
      irTypeBool()
    of "string":
      irTypeString()
    else:
      irTypeBitVec64()
  of ckBracketExpr:
    if n.children.len >= 2 and n.children[0].kind == ckIdent and
       n.children[0].name in ["seq", "openArray", "array"]:
      irTypeList(convertTypeCanon(n.children[1]))
    else:
      irTypeBitVec64()
  of ckEnumTy:
    # An ordinal is used only when the source states one. A bare identifier
    # states none, and numbering it by declaration order would make this
    # translator a second authority on the compiler's implicit ordinals — the
    # same argument that keeps nnkSym case patterns fail-closed in
    # convertCaseStmt.  A member without a stated ordinal makes the whole enum
    # unrepresentable, so the enum is not built.
    var values: seq[string]
    var ordinals: seq[int64]
    for child in n.children:
      if child.kind == ckEnumFieldDef and child.children.len >= 2 and
         child.children[1].kind in {ckIntLit, ckInt64Lit}:
        values.add(child.children[0].name)
        ordinals.add(child.children[1].intVal)
      else:
        return irTypeBitVec64()
    if values.len > 0:
      irTypeEnum("", values, ordinals)
    else:
      irTypeBitVec64()
  of ckObjectTy:
    # Check for case object (variant type with ckRecCase)
    for child in n.children:
      if child.kind == ckRecCase:
        let disc = child.children[0]
        if disc.children.len >= 2:
          # ckRecCase discriminator: resolve via nnkSym path needs NimNode getTypeImpl.
          # CanonNode path: if discriminator child is ckIdent, treat as unresolved.
          # The nnkSym → getTypeImpl → nnkEnumTy resolution stays in convertType (NimNode).
          discard
    irTypeBitVec64()
  of ckDistinctTy:
    # distinct type: unwrap to base type
    if n.children.len >= 1:
      convertTypeCanon(n.children[0])
    else:
      irTypeBitVec64()
  of ckTupleTy:
    # tuple type: simplified to BitVec64
    irTypeBitVec64()
  else:
    irTypeBitVec64()

func convertType*(n: NimNode): IRType =
  ## NimNode entry point — converts to CanonNode then delegates to convertTypeCanon.
  ## nnkSym nodes require getTypeImpl() (compiler symbol table access) which
  ## is not available on CanonNode; those cases are handled here before forwarding.
  case n.kind
  of nnkSym:
    # 1. Static type manifest registry lookup (highest priority)
    let typeName = n.strVal
    let spec = lookupExternalType(typeName)
    if spec.kind != irtBitVec64:
      case spec.kind
      of irtVariant:
        return irTypeVariant("", spec.tags, spec.ordinals, newSeq[IRType](spec.tags.len))
      of irtEnum:
        return irTypeEnum("", spec.tags, spec.ordinals)
      else:
        return irTypeFromKind(spec.kind)
    # 2. Fallback to getTypeImpl
    let impl = n.getTypeImpl()
    if impl.kind == nnkTypeDef and impl.len >= 3:
      # Unwrap nnkTypeDef → actual type definition
      convertType(impl[2])
    elif impl.kind != n.kind:
      convertType(impl)
    else:
      irTypeBitVec64()
  of nnkObjectTy:
    # Check for case object (variant type with nnkRecCase)
    for child in n:
      if child.kind == nnkRecCase:
        let disc = child[0]
        if disc.len >= 2:
          # Resolve discriminator type (may be nnkSym → getTypeImpl → nnkEnumTy)
          let discType = if disc[1].kind == nnkEnumTy: disc[1]
                         elif disc[1].kind == nnkSym: disc[1].getTypeImpl()
                         else: disc[1]
          if discType.kind == nnkEnumTy:
            var tags: seq[string]
            var ordinals: seq[int64]
            for ec in discType:
              # Mirrors convertTypeCanon: a stated ordinal only, never one
              # inferred from declaration order.
              if ec.kind == nnkEnumFieldDef and ec.len >= 2 and
                 ec[1].kind in {nnkIntLit, nnkInt64Lit}:
                tags.add(ec[0].strVal)
                ordinals.add(ec[1].intVal)
              else:
                tags.setLen(0)
                ordinals.setLen(0)
                break
            if tags.len > 0:
              return irTypeVariant("", tags, ordinals, newSeq[IRType](tags.len))
    irTypeBitVec64()
  else:
    convertTypeCanon(toCanon(n))

# ---------------------------------------------------------------------------
# AST helpers
# ---------------------------------------------------------------------------
func opStrVal(n: NimNode): string {.inline.} =
  ## Extract operator string from nnkIdent, nnkSym, nnkOpenSymChoice, or nnkClosedSymChoice.
  ## Nim 2.x quirk: operators resolve to nnkClosedSymChoice when the compiler
  ## narrows overloads to a finite set; both must be handled identically.
  case n.kind
  of nnkIdent, nnkSym: n.strVal
  of nnkOpenSymChoice, nnkClosedSymChoice:
    if n.len > 0: n[0].strVal
    else: ""
  else: ""
func identName(n: NimNode): string {.inline.} =
  ## Extract identifier name from nnkIdent, nnkSym, nnkPostfix,
  ## or nnkOpenSymChoice/nnkClosedSymChoice (overloaded callees).
  case n.kind
  of nnkIdent, nnkSym: n.strVal
  of nnkPostfix:
    if n.len >= 2: n[1].strVal
    else: ""
  of nnkDotExpr:
    if n.len >= 2: n[1].strVal
    else: ""
  of nnkOpenSymChoice, nnkClosedSymChoice:
    if n.len > 0: n[0].strVal
    else: ""
  else: ""

# ---------------------------------------------------------------------------
# Binary operator mapping
# ---------------------------------------------------------------------------
func convertBinOp(op: string): BinOpKind {.inline.} =
  ## Map Nim operator string to IR BinOpKind.
  case op
  of "+":  boAdd
  of "-":  boSub
  of "*":  boMul
  of "/":  boDiv
  of "div": boDiv
  # Nim 2.2.10 has no `%` int operator (`mod` keyword, `%%` for unsigned), so
  # no `"%"` leg exists here: a phantom mapping would claim support the
  # pinned toolchain cannot produce; an AST `%` falls through to
  # boUnsupported below.
  of "mod": boRem
  of "%%": boRemU       ## unsigned modulo (SemanticProfileV1 spModuloUnsigned)
  of "shl": boShl       ## unsupported in SemanticProfileV1 (spShiftUnsupported)
  of "shr": boShr       ## unsupported in SemanticProfileV1 (spShiftUnsupported)
  of "<":  boLt
  of "<=": boLe
  of ">":  boGt
  of ">=": boGe
  of "==": boEq
  of "and": boAnd
  of "or":  boOr
  else:    boUnsupported

func convertBinOpUnsigned(op: string; lhsN, rhsN: NimNode;
    ctx: IrContext): BinOpKind {.raises: [].} =
  ## convertBinOp + the single unsigned refinement: `<` becomes boLtU iff
  ## BOTH operands are determinably unsigned by original source type. Mixed
  ## or unresolvable operands keep boLt (status quo — never a guess).
  if op == "<" and nimOperandIsUnsigned(lhsN, ctx) and
      nimOperandIsUnsigned(rhsN, ctx):
    boLtU
  else:
    convertBinOp(op)

func convertBinOpCanonUnsigned(op: string; lhsN, rhsN: CanonNode;
    ctx: IrContext): BinOpKind {.raises: [].} =
  ## Canon mirror of convertBinOpUnsigned.
  if op == "<" and canonOperandIsUnsigned(lhsN, ctx) and
      canonOperandIsUnsigned(rhsN, ctx):
    boLtU
  else:
    convertBinOp(op)

func isLayoutIntrinsic(name: string): bool {.inline.} =
  ## True for Nim compile-time layout intrinsics (compiler magics
  ## mSizeOf / mAlignOf / mOffsetOf, lib/system.nim `sizeof`, `alignof`,
  ## `offsetOf`, `offsetOfDotExpr`).
  ##
  ## These are ordinary nnkCall / ckCall nodes when a macro sees them: the
  ## compiler folds them to integer literals in semMagic (semmagic.nim
  ## foldSizeOf / foldAlignOf / foldOffsetOf), which runs *after* macro
  ## expansion.  Their value is therefore already lost at this boundary, and
  ## IRTypeKind (axiom_ir_types.nim) has no width field to carry it, so it is
  ## unrepresentable as a known number here.  Any function whose semantics
  ## depend on one must be marked lossy rather than preserved as if it were.
  name in ["sizeof", "alignof", "offsetOf", "offsetOfDotExpr"]

# ---------------------------------------------------------------------------
# Forward declarations (mutual recursion: convertExpr ↔ helpers)
# ---------------------------------------------------------------------------
func convertExpr*(n: NimNode, ctx: var IrContext): IRExpr
func convertIfExpr*(n: NimNode, ctx: var IrContext): IRExpr
func convertIfStmt*(n: NimNode, ctx: var IrContext): IRExpr
func convertCaseStmt*(n: NimNode, ctx: var IrContext): IRExpr
func convertBody*(stmts: NimNode, ctx: var IrContext): IRExpr
func convertBodyFrom(stmts: NimNode, idx: int, ctx: var IrContext): IRExpr

# Forward declarations for convertBody loop desugaring.
func collectLoopVarTargets(body: NimNode): seq[string]
func hasEarlyReturn(body: NimNode): bool
func extractWhileVariant(cond: NimNode, loopVars: seq[string]): NimNode

# ── CanonNode read-only versions (M4) ──────────────────────────
# Hybrid boundary: CanonNode versions are read-only analysis functions.
# They operate on canonical AST nodes and do NOT construct new AST.
# NimNode versions remain for AST construction/manipulation (e.g.
# for-collection desugar uses newTree/genSym which require NimNode).
# See tools/shared/canonical_ast.nim §5 for the hybrid boundary policy.

func convertExprCanon*(n: CanonNode, ctx: var IrContext): IRExpr
func convertIfExprCanon*(n: CanonNode, ctx: var IrContext): IRExpr
func convertCaseStmtCanon*(n: CanonNode, ctx: var IrContext): IRExpr
func convertBodyCanon*(stmts: CanonNode, ctx: var IrContext): IRExpr
func convertBodyFromCanon(stmts: CanonNode, idx: int, ctx: var IrContext): IRExpr

# ---------------------------------------------------------------------------
# Expression conversion
# ---------------------------------------------------------------------------

func convertLiteral(n: NimNode): IRExpr =
  ## Every literal-carrying node kind. A nil literal is IR integer 0: the IR has
  ## no pointer domain, so `nil` is the zero of the only value domain it has.
  case n.kind
  of nnkIntLit, nnkInt64Lit, nnkInt32Lit, nnkInt16Lit, nnkInt8Lit:
    irLit(int64(n.intVal))
  of nnkUIntLit, nnkUInt64Lit, nnkUInt32Lit, nnkUInt16Lit, nnkUInt8Lit:
    irLit(int64(n.intVal))
  of nnkFloatLit, nnkFloat64Lit, nnkFloat32Lit, nnkFloat128Lit:
    irFloatLit(n.floatVal)
  of nnkStrLit, nnkRStrLit, nnkTripleStrLit:
    IRExpr(typ: irTypeString(), kind: irStringLit, stringVal: n.strVal)
  of nnkCharLit:
    irLit(int64(n.intVal))
  of nnkNilLit:
    irLit(0)
  else:
    nil  ## not a literal kind — the dispatcher never routes one here

func convertIdent(n: NimNode, ctx: var IrContext): IRExpr =
  ## A name, and nothing more. There is no name-keyed table of constant values
  ## here: the compiler owns that reading, and inlining a value keyed only by
  ## name would state a value the source under translation never said — on the
  ## CanonNode path, where a subject may define its own same-named `const`. A
  ## constant the compiler has not folded therefore stays an unbound variable,
  ## typed from the environment or defaulted to the kernel's bit-vector width.
  let name = stripGensym(n.strVal)
  irVar(name, ctx.typeEnv.getOrDefault(name, irTypeBitVec64()))

func inferFieldAccessType(obj: IRExpr; fieldName: string): IRType =
  ## Bottom-up field typing: `kind` on a variant widens to a synthesised enum
  ## carrying the variant's tags, and on a plain enum it is already the field
  ## type. nil for every other field, which then carries no type annotation.
  if obj.typ != nil:
    if fieldName == "kind" and obj.typ.kind == irtVariant:
      return irTypeEnum("", obj.typ.variantTags, obj.typ.variantOrdinals)
    if fieldName == "kind" and obj.typ.kind == irtEnum:
      return obj.typ
  nil

func convertDotExpr(n: NimNode, ctx: var IrContext): IRExpr =
  ## Field access: obj.field → irCall("field", @[obj]). A nil object means the
  ## receiver did not translate, so the field name stands alone as a variable.
  if n.len < 2:
    return nil
  let fieldName = n[1].strVal
  let obj = convertExpr(n[0], ctx)
  if obj == nil:
    return irVar(fieldName, irTypeBitVec64())
  let callRetType = inferFieldAccessType(obj, fieldName)
  if callRetType != nil:
    irCall(fieldName, @[obj], callRetType)
  else:
    irCall(fieldName, @[obj])

func convertPrefix(n: NimNode, ctx: var IrContext): IRExpr =
  ## Prefix application: only the two operators with a distinct IR spelling are
  ## named. Any other unary operator is one this IR cannot express, so the loss
  ## is counted and the operator's own meaning is withheld rather than restated
  ## as a negation it is not.
  let op = opStrVal(n[0])
  let arg = convertExpr(n[1], ctx)
  case op
  of "-": irBvNeg(arg)
  of "not": irNot(arg)
  else:
    markLoss(ctx)
    irLit(0)

func convertCall(n: NimNode, ctx: var IrContext): IRExpr =
  ## Call application, including the two special readings.
  let calleeName = identName(n[0])
  # Layout intrinsics are handled below but never evaluated: `sizeof(x)` parses
  # as nnkCall in Nim 2.2 (there is no nnkSizeOfExpr in this version's
  # NimNodeKind) and reaches this converter still unfolded.  Preserving the op
  # keeps the shape; marking the loss is what keeps it sound — an unevaluated
  # size must not reach the solver as a value it can assume nonzero.
  if isLayoutIntrinsic(calleeName):
    markLoss(ctx)
  # nnkSizeOfExpr equivalent: sizeof preserves as irCall("sizeof", @[operand])
  if calleeName == "sizeof" and n.len >= 2:
    return irCall("sizeof", @[convertExpr(n[1], ctx)])
  var args: seq[IRExpr]
  for i in 1..<n.len:
    args.add(convertExpr(n[i], ctx))
  if calleeName == ctx.funcName:
    return irRecCall(args)
  # Bottom-up: infer return type from first argument
  if args.len > 0 and args[0].typ != nil:
    let callRetType = inferFieldAccessType(args[0], calleeName)
    if callRetType != nil:
      return irCall(calleeName, args, callRetType)
  irCall(calleeName, args)

func convertExpr*(n: NimNode, ctx: var IrContext): IRExpr =
  ## Converts a Nim AST expression node to IRExpr.
  ## `ctx` carries type environment and function name for recursive call detection.
  case n.kind
  of nnkIntLit, nnkInt64Lit, nnkInt32Lit, nnkInt16Lit, nnkInt8Lit,
     nnkUIntLit, nnkUInt64Lit, nnkUInt32Lit, nnkUInt16Lit, nnkUInt8Lit,
     nnkFloatLit, nnkFloat64Lit, nnkFloat32Lit, nnkFloat128Lit,
     nnkStrLit, nnkRStrLit, nnkTripleStrLit, nnkCharLit, nnkNilLit:
    convertLiteral(n)
  of nnkIdent, nnkSym:
    convertIdent(n, ctx)
  of nnkDotExpr:
    convertDotExpr(n, ctx)
  of nnkInfix:
    let op = opStrVal(n[0])
    let lhs = convertExpr(n[1], ctx)
    let rhs = convertExpr(n[2], ctx)
    irBinOp(convertBinOpUnsigned(op, n[1], n[2], ctx), lhs, rhs)
  of nnkPrefix:
    convertPrefix(n, ctx)
  of nnkCall:
    convertCall(n, ctx)
  of nnkIfExpr, nnkIfStmt:
    convertIfExpr(n, ctx)
  of nnkStmtListExpr:
    if n.len == 1: convertExpr(n[0], ctx)
    else: convertBody(n, ctx)
  of nnkCaseStmt:
    convertCaseStmt(n, ctx)
  of nnkStmtList:
    convertBody(n, ctx)
  of nnkAsgn, nnkHiddenStdConv, nnkHiddenSubConv:
    convertExpr(n[1], ctx)
  of nnkPar:
    convertExpr(n[0], ctx)
  of nnkReturnStmt:
    if n.len > 0 and n[0].kind != nnkEmpty:
      convertExpr(n[0], ctx)
    else:
      irLit(0)
  else:
    # WP4-j.2: unhandled expression kind — record loss instead of silent drop.
    # NOTE: Nim 2.2 parses `sizeof(x)` as nnkCall("sizeof", ...) — handled in the
    # nnkCall branch above (preserved opaquely as irCall). nnkSizeOfExpr does not
    # exist in this Nim version's NimNodeKind.
    markLoss(ctx)
    irLit(0)

# ---------------------------------------------------------------------------
# If expression helpers
# ---------------------------------------------------------------------------

func convertIfExpr*(n: NimNode, ctx: var IrContext): IRExpr =
  ## Convert nnkIfExpr/nnkIfStmt to irIf.
  ## Handles both expression-form (nnkElifExpr/nnkElseExpr) and
  ## statement-form (nnkElifBranch/nnkElse) children.
  ## nnkElifBranch wraps then-body in nnkStmtList; nnkElifExpr does not.
  ## Multi-way if/elif/else is encoded as a nested irIf chain:
  ##   If(C1, T1, Elif(C2, T2, E)) → irIf(C1, T1, irIf(C2, T2, E))
  type
    BranchKind = enum
      bkCondition    ## elif: cond at [0], then at [1]
      bkFinal        ## final else: value at [0]
  var branches: seq[(BranchKind, NimNode)] = @[]
  for child in n:
    case child.kind
    of nnkElifExpr, nnkElifBranch:
      branches.add((bkCondition, child))
    of nnkElseExpr, nnkElse:
      branches.add((bkFinal, child))
    else: discard
  if branches.len == 0:
    return irLit(0)
  var acc: IRExpr = nil
  for i in countdown(branches.len - 1, 0):
    let (kind, node) = branches[i]
    if kind == bkFinal:
      acc = convertExpr(node[0], ctx)
      if acc == nil: acc = irLit(0)
    else:
      ctx.openGuard()
      let condCh = convertExpr(node[0], ctx)
      ctx.closeGuard()
      let thenCh = convertExpr(node[1], ctx)
      let elseCh = if acc.isNil: irLit(0) else: acc
      acc = irIf(if condCh.isNil: irLit(0) else: condCh,
                 if thenCh.isNil: irLit(0) else: thenCh,
                 elseCh)
  acc

func convertIfStmt*(n: NimNode, ctx: var IrContext): IRExpr =
  ## Alias: convertIfExpr handles both forms.
  convertIfExpr(n, ctx)

# ---------------------------------------------------------------------------
# Case statement conversion
# ---------------------------------------------------------------------------

func convertCaseStmt*(n: NimNode, ctx: var IrContext): IRExpr =
  ## Convert nnkCaseStmt to irCase.
  ## Structure: nnkCaseStmt(scrutinee, ofBranches..., else?)
  let scrutinee = convertExpr(n[0], ctx)
  var branches: seq[CaseBranch]
  var default: IRExpr = nil
  for i in 1..<n.len:
    let child = n[i]
    case child.kind
    of nnkOfBranch:
      let pattern = child[0]
      let body = convertExpr(child[1], ctx)
      if body == nil:
        continue
      case pattern.kind
      of nnkIntLit, nnkInt64Lit:
        branches.add(CaseBranch(pattern: pattern.intVal, body: body))
      of nnkSym:
        # Quirk (Nim 2.2.10): `intVal` is a compiler magic (lib/core/macros.nim,
        # {.magic: "NIntVal."}); its VM op (compiler/vm.nim, opcNIntVal) returns
        # `sym.position` for `skEnumField` only — every other nnkSym takes the
        # `errFieldXNotFound` branch, a Defect that no `try/except` can catch.
        # So this read is a latent crash on the general case, and even where it
        # succeeds the ordinal is a compiler semantic fact this converter does not
        # model; deriving it here would make the translator a second semantic
        # authority.  Fail closed: record the loss and take the wildcard path.
        markGuardLoss(ctx)
        if branches.len == 0:
          branches.add(CaseBranch(pattern: 0'i64, body: body))
      else:
        # Complex pattern — treat as wildcard (first match wins)
        if branches.len == 0:
          branches.add(CaseBranch(pattern: 0'i64, body: body))
    of nnkElse:
      default = convertExpr(child[0], ctx)
    else: discard
  irCase(scrutinee, branches, default)
# ---------------------------------------------------------------------------
# Loop analysis helpers
# ---------------------------------------------------------------------------

func collectLoopVarTargets(body: NimNode): seq[string] =
  ## Walk a loop body AST and collect all variable names that are assigned to.
  ## Returns unique variable names (no duplicates, excludes "result").
  result = @[]
  for child in body:
    case child.kind
    of nnkAsgn:
      if child[0].kind == nnkIdent:
        let name = child[0].strVal
        if name notin result and name != "result":
          result.add(name)
    of nnkVarSection:
      for identDefs in child:
        if identDefs.kind == nnkIdentDefs and identDefs[0].kind == nnkIdent:
          let name = identDefs[0].strVal
          if name notin result:
            result.add(name)
    else:
      # Recurse into nested blocks
      if child.kind in {nnkStmtList, nnkIfStmt, nnkIfExpr, nnkElifBranch,
                         nnkElse, nnkCaseStmt, nnkOfBranch, nnkForStmt,
                         nnkWhileStmt, nnkBlockStmt}:
        for sub in collectLoopVarTargets(child):
          if sub notin result:
            result.add(sub)

func extractWhileVariant(cond: NimNode, loopVars: seq[string]): NimNode =
  ## Detect `while var < expr` and return `expr - var` as termination metric.
  ## Only matches direct nnkInfix(`<`, var, bound) where var ∈ loopVars.
  ## Returns nil if pattern doesn't match (fallback to fuel in Lean backend).
  if cond.kind == nnkInfix and cond[0].strVal == "<":
    let lhsName = if cond[1].kind == nnkIdent: cond[1].strVal else: ""
    if lhsName in loopVars:
      return newCall("-", cond[2].copyNimTree, cond[1].copyNimTree)
  nil

func hasEarlyReturn(body: NimNode): bool =
  ## Check if a loop body contains nnkReturnStmt or nnkBreakStmt.
  for child in body:
    if child.kind in {nnkReturnStmt, nnkBreakStmt}:
      return true
    if child.kind in {nnkStmtList, nnkIfStmt, nnkIfExpr, nnkElifBranch,
                       nnkElse, nnkCaseStmt, nnkOfBranch, nnkForStmt,
                       nnkWhileStmt, nnkBlockStmt}:
      if hasEarlyReturn(child):
        return true

# ---------------------------------------------------------------------------
# Body conversion (handles let bindings + final expression)
# ---------------------------------------------------------------------------

func isEarlyReturnIf(stmt: NimNode): bool =
  ## True if `stmt` is a single-branch nnkIfStmt whose then-branch is an early
  ## `return`. Requires exactly one branch (no elif/else) to keep the
  ## transformation conservative — side-effect `if`s are left untouched.
  if stmt.kind != nnkIfStmt or stmt.len != 1: return false
  let branch = stmt[0]
  if branch.kind != nnkElifBranch or branch.len < 2: return false
  let thenBody = branch[1]
  thenBody.kind == nnkStmtList and thenBody.len > 0 and
    thenBody[0].kind == nnkReturnStmt

func extractReturnValue(thenBody: NimNode): NimNode =
  ## Extract the value expression from an early-return then-branch.
  ## Assumes the first statement is nnkReturnStmt. Returns the return value
  ## node, or a literal 0 for a bare `return`.
  let ret = thenBody[0]
  if ret.kind == nnkReturnStmt and ret.len > 0 and ret[0].kind != nnkEmpty:
    ret[0]
  else:
    newLit(0)

func convertBodyFrom(stmts: NimNode, idx: int, ctx: var IrContext): IRExpr =
  ## Recursively convert statements starting at index `idx`.
  ## On an early-return `if`, emit `irIf(cond, retVal, rest)` where `rest` is
  ## the remaining statements converted recursively; let bindings accumulated
  ## before the `if` wrap the entire chain so both branches stay in scope.
  var letBindings: seq[(string, IRExpr, bool)] = @[]
  var bodyExpr: NimNode = nil
  var i = idx
  while i < stmts.len:
    let child = stmts[i]
    case child.kind
    of nnkIfStmt:
      if isEarlyReturnIf(child):
        ctx.openGuard()
        let cond = convertExpr(child[0][0], ctx)
        ctx.closeGuard()
        let retVal = convertExpr(extractReturnValue(child[0][1]), ctx)
        let elseExpr = convertBodyFrom(stmts, i + 1, ctx)
        var body = irIf(cond, retVal, elseExpr)
        for j in countdown(letBindings.len - 1, 0):
          body = irLet(letBindings[j][0], letBindings[j][1], body, letBindings[j][2])
        return body
      else:
        bodyExpr = child
    of nnkLetSection:
      for identDefs in child:
        if identDefs.kind == nnkIdentDefs and identDefs.len >= 3:
          let name = stripGensym(identDefs[0].strVal)
          let mark = ctx.exprLoss
          let value = convertExpr(identDefs[2], ctx)
          ctx.recordBinding(name, "stmt[" & $i & "]/let", value, mark, false)
          letBindings.add((name, value, false))
    of nnkConstSection:
      # WP4-j.2: preserve compile-time bindings — never dropped, never guessed.
      # NOTE: const sections contain nnkConstDef nodes (not nnkIdentDefs).
      for identDefs in child:
        if identDefs.kind in {nnkIdentDefs, nnkConstDef} and identDefs.len >= 3:
          let name = stripGensym(identDefs[0].strVal)
          let mark = ctx.exprLoss
          let value = convertExpr(identDefs[2], ctx)
          ctx.recordBinding(name, "stmt[" & $i & "]/const", value, mark, true)
          letBindings.add((name, value, true))
    of nnkVarSection:
      for identDefs in child:
        if identDefs.kind == nnkIdentDefs and identDefs.len >= 3:
          let name = stripGensym(identDefs[0].strVal)
          let mark = ctx.exprLoss
          let value = convertExpr(identDefs[2], ctx)
          ctx.recordBinding(name, "stmt[" & $i & "]/var", value, mark, false)
          letBindings.add((name, value, false))
    of nnkAsgn:
      let target = child[0]
      if target.kind == nnkIdent and target.strVal != "result":
        let mark = ctx.exprLoss
        let value = convertExpr(child[1], ctx)
        ctx.recordBinding(target.strVal, "stmt[" & $i & "]/assign", value, mark, false)
        letBindings.add((target.strVal, value, false))
      else:
        bodyExpr = child[1]
    of nnkReturnStmt:
      if child.len > 0 and child[0].kind != nnkEmpty:
        bodyExpr = child[0]
    of nnkDiscardStmt:
      discard
    of nnkStmtListExpr:
      bodyExpr = child
    of nnkForStmt:
      # child[0] = loop variable(s) (nnkIdent or nnkVarTuple for tuple unpacking)
      # child[1] = iterable (range expression or collection)
      # child[2] = body (nnkStmtList)

      # Detect range-based loop: for i in 0..<N or for i in a..b
      let isRange = child[1].kind == nnkInfix and
                    child[1].len >= 3 and
                    (child[1][0].strVal == "<..<" or child[1][0].strVal == "..")

      if isRange:
        # Range-based loop: for i in 0..<N: body
        # child[0] = loop variable (nnkIdent)
        # child[1] = range expression (nnkInfix "<..<" or "..")
        # child[2] = body (nnkStmtList)
        let loopVarName = child[0].strVal
        # Collect mutable state variables in the loop body
        var stateVars = collectLoopVarTargets(child[2])
        # Remove the loop variable itself from state vars (it's handled by loopStep)
        var filtered: seq[string] = @[]
        for sv in stateVars:
          if sv != loopVarName:
            filtered.add(sv)
        stateVars = filtered
        # Detect early return
        let hasReturn = hasEarlyReturn(child[2])
        if hasReturn:
          stateVars.add("hasReturned")
          stateVars.add("exitValue")
        # Build loopVars: [loopVarName] + stateVars
        let allVars = @[loopVarName] & stateVars
        # Build loopInits from var declarations
        var inits: seq[IRExpr] = @[]
        inits.add(convertExpr(child[1][1], ctx))  # start of range
        # For state vars, find their initial values from the body's var sections
        for sv in stateVars:
          if sv == "hasReturned":
            inits.add(IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))  # false
          elif sv == "exitValue":
            inits.add(IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))  # default
          else:
            # Look for var declaration in body
            var found = false
            for bodyChild in child[2]:
              if bodyChild.kind == nnkVarSection:
                for identDefs in bodyChild:
                  if identDefs.kind == nnkIdentDefs and identDefs[0].strVal == sv:
                    if identDefs[2].kind != nnkEmpty:
                      inits.add(convertExpr(identDefs[2], ctx))
                      found = true
                    else:
                      inits.add(IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))
                      found = true
              if found: break
            if not found:
              inits.add(IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))
        # Build loopCond
        ctx.openGuard()
        let endExpr = convertExpr(child[1][2], ctx)  # end of range
        ctx.closeGuard()
        var cond: IRExpr = IRExpr(typ: irTypeBool(), kind: irBinOp, binOp: boLt,
          binLhs: IRExpr(typ: irTypeBitVec64(), kind: irVar, varName: loopVarName, varType: irTypeBitVec64()),
          binRhs: endExpr)
        if hasReturn:
          cond = IRExpr(typ: irTypeBool(), kind: irBinOp, binOp: boAnd,
            binLhs: cond,
            binRhs: IRExpr(typ: irTypeBool(), kind: irUnaryOp, unaryOp: uoNot,
              unaryArg: IRExpr(typ: irTypeBool(), kind: irVar, varName: "hasReturned", varType: irTypeBool())))
        # Build loopStep (increment loop variable)
        let step = IRExpr(typ: irTypeBitVec64(), kind: irBinOp, binOp: boAdd,
          binLhs: IRExpr(typ: irTypeBitVec64(), kind: irVar, varName: loopVarName, varType: irTypeBitVec64()),
          binRhs: IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 1))
        # Build loopBody — convert the loop body statements
        let loopBody = convertBody(child[2], ctx)
        # Create the irLoop expression
        let loopExpr = IRExpr(typ: irTypeBitVec64(), kind: irLoop,
          loopKind: lkFor,
          loopVars: allVars,
          loopInits: inits,
          loopCond: cond,
          loopStep: step,
          loopBody: loopBody,
          loopInvariants: @[],
          loopVariant: nil)
        letBindings.add(("_loop_result", loopExpr, false))
      else:
        # Collection iteration desugaring:
        #   for item in collection: body(item)
        #     → let _col = collection
        #       for _i in 0..<_col.len:
        #         let item = _col[_i]
        #         body(item)
        #
        #   for idx, item in collection: body(idx, item)
        #     → let _col = collection
        #       for _i in 0..<_col.len:
        #         let item = _col[_i]
        #         let idx = _i
        #         body(idx, item)
        let colSym = genSym(nskLet, "col")
        let idxSym = genSym(nskLet, "i")

        # Build desugared AST as nnkStmtList
        var newStmts = nnkStmtList.newTree()

        # let colSym = collection
        newStmts.add(
          nnkLetSection.newTree(
            nnkIdentDefs.newTree(
              colSym,
              newEmptyNode(),
              child[1]  # collection expression
            )
          )
        )

        # Build range: 0..<colSym.len
        let rangeExpr = nnkInfix.newTree(
          ident("<..<"),
          newLit(0),
          nnkCall.newTree(ident("len"), colSym)
        )

        # Build inner body
        var innerBody = nnkStmtList.newTree()

        # Add let-binding(s) for the loop variable(s)
        if child[0].kind == nnkVarTuple:
          # Tuple unpacking: for idx, item in collection
          # child[0] children are the variable names (nnkIdent/nnkSym)
          for i in 0..<child[0].len:
            let varNode = child[0][i]
            if varNode.kind in {nnkIdent, nnkSym}:
              if i == 0:
                # Index variable: let idx = _i
                innerBody.add(
                  nnkLetSection.newTree(
                    nnkIdentDefs.newTree(
                      varNode,
                      newEmptyNode(),
                      idxSym
                    )
                  )
                )
              elif i == 1:
                # Element variable: let item = _col[_i]
                innerBody.add(
                  nnkLetSection.newTree(
                    nnkIdentDefs.newTree(
                      varNode,
                      newEmptyNode(),
                      nnkBracketExpr.newTree(colSym, idxSym)
                    )
                  )
                )
        else:
          # Single variable: let item = _col[_i]
          innerBody.add(
            nnkLetSection.newTree(
              nnkIdentDefs.newTree(
                child[0],
                newEmptyNode(),
                nnkBracketExpr.newTree(colSym, idxSym)
              )
            )
          )

        # Add original body statements
        for stmt in child[2]:
          innerBody.add(stmt)

        # Build the for loop: for _i in 0..<_col.len: innerBody
        newStmts.add(
          nnkForStmt.newTree(
            idxSym,
            rangeExpr,
            innerBody
          )
        )

        # Recursively process the desugared AST
        let desugaredResult = convertBody(newStmts, ctx)
        letBindings.add(("_loop_result", desugaredResult, false))
    of nnkWhileStmt:
      # while cond: body
      # child[0] = condition
      # child[1] = body (nnkStmtList)
      var stateVars = collectLoopVarTargets(child[1])
      let hasReturn = hasEarlyReturn(child[1])
      if hasReturn:
        stateVars.add("hasReturned")
        stateVars.add("exitValue")
      let allVars = stateVars
      # Build loopInits
      var inits: seq[IRExpr] = @[]
      for sv in stateVars:
        if sv == "hasReturned":
          inits.add(IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))
        elif sv == "exitValue":
          inits.add(IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))
        else:
          var found = false
          for bodyChild in child[1]:
            if bodyChild.kind == nnkVarSection:
              for identDefs in bodyChild:
                if identDefs.kind == nnkIdentDefs and identDefs[0].strVal == sv:
                  if identDefs[2].kind != nnkEmpty:
                    inits.add(convertExpr(identDefs[2], ctx))
                    found = true
                  else:
                    inits.add(IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))
                    found = true
            if found: break
          if not found:
            inits.add(IRExpr(typ: irTypeBitVec64(), kind: irLit, litVal: 0))
      # Build loopCond
      ctx.openGuard()
      var cond = convertExpr(child[0], ctx)
      ctx.closeGuard()
      if hasReturn:
        cond = IRExpr(typ: irTypeBool(), kind: irBinOp, binOp: boAnd,
          binLhs: cond,
          binRhs: IRExpr(typ: irTypeBool(), kind: irUnaryOp, unaryOp: uoNot,
            unaryArg: IRExpr(typ: irTypeBool(), kind: irVar, varName: "hasReturned", varType: irTypeBool())))
      # Build loopBody
      let loopBody = convertBody(child[1], ctx)
      # Extract termination variant for well-founded metric
      let variantAst = extractWhileVariant(child[0], allVars)
      let loopVariant = if variantAst != nil: convertExpr(variantAst, ctx) else: nil
      # Create the irLoop expression
      let loopExpr = IRExpr(typ: irTypeBitVec64(), kind: irLoop,
        loopKind: lkWhile,
        loopVars: allVars,
        loopInits: inits,
        loopCond: cond,
        loopStep: nil,
        loopBody: loopBody,
        loopInvariants: @[],
        loopVariant: loopVariant)
      letBindings.add(("_loop_result", loopExpr, false))
    else:
      # WP4-j.2: unhandled statement kind — record the drop instead of silently
      # discarding the statement. A drop is not an expression-level loss when the
      # statement hides no declaration: converting it as the trailing expression
      # still reaches every sub-expression.
      if traversesSubtreeAsExpression(child.kind): markLoss(ctx)
      else: markRegionDrop(ctx)
      bodyExpr = child
    inc i
  var body = if bodyExpr != nil: convertExpr(bodyExpr, ctx)
             else: irLit(0)
  for i in countdown(letBindings.len - 1, 0):
    body = irLet(letBindings[i][0], letBindings[i][1], body, letBindings[i][2])
  body

func convertBody*(stmts: NimNode, ctx: var IrContext): IRExpr =
  ## Convert a nnkStmtList body to IR.
  ## Let bindings → nested irLet; final expression → body.
  ## Early-return `if` statements are converted into an irIf chain whose else
  ## branch is the remainder of the statement list (recursively converted).
  convertBodyFrom(stmts, 0, ctx)

# ── CanonNode read-only conversion functions (M4) ──────────────
# These operate on CanonNode for read-only AST analysis.
# The NimNode versions above handle AST construction/manipulation.
# Hybrid boundary: see tools/shared/canonical_ast.nim §5.

# ── CanonNode read-only conversion functions (M4) ──────────
# These are simplified read-only analysis versions.
# Full AST construction (newTree, genSym, etc.) remains NimNode-only.

func convertDotExprCanon(n: CanonNode, ctx: var IrContext): IRExpr =
  ## Field access: obj.field → irCall("field", @[obj]) — the CanonNode mirror
  ## of convertDotExpr, including its bottom-up field typing.
  if n.children.len < 2:
    return nil
  let fieldName = n.children[1].name
  let obj = convertExprCanon(n.children[0], ctx)
  if obj == nil:
    return irVar(fieldName, irTypeBitVec64())
  let callRetType = inferFieldAccessType(obj, fieldName)
  if callRetType != nil:
    irCall(fieldName, @[obj], callRetType)
  else:
    irCall(fieldName, @[obj])

func convertBracketExprCanon(n: CanonNode, ctx: var IrContext): IRExpr =
  ## Index access `a[i]` → irCall("[]", [a, i]), the exact shape
  ## contract_synthesis.indexGuard reads to build a bounds guard (sequence at
  ## args[0], index at args[^1]). Both operands are the source's own
  ## expressions: the length the guard compares against stays the `len` call
  ## indexGuard itself emits, so no length and no bound is invented here.
  if n.children.len < 2:
    markLoss(ctx)
    return irLit(0)
  let seqExpr = convertExprCanon(n.children[0], ctx)
  let idxExpr = convertExprCanon(n.children[n.children.len - 1], ctx)
  irCall("[]", @[seqExpr, idxExpr])

func convertPrefixCanon(n: CanonNode, ctx: var IrContext): IRExpr =
  ## Prefix application: only the two operators with a distinct IR spelling are
  ## named. As in convertPrefix, an operator this IR cannot express counts a
  ## loss instead of borrowing the negation reading.
  let op = n.children[0].name
  let arg = convertExprCanon(n.children[1], ctx)
  case op
  of "-": irBvNeg(arg)
  of "not": irNot(arg)
  else:
    markLoss(ctx)
    irLit(0)

func convertCallCanon(n: CanonNode, ctx: var IrContext): IRExpr =
  ## Call application. A callee naming the enclosing function is the IR's
  ## recursive-call node; every other callee stays an ordinary call.
  let calleeName = n.children[0].name
  var args: seq[IRExpr]
  for i in 1..<n.children.len:
    args.add(convertExprCanon(n.children[i], ctx))
  # Same fail-closed rule as the NimNode path: layout intrinsics are
  # preserved unevaluated and carry no value this IR can represent.
  if isLayoutIntrinsic(calleeName):
    markLoss(ctx)
  if calleeName == ctx.funcName: irRecCall(args)
  else: irCall(calleeName, args)

func convertExprCanon*(n: CanonNode, ctx: var IrContext): IRExpr =
  ## CanonNode read-only version of convertExpr.
  case n.kind
  of ckIntLit, ckInt64Lit, ckInt32Lit, ckInt16Lit, ckInt8Lit:
    irLit(int64(n.intVal))
  of ckUIntLit, ckUInt64Lit, ckUInt32Lit, ckUInt16Lit, ckUInt8Lit:
    irLit(int64(n.intVal))
  of ckFloatLit, ckFloat64Lit, ckFloat32Lit, ckFloat128Lit:
    irFloatLit(n.floatVal)
  of ckIdent, ckSym:
    # A compiler-resolved symbol names what its identifier names: the bare
    # name, with no type and no value claimed for it.
    let name = stripGensym(n.name)
    irVar(name, ctx.typeEnv.getOrDefault(name, irTypeBitVec64()))
  of ckDotExpr:
    convertDotExprCanon(n, ctx)
  of ckBracketExpr:
    convertBracketExprCanon(n, ctx)
  of ckInfix:
    let op = n.children[0].name
    let lhs = convertExprCanon(n.children[1], ctx)
    let rhs = convertExprCanon(n.children[2], ctx)
    irBinOp(convertBinOpCanonUnsigned(op, n.children[1], n.children[2], ctx),
            lhs, rhs)
  of ckPrefix:
    convertPrefixCanon(n, ctx)
  of ckCall:
    convertCallCanon(n, ctx)
  of ckIfExpr, ckElifExpr, ckElseExpr, ckIfStmt:
    # ckIfStmt mirrors the NimNode path (convertExpr: nnkIfExpr/nnkIfStmt →
    # convertIfExpr): a statement-form if reached in expression position —
    # e.g. pragma-context `(if c: a else: b)` parsed as
    # nkStmtListExpr(nkIfStmt(nkElifExpr, nkElseExpr)) — unwraps through
    # ckStmtListExpr to here, and convertIfExprCanon already collects both
    # branch families (ckElifExpr/ckElifBranch, ckElseExpr/ckElse).
    convertIfExprCanon(n, ctx)
  of ckCaseStmt:
    convertCaseStmtCanon(n, ctx)
  of ckStmtList:
    convertBodyCanon(n, ctx)
  of ckStmtListExpr:
    if n.children.len == 1: convertExprCanon(n.children[0], ctx)
    else: convertBodyCanon(n, ctx)
  of ckStrLit, ckRStrLit, ckTripleStrLit:
    IRExpr(typ: irTypeString(), kind: irStringLit, stringVal: n.strVal)
  of ckCharLit:
    irLit(int64(n.intVal))
  of ckNilLit:
    irLit(0)
  of ckPar:
    # Mirror the NimNode path (nnkPar → convertExpr(n[0])): a parenthesized
    # expression denotes the same value as its content. A multi-child ckPar
    # has no single content expression, so it stays loss-marked like every
    # other shape this translator cannot represent.
    if n.children.len == 1: convertExprCanon(n.children[0], ctx)
    else:
      markLoss(ctx)
      irLit(0)
  of ckReturnStmt:
    if n.children.len > 0 and n.children[0].kind != ckEmpty:
      convertExprCanon(n.children[0], ctx)
    else:
      irLit(0)
  else:
    # WP4-j.2: unhandled expression kind — record loss instead of silent drop.
    # Mirrors the NimNode path above; returning irLit(0) here without the flag
    # would hide the loss behind a plausible-looking zero.
    markLoss(ctx)
    irLit(0)

func convertIfExprCanon*(n: CanonNode, ctx: var IrContext): IRExpr =
  ## CanonNode read-only version of convertIfExpr.
  type BranchKind = enum bkCondition, bkFinal
  var branches: seq[(BranchKind, CanonNode)] = @[]
  for child in n.children:
    case child.kind
    of ckElifExpr, ckElifBranch: branches.add((bkCondition, child))
    of ckElseExpr, ckElse: branches.add((bkFinal, child))
    else: discard
  if branches.len == 0: return irLit(0)
  var acc: IRExpr = nil
  for i in countdown(branches.len - 1, 0):
    let (kind, node) = branches[i]
    if kind == bkFinal:
      acc = convertExprCanon(node.children[0], ctx)
      if acc.isNil: acc = irLit(0)
    else:
      ctx.openGuard()
      let condCh = convertExprCanon(node.children[0], ctx)
      ctx.closeGuard()
      let thenCh = convertExprCanon(node.children[1], ctx)
      let elseCh = if acc.isNil: irLit(0) else: acc
      acc = irIf(if condCh.isNil: irLit(0) else: condCh,
                 if thenCh.isNil: irLit(0) else: thenCh,
                 elseCh)
  acc

func convertCaseStmtCanon*(n: CanonNode, ctx: var IrContext): IRExpr =
  ## CanonNode read-only version of convertCaseStmt.
  let scrutinee = convertExprCanon(n.children[0], ctx)
  var branches: seq[CaseBranch]
  var default: IRExpr = nil
  for i in 1..<n.children.len:
    let child = n.children[i]
    case child.kind
    of ckOfBranch:
      let pattern = child.children[0]
      let body = convertExprCanon(child.children[1], ctx)
      if body.isNil: continue
      case pattern.kind
      of ckIntLit, ckInt64Lit:
        branches.add(CaseBranch(pattern: pattern.intVal, body: body))
      of ckSym:
        # CanonNode mirror of nnkSym: toCanon (tools/shared/canonical_ast.nim)
        # zeroes intVal for every non-literal kind, so `pattern.intVal` does not
        # crash here — it silently reads ordinal 0 for every enum symbol, which
        # is the worse outcome (a wrong known value instead of a recorded loss).
        # Fail closed: record the loss and take the wildcard path.
        markGuardLoss(ctx)
        if branches.len == 0:
          branches.add(CaseBranch(pattern: 0'i64, body: body))
      else:
        if branches.len == 0:
          branches.add(CaseBranch(pattern: 0'i64, body: body))
    of ckElse:
      default = convertExprCanon(child.children[0], ctx)
    else: discard
  irCase(scrutinee, branches, default)

func isEarlyReturnIfCanon(stmt: CanonNode): bool =
  ## CanonNode read-only version of isEarlyReturnIf.
  ## True if `stmt` is a single-branch ckIfStmt whose then-branch is an early
  ## `return`. Requires exactly one branch (no elif/else) to keep the
  ## transformation conservative — side-effect `if`s are left untouched.
  if stmt.kind != ckIfStmt or getChildCount(stmt) != 1: return false
  let branch = getChild(stmt, 0)
  if branch.kind != ckElifBranch or getChildCount(branch) < 2: return false
  let thenBody = getChild(branch, 1)
  thenBody.kind == ckStmtList and getChildCount(thenBody) > 0 and
    getChild(thenBody, 0).kind == ckReturnStmt

func extractReturnValueCanon(thenBody: CanonNode): CanonNode =
  ## CanonNode read-only version of extractReturnValue.
  ## Extract the value expression from an early-return then-branch.
  ## Assumes the first statement is ckReturnStmt. Returns the return value
  ## node, or a literal 0 for a bare `return`.
  let ret = getChild(thenBody, 0)
  if ret.kind == ckReturnStmt and getChildCount(ret) > 0 and
      getChild(ret, 0).kind != ckEmpty:
    getChild(ret, 0)
  else:
    CanonNode(kind: ckIntLit, intVal: 0)

func convertBodyCanon*(stmts: CanonNode, ctx: var IrContext): IRExpr =
  ## CanonNode read-only version of convertBody.
  convertBodyFromCanon(stmts, 0, ctx)

func convertBodyFromCanon(stmts: CanonNode, idx: int, ctx: var IrContext): IRExpr =
  ## CanonNode read-only version of convertBodyFrom.
  var letBindings: seq[(string, IRExpr, bool)] = @[]
  var bodyExpr = newNode(ckUnknown)
  var i = idx
  while i < getChildCount(stmts):
    let child = getChild(stmts, i)
    case child.kind
    of ckIfStmt:
      if isEarlyReturnIfCanon(child):
        ctx.openGuard()
        let cond = convertExprCanon(getChild(getChild(child, 0), 0), ctx)
        ctx.closeGuard()
        let retVal = convertExprCanon(
          extractReturnValueCanon(getChild(getChild(child, 0), 1)), ctx)
        let elseExpr = convertBodyFromCanon(stmts, i + 1, ctx)
        var body = irIf(cond, retVal, elseExpr)
        for j in countdown(letBindings.len - 1, 0):
          body = irLet(letBindings[j][0], letBindings[j][1], body, letBindings[j][2])
        return body
      else:
        bodyExpr = child
    of ckLetSection:
      for identDefs in getChildren(child):
        if identDefs.kind == ckIdentDefs and getChildCount(identDefs) >= 3:
          let name = stripGensym(getChild(identDefs, 0).name)
          let mark = ctx.exprLoss
          let value = convertExprCanon(getChild(identDefs, 2), ctx)
          ctx.recordBinding(name, "stmt[" & $i & "]/let", value, mark, false)
          letBindings.add((name, value, false))
    of ckConstSection:
      # WP4-j.2: preserve compile-time bindings — never dropped, never guessed.
      # NOTE: const sections contain ckConstDef nodes (not ckIdentDefs).
      for identDefs in getChildren(child):
        if identDefs.kind in {ckIdentDefs, ckConstDef} and getChildCount(identDefs) >= 3:
          let name = stripGensym(getChild(identDefs, 0).name)
          let mark = ctx.exprLoss
          let value = convertExprCanon(getChild(identDefs, 2), ctx)
          ctx.recordBinding(name, "stmt[" & $i & "]/const", value, mark, true)
          letBindings.add((name, value, true))
    of ckVarSection:
      for identDefs in getChildren(child):
        if identDefs.kind == ckIdentDefs and getChildCount(identDefs) >= 3:
          let name = stripGensym(getChild(identDefs, 0).name)
          let mark = ctx.exprLoss
          let value = convertExprCanon(getChild(identDefs, 2), ctx)
          ctx.recordBinding(name, "stmt[" & $i & "]/var", value, mark, false)
          letBindings.add((name, value, false))
    of ckAsgn:
      let target = getChild(child, 0)
      if target.kind == ckIdent and target.name != "result":
        let mark = ctx.exprLoss
        let value = convertExprCanon(getChild(child, 1), ctx)
        ctx.recordBinding(target.name, "stmt[" & $i & "]/assign", value, mark, false)
        letBindings.add((target.name, value, false))
      else:
        bodyExpr = getChild(child, 1)
    of ckReturnStmt:
      if getChildCount(child) > 0 and getChild(child, 0).kind != ckEmpty:
        bodyExpr = getChild(child, 0)
    of ckDiscardStmt:
      discard
    of ckStmtListExpr:
      bodyExpr = child
    of ckForStmt, ckWhileStmt:
      # Range/collection loops: simplified CanonNode read-only path.
      # Full desugaring (newTree, genSym) remains NimNode-only.
      # The loop body is not translated on this path, so a binding declared
      # inside it never reaches `recordedBindings` — the same blind spot a
      # dropped statement form creates.
      markRegionDrop(ctx)
      bodyExpr = child
    else:
      # WP4-j.2: unhandled statement kind — record the drop instead of silently
      # discarding the statement (see markRegionDrop on why this is not an
      # expression-level loss).
      #
      # `ckUnknown` on the PNode path is what an unmapped leaf expression becomes
      # — a deref, a dot-call — and `ckCommentStmt` is a documentation comment.
      # Neither holds a declaration, so neither can hide one; requiring the node
      # to be childless keeps that reading from extending to a kind this table
      # has never seen and which does carry statements.
      if child.kind in {ckUnknown, ckCommentStmt} and child.children.len == 0: markLoss(ctx)
      elif traversesSubtreeAsExpression(child.kind): markLoss(ctx)
      else: markRegionDrop(ctx)
      bodyExpr = child
    inc i
  var body = if bodyExpr.kind != ckUnknown: convertExprCanon(bodyExpr, ctx)
             else: irLit(0)
  for i in countdown(letBindings.len - 1, 0):
    body = irLet(letBindings[i][0], letBindings[i][1], body, letBindings[i][2])
  body

# ---------------------------------------------------------------------------
func containsRecCall*(n: NimNode, funcName: string): bool =
  ## Check if AST contains a recursive call to funcName.
  if n.kind == nnkCall:
    let callee = n[0]
    let calleeName = case callee.kind
      of nnkIdent, nnkSym: callee.strVal
      of nnkDotExpr: callee[1].strVal
      of nnkOpenSymChoice, nnkClosedSymChoice:
        if callee.len > 0: callee[0].strVal
        else: ""
      else: ""
    if calleeName == funcName:
      return true
  for child in n:
    if containsRecCall(child, funcName):
      return true
  false

# ── CanonNode read-only versions (M5) ────────────────────────

func containsRecCallCanon(n: CanonNode, funcName: string): bool =
  ## CanonNode read-only version of containsRecCall.
  if n.kind == ckCall and getChildCount(n) > 0:
    let calleeNode = getChild(n, 0)
    var calleeName = ""
    case calleeNode.kind
    of ckIdent, ckSym: calleeName = calleeNode.name
    of ckDotExpr:
      if getChildCount(calleeNode) > 0: calleeName = getChild(calleeNode, 1).name
    else: discard
    if calleeName == funcName:
      return true
  for child in getChildren(n):
    if containsRecCallCanon(child, funcName):
      return true
  false

# ---------------------------------------------------------------------------
# Function definition conversion
# ---------------------------------------------------------------------------
func scopedLossEvidence(ctx: IrContext): (bool, bool) {.raises: [].} =
  ## The two scoped claims a caller certifies a binding channel against.
  ##
  ## `propositionRegionLossFree` holds when nothing a proof obligation is derived
  ## from was fabricated: no loss inside a guard or loop condition, and no
  ## statement form dropped whole (a drop hides the bindings below it rather
  ## than marking them lossy, so name uniqueness over the survivors would
  ## certify a shadowed name).
  ##
  ## `lossOutsideBindingRegions` holds when the function lost something in a
  ## region neither claim above covers. The bindings and guards are then
  ## faithful while the obligation set may not be — a coverage statement, never
  ## a rejection.
  let clean = ctx.guardLoss == 0 and ctx.regionDrops == 0
  var bindingsClean = true
  for b in ctx.bindings:
    if not b.lossFree: bindingsClean = false
  (clean, ctx.lossySeen and clean and bindingsClean)

func convertFuncDef*(n: NimNode): IRFuncDef =
  ## Converts a Nim function/procedure definition AST node (nnkFuncDef | nnkProcDef)
  ## to IRFuncDef.
  ## nnkMethodDef is intentionally excluded: dynamic dispatch (vtable) is outside the static proposition-extraction scope.
  if n.kind notin {nnkFuncDef, nnkProcDef}:
    return IRFuncDef(name: "", params: @[], retType: irTypeBitVec64(),
                     body: irLit(0), isRecursive: false)
  # Extract name (handle nnkPostfix with * export marker)
  let nameNode = n[0]
  let name = stripGensym(case nameNode.kind
    of nnkPostfix: nameNode[1].strVal
    of nnkIdent: nameNode.strVal
    else: "")
  # Formal params (index 3)
  let formalParams = n[3]
  if formalParams.kind != nnkFormalParams:
    return IRFuncDef(name: name, params: @[], retType: irTypeBitVec64(),
                     body: irLit(0), isRecursive: false)
  # Return type (index 0 of formalParams)
  let retType = if formalParams[0].kind != nnkEmpty:
    convertType(formalParams[0])
  else:
    irTypeBitVec64()
  # Parameters (indices 1+)
  var params: seq[IRFuncParam]
  var unsignedNames: seq[string] = @[]
  for i in 1..<formalParams.len:
    let identDefs = formalParams[i]
    if identDefs.kind == nnkIdentDefs and identDefs.len >= 3:
      let typeNode = identDefs[identDefs.len - 2]
      let ty = if typeNode.kind != nnkEmpty: convertType(typeNode)
               else: irTypeBitVec64()
      for j in 0 ..< identDefs.len - 2:
        params.add(IRFuncParam(name: stripGensym(identDefs[j].strVal), ty: ty))
        if nimTypeNodeIsUnsigned(typeNode):
          unsignedNames.add(stripGensym(identDefs[j].strVal))
  # Body (index 6)
  let bodyNode = n[6]
  var ctx = initIrContext(name, params)
  for u in unsignedNames: ctx.unsignedParams.incl(u)
  let body = convertBody(bodyNode, ctx)
  # Detect recursion
  let isRec = containsRecCall(bodyNode, name)
  let (regionClean, outsideLoss) = scopedLossEvidence(ctx)
  IRFuncDef(name: name, params: params, retType: retType,
            body: body, isRecursive: isRec,
            translationLossFree: not ctx.lossySeen,
            recordedBindings: ctx.bindings,
            propositionRegionLossFree: regionClean,
            lossOutsideBindingRegions: outsideLoss)

# ---------------------------------------------------------------------------
# Dependency collection (external calls + recursive functions)
# ---------------------------------------------------------------------------

func inferArgType(a: IRExpr): IRType {.inline.} =
  ## Best-effort type inference from an IRExpr call argument.
  ## Uses explicit typ when available; defaults to BitVec64.
  if a != nil and a.typ != nil: a.typ
  else: irTypeBitVec64()

func collectExternalCalls*(body: IRExpr): seq[IRFuncDecl] =
  ## irExpr에서 외부 함수 호출(irCall)을 수집하여 IRFuncDecl 시퀀스로 반환
  ## 중복 제거 포함
  var seen: seq[string]
  var acc: seq[IRFuncDecl]
  func walk(e: IRExpr) =
    if e == nil: return
    case e.kind
    of irCall:
      # Skip builtin functions — they are inlined, not external
      const irBuiltinsFilter = ["min", "max", "and", "or",
                                "opCastToBool", "opCastToBv64"]
      if e.callName notin irBuiltinsFilter:
        if e.callName notin seen:
          seen.add(e.callName)
          var paramTypes: seq[IRType]
          for a in e.callArgs:
            paramTypes.add(a.inferArgType)
          # Use the irCall node's actual type, not hardcoded BitVec64
          let retTyp = if e.typ != nil: e.typ
                       else: irTypeBitVec64()
          acc.add(IRFuncDecl(name: e.callName, paramTypes: paramTypes,
                             retType: retTyp))
    of irRecCall:
      discard  # 재귀 호출은 별도 처리
    of irBinOp:
      walk(e.binLhs)
      walk(e.binRhs)
    of irUnaryOp:
      walk(e.unaryArg)
    of irIf:
      walk(e.ifCond)
      walk(e.ifThen)
      walk(e.ifElse)
    of irLet:
      walk(e.letVal)
      walk(e.letBody)
    of irCase:
      walk(e.caseScrutinee)
      for br in e.caseBranches:
        walk(br.body)
      if e.caseDefault != nil:
        walk(e.caseDefault)
    of irLoop:
      for v in e.loopInits:
        walk(v)
      if e.loopStep != nil:
        walk(e.loopStep)
      walk(e.loopBody)
    else:
      discard  # irLit, irFloatLit, irVar, irStringLit
  walk(body)
  return acc

func buildIRModule*(funcs: seq[IRFuncDef]): IRModule =
  ## IRFuncDef 시퀀스를 받아 종속성 매니페스트 자동 구성
  result = IRModule(name: "", functions: funcs)
  # Phase 1: 외부 함수 수집
  for fn in funcs:
    let exts = collectExternalCalls(fn.body)
    for ext in exts:
      var found = false
      for existing in result.externalDeclarations:
        if existing.name == ext.name:
          found = true
          break
      if not found:
        result.externalDeclarations.add(ext)
  # Phase 2: 재귀 함수 분리
  for fn in funcs:
    if fn.isRecursive:
      result.recursiveGroup.add(fn)

# ---------------------------------------------------------------------------
# Overflow annotation
# ---------------------------------------------------------------------------
func annotateOverflow*(e: IRExpr): AnnotatedExpr =
  ## Wrap arithmetic operations with overflow checks.
  ## boAdd, boSub and boMul get oNoOverflow — exactly the ops Nim raises
  ## OverflowDefect on (checked builds). The annotation induces an overflow
  ## OBLIGATION (obligation_semantics.md §3.8): ir_to_smt_chunk3.collectOverflowGoals
  ## turns it into a solver goal conjoined with the postcondition, discharged
  ## from preconditions or the function is not verified.
  case e.kind
  of irBinOp:
    case e.binOp
    of boAdd, boSub, boMul:
      AnnotatedExpr(expr: e, overflow: oNoOverflow)
    else:
      AnnotatedExpr(expr: e, overflow: ocNone)
  else:
    AnnotatedExpr(expr: e, overflow: ocNone)

func annotateOverflow*(e: IRExpr; widthBits: int): AnnotatedExpr =
  ## Width-aware annotation: width 64 routes the checked ops to the
  ## oNoOverflowU64 encoding branch (the zero-extend `bvule` forms — the
  ## signed policy is inapplicable: at p ≥ 2^63 a signed reading falsifies
  ## the premises → vacuous emission). Every other width keeps the
  ## narrow/signed annotation unchanged.
  var a = annotateOverflow(e)
  if widthBits == 64 and a.overflow != ocNone:
    a.overflow = oNoOverflowU64
    a.widthBits = 64
  a

# ---------------------------------------------------------------------------
# Main entry point for macro integration
# ---------------------------------------------------------------------------
func axiomBody*(n: NimNode): IRFuncDef =
  ## Main entry point: convert a {.axiom, axiomImpl.} func definition to IR.
  ## Accepts nnkFuncDef or nnkProcDef and returns IRFuncDef.
  case n.kind
  of nnkFuncDef, nnkProcDef:
    convertFuncDef(n)
  else:
    IRFuncDef(name: "", params: @[], retType: irTypeBitVec64(),
              body: irLit(0), isRecursive: false)

{.pop.}

# ── CanonNode read-only versions (M5) ──────────────────────

func convertFuncDefCanon*(n: CanonNode): IRFuncDef =
  ## CanonNode read-only version of convertFuncDef.
  ## Uses CanonNode for structure analysis; NimNode still needed
  ## for getTypeImpl() calls on nnkSym nodes (handled by wrapper).
  if n.kind notin {ckProcDef, ckFuncDef}:
    return IRFuncDef(name: "", params: @[], retType: irTypeBitVec64(),
                     body: irLit(0), isRecursive: false)
  # Extract name (handle ckPostfix with * export marker — mirrors convertFuncDef).
  let nameNode = n.children[0]
  let name = stripGensym(case nameNode.kind
    of ckIdent: nameNode.name
    of ckPostfix:
      if nameNode.children.len > 1 and nameNode.children[1].kind == ckIdent:
        nameNode.children[1].name
      else: ""
    else: "")
  # Formal params (child index 3)
  if n.children.len < 4:
    return IRFuncDef(name: name, params: @[], retType: irTypeBitVec64(),
                     body: irLit(0), isRecursive: false)
  let formalParams = n.children[3]
  if formalParams.kind != ckFormalParams:
    return IRFuncDef(name: name, params: @[], retType: irTypeBitVec64(),
                     body: irLit(0), isRecursive: false)
  # Return type (index 0 of formalParams)
  let retType = if formalParams.children.len > 0 and formalParams.children[0].kind != ckEmpty:
    convertTypeCanon(formalParams.children[0])
  else:
    irTypeBitVec64()
  # Parameters (indices 1+)
  var params: seq[IRFuncParam]
  var unsignedNames: seq[string] = @[]
  for i in 1..<formalParams.children.len:
    let identDefs = formalParams.children[i]
    if identDefs.kind == ckIdentDefs and identDefs.children.len >= 3:
      let typeNode = identDefs.children[identDefs.children.len - 2]
      let ty = if typeNode.kind != ckEmpty: convertTypeCanon(typeNode)
               else: irTypeBitVec64()
      for j in 0 ..< identDefs.children.len - 2:
        params.add(IRFuncParam(name: stripGensym(identDefs.children[j].name), ty: ty))
        if canonTypeNodeIsUnsigned(typeNode):
          unsignedNames.add(stripGensym(identDefs.children[j].name))
  # Body (index 6)
  if n.children.len < 7:
    return IRFuncDef(name: name, params: params, retType: retType,
                     body: irLit(0), isRecursive: false)
  let bodyNode = n.children[6]
  var ctx = initIrContext(name, params)
  for u in unsignedNames: ctx.unsignedParams.incl(u)
  let body = convertBodyCanon(bodyNode, ctx)
  let isRec = containsRecCallCanon(bodyNode, name)
  let (regionClean, outsideLoss) = scopedLossEvidence(ctx)
  IRFuncDef(name: name, params: params, retType: retType,
            body: body, isRecursive: isRec,
            translationLossFree: not ctx.lossySeen,
            recordedBindings: ctx.bindings,
            propositionRegionLossFree: regionClean,
            lossOutsideBindingRegions: outsideLoss)

func axiomBodyCanon*(n: CanonNode): IRFuncDef =
  ## CanonNode read-only entry point.
  case n.kind
  of ckProcDef, ckFuncDef:
    convertFuncDefCanon(n)
  else:
    IRFuncDef(name: "", params: @[], retType: irTypeBitVec64(),
              body: irLit(0), isRecursive: false)
