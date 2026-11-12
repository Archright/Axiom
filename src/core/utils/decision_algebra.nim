## decision_algebra.nim — Axiom's single decision algebra.
##
## One fact -> one decision -> thin projections. A surface that must answer
## "may we proceed?" consumes the DecisionResult produced by Decide instead of
## deriving a verdict of its own; two authorities for one fact is the defect
## this module exists to remove.
##
## Purity is a compile-time contract (AGENTS.md §0.6): Decide is `func` +
## {.raises: [].} and reads no clock, no filesystem, no environment and no
## network. Repository identity and toolchain identity arrive on
## ExecutionContract; evidence arrives already validated and normalized.
##
## Decision table — docs/spec/productization_contract.md §3:
##   GO             ⟺ every invariant is PASS
##   CONDITIONAL GO ⟺ every critical invariant is PASS ∧ ∃ non-critical ∉ PASS
##   NO-GO          ⟺ ∃ critical ∈ {FAIL, UNKNOWN, NOT_RUN}
## §4: UNKNOWN is never promoted to PASS.

import std/[json, strutils]
import core/crypto/hash_kernel
import core/utils/constants

{.push raises: [].}

type
  InvariantState* = enum
    stPass = "PASS"
    stFail = "FAIL"
    stUnknown = "UNKNOWN"
    stNotRun = "NOT_RUN"

const
  VerdictGo* = "GO"
  VerdictConditionalGo* = "CONDITIONAL GO"
  VerdictNoGo* = "NO-GO"

  OutcomeContinue* = "CONTINUE"
  OutcomeBlock* = "BLOCK"
  OutcomeUnresolved* = "UNRESOLVED"

  CategoryContractFail* = "CONTRACT_FAIL"
  CategoryUnknown* = "UNKNOWN"
  CategoryNone* = ""

type
  InvariantStatus* = object
    id*: string
    state*: InvariantState
    critical*: bool
    failureDomain*: string  ## documented failure domain of the invariant's rule

  DecisionCandidate* = object
    ## The closed invariant set under evaluation, in report order. Decide
    ## never reorders it and never invents an id.
    invariants*: seq[InvariantStatus]
    policyId*: string

  DecisionEvidence* = object
    ## Normalized, already-validated evidence. Decide treats it as an opaque
    ## digest anchor: interpreting observations belongs to the evaluator that
    ## produced the states.
    schemaVersion*: int
    digest*: string

  ExecutionContract* = object
    ## The repository / toolchain / policy identity the decision is taken
    ## under. A verdict is only current product truth for this contract.
    contractId*: string
    repoHead*: string
    treeDigest*: string
    toolchainIdentity*: string

  DecisionResult* = object
    schemaVersion*: int
    policyId*: string
    evidenceDigest*: string
    contractId*: string
    invariantStates*: seq[InvariantStatus]
    verdict*: string
    conditions*: seq[string]
    outcome*: string
    failureCategory*: string
    decisionDigest*: string

  StateDecision* = object
    ## One row of the decision table: the verdict, the outcome and the failure
    ## category that a single (criticality, state) fact produces. The three are
    ## axes of one decision, not three decisions.
    verdict*: string
    outcome*: string
    failureCategory*: string

  StatusToken* = tuple[id: string, critical: bool, token: string, failureDomain: string]

  DecisionAggregate* = object
    verdict*: string
    conditions*: seq[string]
    outcome*: string
    failureCategory*: string

# ---------------------------------------------------------------------------
# The single state -> decision mapping
# ---------------------------------------------------------------------------

func decideState*(critical: bool, st: InvariantState): StateDecision =
  ## THE single invariant-state mapping. The §3 table quoted above is its
  ## implementation; nothing else in the codebase maps a state to a decision.
  case st
  of stPass:
    StateDecision(verdict: VerdictGo, outcome: OutcomeContinue,
                  failureCategory: CategoryNone)
  of stFail:
    if critical:
      # failureCategory is the invariant's declared failure domain, filled in
      # by the aggregation below — the state alone does not name a domain.
      StateDecision(verdict: VerdictNoGo, outcome: OutcomeBlock,
                    failureCategory: CategoryNone)
    else:
      StateDecision(verdict: VerdictConditionalGo, outcome: OutcomeContinue,
                    failureCategory: CategoryNone)
  of stUnknown, stNotRun:
    # A critical invariant that was never established has exactly ONE verdict:
    # NO-GO. §3 states `NO-GO ⟺ ∃ critical ∈ {FAIL, UNKNOWN}` — UNKNOWN is a
    # member of that set, so treating it as anything weaker (CONDITIONAL GO) or
    # promoting it to PASS (§4 forbids it) would be a second authority inventing
    # a decision the table does not have.
    #
    # UNRESOLVED is not a competing verdict: it is the outcome axis recording
    # that no confirmed failure was established either, which is exactly the
    # observed/decision separation §4 mandates (continual revalidation).
    if critical:
      StateDecision(verdict: VerdictNoGo, outcome: OutcomeUnresolved,
                    failureCategory: CategoryUnknown)
    else:
      StateDecision(verdict: VerdictConditionalGo, outcome: OutcomeContinue,
                    failureCategory: CategoryNone)

