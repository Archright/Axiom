## core_purity_gate_test — judgment and fingerprint logic of the src/core
## purity ratchet, exercised against trap fixtures.
##
## The fixtures are ordinary compilable Nim modules; what makes them traps is
## their content — documented or banned tokens in strings and prose next to
## real offending code, and escape hatches on both sides of the approval line.

import std/[algorithm, os, sequtils, strutils, tables, tempfiles, unittest]
import tools/ci/core_purity_gate

const FixtureDir = currentSourcePath().parentDir() / ".." / "fixtures" / "core_purity"

proc scanFixture(name: string): seq[Violation] =
  scanModule(name, readFile(FixtureDir / name))

func ruleOf(violations: seq[Violation], r: Rule): seq[Violation] =
  for v in violations:
    if v.rule == r:
      result.add v

suite "core purity gate — clean module":
  test "a module with no side effect and no escape hatch is silent":
    check scanFixture("clean_module.nim") == []

suite "core purity gate — trap module":
  test "documentation and data mentioning banned tokens are not code":
    ## Lines 1-2 module doc, 7-8 const strings, 11 doc prose, 12-13 the
    ## contains/startsWith probe: every one of them spells a banned token.
    let hits = scanFixture("trap_module.nim")
    check hits.len == 2
    for v in hits:
      check v.line notin [1, 2, 7, 8, 11, 12, 13]

  test "the two real violations are the only findings":
    let hits = scanFixture("trap_module.nim")
    check hits.len == 2
    check hits[0].rule == rForbiddenEffect
    check hits[0].file == "trap_module.nim"
    check hits[0].line == 17
    check hits[0].detail == "forbidden effect: echo "
    check hits[1].rule == rIoPrimitive
    check hits[1].line == 18
    check hits[1].detail == "unapproved I/O primitive: writeFile("

suite "core purity gate — escape hatch approval":
  test "a cast carrying both a SEE annotation and an enclosing noSideEffect func passes":
    check scanFixture("cast_approved.nim") == []

  test "each unapproved cast names the condition it is missing":
    let hits = ruleOf(scanFixture("cast_unapproved.nim"), rEscapeHatch)
    check hits.len == 4
    check hits[0].detail == "cast(noSideEffect) escape hatch unapproved: " &
                            "no-nosideeffect-func-enclosing"          # enclosing routine is a template
    check hits[1].detail == "cast(noSideEffect) escape hatch unapproved: " &
                            "no-nosideeffect-func-enclosing"          # enclosing func lacks noSideEffect
    check hits[2].detail == "cast(noSideEffect) escape hatch unapproved: " &
                            "no-see-annotation"                        # func is declared, SEE is absent
    check hits[3].detail == "cast(noSideEffect) escape hatch unapproved: " &
                            "no-see-annotation+no-nosideeffect-func-enclosing"

suite "core purity gate — FFI bypass":
  test "only the importc declaration without effects is a bypass":
    let hits = scanFixture("ffi_module.nim")
    check hits.len == 1
    check hits[0].rule == rImportcBypass
    check hits[0].detail == "importc pragma bypasses the effect system"

suite "core purity gate — no source-level exemption":
  ## Correction 1: a `# axiomIoBoundary` marker is documentation, not a
  ## licence. A file carrying one is judged exactly like any other, so a new
  ## side effect in a declared file cannot pass silently.
  test "a file carrying the declaration line is still judged":
    let declared = """
# axiomIoBoundary
proc leaky(): void =
  echo "x"
  writeFile("a", "b")
"""
    let hits = scanModule("m.nim", declared)
    check ruleOf(hits, rForbiddenEffect).len == 1
    check ruleOf(hits, rIoPrimitive).len == 1

  test "the axiomIoBoundary() call form confers nothing either":
    let hits = scanModule("m.nim", "import api\naxiomIoBoundary(\"core\")\n" &
                                "proc leaky(): void =\n  echo \"x\"\n")
    check ruleOf(hits, rForbiddenEffect).len == 1

  test "a declared file and an undeclared file with the same code judge alike":
    ## Identity is (rule, file, detail) — the declaration line only shifts the
    ## reported line number, which is deliberately not part of the anchor.
    let body = "proc leaky(): void =\n  echo \"x\"\n  readFile(\"a\")\n"
    check scanModule("m.nim", "# axiomIoBoundary\n" & body)
            .mapIt(fingerprint(it)).sorted() ==
          scanModule("m.nim", body).mapIt(fingerprint(it)).sorted()

