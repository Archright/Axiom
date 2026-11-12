#!/usr/bin/env bash
#
# landing_observe.sh — authority-first single-pass PR landing observer (GET-only).
#
# Output is ADVISORY EVIDENCE — this tool is not an authority. Per-fact
# authority (docs/agents/merge_admission_observation.md):
#   * merge-admission outcome = the BOUND admission RUN's conclusion
#     (merge_group context: admission-gate run on the queue merge commit;
#      pr-head context: ruleset-DECLARED required status-check contexts —
#      the aggregate statusCheckRollup is advisory and never decides)
#   * landing truth = GitHub MERGE commit
#     (state==MERGED ∧ mergedAt ∧ mergeCommit.oid ∧ merge-commit parents==2;
#      `merge_commit_sha` standalone is forbidden)
#   * mergeStateStatus = merge-ability verdict ONLY — no reason, no progress.
# Closes the 2026-10-06 blind spot (PR #498, merge_group run 37428943334):
# the failed admission run auto-dequeued the PR while mergeStateStatus stayed
# CLEAN, so a polling loop's terminal conditions never fired (46 minutes of
# identical readings). The queue-phase surface lives on the merge_group RUN,
# never on PR summary fields.
#
# Surface (single pass, one call each — no polling loops, no sleep, no retries):
#   1. GraphQL: PR state / mergedAt / mergeStateStatus / mergeable /
#      mergeCommit{oid} / isInMergeQueue / mergeQueueEntry /
#      statusCheckRollup{state, contexts(first:100) per-check nodes}
#   1b. REST:   /rulesets (complete paginated list) → NAME resolution of
#      the admission ruleset "main" (selection + rules/branches/main
#      cross-validation — identical semantics to the drift monitor's
#      resolveMainRuleset; policy v1.19.0 hybrid authority rotation) →
#      rules[].required_status_checks.parameters.required_status_checks[]
#      .context — the admission authority's own declaration of REQUIRED
#      contexts; resolved once per run (the resolved JSON is the per-run
#      cache); if it cannot be determined, pr-head required-checks are
#      UNKNOWN → fail-closed
#   2. REST:    /actions/runs?event=merge_group filtered by
#      head_branch ~ ^gh-readonly-queue/main/pr-<N>- — latest run per workflow
#      name; the admission-gate row carries the merge_group admission verdict
#   3. REST:    `gh pr view` cross-check + merge-commit parent count (must be 2)
# Purity: read-only — every call is an API read or GraphQL query. No GitHub
# write/mutation/rerun path exists in this file. Repeated observation =
# re-run this script (>=30s apart, per 관측 규칙 2) or the sanctioned waiter
# `gh pr checks --required --watch --interval 30`. Hand-rolled polling loops
# remain forbidden (merge_admission_observation.md).
#
# Verdict — EXACTLY ONE line, then one NEXT: hint (vocabulary maps to the
# Liveness state machine: TERMINAL_SUCCESS→SUCCESS, TERMINAL_FAIL→FAIL/
# OBSERVED_BLOCKER, PROGRESSING→WAIT with identity-changing evidence,
# UNKNOWN→UNKNOWN FAIL CLOSED):
#   TERMINAL_SUCCESS — merged ∧ mergedAt ∧ oid ∧ parents==2, graphql+rest agree
#   TERMINAL_FAIL    — merge_group admission-gate conclusion ∈
#                      {failure,cancelled,timed_out} ∨ mergeStateStatus=DIRTY
#                      ∨ pr-head ruleset-DECLARED required-context FAILURE
#                      (aggregate rollup FAILURE alone never decides: advisory
#                      checks must not block a live merge-queue landing)
#   PROGRESSING      — mergeQueueEntry present ∧ admission run
#                      queued/in_progress/waiting/pending/requested, OR the
#                      admission run completed success while the entry is still
#                      present (the merge itself is the only remaining fact —
#                      reporting UNKNOWN there would deny a known-good state),
#                      OR the entry is QUEUED/AWAITING_CHECKS with 0
#                      merge_group runs yet (documented pre-dispatch phase:
#                      entry → merge group → checks_requested dispatch; the
#                      run's absence is queue scheduling — build concurrency /
#                      group-size wait — not an API failure)
#   UNKNOWN          — everything else (0 applicable runs, null mergeable,
#                      stale/partial data, API failure) — FAIL CLOSED: stop and
#                      report; never extend waiting on UNKNOWN.
# Exit codes: 0=TERMINAL_SUCCESS 1=TERMINAL_FAIL 2=UNKNOWN 3=PROGRESSING
#             (usage/environment errors fail closed to 2=UNKNOWN).
#
# ── L4 canonical-main acceptance (--main <sha>) ────────────────────────────
# A push to main runs this same slice workflow, so canonical-main acceptance is
# an EXISTING artifact, not a new emitter: `axiom-operational-slice-evidence`
# (logs/run-manifest.json + .sha256 + report + exit + proof state). This mode
# only reads it. Its subject is the main merge commit, which is a DIFFERENT
# execution from the PR head run and from the merge_group run — identity is the
# bound run (head_sha + run id + attempt), never SHA equality across events.
#
# REST-only by design: the whole point is to observe without spending GraphQL,
# and the workflow-scoped runs endpoint already yields run_id/run_attempt.
# Download is a 302 redirect (URL expires after 1 minute): the archive transfer
# is a separate request from the API call that resolves it.
#
# Cache: .cache/obs/<run_id>/<run_attempt>/<artifact_id>/  — keyed by the three
# identifiers that make one observation unique (P0-3). A completed run's
# artifact is immutable, so a second read is 0 API calls; `--offline` reads only
# the cache and NEVER claims freshness.
#
# Extra exit codes (one code per state; the L1/L2/L3 codes are unchanged):
#   4=STALE      subject/artifact mismatch, expired artifact, or tampered cache
#   5=NOT_RUN    no push run exists for that commit (NOT_RUN is not success)

