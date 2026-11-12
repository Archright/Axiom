import core/trusted/layer_declaration
axiomLayer "gate"
import infrastructure/logger
{.push raises: [CatchableError].}

## DEBT#419: dir_doc_debt_audit_2026-08-17 grounded 1046 findings in bin/ —
## committed test/scratch ELF binaries without a doc/ownership policy.

## Binary Artifact Gate
##
## Pre-commit gate that blocks binary artifacts (ELF, PE, Mach-O executables)
## and zero-byte files from being committed. Also validates Git LFS pointer
## integrity — files with `filter=lfs` must contain valid LFS pointers, not
## raw binary content.
##
## Exit 0: no banned files found.
## Exit 1: banned files listed on stderr.

import std/os
import std/osproc
import std/streams
import std/strutils
import core/axiom_pragmas
const debtMarker419 {.axiomDebt: "DEBT#419".} = true
import core/utils/repo_root
import core/gate/gate_vfs
import infrastructure/logging_facade


# axiomIoBoundary

const
  GateName* = "binary-artifact-gate"
  MagicLen = 4  ## Longest magic prefix we inspect (ELF / Mach-O).

  ElfMagic    = "\x7fELF"
  PeMagic     = "MZ"
  MachoMagic1 = "\xcf\xfa\xed\xfe"  ## 64-bit Mach-O
  MachoMagic2 = "\xce\xfa\xed\xfe"  ## 32-bit Mach-O

  ## Maximum file size (bytes) for LFS pointer check. A valid LFS pointer
  ## is ~130 bytes; anything larger with `filter=lfs` is a violation.
  LfsPointerMaxBytes = 256

type
  BlockReason = enum
    reasonZeroByte    ## File is 0 bytes.
    reasonElf         ## ELF binary detected.
    reasonPe          ## PE/COFF binary detected.
    reasonMacho       ## Mach-O binary detected.
    reasonLfsViolation ## filter=lfs but file is not a valid LFS pointer.

  BlockedFile = object
    path: string
    reason: BlockReason

func reasonLabel(r: BlockReason): string =
  case r
  of reasonZeroByte:   "zero-byte file"
  of reasonElf:        "ELF binary"
  of reasonPe:         "PE/COFF binary"
  of reasonMacho:      "Mach-O binary"
  of reasonLfsViolation: "LFS pointer violation"

proc getStagedFiles(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Get list of staged file names from `git diff --cached --name-only`.
  let p = startProcess("git", args = @["diff", "--cached", "--name-only"],
                       options = {poStdErrToStdOut, poUsePath})
  let output = p.outputStream().readAll()
  let rc = p.waitForExit()
  p.close()
  if rc != 0:
    logError("binary_artifact_gate", "[" & $(GateName) & "] WARN — git diff --cached failed (exit " & $(rc) & ")")
    return @[]
  result = @[]
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)

