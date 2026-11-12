#!/usr/bin/env bash
# =============================================================================
# go_critical_acceptance_assert.sh — GO-critical merge-group lane ACCEPTANCE
# ASSERTION harness (auditable "green"; fail-closed).
#
# PURPOSE
#   A green `admission-gate` merge_group run is admissible evidence ONLY when
#   the GO-critical admission-contract tests (DEBT#432, the 2-lane
#   `go-critical-lane` job matrix in .github/workflows/admission-check.yml)
#   were freshly EXECUTED and PASSED in that run. GitHub's own surfaces do not
#   guarantee this: a run whose lane skipped its test via the judgment-CAS
#   reuse path reports conclusion=success with a `PASS — 0/0` lane summary
#   (measured: run 39374256331 — `AXIOM_JUDGMENT_CAS: REUSED`, zero kernel
#   runs, run-level conclusion success). This harness makes "green" auditable
#   by asserting, from the run's own bytes, that the lane executed. It is an
#   ACCEPTANCE layer over the run record — it does not re-run anything and it
#   is not a merge authority (Authority ≠ Adapter,
#   docs/agents/merge_admission_observation.md); the merge-admission authority
#   stays GitHub's ruleset/required checks.
#
# MEASURED SEMANTICS (sources: the workflow file + real run logs, 2026-10-20)
#   * Log markers are emitted by .github/workflows/admission-check.yml
#     (go-critical-lane job) and src/verification/judgment_cas.nim
#     (planLogLine — the single wire-text source):
#       plan      : "AXIOM_JUDGMENT_CAS: EXECUTED — <reason>"  (fresh execution)
#                   "AXIOM_JUDGMENT_CAS: REUSED — record <12hex> re-verified (...)"
#                   "AXIOM_JUDGMENT_CAS: OFF — unarmed (...)"
#       per-test  : "[admission-tests] RUN make test-fast-one T=<path>"
#                   "[admission-tests] PASS — <path> (basis=EXECUTED ...)"
#                   "[admission-tests] SKIP — <path> (AXIOM_JUDGMENT_CAS basis=REUSED ...)"
#                   "[admission-tests] FAIL — <path> (make test-fast-one non-zero)"
#       lane      : "[admission-tests] PASS — N/N GO-critical admission tests green"
#       nimtest   : "[OK] evidenceId = H(6 components) ..." / "[OK] splice resistance ..."
#                   "[FAILED] <check name>" (a failing check inside the suite)
#     lane-0 = tests/unit/test_s1a_lean_golden.nim SOLO → a green executed lane
#     is exactly "PASS — 1/1". "PASS — 0/0" is the REUSED-skip signature.
#   * SKIPPED-JOB SEMANTICS (cited): a job whose `if:` evaluates false is
#     skipped and its check-run conclusion is "skipped", but the WORKFLOW RUN
#     conclusion aggregates to "success" — a skipped lane must therefore be
#     detected explicitly, never inferred from the run conclusion.
#       https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/using-conditions-to-control-job-execution
#       https://docs.github.com/en/rest/actions/runs#list-jobs-for-a-workflow-run
#     In the logs-zip layout a skipped job has NO log file at all (measured:
#     `verdict / go-critical-lane` / `anchor-resolve` produce no entry), so
#     "lane-0 log absent" IS the skipped/absent job in offline mode.
#   * MERGE_GROUP SHA (cited): on the merge_group event GITHUB_SHA is the
#     "SHA of the merge group" — the queue merge commit G that gets tested
#     and lands; run.head_sha == merge_group.head_sha == G. The admission
#     identity B (base) is the queue-branch suffix / merge_group.base_sha.
#       https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows#merge_group
#       https://docs.github.com/en/rest/actions/check-runs#list-check-runs-for-a-git-reference
#   * ANSI EVASION TRAP: GitHub logs echo every executed shell source line
#     wrapped in `ESC[36;1m ... ESC[0m`. The workflow SOURCE therefore
#     contains every marker literal (`SKIP —`, `PASS —`, `basis=REUSED`...).
#     This harness matches ONLY output lines: lines carrying ANSI escapes are
#     excluded before any pattern match (self-test fixture `ansi-evasion`
#     pins this).
#
# ASSERTIONS (fail-closed — any FAIL ⇒ exit 1)
#   A1 lane-0 log (output lines only) contains ALL of:
#      "AXIOM_JUDGMENT_CAS: EXECUTED", "[admission-tests] RUN make test-fast-one",
#      "PASS — 1/1 GO-critical admission tests green",
#      "[OK] evidenceId", "[OK] splice resistance"
#   A2 lane-0 log contains NONE of:
#      "PASS — 0/0", "[admission-tests] SKIP —", "basis=REUSED",
#      "AXIOM_JUDGMENT_CAS: REUSED", "[FAILED]", "[admission-tests] FAIL —"
#   A3 job conclusion + M identity:
#      lane-0 job conclusion == success (skipped/cancelled/failure ⇒ FAIL,
#      explicitly diagnosed for skipped), and for --run-id additionally:
#      run.event == merge_group, run.head_sha == expected M, exactly one
#      `attest / go-critical-lane (0)` job, lane-1/rollup/attest
#      admission-check all success, exactly one `admission-check` check-run
#      at commits/<M> with status=completed, conclusion=success,
#      head_sha==<M>, and --pr (when given) matching the queue branch.
#   A4 CAS decision/evidence artifacts (go-judgment-lane-0-<M>-<attempt> etc.):
#      decision.basis == "EXECUTED"; decision.evidenceKey 64-hex;
#      decision.probeTreeOid 40-hex; evidence.verdict == "KERNEL_ACCEPT_ALL"
#      (the measured s1a pass verdict, schema axiom.judgment.cas.v2);
#      candidate (tested landing) tree OID present 40-hex via the
#      tested-tree-digest artifact and — run-id mode — equal to tree(<M>)
#      from the commits API; overlay manifest digest present and 64-hex —
#      REQUIRED, resolved from EITHER admissible source, in order of
#      authority:
#        (1) the CAS payload itself (decision/evidence/record JSON) — the
#            field does not exist in axiom.judgment.cas.v2 yet, so it lands
#            only when the overlay-manifest schema lands;
#        (2) the lane's EXECUTION RECORD go-exec-records/s1a.json (schema
#            axiom.judgment.cas.execution.v2: subject s1a, verdict PASS,
#            basis EXECUTED, identities.overlayManifestDigest 64-hex,
#            identities.executorTreeOid and identities.candidateTreeOid
#            40-hex) TOGETHER WITH the attest admission-check log line
#            "[go-exec] exec record[s1a] OK — verdict=PASS basis=EXECUTED"
#            — the attest job recomputes the per-subject overlay digest
#            from M and the lane's own overlay inputs and compares it with
#            the record, so the harness never trusts the artifact alone.
#      A present-but-malformed field (either source) is a FAIL; absent from
#      BOTH sources is a FAIL naming both (missing evidence is never a
#      pass).
#   A5 B and M identities recorded in the lane-0 log and distinct:
#      B from "MANIFEST VERIFIED: verifier is built from B=<40hex>", M from
#      the go-judgment-lane-0-<40hex>-<attempt> artifact-name lines; both
#      present, B != M, M == expected M; --run-id additionally cross-checks
#      B against the queue-branch suffix pr-<n>-<40hex>.
#
# USAGE
#   go_critical_acceptance_assert.sh --run-id <id> --expected-m-sha <sha> \
#       [--pr <n>] [--repo <owner/repo>] [--logs-dir <dir>]
#       Query the live run (gh): metadata, jobs, logs zip, check-runs at M,
#       CAS artifacts. --logs-dir is optional: extract the run's logs +
#       artifacts there (default: a temp dir) for reuse/inspection.
#   go_critical_acceptance_assert.sh --logs-dir <dir> --expected-m-sha <sha> \
#       [--pr <n>] [--repo <owner/repo>]
#       Offline mode over a previously fetched logs tree (the unzip of
#       `gh api repos/<repo>/actions/runs/<id>/logs`: flat
#       "<NN>_attest _ go-critical-lane (0).txt" files) plus, for A4, the
#       CAS artifact files placed in the dir (judgment-decision.json,
#       judgment-evidence.json, tested-tree-digest and — when the CAS
#       payload predates the overlay field — the lane execution record
#       go-exec-records/s1a.json; download e.g.
#       `gh run download <id> -n go-judgment-lane-0-<M>-<attempt> -D <dir>`
#       and `gh run download <id> -n tested-tree-digest -D <dir>`).
#       Optional <dir>/run-metadata.json ({"event":...,"head_sha":...,
#       "head_branch":...}) is validated when present.
#   go_critical_acceptance_assert.sh --self-test
#       Deterministic fixture suite (synthetic logs, NO network): pass,
#       PASS 0/0, REUSED skip, skipped job, M mismatch, ANSI evasion,
#       missing-overlay-field (neither source), exec-record fallback,
#       tampered exec-record digest, missing attest line.
#
#   exit codes: 0 = all assertions PASS · 1 = assertion FAIL (or a required
#   observation cannot be made — fail-closed) · 2 = usage/input error.
#
# DEPENDENCIES: bash, gh (authenticated, repo scope; --run-id mode), jq,
# unzip, coreutils. Deterministic: LC_ALL=C, sorted discovery, fixed fixture
# content, no clock or network input in --self-test.
# =============================================================================

