## Burn-down Queue
## Combines git churn, test existence, and SAD into a priority score.
## Priority = edit_count × risk_multiplier

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[algorithm, strutils, tables]
import core/interfaces/file_io_executor
import hotspot_analyzer
import core/axiom_pragmas
{.push raises: [].}
# axiomIoBoundary

let fileIo* = SystemFileIoExecutor()

{.push raises: [OSError, IOError].}

type
  HotspotTier* = enum
    htCritical  ## No test exists
    htHigh      ## Has test, SAD < 5%
    htMedium    ## Has test, SAD < 15%
    htLow       ## Has test, SAD ≥ 15%

  HotspotEntry* = object
    filePath*: string
    moduleName*: string
    editCount*: int
    hasTest*: bool
    testPath*: string
    sadScore*: float
    riskMultiplier*: float
    priorityScore*: float
    tier*: HotspotTier

const
  RiskNoTest* = 3.0
  RiskSadLow* = 2.0      ## SAD < 5%
  RiskSadMedium* = 1.5   ## SAD < 15%
  RiskSadHigh* = 1.0     ## SAD ≥ 15%

proc findTestFile*(moduleName: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Search tests/unit/ and tests/gateway/ for matching test file.
  let candidates = [
    "tests/unit/" & moduleName & "_test.nim",
    "tests/unit/" & moduleName & "_feature_test.nim",
    "tests/gateway/" & moduleName & "_test.nim",
    "tests/gateway/" & moduleName & "_feature_test.nim",
  ]
  for c in candidates:
    if fileIo.fileExists(c):
      return c
  result = ""

proc computeSadScore*(filePath: string): float {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Calculate SAD for a test file. Returns 0.0 if file missing.
  if filePath.len == 0 or not fileIo.fileExists(filePath):
    return 0.0
  let content = block:
    try: fileIo.readFile(filePath)
    except CatchableError: ""
  var assertionCount = 0
  var totalLines = 0
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.len == 0 or stripped.startsWith("#"):
      continue
    inc totalLines
    if "check" in stripped or "assert" in stripped or "doAssert" in stripped:
      inc assertionCount
  if totalLines == 0:
    return 0.0
  result = assertionCount.float / totalLines.float

func computeRiskMultiplier*(hasTest: bool; sad: float): float =
  if not hasTest:
    result = RiskNoTest
  elif sad < 0.05:
    result = RiskSadLow
  elif sad < 0.15:
    result = RiskSadMedium
  else:
    result = RiskSadHigh

func computeTier*(hasTest: bool; sad: float): HotspotTier =
  if not hasTest:
    result = htCritical
  elif sad < 0.05:
    result = htHigh
  elif sad < 0.15:
    result = htMedium
  else:
    result = htLow

proc buildPriorityQueue*(
  churn: Table[string, int];
  topN: int = 0
): seq[HotspotEntry] =
  ## Build priority queue from churn scores. topN=0 returns all entries.
  ## Build priority queue from churn scores.
  var entries: seq[HotspotEntry] = @[]
  for path, count in churn.pairs:
    let name = moduleNameFromPath(path)
    let testPath = findTestFile(name)
    let hasTest = testPath.len > 0
    let sad = computeSadScore(testPath)
    let mult = computeRiskMultiplier(hasTest, sad)
    let tier = computeTier(hasTest, sad)
    entries.add(HotspotEntry(
      filePath: path,
      moduleName: name,
      editCount: count,
      hasTest: hasTest,
      testPath: testPath,
      sadScore: sad,
      riskMultiplier: mult,
      priorityScore: count.float * mult,
      tier: tier
    ))
  # Sort by priority descending, then edit count descending, then name ascending
  entries.sort(proc(a, b: HotspotEntry): int =
    if a.priorityScore != b.priorityScore:
      result = cmp(b.priorityScore, a.priorityScore)
    elif a.editCount != b.editCount:
      result = cmp(b.editCount, a.editCount)
    else:
      result = cmp(a.moduleName, b.moduleName)
  )
  if topN > 0 and entries.len > topN:
    entries = entries[0 ..< topN]
  result = entries

func isHotspot*(queue: seq[HotspotEntry]; filePath: string; topN: int): bool =
  ## Check if filePath is in the top-N hotspots.
  let limit = min(topN, queue.len)
  for i in 0 ..< limit:
    if queue[i].filePath == filePath:
      return true

func findHotspotEntry*(queue: seq[HotspotEntry]; filePath: string): HotspotEntry =
  ## Find entry by file path. Returns default if not found.
  for e in queue:
    if e.filePath == filePath:
      return e

{.pop.}

{.pop}