proc isLfsTracked(filePath: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Check if a file has `filter=lfs` via `git check-attr filter`.
  let p = startProcess("git", args = @["check-attr", "filter", "--", filePath],
                       options = {poStdErrToStdOut, poUsePath})
  let output = p.outputStream().readAll()
  let rc = p.waitForExit()
  p.close()
  ## Output format: "path/to/file: filter: lfs" or "…: filter: unset"
  result = (rc == 0) and ("lfs" in output)

proc isLfsPointerValid(filePath: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Validate LFS pointer via `git lfs pointer --check --stdin`.
  ## Returns true if the file content is a valid LFS pointer.
  let p = startProcess("git", args = @["lfs", "pointer", "--check", "--stdin"],
                       options = {poStdErrToStdOut, poUsePath})
  # Pipe file content to stdin
  var f: File
  if open(f, filePath, fmRead):
    try:
      var buf: array[4096, byte]
      while true:
        let n = readBuffer(f, addr buf[0], buf.len)
        if n == 0: break
        var chunk = newString(n)
        copyMem(addr chunk[0], unsafeAddr buf[0], n)
        p.inputStream().write(chunk)
    finally:
      close(f)
  p.inputStream().close()
  let rc = p.waitForExit()
  p.close()
  ## git lfs pointer --check exits 0 for valid pointers, 1 otherwise.
  result = rc == 0

proc detectBinaryMagic(filePath: string): BlockReason =
  ## Read first 4 bytes and classify. Returns the matching reason
  ## or raises on read failure.
  let f = open(filePath, fmRead)
  try:
    var header: array[MagicLen, byte]
    let bytesRead = readBuffer(f, addr header[0], MagicLen)
    if bytesRead >= 4:
      let h = header[0..3]
      if h == [byte 0x7f, 0x45, 0x4c, 0x46]:  # \x7fELF
        return reasonElf
      if h == [byte 0xcf, 0xfa, 0xed, 0xfe]:  # Mach-O 64-bit
        return reasonMacho
      if h == [byte 0xce, 0xfa, 0xed, 0xfe]:  # Mach-O 32-bit
        return reasonMacho
    if bytesRead >= 2:
      let h2 = header[0..1]
      if h2 == [byte 0x4d, 0x5a]:  # MZ (PE)
        return reasonPe
  finally:
    close(f)
  ## No magic match — not a known binary.
  raise newException(CatchableError, "no binary magic found")

proc checkFile(filePath: string): seq[BlockedFile] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  ## Inspect a single staged file for all violation categories.
  result = @[]

  # ── File existence ──────────────────────────────────────────────────────
  if not fileExists(filePath):
    return  # Deleted or untracked — nothing to check.

  # ── Zero-byte detection ─────────────────────────────────────────────────
  let size = getFileSize(filePath)
  if size == 0:
    result.add(BlockedFile(path: filePath, reason: reasonZeroByte))
    return

  # ── Binary magic detection ──────────────────────────────────────────────
  if size >= MagicLen:
    try:
      let reason = detectBinaryMagic(filePath)
      result.add(BlockedFile(path: filePath, reason: reason))
      return
    except CatchableError:
      discard  # Not a recognized binary — continue to LFS check.  # axiom:best-effort(ioboundary catch)

  # ── LFS pointer integrity ──────────────────────────────────────────────
  if isLfsTracked(filePath):
    if size > LfsPointerMaxBytes:
      ## File exceeds max LFS pointer size — definitely not a valid pointer.
      result.add(BlockedFile(path: filePath, reason: reasonLfsViolation))
    elif not isLfsPointerValid(filePath):
      result.add(BlockedFile(path: filePath, reason: reasonLfsViolation))

proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, ExecIOEffect, RootEffect].} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  # Collect staged files: from CLI args or git diff.
  var files: seq[string]
  if paramCount() > 0:
    files = @[]
    for i in 1..paramCount():
      files.add(paramStr(i))
  else:
    files = getStagedFiles()

  if files.len == 0:
    logger.info("[" & GateName & "] PASS — no staged files to check")
    quit(0)

  var blocked: seq[BlockedFile]
  for f in files:
    blocked.add(checkFile(f))

  if blocked.len == 0:
    logger.info("[" & $GateName & "] PASS — " & $files.len & " staged file(s) clean")
    quit(0)
  else:
    logError("binary_artifact_gate", "[" & $(GateName) & "] BLOCK — " & $(blocked.len) & " file(s) contain binary artifacts or violations:")
    for b in blocked:
      logInfo("binary_artifact_gate", "  " & $(b.path) & " (" & $(reasonLabel(b.reason)) & ")")
    logError("binary_artifact_gate", "[" & $(GateName) & "] Blocked files must not be committed. " & "Use Git LFS for binary files.")
    logInfo("binary_artifact_gate", "[" & $(GateName) & "] Emergency override: " & "AXIOM_EMERGENCY_NO_VERIFY=1 git commit --no-verify")
    quit(1)

# ---------------------------------------------------------------------------
# VFS-aware helpers (Wave 5D-1)
# ---------------------------------------------------------------------------

proc getStagedFilesVfs(ctx: GateContext): seq[string] =
  ## Get staged files via VFS subprocess provider.
  let res = vfsExec(ctx, "git", @["diff", "--cached", "--name-only"])
  if res.exitCode != 0:
    logError("binary_artifact_gate", "[" & $(GateName) & "] WARN — git diff --cached failed (exit " & $(res.exitCode) & ")")
    return @[]
  result = @[]
  for line in res.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)

func isLfsTrackedVfs(ctx: GateContext; filePath: string): bool =
  ## Check LFS tracking via VFS subprocess provider.
  let res = vfsExec(ctx, "git", @["check-attr", "filter", "--", filePath])
  (res.exitCode == 0) and ("lfs" in res.output)

proc mainWithVfs(ctx: GateContext) =
  ## VFS-aware entry point for pipeline orchestrator integration.
  setCurrentDir(ctx.repoRoot)

  var files: seq[string]
  if paramCount() > 0:
    files = @[]
    for i in 1..paramCount():
      files.add(paramStr(i))
  else:
    files = getStagedFilesVfs(ctx)

  if files.len == 0:
    logger.info("[" & GateName & "] PASS — no staged files to check")
    quit(0)

  var blocked: seq[BlockedFile]
  for f in files:
    blocked.add(checkFile(f))

  if blocked.len == 0:
    logger.info("[" & $GateName & "] PASS — " & $files.len & " staged file(s) clean")
    quit(0)
  else:
    logError("binary_artifact_gate", "[" & $(GateName) & "] BLOCK — " & $(blocked.len) & " file(s) contain binary artifacts or violations:")
    for b in blocked:
      logInfo("binary_artifact_gate", "  " & $(b.path) & " (" & $(reasonLabel(b.reason)) & ")")
    logError("binary_artifact_gate", "[" & $(GateName) & "] Blocked files must not be committed. " & "Use Git LFS for binary files.")
    logInfo("binary_artifact_gate", "[" & $(GateName) & "] Emergency override: " & "AXIOM_EMERGENCY_NO_VERIFY=1 git commit --no-verify")
    quit(1)

when isMainModule:
  main()

{.pop.}
