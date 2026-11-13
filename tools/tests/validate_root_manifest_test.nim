## validate_root_manifest_test.nim — Tests for validate_root_manifest CLI.
##
## Runs the compiled validator binary against temporary directory structures
## and asserts expected exit codes and output patterns.
##
## Usage: nim c -r tools/tests/validate_root_manifest_test.nim

import std/[os, osproc, strutils, random]

let
  projectRoot = getEnv("AXIOM_PROJECT_ROOT", getAppDir().parentDir())
  validatorBin = projectRoot / "bin" / "validate_root_manifest"

var tempDirCounter = 0

proc createTempDir(): string =
  ## Create a unique temporary directory and return its path.
  tempDirCounter.inc
  result = getTempDir() / "axiom_validate_root_" & $tempDirCounter & "_" & $(rand(99999))
  createDir(result)

proc runValidator(rootDir: string, extraArgs: seq[string] = @[]): tuple[exitCode: int; output: string] =
  ## Run the validator against rootDir with optional extra arguments.
  var cmd = validatorBin
  for a in extraArgs:
    cmd &= " " & a
  cmd &= " --root " & rootDir
  let r = execCmdEx(cmd, options = {poStdErrToStdOut})
  result.exitCode = r.exitCode
  result.output = r.output

proc runValidatorExpectedForbidden(rootDir: string, forbiddenList: seq[string]): tuple[exitCode: int; output: string] =
  ## Run the validator with --expected-forbidden for each entry.
  var args: seq[string] = @[]
  for f in forbiddenList:
    args.add "--expected-forbidden"
    args.add f
  result = runValidator(rootDir, args)

