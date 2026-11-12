import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import core/crypto/hash_kernel
import core/types/frontend_ir
import std/strutils
import ../../core/trusted/axiom_pragmas_lite
const
  GuardMarkerPrefix* = "# AxiomGuard:"
  GuardMarkerEnd* = "# EndAxiomGuard"

# ---------------------------------------------------------------------------
# Deterministic hash — SHA-256 via checksums/sha2 (cross-platform)
# ---------------------------------------------------------------------------
proc hashGuardContent(kind: string; payload: string): string {.raises: [], axiom: ["(assert (and (>= (str.len s) 0) ast_parse_failed_isolated (>= (str.len s) 0) ast_parse_failed_isolated (>= (str.len kind) 0) (>= (str.len payload) 0) (> (str.len result) 16) (>= result 0)))", "s.length ≥ 0 ∧ ast_parse_failed_isolated ∧ s.length ≥ 0 ∧ ast_parse_failed_isolated ∧ kind.length ≥ 0 ∧ payload.length ≥ 0 ∧ result.length > 16 ∧ (result ≥ 0)"].} =
  let raw = kind & "|" & payload
  let h = sha256Hex(raw)
  result = h
  if result.len > 16:
    result = result[0..<16]

## Build Guard Marker.
proc buildGuardMarker*(kind: string; payload: string): string {.raises: [], axiom: ["(assert (and (>= (str.len kind) 0) (>= (str.len payload) 0)))", "kind.length ≥ 0 ∧ payload.length ≥ 0"].} =
  GuardMarkerPrefix & hashGuardContent(kind, payload) & " (" & kind & ")"
proc extractIndent(line: string): string {.raises: [], axiom: ["(assert (and (>= (str.len line) 0)))", "line.length ≥ 0"].} =
  var i = 0
  while i < line.len and line[i] == ' ':
    result.add(' ')
    inc i
  while i < line.len and line[i] == '\t':
    result.add('\t')
    inc i
proc findProcHeaderLine(source: string; procName: string): int {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) (>= (str.len procName) 0) i -1 (>= lines 0) (>= prefixes 0)))", "source.length ≥ 0 ∧ procName.length ≥ 0 ∧ i ∧ -1 ∧ (lines ≥ 0) ∧ (prefixes ≥ 0)"].} =
  let lines = source.splitLines()
  for i, line in lines:
    let stripped = line.strip()
    let prefixes = ["proc " & procName & "(", "func " & procName & "(",
                    "proc " & procName & " ", "func " & procName & " "]
    for p in prefixes:
      if stripped.startsWith(p):
        return i
  return -1
proc findProcBodyStartLine*(source: string; headerLine: int): int {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) (and (>= headerLine -9223372036854775808) (<= headerLine 9223372036854775807)) (< i (str.len lines)) i (+ i 1) -1 (and (>= i 0) (< i lines))))", "source.length ≥ 0 ∧ headerLine ≥ -9223372036854775808 ∧ headerLine ≤ 9223372036854775807 ∧ i < lines.length ∧ i ∧ i + 1 ∧ -1 ∧ ((i ≥ 0) ∧ (i < lines))"].} =
  ## Hardened proc-body detection: tracks parenthesis depth, skips strings
  ## and comments, and only matches '=' at depth 0 — the actual signature/body
  ## separator. This prevents false matches inside default parameters, type
  ## annotations, or inline comments.
  let lines = source.splitLines()
  var parenDepth = 0
  var inString = false
  var stringChar = '\0'
  var i = headerLine
  while i < lines.len:
    let line = lines[i]
    var j = 0
    while j < line.len:
      let c = line[j]
      if inString:
        if c == stringChar:
          inString = false
        elif c == '\\' and j + 1 < line.len:
          inc j
      elif c == '#' and (j == 0 or line[j-1] != '#'):
        break
      elif c == '"' or c == '\'':
        inString = true
        stringChar = c
      elif c == '(' or c == '[' or c == '{':
        inc parenDepth
      elif c == ')' or c == ']' or c == '}':
        if parenDepth > 0: dec parenDepth
      elif c == '=' and parenDepth == 0:
        let afterEq = j + 1
        if afterEq < line.len:
          let rest = line[afterEq..^1].strip()
          if rest.len == 0 or rest.startsWith("#"):
            return i + 1
          else:
            return i
        else:
          return i + 1
      inc j
    inc i
  return -1

# ---------------------------------------------------------------------------
# Strip / replace helpers
# ---------------------------------------------------------------------------

## Strip All Guard Blocks.
proc stripAllGuardBlocks*(source: string): string {.raises: [], axiom: ["(assert (and (>= (str.len source) 0) (< i (str.len lines)) (and (and (>= i 0) (< i lines)) (< i lines))))", "source.length ≥ 0 ∧ i < lines.length ∧ (((i ≥ 0) ∧ (i < lines)) ∧ (i < lines))"].} =
  ## Remove every AxiomGuard .. EndAxiomGuard block for clean re-injection.
  ## If a guard block lacks its end marker (corruption from prior run),
  ## preserve all lines from that point instead of stripping to EOF.
  let lines = source.splitLines()
  var newLines: seq[string] = @[]
  var i = 0
  while i < lines.len:
    if lines[i].strip().startsWith(GuardMarkerPrefix):
      let guardStart = i
      inc i
      var foundEnd = false
      while i < lines.len:
        let s = lines[i].strip()
        if s.startsWith(GuardMarkerEnd):
          inc i
          foundEnd = true
          break
        inc i
      if not foundEnd:
        for j in guardStart ..< lines.len:
          newLines.add(lines[j])
        break
      continue
    newLines.add(lines[i])
    inc i
  newLines.join("\n")

