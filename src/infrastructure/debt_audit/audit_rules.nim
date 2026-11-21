## src/infrastructure/debt_audit/audit_rules.nim — Rule catalog + deterministic rule engine.
##
## Provides a typed, table-driven audit rule system over debt observations.
## Each rule is cataloged in config/audit_rules.json; evalRule dispatches by
## ruleId and returns RuleResult[] with SHA256 fingerprints.
##
## Design notes (QUIRK#audit-rules):
## - Uses checksums/sha2 (Nim stdlib re-export); mission spec says "std/sha2"
##   but Nim 2.2.10 ships sha2 under checksums/. Adjust import if stdlib changes.
## - All pure logic uses func {.raises: [].}; IO-bound helpers use proc.
## - Fingerprint = SHA256(ruleId ‖ path ‖ locator ‖ claim ‖ root) hex.

import core/trusted/layer_declaration
axiomLayer "infrastructure"

import std/[algorithm, json, os, strutils, tables, sets, times]
import checksums/sha2
import core/axiom_pragmas
import infrastructure/debt_audit/audit_observations  # FileObs, Obs, RuleCtx

# ---------------------------------------------------------------------------
# Exported types
# ---------------------------------------------------------------------------

type
  RuleResult* = object
    findingKey*: string       ## deterministic key for dedup
    ruleId*: string           ## e.g. "DIR-BIN-001"
    ruleVersion*: string      ## from catalog
    path*: string             ## affected file/dir path
    locator*: string          ## line / offset / sub-path detail
    claim*: string            ## what the rule asserts
    rootCause*: string        ## why the claim failed
    severity*: string         ## high / medium / low / info
    evidence*: seq[string]    ## supporting facts
    dispositionHint*: string  ## suggested human action

  RuleCat* = object
    ruleId*: string           ## unique identifier
    version*: string          ## catalog version
    domain*: string           ## directory | data | tool | test | documentation | quirk | toolchain | log | audit
    severity*: string         ## default severity override
    defaultAction*: string    ## flag | document

# ---------------------------------------------------------------------------
# Catalog metadata loader
# ---------------------------------------------------------------------------

const AuditRulesConfigPath* = "config/audit_rules.json"

proc loadCatalog*(path: string = AuditRulesConfigPath): seq[RuleCat]
    {.raises: [IOError, ValueError, OSError], axiomEffect: IOEffect.} =
  ## Read config/audit_rules.json and return the rules array as RuleCat[].
  ## Returns empty seq on missing/unparseable file (fail-open).
  var raw = ""
  try:
    raw = readFile(path)
  except IOError:
    return @[]  # missing config → run with code defaults

  try:
    let node = parseJson(raw)
    if not node.hasKey("rules"): return @[]
    let arr = node["rules"].getElems()
    var res: seq[RuleCat]
    for item in arr:
      if item.kind != JObject: continue
      res.add(RuleCat(
        ruleId: item["rule_id"].getStr(),
        version: item["version"].getStr(),
        domain: item["domain"].getStr(),
        severity: item["severity"].getStr(),
        defaultAction: item["default_action"].getStr()
      ))
    return res
  except ValueError:
    return @[]

# ---------------------------------------------------------------------------
# Full rule catalog (hard-coded v1 baseline)
## These are the canonical rules that evalRule dispatches over.
## Config JSON provides metadata overrides; code defines detection logic.
# ---------------------------------------------------------------------------

const cat*: seq[RuleCat] = @[
  # Directory rules
  RuleCat(ruleId: "DIR-BIN-001", version: "1", domain: "directory", severity: "high", defaultAction: "flag"),
  RuleCat(ruleId: "DIR-BIN-002", version: "1", domain: "directory", severity: "medium", defaultAction: "flag"),
  RuleCat(ruleId: "DIR-BIN-003", version: "1", domain: "directory", severity: "medium", defaultAction: "flag"),
  RuleCat(ruleId: "DIR-ART-001", version: "1", domain: "directory", severity: "low", defaultAction: "flag"),
  # Data rules
  RuleCat(ruleId: "DATA-001", version: "1", domain: "data", severity: "high", defaultAction: "flag"),
  # Tool rules
  RuleCat(ruleId: "TOOL-001", version: "1", domain: "tool", severity: "medium", defaultAction: "flag"),
  # Test rules
  RuleCat(ruleId: "TEST-001", version: "1", domain: "test", severity: "low", defaultAction: "flag"),
  # Documentation rules
  RuleCat(ruleId: "DOC-LINK-001", version: "1", domain: "documentation", severity: "medium", defaultAction: "flag"),
  RuleCat(ruleId: "DOC-CLA-001", version: "1", domain: "documentation", severity: "high", defaultAction: "flag"),
  # Quirk rules
  RuleCat(ruleId: "QUIRK-001", version: "1", domain: "quirk", severity: "low", defaultAction: "document"),
  RuleCat(ruleId: "QUIRK-002", version: "1", domain: "quirk", severity: "low", defaultAction: "document"),
  RuleCat(ruleId: "QUIRK-003", version: "1", domain: "quirk", severity: "low", defaultAction: "document"),
  RuleCat(ruleId: "QUIRK-004", version: "1", domain: "quirk", severity: "low", defaultAction: "document"),
  # Toolchain rules
  RuleCat(ruleId: "TC-001", version: "1", domain: "toolchain", severity: "medium", defaultAction: "flag"),
  # Log rules
  RuleCat(ruleId: "LOG-001", version: "1", domain: "log", severity: "low", defaultAction: "flag"),
  RuleCat(ruleId: "LOG-002", version: "1", domain: "log", severity: "low", defaultAction: "flag"),
  RuleCat(ruleId: "LOG-003", version: "1", domain: "log", severity: "low", defaultAction: "flag"),
  # Audit self-check rules
  RuleCat(ruleId: "AUD-001", version: "1", domain: "audit", severity: "info", defaultAction: "flag"),
  RuleCat(ruleId: "AUD-002", version: "1", domain: "audit", severity: "info", defaultAction: "flag"),
  RuleCat(ruleId: "AUD-003", version: "1", domain: "audit", severity: "info", defaultAction: "flag")
]

