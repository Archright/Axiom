## tools/symbol_extractor.nim — PEG-based symbol dependency graph + Tarjan SCC extraction
##
## Uses std/pegs for Nim syntax scanning instead of tree-sitter CST walking.
## Two symbols end up in the same module only if they form a strongly-connected
## dependency cycle. Independent clusters become separate files with explicit `import` edges.
##
## Usage:
##   symbol_extractor --analyze <file>            Print dependency graph + SCCs
##   symbol_extractor --extract <file>            Split into SCC modules + facade
##   symbol_extractor --all --threshold 500       Scan src/ for large files
##   symbol_extractor --dry-run --extract <file>  Preview without writing
##
## Compile:
##   nim c -d:release --hints:off -o:bin/symbol_extractor tools/symbol_extractor.nim
# axiom:theater-fix

import core/trusted/layer_declaration
axiomLayer "tools"

import std/[os, strutils, algorithm, sets, tables, sequtils, osproc, hashes, options, pegs]

# ── Types ────────────────────────────────────────────────────────────────────

type
  SymbolId* = distinct int
    ## Index into the SymbolTable's `symbols` seq.

proc `==`*(a, b: SymbolId): bool {.inline.} =
  int(a) == int(b)

proc hash*(x: SymbolId): Hash {.inline.} =
  hash(int(x))

proc `<`*(a, b: SymbolId): bool {.inline.} =
  int(a) < int(b)

type
  SymbolKind* = enum
    symFunc       ## func proc
    symProc       ## proc / method / converter / template / macro
    symType       ## type section / object declaration / enum declaration
    symConst      ## const_section bindings
    symLet        ## let_section bindings
    symVar        ## var_section bindings
    symImport     ## import statement (external module)
    symOther      ## catch-all for unrecognized declarations

  SymbolDef* = object
    ## A single declared symbol with its source location.
    id*: SymbolId
    name*: string           ## e.g. "parseAllImports"
    kind*: SymbolKind
    startLine*: int         ## Line number where declaration starts
    endLine*: int           ## Line number where declaration ends
    text*: string           ## raw source text of the declaration
    modulePath*: string     ## external module path for symImport

  SymbolGraph* = object
    ## Directed dependency graph: edge A→B means A depends on B.
    symbols*: seq[SymbolDef]
    ## id → seq[SymbolId] adjacency list (forward edges = depends-on)
    edges*: Table[SymbolId, seq[SymbolId]]
    ## Reverse adjacency for quick "depended-by" queries
    reverseEdges*: Table[SymbolId, seq[SymbolId]]
    ## Quick name → id lookup
    nameIndex*: Table[string, SymbolId]

  SCCComponent* = object
    ## A strongly-connected component (a maximal cycle of inter-dependent symbols).
    members*: seq[SymbolId]
    moduleIndex*: int       ## assigned module number after extraction

  ExtractMode* = enum
    modeAnalyze
    modeExtract

  ExtractConfig* = object
    mode*: ExtractMode
    file*: string
    allMode*: bool
    dryRun*: bool
    threshold*: int         ## min line count to trigger extraction

  ExtractResult* = object
    filePath*: string
    lineCount*: int
    symbolCount*: int
    edgeCount*: int
    sccCount*: int
    singleSccs*: int        ## SCCs with exactly 1 member (no cycle)
    multiSccs*: int         ## SCCs with 2+ members (actual cycles)
    modulesGenerated*: int
    success*: bool
    skipped*: bool

# ── Pure: Helpers ───────────────────────────────────────────────────────────

proc baseName*(filePath: string): string =
  let (_, name, _) = splitFile(filePath)
  name

proc countLeadingSpaces*(s: string): int =
  var i = 0
  while i < s.len and (s[i] == ' ' or s[i] == '\t'):
    inc i
  result = i

proc isWordChar*(c: char): bool =
  c.isAlphaNumeric or c == '_'

proc findFirstIdentifierAfter(line: string; startAt: int): string =
  ## Find the first identifier character sequence starting at or after `startAt`.
  var i = startAt
  while i < line.len and line[i].isSpaceAscii:
    inc i
  if i >= line.len: return ""
  if not (line[i].isAlphaAscii or line[i] == '_'): return ""
  let start = i
  while i < line.len and (line[i].isAlphaNumeric or line[i] == '_'):
    inc i
  line[start ..< i]

proc classifyKeyword*(kw: string): SymbolKind =
  case kw
  of "func": symFunc
  of "proc", "method", "converter", "template", "macro", "iterator": symProc
  of "type": symType
  of "const": symConst
  of "let": symLet
  of "var": symVar
  of "import", "from": symImport
  else: symOther

