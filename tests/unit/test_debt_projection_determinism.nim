## tests/unit/test_debt_projection_determinism.nim
##
## Unit tests for the REAL projection core exported by tools/debt_engine.nim.
## Nothing here re-implements the generator: the previous revision of this file
## carried its own `aggregate`/`genConstants`/`genMarkdown` copy, so a defect in
## the shipped generator could not move the test at all. Every assertion below
## runs the exported procs.
##
## Suites:
##   "debt projection determinism"
##     1. determinism — same input -> byte-identical output
##     2. canonical output — golden constants block + rendered row cells
##     3. no timestamp leakage — projections carry no wall-clock metadata
##     4. format independence — JSON layout does not reach the projection
##   "debt projection semantic input"
##     5. counterfactual — across VALID architecture_debt documents the
##        projection bytes do not move
##     6. precondition — the architecture_debt companion is existence-gated,
##        and is not read by the projection core
##   "debt close atomic mutation (DEBT#437)"
##     7. success path — `--close` mutates the SSOT entry and every derived
##        artifact (P1 markdown, P1 constants, P2 ledger) in one operation
##        whose post-state passes `--validate`
##     8. failure paths — unknown id / already-closed target / inconsistent
##        checkout / post-validation failure: every touched file stays
##        byte-identical to its pre-close state (rollback contract)
##
## All logic is in-memory plus per-test temp trees; no repo data file is read or
## written. (Suite 3 is the exception by design: it drives the compiled CLI in
## a temp miniature checkout, never in the repository itself — it reads only
## `data/debt_schema.json` as a read-only template.)

import std/[unittest, json, os, osproc, strutils, tables, tempfiles, algorithm]
import core/debt/debt_registry_projection as engine

# ═══════════════════════════════════════════════════════════════════════════════
# Fixtures — registry entries carry `severity` and `description`; the deprecated
# `impact`/`title` aliases are out of the projection contract and unread.
# ═══════════════════════════════════════════════════════════════════════════════

const RegistryFixture = """{
  "entries": [
    {"id":"DEBT#001","severity":"critical","status":"open","source":"manual","description":"Critical memory leak in engine loop","category":"memory","files":["src/core/engine.nim"]},
    {"id":"DEBT#002","severity":"low","status":"closed","source":"manual","description":"Minor formatting inconsistency","category":"style","files":["src/cli/main.nim"]},
    {"id":"DEBT#003","severity":"high","status":"open","source":"manual","description":"Unhandled edge case in gate runner","category":"logic","files":["src/gate/runners.nim","src/gate/utils.nim"]}
  ]
}"""

## Wider registry: an entry with no references, a reference list that must join,
## a description carrying a literal pipe, and a severity outside the declared
## vocabulary that must still receive its own section.
const RichRegistryFixture = """{
  "version": "1.0.0",
  "entries": [
    {"id":"DEBT#101","severity":"critical","status":"open","source":"manual","description":"Unbounded recursion in the gate scheduler","category":"logic","files":["src/gate/orchestrator_hook.nim","src/gate/scheduler.nim"]},
    {"id":"DEBT#102","severity":"critical","status":"closed","source":"manual","description":"Missing contract on an exported API","category":"api","files":["src/api/index.nim"],"resolution":"FIXED","resolvedAt":"2026-01-02"},
    {"id":"DEBT#103","severity":"high","status":"open","source":"manual","description":"Untracked effect annotation | IO path","category":"effects","files":[]},
    {"id":"DEBT#104","severity":"medium","status":"open","source":"manual","description":"Layer boundary drift in the verifier","category":"architecture","files":["src/core/verifier/lean_repl_bridge.nim"]},
    {"id":"DEBT#105","severity":"low","status":"closed","source":"manual","description":"Doc comment drift","category":"docs","files":["docs/spec/example.md"]},
    {"id":"DEBT#106","severity":"blocker","status":"open","source":"manual","description":"Out-of-vocabulary severity still receives a section","category":"experiment","files":["tools/probe.nim"]}
  ]
}"""