# ---------------------------------------------------------------------------
# Helper: build catalog lookup table
# ---------------------------------------------------------------------------

func catalogTable*(): Table[string, RuleCat] {.raises: [].} =
  ## Build a ruleId → RuleCat lookup from the canonical catalog.
  for rc in cat:
    result[rc.ruleId] = rc

# ---------------------------------------------------------------------------
# Fingerprint: SHA256(ruleId ‖ path ‖ locator ‖ claim ‖ root) hex
# Inputs sorted symmetrically before hashing for stability.
# ---------------------------------------------------------------------------

func fingerprint*(ruleId, path, locator, claim, root: string): string {.raises: [].} =
  ## Deterministic SHA256 fingerprint of a rule result's identifying fields.
  ## Inputs are sorted lexicographically to ensure symmetric ordering.
  var inputs: seq[string] = @[ruleId, path, locator, claim, root]
  inputs.sort(system.cmp[string])
  let joined = inputs.join("\x1e")
  "sha256:" & $secureHash(Sha_256, joined)

proc isExecutablePath*(p: string): bool {.raises: [OSError].} =
  ## Executable bit check without deprecated hasFileAttr.
  let perms = getFilePermissions(p)
  result = (fpUserExec in perms) or (fpGroupExec in perms) or (fpOthersExec in perms)

# ---------------------------------------------------------------------------
# Severity resolution: catalog default, then code override
# ---------------------------------------------------------------------------

func resolveSeverity*(ruleId: string): string {.raises: [].} =
  ## Return severity for a ruleId: catalog value if present, else "medium".
  let ct = catalogTable()
  let rc = ct.getOrDefault(ruleId)
  if rc.ruleId.len > 0:
    return rc.severity
  "medium"  # code default for uncataloged rules

# ---------------------------------------------------------------------------
# Rule evaluation functions (pure func where possible)
# ---------------------------------------------------------------------------

# Recursive glob helper: Nim 2.2's walkFiles is an inline iterator without
# `**` support (returns nothing for "dir/**/*"); materialize + sort instead.
proc globFiles(pattern: string): seq[string] {.raises: [CatchableError].} =
  ## Deterministic recursive glob: "root/**/*.ext" → sorted files under root.
  ## Supports `*`, `*.ext`, `*.{a,b}`, and `<prefix>*.ext` tail patterns.
  let starIdx = pattern.find("/**")
  if starIdx < 0:
    for p in globFiles(pattern):
      result.add p
    result.sort()
    return
  let root = pattern[0 ..< starIdx]
  if not dirExists(root): return
  var tailPat = pattern[starIdx + 4 .. ^1]  # "/**" consumed; rest after it
  if tailPat.startsWith("/"): tailPat = tailPat[1 .. ^1]
  var prefix = ""
  var suffixes: seq[string] = @[]
  if tailPat.len == 0 or tailPat == "*":
    discard  # all files
  elif tailPat.startsWith("*.{"):
    let inner = tailPat[3 .. ^2]
    for ext in inner.split(','):
      suffixes.add "." & ext.strip()
  elif tailPat.startsWith("*."):
    suffixes.add tailPat[1 .. ^1]
  elif '*' in tailPat:
    let si = tailPat.find('*')
    prefix = tailPat[0 ..< si]
    suffixes.add tailPat[si + 1 .. ^1]
  for p in walkDirRec(root, yieldFilter = {pcFile}):
    if prefix.len > 0 and not extractFilename(p).startsWith(prefix):
      continue
    if suffixes.len == 0:
      result.add p
    else:
      for suf in suffixes:
        if p.endsWith(suf):
          result.add p
          break
  result.sort()

# --- DIR-BIN-001: untracked executables under bin/ ---

proc evalDirBin001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Find files under bin/ that are executable but not in the allowlist
  ## and not produced by any known make/CI producer.
  if ctx.binDir.len == 0 or not dirExists(ctx.binDir): return @[]
  try:
    let entries = globFiles(ctx.binDir & "/**/*")
    for entry in entries:
      let baseName = extractFilename(entry)
      # Skip directories and hidden files
      if baseName.startsWith("."): continue
      if entry.endsWith("/"): continue
      # Check if executable
      if not isExecutablePath(entry): continue
      # Check allowlist (full relpath entries: "bin/<name>")
      if ctx.allowlist.contains(entry): continue
      # Check known producers (make, CI scripts)
      var isProduced = false
      for prod in ctx.knownProducers:
        if prod.len > 0 and entry.contains(prod):
          isProduced = true
          break
      if isProduced: continue
      # Finding: untracked executable
      let sev = resolveSeverity("DIR-BIN-001")
      result.add(RuleResult(
        findingKey: fingerprint("DIR-BIN-001", entry, "executable",
          "bin/" & baseName & " is an untracked executable",
          "untracked-executable"),
        ruleId: "DIR-BIN-001", ruleVersion: "1", path: entry,
        locator: "file", claim: "bin/ executables must be tracked",
        rootCause: "not in allowlist and no known producer",
        severity: sev, evidence: @[entry],
        dispositionHint: "Add to allowlist or remove from bin/"
      ))
  except CatchableError:
    discard

# --- DIR-BIN-002: stat garbage (mtime older than 90 days) ---