set -euo pipefail
export LC_ALL=C

EX_OK=0
EX_FAIL=1
EX_USAGE=2

MODE=""            # run-id | logs-dir | self-test
RUN_ID=""
LOGS_DIR=""
PR_NUMBER=""
EXPECTED_M=""
REPO="Archright/Axiom"

FAILS=0
TMPDIR_RUN=""
SELFTEST_ROOT=""
SELFTEST_FAILURES=0

# ── A4 overlay-digest evidence contract ─────────────────────────────────────
# The overlay manifest digest is REQUIRED by A4. It is admissible from two
# sources, in order of authority:
#   (1) the CAS payload itself (the overlay field is absent from
#       axiom.judgment.cas.v2 today and lands with the overlay schema);
#   (2) the lane's EXECUTION RECORD (go-exec-records/s1a.json) together
#       with the attest job's recomputation attestation — the attest job
#       recomputes the per-subject overlay digest from M and the lane's own
#       overlay inputs and compares it with the record, so the harness never
#       trusts the artifact alone.
OVERLAY_FIELD_NAMES="overlayManifestDigest overlay_manifest_digest"
EXEC_RECORD_REL="go-exec-records/s1a.json"
EXEC_RECORD_SCHEMA="axiom.judgment.cas.execution.v2"
ATTEST_EXEC_LINE="[go-exec] exec record[s1a] OK — verdict=PASS basis=EXECUTED"

die_usage() {
    printf 'usage error: %s\n' "$*" >&2
    exit "$EX_USAGE"
}

usage_text() {
    cat <<'EOF'
tools/ci/go_critical_acceptance_assert.sh — GO-critical merge-group lane acceptance assertion harness

  --run-id <id>          admission-gate merge_group run id to audit (network via gh)
  --logs-dir <dir>       offline logs directory (unzip of the run logs API) — also used as the
                         extraction target when combined with --run-id
  --expected-m-sha <sha> the expected merge-group candidate commit SHA (M) — required outside --self-test
  --pr <n>               PR number provenance cross-check (queue branch pr-<n>-<B>)
  --repo <owner/repo>    repository (default: Archright/Axiom)
  --self-test            deterministic fixture suite (no network)

exit: 0 pass · 1 fail · 2 usage
EOF
}

record_fail() {
    # diagnostics go to STDERR: assertion functions are captured via command
    # substitution (find_single returns a path on stdout) — stdout must stay
    # data-clean; the final ACCEPTANCE verdict line is the only stdout report
    printf 'FAIL: %s\n' "$*" >&2
    FAILS=$((FAILS + 1))
}

record_ok() {
    printf 'OK:   %s\n' "$*" >&2
}

is_sha40() {
    printf '%s' "$1" | grep -Eq '^[0-9a-f]{40}$'
}

is_hex64() {
    printf '%s' "$1" | grep -Eq '^[0-9a-f]{64}$'
}

# jq reader: prints the filter's result, or "" when the file is unreadable
# or the field is absent (absent evidence is never an implicit pass).
json_get() {
    local out
    out="$(jq -r "$2" "$1" 2>/dev/null)" || { printf ''; return 0; }
    printf '%s' "$out"
}

# ── log evidence extraction ──────────────────────────────────────────────────
# GitHub's runner logs each executed shell source line wrapped in ANSI
# `ESC[36;1m ... ESC[0m`; every marker literal also appears inside that
# source echo. Evidence = lines WITHOUT ANSI escapes (deleted), BOM-stripped,
# timestamp prefix removed, residual ANSI sequences stripped defensively.
normalize_log() {
    local file="$1"
    LC_ALL=C sed -e 's/^\xEF\xBB\xBF//' -e $'/\x1b\\[/d' "$file" \
        | LC_ALL=C sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?Z[[:space:]]//' \
        | LC_ALL=C sed -E $'s/\x1b\\[[0-9;]*[A-Za-z]//g'
}

# exactly-one discovery; sets the output VARIABLE named by $1 to the single
# path (or "" after recording a FAIL) and returns non-zero on failure. Runs
# in the caller's shell (record_fail's FAILS increment must survive — a
# command substitution would discard it in a subshell).
#   $1 = output var name, $2 = dir, $3 = name glob, $4 = label, $5 = absence hint.
find_single() {
    local __out="$1" dir="$2" pattern="$3" label="$4" hint="${5:-}" hits n
    hits="$(find "$dir" -maxdepth 2 -type f -name "$pattern" | LC_ALL=C sort || printf '')"
    if [ -z "$hits" ]; then
        if [ -n "$label" ]; then
            record_fail "$label: no file matching '$pattern' under $dir${hint:+ — }$hint"
        fi
        printf -v "$__out" '%s' ""
        return 1
    fi
    n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    if [ "$n" -gt 1 ]; then
        if [ -n "$label" ]; then
            record_fail "$label: ambiguous — $n files match '$pattern' under $dir (exactly-one contract): $(printf '%s' "$hits" | tr '\n' ' ')"
        fi
        printf -v "$__out" '%s' ""
        return 1
    fi
    printf -v "$__out" '%s' "$hits"
    return 0
}

