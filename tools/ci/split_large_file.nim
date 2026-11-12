## split_large_file.nim — Split a large .nim file into _core (pure logic) and _io (I/O operations).
##
## Usage: nim c -r tools/ci/split_large_file.nim <path/to/large_file.nim>
##
## The tool:
##   1. Checks the file exceeds 500 lines
##   2. Classifies each line as I/O or pure logic
##   3. Produces:
##        <BASE>_core.nim  — pure logic (funcs, types, const, etc.)
##        <BASE>_io.nim    — I/O operations (readFile, writeFile, echo, execProcess, etc.)
##        <BASE>.nim       — facade that imports and re-exports both
##   4. The original file is backed up to <BASE>.nim.bak
##
## I/O detection patterns (case-insensitive prefix match on stripped line):
##   readFile, writeFile, echo, execProcess, startProcess, open, close,
##   getEnv, putEnv, fileExists, dirExists, removeFile, createDir,
##   moveFile, copyFile, getCurrentDir, setCurrentDir, getAppFilename,
##   walkDir, walkDirRec, existsOrCreateDir, tryRemoveFile, openUrl,
##   execCmd, execCmdEx, execProcesses, rawExec, gorge, staticExec,
##   sleep, getCurrentProcessId, getTempDir, stdout, stderr, stdin,
##   getch, readLine, write, writeln

import core/trusted/layer_declaration
axiomLayer "tools"
# Standalone compilation: define axiomEffect pragma locally.
# When compiled within the full project build, axiom_pragmas.nim (via config.nims)
# provides the canonical definition. Here we provide a fallback for --skipParentCfg.
type IoEffect* = object
template axiomEffect*(effectType: typedesc) {.pragma.}

{.push raises: [].}

import std/[os, strutils]

const
  MinLines = 500

  ## Line-start I/O patterns (stripped). Matches `IO_PATTERN` from the shell script.
  IoPatternsStart = [
    "readFile", "writeFile", "echo", "execProcess", "startProcess",
    "open", "close", "getEnv", "putEnv", "fileExists", "dirExists",
    "removeFile", "createDir", "moveFile", "copyFile",
    "getCurrentDir", "setCurrentDir", "getAppFilename",
    "walkDir", "walkDirRec", "existsOrCreateDir", "tryRemoveFile",
    "openUrl", "execCmd", "execCmdEx", "rawExec",
    "gorge", "staticExec", "sleep", "getCurrentProcessId", "getTempDir",
    "stdout", "stderr", "stdin", "getch", "readLine",
    "import std/os", "import std/osproc", "import std/streams",
    "import std/terminal", "import std/syncio", "import std/asyncdispatch",
    "import os", "import osproc", "import streams",
    "import terminal", "import syncio",
  ]

  ## Inline I/O patterns (anywhere in the line). Matches `IO_INLINE_PATTERN`.
  IoPatternsInline = [
    "readFile", "writeFile", "execProcess", "startProcess",
    "getEnv", "putEnv", "fileExists", "dirExists",
    "removeFile", "createDir", "moveFile", "copyFile",
    "getCurrentDir", "setCurrentDir", "walkDir", "walkDirRec",
    "open(", "close(", "stdout.", "stderr.", "stdin.",
  ]

  ## Special prefix: `write` followed by a non-alpha char (i.e. `write(`, `write "`, etc.)
  WritePrefix = "write"

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

func isIoLine(line: string): bool {.raises: [].} =
  ## Classify a line as I/O or pure logic.
  let stripped = line.strip()

  # Check line-start patterns
  for pat in IoPatternsStart:
    if stripped.startsWith(pat):
      return true

  # Special case: write[^A-Za-z] (write followed by non-alpha)
  if stripped.startsWith(WritePrefix) and stripped.len > WritePrefix.len:
    let next = stripped[WritePrefix.len]
    if not next.isAlphaAscii:
      return true

  # Check inline patterns
  for pat in IoPatternsInline:
    if pat in stripped:
      return true

  return false

# ---------------------------------------------------------------------------
# I/O procs
# ---------------------------------------------------------------------------

proc writeLines(f: File; lines: seq[string]) {.axiomEffect: IoEffect, raises: [CatchableError].} =
  for line in lines:
    f.writeLine(line)

proc main() {.axiomEffect: IoEffect, raises: [CatchableError].} =
  let args = commandLineParams()

  if args.len < 1:
    echo "Usage: split_large_file <path/to/file.nim>"
    quit(1)

  let inputFile = args[0]

  if not fileExists(inputFile):
    echo "Error: file not found: " & inputFile
    quit(1)

  if not inputFile.endsWith(".nim"):
    echo "Error: only .nim files are supported, got: " & inputFile
    quit(1)

  let content = readFile(inputFile)
  let allLines = content.splitLines()
  let lineCount = allLines.len

  if lineCount < MinLines:
    echo "File has " & $lineCount & " lines (minimum " & $MinLines & "). Nothing to split."
    quit(0)

  # Derive output paths
  let dir = inputFile.parentDir()
  let baseName = inputFile.extractFilename().changeFileExt("")
  let coreFile = dir / (baseName & "_core.nim")
  let ioFile = dir / (baseName & "_io.nim")
  let facadeFile = inputFile  # overwrite original as facade
  let backupFile = inputFile & ".bak"

  echo "Splitting " & inputFile & " (" & $lineCount & " lines) → _core + _io"

  # Backup original
  copyFile(inputFile, backupFile)

  # Classify lines
  var coreLines: seq[string] = @[]
  var ioLines: seq[string] = @[]

  for line in allLines:
    if isIoLine(line):
      ioLines.add(line)
    else:
      coreLines.add(line)

  # Write _core.nim
  block:
    var f = open(coreFile, fmWrite)
    f.writeLine("# Auto-generated by split_large_file.nim — pure logic")
    f.writeLine("# Source: " & inputFile)
    f.writeLine("{.push raises: [].}")
    f.writeLine("")
    f.writeLines(coreLines)
    f.writeLine("")
    f.writeLine("{.pop.}")
    close(f)

  # Write _io.nim
  block:
    var f = open(ioFile, fmWrite)
    f.writeLine("# Auto-generated by split_large_file.nim — I/O operations")
    f.writeLine("# Source: " & inputFile)
    f.writeLine("{.push raises: [].}")
    f.writeLine("")
    f.writeLines(ioLines)
    f.writeLine("")
    f.writeLine("{.pop.}")
    close(f)

  # Write facade (re-export both)
  block:
    var f = open(facadeFile, fmWrite)
    f.writeLine("# Facade — imports and re-exports _core and _io parts.")
    f.writeLine("# Auto-generated by split_large_file.nim")
    f.writeLine("# Original backed up at: " & backupFile)
    f.writeLine("")
    f.writeLine("import " & baseName & "_core")
    f.writeLine("import " & baseName & "_io")
    f.writeLine("export " & baseName & "_core")
    f.writeLine("export " & baseName & "_io")
    close(f)

  # Summary
  echo "Done."
  echo "  Core lines : " & $coreLines.len & " → " & coreFile
  echo "  I/O lines  : " & $ioLines.len & "  → " & ioFile
  echo "  Facade     : " & facadeFile
  echo "  Backup     : " & backupFile
  echo ""
  echo "Verify with: nim check --hints:off " & facadeFile

when isMainModule:
  main()

{.pop.}
