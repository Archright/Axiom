#!/usr/bin/env bash
# Read-only conformance checker for axiom-admission-verifier verdict attribution.
# Scope: pull_request venue only. check-runs with a merge_group external_id (`v1|...`)
# are excluded and counted; they are never judged as PR-venue verdicts.
set -euo pipefail

DEFAULT_REPO="Archright/Axiom"
WORKFLOW_PATH=".github/workflows/admission-gate-v2.yml"
APP_ID="5795152"

REPO="$DEFAULT_REPO"
MAX_LAG=600
NOW="$(date +%s)"
JSON_OUT=0
ALLOW_EMPTY=0
STDIN_MODE=0
SELF_TEST=0
SHAS=()
WORK=""
REPO_ID_JSON="null"
SELF=""

usage() {
  cat <<'EOF'
Usage:
  verdict_attribution_check.sh --self-test
  verdict_attribution_check.sh [--repo OWNER/REPO] [--sha SHA]... [--max-lag-seconds N] [--now EPOCH] [--json] [--allow-empty]
  verdict_attribution_check.sh --stdin [--sha SHA]... [--max-lag-seconds N] [--now EPOCH] [--json] [--allow-empty]

Exit codes:
  0  every check passed and at least one eligible subject was evaluated
  1  at least one violation
  2  unverifiable (missing tool, API failure, unresolved run, incomplete pagination,
     malformed input, or zero eligible subjects without --allow-empty)

Scope:
  Eligible runs   : path=.github/workflows/admission-gate-v2.yml, event=pull_request,
                    status=completed, head_sha in --sha set
  Eligible checks : app.id=5795152, name=admission-check, external_id venue=pull_request
  Excluded checks : external_id venue=merge_group (counted, never judged here)
EOF
}

die() { printf 'ERROR %s\n' "$*" >&2; exit 2; }

cleanup() {
  if [ -n "$WORK" ]; then
    rm -rf "$WORK"
  fi
}

bool_json() {
  if [ "$1" -eq 1 ]; then printf 'true'; else printf 'false'; fi
}

normalize_sha() {
  local s="$1"
  case "$s" in
    ''|*[!0-9a-fA-F]*) return 1 ;;
  esac
  if [ "${#s}" -ne 40 ] && [ "${#s}" -ne 64 ]; then return 1; fi
  printf '%s' "$s" | tr 'A-F' 'a-f'
}