# ── A1/A2: lane-0 log marker assertions ─────────────────────────────────────
assert_lane_markers() {
    local lane_log="$1"
    local evidence marker
    evidence="$(normalize_log "$lane_log")"

    for marker in \
        "AXIOM_JUDGMENT_CAS: EXECUTED" \
        "[admission-tests] RUN make test-fast-one T=" \
        "[OK] evidenceId" \
        "[OK] splice resistance"; do
        if printf '%s\n' "$evidence" | grep -F -- "$marker" >/dev/null; then
            record_ok "A1 lane-0 log contains: $marker"
        else
            record_fail "A1 lane-0 log missing required marker: $marker"
        fi
    done

    for marker in \
        "PASS — 0/0" \
        "[admission-tests] SKIP —" \
        "basis=REUSED" \
        "AXIOM_JUDGMENT_CAS: REUSED" \
        "[FAILED]" \
        "[admission-tests] FAIL —"; do
        if printf '%s\n' "$evidence" | grep -F -- "$marker" >/dev/null; then
            record_fail "A2 lane-0 log contains forbidden marker: $marker"
        else
            record_ok "A2 lane-0 log free of: $marker"
        fi
    done
    # The lane summary wording changed across generations. Accept either the
    # historical literal or the current "EXECUTED <n>/<n>, REUSED(skip) 0"
    # form; A2 still rejects zero-execution / REUSED outcomes.
    if printf '%s\n' "$evidence" | grep -E -- 'PASS — (1/1 GO-critical admission tests green|EXECUTED 1/1, REUSED\(skip\) 0)' >/dev/null; then
        record_ok "A1 lane-0 log contains: executed 1/1 summary"
    else
        record_fail "A1 lane-0 log missing required marker: executed 1/1 summary (old or current wording)"
    fi
}

# ── A5: B / M identity recorded and distinct (from the lane-0 log) ──────────
assert_lane_identity() {
    local lane_log="$1"
    local evidence b_sha m_sha branch_b
    evidence="$(normalize_log "$lane_log")"

    b_sha="$(printf '%s\n' "$evidence" \
        | grep -m1 -oE 'MANIFEST VERIFIED: verifier is built from B=[0-9a-f]{40}' \
        | grep -oE '[0-9a-f]{40}$' || printf '')"
    m_sha="$(printf '%s\n' "$evidence" \
        | grep -m1 -oE 'go-judgment-lane-0-[0-9a-f]{40}-[0-9]+' \
        | sed -E 's/^go-judgment-lane-0-([0-9a-f]{40})-[0-9]+$/\1/' || printf '')"

    if [ -n "$b_sha" ] && is_sha40 "$b_sha"; then
        record_ok "A5 base identity B recorded in lane-0 log: $b_sha"
    else
        record_fail "A5 base identity B not recorded in lane-0 log (expected 'MANIFEST VERIFIED: verifier is built from B=<40hex>')"
    fi
    if [ -n "$m_sha" ] && is_sha40 "$m_sha"; then
        record_ok "A5 candidate identity M recorded in lane-0 log: $m_sha"
    else
        record_fail "A5 candidate identity M not recorded in lane-0 log (expected go-judgment-lane-0-<40hex>-<attempt> artifact-name lines)"
    fi

    if [ -n "$b_sha" ] && is_sha40 "$b_sha" && [ -n "$m_sha" ] && is_sha40 "$m_sha"; then
        if [ "$b_sha" != "$m_sha" ]; then
            record_ok "A5 B and M identities are distinct (B=$b_sha M=$m_sha)"
        else
            record_fail "A5 B and M identities are identical ($b_sha) — the lane executes on the BASE tree against a distinct merge-group candidate"
        fi
    fi
    if [ -n "$m_sha" ] && is_sha40 "$m_sha" && [ -n "$EXPECTED_M" ] && [ "$m_sha" != "$EXPECTED_M" ]; then
        record_fail "A5 lane-0 log records M=$m_sha but expected M=$EXPECTED_M (identity binding broken)"
    fi

    # optional run-metadata head_branch: gh-readonly-queue/main/pr-<n>-<B>
    if [ -f "$LOGS_DIR/run-metadata.json" ]; then
        branch_b="$(jq -r '(.head_branch // "") | capture("pr-[0-9]+-(?<b>[0-9a-f]{40})$") | .b // empty' \
            "$LOGS_DIR/run-metadata.json" 2>/dev/null)" || branch_b=""
        if [ -n "$branch_b" ] && [ -n "$b_sha" ] && [ "$branch_b" != "$b_sha" ]; then
            record_fail "A5 queue-branch base B=$branch_b != lane-log B=$b_sha"
        elif [ -n "$branch_b" ]; then
            record_ok "A5 queue-branch base matches lane-log B ($branch_b)"
        fi
    fi
}

# ── A4: CAS decision/evidence artifacts ─────────────────────────────────────
# Outcome via record_fail/record_ok; returns 0 always (fail-closed findings
# accumulate in FAILS). CANDIDATE_TREE_OBSERVED is set for the run-id
# tree(M) cross-check.
CANDIDATE_TREE_OBSERVED=""
assert_cas_artifacts() {
    local attest_log="$1"
    local dec ev ttd basis ekey ptree verdict schema
    CANDIDATE_TREE_OBSERVED=""

    find_single dec "$LOGS_DIR" 'judgment-decision.json' 'A4 CAS decision file' 'download the go-judgment-lane-0-<M>-<attempt> artifact into the logs dir' || dec=""
    find_single ev "$LOGS_DIR" 'judgment-evidence.json' 'A4 CAS evidence file' 'download the go-judgment-lane-0-<M>-<attempt> artifact into the logs dir' || ev=""
    find_single ttd "$LOGS_DIR" 'testedTreeDigest' '' '' || ttd=""
    if [ -z "$ttd" ]; then
        # artifact-name spelling fallback (gh run download uses the dashed form)
        find_single ttd "$LOGS_DIR" 'tested-tree-digest' '' '' || ttd=""
    fi
    if [ -z "$ttd" ]; then
        record_fail "A4 tested-tree-digest artifact: neither 'testedTreeDigest' nor 'tested-tree-digest' found under $LOGS_DIR — download the tested-tree-digest artifact into the logs dir (candidate tree OID absent = FAIL, never pass)"
    fi

    if [ -z "$dec" ] || [ -z "$ev" ]; then
        record_fail "A4 CAS decision/evidence artifacts not found under $LOGS_DIR (fail-closed: no artifact, no acceptance)"
        return 0
    fi

    basis="$(jq -r '(.basis // "")' "$dec" 2>/dev/null)" || basis=""
    ekey="$(jq -r '(.evidenceKey // "")' "$dec" 2>/dev/null)" || ekey=""
    ptree="$(jq -r '(.probeTreeOid // "")' "$dec" 2>/dev/null)" || ptree=""
    verdict="$(jq -r '(.verdict // "")' "$ev" 2>/dev/null)" || verdict=""
    schema="$(jq -r '(.schemaVersion // "")' "$ev" 2>/dev/null)" || schema=""

    if [ "$basis" = "EXECUTED" ]; then
        record_ok "A4 decision basis=EXECUTED"
    else
        record_fail "A4 decision basis='$basis' != EXECUTED"
    fi
    if is_hex64 "$ekey"; then
        record_ok "A4 decision evidenceKey present (64-hex)"
    else
        record_fail "A4 decision evidenceKey missing/malformed: '$ekey'"
    fi
    if is_sha40 "$ptree"; then
        record_ok "A4 decision probeTreeOid present (tested-tree anchor, 40-hex)"
    else
        record_fail "A4 decision probeTreeOid missing/malformed: '$ptree' (a present tree OID is required — missing fields are FAIL, never pass)"
    fi

    # Measured s1a pass verdict (judgment-evidence.json): the green executed
    # lane writes verdict == "KERNEL_ACCEPT_ALL". Anything else fails closed.
    if [ "$verdict" = "KERNEL_ACCEPT_ALL" ]; then
        record_ok "A4 evidence verdict=KERNEL_ACCEPT_ALL (schema ${schema:-unknown})"
    else
        record_fail "A4 evidence verdict='$verdict' != KERNEL_ACCEPT_ALL (missing fields are FAIL, never pass)"
    fi

    # Candidate (tested landing) tree OID: the tested-tree-digest artifact.
    if [ -n "$ttd" ]; then
        local ttd_val
        ttd_val="$(tr -d '[:space:]' < "$ttd")"
        if is_sha40 "$ttd_val"; then
            record_ok "A4 candidate tree OID present in tested-tree-digest: $ttd_val"
            CANDIDATE_TREE_OBSERVED="$ttd_val"
        else
            record_fail "A4 tested-tree-digest content malformed: '$ttd_val'"
        fi
    else
        record_fail "A4 candidate tree OID absent (no tested-tree-digest artifact under $LOGS_DIR)"
    fi

    # Overlay manifest digest — REQUIRED (fail-closed); resolved by
    # assert_overlay_digest from the CAS payload or the lane execution
    # record + its attest attestation.
    assert_overlay_digest "$dec" "$ev" "$attest_log"
    return 0
}

