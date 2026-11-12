## tools/ast_splitter.nim — Text-based 3-way file splitter
##
## Splits large Nim files (500+ lines) into three sub-modules:
##   - `[name]_types.nim`  — type_section declarations
##   - `[name]_funcs.nim`  — func_declaration nodes
##   - `[name]_procs.nim`  — proc/method/converter/template/macro declarations
##
## The original file is replaced with a Composition Root that imports
## and re-exports all three sub-modules.
##
## Safety: backs up originals, runs `nim check` after split, restores on failure.
## Idempotency: skips sub-modules that already exist.
##
## Usage:
##   ast_splitter [--dry-run] [--file <path>] [--all]
##
## Compile:
##   nim c -d:release --hints:off -o:bin/ast_splitter tools/ast_splitter.nim

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, strutils, algorithm, sets, tables, osproc]

# ── Types ────────────────────────────────────────────────────────────────────

type
  SplitConfig* = object
    dryRun*: bool
    files*: seq[string]
    allMode*: bool

  DeclCategory* = enum
    catTypes,    ## type_section
    catFuncs,    ## func_declaration
    catProcs,    ## proc/method/converter/template/macro_declaration
    catImport,   ## import_statement / from_statement
    catOther,    ## const_section, var_section, let_section, etc.
    catSkip      ## when_statement, standalone pragma — goes to composition root

  ExtractedDecl* = object
    ## A single top-level declaration extracted from the CST.
    category*: DeclCategory
    name*: string         ## Symbol name (for diagnostics)
    startByte*: uint32    ## Byte offset of first character
    endByte*: uint32      ## Byte offset past last character
    text*: string         ## Source text slice

  HeaderInfo* = object
    ## Parsed module header: doc comments, pragmas, and import lines.
    docLines*: seq[string]
    pragmaLines*: seq[string]
    importLines*: seq[string]
    headerEndByte*: uint32  ## Byte offset where header ends / body begins

  SplitResult* = object
    filePath*: string
    typesPath*: string
    funcsPath*: string
    procsPath*: string
    typesCount*: int
    funcsCount*: int
    procsCount*: int
    otherCount*: int
    success*: bool
    skipped*: bool        ## true if sub-modules already exist (idempotent)

# ── Constants ────────────────────────────────────────────────────────────────

const
  GrandfatherFiles*: array[14, string] = [
    "unified_gate_runner.nim",
    "documentation_first_gate.nim",
    "architecture_config_gate.nim",
    "debt_scan_gate.nim",
    "logging_policy_gate.nim",
    "codec_codegen.nim",
    "gate_memo.nim",
    "shell_ast_analyzer.nim",
    "semantic_boundary_guard.nim",
    "dependency_rules_gate.nim",
    "nim_check_runner.nim",
    "nimtry_cli.nim",
    "pipeline_orchestrator.nim",
    "task_schema.nim",
  ]

  TypeNodeTypes* = [
    "type_section",
  ]

  FuncNodeTypes* = [
    "func_declaration",
  ]

  ProcNodeTypes* = [
    "proc_declaration",
    "method_declaration",
    "converter_declaration",
    "template_declaration",
    "macro_declaration",
  ]

  ImportNodeTypes* = [
    "import_statement",
    "from_statement",
  ]

  OtherDeclTypes* = [
    "const_section",
    "var_section",
    "let_section",
    "enum_declaration",
    "object_declaration",
    "tuple_declaration",
    "alias_declaration",
    "section_constant",
    "section_variable",
    "section_definition",
  ]

  SkipNodeTypes* = [
    "when",
    "pragma_statement",
  ]

# ── Pure Functions: Classification ───────────────────────────────────────────

func classifyNode*(nodeType: string): DeclCategory {.raises: [].} =
  ## Classify a tree-sitter node type into a declaration category.
  if nodeType in TypeNodeTypes: return catTypes
  if nodeType in FuncNodeTypes: return catFuncs
  if nodeType in ProcNodeTypes: return catProcs
  if nodeType in ImportNodeTypes: return catImport
  if nodeType in SkipNodeTypes: return catSkip
  catOther

func extractNodeText*(source: string; startByte, endByte: uint32): string {.raises: [].} =
  ## Extract source text for a node using byte offsets.
  let s = startByte.int
  let e = endByte.int
  if s < 0 or e > source.len or s >= e:
    return ""
  source[s ..< e]

