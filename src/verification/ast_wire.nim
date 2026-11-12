import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## AST Wire Codec — deterministic serialization of the certified-subset
## canonical AST (certification-continuity Phase 3.75 — Tier 2).
##
## PURPOSE
##   Serialize the certified-subset CanonNode tree (the subset the canonical
##   Nim extractor ast_to_ir.convertExprCanon/convertBodyCanon/
##   convertFuncDefCanon consumes WITHOUT loss) into a stable, deterministic,
##   8-byte-aligned binary form that the independent Lean reference extractor
##   (proofs/IR/ReferenceExtractor.lean) decodes with its OWN decoder.
##   ir_binary_codec's tag style is reused for consistency (1-byte tag + 7
##   padding bytes per slot; LE scalars; length-prefixed strings), but this is
##   a DIFFERENT wire: it serializes canonical AST nodes, not IRExpr.
##
## SUPPORTED WIRE KINDS — the certified-subset extraction surface (MINIMAL):
##   literals   ckIntLit/ckInt8/16/32/64Lit, ckUInt*Lit (unified 0x1C, int64),
##              ckCharLit (0x21), ckNilLit (0x22 → lit 0)
##   variables  ckIdent (0x1D, gensym-stripped)
##   structure  ckInfix (0x1E), ckPrefix (0x1F), ckCall (0x20)
##   control    ckReturnStmt (0x17); ckIfStmt (0x18) ONLY in the early-return
##              shape the canonical extractor truly handles (single ckElifBranch
##              whose then-body is exactly [ckReturnStmt]; encoded at the
##              STMT-LIST level as awIfStmt(cond, retVal, rest-stmtList) —
##              the rest folds into the else branch exactly like
##              convertBodyFromCanon(stmts, i+1))
##   bindings   ckLetSection (0x13) / ckVarSection (0x14) / ckConstSection
##              (0x15): single-name ckIdentDefs ONLY (len == 3; name = child[0],
##              value = child[2], ckEmpty value → lit 0 — exactly what
##              convertBodyFromCanon reads); ckAsgn (0x16) with a plain ckIdent
##              target ("result" → body expression on the Lean side, matching
##              the canonical extractor)
##   functions  ckProcDef/ckFuncDef (0x11) + ckFormalParams (param names =
##              children[0 .. len-3], type child = len-2, default value
##              ignored — mirroring convertFuncDefCanon). The param TYPE
##              accepts ckIdent, ckEmpty, and the bounded bracket shape
##              `typedesc[<Ident>]` (recorded as the string "typedesc[X]";
##              both extractors map it to bitVec64 — the list family
##              seq/openArray/array stays rejected, see convertTypeCanon).
##   containers ckStmtList (0x12); ckDiscardStmt is a semantic no-op of the
##              extractor (binds nothing, emits nothing) and is therefore
##              ELIDED by the wire codec, exactly as convertBodyFromCanon
##              skips it; a CHILDLESS ckCommentStmt (a doc-comment statement:
##              binds nothing, emits nothing, and has no IR image in either
##              extractor) is likewise ELIDED at statement position — the
##              differential's subject is the resulting IR, and a comment
##              contributes nothing to it on either side. A comment carrying
##              children is NOT a no-op shape and stays fail-closed. This
##              elision is explicit, not silent: the production extractor's
##              conservative loss accounting for comments (ast_to_ir
##              markLoss) is a production-path flag, recorded independently
##              in the CompletenessEvidence, and is not part of what the
##              wire differential certifies. ckPar with exactly one child
##              serializes its CONTENT — the canonical extractor's own
##              unwrap rule (convertExprCanon: nnkPar → convertExpr(n[0]));
##              multi-child ckPar stays fail-closed.
##
## UNSUPPORTED (fail-closed — serializeAstWire returns aweUnsupported):
##   floats (ckFloat*Lit), strings (ckStrLit family), ckSym, ckCaseStmt,
##   ckForStmt/ckWhileStmt, ckIfExpr in ANY shape (the canonical extractor
##   silently degrades stmtList-wrapped branch bodies to irLit(0) — lossy —
##   so expression-form if is outside the agreement subset), multi-branch or
##   non-early-return ckIfStmt, ckStmtListExpr/ckBlockExpr, multi-name
##   identdefs (len > 3), and every remaining CanonKind. The Nim extractor's
##   lossy paths must NEVER be silently wired: an unsupported node aborts the
##   differential with EA_UNSUPPORTED.
##
## WIRE LAYOUT (8-byte aligned, ir_binary_codec tag style):
##   magic 0xA0 (8-byte slot) · uint64 version (=1) · root node
##   node := tag(8) fields…; strings := uint64 len + bytes + zero-pad to 8;
##   counts := uint64.

