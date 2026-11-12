import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Axiom IR Binary Codec — 8-byte aligned serialization for mmap-based IPC.
##
## Every field starts at an 8-byte boundary. Tag bytes occupy a full 8-byte
## slot (1 byte tag + 7 bytes padding). Strings are length-prefixed with
## padding. Sequences are count-prefixed with each element aligned.
##
## Tag-byte encoding:
##   0x00 = nil sentinel
##   0x01 = irLit (SIGNED int64 payload — the canonical signed reading
##          [−2^63, 2^63−1]; INVALID for any value with the high bit set:
##          a value ≥ 2^63 travels only under 0x0F, never reinterpreted
##          into the signed payload), 0x02 = irFloatLit, 0x03 = irVar
##   0x04 = irLet (isCompileTime=false), 0x0E = irLet (isCompileTime=true, CLET)
##   0x05 = irIf,  0x06 = irCase,     0x07 = irCall, 0x08 = irBinOp
##   0x09 = irUnaryOp, 0x0A = irRecCall, 0x0B = irLoop, 0x0C = irStringLit
##   0x0D = irCast, 0x0F = irLitU64 (8-byte LE direct uint64; payload < 2^63
##          is a domain violation and decodes as an error)
##
## IRType tags:
##   0x00 = nil, 0x01 = irtBitVec64, 0x02 = irtBool, 0x03 = irtList, 0x04 = irtString
##   0x05 = irtEnum, 0x06 = irtVariant
##
## All multi-byte scalars use little-endian encoding.
##
## Decode errors are the sticky `-1` offset sentinel: every read helper sets
## `offset = -1` on truncation and every consumer checks before continuing,
## so truncated/corrupt data can never decode into a silently-wrong tree —
## `deserializeIRExprAligned` returns nil for ANY decode error (indistinguishable
## from the valid nil-sentinel document only at the top-level API; the
## internal error state is explicit).

import core/trusted/axiom_ir

# ---------------------------------------------------------------------------
# Alignment helpers
# ---------------------------------------------------------------------------

func align8*(n: int): int =
  ## Round up `n` to the next 8-byte boundary.
  (n + 7) and not 7

# ---------------------------------------------------------------------------
# Write helpers — append to seq[byte], maintaining 8-byte alignment
# ---------------------------------------------------------------------------

func writeUint64Aligned(buf: var seq[byte], val: uint64) =
  ## Append a uint64 (8 bytes) at the current position, aligned.
  buf.setLen(align8(buf.len))
  let base = buf.len
  buf.setLen(base + 8)
  buf[base + 0] = byte(val shr 0)
  buf[base + 1] = byte(val shr 8)
  buf[base + 2] = byte(val shr 16)
  buf[base + 3] = byte(val shr 24)
  buf[base + 4] = byte(val shr 32)
  buf[base + 5] = byte(val shr 40)
  buf[base + 6] = byte(val shr 48)
  buf[base + 7] = byte(val shr 56)

func writeInt64Aligned(buf: var seq[byte], val: int64) =
  ## Append an int64 (8 bytes) at the current position, aligned.
  writeUint64Aligned(buf, cast[uint64](val))

func writeFloat64Aligned(buf: var seq[byte], val: float64) =
  ## Append a float64 (8 bytes) at the current position, aligned.
  writeUint64Aligned(buf, cast[uint64](val))

func writeStringAligned(buf: var seq[byte], s: string) =
  ## Append length (uint64) + raw data + zero-padding to 8-byte boundary.
  writeUint64Aligned(buf, uint64(s.len))
  let dataStart = buf.len
  buf.setLen(dataStart + s.len)
  for i in 0 ..< s.len:
    buf[dataStart + i] = byte(s[i])
  # Pad to 8-byte boundary (setLen zero-fills new bytes)
  let padded = align8(s.len)
  let padCount = padded - s.len
  if padCount > 0:
    buf.setLen(buf.len + padCount)

func writeTag(buf: var seq[byte], tag: byte) =
  ## Append 1-byte tag + 7 bytes zero-padding (total 8 bytes, aligned).
  buf.setLen(align8(buf.len))
  let base = buf.len
  buf.setLen(base + 8)
  buf[base] = tag
  # bytes 1–7 are zero from setLen

# ---------------------------------------------------------------------------
# Read helpers — read from openArray[byte], advancing offset
# ---------------------------------------------------------------------------