# first non-empty value of a known overlay spelling (top level, then
# identities) — prints "" when the field is absent.
cas_overlay_value() {
    local f="$1" fld val
    for fld in $OVERLAY_FIELD_NAMES; do
        val="$(jq -r --arg k "$fld" '.[$k] // empty' "$f" 2>/dev/null)" || val=""
        [ -n "$val" ] && { printf '%s' "$val"; return 0; }
        val="$(jq -r --arg k "$fld" '.identities[$k] // empty' "$f" 2>/dev/null)" || val=""
        [ -n "$val" ] && { printf '%s' "$val"; return 0; }
    done
    return 0
}

# ── A4: overlay manifest digest — two admissible sources (fail-closed) ─────
# Source 1 — the CAS payload (decision/evidence/record JSON): the field
#   lands with the overlay-manifest schema; a present field must be 64-hex.
# Source 2 — the lane execution record go-exec-records/s1a.json PLUS the
#   attest job's recomputation attestation: the attest job recomputes the
#   per-subject overlay digest from M and the lane's own overlay inputs and
#   compares it with the record, so the artifact is never trusted alone.
# $1 = judgment-decision.json path, $2 = judgment-evidence.json path,
# $3 = attest admission-check log path ("" when absent).
OVERLAY_SOURCE=""
OVERLAY_VALUE=""
assert_overlay_digest() {
    local dec="$1" ev="$2" attest_log="$3"
    local f val hits n rec
    local schema subject verdict basis digest exec_tree cand_tree
    local evidence recomputed

    OVERLAY_SOURCE=""
    OVERLAY_VALUE=""

    # ── source 1: the CAS payload ────────────────────────────────────────
    for f in "$dec" "$ev" "$(find "$LOGS_DIR" -maxdepth 2 -type f -name 'judgment-record.json' | LC_ALL=C sort | sed -n '1p')"; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        val="$(cas_overlay_value "$f")"
        [ -n "$val" ] || continue
        if is_hex64 "$val"; then
            OVERLAY_SOURCE="cas-payload"
            OVERLAY_VALUE="$val"
            record_ok "A4 overlay manifest digest present in the CAS payload ($(basename "$f"), 64-hex)"
        else
            record_fail "A4 overlay manifest digest malformed in the CAS payload ($(basename "$f")): '$val' — a present field must be 64-hex (missing fields are FAIL, never pass)"
        fi
        return 0
    done

    # ── source 2: the lane execution record ──────────────────────────────
    hits="$(find "$LOGS_DIR" -maxdepth 3 -type f -path "*/$EXEC_RECORD_REL" | LC_ALL=C sort || printf '')"
    if [ -z "$hits" ]; then
        record_fail "A4 overlay manifest digest absent from BOTH sources — the CAS payload carries no overlay field (schema axiom.judgment.cas.v2 predates it) AND the lane execution record ($EXEC_RECORD_REL) is missing under $LOGS_DIR — missing evidence is FAIL, never pass"
        return 0
    fi
    n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    if [ "$n" -ne 1 ]; then
        record_fail "A4 lane execution record ambiguous — $n files match '$EXEC_RECORD_REL' under $LOGS_DIR (exactly-one contract)"
        return 0
    fi
    rec="$hits"
    schema="$(json_get "$rec" '.schemaVersion // ""')"
    subject="$(json_get "$rec" '.subject // ""')"
    verdict="$(json_get "$rec" '.verdict // ""')"
    basis="$(json_get "$rec" '.basis // ""')"
    digest="$(json_get "$rec" '.identities.overlayManifestDigest // ""')"
    exec_tree="$(json_get "$rec" '.identities.executorTreeOid // ""')"
    cand_tree="$(json_get "$rec" '.identities.candidateTreeOid // ""')"

    if [ "$schema" = "$EXEC_RECORD_SCHEMA" ]; then
        record_ok "A4 execution record schemaVersion=$EXEC_RECORD_SCHEMA"
    else
        record_fail "A4 execution record schemaVersion='$schema' != $EXEC_RECORD_SCHEMA"
    fi
    if [ "$subject" = "s1a" ]; then
        record_ok "A4 execution record subject=s1a"
    else
        record_fail "A4 execution record subject='$subject' != s1a"
    fi
    if [ "$verdict" = "PASS" ]; then
        record_ok "A4 execution record verdict=PASS"
    else
        record_fail "A4 execution record verdict='$verdict' != PASS"
    fi
    if [ "$basis" = "EXECUTED" ]; then
        record_ok "A4 execution record basis=EXECUTED"
    else
        record_fail "A4 execution record basis='$basis' != EXECUTED"
    fi
    if is_hex64 "$digest"; then
        record_ok "A4 execution record identities.overlayManifestDigest present (64-hex)"
    else
        record_fail "A4 execution record identities.overlayManifestDigest missing/malformed: '$digest'"
    fi
    if is_sha40 "$exec_tree"; then
        record_ok "A4 execution record identities.executorTreeOid present (40-hex)"
    else
        record_fail "A4 execution record identities.executorTreeOid missing/malformed: '$exec_tree'"
    fi
    if is_sha40 "$cand_tree"; then
        record_ok "A4 execution record identities.candidateTreeOid present (40-hex)"
    else
        record_fail "A4 execution record identities.candidateTreeOid missing/malformed: '$cand_tree'"
    fi

    # the attestation — the attest job recomputed the digest from M and the
    # lane's own overlay inputs and compared it with the record.
    if [ -z "$attest_log" ] || [ ! -f "$attest_log" ]; then
        record_fail "A4 attest admission-check log absent — the execution record's overlay digest cannot be attested by the trusted executor (fail-closed)"
        return 0
    fi
    evidence="$(normalize_log "$attest_log")"
    if printf '%s\n' "$evidence" | grep -F -- "$ATTEST_EXEC_LINE" >/dev/null; then
        record_ok "A4 attest log attests the recomputed overlay digest: $ATTEST_EXEC_LINE"
    else
        record_fail "A4 attest log lacks '$ATTEST_EXEC_LINE' — the lane execution record's overlay digest was not recomputed and matched by the trusted executor (fail-closed)"
        return 0
    fi

    # corroboration — when the attest log also prints the digest it
    # recomputed, it must equal the record's digest.
    recomputed="$(printf '%s\n' "$evidence" | grep -F 'overlay' | grep -oE 's1a=[0-9a-f]{64}' | head -n 1 | sed -E 's/^s1a=//' || printf '')"
    if [ -z "$recomputed" ]; then
        recomputed="$(printf '%s\n' "$evidence" | grep -F 'overlay' | grep -oE 'lane0=[0-9a-f]{64}' | head -n 1 | sed -E 's/^lane0=//' || printf '')"
    fi
    if [ -n "$recomputed" ]; then
        if [ "$recomputed" = "$digest" ]; then
            record_ok "A4 execution-record overlay digest == the digest recomputed by the attest job ($digest)"
        else
            record_fail "A4 execution-record overlay digest $digest != the digest recomputed by the attest job $recomputed (overlay identity broken)"
            return 0
        fi
    fi

    OVERLAY_SOURCE="execution-record"
    OVERLAY_VALUE="$digest"
    return 0
}

