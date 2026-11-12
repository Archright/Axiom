#!/usr/bin/env bash
#
# golive_detect.sh — go-live 경계 탐지기 (org-delegated admission gate의 callee
# blob 전환 관측기). GET-only reporter — merge_latency_audit.sh의 AFTER 데이터셋
# 시작점을 정의하는 계측 보조 도구 (DEBT#473 pin rotation 파트너).
#
# 배경 (PR #760 toolchain-handoff, DEBT#473):
#   도구체인 핸드오프는 Axiom main에 착지했지만 즉시 live가 아니다. org caller
#   Archright/.github의 admission-gate.yml은 Axiom callee(admission-check.yml)를
#   고정 커밋에 핀한다. 핀 회전은 Dependabot rotation + pin-promotion-gate
#   (DEBT#473, content-addressed)만이 수행한다.
#   go-live = NEW callee blob을 실행한 첫 merge_group 런. NEW blob의 등식:
#     blob(.github/workflows/admission-check.yml @ 실행된 핀 ref)
#       == config/trusted_writer_set.json의 trustedAdmissionWorkflowSha (Axiom main)
#
# 실행된 핀의 관측 필드 (신뢰도 순 — 2026-10-12 실측으로 확정):
#   1차 — RUN METADATA (frozen execution record): run 객체의
#     referenced_workflows[].path = "Archright/Axiom/.github/workflows/
#     admission-check.yml@<REF>" (+ .sha = REF). run/job API 메타데이터 중
#     유일하게 실행된 callee ref를 기록하는 필드. 런 1건당 1회 GET으로 끝나고
#     로그 보존 기한·Q3 quirk의 영향을 받지 않는다.
#   2차(폴백) — JOB LOGS (E3 §9 authority table): callee job
#     `attest / admission-check` 로그에 runner가 발행하는 행
#     "Uses: Archright/Axiom/.github/workflows/admission-check.yml@<REF>".
#     1차 필드가 비어있을 때만 /actions/jobs/{id}/logs로 폴백 관측한다.
#   ref는 커밋 sha이고 TWS는 blob sha이므로 contents API(GET)로 ref→blob 해석
#   후 비교한다 — content-addressed (핀이 어느 커밋으로 회전해도 등식 불변).
#
# Quirk compliance (docs/spec/gh_merge_admission_observation_quirks.md):
#   Q2 — merge_group 런은 `gh run view --log` 404; 폴백 로그는
#        /actions/runs/{id}/jobs → /actions/jobs/{job_id}/logs 경유.
#   Q3 — `gh api` 로그 인출은 --allow-escape-sequences 필요 (없으면 빈 출력이
#        로그 부재로 위장한다).
#   SIGPIPE — set -o pipefail 하의 `생성자 | grep -q`는 grep이 매치 시 즉시
#        종료하며 생성자를 SIGPIPE(141)로 죽여 파이프라인이 실패한다(322KB 로그
#       에서 재현). 모든 -q/-m1 조기 종료 grep은 파이프 없이 bash 조건식 또는
#        here-string 단일 명령으로만 사용한다.
#
# Modes:
#   --runs ID1[,ID2,…]            명시 런 집합 분류 (비-admission-gate 런 = fail)
#   --since ISO8601 --until …     창 내 모든 merge_group admission-gate 런 분류
#
# Output (PREFIX 기본: data/merge_latency/golive):
#   PREFIX.runs.jsonl      런당 분류 레코드 (JSON 배열 — baseline runs.jsonl 동형)
#   PREFIX.report.json     요약: go-live 관측 여부 + 경계(첫 new-blob 런 id/시각)
#   PREFIX.post_golive.ids post-golive 런 id 목록(1행 1개) —
#                          merge_latency_audit.sh --compare BASE @PREFIX.post_golive.ids
#                          직결 피드 (@idsfile 규약: 1행 1 id)
#
# Exit codes (fail-closed):
#   0 = 완료, 전 런 분류됨 (go-live 미관측도 정상 완료 — 보고만 한다)
#   1 = 하드 실패 (비-admission-gate 런 id, 구조적 API 실패, result-cap 위반)
#   2 = 사용법/환경 오류 (gh/jq/base64 부재, 인자 오류, TWS 미해석)
#   3 = 완료하나 ≥1 런 미분류 (핀 증거 미관측/해석 불가) — 기록·플래그,
#       침묵 폐기 없음 (A2.2.7 fail-closed 정신)
#
# Purity: read-only. 모든 네트워크 호출은 API GET(gh api). mutation·재실행·취소
# 경로 없음. 폴링 루프 없음 — 런 id당 1회 관측(폴백 시 +2 GET). 이 도구는
# REPORTER다 — 병합 판정을 내지 않고 GitHub의 merge-admission 판정을 대체하지
# 않는다(AGENTS.md §2.3).

