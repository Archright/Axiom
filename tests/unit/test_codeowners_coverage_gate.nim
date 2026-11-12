## Unit tests for tools/codeowners_coverage_gate.nim — the mechanical
## CODEOWNERS coverage gate for the auto-merge trust surface. Covers the
## pure core: CODEOWNERS parsing, CODEOWNERS pattern semantics (anchored
## patterns, trailing '/', '/**', '*'), coverage judgment (covered+right
## owner PASS, uncovered FAIL, wrong-owner FAIL), the CODEOWNERS-itself
## self-protection target, the textual TrustSurfaceTombstones const
## extraction (compile-decoupled from src/cli/merge_cli.nim), the
## merge_admission.json trustSurface reader, and the target-set union/dedup.
##
## No network access; no repo files are read (synthetic fixtures only).
##
## Run from repo root:
##   nim c -r --hints:off --nimcache:/tmp/nimc_co_gate \
##       tests/unit/test_codeowners_coverage_gate.nim

import std/[json, unittest, strutils]
import ../../tools/codeowners_coverage_gate

suite "parseCodeowners":
  test "skips comments and blank lines, parses pattern + owners":
    let rules = parseCodeowners("""
# header comment
/templates/                       @Archright/architect  @some-team

/src/core/domain_types.nim         @Archright/architect
/Makefile                          @Archright/architect  # trailing note
""")
    check rules.len == 3
    check rules[0].pattern == "/templates/"
    check rules[0].owners == @["@Archright/architect", "@some-team"]
    check rules[1].pattern == "/src/core/domain_types.nim"
    check rules[1].owners == @["@Archright/architect"]
    check rules[2].pattern == "/Makefile"
    check rules[2].owners == @["@Archright/architect"]

  test "owner-less line is ignored (GitHub treats it as invalid)":
    let rules = parseCodeowners("/orphan\n/ok  @Archright/architect\n")
    check rules.len == 1
    check rules[0].pattern == "/ok"

suite "codeownersPatternMatches":
  test "plain pattern matches exact path and children":
    check codeownersPatternMatches("/Makefile", "Makefile")
    check codeownersPatternMatches("/src/cli/merge_cli.nim", "src/cli/merge_cli.nim")
    check codeownersPatternMatches("/src/cli/merge_cli.nim", "src/cli/merge_cli.nim/x")
    check not codeownersPatternMatches("/Makefile", "Makefile2")
    check not codeownersPatternMatches("/src/cli/merge_cli.nim", "src/cli/merge_other.nim")

  test "trailing slash is a directory prefix":
    check codeownersPatternMatches("/templates/", "templates")
    check codeownersPatternMatches("/templates/", "templates/page.html")
    check codeownersPatternMatches("/templates/", "templates/x/y/z.html")
    check not codeownersPatternMatches("/templates/", "template/page.html")
    check not codeownersPatternMatches("/templates/", "src/templates/page.html")

  test "double-star suffix covers the prefix directory":
    check codeownersPatternMatches("/a/b/**", "a/b")
    check codeownersPatternMatches("/a/b/**", "a/b/c")
    check codeownersPatternMatches("/a/b/**", "a/b/c/d/e")
    check not codeownersPatternMatches("/a/b/**", "a/c")

  test "star matches within a run, never across '/'":
    check codeownersPatternMatches("/*.nim", "main.nim")
    check not codeownersPatternMatches("/*.nim", "src/main.nim")
    check codeownersPatternMatches("/tools/*.nim", "tools/example.nim")
    check not codeownersPatternMatches("/tools/*.nim", "tools/sub/deep.nim")
    check codeownersPatternMatches("/ax*", "ax")
    check not codeownersPatternMatches("/ax*", "bx")

