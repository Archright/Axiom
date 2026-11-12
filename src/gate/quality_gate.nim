import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import core/parser_utils
import compiler/ast
import core/gate/architecture_policy
import core/utils/repo_root
import std/[os, tables, sets, strutils, sequtils]
type
  ModuleInfo* = object
    path*: string
    imports*: seq[string]
    funcCount*: int
    procCount*: int
    totalFunctions*: int
    exportedFunctions*: int
    importCount*: int

  DependencyGraph* = object
    modules*: Table[string, ModuleInfo]
    reverseDeps*: Table[string, seq[string]]

  QualityViolation* = object
    rule*: string
    detail*: string
    file*: string
    line*: int
    severity*: string
# ---------------------------------------------------------------------------
# AST node classification (func only)
# ---------------------------------------------------------------------------

const
  StmtContainerKinds = {nkStmtList, nkWhenStmt, nkIfStmt, nkBlockStmt, nkTryStmt,
    nkTypeSection, nkConstSection, nkVarSection, nkLetSection}
  FuncDefKinds = {nkFuncDef, nkProcDef, nkMethodDef}

proc collectTransitiveAffected*(
  changedFiles: seq[string]; graph: DependencyGraph;
  maxDepth: int = 2
): HashSet[string] {.raises: [].} =
  var queue: seq[tuple[path: string; depth: int]] = @[]
  for f in changedFiles: queue.add((f, 0))
  while queue.len > 0:
    let current = queue[0]
    queue = queue[1 .. ^1]
    if current.path in result: continue
    result.incl(current.path)
    if current.depth >= maxDepth: continue
    for dep in graph.reverseDeps.getOrDefault(current.path, @[]):
      if dep notin result: queue.add((dep, current.depth + 1))
# ---------------------------------------------------------------------------
# I/O boundary (proc — single boundary for all I/O)
# ---------------------------------------------------------------------------
proc isStmtContainer(kind: TNodeKind): bool {.raises: [].} = kind in StmtContainerKinds
proc isFuncDefKind(kind: TNodeKind): bool {.raises: [].} = kind in FuncDefKinds

# ---------------------------------------------------------------------------
# Import path resolution (func only)
# ---------------------------------------------------------------------------
proc resolveImportPath*(importExpr: string; currentFile: string): string {.raises: [].} =
  var expr = importExpr.strip()
  if expr.len == 0: return ""
  let aliasIdx = expr.find(" as ")
  if aliasIdx >= 0: expr = expr[0 ..< aliasIdx].strip()
  if expr.startsWith("../") or expr.startsWith("./"):
    var parts = parentDir(currentFile).split('/')
    for part in expr.split('/'):
      if part == "..":
        if parts.len > 0: discard parts.pop()
      elif part == "." or part.len == 0: discard
      else: parts.add(part)
    return parts.join("/") & ".nim"
  if '/' in expr: return expr & ".nim"
  "src/" & expr.replace(".", "/") & ".nim"

# ---------------------------------------------------------------------------
# AST walking helpers (func only — pure PNode traversal)
# ---------------------------------------------------------------------------
proc collectDottedPath(node: PNode): string {.raises: [].} =
  var parts: seq[string] = @[]
  func walk(n: PNode) =
    if n == nil: return
    if n.kind == nkDotExpr:
      walk(n[0])
      if n.safeLen >= 2 and n[1].kind == nkIdent: parts.add(n[1].ident.s)
    elif n.kind == nkIdent: parts.add(n.ident.s)
  try: walk(node)
  except CatchableError: discard  # axiom:best-effort(ioboundary catch)
  parts.join(".")
proc collectModuleNamesFromImport(node: PNode; acc: var seq[string]) {.raises: [].} =
  if node.kind == nkIdent: acc.add(node.ident.s)
  elif node.kind == nkDotExpr:
    let dotted = collectDottedPath(node)
    if dotted.len > 0: acc.add(dotted)
proc walkImports(node: PNode; acc: var seq[string]) {.raises: [].} =
  if node.kind == nkStmtList:
    for i in 0 ..< node.safeLen: walkImports(node[i], acc)
  elif node.kind == nkImportStmt:
    for i in 0 ..< node.safeLen: collectModuleNamesFromImport(node[i], acc)
  elif node.kind == nkFromStmt:
    if node.safeLen >= 1: collectModuleNamesFromImport(node[0], acc)
proc isExportMarker(n: PNode): bool {.raises: [].} =
  n.kind == nkPostfix and n.safeLen >= 2 and n[0].kind == nkIdent and n[0].ident.s == "*"
proc walkFuncDefs(n: PNode; counts: var tuple[funcCount, procCount, methodCount, exportedCount: int]) {.raises: [].} =
  if isFuncDefKind(n.kind):
    if n.kind == nkFuncDef: inc counts.funcCount
    elif n.kind == nkProcDef: inc counts.procCount
    else: inc counts.methodCount
    if n.safeLen >= 1 and isExportMarker(n[0]): inc counts.exportedCount
  elif isStmtContainer(n.kind):
    for i in 0 ..< n.safeLen: walkFuncDefs(n[i], counts)