set -euo pipefail

OWNER="Archright"
REPO="Axiom"
GATE_PATH="admission-gate.yml"
CLASSIFIER_JOB="attest / admission-check"
CALLEE_PATH=".github/workflows/admission-check.yml"
TWS_PATH="config/trusted_writer_set.json"
USES_RE='Uses: Archright/Axiom/\.github/workflows/admission-check\.yml@[0-9a-f]{40}'
RESULT_CAP=1000                                # 침묵 잘림 방지 (harness 계승)

MODE_RUNS=""; SINCE=""; UNTIL=""
TWS_SHA=""; TWS_REF="main"
OUT_PREFIX="data/merge_latency/golive"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

usage() { sed -n '2,64p' "$0" | grep -E '^#' | sed 's/^# \{0,1\}//'; }

die() { echo "[golive] HARD-FAIL: $1" >&2; exit 1; }
die_env() { echo "[golive] ENV-FAIL: $1" >&2; exit 2; }
die_usage() { echo "[golive] $1" >&2; usage >&2; exit 2; }

for dep in gh jq base64 date; do
  command -v "$dep" >/dev/null 2>&1 || die_usage "필수 명령 없음: $dep"
done

while [ $# -gt 0 ]; do
  case "$1" in
    --runs)    MODE_RUNS="${2:-}"; shift 2 ;;
    --since)   SINCE="${2:-}"; shift 2 ;;
    --until)   UNTIL="${2:-}"; shift 2 ;;
    --tws-sha) TWS_SHA="${2:-}"; shift 2 ;;
    --tws-ref) TWS_REF="${2:-}"; shift 2 ;;
    --out)     OUT_PREFIX="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "알 수 없는 인자: $1" ;;
  esac
done

if [ -z "$MODE_RUNS" ]; then
  [ -n "$SINCE" ] && [ -n "$UNTIL" ] \
    || die_usage "measure에는 --runs IDS 또는 --since X --until Y 필요"
  date -u -d "$SINCE" +%s >/dev/null 2>&1 || die_usage "--since ISO8601 아님: $SINCE"
  date -u -d "$UNTIL" +%s >/dev/null 2>&1 || die_usage "--until ISO8601 아님: $UNTIL"
  [ "$(date -u -d "$SINCE" +%s)" -lt "$(date -u -d "$UNTIL" +%s)" ] \
    || die_usage "--since가 --until 이후임"
elif [ -n "$SINCE" ] || [ -n "$UNTIL" ]; then
  die_usage "--runs와 --since/--until은 동시 사용 불가"
fi
if [ -n "$TWS_SHA" ] && [ "$TWS_REF" != "main" ]; then
  die_usage "--tws-sha와 --tws-ref는 동시 사용 불가"
fi

api_get() { gh api "$@"; }

hex40() { [[ "${1:-}" =~ ^[0-9a-f]{40}$ ]]; }

# ─────────────────────────────────────────── TWS 등식 소스 (신뢰 앵커) ──
resolve_tws() {
  if [ -n "$TWS_SHA" ]; then
    hex40 "$TWS_SHA" || die_usage "--tws-sha가 40-hex 아님: $TWS_SHA"
    TWS_SOURCE='{"kind":"explicit","ref":null}'
    return
  fi
  # 기본: GitHub main (등식의 정본 — 로컬 클론 신선도와 무관하게 "Axiom main의 TWS")
  local content sha
  content="$(api_get "repos/$OWNER/$REPO/contents/$TWS_PATH?ref=$TWS_REF" --jq '.content' 2>/dev/null)" \
    || die_env "TWS 소스 미해석: $TWS_PATH @ $TWS_REF (ref 부재/오타 — 환경 오류)"
  sha="$(printf '%s' "$content" | base64 -d \
    | sed -E 's|^[[:space:]]*//.*$||' \
    | jq -er '.trustedAdmissionWorkflowSha' 2>/dev/null)" \
    || die_env "trustedAdmissionWorkflowSha 미해석/malformed: $TWS_PATH @ $TWS_REF"
  hex40 "$sha" || die_env "trustedAdmissionWorkflowSha '$sha'가 40-hex 아님 (fail-closed)"
  TWS_SHA="$sha"
  TWS_SOURCE="{\"kind\":\"api\",\"ref\":\"$TWS_REF\"}"
}