## Variant A — realistic: many tracked paths, spanning counts and dates.
const ArchDebtRich = """{
  "version": 2,
  "generatedBy": "projection-determinism-fixture",
  "entries": [
    {"file":"src/gate/orchestrator_hook.nim","count":12,"firstSeen":"2025-11-03","lastSeen":"2026-09-28"},
    {"file":"src/gate/scheduler.nim","count":7,"firstSeen":"2025-12-14","lastSeen":"2026-09-28"},
    {"file":"src/api/index.nim","count":3,"firstSeen":"2026-01-02","lastSeen":"2026-08-30"},
    {"file":"src/core/verifier/lean_repl_bridge.nim","count":21,"firstSeen":"2025-06-19","lastSeen":"2026-09-27"},
    {"file":"docs/spec/example.md","count":1,"firstSeen":"2026-03-08","lastSeen":"2026-03-08"},
    {"file":"tools/probe.nim","count":4,"firstSeen":"2026-04-21","lastSeen":"2026-09-11"}
  ]
}"""

## Variant B — minimal and still valid: an empty entry list is a legal
## architecture-debt document, so it must be accepted by the same structural
## rules and must not be a distinguishable input either.
const ArchDebtMinimal = """{
  "version": 1,
  "entries": []
}"""

## Structurally INVALID: `version` is a string rather than an int and the entry
## list carries wrong-typed fields.
const ArchDebtInvalid = """{
  "version": "two",
  "entries": [
    {"file":"src/gate/orchestrator_hook.nim","count":"twelve","firstSeen":7,"lastSeen":[]}
  ]
}"""

const CurrentProjectionVersion = "2"

# ═══════════════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════════════

func containsIsoDate(s: string): bool =
  ## True when `s` carries an ISO-8601 calendar date anywhere. Scans by
  ## code point rather than by regex so the verdict does not depend on any
  ## external pattern engine.
  var digitsRun = 0
  for ch in s:
    if ch in {'0'..'9'}:
      inc digitsRun
    else:
      if digitsRun == 4 and ch == '-': return true
      digitsRun = 0
  false

proc archDocumentIsStructurallyValid(doc: string): bool {.raises: [CatchableError].} =
  ## Restates the structural rules `--validate` Part A applies to
  ## `data/architecture_debt.json` (version is an int, entries is an array, and
  ## every entry carries a non-empty `file`, a positive int `count`, a string
  ## `firstSeen` and a string `lastSeen`). The validator itself is not exported
  ## from tools/debt_engine.nim, so this predicate is a restatement rather than
  ## a call into it — it is used only to prove the counterfactual documents are
  ## both admissible, never to decide an outcome.
  var node: JsonNode
  try:
    node = parseJson(doc)
  except JsonParsingError:
    return false
  if node.kind != JObject: return false
  if not node.hasKey("version") or node["version"].kind != JInt: return false
  if not node.hasKey("entries") or node["entries"].kind != JArray: return false
  for e in node["entries"]:
    if e{"file"}.kind != JString or e{"file"}.getStr().len == 0: return false
    if e{"count"}.kind != JInt or e{"count"}.getInt() <= 0: return false
    if e{"firstSeen"}.kind != JString: return false
    if e{"lastSeen"}.kind != JString: return false
  true

proc projectUnderArchDocument(root, archDocument: string;
                              registryJson: string): tuple[md, constants: string] =
  ## Materialise `archDocument` as the checkout's architecture-debt companion and
  ## run the REAL generator with the registry held constant. The generator is
  ## chdir-sensitive by construction only if it reads the companion, which is
  ## exactly what the counterfactual measures.
  createDir(root / "data")
  writeFile(root / "data" / "architecture_debt.json", archDocument)
  let previous = getCurrentDir()
  setCurrentDir(root)
  defer: setCurrentDir(previous)
  engine.generateProjections(registryJson)

# ═══════════════════════════════════════════════════════════════════════════════
# Suite 1 — determinism of the real projection
# ═══════════════════════════════════════════════════════════════════════════════

