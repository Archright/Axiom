import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Rust Canonical Wire Codec — deterministic serialization of the Rust
## certified-subset shared canonical (feat/rust-subject-v1).
##
## PURPOSE
##   Serialize/deserialize the closed 11-kind Rust canonical
##   (src/core/trusted/rust_canonical.nim) into a stable, deterministic,
##   8-byte-aligned binary form that BOTH INV-4 legs share: the Nim leg
##   derives IR from the canonical object, the Lean reference extractor
##   (proofs/IR/RustReferenceExtractor.lean) decodes THIS wire with its OWN
##   decoder. Tag style follows src/verification/ast_wire.nim (1-byte tag +
##   7 padding bytes per slot; LE scalars; length-prefixed strings) — but
##   this is a DIFFERENT wire: it serializes the Rust canonical, and unlike
##   ast_wire it is round-trip complete (serializer AND deserializer).
##
## SUPPORTED GRAMMAR — exactly the measured 11 LLBC node kinds; the tag
## table IS the grammar (anything not listed is unrepresentable):
##   statements  StorageLive (0x11), StorageDead (0x12), Assign (0x13),
##               Return (0x14), Panic (0x15)
##   rvalues     Use (0x21), BinaryOp (0x22, form codes 1=Eq, 2=Lt, 3=And,
##               4=Or), AddChecked (0x23), Expr (0x24 — the Switch collapse's
##               recursive expression tree)
##   expr        Operand (0x25) | BinaryOp (0x26, form code + expr + expr) |
##               Ite (0x27, cond + then + else) — v3 only
##   operands    Copy (0x31), Move (0x32), Constant (0x33, value + domain
##               code + type; v2 adds the 8-byte domain code after the value:
##               0 = signed int64 payload, 1 = unsigned u64 payload (≥ 2^63
##               enforced — the u64 domain never travels as a negative
##               reinterpretation))
##   types       0x41 + kind(0=int,1=bool) + widthBits + signedness(0/1);
##               the v1 closed set accepts ONLY int/8/unsigned,
##               int/32/unsigned, bool/1/unsigned (isSupportedRustType)
##   failureMode uint64: 0 = noneObserved, 1 = panicOnOverflowObserved —
##               a TOOL-LAYER observation record (rustc/Charon, this build
##               profile), NOT a program-meaning claim (ADR-0030 D2:
##               fsObserved cap / fingerprint→evidence only)
##
## FAIL-CLOSED RULES (never skip, never default):
##   rweUnsupportedKind — unknown node tag or out-of-domain enum code
##                        (binary form, signedness code, failureMode code)
##   rweUnsupportedType — well-formed type triple outside the closed v1 set
##   rweMalformed       — bounds violations, empty names/places, counts that
##                        do not match the payload, trailing bytes after the
##                        root node, an empty body, a body whose last
##                        statement is not Return
##   The decoder additionally re-runs validateRustCanonical on the decoded
##   tree, so decode(encode(c)) cannot produce a canonical the trusted
##   module would reject.
##
## WIRE LAYOUT (8-byte aligned, ast_wire tag style):
##   magic 0xA1 (8-byte slot) · uint64 version (=3 — v1→v2 added the Constant
##   domain code; v2→v3 added the expression tree and the Lt/And/Or form
##   codes. Readers fail closed on any other version — the generations are
##   coherent, never mixed)
##   · str modulePath · str sourceIdentity · str funcName · str returnPlace
##   · uint64 failureMode · uint64 paramCount · (str name · type)*
##   · type retType · body
##   body := 0x10 · uint64 count · stmt*
##   type := 0x41 · uint64 kind · uint64 widthBits · uint64 signedness
##   constant := 0x33 · uint64 value-bits · uint64 domain (0=signed int64,
##               1=unsigned u64) · type

import core/trusted/rust_canonical

type
  RustWireError* = enum
    rweNone
    rweUnsupportedKind
    rweUnsupportedType
    rweMalformed

  RustWireOutcome* = object
    ## Per-node serialize outcome (first error aborts the whole wire).
    ok*: bool
    error*: RustWireError
    kind*: string

  RustWireResult* = object
    ok*: bool
    bytes*: seq[byte]
    error*: RustWireError
    kindName*: string

  RustWireDecodeResult* = object
    ok*: bool
    canonical*: RustCanonical
    error*: RustWireError
    kindName*: string

