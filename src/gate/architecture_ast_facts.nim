import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/options

## Typed AST facts consumed by the architecture gate.

type
  FuncDeclKind* = enum
    fdkProc
    fdkFunc
    fdkMethod

  SourceLocation* = object
    path*: string
    line*: int
    column*: int

  ImportFact* = object
    modulePath*: string
    symbols*: seq[string]
    location*: SourceLocation

  CallFact* = object
    callee*: string
    qualifiedCallee*: string
    location*: SourceLocation

  AssignmentFact* = object
    targetPath*: string
    rhsExpr*: string          # ← NEW: RHS expression text
    operator*: string
    location*: SourceLocation

  DivisionFact* = object
    lhs*: string              # numerator subtree text
    rhs*: string              # denominator subtree text
    text*: string             # full division expression text
    insideFactory*: bool      # true if division occurs inside initKernelRatio/initAsiRatio args
    location*: SourceLocation

  TypeDefFact* = object
    name*: string
    exported*: bool
    location*: SourceLocation

  ParamInfo* = object
    name*: string
    paramType*: string

  FunctionFact* = object
    name*: string
    exported*: bool
    declKind*: FuncDeclKind
    normalizedAstFingerprint*: string
    alphaFingerprint*: string
    nodeCount*: int
    lineCount*: int  ## number of source lines spanned by this function
    physicalSpan*: int  ## number of source lines spanned (same as lineCount for backward compat)
    effectiveSLOC*: int  ## non-whitespace token line count (comments/whitespace excluded)
    variableRefs*: seq[string]  ## PNode nkIdent.ident.s extracted from body
    params*: seq[ParamInfo]
    returnType*: string
    axiomEffect*: Option[string]  ## {.axiomEffect: X.} pragma value ("Pure" or "IOEffect")
    location*: SourceLocation

  ConstStringFact* = object
    value*: string
    name*: string
    location*: SourceLocation

  PragmaFact* = object
    targetName*: string
    pragmaName*: string
    pragmaValue*: string
    location*: SourceLocation

  DistinctTypeFact* = object
    name*: string
    baseType*: string
    location*: SourceLocation

  # OCP detection support — counts nkOfBranch branches

  CallEdgeFact* = object
    callerModule*: string
    callerFunction*: string
    calleeModule*: string
    calleeFunction*: string
    location*: SourceLocation

  ModuleFacts* = object
    path*: string
    imports*: seq[ImportFact]
    calls*: seq[CallFact]
    assignments*: seq[AssignmentFact]
    divisions*: seq[DivisionFact]
    typeDefs*: seq[TypeDefFact]
    functions*: seq[FunctionFact]
    constStrings*: seq[ConstStringFact]
    pragmas*: seq[PragmaFact]
    distinctTypes*: seq[DistinctTypeFact]
    callEdges*: seq[CallEdgeFact]
    caseBranchCount*: int
    typeCaseBranchCount*: int  ## branches inside nkTypeSection (object variants) — not runtime dispatch
    caseBranchLocations*: seq[SourceLocation]
    addedLineRanges*: seq[tuple[startLine, endLine: int]]
    whenBlocks*: seq[string]  # Names of when-conditions (e.g., "isMainModule")


func axiomEffectOf*(facts: ModuleFacts; procName: string): Option[string] {.raises: [].} =
  ## Return the raw value of the {.axiomEffect: X.} pragma for a procedure,
  ## or none if absent. Values are "Pure" or "IOEffect".
  for p in facts.pragmas:
    if p.targetName == procName and p.pragmaName == "axiomEffect":
      return some(p.pragmaValue)
  return none(string)

{.pop.}