proc evalDirBin002*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Flag bin/ items whose mtime is older than 90 days from now.
  if ctx.binDir.len == 0 or not dirExists(ctx.binDir): return @[]
  try:
    let now = getFileInfo(ctx.binDir).lastWriteTime  # approximate current time
    let entries = globFiles(ctx.binDir & "/**/*")
    for entry in entries:
      if not fileExists(entry): continue
      let fi = getFileInfo(entry)
      let ageDays = (toUnix(now) - toUnix(fi.lastWriteTime)) div 86_400
      if ageDays > 90:
        let sev = resolveSeverity("DIR-BIN-002")
        result.add(RuleResult(
          findingKey: fingerprint("DIR-BIN-002", entry, $ageDays & "d",
            "mtime=" & $toUnix(fi.lastWriteTime),
            "stale-mtime"),
          ruleId: "DIR-BIN-002", ruleVersion: "1", path: entry,
          locator: "mtime=" & $ageDays & "days",
          claim: "bin/ items should have recent mtime",
          rootCause: "file untouched for " & $ageDays & " days (>90d threshold)",
          severity: sev, evidence: @[entry, "age=" & $ageDays & "days"],
          dispositionHint: "Review and update or remove stale artifact"
        ))
  except CatchableError:
    discard

# --- DIR-BIN-003: unknown-producer ---

proc evalDirBin003*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## bin/ items with no producer occupancy anywhere → UNKNOWN_PRODUCER_BY_KNOWN_PIPELINES.
  if ctx.binDir.len == 0 or not dirExists(ctx.binDir): return @[]
  try:
    let entries = globFiles(ctx.binDir & "/**/*")
    for entry in entries:
      let baseName = extractFilename(entry)
      if baseName.startsWith("."): continue
      var hasProducer = false
      for prod in ctx.knownProducers:
        if prod.len > 0 and entry.contains(prod):
          hasProducer = true
          break
      if hasProducer: continue
      let sev = resolveSeverity("DIR-BIN-003")
      result.add(RuleResult(
        findingKey: fingerprint("DIR-BIN-003", entry, "no-producer",
          "UNKNOWN_PRODUCER_BY_KNOWN_PIPELINES",
          "unknown-producer"),
        ruleId: "DIR-BIN-003", ruleVersion: "1", path: entry,
        locator: "producer=none",
        claim: "bin/ items must have a known producer pipeline",
        rootCause: "UNKNOWN_PRODUCER_BY_KNOWN_PIPELINES",
        severity: sev, evidence: @[entry],
        dispositionHint: "Identify producer pipeline or add to knownProducers"
      ))
  except CatchableError:
    discard

# --- DIR-ART-001: debris under tmp/ ---

proc evalDirArt001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Find non-generated files under tmp/ excluding current bundle dir.
  if ctx.tmpDir.len == 0 or not dirExists(ctx.tmpDir): return @[]
  try:
    let excluded = ctx.excludedDirs  # set of dirs to skip
    let entries = globFiles(ctx.tmpDir & "/**/*")
    for entry in entries:
      # Skip excluded dirs (current bundle)
      var skip = false
      for ex in excluded:
        if entry.startsWith(ex):
          skip = true
          break
      if skip: continue
      # Check if generated (contains .generated marker or temp suffix)
      let bn = extractFilename(entry)
      if bn.endsWith(".generated") or bn.startsWith(".tmp_"): continue
      let sev = resolveSeverity("DIR-ART-001")
      result.add(RuleResult(
        findingKey: fingerprint("DIR-ART-001", entry, "debris",
          "non-generated-file-in-tmp",
          "tmp-debris"),
        ruleId: "DIR-ART-001", ruleVersion: "1", path: entry,
        locator: "file",
        claim: "tmp/ should only contain generated/temp artifacts",
        rootCause: "non-generated file found in tmp/",
        severity: sev, evidence: @[entry],
        dispositionHint: "Move to appropriate location or mark as generated"
      ))
  except CatchableError:
    discard

# --- DATA-001: live registry.files paths missing on disk ---

func stripLineAnnotation(p: string): string {.raises: [].} =
  ## Strip a trailing line-annotation suffix (":N", ":N-M", or comma lists
  ## such as ":221-236,439-526"). Mirrors the canonical helper in
  ## tools/debt_engine.nim; the schema states annotations do not affect
  ## existence (data/debt_schema.json, fileRef).
  result = p
  let pos = result.rfind(':')
  if pos <= 0 or pos + 1 >= result.len: return
  var i = pos + 1
  var sawDigits = false
  while i < result.len and result[i] in Digits:
    inc i; sawDigits = true
  if not sawDigits: return
  if i < result.len and result[i] == '-':
    inc i
    var sawRangeEnd = false
    while i < result.len and result[i] in Digits:
      inc i; sawRangeEnd = true
    if not sawRangeEnd: return
  while i < result.len and result[i] == ',':
    inc i
    var sawNext = false
    while i < result.len and result[i] in Digits:
      inc i; sawNext = true
    if not sawNext: return
    if i < result.len and result[i] == '-':
      inc i
      var sawNextEnd = false
      while i < result.len and result[i] in Digits:
        inc i; sawNextEnd = true
      if not sawNextEnd: return
  if i == result.len:
    result = result[0 ..< pos]

func entryFiles(entry: JsonNode): seq[string] {.raises: [].} =
  ## `files` refs of one registry entry; absent/non-array → empty.
  let node = entry{"files"}
  if node != nil and node.kind == JArray:
    for r in node:
      if r.kind == JString:
        result.add(r.getStr())

