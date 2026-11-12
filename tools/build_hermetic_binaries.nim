## tools/build_hermetic_binaries.nim — Hermetic Binary Build Tool (Phase 13)
##
## Builds Lean 4 and Z3 as fully statically linked musl binaries for
## deterministic gate signing. Generates `axiom-toolchain.lock` with
## SHA-256 fingerprints of built binaries.
##
## Architecture:
##   Ensures zero-footprint integrity by eliminating glibc, dynamic linker,
##   and kernel version differences from the verification toolchain.
##
## Subcommands:
##   build   — Print musl compilation commands for review (not executed)
##   verify  — Compare installed binaries against axiom-toolchain.lock hashes
##   status  — Show current toolchain state (musl, lean, z3)
##
## Usage:
##   nim c --hints:off -d:allowMissingZ3 -d:release tools/build_hermetic_binaries.nim
##   bin/build_hermetic_binaries build
##   bin/build_hermetic_binaries verify
##   bin/build_hermetic_binaries status

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[os, strutils, strformat, times, osproc]
import checksums/sha2

const
  LockFilePath = "axiom-toolchain.lock"
  LeanInstallPath = "/usr/local/bin/axiom-lean"
  Z3InstallPath = "/usr/local/bin/axiom-z3"
  LeanSourceUrl = "https://github.com/leanprover/lean4"
  Z3SourceUrl = "https://github.com/Z3Prover/z3"
  LeanVersion = "4.29.0"
  Z3Version = "4.13.4"

type
  ToolchainStatus = object
    muslAvailable: bool
    muslGccPath: string
    muslVersion: string
    leanInstalled: bool
    leanPath: string
    leanVersion: string
    leanHash: string
    z3Installed: bool
    z3Path: string
    z3Version: string
    z3Hash: string

  LockEntry = object
    leanVersion: string
    leanHash: string
    leanPath: string
    z3Version: string
    z3Hash: string
    z3Path: string
    muslVersion: string
    generated: string

# ── Utility ──────────────────────────────────────────────────────────────

proc fileSha256(path: string): string =
  ## Compute SHA-256 hex digest of a file. Returns "not-found" if missing.
  if not fileExists(path):
    return "not-found"
  try:
    let data = readFile(path)
    return $secureHash(Sha_256, data)
  except IOError, OSError:
    return "read-error"

proc runCmd(cmd: string): tuple[output: string, exitCode: int] =
  ## Run a command and capture output. Returns ("", -1) on failure.
  try:
    result = execCmdEx(cmd)
  except OSError, IOError:
    result = ("", -1)

proc findMuslGcc(): tuple[found: bool, path: string] =
  ## Detect musl-gcc cross-compiler in PATH.
  # Try x86_64-linux-musl-gcc first (Arch/Gentoo), then musl-gcc (Alpine)
  for name in ["x86_64-linux-musl-gcc", "musl-gcc"]:
    let (output, code) = runCmd("which " & name)
    if code == 0 and output.strip().len > 0:
      return (true, output.strip())
  return (false, "")

proc muslVersion(gccPath: string): string =
  ## Extract musl-gcc version string.
  let (output, code) = runCmd(gccPath & " --version")
  if code != 0 or output.len == 0:
    return "unknown"
  let firstLine = output.splitLines()[0]
  # Extract version number: typically "musl-gcc (GCC) 13.2.1" or "x86_64-linux-musl-gcc (Alpine ...) 12.2.1"
  for part in firstLine.split(' '):
    if part.len > 0 and part[0].isDigit():
      return part.strip(chars = {'(', ')'})
  return firstLine.strip()

proc detectBinary(path: string, versionFlag: string): tuple[found: bool, version: string] =
  ## Check if a binary exists and extract its version.
  if not fileExists(path):
    return (false, "")
  let (output, code) = runCmd(path & " " & versionFlag)
  if code != 0:
    # Binary exists but version flag failed — still counts as installed
    return (true, "unknown")
  # Extract version from first line
  let firstLine = output.splitLines()[0]
  for word in firstLine.split(' '):
    if word.len > 0 and word[0].isDigit():
      return (true, word.strip(chars = {',', ';', '.'} + Letters))
  return (true, firstLine.strip())

