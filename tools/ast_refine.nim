## tools/ast_refine.nim — Axiom AST-based code refinement tool
##
## Single binary with 5 subcommands for AST-driven code transformation:
##   proc-to-func      Convert eligible procs to funcs using call-graph analysis
##   narrow-raises     Find {.raises: [Exception].} patterns for review
##   migrate-imports   Find import boundary violations (layer ordering)
##   collect-debt      Scan for axiomDebt pragmas, generate debt ledger
##   add-raises        Inject {.push raises: [].} where compiler-verified safe
##
## Build:
##   nim c --hints:off -o:bin/ast-refine tools/ast_refine.nim
##
## Usage:
##   bin/ast-refine proc-to-func [--dry-run] [--verify]
##   bin/ast-refine narrow-raises
##   bin/ast-refine migrate-imports
##   bin/ast-refine collect-debt
##   bin/ast-refine add-raises [--dry-run]

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, macros, sequtils, algorithm, tables,
            sets, osproc, streams]
import api/tools_facade
import safe_move

# ═══════════════════════════════════════════════════════════════════════
# Effect declarations (AGENTS.md §0.6 Static First)
# ═══════════════════════════════════════════════════════════════════════

template axiomEffect*(e: untyped) {.pragma.}
type IoEffect* = object

# ═══════════════════════════════════════════════════════════════════════
# Types
# ═══════════════════════════════════════════════════════════════════════

type
  ProcInfo = object
    name: string
    line: int          ## 0-based line index of the proc declaration
    bodyStart: int     ## 0-based line index where body begins (after =)
    endLine: int       ## 0-based line index (exclusive) after the proc body
    isFunc: bool
    hasSideEffect: bool
    hasRaisesPragma: bool

  RaisesViolation = object
    file: string
    line: int          ## 1-based
    procName: string
    raisesClause: string

  ImportViolation = object
    file: string
    line: int          ## 1-based
    importPath: string
    sourceLayer: string
    targetLayer: string

  DebtRecord = object
    id: string
    file: string
    line: int          ## 1-based
    category: string
    severity: string
    ttl: string

  RaisesCheckResult = object
    file: string
    injectable: bool
    errorLines: seq[string] ## compiler output lines explaining rejection

  LayerLevel = enum
    lInfrastructure = 0
    lCore = 1
    lEngine = 2
    lGate = 3
    lFrontend = 4
    lCli = 5
    lUnknown = 99

# ═══════════════════════════════════════════════════════════════════════
# Logging
# ═══════════════════════════════════════════════════════════════════════

proc log(msg: string) {.axiomEffect: IoEffect.} =
  echo msg

# ═══════════════════════════════════════════════════════════════════════
# File discovery
# ═══════════════════════════════════════════════════════════════════════

proc findNimFiles(root: string,
                  extraExclude: seq[string] = @[]): seq[string] =
  ## Recursively find .nim files under root, excluding build/cache dirs.
  ## walkDirRec can raise OSError — catch and return partial results.
  const defaultExclude = [".nimcache", "nimcache", ".git", "node_modules",
                          "build", "vendor", ".kimi-code"]
  try:
    for path in walkDirRec(root):
      if not path.endsWith(".nim"):
        continue
      let (_, dirPart, _) = splitFile(path)
      var skip = false
      for ex in defaultExclude:
        if ex in dirPart:
          skip = true
          break
      if not skip:
        for ex in extraExclude:
          if ex in dirPart:
            skip = true
            break
      if not skip:
        result.add(path)
  except OSError:
    discard
  result.sort()

# ═══════════════════════════════════════════════════════════════════════
# Layer mapping (AGENTS.md §0.3)
# ═══════════════════════════════════════════════════════════════════════

func layerFromPath(filePath: string): LayerLevel =
  let normalized = filePath.replace('\\', '/')
  if "/infrastructure/" in normalized:
    lInfrastructure
  elif "/core/" in normalized:
    lCore
  elif "/engine/" in normalized:
    lEngine
  elif "/gate/" in normalized:
    lGate
  elif "/frontend/" in normalized:
    lFrontend
  elif "/cli/" in normalized:
    lCli
  else:
    lUnknown

