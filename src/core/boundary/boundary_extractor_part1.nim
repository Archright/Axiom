import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

import core/trusted/axiom_pragmas
import core/boundary/boundary_extraction_types
import core/boundary/boundary_extraction_helpers
import core/boundary/private/boundary_context
import core/boundary/private/boundary_phases
import core/boundary/private/semantic_hint_factory
import core/types/hubs/semantic_hint_hub

proc extractBoundaries*(nodeId, fileContext: string): BoundaryExtractionResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, TimeEffect, RootEffect].} =
  ## Extract parameter boundaries from a function's type signatures.
  ## Delegates to Transient Context State Machine in boundary/private/.

  # ── I/O Boundary: load source HERE, not in context ──
  var effectiveFileContext = fileContext
  if effectiveFileContext.len == 0:
    effectiveFileContext = loadSourceFromNodeId(nodeId)
  if effectiveFileContext.len == 0:
    return BoundaryExtractionResult(
      completeness: bcPartialHavoc,
      hint: buildSemanticHint(
        "ast_parse_failed_isolated",
        "(assert ast_parse_failed_isolated)",
        "BoundaryExtractor[bcPartialHavoc:empty-source] for " & nodeId,
        0.5, isIntervalAbstraction, @[]
      )
    )

  # ── Pure State Machine: all phases are func ──
  var ctx = initBoundaryContext(nodeId, effectiveFileContext)
  ctx.discoverFunction()
  if ctx.shouldEarlyReturn(): return ctx.toResult()
  ctx.detectEffects()
  ctx.computeConstraints()
  ctx.injectIsolation()
  if ctx.shouldEarlyReturn(): return ctx.toResult()
  ctx.filterTrivial()
  if ctx.shouldEarlyReturn(): return ctx.toResult()
  return ctx.assembleResult()

{.pop.}
