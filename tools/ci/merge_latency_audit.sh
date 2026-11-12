#!/usr/bin/env bash
#
# merge_latency_audit.sh — 병합 지연 효과 측정 하니스 (merge-latency BEFORE/AFTER
# measurement instrument for the measure→change→measure→re-check loop). GET-only.
#
# Contract (pre-registered measurement rules — do NOT retune after seeing data):
#   * docs/evidence/e3_measurement_contract_2026-10-11.md
#       §5.2  L/H regime stratification via the `##[end-action id=__self.a-restore
#             …duration_ms=…]` log field, threshold 40,000 ms (H = >40 s, L = ≤40 s).
#       §7.1  run-level wall-clock = `updated_at − run_started_at` (UI-equivalent).
#             `GET /actions/runs/{id}/timing` is FORBIDDEN (shutdown) and is never called.
#       §7.2  API job/step timestamps are SECOND-granularity; every value here carries
#             measurement_basis="api-second-granularity" (±1 s). The log-line 7-digit
#             channel of §7.2 remains the estimand-grade source of the E3 Δ̂ tooling;
#             this harness consumes the run/job record plane (A2.3.4 firewall).
#   * docs/evidence/e3_amendment_a2_2026-10-11.md
#       A2.1  REUSED/EXECUTED separation: runs whose GO-critical work is a Judgment-CAS
#             reuse (SKIP lines > 0 ∧ RUN lines = 0 — 4/4 `basis=REUSED`) are classified
#             FULL_REUSE, reported as a SEPARATE stratum, and NEVER averaged into
#             test-execution costs. Operational wall-clock keeps BOTH strata.
#       A2.2.7 regime undetermined (a-restore marker absent / log lost) → fail-closed:
#             the stricter H band policy applies downstream; the run lands in the
#             "unknown" regime stratum and is flagged in every summary.
#   * docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md
#       §10 Q2 (2026-10-16 append-only adjudication — APPROVED "수집 채널 적응",
#       1차값 정의 불변): the G2 generation moved the GO-critical tests out of the
#       consume job's serial `[check] GO-critical` step into the 2-lane job matrix
#       `attest / go-critical-lane (0)` / `(1)`. The steps matcher and the A2.1.2
#       admission-tests corpus (SKIP/RUN lines) are extended to the lane jobs —
#       a sourcing-channel adaptation only: GO step = per-job multi-match summed,
#       then max across GO-bearing jobs (the §5(a) composite GO component
#       `max(lane-0 GO, lane-1 GO)`); classification = the same mechanical
#       SKIP/RUN rule over the union corpus (consume + lane logs). Serial
#       generations have no lane jobs — every extension degenerates to the
#       legacy path byte-identically. Regime stays bound to the consume job's
#       a-restore marker (E3 §5.2 authority — unchanged). Evidence:
#       docs/evidence/harness_lane_sourcing_gapb_2026-10-17.md.
#
# Components (per merge_group admission-gate run — reconciliation identity):
#   dur_sum   Σ visible critical-path job time = union of executed-job intervals.
#             A job segment hidden under an already-covered parallel prefix counts 0
#             (overlap is never double-counted). Telescoping identity:
#             dur_sum + gaps_sum = last_job_end − first_job_start.
#   gaps_sum  Σ idle gaps between consecutive critical-path segments
#             (predecessor completed_at → successor started_at).
#   wall      updated_at − run_started_at                                (§7.1, never /timing)
#   residual  wall − (dur_sum + gaps_sum) → start-offset + tail-offset overhead
#             (observed 3–5 s; E3 §7.1).
# Raw per-job durations, the gap segment table and the critical-path segment table
# are recorded per run so any re-cut is reproducible from the artifact without
# re-fetching.
#
# Reported per component: mean / p50 / p90 / min / max / sd (sample sd, n−1).
# Duration statistics (dur_sum / gaps_sum / residual / go_step) are computed over
# EXECUTED runs only; wall is reported BOTH pooled (operational, ALL runs) and
# executed-only. The sd column is the variance-aware termination input: the loop's
# stop rule ("next lever's expected saving must exceed BOTH measurement resolution
# AND run-to-run variation") evaluates mechanically as
#   required_min_saving_s = max(resolution_s, sd_baseline, sd_after)   per component.
#
# Modes:
#   measure  one run set → per-run records (JSONL) + summary stats
#   compare  --compare BASE AFTER → delta table (component | baseline mean±sd |
#            after mean±sd | delta | regime-split deltas | REUSED counts/side)
#            + boundary-note slot (changes land mid-window; per-boundary reporting,
#            PR #729 precedent) + termination block
#   snet     handoff helper: S_net = T_old_provision − ΔT_producer − ΔT_consumer
#            over named producer/consumer steps. Overlap is not double-counted: a
#            step (or step extension) hidden under a parallel predecessor's job
#            interval contributes only its visible wall portion.
#
# Authority (AGENTS.md §2.3, Authority ≠ Adapter): run/job/step existence and
# timestamps = GitHub Actions API; regime marker + REUSED classification lines =
# job logs (E3 §9 authority table). This tool is a REPORTER — it emits no merge
# verdict, changes no gate, and its outputs never override GitHub's
# merge-admission judgment.
#
# Purity: read-only. Every network call is an API GET (gh api). No mutation,
# rerun, cancel, or write path exists. No polling loops — one pass per run id.
#
# Quirk compliance (docs/spec/gh_merge_admission_observation_quirks.md):
#   Q2 — `gh run view`/`--log` 404 for merge_group runs; job logs are fetched via
#        /actions/runs/{id}/jobs → /actions/jobs/{job_id}/logs.
#   Q3 — job logs carry ANSI escapes; `gh api` requires --allow-escape-sequences
#        (else empty output that mimics log absence); escapes stripped before match.
#   Re-runs keep the run id and increment run_attempt; attempt > 1 is measured via
#        /attempts/{n} views as its own observation.
#   scan     (--since/--until measure): every merge_group admission-gate run in the
#            window is measured and its run-level conclusion recorded per run —
#            failure-conclusion runs are part of the operational wall-clock (the
#            registered 25-run window contains 3); strata separate them via the
#            per-run `conclusion` field, never silently.
#
# Usage:
#   merge_latency_audit.sh --runs ID1[,ID2,…] [--out PREFIX] [--boundary-note TEXT]
#                          [--no-logs] [--now ISO8601]
#   merge_latency_audit.sh --since ISO8601 --until ISO8601 [same options]
#   merge_latency_audit.sh --compare (IDS|@idsfile|PREFIX.runs.jsonl)
#                                   (IDS|@idsfile|PREFIX.runs.jsonl)
#                          [--out PREFIX] [--boundary-note TEXT] [--no-logs]
#   merge_latency_audit.sh --snet --baseline (IDS|@f|PREFIX.runs.jsonl)
#                                  --after    (IDS|@f|PREFIX.runs.jsonl)
#                                  --producer-steps RE1[,RE2,…] --consumer-steps RE3[,RE4,…]
#                                  [--producer-job RE] [--consumer-job RE]
#                                  [--baseline-provision SECONDS] [--out PREFIX]
#   merge_latency_audit.sh -h
#
# Output (measure): PREFIX.runs.jsonl (one record per run) + PREFIX.summary.json.
#                   Default PREFIX: data/merge_latency/audit
# Output (compare): PREFIX.compare.json + PREFIX.compare.md. Default: data/merge_latency/compare
# Output (snet):    PREFIX.snet.json + PREFIX.snet.md.     Default: data/merge_latency/snet
#
# Exit codes: 0 = pass complete (UNKNOWN classification/regime runs are recorded,
#             never silently dropped); 1 = hard failure (result-cap breach,
#             non-admission-gate run id, structural API failure) — fail-closed;
#             2 = usage/environment error (gh/jq unavailable, bad arguments).

set -euo pipefail

OWNER="Archright"
REPO="Axiom"
# Admission-gate registration paths: Lever-B (2026-10-16) renamed the org workflow
# admission-gate.yml → admission-gate-v2.yml (docs/evidence/g1_leverB_path_rename_2026-10-16.md).
# Both generations measure the SAME gate; anything else is refused (fail-closed).
# One regex serves both matchers: `[.]` avoids `\.` (rejected inside jq string
# literals) and `^(.*/)?` lets the same anchor match the full registration path
# (.github/workflows/<name>) in the scan filter as well as the basename here.
GATE_PATH_RE='^(.*/)?admission-gate(-v2)?[.]yml$'
CONSUME_JOB="attest / admission-check"
# E3 §5.1 name-prefix rule. Prereg §10 Q2 adds the matrix-generation twin: the
# GO-critical step lives in the lane jobs as
# `[lane] GO-critical admission tests (DEBT#432 — lane N, fail-closed)`
# (.github/workflows/admission-check.yml go-critical-lane). Exactly one added
# disjunct `[lane]` — no other step in either generation can match it.
GO_STEP_RE='^\[(check|lane)\] GO-critical'
LANE_JOB_0="attest / go-critical-lane (0)"
LANE_JOB_1="attest / go-critical-lane (1)"