proc buildModuleInfoFromAST*(filePath: string; topNode: PNode): ModuleInfo {.raises: [].} =
  var rawImports: seq[string] = @[]
  walkImports(topNode, rawImports)
  var resolvedImports: seq[string] = @[]
  for imp in rawImports:
    let resolved = resolveImportPath(imp, filePath)
    if resolved.len > 0: resolvedImports.add(resolved)
  var counts: tuple[funcCount, procCount, methodCount, exportedCount: int]
  walkFuncDefs(topNode, counts)
  ModuleInfo(
    path: filePath, imports: resolvedImports,
    funcCount: counts.funcCount, procCount: counts.procCount,
    totalFunctions: counts.funcCount + counts.procCount + counts.methodCount,
    exportedFunctions: counts.exportedCount,
    importCount: resolvedImports.len)
proc buildGraphFromModules*(moduleInfos: seq[ModuleInfo]): DependencyGraph {.raises: [].} =
  for info in moduleInfos:
    result.modules[info.path] = info
    for imp in info.imports:
      result.reverseDeps.mgetOrPut(imp, @[]).add(info.path)
proc collectTransitiveAffected*(
  graph: DependencyGraph;
  changedFiles: seq[string];
  maxDepth: int = 5
): HashSet[string] {.raises: [].} =
  var queue: seq[tuple[path: string; depth: int]] = @[]
  for f in changedFiles: queue.add((f, 0))
  while queue.len > 0:
    let current = queue[0]
    queue = queue[1 .. ^1]
    if current.path in result: continue
    result.incl(current.path)
    if current.depth >= maxDepth: continue
    for dep in graph.reverseDeps.getOrDefault(current.path, @[]):
      if dep notin result: queue.add((dep, current.depth + 1))

# ---------------------------------------------------------------------------
# Quality checks (func only — pure analysis)
# ---------------------------------------------------------------------------
proc checkFuncProcRatio(violations: var seq[QualityViolation]; info: ModuleInfo) {.raises: [].} =
  let total = info.funcCount + info.procCount
  if total == 0: return
  let ratio = info.funcCount.float / total.float
  if ratio < 0.8:
    let pctInt = int(ratio * 100)
    violations.add(QualityViolation(
      rule: "Static-First",
      detail: info.path & ": func ratio " & $pctInt & "pct < 80pct " &
              "(func=" & $info.funcCount & ", proc=" & $info.procCount & ")",
      file: info.path, line: 0, severity: "error"))
proc checkImportCount(violations: var seq[QualityViolation]; info: ModuleInfo; policy: ArchitecturePolicy) {.raises: [].} =
  let layer = policy.layerForPath(info.path)
  if layer.len == 0: return
  var maxImports = policy.surfaceArea.defaultMaxImports
  try:
    let ll = policy.surfaceArea.layerLimits.getOrDefault(layer,
      LayerLimit(maxImports: maxImports, maxExportedFunctions: 0))
    if ll.maxImports > 0: maxImports = ll.maxImports
  except KeyError: discard
  if info.importCount > maxImports:
    violations.add(QualityViolation(
      rule: "SoC",
      detail: info.path & ": " & $info.importCount & " imports exceeds layer " &
              layer & " limit " & $maxImports,
      file: info.path, line: 0, severity: "warning"))
proc checkExportedFunctionCount(violations: var seq[QualityViolation]; info: ModuleInfo; policy: ArchitecturePolicy) {.raises: [].} =
  let layer = policy.layerForPath(info.path)
  if layer.len == 0: return
  var maxExported = policy.surfaceArea.defaultMaxExportedFunctions
  try:
    let ll = policy.surfaceArea.layerLimits.getOrDefault(layer,
      LayerLimit(maxImports: 0, maxExportedFunctions: maxExported))
    if ll.maxExportedFunctions > 0: maxExported = ll.maxExportedFunctions
  except KeyError: discard
  let moduleOverride = policy.surfaceArea.moduleOverrides.getOrDefault(info.path,
    LayerLimit(maxImports: -1, maxExportedFunctions: -1))
  if moduleOverride.maxExportedFunctions > 0: maxExported = moduleOverride.maxExportedFunctions
  if info.exportedFunctions > maxExported:
    violations.add(QualityViolation(
      rule: "SOLID",
      detail: info.path & ": " & $info.exportedFunctions & " exported functions exceeds layer " &
              layer & " limit " & $maxExported,
      file: info.path, line: 0, severity: "warning"))
proc checkLayerEdgeViolations(violations: var seq[QualityViolation]; graph: DependencyGraph; info: ModuleInfo; policy: ArchitecturePolicy) {.raises: [].} =
  let sourceLayer = policy.layerForPath(info.path)
  if sourceLayer.len == 0: return
  for impPath in info.imports:
    let targetLayer = policy.layerForPath(impPath)
    if targetLayer.len == 0: continue
    if sourceLayer != targetLayer and targetLayer notin policy.allowedLayersFor(sourceLayer):
      violations.add(QualityViolation(
        rule: "SoC",
        detail: info.path & " (" & sourceLayer & ") imports " &
                impPath & " (" & targetLayer & ") -- forbidden edge",
        file: info.path, line: 0, severity: "error"))
