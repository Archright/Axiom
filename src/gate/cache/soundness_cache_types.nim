import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import core/trusted/axiom_pragmas_lite
import std/options
import std/json
import std/os

## ============================================================================
## Soundness Cache Types
## ============================================================================
## Defines the type system for the Soundness Cache Engine.
##
## Previous Bug (§0.9 Theater — Always-Pass):
## The cache system returned true on cache HIT without checking previous
## pass/fail status. A FAILED gate run would be silently replayed as PASS
## on subsequent runs, violating the fail-closed principle.
##
## Fix:
## GateVerificationStatus explicitly tracks pass/fail/unchecked state.
## Cache lookup returns Option[GateVerificationStatus], forcing callers
## to handle all three cases explicitly.
## ============================================================================

type
  ## Status of a gate verification cached in the soundness cache.
  GateVerificationStatus* {.pure.} = enum
    gvsUnchecked  ## Cache entry exists but verification has not been performed
    gvsPass       ## Gate previously passed with matching source hash
    gvsFail       ## Gate previously failed with matching source hash

  ## A single entry in the soundness cache.
  VerificationCacheEntry* = object
    schemaVersion*: string            ## Schema version for forward compatibility
    compositeLockHash*: string        ## Lock hash of gate inputs
    sourceHash*: string               ## Project source hash (src/ + config)
    status*: GateVerificationStatus   ## Pass/fail/unchecked
    timestamp*: float                 ## Unix epoch of cache write
    gateId*: string                   ## Gate identifier

  ## The full soundness cache (persisted as JSON).
  SoundnessCache* = ref object
    version*: string                  ## Schema version
    entries*: seq[VerificationCacheEntry]
    projectSourceHash*: string        ## Hash of src/ + build config files

proc soundnessCachePath*(repoRoot: string): string {.raises: [], axiomEffect: IOEffect.} =
  ## Default path for the unified soundness cache file.
  repoRoot / ".axiom" / "cache" / "soundness_cache.json"

proc lookupSoundnessCache*(cache: SoundnessCache; gateId, sourceHash: string): Option[GateVerificationStatus] {.raises: [].} =
  ## Lookup cache entry by gateId and sourceHash.
  ## Returns none if no matching entry found.
  for entry in cache.entries:
    if entry.gateId == gateId and entry.sourceHash == sourceHash:
      return some(entry.status)
  none(GateVerificationStatus)

func serializeEntry*(entry: VerificationCacheEntry): JsonNode {.raises: [].} =
  ## Serialize VerificationCacheEntry to JSON node.
  %*{
    "schemaVersion": entry.schemaVersion,
    "compositeLockHash": entry.compositeLockHash,
    "sourceHash": entry.sourceHash,
    "status": $entry.status,
    "timestamp": entry.timestamp,
    "gateId": entry.gateId
  }

func deserializeEntry*(node: JsonNode): VerificationCacheEntry {.raises: [].} =
  ## Deserialize JSON node to VerificationCacheEntry.
  var status = gvsUnchecked
  let statusStr = node{"status"}.getStr("")
  case statusStr
  of "gvsUnchecked": status = gvsUnchecked
  of "gvsPass": status = gvsPass
  of "gvsFail": status = gvsFail
  else: status = gvsUnchecked
  VerificationCacheEntry(
    schemaVersion: node{"schemaVersion"}.getStr("1.0"),
    compositeLockHash: node{"compositeLockHash"}.getStr(""),
    sourceHash: node{"sourceHash"}.getStr(""),
    status: status,
    timestamp: node{"timestamp"}.getFloat(0.0),
    gateId: node{"gateId"}.getStr("")
  )

func serializeCache*(cache: SoundnessCache): JsonNode {.raises: [].} =
  ## Serialize SoundnessCache to JSON node.
  var entriesArr = newJArray()
  for entry in cache.entries:
    entriesArr.add(serializeEntry(entry))
  %*{
    "version": cache.version,
    "projectSourceHash": cache.projectSourceHash,
    "entries": entriesArr
  }

func deserializeCache*(root: JsonNode): SoundnessCache {.raises: [].} =
  ## Deserialize JSON node to SoundnessCache.
  var entries: seq[VerificationCacheEntry] = @[]
  let entriesNode = root{"entries"}
  if entriesNode != nil and entriesNode.kind == JArray:
    for node in entriesNode:
      entries.add(deserializeEntry(node))
  SoundnessCache(
    version: root{"version"}.getStr("1.0"),
    entries: entries,
    projectSourceHash: root{"projectSourceHash"}.getStr("")
  )

{.pop.}
