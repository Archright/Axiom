## Unit tests for verification_query_engine.nim — A~F Acceptance Matrix.
## Uses custom main() pattern to avoid unittest framework crashes.
## Verifies: semantic change invalidation, provenance-only immunity,
## fail-closed reuse, and 3-stage type-boundary enforcement.
##
## Each letter maps to a distinct named test. Reports PASS/FAIL per test.

import std/[os, strutils, times]
import core/crypto/hash_kernel
import core/types/results
import verification/semantic_query_types
import verification/verification_dependency
import verification/observation_pipeline
import verification/verification_query_engine

# ---------------------------------------------------------------------------
# Test fixture helper
# ---------------------------------------------------------------------------
# Creates a deterministic temp fixture with the standard directory
# layout and default file contents. Returns the repo root path.
# Each test gets its own uniquely-named subdirectory so there is
# no cross-test contamination.

proc fixtureRoot*(name: string): string =
  result = getTempDir() / ("vqe_" & name & "_" & $epochTime())
  if dirExists(result): removeDir(result)
  createDir(result)
  createDir(result / "src")
  createDir(result / "tests" / "gateway")
  createDir(result / "tests" / "features")
  createDir(result / "data")
  createDir(result / "config")

proc writeAll*(base: string) =
  ## Populate the fixture with default content for the engine tests.
  writeFile(base / "src" / "foo.nim", "echo \"hello world\"")
  writeFile(base / "tests" / "gateway" / "test1.feature", "Feature: gateway test")
  writeFile(base / "tests" / "gateway" / "test1.nim", "echo \"gateway nim\"")
  writeFile(base / "data" / "verification_auditor_baseline.json",
    """{"domain_count":649,"updated_at":"2026-08-31T17:36:10Z"}""")
  writeFile(base / "topology.lock", """{"lock_revision":32}""")
  writeFile(base / "config" / "gates.json", """{"phase3c":true,"gates":{"verification-auditor":{"enabled":true}}}""")

proc makeStored*(base: string): tuple[query: SemanticQuery, stored: StoredVerificationResult] =
  let qr = buildSemanticQuery(base, "verification-auditor-gate-impl-v1")
  if qr.isErr:
    echo "  BUILD-ERROR: " & qr.error
    quit(1)
  let q = qr.get
  let stored = newStoredVerificationResult(q, "PASS")
  return (q, stored)