A_RESTORE_THRESHOLD_MS=40000                  # E3 §5.2 — a priori fixed
GO_REUSE_EPSILON_S=1                          # "GO step ≈ 0 s" tolerance at second granularity
RESOLUTION_S=1                                # API second-granularity (§7.2) — termination input
RESULT_CAP=1000                               # silent-truncation guard (e4e5_collect.sh precedent)

MODE="measure"
RUNS_ARG=""
SINCE=""; UNTIL=""
BASE_ARG=""; AFTER_ARG=""
PRODUCER_STEPS=""; CONSUMER_STEPS=""
PRODUCER_JOB_RE=""; CONSUMER_JOB_RE=""
BASELINE_PROVISION=""
BOUNDARY_NOTE=""
NO_LOGS=0
NOW_OVERRIDE=""
OUT_PREFIX=""

usage() { sed -n '2,102p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --runs)               RUNS_ARG="$2"; shift 2 ;;
    --since)              SINCE="$2"; shift 2 ;;
    --until)              UNTIL="$2"; shift 2 ;;
    --compare)            MODE="compare"; BASE_ARG="$2"; AFTER_ARG="$3"; shift 3 ;;
    --snet)               MODE="snet"; shift ;;
    --baseline)           BASE_ARG="$2"; shift 2 ;;
    --after)              AFTER_ARG="$2"; shift 2 ;;
    --producer-steps)     PRODUCER_STEPS="$2"; shift 2 ;;
    --consumer-steps)     CONSUMER_STEPS="$2"; shift 2 ;;
    --producer-job)       PRODUCER_JOB_RE="$2"; shift 2 ;;
    --consumer-job)       CONSUMER_JOB_RE="$2"; shift 2 ;;
    --baseline-provision) BASELINE_PROVISION="$2"; shift 2 ;;
    --boundary-note)      BOUNDARY_NOTE="$2"; shift 2 ;;
    --out)                OUT_PREFIX="$2"; shift 2 ;;
    --no-logs)            NO_LOGS=1; shift ;;
    --now)                NOW_OVERRIDE="$2"; shift 2 ;;
    -h|--help)            usage 0 ;;
    *) echo "[mla] FAIL: unknown argument: $1" >&2; usage 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "[mla] FAIL: gh not available" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "[mla] FAIL: jq not available" >&2; exit 2; }
case "$MODE" in
  compare) [ -n "$BASE_ARG" ] && [ -n "$AFTER_ARG" ] || { echo "[mla] FAIL: --compare needs two sides" >&2; exit 2; } ;;
  snet)    [ -n "$BASE_ARG" ] && [ -n "$AFTER_ARG" ] || { echo "[mla] FAIL: --snet needs --baseline/--after" >&2; exit 2; }
           [ -n "$PRODUCER_STEPS" ] || { echo "[mla] FAIL: --snet needs --producer-steps RE1[,RE2,…]" >&2; exit 2; } ;;
  measure) : ;;
esac

COLLECTED_AT="${NOW_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
OUT_PREFIX="${OUT_PREFIX:-data/merge_latency/audit}"
mkdir -p "$(dirname "$OUT_PREFIX")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"

# ===================================================================== jq lib ==
# Shared function library prepended to every program file below. All interval
# math is integer epoch seconds (api-second-granularity, §7.2).
cat > "$WORK/lib.jq" <<'EOF'
def iso2epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
def r1($x): if $x == null then null else (($x * 10 | round) / 10) end;
def union_measure(ivs):
  (ivs | sort_by(.[0]) | reduce .[] as $iv ({cs: null, ce: null, m: 0};
    if .cs == null then {cs: $iv[0], ce: $iv[1], m: 0}
    elif $iv[0] <= .ce then {cs: .cs, ce: (if $iv[1] > .ce then $iv[1] else .ce end), m: .m}
    else {cs: $iv[0], ce: $iv[1], m: (.m + (.ce - .cs))} end)) as $r
  | if $r.cs == null then 0 else $r.m + ($r.ce - $r.cs) end;
def subtract_holes($iv; holes):
  ($iv[0]) as $s | ($iv[1]) as $e |
  (reduce (holes | sort_by(.[0]))[] as $h ({cur: $s, frags: []};
    if .cur >= $e then .
    elif ($h[1] <= .cur) or ($h[0] >= $e) then .
    else
      (if $h[0] > .cur then .frags + [[.cur, (if $h[0] < $e then $h[0] else $e end)]] else .frags end) as $f
      | {cur: (if $h[1] > .cur then $h[1] else .cur end), frags: $f}
    end)) as $r
  | (if $r.cur < $e then $r.frags + [[$r.cur, $e]] else $r.frags end);
# critical-path decomposition over executed-job intervals, where a job "executed"
# iff it ran (success OR failure — failed jobs occupy wall time on the path;
# only conclusion="skipped" jobs are excluded). Telescoping identity:
# dur_sum + gaps_sum = last_end − first_start. A job ending inside the already
# covered prefix is hidden and contributes 0 (overlap never double-counted).
def decomp:
  ([.[] | select(.executed)] | sort_by(.s, (-(.e)), .job_id)) as $sorted |
  reduce $sorted[] as $j ({cur: null, dur: 0, gaps: 0, gap_segs: [], path: [], last_name: null};
    if .cur != null and ($j.e <= .cur)
    then .path += [$j + {visible_s: 0, gap_before_s: 0, hidden: true}]
    else
      (if .cur == null then $j.s elif $j.s > .cur then $j.s else .cur end) as $s2 |
      (if .cur == null then 0 else $s2 - .cur end) as $g |
      {cur: $j.e, dur: (.dur + ($j.e - $s2)), gaps: (.gaps + $g),
       gap_segs: (if $g > 0 then .gap_segs + [{from: .last_name, to: $j.name, gap_s: $g}] else .gap_segs end),
       path: (.path + [$j + {visible_s: ($j.e - $s2), gap_before_s: $g, hidden: false}]),
       last_name: $j.name}
    end)
  | {dur_sum_s: .dur, gaps_sum_s: .gaps, gap_segments: .gap_segs,
     critical_path: [.path[] | {job: .name, job_id: .job_id, visible_s: .visible_s, gap_before_s: .gap_before_s, hidden: .hidden}]};
def stats(v):
  ((v | length)) as $n |
  if $n == 0 then {n: 0}
  else
    (v | sort) as $s |
    (($s | add) / $n) as $mean |
    (if $n > 1
     then (((($s | map(.*.) | add) - (($s | add) * ($s | add) / $n)) / ($n - 1)) | sqrt)
     else null end) as $sd |
    (((($s | length) - 1) * 0.5)) as $i50 |
    (((($s | length) - 1) * 0.9)) as $i90 |
    def q($ix):
      (($ix | floor)) as $lo |
      if $lo >= (($s | length) - 1) then $s[-1]
      else $s[$lo] + (($ix - $lo) * ($s[$lo + 1] - $s[$lo])) end;
    {n: $n, mean: r1($mean), sd: r1($sd), p50: r1(q($i50)), p90: r1(q($i90)),
     min: $s[0], max: $s[-1]}
  end;
EOF

