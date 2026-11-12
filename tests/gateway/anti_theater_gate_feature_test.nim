{.push raises: [CatchableError].}

## Anti-Theater Gate Feature Test.
## See tests/features/anti_theater.feature for the specification.
##
## Unit-tests the pure detection functions exported by anti_theater_gate.nim.
## Tests diff parsing, rule matching, and tag exemption logic.

import std/[unittest, os]
import gate/runners/anti_theater_gate

suite "Anti-Theater Gate — parseDiff":
  test "parses added lines from git diff output":
    let diff = """
diff --git a/src/foo.nim b/src/foo.nim
index abc..def 100644
--- a/src/foo.nim
+++ b/src/foo.nim
@@ -1,3 +1,4 @@
 proc main() =
   try:
     dangerousOp()
+  except CatchableError:
+    discard
"""
    let files = parseDiff(diff)
    check files.len == 1
    check files[0].fileName == "src/foo.nim"
    check files[0].lines.len == 2

  test "handles empty diff":
    let files = parseDiff("")
    check files.len == 0

  test "skips context lines":
    let diff = """
+++ b/src/bar.nim
 context
+added
"""
    let files = parseDiff(diff)
    check files.len == 1
    check files[0].lines.len == 1

suite "Anti-Theater Gate — Rule A (S2: except: discard)":
  test "detects same-line except: discard":
    let df = DiffFile(fileName: "src/mod.nim", lines: @["+  except: discard"])
    let v = checkRuleA(@[df])
    check v.len == 1
    check v[0].rule == "S2"

  test "detects same-line except CatchableError: discard":
    let df = DiffFile(fileName: "src/mod.nim", lines: @["+  except CatchableError: discard"])
    let v = checkRuleA(@[df])
    check v.len == 1

  test "detects multi-line except: discard":
    let df = DiffFile(fileName: "src/mod.nim", lines: @["+  except:", "+    discard"])
    let v = checkRuleA(@[df])
    check v.len == 1

  test "exempts tagged same-line discard":
    let df = DiffFile(fileName: "src/mod.nim", lines: @["+  except: discard # axiom:best-effort(refactor pending)"])
    let v = checkRuleA(@[df])
    check v.len == 0

  test "exempts multi-line with tag on except line":
    let df = DiffFile(fileName: "src/mod.nim", lines: @["+  except: # axiom:best-effort(refactor)", "+    discard"])
    let v = checkRuleA(@[df])
    check v.len == 0

  test "exempts multi-line with tag on discard line":
    let df = DiffFile(fileName: "src/mod.nim", lines: @["+  except:", "+    discard # axiom:best-effort(refactor)"])
    let v = checkRuleA(@[df])
    check v.len == 0

  test "skips files outside src/ and tools/":
    let df = DiffFile(fileName: "tests/mod.nim", lines: @["+  except: discard"])
    let v = checkRuleA(@[df])
    check v.len == 0

  test "ignores non-Nim files":
    let df = DiffFile(fileName: "src/mod.py", lines: @["+  except: discard"])
    let v = checkRuleA(@[df])
    check v.len == 0

suite "Anti-Theater Gate — Rule B (S1: check true stub)":
  test "detects check true":
    let df = DiffFile(fileName: "tests/test_mod.nim", lines: @["+  check true"])
    let v = checkRuleB(@[df])
    check v.len == 1
    check v[0].rule == "S1"

  test "detects doAssert true":
    let df = DiffFile(fileName: "tests/test_mod.nim", lines: @["+  doAssert true"])
    let v = checkRuleB(@[df])
    check v.len == 1

  test "detects assert true":
    let df = DiffFile(fileName: "tests/test_mod.nim", lines: @["+  assert true"])
    let v = checkRuleB(@[df])
    check v.len == 1

  test "exempts tagged check true":
    let df = DiffFile(fileName: "tests/test_mod.nim", lines: @["+  check true # axiom:compile-check"])
    let v = checkRuleB(@[df])
    check v.len == 0

  test "exempts with tag on previous line":
    let df = DiffFile(fileName: "tests/test_mod.nim", lines: @["+  # axiom:compile-check", "+  check true"])
    let v = checkRuleB(@[df])
    check v.len == 0

  test "skips files outside tests/":
    let df = DiffFile(fileName: "src/test_mod.nim", lines: @["+  check true"])
    let v = checkRuleB(@[df])
    check v.len == 0

  test "does not flag substantive assertion":
    let df = DiffFile(fileName: "tests/test_mod.nim", lines: @["+  check x == 5"])
    let v = checkRuleB(@[df])
    check v.len == 0