set -euo pipefail

OWNER="Archright"
REPO="Axiom"

say() { printf '%s\n' "$*"; }

status_word() {
  if [ "$1" -eq 1 ]; then echo "ok"; else echo "FAILED"; fi
}

verdict_unknown() {
  say "VERDICT: UNKNOWN"
  say "NEXT: stop and report — never extend waiting on UNKNOWN (fail-closed; 재관측 루프로 정지를 연장하지 않는다 — docs/agents/merge_admission_observation.md Liveness UNKNOWN 행: 마지막 raw facts 출력 후 제어권 반환)"
  exit 2
}

# ── modes, call budget, shared exits ───────────────────────────────────────
MODE="pr"
PR_NUMBER=""
MAIN_SHA=""
OFFLINE=0
STATS=0
CACHE_ROOT="${AXIOM_OBS_CACHE:-.cache/obs}"
WORKFLOW_FILE="axiom-operational-slice.yml"
ARTIFACT_NAME="axiom-operational-slice-evidence"
API_CALLS_FILE=""

# Every GitHub request is counted in a FILE, not a shell variable: each call
# runs inside $( … ), and a subshell's variable write never reaches the parent
# — a counter that silently reports 1 instead of 3 is a lie. The transfer that
# follows a 302 is bytes, not an API call.
api_get()     { if [ -n "$API_CALLS_FILE" ]; then printf 'call\n' >> "$API_CALLS_FILE"; fi; gh api "$@"; }
api_pr_view() { if [ -n "$API_CALLS_FILE" ]; then printf 'call\n' >> "$API_CALLS_FILE"; fi; gh pr view "$@"; }
obs_exit()    { say "VERDICT: $1"; exit "$2"; }

usage() {
  cat <<'USAGE'
usage: landing_observe.sh <PR_NUMBER>             L1/L2/L3 — PR / queue / landing truth
       landing_observe.sh --main <sha>            L4 — canonical-main acceptance artifact
       landing_observe.sh --main <sha> --offline  L4 from cache only (never a freshness claim)
options: --stats (observed API call count to stderr on exit), -h|--help
USAGE
}

# ── L4: canonical-main acceptance (read-only over the EXISTING artifact) ────
# <dir> <want_sha>: the artifact must be self-consistent (declared digest) and
# bound to the commit it claims to describe. Absent, tampered, or unbound → 1.
verify_manifest_dir() {
  local dir="$1" want="$2" got_digest decl_digest got_sha
  [ -f "$dir/run-manifest.json" ] || dir="$dir/logs"   # zip root = LCA(logs/*)
  [ -f "$dir/run-manifest.json" ] && [ -f "$dir/run-manifest.sha256" ] || return 1
  got_digest="$(sha256sum "$dir/run-manifest.json" | awk '{print $1}')" || return 1
  decl_digest="$(awk '{print $1}' "$dir/run-manifest.sha256")" || return 1
  [ "$got_digest" = "$decl_digest" ] || return 1
  got_sha="$(jq -r '.sourceTree.gitHead // empty' "$dir/run-manifest.json" 2>/dev/null)" || return 1
  [ "$got_sha" = "$want" ]
}

run_main_offline() {
  local sha="$1" hit="" d
  say "== landing_observe: main acceptance — sha=$sha (L4 --offline: CACHE READ ONLY — not a freshness claim) =="
  if [ -d "$CACHE_ROOT" ]; then
    while IFS= read -r d; do
      [ -f "$d/meta.json" ] || continue
      if [ "$(jq -r '.subject.mainSha // empty' "$d/meta.json" 2>/dev/null)" = "$sha" ]; then
        hit="$d"
      fi
    done < <(find "$CACHE_ROOT" -mindepth 3 -maxdepth 3 -type d | sort)
  fi
  if [ -z "$hit" ]; then
    say "[CACHE]    no cached observation for sha=$sha under $CACHE_ROOT"
    say "NEXT: run without --offline to observe the push run — cache-only evidence cannot be invented."
    obs_exit "UNKNOWN" 2
  fi
  if ! verify_manifest_dir "$hit" "$sha"; then
    say "[CACHE]    $hit — manifest digest/subject binding FAILED (tampered or foreign)"
    obs_exit "STALE" 4
  fi
  say "[CACHE]    hit=$hit runId=$(jq -r '.execution.runId // "?"' "$hit/meta.json") attempt=$(jq -r '.execution.runAttempt // "?"' "$hit/meta.json") artifactId=$(jq -r '.artifact.id // "?"' "$hit/meta.json")"
  say "[MANIFEST] gitHead=$sha digest=verified artifact=$ARTIFACT_NAME"
  say "NEXT: previous observation reused (0 API calls). NOT a freshness claim — re-run without --offline to confirm the current state."
  obs_exit "OBSERVED_SUCCESS" 0
}