const
  rwMagic* = 0xA1'u8
  rwVersion* = 3'u64
  ## v3 (2026-11-12 bool-expression row): adds the rrvExpr tag + the
  ## recursive expression tree (rexOperand/rexBinaryOp/rexIte) and the
  ## Lt/And/Or form codes. v2 readers fail closed on the version; v3 readers
  ## fail closed on v2 (coherent-generation switch — no v2 artifact carries
  ## the new forms).
  # statement tags
  rwBody* = 0x10'u8
  rwStorageLive* = 0x11'u8
  rwStorageDead* = 0x12'u8
  rwAssign* = 0x13'u8
  rwReturn* = 0x14'u8
  rwPanic* = 0x15'u8
  # rvalue tags
  rwUse* = 0x21'u8
  rwBinaryOp* = 0x22'u8
  rwAddChecked* = 0x23'u8
  rwExpr* = 0x24'u8
  # expression-tree tags (payload of rwExpr)
  rwExprOperand* = 0x25'u8
  rwExprBinaryOp* = 0x26'u8
  rwExprIte* = 0x27'u8
  # operand tags
  rwCopy* = 0x31'u8
  rwMove* = 0x32'u8
  rwConstant* = 0x33'u8
  # type tag
  rwType* = 0x41'u8
  # enum payload codes (closed domains)
  rwcTypeInt* = 0'u64
  rwcTypeBool* = 1'u64
  rwcSignednessUnsigned* = 0'u64
  rwcSignednessSigned* = 1'u64
  rwcBinOpEq* = 1'u64
  rwcBinOpLt* = 2'u64
  rwcBinOpAnd* = 3'u64
  rwcBinOpOr* = 4'u64
  rwcFailureNoneObserved* = 0'u64
  rwcFailurePanicOnOverflowObserved* = 1'u64
  # Constant literal domain codes (v2): the payload's 8-byte reading
  rwcConstSignedI64* = 0'u64
  rwcConstUnsignedU64* = 1'u64

func okOutcome(): RustWireOutcome {.inline.} =
  RustWireOutcome(ok: true, error: rweNone, kind: "")

func failOutcome(error: RustWireError; kind: string): RustWireOutcome {.inline.} =
  RustWireOutcome(ok: false, error: error, kind: kind)

# ---------------------------------------------------------------------------
# Alignment + write helpers (ast_wire.nim discipline)
# ---------------------------------------------------------------------------

func align8*(n: int): int {.inline.} =
  (n + 7) and not 7

func writeTagAligned(buf: var seq[byte]; tag: byte) =
  buf.setLen(align8(buf.len))
  let base = buf.len
  buf.setLen(base + 8)
  buf[base] = tag

func writeU64Aligned(buf: var seq[byte]; v: uint64) =
  buf.setLen(align8(buf.len))
  let base = buf.len
  buf.setLen(base + 8)
  buf[base + 0] = byte(v shr 0)
  buf[base + 1] = byte(v shr 8)
  buf[base + 2] = byte(v shr 16)
  buf[base + 3] = byte(v shr 24)
  buf[base + 4] = byte(v shr 32)
  buf[base + 5] = byte(v shr 40)
  buf[base + 6] = byte(v shr 48)
  buf[base + 7] = byte(v shr 56)

func writeI64Aligned(buf: var seq[byte]; v: int64) =
  writeU64Aligned(buf, cast[uint64](v))

func writeStrAligned(buf: var seq[byte]; s: string) =
  writeU64Aligned(buf, uint64(s.len))
  let dataStart = buf.len
  buf.setLen(dataStart + s.len)
  for i in 0 ..< s.len:
    buf[dataStart + i] = byte(s[i])
  let pad = align8(s.len) - s.len
  if pad > 0:
    buf.setLen(buf.len + pad)

# ---------------------------------------------------------------------------
# Fail-closed read helpers (deserializer side)
# ---------------------------------------------------------------------------

type WireReader* = object
  data*: seq[byte]
  pos*: int

func remaining(r: WireReader): int {.inline.} =
  r.data.len - r.pos