func baseName*(filePath: string): string {.raises: [].} =
  ## Extract the base name (without extension) from a file path.
  let (dir, name, ext) = splitFile(filePath)
  name

# ── Pure Functions: Import Parsing (regex-based) ────────────────────────────

func expandImportsFromText*(text: string; seen: var HashSet[string];
                            output: var seq[string]) {.raises: [].} =
  ## Parse an import text line, handling bracket syntax BEFORE comma splitting.
  ## E.g. "std/[os, strutils], core/results" → "std/os", "std/strutils", "core/results"
  ## The key insight: brackets must be expanded before commas are split,
  ## otherwise "std/[os" loses its closing "]" and breaks syntax.
  var remaining = text.strip()

  while remaining.len > 0:
    # Find the next bracket open
    let bracketOpen = remaining.find('[')
    if bracketOpen < 0:
      # No more brackets — split remaining by comma as plain imports
      for item in remaining.split(','):
        let t = item.strip()
        if t.len > 0 and t notin seen:
          seen.incl(t)
          output.add(t)
      break

    # Find the last comma before '[' — everything before it is standalone imports
    let lastCommaBefore = remaining.rfind(',', 0, bracketOpen)
    if lastCommaBefore >= 0:
      let before = remaining[0 ..< lastCommaBefore]
      for item in before.split(','):
        let t = item.strip()
        if t.len > 0 and t notin seen:
          seen.incl(t)
          output.add(t)

    # The bracket prefix is text between last comma (or start) and '['
    let prefixStart = if lastCommaBefore >= 0: lastCommaBefore + 1 else: 0

    # Find the matching bracket close
    let bracketClose = remaining.find(']', bracketOpen + 1)
    if bracketClose < 0:
      # Unclosed bracket — treat the rest as plain imports
      for item in remaining[prefixStart .. ^1].split(','):
        let t = item.strip()
        if t.len > 0 and t notin seen:
          seen.incl(t)
          output.add(t)
      break

    # Extract prefix and ensure it ends with '/'
    var prefix = remaining[prefixStart ..< bracketOpen].strip()
    if not prefix.endsWith("/"):
      prefix.add("/")
    let inner = remaining[bracketOpen + 1 ..< bracketClose]
    for item in inner.split(','):
      let expanded = prefix & item.strip()
      if expanded.len > 0 and expanded notin seen:
        seen.incl(expanded)
        output.add(expanded)

    # Continue after the closing bracket
    remaining = remaining[bracketClose + 1 .. ^1].strip()
    # Skip comma separator between imports
    if remaining.len > 0 and remaining[0] == ',':
      remaining = remaining[1 .. ^1].strip()

func parseAllImports*(source: string): seq[string] {.raises: [].} =
  ## Parse all import targets from a Nim source string.
  ## Returns deduplicated module path tokens (e.g. "std/strutils", "core/types/results").
  ## Handles bracket syntax: std/[os, strutils] → "std/os", "std/strutils"
  result = @[]
  var seen = initHashSet[string]()
  var inMultilineImport = false

  for rawLine in source.splitLines():
    let trimmed = rawLine.strip()

    # Skip empty lines and comments
    if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("##"):
      inMultilineImport = false
      continue

    # `from X import symbol`
    if trimmed.startsWith("from "):
      let rest = trimmed[5 .. ^1]
      let importIdx = rest.find(" import")
      if importIdx > 0:
        let moduleName = rest[0 ..< importIdx].strip()
        expandImportsFromText(moduleName, seen, result)
      inMultilineImport = false
      continue

    # `import X, Y, Z` (possibly multi-line)
    if trimmed.startsWith("import "):
      let rest = trimmed[7 .. ^1]
      if rest.strip().endsWith(","):
        expandImportsFromText(rest[0 .. ^2].strip(), seen, result)
        inMultilineImport = true
      else:
        expandImportsFromText(rest, seen, result)
        inMultilineImport = false
      continue

    # Continuation of multi-line import
    if inMultilineImport:
      if trimmed.endsWith(","):
        expandImportsFromText(trimmed[0 .. ^2].strip(), seen, result)
      else:
        expandImportsFromText(trimmed, seen, result)
        inMultilineImport = false

