import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## VerificationDecisionAuthority — Authority C (R4)
##
## The ONLY authority that may produce a verified verdict from a
## KernelAcceptanceAttestation.  `evaluate(KAA, Policy)` is the
## decision boundary; only it may produce `vdVerified`.
##
## This authority is policy-neutral in its inputs (KAA is policy-neutral
## per Authority B) but applies the current VerificationPolicy to
## decide whether the accepted artifact qualifies as VERIFIED.
##
## Invariant: Only VerificationDecisionAuthority may produce vdVerified.
## No other code path may set a verdict to verified without passing
## through this authority's evaluate function.
##
## Run-level (Plan 1 — Authority Unification, INV-X1 inversion):
## `evaluateRunOutcome(raw accounting, universe provenance, fact-gate)` is
## the run-level decision boundary; only it may produce `vrPass` (with its
## verbal basis PROVEN / NO_OBLIGATION / REUSED). No other code path may
## set a run-level PASS without passing through this authority.

import verification/obligation/kernel_acceptance_authority
import verification/obligation/identity
import verification/accounting/run_accounting
import core/crypto/hash_kernel
import std/[algorithm, json, strutils]

# ---------------------------------------------------------------------------
# SorryPolicy — how sorry markers are treated in verification decisions
# ---------------------------------------------------------------------------

type SorryPolicy* = enum
  spForbid       ## sorry markers → PolicyRejected
  spAllow        ## sorry markers → Candidate (not VERIFIED)
  spIgnore       ## deprecated alias of spAllow: a sorry-bearing artifact
                 ## can never qualify as VERIFIED under either value

# ---------------------------------------------------------------------------
# VerificationPolicy — the current product policy for VERIFIED qualification
# ---------------------------------------------------------------------------
## Contains the rules that determine whether a KernelAcceptanceAttestation
## qualifies as VERIFIED.  Policy is separate from the kernel fact —
## the same kernel ACCEPT may be VERIFIED under one policy and
## PolicyRejected under another (e.g., different axiom allowlists).

type VerificationPolicy* = object
  allowedAxioms*: seq[string]       ## axioms permitted in the artifact
  sorryPolicy*: SorryPolicy         ## how sorry markers are treated
  ## NOTE: no `requireLeanEvidence` field — the KAA input type ITSELF is the
  ## guarantee that genuine Lean kernel evidence exists (KAA can only be
  ## produced from an actual canonical kernel receipt). A separate boolean
  ## would duplicate that semantics and invite "KAA present but not required"
  ## second evidence regimes. KAA = the fact; Policy = whether the fact
  ## qualifies as VERIFIED under current product rules.

# ---------------------------------------------------------------------------
# VerificationDecision — the result of evaluating a KAA against a Policy
# ---------------------------------------------------------------------------

type VerificationDecision* = enum
  vdVerified        ## KAA exists ∧ CurrentPolicySatisfied
  vdCandidate       ## KAA exists but policy does not yet qualify
  vdPolicyRejected  ## KAA exists but policy explicitly rejects

# ---------------------------------------------------------------------------
# Private verdict constructor — only evaluate may produce verified
# ---------------------------------------------------------------------------
## The private (non-exported) constructor ensures that only `evaluate` can
## produce a verified decision.  This is the compile-time enforcement of
## "Only VerificationDecisionAuthority may produce vdVerified".

func makeVerifiedDecision(kaa: KernelAcceptanceAttestation;
                            policy: VerificationPolicy): VerificationDecision {.
  raises: [].} =
  ## Decision function: evaluate KAA against Policy.
  ## Returns vdVerified only when:
  ##   1. KAA exists (receipt from canonicalLeanKernelCheck)
  ##   2. Policy is satisfied (axioms allowed, sorry policy permits)
  ##
  ## This is the SINGLE verified-verdict production point.
  ## No other code path may produce vdVerified.

  # Check axiom allowlist. An empty allowlist permits NO axioms — it never
  # silently skips the check (fail-closed); a KAA with no observed axioms
  # still qualifies.
  for axiom in kaa.kaaAxiomSet():
    if axiom notin policy.allowedAxioms:
      return vdPolicyRejected

  # Check sorry policy
  case policy.sorryPolicy
  of spForbid:
    if kaa.kaaSorryScan().len > 0:
      return vdPolicyRejected
  of spAllow, spIgnore:
    # Doc-vs-code resolution (docs/spec/base36_sizing_binding_contract.md §5):
    # the code was wrong — a sorry-bearing artifact is tolerated as evidence
    # but caps at Candidate, never VERIFIED.
    if kaa.kaaSorryScan().len > 0:
      return vdCandidate

  # NOTE: no Z3-only depth limit here — Z3-only evidence can never reach this
  # function at all (it cannot produce a KAA). Candidate-only status of Z3
  # evidence is enforced upstream by the static architecture gate.

  # If all checks pass, the KAA is verified under this policy
  vdVerified

