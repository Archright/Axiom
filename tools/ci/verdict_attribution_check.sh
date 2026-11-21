#!/usr/bin/env bash
# Read-only conformance checker for axiom-admission-verifier verdict attribution.
# Venues: pull_request (default; external_id prefix `v1p|`, run identity encoded in
# external_id) and merge_group (external_id prefix `v1|`; the external_id does not
# encode a run id, so run identity is resolved from output.summary and cross-checked
# against the Actions Run API).
set -euo pipefail

DEFAULT_REPO="Archright/Axiom"
WORKFLOW_PATH=".github/workflows/admission-gate-v2.yml"
APP_ID="5795152"

REPO="$DEFAULT_REPO"
VENUE="pull_request"
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
  verdict_attribution_check.sh [--venue pull_request|merge_group] [--repo OWNER/REPO] [--sha SHA]... [--max-lag-seconds N] [--now EPOCH] [--json] [--allow-empty]
  verdict_attribution_check.sh --stdin [--venue pull_request|merge_group] [--sha SHA]... [--max-lag-seconds N] [--now EPOCH] [--json] [--allow-empty]

Exit codes:
  0  every check passed and at least one eligible subject was evaluated
  1  at least one violation
  2  unverifiable (missing tool, API failure, unresolved run, incomplete pagination,
     malformed input, or zero eligible subjects without --allow-empty)

Venues:
  pull_request (default)
    Eligible runs   : path=.github/workflows/admission-gate-v2.yml (normalized: strip
                      everything from the first `@` before comparing), event=pull_request,
                      status=completed, head_sha in --sha set
    Eligible checks : app.id=5795152, name=admission-check, external_id prefix `v1p|`
    Excluded checks : external_id prefix `v1|` (merge_group; counted, never judged here)
  merge_group
    Eligible runs   : path=.github/workflows/admission-gate-v2.yml (same normalization),
                      event=merge_group, status=completed, head_sha in --sha set
    Eligible checks : app.id=5795152, name=admission-check, external_id prefix `v1|`
                      (run=<id> and attempt=<n> are resolved from output.summary and
                      cross-checked against the Actions Run API; an unresolvable summary
                      is V2-UNRESOLVED -> exit 2)
    Excluded checks : external_id prefix `v1p|` (pull_request; counted, never judged here)

Coverage (per subject SHA):
  RESOLVED_CLEAN      exit 0 with >= 1 eligible run
  RESOLVED_VIOLATION  exit 1
  UNRESOLVED          exit 2
  `coverage` reports subjects, resolved, unresolved, violations (RESOLVED_VIOLATION
  subjects), coverageRatio = resolved/(resolved+unresolved), and perSubject.
  coverageRatio is null when the denominator is 0. Any UNRESOLVED subject forces
  result=UNVERIFIABLE and exit 2: a declared subject with no resolvable run is never
  PASS. PASS requires subjects>0, unresolved==0, violations==0, and
  resolved==subjects. Coverage and correctness are orthogonal: coverageRatio==1 with
  violations>0 is FAIL.
  One invocation returns ONE exit code. For per-subject attribution either invoke per
  SHA or read coverage.perSubject.
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
      --venue)
        [ $# -ge 2 ] || die "--venue requires a value"
        VENUE="$2"; shift 2 ;;
      --venue=*)
        VENUE="${1#*=}"; shift ;;
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
  case "$VENUE" in
    pull_request|merge_group) ;;
    *) die "invalid --venue (expected pull_request or merge_group): $VENUE" ;;
  esac
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

# workflow_run.path may carry an `@ref` suffix (quirk Q6,
# docs/spec/ci_provider_failover_quirks.md). Strip from the first `@` before
# comparing; the sanctioned shell form is "${RAW_PATH%%@*}".
def norm_path:
  if . == null then null else (sub("@.*$"; "")) end;