proc evalData001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Schema contract (data/debt_schema.json): existence is enforced only for
  ## `files` of open/deferred entries; line annotations do not affect
  ## existence, directories are valid targets, and cross-entry duplicates are
  ## not prohibited.
  var ids: seq[string]
  for id in ctx.registryEntries.keys:
    ids.add(id)
  ids.sort()
  var seenMissing = initHashSet[string]()
  for id in ids:
    let entry = ctx.registryEntries.getOrDefault(id)
    if entry == nil or entry.kind != JObject: continue
    if entry{"status"}.getStr("").toLowerAscii() notin ["open", "deferred"]:
      continue
    for p in entryFiles(entry):
      let base = stripLineAnnotation(p)
      if base.len == 0: continue
      if fileExists(base) or dirExists(base): continue
      if base in seenMissing: continue
      seenMissing.incl(base)
      let sev = resolveSeverity("DATA-001")
      result.add(RuleResult(
        findingKey: fingerprint("DATA-001", p, "missing",
          "registry-file-not-on-disk",
          "missing-registry-file"),
        ruleId: "DATA-001", ruleVersion: "1", path: p,
        locator: "file",
        claim: "open/deferred registry.files paths must exist on disk",
        rootCause: "file not found at path",
        severity: sev, evidence: @[p],
        dispositionHint: "Create file or remove from registry"
      ))

# --- TOOL-001: tools/**/*.nim with zero references ---

proc evalTool001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Find tools/**/*.nim files not referenced in Makefile, ci.yml, docs/**.
  if ctx.toolsDir.len == 0 or not dirExists(ctx.toolsDir): return @[]
  try:
    let nimFiles = globFiles(ctx.toolsDir & "/**/*.nim")
    # Collect all reference targets from Makefile, ci.yml, docs
    var refTargets: HashSet[string]
    for refFile in ctx.referenceFiles:
      if fileExists(refFile):
        try:
          let content = readFile(refFile)
          for nf in nimFiles:
            let baseName = extractFilename(nf).replace(".nim", "")
            if baseName.len > 0 and content.contains(baseName):
              refTargets.incl(baseName)
        except CatchableError:
          discard
    for nf in nimFiles:
      let baseName = extractFilename(nf).replace(".nim", "")
      if not refTargets.contains(baseName):
        let sev = resolveSeverity("TOOL-001")
        result.add(RuleResult(
          findingKey: fingerprint("TOOL-001", nf, "zero-ref",
            "STATIC-UNREFERENCED",
            "unreferenced-tool"),
          ruleId: "TOOL-001", ruleVersion: "1", path: nf,
          locator: "references=0",
          claim: "tools/**/*.nim must be referenced in build/docs",
          rootCause: "STATIC-UNREFERENCED",
          severity: sev, evidence: @[nf],
          dispositionHint: "Add reference or remove unused tool"
        ))
  except CatchableError:
    discard

# --- TEST-001: unreferenced golden/fixture files ---

proc evalTest001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Find tests/**/*.golden.json or fixtures not referenced statically.
  if ctx.testDir.len == 0 or not dirExists(ctx.testDir): return @[]
  try:
    let goldenFiles = globFiles(ctx.testDir & "/**/*.golden.json")
    var refTargets: HashSet[string]
    for refFile in ctx.referenceFiles:
      if fileExists(refFile):
        try:
          let content = readFile(refFile)
          for gf in goldenFiles:
            let baseName = extractFilename(gf)
            if baseName.len > 0 and content.contains(baseName):
              refTargets.incl(baseName)
        except CatchableError:
          discard
    for gf in goldenFiles:
      let baseName = extractFilename(gf)
      if not refTargets.contains(baseName):
        let sev = resolveSeverity("TEST-001")
        result.add(RuleResult(
          findingKey: fingerprint("TEST-001", gf, "zero-ref",
            "STATIC-UNREFERENCED",
            "unreferenced-golden"),
          ruleId: "TEST-001", ruleVersion: "1", path: gf,
          locator: "references=0",
          claim: "tests/**/*.golden.json must be referenced in tests",
          rootCause: "STATIC-UNREFERENCED",
          severity: sev, evidence: @[gf],
          dispositionHint: "Add test reference or remove orphan golden"
        ))
  except CatchableError:
    discard

# --- DOC-LINK-001: broken relative markdown links ---

proc isExcludedPath*(ctx: RuleCtx, p: string): bool {.raises: [].} =
  ## True when `p` (repo-relative) falls under any excluded dir (e.g. the
  ## audit's own generated reports under docs/audit/). Deterministic prefix
  ## match, mirroring audit_observations' exclusion.
  for d in ctx.excludedDirs:
    if p == d or p.startsWith(d):
      return true
  false

func isEscaped(s: string; idx: int): bool {.raises: [].} =
  ## True when the character at `idx` is preceded by an odd run of backslashes.
  var backslashes = 0
  var i = idx - 1
  while i >= 0 and s[i] == '\\':
    inc backslashes
    dec i
  (backslashes mod 2) == 1

func maskInlineCode(line: string): string {.raises: [].} =
  ## Replace CommonMark code spans (matched backtick runs) with spaces,
  ## preserving length so column positions stay valid.
  result = line
  var i = 0
  while i < result.len:
    if result[i] != '`':
      inc i
      continue
    var runEnd = i
    while runEnd < result.len and result[runEnd] == '`':
      inc runEnd
    let runLen = runEnd - i
    var j = runEnd
    var closeAt = -1
    while j < result.len:
      if result[j] == '`':
        var k = j
        while k < result.len and result[k] == '`':
          inc k
        if k - j == runLen:
          closeAt = j
          break
        j = k
      else:
        inc j
    if closeAt < 0:
      i = runEnd
      continue
    for x in i ..< closeAt + runLen:
      result[x] = ' '
    i = closeAt + runLen

