## Schema-as-Code Utilities — Shared Types
##
## Common types used by both compile-time macros and runtime validators.
## This module is the SSOT for schema type definitions.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

# ---------------------------------------------------------------------------
# Schema Version
# ---------------------------------------------------------------------------

const AxiomSchemaVersion* = "axiom.schema.v1"
  ## Monotonically increasing schema version string.
  ## Bump on any breaking change to schema types or validation rules.

# ---------------------------------------------------------------------------
# Violation Types
# ---------------------------------------------------------------------------

type
  ViolationSeverity* = enum
    ## Severity of a schema violation.
    vsError = "error"     ## Hard failure -- policy config is invalid.
    vsWarning = "warning" ## Soft signal -- policy config is unusual but valid.

  SchemaViolation* = object
    ## A single schema violation with full diagnostic context.
    severity*: ViolationSeverity
    schemaName*: string   ## Which schema produced this violation.
    fieldPath*: string    ## Dot-separated path to the offending field.
    message*: string      ## Human-readable description of the violation.
    line*: int            ## Source line number (0 if not available).
    column*: int          ## Source column number (0 if not available).

  PolicyFieldKind* = enum
    ## Supported field types in policy schema specs.
    pfkString
    pfkInt
    pfkFloat
    pfkBool
    pfkArray
    pfkObject

  PolicyFieldSpec* = object
    ## Specification for a single field in a policy schema.
    name*: string
    kind*: PolicyFieldKind
    required*: bool
    minLength*: int       ## For strings: minimum length (0 = no limit).
    maxLength*: int       ## For strings: maximum length (0 = no limit).
    allowedValues*: seq[string] ## If non-empty, value must be one of these.

  PolicySchema* = object
    ## Declarative schema for a policy config object.
    name*: string
    version*: string
    fields*: seq[PolicyFieldSpec]

# ---------------------------------------------------------------------------
# String conversions
# ---------------------------------------------------------------------------

func `$`*(v: ViolationSeverity): string {.inline.} =
  case v
  of vsError: "error"
  of vsWarning: "warning"

func `$`*(sv: SchemaViolation): string =
  ## Human-readable representation of a violation.
  let loc = if sv.line > 0: ":" & $sv.line & ":" & $sv.column
            else: ""
  "[" & $sv.severity & "]" & loc & " " & sv.schemaName & "." &
    sv.fieldPath & ": " & sv.message

func `$`*(pk: PolicyFieldKind): string =
  case pk
  of pfkString: "string"
  of pfkInt: "int"
  of pfkFloat: "float"
  of pfkBool: "bool"
  of pfkArray: "array"
  of pfkObject: "object"

# ---------------------------------------------------------------------------
# Schema Construction Helpers (pure -- no I/O, no JsonNode access)
# ---------------------------------------------------------------------------

func mkField*(name: string; kind: PolicyFieldKind; required = true;
    minLength = 0; maxLength = 0;
    allowedValues: seq[string] = @[]): PolicyFieldSpec =
  ## Convenience constructor for PolicyFieldSpec.
  PolicyFieldSpec(
    name: name,
    kind: kind,
    required: required,
    minLength: minLength,
    maxLength: maxLength,
    allowedValues: allowedValues
  )

func mkSchema*(name: string; version: string;
    fields: seq[PolicyFieldSpec]): PolicySchema =
  ## Convenience constructor for PolicySchema.
  PolicySchema(name: name, version: version, fields: fields)

{.pop.}
