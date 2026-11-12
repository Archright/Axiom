## Verification Auditor — Static module classifier for test-scope enforcement.
##
## Scans Nim source files and categorizes them into:
##   mcExempt       : type-only / converter-only modules (compiler guarantees)
##   mcInfrastructure: I/O-bound or FFI modules (integration-test only)
##   mcDomain       : business-logic modules (unit-test mandatory)
##
## AGENTS.md §0.7 Business-Only Test Scope enforcement.
## Design: readFile + regex line scan (Nim compiler API avoided as overkill).

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[json, os, strutils, re, tables, times]

type
  ModuleCategory* = enum
    mcExempt = "exempt"
    mcInfrastructure = "infrastructure"
    mcDomain = "domain"

  ModuleAudit* = object
    path*: string
    category*: ModuleCategory
    evidence*: string

const
  infraModules = [
    "os", "posix", "winlean", "asyncdispatch", "asyncfutures",
    "malebolgia", "threadpool", "isolates", "cpuload",
    "net", "rawsockets", "selectors",
    "dynlib", "pcre", "re", "nre",
    "db_sqlite", "db_postgres", "db_mysql", "db_odbc",
    "smtp", "httpclient", "asynchttpserver",
    "streams", "terminal", "rdstdin"
  ]

func isCommentLine(line: string): bool {.raises: [].} =
  let stripped = line.strip()
  stripped.len > 0 and stripped[0] == '#'

proc hasProcLikeDecl(content: string): bool {.raises: [RegexError].} =
  let procDeclPattern = re(r"\b(proc|func|method|template|macro)\b")
  content.find(procDeclPattern) >= 0

proc hasInfrastructureImport(content: string): bool {.raises: [RegexError].} =
  let infraPattern = re(r"\bimport\s+.*?\b(" & infraModules.join("|") & r")\b")
  content.find(infraPattern) >= 0

proc auditFile(path: string): ModuleAudit {.raises: [IOError, RegexError].} =
  let content = readFile(path)
  var codeLines: seq[string] = @[]
  for line in content.splitLines():
    if not isCommentLine(line):
      codeLines.add(line)
  let code = codeLines.join("\n")

  if not hasProcLikeDecl(code):
    return ModuleAudit(
      path: path,
      category: mcExempt,
      evidence: "no proc/func/method/template/macro declarations"
    )

  if hasInfrastructureImport(code):
    return ModuleAudit(
      path: path,
      category: mcInfrastructure,
      evidence: "imports I/O or FFI module"
    )

  ModuleAudit(
    path: path,
    category: mcDomain,
    evidence: "contains business logic"
  )

proc auditDirectory(dir: string): seq[ModuleAudit] {.raises: [OSError, IOError, RegexError].} =
  for path in walkDirRec(dir):
    if path.endsWith(".nim"):
      result.add(auditFile(path))

proc hasCorrespondingTest*(modulePath: string): bool {.raises: [].} =
  ## Check if a test file exists for the given module.
  ## Heuristic: tests/gateway/{module_name}_test.nim
  ## NOTE: tests/generated_pbt/ directory was removed; only gateway tests are checked.
  let base = modulePath.splitFile.name
  let gatewayPath = "tests/gateway/" & base & "_test.nim"
  try:
    result = fileExists(gatewayPath)
  except CatchableError:
    result = false

proc isManualFeature(path: string): bool {.raises: [IOError].} =
  ## Check if a .feature file has the @manual tag.
  ## Reads only lines preceding the first 'Feature:' line.
  let content = readFile(path)
  for line in content.splitLines():
    let stripped = line.strip()
    if stripped.startsWith("Feature:"):
      break
    if "@manual" in stripped:
      return true
  return false

func classifyFeature(path: string): string {.raises: [].} =
  ## Stub classification for a manual feature.
  result = "[CLASSIFY] Stub classification for: " & path

