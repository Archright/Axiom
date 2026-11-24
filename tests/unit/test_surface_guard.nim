## Unit tests for tools/surface_guard.nim — deterministic repository-surface
## guard. Covers the frozen interface contract: class x op decision table,
## rename/copy/typechange semantics, determinism, fail-closed behavior, glob
## semantics, resolution order, and checkClosure.
##
## v2 additions: structural validation (unknown keys in classes/rules/op
## rules, defaultClass domain, resolutionOrder exactness, selfAmendment
## shape, exact double registration), two-sided rename judgment (old path
## judged with op DELETE), and the selfAmendment exception contract
## (conditions a-d, one miss leaves the FAIL standing).
##
## v3 additions (DEBT#545): frozenExceptions must register every exact
## PRODUCT/CONTROLLED pattern that a FROZEN pattern also matches, reject
## unregistered conflicts, dead exceptions, wildcard registrations, and
## groups without rationale/approvedBy; the shipped policy must stay valid
## and keep its FROZEN intent.
##
## v4 additions: the shipped-policy assertions are SEMANTIC, not pinned
## literals. v3 asserted `len == 109` and `policyVersion == 102`; both went
## stale the moment the policy was revised (actual: 116 / 108), so the file
## was red while proving nothing. The registry is now compared against a set
## recomputed from the policy itself — the exact PRODUCT/CONTROLLED
## registrations that a FROZEN glob would otherwise catch — and policyVersion
## is checked for the properties that matter (positive integer, echoed by
## every entry point, recorded in the changelog) rather than for a number.
## A back-ported `116`/`108` would have been the same defect one revision
## later. v4 also pins the abuse vectors of the selfAmendment exception: the
## allow-list is read from the BASE policy, matched exactly, and applied
## all-or-nothing, so a head policy cannot widen its own lane.
##
## Hermetic: only std/[json, unittest, strutils] plus the guard module. The
## sole filesystem read is the guard's own loadPolicy() boundary.
##
## Run from repo root (project config is skipped so the build needs no
## bin/ax or nimble path):
##   nim c -r --hints:off --skipParentCfg --skipProjCfg --skipUserCfg \
##     --noNimblePath --nimcache:build/nimcache/tsg -o:build/tsg \
##     tests/unit/test_surface_guard.nim

import std/[json, unittest, strutils]
import ../../tools/surface_guard

const SHIPPED_POLICY = "config/repository_surface.json"

proc frozenOnlyView(policy: JsonNode): JsonNode =
  ## Copy of `policy` with PRODUCT/CONTROLLED emptied and a non-FROZEN
  ## defaultClass, so the guard's own glob engine answers exactly one
  ## question: "would a FROZEN pattern catch this path if no earlier
  ## registration shadowed it?" Used to recompute the exception set instead
  ## of trusting frozenExceptions to describe itself.
  result = parseJson($policy)
  result["classes"]["PRODUCT"] = newJArray()
  result["classes"]["CONTROLLED"] = newJArray()
  result["defaultClass"] = %"PRODUCT"

proc shadowedExceptionSet(policy: JsonNode): seq[string] =
  ## The registry the policy OUGHT to carry, derived only from `classes`:
  ## every exact (wildcard-free) PRODUCT/CONTROLLED registration that a
  ## FROZEN pattern also matches. Duplicate-free, declaration order.
  let probe = frozenOnlyView(policy)
  for cls in ["PRODUCT", "CONTROLLED"]:
    for entry in policy["classes"][cls].items:
      let path = entry.getStr()
      if '*' in path:
        continue
      if resolveClass(probe, path) == "FROZEN" and path notin result:
        result.add(path)

let POLICY = parseJson("""
{
  "schemaVersion": 1,
  "policyVersion": 7,
  "classes": {
    "PRODUCT": ["src/**", "Makefile"],
    "CONTROLLED": ["tools/**", "config/**"],
    "FROZEN": ["**"]
  },
  "defaultClass": "FROZEN",
  "rules": {
    "PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
    "CONTROLLED": {"ADD": "FAIL", "MODIFY": "PASS", "DELETE": "PASS"},
    "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "PASS"}
  },
  "frozenExceptions": {
    "schema": "axiom.repository-surface-frozen-exceptions.v1",
    "groups": {"fixture": {"rationale": "PRODUCT carve-out under the FROZEN catch-all", "approvedBy": "unit-test"}},
    "paths": {"Makefile": "fixture"}
  }
}
""")

