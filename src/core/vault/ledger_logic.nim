import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Ledger Business Logic
## Extracted from: src/core/types/ledger_types.nim
## Symbols: buildIntegrityLedger, detectFingerprintMismatches, ledgerEntryToJson, ledgerToJson

import std/tables
import std/json
import core/types/domain_types
import core/types/ledger_types
import ../../core/trusted/axiom_pragmas

## Build Integrity Ledger.
func buildIntegrityLedger*(
  proofState: JsonNode;
  vaultIndex: VaultIndex;
  auditLines: seq[string] = newSeq[string]();
  historyMarkdown: string = ""
): Table[string, IntegrityLedgerEntry] {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  var merged = newSeq[(string, IntegrityLedgerEntry)]()

  let entriesNode = proofState{"entries"}
  if entriesNode.kind == JArray:
    for entry in entriesNode.elems:
      if entry.kind != JObject:
        continue
      let nodeId = entry{"nodeId"}.getStr("")
      if nodeId.len == 0:
        continue
      var ledgerEntry = emptyLedgerEntry(nodeId)
      ledgerEntry.label = entry{"label"}.getStr("")
      ledgerEntry.modulePath = entry{"modulePath"}.getStr("")
      ledgerEntry.functionName = entry{"functionName"}.getStr("")
      ledgerEntry.nodeType = entry{"nodeType"}.getStr("")
      ledgerEntry.currentStatus = entry{"status"}.getStr("")
      merged.add((nodeId, ledgerEntry))

  for key, vaultEntry in vaultIndex.entries:
    let nodeId = vaultEntry.modulePath & "::" & vaultEntry.functionName
    var foundIdx = -1
    for i in 0 ..< merged.len:
      if merged[i][0] == nodeId:
        foundIdx = i
        break
    if foundIdx >= 0:
      merged[foundIdx][1].certificateStatus = vaultEntry.status
      merged[foundIdx][1].certificateFingerprint = vaultEntry.fingerprint
    else:
      var ledgerEntry = emptyLedgerEntry(nodeId)
      ledgerEntry.modulePath = vaultEntry.modulePath
      ledgerEntry.functionName = vaultEntry.functionName
      ledgerEntry.certificateStatus = vaultEntry.status
      ledgerEntry.certificateFingerprint = vaultEntry.fingerprint
      merged.add((nodeId, ledgerEntry))

  result = initTable[string, IntegrityLedgerEntry]()
  for i in 0 ..< merged.len:
    result[merged[i][0]] = merged[i][1]

  discard auditLines
  discard historyMarkdown

## Detect Fingerprint Mismatches.
func detectFingerprintMismatches*(
  ledger: Table[string, IntegrityLedgerEntry];
  sourceFingerprintResolver: proc (nodeId: string): string {.noSideEffect, raises: [].}
): seq[string] {.raises: [].} =
  result = newSeq[string]()
  for nodeId, entry in ledger:
    if entry.certificateFingerprint.len == 0:
      continue
    let currentFingerprint = sourceFingerprintResolver(nodeId)
    if currentFingerprint.len > 0 and currentFingerprint != entry.certificateFingerprint:
      result.add(nodeId)

## Ledger Entry To Json.
func ledgerEntryToJson*(entry: IntegrityLedgerEntry): JsonNode {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  let historyNodes = newJArray()
  for transition in entry.history:
    historyNodes.add(%*{
      "timestamp": transition.timestamp,
      "from": transition.fromStatus,
      "to": transition.toStatus,
      "eventKind": $transition.eventKind,
      "reason": transition.reason,
      "actor": transition.actor
    })
  %*{
    "nodeId": entry.nodeId,
    "label": entry.label,
    "modulePath": entry.modulePath,
    "functionName": entry.functionName,
    "nodeType": entry.nodeType,
    "currentStatus": entry.currentStatus,
    "history": historyNodes,
    "certificateStatus": entry.certificateStatus,
    "certificateFingerprint": entry.certificateFingerprint,
    "solverMeta": entry.solverMeta
  }

## Ledger To Json.
func ledgerToJson*(ledger: Table[string, IntegrityLedgerEntry]): JsonNode {.raises: [].} =
  let entries = newJArray()
  for nodeId, entry in ledger:
    entries.add(ledgerEntryToJson(entry))
  %*{ "entries": entries, "count": ledger.len }

{.pop.}
