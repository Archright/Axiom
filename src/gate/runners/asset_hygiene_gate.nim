import core/trusted/layer_declaration
axiomLayer "gate"
import ../utils/real_git
import core/axiom_pragmas
import core/gate/gate_vfs
import core/types/results
import core/utils/axiom_error
import core/utils/repo_root
import infrastructure/logger
import std/algorithm
import std/json
import std/os
import std/osproc
import std/strutils
import infrastructure/logging_facade



# Merged from magic-number-sniffer: magic byte detection
type
  MagicSignature = object
    magic: string
    description: string

func magicSignatures(): seq[MagicSignature] =
  result.add(MagicSignature(magic: "\x7fELF", description: "ELF executable/object"))
  result.add(MagicSignature(magic: "MZ", description: "PE executable/DLL"))
  result.add(MagicSignature(magic: "\xfe\xed\xfa\xcf", description: "Mach-O 32-bit"))
  result.add(MagicSignature(magic: "\xcf\xfa\xed\xfe", description: "Mach-O 64-bit"))
  result.add(MagicSignature(magic: "\xca\xfe\xba\xbe", description: "Mach-O universal/fat"))
  result.add(MagicSignature(magic: "\x89PNG\r\n\x1a\n", description: "PNG image"))
  result.add(MagicSignature(magic: "\xff\xd8\xff", description: "JPEG image"))
  result.add(MagicSignature(magic: "GIF87a", description: "GIF image"))
  result.add(MagicSignature(magic: "GIF89a", description: "GIF image"))
  result.add(MagicSignature(magic: "%PDF", description: "PDF document"))
  result.add(MagicSignature(magic: "PK\x03\x04", description: "ZIP archive (docx/xlsx/jar/apk/etc.)"))
  result.add(MagicSignature(magic: "PK\x05\x06", description: "ZIP archive (empty)"))
  result.add(MagicSignature(magic: "PK\x07\x08", description: "ZIP archive"))
  result.add(MagicSignature(magic: "Rar!", description: "RAR archive"))
  result.add(MagicSignature(magic: "\x1f\x8b", description: "gzip archive"))
  result.add(MagicSignature(magic: "BZh", description: "bzip2 archive"))
  result.add(MagicSignature(magic: "\xfd7zXZ", description: "XZ archive"))
  result.add(MagicSignature(magic: "\x00\x00\x00\x20ftyp", description: "MP4/M4V video"))
  result.add(MagicSignature(magic: "\x00\x00\x00\x18ftyp", description: "MP4/M4V video"))
  result.add(MagicSignature(magic: "\x00\x00\x00\x14ftyp", description: "MP4/M4V video"))
  result.add(MagicSignature(magic: "\x00\x00\x00\x0cftyp", description: "MP4/M4V video"))
  result.add(MagicSignature(magic: "ID3", description: "MP3 audio"))
  result.add(MagicSignature(magic: "fLaC", description: "FLAC audio"))
  result.add(MagicSignature(magic: "OggS", description: "OGG audio"))
  result.add(MagicSignature(magic: "RIFF", description: "RIFF media (avi/wav/webp)"))

proc detectMagicBytes(filePath: string): Result[string, AxiomError] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], raises: [].} =
  try:
    let size = getFileSize(filePath)
    if size == 0:
      return ok("")
    var f: File
    if not open(f, filePath, fmRead):
      return ok("")
    defer: close(f)
    var header: array[32, byte]
    let bytesRead = readBuffer(f, addr header[0], 32)
    if bytesRead == 0:
      return ok("")
    var headerStr = newString(bytesRead)
    for i in 0 ..< bytesRead: headerStr[i] = char(header[i])
    for sig in magicSignatures():
      if headerStr.startsWith(sig.magic):
        return ok(sig.description)
    ok("")
  except CatchableError as e:
    err(ioError("detectMagicBytes(" & filePath & "): " & e.msg))

# axiomIoBoundary

let gitExe = findRealGit()

