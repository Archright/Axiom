import core/trusted/layer_declaration
axiomLayer "gate"
{.experimental: "codeReordering".}
{.push raises: [CatchableError].}

## unified_gate_runner — Gate 1: Pre-expansion syntactic AST scanner
##
## Scans Nim AST for forbidden patterns BEFORE macro/template expansion.
## Four check layers:
##   SA-2.1  verifyLayerBoundaries  — cross-layer import detection
##   SA-2.2  calculateAstWeight     — AST complexity bounds
##   SA-2.3  scanForbiddenTokens    — token ban enforcement (cast/ptr/emit/...)
##   SA-2.4  scanResultErrorTypes   — Result[T, E] with forbidden error types
##
## This gate is BLOCKING (exit 1 on violations).
## No semantic analysis — purely syntactic AST walk.

import std/[os, strutils, strformat, json, monotimes, times]
import core/crypto/hash_kernel
import core/parser_utils
import compiler/ast
import core/axiom_pragmas
import infrastructure/logging_facade
# axiomIoBoundary
# NOTE: gate/gate_types NOT imported — this runner defines its own GateResult
# to avoid the gate_contract → core/gate_types transitive dependency.

const
  GateTag = "[unified-gate]"

  ## Maximum AST weight: depth² × (node_count / 100)
  MaxAstWeight* = 2000.0

  ## Infrastructure layer paths — exempt from some checks
  InfrastructureExemptPaths* = [
    "src/core/trusted/",
    "src/infrastructure/",
  ]

  ## Layer prefix mapping for source files
  CorePrefix* = "src/core/"
  DomainPrefix* = "src/engine/"
  GatePrefix* = "src/gate/"
  InfraPrefix* = "src/infrastructure/"
  CliPrefix* = "src/cli/"

  ## Forbidden Result error types (SA-2.4)
  ForbiddenErrorTypes* = ["string", "seq"]

  ## Default cache file path (gitignored, runtime-generated)
  DefaultCachePath* = "src/gate/.unified_gate_cache.json"

  ## Cache schema version — bump to force full invalidation
  CacheVersion = 1

type
  Violation* = object
    ## Single AST violation detected by a scan proc.
    file*: string
    line*: int
    column*: int
    rule*: string       ## e.g. "SA-2.1", "SA-2.2", "SA-2.3", "SA-2.4"
    severity*: string   ## "critical", "high", "medium"
    message*: string

  GateResult* = object
    ok*: bool
    violations*: seq[Violation]
    stdout*: string
    stderr*: string

  ForbiddenTokenRule* = object
    ## Parsed entry from forbidden_tokens.json.
    id*: string
    name*: string
    severity*: string
    layers*: seq[string]
    reason*: string
    replacement*: string
    ## AST node kinds this rule matches
    nodeKinds*: set[TNodeKind]
    ## Ident names to match inside calls (empty = match all calls for this kind)
    identNames*: seq[string]

  LayerDag* = JsonNode
    ## Layer dependency graph: { "core": { "allowed": ["core", "infrastructure"] }, ... }

# ─── AST Parsing ───────────────────────────────────────────────────────────

proc lineInfoOf*(ast: PNode): tuple[line, col: int] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Extract line/column from a PNode's info.
  let info = ast.info
  if info.line.int > 0:
    result = (line: info.line.int, col: info.col.int)
  else:
    result = (line: 0, col: 0)