# ── Pure: Identifier collection ─────────────────────────────────────────────

proc collectIdentifiers*(text: string; outIdents: var seq[string]) =
  ## Collect all identifier-like sequences from text.
  var i = 0
  while i < text.len:
    if text[i].isAlphaAscii or text[i] == '_':
      let start = i
      while i < text.len and (text[i].isAlphaNumeric or text[i] == '_'):
        inc i
      outIdents.add(text[start ..< i])
    else:
      inc i

proc collectIdentifiersDedup*(text: string): seq[string] =
  var raw: seq[string]
  collectIdentifiers(text, raw)
  var seen = initHashSet[string]()
  result = @[]
  for ident in raw:
    if ident notin seen:
      seen.incl(ident)
      result.add(ident)

# ── Pure: Import path extraction ────────────────────────────────────────────

proc expandBracketImports*(text: string; seen: var HashSet[string];
                             output: var seq[string]) =
  ## Parse bracket-syntax imports: "std/[os, strutils]" → "std/os", "std/strutils"
  var remaining = text.strip()
  while remaining.len > 0:
    let bracketOpen = remaining.find('[')
    if bracketOpen < 0:
      for item in remaining.split(','):
        let t = item.strip()
        if t.len > 0 and t notin seen:
          seen.incl(t)
          output.add(t)
      break
    let lastCommaBefore = remaining.rfind(',', 0, bracketOpen)
    if lastCommaBefore >= 0:
      let before = remaining[0 ..< lastCommaBefore]
      for item in before.split(','):
        let t = item.strip()
        if t.len > 0 and t notin seen:
          seen.incl(t)
          output.add(t)
    let prefixStart = if lastCommaBefore >= 0: lastCommaBefore + 1 else: 0
    let bracketClose = remaining.find(']', bracketOpen + 1)
    if bracketClose < 0:
      for item in remaining[prefixStart .. ^1].split(','):
        let t = item.strip()
        if t.len > 0 and t notin seen:
          seen.incl(t)
          output.add(t)
      break
    var prefix = remaining[prefixStart ..< bracketOpen].strip()
    if not prefix.endsWith("/"):
      prefix.add("/")
    let inner = remaining[bracketOpen + 1 ..< bracketClose]
    for item in inner.split(','):
      let expanded = prefix & item.strip()
      if expanded.len > 0 and expanded notin seen:
        seen.incl(expanded)
        output.add(expanded)
    remaining = remaining[bracketClose + 1 .. ^1].strip()
    if remaining.len > 0 and remaining[0] == ',':
      remaining = remaining[1 .. ^1].strip()

proc parseImportPaths*(source: string): seq[string] =
  ## Extract all import module paths from a source string.
  result = @[]
  var seen = initHashSet[string]()
  var inMultiline = false
  for rawLine in source.splitLines():
    let trimmed = rawLine.strip()
    if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("##"):
      inMultiline = false
      continue
    if trimmed.startsWith("from "):
      let rest = trimmed[5 .. ^1]
      let idx = rest.find(" import")
      if idx > 0:
        expandBracketImports(rest[0 ..< idx].strip(), seen, result)
      inMultiline = false
      continue
    if trimmed.startsWith("import "):
      let rest = trimmed[7 .. ^1]
      if rest.strip().endsWith(","):
        expandBracketImports(rest[0 .. ^2].strip(), seen, result)
        inMultiline = true
      else:
        expandBracketImports(rest, seen, result)
        inMultiline = false
      continue
    if inMultiline:
      if trimmed.endsWith(","):
        expandBracketImports(trimmed[0 .. ^2].strip(), seen, result)
      else:
        expandBracketImports(trimmed, seen, result)
        inMultiline = false

# ── Pure: Graph construction ────────────────────────────────────────────────

proc newSymbolGraph*(): SymbolGraph =
  SymbolGraph(
    symbols: @[],
    edges: initTable[SymbolId, seq[SymbolId]](),
    reverseEdges: initTable[SymbolId, seq[SymbolId]](),
    nameIndex: initTable[string, SymbolId](),
  )

proc addSymbol*(graph: var SymbolGraph; name: string; kind: SymbolKind;
                startLine, endLine: int; text: string;
                modulePath: string = ""): SymbolId =
  ## Add a symbol to the graph and return its id.
  let id = SymbolId(graph.symbols.len)
  graph.symbols.add(SymbolDef(
    id: id, name: name, kind: kind,
    startLine: startLine, endLine: endLine,
    text: text, modulePath: modulePath,
  ))
  if name.len > 0:
    graph.nameIndex[name] = id
  graph.edges[id] = @[]
  graph.reverseEdges[id] = @[]
  id