# ── Pure Functions: Header Extraction ────────────────────────────────────────

func extractHeader*(source: string; bodyStartByte: uint32): HeaderInfo {.raises: [].} =
  ## Extract module header (doc comments, pragmas, imports) from source.
  ## bodyStartByte marks where declarations begin.
  result = HeaderInfo(
    docLines: @[],
    pragmaLines: @[],
    importLines: @[],
    headerEndByte: bodyStartByte,
  )

  let headerText = if bodyStartByte > 0: source[0 ..< bodyStartByte.int] else: ""
  if headerText.len == 0:
    return

  var inPragmaBlock = false
  for line in headerText.splitLines():
    let stripped = line.strip()
    if stripped.len == 0:
      continue
    if stripped.startsWith("##"):
      result.docLines.add(line)
    elif stripped.startsWith("{.") or stripped.startsWith(".}"):
      result.pragmaLines.add(line)
      if stripped.contains("push"):
        inPragmaBlock = true
      elif stripped.contains("pop"):
        inPragmaBlock = false
    elif stripped.startsWith("import ") or stripped.startsWith("from "):
      result.importLines.add(line)
    elif inPragmaBlock:
      result.pragmaLines.add(line)

# ── Pure Functions: Module Generation ────────────────────────────────────────

func buildModuleHeader*(moduleName: string; description: string;
                        imports: seq[string]): string {.raises: [].} =
  ## Build a clean module header with doc comment and imports.
  result = ""
  result.add("## " & moduleName & "\n")
  result.add("## " & description & "\n")
  result.add("## Auto-generated by ast_splitter — review imports and adjust.\n")
  result.add("\n")
  for imp in imports:
    result.add("import " & imp & "\n")

func buildSubModule*(moduleName: string; description: string;
                     imports: seq[string];
                     declarations: seq[ExtractedDecl];
                     extraImports: openArray[string] = []): string {.raises: [].} =
  ## Build a complete sub-module file content.
  ## extraImports: additional imports to add (e.g. importing the types module).
  result = buildModuleHeader(moduleName, description, imports)
  # Add extra imports (e.g. from _types module for shared declarations)
  for extra in extraImports:
    result.add("import " & extra & "\n")
  if declarations.len > 0:
    result.add("\n")
    for decl in declarations:
      result.add(decl.text)
      # Ensure trailing newline
      if decl.text.len > 0 and decl.text[^1] != '\n':
        result.add("\n")
      result.add("\n")

func forceExportConstVars*(content: string): string {.raises: [].} =
  ## Post-process types module content to add '*' export markers to
  ## private const/var/let declaration names. This makes them accessible
  ## to importing sub-modules (_funcs, _procs).
  ## e.g. "  GateTag = \"[unified-gate]\"" → "  GateTag* = \"[unified-gate]\""
  result = ""
  var inSection = false  # Inside a const/var/let section
  for line in content.splitLines():
    var outLine = line
    let stripped = line.strip()

    # Detect section headers
    if stripped in ["const", "var", "let"]:
      inSection = true
      result.add(line & "\n")
      continue

    # If not in a section, or line is empty/comment/doc, pass through
    if not inSection or stripped.len == 0 or stripped.startsWith("##") or stripped.startsWith("#"):
      # Exit section on non-indented, non-comment, non-empty content
      # (doc comments inside sections are allowed — they describe the next declaration)
      if inSection and stripped.len > 0 and
         not stripped.startsWith("##") and not stripped.startsWith("#") and
         not stripped.startsWith(" ") and not stripped.startsWith("\t"):
        inSection = false
      result.add(line & "\n")
      continue

    # Inside a const/var/let section: look for "  Name = " or "  Name =" patterns
    # that don't already have '*' export marker
    if stripped.len > 0 and not stripped.startsWith("##") and not stripped.startsWith("#"):
      # Find the first identifier in the line
      var j = 0
      # Skip leading whitespace
      while j < stripped.len and (stripped[j] == ' ' or stripped[j] == '\t'):
        inc j
      let identStart = j
      # Read identifier characters
      while j < stripped.len and (stripped[j].isAlphaNumeric or stripped[j] == '_'):
        inc j
      let identEnd = j
      if identEnd > identStart:
        let ident = stripped[identStart ..< identEnd]
        # Check if followed by '=' (declaration) and not already exported
        var k = j
        while k < stripped.len and stripped[k] == ' ':
          inc k
        if k < stripped.len and stripped[k] == '=' and '*' notin stripped[identStart ..< identEnd + 1]:
          # Add '*' export marker after the identifier
          let prefix = line[0 ..< line.len - stripped.len + identEnd]
          let suffix = line[line.len - stripped.len + identEnd .. ^1]
          outLine = prefix & "*" & suffix

    result.add(outLine & "\n")

