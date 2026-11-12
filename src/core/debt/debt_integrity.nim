{.push raises: [].}
## src/core/debt/debt_integrity.nim — Debt Integrity Hash Engine (SSOT)
##
## Provides deterministic hash computation for architecture debt tracking.
## Identity separation: rawContentHash ≠ canonicalSyntaxHash.
##
## API:
##   - computeRawContentHash(src: string): string  — SHA-256 exact bytes → "sha256:" + hex
##   - computeCanonicalSyntaxHash(src: string): string  — delegates to AST kernel PNode v2 → "sha256:v2:nim-pnode-canonical-v2:" + hex
##   - debtTargets(registryJson: JsonNode): seq[string]  — extract debt target files
##   - validateHashBinding(entry, rawHash, canonicalHash): HashStatus
##   - hashStatusToStr: HashStatus → string

import core/trusted/layer_declaration
axiomLayer "domain"

import std/[json, os, strutils, algorithm, sets]
import core/ast_kernel
import core/crypto/hash_kernel
import core/results

type
  HashStatus* = enum
    ok
    rawOnly
    substantive

func computeRawContentHash*(src: string): string =
  ## Compute SHA-256 digest of exact file bytes.
  ## Returns self-describing "sha256:" prefix + hex digest.
  "sha256:" & computeContentHash(src)

func stripLineComment*(line: string; startIdx: var int): string =
  ## Strip line comment from a line, starting at position startIdx.
  ## Preserves # inside string and character literals.
  var inStr = false
  var inCh = false
  var escaped = false
  while startIdx < line.len:
    let c = line[startIdx]
    if escaped:
      escaped = false
      inc startIdx
      continue
    case c
    of '\\':
      if inStr or inCh:
        escaped = true
    of '"':
      if not inCh:
        inStr = not inStr
    of '\'':
      if not inStr:
        inCh = not inCh
    of '#':
      if not inStr and not inCh:
        return line[0..<startIdx]
      inc startIdx
      continue
    else:
      discard
    inc startIdx
  line

func stripBlockComments*(src: string): string =
  ## Remove Nim block comments #[...]# from source.
  ## Handles nested block comments.
  var output: string
  var i = 0
  while i < src.len:
    if src[i] == '#':
      if i + 1 < src.len:
        let next = src[i + 1]
        if next == '[':
          var depth = 1
          inc i, 2
          while i < src.len and depth > 0:
            if src[i] == '#' and i + 1 < src.len and src[i + 1] == ']':
              dec depth
              inc i
              if i < src.len and src[i] == '#':
                inc i
            elif src[i] == '[' and i + 1 < src.len and src[i + 1] == '#':
              inc depth
              inc i
              inc i
            else:
              inc i
          inc i
        else:
          output.add(src[i])
          inc i
      else:
        output.add(src[i])
        inc i
    else:
      output.add(src[i])
      inc i
  output

func stripNimComments*(src: string): string =
  ## Remove Nim-style comments outside string/char literals.
  ## Handles: #[...]# block comments (nested), # line comments,
  ## string literals ("..."), char literals ('...'), with escape handling.
  ## Replaces comment content with spaces, then removes whitespace-only lines.
  var buf = newStringOfCap(src.len)
  var i = 0
  var inBlockComment = 0
  var inStr = false
  var inCh = false
  var escaped = false

  while i < src.len:
    let c = src[i]

    if inBlockComment > 0:
      if c == '#' and i + 1 < src.len and src[i + 1] == ']':
        dec inBlockComment
        buf.add(' ')
        inc i
        if i < src.len and src[i] == '#':
          inc i
      elif c == '#' and i + 1 < src.len and src[i + 1] == '[':
        inc inBlockComment
        buf.add(' ')
        inc i
        inc i
      else:
        buf.add(' ')
        inc i
      continue

    if escaped:
      escaped = false
      buf.add(c)
      inc i
      continue

    case c
    of '\\':
      if inStr or inCh:
        escaped = true
      buf.add(c)
      inc i
    of '"':
      if not inCh:
        inStr = not inStr
      buf.add(c)
      inc i
    of '\'':
      if not inStr:
        inCh = not inCh
      buf.add(c)
      inc i
    of '#':
      if inStr or inCh:
        buf.add(c)
        inc i
      elif i + 1 < src.len and src[i + 1] == '[':
        inc inBlockComment
        buf.add(' ')
        inc i
        inc i
      else:
        while i < src.len and src[i] != '\n':
          buf.add(' ')
          inc i
        if i < src.len and src[i] == '\n':
          buf.add('\n')
          inc i
    of '\r', '\n':
      buf.add(c)
      inc i
    else:
      buf.add(c)
      inc i

  var lines = buf.splitLines()
  var kept: seq[string]
  for line in lines:
    var allWs = true
    for ch in line:
      if ch notin {' ', '\t'}:
        allWs = false
        break
    if not allWs:
      kept.add(line)
  result = kept.join("\n")

