## tools/ast_import_extractor.nim — Import Extractor
##
## Extracts all import statements from Nim source files using regex-based
## parsing (reusing `parseRawImports` from `import_resolver.nim`).
##
## Usage:
##   ast_import_extractor [--src-root DIR] [--format jsonl|text]
##                        [file1.nim file2.nim ...]
##
## If no files are given, scans all `src/**/*.nim`.
##
## Compile:
##   nim c -o:bin/ast_import_extractor tools/ast_import_extractor.nim

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, strutils, tables, algorithm]
import import_resolver

# ── Types ─────────────────────────────────────────────────────────────────────

type
  ImportEntry* = object
    file*: string       ## Source file path
    line*: int          ## 1-based line number of the import statement
    rawImport*: string  ## Raw import token (e.g. "core/pure_deps/json_parse")
    resolvedPath*: string  ## Resolved file path ("" if unresolvable)
    isStdlib*: bool     ## Whether this is a standard library import

  Config* = object
    srcRoot*: string      ## Root source directory (default: "src")
    format*: OutputFormat ## Output format
    files*: seq[string]   ## Explicit file list; empty = scan src/**/*.nim

  OutputFormat* = enum
    fmtText,
    fmtJsonl

# ── Line-tracked import parser ────────────────────────────────────────────────

func stripComment(line: string): string {.raises: [].} =
  ## Return empty string for comment/blank lines.
  let trimmed = line.strip()
  if trimmed.len == 0 or trimmed.startsWith("#") or trimmed.startsWith("##"):
    return ""
  trimmed

func parseImportsWithLines*(source: string): seq[(int, string)] =
  ## Parse all import targets from a Nim source string, tracking line numbers.
  ## Returns (lineNumber, rawImport) pairs (1-based line numbers).
  ## Mirrors the parsing logic of `import_resolver.parseRawImports` exactly,
  ## but also captures the line number of each import statement.
  result = @[]
  var inMultilineImport = false

  var lineNum = 0
  for rawLine in source.splitLines():
    inc lineNum
    let line = stripComment(rawLine)
    if line.len == 0:
      inMultilineImport = false
      continue

    let trimmed = line.strip()

    # `from X import symbol`
    if trimmed.startsWith("from "):
      let rest = trimmed[5 .. ^1]
      let importIdx = rest.find(" import")
      if importIdx > 0:
        let moduleName = rest[0 .. importIdx-1].strip()
        if moduleName.len > 0:
          result.add((lineNum, moduleName))
      inMultilineImport = false
      continue

    # `import X, Y, Z` (possibly multi-line)
    if trimmed.startsWith("import "):
      let rest = trimmed[7 .. ^1]
      if rest.strip().endsWith(","):
        let items = rest[0 .. ^2].strip()
        for item in items.split(','):
          let s = item.strip()
          if s.len > 0:
            result.add((lineNum, s))
        inMultilineImport = true
      else:
        for item in rest.split(','):
          let s = item.strip()
          if s.len > 0:
            result.add((lineNum, s))
        inMultilineImport = false
      continue

    # Continuation of multi-line import
    if inMultilineImport:
      if trimmed.endsWith(","):
        let items = trimmed[0 .. ^2].strip()
        for item in items.split(','):
          let s = item.strip()
          if s.len > 0:
            result.add((lineNum, s))
      else:
        for item in trimmed.split(','):
          let s = item.strip()
          if s.len > 0:
            result.add((lineNum, s))
        inMultilineImport = false

# ── File scanning ─────────────────────────────────────────────────────────────

func canonicalPath*(filePath: string): string {.raises: [].} =
  ## Normalize path to use forward slashes and collapse doubles.
  result = filePath.replace('\\', '/')
  while "//" in result:
    result = result.replace("//", "/")
  if result.endsWith("/"):
    result = result[0 .. ^2]

proc extractImportsFromFile*(filePath: string, srcRoot: string): seq[ImportEntry] =
  ## Extract all imports from a single file with line tracking and resolution.
  ## Deduplicates within the file (same raw import on same line → keep first).
  result = @[]
  if not fileExists(filePath):
    return

  var content: string
  try:
    content = readFile(filePath)
  except IOError:
    return

  let importsWithLines = parseImportsWithLines(content)
  var seen = initTable[string, bool]()

  for (lineNum, rawImport) in importsWithLines:
    # Deduplicate: same raw import token within the file
    if rawImport in seen:
      continue
    seen[rawImport] = true

    let resolved = resolveImportPath(rawImport, filePath, srcRoot)
    let entry = ImportEntry(
      file: filePath,
      line: lineNum,
      rawImport: rawImport,
      resolvedPath: resolved,
      isStdlib: isStdlib(rawImport),
    )
    result.add(entry)

proc collectNimFiles(srcRoot: string): seq[string] =
  ## Collect all .nim files under srcRoot, sorted deterministically.
  result = @[]
  if not dirExists(srcRoot):
    return
  for path in walkDirRec(srcRoot):
    if path.endsWith(".nim"):
      result.add(canonicalPath(path))
  result.sort(cmp)

# ── Output formatting ─────────────────────────────────────────────────────────

func escapeJson(s: string): string =
  ## Escape a string for JSON output (minimal, handles required escapes).
  result = ""
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      if ord(c) < 0x20:
        result.add("\\u")
        result.add(toHex(ord(c), 4))
      else:
        result.add(c)

