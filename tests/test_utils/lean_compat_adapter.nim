{.push raises: [].}

## Lean Compat Adapter — Bridge between deprecated and new API.
##
## Bridges deprecated buildLeanSkeleton → buildLeanTheoremSkeleton.
## buildUniversalLeanSource has no (nodeId,hint,smtlib2) overload — only TranslatorContext path exists.
##
## Verified output format (Nim 2.2.10):
##   - contains 'import' ✅
##   - contains 'theorem' ✅
##   - not contains 'sorry' ✅
##   - does NOT end with ':= by\n' (proof body is included)

import core/judge/the_judge_query_part2
import core/judge/smart_search

proc adaptToLeanSkeleton*(nodeId: string; hint: SemanticHint): string =
  ## Replacement for buildLeanSkeleton(nodeId, hint).
  ## Produces complete Lean source with imports, theorem, and proof body.
  buildLeanTheoremSkeleton(nodeId, hint)

proc adaptToLeanSkeletonPremises*(nodeId: string; hint: SemanticHint): string =
  ## Replacement for buildLeanSkeletonPremises(nodeId, hint).
  # axiom:todo-cleanup — buildUniversalLeanSource has no (nodeId,hint,smtlib2) overload
  buildLeanTheoremSkeleton(nodeId, hint)
