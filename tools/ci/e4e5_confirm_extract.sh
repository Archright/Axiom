#!/usr/bin/env bash
#
# e4e5_confirm_extract.sh — THE confirmatory GO-critical duration extraction
# (E3 Δ̂ estimand, contract §5.1/§5.6). Single-shot, snapshot-bound.
#
# This is the ONLY tool in the E-4/E-5 pipeline permitted to read GO-critical
# duration values, and it may do so EXACTLY ONCE per snapshot:
#
#   §5.6   "단일 분석: 유효 n_B=12 ∧ n_C=30 도달 시점에 딱 한 번 결과 추출·분석
#           수행. 결과 추출은 스크립트 단일 패스로 수행하고 반복 추출 금지."
#   §5.6(b) 창 닫힘 종료: window closed with n short → exactly one
#           "underpowered, non-confirmatory" analysis at the achieved n.
#   §5.6(c) 중간 분석 금지: collectors/classifiers may re-run freely
#           (inclusion checks expose no result distribution) — duration
#           extraction is NOT an inclusion check and is banned until the
#           single analysis point.
#
# Guard chain (each phase HARD-FAILS closed):
#   P1 snapshot resolution  — named snapshot must exist with a valid manifest
#   P2 content integrity    — every frozen file re-hashed against the
#                             manifest; snapshot_content_sha256 recomputed;
#                             any mismatch = tampered/rotted snapshot → FAIL
#   P3 single-shot guard    — manifest.confirmatory_extraction.attempts
#                             non-empty → HARD FAIL (the completion marker IS
#                             the no-peeking enforcement; a second extraction
#                             on the same snapshot is history revision)
#   P4 stop rule            — extraction runs only at fixed n
#                             (n_B ≥ 12 ∧ n_C ≥ 30, observable-duration
#                             denominators from the frozen census) OR after
#                             window close (§5.6(b), labeled underpowered).
#                             Interim → HARD FAIL exit 3, NO marker written
#                             (nothing was peeked; the run may lawfully fire
#                             later when the rule fires). The clock is the
#                             real clock — no override exists, by design.
#   P5 selection            — confirmatory set re-derived from the FROZEN
#                             ledger (design variables only: eligibility,
#                             HIT/MISS arm, generation attribution,
#                             reused_skip) with the classifier's anomaly
#                             rule; cross-checked against the frozen census.
#                             개정 기록 A1: duration-pre-observed runs are
#                             excluded fail-closed — mechanically impossible
#                             here (the window OPENS at the contract merge
#                             instant) and asserted, not assumed.
#   P6 extraction           — ONE pass: per selected run, GET the job record
#                             (steps[]) + job log once. GO-critical steps =
#                             name starting "[check] GO-critical" (§5.1,
#                             multiple matches summed). Measurement source:
#                             log-line timestamps (7-dp, §7.2 primary),
#                             bracketed by the API step window (second
#                             resolution — lines of adjacent steps falling
#                             inside a boundary second can contribute ≤ 1 s
#                             bracket noise, recorded alongside the API
#                             seconds as the §7.2 fallback). a-restore
#                             duration_ms (§5.2 stratification marker) is
#                             pulled in the same single pass. Log fetch
#                             failure → recorded exclusion (결측 규칙 §5.4:
#                             exclude + record, no imputation) — the pass is
#                             still consumed.
#   P7 evidence + marker    — result written to a NEW dated evidence file
#                             (never overwrites), then the completion marker
#                             is APPENDED to the snapshot manifest (atomic
#                             tmp+mv; frozen files untouched)
#
# Interrupted passes: the extraction phase buffers in a temp dir; the marker
# is written only after the evidence file exists. A crash before P7 leaves no
# marker — the next invocation is then the FIRST completed pass (a crashed
# pass produced no result and no analysis; the once-only rule binds
# completed analytical extractions).
#
# Usage: e4e5_confirm_extract.sh --snapshot ID [--data-dir DIR]
#                                [--evidence-dir DIR]
#   ID = snapshot stamp (directory name under <data-dir>/snapshots/).
# Exit codes: 0 = extraction complete (evidence + marker written)
#             1 = hard failure (integrity / marker guard / selection
#                 cross-check / evidence write)
#             2 = usage/environment error
#             3 = stop rule not met — interim extraction banned (§5.6(c));
#                 no marker written, retry is lawful when the rule fires

