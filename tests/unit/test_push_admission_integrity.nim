## DEBT#534/DEBT#535 regression suite — push-admissibility declared-vs-executed
## set equality (tools/ci/push_admission_integrity_gate.nim).
##
## Pins the contract:
##   - the declared set (PUSH_ADMISSIBILITY_GATES, read from make's own
##     database via `make -pn` — never text-parsed) must EQUAL the executed
##     set derived from the recipe's `# @pushGate` invocation markers;
##   - the exact DEBT#534 failure mode (check-merge-admission-cert-mirror
##     declared but never invoked) must FAIL closed and be named;
##   - removing the auditor from the recipe must FAIL (DEBT#535 — the check
##     is wired into the path it audits);
##   - unaccounted sub-makes and marker/sub-make mismatches must FAIL;
##   - `--executed-summary` (the source of the PASS summary line) must emit
##     the executed set only, omitting an unwired gate, and must refuse to
##     emit for a recipe that lost its auditor.

import std/[unittest, os, osproc, strutils, sequtils, times]

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  for i in 0 ..< 20:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  raise newException(IOError, ".axiom_root not found from " & getCurrentDir())

proc buildGateUnderTest(repoRoot, scratchDir: string): string =
  ## Compile the gate from the live working tree so the suite always
  ## exercises the current source (mirrors hermetic_source_hash_gate_test).
  let outBin = scratchDir / "push_admission_integrity_gate_under_test"
  let cmd = "AXIOM_HERMETIC_BUILDING=1 nim c --hints:off --warnings:off " &
    "--nimcache:" & quoteShell(scratchDir / "nimcache_pai") &
    " -o:" & quoteShell(outBin) & " " &
    quoteShell(repoRoot / "tools" / "ci" / "push_admission_integrity_gate.nim")
  let (output, rc) = execCmdEx(cmd, workingDir = repoRoot)
  if rc != 0:
    raise newException(IOError,
      "failed to compile tools/ci/push_admission_integrity_gate.nim (rc=" &
      $rc & "):\n" & output)
  result = outBin

proc declaredSetViaMake(repoRoot: string): string =
  ## PUSH_ADMISSIBILITY_GATES as make itself resolves it (`make -pn`
  ## database print — the SSOT route the pre-push hook also uses).
  let (output, rc) = execCmdEx("make -pn", workingDir = repoRoot)
  if rc != 0:
    raise newException(IOError, "make -pn failed (rc=" & $rc & ")")
  const prefix = "PUSH_ADMISSIBILITY_GATES := "
  for line in output.splitLines():
    if line.startsWith(prefix):
      return line[prefix.len .. ^1].strip()
  raise newException(IOError, "PUSH_ADMISSIBILITY_GATES not found in make -pn")

proc runGate(gate, makefilePath, declared: string; emission = false): tuple[
    output: string, exitCode: int] =
  var cmd = quoteShell(gate)
  if emission:
    cmd = cmd & " --executed-summary"
  else:
    cmd = cmd & " --declared " & quoteShell(declared)
  if makefilePath != "Makefile":
    cmd = cmd & " --makefile " & quoteShell(makefilePath)
  execCmdEx(cmd, workingDir = findRepoRoot())

proc dropLineContaining(makefileText, needle: string): string =
  makefileText.splitLines().filterIt(not it.contains(needle)).join("\n") & "\n"

