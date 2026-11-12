import core/trusted/layer_declaration
axiomLayer "tools"
import api/tools_facade
import std/[os, osproc, strutils, streams]

const vacuityScanner = "proofs/check_vacuity.lean"

proc repoRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  result = getCurrentDir()

proc collectLeanFiles(root: string): seq[string] =
  result = @[]
  if dirExists(root):
    for path in walkDirRec(root):
      if path.endsWith(".lean") and path != "lakefile.lean":
        if "_sorry." in path: continue
        result.add path
  elif fileExists(root) and root.endsWith(".lean"):
    result.add root

proc pathFromArgs(args: seq[string]): string =
  for arg in args:
    if arg.startsWith("--path:"):
      return arg.substr("--path:".len)
  if args.len > 0:
    return args[0]
  result = "tests/fixtures"

proc main(): int {.axiomEffect: IOEffect.} =
  let params = commandLineParams()
  let target = pathFromArgs(params)
  let root = repoRoot()
  let scanner = root / vacuityScanner

  if not fileExists(scanner):
    stderr.writeLine("ERROR: vacuity scanner not found: " & scanner)
    return 1

  let files = collectLeanFiles(root / target)
  if files.len == 0:
    echo "No .lean files found under " & target
    return 0

  var process = startProcess(
    "lean",
    args = @["--run", scanner] & files,
    workingDir = root,
    options = {poStdErrToStdOut, poUsePath}
  )
  var outp = outputStream(process)
  var line = ""
  while outp.readLine(line):
    echo line
  result = process.waitForExit()
  close(process)

  if result != 0:
    stderr.writeLine("ERROR: vacuity scan failed for " & target)

when isMainModule:
  quit(main())
