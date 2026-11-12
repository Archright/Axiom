import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Canonical Admissibility Decision Pipeline (P0)
##
## Single source of truth for whether a candidate may enter proof execution.
## Mirrors the 3-state model: statically-admissible, statically-ineligible, or
## defer-to-runtime. It wraps the existing static signal (`classifyFunction`) and
## the compile-time `bmcSkippable` field, so selector and solver no longer each
## maintain a private, drifting eligibility notion.
##
## Design note (rationale):
##   * `classifyFunction` (ax_classify.nim) already computes static tier + loop
##     bound for a deserialized IRFuncDef. We do NOT duplicate that logic.
##   * `ValidatedIrEntry.entry.bmcSkippable` is the compile-time semantic twin of
##     the string/float exclusion. We do NOT re-derive it here.
##   * A candidate is DEFER_TO_RUNTIME when static analysis cannot fully
##     discharge it (e.g. structural bodies, unresolved loops, or IR encoding
##     failures that only appear at encode time, like normalizedEntries). This is
##     a legal, defensive fallback — NOT an invariant violation.

import core/trusted/axiom_pragmas
import core/trusted/axiom_ir
import std/[options, strutils, tables]
import verification/ax_classify

type
  AdmissibilityDecision* = enum
    ADMISSIBLE       ## Statically known executable-proof candidate.
    INELIGIBLE       ## Statically known unsupported — excluded before ranking/budget.
    DEFER_TO_RUNTIME ## Static cannot finalize → runtime admission decides.

  IneligibilityReason* = enum
    ireNone
    ireUnsupportedType     ## string / float — not representable in QF_BV.
    ireUnboundedLoop       ## loop without a sound, <= depth static bound.
    ireUnsupportedTheory   ## body uses a theory outside QF_BV/CHC support.

  AdmissibilityOutcome* = object
    decision*: AdmissibilityDecision
    reason*: IneligibilityReason
    detail*: string

func toIneligibilityReason*(tier: VerificationTier; reason: string): IneligibilityReason {.raises: [].} =
  ## Map a static classification to a canonical ineligibility reason.
  ## ADMISSIBLE is never produced here — only reasons for the negative branch.
  case tier
  of vtNonDecidable:
    if reason.contains("string") or reason.contains("float"): ireUnsupportedType
    else: ireUnsupportedTheory
  of vtStructural:
    if reason.contains("recursive"): ireUnsupportedTheory
    else: ireUnboundedLoop
  of vtSmtNative:
    ireNone

func assessAdmissibility*(entry: RuntimeAxiomEntry; funcDef: IRFuncDef): AdmissibilityOutcome {.axiomDecision(
  id = "DECISION-0627",
  reason = "Canonical 3-state admissibility decision (ADMISSIBLE / INELIGIBLE / DEFER_TO_RUNTIME) so candidate selection and proof execution share one eligibility contract instead of duplicating drift-prone private logic",
  adr = "docs/spec/ir_pipeline_integration.md",
  introduced = "v39").} =
  ## 3-state admissibility contract. Takes the compile-time registry entry and
  ## the cached deserialization (ValidatedIrEntry decomposes into these two),
  ## keeping this module import-safe (avoids a cycle back into the pipeline).
  ##
  ##   1. Compile-time `bmcSkippable` (string/float in QF_BV) → INELIGIBLE.
  ##   2. `classifyFunction` vtNonDecidable → INELIGIBLE.
  ##   3. `classifyFunction` vtStructural with an UNSOUND/unresolved loop bound →
  ##      INELIGIBLE (unbounded loop cannot be faithfully encoded).
  ##   4. vtSmtNative → ADMISSIBLE (statically executable, simple bitvec/bool).
  ##   5. Structural-with-sound-bound / other → DEFER_TO_RUNTIME (the runtime
  ##      admission/encode step stays authoritative; a static-sounding candidate
  ##      like normalizedEntries is resolved there, not over-claimed statically).
  ##
  ## Only fully-static *negative* proofs earn INELIGIBLE, and only fully-static
  ## simple bodies earn ADMISSIBLE. Everything else is honest runtime deferral —
  ## preserving the P6 fallback: STATIC_INELIGIBLE and RUNTIME_INELIGIBLE both
  ## reject before proof attempt; only a post-execution theory skip is an
  ## invariant violation.
  if entry.bmcSkippable:
    return AdmissibilityOutcome(decision: INELIGIBLE, reason: ireUnsupportedType,
      detail: "compile-time bmcSkippable (string/float not QF_BV-representable)")
  let tierInfo = classifyFunction(funcDef)
  case tierInfo.tier
  of vtNonDecidable:
    return AdmissibilityOutcome(decision: INELIGIBLE,
      reason: toIneligibilityReason(tierInfo.tier, tierInfo.reason),
      detail: tierInfo.reason)
  of vtStructural:
    if tierInfo.loopBound.isNone and bodyHasLoop(funcDef.body):
      return AdmissibilityOutcome(decision: INELIGIBLE,
        reason: ireUnboundedLoop,
        detail: "loop bound unresolved/unsound for faithful SMT unroll")
    return AdmissibilityOutcome(decision: DEFER_TO_RUNTIME,
      reason: ireNone, detail: "structural body — runtime admission decides")
  of vtSmtNative:
    return AdmissibilityOutcome(decision: ADMISSIBLE,
      reason: ireNone, detail: "simple SMT-native body — statically executable")

func isSelectionEligible*(o: AdmissibilityOutcome): bool {.raises: [].} =
  ## True when the candidate may proceed to (ranked) selection. Both ADMISSIBLE
  ## and DEFER_TO_RUNTIME are eligible — only INELIGIBLE is filtered. This is the
  ## P1 contract: static-negative ones consume zero budget/rank; the static-unsure
  ## ones still surface to runtime admission where they are conclusively resolved.
  o.decision != INELIGIBLE

proc isFunctionTextuallyIneligible*(funcName: string): bool {.raises: [].} =
  ## Frontier-level cheap gate: given a bare function name (with any `*` export
  ## marker), look it up in the compile-time registry and return whether it is
  ## statically INELIGIBLE. Unknown names (no IR registry entry) are treated as
  ## NOT ineligible so frontiers are never artificially starved by a name we
  ## cannot resolve — the IR pipeline itself reports the skip honestly there.
  ##
  ## Uses a linear scan of `runtimeAxiomRegistry` (a seq) instead of the
  ## `registryLookup` Table to keep this effect-free under `{raises: []}` — the
  ## table indexing pattern would surface a KeyError and the copy-effect here.
  ## Used by `ax prove` to filter the verified frontier *before* payload
  ## construction, so an INELIGIBLE candidate (string/float, non-decidable tier,
  ## unbounded loop) does not consume the `--limit N` proof-attempt budget.
  var bare = funcName
  if bare.endsWith("*"):
    bare = bare[0..^2]
  for entry in runtimeAxiomRegistry:
    if entry.name != bare or entry.irSerialized.len == 0:
      continue
    let funcDef = deserializeIRFuncDef(entry.irSerialized)
    if funcDef.name.len > 0:
      return assessAdmissibility(entry, funcDef).decision == INELIGIBLE
  false

{.pop.}