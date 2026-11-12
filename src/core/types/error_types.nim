import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## error_types.nim — SSOT for AxiomError enum.
## Extracted from domain_types.nim (Phase B-4).

type
  AxiomError* = enum
    axiomErrSchemaVersionUnsupported
    axiomErrInvalidValue
    axiomErrNotFound
    axiomErrUuidInvalid
    axiomErrTimestampInvalid
    axiomErrIsoDateInvalid
    axiomErrEmptyString
    axiomErrMimeTypeInvalid
    axiomErrBase64Invalid
    axiomErrJsonBlobInvalid
    axiomErrEnumValueUnknown
    axiomErrJsonInvalid
    axiomErrJsonMissingField
    axiomErrJsonWrongType
    axiomErrExportTargetUnsupported
    axiomErrFileSystemError
    axiomErrInconsistentState
    axiomErrNetworkFailure
    axiomErrSolverSatCounterExample
    axiomErrSolverUnknown
    axiomErrSolverParseFailure
    axiomErrSolverTimeout
    axiomErrVacuousContradiction
    axiomErrSynthesisFailed

{.pop.}
