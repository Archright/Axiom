import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Reasoning Ledger Recorder (Wave 15)
##
## [AXIOM v0.6.8] Audit trail is buffered per-thread in-memory and merged
## into the global buffer by the main thread after parallel execution.
## Mid-pipeline disk I/O on reasoning_ledger.jsonl is permanently discontinued.

import std/times
import core/json/std_redirect
import ../../core/trusted/axiom_pragmas

const reasoningLedgerPath* = "logs/audit/reasoning_ledger.jsonl"

## Per-thread reasoning trail buffer. Worker threads accumulate events here;
## the main thread drains each worker's buffer after executeHealNode returns.
var threadReasoningTrail {.threadvar.}: seq[JsonNode]

proc recordReasoningEvent*(nodeId: string; event: JsonNode) {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) ast_parse_failed_isolated))", "nodeId.length ≥ 0 ∧ ast_parse_failed_isolated"].} =
  var entry = event
  entry["nodeId"] = %nodeId
  entry["ts"] = %now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'")
  threadReasoningTrail.add(entry)

proc drainThreadReasoningTrail*(): seq[JsonNode] {.raises: [].} =
  ## Return and clear the current thread's reasoning trail buffer.
  result = threadReasoningTrail
  threadReasoningTrail = @[]

proc recordPhase*(nodeId, phase, detail: string; strategy: string = "";
                  hintProp: string = ""; hintSmt: string = "";
                  leanError: string = ""; leanSource: string = "";
                  retryCount: int = 0) {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) (>= (str.len phase) 0) (>= (str.len detail) 0) (>= (str.len strategy) 0) (>= (str.len hintProp) 0) (>= (str.len hintSmt) 0) (>= (str.len leanError) 0) (>= (str.len leanSource) 0) (and (>= retryCount -9223372036854775808) (<= retryCount 9223372036854775807)) ast_parse_failed_isolated))", "nodeId.length ≥ 0 ∧ phase.length ≥ 0 ∧ detail.length ≥ 0 ∧ strategy.length ≥ 0 ∧ hintProp.length ≥ 0 ∧ hintSmt.length ≥ 0 ∧ leanError.length ≥ 0 ∧ leanSource.length ≥ 0 ∧ retryCount ≥ -9223372036854775808 ∧ retryCount ≤ 9223372036854775807 ∧ ast_parse_failed_isolated"].} =
  recordReasoningEvent(nodeId, %*{
    "phase": phase,
    "detail": detail,
    "strategy": strategy,
    "hintProposition": hintProp,
    "hintSmt": hintSmt,
    "leanError": leanError,
    "leanSource": leanSource,
    "retryCount": retryCount
  })

proc recordVerdict*(nodeId, verdict, reason: string;
                    winningStrategy: string = ""; retryCount: int = 0) {.raises: [], axiom: ["(assert (and (>= (str.len nodeId) 0) (>= (str.len verdict) 0) (>= (str.len reason) 0) (>= (str.len winningStrategy) 0) (and (>= retryCount -9223372036854775808) (<= retryCount 9223372036854775807))))", "nodeId.length ≥ 0 ∧ verdict.length ≥ 0 ∧ reason.length ≥ 0 ∧ winningStrategy.length ≥ 0 ∧ retryCount ≥ -9223372036854775808 ∧ retryCount ≤ 9223372036854775807"].} =
  recordReasoningEvent(nodeId, %*{
    "phase": "verdict",
    "verdict": verdict,
    "reason": reason,
    "winningStrategy": winningStrategy,
    "retryCount": retryCount
  })

{.pop.}