import shared/canonical_ast
import std/strutils  # `find` for stripGensymWire

type
  AstWireError* = enum
    aweNone
    aweUnsupportedKind
    aweMalformed

  AstWireResult* = object
    ok*: bool
    bytes*: seq[byte]
    error*: AstWireError
    kindName*: string

  SerializeOutcome* = object
    ok*: bool
    error*: AstWireError
    kind*: string

const
  awMagic* = 0xA0'u8
  awVersion* = 1'u64
  awFuncDef* = 0x11'u8
  awStmtList* = 0x12'u8
  awLetSection* = 0x13'u8
  awVarSection* = 0x14'u8
  awConstSection* = 0x15'u8
  awAsgn* = 0x16'u8
  awReturnStmt* = 0x17'u8
  awIfStmt* = 0x18'u8
  awElifExpr* = 0x19'u8
  awElseExpr* = 0x1A'u8
  awIfExpr* = 0x1B'u8
  awIntLit* = 0x1C'u8
  awIdent* = 0x1D'u8
  awInfix* = 0x1E'u8
  awPrefix* = 0x1F'u8
  awCall* = 0x20'u8
  awCharLit* = 0x21'u8
  awNilLit* = 0x22'u8

func okOutcome(): SerializeOutcome {.inline.} =
  SerializeOutcome(ok: true, error: aweNone, kind: "")

func failOutcome(error: AstWireError; kind: string): SerializeOutcome {.inline.} =
  SerializeOutcome(ok: false, error: error, kind: kind)

# ---------------------------------------------------------------------------
# Alignment + write helpers (mirrors ir_binary_codec's 8-byte discipline)
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

func stripGensymWire*(s: string): string {.inline.} =
  ## Strip Nim gensym suffix (everything after backtick), mirroring
  ## ast_to_ir.stripGensym so both extractor inputs see identical names.
  let idx = s.find('`')
  if idx >= 0: s[0 ..< idx]
  else: s

# ---------------------------------------------------------------------------
# Certified-subset shape checks
# ---------------------------------------------------------------------------

func isEarlyReturnIfWire*(stmt: CanonNode): bool =
  ## Early-return shape: ckIfStmt with exactly one ckElifBranch whose
  ## then-body is a stmtList whose FIRST statement is a return stmt
  ## (convertBodyFromCanon's isEarlyReturnIfCanon). The then-body must
  ## contain ONLY that return — trailing statements after a return are
  ## dead code outside the certified subset (fail-closed).
  if stmt.kind != ckIfStmt or stmt.children.len != 1:
    return false
  let br = stmt.children[0]
  if br.kind != ckElifBranch or br.children.len < 2:
    return false
  let thenBody = br.children[1]
  if thenBody.kind != ckStmtList or thenBody.children.len == 0:
    return false
  thenBody.children.len == 1 and thenBody.children[0].kind == ckReturnStmt

# ---------------------------------------------------------------------------
# Node serialization (fail-closed: any unsupported node aborts the run)
# ---------------------------------------------------------------------------

func serializeNodeWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome
  ## Forward declaration (mutual recursion with serializeStmtListWire).