func layerName(layer: LayerLevel): string =
  case layer
  of lInfrastructure: "infrastructure"
  of lCore: "core"
  of lEngine: "engine"
  of lGate: "gate"
  of lFrontend: "frontend"
  of lCli: "cli"
  of lUnknown: "unknown"

func layerFromImportPath(importPath: string): LayerLevel =
  let parts = importPath.split('/')
  if parts.len == 0:
    return lUnknown
  case parts[0].toLowerAscii()
  of "infrastructure", "infra": lInfrastructure
  of "core": lCore
  of "engine": lEngine
  of "gate": lGate
  of "frontend": lFrontend
  of "cli": lCli
  else: lUnknown

# ═══════════════════════════════════════════════════════════════════════
# Import path extraction
# ═══════════════════════════════════════════════════════════════════════

func extractImportPath(line: string): string =
  ## Extract the module path from an import/from statement.
  let stripped = line.strip()

  if stripped.startsWith("from "):
    let rest = stripped[5..^1]
    let sp = rest.find(' ')
    if sp >= 0:
      return rest[0..<sp].strip()
    return rest.strip()

  if stripped.startsWith("import "):
    let rest = stripped[7..^1]
    # Bracket import: import core/[foo, bar]
    let bracket = rest.find('[')
    if bracket >= 0:
      return rest[0..<bracket].strip().strip(chars = {'/'})
    let sp = rest.find(' ')
    if sp >= 0:
      return rest[0..<sp].strip()
    return rest.strip()

  ""

# ═══════════════════════════════════════════════════════════════════════
# Iterative Tarjan SCC Algorithm
# ═══════════════════════════════════════════════════════════════════════

func tarjanSCC(nodes: seq[string],
               edges: Table[string, seq[string]]): seq[seq[string]] =
  ## Iterative Tarjan's SCC — returns strongly connected components.
  ## Stack-safe: uses explicit DFS stack instead of recursion.
  if nodes.len == 0:
    return @[]

  var idx = 0
  var nodeIndex = initTable[string, int]()
  var lowlink = initTable[string, int]()
  var onStack = initHashSet[string]()
  var stack: seq[string]
  var sccs: seq[seq[string]]

  type Frame = object
    node: string
    neighborPos: int

  for startNode in nodes:
    if startNode in nodeIndex:
      continue

    var dfs: seq[Frame]
    nodeIndex[startNode] = idx
    lowlink[startNode] = idx
    inc idx
    stack.add(startNode)
    onStack.incl(startNode)
    dfs.add(Frame(node: startNode, neighborPos: 0))

    while dfs.len > 0:
      var frame = addr dfs[^1]
      let neighbors = edges.getOrDefault(frame.node, @[])

      if frame.neighborPos < neighbors.len:
        let neighbor = neighbors[frame.neighborPos]
        inc frame.neighborPos

        if neighbor notin nodeIndex:
          nodeIndex[neighbor] = idx
          lowlink[neighbor] = idx
          inc idx
          stack.add(neighbor)
          onStack.incl(neighbor)
          dfs.add(Frame(node: neighbor, neighborPos: 0))
        elif neighbor in onStack:
          lowlink[frame.node] = min(lowlink[frame.node],
                                    nodeIndex[neighbor])
      else:
        # All neighbors processed — pop frame
        let completed = dfs[^1].node
        dfs.setLen(dfs.len - 1)

        if lowlink[completed] == nodeIndex[completed]:
          var component: seq[string]
          while true:
            let w = stack[^1]
            stack.setLen(stack.len - 1)
            onStack.excl(w)
            component.add(w)
            if w == completed:
              break
          sccs.add(component)

        # Propagate lowlink to parent
        if dfs.len > 0:
          let parentNode = dfs[^1].node
          lowlink[parentNode] = min(lowlink[parentNode],
                                    lowlink[completed])

  sccs

# ═══════════════════════════════════════════════════════════════════════
# Proc / Func detection helpers
# ═══════════════════════════════════════════════════════════════════════

func stripIndent(line: string): string = line.strip()

func isTopLevelProcDecl(stripped: string): bool =
  stripped.startsWith("proc ") or stripped.startsWith("proc`")

func isTopLevelFuncDecl(stripped: string): bool =
  stripped.startsWith("func ") or stripped.startsWith("func`")

