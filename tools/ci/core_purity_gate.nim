## core_purity_gate.nim — src/core purity ratchet.
##
## Trust Fact enforced: `src/core/**` must not carry unapproved side effects
## (file/process I/O, console output) nor escape hatches that conceal those
## effects. No source construct buys approval: a `# axiomIoBoundary` marker or
## any other file-level declaration is documentation, not a licence, and buys
## nothing here. A file-local marker would let any later edit silently widen
## its own exemption, which is exactly what the Trust Fact forbids.
##
## Scope boundary: effects the compiler already rejects inside a `func` body
## are NOT re-implemented here (AGENTS.md §0.6 — the compiler's effect system
## is the final authority). This gate covers exactly what source text can
## prove and the effect system cannot: effect-system escapes, FFI bypasses,
## and every core site that performs a side effect at all.
##
## Rules (the complete set — no others):
##   R1 forbidden_effect — `echo `, `debugEcho(`, `stderr.write`,
##                        `stdout.write`, `stderr.writeLine`, `stdout.writeLine`
##   R2 io_primitive     — `readFile(`, `writeFile(`, `startProcess(`,
##                        `execProcess(`, `execShellCmd(`, `removeFile(`
##   R3 escape_hatch     — `{.cast(noSideEffect).}` without structural approval:
##                        (a) a `## [SEE:` annotation on the immediately
##                            preceding line, AND
##                        (b) the minimal enclosing `func` declaration
##                            carrying `{.noSideEffect`.
##   R4 importc_bypass   — an `{.importc.}` declaration with no effect pragma.
##
## R1/R2 admit no source-level exemption; R3 is approved structurally at each
## use site; R4 admits none. Only code is judged: string literals and trailing
## comments are projected away before matching, so documentation that mentions
## `echo` or `importc` is never a false positive.
##
## Approval is the baseline, and only the baseline. `data/core_purity_baseline.json`
## anchors every pre-existing violation by a SHA-256 fingerprint over (rule,
## tree-relative file, line/column-normalized detail) together with its observed
## occurrence count. Core I/O an architect has sanctioned is approved by
## registering it as a baseline anchor under that procedure — never by writing
## a marker into the source file.
##
## The anchor is a COUNT ratchet, not a membership set:
##   observed > anchored  → regression (exit 1)
##   unknown fingerprint  → regression (exit 1)
##   observed < anchored  → PASS — paying debt down is always allowed
## Adding a second copy of a violation to a file that already carries an
## anchored one is therefore caught, while removing one is never punished.
## Line numbers are normalized out, so moving a line is churn, not a regression.
##
## Tree and policy are separate by construction: the scanned tree comes from
## `--tree` (default: cwd) so CI can judge a checked-out candidate, while the
## baseline is ALWAYS read from cwd — the judge and its policy come from the
## base commit, the payload from the head.
##
## Exit codes: 0 = no regression · 1 = regression · 2 = judgment impossible
## (missing or unopenable tree, absent or malformed baseline, bad argument).
##
## Usage:
##   nim c --hints:off -d:release -o:bin/core_purity_gate tools/ci/core_purity_gate.nim
##   bin/core_purity_gate                    # --check (default), cwd tree
##   bin/core_purity_gate --tree _candidate  # judge a candidate checkout, cwd baseline
##   bin/core_purity_gate --update-baseline  # re-anchor current violations

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import core/trusted/axiom_pragmas ## axiomEffect / tags pragmas (include chain: axiom_pragmas_macros)
import std/[algorithm, json, os, sequtils, strutils, tables]
import checksums/sha2