func buildCompositionRoot*(originalName: string;
                           subModules: openArray[string]): string {.raises: [].} =
  ## Build the composition root that imports and re-exports sub-modules.
  result = ""
  result.add("## " & originalName & "\n")
  result.add("## Composition root — auto-generated by ast_splitter.\n")
  result.add("## Re-exports all split sub-modules for backward compatibility.\n")
  result.add("\n")
  # Import all sub-modules
  let importList = subModules.join(", ")
  result.add("import " & importList & "\n")
  result.add("\n")
  # Export all sub-modules
  result.add("export " & importList & "\n")

# ── Text-based Declaration Scanner ──────────────────────────────────────────

type
  TopDecl* = object
    ## A top-level declaration found by line-scanning.
    category*: DeclCategory
    name*: string
    startLine*: int          ## 0-based line number
    endLine*: int            ## 0-based line number (inclusive)
    startByte*: uint32       ## Byte offset of first character
    endByte*: uint32         ## Byte offset past last character
    text*: string            ## Source text slice

func lineStartByte*(source: string; lineNum: int): uint32 {.raises: [].} =
  ## Compute byte offset of a 0-based line number.
  var offset = 0'u32
  var currentLine = 0
  for ch in source:
    if currentLine == lineNum:
      return offset
    inc offset
    if ch == '\n':
      inc currentLine
  return offset

func isTopLevelKeyword*(line: string): bool {.raises: [].} =
  ## Check if a line starts with a top-level declaration keyword.
  let trimmed = line.strip()
  if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("##"):
    return false
  result = true
  case trimmed[0]
  of 't':
    result = trimmed.startsWith("type ") or trimmed == "type" or
             trimmed.startsWith("type$") or
             trimmed.startsWith("func ") or trimmed == "func" or
             trimmed.startsWith("func$") or
             trimmed.startsWith("template ") or trimmed == "template" or
             trimmed.startsWith("template$") or
             trimmed.startsWith("const ") or trimmed == "const" or
             trimmed.startsWith("const$") or
             trimmed.startsWith("when ") or trimmed == "when" or
             trimmed.startsWith("when$")
  of 'p', 'm':
    result = trimmed.startsWith("proc ") or trimmed == "proc" or
             trimmed.startsWith("proc$") or
             trimmed.startsWith("method ") or trimmed == "method" or
             trimmed.startsWith("method$")
  of 'c':
    result = trimmed.startsWith("converter ") or trimmed == "converter" or
             trimmed.startsWith("converter$") or
             trimmed.startsWith("var ") or trimmed == "var" or
             trimmed.startsWith("var$")
  of 'l':
    result = trimmed.startsWith("let ") or trimmed == "let" or
             trimmed.startsWith("let$")
  of 'i', 'f':
    result = trimmed.startsWith("import ") or trimmed.startsWith("from ")
  of '{', '.':
    result = trimmed.startsWith("{.") or trimmed.startsWith(".}")
  else:
    result = false

func classifyFromKeyword*(line: string): DeclCategory {.raises: [].} =
  ## Classify a declaration based on its leading keyword.
  let trimmed = line.strip()
  if trimmed.startsWith("type ") or trimmed == "type": return catTypes
  if trimmed.startsWith("func ") or trimmed == "func": return catFuncs
  if trimmed.startsWith("proc ") or trimmed.startsWith("method ") or
     trimmed.startsWith("converter ") or trimmed.startsWith("template ") or
     trimmed.startsWith("macro "): return catProcs
  if trimmed.startsWith("import ") or trimmed.startsWith("from "): return catImport
  if trimmed.startsWith("when ") or trimmed == "when": return catSkip
  if trimmed.startsWith("{.") or trimmed.startsWith(".}"): return catSkip
  if trimmed.startsWith("const ") or trimmed == "const": return catOther
  if trimmed.startsWith("var ") or trimmed == "var": return catOther
  if trimmed.startsWith("let ") or trimmed == "let": return catOther
  catOther