suite "debt projection determinism":

  test "determinism: same registry yields byte-identical projections on every call":
    let first = engine.generateProjections(RegistryFixture)
    let second = engine.generateProjections(RegistryFixture)
    check first.md == second.md
    check first.constants == second.constants
    check first.md.len > 0
    check first.constants.len > 0

  test "format independence: registry JSON layout does not reach the projection":
    let reordered = """{"entries":[
      {"category":"memory","description":"Critical memory leak in engine loop",
       "files":["src/core/engine.nim"],"id":"DEBT#001","severity":"critical",
       "source":"manual","status":"open"},
      {"category":"style","description":"Minor formatting inconsistency",
       "files":["src/cli/main.nim"],"id":"DEBT#002","severity":"low",
       "source":"manual","status":"closed"},
      {"category":"logic","description":"Unhandled edge case in gate runner",
       "files":["src/gate/runners.nim","src/gate/utils.nim"],"id":"DEBT#003",
       "severity":"high","source":"manual","status":"open"}]}"""
    let canonical = engine.generateProjections(RegistryFixture)
    let reflowed = engine.generateProjections(reordered)
    check reflowed.md == canonical.md
    check reflowed.constants == canonical.constants

  test "golden constants: the generated block matches the byte-exact projection":
    let projections = engine.generateProjections(RegistryFixture)
    let expectedConstants = """# AUTO-GENERATED by tools/debt_engine.nim --codegen — DO NOT EDIT
# Source: data/debt_registry.json
# Projection contract: P1 v2

const
  DebtEntryCount* {.intdefine.} = 3
  DebtRowCount* {.intdefine.} = 3
  DebtOpenCount* {.intdefine.} = 2
  DebtOpenCritical* {.intdefine.} = 1
  DebtOpenHigh* {.intdefine.} = 1
  DebtOpenMedium* {.intdefine.} = 0
  DebtOpenLow* {.intdefine.} = 0
  DebtCriticalThreshold* {.intdefine.} = 30
  DebtProjectionVersion* = "2"

static:
  doAssert DebtEntryCount == DebtRowCount,
    "P1 projection lossless: " & $DebtEntryCount & " registry entries but " & $DebtRowCount & " rendered rows"
  doAssert DebtOpenCritical <= DebtCriticalThreshold,
    "DEBT#256 gate FAIL: open critical debt (" & $DebtOpenCritical & ") exceeds threshold (" & $DebtCriticalThreshold & ")""""
    check projections.constants == expectedConstants

  test "rendered rows carry the declared cells and round-trip through the reader":
    let projections = engine.generateProjections(RegistryFixture)
    let header = "| " & engine.RowColumns.join(" | ") & " |"
    check projections.md.contains(header)
    check "Projection: P1 v" & CurrentProjectionVersion in projections.md
    check "Total entries: 3" in projections.md
    check "Open: 2 | Closed: 1" in projections.md

    let rows = engine.parseMarkdownRows(projections.md)
    check rows.len == 3
    var rendered: seq[seq[string]]
    for row in rows: rendered.add(row.cells)
    check rendered.len == 3
    for cells in rendered:
      check cells.len == engine.DebtRowFields.len
    check @[
      @["DEBT#001", "Critical", "memory", "Critical memory leak in engine loop",
        "src/core/engine.nim", "**Open**"],
      @["DEBT#003", "High", "logic", "Unhandled edge case in gate runner",
        "src/gate/runners.nim" & engine.FilesRefSeparator & "src/gate/utils.nim",
        "**Open**"],
      @["DEBT#002", "Low", "style", "Minor formatting inconsistency",
        "src/cli/main.nim", "Closed"]
    ] == rendered

  test "declared cell kinds: empty references, escaping and section order hold":
    let registry = parseJson(RichRegistryFixture)
    let (stats, entries) = engine.aggregate(registry)
    check stats.total == 6
    check stats.openCount == 4
    check engine.parseMarkdownRows(engine.generateProjections(RichRegistryFixture).md).len == 6

    var byId = initTable[string, engine.DebtEntry]()
    for entry in entries: byId[entry.id] = entry

    check engine.renderRow(byId["DEBT#103"])[4] == engine.EmptyFilesMarker
    check engine.renderRow(byId["DEBT#101"])[4] ==
      "src/gate/orchestrator_hook.nim" & engine.FilesRefSeparator & "src/gate/scheduler.nim"
    # A literal pipe in a description is escaped, never emitted as a cell break.
    check engine.renderRow(byId["DEBT#103"])[3] == "Untracked effect annotation \\| IO path"

    # An out-of-vocabulary severity still receives a section, after the declared
    # preference order and in code-point order among the rest.
    check engine.orderedSeverities(@["blocker", "low", "critical", "medium", "high"]) ==
      @["critical", "high", "medium", "low", "blocker"]

  test "no timestamp leakage: projections carry no wall-clock metadata":
    # Control the detector itself: a vacuous absence check proves nothing.
    check containsIsoDate("resolvedAt=2026-01-02")
    check not containsIsoDate("DEBT#001 Critical")

    let projections = engine.generateProjections(RichRegistryFixture)
    for projection in [projections.constants, projections.md]:
      check "Generated" notin projection
      check "DebtLastGenerated" notin projection
      check "promoted_at" notin projection
      check not containsIsoDate(projection)
    check "Projection contract: P1 v" & CurrentProjectionVersion in projections.constants
    check "P1 v" & CurrentProjectionVersion in projections.constants
    # The single-input claim is visible in the generated header itself.
    check "# Source: data/debt_registry.json" in projections.constants
    check "architecture_debt" notin projections.constants
    check "architecture_debt" notin projections.md

  test "timestamp independence: a spurious top-level key does not reach the projection":
    let withStamp = """{
      "generated_at": "2026-08-15T09:51:52Z",
      "lastVerifiedAt": "2026-08-15",
      "entries": [
        {"id":"DEBT#001","severity":"critical","status":"open","source":"manual","description":"Critical memory leak in engine loop","category":"memory","files":["src/core/engine.nim"]},
        {"id":"DEBT#002","severity":"low","status":"closed","source":"manual","description":"Minor formatting inconsistency","category":"style","files":["src/cli/main.nim"]},
        {"id":"DEBT#003","severity":"high","status":"open","source":"manual","description":"Unhandled edge case in gate runner","category":"logic","files":["src/gate/runners.nim","src/gate/utils.nim"]}
      ]
    }"""
    check engine.generateProjections(withStamp).md == engine.generateProjections(RegistryFixture).md
    check engine.generateProjections(withStamp).constants ==
      engine.generateProjections(RegistryFixture).constants

