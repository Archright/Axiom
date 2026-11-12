## Topology Suggestion Engine v2 — Declaration-Driven
## AGENTS.md Topology Contract §Phase C
## Replaces heuristic suggestions with topology.json declaration enforcement.
## Detects: ghost paths, unmapped files, location drift, unclassified files.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/results
import std/[json, os, strutils, tables, algorithm]
import core/topology/policy
import core/topology/lock
import core/topology/declaration
import core/trusted/stdlib_shield
import core/types/hubs/topology_hub
{.push raises: [].}
# axiomIoBoundary

type
  SuggestionSeverity* = enum
    seError, seWarning, seInfo

  SuggestionAction* = enum
    saMove, saShard, saMerge, saRegister, saRemove, saDefer

  Suggestion* = object
    action*: SuggestionAction
    severity*: SuggestionSeverity
    fromPath*: string
    toPath*: string
    rationale*: string
    confidence*: string
    actionRequired*: string

  TopologyAuditResult* = object
    errors*: int
    warnings*: int
    infoCount*: int
    violations*: seq[AuditViolation]

  AuditViolation* = object
    path*: string
    kind*: string
    severity*: SuggestionSeverity
    suggestion*: Suggestion

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func severityFromString*(s: string): SuggestionSeverity =
  case s.toLowerAscii:
  of "error": seError
  of "warning": seWarning
  else: seInfo

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func severityToString*(s: SuggestionSeverity): string =
  case s:
  of seError: "error"
  of seWarning: "warning"
  of seInfo: "info"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func actionToString*(a: SuggestionAction): string =
  case a:
  of saMove: "move"
  of saShard: "shard"
  of saMerge: "merge"
  of saRegister: "register"
  of saRemove: "remove"
  of saDefer: "defer"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func inAllowedPath*(filePath: string; domain, subdomain: string; decl: TopologyDeclaration): bool =
  if not decl.domains.hasKey(domain):
    return false
  let d = decl.domains.getOrDefault(domain)
  if d.description.len == 0 and d.level == 0:
    return false
  let sd = d.subdomains.getOrDefault(subdomain)
  if sd.paths.len == 0:
    return true  # no path constraint means any location is acceptable
  let actualDir = parentDir(filePath)
  for allowedRaw in sd.paths:
    let allowed = if allowedRaw.endsWith("/"): allowedRaw[0..^2] else: allowedRaw
    if actualDir == allowed or actualDir.startsWith(allowed & "/"):
      return true
  return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func locationDriftSeverity*(decl: TopologyDeclaration; domain: string): SuggestionSeverity =
  let lvl = effectiveLevel(decl, domain)
  if lvl >= 2:
    result = seError
  elif lvl == 1:
    result = seWarning
  else:
    result = seInfo

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func locationDriftSuggestion*(filePath, domain, subdomain: string; decl: TopologyDeclaration): Suggestion =
  let expectedBase = expectedPath(filePath, domain, subdomain, decl)
  let targetPath = if expectedBase.len > 0: expectedBase / extractFilename(filePath) else: ""
  let sev = locationDriftSeverity(decl, domain)
  result = Suggestion(
    action: saMove,
    severity: sev,
    fromPath: filePath,
    toPath: targetPath,
    rationale: "declared as " & domain & "/" & subdomain & " but not in allowed path",
    confidence: if targetPath.len > 0: "high" else: "medium",
    actionRequired: "manual_move_then_update_lock"
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runDeclarationAudit*(decl: TopologyDeclaration; lock: TopologyLock): TopologyAuditResult  =
  result = TopologyAuditResult(errors: 0, warnings: 0, infoCount: 0)

  # 1. Ghost paths: declared in topology.json but missing on disk
  for ghost in listGhostPaths(decl):
    let sug = Suggestion(
      action: saRemove,
      severity: seError,
      fromPath: ghost,
      toPath: "",
      rationale: "topology.json references ghost path (file no longer exists)",
      confidence: "high",
      actionRequired: "manual_remove_mapping"
    )
    result.violations.add(AuditViolation(
      path: ghost,
      kind: "ghost_path",
      severity: seError,
      suggestion: sug
    ))
    result.errors += 1

  # 2. Scan filesystem for unmapped/unclassified files and location drift
  let dirOk = try: safeDirExists("src") except CatchableError: false
  if dirOk:
    var files: seq[string] = @[]
    try:
      for path in safeWalkDirRec("src"):
        if path.endsWith(".nim"):
          files.add(path.relativePath("."))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    algorithm.sort(files)

    for relPath in files:
      if isForwardingStub(relPath):
        continue
      let (domain, subdomain, matchedBy) = classifyFile(relPath, decl)

      if matchedBy == "unmapped":
        let sug = Suggestion(
          action: saRegister,
          severity: seWarning,
          fromPath: relPath,
          toPath: "",
          rationale: "file is not declared in topology.json (unmapped)",
          confidence: "medium",
          actionRequired: "declare_in_topology_json"
        )
        result.violations.add(AuditViolation(
          path: relPath,
          kind: "unmapped_file",
          severity: seWarning,
          suggestion: sug
        ))
        result.warnings += 1
      else:
        if not inAllowedPath(relPath, domain, subdomain, decl):
          let sug = locationDriftSuggestion(relPath, domain, subdomain, decl)
          if sug.severity != seInfo:
            result.violations.add(AuditViolation(
              path: relPath,
              kind: "location_drift",
              severity: sug.severity,
              suggestion: sug
            ))
            if sug.severity == seError:
              result.errors += 1
            else:
              result.warnings += 1

# ---------------------------------------------------------------------------
# Legacy policy-driven audit — fallback when topology.json is absent.
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func suggestFromPolicyViolation*(v: Violation; policy: TopologyPolicy): AuditViolation =
  let (action, kind, sevStr) = case v.kind:
    of vkMissing: (saRegister, "lock_missing", "error")
    of vkOrphan: (saRemove, "lock_orphan", "error")
    of vkTransitionalExpired: (saMerge, "transitional_expired", "error")
    of vkOversized: (saShard, "oversized_directory", "warning")
    of vkSingleton: (saMove, "singleton_uncollapsed", "warning")
    of vkEmptyDir: (saDefer, "empty_directory", "warning")
    else: (saDefer, "unknown", "info")
  let sev = severityFromString(sevStr)
  let sug = Suggestion(
    action: action,
    severity: sev,
    fromPath: v.path,
    toPath: "",
    rationale: v.message,
    confidence: "high",
    actionRequired: if sev == seError: "manual_move_then_update_lock" else: "defer_to_human"
  )
  result = AuditViolation(path: v.path, kind: kind, severity: sev, suggestion: sug)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runTopologyAuditWithSuggestions*(policy: TopologyPolicy; lock: TopologyLock): Result[TopologyAuditResult, string] =
  var lockVios: seq[Violation]
  var ttlVios: seq[Violation]
  try:
    lockVios = checkLockCompliance(lock)
    ttlVios = checkTransitionalTTL(lock, policy.defaults.transitionalMaxAgeDays)
  except CatchableError as e:
    return err("topology audit I/O failure: " & e.msg & " — failing closed per §0.9")

  var audit = TopologyAuditResult(errors: 0, warnings: 0, infoCount: 0)
  for v in lockVios & ttlVios:
    if v.kind == vkOrphan and isForwardingStub(v.path):
      continue
    let av = suggestFromPolicyViolation(v, policy)
    audit.violations.add(av)
    if av.severity == seError: audit.errors += 1 else: audit.warnings += 1

  var dirCounts = initTable[string, int]()
  try:
    for root in safeWalkDirRec("src"):
      if not root.endsWith(".nim"): continue
      let dir = root.parentDir.relativePath(".")
      dirCounts[dir] = dirCounts.getOrDefault(dir, 0) + 1
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

  for dir, count in dirCounts:
    let limit = policy.getMaxDirectoryFiles(dir)
    if limit >= 0 and count > limit:
      let av = suggestFromPolicyViolation(Violation(
        kind: vkOversized, moduleId: "", path: dir,
        message: "directory has " & $count & " .nim files (limit " & $limit & ")"
      ), policy)
      audit.violations.add(av)
      audit.warnings += 1

  if policy.defaults.collapseSingletons:
    for dir, count in dirCounts:
      if count == 1 and not policy.isException(dir):
        var hasSubdirs = false
        try:
          for entry in safeWalkDirRec(dir):
            let rel = entry.relativePath(dir)
            if "/" in rel or "\\" in rel:
              hasSubdirs = true
              break
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
        if not hasSubdirs:
          let av = suggestFromPolicyViolation(Violation(
            kind: vkSingleton, moduleId: "", path: dir,
            message: dir & " is a singleton directory (1 .nim file, no subdirs)"
          ), policy)
          audit.violations.add(av)
          audit.warnings += 1

  if policy.defaults.forbidEmptyDirectories:
    try:
      for root in walkDirRec("src", yieldFilter = {pcDir}):
        let relRoot = root.relativePath(".")
        var hasContent = false
        for _ in walkDir(root, relative = true):
          hasContent = true
          break
        if not hasContent:
          let av = suggestFromPolicyViolation(Violation(
            kind: vkEmptyDir, moduleId: "", path: relRoot,
            message: relRoot & " is empty"
          ), policy)
          audit.violations.add(av)
          audit.warnings += 1
    except OSError: # axiom:best-effort(directory scan failure is non-fatal)
      discard
    except ValueError: # axiom:best-effort(invalid suggestion data skipped)
      discard
  ok(audit)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func formatSuggestionHuman*(v: AuditViolation): string =
  let label = case v.severity:
    of seError: "[ERROR]"
    of seWarning: "[WARN]"
    of seInfo: "[INFO]"
  result = label & " " & v.path & " (" & v.kind & ")\n"
  result.add("        Suggestion: " & actionToString(v.suggestion.action).toUpperAscii & " " & v.suggestion.fromPath)
  if v.suggestion.toPath.len > 0:
    result.add(" -> " & v.suggestion.toPath)
  result.add("\n")
  result.add("        Rationale: " & v.suggestion.rationale & "\n")
  result.add("        Confidence: " & v.suggestion.confidence & "\n")
  result.add("        Action: " & v.suggestion.actionRequired & "\n")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func formatResultJson*(r: TopologyAuditResult): JsonNode =
  let violations = newJArray()
  for v in r.violations:
    let sug = newJObject()
    sug["action"] = %actionToString(v.suggestion.action)
    sug["from"] = %v.suggestion.fromPath
    sug["to"] = %v.suggestion.toPath
    sug["rationale"] = %v.suggestion.rationale
    sug["confidence"] = %v.suggestion.confidence
    sug["action_required"] = %v.suggestion.actionRequired
    let obj = newJObject()
    obj["path"] = %v.path
    obj["kind"] = %v.kind
    obj["severity"] = %severityToString(v.suggestion.severity)
    obj["suggestion"] = sug
    violations.add(obj)
  let summary = newJObject()
  summary["errors"] = %r.errors
  summary["warnings"] = %r.warnings
  summary["info"] = %r.infoCount
  summary["exit_code"] = %(if r.errors > 0: 1 else: 0)
  result = newJObject()
  result["summary"] = summary
  result["violations"] = violations

{.pop}
