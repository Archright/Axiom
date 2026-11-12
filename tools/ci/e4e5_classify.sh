#!/usr/bin/env bash
#
# e4e5_classify.sh — E-4/E-5 P/B/M classifier + pre-registered CP gate (GET-only).
#
# Consumes the E-4/E-5 ledger (tools/ci/e4e5_collect.sh → data/e4e5/ledger.json)
# and classifies each eligible key-identification block on the SAME denominator:
# eligible keys = keys merge_group (MG) consumed that needed a seed.
#
#   P  PR necessary      — at MG's FIRST consumption of the key, the covering
#                          seed came only from the PR lane (base-seed had not
#                          yet supplied)
#   B  base-seed coverage— base-seed actually supplied BEFORE that first
#                          consumption
#   M  miss              — neither seeded in time
#
# Pre-registered gate (do NOT change after seeing data):
#   Primary metric: P rate (removal harm). Gate: one-sided 95% Clopper-Pearson
#   UPPER bound ≤ 10%. Minimal case: 0 P-events among n ≥ 29 independent blocks
#   (bound = 1 − 0.05^(1/29) = 9.81%). If P-events ≥ 1: required n from
#   beta.ppf(0.95, k+1, n−k) ≤ 0.10 — if unreachable, reduction is NOT approved.
#   NO Bonferroni: the conjunction "P ≤ 10% ∧ B ≥ 90%" is the identical
#   acceptance region as the B-gate at these thresholds (AND-rule error
#   ≤ min(α) ≤ 5%). B and M bounds are secondary diagnostics only; M is NOT
#   removal-harm evidence and is not a gate.
#
# Validity conditions implemented as audit checks:
#   (a) base-seed producibility is independent of PR lane existence
#       (structural: base-tree keys) — recorded as an assumption, not proven here
#   (b) per-(cache layer, key) attribution — A-layer and B-layer separated
#       (only axiom-b-* keys classified); fallback/prefix matches resolved via
#       the B-restore resolved-key log (matched-key), else excluded as anomalies
#   (c) tie-break: consumption start > save completion ⇒ base supplied it.
#       Save-completion timestamps are rounded UP to the second (outcome lines
#       are late-bound emissions) — conservative: can only shrink B, grow P
#   (d) log-completeness audit — publisher runs with UNKNOWN-seed status or a
#       base_key present with no base-save outcome line are seed-ledger gaps;
#       silent base-save failure would misattribute, so affected findings are
#       caveated (and absence-of-seed findings become UNKNOWN)
#   (e) the fixed-timestamp estimate is a CONSERVATIVE UPPER BOUND on removal
#       risk — removal would delay first consumption, giving base-seed more
#       time — declared in the report
#
# Observation-window rule (pre-registered): t0 = seeding time (block birth =
# first keygen emission; for M territory, first-consumption start); mandatory
# observation through t0 + 135 minutes. Follow-up incomplete or log
# completeness unverified at that point → UNKNOWN (never 0). A verified-
# complete 135-min non-hit is a right-censored observation ("no seed within
# 135 min") — decision-equivalent to "PR necessary at consumption time" for
# lane-safety, so it counts WITH P in the conservative gate input (reported
# separately as well). Permanent 0 is allowed ONLY for closed consumer-set
# verifications (key generation rotated out of scope).
#
# Carryover rule: a key whose first in-window consumption already HITs with no
# in-window seed event ≤ first consumption had its seeding race before the
# window (seeded pre-window) — recorded as carryover_pre_seeded and EXCLUDED
# from the race denominator (it never needed an in-window seed; attribution of
# the pre-window seeder is not observable in-window).
#
# Authority: this tool is a REPORTER over the collected ledger — it emits no
# judgment verdict and changes no gate (AGENTS.md §2.3 Authority ≠ Adapter).
#
# Usage: e4e5_classify.sh [--ledger data/e4e5/ledger.json]
#                         [--out data/e4e5/classification_report.json]
#                         [--now ISO8601]
# Exit codes: 0 = classification produced; 1 = hard failure (missing/corrupt
#             ledger); 2 = usage error.
#
# §5.3 generation census: every report carries, per arm (B/C), the independent
# key-generation count G (normalized keygen triple) next to the observation
# counts, plus the §5.3 퇴화 flag (any arm with G < 2 → 단일 세대 관측).
# Duration-estimand denominators are reported twice: total eligible
# observations and observable-duration observations (REUSED-skip runs —
# admission_tests.reused_skip=true — reported separately, never dropped;
# classification policy lands with the forthcoming amendment).