run_main_mode() {
  local sha="$1"
  if ! printf '%s' "$sha" | grep -Eq '^[0-9a-f]{7,64}$'; then
    echo "landing_observe: --main <sha> must be a lowercase hex commit sha (got '$sha')" >&2
    verdict_unknown
  fi
  say "== landing_observe: main acceptance — sha=$sha (L4; the artifact is the existing slice evidence, read-only) =="

  local runs_json="" total="" row="" run_id="" run_attempt="" status="" conclusion="" head_sha=""
  runs_json="$(api_get "/repos/$OWNER/$REPO/actions/workflows/$WORKFLOW_FILE/runs?head_sha=$sha&event=push&per_page=20" 2>/dev/null)" || runs_json=""
  if [ -z "$runs_json" ]; then
    say "[RUNS]     workflow=$WORKFLOW_FILE event=push head_sha=$sha — query FAILED (fail-closed)"
    verdict_unknown
  fi
  total="$(jq -r '.total_count // 0' <<<"$runs_json" 2>/dev/null)" || total=0
  [ -n "$total" ] || total=0
  say "[RUNS]     workflow=$WORKFLOW_FILE event=push head_sha=$sha total_count=$total"
  if [ "$total" -eq 0 ]; then
    say "NEXT: no push run exists for that commit — NOT_RUN is not success; wait for the push workflow or confirm the sha is the main merge commit."
    obs_exit "NOT_RUN" 5
  fi
  row="$(jq -r --arg sha "$sha" '[.workflow_runs[]? | select(.head_sha == $sha)] | sort_by(.run_number, .id) | last // empty | [(.id|tostring), (.run_attempt|tostring), .status, (.conclusion // "null"), .head_sha] | @tsv' <<<"$runs_json" 2>/dev/null)" || row=""
  if [ -z "$row" ]; then
    say "[RUNS]     total_count=$total but no run carries head_sha=$sha — partial/stale listing"
    verdict_unknown
  fi
  IFS=$'\t' read -r run_id run_attempt status conclusion head_sha <<<"$row"
  say "[RUN]      run_id=$run_id attempt=$run_attempt status=$status conclusion=$conclusion head_sha=$head_sha"
  if [ "$head_sha" != "$sha" ]; then
    say "[STALE]    bound run head_sha=$head_sha != subject sha=$sha"
    obs_exit "STALE" 4
  fi
  if [ "$status" != "completed" ]; then
    say "NEXT: the push run is still $status — WAIT for it; a running acceptance is not an accepted one."
    obs_exit "PENDING" 3
  fi
  if [ "$conclusion" != "success" ]; then
    say "[BLOCKER]  push run id=$run_id conclusion=$conclusion (authority: the bound run, not a check aggregate)"
    say "NEXT: bounded recovery — gh api /repos/$OWNER/$REPO/actions/runs/$run_id/jobs then job logs; fix, push, re-observe."
    obs_exit "OBSERVED_FAILURE" 1
  fi

  local art_json="" any_id="" expired="" art_id="" cache_dir="" reused=0 manifest=""
  art_json="$(api_get "/repos/$OWNER/$REPO/actions/runs/$run_id/artifacts?name=$ARTIFACT_NAME&per_page=20" 2>/dev/null)" || art_json=""
  if [ -z "$art_json" ]; then
    say "[ARTIFACT] listing FAILED for run $run_id (fail-closed)"
    verdict_unknown
  fi
  any_id="$(jq -r --arg n "$ARTIFACT_NAME" '[.artifacts[]? | select(.name == $n)] | sort_by(.id) | last | .id // empty' <<<"$art_json" 2>/dev/null)" || any_id=""
  if [ -z "$any_id" ]; then
    say "[ARTIFACT] none named $ARTIFACT_NAME on run $run_id — creation unconfirmed (not a failure claim)"
    verdict_unknown
  fi
  expired="$(jq -r --argjson id "$any_id" '.artifacts[]? | select(.id == $id) | .expired' <<<"$art_json" 2>/dev/null)" || expired=""
  if [ "$expired" = "true" ]; then
    say "[STALE]    artifact id=$any_id expired — the acceptance evidence is no longer retrievable"
    obs_exit "STALE" 4
  fi
  art_id="$any_id"
  cache_dir="$CACHE_ROOT/$run_id/$run_attempt/$art_id"
  say "[ARTIFACT] id=$art_id name=$ARTIFACT_NAME expired=$expired cache=$cache_dir"

  if [ -d "$cache_dir" ] && verify_manifest_dir "$cache_dir" "$sha"; then
    reused=1
  else
    rm -rf "$cache_dir"; mkdir -p "$cache_dir"
    if ! api_get "/repos/$OWNER/$REPO/actions/artifacts/$art_id/zip" > "$cache_dir/.artifact.zip" 2>/dev/null \
       || ! unzip -q -o "$cache_dir/.artifact.zip" -d "$cache_dir" >/dev/null 2>&1; then
      rm -rf "$cache_dir"
      say "[ARTIFACT] download/extract FAILED for id=$art_id (fail-closed)"
      verdict_unknown
    fi
    rm -f "$cache_dir/.artifact.zip"
  fi
  if [ "$reused" -eq 1 ]; then
    say "[CACHE]    reused — immutable artifact of run $run_id attempt $run_attempt (0 download calls)"
  else
    say "[CACHE]    populated $cache_dir"
  fi
  if ! verify_manifest_dir "$cache_dir" "$sha"; then
    say "[STALE]    artifact manifest is not bound to sha=$sha (digest or gitHead mismatch)"
    obs_exit "STALE" 4
  fi

  manifest="$cache_dir/run-manifest.json"
  [ -f "$manifest" ] || manifest="$cache_dir/logs/run-manifest.json"
  say "[MANIFEST] gitHead=$(jq -r '.sourceTree.gitHead' "$manifest") binary.sha256=$(jq -r '.binary.sha256' "$manifest") engineBuild=$(jq -r '.toolchain.engineBuild' "$manifest") verdict=$(jq -r '.report.verdict' "$manifest") tier=$(jq -r '.certificate.verificationTier' "$manifest")"
  jq -n --arg repo "$OWNER/$REPO" --arg sha "$sha" --arg rid "$run_id" --argjson att "$run_attempt" \
        --arg wf "$WORKFLOW_FILE" --argjson aid "$art_id" --arg name "$ARTIFACT_NAME" \
        --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    schemaVersion: "axiom.observation.v1",
    repository: $repo,
    subject: { mainSha: $sha },
    execution: { event: "push", runId: ($rid|tonumber), runAttempt: $att, workflowFile: $wf },
    artifact: { id: $aid, name: $name },
    verdict: "OBSERVED_SUCCESS",
    observation: { observedAt: $at, source: "actions.workflow_run + artifact (REST)" }
  }' > "$cache_dir/meta.json"
  say "VERDICT: OBSERVED_SUCCESS"
  say "NEXT: stop — acceptance for $sha is the BOUND push run $run_id (attempt $run_attempt) and its verified artifact; this claims nothing about any other commit."
  exit 0
}

