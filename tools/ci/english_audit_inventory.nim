## english_audit_inventory.nim — deterministic Phase 1 inventory of non-Latin
## code points in the repository's tracked text files.
##
## The tool answers one question without interpretation: which tracked files
## contain code points outside ASCII + Latin + Greek + Common + Inherited, how
## many lines and code points do they contain, and what is the stable identity
## of those findings? It never mutates the repository (except for --out).
##
## Usage:
##   english_audit_inventory --base <sha> --out <path> [--check]
##
## Definitions (the JSON carries the same definitions under "definitions"):
##   * eligible path   : tracked by `git ls-files -z`, not under vendor/,
##                       build/, .cache/, or .axiom/, not data/i18n/ko.json,
##                       and not the --out file.
##   * binary          : an eligible path whose bytes contain at least one NUL.
##                       It is counted in binarySkipped, never silently passed.
##   * scannedFiles    : all eligible text files (NUL-free), including empty
##                       files and invalid-UTF-8 files. Tracked files that are
##                       also matched by .gitignore are INCLUDED, because
##                       `git ls-files` is the file-set authority here; their
##                       subset is reported separately in the totals so a
##                       .gitignore-honouring scan can be reconciled.
##   * invalidUtf8     : text files that are not valid UTF-8. Findings are not
##                       computed for them and the run exits 2 (UNKNOWN).
##   * matchedFiles    : valid-UTF-8 files with at least one finding.
##   * matchedLines    : lines with at least one finding.
##   * codePoints      : number of matched code points (rg submatches).
##   * findingsCount   : number of finding records; one per matched line, so
##                       findingsCount == matchedLines by construction.
##   * finding identity: sha256(path + "\n" + normalized line text).
##   * normalized line : line text with one trailing "\n" and then one
##                       trailing "\r" removed; no other whitespace change.
##   * findingsDigest  : sha256 of the sorted finding identities joined by
##                       "\n"; empty finding set hashes the empty string.
##
## Detection uses the pinned ripgrep binary and the exact pattern
## [^\x00-\x7F\p{Latin}\p{Greek}\p{Common}\p{Inherited}]. Resolution order is
## $AXIOM_RG then /tmp/rgpin/rg. Both the version and the sha256 of that binary
## are verified before any scan; any mismatch is UNKNOWN (exit 2), never PASS.
##
## Determinism: no wall-clock timestamps, no absolute paths, sorted file and
## directory ordering, sorted finding identities. --check runs the complete
## collection twice and requires byte-identical JSON.
##
## Exit codes: 0 OK, 1 invalid input, 2 UNKNOWN.

import core/trusted/layer_declaration
import core/trusted/axiom_pragmas_lite
axiomLayer "tools"
import std/[algorithm, base64, json, os, osproc, parseopt, sets, strutils,
            streams, tables]
import tools/sha256_native

const
  ToolName* = "english_audit_inventory"
  ToolVersion* = "1.0.0"
  SchemaVersion* = 1
  Pattern* = "[^\\x00-\\x7F\\p{Latin}\\p{Greek}\\p{Common}\\p{Inherited}]"
  RgVersionPrefix* = "ripgrep 14.1.0"
  RgSha256Pin* = "c2feed7a376d3754958fa6235a6ef88a74bcabc9b0cfccacbd48939b5f87860d"
  RgDefaultPath* = "/tmp/rgpin/rg"
  KoJsonPath* = "data/i18n/ko.json"
  Exclusions* = ["vendor/", "build/", ".cache/", ".axiom/"]
  RgChunkSize* = 500

  Usage = """Usage: english_audit_inventory --base <sha> --out <path> [--check]

  --base <sha>   commit whose tree the inventory describes (required)
  --out <path>   JSON report path (required, excluded from the inventory)
  --check        collect twice and require byte-identical JSON
  --help         print this text

Exit codes: 0 OK, 1 invalid input, 2 UNKNOWN (pinned rg unverified, rg
failure, invalid UTF-8, or a nondeterministic re-run)."""

