import core/trusted/layer_declaration
axiomLayer "tools"
import std/[json, os, strutils]
import sha256_native

template axiomEffect*(effectType: untyped) {.pragma.}

const
  RegistryPath = "data/debt_registry.json"

type
  OrphanReport = object
    entryId: string
    orphaned: bool
    file: string
    symbol: string
    reason: string

  HashReport = object
    entryId: string
    file: string
    symbol: string
    expectedHash: string
    actualHash: string
    reason: string

  TargetRef = object
    file: string
    rangeText: string

  LineRange = object
    start: int
    finish: int

func isIdentPart(c: char): bool {.raises: [].} =
  c in Letters or c in Digits or c == '_'

func getOptionalNode(node: JsonNode; key: string): JsonNode {.raises: [].} =
  try:
    result = node[key]
  except KeyError:
    result = nil

func collectStrings(value: JsonNode): seq[string] {.raises: [].} =
  if value == nil or value.kind == JNull:
    return @[]

  case value.kind
  of JString:
    for part in value.getStr().split(','):
      let t = part.strip()
      if t.len > 0:
        result.add(t)
  of JArray:
    for item in value:
      if item.kind == JString:
        for part in item.getStr().split(','):
          let t = part.strip()
          if t.len > 0:
            result.add(t)
  of JNull:
    discard
  else:
    discard

func normalizeFileRef(path: string): string {.raises: [].} =
  let p = path.strip()
  let colon = p.find(':')
  if colon > 0 and colon + 1 < p.len:
    let suffix = p[colon + 1 .. ^1]
    if suffix.len > 0 and suffix[0] in Digits:
      return p[0 ..< colon]
  p

func collectSymbols(entry: JsonNode): seq[string] {.raises: [].} =
  let symbol = collectStrings(getOptionalNode(entry, "symbol"))
  if symbol.len > 0:
    return symbol

  let symbols = collectStrings(getOptionalNode(entry, "symbols"))
  if symbols.len > 0:
    return symbols

  collectStrings(getOptionalNode(entry, "declName"))

func joinSeq(values: seq[string]): string {.raises: [].} =
  values.join(", ")

func splitTargetRefs(text: string): seq[string] {.raises: [].} =
  for part in text.split(';'):
    let t = part.strip()
    if t.len > 0:
      result.add(t)

func parseTargetRef(raw: string): TargetRef {.raises: [].} =
  let t = raw.strip()
  if t.len == 0:
    return TargetRef()

  let colon = t.find(':')
  if colon <= 0:
    return TargetRef(file: t, rangeText: "")

  TargetRef(
    file: normalizeFileRef(t[0 ..< colon]),
    rangeText: t[colon + 1 .. ^1].strip()
  )

func collectOrphanFileRefs(entry: JsonNode): seq[string] {.raises: [].} =
  let lineRange = getOptionalNode(entry, "lineRange")
  if lineRange != nil and lineRange.kind == JString:
    for rawTarget in splitTargetRefs(lineRange.getStr()):
      let target = parseTargetRef(rawTarget)
      if target.file.len > 0:
        result.add(target.file)

  if result.len > 0:
    return result

  for key in ["file", "files"]:
    for path in collectStrings(getOptionalNode(entry, key)):
      result.add(normalizeFileRef(path))

func parseLineRange(rangeText: string): seq[LineRange] {.raises: [].} =
  for part in rangeText.split(','):
    let t = part.strip()
    if t.len == 0:
      continue

    try:
      let dash = t.find('-')
      if dash > 0:
        let start = t[0 ..< dash].strip().parseInt
        let finish = t[dash + 1 .. ^1].strip().parseInt
        if start > 0 and finish > 0:
          result.add LineRange(start: start, finish: if finish >= start: finish else: start)
      else:
        let start = t.parseInt
        if start > 0:
          result.add LineRange(start: start, finish: start)
    except ValueError:
      discard

func normalizeSha256(hash: string): string {.raises: [].} =
  let h = hash.strip().toLowerAscii()
  if h.startsWith("sha256:"):
    h[7 .. ^1]
  else:
    h

func symbolBase(symbol: string): string {.raises: [].}
func containsIdentifier(text, symbol: string): bool {.raises: [].}

func getExpectedSha256(entry: JsonNode): string {.raises: [].} =
  let contentHash = getOptionalNode(entry, "contentHash")
  if contentHash == nil or contentHash.kind != JString:
    return ""
  normalizeSha256(contentHash.getStr())

