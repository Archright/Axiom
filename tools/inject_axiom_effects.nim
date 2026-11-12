## tools/inject_axiom_effects.nim — Text-based axiomEffect pragma injector
##
## Scans .nim files for I/O procs missing axiomEffect and injects:
##   {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
##
## Also adds `import core/axiom_pragmas` if missing.
##
## Usage:
##   inject_axiom_effects --dir <path> [--dry-run] [--inject] [--file <path>]
##
## Default is dry-run. --inject actually modifies files.
## Outputs JSON report to stdout.

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, strutils, json, parseopt, sets, algorithm]

const
  AxiomEffectPragma = "{.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}"
  AxiomPragmaImportTrusted = "import core/trusted/axiom_pragmas"
  AxiomPragmaImportShim = "import core/axiom_pragmas"
  IoPatterns = [
    "readFile(", "writeFile(", "execProcess(", "startProcess(",
    "execShellCmd(", "stderr.writeLine", "stderr.write ",
    "stdout.write", "open(", "close(", "flushFile(",
    "readAll(", "readLine(", "readBytes(", "writeBytes(",
    "setFilePos(", "getFilePos(", "getFileSize(",
    "existsFile(", "copyFile(", "moveFile(", "removeFile(",
    "createDir(", "removeDir("
  ]
  ExcludeDirs = toHashSet([
    ".git", "nimcache", "build", "vendor", ".lake", ".kimi-code",
    "node_modules", ".agents", "logs"
  ])

func isProcDef(line: string): bool =
  let s = line.strip()
  s.startsWith("proc ") or s.startsWith("func ") or
  s.startsWith("proc* ") or s.startsWith("func* ")

func extractProcName(line: string): string =
  let s = line.strip()
  var rest = s
  if rest.startsWith("proc* ") or rest.startsWith("func* "):
    rest = rest[5..^1].strip()
  elif rest.startsWith("proc ") or rest.startsWith("func "):
    rest = rest[4..^1].strip()
  else:
    return ""
  var name = ""
  for ch in rest:
    if ch in {'(', ':', '[', ' ', '\t', '='}:
      break
    name.add(ch)
  result = name.strip(chars = {'*', '`'})

func skipComment(line: string): bool =
  let s = line.strip()
  s.startsWith("#") or s.startsWith("##")

func hasAxiomEffect(lines: seq[string]; procLine: int): bool =
  for j in procLine ..< min(procLine + 8, lines.len):
    if "axiomEffect" in lines[j]:
      return true
  false

func hasIoInBody(lines: seq[string]; procLine: int): bool =
  let endSearch = min(procLine + 80, lines.len)
  for j in procLine ..< endSearch:
    if j >= lines.len: break
    let bodyLine = lines[j]
    if skipComment(bodyLine): continue
    for pat in IoPatterns:
      if pat in bodyLine:
        return true
  false

func findProcEnd(lines: seq[string]; procStart: int): int =
  var parenDepth = 0
  var bracketDepth = 0
  for i in procStart ..< lines.len:
    let line = lines[i]
    var j = 0
    while j < line.len:
      case line[j]
      of '(':
        inc parenDepth
      of ')':
        if parenDepth > 0:
          dec parenDepth
      of '[':
        inc bracketDepth
      of ']':
        if bracketDepth > 0:
          dec bracketDepth
      of '=':
        if parenDepth == 0 and bracketDepth == 0:
          let prevChar = if j > 0: line[j-1] else: ' '
          let nextChar = if j < line.len - 1: line[j+1] else: ' '
          if prevChar notin {'!', '<', '>', '='} and nextChar notin {'='}:
            return i
      else:
        discard
      inc j
    if parenDepth == 0 and bracketDepth == 0:
      return i
  -1

func insertAxiomBeforeEquals(line: string): string =
  let equalsIdx = line.rfind(" =")
  if equalsIdx >= 0:
    result = line[0 ..< equalsIdx] & " " & AxiomEffectPragma & line[equalsIdx .. ^1]
  else:
    result = line & " " & AxiomEffectPragma

func hasExistingPragmaBlock(line: string): bool =
  let trimmed = line.strip()
  "{." in trimmed and ".}" in trimmed

func addAxiomToExistingBlock(line: string): string =
  let trimmed = line.strip()
  let closeIdx = trimmed.rfind(".}")
  if closeIdx >= 0:
    let insertPos = (line.len - trimmed.len) + closeIdx
    let before = line[0 ..< insertPos]
    let after = line[insertPos .. ^1]
    let pragmaBody = AxiomEffectPragma[2..^3]
    result = before & ", " & pragmaBody & after
  else:
    result = insertAxiomBeforeEquals(line)

func hasAxiomPragmaImport(lines: seq[string]): bool =
  for line in lines:
    let s = line.strip()
    if "axiom_pragmas" in s and (s.startsWith("import") or s.startsWith("from")):
      return true
  false

func choosePragmaImport(lines: seq[string]): string =
  ## Pick the import path that matches what the file already uses, to avoid
  ## pulling in both `core/axiom_pragmas` (shim) and `core/trusted/axiom_pragmas`
  ## (definition) into the same compilation unit, which makes `Pure` ambiguous.
  for line in lines:
    let s = line.strip()
    if "core/trusted/axiom_pragmas" in s and (s.startsWith("import") or s.startsWith("from")):
      return AxiomPragmaImportTrusted
  AxiomPragmaImportShim

func findLastImportLine(lines: seq[string]): int =
  var lastImport = -1
  for i, line in lines:
    let s = line.strip()
    if s.startsWith("import ") or s.startsWith("import["):
      lastImport = i
  lastImport

