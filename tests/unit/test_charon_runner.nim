import std/[os, strutils]
import verification/charon_runner
import verification/extraction_provenance

## Pinned Charon execution runner tests (feat/rust-lane-live-cli).
##
## Coverage:
##   CR1  pure version-line parse + pin gate: exact match, semver mismatch,
##        commit mismatch, garbage (all fail-closed, reasons name measured
##        vs pinned identity)
##   CR2  no-binary fail-closed: crNotFound from probe AND from the runner,
##        and the gate precedes any workDir creation
##   CR3  pin-gate dominance: a fake charon that reports a wrong version
##        never reaches `cargo` (marker-file proof — cargo would poison the
##        marker if the gate were bypassed)
##   CR4  live, env-gated (AXIOM_CHARON_BIN → the pinned charon binary,
##        expected /tmp/charon-probe/charon/target/release/charon):
##        probe returns the exact pinned line; runPinnedCharonCargo on a
##        temp copy of /tmp/axiom-rust-probe produces the LLBC (JSON, subject
##        tree untouched); a Cargo.toml-less subject fails closed
##        (crRunFailed). Binary or probe crate absent → explicit SKIP.

var failures = 0

proc expect(cond: bool; msg: string) =
  if not cond:
    inc failures
    echo "  FAIL: " & msg

proc checkEqStr(name: string; got, exp: string) =
  if got == exp:
    echo "  [PASS] " & name
  else:
    inc failures
    echo "  FAIL: " & name & "\n      got: " & got & "\n      exp: " & exp

proc tempBase(name: string): string =
  joinPath(getTempDir(), name)

proc freshDir(name: string): string =
  let dir = tempBase(name)
  if dirExists(dir):
    removeDir(dir)
  createDir(dir)
  dir

# ---------------------------------------------------------------------------
# CR1 — pure parse + pin gate
# ---------------------------------------------------------------------------
echo "=== CR1: version-line parse + pin gate (pure) ==="

const PinLine = "0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)"

block:
  checkEqStr("CR1 pinned identity renders the exact measured form",
    pinnedCharonIdentity(), PinLine)
  let parsed = parseCharonVersionLine(PinLine)
  expect(parsed.ok, "CR1 the pinned line parses")
  checkEqStr("CR1 parsed version", parsed.version, PinnedCharonVersion)
  checkEqStr("CR1 parsed commit", parsed.commit, PinnedCharonPinCommit)
  let verdict = charonPinVerdict(PinLine)
  expect(verdict.ok and verdict.reason.len == 0,
    "CR1 the pinned line passes the pin gate verbatim")

block:
  # semver component mismatch (commit still pinned)
  let semverLine = "9.9.999 (" & PinnedCharonPinCommit & ")"
  let verdict = charonPinVerdict(semverLine)
  expect(not verdict.ok, "CR1 semver mismatch fails the gate")
  expect(verdict.reason.contains("9.9.999"), "CR1 semver reason names the measured version")
  expect(verdict.reason.contains(PinnedCharonVersion), "CR1 semver reason names the pinned version")
  expect(verdict.reason.contains(PinnedCharonPinCommit), "CR1 semver reason carries the pinned identity")

block:
  # commit mismatch (version still pinned)
  let otherHex = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  expect(otherHex != PinnedCharonPinCommit, "CR1 fixture sanity: other hex differs from pin")
  let commitLine = PinnedCharonVersion & " (" & otherHex & ")"
  let verdict = charonPinVerdict(commitLine)
  expect(not verdict.ok, "CR1 commit mismatch fails the gate")
  expect(verdict.reason.contains(otherHex), "CR1 commit reason names the measured commit")
  expect(verdict.reason.contains(PinnedCharonPinCommit), "CR1 commit reason names the pinned commit")

block:
  # (a) structurally NOT `<semver> (<40-hex>)` — parse rejects AND the gate
  # fails closed with the pinned identity in the reason
  for garbage in ["", "charon", "0.1.281", "0.1.281 (nothex)",
                  "0.1.281(" & PinnedCharonPinCommit & ")",
                  "version 0.1.281 (" & PinnedCharonPinCommit & ")",
                  "0.1.281 (" & PinnedCharonPinCommit & ") trailing",
                  "0 . 1 . 281 (" & PinnedCharonPinCommit & ")",
                  "0.1.281 (" & PinnedCharonPinCommit,
                  PinLine & "\nextra line"]:
    expect(not parseCharonVersionLine(garbage).ok,
      "CR1 garbage does not parse: '" & garbage.replace('\n', '|') & "'")
    let verdict = charonPinVerdict(garbage)
    expect(not verdict.ok, "CR1 garbage fails the gate: '" & garbage.replace('\n', '|') & "'")
    expect(verdict.reason.contains(pinnedCharonIdentity()),
      "CR1 garbage reason carries the pinned identity")