proc addEdge*(graph: var SymbolGraph; src, dst: SymbolId) =
  ## Add a directed dependency edge src → dst (src depends on dst).
  if src == dst: return  # no self-loops
  var edges = graph.edges.getOrDefault(src, @[])
  if dst notin edges:
    edges.add(dst)
    graph.edges[src] = edges
    var rev = graph.reverseEdges.getOrDefault(dst, @[])
    if src notin rev:
      rev.add(src)
    graph.reverseEdges[dst] = rev

proc resolveName*(graph: SymbolGraph; name: string): Option[SymbolId] =
  ## Look up a symbol by name. Returns none if not found.
  if name in graph.nameIndex:
    some(graph.nameIndex[name])
  else:
    none(SymbolId)

# ── PEG-based symbol extraction ─────────────────────────────────────────────

# Compile-time PEG patterns for keyword detection
let procKwPeg = peg"""proc / func / method / template / macro / iterator / converter"""
let typeKwPeg = peg"""type"""
let importKwPeg = peg"""import / from"""
let valKwPeg = peg"""const / let / var"""

type
  Declaration = object
    kind*: SymbolKind
    name*: string
    startLine*: int
    endLine*: int
    text*: string
    modulePath*: string

proc hasWordBoundaryMatch*(text: string; name: string): bool =
  ## Check if `name` appears in `text` with proper word boundaries.
  if name.len == 0 or text.len < name.len: return false
  var pos = 0
  while pos <= text.len - name.len:
    if text[pos ..< pos + name.len] == name:
      let beforeOk = pos == 0 or not isWordChar(text[pos - 1])
      let afterOk = pos + name.len >= text.len or not isWordChar(text[pos + name.len])
      if beforeOk and afterOk:
        return true
    inc pos
  result = false

proc scanProcDeclarations*(source: string): seq[Declaration] =
  ## Scan source for proc/func/method/template/macro declarations using PEG.
  result = @[]
  let lines = source.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i]
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#") or stripped.startsWith("##"):
      inc i
      continue
    if match(stripped, procKwPeg):
      let kwLen = stripped.find("[a-zA-Z_]")
      if kwLen < 0:
        inc i
        continue
      let name = findFirstIdentifierAfter(stripped, kwLen)
      if name.len == 0:
        inc i
        continue
      # Collect full declaration body (multi-line support)
      var bodyLines = @[line]
      var j = i + 1
      var parenDepth = 0
      var braceDepth = 0
      # Count parentheses/braces in signature
      for ch in stripped:
        if ch == '(': inc parenDepth
        elif ch == ')':
          if parenDepth > 0: dec parenDepth
        elif ch == '{': inc braceDepth
        elif ch == '}':
          if braceDepth > 0: dec braceDepth
      # Signature may span multiple lines
      while j < lines.len and (parenDepth > 0 or braceDepth > 0):
        bodyLines.add(lines[j])
        for ch in lines[j]:
          if ch == '(': inc parenDepth
          elif ch == ')': dec parenDepth
          elif ch == '{': inc braceDepth
          elif ch == '}': dec braceDepth
        inc j
      # Continue collecting until we hit body or dedent past declaration
      if j < lines.len:
        let nextLine = lines[j].strip()
        let declIndent = countLeadingSpaces(line)
        if nextLine.len > 0 and not nextLine.startsWith("#"):
          let nextIndent = countLeadingSpaces(lines[j])
          if nextLine.startsWith("=") or nextLine.startsWith(":") or
             nextIndent <= declIndent:
            bodyLines.add(lines[j])
            inc j
            while j < lines.len:
              let bl = lines[j]
              if bl.strip().len == 0:
                bodyLines.add(bl)
                inc j
                continue
              let ci = countLeadingSpaces(bl)
              if ci > declIndent:
                bodyLines.add(bl)
                inc j
              else:
                break
      let bodyText = bodyLines.join("\n")
      result.add(Declaration(
        kind: classifyKeyword(stripped[0..0]),
        name: name,
        startLine: i + 1,
        endLine: bodyLines.len + i,
        text: bodyText,
      ))
    inc i