func readUint64Aligned(data: openArray[byte], offset: var int): uint64 =
  ## Read a uint64 at `offset` (aligns before read). Bounds violation → the
  ## sticky -1 error sentinel in `offset` (never a silent 0).
  if offset < 0: return 0
  let base = align8(offset)
  if base + 8 > data.len:
    offset = -1
    return 0
  offset = base + 8
  result = uint64(data[base + 0]) or
           (uint64(data[base + 1]) shl 8) or
           (uint64(data[base + 2]) shl 16) or
           (uint64(data[base + 3]) shl 24) or
           (uint64(data[base + 4]) shl 32) or
           (uint64(data[base + 5]) shl 40) or
           (uint64(data[base + 6]) shl 48) or
           (uint64(data[base + 7]) shl 56)

func readInt64Aligned(data: openArray[byte], offset: var int): int64 =
  ## Read an int64 at `offset`.
  cast[int64](readUint64Aligned(data, offset))

func readFloat64Aligned(data: openArray[byte], offset: var int): float64 =
  ## Read a float64 at `offset`.
  cast[float64](readUint64Aligned(data, offset))

func readStringAligned(data: openArray[byte], offset: var int): string =
  ## Read a length-prefixed, 8-byte-padded string. Bounds violation → the
  ## sticky -1 error sentinel in `offset` (never a silent "").
  if offset < 0: return ""
  let len = int(readUint64Aligned(data, offset))
  if offset < 0: return ""
  # offset is now aligned and points to start of string data
  if offset + len > data.len:
    offset = -1
    return ""
  result = newString(len)
  for i in 0 ..< len:
    result[i] = char(data[offset + i])
  offset += len
  offset = align8(offset) # skip padding bytes

func readTag(data: openArray[byte], offset: var int): byte =
  ## Read a tag byte (1 byte + 7 padding bytes). Bounds violation → the
  ## sticky -1 error sentinel in `offset` (never a silent 0x00).
  if offset < 0: return 0
  let base = align8(offset)
  if base + 8 > data.len:
    offset = -1
    return 0
  result = data[base]
  offset = base + 8

# ---------------------------------------------------------------------------
# IRType serialization / deserialization
# ---------------------------------------------------------------------------

func serializeIRTypeAligned(buf: var seq[byte], t: IRType) =
  ## Serialize an IRType with 8-byte alignment.
  if t == nil:
    writeTag(buf, 0x00)
    return
  case t.kind
  of irtBitVec64: writeTag(buf, 0x01)
  of irtBool:     writeTag(buf, 0x02)
  of irtList:
    writeTag(buf, 0x03)
    serializeIRTypeAligned(buf, t.elemType)
  of irtString:   writeTag(buf, 0x04)
  of irtEnum:     writeTag(buf, 0x05)
  of irtVariant:
    writeTag(buf, 0x06)
    writeStringAligned(buf, t.variantName)
    writeUint64Aligned(buf, uint64(t.variantTags.len))
    for tag in t.variantTags:
      writeStringAligned(buf, tag)
    for o in t.variantOrdinals:
      writeInt64Aligned(buf, o)
    for pt in t.variantPayloadTypes:
      serializeIRTypeAligned(buf, pt)

func deserializeIRTypeAligned(data: openArray[byte], offset: var int): IRType =
  ## Deserialize an IRType from 8-byte aligned binary data.
  if offset < 0: return nil
  let tag = readTag(data, offset)
  if offset < 0: return nil
  case tag
  of 0x00: nil
  of 0x01: IRType(kind: irtBitVec64)
  of 0x02: IRType(kind: irtBool)
  of 0x03:
    let elem = deserializeIRTypeAligned(data, offset)
    IRType(kind: irtList, elemType: elem)
  of 0x04: IRType(kind: irtString)
  of 0x05: IRType(kind: irtEnum)  # Minimal deserialization; full enum metadata not restored
  of 0x06: # irtVariant
    let variantName = readStringAligned(data, offset)
    let tagCount = int(readUint64Aligned(data, offset))
    var tags = newSeq[string](tagCount)
    for i in 0 ..< tagCount:
      tags[i] = readStringAligned(data, offset)
    var ordinals = newSeq[int64](tagCount)
    for i in 0 ..< tagCount:
      ordinals[i] = readInt64Aligned(data, offset)
    var payloadTypes = newSeq[IRType](tagCount)
    for i in 0 ..< tagCount:
      payloadTypes[i] = deserializeIRTypeAligned(data, offset)
    IRType(kind: irtVariant, variantName: variantName, variantTags: tags,
           variantOrdinals: ordinals, variantPayloadTypes: payloadTypes)
  else:
    offset = -1  # unknown IRType tag — a decode error, never a silent nil
    nil

