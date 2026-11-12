import core/trusted/layer_declaration
axiomLayer "domain"
import core/topology/declaration
import core/trusted/axiom_pragmas
import core/trusted/stdlib_shield
import std/[os, strutils, sets, tables]
# axiomIoBoundary

export declaration

type
  MoveOp* = object
    file*: string
    fromPath*: string
    toPath*: string

  RewriteOp* = object
    file*: string
    oldPath*: string
    newPath*: string

  Plan* = object
    moves*: seq[MoveOp]
    rewrites*: seq[RewriteOp]
# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func moduleImportPath*(relFilePath: string): string {.raises: [].} =
  ## Convert a source file path to its Nim import path.
  ## Example: "src/core/topology/import_graph.nim" -> "core/topology/import_graph"
  if relFilePath.startsWith("src/"):
    result = relFilePath[4..^1]
  else:
    result = relFilePath
  if result.endsWith(".nim"):
    result = result[0..^5]
  result = result.replace("\\", "/")
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc fileExistsRelative*(path: string): bool {.raises: [].} =
  ## IOError/OSError declared as CatchableError: stdlib_shield shadows the
  ## specific identifiers in this module; the supertype is compiler-compatible.
  fileExists(path)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc scanSourceFiles*(root: string = "src"): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let dirOk =
    try: safeDirExists(root)
    except CatchableError: false
  if not dirOk:
    return
  let base = root.parentDir
  try:
    for path in safeWalkDirRec(root):
      if path.endsWith(".nim"):
        result.add(path.relativePath(base))
  except CatchableError:
    discard # axiom:best-effort(scan failure → empty result)
# ---------------------------------------------------------------------------
# Plan generation
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func importsModule*(content, importPath: string): bool {.raises: [].} =
  ## Fast grep-style pre-filter. Not AST-precise; callers must verify with AST.
  let importPrefix = "import " & importPath
  let fromPrefix = "from " & importPath
  var idx = 0
  while true:
    let i = content.find(importPrefix, idx)
    if i < 0: break
    let after = i + importPrefix.len
    if after >= content.len or content[after] in {' ', '\n', '\r', '\t', '/', '[', '"'}:
      return true
    idx = after
  idx = 0
  while true:
    let i = content.find(fromPrefix, idx)
    if i < 0: break
    let after = i + fromPrefix.len
    if after >= content.len or content[after] in {' ', '\n', '\r', '\t', '/', '"'}:
      return true
    idx = after
  false

# ---------------------------------------------------------------------------
# Plan generation
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeDrift*(decl: TopologyDeclaration; root: string = "src"): seq[MoveOp] {.raises: [].} =
  ## Compare filesystem against topology.json and return move operations.
  let files = scanSourceFiles(root)
  for relPath in files:
    let (domain, subdomain, matchedBy) = classifyFile(relPath, decl)
    if matchedBy == "unmapped":
      continue
    let expectedDir = expectedPath(relPath, domain, subdomain, decl)
    if expectedDir.len == 0:
      continue
    let base = extractFilename(relPath)
    let expectedPathFull = expectedDir.replace("\\", "/")
    let expectedFile =
      if expectedPathFull.endsWith("/"):
        expectedPathFull & base
      else:
        expectedPathFull & "/" & base
    if relPath != expectedFile:
      result.add(MoveOp(file: relPath, fromPath: relPath, toPath: expectedFile))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc findConsumers*(importPath: string; root: string = "src"): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Return files that likely import `importPath`.
  let files = scanSourceFiles(root)
  let base = root.parentDir
  for relPath in files:
    let content =
      try: safeReadFile(base / relPath)
      except CatchableError: ""
    if importsModule(content, importPath):
      result.add(relPath)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeRewrites*(moves: seq[MoveOp]; root: string = "src"): seq[RewriteOp] {.raises: [].} =
  for m in moves:
    let oldImport = moduleImportPath(m.fromPath)
    let newImport = moduleImportPath(m.toPath)
    for consumer in findConsumers(oldImport, root):
      result.add(RewriteOp(file: consumer, oldPath: oldImport, newPath: newImport))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computePlan*(decl: TopologyDeclaration; root: string = "src"): Plan {.raises: [].} =
  result.moves = computeDrift(decl, root)
  result.rewrites = computeRewrites(result.moves, root)
