## tools/inline_facade.nim
## CLI tool to analyze and inline forwarding stubs in src/core/.
## Usage: nim c -r tools/inline_facade.nim <stub_file_path>
##
## This tool identifies forwarding stubs and reports their target modules,
## assisting the facade ratchet deprecation workflow.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, parseopt]

proc analyzeStub(filePath: string) =
  ## Analyze a forwarding stub file and report its forwarding target.
  if not fileExists(filePath):
    echo "ERROR: File not found: " & filePath
    quit(1)

  let content = readFile(filePath)
  var imports: seq[string] = @[]
  var exports: seq[string] = @[]
  var otherLines: int = 0

  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#") or stripped.startsWith("{.") or stripped.startsWith("##"):
      continue
    if stripped.startsWith("import "):
      imports.add(stripped[7 .. ^1].strip())
    elif stripped.startsWith("export "):
      exports.add(stripped[7 .. ^1].strip())
    else:
      inc otherLines

  let isStub = imports.len > 0 and exports.len > 0 and otherLines == 0

  echo "File: " & filePath
  echo "  Is forwarding stub: " & $isStub
  echo "  Imports: " & $imports.len
  for imp in imports:
    echo "    import " & imp
  echo "  Exports: " & $exports.len
  for exp in exports:
    echo "    export " & exp

  if isStub:
    echo "  Target: " & (if imports.len > 0: imports[0] else: "unknown")
    echo "  Action: Can be inlined by replacing 'import " & filePath.extractFilename & "' with 'import " & imports[0] & "'"
  else:
    echo "  Not a pure forwarding stub (has business logic)"

proc main() =
  var p = initOptParser()
  var args: seq[string] = @[]
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument:
      args.add(key)
    of cmdLongOption, cmdShortOption:
      if key == "help" or key == "h":
        echo "Usage: inline_facade.nim <stub_file_path> [stub_file_path2 ...]"
        echo ""
        echo "Analyze forwarding stub files in src/core/ and report their targets."
        echo "Part of the facade ratchet deprecation workflow."
        quit(0)
    of cmdEnd:
      discard

  if args.len == 0:
    echo "Usage: inline_facade.nim <stub_file_path> [stub_file_path2 ...]"
    echo "Run with --help for more information."
    quit(1)

  for arg in args:
    analyzeStub(arg)
    echo ""

main()