suite "3 classes x {ADD, MODIFY, DELETE}":
  test "PRODUCT: ADD/MODIFY/DELETE all PASS":
    let recs = @[
      ChangeRecord(status: 'A', path: "src/lib/a.nim"),
      ChangeRecord(status: 'M', path: "src/lib/b.nim"),
      ChangeRecord(status: 'D', path: "src/lib/c.nim")]
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "PASS"
    check v["reasonCode"].getStr() == "OK"
    check v["changeCount"].getInt() == 3
    check v["violations"].len == 0
    check v["summary"]["add"].getInt() == 1
    check v["summary"]["modify"].getInt() == 1
    check v["summary"]["delete"].getInt() == 1
    check v["summary"]["rename"].getInt() == 0
    check v["summary"]["other"].getInt() == 0
    check v["binding"].getStr() == "base"
    check v["policyVersion"].getInt() == 7
    echo "  [product] ADD/MODIFY/DELETE all PASS"

  test "CONTROLLED: ADD FAIL, MODIFY PASS, DELETE PASS":
    let recs = @[
      ChangeRecord(status: 'A', path: "tools/new_tool.nim"),
      ChangeRecord(status: 'M', path: "tools/existing.nim"),
      ChangeRecord(status: 'D', path: "tools/removed.nim")]
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["violations"].len == 1
    let vio = v["violations"][0]
    check vio["path"].getStr() == "tools/new_tool.nim"
    check vio["status"].getStr() == "A"
    check vio["changeClass"].getStr() == "CONTROLLED"
    check vio["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    echo "  [controlled] ADD blocked, MODIFY/DELETE allowed"

  test "FROZEN: ADD/MODIFY FAIL, DELETE PASS":
    let recs = @[
      ChangeRecord(status: 'A', path: "data/new.json"),
      ChangeRecord(status: 'M', path: "data/edited.json"),
      ChangeRecord(status: 'D', path: "data/gone.json")]
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["violations"].len == 2
    check v["violations"][0]["changeClass"].getStr() == "FROZEN"
    check v["violations"][1]["changeClass"].getStr() == "FROZEN"
    echo "  [frozen] ADD/MODIFY blocked, DELETE allowed"

suite "Renames":
  test "rename into PRODUCT -> PASS; old path never generates a violation":
    let recs = @[ChangeRecord(status: 'R', path: "data/old.json",
                             newPath: "src/lib/new.nim")]
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "PASS"
    check v["reasonCode"].getStr() == "OK"
    check v["changeCount"].getInt() == 1
    check v["violations"].len == 0
    check v["summary"]["rename"].getInt() == 1
    echo "  [rename] old FROZEN path judged as DELETE (rule PASS here), new PRODUCT path PASS"

  test "rename into FROZEN -> FAIL (new path judged with op ADD)":
    let recs = @[ChangeRecord(status: 'R', path: "src/lib/a.nim",
                             newPath: "data/frozen.json")]
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["violations"].len == 1
    check v["violations"][0]["path"].getStr() == "data/frozen.json"
    check v["violations"][0]["changeClass"].getStr() == "FROZEN"
    check v["violations"][0]["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    echo "  [rename] into FROZEN blocked"

suite "Copies and typechanges":
  test "copy (C) judged as ADD of the new path":
    let recs = @[ChangeRecord(status: 'C', path: "src/lib/a.nim",
                             newPath: "tools/copied.nim")]
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "FAIL"
    check v["violations"][0]["path"].getStr() == "tools/copied.nim"
    check v["violations"][0]["changeClass"].getStr() == "CONTROLLED"
    check v["summary"]["add"].getInt() == 1
    echo "  [copy] judged as ADD of new path"

  test "copy (C) into PRODUCT -> PASS":
    let recs = @[ChangeRecord(status: 'C', path: "Makefile",
                             newPath: "src/lib/copy.nim")]
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "PASS"
    check v["violations"].len == 0

  test "typechange (T) treated as MODIFY":
    let v = classify(POLICY, @[ChangeRecord(status: 'T', path: "data/x.json")])
    check v["verdict"].getStr() == "FAIL"
    check v["violations"][0]["changeClass"].getStr() == "FROZEN"
    check v["summary"]["modify"].getInt() == 1
    echo "  [typechange] FROZEN MODIFY blocked"

suite "Determinism":
  test "classify twice on identical inputs -> byte-identical JSON":
    let recs = @[
      ChangeRecord(status: 'A', path: "tools/new.nim"),
      ChangeRecord(status: 'M', path: "data/x.json"),
      ChangeRecord(status: 'R', path: "data/old.json", newPath: "src/lib/y.nim"),
      ChangeRecord(status: 'T', path: "Makefile")]
    let j1 = classify(POLICY, recs).pretty(2)
    let j2 = classify(POLICY, recs).pretty(2)
    check j1.len > 0
    check j1 == j2
    echo "  [determinism] byte-identical verdict JSON"

suite "Fail-closed":
  test "invalid policy structure -> FAIL POLICY_INVALID with null policyVersion":
    for badPolicy in @[
      parseJson("[1,2,3]"),
      parseJson("{}"),
      parseJson("""{"schemaVersion": 1, "policyVersion": 1}""")]:
      let v = classify(badPolicy, @[ChangeRecord(status: 'A', path: "src/a.nim")])
      check v["verdict"].getStr() == "FAIL"
      check v["reasonCode"].getStr() == "POLICY_INVALID"
      check v["policyVersion"].kind == JNull
    echo "  [fail-closed] invalid policy -> POLICY_INVALID"

  test "nil policy node (CLI unparsable-JSON sentinel) -> FAIL POLICY_INVALID":
    let v = classify(nil, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    check v["changeCount"].getInt() == 1

  test "unknown status letter -> UNPARSEABLE_DIFF FAIL":
    let (recs, bad) = parseNameStatus("X\tdata/weird.json")
    check bad.len == 0
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "UNPARSEABLE_DIFF"
    check v["violations"][0]["reasonCode"].getStr() == "UNPARSEABLE_DIFF"
    check v["summary"]["other"].getInt() == 1
    echo "  [fail-closed] unknown status -> UNPARSEABLE_DIFF"

  test "line without tab -> UNPARSEABLE_DIFF FAIL":
    let (recs, bad) = parseNameStatus("not-a-diff-line\n\nA\tsrc/x.nim\n")
    check bad.len == 1
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "UNPARSEABLE_DIFF"
    check v["changeCount"].getInt() == 2
    echo "  [fail-closed] unparsable line -> UNPARSEABLE_DIFF"

  test "missing rules entry -> FAIL POLICY_INVALID (structural rejection)":
    let broken = parseJson("""
      {"schemaVersion": 1, "policyVersion": 3,
       "classes": {"PRODUCT": [], "CONTROLLED": ["tools/**"], "FROZEN": ["**"]},
       "defaultClass": "FROZEN",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "PASS"}}}
    """)
    let v = classify(broken, @[ChangeRecord(status: 'A', path: "tools/x.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    check v["policyVersion"].kind == JNull
    echo "  [fail-closed] missing rules entry -> POLICY_INVALID (structural)"

  test "missing rule value for an op -> per-change POLICY_INVALID violation":
    let broken = parseJson("""
      {"schemaVersion": 1, "policyVersion": 4,
       "classes": {"PRODUCT": [], "CONTROLLED": ["tools/**"], "FROZEN": ["**"]},
       "defaultClass": "FROZEN",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "FAIL", "MODIFY": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "PASS"}}}
    """)
    let v = classify(broken, @[ChangeRecord(status: 'D', path: "tools/x.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    check v["violations"][0]["reasonCode"].getStr() == "POLICY_INVALID"
    check v["violations"][0]["changeClass"].getStr() == "CONTROLLED"
    echo "  [fail-closed] missing rule value -> per-change POLICY_INVALID"

  test "empty diff -> PASS with changeCount 0":
    let (recs, _) = parseNameStatus("")
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "PASS"
    check v["reasonCode"].getStr() == "OK"
    check v["changeCount"].getInt() == 0
    echo "  [fail-closed] empty diff -> PASS, changeCount 0"

suite "parseNameStatus":
  test "blank lines skipped; all statuses parsed":
    let (recs, bad) = parseNameStatus(
      "A\ta.nim\n\nM\tb.nim\nD\tc.nim\nR100\told.nim\tnew.nim\n" &
      "C75\tfrom.nim\tto.nim\nT\td.nim\n")
    check bad.len == 0
    check recs.len == 6
    check recs[0].status == 'A' and recs[0].path == "a.nim"
    check recs[1].status == 'M' and recs[1].path == "b.nim"
    check recs[2].status == 'D' and recs[2].path == "c.nim"
    check recs[3].status == 'R' and recs[3].path == "old.nim" and
      recs[3].newPath == "new.nim"
    check recs[4].status == 'C' and recs[4].path == "from.nim" and
      recs[4].newPath == "to.nim"
    check recs[5].status == 'T' and recs[5].path == "d.nim"
    echo "  [parse] blank lines skipped, records parsed"

  test "rename without new path -> unparsable":
    let (recs, bad) = parseNameStatus("R100\tonly-old.nim")
    check bad.len == 1
    check recs.len == 1
    let v = classify(POLICY, recs)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "UNPARSEABLE_DIFF"
    echo "  [parse] rename missing new path -> UNPARSEABLE_DIFF"

suite "Glob semantics":
  let globPolicy = parseJson("""
    {"schemaVersion": 1, "policyVersion": 1,
     "classes": {"PRODUCT": ["src/core/**"],
                 "CONTROLLED": ["Makefile", "tools/*.nim"],
                 "FROZEN": ["**"]},
     "defaultClass": "FROZEN",
     "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "CONTROLLED": {"ADD": "FAIL", "MODIFY": "PASS", "DELETE": "PASS"},
               "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "PASS"}}}
  """)
  test "src/core/** matches nested paths":
    check resolveClass(globPolicy, "src/core/a.nim") == "PRODUCT"
    check resolveClass(globPolicy, "src/core/x/b.nim") == "PRODUCT"
    check resolveClass(globPolicy, "src/core") == "PRODUCT"
    check resolveClass(globPolicy, "src/other.nim") == "FROZEN"
  test "Makefile matches only exactly":
    check resolveClass(globPolicy, "Makefile") == "CONTROLLED"
    check resolveClass(globPolicy, "src/Makefile") == "FROZEN"
  test "tools/*.nim matches only depth-1":
    check resolveClass(globPolicy, "tools/a.nim") == "CONTROLLED"
    check resolveClass(globPolicy, "tools/x/b.nim") == "FROZEN"
    echo "  [glob] ** depth, exact, single-segment *"

suite "Resolution order":
  test "CONTROLLED-specific beats FROZEN-broad":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 1,
       "classes": {"PRODUCT": [], "CONTROLLED": ["tools/surface_guard.nim"],
                   "FROZEN": ["tools/**"]},
       "defaultClass": "FROZEN",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "FAIL", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "PASS"}}}
    """)
    check resolveClass(p, "tools/surface_guard.nim") == "CONTROLLED"
    check resolveClass(p, "tools/other.nim") == "FROZEN"
  test "PRODUCT checked before CONTROLLED before FROZEN":
    check resolveClass(POLICY, "Makefile") == "PRODUCT"
    check resolveClass(POLICY, "tools/guard.nim") == "CONTROLLED"
    check resolveClass(POLICY, "data/x.json") == "FROZEN"
  test "no pattern match -> defaultClass; no default -> empty":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 1,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"], "FROZEN": []},
       "defaultClass": "FROZEN",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "FAIL", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "PASS"}}}
    """)
    check resolveClass(p, "data/unknown.json") == "FROZEN"
    let noDefault = parseJson("""{"classes": {"PRODUCT": ["src/**"],
        "CONTROLLED": [], "FROZEN": []}}""")
    check resolveClass(noDefault, "data/unknown.json") == ""
    echo "  [order] first match wins, default fallback, empty on none"

suite "checkClosure":
  test "all reachable files covered -> PASS":
    let closure = parseJson("""{"schemaVersion": 1, "reachableFiles":
        ["src/a.nim", "Makefile", "tools/guard.nim", "config/p.json"]}""")
    let v = checkClosure(POLICY, closure)
    check v["verdict"].getStr() == "PASS"
    check v["check"].getStr() == "closure"
    check v["uncovered"].len == 0
    check v["policyVersion"].getInt() == 7
    echo "  [closure] all covered -> PASS"
  test "one uncovered path -> FAIL with that path listed":
    let closure = parseJson("""{"schemaVersion": 1, "reachableFiles":
        ["src/a.nim", "data/leak.json"]}""")
    let v = checkClosure(POLICY, closure)
    check v["verdict"].getStr() == "FAIL"
    check v["uncovered"].len == 1
    check v["uncovered"][0].getStr() == "data/leak.json"
    echo "  [closure] FROZEN reachable file -> FAIL, listed in uncovered"
  test "invalid policy -> FAIL with all files uncovered":
    let closure = parseJson("""{"schemaVersion": 1, "reachableFiles":
        ["src/a.nim", "data/leak.json"]}""")
    let v = checkClosure(nil, closure)
    check v["verdict"].getStr() == "FAIL"
    check v["uncovered"].len == 2
    check v["policyVersion"].kind == JNull
    echo "  [closure] invalid policy -> FAIL, all uncovered"

suite "Structural validation (v2)":
  test "exact double registration -> POLICY_INVALID":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["Makefile"],
                   "FROZEN": ["Makefile", "AGENTS.md"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}}}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    check v["policyVersion"].kind == JNull
    echo "  [v2] exact path in two classes -> POLICY_INVALID"

  test "duplicate exact entry within ONE class is not double registration":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["Makefile", "Makefile"],
                   "FROZEN": ["AGENTS.md"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}}}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "PASS"
    echo "  [v2] same-class duplicate exact entry stays valid"

  test "unknown key in classes -> POLICY_INVALID":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"], "EXTRA": []},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}}}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"

  test "unknown key in rules -> POLICY_INVALID":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"},
                 "EXTRA": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"}}}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v2] unknown rules key rejected"

  test "unknown op key in a class rule -> POLICY_INVALID":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL", "PUSH": "FAIL"}}}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v2] unknown op key rejected"

  test "defaultClass outside the three classes -> POLICY_INVALID":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"]},
       "defaultClass": "FREE",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}}}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "nowhere/x.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v2] defaultClass domain enforced"

  test "resolutionOrder not exactly PRODUCT,CONTROLLED,FROZEN -> POLICY_INVALID":
    for ro in @["""["FROZEN", "CONTROLLED", "PRODUCT"]""",
                """["PRODUCT", "CONTROLLED"]""",
                """["PRODUCT", "PRODUCT", "FROZEN"]"""]:
      let p = parseJson("""
        {"schemaVersion": 1, "policyVersion": 20,
         "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"]},
         "defaultClass": "PRODUCT",
         "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                   "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                   "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
         "resolutionOrder": """ & ro & "}")
      let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
      check v["verdict"].getStr() == "FAIL"
      check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v2] resolutionOrder must declare the hardcoded order"

  test "resolutionOrder exactly PRODUCT,CONTROLLED,FROZEN -> valid":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "resolutionOrder": ["PRODUCT", "CONTROLLED", "FROZEN"]}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "PASS"
    echo "  [v2] exact resolutionOrder accepted"

  test "selfAmendment with an extra key -> POLICY_INVALID":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "selfAmendment": {"allowedPaths": ["AGENTS.md"], "owner": "architect"}}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v2] selfAmendment carries only allowedPaths"

  test "selfAmendment allowedPaths with a non-string entry -> POLICY_INVALID":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "selfAmendment": {"allowedPaths": ["AGENTS.md", 3]}}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"

  test "legacy classResolutionOrder is ignored without penalty":
    let p = parseJson("""
      {"schemaVersion": 1, "policyVersion": 20,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["AGENTS.md"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "classResolutionOrder": ["FROZEN", "PRODUCT", "CONTROLLED"]}
    """)
    let v = classify(p, @[ChangeRecord(status: 'A', path: "src/a.nim")])
    check v["verdict"].getStr() == "PASS"
    echo "  [v2] legacy classResolutionOrder ignored"