# ── argument & dependency preflight (fail-closed → UNKNOWN) ────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --main)
      if [ $# -lt 2 ]; then echo "landing_observe: --main requires <sha>" >&2; verdict_unknown; fi
      MODE="main"; MAIN_SHA="$2"; shift 2 ;;
    --offline) OFFLINE=1; shift ;;
    --stats)   STATS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*)       echo "landing_observe: unknown option '$1'" >&2; verdict_unknown ;;
    *)         PR_NUMBER="$1"; shift ;;
  esac
done

if [ "$STATS" -eq 1 ]; then
  API_CALLS_FILE="$(mktemp "${TMPDIR:-/tmp}/landing_observe.calls.XXXXXX")"
  trap 'c=0
    if [ -s "$API_CALLS_FILE" ]; then c="$(wc -l < "$API_CALLS_FILE")"; c="${c// /}"; fi
    printf "API_CALLS: %s\n" "$c" >&2
    rm -f "$API_CALLS_FILE"' EXIT
fi

if [ "$MODE" = "pr" ]; then
  if [ -z "$PR_NUMBER" ] || ! printf '%s' "$PR_NUMBER" | grep -Eq '^[0-9]+$'; then
    echo "usage: landing_observe.sh <PR_NUMBER> (positive integer)" >&2
    verdict_unknown
  fi
elif [ -n "$PR_NUMBER" ]; then
  echo "landing_observe: <PR_NUMBER> and --main are mutually exclusive" >&2
  verdict_unknown
fi

NEED_GH=1
if [ "$MODE" = "main" ] && [ "$OFFLINE" -eq 1 ]; then NEED_GH=0; fi
DEPS="jq"
if [ "$NEED_GH" -eq 1 ]; then DEPS="$DEPS gh"; fi
if [ "$MODE" = "main" ]; then DEPS="$DEPS sha256sum"; fi
if [ "$MODE" = "main" ] && [ "$NEED_GH" -eq 1 ]; then DEPS="$DEPS unzip"; fi
for dep in $DEPS; do
  command -v "$dep" >/dev/null 2>&1 || {
    echo "landing_observe: required dependency '$dep' not on PATH (fail-closed)" >&2
    verdict_unknown
  }
done

# ── M7 no-fallback credential guard (docs/spec/diagnostic_execution_delegation.md §4) ──
# AXIOM_DIAG_TOKEN = explicitly provisioned diagnostic credential (in the
# delegated workflow: the in-job minted read-only installation token — never a
# local token). GH_TOKEN outranks the gh keyring natively, so exporting it here
# makes every gh call below use exactly it. AXIOM_DIAG_STRICT=1 refuses the
# gh-auth fallback (operator PAT) — fail closed to UNKNOWN. The credential
# source is ALWAYS printed (never silent).
if [ "$NEED_GH" -eq 0 ]; then
  CRED_SOURCE="none (--offline cache read: no GitHub request is made)"
elif [ -n "${AXIOM_DIAG_TOKEN:-}" ]; then
  export GH_TOKEN="$AXIOM_DIAG_TOKEN"
  CRED_SOURCE="AXIOM_DIAG_TOKEN"
elif [ "${AXIOM_DIAG_STRICT:-}" = "1" ]; then
  echo "landing_observe: FAIL — AXIOM_DIAG_TOKEN absent and AXIOM_DIAG_STRICT=1: gh-auth credentials (operator PAT) are refused for diagnostic execution (M7 no-fallback — docs/spec/diagnostic_execution_delegation.md §4)" >&2
  verdict_unknown
else
  CRED_SOURCE="gh-auth (fallback — AXIOM_DIAG_STRICT not set; not a diagnostic credential)"
fi
say "[CRED]     credential-source=$CRED_SOURCE"

# ── mode dispatch: L4 exits inside these; the PR path falls through below ──
if [ "$MODE" = "main" ]; then
  if [ "$OFFLINE" -eq 1 ]; then run_main_offline "$MAIN_SHA"; else run_main_mode "$MAIN_SHA"; fi