func extractNameFromLine*(line: string): string {.raises: [].} =
  ## Extract symbol name from a declaration line.
  let trimmed = line.strip()
  var rest = trimmed
  # Skip keywords and get remainder
  var foundKw = false
  for kw in ["type ", "func ", "proc ", "method ", "converter ", "template ",
             "macro ", "const ", "var ", "let ", "when ", "import ", "from "]:
    if rest.startsWith(kw):
      rest = rest[kw.len .. ^1].strip()
      foundKw = true
      break
  if not foundKw:
    return ""
  if rest.len == 0: return ""
  # Extract identifier (handle generics, dots, export markers)
  var j = 0
  while j < rest.len and (rest[j].isAlphaNumeric or rest[j] == '_' or rest[j] == '.' or rest[j] == '*'):
    inc j
  if j > 0:
    result = rest[0 ..< j]

func scanDeclarations*(source: string): seq[TopDecl] {.raises: [].} =
  ## Scan source text for top-level declarations using line-based analysis.
  result = @[]
  let lines = source.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i]
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("##"):
      inc i
      continue
    if not isTopLevelKeyword(line):
      inc i
      continue
    # Found a declaration start
    let startLine = i
    let startByte = lineStartByte(source, i)
    let category = classifyFromKeyword(line)
    let name = extractNameFromLine(line)
    # Find declaration end by scanning forward
    var j = i + 1
    while j < lines.len:
      let nextLine = lines[j]
      let nextTrimmed = nextLine.strip()
      # Empty lines — keep scanning unless followed by top-level decl
      if nextTrimmed.len == 0:
        var k = j + 1
        while k < lines.len and lines[k].strip().len == 0:
          inc k
        if k >= lines.len or isTopLevelKeyword(lines[k]):
          break
        else:
          inc j
          continue
      # Non-empty non-comment line at column 0 that isn't indented continuation
      if nextLine.len > 0 and nextLine[0] != ' ' and nextLine[0] != '\t' and
         not nextTrimmed.startsWith("#") and not nextTrimmed.startsWith("##"):
        # Could be new top-level declaration or end of a block
        # Heuristic: if it looks like a new keyword or bare statement, stop
        if isTopLevelKeyword(nextLine):
          break
        # Unindented non-keyword line (e.g., closing `end`, bare expression)
        break
      inc j
    # j now points to either next declaration or lines.len
    let endLine = if j < lines.len: j - 1 else: j
    let endByte = if j < lines.len: lineStartByte(source, j) else: uint32(source.len)
    # Extract declaration text
    var declText = ""
    for k in startLine .. min(endLine, lines.len - 1):
      declText.add(lines[k])
      declText.add('\n')
    result.add(TopDecl(
      category: category,
      name: name,
      startLine: startLine,
      endLine: endLine,
      startByte: startByte,
      endByte: endByte,
      text: declText,
    ))
    i = j

func findHeaderEnd*(source: string): uint32 {.raises: [].} =
  ## Find byte offset where body declarations begin (after header).
  let decls = scanDeclarations(source)
  if decls.len == 0:
    return uint32(source.len)
  # First non-import, non-other declaration marks body start
  for d in decls:
    if d.category != catImport and d.category != catOther:
      return d.startByte
  # All are imports or other — use first one
  if decls.len > 0:
    return decls[0].startByte
  return uint32(source.len)

func extractDeclarations*(source: string): seq[ExtractedDecl] {.raises: [].} =
  ## Convert scanned TopDecl list to ExtractedDecl format used downstream.
  result = @[]
  for td in scanDeclarations(source):
    # Skip import statements — they go into module headers
    if td.category == catImport:
      continue
    result.add(ExtractedDecl(
      category: td.category,
      name: td.name,
      startByte: td.startByte,
      endByte: td.endByte,
      text: td.text,
    ))

# ── Safety: Backup / Restore / Verify ───────────────────────────────────────

func backupPath*(filePath: string): string {.raises: [].} =
  ## Generate backup file path for a given file.
  filePath & ".ast_splitter.bak"

proc backupFile*(filePath: string): bool =
  ## Create a backup of the file. Returns true on success.
  try:
    if fileExists(filePath):
      copyFile(filePath, backupPath(filePath))
      return true
    return false
  except OSError, IOError:
    return false