# ────────────────────────────────────────────── 창 열거 (GET-only) ──
enumerate_window() { # $1=since $2=until → $3=idsfile (1행 1 id, 수 정렬)
  local cur="$1" until_="$2" idsfile="$3" nxt n_slices=0
  : > "$WORK/window_ids.raw"
  while [ "$(date -u -d "$cur" +%s)" -lt "$(date -u -d "$until_" +%s)" ]; do
    nxt="$(date -u -d "$cur +1 day" +%Y-%m-%dT%H:%M:%SZ)"
    [ "$(date -u -d "$nxt" +%s)" -gt "$(date -u -d "$until_" +%s)" ] && nxt="$until_"
    n_slices=$((n_slices+1))
    local slice="$WORK/slice_$n_slices.tsv"
    api_get "repos/$OWNER/$REPO/actions/runs?event=merge_group&created=$cur..$nxt&per_page=100" \
      --paginate --jq '
        if .total_count > '"$RESULT_CAP"' then "CAPBREACH\t" + (.total_count|tostring)
        else (.workflow_runs[]
          | select(.path | endswith("'"$GATE_PATH"'"))
          | "RUN\t" + (.id|tostring))
        end' > "$slice" || die "slice 질의 실패 $cur..$nxt (구조적 API 실패)"
    if grep -q '^CAPBREACH' "$slice"; then
      die "slice $cur..$nxt total_count > $RESULT_CAP — 침묵 잘림 위험; 창을 좁힐 것"
    fi
    grep '^RUN' "$slice" | cut -f2 >> "$WORK/window_ids.raw"
    cur="$nxt"
  done
  sort -n -u "$WORK/window_ids.raw" > "$idsfile"
}

# ────────────────────────────────────────── 런 분류 (관측 + 등식) ──
declare -A BLOB_CACHE

blob_of_ref() { # $1=ref → stdout: blob sha (캐시)
  local ref="${1:-}"
  hex40 "$ref" || return 1
  if [ -z "${BLOB_CACHE[$ref]:-}" ]; then
    BLOB_CACHE[$ref]="$(api_get \
      "repos/$OWNER/$REPO/contents/$CALLEE_PATH?ref=$ref" --jq '.sha' 2>/dev/null)" \
      || { BLOB_CACHE[$ref]=""; return 1; }
    hex40 "${BLOB_CACHE[$ref]}" || { BLOB_CACHE[$ref]=""; return 1; }
  fi
  [ -n "${BLOB_CACHE[$ref]}" ] || return 1
  printf '%s' "${BLOB_CACHE[$ref]}"
}

# 실행된 핀 ref 관측 — 1차 run.referenced_workflows, 2차 job-log Uses 행
observe_pin_ref() { # $1=run_json → stdout: ref (없으면 rc 1)
  local run_json="$1" ref=""
  ref="$(jq -r '.referenced_workflows // [] | .[]
                | select(.path | test("/\\.github/workflows/admission-check\\.yml@[0-9a-f]{40}$"))
                | .path' <<<"$run_json" 2>/dev/null | tail -1)"
  if hex40 "${ref##*@}"; then
    printf '%s' "${ref##*@}"
    return 0
  fi
  return 1
}

observe_pin_ref_from_log() { # $1=run_id → stdout: ref (없으면 rc 1)
  local rid="$1" job_id log
  local job_json
  job_json="$(api_get "repos/$OWNER/$REPO/actions/runs/$rid/jobs" --paginate \
    --jq '.jobs[] | select(.name == "'"$CLASSIFIER_JOB"'") | .id' 2>/dev/null)" \
    || return 1
  job_id="$(printf '%s\n' "$job_json" | head -1)"
  [ -n "$job_id" ] || return 1
  # Q3: --allow-escape-sequences 없으면 빈 출력이 로그 부재로 위장한다.
  # SIGPIPE 주석(헤더) — grep은 here-string 단일 명령으로만.
  log="$(api_get "repos/$OWNER/$REPO/actions/jobs/$job_id/logs" \
          --allow-escape-sequences 2>/dev/null)" || return 1
  local line
  line="$(grep -aoE -m1 "$USES_RE" <<<"$log" 2>/dev/null || true)"
  local ref="${line##*@}"
  hex40 "$ref" || return 1
  printf '%s' "$ref"
}