proc scanTypeDeclarations*(source: string): seq[Declaration] =
  ## Scan source for type declarations using PEG.
  result = @[]
  let lines = source.splitLines()
  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()
    if stripped.len == 0 or stripped.startsWith("#") or stripped.startsWith("##"):
      inc i
      continue
    if match(stripped, typeKwPeg):
      var j = i
      var bodyLines = @[lines[i]]
      inc j
      while j < lines.len:
        let bl = lines[j].strip()
        if bl.len == 0:
          bodyLines.add(lines[j])
          inc j
          continue
        if bl.startsWith("#"):
          bodyLines.add(lines[j])
          inc j
          continue
        let curIndent = countLeadingSpaces(lines[i])
        let newIndent = countLeadingSpaces(lines[j])
        if newIndent <= curIndent:
          break
        bodyLines.add(lines[j])
        inc j
      for bl in bodyLines:
        let strippedBl = bl.strip()
        if strippedBl.len == 0 or strippedBl.startsWith("#"): continue
        let eqPos = strippedBl.find('=')
        if eqPos > 0:
          let typeName = strippedBl[0 ..< eqPos].strip()
          if typeName.len > 0 and (typeName[0].isAlphaAscii or typeName[0] == '_'):
            result.add(Declaration(
              kind: symType,
              name: typeName,
              startLine: i + 1,
              endLine: bodyLines.len + i,
              text: bodyLines.join("\n"),
            ))
    inc i

proc scanImportStatements*(source: string): seq[Declaration] =
  ## Scan source for import statements using PEG.
  result = @[]
  let lines = source.splitLines()
  var i = 0
  var inMultiline = false
  while i < lines.len:
    let line = lines[i]
    let stripped = line.strip()
    if stripped.len == 0:
      inMultiline = false
      inc i
      continue
    if stripped.startsWith("#") or stripped.startsWith("##"):
      inMultiline = false
      inc i
      continue
    if match(stripped, importKwPeg):
      var importTexts: seq[string] = @[]
      if stripped.startsWith("from "):
        let rest = stripped[5 .. ^1]
        let idx = rest.find(" import")
        if idx > 0:
          importTexts.add(rest[0 ..< idx].strip())
        else:
          importTexts.add(rest.strip())
      elif stripped.startsWith("import "):
        let rest = stripped[7 .. ^1]
        var hs = initHashSet[string]()
        expandBracketImports(rest, hs, importTexts)
        if rest.strip().endsWith(","):
          inMultiline = true
        else:
          inMultiline = false
      elif inMultiline:
        var hs = initHashSet[string]()
        if stripped.endsWith(","):
          expandBracketImports(stripped[0 .. ^2].strip(), hs, importTexts)
        else:
          expandBracketImports(stripped, hs, importTexts)
          inMultiline = false
      for impPath in importTexts:
        result.add(Declaration(
          kind: symImport,
          name: impPath,
          startLine: i + 1,
          endLine: i + 1,
          text: stripped,
          modulePath: impPath,
        ))
    inc i

proc scanValueBindings*(source: string): seq[Declaration] =
  ## Scan source for const/let/var binding declarations.
  result = @[]
  let lines = source.splitLines()
  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()
    if stripped.len == 0 or stripped.startsWith("#") or stripped.startsWith("##"):
      inc i
      continue
    if match(stripped, valKwPeg):
      var kind: SymbolKind = symConst
      case stripped[0].toLowerAscii
      of 'c': kind = symConst
      of 'l': kind = symLet
      of 'v': kind = symVar
      else: discard
      var j = i
      var bodyLines = @[lines[i]]
      inc j
      while j < lines.len:
        let bl = lines[j].strip()
        if bl.len == 0:
          bodyLines.add(lines[j])
          inc j
          continue
        if bl.startsWith("#"):
          bodyLines.add(lines[j])
          inc j
          continue
        let curIndent = countLeadingSpaces(lines[i])
        let newIndent = countLeadingSpaces(lines[j])
        if newIndent <= curIndent and match(bl, valKwPeg):
          break
        let eqPos = bl.find('=')
        let namesStr = if eqPos > 0: bl[0 ..< eqPos].strip() else: bl
        for nm in namesStr.split(','):
          let cleaned = nm.strip()
          if cleaned.len > 0 and (cleaned[0].isAlphaAscii or cleaned[0] == '_'):
            result.add(Declaration(
              kind: kind,
              name: cleaned,
              startLine: i + 1,
              endLine: bodyLines.len + i,
              text: bodyLines.join("\n"),
            ))
        bodyLines.add(lines[j])
        inc j
    inc i

proc extractSymbolsWithPeg*(source: string): seq[Declaration] =
  ## Main entry point: extract all symbol declarations from source using PEG.
  result = @[]
  result.add(scanProcDeclarations(source))
  result.add(scanTypeDeclarations(source))
  result.add(scanImportStatements(source))
  result.add(scanValueBindings(source))
  result.sort(proc(a, b: Declaration): int = cmp(a.startLine, b.startLine))

