import core/trusted/layer_declaration
axiomLayer "gate"
import core/axiom_pragmas
import core/gate/gate_vfs
import core/utils/file_utils
import core/audit/sad_gate
import infrastructure/logger
import std/[json, options, os, strutils, times]
import infrastructure/logging_facade
import gate/cache/soundness_cache_types
import gate/cache/soundness_cache_io


# axiomIoBoundary

# Merged from hotspot-enforcement-gate
const
  SkipOverridePath = OverrideConfigPath
  AuditLogPath = "data/hardening_audit.jsonl"

type
  BreakGlassOverride = object
    skipEnforcement: bool
    reason: string
    expires: string
    appliedBy: string

proc readBreakGlassOverride(): BreakGlassOverride =
  result = BreakGlassOverride()
  if not fileExists(SkipOverridePath): return
  var content = ""
  try: content = readFile(SkipOverridePath)
  except CatchableError: return
  var node: JsonNode
  try: node = parseJson(content)
  except CatchableError: return
  let seNode = node.getOrDefault("skip_enforcement")
  result.skipEnforcement = seNode != nil and seNode.getBool(false)
  let rnNode = node.getOrDefault("reason")
  result.reason = if rnNode != nil: rnNode.getStr("") else: ""
  let exNode = node.getOrDefault("expires")
  result.expires = if exNode != nil: exNode.getStr("") else: ""
  let abNode = node.getOrDefault("applied_by")
  result.appliedBy = if abNode != nil: abNode.getStr("unknown") else: "unknown"

proc isOverrideNotExpired(expires: string): bool =
  if expires.len == 0: return true
  try:
    let expiryDate = parse(expires, "yyyy-MM-dd")
    result = now() <= expiryDate
  except CatchableError: result = false

proc logBreakGlassAudit(override: BreakGlassOverride) =
  let logDir = AuditLogPath.parentDir
  if not dirExists(logDir):
    try: createDir(logDir)
    except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  var entry = newJObject()
  entry["timestamp"] = %now().format("yyyy-MM-dd'T'HH:mm:ss")
  entry["gate"] = %"hotspot-gate"
  entry["event"] = %"break-glass-skip"
  entry["reason"] = %override.reason
  entry["applied_by"] = %override.appliedBy
  entry["expires"] = %override.expires
  try:
    let f = open(AuditLogPath, fmAppend)
    f.writeLine($entry)
    f.close()
  except CatchableError: discard  # axiom:best-effort(ioboundary catch)

# Soundness cache check (§0.9 Theater fix — verify pass/fail status)
proc hotspotGateAlreadyPassed(repoRoot: string): bool {.axiomEffect: IOEffect.} =
  let cachePath = repoRoot / ".axiom" / "cache" / "hotspot_soundness.json"
  let sourceHash = computeProjectSourceHash(repoRoot)
  let soundnessCache = loadAndValidateCache(cachePath)
  let cachedStatus = lookupSoundnessCache(soundnessCache, "hotspot-gate", sourceHash)

  if cachedStatus.isNone():
    result = false  ## Cache miss — must run scan
  elif cachedStatus.get() == gvsPass:
    result = true   ## Cache hit with PASS — skip scan
  else:
    result = false  ## Cache hit with FAIL — MUST re-run scan (fail-closed)

const
  NestingThreshold = 4       ## Indentation depth indicating deep nesting
  LineThreshold = 80         ## Lines per proc/func considered overly long
  BranchThreshold = 10       ## Max case/of or if/elif branches before flag
  SrcDir = "src"
  BaselineMaxBytes = 1_048_576  ## 1 MiB hard cap for baseline file
type
  HotspotResult = tuple[path: string; category: string; detail: string]
  CachedFile = tuple[path: string; content: string]
proc cacheFileContents(files: seq[string]): seq[CachedFile] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  for path in files:
    let content = readFileSafe(path)
    if content.len > 0:
      result.add((path, content))
func cmpHotspot(a, b: HotspotResult): int {.raises: [].} =
  result = cmp(a.path, b.path)
  if result == 0:
    result = cmp(a.category, b.category)