func tryReadU64(r: var WireReader; outVal: out uint64): bool =
  let base = align8(r.pos)
  if base + 8 > r.data.len:
    return false
  r.pos = base + 8
  outVal = uint64(r.data[base + 0]) or
           (uint64(r.data[base + 1]) shl 8) or
           (uint64(r.data[base + 2]) shl 16) or
           (uint64(r.data[base + 3]) shl 24) or
           (uint64(r.data[base + 4]) shl 32) or
           (uint64(r.data[base + 5]) shl 40) or
           (uint64(r.data[base + 6]) shl 48) or
           (uint64(r.data[base + 7]) shl 56)
  true

func tryReadI64(r: var WireReader; outVal: out int64): bool =
  var u: uint64
  if not r.tryReadU64(u):
    return false
  outVal = cast[int64](u)
  true

func tryReadStr(r: var WireReader; outVal: out string): bool =
  var lenU: uint64
  if not r.tryReadU64(lenU):
    return false
  let len = int(lenU)
  let dataStart = r.pos
  if len < 0 or dataStart + len > r.data.len:
    return false
  outVal = newString(len)
  for i in 0 ..< len:
    outVal[i] = char(r.data[dataStart + i])
  r.pos = align8(dataStart + len)
  true

# ---------------------------------------------------------------------------
# Serializer (fail-closed: any unsupported/malformed node aborts the wire)
# ---------------------------------------------------------------------------

func serializeTypeWire(buf: var seq[byte]; t: RustType): RustWireOutcome =
  if not isSupportedRustType(t):
    return failOutcome(rweUnsupportedType, $t.kind & "/" & $t.widthBits)
  writeTagAligned(buf, rwType)
  let kindCode = case t.kind
                 of rtyInt: rwcTypeInt
                 of rtyBool: rwcTypeBool
  writeU64Aligned(buf, kindCode)
  writeU64Aligned(buf, uint64(t.widthBits))
  let sgCode = case t.signedness
               of rsgUnsigned: rwcSignednessUnsigned
               of rsgSigned: rwcSignednessSigned
  writeU64Aligned(buf, sgCode)
  okOutcome()

func serializeOperandWire(buf: var seq[byte]; op: RustOperand): RustWireOutcome =
  case op.kind
  of ropCopy:
    if op.place.len == 0:
      return failOutcome(rweMalformed, $op.kind)
    writeTagAligned(buf, rwCopy)
    writeStrAligned(buf, op.place)
    okOutcome()
  of ropMove:
    if op.place.len == 0:
      return failOutcome(rweMalformed, $op.kind)
    writeTagAligned(buf, rwMove)
    writeStrAligned(buf, op.place)
    okOutcome()
  of ropConstant:
    writeTagAligned(buf, rwConstant)
    if op.valueU64 != 0'u64:
      writeU64Aligned(buf, op.valueU64)
      writeU64Aligned(buf, rwcConstUnsignedU64)
    else:
      writeI64Aligned(buf, op.value)
      writeU64Aligned(buf, rwcConstSignedI64)
    serializeTypeWire(buf, op.ty)

func binOpFormCode(form: RustBinOpForm): uint64 =
  case form
  of rboEq: rwcBinOpEq
  of rboLt: rwcBinOpLt
  of rboAnd: rwcBinOpAnd
  of rboOr: rwcBinOpOr

func serializeExprWire(buf: var seq[byte]; e: RustExpr): RustWireOutcome =
  ## Recursive expression tree (payload of rwExpr). A nil node is malformed —
  ## the wire never encodes a silent zero.
  if e == nil:
    return failOutcome(rweMalformed, "expr-nil")
  case e.kind
  of rexOperand:
    writeTagAligned(buf, rwExprOperand)
    serializeOperandWire(buf, e.operand)
  of rexBinaryOp:
    writeTagAligned(buf, rwExprBinaryOp)
    writeU64Aligned(buf, binOpFormCode(e.form))
    let a = serializeExprWire(buf, e.lhs)
    if not a.ok: return a
    serializeExprWire(buf, e.rhs)
  of rexIte:
    writeTagAligned(buf, rwExprIte)
    let c = serializeExprWire(buf, e.cond)
    if not c.ok: return c
    let t = serializeExprWire(buf, e.thenExpr)
    if not t.ok: return t
    serializeExprWire(buf, e.elseExpr)

