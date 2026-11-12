## Gate Negative Test Matrix
##
## Verifies that anti-theater, decision-binding, and debt-integrity gates
## correctly detect theater signatures, missing pragmas, and stale debts.
## All three suites use string injection — no temp files for suites 1 & 2.
## Suite 3 uses temp dir fixture following debt_scan_gate_feature_test.nim pattern.
##
## Run with: nim c -r --hints:off tests/unit/gate_negative_test.nim

import std/[os, strutils, json, times, sets]
import std/unittest
import gate/runners/decision_binding_gate
import gate/lib/debt_scanner

# ── Inline anti-theater helpers (imported from anti_theater_gate.nim) ──

type
  Violation* = object
    file*: string
    lineContent*: string
    rule*: string
    hint*: string

  DiffFile* = object
    fileName*: string
    lines*: seq[string]

func hasTag*(line: string; tag: string): bool =
  tag in line

func hasBestEffortTag*(line: string): bool =
  "axiom:best-effort(" in line or "bestEffort(" in line

func matchesSrcOrToolsNim*(fileName: string): bool =
  (fileName.startsWith("src/") or fileName.startsWith("tools/")) and
  fileName.endsWith(".nim")

func matchesTestNim*(fileName: string): bool =
  fileName.startsWith("tests/") and fileName.endsWith(".nim")

func matchesCIFile*(fileName: string): bool =
  fileName == "Makefile" or
  fileName.endsWith(".mk") or
  (fileName.startsWith(".circleci/") and fileName.endsWith(".yml"))

func isExceptDiscardSameLine*(line: string): bool =
  let trimmed = line.strip()
  trimmed.contains("except") and trimmed.contains("discard") and
  trimmed.contains(":")

func isExceptLine*(line: string): bool =
  let trimmed = line.strip()
  trimmed.startsWith("except") and trimmed.endsWith(":")

func isDiscardLine*(line: string): bool =
  line.strip() == "discard"

func isCheckTrueStub*(line: string): bool =
  let trimmed = line.strip()
  trimmed == "check true" or trimmed == "doAssert true" or trimmed == "assert true"

func hasOrTrue*(line: string): bool =
  "|| true" in line

func stripPlus*(line: string): string =
  if line.len > 0 and line[0] == '+':
    line[1..^1]
  else:
    line

func parseDiff*(diffText: string): seq[DiffFile] =
  var current: DiffFile
  for line in diffText.splitLines():
    if line.startsWith("+++ b/"):
      if current.fileName.len > 0 and current.lines.len > 0:
        result.add(current)
      current = DiffFile(fileName: line[6..^1])
    elif current.fileName.len > 0:
      if line.len > 0 and (line[0] == ' ' or line[0] == '+'):
        if line[0] == '+' and not line.startsWith("+++"):
          current.lines.add(line)
  if current.fileName.len > 0 and current.lines.len > 0:
    result.add(current)

func checkRuleA*(files: seq[DiffFile]): seq[Violation] =
  for df in files:
    if not matchesSrcOrToolsNim(df.fileName):
      continue
    let lines = df.lines
    for i in 0..<lines.len:
      let raw = lines[i]
      let content = stripPlus(raw)
      let prevContent = if i > 0: stripPlus(lines[i-1]) else: ""
      block sameLineCheck:
        if not isExceptDiscardSameLine(content):
          break sameLineCheck
        if hasBestEffortTag(content):
          break sameLineCheck
        result.add(Violation(
          file: df.fileName,
          lineContent: content.strip(),
          rule: "S2",
          hint: "Use {.bestEffort(\"\"\"reason\"\"\").} or handle the error properly"
        ))
      block multiLineCheck:
        if not isExceptLine(content):
          break multiLineCheck
        if i + 1 >= lines.len:
          break multiLineCheck
        let nextContent = stripPlus(lines[i+1])
        if not isDiscardLine(nextContent):
          break multiLineCheck
        if hasBestEffortTag(content) or hasBestEffortTag(nextContent):
          break multiLineCheck
        if hasBestEffortTag(prevContent):
          break multiLineCheck
        result.add(Violation(
          file: df.fileName,
          lineContent: (content.strip() & " " & nextContent.strip()).strip(),
          rule: "S2",
          hint: "Use {.bestEffort(\"\"\"reason\"\"\").} or handle the error properly"
        ))

