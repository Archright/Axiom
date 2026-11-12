## debt_scanner.nim — Shared {.axiomDebt.} Pragma Scanner
##
## Comment/string-aware state-machine scanner that finds {.axiomDebt.}
## pragmas in Nim source files. Reusable by both the debt registry generator
## and the debt integrity gate runner.
##
## Uses `parseDebtParams` from `core/utils/debt_params.nim` for parameter
## parsing to avoid duplicating parsing logic.

import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

import std/[os, strutils]
import core/utils/debt_params
import core/axiom_pragmas

# ── Types ────────────────────────────────────────────────────────────────────

type
  ScannedDebt* = object
    ## A single {.axiomDebt.} annotation found in source.
    id*: string           ## "DEBT#243"
    kind*: string         ## "debt" | "quirk" | "theater" | "fixme" (default: "debt")
    category*: string
    impact*: string       ## severity as string ("Low", "Medium", "High", "Critical")
    file*: string         ## relative path to source file
    line*: int            ## line number of the pragma
    declaration*: string  ## enclosing proc/type name

# ── Constants ────────────────────────────────────────────────────────────────

const
  MaxLookbackLines* = 30  ## Max lines to scan backward for enclosing declaration

# ── Pure Helpers ─────────────────────────────────────────────────────────────

func extractDeclName(content: string, pragmaLine: int): string {.raises: [].} =
  ## Walk backward from pragmaLine to find the enclosing declaration name.
  let lines = content.split('\n')
  let startIdx = min(pragmaLine - 1, lines.len - 1)
  for i in countdown(startIdx, max(0, startIdx - MaxLookbackLines)):
    let line = lines[i].strip()
    for kw in ["proc ", "func ", "method ", "template ", "macro ",
                "iterator ", "converter ", "type ", "const ", "let ", "var "]:
      if line.startsWith(kw):
        var rest = line[kw.len .. ^1]
        # Handle export marker
        if '*' in rest:
          rest = rest.split('*')[0]
        # Handle parenthesis (end of name for procs)
        if '(' in rest:
          rest = rest.split('(')[0]
        # Handle equals (end of name for types/consts/lets/vars)
        if '=' in rest:
          rest = rest.split('=')[0]
        rest = rest.strip()
        if rest.len > 0:
          return rest
        break
  result = ""

func severityToImpact*(sev: SeverityLevel): string {.raises: [].} =
  ## Convert DebtParams severity enum to display-friendly impact string.
  case sev
  of sevLow: "Low"
  of sevMedium: "Medium"
  of sevHigh: "High"
  of sevCritical: "Critical"

# ── Core Scanner ─────────────────────────────────────────────────────────────