# ---------------------------------------------------------------------------
# Guard injectors
# ---------------------------------------------------------------------------

## Inject Invariant Guards.
proc injectInvariantGuards*(source: string; ir: FrontendIrNode): string {.raises: [], axiom: ["(assert (and (< headerLine 0) (< bodyLine 0) (< bodyLine (str.len lines)) (and (= (str.len baseIndent) 0) (> bodyLine 0)) (= (str.len blockLines) 0) (= i (- bodyLine 1)) invPre invPost invLoop (= result source) (>= lines 0) (>= blockLines 0) (>= result 0) (>= baseIndent 0)))", "headerLine < 0 ∧ bodyLine < 0 ∧ bodyLine < lines.length ∧ baseIndent.length = 0 ∧ bodyLine > 0 ∧ blockLines.length = 0 ∧ i = bodyLine - 1 ∧ invPre ∧ invPost ∧ invLoop ∧ result = source ∧ (lines ≥ 0) ∧ (blockLines ≥ 0) ∧ (result ≥ 0) ∧ (baseIndent ≥ 0)"].} =
  ## Inject doAssert statements for invariants at function entry.
  result = source
  if ir.name.len == 0 or ir.invariants.len == 0:
    return

  let headerLine = findProcHeaderLine(result, ir.name)
  if headerLine < 0:
    return

  let bodyLine = findProcBodyStartLine(result, headerLine)
  if bodyLine < 0:
    return

  let lines = result.splitLines()
  var baseIndent = ""
  if bodyLine < lines.len:
    baseIndent = extractIndent(lines[bodyLine])
    if baseIndent.len == 0 and bodyLine > 0:
      baseIndent = extractIndent(lines[bodyLine - 1]) & "  "

  var blockLines: seq[string] = @[]
  for inv in ir.invariants:
    let marker = buildGuardMarker("inv" & $inv.scope, inv.predicate)
    let scopeLabel = case inv.scope
      of invPre: "pre"
      of invPost: "post"
      of invLoop: "loop"
    blockLines.add(baseIndent & marker)
    blockLines.add(baseIndent & "doAssert " & inv.predicate &
      "  # Axiom-IR " & scopeLabel & " condition")

  if blockLines.len == 0:
    return

  blockLines.add(baseIndent & GuardMarkerEnd)

  var newLines: seq[string] = @[]
  for i, line in lines:
    newLines.add(line)
    if i == bodyLine - 1:
      for bl in blockLines:
        newLines.add(bl)
  result = newLines.join("\n")

## Inject Effect Pragmas.
proc injectEffectPragmas*(source: string; ir: FrontendIrNode): string {.raises: [], axiom: ["(assert (and (< headerLine 0) (= (str.len pragmaText) 0) effNoSideEffect effPure effIO effNetwork effFileSystem effUnknown (= result source) (>= lines 0) (>= result 0)))", "headerLine < 0 ∧ pragmaText.length = 0 ∧ effNoSideEffect ∧ effPure ∧ effIO ∧ effNetwork ∧ effFileSystem ∧ effUnknown ∧ result = source ∧ (lines ≥ 0) ∧ (result ≥ 0)"].} =
  ## Inject pragmas like into proc signature.
  result = source
  if ir.name.len == 0 or ir.effectConstraints.len == 0:
    return

  let headerLine = findProcHeaderLine(result, ir.name)
  if headerLine < 0:
    return

  var lines = result.splitLines()
  var procLine = lines[headerLine]

  for eff in ir.effectConstraints:
    let pragmaText = case eff.kind
      of effNoSideEffect: ""
      of effPure: ""
      of effIO: "{.tags: [ReadIOEffect].}"
      of effNetwork: "{.tags: [ReadIOEffect].}"
      of effFileSystem: "{.tags: [ReadDirEffect].}"
      of effUnknown: ""
    if pragmaText.len == 0:
      continue
    if procLine.contains(pragmaText):
      continue
    let marker = buildGuardMarker("effect", $eff.kind)
    let indent = extractIndent(procLine)
    lines[headerLine] = indent & marker & "\n" & indent & pragmaText & "\n" & procLine
    result = lines.join("\n")
    return

## Weave Guards.
proc weaveGuards*(source: string; ir: FrontendIrNode): string {.raises: [], axiom: ["(assert (and ast_parse_failed_isolated (>= (str.len source) 0)))", "ast_parse_failed_isolated ∧ source.length ≥ 0"].} =
  ## Main entry point: apply all Axiom-IR guards into Nim source.
  ## Always strips old guards first so the result reflects the latest IR.
  result = stripAllGuardBlocks(source)
  result = injectInvariantGuards(result, ir)
  result = injectEffectPragmas(result, ir)
{.pop.}