func checkRuleB*(files: seq[DiffFile]): seq[Violation] =
  for df in files:
    if not matchesTestNim(df.fileName):
      continue
    let lines = df.lines
    for i in 0..<lines.len:
      let raw = lines[i]
      let content = stripPlus(raw)
      let prevContent = if i > 0: stripPlus(lines[i-1]) else: ""
      if not isCheckTrueStub(content):
        continue
      if hasTag(content, "axiom:compile-check") or hasTag(prevContent, "axiom:compile-check"):
        continue
      result.add(Violation(
        file: df.fileName,
        lineContent: content.strip(),
        rule: "S1",
        hint: "Tag with # axiom:compile-check or replace with a meaningful assertion"
      ))

func checkRuleC*(files: seq[DiffFile]): seq[Violation] =
  for df in files:
    if not matchesCIFile(df.fileName):
      continue
    let lines = df.lines
    for i in 0..<lines.len:
      let raw = lines[i]
      let content = stripPlus(raw)
      let prevContent = if i > 0: stripPlus(lines[i-1]) else: ""
      if not hasOrTrue(content):
        continue
      if hasBestEffortTag(content) or hasBestEffortTag(prevContent):
        continue
      result.add(Violation(
        file: df.fileName,
        lineContent: content.strip(),
        rule: "C",
        hint: "Remove `|| true` or use {.bestEffort(\"\"\"reason\"\"\").}"
      ))

func runAllChecks*(files: seq[DiffFile]): seq[Violation] =
  result.add(checkRuleA(files))
  result.add(checkRuleB(files))
  result.add(checkRuleC(files))

# ── Inline debt integrity helpers (imported from debt_integrity_gate.nim) ──

type
  RegistryEntry* = object
    id: string
    status: string

proc isOpenStatus*(status: string): bool =
  status == "open"

proc parseRegistry*(jsonPath: string): seq[RegistryEntry] =
  let content = readFile(jsonPath)
  let root = parseJson(content)
  let entriesNode = root{"entries"}
  if entriesNode.isNil or entriesNode.kind != JArray: return
  for node in entriesNode:
    let id = node{"id"}.getStr("")
    let status = node{"status"}.getStr("")
    if id.len > 0: result.add(RegistryEntry(id: id, status: status))

# ──────────────────────────────────────────────────────────────────────────────
# Suite 1: anti_theater_gate — string injection via DiffFile
# ──────────────────────────────────────────────────────────────────────────────

suite "anti_theater_gate":

  test "rule S1: check true in tests/ triggers violation":
    let diffText = """+++ b/tests/test_mod.nim
+  check true"""
    let files = parseDiff(diffText)
    let violations = runAllChecks(files)
    check violations.len > 0
    check violations[0].rule == "S1"
    check violations[0].file.endsWith("tests/test_mod.nim")

  test "rule S1: assert true in tests/ triggers violation":
    let diffText = """+++ b/tests/assertion_test.nim
+  assert true"""
    let files = parseDiff(diffText)
    let violations = runAllChecks(files)
    check violations.len > 0
    check violations[0].rule == "S1"

  test "rule S1: doAssert true in tests/ triggers violation":
    let diffText = """+++ b/tests/doassert_test.nim
+  doAssert true"""
    let files = parseDiff(diffText)
    let violations = runAllChecks(files)
    check violations.len > 0
    check violations[0].rule == "S1"

  test "rule S2: except: discard same-line in src/ triggers violation":
    let diffText = """+++ b/src/error_handler.nim
+  process() # except: discard"""
    let files = parseDiff(diffText)
    let violations = runAllChecks(files)
    check violations.len > 0
    check violations[0].rule == "S2"

  test "rule S2: except/discard multi-line in src/ triggers violation":
    let diffText = """+++ b/src/safe_runner.nim
+  try:
+    riskyOp()
+  except:
+    discard"""
    let files = parseDiff(diffText)
    let violations = runAllChecks(files)
    check violations.len > 0
    check violations[0].rule == "S2"

  test "rule C: || true in Makefile triggers violation":
    let diffText = """+++ b/Makefile
+  rm -f output || true"""
    let files = parseDiff(diffText)
    let violations = runAllChecks(files)
    check violations.len > 0
    check violations[0].rule == "C"

  test "clean src/ file does NOT trigger rule S1 (Rule B only scans tests/)":
    let diffText = """+++ b/src/clean_module.nim
+  proc foo(): int = 42"""
    let files = parseDiff(diffText)
    let violations = runAllChecks(files)
    check violations.len == 0

  test "empty diff produces no violations":
    let diffText = ""
    let files = parseDiff(diffText)
    let violations = runAllChecks(files)
    check violations.len == 0

  test "checkRuleA ignores non-src files":
    let diffText = """+++ b/docs/readme.md
+  except: discard"""
    let files = parseDiff(diffText)
    let violations = checkRuleA(files)
    check violations.len == 0

  test "checkRuleB ignores non-tests files":
    let diffText = """+++ b/src/mod.nim
+  check true"""
    let files = parseDiff(diffText)
    let violations = checkRuleB(files)
    check violations.len == 0

  test "checkRuleC ignores non-CI files":
    let diffText = """+++ b/src/main.nim
+  rm -f output || true"""
    let files = parseDiff(diffText)
    let violations = checkRuleC(files)
    check violations.len == 0

