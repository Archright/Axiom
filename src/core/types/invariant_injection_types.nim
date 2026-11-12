import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

type
  CfgLoopInfo* = object
    loopHeaderId*: int
    modifiedVars*: seq[string]
    inductionVars*: seq[string]
    variableBounds*: seq[tuple[name, low, high: string]]
    loopCondition*: string
    initConditions*: seq[string]
    transitionRelation*: seq[tuple[pre, post: string; expr: string]]

  InvariantContext* = object
    sourceCode*: string
    functionName*: string
    modulePath*: string
    vulnerabilityKind*: string
    loopInfo*: CfgLoopInfo

  InvariantSource* = enum
    isChcSpacer, isSyGuS, isCraig, isLlm

  InvariantResult* = object
    invariant*: string
    source*: InvariantSource
    smtProof*: string
    rounds*: int