func decideStateToken*(critical: bool, token: string): StateDecision =
  ## Token adapter for surfaces that carry a state as a string rather than as
  ## InvariantState. An unrecognised token is read as not-established (the
  ## fail-closed reading of §4), never as PASS.
  case token
  of "PASS": decideState(critical, stPass)
  of "FAIL": decideState(critical, stFail)
  of "UNKNOWN": decideState(critical, stUnknown)
  of "NOT_RUN": decideState(critical, stNotRun)
  else: decideState(critical, stNotRun)

func decideTokens*(statuses: seq[StatusToken]): DecisionAggregate =
  ## The single aggregation. verdict and outcome are produced by one pass over
  ## one set of decideState rows, so no observed state can be judged twice.
  ## Precedence: verdict NO-GO > CONDITIONAL GO > GO; outcome BLOCK >
  ## UNRESOLVED > CONTINUE (a confirmed failure outranks an unestablished one).
  result = DecisionAggregate(verdict: VerdictGo, conditions: @[],
                             outcome: OutcomeContinue, failureCategory: CategoryNone)
  for s in statuses:
    let d = decideStateToken(s.critical, s.token)
    if d.verdict == VerdictNoGo:
      result.verdict = VerdictNoGo
    elif d.verdict == VerdictConditionalGo and result.verdict == VerdictGo:
      result.verdict = VerdictConditionalGo
      result.conditions.add(s.id & "=" & s.token)
    if d.outcome == OutcomeBlock:
      if result.outcome != OutcomeBlock:
        result.outcome = OutcomeBlock
        result.failureCategory = if s.failureDomain != "": s.failureDomain
                                 else: CategoryContractFail
    elif d.outcome == OutcomeUnresolved and result.outcome == OutcomeContinue:
      result.outcome = OutcomeUnresolved
      result.failureCategory = CategoryUnknown
  if result.verdict == VerdictNoGo:
    result.conditions = @[]

# ---------------------------------------------------------------------------
# The single run-exit rule (run summary -> exit-axis outcome)
# ---------------------------------------------------------------------------

const
  unsetCount = -1  ## sentinel: a count that is absent or not an integer

func countOrUnset(summary: JsonNode, key: string): int =
  ## Fail-closed count read: a key that is absent or is not an integer yields
  ## `unsetCount`, never a silent 0. "No failures recorded" is a claim that must
  ## be readable to be believed.
  let v = summary.getOrDefault(key)
  if v.isNil or v.kind != JInt: unsetCount else: v.getInt(0)

func projectRunOutcome*(reportNode: JsonNode): string =
  ## THE single run-exit rule. `ax prove` and `ax report` derive their exit code
  ## from this one function; no surface re-derives it (productization_contract
  ## §7 — verification-failure / exit 1).
  ##
  ## The rule reads the run summary only:
  ##   BLOCK      — verification claims not established by a failure:
  ##                failedCount > 0, or verified == 0 with a hang-guard abort.
  ##   UNRESOLVED — claims not established because verification is incomplete:
  ##                verified > 0 with a hang-guard abort (timeoutCount > 0), or
  ##                a summary that cannot be read (missing / malformed / counts
  ##                absent).
  ##   CONTINUE   — failedCount == 0 ∧ timeoutCount == 0, and either
  ##                verified > 0 or an empty (no-obligation) run.
  ##
  ## Axis separation: a wall-clock timeout is a hang-guard node abort, not a
  ## verification verdict (the verdict axis never reads timeoutCount), but the
  ## exit axis is fail-closed about incomplete verification.
  let summary = reportNode.getOrDefault("summary")
  if summary.isNil or summary.kind != JObject:
    return OutcomeUnresolved
  if not summary.hasKey(verifiedKey):
    # topology-only preview (no `verified` key — the shortcut scan path): not
    # covered by the rule, legacy behaviour preserved (contract §7 note).
    return OutcomeContinue
  let verified = countOrUnset(summary, verifiedKey)
  let failedCount = countOrUnset(summary, "failedCount")
  let timeoutCount = countOrUnset(summary, "timeoutCount")
  if verified == unsetCount or failedCount == unsetCount or
     timeoutCount == unsetCount:
    return OutcomeUnresolved
  if failedCount > 0:
    return OutcomeBlock
  if verified == 0 and timeoutCount > 0:
    return OutcomeBlock
  if timeoutCount > 0:
    return OutcomeUnresolved
  # failedCount == 0 ∧ timeoutCount == 0: verified > 0 (success) or verified == 0
  # (empty / no-obligation run — §7 requires a failed or timed-out node to make
  # `verified == 0` a failure).
  return OutcomeContinue