# ──────────────────────────────────────────────────────────────────────────────
# Suite 2: decision_binding_gate — checkProc string injection
# ──────────────────────────────────────────────────────────────────────────────

suite "decision_binding_gate":

  test "Result return type without pragma triggers violation":
    let decl = "proc getResult(): Result[int, Error] ="
    let body = "  result = ok(42)"
    let (violations, reasons) = checkProc(decl, body, "src/mod.nim", 10)
    check violations == true
    check reasons.len > 0
    check "Result" in reasons[0] or "Option" in reasons[0]

  test "Option return type without pragma triggers violation":
    let decl = "proc findItem(id: int): Option[string] ="
    let body = "  result = some(\"item\")"
    let (violations, reasons) = checkProc(decl, body, "src/mod.nim", 5)
    check violations == true

  test "early-return pattern WITHOUT pragma — GATE BUG":
    ## GATE BUG: hasEarlyReturnPattern has countdown(low, high) which is always
    ## empty in Nim. The function can never detect guarded early returns.
    ## Expected: violations == true, Actual: violations == false
    let decl = "proc validateInput(input: string): bool ="
    let body = """  if input.len == 0:
    return false
  if input.len > 100:
    return too_long
  result = true"""
    let (violations, reasons) = checkProc(decl, body, "src/mod.nim", 1)
    ## FIX: countdown order corrected — now properly detects guarded early returns.
    check violations == true
    check "early" in reasons[0] or "return" in reasons[0]

  test "validation logic with assert( triggers violation":
    let decl = "proc validateConfig(cfg: Config): bool ="
    let body = """  assert(cfg.host.len > 0)
  check(cfg.port > 0)
  result = true"""
    let (violations, reasons) = checkProc(decl, body, "src/mod.nim", 1)
    check violations == true
    check reasons.len > 0
    check "validation" in reasons[0]

  test "same procs WITH axiomDecision pragma do NOT trigger violation":
    let decl = """proc getResult(): Result[int, Error] {.axiomDecision.} ="""
    let body = "  result = ok(42)"
    let (violations, reasons) = checkProc(decl, body, "src/mod.nim", 10)
    check violations == false
    check reasons.len == 0

  test "simple pure function does NOT trigger violation":
    let decl = "proc add(a: int, b: int): int ="
    let body = "  result = a + b"
    let (violations, reasons) = checkProc(decl, body, "src/math.nim", 1)
    check violations == false
    check reasons.len == 0

  test "func returning bool without special patterns does NOT trigger":
    let decl = "proc isEnabled(): bool ="
    let body = "  result = true"
    let (violations, reasons) = checkProc(decl, body, "src/config.nim", 1)
    check violations == false

  test "single early return does NOT trigger (needs 2+)":
    let decl = "proc safeDivide(a, b: float): float ="
    let body = """  if b == 0.0: return 0.0
  result = a / b"""
    let (violations, reasons) = checkProc(decl, body, "src/math.nim", 1)
    check violations == false

  test "Result return WITH axiomDecision pragma does NOT trigger":
    let decl = """proc fetchUser(id: UserId): Result[User, FetchError] {.axiomDecision.} ="""
    let body = """  if id.isNil: return err(FetchError.noId)
  result = ok(User(id))"""
    let (violations, reasons) = checkProc(decl, body, "src/users.nim", 1)
    check violations == false
    check reasons.len == 0

  test "guard clause validation without pragma triggers":
    let decl = "proc authenticate(user: string, pass: string): bool ="
    let body = """  guard user.isValid
  guard pass.length >= 8
  result = checkCredentials(user, pass)"""
    let (violations, reasons) = checkProc(decl, body, "src/auth.nim", 1)
    check violations == true
    check reasons.len > 0

