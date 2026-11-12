import std/[os, osproc, tables, json, strutils]
import core/results
import core/proof/source_fingerprint
import verification/cert_reconcile

## WP4-g.1-D baseline probe: project the single stale tracked reference cert
## f3d17f0e via projectReferenceCertificate using the CURRENT staged source.
## Avoids the CLI's journal-wide git-show source snapshot (the slow path) by
## building the snapshot for exactly the one module that matters.

proc findRepoRoot(): string =
  var dir = getCurrentDir()
  while dir.len > 0:
    if fileExists(dir / ".axiom_root") or fileExists(dir / "axiom.toml"):
      return dir
    let parent = dir.parentDir()
    if parent == dir:
      break
    dir = parent
  getCurrentDir()

when isMainModule:
  let repoRoot = findRepoRoot()
  if repoRoot.len == 0 or not fileExists(repoRoot / "axiom.toml"):
    echo "ERR repo root not found"
    quit(2)
  setCurrentDir(repoRoot)

  let trackedPath = repoRoot / "src/verification/certificates/f3d17f0e592362e8183b876069904f5f504bd09c2530d21b9c878e31f854e6ac.json"
  if not fileExists(trackedPath):
    echo "ERR tracked cert not found: " & trackedPath
    quit(2)

  # Current staged source (matches stale_cert_gate index-mode semantics).
  let modulePath = "src/core/topology/topology_dependency.nim"
  let staged = execProcess("git show :" & modulePath).strip(chars = {'\n'})
  if staged.len == 0:
    echo "ERR staged source empty for " & modulePath
    quit(2)
  let stagedHash = computeStableSourceFingerprint(staged)

  var sourceSnapshot: Table[string, string]
  sourceSnapshot[modulePath] = staged

  let journalBaseDir = repoRoot
  let projRes = projectReferenceCertificate(trackedPath, journalBaseDir, sourceSnapshot, repoRoot)
  if projRes.isErr():
    echo "PROJECTION_ERROR: " & projRes.error.message
    quit(1)
  let proj = projRes.value
  echo "outcome:       " & $proj.outcome
  echo "claimIdentity: " & proj.claimIdentity
  echo "trackedCertId: " & proj.trackedCertId
  echo "stagedHash:    " & stagedHash
  case proj.outcome
  of rpoResolved:
    echo "journalCommit: " & proj.journalCommitId
    echo "certDigest:    " & proj.certificateDigest
    echo "bytesLen:      " & $proj.bytes.len
  of rpoAmbiguousEvidence:
    echo "variantCount:  " & $proj.variantCount
  else:
    discard
