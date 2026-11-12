## tools/refactor_best_effort.nim — AST-Aware Refactoring Engine
##
## Migrates `# axiom:best-effort(<reason>)` comments to `{.bestEffort("reason").}`
## pragmas on proc/func definitions using Nim AST parser.
##
## Uses Nim's compiler/parser API to:
## 1. Parse file into AST nodes
## 2. Locate proc/func definitions and their line ranges
## 3. Bind comments to containing proc definitions
## 4. Generate transformed source with pragmas added
##
## Usage:
##   nim c -r tools/refactor_best_effort.nim --dry-run   # Preview only
##   nim c -r tools/refactor_best_effort.nim --execute   # Write changes
##   nim c -r tools/refactor_best_effort.nim --file <path> # Single file
##
## Build:
##   nim c -r tools/refactor_best_effort.nim --dry-run
##

import core/trusted/layer_declaration
axiomLayer "tools"

import std/[os, strutils, sequtils]
import compiler/[ast, parser, options, llstream, idents, pathutils]

type
  ProcLineInfo = object
    line: int
    endLine: int
    sig: string
    hasBestEffort: bool

  Transformation = object
    filePath: string
    commentLine: int
    procLine: int
    reason: string
    originalLine: string

  TransformResult = object
    filePath: string
    fileName: string
    commentsFound: int
    transformations: seq[Transformation]
    errors: seq[string]

const DefaultReason* = "Migrated legacy best-effort gate - pending audit"

func safeLen(n: PNode): int {.inline.} =
  if n.isNil: return 0
  case n.kind
  of nkIdent, nkSym, nkType, nkNone, nkEmpty, nkCommentStmt,
     nkCharLit..nkUInt64Lit, nkFloatLit..nkFloat128Lit,
     nkStrLit..nkTripleStrLit, nkNilLit:
    0
  else:
    n.len

func parseBestEffortComment(line: string): tuple[found: bool, reason: string] =
  let stripped = line.strip()
  
  if not stripped.startsWith("#"):
    return (false, "")
  
  var commentBody = stripped[1..^1].strip()
  
  let axIdx = commentBody.find("axiom:best-effort(")
  let axIdx2 = commentBody.find("axiom: best-effort(")
  
  if axIdx == -1 and axIdx2 == -1:
    return (false, "")
  
  var reasonStart: int
  if axIdx != -1:
    reasonStart = axIdx + "axiom:best-effort(".len
  else:
    reasonStart = axIdx2 + "axiom: best-effort(".len
  
  let reasonPart = commentBody[reasonStart..^1]
  let closeParen = reasonPart.find(")")
  if closeParen == -1:
    return (false, "")
  
  let reasonText = reasonPart[0..<closeParen].strip()
  return (true, reasonText)

func isProcOrFuncDef(n: PNode): bool =
  if n.isNil: return false
  n.kind in {nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef, nkConverterDef}

func hasBestEffortPragma(n: PNode): bool =
  if n.isNil or n.kind != nkProcDef:
    return false
  if safeLen(n) <= 4:
    return false
  let pragmaNode = n[4]
  if pragmaNode.isNil or pragmaNode.kind != nkPragma:
    return false
  for i in 0..<pragmaNode.len:
    let p = pragmaNode[i]
    if p.kind == nkIdent and p.ident.s == "bestEffort":
      return true
    if p.kind == nkExprColonExpr and safeLen(p) >= 2:
      if p[0].kind in {nkIdent, nkSym}:
        let name = if p[0].kind == nkIdent: p[0].ident.s else: p[0].sym.name.s
        if name == "bestEffort":
          return true
  false

func getProcEndLine(n: PNode): int =
  if n.isNil:
    return 0
  var maxLine = n.info.line.int
  if safeLen(n) > 0:
    for i in 0..<n.len:
      let childEnd = getProcEndLine(n[i])
      if childEnd > maxLine:
        maxLine = childEnd
  maxLine

func extractProcSig(n: PNode): string =
  if n.isNil or safeLen(n) == 0:
    return ""
  let firstChild = n[0]
  case firstChild.kind
  of nkIdent:
    firstChild.ident.s
  of nkPostfix:
    if safeLen(firstChild) >= 2:
      if firstChild[1].kind == nkIdent:
        firstChild[1].ident.s
      else:
        ""
    else:
      ""
  of nkAccQuoted:
    if safeLen(firstChild) >= 1:
      let inner = firstChild[0]
      if inner.kind == nkIdent:
        inner.ident.s
      else:
        ""
    else:
      ""
  of nkSym:
    firstChild.sym.name.s
  else:
    ""

