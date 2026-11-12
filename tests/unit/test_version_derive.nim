import std/unittest
import std/options
import core/release/version_derive

suite "parseSemVer":
  test "accepts 0.4.12":
    let r = parseSemVer("0.4.12")
    check r.isSome
    check r.get() == SemVer(major: 0, minor: 4, patch: 12)

  test "accepts v0.4.12":
    let r = parseSemVer("v0.4.12")
    check r.isSome
    check r.get() == SemVer(major: 0, minor: 4, patch: 12)

  test "rejects v0.4":
    check parseSemVer("v0.4").isNone

  test "rejects 0.4.12.1":
    check parseSemVer("0.4.12.1").isNone

  test "rejects vX.Y.Z":
    check parseSemVer("vX.Y.Z").isNone

  test "rejects empty string":
    check parseSemVer("").isNone

  test "rejects v-1.0.0":
    check parseSemVer("v-1.0.0").isNone

  test "rejects 1.2.3-rc1":
    check parseSemVer("1.2.3-rc1").isNone

suite "classifyCommit":
  test "feat -> minor":
    check classifyCommit("feat: add widget") == bkMinor

  test "fix -> patch":
    check classifyCommit("fix: crash on null") == bkPatch

  test "perf -> patch":
    check classifyCommit("perf: speed up sort") == bkPatch

  test "refactor -> none":
    check classifyCommit("refactor: rename var") == bkNone

  test "docs -> none":
    check classifyCommit("docs: update readme") == bkNone

  test "test -> none":
    check classifyCommit("test: add coverage") == bkNone

  test "ci -> none":
    check classifyCommit("ci: fix pipeline") == bkNone

  test "build -> none":
    check classifyCommit("build: bump deps") == bkNone

  test "chore -> none":
    check classifyCommit("chore: cleanup") == bkNone

  test "revert -> none":
    check classifyCommit("revert: undo feat") == bkNone

  test "scope form feat(scope): x -> minor":
    check classifyCommit("feat(scope): x") == bkMinor

  test "scope form fix(a.b-c): x -> patch":
    check classifyCommit("fix(a.b-c): x") == bkPatch

  test "breaking feat!: x -> major":
    check classifyCommit("feat!: x") == bkMajor

  test "breaking fix(core)!: x -> major":
    check classifyCommit("fix(core)!: x") == bkMajor

  test "body BREAKING CHANGE footer -> major":
    check classifyCommit("feat: x", "BREAKING CHANGE: remove API") == bkMajor

  test "body BREAKING-CHANGE footer -> major":
    check classifyCommit("fix: x", "BREAKING-CHANGE: drop support") == bkMajor

  test "non-conventional plain text -> none":
    check classifyCommit("Add stuff") == bkNone

  test "non-conventional WIP: x -> none":
    check classifyCommit("WIP: x") == bkNone

  test "non-conventional merge: x -> none":
    check classifyCommit("merge: x") == bkNone

  test "non-conventional unknown(scope): x -> none":
    check classifyCommit("unknown(scope): x") == bkNone

  test "non-conventional feat x (no colon) -> none":
    check classifyCommit("feat x") == bkNone

suite "maxBump":
  test "precedence [none, patch, minor, major] -> major":
    check maxBump([bkNone, bkPatch, bkMinor, bkMajor]) == bkMajor

  test "[patch, patch] -> patch":
    check maxBump([bkPatch, bkPatch]) == bkPatch

  test "empty -> none":
    check maxBump([]) == bkNone

suite "bump":
  test "1.2.3 + major -> 2.0.0":
    check bump(SemVer(major: 1, minor: 2, patch: 3), bkMajor) == SemVer(major: 2, minor: 0, patch: 0)

  test "1.2.3 + minor -> 1.3.0":
    check bump(SemVer(major: 1, minor: 2, patch: 3), bkMinor) == SemVer(major: 1, minor: 3, patch: 0)

  test "1.2.3 + patch -> 1.2.4":
    check bump(SemVer(major: 1, minor: 2, patch: 3), bkPatch) == SemVer(major: 1, minor: 2, patch: 4)

  test "1.2.3 + none -> 1.2.3":
    check bump(SemVer(major: 1, minor: 2, patch: 3), bkNone) == SemVer(major: 1, minor: 2, patch: 3)

suite "deriveNextVersion":
  test "feat+fix from v0.4.12 -> doOk 0.5.0":
    let r = deriveNextVersion("v0.4.12", @["feat: a", "fix: b"])
    check r.outcome == doOk
    check r.version == SemVer(major: 0, minor: 5, patch: 0)
    check r.bumpKind == bkMinor

  test "chore+refactor from v0.4.12 -> doNoBump":
    let r = deriveNextVersion("v0.4.12", @["chore: a", "refactor: b"])
    check r.outcome == doNoBump

  test "fix from v0.4.12 -> doOk 0.4.13":
    let r = deriveNextVersion("v0.4.12", @["fix: a"])
    check r.outcome == doOk
    check r.version == SemVer(major: 0, minor: 4, patch: 13)
    check r.bumpKind == bkPatch

  test "chore with BREAKING CHANGE body -> doOk 1.0.0":
    let r = deriveNextVersion("v0.4.12", @["chore: a"], @["BREAKING CHANGE: x"])
    check r.outcome == doOk
    check r.version == SemVer(major: 1, minor: 0, patch: 0)
    check r.bumpKind == bkMajor

  test "garbage tag -> doBadTag":
    let r = deriveNextVersion("garbage", @["feat: a"])
    check r.outcome == doBadTag

  test "empty commits -> doNoBump":
    let r = deriveNextVersion("v0.4.12", @[])
    check r.outcome == doNoBump
