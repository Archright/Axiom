import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/types/pipeline_core_types
import std/options
import std/tables
type
  FunctionComplexityClass* = enum
    fccLinear
    fccLoopSimple
    fccRecursive
    fccNonLinear
    fccCombined

  FunctionVerificationSummary* = object
    functionName*: string
    modulePath*: string
    preConditions*: seq[string]
    postConditions*: seq[string]
    invariant*: string
    provenLayer*: ProvenLayerKind
    checksum*: string
    complexityClass*: FunctionComplexityClass
    vacuityProven*: bool
    vkdFixed4*: string

  SummaryCache* = Table[string, FunctionVerificationSummary]
func makeCacheKey*(modulePath, functionName: string): string {.raises: [].} =
  modulePath & "#" & functionName
func lookupSummary*(cache: SummaryCache; modulePath, functionName: string): Option[FunctionVerificationSummary] {.raises: [].} =
  let key = makeCacheKey(modulePath, functionName)
  if cache.hasKey(key):
    result = some(cache.getOrDefault(key))
  else:
    result = none(FunctionVerificationSummary)
func storeSummary*(cache: var SummaryCache; summary: FunctionVerificationSummary) {.raises: [].} =
  let key = makeCacheKey(summary.modulePath, summary.functionName)
  cache[key] = summary
  # Simple eviction: if > 1024, clear half
  if cache.len > 1024:
    var count = 0
    var toRemove: seq[string] = @[]
    for k in cache.keys:
      if count < 512:
        toRemove.add(k)
      inc count
    for k in toRemove:
      cache.del(k)

{.pop.}