suite "Anti-Theater Gate — Rule C (|| true in CI files)":
  test "detects || true in Makefile":
    let df = DiffFile(fileName: "Makefile", lines: @["+  command || true"])
    let v = checkRuleC(@[df])
    check v.len == 1
    check v[0].rule == "C"

  test "detects || true in .mk file":
    let df = DiffFile(fileName: "build.mk", lines: @["+  command || true"])
    let v = checkRuleC(@[df])
    check v.len == 1

  test "detects || true in .circleci config":
    let df = DiffFile(fileName: ".circleci/config.yml", lines: @["+  command || true"])
    let v = checkRuleC(@[df])
    check v.len == 1

  test "detects || rm -rf in Makefile":
    let df = DiffFile(fileName: "Makefile", lines: @["+  command || rm -rf build/x"])
    let v = checkRuleC(@[df])
    check v.len == 1
    check v[0].rule == "C"

  test "detects || echo in Makefile":
    let df = DiffFile(fileName: "Makefile", lines: @["+  command || echo done"])
    let v = checkRuleC(@[df])
    check v.len == 1
    check v[0].rule == "C"

  test "detects || : in Makefile":
    let df = DiffFile(fileName: "Makefile", lines: @["+  command || :"])
    let v = checkRuleC(@[df])
    check v.len == 1
    check v[0].rule == "C"

  test "does not flag || exit 1 in Makefile (fail-closed)":
    let df = DiffFile(fileName: "Makefile", lines: @["+  command || exit 1"])
    let v = checkRuleC(@[df])
    check v.len == 0

  test "does not flag || exit $? in Makefile (fail-closed)":
    let df = DiffFile(fileName: "Makefile", lines: @["+  command || exit $?"])
    let v = checkRuleC(@[df])
    check v.len == 0

  test "exempts tagged || true":
    let df = DiffFile(fileName: "Makefile", lines: @["+  command || true # axiom:best-effort(exit ignored intentionally)"])
    let v = checkRuleC(@[df])
    check v.len == 0

  test "exempts with tag on previous line":
    let df = DiffFile(fileName: "Makefile", lines: @["+  # axiom:best-effort(exit ignored)", "+  command || true"])
    let v = checkRuleC(@[df])
    check v.len == 0

  test "ignores non-CI files":
    let df = DiffFile(fileName: "src/main.nim", lines: @["+  command || true"])
    let v = checkRuleC(@[df])
    check v.len == 0

  test "detects || true in .github/workflows/ YAML":
    let df = DiffFile(fileName: ".github/workflows/ci.yml", lines: @["+  command || true"])
    let v = checkRuleC(@[df])
    check v.len == 1
    check v[0].rule == "C"

  test "detects || true in .github/actions/ YAML":
    let df = DiffFile(fileName: ".github/actions/action.yml", lines: @["+  command || true"])
    let v = checkRuleC(@[df])
    check v.len == 1
    check v[0].rule == "C"

  test "detects || rm -rf in .github/workflows/ YAML":
    let df = DiffFile(fileName: ".github/workflows/cleanup.yml", lines: @["+  command || rm -rf build/"])
    let v = checkRuleC(@[df])
    check v.len == 1
    check v[0].rule == "C"

  test "does not flag || exit 1 in .github/workflows/ YAML (fail-closed)":
    let df = DiffFile(fileName: ".github/workflows/ci.yml", lines: @["+  command || exit 1"])
    let v = checkRuleC(@[df])
    check v.len == 0

  test "non-CI file with || rm -rf is not flagged":
    let df = DiffFile(fileName: "src/main.nim", lines: @["+  command || rm -rf build/x"])
    let v = checkRuleC(@[df])
    check v.len == 0

suite "Anti-Theater Gate — hasFailOpenSwallow":
  test "detects || true":
    check hasFailOpenSwallow("command || true")
  test "detects || true with comment":
    check hasFailOpenSwallow("command || true # comment")
  test "detects || :":
    check hasFailOpenSwallow("command || :")
  test "detects || rm -rf":
    check hasFailOpenSwallow("command || rm -rf build/x")
  test "detects || rm with path":
    check hasFailOpenSwallow("command || rm /tmp/file")
  test "detects || echo":
    check hasFailOpenSwallow("command || echo done")
  test "detects || echo with message":
    check hasFailOpenSwallow("command || echo 'build complete'")
  test "does not flag || exit 1":
    check not hasFailOpenSwallow("command || exit 1")
  test "does not flag || exit $?":
    check not hasFailOpenSwallow("command || exit $?")
  test "does not flag || exit 0":
    check not hasFailOpenSwallow("command || exit 0")
  test "no pipe at all":
    check not hasFailOpenSwallow("command")
  test "single pipe with no RHS":
    check not hasFailOpenSwallow("command ||")

suite "Anti-Theater Gate — edge cases":
  test "empty files list passes clean":
    let v = runAllChecks(@[])
    check v.len == 0

  test "tag detection works on standalone line":
    check hasTag("# axiom:best-effort(test)", "axiom:best-effort(")
    check not hasTag("discard", "axiom:best-effort(")
    check hasTag("# axiom:compile-check", "axiom:compile-check")

  test "matchesSrcOrToolsNim":
    check matchesSrcOrToolsNim("src/core/types.nim")
    check matchesSrcOrToolsNim("tools/build.nim")
    check not matchesSrcOrToolsNim("tests/test.nim")
    check not matchesSrcOrToolsNim("src/core/types.py")

  test "matchesTestNim":
    check matchesTestNim("tests/test_mod.nim")
    check not matchesTestNim("src/core/test_mod.nim")
    check not matchesTestNim("tests/test_mod.py")

  test "matchesCIFile":
    check matchesCIFile("Makefile")
    check matchesCIFile("build.mk")
    check matchesCIFile("rules.mk")
    check matchesCIFile(".circleci/config.yml")
    check matchesCIFile(".github/workflows/ci.yml")
    check matchesCIFile(".github/workflows/ci.yaml")
    check matchesCIFile(".github/actions/action.yml")
    check matchesCIFile(".github/actions/action.yaml")
    check not matchesCIFile("src/main.nim")
    check not matchesCIFile("Makefile.bak")
