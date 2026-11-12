import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## MerkleCache — SHA-256 Merkle CST cache for incremental topology scanning.
## Caches per-file content hashes and symbol names to skip re-parsing unchanged files.
## Provides O(1) change detection and Merkle root for batch validation.
##
## Design:
##   - contentHash  = SHA-256(raw source text) — fast change detection
##   - cstHash      = SHA-256(CST node structure) — structural fingerprint
##   - symbolNames  = cached function/proc names — skip re-scan
##   - merkleRoot   = Merkle tree root of all file hashes — O(1) global check

import core/crypto/hash_kernel
import core/interfaces/logging_hub
import core/io/io_utils
import core/parser_utils
import core/trusted/axiom_pragmas_lite
import core/types/results
import core/utils/axiom_error
import core/utils/io_utils
import std/algorithm
import std/json
import std/options
import std/tables
import compiler/ast

type
  MerkleCacheEntry* = object
    ## Per-file cache entry with content hash and symbol metadata.
    contentHash*: string       ## SHA-256 hex of file content (fast change detection)
    cstHash*: string           ## SHA-256 hex of CST node structure
    symbolNames*: seq[string]  ## Function/proc names discovered in this file
    lastModified*: int64       ## File modification timestamp (0 = unknown)
    fileSize*: int64           ## File size in bytes for dual mtime+size guard
    cachedSymbols*: seq[CachedTopologySymbol]  ## Full symbol data for cache hit reconstruction

  CachedTopologySymbol* = object
    ## Serializable subset of TopologySymbol for cache persistence.
    modulePath*: string
    functionName*: string
    nodeType*: string
    nodeIdStr*: string  ## SorterNodeId as string
    declarationLine*: int
    bodyStartLine*: int
    bodyEndLine*: int
    exported*: bool
    boundaryKind*: int  ## TopologyBoundaryKind ordinal
    rawCallTargets*: seq[string]
    branchCount*: int
    nestingDepth*: int
    lineSpan*: int
    hasAxiomImpl*: bool
    definitionFingerprint*: string

  MerkleQueryEngine* = object
    ## Merkle-based topology cache with O(1) change detection.
    fileCache*: Table[string, MerkleCacheEntry]
    symbolToFiles*: Table[string, seq[string]]
    merkleRoot*: string        ## SHA-256 Merkle root of all file hashes

# ─── Hash Functions ─────────────────────────────────────────────────────────

func computeFileContentHash*(source: string): string {.inline.} =
  ## SHA-256 hex digest of file content. Primary cache lookup key.
  sha256Hex(source)

func serializeCstStructure*(node: PNode): string {.raises: [].} =
  ## Recursively serialize PNode kind hierarchy for structural hashing.
  ## Captures tree shape (node kinds) but ignores text content —
  ## two files with different whitespace/comments but same declarations
  ## produce the same structural hash.
  if node.isNil:
    return ""
  result = $node.kind & "("
  for i in 0 ..< node.len:
    let childSer = serializeCstStructure(node[i])
    if childSer.len > 0:
      result &= childSer & ","
  result &= ")"

proc computeCstMerkleRoot*(source: string): string {.raises: [].} =
  ## Parse source with Nim compiler AST and hash the node structure.
  ## Returns SHA-256 of serialized node-kind hierarchy.
  ## Falls back to content hash if parse fails.
  let parseResult = parseNimRes(source)
  if parseResult.isErr:
    return sha256Hex(source)
  let cst = parseResult.get
  let serialized = serializeCstStructure(cst)
  sha256Hex(serialized)

# ─── Cache Lookup ───────────────────────────────────────────────────────────

func isFileUnchanged*(engine: var MerkleQueryEngine;
                      filePath: string;
                      currentHash: string): bool {.inline, raises: [].} =
  ## O(1) cache lookup — returns true if file content hash matches.
  engine.fileCache.getOrDefault(filePath).contentHash == currentHash

func getSymbols*(engine: var MerkleQueryEngine;
                 filePath: string): seq[string] {.inline, raises: [].} =
  ## Retrieve cached symbol names for a file. Empty seq if not cached.
  engine.fileCache.getOrDefault(filePath).symbolNames

func getEntry*(engine: var MerkleQueryEngine;
               filePath: string): Option[MerkleCacheEntry] {.inline, raises: [].} =
  ## Retrieve full cache entry for a file. Returns none if not cached.
  if filePath in engine.fileCache:
    some(engine.fileCache.getOrDefault(filePath))
  else:
    none(MerkleCacheEntry)

# ─── Index Management ───────────────────────────────────────────────────────

func rebuildSymbolIndex*(engine: var MerkleQueryEngine) {.raises: [].} =
  ## Rebuild symbolToFiles reverse index from fileCache.
  engine.symbolToFiles.clear()
  for filePath, entry in engine.fileCache:
    for symName in entry.symbolNames:
      engine.symbolToFiles.mgetOrPut(symName, @[]).add(filePath)