# ── Status ───────────────────────────────────────────────────────────────

proc collectStatus(): ToolchainStatus =
  ## Gather current toolchain state.
  let (muslFound, muslPath) = findMuslGcc()
  result.muslAvailable = muslFound
  result.muslGccPath = muslPath
  result.muslVersion = if muslFound: muslVersion(muslPath) else: "not-installed"

  # Try multiple known paths for lean
  let leanPaths = [LeanInstallPath, "/usr/bin/axiom-lean", "lean"]
  for p in leanPaths:
    let (found, ver) = detectBinary(p, "--version")
    if found:
      result.leanInstalled = true
      result.leanPath = p
      result.leanVersion = if ver.len > 0: ver else: "unknown"
      result.leanHash = fileSha256(p)
      break

  # Try multiple known paths for z3
  let z3Paths = [Z3InstallPath, "/usr/bin/axiom-z3", "z3"]
  for p in z3Paths:
    let (found, ver) = detectBinary(p, "--version")
    if found:
      result.z3Installed = true
      result.z3Path = p
      result.z3Version = if ver.len > 0: ver else: "unknown"
      result.z3Hash = fileSha256(p)
      break

# ── Lock File I/O ────────────────────────────────────────────────────────

proc generateLockFile(status: ToolchainStatus): string =
  ## Produce axiom-toolchain.lock content from current status.
  let now = now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  result = "# axiom-toolchain.lock — Hermetic binary fingerprint\n"
  result &= "# Generated: " & now & "\n"
  result &= "lean_version=" & (if status.leanInstalled: status.leanVersion else: LeanVersion) & "\n"
  result &= "lean_hash=" & (if status.leanInstalled: status.leanHash else: "not-built") & "\n"
  result &= "lean_path=" & (if status.leanInstalled: status.leanPath else: LeanInstallPath) & "\n"
  result &= "z3_version=" & (if status.z3Installed: status.z3Version else: Z3Version) & "\n"
  result &= "z3_hash=" & (if status.z3Installed: status.z3Hash else: "not-built") & "\n"
  result &= "z3_path=" & (if status.z3Installed: status.z3Path else: Z3InstallPath) & "\n"
  result &= "musl_version=" & status.muslVersion & "\n"

proc parseLockFile(path: string): LockEntry =
  ## Parse axiom-toolchain.lock into a LockEntry.
  if not fileExists(path):
    return
  try:
    let content = readFile(path)
    for line in content.splitLines():
      let stripped = line.strip()
      if stripped.startsWith("#") or stripped.len == 0:
        continue
      let eqPos = stripped.find('=')
      if eqPos < 0:
        continue
      let key = stripped[0 ..< eqPos]
      let val = stripped[(eqPos + 1) .. ^1]
      case key
      of "lean_version": result.leanVersion = val
      of "lean_hash": result.leanHash = val
      of "lean_path": result.leanPath = val
      of "z3_version": result.z3Version = val
      of "z3_hash": result.z3Hash = val
      of "z3_path": result.z3Path = val
      of "musl_version": result.muslVersion = val
      of "generated": result.generated = val
      else: discard
  except IOError, OSError:
    discard

# ── Subcommand: status ───────────────────────────────────────────────────

proc cmdStatus(): int =
  ## Display current toolchain status.
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║     Hermetic Toolchain Status (Phase 13)           ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  let status = collectStatus()

  # Musl
  if status.muslAvailable:
    echo "  ✅ musl-gcc:     " & status.muslVersion & " (" & status.muslGccPath & ")"
  else:
    echo "  ❌ musl-gcc:     not found in PATH"
    echo "     Install: sudo apt install musl-tools  (Debian/Ubuntu)"
    echo "              sudo pacman -S musl           (Arch)"

  # Lean
  if status.leanInstalled:
    echo "  ✅ Lean:         " & status.leanVersion & " (" & status.leanPath & ")"
    echo "     SHA-256:      " & status.leanHash
  else:
    echo "  ❌ Lean:         not installed at expected paths"
    echo "     Expected:     " & LeanInstallPath

  # Z3
  if status.z3Installed:
    echo "  ✅ Z3:           " & status.z3Version & " (" & status.z3Path & ")"
    echo "     SHA-256:      " & status.z3Hash
  else:
    echo "  ❌ Z3:           not installed at expected paths"
    echo "     Expected:     " & Z3InstallPath

  # Lock file
  echo ""
  if fileExists(LockFilePath):
    echo "  📄 Lock file:    " & LockFilePath & " (present)"
    let entry = parseLockFile(LockFilePath)
    if entry.generated.len > 0:
      echo "     Generated:    " & entry.generated
  else:
    echo "  📄 Lock file:    " & LockFilePath & " (missing — run 'build' to generate)"

  echo ""
  return 0

