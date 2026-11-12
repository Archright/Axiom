## Journal framing lock tests (bugfix: legacy `|`-delimited framing corrupts
## records whose payload/observedAt/toolchainContext contain an embedded `|`).
##
## Canonical persistence is JSONL (one JSON object per line). Legacy lines are
## still parsed on read for backward compatibility. Verifies:
##  - JSONL round-trip preserves embedded `|` and embedded newlines
##  - digest stability across JSON / legacy representations (identity excludes
##    snapshotId + observedAt)
##  - legacy `|` records are still parseable (backward compatibility)
##  - rebuildIndex keys by the deterministic digest

import std/[unittest, options, tables, strutils, os]
import core/types/debt_types
import core/debt/debt_observation

proc mkObs(modified: bool = false): DebtObservation =
  DebtObservation(
    kind: okMetric,
    subject: "src/core/metrics.nim",
    semanticIdentity: "measureEffectViolations",
    snapshotId: if modified: "snap-2" else: "snap-1",
    source: "topology_scanner",
    payload: "effect_violations | baseline=80 | actual=2090",
    observedAt: if modified: "2026-09-01T00:00:00Z" else: "2026-08-15T00:00:00Z",
    toolchainContext: "nim-2.2.10 | lean-4.29.0"
  )

suite "JSONL framing safety":
  test "round-trip preserves embedded pipe and newline bytes":
    var obs = mkObs()
    obs.payload = "a|b|c\nd\n  e"
    let line = observationRecord(obs)
    let parsed = parseObservationLine(line)
    check parsed.isSome
    let p = parsed.get()
    check p.payload == "a|b|c\nd\n  e"
    check p.subject == obs.subject
    check p.kind == okMetric
    # no raw newline inside the serialized line (true JSONL)
    check not line.contains("\n")

  test "digest identity is stable across JSON and legacy forms":
    let obs = mkObs()
    let ja = parseObservationLine(observationRecord(obs)).get()
    check observationDigest(ja) == observationDigest(obs)
    # Legacy `|` framing cannot represent any embedded `|`; use an entirely
    # pipe-free payload+context so both representations round-trip to the same
    # identity content (canonicalizeObservation excludes snapshotId/observedAt).
    var clean = mkObs()
    clean.payload = "plain payload without pipes"
    clean.toolchainContext = "nim-2.2.10"
    let le = parseObservationLine(observationRecordLegacy(clean))
    check le.isSome
    check observationDigest(le.get()) == observationDigest(clean)

suite "backward compatibility":
  test "legacy pipe record still parses":
    let line = "0|subj|si|snap|src|payload|2026-08-15T00:00:00Z|tc"
    let parsed = parseObservationLine(line)
    check parsed.isSome
    check parsed.get().subject == "subj"
    check parsed.get().observedAt == "2026-08-15T00:00:00Z"
    check parsed.get().toolchainContext == "tc"

  test "unparseable line yields none, not a crash":
    check parseObservationLine("").isNone
    check parseObservationLine("garbage-not-json|also|not|pipe|delimited").isNone

suite "index rebuild via stable digest":
  test "rebuildIndex keys by observationDigest":
    let tmp = getTempDir() / "ax_test_obs_" & $getCurrentProcessId() & ".journal"
    defer: removeFile(tmp)
    let obs = mkObs()
    discard appendObservation(obs, tmp)
    let idx = rebuildIndex(tmp)
    check idx.hasKey(observationDigest(obs))