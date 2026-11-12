import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

import checksums/sha2
import core/trusted/axiom_pragmas

## SSOT for deterministic CAS content keys used across the verification
## pipeline.  Both `cross_validation` and `ir_pipeline_runner` import this
## module to compute a SHA-256 content hash keyed by the verification
## schema version, ensuring cache identity is stable and single-sourced.

const VERIFICATION_SCHEMA_VERSION* = 2
  ## Increment when the CAS key computation semantics change (e.g. hash
  ## algorithm, version suffix format), forcing cache invalidation.

const EvidenceIdContractVersion* = "evidence-id-contract.v1"
  ## The evidenceId contract generation — the single source of truth shared
  ## by the lane's independent checker (tools/ci/check_evidence_id_contract.nim)
  ## and the Judgment CAS reusable-PASS identity (verification/judgment_cas.nim).
  ## Bump when the normative evidenceId formula contract changes (component
  ## set, separators, strict extension rule); a bump re-keys reusable-PASS
  ## eligibility so records of the old contract are never reusable.

func computeDeterministicCasKey*(irContentHash: string): string {.inline, raises: [], axiomDecision(
  id = "DECISION-0611",
  reason = "Shared CAS content key computation extracted from cross_validation and ir_pipeline_runner into L0 domain module; eliminates duplication and ensures single source of truth for cache identity",
  adr = "docs/spec/verification_density.md",
  introduced = "v38"
).} =
  result = $secureHash(Sha_256, irContentHash & ":v" & $VERIFICATION_SCHEMA_VERSION)

{.pop.}