classify_run() { # $1=run_id → 레코드 1개 기록, 전역 통계 갱신
  local rid="$1"
  local run_json pin_ref="" pin_blob="" verdict reason evidence
  local r_event r_path r_attempt r_head r_concl r_created r_started

  run_json="$(api_get "repos/$OWNER/$REPO/actions/runs/$rid")" \
    || die "런 $rid 조회 실패 (구조적 API 실패 — fail-closed)"
  r_event="$(jq -r '.event' <<<"$run_json")"
  r_path="$(jq -r '.path' <<<"$run_json")"
  r_attempt="$(jq -r '.run_attempt' <<<"$run_json")"
  r_head="$(jq -r '.head_sha' <<<"$run_json")"
  r_concl="$(jq -r '.conclusion // "null"' <<<"$run_json")"
  r_created="$(jq -r '.created_at' <<<"$run_json")"
  r_started="$(jq -r '.run_started_at // .created_at' <<<"$run_json")"
  [[ "$r_path" == *"$GATE_PATH" ]] \
    || die "런 $rid는 $GATE_PATH 런이 아님 (path=$r_path — 비-admission-gate run id)"
  [ "$r_event" = "merge_group" ] \
    || die "런 $rid는 merge_group 런이 아님 (event=$r_event)"

  verdict="unknown"
  if pin_ref="$(observe_pin_ref "$run_json")"; then
    evidence="run.referenced_workflows"
  elif pin_ref="$(observe_pin_ref_from_log "$rid")"; then
    evidence="job-log Uses: line"
  else
    evidence="unobservable"; pin_ref=""
  fi

  if hex40 "$pin_ref"; then
    if pin_blob="$(blob_of_ref "$pin_ref")"; then
      if [ "$pin_blob" = "$TWS_SHA" ]; then
        verdict="post_golive"; reason="blob == TWS (new callee blob)"
      else
        verdict="pre_golive"; reason="blob != TWS (old callee blob)"
      fi
    else
      reason="ref→blob 해석 실패 (contents API)"
    fi
  else
    reason="핀 증거 미관측 (referenced_workflows 부재 + 폴백 로그 부재/만료)"
  fi

  printf '{"schema":"axiom.golive.run/1","tool":"tools/ci/golive_detect.sh","run_id":%s,"run_attempt":%s,"event":"%s","workflow_path":"%s","head_sha":"%s","conclusion":"%s","created_at":"%s","run_started_at":"%s","classification":"%s","callee_pin_ref":%s,"callee_pin_blob_sha":%s,"pin_evidence":"%s"}\n' \
    "$rid" "$r_attempt" "$r_event" "$r_path" "$r_head" "$r_concl" "$r_created" "$r_started" \
    "$verdict" \
    "$( [ -n "$pin_ref" ] && printf '"%s"' "$pin_ref" || printf 'null' )" \
    "$( [ -n "$pin_blob" ] && printf '"%s"' "$pin_blob" || printf 'null' )" \
    "$evidence" \
    > "$WORK/rec_$rid.json"

  N_RUNS=$((N_RUNS+1))
  case "$verdict" in
    post_golive)
      N_POST=$((N_POST+1))
      printf '%s\n' "$rid" >> "$WORK/post_ids.txt"
      printf '%s\t%s\n' "$r_started" "$rid" >> "$WORK/post_by_time.tsv"
      echo "[golive] run $rid: ref=${pin_ref:0:12} blob=${pin_blob:0:12} → POST-go-live ($reason)" >&2 ;;
    pre_golive)
      N_PRE=$((N_PRE+1))
      printf '%s\n' "$rid" >> "$WORK/pre_ids.txt"
      echo "[golive] run $rid: ref=${pin_ref:0:12} blob=${pin_blob:0:12} → pre-go-live ($reason)" >&2 ;;
    *)
      N_UNKNOWN=$((N_UNKNOWN+1))
      printf '%s\n' "$rid" >> "$WORK/unknown_ids.txt"
      echo "[golive] run $rid: UNKNOWN — $reason (기록됨, 침묵 폐기 없음)" >&2 ;;
  esac
}

# ──────────────────────────────────────────────────────── 진입 ──
resolve_tws
echo "[golive] TWS 등식 소스: $TWS_PATH @ $TWS_REF → trustedAdmissionWorkflowSha=${TWS_SHA:0:12}…" >&2
echo "[golive] 분류 등식: blob($CALLEE_PATH @ 실행 핀 ref) == $TWS_SHA" >&2

mkdir -p "$(dirname "$OUT_PREFIX")"