# ═══════════════════════════════════════════════════════════════════════════════
# Suite 2 — the semantic input set is one file
#
# `data/architecture_debt.json` is an EXISTENCE PRECONDITION of a well-formed
# checkout, not a semantic input of the projection. The counterfactual below is
# the statement of that claim: hold the registry constant, vary the companion
# across documents the tool would accept, and require byte-identical output.
# ═══════════════════════════════════════════════════════════════════════════════

suite "debt projection semantic input":

  test "counterfactual: distinct valid architecture_debt documents do not move the projection":
    check ArchDebtRich != ArchDebtMinimal
    check archDocumentIsStructurallyValid(ArchDebtRich)
    check archDocumentIsStructurallyValid(ArchDebtMinimal)

    let root = createTempDir("axiom_debtproj_", "")
    defer: removeDir(root)

    let rich = projectUnderArchDocument(root, ArchDebtRich, RichRegistryFixture)
    let minimal = projectUnderArchDocument(root, ArchDebtMinimal, RichRegistryFixture)

    check rich.md == minimal.md
    check rich.constants == minimal.constants
    # The shared projection is substantive, not two empty strings agreeing.
    check rich.md.len > 0
    check engine.parseMarkdownRows(rich.md).len == 6

  test "precondition: the architecture_debt companion is existence-gated and unread":
    check not archDocumentIsStructurallyValid(ArchDebtInvalid)

    let root = createTempDir("axiom_debtprecond_", "")
    defer: removeDir(root)

    let reference = projectUnderArchDocument(root, ArchDebtRich, RichRegistryFixture)

    let invalid = projectUnderArchDocument(root, ArchDebtInvalid, RichRegistryFixture)
    check invalid.md == reference.md
    check invalid.constants == reference.constants

    removeFile(root / "data" / "architecture_debt.json")
    let absent = projectUnderArchDocument(root, ArchDebtRich, RichRegistryFixture)
    removeFile(root / "data" / "architecture_debt.json")
    let missing = engine.generateProjections(RichRegistryFixture)
    check missing.md == reference.md
    check missing.constants == reference.constants
    check absent.md == reference.md

    # The fail-closed refusal is not in the pure core: `debt_engine --codegen`
    # guards on the companion's existence before it calls the generator. This
    # core therefore has no arch-file verdict to assert — what it does have is
    # the stronger property that the arch file cannot reach it at all.
    check not fileExists(root / "data" / "architecture_debt.json")
    check missing.md.len > 0