# ── Subcommand: build ────────────────────────────────────────────────────

proc cmdBuild(): int =
  ## Print musl static compilation commands for review.
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║     Hermetic Binary Build Commands (Phase 13)      ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""
  echo "⚠️  Commands printed below are for REVIEW only."
  echo "    Execute them manually or in CI."
  echo ""

  let status = collectStatus()

  if not status.muslAvailable:
    echo "❌ musl-gcc not found. Install before proceeding:"
    echo ""
    echo "  Debian/Ubuntu:  sudo apt install musl-tools"
    echo "  Arch:           sudo pacman -S musl"
    echo "  Alpine:         apk add musl-dev gcc (already musl-native)"
    echo ""
    return 1

  echo "─── Step 1: Build Lean 4 (musl static) ───────────────"
  echo ""
  echo "# Clone and build Lean 4 with musl cross-compilation"
  echo "cd /tmp && git clone --depth 1 --branch v" & LeanVersion & " " & LeanSourceUrl
  echo "cd lean4"
  echo ""
  echo "# Configure for musl static build"
  echo "CMAKE_FLAGS=\"-DCMAKE_C_COMPILER=" & status.muslGccPath & "\" \\"
  echo "  CMAKE_FLAGS+=\" -DCMAKE_SYSTEM_NAME=Linux\" \\"
  echo "  CMAKE_FLAGS+=\" -DCMAKE_C_FLAGS='-static'\" \\"
  echo "  CMAKE_FLAGS+=\" -DCMAKE_EXE_LINKER_FLAGS='-static -no-pie'\" \\"
  echo "  cmake -B build $CMAKE_FLAGS"
  echo "cmake --build build -j$(nproc)"
  echo ""
  echo "# Install to axiom-prefixed path"
  echo "sudo cp build/bin/lean " & LeanInstallPath
  echo "sudo chmod 755 " & LeanInstallPath
  echo ""

  echo "─── Step 2: Build Z3 (musl static) ───────────────────"
  echo ""
  echo "# Clone and build Z3 with musl"
  echo "cd /tmp && git clone --depth 1 --branch z3-" & Z3Version & " " & Z3SourceUrl
  echo "cd z3"
  echo ""
  echo "# Configure for musl static build"
  echo "CC=" & status.muslGccPath & " CXX=" & status.muslGccPath.replace("gcc", "g++") & " \\"
  echo "  CFLAGS='-static' CXXFLAGS='-static' LDFLAGS='-static -no-pie' \\"
  echo "  python3 mk_make.py --prefix=/usr/local --static"
  echo "cd build && make -j$(nproc)"
  echo ""
  echo "# Install to axiom-prefixed path"
  echo "sudo cp z3 " & Z3InstallPath
  echo "sudo chmod 755 " & Z3InstallPath
  echo ""

  echo "─── Step 3: Verify and lock ──────────────────────────"
  echo ""
  echo "# Re-run this tool to generate axiom-toolchain.lock"
  echo "bin/build_hermetic_binaries verify"
  echo ""

  # Generate lock file from current status
  let lockContent = generateLockFile(status)
  echo "─── Lock file preview ────────────────────────────────"
  echo ""
  for line in lockContent.splitLines():
    echo "  " & line
  echo ""

  # Write lock file
  try:
    writeFile(LockFilePath, lockContent)
    echo "✅ Written: " & LockFilePath
  except IOError, OSError:
    echo "❌ Failed to write " & LockFilePath
    return 1

  echo ""
  return 0

# ── Subcommand: verify ───────────────────────────────────────────────────

