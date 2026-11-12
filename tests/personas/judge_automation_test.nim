## Judge Automation + Tactic History Fingerprinting Tests
##
## Real tests for judge_automation.nim and tactic deduplication in
## legislator_feedback.nim. No stubs, no `check true`.

import std/unittest
import std/tables
import std/sets
import std/options
import std/os
import std/strutils
import std/json

import personas/judge_automation
import personas/legislator_feedback

# ──────────────────────────────────────────────────────────────────────────────
# selectStrategies — one test per GoalShape
# ──────────────────────────────────────────────────────────────────────────────

suite "selectStrategies maps each GoalShape correctly":
  test "gsLinearArithmetic → omega first":
    let strats = selectStrategies(gsLinearArithmetic)
    check strats.len > 0
    check strats[0] == jsOmega

  test "gsEquality → decide first":
    let strats = selectStrategies(gsEquality)
    check strats.len > 0
    check strats[0] == jsDecide

  test "gsInductiveStructure → grind first":
    let strats = selectStrategies(gsInductiveStructure)
    check strats.len > 0
    check strats[0] == jsGrind

  test "gsFiniteEquality → decide first":
    let strats = selectStrategies(gsFiniteEquality)
    check strats.len > 0
    check strats[0] == jsDecide

  test "gsGeneral → omega first":
    let strats = selectStrategies(gsGeneral)
    check strats.len > 0
    check strats[0] == jsOmega

  test "gsUnknown → only LLM fallback":
    let strats = selectStrategies(gsUnknown)
    check strats.len == 1
    check strats[0] == jsLlmFallback

  test "all GoalShapes produce non-empty strategy lists":
    for shape in [gsLinearArithmetic, gsEquality, gsInductiveStructure,
                  gsFiniteEquality, gsGeneral, gsUnknown]:
      let strats = selectStrategies(shape)
      check strats.len > 0

# ──────────────────────────────────────────────────────────────────────────────
# strategyToTactic — verify tactic names
# ──────────────────────────────────────────────────────────────────────────────

suite "strategyToTactic produces valid Lean tactic names":
  test "jsRfl → rfl":
    check strategyToTactic(jsRfl) == "rfl"
  test "jsOmega → omega":
    check strategyToTactic(jsOmega) == "omega"
  test "jsDecide → decide":
    check strategyToTactic(jsDecide) == "decide"
  test "jsNativeDecide → native_decide":
    check strategyToTactic(jsNativeDecide) == "native_decide"
  test "jsSimp → simp":
    check strategyToTactic(jsSimp) == "simp"
  test "jsSimpOmega → simp + omega":
    check strategyToTactic(jsSimpOmega) == "simp\n  omega"
  test "jsGrind → grind":
    check strategyToTactic(jsGrind) == "grind"
  test "jsAesop → aesop":
    check strategyToTactic(jsAesop) == "aesop"
  test "jsLlmFallback → sorry":
    check strategyToTactic(jsLlmFallback) == "sorry"

# ──────────────────────────────────────────────────────────────────────────────
# GoalShapeCache LRU — hit, miss, eviction
# ──────────────────────────────────────────────────────────────────────────────

suite "GoalShapeCache LRU behavior":
  test "empty cache returns none on get":
    var cache = initGoalShapeCache(maxSize = 4)
    let key: GoalShapeCacheKey = (nodeId: "n1", proofAttemptCount: 0)
    let result = cacheGet(cache, key)
    check result.isNone()

  test "cache put then get returns shape":
    var cache = initGoalShapeCache(maxSize = 4)
    let key: GoalShapeCacheKey = (nodeId: "n1", proofAttemptCount: 0)
    cachePut(cache, key, gsEquality, "eq_test")
    let result = cacheGet(cache, key)
    check result.isSome()
    check result.get() == gsEquality

  test "cacheLen tracks insertion count":
    var cache = initGoalShapeCache(maxSize = 4)
    check cacheLen(cache) == 0
    cachePut(cache, ("n1", 0), gsLinearArithmetic)
    check cacheLen(cache) == 1
    cachePut(cache, ("n2", 0), gsEquality)
    check cacheLen(cache) == 2

  test "cache miss returns none for unknown key":
    var cache = initGoalShapeCache(maxSize = 4)
    cachePut(cache, ("n1", 0), gsLinearArithmetic)
    let result = cacheGet(cache, ("n2", 0))
    check result.isNone()

  test "cache eviction removes LRU entry when at capacity":
    var cache = initGoalShapeCache(maxSize = 3)
    cachePut(cache, ("n1", 0), gsLinearArithmetic)
    cachePut(cache, ("n2", 0), gsEquality)
    cachePut(cache, ("n3", 0), gsInductiveStructure)
    check cacheLen(cache) == 3
    # Access n1 to make it most recently used
    discard cacheGet(cache, ("n1", 0))
    # Insert n4 — should evict n2 (least recently used)
    cachePut(cache, ("n4", 0), gsFiniteEquality)
    check cacheLen(cache) == 3
    check cacheGet(cache, ("n1", 0)).isSome()    # n1 still present
    check cacheGet(cache, ("n2", 0)).isNone()    # n2 evicted
    check cacheGet(cache, ("n3", 0)).isSome()    # n3 still present
    check cacheGet(cache, ("n4", 0)).isSome()    # n4 inserted

  test "cache update existing key moves to front":
    var cache = initGoalShapeCache(maxSize = 3)
    cachePut(cache, ("n1", 0), gsLinearArithmetic)
    cachePut(cache, ("n2", 0), gsEquality)
    cachePut(cache, ("n3", 0), gsInductiveStructure)
    # Update n1 — should move to front
    cachePut(cache, ("n1", 0), gsGeneral)
    # Insert n4 — should evict n2 (now LRU)
    cachePut(cache, ("n4", 0), gsFiniteEquality)
    check cacheGet(cache, ("n1", 0)).get() == gsGeneral  # updated and present
    check cacheGet(cache, ("n2", 0)).isNone()             # n2 evicted