proc restoreFile*(filePath: string): bool =
  ## Restore file from backup. Returns true on success.
  let bak = backupPath(filePath)
  try:
    if fileExists(bak):
      copyFile(bak, filePath)
      return true
    return false
  except OSError, IOError:
    return false

proc cleanupBackup*(filePath: string) =
  ## Remove backup file after successful split.
  let bak = backupPath(filePath)
  try:
    if fileExists(bak):
      removeFile(bak)
  except OSError, IOError:
    discard  # axiom:best-effort(backup file cleanup; non-critical, original file unaffected)

proc verifyCompilation*(filePath: string): tuple[ok: bool; output: string] =
  ## Run `nim check` on a file and return success status + output.
  try:
    let cmd = "nim check --hints:off " & quoteShell(filePath)
    let (output, exitCode) = execCmdEx(cmd)
    return (ok: exitCode == 0, output: output)
  except CatchableError as e:
    return (ok: false, output: "Failed to run nim check: " & e.msg)

# ── Core: Split a Single File ───────────────────────────────────────────────

proc splitSingleFile*(filePath: string; dryRun: bool): SplitResult =
  ## Split a single Nim file into _types, _funcs, _procs sub-modules.
  ## Returns SplitResult with statistics and status.
  result = SplitResult(filePath: filePath, success: false, skipped: false)

  let absPath = filePath.expandFilename
  if not fileExists(absPath):
    stderr.writeLine("ERROR: File not found: " & absPath)
    return

  let source = try:
    readFile(absPath)
  except IOError as e:
    stderr.writeLine("ERROR: Cannot read " & absPath & ": " & e.msg)
    return

  let lineCount = source.splitLines().len
  if lineCount < 500:
    stderr.writeLine("SKIP: " & absPath & " has " & $lineCount & " lines (< 500 threshold)")
    result.success = true
    result.skipped = true
    return

  let dir = parentDir(absPath)
  let name = baseName(absPath)

  # Compute sub-module paths
  let typesPath = dir / (name & "_types.nim")
  let funcsPath = dir / (name & "_funcs.nim")
  let procsPath = dir / (name & "_procs.nim")
  result.typesPath = typesPath
  result.funcsPath = funcsPath
  result.procsPath = procsPath

  # Idempotency: skip if ALL sub-modules already exist
  if fileExists(typesPath) and fileExists(funcsPath) and fileExists(procsPath):
    stderr.writeLine("SKIP: Sub-modules already exist for " & name)
    result.success = true
    result.skipped = true
    return

  # Scan declarations via text-based analysis
  let allImports = parseAllImports(source)

  # Extract declarations using line-scanner
  let declarations = extractDeclarations(source)

  # Classify declarations
  var typeDecls: seq[ExtractedDecl]
  var funcDecls: seq[ExtractedDecl]
  var procDecls: seq[ExtractedDecl]
  var otherDecls: seq[ExtractedDecl]
  var skipDecls: seq[ExtractedDecl]  # when/pragma → composition root

  for decl in declarations:
    case decl.category
    of catTypes: typeDecls.add(decl)
    of catFuncs: funcDecls.add(decl)
    of catProcs: procDecls.add(decl)
    of catOther: otherDecls.add(decl)
    of catImport: discard  # Already handled
    of catSkip: skipDecls.add(decl)

  result.typesCount = typeDecls.len
  result.funcsCount = funcDecls.len
  result.procsCount = procDecls.len
  result.otherCount = otherDecls.len

  # Report statistics
  stderr.writeLine("Splitting " & absPath & " (" & $lineCount & " lines):")
  stderr.writeLine("  types: " & $typeDecls.len &
                   ", funcs: " & $funcDecls.len &
                   ", procs: " & $procDecls.len &
                   ", other: " & $otherDecls.len)

  if typeDecls.len == 0 and funcDecls.len == 0 and procDecls.len == 0:
    stderr.writeLine("SKIP: No splittable declarations found in " & absPath)
    result.success = true
    result.skipped = true
    return

  # Move "other" declarations (var/const/let sections, enums, objects, etc.)
  # into the types module so they're shared across all sub-modules.
  # Module-level state must be visible to both funcs and procs sub-modules.
  for decl in otherDecls:
    typeDecls.add(decl)

  # Generate sub-module contents
  # Types module gets type declarations + module-level state (catOther)
  # Post-process to auto-export const/var/let names (add '*' markers)
  # so importing sub-modules can access them.
  var typesContent = buildSubModule(
    name & "_types",
    "Type declarations extracted from " & name,
    allImports,
    typeDecls,
  )
  typesContent = forceExportConstVars(typesContent)

  # Funcs module imports from types to see shared declarations
  let funcsContent = buildSubModule(
    name & "_funcs",
    "Function declarations extracted from " & name,
    allImports,
    funcDecls,
    extraImports = [name & "_types"],
  )

  # Procs module imports from types to see shared declarations
  let procsContent = buildSubModule(
    name & "_procs",
    "Proc/other declarations extracted from " & name,
    allImports,
    procDecls,
    extraImports = [name & "_types"],
  )

  # Generate composition root
  # Note: skip declarations (when/pragma blocks) are intentionally omitted.
  # Top-level `when isMainModule` blocks reference private procs and are
  # only useful for standalone scripts. Closing pragmas like {.pop.} are
  # tied to the original file's {.push.} scope and don't apply to the
  # composition root.
  let compRoot = buildCompositionRoot(name, [name & "_types", name & "_funcs", name & "_procs"])

  if dryRun:
    stderr.writeLine("  [DRY RUN] Would write:")
    stderr.writeLine("    " & typesPath)
    stderr.writeLine("    " & funcsPath)
    stderr.writeLine("    " & procsPath)
    stderr.writeLine("    " & absPath & " (composition root)")
    result.success = true
    return

  # Backup originals before writing
  if not backupFile(absPath):
    stderr.writeLine("WARNING: Could not backup " & absPath)

  # Write sub-modules (skip existing ones for idempotency)
  proc writeFileIfNew(path, content: string): bool =
    if fileExists(path):
      stderr.writeLine("  SKIP (exists): " & path)
      return true
    try:
      writeFile(path, content)
      stderr.writeLine("  WROTE: " & path)
      return true
    except IOError as e:
      stderr.writeLine("  ERROR writing " & path & ": " & e.msg)
      return false

  if not writeFileIfNew(typesPath, typesContent):
    discard restoreFile(absPath)
    return

  if not writeFileIfNew(funcsPath, funcsContent):
    # Restore types if we wrote it
    # axiom:best-effort(cleanup on write failure)
    try: removeFile(typesPath)
    except OSError as e:
      stderr.writeLine("  WARNING: cleanup removeFile failed: " & e.msg)
    discard restoreFile(absPath)
    return

  if not writeFileIfNew(procsPath, procsContent):
    # Restore types and funcs
    # axiom:best-effort(cleanup on write failure)
    try: removeFile(typesPath)
    except OSError as e:
      stderr.writeLine("  WARNING: cleanup removeFile failed: " & e.msg)
    try: removeFile(funcsPath)
    except OSError as e:
      stderr.writeLine("  WARNING: cleanup removeFile failed: " & e.msg)
    discard restoreFile(absPath)
    return

  # Write composition root (overwrite original)
  try:
    writeFile(absPath, compRoot)
    stderr.writeLine("  WROTE: " & absPath & " (composition root)")
  except IOError as e:
    stderr.writeLine("  ERROR writing composition root: " & e.msg)
    discard restoreFile(absPath)
    return

  # Safety: verify compilation
  stderr.writeLine("  Verifying compilation...")
  let verifyResult = verifyCompilation(absPath)
  if verifyResult.ok:
    stderr.writeLine("  ✓ Compilation verified")
    cleanupBackup(absPath)
    result.success = true
  else:
    stderr.writeLine("  ✗ Compilation FAILED — restoring original")
    stderr.writeLine("  nim check output:")
    for line in verifyResult.output.splitLines():
      stderr.writeLine("    " & line)
    # Restore original
    discard restoreFile(absPath)
    # Clean up sub-modules
    # axiom:best-effort(cleanup on compilation failure)
    for p in [typesPath, funcsPath, procsPath]:
      try:
        if fileExists(p):
          removeFile(p)
      except OSError as e:
        stderr.writeLine("  WARNING: cleanup removeFile failed: " & e.msg)
    result.success = false

