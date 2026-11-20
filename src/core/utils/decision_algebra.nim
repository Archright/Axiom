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
import core/trusted/axiom_pragmas_lite
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
  runOutcomeKey = "runOutcome"
  runVerdictKey = "verdict"
  runGateVerdictKey = "gateVerdict"
  verdictPass = "PASS"
  verdictFail = "FAIL"

func projectRunOutcome*(reportNode: JsonNode): string {.
    axiomDecision(id = "DECISION-0831", reason = "The single run-exit rule: maps the canonical runOutcome verdict block to CONTINUE/BLOCK/UNRESOLVED and never reads summary counts. Missing, malformed, or projection-contradicting documents are UNRESOLVED, so no adapter can infer success from telemetry", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v34").} =
  ## THE single run-exit rule. `ax prove` and `ax report` derive their exit code
  ## from this one function; no surface re-derives it (productization_contract
  ## §7).
  ##
  ## The rule consumes ONLY the canonical authority block written by
  ## verification_decision_authority.evaluateRunOutcome / the read-path
  ## re-decision:
  ##   CONTINUE   — verdict == PASS
  ##   BLOCK      — verdict == FAIL
  ##   UNRESOLVED — verdict == BLOCKED / INCONCLUSIVE, or the block is missing,
  ##                malformed, or contradicts its gateVerdict projection.
  ##
  ## `summary` is telemetry. It is never read here: a count cannot establish a
  ## verification claim, and an absent count cannot be treated as zero success.
  ## A document without `runOutcome` (pre-loop skeleton, legacy/checkpoint
  ## state, topology scan) is UNRESOLVED — never an inferred success.
  ##
  ## `gateVerdict` is a serialization projection of `verdict` (PASS iff
  ## verdict == PASS). A contradiction between the two is an UNKNOWN document,
  ## never a PASS.
  if reportNode.isNil or reportNode.kind != JObject:
    return OutcomeUnresolved
  let runOutcome = reportNode.getOrDefault(runOutcomeKey)
  if runOutcome.isNil or runOutcome.kind != JObject:
    return OutcomeUnresolved
  let verdictNode = runOutcome.getOrDefault(runVerdictKey)
  if verdictNode.isNil or verdictNode.kind != JString:
    return OutcomeUnresolved
  let verdict = verdictNode.getStr()
  let gateNode = runOutcome.getOrDefault(runGateVerdictKey)
  if not gateNode.isNil and gateNode.kind != JNull:
    if gateNode.kind != JString:
      return OutcomeUnresolved
    let expectedGate = if verdict == verdictPass: verdictPass else: verdictFail
    if gateNode.getStr() != expectedGate:
      return OutcomeUnresolved
  if verdict == verdictPass:
    return OutcomeContinue
  if verdict == verdictFail:
    return OutcomeBlock
  # BLOCKED / INCONCLUSIVE / unknown vocabulary all collapse to the same
  # fail-closed axis.
  OutcomeUnresolved

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
