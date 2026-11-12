import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import core/trusted/candidate_evidence
import core/contracts/z3_extraction

const AllowedSafeProducers* = ["EvidenceValidator.validate"]

func assertEvidenceAuthority*(producer: string): bool {.raises: [].} =
  result = producer in AllowedSafeProducers

func proofResultToCandidateEvidence*(r: ProofResult; z3Path: string): CandidateEvidence {.raises: [].} =
  let provenance = "solver:" & z3Path & ":" & $r.status
  result = candidateEvidence(cesSolver, @[], provenance, "")

{.pop.}