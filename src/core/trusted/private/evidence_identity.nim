import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/trusted/axiom_pragmas
import core/trusted/fingerprint_generator

## C19 — Evidence Identity Layer.
##
## Types for certificate and evidence identity in the verification
## evidence chain. The old verification_identity EvidenceIdentity
## (candidateEvidenceId + fingerprint) is DEAD and has been removed.

type
  CertificateIdentity* {.axiomDecision(
    id = "DECISION-0605",
    reason = "Provenance-complete certificate identity binding the full chain (schema, function, spec, source, IR, SMT, translation, solver, proof); legacy formula field retained for backward compat; legacy computeVerificationFingerprint NOT retroactively applied",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v37").} = object
    formula*: string                       # legacy formula (kept for backward compat)
    schemaVersion*: string
    functionId*: string
    specOrigin*: string
    propertyFormula*: string
    sourceHash*: string
    irHash*: string
    smtHash*: string
    translationVersion*: string           # invariant I5: must be in identity
    solverIdentity*: string
    proofArtifactDigest*: string

  EvidenceIdentity* {.axiomDecision(
    id = "DECISION-0606",
    reason = "Evidence identity binding a certificate; old candidateEvidenceId+fingerprint design removed (dead)",
    adr = "docs/spec/cfg_contract_specification.md",
    introduced = "v37").} = object
    certificate*: CertificateIdentity

func identityDigest*(cert: CertificateIdentity): string {.raises: [].} =
  let fields = @[
    cert.schemaVersion,
    cert.functionId,
    cert.specOrigin,
    cert.propertyFormula,
    cert.sourceHash,
    cert.irHash,
    cert.smtHash,
    cert.translationVersion,
    cert.solverIdentity,
    cert.proofArtifactDigest
  ]
  computeCertificateIdentity(fields)

{.pop.}