func isTopLevelDecl(stripped: string): bool =
  ## Any top-level declaration that delimits a proc body boundary.
  isTopLevelProcDecl(stripped) or isTopLevelFuncDecl(stripped) or
  stripped.startsWith("method ") or stripped.startsWith("template ") or
  stripped.startsWith("macro ") or stripped.startsWith("iterator ") or
  stripped.startsWith("converter ") or stripped.startsWith("type ") or
  stripped.startsWith("const ") or stripped.startsWith("var ") or
  stripped.startsWith("let ") or stripped.startsWith("import ") or
  stripped.startsWith("from ") or stripped.startsWith("include ") or
  stripped.startsWith("when ") or stripped.startsWith("if ") or
  stripped.startsWith("elif ") or stripped.startsWith("else") or
  stripped.startsWith("for ") or stripped.startsWith("while ") or
  stripped.startsWith("block ") or stripped.startsWith("case ")

func extractProcName(decl: string): string =
  ## Extract the proc/func name from a declaration line (already stripped).
  var s = decl
  # Skip keyword
  for prefix in ["proc ", "proc`", "func ", "func`", "method "]:
    if s.startsWith(prefix):
      s = s[prefix.len .. ^1]
      break

  # Backtick-quoted name
  if s.startsWith("`"):
    let endTick = s.find('`', 1)
    if endTick >= 0:
      return s[1..<endTick]

  # Regular identifier
  var name = ""
  for ch in s:
    if ch.isAlphaNumeric() or ch == '_':
      name.add(ch)
    else:
      break
  name

func hasImpurePragma(lines: seq[string], declLine: int): bool =
  ## Check if the proc has a pragma that prevents func conversion.
  # Check declaration line itself
  let searchStart = max(0, declLine - 1)
  let searchEnd = min(declLine + 4, lines.len)
  for i in searchStart ..< searchEnd:
    let ln = lines[i]
    if "{.sideEffect" in ln or "{.importc" in ln or "{.importcpp" in ln or
       "{.dynlib" in ln or "{.effectPattern" in ln or "axiomEffect" in ln or
       "{.cdecl" in ln or "{.stdcall" in ln or "{.fastcall" in ln or
       "{.exportc" in ln or "{.header" in ln or "{.link" in ln or
       "{.deprecated" in ln or "{.error" in ln or "{.noSideEffect" in ln:
      return true
  false

func hasRaisesPragma(lines: seq[string], declLine: int): bool =
  ## Check if the proc already has a {.raises: ...} pragma.
  let searchEnd = min(declLine + 5, lines.len)
  for i in declLine ..< searchEnd:
    if "{.raises:" in lines[i]:
      return true
  false

func bodyIndentOf(lines: seq[string], declLine: int): int =
  ## Find the body start line and return its indentation.
  for j in declLine ..< min(declLine + 6, lines.len):
    if '=' in lines[j]:
      let stripped = lines[j].strip()
      # The "=" might be at end of line (proc foo() =)
      # or after the return type
      let eqPos = lines[j].rfind('=')
      if eqPos >= 0:
        # Ensure it's not == or != or <=
        if eqPos + 1 < lines[j].len and lines[j][eqPos + 1] == '=':
          continue
        if eqPos > 0 and lines[j][eqPos - 1] == '!' :
          continue
        if eqPos > 0 and lines[j][eqPos - 1] == '<' :
          continue
        # Body indent is the indent of the next line after =
        if j + 1 < lines.len:
          let nextLine = lines[j + 1]
          let nextStripped = nextLine.strip()
          if nextStripped.len == 0:
            # Blank line — use decl indent + 2
            return lines[declLine].len - lines[declLine].strip().len + 2
          return nextLine.len - nextStripped.len
        else:
          return lines[declLine].len - lines[declLine].strip().len + 2
  # Forward declaration (no body)
  -1

