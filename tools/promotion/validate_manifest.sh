#!/usr/bin/env bash
# tools/promotion/validate_manifest.sh — 승격(promotion) manifest의 **관계** 검증.
#
# 승격이 "완료되었다"는 주장은 **필드 존재**가 아니라 **관계**로 증명되어야 한다.
# 이 스크립트는 schema 검사(필수 필드 존재·형식)와 관계 검증을 **분리된
# 함수**로 수행하고, 다음 5개 관계를 gh(실측) + jq로 판정한다:
#
#   (1) acceptanceRun — Archright/Axiom의 generation-acceptance 워크플로 run이며,
#       event == merge_group, conclusion == success, 그리고 run의 head_sha가
#       기록되어 있고 API 실측값과 일치한다. merge_group의 head는 큐가 만든
#       임시 merge 커밋이므로 **PR head와 다르다** — 이 가정으로 검증하지 않는다.
#   (2) candidateSha — 해당 후보 PR의 head SHA와 같다(PR API 실측).
#   (3) rulesetReadback — 승격 후 실취득이며 provenance이
#       'operator-promotion-adapter'이고, fetchedAt·expected·actual·equal가
#       기록되어 있으며 expected == actual이다.
#   (4) productionRun — 승격 워크플로의 main 실행이며 run의 head_sha가
#       mergeSha와 일치한다(main 착지 직후 실행).
#   (5) mergeSha — 후보 PR의 실제 mergeCommit oid와 같다(PR API 실측).
#
# UNKNOWN 값은 통과로 읽지 않는다 — 승격 완료 선언의 불가 조건이다.
# 결정론적: 같은 입력 → 같은 출력(시간·무작위 정렬 없음). 배열 비교는
# 정렬 후 원소 단위로 한다.
#
# 사용법:
#   tools/promotion/validate_manifest.sh <manifest.json>
#
# 종료 코드:
#   0 = 모든 검사 통과(5개 관계 전부 성립)
#   1 = 검증 실패(어느 관계가 왜 어긋났는지 명시)
#   2 = 사용법/환경 오류(인자 없음, gh/jq 없음, 파일 읽기 실패)

set -uo pipefail

readonly EXIT_OK=0
readonly EXIT_FAIL=1
readonly EXIT_USAGE=2

readonly REPO="${GPA_REPO:-Archright/Axiom}"
readonly WORKFLOW_NAME="${GPA_WORKFLOW:-generation-acceptance}"
readonly WORKFLOW_PATH=".github/workflows/${WORKFLOW_NAME}.yml"
readonly UNKNOWN_MARKER="UNKNOWN"

usage() {
  cat <<'USAGE'
usage: tools/promotion/validate_manifest.sh <manifest.json>

승격 manifest의 스키마와 관계(run↔SHA↔readback↔merge 연결)를 검증한다.
관계 5항은 ADR-0036 §5에 정의되어 있다.
환경변수: GPA_REPO(기본 Archright/Axiom), GPA_WORKFLOW(기본 generation-acceptance)
USAGE
}

fail() {
  echo "VALIDATE_MANIFEST: FAIL — $1" >&2
  exit "$EXIT_FAIL"
}

usage_error() {
  echo "VALIDATE_MANIFEST: USAGE — $1" >&2
  usage >&2
  exit "$EXIT_USAGE"
}

# ── 0. 인자·환경 ───────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help) usage; exit "$EXIT_OK";;
esac
[ "$#" -eq 1 ] || usage_error "manifest 경로 인자가 정확히 하나여야 한다"
MANIFEST="$1"
[ -f "$MANIFEST" ] || usage_error "manifest 파일이 없다: $MANIFEST"
command -v jq >/dev/null 2>&1 || usage_error "jq가 없다(runner 프리인스톨)"
command -v gh >/dev/null 2>&1 || usage_error "gh 클라이언트가 없다"

TMPDIR_RUN="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_RUN"' EXIT

