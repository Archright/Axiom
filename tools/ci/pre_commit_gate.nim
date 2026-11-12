import std/[os, osproc, strutils, sequtils]
import core/parser_utils

proc getGitRoot(): string =
  let (output, exitCode) = execCmdEx("git rev-parse --show-toplevel")
  return if exitCode == 0: output.strip() else: getCurrentDir()

proc getStagedNimFiles(gitRoot: string): seq[string] =
  let (output, exitCode) = execCmdEx("git diff --cached --name-only --diff-filter=d")
  if exitCode != 0 or output.strip().len == 0:
    return @[]

  result = output.splitLines()
    .mapIt(it.strip())
    .filterIt(it.endsWith(".nim"))
    .mapIt(gitRoot / it)
    .filterIt(fileExists(it))

proc checkSyntax(filePath: string): bool =
  ## Syntax-check a staged Nim file using shared IdentCache/ConfigRef caches.
  let content = readFile(filePath)
  if content.len == 0: return true
  let ast = parser_utils.parseStringAST(content)
  result = ast != nil

proc main() =
  # L2 진입 시 스킵
  if getEnv("AXIOM_GATE_L2") == "1":
    quit(0)

  let gitRoot = getGitRoot()
  let stagedFiles = getStagedNimFiles(gitRoot)

  if stagedFiles.len == 0:
    quit(0)

  var hasError = false
  for file in stagedFiles:
    if not checkSyntax(file):
      hasError = true

  if hasError:
    echo "[L1 Gate FAIL] Syntax errors detected in staged files."
    quit(1)
  else:
    echo "[L1 Gate PASS] All staged Nim files have valid syntax."

when isMainModule:
  main()