type
  CliArgs = object
    base: string
    outPath: string
    check: bool
    help: bool
    error: string

  ProcResult = object
    output: string
    exitCode: int

  RgResolution = object
    ok: bool
    path: string
    version: string
    sha256: string
    error: string

  RgFindings = object
    identities: seq[string]
    codePoints: int

  FileRecord* = object
    path*: string
    sha256*: string
    matchedLines*: int
    codePoints*: int
    findingsCount*: int
    findingsDigest*: string
    text*: bool
    utf8*: bool
    gitIgnored*: bool

  DirAgg = object
    name: string
    files: int
    matchedFiles: int
    matchedLines: int
    codePoints: int

  KoJsonRecord = object
    path: string
    sha256: string
    codePoints: int
    matchedLines: int
    totalLines: int

  Totals = object
    scannedFiles: int
    binarySkipped: int
    invalidUtf8: int
    matchedFiles: int
    matchedLines: int
    codePoints: int
    emptyTextFiles: int
    gitIgnoredTrackedTextFiles: int
    gitIgnoredMatchedFiles: int
    gitIgnoredMatchedLines: int
    gitIgnoredCodePoints: int

  InventoryReport = object
    baseCommit: string
    rgVersion: string
    rgSha256: string
    koJson: KoJsonRecord
    totals: Totals
    byTopDir: seq[DirAgg]
    perFile: seq[FileRecord]

# ── Pure predicates and projections ─────────────────────────────────────────

func isExcludedPath*(path: string): bool {.raises: [].} =
  ## Exact directory-prefix exclusions from the Phase 1 contract.
  for prefix in Exclusions:
    if path.startsWith(prefix):
      return true

func topDirOf*(path: string): string {.raises: [].} =
  ## First path segment, or "." for a repository-root file.
  let slash = path.find('/')
  if slash < 0: "." else: path[0 ..< slash]

func hasNul*(data: string): bool {.raises: [].} =
  data.find('\0') >= 0

func normalizeLineText*(raw: string): string {.raises: [].} =
  ## Remove one line terminator; CRLF is normalized by dropping the CR too.
  result = raw
  if result.len > 0 and result[^1] == '\n':
    result.setLen(result.len - 1)
  if result.len > 0 and result[^1] == '\r':
    result.setLen(result.len - 1)

func isValidUtf8*(data: string): bool {.raises: [].} =
  ## Strict UTF-8 validation: rejects overlong forms, surrogates, and values
  ## above U+10FFFF. This is deliberately independent of platform locales.
  var i = 0
  while i < data.len:
    let b0 = uint8(ord(data[i]))
    if b0 <= 0x7F:
      inc i
    elif b0 >= 0xC2 and b0 <= 0xDF:
      if i + 1 >= data.len: return false
      let b1 = uint8(ord(data[i + 1]))
      if b1 < 0x80 or b1 > 0xBF: return false
      i += 2
    elif b0 >= 0xE0 and b0 <= 0xEF:
      if i + 2 >= data.len: return false
      let b1 = uint8(ord(data[i + 1]))
      let b2 = uint8(ord(data[i + 2]))
      if b1 < 0x80 or b1 > 0xBF or b2 < 0x80 or b2 > 0xBF: return false
      if b0 == 0xE0 and b1 < 0xA0: return false
      if b0 == 0xED and b1 > 0x9F: return false
      i += 3
    elif b0 >= 0xF0 and b0 <= 0xF4:
      if i + 3 >= data.len: return false
      let b1 = uint8(ord(data[i + 1]))
      let b2 = uint8(ord(data[i + 2]))
      let b3 = uint8(ord(data[i + 3]))
      if b1 < 0x80 or b1 > 0xBF or b2 < 0x80 or b2 > 0xBF or
         b3 < 0x80 or b3 > 0xBF:
        return false
      if b0 == 0xF0 and b1 < 0x90: return false
      if b0 == 0xF4 and b1 > 0x8F: return false
      i += 4
    else:
      return false
  result = true

func countLines*(data: string): int {.raises: [].} =
  ## `wc -l` semantics, plus a final unterminated line.
  for ch in data:
    if ch == '\n': inc result
  if data.len > 0 and data[^1] != '\n':
    inc result

func splitNul*(raw: string): seq[string] {.raises: [].} =
  var start = 0
  for i in 0 ..< raw.len:
    if raw[i] == '\0':
      if i > start:
        result.add raw[start ..< i]
      start = i + 1
  if start < raw.len:
    result.add raw[start ..< raw.len]

