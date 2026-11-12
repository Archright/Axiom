{.push raises: [].}
import std/json

type
  TierKind* = enum
    tkTier1_Fast, tkTier1_5_Inductive, tkTier2_LLM, tkTier3_Z3, tkFailed

  TierExecutionMetric* = object
    functionName*: string
    resolvedTier*: TierKind
    durationMs*: float
    cacheHit*: bool

proc toJson*(metric: TierExecutionMetric): JsonNode =
  %*{
    "functionName": metric.functionName,
    "resolvedTier": $metric.resolvedTier,
    "durationMs": metric.durationMs,
    "cacheHit": metric.cacheHit
  }
