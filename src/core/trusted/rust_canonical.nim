import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Rust Shared Canonical — the certified-subset canonical representation for
## the Rust subject path (trust_boundary "LLBC to shared canonical translation"
## + "dual IR derivation from shared canonical" — the REPRESENTATION defined
## here; the LLBC→canonical producer remains an open work item, so the
## AxiomTrustBoundary rows stay `exists: false`).
##
## This is a NEW artifact class, deliberately NOT CanonNode (its CanonKind is
## a NimNodeKind mirror — extending it would poison the certified-subset wire
## set and the byte-equality anchor) and NOT LLBC (promoting a Qualified
## channel to identity would pull the Charon format into the TCB surface).
## ADR-0029 D3 / ADR-0030 D3: rustc→LLBC stays Qualified; this canonical is
## the shared INPUT both INV-4 legs derive from
## (docs/spec/certification_continuity_contract.md:249 — different-language
## OR different-derivation legs; shared input is the Nim-path precedent,
## src/verification/extraction_agreement.nim:230-244).
##
## MEASURED CLOSED GRAMMAR (docs/spec/rust_certified_subset.md §1;
## docs/spec/llbc_quirks.md Q2/Q3 — the MEASURED truth, which corrected the
## earlier "exactly these 11 node kinds" reading: the closed grammar is the
## 11 straight-line node kinds below, with `Assert` admitted ONLY inside the
## AddChecked collapse. This is the ONLY grammar the canonical can
## represent; the 3-function probe add_u8 / add_u8_mutant / is_zero
## exercises it):
##
##   straight-line accepted (11)  StorageLive, StorageDead, Assign, Return,
##                                Panic, Use, BinaryOp, AddChecked, Copy,
##                                Move, Constant
##   Assert                       accepted ONLY as part of the AddChecked
##                                collapse — it IS the checked-add overflow
##                                guard; a standalone Assert is rejected
##                                (llbc_quirks Q3)
##   rejected (fail-closed)       Switch, SwitchInt, Call, Goto, Cast, Len,
##                                Discriminant — and every other LLBC node
##                                kind (llbc_quirks Q2: `is_zero` lowers to
##                                `Switch`, so it is OUT OF SCOPE →
##                                rceUnsupportedGrammar → fail-closed
##                                UNKNOWN downstream, never widened)
##
##   LLBC node kind   canonical carrier
##   ---------------  --------------------------------------------------
##   StorageLive      RustStmtKind.rskStorageLive
##   StorageDead      RustStmtKind.rskStorageDead
##   Assign           RustStmtKind.rskAssign
##   Return           RustStmtKind.rskReturn
##   Panic            RustStmtKind.rskPanic
##   Use              RustRvalueKind.rrvUse
##   BinaryOp         RustRvalueKind.rrvBinaryOp  (form rboEq only — plain
##                                                 `+` is AddChecked, NOT
##                                                 BinaryOp add, in the
##                                                 measured probe)
##   AddChecked       RustRvalueKind.rrvAddChecked
##   Copy             RustOperandKind.ropCopy
##   Move             RustOperandKind.ropMove
##   Constant         RustOperandKind.ropConstant
##
## REJECTED (fail-closed — unrepresentable by construction; a producer must
## abort before constructing a canonical, never degrade): every other LLBC
## node kind — i64/signed integer types, wrapping_add, checked_add with
## Result/Option, every arithmetic/comparison form outside {AddChecked,
## BinaryOp-Eq}, every control-flow form (branches, switches, loops, calls,
## aggregates, references). `validateRustCanonical` re-checks the closed shape
## so a hand-built canonical cannot smuggle in a wider surface.
##
## THE FIVE PRESERVED PROPERTIES (INV-4 shared-input constraint):
##   1. function/param identifiers and types — funcName, RustParam, retType
##   2. u8 width and signedness — RustType.widthBits + RustType.signedness are
##      EXPLICIT fields (v1 accepted set: int/8/unsigned, int/32/unsigned,
##      bool/1/unsigned — nothing else validates)
##   3. the AddChecked operation form — RustRvalueKind.rrvAddChecked is a
##      distinct tag; it never decays to a plain add
##   4. the failure-mode fact — failureMode, a TOOL-LAYER fact, see below
##   5. logical module/function path + source identity — modulePath,
##      sourceIdentity, funcName
##
## failureMode IS A TOOL-LAYER FACT, NOT A PROGRAM-MEANING CLAIM.
## Rust integer-overflow behavior is a build-profile choice (debug=panic,
## release=wrap at implementation discretion — docs/spec/rust_certified_subset.md
## §3). `rfmPanicOnOverflowObserved` records what the rustc/Charon tool
## OBSERVED for the build profile this body was extracted from; it does NOT
## assert "this program panics on overflow" as semantics. Per ADR-0030 D2 a
## toolchain-derived fact enters verification only as an fsObserved-capped
## assumption or through fingerprint→evidence identity — never as evidence,
## never as a program premise. The verified domain excludes overflow
## reachability entirely (§1 width-precondition discipline), so both INV-4
## derivation legs are value-path derivations that IGNORE the panic branch
## deterministically (documented at the extraction sites).

