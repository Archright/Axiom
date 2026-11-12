## verify_stubs.nim — Forwarding Stub Integrity Check (Nim port)
## AGENTS.md §1.3b: Stubs must not contain business logic.
## Only import + export + comments + blank lines allowed.
##
## Scans src/core/*.nim files ≤10 lines (forwarding stub candidates).
## Exit code: 0 = all clean, 1 = violations found

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]

proc findRepoRoot(): string =
  var dir = getAppDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = parentDir(dir)
    if parent == dir:
      break
    dir = parent
  result = getAppDir() / ".." / ".."
  normalizePath(result)

type
  StubViolation = object
    filename: string
    lineCount: int
    violatingLines: seq[(int, string)]

proc isAllowedLine(line: string): bool =
  let stripped = line.strip()
  if stripped.len == 0:
    return true
  if stripped.startsWith("#"):
    return true
  if stripped.startsWith("import ") or stripped.startsWith("import{"):
    return true
  if stripped.startsWith("export ") or stripped.startsWith("export{"):
    return true
  if stripped.startsWith("{."):
    return true
  if stripped.startsWith("axiomLayer "):
    return true
  result = false

proc main() =
  let repoRoot = findRepoRoot()
  let srcCore = repoRoot / "src" / "core"

  echo "=== Forwarding Stub Integrity Check (AGENTS.md §1.3b) ==="
  echo ""

  if not dirExists(srcCore):
    echo "⚠️  src/core/ not found at " & srcCore
    quit(1)

  var violations: seq[StubViolation] = @[]

  for kind, path in walkDir(srcCore):
    if kind != pcFile or not path.endsWith(".nim"):
      continue

    let filename = extractFilename(path)
    try:
      let content = readFile(path)
      let lines = content.splitLines()
      let lineCount = lines.len

      if lineCount > 10:
        continue

      var violatingLines: seq[(int, string)] = @[]
      for i, line in lines:
        if not isAllowedLine(line):
          violatingLines.add((i + 1, line))

      if violatingLines.len > 0:
        violations.add(StubViolation(
          filename: filename,
          lineCount: lineCount,
          violatingLines: violatingLines
        ))
    except IOError:
      discard

  for v in violations:
    echo "❌ VIOLATION: " & v.filename & " (" & $v.lineCount & " lines) contains business logic:"
    for (lineNum, lineContent) in v.violatingLines:
      echo "   | " & lineContent
    echo ""

  echo ""
  if violations.len > 0:
    echo "❌ " & $violations.len & " stub(s) contain business logic. Move implementation to sub-module."
    echo "   Fix: Keep only 'import sub/module; export sub/module' in the stub."
    quit(1)
  else:
    echo "✅ All forwarding stubs are clean (import+export only)."
    quit(0)

when isMainModule:
  main()
