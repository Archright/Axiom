## Unit tests for the `ax debt sync` hash-drift check (hashDriftIds, DEBT#543).
##
## Verifies both directions of the like-for-like comparison contract
## (docs/spec/debt_registry_schema.md §6):
##  (a) an entry written per the §6 convention does NOT drift — whole-artifact
##      digest, raw line-range digest, trimmed line-range digest, and
##      suffixed/annotated/multi-segment reference forms all resolve
##  (b) a tampered file DOES drift — for both anchor flavors
##  (c) a digest stored in a convention nobody writes (the old composite
##      whole-file formula) drifts — the check never silently passes

import std/[unittest, json, os, strutils]
import checksums/sha2
import cli/debt_cli

proc sha(s: string): string =
  "sha256:" & $Sha_256.secureHash(s)

proc shaFile(path: string): string =
  "sha256:" & $Sha_256.secureHash(readFile(path))

proc mkEntry(id: string; files: seq[string]; lineRange: string;
             contentHash: string): JsonNode =
  %*{
    "id": id,
    "category": "Correctness/Structural Constraint",
    "description": "fixture",
    "files": files,
    "lineRange": lineRange,
    "contentHash": contentHash
  }

const tmpDir = getTempDir() / "axiom_debt_hash_drift_test"

proc writeFixture(name: string; content: string): string =
  createDir(tmpDir)
  let path = tmpDir / name
  writeFile(path, content)
  path

suite "hashDriftIds like-for-like comparison (DEBT#543)":
  setup:
    createDir(tmpDir)

  teardown:
    if dirExists(tmpDir):
      removeDir(tmpDir)

  test "(a1) whole-artifact anchor does not drift":
    let f = writeFixture("whole.nim", "proc a() =\n  discard\nproc b() =\n  discard\n")
    let e = mkEntry("DEBT-TEST#1", @[f], f & ":1-4", shaFile(f))
    check hashDriftIds(%[e]).len == 0

  test "(a2) raw line-range anchor with suffixed files ref does not drift":
    let f = writeFixture("range.nim", "proc a() =\n  echo 1\nproc b() =\n  echo 2\n")
    let body = readFile(f).splitLines()[1 .. 2].join("\n")
    let e = mkEntry("DEBT-TEST#2", @[f & ":2-3"], f & ":2-3", sha(body))
    check hashDriftIds(%[e]).len == 0

  test "(a3) trimmed line-range anchor does not drift":
    let f = writeFixture("trim.nim", "proc a() =\n  echo 1\nproc b() =\n  echo 2\n")
    let body = readFile(f).splitLines()[1 .. 2].join("\n").strip()
    let e = mkEntry("DEBT-TEST#3", @[f], f & ":2-3", sha(body))
    check hashDriftIds(%[e]).len == 0

  test "(a4) annotated and multi-segment references resolve":
    # Annotation in parens is stripped; one matching segment suffices.
    let f = writeFixture("annot.nim", "proc a() =\n  echo 1\nproc b() =\n  echo 2\n")
    let body = readFile(f).splitLines()[1 .. 2].join("\n")
    let e = mkEntry("DEBT-TEST#4", @[f],
                    f & ":2-3 (body); " & f & ":4-9 (REMOVED)", sha(body))
    check hashDriftIds(%[e]).len == 0

  test "(a5) single-line and comma sub-range specs resolve":
    let f = writeFixture("comma.nim", "proc a() =\n  echo 1\nproc b() =\n  echo 2\nproc c() =\n  echo 3\n")
    let line2 = readFile(f).splitLines()[1]
    let e = mkEntry("DEBT-TEST#5", @[f], f & ":2", sha(line2))
    check hashDriftIds(%[e]).len == 0
    # Each comma sub-range anchors its own region (§6 "exact line/line-range
    # content"); a stored digest of one region verifies via that region.
    let e2 = mkEntry("DEBT-TEST#6", @[f & ":2,5"], f & ":2,5", sha(line2))
    check hashDriftIds(%[e2]).len == 0
    # A digest joining two regions is not a written convention — it drifts.
    let joined = line2 & "\n" & readFile(f).splitLines()[4]
    let e3 = mkEntry("DEBT-TEST#6b", @[f & ":2,5"], f & ":2,5", sha(joined))
    check hashDriftIds(%[e3]) == @["DEBT-TEST#6b"]

  test "(b1) tampered file drifts (whole-artifact anchor)":
    let f = writeFixture("tamper1.nim", "proc a() =\n  discard\n")
    let e = mkEntry("DEBT-TEST#7", @[f], f & ":1-2", shaFile(f))
    check hashDriftIds(%[e]).len == 0
    writeFile(f, "proc a() =\n  echo \"tampered\"\n")
    check hashDriftIds(%[e]) == @["DEBT-TEST#7"]

  test "(b2) tampered anchored region drifts (line-range anchor)":
    let f = writeFixture("tamper2.nim", "proc a() =\n  echo 1\nproc b() =\n  echo 2\n")
    let body = readFile(f).splitLines()[1 .. 2].join("\n")
    let e = mkEntry("DEBT-TEST#8", @[f & ":2-3"], f & ":2-3", sha(body))
    check hashDriftIds(%[e]).len == 0
    writeFile(f, "proc a() =\n  echo 999\nproc b() =\n  echo 2\n")
    check hashDriftIds(%[e]) == @["DEBT-TEST#8"]

  test "(c) composite whole-file convention (the pre-fix expectation) drifts":
    let f = writeFixture("composite.nim", "proc a() =\n  discard\n")
    # The convention hashDriftIds used before DEBT#543 — never written by any
    # registry writer. A stored digest of that shape must not pass the check.
    let composite = "sha256:" & $Sha_256.secureHash(
      "sha256:" & $Sha_256.secureHash(readFile(f)) & "\x02" & f)
    let e = mkEntry("DEBT-TEST#9", @[f], f & ":1-2", composite)
    check hashDriftIds(%[e]) == @["DEBT-TEST#9"]

  test "entries without resolvable references stay out of scope":
    let e = mkEntry("DEBT-TEST#10", @["does/not/exist.nim:1-2"],
                    "does/not/exist.nim:1-2", "sha256:" & repeat('a', 64))
    check hashDriftIds(%[e]).len == 0

  test "entries without contentHash but with resolvable refs drift":
    let f = writeFixture("nohash.nim", "proc a() =\n  discard\n")
    var e = mkEntry("DEBT-TEST#11", @[f], f & ":1-2", "")
    check hashDriftIds(%[e]) == @["DEBT-TEST#11"]