func findProcBodies(lines: seq[string]): seq[ProcInfo] =
  ## Parse all proc/func declarations and map their body ranges.
  result = @[]
  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()

    # Skip comments and blank lines
    if stripped.len == 0 or stripped.startsWith("#"):
      inc i
      continue

    # Only look at top-level proc declarations (column 0)
    let indent = lines[i].len - stripped.len
    if indent > 0:
      inc i
      continue

    if isTopLevelProcDecl(stripped):
      let name = extractProcName(stripped)
      if name.len == 0:
        inc i
        continue

      let declLine = i
      let isFunc = isTopLevelFuncDecl(stripped)
      let impure = hasImpurePragma(lines, i)
      let hasRaises = hasRaisesPragma(lines, i)

      let bodyIndent = bodyIndentOf(lines, declLine)
      if bodyIndent < 0:
        # Forward declaration
        result.add(ProcInfo(name: name, line: declLine,
                            bodyStart: declLine, endLine: declLine + 1,
                            isFunc: isFunc, hasSideEffect: impure,
                            hasRaisesPragma: hasRaises))
        inc i
        continue

      # Find body end: next line at same or lesser indentation (non-blank)
      var endLine = declLine + 1
      while endLine < lines.len:
        let ln = lines[endLine]
        let lnStripped = ln.strip()
        if lnStripped.len == 0:
          inc endLine
          continue
        let lnIndent = ln.len - lnStripped.len
        if lnIndent <= indent:
          break
        inc endLine

      result.add(ProcInfo(name: name, line: declLine,
                          bodyStart: declLine + 1, endLine: endLine,
                          isFunc: isFunc, hasSideEffect: impure,
                          hasRaisesPragma: hasRaises))

    inc i

# ═══════════════════════════════════════════════════════════════════════
# Call graph construction
# ═══════════════════════════════════════════════════════════════════════

func buildCallGraph(lines: seq[string],
                    procs: seq[ProcInfo]): Table[string, seq[string]] =
  ## Build caller→callee edges for procs within the same file.
  result = initTable[string, seq[string]]()

  var procNames = initHashSet[string]()
  for p in procs:
    procNames.incl(p.name)

  for p in procs:
    var callees: seq[string]
    for i in p.bodyStart ..< p.endLine:
      if i >= lines.len:
        break
      let line = lines[i]
      let stripped = line.strip()
      if stripped.startsWith("#"):
        continue

      for callee in procNames:
        if callee == p.name:
          continue
        # Search for the callee name as a whole-word identifier
        var pos = 0
        while pos < line.len:
          let idx = line.find(callee, pos)
          if idx < 0:
            break
          let beforeOk = idx == 0 or not line[idx - 1].isAlphaNumeric()
          let afterIdx = idx + callee.len
          let afterOk = afterIdx >= line.len or not line[afterIdx].isAlphaNumeric()
          if beforeOk and afterOk:
            callees.add(callee)
            break  # one edge per (caller, callee) pair
          pos = idx + 1

    if callees.len > 0:
      # Deduplicate while preserving order
      var seen = initHashSet[string]()
      var unique: seq[string]
      for c in callees:
        if c notin seen:
          seen.incl(c)
          unique.add(c)
      result[p.name] = unique

# ═══════════════════════════════════════════════════════════════════════
# Text transformation helpers
# ═══════════════════════════════════════════════════════════════════════

func replaceProcWithFunc(source: string, lineIdx: int): string =
  ## Replace the 'proc' keyword with 'func' on lineIdx (0-based).
  var lines = source.splitLines()
  if lineIdx < 0 or lineIdx >= lines.len:
    return source

  let line = lines[lineIdx]
  let stripped = line.strip()

  if stripped.startsWith("proc "):
    let indent = line.len - stripped.len
    lines[lineIdx] = line[0..<indent] & "func " & stripped[5..^1]
  elif stripped.startsWith("proc`"):
    let indent = line.len - stripped.len
    lines[lineIdx] = line[0..<indent] & "func`" & stripped[4..^1]

  lines.join("\n")

# ═══════════════════════════════════════════════════════════════════════
# Compiler verification
# ═══════════════════════════════════════════════════════════════════════

proc runNimCheck(filePath: string): bool {.axiomEffect: IoEffect.} =
  ## Compile-check a single file. Returns true on success.
  let nim = findExe("nim")
  if nim.len == 0:
    return false
  let cmd = nim & " c --hints:off --warnings:off --errorMax:1 " &
            "--path:src " & filePath
  try:
    let (output, exitCode) = execCmdEx(cmd)
    discard output
    exitCode == 0
  except CatchableError:
    false

