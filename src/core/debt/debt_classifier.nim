## src/core/debt/debt_classifier.nim — Pure Debt Classification Engine
##
## Deterministic, I/O-free classification of DebtObservation into DebtClass.
## Uses event sourcing (append-only ClassificationEvent) — never overwrites.
## The latest valid event per candidateId constitutes the current view.
##
## Public API:
##   classifyDebt — classify a single observation, producing a new ClassificationEvent
##   latestClassification — retrieve the most recent valid event for a candidate
##   currentView — retrieve the latest event for every distinct candidate lineage

import core/types/debt_types
import std/[options, sets, strutils]
import checksums/sha2

# ---------------------------------------------------------------------------
# classifyDebt
# ---------------------------------------------------------------------------

func classifyDebt*(
    obs: DebtObservation;
    ruleSetHash, classifierVersion, taxonomyVersion, repositorySnapshot, recordedAt: string;
    prev: Option[ClassificationEvent] = none(ClassificationEvent)
): ClassificationEvent {.raises: [].} =
  ## Classify a DebtObservation into a DebtClass deterministically.
  ##
  ## Classification rules (pure, no I/O, based solely on obs.kind and obs.payload):
  ##
  ##   okSourceMarker + payload contains "RESOLVED"/"FIXED"  → dcResolved
  ##   okSourceMarker + payload contains "STALE"             → dcStale
  ##   okSourceMarker + payload contains "QUIRK"             → dcQuirk
  ##   okSourceMarker (fallback/default)                     → dcOpenDebt
  ##   okMetric                                              → dcBudgetDrift
  ##   okGateDeclaration / okGateExecution                   → dcOpenDebt
  ##   okCertificate / okProofArtifact                       → dcResolved
  ##   okDocumentClaim / okExternalClaim                     → dcUnverified
  ##   okAstPattern / okCfgPattern                           → dcOpenDebt
  ##   all other kinds                                       → dcUnverified
  ##
  ## eventId  = sha256(candidateId | classifierVersion | ruleSetHash | parentEventId)
  ## parentEventId = prev.eventId when prev is some, else ""
  ## recordedAt = injected by caller (pure func cannot obtain time itself).

  let parentEventId = if prev.isSome: prev.get().eventId else: ""

  # Determine DebtClass from observation kind and payload.
  let dc: DebtClass =
    case obs.kind
    of okSourceMarker:
      let p = obs.payload.toLowerAscii()
      if p.contains("resolved") or p.contains("fixed"):
        dcResolved
      elif p.contains("stale"):
        dcStale
      elif p.contains("quirk"):
        dcQuirk
      else:
        dcOpenDebt                       # fallback for okSourceMarker
    of okMetric:
      dcBudgetDrift
    of okGateDeclaration, okGateExecution:
      dcOpenDebt
    of okCertificate, okProofArtifact:
      dcResolved
    of okDocumentClaim, okExternalClaim:
      dcUnverified
    of okAstPattern, okCfgPattern:
      dcOpenDebt
    else:
      dcUnverified

  # candidateId = H(subject ∥ semanticIdentity) per debt_types contract.
  let candidateId = $secureHash(Sha_256, observationIdentity(obs.subject, obs.semanticIdentity))

  # Build eventId: sha256(candidateId | classifierVersion | ruleSetHash | parentEventId)
  let raw = candidateId & "|" & classifierVersion & "|" & ruleSetHash & "|" & parentEventId
  let eventId = $secureHash(Sha_256, raw)

  ClassificationEvent(
    eventId: eventId,
    candidateId: candidateId,
    classifierVersion: classifierVersion,
    ruleSetHash: ruleSetHash,
    taxonomyVersion: taxonomyVersion,
    result: dc,
    evidenceIds: @[],
    parentEventId: parentEventId,
    recordedAt: recordedAt,
    repositorySnapshot: repositorySnapshot,
  )

# ---------------------------------------------------------------------------
# latestClassification
# ---------------------------------------------------------------------------

func latestClassification*(
    events: openArray[ClassificationEvent];
    candidateId: string
): Option[ClassificationEvent] {.raises: [].} =
  ## Return the most recent valid ClassificationEvent for the given candidateId.
  ## "Most recent" = greatest recordedAt (ISO-8601 lexicographic order).
  ## If multiple events share the same recordedAt, the last one in the array wins.
  ## Returns none if no matching event exists.

  var best: Option[ClassificationEvent] = none(ClassificationEvent)
  for ev in events:
    if ev.candidateId != candidateId:
      continue
    if best.isNone:
      best = some(ev)
    elif ev.recordedAt >= best.get().recordedAt:
      best = some(ev)
  best

# ---------------------------------------------------------------------------
# currentView
# ---------------------------------------------------------------------------

func currentView*(events: openArray[ClassificationEvent]): seq[ClassificationEvent] {.raises: [].} =
  ## Return the latest ClassificationEvent for each distinct candidateId lineage.
  ## Preserves the first-encountered order of candidateIds.

  var seen: HashSet[string]
  var view: seq[ClassificationEvent]
  for ev in events:
    if ev.candidateId in seen:
      continue
    seen.incl(ev.candidateId)
    let latest = latestClassification(events, ev.candidateId)
    if latest.isSome:
      view.add(latest.get())
  view

# ---------------------------------------------------------------------------
# Pinned rule set identity (replaces the legacy "classifier-dev" hardcode).
# ruleSetHash is a deterministic digest of the actual rule text, so changing a
# rule changes the hash and every classification event/provenance referencing
# it stays distinguishable (rule-pinning + reproducibility invariant I5).
# ---------------------------------------------------------------------------

const DebtClassifierRulesCanonical* = """classifier-v1 rules
okSourceMarker+payload contains RESOLVED/FIXED -> dcResolved
okSourceMarker+payload contains STALE           -> dcStale
okSourceMarker+payload contains QUIRK           -> dcQuirk
okSourceMarker (default)                        -> dcOpenDebt
okMetric                                        -> dcBudgetDrift
okGateDeclaration/okGateExecution               -> dcOpenDebt
okCertificate/okProofArtifact                   -> dcResolved
okDocumentClaim/okExternalClaim                 -> dcUnverified
okAstPattern/okCfgPattern                       -> dcOpenDebt
other                                           -> dcUnverified"""

const DebtClassifierVersion* = "classifier-v1"
const DebtTaxonomyVersion* = "taxonomy-v1"

func debtRuleSetHash*(): string {.raises: [].} =
  ## Deterministic hash over the canonical rule text. Imports sha256Ref from
  ## debt_types (the typed identity substrate) for a single hash form.
  sha256Ref("classifier-rules:", DebtClassifierRulesCanonical)