# ──────────────────────────────────────────────────────────────────────────────
# Fingerprint — FNV-1a hash with known inputs
# ──────────────────────────────────────────────────────────────────────────────

suite "fingerprint produces deterministic FNV-1a hashes":
  test "same inputs produce same hash":
    let h1 = fingerprint("omega", "type_mismatch")
    let h2 = fingerprint("omega", "type_mismatch")
    check h1 == h2

  test "different tactics produce different hashes":
    let h1 = fingerprint("omega", "type_mismatch")
    let h2 = fingerprint("decide", "type_mismatch")
    check h1 != h2

  test "different error types produce different hashes":
    let h1 = fingerprint("omega", "type_mismatch")
    let h2 = fingerprint("omega", "goal_unsolvable")
    check h1 != h2

  test "empty inputs produce valid hash":
    let h = fingerprint("", "")
    check h == 1469598103934665603'u64  # FNV offset basis (no XOR/multiply for empty)

  test "hash is non-zero for non-empty inputs":
    let h = fingerprint("rfl", "success")
    check h != 0'u64

  test "known FNV-1a computation for single char":
    # FNV-1a of "a": offset_basis XOR 'a' = 1469598103934665603 XOR 97
    # Then multiply by prime
    let expected = (1469598103934665603'u64 xor 97'u64) * 1099511628211'u64
    let h = fingerprint("a", "")
    check h == expected

# ──────────────────────────────────────────────────────────────────────────────
# TacticHistory — isDuplicate detection
# ──────────────────────────────────────────────────────────────────────────────

suite "TacticHistory deduplication":
  test "empty history has no duplicates":
    var history = initTacticHistory()
    check not isDuplicate(history, fingerprint("omega", "type_mismatch"))

  test "recorded attempt is detected as duplicate":
    var history = initTacticHistory()
    recordAttempt(history, "omega", "type_mismatch")
    let h = fingerprint("omega", "type_mismatch")
    check isDuplicate(history, h)

  test "unrecorded attempt is not a duplicate":
    var history = initTacticHistory()
    recordAttempt(history, "omega", "type_mismatch")
    let h = fingerprint("decide", "goal_unsolvable")
    check not isDuplicate(history, h)

  test "multiple distinct attempts all detected":
    var history = initTacticHistory()
    recordAttempt(history, "omega", "type_mismatch")
    recordAttempt(history, "decide", "goal_unsolvable")
    recordAttempt(history, "simp", "timeout")
    check isDuplicate(history, fingerprint("omega", "type_mismatch"))
    check isDuplicate(history, fingerprint("decide", "goal_unsolvable"))
    check isDuplicate(history, fingerprint("simp", "timeout"))
    check not isDuplicate(history, fingerprint("grind", "unknown"))

  test "duplicate detection is order-independent":
    var history = initTacticHistory()
    recordAttempt(history, "decide", "err_a")
    recordAttempt(history, "omega", "err_b")
    # Check in reverse order of recording
    check isDuplicate(history, fingerprint("omega", "err_b"))
    check isDuplicate(history, fingerprint("decide", "err_a"))

  test "history attempts seq tracks all records":
    var history = initTacticHistory()
    recordAttempt(history, "rfl", "success")
    recordAttempt(history, "omega", "fail")
    check history.attempts.len == 2
    check history.attempts[0].tactic == "rfl"
    check history.attempts[0].errorType == "success"
    check history.attempts[1].tactic == "omega"
    check history.attempts[1].errorType == "fail"

  test "fingerprint stored in attempt matches computed value":
    var history = initTacticHistory()
    recordAttempt(history, "simp", "type_error")
    let expected = fingerprint("simp", "type_error")
    check history.attempts[0].errorHash == expected