type
  RustSignedness* = enum
    rsgUnsigned
    rsgSigned     ## representable in the type triple, REJECTED by the v1
                  ## closed set (no signed integer in the measured probe)

  RustTypeKind* = enum
    rtyInt
    rtyBool

  RustType* = object
    kind*: RustTypeKind
    widthBits*: int            ## EXPLICIT width (property 2); bool = 1
    signedness*: RustSignedness

  RustBinOpForm* = enum
    ## Operation-form tags for BinaryOp. v1 measured only `==`; the v1.3
    ## bool-expression row adds the comparison/boolean forms the short-circuit
    ## collapse needs (`Lt`, `And`, `Or`). Plain `+` on integers remains
    ## AddChecked (a different LLBC kind), not BinaryOp add.
    rboEq
    rboLt
    rboAnd
    rboOr

  RustOperandKind* = enum
    ropCopy
    ropMove
    ropConstant

  RustOperand* = object
    case kind*: RustOperandKind
    of ropCopy, ropMove:
      place*: string
    of ropConstant:
      value*: int64
        ## signed-domain literal [−2^63, 2^63−1] — active iff `valueU64 == 0`
      valueU64*: uint64
        ## u64-domain literal [2^63, 2^64−1] — the ONLY carrier for values
        ## ≥ 2^63; nonzero ⟺ active (never a negative `value` reinterpretation)
      ty*: RustType

  RustRvalueKind* = enum
    rrvUse           ## Use — plain read of one operand
    rrvBinaryOp      ## BinaryOp — form-tagged (rboEq/rboLt/rboAnd/rboOr)
    rrvAddChecked    ## AddChecked — property 3: the checked-add operation
                     ## form; its overflow→Panic edge is carried by
                     ## RustCanonical.failureMode (tool-layer), not re-derived
    rrvExpr          ## the short-circuit collapse's expression tree — the
                     ## ONLY carrier of nested boolean structure (ite + the
                     ## form-tagged comparisons); a straight-line body never
                     ## needs it

  RustExprKind* = enum
    rexOperand       ## leaf: Copy/Move/Constant
    rexBinaryOp      ## form-tagged binary expression
    rexIte           ## if-then-else (the collapsed Switch)

  RustExpr* = ref object
    ## Recursive boolean/int expression tree produced by the Switch collapse.
    ## Types are NOT stored here: the IR derivation reconstructs them from the
    ## operand environment and the operator's result rule (the same closed
    ## rule the straight-line forms use). A nil node is malformed.
    case kind*: RustExprKind
    of rexOperand:
      operand*: RustOperand
    of rexBinaryOp:
      form*: RustBinOpForm
      lhs*, rhs*: RustExpr
    of rexIte:
      cond*, thenExpr*, elseExpr*: RustExpr

  RustRvalue* = object
    case kind*: RustRvalueKind
    of rrvUse:
      operand*: RustOperand
    of rrvBinaryOp:
      form*: RustBinOpForm
      lhs*, rhs*: RustOperand
    of rrvAddChecked:
      addLhs*, addRhs*: RustOperand
    of rrvExpr:
      expr*: RustExpr

  RustStmtKind* = enum
    rskStorageLive
    rskStorageDead
    rskAssign
    rskReturn
    rskPanic

  RustStmt* = object
    case kind*: RustStmtKind
    of rskStorageLive, rskStorageDead:
      place*: string
    of rskAssign:
      dest*: string
      rvalue*: RustRvalue
    of rskReturn, rskPanic:
      discard

  RustFailureMode* = enum
    ## TOOL-LAYER observation record — NOT program semantics. See the module
    ## docstring and ADR-0030 D2 (fsObserved cap; fingerprint→evidence only).
    rfmNoneObserved
    rfmPanicOnOverflowObserved

  RustParam* = object
    name*: string
    ty*: RustType

  RustCanonical* = object
    modulePath*: string        ## property 5: logical module path
    sourceIdentity*: string    ## property 5: source identity (provenance key)
    funcName*: string          ## property 1
    returnPlace*: string       ## designated return place (LLBC `_0` shape —
                               ## recorded, never assumed)
    failureMode*: RustFailureMode  ## property 4 (tool-layer fact)
    params*: seq[RustParam]    ## property 1
    retType*: RustType         ## property 1
    body*: seq[RustStmt]       ## straight-line: exactly one rskReturn, LAST

  RustCanonicalError* = enum
    rceNone
    rceUnsupportedGrammar  ## a type/statement/rvalue outside the closed set
    rceMalformed           ## structural violation (empty names, Return not
                           ## last, duplicate param/place names, …)