const
  ScannedRoot* = "src/core"
  BaselineRelPath* = "data/core_purity_baseline.json"
  BaselineVersion* = 2
  RuleVersion* = 1
  GateId* = "core_purity"

  ForbiddenEffectPatterns* = [
    "echo ", "debugEcho(", "stderr.writeLine", "stdout.writeLine",
    "stderr.write", "stdout.write",
  ]
  IoPrimitivePatterns* = [
    "readFile(", "writeFile(", "startProcess(", "execProcess(",
    "execShellCmd(", "removeFile(",
  ]
  ## Pragma markers that actually declare effects in Nim's effect system.
  ## Codegen/ABI markers (`header`, `dynlib`, `cdecl`, `importcpp`) declare no
  ## effect, so they cannot discharge the R4 bypass.
  EffectPragmaMarkers* = ["noSideEffect", "raises"]

  CastPattern* = "cast(noSideEffect)"
  SeeAnnotation* = "## [SEE:"
  RoutineKeywords = [
    "func ", "func*", "proc ", "proc*", "template ", "template*",
    "method ", "method*", "macro ", "macro*", "iterator ", "iterator*",
    "converter ", "converter*",
  ]
  ImportcToken = "importc"
  TreePrefix* = "--tree="

type
  Rule* = enum
    rForbiddenEffect, rIoPrimitive, rEscapeHatch, rImportcBypass

  Violation* = object
    rule*: Rule
    file*: string   ## tree-relative, forward slashes
    line*: int
    detail*: string

  Regressed* = object
    fingerprint*: string
    rule*: Rule
    file*: string
    detail*: string
    observed*: int    ## occurrences found in the scanned tree
    anchored*: int    ## occurrences the baseline permits
    extraLines*: seq[int]  ## occurrences beyond the anchor, sorted

const AllRules: array[4, Rule] = [rForbiddenEffect, rIoPrimitive, rEscapeHatch, rImportcBypass]

func ruleId*(r: Rule): string {.raises: [].} =
  case r
  of rForbiddenEffect: "forbidden_effect"
  of rIoPrimitive: "io_primitive"
  of rEscapeHatch: "escape_hatch"
  of rImportcBypass: "importc_bypass"

# ── Code projection ──────────────────────────────────────────────────

func stripCode*(line: string): string {.raises: [].} =
  ## Code-only projection of a source line: string literal contents and the
  ## trailing comment are dropped. Documentation and data mentioning a banned
  ## token therefore never register as code.
  var i = 0
  while i < line.len:
    let c = line[i]
    if c == '"':
      inc i
      while i < line.len:
        if line[i] == '\\':
          i += 2
          continue
        inc i
        if i <= line.len and i - 1 < line.len and line[i - 1] == '"':
          break
    elif c == '#':
      break
    else:
      result.add c
      inc i

# ── R3 structural approval ───────────────────────────────────────────

func isRoutineStart(line: string): bool {.raises: [].} =
  let t = stripCode(line).strip()
  for kw in RoutineKeywords:
    if t.startsWith(kw):
      return true
  false

func enclosingRoutineIndex(lines: seq[string], fromIdx: int): int {.raises: [].} =
  ## Nearest preceding routine declaration lexically enclosing `fromIdx`,
  ## or -1 when the use site has no routine above it.
  var i = fromIdx
  while i >= 0:
    if isRoutineStart(lines[i]):
      return i
    dec i
  -1

func declarationSpan(lines: seq[string], startIdx: int): string {.raises: [].} =
  ## Signature of the routine declared at `startIdx`: its declaration lines
  ## up to the body introducer. Stops at a blank line or the next routine so
  ## a signature never absorbs an unrelated declaration.
  var i = startIdx
  while i < lines.len:
    let code = stripCode(lines[i]).strip()
    if i > startIdx and code.len == 0:
      break
    if i > startIdx and isRoutineStart(lines[i]):
      break
    result.add code
    result.add "\n"
    if code.endsWith("=") or code.endsWith("->"):
      break
    inc i

