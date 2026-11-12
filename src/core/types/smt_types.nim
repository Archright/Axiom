import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## smt_types.nim — SSOT for SMT logic and verification constraint types.
## Extracted from domain_types.nim (Phase B-4).

type
  SmtLogic* = enum
    slQfLia   ## Quantifier-Free Linear Integer Arithmetic (default)
    slQfBv    ## Quantifier-Free Bit-Vectors (legacy)
    slHorn    ## Constrained Horn Clauses / SPACER placeholder
    slQfSlia  ## Quantifier-Free String and Linear Integer Arithmetic (QF_SLIA)
    slQfAufbv ## Quantifier-Free Arrays + UF + BitVectors (QF_AUFBV)

  ConstraintKind* = enum
    ckStaticBounds   ## Boundary Extractor: type/length/domain constraints
    ckDynamicStep    ## AST Mapper: assignment, branch, loop transitions

  VerificationConstraint* = object
    kind*: ConstraintKind
    expression*: string
    source*: string

  AxiomVerificationContext* = object
    functionName*: string
    logic*: SmtLogic
    constraints*: seq[VerificationConstraint]
    hornRelations*: seq[string]
    hornRules*: seq[string]
    hornQueries*: seq[string]

{.pop.}