func isSupportedRustType*(t: RustType): bool {.inline.} =
  ## v1 closed type set: int{8,unsigned}, int{32,unsigned}, bool{1,unsigned},
  ## plus the v1.2 full-domain row int{64,unsigned} (usize on the pinned x86_64
  ## target): params/returns/constant values of width 64 are ADMITTED over the
  ## FULL domain [0, 2^64−1] — the IR literal two-part form carries values
  ## ≥ 2^63 in the u64-domain representation, and plain `+` is admitted where
  ## the no-overflow obligation is discharged (docs/spec/rust_certified_subset.md
  ## §1 v1.2). Everything else (i8, i32, signed anything) is OUTSIDE the
  ## measured grammar → unsupported (fail-closed, never silently widened).
  case t.kind
  of rtyInt:
    t.signedness == rsgUnsigned and
      (t.widthBits == 8 or t.widthBits == 32 or t.widthBits == 64)
  of rtyBool:
    t.signedness == rsgUnsigned and t.widthBits == 1

func rustU8Type*(): RustType {.inline.} =
  RustType(kind: rtyInt, widthBits: 8, signedness: rsgUnsigned)

func rustU32Type*(): RustType {.inline.} =
  RustType(kind: rtyInt, widthBits: 32, signedness: rsgUnsigned)

func rustU64Type*(): RustType {.inline.} =
  ## Full-domain row (§1 v1.2): params/returns/constants of width 64 are
  ## admitted over [0, 2^64−1]; plain `+` is admitted where the no-overflow
  ## obligation `lhs+rhs ≤ 18446744073709551615` is discharged (§1).
  RustType(kind: rtyInt, widthBits: 64, signedness: rsgUnsigned)

func rustBoolType*(): RustType {.inline.} =
  RustType(kind: rtyBool, widthBits: 1, signedness: rsgUnsigned)

const u64DomainLow*: uint64 = 0x8000000000000000'u64
  ## The u64-domain literal floor 2^63 — values below it belong to the signed
  ## domain (the two-part split is disjoint by construction).

const u64DomainHigh*: uint64 = 18446744073709551615'u64
  ## The u64 domain ceiling 2^64−1 — the honest full-range upper bound for
  ## width-64 range/overflow obligations (expressible via the two-part
  ## literal form; `irLit` alone cannot represent it).