# ---------------------------------------------------------------------------
# evaluate — the decision boundary (Authority C)
# ---------------------------------------------------------------------------
## `evaluate(KAA, Policy)` is the sole decision boundary.
## It applies the VerificationPolicy to the KernelAcceptanceAttestation
## and produces a VerificationDecision.
##
## Invariant: Only this function may produce vdVerified.
## The KAA input guarantees that a real canonical Lean kernel check
## occurred (KAA exists → Receipt exists → CanonicalLeanKernelCheckOccurred).

proc evaluate*(kaa: KernelAcceptanceAttestation;
               policy: VerificationPolicy): VerificationDecision {.
  raises: [].} =
  ## Evaluate a KernelAcceptanceAttestation against a VerificationPolicy.
  ## This is the decision boundary — the only place that may produce
  ## a verified verdict.
  makeVerifiedDecision(kaa, policy)

# ---------------------------------------------------------------------------
# Helper: check if a policy is satisfied (public for query, not for verdict production)
# ---------------------------------------------------------------------------

func policySatisfied*(kaa: KernelAcceptanceAttestation;
                      policy: VerificationPolicy): bool {.raises: [].} =
  ## Check whether the KAA satisfies the policy (without producing a verdict).
  ## Useful for query/inspection without triggering the decision boundary.
  ## Mirrors makeVerifiedDecision: empty allowlist permits no axioms;
  ## sorry-bearing artifacts do not satisfy spForbid/spAllow/spIgnore.
  for axiom in kaa.kaaAxiomSet():
    if axiom notin policy.allowedAxioms:
      return false
  case policy.sorryPolicy
  of spForbid:
    if kaa.kaaSorryScan().len > 0:
      return false
  of spAllow, spIgnore:
    if kaa.kaaSorryScan().len > 0:
      return false
  true

# ---------------------------------------------------------------------------
# C1.5 Decision Identity — VerificationPolicyRevision + DecisionIdentity
# ---------------------------------------------------------------------------
## VerificationPolicyRevision is a stable, deterministic digest of the
## VerificationPolicy.  DecisionIdentity = H(KAAIdentity + VerificationPolicyRevision).
## Policy changes must NOT contaminate execution identity.

func verificationPolicyRevision*(policy: VerificationPolicy): string {.raises: [].} =
  ## Stable, deterministic digest of the VerificationPolicy.
  ## Uses sorted axiom list for canonical ordering.
  sha256Hex(
    policy.allowedAxioms.sorted.join("|") & "|" &
    $policy.sorryPolicy
  )

func decisionIdentity*(kaaIdentity: string; policyRevision: string): string {.raises: [].} =
  sha256Hex(kaaIdentity & "|" & policyRevision)

# ---------------------------------------------------------------------------
# Run-level verdict — Authority Unification (Plan 1, INV-X1 inversion)
# ---------------------------------------------------------------------------
## The run-level counterpart of the unit-level authority: just as only
## `evaluate(KAA, Policy)` may produce `vdVerified`, ONLY `evaluateRunOutcome`
## may produce a run-level PASS (`vrPass`). run_accounting preserves raw
## state; the verdict/basis are decided here from (raw state + universe /
## REUSED evidence) per the decision tree in
## docs/spec/execution_accounting_contract.md §17:
##   PASS(PROVEN)      — obligation ≥1 ∧ KAA (fresh verified evidence) exists
##   PASS(NO_OBLIGATION) — non-empty universe ∧ all NOT_REQUIRED ∧ enumeration
##                        completed ∧ NoObligationProvenance ("0이라서 PASS" 금지)
##   PASS(REUSED)      — every satisfied unit's reuse basis established by the
##                       5-condition re-verification (the reducer performs the
##                       per-row verification on the execution path; VDA decides
##                       the final PASS and records the condition set)
##   FAIL              — proof-level failure only (proofFailedCount ≥ 1:
##                       counterexample/UNSATISFIED after a genuine attempt)
##   BLOCKED           — pending ∧ attempted==0 ∧ fact-gate
##   INCONCLUSIVE      — timeout (raw) · infra/evidence failure · vacuous ·
##                       skipped · contested · unresolved enumeration — never
##                       mixed into FAIL (the accounting's timeout→UNSATISFIED
##                       aggregation is preserved as the raw fact)
## Only this module may reference `vrPass` in a value-producing position
## (evidence_truth_boundary_gate, table entry).