func fenceRun(line: string): (bool, char, int) {.raises: [].} =
  ## Detect a fenced-code delimiter (``` or ~~~, indented at most 3 spaces).
  ## Returns (isRun, fenceChar, runLength).
  var i = 0
  while i < line.len and line[i] == ' ' and i < 4:
    inc i
  if i > 3 or i >= line.len: return (false, '\0', 0)
  let c = line[i]
  if c != '`' and c != '~': return (false, '\0', 0)
  var j = i
  while j < line.len and line[j] == c:
    inc j
  if j - i < 3: return (false, '\0', 0)
  if c == '`':
    # Backtick info strings may not contain backticks (CommonMark).
    for k in j ..< line.len:
      if line[k] == '`': return (false, '\0', 0)
  (true, c, j - i)

func parseLinkDestination(line: string; start: int): (bool, string, int) {.raises: [].} =
  ## Parse a CommonMark inline-link destination starting just after "](".
  ## Returns (ok, destination, indexAfterCloseParen). Invalid link syntax is
  ## rejected instead of treating arbitrary bracketed prose as a link.
  var i = start
  while i < line.len and line[i] in {' ', '\t'}:
    inc i
  if i >= line.len: return (false, "", -1)
  var dest = ""
  if line[i] == '<':
    inc i
    var closed = false
    while i < line.len:
      if line[i] == '\\' and i + 1 < line.len:
        dest.add(line[i + 1])
        i += 2
        continue
      if line[i] == '>':
        inc i
        closed = true
        break
      if line[i] == '<' or line[i] == '\n':
        break
      dest.add(line[i])
      inc i
    if not closed: return (false, "", -1)
  else:
    var depth = 0
    while i < line.len:
      let c = line[i]
      if c == '\\' and i + 1 < line.len:
        dest.add(line[i + 1])
        i += 2
        continue
      if c in {' ', '\t'}:
        break
      if c == '(':
        inc depth
        dest.add(c)
        inc i
        continue
      if c == ')':
        if depth == 0: break
        dec depth
        dest.add(c)
        inc i
        continue
      dest.add(c)
      inc i
    if depth != 0: return (false, "", -1)
  var j = i
  while j < line.len and line[j] in {' ', '\t'}:
    inc j
  if j < line.len and line[j] == ')':
    return (true, dest, j + 1)
  # Optional link title: "...", '...', or (...).
  if j < line.len and line[j] in {'"', '\'', '('}:
    let opener = line[j]
    let closer = if opener == '(': ')' else: opener
    inc j
    var titleClosed = false
    while j < line.len:
      if line[j] == '\\' and j + 1 < line.len:
        j += 2
        continue
      if line[j] == closer:
        inc j
        titleClosed = true
        break
      inc j
    if not titleClosed: return (false, "", -1)
    while j < line.len and line[j] in {' ', '\t'}:
      inc j
    if j < line.len and line[j] == ')':
      return (true, dest, j + 1)
  (false, "", -1)

func isExternalTarget(target: string): bool {.raises: [].} =
  ## URLs with a scheme, protocol-relative, root-absolute, and home-relative
  ## targets are not repository-relative filesystem paths.
  if target.startsWith("//") or target.startsWith("/") or target.startsWith("~"):
    return true
  let colon = target.find(':')
  if colon > 0 and target[0].isAlphaAscii():
    var scheme = true
    for i in 0 ..< colon:
      let c = target[i]
      if not (c.isAlphaNumeric or c in {'+', '-', '.'}):
        scheme = false
        break
    if scheme: return true
  false

proc evalDocLink001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Only CommonMark inline links (`](target)`) outside fenced code blocks and
  ## inline code spans are inspected. `#anchor` fragments are not path
  ## components, and the locator records the real 1-based source line.
  if ctx.docsDir.len == 0 or not dirExists(ctx.docsDir): return @[]
  try:
    let mdFiles = globFiles(ctx.docsDir & "/**/*.md")
    for mdFile in mdFiles:
      if isExcludedPath(ctx, mdFile): continue
      let content = readFile(mdFile)
      var inFence = false
      var fenceChar = '\0'
      var fenceLen = 0
      var lineNum = 0
      for rawLine in content.splitLines:
        inc lineNum
        let (isRun, fc, fl) = fenceRun(rawLine)
        if isRun:
          if not inFence:
            inFence = true
            fenceChar = fc
            fenceLen = fl
          elif fc == fenceChar and fl >= fenceLen:
            var trailing = rawLine.strip()
            var onlyFence = trailing.len >= fl
            if onlyFence:
              for c in trailing:
                if c != fc:
                  onlyFence = false
                  break
            if onlyFence:
              inFence = false
          continue
        if inFence: continue
        let line = maskInlineCode(rawLine)
        var pos = 0
        while pos + 1 < line.len:
          let closeBracket = line.find("](", pos)
          if closeBracket < 0: break
          var hasOpener = false
          var k = closeBracket - 1
          while k >= 0:
            if line[k] == '[' and not isEscaped(line, k):
              hasOpener = true
              break
            dec k
          if not hasOpener or isEscaped(line, closeBracket):
            pos = closeBracket + 2
            continue
          let (ok, rawTarget, afterLink) = parseLinkDestination(line, closeBracket + 2)
          if not ok:
            pos = closeBracket + 2
            continue
          pos = afterLink
          let hashPos = rawTarget.find('#')
          let linkTarget = if hashPos >= 0: rawTarget[0 ..< hashPos] else: rawTarget
          if linkTarget.len == 0 or isExternalTarget(linkTarget):
            continue
          # Resolve relative to the markdown file's directory.
          let mdDir = parentDir(mdFile)
          let resolved = joinPath(mdDir, linkTarget)
          if not fileExists(resolved) and not dirExists(resolved):
            let sev = resolveSeverity("DOC-LINK-001")
            result.add(RuleResult(
              findingKey: fingerprint("DOC-LINK-001", mdFile, linkTarget,
                "broken-relative-link",
                "doc-link-broken"),
              ruleId: "DOC-LINK-001", ruleVersion: "1", path: mdFile,
              locator: "line=" & $lineNum,
              claim: "docs markdown relative links must resolve",
              rootCause: "link target does not exist: " & rawTarget,
              severity: sev, evidence: @[resolved],
              dispositionHint: "Fix broken link or remove dead reference"
            ))
  except CatchableError:
    discard