# ============================================================== record builder ==
cat > "$WORK/record.jq" <<'EOF'
def run_record:
  (if .updated == "" or .started == "" then null
   else ((.updated | iso2epoch) - (.started | iso2epoch)) end) as $wall |
  (.jobs
   | map({s: (if .started_at == "" then null else (.started_at | iso2epoch) end),
          e: (if .completed_at == "" then null else (.completed_at | iso2epoch) end),
          job_id: .job_id, name: .name, conclusion: .conclusion,
          started_at_str: (if .started_at == "" then null else .started_at end),
          completed_at_str: (if .completed_at == "" then null else .completed_at end),
          executed: (.conclusion != "skipped" and .started_at != "" and .completed_at != "")})
   | sort_by((.s // 0), .job_id)) as $jobs |
  ($jobs | decomp) as $dc |
  {
    schema: "axiom.merge_latency.run/1",
    tool: "tools/ci/merge_latency_audit.sh",
    measurement_basis: "api-second-granularity",
    run_id: (.run_id | tonumber),
    run_attempt: .attempt,
    event: .event,
    workflow_path: .path,
    head_sha: .head,
    conclusion: .concl,
    created_at: .created,
    run_started_at: .started,
    updated_at: .updated,
    wall_s: $wall,
    jobs: [$jobs[] | {job: .name, job_id: .job_id,
            started_at: .started_at_str, completed_at: .completed_at_str,
            conclusion: .conclusion, executed: .executed,
            duration_s: (if .s != null and .e != null then (.e - .s) else null end)}],
    dur_sum_s: $dc.dur_sum_s,
    gaps_sum_s: $dc.gaps_sum_s,
    gap_segments: $dc.gap_segments,
    critical_path: $dc.critical_path,
    residual_s: (if $wall == null then null else ($wall - $dc.dur_sum_s - $dc.gaps_sum_s) end),
    consume_job_id: (if .consume_job_id == "" then null else (.consume_job_id | tonumber) end),
    go_step_s: .go_step_s,
    go_step_matches: .go_step_matches,
    go_step_source_jobs: .go_step_source_jobs,
    lane_jobs: .lane_jobs,
    go_reuse_consistent: (if .go_step_s == null then null else .go_step_s <= .eps end),
    a_restore_ms: .a_restore_ms,
    a_restore_threshold_ms: .threshold,
    regime: .regime,
    regime_note: (if .regime == "unknown"
                  then "a-restore marker unavailable — A2.2.7 fail-closed: stricter H band applies downstream"
                  else null end),
    admission_tests: {skip_lines: .skip_lines, run_lines: .run_lines, log_read: (.log_ok == "1")},
    classification: .classification,
    reuse_k: .reuse_k,
    boundary_note: .boundary,
    collected_at: .collected
  };
run_record
EOF

cat > "$WORK/gostep.jq" <<'EOF'
# E3 §5.1 name rule + prereg §10 Q2 lane sourcing: matches are summed within
# each GO-bearing job (multi-match rule unchanged), then the per-job sums are
# reduced with max. Serial generation: exactly one GO-bearing job → max = its
# sum (byte-identical legacy value). Matrix generation: the two lane GO steps
# run concurrently, so the longer lane is the critical-path GO duration — the
# same GO component the frozen §5(a) composite formula consumes
# (max(lane-0 GO, lane-1 GO) + per-lane setup).
([.[] | select((.name | test($pre)) and .conclusion == "success"
               and .s != null and .e != null)
   | {job: .job_id, s: (.s | iso2epoch), e: (.e | iso2epoch)}]) as $g
| ($g | group_by(.job) | map(map(.e - .s) | add)) as $per
| (if ($per | length) == 0 then null else ($per | max) end) as $tot
| "\($tot // "null") \($g | length) \(([$g[].job] | unique | join(",")))"
EOF
cat "$WORK/lib.jq" "$WORK/gostep.jq" > "$WORK/gostep_full.jq"

# ================================================================ API helpers ==
api_get() { gh api "$@"; }

fetch_run_record() { api_get "repos/$OWNER/$REPO/actions/runs/$1"; }

fetch_jobs_tsv() { # $1=run_id $2=attempt → TSV: id name started completed conclusion
  local jobs_path="repos/$OWNER/$REPO/actions/runs/$1/jobs?per_page=100"
  [ "$2" != "1" ] && jobs_path="repos/$OWNER/$REPO/actions/runs/$1/attempts/$2/jobs?per_page=100"
  api_get "$jobs_path" --jq '.jobs[] | [(.id|tostring), .name,
    (.started_at // ""), (.completed_at // ""), (.conclusion // "null")] | @tsv'
}

fetch_job_steps() { # $1=job_id → steps JSON with s/e kept as strings
  api_get "repos/$OWNER/$REPO/actions/jobs/$1" \
    --jq '[.steps[] | {name: .name, number: .number,
            s: (.started_at // null), e: (.completed_at // null),
            conclusion: (.conclusion // "null")}]' 2>/dev/null || echo "[]"
}

fetch_job_log() { # $1=job_id $2=outfile — quirks Q2/Q3; returns 0 iff non-empty
  gh api --allow-escape-sequences "repos/$OWNER/$REPO/actions/jobs/$1/logs" > "$2" 2>/dev/null || true
  [ -s "$2" ]
}

# --------------------------------------------------------------- run pipeline --
process_run() { # $1=run_id $2=out jsonl $3=want_logs(0/1)
  local id="$1" out="$2" want_logs="$3"
  local rec
  rec="$(fetch_run_record "$id" 2>/dev/null)" || {
    echo "[mla] HARD-FAIL: run record fetch failed for run $id (structural API failure)" >&2; exit 1; }

  local path event attempt started updated concl head created
  path="$(jq -r '.path // ""' <<<"$rec")"
  event="$(jq -r '.event // ""' <<<"$rec")"
  attempt="$(jq -r '.run_attempt // 1' <<<"$rec")"
  started="$(jq -r '.run_started_at // ""' <<<"$rec")"
  updated="$(jq -r '.updated_at // ""' <<<"$rec")"
  concl="$(jq -r '(.conclusion // "null")' <<<"$rec")"
  head="$(jq -r '.head_sha // ""' <<<"$rec")"
  created="$(jq -r '.created_at // ""' <<<"$rec")"
  if ! [[ "${path##*/}" =~ $GATE_PATH_RE ]]; then
    echo "[mla] HARD-FAIL: run $id path '$path' is not an admission-gate run (allowlist: ${GATE_PATH_RE}) — refusing to measure non-admission-gate runs" >&2
    exit 1
  fi

  local jobs_tsv
  jobs_tsv="$(fetch_jobs_tsv "$id" "$attempt" 2>/dev/null || true)"
  [ -n "$jobs_tsv" ] || { echo "[mla] HARD-FAIL: jobs fetch failed/empty for run $id" >&2; exit 1; }
  printf '%s\n' "$jobs_tsv" | jq -Rn '
    [inputs | select(length > 0) | split("\t")
     | {job_id: (.[0] | tonumber), name: .[1], started_at: .[2], completed_at: .[3], conclusion: .[4]}]
  ' > "$WORK/jobs_$id.json"

  local consume_job_id
  consume_job_id="$(jq -r --arg cj "$CONSUME_JOB" '
    ([.[] | select(.name == $cj and .conclusion == "success")] | sort_by(.job_id) | .[0].job_id // null
     | if . == null then "" else (. | tostring) end)
  ' "$WORK/jobs_$id.json")"

  # Lane jobs (prereg §10 Q2 — matrix generation): the GO-critical tests run
  # in `attest / go-critical-lane (0)` / `(1)`. Serial-generation runs have no
  # lane jobs at all — lanes_tsv is empty and every use below degenerates to
  # the legacy path. A lane that did not run (skipped PR-venue expansion,
  # missing conclusion) is never sourced: a non-ran job contributes no GO
  # steps and no admission-tests lines (fail-closed: nothing is invented).
  local lanes_tsv
  lanes_tsv="$(jq -r --arg a "$LANE_JOB_0" --arg b "$LANE_JOB_1" '
    [.[] | select((.name == $a or .name == $b)
                  and .conclusion != "skipped" and .conclusion != "null")]
    | sort_by(.name, .job_id)[]
    | [.name, (.job_id | tostring)] | @tsv
  ' "$WORK/jobs_$id.json")"

  # GO-critical step seconds over the GO-bearing corpus: consume job steps +
  # lane job steps, each tagged with its job id (E3 §5.1 name rule; per-job
  # multi-match summed, max across jobs — see gostep.jq).
  local go_step_s="null" go_step_matches=0 go_step_jobs=""
  : > "$WORK/steps_raw_$id.txt"
  if [ -n "$consume_job_id" ]; then
    fetch_job_steps "$consume_job_id" \
      | jq -c --argjson jid "$consume_job_id" '.[] | .job_id = $jid' >> "$WORK/steps_raw_$id.txt" || true
  fi
  if [ -n "$lanes_tsv" ]; then
    local lid
    while IFS=$'\t' read -r _ lid; do
      [ -n "$lid" ] || continue
      fetch_job_steps "$lid" \
        | jq -c --argjson jid "$lid" '.[] | .job_id = $jid' >> "$WORK/steps_raw_$id.txt" || true
    done <<< "$lanes_tsv"
  fi
  if [ -s "$WORK/steps_raw_$id.txt" ]; then
    jq -s '.' "$WORK/steps_raw_$id.txt" > "$WORK/steps_$id.json"
    read -r go_step_s go_step_matches go_step_jobs \
      < <(jq -r --arg pre "$GO_STEP_RE" -f "$WORK/gostep_full.jq" "$WORK/steps_$id.json")
  else
    echo '[]' > "$WORK/steps_$id.json"
  fi

  # Consume job log → regime marker (E3 §5.2 authority — unchanged: the
  # a-restore marker persists in the consume job log after the lane move,
  # observed 2026-10-17 on runs 38925131342/38913175446/38891209338).
  local a_restore_ms="" log_ok=0
  if [ "$want_logs" = "1" ] && [ -n "$consume_job_id" ]; then
    if fetch_job_log "$consume_job_id" "$WORK/log_$id.raw"; then
      log_ok=1
      sed -E 's/\x1b\[[0-9;]*m//g' "$WORK/log_$id.raw" > "$WORK/log_$id.txt"
      a_restore_ms="$(grep -aoE '##\[end-action id=__self\.a-restore;[^]]*duration_ms=[0-9]+\]' "$WORK/log_$id.txt" \
        | head -1 | sed -E 's/^.*duration_ms=([0-9]+)\]$/\1/' || true)"
    fi
  fi

  # A2.1.2 admission-tests corpus: consume log + lane logs (union). The
  # classification rule itself is untouched — SKIP/RUN lines carry the same
  # `[admission-tests]` vocabulary in both generations; the serial consume
  # log holds them all, the matrix generation's consume log holds none and
  # the lane logs hold the per-lane halves. Step-source echo lines in the
  # logs do not match the anchored patterns (timestamp followed by shell
  # source text, not the marker).
  local skip_lines=0 run_lines=0 lane_log_ok=0
  : > "$WORK/admtests_$id.txt"
  if [ "$log_ok" = "1" ]; then
    cat "$WORK/log_$id.txt" >> "$WORK/admtests_$id.txt"
  fi
  if [ "$want_logs" = "1" ] && [ -n "$lanes_tsv" ]; then
    local lname
    while IFS=$'\t' read -r lname lid; do
      [ -n "$lid" ] || continue
      if fetch_job_log "$lid" "$WORK/lanelog_$lid.raw"; then
        sed -E 's/\x1b\[[0-9;]*m//g' "$WORK/lanelog_$lid.raw" >> "$WORK/admtests_$id.txt"
        lane_log_ok=$((lane_log_ok+1))
      fi
    done <<< "$lanes_tsv"
  fi
  skip_lines="$(grep -acE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[admission-tests\] SKIP — ' "$WORK/admtests_$id.txt" || true)"
  run_lines="$(grep -acE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[admission-tests\] RUN make test-fast-one' "$WORK/admtests_$id.txt" || true)"

  # classification (A2.1.2 mechanical, log-line authority). Gate = any corpus
  # component read (consume log and/or lane logs) — UNKNOWN_LOG only when the
  # whole admission-tests corpus is unavailable (A2.1.2 "no log").
  local classification="UNKNOWN_LOG" reuse_k="null"
  if [ "$log_ok" = "1" ] || [ "$lane_log_ok" -gt 0 ]; then
    if   [ "$skip_lines" -gt 0 ] && [ "$run_lines" -eq 0 ]; then classification="FULL_REUSE";    reuse_k="$skip_lines"
    elif [ "$skip_lines" -eq 0 ] && [ "$run_lines" -gt 0 ]; then classification="EXECUTED"
    elif [ "$skip_lines" -gt 0 ] && [ "$run_lines" -gt 0 ]; then classification="PARTIAL_REUSE"; reuse_k="$skip_lines"
    fi
  fi

  # regime (E3 §5.2 marker authority; absent → unknown + A2.2.7 fail-closed note)
  local regime="unknown"
  if [ -n "$a_restore_ms" ]; then
    if [ "$a_restore_ms" -gt "$A_RESTORE_THRESHOLD_MS" ]; then regime="H"; else regime="L"; fi
  fi

  # flat raw document → single jq record program → one JSONL line
  local lane_jobs_json go_step_jobs_json
  lane_jobs_json="$(printf '%s\n' "$lanes_tsv" | jq -Rn '
    [inputs | select(length > 0) | split("\t") | {name: .[0], job_id: (.[1] | tonumber)}]')"
  go_step_jobs_json="$(if [ -n "$go_step_jobs" ]; then
    printf '%s' "$go_step_jobs" | jq -R 'split(",") | map(tonumber)'
  else echo '[]'; fi)"
  jq -n \
    --arg collected "$COLLECTED_AT" \
    --arg run_id "$id" --arg event "$event" --arg path "$path" \
    --arg created "$created" --arg started "$started" --arg updated "$updated" \
    --arg concl "$concl" --arg head "$head" --argjson attempt "$attempt" \
    --slurpfile jobs "$WORK/jobs_$id.json" \
    --argjson go_step_s "$go_step_s" --argjson go_step_matches "$go_step_matches" \
    --argjson go_step_source_jobs "$go_step_jobs_json" \
    --argjson lane_jobs "$lane_jobs_json" \
    --argjson a_restore_ms "$(if [ -n "$a_restore_ms" ]; then printf '%s' "$a_restore_ms"; else echo null; fi)" \
    --argjson skip_lines "$skip_lines" --argjson run_lines "$run_lines" \
    --arg classification "$classification" --argjson reuse_k "$reuse_k" \
    --arg regime "$regime" --arg boundary "$BOUNDARY_NOTE" \
    --argjson threshold "$A_RESTORE_THRESHOLD_MS" --argjson eps "$GO_REUSE_EPSILON_S" \
    --arg consume_job_id "$consume_job_id" --arg log_ok "$log_ok" \
    '{collected: $collected, run_id: $run_id, event: $event, path: $path,
      created: $created, started: $started, updated: $updated, concl: $concl,
      head: $head, attempt: $attempt, jobs: $jobs[0],
      go_step_s: $go_step_s, go_step_matches: $go_step_matches,
      go_step_source_jobs: $go_step_source_jobs, lane_jobs: $lane_jobs,
      a_restore_ms: $a_restore_ms, skip_lines: $skip_lines, run_lines: $run_lines,
      classification: $classification, reuse_k: $reuse_k, regime: $regime,
      boundary: $boundary, threshold: $threshold, eps: $eps,
      consume_job_id: $consume_job_id, log_ok: $log_ok}' > "$WORK/raw_$id.json"
  jq -c -f "$WORK/record_full.jq" "$WORK/raw_$id.json" > "$WORK/rec_$id.json"
  cat "$WORK/rec_$id.json" >> "$out"
  echo "[mla] run $id: wall=$(jq -r '.wall_s' "$WORK/rec_$id.json")s class=$classification regime=$regime go_step=$(jq -r '.go_step_s' "$WORK/rec_$id.json")s lanes=$(jq -r '.lane_jobs | length' "$WORK/rec_$id.json")"
}

# ============================================================== summary stats ==
cat > "$WORK/summary.jq" <<'EOF'
([.runs[] | select(.classification == "FULL_REUSE")    | .run_id]) as $reuse_ids |
([.runs[] | select(.classification == "PARTIAL_REUSE") | .run_id]) as $partial_ids |
([.runs[] | select(.classification == "UNKNOWN_LOG")   | .run_id]) as $unknown_ids |
([.runs[] | select(.classification == "EXECUTED")]) as $exec |
([.runs[]]) as $all |
([.runs[] | select(.classification == "EXECUTED" and .regime == "L")]) as $execL |
([.runs[] | select(.classification == "EXECUTED" and .regime == "H")]) as $execH |
([.runs[] | select(.classification == "EXECUTED" and .regime == "unknown")]) as $execU |
([$exec[] | .dur_sum_s])  as $v_dur |
([$exec[] | .gaps_sum_s]) as $v_gap |
([$exec[] | .residual_s]) as $v_res |
([$exec[] | .wall_s])     as $v_wallE |
([$all[]  | .wall_s])     as $v_wallA |
([$exec[] | select(.go_step_s != null) | .go_step_s]) as $v_go |
([$all[] | select(.classification == "FULL_REUSE") | .wall_s]) as $v_wallR |
(.resolution_s) as $res |
{
  schema: "axiom.merge_latency.summary/1",
  tool: "tools/ci/merge_latency_audit.sh",
  collected_at: .collected,
  boundary_note: (if .boundary_note == "" then null else .boundary_note end),
  window: .window,
  scan: .scan,
  rules: {
    wall_definition: "updated_at − run_started_at (E3 §7.1; /timing endpoint never used)",
    regime_marker: "##[end-action id=__self.a-restore …duration_ms=…] log field (E3 §5.2 authority)",
    a_restore_threshold_ms: .threshold,
    regime_rule: "H = >40000 ms, L = ≤40000 ms; unknown → A2.2.7 fail-closed stricter H band downstream",
    classification: "A2.1.2 mechanical over the admission-tests corpus (consume + lane job logs — prereg §10 Q2 sourcing extension; serial generations have no lane jobs): SKIP>0 ∧ RUN=0 → FULL_REUSE; SKIP=0 ∧ RUN>0 → EXECUTED; mixed → PARTIAL_REUSE(k=SKIP); no lines → UNKNOWN_LOG",
    go_step_sourcing: "E3 §5.1 name rule (multi-match summed per GO-bearing job) over consume + lane job steps; max across GO-bearing jobs = prereg §5(a) composite GO component; serial generation: single job, value unchanged",
    duration_statistics_denominator: "EXECUTED runs only (A2.1.3); FULL_REUSE never averaged into execution costs; operational wall-clock keeps both strata",
    stats_definition: "mean/p50/p90/min/max + sample sd (n−1); p50/p90 linear interpolation",
    measurement_basis: "api-second-granularity (E3 §7.2, ±1 s)",
    reconciliation_identity: "dur_sum + gaps_sum = last_job_end − first_job_start (telescoping); residual = wall − dur_sum − gaps_sum"
  },
  counts: {
    runs: ($all | length),
    executed: ($exec | length),
    full_reuse: ($reuse_ids | length),
    partial_reuse: ($partial_ids | length),
    unknown_log: ($unknown_ids | length),
    executed_by_regime: {L: ($execL | length), H: ($execH | length), unknown: ($execU | length)}
  },
  full_reuse_run_ids: $reuse_ids,
  partial_reuse_run_ids: $partial_ids,
  unknown_log_run_ids: $unknown_ids,
  stats: {
    all_operational: {
      note: "operational projection over ALL measured runs (incl. FULL_REUSE and failure-conclusion runs) — this cut corresponds to the registered wall-clock baseline; duration-statistics denominator remains EXECUTED-only",
      wall_s:     ($v_wallA | stats(.)),
      dur_sum_s:  ([$all[] | .dur_sum_s]  | stats(.)),
      gaps_sum_s: ([$all[] | .gaps_sum_s] | stats(.)),
      residual_s: ([$all[] | .residual_s] | stats(.))
    },
    executed_only: {
      dur_sum_s:  ($v_dur  | stats(.)),
      gaps_sum_s: ($v_gap  | stats(.)),
      residual_s: ($v_res  | stats(.)),
      wall_s:     ($v_wallE | stats(.)),
      go_step_s:  ($v_go   | stats(.))
    },
    full_reuse_stratum: {
      note: "A2.1.3: FULL_REUSE = Judgment-CAS reuse (GO-critical ≈ 0 s) — separate stratum; never averaged into duration statistics; operational wall-clock retained",
      wall_s: ($v_wallR | stats(.))
    },
    executed_by_regime: {
      L: {dur_sum_s:  ([$execL[] | .dur_sum_s]  | stats(.)),
          gaps_sum_s: ([$execL[] | .gaps_sum_s] | stats(.)),
          residual_s: ([$execL[] | .residual_s] | stats(.)),
          wall_s:     ([$execL[] | .wall_s]     | stats(.))},
      H: {dur_sum_s:  ([$execH[] | .dur_sum_s]  | stats(.)),
          gaps_sum_s: ([$execH[] | .gaps_sum_s] | stats(.)),
          residual_s: ([$execH[] | .residual_s] | stats(.)),
          wall_s:     ([$execH[] | .wall_s]     | stats(.))},
      unknown: {dur_sum_s:  ([$execU[] | .dur_sum_s]  | stats(.)),
          gaps_sum_s: ([$execU[] | .gaps_sum_s] | stats(.)),
          residual_s: ([$execU[] | .residual_s] | stats(.)),
          wall_s:     ([$execU[] | .wall_s]     | stats(.))}
    }
  },
  termination_inputs: {
    note: "loop stop rule: the next lever's expected saving must exceed BOTH measurement resolution AND run-to-run variation → required_min_saving_s = max(resolution_s, sd) per component (executed-only stats)",
    resolution_s: $res,
    components: {
      dur_sum_s:  {sd: ($v_dur  | stats(.)).sd,
                   required_min_saving_s: (if ($v_dur | stats(.)).sd  == null then $res else ([$res, ($v_dur | stats(.)).sd]  | max) end)},
      gaps_sum_s: {sd: ($v_gap | stats(.)).sd,
                   required_min_saving_s: (if ($v_gap | stats(.)).sd == null then $res else ([$res, ($v_gap | stats(.)).sd] | max) end)},
      residual_s: {sd: ($v_res | stats(.)).sd,
                   required_min_saving_s: (if ($v_res | stats(.)).sd == null then $res else ([$res, ($v_res | stats(.)).sd] | max) end)},
      wall_s:     {sd: ($v_wallE | stats(.)).sd,
                   required_min_saving_s: (if ($v_wallE | stats(.)).sd == null then $res else ([$res, ($v_wallE | stats(.)).sd] | max) end)}
    }
  }
}
EOF

emit_summary() { # $1=runs.jsonl $2=out summary.json $3=window_json $4=scan_json
  [ -s "$1" ] || { echo "[mla] HARD-FAIL: no run records measured — refusing to emit an empty summary" >&2; exit 1; }
  jq -c -n --slurpfile runs "$1" \
    --arg collected "$COLLECTED_AT" --arg boundary "$BOUNDARY_NOTE" \
    --argjson window "$3" --argjson scan "$4" \
    --argjson threshold "$A_RESTORE_THRESHOLD_MS" --argjson resolution "$RESOLUTION_S" \
    '{runs: $runs, collected: $collected, boundary_note: $boundary,
      window: $window, scan: $scan, threshold: $threshold, resolution_s: $resolution}' \
  | jq -f "$WORK/summary_full.jq" > "$2"
}

# ------------------------------------------------------------------- run sets --
resolve_runs_arg() { # $1=arg → comma-joined ids on stdout
  case "$1" in
    @*) tr ',\t\n' '\n\n\n' < "${1#@}" | grep -vE '^[[:space:]]*$' | paste -sd, - ;;
    *.runs.jsonl)
      [ -s "$1" ] || { echo "[mla] FAIL: artifact not found: $1" >&2; exit 2; }
      jq -r '[.[].run_id] | map(tostring) | join(",")' "$1" ;;
    *) printf '%s' "$1" ;;
  esac
}

