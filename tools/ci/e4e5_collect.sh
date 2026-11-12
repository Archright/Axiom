#!/usr/bin/env bash
#
# e4e5_collect.sh — E-4/E-5 merge-admission collection pass (GET-only, single-pass).
#
# Contract: docs/evidence/e3_measurement_contract_2026-10-11.md (merge ad43e67fa,
# 2026-10-11T02:52:14Z) + 개정 기록 A1. This is the OPERATIONAL ARTIFACT of the
# 30-day collection window (§5.6 stop rule (b)): the window anchor is the
# contract document's own merge instant 2026-10-11T02:52:14Z → 2026-11-10T02:52:14Z.
# Re-running it as the window fills re-scans the whole window to date; the latest
# scan is a superset of earlier ones.
#
# What it collects (§5.4 machine criteria, wide-boundary query + client filter):
#   * admission-gate runs, event=merge_group — the consumption side
#   * ci-cache-publisher runs, event=workflow_run — the seed side
# Per eligible admission-gate run, the `attest / admission-check` job log is
# fetched and key-identification lines are extracted:
#   AXIOM_CACHE_KEYGEN: a-key=… / b-identity=… b-key=… probe-tree=…
#   AXIOM_CACHE_B_RESTORE: exact-hit=… requested-key=… primary-key=… matched-key=…   (#724)
#   AXIOM_CACHE_B_VERIFY: anchor — … recipe=… a_fp=… / RESULT OK — n/n
#   AXIOM_CACHE_B_PROBE: OK
#   [test-supply] restored build/nimcache/test entries=N
# Per publisher run, the `publish` job log is fetched and seed lines extracted:
#   [publish] base-guard=… base-key=…   /   [publish] base-save: outcome=…
#   [publish-skip] base key exists — save withheld (single-flight): <key>  (#724)
#   [publish] guard=… key=…             /   [publish] lane-save: outcome=…
#   [publish-skip] reason=…             (#724 skip-reason instrumentation)
#
# Authority (AGENTS.md §2.3, Authority ≠ Adapter): run existence/status =
# GitHub Actions API; key identity algebra = keygen log lines (contract §9);
# this tool is a REPORTER — it emits no judgment verdict and changes no gate.
#
# Purity: read-only. Every network call is an API GET (gh api). No mutation,
# rerun, or write path exists in this file. No polling loops — one pass per run.
#
# §5.6(c) boundary: this tool does NOT extract GO-critical durations. Interim
# duration extraction is forbidden by the measurement contract; only design
# variables (HIT/MISS, key/generation attribution, timestamps) are recorded.
#
# REUSED-run recording (structural, not result values): per consumer job the
# emitted `[admission-tests] SKIP — …` / `[admission-tests] RUN make
# test-fast-one` lines are counted (timestamp-anchored, like every pattern
# here). skip_lines > 0 ∧ run_lines = 0 ⇒ every GO-critical subject hit
# Judgment CAS basis=REUSED (kernel skip ⇒ GO-critical step ≈ 0 s). Such runs
# are recorded with admission_tests.reused_skip=true + the job wall-clock and
# are NEVER dropped from the operational ledger. Their purpose-based
# classification (non-observation for the duration estimand vs separate
# operational type) is defined by the forthcoming contract amendment; the
# classification-side hook lives in tools/ci/e4e5_classify.sh.
#
# Silent-truncation mitigation: `created`+`event` search results cap at 1,000
# with NO error (docs.github.com REST reference, "List workflow runs for a
# repository": "This endpoint will return up to 1,000 results for each search"
# for the actor/branch/check_suite_id/created/event/head_sha/status filters).
# The window is scanned in fixed ≤1-day slices; a slice whose `total_count`
# exceeds the cap is split at the exact UTC midpoint (integer seconds,
# s + (e−s)/2) and rescanned recursively in chronological order — every leaf
# sub-slice issues its own query and contributes its own RUN lines. A slice at
# the 300 s (5 min) floor that still breaches HARD-FAILS the whole pass
# (exit 1, fail-closed — no ledger): results fetched from a breached range are
# discarded, never merged into the ledger; n_slices counts leaf scans.
#
# Re-run quirk compliance (docs/spec/gh_merge_admission_observation_quirks.md):
#   Q2 — `gh run view`/`--log` 404 for merge_group admission-gate runs; log
#        bodies come via /actions/runs/{id}/jobs → /actions/jobs/{id}/logs.
#   Q3 (gh_run_observation_quirks) — job logs carry ANSI escapes; `gh api`
#        requires --allow-escape-sequences (else empty output + failure that
#        mimics log absence); escapes are stripped before matching.
#   Q1 (gh_merge_admission…, advisory) — run records are platform facts;
#        eligibility here is contract-bookkeeping, never a merge verdict.
#
# Observation-unit rule (recorded in ledger meta): re-runs keep the run id and
# increment run_attempt while resetting run_started_at. Each (run_id,
# run_attempt) is a separate observation; attempts are enumerated from
# /runs/{id}/attempts when run_attempt > 1 and both are recorded.
#
# Output: data/e4e5/ledger.json (full-window scan, overwritten each pass),
#         data/e4e5/collection_log.jsonl (one provenance line per pass).
#
# Exit codes: 0 = collection pass complete (UNKNOWN-key runs are a normal
#             outcome, reported, never excluded silently)
#             1 = hard failure (result-cap breach, structural API failure)
#                 — fail-closed, no ledger written; empty/failed log fetches
#                 are NOT hard failures (WARN + UNKNOWN-seed/UNKNOWN-key)
#             2 = usage/environment error (gh unavailable, bad arguments)

