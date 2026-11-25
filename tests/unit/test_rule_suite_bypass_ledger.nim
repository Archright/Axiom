## tests/unit/test_rule_suite_bypass_ledger.nim
## Unit tests for tools/ci/rule_suite_bypass_ledger.nim — the pure core only.
##
## WHY THE PURE CORE IS TESTED HERE AND THE CLI IS NOT: the merge/assert
## contract is a set of total functions over already-parsed JSON. A test that
## shelled out to the binary would re-test `readFile` and `quit`, and would
## pass even if the judgments were wrong. These tests drive the functions
## that make the decisions.
##
## The tests that matter most are the ones that assert the tool REFUSES:
## a bypass record is immutable, so a merge that silently picks a winner on
## conflicting input would corrupt the permanent record it exists to keep.

import std/[json, options, sets, strutils]
import ../../tools/ci/rule_suite_bypass_ledger

# ---------------------------------------------------------------------------
# Fixtures (module scope — keeps `%*` out of template bodies)
# ---------------------------------------------------------------------------

proc entry(id: int; pushedAt: string; afterSha = "aa"; verdict = "bypass"): JsonNode =
  %*{
    "id": id,
    "actor_id": 53123826,
    "actor_name": "wintrover",
    "before_sha": "bb",
    "after_sha": afterSha,
    "ref": "refs/heads/main",
    "repository_id": 1454952493,
    "repository_name": "Axiom",
    "pushed_at": pushedAt,
    "result": verdict
  }

const
  ## A fixed judgment clock. Every freshness case below passes this as
  ## `--now`-equivalent, so the suite is deterministic: a test that read the
  ## host clock would pass today and fail on the day the fixture aged out,
  ## which is the same silent-rot failure the freshness check exists to catch.
  NewestPushedAt = "2026-11-24T19:58:18+09:00"   # epoch 1795517898
  NewestEpoch = 1795517898'i64
  Day = 86400'i64

proc judgeAt(rows: seq[JsonNode]; nowEpoch: int64; maxAgeDays: int64;
             maxAgeSupplied = true): LedgerReport =
  ## Freshness-only judgment with the other two checks deliberately UNKNOWN —
  ## the point of each case is the freshness dimension alone.
  judge(rows, initHashSet[string](), false, @[], false, nowEpoch, maxAgeDays,
        maxAgeSupplied)

