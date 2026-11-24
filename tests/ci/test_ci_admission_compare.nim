## test_ci_admission_compare.nim - fixtures for tools/ci/ci_admission_compare.nim.
##
## NO network, NO subprocess, NO live repository state: the comparator's pure core
## is imported directly and every CLI case drives `runCli` in-process against
## synthetic snapshot files. Each group pins one property that the design's
## validation run established against the reference implementation:
##
##   * the exact Mann-Whitney null has the closed forms it must have: the counts
##     sum to C(n1+n2, n1), the distribution is symmetric, perfect separation
##     gives U = 0 and p = 2/C(n1+n2, n1);
##   * Hodges-Lehmann is the exact median of the pairwise differences on a
##     hand-checkable case;
##   * the cohort gate refuses an overlapping pair and a same-boundary pair,
##     because a p-value over a re-sampled population is pseudo-replication;
##   * headroom is derived from the snapshot alone, and a shared top instant is
##     TIE_AT_MAX with zero headroom rather than a fabricated gap;
##   * the fixed-LCG bootstrap reports UNINFORMATIVE exactly where its resample
##     median support is degenerate, and INFORMATIVE where it is not;
##   * the pre-registered rule never promotes an approximate p, and never reads a
##     null result as evidence of no change while the sample is underpowered.

import std/[algorithm, json, math, os, strutils, unittest]

import ../../tools/ci/ci_admission_compare

# ---------------------------------------------------------------------------
# Fixture constructors
# ---------------------------------------------------------------------------

const
  BoundaryA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  BoundaryB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  SlicePath = ".github/workflows/axiom-operational-slice.yml"
  VerdictPath = ".github/workflows/admission-gate-v2.yml"
  PubPath = ".github/workflows/publication-integrity.yml"

func sha(prefix: string; i: int): string =
  prefix & align($i, 40 - prefix.len, '0')

func checkRow(context, workflowPath, completedAt: string; bound = true): CheckRow =
  CheckRow(context: context, workflowPath: workflowPath, completedAt: completedAt,
           bound: bound)

func candidate(pr: int; headSha: string; admission: int;
               checks: seq[CheckRow]): CandidateRow =
  result = CandidateRow(prNumber: pr, headSha: headSha, lastFinisher: "",
                        checks: checks)
  for k in PhaseKey:
    result.phaseSeconds[k] = -1
  result.phaseSeconds[pkQueue] = 10
  result.phaseSeconds[pkMerge] = 20
  result.phaseSeconds[pkVerify] = admission - 30
  result.phaseSeconds[pkPublication] = 0
  result.phaseSeconds[pkReady] = admission - 20
  result.phaseSeconds[pkAdmission] = admission

func snapshot(name, boundary: string; rows: seq[CandidateRow];
              cohortN = 0): Snapshot =
  result = Snapshot(path: name, repo: "Archright/Axiom", boundary: boundary,
                    boundarySource: (if boundary.len > 0: "top-level:boundary"
                                     else: "ABSENT"),
                    cohortSource: name & ":cohort")
  result.observed = rows
  for r in rows:
    result.headShas.add r.headSha
  result.cohortN = if cohortN > 0: cohortN else: rows.len
  result.observedN = rows.len
  result.unknownN = max(0, result.cohortN - rows.len)

# A snapshot with `n` observed candidates whose admission seconds are `values`.
func cohort(name, boundary, shaPrefix: string; values: seq[int]): Snapshot =
  var rows: seq[CandidateRow] = @[]
  for i, v in values:
    rows.add candidate(900 + i, sha(shaPrefix, i), v,
      @[checkRow("readiness-verdict", SlicePath, "2026-11-23T14:10:00Z"),
        checkRow("admission-check", VerdictPath, "2026-11-23T14:09:00Z"),
        checkRow("publication-integrity", PubPath, "2026-11-23T14:08:00Z")])
  snapshot(name, boundary, rows)

proc writeTemp(dir, name: string; node: JsonNode): string =
  result = dir / name
  writeFile(result, $node)

func observeNode(name, boundary, shaPrefix: string; values: seq[int]): JsonNode =
  ## The real `axiom.ci_admission_observe.v1` shape: phases carry only
  ## queue/verify/publication/merge, and ready_seconds / admission_seconds are
  ## top-level candidate fields.
  var cands = newJArray()
  var shas = newJArray()
  for i, v in values:
    let h = sha(shaPrefix, i)
    shas.add %h
    cands.add %*{
      "pr_number": 900 + i,
      "head_sha": h,
      "queue_ref": "gh-readonly-queue/main/pr-" & $(900 + i) & "-" & h[0 .. 7],
      "queue_entry_at": "2026-11-23T14:00:00Z",
      "merged_at": "2026-11-23T14:11:00Z",
      "merge_commit": h,
      "outcome": "OBSERVED",
      "unknown_reason": "",
      "phases": [
        %*{"name": "queue", "start_at": "2026-11-23T14:00:00Z",
           "end_at": "2026-11-23T14:00:10Z", "seconds": 10},
        %*{"name": "verify", "start_at": "2026-11-23T14:00:10Z",
           "end_at": "2026-11-23T14:09:40Z", "seconds": v - 30},
        %*{"name": "publication", "start_at": "2026-11-23T14:09:40Z",
           "end_at": "2026-11-23T14:09:40Z", "seconds": 0},
        %*{"name": "merge", "start_at": "2026-11-23T14:09:40Z",
           "end_at": "2026-11-23T14:11:00Z", "seconds": 20}
      ],
      "ready_seconds": v - 20,
      "admission_seconds": v,
      "last_finisher": "readiness-verdict",
      "checks": [
        %*{"context": "readiness-verdict", "workflow_path": SlicePath,
           "is_app_verdict": false, "expected_app_id": 15368,
           "observed_app_id": 15368, "check_run_id": "1", "check_suite_id": "2",
           "workflow_run_id": "3", "run_attempt": 1, "status": "completed",
           "conclusion": "success", "started_at": "2026-11-23T14:00:20Z",
           "completed_at": "2026-11-23T14:09:40Z", "bound": true,
           "unbound_reason": ""},
        %*{"context": "admission-check", "workflow_path": VerdictPath,
           "is_app_verdict": true, "expected_app_id": 5795152,
           "observed_app_id": 5795152, "check_run_id": "4", "check_suite_id": "5",
           "workflow_run_id": "", "run_attempt": 0, "status": "completed",
           "conclusion": "success", "started_at": "2026-11-23T14:09:37Z",
           "completed_at": "2026-11-23T14:09:39Z", "bound": true,
           "unbound_reason": ""},
        %*{"context": "publication-integrity", "workflow_path": PubPath,
           "is_app_verdict": false, "expected_app_id": 15368,
           "observed_app_id": 15368, "check_run_id": "6", "check_suite_id": "7",
           "workflow_run_id": "8", "run_attempt": 1, "status": "completed",
           "conclusion": "success", "started_at": "2026-11-23T14:05:00Z",
           "completed_at": "2026-11-23T14:09:30Z", "bound": true,
           "unbound_reason": ""}
      ]
    }
  %*{
    "schema_version": "axiom.ci_admission_observe.v1",
    "tool": "ci_admission_observe",
    "repo": "Archright/Axiom",
    "policy_path": "config/policy/merge_admission.json",
    "estimators": {"p50": "canonical", "p90": "hyndman-fan-7"},
    "boundary": boundary,
    "cohort": {"source": name, "n": values.len, "head_shas": shas,
               "pr_numbers": (block:
                 var prs = newJArray()
                 for i in 0 ..< values.len:
                   prs.add %(900 + i)
                 prs)},
    "binding": {},
    "authority": {"context_sets_equal": true},
    "observed_n": values.len,
    "unknown_n": 0,
    "phase_stats": {},
    "last_finisher_counts": {"readiness-verdict": values.len},
    "candidates": cands
  }