suite "push-admissibility declared == executed (DEBT#534/535)":
  let repoRoot = findRepoRoot()
  let suiteDir = getTempDir() / ("axiom_pai_" & $getCurrentProcessId() & "_" &
    $epochTime().int)
  createDir(suiteDir)
  let gate = buildGateUnderTest(repoRoot, suiteDir)
  let declaredGates = declaredSetViaMake(repoRoot)
  let realMakefile = repoRoot / "Makefile"

  test "declared set resolves to 9 gates including the mirror gate":
    check declaredGates.splitWhitespace().len == 9
    check "check-merge-admission-cert-mirror" in declaredGates.splitWhitespace()

  test "real Makefile: declared == executed (DEBT#534/535 fix state)":
    let (outText, rc) = runGate(gate, realMakefile, declaredGates)
    check rc == 0
    check outText.contains("PASS: declared == executed (9 = 9)")

  test "--executed-summary emits the executed set incl. mirror gate":
    let (outText, rc) = runGate(gate, realMakefile, "", emission = true)
    check rc == 0
    let names = outText.splitWhitespace()
    check names.len == 9
    check "check-merge-admission-cert-mirror" in names
    check "check-debt" notin names
    # CI-covered gates are not re-executed on the push path (second pruning):
    # repository-surface (SL-20), root-layout and workflow-shell-syntax all
    # judge the real merge candidate on the landing venue itself.
    check "validate-root-layout" notin names
    check "check-repository-surface" notin names
    check "check-workflow-shell-syntax" notin names

  test "DEBT#534 replay: declared gate without recipe invocation FAILs":
    # A staged change that adds a name to the declaration without wiring
    # the invocation must be caught by name.
    let (outText, rc) = runGate(gate, realMakefile,
      declaredGates & " check-cert-integrity")
    check rc == 1
    check outText.contains("DECLARED-BUT-NOT-EXECUTED")
    check outText.contains("check-cert-integrity")

  test "DEBT#534 exact replay: mirror-gate invocation removed FAILs by name":
    let mutated = dropLineContaining(readFile(realMakefile),
      "@$(MAKE) --no-print-directory check-merge-admission-cert-mirror")
    let mutatedPath = suiteDir / "mf_no_mirror.mk"
    writeFile(mutatedPath, mutated)
    defer: removeFile(mutatedPath)
    let (outText, rc) = runGate(gate, mutatedPath, declaredGates)
    check rc == 1
    check outText.contains("DECLARED-BUT-NOT-EXECUTED")
    check outText.contains("check-merge-admission-cert-mirror")

  test "DEBT#534 replay: emission omits the unwired gate (summary truthful)":
    let mutated = dropLineContaining(readFile(realMakefile),
      "@$(MAKE) --no-print-directory check-merge-admission-cert-mirror")
    let mutatedPath = suiteDir / "mf_no_mirror_emit.mk"
    writeFile(mutatedPath, mutated)
    defer: removeFile(mutatedPath)
    let (outText, rc) = runGate(gate, mutatedPath, "", emission = true)
    check rc == 0
    let names = outText.splitWhitespace()
    check names.len == 8
    check "check-merge-admission-cert-mirror" notin names

  test "DEBT#535 regression: auditor removed from recipe FAILs":
    let mutated = dropLineContaining(readFile(realMakefile),
      "@$(MAKE) --no-print-directory check-push-admissibility-integrity")
    let mutatedPath = suiteDir / "mf_no_audit.mk"
    writeFile(mutatedPath, mutated)
    defer: removeFile(mutatedPath)
    let (outText, rc) = runGate(gate, mutatedPath, declaredGates)
    check rc == 1
    check outText.contains("not invoked by the push-admissibility recipe")

  test "DEBT#535 regression: emission refuses an unaudited recipe":
    let mutated = dropLineContaining(readFile(realMakefile),
      "@$(MAKE) --no-print-directory check-push-admissibility-integrity")
    let mutatedPath = suiteDir / "mf_no_audit_emit.mk"
    writeFile(mutatedPath, mutated)
    defer: removeFile(mutatedPath)
    let (outText, rc) = runGate(gate, mutatedPath, "", emission = true)
    check rc == 1
    check outText.contains("not invoked by the push-admissibility recipe")

  test "fixture: minimal recipe with matching declaration passes":
    let fixture = suiteDir / "mf_min_ok.mk"
    writeFile(fixture,
      "push-admissibility:\n" &
      "\t@$(MAKE) --no-print-directory check-push-admissibility-integrity\n" &
      "\t@bin/fake_gate_one  # @pushGate fake-gate-one\n" &
      "\t@$(MAKE) --no-print-directory fake-gate-two  # @pushGate fake-gate-two\n")
    defer: removeFile(fixture)
    let (outText, rc) = runGate(gate, fixture, "fake-gate-one fake-gate-two")
    check rc == 0
    check outText.contains("declared == executed (2 = 2)")
    let (emitText, emitRc) = runGate(gate, fixture, "", emission = true)
    check emitRc == 0
    check emitText.strip() == "fake-gate-one fake-gate-two"

  test "fixture: unaccounted gate sub-make (no marker) FAILs":
    let fixture = suiteDir / "mf_unaccounted.mk"
    writeFile(fixture,
      "push-admissibility:\n" &
      "\t@$(MAKE) --no-print-directory check-push-admissibility-integrity\n" &
      "\t@$(MAKE) --no-print-directory fake-gate-two\n")
    defer: removeFile(fixture)
    let (outText, rc) = runGate(gate, fixture, "fake-gate-two")
    check rc == 1
    check outText.contains("unaccounted sub-make 'fake-gate-two'")

  test "fixture: marker not matching its sub-make target FAILs":
    let fixture = suiteDir / "mf_mismatch.mk"
    writeFile(fixture,
      "push-admissibility:\n" &
      "\t@$(MAKE) --no-print-directory check-push-admissibility-integrity\n" &
      "\t@$(MAKE) --no-print-directory fake-gate-two  # @pushGate fake-gate-one\n")
    defer: removeFile(fixture)
    let (outText, rc) = runGate(gate, fixture, "fake-gate-one")
    check rc == 1
    check outText.contains(
      "marker 'fake-gate-one' does not match its sub-make target 'fake-gate-two'")

  removeDir(suiteDir)
