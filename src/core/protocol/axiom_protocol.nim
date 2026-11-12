import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## axiom_protocol.nim — Standard protocol for gate runner communication.
##
## Version-managed, capability-aware protocol for CLI, MCP, and orchestrator.
## All gate runners MUST produce output conforming to this protocol.
##
## Architecture: Protocol module in src/core/protocol/.
## Imports: std/* only (SOC-leaf, pure data + serialization).

import std/[json, tables, times]

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  ProtocolVersion* = "1.0.0"
    ## Current protocol version (semver).
  MinSupportedVersion* = "0.9.0"
    ## Minimum protocol version accepted by this implementation.

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  GateStatus* = enum
    gsPass          ## Gate passed all checks
    gsFail          ## Gate failed with violations
    gsSkip          ## Gate was skipped (dependency failure)
    gsError         ## Gate encountered an internal error
    gsTimeout       ## Gate exceeded its timeout

  ProtocolViolation* = object
    ## A single rule violation reported by a gate runner.
    ruleId*: string
    severity*: string       ## "warning" | "blocking" | "info"
    message*: string
    affectedFiles*: seq[string]
    suggestion*: string

  ProtocolMetrics* = object
    ## Execution metrics collected during a gate run.
    durationMs*: int64
    filesScanned*: int
    violationsFound*: int
    cacheHit*: bool
    retryCount*: int

  AxiomProtocol* = object
    ## Standard output envelope for all gate runners.
    version*: string                    ## Protocol version (semver)
    gateId*: string                     ## Gate identifier
    gateVersion*: string                ## Gate's own version
    status*: GateStatus
    violations*: seq[ProtocolViolation]
    metrics*: ProtocolMetrics
    timestamp*: int64                   ## Unix timestamp
    message*: string                    ## Human-readable summary
    metadata*: Table[string, string]    ## Free-form key-value pairs

  CapabilitySet* = object
    ## Declares what features a gate runner supports.
    supportedFeatures*: seq[string]     ## e.g., ["json-output", "sharded-log", "shadow-mode"]
    minProtocolVersion*: string         ## Minimum protocol version this runner requires
    maxProtocolVersion*: string         ## Maximum protocol version this runner supports

# ---------------------------------------------------------------------------
# Internal Helpers
# ---------------------------------------------------------------------------

func safeTimestamp(): int64 {.raises: [].} =
  ## Get current Unix timestamp. getTime() is effect-tagged but does not raise.
  toUnix(getTime())

# ---------------------------------------------------------------------------
# Constructors
# ---------------------------------------------------------------------------

func newProtocol*(gateId: string, gateVersion: string = "0.1.0"): AxiomProtocol =
  ## Construct a fresh protocol envelope with default values.
  AxiomProtocol(
    version: ProtocolVersion,
    gateId: gateId,
    gateVersion: gateVersion,
    status: gsPass,
    timestamp: safeTimestamp(),
    metadata: initTable[string, string]()
  )

func ok*(gateId: string, message: string = ""): AxiomProtocol {.raises: [].} =
  ## Construct a passing protocol envelope.
  var p = newProtocol(gateId)
  p.status = gsPass
  p.message = message
  p

func fail*(gateId: string, violations: seq[ProtocolViolation],
           message: string = ""): AxiomProtocol {.raises: [].} =
  ## Construct a failing protocol envelope with violations.
  var p = newProtocol(gateId)
  p.status = gsFail
  p.violations = violations
  p.message = message
  p.metrics.violationsFound = violations.len
  p

func skip*(gateId: string, message: string = ""): AxiomProtocol =
  ## Construct a skipped protocol envelope.
  var p = newProtocol(gateId)
  p.status = gsSkip
  p.message = message
  p

func error*(gateId: string, message: string = ""): AxiomProtocol =
  ## Construct an error protocol envelope.
  var p = newProtocol(gateId)
  p.status = gsError
  p.message = message
  p

func timeout*(gateId: string, message: string = ""): AxiomProtocol =
  ## Construct a timeout protocol envelope.
  var p = newProtocol(gateId)
  p.status = gsTimeout
  p.message = message
  p

# ---------------------------------------------------------------------------
# GateStatus Serialization
# ---------------------------------------------------------------------------

func gateStatusToStr*(s: GateStatus): string {.noSideEffect.} =
  ## Serialize GateStatus to lowercase string.
  case s
  of gsPass:    "pass"
  of gsFail:    "fail"
  of gsSkip:    "skip"
  of gsError:   "error"
  of gsTimeout: "timeout"

