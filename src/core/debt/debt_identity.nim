## src/core/debt/debt_identity.nim — Deterministic candidate identity.
##
## Provides content-addressable identity computation for debt observations.
## candidateId is rule-independent and snapshot-independent (per feedback #2).

import core/trusted/layer_declaration
axiomLayer "domain"

import checksums/sha2
import std/algorithm
import core/types/debt_types

# ---------------------------------------------------------------------------
# Identity computation
# ---------------------------------------------------------------------------

func computeCandidateId*(subject: string; semanticIdentity: string): string {.raises: [].} =
  ## Deterministic candidate identity: sha256("candidate:" & observationIdentity(subject, semanticIdentity)).
  ## Rule-independent, snapshot-independent — no line number, no rule hash, no version.
  "sha256:" & $Sha_256.secureHash("candidate:" & observationIdentity(subject, semanticIdentity))

func fromObservation*(obs: DebtObservation): string {.raises: [].} =
  ## Derive candidateId from a DebtObservation.
  ## Delegates to computeCandidateId using obs.subject and obs.semanticIdentity.
  computeCandidateId(obs.subject, obs.semanticIdentity)

# ---------------------------------------------------------------------------
# Universe digest
# ---------------------------------------------------------------------------

func computeUniverseDigest*(events: openArray[ClassificationEvent]; ruleSetHash, taxonomyVersion: string): string {.raises: [].} =
  ## Deterministic universe digest: sha256 of sorted classification events
  ## prefixed by ruleSetHash and taxonomyVersion.
  ## Excludes recordedAt (execution-time) to ensure same repo + same rule → same digest.
  ## Sort key: (candidateId, eventId) for stable ordering across runs.
  var sortedEvents = @events
  sortedEvents.sort(proc(a, b: ClassificationEvent): int =
    result = cmp(a.candidateId, b.candidateId)
    if result == 0: result = cmp(a.eventId, b.eventId)
  )
  var payload = ruleSetHash & taxonomyVersion
  for ev in sortedEvents:
    payload.add("|")
    payload.add(ev.candidateId)
    payload.add("|")
    payload.add(debtClassToStr(ev.result))
    payload.add("|")
    payload.add(ev.eventId)
  "sha256:" & $Sha_256.secureHash(payload)