type NoObligationProvenance* = object
  ## Universe/OGR enumeration provenance for the NO_OBLIGATION PASS basis.
  ## The canonical OGR/eligibility enumeration completed over a NON-EMPTY
  ## universe and every unit was classified NOT_REQUIRED.
  universeEnumerated*: bool
  source*: string   ## provenance source label (e.g. "canonical_ogr_eligibility")

const restoredStateSource* = "restored_state_read_path"
  ## provenance label for a restored state — deliberately NOT an enumeration
  ## provenance (see evaluateRestoredStateRunOutcome).

func makeRunOutcomeVerdict(
  accounting: RunAccounting;
  noObligation: NoObligationProvenance;
  factGateActive: bool;
  identityBound: bool = true
): RunOutcome {.raises: [].} =
  ## Private run-verdict constructor — the SINGLE run-level PASS production
  ## point (the KAA analogue of makeVerifiedDecision). Only the evaluate*
  ## entry points below may call it.
  ##
  ## `identityBound` is the read-path identity precondition (contract §17.1):
  ## `true` on the execution path, where the state was produced under the
  ## context measured now, and `revalidateRestoredStateIdentity(...).established`
  ## on the read path. It gates the PASS branches ONLY — rules 1-6 and 10 are
  ## facts of the run itself and stay reachable whatever the binding is, so an
  ## unbound state can never obtain a MORE favourable verdict by hiding them.
  result = RunOutcome(
    planComplete: accounting.runOutcome.planComplete,
    executionComplete: accounting.runOutcome.executionComplete,
    verificationComplete: accounting.runOutcome.verificationComplete
  )
  # Verdict precedence (decision tree, contract §17 — FAIL 축소: FAIL is
  # exclusively proof-level; everything else classifies down/inconclusive).
  if accounting.proofFailedCount >= 1:
    result.verdict = vrFail
  elif accounting.timeoutUnsatCount >= 1:
    # timeout rows are a raw fact — VDA interprets them as INCONCLUSIVE,
    # never as FAIL (the accounting aggregation is left untouched).
    result.verdict = vrInconclusive
  elif accounting.pendingCount >= 1:
    if accounting.attemptedCount == 0 and factGateActive:
      result.verdict = vrBlocked
    else:
      # attempted-but-unresolved (not_verifiable/vacuous/skipped/…) or a
      # reuse row whose REUSED basis was not established → INCONCLUSIVE;
      # VDA must not decide PASS on it (fail-closed).
      result.verdict = vrInconclusive
  elif accounting.contestedCount >= 1:
    # report-consistency failure (REQUIRED ∧ runtime no_obligation) — never
    # satisfying, never a proof-level failure → INCONCLUSIVE.
    result.verdict = vrInconclusive
  elif accounting.unresolvedDecisionCount >= 1:
    # obligation enumeration incomplete → PASS impossible.
    result.verdict = vrInconclusive
  elif identityBound and accounting.requiredCount >= 1:
    if accounting.satisfiedByFresh >= 1:
      result.verdict = vrPass
      result.basis = rbProven
    elif accounting.satisfiedByReused >= 1:
      # REUSED is a provenance/basis, not a decision-maker: the per-row
      # 5-condition re-verification (reducer) established the basis for every
      # reuse row (rejected rows are PENDING and would have hit the branch
      # above); VDA decides the final PASS here.
      result.verdict = vrPass
      result.basis = rbReused
      result.reusedConditionsMet = @[
        "subjectFingerprint", "executionBundleFingerprint",
        "executionConfigDigest", "artifactContentDigest", "toolchainIdentity"
      ]
    else:
      # unreachable under the reducer invariants (requiredCount ==
      # satisfied+unsatisfied+pending) — fail-closed.
      result.verdict = vrInconclusive
  elif identityBound and accounting.units.len >= 1 and noObligation.universeEnumerated:
    # PASS(NO_OBLIGATION): non-empty universe ∧ every unit NOT_REQUIRED ∧
    # enumeration completed (NoObligationProvenance).
    result.verdict = vrPass
    result.basis = rbNoObligation
  else:
    # empty universe, absent enumeration, or an UNBOUND identity — "0이라서
    # PASS" 금지, and an unbound state may not assert a PASS at all (§17.1).
    result.verdict = vrInconclusive