validate_repo() {
  case "$REPO" in
    */*) ;;
    *) die "invalid --repo (expected OWNER/REPO): $REPO" ;;
  esac
  case "$REPO" in
    *[!A-Za-z0-9._/-]*|/*|*/|*/*/*) die "invalid --repo: $REPO" ;;
  esac
}

parse_args() {
  local sha
  while [ $# -gt 0 ]; do
    case "$1" in
      --self-test) SELF_TEST=1; shift ;;
      --stdin) STDIN_MODE=1; shift ;;
      --json) JSON_OUT=1; shift ;;
      --allow-empty) ALLOW_EMPTY=1; shift ;;
      --repo)
        [ $# -ge 2 ] || die "--repo requires a value"
        REPO="$2"; shift 2 ;;
      --repo=*)
        REPO="${1#*=}"; shift ;;
      --sha)
        [ $# -ge 2 ] || die "--sha requires a value"
        sha="$(normalize_sha "$2")" || die "invalid --sha: $2"
        SHAS+=("$sha"); shift 2 ;;
      --sha=*)
        sha="$(normalize_sha "${1#*=}")" || die "invalid --sha: ${1#*=}"
        SHAS+=("$sha"); shift ;;
      --max-lag-seconds)
        [ $# -ge 2 ] || die "--max-lag-seconds requires a value"
        MAX_LAG="$2"; shift 2 ;;
      --max-lag-seconds=*)
        MAX_LAG="${1#*=}"; shift ;;
      --now)
        [ $# -ge 2 ] || die "--now requires a value"
        NOW="$2"; shift 2 ;;
      --now=*)
        NOW="${1#*=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  case "$MAX_LAG" in
    ''|*[!0-9]*) die "--max-lag-seconds must be a non-negative integer: $MAX_LAG" ;;
  esac
  case "$NOW" in
    ''|*[!0-9]*) die "--now must be a non-negative epoch: $NOW" ;;
  esac
}

read -r -d '' JQ_PROGRAM <<'JQ' || true
def WORKFLOW_PATH: ".github/workflows/admission-gate-v2.yml";
def APP_ID: 5795152;

def to_epoch:
  if . == null then null
  else (try (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch null) end;

def ext_venue:
  (.external_id // "") as $e
  | if ($e | test("^v1p\\|")) then "pull_request"
    elif ($e | test("^v1\\|")) then "merge_group"
    else null end;

def capture_ext:
  (.external_id // "") as $e
  | if $e == "" then null
    else ((try ($e | capture("^v1p\\|(?<repo_id>[0-9]+)\\|(?<head_sha>[0-9a-f]{40})\\|(?<base_sha>[0-9a-f]{40})\\|run=(?<run_id>[0-9]+)#(?<attempt>[0-9]+)$")) catch null) // null)
    end;

def summary_run_id:
  (.output.summary // "") | (([scan("(?:^|\\s)run=([0-9]+)") | .[0]] | .[0]) // null);
def summary_attempt:
  (.output.summary // "") | (([scan("(?:^|\\s)attempt=([0-9]+)") | .[0]] | .[0]) // null);
def summary_evaluated:
  (.output.summary // "") | (([scan("(?:^|\\s)evaluated_commit=([0-9a-fA-F]{7,64})") | .[0]] | .[0]) // null);

def clean_detail: tostring | gsub("[\\r\\n\\t]"; " ");

def violation($code; $cr; $run; $sha; $detail):
  {code: $code,
   check_run: (if $cr == null then null else ($cr.id // null) end),
   run: $run,
   sha: $sha,
   detail: ($detail | clean_detail)};

def info($code; $cr; $run; $sha; $detail):
  {code: $code,
   check_run: (if $cr == null then null else ($cr.id // null) end),
   run: $run,
   sha: $sha,
   detail: ($detail | clean_detail)};

. as $doc
| ($doc.runs // []) as $runs
| ($doc.check_runs // []) as $check_runs
| ($doc.repo_id // null) as $doc_repo_id
| ($runs
   | map(select(.id != null))
   | sort_by(.id, (.run_attempt // 0))
   | group_by(.id)
   | map(.[-1])
   | map(. as $r | select(
       ($r.path == WORKFLOW_PATH)
       and ($r.event == "pull_request")
       and ($r.status == "completed")
       and ((($sha_filter | length) == 0) or (($sha_filter | index($r.head_sha)) != null))
     ))
   | sort_by(.id)
  ) as $eligible
| ($eligible | map(.id)) as $eligible_ids
| ($check_runs
   | map(select(.id != null))
   | sort_by(.id)
   | group_by(.id)
   | map(.[0])
   | map(select((((.app.id // null) | tostring) == (APP_ID | tostring)) and (.name == "admission-check")))
  ) as $scope
| ($scope
   | map(. as $cr
     | ($cr | capture_ext) as $m
     | {cr: $cr,
        venue: ($cr | ext_venue),
        e: (if $m == null then null
            else {repo_id: ($m.repo_id | tonumber),
                  head_sha: $m.head_sha,
                  base_sha: $m.base_sha,
                  run_id: ($m.run_id | tonumber),
                  attempt: ($m.attempt | tonumber)}
            end)})
  ) as $parsed
| ($runs | map(select(.id != null)) | sort_by(.id, (.run_attempt // 0))
   | map({key: ((.id|tostring) + ":" + ((.run_attempt // 1)|tostring)), value: .}) | from_entries) as $by_key
| ($runs | map(select(.id != null)) | sort_by(.id, (.run_attempt // 0))
   | map({key: (.id|tostring), value: .}) | from_entries) as $by_id
| (($unresolved[0] // []) | map({key: (.check_run|tostring), value: .detail}) | from_entries) as $unresolved_map
| ([$parsed[]
    | . as $p
    | $p.cr as $cr
    | if $p.venue == "merge_group" then
        {violations: [], infos: []}
      elif $p.e == null then
        {violations: [violation("V2-MALFORMED"; $cr; null; $cr.head_sha; "external_id missing or malformed: \($cr.external_id // "<absent>")")], infos: []}
      else
        $p.e as $e
        | ("\($e.run_id)#\($e.attempt)") as $runkey
        | ($unresolved_map[($cr.id|tostring)]) as $why
        | if $why != null then
            {violations: [violation("V2-UNRESOLVED"; $cr; $runkey; $cr.head_sha; $why)], infos: []}
          else
            ($by_key["\($e.run_id):\($e.attempt)"] // $by_id[($e.run_id|tostring)]) as $R
            | if $R == null then
                {violations: [violation("V2-UNRESOLVED"; $cr; $runkey; $cr.head_sha; "run \($e.run_id)#\($e.attempt) not present in input")], infos: []}
              else
                [
                  (if $cr.head_sha != $e.head_sha then
                     violation("V1-SUBJECT-MISMATCH"; $cr; $runkey; $cr.head_sha;
                       "check_run.head_sha=\($cr.head_sha // "-") != external_id head_sha=\($e.head_sha)")
                   else empty end),
                  (if ($R.id // null) != $e.run_id then
                     violation("V2-ID-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "run.id=\($R.id // "-") != external_id run=\($e.run_id)")
                   else empty end),
                  (if ($R.run_attempt // null) != $e.attempt then
                     violation("V2-ATTEMPT-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "run.run_attempt=\($R.run_attempt // "-") != external_id attempt=\($e.attempt)")
                   else empty end),
                  (if $doc_repo_id != null and $e.repo_id != $doc_repo_id then
                     violation("V2-REPO-ID-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "external_id repo_id=\($e.repo_id) != repo id=\($doc_repo_id)")
                   else empty end),
                  (if ($R.head_sha // null) != $e.head_sha then
                     violation("V2-HEAD-SHA-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "run.head_sha=\($R.head_sha // "-") != external_id head_sha=\($e.head_sha)")
                   else empty end),
                  (if ($cr.head_sha // null) != ($R.head_sha // null) then
                     violation("V2-CHECK-RUN-SHA-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "check_run.head_sha=\($cr.head_sha // "-") != run.head_sha=\($R.head_sha // "-")")
                   else empty end),
                  (if ($R.path // null) != WORKFLOW_PATH then
                     violation("V2-WORKFLOW-PATH-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "run.path=\($R.path // "-") != \(WORKFLOW_PATH) (workflow_id=\($R.workflow_id // "-"))")
                   else empty end),
                  (if ($R.event // null) != "pull_request" then
                     violation("V2-EVENT-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "run.event=\($R.event // "-") != pull_request")
                   else empty end)
                ] as $base_v
                | ($eligible_ids | index($e.run_id)) as $bound_idx
                | if $bound_idx == null then
                    {violations: $base_v, infos: []}
                  else
                    ($R.updated_at | to_epoch) as $run_completed
                    | (if $run_completed == null then
                         {v: [violation("V4-UNVERIFIABLE"; $cr; $runkey; $R.head_sha; "run.updated_at missing or unparseable")], i: []}
                       elif (($cr.status != "completed") or ($cr.completed_at == null)) then
                         (($now - $run_completed)) as $age
                         | if $age > $max_lag then
                             {v: [violation("V4-PENDING"; $cr; $runkey; $R.head_sha;
                               "check-run not completed; \($age)s since run completion (\($R.updated_at)) > max_lag=\($max_lag)")], i: []}
                           else
                             {v: [], i: [info("V4-INFLIGHT"; $cr; $runkey; $R.head_sha;
                               "check-run not completed; age=\($age)s <= max_lag=\($max_lag)")]}
                           end
                       else
                         ($cr.completed_at | to_epoch) as $done
                         | if $done == null then
                             {v: [violation("V4-UNVERIFIABLE"; $cr; $runkey; $R.head_sha; "check_run.completed_at unparseable: \($cr.completed_at)")], i: []}
                           else
                             ($done - $run_completed) as $d
                             | if $d < 0 then
                                 {v: [violation("V4-PREMATURE"; $cr; $runkey; $R.head_sha;
                                   "check-run completed \((-$d))s before run completion (\($cr.completed_at) < \($R.updated_at))")], i: []}
                               elif $d > $max_lag then
                                 {v: [violation("V4-LATE"; $cr; $runkey; $R.head_sha;
                                   "check-run completed \($d)s after run completion > max_lag=\($max_lag)")], i: []}
                               else {v: [], i: []} end
                           end
                       end) as $v4
                    | (if $cr.conclusion == "stale" then
                         [violation("V4-STALE"; $cr; $runkey; $R.head_sha; "conclusion=stale (GitHub 14-day surrogate for a never-completed check-run)")]
                       else [] end) as $v4stale
                    | ($cr | summary_run_id) as $srun
                    | ($cr | summary_attempt) as $satt
                    | ($cr | summary_evaluated) as $seval
                    | ([
                        (if $srun != null and (($srun | tonumber) != $e.run_id) then
                           violation("V5A-SUMMARY-RUN-MISMATCH"; $cr; $runkey; $R.head_sha;
                             "summary run=\($srun) != external_id run=\($e.run_id)")
                         else empty end),
                        (if $seval != null and $seval != $R.head_sha then
                           violation("V5B-EVALUATED-COMMIT-MISMATCH"; $cr; $runkey; $R.head_sha;
                             "summary evaluated_commit=\($seval) != run head_sha=\($R.head_sha)")
                         elif $seval != null and $srun != null and (($srun | tonumber) != $e.run_id) then
                           (($by_key["\($srun):\($satt // "")"] // null) // $by_id[$srun]) as $SR
                           | if $SR != null and $seval != $SR.head_sha then
                               violation("V5B-EVALUATED-COMMIT-MISMATCH"; $cr; $runkey; $R.head_sha;
                                 "summary evaluated_commit=\($seval) != summary-run head_sha=\($SR.head_sha // "-") (summary run=\($srun))")
                             else empty end
                         else empty end),
                        (if $satt != null and (($satt | tonumber) != $e.attempt) then
                           violation("V5C-SUMMARY-ATTEMPT-MISMATCH"; $cr; $runkey; $R.head_sha;
                             "summary attempt=\($satt) != external_id attempt=\($e.attempt)")
                         else empty end)
                      ]) as $v5
                    | {violations: ($base_v + $v4.v + $v4stale + $v5), infos: $v4.i}
                  end
              end
          end
      end
  ]) as $evaluated
| ([$evaluated[].violations[]]) as $ev_v
| ([$evaluated[].infos[]]) as $ev_i
| ([$eligible[] as $R
    | ([$parsed[] | select(.venue == "pull_request" and .e != null and .e.run_id == $R.id) | .cr.id]) as $bound
    | ("\($R.id)#\($R.run_attempt // "-")") as $runkey
    | if ($bound | length) == 0 then
        violation("V3-MISSING"; null; $runkey; $R.head_sha; "no admission-check check-run names run \($R.id)#\($R.run_attempt // "-")")
      elif ($bound | length) > 1 then
        violation("V3-DUPLICATE"; null; $runkey; $R.head_sha;
          "\($bound|length) admission-check check-runs name run \($R.id)#\($R.run_attempt // "-"): \($bound|map(tostring)|join(","))")
      else empty end
  ]) as $v3
| ($ev_v + $v3) as $violations
| ([$eligible[] | {run: "\(.id)#\(.run_attempt // "-")", workflow_id: (.workflow_id // null), head_sha: (.head_sha // null), event: (.event // null), path: (.path // null)}]) as $run_records
| (([$violations[] | select(.code == "V2-UNRESOLVED" or .code == "V4-UNVERIFIABLE")] | length) > 0) as $unverifiable
| (if $unverifiable then "UNVERIFIABLE"
   elif (($eligible | length) == 0 and ($allow_empty | not)) then "UNVERIFIABLE"
   elif (($violations | length) > 0) then "FAIL"
   else "PASS" end) as $result
| (if $doc_repo_id == null then ["repo_id absent in input; V2 repo-id leg skipped"] else [] end) as $base_notes
| (([$parsed[] | select(.venue == "merge_group")] | length)) as $excluded_mg
| (if $excluded_mg > 0 then
     ["merge_group venue check-runs excluded from PR-venue scope: \($excluded_mg)"]
   else [] end) as $venue_notes
| ($base_notes + $venue_notes) as $notes
| {
    eligible_runs: ($eligible | length),
    check_runs: ([$parsed[] | select(.venue == "pull_request")] | length),
    excluded_check_runs: {merge_group: $excluded_mg},
    violations: ($violations | sort_by(.code, (.check_run // 0), (.run // ""), .detail)),
    informational: ($ev_i | sort_by(.code, (.check_run // 0), (.run // ""), .detail)),
    run_records: ($run_records | sort_by(.run)),
    max_lag_seconds: $max_lag,
    result: $result,
    notes: $notes
  }
JQ

run_eval() {
  jq \
    --argjson max_lag "$MAX_LAG" \
    --argjson now "$NOW" \
    --argjson allow_empty "$(bool_json "$ALLOW_EMPTY")" \
    --argjson sha_filter "$SHA_FILTER_JSON" \
    --argjson repo_id "$REPO_ID_JSON" \
    --slurpfile unresolved "$WORK/unresolved.json" \
    "$JQ_PROGRAM" < "$WORK/doc.json"
}

report() {
  local result_json="$1" result
  if [ "$JSON_OUT" -eq 1 ]; then
    printf '%s' "$result_json" | jq -c '{eligible_runs, check_runs, excluded_check_runs, violations, max_lag_seconds, result}' \
      || die "failed to render JSON result"
    printf '%s' "$result_json" | jq -r '.notes[]? | "NOTE \(.)"' >&2 \
      || die "failed to render notes"
  else
    printf '%s' "$result_json" | jq -r '
      (.run_records[] | "INFO RUN run=\(.run) workflow_id=\(.workflow_id // "-") head=\(if .head_sha == null then "-" else .head_sha[0:8] end) event=\(.event // "-") path=\(.path // "-")"),
      (.informational[] | "INFO \(.code) check_run=\(.check_run // "-") run=\(.run // "-") sha=\(if .sha == null then "-" else .sha[0:8] end) detail=\(.detail)")
    ' || die "failed to render informational output"
    printf '%s' "$result_json" | jq -r '
      .violations[]
      | "VIOLATION \(.code) check_run=\(.check_run // "-") run=\(.run // "-") sha=\(if .sha == null then "-" else .sha[0:8] end) detail=\(.detail)"
    ' || die "failed to render violations"
    printf '%s' "$result_json" | jq -r '
      "SUMMARY eligible_runs=\(.eligible_runs) in_scope_check_runs=\(.check_runs) excluded_merge_group_check_runs=\(.excluded_check_runs.merge_group) violations=\(.violations | length) max_lag_seconds=\(.max_lag_seconds)"
    ' || die "failed to render summary"
    printf '%s' "$result_json" | jq -r '.notes[]? | "NOTE \(.)"' >&2 \
      || die "failed to render notes"
  fi
  result="$(printf '%s' "$result_json" | jq -r '.result')" || die "failed to read result"
  case "$result" in
    PASS) return 0 ;;
    FAIL) return 1 ;;
    *) return 2 ;;
  esac
}

make_workdir() {
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/verdict-attribution-check.XXXXXX")" \
    || die "failed to create temporary directory"
  trap cleanup EXIT
}

sha_filter_json() {
  if [ "${#SHAS[@]}" -eq 0 ]; then
    printf '[]'
  else
    jq -n --args '$ARGS.positional' "${SHAS[@]}"
  fi
}

fetch_check_runs() {
  local sha="$1" idx="$2" raw total n
  raw="$(gh api --paginate --slurp "repos/$REPO/commits/$sha/check-runs?per_page=100&filter=all")" \
    || die "check-runs API failed for $sha"
  printf '%s' "$raw" | jq -e '
    type == "array" and length >= 1
    and all(.[]; type == "object" and (.check_runs | type) == "array" and (.total_count | type) == "number")
  ' >/dev/null 2>&1 || die "unexpected check-runs response shape for $sha"
  total="$(printf '%s' "$raw" | jq -r '.[0].total_count')" || die "check-runs total_count unreadable"
  n="$(printf '%s' "$raw" | jq -r '[.[].check_runs[]] | length')" || die "check-runs flatten failed"
  [ "$n" -eq "$total" ] || die "incomplete check-runs pagination for $sha: collected $n of $total"
  printf '%s' "$raw" | jq -c '[.[].check_runs[]]' > "$WORK/check_runs_$idx.json" \
    || die "check-runs write failed"
}

fetch_workflow_runs() {
  local sha="$1" idx="$2" raw total n
  raw="$(gh api --paginate --slurp "repos/$REPO/actions/runs?head_sha=$sha&per_page=100")" \
    || die "workflow-runs API failed for $sha"
  printf '%s' "$raw" | jq -e '
    type == "array" and length >= 1
    and all(.[]; type == "object" and (.workflow_runs | type) == "array" and (.total_count | type) == "number")
  ' >/dev/null 2>&1 || die "unexpected workflow-runs response shape for $sha"
  total="$(printf '%s' "$raw" | jq -r '.[0].total_count')" || die "workflow-runs total_count unreadable"
  n="$(printf '%s' "$raw" | jq -r '[.[].workflow_runs[]] | length')" || die "workflow-runs flatten failed"
  [ "$n" -eq "$total" ] || die "incomplete workflow-runs pagination for $sha: collected $n of $total"
  printf '%s' "$raw" | jq -c '[.[].workflow_runs[]]' > "$WORK/workflow_runs_$idx.json" \
    || die "workflow-runs write failed"
}

fetch_run_json() {
  local rid="$1" f="$WORK/run_cache/$rid.json"
  if [ -s "$f" ]; then
    printf '%s' "$f"
    return 0
  fi
  if ! gh api "repos/$REPO/actions/runs/$rid" > "$f" 2>"$WORK/run_err_$rid"; then
    rm -f "$f"
    return 1
  fi
  if ! jq -e 'type == "object" and (.id | type) == "number"' "$f" >/dev/null 2>&1; then
    rm -f "$f"
    return 1
  fi
  printf '%s' "$f"
}

fetch_attempt_json() {
  local rid="$1" att="$2" f="$WORK/run_cache/$rid-$att.json"
  if [ -s "$f" ]; then
    printf '%s' "$f"
    return 0
  fi
  if ! gh api "repos/$REPO/actions/runs/$rid/attempts/$att" > "$f" 2>"$WORK/attempt_err_$rid-$att"; then
    rm -f "$f"
    return 1
  fi
  if ! jq -e 'type == "object" and (.id | type) == "number"' "$f" >/dev/null 2>&1; then
    rm -f "$f"
    return 1
  fi
  printf '%s' "$f"
}

live_main() {
  local repo_id i sha cr_id rid att base base_att af sf srun satt base_att_s
  command -v gh >/dev/null 2>&1 || die "gh is required for live mode"
  [ "${#SHAS[@]}" -gt 0 ] || die "at least one --sha is required in live mode (no implicit subject set)"
  validate_repo
  make_workdir
  SHA_FILTER_JSON="$(sha_filter_json)" || die "failed to build SHA filter"

  repo_id="$(gh api "repos/$REPO" --jq '.id')" || die "failed to read repo id for $REPO"
  case "$repo_id" in
    ''|*[!0-9]*) die "repo id is not numeric: $repo_id" ;;
  esac
  REPO_ID_JSON="$repo_id"

  i=0
  for sha in "${SHAS[@]}"; do
    fetch_check_runs "$sha" "$i"
    fetch_workflow_runs "$sha" "$i"
    i=$((i + 1))
  done
  jq -s 'add // []' "$WORK"/check_runs_*.json > "$WORK/check_runs.json" || die "check-runs aggregation failed"
  jq -s 'add // []' "$WORK"/workflow_runs_*.json > "$WORK/workflow_runs.json" || die "workflow-runs aggregation failed"

  mkdir -p "$WORK/run_cache"
  : > "$WORK/fetched_runs.jsonl"
  : > "$WORK/unresolved.jsonl"

  jq -r '
    .[] | select(((.app.id // null) | tostring) == "5795152" and .name == "admission-check")
    | . as $cr
    | (.external_id // "") as $e
    | if ($e | test("^v1p\\|[0-9]+\\|[0-9a-f]{40}\\|[0-9a-f]{40}\\|run=[0-9]+#[0-9]+$")) then
        ($e | capture("run=(?<run>[0-9]+)#(?<att>[0-9]+)$")) as $m
        | "\($cr.id)\t\($m.run)\t\($m.att)"
      else empty end
  ' "$WORK/check_runs.json" > "$WORK/refs.tsv" || die "external_id scan failed"

  while IFS=$'\t' read -r cr_id rid att; do
    [ -n "${cr_id:-}" ] || continue
    if ! base="$(fetch_run_json "$rid")"; then
      printf '{"check_run":%s,"detail":"run %s#%s unresolvable (run API error)"}\n' "$cr_id" "$rid" "$att" \
        >> "$WORK/unresolved.jsonl"
      continue
    fi
    jq -c '.' "$base" >> "$WORK/fetched_runs.jsonl" || die "run cache append failed"
    base_att="$(jq -r '.run_attempt // empty' "$base")" || die "run attempt unreadable"
    if [ "$att" != "$base_att" ]; then
      if ! af="$(fetch_attempt_json "$rid" "$att")"; then
        printf '{"check_run":%s,"detail":"run %s attempt %s unresolvable (attempt API error)"}\n' "$cr_id" "$rid" "$att" \
          >> "$WORK/unresolved.jsonl"
        continue
      fi
      jq -c '.' "$af" >> "$WORK/fetched_runs.jsonl" || die "attempt cache append failed"
    fi
  done < "$WORK/refs.tsv"

  jq -r '
    .[] | select(((.app.id // null) | tostring) == "5795152" and .name == "admission-check")
    | . as $cr
    | (.external_id // "") as $e
    | if ($e | test("^v1p\\|[0-9]+\\|[0-9a-f]{40}\\|[0-9a-f]{40}\\|run=[0-9]+#[0-9]+$")) then
        ($cr.output.summary // "") as $s
        | ($s | (([scan("(?:^|\\s)run=([0-9]+)") | .[0]] | .[0]) // null)) as $srun
        | ($s | (([scan("(?:^|\\s)attempt=([0-9]+)") | .[0]] | .[0]) // null)) as $satt
        | if $srun != null then "\($cr.id)\t\($srun)\t\($satt // "")" else empty end
      else empty end
  ' "$WORK/check_runs.json" > "$WORK/summary_refs.tsv" || die "summary scan failed"

  while IFS=$'\t' read -r cr_id srun satt; do
    [ -n "${cr_id:-}" ] || continue
    if ! sf="$(fetch_run_json "$srun")"; then
      printf 'NOTE summary run %s for check_run %s unresolvable; V5B summary-run leg skipped\n' "$srun" "$cr_id" >&2
      continue
    fi
    jq -c '.' "$sf" >> "$WORK/fetched_runs.jsonl" || die "summary run cache append failed"
    if [ -n "$satt" ]; then
      base_att_s="$(jq -r '.run_attempt // empty' "$sf")" || die "summary run attempt unreadable"
      if [ "$satt" != "$base_att_s" ]; then
        if af="$(fetch_attempt_json "$srun" "$satt")"; then
          jq -c '.' "$af" >> "$WORK/fetched_runs.jsonl" || die "summary attempt cache append failed"
        else
          printf 'NOTE summary run %s attempt %s unresolvable; V5B summary-run leg uses base attempt\n' "$srun" "$satt" >&2
        fi
      fi
    fi
  done < "$WORK/summary_refs.tsv"

  jq -s '.' "$WORK/unresolved.jsonl" > "$WORK/unresolved.json" || die "unresolved aggregation failed"
  jq -s '.' "$WORK/fetched_runs.jsonl" > "$WORK/fetched_runs.json" || die "fetched-run aggregation failed"
  jq -n \
    --argjson repo_id "$REPO_ID_JSON" \
    --slurpfile runs "$WORK/workflow_runs.json" \
    --slurpfile fetched "$WORK/fetched_runs.json" \
    --slurpfile cr "$WORK/check_runs.json" \
    '{repo_id: $repo_id, runs: (($runs[0] // []) + ($fetched[0] // [])), check_runs: ($cr[0] // [])}' \
    > "$WORK/doc.json" || die "input document assembly failed"

  local result_json
  result_json="$(run_eval)" || die "evaluation failed"
  if report "$result_json"; then
    exit 0
  else
    exit $?
  fi
}

stdin_main() {
  command -v jq >/dev/null 2>&1 || die "jq is required"
  [ ! -t 0 ] || die "--stdin requires a JSON document on stdin"
  make_workdir
  SHA_FILTER_JSON="$(sha_filter_json)" || die "failed to build SHA filter"
  cat > "$WORK/doc.json" || die "failed to read --stdin document"
  jq -e '
    type == "object"
    and (.runs | type) == "array"
    and (.check_runs | type) == "array"
    and all(.runs[]; type == "object")
    and all(.check_runs[]; type == "object")
    and ((has("repo_id") | not)
         or ((.repo_id | type) == "number" and .repo_id == (.repo_id | floor)))
  ' "$WORK/doc.json" >/dev/null 2>&1 || die "invalid --stdin document"
  REPO_ID_JSON="$(jq -c 'if has("repo_id") then .repo_id else null end' "$WORK/doc.json")" \
    || die "failed to read repo_id from input"
  printf '[]' > "$WORK/unresolved.json"
  local result_json
  result_json="$(run_eval)" || die "evaluation failed"
  if report "$result_json"; then
    exit 0
  else
    exit $?
  fi
}

st_fail() {
  printf 'SELF-TEST FAIL %s\n' "$*" >&2
  exit 1
}

st_invoke() {
  local fixture="$1"
  shift
  printf '%s' "$fixture" | bash "$SELF" --stdin --json "$@"
}

st_case() {
  local name="$1" fixture="$2" want_rc="$3" assert="$4" out err rc
  shift 4
  err="$WORK/self_test_$name.err"
  if out="$(st_invoke "$fixture" "$@" 2>"$err")"; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne "$want_rc" ]; then
    st_fail "$name: exit=$rc want=$want_rc stdout=[$out] stderr=[$(cat "$err")]"
  fi
  if ! printf '%s' "$out" | jq -e "$assert" >/dev/null 2>&1; then
    st_fail "$name: assertion failed: $assert stdout=[$out] stderr=[$(cat "$err")]"
  fi
}

self_test() {
  command -v jq >/dev/null 2>&1 || { printf 'SELF-TEST FAIL jq not found\n' >&2; exit 2; }
  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  [ -f "$SELF" ] || { printf 'SELF-TEST FAIL script not found: %s\n' "$SELF" >&2; exit 2; }
  make_workdir

  local fixture_incident fixture_clean fixture_empty
  local now_incident now_clean
  local assert_incident assert_clean assert_empty assert_allow

  fixture_incident="$(cat <<'JSON'
{
  "repo_id": 1454952493,
  "runs": [
    {
      "id": 44873857358,
      "run_attempt": 1,
      "event": "pull_request",
      "head_sha": "2f2135b848320dc0e0120752d787dd3a3f3f0b1a",
      "path": ".github/workflows/admission-gate-v2.yml",
      "workflow_id": 111111,
      "status": "completed",
      "conclusion": "failure",
      "created_at": "2026-11-21T06:05:00Z",
      "updated_at": "2026-11-21T06:11:54Z"
    },
    {
      "id": 44874261646,
      "run_attempt": 1,
      "event": "pull_request",
      "head_sha": "434d4ce9e5b44bc211cd22295c656ee120baa28b",
      "path": ".github/workflows/admission-gate-v2.yml",
      "workflow_id": 111111,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:10:00Z",
      "updated_at": "2026-11-21T06:16:18Z"
    }
  ],
  "check_runs": [
    {
      "id": 136754110365,
      "name": "admission-check",
      "head_sha": "2f2135b848320dc0e0120752d787dd3a3f3f0b1a",
      "status": "in_progress",
      "conclusion": null,
      "started_at": "2026-11-21T06:05:08Z",
      "completed_at": null,
      "external_id": "v1p|1454952493|2f2135b848320dc0e0120752d787dd3a3f3f0b1a|6a9ef54a2aaab62b26978185a6aaeb4b2580e6d8|run=44873857358#1",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "PR head=2f2135b848320dc0e0120752d787dd3a3f3f0b1a\nbase=6a9ef54a2aaab62b26978185a6aaeb4b2580e6d8\nvenue=pull_request\n"
      }
    },
    {
      "id": 136755374873,
      "name": "admission-check",
      "head_sha": "434d4ce9e5b44bc211cd22295c656ee120baa28b",
      "status": "completed",
      "conclusion": "failure",
      "started_at": "2026-11-21T06:10:16Z",
      "completed_at": "2026-11-21T06:11:56Z",
      "external_id": "v1p|1454952493|434d4ce9e5b44bc211cd22295c656ee120baa28b|6a9ef54a2aaab62b26978185a6aaeb4b2580e6d8|run=44874261646#1",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "venue=pull_request\nhead=434d4ce9e5b44bc211cd22295c656ee120baa28b\nbase=6a9ef54a2aaab62b26978185a6aaeb4b2580e6d8\nevaluated_commit=434d4ce9e5b44bc211cd22295c656ee120baa28b\nrun=44873857358 attempt=1 conclusion=failure\nreasons=run_head_mismatch\n"
      }
    }
  ]
}
JSON
)"

  fixture_clean="$(cat <<'JSON'
{
  "repo_id": 1454952493,
  "runs": [
    {
      "id": 9001,
      "run_attempt": 1,
      "event": "pull_request",
      "head_sha": "1111111111111111111111111111111111111111",
      "path": ".github/workflows/admission-gate-v2.yml",
      "workflow_id": 222222,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:00:00Z",
      "updated_at": "2026-11-21T06:05:00Z"
    }
  ],
  "check_runs": [
    {
      "id": 7001,
      "name": "admission-check",
      "head_sha": "1111111111111111111111111111111111111111",
      "status": "completed",
      "conclusion": "success",
      "started_at": "2026-11-21T06:00:05Z",
      "completed_at": "2026-11-21T06:05:04Z",
      "external_id": "v1p|1454952493|1111111111111111111111111111111111111111|2222222222222222222222222222222222222222|run=9001#1",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "venue=pull_request\nhead=1111111111111111111111111111111111111111\nbase=2222222222222222222222222222222222222222\nevaluated_commit=1111111111111111111111111111111111111111\nrun=9001 attempt=1 conclusion=success\n"
      }
    }
  ]
}
JSON
)"

  fixture_empty="$(cat <<'JSON'
{"repo_id": 1454952493, "runs": [], "check_runs": []}
JSON
)"

  now_incident="$(jq -n '"2026-11-21T06:20:00Z" | fromdateiso8601')"
  now_clean="$(jq -n '"2026-11-21T06:10:00Z" | fromdateiso8601')"

  assert_incident='
    .result == "FAIL"
    and .eligible_runs == 2
    and .check_runs == 2
    and ([.violations[] | select(.code == "V4-PREMATURE" and .check_run == 136755374873)] | length) == 1
    and ([.violations[] | select(.code == "V5A-SUMMARY-RUN-MISMATCH" and .check_run == 136755374873)] | length) == 1
    and ([.violations[] | select(.code == "V5B-EVALUATED-COMMIT-MISMATCH" and .check_run == 136755374873)] | length) == 1
    and ([.violations[] | select(.code == "V4-PENDING" and .check_run == 136754110365)] | length) == 1
    and ([.violations[] | .code | select(startswith("V3-"))] | length) == 0
    and ([.violations[] | .code | select(startswith("V1-") or startswith("V2-"))] | length) == 0
  '
  assert_clean='
    .result == "PASS"
    and .eligible_runs == 1
    and .check_runs == 1
    and (.violations | length) == 0
  '
  assert_empty='
    .result == "UNVERIFIABLE"
    and .eligible_runs == 0
    and .check_runs == 0
    and (.violations | length) == 0
  '
  assert_allow='
    .result == "PASS"
    and .eligible_runs == 0
    and (.violations | length) == 0
  '

  st_case incident "$fixture_incident" 1 "$assert_incident" \
    --max-lag-seconds 300 --now "$now_incident"
  st_case clean "$fixture_clean" 0 "$assert_clean" \
    --max-lag-seconds 600 --now "$now_clean"
  st_case empty "$fixture_empty" 2 "$assert_empty" \
    --max-lag-seconds 600 --now "$now_clean"
  st_case empty_allow "$fixture_empty" 0 "$assert_allow" \
    --max-lag-seconds 600 --now "$now_clean" --allow-empty

  printf 'SELF-TEST PASS\n'
  exit 0
}

main() {
  parse_args "$@"
  command -v jq >/dev/null 2>&1 || die "jq is required"
  if [ "$SELF_TEST" -eq 1 ]; then
    self_test
  elif [ "$STDIN_MODE" -eq 1 ]; then
    stdin_main
  else
    live_main
  fi
}

main "$@"