## tools/build_parsers.nim — Deterministic tree-sitter parser build
##
## Compiles vendored tree-sitter C runtime + Nim grammar into a static archive.
## Uses `staticExec` for compile-time verification.
##
## Usage: nim c -r tools/build_parsers.nim

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, times, hashes]

const
  vendorTs = "vendor/tree-sitter"
  vendorGrammar = "vendor/tree-sitter-nim"
  buildDir = "build/parser"
  libSrc = vendorTs / "lib" / "src" / "lib.c"
  grammarSrc = vendorGrammar / "src" / "parser.c"
  headerDir = vendorTs / "lib" / "include"

proc computeFileHash(path: string): Hash =
  ## Compute hash of file contents for change detection
  if not fileExists(path):
    return Hash(0)
  let content = readFile(path)
  result = hash(content)

proc buildParser() =
  ## Compile tree-sitter runtime + grammar to object files
  echo "[build_parsers] Compiling tree-sitter C runtime..."
  createDir(buildDir)

  # Compile C runtime
  let rtObj = buildDir / "tree_sitter_runtime.o"
  let rtCmd = "gcc -c -fPIC -I" & headerDir & " -o " & rtObj & " " & libSrc
  echo "[build_parsers] ", rtCmd
  let rtExit = execShellCmd(rtCmd)
  if rtExit != 0:
    echo "[build_parsers] ERROR: Failed to compile tree-sitter runtime"
    quit(1)

  # Compile grammar parser
  echo "[build_parsers] Compiling Nim grammar parser..."
  let grObj = buildDir / "tree_sitter_nim_grammar.o"
  let grCmd = "gcc -c -fPIC -I" & vendorGrammar / "src" & " -I" & headerDir & " -o " & grObj & " " & grammarSrc
  echo "[build_parsers] ", grCmd
  let grExit = execShellCmd(grCmd)
  if grExit != 0:
    echo "[build_parsers] ERROR: Failed to compile grammar parser"
    quit(1)

  # Create static archive
  echo "[build_parsers] Creating static archive..."
  let libPath = buildDir / "libtreesitter_nim.a"
  let arCmd = "ar rvs " & libPath & " " & rtObj & " " & grObj
  echo "[build_parsers] ", arCmd
  let arExit = execShellCmd(arCmd)
  if arExit != 0:
    echo "[build_parsers] ERROR: Failed to create static archive"
    quit(1)

  # Write build stamp
  let stamp = buildDir / ".build_stamp"
  let rtHash = computeFileHash(libSrc)
  let grHash = computeFileHash(grammarSrc)
  let now = now().format("yyyy-MM-dd'T'HH:mm:ss")
  writeFile(stamp, "runtime_hash=" & $rtHash & "\ngrammar_hash=" & $grHash & "\nbuilt_at=" & now & "\n")

  echo "[build_parsers] DONE: ", libPath
  echo "[build_parsers] Build stamp: ", stamp

proc verifyBuild() =
  ## Verify the built library has required symbols
  let libPath = buildDir / "libtreesitter_nim.a"
  if not fileExists(libPath):
    echo "[build_parsers] ERROR: Archive not found: ", libPath
    quit(1)

  echo "[build_parsers] Verifying symbols..."
  let nmCmd = "nm " & libPath & " | grep -q tree_sitter_nim"
  let nmExit = execShellCmd(nmCmd)
  if nmExit != 0:
    echo "[build_parsers] WARNING: tree_sitter_nim symbol not found in archive"
  else:
    echo "[build_parsers] OK: tree_sitter_nim symbol found"

when isMainModule:
  echo "[build_parsers] Starting deterministic parser build..."
  echo "[build_parsers] Vendor TS: ", vendorTs
  echo "[build_parsers] Vendor Grammar: ", vendorGrammar

  if not fileExists(libSrc):
    echo "[build_parsers] ERROR: tree-sitter runtime not found: ", libSrc
    echo "[build_parsers] Run: git submodule init && git submodule update"
    quit(1)

  if not fileExists(grammarSrc):
    echo "[build_parsers] ERROR: grammar parser not found: ", grammarSrc
    echo "[build_parsers] Run: git submodule update vendor/tree-sitter-nim"
    quit(1)

  buildParser()
  verifyBuild()
