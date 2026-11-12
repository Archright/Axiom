import compiler/[ast, idents]
import std/[strutils, algorithm, options, sets]
import core/trusted/axiom_pragmas_lite
import core/parser_utils
import core/crypto/hash_kernel
import core/results
import core/sloc_policy

const CanonicalHashAlgorithm* = "nim-pnode-canonical-v2"

const EffectiveSlocAlgorithmVersion* = sloc_policy.EffectiveSlocAlgorithmVersion
const EffectiveSlocPolicyVersion* = sloc_policy.EffectiveSlocPolicyVersion

const
  nkHiddenKinds* = {nkHiddenCallConv, nkHiddenStdConv, nkHiddenSubConv,
                     nkHiddenAddr, nkHiddenDeref, nkHiddenTryStmt}

proc extractEffectiveSourceSpans*(n: PNode): seq[(int, int)] {.raises: [], axiomDecision(
  id = "DECISION-0003",
  reason = "PNode traversal to collect source-origin effective unit line intervals for EffectiveSLOC computation; policy version: " & EffectiveSlocPolicyVersion,
  adr = "docs/spec/effective_sloc.md",
  introduced = "v2"
).} =
  if n.isNil:
    return @[]
  if n.info.line == 0:
    for i in 0 ..< n.safeLen:
      result.add extractEffectiveSourceSpans(n[i])
    return result
  if n.kind == nkCommentStmt:
    return @[]
  if n.kind == nkEmpty:
    for i in 0 ..< n.safeLen:
      result.add extractEffectiveSourceSpans(n[i])
    return result
  case n.kind
  of nkHiddenKinds:
    for i in 0 ..< n.safeLen:
      result.add extractEffectiveSourceSpans(n[i])
    return result
  of nkStmtList, nkStmtListExpr, nkBlockStmt, nkBlockExpr,
     nkStmtListType, nkBlockType, nkProcDef, nkFuncDef,
     nkTemplateDef, nkMacroDef, nkMethodDef, nkConverterDef,
     nkIteratorDef, nkWhenStmt, nkIfStmt, nkCaseStmt, nkTryStmt:
    for i in 0 ..< n.safeLen:
      result.add extractEffectiveSourceSpans(n[i])
    return result
  else: discard
  let startLine = n.info.line.int
  let endLine = if n.kind in {nkStrLit, nkTripleStrLit}:
                  startLine + n.strVal.splitLines().len
                else:
                  maxSourceLine(n)
  if endLine > 0:
    result.add (startLine, endLine)
  for i in 0 ..< n.safeLen:
    result.add extractEffectiveSourceSpans(n[i])

proc effectiveSlocFromSpans*(spans: seq[(int, int)]): int {.raises: [], axiomDecision(
  id = "DECISION-0004",
  reason = "Interval union to compute distinct effective source line count from extracted spans; policy version: " & EffectiveSlocPolicyVersion,
  adr = "docs/spec/effective_sloc.md",
  introduced = "v2"
).} =
  if spans.len == 0:
    return 0
  var sorted = spans.sortedByIt(it[0])
  var curStart = sorted[0][0]
  var curEnd = sorted[0][1]
  for i in 1 ..< sorted.len:
    let s = sorted[i][0]
    let e = sorted[i][1]
    if s <= curEnd + 1:
      if e > curEnd:
        curEnd = e
    else:
      result.inc curEnd - curStart + 1
      curStart = s
      curEnd = e
  result.inc curEnd - curStart + 1

proc parseSourceToPNode*(source: string): Result[PNode, string] {.raises: [], axiomDecision(
  id = "DECISION-0001",
  reason = "Reuse parseNimRes from parser_utils for fail-closed PNode extraction",
  adr = "docs/spec/canonical_ast_identity.md",
  introduced = "v2"
).} =
  parseNimRes(source)

func canonicalProjectVal*(n: PNode): string {.raises: [].} =
  case n.kind
  of nkIdent:
    if n.ident.isNil: "" else: n.ident.s
  of nkSym:
    if n.sym.isNil or n.sym.name.isNil: "" else: n.sym.name.s
  of nkIntLit..nkUInt64Lit:
    $n.intVal
  of nkFloatLit..nkFloat128Lit:
    $n.floatVal
  of nkStrLit..nkTripleStrLit:
    n.strVal
  of nkCharLit:
    $n.intVal
  of nkEmpty, nkNilLit:
    ""
  else:
    ""

proc canonicalizePNode*(n: PNode): string {.raises: [].} =
  if n.isNil:
    return ""
  var parts: seq[string]
  parts.add($n.kind)
  case n.kind
  of nkIdent, nkSym, nkIntLit..nkUInt64Lit, nkFloatLit..nkFloat128Lit,
     nkStrLit..nkTripleStrLit, nkCharLit, nkEmpty, nkNilLit:
    parts.add(canonicalProjectVal(n))
  of nkTableConstr, nkCurly:
    var childReprs: seq[string]
    for i in 0 ..< n.safeLen:
      childReprs.add(canonicalizePNode(n[i]))
    childReprs.sort()
    for repr in childReprs:
      parts.add(repr)
  else:
    for i in 0 ..< n.safeLen:
      parts.add(canonicalizePNode(n[i]))
  result = parts.join("|")

proc computeCanonicalAstHash*(source: string): Result[string, string] {.raises: [], axiomDecision(
  id = "DECISION-0002",
  reason = "Source-to-hash pipeline: parse fail-closed, canonicalize, then SHA-256 with algorithm version prefix",
  adr = "docs/spec/canonical_ast_identity.md",
  introduced = "v2"
).} =
  let parsed = parseSourceToPNode(source)
  if parsed.isErr:
    return err(parsed.err)
  let canonical = canonicalizePNode(parsed.get)
  let hashHex = sha256Hex(canonical)
  ok("sha256:v2:" & CanonicalHashAlgorithm & ":" & hashHex)

proc sourceSloc*(node: PNode): int {.raises: [], axiomDecision(
  id = "DECISION-0008",
  reason = "Public SLOC computation entry point: delegates to extractEffectiveSourceSpans + effectiveSlocFromSpans; decision-bearing public per §0.10 R1",
  adr = "docs/spec/effective_sloc.md",
  introduced = "v9"
).} =
  let spans = extractEffectiveSourceSpans(node)
  effectiveSlocFromSpans(spans)

proc effectiveSloc*(node: PNode; ctx: WhenContext): Result[int, UnknownReason] {.raises: [], axiomDecision(
  id = "DECISION-0009",
  reason = "EffectiveSLOC with WhenContext-aware branch selection; Result-bearing public per §0.10 R1; policy version: " & EffectiveSlocPolicyVersion,
  adr = "docs/spec/effective_sloc.md",
  introduced = "v9"
).} =
  let spansResult = extractEffectiveSourceSpansCtx(node, ctx)
  if spansResult.isErr:
    return err(spansResult.error)
  ok(effectiveSlocFromSpans(spansResult.get))