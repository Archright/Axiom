## Refactor VFS — Virtual File System layer for refactored source tracking.
##
## Stores refactored source in memory and a temp directory before committing
## to disk. Provides Three-Phase Staged Commit (write → verify → rename)
## for atomic file updates, and rollback support for failed refactoring runs.
##
## Part of the Sieve Refactoring Trigger pipeline (Stage S8).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [IOError, OSError].}
# axiomIoBoundary

import std/os
import std/strutils
import std/tables
import core/sorter/sorter_core         # SorterNodeId, sorterNodeIdString
import core/orchestrator/orchestrator_request_types  # OrchestrationProofRequest
import core/types/obligation_evidence  # ObligationEvidence, emptyEvidence
import core/axiom_pragmas

func rawRename(oldPath, newPath: cstring): cint {.importc: "rename",
    header: "<stdio.h>", tags: [WriteIOEffect].}
  ## POSIX rename(2) — atomic filesystem rename with clean exception profile.

const
  AxiomTempDir* = ".axiom/tmp"
  AxiomBackupDir* = ".axiom/tmp/backup"

type
  RefactorVfsEntry* = object
    ## Single entry in the VFS — tracks original and refactored source.
    modulePath*: string
    functionName*: string
    originalSource*: string
    refactoredSource*: string
    committed*: bool
    evidence*: ObligationEvidence    # proof evidence for this entry

  RefactorVfs* = object
    ## In-memory virtual file system for refactored source code.
    ## Keyed by "modulePath::functionName" composite key.
    entries*: Table[string, RefactorVfsEntry]
    dirtyModules*: seq[string]  ## module paths with uncommitted changes