# ---------------------------------------------------------------------------
# Enum serialization helpers
# ---------------------------------------------------------------------------

func serializeBinOpAligned(buf: var seq[byte], op: BinOpKind) =
  ## Serialize BinOpKind as a uint64 ordinal (8 bytes).
  writeUint64Aligned(buf, uint64(op.ord))

func serializeUnaryOpAligned(buf: var seq[byte], op: UnaryOpKind) =
  ## Serialize UnaryOpKind as a uint64 ordinal (8 bytes).
  writeUint64Aligned(buf, uint64(op.ord))

func serializeLoopKindAligned(buf: var seq[byte], lk: LoopKind) =
  ## Serialize LoopKind as a uint64 ordinal (8 bytes).
  writeUint64Aligned(buf, uint64(lk.ord))

# ---------------------------------------------------------------------------
# IRExpr serialization (forward declaration for mutual recursion)
# ---------------------------------------------------------------------------

func serializeIRExprAligned*(ir: IRExpr): seq[byte]
  ## Forward declaration — main entry point for binary serialization.

# --- helpers that call serializeIRExprAligned ---

func serializeCaseBranchAligned(buf: var seq[byte], br: CaseBranch) =
  ## Serialize a CaseBranch: pattern (int64) + body (IRExpr).
  writeInt64Aligned(buf, br.pattern)
  let bodyBytes = serializeIRExprAligned(br.body)
  buf.add(bodyBytes)

func serializeIRExprSeq(buf: var seq[byte], exprs: seq[IRExpr]) =
  ## Serialize a sequence of IRExpr: count (uint64) + aligned elements.
  writeUint64Aligned(buf, uint64(exprs.len))
  for e in exprs:
    let eBytes = serializeIRExprAligned(e)
    buf.add(eBytes)

func serializeStringSeq(buf: var seq[byte], strs: seq[string]) =
  ## Serialize a sequence of strings: count (uint64) + aligned elements.
  writeUint64Aligned(buf, uint64(strs.len))
  for s in strs:
    writeStringAligned(buf, s)

# --- main implementation (mutual recursion resolved) ---

func serializeIRExprAligned*(ir: IRExpr): seq[byte] =
  ## Main serialization: produces a seq[byte] with all fields 8-byte aligned.
  ## nil IRExpr is encoded as a single 8-byte nil tag (0x00).
  result = @[]
  if ir == nil:
    writeTag(result, 0x00)
    return

  case ir.kind
  of irLit:
    if ir.litU64 != 0'u64:
      # 0x0F = irLitU64 — the u64 domain [2^63, 2^64−1] travels ONLY under
      # this tag; the legacy 0x01 tag is invalid for any value whose high
      # bit would be set (never a negative-litVal reinterpretation)
      writeTag(result, 0x0F)
      writeUint64Aligned(result, ir.litU64)
    else:
      writeTag(result, 0x01)
      writeInt64Aligned(result, ir.litVal)

  of irFloatLit:
    writeTag(result, 0x02)
    writeFloat64Aligned(result, ir.floatVal)

  of irVar:
    writeTag(result, 0x03)
    writeStringAligned(result, ir.varName)
    serializeIRTypeAligned(result, ir.varType)

  of irLet:
    if ir.isCompileTime:
      writeTag(result, 0x0E)
    else:
      writeTag(result, 0x04)
    writeStringAligned(result, ir.letName)
    let valBytes = serializeIRExprAligned(ir.letVal)
    result.add(valBytes)
    let bodyBytes = serializeIRExprAligned(ir.letBody)
    result.add(bodyBytes)

  of irIf:
    writeTag(result, 0x05)
    result.add(serializeIRExprAligned(ir.ifCond))
    result.add(serializeIRExprAligned(ir.ifThen))
    result.add(serializeIRExprAligned(ir.ifElse))

  of irCase:
    writeTag(result, 0x06)
    result.add(serializeIRExprAligned(ir.caseScrutinee))
    # Branches: count + each (pattern:int64 + body:IRExpr)
    writeUint64Aligned(result, uint64(ir.caseBranches.len))
    for br in ir.caseBranches:
      serializeCaseBranchAligned(result, br)
    # Default branch (nil → 0x00 tag)
    result.add(serializeIRExprAligned(ir.caseDefault))

  of irCall:
    writeTag(result, 0x07)
    writeStringAligned(result, ir.callName)
    serializeIRExprSeq(result, ir.callArgs)

  of irBinOp:
    writeTag(result, 0x08)
    serializeBinOpAligned(result, ir.binOp)
    result.add(serializeIRExprAligned(ir.binLhs))
    result.add(serializeIRExprAligned(ir.binRhs))

  of irUnaryOp:
    writeTag(result, 0x09)
    serializeUnaryOpAligned(result, ir.unaryOp)
    result.add(serializeIRExprAligned(ir.unaryArg))

  of irRecCall:
    writeTag(result, 0x0A)
    serializeIRExprSeq(result, ir.recArgs)

  of irLoop:
    writeTag(result, 0x0B)
    serializeLoopKindAligned(result, ir.loopKind)
    serializeStringSeq(result, ir.loopVars)
    serializeIRExprSeq(result, ir.loopInits)
    result.add(serializeIRExprAligned(ir.loopCond))
    result.add(serializeIRExprAligned(ir.loopStep))
    result.add(serializeIRExprAligned(ir.loopBody))
    serializeIRExprSeq(result, ir.loopInvariants)
    result.add(serializeIRExprAligned(ir.loopVariant))

  of irStringLit:
    writeTag(result, 0x0C)
    writeStringAligned(result, ir.stringVal)

  of irCast:
    writeTag(result, 0x0D)
    result.add(serializeIRExprAligned(ir.castExpr))
    serializeIRTypeAligned(result, ir.castFrom)
    serializeIRTypeAligned(result, ir.castTo)

