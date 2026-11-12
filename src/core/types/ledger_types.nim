import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Pure Ledger Types
## Extracted from integrity_ledger.nim to prevent Domain→Infrastructure
## reverse references during module relocation.

import std/json
import core/trusted/axiom_pragmas

type
  IntegrityEventKind* = enum
    iekSmtSat
    iekLeanProof
    iekHealAttempt
    iekAutoSync
    iekStatusChange
    iekCertificateVault
    iekAuditLog
    iekHumanIntent

  StateTransition* = object
    timestamp*: string
    fromStatus*: string
    toStatus*: string
    eventKind*: IntegrityEventKind
    reason*: string
    actor*: string

  IntegrityLedgerEntry* = object
    nodeId*: string
    label*: string
    modulePath*: string
    functionName*: string
    nodeType*: string
    currentStatus*: string
    history*: seq[StateTransition]
    certificateStatus*: string
    certificateFingerprint*: string
    solverMeta*: JsonNode

## Empty Ledger Entry.
func emptyLedgerEntry*(nodeId: string): IntegrityLedgerEntry {.raises: [], axiom: ["(assert ast_parse_failed_isolated)", "ast_parse_failed_isolated"].} =
  IntegrityLedgerEntry(
    nodeId: nodeId,
    history: newSeq[StateTransition](),
    solverMeta: newJObject()
  )

{.pop.}
{.pop.}
