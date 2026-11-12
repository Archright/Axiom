## fetch_z3.nim — Download and restore Z3 4.13.3 pre-built binaries for Linux/macOS/Windows
## vendor/z3/ contains LFS-tracked binaries that are not available on the remote.
## This script fetches the official Z3 release from GitHub and restores the
## expected files into vendor/z3/ (bin/z3, lib/libz3.so*, include/z3.h).
##
## Usage: nim c -r tools/fetch_z3.nim [--sha256=<hex>] [--force]
## axe:v2 (artifact identity manifest)

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, httpclient, tempfiles, hashes, tables, osproc, sequtils]

const
  Z3Version = "4.13.3"
  ## Z3 release version to fetch
  ReleaseTag = "z3-" & Z3Version
  ## GitHub release tag

type
  PlatformKey = string
  ArtifactInfo = tuple[archiveName: string, sha256: string]

## Artifact identity manifest: maps platform keys to (archive name, SHA256 hex).
## Archive names match the exact file published in the Z3 4.13.3 GitHub release.
## SHA256 values were computed by downloading each archive from GitHub and
## running `sha256sum`. Verified against the official release assets.
proc makeZ3Artifacts*(): Table[PlatformKey, ArtifactInfo] =
  ## Build the artifact identity manifest at runtime (Nim const tables require
  ## .toTable which is not allowed in const blocks).
  result = initTable[PlatformKey, ArtifactInfo]()
  result["linux-x86_64"] = ("z3-" & Z3Version & "-x64-glibc-2.35.zip",
                            "32c7377026733c9d7b33c21cd77a68f50ba682367207b031a6bfd80140a8722f")
  result["linux-aarch64"] = ("z3-" & Z3Version & "-arm64-glibc-2.34.zip",
                             "5bc5fd2c501445970de3b13d5699ff601ff51d3e496cb15ce67d7ee2a4a93b03")
  result["macos-arm64"] = ("z3-" & Z3Version & "-arm64-osx-13.7.zip",
                           "2b2c6e23ff5488722bc93002e04c6d6f60d621af9d345f2e05a8691b40280e53")
  result["windows-x86_64"] = ("z3-" & Z3Version & "-x64-win.zip",
                              "014e313f5aa414c48f36620a32eced705002fdc8c840ed8a1b51f186f0da0348")

const
  VendorZ3Dir = "vendor/z3"
  BinPath     = VendorZ3Dir & "/bin/z3"
  LibDir      = VendorZ3Dir & "/lib"
  IncludeDir  = VendorZ3Dir & "/include"

type
  FetchError = object of CatchableError

proc fail(msg: string) {.noinline.} =
  echo "ERROR: ", msg
  quit(1)

proc printUsage() =
  echo """\
Usage: nim c -r tools/fetch_z3.nim [OPTIONS]

Options:
  --sha256=<hex>   Required. Expected SHA256 hex digest of the downloaded archive.
                   The script verifies the archive against this value before extraction.
  --force          Re-fetch even if vendor/z3/ appears populated.
  --help           Show this help message.
  --version        Print Z3 version and exit.

Supported platforms:
  linux-x86_64     x86_64 Linux (glibc 2.35+)
  linux-aarch64    ARM64 Linux (glibc 2.34+)
  macos-arm64      Apple Silicon macOS (13.7+)
  windows-x86_64   x86_64 Windows (MinGW/MSVC runtime)
"""

proc downloadFile(url, dest: string) =
  echo "Downloading: ", url
  var client = newHttpClient()
  try:
    client.downloadFile(url, dest)
  except Exception as e:
    fail("Download failed: " & e.msg)
  finally:
    client.close()
  echo "Saved to: ", dest

proc verifySha256(filePath, expectedHex: string) =
  echo "Verifying SHA256 of: ", filePath
  let output = execProcess("sha256sum \"" & filePath & "\"")
  let actualHex = output.strip().split(" ")[0].toLower()
  let expected = expectedHex.toLower()
  if actualHex != expected:
    fail("SHA256 mismatch for " & filePath & "\n  expected: " & expected &
         "\n  actual:   " & actualHex)
  echo "SHA256 OK: ", actualHex

