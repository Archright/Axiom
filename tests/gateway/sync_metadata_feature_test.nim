## Sync Metadata Feature Test — per-commit metadata and payload computation.
## See tests/features/sync_metadata.feature for the specification.
##
## Contract: computePayload determinism, TTL checks.

import std/[unittest, times]

# We test pure functions only (no I/O)
# computePayload and isWithinTtl are pure

type
  SyncMetadata = object
    mergeCommit: string
    baseBranch: string
    secondaryBranch: string
    treeOid: string
    timestamp: int64
    resolvedVia: string
    signature: string

proc computePayload(m: SyncMetadata): string =
  $m.timestamp & "|" & m.mergeCommit & "|" & m.treeOid

proc isWithinTtl(m: SyncMetadata, ttlSeconds: int64 = 86400): bool =
  let now = getTime().toUnix()
  result = (now - m.timestamp) <= ttlSeconds

suite "Sync Metadata — Per-Commit State":
  test "computePayload — deterministic output":
    ## Scenario: Compute deterministic payload
    ## Given a SyncMetadata with known fields
    let m = SyncMetadata(
      mergeCommit: "abc123def456abc123def456abc123def456abc1",
      baseBranch: "main",
      secondaryBranch: "core",
      treeOid: "e5d44411292334a0a48fb966faf1eda35235a9b9",
      timestamp: 1782126825,
      resolvedVia: "sync-branch",
      signature: ""
    )
    ## When computePayload is called
    let payload = computePayload(m)
    ## Then the result is "{timestamp}|{mergeCommit}|{treeOid}"
    check payload == "1782126825|abc123def456abc123def456abc123def456abc1|e5d44411292334a0a48fb966faf1eda35235a9b9"

  test "isWithinTtl — current timestamp passes":
    ## Scenario: TTL check — within 24 hours
    let m = SyncMetadata(timestamp: getTime().toUnix())
    check isWithinTtl(m) == true

  test "isWithinTtl — old timestamp fails":
    ## Scenario: TTL check — expired
    let m = SyncMetadata(timestamp: getTime().toUnix() - 172800)  # 48 hours ago
    check isWithinTtl(m) == false

  test "isWithinTtl — exactly at boundary passes":
    ## Edge case: exactly at TTL boundary
    let m = SyncMetadata(timestamp: getTime().toUnix() - 86400)
    check isWithinTtl(m) == true

  test "isWithinTtl — just past boundary fails":
    ## Edge case: 1 second past TTL
    let m = SyncMetadata(timestamp: getTime().toUnix() - 86401)
    check isWithinTtl(m) == false