# run-id only: the candidate tree OID must equal tree(<M>) from the commits API
assert_candidate_tree_matches_m() {
    local m="$1" api_tree
    if [ -z "$CANDIDATE_TREE_OBSERVED" ]; then
        return 0
    fi
    api_tree="$(gh api "repos/$REPO/commits/$m" --jq '.commit.tree.sha' 2>/dev/null)" || api_tree=""
    if [ -z "$api_tree" ]; then
        record_fail "A4 tree(<M>) query failed for $m — candidate-tree identity unverifiable (fail-closed)"
    elif [ "$api_tree" = "$CANDIDATE_TREE_OBSERVED" ]; then
        record_ok "A4 tested-tree-digest == tree(M) == $api_tree (candidate identity bound)"
    else
        record_fail "A4 tested-tree-digest $CANDIDATE_TREE_OBSERVED != tree(M) $api_tree (candidate tree identity broken)"
    fi
    return 0
}

# ── A3: job conclusion + check-run identity (run-id mode) ───────────────────
assert_job_conclusions() {
    local jobs_json="$1" lane0 concl
    lane0="$(printf '%s' "$jobs_json" | jq -r '[.jobs[] | select(.name == "attest / go-critical-lane (0)") | .conclusion] | if length == 0 then "ABSENT" elif length == 1 then .[0] else "MULTIPLE" end')"
    case "$lane0" in
        success)
            record_ok "A3 lane-0 job conclusion=success"
            ;;
        skipped)
            record_fail "A3 lane-0 job conclusion=skipped — GitHub reports skipped jobs as success at the WORKFLOW-RUN level; a skipped lane is never green (docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/using-conditions-to-control-job-execution)"
            ;;
        ABSENT)
            record_fail "A3 no 'attest / go-critical-lane (0)' job in run $RUN_ID (fail-closed)"
            ;;
        MULTIPLE)
            record_fail "A3 multiple 'attest / go-critical-lane (0)' jobs in run $RUN_ID (exactly-one contract)"
            ;;
        *)
            record_fail "A3 lane-0 job conclusion=$lane0 (!= success)"
            ;;
    esac

    for concl in "attest / go-critical-lane (1)" "attest / go-critical-rollup" "attest / admission-check"; do
        local got
        got="$(printf '%s' "$jobs_json" | jq -r --arg n "$concl" '[.jobs[] | select(.name == $n) | .conclusion] | if length == 0 then "ABSENT" elif length == 1 then .[0] else "MULTIPLE" end')"
        if [ "$got" = "success" ]; then
            record_ok "A3 '$concl' conclusion=success"
        else
            record_fail "A3 '$concl' conclusion=$got (the GO-critical landing lane group requires every member success — skipped is never green)"
        fi
    done
    return 0
}

assert_checkrun_at_m() {
    local m="$1" cr row status conclusion cr_head
    if ! cr="$(gh api "repos/$REPO/commits/$m/check-runs?per_page=100" 2>/dev/null)"; then
        record_fail "A3 check-runs query at commits/$m failed (network/gh) — fail-closed"
        return 0
    fi
    row="$(printf '%s' "$cr" | jq -r '[.check_runs[] | select(.name == "admission-check")] | if length == 0 then "ABSENT" elif length == 1 then (.[0].status + "|" + (.[0].conclusion // "") + "|" + .[0].head_sha) else "MULTIPLE" end')"
    case "$row" in
        ABSENT)
            record_fail "A3 no 'admission-check' check-run at commits/$m — a required check that is absent is UNKNOWN/NOT READY, never success"
            ;;
        MULTIPLE)
            record_fail "A3 multiple 'admission-check' check-runs at commits/$m (exactly-one contract)"
            ;;
        "completed|success|$m")
            record_ok "A3 admission-check check-run at M: completed/success, head_sha==M"
            ;;
        *)
            status="${row%%|*}"
            row="${row#*|}"
            conclusion="${row%%|*}"
            cr_head="${row#*|}"
            if [ "$conclusion" != "success" ]; then
                record_fail "A3 admission-check check-run at commits/$m: status=$status conclusion=$conclusion (!= success)"
            else
                record_fail "A3 admission-check check-run head_sha=$cr_head != M=$m"
            fi
            ;;
    esac
    return 0
}

# ── mode: --run-id ───────────────────────────────────────────────────────────
run_mode_run_id() {
    local run_json jobs_json attempt event head_sha head_branch
    if ! run_json="$(gh api "repos/$REPO/actions/runs/$RUN_ID" 2>/dev/null)"; then
        record_fail "run $RUN_ID not readable via gh api (repo=$REPO) — fail-closed"
        return 0
    fi
    event="$(printf '%s' "$run_json" | jq -r '.event')"
    head_sha="$(printf '%s' "$run_json" | jq -r '.head_sha')"
    head_branch="$(printf '%s' "$run_json" | jq -r '.head_branch')"
    attempt="$(printf '%s' "$run_json" | jq -r '.run_attempt')"

    if [ "$event" = "merge_group" ]; then
        record_ok "A3 run event=merge_group"
    else
        record_fail "A3 run event='$event' != merge_group (this harness asserts the merge-group landing lane only)"
    fi
    if [ "$head_sha" = "$EXPECTED_M" ]; then
        record_ok "A3 run.head_sha == expected M ($EXPECTED_M)"
    else
        record_fail "A3 run.head_sha=$head_sha != expected M=$EXPECTED_M"
    fi
    if [ -n "$PR_NUMBER" ]; then
        if printf '%s' "$head_branch" | grep -E "pr-${PR_NUMBER}-[0-9a-f]{40}$" >/dev/null; then
            record_ok "A3 queue branch '$head_branch' matches --pr $PR_NUMBER"
        else
            record_fail "A3 queue branch '$head_branch' does not carry pr-$PR_NUMBER-<B> (PR/run binding broken)"
        fi
    fi

    if ! jobs_json="$(gh api "repos/$REPO/actions/runs/$RUN_ID/jobs?per_page=100" 2>/dev/null)"; then
        record_fail "jobs query for run $RUN_ID failed — fail-closed"
        return 0
    fi
    assert_job_conclusions "$jobs_json"
    assert_checkrun_at_m "$EXPECTED_M"

    # logs + CAS artifacts → LOGS_DIR
    mkdir -p "$LOGS_DIR"
    if printf '%s\n' "$run_json" | jq '{event, head_sha, head_branch, run_attempt, conclusion}' > "$LOGS_DIR/run-metadata.json"; then
        record_ok "run metadata written to $LOGS_DIR/run-metadata.json"
    else
        record_fail "run metadata write failed ($LOGS_DIR/run-metadata.json)"
    fi

    local logs_zip="$LOGS_DIR/logs-$RUN_ID.zip"
    if gh api "repos/$REPO/actions/runs/$RUN_ID/logs" > "$logs_zip" 2>/dev/null && unzip -q -o "$logs_zip" -d "$LOGS_DIR"; then
        record_ok "logs zip extracted into $LOGS_DIR"
        rm -f "$logs_zip"
    else
        record_fail "logs download/extraction failed for run $RUN_ID — fail-closed"
        return 0
    fi

    local art_list art_id art_name
    art_list="$(gh api "repos/$REPO/actions/runs/$RUN_ID/artifacts?per_page=100" 2>/dev/null)" || art_list=""
    for art_name in "go-judgment-lane-0-$EXPECTED_M-$attempt" "tested-tree-digest" "judgment-record-$EXPECTED_M-$attempt"; do
        art_id=""
        if [ -n "$art_list" ]; then
            art_id="$(printf '%s' "$art_list" | jq -r --arg n "$art_name" '[.artifacts[] | select(.name == $n) | .id] | first // empty' 2>/dev/null)" || art_id=""
        fi
        if [ -n "$art_id" ]; then
            if gh api "repos/$REPO/actions/artifacts/$art_id/zip" > "$LOGS_DIR/.art-$art_id.zip" 2>/dev/null \
               && unzip -q -o "$LOGS_DIR/.art-$art_id.zip" -d "$LOGS_DIR"; then
                record_ok "artifact '$art_name' extracted into $LOGS_DIR"
                rm -f "$LOGS_DIR/.art-$art_id.zip"
            else
                record_fail "artifact '$art_name' (id $art_id) download/extraction failed — fail-closed"
            fi
        else
            record_fail "artifact '$art_name' not found on run $RUN_ID — fail-closed (A4 needs the CAS artifacts)"
        fi
    done
    return 0
}

