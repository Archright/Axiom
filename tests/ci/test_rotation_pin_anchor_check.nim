{.push raises: [CatchableError].}

## test_rotation_pin_anchor_check.nim — rotation preflight checker contract
## tests (golden verdicts + CLI surface).
##
## The in-process equivalence to the landing predicate (checker exit==0 ⇔
## adjudicateRotation(...).check.newAnchorOk) lives in
## tests/cli/test_merge_cli.nim (wired into `make test-unit`); THIS file
## covers the checker's own contract: exit codes 0/1/2, the one-line stdout
## shape, JSONC pin parsing, and the fail-closed input handling (a malformed
## or missing input is a run-level failure, never an H2 verdict).
##
## Fixtures live in an isolated temp dir — the working repository is never
## touched (same policy as test_derive_checker_closure.nim).

import std/[json, os, strutils, unittest]

import ci/rotation_pin_anchor_check
import core/policy/rotation_closure_facts
import core/results

let FixtureDir = getTempDir() / "axiom_vs1_rotation_pin_anchor_check"

const
  LineA = "100644 blob a1\tci/checker.mk"
  LineB = "100644 blob b2\ttools/ci/derive_checker_closure.nim"
  EntryA = (path: "ci/checker.mk", mode: "100644", sha: "a1")
  EntryB = (path: "tools/ci/derive_checker_closure.nim", mode: "100644", sha: "b2")
  EntryBZZ = (path: "tools/ci/derive_checker_closure.nim", mode: "100644", sha: "ZZ")

proc writeFixture(name, content: string): string =
  createDir(FixtureDir)
  result = FixtureDir / name
  writeFile(result, content)

proc pinDocText(entries: seq[tuple[path, mode, sha: string]];
                keyPresent = true; jsonc = false): string =
  ## trusted_writer_set document — optionally without the closure key (the
  ## genesis tree fact) and optionally wrapped in JSONC comments (the real
  ## pin files carry whole-line `//` comments).
  var doc = %*{"schema": 1}
  if keyPresent:
    var obj = newJObject()
    for e in entries:
      obj[e.path] = %*{"mode": e.mode, "type": "blob", "sha": e.sha}
    doc[RotationPinKey] = obj
  var text = $doc
  if jsonc:
    text = "// trusted writer set (JSONC comment)\n" & text & " // trailing inline\n"
  text

