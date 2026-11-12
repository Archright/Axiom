#!/usr/bin/env bash
#
# go_critical_parallel_extraction.sh — read-only GO-critical step economics extractor (GET-only).
#
# Consumes EXISTING GitHub Actions records only (no instrumentation, no canaries,
# no workflow restructuring) — the measurement surface authorized by
# docs/evidence/e3_measurement_contract_2026-10-11.md §7 (authority table):
#   * run existence / state     = GitHub Actions API + job logs
#   * GO-critical step duration = log line timestamps (7-digit fractional, §7.2 primary);
#                                 API steps[] timestamps are the coarser fallback adapter
#   * a-restore covariate       = `##[end-action id=__self.a-restore …duration_ms=…]` log field
#   * run wall-clock            = run record `updated_at − run_started_at`
#                                 (GET /actions/runs/{id}/timing is FORBIDDEN, §7.1)
#
# Extraction targets (per run, `attest / admission-check` job):
#   - job identity: id, runner_name, labels (environment metadata — NOT speed
#     measurements; recorded to expose the PR #729 routing cohort boundary,
#     merge 3cefd3079, 2026-10-11T04:11:07Z)
#   - full steps[] anatomy (job prep / compile / serial remainder — inputs for
#     T_parallel,total estimation, NOT used for GO-critical primary values)
#   - per-test GO-critical durations (fractional-second precision) for the
#     4 DEBT#432 tests — serial era: RUN→PASS log-line deltas (UNCHANGED path);
#     parallel era: `[admission-tests] LANE` duration_ms rows (1차값)
#   - GO-critical step span (first step log line → 4/4 PASS line)
#   - a-restore duration_ms (stratification marker, threshold 40,000 ms fixed a
#     priori by contract §5.2 — >40s is the fast phenotype H stratum)
#   - `[test-supply] restored … entries=N` (warm N>0 / cold N=0 carrier state)
#
# Lane-aware job sourcing (prereg §10 Q2, 2026-10-16 APPROVED — 수집 채널
# 적응, 1차값 정의 불변; evidence: docs/evidence/harness_lane_sourcing_gapb_
# 2026-10-17.md): matrix-generation runs (G2, ≥ 38805085401) run the
# GO-critical tests in the 2-lane job matrix `attest / go-critical-lane (0)`
# / `(1)` — the frozen extractor sourced only `attest / admission-check` and
# recorded go_mode=none / NA for every matrix run. The run's lane job logs
# are now appended to the parsing corpus (consume → lane-0 → lane-1; the
# dual-mode parser keeps its semantics — any LANE row flips it to lane mode,
# and the four tests are disjoint halves, one LANE row each; one latent
# matcher defect fixed, see below):
#   * per-test columns + go_lane_sum_s come from the union LANE rows
#     (= §4.1's log-line 1차값 path, verbatim command of §4.3);
#   * a-restore stays sourced from the consume job log only (E3 §5.2
#     authority — each lane also prints its OWN a-restore marker; not
#     consumed, different restores are an observation, not a covariate swap);
#   * supply_entries = first `[test-supply]` line of the corpus (serial era:
#     the consume line, byte-identical; matrix era: lane-0's — the per-lane
#     values remain in the lane logs);
#   * gc_fired = every sourced lane shows its own `PASS — <n>/<n> GO-critical
#     admission tests green` aggregate (the serial 4/4 aggregate line does
#     not exist in the matrix generation); serial era: the 4/4 grep verbatim;
#   * LANE-row matcher fix (latent frozen-parser defect surfaced BY this
#     sourcing change): the dual-mode regex `LANE [A-Za-z0-9_]+ duration_ms=`
#     never matched the production `LANE lane=<N> <slug> duration_ms=` rows
#     (the `lane=<N> ` prefix breaks the slug match). Unobservable while only
#     the consume job was sourced (no LANE rows there); once lane logs joined
#     the corpus, the parser silently degraded to serial RUN→PASS parsing of
#     the lane logs — plausible-looking values, wrong channel, sum=NA
#     (mislabeling = fail-closed visible, never shipped). Fixed to accept the
#     production shape (legacy shape kept); §4.3's duration_ms 1차값 경로가
#     이제 실제로 발화한다.
#   * gc_span_s stays NA in lane mode (no single cross-lane span exists; the
#     lane steps[] wall-clocks are in <OUT_PREFIX>.steps.tsv via the lane job
#     ids recorded in the two appended columns go_lane0_job_id/go_lane1_job_id).
# Serial-era runs have no lane jobs — every extension degenerates to the
# legacy path byte-identically.
#
# Modes:
#   runs <CREATED_AFTER> <OUT_PREFIX>   extract per-run + per-step TSV tables
#   cadence <DAYS>                      admission-gate runs per UTC day by event
#                                       (K derivation for S_K economics; firing
#                                       fraction comes from `runs` output)
#
# Dual-mode parsing (per run log corpus — mutually exclusive — never mixed):
#   * ≥1 `[admission-tests] LANE lane=<N> <slug> duration_ms=<ms> — <test>`
#     line (production shape; the legacy `LANE <slug> duration_ms=` shape is
#     also accepted) → LANE mode (`go_mode=lane`): per-test = that lane's
#     duration_ms; `go_lane_sum_s` = Σ lane duration_ms = GO 스텝 테스트 소요 —
#     step wall-clock(gc_span_s, steps.tsv)과 구분되는 별도 컬럼. duration_ms
#     파일/행 결측(또는 비숫자)은 `NA` 보고 — 삼킴 금지(§0.9; 합산 성분이
#     하나라도 결측면 합계도 NA).
#   * else the pre-parallel serial RUN→PASS path verbatim (`go_mode=serial`) —
#     기존 20컬럼 값 바이트 동일 보존. neither marker → `go_mode=none`, values NA.
#   Basis: AB 원장 §3 절차 4 / §4 — docs/evidence/go_critical_parallel_ab_proof_2026-10-11.md:
#   "병렬 레짐 로그에서 RUN→PASS 로그행 타임스탬프는 post-wait 출력이라 퇴화값이다
#   — 테스트별 1차값은 `LANE duration_ms` 행이다 (…AWK는 … LANE 행 기반 파싱으로
#   갱신을 요구한다 — 후속 커밋)". 직렬 로그는 착지 전까지 계속 나오므로 하위호환 필수.
#
# NOTE on pagination: `--paginate` silently undercounts on this repo's volume
# (measured 2026-10-11: it stopped after ~1000 runs, missing older days), so
# `cadence` iterates day-bounded queries with explicit pages instead.
#
# Output (runs mode): <OUT_PREFIX>.runs.tsv (one row per run; legacy 20 columns
#                     + appended go_mode, go_lane_sum_s + appended
#                     go_lane0_job_id, go_lane1_job_id) +
#                     <OUT_PREFIX>.steps.tsv (one row per job step).
# Both are projections of API/log records — advisory evidence, not authority.

