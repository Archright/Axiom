## parser_utils.nim — Nim compiler AST parsing with global IdentCache reuse
## Thread-safe via threadvar caches for malebolgia parallel processing.
## Pattern: ast_builder.nim creates IdentCache/ConfigRef once, reuses across files.

import core/trusted/axiom_pragmas_lite
import compiler/[parser, ast, idents, options, llstream, pathutils, lineinfos]
import core/crypto/hash_kernel
import core/results
import core/utils/io_utils
import std/json

# ── Global thread-local caches ────────────────────────────────────
var identCache* {.threadvar.}: IdentCache
var configRef* {.threadvar.}: ConfigRef

# ── Parse memo (VS-R2c "AST single parse") ────────────────────────
# The parse input at this seam is BYTES, so the memo identity is the content
# itself — sha256 via core/crypto/hash_kernel (the project hash SSOT). Content
# identity is strictly stronger than a path/stat identity: a same-size,
# same-stat overwrite of a file changes the bytes and therefore the key.
# Bounded FIFO: only clean parses (non-nil AST, no parse-error increment) are
# stored; failed or partial parses stay uncached so their per-call diagnostic
# capture (captureParseFailure) keeps firing. Sharing the returned PNode is
# safe because every consumer treats the parse result as read-only (verified
# by grep: the only PNode-tree mutation in src/ operates on a copyTree copy
# in the nimtry gate, which parses through its own parser instance), and
# hash(PIdent) is the interned identifier STRING hash, not pointer identity
# (docs/spec/nim_ast_node_shape_quirks.md Q4).
const ParseMemoCapacity = 16

type
  ParseMemoEntry = object
    contentSha: string
    ast: PNode

var
  parseMemo {.threadvar.}: seq[ParseMemoEntry]
  parseMemoHits* {.threadvar.}: int
  parseMemoMisses* {.threadvar.}: int

template lookupParseMemo(contentSha: string): PNode =
  ## Returns the memoized AST for `contentSha` (nil = miss) and maintains the
  ## thread-local hit/miss counters. A template, not a func: the effect system
  ## rejects threadvar access in funcs, and the src/core/ proc-count ratchet
  ## (architecture_invariants.nim) permits no new proc declarations.
  block:
    var hit: PNode = nil
    for i in 0 ..< parseMemo.len:
      if parseMemo[i].contentSha == contentSha:
        hit = parseMemo[i].ast
        inc parseMemoHits
        break
    if hit.isNil:
      inc parseMemoMisses
    hit

template storeParseMemo(contentSha: string; parsedAst: PNode) =
  ## Insert/refresh a memo entry (threadvar mutation — template, inlined at
  ## the proc call site; src/core/ proc ratchet: no new proc declarations).
  ## The parameter is named `parsedAst` (not `ast`): template parameter
  ## substitution is identifier-textual in Nim 2.2.10 and would rewrite the
  ## `parseMemo[i].ast` field selector to the argument expression.
  block:
    var updated = false
    for i in 0 ..< parseMemo.len:
      if parseMemo[i].contentSha == contentSha:
        parseMemo[i].ast = parsedAst
        updated = true
        break
    if not updated:
      if parseMemo.len >= ParseMemoCapacity:
        parseMemo.delete(0)
      parseMemo.add(ParseMemoEntry(contentSha: contentSha, ast: parsedAst))

template parseMemoStats*(): tuple[hits, misses: int] =
  ## Thread-local parse-memo hit/miss counters for deterministic verification.
  (hits: parseMemoHits, misses: parseMemoMisses)

template resetParseMemoStats*() =
  ## Reset thread-local parse-memo state and hit/miss counters for testing.
  parseMemo.setLen(0)
  parseMemoHits = 0
  parseMemoMisses = 0

proc initParserUtils*() {.raises: [].} =
  ## Initialize the global parser caches for the current thread.
  ## Must be called once per thread before using parseFileAST/parseStringAST.
  identCache = newIdentCache()
  configRef = newConfigRef()
  ## newConfigRef() leaves errorMax at 0, which makes the Nim compiler call
  ## quit() on the FIRST parse error — terminating the host process instead of
  ## failing soft. parseStringAST's contract is "returns nil on failure", so
  ## raise the cap to make parse errors recoverable. Without this, any invalid
  ## .nim content (e.g. a file walked by the global symbol graph builder) kills
  ## the whole `ax prove` process with exit 1 after the pipeline completes.
  configRef.errorMax = high(int)