fi

# ── pass 1: GraphQL — PR identity, queue entry, merge-ability verdict ──────
GQL_QUERY="query{repository(owner:\"$OWNER\",name:\"$REPO\"){pullRequest(number:$PR_NUMBER){state mergedAt mergeStateStatus mergeable mergeCommit{oid} isInMergeQueue mergeQueueEntry{state position headCommit{oid}} statusCheckRollup{state contexts(first:100){nodes{__typename ... on CheckRun{name conclusion status} ... on StatusContext{context state}}}}}}}"
GQL_OK=1
GQL_JSON="$(api_get graphql -f query="$GQL_QUERY" 2>/dev/null)" || GQL_OK=0
PR_JSON=""
if [ "$GQL_OK" -eq 1 ]; then
  PR_JSON="$(jq -c '.data.repository.pullRequest // empty' <<<"$GQL_JSON" 2>/dev/null)" || PR_JSON=""
  [ -n "$PR_JSON" ] || GQL_OK=0
fi

G_STATE="unavailable"; G_MERGED_AT="unavailable"; G_MSS="unavailable"
G_MERGEABLE="unavailable"; G_OID="unavailable"; G_INQ="unavailable"
G_QSTATE="unavailable"; G_QPOS="unavailable"; G_QHEAD="unavailable"
G_ROLLUP="unavailable"; G_NODES="null"
if [ "$GQL_OK" -eq 1 ]; then
  G_STATE="$(jq -r '.state // "null"' <<<"$PR_JSON")"
  G_MERGED_AT="$(jq -r '.mergedAt // "null"' <<<"$PR_JSON")"
  G_MSS="$(jq -r '.mergeStateStatus // "null"' <<<"$PR_JSON")"
  G_MERGEABLE="$(jq -r '.mergeable // "null"' <<<"$PR_JSON")"
  G_OID="$(jq -r '.mergeCommit.oid // "null"' <<<"$PR_JSON")"
  G_INQ="$(jq -r '.isInMergeQueue // "null"' <<<"$PR_JSON")"
  G_QSTATE="$(jq -r '.mergeQueueEntry.state // "null"' <<<"$PR_JSON")"
  G_QPOS="$(jq -r 'if .mergeQueueEntry == null then "null" else (.mergeQueueEntry.position | tostring) end' <<<"$PR_JSON")"
  G_QHEAD="$(jq -r '.mergeQueueEntry.headCommit.oid // "null"' <<<"$PR_JSON")"
  G_ROLLUP="$(jq -r '.statusCheckRollup.state // "null"' <<<"$PR_JSON")"
  G_NODES="$(jq -c 'if (.statusCheckRollup.contexts.nodes | type) == "array" then .statusCheckRollup.contexts.nodes else null end' <<<"$PR_JSON" 2>/dev/null)" || G_NODES="null"
fi

# ── pass 1b: REST — ruleset-declared REQUIRED status-check contexts ────────
# Authority-first: "required" is read from the ruleset's own declaration,
# never invented from the aggregate rollup. The ruleset is identified by
# NAME resolution ("main") — policy v1.19.0 hybrid authority rotation: the
# numeric ruleset id is a repository-scoped value reassigned when the
# repository is recreated (the pre-rotation id 20303214 belonged to the OLD
# repository, preserved as <legacy-repo>, and 404s here).
# Resolution semantics are IDENTICAL to tools/merge_ruleset_drift_monitor.nim
# (resolveMainRuleset) and the GPA L2 leg: complete paginated list →
# selection (name∧active∧branch∧repo-source∧conditions→refs/heads/main∧
# required_status_checks==policy expectation) → rules/branches/main
# cross-validation; exactly 1 → resolved; 0 or 2+ → UNDETERMINED; fetch
# failure/incomplete pagination → UNDETERMINED (UNKNOWN ≠ empty — the
# reason is printed explicitly). One resolution per run; the resolved JSON
# is the per-run cache. Undeterminable → pr-head required-checks UNKNOWN
# (fail-closed: no FAIL invention, no SUCCESS claim either).
REQ_OK=1
REQ_JSON=""
REQ_DECL="required set UNDETERMINED (fail-closed)"
REQ_CONTEXTS="null"
RULESET_NAME="main"
REPO_FULL="$OWNER/$REPO"
POLICY_SSOT="config/policy/merge_admission.json"
resolve_ruleset_undetermined() {  # $1 = the explicit reason (never silent)
  REQ_OK=0
  REQ_DECL="ruleset(\"$RULESET_NAME\") 해석 불가: $1 → required set UNDETERMINED (fail-closed)"
}
if [ ! -r "$POLICY_SSOT" ]; then
  resolve_ruleset_undetermined "정책 SSOT($POLICY_SSOT) 읽기 실패"
