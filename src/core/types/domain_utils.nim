import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/strutils
{.push noSideEffect.}

import core/types/domain_types
import core/trusted/axiom_pragmas

## Domain Utilities
## Business logic extracted from domain_types.nim per AGENTS.md §1.3b.
## Type definitions remain in types/domain_types.nim (leaf module).
## This module provides error messages, status operators, and gate utilities.

# ---------------------------------------------------------------------------
# Axiom Error Message
# ---------------------------------------------------------------------------

## Axiom Error Message.
func axiomErrorMessage*(e: AxiomError): string {.raises: [], axiom: ["(assert (and (>= depth 0) axiomErrSchemaVersionUnsupported axiomErrInvalidValue axiomErrNotFound axiomErrUuidInvalid axiomErrTimestampInvalid axiomErrIsoDateInvalid axiomErrEmptyString axiomErrMimeTypeInvalid axiomErrBase64Invalid axiomErrJsonBlobInvalid axiomErrEnumValueUnknown axiomErrJsonInvalid axiomErrJsonMissingField axiomErrJsonWrongType axiomErrExportTargetUnsupported axiomErrFileSystemError axiomErrInconsistentState axiomErrNetworkFailure axiomErrSolverSatCounterExample axiomErrSolverUnknown axiomErrSolverParseFailure axiomErrSolverTimeout axiomErrVacuousContradiction))", "depth >= 0 ∧ axiomErrSchemaVersionUnsupported ∧ axiomErrInvalidValue ∧ axiomErrNotFound ∧ axiomErrUuidInvalid ∧ axiomErrTimestampInvalid ∧ axiomErrIsoDateInvalid ∧ axiomErrEmptyString ∧ axiomErrMimeTypeInvalid ∧ axiomErrBase64Invalid ∧ axiomErrJsonBlobInvalid ∧ axiomErrEnumValueUnknown ∧ axiomErrJsonInvalid ∧ axiomErrJsonMissingField ∧ axiomErrJsonWrongType ∧ axiomErrExportTargetUnsupported ∧ axiomErrFileSystemError ∧ axiomErrInconsistentState ∧ axiomErrNetworkFailure ∧ axiomErrSolverSatCounterExample ∧ axiomErrSolverUnknown ∧ axiomErrSolverParseFailure ∧ axiomErrSolverTimeout ∧ axiomErrVacuousContradiction"].} =
  case e
  of axiomErrSchemaVersionUnsupported:
    "schemaVersion not supported"
  of axiomErrInvalidValue:
    "invalid value"
  of axiomErrNotFound:
    "requested item not found"
  of axiomErrUuidInvalid:
    "invalid uuid format"
  of axiomErrTimestampInvalid:
    "invalid timestamp format"
  of axiomErrIsoDateInvalid:
    "invalid date format"
  of axiomErrEmptyString:
    "cannot be empty"
  of axiomErrMimeTypeInvalid:
    "invalid contentType format"
  of axiomErrBase64Invalid:
    "invalid base64 format"
  of axiomErrJsonBlobInvalid:
    "invalid jsonBlob format"
  of axiomErrEnumValueUnknown:
    "enum value not supported"
  of axiomErrJsonInvalid:
    "json parsing failed"
  of axiomErrJsonMissingField:
    "required field missing"
  of axiomErrJsonWrongType:
    "field type mismatch"
  of axiomErrExportTargetUnsupported:
    "export target not supported"
  of axiomErrFileSystemError:
    "file system error"
  of axiomErrInconsistentState:
    "inconsistent state detected"
  of axiomErrNetworkFailure:
    "network error (retry assessment needed)"
  of axiomErrSolverSatCounterExample:
    "solver found counter-example"
  of axiomErrSolverUnknown:
    "solver result is unknown"
  of axiomErrSolverParseFailure:
    "solver result parsing failed"
  of axiomErrSolverTimeout:
    "solver timeout exceeded"
  of axiomErrVacuousContradiction:
    "vacuous truth contradiction detected"
  of axiomErrSynthesisFailed:
    "LLM synthesis failed"

# ---------------------------------------------------------------------------
# Certificate Status Operators
# ---------------------------------------------------------------------------

func parseCertStatus*(statusStr: string): CertificateStatus {.raises: [ValueError].} =
  case statusStr
  of "certGreen", "verified", "verifiedKey": certGreen
  of "certRed", "red", "failed": certRed
  of "certPending", "pending": certPending
  of "certYellow", "yellow", "bounded": certYellow
  of "certNoObligation", "no_obligation": certNoObligation
  of "certStale": certStale
  of "certVerifiedAxiom": certVerifiedAxiom
  of "certPseudoVerified": certPseudoVerified
  of "certSoundnessDebt": certSoundnessDebt
  else: raise newException(ValueError, "Unknown cert status: " & statusStr)

func isCertificateVerified*(status: CertificateStatus): bool {.raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  status in {certGreen, certVerifiedAxiom, certDualVerified,
             certZ3Verified, certLeanVerified, certTypeLevelVerified,
             certSafetyVerified}

func isFormalProofStatus*(status: CertificateStatus): bool {.raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  status in {certGreen, certZ3Verified, certLeanVerified,
             certDualVerified, certTypeLevelVerified, certSafetyVerified}

func isVerifiedAxiomStatus*(status: CertificateStatus): bool {.raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  status == certVerifiedAxiom

func isPseudoVerifiedStatus*(status: CertificateStatus): bool {.raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  status == certPseudoVerified

func isYellowStatus*(status: CertificateStatus): bool {.raises: [], axiom: ["(assert (and (>= depth 0)))", "depth >= 0"].} =
  ## certYellow: BMC-bounded or Assume-Guarantee partial verification.
  ## Verified up to bound N or under declared assumptions.
  status == certYellow

# ---------------------------------------------------------------------------
# Gate Utility Functions (moved from gate/gate_rules_normalization.nim)
# ---------------------------------------------------------------------------

## Qualified Name — SSOT for certificate identification.
func qualifiedName*(cert: FunctionCertificate): string {.raises: [].} =
  if cert.functionName.len == 0:
    return ""
  let path = string(cert.modulePath)
  var stem = ""
  let lastSlash = path.rfind('/')
  if lastSlash >= 0:
    stem = path[lastSlash+1..^1]
  else:
    stem = path
  let dotPos = stem.rfind('.')
  if dotPos > 0:
    stem = stem[0..<dotPos]
  if stem.len == 0:
    return cert.functionName
  stem & "." & cert.functionName

{.pop.}

{.pop.}