proc parseClock(iso: string): int64 =
  ## The suite parses its own clock inputs through the SHIPPED parser, so a
  ## fixture cannot silently encode a different instant than the tool reads.
  let e = pushedEpoch(iso)
  doAssert e.isSome, "clock fixture must parse: " & iso
  e.get()

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
      except Defect:
        inc failed
        echo "  FAIL: " & name & " - " & getCurrentExceptionMsg()

  # ── pushed_at parsing (hand-rolled, no timezone DB) ──────────────────────
  echo "=== pushed_at epoch parsing ==="

  check "epoch: known instant round-trips to the real offset":
    # 2026-11-21T11:40:45+09:00 == 2026-11-21T02:40:45Z (verified with
    # python datetime, not assumed)
    let got = pushedEpoch("2026-11-21T11:40:45+09:00")
    assert got.isSome, "must parse"
    assert got.get() == 1795228845'i64, "got " & $got.get()

  check "epoch: offset is applied, not ignored":
    let a = pushedEpoch("2026-11-21T11:40:45+09:00")
    let b = pushedEpoch("2026-11-21T11:40:45+00:00")
    assert a.isSome and b.isSome
    assert a.get() != b.get(), "different offsets must differ"
    assert b.get() - a.get() == 9'i64 * 3600'i64

  check "epoch: negative offset":
    # -05:00 02:40:45 is a LATER instant than 02:40:45Z (same wall clock,
    # offset behind UTC), so a - b is positive here.
    let a = pushedEpoch("2026-11-21T02:40:45-05:00")
    let b = pushedEpoch("2026-11-21T02:40:45+00:00")
    assert a.isSome and b.isSome
    assert a.get() - b.get() == 5'i64 * 3600'i64,
      "a=" & $a.get() & " b=" & $b.get()

  check "epoch: leap day is handled":
    assert pushedEpoch("2024-02-29T00:00:00+00:00").isSome

  check "epoch: malformed shapes are none, never a guess":
    for bad in ["", "2026-11-21", "2026-11-21T11:40:45", "2026-13-01T00:00:00+00:00",
                "2026-11-21T11:40:45+0900", "not-a-date", "2026-11-21T11:40:45+09:00Z"]:
      assert pushedEpoch(bad).isNone, "should reject: " & bad

  # ── canonical projection ─────────────────────────────────────────────────
  echo "=== canonical projection ==="

  check "canonical: ten fields in fixed order, extras dropped":
    var raw = entry(1, "2026-11-21T11:40:45+09:00")
    raw["evaluation_result"] = %"bypass"      # API extra — must NOT be guessed in
    let c = canonicalEntry(raw)
    assert not c.isNil
    assert c.len == 10, "got " & $c.len
    var keys: seq[string] = @[]
    for k, v in c: keys.add(k)
    assert keys == @["id", "actor_id", "actor_name", "before_sha", "after_sha",
                     "ref", "repository_id", "repository_name", "pushed_at",
                     "result"], "order: " & $keys
    assert not c.hasKey("evaluation_result"), "extra field must be dropped"

  check "canonical: missing field -> nil (no partially populated line)":
    var raw = entry(2, "2026-11-21T11:40:45+09:00")
    raw.delete("actor_name")
    assert canonicalEntry(raw).isNil

  check "canonical: wrong JSON type -> nil":
    var raw = entry(3, "2026-11-21T11:40:45+09:00")
    raw["id"] = %"not-an-integer"
    assert canonicalEntry(raw).isNil

  check "canonical: null field -> nil":
    var raw = entry(4, "2026-11-21T11:40:45+09:00")
    raw["actor_name"] = newJNull()
    assert canonicalEntry(raw).isNil

  check "canonical: non-object -> nil":
    assert canonicalEntry(%[1, 2, 3]).isNil
    assert canonicalEntry(newJNull()).isNil

  # ── merge: idempotence and immutability ──────────────────────────────────
  echo "=== merge semantics ==="

  check "merge: identical re-run is a no-op (idempotent)":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00")]
    let once = mergeNodes(rows, rows)
    assert once.ok, "same bytes for one id is NOT a conflict"
    assert once.rows.len == 1
    let twice = mergeNodes(once.rows, rows)
    assert twice.ok
    assert $renderJsonl(twice.rows) == $renderJsonl(once.rows),
      "second merge must be byte-identical"

  check "merge: disjoint sets union":
    let a = @[entry(1, "2026-11-21T11:40:45+09:00")]
    let b = @[entry(2, "2026-11-22T11:40:45+09:00")]
    let m = mergeNodes(a, b)
    assert m.ok and m.rows.len == 2

  check "merge: same id with DIFFERENT bytes fails closed":
    let a = @[entry(1, "2026-11-21T11:40:45+09:00", afterSha = "aa")]
    let b = @[entry(1, "2026-11-21T11:40:45+09:00", afterSha = "zz")]
    let m = mergeNodes(a, b)
    assert not m.ok, "must refuse, not pick a winner"
    assert m.conflictId == 1

  check "merge: malformed input fails closed":
    var bad = entry(1, "2026-11-21T11:40:45+09:00")
    bad.delete("result")
    assert not mergeNodes(@[bad], @[]).ok

  # ── ordering ─────────────────────────────────────────────────────────────
  echo "=== ordering ==="

  check "order: sorted by absolute time, not raw string":
    # +09:00 11:40 == 02:40Z is EARLIER than +00:00 03:00Z, though the raw
    # strings sort the other way ('11' > '03' as text is false, so the string
    # order would also be wrong the other way round).
    let later = entry(2, "2026-11-21T03:00:00+00:00")
    let earlier = entry(1, "2026-11-21T11:40:45+09:00")
    let m = mergeNodes(@[later, earlier], @[])
    assert m.ok
    var lines: seq[string] = @[]
    for ln in renderJsonl(m.rows).splitLines():
      if ln.len > 0: lines.add(ln)   # splitLines yields a trailing "" for the final LF
    assert lines.len == 2
    assert lines[0].find("\"id\":1") >= 0,
      "earlier instant (id 1) must sort first:\n" & $renderJsonl(m.rows)
    assert lines[1].find("\"id\":2") >= 0,
      "later instant (id 2) must sort second:\n" & $renderJsonl(m.rows)

  check "order: id breaks ties (total order, stable re-derivation)":
    let a = entry(9, "2026-11-21T11:40:45+09:00")
    let b = entry(3, "2026-11-21T11:40:45+09:00")
    let m = mergeNodes(@[a, b], @[])
    assert m.ok
    var lines: seq[string] = @[]
    for ln in renderJsonl(m.rows).splitLines():
      if ln.len > 0: lines.add(ln)
    assert lines.len == 2
    assert lines[0].find("\"id\":3") >= 0, "id 3 must come first: " & lines[0]
    assert lines[1].find("\"id\":9") >= 0, "id 9 must come second: " & lines[1]

  # ── rendering ────────────────────────────────────────────────────────────
  echo "=== canonical bytes ==="

  check "render: one compact object per line, LF, trailing newline":
    let txt = renderJsonl(@[entry(1, "2026-11-21T11:40:45+09:00")])
    assert txt.endsWith("\n")
    assert txt.count('\n') == 1
    assert not txt.contains(": "), "compact form has no space after colon"
    assert not txt.contains("\n\n")

  check "render: same rows -> same bytes":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00"),
                 entry(2, "2026-11-22T11:40:45+09:00")]
    assert renderJsonl(rows) == renderJsonl(rows)

  check "render: jsonl round-trips through the parser":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00"),
                 entry(2, "2026-11-22T11:40:45+09:00")]
    let txt = renderJsonl(rows)
    let back = parseJsonl(txt)
    assert back.ok
    assert back.rows.len == 2
    assert renderJsonl(back.rows) == txt

  check "parseJsonl: blank lines tolerated, bad line fails whole file":
    let ok = parseJsonl(renderJsonl(@[entry(1, "2026-11-21T11:40:45+09:00")]) & "\n")
    assert ok.ok and ok.rows.len == 1
    assert not parseJsonl("{\"a\":1}\nnot json\n").ok

  check "parseJsonl: non-object line fails":
    assert not parseJsonl("[1,2,3]\n").ok

  # ── direct-push detection ────────────────────────────────────────────────
  echo "=== direct-push detection ==="

  check "direct: after_sha in first-parent set -> no finding":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00", afterSha = "known")]
    var fp = initHashSet[string]()
    fp.incl("known")
    assert findDirectPushes(rows, fp).len == 0

  check "direct: after_sha absent from set -> finding":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00", afterSha = "unknown")]
    var fp = initHashSet[string]()
    fp.incl("known")
    assert findDirectPushes(rows, fp).len == 1

  check "direct: check is not vacuous over an empty set":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00", afterSha = "x")]
    assert findDirectPushes(rows, initHashSet[string]()).len == 1

  # ── elevation windows ────────────────────────────────────────────────────
  echo "=== elevation windows ==="

  check "windows: parse a well-formed document":
    let doc = %*{"windows": [{"label": "w1",
                              "start": "2026-11-21T11:00:00+09:00",
                              "end": "2026-11-21T17:30:00+09:00"}]}
    let p = parseWindows(doc)
    assert p.ok
    assert p.windows.len == 1

  check "windows: malformed document is an error, NOT 'no windows'":
    let doc = %*{"windows": [{"label": "w1", "start": "nope", "end": "nope"}]}
    assert not parseWindows(doc).ok

  check "windows: missing key is an error":
    assert not parseWindows(%*{"windows": [{"label": "w1"}]}).ok
    assert not parseWindows(%*{"nope": []}).ok

  check "windows: inclusive at both ends":
    let doc = %*{"windows": [{"label": "w1",
                              "start": "2026-11-21T11:40:45+09:00",
                              "end": "2026-11-21T11:40:45+09:00"}]}
    let p = parseWindows(doc)
    assert p.ok
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00")]
    assert findWindowMatches(rows, p.windows).len == 1, "endpoints are inclusive"

  check "windows: outside the interval -> no match":
    let doc = %*{"windows": [{"label": "w1",
                              "start": "2026-11-21T00:00:00+09:00",
                              "end": "2026-11-21T01:00:00+09:00"}]}
    let p = parseWindows(doc)
    assert p.ok
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00")]
    assert findWindowMatches(rows, p.windows).len == 0

  # ── the report must never look clean when a check did not run ────────────
  echo "=== UNKNOWN is not zero ==="

  check "judge: nothing supplied -> all three checks UNKNOWN, no findings":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00")]
    let r = judge(rows, initHashSet[string](), false, @[], false, 0'i64, 0'i64, false)
    assert not r.directPushCheckable, "unperformed check must not be checkable"
    assert not r.windowCheckable
    assert r.freshness == freshUnknown
    assert not r.isFinding
    assert r.directPushes.len == 0
    assert r.total == 1

  check "judge: unperformed checks render as UNKNOWN text, never PASS":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00")]
    let txt = renderReport(judge(rows, initHashSet[string](), false, @[], false,
                                 0'i64, 0'i64, false))
    assert txt.contains("UNKNOWN")
    assert not txt.contains("PASS"), "an unrun check must not read as PASS"
    assert not txt.contains("FRESH"), "unasked freshness must not read as FRESH"

  check "judge: direct-push supplied and clean -> PASS, windows still UNKNOWN":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00", afterSha = "known")]
    var fp = initHashSet[string]()
    fp.incl("known")
    let txt = renderReport(judge(rows, fp, true, @[], false, 0'i64, 0'i64, false))
    assert txt.contains("PASS")
    assert txt.contains("UNKNOWN"), "the unrun check must still be flagged"

  check "judge: json projection distinguishes PERFORMED from UNKNOWN":
    let rows = @[entry(1, "2026-11-21T11:40:45+09:00", afterSha = "k")]
    let unknown = reportJson(judge(rows, initHashSet[string](), false, @[], false,
                                   0'i64, 0'i64, false))
    assert unknown["directPushCheck"].getStr() == "UNKNOWN"
    var fp = initHashSet[string]()
    fp.incl("k")
    let performed = reportJson(judge(rows, fp, true, @[], false, 0'i64, 0'i64, false))
    assert performed["directPushCheck"].getStr() == "PERFORMED"

  # ── freshness: is the ledger new enough to be evidence? ──────────────────
  echo "=== freshness ==="

  check "freshness: absent limit -> UNKNOWN, never FRESH, never a finding":
    let rows = @[entry(1, NewestPushedAt)]
    let r = judgeAt(rows, NewestEpoch + 400 * Day, 0, maxAgeSupplied = false)
    assert r.freshness == freshUnknown, "got " & $r.freshness
    assert not r.isFinding, "an unasked question must not become a finding"
    let txt = renderReport(r)
    assert txt.contains("freshness: UNKNOWN")
    assert not txt.contains("FRESH"), "UNKNOWN must not print FRESH anywhere"
    assert reportJson(r)["freshnessCheck"].getStr() == "UNKNOWN"

  check "freshness: exactly N days old is FRESH (inclusive boundary)":
    let rows = @[entry(1, NewestPushedAt)]
    let r = judgeAt(rows, NewestEpoch + 2 * Day, 2)
    assert r.freshness == freshFresh, "N days must be within a limit of N"
    assert r.newestAgeDays == 2, "got " & $r.newestAgeDays
    assert not r.isFinding

  check "freshness: one second inside N days is FRESH":
    let rows = @[entry(1, NewestPushedAt)]
    let r = judgeAt(rows, NewestEpoch + 2 * Day - 1, 2)
    assert r.freshness == freshFresh

  check "freshness: N days + 1 second is still FRESH (age is whole days)":
    # The limit is a day count, so the discriminating comparison is on whole
    # days: one second past the boundary is still age N under div, which
    # reads FRESH. The boundary the tool must honour is N inclusive,
    # N+1 exclusive, and this pins that off-by-one explicitly.
    let rows = @[entry(1, NewestPushedAt)]
    let r = judgeAt(rows, NewestEpoch + (2 * Day) + 1, 2)
    assert r.freshness == freshFresh,
      "age is whole days, so N+1s is still age N — the tool must not " &
      "report STALE for a sub-day overshoot (got " & $r.freshness & ")"

  check "freshness: N+1 whole days is STALE":
    let rows = @[entry(1, NewestPushedAt)]
    let r = judgeAt(rows, NewestEpoch + 3 * Day, 2)
    assert r.freshness == freshStale, "got " & $r.freshness
    assert r.newestAgeDays == 3
    assert r.isFinding, "STALE must be a finding (exit 1)"

  check "freshness: STALE renders the age and the limit":
    let rows = @[entry(1, NewestPushedAt)]
    let txt = renderReport(judgeAt(rows, NewestEpoch + 5 * Day, 2))
    assert txt.contains("freshness: STALE (age=5d, limit=2d)"),
      "report must state the measurement: " & txt

  check "freshness: STALE json is machine-readable":
    let rows = @[entry(1, NewestPushedAt)]
    let j = reportJson(judgeAt(rows, NewestEpoch + 5 * Day, 2))
    assert j["freshness"].getStr() == "STALE"
    assert j["freshnessCheck"].getStr() == "PERFORMED"
    assert j["freshnessAgeDays"].getBiggestInt() == 5
    assert j["freshnessMaxAgeDays"].getBiggestInt() == 2
    assert j["finding"].getBool()

  check "freshness: oldest row does not drive the verdict, only the newest":
    # A ledger with one ancient row and one fresh row is fresh: the question
    # is whether anything newer than the newest row is unrecorded.
    let rows = @[entry(1, "2020-01-01T00:00:00+00:00"),
                 entry(2, NewestPushedAt)]
    let r = judgeAt(rows, NewestEpoch + Day, 2)
    assert r.freshness == freshFresh, "got " & $r.freshness

  check "freshness: unwrapped clock skew -> FUTURE, its own verdict":
    # The newest row is ahead of the judgment clock. A negative age trivially
    # satisfies `age <= limit`, so folding it into FRESH would let a
    # hand-edited (or clock-skewed) row attest freshness forever.
    let rows = @[entry(1, NewestPushedAt)]
    let r = judgeAt(rows, NewestEpoch - 3600, 2)
    assert r.freshness == freshFuture, "got " & $r.freshness
    assert r.isFinding, "an unauditable record must not exit 0"
    let txt = renderReport(r)
    assert txt.contains("freshness: FUTURE")
    assert not txt.contains("FRESH ("), "FUTURE must not render as FRESH"

  check "freshness: FUTURE json distinct from STALE json":
    let rows = @[entry(1, NewestPushedAt)]
    let j = reportJson(judgeAt(rows, NewestEpoch - 3600, 2))
    assert j["freshness"].getStr() == "FUTURE"
    assert j["freshnessCheck"].getStr() == "PERFORMED"
    assert j["finding"].getBool()

  check "freshness: empty ledger is UNKNOWN, not STALE and not FRESH":
    # No rows means no age to measure. STALE would invent a measurement;
    # FRESH would attest a ledger that recorded nothing.
    let r = judgeAt(@[], NewestEpoch, 2)
    assert r.freshness == freshUnknown, "got " & $r.freshness
    assert not r.isFinding, "no measurement is not a staleness finding"

  check "freshness: judgeFreshness is total over the epoch extremes":
    # `now` far past / far before the row must not overflow or wrap.
    let f1 = judgeFreshness(0'i64, true, high(int64) - 1, 2, true)
    assert f1.verdict == freshStale, "got " & $f1.verdict
    let f2 = judgeFreshness(high(int64) - 1, true, 0'i64, 2, true)
    assert f2.verdict == freshFuture, "got " & $f2.verdict

  check "freshness: a limit of 1 still catches a 2-day-old ledger":
    let rows = @[entry(1, NewestPushedAt)]
    assert judgeAt(rows, NewestEpoch + Day, 1).freshness == freshFresh
    assert judgeAt(rows, NewestEpoch + 2 * Day, 1).freshness == freshStale

  check "freshness: a 30-day-old ledger is STALE under a 2-day limit":
    # The concrete rot scenario the README named: nothing collected for a
    # month, so every landing in that month is unrecorded. Before freshness
    # existed this file reported a clean PASS over exactly these contents.
    let rows = @[entry(1, NewestPushedAt)]
    let r = judgeAt(rows, NewestEpoch + 30 * Day, 2)
    assert r.freshness == freshStale, "got " & $r.freshness
    assert r.newestAgeDays == 30
    assert r.isFinding, "a month-stale ledger must exit non-zero"

  # ── Summary ──────────────────────────────────────────────────────────────

  echo ""
  echo "=== Results: " & $passed & " passed, " & $failed & " failed ==="
  if failed > 0:
    quit(1)

when isMainModule:
  main()
