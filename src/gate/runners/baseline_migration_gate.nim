import gate/baseline_transition
import std/json
import std/os
import std/strutils
import core/axiom_pragmas
const debtMarker430 {.axiomDebt: "DEBT#430".} = true

## DEBT#430: ci.yml:8 claims "push CI is ax baseline check" but no step invokes
## `ax baseline check` (VKD checker). Only the local Makefile:300 ci-bootstrap runs
## it — proof-bearing regressions can lower VKD without CI failing closed.

proc runBaselineMigrationGate*(old: BaselineTransitionInput, new: BaselineTransitionInput): int =
  let transition = BaselineTransitionInput(
    oldClaimPolicyVersion: old.newClaimPolicyVersion,
    newClaimPolicyVersion: new.newClaimPolicyVersion,
    oldClaimSetHash: old.newClaimSetHash,
    newClaimSetHash: new.newClaimSetHash,
    oldVkdNum: old.newVkdNum,
    newVkdNum: new.newVkdNum,
    policyDrift: new.policyDrift
  )
  let kind = classifyChange(transition)
  case kind
  of tkRegression, tkInvalidState:
    echo "BASELINE MIGRATION GATE: FAIL — " & $kind
    return 1
  of tkImprovement:
    echo "BASELINE MIGRATION GATE: PASS — improvement detected"
    return 0
  of tkReclassification:
    echo "BASELINE MIGRATION GATE: PASS — reclassification detected"
    return 0
  of tkMigration:
    echo "BASELINE MIGRATION GATE: PASS — migration detected"
    return 0

when isMainModule:
  if paramCount() < 2:
    echo "Usage: baseline_migration_gate <old_baseline.json> <new_baseline.json>"
    quit(2)
  let oldPath = paramStr(1)
  let newPath = paramStr(2)
  if not fileExists(oldPath):
    echo "Error: old baseline file not found: " & oldPath
    quit(2)
  if not fileExists(newPath):
    echo "Error: new baseline file not found: " & newPath
    quit(2)
  let oldJson = parseJson(readFile(oldPath))
  let newJson = parseJson(readFile(newPath))
  let old = BaselineTransitionInput(
    oldClaimPolicyVersion: oldJson["oldClaimPolicyVersion"].getStr(""),
    newClaimPolicyVersion: oldJson["newClaimPolicyVersion"].getStr(""),
    oldClaimSetHash: oldJson["oldClaimSetHash"].getStr(""),
    newClaimSetHash: oldJson["newClaimSetHash"].getStr(""),
    oldVkdNum: oldJson["oldVkdNum"].getInt(0),
    newVkdNum: oldJson["newVkdNum"].getInt(0),
    policyDrift: oldJson["policyDrift"].getBool(false)
  )
  let new = BaselineTransitionInput(
    oldClaimPolicyVersion: newJson["oldClaimPolicyVersion"].getStr(""),
    newClaimPolicyVersion: newJson["newClaimPolicyVersion"].getStr(""),
    oldClaimSetHash: newJson["oldClaimSetHash"].getStr(""),
    newClaimSetHash: newJson["newClaimSetHash"].getStr(""),
    oldVkdNum: newJson["oldVkdNum"].getInt(0),
    newVkdNum: newJson["newVkdNum"].getInt(0),
    policyDrift: newJson["policyDrift"].getBool(false)
  )
  let exitCode = runBaselineMigrationGate(old, new)
  quit(exitCode)