func serializeStmtListWire(buf: var seq[byte]; stmts: openArray[CanonNode]): SerializeOutcome =
  ## Serialize a statement list. Early-return ifs are encoded with their
  ## REMAINING statements folded into the else branch as an inner stmt list
  ## (mirrors convertBodyFromCanon(stmts, i + 1)); discards are elided.
  ## The count covers every non-discard statement (the early-return if
  ## counts as ONE), so the decoder walks exactly the emitted nodes.
  writeTagAligned(buf, awStmtList)
  ## Outer membership rule: an early-return if is always the LAST outer
  ## statement (convertBodyFromCanon returns at the FIRST early-if and folds
  ## the remainder into the if's else) — so the count covers the prefix
  ## statements plus that one if, and post-if statements live inside rest.
  var total = 0
  for child in stmts:
    if child.kind == ckDiscardStmt or
        (child.kind == ckCommentStmt and child.children.len == 0):
      continue
    inc total
    if child.kind == ckIfStmt and isEarlyReturnIfWire(child):
      break
  writeU64Aligned(buf, uint64(total))
  var i = 0
  while i < stmts.len:
    let child = stmts[i]
    if child.kind == ckDiscardStmt or
        (child.kind == ckCommentStmt and child.children.len == 0):
      inc i
      continue
    if child.kind == ckIfStmt and isEarlyReturnIfWire(child):
      let branch = child.children[0]
      let thenBody = branch.children[1]
      writeTagAligned(buf, awIfStmt)
      let c = serializeNodeWire(buf, branch.children[0])
      if not c.ok: return c
      let ret = thenBody.children[0]
      if ret.children.len > 0 and ret.children[0].kind != ckEmpty:
        let r = serializeNodeWire(buf, ret.children[0])
        if not r.ok: return r
      else:
        writeTagAligned(buf, awIntLit)
        writeI64Aligned(buf, 0)
      if i + 1 < stmts.len:
        return serializeStmtListWire(buf, stmts.toOpenArray(i + 1, stmts.len - 1))
      writeTagAligned(buf, awStmtList)
      writeU64Aligned(buf, 0)
      return okOutcome()
    let r = serializeNodeWire(buf, child)
    if not r.ok: return r
    inc i
  okOutcome()

func serializeInfixWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome =
  ## ckInfix: op-name + two operands (child count must be exactly 3).
  if n.children.len != 3:
    return failOutcome(aweMalformed, $n.kind)
  writeTagAligned(buf, awInfix)
  writeStrAligned(buf, stripGensymWire(n.children[0].name))
  let l = serializeNodeWire(buf, n.children[1])
  if not l.ok: return l
  serializeNodeWire(buf, n.children[2])

func serializePrefixWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome =
  ## ckPrefix: op-name + one operand.
  if n.children.len != 2:
    return failOutcome(aweMalformed, $n.kind)
  writeTagAligned(buf, awPrefix)
  writeStrAligned(buf, stripGensymWire(n.children[0].name))
  serializeNodeWire(buf, n.children[1])

func serializeCallWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome =
  ## ckCall: callee-name + count + args.
  if n.children.len < 1:
    return failOutcome(aweMalformed, $n.kind)
  writeTagAligned(buf, awCall)
  writeStrAligned(buf, stripGensymWire(n.children[0].name))
  writeU64Aligned(buf, uint64(n.children.len - 1))
  for i in 1 ..< n.children.len:
    let r = serializeNodeWire(buf, n.children[i])
    if not r.ok: return r
  okOutcome()

func serializeAsgnWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome =
  ## ckAsgn with a plain ckIdent target ("result" → body expr on the Lean side).
  if n.children.len != 2 or n.children[0].kind != ckIdent:
    return failOutcome(aweUnsupportedKind, $n.kind)
  writeTagAligned(buf, awAsgn)
  writeStrAligned(buf, stripGensymWire(n.children[0].name))
  serializeNodeWire(buf, n.children[1])

func serializeReturnWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome =
  ## ckReturnStmt: value node, or lit 0 for a bare return.
  writeTagAligned(buf, awReturnStmt)
  if n.children.len > 0 and n.children[0].kind != ckEmpty:
    let r = serializeNodeWire(buf, n.children[0])
    if not r.ok: return r
  else:
    writeTagAligned(buf, awIntLit)
    writeI64Aligned(buf, 0)
  okOutcome()

func serializeBindSectionWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome =
  ## let/var/const section: single-name identdefs only (child[0], child[2]);
  ## multi-name or malformed identdefs are rejected (never guessed).
  let tag = case n.kind
            of ckLetSection: awLetSection
            of ckVarSection: awVarSection
            else: awConstSection
  writeTagAligned(buf, tag)
  writeU64Aligned(buf, uint64(getChildren(n).len))
  for idn in getChildren(n):
    if idn.kind != ckIdentDefs or idn.children.len != 3:
      return failOutcome(aweUnsupportedKind, $idn.kind & "/" & $idn.children.len)
    let nameNode = idn.children[0]
    if nameNode.kind != ckIdent:
      return failOutcome(aweUnsupportedKind, $nameNode.kind)
    writeStrAligned(buf, stripGensymWire(nameNode.name))
    let valueNode = idn.children[2]
    if valueNode.kind == ckEmpty:
      # Uninitialized var/let: the canonical extractor binds convertExprCanon
      # (ckEmpty) = irLit(0) — encode that explicitly.
      writeTagAligned(buf, awIntLit)
      writeI64Aligned(buf, 0)
    else:
      let r = serializeNodeWire(buf, valueNode)
      if not r.ok: return r
  okOutcome()

func serializeNodeWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome =
  ## Serialize ONE supported canonical node into `buf`. The first error
  ## (with the offending kind name) is returned — callers abort the whole
  ## wire on any non-ok outcome.
  case n.kind
  of ckIntLit, ckInt8Lit, ckInt16Lit, ckInt32Lit, ckInt64Lit,
     ckUIntLit, ckUInt8Lit, ckUInt16Lit, ckUInt32Lit, ckUInt64Lit:
    writeTagAligned(buf, awIntLit)
    writeI64Aligned(buf, int64(n.intVal))
    okOutcome()
  of ckCharLit:
    writeTagAligned(buf, awCharLit)
    writeI64Aligned(buf, int64(n.intVal))
    okOutcome()
  of ckNilLit:
    writeTagAligned(buf, awNilLit)
    okOutcome()
  of ckIdent:
    writeTagAligned(buf, awIdent)
    writeStrAligned(buf, stripGensymWire(n.name))
    okOutcome()
  of ckInfix:
    serializeInfixWire(buf, n)
  of ckPrefix:
    serializePrefixWire(buf, n)
  of ckCall:
    serializeCallWire(buf, n)
  of ckStmtList:
    if n.children.len == 0:
      serializeStmtListWire(buf, [])
    else:
      serializeStmtListWire(buf, toOpenArray(n.children, 0, n.children.len - 1))
  of ckLetSection, ckVarSection, ckConstSection:
    serializeBindSectionWire(buf, n)
  of ckAsgn:
    serializeAsgnWire(buf, n)
  of ckReturnStmt:
    serializeReturnWire(buf, n)
  of ckPar:
    # Bounded paren surface: a SINGLE-child ckPar unwraps to its content —
    # exactly the canonical extractor's rule (convertExprCanon: nnkPar →
    # convertExpr(n[0]); "a parenthesized expression denotes the same value
    # as its content"). Serializing the content is a faithful encoding of
    # that denotation (same principle as the ckDiscardStmt elision), and
    # both extractors compare the resulting IR byte-for-byte. A multi-child
    # ckPar has no single content expression and stays fail-closed, matching
    # the extractor's loss-marking there.
    if n.children.len == 1:
      serializeNodeWire(buf, n.children[0])
    else:
      failOutcome(aweUnsupportedKind, $n.kind)
  of ckIfStmt, ckIfExpr:
    # Statement-form ifs are only supported in the early-return shape, which
    # is encoded at the STMT-LIST level (see serializeStmtListWire).
    # Expression-form if is lossy in the canonical extractor (both frontends
    # wrap branch bodies in ckStmtList → convertIfExprCanon emits irLit(0)).
    failOutcome(aweUnsupportedKind, $n.kind)
  else:
    failOutcome(aweUnsupportedKind, $n.kind)