func findingIdentity*(path, lineText: string): string {.raises: [].} =
  sha256String(path & "\n" & normalizeLineText(lineText))

func findingsDigestOf*(identities: seq[string]): string {.raises: [].} =
  var sorted = identities
  sorted.sort()
  sha256String(sorted.join("\n"))

# ── I/O boundary ────────────────────────────────────────────────────────────

proc runCapture(exe: string; args: openArray[string]; workDir: string):
    ProcResult {.axiomEffect: IOEffect,
    raises: [OSError, IOError, ValueError].} =
  ## Run one program without a shell. stderr is folded into stdout so a
  ## failure cannot deadlock on a full pipe; callers check the exit code.
  let process = startProcess(exe, workingDir = workDir, args = args,
                             options = {poUsePath, poStdErrToStdOut})
  try:
    result.output = process.outputStream.readAll()
    result.exitCode = process.waitForExit()
  finally:
    process.close()

proc findRepoRoot(): string {.axiomEffect: IOEffect,
    raises: [OSError, IOError, ValueError].} =
  let captured = runCapture("git", ["rev-parse", "--show-toplevel"], "")
  if captured.exitCode != 0:
    return ""
  result = captured.output.strip()

proc resolveRg(root: string): RgResolution {.axiomEffect: IOEffect,
    raises: [OSError, IOError, ValueError].} =
  let fromEnv = getEnv("AXIOM_RG")
  result.path = if fromEnv.len > 0: fromEnv else: RgDefaultPath
  if not fileExists(result.path):
    result.error = "pinned ripgrep not found at " & result.path
    return
  let versionRun = runCapture(result.path, ["--version"], root)
  if versionRun.exitCode != 0:
    result.error = "rg --version failed at " & result.path
    return
  let lines = versionRun.output.splitLines()
  if lines.len == 0:
    result.error = "rg --version produced no output"
    return
  result.version = lines[0].strip()
  if not (result.version.startsWith(RgVersionPrefix) or
          result.version.startsWith("14.1.0")):
    result.error = "rg version is not 14.1.0: " & result.version
    return
  result.sha256 = sha256File(result.path)
  if result.sha256 != RgSha256Pin:
    result.error = "rg sha256 mismatch: expected " & RgSha256Pin &
                   ", got " & result.sha256
    return
  result.ok = true

# ── ripgrep JSON parsing (pure) ─────────────────────────────────────────────

func decodeRgPath(node: JsonNode): string {.raises: [ValueError].} =
  if node.kind != JObject:
    raise newException(ValueError, "rg json path node is not an object")
  if node.hasKey("text"):
    return node["text"].getStr()
  if node.hasKey("bytes"):
    return decode(node["bytes"].getStr())
  raise newException(ValueError, "rg json path has neither text nor bytes")

proc parseRgChunk*(raw: string): Table[string, RgFindings] {.
    raises: [ValueError, IOError, OSError].} =
  ## Parse one ripgrep --json stream. Only match events matter; each event is
  ## one line and its submatches are the matched code points. This is a proc
  ## rather than a func only because std/json's parseJson carries a sideEffect
  ## annotation; the body touches no global state.
  result = initTable[string, RgFindings]()
  for rawLine in raw.splitLines():
    if rawLine.len == 0: continue
    let node = parseJson(rawLine)
    if node.kind != JObject or not node.hasKey("type"): continue
    if node["type"].getStr() != "match": continue
    if not node.hasKey("data"): continue
    let data = node["data"]
    let path = decodeRgPath(data["path"])
    let lineText = data["lines"]["text"].getStr()
    if not data.hasKey("submatches") or data["submatches"].kind != JArray:
      continue
    var findings = result.mgetOrPut(path, RgFindings())
    findings.identities.add(findingIdentity(path, lineText))
    findings.codePoints += data["submatches"].len
    result[path] = findings

