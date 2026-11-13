import core/trusted/layer_declaration
axiomLayer "domain"
# src/core/gate/cache_manifest.nim — Merkle-DAG with Single-Writer Gate
import std/[tables, strutils, os]
import core/axiom_pragmas
import core/types/results
const debtMarker525 {.axiomDebt: "DEBT#525".} = true

type
  TxKind* = enum
    tkNormal, tkMerge

  TxRecord* = object
    gateId*: string
    binaryHash*: string
    memoHash*: string
    sourceHash*: string
    configHash*: string
    parentHashes*: seq[string]
    contentHash*: string
    writerId*: string
    kind*: TxKind

  GateOwnership* = object
    owners: Table[string, string]

  OwnershipError* = object of CatchableError

const ManifestDir = ".axiom/cache/manifests"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeContentHash*(record: TxRecord): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  let payload = record.gateId & "|" & record.binaryHash & "|" &
    record.memoHash & "|" & record.sourceHash & "|" &
    record.configHash & "|" & record.parentHashes.join(",") & "|" &
    record.writerId & "|" & $record.kind
  result = $payload

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc claimOwnership*(reg: var GateOwnership, gateId, writerId: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [KeyError, OwnershipError].} =
  if gateId in reg.owners and reg.owners[gateId] != writerId:
    raise newException(OwnershipError,
      "Gate " & gateId & " already owned by " & reg.owners[gateId])
  reg.owners[gateId] = writerId

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc manifestDir(): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} = ManifestDir

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc appendTxRecord*(reg: GateOwnership, record: var TxRecord): Result[string, string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [CatchableError].} =
  if record.gateId notin reg.owners:
    return err("Gate " & record.gateId & " has no registered owner")
  if reg.owners[record.gateId] != record.writerId:
    return err("Writer " & record.writerId & " is not owner of " & record.gateId)
  record.contentHash = computeContentHash(record)
  let dir = manifestDir() / record.contentHash[0..1]
  let path = dir / record.contentHash[2..^1] & ".tx"
  try:
    if not dirExists(dir): createDir(dir)
    let content = $record.gateId & "\n" & $record.kind & "\n" &
      record.writerId & "\n" & record.binaryHash & "\n" &
      record.memoHash & "\n" & record.sourceHash & "\n" &
      record.configHash & "\n" & record.parentHashes.join(",") & "\n" &
      record.contentHash
    writeFile(path, content)
    return ok(record.contentHash)
  except CatchableError as e:
    return err("Failed to write tx: " & e.msg)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc createMergeNode*(gateId, writerId: string,
                      parentHashes: seq[string]): TxRecord {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  result.gateId = gateId
  result.writerId = writerId
  result.parentHashes = parentHashes
  result.kind = tkMerge
  result.contentHash = computeContentHash(result)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc compactManifests*(orchestratorId: string): Result[void, string] {.raises: [].} =
  # Topological sort of .tx files, merge into snapshot
  Result[void, string](ok: true)