# ═══════════════════════════════════════════════════════════════════════
# SUBCOMMAND: proc-to-func
# ═══════════════════════════════════════════════════════════════════════

proc cmdProcToFunc(dryRun, verify: bool) {.axiomEffect: IoEffect.} =
  log("=== proc-to-func: Call-graph-aware proc→func conversion ===")
  log("Scope: src/core/")

  let files = findNimFiles("src/core")
  log("Found " & $files.len & " .nim files")
  log("")

  var totalCandidates = 0
  var totalConverted = 0
  var totalSkipped = 0
  var totalRolledBack = 0

  for filePath in files:
    var source: string
    try:
      source = readFile(filePath)
    except CatchableError:
      continue

    let lines = source.splitLines()

    # 1. Find all proc declarations
    let procs = findProcBodies(lines)

    # 2. Filter: only `proc` (not `func`), not impure
    var eligible: seq[ProcInfo]
    for p in procs:
      if p.isFunc:
        continue
      if p.hasSideEffect:
        inc totalSkipped
        continue
      eligible.add(p)

    if eligible.len == 0:
      continue

    # 3. Build intra-file call graph
    let callGraph = buildCallGraph(lines, eligible)

    # 4. Tarjan SCC
    var nodeNames: seq[string]
    for p in eligible:
      nodeNames.add(p.name)

    let sccs = tarjanSCC(nodeNames, callGraph)

    # 5. Convert SCCs of size 1 (no mutual recursion)
    var modified = source
    var fileConverted = 0

    for scc in sccs:
      if scc.len > 1:
        # Mutually recursive group — skip
        totalSkipped += scc.len
        continue

      let procName = scc[0]
      var target: ProcInfo
      var found = false
      for p in eligible:
        if p.name == procName:
          target = p
          found = true
          break
      if not found:
        continue

      inc totalCandidates
      modified = replaceProcWithFunc(modified, target.line)
      inc fileConverted
      inc totalConverted

    if fileConverted == 0:
      continue

    if dryRun:
      log("[DRY-RUN] " & filePath & ": " & $fileConverted & " proc→func")
      continue

    # 6. Write transformed source
    try:
      writeFile(filePath, modified)
    except CatchableError as e:
      log("  ERROR writing " & filePath & ": " & e.msg)
      continue

    log("  Converted " & $fileConverted & " proc(s) in " & filePath)

    # 7. Verify — roll back on failure
    if verify:
      if not runNimCheck(filePath):
        log("  ⚠  Verification FAILED — rolling back " & filePath)
        try:
          writeFile(filePath, source)
        except CatchableError:
          discard  # axiom:best-effort(rollback write failure — source already backed up in 'source' variable, non-fatal for the conversion tool)
        inc totalRolledBack
        totalConverted -= fileConverted
      else:
        log("  ✓  Verified " & filePath)

  log("")
  log("── Summary ──")
  log("  Candidates found:   " & $totalCandidates)
  log("  Converted:          " & $totalConverted)
  log("  Skipped (recursive/impure): " & $totalSkipped)
  if verify:
    log("  Rolled back (nim check fail): " & $totalRolledBack)

# ═══════════════════════════════════════════════════════════════════════
# SUBCOMMAND: narrow-raises
# ═══════════════════════════════════════════════════════════════════════