set -euo pipefail

SNAPSHOT_ID=""
DATA_DIR="data/e4e5"
EVIDENCE_DIR=""
OWNER="Archright"
REPO="Axiom"
# Fixed design values (contract §5.5/§5.6 — NOT derived from data).
FIXED_N_B=12
FIXED_N_C=30

while [ $# -gt 0 ]; do
  case "$1" in
    --snapshot)     SNAPSHOT_ID="$2"; shift 2 ;;
    --data-dir)     DATA_DIR="$2"; shift 2 ;;
    --evidence-dir) EVIDENCE_DIR="$2"; shift 2 ;;
    -h|--help)      sed -n '2,72p' "$0"; exit 0 ;;
    *) echo "usage: $0 --snapshot ID [--data-dir DIR] [--evidence-dir DIR]" >&2; exit 2 ;;
  esac
done
[ -n "$SNAPSHOT_ID" ] || { echo "[e4e5-confirm] FAIL: --snapshot ID is required" >&2; exit 2; }
printf '%s' "$SNAPSHOT_ID" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' \
  || { echo "[e4e5-confirm] FAIL: snapshot id must be a snapshot stamp (UTCcompact, e.g. 20261011T094401Z): $SNAPSHOT_ID" >&2; exit 2; }
[ -z "$EVIDENCE_DIR" ] && EVIDENCE_DIR="$DATA_DIR/confirmatory"

