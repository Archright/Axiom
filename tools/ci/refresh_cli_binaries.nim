## refresh_cli_binaries — Build entry point for CLI binaries.
## After compilation, ensures ~/.local/bin/ax (and siblings) reflect
## the latest source. Uses native SHA1 via secureHash for
## cross-platform compatibility.

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils]
import checksums/sha1

proc computeFileHash(path: string): string =
  ## Compute SHA1 hash of a file using Nim's native secureHash.
  result = $secureHash(readFile(path))

proc ensureSymlink(target, linkPath: string) =
  if symlinkExists(linkPath):
    removeFile(linkPath)
  createSymlink(target, linkPath)

proc refreshBinary(srcBin, destDir: string) =
  let destBin = destDir / extractFilename(srcBin)
  if fileExists(destBin):
    let srcHash = computeFileHash(srcBin)
    let destHash = computeFileHash(destBin)
    if srcHash == destHash:
      return
  copyFile(srcBin, destBin)
  setFilePermissions(destBin, {fpUserExec, fpUserRead, fpGroupRead, fpOthersRead})

proc main() =
  let repoRoot = getCurrentDir()
  let localBin = getHomeDir() / ".local" / "bin"
  createDir(localBin)

  # Build main binary
  let mainSrc = repoRoot / "src" / "cli" / "main.nim"
  let mainBin = repoRoot / "bin" / "main"
  let (buildOutput, buildExit) = execCmdEx("nim c -o:" & quoteShell(mainBin) & " " & quoteShell(mainSrc))
  if buildExit != 0:
    stderr.writeLine("Build failed: " & buildOutput)
    quit(1)

  # Refresh binaries
  refreshBinary(mainBin, localBin)
  ensureSymlink(localBin / "main", localBin / "ax")

when isMainModule:
  main()