func serializeRvalueWire(buf: var seq[byte]; rv: RustRvalue): RustWireOutcome =
  case rv.kind
  of rrvUse:
    writeTagAligned(buf, rwUse)
    serializeOperandWire(buf, rv.operand)
  of rrvBinaryOp:
    writeTagAligned(buf, rwBinaryOp)
    writeU64Aligned(buf, binOpFormCode(rv.form))
    let a = serializeOperandWire(buf, rv.lhs)
    if not a.ok: return a
    serializeOperandWire(buf, rv.rhs)
  of rrvAddChecked:
    writeTagAligned(buf, rwAddChecked)
    let a = serializeOperandWire(buf, rv.addLhs)
    if not a.ok: return a
    serializeOperandWire(buf, rv.addRhs)
  of rrvExpr:
    writeTagAligned(buf, rwExpr)
    serializeExprWire(buf, rv.expr)

func serializeStmtWire(buf: var seq[byte]; s: RustStmt): RustWireOutcome =
  case s.kind
  of rskStorageLive:
    if s.place.len == 0:
      return failOutcome(rweMalformed, $s.kind)
    writeTagAligned(buf, rwStorageLive)
    writeStrAligned(buf, s.place)
    okOutcome()
  of rskStorageDead:
    if s.place.len == 0:
      return failOutcome(rweMalformed, $s.kind)
    writeTagAligned(buf, rwStorageDead)
    writeStrAligned(buf, s.place)
    okOutcome()
  of rskAssign:
    if s.dest.len == 0:
      return failOutcome(rweMalformed, $s.kind)
    writeTagAligned(buf, rwAssign)
    writeStrAligned(buf, s.dest)
    serializeRvalueWire(buf, s.rvalue)
  of rskReturn:
    writeTagAligned(buf, rwReturn)
    okOutcome()
  of rskPanic:
    writeTagAligned(buf, rwPanic)
    okOutcome()

func serializeCanonicalWire*(c: RustCanonical): RustWireResult =
  ## Entry point: serialize the shared canonical to the wire form. The
  ## canonical must pass validateRustCanonical first — an invalid canonical
  ## aborts here (fail-closed), never reaches a leg.
  result = RustWireResult(ok: false, bytes: @[], error: rweNone, kindName: "")
  let v = validateRustCanonical(c)
  if v != rceNone:
    result.error = case v
                   of rceUnsupportedGrammar: rweUnsupportedType
                   of rceMalformed: rweMalformed
                   of rceNone: rweNone
    result.kindName = rustCanonicalErrorReason(v)
    return
  var buf: seq[byte] = @[]
  writeTagAligned(buf, rwMagic)
  writeU64Aligned(buf, rwVersion)
  writeStrAligned(buf, c.modulePath)
  writeStrAligned(buf, c.sourceIdentity)
  writeStrAligned(buf, c.funcName)
  writeStrAligned(buf, c.returnPlace)
  let fmCode = case c.failureMode
               of rfmNoneObserved: rwcFailureNoneObserved
               of rfmPanicOnOverflowObserved: rwcFailurePanicOnOverflowObserved
  writeU64Aligned(buf, fmCode)
  writeU64Aligned(buf, uint64(c.params.len))
  for p in c.params:
    writeStrAligned(buf, p.name)
    let pt = serializeTypeWire(buf, p.ty)
    if not pt.ok:
      result.error = pt.error
      result.kindName = pt.kind
      return
  let rt = serializeTypeWire(buf, c.retType)
  if not rt.ok:
    result.error = rt.error
    result.kindName = rt.kind
    return
  writeTagAligned(buf, rwBody)
  writeU64Aligned(buf, uint64(c.body.len))
  for s in c.body:
    let so = serializeStmtWire(buf, s)
    if not so.ok:
      result.error = so.error
      result.kindName = so.kind
      return
  result.ok = true
  result.bytes = buf

# ---------------------------------------------------------------------------
# Deserializer (fail-closed; mutual independence with the Lean decoder)
# ---------------------------------------------------------------------------