proc main() =
  var failures = 0

  # Test 1: Required dirs only → exit 0
  block cleanRoot:
    echo "TEST 1: REQUIRED dirs only → exit 0"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    let r = runValidator(tmpDir)
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 2: Unknown directory → exit 1
  block unknownDir:
    echo "TEST 2: Unknown dir (mystery/) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "mystery")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      inc failures
    elif "FAIL: mystery unknown" notin r.output:
      echo "  FAIL: expected 'FAIL: mystery unknown' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 3: Forbidden directory → exit 1
  block forbiddenDir:
    echo "TEST 3: Forbidden dir (cli/) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "cli")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      inc failures
    elif "FAIL: cli forbidden" notin r.output:
      echo "  FAIL: expected 'FAIL: cli forbidden' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 4: REQUIRED missing (src/ removed) → exit 1
  block missingRequired:
    echo "TEST 4: REQUIRED missing (src/ removed) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      inc failures
    elif "FAIL: src required missing" notin r.output:
      echo "  FAIL: expected 'FAIL: src required missing' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 5: OPTIONAL (bin/) absent → exit 0
  block optionalAbsent:
    echo "TEST 5: OPTIONAL bin/ absent → exit 0"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    let r = runValidator(tmpDir)
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      inc failures
    else:
      echo "  PASS"

  # Test 6: bin/ present with canonical surface → exit 0
  block binCanonical:
    echo "TEST 6: bin/ with canonical surface (ax) → exit 0"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "bin")
    writeFile(tmpDir / "bin" / "ax", "")
    let r = runValidator(tmpDir)
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 7: bin/ with shebang script → exit 1
  block binShebang:
    echo "TEST 7: bin/ with shebang script → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "bin")
    writeFile(tmpDir / "bin" / "evil_script.sh", "#!/bin/sh\necho hello\n")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      inc failures
    elif "shebang script" notin r.output:
      echo "  FAIL: expected 'shebang script' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 8: --expected-forbidden cli with cli/ present → exit 0
  block expectedForbidden:
    echo "TEST 8: --expected-forbidden cli with cli/ present → exit 0"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "cli")
    let r = runValidator(tmpDir, @["--expected-forbidden", "cli"])
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 9a: .env.local (pattern allow) → exit 0
  block envLocal:
    echo "TEST 9a: .env.local (pattern allowed) → exit 0"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    writeFile(tmpDir / ".env.local", "KEY=VALUE\n")
    let r = runValidator(tmpDir)
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 9b: .env.secret (forbidden pattern) → exit 1
  block envSecret:
    echo "TEST 9b: .env.secret (forbidden pattern) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    writeFile(tmpDir / ".env.secret", "KEY=VALUE\n")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      inc failures
    elif "FAIL: .env.secret forbidden" notin r.output:
      echo "  FAIL: expected 'FAIL: .env.secret forbidden' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 10: --strict combined with --expected-forbidden → ALL forbidden FAIL
  block strictOverridesExpected:
    echo "TEST 10: --strict + --expected-forbidden cli (cli/ present) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "cli")
    let r = runValidator(tmpDir, @["--strict", "--expected-forbidden", "cli"])
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "FAIL: cli forbidden" notin r.output:
      echo "  FAIL: expected 'FAIL: cli forbidden' in output despite --expected-forbidden"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 11: deleted build cache dir regenerated (nimcache/) → exit 1
  block forbiddenCache:
    echo "TEST 11: regenerated cache dir (nimcache/) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "nimcache")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "FAIL: nimcache forbidden" notin r.output:
      echo "  FAIL: expected 'FAIL: nimcache forbidden' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 12: bin/ with unclassified non-ELF materialization → exit 1
  block:
    echo "TEST 12: bin/ plain text file → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "bin")
    writeFile(tmpDir / "bin" / "notes.txt", "just text\n")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "unclassified materialization" notin r.output:
      echo "  FAIL: expected 'unclassified materialization' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 13: proof_universe.lock in root → exit 1
  block proofUniverseLock:
    echo "TEST 13: proof_universe.lock in root → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    writeFile(tmpDir / "proof_universe.lock", "locked\n")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "proof_universe.lock forbidden" notin r.output:
      echo "  FAIL: expected 'proof_universe.lock forbidden' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 14: logs/ with git-tracked file → exit 1
  block logsTracked:
    echo "TEST 14: logs/ with git-tracked file → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "logs" / "audit")
    writeFile(tmpDir / "logs" / "audit" / "tier_classification.json", "{}")
    # Initialize as git repo and commit the file so it becomes tracked
    discard execCmdEx("git init " & quoteShell(tmpDir))
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " config user.email \"test@test.com\"")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " config user.name \"Test\"")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " add logs/audit/tier_classification.json")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " commit -m \"add log\"")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "git-tracked" notin r.output:
      echo "  FAIL: expected 'git-tracked' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 15: vendor/ed25519/.git exists → exit 1
  block vendorGitDir:
    echo "TEST 15: vendor/ed25519/.git exists → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "vendor" / "ed25519" / ".git")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "vendor/ed25519/.git" notin r.output:
      echo "  FAIL: expected vendor/ed25519/.git error in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 16: logs/ all untracked + .gitignore → exit 0
  block logsUntracked:
    echo "TEST 16: logs/ untracked + .gitignore → exit 0"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "logs" / "audit")
    writeFile(tmpDir / "logs" / "audit" / "tier_classification.json", "{}")
    # Initialize as git repo but do NOT commit — file is untracked
    discard execCmdEx("git init " & quoteShell(tmpDir))
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " config user.email \"test@test.com\"")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " config user.name \"Test\"")
    # Add logs/* to .gitignore so it stays untracked and ignored
    writeFile(tmpDir / ".gitignore", "logs/*\n")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " add .gitignore")
    discard execCmdEx("git -C " & quoteShell(tmpDir) & " commit -m \"init\"")
    let r = runValidator(tmpDir)
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 17: logs/ present, root NOT a git repo → exit 1 (tracked-status UNKNOWN, fail-closed)
  block logsNoGitFailClosed:
    echo "TEST 17: logs/ present, no git repo → exit 1 (UNKNOWN, fail-closed)"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "logs" / "audit")
    writeFile(tmpDir / "logs" / "audit" / "tier_classification.json", "{}")
    # deliberately NOT git-init'd: git ls-files must fail → UNKNOWN → FAIL
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "UNKNOWN" notin r.output:
      echo "  FAIL: expected 'UNKNOWN' in output (fail-closed tracked-status)"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 18: root-level forbidden file (debug_real.nims) → exit 1
  block forbiddenRootFile:
    echo "TEST 18: root file-level Forbidden (debug_real.nims) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    writeFile(tmpDir / "debug_real.nims", "switch(\"debugger\")\n")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "FAIL: debug_real.nims forbidden" notin r.output:
      echo "  FAIL: expected 'FAIL: debug_real.nims forbidden' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 19: bin/axiom.nim (LegacyBinExceptions) → exit 0
  block binLegacyException:
    echo "TEST 19: bin/axiom.nim present (legacy exception) → exit 0"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "bin")
    writeFile(tmpDir / "bin" / "axiom.nim", "import gate/static_gate_scanner\n")
    let r = runValidator(tmpDir)
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 20: ci/ + experiments/ + _lto_evidence/ (tracked content dirs) → exit 0
  block trackedContentDirs:
    echo "TEST 20: ci/experiments/_lto_evidence present → exit 0"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    for d in ["ci", "experiments", "_lto_evidence"]:
      createDir(tmpDir / d)
      writeFile(tmpDir / d / "entry.nim", "# tracked content\n")
    let r = runValidator(tmpDir)
    if r.exitCode != 0:
      echo "  FAIL: expected exit 0, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 21: new unclassified directory → exit 1 (T2 pattern extension)
  block unclassifiedDir:
    echo "TEST 21: unclassified dir (new_untracked_zone/) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    createDir(tmpDir / "new_untracked_zone")
    let r = runValidator(tmpDir)
    if r.exitCode != 1:
      echo "  FAIL: expected exit 1, got " & $r.exitCode
      echo "  output: " & r.output
      inc failures
    elif "FAIL: new_untracked_zone unknown" notin r.output:
      echo "  FAIL: expected 'FAIL: new_untracked_zone unknown' in output"
      echo "  output: " & r.output
      inc failures
    else:
      echo "  PASS"

  # Test 22: removed dead root entries → exit 1 (lfs_exceptions.json unknown; .env* pattern forbidden)
  block deadRootEntriesRejected:
    echo "TEST 22: dead root entries (lfs_exceptions.json/.env.example/.envrc.example) → exit 1"
    let tmpDir = createTempDir()
    defer: removeDir(tmpDir)
    for d in ["src", "tests", "tools", "proofs", "data", "docs", "config"]:
      createDir(tmpDir / d)
    for (deadName, deadContent, expectedMsg) in [
      ("lfs_exceptions.json", "{}\n", "FAIL: lfs_exceptions.json unknown"),
      (".env.example", "KEY=VALUE\n", "FAIL: .env.example forbidden"),
      (".envrc.example", "KEY=VALUE\n", "FAIL: .envrc.example forbidden"),
    ]:
      writeFile(tmpDir / deadName, deadContent)
      let r = runValidator(tmpDir)
      if r.exitCode != 1:
        echo "  FAIL: expected exit 1 for " & deadName & ", got " & $r.exitCode
        echo "  output: " & r.output
        inc failures
      elif expectedMsg notin r.output:
        echo "  FAIL: expected '" & expectedMsg & "' in output for " & deadName
        echo "  output: " & r.output
        inc failures
      else:
        echo "  PASS: " & deadName
      removeFile(tmpDir / deadName)

  echo ""
  if failures > 0:
    echo $failures & " test(s) FAILED"
    quit(1)
  else:
    echo "All validate_root_manifest tests passed."

when isMainModule:
  main()
