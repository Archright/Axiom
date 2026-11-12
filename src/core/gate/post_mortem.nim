import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## Post-Mortem Debugger — Failed Build Preservation
##
## 빌드 실패 시 샌드박스 상태를 보존하여 개발자가 직접 조사 가능.
## .axiom/failed_builds/<ActionKey[:16]>/
##   result.json    — stdout, stderr, exitCode
##   inputs.json    — input path → content hash
##   _latest → symlink to most recent failure

import std/[os, json, strutils, tables, algorithm, times]
import core/trusted/axiom_pragmas_lite
import core/trusted/effect_bridge
import core/trusted/stdlib_shield

const
  FailedBuildsDir* = ".axiom/failed_builds"

type
  PostMortemRecord* = object
    actionKey*: string
    gateId*: string
    failedAt*: float
    stdout*: string
    stderr*: string
    exitCode*: int
    inputs*: Table[string, string]    # input path → content hash
    namespaceConfig*: string          # JSON serialized
# axiomIoBoundary

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc initPostMortem*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  createDir(FailedBuildsDir)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc preserveFailed*(record: PostMortemRecord) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Preserve a failed build for post-mortem analysis.
  createDir(FailedBuildsDir)
  let keyPrefix = if record.actionKey.len >= 16: record.actionKey[0..15]
                  else: record.actionKey
  let dir = FailedBuildsDir / keyPrefix
  createDir(dir)

  # result.json
  let rj = %*{
    "actionKey": record.actionKey,
    "gateId": record.gateId,
    "failedAt": record.failedAt,
    "stdout": record.stdout,
    "stderr": record.stderr,
    "exitCode": record.exitCode,
    "namespaceConfig": record.namespaceConfig
  }
  writeFile(dir / "result.json", pretty(rj))

  # inputs.json
  var ij = newJObject()
  for k, v in record.inputs:
    ij[k] = %v
  writeFile(dir / "inputs.json", pretty(ij))

  # _latest symlink
  let latestLink = FailedBuildsDir / "_latest"
  if symlinkExists(latestLink) or fileExists(latestLink):
    safeRemoveFile(latestLink)
  createSymlink(keyPrefix, latestLink)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc listFailed*(): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## List all failed build directories.
  result = @[]
  if not dirExists(FailedBuildsDir): return
  for kind, path in walkDir(FailedBuildsDir):
    if kind == pcDir:
      let name = extractFilename(path)
      if not name.startsWith("_"):
        result.add(name)
  result.sort()
  result.reverse()  # Most recent first

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc getLatestFailedDir*(): string {.axiomEffect: IoEffect.} =
  ## Get path to most recent failed build directory.
  let latestLink = FailedBuildsDir / "_latest"
  if symlinkExists(latestLink):
    return FailedBuildsDir / expandSymlink(latestLink)
  let failed = listFailed()
  if failed.len > 0:
    return FailedBuildsDir / failed[0]
  ""

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc cleanPostMortem*(maxAge: float = 7 * 86400.0) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Clean old post-mortem records. Default: 7 days TTL.
  if not dirExists(FailedBuildsDir): return
  let now = epochTime()
  for kind, path in walkDir(FailedBuildsDir):
    if kind != pcDir: continue
    let name = extractFilename(path)
    if name.startsWith("_"): continue
    let resultFile = path / "result.json"
    if fileExists(resultFile):
      try:
        let j = parseJson(readFile(resultFile))
        let failedAt = j{"failedAt"}.getFloat(0.0)
        if now - failedAt > maxAge:
          removeDir(path)
      except CatchableError:
        # If can't parse, remove anyway (corrupt)
        removeDir(path)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadRecord*(keyPrefix: string): PostMortemRecord {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load a post-mortem record by key prefix.
  let dir = FailedBuildsDir / keyPrefix
  let rj = parseJson(readFile(dir / "result.json"))
  result.actionKey = rj{"actionKey"}.getStr()
  result.gateId = rj{"gateId"}.getStr()
  result.failedAt = rj{"failedAt"}.getFloat()
  result.stdout = rj{"stdout"}.getStr()
  result.stderr = rj{"stderr"}.getStr()
  result.exitCode = rj{"exitCode"}.getInt()
  result.namespaceConfig = rj{"namespaceConfig"}.getStr()
  result.inputs = initTable[string, string]()
  let ijPath = dir / "inputs.json"
  if fileExists(ijPath):
    let ij = parseJson(readFile(ijPath))
    for k, v in ij:
      result.inputs[k] = v.getStr()