block:
  # (b) structurally parseable but NOT the pinned identity — the two-layer
  # design: the parse is a shape check, the GATE is the identity check
  let twoComp = "0.1 (" & PinnedCharonPinCommit & ")"
  let parsed = parseCharonVersionLine(twoComp)
  expect(parsed.ok, "CR1 a two-component semver is structurally parseable")
  let verdict = charonPinVerdict(twoComp)
  expect(not verdict.ok, "CR1 a parseable non-pinned version still fails the gate")
  expect(verdict.reason.contains("'0.1'"), "CR1 the gate reason names the measured version")

# ---------------------------------------------------------------------------
# CR2 — no-binary fail-closed (no live charon required)
# ---------------------------------------------------------------------------
echo "=== CR2: absent binary fails closed ==="

block:
  let absent = joinPath(getTempDir(), "axiom-charon-absent-bin")
  let probe = probeCharonVersion(absent)
  expect(not probe.ok, "CR2 probe fails on an absent binary")
  expect(probe.versionLine.len == 0, "CR2 absent probe records no version line")
  expect(probe.reason.contains("not found"), "CR2 absent probe reason names not-found")
  expect(probe.reason.contains(absent), "CR2 absent probe reason names the exe")

  let subject = freshDir("axiom_charon_runner_cr2_subject")
  let workDir = tempBase("axiom_charon_runner_cr2_wd")
  if dirExists(workDir):
    removeDir(workDir)
  let res = runPinnedCharonCargo(subject, workDir, absent)
  expect(not res.ok, "CR2 runner fails on an absent binary")
  expect(res.error == crNotFound, "CR2 runner error is crNotFound")
  expect(res.llbcPath.len == 0, "CR2 no llbcPath on gate failure")
  expect(not dirExists(workDir), "CR2 the gate precedes workDir creation")

block:
  # caller misuse — crInternal, no subprocess spawned
  let subject = freshDir("axiom_charon_runner_cr2_misuse")
  writeFile(subject / "not_a_dir_marker", "x")
  let resFile = runPinnedCharonCargo(subject / "not_a_dir_marker",
                                     tempBase("axiom_charon_runner_cr2_misuse_wd"))
  expect(resFile.error == crInternal and not resFile.ok,
    "CR2 a file as subject root is crInternal")
  let resEmpty = runPinnedCharonCargo("", tempBase("axiom_charon_runner_cr2_empty_wd"))
  expect(resEmpty.error == crInternal and not resEmpty.ok,
    "CR2 an empty subject root is crInternal")
  let resNoWd = runPinnedCharonCargo(subject, "")
  expect(resNoWd.error == crInternal and not resNoWd.ok,
    "CR2 an empty workDir is crInternal")

# ---------------------------------------------------------------------------
# CR3 — pin-gate dominance: a mismatching charon NEVER reaches cargo
# ---------------------------------------------------------------------------
echo "=== CR3: pin mismatch never runs cargo (fake-exe marker proof) ==="

block:
  let base = freshDir("axiom_charon_runner_cr3")
  let marker = base / "cargo_marker"
  let fakePath = base / "fake-charon"
  let fakeScript = "#!/bin/sh\n" &
    "if [ \"$1\" = \"version\" ]; then\n" &
    "  echo '9.9.999 (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)'\n" &
    "  exit 0\n" &
    "fi\n" &
    "echo \"$1\" >> \"" & marker & "\"\n" &
    "exit 0\n"
  writeFile(fakePath, fakeScript)
  setFilePermissions(fakePath, {fpUserRead, fpUserWrite, fpUserExec,
                                fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})
  let subject = freshDir("axiom_charon_runner_cr3_subject")
  let workDir = tempBase("axiom_charon_runner_cr3_wd")
  if dirExists(workDir):
    removeDir(workDir)
  let res = runPinnedCharonCargo(subject, workDir, fakePath)
  expect(not res.ok, "CR3 mismatching charon is not ok")
  expect(res.error == crPinMismatch, "CR3 mismatching charon is crPinMismatch")
  expect(res.reason.contains("9.9.999"), "CR3 reason names the measured version")
  expect(res.reason.contains(pinnedCharonIdentity()), "CR3 reason names the pinned identity")
  expect(res.llbcPath.len == 0, "CR3 no llbcPath on gate failure")
  expect(not fileExists(marker), "CR3 cargo never ran (marker absent)")
  expect(not dirExists(workDir), "CR3 the gate precedes any workDir write")