set -euo pipefail

LEDGER="data/e4e5/ledger.json"
OUT="data/e4e5/classification_report.json"
NOW_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ledger) LEDGER="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    --now)    NOW_OVERRIDE="$2"; shift 2 ;;
    -h|--help) sed -n '2,72p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--ledger FILE] [--out FILE] [--now ISO8601]" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "[e4e5-classify] FAIL: jq not available" >&2; exit 2; }
[ -s "$LEDGER" ] || { echo "[e4e5-classify] FAIL: ledger missing/empty: $LEDGER" >&2; exit 1; }
jq -e . "$LEDGER" >/dev/null 2>&1 || { echo "[e4e5-classify] FAIL: ledger not valid JSON: $LEDGER" >&2; exit 1; }

GENERATED_AT="${NOW_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

mkdir -p "$(dirname "$OUT")"

jq --arg now "$GENERATED_AT" --arg ledger_path "$LEDGER" '
  # ---------- math: binomial CDF + Clopper-Pearson one-sided upper bound ----
  def epoch(ts): (ts | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
    + (if (ts | test("\\.[1-9]")) then 1 else 0 end);   # ceil to second (conservative)
  def binom_cdf(k; n; x):                                # P(X ≤ k), X~Bin(n,x)
    if x <= 0 then 1.0
    elif x >= 1 then (if k >= n then 1.0 else 0.0 end)
    else
      ((1 - x) | pow(.; n)) as $t0
      | if $t0 == 0 then (if k >= n then 1.0 else 0.0 end)
        else
          reduce range(0; k + 1) as $i ({t: $t0, s: 0.0};
            {s: (.s + .t),
             t: (.t * (x / (1 - x)) * ((n - $i) / ($i + 1)))})
          | .s
        end
    end;
  def cp_upper(k; n; alpha):                             # smallest U with F(U) ≤ alpha, monotone
    if n <= 0 then null
    elif k >= n then 1.0
    elif k < 0 then 0.0
    elif k == 0 then 1.0 - pow(alpha; 1 / n)
    else
      reduce range(0; 80) as $_ ({lo: 0.0, hi: 1.0};
        ((.lo + .hi) / 2) as $mid
        | if binom_cdf(k; n; $mid) > alpha
          then {lo: $mid, hi: .hi} else {lo: .lo, hi: $mid} end)
      | .hi
    end;
  def min_n_for(k; target):                              # minimal n with cp_upper ≤ target
    if k < 0 then null
    else
      ([(k + 1), 1] | max) as $start
      | (50 * $start + 500) as $cap
      | if cp_upper(k; $cap; 0.05) > target then null    # unreachable within cap
        else
          reduce range(0; 40) as $_ ({lo: $start, hi: $cap};
            ((.lo + .hi) / 2 | floor) as $mid
            | if $mid <= .lo then .
              elif cp_upper(k; $mid; 0.05) <= target
              then {lo: .lo, hi: $mid}
              else {lo: $mid, hi: .hi} end)
          | .hi
        end
    end;

  # §5.3 generation identity: one keygen emission = one key generation. The
  # mechanical census key is the normalized keygen triple (b_identity,
  # recipe_hash, a_fp) — the contract generation naming of §3.1
  # (`2148f712/090df7f1` = b_identity/recipe prefixes). Runs sharing a
  # triple share a seed lifetime and are NOT independent observations.
  def gen_key:
    {b_identity: .keygen.b_identity,
     recipe_hash: .keygen.recipe_hash,
     a_fp: .keygen.a_fp}
    | to_entries | sort_by(.key) | from_entries | tostring;

  # ---------- inputs --------------------------------------------------------
  . as $L
  | ($L.consumer_observations // []) as $C
  | ($L.seed_observations // []) as $S
  | ($now | fromdateiso8601) as $now_e
  | (135 * 60) as $obs_window

  # ---------- validity (b): per-(layer,key) attribution anomalies -----------
  | [$C[] | select(.b_restore.requested_key != .keygen.b_key)] as $key_mismatches
  | [$C[]
     | select(.b_restore.matched_key != null
              and .b_restore.matched_key != ""
              and .b_restore.matched_key != .b_restore.requested_key)] as $prefix_matches
  | ([$key_mismatches[].run_id] + [$prefix_matches[].run_id]) as $anomaly_run_ids
  | [$C[] | select(.eligibility == "eligible" or .eligibility == "provisional")
     | select(.run_id | IN($anomaly_run_ids[]) | not)] as $E

  # ---------- arms and §5.3 generation census -------------------------------
  # Arm split over the same denominator as the race blocks (eligible,
  # non-anomaly observations). G = independent key-generation count per arm.
  | ([$E[] | select(.carrier_hit)]) as $E_B
  | ([$E[] | select(.carrier_hit | not)]) as $E_C
  | ($E_B | map(gen_key) | unique | length) as $G_B
  | ($E_C | map(gen_key) | unique | length) as $G_C

  # ---------- n_C / n_B definition support (forthcoming amendment) ----------
  # REUSED-run classification policy HOOK — single insertion point.
  # The ledger records admission_tests.reused_skip=true for runs whose every
  # GO-critical subject hit Judgment CAS basis=REUSED (kernel skip ⇒
  # GO-critical step ≈ 0 s). Mechanically such runs carry no observable
  # GO-critical duration, so they are reported OUTSIDE the observable-duration
  # denominator below and NEVER dropped from the operational ledger. Their
  # purpose-based classification (non-observation for the duration estimand vs
  # separate operational performance type) is DEFINED BY THE FORTHCOMING
  # AMENDMENT document; when it lands, only this block changes. Old ledgers
  # (schema /1, no admission_tests field) default to reused_skip=false.
  | ([$E_B[] | select((.admission_tests.reused_skip // false) | not)]) as $E_B_obs
  | ([$E_C[] | select((.admission_tests.reused_skip // false) | not)]) as $E_C_obs

  # ---------- validity (d): seed-ledger gaps --------------------------------
  | [$S[] | select(.status == "UNKNOWN-seed")] as $unknown_seed_runs
  | [$S[] | select(.evidence_kind == "publisher-log"
                   and .status != "UNKNOWN-seed"
                   and .base_key != null
                   and (.base_save.outcome == null))] as $silent_gap_runs
  | (([$unknown_seed_runs[] | .run_id]) + ([$silent_gap_runs[] | .run_id])) as $gap_run_ids
  | [$S[] | select(.run_id | IN($gap_run_ids[])) | .created_at | epoch(.)] as $gap_epochs

  # ---------- seed events per key (conservative ceil-rounded epochs) --------
  | ([$S[] | select(.base_key != null and .base_save.outcome == "saved")
      | {key: .base_key, k: epoch(.base_save.ts), kind: "base-save"}]
    + [$S[] | select(.base_key_exists_skip_key != null
                     and .base_save.outcome == "skipped")
      | {key: .base_key_exists_skip_key, k: epoch(.base_save.ts), kind: "base-exists-proof"}]
    + [$S[] | select(.lane_key != null and .lane_save.outcome == "saved")
      | {key: .lane_key, k: epoch(.lane_save.ts), kind: "lane-save"}]) as $seed_events

  # ---------- key-identification blocks (b_identity+recipe+a_fp triples) ----
  | [$C[] | {b_identity: .keygen.b_identity,
             recipe_hash: .keygen.recipe_hash,
             a_fp: .keygen.a_fp} | to_entries | sort_by(.key) | from_entries] as $triple_norm
  | ($triple_norm | unique) as $triples

  # ---------- block classification ------------------------------------------
  | ([ $E[].keygen.b_key ] | unique) as $keys
  | [ $keys[] as $k
      | [$E[] | select(.keygen.b_key == $k)] as $obs
      | ([$obs[].job_started_at] | min) as $t_c_iso
      | (epoch($t_c_iso)) as $t_c
      | ([$obs[] | select(.job_started_at == $t_c_iso)] | sort_by(.run_id))[0] as $first
      | ([$obs[].keygen.ts] | min) as $t_birth_iso
      | (epoch($t_birth_iso)) as $t_birth
      | ($seed_events | map(select(.key == $k))) as $sev
      | ($sev | map(select(.k <= $t_c))) as $sev_before
      | ($sev | map(select(.kind == "base-save" or .kind == "base-exists-proof"))) as $base_ev
      | ($sev | map(select(.kind == "lane-save"))) as $lane_ev
      | ($base_ev | map(select(.k <= $t_c))) as $base_before
      | ($lane_ev | map(select(.k <= $t_c))) as $lane_before
      | ($base_ev | map(select(.k > $t_c))) as $base_after
      | ($sev | length) as $n_seed_ev
      | ($obs | map(.run_id) | unique) as $run_ids
      | ([$obs[].run_id] | length) as $n_obs
      | (any($gap_epochs[]; . >= $t_birth and . <= $now_e)) as $gap_caveat
      | (if $first.b_restore.exact_hit then
           if ($base_before | length) > 0 then
             {category: "B",
             basis: "base-side seed event at-or-before first consumption start (tie-break c)"}
           elif ($lane_before | length) > 0 then
             {category: "P",
              basis: "lane-save at-or-before first consumption start; no base-side event (tie-break c)"}
           else
             {category: "CARRYOVER_PRE_SEEDED",
              basis: "first in-window consumption HITs with no in-window seed event ≤ it — seeding race happened before the window"}
           end
         else
           if ($sev_before | length) > 0 then
             {category: "UNKNOWN",
              reason: "restore-mismatch-anomaly",
              basis: "seed event existed at-or-before first consumption but B-restore exact-hit=false (cache VERSION/path mismatch class — resolved-key log shows miss)"}
           else
             ($t_c + $obs_window) as $deadline
             | if $now_e < $deadline then
                 {category: "PENDING_OBSERVATION",
                  basis: "135-min mandatory observation not complete (135 min from first-consumption start)"}
               elif (($base_after | map(select(.k <= $deadline)) | length) > 0) then
                 {category: "M_BOUNDED",
                  basis: "no seed at first consumption; base-side seed arrived within the 135-min window (bounded-delay diagnostic)"}
               elif $gap_caveat then
                 {category: "UNKNOWN",
                  reason: "seed-ledger-gap",
                  basis: "verified non-hit through 135 min but a publisher run in-window has no extractable seed ledger (log fetch failed or silent outcome absence)"}
               else
                 {category: "M_RIGHT_CENSORED",
                  basis: "verified-complete 135-min non-hit (right-censored) — decision-equivalent to PR necessary for lane-safety"}
               end
           end
         end) as $verdict
      | ([$obs[] | select(.carrier_hit) | .run_id] | unique) as $hit_runs
      | ([$obs[] | select(.carrier_hit | not) | .run_id] | unique) as $miss_runs
      | {key: $k,
         b_identity: $first.keygen.b_identity,
         recipe_hash: $first.keygen.recipe_hash,
         a_fp: $first.keygen.a_fp,
         run_ids: $run_ids,
         n_observations: $n_obs,
         first_consumption: {run_id: $first.run_id, run_attempt: $first.run_attempt,
                             job_started_at: $t_c_iso,
                             exact_hit: $first.b_restore.exact_hit,
                             matched_key: $first.b_restore.matched_key},
         t_birth: $t_birth_iso,
         seed_events_in_window: $sev,
         hit_run_ids: $hit_runs, miss_run_ids: $miss_runs,
         seed_ledger_gap_caveat: $gap_caveat,
         category: $verdict.category,
         reason: ($verdict.reason // null),
         basis: $verdict.basis,
         delay_minutes: (if $verdict.category == "M_BOUNDED"
                         then (([$base_ev[] | select(.k > $t_c) | .k] | min) - $t_c) / 60
                         else null end)}
    ] as $blocks

  # ---------- denominators and counts ---------------------------------------
  | ([$blocks[] | select(.category == "B"
                        or .category == "P"
                        or .category == "M_BOUNDED"
                        or .category == "M_RIGHT_CENSORED")]) as $race_blocks
  | ($race_blocks | length) as $n_race
  | ([$blocks[] | select(.category == "P")] | length) as $k_p
  | ([$blocks[] | select(.category == "M_RIGHT_CENSORED")] | length) as $k_censored
  | ($k_p + $k_censored) as $k_lane_safety
  | ([$blocks[] | select(.category == "B")] | length) as $k_b
  | ([$blocks[] | select(.category == "M_BOUNDED")] | length) as $k_m_bounded
  | ([$blocks[] | select(.category == "CARRYOVER_PRE_SEEDED")] | length) as $k_carryover
  | ([$blocks[] | select(.category == "PENDING_OBSERVATION"
                        or .category == "UNKNOWN")] | length) as $k_unknown
  | ($E_C | length) as $n_C
  | ($E_B | length) as $n_B
  | 0.10 as $limit
  | cp_upper($k_lane_safety; $n_race; 0.05) as $u_cons
  | cp_upper($k_p; $n_race; 0.05) as $u_strict
  | min_n_for($k_lane_safety; $limit) as $required_n
  | (if $n_race == 0 then "IN COLLECTION — no race-eligible blocks yet (window open; underpowered)"
     elif $required_n == null then "NOT APPROVED — required n unreachable for observed P-events (pre-registered formula)"
     elif $u_cons == null then "UNKNOWN — bound not computable"
     elif $u_cons <= $limit then
       (if $n_race < $required_n
        then "IN COLLECTION / UNDERPOWERED — bound \(((($u_cons * 1000) | round) / 10))% ≤ 10% at current n but n < required_n (window open)"
        else "PASSED — one-sided 95% CP upper bound ≤ 10% at required n"
        end)
     else "IN COLLECTION / UNDERPOWERED — bound \(((($u_cons * 1000) | round) / 10))% > 10% at current n (window open)"
     end) as $gate_verdict

  # ---------- report ---------------------------------------------------------
  | {
      schema: "axiom.e4e5.classification/2",
      generated_at: $now,
      ledger: {collected_at: $L.collected_at,
               window: $L.window,
               path: $ledger_path},
      reused_run_policy_hook: "admission_tests.reused_skip=true runs are RECORDED in the ledger and excluded only mechanically from the observable-duration denominators (no GO-critical duration exists to observe — kernel skip). Purpose-based classification is defined by the forthcoming contract amendment; insertion point: the E_B_obs/E_C_obs block in tools/ci/e4e5_classify.sh.",
      metric_definitions: {
        denominator: "eligible keys = keys MG consumed that needed a seed (in-window race blocks; carryover pre-seeded keys excluded and reported separately)",
        P: "at MG first consumption the covering seed came only from the PR lane",
        B: "base-seed supplied before MG first consumption (tie-break: consumption start > save completion)",
        M: "neither seeded in time (M_BOUNDED = base arrived within 135 min; M_RIGHT_CENSORED = verified-complete 135-min non-hit)"},
      validity_conditions: {
        a: {status: "ASSUMPTION",
            statement: "base-seed producibility is independent of PR lane existence — structural: base keys derive from the base tree (keygen reads base tree, contract §3.1); not proven by this tool"},
        b: {status: "ENFORCED",
            statement: "per-(cache layer, key) attribution — A-layer (axiom-a-*) lines are never classified; only axiom-b-* keys; prefix/fallback resolved via B-restore matched-key, mismatches excluded as anomalies",
            key_mismatch_observations: ($key_mismatches | length),
            prefix_match_observations: ($prefix_matches | length)},
        c: {status: "ENFORCED",
            statement: "consumption start > save completion ⇒ base supplied it; save completions are outcome-line emissions rounded UP to the second (conservative — can only shrink B, grow P)"},
        d: {status: "AUDITED",
            statement: "log-completeness: publisher runs with UNKNOWN-seed status or absent base-save outcome line are seed-ledger gaps; absence-of-seed findings under gaps are UNKNOWN (never 0)",
            gap_run_ids: $gap_run_ids},
        e: {status: "DECLARED",
            statement: "the fixed-timestamp estimate is a CONSERVATIVE UPPER BOUND on removal risk: removing the PR lane would delay first consumption, giving base-seed more time — measured P overcounts realized harm"}},
      observation_window_rule: "t0 = seeding time (block birth = first keygen emission; for miss territory, first-consumption start); mandatory observation through t0+135 min; incomplete follow-up or unverified completeness → UNKNOWN (never 0); verified-complete 135-min non-hit = right-censored, decision-equivalent to PR necessary for lane-safety; permanent 0 only for closed consumer-set verifications",
      gate_pre_registered: {
        primary_metric: "P rate (removal harm)",
        rule: "one-sided 95% Clopper-Pearson UPPER bound ≤ 10%",
        minimal_case: "0 P-events among n ≥ 29 independent blocks (bound = 1 − 0.05^(1/29) = 9.81%)",
        p_events_ge_1: "required n from beta.ppf(0.95, k+1, n−k) ≤ 0.10; unreachable ⇒ reduction NOT approved",
        bonferroni: "NONE — conjunction P≤10% ∧ B≥90% is the identical acceptance region as the B-gate at these thresholds (AND-rule error ≤ min(α) ≤ 5%); B and M are secondary diagnostics; M is NOT removal-harm evidence and is NOT a gate",
        no_post_hoc_changes: true},
      counts: {
        key_identification_blocks_observed: ($triples | length),
        independent_generation_blocks: ($blocks | length),
        race_denominator_n: $n_race,
        B: $k_b, P: $k_p,
        M_bounded: $k_m_bounded, M_right_censored: $k_censored,
        lane_safety_P_equivalent: $k_lane_safety,
        carryover_pre_seeded: $k_carryover,
        pending_or_unknown: $k_unknown,
        n_C_eligible_miss_observations: $n_C,
        n_B_eligible_hit_observations: $n_B,
        n_B_total_eligible_observations: ($E_B | length),
        n_C_total_eligible_observations: ($E_C | length),
        n_B_observable_duration: ($E_B_obs | length),
        n_C_observable_duration: ($E_C_obs | length),
        n_B_reused_skips: (($E_B | length) - ($E_B_obs | length)),
        n_C_reused_skips: (($E_C | length) - ($E_C_obs | length)),
        generation_census: {
          definition: "G = independent key-generation count per arm (§5.3): runs sharing a normalized keygen triple (b_identity, recipe_hash, a_fp) share a seed lifetime and are not independent; inference uses generation-level block bootstrap, never run-level independence",
          B: {n_observations: ($E_B | length),
              n_runs: ($E_B | map(.run_id) | unique | length),
              G: $G_B,
              single_generation_observation: ($G_B < 2)},
          C: {n_observations: ($E_C | length),
              n_runs: ($E_C | map(.run_id) | unique | length),
              G: $G_C,
              single_generation_observation: ($G_C < 2)},
          degenerate_rule: "§5.3 퇴화: any arm with G < 2 is labeled 단일 세대 관측 (single-generation observation) and reported without generation-generalization claims",
          any_arm_degenerate: (($G_B < 2) or ($G_C < 2))},
        unknown_key_observations_in_ledger: ($L.unknown_key_observations // [] | length)},
      cp_gate: {
        k_p_strict: $k_p,
        k_lane_safety_conservative: $k_lane_safety,
        n: $n_race,
        upper_bound_strict_P: $u_strict,
        upper_bound_lane_safety: $u_cons,
        bound_limit: $limit,
        required_n_for_observed_k: $required_n,
        verdict: $gate_verdict},
      secondary_diagnostics: {
        B_upper_bound_95: (if $n_race > 0 then cp_upper($k_b; $n_race; 0.05) else null end),
        M_total: ($k_m_bounded + $k_censored),
        M_upper_bound_95: (if $n_race > 0 then cp_upper($k_m_bounded + $k_censored; $n_race; 0.05) else null end),
        note: "diagnostics only — B∧P conjunction needs no Bonferroni (identical acceptance region); M is not removal-harm evidence"},
      blocks: $blocks
    }
' "$LEDGER" > "$OUT.tmp"

mv "$OUT.tmp" "$OUT"

# ---- console summary (reporter output only — no judgment verdict) -----------
jq -r '"[e4e5-classify] blocks=\(.counts.independent_generation_blocks) race_n=\(.counts.race_denominator_n) B=\(.counts.B) P=\(.counts.P) M_b=\(.counts.M_bounded) M_rc=\(.counts.M_right_censored) carryover=\(.counts.carryover_pre_seeded) pending/unknown=\(.counts.pending_or_unknown) | n_C=\(.counts.n_C_eligible_miss_observations) n_B=\(.counts.n_B_eligible_hit_observations)"' "$OUT"
jq -r '"[e4e5-classify] generations (§5.3): G_B=\(.counts.generation_census.B.G) (n_B=\(.counts.generation_census.B.n_observations), runs=\(.counts.generation_census.B.n_runs)) G_C=\(.counts.generation_census.C.G) (n_C=\(.counts.generation_census.C.n_observations), runs=\(.counts.generation_census.C.n_runs)) | degenerate(B<2∨C<2)=\(.counts.generation_census.any_arm_degenerate)"' "$OUT"
jq -r '"[e4e5-classify] duration-estimand denominators: n_B total=\(.counts.n_B_total_eligible_observations) observable=\(.counts.n_B_observable_duration) reused_skips=\(.counts.n_B_reused_skips) | n_C total=\(.counts.n_C_total_eligible_observations) observable=\(.counts.n_C_observable_duration) reused_skips=\(.counts.n_C_reused_skips)"' "$OUT"
jq -r '"[e4e5-classify] CP gate: k_lane_safety=\(.cp_gate.k_lane_safety_conservative) n=\(.cp_gate.n) U=\(.cp_gate.upper_bound_lane_safety // "n/a") limit=\(.cp_gate.bound_limit) required_n=\(.cp_gate.required_n_for_observed_k // "n/a") → \(.cp_gate.verdict)"' "$OUT"
[ "$(jq '.counts.pending_or_unknown' "$OUT")" -gt 0 ] && jq -r '.blocks[] | select(.category == "PENDING_OBSERVATION" or .category == "UNKNOWN" or .category == "CARRYOVER_PRE_SEEDED") | "[e4e5-classify]   block \(.b_identity[0:12])/\(.recipe_hash[0:12]) runs=\(.run_ids | join(",")) → \(.category)\(if .reason then " (\(.reason))" else "" end): \(.basis)"' "$OUT" || true
echo "[e4e5-classify] report → $OUT"
exit 0