proc buildGraphFromDeclarations*(decls: openArray[Declaration];
                                   graph: var SymbolGraph) =
  ## Build symbol dependency graph from extracted declarations.
  for decl in decls:
    discard graph.addSymbol(decl.name, decl.kind,
      decl.startLine, decl.endLine, decl.text,
      modulePath = decl.modulePath)

  let symCount = graph.symbols.len
  for i in 0 ..< symCount:
    let sid = SymbolId(i)
    let sym = graph.symbols[i]
    if sym.kind == symImport: continue

    var seen = initHashSet[string]()
    for j in 0 ..< symCount:
      if i == j: continue
      let other = graph.symbols[j]
      if other.name.len == 0: continue
      if other.name in seen: continue
      if hasWordBoundaryMatch(sym.text, other.name):
        seen.incl(other.name)
        if other.name != sym.name:
          let resolved = graph.resolveName(other.name)
          if resolved.isSome:
            addEdge(graph, sid, resolved.get)

# ── Core: Analyze a single file ─────────────────────────────────────────────

proc analyzeFile*(filePath: string): SymbolGraph =
  ## Parse a file with PEG and build its symbol dependency graph.
  result = newSymbolGraph()
  let absPath = filePath.expandFilename
  if not fileExists(absPath):
    stderr.writeLine("ERROR: File not found: " & absPath)
    return

  let source = try:
    readFile(absPath)
  except IOError as e:
    stderr.writeLine("ERROR: Cannot read " & absPath & ": " & e.msg)
    return

  if source.len == 0:
    return

  let decls = extractSymbolsWithPeg(source)
  buildGraphFromDeclarations(decls, result)

# ── CLI: Argument parsing ───────────────────────────────────────────────────

proc parseExtractArgs*(): ExtractConfig =
  result = ExtractConfig(
    mode: modeAnalyze, file: "", allMode: false,
    dryRun: false, threshold: 500,
  )
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg == "--analyze":
      result.mode = modeAnalyze
      if i + 1 < args.len and not args[i + 1].startsWith("-"):
        result.file = args[i + 1]
        i += 2
      else:
        inc i
    elif arg == "--extract":
      result.mode = modeExtract
      if i + 1 < args.len and not args[i + 1].startsWith("-"):
        result.file = args[i + 1]
        i += 2
      else:
        inc i
    elif arg == "--all":
      result.allMode = true
      inc i
    elif arg == "--dry-run":
      result.dryRun = true
      inc i
    elif arg == "--threshold" and i + 1 < args.len:
      try:
        result.threshold = parseInt(args[i + 1])
      except ValueError as e:
        stderr.writeLine("WARNING: Invalid --threshold value: " & e.msg)
      i += 2
    elif arg == "--help" or arg == "-h":
      stdout.writeLine("Usage: symbol_extractor [options]")
      stdout.writeLine("")
      stdout.writeLine("Extract independent modules from Nim files using")
      stdout.writeLine("Tarjan's SCC algorithm on symbol dependency graphs.")
      stdout.writeLine("")
      stdout.writeLine("Options:")
      stdout.writeLine("  --analyze <file>       Print dependency graph + SCC analysis")
      stdout.writeLine("  --extract <file>       Split into SCC modules + facade")
      stdout.writeLine("  --all                  Scan src/ for files exceeding threshold")
      stdout.writeLine("  --dry-run              Preview without writing files")
      stdout.writeLine("  --threshold <N>        Min line count to extract (default: 500)")
      stdout.writeLine("  --help, -h             Show this help message")
      stdout.writeLine("")
      stdout.writeLine("Examples:")
      stdout.writeLine("  symbol_extractor --analyze src/core/engine/parser.nim")
      stdout.writeLine("  symbol_extractor --extract tools/ast_splitter.nim --dry-run")
      stdout.writeLine("  symbol_extractor --all --threshold 300")
      quit(0)
    elif arg.startsWith("-"):
      stderr.writeLine("Unknown option: " & arg)
      stderr.writeLine("Use --help for usage information.")
      quit(1)
    else:
      result.file = arg
      inc i

# ── Core: Print analysis report ──────────────────────────────────────────────

proc computeInterSCCDeps*(sccs: seq[SCCComponent];
                           graph: SymbolGraph): seq[seq[int]]

