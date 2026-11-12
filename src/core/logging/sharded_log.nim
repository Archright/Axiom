import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## sharded_log.nim — Sharded JSON log with atomic appends.
##
## Log structure: logs/history/<gate_id>/<timestamp>.json
## Each shard is a single JSON file. Aggregation reads all shards
## plus compacted.jsonl (Phase E6 fix for post-compaction data loss).

import std/[json, os, sequtils, algorithm, strutils]
import core/trusted/axiom_pragmas

type
  LogEntry* = object
    gateId*: string
    timestamp*: int64       ## Unix timestamp
    status*: string         ## "pass" | "fail" | "skip"
    duration*: float        ## seconds
    violations*: seq[string]
    metadata*: JsonNode     ## free-form

  ShardedLog* = object
    baseDir*: string        ## e.g., "logs/history"
    gateId*: string

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func newShardedLog*(baseDir: string, gateId: string): ShardedLog =
  ShardedLog(baseDir: baseDir, gateId: gateId)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func shardPath*(log: ShardedLog, ts: int64): string =
  ## Generate shard file path: <baseDir>/<gate_id>/<timestamp>.json
  log.baseDir / log.gateId / $ts & ".json"

# Quirk isolation: moveFile lacks raises pragma in Nim stdlib (nim_effect_system_quirks.md §7).
# Only this module uses except Exception for stdlib; business logic uses CatchableError.
{.warning[BareExcept]:off.}
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc moveFileSafe(source, dest: string) {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    moveFile(source, dest)
  except Exception as e:
    raise newException(IOError, "moveFile failed: " & e.msg)
{.warning[BareExcept]:on.}

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc append*(log: ShardedLog, entry: LogEntry) {.raises: [IOError, CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Atomic append: write to temp file, then rename.
  let dir = log.baseDir / log.gateId
  createDir(dir)
  let ts = entry.timestamp
  let finalPath = log.shardPath(ts)
  let tmpPath = finalPath & ".tmp"
  let json = %*{
    "gateId": entry.gateId,
    "timestamp": entry.timestamp,
    "status": entry.status,
    "duration": entry.duration,
    "violations": entry.violations,
    "metadata": entry.metadata
  }
  writeFile(tmpPath, json.pretty())
  moveFileSafe(tmpPath, finalPath)

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
proc readAll*(log: ShardedLog): seq[LogEntry] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read all shards for this gate, including compacted.jsonl, sorted by timestamp.
  let dir = log.baseDir / log.gateId
  if not dirExists(dir): return @[]
  var entries: seq[LogEntry] = @[]

  # Phase E6 fix: read compacted.jsonl first so no data is lost after compaction.
  let compactPath = dir / "compacted.jsonl"
  if fileExists(compactPath):
    let lines = readFile(compactPath).splitLines()
    for line in lines:
      let trimmed = line.strip()
      if trimmed.len == 0: continue
      let node = parseJson(trimmed)
      entries.add(parseLogEntry(node))

  # Read individual shard files.
  for path in walkDir(dir):
    if path.kind == pcFile and path.path.endsWith(".json") and not path.path.endsWith(".tmp"):
      let content = readFile(path.path)
      let node = parseJson(content)
      entries.add(parseLogEntry(node))

  entries.sort(proc(a, b: LogEntry): int = cmp(a.timestamp, b.timestamp))
  entries

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc recentEntries*(log: ShardedLog, n: int): seq[LogEntry] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Get the N most recent log entries.
  let all = log.readAll()
  let start = max(0, all.len - n)
  all[start .. ^1]

{.pop.}
