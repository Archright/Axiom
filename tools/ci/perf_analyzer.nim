import std/[json, os, algorithm, strformat, terminal]

type
  ProfileBlock = object
    name: string
    durationUs: float
    percentage: float

proc analyzePerfData*(latestPath, budgetPath: string) =
  if not fileExists(latestPath):
    quit("[PERF ERROR] Benchmark file missing: " & latestPath, 1)

  let latestJson = parseJson(readFile(latestPath))
  var blocks: seq[ProfileBlock]
  var totalUs = 0.0

  for key, val in latestJson.pairs:
    let dur = val.getFloat()
    totalUs += dur
    blocks.add(ProfileBlock(name: key, durationUs: dur))

  for b in blocks.mitems:
    b.percentage = (b.durationUs / totalUs) * 100.0
  blocks.sort(proc(x, y: ProfileBlock): int = cmp(y.durationUs, x.durationUs))

  styledEcho(fgCyan, styleBright, "\n=== Axiom Performance Profile Bottleneck Top 5 ===")
  for i in 0 ..< min(5, blocks.len):
    let b = blocks[i]
    echo &" [{i+1}] {b.name:<30} | {b.durationUs:>10.2f} us | {b.percentage:>5.1f}%"
  styledEcho(fgCyan, "===================================================\n")

when isMainModule:
  analyzePerfData("data/benchmarks/perf_latest.json", "data/benchmarks/perf_budget.json")