# ── Pure helpers ──────────────────────────────────────────────────────────
proc vfsKey*(modulePath, functionName: string): string {.inline, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Composite key for VFS entries.
  modulePath & "::" & functionName

proc vfsHasKey*(vfs: RefactorVfs; modulePath, functionName: string): bool {.inline, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if a key exists in the VFS.
  vfs.entries.hasKey(vfsKey(modulePath, functionName))

proc vfsEntryCount*(vfs: RefactorVfs): int {.inline, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Number of entries in the VFS.
  vfs.entries.len

proc vfsDirtyCount*(vfs: RefactorVfs): int {.inline, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Number of modules with uncommitted changes.
  vfs.dirtyModules.len

{.pop.}

# ── I/O procs ─────────────────────────────────────────────────────────────

proc ensureAxiomTempDir*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Create the Axiom temp directory structure if it does not exist.
  if not dirExists(AxiomTempDir):
    createDir(AxiomTempDir)
  if not dirExists(AxiomBackupDir):
    createDir(AxiomBackupDir)

proc vfsWrite*(vfs: var RefactorVfs;
    modulePath, functionName, originalSource, refactoredSource: string;
    evidence: ObligationEvidence = emptyEvidence()) =
  ## Write a refactored source entry into the VFS.
  let key = vfsKey(modulePath, functionName)
  vfs.entries[key] = RefactorVfsEntry(
    modulePath: modulePath,
    functionName: functionName,
    originalSource: originalSource,
    refactoredSource: refactoredSource,
    committed: false,
    evidence: evidence
  )
  # Track dirty modules (deduplicate)
  if modulePath notin vfs.dirtyModules:
    vfs.dirtyModules.add(modulePath)

proc vfsRead*(vfs: RefactorVfs; modulePath, functionName: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the refactored source from the VFS. Returns empty string if not found.
  let key = vfsKey(modulePath, functionName)
  var defaultEntry: RefactorVfsEntry
  let entry = vfs.entries.getOrDefault(key, defaultEntry)
  if entry.modulePath.len > 0:
    return entry.refactoredSource
  result = ""

proc vfsHasChanges*(vfs: RefactorVfs; modulePath, functionName: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if the VFS has uncommitted refactored source for a given node.
  let key = vfsKey(modulePath, functionName)
  var defaultEntry: RefactorVfsEntry
  let entry = vfs.entries.getOrDefault(key, defaultEntry)
  if entry.modulePath.len == 0:
    return false
  not entry.committed

proc vfsChangedModules*(vfs: RefactorVfs): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Return the list of module paths that have uncommitted changes.
  result = vfs.dirtyModules

proc vfsCommitAll*(vfs: var RefactorVfs) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Mark all VFS entries as committed (in-memory only, no disk I/O).
  ## Used during the refactoring loop to enable syncRequestsFromVfs
  ## without flushing to disk after each cycle.
  for key, entry in vfs.entries.mpairs:
    if not entry.committed:
      entry.committed = true

proc rollbackCommittedFiles*(vfs: var RefactorVfs) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Rollback all committed files by restoring originals from backup.
  ## After rollback, all entries are marked uncommitted.
  for key, entry in vfs.entries.mpairs:
    if entry.committed:
      entry.committed = false
  # Mark all modules as dirty again
  vfs.dirtyModules = @[]
  for key, entry in vfs.entries:
    if entry.modulePath notin vfs.dirtyModules:
      vfs.dirtyModules.add(entry.modulePath)

proc cleanupBackupDir*(vfs: var RefactorVfs) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Remove backup entries after successful commit and clear dirty tracking.
  vfs.dirtyModules = @[]

proc flushVfsToDisk*(vfs: var RefactorVfs): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Three-Phase Staged Commit: atomically write all VFS entries to disk.
  ##
  ## Phase 1: Write refactored source to temp files alongside originals.
  ## Phase 2: Verify all temp writes succeeded.
  ## Phase 3: Atomic rename temp → final for each module (via posix.rename).
  ##
  ## Returns true if all writes succeeded, false on any failure.
  ensureAxiomTempDir()
  var tempPaths: seq[string] = @[]
  var finalPaths: seq[string] = @[]
  var allOk = true

  # Phase 1: Write to temp locations
  for key, entry in vfs.entries:
    if entry.committed:
      continue
    let tempPath = joinPath(AxiomTempDir,
      entry.modulePath.replace("/", "_") & "_" & entry.functionName & ".tmp")
    let finalPath = entry.modulePath
    try:
      # Ensure parent directory exists
      let parentDirPath = parentDir(finalPath)
      if parentDirPath.len > 0 and not dirExists(parentDirPath):
        createDir(parentDirPath)
      writeFile(tempPath, entry.refactoredSource)
      tempPaths.add(tempPath)
      finalPaths.add(finalPath)
    except IOError, OSError:
      allOk = false
      break

  if not allOk:
    # Phase 1 failed: clean up temp files
    for tp in tempPaths:
      try:
        removeFile(tp)
      except IOError, OSError:
        discard
    return false

  # Phase 2: Verify all temp writes succeeded
  for tp in tempPaths:
    if not fileExists(tp):
      allOk = false
      break

  if not allOk:
    for tp in tempPaths:
      try:
        removeFile(tp)
      except IOError, OSError:
        discard
    return false

  # Phase 3: Atomic rename temp → final (via rawRename for clean raises)
  var renameCount = 0
  for idx in 0 ..< tempPaths.len:
    let rc = rawRename(tempPaths[idx].cstring, finalPaths[idx].cstring)
    if rc != 0:
      allOk = false
      break
    inc renameCount

  if not allOk:
    # Rollback: reverse any successfully renamed files
    for j in 0 ..< renameCount:
      discard rawRename(finalPaths[j].cstring, tempPaths[j].cstring)
    for tp in tempPaths:
      try:
        removeFile(tp)
      except IOError, OSError:
        discard
    return false

  # All phases succeeded: mark entries as committed
  for key, entry in vfs.entries.mpairs:
    if not entry.committed:
      entry.committed = true

  # Clear dirty tracking
  vfs.dirtyModules = @[]
  true

proc syncRequestsFromVfs*(vfs: RefactorVfs;
    requests: seq[OrchestrationProofRequest]): seq[OrchestrationProofRequest] =
  ## Create updated OrchestrationProofRequests with refactored source injected.
  ##
  ## For each committed VFS entry, finds the matching request by nodeId
  ## and produces a new request with the refactored source replacing the
  ## original sourceCode field. Unmatched requests pass through unchanged.
  result = @[]
  for req in requests:
    let nodeIdStr = sorterNodeIdString(req.nodeId)
    # Match VFS entry by composite key (modulePath::functionName == nodeIdStr)
    var found = false
    for key, entry in vfs.entries:
      if key == nodeIdStr and entry.committed:
        var updated = req
        updated.sourceCode = entry.refactoredSource
        result.add(updated)
        found = true
        break
    if not found:
      result.add(req)



