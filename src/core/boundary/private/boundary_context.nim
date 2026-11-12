import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [], tags: [].}

import std/[options, strutils]
import compiler/ast
import core/boundary/boundary_extraction_types
import core/types/hubs/semantic_hint_hub
import core/types/hubs/param_type_info_hub
# axiomIoBoundary

type BoundaryContext* = object
  ## Transient Context State Machine for extractBoundaries refactoring.
  ## Stack-allocated shell with ARC-managed heap fields (PNode refs, seqs, strings).
  ## var BoundaryContext passes as C pointer — zero copy cost.
  # ── Input (immutable after init) ──
  nodeId*: string
  functionName*: string
  effectiveFileContext*: string
  # ── AST State (ref fields: heap-allocated, ARC-managed) ──
  ast*: PNode              # ref PNode — ARC auto-destroy at scope exit
  parseFailed*: bool
  fnNode*: PNode           # ref PNode — ARC auto-destroy at scope exit
  foundFn*: bool
  regexFallback*: bool
  # ── Effect Detection ──
  hasVarParam*: bool
  hasExternalIO*: bool
  isFfi*: bool
  # ── Constraint Accumulators ──
  smtParts*: seq[string]
  leanParts*: seq[string]
  fieldParamTypes*: seq[ParamTypeInfo]
  # ── Result Building ──
  completeness*: BoundaryCompleteness
  params*: seq[ParamBoundary]
  hint*: Option[SemanticHint]
  returnType*: string

func initBoundaryContext*(nodeId, fileContext: string): BoundaryContext {.inline, raises: [].} =
  ## Pure constructor — NO I/O. fileContext must be pre-loaded by caller.
  ## Extracts functionName from nodeId ("Module::funcName" → "funcName").
  let parts = nodeId.split("::")
  let fnName = if parts.len >= 2: parts[1] else: ""
  BoundaryContext(
    nodeId: nodeId,
    functionName: fnName,
    effectiveFileContext: fileContext,
    completeness: if parts.len < 2: bcIncompleteIO else: bcComplete,
    parseFailed: false,
    foundFn: false,
    regexFallback: false,
    hasVarParam: false,
    hasExternalIO: false,
    isFfi: false
  )

func shouldEarlyReturn*(ctx: BoundaryContext): bool {.inline, raises: [].} =
  ## Check if any phase set completeness away from bcComplete.
  ctx.completeness != bcComplete

func toResult*(ctx: BoundaryContext): BoundaryExtractionResult {.inline, raises: [].} =
  ## Terminal conversion from context to public result type.
  BoundaryExtractionResult(
    completeness: ctx.completeness,
    functionName: ctx.functionName,
    params: ctx.params,
    returnType: ctx.returnType,
    hint: ctx.hint,
    smtParts: ctx.smtParts,
    leanParts: ctx.leanParts
  )

{.pop.}