suite "core purity gate — count ratchet":
  ## Correction 2: the anchor is a permitted occurrence COUNT, not a
  ## membership bit. These are the mutation B/D regressions.
  const EchoDetail = "forbidden effect: echo "
  func echoAt(line: int): Violation =
    Violation(rule: rForbiddenEffect, file: "src/core/m.nim", line: line,
              detail: EchoDetail)

  test "a fingerprint observed more often than anchored is a regression":
    var anchors = initTable[string, int]()
    anchors[fingerprint(echoAt(1))] = 2
    let found = judge(@[echoAt(10), echoAt(20), echoAt(30)], anchors)
    check found.len == 1
    check found[0].observed == 3
    check found[0].anchored == 2
    check found[0].extraLines == @[30]

  test "adding one more copy of an already-anchored defect is caught":
    ## The exact shape of mutation B: the file already carried `echo` and the
    ## anchor covered it; one more copy must not be absorbed.
    var anchors = initTable[string, int]()
    anchors[fingerprint(echoAt(1))] = 6
    check judge(@[echoAt(1), echoAt(2), echoAt(3), echoAt(4), echoAt(5), echoAt(6)],
                anchors).len == 0
    check judge(@[echoAt(1), echoAt(2), echoAt(3), echoAt(4), echoAt(5), echoAt(6),
                 echoAt(7)], anchors).len == 1

  test "a fingerprint absent from the baseline is a regression":
    let anchors = initTable[string, int]()
    check judge(@[echoAt(1)], anchors).len == 1

  test "removing violations is always allowed":
    var anchors = initTable[string, int]()
    anchors[fingerprint(echoAt(1))] = 5
    check judge(@[echoAt(1), echoAt(2)], anchors).len == 0
    anchors[fingerprint(echoAt(1))] = 1
    check judge(@[], anchors).len == 0

  test "the reported excess is the occurrences past the anchor, in order":
    var anchors = initTable[string, int]()
    anchors[fingerprint(echoAt(1))] = 1
    let found = judge(@[echoAt(90), echoAt(10), echoAt(50)], anchors)
    check found.len == 1
    check found[0].extraLines == @[50, 90]

suite "core purity gate — tree and policy separation":
  ## Correction 3: `--tree` selects the payload; the baseline always comes
  ## from cwd, so judge+policy are the base and the payload is the head.
  test "a missing tree is indeterminate, never a clean pass":
    let (err, _) = resolveScanRoot("/nonexistent/_candidate", "/tmp")
    check err.len > 0

  test "a tree without the scanned root leaves the scan universe unclosed":
    let tmpRoot = createTempDir("axiom_core_purity_", "")
    defer: removeDir(tmpRoot)
    let (err, _) = resolveScanRoot(tmpRoot, tmpRoot)
    check err.len > 0

  test "an empty tree argument falls back to cwd":
    let (err, scanRoot) = resolveScanRoot("", getCurrentDir())
    check err.len == 0
    check scanRoot.endsWith(ScannedRoot)

  test "the resolved scan root is absolute and normalized":
    let (err, scanRoot) = resolveScanRoot(".", getCurrentDir())
    check err.len == 0
    check scanRoot.isAbsolute
    check ".." notin scanRoot

suite "core purity gate — code projection":
  test "string literals and trailing comments never reach the matcher":
    check stripCode("  echo \"hi\"  # echo again").strip == "echo"
    check stripCode("const s = \"echo \" & x").strip == "const s =  & x"
    check stripCode("## doc mentioning echo ").strip == ""
    check stripCode("  ## doc mentioning echo ").strip == ""
    check stripCode("  result = a # trailing").strip == "result = a"

suite "core purity gate — fingerprinting":
  test "a violation is anchored by rule, file and detail — never by line":
    let a = Violation(rule: rIoPrimitive, file: "src/core/x.nim", line: 10,
                      detail: "unapproved I/O primitive: readFile(")
    let b = Violation(rule: rIoPrimitive, file: "src/core/x.nim", line: 999,
                      detail: "unapproved I/O primitive: readFile(")
    check fingerprint(a) == fingerprint(b)

  test "rule, file and detail each change the fingerprint":
    let base = Violation(rule: rIoPrimitive, file: "src/core/x.nim", line: 10,
                         detail: "unapproved I/O primitive: readFile(")
    var other = base
    other.rule = rForbiddenEffect
    check fingerprint(other) != fingerprint(base)
    other = base
    other.file = "src/core/y.nim"
    check fingerprint(other) != fingerprint(base)
    other = base
    other.detail = "unapproved I/O primitive: writeFile("
    check fingerprint(other) != fingerprint(base)

  test "an absolute checkout path cannot reach the fingerprint":
    let a = Violation(rule: rIoPrimitive, file: "src/core/x.nim", line: 1, detail: "d")
    let b = Violation(rule: rIoPrimitive, file: "src/core\\x.nim", line: 1, detail: "d")
    check fingerprint(a) == fingerprint(b)

  test "line and column numbers are normalized out of the detail":
    ## Both arities collapse to one marker, so the same defect anchors once.
    check normalizeDetail("src/core/x.nim:42:7: boom") == "src/core/x.nim:: boom"
    check normalizeDetail("src/core/x.nim:42: boom") == "src/core/x.nim:: boom"
    check normalizeDetail("src/core/x.nim:42:7 boom") == "src/core/x.nim:: boom"
    check normalizeDetail("src/core/x.nim:42") == "src/core/x.nim::"
    check normalizeDetail("no path here:42: boom") == "no path here:42: boom"

  test "fingerprinting is stable and order-independent":
    var first = scanFixture("cast_unapproved.nim").mapIt(fingerprint(it)).sorted()
    var second = scanFixture("cast_unapproved.nim").mapIt(fingerprint(it)).sorted()
    check first == second
    check first.len == 4