# ═══════════════════════════════════════════════════════════════════════════════
# Suite 3 — `--close` atomic mutation path (DEBT#437)
#
# The pure core suites above cover Generate(registry); this suite covers the
# ORCHESTRATION, which exists only in the compiled CLI: validate -> mutate SSOT
# entry -> regenerate P1 -> sync P2 -> re-validate -> rollback-or-keep. Each
# scenario builds a complete miniature checkout (registry, architecture debt,
# ledger, budgets, policy dispositions, JSON schema) in a temp tree, runs a real
# `--codegen` to materialize the P1 pair, then drives `--close` as a subprocess.
# The repository itself is never written: the engine's paths are relative and
# the subprocess runs with the temp tree as CWD.
# ═══════════════════════════════════════════════════════════════════════════════

let RepoRoot = getCurrentDir() ## tests execute from the repository root

proc engineBinary(): string =
  ## The debt_engine binary under test. AXIOM_DEBT_ENGINE_BIN pins a
  ## work-in-progress build; the default is the canonical Makefile output.
  result = getEnv("AXIOM_DEBT_ENGINE_BIN", "bin/debt_engine")
  if not result.isAbsolute:
    result = RepoRoot / result

proc runEngine(binary, cwd, args: string): tuple[output: string, exitCode: int] =
  let previous = getCurrentDir()
  setCurrentDir(cwd)
  defer: setCurrentDir(previous)
  execCmdEx(quoteShell(binary) & " " & args, options = {poStdErrToStdOut})

const CloseRegistryFixture = """{
  "version": 1,
  "generatedAt": null,
  "scanner": "vs2-fixture",
  "entries": [
    {
      "id": "DEBT#900",
      "severity": "medium",
      "status": "open",
      "source": "manual",
      "category": "test",
      "description": "Fixture debt for --close atomic mutation tests",
      "files": ["data/debt_registry.json"]
    }
  ]
}"""

const CloseArchFixture = """{
  "version": 1,
  "entries": []
}"""

## BUDGET#005/#006 committed currents match the fixture's 1 open / 0 closed
## entries, so the miniature checkout starts fully consistent.
const CloseLedgerFixture = """{
  "version": "1.1.0",
  "generated": "2026-11-13T00:00:00Z",
  "description": "vs2 fixture ledger for --close tests",
  "totalRecords": 2,
  "records": [
    {
      "id": "BUDGET#005",
      "category": "BudgetCategory",
      "description": "Open registry entries",
      "budgetCategory": "bcDebtRegistryOpen",
      "metric": "debt_registry_open",
      "baseline": 1,
      "target": 0,
      "current": 1,
      "severity": "medium",
      "source": "fixture",
      "status": "open",
      "resolution": "WONT_FIX",
      "lastVerifiedAt": "2026-11-13T00:00:00Z"
    },
    {
      "id": "BUDGET#006",
      "category": "BudgetCategory",
      "description": "Closed registry entries",
      "budgetCategory": "bcDebtRegistryClosed",
      "metric": "debt_registry_closed",
      "baseline": 0,
      "target": 0,
      "current": 0,
      "severity": "low",
      "source": "fixture",
      "status": "closed",
      "resolution": "FIXED",
      "lastVerifiedAt": "2026-11-13T00:00:00Z"
    }
  ]
}"""