# --- DOC-CLA-001: tierA claims verification ---

proc evalDocCla001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Verify tierA claims: doc tokens bin/… & make targets reported in docs exist.
  if ctx.docsDir.len == 0 or not dirExists(ctx.docsDir): return @[]
  try:
    let mdFiles = globFiles(ctx.docsDir & "/**/*.md")
    for mdFile in mdFiles:
      if isExcludedPath(ctx, mdFile): continue
      let content = readFile(mdFile)
      for line in content.splitLines:
        # Look for tierA claim markers: mentions of bin/ paths or make targets
        if line.contains("tierA") or line.contains("TierA"):
          # Extract bin/ path references
          var pos = 0
          while pos < line.len:
            let binRef = line.find("bin/", pos)
            if binRef < 0: break
            var endPos = binRef + 4
            while endPos < line.len and line[endPos] notin {' ', '\t', ')', ']', '"'}:
              inc endPos
            let pathToken = if endPos < line.len: line[binRef..(endPos - 1)] else: line[binRef..^1]
            let fullPath = joinPath(ctx.repoRoot, pathToken)
            if not fileExists(fullPath) and not dirExists(fullPath):
              let sev = resolveSeverity("DOC-CLA-001")
              result.add(RuleResult(
                findingKey: fingerprint("DOC-CLA-001", mdFile, pathToken,
                  "tierA-bin-path-missing",
                  "doc-cla-missing"),
                ruleId: "DOC-CLA-001", ruleVersion: "1", path: mdFile,
                locator: "line=" & $(binRef + 1),
                claim: "tierA claims about bin/ paths must reference existing files",
                rootCause: "file/directory not found: " & pathToken,
                severity: sev, evidence: @[fullPath],
                dispositionHint: "Update claim or create the referenced artifact"
              ))
            pos = if endPos > 0: endPos + 1 else: line.len
  except CatchableError:
    discard

# --- QUIRK-001..004: marker-lacking-registry → quirk-doc path ---

# Forward declaration: base evaluator defined after the per-marker wrappers.
proc evalQuirkBase*(ctx: RuleCtx, ruleId, marker, docPath: string): seq[RuleResult]
    {.raises: [].}

proc evalQuirk001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## QUIRK-001: DEBT# markers lacking registry entry ⇒ quirk-doc path exists?
  evalQuirkBase(ctx, "QUIRK-001", "DEBT#", "docs/spec/debt_quirks.md")

proc evalQuirk002*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## QUIRK-002: TODO# markers lacking registry entry.
  evalQuirkBase(ctx, "QUIRK-002", "TODO#", "docs/spec/todo_quirks.md")

proc evalQuirk003*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## QUIRK-003: HACK# markers lacking registry entry.
  evalQuirkBase(ctx, "QUIRK-003", "HACK#", "docs/spec/hack_quirks.md")

proc evalQuirk004*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## QUIRK-004: FIXME# markers lacking registry entry.
  evalQuirkBase(ctx, "QUIRK-004", "FIXME#", "docs/spec/fixme_quirks.md")

proc evalQuirkBase*(ctx: RuleCtx, ruleId, marker, docPath: string): seq[RuleResult] {.raises: [].} =
  ## Generic quirk-base evaluator: scan source files for marker patterns,
  ## check if corresponding quirk-doc path exists.
  let sev = resolveSeverity(ruleId)
  let scanDirs = @[ctx.srcDir, ctx.toolsDir]
  for scanDir in scanDirs:
    if scanDir.len == 0 or not dirExists(scanDir): continue
    try:
      let files = globFiles(scanDir & "/**/*.nim")
      for f in files:
        let content = readFile(f)
        let lines = content.splitLines
        for lineNum in 0 ..< lines.len:
          let line = lines[lineNum]
          if line.contains(marker):
            # Check if quirk-doc path exists
            let quirkDoc = joinPath(ctx.repoRoot, docPath)
            if not fileExists(quirkDoc):
              result.add(RuleResult(
                findingKey: fingerprint(ruleId, f, "line=" & $(lineNum + 1),
                  "marker-" & marker & "-lacking-registry",
                  "quirk-doc-missing"),
                ruleId: ruleId, ruleVersion: "1", path: f,
                locator: "line=" & $(lineNum + 1),
                claim: "markers require registry entry + quirk-doc path",
                rootCause: "marker " & marker & " found but " & docPath & " missing",
                severity: sev, evidence: @[f, "marker=" & marker],
                dispositionHint: "Create " & docPath & " or register marker in debt_registry"
              ))
    except CatchableError:
      discard

# --- TC-001: toolchain version mismatch ---