# ---------------------------------------------------------------------------
# CR4 — live tests (env-gated: AXIOM_CHARON_BIN)
# ---------------------------------------------------------------------------
echo "=== CR4: live pinned binary (env-gated) ==="

const
  DefaultProbeBin = "/tmp/charon-probe/charon/target/release/charon"
  ProbeCrate = "/tmp/axiom-rust-probe"

let liveBin = getEnv("AXIOM_CHARON_BIN", "")
if liveBin.len == 0 or not fileExists(liveBin):
  echo "  SKIP: live charon tests (set AXIOM_CHARON_BIN to the pinned charon binary, expected " &
    DefaultProbeBin & ")"
else:
  block:
    let probe = probeCharonVersion(liveBin)
    expect(probe.ok and probe.reason.len == 0, "CR4 live probe passes the pin gate")
    checkEqStr("CR4 live probe measures the exact pinned line",
      probe.versionLine, pinnedCharonIdentity())

  if dirExists(ProbeCrate):
    block:
      let subject = tempBase("axiom_charon_runner_cr4_subject")
      let workDir = tempBase("axiom_charon_runner_cr4_wd")
      if dirExists(subject):
        removeDir(subject)
      if dirExists(workDir):
        removeDir(workDir)
      copyDir(ProbeCrate, subject)
      if dirExists(subject / "target"):
        removeDir(subject / "target")
      let res = runPinnedCharonCargo(subject, workDir, liveBin)
      if not res.ok:
        inc failures
        echo "  FAIL: CR4 live extraction failed: " & res.reason
      else:
        echo "  [PASS] CR4 live extraction ok: " & res.llbcPath
        expect(fileExists(res.llbcPath), "CR4 the produced LLBC exists")
        expect(res.llbcPath.isAbsolute, "CR4 llbcPath is absolute")
        expect(res.llbcPath.startsWith(workDir), "CR4 the LLBC lands in workDir")
        checkEqStr("CR4 the recorded version line is the pinned identity",
          res.versionLine, pinnedCharonIdentity())
        var head = ""
        try:
          let text = readFile(res.llbcPath)
          if text.len > 0:
            head = $text[0]
        except CatchableError:
          discard # axiom:best-effort(read-failure falls through to the explicit checkEqStr mismatch below — never silently passes)
        checkEqStr("CR4 the LLBC starts with '{' (JSON)", head, "{")
        expect(not dirExists(subject / "target"),
          "CR4 the subject tree stays clean (cargo build tree redirected)")
      if dirExists(subject):
        removeDir(subject)

    block:
      # fail-closed run: a subject without Cargo.toml cannot extract
      let subject = freshDir("axiom_charon_runner_cr4_nocargo")
      let workDir = tempBase("axiom_charon_runner_cr4_nocargo_wd")
      if dirExists(workDir):
        removeDir(workDir)
      let res = runPinnedCharonCargo(subject, workDir, liveBin)
      expect(not res.ok, "CR4 a Cargo.toml-less subject fails closed")
      expect(res.error == crRunFailed, "CR4 a Cargo.toml-less subject is crRunFailed")
      expect(res.reason.contains("charon cargo failed"), "CR4 the run-failure reason names the stage")
      expect(res.llbcPath.len == 0, "CR4 no llbcPath on run failure")
  else:
    echo "  SKIP: live extraction test (probe crate absent: " & ProbeCrate & ")"

# ---------------------------------------------------------------------------
echo ""
if failures == 0:
  echo "✅ test_charon_runner PASSED"
else:
  echo "❌ test_charon_runner FAILED — " & $failures & " failure(s)"
  quit(1)
