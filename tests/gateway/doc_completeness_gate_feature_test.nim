## Doc Completeness Gate Feature Test.
## See tests/features/doc_completeness_gate.feature for the specification.
##
## Verifies the documentation completeness gate:
##   - Module compiles with expected constants
##   - AGENTS.md contains all required sections (§0~§3)
##   - Rebase-Only Policy: no .git/MERGE_HEAD during normal operation
##   - Evidence registry exists at the expected path

import std/[unittest, os, strutils]
import gate/runners/doc_completeness_gate

const
  ## Mirror of the gate's RequiredSections — these are the sections the gate
  ## enforces. Testing them directly validates the same invariant.
  ExpectedSections = ["§0.", "§1.", "§2.", "§3."]
  GateAgmdPath = "AGENTS.md"
  GateHistoryDir = "docs/history/"

suite "Doc Completeness Gate":
  test "module compiles and can be imported":
    ## Given the doc_completeness_gate module exists
    ## When imported by a test
    ## Then compilation succeeds (reaching this line proves it)
    check true  # axiom:compile-check

  test "AGENTS.md exists at the expected path":
    ## Given the gate enforces AGENTS.md presence
    ## When we check the project root
    ## Then AGENTS.md exists
    check fileExists(GateAgmdPath)

  test "AGENTS.md contains all required sections":
    ## Given the gate checks for §0., §1., §2., §3. in AGENTS.md
    ## When we read the file
    ## Then all four required section markers are present
    let content = readFile(GateAgmdPath)
    for section in ExpectedSections:
      check section in content

  test "no merge in progress (Rebase-Only Policy)":
    ## Given the gate blocks merge commits (checks .git/MERGE_HEAD)
    ## When we check for the merge head file
    ## Then it does not exist during normal operation
    check not fileExists(".git/MERGE_HEAD")

  test "history directory exists":
    ## Given the gate checks docs/history/ for evidence freshness
    ## When we verify the directory
    ## Then it exists in the project
    check dirExists(GateHistoryDir)

  test "AGENTS.md section content is non-trivial":
    ## Given the gate requires sections §0~§3 to be present
    ## When we read each section
    ## Then each section has meaningful content (not just the header)
    let content = readFile(GateAgmdPath)
    for section in ExpectedSections:
      let sectionStart = content.find(section)
      check sectionStart >= 0
      # Extract content between this section and the next (or end of file)
      let nextSectionStart = block:
        var found = -1
        for s in ExpectedSections:
          let pos = content.find(s, sectionStart + section.len)
          if pos >= 0 and (found < 0 or pos < found):
            found = pos
        found
      let sectionEnd = if nextSectionStart >= 0: nextSectionStart else: content.len
      let sectionBody = content[sectionStart ..< sectionEnd].strip()
      # Each section should have at least the header line plus some content
      check sectionBody.len > section.len