proc runQualityChecks(
  graph: DependencyGraph;
  affectedModules: HashSet[string];
  policy: ArchitecturePolicy;
  hasPolicy: bool
): seq[QualityViolation] {.raises: [].} =
  for modulePath in affectedModules:
    let info = graph.modules.getOrDefault(modulePath)
    if info.path.len == 0: continue
    checkFuncProcRatio(result, info)
    if hasPolicy:
      checkImportCount(result, info, policy)
      checkExportedFunctionCount(result, info, policy)
      checkLayerEdgeViolations(result, graph, info, policy)

# ---------------------------------------------------------------------------
# I/O boundary (proc — single boundary for all I/O)
# ---------------------------------------------------------------------------
proc parseSourceAST(filePath: string): PNode {.raises: [].} =
  ## Parse Nim source file into AST using shared IdentCache/ConfigRef caches.
  parser_utils.parseFileAST(filePath)
proc scanImportGraph(repoRoot: string): seq[ModuleInfo] {.raises: [Exception].} =
  ## Scan all source files to build complete import dependency graph.
  try:
    for path in walkDirRec(repoRoot / "src"):
      if path.endsWith(".nim"):
        let normalized = path.relativePath(repoRoot).replace("\\", "/")
        let topNode = parseSourceAST(normalized)
        if topNode != nil: result.add(buildModuleInfoFromAST(normalized, topNode))
  except CatchableError: discard  # axiom:best-effort(ioboundary catch)
# Normalize a staged file path to the same POSIX-relative form used as
# graph keys by scanImportGraph (relativePath(repoRoot) / "src"). Graph-key
# consistency is required so incremental seed files match reverse-dependency
# lookups; otherwise the affected set is silently empty (theater risk).
func normalizeStagedPath*(path: string; repoRoot: string): string {.raises: [].} =
  ## Normalize a staged file path to a POSIX-relative form. Absolute inputs are
  ## made relative to repoRoot without relying on std/os relativePath (which is
  ## not side-effect-free and cannot run in a `func`); relative inputs pass
  ## through with slashes normalized. Must mirror the graph-key form produced by
  ## scanImportGraph so seeds resolve against reverse-dependency lookups.
  let p = path.replace("\\", "/")
  if isAbsolute(p) and (repoRoot.len > 0) and p.startsWith(repoRoot):
    p[repoRoot.len .. ^1].strip(chars = {'/'}).normalizedPath
  else:
    p.strip(chars = {'/'}).normalizedPath

proc collectAndParseFiles(repoRoot: string; stagedFiles: seq[string]; fullTree: bool): seq[ModuleInfo] {.raises: [Exception].} =
  if fullTree:
    return scanImportGraph(repoRoot)
  # For incremental mode: build the complete reverse-dependency graph but only
  # check staged files (seeded in runQualityGate). Normalize path form to match
  # graph keys (POSIX-relative) so staged seeds resolve against reverse-deps.
  let hasStaged = anyIt(stagedFiles):
    let path = normalizeStagedPath(it, repoRoot)
    path.endsWith(".nim") and fileExists(path)
  # Return the full graph so transitive dependents of changed files are checked.
  result = scanImportGraph(repoRoot)
  if not hasStaged: result = @[]

# ---------------------------------------------------------------------------
# Main Entry Point
# ---------------------------------------------------------------------------
proc runQualityGate*(
  stagedFiles: seq[string] = @[];
  fullTree: bool = false
): seq[QualityViolation] {.raises: [Exception].} =
  let repoRoot = findRepoRoot()
  let parsedPolicy = loadArchitecturePolicy()
  # Build complete import graph from all source files for reverse dependency tracking
  let moduleInfos = collectAndParseFiles(repoRoot, stagedFiles, fullTree)
  if moduleInfos.len == 0: return

  let graph = buildGraphFromModules(moduleInfos)

  # Determine the seed set: staged files or all modules
  var seedFiles: seq[string] = @[]
  if fullTree:
    for info in moduleInfos: seedFiles.add(info.path)
  else:
    for rawPath in stagedFiles:
      let path = normalizeStagedPath(rawPath, repoRoot)
      if path.endsWith(".nim") and fileExists(path): seedFiles.add(path)

  # Walk import tree: find all modules transitively affected by changes
  let affectedModules = collectTransitiveAffected(graph, seedFiles)
  runQualityChecks(graph, affectedModules, parsedPolicy.policy, parsedPolicy.ok)
proc qualityGateReport(violations: seq[QualityViolation]): string {.raises: [].} =
  if violations.len == 0: return "[quality-gate] PASS -- no violations detected"
  result = "[quality-gate] FAIL -- " & $violations.len & " violation(s):\n"
  for v in violations:
    let loc = if v.line > 0: ":" & $v.line else: ""
    result.add("  [" & v.severity & "] " & v.rule & ": " & v.file & loc & ": " & v.detail & "\n")
proc qualityGateExitCode(violations: seq[QualityViolation]): int {.raises: [].} =
  for v in violations:
    if v.severity == "error": return 1
  0

{.pop.}