func escapeHatchApproved*(lines: seq[string], idx: int): bool {.raises: [].} =
  ## R3 approval = (a) SEE annotation on the immediately preceding line AND
  ## (b) minimal enclosing `func` declaration carrying `{.noSideEffect`.
  let seeOk = idx > 0 and SeeAnnotation in lines[idx - 1]
  let declIdx = enclosingRoutineIndex(lines, idx)
  let funcOk = declIdx >= 0 and
               stripCode(lines[declIdx]).strip().startsWith("func") and
               "noSideEffect" in declarationSpan(lines, declIdx)
  seeOk and funcOk

func escapeHatchMissing(lines: seq[string], idx: int): string {.raises: [].} =
  var missing: seq[string]
  if not (idx > 0 and SeeAnnotation in lines[idx - 1]):
    missing.add "no-see-annotation"
  let declIdx = enclosingRoutineIndex(lines, idx)
  if declIdx < 0 or
      not stripCode(lines[declIdx]).strip().startsWith("func") or
      not ("noSideEffect" in declarationSpan(lines, declIdx)):
    missing.add "no-nosideeffect-func-enclosing"
  missing.join("+")

# ── R4 FFI bypass ────────────────────────────────────────────────────

func hasEffectPragma*(code: string): bool {.raises: [].} =
  for marker in EffectPragmaMarkers:
    if marker in code:
      return true

func isImportcPragma*(code: string): bool {.raises: [].} =
  ## `{.importc...}` / `{.importc: "...", ...}` as a pragma name. The token
  ## must directly follow a pragma opening `{.` or a pragma separator `,` so
  ## that `strVal == "importc"` or `.importc.` in data is not a pragma.
  var i = 0
  while i + ImportcToken.len <= code.len:
    if code[i ..< i + ImportcToken.len] == ImportcToken:
      let after = i + ImportcToken.len
      if after >= code.len or not code[after].isAlphaNumeric:
        var j = i - 1
        while j >= 0 and code[j] in {' ', '\t'}:
          dec j
        if j >= 0 and code[j] == ',':
          return true
        if j >= 1 and code[j] == '.' and code[j - 1] == '{':
          return true
      i = after
    else:
      inc i

# ── Module scan ──────────────────────────────────────────────────────

func scanModule*(relPath: string, source: string): seq[Violation] {.raises: [].} =
  ## Pure judgment of one module's source. No rule carries a file-level
  ## exemption: a declaration line in the file grants nothing. R3 is approved
  ## structurally at each use site, R4 admits none, and R1/R2 admit none.
  let lines = source.splitLines()
  for i in 0 ..< lines.len:
    let code = stripCode(lines[i])
    if code.strip().len == 0:
      continue
    for pattern in ForbiddenEffectPatterns:
      if pattern in code:
        result.add Violation(rule: rForbiddenEffect, file: relPath, line: i + 1,
                             detail: "forbidden effect: " & pattern)
        break
    for pattern in IoPrimitivePatterns:
      if pattern in code:
        result.add Violation(rule: rIoPrimitive, file: relPath, line: i + 1,
                             detail: "unapproved I/O primitive: " & pattern)
        break
    if CastPattern in code and not escapeHatchApproved(lines, i):
      result.add Violation(rule: rEscapeHatch, file: relPath, line: i + 1,
                           detail: "cast(noSideEffect) escape hatch unapproved: " &
                                   escapeHatchMissing(lines, i))
    if isImportcPragma(code) and not hasEffectPragma(code):
      result.add Violation(rule: rImportcBypass, file: relPath, line: i + 1,
                           detail: "importc pragma bypasses the effect system")

# ── Fingerprinting ───────────────────────────────────────────────────

func detailHasNimExt(s: string, at: int): bool {.raises: [].} =
  ## True when the `:` at `at` follows a `.nim` path fragment.
  var j = min(at - 1, s.high)
  while j >= 3:
    if s[j] == ' ' or s[j] == '\n':
      return false
    if s[j - 3 .. j] == ".nim":
      return true
    dec j
  false