measure_ids() { # $1=comma ids $2=out jsonl $3=want_logs(0/1)
  : > "$2"
  printf '%s\n' "$1" | tr ',' '\n' | while read -r rid; do
    rid="$(printf '%s\n' "$rid" | tr -d '[:space:]')"
    [ -n "$rid" ] || continue
    process_run "$rid" "$2" "$3"
  done
}

scan_window() { # $1=since $2=until $3=out ids-file — ≤1-day slices + cap guard
  local since="$1" until_="$2" idsfile="$3"
  : > "$idsfile"
  : > "$WORK/slices.tsv"
  local cur="$since" nxt
  while [ "$(date -u -d "$cur" +%s)" -lt "$(date -u -d "$until_" +%s)" ]; do
    nxt="$(date -u -d "$cur +1 day" +%Y-%m-%dT%H:%M:%SZ)"
    [ "$(date -u -d "$nxt" +%s)" -gt "$(date -u -d "$until_" +%s)" ] && nxt="$until_"
    printf '%s\t%s\n' "$cur" "$nxt" >> "$WORK/slices.tsv"
    cur="$nxt"
  done
  : > "$WORK/scan_raw.tsv"
  local n_slices=0 s e total
  while IFS=$'\t' read -r s e; do
    n_slices=$((n_slices+1))
    total="$(api_get "repos/$OWNER/$REPO/actions/runs?event=merge_group&created=$s..$e&per_page=100" \
      --paginate --jq '
        if .total_count > '"$RESULT_CAP"' then "CAPBREACH\t" + (.total_count|tostring)
        else (.workflow_runs[]
          | select(.path | test("'"$GATE_PATH_RE"'"))
          | "RUN\t" + ([.id, (.conclusion // "null")] | @tsv))
        end' | tee "$WORK/slice_$n_slices.tsv")" || {
      echo "[mla] HARD-FAIL: slice query $s..$e" >&2; exit 1; }
    if printf '%s\n' "$total" | grep -q '^CAPBREACH'; then
      echo "[mla] HARD-FAIL: slice $s..$e total_count > $RESULT_CAP — silent truncation risk; narrow the window" >&2
      exit 1
    fi
    grep '^RUN' "$WORK/slice_$n_slices.tsv" >> "$WORK/scan_raw.tsv" || true
  done < "$WORK/slices.tsv"
  sort -t $'\t' -k2,2n -u "$WORK/scan_raw.tsv" | awk -F'\t' '{print $2}' > "$idsfile"
  SCAN_SEEN="$(sort -t $'\t' -k2,2n -u "$WORK/scan_raw.tsv" | wc -l | tr -d ' ')"
  SCAN_INCLUDED="$(wc -l < "$idsfile" | tr -d ' ')"
  SCAN_SLICES="$n_slices"
}
# ============================================================== compare mode ===
cat > "$WORK/compare.jq" <<'EOF'
([.base[]])  as $B | ([.after[]]) as $A |
([$B[] | select(.classification == "EXECUTED")]) as $Be |
([$A[] | select(.classification == "EXECUTED")]) as $Ae |
([$Be[] | select(.regime == "L")]) as $BeL | ([$Be[] | select(.regime == "H")]) as $BeH |
([$Ae[] | select(.regime == "L")]) as $AeL | ([$Ae[] | select(.regime == "H")]) as $AeH |
([$B[] | select(.classification == "FULL_REUSE")]) as $Br | ([$A[] | select(.classification == "FULL_REUSE")]) as $Ar |
([$Be[] | .dur_sum_s])  as $durB |  ([$Ae[] | .dur_sum_s])  as $durA |
([$Be[] | .gaps_sum_s]) as $gapB |  ([$Ae[] | .gaps_sum_s]) as $gapA |
([$Be[] | .residual_s]) as $resB |  ([$Ae[] | .residual_s]) as $resA |
([$Be[] | .wall_s])     as $walB |  ([$Ae[] | .wall_s])     as $walA |
([$B[]  | .wall_s])     as $woB |  ([$A[]  | .wall_s])     as $woA |
([$Be[] | select(.go_step_s != null) | .go_step_s]) as $goB |
([$Ae[] | select(.go_step_s != null) | .go_step_s]) as $goA |
([$BeL[] | .dur_sum_s]) as $durBL | ([$AeL[] | .dur_sum_s]) as $durAL |
([$BeH[] | .dur_sum_s]) as $durBH | ([$AeH[] | .dur_sum_s]) as $durAH |
([$BeL[] | .wall_s])    as $walBL | ([$AeL[] | .wall_s])    as $walAL |
([$BeH[] | .wall_s])    as $walBH | ([$AeH[] | .wall_s])    as $walAH |
(.resolution_s) as $res |
def dmean($x; $y): (if ($x | stats(.)).mean == null or ($y | stats(.)).mean == null then null
                    else r1((($y | stats(.)).mean) - (($x | stats(.)).mean)) end);
def regdelta($xb; $xa): (if ($xb | stats(.)).n == 0 or ($xa | stats(.)).n == 0 then null
                         else r1((($xa | stats(.)).mean) - (($xb | stats(.)).mean)) end);
{
  schema: "axiom.merge_latency.compare/1",
  tool: "tools/ci/merge_latency_audit.sh",
  collected_at: .collected,
  boundary_note: (if .boundary_note == "" then null else .boundary_note end),
  rules_note: "duration statistics over EXECUTED runs only (A2.1.3); wall reported both operational (ALL) and executed-only; regime split L/H per E3 §5.2 (≤/> 40000 ms)",
  counts: {
    baseline: {runs: ($B | length), executed: ($Be | length), full_reuse: ($Br | length),
               full_reuse_run_ids: [$Br[] | .run_id],
               partial_reuse: ([$B[] | select(.classification == "PARTIAL_REUSE")] | length),
               unknown_log: ([$B[] | select(.classification == "UNKNOWN_LOG")] | length),
               regimes: {L: ($BeL | length), H: ($BeH | length)}},
    after:    {runs: ($A | length), executed: ($Ae | length), full_reuse: ($Ar | length),
               full_reuse_run_ids: [$Ar[] | .run_id],
               partial_reuse: ([$A[] | select(.classification == "PARTIAL_REUSE")] | length),
               unknown_log: ([$A[] | select(.classification == "UNKNOWN_LOG")] | length),
               regimes: {L: ($AeL | length), H: ($AeH | length)}}
  },
  rows: [
    {component: "wall_s [operational, ALL]",
     base: ($woB | stats(.)), after: ($woA | stats(.)), delta: dmean($woB; $woA),
     delta_L: null, delta_H: null},
    {component: "wall_s [EXECUTED only]",
     base: ($walB | stats(.)), after: ($walA | stats(.)), delta: dmean($walB; $walA),
     delta_L: regdelta($walBL; $walAL), delta_H: regdelta($walBH; $walAH)},
    {component: "dur_sum_s",
     base: ($durB | stats(.)), after: ($durA | stats(.)), delta: dmean($durB; $durA),
     delta_L: regdelta($durBL; $durAL), delta_H: regdelta($durBH; $durAH)},
    {component: "gaps_sum_s",
     base: ($gapB | stats(.)), after: ($gapA | stats(.)), delta: dmean($gapB; $gapA),
     delta_L: null, delta_H: null},
    {component: "residual_s",
     base: ($resB | stats(.)), after: ($resA | stats(.)), delta: dmean($resB; $resA),
     delta_L: null, delta_H: null},
    {component: "go_step_s",
     base: ($goB | stats(.)), after: ($goA | stats(.)), delta: dmean($goB; $goA),
     delta_L: null, delta_H: null}
  ],
  termination_inputs: {
    note: "loop stop rule: next lever's expected saving must exceed BOTH measurement resolution AND run-to-run variation → required_min_saving_s = max(resolution_s, sd_base, sd_after)",
    resolution_s: $res,
    per_component: [
      {component: "wall_s [EXECUTED]", sd_base: ($walB | stats(.)).sd, sd_after: ($walA | stats(.)).sd,
       required_min_saving_s: ([$res, ($walB | stats(.)).sd // 0, ($walA | stats(.)).sd // 0] | max)},
      {component: "dur_sum_s", sd_base: ($durB | stats(.)).sd, sd_after: ($durA | stats(.)).sd,
       required_min_saving_s: ([$res, ($durB | stats(.)).sd // 0, ($durA | stats(.)).sd // 0] | max)},
      {component: "gaps_sum_s", sd_base: ($gapB | stats(.)).sd, sd_after: ($gapA | stats(.)).sd,
       required_min_saving_s: ([$res, ($gapB | stats(.)).sd // 0, ($gapA | stats(.)).sd // 0] | max)},
      {component: "residual_s", sd_base: ($resB | stats(.)).sd, sd_after: ($resA | stats(.)).sd,
       required_min_saving_s: ([$res, ($resB | stats(.)).sd // 0, ($resA | stats(.)).sd // 0] | max)}
    ]
  }
}
EOF

cat > "$WORK/compare_md.jq" <<'EOF'
def fm($x): if $x == null then "—" else (if $x == ($x | round) then "\($x | round)" else "\($x)" end) end;
def cell($st): if ($st.n // 0) == 0 then "—"
               elif $st.sd == null then "\(fm($st.mean)) (n=\($st.n))"
               else "\(fm($st.mean))±\(fm($st.sd)) (n=\($st.n))" end;
(.termination_inputs.resolution_s) as $resv |
"# 병합 지연 BEFORE/AFTER 비교 — merge_latency_audit.sh compare\n",
"collected_at: \(.collected_at)\n",
"boundary_note: \(if .boundary_note then .boundary_note else "—" end)\n",
"\n| component | baseline mean±sd | after mean±sd | delta | Δ_L | Δ_H |\n|---|---|---|---|---|---|\n",
([.rows[] |
  "| \(.component) | \(cell(.base)) | \(cell(.after)) | \(fm(.delta)) | \(fm(.delta_L)) | \(fm(.delta_H)) |\n"] | join("")),
"\nREUSED stratum (A2.1): baseline FULL_REUSE=\(.counts.baseline.full_reuse) \( .counts.baseline.full_reuse_run_ids ) / after FULL_REUSE=\(.counts.after.full_reuse) \( .counts.after.full_reuse_run_ids )\n",
"- baseline: runs=\(.counts.baseline.runs) executed=\(.counts.baseline.executed) partial_reuse=\(.counts.baseline.partial_reuse) unknown_log=\(.counts.baseline.unknown_log) regimes(L/H)=\(.counts.baseline.regimes.L)/\(.counts.baseline.regimes.H)\n",
"- after:    runs=\(.counts.after.runs) executed=\(.counts.after.executed) partial_reuse=\(.counts.after.partial_reuse) unknown_log=\(.counts.after.unknown_log) regimes(L/H)=\(.counts.after.regimes.L)/\(.counts.after.regimes.H)\n",
"\n### Variance-aware termination inputs\n",
"\n| component | sd (baseline) | sd (after) | resolution_s | required_min_saving_s |\n|---|---|---|---|---|\n",
([.termination_inputs.per_component[] |
  "| \(.component) | \(fm(.sd_base)) | \(fm(.sd_after)) | \($resv) | \(fm(.required_min_saving_s)) |\n"] | join("")),
"\n판정 규칙: 다음 레버의 기대 절감이 각 성분의 required_min_saving_s (측정 분해능과 런간 변동을 모두 초과)를 넘지 못하면 루프 종료.\n"
EOF

load_side() { # $1=arg $2=out jsonl
  case "$1" in
    *.runs.jsonl)
      [ -s "$1" ] || { echo "[mla] FAIL: artifact not found: $1" >&2; exit 2; }
      cp "$1" "$2" ;;
    *)
      local ids
      ids="$(resolve_runs_arg "$1")"
      [ -n "$ids" ] || { echo "[mla] FAIL: empty run set: $1" >&2; exit 2; }
      measure_ids "$ids" "$2" "$( [ "$NO_LOGS" = "1" ] && echo 0 || echo 1 )" ;;
  esac
}

emit_compare() { # $1=base.jsonl $2=after.jsonl $3=out prefix
  jq -c -n --slurpfile base "$1" --slurpfile after "$2" \
    --arg collected "$COLLECTED_AT" --arg boundary "$BOUNDARY_NOTE" \
    --argjson resolution "$RESOLUTION_S" \
    '{base: $base, after: $after, collected: $collected,
      boundary_note: $boundary, resolution_s: $resolution}' \
  | jq -f "$WORK/compare_full.jq" > "$3.compare.json"
  jq -r -f "$WORK/compare_md.jq" "$3.compare.json" > "$3.compare.md"
}

# ================================================================ snet mode ====
cat > "$WORK/snet_run.jq" <<'EOF'
. as $doc |
($doc.jobs | map({s: (if .started_at == "" then null else (.started_at | iso2epoch) end),
                   e: (if .completed_at == "" then null else (.completed_at | iso2epoch) end),
                   job_id: .job_id, name: .name,
                   executed: (.conclusion != "skipped" and .started_at != "" and .completed_at != "")})
        | map(select(.executed))) as $ej |
([$doc.steps[] | select(.conclusion == "success" and .s != null and .e != null
    and (.name | test($rx)) and ($jr == "" or (.job_name | test($jr))))
  | {s: (.s | iso2epoch), e: (.e | iso2epoch), job_id: .job_id}]) as $ivs |
([$ivs[] | . as $iv |
   ([$ej[] | select(.job_id != $iv.job_id)] | map([.s, .e])) as $holes |
   subtract_holes([$iv.s, $iv.e]; $holes)]
 | flatten(1)) as $frags |
{
  run_id: ($doc.run_id | tonumber),
  matched_steps: ($ivs | length),
  total_s: ([$ivs[] | (.e - .s)] | add // 0),
  visible_s: union_measure($frags),
  hidden_s: (([$ivs[] | (.e - .s)] | add // 0) - union_measure($frags))
}
EOF

cat > "$WORK/snet.jq" <<'EOF'
(.baseline_provision) as $prov_override |
([.base[] | .producer.visible_s])  as $bp |
([.base[] | .consumer.visible_s])  as $bc |
([.after[] | .producer.visible_s]) as $ap |
([.after[] | .consumer.visible_s]) as $ac |
([$bp[] ] | stats(.)) as $bpS | ([$ap[]] | stats(.)) as $apS |
([$bc[] ] | stats(.)) as $bcS | ([$ac[]] | stats(.)) as $acS |
(if $prov_override == null then $bpS.mean else $prov_override end) as $T_old |
(if $apS.mean == null or $bpS.mean == null then null else r1($apS.mean - $bpS.mean) end) as $dT_prod |
(if $acS.mean == null or $bcS.mean == null then null else r1($acS.mean - $bcS.mean) end) as $dT_cons |
{
  schema: "axiom.merge_latency.snet/1",
  tool: "tools/ci/merge_latency_audit.sh",
  collected_at: .collected,
  boundary_note: (if .boundary_note == "" then null else .boundary_note end),
  definitions: {
    formula: "S_net = T_old_provision − ΔT_producer − ΔT_consumer",
    T_old_provision: (if $prov_override == null
                      then "baseline mean of producer visible wall (measured)"
                      else "override constant (--baseline-provision)" end),
    delta_t_producer: "after mean − baseline mean of producer-step VISIBLE wall (steps hidden under parallel predecessor jobs count only their visible portion; overlapping steps in the set count once)",
    delta_t_consumer: "after mean − baseline mean of consumer-step VISIBLE wall (consumer additions typically absent in baseline → equals total)",
    units: "seconds (api-second-granularity, ±1 s)"
  },
  T_old_provision_s: $T_old,
  delta_t_producer_s: $dT_prod,
  delta_t_consumer_s: $dT_cons,
  S_net_s: (if $T_old == null or $dT_prod == null or $dT_cons == null then null
            else r1($T_old - $dT_prod - $dT_cons) end),
  stats: {
    producer: {baseline_visible: $bpS, after_visible: $apS},
    consumer: {baseline_visible: $bcS, after_visible: $acS}
  },
  per_run: {baseline: .base, after: .after}
}
EOF

emit_snet_side() { # $1=ids|artifact $2=out side.jsonl (per-run producer/consumer metrics)
  local ids
  ids="$(resolve_runs_arg "$1")"
  [ -n "$ids" ] || { echo "[mla] FAIL: empty run set: $1" >&2; exit 2; }
  : > "$2"
  printf '%s\n' "$ids" | tr ',' '\n' | while read -r rid; do
    rid="$(printf '%s\n' "$rid" | tr -d '[:space:]')"
    [ -n "$rid" ] || continue
    local rec
    rec="$(fetch_run_record "$rid" 2>/dev/null)" || {
      echo "[mla] HARD-FAIL: run record fetch failed for run $rid" >&2; exit 1; }
    local path attempt
    path="$(jq -r '.path // ""' <<<"$rec")"
    attempt="$(jq -r '.run_attempt // 1' <<<"$rec")"
    if ! [[ "${path##*/}" =~ $GATE_PATH_RE ]]; then
      echo "[mla] HARD-FAIL: run $rid path '$path' is not an admission-gate run (allowlist: ${GATE_PATH_RE})" >&2
      exit 1
    fi
    local jobs_tsv
    jobs_tsv="$(fetch_jobs_tsv "$rid" "$attempt" 2>/dev/null || true)"
    [ -n "$jobs_tsv" ] || { echo "[mla] HARD-FAIL: jobs fetch failed for run $rid" >&2; exit 1; }
    printf '%s\n' "$jobs_tsv" | jq -Rn '
      [inputs | select(length > 0) | split("\t")
       | {job_id: (.[0] | tonumber), name: .[1], started_at: .[2], completed_at: .[3], conclusion: .[4]}]
    ' > "$WORK/sjobs_$rid.json"
    # steps of every executed job, flattened to step-level JSONL with job identity
    : > "$WORK/ssteps_$rid.json"
    : > "$WORK/ssteps_raw_$rid.txt"
    local jid
    for jid in $(jq -r '.[] | select(.conclusion == "success") | .job_id' "$WORK/sjobs_$rid.json"); do
      fetch_job_steps "$jid" \
        | jq -c --argjson jid "$jid" \
            --arg jname "$(jq -r --argjson jid "$jid" '.[] | select(.job_id == $jid) | .name' "$WORK/sjobs_$rid.json")" \
            '.[] | .job_id = $jid | .job_name = $jname' >> "$WORK/ssteps_raw_$rid.txt" || true
    done
    if [ -s "$WORK/ssteps_raw_$rid.txt" ]; then
      jq -s '.' "$WORK/ssteps_raw_$rid.txt" > "$WORK/ssteps_$rid.json"
    else
      echo '[]' > "$WORK/ssteps_$rid.json"
    fi
    cp "$WORK/snet_run_body_full.jq" "$WORK/snet_prog.jq"
    jq -c -n \
      --arg run_id "$rid" \
      --arg psteps "$PRODUCER_STEPS_RE" --arg csteps "$CONSUMER_STEPS_RE" \
      --arg pjob "$PRODUCER_JOB_RE" --arg cjob "$CONSUMER_JOB_RE" \
      --slurpfile jobs "$WORK/sjobs_$rid.json" \
      --slurpfile steps "$WORK/ssteps_$rid.json" \
      -f "$WORK/snet_prog.jq" > "$WORK/snetrec_$rid.json"
    cat "$WORK/snetrec_$rid.json" >> "$2"
    echo "[mla] snet run $rid: producer vis=$(jq -r '.producer.visible_s' "$WORK/snetrec_$rid.json")s consumer vis=$(jq -r '.consumer.visible_s' "$WORK/snetrec_$rid.json")s"
  done
}

cat > "$WORK/snet_run_body.jq" <<'EOF'
def side($rx; $jr; $jobs; $steps):
  ($jobs | map(select(.executed))) as $ej |
  ([$steps[] | select(.conclusion == "success" and .s != null and .e != null
      and (.name | test($rx)) and ($jr == "" or (.job_name | test($jr))))
    | {s: (.s | iso2epoch), e: (.e | iso2epoch), job_id: .job_id}]) as $ivs |
  ([$ivs[] | . as $iv |
     ([$ej[] | select(.job_id != $iv.job_id)] | map([.s, .e])) as $holes |
     subtract_holes([$iv.s, $iv.e]; $holes)]
   | flatten(1)) as $frags |
  {
    matched_steps: ($ivs | length),
    total_s: ([$ivs[] | (.e - .s)] | add // 0),
    visible_s: union_measure($frags),
    hidden_s: (([$ivs[] | (.e - .s)] | add // 0) - union_measure($frags))
  };
{
  run_id: ($run_id | tonumber),
  producer: side($psteps; $pjob; $jobs[0]; $steps[0]),
  consumer: side($csteps; $cjob; $jobs[0]; $steps[0])
}
EOF

cat > "$WORK/snet_md.jq" <<'EOF'
def fm($x): if $x == null then "—" else (if $x == ($x | round) then "\($x | round)" else "\($x)" end) end;
"# S_net 손유표 — merge_latency_audit.sh snet\n",
"collected_at: \(.collected_at)\n",
"boundary_note: \(if .boundary_note then .boundary_note else "—" end)\n",
"\n정의: S_net = T_old_provision − ΔT_producer − ΔT_consumer (겹침 이중계산 없음 — 평행 선행 job에 가려진 스텝 구간은 보이는 벽시계 몫만 계수)\n",
"\n- T_old_provision: \(fm(.T_old_provision_s)) s\n",
"- ΔT_producer: \(fm(.delta_t_producer_s)) s\n",
"- ΔT_consumer: \(fm(.delta_t_consumer_s)) s\n",
"- **S_net: \(fm(.S_net_s)) s**\n",
"\n| run set | component | n | mean | total mean (unadjusted) | hidden mean |\n|---|---|---|---|---|---|\n",
([(.per_run.baseline[] | {side: "baseline", c: "producer", d: .producer}),
  (.per_run.baseline[] | {side: "baseline", c: "consumer", d: .consumer}),
  (.per_run.after[]    | {side: "after",    c: "producer", d: .producer}),
  (.per_run.after[]    | {side: "after",    c: "consumer", d: .consumer})]
 | group_by(.side + "/" + .c)[] |
  ([.[].d.visible_s]) as $v | ([.[].d.total_s]) as $t | ([.[].d.hidden_s]) as $h |
  "| \((.[0].side)) \((.[0].c)) | n=\(length) | \(fm(($v | add) / ($v | length))) | \(fm(($t | add) / ($t | length))) | \(fm(($h | add) / ($h | length))) |\n")
EOF

# program files get the shared library prepended (jq has no cross-file include)
for prog in record summary compare compare_md snet snet_md snet_run_body; do
  cat "$WORK/lib.jq" "$WORK/$prog.jq" > "$WORK/${prog}_full.jq"
done

# ================================================================== main flow ==
case "$MODE" in
  measure)
    if [ -n "$RUNS_ARG" ]; then
      IDS="$(resolve_runs_arg "$RUNS_ARG")"
      WINDOW_JSON="null"; SCAN_JSON="null"
    elif [ -n "$SINCE" ] && [ -n "$UNTIL" ]; then
      scan_window "$SINCE" "$UNTIL" "$WORK/win_ids.txt"
      IDS="$(paste -sd, "$WORK/win_ids.txt")"
      WINDOW_JSON="$(jq -cn --arg s "$SINCE" --arg e "$UNTIL" '{since: $s, until: $e}')"
      SCAN_JSON="$(jq -cn --arg seen "${SCAN_SEEN:-0}" --arg inc "${SCAN_INCLUDED:-0}" --arg sl "${SCAN_SLICES:-0}" \
        '{merge_group_gate_runs_seen: ($seen|tonumber), included_success: ($inc|tonumber), slices: ($sl|tonumber),
         cap_policy: "HARD-FAIL on total_count > '"$RESULT_CAP"' in any ≤1-day slice (silent-truncation guard)"}')"
    else
      echo "[mla] FAIL: measure needs --runs IDS or --since X --until Y" >&2
      exit 2
    fi
    [ -n "$IDS" ] || { echo "[mla] HARD-FAIL: no admission-gate success runs selected" >&2; exit 1; }
    measure_ids "$IDS" "$OUT_PREFIX.runs.jsonl" "$( [ "$NO_LOGS" = "1" ] && echo 0 || echo 1 )"
    emit_summary "$OUT_PREFIX.runs.jsonl" "$OUT_PREFIX.summary.json" "$WINDOW_JSON" "$SCAN_JSON"
    echo "[mla] measure complete: $OUT_PREFIX.runs.jsonl + $OUT_PREFIX.summary.json"
    ;;

  compare)
    load_side "$BASE_ARG" "$WORK/base.jsonl"
    load_side "$AFTER_ARG" "$WORK/after.jsonl"
    CMP_PREFIX="$OUT_PREFIX"; CMP_PREFIX="${CMP_PREFIX%/}"
    emit_compare "$WORK/base.jsonl" "$WORK/after.jsonl" "$CMP_PREFIX"
    echo "[mla] compare complete: $CMP_PREFIX.compare.json + $CMP_PREFIX.compare.md"
    ;;

  snet)
    PRODUCER_STEPS_RE="$(printf '%s' "$PRODUCER_STEPS" | tr ',' '|')"
    CONSUMER_STEPS_RE=""
    if [ -n "$CONSUMER_STEPS" ]; then
      CONSUMER_STEPS_RE="$(printf '%s' "$CONSUMER_STEPS" | tr ',' '|')"
    fi
    PROV_OVERRIDE="null"
    if [ -n "$BASELINE_PROVISION" ]; then
      printf '%s' "$BASELINE_PROVISION" | grep -qE '^[0-9]+(\.[0-9]+)?$' || {
        echo "[mla] FAIL: --baseline-provision must be a number of seconds" >&2; exit 2; }
      PROV_OVERRIDE="$BASELINE_PROVISION"
    fi
    emit_snet_side "$BASE_ARG" "$WORK/sbase.jsonl"
    emit_snet_side "$AFTER_ARG" "$WORK/safter.jsonl"
    SNET_PREFIX="$OUT_PREFIX"; SNET_PREFIX="${SNET_PREFIX%/}"
    jq -c -n --slurpfile base "$WORK/sbase.jsonl" --slurpfile after "$WORK/safter.jsonl" \
      --arg collected "$COLLECTED_AT" --arg boundary "$BOUNDARY_NOTE" \
      --argjson baseline_provision "$PROV_OVERRIDE" \
      '{base: $base, after: $after, collected: $collected,
        boundary_note: $boundary, baseline_provision: $baseline_provision}' \
    | jq -f "$WORK/snet_full.jq" > "$SNET_PREFIX.snet.json"
    jq -r -f "$WORK/snet_md.jq" "$SNET_PREFIX.snet.json" > "$SNET_PREFIX.snet.md"
    echo "[mla] snet complete: $SNET_PREFIX.snet.json + $SNET_PREFIX.snet.md"
    ;;
esac