set -euo pipefail

OWNER="Archright"
REPO="Axiom"
# Contract fixation parameters — constants from the contract document, not
# derived from wall clock (the window anchor is the contract's merge instant).
CONTRACT_MERGE_OID="ad43e67fac29e676d9eb952652297ccd95fb11d4"
WINDOW_START="2026-10-11T02:52:14Z"
WINDOW_END="2026-11-10T02:52:14Z"
INTERVENTION_MERGE_OID="2ea11a3a5c155503d87e30efd87b7f1f2e74b7ac"
INTERVENTION_MERGE_AT="2026-10-10T22:39:36Z"
# 게이트 path 세대: 2026-10-16 rename(admission-gate.yml → admission-gate-v2.yml)이
# 수집 창(2026-10-11T02:52:14Z ~ 2026-11-10T02:52:14Z) 내부에 있다. 한 세대만
# 스캔하면 창의 한쪽이 구조적으로 누락된다 — 양 세대를 동일 게이트로 함께 스캔한다
# (선례: tools/ci/merge_latency_audit.sh의 gate path regex, 그 외는 fail-closed).
GATE_PATH="admission-gate-v2.yml"
GATE_PATH_LEGACY="admission-gate.yml"
PUBLISHER_PATH="ci-cache-publisher.yml"
CONSUME_JOB="attest / admission-check"
SEED_JOB="publish"

OUT_DIR="data/e4e5"
NOW_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --now)     NOW_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '2,60p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--out-dir DIR] [--now ISO8601]" >&2; exit 2 ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "[e4e5] FAIL: gh not available" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "[e4e5] FAIL: jq not available" >&2; exit 2; }

COLLECTED_AT="${NOW_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
SCAN_END="$COLLECTED_AT"
if [ "$(date -u -d "$SCAN_END" +%s)" -gt "$(date -u -d "$WINDOW_END" +%s)" ]; then
  SCAN_END="$WINDOW_END"
fi
if [ "$(date -u -d "$SCAN_END" +%s)" -le "$(date -u -d "$WINDOW_START" +%s)" ]; then
  echo "[e4e5] FAIL: scan end $SCAN_END not after window start $WINDOW_START" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT_DIR" "$WORK/runs" "$WORK/seeds"

# ---------------------------------------------------------------- slice scan
# Wide-boundary query per slice: server filters event+created; the path
# filter is applied client-side (contract criteria are client-side bookkeeping).
#
# Adaptive split: a slice breaching the cap (SPLIT_CAP, the API's silent
# 1,000-result search cap — literal mirrored in the jq guard below) and longer
# than SPLIT_FLOOR_SECONDS is split at the exact UTC midpoint and rescanned
# recursively; halves are scanned left→right, so chronological order is
# preserved. Durations strictly decrease per split (both halves ≤ dur−150 s),
# so recursion terminates. A breach at the floor is fail-closed: HARD-FAIL the
# whole pass exactly as before — nothing from the breached range is used.
SPLIT_CAP=1000
SPLIT_FLOOR_SECONDS=300

