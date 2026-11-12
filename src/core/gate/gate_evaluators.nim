import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Gate Evaluators — Pure gate rule functions in Domain layer.
##
## These functions were originally in verification/translation_validator.nim
## and gate/gate_rules.nim. Moved here to break circular dependencies:
##   - gate_registry ↔ translation_validator
##   - gate → verification (proof_linkage, proof_state_convergence)
##
## All functions are PURE (no I/O, no side effects).
## All types come from core/types/domain_types
## import core/types/domain_utils.nim.
##
## AGENTS.md §1.2: Domain never imports Infrastructure.

import std/tables
import core/types/domain_types
import core/types/domain_utils

# Callback types for Infrastructure functions (DIP)
type
  ProofLinkageCallback* = proc(
    cert: FunctionCertificate
  ): AxiomLinkageResult {.raises: [], gcsafe.}

# ---------------------------------------------------------------------------
# Semantic Integrity Gate — validates AI-synthesized proofs
# ---------------------------------------------------------------------------

func applySemanticIntegrityGate*(
  certificates: seq[FunctionCertificate];
  semanticResults: Table[string, TranslationValidationResult]
): GateDirectiveBundle[SemanticIntegrityGate] =
  ## Validates that AI-synthesized proofs match original Nim logic.
  ## Only semantic-hallucination (proven-but-wrong) is blocking.
  result.gateResult = SemanticIntegrityGate(violations: @[], blockingFailures: 0, validatedCount: 0, semanticHallucinations: 0)

  for cert in certificates:
    if cert.status != certGreen:
      continue
    let qn = qualifiedName(cert)
    if not semanticResults.hasKey(qn):
      let violation = SemanticIntegrityViolation(
        functionName: qn,
        ruleId: "missing-semantic-validation",
        severity: agWarning,
        message: "No semantic equivalence validation performed for " & qn,
        affectedNodes: @[qn],
        nimInvariant: "",
        leanProposition: ""
      )
      result.gateResult.violations.add(violation)
      continue

    let res = semanticResults.getOrDefault(qn)
    if res.equivalent:
      inc result.gateResult.validatedCount
      continue

    let violation = SemanticIntegrityViolation(
      functionName: qn,
      ruleId: "semantic-hallucination",
      severity: agBlocking,
      message: res.message & " | nim: " & res.nimSmt2 & " | lean: " & res.leanSmt2,
      affectedNodes: @[qn],
      nimInvariant: res.nimSmt2,
      leanProposition: res.leanSmt2
    )
    result.gateResult.violations.add(violation)
    result.gateResult.blockingFailures += 1
    result.gateResult.semanticHallucinations += 1
    result.directives.add(CertificateDirective(
      functionName: qn,
      kind: cdkSetStatus,
      status: certRed,
      reason: "semantic-hallucination"
    ))

func runSemanticIntegrityGate*(
  certificates: seq[FunctionCertificate];
  semanticResults: Table[string, TranslationValidationResult];
  enabled: bool
): SemanticIntegrityGate {.raises: [].} =
  ## Conditional runner for the semantic integrity gate.
  ## When disabled (non-symbolic runs), returns an empty gate to avoid
  ## mass missing-validation warnings.
  if not enabled:
    return SemanticIntegrityGate(
      violations: @[],
      blockingFailures: 0,
      validatedCount: 0,
      semanticHallucinations: 0
    )
  result = applySemanticIntegrityGate(certificates, semanticResults).gateResult

{.pop.}
