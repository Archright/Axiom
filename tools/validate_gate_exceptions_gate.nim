## validate_gate_exceptions_gate.nim — Schema validation for gate_exceptions.json.
##
## Required fields: gate, check, expires, review_action, approved_by
## Exit 0 if valid, exit 1 if invalid.

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
  GateTag = "[validate-gate-exceptions]"
  ExceptionsRelPath = "data/gate_exceptions.json"
  RequiredFields: array[5, string] = [
    "gate", "check", "expires", "review_action", "approved_by"
  ]

proc parseIsoDate(dateStr: string): Option[Time] =
  ## Attempt to parse an ISO 8601 date string.
  if dateStr.len == 0:
    return none(Time)
  let s = dateStr.replace("Z", "+00:00")
  # Try common formats
  for fmt in ["yyyy-MM-dd'T'HH:mm:ss'.'fffzzz",
              "yyyy-MM-dd'T'HH:mm:sszzz",
              "yyyy-MM-dd'T'HH:mm:ss",
              "yyyy-MM-dd"]:
    try:
      let dt = parse(s, fmt)
      return some(dt.toTime())
    except ValueError:
      discard
  none(Time)

proc main() {.axiomEffect: IoEffect.} =
  let repoRoot = findRepoRoot()
  setCurrentDir(repoRoot)
  let exceptionsPath = repoRoot / ExceptionsRelPath

  if not fileExists(exceptionsPath):
    echo GateTag, " FAIL: exceptions file not found: ", exceptionsPath
    quit(1)

  var data: JsonNode
  try:
    data = parseJson(readFile(exceptionsPath))
  except JsonParsingError as e:
    echo GateTag, " FAIL: malformed JSON: ", e.msg
    quit(1)

  let exceptions = data.getOrDefault("exceptions")
  if exceptions.isNil or exceptions.kind != JArray:
    echo GateTag, " FAIL: 'exceptions' key missing or not an array"
    quit(1)

  var errors: seq[string] = @[]
  let now = getTime()

  var idx = 0
  for exc in exceptions:
    # Each element must be a JObject (an exception entry)
    if exc.kind != JObject:
      errors.add("Exception #" & $idx & ": not a JSON object")
      inc idx
      continue

    for field in RequiredFields:
      if not exc.hasKey(field):
        errors.add("Exception #" & $idx & ": missing required field '" & field & "'")

    if exc.hasKey("expires"):
      let expiresStr = exc["expires"].getStr()
      let dt = parseIsoDate(expiresStr)
      if dt.isSome:
        if dt.get() < now:
          let pattern = exc.getOrDefault("pattern").getStr("unknown")
          echo "⚠ WARNING: Exception #", idx, " (", pattern, ") EXPIRED on ", expiresStr
      elif expiresStr.len > 0:
        errors.add("Exception #" & $idx & ": invalid date format '" &
          expiresStr & "' (expected ISO 8601)")
    inc idx

  if errors.len > 0:
    for e in errors:
      echo "❌ ", e
    quit(1)

  echo "✅ gate_exceptions.json: all ", exceptions.len, " exceptions valid"
  quit(0)

when isMainModule:
  main()