proc relativePathSafe(path, base: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    result = relativePath(path, base)
  except CatchableError:
    result = path
proc getFilesToScan(repoRoot: string; files: seq[string]): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  if files.len == 0:
    let srcPath = repoRoot / SrcDir
    try:
      for path in walkDirRec(srcPath):
        if path.endsWith(".nim"):
          result.add(path)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  else:
    for f in files:
      if f.endsWith(".nim"):
        let path = repoRoot / f
        try:
          if fileExists(path):
            result.add(path)
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
func measureIndent(line: string): int {.raises: [].} =
  ## Count leading whitespace (spaces) as indentation depth.
  result = 0
  for ch in line:
    if ch == ' ':
      inc result
    elif ch == '\t':
      result += 2
    else:
      break
func isProcOrFuncStart(line: string): bool {.raises: [].} =
  let stripped = line.strip()
  result = stripped.startsWith("proc ") or
           stripped.startsWith("func ") or
           stripped.startsWith("method ")
proc scanNestingHotspots(cached: seq[CachedFile]; repoRoot: string): seq[HotspotResult] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  for (path, content) in cached:
    let relPath = relativePathSafe(path, repoRoot)
    var lineno = 1
    for line in content.splitLines():
      let depth = measureIndent(line)
      if depth >= NestingThreshold * 2:  # 2 spaces per level
        let stripped = line.strip()
        if stripped.len > 0 and not stripped.startsWith("#"):
          result.add((relPath, "deep-nesting", "L" & $lineno & " depth=" & $(depth div 2) & ": " & stripped[0 ..< min(60, stripped.len)]))
      inc lineno
proc scanLongProcedures(cached: seq[CachedFile]; repoRoot: string): seq[HotspotResult] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  for (path, content) in cached:
    let relPath = relativePathSafe(path, repoRoot)
    var inProc = false
    var procStart = 0
    var procName = ""
    var lineno = 1
    for line in content.splitLines():
      if isProcOrFuncStart(line):
        inProc = true
        procStart = lineno
        let stripped = line.strip()
        let parenIdx = stripped.find('(')
        if parenIdx > 0:
          procName = stripped[5 ..< parenIdx].strip()
        else:
          procName = stripped[5 ..< min(40, stripped.len)].strip()
      elif inProc and line.strip().startsWith("return") and measureIndent(line) <= 2:
        let span = lineno - procStart
        if span > LineThreshold:
          result.add((relPath, "long-proc", procName & " (" & $span & " lines, L" & $procStart & "-L" & $lineno & ")"))
        inProc = false
      inc lineno
proc scanDenseBranching(cached: seq[CachedFile]; repoRoot: string): seq[HotspotResult] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  for (path, content) in cached:
    let relPath = relativePathSafe(path, repoRoot)
    var branchCount = 0
    var branchStart = 0
    var lineno = 1
    for line in content.splitLines():
      let stripped = line.strip()
      if stripped.startsWith("case ") or stripped.startsWith("if "):
        branchCount = 1
        branchStart = lineno
      elif (stripped.startsWith("of ") or stripped.startsWith("elif ") or stripped.startsWith("else:")) and branchCount > 0:
        inc branchCount
        if branchCount > BranchThreshold:
          result.add((relPath, "dense-branching", $branchCount & " branches starting at L" & $branchStart))
          branchCount = 0
      elif stripped.len > 0 and not stripped.startsWith("#") and measureIndent(line) <= 2:
        branchCount = 0
      inc lineno
proc loadBaseline*(path: string): JsonNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    let content = readFileSafe(path)
    if content.len == 0: return newJObject()
    if content.len > BaselineMaxBytes:
      logger.warn("[hotspot-gate] baseline exceeds 1 MiB; falling back to full scan")
      return newJObject()
    result = parseJson(content)
  except CatchableError:
    result = newJObject()
proc isNewHotspot*(baseline: JsonNode; relPath, category: string; currentCount: int): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let fileNode = baseline{"metrics"}{"hotspot"}{"byFile"}.getOrDefault(relPath)
  if fileNode == nil or fileNode.kind != JObject:
    return currentCount > 0
  let baselineCount = fileNode.getOrDefault(category).getInt(0)
  return currentCount > baselineCount
proc reportCategory(baseline: JsonNode; issues: seq[HotspotResult];
    category, label, emptyMsg: string;
    newCount: var int): int {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if issues.len > 0:
    # Check if ALL items are baseline (no new hotspots) — suppress verbose output
    var anyNew = false
    for item in issues:
      if isNewHotspot(baseline, item.path, category, 1):
        anyNew = true
        break
    if anyNew:
      logger.info label
      var baselineCount = 0
      for item in issues:
        if isNewHotspot(baseline, item.path, category, 1):
          logger.info "  🔴 " & item.path & ": " & item.detail
          inc newCount
        else:
          inc baselineCount
      if baselineCount > 0:
        logger.info("  ⏭️  " & $baselineCount & " item(s) at baseline (suppressed)")
      logger.info("")
    else:
      # All baseline — print summary only (suppresses 8000+ line output)
      logger.info label & " " & $issues.len & " item(s) all baseline.\n"
  else:
    logger.info emptyMsg & "\n"
  result = issues.len
proc runHotspotScan*(repoRoot: string; files: seq[string]; baselinePath: string  = ""): bool =
  let baseline = if baselinePath.len > 0: loadBaseline(baselinePath) else: newJObject()
  let filesToScan = getFilesToScan(repoRoot, files)
  let cached = cacheFileContents(filesToScan)
  logger.info("=== Hotspot Scan (" & $cached.len & " files) ===\n")
  var newCount = 0
  var total = 0
  inc total, reportCategory(baseline, scanNestingHotspots(cached, repoRoot),
    "deepNesting", "Deep nesting hotspots (depth >= " & $NestingThreshold & "):",
    "✅ No deep nesting hotspots.", newCount)
  inc total, reportCategory(baseline, scanLongProcedures(cached, repoRoot),
    "longProc", "Long procedures (>" & $LineThreshold & " lines):",
    "✅ No overly long procedures.", newCount)
  inc total, reportCategory(baseline, scanDenseBranching(cached, repoRoot),
    "denseBranching", "Dense branching (>" & $BranchThreshold & " branches):",
    "✅ No dense branching hotspots.", newCount)
  logger.info $repeat('=', 60)
  logger.info "Total hotspot items: " & $total
  if baselinePath.len > 0:
    logger.info "New hotspots (above baseline): " & $newCount
  result = newCount == 0
proc main()  =
  let args = commandLineParams()
  if args.len < 3:
    logInfo("hotspot_gate", "Usage: hotspot_gate <repoRoot> <mode> <maxJobs> [baselinePath] [files...]")
    quit(1)

  let repoRoot = args[0]

  # Merged from hotspot-enforcement: break-glass check
  let override = readBreakGlassOverride()
  if override.skipEnforcement and isOverrideNotExpired(override.expires):
    logBreakGlassAudit(override)
    logInfo("hotspot_gate", "Break-glass active: " & override.reason & " — skipping enforcement")
    quit(0)

  # Merged from hotspot-enforcement: enforcement radius via sad_gate
  let radius = calculateEnforcementRadius()
  let strictMode = radius >= 75
  logWarn("hotspot_gate", "Enforcement radius: " & $radius & "/100 — " & (if strictMode: "BLOCK" else: "WARN"))

  # Merged from hotspot-ratchet: memo cache check
  if hotspotGateAlreadyPassed(repoRoot):
    logger.info("[hotspot-gate] Already passed (memo cache hit), skipping redundant scan")
    quit(0)

  # 4th arg is optional baseline path (if it ends with .json or is empty)
  var baselinePath = ""
  var fileStart = 3
  if args.len > 3 and args[3].endsWith(".json"):
    baselinePath = args[3]
    fileStart = 4
  let files = if args.len > fileStart: args[fileStart .. ^1] else: @[]

  let passed = runHotspotScan(repoRoot, files, baselinePath)

  ## Persist soundness cache entry
  try:
    let cachePath = repoRoot / ".axiom" / "cache" / "hotspot_soundness.json"
    let sourceHash = computeProjectSourceHash(repoRoot)
    let entry = VerificationCacheEntry(
      schemaVersion: SoundnessCacheSchemaVersion,
      compositeLockHash: "",
      sourceHash: sourceHash,
      status: if passed: gvsPass else: gvsFail,
      timestamp: epochTime().float,
      gateId: "hotspot-gate"
    )
    saveCacheEntry(cachePath, entry)
  except CatchableError:
    discard

  if passed:
    logger.info("[hotspot-gate] PASS")
    quit(0)
  else:
    logger.info("[hotspot-gate] FAIL")
    quit(1)
func getFilesToScanVfs(ctx: GateContext; repoRoot: string; files: seq[string]): seq[string]  =
  ## VFS-aware version of getFilesToScan.
  result = @[]
  if files.len == 0:
    let srcPath = repoRoot / SrcDir
    let entries = vfsListDir(ctx, srcPath)
    for path in entries:
      if path.endsWith(".nim"):
        result.add(path)
  else:
    for f in files:
      if f.endsWith(".nim"):
        let path = repoRoot / f
        if vfsExists(ctx, path):
          result.add(path)
func cacheFileContentsVfs(ctx: GateContext; files: seq[string]): seq[CachedFile]  =
  ## VFS-aware version of cacheFileContents.
  result = @[]
  for path in files:
    let content = vfsReadOpt(ctx, path).get("")
    if content.len > 0:
      result.add((path, content))
proc loadBaselineVfs*(ctx: GateContext; path: string): JsonNode  =
  ## VFS-aware version of loadBaseline.
  try:
    let content = vfsReadOpt(ctx, path).get("")
    if content.len == 0: return newJObject()
    if content.len > BaselineMaxBytes:
      logger.warn("[hotspot-gate] baseline exceeds 1 MiB; falling back to full scan")
      return newJObject()
    result = parseJson(content)
  except CatchableError:
    result = newJObject()
proc runHotspotScanVfs*(ctx: GateContext; repoRoot: string; files: seq[string]; baselinePath: string  = ""): bool =
  ## VFS-aware version of runHotspotScan.
  let baseline = if baselinePath.len > 0: loadBaselineVfs(ctx, baselinePath) else: newJObject()
  let filesToScan = getFilesToScanVfs(ctx, repoRoot, files)
  let cached = cacheFileContentsVfs(ctx, filesToScan)
  logger.info("=== Hotspot Scan (" & $cached.len & " files) ===\n")
  var newCount = 0
  var total = 0
  inc total, reportCategory(baseline, scanNestingHotspots(cached, repoRoot),
    "deepNesting", "Deep nesting hotspots (depth >= " & $NestingThreshold & "):",
    "✅ No deep nesting hotspots.", newCount)
  inc total, reportCategory(baseline, scanLongProcedures(cached, repoRoot),
    "longProc", "Long procedures (>" & $LineThreshold & " lines):",
    "✅ No overly long procedures.", newCount)
  inc total, reportCategory(baseline, scanDenseBranching(cached, repoRoot),
    "denseBranching", "Dense branching (>" & $BranchThreshold & " branches):",
    "✅ No dense branching hotspots.", newCount)
  logger.info $repeat('=', 60)
  logger.info "Total hotspot items: " & $total
  if baselinePath.len > 0:
    logger.info "New hotspots (above baseline): " & $newCount
  result = newCount == 0
proc mainWithVfs*(ctx: GateContext)  =
  ## VFS-aware entry point.
  let args = commandLineParams()
  if args.len < 3:
    logInfo("hotspot_gate", "Usage: hotspot_gate <repoRoot> <mode> <maxJobs> [baselinePath] [files...]")
    quit(1)
  let repoRoot = args[0]
  var baselinePath = ""
  var fileStart = 3
  if args.len > 3 and args[3].endsWith(".json"):
    baselinePath = args[3]
    fileStart = 4
  let files = if args.len > fileStart: args[fileStart .. ^1] else: @[]
  let passed = runHotspotScanVfs(ctx, repoRoot, files, baselinePath)

  ## Persist soundness cache entry
  try:
    let cachePath = repoRoot / ".axiom" / "cache" / "hotspot_soundness.json"
    let sourceHash = computeProjectSourceHash(repoRoot)
    let entry = VerificationCacheEntry(
      schemaVersion: SoundnessCacheSchemaVersion,
      compositeLockHash: "",
      sourceHash: sourceHash,
      status: if passed: gvsPass else: gvsFail,
      timestamp: epochTime().float,
      gateId: "hotspot-gate"
    )
    saveCacheEntry(cachePath, entry)
  except CatchableError:
    discard

  if passed:
    logger.info("[hotspot-gate] PASS")
    quit(0)
  else:
    logger.info("[hotspot-gate] FAIL")
    quit(1)

when isMainModule:
  main()