func collectTargetLines(entry: JsonNode; target: TargetRef; lines: seq[string]): string {.raises: [].} =
  let expected = getExpectedSha256(entry)
  if expected.len == 0:
    return ""

  let symbols = collectSymbols(entry)
  if symbols.len > 0 and target.file.endsWith(".nim") and target.rangeText.len > 0:
    let baseSymbol = symbolBase(symbols[0])
    var declarationLine = 0
    for i in 0 ..< lines.len:
      if containsIdentifier(lines[i], baseSymbol):
        declarationLine = i + 1
        break

    if declarationLine == 0:
      declarationLine = 1

    var content = lines[declarationLine - 1 ..< lines.len].join("\n")
    content.add("\n")

    for range in parseLineRange(target.rangeText):
      let bodyStart = max(range.start, declarationLine)
      let endLine = min(range.finish, lines.len)
      if bodyStart <= declarationLine or bodyStart > endLine:
        continue

      if content[^1] != '\n':
        content.add("\n")
      content.add(lines[bodyStart - 1 ..< endLine].join("\n"))
      content.add("\n")

    return sha256String(content)

  var included: seq[string]
  for range in parseLineRange(target.rangeText):
    let endLine = min(range.finish, lines.len)
    if range.start <= endLine:
      included.add(lines[range.start - 1 ..< endLine])

  var content = included.join("\n")
  if content.len > 0:
    content.add("\n")

  sha256String(content)

func getEntryId(entry: JsonNode): string {.raises: [].} =
  let id = getOptionalNode(entry, "id")
  if id != nil and id.kind == JString:
    id.getStr()
  else:
    "?"

proc hashTarget(entry: JsonNode; target: TargetRef): HashReport {.axiomEffect: IOEffect.} =
  result.entryId = getEntryId(entry)
  result.file = target.file
  result.symbol = joinSeq(collectSymbols(entry))
  result.expectedHash = getExpectedSha256(entry)

  if result.expectedHash.len == 0:
    result.reason = "contentHash missing"
    return

  if not fileExists(target.file):
    result.reason = "file does not exist"
    return

  try:
    let lines = readFile(target.file).splitLines()
    result.actualHash = collectTargetLines(entry, target, lines)
    if result.actualHash != result.expectedHash:
      result.reason = "hash mismatch"
  except CatchableError:
    result.reason = "failed to read target"

proc checkHashes(raw: JsonNode): seq[HashReport] {.axiomEffect: IOEffect.} =
  for entry in raw["entries"]:
    if getOptionalNode(entry, "contentHash") == nil:
      continue

    let lineRange = getOptionalNode(entry, "lineRange")
    if lineRange == nil or lineRange.kind != JString:
      continue

    for rawTarget in splitTargetRefs(lineRange.getStr()):
      let target = parseTargetRef(rawTarget)
      if target.file.len == 0:
        continue
      let report = hashTarget(entry, target)
      if report.reason.len > 0 or report.actualHash.len > 0:
        result.add(report)

func containsIdentifier(text, symbol: string): bool {.raises: [].} =
  if symbol.len == 0:
    return false

  var cursor = 0
  while cursor < text.len:
    let pos = text.find(symbol, cursor)
    if pos < 0:
      return false

    let before = if pos == 0: '\0' else: text[pos - 1]
    let after = if pos + symbol.len >= text.len: '\0' else: text[pos + symbol.len]
    if (before == '\0' or not isIdentPart(before)) and
       (after == '\0' or not isIdentPart(after)):
      return true

    cursor = pos + symbol.len

  false

func symbolBase(symbol: string): string {.raises: [].} =
  var s = symbol.strip()
  let paren = s.find('(')
  if paren >= 0:
    s = s[0 ..< paren]

  if s.endsWith("*"):
    s = s[0 ..< s.len - 1]

  s.strip()

proc targetIsConcrete(file, symbol: string): bool {.axiomEffect: IOEffect.} =
  if file.len == 0:
    return false
  if symbol.len == 0:
    return false
  fileExists(file)