# ─── Merkle Root ────────────────────────────────────────────────────────────

proc computeMerkleRoot*(engine: var MerkleQueryEngine): string {.raises: [].} =
  ## Compute Merkle root over all file content hashes.
  ## Sorted file paths ensure determinism across platforms.
  var hashes: seq[string] = @[]
  for filePath, entry in engine.fileCache:
    hashes.add(filePath & ":" & entry.contentHash)
  hashes.sort()
  if hashes.len == 0:
    return ""
  # Build Merkle tree by pairwise hashing
  var current = hashes
  while current.len > 1:
    var next: seq[string] = @[]
    var i = 0
    while i < current.len:
      if i + 1 < current.len:
        next.add(sha256Hex(current[i] & current[i + 1]))
      else:
        next.add(sha256Hex(current[i]))
      i += 2
    current = next
  current[0]

# ─── JSON Persistence ───────────────────────────────────────────────────────

func entryToJson(entry: MerkleCacheEntry): JsonNode {.raises: [].} =
  var symbolsArray = newJArray()
  for sym in entry.cachedSymbols:
    symbolsArray.add(%*{
      "modulePath": sym.modulePath,
      "functionName": sym.functionName,
      "nodeType": sym.nodeType,
      "nodeIdStr": sym.nodeIdStr,
      "declarationLine": sym.declarationLine,
      "bodyStartLine": sym.bodyStartLine,
      "bodyEndLine": sym.bodyEndLine,
      "exported": sym.exported,
      "boundaryKind": sym.boundaryKind,
      "rawCallTargets": sym.rawCallTargets,
      "branchCount": sym.branchCount,
      "nestingDepth": sym.nestingDepth,
      "lineSpan": sym.lineSpan,
      "hasAxiomImpl": sym.hasAxiomImpl,
      "definitionFingerprint": sym.definitionFingerprint
    })
  %*{
    "contentHash": entry.contentHash,
    "cstHash": entry.cstHash,
    "symbolNames": entry.symbolNames,
    "lastModified": entry.lastModified,
    "cachedSymbols": symbolsArray
  }