func wireParamNames(fp: CanonNode): tuple[names, types: seq[string]; oc: SerializeOutcome] =
  ## Formal-param names/types (mirrors convertFuncDefCanon: names are
  ## children[0 .. len-3], type is child len-2; empty type → BV64 default).
  result = (names: @[], types: @[], oc: okOutcome())
  for i in 1 ..< fp.children.len:
    let idn = fp.children[i]
    if idn.kind != ckIdentDefs:
      continue
    if idn.children.len < 2:
      result.oc = failOutcome(aweMalformed, $idn.kind)
      return
    let tyNode = idn.children[idn.children.len - 2]
    var typeName = ""
    case tyNode.kind
    of ckIdent:
      typeName = stripGensymWire(tyNode.name)
    of ckEmpty:
      discard
    of ckBracketExpr:
      # Bounded bracket-type surface: `typedesc[<Ident>]` — a compile-time
      # type-carrier parameter. Both extractors agree exactly on it: the
      # canonical Nim extractor maps a bracket type outside the
      # seq/openArray/array list family to irTypeBitVec64
      # (convertTypeCanon), and the Lean reference extractor maps the
      # recorded "typedesc[X]" string to bitVec64 by the same default
      # (typeOfName: not bool/string). The seq/openArray/array family stays
      # REJECTED — there the two sides would diverge (irTypeList vs the
      # bitVec64 default) — and so does every other bracket shape (wrong
      # arity, non-ident head/arg).
      if tyNode.children.len == 2 and
          tyNode.children[0].kind == ckIdent and
          stripGensymWire(tyNode.children[0].name) == "typedesc" and
          tyNode.children[1].kind == ckIdent:
        typeName = "typedesc[" & stripGensymWire(tyNode.children[1].name) & "]"
      else:
        result.oc = failOutcome(aweUnsupportedKind, $tyNode.kind)
        return
    else:
      result.oc = failOutcome(aweUnsupportedKind, $tyNode.kind)
      return
    for j in 0 ..< idn.children.len - 2:
      let nm = idn.children[j]
      if nm.kind != ckIdent:
        result.oc = failOutcome(aweUnsupportedKind, $nm.kind)
        return
      result.names.add(stripGensymWire(nm.name))
      result.types.add(typeName)

func serializeFuncDefWire(buf: var seq[byte]; n: CanonNode): SerializeOutcome =
  ## Root node: the func def. Validates the subset func-def shape used by
  ## convertFuncDefCanon (name node, formal params, stmt-list body).
  if n.kind notin {ckProcDef, ckFuncDef}:
    return failOutcome(aweUnsupportedKind, $n.kind)
  writeTagAligned(buf, awFuncDef)
  if n.children.len < 4:
    return failOutcome(aweMalformed, $n.kind)
  let nameNode = n.children[0]
  var name = ""
  case nameNode.kind
  of ckIdent:
    name = stripGensymWire(nameNode.name)
  of ckPostfix:
    if nameNode.children.len > 1 and nameNode.children[1].kind == ckIdent:
      name = stripGensymWire(nameNode.children[1].name)
    else:
      return failOutcome(aweMalformed, $nameNode.kind)
  else:
    return failOutcome(aweUnsupportedKind, $nameNode.kind)
  writeStrAligned(buf, name)
  let fp = n.children[3]
  if fp.kind != ckFormalParams:
    return failOutcome(aweMalformed, $fp.kind)
  let (pnames, ptypes, poke) = wireParamNames(fp)
  if not poke.ok: return poke
  writeU64Aligned(buf, uint64(pnames.len))
  for i in 0 ..< pnames.len:
    writeStrAligned(buf, pnames[i])
    writeStrAligned(buf, ptypes[i])
  if n.children.len < 7:
    return failOutcome(aweMalformed, $n.kind)
  let body = n.children[6]
  if body.kind != ckStmtList:
    return failOutcome(aweUnsupportedKind, $body.kind)
  serializeStmtListWire(buf, toOpenArray(body.children, 0, body.children.len - 1))

func serializeAstWire*(root: CanonNode): AstWireResult =
  ## Entry point: serialize a certified-subset function def to the wire form.
  ## Unsupported/malformed AST → ok=false with the failing kind recorded
  ## (fail-closed — the caller must not proceed with partial evidence).
  result = AstWireResult(ok: false, bytes: @[], error: aweNone, kindName: "")
  var buf: seq[byte] = @[]
  writeTagAligned(buf, awMagic)
  writeU64Aligned(buf, awVersion)
  let r = serializeFuncDefWire(buf, root)
  if not r.ok:
    result.error = r.error
    result.kindName = r.kind
    return
  result.ok = true
  result.bytes = buf

{.pop.}