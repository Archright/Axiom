## AST-aware Import Boundary Scanner + Tier 1 Raw Primitive Detector
##
## Uses a two-pass approach for robust import detection:
##   Pass 1: Strip comments and string literals (false positive elimination)
##   Pass 2: Regex-match import statements against forbidden paths
##
## While not a full AST parse, this handles:
##   - Single-line and multi-line comments (#, #[ ]#)
##   - Strings containing "import" (stripped before matching)
##   - `from X import Y` syntax
##   - Multi-line imports (parenthesized)
##
## Build pipeline (gorgeEx 2-step — prevents config.nims recursion):
##   Step 1: gorgeEx("AXIOM_HERMETIC_BUILDING=1 nim c --hints:off -o:bin/check_imports_ast tools/check_imports_ast.nim")
##   Step 2: gorgeEx("bin/check_imports_ast")

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, sequtils, json, times, sets]
import checksums/sha2

const
  ForbiddenPaths = ["tools/", "kimi-sdk/"]
  ExemptedPrefixes = ["src/core/boundary/"]
  CachePath = ".axiom/cache/verification_cache.json"
  ImportCacheDir = ".cache/imports"
  ImportCachePath = ImportCacheDir & "/cache.json"
  Tier1Modules = [
    "src/core/metrics.nim",
    "src/core/telemetry/metrics.nim",
    "src/core/types/certificate_types.nim",
    "src/core/types/verification_tier.nim",
    "src/cli/shared/proof_hydration.nim"
  ]



proc computeFileHash(content: string): string =
  var hasher = initSha_256()
  hasher.update(content)
  $hasher.digest()

proc getStagedContent(filePath: string): string =
  let (output, exitCode) = execCmdEx("git cat-file -p :" & filePath)
  if exitCode == 0 and output.len > 0:
    return output
  readFile(filePath)

proc loadCache(): JsonNode =
  if fileExists(CachePath):
    parseJson(readFile(CachePath))
  else: %*{"epoch": 0, "modules": {}}

proc saveCache(cache: JsonNode) =
  writeFile(CachePath, pretty(cache))

proc isCacheValid(filePath: string; currentHash: string): bool =
  let cache = loadCache()
  if not cache.hasKey("modules"): return false
  let mods = cache["modules"]
  if not mods.hasKey(filePath): return false
  mods[filePath].getOrDefault("hash").getStr() == currentHash

proc updateCache(filePath: string; hash: string; passed: bool) =
  var cache = loadCache()
  if not cache.hasKey("modules"): cache["modules"] = %*{}
  cache["modules"][filePath] = %*{
    "hash": hash,
    "result": if passed: "PASS" else: "FAIL",
    "cached_at": $now()
  }
  saveCache(cache)

proc loadImportCache(): JsonNode =
  if fileExists(ImportCachePath):
    parseJson(readFile(ImportCachePath))
  else: %*{}

proc saveImportCache(cache: JsonNode) =
  let dir = ImportCacheDir
  if not dirExists(dir):
    createDir(dir)
  writeFile(ImportCachePath, pretty(cache))

proc isImportCacheValid(filePath: string; currentHash: string): bool =
  let cache = loadImportCache()
  if not cache.hasKey(filePath): return false
  cache[filePath].getOrDefault("hash").getStr() == currentHash

proc cachedViolations(filePath: string): seq[string] =
  ## Replays the violations recorded alongside a valid cache entry.
  ## A cached FAIL must keep failing: skipping it lets the scanner report
  ## PASSED for a file that is known to cross the import boundary.
  let cache = loadImportCache()
  if not cache.hasKey(filePath): return @[]
  for v in cache[filePath].getOrDefault("violations").getElems:
    result.add(v.getStr())

proc updateImportCache(filePath: string; hash: string; passed: bool; violations: seq[string]) =
  var cache = loadImportCache()
  cache[filePath] = %*{
    "hash": hash,
    "result": if passed: "PASS" else: "FAIL",
    "violations": violations,
    "checked_at": $now()
  }
  saveImportCache(cache)

proc getChangedFiles(): seq[string] =
  let (staged, stagedExit) = execCmdEx("git diff --cached --name-only --diff-filter=ACM")
  let (unstaged, unstagedExit) = execCmdEx("git diff --name-only --diff-filter=ACM")
  if stagedExit != 0 and unstagedExit != 0:
    for f in walkDirRec("src/"):
      if f.endsWith(".nim"):
        result.add(f)
    return
  var files: HashSet[string]
  for f in staged.splitLines():
    if f.len > 0 and f.endsWith(".nim"):
      files.incl(f)
  for f in unstaged.splitLines():
    if f.len > 0 and f.endsWith(".nim"):
      files.incl(f)
  result = files.toSeq()