proc printAnalysisReport*(graph: SymbolGraph; sccs: seq[SCCComponent];
                            filePath: string) =
  ## Print a human-readable analysis report to stdout.
  let interSCCDeps = computeInterSCCDeps(sccs, graph)
  let lineCount = try:
    let src = readFile(filePath)
    src.splitLines().len
  except IOError: 0

  stdout.writeLine("=== symbol_extractor analysis ===")
  stdout.writeLine("File: " & filePath)
  stdout.writeLine("Lines: " & $lineCount)
  stdout.writeLine("Symbols: " & $graph.symbols.len)

  var edgeCount = 0
  for sid, targets in graph.edges:
    if graph.symbols[int(sid)].kind != symImport:
      edgeCount += targets.len
  stdout.writeLine("Dependency edges: " & $edgeCount)
  stdout.writeLine("SCCs: " & $sccs.len)
  stdout.writeLine("")

  stdout.writeLine("--- Symbols ---")
  for sym in graph.symbols:
    let kindStr = case sym.kind
    of symFunc: "func"
    of symProc: "proc"
    of symType: "type"
    of symConst: "const"
    of symLet: "let"
    of symVar: "var"
    of symImport: "import"
    of symOther: "other"
    stdout.writeLine("  [" & kindStr & "] " & sym.name)

  stdout.writeLine("")
  stdout.writeLine("--- Dependencies ---")
  for i in 0 ..< graph.symbols.len:
    let sid = SymbolId(i)
    let targets = graph.edges.getOrDefault(sid, @[])
    if targets.len > 0:
      let name = graph.symbols[i].name
      var deps: seq[string]
      for t in targets:
        deps.add(graph.symbols[int(t)].name)
      stdout.writeLine("  " & name & " -> " & deps.join(", "))

  stdout.writeLine("")
  stdout.writeLine("--- Strongly Connected Components ---")
  for i in 0 ..< sccs.len:
    let scc = sccs[i]
    var names: seq[string]
    for m in scc.members:
      names.add(graph.symbols[int(m)].name)
    let depStrs = interSCCDeps[i].mapIt($it)
    let depLabel = if depStrs.len > 0: " depends on SCC " & depStrs.join(", ") else: " (root - no inter-SCC deps)"
    stdout.writeLine("  SCC " & $i & " [" & $scc.members.len & " symbols]: " &
                      names.join(", ") & depLabel)

  stdout.writeLine("")
  stdout.writeLine("--- Module Plan ---")
  let name = baseName(filePath)
  stdout.writeLine("  Facade: " & name & ".nim")
  for i in 0 ..< sccs.len:
    stdout.writeLine("  Module: " & name & "_scc" & $i & ".nim (" &
                      $sccs[i].members.len & " symbols)")

# ── Algorithm: Tarjan's SCC ──────────────────────────────────────────────────

type
  TarjanState = object
    index*: int
    stack*: seq[SymbolId]
    indices*: Table[SymbolId, int]
    lowlinks*: Table[SymbolId, int]
    onStack*: HashSet[SymbolId]
    components*: seq[SCCComponent]

proc tarjanStrongConnect*(graph: SymbolGraph; v: SymbolId;
                           state: var TarjanState) =
  ## Tarjan's strong-connect subroutine.
  state.indices[v] = state.index
  state.lowlinks[v] = state.index
  inc state.index
  state.stack.add(v)
  state.onStack.incl(v)

  let neighbors = graph.edges.getOrDefault(v, @[])
  for w in neighbors:
    if w notin state.indices:
      tarjanStrongConnect(graph, w, state)
      state.lowlinks[v] = min(state.lowlinks[v], state.lowlinks[w])
    elif w in state.onStack:
      state.lowlinks[v] = min(state.lowlinks[v], state.indices[w])

  if state.lowlinks[v] == state.indices[v]:
    var comp = SCCComponent(members: @[])
    while true:
      let w = state.stack[^1]
      state.stack.setLen(state.stack.len - 1)
      state.onStack.excl(w)
      comp.members.add(w)
      if w == v: break
    comp.members.sort(proc(a, b: SymbolId): int = cmp(int(a), int(b)))
    state.components.add(comp)

proc findSCCs*(graph: SymbolGraph): seq[SCCComponent] =
  ## Run Tarjan's algorithm and return all strongly-connected components.
  var state = TarjanState(
    index: 0,
    stack: @[],
    indices: initTable[SymbolId, int](),
    lowlinks: initTable[SymbolId, int](),
    onStack: initHashSet[SymbolId](),
    components: @[],
  )
  let n = graph.symbols.len
  for i in 0 ..< n:
    let v = SymbolId(i)
    if v notin state.indices:
      tarjanStrongConnect(graph, v, state)
  for i in 0 ..< state.components.len:
    state.components[i].moduleIndex = i
  state.components

# ── Pure: Module generation ──────────────────────────────────────────────────