proc printSummaryReport(audits: seq[ModuleAudit]) {.raises: [].} =
  var counts = initCountTable[ModuleCategory]()
  for a in audits:
    counts.inc(a.category)

  echo "=== Verification Auditor Report ==="
  echo "Total modules scanned: ", audits.len
  for cat, cnt in counts:
    echo "  ", $cat, ": ", cnt
  echo ""
  echo "=== Domain modules (require tests) ==="
  for a in audits:
    if a.category == mcDomain:
      echo "  ", a.path
  echo ""
  echo "=== Infrastructure modules (integration tests only) ==="
  for a in audits:
    if a.category == mcInfrastructure:
      echo "  ", a.path, "  (", a.evidence, ")"

proc enforceReport(audits: seq[ModuleAudit], auditManual: bool) {.raises: [OSError, IOError].} =
  printSummaryReport(audits)

  echo ""
  echo "=== PBT Enforcement ==="
  for a in audits:
    if a.category == mcDomain:
      if not hasCorrespondingTest(a.path):
        echo "[PBT-DEBT] Module lacks test: ", a.path

  echo ""
  echo "=== Manual Features ==="
  for path in walkDirRec("tests/features"):
    if path.endsWith(".feature") and isManualFeature(path):
      echo "[MANUAL] Feature: ", path
      if auditManual:
        echo classifyFeature(path)

proc readLockRevision(lockPath: string): int {.raises: [OSError, IOError].} =
  ## Read lock_revision from topology.lock JSON.
  if not fileExists(lockPath):
    return 0
  try:
    let content = readFile(lockPath)
    let parsed = parseJson(content)
    result = parsed["lock_revision"].getInt()
  except CatchableError:
    result = 0

proc writeBaseline(domainCount: int, baselinePath: string, lockPath: string) {.raises: [OSError, IOError].} =
  ## Write the verification auditor baseline JSON idempotently.
  ## updated_at is audit metadata — excluded from comparison to avoid
  ## unnecessary rewrites on every run.
  let lockRev = readLockRevision(lockPath)
  let now = $now().utc
  var j = newJObject()
  j["domain_count"] = newJInt(domainCount)
  j["updated_at"] = newJString(now)
  j["updated_by"] = newJString("verification_auditor --update-baseline")
  j["lock_revision"] = newJInt(lockRev)

  let parentDir = baselinePath.parentDir()
  if not dirExists(parentDir):
    createDir(parentDir)

  # Idempotent write: exclude updated_at from comparison
  # NOTE: JsonNode is a ref type — `var x = j` aliases the same object, so
  # zeroing stableJ's updated_at also zeroes j's. Build a fresh comparison
  # object instead of mutating (a copy of) j.
  var changed = true
  if fileExists(baselinePath):
    try:
      let existing = readFile(baselinePath)
      let existingJson = parseJson(existing)
      var stableExisting = existingJson
      stableExisting["updated_at"] = %""
      var stableJ = newJObject()
      stableJ["domain_count"] = j["domain_count"]
      stableJ["updated_at"] = %""
      stableJ["updated_by"] = j["updated_by"]
      stableJ["lock_revision"] = j["lock_revision"]
      if stableExisting.pretty == stableJ.pretty:
        changed = false
    except CatchableError: # axiom:best-effort(existing-baseline-read: unreadable prior baseline treated as changed, idempotent write still proceeded)
      discard

  if changed:
    writeFile(baselinePath, pretty(j) & "\n")
  echo "[verification-auditor] Baseline written: domain_count=", domainCount, ", lock_revision=", lockRev, " -> ", baselinePath

proc main(enforce: bool = false, auditManual: bool = false, updateBaseline: bool = false) {.raises: [OSError, IOError, RegexError].} =
  let audits = auditDirectory("src")

  # Compute domain count
  var domainCount = 0
  for a in audits:
    if a.category == mcDomain:
      inc domainCount

  if updateBaseline:
    writeBaseline(domainCount, "data/verification_auditor_baseline.json", "topology.lock")

  if enforce:
    enforceReport(audits, auditManual)
  else:
    printSummaryReport(audits)

when isMainModule:
  var enforce = false
  var auditManual = false
  var updateBaseline = false
  for arg in commandLineParams():
    if arg == "--enforce":
      enforce = true
    elif arg == "--audit-manual":
      auditManual = true
    elif arg == "--update-baseline":
      updateBaseline = true
  main(enforce = enforce, auditManual = auditManual, updateBaseline = updateBaseline)

{.pop.}