command -v gh        >/dev/null 2>&1 || { echo "[e4e5-confirm] FAIL: gh not available" >&2; exit 2; }
command -v jq        >/dev/null 2>&1 || { echo "[e4e5-confirm] FAIL: jq not available" >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "[e4e5-confirm] FAIL: sha256sum not available" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SNAP_DIR="$DATA_DIR/snapshots/$SNAPSHOT_ID"
MANIFEST="$SNAP_DIR/manifest.json"

# ---------------------------------------------------------------- P1: resolve
[ -d "$SNAP_DIR" ] || { echo "[e4e5-confirm] HARD-FAIL: snapshot not found: $SNAP_DIR" >&2; exit 1; }
[ -s "$MANIFEST" ] || { echo "[e4e5-confirm] HARD-FAIL: snapshot manifest missing: $MANIFEST" >&2; exit 1; }
jq -e . "$MANIFEST" >/dev/null 2>&1 \
  || { echo "[e4e5-confirm] HARD-FAIL: manifest not valid JSON: $MANIFEST" >&2; exit 1; }
[ "$(jq -r '.schema' "$MANIFEST")" = "axiom.e4e5.snapshot_manifest/1" ] \
  || { echo "[e4e5-confirm] HARD-FAIL: unexpected manifest schema: $(jq -r '.schema' "$MANIFEST")" >&2; exit 1; }

# ------------------------------------------------------- P2: content integrity
integrity_fail() { echo "[e4e5-confirm] HARD-FAIL: snapshot integrity: $1" >&2; exit 1; }
while IFS=$'\t' read -r f h b; do
  [ -s "$SNAP_DIR/$f" ] || integrity_fail "frozen file missing/empty: $f"
  actual="$(sha256sum "$SNAP_DIR/$f" | cut -d' ' -f1)"
  [ "$actual" = "$h" ] || integrity_fail "frozen file hash mismatch: $f (manifest=$h actual=$actual)"
  fsz="$(wc -c < "$SNAP_DIR/$f" | tr -d ' ')"
  [ "$fsz" = "$b" ] || integrity_fail "frozen file size mismatch: $f"
done < <(jq -r '.content.files[] | [.path, .sha256, (.bytes|tostring)] | @tsv' "$MANIFEST")
content_actual="$(jq -r '.content.files[] | "\(.sha256)  \(.path)"' "$MANIFEST" | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1)"
[ "$content_actual" = "$(jq -r '.content.snapshot_content_sha256' "$MANIFEST")" ] \
  || integrity_fail "snapshot_content_sha256 mismatch — frozen content was modified after freeze"
echo "[e4e5-confirm] P2 integrity: all frozen files hash-verified (content sha256 ${content_actual:0:16}…)"

# ------------------------------------------------------- P3: single-shot guard
n_attempts="$(jq '.confirmatory_extraction.attempts | length' "$MANIFEST")"
if [ "$n_attempts" -gt 0 ]; then
  echo "[e4e5-confirm] HARD-FAIL: snapshot $SNAPSHOT_ID already has $n_attempts confirmatory extraction attempt(s) on record:" >&2
  jq -r '.confirmatory_extraction.attempts[] | "  at=\(.at) outcome=\(.outcome) evidence=\(.evidence_file // "n/a")"' "$MANIFEST" >&2
  echo "[e4e5-confirm] HARD-FAIL: the confirmatory extraction runs EXACTLY ONCE per snapshot (§5.6 단일 분석; 반복 추출 금지). A new analysis requires a NEW dated snapshot frozen after the triggering event." >&2
  exit 1
fi
echo "[e4e5-confirm] P3 single-shot: no prior extraction attempt on this snapshot — proceeding"

# ------------------------------------------------------------ P4: stop rule
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_E="$(date -u -d "$NOW" +%s)"
WINDOW_END="$(jq -r '.window.end' "$MANIFEST")"
WINDOW_END_E="$(date -u -d "$WINDOW_END" +%s)"
N_B_OBS="$(jq -r '.census.n_B_observable_duration' "$MANIFEST")"
N_C_OBS="$(jq -r '.census.n_C_observable_duration' "$MANIFEST")"
STOP_RULE=""
if [ "$N_B_OBS" -ge "$FIXED_N_B" ] && [ "$N_C_OBS" -ge "$FIXED_N_C" ]; then
  STOP_RULE="fixed_n_reached"
elif [ "$NOW_E" -ge "$WINDOW_END_E" ]; then
  STOP_RULE="window_close_underpowered"
else
  echo "[e4e5-confirm] HARD-FAIL: interim extraction banned (§5.6(c)) — stop rule not met:" >&2
  echo "[e4e5-confirm]   observable n_B=$N_B_OBS/$FIXED_N_B  n_C=$N_C_OBS/$FIXED_N_C (fixed n, §5.5/§5.6)" >&2
  echo "[e4e5-confirm]   window open until $WINDOW_END (now=$NOW)" >&2
  echo "[e4e5-confirm]   collection continues; this extraction may lawfully run once when fixed n is reached or at window close. NO marker written — nothing was extracted." >&2
  exit 3
fi
echo "[e4e5-confirm] P4 stop rule: $STOP_RULE (observable n_B=$N_B_OBS n_C=$N_C_OBS; now=$NOW)"

# ---------------------------------------------------------- P5: selection
SEL="$WORK/selection.json"
LEDGER="$SNAP_DIR/ledger.json"
jq -c '
  . as $L
  | (([$L.consumer_observations[] | select(.b_restore.requested_key != .keygen.b_key) | .run_id]
      + [$L.consumer_observations[]
         | select(.b_restore.matched_key != null and .b_restore.matched_key != ""
                  and .b_restore.matched_key != .b_restore.requested_key) | .run_id])
     | unique) as $anom
  | [$L.consumer_observations[]
     | select(.eligibility == "eligible" or .eligibility == "provisional")
     | select((.admission_tests.reused_skip // false) | not)
     | select(.run_id | IN($anom[]) | not)
     | {run_id, run_attempt, job_id, created_at,
        arm: (if .carrier_hit then "B" else "C" end),
        b_identity: .keygen.b_identity, b_key: .keygen.b_key}]
  | {B: [.[] | select(.arm == "B")], C: [.[] | select(.arm == "C")]}' "$LEDGER" > "$SEL"

SEL_B="$(jq '.B | length' "$SEL")"
SEL_C="$(jq '.C | length' "$SEL")"
[ "$SEL_B" -eq "$N_B_OBS" ] && [ "$SEL_C" -eq "$N_C_OBS" ] \
  || { echo "[e4e5-confirm] HARD-FAIL: selection cross-check failed — frozen-ledger re-derivation (B=$SEL_B C=$SEL_C) ≠ frozen census (B=$N_B_OBS C=$N_C_OBS); manifest and ledger desync" >&2; exit 1; }

# 개정 기록 A1 (fail-closed): duration-pre-observed (pre-fixation) runs must
# not enter the confirmatory set. The collection window OPENS at the contract
# merge instant, so every frozen run is post-fixation — asserted mechanically.
A1_VIOLATIONS="$(jq -r --arg ws "$(jq -r '.window.start' "$MANIFEST")" \
  '[(.B + .C)[] | select(.created_at < $ws)] | length' "$SEL")"
[ "$A1_VIOLATIONS" -eq 0 ] \
  || { echo "[e4e5-confirm] HARD-FAIL: A1 pre-fixation runs in frozen ledger (created_at < window start): $A1_VIOLATIONS" >&2; exit 1; }
echo "[e4e5-confirm] P5 selection: B=$SEL_B C=$SEL_C (matches frozen census; A1 pre-fixation check: pass)"

# --------------------------------------------- P6: extraction (SINGLE PASS)
mkdir -p "$WORK/extr"

ts2epoch() { # ISO8601 (optionally 7-dp) UTC → decimal seconds (§7.2)
  local t="$1" base frac=""
  t="${t%Z}"
  case "$t" in
    *.*) base="${t%.*}"; frac=".${t##*.}" ;;
    *)   base="$t" ;;
  esac
  printf '%s%s\n' "$(date -u -d "${base}Z" +%s)" "$frac"
}

# extract_run <arm> <run_id> <run_attempt> <job_id> → $WORK/extr/<run>_<att>.json
extract_run() {
  local arm="$1" rid="$2" att="$3" job="$4"
  local steps log a_restore n_gc
  if ! steps="$(gh api "repos/$OWNER/$REPO/actions/jobs/$job" \
      --jq '[.steps[] | select(.name | startswith("[check] GO-critical"))
            | {name, number, started_at, completed_at}]' 2>/dev/null)" || [ -z "$steps" ]; then
    jq -cn --arg arm "$arm" --arg rid "$rid" --arg att "$att" --arg job "$job" \
      '{arm: $arm, run_id: ($rid|tonumber), run_attempt: ($att|tonumber), job_id: ($job|tonumber),
        status: "extraction_failed", reason: "job-record-fetch-failed"}' \
      > "$WORK/extr/${rid}_${att}.json"
    return 0
  fi
  log="$WORK/log_${job}.txt"
  if ! gh api --allow-escape-sequences "repos/$OWNER/$REPO/actions/jobs/$job/logs" > "$log" 2>/dev/null \
     || [ ! -s "$log" ]; then
    jq -cn --arg arm "$arm" --arg rid "$rid" --arg att "$att" --arg job "$job" \
      '{arm: $arm, run_id: ($rid|tonumber), run_attempt: ($att|tonumber), job_id: ($job|tonumber),
        status: "extraction_failed",
        reason: "job-log-fetch-failed (§5.4 결측 규칙: excluded + recorded, no imputation)"}' \
      > "$WORK/extr/${rid}_${att}.json"
    return 0
  fi
  sed -E 's/\x1b\[[0-9;]*m//g' "$log" > "$WORK/log_clean.txt"
  # Timestamped log lines only (script-source echoes carry text right after
  # the timestamp and never match this anchor).
  grep -aoE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z' "$WORK/log_clean.txt" \
    > "$WORK/log_ts.txt" || true
  # a-restore stratification marker (§5.2) — same single pass, design variable.
  a_restore="$(grep -aoE '##\[end-action id=__self\.a-restore;[^]]*duration_ms=[0-9]+' "$WORK/log_clean.txt" \
    | sed -E 's/^.*duration_ms=([0-9]+)$/\1/' | head -1 || true)"
  n_gc="$(printf '%s' "$steps" | jq 'length')"
  if [ "$n_gc" -eq 0 ]; then
    jq -cn --arg arm "$arm" --arg rid "$rid" --arg att "$att" --arg job "$job" \
      '{arm: $arm, run_id: ($rid|tonumber), run_attempt: ($att|tonumber), job_id: ($job|tonumber),
        status: "extraction_failed",
        reason: "no [check] GO-critical step in job record (§5.1 definition unmet)"}' \
      > "$WORK/extr/${rid}_${att}.json"
    return 0
  fi
  local api_sum=0 log_sum="" step_details="" sstart send sname snum tmp
  local s_api l_first l_last l_secs
  while IFS=$'\t' read -r sname snum sstart send; do
    s_api=$(( $(ts2epoch "$send" | cut -d. -f1) - $(ts2epoch "$sstart" | cut -d. -f1) ))
    # §7.2 primary: log-line timestamps within the API step window (second-
    # resolution bounds; adjacent-step lines inside a boundary second are
    # bounded ≤ 1 s bracket noise — declared in the evidence file).
    l_first="$(awk -v s="${sstart:0:19}" -v e="${send:0:19}" \
      '$0 >= s && substr($0, 1, 19) <= e {print; exit}' "$WORK/log_ts.txt" | head -1 || true)"
    l_last="$(awk -v s="${sstart:0:19}" -v e="${send:0:19}" \
      '$0 >= s && substr($0, 1, 19) <= e {last=$0} END{if (last != "") print last}' "$WORK/log_ts.txt" | head -1 || true)"
    l_secs="null"
    if [ -n "$l_first" ] && [ -n "$l_last" ]; then
      l_secs="$(awk -v a="$(ts2epoch "$l_first")" -v b="$(ts2epoch "$l_last")" 'BEGIN{printf "%.7f", b - a}')"
    fi
    tmp="$WORK/step_${rid}_${att}_${snum}.json"
    jq -cn --arg name "$sname" --argjson num "$snum" --arg st "$sstart" --arg en "$send" \
      --argjson api "$s_api" --arg lf "${l_first:-}" --arg ll "${l_last:-}" --argjson ls "$l_secs" \
      '{step_name: $name, step_number: $num,
        api: {started_at: $st, completed_at: $en, seconds: $api},
        log: (if $lf == "" then null
              else {first_ts: $lf, last_ts: $ll, seconds: $ls,
                    precision: (if $ls == null then "api-second-fallback (§7.2)"
                                else "log-line-7dp (§7.2 primary)" end)} end)}' \
      > "$tmp"
    step_details="$step_details$(cat "$tmp"),"
    api_sum=$((api_sum + s_api))
    if [ "$l_secs" != "null" ]; then
      log_sum="$(awk -v a="${log_sum:-0}" -v b="$l_secs" 'BEGIN{printf "%.7f", a + b}')"
    fi
  done < <(printf '%s' "$steps" | jq -r '.[] | [.name, (.number|tostring), (.started_at // ""), (.completed_at // "")] | @tsv')
  step_details="${step_details%,}"
  local primary
  if [ -n "$log_sum" ]; then
    primary="log"
  else
    primary="api"
  fi
  jq -cn --arg arm "$arm" --arg rid "$rid" --arg att "$att" --arg job "$job" \
    --argjson steps "[$step_details]" \
    --argjson api_sum "$api_sum" --argjson log_sum "${log_sum:-null}" \
    --arg primary_source "$primary" \
    --arg a_restore "${a_restore:-}" \
    '{arm: $arm, run_id: ($rid|tonumber), run_attempt: ($att|tonumber), job_id: ($job|tonumber),
      status: "extracted",
      go_critical_steps: $steps,
      go_critical_seconds: {api_sum: $api_sum, log_sum: $log_sum,
                            primary: (if $primary_source == "log" then $log_sum else $api_sum end),
                            primary_source: (if $primary_source == "log"
                                             then "log-line-7dp (§7.2 primary)"
                                             else "api-second-fallback (§7.2)" end)},
      a_restore_ms: (if $a_restore == "" then null else ($a_restore|tonumber) end)}' \
    > "$WORK/extr/${rid}_${att}.json"
}