proc buildSCCModule*(scc: SCCComponent; graph: SymbolGraph;
                      moduleName: string;
                      importModules: seq[string]): string =
  ## Generate the Nim source for a single SCC module.
  result = ""
  result.add("## " & moduleName & ".nim\n")
  result.add("## Auto-generated by symbol_extractor.\n")
  result.add("## SCC module: " & $scc.members.len & " symbol(s).\n")
  result.add("## Members: ")
  for idx in 0 ..< scc.members.len:
    if idx > 0: result.add(", ")
    result.add(graph.symbols[int(scc.members[idx])].name)
  result.add("\n")
  result.add("\n")
  result.add("{.push raises: [].}\n")
  result.add("\n")

  if importModules.len > 0:
    let joined = importModules.join(", ")
    result.add("import " & joined & "\n")
    result.add("\n")

  for sid in scc.members:
    let sym = graph.symbols[int(sid)]
    if sym.kind == symImport:
      result.add("import " & sym.modulePath & "\n")
    else:
      result.add(sym.text)
      if sym.text.len > 0 and sym.text[^1] != '\n':
        result.add("\n")
      result.add("\n")

proc buildFacade*(originalName: string; moduleNames: seq[string]): string =
  ## Generate a thin facade that re-exports all SCC modules.
  result = ""
  result.add("## " & originalName & ".nim\n")
  result.add("## Facade - auto-generated by symbol_extractor.\n")
  result.add("## Re-exports all extracted SCC modules for backward compatibility.\n")
  result.add("\n")
  if moduleNames.len == 0:
    result.add("# No modules extracted - this file is already minimal.\n")
    return
  let joined = moduleNames.join(", ")
  result.add("import " & joined & "\n")
  result.add("\n")
  result.add("export " & joined & "\n")

proc buildHeaderPragma*(): string =
  "{.push raises: [].}\n"

# ── Pure: Dependency edge analysis for module import generation ──────────────

proc computeInterSCCDeps*(sccs: seq[SCCComponent];
                           graph: SymbolGraph): seq[seq[int]] =
  ## For each SCC, compute which *other* SCCs it depends on.
  result = newSeq[seq[int]](sccs.len)
  var memberToSCC = initTable[SymbolId, int]()
  for i in 0 ..< sccs.len:
    for member in sccs[i].members:
      memberToSCC[member] = i
  for i in 0 ..< sccs.len:
    var deps: seq[int]
    for member in sccs[i].members:
      let neighbors = graph.edges.getOrDefault(member, @[])
      for neighbor in neighbors:
        if neighbor in memberToSCC:
          let depSCC = memberToSCC[neighbor]
          if depSCC != i and depSCC notin deps:
            deps.add(depSCC)
    deps.sort()
    result[i] = deps

# ── Core: Extract a single file ─────────────────────────────────────────────

proc extractSingleFile*(filePath: string; dryRun: bool): ExtractResult =
  ## Analyze and extract SCC modules from a single file.
  result = ExtractResult(filePath: filePath, success: false, skipped: false)

  let absPath = filePath.expandFilename
  if not fileExists(absPath):
    stderr.writeLine("ERROR: File not found: " & absPath)
    return

  let source = try:
    readFile(absPath)
  except IOError as e:
    stderr.writeLine("ERROR: Cannot read " & absPath & ": " & e.msg)
    return

  result.lineCount = source.splitLines().len
  if result.lineCount < 500:
    stderr.writeLine("SKIP: " & absPath & " has " & $result.lineCount & " lines (< 500)")
    result.success = true
    result.skipped = true
    return

  let graph = analyzeFile(absPath)
  result.symbolCount = graph.symbols.len
  var totalEdges = 0
  for _, targets in graph.edges:
    totalEdges += targets.len
  result.edgeCount = totalEdges

  let sccs = findSCCs(graph)
  result.sccCount = sccs.len

  if sccs.len <= 1:
    stderr.writeLine("SKIP: " & absPath & " has only 1 SCC - nothing to extract")
    result.success = true
    result.skipped = true
    return

  for scc in sccs:
    if scc.members.len == 1: inc result.singleSccs
    else: inc result.multiSccs

  printAnalysisReport(graph, sccs, absPath)

  if dryRun:
    stderr.writeLine("[DRY RUN] Would generate " & $sccs.len & " modules + facade")
    result.success = true
    result.modulesGenerated = sccs.len
    return

  let interSCCDeps = computeInterSCCDeps(sccs, graph)
  let dir = parentDir(absPath)
  let name = baseName(absPath)

  var moduleNames: seq[string]
  for i in 0 ..< sccs.len:
    let moduleName = name & "_scc" & $i
    moduleNames.add(moduleName)
    let importModules = interSCCDeps[i].mapIt(name & "_scc" & $it)
    let content = buildSCCModule(sccs[i], graph, moduleName, importModules)
    let modulePath = dir / (moduleName & ".nim")
    try:
      writeFile(modulePath, content)
      stderr.writeLine("  WROTE: " & modulePath)
    except IOError as e:
      stderr.writeLine("  ERROR writing " & modulePath & ": " & e.msg)
      result.success = false
      return
    inc result.modulesGenerated

  let facadeContent = buildFacade(name, moduleNames)
  try:
    writeFile(absPath, facadeContent)
    stderr.writeLine("  WROTE: " & absPath & " (facade)")
  except IOError as e:
    stderr.writeLine("  ERROR writing facade: " & e.msg)
    result.success = false
    return

  stderr.writeLine("  Verifying compilation...")
  try:
    let cmd = "nim check --hints:off " & quoteShell(absPath)
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode == 0:
      stderr.writeLine("  Compilation verified")
      result.success = true
    else:
      stderr.writeLine("  Compilation FAILED - rolling back")
      for line in output.splitLines():
        stderr.writeLine("    " & line)
      for i in 0 ..< sccs.len:
        let modulePath = dir / (name & "_scc" & $i & ".nim")
        try:
          if fileExists(modulePath): removeFile(modulePath)
        except OSError as e:
          stderr.writeLine("  WARNING: rollback removeFile failed: " & e.msg)
      try:
        writeFile(absPath, source)
      except IOError as e:
        stderr.writeLine("  WARNING: rollback writeFile failed: " & e.msg)
      result.success = false
  except CatchableError as e:
    stderr.writeLine("  ERROR running nim check: " & e.msg)
    result.success = false

