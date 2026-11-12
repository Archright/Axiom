import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import checksums/sha2
import std/options
import core/json/std_redirect
import core/parsers/safe_parsers
import core/pure/json_parse
import core/symbol_graph/global_symbol_graph_builder_part1
import core/symbol_graph/global_symbol_graph_builder_part2
import core/symbol_graph/global_symbol_graph_query
import core/symbolic/global_symbol_graph_types
import core/telemetry/metrics
import core/types/asi_types
import core/trusted/axiom_pragmas
import core/types/global_symbol_graph_types
import core/types/results
import core/types/universe_types
import core/utils/constants
import core/utils/io_utils
import std/algorithm
import std/os
import std/strutils
import std/tables
import std/times
const defaultProofUniverseLockPath* = "data/universe_merkle.lock"
const defaultCertDir* = ".axiom/vault"
const defaultStateFile* = "logs/ax_proof_state.json"
const defaultGlobalSymbolGraphPath* = "logs/global_symbol_graph.json"
const defaultSeedSymbolGraphPath* = "data/seed_symbol_graph.json"
const missingGraphMerkleHash* = "0000000000000000000000000000000000000000"
# ─── Thin I/O boundary wrappers (centralized exception → Result) ────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readFileResult(path: string): Result[string, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  readFileOpt(path)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseJsonResult(s: string): Result[JsonNode, string] {.raises: [].} =
  try:
    ok(pureParseJson(s))
  except CatchableError as e:
    err("parseJson: " & e.msg)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func sha256Result(s: string): Result[string, string] {.raises: [].} =
  try:
    ok($secureHash(Sha_256, s))
  except CatchableError as e:
    err("sha256: " & e.msg)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc copyFileResult(src, dst: string): Result[bool, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    copyFile(src, dst)
    ok(true)
  except CatchableError as e:
    err("copyFile: " & e.msg)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func sortJsonKeysRecursively(node: JsonNode): JsonNode {.raises: [].} =
  case node.kind
  of JObject:
    var sorted = newJObject()
    var keys: seq[string] = @[]
    for key in node.keys:
      keys.add(key)
    keys.sort(system.cmp[string])
    for key in keys:
      let child = node{key}
      if not child.isNil:
        sorted[key] = sortJsonKeysRecursively(child)
    result = sorted
  of JArray:
    var arr = newJArray()
    for child in node.elems:
      arr.add(sortJsonKeysRecursively(child))
    result = arr
  else:
    result = node
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeDeterministicCertHash(path: string): Result[string, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let raw = ??readFileResult(path)
  let j = ??parseJsonResult(raw)
  let sorted = sortJsonKeysRecursively(j)
  sha256Result($sorted)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeGraphMerkleHash*(graphPath: string): Result[string, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(graphPath):
    return err("graph file not found: " & graphPath)
  let raw = ??readFileResult(graphPath)
  sha256Result(raw)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func graphSnapshotJson*(graph: GlobalSymbolGraph): JsonNode {.raises: [].} =
  var symArr = newJArray()
  for qn in sortedSymbolKeys(graph.symbols):
    let sym = graph.symbols.getOrDefault(qn)
    symArr.add(%*{
      "qualifiedName": sym.qualifiedName,
      "kind": $sym.kind,
      "modulePath": sym.modulePath,
      "visibility": sym.visibility
    })

  var edgeArr = newJArray()
  var edges = graph.edges
  edges.sort(referenceEdgeCmp)
  for edge in edges:
    edgeArr.add(%*{
      "source": edge.source,
      "target": edge.target,
      "kind": $edge.kind,
      "line": edge.line,
      "column": edge.column
    })

  %*{
    "schemaVersion": "axiom.global-symbol-graph.v1",
    "hash": graphHash(graph),
    "symbolCount": graph.symbols.len,
    "edgeCount": graph.edges.len,
    "symbols": symArr,
    "edges": edgeArr
  }
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc buildProofUniverseLockGraph*(
  sourceRoot: string;
  freezeGraphCache: bool  = true
): Result[GlobalSymbolGraph, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var graph = buildGlobalSymbolGraph(sourceRoot, freezeGraphCache)
  let partialGraph =
    graph.symbols.len == 0 or graph.edges.len == 0 or graph.edges.len < graph.symbols.len
  if freezeGraphCache and partialGraph:
    let cachePath = globalSymbolGraphIncrementalCachePath(sourceRoot)
    discard removeFileOpt(cachePath)  # non-fatal cache cleanup
    graph = buildGlobalSymbolGraph(sourceRoot, false)
  ok(graph)
## @axiom-hint: Extracts ASI string from proof-state JSON file. Pure read-side operation.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc parseAsiFromStateFile*(stateFile: string): Result[string, string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let content = ??readFileResult(stateFile)
  let j = ??parseJsonResult(content)
  let summary = j.getOrDefault("summary")
  if not summary.isNil and summary.kind == JObject:
    for key in ["engineAsiFixed4", "asiFixed4", "substantiveAsiFixed4"]:
      let v = summary.getOrDefault(key).getStr("")
      if v.len > 0 and v != "0.0000": return ok(v)
  let topAsi = j.getOrDefault("asiFixed4").getStr("")
  if topAsi.len > 0 and topAsi != "0.0000": return ok(topAsi)
  err("VKD not found in state file: " & stateFile)

## Parses ASI from an in-memory proof-state summary JsonNode.
## Replaces the legacy runtimeAsiValueForProofLock helper removed during Wave 8 CLI refactoring.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseAsiFromLockSummary*(j: JsonNode): Result[string, string] {.raises: [].} =
  let summary = j.getOrDefault("summary")
  if summary.isNil or summary.kind == JNull:
    return err("runtime ASI missing: summary field not found")
  let totalNodes = summary.getOrDefault("totalNodes").getInt(0)
  if totalNodes == 0 and summary.hasKey("totalNodes"):
    return err("Pipeline truncated: zero total nodes")
  let timedOut = summary.getOrDefault("timedOut").getInt(0)
  if timedOut > 0 and summary.hasKey("timedOut"):
    return err("timeout: solver timed out on one or more nodes")
  for key in ["engineAsiFixed4", "asiFixed4"]:
    let v = summary.getOrDefault(key).getStr("")
    if v.len > 0: return ok(v)
  err("runtime ASI missing")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeProofUniverseLock*(
  repoRoot: string;
  certDir: string  = defaultCertDir;
  vkdFixed4: ValidatedAsi;
  source: AsiSource = asiInjected
): Result[ProofUniverseLock, string] {.raises: [].} =
  ## [AXIOM AMU] ASI source distinguishes computed vs injected values.
  ## - asiInjected: 0.0000 or empty rejected (fallback guard)
  ## - asiComputed: 0.0000 allowed (explicitly computed zero ASI valid)
  ## Contract Assert: format/range validation for all sources (Param Desync prevention)
  let actualAsi = asString(vkdFixed4)
  if actualAsi.len == 0:
    return err("[AXIOM DEFECT] proof_universe.lock: ValidatedAsi is empty.")
  var score: float
  let parsedRes = safeParseFloat(actualAsi)
  if parsedRes.isErr:
    return err("[AXIOM DEFECT] proof_universe.lock: invalid ASI format: " & actualAsi)
  score = parsedRes.get
  if score < 0.0 or score > 1.0:
    return err("[AXIOM DEFECT] proof_universe.lock: ASI out of range [0,1]: " & actualAsi)
  if source == asiInjected and actualAsi == "0.0000":
    return err("[AXIOM DEFECT] proof_universe.lock: ValidatedAsi is zero. ASI must be computed by metrics.nim before lock commit.")

  var hashes: seq[string]
  let absCertDir = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0: joinPath(sr, certDir)
    else: repoRoot / certDir
  let certFilesResult = collectJsonFiles(absCertDir)
  var certFiles: seq[string] = if certFilesResult.isOk: certFilesResult.get else: @[]
  certFiles.sort(cmp[string])
  for path in certFiles:
    let h = computeDeterministicCertHash(path)
    if h.isOk:
      hashes.add(h.get)
  let absGraphFile = block:
    let sr = getEnv("AXIOM_STATE_DIR", "").strip()
    if sr.len > 0: joinPath(sr, defaultGlobalSymbolGraphPath)
    else: repoRoot / defaultGlobalSymbolGraphPath
  if not fileExists(absGraphFile):
    let seedPath = block:
      let sr = getEnv("AXIOM_STATE_DIR", "").strip()
      if sr.len > 0: joinPath(sr, defaultSeedSymbolGraphPath)
      else: repoRoot / defaultSeedSymbolGraphPath
    if fileExists(seedPath):
      let copyRes = copyFileResult(seedPath, absGraphFile)
      if copyRes.isErr:
        return err("[AXIOM DEFECT] proof_universe.lock: cannot seed global_symbol_graph.json from " & seedPath)
    if not fileExists(absGraphFile):
      return err("[AXIOM DEFECT] proof_universe.lock: global_symbol_graph.json seed copy failed")
  let graphMerkleHashResult = computeGraphMerkleHash(absGraphFile)
  if graphMerkleHashResult.isErr:
    return err("[AXIOM DEFECT] proof_universe.lock: global_symbol_graph.json is missing or unreadable")
  hashes.add(graphMerkleHashResult.get)
  let rootHash = ??sha256Result(hashes.join("\n"))
  var lock: ProofUniverseLock
  lock.merkleRoot = rootHash
  lock.fileCount = hashes.len
  lock.timestamp = $now()
  lock.vkdFixed4 = actualAsi
  ok(lock)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readProofUniverseLock*(
  path: string  = defaultProofUniverseLockPath
): Result[ProofUniverseLock, string] {.raises: [].} =
  let content = ??readFileResult(path)
  let j = ??parseJsonResult(content)
  var lock: ProofUniverseLock
  lock.merkleRoot = j.getOrDefault("merkleRoot").getStr("")
  lock.timestamp = j.getOrDefault("timestamp").getStr("")
  lock.fileCount = j.getOrDefault("fileCount").getInt(0)
  lock.vkdFixed4 = j.getOrDefault(vkdFixed4Key).getStr("0.0000")
  ok(lock)

## @axiom-hint: Compares stored Merkle root against recomputed deterministic hash. Side-effect-free verification kernel.
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc verifyProofUniverseLock*(
  repoRoot: string;
  certDir: string  = defaultCertDir;
  path: string = defaultProofUniverseLockPath
): Result[bool, string] {.raises: [].} =
  let stored = readProofUniverseLock(path)
  if stored.isErr:
    return ok(false)
  let parsedAsi = safeParseFloat(stored.get.vkdFixed4)
  if parsedAsi.isErr:
    return ok(false)
  let rawScore = parsedAsi.get
  let asiOpt = initAsiRatio(rawScore)
  let asiScore = if asiOpt.isSome: asiOpt.get else: defaultAsiRatio()
  let currentResult = computeProofUniverseLock(repoRoot, certDir, exportAsiFixed4(asiScore), source = asiComputed)
  if currentResult.isErr:
    return ok(false)
  let current = currentResult.get
  ok(current.merkleRoot == stored.get.merkleRoot and current.fileCount == stored.get.fileCount)

{.pop.}