type
  InjectionResult = object
    file: string
    procsScanned: int
    procsWithIo: int
    procsNeedingInjection: int
    procsInjected: int
    importAdded: bool
    changes: seq[JsonNode]

proc findAllNimFiles(dir: string): seq[string] =
  result = @[]
  for kind, path in walkDir(dir):
    case kind
    of pcFile:
      if path.endsWith(".nim") and not path.extractFilename().startsWith("."):
        result.add(path)
    of pcDir:
      let dirName = path.parentDir().splitPath().tail
      if dirName notin ExcludeDirs:
        result.add(findAllNimFiles(path))
    else:
      discard
  result.sort()

proc processFile(filePath: string; doInject: bool): InjectionResult =
  result.file = filePath
  result.procsScanned = 0
  result.procsWithIo = 0
  result.procsNeedingInjection = 0
  result.procsInjected = 0
  result.importAdded = false
  result.changes = @[]

  var fileContent: string
  try:
    fileContent = readFile(filePath)
  except IOError:
    return
  if fileContent.len == 0:
    return

  var lines = fileContent.splitLines()
  var i = 0
  var modified = false

  while i < lines.len:
    let stripped = lines[i].strip()
    if isProcDef(stripped):
      # A `func` already implies noSideEffect; adding {.axiomEffect: IoEffect.}
      # to a func is a project violation (see tests/negative/nimtry_effect_negative_test.nim)
      # and would break compilation. Only `proc` definitions are eligible.
      if stripped.startsWith("func") or stripped.startsWith("func*"):
        inc i
        continue
      inc result.procsScanned
      let procName = extractProcName(lines[i])

      if not hasAxiomEffect(lines, i):
        if hasIoInBody(lines, i):
          inc result.procsWithIo
          inc result.procsNeedingInjection
          let procEnd = findProcEnd(lines, i)
          if procEnd >= 0:
            let originalLine = lines[procEnd]
            var newLine: string
            if hasExistingPragmaBlock(originalLine):
              newLine = addAxiomToExistingBlock(originalLine)
            else:
              newLine = insertAxiomBeforeEquals(originalLine)
            if newLine != originalLine:
              result.changes.add(%*{
                "proc": procName,
                "line": procEnd + 1,
                "original": originalLine.strip(),
                "modified": newLine.strip()
              })
              if doInject:
                lines[procEnd] = newLine
                inc result.procsInjected
                modified = true
    inc i

  if result.procsNeedingInjection > 0 and not hasAxiomPragmaImport(lines):
    let lastImport = findLastImportLine(lines)
    let importLine = choosePragmaImport(lines)
    if lastImport >= 0:
      if doInject:
        lines = lines[0 .. lastImport] & @[importLine] & lines[lastImport + 1 .. ^1]
        modified = true
        result.importAdded = true
      else:
        result.changes.add(%*{
          "proc": "(import)",
          "line": lastImport + 2,
          "original": "",
          "modified": importLine
        })

  if modified and doInject:
    try:
      writeFile(filePath, lines.join("\n"))
    except IOError:
      discard

proc main() =
  var dryRun = true
  var doInject = false
  var targetDir = ""
  var targetFile = ""

  for kind, key, val in getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "dry-run":
        dryRun = true
        doInject = false
      of "inject":
        dryRun = false
        doInject = true
      of "dir", "d":
        if val.len > 0:
          targetDir = val
        else:
          targetDir = ""
      of "file", "f":
        if val.len > 0:
          targetFile = val
        else:
          targetFile = ""
      else:
        discard
    of cmdArgument:
      if targetDir.len == 0 and targetFile.len == 0:
        if val.endsWith(".nim") and fileExists(val):
          targetFile = val
        elif dirExists(val):
          targetDir = val
    of cmdEnd:
      break

  if targetDir.len == 0 and targetFile.len == 0:
    echo "Usage: inject_axiom_effects --dir <path> [--file <path>] [--dry-run] [--inject]"
    echo ""
    echo "Options:"
    echo "  --dir PATH     Scan directory recursively"
    echo "  --file PATH    Process a single file"
    echo "  --dry-run      Show what would be changed (default)"
    echo "  --inject       Actually modify files"
    quit(1)

  var files: seq[string] = @[]
  if targetFile.len > 0:
    if not fileExists(targetFile):
      stderr.writeLine("Error: File not found: ", targetFile)
      quit(1)
    files.add(targetFile)
  elif targetDir.len > 0:
    if not dirExists(targetDir):
      stderr.writeLine("Error: Directory not found: ", targetDir)
      quit(1)
    files = findAllNimFiles(targetDir)

  var totalScanned = 0
  var totalWithIo = 0
  var totalNeedingInjection = 0
  var totalInjected = 0
  var totalImportsAdded = 0
  var allChanges: seq[JsonNode] = @[]

  for filePath in files:
    let res = processFile(filePath, doInject)
    totalScanned += res.procsScanned
    totalWithIo += res.procsWithIo
    totalNeedingInjection += res.procsNeedingInjection
    totalInjected += res.procsInjected
    if res.importAdded:
      inc totalImportsAdded
    for c in res.changes:
      var entry = %*{"file": filePath}
      for k, v in c:
        entry[k] = v
      allChanges.add(entry)

  let report = %*{
    "mode": (if doInject: "inject" else: "dry-run"),
    "filesScanned": files.len,
    "procsScanned": totalScanned,
    "procsWithIo": totalWithIo,
    "procsNeedingInjection": totalNeedingInjection,
    "procsInjected": totalInjected,
    "importsAdded": totalImportsAdded,
    "changes": allChanges
  }
  echo report.pretty()

when isMainModule:
  main()

{.pop}