def ext_venue:
  (.external_id // "") as $e
  | if ($e | test("^v1p\\|")) then "pull_request"
    elif ($e | test("^v1\\|")) then "merge_group"
    else null end;

def capture_ext:
  (.external_id // "") as $e
  | if $e == "" then null
    else (try (
      if ($e | test("^v1p\\|")) then
        ($e | capture("^v1p\\|(?<repo_id>[0-9]+)\\|(?<head_sha>[0-9a-f]{40})\\|(?<base_sha>[0-9a-f]{40})\\|run=(?<run_id>[0-9]+)#(?<attempt>[0-9]+)$")
         | {repo_id: (.repo_id | tonumber),
            head_sha: .head_sha,
            base_sha: .base_sha,
            run_id: (.run_id | tonumber),
            attempt: (.attempt | tonumber)})
      elif ($e | test("^v1\\|")) then
        ($e | capture("^v1\\|(?<repo_id>[0-9]+)\\|(?<head_sha>[0-9a-f]{40})\\|(?<base_sha>[0-9a-f]{40})\\|(?<baseline>[0-9a-f]{40})$")
         | {repo_id: (.repo_id | tonumber),
            head_sha: .head_sha,
            base_sha: .base_sha,
            baseline: .baseline})
      else null end
    ) catch null)
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
| (if $venue == "pull_request" then "merge_group" else "pull_request" end) as $other_venue
| ($runs
   | map(select(.id != null))
   | sort_by(.id, (.run_attempt // 0))
   | group_by(.id)
   | map(.[-1])
   | map(. as $r | select(
       (($r.path | norm_path) == WORKFLOW_PATH)
       and ($r.event == $venue)
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
     | {cr: $cr,
        venue: ($cr | ext_venue),
        e: ($cr | capture_ext)})
  ) as $parsed
| ($runs | map(select(.id != null)) | sort_by(.id, (.run_attempt // 0))
   | map({key: ((.id|tostring) + ":" + ((.run_attempt // 1)|tostring)), value: .}) | from_entries) as $by_key
| ($runs | map(select(.id != null)) | sort_by(.id, (.run_attempt // 0))
   | map({key: (.id|tostring), value: .}) | from_entries) as $by_id
| (($unresolved[0] // []) | map({key: (.check_run|tostring), value: .detail}) | from_entries) as $unresolved_map
| ([$parsed[]
    | . as $p
    | $p.cr as $cr
    | if $p.venue != null and $p.venue != $venue then
        {violations: [], infos: [], subject: null}
      elif $p.e == null then
        {violations: [violation("V2-MALFORMED"; $cr; null; $cr.head_sha; "external_id missing or malformed: \($cr.external_id // "<absent>")")], infos: [], subject: $cr.head_sha}
      elif $venue == "merge_group" then
        $p.e as $e
        | ($e.head_sha) as $subject_sha
        | ($eligible | map(select(.head_sha == $subject_sha))) as $own_runs
        | ($cr | summary_run_id) as $srun
        | ($cr | summary_attempt) as $satt
        | ($cr | summary_evaluated) as $seval
        | ("\($srun // "-")#\($satt // "-")") as $runkey
        | ($unresolved_map[($cr.id|tostring)]) as $why
        | if $why != null then
            {violations: [violation("V2-UNRESOLVED"; $cr; $runkey; $subject_sha; $why)], infos: [], subject: $cr.head_sha}
          elif $srun == null then
            {violations: [violation("V2-UNRESOLVED"; $cr; null; $subject_sha;
              "summary does not name run=<id>; merge_group run identity unresolvable")], infos: [], subject: $cr.head_sha}
          elif $satt == null then
            {violations: [violation("V2-UNRESOLVED"; $cr; $runkey; $subject_sha;
              "summary does not name attempt=<n> for run=\($srun); merge_group run identity unresolvable")], infos: [], subject: $cr.head_sha}
          else
            ($by_key["\($srun):\($satt)"] // $by_id[$srun]) as $R
            | if $R == null then
                {violations: [violation("V2-UNRESOLVED"; $cr; $runkey; $subject_sha;
                  "summary run \($srun)#\($satt) not present in input")], infos: [], subject: $cr.head_sha}
              else
                ([
                   (if $cr.head_sha != $e.head_sha then
                      violation("V1-SUBJECT-MISMATCH"; $cr; $runkey; $cr.head_sha;
                        "check_run.head_sha=\($cr.head_sha // "-") != external_id head_sha=\($e.head_sha)")
                    else empty end),
                   (if ($R.id // null) != ($srun | tonumber) then
                      violation("V2-ID-MISMATCH"; $cr; $runkey; $R.head_sha;
                        "run.id=\($R.id // "-") != summary run=\($srun)")
                    else empty end),
                   (if ($R.run_attempt // null) != ($satt | tonumber) then
                      violation("V2-ATTEMPT-MISMATCH"; $cr; $runkey; $R.head_sha;
                        "run.run_attempt=\($R.run_attempt // "-") != summary attempt=\($satt)")
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
                   (if ($R.path | norm_path) != WORKFLOW_PATH then
                      violation("V2-WORKFLOW-PATH-MISMATCH"; $cr; $runkey; $R.head_sha;
                        "run.path=\($R.path // "-") (normalized=\(($R.path | norm_path) // "-")) != \(WORKFLOW_PATH) (workflow_id=\($R.workflow_id // "-"))")
                    else empty end),
                   (if ($R.event // null) != "merge_group" then
                      violation("V2-EVENT-MISMATCH"; $cr; $runkey; $R.head_sha;
                        "run.event=\($R.event // "-") != merge_group")
                    else empty end),
                   (($own_runs | map(.workflow_id // null) | map(select(. != null)) | unique) as $own_wfs
                    | ([$eligible[] | .workflow_id // null] | map(select(. != null)) | unique) as $all_wfs
                    | (if (($own_wfs | length) == 1) then $own_wfs[0]
                       elif (($all_wfs | length) == 1) then $all_wfs[0]
                       else null end) as $expected_wf
                    | if $expected_wf != null and (($R.workflow_id // null) != $expected_wf) then
                        violation("V2-WORKFLOW-ID-MISMATCH"; $cr; $runkey; $R.head_sha;
                          "run.workflow_id=\($R.workflow_id // "-") != eligible merge_group workflow_id=\($expected_wf)")
                      else empty end)
                 ]) as $base_v
                | if ($own_runs | length) == 0 then
                    {violations: $base_v, infos: [], subject: $cr.head_sha}
                  elif ($own_runs | length) > 1 then
                    {violations: ($base_v + [violation("V2-UNRESOLVED"; $cr; $runkey; $subject_sha;
                       "\($own_runs|length) eligible merge_group runs share head_sha \($subject_sha); verdict subject unresolvable")]), infos: [], subject: $cr.head_sha}
                  else
                    $own_runs[0] as $own
                    | ($own.updated_at | to_epoch) as $run_completed
                    | (if $run_completed == null then
                         {v: [violation("V4-UNVERIFIABLE"; $cr; $runkey; $own.head_sha; "run.updated_at missing or unparseable")], i: []}
                       elif (($cr.status != "completed") or ($cr.completed_at == null)) then
                         (($now - $run_completed)) as $age
                         | if $age > $max_lag then
                             {v: [violation("V4-PENDING"; $cr; $runkey; $own.head_sha;
                               "check-run not completed; \($age)s since run completion (\($own.updated_at)) > max_lag=\($max_lag)")], i: []}
                           else
                             {v: [], i: [info("V4-INFLIGHT"; $cr; $runkey; $own.head_sha;
                               "check-run not completed; age=\($age)s <= max_lag=\($max_lag)")]}
                           end
                       else
                         ($cr.completed_at | to_epoch) as $done
                         | if $done == null then
                             {v: [violation("V4-UNVERIFIABLE"; $cr; $runkey; $own.head_sha; "check_run.completed_at unparseable: \($cr.completed_at)")], i: []}
                           else
                             ($done - $run_completed) as $d
                             | if $d < 0 then
                                 {v: [violation("V4-PREMATURE"; $cr; $runkey; $own.head_sha;
                                   "check-run completed \((-$d))s before run completion (\($cr.completed_at) < \($own.updated_at))")], i: []}
                               elif $d > $max_lag then
                                 {v: [violation("V4-LATE"; $cr; $runkey; $own.head_sha;
                                   "check-run completed \($d)s after run completion > max_lag=\($max_lag)")], i: []}
                               else {v: [], i: []} end
                           end
                       end) as $v4
                    | (if $cr.conclusion == "stale" then
                         [violation("V4-STALE"; $cr; $runkey; $own.head_sha; "conclusion=stale (GitHub 14-day surrogate for a never-completed check-run)")]
                       else [] end) as $v4stale
                    | ([
                        (if $srun != null and (($srun | tonumber) != $own.id) then
                           violation("V5A-SUMMARY-RUN-MISMATCH"; $cr; $runkey; $own.head_sha;
                             "summary run=\($srun) != subject run=\($own.id)")
                         else empty end),
                        (if $seval != null and $seval != $own.head_sha then
                           violation("V5B-EVALUATED-COMMIT-MISMATCH"; $cr; $runkey; $own.head_sha;
                             "summary evaluated_commit=\($seval) != subject run head_sha=\($own.head_sha // "-")")
                         else empty end),
                        (if $satt != null and $own.run_attempt != null and (($satt | tonumber) != $own.run_attempt) then
                           violation("V5C-SUMMARY-ATTEMPT-MISMATCH"; $cr; $runkey; $own.head_sha;
                             "summary attempt=\($satt) != subject run attempt=\($own.run_attempt // "-")")
                         else empty end)
                      ]) as $v5
                    | {violations: ($base_v + $v4.v + $v4stale + $v5), infos: $v4.i, subject: $cr.head_sha}
                  end
              end
          end
      else
        $p.e as $e
        | ("\($e.run_id)#\($e.attempt)") as $runkey
        | ($unresolved_map[($cr.id|tostring)]) as $why
        | if $why != null then
            {violations: [violation("V2-UNRESOLVED"; $cr; $runkey; $cr.head_sha; $why)], infos: [], subject: $cr.head_sha}
          else
            ($by_key["\($e.run_id):\($e.attempt)"] // $by_id[($e.run_id|tostring)]) as $R
            | if $R == null then
                {violations: [violation("V2-UNRESOLVED"; $cr; $runkey; $cr.head_sha; "run \($e.run_id)#\($e.attempt) not present in input")], infos: [], subject: $cr.head_sha}
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
                  (if ($R.path | norm_path) != WORKFLOW_PATH then
                     violation("V2-WORKFLOW-PATH-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "run.path=\($R.path // "-") (normalized=\(($R.path | norm_path) // "-")) != \(WORKFLOW_PATH) (workflow_id=\($R.workflow_id // "-"))")
                   else empty end),
                  (if ($R.event // null) != "pull_request" then
                     violation("V2-EVENT-MISMATCH"; $cr; $runkey; $R.head_sha;
                       "run.event=\($R.event // "-") != pull_request")
                   else empty end)
                ] as $base_v
                | ($eligible_ids | index($e.run_id)) as $bound_idx
                | if $bound_idx == null then
                    {violations: $base_v, infos: [], subject: $cr.head_sha}
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
                    | {violations: ($base_v + $v4.v + $v4stale + $v5), infos: $v4.i, subject: $cr.head_sha}
                  end
              end
          end
      end
  ]) as $evaluated
| ([$evaluated[] as $ev | $ev.violations[] | . + {subject: ($ev.subject // null)}]) as $ev_v
| ([$evaluated[] as $ev | $ev.infos[] | . + {subject: ($ev.subject // null)}]) as $ev_i
| ([$eligible[] as $R
    | ([$parsed[] | select(.venue == $venue and .e != null and (if $venue == "pull_request" then .e.run_id == $R.id else .cr.head_sha == $R.head_sha end)) | .cr.id]) as $bound
    | ("\($R.id)#\($R.run_attempt // "-")") as $runkey
    | if ($bound | length) == 0 then
        (violation("V3-MISSING"; null; $runkey; $R.head_sha;
          (if $venue == "pull_request" then
             "no admission-check check-run names run \($R.id)#\($R.run_attempt // "-")"
           else
             "no admission-check check-run shares merge_group subject head_sha \($R.head_sha)"
           end)) + {subject: $R.head_sha})
      elif ($bound | length) > 1 then
        (violation("V3-DUPLICATE"; null; $runkey; $R.head_sha;
          (if $venue == "pull_request" then
             "\($bound|length) admission-check check-runs name run \($R.id)#\($R.run_attempt // "-"): \($bound|map(tostring)|join(","))"
           else
             "\($bound|length) admission-check check-runs share merge_group subject head_sha \($R.head_sha): \($bound|map(tostring)|join(","))"
           end)) + {subject: $R.head_sha})
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
| (([$parsed[] | select(.venue == $other_venue)] | length)) as $excluded_other
| (if $excluded_other > 0 then
     [(if $other_venue == "merge_group" then
         "merge_group venue check-runs excluded from PR-venue scope: \($excluded_other)"
       else
         "pull_request venue check-runs excluded from merge_group-venue scope: \($excluded_other)"
       end)]
   else [] end) as $venue_notes
| ($base_notes + $venue_notes) as $notes
| ([$eligible[] | .head_sha] + [$parsed[] | select(.venue == $venue or .venue == null) | .cr.head_sha]
   | map(select(. != null)) | unique) as $observed_subjects
| (if ($sha_filter | length) > 0 then ($sha_filter | unique) else $observed_subjects end) as $subjects
| ([$subjects[] as $s
    | ([$eligible[] | select(.head_sha == $s)] | length) as $n_runs
    | ([$violations[] | select(.subject == $s)]) as $sv
    | ([$sv[] | select(.code == "V2-UNRESOLVED" or .code == "V4-UNVERIFIABLE")] | length) as $n_unres
    | {sha: $s,
       classification: (if $n_runs == 0 then "UNRESOLVED"
                        elif $n_unres > 0 then "UNRESOLVED"
                        elif ($sv | length) > 0 then "RESOLVED_VIOLATION"
                        else "RESOLVED_CLEAN" end),
       eligibleRuns: $n_runs,
       violations: ($sv | map(.code) | sort | unique)}
  ]) as $per_subject
| ([$per_subject[] | select(.classification != "UNRESOLVED")] | length) as $n_resolved
| ([$per_subject[] | select(.classification == "UNRESOLVED")] | length) as $n_unresolved
| ([$per_subject[] | select(.classification == "RESOLVED_VIOLATION")] | length) as $n_violation_subjects
| (if $result == "PASS" and $n_unresolved > 0 then "UNVERIFIABLE" else $result end) as $result
| {
    eligible_runs: ($eligible | length),
    check_runs: ([$parsed[] | select(.venue == $venue)] | length),
    excluded_check_runs: {($other_venue): $excluded_other},
    violations: ($violations | sort_by(.code, (.check_run // 0), (.run // ""), .detail)),
    informational: ($ev_i | sort_by(.code, (.check_run // 0), (.run // ""), .detail)),
    run_records: ($run_records | sort_by(.run)),
    coverage: {
      subjects: ($per_subject | length),
      resolved: $n_resolved,
      unresolved: $n_unresolved,
      violations: $n_violation_subjects,
      coverageRatio: (if ($n_resolved + $n_unresolved) == 0 then null
                      else (((($n_resolved * 10000) / ($n_resolved + $n_unresolved)) | round) / 10000) end),
      perSubject: $per_subject
    },
    max_lag_seconds: $max_lag,
    result: $result,
    notes: $notes
  }
JQ

run_eval() {
  jq \
    --arg venue "$VENUE" \
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
    printf '%s' "$result_json" | jq -c '{eligible_runs, check_runs, excluded_check_runs, violations, coverage, max_lag_seconds, result}' \
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
      .coverage.perSubject[]
      | "SUBJECT sha=\(.sha) classification=\(.classification) eligible_runs=\(.eligibleRuns) violations=\(if (.violations | length) == 0 then "none" else (.violations | join(",")) end)"
    ' || die "failed to render per-subject coverage"
    printf '%s' "$result_json" | jq -r --arg venue "$VENUE" '
      (if $venue == "pull_request" then "merge_group" else "pull_request" end) as $other
      | "SUMMARY eligible_runs=\(.eligible_runs) in_scope_check_runs=\(.check_runs) excluded_\($other)_check_runs=\(.excluded_check_runs[$other]) violations=\(.violations | length) max_lag_seconds=\(.max_lag_seconds) subjects=\(.coverage.subjects) resolved=\(.coverage.resolved) unresolved=\(.coverage.unresolved) violation_subjects=\(.coverage.violations) coverageRatio=\(.coverage.coverageRatio // "null")"
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
  local rid="$1"
  local f="$WORK/run_cache/$rid.json"
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
  local rid="$1" att="$2"
  local f="$WORK/run_cache/$rid-$att.json"
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

  if [ "$VENUE" = "pull_request" ]; then
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
  else
    jq -r '
      .[] | select(((.app.id // null) | tostring) == "5795152" and .name == "admission-check")
      | . as $cr
      | (.external_id // "") as $e
      | if ($e | test("^v1\\|[0-9]+\\|[0-9a-f]{40}\\|[0-9a-f]{40}\\|[0-9a-f]{40}$")) then
          ((.output.summary // "") | (([scan("(?:^|\\s)run=([0-9]+)") | .[0]] | .[0]) // "")) as $srun
          | ((.output.summary // "") | (([scan("(?:^|\\s)attempt=([0-9]+)") | .[0]] | .[0]) // "")) as $satt
          | "\($cr.id)\t\($srun)\t\($satt)"
        else empty end
    ' "$WORK/check_runs.json" > "$WORK/mg_refs.tsv" || die "merge_group summary scan failed"

    while IFS=$'\t' read -r cr_id srun satt; do
      [ -n "${cr_id:-}" ] || continue
      if [ -z "$srun" ]; then
        printf '{"check_run":%s,"detail":"summary does not name run=<id>; merge_group run identity unresolvable"}\n' "$cr_id" \
          >> "$WORK/unresolved.jsonl"
        continue
      fi
      if [ -z "$satt" ]; then
        printf '{"check_run":%s,"detail":"summary does not name attempt=<n> for run %s; merge_group run identity unresolvable"}\n' "$cr_id" "$srun" \
          >> "$WORK/unresolved.jsonl"
        continue
      fi
      if ! base="$(fetch_run_json "$srun")"; then
        printf '{"check_run":%s,"detail":"summary run %s#%s unresolvable (run API error)"}\n' "$cr_id" "$srun" "$satt" \
          >> "$WORK/unresolved.jsonl"
        continue
      fi
      jq -c '.' "$base" >> "$WORK/fetched_runs.jsonl" || die "run cache append failed"
      base_att="$(jq -r '.run_attempt // empty' "$base")" || die "run attempt unreadable"
      if [ "$satt" != "$base_att" ]; then
        if ! af="$(fetch_attempt_json "$srun" "$satt")"; then
          printf '{"check_run":%s,"detail":"summary run %s attempt %s unresolvable (attempt API error)"}\n' "$cr_id" "$srun" "$satt" \
            >> "$WORK/unresolved.jsonl"
          continue
        fi
        jq -c '.' "$af" >> "$WORK/fetched_runs.jsonl" || die "attempt cache append failed"
      fi
    done < "$WORK/mg_refs.tsv"
  fi

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
  local fixture_mg_clean fixture_mg_violation fixture_mg_unresolved
  local fixture_mg_path_at fixture_mg_path_probe fixture_coverage
  local now_incident now_clean
  local assert_incident assert_clean assert_empty assert_allow
  local human_out human_rc
  local assert_mg_clean assert_mg_violation assert_mg_unresolved
  local assert_mg_path_at assert_mg_path_probe
  local assert_coverage assert_coverage_ratio_null
  local venue_out venue_rc

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

  fixture_mg_clean="$(cat <<'JSON'
{
  "repo_id": 1454952493,
  "runs": [
    {
      "id": 9101,
      "run_attempt": 1,
      "event": "merge_group",
      "head_sha": "3333333333333333333333333333333333333333",
      "path": ".github/workflows/admission-gate-v2.yml",
      "workflow_id": 420946486,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:00:00Z",
      "updated_at": "2026-11-21T06:05:00Z"
    }
  ],
  "check_runs": [
    {
      "id": 7101,
      "name": "admission-check",
      "head_sha": "3333333333333333333333333333333333333333",
      "status": "completed",
      "conclusion": "success",
      "started_at": "2026-11-21T06:00:05Z",
      "completed_at": "2026-11-21T06:05:04Z",
      "external_id": "v1|1454952493|3333333333333333333333333333333333333333|4444444444444444444444444444444444444444|5555555555555555555555555555555555555555",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "G=3333333333333333333333333333333333333333\nbase=4444444444444444444444444444444444444444\nrun=9101 attempt=1 conclusion=success\n"
      }
    }
  ]
}
JSON
)"

  fixture_mg_violation="$(cat <<'JSON'
{
  "repo_id": 1454952493,
  "runs": [
    {
      "id": 9201,
      "run_attempt": 1,
      "event": "merge_group",
      "head_sha": "6666666666666666666666666666666666666666",
      "path": ".github/workflows/admission-gate-v2.yml",
      "workflow_id": 420946486,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:00:00Z",
      "updated_at": "2026-11-21T06:05:00Z"
    },
    {
      "id": 9202,
      "run_attempt": 1,
      "event": "merge_group",
      "head_sha": "6666666666666666666666666666666666666666",
      "path": ".github/workflows/admission-gate-v2.yml",
      "workflow_id": 420946486,
      "status": "queued",
      "conclusion": null,
      "created_at": "2026-11-21T06:06:00Z",
      "updated_at": "2026-11-21T06:06:00Z"
    }
  ],
  "check_runs": [
    {
      "id": 7201,
      "name": "admission-check",
      "head_sha": "6666666666666666666666666666666666666666",
      "status": "completed",
      "conclusion": "success",
      "started_at": "2026-11-21T06:00:05Z",
      "completed_at": "2026-11-21T06:04:00Z",
      "external_id": "v1|1454952493|6666666666666666666666666666666666666666|7777777777777777777777777777777777777777|8888888888888888888888888888888888888888",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "G=6666666666666666666666666666666666666666\nbase=7777777777777777777777777777777777777777\nrun=9202 attempt=1 conclusion=success\n"
      }
    }
  ]
}
JSON
)"

  fixture_mg_unresolved="$(cat <<'JSON'
{
  "repo_id": 1454952493,
  "runs": [
    {
      "id": 9301,
      "run_attempt": 1,
      "event": "merge_group",
      "head_sha": "9999999999999999999999999999999999999999",
      "path": ".github/workflows/admission-gate-v2.yml",
      "workflow_id": 420946486,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:00:00Z",
      "updated_at": "2026-11-21T06:05:00Z"
    }
  ],
  "check_runs": [
    {
      "id": 7301,
      "name": "admission-check",
      "head_sha": "9999999999999999999999999999999999999999",
      "status": "completed",
      "conclusion": "success",
      "started_at": "2026-11-21T06:00:05Z",
      "completed_at": "2026-11-21T06:05:04Z",
      "external_id": "v1|1454952493|9999999999999999999999999999999999999999|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "G=9999999999999999999999999999999999999999\nbase=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\nconclusion=success\n"
      }
    }
  ]
}
JSON
)"

  now_incident="$(jq -n '"2026-11-21T06:20:00Z" | fromdateiso8601')"
  now_clean="$(jq -n '"2026-11-21T06:10:00Z" | fromdateiso8601')"

  fixture_mg_path_at="$(cat <<'JSON'
{
  "repo_id": 1454952493,
  "runs": [
    {
      "id": 9401,
      "run_attempt": 1,
      "event": "merge_group",
      "head_sha": "cccccccccccccccccccccccccccccccccccccccc",
      "path": ".github/workflows/admission-gate-v2.yml@main",
      "workflow_id": 420946486,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:00:00Z",
      "updated_at": "2026-11-21T06:05:00Z"
    }
  ],
  "check_runs": [
    {
      "id": 7401,
      "name": "admission-check",
      "head_sha": "cccccccccccccccccccccccccccccccccccccccc",
      "status": "completed",
      "conclusion": "success",
      "started_at": "2026-11-21T06:00:05Z",
      "completed_at": "2026-11-21T06:05:04Z",
      "external_id": "v1|1454952493|cccccccccccccccccccccccccccccccccccccccc|dddddddddddddddddddddddddddddddddddddddd|eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "G=cccccccccccccccccccccccccccccccccccccccc\nbase=dddddddddddddddddddddddddddddddddddddddd\nrun=9401 attempt=1 conclusion=success\n"
      }
    }
  ]
}
JSON
)"

  fixture_mg_path_probe="$(cat <<'JSON'
{
  "repo_id": 1454952493,
  "runs": [
    {
      "id": 9501,
      "run_attempt": 1,
      "event": "merge_group",
      "head_sha": "ffffffffffffffffffffffffffffffffffffffff",
      "path": ".github/workflows/probe-merge-queue.yml@main",
      "workflow_id": 430000000,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:00:00Z",
      "updated_at": "2026-11-21T06:05:00Z"
    }
  ],
  "check_runs": [
    {
      "id": 7501,
      "name": "admission-check",
      "head_sha": "ffffffffffffffffffffffffffffffffffffffff",
      "status": "completed",
      "conclusion": "success",
      "started_at": "2026-11-21T06:00:05Z",
      "completed_at": "2026-11-21T06:05:04Z",
      "external_id": "v1|1454952493|ffffffffffffffffffffffffffffffffffffffff|1111111111111111111111111111111111111111|2222222222222222222222222222222222222222",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "G=ffffffffffffffffffffffffffffffffffffffff\nbase=1111111111111111111111111111111111111111\nrun=9501 attempt=1 conclusion=success\n"
      }
    }
  ]
}
JSON
)"

  fixture_coverage="$(cat <<'JSON'
{
  "repo_id": 1454952493,
  "runs": [
    {
      "id": 9601,
      "run_attempt": 1,
      "event": "merge_group",
      "head_sha": "aaaa000000000000000000000000000000000001",
      "path": ".github/workflows/admission-gate-v2.yml@main",
      "workflow_id": 420946486,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:00:00Z",
      "updated_at": "2026-11-21T06:05:00Z"
    },
    {
      "id": 9602,
      "run_attempt": 1,
      "event": "merge_group",
      "head_sha": "aaaa000000000000000000000000000000000002",
      "path": ".github/workflows/admission-gate-v2.yml",
      "workflow_id": 420946486,
      "status": "completed",
      "conclusion": "success",
      "created_at": "2026-11-21T06:00:00Z",
      "updated_at": "2026-11-21T06:05:00Z"
    }
  ],
  "check_runs": [
    {
      "id": 7601,
      "name": "admission-check",
      "head_sha": "aaaa000000000000000000000000000000000001",
      "status": "completed",
      "conclusion": "success",
      "started_at": "2026-11-21T06:00:05Z",
      "completed_at": "2026-11-21T06:05:04Z",
      "external_id": "v1|1454952493|aaaa000000000000000000000000000000000001|bbbb000000000000000000000000000000000001|cccc000000000000000000000000000000000001",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "G=aaaa000000000000000000000000000000000001\nbase=bbbb000000000000000000000000000000000001\nrun=9601 attempt=1 conclusion=success\n"
      }
    },
    {
      "id": 7602,
      "name": "admission-check",
      "head_sha": "aaaa000000000000000000000000000000000002",
      "status": "completed",
      "conclusion": "success",
      "started_at": "2026-11-21T06:00:05Z",
      "completed_at": "2026-11-21T06:04:00Z",
      "external_id": "v1|1454952493|aaaa000000000000000000000000000000000002|bbbb000000000000000000000000000000000002|cccc000000000000000000000000000000000002",
      "app": {"id": 5795152},
      "output": {
        "title": "admission-check",
        "summary": "G=aaaa000000000000000000000000000000000002\nbase=bbbb000000000000000000000000000000000002\nrun=9602 attempt=1 conclusion=success\n"
      }
    }
  ]
}
JSON
)"

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
    and .coverage.subjects == 2
    and .coverage.resolved == 2
    and .coverage.unresolved == 0
    and .coverage.violations == 2
    and .coverage.coverageRatio == 1
  '
  assert_clean='
    .result == "PASS"
    and .eligible_runs == 1
    and .check_runs == 1
    and (.violations | length) == 0
    and .coverage.subjects == 1
    and .coverage.resolved == 1
    and .coverage.unresolved == 0
    and .coverage.violations == 0
    and .coverage.coverageRatio == 1
    and .coverage.perSubject[0].classification == "RESOLVED_CLEAN"
  '
  assert_empty='
    .result == "UNVERIFIABLE"
    and .eligible_runs == 0
    and .check_runs == 0
    and (.violations | length) == 0
    and .coverage.subjects == 0
    and .coverage.coverageRatio == null
  '
  assert_allow='
    .result == "PASS"
    and .eligible_runs == 0
    and (.violations | length) == 0
    and .coverage.subjects == 0
    and .coverage.resolved == 0
    and .coverage.unresolved == 0
    and .coverage.coverageRatio == null
  '
  assert_mg_clean='
    .result == "PASS"
    and .eligible_runs == 1
    and .check_runs == 1
    and .excluded_check_runs.pull_request == 0
    and (.violations | length) == 0
    and .coverage.perSubject[0].classification == "RESOLVED_CLEAN"
  '
  assert_mg_violation='
    .result == "FAIL"
    and .eligible_runs == 1
    and .check_runs == 1
    and .excluded_check_runs.pull_request == 0
    and ([.violations[] | select(.code == "V5A-SUMMARY-RUN-MISMATCH" and .check_run == 7201)] | length) == 1
    and ([.violations[] | select(.code == "V4-PREMATURE" and .check_run == 7201)] | length) == 1
    and ([.violations[] | .code | select(startswith("V1-") or startswith("V2-") or startswith("V3-"))] | length) == 0
    and .coverage.subjects == 1
    and .coverage.resolved == 1
    and .coverage.violations == 1
    and .coverage.perSubject[0].classification == "RESOLVED_VIOLATION"
  '
  assert_mg_unresolved='
    .result == "UNVERIFIABLE"
    and .eligible_runs == 1
    and .check_runs == 1
    and ([.violations[] | select(.code == "V2-UNRESOLVED" and .check_run == 7301)] | length) == 1
    and .coverage.subjects == 1
    and .coverage.resolved == 0
    and .coverage.unresolved == 1
    and .coverage.coverageRatio == 0
  '
  assert_mg_path_at='
    .result == "PASS"
    and .eligible_runs == 1
    and .check_runs == 1
    and ([.violations[] | .code | select(startswith("V2-") or startswith("V3-"))] | length) == 0
    and .coverage.perSubject[0].classification == "RESOLVED_CLEAN"
  '
  assert_mg_path_probe='
    .result == "UNVERIFIABLE"
    and .eligible_runs == 0
    and ([.violations[] | select(.code == "V3-MISSING" or .code == "V3-DUPLICATE")] | length) == 0
    and .check_runs == 1
    and ([.violations[] | select(.code == "V2-WORKFLOW-PATH-MISMATCH" and .check_run == 7501)] | length) == 1
    and .coverage.subjects == 1
    and .coverage.resolved == 0
    and .coverage.unresolved == 1
    and .coverage.coverageRatio == 0
    and .coverage.perSubject[0].classification == "UNRESOLVED"
  '
  assert_coverage_unobserved='
    .result == "FAIL"
    and .coverage.subjects == 3
    and .coverage.resolved == 2
    and .coverage.unresolved == 1
    and .coverage.violations == 1
    and .coverage.coverageRatio == 0.6667
    and ([.coverage.perSubject[] | select(.sha == "dddd000000000000000000000000000000000003" and .classification == "UNRESOLVED" and .eligibleRuns == 0)] | length) == 1
  '
  assert_coverage='
    .result == "FAIL"
    and .coverage.subjects == 2
    and .coverage.resolved == 2
    and .coverage.unresolved == 0
    and .coverage.violations == 1
    and .coverage.coverageRatio == 1
    and ([.coverage.perSubject[] | select(.sha == "aaaa000000000000000000000000000000000001" and .classification == "RESOLVED_CLEAN" and .eligibleRuns == 1 and (.violations | length) == 0)] | length) == 1
    and ([.coverage.perSubject[] | select(.sha == "aaaa000000000000000000000000000000000002" and .classification == "RESOLVED_VIOLATION" and .eligibleRuns == 1 and (.violations | index("V4-PREMATURE")) != null)] | length) == 1
  '
  assert_coverage_ratio_null='
    .coverage.subjects == 0
    and .coverage.resolved == 0
    and .coverage.unresolved == 0
    and .coverage.coverageRatio == null
  '
  assert_eight_unresolved='
    .result == "UNVERIFIABLE"
    and .coverage.subjects == 9
    and .coverage.resolved == 1
    and .coverage.unresolved == 8
    and .coverage.violations == 0
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
  st_case mg_path_at "$fixture_mg_path_at" 0 "$assert_mg_path_at" \
    --venue merge_group --max-lag-seconds 600 --now "$now_clean"
  st_case mg_path_probe "$fixture_mg_path_probe" 2 "$assert_mg_path_probe" \
    --venue merge_group --max-lag-seconds 600 --now "$now_clean"
  st_case coverage "$fixture_coverage" 1 "$assert_coverage" \
    --venue merge_group --max-lag-seconds 600 --now "$now_clean"
  st_case coverage_ratio_null "$fixture_empty" 0 "$assert_coverage_ratio_null" \
    --max-lag-seconds 600 --now "$now_clean" --allow-empty
  st_case coverage_unobserved "$fixture_coverage" 1 "$assert_coverage_unobserved" \
    --venue merge_group --max-lag-seconds 600 --now "$now_clean" \
    --sha aaaa000000000000000000000000000000000001 \
    --sha aaaa000000000000000000000000000000000002 \
    --sha dddd000000000000000000000000000000000003
  st_case mg_clean "$fixture_mg_clean" 0 "$assert_mg_clean" \
    --venue merge_group --max-lag-seconds 600 --now "$now_clean"
  st_case mg_violation "$fixture_mg_violation" 1 "$assert_mg_violation" \
    --venue merge_group --max-lag-seconds 600 --now "$now_clean"
  st_case mg_unresolved "$fixture_mg_unresolved" 2 "$assert_mg_unresolved" \
    --venue merge_group --max-lag-seconds 600 --now "$now_clean"
  st_case eight_unresolved "$fixture_mg_clean" 2 "$assert_eight_unresolved" \
    --venue merge_group --max-lag-seconds 600 --now "$now_clean" \
    --sha 3333333333333333333333333333333333333333 \
    --sha aaaa0000000000000000000000000000000000a1 \
    --sha aaaa0000000000000000000000000000000000a2 \
    --sha aaaa0000000000000000000000000000000000a3 \
    --sha aaaa0000000000000000000000000000000000a4 \
    --sha aaaa0000000000000000000000000000000000a5 \
    --sha aaaa0000000000000000000000000000000000a6 \
    --sha aaaa0000000000000000000000000000000000a7 \
    --sha aaaa0000000000000000000000000000000000a8

  if human_out="$(printf '%s' "$fixture_coverage" | bash "$SELF" --stdin --venue merge_group \
      --max-lag-seconds 600 --now "$now_clean" 2>"$WORK/self_test_human.err")"; then
    human_rc=0
  else
    human_rc=$?
  fi
  [ "$human_rc" -eq 1 ] || st_fail "human_coverage: exit=$human_rc want=1 stdout=[$human_out]"
  case "$human_out" in
    *"subjects=2 resolved=2 unresolved=0 violation_subjects=1 coverageRatio=1"*) ;;
    *) st_fail "human_coverage: aggregate fields missing: [$human_out]" ;;
  esac
  case "$human_out" in
    *"SUBJECT sha=aaaa000000000000000000000000000000000002 classification=RESOLVED_VIOLATION"*) ;;
    *) st_fail "human_coverage: per-subject line missing: [$human_out]" ;;
  esac

  if venue_out="$(printf '{}' | bash "$SELF" --venue bogus --stdin 2>"$WORK/self_test_venue.err")"; then
    venue_rc=0
  else
    venue_rc=$?
  fi
  [ "$venue_rc" -eq 2 ] || st_fail "unknown_venue: exit=$venue_rc want=2 stdout=[$venue_out]"
  case "$(cat "$WORK/self_test_venue.err")" in
    *"invalid --venue"*) ;;
    *) st_fail "unknown_venue: missing rejection detail: [$(cat "$WORK/self_test_venue.err")]" ;;
  esac

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