## Unit tests for tools/surface_guard.nim — deterministic repository-surface
## guard. Covers the frozen interface contract: class x op decision table,
## rename/copy/typechange semantics, determinism, fail-closed behavior, glob
## semantics, resolution order, and checkClosure.
##
## Run from repo root:
##   nim c -r --hints:off --nimcache:/tmp/nimc_guard tests/unit/test_surface_guard.nim

import std/[json, unittest, strutils]
import ../../tools/surface_guard

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
    echo "  [rename] old FROZEN path ignored (implicit DELETE), new PRODUCT path PASS"

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
