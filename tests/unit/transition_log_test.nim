import std/[json, tables, unittest]
import verification/integrity_ledger
import cli/wf_state

suite "Transition Log":
  test "mergeTransitionLogIntoProofState appends transition on status change":
    var proofState = %*{
      "entries": [
        {"nodeId": "core/test.nim::foo", "label": "test.nim::foo", "status": "verified", "strategy": "prove"}
      ]
    }
    var ledger = initTable[string, IntegrityLedgerEntry]()
    ledger["core/test.nim::foo"] = IntegrityLedgerEntry(
      nodeId: "core/test.nim::foo",
      history: @[],
      solverMeta: newJObject()
    )
    mergeTransitionLogIntoProofState(proofState, ledger)
    let entry = proofState["entries"][0]
    check entry.hasKey("transitionLog")
    check entry["transitionLog"].kind == JArray
    check entry["transitionLog"].len == 1
    check entry["transitionLog"][0]{"to"}.getStr() == "verified"
    check entry["transitionLog"][0]{"actor"}.getStr() == "prove"

  test "mergeTransitionLogIntoProofState does not duplicate same status":
    var proofState = %*{
      "entries": [
        {"nodeId": "core/test.nim::foo", "label": "test.nim::foo", "status": "verified", "strategy": "prove",
         "transitionLog": [{"ts": "2026-01-01T00:00:00Z", "from": "", "to": "verified", "actor": "prove", "reason": "status-updated"}]}
      ]
    }
    var ledger = initTable[string, IntegrityLedgerEntry]()
    ledger["core/test.nim::foo"] = IntegrityLedgerEntry(
      nodeId: "core/test.nim::foo",
      history: @[],
      solverMeta: newJObject()
    )
    mergeTransitionLogIntoProofState(proofState, ledger)
    let entry = proofState["entries"][0]
    check entry["transitionLog"].len == 1

  test "mergeTransitionLogIntoProofState caps at 10 entries":
    var existingLog = newJArray()
    for i in 1..10:
      existingLog.add(%*{"ts": "2026-01-" & $i & "T00:00:00Z", "from": "", "to": "verified", "actor": "prove", "reason": "test"})
    var proofState = %*{
      "entries": [
        {"nodeId": "core/test.nim::foo", "label": "test.nim::foo", "status": "unverifiable", "strategy": "heal",
         "transitionLog": existingLog}
      ]
    }
    var ledger = initTable[string, IntegrityLedgerEntry]()
    ledger["core/test.nim::foo"] = IntegrityLedgerEntry(
      nodeId: "core/test.nim::foo",
      history: @[],
      solverMeta: newJObject()
    )
    mergeTransitionLogIntoProofState(proofState, ledger)
    let entry = proofState["entries"][0]
    check entry["transitionLog"].len == 10
    check entry["transitionLog"][0]{"ts"}.getStr() == "2026-01-2T00:00:00Z"
    check entry["transitionLog"][9]{"to"}.getStr() == "unverifiable"