# ── 1. 스키마 검사 (필수 필드 존재·형식) ───────────────────────────────
# 관계 검사와 분리된 단계: 필드가 없으면 "관계가 어긋났다"가 아니라
# "증거가 없다"로 보고한다(관측 불가 ≠ 일치).
schema_check() {
  local m="$1"
  local missing=0
  local f

  for f in schemaVersion repository promotionId candidateSha candidatePr \
           mergeSha acceptanceRun rulesetReadback productionRun; do
    if ! jq -e --arg k "$f" 'has($k) and (.[$k] != null)' "$m" >/dev/null 2>&1; then
      echo "  schema: MISSING — $f" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    return 1
  fi

  # 형식 검사 — 값의 모양이 계약과 다르면 그 관계는 판정할 수 없다.
  local type_err=""
  check_type() { # $1 = jq path, $2 = expected type
    local got
    got="$(jq -r "$1 | type" "$m" 2>/dev/null || echo "invalid")"
    if [ "$got" != "$2" ]; then
      type_err="$type_err $1($2≠$got)"
    fi
  }
  check_type '.schemaVersion' number
  check_type '.repository' string
  check_type '.promotionId' string
  check_type '.candidateSha' string
  check_type '.candidatePr' number
  check_type '.mergeSha' string
  check_type '.acceptanceRun' object
  check_type '.acceptanceRun.id' number
  check_type '.acceptanceRun.workflow' string
  check_type '.acceptanceRun.event' string
  check_type '.acceptanceRun.conclusion' string
  check_type '.acceptanceRun.headSha' string
  check_type '.rulesetReadback' object
  check_type '.rulesetReadback.provenance' string
  check_type '.rulesetReadback.fetchedAt' string
  check_type '.rulesetReadback.expected' array
  check_type '.rulesetReadback.actual' array
  check_type '.rulesetReadback.equal' boolean
  check_type '.productionRun' object
  check_type '.productionRun.id' number
  check_type '.productionRun.workflow' string
  check_type '.productionRun.event' string
  check_type '.productionRun.headSha' string

  if [ -n "$type_err" ]; then
    echo "  schema: TYPE MISMATCH —$type_err" >&2
    return 1
  fi

  # UNKNOWN 마커는 통과로 읽지 않는다(승격 완료 선언 불가).
  local unknowns
  unknowns="$(jq -r '
    [.. | strings | select(. == "UNKNOWN" or . == "unknown" or . == "TBD" or . == "")]
    | length' "$m" 2>/dev/null || echo "-1")"
  if [ "$unknowns" != "0" ]; then
    echo "  schema: UNKNOWN/EMPTY 값이 $unknowns개 있다(관측 불가 = 통과 불가)" >&2
    return 1
  fi
  return 0
}

# ── 2. 관계 검사 ───────────────────────────────────────────────────────
# 각 함수는 실패 시 1을 반환하고, 호출부는 어떤 관계가 어긋났는지 출력한다.
# 모든 실측은 gh API(네트워크) — 값은 서버에서 온다.

pr_field() { # $1 = pr number, $2 = jq field — 실패 시 1(값을 출력하지 않는다)
  local out
  out="$(gh api "repos/$REPO/pulls/$1" --jq "$2" 2>/dev/null)" || return 1
  printf '%s' "$out"
}

run_field() { # $1 = run id, $2 = jq field — 실패 시 1(값을 출력하지 않는다)
  local out
  out="$(gh api "repos/$REPO/actions/runs/$1" --jq "$2" 2>/dev/null)" || return 1
  printf '%s' "$out"
}

rel_1_acceptance_run() {
  local m="$1"
  local id workflow event conclusion head_sha
  id="$(jq -r '.acceptanceRun.id' "$m")"
  workflow="$(jq -r '.acceptanceRun.workflow' "$m")"
  event="$(jq -r '.acceptanceRun.event' "$m")"
  conclusion="$(jq -r '.acceptanceRun.conclusion' "$m")"
  head_sha="$(jq -r '.acceptanceRun.headSha' "$m")"

  if [ "$workflow" != "$WORKFLOW_NAME" ]; then
    echo "  (1) acceptanceRun.workflow — 기대 '$WORKFLOW_NAME', 실제 '$workflow'" >&2
    return 1
  fi
  if [ "$event" != "merge_group" ]; then
    echo "  (1) acceptanceRun.event — 기대 'merge_group', 실제 '$event'" >&2
    return 1
  fi
  if [ "$conclusion" != "success" ]; then
    echo "  (1) acceptanceRun.conclusion — 기대 'success', 실제 '$conclusion'" >&2
    return 1
  fi

  local api_event api_conclusion api_head_sha api_name
  api_event="$(run_field "$id" '.event')" || true
  api_conclusion="$(run_field "$id" '.conclusion')" || true
  api_head_sha="$(run_field "$id" '.head_sha')" || true
  api_name="$(run_field "$id" '.name')" || true
  if [ -z "$api_event" ] || [ -z "$api_head_sha" ]; then
    echo "  (1) acceptanceRun — run $id을 API에서 읽지 못했다(관측 불가)" >&2
    return 1
  fi
  if [ "$api_event" != "merge_group" ]; then
    echo "  (1) acceptanceRun 실측 event — 기대 'merge_group', 실제 '$api_event'" >&2
    return 1
  fi
  if [ "$api_conclusion" != "success" ]; then
    echo "  (1) acceptanceRun 실측 conclusion — 기대 'success', 실제 '$api_conclusion'" >&2
    return 1
  fi
  if [ "$api_head_sha" != "$head_sha" ]; then
    echo "  (1) acceptanceRun.headSha — 기록 '$head_sha' ≠ 실측 '$api_head_sha'" >&2
    return 1
  fi
  echo "  (1) acceptanceRun — OK (run $id, '$api_name', event=merge_group, conclusion=success, head_sha=$api_head_sha)"
  return 0
}

