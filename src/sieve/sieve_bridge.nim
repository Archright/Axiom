import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Z3 artifact → Subjective Logic opinion mapping.
## Deterministic lookup: same Z3 output → same BinomialOpinion.

import std/strutils
import sieve/subjective_logic

func isTokenBoundary(source: string; pos: int): bool {.raises: [].} =
  ## Check if position is at a token boundary (not inside an identifier)
  if pos < 0 or pos >= source.len: return true
  source[pos] notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}

func findIsolatedOccurrences*(source, token: string): seq[int] {.raises: [].} =
  ## Find all occurrences of token that satisfy word boundary on both sides.
  result = @[]
  var pos = 0
  while pos <= source.len - token.len:
    let idx = source.find(token, pos)
    if idx < 0: break
    # Check boundary BEFORE token (idx-1) and AFTER token (idx+token.len)
    if isTokenBoundary(source, idx - 1) and isTokenBoundary(source, idx + token.len):
      result.add(idx)
    pos = idx + 1

func mapUnsatCoreToOpinion*(coreVars: seq[string]; sourceCode: string): BinomialOpinion {.noSideEffect, raises: [].} =
  ## Deterministic mapping: Z3 unsat core → BinomialOpinion.
  ## Uses token boundary checking for robust identifier matching.
  ## Checks both left and right of variable for non-linear operators.
  if coreVars.len == 0:
    return BinomialOpinion(b: 0.02, d: 0.90, u: 0.08, a: 0.4)  # low danger = safe

  var hasNonLinear = false
  var hasLoopContext = false

  for varName in coreVars:
    if varName.len == 0: continue
    let occurrences = findIsolatedOccurrences(sourceCode, varName)
    if occurrences.len == 0: continue

    for occ in occurrences:
      # Right-hand check: varName followed by " * " or " / "
      let afterVar = occ + varName.len
      for pat in [" * ", " / "]:
        if afterVar + pat.len <= sourceCode.len and
           sourceCode[afterVar ..< afterVar + pat.len] == pat:
          hasNonLinear = true
          break
      # Left-hand check: varName preceded by " * " or " / "
      if not hasNonLinear:
        for pat in [" * ", " / "]:
          let beforeStart = occ - pat.len
          if beforeStart >= 0 and sourceCode[beforeStart ..< occ] == pat:
            hasNonLinear = true
            break
      if hasNonLinear: break

    # Loop context: 20-char lookback window
    if not hasLoopContext:
      for occ in occurrences:
        let lookback = max(0, occ - 20)
        let prefixZone = sourceCode[lookback ..< occ]
        if "while" in prefixZone or "for" in prefixZone:
          hasLoopContext = true
          break

  # Deterministic opinion mapping table
  if hasNonLinear:
    BinomialOpinion(b: 0.90, d: 0.02, u: 0.08, a: 0.4)  # high danger
  elif hasLoopContext:
    BinomialOpinion(b: 0.85, d: 0.05, u: 0.10, a: 0.4)  # high danger
  else:
    let confidence = min(0.95, 0.50 + coreVars.len.float * 0.05)
    BinomialOpinion(b: confidence, d: 0.02, u: 1.0 - 0.02 - confidence, a: 0.4)  # scaled danger
{.pop.}
