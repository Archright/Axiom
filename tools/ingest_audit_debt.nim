## tools/ingest_audit_debt.nim — Audit MEDIUM/LOW theater audit findings against the debt registry
##
## Reads docs/audit/theater_audit_2026-07-27.md MEDIUM and LOW sections,
## parses their tables/inline lists, and REPORTS which findings are not yet
## registered in data/debt_registry.json.
##
## Read-only: bin/debt_engine is the sole writer of the registry SSOT and of
## its projections. This tool exits non-zero while unregistered findings remain.
##
## Run: nim c -r --hints:off tools/ingest_audit_debt.nim

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, strutils, sequtils]

const
  AuditPath = "docs/audit/theater_audit_2026-07-27.md"
  RegistryPath = "data/debt_registry.json"

type
  AuditEntry = object
    origId: string       # e.g. "M1", "L5"
    location: string     # file path(s)
    sig: string          # S1, S2, etc.
    summary: string
    severity: string     # "medium" or "low"

func sigToCategory(sig: string): string =
  let s = sig.strip
  if s == "S1": result = "Theater/Always-Pass"
  elif s == "S2": result = "Theater/Swallowed Failure"
  elif s == "S3": result = "Theater/Disguised Stub"
  elif s == "S4": result = "Theater/Vacuous Proof"
  elif s == "S5": result = "Theater/Dead Gate"
  elif s == "S6": result = "Theater/Unenforced Claim"
  else: result = "Theater/Uncategorized"

proc parseLocationLine(line: string): seq[string] =
  let trimmed = line.strip
  if trimmed.len == 0: return
  # Strip surrounding backticks
  var cleaned = trimmed.replace('`', ' ').strip
  # Replace '+' with whitespace to separate file groups
  cleaned = cleaned.replace("+", " ")
  # Split on whitespace only (NOT commas — commas inside line ranges like foo.nim:1,2,3)
  for part in cleaned.splitWhitespace:
    if part.len == 0: continue
    result.add part

proc parseMediumTable(lines: seq[string]; startIdx: int): seq[AuditEntry] =
  ## Parse the MEDIUM section markdown table. startIdx points to the first data row
  ## (after the header and separator rows have been skipped by the caller).
  var i = startIdx
  while i < lines.len:
    let line = lines[i].strip
    i += 1
    if line.len == 0 or line.startsWith("##") or line.startsWith("---"):
      break
    if not line.startsWith("|"):
      continue
    let parts = line.split('|')
    if parts.len < 4:
      continue
    let locPart = parts[1].strip
    let sigPart = parts[2].strip
    let summaryPart = parts[3].strip
    if locPart.len == 0 or sigPart.len == 0 or summaryPart.len == 0:
      continue
    result.add AuditEntry(
      origId: "",
      location: locPart,
      sig: sigPart,
      summary: summaryPart,
      severity: "medium"
    )

proc parseLowLines(lines: seq[string]; startIdx: int): seq[AuditEntry] =
  ## Parse the LOW section: a single prose paragraph where each item is
  ## backtick-delimited: `filepath:lines` followed by optional parenthetical.
  var i = startIdx
  var text = ""
  while i < lines.len:
    let line = lines[i]
    i += 1
    if line.strip.len == 0 or line.startsWith("##"):
      break
    text &= " " & line.strip

  if text.len == 0: return

  # Split on backtick-enclosed items: find `...` patterns
  var pos = 0
  while true:
    let btStart = text.find('`', pos)
    if btStart < 0: break
    let btEnd = text.find('`', btStart + 1)
    if btEnd < 0: break
    let item = text[btStart+1 .. btEnd-1].strip
    pos = btEnd + 1

    # Skip empty backtick content
    if item.len == 0: continue

    # Check for parenthetical description after the closing backtick
    var descPart = ""
    var j = pos
    while j < text.len and text[j] == ' ':
      j += 1
    if j < text.len and text[j] == '(':
      let parenEnd = text.find(')', j)
      if parenEnd >= 0:
        descPart = text[j .. parenEnd]
        pos = parenEnd + 1

    # Remove backticks from item if any remain
    let cleanItem = item.replace("`", "").strip
    if cleanItem.len == 0: continue

    result.add AuditEntry(
      origId: "",
      location: cleanItem,
      sig: "S2",
      summary: "(report-only) " & descPart,
      severity: "low"
    )