n_total=$((SEL_B + SEL_C))
i=0
while IFS=$'\t' read -r arm rid att job; do
  i=$((i + 1))
  echo "[e4e5-confirm] P6 extraction pass [$i/$n_total]: arm=$arm run=$rid attempt=$att job=$job"
  extract_run "$arm" "$rid" "$att" "$job"
done < <(jq -r '(.B + .C)[] | [.arm, (.run_id|tostring), (.run_attempt|tostring), (.job_id|tostring)] | @tsv' "$SEL")

n_extracted="$(grep -l '"status":"extracted"' "$WORK"/extr/*.json | wc -l | tr -d ' ')"
n_failed=$((n_total - n_extracted))
if [ "$n_failed" -eq 0 ]; then
  echo "[e4e5-confirm] P6 extraction pass complete: $n_extracted/$n_total runs extracted (no exclusions)"
else
  echo "[e4e5-confirm] P6 extraction pass complete: $n_extracted/$n_total extracted, $n_failed excluded+recorded (§5.4 결측 규칙)"
fi

# ------------------------------------------------ P7: evidence file + marker
# Per-run extracts are compact single-line JSON (jq -cn) — concatenation is a
# JSON stream, which is what --slurpfile consumes into one array.
cat "$WORK"/extr/*.json > "$WORK/extr_all.json"
mkdir -p "$EVIDENCE_DIR"
EV_STAMP="$(printf '%s' "$NOW" | sed -E 's/[-:]//g')"
EV_FILE="$EVIDENCE_DIR/confirmatory_extract_${EV_STAMP}.json"
[ -e "$EV_FILE" ] \
  && { echo "[e4e5-confirm] FAIL: evidence file already exists: $EV_FILE — never overwritten (new dated records only)" >&2; exit 1; }
jq -n \
  --arg schema "axiom.e4e5.confirmatory_extract/1" \
  --arg now "$NOW" \
  --arg snap "$SNAPSHOT_ID" \
  --arg content_sha "$content_actual" \
  --arg stop_rule "$STOP_RULE" \
  --argjson fixed_nb "$FIXED_N_B" --argjson fixed_nc "$FIXED_N_C" \
  --argjson obs_nb "$N_B_OBS" --argjson obs_nc "$N_C_OBS" \
  --arg window_end "$WINDOW_END" \
  --argjson sel "$(jq -c '.' "$SEL")" \
  --slurpfile extr "$WORK/extr_all.json" \
  --argjson census "$(jq -c '.census.generation_census' "$MANIFEST")" \
  --arg a1_note "개정 기록 A1: duration-pre-observed (pre-fixation) runs are excluded fail-closed; the collection window opens AT the contract merge instant so the frozen ledger is post-fixation by construction (asserted in P5)." \
  '([$extr[] | select(.status == "extracted")]) as $ok
   | ([$ok[] | select(.arm == "B") | .go_critical_seconds.primary]) as $b_secs
   | ([$ok[] | select(.arm == "C") | .go_critical_seconds.primary]) as $c_secs
   | (if ($b_secs | length) > 0 then ($b_secs | add / length) else null end) as $b_mean
   | (if ($c_secs | length) > 0 then ($c_secs | add / length) else null end) as $c_mean
   | {
      schema: $schema,
      generated_at: $now,
      snapshot: {id: $snap, content_sha256_verified: $content_sha},
      stop_rule: {verdict: $stop_rule,
                  fixed: {n_B: $fixed_nb, n_C: $fixed_nc},
                  observed_observable_duration: {n_B: $obs_nb, n_C: $obs_nc},
                  window_end: $window_end,
                  underpowered: ($stop_rule == "window_close_underpowered"),
                  note: (if $stop_rule == "window_close_underpowered"
                         then "§5.6(b): window closed with n short — underpowered, non-confirmatory; no Tier 2 claim, Tier 1 requires lower bound > 0"
                         else "§5.6(a): fixed n reached — the single confirmatory analysis input" end)},
      generation_census: {B: $census.B, C: $census.C,
        degenerate_labeling: "§5.3 퇴화: any arm with G < 2 is 단일 세대 관측 — reported without generation-generalization claims"},
      a1_pre_fixation_exclusion: $a1_note,
      selection: $sel,
      measurement_note: "§5.1: GO-critical = steps named [check] GO-critical*, multiple matches summed; per-run primary = sum of §7.2 log-line durations (7-dp) bracketed by API step windows, with the API second-resolution sum recorded alongside. Boundary-second bracket noise ≤ 1 s is possible (declared).",
      estimand_note: "§5.1: Δ = μ_B − μ_C over per-run GO-critical seconds. Descriptive means only — the inferential CI is the §5.3 generation-level block bootstrap computed at analysis, out of this extraction tool scope.",
      runs: $extr,
      summary: {
        extracted: ($ok | length),
        extraction_failures: ([$extr[] | select(.status != "extracted")]),
        B: {n: ($b_secs | length), mean_seconds: $b_mean},
        C: {n: ($c_secs | length), mean_seconds: $c_mean}},
      delta_hat_seconds: (if $b_mean != null and $c_mean != null
                          then (($b_mean - $c_mean) * 10000000 | round) / 10000000
                          else null end)
    }' > "$WORK/evidence.json"
# Atomic publication: the evidence file appears complete or not at all.
mv "$WORK/evidence.json" "$EV_FILE"

EV_SHA="$(sha256sum "$EV_FILE" | cut -d' ' -f1)"
OUTCOME="complete"
[ "$n_failed" -eq 0 ] || OUTCOME="complete_with_exclusion_failures"

# Completion marker: append-only write into the manifest (frozen files untouched).
jq --arg at "$NOW" --arg outcome "$OUTCOME" --arg ev "$EV_FILE" --arg ev_sha "$EV_SHA" \
   --arg rule "$STOP_RULE" --argjson extracted "$n_extracted" --argjson excluded "$n_failed" \
   '.confirmatory_extraction.attempts +=
      [{at: $at, outcome: $outcome, stop_rule: $rule,
        evidence_file: $ev, evidence_sha256: $ev_sha,
        extracted_runs: $extracted, excluded_runs: $excluded}]' \
   "$MANIFEST" > "$MANIFEST.tmp"
mv "$MANIFEST.tmp" "$MANIFEST"

echo "[e4e5-confirm] P7 evidence written: $EV_FILE (sha256 ${EV_SHA:0:16}…)"
echo "[e4e5-confirm] P7 completion marker appended to $MANIFEST — this snapshot is now extraction-closed (any further attempt HARD-FAILs)"
jq -r '"[e4e5-confirm] Δ̂ (descriptive): " + (if .delta_hat_seconds == null then "n/a"
        else (((.delta_hat_seconds * 10 | round) / 10 | tostring) + " s") end)
      + " | B mean=" + (if .summary.B.mean_seconds == null then "n/a" else (((.summary.B.mean_seconds * 10 | round) / 10 | tostring) + "s") end)
      + " (n=" + (.summary.B.n|tostring) + ")"
      + " | C mean=" + (if .summary.C.mean_seconds == null then "n/a" else (((.summary.C.mean_seconds * 10 | round) / 10 | tostring) + "s") end)
      + " (n=" + (.summary.C.n|tostring) + ")"' "$EV_FILE"
exit 0