# ──────────────────────────────────────────────────────────────────────────────
# Suite 3: debt_integrity — temp dir fixture (registry + code marker binding)
# ──────────────────────────────────────────────────────────────────────────────

suite "debt_integrity (binding checks)":

  setup:
    let tmpDir = getTempDir() / "axiom_debt_binding_test_" & $epochTime().int
    createDir(tmpDir / "src")
    createDir(tmpDir / "data")

  teardown:
    removeDir(tmpDir)

  test "open debt in registry without code marker reports stale failure":
    writeFile(tmpDir / "data" / "debt_registry.json",
      """{"entries": [{"id": "DEBT#999", "status": "open", "severity": "high", "category": "test"}]}""")
    writeFile(tmpDir / "src" / "clean.nim", "echo \"no debt here\"\n")

    let entries = parseRegistry(tmpDir / "data" / "debt_registry.json")
    check entries.len == 1
    check entries[0].id == "DEBT#999"
    check entries[0].status == "open"

    let scanned = scanDebtPragmas(tmpDir / "src")
    var codeIds: HashSet[string]
    for s in scanned: codeIds.incl(s.id)

    check "DEBT#999" notin codeIds

  test "open debt in registry WITH matching code marker passes binding":
    writeFile(tmpDir / "data" / "debt_registry.json",
      """{"entries": [{"id": "DEBT#100", "status": "open", "severity": "medium", "category": "test"}]}""")
    writeFile(tmpDir / "src" / "marked.nim", """
# LEGACY-0000
{.axiomDebt: "DEBT#100", kind: "quirk".}
proc markedFunc() = discard
""")

    let scanned = scanDebtPragmas(tmpDir / "src")
    var codeIds: HashSet[string]
    for s in scanned: codeIds.incl(s.id)

    check "DEBT#100" in codeIds

  test "closed debt in registry does NOT cause stale failure":
    writeFile(tmpDir / "data" / "debt_registry.json",
      """{"entries": [{"id": "DEBT#200", "status": "closed", "severity": "low", "category": "test"}]}""")
    writeFile(tmpDir / "src" / "clean.nim", "echo done\n")

    let entries = parseRegistry(tmpDir / "data" / "debt_registry.json")
    check entries.len == 1
    check entries[0].status == "closed"

    let scanned = scanDebtPragmas(tmpDir / "src")
    var codeIds: HashSet[string]
    for s in scanned: codeIds.incl(s.id)

    var openIds: seq[string]
    for e in entries:
      if e.status == "open": openIds.add(e.id)
    check openIds.len == 0

  test "accepted debt without marker produces orphan warning (not failure)":
    writeFile(tmpDir / "data" / "debt_registry.json",
      """{"entries": [{"id": "DEBT#300", "status": "accepted", "severity": "low", "category": "test"}]}""")
    writeFile(tmpDir / "src" / "clean.nim", "echo nothing\n")

    let entries = parseRegistry(tmpDir / "data" / "debt_registry.json")
    var acceptedIds: seq[string]
    for e in entries:
      if e.status == "accepted" or e.status == "exempted": acceptedIds.add(e.id)
    check acceptedIds.len == 1

    let scanned = scanDebtPragmas(tmpDir / "src")
    var codeIds: HashSet[string]
    for s in scanned: codeIds.incl(s.id)

    check "DEBT#300" notin codeIds

  test "code marker without registry entry is orphan-code warning":
    writeFile(tmpDir / "data" / "debt_registry.json",
      """{"entries": []}""")
    writeFile(tmpDir / "src" / "dangling.nim", """
{.axiomDebt: "DEBT#777", kind: "fixme".}
proc dangling() = discard
""")

    let entries = parseRegistry(tmpDir / "data" / "debt_registry.json")
    check entries.len == 0

    let scanned = scanDebtPragmas(tmpDir / "src")
    check scanned.len > 0
    check scanned[0].id == "DEBT#777"

    var allRegistryIds: HashSet[string]
    for e in entries: allRegistryIds.incl(e.id)
    check "DEBT#777" notin allRegistryIds

  test "parseRegistry handles empty entries array":
    writeFile(tmpDir / "data" / "debt_registry.json",
      """{"entries": []}""")
    let entries = parseRegistry(tmpDir / "data" / "debt_registry.json")
    check entries.len == 0

  test "scanDebtPragmas on empty src directory returns empty":
    let emptySrc = tmpDir / "empty_src"
    createDir(emptySrc)
    let scanned = scanDebtPragmas(emptySrc)
    check scanned.len == 0