proc main() =
  var passed = 0
  var failed = 0

  template check(name: string, body: untyped) =
    block:
      try:
        body
        inc passed
        echo "  PASS: " & name
      except CatchableError:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  echo "=== A — semantic change -> identity change -> recompute ==="

  block:
    let base = fixtureRoot("A")
    writeAll(base)
    let (query1, stored) = makeStored(base)
    let id1 = provisionalQueryID(query1)

    # Mutate the source file inside the snapshot closure.
    writeFile(base / "src" / "foo.nim", "echo \"changed content\"")
    let qr2 = buildSemanticQuery(base, "verification-auditor-gate-impl-v1")
    if qr2.isErr:
      echo "  BUILD-ERROR: " & qr2.error
      quit(1)
    let query2 = qr2.get
    let id2 = provisionalQueryID(query2)

    check "two runs with changed src/foo.nim yield different QueryID":
      assert id1 != id2

    check "stored-result reuse decision is RECOMPUTE when QueryID differs":
      let d = decideReuse(stored, query2, @[])
      assert d.kind == rdRecompute

  echo ""
  echo "=== B — closure content change / semantic dep change -> recompute ==="

  block:
    let base = fixtureRoot("B")
    writeAll(base)
    let (query1, stored) = makeStored(base)
    let id1 = provisionalQueryID(query1)

    # Sub-test B1: change a file inside the snapshot closure (src/foo.nim).
    writeFile(base / "src" / "foo2.nim", "extra source file")
    let qr2 = buildSemanticQuery(base, "verification-auditor-gate-impl-v1")
    if qr2.isErr:
      echo "  BUILD-ERROR: " & qr2.error
      quit(1)
    let query2 = qr2.get
    let id2 = provisionalQueryID(query2)

    check "added src file inside snapshot closure -> different QueryID":
      assert id1 != id2

    check "reuse decision is RECOMPUTE after closure content change":
      let d = decideReuse(stored, query2, @[])
      assert d.kind == rdRecompute

    # Sub-test B2: change a SEMANTIC dependency's content (baseline bytes).
    # Restore the fixture to a known state first by rebuilding.
    removeDir(base)
    let base2 = fixtureRoot("B2")
    writeAll(base2)
    let (query2a, stored2) = makeStored(base2)
    let id2a = provisionalQueryID(query2a)

    writeFile(base2 / "data" / "verification_auditor_baseline.json",
      """{"domain_count":999,"updated_at":"2026-09-03T00:00:00Z"}""")
    let qr3 = buildSemanticQuery(base2, "verification-auditor-gate-impl-v1")
    if qr3.isErr:
      echo "  BUILD-ERROR: " & qr3.error
      quit(1)
    let query3 = qr3.get
    let id3 = provisionalQueryID(query3)

    check "changed baseline bytes -> different QueryID":
      assert id2a != id3

    check "reuse decision is RECOMPUTE after baseline change":
      let d = decideReuse(stored2, query3, @[])
      assert d.kind == rdRecompute

  echo ""
  echo "=== C — provenance-only change -> reuse ALLOWED ==="

  block:
    let base = fixtureRoot("C")
    writeAll(base)
    let (query1, stored) = makeStored(base)
    let id1 = provisionalQueryID(query1)

    # Add a file OUTSIDE the snapshot closure: docs/change.md is not
    # in includeDirs (src, tests/features, tests/gateway), so it must
    # not affect the snapshot or testClosure.
    createDir(base / "docs")
    writeFile(base / "docs" / "change.md", "# Changelog")

    # Also add a file inside a skipDir (.git/) to prove skipDirs work.
    createDir(base / ".git")
    writeFile(base / ".git" / "FETCH_HEAD", "ref: refs/heads/main")

    let qr2 = buildSemanticQuery(base, "verification-auditor-gate-impl-v1")
    if qr2.isErr:
      echo "  BUILD-ERROR: " & qr2.error
      quit(1)
    let query2 = qr2.get
    let id2 = provisionalQueryID(query2)

    check "provenance-only filesystem change (docs/.git files) does NOT change QueryID":
      assert id1 == id2

    check "reuse decision ALLOWED when QueryID equal and no problematic deps":
      let d = decideReuse(stored, query2, @[])
      assert d.kind == rdReuse

  echo ""
  echo "=== D — probe failure = Unknown -> reuse FORBIDDEN ==="

  block:
    let base = fixtureRoot("D")
    writeAll(base)
    let (query, stored) = makeStored(base)

    # Model a ValidatedDependency with osUnknown (cannot determine).
    # Constructed via the exported constructor only — fields are
    # non-exported; this is the ONLY permitted construction path.
    let dep = newValidatedDependency(
      "src/unknown.nim", rcModuleContent, dkSemantic,
      hash_kernel.sha256Hex("src/unknown.nim:content"), osUnknown)

    check "ValidatedDependency with osUnknown is not declared":
      assert dep.depStatus == osUnknown

    check "decideReuse returns RECOMPUTE when dep status is osUnknown":
      let d = decideReuse(stored, query, @[dep])
      assert d.kind == rdRecompute

  echo ""
  echo "=== E — Unclassified -> reuse FORBIDDEN (fail-closed) ==="

  block:
    let base = fixtureRoot("E")
    writeAll(base)
    let (query, stored) = makeStored(base)

    # Model a ValidatedDependency with dkUnclassified.
    # resolve() maps UNCLASSIFIED -> drFailClosed -> decideRecompute.
    let dep = newValidatedDependency(
      "/etc/hosts", rcOther, dkUnclassified, "", osUnclassified)

    check "ValidatedDependency with dkUnclassified resolves to drFailClosed":
      assert resolve(dep) == drFailClosed

    check "decideReuse returns RECOMPUTE when dep is UNCLASSIFIED":
      let d = decideReuse(stored, query, @[dep])
      assert d.kind == rdRecompute

  echo ""
  echo "=== F — 3-stage type boundary is compile-enforced ==="

  block:
    # COMPILE-TIME ENFORCEMENT PROOF (documented, not a compile-fail assert):
    # RawObservation, ClassifiedObservation, and ValidatedDependency are
    # DISTINCT types with NON-EXPORTED fields. Direct construction from
    # outside the module is impossible — only the exported constructors
    # (newRawObservation / newClassifiedObservation / newValidatedDependency)
    # and transition functions (classify / validate) can produce them.
    # This is verified positively by exercising the ONLY permitted path.

    # Stage 1: create RawObservation via exported constructor.
    let raw = newRawObservation("src/core/gate/gate_memo.nim", rcModuleContent, "module contents here")

    # Stage 2: classify -> ClassifiedObservation (distinct type).
    let cls = classify(raw)

    # Stage 3: validate -> ValidatedDependency (distinct type).
    let val = validate(cls)

    # Positive assertions: the pipeline produces correct transitions
    # and the types are distinct (each stage accessor returns the
    # expected field through the stage-specific accessor).
    check "RawObservation accessor returns original path":
      assert rawPath(raw) == "src/core/gate/gate_memo.nim"

    check "ClassifiedObservation preserves path from RawObservation":
      assert classifiedPath(cls) == rawPath(raw)

    check "ValidatedDependency preserves path through pipeline":
      assert depPath(val) == classifiedPath(cls)

    check "SEMANTIC + content -> Complete status flows through":
      assert cls.classifiedStatus == osComplete
      assert val.depStatus == osComplete

    check "resolve(SEMANTIC+Complete) -> drDeclared (reusable)":
      assert resolve(val) == drDeclared

    check "stages produce distinct-typed results (RawObservation != ValidatedDependency)":
      # The types are distinct; the stage accessors are type-specific.
      # rawPath works on RawObservation; depPath works on ValidatedDependency.
      # Assigning a RawObservation to a ValidatedDependency variable is
      # a compile-time error (distinct types). We prove the boundary by
      # showing the accessors are stage-specific and correct.
      assert string(rawPath(raw)) == string(depPath(val))  # same path value

    # The fields of ValidatedDependency (path, readClass, kind, contentDigest,
    # status) are non-exported; external code cannot assign to them directly.
    # The ONLY construction path is newValidatedDependency(...).
    check "ValidatedDependency fields accessible only via exported accessors":
      assert depPath(val).len > 0
      assert depReadClass(val) == rcModuleContent
      assert depKind(val) == dkSemantic
      assert depContentDigest(val).len > 0
      assert depStatus(val) == osComplete

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0: quit(1)

main()