set -euo pipefail

REPO="Archright/Axiom"
WF=".github/workflows/admission-gate-v2.yml"
MODE="${1:-runs}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 2; }; }
need gh; need jq; need awk; need date

PERTHEST_AWK='
function tsec(ts,   i, h, m, s) {
  i = index(ts, "T")
  h = substr(ts, i+1, 2) + 0
  m = substr(ts, i+4, 2) + 0
  s = substr(ts, i+7, 10) + 0
  return h*3600 + m*60 + s
}
function fmt(v) { return (v == "NA") ? "NA" : sprintf("%.1f", v) }
function laneout(p,   k) {
  for (k = 1; k <= 4; k++) if (p == P[k] && (p in lms) && lms[p] != "NA") return lms[p] / 1000
  return "NA"
}
function iscanon(p,   k) { for (k = 1; k <= 4; k++) if (p == P[k]) return 1; return 0 }
BEGIN {
  np = split("tests/unit/proof_integrity_test.nim tests/unit/test_s1a_lean_golden.nim tests/unit/test_d2_golden.nim tests/unit/test_d2_persist.nim", P, " ")
}
# serial-era capture — semantics byte-identical to the pre-dual-mode extractor
/\[admission-tests\] RUN make test-fast-one T=/ {
  ser = 1
  cur = tsec($1); f = $0; sub(/.* T=/, "", f); curfile = f
}
/\[admission-tests\] PASS — tests\// && curfile != "" {
  e = tsec($1); m = $0; sub(/.*PASS — /, "", m); sub(/ .*/, "", m); dur[m] = tsec($1) - cur
}
# parallel-era capture — LANE rows are the 1차값; any LANE row flips the whole
# log to lane mode (degenerate post-wait RUN/PASS rows above are then ignored;
# 두 경로는 한 로그에서 절대 혼합되지 않는다). Production row shape (verbatim,
# admission-check.yml go-critical-lane step):
#   `[admission-tests] LANE lane=<N> <slug> duration_ms=<ms> — <test>`
#   (실패행: `… duration_ms=<ms> result=FAIL — <test>` — duration 캡처 동일)
# The frozen parser regex `LANE [A-Za-z0-9_]+ duration_ms=` never matched the
# production `lane=<N> ` prefix (latent since the dual-mode commit — the
# frozen extractor sourced only the consume log, which carries no LANE rows,
# so the mismatch was unobservable); both shapes are accepted here.
/\[admission-tests\] LANE (lane=[0-9]+ )?[A-Za-z0-9_]+ duration_ms=[0-9]+/ {
  lane = 1
  lt = $0; sub(/^.* — /, "", lt); sub(/ .*/, "", lt)
  ms = ""
  for (j = 1; j <= NF; j++) if ($j ~ /^duration_ms=/) ms = substr($j, 13)
  lms[lt] = (ms ~ /^[0-9]+$/) ? ms + 0 : "NA"
  if (!iscanon(lt)) lforeign = 1
}
/\[test-supply\] restored build\/nimcache\/test entries=/ && gstart == 0 { gstart = tsec($1); sseen = 1 }
/\[admission-tests\] PASS — 4\/4 GO-critical/ { gend = tsec($1); eseen = 1 }
END {
  if (lane) {
    pi = laneout(P[1]); s1a = laneout(P[2]); d2g = laneout(P[3]); d2p = laneout(P[4])
    span = (sseen && eseen) ? gend - gstart : "NA"
    tot = 0; oksum = !lforeign
    for (k = 1; k <= np; k++) {
      if (!(P[k] in lms) || lms[P[k]] == "NA") oksum = 0
      else tot += lms[P[k]]
    }
    gsum = oksum ? tot / 1000 : "NA"
    printf "%s %s %s %s %s lane %s\n", fmt(pi), fmt(s1a), fmt(d2g), fmt(d2p), fmt(span), fmt(gsum)
  } else if (ser) {
    pi = dur[P[1]] + 0; s1a = dur[P[2]] + 0; d2g = dur[P[3]] + 0; d2p = dur[P[4]] + 0
    span = (gend > 0) ? (gend - gstart) : 0
    printf "%.1f %.1f %.1f %.1f %.1f serial NA\n", pi, s1a, d2g, d2p, span
  } else {
    print "NA NA NA NA NA none NA"
  }
}'