let Work = getTempDir() / "axiom_ci_admission_compare_test"

proc ensureWork() =
  createDir(Work)

# ---------------------------------------------------------------------------
# 1. The exact U null distribution
# ---------------------------------------------------------------------------

suite "exact Mann-Whitney null distribution":

  test "the counts sum to C(n1+n2, n1) for every tested n":
    # This is the identity validate_stats.py checks against math.comb; it is the
    # whole correctness argument for the DP, so it is asserted directly.
    for pair in [(3, 3), (4, 4), (5, 5), (8, 8), (10, 10)]:
      let (ok, counts, total) = exactUDistribution(pair[0], pair[1])
      check ok
      check counts.len == pair[0] * pair[1] + 1
      var summed = 0'u64
      for c in counts:
        summed += c
      check summed == total
      let (expect, ovf) = binomialBounded(pair[0] + pair[1], pair[0], high(uint64))
      check not ovf
      check total == expect

  test "C(40,20) is exact and fits uint64, as the reference reports":
    # The design cites C(40,20) = 137846528820 as the load-bearing value: if it
    # fit, no n in the practical range can overflow the DP.
    let (v, ovf) = binomialBounded(40, 20, high(uint64))
    check not ovf
    check v == 137846528820'u64
    let (ok, counts, total) = exactUDistribution(20, 20)
    check ok
    check total == 137846528820'u64
    check counts.len == 401

  test "the distribution is symmetric about n1*n2/2":
    for pair in [(3, 3), (8, 8), (10, 10)]:
      let (ok, counts, _) = exactUDistribution(pair[0], pair[1])
      check ok
      let hi = pair[0] * pair[1]
      for u in 0 .. hi:
        check counts[u] == counts[hi - u]

  test "the counts are strictly increasing up to the centre":
    # A weak monotonicity check that a transposed or mis-shifted DP would break.
    let (ok, counts, _) = exactUDistribution(8, 8)
    check ok
    for u in 0 ..< 32:
      check counts[u] <= counts[u + 1]

  test "overflow is reported rather than wrapped":
    # C(200,100) exceeds uint64, so the DP must decline instead of producing a
    # silently truncated null.
    let (_, ovf) = binomialBounded(200, 100, high(uint64))
    check ovf
    let (ok2, counts2, total2) = exactUDistribution(200, 100)
    check not ok2
    check counts2.len == 0
    check total2 == 0'u64

  test "a degenerate n is refused, never treated as an empty null":
    check not exactUDistribution(0, 5)[0]
    check not exactUDistribution(5, 0)[0]
    check not exactUDistribution(-1, 5)[0]

# ---------------------------------------------------------------------------
# 2. Midranks and the U statistic
# ---------------------------------------------------------------------------