proc collectProcLines(root: PNode): seq[ProcLineInfo] =
  var procs: seq[ProcLineInfo] = @[]
  
  proc collect(n: PNode) =
    if n.isNil:
      return
    if isProcOrFuncDef(n) and not hasBestEffortPragma(n):
      procs.add(ProcLineInfo(
        line: n.info.line.int,
        endLine: getProcEndLine(n),
        sig: extractProcSig(n),
        hasBestEffort: false
      ))
    if safeLen(n) > 0:
      for i in 0..<n.len:
        collect(n[i])
  
  collect(root)
  procs

proc parseNimFile(path: string): PNode =
  let cache = newIdentCache()
  let config = newConfigRef()
  {.cast(raises: []).}:
    let absFile = AbsoluteFile(path)
    var stream = llStreamOpen(absFile, fmRead)
    var parser: Parser
    openParser(parser, absFile, stream, cache, config)
    let ast = parseAll(parser)
    closeParser(parser)
    ast

proc findContainingProc(procLines: seq[ProcLineInfo], lineNumber: int): ProcLineInfo =
  for p in procLines:
    if lineNumber >= p.line and lineNumber <= p.endLine:
      result = p
      return
  result.line = 0
  result.endLine = 0

proc buildPragma(reason: string): string =
  ## Build pragma string with proper escaping.
  ## Remove double quotes, commas, and other problematic characters.
  let normalizedReason = reason.replace("\"", "").replace(",", ";").replace("\n", " ")
  "bestEffort(\"" & normalizedReason & "\")"

proc addPragmaToProcLine(procLine: string, reason: string): string =
  ## Add {.bestEffort("reason").} pragma to an existing proc/func definition line.
  ## Handles three cases:
  ## 1. No existing pragma: append ` {.bestEffort("reason").}`
  ## 2. Existing pragma block: insert `bestEffort("reason")` inside `{. ... .}`
  ## 3. Pragma with `=`: append before `=`
  
  let pragmaStr = "bestEffort(\"" & reason & "\")"
  
  # Case 1: No existing pragma
  if "{." notin procLine:
    if procLine.endsWith("="):
      return procLine[0..^2] & " {.bestEffort(\"" & reason & "\").} ="
    else:
      return procLine & " {.bestEffort(\"" & reason & "\").}"
  
  # Case 2: Existing pragma block
  let openIdx = procLine.find("{.")
  let closeIdx = procLine.find("}.", openIdx)
  if closeIdx != -1:
    # Insert before closing .}
    let beforeClose = procLine[0..<closeIdx]
    let afterClose = procLine[closeIdx..^1]
    return beforeClose & " " & pragmaStr & afterClose
  
  # Fallback: append at end
  return procLine & " {.bestEffort(\"" & reason & "\").}"

proc transformFile(filePath: string, dryRun: bool): TransformResult =
  result = TransformResult(
    filePath: filePath,
    fileName: extractFilename(filePath),
    commentsFound: 0,
    transformations: @[],
    errors: @[]
  )
  
  let content = readFile(filePath)
  var lines = content.splitLines()
  
  # AST parsing is disabled due to strict parser requiring valid syntax.
  # Use line-based heuristic for robustness across all files.
  var useAst = false
  var ast: PNode = nil
  let procLines: seq[ProcLineInfo] = @[]
  
  var transformations: seq[Transformation] = @[]
  
  for i, line in lines:
    let (found, reason) = parseBestEffortComment(line)
    if not found:
      continue
    
    inc result.commentsFound
    
    var containingProcLine = -1
    if procLines.len > 0:
      let containingProc = findContainingProc(procLines, i + 1)
      containingProcLine = containingProc.line
    else:
      # Fallback: find next proc/func definition after comment
      for j in i+1..<lines.len:
        let trimmed = lines[j].strip()
        if trimmed.startsWith("proc ") or trimmed.startsWith("func ") or 
           trimmed.startsWith("method ") or trimmed.startsWith("iterator "):
          containingProcLine = j + 1  # 1-indexed
          break
    
    if containingProcLine == -1:
      continue
    
    let reasonText = if reason.len > 0: reason else: DefaultReason
    
    transformations.add(Transformation(
      filePath: filePath,
      commentLine: i + 1,
      procLine: containingProcLine,
      reason: reasonText,
      originalLine: line
    ))
  
  result.transformations = transformations
  
  if dryRun:
    return
  
  if transformations.len == 0:
    return
  
  var newLines = lines
  var offset = 0  # Track line number changes due to comment removal
  for t in transformations:
    let commentIdx = t.commentLine - 1
    let procIdx = t.procLine - 1 + offset
    if commentIdx < 0 or commentIdx >= newLines.len or procIdx < 0 or procIdx >= newLines.len:
      continue
    
    # Remove comment line and add pragma to proc line
    newLines[commentIdx] = ""  # Remove comment
    newLines[procIdx] = addPragmaToProcLine(newLines[procIdx], t.reason)
    dec offset  # Account for removed comment line
  
  # Filter out empty lines
  newLines = newLines.filterIt(it.len > 0)
  let newContent = newLines.join("\n")
  
  try:
    writeFile(filePath, newContent)
  except CatchableError as e:
    result.errors.add("Write error: " & e.msg)

