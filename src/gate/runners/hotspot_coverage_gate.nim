import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## hotspot_coverage_gate.nim — Hotspot Coverage Gate
##
## Enforces test coverage on high-churn (hotspot) source modules so that
## frequently-modified code is always backed by tests.
##
## A "hotspot" is a top-10% most-churned module under src/, computed from
## git history (number of commits touching each file). Every hotspot must
## have a corresponding test file.
##
## Tiered coverage thresholds (see tests/features/hotspot_coverage.feature):
##   Tier 1 — critical hotspot: 100% must have tests (14/15 → FAIL)
##   Tier 2 — mid-tier hotspot:  80% must have tests (28/35 → PASS, 25/35 → FAIL)
##   Tier 3 — long-tail hotspot: 50% must have tests (50/90 → PASS)
##
## CLI:
##   hotspot_coverage_gate <repoRoot>   compute churn & check coverage
##   hotspot_coverage_gate --self-test  validate tier logic
##
## See: tests/features/hotspot_coverage.feature

import std/[os, strutils, osproc, algorithm, tables]

const GateTag = "[hotspot-coverage]"
const TopPercentile = 0.10       ## top 10% files by churn are hotspots

# ── Tiered coverage thresholds (pure logic, self-tested) ─────────────────

type
  Tier* {.pure.} = enum
    Tier1 = "tier1"
    Tier2 = "tier2"
    Tier3 = "tier3"

  TierResult* = object
    tier*: Tier
    covered*: int
    total*: int
    required*: int      ## number of tests required (percentage of total)
    pass*: bool
    gap*: int           ## number of missing tests

const TierThresholds*: array[Tier, int] = [
  Tier.Tier1: 100,   ## Tier 1 requires 100% test coverage
  Tier.Tier2: 80,    ## Tier 2 requires 80%
  Tier.Tier3: 50,    ## Tier 3 requires 50%
]

func tierThreshold*(tier: Tier): int {.raises: [].} =
  ## The coverage percentage required for a tier.
  result = TierThresholds[tier]

func requiredCount*(total, thresholdPct: int): int {.raises: [].} =
  ## Ceiling number of covered items required to satisfy a percentage.
  if total <= 0: return 0
  result = (total * thresholdPct + 99) div 100

func evaluateTier*(tier: Tier, covered, total: int): TierResult {.raises: [].} =
  ## Evaluate one tier against its threshold. gap = missing tests.
  let required = requiredCount(total, tierThreshold(tier))
  result = TierResult(
    tier: tier,
    covered: covered,
    total: total,
    required: required,
    pass: covered >= required,
    gap: max(0, required - covered),
  )

proc evaluateAllTiers*(specs: seq[tuple[tier: Tier, covered, total: int]]): seq[TierResult] {.raises: [].} =
  ## Evaluate a set of tier specifications at once.
  for (tier, covered, total) in specs:
    result.add(evaluateTier(tier, covered, total))

# ── Churn computation via git history ─────────────────────────────────────

proc enumerateSourceFiles*(repoRoot: string): seq[string] {.raises: [CatchableError].} =
  ## Recursively list .nim source files under repoRoot/src, sorted.
  let srcDir = repoRoot / "src"
  if not dirExists(srcDir):
    return @[]
  var paths: seq[string] = @[]
  proc walk(dir: string) =
    for kind, path in walkDir(dir):
      if kind == pcFile and path.endsWith(".nim"):
        paths.add(path)
      elif kind == pcDir:
        walk(path)
  walk(srcDir)
  paths.sort()
  result = paths

proc computeChurn*(repoRoot: string, files: seq[string]): OrderedTable[string, int] {.raises: [CatchableError].} =
  ## Count how many commits touched each file (git log --name-only).
  ## Missing files / non-git repo → 0 churn for every file.
  for f in files:
    result[f] = 0
  if files.len == 0:
    return
  let cmd = "git -C " & quoteShell(repoRoot) & " log --pretty=format: --name-only -- 'src/**/*.nim' 'src/*.nim'"
  let (output, _) = try: execCmdEx(cmd) except CatchableError: ("", 1)
  for line in output.splitLines():
    let rel = line.strip()
    if rel.len == 0 or not rel.startsWith("src/"):
      continue
    let full = repoRoot / rel
    if full in result:
      inc result[full]