# ── CLI: Argument Parsing ───────────────────────────────────────────────────

proc parseArgs*(): SplitConfig =
  ## Parse command-line arguments.
  result = SplitConfig(dryRun: false, files: @[], allMode: false)
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg == "--dry-run":
      result.dryRun = true
      inc i
    elif arg == "--all":
      result.allMode = true
      inc i
    elif arg == "--file" and i + 1 < args.len:
      result.files.add(args[i + 1])
      i += 2
    elif arg == "--help" or arg == "-h":
      stdout.writeLine("Usage: ast_splitter [options]")
      stdout.writeLine("")
      stdout.writeLine("Split large Nim files into _types, _funcs, _procs sub-modules.")
      stdout.writeLine("")
      stdout.writeLine("Options:")
      stdout.writeLine("  --dry-run       Show what would be done without writing files")
      stdout.writeLine("  --file <path>   Split a specific file")
      stdout.writeLine("  --all           Process all 16 grandfather files")
      stdout.writeLine("  --help, -h      Show this help message")
      stdout.writeLine("")
      stdout.writeLine("Examples:")
      stdout.writeLine("  ast_splitter --file src/gate/runners/debt_scan_gate.nim")
      stdout.writeLine("  ast_splitter --all --dry-run")
      quit(0)
    elif arg.startsWith("-"):
      stderr.writeLine("Unknown option: " & arg)
      stderr.writeLine("Use --help for usage information.")
      quit(1)
    else:
      result.files.add(arg)
      inc i