proc collectFindings(rgPath, root: string; paths: seq[string]):
    Table[string, RgFindings] {.axiomEffect: IOEffect,
    raises: [OSError, IOError, ValueError].} =
  result = initTable[string, RgFindings]()
  var start = 0
  while start < paths.len:
    let stop = min(start + RgChunkSize, paths.len)
    var args = @["--json", "--no-config", "--text", "--no-messages",
                 "-e", Pattern, "--"]
    for i in start ..< stop:
      args.add paths[i]
    let captured = runCapture(rgPath, args, root)
    if captured.exitCode notin [0, 1]:
      let detail = captured.output[0 ..< min(captured.output.len, 2000)]
      raise newException(IOError, "rg failed with exit " &
        $captured.exitCode & ": " & detail)
    let parsed = parseRgChunk(captured.output)
    for i in start ..< stop:
      let path = paths[i]
      if not parsed.hasKey(path): continue
      var merged = result.mgetOrPut(path, RgFindings())
      for identity in parsed[path].identities:
        merged.identities.add identity
      merged.codePoints += parsed[path].codePoints
      result[path] = merged
    start = stop

# ── Collection ──────────────────────────────────────────────────────────────

proc collect(root, baseSha, rgPath, rgVersion, rgSha, outRel: string):
    InventoryReport {.axiomEffect: IOEffect,
    raises: [OSError, IOError, ValueError].} =
  let listed = runCapture("git", ["ls-files", "-z"], root)
  if listed.exitCode != 0:
    raise newException(IOError, "git ls-files failed")
  let ignoredRun = runCapture("git",
    ["ls-files", "-ci", "--exclude-standard", "-z"], root)
  if ignoredRun.exitCode != 0:
    raise newException(IOError, "git ls-files -ci --exclude-standard failed")
  var ignored = initHashSet[string]()
  for path in splitNul(ignoredRun.output):
    ignored.incl path

  var paths = splitNul(listed.output)
  paths.sort()

  result.baseCommit = baseSha
  result.rgVersion = rgVersion
  result.rgSha256 = rgSha

  var records = initTable[string, FileRecord]()
  var validPaths: seq[string] = @[]
  for path in paths:
    if isExcludedPath(path) or path == KoJsonPath or path == outRel:
      continue
    let data = readFile(root / path)
    if hasNul(data):
      inc result.totals.binarySkipped
      continue
    inc result.totals.scannedFiles
    if data.len == 0:
      inc result.totals.emptyTextFiles
    let record = FileRecord(
      path: path,
      sha256: sha256String(data),
      findingsDigest: sha256String(""),
      text: true,
      utf8: isValidUtf8(data),
      gitIgnored: path in ignored)
    if record.utf8:
      validPaths.add path
    else:
      inc result.totals.invalidUtf8
    records[path] = record

  let findings = collectFindings(rgPath, root, validPaths)
  for path in validPaths:
    var record = records[path]
    if findings.hasKey(path):
      let observed = findings[path]
      record.matchedLines = observed.identities.len
      record.codePoints = observed.codePoints
      record.findingsCount = observed.identities.len
      record.findingsDigest = findingsDigestOf(observed.identities)
    records[path] = record

  # data/i18n/ko.json is reported separately and never enters the main totals.
  let koData = readFile(root / KoJsonPath)
  if hasNul(koData):
    raise newException(IOError, KoJsonPath & " contains a NUL byte")
  if not isValidUtf8(koData):
    raise newException(IOError, KoJsonPath & " is not valid UTF-8")
  let koFindings = collectFindings(rgPath, root, @[KoJsonPath])
  var koMatchedLines = 0
  var koCodePoints = 0
  if koFindings.hasKey(KoJsonPath):
    koMatchedLines = koFindings[KoJsonPath].identities.len
    koCodePoints = koFindings[KoJsonPath].codePoints
  result.koJson = KoJsonRecord(
    path: KoJsonPath,
    sha256: sha256String(koData),
    codePoints: koCodePoints,
    matchedLines: koMatchedLines,
    totalLines: countLines(koData))

  var dirTable = initTable[string, DirAgg]()
  for path, record in records:
    let key = topDirOf(path)
    var agg = dirTable.getOrDefault(key, DirAgg(name: key))
    inc agg.files
    if record.matchedLines > 0:
      inc agg.matchedFiles
      agg.matchedLines += record.matchedLines
      agg.codePoints += record.codePoints
    dirTable[key] = agg

    inc result.totals.matchedFiles, (if record.matchedLines > 0: 1 else: 0)
    inc result.totals.matchedLines, record.matchedLines
    inc result.totals.codePoints, record.codePoints
    if record.gitIgnored:
      inc result.totals.gitIgnoredTrackedTextFiles
      if record.matchedLines > 0:
        inc result.totals.gitIgnoredMatchedFiles
        result.totals.gitIgnoredMatchedLines += record.matchedLines
        result.totals.gitIgnoredCodePoints += record.codePoints

  var dirKeys: seq[string] = @[]
  for key in dirTable.keys:
    dirKeys.add key
  dirKeys.sort()
  for key in dirKeys:
    result.byTopDir.add dirTable[key]

  var recordPaths: seq[string] = @[]
  for path in records.keys:
    recordPaths.add path
  recordPaths.sort()
  for path in recordPaths:
    result.perFile.add records[path]