proc writeCloseFixture(sandbox: string; rejectNonWontFixResolution: bool) =
  ## Materialize the miniature checkout. `rejectNonWontFixResolution` is the
  ## post-validation failure injection: the schema's `resolution` pattern
  ## accepts WONT_FIX only, which the OPEN fixture entry trivially satisfies
  ## (it has no resolution) but the entry `--close` would write ("FIXED ...")
  ## does not. Pre-validation therefore passes and only the post-mutation
  ## validation can fail — exactly the rollback scenario under test.
  createDir(sandbox / "data")
  createDir(sandbox / "config" / "policy")
  writeFile(sandbox / "data" / "debt_registry.json", CloseRegistryFixture)
  writeFile(sandbox / "data" / "architecture_debt.json", CloseArchFixture)
  writeFile(sandbox / "data" / "debt_ledger.json", CloseLedgerFixture)
  writeFile(sandbox / "data" / "debt_budgets.json", """{"metrics": {}}""")
  writeFile(sandbox / "config" / "policy" / "policy_dispositions.json",
            """{"version": "1.0.0", "metrics": {}}""")
  let schemaRaw = readFile(RepoRoot / "data" / "debt_schema.json")
  if not rejectNonWontFixResolution:
    writeFile(sandbox / "data" / "debt_schema.json", schemaRaw)
  else:
    let schema = parseJson(schemaRaw)
    schema["definitions"]["DebtRegistryEntry"]["properties"]["resolution"] = %*{
      "type": "string", "pattern": "^WONT_FIX$",
      "description": "INJECTED by the DEBT#437 rollback test"}
    writeFile(sandbox / "data" / "debt_schema.json", schema.pretty() & "\n")

const CloseTargets = ["data/debt_registry.json", "docs/DEBT_REGISTRY.md",
                      "src/generated/debt_constants.nim", "data/debt_ledger.json"]

proc snapshotCloseTargets(root: string): seq[tuple[path, bytes: string]] =
  for rel in CloseTargets:
    let p = root / rel
    result.add((rel, if fileExists(p): readFile(p) else: ""))

proc checkByteIdentical(root: string; snap: seq[tuple[path, bytes: string]]) =
  ## The DEBT#437 atomicity verdict: content bytes, not mtimes. A failed close
  ## must leave every touched file byte-identical to its pre-close state.
  for (rel, bytes) in snap:
    let p = root / rel
    var matches = false
    if bytes.len == 0:
      matches = not fileExists(p)
    else:
      matches = fileExists(p) and readFile(p) == bytes
    if not matches:
      echo "  [byte-mismatch] " & rel & (if bytes.len == 0: " (must not exist)" else: "")
    check matches

const CloseSuccessArgs =
  "--close DEBT#900 " &
  "--resolution \"FIXED 2026-11-13 (vs2-fixture): atomic close verified\" " &
  "--note \"closed by the DEBT#437 unit suite\" " &
  "--resolved-by \"vs2-unit-test\""