func deserializeTypeWire*(r: var WireReader; outTy: out RustType;
                          err: out RustWireError; outKind: var string): bool =
  err = rweMalformed
  outKind = ""
  var tag: uint64
  if not r.tryReadU64(tag) or tag != uint64(rwType):
    outKind = "type-tag"
    return false
  var kindCode, width, sgCode: uint64
  if not r.tryReadU64(kindCode) or not r.tryReadU64(width) or
      not r.tryReadU64(sgCode):
    outKind = "type-fields"
    return false
  var k: RustTypeKind
  case kindCode
  of rwcTypeInt: k = rtyInt
  of rwcTypeBool: k = rtyBool
  else:
    err = rweUnsupportedKind
    outKind = "type-kind/" & $kindCode
    return false
  var sg: RustSignedness
  case sgCode
  of rwcSignednessUnsigned: sg = rsgUnsigned
  of rwcSignednessSigned: sg = rsgSigned
  else:
    err = rweUnsupportedKind
    outKind = "signedness/" & $sgCode
    return false
  if width == 0 or width > uint64(int.high):
    outKind = "width/" & $width
    return false
  outTy = RustType(kind: k, widthBits: int(width), signedness: sg)
  if not isSupportedRustType(outTy):
    err = rweUnsupportedType
    outKind = $k & "/" & $outTy.widthBits
    return false
  true

func deserializeOperandWire*(r: var WireReader; outOp: out RustOperand;
                             err: out RustWireError; outKind: var string): bool =
  err = rweMalformed
  outKind = ""
  outOp = RustOperand(kind: ropCopy)  ## ProveInit: defined default before dispatch
  var tag: uint64
  if not r.tryReadU64(tag):
    outKind = "operand-bounds"
    return false
  case tag
  of uint64(rwCopy):
    var place: string
    if not r.tryReadStr(place) or place.len == 0:
      outKind = "copy-place"
      return false
    outOp = RustOperand(kind: ropCopy, place: place)
    true
  of uint64(rwMove):
    var place: string
    if not r.tryReadStr(place) or place.len == 0:
      outKind = "move-place"
      return false
    outOp = RustOperand(kind: ropMove, place: place)
    true
  of uint64(rwConstant):
    var raw: uint64
    if not r.tryReadU64(raw):
      outKind = "constant-value"
      return false
    var domainCode: uint64
    if not r.tryReadU64(domainCode):
      outKind = "constant-domain-bounds"
      return false
    var ty: RustType
    if not deserializeTypeWire(r, ty, err, outKind):
      return false
    case domainCode
    of rwcConstSignedI64:
      outOp = RustOperand(kind: ropConstant, value: cast[int64](raw), ty: ty)
      true
    of rwcConstUnsignedU64:
      if raw < u64DomainLow:
        err = rweUnsupportedKind
        outKind = "constant-u64-domain/" & $raw
        return false
      outOp = RustOperand(kind: ropConstant, valueU64: raw, ty: ty)
      true
    else:
      err = rweUnsupportedKind
      outKind = "constant-domain/" & $domainCode
      false
  else:
    err = rweUnsupportedKind
    outKind = "operand-tag/" & $tag
    false

func decodeBinOpForm(code: uint64; form: out RustBinOpForm): bool =
  form = rboEq  ## ProveInit: defined default before dispatch
  case code
  of rwcBinOpEq: form = rboEq; true
  of rwcBinOpLt: form = rboLt; true
  of rwcBinOpAnd: form = rboAnd; true
  of rwcBinOpOr: form = rboOr; true
  else: false

func deserializeExprWire(r: var WireReader; outE: out RustExpr;
                         err: out RustWireError; outKind: var string): bool =
  err = rweMalformed
  outKind = ""
  outE = nil
  var tag: uint64
  if not r.tryReadU64(tag):
    outKind = "expr-bounds"
    return false
  case tag
  of uint64(rwExprOperand):
    var op: RustOperand
    if not deserializeOperandWire(r, op, err, outKind):
      return false
    outE = RustExpr(kind: rexOperand, operand: op)
    true
  of uint64(rwExprBinaryOp):
    var formCode: uint64
    if not r.tryReadU64(formCode):
      outKind = "expr-binaryop-form-bounds"
      return false
    var form: RustBinOpForm
    if not decodeBinOpForm(formCode, form):
      err = rweUnsupportedKind
      outKind = "expr-binaryop-form/" & $formCode
      return false
    var lhs: RustExpr
    if not deserializeExprWire(r, lhs, err, outKind):
      return false
    var rhs: RustExpr
    if not deserializeExprWire(r, rhs, err, outKind):
      return false
    outE = RustExpr(kind: rexBinaryOp, form: form, lhs: lhs, rhs: rhs)
    true
  of uint64(rwExprIte):
    var cond: RustExpr
    if not deserializeExprWire(r, cond, err, outKind):
      return false
    var thenExpr: RustExpr
    if not deserializeExprWire(r, thenExpr, err, outKind):
      return false
    var elseExpr: RustExpr
    if not deserializeExprWire(r, elseExpr, err, outKind):
      return false
    outE = RustExpr(kind: rexIte, cond: cond, thenExpr: thenExpr,
                    elseExpr: elseExpr)
    true
  else:
    err = rweUnsupportedKind
    outKind = "expr-tag/" & $tag
    false