# ── offline identity checks (logs-dir mode; also consumes run-metadata) ─────
run_offline_identity_checks() {
    if [ -f "$LOGS_DIR/run-metadata.json" ]; then
        local event head_sha
        event="$(jq -r '(.event // "")' "$LOGS_DIR/run-metadata.json" 2>/dev/null)" || event=""
        head_sha="$(jq -r '(.head_sha // "")' "$LOGS_DIR/run-metadata.json" 2>/dev/null)" || head_sha=""
        if [ "$event" = "merge_group" ]; then
            record_ok "A3 run-metadata event=merge_group"
        else
            record_fail "A3 run-metadata event='$event' != merge_group"
        fi
        if [ "$head_sha" = "$EXPECTED_M" ]; then
            record_ok "A3 run-metadata head_sha == expected M"
        else
            record_fail "A3 run-metadata head_sha=$head_sha != expected M=$EXPECTED_M"
        fi
    else
        record_ok "A3 run-metadata.json absent — the M binding is enforced via the lane-log identity (A5) in offline mode"
    fi
    return 0
}

# ── shared assertion driver ──────────────────────────────────────────────────
drive_assertions() {
    local lane_log attest_log
    find_single lane_log "$LOGS_DIR" '*attest _ go-critical-lane (0).txt' 'A1 lane-0 job log' 'on the landing venue an absent lane log IS a skipped/absent job — GitHub reports skipped as success at the run level; detected explicitly here' || lane_log=""
    if [ -n "$lane_log" ]; then
        record_ok "lane-0 job log located: $(basename "$lane_log")"
        assert_lane_markers "$lane_log"
        assert_lane_identity "$lane_log"
    fi
    find_single attest_log "$LOGS_DIR" '*attest _ admission-check.txt' 'attest admission-check job log' 'the landing identity line (ADM_IDENTITY/mergeTree) cannot be observed without it' || attest_log=""
    if [ -z "$attest_log" ]; then
        record_fail "attest admission-check job log absent — the admission identity line (ADM_IDENTITY/mergeTree) cannot be observed (fail-closed)"
    else
        if normalize_log "$attest_log" | grep -F 'ADM_IDENTITY: OK' >/dev/null; then
            record_ok "attest admission-check log carries the ADM_IDENTITY: OK identity line"
        else
            record_fail "attest admission-check log lacks 'ADM_IDENTITY: OK' — landing identity re-derivation not observed"
        fi
    fi
    assert_cas_artifacts "$attest_log"
    if [ "$MODE" = "run-id" ]; then
        assert_candidate_tree_matches_m "$EXPECTED_M"
    fi
    return 0
}

# ── self-test fixtures (synthetic, deterministic, no network) ────────────────
fx_ts() {
    printf '2026-10-20T00:00:00.0000000Z %s\n' "$*"
}

fx_src() {
    printf '2026-10-20T00:00:00.0000000Z \x1b[36;1m%s\x1b[0m\n' "$*"
}

B_FIX="049f57ccdc4cd2cbc068bf4405a4c78112f54bb7"
B_TREE_FIX="7086b9bcbe72aaa4c5a563f3008d27089d27b16b"
M_FIX="1cd8bfafe7d5fc32935fced1d98235e8409d2f50"
M_TREE_FIX="1512194c2e032f957629d2d46365b40b72ef2ef3"
M_OTHER_FIX="8487124133a2e6f2d994824d2693e1ad687b754f"
PR_FIX="965"
# the lane's per-subject overlay manifest digest (64-hex) and a tampered
# twin of it (same length, different value)
EXEC_OVERLAY_FIX="f26006599aad3f5b0e2c1d4f6a8b0c2d4e6f8a0b2c4d6e8f0a2b4c6d8e0f2a4b"
EXEC_OVERLAY_TAMPERED_FIX="f26006599aad3f5b0e2c1d4f6a8b0c2d4e6f8a0b2c4d6e8f0a2b4c6d8e0f2a4c"

make_fixture() {
    local d="$SELFTEST_ROOT/$1"
    mkdir -p "$d"
    printf '%s' "$d"
}

write_lane_log_green() {
    local file="$1" b="$2" m="$3"
    {
        fx_src 'echo "[admission-tests] SKIP — $t (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)"'
        fx_src 'echo "[admission-tests] PASS — 0/0 GO-critical admission tests green"'
        fx_ts "Complete job name: attest / go-critical-lane (0)"
        fx_ts "  ref: $b"
        fx_ts "MANIFEST VERIFIED: verifier is built from B=$b"
        fx_ts "AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)"
        fx_ts "[test-supply] restored build/nimcache/test entries=0 (J3 supply — acceleration only)"
        fx_ts "[admission-tests] RUN make test-fast-one T=tests/unit/test_s1a_lean_golden.nim"
        fx_ts "  [OK] genuine Lean 4.33 kernel ACCEPTS the generated theorem"
        fx_ts "  [OK] evidenceId = H(6 components) and identity components are distinct spaces"
        fx_ts "  [OK] splice resistance — cross-assembled genuine evidence is rejected"
        fx_ts "[admission-tests] LANE lane=0 test_s1a_lean_golden duration_ms=265263 — tests/unit/test_s1a_lean_golden.nim"
        fx_ts "[admission-tests] PASS — tests/unit/test_s1a_lean_golden.nim (basis=EXECUTED — fresh judgment measured)"
        fx_ts "[admission-tests] PASS — 1/1 GO-critical admission tests green (lane=0: tests/unit/test_s1a_lean_golden.nim)"
        fx_ts "Artifact go-judgment-lane-0-$m-1 has been successfully uploaded!"
        fx_ts "   name: go-judgment-lane-0-$m-1"
    } > "$file"
}