proc cmdNarrowRaises() {.axiomEffect: IoEffect.} =
  log("=== narrow-raises: Find {.raises: [Exception].} patterns ===")
  log("")

  let files = findNimFiles("src")
  var violations: seq[RaisesViolation]

  for filePath in files:
    var lines: seq[string]
    try:
      lines = readFile(filePath).splitLines()
    except CatchableError:
      continue

    for i, line in lines:
      let trimmed = line.strip()
      # Match: {.raises: [Exception].}  (broadly: any raises with only Exception)
      if "{.raises:" notin trimmed or "[Exception]" notin trimmed:
        continue
      # Skip if it also has more specific exceptions
      let raisesPart = trimmed
      if "[CatchableError]" in raisesPart or "[ValueError]" in raisesPart or
         "[IOError]" in raisesPart or "[KeyError]" in raisesPart or
         "[RangeDefect]" in raisesPart or "[Defect]" in raisesPart or
         "[OSError]" in raisesPart or "[ IOError" in raisesPart:
        # Has specific exceptions — still worth flagging if Exception is there
        discard

      # Search backward for the enclosing proc/func name
      var procName = "(module-level)"
      for j in countdown(i, max(0, i - 15)):
        let prev = lines[j].strip()
        if prev.startsWith("proc ") or prev.startsWith("func ") or
           prev.startsWith("method "):
          procName = extractProcName(prev)
          break

      violations.add(RaisesViolation(
        file: filePath,
        line: i + 1,
        procName: procName,
        raisesClause: trimmed
      ))

  # Report
  log("Found " & $violations.len & " {.raises: [Exception].} violations:")
  log("")

  for v in violations:
    log("  " & v.file & ":" & $v.line)
    log("    proc:  " & v.procName)
    log("    pragma: " & v.raisesClause)
    log("")

  log("Total: " & $violations.len)

# ═══════════════════════════════════════════════════════════════════════
# SUBCOMMAND: migrate-imports
# ═══════════════════════════════════════════════════════════════════════

proc cmdMigrateImports() {.axiomEffect: IoEffect.} =
  log("=== migrate-imports: Find import boundary violations ===")
  log("Layer ordering: infrastructure < core < engine < gate < frontend < cli")
  log("")

  let files = findNimFiles("src")
  var violations: seq[ImportViolation]

  for filePath in files:
    let sourceLayer = layerFromPath(filePath)
    if sourceLayer == lUnknown:
      continue

    var lines: seq[string]
    try:
      lines = readFile(filePath).splitLines()
    except CatchableError:
      continue

    for i, line in lines:
      let stripped = line.strip()

      # Skip comments
      if stripped.startsWith("#") or stripped.startsWith("##"):
        continue

      # Only process import/from lines
      if not (stripped.startsWith("import ") or stripped.startsWith("from ")):
        continue

      let importPath = extractImportPath(stripped)
      if importPath.len == 0:
        continue

      # Skip stdlib / bare module imports (no slash = likely stdlib)
      if '/' notin importPath and '.' notin importPath:
        continue

      # Normalize dotted imports to slash form
      let normalizedPath = importPath.replace('.', '/')
      let targetLayer = layerFromImportPath(normalizedPath)
      if targetLayer == lUnknown:
        continue

      # Violation: lower layer importing from a higher layer
      if ord(targetLayer) > ord(sourceLayer):
        violations.add(ImportViolation(
          file: filePath,
          line: i + 1,
          importPath: importPath,
          sourceLayer: layerName(sourceLayer),
          targetLayer: layerName(targetLayer)
        ))

  # Report
  log("Found " & $violations.len & " import boundary violations:")
  log("")

  for v in violations:
    log("  " & v.file & ":" & $v.line)
    log("    " & v.sourceLayer & " → " & v.targetLayer & ": " & v.importPath)
  log("")
  log("Total: " & $violations.len)

# ═══════════════════════════════════════════════════════════════════════
# SUBCOMMAND: collect-debt
# ═══════════════════════════════════════════════════════════════════════

func parseDebtPragma(line: string): DebtParams =
  ## Parse an axiomDebt pragma via shared DebtParams SSOT.
  ## Handles both old pragma syntax and new macro call syntax.
  parseDebtParams(line)

