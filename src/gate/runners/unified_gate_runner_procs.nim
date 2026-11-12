## unified_gate_runner_procs
## Composition root — includes split sub-modules and defines entry procs.
## Public API preserved: all procs remain exported from this module.

import core/trusted/layer_declaration
axiomLayer "gate"
import std/os
import std/strformat
import std/json
import std/monotimes
import compiler/ast
import core/axiom_pragmas
import infrastructure/logging_facade
import unified_gate_runner_types

# ─── Included sub-modules ──────────────────────────────────────────────────
# Textually pasted via Nim `include`. All symbols share the same module scope
# and see the imports above. Ordering matters: helpers before scanners.

include unified_gate_runner_procs_helpers
include unified_gate_runner_procs_scanners

# ─── Main Entry Point ──────────────────────────────────────────────────────

proc runUnifiedGate*(files: seq[string]; layerDag: LayerDag = nil;
                     useCache: bool = true): GateResult {.raises: [CatchableError], axiomEffect: IOEffect.} =
  ## Main entry point: run all four check layers on the given files.
  ## Returns a GateResult with violations and pass/fail status.
  ## When useCache is true, uses SHA-256 content hashing for incremental skips.
  var allViolations: seq[Violation]
  var processedCount = 0
  var cacheHits = 0
  var cacheMisses = 0

  ## Load forbidden tokens from the registry
  var tokenRules: seq[ForbiddenTokenRule]
  let tokenPath = "src/gate/forbidden_tokens.json"
  try:
    if fileExists(tokenPath):
      let content = readFile(tokenPath)
      let json = parseJson(content)
      tokenRules = parseForbiddenTokens(json)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  ## Load incremental cache
  let gateCache = if useCache: loadCache(DefaultCachePath)
                  else: newJObject()

  ## Compute tokens hash for cache invalidation
  var tokensHash = ""
  if useCache and fileExists(tokenPath):
    try:
      tokensHash = computeFileHash(tokenPath)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  ## Invalidate cache if forbidden_tokens.json or schema version changed
  if useCache:
    let prevHash = gateCache{"tokensHash"}.getStr("")
    let prevVersion = gateCache{"version"}.getInt(0)
    if prevVersion != CacheVersion or (prevHash.len > 0 and prevHash != tokensHash):
      invalidateCache(gateCache)
    gateCache["tokensHash"] = %tokensHash
    gateCache["version"] = %CacheVersion

  for filePath in files:
    if not filePath.endsWith(".nim"):
      continue
    inc processedCount

    ## Compute file content hash for cache lookup
    var fileHash = ""
    if useCache:
      try:
        fileHash = computeFileHash(filePath)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)

    ## Cache hit: skip Gate 1+2, use cached result
    if useCache and fileHash.len > 0:
      let filesNode = gateCache{"files"}
      if filesNode != nil and filesNode.kind == JObject:
        let cached = filesNode{fileHash}
        if cached != nil and cached.kind == JObject:
          inc cacheHits
          let cachedViolations = cached{"violations"}
          if cachedViolations != nil and cachedViolations.kind == JArray:
            for jv in cachedViolations:
              allViolations.add(Violation(
                file: jv{"file"}.getStr(filePath),
                line: jv{"line"}.getInt(0),
                column: jv{"column"}.getInt(0),
                rule: jv{"rule"}.getStr(""),
                severity: jv{"severity"}.getStr(""),
                message: jv{"message"}.getStr(""),
              ))
          continue

    ## Cache miss — run full scan
    inc cacheMisses

    ## Parse file to AST
    var ast: PNode
    try:
      ast = parseFileToAst(filePath)
    except CatchableError:
      continue

    if ast == nil:
      continue

    var fileViolations: seq[Violation]

    ## SA-2.1: Layer boundary verification
    try:
      fileViolations.add(verifyLayerBoundaries(ast, filePath, layerDag))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    ## SA-2.2: AST complexity check
    try:
      fileViolations.add(calculateAstWeight(ast, filePath))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    ## SA-2.3: Forbidden token scan
    try:
      fileViolations.add(scanForbiddenTokens(ast, filePath, tokenRules))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    ## SA-2.4: Result error type scan
    try:
      fileViolations.add(scanResultErrorTypes(ast, filePath))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

    allViolations.add(fileViolations)

    ## Store result in cache
    if useCache and fileHash.len > 0:
      var hasFileBlocking = false
      for v in fileViolations:
        if v.severity in ["critical", "high"]:
          hasFileBlocking = true
          break
      var jFileViolations = newJArray()
      for v in fileViolations:
        var jv = newJObject()
        jv["file"] = %v.file
        jv["line"] = %v.line
        jv["column"] = %v.column
        jv["rule"] = %v.rule
        jv["severity"] = %v.severity
        jv["message"] = %v.message
        jFileViolations.add(jv)
      var entry = newJObject()
      entry["result"] = %(if hasFileBlocking: "fail" else: "pass")
      entry["violations"] = jFileViolations
      entry["timestamp"] = %($int64(epochTime()))
      if gateCache{"files"} == nil or gateCache{"files"}.kind != JObject:
        gateCache["files"] = newJObject()
      gateCache{"files", fileHash} = entry

  ## Persist cache to disk
  if useCache:
    saveCache(DefaultCachePath, gateCache)

  ## Determine pass/fail — any critical or high severity = fail
  var hasBlocking = false
  for v in allViolations:
    if v.severity in ["critical", "high"]:
      hasBlocking = true
      break

  ## Build JSON output
  var jViolations = newJArray()
  for v in allViolations:
    var jv = newJObject()
    jv["file"] = %v.file
    jv["line"] = %v.line
    jv["column"] = %v.column
    jv["rule"] = %v.rule
    jv["severity"] = %v.severity
    jv["message"] = %v.message
    jViolations.add(jv)

  var jOutput = newJObject()
  jOutput["gate"] = %"unified-gate-runner"
  jOutput["totalFiles"] = %processedCount
  jOutput["totalViolations"] = %allViolations.len
  jOutput["cacheHits"] = %cacheHits
  jOutput["cacheMisses"] = %cacheMisses
  jOutput["violations"] = jViolations

  let stdoutJson =
    try: $jOutput.pretty()
    except CatchableError: "{}"

  let cacheInfo = if useCache: fmt" (cache: {cacheHits}h/{cacheMisses}m)" else: ""
  let stderrText =
    if hasBlocking:
      var lines: seq[string]
      for v in allViolations:
        if v.severity in ["critical", "high"]:
          lines.add(fmt"  [{v.severity.toUpperAscii}] {v.rule}: {v.file}:{v.line} {v.message}")
      fmt"{GateTag} FAIL — {allViolations.len} violation(s):\n" & lines.join("\n")
    elif allViolations.len > 0:
      fmt"{GateTag} PASS — {allViolations.len} warning(s){cacheInfo}"
    else:
      fmt"{GateTag} PASS — {processedCount} files scanned, no violations{cacheInfo}"

  result = GateResult(
    ok: not hasBlocking,
    violations: allViolations,
    stdout: stdoutJson,
    stderr: stderrText,
  )

# ─── CLI Entry Point ───────────────────────────────────────────────────────

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var files: seq[string]
  var useCache = true

  for i in 1 .. paramCount():
    let arg = paramStr(i)
    if arg == "--no-cache":
      useCache = false
    elif arg.endsWith(".nim"):
      files.add(arg)

  ## If no files passed, scan entire src/ directory
  if files.len == 0:
    for path in walkDirRec("src"):
      if path.endsWith(".nim"):
        files.add(path)

  let t0Ticks = getMonoTime().ticks
  let res = runUnifiedGate(files, useCache = useCache)
  let elapsedMs = (getMonoTime().ticks - t0Ticks) div 1_000_000

  if elapsedMs > 500:
    logInfo("unified_gate_runner", $(GateTag) & " [PERF] unified-gate took " & $(elapsedMs) & "ms (threshold: 500ms)")

  logInfo("unified_gate_runner", $(GateTag) & " " & $(res.stderr))
  quit(if res.ok: 0 else: 1)