# ── JSON projection (pure) ──────────────────────────────────────────────────

func renderReport*(report: InventoryReport): string {.raises: [].} =
  var perFile = newJArray()
  for record in report.perFile:
    perFile.add(%*{
      "path": record.path,
      "sha256": record.sha256,
      "matchedLines": record.matchedLines,
      "codePoints": record.codePoints,
      "findingsCount": record.findingsCount,
      "findingsDigest": record.findingsDigest,
      "text": record.text,
      "utf8": record.utf8,
      "gitIgnored": record.gitIgnored
    })

  var byTopDir = newJObject()
  for agg in report.byTopDir:
    byTopDir[agg.name] = %*{
      "files": agg.files,
      "matchedFiles": agg.matchedFiles,
      "matchedLines": agg.matchedLines,
      "codePoints": agg.codePoints
    }

  let totals = report.totals
  let node = %*{
    "schemaVersion": SchemaVersion,
    "baseCommit": report.baseCommit,
    "generatedBy": {
      "name": ToolName,
      "version": ToolVersion
    },
    "exclusions": %*["vendor/", "build/", ".cache/", ".axiom/"],
    "tool": {
      "rgVersion": report.rgVersion,
      "rgSha256": report.rgSha256
    },
    "pattern": Pattern,
    "koJson": {
      "path": report.koJson.path,
      "sha256": report.koJson.sha256,
      "codePoints": report.koJson.codePoints,
      "matchedLines": report.koJson.matchedLines,
      "totalLines": report.koJson.totalLines,
      "text": true,
      "utf8": true
    },
    "definitions": {
      "scannedFiles": "all eligible text files (NUL-free), including empty and gitignored-tracked files",
      "matchedFiles": "valid-UTF-8 files with at least one finding",
      "matchedFilesWithFindings": "alias of matchedFiles",
      "matchedLines": "lines with at least one finding",
      "codePoints": "matched code points (rg submatches)",
      "findingsCount": "finding records; one per matched line (equals matchedLines)",
      "findingIdentity": "sha256(path + newline + normalized line text)",
      "findingsDigest": "sha256 of sorted finding identities joined by newline",
      "normalizedLine": "line text with one trailing newline and one trailing carriage return removed",
      "binary": "eligible path whose bytes contain a NUL byte; counted in binarySkipped",
      "invalidUtf8": "text file that is not valid UTF-8; findings unknown, run exits 2"
    },
    "totals": {
      "scannedFiles": totals.scannedFiles,
      "binarySkipped": totals.binarySkipped,
      "invalidUtf8": totals.invalidUtf8,
      "unknownFiles": totals.invalidUtf8,
      "matchedFiles": totals.matchedFiles,
      "matchedFilesWithFindings": totals.matchedFiles,
      "matchedLines": totals.matchedLines,
      "codePoints": totals.codePoints,
      "emptyTextFiles": totals.emptyTextFiles,
      "gitIgnoredTrackedTextFiles": totals.gitIgnoredTrackedTextFiles,
      "gitIgnoredMatchedFiles": totals.gitIgnoredMatchedFiles,
      "gitIgnoredMatchedLines": totals.gitIgnoredMatchedLines,
      "gitIgnoredCodePoints": totals.gitIgnoredCodePoints
    },
    "byTopDir": byTopDir,
    "perFile": perFile
  }
  result = pretty(node, 2) & "\n"

# ── CLI ─────────────────────────────────────────────────────────────────────