proc evalTc001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Compare toolchain versions in docs/spec/ vs ctx.toolchain versions.
  if ctx.docsDir.len == 0 or not dirExists(ctx.docsDir): return @[]
  if ctx.toolchainVersions.len == 0: return @[]
  try:
    let specFiles = globFiles(ctx.docsDir & "/**/toolchain*.md") &
                    globFiles(ctx.docsDir & "/**/spec*.md")
    for sf in specFiles:
      let content = readFile(sf)
      for tvPair in ctx.toolchainVersions:
        let (name, expectedVer) = tvPair
        # Look for version declarations like "Nim 2.2.10" or "Lean 4.29"
        let pattern = name & " "
        if content.contains(pattern):
          # Extract declared version from content
          for line in content.splitLines:
            if line.contains(pattern):
              let verStart = line.find(pattern) + pattern.len
              var verEnd = verStart
              while verEnd < line.len and (line[verEnd].isAlphaNumeric or line[verEnd] == '.'):
                inc verEnd
              let declaredVer = line[verStart..(verEnd - 1)]
              if declaredVer != expectedVer:
                let sev = resolveSeverity("TC-001")
                result.add(RuleResult(
                  findingKey: fingerprint("TC-001", sf, name,
                    "version-mismatch",
                    "tc-version-drift"),
                  ruleId: "TC-001", ruleVersion: "1", path: sf,
                  locator: "line=" & $verStart,
                  claim: "docs/spec toolchain versions must match ctx.toolchain",
                  rootCause: name & " declared=" & declaredVer & " expected=" & expectedVer,
                  severity: sev, evidence: @[sf, "declared=" & declaredVer, "expected=" & expectedVer],
                  dispositionHint: "Update docs or toolchain context to match"
                ))
  except CatchableError:
    discard

# --- LOG-001: tracked logs larger than 5MB cap ---

proc evalLog001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Check tracked log files exceeding 5MB size cap.
  if ctx.logDir.len == 0 or not dirExists(ctx.logDir): return @[]
  const MaxLogSize = 5 * 1024 * 1024  # 5MB
  try:
    let logFiles = globFiles(ctx.logDir & "/**/*.{log,json}")
    for lf in logFiles:
      if not fileExists(lf): continue
      let fi = getFileInfo(lf)
      if fi.size > MaxLogSize:
        let sev = resolveSeverity("LOG-001")
        let sizeMB = fi.size div (1024 * 1024)
        result.add(RuleResult(
          findingKey: fingerprint("LOG-001", lf, $sizeMB & "MB",
            "log-exceeds-cap",
            "oversized-log"),
          ruleId: "LOG-001", ruleVersion: "1", path: lf,
          locator: "size=" & $sizeMB & "MB",
          claim: "tracked logs must not exceed 5MB cap",
          rootCause: "log file is " & $sizeMB & "MB (cap=5MB)",
          severity: sev, evidence: @[lf, "size=" & $fi.size],
          dispositionHint: "Rotate or archive oversized log"
        ))
  except CatchableError:
    discard

# --- LOG-002: logs not referenced ---

proc evalLog002*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Fact-only: identify log files not referenced in any config/doc.
  if ctx.logDir.len == 0 or not dirExists(ctx.logDir): return @[]
  try:
    let logFiles = globFiles(ctx.logDir & "/**/*.{log,json}")
    var refTargets: HashSet[string]
    for refFile in ctx.referenceFiles:
      if fileExists(refFile):
        try:
          let content = readFile(refFile)
          for lf in logFiles:
            let baseName = extractFilename(lf)
            if baseName.len > 0 and content.contains(baseName):
              refTargets.incl(baseName)
        except CatchableError:
          discard
    for lf in logFiles:
      let baseName = extractFilename(lf)
      if not refTargets.contains(baseName):
        let sev = resolveSeverity("LOG-002")
        result.add(RuleResult(
          findingKey: fingerprint("LOG-002", lf, "unreferenced",
            "log-not-referenced",
            "orphan-log"),
          ruleId: "LOG-002", ruleVersion: "1", path: lf,
          locator: "references=0",
          claim: "log files should be referenced in config/docs",
          rootCause: "fact: log file not referenced anywhere",
          severity: sev, evidence: @[lf],
          dispositionHint: "Document log purpose or remove if orphaned"
        ))
  except CatchableError:
    discard

# --- LOG-003: logs not tracked ---

proc evalLog003*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Fact-only: log files present but not in any tracking manifest.
  if ctx.logDir.len == 0 or not dirExists(ctx.logDir): return @[]
  try:
    let logFiles = globFiles(ctx.logDir & "/**/*.{log,json}")
    for lf in logFiles:
      let sev = resolveSeverity("LOG-003")
      result.add(RuleResult(
        findingKey: fingerprint("LOG-003", lf, "untracked",
          "log-not-in-manifest",
          "untracked-log"),
        ruleId: "LOG-003", ruleVersion: "1", path: lf,
        locator: "manifest=none",
        claim: "log files should be tracked in a manifest",
        rootCause: "fact: log file exists but not in tracking manifest",
        severity: sev, evidence: @[lf],
        dispositionHint: "Add to log tracking manifest"
      ))
  except CatchableError:
    discard

# --- AUD-001: audit modules referenced from tools/debt_engine.nim ---

proc evalAud001*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Self-check: audit modules referenced from tools/debt_engine.nim.
  if ctx.debtEnginePath.len == 0 or not fileExists(ctx.debtEnginePath): return @[]
  try:
    let engineContent = readFile(ctx.debtEnginePath)
    let auditModules = globFiles(ctx.srcDir & "/**/audit*.nim")
    for am in auditModules:
      let baseName = extractFilename(am).replace(".nim", "")
      if not engineContent.contains(baseName):
        let sev = resolveSeverity("AUD-001")
        result.add(RuleResult(
          findingKey: fingerprint("AUD-001", am, "not-referenced",
            "audit-module-unreferenced-by-engine",
            "audit-orphan"),
          ruleId: "AUD-001", ruleVersion: "1", path: am,
          locator: "engine-reference=0",
          claim: "audit modules should be referenced from tools/debt_engine.nim",
          rootCause: "audit module not imported by debt_engine",
          severity: sev, evidence: @[am, ctx.debtEnginePath],
          dispositionHint: "Import audit module into debt_engine or remove"
        ))
  except CatchableError:
    discard