proc evaluateRunOutcome*(
  accounting: RunAccounting;
  noObligation: NoObligationProvenance;
  factGateActive: bool
): RunOutcome {.raises: [].} =
  ## Run-level decision boundary (INV-X1 inversion): the ONLY authority that
  ## may produce a run-level PASS. Input = raw accounting state + universe
  ## enumeration provenance + fact-gate signal. Execution path: the state was
  ## produced under the context measured now, so the identity precondition of
  ## §17.1 holds by construction.
  makeRunOutcomeVerdict(accounting, noObligation, factGateActive, true)

# ---------------------------------------------------------------------------
# Read path — restored state (contract §15.3 + §17.1)
# ---------------------------------------------------------------------------
## A persisted run STATE is the other carrier of a verdict: a different process
## reads it back, possibly from a cache that outlived the run that produced it.
## The re-validation itself (`revalidateRestoredStateIdentity`) and the demotion
## (`demoteRestoredReusedUnits`) are pure projections in run_accounting; the
## DECISION they feed belongs here, because this module is the sole run-verdict
## writer (INV-X1 inversion, §9). No other code path may write
## verdict/basis/gateVerdict.
##
## The identity precondition (§17.1) gates the PASS branches ONLY:
##   - rules 1-6 and 10 are unchanged. A proof-level FAIL, a timeout, a PENDING
##     unit, a contested or unresolved enumeration are facts of the run itself
##     and are not identity-dependent — an unbound envelope must never be able
##     to obtain a MORE favourable verdict by hiding them.
##   - the PASS rules (7 PROVEN / 8 REUSED / 9 NO_OBLIGATION) additionally
##     require the state to be bound to the current execution identity. An
##     unbound state cannot assert a PASS: the satisfaction it records was
##     established under an identity that is no longer provably current, which
##     is §15.0's "a cache is acceleration, never evidence and never a verdict
##     input" applied to the state as a whole.
##
## The case that fixes this: a FRESH-ONLY state (demoted == 0 — nothing was
## REUSED, so the demotion is silent) whose envelope cannot be bound reads as
## INCONCLUSIVE, never PASS. `demoted == 0` is a statement about the rows, not
## about the identity: §17 rule 7 (`requiredCount ≥ 1 ∧ fresh ≥ 1 → PASS
## basis PROVEN`) is decided on BOUND state, and the unbound reading of that
## same state is the fail-closed `otherwise` branch. BLOCKED remains reachable
## on its own §17 rule 3 terms (PENDING ∧ nothing attempted ∧ fact-gate), not
## as a synonym for "the envelope did not bind".

func restoredStateFactGateActive(stateJson: JsonNode): bool {.raises: [].} =
  ## Read-path fact-gate signal (§17 rule 3): the run recorded blocked nodes.
  ## There is no live gate process on the read path — the recorded
  ## blockedNodes ARE the record that a fact-gate fired.
  let blocked = stateJson{"blockedNodes"}
  not blocked.isNil and blocked.kind == JArray and blocked.len > 0

func evaluateRestoredStateRunOutcome*(
  stateJson: JsonNode;
  reval: RestoredStateRevalidation
): JsonNode {.raises: [].} =
  ## Restored-state read path — the §17 decision, owned by this module.
  ## Mutates and returns `stateJson`: demotes the REUSED satisfactions the
  ## re-validation could not establish, then writes the authority-decided
  ## `runOutcome` block (raw completeness projections + verdict/basis/
  ## gateVerdict) beside the re-validation telemetry.
  if stateJson.isNil or stateJson.kind != JObject: return stateJson
  let demoted = demoteRestoredReusedUnits(stateJson, reval)
  let outcome = makeRunOutcomeVerdict(
    runAccountingFromJson(stateJson{"runAccounting"}),
    NoObligationProvenance(universeEnumerated: false, source: restoredStateSource),
    restoredStateFactGateActive(stateJson),
    reval.established)
  var reasons = newJArray()
  for reason in reval.reasons: reasons.add(%reason)
  let outcomeJson = runOutcomeToJson(outcome)
  outcomeJson["readTimeRevalidation"] = %*{
    "established": reval.established,
    "demotedReusedUnits": demoted,
    "reasons": reasons
  }
  stateJson["runOutcome"] = outcomeJson
  result = stateJson

{.pop.}