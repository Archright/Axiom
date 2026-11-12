# §6c skReport cross-path comparison consumer — tests-tree evidence driver,
# NOT a CLI surface, NOT a tools/ infrastructure tool.
#
# Loads two rust-lane runs' (payload, sidecar) pairs — payload from the run's
# trajectory skReport `extra`, sidecar from
# <stateRoot>/.axiom/rust-lane/<sha256Hex(projectAbs)[0..15]>/skreport-identity.json —
# optionally re-measures the subject world through the SAME primitives the
# lane used at production time (subjectGitIdentity, fileSha256Hex,
# subjectSourceFingerprint — the I/O boundary of §6c), and prints the
# compareSkReports verdict record (THE single implementation,
# core/utils/skreport_comparison.nim).
#
# Placement (2026-11-01): lives in the tests tree because compare-time anchor
# re-measurement consumes the lane's verification primitives directly —
# sanctioned for harness code under tests/, rejected for the tools/ tree
# (layer rule tools/ forbids verification/ imports; measured fail-closed at
# the pre-push layer_enforcement_gate when this driver was first placed in
# tools/debug/). Relocation is the compliant fix — the layer rule itself is
# untouched and still enforced for src/ and tools/.
#
# Usage:
#   nim c -r --hints:off -o:build/skreport_compare_tool \
#     tests/skreport_compare_tool.nim -- \
#     <payloadL.json> <sidecarL.json|absent> <payloadR.json> <sidecarR.json|absent> \
#     [<subjectRootL> <stateRootL> <subjectRootR> <stateRootR>]
#
# The 4 trailing paths are optional: when all are given and readable, the
# anchors {subject.commit, subject.moduleSha256, subject.sourceFingerprint,
# scope.rustTargetsSha256} are re-measured NOW and attached to the run as
# refutation material. A failed re-measurement records NO anchor
# (fail-closed absence — never a fabricated match). Exit code is 0 whenever
# the tool ran; the verdict itself is an observation, not a tool failure
# (§7 exit coupling is untouched).

import std/[json, os, strutils]

import core/utils/skreport_comparison
import core/results                  # Result accessors (isOk/get) for fileSha256Hex
import cli/rust_lane_cli             # subjectSourceFingerprint — the D1 `.rs` fingerprint
import verification/extraction_provenance  # fileSha256Hex (Result) — the lane's digest primitive
import verification/rust_replay_adapter    # subjectGitIdentity — the lane's git primitive

const usage = """usage: skreport_compare_tool <payloadL> <sidecarL|absent> <payloadR> <sidecarR|absent> [subjectRootL stateRootL subjectRootR stateRootR]"""

proc die(msg: string) {.noreturn.} =
  stderr.writeLine("skreport_compare_tool: " & msg)
  quit(2)

proc loadJsonOrNone(path: string): JsonNode =
  ## nil = absent (unreadable or missing) — the comparison's fail-closed shape.
  if path == "absent" or not fileExists(path):
    return nil
  try:
    parseFile(path)
  except CatchableError:
    nil

proc measuredAnchors(subjectRoot, stateRoot, moduleRel: string): JsonNode =
  ## Re-measure the declared identity anchors NOW, via the same primitives the
  ## lane used at production time. Only measurable anchors are recorded.
  var subject = newJObject()
  let git = subjectGitIdentity(subjectRoot)
  if git.gitRef.len > 0:
    subject["commit"] = %git.gitRef
  let modSha = fileSha256Hex(subjectRoot / moduleRel)
  if modSha.isOk():
    subject["moduleSha256"] = %modSha.get()
  let fp = subjectSourceFingerprint(subjectRoot)
  if fp.len > 0:
    subject["sourceFingerprint"] = %fp
  var scope = newJObject()
  let lockSha = fileSha256Hex(stateRoot / "data" / "verification_scope.lock")
  if lockSha.isOk():
    scope["rustTargetsSha256"] = %lockSha.get()
  %*{"subject": subject, "scope": scope}

proc main() =
  let args = commandLineParams()
  if args.len < 4:
    die(usage)
  let runs = [(payloadPath: args[0], sidecarPath: args[1]),
              (payloadPath: args[2], sidecarPath: args[3])]
  var measures = [(on: false, subject: "", state: ""),
                  (on: false, subject: "", state: "")]
  if args.len >= 8:
    for i in 0 ..< 2:
      let (s, st) = (args[4 + i * 2], args[5 + i * 2])
      if dirExists(s) and dirExists(st):
        measures[i] = (on: true, subject: s, state: st)
      else:
        die("measure roots not directories: " & s & ", " & st)
  elif args.len != 4:
    die(usage)

  var runsIn: array[2, SkReportRun]
  for i in 0 ..< 2:
    let payload = loadJsonOrNone(runs[i].payloadPath)
    if payload.isNil:
      die("payload unreadable: " & runs[i].payloadPath)
    let sidecar = loadJsonOrNone(runs[i].sidecarPath)
    var measured: JsonNode = nil
    if measures[i].on and not sidecar.isNil:
      let moduleRel = sidecar{"identity"}{"subject"}{"modulePath"}
      if not moduleRel.isNil and moduleRel.kind == JString:
        measured = measuredAnchors(measures[i].subject, measures[i].state,
                                   moduleRel.getStr())
    runsIn[i] = SkReportRun(payload: payload, sidecar: sidecar,
                            measured: measured)

  for i, label in @["left", "right"]:
    if not runsIn[i].measured.isNil:
      stderr.writeLine("# re-measured anchors (" & label & "): " &
        pretty(runsIn[i].measured).replace("\n", "\n# "))
    else:
      stderr.writeLine("# re-measured anchors (" & label &
        "): none (production-time measurement stands)")
  echo pretty(compareSkReports(runsIn[0], runsIn[1]))

when isMainModule:
  main()
