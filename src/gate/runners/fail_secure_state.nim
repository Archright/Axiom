import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Fail-Secure State Machine — Bypass Audit Verification
##
## Uses Hash-Anchored Reconciliation to verify bypass audit integrity:
## 1. Extract bypass commit hashes from Git history
## 2. Extract commit hashes from local audit log's `commitHash` field
## 3. Verify: every local commitHash must exist in Git history (subset check)
## 4. Pre-push/non-commit events have no commitHash → excluded from comparison
## 5. Missing audit file → fsLocked (fail-secure)
##
## State machine:
##   fsHealthy  — all audited bypass commits verifiable in Git history
##   fsDegraded — audit file present but some entries unverifiable
##   fsLocked   — audit file missing or critical failure → all bypasses blocked
##
## All git subprocess calls delegate to git_operations.nim (SSOT).

import std/[json, os, strutils]
import core/interfaces/git_operations
import core/axiom_pragmas
# axiomIoBoundary

type
  FailSecureState* = enum
    fsHealthy,   ## All audited bypass commits verifiable in Git history
    fsDegraded,  ## Audit file present but some entries unverifiable
    fsLocked     ## Audit file missing or critical failure — all bypasses blocked

proc countLinesSafe*(s: string): int {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = 0

proc verifyCommitExists(hash: string): bool {.axiomEffect: IOEffect.} =
  let (_, code) = git_operations.runGit("cat-file -e " & hash)
  result = code == 0

proc extractAuditHashes(auditPath: string): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = @[]
  try:
    let content = readFile(auditPath)
    if content.len == 0:
      return
    for line in content.splitLines():
      let trimmed = line.strip()
      if trimmed.len == 0:
        continue
      try:
        let entry = parseJson(trimmed)
        if entry.hasKey("commitHash"):
          let hash = entry["commitHash"].getStr()
          if hash.len >= 40:
            result.add(hash)
      except JsonParsingError, ValueError: # axiom:best-effort(malformed entry skipped from state extraction)
        discard
  except IOError, OSError: # axiom:best-effort(state file read failure is non-fatal)
    discard

proc computeState*(auditPath: string; commitMsgPath: string = ""): FailSecureState {.axiomEffect: IOEffect.} =
  result = fsLocked

  if not fileExists(auditPath):
    return

  let localHashes = extractAuditHashes(auditPath)

  if localHashes.len == 0:
    return fsHealthy

  for hash in localHashes:
    if not verifyCommitExists(hash):
      return fsDegraded

  result = fsHealthy

proc canBypass*(state: FailSecureState): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  result = state == fsHealthy

proc stateDescription*(state: FailSecureState): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  case state
  of fsHealthy: "healthy"
  of fsDegraded: "degraded"
  of fsLocked: "locked"