suite "debt close atomic mutation (DEBT#437)":

  test "success: one operation closes the entry and keeps SSOT, P1 and P2 consistent":
    let engine = engineBinary()
    checkpoint "engine under test: " & engine
    require fileExists(engine)
    let root = createTempDir("axiom_debtclose_", "")
    defer: removeDir(root)
    writeCloseFixture(root, false)
    check runEngine(engine, root, "--codegen").exitCode == 0
    check runEngine(engine, root, "--validate").exitCode == 0

    let closed = runEngine(engine, root, CloseSuccessArgs)
    check closed.exitCode == 0
    check "Close complete: DEBT#900" in closed.output
    check "Post-validation passed." in closed.output

    # SSOT entry carries the closed five-field structure (cf. DEBT#526) and
    # the registry's non-entry keys survive the parse->mutate->pretty roundtrip.
    let reg = parseJson(readFile(root / "data" / "debt_registry.json"))
    let entry = reg{"entries"}[0]
    check entry{"id"}.getStr() == "DEBT#900"
    check entry{"status"}.getStr() == "closed"
    check entry{"resolution"}.getStr() ==
      "FIXED 2026-11-13 (vs2-fixture): atomic close verified"
    check entry{"resolvedBy"}.getStr() == "vs2-unit-test"
    check entry{"resolutionNote"}.getStr() == "closed by the DEBT#437 unit suite"
    check entry{"resolvedAt"}.getStr().len == 10  # date-only, like DEBT#526
    check entry{"lastVerifiedAt"}.getStr().len == 20  # strict ISO-8601 Z (schema)
    check reg{"version"}.getInt() == 1
    check reg{"scanner"}.getStr() == "vs2-fixture"

    # P1 markdown: header counts and the row's status cell moved together.
    let md = readFile(root / "docs" / "DEBT_REGISTRY.md")
    check "> Open: 0 | Closed: 1" in md
    check "| DEBT#900 | Medium | test |" in md
    check "data/debt_registry.json | Closed |" in md

    # P1 constants: the open count the compile-time gate asserts on.
    let constants = readFile(root / "src" / "generated" / "debt_constants.nim")
    check "DebtOpenCount* {.intdefine.} = 0" in constants
    check "DebtEntryCount* {.intdefine.} = 1" in constants

    # P2 ledger: BUDGET#005/#006 re-derived from the closed registry.
    let ledger = parseJson(readFile(root / "data" / "debt_ledger.json"))
    var byId: Table[string, JsonNode]
    for r in ledger{"records"}: byId[r{"id"}.getStr()] = r
    check byId["BUDGET#005"]{"current"}.getInt() == 0
    check byId["BUDGET#005"]{"status"}.getStr() == "closed"
    check byId["BUDGET#006"]{"current"}.getInt() == 1

    # Terminal state: a standalone --validate run over the closed fixture passes.
    check runEngine(engine, root, "--validate").exitCode == 0

  test "failure: unknown id changes no target file (byte-identical)":
    let engine = engineBinary()
    require fileExists(engine)
    let root = createTempDir("axiom_debtclose_", "")
    defer: removeDir(root)
    writeCloseFixture(root, false)
    check runEngine(engine, root, "--codegen").exitCode == 0
    let snap = snapshotCloseTargets(root)

    let res = runEngine(engine, root, "--close DEBT#999 --resolution \"FIXED ghost\"")
    check res.exitCode != 0
    check "DEBT#999 not found" in res.output
    checkByteIdentical(root, snap)

  test "failure: post-validation failure rolls every target file back to pre-close bytes":
    let engine = engineBinary()
    require fileExists(engine)
    let root = createTempDir("axiom_debtclose_", "")
    defer: removeDir(root)
    writeCloseFixture(root, true)
    check runEngine(engine, root, "--codegen").exitCode == 0
    # The injected schema passes while the entry is open — the failure can only
    # fire AFTER --close has materialized its candidate state.
    check runEngine(engine, root, "--validate").exitCode == 0
    let snap = snapshotCloseTargets(root)

    let res = runEngine(engine, root, CloseSuccessArgs)
    check res.exitCode != 0
    check "Post-validation FAILED" in res.output
    check "Rolled back to pre-close bytes" in res.output
    checkByteIdentical(root, snap)

  test "failure: an already-closed target is refused without further mutation":
    let engine = engineBinary()
    require fileExists(engine)
    let root = createTempDir("axiom_debtclose_", "")
    defer: removeDir(root)
    writeCloseFixture(root, false)
    check runEngine(engine, root, "--codegen").exitCode == 0
    check runEngine(engine, root, CloseSuccessArgs).exitCode == 0
    let snap = snapshotCloseTargets(root)

    let res = runEngine(engine, root, CloseSuccessArgs)
    check res.exitCode != 0
    check "already closed" in res.output
    checkByteIdentical(root, snap)

  test "failure: an inconsistent checkout is refused before any mutation":
    let engine = engineBinary()
    require fileExists(engine)
    let sandbox = createTempDir("axiom_debtclose_", "")
    defer: removeDir(sandbox)
    writeCloseFixture(sandbox, false)
    check runEngine(engine, sandbox, "--codegen").exitCode == 0
    # Simulate the manual-protocol drift DEBT#436 recorded: a hand-edited
    # projection the SSOT no longer matches.
    writeFile(sandbox / "docs" / "DEBT_REGISTRY.md",
              readFile(sandbox / "docs" / "DEBT_REGISTRY.md") & "\n<!-- hand edit drift -->\n")
    let snap = snapshotCloseTargets(sandbox)

    let res = runEngine(engine, sandbox, CloseSuccessArgs)
    check res.exitCode != 0
    check "Pre-validation FAILED" in res.output
    # Nothing was written — not even a "repair" of the drifted markdown.
    checkByteIdentical(sandbox, snap)
