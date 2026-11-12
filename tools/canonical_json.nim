## canonical_json.nim — Deterministic Canonical JSON Serialization
##
## Provides canonical (deterministic) JSON serialization for debt entries
## to prevent Git churn from non-deterministic key ordering.
##
## Keys are sorted alphabetically within each object.
## Entries are sorted by id.
## 2-space indentation, no trailing whitespace.
##
## Run: nim c -o:bin/canonical_json tools/canonical_json.nim

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[json, algorithm, strutils]
import checksums/sha2

# ── Types ──────────────────────────────────────────────────────────────────────

type
  DebtEntry* = object
    id*: string
    category*: string
    severity*: string
    status*: string
    description*: string
    source*: string
    files*: seq[string]

# ── Pure helpers ───────────────────────────────────────────────────────────────

func escapeJsonString(s: string): string =
  ## Escape a string value for JSON output (manual to avoid std/json non-determinism).
  result = "\""
  for c in s:
    case c
    of '\"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\b': result.add("\\b")
    of '\f': result.add("\\f")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else:
      if ord(c) < 0x20:
        result.add("\\u")
        result.add(toHex(ord(c), 4))
      else:
        result.add(c)
  result.add("\"")

func escapeJsonStringPretty(s: string): string =
  ## Escape a string value for pretty-printed JSON output.
  result = "\"" & s & "\""

func canonicalObjectKeys*(): seq[string] =
  ## Return the canonical (alphabetically sorted) key order for DebtEntry.
  result = @["category", "description", "files", "id", "severity", "source", "status"]

func indentLine(indent: int, text: string): string =
  ## Produce an indented line.
  result = ""
  for i in 0 ..< indent:
    result.add("  ")
  result.add(text)

func entryToSortedJson(entry: DebtEntry, indent: int): string =
  ## Convert a single DebtEntry to a canonical JSON object string.
  ## Keys are emitted in alphabetical order.
  let keys = canonicalObjectKeys()
  var lines: seq[string]
  lines.add(indentLine(indent, "{"))
  for idx, key in keys:
    let comma = if idx < keys.len - 1: "," else: ""
    var value: string
    case key
    of "category":
      value = indentLine(indent + 1, "\"category\": " & escapeJsonStringPretty(entry.category) & comma)
    of "description":
      value = indentLine(indent + 1, "\"description\": " & escapeJsonStringPretty(entry.description) & comma)
    of "files":
      # Build the array inline
      var arrParts: seq[string]
      for f in entry.files:
        arrParts.add(escapeJsonString(f))
      let arrStr = "[" & arrParts.join(", ") & "]"
      value = indentLine(indent + 1, "\"files\": " & arrStr & comma)
    of "id":
      value = indentLine(indent + 1, "\"id\": " & escapeJsonStringPretty(entry.id) & comma)
    of "severity":
      value = indentLine(indent + 1, "\"severity\": " & escapeJsonStringPretty(entry.severity) & comma)
    of "source":
      value = indentLine(indent + 1, "\"source\": " & escapeJsonStringPretty(entry.source) & comma)
    of "status":
      value = indentLine(indent + 1, "\"status\": " & escapeJsonStringPretty(entry.status) & comma)
    else: discard
    lines.add(value)
  lines.add(indentLine(indent, "}"))
  result = lines.join("\n")

func debtIdNum(entry: DebtEntry): int =
  ## Extract numeric part from "DEBT#NNN" for sorting.
  let hashPos = entry.id.find('#')
  if hashPos < 0: return 0
  var numStr = ""
  for i in (hashPos + 1) ..< entry.id.len:
    if entry.id[i] in Digits:
      numStr.add(entry.id[i])
    else:
      break
  if numStr.len == 0: return 0
  for c in numStr:
    result = result * 10 + (c.int - '0'.int)

func sortEntries(entries: seq[DebtEntry]): seq[DebtEntry] =
  ## Return entries sorted by numeric ID (ascending).
  result = @entries
  result.sort(proc (a, b: DebtEntry): int =
    cmp(a.debtIdNum, b.debtIdNum)
  )

# ── Public API ─────────────────────────────────────────────────────────────────

proc canonicalJson*(entries: seq[DebtEntry]): string =
  ## Serialize debt entries as canonical JSON.
  ## Keys are sorted alphabetically within each object.
  ## Entries are sorted by id.
  ## No trailing whitespace, consistent indentation.
  let sorted = sortEntries(entries)
  var lines: seq[string]
  lines.add("{")
  lines.add("  \"entries\": [")
  for idx, entry in sorted:
    let objStr = entryToSortedJson(entry, 2)
    let comma = if idx < sorted.len - 1: "," else: ""
    for line in objStr.splitLines():
      lines.add("  " & line)
    if comma.len > 0:
      # Append comma to closing brace line
      lines[^1] = lines[^1] & ","
  lines.add("  ]")
  lines.add("}")
  result = lines.join("\n")

func parseDebtEntry*(node: JsonNode): DebtEntry =
  ## Parse a single JsonNode into a DebtEntry.
  result = DebtEntry(
    id: node{"id"}.getStr(""),
    category: node{"category"}.getStr(""),
    severity: node{"severity"}.getStr(""),
    status: node{"status"}.getStr(""),
    description: node{"description"}.getStr(""),
    source: node{"source"}.getStr(""),
    files: block:
      var fs: seq[string]
      let arr = node{"files"}
      if arr.kind == JArray:
        for item in arr:
          fs.add(item.getStr(""))
      fs
  )

proc parseDebtEntries*(jsonStr: string): seq[DebtEntry] {.raises: [CatchableError].} =
  ## Parse debt entries from JSON string.
  let root = parseJson(jsonStr)
  let entriesNode = root{"entries"}
  if entriesNode.kind == JArray:
    for item in entriesNode:
      result.add(parseDebtEntry(item))

proc isCanonical*(jsonStr: string): bool =
  ## Check if a JSON string is already in canonical form.
  ## Parses, re-serializes, and compares.
  try:
    let entries = parseDebtEntries(jsonStr)
    let canonical = canonicalJson(entries)
    result = (jsonStr == canonical)
  except CatchableError:
    result = false

proc canonicalHash*(entries: seq[DebtEntry]): string =
  ## Compute SHA256 of canonical JSON representation.
  ## Uses checksums/sha2 (NOT std/sha256 which doesn't exist).
  let canonical = canonicalJson(entries)
  var hasher = initSha_256()
  hasher.update(canonical)
  let digest = hasher.digest()
  result = $digest