func normalizeWhitespace*(src: string): string =
  ## Normalize whitespace for canonical form.
  ## Collapses multiple spaces/tabs, preserves newlines, trims trailing whitespace.
  var output: string
  var prevWs = false
  for ch in src:
    if ch in {' ', '\t'}:
      if not prevWs and output.len > 0:
        output.add(' ')
      prevWs = true
    elif ch == '\n':
      while output.len > 0 and output[^1] == '\n':
        output.setLen(output.len - 1)
      output.add('\n')
      prevWs = false
    else:
      output.add(ch)
      prevWs = false
  while output.len > 0 and output[^1] in {' ', '\n'}:
    output.setLen(output.len - 1)
  output

proc computeCanonicalSyntaxHash*(src: string): string =
  ## Compute canonical syntax hash for semantic drift detection.
  ##
  ## Delegates to AST kernel PNode-based canonicalization (v2):
  ##   1. Parse source to PNode (fail-closed: parse error → "")
  ##   2. Canonicalize PNode structure (order-independent for sets)
  ##   3. SHA-256 with "sha256:v2:nim-pnode-canonical-v2:" prefix
  ##
  ## v1 text-based canonicalization is rejected; v2 is the only accepted format.

  let hashResult = computeCanonicalAstHash(src)
  if hashResult.isOk:
    hashResult.get()
  else:
    ""

proc debtTargets*(registryJson: JsonNode): seq[string] {.raises: [CatchableError].} =
  ## Extract debt target files from architecture_debt.json.
  ## Returns normalized paths, deduplicated and deterministically sorted.
  const archDebtPath = "data/architecture_debt.json"
  var rawJson: JsonNode
  if registryJson.isNil:
    if fileExists(archDebtPath):
      try:
        rawJson = parseJson(readFile(archDebtPath))
      except CatchableError:
        return @[]
    else:
      return @[]
  else:
    rawJson = registryJson

  if not rawJson.hasKey("entries"):
    return @[]

  var entriesNode: JsonNode = newJNull()
  try:
    entriesNode = rawJson["entries"]
  except CatchableError:  # axiom:best-effort(entries field absent/corrupt -> empty target set; callers fail-closed on empty debt registry)
    return @[]

  if entriesNode.isNil or entriesNode.kind != JArray:
    return @[]

  var targets: HashSet[string]
  for entry in entriesNode:
    if entry.hasKey("file"):
      try:
        let filePath = entry["file"].getStr().strip()
        if filePath.len > 0:
          targets.incl(filePath)
      except CatchableError:  # axiom:best-effort(malformed registry entry skipped from debt-target set; the registry validity is enforced by check_debt_sync structure checks, not by target extraction)
        discard

  var filePaths: seq[string]
  for t in targets:
    filePaths.add(t)
  filePaths.sort()
  return filePaths

proc parseArchitectureDebt*(path: string): JsonNode {.raises: [CatchableError].} =
  const archDebtPath = "data/architecture_debt.json"
  let actualPath = if path.len == 0: archDebtPath else: path
  if not fileExists(actualPath):
    return newJObject()
  parseJson(readFile(actualPath))

func isValidV2CanonicalHash*(hash: string): bool {.raises: [].} =
  hash.startsWith("sha256:v2:nim-pnode-canonical-v2:")

func validateHashBinding*(entry: JsonNode; rawHash: string; canonicalHash: string): HashStatus =
  ## Validate hash changes between expected and actual values.
  ##
  ## Fail-closed for v1/unknown canonical prefixes:
  ##   - v2 prefix (`sha256:v2:nim-pnode-canonical-v2:`): proceed with comparison
  ##   - v1 prefix (`sha256:v1:`): reject → substantive
  ##   - unknown/empty prefix: reject → substantive
  ##
  ## Returns:
  ##   - ok: both raw and canonical match
  ##   - rawOnly: only raw changed (comment/whitespace change, acceptable)
  ##   - substantive: canonical changed or v1/unknown prefix (logic change or invalid format)

  let expectedRaw = entry{"rawContentHash"}.getStr()
  let expectedCanonical = entry{"canonicalSyntaxHash"}.getStr()

  if canonicalHash.len == 0 or not isValidV2CanonicalHash(canonicalHash):
    return substantive
  if expectedCanonical.len > 0 and not isValidV2CanonicalHash(expectedCanonical):
    return substantive

  if rawHash == expectedRaw and canonicalHash == expectedCanonical:
    return ok
  elif rawHash == expectedRaw:
    return ok
  elif canonicalHash == expectedCanonical:
    return rawOnly
  else:
    return substantive

func hashStatusToStr*(status: HashStatus): string =
  case status
  of ok: "ok"
  of rawOnly: "raw-only"
  of substantive: "substantive"

proc getExpectedHashes*(filePath: string): (string, string) {.raises: [CatchableError].} =
  ## Compute both raw and canonical hashes for a file.
  ## Returns (rawContentHash, canonicalSyntaxHash).
  if not fileExists(filePath):
    return ("", "")
  let content = readFile(filePath)
  let rawHash = computeRawContentHash(content)
  let canonicalHash = computeCanonicalSyntaxHash(content)
  (rawHash, canonicalHash)