# ── Byte Offset Helpers (for CST surgical editor replacement) ──────
proc buildLineOffsetTable*(source: string): seq[int] {.raises: [].} =
  ## Build a table mapping line number (1-indexed) to byte offset of line start.
  ## O(N) scan, O(1) lookup.
  result = @[0]
  for i, ch in source:
    if ch == '\n':
      result.add(i + 1)  # +1 because next line starts after \n

proc lineInfoToByteOffset*(info: TLineInfo; lineStarts: seq[int]): int {.raises: [].} =
  ## Convert TLineInfo (line, col) to exact byte offset in source.
  ## Returns -1 if line is out of range.
  let lineIdx = int(info.line) - 1
  if lineIdx < 0 or lineIdx >= lineStarts.len:
    return -1
  result = lineStarts[lineIdx] + int(info.col)

proc byteOffsetToLineInfo*(offset: int; source: string; lineStarts: seq[int]): TLineInfo {.raises: [].} =
  ## Reverse conversion: byte offset to TLineInfo.
  ## Returns TLineInfo with line/col set (fileIndex = 0).
  for i, start in lineStarts:
    if start > offset:
      return TLineInfo(line: uint16(i), col: int16(offset - lineStarts[i-1]), fileIndex: FileIndex(0))
  return TLineInfo(line: uint16(lineStarts.len), col: int16(offset - lineStarts[^1]), fileIndex: FileIndex(0))

proc captureParseFailure(content: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## P1 diagnostic: best-effort capture of a Nim source string that failed
  ## in-process parsing (emits `<string>(line, col)` diagnostics to stderr).
  ## Written to logs/lean_lsp_payloads.jsonl so the offending line can be
  ## recovered from a prove run. Fail-open: capture failures are discarded —
  ## this is a diagnostic aid, never a gate (AGENTS.md §0.9).
  # axiom:best-effort(parse failure capture is diagnostic-only; failures never block parsing)
  try:
    let payload = $(%*{"event": "parse_string_failure", "source": content})
    ## intentional-discard: append-only diagnostic log; failure is non-blocking (best-effort)
    discard appendFileLineOpt("logs/lean_lsp_payloads.jsonl", @[payload])
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc parseStringAST*(content: string): PNode {.raises: [].} =
  ## Parse Nim source string into AST using global thread-local caches.
  ## Returns nil on failure.
  ## VS-R2c: identical bytes parsed repeatedly in one thread return the SAME
  ## cached PNode (content-keyed memo). The prove pipeline's selection
  ## boundary parses one subject module three times per candidate (canonical
  ## AST hash, extraction agreement, binding inventory); the memo collapses
  ## those to a single parse with byte-identical downstream results.
  {.push warning[BareExcept]: off.}
  try:
    if content.len == 0: return
    let contentSha = sha256Hex(content)
    let memoHit = lookupParseMemo(contentSha)
    if not memoHit.isNil:
      result = memoHit
      return
    if configRef.isNil: initParserUtils()
    var stream = llStreamOpen(content)
    let fakePath = AbsoluteFile("<string>")
    var p: Parser
    let errCountBefore = configRef.errorCounter
    openParser(p, fakePath, stream, identCache, configRef)
    result = parseAll(p)
    closeParser(p)
    if result.isNil or configRef.errorCounter > errCountBefore:
      captureParseFailure(content)
    else:
      storeParseMemo(contentSha, result)
  except CatchableError:
    captureParseFailure(content)
  except Exception:
    discard
  {.pop.}

proc parseFileAST*(filePath: string): PNode {.raises: [].} =
  ## Parse a Nim source file into AST using global thread-local caches.
  ## Returns nil on failure.
  {.push warning[BareExcept]: off.}
  try:
    let content = readFile(filePath)
    result = parseStringAST(content)
  except CatchableError:
    discard  # axiom:best-effort(file read or parse failure -> nil; documented fail-open)
  except Exception:
    discard
  {.pop.}

proc parseNimRes*(source: string): Result[PNode, string] {.raises: [], axiomDecision.} =
  ## Wrap parseStringAST returning Result[PNode, string].
  let ast = parseStringAST(source)
  if ast.isNil:
    return err("Failed to parse Nim source")
  ok(ast)