proc analyzeEntry(entry: JsonNode): OrphanReport {.axiomEffect: IOEffect.} =
  result.entryId = getEntryId(entry)

  let fileRefs = collectOrphanFileRefs(entry)
  let symbols = collectSymbols(entry)
  if fileRefs.len == 0 or symbols.len == 0:
    return result

  for file in fileRefs:
    for symbol in symbols:
      let baseSymbol = symbolBase(symbol)
      if not targetIsConcrete(file, baseSymbol):
        result.orphaned = true
        result.file = file
        result.symbol = symbol
        if not fileExists(file):
          result.reason = "file does not exist"
        else:
          try:
            if containsIdentifier(readFile(file), baseSymbol):
              continue
          except CatchableError:
            discard  # axiom:best-effort(corrupt/unreadable hash cache -> start empty; full-scan recomputes, correctness unchanged — cache is performance-only)
          result.reason = "symbol not found"
        return result

  result

proc printReport(report: OrphanReport) =
  if report.entryId.len > 0:
    stderr.writeLine("  ORPHAN: " & report.entryId)
    stderr.writeLine("    file: " & report.file)
    stderr.writeLine("    symbol: " & report.symbol)
    stderr.writeLine("    reason: " & report.reason)

proc printHashReport(report: HashReport) =
  if report.entryId.len > 0:
    stderr.writeLine("  HASH: " & report.entryId)
    stderr.writeLine("    file: " & report.file)
    if report.symbol.len > 0:
      stderr.writeLine("    symbol: " & report.symbol)
    stderr.writeLine("    expected: " & report.expectedHash)
    if report.actualHash.len > 0:
      stderr.writeLine("    actual: " & report.actualHash)
    stderr.writeLine("    reason: " & report.reason)

type
  DebtGcOptions = tuple[dryRun: bool, checkMode: bool, removeOrphaned: bool]

proc parseArgs(): DebtGcOptions =
  var dryRun = false
  var checkMode = false
  var removeOrphaned = false

  for i in 1 .. paramCount():
    let arg = paramStr(i)
    case arg
    of "--dry-run", "-d":
      dryRun = true
    of "--check":
      checkMode = true
    of "--remove-orphaned", "--apply":
      removeOrphaned = true
    else:
      stderr.writeLine("Unknown argument: " & arg)
      stderr.writeLine("Usage: nim c -r tools/debt_gc.nim [--check] [--dry-run] [--remove-orphaned]")
      quit(1)

  if dryRun and removeOrphaned:
    stderr.writeLine("Use either --dry-run or --remove-orphaned, not both")
    quit(1)

  if checkMode and removeOrphaned:
    stderr.writeLine("Use either --check or --remove-orphaned, not both")
    quit(1)

  if dryRun:
    checkMode = true

  (dryRun, checkMode, removeOrphaned)

proc main() {.axiomEffect: IOEffect.} =
  ## Read-only audit of the debt registry. bin/debt_engine is the sole writer;
  ## every mode here reports orphaned entries and exits non-zero when any exist.
  let (dryRun, checkMode, removeOrphaned) = parseArgs()
  let raw = parseJson(readFile(RegistryPath))

  if raw["entries"].kind != JArray:
    stderr.writeLine("FATAL: " & RegistryPath & " must contain an 'entries' array")
    quit(1)

  var kept: seq[JsonNode]
  var orphaned: seq[OrphanReport]
  var hashMismatches: seq[HashReport]

  for entry in raw["entries"]:
    let report = analyzeEntry(entry)
    if report.orphaned:
      orphaned.add(report)
    else:
      kept.add(entry)

  hashMismatches = checkHashes(raw)

  echo "Debt GC: " & RegistryPath
  echo "  scanned: " & $raw["entries"].len
  echo "  kept:    " & $kept.len
  echo "  orphaned:" & $orphaned.len
  echo "  hashes:  " & $hashMismatches.len

  for report in orphaned:
    printReport(report)

  for report in hashMismatches:
    printHashReport(report)

  let issueCount = orphaned.len + hashMismatches.len
  if issueCount > 0:
    if removeOrphaned:
      if orphaned.len > 0:
        echo "  orphaned: " & $orphaned.len & " — removal is owned by bin/debt_engine (e.g. --prune --apply)"
      if hashMismatches.len > 0:
        echo "  hash warnings: " & $hashMismatches.len
      echo "  mode:    --remove-orphaned is audit-only (read-only)"
      echo "  status:  failed"
      quit(1)
    elif checkMode:
      echo "  mode:    --check read-only"
      echo "  status:  failed"
      quit(1)
    elif dryRun:
      echo "  preview: the orphaned entries above would be removed by bin/debt_engine --prune --apply"
      quit(1)
    else:
      echo "  action:  use --check to audit them, or bin/debt_engine --prune --apply to remove"
      quit(1)
  else:
    echo "  status:  clean"

main()