# ---------------------------------------------------------------------------
# Filter suggestions and blast-radius summary
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseFilterExpr*(filterExpr: string): tuple[domain, subdomain: string] {.raises: [].} =
  ## Parse "domain" or "domain.subdomain".
  if filterExpr.len == 0:
    return ("", "")
  let parts = filterExpr.split('.')
  result.domain = parts[0]
  if parts.len > 1:
    result.subdomain = parts[1]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func matchesFilter*(filePath: string; decl: TopologyDeclaration;
                    domain, subdomain: string): bool {.raises: [].} =
  ## Check whether a file path matches the filter. Subdomain prefix matching
  ## is supported so "gate.nimtry" also matches "gate.nimtry.extract".
  let (d, s, matchedBy) = classifyFile(filePath, decl)
  if matchedBy == "unmapped":
    return false
  if domain.len > 0 and d != domain:
    return false
  if subdomain.len > 0:
    if s != subdomain and not s.startsWith(subdomain & "/"):
      return false
  true
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func filterPlan*(plan: Plan; decl: TopologyDeclaration; filterExpr: string): Plan {.raises: [].} =
  ## Return a plan containing only moves matching the filter and all rewrites
  ## for those moves (regardless of consumer domain). This implements the
  ## "filter selects targets, work scope expands to transitive consumers"
  ## rule from the approved surgical-reconciliation plan.
  if filterExpr.len == 0:
    return plan
  let (domain, subdomain) = parseFilterExpr(filterExpr)

  var filteredMoves: seq[MoveOp] = @[]
  for m in plan.moves:
    if matchesFilter(m.fromPath, decl, domain, subdomain):
      filteredMoves.add(m)

  var targetedOldImports = initHashSet[string]()
  for m in filteredMoves:
    targetedOldImports.incl(moduleImportPath(m.fromPath))

  var filteredRewrites: seq[RewriteOp] = @[]
  for r in plan.rewrites:
    if targetedOldImports.contains(r.oldPath):
      filteredRewrites.add(r)

  result.moves = filteredMoves
  result.rewrites = filteredRewrites


# ---------------------------------------------------------------------------
# Filter suggestions and blast-radius summary
# ---------------------------------------------------------------------------
type
  FilterSuggestion* = object
    filter*: string
    moveCount*: int
    rewriteCount*: int
    affectedConsumerDomains*: seq[string]
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func suggestFilters*(plan: Plan; decl: TopologyDeclaration): seq[FilterSuggestion] {.raises: [].} =
  ## Group moves by their domain.subdomain and calculate blast radius:
  ## how many consumer rewrites each group triggers and in which domains.
  var groups: Table[string, FilterSuggestion]
  for m in plan.moves:
    let (d, s, _) = classifyFile(m.fromPath, decl)
    let filterExpr = d & "." & s
    if not groups.hasKey(filterExpr):
      groups[filterExpr] = FilterSuggestion(filter: filterExpr)
    try: groups[filterExpr].moveCount += 1
    except KeyError: discard

  for r in plan.rewrites:
    let (consumerDomain, _, _) = classifyFile(r.file, decl)
    for m in plan.moves:
      if moduleImportPath(m.fromPath) == r.oldPath:
        let (md, ms, _) = classifyFile(m.fromPath, decl)
        let filterExpr = md & "." & ms
        if groups.hasKey(filterExpr):
          try:
            groups[filterExpr].rewriteCount += 1
            if consumerDomain notin groups[filterExpr].affectedConsumerDomains:
              groups[filterExpr].affectedConsumerDomains.add(consumerDomain)
          except KeyError: discard
        break

  for v in groups.values:
    result.add(v)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func formatSuggestions*(suggestions: seq[FilterSuggestion]): string {.raises: [].} =
  if suggestions.len == 0:
    return ""
  var lines: seq[string] = @[]
  lines.add("")
  lines.add("Detected " & $suggestions.len & " subdomain drift groups. Suggested commands:")
  for s in suggestions:
    var consumerInfo = ""
    if s.affectedConsumerDomains.len > 0:
      consumerInfo = " (affects consumers in " & s.affectedConsumerDomains.join(", ") & ")"
    lines.add("  ax topology apply --filter " & s.filter &
              "  # " & $s.moveCount & " moves, " & $s.rewriteCount & " rewrites" & consumerInfo)
  result = lines.join("\n")

# ---------------------------------------------------------------------------
# Human-readable plan rendering
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func formatPlan*(plan: Plan): string {.raises: [].} =
  if plan.moves.len == 0 and plan.rewrites.len == 0:
    return "No drift detected. Topology matches declaration."
  var lines: seq[string] = @[]
  lines.add("Plan:")
  if plan.moves.len > 0:
    lines.add("")
    lines.add("Moves (" & $plan.moves.len & "):")
    for m in plan.moves:
      lines.add("  move " & m.fromPath & " -> " & m.toPath)
  if plan.rewrites.len > 0:
    lines.add("")
    lines.add("Import rewrites (" & $plan.rewrites.len & "):")
    for r in plan.rewrites:
      lines.add("  " & r.file & ": " & r.oldPath & " -> " & r.newPath)
  result = lines.join("\n")

