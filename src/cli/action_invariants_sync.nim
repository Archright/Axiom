import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

import std/[os, strutils, json, times]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/trusted/stdlib_shield

const
  InvariantsRelPath = "src/core/trusted/architecture_invariants.nim"
  ExpectedHashRelPath = "data/expected_invariant_hash.txt"
  AuditLogRelPath = "data/audit_log.jsonl"

proc invariantsSha256(repoRoot: string): string =
  let path = repoRoot / InvariantsRelPath
  if not fileExists(path):
    raise newException(system.IOError, "architecture_invariants.nim not found: " & path)
  sha256Hex(readFile(path))

proc appendAuditEvent(repoRoot: string; kind, oldHash, newHash: string) =
  let path = repoRoot / AuditLogRelPath
  createDir(parentDir(path))
  let line = %*{"ts": now().utc().format("yyyy-MM-dd'T'HH:mm:ss'Z'"), "kind": kind, "oldHash": oldHash, "newHash": newHash}
  var f = open(path, fmAppend)
  f.writeLine($line)
  f.close()

proc cmdInvariantsSync*(): int {.axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let repoRoot = getCurrentDir()
  let hashPath = repoRoot / ExpectedHashRelPath
  let newHash = invariantsSha256(repoRoot)
  let oldHash = if fileExists(hashPath): readFile(hashPath).strip() else: ""
  if oldHash == newHash:
    echo "[invariants] hash unchanged — NO-OP"
    return 0
  let dir = parentDir(hashPath)
  if dir.len > 0 and not dirExists(dir):
    createDir(dir)
  let tmpPath = hashPath & ".tmp"
  writeFile(tmpPath, newHash & "\n")
  safeMoveFile(tmpPath, hashPath)
  appendAuditEvent(repoRoot, "INVARIANT_HASH_SYNCED", oldHash, newHash)
  echo "[invariants] synced: " & newHash
  result = 0

proc runInvariantsCli*(args: seq[string]): int {.axiomDecision.} =
  let cmd = if args.len > 0: args[0] else: ""
  case cmd
  of "sync":
    result = cmdInvariantsSync()
  else:
    echo "Usage: ax invariants <sync>"
    result = 1
{.pop.}