func normalizeDetail*(detail: string): string {.raises: [].} =
  ## Collapse `:<line>` / `:<line>:<col>` groups that trail a `.nim` path so a
  ## fingerprint survives code motion. Both arities, and the separator colon
  ## that follows them, collapse to the single `::` marker — so one defect
  ## written with a column and the same defect written without one are ONE
  ## anchor rather than two.
  result = detail
  var i = 0
  while i < result.len:
    if result[i] == ':' and i + 1 < result.len and result[i + 1].isDigit and
       detailHasNimExt(result, i):
      var j = i + 1
      while j < result.len and result[j].isDigit:
        inc j
      if j < result.len and result[j] == ':':
        var k = j + 1
        while k < result.len and result[k].isDigit:
          inc k
        j = k
      if j < result.len and result[j] == ':':
        inc j
      let tail = if j < result.len: result[j .. ^1] else: ""
      result = result[0 ..< i] & "::" & tail
      i += 2
      continue
    inc i

func fingerprint*(v: Violation): string {.raises: [].} =
  ## Rule + tree-relative file + normalized detail. The line number is an
  ## input to reporting only, never to identity, and no absolute path enters
  ## the hash — identical tree ⇒ identical fingerprint in any checkout.
  var hasher = initSha_256()
  hasher.update(ruleId(v.rule) & "::" & v.file.replace('\\', '/') & "::" &
                normalizeDetail(v.detail))
  $hasher.digest()

func compareViolations(a, b: Violation): int {.raises: [].} =
  result = cmp(a.file, b.file)
  if result == 0: result = cmp(a.line, b.line)
  if result == 0: result = cmp(ruleId(a.rule), ruleId(b.rule))

func sortViolations*(violations: var seq[Violation]) {.raises: [].} =
  violations.sort(compareViolations)

# ── Count ratchet ────────────────────────────────────────────────────

func anchorCounts*(violations: seq[Violation]): Table[string, int] {.raises: [].} =
  ## Observed occurrence count per fingerprint.
  result = initTable[string, int]()
  for v in violations:
    let fp = fingerprint(v)
    result[fp] = result.getOrDefault(fp) + 1

func judge*(violations: seq[Violation], anchors: Table[string, int]): seq[Regressed] {.raises: [].} =
  ## Count ratchet, not a membership test. Group the observed violations by
  ## fingerprint and compare each group's size with its anchor:
  ##   observed > anchored → regression (a second copy of an anchored defect
  ##                          is caught, not absorbed)
  ##   unknown fingerprint → regression
  ##   observed < anchored → pass (paying debt down is never a failure)
  ## Within a regressing group the occurrences are sorted and the ones past the
  ## anchor are reported as the excess; which physical lines are old cannot be
  ## known from a line-independent fingerprint, so the anchor is presumed to
  ## cover the earliest occurrences in sorted order.
  var order: seq[string]
  var groups = initTable[string, seq[Violation]]()
  for v in violations:
    let fp = fingerprint(v)
    if fp notin groups:
      order.add fp
    groups[fp] = groups.getOrDefault(fp) & @[v]
  for fp in order:
    var group = groups.getOrDefault(fp)
    group.sort(compareViolations)
    let anchored = anchors.getOrDefault(fp)
    if group.len <= anchored:
      continue
    var extra: seq[int]
    for i in anchored ..< group.len:
      extra.add group[i].line
    result.add Regressed(fingerprint: fp, rule: group[0].rule, file: group[0].file,
                         detail: group[0].detail, observed: group.len,
                         anchored: anchored, extraLines: extra)
  result.sort(proc (a, b: Regressed): int {.raises: [].} =
    result = cmp(a.file, b.file)
    if result == 0: result = cmp(ruleId(a.rule), ruleId(b.rule))
    if result == 0: result = cmp(a.fingerprint, b.fingerprint))

# ── Filesystem / process boundary ────────────────────────────────────