proc parseAuditFile(): seq[AuditEntry] =
  let content = readFile(AuditPath)
  let lines = content.splitLines()
  result = @[]

  for i, line in lines:
    if line.startsWith("## MEDIUM (") or line == "## MEDIUM":
      var j = i + 1
      while j < lines.len and lines[j].strip.len == 0:
        j += 1
      if j < lines.len and lines[j].strip.startsWith("|"):
        j += 1
      if j < lines.len and lines[j].strip.startsWith("|"):
        j += 1
      result.add parseMediumTable(lines, j)
    elif line.startsWith("## LOW") or line == "## LOW":
      var j = i + 1
      while j < lines.len and lines[j].strip.len == 0:
        j += 1
      result.add parseLowLines(lines, j)

proc maxDebtId(entries: seq[JsonNode]): int =
  result = 0
  for e in entries:
    let id = e{"id"}.getStr("")
    if id.startsWith("DEBT#"):
      let numPart = id[5..^1]
      let num = parseInt(numPart)
      if num > result: result = num

proc main =
  # 1. Parse audit
  let auditEntries = parseAuditFile()
  if auditEntries.len == 0:
    stderr.writeLine "ERROR: no audit entries parsed — check format of ", AuditPath
    quit(1)

  let midCount = auditEntries.filterIt(it.severity == "medium").len
  let lowCount = auditEntries.filterIt(it.severity == "low").len
  echo "Parsed ", auditEntries.len, " entries from audit (medium=", midCount, ", low=", lowCount, ")"

  # 2. Read existing registry
  let registry = parseJson(readFile(RegistryPath))
  var entries: seq[JsonNode]
  for e in registry{"entries"}.getElems():
    entries.add e

  # 3. Determine next ID
  var nextId = maxDebtId(entries) + 1

  # 4. Build new entries (idempotent: skip if same source + location + summary prefix exists)
  var newEntries: seq[JsonNode]
  var idCount = 0
  let existingSourceLoc: seq[string] = entries.filterIt(it{"source"}.getStr("") == "theater_audit_medium_low").mapIt(
    it{"description"}.getStr("")
  )

  for ae in auditEntries:
    let desc = ae.summary & " [audit: " & ae.location & ", sig: " & ae.sig & "]. Source: docs/audit/theater_audit_2026-07-27.md"

    # Skip if already registered (match by source + location + summary prefix)
    var alreadyExists = false
    for existing in existingSourceLoc:
      if existing.contains(ae.location) and existing.contains(ae.summary[0..min(ae.summary.high, 60)]):
        alreadyExists = true
        break
    if alreadyExists:
      continue

    let idStr = "DEBT#" & $nextId
    nextId += 1

    let category = sigToCategory(ae.sig)

    let entry = %*{
      "id": idStr,
      "category": category,
      "title": ae.summary,
      "impact": ae.severity,
      "severity": ae.severity,
      "description": desc,
      "files": parseLocationLine(ae.location),
      "source": "theater_audit_medium_low",
      "status": "open"
    }

    entries.add entry
    newEntries.add entry
    idCount += 1

  if idCount == 0:
    echo "No unregistered findings — registry already up to date."
    quit(0)

  echo ""
  echo "UNREGISTERED theater audit findings (", idCount, ") — not written to ", RegistryPath
  for entry in newEntries:
    echo "  would add ", entry{"id"}.getStr(), " [", entry{"severity"}.getStr(), "] ",
         entry{"category"}.getStr(), " ", entry{"title"}.getStr()
  echo ""
  echo "Registration is owned by bin/debt_engine; this tool is audit-only."
  quit(1)

when isMainModule:
  main()