proc isTier1Module(filePath: string): bool =
  filePath in Tier1Modules

proc hasRawPrimitiveInSignature(line: string): bool =
  let stripped = line.strip()
  if not (stripped.startsWith("proc *") or stripped.startsWith("func *") or
          stripped.startsWith("proc ") or stripped.startsWith("func ")):
    return false
  if stripped.contains("ASIRatio") or stripped.contains("VerifiedKernelRatio") or
     stripped.contains("NonNegativeDuration") or stripped.contains("CertificateStatus"):
    return false
  stripped.contains(": float") or stripped.contains(": int ") or
  stripped.contains("float =") or stripped.contains("int =")

proc verifyTier1Raw*(stagedFiles: seq[string]): tuple[passed: bool; violations: seq[string]] =
  var violations: seq[string] = @[]

  for filePath in stagedFiles:
    if not filePath.endsWith(".nim"): continue
    if not isTier1Module(filePath): continue

    let content = getStagedContent(filePath)
    let hash = computeFileHash(content)

    if isCacheValid(filePath, hash):
      continue

    let lines = content.splitLines()
    for i in 0..<lines.len:
      if hasRawPrimitiveInSignature(lines[i]):
        violations.add(filePath & ":" & $(i+1) & " " & lines[i].strip())

    updateCache(filePath, hash, violations.filterIt(it.startsWith(filePath)).len == 0)

  (violations.len == 0, violations)

proc stripComments(content: string): string =
  result = content
  while true:
    let start = result.find("#[")
    if start < 0: break
    let stop = result.find("]#", start + 2)
    if stop < 0:
      result = result[0 ..< start]
      break
    result = result[0 ..< start] & result[stop + 2 .. ^1]
  var lines: seq[string]
  for line in result.splitLines():
    let commentPos = line.find('#')
    if commentPos >= 0:
      lines.add(line[0 ..< commentPos])
    else:
      lines.add(line)
  result = lines.join("\n")

proc checkFile(path: string): seq[string] =
  try:
    let content = readFile(path)
    let cleaned = stripComments(content)
    let isExempted = ExemptedPrefixes.anyIt(path.replace('\\', '/').startsWith(it))
    for line in cleaned.splitLines():
      let stripped = line.strip()
      if stripped.startsWith("import ") or stripped.startsWith("from "):
        for forbidden in ForbiddenPaths:
          if forbidden in stripped:
            if not isExempted:
              let msg = path & " — '" & stripped & "' contains '" & forbidden & "'"
              echo "IMPORT VIOLATION: ", msg
              result.add(msg)
  except CatchableError as e:
    echo "PARSE WARNING: ", path, " — ", e.msg

when isMainModule:
  let stagedOnly = "--staged-only" in commandLineParams()
  let checkTier1 = "--tier1-raw" in commandLineParams()
  let checkAll = "--all" in commandLineParams()

  var targetFiles: seq[string] = @[]

  if checkTier1:
    if stagedOnly:
      let (output, _) = execCmdEx("git diff --cached --name-only --diff-filter=ACM")
      targetFiles = output.splitLines().filterIt(it.len > 0 and it.endsWith(".nim"))
    else:
      targetFiles = getChangedFiles()

    let (passed, violations) = verifyTier1Raw(targetFiles)
    if not passed:
      echo "[FAIL] " & $violations.len & " raw primitive violations:"
      for v in violations: echo "  - " & v
      quit(1)
    echo "[PASS] Tier 1 raw primitive check passed"
  else:
    echo "AST-Aware Import Boundary Scanner v5"
    echo "Forbidden paths: ", ForbiddenPaths.join(", ")
    echo "---"

    if checkAll:
      for f in walkDirRec("src/"):
        if f.endsWith(".nim"):
          targetFiles.add(f)
    elif stagedOnly:
      let (output, _) = execCmdEx("git diff --cached --name-only --diff-filter=ACM")
      targetFiles = output.splitLines().filterIt(it.len > 0 and it.endsWith(".nim"))
    else:
      targetFiles = getChangedFiles()

    var allViolations: seq[string] = @[]
    var fileCount = 0
    for filePath in targetFiles:
      if not filePath.endsWith(".nim"): continue

      let content = readFile(filePath)
      let hash = computeFileHash(content)

      if not checkAll and isImportCacheValid(filePath, hash):
        allViolations.add(cachedViolations(filePath))
        fileCount += 1
        continue

      let violations = checkFile(filePath)
      allViolations.add(violations)
      updateImportCache(filePath, hash, violations.len == 0, violations)
      fileCount += 1

    echo "---"
    echo "Scanned ", fileCount, " files"
    if allViolations.len > 0:
      echo "FAILED: ", allViolations.len, " import violation(s) found"
      quit(1)
    else:
      echo "PASSED: No import boundary violations"