func deserializeRvalueWire*(r: var WireReader; outRv: out RustRvalue;
                            err: out RustWireError; outKind: var string): bool =
  err = rweMalformed
  outKind = ""
  outRv = RustRvalue(kind: rrvUse)  ## ProveInit: defined default before dispatch
  var tag: uint64
  if not r.tryReadU64(tag):
    outKind = "rvalue-bounds"
    return false
  case tag
  of uint64(rwUse):
    var op: RustOperand
    if not deserializeOperandWire(r, op, err, outKind):
      return false
    outRv = RustRvalue(kind: rrvUse, operand: op)
    true
  of uint64(rwBinaryOp):
    var formCode: uint64
    if not r.tryReadU64(formCode):
      outKind = "binaryop-form-bounds"
      return false
    var form: RustBinOpForm
    if not decodeBinOpForm(formCode, form):
      err = rweUnsupportedKind
      outKind = "binaryop-form/" & $formCode
      return false
    var lhs: RustOperand
    if not deserializeOperandWire(r, lhs, err, outKind):
      return false
    var rhs: RustOperand
    if not deserializeOperandWire(r, rhs, err, outKind):
      return false
    outRv = RustRvalue(kind: rrvBinaryOp, form: form, lhs: lhs, rhs: rhs)
    true
  of uint64(rwAddChecked):
    var lhs: RustOperand
    if not deserializeOperandWire(r, lhs, err, outKind):
      return false
    var rhs: RustOperand
    if not deserializeOperandWire(r, rhs, err, outKind):
      return false
    outRv = RustRvalue(kind: rrvAddChecked, addLhs: lhs, addRhs: rhs)
    true
  of uint64(rwExpr):
    var e: RustExpr
    if not deserializeExprWire(r, e, err, outKind):
      return false
    outRv = RustRvalue(kind: rrvExpr, expr: e)
    true
  else:
    err = rweUnsupportedKind
    outKind = "rvalue-tag/" & $tag
    false

func deserializeStmtWire*(r: var WireReader; outStmt: out RustStmt;
                          err: out RustWireError; outKind: var string): bool =
  err = rweMalformed
  outKind = ""
  outStmt = RustStmt(kind: rskReturn)  ## ProveInit: defined default before dispatch
  var tag: uint64
  if not r.tryReadU64(tag):
    outKind = "stmt-bounds"
    return false
  case tag
  of uint64(rwStorageLive):
    var place: string
    if not r.tryReadStr(place) or place.len == 0:
      outKind = "storagelive-place"
      return false
    outStmt = RustStmt(kind: rskStorageLive, place: place)
    true
  of uint64(rwStorageDead):
    var place: string
    if not r.tryReadStr(place) or place.len == 0:
      outKind = "storagedead-place"
      return false
    outStmt = RustStmt(kind: rskStorageDead, place: place)
    true
  of uint64(rwAssign):
    var dest: string
    if not r.tryReadStr(dest) or dest.len == 0:
      outKind = "assign-dest"
      return false
    var rv: RustRvalue
    if not deserializeRvalueWire(r, rv, err, outKind):
      return false
    outStmt = RustStmt(kind: rskAssign, dest: dest, rvalue: rv)
    true
  of uint64(rwReturn):
    outStmt = RustStmt(kind: rskReturn)
    true
  of uint64(rwPanic):
    outStmt = RustStmt(kind: rskPanic)
    true
  else:
    err = rweUnsupportedKind
    outKind = "stmt-tag/" & $tag
    false