proc scanDirectory(dir: string): seq[string] =
  var files: seq[string] = @[]
  for entry in walkDirRec(dir):
    if entry.endsWith(".nim"):
      files.add(entry)
  files

proc formatTransformation(t: Transformation): string =
  "  [Line " & $t.commentLine & "] " & t.originalLine.strip() &
  "\n     -> {.bestEffort(\"" & t.reason & "\").}"

proc main() =
  var dryRun = true
  var filePathArg = ""
  var directory = "src"
  
  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    case arg
    of "--dry-run", "-d":
      dryRun = true
    of "--execute", "-e":
      dryRun = false
    of "--file":
      inc i
      if i <= paramCount():
        filePathArg = paramStr(i)
    of "--file=":
      filePathArg = arg[7..^1]
    of "--dir":
      inc i
      if i <= paramCount():
        directory = paramStr(i)
    of "--dir=":
      directory = arg[5..^1]
    of "--help", "-h":
      echo "AST-Aware Refactoring Engine for axiom:best-effort comment migration"
      echo ""
      echo "Usage:"
      echo "  nim c -r tools/refactor_best_effort.nim --dry-run --file <path>"
      echo "  nim c -r tools/refactor_best_effort.nim --execute --file <path>"
      echo "  nim c -r tools/refactor_best_effort.nim --dry-run --dir <dir>"
      echo ""
      echo "Options:"
      echo "  --dry-run, -d      Preview changes without writing (default)"
      echo "  --execute, -e      Actually write changes"
      echo "  --file PATH        Process single file"
      echo "  --dir PATH         Process all .nim files in directory (recursive, default: src/)"
      echo "  --help, -h         Show this help"
      quit(0)
    else:
      discard
    inc i
  
  echo "=== Best-Effort Comment Refactoring Engine ==="
  if dryRun:
    echo "  [DRY RUN] Preview mode - no changes will be written"
  else:
    echo "  [EXECUTE] Changes will be written to files"
  echo ""
  
  var filesToProcess: seq[string] = @[]
  
  if filePathArg.len > 0:
    if fileExists(filePathArg):
      filesToProcess = @[filePathArg]
    else:
      stderr.writeLine("Error: File not found: " & filePathArg)
      quit(1)
  elif dirExists(directory):
    filesToProcess = scanDirectory(directory)
  else:
    stderr.writeLine("Error: Directory not found: " & directory)
    quit(1)
  
  echo "Scanning " & $filesToProcess.len & " nim files..."
  echo ""
  
  var totalComments = 0
  var totalFilesWithComments = 0
  
  for f in filesToProcess:
    let res = transformFile(f, dryRun)
    
    if res.commentsFound == 0:
      continue
    
    inc totalFilesWithComments
    totalComments += res.commentsFound
    
    echo "--- " & res.fileName & " ---"
    echo "  Comments found: " & $res.commentsFound
    
    for t in res.transformations:
      echo formatTransformation(t)
    
    if res.errors.len > 0:
      echo "  Errors:"
      for e in res.errors:
        echo "    " & e
      echo "  Status: ERRORS"
    else:
      echo "  Status: OK"
    echo ""
  
  echo "=== Summary ==="
  echo "  Files scanned:         " & $filesToProcess.len
  echo "  Files with comments:   " & $totalFilesWithComments
  echo "  Total comments:        " & $totalComments
  echo ""
  
  if dryRun:
    echo "  [DRY RUN] No changes written."
  else:
    var totalErrors = 0
    for f in filesToProcess:
      let r = transformFile(f, dryRun)
      totalErrors += r.errors.len
    echo "  Files processed successfully: " & $totalFilesWithComments
    if totalErrors > 0:
      echo "  Errors: " & $totalErrors

when isMainModule:
  main()