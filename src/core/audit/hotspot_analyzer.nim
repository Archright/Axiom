import core/trusted/layer_declaration
axiomLayer "domain"
import core/interfaces/git_ops_hub
import core/interfaces/file_io_executor
import core/interfaces/io_executor
import core/types/results
import std/[strutils, tables, algorithm, json, os]
import core/axiom_pragmas
import core/macros/best_effort
# axiomIoBoundary


let fileIo* = SystemFileIoExecutor()
let sysExec* = newSystemExecutor()
let gitExe* = git_ops_hub.findRealGit()
type
  ChurnPeriod* = enum
    cp7d, cp14d, cp30d, cp90d
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func periodDays*(period: ChurnPeriod): int {.raises: [].} =
  case period
  of cp7d: 7
  of cp14d: 14
  of cp30d: 30
  of cp90d: 90
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc runGitLog*(sinceDays: int; sourceGlob: string = "src/**/*.nim"): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""git log — empty result on failure""").} =
  ## Execute git log to get file change list. Deterministic ordering.
  let cmd = gitExe & " log --since=\"" & $sinceDays &
    " days ago\" --pretty=format: --name-only -- \"" & sourceGlob & "\""
  try:
    let pc = ProcessCommand(program: "bash", args: @["-c", cmd])
    let r = sysExec.execute(pc)
    if r.isOk: result = r.get().stdout
  except CatchableError:
    result = ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseChurnScores*(gitLogOutput: string): Table[string, int] {.raises: [].} =
  ## Parse git log output into file → edit_count map.
  ## Empty lines and non-.nim files are filtered.
  for line in gitLogOutput.splitLines():
    let trimmed = line.strip()
    if trimmed.len == 0:
      continue
    if not trimmed.endsWith(".nim"):
      continue
    if trimmed.startsWith("tests/") or trimmed.startsWith("vendor/"):
      continue
    result[trimmed] = result.getOrDefault(trimmed, 0) + 1
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeChurnScores*(sinceDays: int; sourceGlob: string = "src/**/*.nim"): Table[string, int] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## High-level entry: run git log and parse churn scores.
  let raw = runGitLog(sinceDays, sourceGlob)
  result = parseChurnScores(raw)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getHeadHash(): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""git rev-parse — empty hash on failure""").} =
  ## Get current HEAD commit hash. Returns "" on failure.
  try:
    let pc = ProcessCommand(program: gitExe, args: @["rev-parse", "HEAD"])
    let r = sysExec.execute(pc)
    if r.isOk: result = r.get().stdout.strip()
  except CatchableError:
    result = ""
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc tryReadChurnCache(cachePath, headHash: string): Table[string, int] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""cache read — empty table on miss or corruption""").} =
  ## Try to read cached churn scores. Returns empty table on miss.
  result = initTable[string, int]()
  if headHash.len == 0:
    return
  if not fileIo.fileExists(cachePath):
    return
  try:
    let cached = parseJson(fileIo.readFile(cachePath))
    if cached{"head"}.getStr() == headHash:
      let raw = cached{"raw"}.getStr()
      return parseChurnScores(raw)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc writeChurnCache(
    cacheDir, cachePath, headHash, raw: string) {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""cache write — failure is non-fatal""").} =
  ## Persist churn cache to disk. Best-effort, never propagates errors.
  if headHash.len == 0:
    return
  try:
    if not fileIo.dirExists(cacheDir):
      discard fileIo.createDir(cacheDir)
    var cacheNode = newJObject()
    cacheNode["head"] = %headHash
    cacheNode["raw"] = %raw
    discard fileIo.writeFile(cachePath, $cacheNode)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc computeChurnScoresCached*(
    sinceDays: int;
    sourceGlob: string = "src/**/*.nim";
    repoRoot: string = ""): Table[string, int] {.raises: [].} =
  ## Cached variant of computeChurnScores. Uses HEAD commit hash as cache key
  ## to avoid redundant git-log invocations across gates in the same batch.
  ## Cache file: .axiom/cache/churn_{sinceDays}d.json
  let root = if repoRoot.len > 0: repoRoot
             else: (try: getCurrentDir() except CatchableError: ".")
  let cacheDir = root / ".axiom" / "cache"
  let path = cacheDir / ("churn_" & $sinceDays & "d.json")

  let headHash = getHeadHash()

  # Try cache hit
  let cached = tryReadChurnCache(path, headHash)
  if cached.len > 0:
    return cached

  # Cache miss — compute fresh and persist raw output
  let raw = runGitLog(sinceDays, sourceGlob)
  result = parseChurnScores(raw)
  writeChurnCache(cacheDir, path, headHash, raw)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func moduleNameFromPath*(filePath: string): string {.raises: [].} =
  ## Extract module name (basename without .nim extension).
  let base = extractFilename(filePath)
  if base.endsWith(".nim"):
    result = base[0 .. ^5]
  else:
    result = base
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func sortedChurnByScore*(churn: Table[string, int]): seq[(string, int)] {.raises: [].} =
  ## Return churn entries sorted by edit count descending, then path ascending.
  for path, count in churn.pairs:
    result.add((path, count))
  result.sort(proc(a, b: (string, int)): int =
    if a[1] != b[1]:
      result = cmp(b[1], a[1])  # Descending by count
    else:
      result = cmp(a[0], b[0])  # Ascending by path
  )