proc scanFile(filePath: string, content: string): seq[ScannedDebt] {.raises: [].} =
  ## Scan a single .nim file for {.axiomDebt.} pragmas.
  ## Uses comment/string-aware state machine (NOT regex).
  result = @[]

  var pos = 0
  var lineNum = 1
  let totalLen = content.len

  while pos < totalLen:
    let c = content[pos]

    # ── Line comment (# but not #[) ──
    if c == '#' and not (pos + 1 < totalLen and content[pos + 1] == '['):
      while pos < totalLen and content[pos] != '\n':
        pos += 1
      continue

    # ── Block comment (#[ ... ]#, nested) ──
    if c == '#' and pos + 1 < totalLen and content[pos + 1] == '[':
      pos += 2
      var depth = 1
      while pos < totalLen and depth > 0:
        if content[pos] == '#' and pos + 1 < totalLen and content[pos + 1] == '[':
          depth += 1
          pos += 2
        elif content[pos] == ']' and pos + 1 < totalLen and content[pos + 1] == '#':
          depth -= 1
          pos += 2
        else:
          if content[pos] == '\n': lineNum += 1
          pos += 1
      continue

    # ── Triple-quoted string ──
    if c == '"' and pos + 2 < totalLen and
       content[pos + 1] == '"' and content[pos + 2] == '"':
      pos += 3
      while pos + 2 < totalLen:
        if content[pos] == '"' and content[pos + 1] == '"' and content[pos + 2] == '"':
          pos += 3
          break
        if content[pos] == '\\':
          pos += 1  # skip escaped char
        if pos < totalLen and content[pos] == '\n': lineNum += 1
        pos += 1
      continue

    # ── Regular string ──
    if c == '"':
      pos += 1
      while pos < totalLen and content[pos] != '"':
        if content[pos] == '\\':
          pos += 1  # skip escaped char
        if pos < totalLen and content[pos] == '\n': lineNum += 1
        pos += 1
      if pos < totalLen: pos += 1
      continue

    # ── Pragma block ({. ... .}) with string-aware nesting ──
    if c == '{' and pos + 1 < totalLen and content[pos + 1] == '.':
      let pragmaLine = lineNum
      pos += 2  # Skip {.

      # Collect pragma body until .}, tracking strings and nested {.
      var pragmaBody = ""
      var depth = 1
      var inStr = false
      var inTripleStr = false

      while pos + 1 < totalLen and depth > 0:
        # String state tracking inside pragma
        if inTripleStr:
          if content[pos] == '"' and pos + 2 < totalLen and
             content[pos + 1] == '"' and content[pos + 2] == '"':
            inTripleStr = false
            pragmaBody.add("\"\"\"")
            pos += 3
            continue
          if content[pos] == '\\':
            pragmaBody.add(content[pos .. min(pos + 1, totalLen - 1)])
            pos += 2
            continue
          if content[pos] == '\n': lineNum += 1
          pragmaBody.add(content[pos])
          pos += 1
          continue

        if inStr:
          if content[pos] == '\\' and pos + 1 < totalLen:
            pragmaBody.add(content[pos .. pos + 1])
            pos += 2
            continue
          if content[pos] == '"':
            inStr = false
            pragmaBody.add("\"")
            pos += 1
            continue
          if content[pos] == '\n': lineNum += 1
          pragmaBody.add(content[pos])
          pos += 1
          continue

        # Normal state: detect string starts, nested {., and closing .}
        if content[pos] == '"' and pos + 2 < totalLen and
           content[pos + 1] == '"' and content[pos + 2] == '"':
          inTripleStr = true
          pragmaBody.add("\"\"\"")
          pos += 3
          continue

        if content[pos] == '"':
          inStr = true
          pragmaBody.add("\"")
          pos += 1
          continue

        if content[pos] == '{' and pos + 1 < totalLen and content[pos + 1] == '.':
          depth += 1
          pragmaBody.add("{.")
          pos += 2
          continue

        if content[pos] == '.' and pos + 1 < totalLen and content[pos + 1] == '}':
          depth -= 1
          if depth == 0:
            pos += 2
            break
          pragmaBody.add(".}")
          pos += 2
          continue

        if content[pos] == '\n': lineNum += 1
        pragmaBody.add(content[pos])
        pos += 1

      # Check for axiomDebt in collected pragma body
      if depth == 0 and "axiomDebt" in pragmaBody:
        # Reconstruct full pragma text for parseDebtParams
        let fullPragma = "{." & pragmaBody & ".}"
        let params = parseDebtParams(fullPragma)
        if params.valid:
          let declName = extractDeclName(content, pragmaLine)
          result.add(ScannedDebt(
            id: params.id,
            kind: params.kind,
            category: params.category,
            impact: severityToImpact(params.severity),
            file: filePath,
            line: pragmaLine,
            declaration: declName,
          ))
      continue

    if c == '\n': lineNum += 1
    pos += 1

# ── Public API ───────────────────────────────────────────────────────────────

proc scanDebtPragmas*(srcDir: string): seq[ScannedDebt] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Walk all .nim files under `srcDir` and extract {.axiomDebt.} pragmas.
  ## Returns a sequence of ScannedDebt objects.
  result = @[]

  if not dirExists(srcDir):
    return

  for path in walkDirRec(srcDir):
    if not path.endsWith(".nim"): continue
    var content: string
    try:
      content = readFile(path)
    except IOError:
      continue
    let entries = scanFile(path, content)
    result.add(entries)

{.pop.}