proc cmdCollectDebt() {.axiomEffect: IoEffect.} =
  log("=== collect-debt: Scan for axiomDebt pragmas ===")
  log("")

  let files = findNimFiles("src")
  var debts: seq[DebtRecord]

  for filePath in files:
    var lines: seq[string]
    try:
      lines = readFile(filePath).splitLines()
    except CatchableError:
      continue

    for i, line in lines:
      let trimmed = line.strip()
      if "axiomDebt" notin trimmed:
        continue
      if "{." notin trimmed:
        continue

      let params = parseDebtPragma(trimmed)
      if params.valid:
        debts.add(DebtRecord(
          id: params.id,
          file: filePath,
          line: i + 1,
          category: if params.category.len > 0: params.category else: "unspecified",
          severity: $params.severity,
          ttl: params.ttl
        ))

  # Sort by ID
  debts.sort(proc (a, b: DebtRecord): int = cmp(a.id, b.id))

  # ── Report collected debt records ──
  # docs/DEBT_REGISTRY.md is a projection of data/debt_registry.json and is
  # generated solely by bin/debt_engine --codegen.
  log("")
  log("── Collected Debt Records ──")
  log("  total: " & $debts.len)
  for d in debts:
    log("  " & d.id & "  " & d.category & "  " & d.severity & "  ttl=" & d.ttl &
        "  " & d.file & ":" & $d.line)

  # ── Category breakdown ──
  log("")
  log("── Category Breakdown ──")
  var cats = initTable[string, int]()
  for d in debts:
    cats.mgetOrPut(d.category, 0) += 1
  for cat, count in cats:
    log("  " & cat & ": " & $count)

# ═══════════════════════════════════════════════════════════════════════
# SUBCOMMAND: add-raises
# ═══════════════════════════════════════════════════════════════════════

func hasFileLevelPushRaises(content: string): bool =
  ## Check if file already contains {.push raises: ...} pragma.
  for line in content.splitLines():
    let trimmed = line.strip()
    if "{.push raises:" in trimmed:
      return true
  false

func hasAxiomPrelude(content: string): bool =
  ## Check if file imports or uses axiomPrelude.
  for line in content.splitLines():
    let trimmed = line.strip()
    if "axiomPrelude" in trimmed:
      return true
  false

func injectPushRaises(content: string): string =
  ## Prepend {.push raises: [].} at the very top of the file.
  "{.push raises: [].}\n" & content

proc runNimCheckWithOutput(filePath: string): tuple[output: string;
                                                     exitCode: int] {.
    axiomEffect: IoEffect.} =
  ## Compile-check a file, returning both stdout+stderr and exit code.
  let nim = findExe("nim")
  if nim.len == 0:
    return (output: "", exitCode: -1)
  let cmd = nim & " c --hints:off --path:src " & filePath
  try:
    execCmdEx(cmd)
  except CatchableError:
    (output: "", exitCode: -1)

proc atomicWriteFile(target, content: string) {.axiomEffect: IoEffect.} =
  ## Write content to target using atomic temp+rename pattern.
  let tmpPath = target & ".tmp"
  try:
    writeFile(tmpPath, content)
    safeMoveFile(tmpPath, target)
  except CatchableError as e:
    try:
      removeFile(tmpPath)
    except CatchableError:
      discard  # axiom:best-effort(temp file cleanup on write failure — raised error already propagates, cleanup is best-effort hygiene)
    raise (ref CatchableError)(msg: e.msg)