proc jsonToEntry(node: JsonNode): Option[MerkleCacheEntry] {.raises: [],
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deserialize one cache entry from JSON.
  ## Required fields (must be present with the correct kind, else entry is invalid):
  ##   contentHash (JString), cstHash (JString), lastModified (JInt)
  ## Optional fields (defaults when absent):
  ##   symbolNames (JArray of JString), cachedSymbols (JArray of JObject)
  ## Per-symbol required fields: modulePath, functionName, nodeType, nodeIdStr,
  ##   declarationLine, bodyStartLine, bodyEndLine, exported, boundaryKind,
  ##   branchCount, nestingDepth, lineSpan, hasAxiomImpl.
  ## Per-symbol optional: rawCallTargets (JArray of JString).
  ## Any structural violation (nil/missing/wrong-kind on a required field) → none.
  try:
    if node.isNil or node.kind != JObject:
      return none(MerkleCacheEntry)
    var entry: MerkleCacheEntry
    let ch = node{"contentHash"}
    if ch.isNil or ch.kind != JString:
      return none(MerkleCacheEntry)
    entry.contentHash = ch.getStr()
    let csh = node{"cstHash"}
    if csh.isNil or csh.kind != JString:
      return none(MerkleCacheEntry)
    entry.cstHash = csh.getStr()
    let lm = node{"lastModified"}
    if lm.isNil or lm.kind != JInt:
      return none(MerkleCacheEntry)
    entry.lastModified = lm.getInt()
    let sn = node{"symbolNames"}
    if not sn.isNil and sn.kind == JArray:
      for s in sn:
        if s.isNil or s.kind != JString:
          return none(MerkleCacheEntry)
        entry.symbolNames.add(s.getStr())
    let cs = node{"cachedSymbols"}
    if not cs.isNil and cs.kind == JArray:
      for s in cs:
        if s.isNil or s.kind != JObject:
          return none(MerkleCacheEntry)
        let mp = s{"modulePath"}
        if mp.isNil or mp.kind != JString: return none(MerkleCacheEntry)
        let fn = s{"functionName"}
        if fn.isNil or fn.kind != JString: return none(MerkleCacheEntry)
        let nt = s{"nodeType"}
        if nt.isNil or nt.kind != JString: return none(MerkleCacheEntry)
        let nid = s{"nodeIdStr"}
        if nid.isNil or nid.kind != JString: return none(MerkleCacheEntry)
        let dl = s{"declarationLine"}
        if dl.isNil or dl.kind != JInt: return none(MerkleCacheEntry)
        let bs = s{"bodyStartLine"}
        if bs.isNil or bs.kind != JInt: return none(MerkleCacheEntry)
        let be = s{"bodyEndLine"}
        if be.isNil or be.kind != JInt: return none(MerkleCacheEntry)
        let ex = s{"exported"}
        if ex.isNil or ex.kind != JBool: return none(MerkleCacheEntry)
        let bk = s{"boundaryKind"}
        if bk.isNil or bk.kind != JInt: return none(MerkleCacheEntry)
        let br = s{"branchCount"}
        if br.isNil or br.kind != JInt: return none(MerkleCacheEntry)
        let nd = s{"nestingDepth"}
        if nd.isNil or nd.kind != JInt: return none(MerkleCacheEntry)
        let ls = s{"lineSpan"}
        if ls.isNil or ls.kind != JInt: return none(MerkleCacheEntry)
        let ai = s{"hasAxiomImpl"}
        if ai.isNil or ai.kind != JBool: return none(MerkleCacheEntry)
        let rct = s{"rawCallTargets"}
        var targets: seq[string] = @[]
        if not rct.isNil and rct.kind == JArray:
          for t in rct:
            if t.isNil or t.kind != JString:
              return none(MerkleCacheEntry)
            targets.add(t.getStr())
        let df = s{"definitionFingerprint"}
        var defFingerprint = ""
        if not df.isNil and df.kind == JString:
          defFingerprint = df.getStr()
        entry.cachedSymbols.add(CachedTopologySymbol(
          modulePath: mp.getStr(),
          functionName: fn.getStr(),
          nodeType: nt.getStr(),
          nodeIdStr: nid.getStr(),
          declarationLine: dl.getInt(),
          bodyStartLine: bs.getInt(),
          bodyEndLine: be.getInt(),
          exported: ex.getBool(),
          boundaryKind: bk.getInt(),
          branchCount: br.getInt(),
          nestingDepth: nd.getInt(),
          lineSpan: ls.getInt(),
          hasAxiomImpl: ai.getBool(),
          rawCallTargets: targets,
          definitionFingerprint: defFingerprint
        ))
    some(entry)
  except CatchableError as e:
    logError("jsonToEntry: " & e.msg)
    none(MerkleCacheEntry)

proc loadCache*(path: string): Result[MerkleQueryEngine, AxiomError] {.raises: [],
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load the Merkle topology cache from disk.
  ##
  ## Outcome contract (fail-closed, never SIGSEGV):
  ##   * absent/unreadable file  → ok(empty engine)      — cold start, silent
  ##   * valid cache             → ok(populated engine)  — as before
  ##   * malformed/corrupt cache → err(parseError)        — recoverable: caller
  ##       cold-starts (fresh MerkleQueryEngine) and rebuilds the cache on save.
  ## The persisted cache is disposable derived state: corrupt = regenerate.
  ##
  ## Strictest sound semantics: any structural violation (root not JObject,
  ## missing/malformed 'files' object, or a single invalid cache entry) makes the
  ## whole cache invalid. There is no partial-load path that silently drops
  ## entries — invalid → err → rebuild from source.
  let readRes = readFileOpt(path)
  if readRes.isErr:
    # Absent file → cold start with an empty engine (recoverable, not an error).
    return ok(MerkleQueryEngine())
  try:
    let node = parseJson(readRes.get)
    if node.isNil or node.kind != JObject:
      return err(parseError("loadCache: root not JObject: " & path))
    let root = node
    var engine = MerkleQueryEngine()
    let filesNode = root{"files"}
    if filesNode.isNil or filesNode.kind != JObject:
      return err(parseError("loadCache: missing or malformed 'files' object: " & path))
    for key, entryNode in filesNode.fields:
      let optEntry = jsonToEntry(entryNode)
      if optEntry.isSome:
        engine.fileCache[key] = optEntry.get
      else:
        # Structural violation in one entry → whole-cache invalid (recoverable).
        return err(parseError("loadCache: invalid cache entry '" & key & "' in: " & path))
    rebuildSymbolIndex(engine)
    let mr = root{"merkleRoot"}
    if not mr.isNil and mr.kind == JString:
      engine.merkleRoot = mr.getStr()
    ok(engine)
  except CatchableError as e:
    err(parseError("loadCache(" & path & "): " & e.msg))

proc saveCache*(engine: MerkleQueryEngine; path: string): Result[void, AxiomError] {.raises: [],
  axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    var filesObj = newJObject()
    for filePath, entry in engine.fileCache:
      filesObj[filePath] = entryToJson(entry)
    let root = %*{"files": filesObj, "merkleRoot": engine.merkleRoot}
    let tmpPath = path & ".tmp"
    let writeRes = writeFileOpt(tmpPath, pretty(root))
    if writeRes.isErr:
      return err(ioError("saveCache write: " & writeRes.error))
    let moveRes = moveFileOpt(tmpPath, path)
    if moveRes.isErr:
      return err(ioError("saveCache move: " & moveRes.error))
    Result[void, AxiomError](ok: true)
  except CatchableError as e:
    err(ioError("saveCache(" & path & "): " & e.msg))

{.pop.}
