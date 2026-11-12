import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/types/hubs/proof_hub
import core/types/hubs/refactoring_hub

export proof_hub

type
  MathematicalDiscontinuity* = object
    filePath*: string
    lineNumber*: int
    smtUnsatCoreVars*: seq[string]
    discontinuityKind*: DiscontinuityKind
    description*: string

  RemediationPattern* = object
    patternName*: string
    patternDescription*: string
    nimCodeTemplate*: string
    applicableTo*: seq[DiscontinuityKind]

  StructuredRemediationPayload* = object
    discontinuities*: seq[MathematicalDiscontinuity]
    suggestedPatterns*: seq[RemediationPattern]
    refactoringTemplates*: seq[RefactoringTemplate]

{.pop.}