rel_2_candidate_sha() {
  local m="$1"
  local pr candidate_sha api_head
  pr="$(jq -r '.candidatePr' "$m")"
  candidate_sha="$(jq -r '.candidateSha' "$m")"
  api_head="$(pr_field "$pr" '.head.sha')" || true
  if [ -z "$api_head" ]; then
    echo "  (2) candidateSha — PR $pr의 head SHA를 읽지 못했다(관측 불가)" >&2
    return 1
  fi
  if [ "$api_head" != "$candidate_sha" ]; then
    echo "  (2) candidateSha — 기록 '$candidate_sha' ≠ PR $pr의 실측 head '$api_head'" >&2
    return 1
  fi
  echo "  (2) candidateSha — OK (PR $pr head = $api_head)"
  return 0
}

rel_3_ruleset_readback() {
  local m="$1"
  local provenance fetched_at equal expected actual
  provenance="$(jq -r '.rulesetReadback.provenance' "$m")"
  fetched_at="$(jq -r '.rulesetReadback.fetchedAt' "$m")"
  equal="$(jq -r '.rulesetReadback.equal' "$m")"
  expected="$(jq -r '.rulesetReadback.expected | map(tostring) | sort | join("\n")' "$m")"
  actual="$(jq -r '.rulesetReadback.actual | map(tostring) | sort | join("\n")' "$m")"

  if [ "$provenance" != "operator-promotion-adapter" ]; then
    echo "  (3) rulesetReadback.provenance — 기대 'operator-promotion-adapter', 실제 '$provenance'" >&2
    return 1
  fi
  if [ -z "$fetched_at" ]; then
    echo "  (3) rulesetReadback.fetchedAt — 비어 있다(취득 시각 없음 = 실취득 아님)" >&2
    return 1
  fi
  if [ -z "$expected" ] || [ -z "$actual" ]; then
    echo "  (3) rulesetReadback — expected/actual가 비어 있다(비교 대상 없음)" >&2
    return 1
  fi
  if [ "$equal" != "true" ]; then
    echo "  (3) rulesetReadback.equal — false(기록된 expected ≠ actual)" >&2
    return 1
  fi
  if [ "$expected" != "$actual" ]; then
    echo "  (3) rulesetReadback — expected ≠ actual" >&2
    echo "      expected: $(echo "$expected" | tr '\n' ' ')" >&2
    echo "      actual:   $(echo "$actual" | tr '\n' ' ')" >&2
    return 1
  fi
  echo "  (3) rulesetReadback — OK (provenance=$provenance, fetchedAt=$fetched_at, expected==actual)"
  return 0
}

rel_4_production_run() {
  local m="$1"
  local id merge_sha api_head
  id="$(jq -r '.productionRun.id' "$m")"
  merge_sha="$(jq -r '.mergeSha' "$m")"
  api_head="$(run_field "$id" '.head_sha')" || true
  if [ -z "$api_head" ]; then
    echo "  (4) productionRun — run $id을 API에서 읽지 못했다(관측 불가)" >&2
    return 1
  fi
  if [ "$api_head" != "$merge_sha" ]; then
    echo "  (4) productionRun.head_sha — 실측 '$api_head' ≠ mergeSha '$merge_sha'" >&2
    return 1
  fi
  echo "  (4) productionRun — OK (run $id head_sha = mergeSha = $api_head)"
  return 0
}

rel_5_merge_sha() {
  local m="$1"
  local pr merge_sha api_merge
  pr="$(jq -r '.candidatePr' "$m")"
  merge_sha="$(jq -r '.mergeSha' "$m")"
  api_merge="$(pr_field "$pr" '.merge_commit_sha')" || true
  if [ -z "$api_merge" ]; then
    echo "  (5) mergeSha — PR $pr의 mergeCommit을 읽지 못했다(관측 불가)" >&2
    return 1
  fi
  if [ "$api_merge" != "$merge_sha" ]; then
    echo "  (5) mergeSha — 기록 '$merge_sha' ≠ PR $pr의 실측 mergeCommit '$api_merge'" >&2
    return 1
  fi
  echo "  (5) mergeSha — OK (PR $pr mergeCommit = $api_merge)"
  return 0
}

# ── 실행 ───────────────────────────────────────────────────────────────
echo "VALIDATE_MANIFEST: $MANIFEST (repo=$REPO, workflow=$WORKFLOW_NAME)"

if ! schema_check "$MANIFEST"; then
  fail "schema 검사 실패 — 필수 필드/형식/UNKNOWN 값 확인 필요"
fi
echo "  schema — OK"

rc=0
rel_1_acceptance_run "$MANIFEST" || rc=1
rel_2_candidate_sha "$MANIFEST" || rc=1
rel_3_ruleset_readback "$MANIFEST" || rc=1
rel_4_production_run "$MANIFEST" || rc=1
rel_5_merge_sha "$MANIFEST" || rc=1

if [ "$rc" -ne 0 ]; then
  fail "관계 검증 실패 — 위 항목 중 어긋난 관계를 확인한다(승격 완료 선언 불가)"
fi

echo "VALIDATE_MANIFEST: PASS — 5개 관계 전부 실측 연결 (acceptanceRun event=merge_group, candidateSha==PR head, readback expected==actual[operator provenance], productionRun@mergeSha, mergeSha==PR mergeCommit)"
exit "$EXIT_OK"