write_lane_log_reused() {
    local file="$1" b="$2" m="$3"
    {
        fx_ts "MANIFEST VERIFIED: verifier is built from B=$b"
        fx_ts "AXIOM_JUDGMENT_CAS: REUSED — record 301c8f488931 re-verified (closure re-derivation + executionEpoch + per-read re-hash all passed)"
        fx_ts "[admission-tests] SKIP — tests/unit/test_s1a_lean_golden.nim (AXIOM_JUDGMENT_CAS basis=REUSED — record re-verified, no kernel run this attempt)"
        fx_ts "[admission-tests] PASS — 0/0 GO-critical admission tests green (lane=0: tests/unit/test_s1a_lean_golden.nim)"
        fx_ts "Artifact go-judgment-lane-0-$m-1 has been successfully uploaded!"
        fx_ts "   name: go-judgment-lane-0-$m-1"
    } > "$file"
}

write_attest_log() {
    # $4 = "1" → emit the exec-record attestation line; $5 = the digest the
    # attest job recomputed ("" → the recomputation is not printed).
    local file="$1" b="$2" mtree="$3" attest_exec="${4:-}" recomputed="${5:-}"
    {
        fx_ts "MANIFEST VERIFIED: verifier is built from B=$b"
        fx_ts "ADM_IDENTITY: OK — PR #0 head==H base==B ref==main tree $mtree mergeTree $mtree subject 5aa8d9aa20be5e0ea7670beff524de094f371109 candidateTree $mtree"
        if [ -n "$attest_exec" ]; then
            fx_ts "[go-exec] exec record[s1a] OK — verdict=PASS basis=EXECUTED decision=EXECUTED"
        fi
        if [ -n "$recomputed" ]; then
            fx_ts "[go-exec] tested tree = M^{tree} $mtree (overlay digests — s1a=$recomputed proof_integrity=$recomputed d2_golden=$recomputed d2_persist=$recomputed — exported for the armed attest closure)"
        fi
    } > "$file"
}

write_exec_record() {
    # $1 = dir, $2 = subject, $3 = overlay digest, $4 = schema, $5 = verdict,
    # $6 = basis, $7 = executor tree, $8 = candidate tree
    local dir="$1" subject="$2" digest="$3" schema="$4" verdict="$5" basis="$6" exec_tree="$7" cand_tree="$8"
    mkdir -p "$dir/go-exec-records"
    printf '{"schemaVersion":"%s","subject":"%s","verdict":"%s","basis":"%s","evidenceKey":"c15f38cab0dbc089e5b28b70183566039ebeaf21ea5d439f04652ff4cbf99270","identities":{"schemaVersion":"%s","executorTreeOid":"%s","candidateTreeOid":"%s","overlayManifestDigest":"%s"}}\n' \
        "$schema" "$subject" "$verdict" "$basis" "$schema" "$exec_tree" "$cand_tree" "$digest" \
        > "$dir/go-exec-records/$subject.json"
}

write_cas_artifacts() {
    local dir="$1" btree="$2" mtree="$3" with_overlay="$4" overlay_json=""
    if [ "$with_overlay" = "1" ]; then
        overlay_json=', "overlayManifestDigest": "a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90"'
    fi
    printf '{"basis":"EXECUTED","evidenceKey":"c15f38cab0dbc089e5b28b70183566039ebeaf21ea5d439f04652ff4cbf99270","probeTreeOid":"%s","reason":"fresh judgment"}\n' "$btree" \
        > "$dir/judgment-decision.json"
    printf '{"schemaVersion":"axiom.judgment.cas.v2","verdict":"KERNEL_ACCEPT_ALL","kernelAcceptCount":17,"probeCount":14,"executionEpoch":"a77c0c6db87494e8ebfd3d98385425cfd4330fc8db039d97204133d58e44d801"%s}\n' "$overlay_json" \
        > "$dir/judgment-evidence.json"
    printf '%s\n' "$mtree" > "$dir/tested-tree-digest"
}

write_run_metadata() {
    local dir="$1" m="$2" b="$3" pr="$4"
    printf '{"event":"merge_group","head_sha":"%s","head_branch":"gh-readonly-queue/main/pr-%s-%s","run_attempt":1,"conclusion":"success"}\n' "$m" "$pr" "$b" \
        > "$dir/run-metadata.json"
}

# offline assertion run against a fixture dir; prints the harness exit via $?
run_assertions_offline() {
    local dir="$1" m="$2" rc=0
    local saved_dir="$LOGS_DIR" saved_m="$EXPECTED_M" saved_fails=0
    LOGS_DIR="$dir"
    EXPECTED_M="$m"
    FAILS=0
    drive_assertions
    run_offline_identity_checks
    if [ "$FAILS" -ne 0 ]; then
        rc=1
    fi
    LOGS_DIR="$saved_dir"
    EXPECTED_M="$saved_m"
    FAILS=0
    return "$rc"
}

expect_exit() {
    local label="$1" want="$2" got="$3"
    if [ "$want" = "$got" ]; then
        printf 'self-test: PASS  %-38s (exit %s as expected)\n' "$label" "$got"
    else
        printf 'self-test: FAIL  %-38s (expected exit %s, got %s)\n' "$label" "$want" "$got"
        SELFTEST_FAILURES=$((SELFTEST_FAILURES + 1))
    fi
}

fixture_pass() {
    local d rc=0
    d="$(make_fixture pass)"
    write_lane_log_green "$d/17_attest _ go-critical-lane (0).txt" "$B_FIX" "$M_FIX"
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 1
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "pass (EXECUTED green, schema landed)" 0 "$rc"
}

fixture_pass00() {
    local d rc=0
    d="$(make_fixture pass00)"
    write_lane_log_reused "$d/17_attest _ go-critical-lane (0).txt" "$B_FIX" "$M_FIX"
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 1
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "PASS 0/0 rejected" 1 "$rc"
}

fixture_reused() {
    local d rc=0
    d="$(make_fixture reused)"
    write_lane_log_reused "$d/17_attest _ go-critical-lane (0).txt" "$B_FIX" "$M_FIX"
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 1
    printf '{"basis":"REUSED","evidenceKey":"c15f38cab0dbc089e5b28b70183566039ebeaf21ea5d439f04652ff4cbf99270","probeTreeOid":"%s","rootRecord":{"evidenceKey":"301c8f4889310000000000000000000000000000000000000000000000000000","payloadSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","executionEpoch":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}\n' "$B_TREE_FIX" \
        > "$d/judgment-decision.json"
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "REUSED skip rejected" 1 "$rc"
}

fixture_skipped() {
    local d rc=0
    d="$(make_fixture skipped)"
    # lane-0 log ABSENT (the measured logs-zip shape of a skipped job) while
    # the run-level conclusion reads success — the false green to reject.
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 1
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "skipped job (run success) rejected" 1 "$rc"
}

fixture_m_mismatch() {
    local d rc=0
    d="$(make_fixture m-mismatch)"
    write_lane_log_green "$d/17_attest _ go-critical-lane (0).txt" "$B_FIX" "$M_FIX"
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 1
    write_run_metadata "$d" "$M_OTHER_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "M mismatch rejected" 1 "$rc"
}

