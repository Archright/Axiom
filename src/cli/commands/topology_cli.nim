import core/trusted/layer_declaration
axiomLayer "presentation"
import cli/commands/command_registry
import core/audit/burn_down_queue
import core/audit/hotspot_analyzer
import core/audit/hotspot_render
import core/parsers/safe_parsers
import core/results
import core/stdlib_shield
import core/topology/[policy, lock, explain, declaration, manifest, suggest, apply, lock_update]
import core/topology/gate_ops
import infrastructure/topology_executor
import std/[os, strutils, json]
import infrastructure/logging_facade
import core/axiom_pragmas
# axiomIoBoundary

# Re-export gate_ops procs so existing callers of topology_cli still work
export gate_ops

type
  AuditFormat* = enum
    afHuman, afJson
proc parseAuditFlags*(args: seq[string]; outFormat: var AuditFormat;
                      strict, apply, dryRun, verbose: var bool): bool {.raises: [system.IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  outFormat = afHuman
  strict = false
  apply = false
  dryRun = false
  verbose = false
  for i in 1..<args.len:
    let a = args[i]
    case a:
    of "--format":
      if i + 1 >= args.len:
        logError("topology_cli", "[ERROR] --format requires an argument (json|human)")
        return false
      let f = args[i + 1].toLowerAscii
      case f:
      of "json": outFormat = afJson
      of "human": outFormat = afHuman
      else:
        logError("topology_cli", "[ERROR] Unknown format: " & f)
        return false
    of "--strict": strict = true
    of "--apply", "--fix": apply = true
    of "--dry-run": dryRun = true
    of "--verbose": verbose = true
    else:
      if a.startsWith("-"):
        logError("topology_cli", "[ERROR] Unknown flag: " & a)
        return false
  result = true
proc parseGenerateManifestFlags*(args: seq[string]; outputPath: var string; dryRun: var bool): bool {.raises: [system.IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  outputPath = "topology.json"
  dryRun = false
  var i = 1
  while i < args.len:
    let a = args[i]
    case a:
    of "--output":
      if i + 1 >= args.len:
        logError("topology_cli", "[ERROR] --output requires an argument")
        return false
      outputPath = args[i + 1]
      inc i
    of "--dry-run":
      dryRun = true
    else:
      if a.startsWith("-"):
        logError("topology_cli", "[ERROR] Unknown flag: " & a)
        return false
    inc i
  result = true
# runTopologyCheck moved to core/topology/gate_ops (imported+exported above)
proc applySafeMoves*(auditRes: TopologyAuditResult; dryRun: bool): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var log: seq[string] = @[]
  for v in auditRes.violations:
    if v.suggestion.actionRequired != "auto_safe":
      continue
    if v.suggestion.confidence != "high":
      continue
    let src = v.suggestion.fromPath
    let dst = v.suggestion.toPath
    if src.len == 0 or dst.len == 0:
      continue
    if not fileExists(src):
      continue
    if fileExists(dst) or dirExists(dst):
      log.add("[SKIP] target already exists: " & dst)
      continue
    let dstDir = parentDir(dst)
    if not dirExists(dstDir):
      if not dryRun:
        createDir(dstDir)
    if dryRun:
      log.add("[WOULD MOVE] " & src & " -> " & dst)
    else:
      safeMoveFile(src, dst)
      log.add("[MOVED] " & src & " -> " & dst)
proc parseApplyFlags*(args: seq[string]; dryRun, autoApprove, force: var bool; filterExpr: var string): bool {.raises: [system.IOError].} =
  dryRun = false
  autoApprove = false
  force = false
  filterExpr = ""
  var i = 1
  while i < args.len:
    let a = args[i]
    case a:
    of "--dry-run": dryRun = true
    of "--auto-approve", "-y": autoApprove = true
    of "--force": force = true
    of "--filter":
      if i + 1 >= args.len:
        logError("topology_cli", "[ERROR] --filter requires an argument (domain or domain.subdomain)")
        return false
      filterExpr = args[i + 1]
      inc i
    else:
      if a.startsWith("-"):
        logError("topology_cli", "[ERROR] Unknown flag: " & a)
        return false
    inc i
  result = true
proc runTopologyAudit*(policyPath, lockPath, declPath: string; args: seq[string]): int {.raises: [].} =
  try:
    var fmt: AuditFormat
    var strict, apply, dryRun, verbose: bool
    if not parseAuditFlags(args, fmt, strict, apply, dryRun, verbose):
      return 2

    var auditRes = TopologyAuditResult(errors: 0, warnings: 0, infoCount: 0)

    # Declaration-driven audit (if topology.json exists)
    if fileExists(declPath):
      let declRes = parseTopologyDeclaration(declPath)
      if declRes.isErr:
        logError("topology_cli", declRes.error)
        return 1
      let lockRes = parseTopologyLock(lockPath)
      if lockRes.isErr:
        logError("topology_cli", lockRes.error)
        return 1
      auditRes = runDeclarationAudit(declRes.get, lockRes.get)
    else:
      # Fallback to policy-driven audit
      let policyRes = parseTopologyPolicy(policyPath)
      if policyRes.isErr:
        logError("topology_cli", policyRes.error)
        return 1
      let lockRes = parseTopologyLock(lockPath)
      if lockRes.isErr:
        logError("topology_cli", lockRes.error)
        return 1
      let auditResOpt = runTopologyAuditWithSuggestions(policyRes.get, lockRes.get)
      if auditResOpt.isErr:
        logError("topology_cli", auditResOpt.error)
        return 1
      auditRes = auditResOpt.get

    # Apply safe moves if requested
    var applyLog: seq[string] = @[]
    if apply:
      applyLog = applySafeMoves(auditRes, dryRun)

    # Determine exit code
    var exitCode = 0
    if auditRes.errors > 0:
      exitCode = 1
    if strict and auditRes.warnings > 0:
      exitCode = 1

    if fmt == afJson:
      let j = formatResultJson(auditRes)
      j{"summary"}["exit_code"] = %exitCode
      if apply:
        let applyArr = newJArray()
        for line in applyLog:
          applyArr.add(%line)
        j["apply_log"] = applyArr
      echo j.pretty
      return exitCode

    # Human format
    if auditRes.violations.len == 0:
      echo "[PASS] Topology audit: no policy drift detected."
    else:
      for v in auditRes.violations:
        if v.severity == seInfo and not verbose:
          continue
        echo formatSuggestionHuman(v)

    if applyLog.len > 0:
      echo ""
      echo "=== Apply Log ==="
      for line in applyLog:
        echo line

    echo ""
    echo "[SUMMARY] errors=" & $auditRes.errors &
         " warnings=" & $auditRes.warnings &
         " info=" & $auditRes.infoCount

    return exitCode
  except CatchableError:
    return 1
proc runTopologyApply*(declPath, lockPath: string; args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var dryRun, autoApprove, force: bool
  var filterExpr: string
  if not parseApplyFlags(args, dryRun, autoApprove, force, filterExpr):
    return 2
  if not fileExists(declPath):
    logError("topology_cli", "[ERROR] Declaration not found: " & declPath)
    return 2
  let declJson = safeReadFile(declPath)
  let declRes = parseTopologyDeclarationJson(declJson)
  if declRes.isErr:
    logError("topology_cli", declRes.error)
    return 2
  let decl = declRes.get
  var plan = computePlan(decl, "src")
  if filterExpr.len > 0:
    plan = filterPlan(plan, decl, filterExpr)
  echo formatPlan(plan)
  if dryRun and filterExpr.len == 0:
    let suggestions = suggestFilters(plan, decl)
    echo formatSuggestions(suggestions)
  let axPath = "./bin/ax"
  var res: TopologyExecutionResult
  try:
    res = executeTopologyApply(plan, dryRun, autoApprove, force, axPath, lockPath)
  except CatchableError as e:
    raise newException(CatchableError, "executeTopologyApply failed: " & e.msg)
  case res.kind:
  of terkSuccess:
    echo "\nApply complete."
    if lockPath.len > 0 and fileExists(lockPath):
      let lockJson = safeReadFile(lockPath)
      let lockRes = parseTopologyLockJson(lockJson)
      if lockRes.isOk:
        echo "[OK] topology.lock updated to revision ", lockRes.get.lockRevision
      else:
        logError("topology_cli", lockRes.error)
    return 0
  of terkDryRun:
    echo "\n(Dry run — no changes made.)"
    return 0
  of terkCancelled:
    if res.error.isSome:
      echo "\n", res.error.get
    return 1
  of terkValidationFailed:
    if res.error.isSome:
      echo "\nApply failed: ", res.error.get
    return 1
  of terkRollbackFailed:
    if res.error.isSome:
      echo "\nCRITICAL: Rollback failed. Manual recovery required. ", res.error.get
    return 2
proc runTopologyExplain*(targetPath, policyPath, lockPath: string): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let policyRes = parseTopologyPolicy(policyPath)
  if policyRes.isErr:
    logError("topology_cli", policyRes.error)
    return 1
  let lockRes = parseTopologyLock(lockPath)
  if lockRes.isErr:
    logError("topology_cli", lockRes.error)
    return 1
  echo generateExplanation(targetPath, policyRes.get, lockRes.get)
  return 0
proc runTopologyGenerateManifest*(args: seq[string]): int {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var outputPath: string
  var dryRun: bool
  if not parseGenerateManifestFlags(args, outputPath, dryRun):
    return 2

  let existingDeclPath = if fileExists("topology.json"): "topology.json" else: ""
  var decl = TopologyDeclaration()
  if existingDeclPath.len > 0:
    let declJson = safeReadFile(existingDeclPath)
    let declRes = parseTopologyDeclarationJson(declJson)
    if declRes.isErr:
      logError("topology_cli", declRes.error)
      return 1
    decl = declRes.get
  let files = plan.scanSourceFiles("src")
  let j = generateManifestJsonFromData(decl, files)
  if dryRun:
    echo j.pretty
  else:
    writeFile(outputPath, j.pretty)
    echo "[OK] Generated topology manifest: " & outputPath
  return 0
# runTopologySyncLock moved to core/topology/gate_ops (imported+exported above)
proc runTopologyHotspot*(args: seq[string]): int {.raises: [CatchableError].} =
  var sinceDays = 30
  var topN = 20
  var fmt = rfTTY
  var i = 1
  while i < args.len:
    let arg = args[i]
    if arg.startsWith("--since="):
      sinceDays = safeParseInt(arg[8..^1]).getOrDefault(30)
    elif arg == "--since" and i + 1 < args.len:
      sinceDays = safeParseInt(args[i + 1]).getOrDefault(30)
      inc i
    elif arg.startsWith("--top="):
      topN = safeParseInt(arg[6..^1]).getOrDefault(20)
    elif arg == "--top" and i + 1 < args.len:
      topN = safeParseInt(args[i + 1]).getOrDefault(20)
      inc i
    elif arg == "--json": fmt = rfJson
    elif arg == "--markdown" or arg == "--md": fmt = rfMarkdown
    inc i

  let churn = computeChurnScoresCached(sinceDays)
  let queue = buildPriorityQueue(churn, topN)
  case fmt
  of rfMarkdown: echo renderMarkdown(queue, sinceDays)
  of rfJson: echo renderJson(queue, sinceDays)
  of rfTTY: echo renderTTY(queue, sinceDays)
  return 0
# topologyPolicyPath, topologyLockPath, topologyDeclPath re-exported from core/topology/gate_ops
proc wrapTopologyCheck(args: seq[string]): int {.nimcall, raises: [].} =
  try: runTopologyCheck(topologyPolicyPath, topologyLockPath)
  except CatchableError: echo "Error: " & getCurrentExceptionMsg(); 1
proc wrapTopologyAudit(args: seq[string]): int {.nimcall, raises: [].} =
  try: runTopologyAudit(topologyPolicyPath, topologyLockPath, topologyDeclPath, args)
  except CatchableError: echo "Error: " & getCurrentExceptionMsg(); 1
proc wrapTopologyApply(args: seq[string]): int {.nimcall, raises: [].} =
  try: runTopologyApply(topologyDeclPath, topologyLockPath, args)
  except CatchableError: echo "Error: " & getCurrentExceptionMsg(); 1
proc wrapTopologyExplain(args: seq[string]): int {.nimcall, raises: [].} =
  if args.len < 2:
    echo "Usage: ax topology explain <path>"
    return 1
  try: runTopologyExplain(args[1], topologyPolicyPath, topologyLockPath)
  except CatchableError: echo "Error: " & getCurrentExceptionMsg(); 1
proc wrapTopologyGenerateManifest(args: seq[string]): int {.nimcall, raises: [].} =
  try: runTopologyGenerateManifest(args)
  except CatchableError: echo "Error: " & getCurrentExceptionMsg(); 1
proc wrapTopologySyncLock(args: seq[string]): int {.nimcall, raises: [].} =
  try: runTopologySyncLock(topologyLockPath, topologyPolicyPath, args)
  except CatchableError: echo "Error: " & getCurrentExceptionMsg(); 1
proc wrapTopologyHotspot(args: seq[string]): int {.nimcall, raises: [].} =
  try: runTopologyHotspot(args)
  except CatchableError: echo "Error: " & getCurrentExceptionMsg(); 1
func registerAllCommands(): CommandRegistry {.raises: [].} =
  result = @[]
  result.register("check", wrapTopologyCheck, "Validate topology against policy")
  result.register("audit", wrapTopologyAudit, "Audit with actionable suggestions")
  result.register("apply", wrapTopologyApply, "Apply safe moves")
  result.register("explain", wrapTopologyExplain, "Explain a module path")
  result.register("generate-manifest", wrapTopologyGenerateManifest, "Generate manifest")
  result.register("sync-lock", wrapTopologySyncLock, "Sync topology lock")
  result.register("hotspot", wrapTopologyHotspot, "Analyze hotspot churn")
proc main*(args: seq[string]): int =
  if args.len < 1:
    echo "Usage: ax topology <command> [args...]"
    echo ""
    let reg = registerAllCommands()
    for entry in reg:
      echo "  " & entry.name.alignLeft(20) & entry.description
    return 1
  let registry = registerAllCommands()
  return registry.dispatch(args[0], args)