# ── Core: Find large files in src/ ──────────────────────────────────────────

proc findLargeFiles*(threshold: int): seq[string] =
  ## Walk src/ and tools/ for .nim files exceeding the line threshold.
  result = @[]
  for searchDir in ["src", "tools"]:
    if not dirExists(searchDir): continue
    for path in walkDirRec(searchDir):
      if not path.endsWith(".nim"): continue
      let name = baseName(path)
      if "_scc" in name: continue
      try:
        let src = readFile(path)
        if src.splitLines().len >= threshold:
          result.add(path)
      except IOError:
        discard
  result.sort()

# ── Main ─────────────────────────────────────────────────────────────────────

proc main*() =
  let config = parseExtractArgs()

  if config.file.len > 0:
    if config.mode == modeAnalyze:
      let graph = analyzeFile(config.file)
      let sccs = findSCCs(graph)
      printAnalysisReport(graph, sccs, config.file)
    else:
      let result = extractSingleFile(config.file, config.dryRun)
      stdout.writeLine("")
      stdout.writeLine("=== symbol_extractor result ===")
      stdout.writeLine("File: " & result.filePath)
      stdout.writeLine("Lines: " & $result.lineCount)
      stdout.writeLine("Symbols: " & $result.symbolCount)
      stdout.writeLine("Edges: " & $result.edgeCount)
      stdout.writeLine("SCCs: " & $result.sccCount & " (" &
                       $result.singleSccs & " single, " &
                       $result.multiSccs & " multi)")
      stdout.writeLine("Modules generated: " & $result.modulesGenerated)
      stdout.writeLine("Success: " & $result.success)
      stdout.writeLine("Skipped: " & $result.skipped)
      if not result.success and not result.skipped:
        quit(1)
    return

  if config.allMode:
    let files = findLargeFiles(config.threshold)
    stdout.writeLine("Found " & $files.len & " files exceeding " & $config.threshold & " lines")
    var successCount = 0
    var skipCount = 0
    var failCount = 0
    for f in files:
      stdout.writeLine("")
      stdout.writeLine("--- " & f & " ---")
      let result = extractSingleFile(f, config.dryRun)
      if result.success: inc successCount
      if result.skipped: inc skipCount
      if not result.success and not result.skipped: inc failCount
    stdout.writeLine("")
    stdout.writeLine("=== symbol_extractor summary ===")
    stdout.writeLine("Files: " & $files.len &
                     " (success: " & $successCount &
                     ", skipped: " & $skipCount &
                     ", failed: " & $failCount & ")")
    if config.dryRun:
      stdout.writeLine("(DRY RUN - no files were modified)")
    if failCount > 0:
      quit(1)
    return

  stderr.writeLine("No action specified. Use --analyze <file>, --extract <file>, or --all.")
  stderr.writeLine("Use --help for usage information.")
  quit(1)

when isMainModule:
  main()
