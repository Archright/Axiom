import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, sequtils]

const
  ElfBinaries = [
    "src/cli/procedure_gate",
    "tests/fuzz/generate_fuzz_input",
  ]

proc runCmd(cmd: string): tuple[output: string, exitCode: int] =
  echo "  $ " & cmd
  let repoRoot = getCurrentDir()
  result = execCmdEx(cmd, workingDir = repoRoot)

proc main() =
  echo "=== Axiom Repo Vacuum ===\n"

  # 1. Remove ELF binaries from git tracking
  echo "[1/3] Removing tracked ELF binaries..."
  for binary in ElfBinaries:
    let (_, code) = runCmd("git ls-files --error-unmatch " & binary)
    if code == 0:
      discard runCmd("git rm --cached " & binary)
      echo "  Removed from index: " & binary
    else:
      echo "  Not tracked (skip): " & binary

  # 2. Update .gitignore with ELF patterns
  echo "\n[2/3] Updating .gitignore..."
  let gitignorePath = ".gitignore"
  let elfPatterns = [
    "# ELF binaries (vacuum-generated)",
    "src/cli/procedure_gate",
    "tests/fuzz/generate_fuzz_input",
    "*.elf",
  ]
  var existing = ""
  if fileExists(gitignorePath):
    existing = readFile(gitignorePath)
  var added: seq[string] = @[]
  for pattern in elfPatterns:
    if pattern notin existing:
      added.add(pattern)
  if added.len > 0:
    var content = existing
    if not content.endsWith("\n"):
      content.add("\n")
    content.add(added.join("\n") & "\n")
    writeFile(gitignorePath, content)
    echo "  Added " & $added.len & " patterns to .gitignore"
  else:
    echo "  All patterns already in .gitignore"

  # 3. Clean empty vendor directory
  echo "\n[3/3] Checking vendor/tree-sitter-nim..."
  let vendorDir = "vendor" / "tree-sitter-nim"
  if dirExists(vendorDir):
    var contents: seq[string] = @[]
    for kind, path in walkDir(vendorDir):
      contents.add(path)
    if contents.len == 0:
      removeDir(vendorDir)
      echo "  Removed empty vendor/tree-sitter-nim/"
    else:
      echo "  vendor/tree-sitter-nim/ has " & $contents.len & " entries — not empty, skipping"
  else:
    echo "  vendor/tree-sitter-nim/ does not exist — skipping"

  echo "\n=== Vacuum complete ==="
  echo "Run 'git status' to review changes, then commit when satisfied."

when isMainModule:
  main()