# ---------------------------------------------------------------------------
# IRExpr deserialization (forward declaration for mutual recursion)
# ---------------------------------------------------------------------------

func deserializeIRExprAlignedAt(data: openArray[byte], offset: var int): IRExpr
  ## Forward declaration — internal recursive deserializer at a given offset.

# --- helpers that call deserializeIRExprAlignedAt ---

func deserializeCaseBranchAligned(data: openArray[byte], offset: var int): CaseBranch =
  ## Deserialize a CaseBranch: pattern (int64) + body (IRExpr).
  if offset < 0: return CaseBranch(pattern: 0, body: nil)
  let pattern = readInt64Aligned(data, offset)
  if offset < 0: return CaseBranch(pattern: 0, body: nil)
  let body = deserializeIRExprAlignedAt(data, offset)
  if offset < 0: return CaseBranch(pattern: 0, body: nil)
  CaseBranch(pattern: pattern, body: body)

func deserializeIRExprSeqAligned(data: openArray[byte], offset: var int): seq[IRExpr] =
  ## Deserialize a sequence of IRExpr: count (uint64) + aligned elements.
  if offset < 0: return @[]
  let count = int(readUint64Aligned(data, offset))
  if offset < 0: return @[]
  result = newSeq[IRExpr](count)
  for i in 0 ..< count:
    result[i] = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return @[]

func deserializeStringSeqAligned(data: openArray[byte], offset: var int): seq[string] =
  ## Deserialize a sequence of strings: count (uint64) + aligned elements.
  if offset < 0: return @[]
  let count = int(readUint64Aligned(data, offset))
  if offset < 0: return @[]
  result = newSeq[string](count)
  for i in 0 ..< count:
    result[i] = readStringAligned(data, offset)
    if offset < 0: return @[]

# --- main implementation (mutual recursion resolved) ---

