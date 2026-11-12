## bypass_expiry_gate.nim — Check bypass_audit.jsonl for expired temporary bypasses.
##
## Rules:
##   - Each entry's `reason` must start with #TEMP_DEBT or #REFACTOR_NEEDED (WARNING if missing).
##   - Entries older than 48 hours are hard-fail (ERROR).
##
## Exit codes:
##   0 = all OK
##   1 = at least one 48h-expired bypass found

import core/trusted/layer_declaration
axiomLayer "tools"
import shared_types/shared_types
import std/json
import std/options
import std/os
import std/strutils
import std/times

axiomIoBoundary()

const
  GateTag = "[bypass-expiry]"
  AuditLogRelPath = "logs/bypass_audit.jsonl"
  ExpiryHours = 48

  ValidPrefixes: array[2, string] = ["#TEMP_DEBT", "#REFACTOR_NEEDED"]

proc parseTimestamp(tsStr: string): Option[Time] =
  if tsStr.len == 0:
    return none(Time)

  var s = tsStr
  if s.endsWith("Z"):
    s = s[0 .. ^2] & "+00:00"

  try:
    let dt = parse(s, "yyyy-MM-dd'T'HH:mm:ss'.'fffzzz")
    return some(dt.toTime())
  except ValueError:
    discard

  try:
    let dt = parse(s, "yyyy-MM-dd'T'HH:mm:sszzz")
    return some(dt.toTime())
  except ValueError:
    discard

  try:
    let dt = parse(s, "yyyy-MM-dd'T'HH:mm:ss")
    return some(dt.toTime())
  except ValueError:
    discard

  none(Time)

func reasonHasValidPrefix(reason: string): bool =
  for p in ValidPrefixes:
    if reason.startsWith(p):
      return true
  false

proc main() {.axiomEffect: IOEffect.} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)
  let auditLogPath = repoRoot / AuditLogRelPath

  if not fileExists(auditLogPath):
    echo GateTag, " PASS: audit log not found at ", auditLogPath, ", nothing to check"
    quit(0)

  let content = readFile(auditLogPath)
  var lines: seq[string] = @[]
  for line in content.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      lines.add(trimmed)

  if lines.len == 0:
    echo GateTag, " PASS: 0 entries in audit log"
    quit(0)

  let now = getTime()
  let expiryCutoff = now - initDuration(hours = ExpiryHours)

  var expired: seq[(int, string, string)] = @[]  # (lineno, commit, timestamp)
  var missingPrefix: seq[(int, string, string)] = @[]  # (lineno, commit, reason)

  for i, line in lines:
    let lineno = i + 1
    var entry: JsonNode
    try:
      entry = parseJson(line)
    except JsonParsingError:
      stderr.writeLine(GateTag, " WARNING: malformed JSON at line ", lineno, ", skipping")
      continue

    let reason = entry.getOrDefault("reason").getStr("")
    let timestampStr = entry.getOrDefault("timestamp").getStr("")
    let commit = if entry.hasKey("commit"): entry["commit"].getStr()
                 elif entry.hasKey("commit_msg"): entry["commit_msg"].getStr()
                 else: "unknown"

    # Check reason prefix
    if reason.len == 0 or not reasonHasValidPrefix(reason):
      missingPrefix.add((lineno, commit, reason))

    # Check expiry
    let dt = parseTimestamp(timestampStr)
    if dt.isSome and dt.get() < expiryCutoff:
      expired.add((lineno, commit, timestampStr))
    elif dt.isNone and timestampStr.len > 0:
      stderr.writeLine(GateTag, " WARNING: unparseable timestamp at line ", lineno, ": ", timestampStr)

  # Report missing prefix warnings
  for (lineno, commit, reason) in missingPrefix:
    let shortReason = if reason.len > 80: reason[0 ..< 80] else: reason
    stderr.writeLine(GateTag, " WARNING: line ", lineno, " commit ", commit,
      ": reason missing #TEMP_DEBT or #REFACTOR_NEEDED prefix (got: \"", shortReason, "\")")

  # Report results
  if expired.len > 0:
    var expiredCommits = ""
    for i in 0 ..< min(5, expired.len):
      if i > 0: expiredCommits.add(", ")
      expiredCommits.add(expired[i][1])
    if expired.len > 5:
      expiredCommits.add(" (+" & $(expired.len - 5) & " more)")
    echo GateTag, " FAIL: ", expired.len, " entries expired (>", ExpiryHours, "h): commit ", expiredCommits
    quit(1)
  else:
    echo GateTag, " PASS: ", lines.len, " entries checked, 0 expired"
    quit(0)

when isMainModule:
  main()