func validateRustOperand(op: RustOperand): RustCanonicalError {.raises: [].} =
  case op.kind
  of ropCopy, ropMove:
    if op.place.len == 0: rceMalformed else: rceNone
  of ropConstant:
    if not isSupportedRustType(op.ty): rceUnsupportedGrammar
    elif op.value != 0 and op.valueU64 != 0: rceMalformed
    elif op.valueU64 != 0 and op.valueU64 < u64DomainLow: rceMalformed
    else: rceNone

func validateRustExpr(e: RustExpr): RustCanonicalError {.raises: [].} =
  ## Structural validation of the collapsed expression tree. Types are
  ## reconstructed by the IR derivation, so this layer checks shape only:
  ## non-nil nodes, valid operands, and the closed form set. A nil child is
  ## malformed (never a silent zero).
  if e == nil:
    return rceMalformed
  case e.kind
  of rexOperand:
    validateRustOperand(e.operand)
  of rexBinaryOp:
    let a = validateRustExpr(e.lhs)
    if a != rceNone: return a
    validateRustExpr(e.rhs)
  of rexIte:
    let c = validateRustExpr(e.cond)
    if c != rceNone: return c
    let t = validateRustExpr(e.thenExpr)
    if t != rceNone: return t
    validateRustExpr(e.elseExpr)

func validateRustRvalue(rv: RustRvalue): RustCanonicalError {.raises: [].} =
  case rv.kind
  of rrvUse:
    validateRustOperand(rv.operand)
  of rrvBinaryOp:
    let a = validateRustOperand(rv.lhs)
    if a != rceNone: return a
    validateRustOperand(rv.rhs)
  of rrvAddChecked:
    let a = validateRustOperand(rv.addLhs)
    if a != rceNone: return a
    validateRustOperand(rv.addRhs)
  of rrvExpr:
    validateRustExpr(rv.expr)

func validateRustCanonical*(c: RustCanonical): RustCanonicalError {.raises: [].} =
  ## Fail-closed structural validation of the closed v1 grammar. An invalid
  ## canonical must never reach the wire codec or either INV-4 leg.
  if c.funcName.len == 0 or c.modulePath.len == 0 or
      c.sourceIdentity.len == 0 or c.returnPlace.len == 0:
    return rceMalformed
  if not isSupportedRustType(c.retType):
    return rceUnsupportedGrammar
  for i in 0 ..< c.params.len:
    if c.params[i].name.len == 0:
      return rceMalformed
    if not isSupportedRustType(c.params[i].ty):
      return rceUnsupportedGrammar
    for j in 0 ..< i:
      if c.params[j].name == c.params[i].name:
        return rceMalformed
  for p in c.params:
    if c.returnPlace == p.name:
      return rceMalformed
  if c.body.len == 0:
    return rceMalformed
  if c.body[c.body.len - 1].kind != rskReturn:
    return rceMalformed  ## exactly one Return, LAST (straight-line v1)
  var assigned: seq[string] = @[]
  for i in 0 ..< c.body.len:
    let s = c.body[i]
    case s.kind
    of rskStorageLive, rskStorageDead:
      if s.place.len == 0: return rceMalformed
    of rskPanic, rskReturn:
      discard
    of rskAssign:
      if s.dest.len == 0: return rceMalformed
      let rvErr = validateRustRvalue(s.rvalue)
      if rvErr != rceNone: return rvErr
      if s.dest in assigned:
        return rceMalformed  ## single-assignment (SSA-fresh places, measured
                             ## probe shape); re-assignment is not v1 grammar
      assigned.add(s.dest)
  rceNone

func rustCanonicalErrorReason*(e: RustCanonicalError): string {.raises: [].} =
  case e
  of rceNone: "canonical is within the closed v1 grammar"
  of rceUnsupportedGrammar:
    "type/statement/rvalue outside the closed v1 grammar (fail-closed, never widened)"
  of rceMalformed:
    "structural violation: empty name, Return not last, duplicate param/place, " &
    "or re-assignment"

{.pop.}