func formatJsonl(entries: seq[ImportEntry]): seq[string] =
  ## Format entries as JSONL lines.
  result = @[]
  for entry in entries:
    var obj = "{"
    obj.add("\"file\":\"" & escapeJson(entry.file) & "\",")
    obj.add("\"line\":" & $entry.line & ",")
    obj.add("\"rawImport\":\"" & escapeJson(entry.rawImport) & "\",")
    obj.add("\"resolvedPath\":\"" & escapeJson(entry.resolvedPath) & "\",")
    obj.add("\"isStdlib\":" & $entry.isStdlib)
    obj.add("}")
    result.add(obj)

func formatText(entries: seq[ImportEntry], srcRoot: string): seq[string] =
  ## Format entries as human-readable text.
  result = @[]
  var currentFile = ""

  for entry in entries:
    # Show file header when the source file changes
    if entry.file != currentFile:
      currentFile = entry.file
      # Make the path relative to project root for readability
      var displayPath = currentFile
      if displayPath.startsWith(srcRoot & "/"):
        displayPath = displayPath[srcRoot.len + 1 .. ^1]
      result.add("")
      result.add("── " & displayPath & " ──")

    let lineStr = alignLeft($entry.line, 4)
    let resolved =
      if entry.isStdlib: "[stdlib]"
      elif entry.resolvedPath.len > 0: entry.resolvedPath
      else: "[unresolved]"
    result.add("  L" & lineStr & "  " & entry.rawImport & "  →  " & resolved)

# ── Summary statistics ────────────────────────────────────────────────────────

type
  Stats* = object
    filesScanned*: int
    totalImports*: int
    stdlibImports*: int
    projectImports*: int
    unresolvedImports*: int

func computeStats(entries: seq[ImportEntry], filesScanned: int): Stats =
  result = Stats(
    filesScanned: filesScanned,
    totalImports: entries.len,
    stdlibImports: 0,
    projectImports: 0,
    unresolvedImports: 0,
  )
  for entry in entries:
    if entry.isStdlib:
      inc result.stdlibImports
    elif entry.resolvedPath.len > 0:
      inc result.projectImports
    else:
      inc result.unresolvedImports

func formatWithCommas(n: int): string =
  ## Format an integer with comma separators (e.g. 2847 → "2,847").
  let s = $n
  result = ""
  for i, c in s:
    if i > 0 and (s.len - i) mod 3 == 0:
      result.add(',')
    result.add(c)

func formatStats(stats: Stats): string =
  ## Format summary stats for stderr.
  let total = stats.totalImports
  let formatted = formatWithCommas(total)
  var parts: seq[string] = @[]
  parts.add($stats.stdlibImports & " stdlib")
  parts.add($stats.projectImports & " project")
  if stats.unresolvedImports > 0:
    parts.add($stats.unresolvedImports & " unresolved")
  "Scanned " & $stats.filesScanned & " files, found " & formatted &
    " imports (" & parts.join(", ") & ")"

# ── CLI argument parsing ──────────────────────────────────────────────────────

proc parseArgs(): Config =
  result = Config(
    srcRoot: "src",
    format: fmtText,
    files: @[],
  )
  let args = commandLineParams()
  var i = 0
  while i < args.len:
    let arg = args[i]
    if arg == "--src-root" and i + 1 < args.len:
      result.srcRoot = args[i + 1]
      i += 2
    elif arg == "--format" and i + 1 < args.len:
      let fmt = args[i + 1].toLowerAscii()
      case fmt
      of "jsonl": result.format = fmtJsonl
      of "text": result.format = fmtText
      else:
        stderr.writeLine("Unknown format: " & args[i + 1] & " (expected: jsonl|text)")
        quit(1)
      i += 2
    elif arg == "--help" or arg == "-h":
      stderr.writeLine("Usage: ast_import_extractor [options] [file1.nim file2.nim ...]")
      stderr.writeLine("")
      stderr.writeLine("Extract import statements from Nim source files.")
      stderr.writeLine("")
      stderr.writeLine("Options:")
      stderr.writeLine("  --src-root DIR   Source root directory (default: src)")
      stderr.writeLine("  --format FMT     Output format: text (default) or jsonl")
      stderr.writeLine("  --help, -h       Show this help message")
      stderr.writeLine("")
      stderr.writeLine("If no files are given, scans all " & result.srcRoot & "/**/*.nim.")
      quit(0)
    elif arg.startsWith("-"):
      stderr.writeLine("Unknown option: " & arg)
      stderr.writeLine("Use --help for usage information.")
      quit(1)
    else:
      result.files.add(arg)
      i += 1

# ── Main ──────────────────────────────────────────────────────────────────────

proc main() =
  let config = parseArgs()

  # Collect files to process
  var files: seq[string]
  if config.files.len > 0:
    # Validate explicit file list
    for f in config.files:
      if not fileExists(f):
        stderr.writeLine("File not found: " & f)
        quit(1)
    files = config.files
  else:
    files = collectNimFiles(config.srcRoot)

  if files.len == 0:
    stderr.writeLine("No .nim files found.")
    quit(0)

  # Extract imports from all files
  var allEntries: seq[ImportEntry] = @[]
  for filePath in files:
    let entries = extractImportsFromFile(filePath, config.srcRoot)
    for entry in entries:
      allEntries.add(entry)

  # Compute and output stats to stderr
  let stats = computeStats(allEntries, files.len)
  stderr.writeLine(formatStats(stats))

  # Format and output to stdout
  case config.format
  of fmtJsonl:
    let lines = formatJsonl(allEntries)
    for line in lines:
      echo line
  of fmtText:
    let lines = formatText(allEntries, config.srcRoot)
    for line in lines:
      echo line

when isMainModule:
  main()

{.pop.}