axiomIoBoundary()
const
  GateTag = "[asset-hygiene]"
  BaselineRelPath = "data/asset_hygiene_baseline.json"

  LfsSizeLimit = 15 * 1024 * 1024   ## 15 MiB
  NonLfsSizeLimit = 10 * 1024        ## 10 KiB

  ## Extensions that must be LFS-tracked when larger than the small-icon threshold.
  LfsRequiredExtensions: array[31, string] = [
    ".pdf", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif",
    ".ico", ".mp3", ".mp4", ".avi", ".mov", ".mkv", ".webm",
    ".zip", ".tar", ".gz", ".bz2", ".xz", ".rar", ".7z",
    ".bin", ".so", ".dll", ".dylib", ".exe", ".o", ".a", ".lib",
  ]
type
  Findings = object
    untrackedBinaries: seq[string]
    oversizedLfs: seq[string]
    oversizedNonLfs: seq[string]
    zeroByteFiles: seq[string]
func isLfsRequiredExtension(ext: string): bool =
  for e in LfsRequiredExtensions:
    if ext == e:
      return true
  false
proc gitLsFiles(repoRoot: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (output, exitCode) = execCmdEx(gitExe & " ls-files", workingDir = repoRoot)
  if exitCode != 0:
    logError("asset_hygiene_gate", $(GateTag) & " WARN: git ls-files failed (exit " & $(exitCode) & ")")
    return @[]
  result = @[]
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)
proc isLfsTracked(repoRoot: string, relPath: string): bool {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let (output, exitCode) = execCmdEx(
    "git check-attr filter -- " & relPath, workingDir = repoRoot
  )
  result = (exitCode == 0) and ("filter: lfs" in output)
proc scanAssets(repoRoot: string): Findings {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let files = gitLsFiles(repoRoot)
  for rel in files:
    let fullPath = repoRoot / rel
    if not fileExists(fullPath):
      continue
    let size = getFileSize(fullPath)
    if size == 0:
      result.zeroByteFiles.add(rel)
      continue

    let (_, _, ext) = splitFile(fullPath)
    let lowerExt = ext.toLowerAscii()
    if isLfsRequiredExtension(lowerExt):
      if isLfsTracked(repoRoot, rel):
        if size > LfsSizeLimit:
          result.oversizedLfs.add(rel & " (" & $size & " bytes)")
      else:
        if size > NonLfsSizeLimit:
          result.untrackedBinaries.add(rel & " (" & $size & " bytes)")

    let magicRes = detectMagicBytes(fullPath)
    if magicRes.isErr:
      logError("asset_hygiene_gate", $(GateTag) & " detectMagicBytes failed for " & rel & ": " & magicRes.error.message)
    else:
      let magicDetection = magicRes.get()
      if magicDetection.len > 0 and not isLfsTracked(repoRoot, rel) and not (lowerExt in [".ico",".png",".jpg",".jpeg",".gif",".webp",".bmp",".tiff",".tif"] and size <= 10240):
        result.untrackedBinaries.add(rel & " (magic: " & magicDetection & ")")
func countFindings(f: Findings): seq[(string, int)] =
  result.add(("untracked_binaries", f.untrackedBinaries.len))
  result.add(("oversized_lfs", f.oversizedLfs.len))
  result.add(("oversized_non_lfs", f.oversizedNonLfs.len))
  result.add(("zero_byte_files", f.zeroByteFiles.len))
proc loadBaseline(repoRoot: string): Result[seq[(string, int)], AxiomError] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let baselinePath = repoRoot / BaselineRelPath
  if not fileExists(baselinePath):
    return ok(newSeq[(string, int)]())
  try:
    let data = parseJson(readFile(baselinePath))
    let counts = data["counts"]
    var keys: seq[string] = @[]
    for k in counts.keys:
      keys.add(k)
    keys.sort()
    var res: seq[(string, int)]
    for k in keys:
      res.add((k, counts[k].getInt()))
    ok(res)
  except CatchableError as e:
    err(ioError("loadBaseline: " & e.msg))
func getBaselineValue(baseline: seq[(string, int)], key: string): int =
  for (k, v) in baseline:
    if k == key:
      return v
  0
func getFindingItems(f: Findings, key: string): seq[string] =
  case key
  of "untracked_binaries": f.untrackedBinaries
  of "oversized_lfs": f.oversizedLfs
  of "oversized_non_lfs": f.oversizedNonLfs
  of "zero_byte_files": f.zeroByteFiles
  else: @[]
proc saveBaseline(repoRoot: string, counts: seq[(string, int)]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let baselinePath = repoRoot / BaselineRelPath
  let parentDir = baselinePath.parentDir()
  if not dirExists(parentDir):
    createDir(parentDir)
  var countsObj = newJObject()
  for (k, v) in counts:
    countsObj[k] = newJInt(v)
  let payload = %*{
    "counts": countsObj,
    "note": "Auto-generated by tools/ci/asset_hygiene_gate.py --update-baseline"
  }
  writeFile(baselinePath, $payload & "\n")
proc main() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)

  var updateBaseline = false
  for i in 1 .. paramCount():
    if paramStr(i) == "--update-baseline":
      updateBaseline = true
      break

  let findings = scanAssets(repoRoot)
  let currentCounts = countFindings(findings)

  if updateBaseline:
    saveBaseline(repoRoot, currentCounts)
    logger.info $GateTag & " Baseline updated:"
    for (key, value) in currentCounts:
      logger.info("  " & $key & ": " & $value)
    logger.info $GateTag & " Stage and commit " & $BaselineRelPath & "."
    quit(0)

  let baselineRes = loadBaseline(repoRoot)
  if baselineRes.isErr:
    logError("asset_hygiene_gate", $(GateTag) & " loadBaseline failed: " & baselineRes.error.message)
    quit(1)
  let baseline = baselineRes.get()
  logger.info $GateTag & " Current asset hygiene:"
  for (key, value) in currentCounts:
    let base = getBaselineValue(baseline, key)
    logger.info("  " & $key & ": current=" & $value & " baseline=" & $base)

  var failed = false
  for (key, value) in currentCounts:
    let base = getBaselineValue(baseline, key)
    if value > base:
      logError("asset_hygiene_gate", $(GateTag) & " FAIL: " & $(key) & " increased (" & $(value) & " > " & $(base) & ").")
      let items = getFindingItems(findings, key)
      for item in items[0 .. min(9, items.high)]:
        logInfo("asset_hygiene_gate", "    - " & $(item))
      if items.len > 10:
        logInfo("asset_hygiene_gate", "    ... and " & $(items.len - 10) & " more")
      failed = true

  if failed:
    logInfo("asset_hygiene_gate", $(GateTag) & " Add binary files via Git LFS or reduce their size.")
    quit(1)

  logger.info $GateTag & " PASS: asset hygiene ratchet holds."
  quit(0)

# ---------------------------------------------------------------------------
# VFS-aware helpers
# ---------------------------------------------------------------------------
proc gitLsFilesVfs(ctx: GateContext): seq[string] =
  ## List tracked files via VFS subprocess provider.
  let res = vfsExec(ctx, "git", @["ls-files"])
  if res.exitCode != 0:
    logError("asset_hygiene_gate", $(GateTag) & " WARN: git ls-files failed (exit " & $(res.exitCode) & ")")
    return @[]
  result = @[]
  for line in res.output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add(trimmed)
func isLfsTrackedVfs(ctx: GateContext; relPath: string): bool =
  ## Check LFS tracking via VFS subprocess provider.
  let res = vfsExec(ctx, "git", @["check-attr", "filter", "--", relPath])
  result = (res.exitCode == 0) and ("filter: lfs" in res.output)
proc scanAssetsVfs(ctx: GateContext; repoRoot: string): Findings =
  ## Scan assets using VFS for git commands and file existence checks.
  let files = gitLsFilesVfs(ctx)
  for rel in files:
    # Use vfsExists to check file presence in VFS (built from git index).
    if not vfsExists(ctx, rel):
      continue
    # NOTE: getFileSize requires real filesystem — VFS does not store binary
    # content or metadata. We fall back to real filesystem for size checks.
    let fullPath = repoRoot / rel
    if not fileExists(fullPath):
      continue
    let size = getFileSize(fullPath)
    if size == 0:
      result.zeroByteFiles.add(rel)
      continue

    let (_, _, ext) = splitFile(fullPath)
    let lowerExt = ext.toLowerAscii()
    if isLfsRequiredExtension(lowerExt):
      if isLfsTrackedVfs(ctx, rel):
        if size > LfsSizeLimit:
          result.oversizedLfs.add(rel & " (" & $size & " bytes)")
      else:
        if size > NonLfsSizeLimit:
          result.untrackedBinaries.add(rel & " (" & $size & " bytes)")
proc loadBaselineVfs(ctx: GateContext; repoRoot: string): Result[seq[(string, int)], AxiomError] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load baseline via VFS file read.
  let baselineRel = BaselineRelPath
  if not vfsExists(ctx, baselineRel):
    return ok(newSeq[(string, int)]())
  try:
    let data = parseJson(vfsRead(ctx, baselineRel))
    let counts = data["counts"]
    var keys: seq[string] = @[]
    for k in counts.keys:
      keys.add(k)
    keys.sort()
    var res: seq[(string, int)]
    for k in keys:
      res.add((k, counts[k].getInt()))
    ok(res)
  except CatchableError as e:
    err(ioError("loadBaselineVfs: " & e.msg))
proc mainWithVfs(ctx: GateContext) =
  ## VFS entry point. Compares asset hygiene against baseline.
  setCurrentDir(ctx.repoRoot)

  var updateBaseline = false
  for i in 1 .. paramCount():
    if paramStr(i) == "--update-baseline":
      updateBaseline = true
      break

  let findings = scanAssetsVfs(ctx, ctx.repoRoot)
  let currentCounts = countFindings(findings)

  if updateBaseline:
    # writeFile stays on real filesystem (VFS is read-only for writes)
    saveBaseline(ctx.repoRoot, currentCounts)
    logger.info $GateTag & " Baseline updated:"
    for (key, value) in currentCounts:
      logger.info("  " & $key & ": " & $value)
    logger.info $GateTag & " Stage and commit " & $BaselineRelPath & "."
    quit(0)

  let baselineRes = loadBaselineVfs(ctx, ctx.repoRoot)
  if baselineRes.isErr:
    logError("asset_hygiene_gate", $(GateTag) & " loadBaselineVfs failed: " & baselineRes.error.message)
    quit(1)
  let baseline = baselineRes.get()
  logger.info $GateTag & " Current asset hygiene:"
  for (key, value) in currentCounts:
    let base = getBaselineValue(baseline, key)
    logger.info("  " & $key & ": current=" & $value & " baseline=" & $base)

  var failed = false
  for (key, value) in currentCounts:
    let base = getBaselineValue(baseline, key)
    if value > base:
      logError("asset_hygiene_gate", $(GateTag) & " FAIL: " & $(key) & " increased (" & $(value) & " > " & $(base) & ").")
      let items = getFindingItems(findings, key)
      for item in items[0 .. min(9, items.high)]:
        logInfo("asset_hygiene_gate", "    - " & $(item))
      if items.len > 10:
        logInfo("asset_hygiene_gate", "    ... and " & $(items.len - 10) & " more")
      failed = true

  if failed:
    logInfo("asset_hygiene_gate", $(GateTag) & " Add binary files via Git LFS or reduce their size.")
    quit(1)

  logger.info $GateTag & " PASS: asset hygiene ratchet holds."
  quit(0)

when isMainModule:
  main()
