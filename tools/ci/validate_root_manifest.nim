# validate_root_manifest.nim — Root manifest validator for Filesystem Contract V2.
#
# Usage: validate_root_manifest [--root <dir>] [--expected-forbidden <path>...] [--strict]
# Exit 0 = PASS, exit 1 = violation.

import std/[os, osproc, strutils, tables]

# ---------------------------------------------------------------------------
# Classification constants
# ---------------------------------------------------------------------------

const RequiredDirs: seq[string] = @[
  "src", "tests", "tools", "proofs", "data", "docs", "config"
]

const OptionalDirs: seq[string] = @[
  "bin", "build", "logs", "vendor"
]

const ForbiddenDirs: seq[string] = @[
  "cli", "templates", "benchmarks", "trusted", "tmp", "deps",
  # deleted build caches — regeneration is a contract violation
  "nimcache", ".nimcache", ".lake"
]

const ForbiddenFiles: seq[string] = @[
  "debug_real.nims", "deferred_migration.json", "proof_universe.lock"
]

const ExactAllowedFiles: seq[string] = @[
  "AGENTS.md", "README.md", "LICENSE", "THIRD-PARTY-NOTICES.md", "Makefile",
  "axiom.nimble", "config.nims", "nimble.lock", "axiom.lock",
  "axiom.toml", "topology.json", "topology.lock", "topology_policy.json",
  "promotion_intent.json", "flake.nix",
  "lakefile.toml", "lake-manifest.json", "lean-toolchain",
  "Dockerfile.build",
  # dot / toolchain files
  ".axiom_root", ".gitignore", ".gitattributes", ".editorconfig",
  ".dockerignore", ".cursorrules", ".envrc",
  # ignored root (EXACT_ALLOWED)
  "config.json", "nimble.paths", "opencode.json",
]

const ExactAllowedDirs: seq[string] = @[
  ".githooks", ".github", ".config", ".opencode",
  # VCS-internal + runtime state dirs (always allowed)
  ".git", ".axiom", ".cache",
  # tracked content directories (EXACT_ALLOWED — docs/spec/filesystem_contract.md §2.4)
  "ci", "experiments", "_lto_evidence",
  "LICENSES", "CLA", "compliance",
]

const PatternAllowedEnvs: seq[string] = @[
  "production", "development", "staging", "test", "local"
]

# bin/ canonical surface names
const CanonicalBinNames: seq[string] = @["ax", "run_gate", "axiom-gate"]

# bin/ legacy exception: tracked Nim source stubs (NOT ELF), grandfathered
# under I2 (docs/spec/filesystem_contract.md §7.1) — currently only
# bin/axiom.nim (compile-time gate stub detection).
const LegacyBinExceptions: seq[string] = @["axiom.nim"]

# Forbidden source extensions in bin/
const ForbiddenBinExtensions: seq[string] = @[".nim", ".nims", ".c", ".py", ".sh"]

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  Classification = enum
    clExactAllowed
    clPatternAllowed
    clForbidden
    clOptional
    clRequired
    clUnknown

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc basename(path: string): string =
  ## Extract the final component of a path (like Unix basename).
  result = path
  let lastSlash = path.rfind('/')
  if lastSlash >= 0:
    result = path.substr(lastSlash + 1)

proc hasExtension(name, ext: string): bool =
  ## Case-sensitive extension check.
  if name.len <= ext.len:
    return false
  name.substr(name.len - ext.len) == ext

proc isElfBinary(path: string): bool =
  var f: File
  if open(f, path, fmRead):
    defer: close(f)
    var magic: array[4, char]
    let n = readBuffer(f, addr magic[0], 4)
    if n < 4:
      return false
    return magic[0] == '\x7f' and magic[1] == 'E' and magic[2] == 'L' and magic[3] == 'F'
  return false

proc isShebangScript(path: string): bool =
  var f: File
  if open(f, path, fmRead):
    defer: close(f)
    var buf: array[2, char]
    let n = readBuffer(f, addr buf[0], 2)
    if n < 2:
      return false
    return buf[0] == '#' and buf[1] == '!'
  return false

proc hasForbiddenSourceExtension(name: string): bool =
  for ext in ForbiddenBinExtensions:
    if hasExtension(name, ext):
      return true
  return false

proc hasSecretName(name: string): bool =
  ## Check for secret-classified names: .env*, *.pem, *.key, id_rsa*
  if name.startsWith(".env"):
    return true
  if hasExtension(name, ".pem") or hasExtension(name, ".key"):
    return true
  if name.startsWith("id_rsa"):
    return true
  return false

