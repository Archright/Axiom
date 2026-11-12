## Lean LSP Types — Pure type definitions for the Lean LSP subsystem.
## Tier 0: DAG leaf module. No core/ imports except stdlib.
## IoC callback types enable inversion of control without circular imports.
import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import std/json
import std/tables
import std/asyncfutures
import std/osproc
import std/streams
import std/locks
import std/times
import core/types/domain_types
export domain_types.LeanDiagnostic

type
  LeanGoalState* {.acyclic.} = object
    ## Structured proof goal from `$/lean/plainGoal` LSP method.
    ## Provides parsed hypothesis/conclusion breakdown instead of raw text.
    goalText*: string              ## Full goal as displayed (e.g. "⊢ foo.bar")
    hypotheses*: seq[string]        ## Local context / assumptions
    conclusion*: string             ## The main goal to prove
    position*: tuple[line, character: int]  ## Position where goal was queried

  GoalDelta* = object
    ## Structured comparison between Goal states before/after a tactic.
    ## Tracks what proof goals were resolved, created, or unchanged.
    ## Used by the Legislator feedback prompt for goal-aware invariant drafting.
    unchangedGoals*: seq[string]   ## Goals present in both before and after
    resolvedGoals*: seq[string]    ## Goals in before but NOT in after (solved!)
    newGoals*: seq[string]         ## Goals in after but NOT in before (created)
    typeErrors*: seq[string]       ## Type mismatch errors observed

  # IoC callback types — closure convention required for environment capture
  ShutdownCallback* = proc() {.closure, raises: [].}
  KillProcessCallback* = proc(p: Process) {.closure, raises: [CatchableError].}

  LeanSearchResult* = object
    succeeded*: bool
    attempts*: int
    finalTactic*: string
    reason*: string
    diagnostics*: seq[LeanDiagnostic]
    goals*: seq[string]
    tacticTrace*: seq[string]
    hypothesisSuggestions*: seq[string]
    proofVaultArtifact*: string

  LeanCompilerResult* = object
    verified*: bool
    negativeTestVerified*: bool
    exitCode*: int
    diagnostics*: seq[LeanDiagnostic]
    output*: string
    artifactPath*: string
    vacuityProven*: bool          ## Anti-vacuity linter result (Phase A-2)

  LeanLspClient* {.acyclic.} = ref object
    p*: Process
    input*: Stream
    output*: Stream
    nextId*: int
    uri*: string
    version*: int
    pendingRequests*: Table[int, Future[JsonNode]]
    notifications*: seq[JsonNode]
    isShutdown*: bool
    msgChannel*: Channel[string]
    readerThread*: Thread[LeanLspClient]
    onShutdown*: ShutdownCallback
    onKillProcess*: KillProcessCallback
    diagnosticNotificationCount*: int ## Number of publishDiagnostics notifications received
    lastUsed*: Time ## Last time this client was acquired from the pool for use

  LeanSymbolKind* = enum
    lskTheorem, lskDef, lskLemma, lskAxiom, lskInductive, lskStructure, lskClass, lskInstance, lskOther

  LeanSymbol* = object
    name*: string
    kind*: LeanSymbolKind
    range*: tuple[startLine, startCol, endLine, endCol: int]
    children*: seq[LeanSymbol]

  AxiomLspError* = object of CatchableError

  LeanLspClientPool* = object
    activeClients*: seq[LeanLspClient]
    gate*: Lock
    maxPoolSize*: int ## Maximum number of pooled clients (0 = unlimited)
    idleTimeoutSec*: float ## Seconds before an idle client is discarded (default: 300.0 = 5 min)

{.pop.}
