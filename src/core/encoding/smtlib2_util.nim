import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
import std/strutils
import std/sets

## Extract all identifier tokens from an SMT-LIB2 string.
## Filters out reserved words, operators, and numeric literals.
func extractSmtIdentifiers*(smt: string): seq[string] {.raises: [].} =
  const reserved = ["assert", "and", "or", "not", ">=", "<=", ">", "<", "=",
                    "str.len", "seq.len", "forall", "exists",
                    "Int", "Nat", "Bool", "String", "Real", "Char", "Seq",
                    "true", "false"]
  var tokens: seq[string] = @[]
  var current = ""
  for ch in smt:
    if ch in {'(', ')', ' ', '\t', '\n'}:
      if current.len > 0:
        tokens.add(current)
        current = ""
    else:
      current.add(ch)
  if current.len > 0:
    tokens.add(current)
  var seen = initHashSet[string]()
  for tok in tokens:
    if tok.len == 0: continue
    if tok[0].isAlphaAscii or tok[0] == '_':
      if tok notin reserved and tok notin seen:
        seen.incl(tok)
        result.add(tok)

## Scan source for an @axiom-hint annotation immediately preceding the
## named function definition. Returns the raw SMT string inside smt="...".
func extractAxiomHintForFunction*(source, functionName: string): string {.raises: [].} =
  let lines = source.splitLines()
  var i = 0
  while i < lines.len:
    let line = lines[i].strip()
    if line.startsWith("# @axiom-hint:") and line.contains("smt=\""):
      var j = i + 1
      while j < lines.len:
        let nextLine = lines[j].strip()
        if nextLine.len == 0 or nextLine.startsWith("#"):
          inc j
          continue
        if (nextLine.startsWith("func ") or nextLine.startsWith("proc ") or
            nextLine.startsWith("template ") or nextLine.startsWith("macro ")):
          let nameIdx = nextLine.find(functionName)
          if nameIdx >= 0:
            let afterName = nextLine[nameIdx + functionName.len .. ^1]
            if afterName.contains("("):
              let smtStart = line.find("smt=\"")
              if smtStart >= 0:
                let start = smtStart + 5
                var endIdx = start
                while endIdx < line.len and line[endIdx] != '"':
                  inc endIdx
                return line[start ..< endIdx]
        break
    inc i

func isVacuousPrimitiveSmt*(smt: string): bool {.raises: [].} =
  let trimmed = smt.strip()
  trimmed == "vacuous_primitive" or
    trimmed == "(assert vacuous_primitive)"

func sourceHasAxiomPurePragma*(source: string): bool {.raises: [].} =
  for line in source.splitLines():
    let stripped = line.strip()
    if (stripped.contains("{.push") and stripped.contains("axiomPure")) or
       stripped.contains("{.pragma: axiomPure"):
      return true
  false

func isCertifiedExemptFunctionSource*(source, functionName: string): bool {.raises: [].} =
  if sourceHasAxiomPurePragma(source):
    return true
  let hintSmt = extractAxiomHintForFunction(source, functionName)
  if hintSmt.len > 0 and isVacuousPrimitiveSmt(hintSmt):
    return true
  false

{.pop.}