suite "midranks and U":

  test "doubled midranks keep a half rank exact":
    # Ranks 1..4 with a tie across 2 and 3 -> midrank 2.5 -> doubled 5.
    check doubledMidranks(@[10, 20, 20, 40]) == @[2'i64, 5'i64, 5'i64, 8'i64]
    check doubledMidranks(@[7]) == @[2'i64]
    check doubledMidranks(newSeq[int]()) == newSeq[int64]()

  test "doubled midranks are order-independent":
    let a = doubledMidranks(@[40, 10, 20, 20])
    check a == @[8'i64, 2'i64, 5'i64, 5'i64]

  test "U is 0 under perfect separation and n1*n2 under full reversal":
    let x = @[1, 2, 3, 4, 5, 6]
    let y = @[7, 8, 9, 10, 11, 12]
    check uDoubled(x, y) == 0'i64
    check uDoubled(y, x) == 72'i64

  test "U never exceeds n1*n2":
    let x = @[1, 5, 9, 13]
    let y = @[2, 6, 10, 14]
    let u = uDoubled(x, y)
    check u >= 0'i64
    check u <= 32'i64

# ---------------------------------------------------------------------------
# 3. Exact two-sided p-value
# ---------------------------------------------------------------------------

suite "exact p-value":

  test "perfect separation gives p = 2/C(n1+n2, n1)":
    for pair in [(3, 3), (6, 6)]:
      let n1 = pair[0]
      let n2 = pair[1]
      var x: seq[int] = @[]
      var y: seq[int] = @[]
      for i in 0 ..< n1:
        x.add 1 + i
      for i in 0 ..< n2:
        y.add 1 + n1 + i
      let mw = mannWhitney(x, y)
      check mw.exact
      check mw.methodName == "exact-u-dp"
      check mw.uDoubled == 0'i64
      let comb = binomialBounded(n1 + n2, n1, high(uint64)).value
      check mw.pExact == fractionString(2'u64, comb)
      check abs(mw.p - 2.0 / float(comb)) < 1e-12

  test "perfect separation at 3 vs 3 is exactly 1/10":
    # C(6,3) = 20, so 2/20 = 1/10 after reduction. This is the smallest case
    # where the exact tail is checkable by hand.
    let mw = mannWhitney(@[1, 2, 3], @[4, 5, 6])
    check mw.pExact == "1/10"

  test "full reversal has the same p as perfect separation":
    let forward = mannWhitney(@[1, 2, 3, 4, 5, 6], @[7, 8, 9, 10, 11, 12])
    let reversed = mannWhitney(@[7, 8, 9, 10, 11, 12], @[1, 2, 3, 4, 5, 6])
    check forward.pExact == reversed.pExact
    check reversed.uDoubled == 72'i64

  test "an identical pair of samples is not significant":
    let mw = mannWhitney(@[10, 20, 30, 40], @[10, 20, 30, 40])
    check mw.exact
    check mw.p > 0.9

  test "the p-value is a probability":
    let mw = mannWhitney(@[5, 9, 12, 20, 21], @[6, 7, 30, 31])
    check mw.p >= 0.0
    check mw.p <= 1.0

  test "an empty arm is degenerate, not significant":
    let mw = mannWhitney(@[], @[1, 2, 3])
    check not mw.exact
    check mw.p == 1.0
    check mw.methodName == "degenerate-empty-arm"

# ---------------------------------------------------------------------------
# 4. Ties
# ---------------------------------------------------------------------------

suite "ties":

  test "tie groups are counted from the pooled sample":
    let info = tieInfo(@[1, 2, 2, 3], @[2, 4])
    check info.tieGroups == 1
    check info.tiedValues == 3

  test "no ties is reported as zero groups":
    let info = tieInfo(@[1, 3, 5], @[2, 4, 6])
    check info.tieGroups == 0
    check info.tiedValues == 0

  test "a tied small case still yields an exact p, labelled as permutation":
    # With ties the no-tie DP null is invalid; the comparator must switch to the
    # exact permutation over label splits rather than reuse the DP.
    let mw = mannWhitney(@[1, 2, 2, 3], @[2, 3, 3, 4])
    check mw.exact
    check mw.methodName == "exact-permutation-midrank"
    check mw.p > 0.0
    check mw.p <= 1.0
    check mw.pExact != NotExact

  test "ties with a midrank U stay inside the feasible range":
    let mw = mannWhitney(@[1, 2, 2, 2, 3], @[2, 2, 4, 4, 5])
    check mw.uDoubled >= 0'i64
    check mw.uDoubled <= 50'i64

  test "a large tied sample falls back and says so":
    # n1+n2 = 30 with heavy ties: C(30,15) = 155117520 exceeds the enumeration cap,
    # so the exact permutation is not attempted and `exact` must be false.
    var x: seq[int] = @[]
    var y: seq[int] = @[]
    for i in 0 ..< 15:
      x.add 100 + (i mod 5)
      y.add 100 + ((i + 2) mod 5)
    let mw = mannWhitney(x, y)
    check not mw.exact
    check mw.methodName == "tie-corrected-normal"
    check mw.pExact == NotExact
    check mw.p >= 0.0
    check mw.p <= 1.0

# ---------------------------------------------------------------------------
# 5. Hodges-Lehmann
# ---------------------------------------------------------------------------

suite "Hodges-Lehmann":

  test "the hand-checkable case is exactly 5":
    # validate_stats.py: x=[10,20,30], y=[15,25,35] -> all pairwise differences
    # are {5,15,25} x {.,.} = the 9 values below, whose median is 5.
    let diffs = @[5, 15, 25, -5, 5, 15, -15, -5, 5]
    check diffs.len == 9
    check hodgesLehmann(@[10, 20, 30], @[15, 25, 35]) == 5.0
    check hodgesLehmannDoubled(@[10, 20, 30], @[15, 25, 35]) == 10'i64

  test "an even number of differences yields an exact half-integer":
    # 2x2 differences {1, 3, 2, 4} -> median (2+3)/2 = 2.5.
    check hodgesLehmann(@[10, 20], @[11, 24]) == 2.5
    check hodgesLehmannDoubled(@[10, 20], @[11, 24]) == 5'i64

  test "a pure shift is recovered exactly":
    check hodgesLehmann(@[100, 110, 120], @[140, 150, 160]) == 40.0

  test "no shift is zero":
    check hodgesLehmann(@[5, 6, 7], @[5, 6, 7]) == 0.0

  test "an empty arm is not a shift":
    check hodgesLehmann(@[], @[1, 2]) == 0.0
    check hodgesLehmann(@[1, 2], @[]) == 0.0

# ---------------------------------------------------------------------------
# 6. Spread
# ---------------------------------------------------------------------------

suite "spread":

  test "sd and variance use the sample denominator":
    # sample variance of [1,2,3,4] = 5/3, sd = sqrt(5/3).
    let s = spreadOf(@[1, 2, 3, 4])
    check s.n == 4
    check abs(s.variance - 5.0 / 3.0) < 1e-12
    check abs(s.sd - sqrt(5.0 / 3.0)) < 1e-12
    check s.rangeSeconds == 3
    check s.minSeconds == 1
    check s.maxSeconds == 4

  test "a single value has no spread, not a zero variance claim":
    let s = spreadOf(@[42])
    check s.n == 1
    check s.variance == 0.0
    check s.sd == 0.0
    check s.rangeSeconds == 0

  test "an empty array reports nothing rather than zero":
    let s = spreadOf(@[])
    check s.n == 0
    check s.minSeconds == -1
    check s.maxSeconds == -1

  test "p95 is INCOMPLETE below n=20 and reported at n=20":
    var small: seq[int] = @[]
    for i in 0 ..< 19:
      small.add 100 + i
    check spreadOf(small).p95Status == P95Incomplete
    var big: seq[int] = @[]
    for i in 0 ..< 20:
      big.add 100 + i
    let s = spreadOf(big)
    check s.p95Status == "REPORTED"
    check s.p95 > s.p50

  test "IQR uses the same estimator family as p50":
    # r7(0.75) - r7(0.25) on 1..9: r7(0.25)=3, r7(0.75)=7.
    check spreadOf(@[1, 2, 3, 4, 5, 6, 7, 8, 9]).iqr == 4.0

# ---------------------------------------------------------------------------
# 7. Minimum detectable effect and AUC
# ---------------------------------------------------------------------------

suite "minimum detectable effect":

  test "the n=8 threshold matches the design table":
    # DESIGN.md section 7: at n=8/arm the smallest detectable |U-n^2/2| is 19 of
    # 64, i.e. a detectable AUC of 0.203125.
    let m = minDetectableEffect(8, 8, 0.05)
    check m.computed
    check m.minAbsUDev == 19.0
    check abs(m.detectableAuc - 0.203125) < 1e-12

  test "the table is reproduced for the other cited n":
    check minDetectableEffect(10, 10, 0.05).minAbsUDev == 27.0
    check minDetectableEffect(20, 20, 0.05).minAbsUDev == 73.0
    check minDetectableEffect(30, 30, 0.05).minAbsUDev == 133.0

  test "a smaller n cannot detect a smaller effect":
    # The threshold is monotone in n; if it were not, the power gate would be
    # meaningless.
    var previous = 0.0
    for n in [6, 8, 10, 13, 20]:
      let v = minDetectableEffect(n, n, 0.05).minAbsUDev
      check v >= previous
      previous = v

  test "POWERED requires the observed separation to reach the threshold":
    var m = minDetectableEffect(8, 8, 0.05)
    check m.verdict == VerdictUnderpowered
    m.applyObservedEffect(30'i64)   # |2U - n^2| = 30 < 38 = 2*19
    check m.verdict == VerdictUnderpowered
    m.applyObservedEffect(38'i64)
    check m.verdict == VerdictPowered

  test "a degenerate n produces no threshold, never zero":
    let m = minDetectableEffect(0, 8, 0.05)
    check not m.computed
    check m.minAbsUDev == -1.0
    check m.verdict == VerdictUnderpowered

# ---------------------------------------------------------------------------
# 8. Deterministic LCG bootstrap
# ---------------------------------------------------------------------------

suite "bootstrap":

  test "the LCG is the documented recurrence":
    check nextLcg(0) == 12345
    check nextLcg(20261124) == (1103515245'i64 * 20261124'i64 + 12345'i64) mod 2147483648'i64
    # Every state stays inside [0, 2^31).
    var s = 20261124'i64
    for _ in 0 ..< 100:
      s = nextLcg(s)
      check s >= 0'i64
      check s < 2147483648'i64

  test "the CI is a pure function of (x, y, reps, seed)":
    let x = @[100, 120, 140, 160, 180, 200]
    let y = @[110, 130, 150, 170, 190, 210]
    let a = bootstrapMedianCi(x, y, 500, DefaultSeed, 0.05)
    let b = bootstrapMedianCi(x, y, 500, DefaultSeed, 0.05)
    check a.point == b.point
    check a.ciLow == b.ciLow
    check a.ciHigh == b.ciHigh
    check a.status == b.status
    # A different seed must move the interval: otherwise the seed is decorative.
    let c = bootstrapMedianCi(x, y, 500, DefaultSeed + 1, 0.05)
    check c.ciLow != a.ciLow or c.ciHigh != a.ciHigh

  test "n=8 with separated ranges is UNINFORMATIVE, not a narrow interval":
    # This is the degeneracy the design documents: at n=8 the resampled median
    # support collapses, so a zero-width CI must be labelled as carrying no
    # information rather than printed as high confidence.
    let pre = @[880, 910, 940, 965, 990, 1015, 1040, 1070]
    let post = @[570, 588, 602, 639, 660, 707, 718, 755]
    let b = bootstrapMedianCi(pre, post, 2000, DefaultSeed, 0.05)
    check b.status == StatusUninformative
    check b.distinctMedianCount < 3
    check b.width == 0.0
    check b.point == -328.0

  test "an n=12 spread cohort is INFORMATIVE":
    # same n as the fixture in the design dry run, but a wider support: the
    # resample median is no longer degenerate.
    var x: seq[int] = @[]
    var y: seq[int] = @[]
    for i in 0 ..< 12:
      x.add 300 + 10 * i
      y.add 250 + 10 * i
    let b = bootstrapMedianCi(x, y, 2000, DefaultSeed, 0.05)
    check b.status == StatusInformative
    check b.distinctMedianCount >= 3
    check b.width > 0.0
    check b.ciLow <= b.point
    check b.ciHigh >= b.point

  test "a degenerate arm yields no CI":
    let b = bootstrapMedianCi(@[], @[1, 2, 3], 100, DefaultSeed, 0.05)
    check b.status == StatusUninformative
    check b.distinctMedianCount == 0

  test "reps below 1 is refused rather than returning a point interval":
    check bootstrapMedianCi(@[1, 2], @[3, 4], 0, DefaultSeed, 0.05).status ==
      StatusUninformative

# ---------------------------------------------------------------------------
# 9. Cohort validity gate
# ---------------------------------------------------------------------------

suite "cohort validity":

  test "disjoint head_sha sets are VALID":
    let a = cohort("pre", BoundaryA, "pre", @[100, 200, 300])
    let b = cohort("post", BoundaryB, "post", @[110, 210, 310])
    let v = cohortValidity(a, b)
    check v.verdict == cvValid
    check v.disjoint
    check v.shared.len == 0
    check v.boundaryCheck == "COMPARED"

  test "an identical boundary is SAME_BOUNDARY_REFUSED even without overlap":
    # Same boundary proves one population regardless of the head lists, so this
    # check must fire before the overlap check.
    let a = cohort("pre", BoundaryA, "pre", @[100, 200, 300])
    let b = cohort("post", BoundaryA, "post", @[110, 210, 310])
    let v = cohortValidity(a, b)
    check v.verdict == cvSameBoundaryRefused
    check v.sameBoundary
    check not v.disjoint
    check "pseudo-replication" in v.reason

  test "shared head_shas are OVERLAP_REFUSED":
    var rows: seq[CandidateRow] = @[]
    for i, v in [100, 200, 300]:
      rows.add candidate(900 + i, sha("same", i), v, @[])
    let a = snapshot("pre", BoundaryA, rows)
    # Same SHAs, different boundary and different values: the overlap gate must
    # still refuse, because pseudo-replication is about identity, not timing.
    var rowsB: seq[CandidateRow] = @[]
    for i, v in [50, 150, 250]:
      rowsB.add candidate(910 + i, sha("same", i), v, @[])
    let b = snapshot("post", BoundaryB, rowsB)
    let v = cohortValidity(a, b)
    check v.verdict == cvOverlapRefused
    check v.shared.len == 3
    check v.preSubsetOfPost
    check not v.disjoint
    check "shared candidates would be counted in both arms" in v.reason

  test "partial overlap is still refused, and only the shared set is reported":
    var rowsA: seq[CandidateRow] = @[]
    for i in 0 ..< 3:
      rowsA.add candidate(900 + i, sha("sh", i), 100 + i, @[])
    var rowsB: seq[CandidateRow] = @[]
    for i in 2 ..< 5:
      rowsB.add candidate(910 + i, sha("sh", i), 200 + i, @[])
    let v = cohortValidity(snapshot("pre", BoundaryA, rowsA),
                           snapshot("post", BoundaryB, rowsB))
    check v.verdict == cvOverlapRefused
    check v.shared.len == 1
    check v.shared[0] == sha("sh", 2)

  test "the subset relation is recorded in both directions":
    var rowsA: seq[CandidateRow] = @[]
    rowsA.add candidate(1, sha("s", 0), 100, @[])
    var rowsB: seq[CandidateRow] = @[]
    for i in 0 ..< 3:
      rowsB.add candidate(10 + i, sha("s", i), 200, @[])
    let v = cohortValidity(snapshot("pre", BoundaryA, rowsA),
                          snapshot("post", BoundaryB, rowsB))
    check v.preSubsetOfPost
    check not v.postSubsetOfPre

  test "absent boundary refs are recorded as UNKNOWN, not silently compared":
    let a = cohort("pre", "", "pre", @[100, 200])
    let b = cohort("post", "", "post", @[110, 210])
    let v = cohortValidity(a, b)
    check v.boundaryCheck == "UNKNOWN_BOTH_ABSENT"
    check not v.sameBoundary
    check v.verdict == cvValid

  test "one absent boundary ref is recorded as one-sided UNKNOWN":
    let a = cohort("pre", BoundaryA, "pre", @[100, 200])
    let b = cohort("post", "", "post", @[110, 210])
    check cohortValidity(a, b).boundaryCheck == "UNKNOWN_POST_ABSENT"
    check cohortValidity(b, a).boundaryCheck == "UNKNOWN_PRE_ABSENT"

# ---------------------------------------------------------------------------
# 10. Set algebra
# ---------------------------------------------------------------------------

suite "set algebra":

  test "sortedUnique sorts and de-duplicates":
    check sortedUnique(@["b", "a", "b"]) == @["a", "b"]
    check sortedUnique(@[]) == newSeq[string]()

  test "sharedOf intersects sorted unique inputs":
    check sharedOf(@["a", "c", "e"], @["b", "c", "e"]) == @["c", "e"]
    check sharedOf(@["a"], @["b"]) == newSeq[string]()
    check sharedOf(newSeq[string](), @["b"]) == newSeq[string]()

  test "isSubsetOf is vacuously true for an empty left side":
    check isSubsetOf(@["a"], @["a", "b"])
    check isSubsetOf(@[], @["a"])
    check not isSubsetOf(@["c"], @["a", "b"])

# ---------------------------------------------------------------------------
# 11. Headroom
# ---------------------------------------------------------------------------

suite "headroom":

  test "second_last_finisher and headroom_second on a clean timeline":
    # readiness-verdict finishes last at 14:10:00, admission-check 3s earlier.
    let checks = @[
      checkRow("readiness-verdict", SlicePath, "2026-11-23T14:10:00Z"),
      checkRow("admission-check", VerdictPath, "2026-11-23T14:09:57Z"),
      checkRow("publication-integrity", PubPath, "2026-11-23T14:08:00Z")]
    let r = deriveHeadroom(416, "sha", checks)
    check r.status == StatusObserved
    check r.lastFinisher == "readiness-verdict"
    check r.secondLastFinisher == "admission-check"
    check r.headroomSecond == 3
    check r.slowestIndependent == "admission-check"
    check r.headroomIndependent == 3
    check not r.tieAtMax

  test "headroom_independent skips contexts in the last finisher's workflow":
    # generation-acceptance shares the slice workflow, so it is treated as
    # possibly DAG-coupled and must be skipped even though it finishes second.
    let checks = @[
      checkRow("readiness-verdict", SlicePath, "2026-11-23T14:10:00Z"),
      checkRow("generation-acceptance", SlicePath, "2026-11-23T14:09:50Z"),
      checkRow("admission-check", VerdictPath, "2026-11-23T14:09:00Z")]
    let r = deriveHeadroom(423, "sha", checks)
    check r.secondLastFinisher == "generation-acceptance"
    check r.headroomSecond == 10
    check r.slowestIndependent == "admission-check"
    check r.headroomIndependent == 60

  test "no different-workflow context leaves headroom_independent UNKNOWN":
    let checks = @[
      checkRow("readiness-verdict", SlicePath, "2026-11-23T14:10:00Z"),
      checkRow("generation-acceptance", SlicePath, "2026-11-23T14:09:50Z")]
    let r = deriveHeadroom(1, "sha", checks)
    check r.status == StatusObserved
    check r.headroomSecond == 10
    check r.headroomIndependent == -1
    check r.slowestIndependent.len == 0
    check "no context from a different workflow_path" in r.reason

  test "a shared top instant is TIE_AT_MAX with zero headroom":
    # Two contexts finish at the same instant: freeing one saves nothing, so the
    # honest answer is 0 with the tie recorded, not the gap to a third context.
    # The runner-up stays the second element of the ascending (completed_at,
    # context) order, which is the other tied context here.
    let checks = @[
      checkRow("readiness-verdict", SlicePath, "2026-11-23T14:10:00Z"),
      checkRow("admission-check", VerdictPath, "2026-11-23T14:10:00Z"),
      checkRow("publication-integrity", PubPath, "2026-11-23T14:05:00Z")]
    let r = deriveHeadroom(7, "sha", checks)
    check r.tieAtMax
    check r.tiedCount == 2
    check r.headroomSecond == 0
    check r.headroomIndependent == 0
    check r.secondLastFinisher == "admission-check"

  test "the tie-break names the lexicographically smallest tied context":
    # Matches the observer's lastFinisher convention, so the derived row cannot
    # disagree with the snapshot's own last_finisher field.
    let checks = @[
      checkRow("zeta", SlicePath, "2026-11-23T14:10:00Z"),
      checkRow("alpha", VerdictPath, "2026-11-23T14:10:00Z")]
    let r = deriveHeadroom(8, "sha", checks)
    check r.lastFinisher == "alpha"
    check r.tieAtMax

  test "fewer than two bound completions is UNKNOWN":
    let one = @[checkRow("readiness-verdict", SlicePath, "2026-11-23T14:10:00Z")]
    let r = deriveHeadroom(1, "sha", one)
    check r.status == StatusUnknown
    check r.headroomSecond == -1
    check "fewer than two bound checks" in r.reason

    let unbound = @[
      checkRow("a", SlicePath, "2026-11-23T14:10:00Z", bound = false),
      checkRow("b", VerdictPath, "2026-11-23T14:09:00Z", bound = false)]
    check deriveHeadroom(2, "sha", unbound).status == StatusUnknown

  test "a timestamp-less bound check is invisible to the derivation":
    let checks = @[
      checkRow("readiness-verdict", SlicePath, "2026-11-23T14:10:00Z"),
      checkRow("admission-check", VerdictPath, ""),
      checkRow("publication-integrity", PubPath, "2026-11-23T14:08:00Z")]
    let r = deriveHeadroom(3, "sha", checks)
    check r.secondLastFinisher == "publication-integrity"
    check r.headroomSecond == 120

  test "a last finisher with no workflow_path leaves independence UNKNOWN":
    # Without a workflow path the exclusion rule has nothing to exclude, so the
    # independent headroom cannot be established and must fail closed.
    let checks = @[
      checkRow("readiness-verdict", "", "2026-11-23T14:10:00Z"),
      checkRow("admission-check", VerdictPath, "2026-11-23T14:09:00Z")]
    let r = deriveHeadroom(4, "sha", checks)
    check r.status == StatusUnknown
    check r.headroomSecond == 60
    check r.headroomIndependent == -1
    check "independence is unprovable" in r.reason

  test "summarizeHeadroom reports n, p50, min, max and the unknown count":
    var rows: seq[HeadroomRow] = @[]
    for v in [3, 104, 41]:
      rows.add HeadroomRow(prNumber: 1, headSha: "s", status: StatusObserved,
                           headroomSecond: v, headroomIndependent: v,
                           tieAtMax: false, tiedCount: 1)
    rows.add HeadroomRow(prNumber: 2, headSha: "t", status: StatusUnknown,
                         headroomSecond: -1, headroomIndependent: -1)
    let s = summarizeHeadroom(rows, false)
    check s.n == 3
    check s.minSeconds == 3
    check s.maxSeconds == 104
    check s.p50 == 41.0
    check s.unknownN == 1
    check s.tieAtMaxN == 0

  test "second_last_finisher counts are aggregated by context":
    var rows: seq[HeadroomRow] = @[]
    rows.add HeadroomRow(secondLastFinisher: "admission-check")
    rows.add HeadroomRow(secondLastFinisher: "admission-check")
    rows.add HeadroomRow(secondLastFinisher: "publication-integrity")
    let counts = countKeys(secondLastOf(rows))
    check counts.len == 2
    check counts[0].key == "admission-check"
    check counts[0].count == 2
    check counts[1].key == "publication-integrity"

# ---------------------------------------------------------------------------
# 12. Pre-registered significance rule
# ---------------------------------------------------------------------------

func mwExact(p: float; u: float): MwResult =
  MwResult(n1: 8, n2: 8, u: u, p: p, pExact: "1/100", exact: true,
           methodName: "exact-u-dp")

func mwInexact(p: float): MwResult =
  MwResult(n1: 8, n2: 8, u: 30.0, p: p, pExact: NotExact, exact: false,
           methodName: "tie-corrected-normal")

func mdePowered(): MdeResult =
  MdeResult(n1: 8, n2: 8, alpha: 0.05, minAbsUDoubled: 38, minAbsUDev: 19.0,
            detectableAuc: 0.203125, verdict: VerdictPowered, computed: true)

func mdeUnderpowered(): MdeResult =
  MdeResult(n1: 8, n2: 8, alpha: 0.05, minAbsUDoubled: 38, minAbsUDev: 19.0,
            detectableAuc: 0.203125, verdict: VerdictUnderpowered, computed: true)

suite "pre-registered rule":

  test "an invalid cohort is REFUSED regardless of p":
    let d = preRegisteredVerdict(cvOverlapRefused, mwExact(0.0001, 0.0),
                                 mdePowered(), 8, 8, 0.05)
    check d.verdict == tvRefused
    check "cohort gate" in d.reason
    let d2 = preRegisteredVerdict(cvSameBoundaryRefused, mwExact(0.0001, 0.0),
                                  mdePowered(), 8, 8, 0.05)
    check d2.verdict == tvRefused

  test "an arm below the sample floor is INCONCLUSIVE even at p=0":
    let d = preRegisteredVerdict(cvValid, mwExact(0.0, 0.0), mdePowered(), 7, 8, 0.05)
    check d.verdict == tvInconclusive
    check "sample floor" in d.reason

  test "an exact p at or below alpha is SIGNIFICANT":
    let d = preRegisteredVerdict(cvValid, mwExact(0.05, 0.0), mdePowered(), 8, 8, 0.05)
    check d.verdict == tvSignificant

  test "an approximate p is never promoted, even when it is tiny":
    # The pre-registered primary test is exact; an approximation entering the
    # decision would make the rule unfalsifiable.
    let d = preRegisteredVerdict(cvValid, mwInexact(1e-9), mdePowered(), 8, 8, 0.05)
    check d.verdict == tvInconclusive
    check "exact null unavailable" in d.reason

  test "a null result while underpowered is INCONCLUSIVE, not 'no change'":
    let d = preRegisteredVerdict(cvValid, mwExact(0.42, 30.0), mdeUnderpowered(), 8, 8, 0.05)
    check d.verdict == tvInconclusive
    check "absence of evidence" in d.reason

  test "a null result while powered is NOT_SIGNIFICANT":
    let d = preRegisteredVerdict(cvValid, mwExact(0.42, 30.0), mdePowered(), 8, 8, 0.05)
    check d.verdict == tvNotSignificant

  test "every reachable verdict is one of the four declared values":
    let seen = [tvSignificant, tvNotSignificant, tvInconclusive, tvRefused]
    check seen.len == 4
    check $tvRefused == "REFUSED"
    check $tvSignificant == "SIGNIFICANT"
    check $tvNotSignificant == "NOT_SIGNIFICANT"
    check $tvInconclusive == "INCONCLUSIVE"

# ---------------------------------------------------------------------------
# 13. Snapshot parsing
# ---------------------------------------------------------------------------

suite "snapshot parsing":

  test "the real observe shape parses, with the top-level totals preserved":
    let (ok, snap, err) = parseSnapshot(
      observeNode("n", BoundaryA, "pre", @[600, 610, 620]), "fixture.json")
    check ok
    check err.len == 0
    check snap.boundary == BoundaryA
    check snap.boundarySource == "top-level:boundary"
    check snap.cohortN == 3
    check snap.observedN == 3
    check snap.observed.len == 3
    check snap.observed[0].phaseSeconds[pkAdmission] == 600
    check snap.observed[0].phaseSeconds[pkReady] == 580
    check snap.observed[0].phaseSeconds[pkVerify] == 570
    check snap.observed[0].checks.len == 3
    check snap.observed[0].checks[0].bound

  test "a wrong schema version is a refusal, not a best-effort parse":
    var node = observeNode("n", BoundaryA, "pre", @[600])
    node["schema_version"] = %"axiom.ci_admission_observe.v2"
    let (ok, _, err) = parseSnapshot(node, "x.json")
    check not ok
    check "axiom.ci_admission_observe.v2" in err

  test "a non-object payload is refused":
    check not parseSnapshot(newJNull(), "x").ok
    check not parseSnapshot(%*[1, 2, 3], "x").ok

  test "a missing candidates array is refused":
    var node = observeNode("n", BoundaryA, "pre", @[600])
    node.delete("candidates")
    let (ok, _, err) = parseSnapshot(node, "x")
    check not ok
    check "candidates" in err

  test "non-OBSERVED candidates never enter the metric":
    var node = observeNode("n", BoundaryA, "pre", @[600, 610])
    node["candidates"][1]["outcome"] = %"UNKNOWN"
    let (ok, snap, _) = parseSnapshot(node, "x")
    check ok
    check snap.observed.len == 1
    check metricValues(snap, mmAdmission) == @[600]

  test "the boundary may be declared under cohort or binding instead":
    var node = observeNode("n", BoundaryA, "pre", @[600])
    node.delete("boundary")
    node["cohort"]["boundary"] = %BoundaryB
    check boundaryOf(node).source == "cohort.boundary"
    node.delete("cohort")
    node["binding"] = %*{"boundary": BoundaryA}
    check boundaryOf(node).source == "binding.boundary"
    node.delete("binding")
    check boundaryOf(node).source == "ABSENT"

  test "cohort.source is recorded but never used as a boundary":
    let node = observeNode("pre_report.json", "", "pre", @[600])
    let (ok, snap, _) = parseSnapshot(node, "x")
    check ok
    check snap.cohortSource == "pre_report.json"
    check snap.boundary.len == 0
    check snap.boundarySource == "ABSENT"

# ---------------------------------------------------------------------------
# 14. Comparison assembly
# ---------------------------------------------------------------------------

suite "comparison assembly":

  func opts(metric = mmAdmission): Options =
    Options(metric: metric, reps: 200, seed: DefaultSeed, alpha: 0.05)

  test "a valid disjoint pair produces a comparison on the requested metric":
    let pre = cohort("pre", BoundaryA, "pre", @[880, 910, 940, 965, 990, 1015, 1040, 1070])
    let post = cohort("post", BoundaryB, "post", @[570, 588, 602, 639, 660, 707, 718, 755])
    let c = buildComparison(pre, post, opts(), CharonResult(), CharonResult())
    check c.validity.verdict == cvValid
    check c.x.len == 8
    check c.y.len == 8
    check c.mw.exact
    check c.mw.u == 64.0
    check c.mw.uDoubled == 128'i64
    check c.mw.pExact == "1/6435"
    check c.hlDoubled == -644'i64        # -322.0 seconds
    check c.mde.minAbsUDev == 19.0
    check c.mde.verdict == VerdictPowered
    check c.verdict == tvSignificant
    check not c.withheld

  test "--metric verify selects the verify phase, not the admission wall":
    let pre = cohort("pre", BoundaryA, "pre", @[880, 910])
    let post = cohort("post", BoundaryB, "post", @[570, 588])
    let c = buildComparison(pre, post, opts(mmVerify), CharonResult(), CharonResult())
    # The fixture sets verify = admission - 30, so the tested values shift by 30.
    check c.x == @[850, 880]
    check c.y == @[540, 558]

  test "--metric ready selects ready_seconds":
    let pre = cohort("pre", BoundaryA, "pre", @[880, 910])
    let post = cohort("post", BoundaryB, "post", @[570, 588])
    let c = buildComparison(pre, post, opts(mmReady), CharonResult(), CharonResult())
    check c.x == @[860, 890]
    check c.y == @[550, 568]

  test "a refused cohort withholds the inferential statistics":
    let a = cohort("pre", BoundaryA, "pre", @[100, 200])
    let b = cohort("post", BoundaryA, "post", @[110, 210])
    let c = buildComparison(a, b, opts(), CharonResult(), CharonResult())
    check c.verdict == tvRefused
    check c.withheld
    check c.boot.status == WithheldRefused
    # Descriptive quantities stay visible so a reviewer can still read them.
    check c.mw.u >= 0.0
    check c.x.len == 2
    let node = comparisonJson(c)
    check node{"test", "mann_whitney", "p_exact"}.getStr() == WithheldRefused
    check node{"test", "mann_whitney", "withheld"}.getBool()
    check node{"test", "bootstrap", "status"}.getStr() == WithheldRefused

  test "T_charon is NO_LOG_SOURCE unless spans are supplied":
    let a = cohort("pre", BoundaryA, "pre", @[100])
    let b = cohort("post", BoundaryB, "post", @[110])
    let c = buildComparison(a, b, opts(), CharonResult(), CharonResult())
    check c.preCharon.status == StatusNoLogSource
    check c.postCharon.status == StatusNoLogSource

  test "supplied charon spans become OBSERVED with their own summary":
    let s = charonFromSpans(@[30, 10, 20], "spans.json")
    check s.status == StatusObserved
    check s.n == 3
    check s.p50 == 20.0
    check s.minSeconds == 10
    check s.maxSeconds == 30
    check charonFromSpans(@[], "spans.json").status == StatusUnknown

  test "the comparison JSON carries the versioned schema and limitations":
    let a = cohort("pre", BoundaryA, "pre", @[100, 200])
    let b = cohort("post", BoundaryB, "post", @[110, 210])
    let node = comparisonJson(
      buildComparison(a, b, opts(), CharonResult(), CharonResult()))
    check node{"schema_version"}.getStr() == "axiom.ci_admission_compare.v1"
    check node{"observe_schema_version"}.getStr() ==
      "axiom.ci_admission_observe.v1"
    check node{"metric_pre_registered"}.getBool()
    check node{"cohort_validity", "verdict"}.getStr() == "VALID"
    check node{"test", "verdict"}.getStr().len > 0
    check node{"limitations"}.len >= 5
    check node{"derived", "pre", "t_charon", "status"}.getStr() ==
      StatusNoLogSource

  test "the p95 field is the documented INCOMPLETE label, not a number":
    let a = cohort("pre", BoundaryA, "pre", @[100, 200])
    let b = cohort("post", BoundaryB, "post", @[110, 210])
    let node = comparisonJson(
      buildComparison(a, b, opts(), CharonResult(), CharonResult()))
    check node{"spread", "pre", "admission", "p95"}.getStr() == P95Incomplete

  test "the metric field name is the pre-registered one for admission":
    check metricField(mmAdmission) == MetricPreRegistered
    check metricField(mmReady) == "ready_seconds"
    check metricField(mmVerify) == "verify_seconds"
    check parseMetric("admission").metric == mmAdmission
    check not parseMetric("queue").ok

# ---------------------------------------------------------------------------
# 15. Formatting
# ---------------------------------------------------------------------------

suite "formatting":

  test "fmt2 rounds half away from zero at two decimals":
    check fmt2(0.0) == "0.00"
    check fmt2(1.5) == "1.50"
    check fmt2(-322.0) == "-322.00"
    check fmt2(0.005) == "0.01"
    check fmt2(0.1554) == "0.16"
    check fmt2(-0.5) == "-0.50"

  test "nan and over-range values are labelled, not rendered as numbers":
    check fmt2(NaN) == "nan"
    check fmt2(1.0e20) == "over-range"

  test "fractionString reduces and never divides by zero":
    check fractionString(2'u64, 20'u64) == "1/10"
    check fractionString(1'u64, 6435'u64) == "1/6435"
    check fractionString(0'u64, 20'u64) == "0/1"
    check fractionString(0'u64, 0'u64) == "0/0"
    check fractionString(6'u64, 20'u64) == "3/10"

# ---------------------------------------------------------------------------
# 16. CLI (in-process, fixture files)
# ---------------------------------------------------------------------------

suite "cli":

  test "--help prints usage and exits 0":
    let r = runCli(@["--help"])
    check r.code == ExitProduced
    check "usage:" in r.outText
    check "--allow-overlap" in r.outText
    check "--charon-spans" in r.outText
    check $DefaultReps in r.outText

  test "missing --pre/--post is an input error":
    let r = runCli(@["--pre", "x.json"])
    check r.code == ExitInputError
    check "--pre and --post are required" in r.errText

  test "an unknown flag is an input error with usage":
    let r = runCli(@["--pre", "a", "--post", "b", "--bogus"])
    check r.code == ExitInputError
    check "unknown argument" in r.errText

  test "a bad enum value, reps, seed or alpha is an input error":
    check "admission|ready|verify" in runCli(@["--pre", "a", "--post", "b",
      "--metric", "wall"]).errText
    check "--reps must be >= 1" in runCli(@["--pre", "a", "--post", "b",
      "--reps", "0"]).errText
    check "--seed expects an integer" in runCli(@["--pre", "a", "--post", "b",
      "--seed", "abc"]).errText
    check "--alpha must be in (0,1)" in runCli(@["--pre", "a", "--post", "b",
      "--alpha", "1.5"]).errText
    check "--alpha must be in (0,1)" in runCli(@["--pre", "a", "--post", "b",
      "--alpha", "0"]).errText

  test "a missing file is an input error, not an empty comparison":
    let r = runCli(@["--pre", Work / "absent-pre.json", "--post", Work / "absent-post.json"])
    check r.code == ExitInputError
    check "pre snapshot unusable" in r.errText

  test "a schema mismatch is an input error":
    ensureWork()
    var node = observeNode("post", BoundaryB, "post", @[100, 200])
    node["schema_version"] = %"not-a-schema"
    let path = writeTemp(Work, "bad-schema.json", node)
    let r = runCli(@["--pre", path, "--post", path])
    check r.code == ExitInputError
    check "pre snapshot unusable" in r.errText
    check "not-a-schema" in r.errText

  test "a valid disjoint pair exits 0 and writes both reports":
    ensureWork()
    let pre = writeTemp(Work, "cli-pre-valid.json",
      observeNode("pre", BoundaryA, "pre", @[880, 910, 940, 965, 990, 1015, 1040, 1070]))
    let post = writeTemp(Work, "cli-post-valid.json",
      observeNode("post", BoundaryB, "post", @[570, 588, 602, 639, 660, 707, 718, 755]))
    let outDir = Work / "out-valid"
    let r = runCli(@["--pre", pre, "--post", post, "--out", outDir])
    check r.code == ExitProduced
    check r.errText.len == 0
    check fileExists(outDir / "ci_admission_compare_report.json")
    check fileExists(outDir / "ci_admission_compare_report.md")
    check "verdict: SIGNIFICANT" in r.outText

    let report = parseFile(outDir / "ci_admission_compare_report.json")
    check report{"schema_version"}.getStr() == "axiom.ci_admission_compare.v1"
    check report{"cohort_validity", "verdict"}.getStr() == "VALID"
    check report{"test", "mann_whitney", "p_exact"}.getStr() == "1/6435"
    check report{"derived", "post", "headroom_second", "n"}.getInt() == 8

    let md = readFile(outDir / "ci_admission_compare_report.md")
    check "# CI admission comparison" in md
    check "## Cohort validity" in md
    check "## Spread" in md
    check "## Headroom" in md
    check "## T_charon" in md

  test "--json writes the report to stdout instead of the summary":
    ensureWork()
    let pre = writeTemp(Work, "cli-pre-json.json",
      observeNode("pre", BoundaryA, "pre", @[100, 200]))
    let post = writeTemp(Work, "cli-post-json.json",
      observeNode("post", BoundaryB, "post", @[110, 210]))
    let r = runCli(@["--pre", pre, "--post", post, "--json"])
    check r.code == ExitProduced
    check r.outText.startsWith("{")
    let node = parseJson(r.outText)
    check node{"tool"}.getStr() == "ci_admission_compare"

  test "an overlapping pair exits 1 by default":
    ensureWork()
    let node = observeNode("same", BoundaryA, "same", @[100, 200, 300])
    let pre = writeTemp(Work, "cli-pre-overlap.json", node)
    let post = writeTemp(Work, "cli-post-overlap.json", node)
    let r = runCli(@["--pre", pre, "--post", post])
    check r.code == ExitCohortInvalid
    check "cohort invalid" in r.errText
    check "SAME_BOUNDARY_REFUSED" in r.errText

  test "--allow-overlap exits 0 but the verdict stays REFUSED":
    ensureWork()
    var rowsA: seq[CandidateRow] = @[]
    for i, v in [100, 200, 300]:
      rowsA.add candidate(900 + i, sha("same", i), v, @[])
    var rowsB: seq[CandidateRow] = @[]
    for i, v in [50, 150, 250]:
      rowsB.add candidate(910 + i, sha("same", i), v, @[])
    let pre = writeTemp(Work, "cli-pre-allow.json",
      observeNode("pre", BoundaryA, "same", @[100, 200, 300]))
    let post = writeTemp(Work, "cli-post-allow.json",
      observeNode("post", BoundaryB, "same", @[50, 150, 250]))
    discard rowsA
    discard rowsB
    let outDir = Work / "out-allow"
    let r = runCli(@["--pre", pre, "--post", post, "--allow-overlap",
                     "--out", outDir])
    check r.code == ExitProduced
    check "--allow-overlap" in r.errText
    let report = parseFile(outDir / "ci_admission_compare_report.json")
    check report{"cohort_validity", "verdict"}.getStr() == "OVERLAP_REFUSED"
    check report{"test", "verdict"}.getStr() == "REFUSED"

  test "a boundary split rescues an otherwise overlapping pair":
    # Same SHAs but different boundaries is still an overlap: the gate is
    # identity-based, so the rescue attempt must fail closed.
    ensureWork()
    let pre = writeTemp(Work, "cli-pre-split.json",
      observeNode("pre", BoundaryA, "same", @[100, 200, 300]))
    let post = writeTemp(Work, "cli-post-split.json",
      observeNode("post", BoundaryB, "same", @[50, 150, 250]))
    let r = runCli(@["--pre", pre, "--post", post])
    check r.code == ExitCohortInvalid
    check "OVERLAP_REFUSED" in r.errText

  test "--charon-spans replaces NO_LOG_SOURCE in both cohorts":
    ensureWork()
    let pre = writeTemp(Work, "cli-pre-charon.json",
      observeNode("pre", BoundaryA, "pre", @[100, 200]))
    let post = writeTemp(Work, "cli-post-charon.json",
      observeNode("post", BoundaryB, "post", @[110, 210]))
    let spans = Work / "charon-spans.json"
    writeFile(spans, """{"pre": [30, 40, 50], "post": [10, 20]}""")
    let outDir = Work / "out-charon"
    let r = runCli(@["--pre", pre, "--post", post, "--charon-spans", spans,
                     "--out", outDir])
    check r.code == ExitProduced
    let report = parseFile(outDir / "ci_admission_compare_report.json")
    check report{"derived", "pre", "t_charon", "status"}.getStr() == StatusObserved
    check report{"derived", "pre", "t_charon", "n"}.getInt() == 3
    check report{"derived", "post", "t_charon", "n"}.getInt() == 2

  test "a malformed charon span file is an input error, not a silent default":
    ensureWork()
    let pre = writeTemp(Work, "cli-pre-cbad.json",
      observeNode("pre", BoundaryA, "pre", @[100, 200]))
    let post = writeTemp(Work, "cli-post-cbad.json",
      observeNode("post", BoundaryB, "post", @[110, 210]))
    let spans = Work / "charon-bad.json"
    writeFile(spans, """{"pre": ["thirty"], "post": [10]}""")
    let r = runCli(@["--pre", pre, "--post", post, "--charon-spans", spans])
    check r.code == ExitInputError
    check "charon spans unusable" in r.errText

  test "a negative span is refused rather than accepted as a duration":
    ensureWork()
    let pre = writeTemp(Work, "cli-pre-cneg.json",
      observeNode("pre", BoundaryA, "pre", @[100, 200]))
    let post = writeTemp(Work, "cli-post-cneg.json",
      observeNode("post", BoundaryB, "post", @[110, 210]))
    let spans = Work / "charon-neg.json"
    writeFile(spans, """{"pre": [-5], "post": [10]}""")
    check runCli(@["--pre", pre, "--post", post, "--charon-spans", spans]).code ==
      ExitInputError
