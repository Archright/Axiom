import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## Component F — Pure Fingerprint Engine
##
## Deterministic fingerprinting, ASI computation, and invariant refinement
## for the semantic verification pipeline. Zero I/O.

{.push raises: [].}
{.push noSideEffect.}
import std/options
import std/strutils

import core/logic/refinement_string
import core/types/asi_types
import core/utils/text_utils
import core/types/pipeline_core_types
export pipeline_core_types
import core/logic/universal_translation_types
import core/telemetry/metrics

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func hitFingerprintSeed*(ah: AnnotatedHit): string {.raises: [], noSideEffect.} =
  let payloadSeed = case ah.hit.kind
  of vkBufferOverflow: ah.hit.boInfo.getFingerprintSeed()
  of vkNullPointerDereference: ah.hit.npInfo.getFingerprintSeed()
  of vkIntegerOverflowUnderflow: ah.hit.ioInfo.getFingerprintSeed()
  of vkGhostUpdate: ah.hit.guInfo.getFingerprintSeed()
  of vkDeadlockRaceCondition: ah.hit.dlInfo.getFingerprintSeed()
  payloadSeed & "|" & $ah.sat & "|" & ah.violatedProperty & "|" &
    ah.counterExampleInput & "|" & ah.remediation

# @axiom-hint: lean="depth >= 0" smt="(assert (and (>= depth 0)))"
func scanFingerprintSeed(scan: NegativeInvariantScan): string {.raises: [], noSideEffect.} =
  var parts = newSeq[string](0)
  parts.add($scan.hasVulnerability)
  for hit in scan.hits:
    parts.add(hitFingerprintSeed(hit))
  parts.join("\n")

## Compute Unified Proof Fingerprints.
# @axiom-hint: lean="verificationVerdict.length ≥ 0 ∧ activeInvariant.length ≥ 0 ∧ refinedInvariant.length ≥ 0" smt="(assert (and (>= (str.len verificationVerdict) 0) (>= (str.len activeInvariant) 0) (>= (str.len refinedInvariant) 0)))"
func computeUnifiedProofFingerprints*(
  translation: UniversalTranslation;
  inferred: LeanSpecInference;
  verificationVerdict: string;
  activeInvariant: string;
  refinedInvariant: string;
  finalScan: NegativeInvariantScan
): UnifiedProofFingerprints {.raises: [], noSideEffect.} =
  let smtFingerprint = computeSourceFingerprint(translation.smt2)
  let leanFingerprint = computeSourceFingerprint(inferred.theoremSource)
  let certFingerprint = computeSourceFingerprint(
    verificationVerdict & "\n" &
    activeInvariant & "\n" &
    refinedInvariant & "\n" &
    scanFingerprintSeed(finalScan)
  )
  UnifiedProofFingerprints(
    smt: smtFingerprint,
    lean: leanFingerprint,
    cert: certFingerprint,
    unified: computeSourceFingerprint(
      smtFingerprint & "\n" & leanFingerprint & "\n" & certFingerprint
    )
  )

## Healing State Fingerprint.
# @axiom-hint: lean="sourceCode.length ≥ 0 ∧ activeInvariant.length ≥ 0" smt="(assert (and (>= (str.len sourceCode) 0) (>= (str.len activeInvariant) 0)))"
func healingStateFingerprint*(sourceCode: string; activeInvariant: string): string {.raises: [], noSideEffect.} =
  computeSourceFingerprint(sourceCode & "\n" & activeInvariant)

## Compute Asi Fixed4.
func computeAsiFixed4*(finalScan: NegativeInvariantScan): string =
  if finalScan.logicModelConflicted:
    return asString(metrics.exportAsiFixed4(initAsiRatio(0.0).get(defaultAsiRatio())))
  if not finalScan.hasVulnerability:
    return asString(metrics.exportAsiFixed4(initAsiRatio(1.0).get(defaultAsiRatio())))
  let totalKinds = 5.0
  let resolved = totalKinds - min(totalKinds, finalScan.hits.len.float)
  let value = resolved / totalKinds
  return asString(metrics.exportAsiFixed4(initAsiRatio(value).get(defaultAsiRatio())))

func computeAsiFixed4*(finalScan: NegativeInvariantScan; verdict: string): string =
  if verdict == "verified" or verdict == "proven_by_induction":
    return asString(metrics.exportAsiFixed4(initAsiRatio(1.0).get(defaultAsiRatio())))
  computeAsiFixed4(finalScan)

# @axiom-hint: lean="kind.length ≥ 0 ∧ ast_parse_failed_isolated" smt="(assert (and (>= (str.len kind) 0) ast_parse_failed_isolated))"
func hitPriority*(kind: VulnerabilityKind): int {.raises: [], noSideEffect.} =
  case kind
  of vkGhostUpdate: 0
  of vkBufferOverflow: 1
  of vkNullPointerDereference: 2
  of vkIntegerOverflowUnderflow: 3
  of vkDeadlockRaceCondition: 4

## Select Evolution Hit.
# @axiom-hint: lean="best = hit ∧ (best ≥ 0)" smt="(assert (and (= best hit) (>= best 0)))"
func selectEvolutionHit*(initial: NegativeInvariantScan): Option[AnnotatedHit] {.raises: [], noSideEffect.} =
  if initial.hits.len == 0:
    return none(AnnotatedHit)
  var best = initial.hits[0]
  for hit in initial.hits:
    if hitPriority(hit.hit.kind) < hitPriority(best.hit.kind):
      best = hit
  some(best)

## Build Refined Invariant.
# @axiom-hint: lean="invariant" smt="(assert (and invariant))"
func buildRefinedInvariant*(
  translation: UniversalTranslation;
  sourceCode: string;
  hit: AnnotatedHit
): string =
  case hit.hit.kind
  of vkGhostUpdate:
    "next.version >= state.version ∧ (next.payload ≠ state.payload -> next.version > state.version) ∧ (next.version = state.version -> next.payload = state.payload)"
  of vkBufferOverflow:
    for invariant in translation.transitionInvariants:
      let invTokens = tokenizeLowered(invariant)
      if "base" in invTokens and "idx" in invTokens:
        return invariant
    for invariant in translation.transitionInvariants:
      let invTokens = tokenizeLowered(invariant)
      if "idx" in invTokens:
        return invariant
    "0 <= idx ∧ idx < length ∧ base <= base + idx ∧ base + idx < base + length"
  of vkNullPointerDereference:
    "ptr != nil"
  of vkIntegerOverflowUnderflow:
    let sourceTokens = tokenizeLowered(sourceCode)
    if "balance" in sourceTokens:
      for inv in translation.transitionInvariants:
        let invTokens = tokenizeLowered(inv)
        if "next" in invTokens and "balance" in invTokens and "<=" in invTokens:
          return "0 <= amount ∧ amount <= state.balance ∧ next.balance <= state.balance"
      return "0 <= amount ∧ amount <= state.balance"
    else:
      "value stays within declared arithmetic bounds"
  of vkDeadlockRaceCondition:
    "shared_state_access -> lockHeld = true"


## Infer Verification Verdict.
func inferVerificationVerdict*(finalScan: NegativeInvariantScan): string =
  if finalScan.logicModelConflicted:
    return "critical_failure"
  if finalScan.hasVulnerability:
    return "refuted_by_counterexample"
  "proven_by_induction"

{.pop.}

{.pop.}
{.pop.}
{.pop.}