suite "assessCoverage":
  let rules = parseCodeowners("""
/.github/                          @Archright/architect
/AGENTS.md                         @Archright/architect
/src/cli/merge_cli.nim             @Archright/architect
""")

  test "covered + right owner PASS":
    let v = assessCoverage(rules, @["AGENTS.md", ".github/CODEOWNERS",
                                   "src/cli/merge_cli.nim"])
    check v.pass
    check v.checked == 3
    check v.problems.len == 0

  test "uncovered target FAIL":
    let v = assessCoverage(rules, @["config/policy/merge_admission.json"])
    check not v.pass
    check v.problems.len == 1
    check v.problems[0].startsWith("UNCOVERED config/policy/merge_admission.json")

  test "wrong-owner covering rule FAIL":
    let bad = parseCodeowners("/src/cli/merge_cli.nim  @Other/team")
    let v = assessCoverage(bad, @["src/cli/merge_cli.nim"])
    check not v.pass
    check v.problems.len == 1
    check v.problems[0].startsWith("WRONG_OWNER src/cli/merge_cli.nim")

  test "every covering rule must list the owner (multi-rule path)":
    let multi = parseCodeowners("""
/src/cli/                          @Archright/architect
/src/cli/merge_cli.nim             @Archright/architect
""")
    check assessCoverage(multi, @["src/cli/merge_cli.nim"]).pass
    let multi2 = parseCodeowners("""
/src/cli/                          @Archright/architect
/src/cli/merge_cli.nim             @Flash/team
""")
    check not assessCoverage(multi2, @["src/cli/merge_cli.nim"]).pass

  test "CODEOWNERS itself is a self-protection target":
    let v = assessCoverage(rules, @[".github/CODEOWNERS"])
    check v.pass
    check ".github/CODEOWNERS" in buildTargetSet(@[], @[])

  test "ownersInclude is case-insensitive":
    let r = OwnerRule(pattern: "/x", owners: @["@archright/architect"])
    check ownersInclude(r, "@Archright/architect")
    check not ownersInclude(r, "@Other/team")

suite "extractTrustSurfaceTombstones (textual, no import)":
  test "extracts the const array literal strings":
    let src = """
  ## some comment mentioning TrustSurfaceTombstones in prose
  TrustSurfaceTombstones*: seq[string] = @[
    ".github/workflows/auto_merge.yml",
    "src/cli/merge_cli.nim",
    ".github/actions/canonical-bootstrap/**",
  ]
"""
    let entries = extractTrustSurfaceTombstones(src)
    check entries == @[".github/workflows/auto_merge.yml",
                       "src/cli/merge_cli.nim",
                       ".github/actions/canonical-bootstrap/**"]

  test "protection-retention entries are included by construction":
    let src = "TrustSurfaceTombstones*: seq[string] = @[\n  \"config/policy/merge_admission.json\",\n]"
    check extractTrustSurfaceTombstones(src) == @["config/policy/merge_admission.json"]

  test "missing declaration returns empty (fail-closed caller)":
    check extractTrustSurfaceTombstones("TrustSurfaceTombstones = 1").len == 0
    check extractTrustSurfaceTombstones("").len == 0
    check extractTrustSurfaceTombstones(
      "TrustSurfaceTombstones*: seq[string] = @[\n]").len == 0

  test "the removed live-surface decl does not satisfy the gate (fail-closed)":
    ## Since the policy-SSOT single-sourcing the live surface must not be
    ## compiled back into merge_cli.nim; the old `TrustSurface` literal does
    ## not match the tombstones regex, so the gate FAILs if it reappears.
    check extractTrustSurfaceTombstones(
      "TrustSurface*: seq[string] = @[\n  \"src/cli/merge_cli.nim\",\n]").len == 0

suite "jsonTrustSurface":
  test "reads the array; missing/invalid -> ok=false":
    let good = parseJson("""{"trustSurface": ["a", "b"]}""")
    let (entries, ok) = jsonTrustSurface(good)
    check ok
    check entries == @["a", "b"]
    let (e2, ok2) = jsonTrustSurface(parseJson("""{"other": 1}"""))
    check not ok2
    check e2.len == 0
    let (e3, ok3) = jsonTrustSurface(parseJson("""{"trustSurface": "not-array"}"""))
    check not ok3

suite "buildTargetSet":
  test "union, order-preserving, dedup, fixed additions appended":
    let targets = buildTargetSet(@["x", "y"], @["y", "z"])
    check targets == @["x", "y", "z", "AGENTS.md", ".github/CODEOWNERS"]
    check targets.len == 5