else
  EXPECTED_CTX="$(jq -r '[.requiredValidations[]?.job, .requiredWorkflowDetection.verdictJob]
                        | map(select(type == "string" and length > 0))
                        | unique | sort | join(",")' "$POLICY_SSOT" 2>/dev/null)" || EXPECTED_CTX=""
  if [ -z "$EXPECTED_CTX" ]; then
    resolve_ruleset_undetermined "정책 기대 문맥 집합 유도 실패"
  elif ! PAGES_JSON="$(api_get --paginate --slurp \
      "/repos/$OWNER/$REPO/rulesets?includes_parents=true&per_page=100" 2>/dev/null)"; then
    resolve_ruleset_undetermined "ruleset 목록(전체 페이지) 조회 실패 — UNKNOWN(페이지 미완결 포함, 빈 결과와 구분)"
  else
    MATCHED_ID=""
    MATCH_COUNT=0
    while IFS= read -r cid; do
      [ -n "$cid" ] || continue
      if ! DETAIL_JSON="$(api_get "/repos/$OWNER/$REPO/rulesets/$cid" 2>/dev/null)"; then
        resolve_ruleset_undetermined "ruleset $cid 상세 조회 실패 — UNKNOWN"
        break
      fi
      COND_OK="$(jq -r '([.conditions.ref_name.include[]?]
                        | (index("~DEFAULT_BRANCH") != null) or (index("refs/heads/main") != null))' \
                    <<<"$DETAIL_JSON" 2>/dev/null || echo false)"
      CHECKS_OK="$(jq -r --arg exp "$EXPECTED_CTX" '
          ([.rules[]? | select(.type == "required_status_checks")
            | .parameters.required_status_checks[]?] as $entries
           | (($entries | map(.context) | unique | sort | join(",")) == $exp)
             and ($entries | all(.integration_id? == 15368)))' \
                    <<<"$DETAIL_JSON" 2>/dev/null || echo false)"
      if [ "$COND_OK" = "true" ] && [ "$CHECKS_OK" = "true" ]; then
        MATCHED_ID="$cid"
        REQ_JSON="$DETAIL_JSON"
        MATCH_COUNT=$((MATCH_COUNT + 1))
      fi
    done < <(jq -r --arg repo "$REPO_FULL" '
        flatten | map(select((.name? == "main") and (.enforcement? == "active")
                             and (.target? == "branch") and (.source? == $repo)))
        | .[].id' <<<"$PAGES_JSON" 2>/dev/null)
    if [ "$REQ_OK" -eq 1 ]; then
      if [ "$MATCH_COUNT" -eq 0 ]; then
        resolve_ruleset_undetermined "선택 조건(name/enforcement/target/source/conditions/checks) 만족 0건"
      elif [ "$MATCH_COUNT" -ge 2 ]; then
        resolve_ruleset_undetermined "선택 조건 만족 ${MATCH_COUNT}건 — admission 표면 모호"
      elif ! BRANCH_JSON="$(api_get "/repos/$OWNER/$REPO/rules/branches/main" 2>/dev/null)"; then
        resolve_ruleset_undetermined "rules/branches/main 교차검증 조회 실패 — UNKNOWN"
      elif ! jq -e --argjson id "$MATCHED_ID" 'map(.ruleset_id? == $id) | any' \
             <<<"$BRANCH_JSON" >/dev/null 2>&1; then
        resolve_ruleset_undetermined "교차검증 실패 — ruleset $MATCHED_ID 가 rules/branches/main 에 적용되지 않음"
      else
        REQ_CONTEXTS="$(jq -c '[.rules[]? | select(.type == "required_status_checks") | .parameters.required_status_checks[]?.context] | unique' <<<"$REQ_JSON" 2>/dev/null)" || REQ_CONTEXTS="null"
        if [ "$REQ_CONTEXTS" != "null" ]; then
          REQ_DECL="ruleset#$MATCHED_ID(\"$RULESET_NAME\" 이름 해석; $(jq -r '"\(.name // "?") enforcement=\(.enforcement // "?")"' <<<"$REQ_JSON" 2>/dev/null))"
        else
          REQ_OK=0
        fi
      fi
    fi
  fi
fi

# pr-head required-context evaluation (pure jq over already-fetched data):
# per declared required context, classify the observed pr-head state.
# MISSING/PENDING are surfaced but never promoted to FAILURE — the verdict
# below is driven by FAILURE rows only.
REQ_EVAL="null"
if [ "$REQ_OK" -eq 1 ] && [ "$G_NODES" != "null" ]; then
  REQ_EVAL="$(jq -cn --argjson req "$REQ_CONTEXTS" --argjson nodes "$G_NODES" '
    [ $req[] as $ctx
      | ([$nodes[] | select((.context? == $ctx) or (.name? == $ctx))][0]) as $h
      | if $h == null then {c: $ctx, s: "MISSING"}
        elif $h.__typename == "CheckRun" then
          {c: $ctx,
           s: (if $h.status != "COMPLETED" then "PENDING"
               elif (["FAILURE","TIMED_OUT","STARTUP_FAILURE","CANCELLED","ACTION_REQUIRED"]
                     | index($h.conclusion)) != null then "FAILURE"
               else "OK" end)}
        else
          {c: $ctx,
           s: (if (["FAILURE","ERROR"] | index($h.state)) != null then "FAILURE"
               elif (["EXPECTED","PENDING"] | index($h.state)) != null then "PENDING"
               else "OK" end)}
        end ]' 2>/dev/null)" || REQ_EVAL="null"
fi
REQ_SUMMARY="undetermined → fail-closed (required set unavailable)"
if [ "$REQ_EVAL" != "null" ]; then
  REQ_SUMMARY="$(jq -r 'if length == 0 then "(none declared — 0 required contexts)" else map("\(.c)=\(.s)") | join(" ") end' <<<"$REQ_EVAL")" || REQ_SUMMARY="undetermined → fail-closed"
fi

# ── pass 2: REST — merge_group admission runs bound to this PR ─────────────
RUNS_OK=1
RUNS_JSON="$(api_get "/repos/$OWNER/$REPO/actions/runs?event=merge_group&per_page=30" 2>/dev/null)" || RUNS_OK=0
PR_RUNS="[]"
if [ "$RUNS_OK" -eq 1 ]; then
  PR_RUNS="$(jq -c --arg pr "$PR_NUMBER" '[.workflow_runs[]? | select(.head_branch != null) | select(.head_branch | test("^gh-readonly-queue/main/pr-" + $pr + "-"))]' <<<"$RUNS_JSON" 2>/dev/null)" || RUNS_OK=0
fi

MG_STATUS="absent"; MG_CONCLUSION="absent"; MG_NAME="-"; MG_ID="-"
RUN_LINES=""
if [ "$RUNS_OK" -eq 1 ]; then
  RUN_LINES="$(jq -r 'if length == 0 then "  (none — 0 merge_group runs for this PR within the last 30 queue-entry runs)" else (group_by(.name) | map(sort_by(.run_number, .id) | last) | sort_by(.name)[] | "  name=\(.name) id=\(.id) status=\(.status) conclusion=\(.conclusion // "-") started=\(.created_at) updated=\(.updated_at) group_head=\(.head_sha[0:12])") end' <<<"$PR_RUNS")" || RUNS_OK=0
fi
if [ "$RUNS_OK" -eq 1 ]; then
  GATE_ROW="$(jq -r 'map(select((.name | ascii_downcase | contains("admission")) or ((.path // "") | ascii_downcase | contains("admission")))) | sort_by(.run_number, .id) | last // empty | [(.status), (.conclusion // "null"), .name, (.id | tostring)] | @tsv' <<<"$PR_RUNS" 2>/dev/null)" || GATE_ROW=""
  if [ -n "${GATE_ROW:-}" ]; then
    while IFS=$'\t' read -r T_STATUS T_CONCLUSION T_NAME T_ID; do
      # copy only on successful reads — the final EOF read clobbers temps
      MG_STATUS="$T_STATUS"; MG_CONCLUSION="$T_CONCLUSION"
      MG_NAME="$T_NAME"; MG_ID="$T_ID"
    done <<<"$GATE_ROW"
  fi
fi

# ── pass 3: REST cross-check + MERGE-commit parent count ───────────────────
REST_OK=1
REST_JSON="$(api_pr_view "$PR_NUMBER" -R "$OWNER/$REPO" --json state,mergedAt,mergeCommit 2>/dev/null)" || REST_OK=0
R_STATE="unavailable"; R_MERGED_AT="unavailable"; R_OID="unavailable"
if [ "$REST_OK" -eq 1 ]; then
  R_STATE="$(jq -r '.state // "null"' <<<"$REST_JSON")"
  R_MERGED_AT="$(jq -r '.mergedAt // "null"' <<<"$REST_JSON")"
  R_OID="$(jq -r '.mergeCommit.oid // "null"' <<<"$REST_JSON")"
fi

PARENTS="n/a"
if [ "$G_OID" != "null" ] && [ "$G_OID" != "unavailable" ]; then
  PARENTS="$(api_get "/repos/$OWNER/$REPO/commits/$G_OID" --jq '.parents | length' 2>/dev/null)" || PARENTS="n/a"
fi
CONSISTENT="n/a"
if [ "$GQL_OK" -eq 1 ] && [ "$REST_OK" -eq 1 ]; then
  if [ "$G_STATE" = "$R_STATE" ] && [ "$G_MERGED_AT" = "$R_MERGED_AT" ] && [ "$G_OID" = "$R_OID" ]; then
    CONSISTENT="consistent"
  else
    CONSISTENT="MISMATCH(stale/partial)"
  fi
fi

# ── fact block (raw observed facts — the audit evidence) ────────────────────
say "== landing_observe: PR #$PR_NUMBER — authority-first single-pass observation (advisory evidence; authority = bound admission run + MERGE commit) =="
say "[QUERY]    graphql=$(status_word "$GQL_OK") merge_group_runs=$(status_word "$RUNS_OK") gh_pr_view=$(status_word "$REST_OK")"
say "[PR]       state=$G_STATE mergedAt=$G_MERGED_AT mergeCommit.oid=$G_OID"
say "[PR]       mergeStateStatus=$G_MSS mergeable=$G_MERGEABLE statusCheckRollup.state=$G_ROLLUP (aggregate — advisory only)"
say "[QUEUE]    isInMergeQueue=$G_INQ mergeQueueEntry.state=$G_QSTATE position=$G_QPOS headCommit.oid=$G_QHEAD"
say "[REQCHK]   pr-head required-checks ($REQ_DECL): $REQ_SUMMARY"
say "[RUNS]     event=merge_group head_branch~^gh-readonly-queue/main/pr-$PR_NUMBER- (latest per workflow; admission-gate = merge_group admission authority)"
if [ -n "$RUN_LINES" ]; then
  printf '%s\n' "$RUN_LINES"
fi
say "[GATE]     admission-gate-row: name=$MG_NAME id=$MG_ID status=$MG_STATUS conclusion=$MG_CONCLUSION"
say "[CROSSCHK] gh pr view: state=$R_STATE mergedAt=$R_MERGED_AT oid=$R_OID | mergeCommit.parents=$PARENTS | graphql↔rest=$CONSISTENT"

# ── verdict 1: TERMINAL_SUCCESS (landing truth, all layers agree) ──────────
if [ "$GQL_OK" -eq 1 ] && [ "$REST_OK" -eq 1 ] \
   && [ "$G_STATE" = "MERGED" ] && [ "$G_MERGED_AT" != "null" ] \
   && [ "$G_OID" != "null" ] && [ "$PARENTS" = "2" ] \
   && [ "$R_STATE" = "MERGED" ] && [ "$CONSISTENT" = "consistent" ]; then
  say "VERDICT: TERMINAL_SUCCESS"
  say "NEXT: stop — landing truth observed (state=MERGED ∧ mergedAt ∧ mergeCommit.oid ∧ parents=2, graphql↔rest consistent). 관측 종료 (L3)."
  exit 0
fi

# ── verdict 2: TERMINAL_FAIL (observed blocker — bounded action, not waiting)
FAIL_EVIDENCE=""
if [ "$RUNS_OK" -eq 1 ]; then
  case "$MG_CONCLUSION" in
    failure|cancelled|timed_out)
      FAIL_EVIDENCE="merge_group admission-gate run id=$MG_ID conclusion=$MG_CONCLUSION (authority: bound admission RUN)" ;;
  esac
fi
if [ -z "$FAIL_EVIDENCE" ] && [ "$GQL_OK" -eq 1 ] && [ "$G_MSS" = "DIRTY" ]; then
  FAIL_EVIDENCE="mergeStateStatus=DIRTY (merge-ability verdict: conflict with base)"
fi
if [ -z "$FAIL_EVIDENCE" ] && [ "$REQ_EVAL" != "null" ] \
   && jq -e 'map(select(.s == "FAILURE")) | length > 0' <<<"$REQ_EVAL" >/dev/null; then
  FAIL_EVIDENCE="pr-head required-check FAILURE: $(jq -r 'map(select(.s == "FAILURE")) | map(.c) | join(", ")' <<<"$REQ_EVAL") (declaration: $REQ_DECL; aggregate rollup=$G_ROLLUP is advisory)"
fi
if [ -n "$FAIL_EVIDENCE" ]; then
  say "[BLOCKER]  $FAIL_EVIDENCE"
  say "VERDICT: TERMINAL_FAIL"
  say "NEXT: bounded recovery — (1) diagnose: gh api /repos/$OWNER/$REPO/actions/runs/<run_id>/jobs then job logs (completed runs only); (2) fix the PR, push a new commit; (3) re-enqueue: gh pr merge $PR_NUMBER --auto. NOTE: gh run rerun re-executes jobs on the dead gh-readonly-queue branch — it does NOT re-enqueue."
  exit 1
fi

# ── verdict 3: PROGRESSING (WAIT — identity-changing progress evidence) ────
if [ "$GQL_OK" -eq 1 ] && [ "$G_INQ" = "true" ] && [ "$G_QSTATE" != "null" ]; then
  case "$MG_STATUS" in
    queued|in_progress|waiting|pending|requested)
      say "VERDICT: PROGRESSING"
      say "NEXT: identity-changing progress evidence present (queue entry state=$G_QSTATE position=$G_QPOS head=$G_QHEAD; admission-gate run id=$MG_ID status=$MG_STATUS). 반복 관측은 승인된 형태만 — 본 스크립트 ≥30s 간격 재실행 또는 gh pr checks --required --watch --interval 30 (hand-rolled polling 금지)."
      exit 3 ;;
  esac
  if [ "$MG_STATUS" = "completed" ] && [ "$MG_CONCLUSION" = "success" ]; then
    say "VERDICT: PROGRESSING"
    say "NEXT: admission-gate run id=$MG_ID completed=success and the queue entry is still present (state=$G_QSTATE position=$G_QPOS head=$G_QHEAD) — the only remaining fact is the MERGE commit (state=MERGED ∧ parents=2). Re-observe at ≥30s; do not read this as landed."
    exit 3
  fi
  # Documented pre-dispatch phase (docs.github.com — Managing a merge queue;
  # GraphQL MergeQueueEntryState): an accepted entry advances
  # entry → merge group → checks_requested dispatch, so a QUEUED/AWAITING_CHECKS
  # entry observed through SUCCESSFUL API reads with 0 merge_group runs is
  # determinate progress — checks are not yet dispatched (build concurrency /
  # group-size wait), not an API failure, and not a dequeue reason. RUNS_OK is
  # required: a failed runs query must stay UNKNOWN (absent ≠ fetch-failed).
  if [ "$RUNS_OK" -eq 1 ] && [ "$MG_STATUS" = "absent" ]; then
    case "$G_QSTATE" in
      QUEUED|AWAITING_CHECKS)
        say "VERDICT: PROGRESSING"
        say "NEXT: queue entry accepted (state=$G_QSTATE position=$G_QPOS head=$G_QHEAD) and 0 merge_group runs exist yet — the documented pre-dispatch phase (entry → merge group → checks_requested; timing governed by queue build concurrency / group-size wait). Remaining facts: merge_group admission-gate run creation, then the MERGE commit (state=MERGED ∧ parents=2). 반복 관측은 승인된 형태만 — 본 스크립트 ≥30s 간격 재실행 또는 gh pr checks --required --watch --interval 30 (hand-rolled polling 금지)."
        exit 3 ;;
    esac
  fi
fi

# ── verdict 4: UNKNOWN (fail-closed — stop, report, never extend waiting) ──
verdict_unknown