proc parseArgs(args: seq[string]): CliArgs {.raises: [].} =
  ## Pure in behaviour; a proc because std/parseopt's initOptParser carries a
  ## sideEffect annotation. longNoVal/shortNoVal are declared so `--base <sha>`
  ## and `--out <path>` accept whitespace-separated values.
  var parser = initOptParser(args, shortNoVal = {'c', 'h'},
                             longNoVal = @["check", "help"])
  for kind, key, value in parser.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "base", "b":
        if value.len == 0:
          result.error = "--base requires a value"
          return
        result.base = value
      of "out", "o":
        if value.len == 0:
          result.error = "--out requires a value"
          return
        result.outPath = value
      of "check", "c":
        if value.len > 0:
          result.error = "--check takes no value"
          return
        result.check = true
      of "help", "h":
        result.help = true
      else:
        result.error = "unknown option: " & key
        return
    of cmdArgument:
      result.error = "unexpected argument: " & key
      return
    of cmdEnd:
      discard
  if not result.help:
    if result.base.len == 0: result.error = "--base is required"
    elif result.outPath.len == 0: result.error = "--out is required"

proc run(cli: CliArgs): int {.axiomEffect: IOEffect,
    raises: [OSError, IOError, ValueError].} =
  let root = findRepoRoot()
  if root.len == 0:
    stderr.writeLine(ToolName & ": not inside a git worktree")
    return 1

  let baseRun = runCapture("git",
    ["rev-parse", "--verify", "--quiet", "--end-of-options",
     cli.base & "^{commit}"], root)
  if baseRun.exitCode != 0 or baseRun.output.strip.len == 0:
    stderr.writeLine(ToolName & ": --base is not a commit: " & cli.base)
    return 1
  let baseSha = baseRun.output.strip.splitLines()[0]

  let outAbs = absolutePath(cli.outPath)
  var rootNorm = root
  normalizePath(rootNorm)
  let rootPrefix = rootNorm & "/"
  var outNorm = outAbs
  normalizePath(outNorm)
  let outRel = if outNorm.startsWith(rootPrefix):
                 outNorm[rootPrefix.len .. ^1]
               else:
                 ""

  var diffArgs = @["diff", "--quiet", baseSha, "--", "."]
  if outRel.len > 0:
    diffArgs.add ":(exclude,literal)" & outRel
  let diffRun = runCapture("git", diffArgs, root)
  if diffRun.exitCode == 1:
    stderr.writeLine(ToolName & ": working tree differs from --base " &
      baseSha & "; check out the base commit and retry")
    return 1
  if diffRun.exitCode != 0:
    stderr.writeLine(ToolName & ": git diff failed with exit " &
      $diffRun.exitCode)
    return 2

  let rg = resolveRg(root)
  if not rg.ok:
    stderr.writeLine(ToolName & ": UNKNOWN: " & rg.error)
    return 2

  let first = collect(root, baseSha, rg.path, rg.version, rg.sha256, outRel)
  let firstText = renderReport(first)
  if cli.check:
    let second = collect(root, baseSha, rg.path, rg.version, rg.sha256, outRel)
    let secondText = renderReport(second)
    if firstText != secondText:
      stderr.writeLine(ToolName & ": --check MISMATCH (re-run differs)")
      return 2
    stderr.writeLine(ToolName & ": --check OK (byte-identical re-run)")

  let outDir = parentDir(outAbs)
  if outDir.len > 0 and not dirExists(outDir):
    createDir(outDir)
  writeFile(outAbs, firstText)

  if first.totals.invalidUtf8 > 0:
    stderr.writeLine(ToolName & ": UNKNOWN: " &
      $first.totals.invalidUtf8 & " invalid UTF-8 text file(s)")
    return 2
  return 0

proc main(): int {.raises: [].} =
  try:
    let cli = parseArgs(commandLineParams())
    if cli.error.len > 0:
      stderr.writeLine(ToolName & ": " & cli.error)
      stderr.writeLine(Usage)
      return 1
    if cli.help:
      stdout.writeLine(Usage)
      return 0
    result = run(cli)
  except CatchableError as error:
    try:
      stderr.writeLine(ToolName & ": UNKNOWN: " & error.msg)
    except IOError, OSError: # bestEffort("""diagnostic stream unavailable — the exit code is the contract, the message is advisory""")
      discard
    result = 2

when isMainModule:
  quit(main())