proc isHashSuffixBinary(name: string): bool =
  ## Pattern: <base>_<HEX>=8+ (last underscore-separated segment is all hex, >=8 chars)
  let lastUnderscore = name.rfind('_')
  if lastUnderscore < 0:
    return false
  let suffix = name.substr(lastUnderscore + 1)
  if suffix.len < 8:
    return false
  for ch in suffix:
    if ch notin {'0'..'9', 'A'..'F', 'a'..'f'}:
      return false
  return true

# ---------------------------------------------------------------------------
# Classification
# ---------------------------------------------------------------------------

proc classifyEntry(name: string): Classification =
  # 1. EXACT_ALLOWED files
  if name in ExactAllowedFiles:
    return clExactAllowed

  # 2. EXACT_ALLOWED dirs
  if name in ExactAllowedDirs:
    return clExactAllowed

  # 3. PATTERN_ALLOWED: .env.<env> where env is in the allowed set
  if name.startsWith(".env."):
    let env = name.substr(5)  # skip ".env."
    if env in PatternAllowedEnvs:
      return clPatternAllowed

  # 4. FORBIDDEN dirs
  if name in ForbiddenDirs:
    return clForbidden

  # 5. FORBIDDEN files
  if name in ForbiddenFiles:
    return clForbidden

  # 6. FORBIDDEN pattern: .env* (except .env.<env> already handled above)
  if name.startsWith(".env"):
    return clForbidden

  # 7. OPTIONAL dirs
  if name in OptionalDirs:
    return clOptional

  # 8. REQUIRED dirs
  if name in RequiredDirs:
    return clRequired

  # 9. UNKNOWN
  return clUnknown

# ---------------------------------------------------------------------------
# bin/ contents contract check
# ---------------------------------------------------------------------------

proc checkBinContents(rootDir: string): seq[string] =
  let binDir = rootDir / "bin"
  if not dirExists(binDir):
    return @[]

  for entry in walkDir(binDir, relative = true, checkDir = false):
    let fullPath = binDir / entry.path
    let name = entry.path

    # (d) Single directory depth only — no subdirectories in bin/
    if dirExists(fullPath):
      result.add "FAIL: bin/" & entry.path & " forbidden (directory in bin/ violates single-depth rule)"
      continue

    # Legacy exception: tracked Nim source stub, grandfathered under I2 (§7.1)
    if name in LegacyBinExceptions:
      continue

    # (a) Canonical surface names
    if name in CanonicalBinNames:
      continue

    # (e) Shebang scripts — forbidden
    if isShebangScript(fullPath):
      result.add "FAIL: bin/" & entry.path & " forbidden (shebang script in bin/)"
      continue

    # (e) Forbidden source extensions
    if hasForbiddenSourceExtension(name):
      result.add "FAIL: bin/" & entry.path & " forbidden (source extension in bin/)"
      continue

    # (e) Secret names
    if hasSecretName(name):
      result.add "FAIL: bin/" & entry.path & " forbidden (secret-classified name in bin/)"
      continue

    # (b) Hash-suffix binaries — allowed if they survived the above checks
    if isHashSuffixBinary(name):
      continue

    # (c) ELF executables
    if isElfBinary(fullPath):
      continue

    # Anything else is an unclassified materialization → FAIL
    result.add "FAIL: bin/" & entry.path & " forbidden (unclassified materialization — not ELF, not hash-suffix, not canonical surface)"
  # end for

# ---------------------------------------------------------------------------
# OPTIONAL contents contracts for build/, logs/, vendor/
# ---------------------------------------------------------------------------

proc checkOptionalContents(rootDir: string): seq[string] =
  for optDir in ["build", "logs", "vendor"]:
    let dirPath = rootDir / optDir
    if not dirExists(dirPath):
      continue
    for entry in walkDir(dirPath, relative = true, checkDir = false):
      let fullPath = dirPath / entry.path
      let name = entry.path
      # Skip directories — only files are checked for secret names
      if dirExists(fullPath):
        continue
      # Secret names: .env*, *.pem, *.key, id_rsa*
      if hasSecretName(name):
        result.add "FAIL: " & optDir & "/" & entry.path & " forbidden (secret-classified name in " & optDir & "/)"

# ---------------------------------------------------------------------------
# logs/ untracked transition check
# ---------------------------------------------------------------------------

proc checkLogsUntracked(rootDir: string): seq[string] =
  let logsDir = rootDir / "logs"
  if not dirExists(logsDir):
    return @[]
  # Query git for tracked files under logs/
  let gitCmd = "git -C " & quoteShell(rootDir) & " ls-files logs/"
  let r = execCmdEx(gitCmd, options = {poStdErrToStdOut})
  if r.exitCode != 0:
    # Not a git repo or git unavailable — tracked status is UNKNOWN → FAIL
    # (fail-closed per docs/spec/filesystem_contract.md §7.3; never a silent skip)
    result.add "FAIL: logs/ tracked-status UNKNOWN — git ls-files exit " &
               $r.exitCode & " (fail-closed)"
    return
  for line in r.output.strip.splitLines:
    if line.len > 0:
      result.add "FAIL: logs/" & line & " is git-tracked (must be untracked per V2)"

