## tests/cli/test_panics_exit_contract.nim
##
## R5 exit-state contract probe (issue #346): unrecoverable runtime
## termination under `--panics:on`. `config.nims:49` sets
## `switch("panics", "on")` for release/danger builds, and
## docs/spec/productization_contract.md ("Panic abort under `--panics:on`")
## classifies the resulting abort as an out-of-contract termination that is
## NEVER a verification claim.
##
## This probe MEASURES the matrix instead of restating it: the same program is
## compiled twice (`--panics:on` / `--panics:off`) and run, and the observed
## exit codes are compared with the contract's machine-read anchor and with the
## fixed 0..4 table.
##
## Non-vacuity — every assertion below can fail:
##   * the abort arm must stay an abort: `before-defect` is the last thing
##     produced, `caught-defect` / `after-defect` never appear and the
##     `canonical-claim` marker line is unreachable, so execution cannot reach
##     any reporting path that could emit a canonical verdict;
##   * the abort must never take a designed state's code other than the
##     documented numeric collision with `1`: `0` (success), `2`
##     (INTERNAL_ERROR), `3` (INVALID_INPUT) and `4` (NOT_CURRENT) are
##     rejected — a panic-to-exit shim changes the code and fails here;
##   * the control arm must actually recover (`--panics:off` -> the handler
##     runs, exit `0`), otherwise the matrix is not measuring the switch;
##   * the fixed table is re-read from the contract, so renumbering `0..4`
##     (which would "resolve" the collision by moving the meanings) fails here.
##
## Run:
##   make test-panics-exit-contract
##   nim c -r --skipParentCfg --skipProjCfg --skipUserCfg --noNimblePath \
##     tests/cli/test_panics_exit_contract.nim

import std/[os, osproc, sequtils, strutils, unittest]

const
  contractRel = "docs/spec/productization_contract.md"
  configNimsRel = "config.nims"

  probeSource = """
proc main() =
  echo "before-defect"
  flushFile(stdout)
  try:
    var x = 0
    echo "div=" & $(1 div x)
  except Defect:
    echo "caught-defect"
    flushFile(stdout)
  echo "after-defect"
  echo "canonical-claim=verification-failure"
  flushFile(stdout)

main()
"""