scan_target() { # $1=event $2=path-suffix $3=slice_start $4=slice_end $5=outfile (RUN lines appended, leaves only)
  local ev="$1" suffix="$2" s="$3" e="$4" out="$5" total n s_sec e_sec mid mid_iso
  total="$(gh api "repos/$OWNER/$REPO/actions/runs?event=$ev&created=$s..$e&per_page=100" \
    --paginate --jq '
      if .total_count > 1000 then "CAPBREACH\t" + (.total_count|tostring)
      else (.workflow_runs[]
        # Q6: workflow_run.path는 @ref suffix를 가질 수 있다 — 정규화 후 비교
        # (exact bare-path match은 비정상). 두 스캔(gate·publisher) 공통.
        | select((((.path // "") | split("@")[0]) | endswith("'"$suffix"'")))
        | "RUN\t" + ([.id, .name, .path, .event, .created_at, .run_started_at,
                      .run_attempt, (.conclusion // "null"), .head_sha] | @tsv))
      end')" || { echo "[e4e5] FAIL: slice query $s..$e event=$ev" >&2; exit 1; }
  if printf '%s\n' "$total" | grep -q '^CAPBREACH'; then
    n="$(printf '%s\n' "$total" | grep '^CAPBREACH' | head -1 | cut -f2)"
    s_sec="$(date -u -d "$s" +%s)"; e_sec="$(date -u -d "$e" +%s)"
    if [ $((e_sec - s_sec)) -le "$SPLIT_FLOOR_SECONDS" ]; then
      echo "[e4e5] HARD-FAIL: slice $s..$e event=$ev total_count=$n > $SPLIT_CAP — silent truncation risk; slice floor ${SPLIT_FLOOR_SECONDS}s reached — cannot split further" >&2
      exit 1
    fi
    mid=$(( s_sec + (e_sec - s_sec) / 2 ))
    mid_iso="$(date -u -d "@$mid" +%Y-%m-%dT%H:%M:%SZ)"
    echo "[e4e5] slice $s..$e event=$ev total_count=$n > $SPLIT_CAP — split at midpoint $mid_iso" >&2
    scan_target "$ev" "$suffix" "$s"      "$mid_iso" "$out"
    scan_target "$ev" "$suffix" "$mid_iso" "$e"       "$out"
    return
  fi
  if [ -n "$total" ]; then
    printf '%s\n' "$total" >> "$out"
  fi
  n_slices=$((n_slices+1))
}

SLICES="$WORK/slices.tsv"
: > "$SLICES"
cur="$WINDOW_START"
while [ "$(date -u -d "$cur" +%s)" -lt "$(date -u -d "$SCAN_END" +%s)" ]; do
  nxt="$(date -u -d "$cur +1 day" +%Y-%m-%dT%H:%M:%SZ)"
  if [ "$(date -u -d "$nxt" +%s)" -gt "$(date -u -d "$SCAN_END" +%s)" ]; then
    nxt="$SCAN_END"
  fi
  printf '%s\t%s\n' "$cur" "$nxt" >> "$SLICES"
  cur="$nxt"
done

GATE_RAW="$WORK/gate_raw.tsv"
PUB_RAW="$WORK/pub_raw.tsv"
: > "$GATE_RAW"; : > "$PUB_RAW"
n_slices=0
slice_idx=0
while IFS=$'\t' read -r s e; do
  slice_idx=$((slice_idx+1))
  : > "$WORK/slice_g_$slice_idx.tsv"
  : > "$WORK/slice_g_legacy_$slice_idx.tsv"
  : > "$WORK/slice_p_$slice_idx.tsv"
  scan_target merge_group  "$GATE_PATH"        "$s" "$e" "$WORK/slice_g_$slice_idx.tsv"
  scan_target merge_group  "$GATE_PATH_LEGACY" "$s" "$e" "$WORK/slice_g_legacy_$slice_idx.tsv"
  scan_target workflow_run "$PUBLISHER_PATH"   "$s" "$e" "$WORK/slice_p_$slice_idx.tsv"
  cat "$WORK/slice_g_$slice_idx.tsv" >> "$GATE_RAW"
  cat "$WORK/slice_g_legacy_$slice_idx.tsv" >> "$GATE_RAW"
  cat "$WORK/slice_p_$slice_idx.tsv" >> "$PUB_RAW"
done < "$SLICES"

# Dedup by run id across slice boundaries (id is the key; attempts live inside
# one run record — see observation-unit rule in the header).
dedup() { # $1=rawfile $2=outfile — fields: 1=tag 2=id 6=created_at
  sort -t $'\t' -k2,2n -u "$1" | sort -t $'\t' -k6,6 > "$2"
}
dedup "$GATE_RAW" "$WORK/gate_runs.tsv"
dedup "$PUB_RAW"  "$WORK/pub_runs.tsv"

gate_total=$(grep -c '^RUN' "$WORK/gate_runs.tsv" || true)
pub_total=$(grep -c '^RUN' "$WORK/pub_runs.tsv" || true)
echo "[e4e5] slice scan: $n_slices slice(s) $WINDOW_START → $SCAN_END; admission-gate runs=$gate_total publisher runs=$pub_total"

# -------------------------------------------------- publisher seed extraction
# Save-completion time := the outcome line's log timestamp. That line is
# emitted by the summary step AFTER the save step finished, so it is a LATE
# bound for save completion — deliberately conservative: it makes category B
# (base covered before consumption) harder to claim, i.e. it can only inflate
# the P rate, and the P rate is the removal-harm metric (fail-closed direction).
publisher_lines() { # $1=logfile — emitted lines only (timestamp-anchored)
  sed -E 's/\x1b\[[0-9;]*m//g' "$1" | grep -aE \
    -e '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[publish\] (base-guard|guard)=.*key=' \
    -e '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[publish\] (base|lane)-save: outcome=' \
    -e '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[publish\] lane-lookup: outcome=' \
    -e '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[publish-skip\] ' \
    || true
}

pub_seed_count=0
pub_prefiltered=0
: > "$WORK/seed_events.jsonl"
while IFS=$'\t' read -r _tag id _name _path _ev created started attempt conclusion head_sha; do
  jobs_json="$(gh api "repos/$OWNER/$REPO/actions/runs/$id/jobs?per_page=100")" \
    || { echo "[e4e5] WARN: jobs fetch failed for publisher run $id — recorded as UNKNOWN-seed" >&2
         jq -cn --arg id "$id" --arg created "$created" --arg why "jobs-fetch-failed" \
           '{run_id: ($id|tonumber), created_at: $created, job_id: null, status: "UNKNOWN-seed", reason: $why}' \
           >> "$WORK/seed_events.jsonl" 2>/dev/null || true
         continue; }
  jobs="$(jq -r --arg n "$SEED_JOB" '.jobs[] | select(.name == $n) | [.id, (.conclusion // "null"), .started_at, .completed_at] | @tsv' <<<"$jobs_json")"
  [ -n "$jobs" ] || { echo "[e4e5] WARN: publisher run $id has no '$SEED_JOB' job" >&2; continue; }
  # 스케줄러 pre-filter로 실행되지 않은 런 (2026-10-25~): publish와 skip-report가
  # 모두 skipped. path 조건은 publish.if에만 있으므로 이 조합은 "성공 conclusion +
  # 게이트 path 미인식"과 동치다 — 비성공 conclusion이면 skip-report가 path와 무관하게
  # 반드시 실행되기 때문이다. 따라서 seed 관측이 아니며, 로그가 없는 것은 결함이
  # 아니라 설계 결과다. UNKNOWN-seed로 계수하면 seed-ledger gap이 오염된다.
  skip_report_concl="$(jq -r '[.jobs[] | select(.name == "skip-report") | (.conclusion // "null")][0] // "absent"' <<<"$jobs_json")"
  if [ "$skip_report_concl" = "skipped" ] && [ "$(cut -f2 <<<"$jobs")" = "skipped" ]; then
    pub_prefiltered=$((pub_prefiltered+1))
    continue
  fi
  while IFS=$'\t' read -r job_id job_concl jstart jend; do
    log="$WORK/pub_$id.log"
    if ! gh api --allow-escape-sequences "repos/$OWNER/$REPO/actions/jobs/$job_id/logs" > "$log" 2>/dev/null \
       || [ ! -s "$log" ]; then
      echo "[e4e5] WARN: log fetch empty/failed for publisher job $job_id (run $id) — UNKNOWN-seed (quirks Q3)" >&2
      jq -cn --arg id "$id" --arg created "$created" --arg job "$job_id" --arg why "log-fetch-failed" \
        '{run_id: ($id|tonumber), created_at: $created, job_id: ($job|tonumber), status: "UNKNOWN-seed", reason: $why}' \
        >> "$WORK/seed_events.jsonl" || true
      continue
    fi
    publisher_lines "$log" > "$WORK/publines.txt"
    base_key="$(grep -aE 'Z \[publish\] base-guard=[^ ]+ base-verify=[^ ]* base-key=' "$WORK/publines.txt" | sed -E 's/^.* base-key=([^ ]*).*$/\1/' | head -1 || true)"
    lane_key="$(grep -aE 'Z \[publish\] guard=[^ ]+ trees=[^ ]+ verify=[^ ]* key=' "$WORK/publines.txt" | sed -E 's/^.* verify=[^ ]* key=([^ ]*).*$/\1/' | head -1 || true)"
    base_save="$(grep -aE 'Z \[publish\] base-save: outcome=' "$WORK/publines.txt" | head -1 || true)"
    lane_save="$(grep -aE 'Z \[publish\] lane-save: outcome=' "$WORK/publines.txt" | head -1 || true)"
    lane_lookup="$(grep -aE 'Z \[publish\] lane-lookup: outcome=' "$WORK/publines.txt" | head -1 || true)"
    base_save_outcome="$(printf '%s' "$base_save" | sed -E 's/^.* base-save: outcome=([^ ]+).*/\1/' || true)"
    base_save_ts="$(printf '%s' "$base_save" | sed -E 's/^([0-9T:.Z-]+) .*/\1/' || true)"
    lane_save_outcome="$(printf '%s' "$lane_save" | sed -E 's/^.* lane-save: outcome=([^ ]+).*/\1/' || true)"
    lane_save_ts="$(printf '%s' "$lane_save" | sed -E 's/^([0-9T:.Z-]+) .*/\1/' || true)"
    lane_lookup_hit="$(printf '%s' "$lane_lookup" | sed -E 's/^.* lane-lookup: outcome=[^ ]+ hit=([^ ]*).*/\1/' || true)"
    # Already-seeded proof (single-flight skip carries the pre-existing key).
    exists_key="$(grep -aE 'Z \[publish-skip\] base key exists — save withheld \(single-flight\): ' "$WORK/publines.txt" \
      | sed -E 's/^.*single-flight\): //' | head -1 || true)"
    skip_reasons="$(grep -aE 'Z \[publish-skip\] reason=' "$WORK/publines.txt" | sed -E 's/^[^ ]+Z //' | paste -sd ';' - || true)"
    jq -cn \
      --arg id "$id" --arg created "$created" --arg started "$started" --arg attempt "$attempt" \
      --arg conclusion "$conclusion" --arg head "$head_sha" --arg job "$job_id" \
      --arg jconcl "$job_concl" --arg base_key "$base_key" --arg lane_key "$lane_key" \
      --arg bso "$base_save_outcome" --arg bst "$base_save_ts" \
      --arg lso "$lane_save_outcome" --arg lst "$lane_save_ts" --arg llh "$lane_lookup_hit" \
      --arg exists_key "$exists_key" --arg skip_reasons "$skip_reasons" \
      '{run_id: ($id|tonumber), created_at: $created, run_started_at: $started,
        run_attempt: ($attempt|tonumber), conclusion: $conclusion, head_sha: $head,
        job_id: ($job|tonumber), job_conclusion: $jconcl,
        base_key: (if $base_key == "" then null else $base_key end),
        lane_key: (if $lane_key == "" then null else $lane_key end),
        base_save: {outcome: (if $bso == "" then null else $bso end),
                    ts: (if $bst == "" then null else $bst end)},
        lane_save: {outcome: (if $lso == "" then null else $lso end),
                    ts: (if $lst == "" then null else $lst end)},
        lane_lookup_hit: (if $llh == "" then null else $llh end),
        base_key_exists_skip_key: (if $exists_key == "" then null else $exists_key end),
        publish_skip_reasons: (if $skip_reasons == "" then null else $skip_reasons end),
        evidence_kind: "publisher-log"}' >> "$WORK/seed_events.jsonl"
    pub_seed_count=$((pub_seed_count+1))
  done <<< "$jobs"
done < "$WORK/pub_runs.tsv"

# ------------------------------------------- consumption-side eligibility+extraction
# §5.4 common criteria: admission-gate workflow + attest / admission-check job +
# conclusion success + log preservation + executed from code after 2ea11a3a.
# Post-intervention is operationalized as: (i) created after the intervention
# merge instant (always true in-window; recorded), plus (ii) a compare-API
# ancestry diagnostic (2ea11a3a is an ancestor of the run's head) recorded per
# run; "unknown" ancestry (API failure) keeps eligibility provisional —
# recorded for the §5.4 composition audit, never silently resolved.
intervention_ancestor() { # $1=head_sha → echoes true|false|unknown
  local cmp st mb
  cmp="$(gh api "repos/$OWNER/$REPO/compare/$INTERVENTION_MERGE_OID...$1" \
    --jq '[(.status // "null"), (.merge_base_commit.sha // "null")] | @tsv' 2>/dev/null)" \
    || { echo "unknown"; return; }
  st="$(printf '%s' "$cmp" | cut -f1)"
  mb="$(printf '%s' "$cmp" | cut -f2)"
  if [ "$st" = "ahead" ] || [ "$mb" = "$INTERVENTION_MERGE_OID" ]; then
    echo "true"
  else
    echo "false"
  fi
}

emit_unknown_run() { # $1=run_id $2=run_attempt $3=created $4=job_id $5=reason
  jq -cn --arg id "$1" --arg att "$2" --arg created "$3" --arg job "$4" --arg why "$5" \
    '{run_id: ($id|tonumber), run_attempt: ($att|tonumber), created_at: $created,
      job_id: (if $job == "" then null else ($job|tonumber) end),
      status: "UNKNOWN-key", reason: $why}' >> "$WORK/unknown_runs.jsonl"
}

: > "$WORK/unknown_runs.jsonl"
: > "$WORK/consume_events.jsonl"
eligible=0; unknown_runs=0; ineligible=0
while IFS=$'\t' read -r _tag id _name _path _ev created started attempt conclusion head_sha; do
  # Attempt enumeration (observation-unit rule): the list record is the latest
  # attempt; attempts > 1 are enumerated so every attempt is an observation.
  attempts="$attempt"
  if [ "$attempt" -gt 1 ] 2>/dev/null; then
    att_list="$(gh api "repos/$OWNER/$REPO/actions/runs/$id/attempts" --jq '[.total_count, ([.run_attempts[].run_attempt]|tostring)] | @tsv' 2>/dev/null || true)"
    [ -n "$att_list" ] && attempts="$(printf '%s' "$att_list" | cut -f2 | tr ',' ' ')"
    echo "[e4e5] NOTE: run $id has multiple attempts [$attempts] — each is a separate observation (re-runs reset run_started_at)" >&2
  fi
  for att in $attempts; do
    run_prefix="repos/$OWNER/$REPO/actions/runs/$id"
    if [ "$att" = "$attempt" ]; then
      rec="$(gh api "$run_prefix" --jq '[.run_started_at, (.conclusion // "null")] | @tsv' 2>/dev/null)" || rec=""
      att_started="$(printf '%s' "$rec" | cut -f1)"; att_concl="$(printf '%s' "$rec" | cut -f2)"
      jobs_path="$run_prefix/jobs?per_page=100"
    else
      rec="$(gh api "$run_prefix/attempts/$att" --jq '[.run_started_at, (.conclusion // "null")] | @tsv' 2>/dev/null)" || rec=""
      att_started="$(printf '%s' "$rec" | cut -f1)"; att_concl="$(printf '%s' "$rec" | cut -f2)"
      jobs_path="$run_prefix/attempts/$att/jobs?per_page=100"
    fi
    [ -n "$att_started" ] || { emit_unknown_run "$id" "$att" "$created" "" "run-record-fetch-failed"; unknown_runs=$((unknown_runs+1)); continue; }

    elig="eligible"
    elig_reasons=""
    if [ "$att_concl" != "success" ]; then
      elig="ineligible"; elig_reasons="conclusion=$att_concl"
    fi
    anc="$(intervention_ancestor "$head_sha")"
    post_int_ts="false"
    [ "$(date -u -d "$created" +%s)" -gt "$(date -u -d "$INTERVENTION_MERGE_AT" +%s)" ] && post_int_ts="true"
    if [ "$anc" = "false" ]; then
      elig="ineligible"; elig_reasons="$elig_reasons;intervention-not-ancestor"
    elif [ "$anc" = "unknown" ] && [ "$post_int_ts" = "true" ]; then
      elig="provisional"; elig_reasons="$elig_reasons;ancestry-unknown(created>intervention-merge)"
    fi

    jobs="$(gh api "$jobs_path" --jq '.jobs[] | select(.name == "'"$CONSUME_JOB"'") | [.id, (.conclusion // "null"), .started_at, .completed_at] | @tsv' 2>/dev/null)" || jobs=""
    if [ -z "$jobs" ]; then
      if [ "$elig" != "ineligible" ]; then
        emit_unknown_run "$id" "$att" "$created" "" "no-$CONSUME_JOB-job-or-jobs-fetch-failed"
        unknown_runs=$((unknown_runs+1))
      else
        jq -cn --arg id "$id" --arg att "$att" --arg created "$created" --arg why "$elig_reasons" \
          '{run_id: ($id|tonumber), run_attempt: ($att|tonumber), created_at: $created,
            job_id: null, status: "ineligible", reason: $why}' >> "$WORK/unknown_runs.jsonl"
        ineligible=$((ineligible+1))
      fi
      continue
    fi
    while IFS=$'\t' read -r job_id job_concl jstart jend; do
      if [ "$job_concl" != "success" ]; then
        if [ "$elig" != "ineligible" ]; then
          emit_unknown_run "$id" "$att" "$created" "$job_id" "consume-job-conclusion=$job_concl"
          unknown_runs=$((unknown_runs+1))
        else
          jq -cn --arg id "$id" --arg att "$att" --arg created "$created" --arg job "$job_id" --arg why "$elig_reasons" \
            '{run_id: ($id|tonumber), run_attempt: ($att|tonumber), created_at: $created,
              job_id: ($job|tonumber), status: "ineligible", reason: $why}' >> "$WORK/unknown_runs.jsonl"
          ineligible=$((ineligible+1))
        fi
        continue
      fi
      log="$WORK/consume_${id}_${att}.log"
      if ! gh api --allow-escape-sequences "repos/$OWNER/$REPO/actions/jobs/$job_id/logs" > "$log" 2>/dev/null \
         || [ ! -s "$log" ]; then
        echo "[e4e5] WARN: log fetch empty/failed for job $job_id (run $id attempt $att) — UNKNOWN-key (quirks Q3)" >&2
        emit_unknown_run "$id" "$att" "$created" "$job_id" "log-fetch-failed"
        unknown_runs=$((unknown_runs+1)); continue
      fi
      sed -E 's/\x1b\[[0-9;]*m//g' "$log" > "$WORK/consume_clean.log"
      # Emitted lines only: every pattern is anchored to the log timestamp so
      # script-source echoes (echo "AXIOM_CACHE_KEYGEN: …=$var") never match.
      kgen_b="$(grep -aE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z AXIOM_CACHE_KEYGEN: b-identity=[0-9a-f]{40} b-key=axiom-b-' "$WORK/consume_clean.log" | head -1 || true)"
      kgen_a="$(grep -aE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z AXIOM_CACHE_KEYGEN: a-key=axiom-a-' "$WORK/consume_clean.log" | head -1 || true)"
      bres="$(grep -aE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z AXIOM_CACHE_B_RESTORE: exact-hit=(true|false) requested-key=' "$WORK/consume_clean.log" | head -1 || true)"
      anchor="$(grep -aE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z AXIOM_CACHE_B_VERIFY: anchor — derivation source identity=' "$WORK/consume_clean.log" | head -1 || true)"
      result_ok="$(grep -acE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z AXIOM_CACHE_B_VERIFY: RESULT OK' "$WORK/consume_clean.log" || true)"
      probe_ok="$(grep -acE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z AXIOM_CACHE_B_PROBE: OK' "$WORK/consume_clean.log" || true)"
      tsupply="$(grep -aE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[test-supply\] restored build/nimcache/test entries=[0-9]+' "$WORK/consume_clean.log" | head -1 || true)"
      # REUSED-run recording: structural facts only (which subjects ran/skipped).
      # Anchor discipline identical to every pattern above: the emitted lines
      # start with the log timestamp immediately followed by "[admission-tests]";
      # script-source echoes carry `echo "` right after the timestamp and never
      # match. grep -c prints 0 and exits 1 on no match — || true keeps count.
      att_skip="$(grep -acE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[admission-tests\] SKIP — ' "$WORK/consume_clean.log" || true)"
      att_run="$(grep -acE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z \[admission-tests\] RUN make test-fast-one' "$WORK/consume_clean.log" || true)"

      if [ -z "$kgen_b" ] || [ -z "$bres" ]; then
        reason=""; [ -z "$kgen_b" ] && reason="keygen-line-absent"
        [ -z "$bres" ] && reason="${reason:+$reason+}b-restore-line-absent"
        emit_unknown_run "$id" "$att" "$created" "$job_id" "$reason"
        unknown_runs=$((unknown_runs+1)); continue
      fi
      ts_kgen="$(printf '%s' "$kgen_b" | sed -E 's/^([0-9T:.Z-]+) .*/\1/')"
      b_identity="$(printf '%s' "$kgen_b" | sed -E 's/^.* b-identity=([0-9a-f]{40}) b-key=.*/\1/')"
      b_key="$(printf '%s' "$kgen_b" | sed -E 's/^.* b-key=([^ ]+).*$/\1/')"
      a_key="$(printf '%s' "$kgen_a" | sed -E 's/^.* a-key=([^ ]+).*$/\1/' || true)"
      hit="$(printf '%s' "$bres" | sed -E 's/^.* exact-hit=(true|false) requested-key=.*/\1/')"
      req_key="$(printf '%s' "$bres" | sed -E 's/^.* requested-key=([^ ]*).*/\1/')"
      pri_key="$(printf '%s' "$bres" | sed -E 's/^.* primary-key=([^ ]*).*/\1/')"
      match_key="$(printf '%s' "$bres" | sed -E 's/^.* matched-key=([^ ]*).*/\1/')"
      ts_restore="$(printf '%s' "$bres" | sed -E 's/^([0-9T:.Z-]+) .*/\1/')"
      recipe=""; a_fp=""
      if [ -n "$anchor" ]; then
        recipe="$(printf '%s' "$anchor" | sed -E 's/^.* recipe=([^ ]+).*$/\1/')"
        a_fp="$(printf '%s' "$anchor" | sed -E 's/^.* a_fp=([^ ]+).*$/\1/')"
      fi
      tsupply_n="$(printf '%s' "$tsupply" | sed -E 's/^.* entries=([0-9]+).*/\1/' || true)"
      jq -cn \
        --arg id "$id" --arg att "$att" --arg created "$created" --arg started "$att_started" \
        --arg job "$job_id" --arg jstart "$jstart" --arg jend "$jend" \
        --arg head "$head_sha" --arg anc "$anc" --arg postts "$post_int_ts" \
        --arg elig "$elig" --arg eligwhy "${elig_reasons#;}" \
        --arg ts_kgen "$ts_kgen" --arg identity "$b_identity" --arg bkey "$b_key" \
        --arg akey "$a_key" --arg recipe "$recipe" --arg afp "$a_fp" \
        --arg hit "$hit" --arg req "$req_key" --arg pri "$pri_key" --arg match "$match_key" \
        --arg ts_restore "$ts_restore" --arg tsupply_n "$tsupply_n" \
        --arg att_skip "$att_skip" --arg att_run "$att_run" \
        --argjson result_ok "$result_ok" --argjson probe_ok "$probe_ok" \
        '{run_id: ($id|tonumber), run_attempt: ($att|tonumber), created_at: $created,
          job_id: ($job|tonumber), job_started_at: $jstart, job_completed_at: $jend,
          job_wall_clock_seconds: (if $jend == "" or $jstart == "" then null
                                   else (($jend | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
                                         - ($jstart | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)) end),
          head_sha: $head, intervention_ancestor: $anc, created_after_intervention: ($postts == "true"),
          eligibility: $elig, eligibility_note: (if $eligwhy == "" then null else $eligwhy end),
          keygen: {ts: $ts_kgen, b_identity: $identity, b_key: $bkey, a_key: $akey,
                   recipe_hash: (if $recipe == "" then null else $recipe end),
                   a_fp: (if $afp == "" then null else $afp end)},
          b_restore: {ts: $ts_restore, exact_hit: ($hit == "true"),
                      requested_key: $req, primary_key: $pri, matched_key: $match},
          b_verify_result_ok: ($result_ok > 0), b_probe_ok_count: $probe_ok,
          test_supply_entries: (if $tsupply_n == "" then null else ($tsupply_n|tonumber) end),
          carrier_hit: ($hit == "true"),
          admission_tests: {skip_lines: ($att_skip|tonumber), run_lines: ($att_run|tonumber),
                            reused_skip: ((($att_skip|tonumber) > 0) and (($att_run|tonumber) == 0))},
          evidence_kind: "consumer-log"}' >> "$WORK/consume_events.jsonl"
      if [ "$elig" = "eligible" ] || [ "$elig" = "provisional" ]; then
        eligible=$((eligible+1))
      fi
    done <<< "$jobs"
  done
done < "$WORK/gate_runs.tsv"

# ------------------------------------------------------------------- assembly
n_consume=$(jq -s 'length' "$WORK/consume_events.jsonl")
n_seed=$(jq -s 'length' "$WORK/seed_events.jsonl")
n_unknown=$(jq -s 'length' "$WORK/unknown_runs.jsonl")
n_c=$(jq -s '[.[] | select(.evidence_kind == "consumer-log" and .carrier_hit == false)] | length' "$WORK/consume_events.jsonl" 2>/dev/null || echo 0)
n_b=$(jq -s '[.[] | select(.evidence_kind == "consumer-log" and .carrier_hit == true)] | length' "$WORK/consume_events.jsonl" 2>/dev/null || echo 0)
n_reused=$(jq -s '[.[] | select(.evidence_kind == "consumer-log" and .admission_tests.reused_skip == true)] | length' "$WORK/consume_events.jsonl" 2>/dev/null || echo 0)

jq -n \
  --arg schema "axiom.e4e5.ledger/2" \
  --arg collected "$COLLECTED_AT" \
  --arg scan_end "$SCAN_END" \
  --arg contract_oid "$CONTRACT_MERGE_OID" \
  --arg window_start "$WINDOW_START" --arg window_end "$WINDOW_END" \
  --arg intervention_oid "$INTERVENTION_MERGE_OID" --arg intervention_at "$INTERVENTION_MERGE_AT" \
  --arg gate_path ".github/workflows/$GATE_PATH" --arg gate_path_legacy ".github/workflows/$GATE_PATH_LEGACY" \
  --arg publisher_path ".github/workflows/$PUBLISHER_PATH" \
  --arg consume_job "$CONSUME_JOB" --arg seed_job "$SEED_JOB" \
  --argjson n_slices "$n_slices" \
  --argjson gate_total "$gate_total" --argjson pub_total "$pub_total" \
  --argjson n_consume "$n_consume" --argjson n_seed "$n_seed" --argjson n_unknown "$n_unknown" \
  --argjson n_prefiltered "$pub_prefiltered" \
  --argjson n_c "$n_c" --argjson n_b "$n_b" --argjson n_reused "$n_reused" \
  --slurpfile consume "$WORK/consume_events.jsonl" \
  --slurpfile seeds "$WORK/seed_events.jsonl" \
  --slurpfile unknown "$WORK/unknown_runs.jsonl" \
  '{
    schema: $schema,
    collected_at: $collected,
    window: {anchor: "contract merge instant (e3_measurement_contract_2026-10-11.md §5.6(b))",
             start: $window_start, end: $window_end, scanned_through: $scan_end,
             contract_merge_oid: $contract_oid,
             intervention_merge_oid: $intervention_oid, intervention_merge_at: $intervention_at},
    targets: {admission_gate: {path: $gate_path, paths: [$gate_path, $gate_path_legacy],
                               event: "merge_group", runs_seen: $gate_total},
              ci_cache_publisher: {path: $publisher_path, event: "workflow_run", runs_seen: $pub_total}},
    selection: {consume_job: $consume_job, seed_job: $seed_job,
                slices: $n_slices, result_cap_per_slice: 1000,
                cap_policy: "adaptive: total_count > 1000 slices are split at the exact UTC midpoint and rescanned recursively; HARD-FAIL (fail-closed, no ledger) if a 300s-floor slice still breaches — silent-truncation mitigation"},
    observation_unit: {unit: "(run_id, run_attempt)",
                       rule: "re-runs keep the run id and increment run_attempt while resetting run_started_at; each attempt is a separate observation and all attempts are recorded"},
    counts: {consumer_observations: $n_consume, seed_observations: $n_seed,
             unknown_key_observations: $n_unknown,
             prefiltered_observations: $n_prefiltered,
             carrier_hit_observations: $n_b, carrier_miss_observations: $n_c,
             reused_skip_observations: $n_reused,
             n_c_candidate: $n_c, n_b_candidate: $n_b},
    notes: [
      "UNKNOWN-key runs are reported, never excluded (log-fetch failure / missing keygen or B-restore markers).",
      "This collector extracts key identifiers only — GO-critical durations are NOT extracted (contract §5.6(c) interim rule).",
      "REUSED-runs (admission_tests.reused_skip=true: every GO-critical subject hit Judgment CAS basis=REUSED, kernel skip) are recorded with their job wall-clock and never dropped; purpose-based classification lands with the forthcoming amendment.",
      "n_c_candidate/n_b_candidate are §5.4 bookkeeping inputs; the confirmatory sets are filled per the contract and 개정 기록 A1 (duration-pre-observed runs excluded, fail-closed).",
      "save-completion timestamps are outcome-line emissions (late bound) — conservative for base-coverage attribution.",
      "prefiltered_observations counts publisher runs whose publish AND skip-report jobs were both skipped: since the 2026-10-25 job-level pre-filter this is exactly a successful completion whose triggering path is not the gate (the path condition sits only on publish.if; every non-success completion still executes skip-report). These runs are outside seed scope by design, not by fetch failure — non-success UNKNOWN-seed semantics are unchanged."],
    consumer_observations: $consume,
    seed_observations: $seeds,
    unknown_key_observations: $unknown
  }' > "$OUT_DIR/ledger.json.tmp"

mv "$OUT_DIR/ledger.json.tmp" "$OUT_DIR/ledger.json"
jq -cn --arg at "$COLLECTED_AT" --arg scan_end "$SCAN_END" \
  --argjson n_consume "$n_consume" --argjson n_seed "$n_seed" --argjson n_unknown "$n_unknown" \
  --argjson n_prefiltered "$pub_prefiltered" \
  --argjson n_c "$n_c" --argjson n_b "$n_b" --argjson n_reused "$n_reused" --argjson slices "$n_slices" \
  '{collected_at: $at, scanned_through: $scan_end, slices: $slices,
    consumer_observations: $n_consume, seed_observations: $n_seed,
    unknown_key_observations: $n_unknown, prefiltered_observations: $n_prefiltered,
    carrier_miss: $n_c, carrier_hit: $n_b,
    reused_skip: $n_reused}' \
  >> "$OUT_DIR/collection_log.jsonl"

echo "[e4e5] collection pass complete: consumer=$n_consume seed=$n_seed unknown=$n_unknown prefiltered=$pub_prefiltered (hit=$n_b miss=$n_c reused_skip=$n_reused) → $OUT_DIR/ledger.json"
[ "$n_consume" -gt 0 ] || [ "$gate_total" -eq 0 ] || echo "[e4e5] NOTE: gate runs seen but zero consumer observations — inspect unknown_key_observations" >&2
exit 0