# ──────────────────────────────────────────────────────────────────────────────
# buildDoNotRepeatSection — prompt generation
# ──────────────────────────────────────────────────────────────────────────────

suite "buildDoNotRepeatSection":
  test "empty history produces empty string":
    var history = initTacticHistory()
    let section = buildDoNotRepeatSection(history)
    check section.len == 0

  test "non-empty history produces DO NOT REPEAT section":
    var history = initTacticHistory()
    recordAttempt(history, "omega", "type_mismatch")
    recordAttempt(history, "decide", "goal_unsolvable")
    let section = buildDoNotRepeatSection(history)
    check "DO NOT REPEAT" in section
    check "omega" in section
    check "decide" in section
    check "type_mismatch" in section
    check "goal_unsolvable" in section
    check "NOVEL" in section

# ──────────────────────────────────────────────────────────────────────────────
# unknownRatio — edge cases
# ──────────────────────────────────────────────────────────────────────────────

suite "unknownRatio computation":
  test "zero total returns 0.0":
    check unknownRatio(0, 0) == 0.0

  test "non-zero total with zeros":
    check unknownRatio(100, 0) == 0.0

  test "all unknown returns 1.0":
    check unknownRatio(50, 50) == 1.0

  test "partial unknown":
    let ratio = unknownRatio(100, 25)
    check ratio > 0.24
    check ratio < 0.26

# ──────────────────────────────────────────────────────────────────────────────
# analyzeUnknownGoalShapes — sample JSONL
# ──────────────────────────────────────────────────────────────────────────────

suite "analyzeUnknownGoalShapes with sample JSONL":
  test "missing file returns empty seq":
    let result = analyzeUnknownGoalShapes("/tmp/nonexistent_goal_shapes.jsonl")
    check result.len == 0

  test "empty file returns empty seq":
    let path = "/tmp/test_unknown_goals_empty.jsonl"
    var f: File
    discard open(f, path, fmWrite)
    f.close()
    let result = analyzeUnknownGoalShapes(path)
    check result.len == 0
    removeFile(path)

  test "aggregates frequencies from JSONL entries":
    let path = "/tmp/test_unknown_goals_freq.jsonl"
    var f: File
    discard open(f, path, fmWrite)
    # Write 3 entries with 2 unique names
    f.write(pretty(%*{"goalSource": "alpha_goal_xyz", "shape": "gsUnknown", "timestamp": 1000}) & "\n")
    f.write(pretty(%*{"goalSource": "beta_goal_xyz", "shape": "gsUnknown", "timestamp": 1001}) & "\n")
    f.write(pretty(%*{"goalSource": "alpha_goal_xyz", "shape": "gsUnknown", "timestamp": 1002}) & "\n")
    f.close()

    let result = analyzeUnknownGoalShapes(path)
    check result.len == 2
    # alpha appears 2x, beta appears 1x — sorted by frequency descending
    check result[0].name == "alpha_goal_xyz"
    check result[0].sampleCount == 2
    check result[1].name == "beta_goal_xyz"
    check result[1].sampleCount == 1
    removeFile(path)

  test "prefers constName over goalSource for aggregation":
    let path = "/tmp/test_unknown_goals_constname.jsonl"
    var f: File
    discard open(f, path, fmWrite)
    f.write(pretty(%*{"constName": "myFunc", "goalSource": "some_long_source", "shape": "gsUnknown"}) & "\n")
    f.write(pretty(%*{"constName": "myFunc", "goalSource": "other_source", "shape": "gsUnknown"}) & "\n")
    f.close()

    let result = analyzeUnknownGoalShapes(path)
    check result.len == 1
    check result[0].name == "myFunc"
    check result[0].sampleCount == 2
    removeFile(path)

  test "malformed JSON lines are skipped gracefully":
    let path = "/tmp/test_unknown_goals_malformed.jsonl"
    var f: File
    discard open(f, path, fmWrite)
    f.write("not valid json\n")
    f.write(pretty(%*{"goalSource": "valid_goal", "shape": "gsUnknown"}) & "\n")
    f.write("{broken json\n")
    f.close()

    let result = analyzeUnknownGoalShapes(path)
    check result.len == 1
    check result[0].name == "valid_goal"
    removeFile(path)
