## orchestrator_types.nim — Leaf-node type module for orchestrator layer.
## No procs, no I/O. Guarantees zero cyclic dependency risk.

import core/trusted/layer_declaration
axiomLayer "gate"
import std/tables
import std/osproc
import std/times
import core/types/gate_types  # FailureCategory

const
  L2GateTimeoutMs* = when defined(axiomL2TimeoutMs):
    axiomL2TimeoutMs.int else: 30_000
  GlobalMaxTokens* = when defined(axiomGlobalMaxTokens):
    axiomGlobalMaxTokens.int
  else:
    12

type
  GateRunStatus* = enum
    grsSuccess
    grsFailed
    grsTimeout
    grsCrash

  GateRunRecord* = object
    status*: GateRunStatus
    elapsedMs*: int
    failCategory*: FailureCategory
    failReason*: string

  SessionJournal* {.acyclic.} = ref object
    entries*: Table[string, GateRunRecord]

  RunningGate* = object
    process*: Process
    gateIdx*: int
    startTime*: times.Time
    allocatedTokens*: int
    outputLog*: string

  WaitStatusKind* = enum
    wskRunning
    wskExited
    wskSignalKilled
