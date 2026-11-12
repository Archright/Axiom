import std/[strutils, os]
import core/trusted/status_transition
import core/types/certificate_types

proc main() =
  echo "=== StatusTransition Tests ==="

  # Test 1: Append certGreen → certNotCurrent succeeds (projected current was certGreen)
  var events: seq[StatusTransition] = @[]
  let baseStatus = "certGreen"
  let t1 = makeStatusTransition(
    "cert-001",
    "certGreen",
    "certNotCurrent",
    "legacy_schema",
    "hash-001"
  )
  let ok1 = appendStatusTransition(events, t1, baseStatus)
  doAssert ok1 == true, "certGreen→certNotCurrent should succeed"
  doAssert events.len == 1, "events should have 1 entry"
  echo "  [PASS] certGreen→certNotCurrent appended successfully"

  # Test 2: projectedCurrentStatus after [green→notCurrent] = "certNotCurrent"
  let projected = projectedCurrentStatus(events, "cert-001", baseStatus)
  doAssert projected == "certNotCurrent",
    "projectedCurrentStatus should be certNotCurrent, got " & projected
  echo "  [PASS] projectedCurrentStatus = certNotCurrent"

  # Test 3: Forked transition certGreen→certRed rejected (fromStatus no longer current)
  let t2 = makeStatusTransition(
    "cert-001",
    "certGreen",
    "certRed",
    "legacy_schema",
    "hash-002"
  )
  let canAppend2 = canAppendTransition(events, t2, baseStatus)
  doAssert canAppend2 == false, "forked certGreen→certRed should be rejected by canAppendTransition"
  let ok2 = appendStatusTransition(events, t2, baseStatus)
  doAssert ok2 == false, "forked certGreen→certRed appendStatusTransition should return false"
  doAssert events.len == 1, "events should still have 1 entry (rejected)"
  echo "  [PASS] forked certGreen→certRed rejected"

  # Test 4: Invalid transition certNotCurrent→certGreen rejected (violates isValidTransition sink)
  let t3 = makeStatusTransition(
    "cert-001",
    "certNotCurrent",
    "certGreen",
    "legacy_schema",
    "hash-003"
  )
  let canAppend3 = canAppendTransition(events, t3, baseStatus)
  doAssert canAppend3 == true, "projected current is certNotCurrent, matching fromStatus"
  let ok3 = appendStatusTransition(events, t3, baseStatus)
  doAssert ok3 == false, "certNotCurrent→certGreen should be rejected by isValidTransition"
  doAssert events.len == 1, "events should still have 1 entry (rejected)"
  echo "  [PASS] certNotCurrent→certGreen rejected by isValidTransition"

  # Test 5: Determinism — same events produce same projected status
  let events2 = events
  let projected2 = projectedCurrentStatus(events2, "cert-001", baseStatus)
  doAssert projected == projected2, "determinism: same events must yield same projected status"
  echo "  [PASS] determinism: same events → same projected status"

  # Test 6: canAppendTransition returns false when fromStatus doesn't match projected current
  let t4 = makeStatusTransition(
    "cert-001",
    "certGreen",
    "certYellow",
    "legacy_schema",
    "hash-004"
  )
  let canAppend4 = canAppendTransition(events, t4, baseStatus)
  doAssert canAppend4 == false, "certGreen→certYellow should be rejected (current is certNotCurrent)"
  echo "  [PASS] canAppendTransition false for mismatched fromStatus"

  echo "=== StatusTransition Tests OK ==="

main()