suite "rotation_pin_anchor_check — CLI contract (golden verdicts, fail-closed inputs)":
  setup:
    if dirExists(FixtureDir):
      removeDir(FixtureDir)

  test "match → exit 0, exact PASS line":
    let d = writeFixture("derived_H.txt", LineA & "\n" & LineB)
    let ph = writeFixture("pin_H.json", pinDocText(@[EntryA, EntryB]))
    let pb = writeFixture("pin_B.json", pinDocText(@[EntryA, EntryB]))
    let o = evaluatePinAnchorFiles(d, ph, pb)
    check o.exitCode == ExitPass
    check o.line == "H2 PASS code=OK"
    check runCheck(@["--derived-H", d, "--pin-H", ph, "--pin-B", pb]) == ExitPass

  test "one-line diff → exit 1 / ROT_NEW_PIN + shared reason + differing paths":
    let d = writeFixture("derived_H.txt", LineA & "\n" & LineB)
    let ph = writeFixture("pin_H.json", pinDocText(@[EntryA, EntryBZZ]))
    let pb = writeFixture("pin_B.json", pinDocText(@[EntryA, EntryB]))
    let o = evaluatePinAnchorFiles(d, ph, pb)
    check o.exitCode == ExitH2Fail
    check o.line.contains("H2 FAIL code=ROT_NEW_PIN")
    check o.line.contains("reason=pin anchor invalid: line-set(pin@H) != set(derived H)")
    check o.line.contains("missing-from-pin=tools/ci/derive_checker_closure.nim")
    check o.line.contains("pin-only=tools/ci/derive_checker_closure.nim")
    check runCheck(@["--derived-H", d, "--pin-H", ph, "--pin-B", pb]) == ExitH2Fail

  test "pin-H key absent + pin-B key absent → exit 1 / ROT_GENESIS_INVALID":
    let d = writeFixture("derived_H.txt", LineA)
    let ph = writeFixture("pin_H_nokey.json", pinDocText(@[], keyPresent = false))
    let pb = writeFixture("pin_B_nokey.json", pinDocText(@[], keyPresent = false))
    let o = evaluatePinAnchorFiles(d, ph, pb)
    check o.exitCode == ExitH2Fail
    check o.line.contains("H2 FAIL code=ROT_GENESIS_INVALID")
    check o.line.contains("missing-from-pin=ci/checker.mk")
    check runCheck(@["--derived-H", d, "--pin-H", ph, "--pin-B", pb]) == ExitH2Fail

  test "JSONC comments (whole-line + trailing inline) parse":
    let d = writeFixture("derived_H.txt", LineA)
    let ph = writeFixture("pin_H.jsonc", pinDocText(@[EntryA], jsonc = true))
    let pb = writeFixture("pin_B.jsonc", pinDocText(@[EntryA], jsonc = true))
    check evaluatePinAnchorFiles(d, ph, pb).exitCode == ExitPass

  test "malformed derived line → exit 2 (fail-closed, never a verdict)":
    let d = writeFixture("derived_bad.txt", "100644 blob a1 ci/checker.mk")
    let ph = writeFixture("pin_H.json", pinDocText(@[EntryA]))
    let pb = writeFixture("pin_B.json", pinDocText(@[EntryA]))
    let o = evaluatePinAnchorFiles(d, ph, pb)
    check o.exitCode == ExitInputViolation
    check o.line.contains("malformed derived line")
    check runCheck(@["--derived-H", d, "--pin-H", ph, "--pin-B", pb]) == ExitInputViolation

  test "missing pin-H file → exit 2":
    let d = writeFixture("derived_H.txt", LineA)
    let pb = writeFixture("pin_B.json", pinDocText(@[EntryA]))
    check evaluatePinAnchorFiles(d, FixtureDir / "missing.json", pb).exitCode ==
      ExitInputViolation

  test "malformed pin JSON → exit 2":
    let d = writeFixture("derived_H.txt", LineA)
    let ph = writeFixture("pin_H_broken.json", "{\"trustedCheckerTreeClosure\": ")
    let pb = writeFixture("pin_B.json", pinDocText(@[EntryA]))
    check evaluatePinAnchorFiles(d, ph, pb).exitCode == ExitInputViolation

  test "pin entry missing sha → exit 2 (pinClosureLineSet fail-closed)":
    let d = writeFixture("derived_H.txt", LineA)
    let ph = writeFixture("pin_H_partial.json",
      "{\"trustedCheckerTreeClosure\": {\"ci/checker.mk\": " &
      "{\"mode\": \"100644\", \"type\": \"blob\"}}}")
    let pb = writeFixture("pin_B.json", pinDocText(@[EntryA]))
    check evaluatePinAnchorFiles(d, ph, pb).exitCode == ExitInputViolation

  test "arg contract: required flags, unknown option, default pin-B":
    check parseCheckArgs(@[]).isErr
    check parseCheckArgs(@["--derived-H", "d"]).isErr        # --pin-H missing
    check parseCheckArgs(@["--pin-H", "h"]).isErr            # --derived-H missing
    check parseCheckArgs(@["--frobnicate", "x"]).isErr
    check parseCheckArgs(@["--derived-H"]).isErr             # value missing
    let parsed = parseCheckArgs(@["--derived-H", "d", "--pin-H", "h"])
    check parsed.isOk
    check parsed.get.derivedHPath == "d"
    check parsed.get.pinHPath == "h"
    check parsed.get.pinBPath == RotationPinBPath            # cwd-relative default
    let explicit = parseCheckArgs(@["--derived-H", "d", "--pin-H", "h", "--pin-B", "b"])
    check explicit.isOk
    check explicit.get.pinBPath == "b"
    check runCheck(@[]) == ExitInputViolation

  test "omitted --pin-B reads config/trusted_writer_set.json from the cwd":
    let cwd = getCurrentDir()
    try:
      createDir(FixtureDir / "ws" / "config")
      writeFile(FixtureDir / "ws" / "config" / "trusted_writer_set.json",
        pinDocText(@[EntryA]))
      writeFile(FixtureDir / "ws" / "derived_H.txt", LineA)
      writeFile(FixtureDir / "ws" / "pin_H.json", pinDocText(@[EntryA]))
      setCurrentDir(FixtureDir / "ws")
      check runCheck(@["--derived-H", "derived_H.txt", "--pin-H", "pin_H.json"]) ==
        ExitPass
    finally:
      setCurrentDir(cwd)
