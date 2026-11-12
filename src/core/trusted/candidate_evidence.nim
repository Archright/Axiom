import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/options
import std/sequtils
import std/tables
import core/trusted/axiom_pragmas

type
  CandidateEvidenceSource* {.axiomDecision(
    id = "DECISION-0301",
    reason = "Enumeration of evidence provenance sources for CandidateEvidence (C18)",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v32").} = enum
    cesSolver
    cesSynthesizer
    cesUser
    cesImported

  CandidateEvidence* {.axiomDecision(
    id = "DECISION-0302",
    reason = "Contract C18: backend-neutral candidate evidence type with RelationId keys per C19; carries SAT model string when source is cesSolver (P4)",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v32").} = object
    source*: CandidateEvidenceSource
    invariants*: OrderedTable[string, string]
    provenance*: string
    fingerprint*: string
    model*: string

func isEmpty*(ce: CandidateEvidence): bool {.axiomDecision(
    id = "DECISION-0303",
    reason = "C20: missing evidence (no invariants AND no solver model) yields Inconclusive; empty check is the gate predicate. S6: the SAT-model leg is evidence of a counterexample (DECISION-0302 carries it for cesSolver) — a model-carrying candidate is NOT empty, otherwise the P4 cvConfirmed promotion would be unreachable for every BMC SAT",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v32"), raises: [].} =
  ce.invariants.len == 0 and ce.model.len == 0

func candidateEvidence*(source: CandidateEvidenceSource; invariants: openArray[(string, string)]; provenance, fingerprint: string; model: string = ""): CandidateEvidence {.axiomDecision(
     id = "DECISION-0304",
     reason = "Convenient constructor for CandidateEvidence from openArray of RelationId->Formula pairs (C19); carries SAT model string for cesSolver when model is provided",
     adr = "docs/spec/cfg_contract_specification.md",
     introduced = "v32"), raises: [].} =
   result = CandidateEvidence(source: source, provenance: provenance, fingerprint: fingerprint, model: model)
   for (k, v) in invariants.items:
     result.invariants[k] = v

func isSolverProduced*(ce: CandidateEvidence): bool {.axiomDecision(
    id = "DECISION-0305",
    reason = "Check whether candidate evidence originates from the solver (cesSolver) per C18",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v32"), raises: [].} =
  ce.source == cesSolver

{.pop.}