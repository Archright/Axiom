import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Pure logic layer for orchestrator — zero I/O, zero side effects.
##
## Every function is a `func` with `{.raises: [].}`.
## The compiler enforces purity: any I/O call in a `func` is a compile-time error.
##
## ┌───────────────────────────────────────────────────────────────────┐
## │ IMPORT BAN: Only pure modules allowed.                           │
## │ Allowed: gate/types, core/crypto/hash_kernel, std/strutils, std/sequtils  │
## │          core/crypto/hash_kernel, core/gate/state_ledger_types   │
## │ Banned: os, osproc, net, asyncdispatch, json, streams, terminal  │
## └───────────────────────────────────────────────────────────────────┘

import gate/types
import core/crypto/hash_kernel
import std/[strutils, sequtils, tables]
import core/gate/state_ledger_types

# ─── Type Aliases ──────────────────────────────────────────────────────────────

type
  LedgerEntryTuple* = tuple
    gateIdHash: uint32
    cacheKey: HashValue
    result: uint8
    tier: uint8
    deferredAt: int64
    deferredStage: uint8

# ─── Failure Classification ────────────────────────────────────────────────────

func classifyFailure*(exitCode: int, output: string):
    tuple[category: FailureCategory, reason: string] =
  ## Deterministic failure classification based on POSIX exit code.
  ## Zero I/O — operates only on string arguments.
  ## Convention:
  ##   0: success (shouldn't be called)
  ##   1: validation failure (gate logic rejected the input)
  ##   2: configuration/policy error
  ##   134 (128+6): SIGABRT — self-diagnostic failure
  ##   139 (128+11): SIGSEGV — memory fault
  ## Falls back to structured output markers ([fcPermanent]/[fcValidation])
  ## for gates that explicitly categorize their failures.
  let failLines = output.splitLines().filterIt("FAIL" in it)
  let reason = failLines.join("; ")
  case exitCode
  of 1: (fcValidation, reason)
  of 2: (fcPermanent, reason)
  of 128 + 6: (fcPermanent, "SIGABRT: " & reason)
  of 128 + 11: (fcPermanent, "SIGSEGV: " & reason)
  else:
    # Check structured output markers for gates that explicitly categorize
    for line in output.splitLines():
      if "[fcPermanent]" in line:
        let parts = line.split("]", 2).mapIt(it.strip()).filterIt(it.len > 0)
        let msg = if parts.len >= 3: parts[2] else: line
        return (fcPermanent, msg)
      if "[fcValidation]" in line:
        let parts = line.split("]", 2).mapIt(it.strip()).filterIt(it.len > 0)
        let msg = if parts.len >= 3: parts[2] else: line
        return (fcValidation, msg)
    (fcTransient, reason)  # fallback: unclassified exit codes are transient

# ─── Hash Composition ──────────────────────────────────────────────────────────

func assembleCompositeHash*(inputHash, gateHash, rootHash,
    buildEnvHash, subtreeRoot, binaryHash, envHash,
    toolchainSalt: string): string =
  ## Pure hash composition — all inputs pre-resolved by effect layer.
  ## This is the final SHA-256 from computeCompositeLockHash (isPath=false).
  ## The caller must resolve all 8 components via I/O before calling this.
  hash_kernel.sha256Hex(inputHash & "|" & gateHash & "|" & rootHash & "|" &
              buildEnvHash & "|" & subtreeRoot & "|" & binaryHash & "|" &
              envHash & "|" & toolchainSalt)

# ─── String Filtering ──────────────────────────────────────────────────────────

func filterByPattern*(changedFiles: seq[string]; filesPattern: string): seq[string] =
  ## Filter files by pipe-separated pattern. Zero I/O.
  if filesPattern.len == 0:
    return changedFiles
  let patterns = filesPattern.split('|')
  result = @[]
  for f in changedFiles:
    for p in patterns:
      if f.contains(p.strip()):
        result.add(f)
        break

# ─── Environment Hash ──────────────────────────────────────────────────────────

func computeEnvHash*(deps: seq[EnvDependency];
                     snapshot: EnvContextSnapshot): string =
  ## Pure function: compute hash of external state dependencies from a snapshot.
  ## Zero I/O — all values pre-resolved in EnvContextSnapshot.
  if deps.len == 0: return ""
  var parts: seq[string] = @[]
  for dep in deps:
    let prefix = case dep.kind
      of dkGitConfig: "git:"
      of dkEnvVar: "env:"
    let val = snapshot.values.getOrDefault(dep.key, "__AXIOM_MISSING__")
    parts.add(prefix & dep.key & "=" & val)
  if parts.len == 0: return ""
  hash_kernel.sha256Hex(parts.join("|"))

# ─── Gate Partitioning ─────────────────────────────────────────────────────────

func partitionByLayer*(gates: seq[GateConfig]):
    tuple[l1: seq[GateConfig]; l2: seq[GateConfig]] =
  ## Separate L1 (glMeta) from L2 (glFunctional) gates. Zero I/O.
  var l1: seq[GateConfig] = @[]
  var l2: seq[GateConfig] = @[]
  for g in gates:
    if g.layer == glMeta:
      l1.add(g)
    else:
      l2.add(g)
  (l1, l2)

func filterDeferredGates*(gates: seq[GateConfig]):
    tuple[active: seq[GateConfig]; deferredCount: int] =
  ## Separate tier-2 (deferred) from tier-1 (active) gates. Zero I/O.
  ## Logging and early-return logic must stay in the caller.
  var active: seq[GateConfig] = @[]
  var deferredCount = 0
  for g in gates:
    if g.tier == 2:
      inc deferredCount
    else:
      active.add(g)
  (active, deferredCount)

# ─── Ledger Entry Assembly ─────────────────────────────────────────────────────

func buildLedgerEntries*(gates: seq[GateConfig]; epoch: int;
                         stage: GateStage): seq[LedgerEntryTuple] =
  ## Assemble ledger entry sequence for state ledger creation. Zero I/O.
  ## Deterministic: same inputs → same output (no timestamps, no randomness).
  let now = int64(epoch)
  let stageId = case stage
    of gsPreCommit: 0'u8   # lsPreCommit
    of gsPrePush: 1'u8     # lsPrePush
    of gsManual: 0'u8      # default to pre-commit
    of gsCI: 3'u8          # lsCi
    of gsAnyCi: 3'u8       # lsCi (same as gsCI)
  result = @[]
  for g in gates:
    if g.tier == 2:
      result.add((
        gateIdHash: stableHash32(g.id),
        cacheKey: H_VOID,
        result: uint8(lgrDeferred),
        tier: uint8(g.tier),
        deferredAt: now,
        deferredStage: stageId
      ))
    else:
      result.add((
        gateIdHash: stableHash32(g.id),
        cacheKey: H_VOID,
        result: 0'u8,
        tier: uint8(g.tier),
        deferredAt: 0'i64,
        deferredStage: 0'u8
      ))