# ---------------------------------------------------------------------------
# Canonical JSON + digest (single implementation, shared by every projection)
# ---------------------------------------------------------------------------

func canonicalJson*(n: JsonNode): string =
  ## Keys sorted, compact, no whitespace. Deterministic.
  if n == nil:
    return "null"
  case n.kind
  of JObject:
    var keys: seq[string] = @[]
    for k in n.keys:
      keys.add(k)
    var i = 1
    while i < keys.len:
      let k = keys[i]
      var j = i
      while j > 0 and keys[j - 1] > k:
        keys[j] = keys[j - 1]
        dec j
      keys[j] = k
      inc i
    var parts: seq[string] = @[]
    for k in keys:
      var child: JsonNode = newJNull()
      try:
        child = n[k]
      except KeyError:
        discard  # keys originate from n.keys, so this is unreachable in practice
      parts.add(escapeJson(k) & ":" & canonicalJson(child))
    result = "{" & parts.join(",") & "}"
  of JArray:
    var parts: seq[string] = @[]
    for it in n.items:
      parts.add(canonicalJson(it))
    result = "[" & parts.join(",") & "]"
  of JString:
    result = escapeJson(n.getStr())
  of JInt:
    result = $n.getInt()
  of JFloat:
    result = $n.getFloat()
  of JBool:
    result = if n.getBool(): "true" else: "false"
  of JNull:
    result = "null"

func canonicalSha256*(n: JsonNode): string =
  sha256Hex(canonicalJson(n))

func invariantStatesJson*(invariants: seq[InvariantStatus]): JsonNode =
  ## {"R1": "PASS", ...} in candidate order — the projection Decide digests.
  result = newJObject()
  for inv in invariants:
    result[inv.id] = %($inv.state)

# ---------------------------------------------------------------------------
# Decide
# ---------------------------------------------------------------------------

func Decide*(candidate: DecisionCandidate, evidence: DecisionEvidence,
             executionContract: ExecutionContract): DecisionResult =
  ## Pure: the same (candidate, evidence, executionContract) always yields the
  ## same DecisionResult, on any machine, at any wall-clock time.
  var statuses: seq[StatusToken] = @[]
  for inv in candidate.invariants:
    statuses.add((id: inv.id, critical: inv.critical, token: $inv.state,
                  failureDomain: inv.failureDomain))
  let agg = decideTokens(statuses)

  let payload = newJObject()
  payload["verdict"] = %agg.verdict
  let condArr = newJArray()
  for c in agg.conditions:
    condArr.add(%c)
  payload["conditions"] = condArr
  payload["invariantStates"] = invariantStatesJson(candidate.invariants)

  result = DecisionResult(
    schemaVersion: 1,
    policyId: candidate.policyId,
    evidenceDigest: evidence.digest,
    contractId: executionContract.contractId,
    invariantStates: candidate.invariants,
    verdict: agg.verdict,
    conditions: agg.conditions,
    outcome: agg.outcome,
    failureCategory: agg.failureCategory,
    decisionDigest: canonicalSha256(payload))

func isCurrent*(r: DecisionResult, c: ExecutionContract): bool =
  ## A decision is current product truth only for the contract it was taken
  ## under; a re-decision under a different contract must not inherit it.
  ## This is the core-side predicate a CLI exit projection needs before it
  ## may report the verdict as current (CliOutcome.NOT_CURRENT).
  r.contractId == c.contractId

{.pop.}
