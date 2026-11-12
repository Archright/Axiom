import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## translation_types.nim — SSOT for AST mapping and universal translation types.
## Extracted from domain_types.nim (Phase B-4).

import core/types/smt_types

type
  AstMapEntry* = object
    nodeId*: string
    kind*: string
    il*: string
    smt*: string

  UniversalTranslation* = object
    language*: string
    functionName*: string
    logic*: SmtLogic
    ilEntries*: seq[AstMapEntry]
    smt2*: string
    controlFlowCount*: int
    memoryAccessCount*: int
    stateSpace*: seq[string]
    stateInvariants*: seq[string]
    transitionRelation*: seq[string]
    transitionInvariants*: seq[string]
    operationalSemantics*: seq[string]
    environmentInputs*: seq[string]
    envInputConstructors*: seq[string]
    stepFunctionCases*: seq[string]
    loopControlVariables*: seq[string]
    rankVariables*: seq[string]

{.pop.}