func gateStatusFromStr*(s: string): GateStatus {.noSideEffect.} =
  ## Deserialize string to GateStatus. Defaults to gsError on unknown input.
  case s
  of "pass":    gsPass
  of "fail":    gsFail
  of "skip":    gsSkip
  of "error":   gsError
  of "timeout": gsTimeout
  else:         gsError

# ---------------------------------------------------------------------------
# JSON Serialization
# ---------------------------------------------------------------------------

func `%`*(v: ProtocolViolation): JsonNode {.noSideEffect.} =
  ## Serialize a ProtocolViolation to JSON.
  %*{
    "ruleId": v.ruleId,
    "severity": v.severity,
    "message": v.message,
    "affectedFiles": v.affectedFiles,
    "suggestion": v.suggestion
  }

func `%`*(m: ProtocolMetrics): JsonNode {.noSideEffect.} =
  ## Serialize ProtocolMetrics to JSON.
  %*{
    "durationMs": m.durationMs,
    "filesScanned": m.filesScanned,
    "violationsFound": m.violationsFound,
    "cacheHit": m.cacheHit,
    "retryCount": m.retryCount
  }

func `%`*(p: AxiomProtocol): JsonNode {.noSideEffect.} =
  ## Serialize AxiomProtocol to standard JSON envelope.
  var violationsNode = newJArray()
  for v in p.violations:
    violationsNode.add(%v)
  %*{
    "version": p.version,
    "gateId": p.gateId,
    "gateVersion": p.gateVersion,
    "status": gateStatusToStr(p.status),
    "violations": violationsNode,
    "metrics": %p.metrics,
    "timestamp": p.timestamp,
    "message": p.message,
    "metadata": p.metadata
  }

func toJson*(p: AxiomProtocol): JsonNode {.noSideEffect.} =
  ## Named alias for JSON serialization.
  %p

# ---------------------------------------------------------------------------
# JSON Deserialization
# ---------------------------------------------------------------------------

func fromJson*(node: JsonNode, _: typedesc[ProtocolViolation]): ProtocolViolation {.noSideEffect.} =
  ## Deserialize a JsonNode into a ProtocolViolation.
  ProtocolViolation(
    ruleId: node{"ruleId"}.getStr(),
    severity: node{"severity"}.getStr(),
    message: node{"message"}.getStr(),
    affectedFiles: block:
      var files: seq[string]
      let arr = node{"affectedFiles"}
      if not arr.isNil and arr.kind == JArray:
        for item in arr:
          files.add(item.getStr())
      files,
    suggestion: node{"suggestion"}.getStr()
  )

func fromJson*(node: JsonNode, _: typedesc[ProtocolMetrics]): ProtocolMetrics {.noSideEffect.} =
  ## Deserialize a JsonNode into ProtocolMetrics.
  ProtocolMetrics(
    durationMs: node{"durationMs"}.getInt(),
    filesScanned: node{"filesScanned"}.getInt(),
    violationsFound: node{"violationsFound"}.getInt(),
    cacheHit: node{"cacheHit"}.getBool(),
    retryCount: node{"retryCount"}.getInt()
  )

func fromJson*(node: JsonNode, _: typedesc[AxiomProtocol]): AxiomProtocol {.noSideEffect.} =
  ## Deserialize a JsonNode into AxiomProtocol.
  var violations: seq[ProtocolViolation]
  let violationsNode = node{"violations"}
  if not violationsNode.isNil and violationsNode.kind == JArray:
    for vNode in violationsNode:
      violations.add(fromJson(vNode, ProtocolViolation))

  AxiomProtocol(
    version: node{"version"}.getStr(),
    gateId: node{"gateId"}.getStr(),
    gateVersion: node{"gateVersion"}.getStr(),
    status: gateStatusFromStr(node{"status"}.getStr()),
    violations: violations,
    metrics: fromJson(node{"metrics"}, ProtocolMetrics),
    timestamp: node{"timestamp"}.getInt(),
    message: node{"message"}.getStr(),
    metadata: block:
      var meta: Table[string, string]
      let metaNode = node{"metadata"}
      if not metaNode.isNil and metaNode.kind == JObject:
        for k, v in metaNode:
          meta[k] = v.getStr()
      meta
  )

func protocolFromJson*(node: JsonNode): AxiomProtocol {.noSideEffect.} =
  ## Named alias for deserialization.
  fromJson(node, AxiomProtocol)

{.pop.}