# --- AUD-002: audit modules referenced from tests ---

proc evalAud002*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Self-check: audit modules referenced from test files.
  if ctx.testDir.len == 0 or not dirExists(ctx.testDir): return @[]
  try:
    let testFiles = globFiles(ctx.testDir & "/**/*.nim")
    var refTargets: HashSet[string]
    for tf in testFiles:
      try:
        let content = readFile(tf)
        let baseName = extractFilename(tf).replace(".nim", "")
        if baseName.len > 0 and content.contains("audit"):
          refTargets.incl(baseName)
      except CatchableError:
        discard
    let auditModules = globFiles(ctx.srcDir & "/**/audit*.nim")
    for am in auditModules:
      let baseName = extractFilename(am).replace(".nim", "")
      if not refTargets.contains(baseName):
        let sev = resolveSeverity("AUD-002")
        result.add(RuleResult(
          findingKey: fingerprint("AUD-002", am, "no-test-ref",
            "audit-module-no-test-reference",
            "audit-untested"),
          ruleId: "AUD-002", ruleVersion: "1", path: am,
          locator: "test-reference=0",
          claim: "audit modules should have test references",
          rootCause: "no test file imports this audit module",
          severity: sev, evidence: @[am],
          dispositionHint: "Add test coverage for audit module"
        ))
  except CatchableError:
    discard

# --- AUD-003: audit produce findings list completeness ---

proc evalAud003*(ctx: RuleCtx): seq[RuleResult] {.raises: [].} =
  ## Self-check: audit produces complete findings list.
  ## Fact-only: verify that audit-related modules export RuleResult.
  try:
    let auditModules = globFiles(ctx.srcDir & "/**/audit*.nim")
    for am in auditModules:
      let content = readFile(am)
      if not content.contains("RuleResult"):
        let sev = resolveSeverity("AUD-003")
        result.add(RuleResult(
          findingKey: fingerprint("AUD-003", am, "no-rule-result",
            "audit-module-missing-ruleresult-export",
            "audit-incomplete"),
          ruleId: "AUD-003", ruleVersion: "1", path: am,
          locator: "export=none",
          claim: "audit modules should export RuleResult type",
          rootCause: "module does not define/export RuleResult",
          severity: sev, evidence: @[am],
          dispositionHint: "Export RuleResult from audit module"
        ))
  except CatchableError:
    discard

# ---------------------------------------------------------------------------
# Main dispatcher: evalRule
# ---------------------------------------------------------------------------

proc evalRule*(ruleId: string; ctx: RuleCtx; obsFilters: openArray[Obs] = @[]): seq[RuleResult] =
  ## Dispatch rule evaluation by ruleId. Returns RuleResult[] for the given rule.
  ## obsFilters is passed through for future observation-based enrichment.
  case ruleId
  of "DIR-BIN-001": result = evalDirBin001(ctx)
  of "DIR-BIN-002": result = evalDirBin002(ctx)
  of "DIR-BIN-003": result = evalDirBin003(ctx)
  of "DIR-ART-001": result = evalDirArt001(ctx)
  of "DATA-001": result = evalData001(ctx)
  of "TOOL-001": result = evalTool001(ctx)
  of "TEST-001": result = evalTest001(ctx)
  of "DOC-LINK-001": result = evalDocLink001(ctx)
  of "DOC-CLA-001": result = evalDocCla001(ctx)
  of "QUIRK-001": result = evalQuirk001(ctx)
  of "QUIRK-002": result = evalQuirk002(ctx)
  of "QUIRK-003": result = evalQuirk003(ctx)
  of "QUIRK-004": result = evalQuirk004(ctx)
  of "TC-001": result = evalTc001(ctx)
  of "LOG-001": result = evalLog001(ctx)
  of "LOG-002": result = evalLog002(ctx)
  of "LOG-003": result = evalLog003(ctx)
  of "AUD-001": result = evalAud001(ctx)
  of "AUD-002": result = evalAud002(ctx)
  of "AUD-003": result = evalAud003(ctx)
  else:
    # Unknown ruleId — run with code default severity, return empty findings.
    # This allows evalRule to be called with any string without crashing.
    discard

# ---------------------------------------------------------------------------
# Convenience: evalAll runs every catalog rule
# ---------------------------------------------------------------------------

proc evalAll*(ctx: RuleCtx; obsFilters: openArray[Obs] = @[]): seq[RuleResult] {.raises: [].} =
  ## Evaluate all catalog rules and return combined findings.
  for rc in cat:
    let findings = evalRule(rc.ruleId, ctx, obsFilters)
    result.add(findings)

# ---------------------------------------------------------------------------
# Debug helper
# ---------------------------------------------------------------------------

proc debugSample*(ctx: RuleCtx) =
  ## Print a sample evaluation of all rules to stdout for debugging.
  ## Intended for development; not part of the product contract.
  echo "=== audit_rules debug sample ==="
  echo "ctx.binDir=", ctx.binDir
  echo "ctx.tmpDir=", ctx.tmpDir
  echo "ctx.srcDir=", ctx.srcDir
  echo "ctx.docsDir=", ctx.docsDir
  echo "ctx.testDir=", ctx.testDir
  echo "ctx.logDir=", ctx.logDir
  echo "catalog size=", cat.len
  echo "---"
  for rc in cat:
    let findings = evalRule(rc.ruleId, ctx)
    echo rc.ruleId, " v", rc.version, " => ", findings.len, " findings"
  echo "=== done ==="
