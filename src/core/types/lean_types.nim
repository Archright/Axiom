import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## lean_types.nim — SSOT for Lean diagnostic and feedback types.
## Extracted from domain_types.nim (Phase B-4).

type
  LeanDiagnostic* = object
    line*: int
    character*: int
    severity*: int
    message*: string
    code*: string = ""
    kind*: string = ""

  LeanFeedback* = object
    diagnostics*: seq[LeanDiagnostic]
    goals*: seq[string]
    events*: seq[string]

  LeanLiveDiagnosticFeedback* = object
    line*: int
    hasErrors*: bool
    hasWarnings*: bool
    dominantKind*: string
    summary*: string
    diagnostics*: seq[LeanDiagnostic]
    goals*: seq[string]
    actionableHints*: seq[string]

  LeanSpecComplexity* = object
    hasRecursiveDefs*: bool
    needsInduction*: bool
    needsCases*: bool
    hasPatternMatching*: bool
    fingerprint*: string
    summary*: string

{.pop.}