proc cmdVerify(): int =
  ## Compare installed binary hashes against axiom-toolchain.lock.
  echo "╔══════════════════════════════════════════════════════╗"
  echo "║     Hermetic Toolchain Verification (Phase 13)     ║"
  echo "╚══════════════════════════════════════════════════════╝"
  echo ""

  if not fileExists(LockFilePath):
    echo "❌ Lock file not found: " & LockFilePath
    echo "   Run 'build' subcommand first to generate it."
    return 1

  let entry = parseLockFile(LockFilePath)
  echo "  📄 Lock file:   " & LockFilePath
  if entry.generated.len > 0:
    echo "     Generated:  " & entry.generated
  echo ""

  var allPassed = true

  # Verify Lean
  echo "─── Lean verification ───────────────────────────────"
  if entry.leanHash == "not-built":
    echo "  ⏭️  Lean: not built yet (hash = not-built)"
  elif entry.leanPath.len > 0 and fileExists(entry.leanPath):
    let currentHash = fileSha256(entry.leanPath)
    if currentHash == entry.leanHash:
      echo "  ✅ Lean:  hash matches (" & entry.leanVersion & ")"
      echo "     Path:  " & entry.leanPath
    else:
      echo "  ❌ Lean:  HASH MISMATCH"
      echo "     Expected: " & entry.leanHash
      echo "     Current:  " & currentHash
      echo "     Path:     " & entry.leanPath
      allPassed = false
  else:
    echo "  ❌ Lean:  binary not found at " & entry.leanPath
    allPassed = false

  echo ""

  # Verify Z3
  echo "─── Z3 verification ─────────────────────────────────"
  if entry.z3Hash == "not-built":
    echo "  ⏭️  Z3: not built yet (hash = not-built)"
  elif entry.z3Path.len > 0 and fileExists(entry.z3Path):
    let currentHash = fileSha256(entry.z3Path)
    if currentHash == entry.z3Hash:
      echo "  ✅ Z3:    hash matches (" & entry.z3Version & ")"
      echo "     Path:  " & entry.z3Path
    else:
      echo "  ❌ Z3:    HASH MISMATCH"
      echo "     Expected: " & entry.z3Hash
      echo "     Current:  " & currentHash
      echo "     Path:     " & entry.z3Path
      allPassed = false
  else:
    echo "  ❌ Z3:    binary not found at " & entry.z3Path
    allPassed = false

  echo ""

  # Verify musl
  echo "─── musl verification ───────────────────────────────"
  let (_, muslPath) = findMuslGcc()
  if entry.muslVersion.len > 0 and entry.muslVersion != "not-installed":
    echo "  ℹ️  musl:  locked version = " & entry.muslVersion
    if muslPath.len > 0:
      let currentMuslVer = muslVersion(muslPath)
      if currentMuslVer == entry.muslVersion:
        echo "  ✅ musl:  version matches"
      else:
        echo "  ⚠️  musl:  version differs (current: " & currentMuslVer & ")"
        echo "     This may cause non-deterministic builds."
        allPassed = false
    else:
      echo "  ❌ musl:  not found in PATH"
      allPassed = false
  else:
    echo "  ⏭️  musl: not recorded in lock file"

  echo ""

  if allPassed:
    echo "✅ All toolchain checks passed."
    return 0
  else:
    echo "❌ Toolchain verification FAILED. Rebuild with 'build' subcommand."
    return 1

# ── Main ─────────────────────────────────────────────────────────────────

proc main(): int =
  if paramCount() == 0:
    echo "Usage: build_hermetic_binaries <subcommand>"
    echo ""
    echo "Subcommands:"
    echo "  build   — Print musl compilation commands and generate lock file"
    echo "  verify  — Verify installed binaries against axiom-toolchain.lock"
    echo "  status  — Show current toolchain state"
    return 0

  let cmd = paramStr(1).toLowerAscii()
  case cmd
  of "build":
    return cmdBuild()
  of "verify":
    return cmdVerify()
  of "status":
    return cmdStatus()
  else:
    echo "Unknown subcommand: " & paramStr(1)
    echo "Available: build, verify, status"
    return 1

quit(main())
