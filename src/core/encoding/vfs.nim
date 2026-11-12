import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## tmpfs-backed Virtual File System for Lean 4 proof artifacts.
##
## Q4 Design Decision: tmpfs-backed (RAM disk) for speed and compatibility.
## Lean 4 kernel process requires real filesystem I/O; pure in-memory
## buffers cause pipeline friction. tmpfs gives us RAM speed with
## POSIX file semantics.

import std/os
import std/strutils
import core/utils/io_utils
import core/types/results
import core/trusted/axiom_pragmas
import infrastructure/logging_facade

const
  VfsRoot* = "/dev/shm/axiom_vfs"
  VfsLeanDir* = VfsRoot / "lean"
  VfsZ3Dir* = VfsRoot / "z3"

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc initVfs*() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Create tmpfs directories if they don't exist.
  let leanRes = existsOrCreateDirOpt(VfsLeanDir)
  if not leanRes.isOk:
    logWarn("vfs", "Failed to create lean dir: " & leanRes.error)
  let z3Res = existsOrCreateDirOpt(VfsZ3Dir)
  if not z3Res.isOk:
    logWarn("vfs", "Failed to create z3 dir: " & z3Res.error)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func vfsLeanPath*(moduleName: string; functionName: string): string {.raises: [].} =
  ## Canonical path for a generated Lean 4 theorem.
  ## Individual function unit (Q3); no bundles.
  let safeModule = moduleName.replace("/", "_").replace("\\", "_")
  let safeFunction = functionName.replace("/", "_").replace("\\", "_")
  VfsLeanDir / (safeModule & "__" & safeFunction & ".lean")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func vfsZ3Path*(moduleName: string; functionName: string): string {.raises: [].} =
  ## Canonical path for a Z3 SMT-LIB2 query.
  let safeModule = moduleName.replace("/", "_").replace("\\", "_")
  let safeFunction = functionName.replace("/", "_").replace("\\", "_")
  VfsZ3Dir / (safeModule & "__" & safeFunction & ".smt2")

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeVfsLean*(path: string; content: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write Lean 4 theorem source to VFS.
  let res = writeFileOpt(path, content)
  res.isOk # axiom:best-effort(VFS is scratch; caller retries on empty return)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeVfsZ3*(path: string; content: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Write SMT-LIB2 query to VFS.
  let res = writeFileOpt(path, content)
  res.isOk # axiom:best-effort(VFS is scratch; caller retries on empty return)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc readVfs*(path: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read artifact from VFS.
  let readRes = readFileOpt(path)
  if readRes.isOk: readRes.get else: "" # axiom:best-effort(VFS miss at read; caller validates artifact)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc vfsExists*(path: string): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if artifact exists in VFS.
  try:
    fileExists(path)
  except OSError, IOError:
    false # axiom:best-effort(file existence check; path may be transient)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc clearVfs*() {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Wipe all generated artifacts. Call between proof batches.
  try:
    removeDir(VfsRoot)
  except CatchableError as e:
    logWarn("vfs", "Failed to remove VFS root: " & e.msg)
  let leanRes = existsOrCreateDirOpt(VfsLeanDir)
  if not leanRes.isOk:
    logWarn("vfs", "Failed to recreate lean dir after clear: " & leanRes.error)
  let z3Res = existsOrCreateDirOpt(VfsZ3Dir)
  if not z3Res.isOk:
    logWarn("vfs", "Failed to recreate z3 dir after clear: " & z3Res.error)
{.pop.}

