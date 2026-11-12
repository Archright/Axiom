import core/trusted/layer_declaration
axiomLayer "domain"
import std/[strutils, tables]
type
  SeverityLevel* = enum
    sevLow = "low"
    sevMedium = "medium"
    sevHigh = "high"
    sevCritical = "critical"

  DebtParams* = object
    id*: string              # "DEBT#243" — fixed field
    ttl*: string             # "2026-07-15" — fixed field
    severity*: SeverityLevel # enum — compile-time invalid value rejection
    category*: string        # fixed field
    kind*: string            # "debt" | "quirk" | "theater" | "fixme" (default: "debt")
    extra*: Table[string, string] # future extensions only (verifies, proofPath, fallback)
    valid*: bool             # parsing success

func splitByComma(s: string): seq[string] {.raises: [].} =
  ## Split content by commas, respecting quoted strings.
  var parts: seq[string]
  var current = ""
  var inQuote = false
  for ch in s:
    if ch == '"': inQuote = not inQuote
    if ch == ',' and not inQuote:
      parts.add(current.strip())
      current = ""
    else:
      current.add(ch)
  if current.strip().len > 0:
    parts.add(current.strip())
  parts

func stripQuotes(s: string): string {.raises: [].} =
  ## Remove surrounding double-quotes if present.
  if s.startsWith("\"") and s.endsWith("\""):
    result = s[1 ..< ^1]
  else:
    result = s

func parseSeverity*(s: string): SeverityLevel {.raises: [].} =
  ## Convert severity string to enum. Unknown values default to sevMedium.
  case s.toLowerAscii
  of "low": sevLow
  of "medium": sevMedium
  of "high": sevHigh
  of "critical": sevCritical
  else: sevMedium  # default fallback for unknown values

func parseMacroArgs(parts: seq[string]): DebtParams {.raises: [].} =
  ## Parse key="value" pairs from macro call arguments.
  result = DebtParams(severity: sevMedium, valid: false)
  for i, part in parts:
    let p = part.strip()
    if i == 0 and p.startsWith("\"") and p.endsWith("\""):
      result.id = p[1 ..< ^1]
      result.valid = true
    elif "=" in p:
      let eqIdx = p.find('=')
      let key = p[0 ..< eqIdx].strip()
      let val = stripQuotes(p[eqIdx + 1 .. ^1].strip())
      case key
      of "ttl": result.ttl = val
      of "severity": result.severity = parseSeverity(val)
      of "category": result.category = val
      of "kind": result.kind = val
      else: result.extra[key] = val

func parsePragmaArgs(content: string): DebtParams {.raises: [].} =
  ## Parse key: "value" pairs from pragma syntax body.
  ## The `axiomDebt` pragma name may be the first argument
  ## (`{.axiomDebt: "DEBT#NNN", category: "x".}`) or appear later in an
  ## argument list (`{.raises: [], axiomDebt: "DEBT#NNN".}`). Locate the
  ## `axiomDebt` key position-independently so the id is always extracted
  ## regardless of argument order.
  result = DebtParams(severity: sevMedium, valid: false)
  # Locate the standalone `axiomDebt` keyword (followed by ':') anywhere.
  let cl = content.len
  var debtIdx = -1
  var startIdx = 0
  while true:
    let j = content.find("axiomDebt", startIdx)
    if j < 0: break
    var k = j + "axiomDebt".len
    while k < cl and content[k] in {' ', '\t'}: inc k
    if k < cl and content[k] == ':':
      debtIdx = j
      break
    startIdx = j + "axiomDebt".len
  if debtIdx < 0: return
  # Slice from the `axiomDebt` keyword onward; the id is the leading quoted
  # literal after the ':' (ignoring any unrelated args before it).
  var rest = content[debtIdx + "axiomDebt".len .. ^1]
  let colonIdx = rest.find(':')
  if colonIdx < 0: return
  rest = rest[colonIdx + 1 .. ^1].strip()
  let parts = splitByComma(rest)
  for i, part in parts:
    let p = part.strip()
    if i == 0 and p.startsWith("\"") and p.endsWith("\""):
      result.id = p[1 ..< ^1]
      result.valid = true
    elif ":" in p:
      let colonIdx = p.find(':')
      let key = p[0 ..< colonIdx].strip()
      let val = stripQuotes(p[colonIdx + 1 .. ^1].strip())
      case key
      of "category": result.category = val
      else: result.extra[key] = val

func parseDebtParams*(text: string): DebtParams {.raises: [].} =
  ## Parse debt parameters from either format:
  ##   New macro: axiomDebt("DEBT#243", ttl="2026-07-15", severity="medium", category="structural"):
  ##   Old pragma: {.axiomDebt: "DEBT#243", category: "structural".}
  result = DebtParams(severity: sevMedium, valid: false)
  let trimmed = text.strip()
  if "axiomDebt" notin trimmed:
    return

  # Detect format
  if trimmed.startsWith("axiomDebt("):
    # New macro call syntax: axiomDebt("DEBT#243", key="val", ...)
    let openParen = trimmed.find('(')
    let closeParen = trimmed.rfind(')')
    if openParen < 0 or closeParen < 0 or closeParen <= openParen:
      return
    let content = trimmed[(openParen + 1) ..< closeParen]
    return parseMacroArgs(splitByComma(content))

  elif "{." in trimmed:
    # Old pragma syntax: {.axiomDebt: "DEBT#243", category: "structural".}
    let openIdx = trimmed.find("{.")
    let closeIdx = trimmed.find(".}", openIdx)
    if closeIdx < 0: return
    let content = trimmed[(openIdx + 2) ..< closeIdx].strip()
    return parsePragmaArgs(content)

func formatDebtParams*(p: DebtParams): string {.raises: [].} =
  ## DebtParams → human-readable string
  result = p.id
  if p.ttl.len > 0: result &= ", ttl=" & p.ttl
  result &= ", severity=" & $p.severity
  if p.category.len > 0: result &= ", category=" & p.category