fixture_ansi_evasion() {
    local d rc=0
    d="$(make_fixture ansi-evasion)"
    # every marker lives ONLY inside ANSI source-echo lines (the runner
    # echoing the workflow source) — output-line matching must NOT be fooled
    {
        fx_src 'echo "AXIOM_JUDGMENT_CAS: EXECUTED — no record for the current closure (fresh judgment)"'
        fx_src 'echo "[admission-tests] RUN make test-fast-one T=tests/unit/test_s1a_lean_golden.nim"'
        fx_src 'echo "[admission-tests] PASS — 1/1 GO-critical admission tests green"'
        fx_src 'echo "  [OK] evidenceId = H(6 components)"'
        fx_src 'echo "  [OK] splice resistance"'
        fx_ts "MANIFEST VERIFIED: verifier is built from B=$B_FIX"
        fx_ts "Artifact go-judgment-lane-0-$M_FIX-1 has been successfully uploaded!"
        fx_ts "   name: go-judgment-lane-0-$M_FIX-1"
    } > "$d/17_attest _ go-critical-lane (0).txt"
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 1
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "ANSI source-echo evasion rejected" 1 "$rc"
}

fixture_overlay_missing() {
    local d rc=0
    d="$(make_fixture overlay-missing)"
    write_lane_log_green "$d/17_attest _ go-critical-lane (0).txt" "$B_FIX" "$M_FIX"
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 0
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "missing overlay field (both sources) rejected" 1 "$rc"
}

fixture_exec_record() {
    local d rc=0
    d="$(make_fixture exec-record-fallback)"
    write_lane_log_green "$d/17_attest _ go-critical-lane (0).txt" "$B_FIX" "$M_FIX"
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX" 1 "$EXEC_OVERLAY_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 0
    write_exec_record "$d" s1a "$EXEC_OVERLAY_FIX" "axiom.judgment.cas.execution.v2" PASS EXECUTED "$B_TREE_FIX" "$M_TREE_FIX"
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "exec-record overlay evidence accepted" 0 "$rc"
}

fixture_exec_record_tampered() {
    local d rc=0
    d="$(make_fixture exec-record-tampered)"
    write_lane_log_green "$d/17_attest _ go-critical-lane (0).txt" "$B_FIX" "$M_FIX"
    # the attest job recomputed the TRUE digest; the artifact's digest was
    # tampered afterwards → the harness must reject the mismatch
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX" 1 "$EXEC_OVERLAY_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 0
    write_exec_record "$d" s1a "$EXEC_OVERLAY_TAMPERED_FIX" "axiom.judgment.cas.execution.v2" PASS EXECUTED "$B_TREE_FIX" "$M_TREE_FIX"
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "tampered exec-record digest rejected" 1 "$rc"
}

fixture_exec_record_no_attest() {
    local d rc=0
    d="$(make_fixture exec-record-no-attest)"
    write_lane_log_green "$d/17_attest _ go-critical-lane (0).txt" "$B_FIX" "$M_FIX"
    # the execution record alone is not evidence — the attest job's
    # recomputation attestation is missing
    write_attest_log "$d/10_attest _ admission-check.txt" "$B_FIX" "$M_TREE_FIX"
    write_cas_artifacts "$d" "$B_TREE_FIX" "$M_TREE_FIX" 0
    write_exec_record "$d" s1a "$EXEC_OVERLAY_FIX" "axiom.judgment.cas.execution.v2" PASS EXECUTED "$B_TREE_FIX" "$M_TREE_FIX"
    write_run_metadata "$d" "$M_FIX" "$B_FIX" "$PR_FIX"
    run_assertions_offline "$d" "$M_FIX" || rc=$?
    expect_exit "exec record without attest line rejected" 1 "$rc"
}

run_self_test() {
    SELFTEST_FAILURES=0
    SELFTEST_ROOT="$(mktemp -d)"
    trap 'rm -rf "$SELFTEST_ROOT"' EXIT
    printf 'self-test: fixtures in %s (synthetic logs, no network)\n' "$SELFTEST_ROOT"
    fixture_pass
    fixture_pass00
    fixture_reused
    fixture_skipped
    fixture_m_mismatch
    fixture_ansi_evasion
    fixture_overlay_missing
    fixture_exec_record
    fixture_exec_record_tampered
    fixture_exec_record_no_attest
    if [ "$SELFTEST_FAILURES" -eq 0 ]; then
        printf 'self-test: ALL FIXTURES PASS\n'
        return 0
    fi
    printf 'self-test: %s fixture(s) FAILED\n' "$SELFTEST_FAILURES"
    return 1
}

# ── argument parsing ─────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --run-id)         [ $# -ge 2 ] || die_usage "--run-id needs a value"; RUN_ID="$2"; MODE="run-id"; shift 2 ;;
        --logs-dir)       [ $# -ge 2 ] || die_usage "--logs-dir needs a value"; LOGS_DIR="$2"; if [ -z "$MODE" ]; then MODE="logs-dir"; fi; shift 2 ;;
        --pr)             [ $# -ge 2 ] || die_usage "--pr needs a value"; PR_NUMBER="$2"; shift 2 ;;
        --expected-m-sha) [ $# -ge 2 ] || die_usage "--expected-m-sha needs a value"; EXPECTED_M="$2"; shift 2 ;;
        --repo)           [ $# -ge 2 ] || die_usage "--repo needs a value"; REPO="$2"; shift 2 ;;
        --self-test)      MODE="self-test"; shift ;;
        -h|--help)        usage_text; exit "$EX_OK" ;;
        *)                die_usage "unknown argument: $1" ;;
    esac
done

case "$MODE" in
    self-test)
        run_self_test
        exit $?
        ;;
    run-id|logs-dir)
        ;;
    *)
        usage_text >&2
        exit "$EX_USAGE"
        ;;
esac

if [ "$MODE" = "run-id" ]; then
    printf '%s' "$RUN_ID" | grep -Eq '^[0-9]+$' || die_usage "--run-id must be numeric: $RUN_ID"
    command -v gh >/dev/null 2>&1 || die_usage "gh CLI not found (required for --run-id mode)"
fi
[ -n "$EXPECTED_M" ] || die_usage "--expected-m-sha is required"
is_sha40 "$EXPECTED_M" || die_usage "--expected-m-sha must be 40 lowercase hex: $EXPECTED_M"
if [ -n "$PR_NUMBER" ]; then
    printf '%s' "$PR_NUMBER" | grep -Eq '^[0-9]+$' || die_usage "--pr must be numeric: $PR_NUMBER"
fi
command -v jq >/dev/null 2>&1 || die_usage "jq not found (required)"
command -v unzip >/dev/null 2>&1 || die_usage "unzip not found (required)"
if [ "$MODE" = "logs-dir" ] && [ -z "$LOGS_DIR" ]; then
    die_usage "--logs-dir needs a directory in logs-dir mode"
fi

if [ "$MODE" = "run-id" ]; then
    if [ -z "$LOGS_DIR" ]; then
        TMPDIR_RUN="$(mktemp -d)"
        LOGS_DIR="$TMPDIR_RUN/logs"
        trap 'rm -rf "$TMPDIR_RUN"' EXIT
    fi
    run_mode_run_id
else
    run_offline_identity_checks
fi
drive_assertions

printf -- '----\n'
if [ "$FAILS" -eq 0 ]; then
    printf 'ACCEPTANCE: PASS — GO-critical merge-group lane green is auditable (all assertions satisfied)\n'
    exit "$EX_OK"
fi
printf 'ACCEPTANCE: FAIL — %s assertion(s) failed (fail-closed)\n' "$FAILS"
exit "$EX_FAIL"
