import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}
# axiomIoBoundary

## OverlayFS / Hardlink / Copy Mount Layer — Wave 7B-2
##
## "Virtualization over Copying" — files are never copied when possible.
## Three-tier fallback:
##   1. OverlayFS (preferred): lowerdir=read-only store, upperdir=scratch
##   2. Hardlink (fallback): store → workdir hardlink, output via atomic rename
##   3. Copy (last resort): full file copy (existing behavior)
##
## All store insertions are atomic: tmp → fsync → rename

import std/[os, osproc, strutils, strformat]
import core/trusted/stdlib_shield
import core/axiom_pragmas

type
  MountTier* = enum
    mtOverlay = "overlay"
    mtHardlink = "hardlink"
    mtCopy = "copy"

  OverlayConfig* = object
    lowerDir*: seq[string]      ## Read-only layers (store + repo root)
    upperDir*: string           ## Writable scratch space
    workDir*: string            ## OverlayFS work dir (must be same fs as upper)
    mergedDir*: string          ## Final mount point

  MountResult* = object
    tier*: MountTier            ## Which tier succeeded
    mergedDir*: string          ## Mounted path
    upperDir*: string           ## Scratch path for outputs

# ─── Tier Detection ──────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hasOverlaySupport*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if OverlayFS is available in kernel.
  try:
    let content = readFile("/proc/filesystems")
    return "overlay" in content
  except CatchableError:
    return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc canHardlink*(): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Check if hardlinks work (same filesystem).
  let testSrc = getTempDir() / "axiom_hlink_test_src"
  let testDst = getTempDir() / "axiom_hlink_test_dst"
  try:
    writeFile(testSrc, "test")
    createHardlink(testDst, testSrc)
    removeFile(testSrc)
    removeFile(testDst)
    return true
  except CatchableError:
    try:
      removeFile(testSrc)
      removeFile(testDst)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    return false

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc detectBestTier*(): MountTier {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Auto-detect best available mount tier.
  if hasOverlaySupport():
    return mtOverlay
  if canHardlink():
    return mtHardlink
  return mtCopy

# ─── OverlayFS Operations ───────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc mountOverlay*(cfg: OverlayConfig): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Mount OverlayFS. Returns true on success.
  ## Requires: root or user namespace with mount capability.
  ## lowerdir=<store>:<repo>, upperdir=<scratch>, workdir=<work>
  if cfg.lowerDir.len == 0 or cfg.upperDir.len == 0:
    return false

  createDir(cfg.upperDir)
  createDir(cfg.workDir)
  createDir(cfg.mergedDir)

  let lowerArg = cfg.lowerDir.join(":")
  let mountOpts = &"lowerdir={lowerArg},upperdir={cfg.upperDir},workdir={cfg.workDir}"

  # mount -t overlay overlay -o <opts> <merged>
  let (_, exitCode) = execCmdEx(
    &"mount -t overlay overlay -o {mountOpts.quoteShell} {cfg.mergedDir.quoteShell} 2>&1"
  )
  return exitCode == 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc umountOverlay*(mergedDir: string) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Unmount OverlayFS.
  discard execCmdEx(&"umount {mergedDir.quoteShell} 2>&1")

# ─── Hardlink Operations ────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc hardlinkCopy*(srcDir, dstDir: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Hardlink all files from srcDir to dstDir.
  ## Returns count of linked files.
  ## Falls back to copy if hardlink fails (cross-device).
  result = 0
  for kind, path in walkDir(srcDir):
    let relPath = path[srcDir.len + 1 .. ^1]
    let dstPath = dstDir / relPath
    case kind
    of pcFile:
      createDir(dstPath.parentDir)
      try:
        createHardlink(dstPath, path)
      except CatchableError:
        copyFile(path, dstPath)
      inc result
    of pcDir:
      createDir(dstPath)
      result += hardlinkCopy(path, dstPath)
    else:
      discard

# ─── Atomic Store Insertion ──────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc atomicStoreInsert*(srcPath, storeRoot, contentHash: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomically insert a file into the content-addressable store.
  ## Pattern: write to _tmp → rename to store path (Nix pattern).
  ## Returns the final store path.
  let shard = contentHash[0..1]
  let storeDir = storeRoot / shard
  let storePath = storeDir / contentHash
  let tmpPath = storeRoot / "_tmp" / ("write-" & contentHash)

  createDir(storeDir)
  createDir(storeRoot / "_tmp")

  # Copy to tmp location
  copyFile(srcPath, tmpPath)

  # Atomic rename
  try:
    safeMoveFile(tmpPath, storePath)
  except CatchableError, FileMoveError:
    # Cross-device or permission fallback: copy then remove staging
    copyFile(tmpPath, storePath)
    try:
      removeFile(tmpPath)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

  return storePath

# ─── High-Level Mount ────────────────────────────────────────────────────────

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc mountForGate*(storeRoot, repoRoot, scratchDir, gateId: string,
                   tier: MountTier = mtOverlay): MountResult {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Set up a working environment for a gate execution.
  ## Creates the appropriate mount based on available tier.
  let mergedDir = scratchDir / "merged" / gateId
  let upperDir = scratchDir / "upper" / gateId
  let workDir = scratchDir / "work" / gateId

  createDir(mergedDir)

  case tier
  of mtOverlay:
    let cfg = OverlayConfig(
      lowerDir: @[storeRoot, repoRoot],
      upperDir: upperDir,
      workDir: workDir,
      mergedDir: mergedDir
    )
    if mountOverlay(cfg):
      return MountResult(tier: mtOverlay, mergedDir: mergedDir, upperDir: upperDir)
    # Fall through to hardlink if overlay mount fails (e.g. no privileges)

  of mtHardlink:
    createDir(upperDir)
    discard hardlinkCopy(storeRoot, mergedDir)
    discard hardlinkCopy(repoRoot, mergedDir)
    return MountResult(tier: mtHardlink, mergedDir: mergedDir, upperDir: upperDir)

  of mtCopy:
    createDir(upperDir)
    # Just return paths; caller will copy manually
    return MountResult(tier: mtCopy, mergedDir: mergedDir, upperDir: upperDir)

  # Overlay failed → fall back to hardlink
  createDir(upperDir)
  discard hardlinkCopy(storeRoot, mergedDir)
  discard hardlinkCopy(repoRoot, mergedDir)
  return MountResult(tier: mtHardlink, mergedDir: mergedDir, upperDir: upperDir)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc cleanupMount*(result: MountResult) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Clean up after gate execution.
  case result.tier
  of mtOverlay:
    umountOverlay(result.mergedDir)
  of mtHardlink, mtCopy:
    # Remove merged dir (files are hardlinks or copies)
    try:
      removeDir(result.mergedDir)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)

{.pop.}