type
  Arm = object
    exitCode: int
    output: string

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while true:
    if fileExists(dir / ".axiom_root"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  raise newException(IOError, ".axiom_root not found from " & getCurrentDir())

proc anchorValue(contract, key: string): int =
  ## Read `key=<int>` out of the contract clause. A missing anchor is an error,
  ## never a silent default: the doc is the SSOT this probe compares against.
  let at = contract.find(key & "=")
  if at < 0:
    raise newException(IOError, "contract is missing the machine-read anchor '" &
                       key & "='")
  var i = at + key.len + 1
  var digits = ""
  while i < contract.len and contract[i] in {'0'..'9'}:
    digits.add(contract[i])
    inc i
  if digits.len == 0:
    raise newException(IOError, "anchor '" & key & "=' carries no integer value")
  result = parseInt(digits)

proc buildArm(toolchain, scratchDir, switchValue: string): Arm =
  ## Compile the probe with `--panics:<switchValue>` (outside the project
  ## config, so the only variable is the switch) and run it.
  let src = scratchDir / "probe_defect.nim"
  writeFile(src, probeSource)
  let binPath = scratchDir / ("probe_defect_" & switchValue)
  let nimcache = scratchDir / ("nimcache_" & switchValue)
  let compileCmd = quoteShell(toolchain) &
    " c --hints:off --warnings:off --skipUserCfg --skipParentCfg" &
    " --nimcache:" & quoteShell(nimcache) &
    " --panics:" & switchValue &
    " -o:" & quoteShell(binPath) & " " & quoteShell(src)
  let (compileOut, compileRc) = execCmdEx(compileCmd, workingDir = scratchDir)
  if compileRc != 0:
    raise newException(IOError,
      "probe compile with --panics:" & switchValue & " failed (rc=" &
      $compileRc & "):\n" & compileOut)
  let (runOut, runRc) = execCmdEx(quoteShell(binPath), workingDir = scratchDir)
  Arm(exitCode: runRc, output: runOut)

proc recovered(a: Arm): bool = a.output.contains("caught-defect")

let
  repoRoot = findRepoRoot()
  contractText = readFile(repoRoot / contractRel)
  toolchain = findExe("nim")

if toolchain.len == 0:
  raise newException(IOError,
    "nim not found on PATH — the panics on/off matrix cannot be measured")

let scratchDir = getTempDir() / ("axiom_panics_exit_contract_" &
                                 $getCurrentProcessId())
if dirExists(scratchDir):
  removeDir(scratchDir)
createDir(scratchDir)

let
  onArm = buildArm(toolchain, scratchDir, "on")
  offArm = buildArm(toolchain, scratchDir, "off")

echo "panics matrix measured: --panics:on exit=", onArm.exitCode,
     " recovered=", onArm.recovered,
     " | --panics:off exit=", offArm.exitCode,
     " recovered=", offArm.recovered

suite "panics exit contract — measured matrix":

  test "--panics:on: a Defect aborts at the defect, exit code = contract anchor":
    check onArm.output.contains("before-defect")
    check onArm.output.contains("DivByZeroDefect")
    check onArm.output.contains("caught-defect") == false
    check onArm.output.contains("after-defect") == false
    check onArm.exitCode == anchorValue(contractText, "panicAbortExit")

  test "--panics:off: the same program recovers in `except Defect` (control arm)":
    check offArm.output.contains("before-defect")
    check offArm.output.contains("caught-defect")
    check offArm.output.contains("after-defect")
    check offArm.exitCode == anchorValue(contractText, "panicRecoveredExit")

  test "the abort never takes a designed state's exit code (a shim fails here)":
    # `1` is the documented numeric collision with verification-failure. What
    # the contract forbids is the abort BECOMING a designed state — success
    # (0) or a designed non-verification state (2/3/4) — i.e. a panic-to-exit
    # shim, which would report a crash as a contract state.
    check onArm.exitCode notin [0, 2, 3, 4]
    # ... and it is not a verification claim: execution cannot reach the
    # reporting path (the line that would claim a verdict), so no runOutcome
    # can be projected from it.
    check onArm.output.contains("after-defect") == false
    check onArm.output.contains("canonical-claim") == false

  test "the on/off arms are different observations of the same program":
    check onArm.exitCode != offArm.exitCode
    check onArm.recovered != offArm.recovered
    # the abort arm's only marker is the pre-defect one, so it cannot be
    # confused with a recovery or with a verdict claim.
    check onArm.output.count("before-defect") == 1

suite "panics exit contract — contract text (SSOT)":

  test "the panic clause is present and states the classification":
    check contractText.contains("Panic abort under `--panics:on`")
    check contractText.toLowerAscii.contains("never a verification claim")
    check contractText.contains("config.nims:49")
    check contractText.contains("src/cli/main.nim:112")

  test "the fixed 0..4 mapping is unchanged (no renumbering)":
    let lines = contractText.splitLines()
    const fixedRows = [
      ("0", "VERIFIED"),
      ("1", "VERIFICATION_FAILED"),
      ("2", "INTERNAL_ERROR"),
      ("3", "INVALID_INPUT"),
      ("4", "NOT_CURRENT")]
    for (code, state) in fixedRows:
      let row = "| `" & code & "` |"
      check lines.anyIt(it.startsWith(row) and it.contains(state))

  test "the fixed table carries the panic abort as out-of-contract":
    check contractText.contains("| panic abort (observed `1`) | out-of-contract termination")

suite "panics exit contract — config.nims wiring":

  test "`switch(\"panics\", \"on\")` still sits inside the release/danger GCC branch":
    let lines = readFile(repoRoot / configNimsRel).splitLines()
    let whenIdx = lines.find(
      "when (defined(release) or defined(danger)) and defined(gcc):")
    var panicsIdx = -1
    for i, line in lines:
      if line.strip == "switch(\"panics\", \"on\")":
        panicsIdx = i
        break
    check whenIdx >= 0
    check panicsIdx > whenIdx
    if whenIdx >= 0 and panicsIdx > whenIdx:
      for i in whenIdx + 1 .. panicsIdx:
        check lines[i].len == 0 or lines[i][0] in {' ', '#'}

removeDir(scratchDir)