proc log(msg: string) {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  echo msg

proc warn(msg: string) {.raises: [IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  stderr.writeLine(msg)

proc resolveScanRoot*(tree, cwd: string): (string, string) {.raises: [IOError, OSError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Scan universe for a run. `tree` is the candidate checkout to judge (empty
  ## means cwd, for local development); `cwd` carries the judge and its policy.
  ## Returns (errorMessage, scanRoot) — a non-empty error means judgment is
  ## impossible and the caller must fail closed with exit 2. A tree that exists
  ## but has no scanned root is an unclosed scan universe, never a clean pass.
  ## The returned root is absolute and normalized so that the tree-relative
  ## paths feeding the fingerprints never depend on how the tree was named.
  let base = if tree.len > 0: tree else: cwd
  if base.len == 0:
    return ("no scan tree given and cwd is empty", "")
  let baseAbs = if isAbsolute(base): normalizedPath(base)
               else: normalizedPath(getCurrentDir() / base)
  if not dirExists(baseAbs):
    return ("scan tree does not exist or is not a directory: " & base, "")
  let scanRoot = normalizedPath(baseAbs / ScannedRoot)
  if not dirExists(scanRoot):
    return ("scan universe is not closed — no " & ScannedRoot &
            " under: " & base, "")
  result[1] = scanRoot
  result

proc collectModules(scanRoot: string): seq[string] {.raises: [OSError, IOError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Paths of every module under the scan root, expressed relative to the scan
  ## root and lexicographically sorted, so filesystem iteration order can never
  ## reach the output and an absolute path never enters a fingerprint.
  for path in walkDirRec(scanRoot):
    if path.endsWith(".nim"):
      result.add path.replace('\\', '/')[(scanRoot.replace('\\', '/').len + 1) .. ^1]
  result.sort()

proc loadAnchors(path: string): (Table[string, int], string) {.raises: [IOError, OSError, CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Reads fingerprint → permitted occurrence count. Returns
  ## (anchors, errorMessage); a non-empty error means the baseline cannot be
  ## trusted to judge, which is fail-closed rather than "no debt".
  result[0] = initTable[string, int]()
  if not fileExists(path):
    result[1] = "baseline missing: " & BaselineRelPath
    return
  let node = try: parseJson(readFile(path))
            except JsonParsingError as e:
              result[1] = "baseline is not valid JSON: " & e.msg
              return
  if not node.hasKey("fingerprints") or node["fingerprints"].kind != JArray:
    result[1] = "baseline has no 'fingerprints' array"
    return
  for entry in node["fingerprints"].elems:
    if entry.kind != JObject or not entry.hasKey("fingerprint") or
       not entry.hasKey("count"):
      result[1] = "baseline anchor lacks 'fingerprint'/'count'"
      return
    let fp = entry["fingerprint"].getStr
    let n = entry["count"].getInt
    if n < 0:
      result[1] = "baseline anchor has a negative count"
      return
    result[0][fp] = result[0].getOrDefault(fp) + n

proc baselineByRule(violations: seq[Violation]): Table[string, int] {.raises: [].} =
  result = initTable[string, int]()
  for r in AllRules:
    result[ruleId(r)] = 0
  for v in violations:
    let key = ruleId(v.rule)
    result[key] = result.getOrDefault(key) + 1

proc ruleBreakdown(violations: seq[Violation]): string {.raises: [].} =
  var counts = baselineByRule(violations)
  var parts: seq[string]
  for r in AllRules:
    parts.add ruleId(r) & "=" & $counts.getOrDefault(ruleId(r))
  parts.join(" ")

proc writeBaseline(path: string, violations: seq[Violation]) {.raises: [IOError, OSError, CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Canonical, timestamp-free, path-free serialization — byte-identical for
  ## identical inputs. Anchors are emitted in fingerprint order with their
  ## observed occurrence count.
  var anchors = anchorCounts(violations)
  var ordered = toSeq(anchors.keys())
  ordered.sort()
  var anchorsJson = newJArray()
  for fp in ordered:
    var entry = newJObject()
    entry["fingerprint"] = %fp
    entry["count"] = %anchors[fp]
    anchorsJson.add entry
  var byRule = newJObject()
  var counts = baselineByRule(violations)
  for r in AllRules:
    byRule[ruleId(r)] = %counts.getOrDefault(ruleId(r))
  var root = newJObject()
  root["version"] = %BaselineVersion
  root["rule_version"] = %RuleVersion
  root["gate"] = %GateId
  root["scanned_root"] = %ScannedRoot
  root["total_violations"] = %violations.len
  root["unique_fingerprints"] = %ordered.len
  root["by_rule"] = byRule
  root["fingerprints"] = anchorsJson
  let parent = path.parentDir()
  if parent.len > 0 and not dirExists(parent):
    createDir(parent)
  writeFile(path, pretty(root, indent = 2) & "\n")

proc run(scanRoot, baselinePath: string, updateBaseline: bool): int {.raises: [IOError, OSError, CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let modules = collectModules(scanRoot)
  var violations: seq[Violation]
  for rel in modules:
    violations.add scanModule(rel, readFile(scanRoot / rel))
  sortViolations(violations)

  if updateBaseline:
    writeBaseline(baselinePath, violations)
    var anchors = anchorCounts(violations)
    log("[" & GateId & "] Baseline updated: " & BaselineRelPath)
    log("[" & GateId & "] Modules scanned: " & $modules.len)
    log("[" & GateId & "] Violations anchored: " & $violations.len &
        " (" & $anchors.len & " unique fingerprints)")
    log("[" & GateId & "] By rule: " & ruleBreakdown(violations))
    return 0

  let (anchors, loadError) = loadAnchors(baselinePath)
  if loadError.len > 0:
    warn("[" & GateId & "] INDETERMINATE: " & loadError)
    warn("[" & GateId & "] Generate it with: core_purity_gate --update-baseline")
    return 2

  let regressed = judge(violations, anchors)
  log("[" & GateId & "] Modules scanned: " & $modules.len)
  log("[" & GateId & "] Violations found: " & $violations.len)
  log("[" & GateId & "] Baseline anchors: " & $anchors.len & " fingerprints")

  if regressed.len == 0:
    log("[" & GateId & "] PASS: no new core purity violations.")
    return 0

  log("[" & GateId & "] FAIL: " & $regressed.len & " core purity regression(s).")
  for r in regressed:
    let lines = r.extraLines.mapIt($it).join(", ")
    log("  " & r.file & ":" & lines & ": " & ruleId(r.rule) & " — " & r.detail &
        " (observed " & $r.observed & ", anchored " & $r.anchored & ")")
  return 1

proc main(): int {.raises: [IOError, OSError, CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  var updateBaseline = false
  var tree = ""
  let params = commandLineParams()
  var i = 0
  while i < params.len:
    let arg = params[i]
    if arg.startsWith(TreePrefix):
      tree = arg[TreePrefix.len .. ^1]
    else:
      case arg
      of "--check": discard
      of "--update-baseline": updateBaseline = true
      of "--tree":
        if i + 1 >= params.len:
          warn("[" & GateId & "] --tree requires a path argument")
          return 2
        inc i
        tree = params[i]
      else:
        warn("[" & GateId & "] Unknown argument: " & arg)
        warn("Usage: core_purity_gate [--check | --update-baseline] [--tree <path>]")
        return 2
    inc i

  let cwd = getCurrentDir()
  let (scanError, scanRoot) = resolveScanRoot(tree, cwd)
  if scanError.len > 0:
    warn("[" & GateId & "] INDETERMINATE: " & scanError)
    return 2

  run(scanRoot, cwd / BaselineRelPath, updateBaseline)

when isMainModule:
  quit(main())

{.pop.}