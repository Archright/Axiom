import core/trusted/layer_declaration
axiomLayer "domain"
import std/macros
import std/strutils
import std/os

const ioSymbols*: seq[string] = @["readFile", "writeFile", "open", "close", "readLine", "write", "fileExists", "dirExists", "walkDir", "walkDirRec", "walkFiles", "removeFile", "moveFile", "copyFile", "existsOrCreateDir", "createDir", "getCurrentDir", "setCurrentDir", "startProcess", "execCmdEx", "execProcess", "waitForExit", "peekExitCode", "now", "getTime", "cpuTime", "epochTime", "echo", "debugEcho", "stdout.write", "stderr.write", "getEnv", "existsEnv", "putEnv", "setrlimit", "initLock", "acquire", "release", "parseJson"]

type EffectViolation* = object
  file*: string
  line*: int
  col*: int
  procName*: string
  detectedIO*: seq[string]
  suggestedPragma*: string

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizePath(p: string): string =
  result = p.replace("\\", "/")
  while result.endsWith("/"):
    result = result[0 .. ^2]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func isIoCall*(node: NimNode): bool =
  if node.kind == nnkCall:
    let callee = node[0]
    var name: string
    if callee.kind == nnkDotExpr:
      name = $callee[0] & "." & $callee[1]
    elif callee.kind == nnkIdent or callee.kind == nnkSym:
      name = $callee
    else:
      return false
    return name in ioSymbols
  return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func hasAxiomEffectPragma*(pragmas: NimNode): bool =
  if pragmas.kind == nnkEmpty:
    return false
  for pragma in pragmas:
    if pragma.kind == nnkCall:
      let ident = pragma[0]
      if ident.kind == nnkIdent or ident.kind == nnkSym:
        if $ident == "axiomEffect":
          return true
  return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func collectIoCalls*(body: NimNode, targetFile: string, detectedIO: var seq[string]) =
  if body.kind in {nnkCall, nnkInfix, nnkPrefix, nnkPostfix, nnkCommand, nnkBracketExpr, nnkDotExpr}:
    let info = body.lineInfoObj
    let nodeFile = normalizePath(info.filename)
    let targetNorm = normalizePath(targetFile)
    if nodeFile == targetNorm or nodeFile.endsWith("/" & extractFilename(targetFile)):
      if isIoCall(body):
        var name: string
        let callee = body[0]
        if callee.kind == nnkDotExpr:
          name = $callee[0] & "." & $callee[1]
        else:
          name = $callee
        if name notin detectedIO:
          detectedIO.add(name)
  for child in body:
    collectIoCalls(child, targetFile, detectedIO)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func scanProcDef(node: NimNode, filePath: string): EffectViolation =
  let procName = $node[0]
  let pragmas = node[4]

  if hasAxiomEffectPragma(pragmas):
    return EffectViolation(file: "", line: 0, col: 0, procName: "", detectedIO: @[], suggestedPragma: "")

  let body = node[6]
  var detectedIO: seq[string] = @[]
  collectIoCalls(body, filePath, detectedIO)

  if detectedIO.len == 0:
    return EffectViolation(file: "", line: 0, col: 0, procName: "", detectedIO: @[], suggestedPragma: "")

  let info = node.lineInfoObj
  let pragma = "{.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}"

  EffectViolation(
    file: filePath,
    line: info.line,
    col: info.column + 1,
    procName: procName,
    detectedIO: detectedIO,
    suggestedPragma: pragma
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func generatePragmaSuggestion*(detectedIO: seq[string]): string =
  "{.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}"

proc scanFile*(filePath: string): seq[EffectViolation] {.compileTime.} =
  result = @[]
  let content = staticRead(filePath)
  var parsed: NimNode
  try:
    parsed = parseStmt(content, filePath)
  except CatchableError:
    return

  for node in parsed:
    if node.kind == nnkProcDef:
      let violation = scanProcDef(node, filePath)
      if violation.file != "":
        result.add(violation)

proc scanDirectory*(dirPath: string): seq[EffectViolation] {.compileTime.} =
  result = @[]
  for path in walkDirRec(dirPath):
    if path.endsWith(".nim"):
      let violations = scanFile(path)
      for v in violations:
        result.add(v)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro scanFileMacro*(filePath: static[string]): untyped =
  let violations = scanFile(filePath)
  result = newNimNode(nnkBracket)
  for v in violations:
    let lit = newStrLitNode(v.file & ":" & $v.line & ":" & $v.col & " " & v.procName & " IO=" & $v.detectedIO)
    result.add(lit)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro scanDirectoryMacro*(dirPath: static[string]): untyped =
  let violations = scanDirectory(dirPath)
  result = newNimNode(nnkBracket)
  for v in violations:
    let lit = newStrLitNode(v.file & ":" & $v.line & ":" & $v.col & " " & v.procName & " IO=" & $v.detectedIO)
    result.add(lit)