proc cmdAddRaises(dryRun: bool) {.axiomEffect: IoEffect.} =
  log("=== add-raises: Inject {.push raises: [].} where safe ===")
  log("")

  let targetDir = "src"
  let files = findNimFiles(targetDir)
  log("Scanning " & $files.len & " .nim files in " & targetDir)
  log("")

  # Create a probe dir within the project tree — relative imports resolve
  # correctly only when the probe file lives under the same --path root.
  let tmpDir = "src/.axiom_raises_probe"
  try:
    createDir(tmpDir)
  except CatchableError:
    log("ERROR: cannot create temp dir " & tmpDir)
    quit(1)
  let probeFile = tmpDir / "zprobe.nim"

  var
    skippedExisting = 0
    skippedPrelude = 0
    injectable = 0
    rejected = 0
    results: seq[RaisesCheckResult]

  for filePath in files:
    var source: string
    try:
      source = readFile(filePath)
    except CatchableError:
      continue

    # Skip files with existing {.push raises:}
    if hasFileLevelPushRaises(source):
      inc skippedExisting
      continue

    # Skip files with axiomPrelude
    if hasAxiomPrelude(source):
      inc skippedPrelude
      continue

    # Create temp copy with injection and run nim check
    let injected = injectPushRaises(source)
    try:
      writeFile(probeFile, injected)
    except CatchableError:
      continue

    let (output, exitCode) = runNimCheckWithOutput(probeFile)

    # Clean up temp file between iterations
    try:
      removeFile(probeFile)
    except CatchableError:
      discard  # axiom:best-effort(probe file cleanup failure is non-fatal; analysis result already captured)

    if exitCode == 0:
      # File accepts {.push raises: [].} cleanly
      inc injectable
      results.add(RaisesCheckResult(
        file: filePath,
        injectable: true,
        errorLines: @[]
      ))

      if dryRun:
        log("  [DRY-RUN] Would inject: " & filePath)
      else:
        try:
          atomicWriteFile(filePath, injected)
          log("  ✓ Injected " & filePath)
        except CatchableError as e:
          log("  ERROR writing " & filePath & ": " & e.msg)
          inc rejected
    else:
      # Parse error lines for can raise / Effect / Error
      var errorLines: seq[string]
      for line in output.splitLines():
        let trimmed = line.strip()
        if "can raise" in trimmed or "Effect" in trimmed or
           "Error:" in trimmed:
          errorLines.add(trimmed)
      if errorLines.len == 0:
        # Fallback: keep raw output lines that look relevant
        for line in output.splitLines():
          let trimmed = line.strip()
          if trimmed.len > 0 and not trimmed.startsWith("--"):
            errorLines.add(trimmed)
            if errorLines.len >= 5:
              break

      inc rejected
      results.add(RaisesCheckResult(
        file: filePath,
        injectable: false,
        errorLines: errorLines
      ))
      log("  ✗ NOT injectable: " & filePath)
      for errLine in errorLines:
        log("    " & errLine)

  # Clean up temp dir
  try:
    removeDir(tmpDir)
  except CatchableError:
    discard  # axiom:best-effort(temp directory cleanup failure is non-fatal; scan results already recorded)

  # ── Summary ──
  log("")
  log("── Summary ──")
  log("  Skipped (already has push raises): " & $skippedExisting)
  log("  Skipped (axiomPrelude):           " & $skippedPrelude)
  log("  Injectable:                        " & $injectable)
  log("  Rejected:                          " & $rejected)

  if not dryRun and injectable > 0:
    log("")
    log("Injected {.push raises: [].} into " & $injectable & " file(s)")
  elif dryRun and injectable > 0:
    log("")
    log("Would inject {.push raises: [].} into " & $injectable & " file(s)")

  if rejected > 0:
    log("")
    log("⚠ " & $rejected & " file(s) cannot accept {.push raises: [].} — CI gate will FAIL")
    quit(1)

# ═══════════════════════════════════════════════════════════════════════
# Usage & CLI dispatcher
# ═══════════════════════════════════════════════════════════════════════

proc usage() {.axiomEffect: IoEffect.} =
  log("ast-refine: Axiom AST-based code refinement tool")
  log("Usage: ast-refine <subcommand> [options]")
  log("")
  log("Subcommands:")
  log("  proc-to-func      Convert eligible procs to funcs using call-graph analysis")
  log("                      Options: --dry-run  --verify")
  log("  narrow-raises     Find {.raises: [Exception].} patterns for review")
  log("  migrate-imports   Find import boundary violations")
  log("  collect-debt      Scan for axiomDebt pragmas, generate debt ledger")
  log("  add-raises        Inject {.push raises: [].} where compiler-verified safe")
  log("                      Options: --dry-run")

proc main() {.axiomEffect: IoEffect.} =
  if paramCount() < 1:
    usage()
    quit(1)

  let subcmd = paramStr(1)

  case subcmd
  of "proc-to-func":
    var dryRun = false
    var verify = false
    for i in 2 .. paramCount():
      let arg = paramStr(i)
      if arg == "--dry-run":
        dryRun = true
      elif arg == "--verify":
        verify = true
    cmdProcToFunc(dryRun, verify)

  of "narrow-raises":
    cmdNarrowRaises()

  of "migrate-imports":
    cmdMigrateImports()

  of "collect-debt":
    cmdCollectDebt()

  of "add-raises":
    var dryRun = false
    for i in 2 .. paramCount():
      let arg = paramStr(i)
      if arg == "--dry-run":
        dryRun = true
    cmdAddRaises(dryRun)

  of "--help", "-h", "help":
    usage()

  else:
    log("Error: unknown subcommand '" & subcmd & "'")
    usage()
    quit(1)

when isMainModule:
  main()
