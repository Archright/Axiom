import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/axiom_pragmas

import core/types/verification_tier
import core/trusted/semantic_profile
import core/trusted/specification_artifact
import core/trusted/assurance_profile
import core/trusted/dependency_snapshot
import core/trusted/solver_invocation

## Evidence Calculus — Canonical Evidence Model (Phase 1).
##
## Evidence is treated as TYPED facts (value + provenance), NOT a flat boolean
## blob. Boolean flags are DERIVED; the facts carry provenance.
##
## Invariants:
##   I1 status != authority (evidence governs)
##   I2 tier = derive(evidence, policy) only
##   I3 VKD ⊆ derive(evidence), status-only admission forbidden
##   I6 unsat != proofChecked (solver result is distinct from a proof)
##
## FUTURE assurance extension points (P3-P7):
##   semanticFoundation*, proofArtifact*, replay* fields on EvidenceFact
##   are ABSENT by default (empty strings / default objects). They are
##   purely declarative extension points — filling them later does not
##   change current assurance levels, which remain honest as-is.

type
  TranslationEvidence* = object
    sourceHash*: string
    irHash*: string
    translationVersion*: string
    theoremId*: string
    proofArtifactDigest*: string
    checker*: string

  SolverEvidence* = object
    smtHash*: string
    solverIdentity*: string
    proofFormat*: string
    proofDigest*: string
    replayResult*: string   ## "" | "ACCEPTED" | "REJECTED"

  SemanticFoundation* = object
    irSemanticsVersion*: string   ## "" = absent (no formal IR semantics yet)
    translationTheorem*: string   ## "" = absent (no Nim->IR soundness theorem yet)
    qfBvSoundnessTheorem*: string ## "" = absent (no IR->QF_BV soundness theorem yet)

  ProofArtifactInfo* = object
    format*: string    ## "" = absent
    digest*: string    ## "" = absent
    checker*: string   ## "" = absent

  ReplayEvidence* = object
    checker*: string       ## "" = absent
    artifactDigest*: string## "" = absent
    result*: string        ## "" = absent, "valid" = independently replayed

  EvidenceFact* = object
    specOrigin*: string
    solverProved*: bool
    translationProved*: bool
    specProved*: bool
    replayProved*: bool
    kernelScoped*: bool
    provenanceComplete*: bool
    translation*: TranslationEvidence
    solver*: SolverEvidence
    semanticFoundation*: SemanticFoundation   ## absent by default (P3-P7 track)
    proofArtifact*: ProofArtifactInfo         ## absent by default (P5 track)
    replay*: ReplayEvidence                   ## absent by default (P6 track)

  EvidenceBundle* = object
    facts*: EvidenceFact
    certificateEvidence*: CertificateEvidence   ## reuse P0 type (the canonical base)
    specificationArtifact*: SpecificationArtifact ## Phase-2 capture (internal-only, never serialized to certs)
    dependencySnapshot*: DependencySnapshot      ## Phase-2 capture (no policy interpretation)
    solverInvocation*: SolverInvocation          ## Phase-6 T0 replay identity (canonical inputs + solver identity/options)

  AssurancePolicy* = enum
    apV1   ## assurance policy version 1

func toEvidenceBundle*(ev: CertificateEvidence): EvidenceBundle {.raises: [].} =
  ## Promote P0 CertificateEvidence into an EvidenceBundle.
  ## Seeds solverProved from z3Passed and translationProved from leanVerified.
  ## provenanceComplete is false initially — provenance is NOT established yet.
  result.certificateEvidence = ev
  result.facts.solverProved = ev.z3Passed
  result.facts.translationProved = ev.leanVerified
  result.facts.provenanceComplete = false

func deriveAssurance*(bundle: EvidenceBundle; policy: AssurancePolicy): int {.raises: [], axiomDecision(id = "DECISION-0631", reason = "Derive assurance tier from evidence bundle and policy", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Return an assurance tier 0..3 as a PURE derived value from evidence + policy.
  ## Policy v1 (apV1) — conservative: most current bundles derive to tier 0.
  if policy != apV1:
    return 0
  if bundle.facts.replayProved and bundle.facts.kernelScoped and bundle.facts.provenanceComplete and bundle.facts.specProved and bundle.facts.translationProved and bundle.facts.solverProved:
    return 3
  if bundle.facts.kernelScoped and bundle.facts.provenanceComplete and bundle.facts.specProved and bundle.facts.translationProved and bundle.facts.solverProved:
    return 2
  if bundle.facts.specProved and bundle.facts.translationProved and bundle.facts.solverProved:
    return 1
  if bundle.certificateEvidence.z3Passed or bundle.certificateEvidence.leanVerified:
    return 0
  0

func admissibleEvidence*(bundle: EvidenceBundle): bool {.raises: [].} =
  ## VKD evidence predicate (I3, I6). Requires GENUINE established evidence:
  ## BOTH solver proof AND translation (Lean) established. A mere recorded
  ## solver result (z3-only) or a lone Lean artifact is NOT admissible
  ## (recorded != proof, I6). This is intentionally conservative and will be
  ## MONOTONICALLY TIGHTENED in later phases (specProved, then replayProved).
  bundle.facts.solverProved and bundle.facts.translationProved

{.pop.}