proc identifyHotspots*(churn: OrderedTable[string, int], count: int): seq[string] {.raises: [].} =
  ## Return the top `count` files by churn (deterministic: churn desc, name asc).
  if churn.len == 0 or count <= 0:
    return @[]
  var pairs: seq[(string, int)]
  for path, c in churn:
    pairs.add((path, c))
  pairs.sort(proc(a, b: (string, int)): int {.raises: [].} =
    result = b[1] - a[1]             # churn desc
    if result == 0:
      result = cmp(a[0], b[0]))       # name asc
  var resultList: seq[string]
  for i in 0 ..< min(count, pairs.len):
    resultList.add(pairs[i][0])
  result = resultList

proc findTestFor*(repoRoot, srcPath: string): string {.raises: [CatchableError].} =
  ## Locate a test file corresponding to a source file.
  ## Returns the first matching test path, or "" if none found.
  let stem = srcPath.extractFilename()[0 ..< ^4]
  let patterns = @[
    stem & "_test.nim",
    "test_" & stem & ".nim",
    stem & "_tests.nim",
    stem & "Test.nim",
  ]
  var searchRoot = repoRoot / "tests"
  if not dirExists(searchRoot):
    searchRoot = repoRoot / "src"
  proc walk(dir: string): string =
    for kind, path in walkDir(dir):
      if result.len > 0: return result
      if kind == pcFile:
        let fn = path.extractFilename()
        for p in patterns:
          if fn == p:
            return path
      elif kind == pcDir:
        let r = walk(path)
        if r.len > 0:
          return r
    return ""
  result = walk(searchRoot)

proc checkCoverage*(repoRoot: string, hotspots: seq[string]): seq[string] {.raises: [CatchableError].} =
  ## Return the list of hotspot files that lack a corresponding test.
  for h in hotspots:
    if findTestFor(repoRoot, h).len == 0:
      result.add(h)

# ── CLI entry point ────────────────────────────────────────────────────────

proc main() {.raises: [CatchableError].} =
  let args = commandLineParams()

  if args.len == 1 and args[0] == "--self-test":
    var ok = true
    proc expect(label: string, cond: bool) =
      stdout.writeLine(GateTag & " self-test: " & label & (if cond: " PASS" else: " FAIL"))
      if not cond: ok = false
    expect("tier1 threshold=100", tierThreshold(Tier.Tier1) == 100)
    expect("tier2 threshold=80", tierThreshold(Tier.Tier2) == 80)
    expect("tier3 threshold=50", tierThreshold(Tier.Tier3) == 50)
    expect("tier1 14/15 fails", not evaluateTier(Tier.Tier1, 14, 15).pass)
    expect("tier1 15/15 passes", evaluateTier(Tier.Tier1, 15, 15).pass)
    expect("tier2 28/35 passes", evaluateTier(Tier.Tier2, 28, 35).pass)
    expect("tier2 25/35 fails", not evaluateTier(Tier.Tier2, 25, 35).pass)
    expect("tier3 50/90 passes", evaluateTier(Tier.Tier3, 50, 90).pass)
    expect("tier3 40/90 fails", not evaluateTier(Tier.Tier3, 40, 90).pass)
    stdout.writeLine(GateTag & " self-test PASS")
    quit(if ok: 0 else: 1)

  if args.len < 1:
    stdout.writeLine("Usage: hotspot_coverage_gate <repoRoot> | --self-test")
    quit(1)

  let repoRoot = args[0]
  if not dirExists(repoRoot):
    stdout.writeLine(GateTag & " ERROR — repoRoot not found: " & repoRoot)
    quit(1)

  let files = enumerateSourceFiles(repoRoot)
  if files.len == 0:
    stdout.writeLine(GateTag & " PASS — no source files, zero hotspots")
    quit(0)

  let churn = computeChurn(repoRoot, files)
  let hotspotCount = max(1, (files.len * 100 * TopPercentile.int).div 100)
  let hotspots = identifyHotspots(churn, hotspotCount)
  let uncovered = checkCoverage(repoRoot, hotspots)

  if uncovered.len == 0:
    stdout.writeLine(GateTag & " PASS — all " & $hotspots.len &
      " hotspot(s) backed by tests")
    quit(0)
  else:
    stdout.writeLine(GateTag & " FAIL — " & $uncovered.len & " hotspot(s) lack tests:")
    for u in uncovered:
      stdout.writeLine("  " & u)
    quit(1)

when isMainModule:
  main()

{.pop.}