func deserializeCanonicalWire*(bytes: openArray[byte]): RustWireDecodeResult =
  ## Fail-closed decode of the wire document. Unknown tag / out-of-domain
  ## code → rweUnsupportedKind; closed-set violation → rweUnsupportedType;
  ## bounds/shape violations → rweMalformed. The decoded tree is
  ## re-validated with validateRustCanonical so the decoder can never emit a
  ## canonical the trusted module rejects. Trailing bytes after the root are
  ## rejected (the wire is exactly one document).
  result = RustWireDecodeResult(ok: false, canonical: RustCanonical(),
                                error: rweNone, kindName: "")
  var r = WireReader(data: @bytes, pos: 0)
  var tag: uint64
  if not r.tryReadU64(tag) or tag != uint64(rwMagic):
    result.error = rweMalformed
    result.kindName = "magic"
    return
  var version: uint64
  if not r.tryReadU64(version) or version != rwVersion:
    result.error = rweMalformed
    result.kindName = "version"
    return
  var c: RustCanonical
  if not r.tryReadStr(c.modulePath) or c.modulePath.len == 0:
    result.error = rweMalformed
    result.kindName = "modulePath"
    return
  if not r.tryReadStr(c.sourceIdentity) or c.sourceIdentity.len == 0:
    result.error = rweMalformed
    result.kindName = "sourceIdentity"
    return
  if not r.tryReadStr(c.funcName) or c.funcName.len == 0:
    result.error = rweMalformed
    result.kindName = "funcName"
    return
  if not r.tryReadStr(c.returnPlace) or c.returnPlace.len == 0:
    result.error = rweMalformed
    result.kindName = "returnPlace"
    return
  var fmCode: uint64
  if not r.tryReadU64(fmCode):
    result.error = rweMalformed
    result.kindName = "failureMode-bounds"
    return
  case fmCode
  of rwcFailureNoneObserved: c.failureMode = rfmNoneObserved
  of rwcFailurePanicOnOverflowObserved: c.failureMode = rfmPanicOnOverflowObserved
  else:
    result.error = rweUnsupportedKind
    result.kindName = "failureMode/" & $fmCode
    return
  var paramCount: uint64
  if not r.tryReadU64(paramCount):
    result.error = rweMalformed
    result.kindName = "paramCount-bounds"
    return
  if paramCount > uint64(r.remaining div 8):
    result.error = rweMalformed
    result.kindName = "paramCount-overshoot"
    return
  for i in 0 ..< int(paramCount):
    var name: string
    if not r.tryReadStr(name) or name.len == 0:
      result.error = rweMalformed
      result.kindName = "param-name"
      return
    var ty: RustType
    var terr: RustWireError
    if not deserializeTypeWire(r, ty, terr, result.kindName):
      result.error = terr
      return
    c.params.add(RustParam(name: name, ty: ty))
  var retTy: RustType
  var retErr: RustWireError
  if not deserializeTypeWire(r, retTy, retErr, result.kindName):
    result.error = retErr
    return
  c.retType = retTy
  var bodyTag: uint64
  if not r.tryReadU64(bodyTag) or bodyTag != uint64(rwBody):
    result.error = rweMalformed
    result.kindName = "body-tag"
    return
  var stmtCount: uint64
  if not r.tryReadU64(stmtCount):
    result.error = rweMalformed
    result.kindName = "body-count-bounds"
    return
  if stmtCount == 0 or stmtCount > uint64(r.remaining div 8):
    result.error = rweMalformed
    result.kindName = "body-count"
    return
  for i in 0 ..< int(stmtCount):
    var s: RustStmt
    var serr: RustWireError
    if not deserializeStmtWire(r, s, serr, result.kindName):
      result.error = serr
      return
    c.body.add(s)
  if r.remaining != 0:
    result.error = rweMalformed
    result.kindName = "trailing-bytes"
    return
  let v = validateRustCanonical(c)
  if v != rceNone:
    result.error = case v
                   of rceUnsupportedGrammar: rweUnsupportedType
                   of rceMalformed: rweMalformed
                   of rceNone: rweNone
    result.kindName = rustCanonicalErrorReason(v)
    return
  result.ok = true
  result.canonical = c

{.pop.}