# ── Main ─────────────────────────────────────────────────────────────────────

proc findGrandfatherFile*(filename: string): string =
  ## Search for a grandfather file in the source tree.
  ## Returns the full path or empty string if not found.
  let searchDirs = ["src", "tools"]
  for dir in searchDirs:
    if not dirExists(dir):
      continue
    for path in walkDirRec(dir):
      if path.endsWith(filename):
        return path
  # Also check project root
  if fileExists(filename):
    return filename
  ""

proc main*() =
  ## Entry point for ast_splitter CLI.
  let config = parseArgs()

  # Determine files to process
  var filesToProcess: seq[string]

  if config.allMode:
    stdout.writeLine("Processing all " & $GrandfatherFiles.len & " grandfather files...")
    for gf in GrandfatherFiles:
      let found = findGrandfatherFile(gf)
      if found.len > 0:
        filesToProcess.add(found)
      else:
        stderr.writeLine("WARNING: Grandfather file not found: " & gf)
  elif config.files.len > 0:
    for f in config.files:
      if fileExists(f):
        filesToProcess.add(f)
      else:
        stderr.writeLine("ERROR: File not found: " & f)
  else:
    stderr.writeLine("ERROR: No files specified. Use --file <path> or --all.")
    stderr.writeLine("Use --help for usage information.")
    quit(1)

  if filesToProcess.len == 0:
    stderr.writeLine("No files to process.")
    quit(0)

  # Process files
  var totalTypes = 0
  var totalFuncs = 0
  var totalProcs = 0
  var totalOther = 0
  var successCount = 0
  var skipCount = 0
  var failCount = 0

  for filePath in filesToProcess:
    let result = splitSingleFile(filePath, config.dryRun)
    totalTypes += result.typesCount
    totalFuncs += result.funcsCount
    totalProcs += result.procsCount
    totalOther += result.otherCount
    if result.success:
      inc successCount
    if result.skipped:
      inc skipCount
    if not result.success and not result.skipped:
      inc failCount

  # Summary
  stdout.writeLine("\n=== ast_splitter summary ===")
  stdout.writeLine("Files processed: " & $filesToProcess.len)
  stdout.writeLine("  succeeded: " & $successCount)
  stdout.writeLine("  skipped:   " & $skipCount)
  stdout.writeLine("  failed:    " & $failCount)
  stdout.writeLine("Declarations extracted:")
  stdout.writeLine("  types:  " & $totalTypes)
  stdout.writeLine("  funcs:  " & $totalFuncs)
  stdout.writeLine("  procs:  " & $totalProcs)
  stdout.writeLine("  other:  " & $totalOther)

  if config.dryRun:
    stdout.writeLine("(DRY RUN — no files were modified)")

  if failCount > 0:
    quit(1)

when isMainModule:
  main()

{.pop.}