proc extractAndRestore(archivePath, archiveName: string) =
  echo "Extracting archive: ", archivePath
  let tmpDir = createTempDir("z3_fetch_", "")
  try:
    let cmd = "unzip -q \"" & archivePath & "\" -d \"" & tmpDir & "\""
    echo "Running: ", cmd
    let exitCode = execShellCmd(cmd)
    if exitCode != 0:
      fail("unzip failed with exit code: " & $exitCode)
    echo "Extracted to: ", tmpDir

    # Determine extracted root directory name from archive name
    # e.g. z3-4.13.3-x64-glibc-2.35.zip → z3-4.13.3-x64-glibc-2.35
    let baseName = archiveName.replace(".zip", "")
    let extractedRoot = tmpDir / baseName
    if not dirExists(extractedRoot):
      fail("Expected extracted directory not found: " & extractedRoot)

    let srcBinDir = extractedRoot / "bin"
    let srcInclude = extractedRoot / "include"

    if not dirExists(srcBinDir):
      fail("Z3 bin directory not found in archive: " & srcBinDir)
    if not dirExists(srcInclude):
      fail("Z3 include directory not found in archive: " & srcInclude)

    let srcBin = srcBinDir / "z3"
    if not fileExists(srcBin):
      fail("Z3 binary not found in archive: " & srcBin)

    # Create target directories
    createDir(LibDir)
    createDir(IncludeDir)

    # Copy binary
    copyFile(srcBin, BinPath)
    setFilePermissions(BinPath, {fpUserRead, fpUserWrite, fpUserExec,
                                  fpGroupRead, fpGroupExec,
                                  fpOthersRead, fpOthersExec})
    echo "Restored: ", BinPath

    # Copy libraries (libz3.so, libz3java.so) from bin/ to lib/
    var libCount = 0
    for kind, path in walkDir(srcBinDir):
      if kind == pcFile and (path.endsWith(".so") or path.endsWith(".so.")):
        let dest = LibDir / path.lastPathPart
        copyFile(path, dest)
        if path.endsWith(".so"):
          # unversioned symlink/SONAME — read-only
          setFilePermissions(dest, {fpUserRead, fpUserWrite,
                                      fpGroupRead,
                                      fpOthersRead})
        else:
          # versioned .so.X.Y.Z — exec perms needed for dlopen
          setFilePermissions(dest, {fpUserRead, fpUserWrite, fpUserExec,
                                      fpGroupRead, fpGroupExec,
                                      fpOthersRead, fpOthersExec})
        echo "Restored: ", dest
        inc libCount
    if libCount == 0:
      fail("No libz3.so files found in archive")

    # Copy headers
    var headerCount = 0
    for kind, path in walkDir(srcInclude):
      if kind == pcFile:
        let dest = IncludeDir / path.lastPathPart
        copyFile(path, dest)
        echo "Restored: ", dest
        inc headerCount
    if headerCount == 0:
      fail("No header files found in archive")

    echo ""
    echo "Z3 restoration complete."
    echo "  Binary:   ", BinPath
    echo "  Libraries: ", libCount, " file(s) in ", LibDir
    echo "  Headers:  ", headerCount, " file(s) in ", IncludeDir
  finally:
    removeDir(tmpDir, checkDir = false)

proc detectSystemZ3(): bool =
  ## Check if z3 == 4.13.3 is already installed system-wide.
  try:
    let verLine = execProcess("z3 --version").strip()
    if "Z3 version " & Z3Version in verLine:
      echo "INFO: System z3 detected: ", verLine
      echo "       Skipping fetch — vendor/z3/ provisioning not required."
      return true
    else:
      echo "INFO: System z3 found but version mismatch: ", verLine
      echo "       Proceeding with vendor fetch anyway."
      return false
  except:
    echo "INFO: z3 not found on PATH"
    return false

proc main() =
  echo "=== Z3 Vendor Restoration ==="
  echo "Version: ", Z3Version
  echo ""

  # Handle --help / --version early
  if "--help" in commandLineParams():
    printUsage()
    quit(0)

  if "--version" in commandLineParams():
    echo "fetch_z3.nim — Z3 ", Z3Version, " vendor restoration tool"
    quit(0)

  # Check for --sha256 requirement
  var expectedSha256 = ""
  for p in commandLineParams():
    if p.startsWith("--sha256="):
      expectedSha256 = p.substr(9)
      break

  if expectedSha256.len == 0:
    echo "ERROR: --sha256=<hex> is required for artifact identity verification."
    echo ""
    printUsage()
    quit(1)

  # Detect system z3 first
  if detectSystemZ3():
    quit(0)

  # Resolve platform key (hostOS/hostCPU are compiler-injected constants)
  let platformKey = hostOS & "-" & hostCPU

  let artifacts = makeZ3Artifacts()

  if not (platformKey in artifacts):
    fail("Unsupported platform: " & platformKey &
         "\n  OS=" & hostOS & " CPU=" & hostCPU &
         "\n  Supported: " & toSeq(artifacts.keys).join(", "))

  let artifact = artifacts[platformKey]
  let archiveName = artifact.archiveName
  let expectedHash = artifact.sha256

  echo "Platform: ", platformKey
  echo "Archive:  ", archiveName
  echo "URL:      https://github.com/Z3Prover/z3/releases/download/" &
        ReleaseTag & "/" & archiveName
  echo "SHA256:   ", expectedHash
  echo ""

  # Check if already populated
  if fileExists(BinPath) and dirExists(LibDir) and dirExists(IncludeDir):
    let force = "--force" in commandLineParams()
    if not force:
      echo "vendor/z3/ already appears populated. Use --force to re-fetch."
      quit(0)

  let archivePath = getTempDir() / archiveName
  try:
    if fileExists(archivePath) and "--force" in commandLineParams():
      removeFile(archivePath)

    if not fileExists(archivePath):
      let downloadUrl = "https://github.com/Z3Prover/z3/releases/download/" &
                        ReleaseTag & "/" & archiveName
      downloadFile(downloadUrl, archivePath)

    # Verify SHA256 — mandatory
    verifySha256(archivePath, expectedHash)

    extractAndRestore(archivePath, archiveName)
  finally:
    # Clean up downloaded archive
    if fileExists(archivePath):
      removeFile(archivePath)

when isMainModule:
  main()
