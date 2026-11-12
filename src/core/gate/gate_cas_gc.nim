import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## Axiom Gate CAS Garbage Collector
## Retains the newest MaxEntriesPerGate compiled binaries per gate ID under
## .axiom/cache/gates/, deleting older entries once they exceed the retention
## limit. Entries younger than MinCasEntryAgeSec are never deleted, regardless
## of how many exist — the age guard overrides retention.
## Each CAS entry is a subdirectory named <gateId>-<casKey components> under
## .axiom/cache/gates/. Deleted entries are logged before removal.
## Rate-limited: runs at most once per CasGcIntervalSec (1 hour).

import std/os
import std/times
import std/strutils
import std/tables
import std/algorithm
import core/types/results
import core/gate/gate_memo  # GateMemoBaseDir
import core/utils/io_utils
import core/parsers/safe_parsers
import core/interfaces/logging_hub
import core/trusted/axiom_pragmas
# axiomIoBoundary

const
  CasGcIntervalSec* = 3600       ## Minimum seconds between GC runs (1 hour)
  CasGcStateFile* = GateMemoBaseDir / ".cas_gc_last_run"
  CasGatesBaseDir* = ".axiom/cache/gates"
  MaxEntriesPerGate* = 3         ## Newest binaries retained per gate ID
  MinCasEntryAgeSec* = 3600      ## Age before an over-limit entry is eligible for deletion

type
  CasEntry = tuple[path: string, mtime: int64]

# ---------------------------------------------------------------------------
# Rate Limiting
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc shouldRunCasGc*(): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Returns true if CAS GC should run (no state file, stale, or first run).
  try:
    if not fileExists(CasGcStateFile): return true
    let lastRun = safeParseInt(readFile(CasGcStateFile).strip())
    if lastRun.isErr: return true
    return getTime().toUnix() - lastRun.get() >= CasGcIntervalSec
  except CatchableError:
    return true

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc recordCasGcRun*() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Record current timestamp to GC state file for rate limiting.
  try:
    # createDir creates all missing parent directories (existsOrCreateDirOpt
    # does not — it fails when the parent is absent in this environment).
    createDir(GateMemoBaseDir)
    let res = writeFileOpt(CasGcStateFile, $getTime().toUnix() & "\n")
    if res.isErr:
      raise newException(IOError, "failed to record CAS GC state: " & res.error)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

# ---------------------------------------------------------------------------
# CAS Integrity GC
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runCasGc*(repoRoot: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Retain the newest MaxEntriesPerGate CAS entry directories per gate ID.
  ## Group CAS entries under .axiom/cache/gates/ by the gate ID (the name prefix
  ## before the first '-' in each entry directory). For each gate, when there are
  ## more entries than MaxEntriesPerGate, delete the oldest over-limit entries —
  ## but only if they are at least MinCasEntryAgeSec old. Younger entries are kept.
  ## Each deletion is logged before removal.
  try:
    let gatesDir = repoRoot / CasGatesBaseDir
    if not dirExists(gatesDir): return
    let now = getTime().toUnix()
    var entries: seq[CasEntry] = @[]
    for kind, path in walkDir(gatesDir):
      if kind != pcDir: continue
      let name = path.extractFilename()
      if name.startsWith("."): continue
      let mtime =
        try: getLastModificationTime(path).toUnix()
        except CatchableError: now
      entries.add((path, mtime))
    if entries.len == 0: return
    var byGate = initTable[string, seq[CasEntry]]()
    for e in entries:
      let gateId = e.path.extractFilename().split('-')[0]
      byGate.mgetOrPut(gateId, @[]).add(e)
    func newerFirst(a, b: CasEntry): int =
      if a.mtime > b.mtime: -1
      elif a.mtime < b.mtime: 1
      else: 0
    for gateId, group in byGate.mpairs:
      group.sort(newerFirst)
      if group.len <= MaxEntriesPerGate: continue
      for i in MaxEntriesPerGate ..< group.len:
        let age = now - group[i].mtime
        if age < MinCasEntryAgeSec: continue
        logInfo("[CAS-GC] Deleting over-limit " & group[i].path &
                       " (gate " & gateId & ", age " & $age & "s)")
        try:
          removeDir(group[i].path)
        except CatchableError:
          discard  # axiom:best-effort(ioboundary catch)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)

{.pop.}

# Compile-time invariant: CasAddress type safety
static:
  let testContent = """{"gateId":"test","result":true}"""
  let testAddr = computeCasAddress(testContent)
  assert testAddr.isValid(), "CasAddress must produce valid 64-char hex"
  assert testAddr.casSubdir().len == 2, "CAS subdir must be 2 chars"
  assert testAddr.casFilename().len == 62, "CAS filename must be 62 chars"

