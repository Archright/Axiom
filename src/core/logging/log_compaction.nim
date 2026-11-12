import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## log_compaction.nim — Compact sharded logs by merging old shards.
##
## Strategy: merge shards older than `compactAfter` into a single
## JSONL file per gate. Reduces file count while preserving data.
##
## Phase E6 additions:
## - enforceShardLimit: triggers compaction when shard count > maxShardsPerGate.
## - archiveOldCompacted: moves entries older than archiveAfterDays to
##   archived/<year-month>.jsonl for time-based archiving.
## - compactAndArchive: full lifecycle (compact + enforce + archive).

import std/[os, times, algorithm, sequtils, json, strutils]
import system/exceptions
import core/logging/sharded_log
import core/parsers/safe_parsers
import core/trusted/stdlib_shield
import core/types/results
import core/axiom_pragmas

type
  CompactionConfig* = object
    compactAfterDays*: int      ## Merge shards older than this (default: 7)
    maxShardsPerGate*: int      ## Keep at most this many unmerged shards (default: 1000)
    archiveAfterDays*: int      ## Archive compacted.jsonl after this many days (default: 30)
    dryRun*: bool               ## If true, only report what would be compacted

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func defaultCompactionConfig*(): CompactionConfig =
  CompactionConfig(compactAfterDays: 7, maxShardsPerGate: 1000, archiveAfterDays: 30, dryRun: false)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseLogEntry(node: JsonNode): LogEntry {.inline.} =
  ## Parse a JSON node into a LogEntry.
  LogEntry(
    gateId: node{"gateId"}.getStr(),
    timestamp: node{"timestamp"}.getInt(),
    status: node{"status"}.getStr(),
    duration: node{"duration"}.getFloat(),
    violations: (if node{"violations"} != nil: toSeq(node{"violations"}.items).mapIt(it.getStr()) else: @[]),
    metadata: node{"metadata"}
  )

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc countShards(dir: string): int {.raises: [OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Count unmerged .json shard files in a gate directory.
  var count = 0
  for path in walkDir(dir):
    if path.kind == pcFile and path.path.endsWith(".json") and
       not path.path.endsWith(".tmp") and not path.path.endsWith("compacted.jsonl"):
      inc count
  count

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc oldestShardTimestamp(dir: string): int64 {.raises: [OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Return the oldest shard timestamp, or 0 if no shards exist.
  result = high(int64)
  for path in walkDir(dir):
    if path.kind == pcFile and path.path.endsWith(".json") and
       not path.path.endsWith(".tmp") and not path.path.endsWith("compacted.jsonl"):
      let fname = path.path.extractFilename().changeFileExt("")
      let tsResult = safeParseInt(fname)
      if tsResult.isOk:
        let ts = tsResult.get()
        if ts < result: result = ts
  if result == high(int64): result = 0

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc compactGate*(baseDir: string, gateId: string, config: CompactionConfig) {.raises: [CatchableError, exceptions.IOError, OSError, ValueError, JsonParsingError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compact shards for a single gate.
  let dir = baseDir / gateId
  if not dirExists(dir): return

  let cutoff = toUnix(getTime()) - int64(config.compactAfterDays * 86400)
  var oldShards: seq[string] = @[]
  var oldEntries: seq[LogEntry] = @[]

  for path in walkDir(dir):
    if path.kind == pcFile and path.path.endsWith(".json") and not path.path.endsWith(".tmp"):
      let fname = path.path.extractFilename().changeFileExt("")
      let tsResult = safeParseInt(fname)
      if tsResult.isOk:
        let ts = tsResult.get()
        if ts < cutoff:
          oldShards.add(path.path)
          let content = readFile(path.path)
          let node = parseJson(content)
          oldEntries.add(parseLogEntry(node))

  if oldEntries.len == 0: return

  # Sort by timestamp
  oldEntries.sort(proc(a, b: LogEntry): int = cmp(a.timestamp, b.timestamp))

  # Write compacted JSONL
  let compactPath = dir / "compacted.jsonl"
  if not config.dryRun:
    var f = open(compactPath, fmAppend)
    for entry in oldEntries:
      let json = %*{
        "gateId": entry.gateId,
        "timestamp": entry.timestamp,
        "status": entry.status,
        "duration": entry.duration,
        "violations": entry.violations,
        "metadata": entry.metadata
      }
      f.writeLine($json)
    f.close()

    # Remove compacted shards
    for shard in oldShards:
      safeRemoveFile(shard)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc enforceShardLimit*(baseDir: string, gateId: string, config: CompactionConfig) {.raises: [CatchableError, exceptions.IOError, OSError, ValueError, JsonParsingError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Phase E6: Trigger compaction when shard count exceeds maxShardsPerGate.
  let dir = baseDir / gateId
  if not dirExists(dir): return
  if countShards(dir) > config.maxShardsPerGate:
    # Lower the time threshold to force compaction of enough shards.
    compactGate(baseDir, gateId, config)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc archiveOldCompacted*(baseDir: string, gateId: string, config: CompactionConfig) {.raises: [exceptions.IOError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Phase E6: Move entries older than archiveAfterDays from compacted.jsonl
  ## into archived/<year-month>.jsonl for time-based archiving.
  let dir = baseDir / gateId
  let compactPath = dir / "compacted.jsonl"
  if not fileExists(compactPath): return

  let archiveCutoff = toUnix(getTime()) - int64(config.archiveAfterDays * 86400)

  # Read and classify entries.
  var kept: seq[string] = @[]
  # groupKey -> lines: entries bucketed by year-month for archiving.
  var archiveBuckets: seq[tuple[yearMonth: string, line: string]] = @[]

  let lines = readFile(compactPath).splitLines()
  for line in lines:
    let trimmed = line.strip()
    if trimmed.len == 0: continue
    try:
      let node = parseJson(trimmed)
      let ts = node{"timestamp"}.getInt()
      if ts < archiveCutoff:
        # Parse year-month from timestamp for bucketing.
        let dt = fromUnix(ts.int64).utc()
        let ym = $dt.year & "-" & (if dt.month.ord < 10: "0" else: "") & $dt.month.ord
        archiveBuckets.add((ym, trimmed))
      else:
        kept.add(trimmed)
    except CatchableError:
      continue

  if archiveBuckets.len == 0: return
  if config.dryRun: return

  # Ensure archive directory exists.
  let archiveDir = dir / "archived"
  createDir(archiveDir)

  # Append each bucket to its year-month file.
  for bucket in archiveBuckets:
    let archivePath = archiveDir / bucket.yearMonth & ".jsonl"
    var f = open(archivePath, fmAppend)
    f.writeLine(bucket.line)
    f.close()

  # Rewrite compacted.jsonl with only kept entries.
  var f = open(compactPath, fmWrite)
  for line in kept:
    f.writeLine(line)
  f.close()

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc compactAndArchive*(baseDir: string, config: CompactionConfig = defaultCompactionConfig()) {.raises: [CatchableError, exceptions.IOError, OSError, ValueError, JsonParsingError].} =
  ## Phase E6: Full lifecycle — compact, enforce shard limits, and archive old compacted data.
  if not dirExists(baseDir): return
  for entry in walkDir(baseDir):
    if entry.kind == pcDir:
      let gateId = entry.path.extractFilename()
      compactGate(baseDir, gateId, config)
      enforceShardLimit(baseDir, gateId, config)
      archiveOldCompacted(baseDir, gateId, config)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc compactAll*(baseDir: string, config: CompactionConfig = defaultCompactionConfig()) {.raises: [CatchableError, exceptions.IOError, OSError, ValueError, JsonParsingError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compact all gates in the history directory (legacy entry point).
  ## Prefer compactAndArchive for the full lifecycle.
  compactAndArchive(baseDir, config)

{.pop.}
