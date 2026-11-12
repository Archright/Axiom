## JSONL Audit Store — Infrastructure implementation of IAuditStorage
##
## Lives in src/verification/ (Infrastructure layer), NOT in src/core/ (Domain).
## This is the concrete implementation of the audit persistence concept
## that the Domain layer only knows through the IAuditStorage interface.
##
## Responsible for:
##   - Appending audit entries to a JSONL file (append)
##   - Reading the last N entries from the log (recentEntries)
##   - Assessing gate health from recent entries (assessHealth)
##
## The Domain layer (src/core/audit/) must NOT import this module.
## It depends only on the IAuditStorage concept from the SDK.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/[json, times, os, strutils]
import ../../core/audit/audit_types  # Domain types only (AuditEntry, HealthLevel)
import ../../core/audit/audit_storage_interface  # IAuditStorage concept
import core/trusted/axiom_pragmas

type
  JsonlAuditStore* = object
    ## Infrastructure implementation of IAuditStorage backed by a JSONL file.
    path*: string

proc newJsonlAuditStore*(logPath: string): JsonlAuditStore =
  ## Create a new store targeting the given JSONL file path.
  JsonlAuditStore(path: logPath)

proc append*(s: JsonlAuditStore, entry: AuditEntry) {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Append an audit entry to the JSONL log file.
  ## Creates the parent directory if it does not exist.
  let dir = s.path.parentDir
  if dir.len > 0 and not dirExists(dir):
    try:
      createDir(dir)
    except IOError:
      discard  # Best-effort: directory creation failure is non-fatal

  let node = %*{
    "gateId": entry.gateId,
    "passed": entry.passed,
    "durationMs": entry.durationMs,
    "timestamp": entry.timestamp,
    "metadata": entry.metadata
  }

  try:
    let f = open(s.path, fmAppend)
    f.writeLine($node)
    f.close()
  except IOError:
    discard  # Best-effort: write failure is non-fatal

proc loadAll*(s: JsonlAuditStore): seq[AuditEntry] {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load all audit entries from the JSONL file.
  result = @[]
  if not fileExists(s.path):
    return
  var f: File
  if not open(f, s.path, fmRead):
    return
  var line = ""
  while f.readLine(line):
    if line.len == 0:
      continue
    try:
      let j = parseJson(line)
      result.add(AuditEntry(
        gateId: j{"gateId"}.getStr(""),
        passed: j{"passed"}.getBool(false),
        durationMs: j{"durationMs"}.getInt(0),
        timestamp: j{"timestamp"}.getStr(""),
        metadata: j{"metadata"}.getStr("{}")
      ))
    except IOError:
      continue
  f.close()

proc recentEntries*(s: JsonlAuditStore, n: int): seq[AuditEntry] {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read the last N entries from the JSONL log file.
  let all = s.loadAll()
  if all.len <= n:
    result = all
  else:
    result = all[(all.len - n) .. ^1]

proc assessHealth*(s: JsonlAuditStore, gateId: string): HealthLevel {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Assess gate health from the last 100 entries for this gate.
  ## Returns a HealthLevel based on the pass rate.
  const windowSize = 100
  let all = s.loadAll()

  # Filter to entries matching the given gateId
  var filtered: seq[AuditEntry]
  for entry in all:
    if entry.gateId == gateId:
      filtered.add(entry)

  # Take the last windowSize entries
  let entries = if filtered.len <= windowSize: filtered
                else: filtered[(filtered.len - windowSize) .. ^1]

  if entries.len == 0:
    return hlHealthy  # No data = assume healthy (avoid false alarms)

  # Compute pass rate
  var passedCount = 0
  for entry in entries:
    if entry.passed:
      inc passedCount
  let passRate = passedCount.float / entries.len.float

  # Classify health
  if passRate == 0.0:
    result = hlCritical
  elif passRate < 0.5:
    result = hlDegraded
  elif passRate < 0.9:
    result = hlWarning
  else:
    result = hlHealthy