if [ -n "$MODE_RUNS" ]; then
  printf '%s\n' "$MODE_RUNS" | tr ',' '\n' | sed 's/[[:space:]]//g' \
    | grep -vE '^$' | sort -n -u > "$WORK/ids.txt"
  [ -s "$WORK/ids.txt" ] || die_usage "--runs가 유효한 id를 담지 않음"
else
  enumerate_window "$SINCE" "$UNTIL" "$WORK/ids.txt"
fi

N_RUNS=0; N_PRE=0; N_POST=0; N_UNKNOWN=0
: > "$WORK/post_ids.txt"; : > "$WORK/pre_ids.txt"; : > "$WORK/unknown_ids.txt"
: > "$WORK/post_by_time.tsv"

while read -r rid; do
  [ -n "$rid" ] || continue
  [[ "$rid" =~ ^[0-9]+$ ]] || die "런 id 비정형: '$rid'"
  classify_run "$rid"
done < "$WORK/ids.txt"

# ───────────────────────────────────────────────────── 산출물 ──
# runs.jsonl — baseline 동형(JSON 배열, 1런 1레코드)
jq -s '.' "$WORK"/rec_*.json > "$OUT_PREFIX.runs.jsonl" 2>/dev/null \
  || printf '[]\n' > "$OUT_PREFIX.runs.jsonl"

# post_golive.ids — merge_latency_audit.sh --compare @idsfile 직결 (1행 1 id)
cp "$WORK/post_ids.txt" "$OUT_PREFIX.post_golive.ids"

# 경계: 시작 시각 기준 최소(=첫) new-blob 런
BOUNDARY="null"
if [ "$N_POST" -gt 0 ]; then
  read -r B_TS B_ID < <(sort "$WORK/post_by_time.tsv" | head -1)
  BOUNDARY="$(printf '{"first_post_run_id":%s,"first_post_run_started_at":"%s"}' "$B_ID" "$B_TS")"
fi

jq -n \
  --argjson tws_source "$TWS_SOURCE" \
  --arg tws_sha "$TWS_SHA" \
  --arg callee_path "$CALLEE_PATH" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson counts "{\"runs\":$N_RUNS,\"pre_golive\":$N_PRE,\"post_golive\":$N_POST,\"unknown\":$N_UNKNOWN}" \
  --argjson boundary "$BOUNDARY" \
  --slurpfile pre_ids <(jq -s '.' "$WORK/pre_ids.txt" | jq 'map(tostring)') \
  --slurpfile post_ids <(jq -s '.' "$WORK/post_ids.txt" | jq 'map(tostring)') \
  --slurpfile unknown_ids <(jq -s '.' "$WORK/unknown_ids.txt" | jq 'map(tostring)') \
  '{schema:"axiom.golive.summary/1",
    tool:"tools/ci/golive_detect.sh",
    generated_at:$generated_at,
    identity:{callee_path:$callee_path,
              trustedAdmissionWorkflowSha:$tws_sha,
              tws_source:$tws_source,
              rule:"blob(callee_path @ executed pin ref) == trustedAdmissionWorkflowSha → post_golive; != → pre_golive; unobservable → unknown (fail-closed, recorded)"},
    counts:$counts,
    go_live_observed:($counts.post_golive > 0),
    boundary:$boundary,
    pre_golive_run_ids:$pre_ids[0],
    post_golive_run_ids:$post_ids[0],
    unknown_run_ids:$unknown_ids[0],
    compare_feed:{file:"'"$OUT_PREFIX"'.post_golive.ids",
                  usage:"merge_latency_audit.sh --compare <BASE> @'"$OUT_PREFIX"'.post_golive.ids"}}' \
  > "$OUT_PREFIX.report.json"

# ──────────────────────────────────────────────────── 판정 보고 ──
if [ "$N_POST" -gt 0 ]; then
  echo "[golive] GO-LIVE OBSERVED — 첫 new-blob 런: $BOUNDARY" >&2
else
  echo "[golive] go-live not yet observed — 창 내 ${N_RUNS}런 전부 pre-go-live(구 blob) 또는 unknown (정상 완료, 추정 없음)" >&2
fi
echo "[golive] counts: runs=$N_RUNS pre=$N_PRE post=$N_POST unknown=$N_UNKNOWN" >&2
echo "[golive] 산출물: $OUT_PREFIX.runs.jsonl + $OUT_PREFIX.report.json + $OUT_PREFIX.post_golive.ids" >&2

if [ "$N_UNKNOWN" -gt 0 ]; then
  echo "[golive] WARNING: 미분류 런 $N_UNKNOWN건 — $(paste -sd, "$WORK/unknown_ids.txt")" >&2
  exit 3
fi
exit 0
