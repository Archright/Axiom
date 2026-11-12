## tools/ast_invariant_checker.nim — Native Invariant Checker
##
## Scans Nim source files to detect forbidden patterns:
##   1. Direct getEnv() calls — must use trusted/ wrapper
##   2. Broad {.raises: [Exception].} — must narrow to specific exceptions
##   3. Missing axiomEffect on I/O procs — must declare effect
##
## Usage:
##   ast_invariant_checker <dir1> [dir2 ...]
##
## Output: JSON array of violations to stdout.
## Exit code: 0 = pass, 1 = violations found.
##
## Compile:
##   nim c -o:bin/ast_invariant_checker tools/ast_invariant_checker.nim

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[os, strutils, json]

type
  ViolationKind = enum
    vkDirectGetEnv = "direct_getenv"
    vkBroadRaises = "broad_raises"
    vkMissingAxiomEffect = "missing_axiom_effect"

  Violation = object
    kind: ViolationKind
    filePath: string
    line: int
    procName: string
    message: string

const whitelistedFiles = [
  "env_types.nim", "env_types_shadow.nim",
  "core_pure_utils.nim", "axiom_pragmas.nim",
  "shadow_environment.nim", "shadow_environment_shadow.nim",
  "hermetic_sandbox.nim", "hermetic_sandbox_shadow.nim"
]

func isWhitelisted(filePath: string): bool =
  let name = filePath.extractFilename()
  for w in whitelistedFiles:
    if name == w: return true
  false

func skipComment(line: string): bool =
  let stripped = line.strip()
  stripped.startsWith("#") or stripped.startsWith("##")

func extractProcName(line: string): string =
  let stripped = line.strip()
  var s = stripped
  if s.startsWith("proc ") or s.startsWith("func ") or
     s.startsWith("method ") or s.startsWith("macro ") or
     s.startsWith("template ") or s.startsWith("converter ") or
     s.startsWith("iterator "):
    s = s[4..^1].strip()
  elif s.startsWith("proc* ") or s.startsWith("func* ") or
       s.startsWith("method* ") or s.startsWith("macro* ") or
       s.startsWith("template* ") or s.startsWith("converter* ") or
       s.startsWith("iterator* "):
    s = s[5..^1].strip()
  else:
    return ""
  var name = ""
  for ch in s:
    if ch in {'(', ':', '[', ' ', '\t', '='}:
      break
    name.add(ch)
  result = name.strip(chars = {'*', '`'})

func findGetEnvViolations(filePath: string; lines: seq[string]): seq[Violation] =
  result = @[]
  if filePath.isWhitelisted(): return result
  for i, line in lines:
    if line.skipComment(): continue
    let stripped = line.strip()
    if "\"getEnv(" in stripped or "'getEnv(" in stripped: continue
    if "getEnv(" in stripped:
      result.add(Violation(
        kind: vkDirectGetEnv,
        filePath: filePath,
        line: i + 1,
        procName: "",
        message: "Direct getEnv() call — use trusted/ wrapper instead"
      ))

func findBroadRaises(filePath: string; lines: seq[string]): seq[Violation] =
  result = @[]
  for i, line in lines:
    if line.skipComment(): continue
    let stripped = line.strip()
    if "raises:" in stripped and "[Exception]" in stripped:
      let procName = extractProcName(line)
      var contextName = procName
      if contextName.len == 0:
        for j in countdown(i, max(0, i - 10)):
          contextName = extractProcName(lines[j])
          if contextName.len > 0: break
      result.add(Violation(
        kind: vkBroadRaises,
        filePath: filePath,
        line: i + 1,
        procName: contextName,
        message: "Broad {.raises: [Exception].} — narrow to specific exceptions"
      ))

func findMissingAxiomEffect(filePath: string; lines: seq[string]): seq[Violation] =
  result = @[]
  let ioPatterns = [
    "readFile(", "writeFile(", "execProcess(", "startProcess(",
    "execShellCmd(", "stderr.writeLine", "stderr.write ",
    "stdout.write", "open(", "close(", "flushFile(",
    "readAll(", "readLine(", "readBytes(", "writeBytes(",
    "setFilePos(", "getFilePos(", "getFileSize(",
    "existsFile(", "copyFile(", "moveFile(", "removeFile(",
    "createDir(", "removeDir("
  ]

  var i = 0
  while i < lines.len:
    let stripped = lines[i].strip()
    let isProcDef = stripped.startsWith("proc ") or stripped.startsWith("func ") or
                    stripped.startsWith("proc* ") or stripped.startsWith("func* ")
    if isProcDef:
      let procName = extractProcName(lines[i])
      let startLine = i
      var hasAxiomEffect = false
      var procHeaderEnd = i
      var depth = 0
      for j in i ..< min(i + 10, lines.len):
        let hdr = lines[j].strip()
        for ch in hdr:
          if ch == '{': inc depth
          elif ch == '}': dec depth
        if "axiomEffect" in hdr:
          hasAxiomEffect = true
        if depth <= 0 and "{" in hdr:
          procHeaderEnd = j
          break
        if depth <= 0 and j > i and ("=" in hdr or "{" in hdr):
          procHeaderEnd = j
          break
      if not hasAxiomEffect:
        let endSearch = min(startLine + 80, lines.len)
        var hasIo = false
        for j in startLine ..< endSearch:
          if j >= lines.len: break
          let bodyLine = lines[j]
          if skipComment(bodyLine): continue
          for pat in ioPatterns:
            if pat in bodyLine:
              hasIo = true
              break
          if hasIo: break
        if hasIo:
          result.add(Violation(
            kind: vkMissingAxiomEffect,
            filePath: filePath,
            line: startLine + 1,
            procName: procName,
            message: "I/O proc '" & procName & "' missing {.axiomEffect: IoEffect.}"
          ))
    inc i

proc checkFile(filePath: string): seq[Violation] =
  try:
    let content = readFile(filePath)
    if content.len == 0: return @[]
    let lines = content.splitLines()
    result = @[]
    result.add(findGetEnvViolations(filePath, lines))
    result.add(findBroadRaises(filePath, lines))
    result.add(findMissingAxiomEffect(filePath, lines))
  except IOError, OSError:
    result = @[]

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    stderr.writeLine("Usage: ast_invariant_checker <dir1> [dir2 ...]")
    quit(2)

  var allViolations: seq[Violation] = @[]
  for target in args:
    if fileExists(target) and target.endsWith(".nim"):
      allViolations.add(checkFile(target))
    elif dirExists(target):
      for entry in walkDirRec(target):
        if entry.endsWith(".nim"):
          allViolations.add(checkFile(entry))
    else:
      stderr.writeLine("Warning: skipping ", target, " (not found or not .nim)")

  let violationsJson = % allViolations
  echo violationsJson.pretty()

  if allViolations.len > 0:
    quit(1)
  else:
    quit(0)

when isMainModule:
  main()

{.pop}
