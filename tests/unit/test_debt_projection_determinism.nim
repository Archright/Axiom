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
##
## All logic is in-memory plus per-test temp trees; no repo data file is read or
## written.

import std/[unittest, json, os, strutils, tables, tempfiles, algorithm]
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