# ---------------------------------------------------------------------------
# vendor/ embedded git directory check
# ---------------------------------------------------------------------------

proc checkVendorGitDir(rootDir: string): seq[string] =
  let ed25519Git = rootDir / "vendor" / "ed25519" / ".git"
  if dirExists(ed25519Git):
    result.add "FAIL: vendor/ed25519/.git exists (embedded git directory forbidden)"

# ---------------------------------------------------------------------------
# Main validation logic
# ---------------------------------------------------------------------------

proc validateRoot(rootDir: string,
                  expectedForbidden: seq[string],
                  strict: bool): seq[string] =
  var violations: seq[string]

  # Check that rootDir exists
  if not dirExists(rootDir):
    violations.add "FAIL: " & rootDir & " directory does not exist"
    return violations

  # Track which REQUIRED dirs are present
  var requiredPresent = initTable[string, bool]()
  for d in RequiredDirs:
    requiredPresent[d] = false

  # Iterate root entries
  for entry in walkDir(rootDir, relative = true, checkDir = false):
    let name = entry.path

    let cls = classifyEntry(name)

    case cls
    of clExactAllowed:
      discard  # PASS
    of clPatternAllowed:
      discard  # PASS
    of clForbidden:
      if not strict and name in expectedForbidden:
        stdout.write "INFO: " & name & " is expected (deferred)\n"
      else:
        violations.add "FAIL: " & name & " forbidden"
    of clOptional:
      # Contents contract checked separately
      discard
    of clRequired:
      requiredPresent[name] = true
    of clUnknown:
      violations.add "FAIL: " & name & " unknown"

  # Check REQUIRED dirs
  for d in RequiredDirs:
    if not requiredPresent.getOrDefault(d, false):
      violations.add "FAIL: " & d & " required missing"

  # Check bin/ contents contract
  let binViolations = checkBinContents(rootDir)
  for v in binViolations:
    violations.add v

  # Check build/, logs/, vendor/ contents contracts
  let optViolations = checkOptionalContents(rootDir)
  for v in optViolations:
    violations.add v

  # Check logs/ for git-tracked files (untracked transition)
  let logsViolations = checkLogsUntracked(rootDir)
  for v in logsViolations:
    violations.add v

  # Check vendor/ embedded git directories
  let vendorViolations = checkVendorGitDir(rootDir)
  for v in vendorViolations:
    violations.add v

  return violations

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

proc printUsage() =
  echo "Usage: validate_root_manifest [--root <dir>] [--expected-forbidden <path>...] [--strict]"
  echo "  --root <dir>           Root directory to validate (default: cwd)"
  echo "  --expected-forbidden   Allow specific FORBIDDEN entries (repeatable)"
  echo "  --strict               Force strict mode (ignore expected-forbidden relaxations)"
  echo ""
  echo "V2 contract checks: forbidden files, unknown entries, required dirs,"
  echo "  bin/ contents, logs/ git-tracked detection, vendor/ embedded .git detection"

proc main() =
  var rootDir = getCurrentDir()  # default: current working directory
  var expectedForbidden: seq[string] = @[]
  var strict = false  # --strict flag: ignore --expected-forbidden relaxations

  var args = commandLineParams()
  var i = 0
  while i < args.len:
    let a = args[i]
    if a == "--root" and i + 1 < args.len:
      inc i
      rootDir = args[i]
    elif a.startsWith("--root="):
      rootDir = a.substr(7)
    elif a == "--expected-forbidden":
      # Consume all following non-flag arguments as expected-forbidden entries
      inc i
      while i < args.len and not args[i].startsWith("-"):
        expectedForbidden.add args[i]
        inc i
      continue  # skip the outer inc i
    elif a.startsWith("--expected-forbidden="):
      expectedForbidden.add a.substr(21)
    elif a == "--strict":
      strict = true
    elif a == "--help" or a == "-h":
      printUsage()
      quit(0)
    elif a.startsWith("-"):
      stderr.write "Unknown option: " & a & "\n"
      quit(1)
    else:
      stderr.write "Unexpected argument: " & a & "\n"
      quit(1)
    inc i

  let violations = validateRoot(rootDir, expectedForbidden, strict)

  if violations.len > 0:
    for v in violations:
      echo v
    echo "SUMMARY: " & $violations.len & " violation(s) found"
    quit(1)
  else:
    echo "PASS: filesystem contract validated"
    quit(0)

when isMainModule:
  main()