func deserializeIRExprAlignedAt(data: openArray[byte], offset: var int): IRExpr =
  ## Deserialize an IRExpr at the given offset (recursive). Any truncation,
  ## unknown tag, or domain violation leaves the sticky -1 sentinel in
  ## `offset` and returns nil — never a silently-wrong tree.
  if offset < 0: return nil
  let tag = readTag(data, offset)
  if offset < 0: return nil
  case tag
  of 0x00: nil

  of 0x01: # irLit — SIGNED int64 payload (canonical signed reading; the
           # high-bit-set payload IS a negative value — values ≥ 2^63 never
           # travel under this tag)
    let v = readInt64Aligned(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irLit, litVal: v)

  of 0x0F: # irLitU64 — u64-domain literal [2^63, 2^64−1]; payload < 2^63 is
           # a domain violation (decode error, never a signed reinterpretation)
    let v = readUint64Aligned(data, offset)
    if offset < 0: return nil
    if v < 0x8000000000000000'u64:
      offset = -1
      return nil
    IRExpr(kind: irLit, litU64: v)

  of 0x02: # irFloatLit
    let f = readFloat64Aligned(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irFloatLit, floatVal: f)

  of 0x03: # irVar
    let name = readStringAligned(data, offset)
    if offset < 0: return nil
    let ty = deserializeIRTypeAligned(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irVar, varName: name, varType: ty)

  of 0x04: # irLet (isCompileTime=false)
    let name = readStringAligned(data, offset)
    if offset < 0: return nil
    let val = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let body = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irLet, letName: name, letVal: val, letBody: body, isCompileTime: false)

  of 0x0E: # irLet (isCompileTime=true, CLET)
    let name = readStringAligned(data, offset)
    if offset < 0: return nil
    let val = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let body = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irLet, letName: name, letVal: val, letBody: body, isCompileTime: true)

  of 0x05: # irIf
    let cond = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let thenE = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let elseE = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irIf, ifCond: cond, ifThen: thenE, ifElse: elseE)

  of 0x06: # irCase
    let scrutinee = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let branchCount = int(readUint64Aligned(data, offset))
    if offset < 0: return nil
    var branches = newSeq[CaseBranch](branchCount)
    for i in 0 ..< branchCount:
      branches[i] = deserializeCaseBranchAligned(data, offset)
      if offset < 0: return nil
    let defaultExpr = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irCase, caseScrutinee: scrutinee,
           caseBranches: branches, caseDefault: defaultExpr)

  of 0x07: # irCall
    let name = readStringAligned(data, offset)
    if offset < 0: return nil
    let args = deserializeIRExprSeqAligned(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irCall, callName: name, callArgs: args)

  of 0x08: # irBinOp
    let opNum = readUint64Aligned(data, offset)
    if offset < 0: return nil
    if opNum > uint64(boLtU.ord):
      offset = -1  # out-of-domain BinOpKind ordinal — decode error
      return nil
    let op = cast[BinOpKind](int(opNum))
    let lhs = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let rhs = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irBinOp, binOp: op, binLhs: lhs, binRhs: rhs)

  of 0x09: # irUnaryOp
    let opNum = readUint64Aligned(data, offset)
    if offset < 0: return nil
    if opNum > uint64(uoBvNeg.ord):
      offset = -1  # out-of-domain UnaryOpKind ordinal — decode error
      return nil
    let op = cast[UnaryOpKind](int(opNum))
    let arg = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irUnaryOp, unaryOp: op, unaryArg: arg)

  of 0x0A: # irRecCall
    let args = deserializeIRExprSeqAligned(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irRecCall, recArgs: args)

  of 0x0B: # irLoop
    let lkNum = readUint64Aligned(data, offset)
    if offset < 0: return nil
    if lkNum > uint64(lkWhile.ord):
      offset = -1  # out-of-domain LoopKind ordinal — decode error
      return nil
    let lk = cast[LoopKind](int(lkNum))
    let vars = deserializeStringSeqAligned(data, offset)
    if offset < 0: return nil
    let inits = deserializeIRExprSeqAligned(data, offset)
    if offset < 0: return nil
    let cond = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let step = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let body = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let invariants = deserializeIRExprSeqAligned(data, offset)
    if offset < 0: return nil
    let variant = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irLoop, loopKind: lk, loopVars: vars,
           loopInits: inits, loopCond: cond, loopStep: step,
           loopBody: body, loopInvariants: invariants,
           loopVariant: variant)

  of 0x0C: # irStringLit
    let s = readStringAligned(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irStringLit, stringVal: s)

  of 0x0D: # irCast
    let castExpr = deserializeIRExprAlignedAt(data, offset)
    if offset < 0: return nil
    let castFrom = deserializeIRTypeAligned(data, offset)
    if offset < 0: return nil
    let castTo = deserializeIRTypeAligned(data, offset)
    if offset < 0: return nil
    IRExpr(kind: irCast, castExpr: castExpr, castFrom: castFrom, castTo: castTo)

  else:
    offset = -1  # unknown IRExpr tag — a decode error, never a silent nil
    nil

func deserializeIRExprAligned*(data: openArray[byte]): IRExpr =
  ## Main deserialization entry point. Reads from offset 0.
  ## Returns nil on invalid/empty data.
  ## Backfills typ field on deserialized tree via recomputeTyp.
  var offset = 0
  let e = deserializeIRExprAlignedAt(data, offset)
  if e != nil: recomputeTyp(e)
  e

{.pop.}