case "$MODE" in
cadence)
  DAYS="${2:-14}"
  echo "# admission-gate runs per UTC day by event (window: last ${DAYS} days)"
  echo "# columns: day  merge_group  pull_request"
  for I in $(seq 0 $((DAYS-1))); do
    D="$(date -u -d "-${I} days" +%Y-%m-%d)"
    M=0; PRX=0
    for P in 1 2 3 4 5 6 7 8; do
      OUT="$(gh api "repos/${REPO}/actions/runs?created=${D}T00%3A00%3A00Z..${D}T23%3A59%3A59Z&per_page=100&page=${P}" \
        --jq '"\([.workflow_runs[] | select(.path=="'"${WF}"'" and .event=="merge_group")] | length) \([.workflow_runs[] | select(.path=="'"${WF}"'" and .event=="pull_request")] | length) \(.workflow_runs | length)"' 2>/dev/null || echo '0 0 0')"
      read -r MG PR T <<< "${OUT}"
      M=$((M+MG)); PRX=$((PRX+PR))
      [ "${T}" = "0" ] && break
    done
    echo -e "${D}\t${M}\t${PRX}"
  done | sort
  ;;

runs)
  AFTER="${2:-2026-10-10T22:39:36Z}"
  OUT_PREFIX="${3:-/tmp/go_econ}"
  RUNS_OUT="${OUT_PREFIX}.runs.tsv"
  STEPS_OUT="${OUT_PREFIX}.steps.tsv"

  printf 'run_id\tcreated_at\tevent\tconclusion\thead_sha\tbranch\trun_wallclock_s\tjob_id\tjob_started\tjob_completed\trunner_name\tlabels\ta_restore_ms\tsupply_entries\tgc_fired\tgc_span_s\tpi_s\ts1a_s\td2g_s\td2p_s\tgo_mode\tgo_lane_sum_s\tgo_lane0_job_id\tgo_lane1_job_id\n' > "${RUNS_OUT}"
  printf 'run_id\tstep_number\tstep_name\tstep_started\tstep_completed\tstep_s\n' > "${STEPS_OUT}"

  gh api --paginate "repos/${REPO}/actions/runs?created=%3E%3D${AFTER}&per_page=100" \
    --jq '.workflow_runs[] | select(.path=="'"${WF}"'") | [.id, .created_at, .event, .conclusion, .head_sha, .head_branch, .run_started_at, .updated_at] | @tsv' \
  | while IFS=$'\t' read -r RUN_ID CREATED EVENT CONCLUSION HEAD_SHA BRANCH RUN_STARTED RUN_UPDATED; do
      JOB="$(gh api "repos/${REPO}/actions/runs/${RUN_ID}/jobs?per_page=100" \
        --jq '.jobs[] | select(.name=="attest / admission-check") | .id' | head -1)"
      if [ -z "${JOB}" ]; then
        echo "WARN: no attest/admission-check job in run ${RUN_ID}" >&2
        continue
      fi

      # Lane jobs (prereg §10 Q2 — see header). A lane that did not run
      # (PR-venue skipped expansion) is never sourced. LC_ALL=C sort pins the
      # deterministic lane-0 → lane-1 corpus order (matrix job names sort so).
      LANE_IDS="$(gh api "repos/${REPO}/actions/runs/${RUN_ID}/jobs?per_page=100" \
        --jq '.jobs[] | select((.name=="attest / go-critical-lane (0)" or .name=="attest / go-critical-lane (1)") and .conclusion != "skipped") | [.name, (.id|tostring)] | @tsv' \
        | LC_ALL=C sort || true)"
      LANE_CORPUS=""
      N_LANES=0
      LANE0_ID="$(awk -F'\t' '$1=="attest / go-critical-lane (0)"{print $2}' <<< "${LANE_IDS}")"
      LANE1_ID="$(awk -F'\t' '$1=="attest / go-critical-lane (1)"{print $2}' <<< "${LANE_IDS}")"
      if [ -n "${LANE_IDS}" ]; then
        while IFS=$'\t' read -r _ LID; do
          [ -n "${LID}" ] || continue
          gh api --allow-escape-sequences "repos/${REPO}/actions/jobs/${LID}/logs" \
            > "/tmp/go_econ_log_${LID}.log" 2>/dev/null || : > "/tmp/go_econ_log_${LID}.log"
          if [ -s "/tmp/go_econ_log_${LID}.log" ]; then
            LANE_CORPUS="${LANE_CORPUS} /tmp/go_econ_log_${LID}.log"
            N_LANES=$((N_LANES+1))
          fi
        done <<< "${LANE_IDS}"
      fi

      gh api "repos/${REPO}/actions/jobs/${JOB}" \
        --jq '[(.runner_name//"-"), ((.labels//[])|join(";")), (.started_at//"-"), (.completed_at//"-")] | @tsv' \
      > "/tmp/go_econ_id_${JOB}.txt"
      RUNNER_NAME="$(cut -f1 "/tmp/go_econ_id_${JOB}.txt")"
      LABELS="$(cut -f2 "/tmp/go_econ_id_${JOB}.txt")"
      JOB_STARTED="$(cut -f3 "/tmp/go_econ_id_${JOB}.txt")"
      JOB_COMPLETED="$(cut -f4 "/tmp/go_econ_id_${JOB}.txt")"

      gh api "repos/${REPO}/actions/jobs/${JOB}" \
        --jq '.steps[] | [.number, .name, (.started_at//"-"), (.completed_at//"-"), (if .started_at != null and .completed_at != null then ((.completed_at|fromdate) - (.started_at|fromdate)) else "-" end)] | @tsv' \
      | awk -F'\t' -v rid="${RUN_ID}" '{print rid "\t" $0}' >> "${STEPS_OUT}"

      WALL_S=$(( $(date -u -d "${RUN_UPDATED}" +%s) - $(date -u -d "${RUN_STARTED}" +%s) ))

      gh api --allow-escape-sequences "repos/${REPO}/actions/jobs/${JOB}/logs" \
        > "/tmp/go_econ_log_${JOB}.log" 2>/dev/null || : > "/tmp/go_econ_log_${JOB}.log"
      LOG="/tmp/go_econ_log_${JOB}.log"
      # consume log first (a-restore provenance), then lane-0 → lane-1
      # shellcheck disable=SC2086 — intentional word split of the corpus list
      LOGCORPUS="${LOG} ${LANE_CORPUS}"

      A_RESTORE="$(grep -oE 'id=__self\.a-restore;[^]]*duration_ms=[0-9]+' "${LOG}" | head -1 \
        | grep -oE 'duration_ms=[0-9]+' | cut -d= -f2 || true)"
      # shellcheck disable=SC2086
      SUPPLY="$(cat ${LOGCORPUS} | grep -oE 'restored build/nimcache/test entries=[0-9]+' | head -1 \
        | grep -oE 'entries=[0-9]+' | cut -d= -f2 || true)"
      if [ "${N_LANES}" -gt 0 ]; then
        # matrix generation: green = every sourced lane shows its own N/N
        # aggregate (the serial 4/4 aggregate line does not exist here)
        # shellcheck disable=SC2086
        GC_GREENS="$(cat ${LOGCORPUS} | grep -acE '\[admission-tests\] PASS — [0-9]+/[0-9]+ GO-critical admission tests green' || true)"
        GC_FIRED="$( [ "${GC_GREENS}" -ge "${N_LANES}" ] && echo yes || echo no)"
      else
        GC_FIRED="$(grep -q 'PASS — 4/4 GO-critical admission tests green' "${LOG}" && echo yes || echo no)"
      fi

      # shellcheck disable=SC2086
      VALS="$(cat ${LOGCORPUS} | awk "${PERTHEST_AWK}")"
      read -r PI S1A D2G D2P GC_SPAN GO_MODE GO_SUM <<< "${VALS}"

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "${RUN_ID}" "${CREATED}" "${EVENT}" "${CONCLUSION}" "${HEAD_SHA}" "${BRANCH}" \
        "${WALL_S}" "${JOB}" "${JOB_STARTED}" "${JOB_COMPLETED}" "${RUNNER_NAME}" "${LABELS}" \
        "${A_RESTORE:-NA}" "${SUPPLY:-NA}" "${GC_FIRED}" "${GC_SPAN:-NA}" "${PI}" "${S1A}" "${D2G}" "${D2P}" \
        "${GO_MODE}" "${GO_SUM}" "${LANE0_ID:--}" "${LANE1_ID:--}" \
        >> "${RUNS_OUT}"
      rm -f "/tmp/go_econ_id_${JOB}.txt" "/tmp/go_econ_log_${JOB}.log"
      for LCLEAN in ${LANE_CORPUS}; do rm -f "${LCLEAN}"; done
    done
  echo "wrote ${RUNS_OUT}"
  echo "wrote ${STEPS_OUT}"
  ;;
*)
  echo "unknown mode: ${MODE} (use runs|cadence)" >&2
  exit 2
  ;;
esac