suite "Rename two-sided judgment (v2)":
  let twoSided = parseJson("""
    {"schemaVersion": 1, "policyVersion": 21,
     "classes": {"PRODUCT": ["src/**"], "CONTROLLED": [], "FROZEN": ["data/**"]},
     "defaultClass": "PRODUCT",
     "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}}}
  """)
  test "rename OUT of FROZEN -> old path judged with op DELETE":
    let v = classify(twoSided, @[ChangeRecord(status: 'R', path: "data/old.json",
                                            newPath: "src/lib/new.nim")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["violations"].len == 1
    check v["violations"][0]["path"].getStr() == "data/old.json"
    check v["violations"][0]["op"].getStr() == "DELETE"
    check v["violations"][0]["changeClass"].getStr() == "FROZEN"
    check v["violations"][0]["status"].getStr() == "R"
    echo "  [rename] old FROZEN path DELETE now judged (v1 blind spot closed)"

  test "rename INTO FROZEN -> new path ADD FAIL, old PRODUCT side PASS":
    let v = classify(twoSided, @[ChangeRecord(status: 'R', path: "src/lib/a.nim",
                                            newPath: "data/new.json")])
    check v["verdict"].getStr() == "FAIL"
    check v["violations"].len == 1
    check v["violations"][0]["path"].getStr() == "data/new.json"
    check v["violations"][0]["op"].getStr() == "ADD"
    echo "  [rename] new FROZEN path ADD blocked (v1 behavior kept)"

  test "rename within FROZEN -> both sides FAIL":
    let v = classify(twoSided, @[ChangeRecord(status: 'R', path: "data/a.json",
                                            newPath: "data/b.json")])
    check v["verdict"].getStr() == "FAIL"
    check v["violations"].len == 2
    check v["summary"]["rename"].getInt() == 1
    echo "  [rename] both sides of a FROZEN rename judged"

  test "rename within PRODUCT -> PASS":
    let v = classify(twoSided, @[ChangeRecord(status: 'R', path: "src/a.nim",
                                            newPath: "src/b.nim")])
    check v["verdict"].getStr() == "PASS"
    check v["violations"].len == 0

suite "selfAmendment exception (v2)":
  let saBase = parseJson("""
    {"schemaVersion": 1, "policyVersion": 10,
     "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                 "FROZEN": ["config/policy.json", "config/guard.nim"]},
     "defaultClass": "PRODUCT",
     "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
     "selfAmendment": {"allowedPaths": ["config/policy.json"]}}
  """)
  let saHead = parseJson("""
    {"schemaVersion": 1, "policyVersion": 11,
     "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                 "FROZEN": ["config/policy.json", "config/guard.nim"]},
     "defaultClass": "PRODUCT",
     "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
     "selfAmendment": {"allowedPaths": ["config/policy.json"]}}
  """)
  test "armed exception -> PASS with AMENDED and amendments array":
    let v = classify(saBase, @[ChangeRecord(status: 'M', path: "config/policy.json")], saHead)
    check v["verdict"].getStr() == "PASS"
    check v["reasonCode"].getStr() == "AMENDED"
    check v["violations"].len == 0
    check v["amendments"].len == 1
    check v["amendments"][0]["path"].getStr() == "config/policy.json"
    check v["amendments"][0]["changeClass"].getStr() == "FROZEN"
    check v["amendments"][0]["op"].getStr() == "MODIFY"
    check v["policyVersion"].getInt() == 10
    echo "  [selfAmendment] legal self-evolution path -> AMENDED"

  test "violation path outside allowedPaths -> FAIL stands":
    let v = classify(saBase, @[ChangeRecord(status: 'M', path: "config/guard.nim")], saHead)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["amendments"].len == 0
    check v["violations"].len == 1
    echo "  [selfAmendment] allowedPaths is an exact allow-list"

  test "head policyVersion not newer -> FAIL stands":
    let headSameV = parseJson("""
      {"schemaVersion": 1, "policyVersion": 10,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                   "FROZEN": ["config/policy.json", "config/guard.nim"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "selfAmendment": {"allowedPaths": ["config/policy.json"]}}
    """)
    let v = classify(saBase, @[ChangeRecord(status: 'M', path: "config/policy.json")], headSameV)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["amendments"].len == 0
    echo "  [selfAmendment] version monotonicity enforced"

  test "base policy without selfAmendment -> FAIL stands":
    let baseNoSA = parseJson("""
      {"schemaVersion": 1, "policyVersion": 10,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                   "FROZEN": ["config/policy.json", "config/guard.nim"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}}}
    """)
    let v = classify(baseNoSA, @[ChangeRecord(status: 'M', path: "config/policy.json")], saHead)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["amendments"].len == 0
    echo "  [selfAmendment] the BASE policy must arm its own exception"

  test "head policy structurally invalid -> FAIL stands":
    let brokenHead = parseJson("""{"schemaVersion": 1, "policyVersion": 11}""")
    let v = classify(saBase, @[ChangeRecord(status: 'M', path: "config/policy.json")], brokenHead)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["amendments"].len == 0
    echo "  [selfAmendment] invalid head policy leaves the exception unarmed"

  test "no head policy (default param) -> FAIL stands":
    let v = classify(saBase, @[ChangeRecord(status: 'M', path: "config/policy.json")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["amendments"].len == 0

  test "non-FROZEN SURFACE_FORBIDDEN is never amended":
    let base2 = parseJson("""
      {"schemaVersion": 1, "policyVersion": 10,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                   "FROZEN": ["config/policy.json"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "FAIL", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "selfAmendment": {"allowedPaths": ["config/policy.json"]}}
    """)
    let recs = @[ChangeRecord(status: 'M', path: "config/policy.json"),
                 ChangeRecord(status: 'A', path: "tools/new.nim")]
    let v = classify(base2, recs, saHead)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["amendments"].len == 1
    check v["amendments"][0]["path"].getStr() == "config/policy.json"
    check v["violations"].len == 1
    check v["violations"][0]["path"].getStr() == "tools/new.nim"
    echo "  [selfAmendment] exception scoped to FROZEN only"

  test "determinism with the head policy":
    let recs = @[ChangeRecord(status: 'M', path: "config/policy.json")]
    let j1 = classify(saBase, recs, saHead).pretty(2)
    let j2 = classify(saBase, recs, saHead).pretty(2)
    check j1 == j2
    echo "  [selfAmendment] byte-identical verdict JSON"

suite "selfAmendment abuse resistance (v4)":
  ## The v2 suite proves the four documented conditions; it does not prove the
  ## conditions cannot be subverted. These tests pin the remaining vectors: the
  ## head policy must not be able to widen its own lane, and the exception must
  ## be all-or-nothing rather than per-violation.
  const abuseBase = """
    {"schemaVersion": 1, "policyVersion": 10,
     "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                 "FROZEN": ["config/policy.json", "config/guard.nim"]},
     "defaultClass": "PRODUCT",
     "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
               "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
     "selfAmendment": {"allowedPaths": ["config/policy.json"]}}
  """
  let base = parseJson(abuseBase)

  test "a head policy cannot widen allowedPaths on its own behalf":
    # The allow-list is read from the BASE policy (condition (b)). A head that
    # lists the forbidden path must not arm itself — otherwise the exception
    # would be self-granting and revocable only by the same actor it binds.
    let headSelfWide = parseJson("""
      {"schemaVersion": 1, "policyVersion": 11,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                   "FROZEN": ["config/policy.json", "config/guard.nim"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "selfAmendment": {"allowedPaths": ["config/policy.json", "config/guard.nim"]}}
    """)
    let v = classify(base, @[ChangeRecord(status: 'M', path: "config/guard.nim")],
                     headSelfWide)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["amendments"].len == 0
    echo "  [v4] head cannot widen the base allow-list"

  test "a head policy cannot relax the rules that produced the violation":
    # Rules are read from the BASE policy. A head whose FROZEN rules are all
    # PASS must not clear a violation the base forbids — otherwise the "newer
    # revision" condition would be a licence to rewrite the judgment.
    let headPermissive = parseJson("""
      {"schemaVersion": 1, "policyVersion": 11,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                   "FROZEN": ["config/policy.json", "config/guard.nim"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"}},
       "selfAmendment": {"allowedPaths": ["config/policy.json"]}}
    """)
    let v = classify(base, @[ChangeRecord(status: 'M', path: "config/guard.nim")],
                     headPermissive)
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check v["amendments"].len == 0
    echo "  [v4] head rules do not overwrite the base rules"

  test "the exception is all-or-nothing across FROZEN violations":
    # One allowed path plus one forbidden path must leave BOTH violations
    # standing. Partial amendment would silently launder the forbidden one by
    # reporting PASS, so the guard requires every FROZEN violation to be
    # inside allowedPaths before it clears any of them.
    let headOk = parseJson("""
      {"schemaVersion": 1, "policyVersion": 11,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                   "FROZEN": ["config/policy.json", "config/guard.nim"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "selfAmendment": {"allowedPaths": ["config/policy.json"]}}
    """)
    for recs in @[
        @[ChangeRecord(status: 'M', path: "config/policy.json"),
          ChangeRecord(status: 'M', path: "config/guard.nim")],
        @[ChangeRecord(status: 'M', path: "config/guard.nim"),
          ChangeRecord(status: 'M', path: "config/policy.json")]]:
      let v = classify(base, recs, headOk)
      check v["verdict"].getStr() == "FAIL"
      check v["amendments"].len == 0
      # neither path is laundered: both violations survive
      check v["violations"].len == 2
      var sawAllowed = false
      var sawForbidden = false
      for vio in v["violations"].items:
        if vio["path"].getStr() == "config/policy.json": sawAllowed = true
        if vio["path"].getStr() == "config/guard.nim": sawForbidden = true
      check sawAllowed
      check sawForbidden
    echo "  [v4] one forbidden path blocks amendment of the allowed one too"

  test "a wildcard in allowedPaths is inert (exact membership only)":
    # allowedPaths is an exact allow-list: membership is `notin`, never a glob.
    # A wildcard entry therefore arms nothing rather than arming everything.
    let wildBase = parseJson("""
      {"schemaVersion": 1, "policyVersion": 10,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                   "FROZEN": ["config/policy.json", "config/guard.nim"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "selfAmendment": {"allowedPaths": ["config/*"]}}
    """)
    let wildHead = parseJson("""
      {"schemaVersion": 1, "policyVersion": 11,
       "classes": {"PRODUCT": ["src/**"], "CONTROLLED": ["tools/**"],
                   "FROZEN": ["config/policy.json", "config/guard.nim"]},
       "defaultClass": "PRODUCT",
       "rules": {"PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "CONTROLLED": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
                 "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL"}},
       "selfAmendment": {"allowedPaths": ["config/*"]}}
    """)
    let v = classify(wildBase, @[ChangeRecord(status: 'M', path: "config/policy.json")],
                     wildHead)
    check v["verdict"].getStr() == "FAIL"
    check v["amendments"].len == 0
    echo "  [v4] wildcard allow-list arms nothing"

  test "shipped policy allow-list is exact paths, not patterns":
    # The live policy's self-evolution lane must obey the same rule the
    # synthetic wildcard test pins: exact membership, never a glob.
    let loaded = loadPolicy(SHIPPED_POLICY)
    check loaded.ok
    let allowed = selfAmendmentPaths(loaded.node)
    check allowed.len > 0
    var wild: seq[string] = @[]
    for p in allowed:
      if '*' in p:
        wild.add(p)
    check wild.len == 0
    # The lane may also name non-FROZEN paths (the shipped policy does: the
    # test file is PRODUCT and the contract doc is CONTROLLED). Those entries
    # are inert — the exception only ever clears FROZEN violations — so the
    # invariant is that at least one allowed path IS FROZEN, i.e. the lane is
    # not entirely decorative.
    var frozenAllowed = 0
    for p in allowed:
      if resolveClass(loaded.node, p) == "FROZEN":
        inc frozenAllowed
    check frozenAllowed > 0
    echo "  [v4] shipped allow-list: ", allowed.len, " exact paths, ",
         frozenAllowed, " FROZEN"

# ---------------------------------------------------------------------------
# v3 (DEBT#545): frozenExceptions contract.
# ---------------------------------------------------------------------------

const V3_BASE = """
{
  "schemaVersion": 1,
  "policyVersion": 12,
  "classes": {
    "PRODUCT": ["src/**"],
    "CONTROLLED": ["tools/**", "config/policy.json"],
    "FROZEN": ["config/**"]
  },
  "defaultClass": "FROZEN",
  "rules": {
    "PRODUCT": {"ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS"},
    "CONTROLLED": {"ADD": "FAIL", "MODIFY": "PASS", "DELETE": "PASS"},
    "FROZEN": {"ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "PASS"}
  }
}
"""

proc v3Clone(): JsonNode = parseJson(V3_BASE)

proc v3WithExceptions(groups, paths: JsonNode): JsonNode =
  result = v3Clone()
  var fe = newJObject()
  fe["schema"] = %FROZEN_EXCEPTION_SCHEMA
  fe["groups"] = groups
  fe["paths"] = paths
  result["frozenExceptions"] = fe

proc okGroups(): JsonNode =
  %* {"generated-manifest": {"rationale": "generated", "approvedBy": "architect"}}

proc mentionsVersion(text: string, v: int): bool =
  ## True when `text` records revision `v` as a `v<N>` token. The trailing
  ## digit guard keeps v108 from being satisfied by "v1080".
  let token = "v" & $v
  var i = 0
  while i + token.len <= text.len:
    if text[i] == 'v' and text[i ..< i + token.len] == token:
      let after = i + token.len
      if after >= text.len or text[after] notin {'0'..'9'}:
        return true
    inc i
  false

suite "v3 frozenExceptions (DEBT#545)":
  test "unregistered exact/FROZEN conflict -> POLICY_INVALID":
    let v = classify(v3Clone(), @[ChangeRecord(status: 'M', path: "config/policy.json")])
    check v["verdict"].getStr() == "FAIL"
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v3] unregistered conflict is rejected"

  test "registered exception keeps the declared class and verdict":
    let p = v3WithExceptions(okGroups(), %* {"config/policy.json": "generated-manifest"})
    let ok = classify(p, @[ChangeRecord(status: 'M', path: "config/policy.json")])
    check ok["verdict"].getStr() == "PASS"
    check ok["reasonCode"].getStr() == "OK"
    let bad = classify(p, @[ChangeRecord(status: 'A', path: "config/policy.json")])
    check bad["verdict"].getStr() == "FAIL"
    check bad["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check bad["violations"][0]["changeClass"].getStr() == "CONTROLLED"
    echo "  [v3] exception preserves CONTROLLED semantics"

  test "dead exception -> POLICY_INVALID":
    let p = v3WithExceptions(okGroups(),
      %* {"config/policy.json": "generated-manifest",
          "config/never.nim": "generated-manifest"})
    let v = classify(p, @[ChangeRecord(status: 'M', path: "config/policy.json")])
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v3] dead exceptions are rejected"

  test "group without rationale or approvedBy -> POLICY_INVALID":
    let noRationale = %* {"g": {"approvedBy": "architect"}}
    let v1 = classify(v3WithExceptions(noRationale,
      %* {"config/policy.json": "g"}), @[])
    check v1["reasonCode"].getStr() == "POLICY_INVALID"
    let noApprover = %* {"g": {"rationale": "generated"}}
    let v2 = classify(v3WithExceptions(noApprover,
      %* {"config/policy.json": "g"}), @[])
    check v2["reasonCode"].getStr() == "POLICY_INVALID"
    let extraKey = %* {"g": {"rationale": "r", "approvedBy": "a", "extra": "x"}}
    let v3 = classify(v3WithExceptions(extraKey,
      %* {"config/policy.json": "g"}), @[])
    check v3["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v3] group attribution is mandatory and exact"

  test "wildcard registration -> POLICY_INVALID":
    let p = v3WithExceptions(okGroups(),
      %* {"config/policy.json": "generated-manifest",
          "config/*": "generated-manifest"})
    let v = classify(p, @[ChangeRecord(status: 'M', path: "config/policy.json")])
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v3] wildcard exceptions are rejected"

  test "path pointing at an unknown group -> POLICY_INVALID":
    let p = v3WithExceptions(okGroups(),
      %* {"config/policy.json": "no-such-group"})
    let v = classify(p, @[])
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v3] dangling group references are rejected"

  test "wrong exception schema -> POLICY_INVALID":
    var p = v3WithExceptions(okGroups(), %* {"config/policy.json": "generated-manifest"})
    p["frozenExceptions"]["schema"] = %"axiom.repository-surface-frozen-exceptions.v2"
    let v = classify(p, @[])
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v3] schema string is pinned"

  test "shipped policy is structurally valid and its registry is derived, not declared":
    let loaded = loadPolicy(SHIPPED_POLICY)
    check loaded.ok
    check not loaded.invalidContent
    # Structural validity: an empty-diff classify only reaches PASS/OK after
    # isValidPolicy accepts every field, including the frozenExceptions block.
    let v = classify(loaded.node, @[])
    check v["verdict"].getStr() == "PASS"
    check v["reasonCode"].getStr() == "OK"

    # The registry must equal the set the policy's own class tables imply —
    # recomputed here from PRODUCT/CONTROLLED x FROZEN, never read back from
    # frozenExceptions. Equality in BOTH directions is what makes this
    # semantic: a missing entry means a FROZEN declaration is silently inert
    # (DEBT#545), and a surplus entry is a dead exception.
    let registered = frozenExceptionPaths(loaded.node)
    let derived = shadowedExceptionSet(loaded.node)
    check registered.len > 0
    var missing: seq[string] = @[]
    for p in derived:
      if p notin registered:
        missing.add(p)
    var surplus: seq[string] = @[]
    for p in registered:
      if p notin derived:
        surplus.add(p)
    check missing.len == 0
    check surplus.len == 0
    echo "  [v4] shipped registry == derived shadowed set (", registered.len, " paths)"

  test "every shipped exception is exact, uniquely grouped and load-bearing":
    let loaded = loadPolicy(SHIPPED_POLICY)
    check loaded.ok
    let policy = loaded.node
    let paths = policy["frozenExceptions"]["paths"]
    let groups = policy["frozenExceptions"]["groups"]
    let probe = frozenOnlyView(policy)

    var wildcards: seq[string] = @[]
    var noGroup: seq[string] = @[]
    var notShadowing: seq[string] = @[]
    var stillFrozen: seq[string] = @[]
    for e in frozenExceptionPaths(policy):
      # (a) exact only — a wildcard registration would re-arm the theater.
      if '*' in e:
        wildcards.add(e)
      # (b) attribution: the path must name a group declared with rationale
      # and approvedBy (isValidPolicy rejects dangling refs, so a group hit
      # here is a fully attributed one).
      let gid = paths[e]
      if gid.isNil or gid.kind != JString or not groups.hasKey(gid.getStr()):
        noGroup.add(e)
      # (c) shadowing: some FROZEN pattern must match it, else the entry is
      # dead and the guard would reject the policy as POLICY_INVALID.
      if resolveClass(probe, e) != "FROZEN":
        notShadowing.add(e)
      # (d) the override is real: under the shipped policy the path must not
      # resolve FROZEN, or the registration would buy nothing.
      if resolveClass(policy, e) == "FROZEN":
        stillFrozen.add(e)

    check wildcards.len == 0
    check noGroup.len == 0
    check notShadowing.len == 0
    check stillFrozen.len == 0
    # No duplicates: `paths` is a JSON object, so duplicates are impossible
    # by construction — the check above on set equality is what pins it.
    echo "  [v4] ", frozenExceptionPaths(policy).len,
         " exceptions are exact, attributed, shadowing and effective"

  test "policyVersion is a positive integer recorded in the changelog":
    let loaded = loadPolicy(SHIPPED_POLICY)
    check loaded.ok
    let policy = loaded.node
    let pv = policy["policyVersion"]
    # (a) type and sign — the property that matters, not a pinned literal.
    check pv.kind == JInt
    check pv.getInt() > 0
    # (b) every entry point echoes that same version, so the policy cannot
    # disagree with itself about which revision it is.
    check classify(policy, @[])["policyVersion"].getInt() == pv.getInt()
    check checkClosure(policy, %*{"schemaVersion": 1, "reachableFiles": []}
    )["policyVersion"].getInt() == pv.getInt()
    # (c) internal consistency: the description's changelog records the
    # version being shipped (house style appends one "vN (" paragraph per
    # revision). A bump without a changelog entry is caught here.
    check mentionsVersion(policy["description"].getStr(), pv.getInt())
    echo "  [v4] policyVersion v", pv.getInt(),
         " is positive, echoed by classify/closure and in the changelog"

  test "shipped policy: dropping one exception is caught (liveness)":
    let loaded = loadPolicy("config/repository_surface.json")
    check loaded.ok
    var p = loaded.node
    let paths = p["frozenExceptions"]["paths"]
    var victim = ""
    for k in paths.keys:
      victim = k
      break
    check victim.len > 0
    paths.delete(victim)
    let v = classify(p, @[ChangeRecord(status: 'M', path: victim)])
    check v["reasonCode"].getStr() == "POLICY_INVALID"
    echo "  [v3] every shipped exception is load-bearing"

  test "shipped policy: FROZEN intent enforced, docs untouched":
    let loaded = loadPolicy("config/repository_surface.json")
    check loaded.ok
    let frozen = classify(loaded.node,
      @[ChangeRecord(status: 'M', path: ".githooks/pre-push")])
    check frozen["verdict"].getStr() == "FAIL"
    check frozen["reasonCode"].getStr() == "SURFACE_FORBIDDEN"
    check frozen["violations"][0]["changeClass"].getStr() == "FROZEN"
    let docs = classify(loaded.node,
      @[ChangeRecord(status: 'M', path: "docs/agents/operations.md")])
    check docs["verdict"].getStr() == "PASS"
    echo "  [v3] shipped policy enforces FROZEN and spares docs"