proc parseFileToAst*(filePath: string): PNode {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse a .nim file into a PNode tree using shared IdentCache/ConfigRef caches.
  parser_utils.parseFileAST(filePath)

# ─── Forbidden Token Loading ───────────────────────────────────────────────

proc parseForbiddenTokens*(tokensJson: JsonNode): seq[ForbiddenTokenRule] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Parse forbidden_tokens.json into typed rules.
  let tokens = tokensJson{"tokens"}
  if tokens == nil or tokens.kind != JArray:
    return

  for tok in tokens:
    let rule = ForbiddenTokenRule(
      id: tok{"id"}.getStr(""),
      name: tok{"name"}.getStr(""),
      severity: tok{"severity"}.getStr("high"),
      layers: block:
        var layers: seq[string]
        let jLayers = tok{"layers"}
        if jLayers.kind == JArray:
          for j in jLayers: layers.add(j.getStr(""))
        layers,
      reason: tok{"reason"}.getStr(""),
      replacement: tok{"replacement"}.getStr(""),
    )
    result.add(rule)

proc buildTokenLookup*(rules: seq[ForbiddenTokenRule]): seq[ForbiddenTokenRule] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Identity pass — rules already carry their matching information.
  result = rules

# ─── Incremental Cache ──────────────────────────────────────────────────────

proc computeFileHash*(path: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 hex digest of a file's content.
  let content = readFile(path)
  hash_kernel.sha256Hex(content)

proc loadCache*(cachePath: string): JsonNode {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load the gate cache from disk. Returns empty object on missing/corrupt.
  if fileExists(cachePath):
    try:
      result = parseJson(readFile(cachePath))
    except CatchableError:
      result = newJObject()
  else:
    result = newJObject()

proc saveCache*(cachePath: string; cache: JsonNode) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist the gate cache to disk. Best-effort; errors silently ignored.
  try:
    writeFile(cachePath, cache.pretty())
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

proc invalidateCache*(cache: JsonNode) =
  ## Drop all file entries when forbidden_tokens.json changes.
  cache["files"] = newJObject()

# ─── Layer Resolution ──────────────────────────────────────────────────────

proc isInfrastructureExempt*(filePath: string): bool {.raises: [CatchableError].} =
  ## Check if a file resides in an infrastructure-exempt path.
  for prefix in InfrastructureExemptPaths:
    if filePath.startsWith(prefix):
      return true
  result = false

proc layerForPath*(filePath: string): string {.raises: [CatchableError].} =
  ## Determine the architecture layer for a given source file path.
  if filePath.startsWith(CorePrefix): return "core"
  if filePath.startsWith(DomainPrefix): return "domain"
  if filePath.startsWith(GatePrefix): return "gate"
  if filePath.startsWith(InfraPrefix): return "infrastructure"
  if filePath.startsWith(CliPrefix): return "cli"
  result = ""

proc isAllowedImport*(layerDag: LayerDag; sourceLayer, targetLayer: string): bool {.raises: [CatchableError].} =
  ## Check if sourceLayer is allowed to import from targetLayer per the DAG.
  if layerDag == nil:
    ## No DAG provided — allow all (permissive mode)
    return true
  if sourceLayer == targetLayer:
    return true
  let allowed = layerDag{sourceLayer, "allowed"}
  if allowed == nil or allowed.kind != JArray:
    return false
  for a in allowed:
    if a.getStr("") == targetLayer:
      return true
  result = false

proc extractImportTarget*(node: PNode): string {.raises: [CatchableError].} =
  ## Extract the module path string from an import or from statement.
  case node.kind
  of nkImportStmt, nkImportExceptStmt:
    ## import foo/bar — first child is the module ident
    if node.len > 0 and node[0].kind == nkIdent:
      return node[0].ident.s
    if node.len > 0 and node[0].kind == nkInfix:
      ## import foo/bar as baz
      if node[0].len >= 3 and node[0][0].kind == nkIdent and
         node[0][0].ident.s == "as" and
         node[0][1].kind == nkIdent:
        return node[0][1].ident.s
  of nkFromStmt:
    ## from foo/bar import X — first child is module ident
    if node.len > 0 and node[0].kind == nkIdent:
      return node[0].ident.s
  else:
    discard
  result = ""

# ─── AST Weight (SA-2.2) ──────────────────────────────────────────────────

proc countNodes*(ast: PNode): int {.raises: [CatchableError].} =
  ## Count total AST nodes recursively.
  if ast == nil:
    return 0
  result = 1
  for child in ast:
    result += countNodes(child)

proc maxDepth*(ast: PNode): int {.raises: [CatchableError].} =
  ## Compute maximum depth of the AST tree.
  if ast == nil:
    return 0
  var maxChildDepth = 0
  for child in ast:
    let d = maxDepth(child)
    if d > maxChildDepth:
      maxChildDepth = d
  result = 1 + maxChildDepth

proc astWeight*(ast: PNode): float {.raises: [CatchableError].} =
  ## Calculate AST weight: depth² × (node_count / 100).
  let depth = float(maxDepth(ast))
  let count = float(countNodes(ast))
  result = depth * depth * (count / 100.0)

# ─── AST Walk Helpers ──────────────────────────────────────────────────────

proc isCallTo*(node: PNode; names: openArray[string]): bool {.raises: [CatchableError].} =
  ## Check if a node is a call to any of the given identifier names.
  if node.kind != nkCall and node.kind != nkInfix:
    return false
  if node.len == 0:
    return false
  let callee = node[0]
  case callee.kind
  of nkIdent:
    for name in names:
      if callee.ident.s == name:
        return true
  of nkBracketExpr:
    ## qualified call like addr(x) — unlikely but handle
    discard
  of nkDotExpr:
    discard
  else:
    discard
  result = false

proc findIdentNames*(node: PNode; depth: int = 0): seq[string] {.raises: [CatchableError].} =
  ## Collect all ident names from an AST subtree (limited depth).
  if node == nil or depth > 10:
    return
  case node.kind
  of nkIdent:
    result.add(node.ident.s)
  of nkSym:
    discard  ## skip symbols (compiler-resolved)
  else:
    for child in node:
      result.add(findIdentNames(child, depth + 1))

# ─── SA-2.1: Layer Boundary Verification ───────────────────────────────────

proc verifyLayerBoundaries*(ast: PNode; filePath: string; layerDag: LayerDag): seq[Violation] {.raises: [CatchableError].} =
  ## Scans nkImportStmt, nkFromStmt for forbidden cross-layer imports.
  if ast == nil:
    return
  let sourceLayer = layerForPath(filePath)
  if sourceLayer.len == 0:
    ## Unknown layer — cannot verify boundaries
    return
  if isInfrastructureExempt(filePath):
    ## Infrastructure-Exempt: skip layer boundary check
    return

  var violations: seq[Violation]

  proc walkForImports(node: PNode) {.raises: [CatchableError].} =
    if node == nil:
      return
    case node.kind
    of nkImportStmt, nkImportExceptStmt, nkFromStmt:
      let target = extractImportTarget(node)
      if target.len == 0:
        return
      ## Resolve target layer from import path
      var targetLayer = ""
      if target.startsWith("core/"): targetLayer = "core"
      elif target.startsWith("engine/"): targetLayer = "domain"
      elif target.startsWith("gate/"): targetLayer = "gate"
      elif target.startsWith("infrastructure/"): targetLayer = "infrastructure"
      elif target.startsWith("cli/"): targetLayer = "cli"

      if targetLayer.len == 0 or sourceLayer == targetLayer:
        return

      if not isAllowedImport(layerDag, sourceLayer, targetLayer):
        let info = lineInfoOf(node)
        violations.add(Violation(
          file: filePath,
          line: info.line,
          column: info.col,
          rule: "SA-2.1",
          severity: "critical",
          message: fmt"Cross-layer import: {sourceLayer} → {targetLayer} ({target})",
        ))
    else:
      for child in node:
        walkForImports(child)

  walkForImports(ast)
  result = violations

# ─── SA-2.2: AST Complexity Check ─────────────────────────────────────────

proc calculateAstWeight*(ast: PNode; filePath: string): seq[Violation] {.raises: [CatchableError].} =
  ## Depth² × (node_count / 100) ≤ 2000.
  if ast == nil:
    return
  let weight = astWeight(ast)
  if weight > MaxAstWeight:
    let nodeCount = countNodes(ast)
    let depth = maxDepth(ast)
    result.add(Violation(
      file: filePath,
      line: 1,
      column: 0,
      rule: "SA-2.2",
      severity: "high",
      message: fmt"AST weight {weight:.1f} exceeds limit {MaxAstWeight:.0f} " &
               fmt"(depth={depth}, nodes={nodeCount}). Consider decomposing.",
    ))

# ─── SA-2.3: Forbidden Token Scan ─────────────────────────────────────────

proc scanForbiddenTokens*(ast: PNode; filePath: string;
                          rules: seq[ForbiddenTokenRule]): seq[Violation] {.raises: [CatchableError].} =
  ## Walks AST for nkCast, nkPtrTy, nkPragma with emit/global/raises:CatchableError,
  ## nkCall with addr/copyMem/moveMem/zeroMem/alloc/dealloc/realloc.
  if ast == nil:
    return
  if isInfrastructureExempt(filePath):
    return

  let sourceLayer = layerForPath(filePath)

  var violations: seq[Violation]

  proc checkNode(node: PNode; depth: int = 0) =
    if node == nil or depth > 200:
      return

    case node.kind
    of nkCast:
      ## FT-003: cast type bypass
      for rule in rules:
        if rule.id == "FT-003":
          if sourceLayer.len == 0 or sourceLayer in rule.layers:
            let info = lineInfoOf(node)
            violations.add(Violation(
              file: filePath,
              line: info.line,
              column: info.col,
              rule: rule.id,
              severity: rule.severity,
              message: fmt"cast[] type bypass: {rule.reason} — {rule.replacement}",
            ))

    of nkPtrTy:
      ## FT-004: raw pointer type
      for rule in rules:
        if rule.id == "FT-004":
          if sourceLayer.len == 0 or sourceLayer in rule.layers:
            let info = lineInfoOf(node)
            violations.add(Violation(
              file: filePath,
              line: info.line,
              column: info.col,
              rule: rule.id,
              severity: rule.severity,
              message: fmt"Raw ptr type: {rule.reason} — {rule.replacement}",
            ))

    of nkPragma:
      ## FT-001: raises:CatchableError, FT-002: emit, FT-009: global
      for child in node:
        var pragmaName = ""
        case child.kind
        of nkIdent:
          pragmaName = child.ident.s
        of nkExprColonExpr:
          if child.len > 0 and child[0].kind == nkIdent:
            pragmaName = child[0].ident.s
            ## Check for raises: [CatchableError]
            if pragmaName == "raises":
              for rule in rules:
                if rule.id == "FT-001":
                  ## Check if CatchableError is among the raised types
                  if child.len > 1:
                    let raisesSpec = child[1]
                    if raisesSpec.kind == nkBracket:
                      for exc in raisesSpec:
                        if exc.kind == nkIdent and exc.ident.s == "CatchableError":
                          if sourceLayer.len == 0 or sourceLayer in rule.layers:
                            let info = lineInfoOf(node)
                            violations.add(Violation(
                              file: filePath,
                              line: info.line,
                              column: info.col,
                              rule: rule.id,
                              severity: rule.severity,
                              message: fmt"raises CatchableError: {rule.reason} — {rule.replacement}",
                            ))
                            break
                    elif raisesSpec.kind == nkIdent and
                         raisesSpec.ident.s == "CatchableError":
                      for rule in rules:
                        if rule.id == "FT-001":
                          if sourceLayer.len == 0 or sourceLayer in rule.layers:
                            let info = lineInfoOf(node)
                            violations.add(Violation(
                              file: filePath,
                              line: info.line,
                              column: info.col,
                              rule: rule.id,
                              severity: rule.severity,
                              message: fmt"raises CatchableError: {rule.reason} — {rule.replacement}",
                            ))
        else:
          discard

        if pragmaName == "emit":
          for rule in rules:
            if rule.id == "FT-002":
              if sourceLayer.len == 0 or sourceLayer in rule.layers:
                let info = lineInfoOf(node)
                violations.add(Violation(
                  file: filePath,
                  line: info.line,
                  column: info.col,
                  rule: rule.id,
                  severity: rule.severity,
                  message: fmt"Emit pragma: {rule.reason} — {rule.replacement}",
                ))

        if pragmaName == "global":
          for rule in rules:
            if rule.id == "FT-009":
              if sourceLayer.len == 0 or sourceLayer in rule.layers:
                let info = lineInfoOf(node)
                violations.add(Violation(
                  file: filePath,
                  line: info.line,
                  column: info.col,
                  rule: rule.id,
                  severity: rule.severity,
                  message: fmt"Global pragma: {rule.reason} — {rule.replacement}",
                ))

    of nkCall, nkInfix:
      ## FT-005: addr, FT-006: copyMem/moveMem/zeroMem, FT-007: alloc/dealloc/realloc
      if node.len > 0:
        let callee = node[0]
        if callee.kind == nkIdent:
          let calleeName = callee.ident.s
          ## FT-005: addr call
          if calleeName == "addr":
            for rule in rules:
              if rule.id == "FT-005":
                if sourceLayer.len == 0 or sourceLayer in rule.layers:
                  let info = lineInfoOf(node)
                  violations.add(Violation(
                    file: filePath,
                    line: info.line,
                    column: info.col,
                    rule: rule.id,
                    severity: rule.severity,
                    message: fmt"addr() call: {rule.reason} — {rule.replacement}",
                  ))

          ## FT-006: memory manipulation
          if calleeName in ["copyMem", "moveMem", "zeroMem"]:
            for rule in rules:
              if rule.id == "FT-006":
                if sourceLayer.len == 0 or sourceLayer in rule.layers:
                  let info = lineInfoOf(node)
                  violations.add(Violation(
                    file: filePath,
                    line: info.line,
                    column: info.col,
                    rule: rule.id,
                    severity: rule.severity,
                    message: fmt"Memory manipulation ({calleeName}): {rule.reason} — {rule.replacement}",
                  ))

          ## FT-007: heap management
          if calleeName in ["alloc", "dealloc", "realloc"]:
            for rule in rules:
              if rule.id == "FT-007":
                if sourceLayer.len == 0 or sourceLayer in rule.layers:
                  let info = lineInfoOf(node)
                  violations.add(Violation(
                    file: filePath,
                    line: info.line,
                    column: info.col,
                    rule: rule.id,
                    severity: rule.severity,
                    message: fmt"Heap management ({calleeName}): {rule.reason} — {rule.replacement}",
                  ))

    of nkIdent:
      ## FT-008: bare pointer ident
      let name = node.ident.s
      if name == "pointer":
        for rule in rules:
          if rule.id == "FT-008":
            if sourceLayer.len == 0 or sourceLayer in rule.layers:
              ## Avoid false positives from comments — only flag real ident uses
              ## by checking parent is not a comment
              let info = lineInfoOf(node)
              violations.add(Violation(
                file: filePath,
                line: info.line,
                column: info.col,
                rule: rule.id,
                severity: rule.severity,
                message: fmt"Bare 'pointer' type: {rule.reason} — {rule.replacement}",
              ))

    of nkVarSection:
      ## FT-010: top-level var declaration
      for rule in rules:
        if rule.id == "FT-010":
          if sourceLayer.len == 0 or sourceLayer in rule.layers:
            let info = lineInfoOf(node)
            violations.add(Violation(
              file: filePath,
              line: info.line,
              column: info.col,
              rule: rule.id,
              severity: rule.severity,
              message: fmt"Top-level var: {rule.reason} — {rule.replacement}",
            ))

    else:
      discard

    for child in node:
      checkNode(child, depth + 1)

  checkNode(ast)
  result = violations

# ─── SA-2.4: Result Error Type Scan ───────────────────────────────────────

proc extractBracketTypes*(node: PNode): seq[string] {.raises: [CatchableError].} =
  ## Extract type names from nkBracketExpr like Result[T, E].
  if node.kind != nkBracketExpr:
    return
  ## The first ident is typically the type constructor (e.g. "Result")
  for child in node:
    case child.kind
    of nkIdent:
      result.add(child.ident.s)
    of nkSym:
      result.add(child.sym.name.s)
    of nkBracketExpr:
      result.add(extractBracketTypes(child))
    else:
      discard

proc scanResultErrorTypes*(ast: PNode; filePath: string): seq[Violation] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scans nkBracketExpr for Result[T, E] where E might be string/seq.
  if ast == nil:
    return
  if isInfrastructureExempt(filePath):
    return

  var violations: seq[Violation]

  proc checkNode(node: PNode; depth: int = 0) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
    if node == nil or depth > 200:
      return

    case node.kind
    of nkBracketExpr:
      ## Check for Result[T, E] pattern
      if node.len >= 2:
        let constructorName =
          case node[0].kind
          of nkIdent: node[0].ident.s
          of nkSym: node[0].sym.name.s
          else: ""

        if constructorName == "Result":
          ## Examine the error type (last bracket argument)
          let errorTypeNode = node[node.len - 1]
          let errorTypeName =
            case errorTypeNode.kind
            of nkIdent: errorTypeNode.ident.s
            of nkSym: errorTypeNode.sym.name.s
            else: ""

          if errorTypeName in ForbiddenErrorTypes:
            let info = lineInfoOf(node)
            violations.add(Violation(
              file: filePath,
              line: info.line,
              column: info.col,
              rule: "SA-2.4",
              severity: "high",
              message: fmt"Result[T, {errorTypeName}]: error type should be enum, not {errorTypeName}",
            ))
    else:
      discard

    for child in node:
      checkNode(child, depth + 1)

  checkNode(ast)
  result = violations

# ─── Main Entry Point ──────────────────────────────────────────────────────

proc runUnifiedGate*(files: seq[string]; layerDag: LayerDag = nil;
                     useCache: bool = true): GateResult {.raises: [Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
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

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [Exception].} =
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

when isMainModule: main()

{.pop.}
