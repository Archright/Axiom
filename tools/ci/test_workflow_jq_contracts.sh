#!/usr/bin/env bash
#
# test_workflow_jq_contracts.sh — jq data-contract regression test for the
# GitHub Actions workflows' jq expressions (zero new dependencies: bash + jq +
# python3/PyYAML + unzip — the same dep set validate_workflow_shell.sh already
# requires, plus the unzip the probe workflow itself consumes).
#
# Defect class being pinned (2026-11-01 GHEC-return incident): TWO workflow jq
# expressions carried a FALSE assumption about the shape of the GitHub REST API
# responses they consume, and BOTH defects passed the existing `bash -n` shell
# gate before AND after the fix — shell syntax validation never inspects the
# DATA STRUCTURE jq consumes:
#   * Q16 — ghec-canary.yml:94 `[.labels[]?.name]`: the workflow-jobs REST
#     `labels` field is an ARRAY OF STRING (docs.github.com/rest/actions/
#     workflow-jobs), so `.name` indexing died with jq exit 5 BEFORE any
#     identity verdict (fix PR #1160: `[.labels[]? | (.name? // .)]`).
#   * Q17 — ci-provider-router.yml:464 `jq -c '{name,…}'`: ACC_NON_SKIP is an
#     ARRAY (`[.[] | select(…)]`), object shorthand without `.[]` distribution
#     died with "Cannot index array with string" exit 5 between the acceptance
#     verdict and the `return_acceptance=confirmed` write (fix PR #1163:
#     `jq -c '.[] | {name,…}'`).
#   * Q19 — (2026-11-02 fetch-fallback hardening) ci-provider-router.yml:357
#     fetched the run's jobs with an UNPROTECTED pipeline
#     (`gh api --paginate … | jq -sc '[.[].jobs[]]'`): every transport-layer
#     failure (HTTP 404 for a missing run, 403 rate-limit, empty stdout) died
#     on pipefail/jq exit 5 BEFORE the (2-a) UNKNOWN resolution, the
#     return-acceptance verdict/writes, the block transition, and the rerun —
#     the same `return_acceptance=pending` silent-stall shape as Q17, this time
#     before any decision. probe-merge-queue.yml carried the same class in two
#     MINOR sites (:220 artifacts listing pipeline; :238 payload download where
#     a `gh api` error JSON body landed in a .zip — Q18 measured stdout
#     behavior). Fix contract: exit-code gate + acceptance-time envelope schema
#     validation (has("jobs")/has("artifacts"), has("message") contamination
#     detection), failure resolved by the ESTABLISHED UNKNOWN-record semantics
#     (no new state, no new variable fields), streams separated so observation
#     logs cannot kill the judgment value, endpoint/jq expression unchanged
#     (happy path byte-identical).
# Full contracts: docs/spec/ci_provider_failover_quirks.md Q16/Q17/Q18/Q19;
# docs/evidence/ci_provider_canary_fix_epoch_2026-11-01.md;
# docs/evidence/ci_provider_router_acceptance_fix_epoch_2026-11-01.md;
# docs/evidence/ci_provider_fetch_fallback_hardening_epoch_2026-11-02.md;
# docs/evidence/ci_provider_ghec_return_acceptance_2026-11-01.md.
#
# Method (anti-drift by construction):
#   1. EXTRACTION, not copy-paste — every jq program under test is extracted
#      from the LIVE workflow YAML at run time (python3+yaml.safe_load walks
#      jobs.*.steps[*].run scalars; anchored regexes pick each program by its
#      unique shell context). If the workflow moves/renames a site, extraction
#      fails CLOSED (exit 2) — the contract must be re-pinned deliberately.
#      Copying program text into this file would drift silently; it is
#      forbidden here by design. The three FETCH FALLBACK BLOCKS (router
#      jobs-fetch gate, probe artifacts gate, probe payload download gate) are
#      likewise extracted as live multi-line blocks and EXECUTED in a sandbox.
#   2. VERBATIM fixtures — judgment inputs are raw `gh api` GET response bodies
#      captured 2026-11-01/02 (capture_manifest.json holds URL/run/timestamp
#      provenance and the official-schema basis; the 403 rate-limit body is
#      COMPOSED per the official documented schema because inducing a real
#      rate limit is forbidden). Hand-written mocks are the defect class
#      itself and must NOT replace them; negative controls below fail if
#      anyone sanitizes the fixtures into mocks.
#   3. FIXED expectations — every observed output is asserted byte-exact
#      against values pinned from the measured evidence (canary job identity)
#      and committed golden row files (acceptance rows).
#   4. CONTROLLED FAILURE INJECTION (Q19) — the sandbox `gh` is a test-owned
#      PATH shim that replays a committed fixture body (or empty stdout) with
#      a pinned exit code and logs every invocation; the injection MECHANISM is
#      test property, the injected BODIES are committed fixtures. Zero network
#      calls anywhere in this harness.
#
# Contract matrix (fixture × expectation):
#   canary_run_41289547761_jobs.json (Q16 killing shape: labels=["ubuntu-24.04"]
#     as strings, runner_group_id=0):
#     - envelope fetch `.jobs[0]` yields the job object
#     - runner_group_id=0, runner_group_name="GitHub Actions",
#       runner_id=1000035433, runner_name="GitHub Actions 1000035433",
#       labels program → ["ubuntu-24.04"] (exit 0), steps=3
#     - gate program index("ubuntu-24.04") != null → true (jq -e exit 0)
#   run_41298669695_jobs_p1.json (22 jobs = 12 executed GHEC + 10 skipped;
#     the run the first `return_acceptance=confirmed` write was bound to):
#     - page assembly `[.[].jobs[]]` → 22 rows
#     - ACC_NON_SKIP=12 (skipped/all-null excluded), ACC_EXECUTED=12,
#       ACC_BLOCKED=0, ACC_ALL_GHEC=true (the confirmed-write precondition)
#     - acceptance-row program → 12 rows, byte-identical to committed golden
#   run_41312498699_jobs_p1.json (1 executed GHEC job): same pipeline, 1 row.
#   err404_jobs_run_not_found.json (measured 404 body for a nonexistent run,
#     the exact :357 fetch shape under transport failure):
#     - envelope gates (router + probe) REJECT it (has("message"))
#     - repaired router block: exit 1 + UNKNOWN record + zero variable writes
#     - pre-fix pipeline control: `jq -sc '[.[].jobs[]]'` exits 5
#       ("Cannot iterate over null") — the killing shape must stay in fixtures
#   err403_rate_limit_composed.json (official-schema 403, Q18 incident class):
#     - same rejection/fallback/pre-fix-exit-5 expectations as the 404
#   artifacts_envelope_page1_perpage1.json (verbatim envelope, 1 artifact row):
#     - probe BATCH `.artifacts` extraction byte-identical (pre/post repair)
#   Empty stdout (shim `empty_fail`): transport death class → UNKNOWN record.
#   Negative controls (can-fail proof — the fixtures must keep the shapes that
#     KILLED the pre-fix programs):
#     a. pre-fix Q16 program `[.labels[]?.name]` must exit 5 on the canary job
#        (labels = string array). If a "fix" sanitizes the fixture into an
#        object-shaped mock, this control fails.
#     b. pre-fix Q17 object-shorthand program must exit 5 on the ACC_NON_SKIP
#        array. If someone reverts the workflow fix, section 3 fails at the
#        extracted program's exit 5; if someone instead edits fixtures to make
#        the reverted program pass, this control fails.
#     c. pre-fix :357 pipeline (`… | jq -sc '[.[].jobs[]]'`) must die on the
#        404/403 bodies (jq exit 5) and on empty stdout (pipeline rc 1) —
#        revert-detection for the Q19 repair (a revert makes section 5's block
#        extraction fail closed AND this control keeps proving the fixture
#        killing shapes).
#     d. probe pre-fix controls: `.artifacts` on the 404 body yields `null`
#        (rc 0!) and the downstream `.[] | select(…)` dies exit 5 — the silent
#        contamination path; `unzip -t` rejects an error-JSON .zip.
#
# Run:   bash tools/ci/test_workflow_jq_contracts.sh  (or: make test-workflow-jq-contracts)
# No network. Deterministic: committed fixtures + live YAML + controlled shim → fixed verdict.
#
# Exit codes:
#   0 — all contract assertions held
#   1 — contract violation (jq runtime error on a live program, expectation
#       mismatch, or negative control failed) — fail-closed
#   2 — environment/configuration error (missing tool/fixture, workflow anchor
#       not found or ambiguous — the contract site moved; re-pin deliberately)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROBE_YML="$ROOT/.github/workflows/probe-merge-queue.yml"
FIX="$ROOT/tests/fixtures/workflow_jq_contracts"

fail() { echo "test_workflow_jq_contracts: FAIL — $*" >&2; exit 1; }
config_error() { echo "test_workflow_jq_contracts: CONFIG-ERROR — $*" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || config_error "jq not on PATH (fixture contract needs the same tool the workflows consume)"
command -v python3 >/dev/null 2>&1 || config_error "python3 not on PATH"
command -v unzip >/dev/null 2>&1 || config_error "unzip not on PATH (the probe payload acceptance gate consumes it)"
command -v mktemp >/dev/null 2>&1 || config_error "mktemp not on PATH (block sandbox needs it)"
python3 -c 'import yaml' 2>/dev/null || config_error "python3 yaml (PyYAML) unavailable"
[ -f "$PROBE_YML" ] || config_error "missing $PROBE_YML"
[ -f "$FIX/capture_manifest.json" ] || config_error "missing $FIX/capture_manifest.json (fixture provenance SSOT)"
[ -f "$FIX/canary_run_41289547761_jobs.json" ] || config_error "missing canary fixture"
[ -f "$FIX/run_41298669695_jobs_p1.json" ] || config_error "missing acceptance fixture 41298669695"
[ -f "$FIX/run_41312498699_jobs_p1.json" ] || config_error "missing acceptance fixture 41312498699"
[ -f "$FIX/expected_run_41298669695_acceptance_rows.jsonl" ] || config_error "missing golden rows 41298669695"
[ -f "$FIX/expected_run_41312498699_acceptance_rows.jsonl" ] || config_error "missing golden rows 41312498699"
[ -f "$FIX/err404_jobs_run_not_found.json" ] || config_error "missing measured 404 fixture"
[ -f "$FIX/err403_rate_limit_composed.json" ] || config_error "missing composed 403 fixture"
[ -f "$FIX/artifacts_envelope_page1_perpage1.json" ] || config_error "missing artifacts envelope fixture"

# ── sandbox (controlled gh shim + block files) ──────────────────────────────
SB="$(mktemp -d "${TMPDIR:-/tmp}/axwjqc.XXXXXX")" || config_error "mktemp failed"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" "$SB/blocks" "$SB/sb2/payloads"
cat > "$SB/bin/gh" <<'GH_SHIM'
#!/usr/bin/env bash
# test-owned controlled gh shim — replays a committed fixture body (or empty
# stdout) with a pinned exit code; every invocation is logged verbatim (the
# log doubles as the no-variable-write oracle). Injection mechanism is owned
# by this test; injected bodies are the committed fixtures.
LOG="${GH_SHIM_LOG:?GH_SHIM_LOG required}"
printf '%s\n' "$*" >>"$LOG"
case "${GH_SHIM_MODE:?GH_SHIM_MODE required}" in
  emit_fixture) cat "${GH_SHIM_BODY_FILE:?}"; exit "${GH_SHIM_RC:-0}" ;;
  emit_zipfile) cat "${GH_SHIM_ZIP_FILE:?}"; exit "${GH_SHIM_RC:-0}" ;;
  empty_fail)   exit 1 ;;
  *) echo "gh shim: unknown GH_SHIM_MODE '$GH_SHIM_MODE'" >&2; exit 9 ;;
esac
GH_SHIM
chmod +x "$SB/bin/gh"
SHIM_MODE=emit_fixture
SHIM_BODY='-'
SHIM_ZIP='-'
SHIM_RC=0

# ── 1. extract live jq program texts + fallback blocks from the workflow YAML (fail-closed) ───
# yaml.safe_load walks jobs.*.steps[*].run scalars (same extraction shape as
# validate_workflow_shell.sh — the parser owns YAML structure); each anchor
# regex must match EXACTLY ONE line (single-line anchors) / EXACTLY ONE
# region (block anchors) across the whole file. 0 matches = the contract site
# moved/renamed (deliberate re-pin required); >1 = ambiguous.
EXTRACTED="$(python3 - "$PROBE_YML" "$SB/blocks" <<'PYEOF'
import os, re, sys, yaml

def run_scalars(path):
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    out = []
    jobs = doc.get("jobs") if isinstance(doc, dict) else None
    if not isinstance(jobs, dict):
        return out
    for jname, job in jobs.items():
        steps = job.get("steps") if isinstance(job, dict) else None
        if not isinstance(steps, list):
            continue
        for i, step in enumerate(steps):
            if isinstance(step, dict) and isinstance(step.get("run"), str):
                out.append(("%s:%s" % (jname, step.get("name") or ("step#%d" % i)), step["run"]))
    return out

# key -> (file index, per-line anchored pattern, capture group 1 = program text)
SINGLE_ANCHORS = {
    "PROBE_ARTIFACTS_FETCH_CMD": (0, r'^[ \t]*ART_BODY="\$\(gh api "repos/\$GITHUB_REPOSITORY/actions/artifacts\?per_page=100&page=\$PAGE" 2>"\$ART_ERR_FILE"\)" \|\| ART_RC=\$\?$'),
    "PROBE_ARTIFACTS_ENVELOPE":  (0, r'printf \'%s\' "\$ART_BODY" \| jq -se \'([^\']+)\' >/dev/null'),
    "PROBE_ARTIFACTS_BATCH":     (0, r'^[ \t]*BATCH="\$\(printf \'%s\' "\$ART_BODY" \| jq -c \'([^\']*)\'\)"$'),
    "PROBE_URL_PICK":            (0, r'jq -r \'([^\']+)\' <<<"\$BATCH"'),
    "PROBE_DOWNLOAD_FETCH_CMD":  (0, r'^[ \t]*gh api -H "Accept: application/vnd.github\+json" "\$URL" > "\$ZIP_TMP" 2>"payloads/\$ART_ID\.dl_stderr" \|\| DL_RC=\$\?$'),
}
# key -> (file index, multiline region pattern; group 0 = block text)
BLOCK_ANCHORS = {
    "PROBE_ARTIFACTS_BLOCK": (0, r'(?ms)^[ \t]*ART_RC=0$.*?^[ \t]*BATCH="\$\(printf \'%s\' "\$ART_BODY" \| jq -c \'[^\']*\'\)"$'),
    "PROBE_DOWNLOAD_BLOCK":  (0, r'(?ms)^[ \t]*ZIP_TMP="payloads/\$ART_ID\.zip\.partial"$.*?^[ \t]*\(cd "payloads/\$ART_ID" && unzip -o -q "\.\./\$ART_ID\.zip"\)$'),
}

files = [run_scalars(sys.argv[1])]
outdir = sys.argv[2]

def config_err(msg):
    print("CONFIG-ERROR %s" % msg, file=sys.stderr)
    sys.exit(2)

def extract_single(key, fidx, pattern):
    rx = re.compile(pattern)
    hits = []
    for where, body in files[fidx]:
        for line in body.splitlines():
            m = rx.match(line) if pattern.startswith("^") else rx.search(line)
            if m:
                hits.append((where, m.group(1) if m.groups() else m.group(0)))
    if len(hits) == 0:
        config_err("anchor %r not found in %s — workflow restructured; re-pin the contract test" % (key, sys.argv[1 + fidx]))
    if len(hits) > 1:
        config_err("anchor %r matched %d lines (%s) — ambiguous; re-pin" % (key, len(hits), ", ".join(w for w, _ in hits)))
    where, prog = hits[0]
    if "\t" in prog or "\n" in prog:
        config_err("anchor %r captured a multi-line program — transport unsupported; re-pin" % key)
    return prog

for key in sorted(SINGLE_ANCHORS):
    fidx, pattern = SINGLE_ANCHORS[key]
    print("%s\t%s" % (key, extract_single(key, fidx, pattern)))

for key in sorted(BLOCK_ANCHORS):
    fidx, pattern = BLOCK_ANCHORS[key]
    rx = re.compile(pattern)
    hits = []
    for where, body in files[fidx]:
        n = len(rx.findall(body))
        if n > 0:
            hits.append((where, rx.search(body).group(0), n))
    if len(hits) == 0:
        config_err("block anchor %r not found in %s — workflow restructured; re-pin the contract test" % (key, sys.argv[1 + fidx]))
    if len(hits) > 1 or hits[0][2] > 1:
        config_err("block anchor %r matched %d scalar(s), %d region(s) — ambiguous; re-pin" % (key, len(hits), hits[0][2]))
    path = os.path.join(outdir, key + ".sh")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(hits[0][1] + "\n")
    print("%s\t%s" % (key, path))
PYEOF
)" || config_error "extraction failed (see CONFIG-ERROR above)"

declare -A PROG
while IFS=$'\t' read -r k v; do PROG[$k]="$v"; done <<<"$EXTRACTED"
[ "${#PROG[@]}" -eq 7 ] || config_error "expected 7 extracted contracts (5 single-line programs + 2 fallback blocks), got ${#PROG[@]}"

echo "== test_workflow_jq_contracts: extracted 5 live jq/shell programs + 2 live fallback blocks (probe Q19) =="

# jq runners with loud failure on jq runtime error (exit 5 = data-shape
# contract violation — the exact Q16/Q17/Q19 death mode)
jqs() { # jqs <input> <jq args...> — input string on stdin
  local input="$1"; shift
  local out rc=0
  out="$(jq "$@" <<<"$input")" || rc=$?
  [ "$rc" -eq 0 ] || fail "jq exit=$rc on args [$*] — jq runtime error = data-shape contract violation (Q16/Q17 death mode)"
  printf '%s' "$out"
}
jqf() { # jqf <file> <jq args...>
  local file="$1"; shift
  local out rc=0
  out="$(jq "$@" "$file")" || rc=$?
  [ "$rc" -eq 0 ] || fail "jq exit=$rc on $file args [$*] — jq runtime error = data-shape contract violation (Q16/Q17 death mode)"
  printf '%s' "$out"
}

# error bodies (shared by negative controls + probe sections)
E404="$(cat "$FIX/err404_jobs_run_not_found.json")"
E403="$(cat "$FIX/err403_rate_limit_composed.json")"

# ── 2–4. negative controls (a/b) — pre-fix Q16/Q17 programs must die on committed fixtures ──
CAN_JOBS="$FIX/canary_run_41289547761_jobs.json"
job="$(jqf "$CAN_JOBS" -c '.jobs[0]')"
[ -n "$job" ] && [ "$job" != "null" ] || fail "canary envelope fetch yielded an empty/null job — .jobs[0] contract broken"
rc=0
jq -c '[.labels[]?.name]' <<<"$job" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] || fail "pre-fix Q16 negative control expected jq exit 5 on canary job labels, got $rc — fixture sanitized into a mock?"

for f in "$FIX/run_41298669695_jobs_p1.json" "$FIX/run_41312498699_jobs_p1.json"; do
  non_skip="$(jqf "$f" -sc '[.[].jobs[] | select(.conclusion != "skipped" and (.runner_id != null or .runner_group_id != null))]')"
  rc=0
  jq -c '{name,conclusion,runner_id,runner_group_id,runner_group_name,runner_name,steps:(((.steps // []) | length))}' <<<"$non_skip" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 5 ] || fail "$f: pre-fix Q17 negative control expected jq exit 5 on ACC_NON_SKIP array, got $rc — fixture sanitized into a mock?"
done

echo "PASS negative controls: pre-fix Q16 and Q17 programs both exit 5 on the committed measured fixtures (killing shapes retained)"

reset_obs() { : > "$SB/gh_calls.log"; : > "$SB/summary.md"; }

# run_sh <workdir> <script> — sources the extracted block under the exact
# `set -euo pipefail` discipline the workflow uses; writes captured
# stdout+stderr to "$SB/run_out"; sets RUN_RC in THIS shell (no command
# substitution — the rc must survive). Judgment variables are echoed at the
# end so the happy path can be byte-compared.
run_sh() {
  local dir="$1" script="$2" rc=0
  GH_SHIM_LOG="$SB/gh_calls.log" GH_SHIM_MODE="$SHIM_MODE" \
      GH_SHIM_BODY_FILE="${SHIM_BODY#-}" GH_SHIM_RC="$SHIM_RC" GH_SHIM_ZIP_FILE="${SHIM_ZIP#-}" \
      PATH="$SB/bin:$PATH" \
      REPO="Archright/Axiom" WR_ID="41298669695" EVENT_NAME="workflow_run" \
      GITHUB_REPOSITORY="Archright/Axiom" PAGE="1" \
      ART_ID="testart" URL="repos/Archright/Axiom/actions/artifacts/1/zip" \
      RUNNER_TEMP="$SB" GITHUB_STEP_SUMMARY="$SB/summary.md" \
      bash -c 'cd "$1" && set -euo pipefail && source "$2" && printf "%s" "${JOBS_ALL-}${BATCH-}"' \
      _ "$dir" "$script" >"$SB/run_out" 2>&1 && rc=0 || rc=$?
  RUN_RC=$rc
}

no_writes_or() { # no_writes_or <label> — the shim log must show exactly the fetch call, never a PATCH
  local label="$1" calls
  calls="$(wc -l <"$SB/gh_calls.log")"
  [ "$calls" -ge 1 ] || fail "$label: shim log empty — block never fetched"
  if grep -q 'PATCH' "$SB/gh_calls.log"; then
    fail "$label: variable write attempted during fetch failure — single-writer invariant broken: $(cat "$SB/gh_calls.log")"
  fi
}

# 5e. negative control (c) — the PRE-fix :357 pipeline must die on these
#     fixtures (revert + fixture-sanitization detection, mirrors the old line:
#     JOBS_ALL="$(gh api --paginate … | jq -sc '[.[].jobs[]]')")
prefix_pipeline() { # <mode> <bodyfile-or--> <rc> → sets PREFIX_RC (pipeline rc under set -o pipefail)
  local rc=0
  GH_SHIM_LOG="$SB/gh_calls.log" GH_SHIM_MODE="$1" GH_SHIM_BODY_FILE="${2#-}" GH_SHIM_RC="${3:-1}" \
    PATH="$SB/bin:$PATH" \
    bash -c 'set -euo pipefail; JOBS_ALL="$(gh api --paginate "repos/Archright/Axiom/actions/runs/41298669695/jobs?per_page=100" | jq -sc "[.[].jobs[]]")"; printf ok' \
    >/dev/null 2>&1 && rc=0 || rc=$?
  PREFIX_RC=$rc
}
prefix_pipeline emit_fixture "$FIX/err404_jobs_run_not_found.json" 1
[ "$PREFIX_RC" -eq 5 ] || fail "pre-fix :357 negative control: 404 body should kill the pipeline with jq exit 5 (Cannot iterate over null), got $PREFIX_RC"
prefix_pipeline emit_fixture "$FIX/err403_rate_limit_composed.json" 1
[ "$PREFIX_RC" -eq 5 ] || fail "pre-fix :357 negative control: 403 body should kill the pipeline with jq exit 5, got $PREFIX_RC"
prefix_pipeline empty_fail 1
[ "$PREFIX_RC" -eq 1 ] || fail "pre-fix :357 negative control: empty-stdout gh failure should kill the pipeline via pipefail (rc 1), got $PREFIX_RC"
echo "PASS negative control: pre-fix :357 unprotected pipeline exits 5 on 404/403 bodies and 1 on empty stdout (killing shapes retained — Q19 revert detection)"

# ── 6. probe-merge-queue :220 artifacts-listing gate (Q19, MINOR) ───────────
ART_FIXTURE="$FIX/artifacts_envelope_page1_perpage1.json"
[ "${PROG[PROBE_ARTIFACTS_BATCH]}" = '.artifacts' ] || fail "probe BATCH expression drifted: got '${PROG[PROBE_ARTIFACTS_BATCH]}' want '.artifacts'"
grep -q 'has("artifacts")' <<<"${PROG[PROBE_ARTIFACTS_ENVELOPE]}" || fail "probe envelope gate lost has(\"artifacts\") validation"
grep -q 'has("message")' <<<"${PROG[PROBE_ARTIFACTS_ENVELOPE]}" || fail "probe envelope gate lost has(\"message\") contamination detection"

art_expected="$(printf '%s' "$(cat "$ART_FIXTURE")" | jq -c '.artifacts')"
[ "$(printf '%s' "$art_expected" | jq 'length')" = "1" ] || fail "artifacts fixture should carry exactly 1 artifact row"

reset_obs
SHIM_MODE=emit_fixture; SHIM_BODY="$ART_FIXTURE"; SHIM_RC=0
run_sh "$SB" "${PROG[PROBE_ARTIFACTS_BLOCK]}"
out="$(cat "$SB/run_out")"
[ "$RUN_RC" -eq 0 ] || fail "probe artifacts happy path failed (rc=$RUN_RC): $out"
[ "$out" = "$art_expected" ] || fail "probe BATCH not byte-identical to the pre-repair '.artifacts' extraction over the verbatim envelope"
echo "PASS probe :220 happy path: BATCH byte-identical over artifacts_envelope_page1_perpage1 (1 row)"

rc=0; printf '%s' "$(cat "$ART_FIXTURE")" | jq -se "${PROG[PROBE_ARTIFACTS_ENVELOPE]}" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] || fail "probe envelope gate rejected the verbatim artifacts envelope (rc=$rc)"
rc=0; printf '%s' "$E404" | jq -se "${PROG[PROBE_ARTIFACTS_ENVELOPE]}" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "probe envelope gate ACCEPTED the 404 error body"
rc=0; printf '%s' "$E403" | jq -se "${PROG[PROBE_ARTIFACTS_ENVELOPE]}" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "probe envelope gate ACCEPTED the 403 error body"

for probe_case in "emit_fixture:$FIX/err404_jobs_run_not_found.json:1" "emit_fixture:$FIX/err403_rate_limit_composed.json:1" "empty_fail:-:1"; do
  IFS=: read -r pmode pbody prc <<<"$probe_case"
  reset_obs
  SHIM_MODE="$pmode"; SHIM_BODY="$pbody"; SHIM_RC="$prc"
  run_sh "$SB" "${PROG[PROBE_ARTIFACTS_BLOCK]}"
out="$(cat "$SB/run_out")"
  [ "$RUN_RC" -eq 1 ] || fail "probe artifacts gate ($pmode/$pbody): expected explicit exit 1, got $RUN_RC; output: $(printf '%s' "$out" | head -3)"
  grep -q '::error::.*artifact listing fetch failed' <<<"$out" || fail "probe artifacts gate ($pmode): no explicit acquisition-error line"
  no_writes_or "probe artifacts gate ($pmode/$pbody)"
done
echo "PASS probe :220 gate: 404-measured / 403-composed / empty-stdout → explicit ::error:: + exit 1 (fail-closed direction kept), zero writes"

# pre-fix :220 negative control — `.artifacts` on an error body silently
# yields `null` (rc 0!) and the downstream URL-picker then dies exit 5
rc=0; batch="$(printf '%s' "$E404" | jq -c '.artifacts')" || rc=$?
[ "$rc" -eq 0 ] && [ "$batch" = "null" ] || fail "pre-fix probe control: .artifacts on 404 body should yield null with rc 0 (got rc=$rc batch='$batch')"
rc=0; jq -r "${PROG[PROBE_URL_PICK]}" <<<"$batch" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] || fail "pre-fix probe negative control: URL-picker over null BATCH should exit 5, got $rc"
echo "PASS negative control: pre-fix :220 pipeline accepts an error body as data (BATCH=null, rc 0) and its downstream picker exits 5 (silent-contamination shape retained)"

# ── 7. probe-merge-queue :238 payload download gate (Q19, MINOR) ────────────
case "${PROG[PROBE_DOWNLOAD_FETCH_CMD]}" in
  *'> "$ZIP_TMP" 2>"payloads/$ART_ID.dl_stderr" || DL_RC=$?'*) ;;
  *) fail "probe download fetch gate drifted: ${PROG[PROBE_DOWNLOAD_FETCH_CMD]}" ;;
esac
# deterministic acceptance fixture: a minimal zip carrying payload.json (built
# with fixed timestamps — behavior-deterministic; this is NOT an API-response
# mock, it is the payload the gate accepts after validation)
ZIPFIX="$SB/payload_fixture.zip"
python3 - "$ZIPFIX" <<'PYZIP'
import json, sys, zipfile
payload = {"schema": "axiom/probe-merge-queue/payload/v2", "G": "f" * 40,
           "note": "harness-built deterministic acceptance fixture"}
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_STORED) as zf:
    info = zipfile.ZipInfo("payload.json", date_time=(1980, 1, 1, 0, 0, 0))
    zf.writestr(info, json.dumps(payload, sort_keys=True))
PYZIP
TRUNC_ZIP="$SB/truncated.zip"
head -c 48 "$ZIPFIX" > "$TRUNC_ZIP"

reset_sb2() { rm -rf "$SB/sb2/payloads"; mkdir -p "$SB/sb2/payloads"; }

# happy: exit 0 + valid zip → accepted into payloads/ and extracted
reset_sb2; reset_obs
SHIM_MODE=emit_zipfile; SHIM_ZIP="$ZIPFIX"; SHIM_RC=0
run_sh "$SB/sb2" "${PROG[PROBE_DOWNLOAD_BLOCK]}"
out="$(cat "$SB/run_out")"
[ "$RUN_RC" -eq 0 ] || fail "probe download happy path failed (rc=$RUN_RC): $out"
[ -f "$SB/sb2/payloads/testart.zip" ] || fail "probe download happy path: accepted .zip missing"
[ ! -e "$SB/sb2/payloads/testart.zip.partial" ] || fail "probe download happy path: .partial not consumed by acceptance mv"
grep -q '"schema": "axiom/probe-merge-queue/payload/v2"' "$SB/sb2/payloads/testart/payload.json" \
  || fail "probe download happy path: payload.json not extracted from the validated zip"
echo "PASS probe :238 happy path: valid zip accepted (PK + unzip -t verified), payload.json extracted"

# failure classes: nothing accepted into payloads/, explicit ::error::, exit 1
reset_sb2; reset_obs
SHIM_MODE=emit_fixture; SHIM_BODY="$FIX/err404_jobs_run_not_found.json"; SHIM_RC=1
run_sh "$SB/sb2" "${PROG[PROBE_DOWNLOAD_BLOCK]}"
out="$(cat "$SB/run_out")"
[ "$RUN_RC" -eq 1 ] || fail "probe download rc1: expected exit 1, got $RUN_RC"
grep -q '::error::.*payload download failed' <<<"$out" || fail "probe download rc1: no explicit acquisition-error line"
[ ! -e "$SB/sb2/payloads/testart.zip" ] || fail "probe download rc1: an artifact was ACCEPTED despite download failure"
[ -f "$SB/sb2/payloads/testart.zip.partial" ] || fail "probe download rc1: response not preserved for observation (.partial missing)"

reset_sb2; reset_obs
SHIM_MODE=emit_fixture; SHIM_BODY="$FIX/err404_jobs_run_not_found.json"; SHIM_RC=0
run_sh "$SB/sb2" "${PROG[PROBE_DOWNLOAD_BLOCK]}"
out="$(cat "$SB/run_out")"
[ "$RUN_RC" -eq 1 ] || fail "probe download rc0-contaminated: expected exit 1, got $RUN_RC"
grep -q 'bad PK signature' <<<"$out" || fail "probe download rc0-contaminated: error JSON accepted despite failed PK gate"
[ ! -e "$SB/sb2/payloads/testart.zip" ] || fail "probe download rc0-contaminated: error body ACCEPTED as a .zip (Q18 class regression)"

reset_sb2; reset_obs
SHIM_MODE=emit_zipfile; SHIM_ZIP="$TRUNC_ZIP"; SHIM_RC=0
run_sh "$SB/sb2" "${PROG[PROBE_DOWNLOAD_BLOCK]}"
out="$(cat "$SB/run_out")"
[ "$RUN_RC" -eq 1 ] || fail "probe download truncated-zip: expected exit 1, got $RUN_RC"
grep -q 'integrity test' <<<"$out" || fail "probe download truncated-zip: no explicit integrity-error line"
[ ! -e "$SB/sb2/payloads/testart.zip" ] || fail "probe download truncated-zip: truncated payload ACCEPTED"
echo "PASS probe :238 gate: rc1 / rc0-error-body / truncated-zip all refused with explicit ::error:: + exit 1, nothing accepted (fail-closed direction kept)"

# pre-fix :238 negative control — the old line landed gh api stdout straight
# into a .zip; unzip must reject an error-JSON .zip (the exact Q18 acceptance
# path the gate now prevents)
reset_sb2
printf '%s' "$E404" > "$SB/sb2/payloads/errorbody.zip"
rc=0; unzip -t -q "$SB/sb2/payloads/errorbody.zip" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "pre-fix probe download control: unzip must reject an error-JSON .zip (got rc=0)"
echo "PASS negative control: an error JSON body written as .zip fails unzip (the pre-fix :238 acceptance path that the gate now refuses)"

# ════════════════════════════════════════════════════════════════════════════
# 6. release-ship freeze idempotency contract (2026-11-02) — SEPARATE case
#    group: own extraction, own fixtures (release_ship/ subdir), own mock-gh
#    harness. Shares NOTHING with the canary/router groups above (pure append,
#    all helpers carry the rel_ prefix) so parallel contract work on this file
#    cannot collide.
#
# Defect classes pinned (docs/spec/gh_api_paginate_output_quirks.md):
#   * P1 — freeze ⑥ assumed `gh api --paginate …/releases` always yields ONE
#     merged JSON array. The output shape is gh-VERSION-dependent: legacy gh
#     concatenates page bodies into a multi-document stream, on which the
#     pre-fix program `[.[] | select(.tag_name == $v)] | length` evaluates
#     PER DOCUMENT and n_same comes out MULTI-LINE → `[ "$n_same" = "0" ]`
#     errors → false already-exists FAIL blocks a legitimate release
#     (fail-WRONG, not fail-closed). Fixed program: `jq -s` slurp + every
#     document must be an array (else jq error = fail-closed) + flatten +
#     count; empty input = length 0.
#   * P2 — freeze ⑤ treated ANY existing tag ref as instant FAIL, so the
#     re-dispatch of an already-shipped (version, sha) pair could never
#     succeed. Idempotency judgment table pinned here (the boundary is
#     explicit: tag existence ALONE is never success):
#       same tag + same SHA (peel)   → NO-OP success, freeze_verdict=noop
#                                       (+frozen_sha, version_norm), ⑥⑦ skipped
#       same tag + different SHA     → explicit FAIL (clobber forbidden)
#       tag absent                   → proceed
#       unclear (5xx/network/parse)  → fail-closed FAIL
#
# Method (same anti-drift discipline as sections 1-4): the freeze step script
# is extracted VERBATIM from the live release-ship.yml at run time (yaml walk
# by step id, fail-closed on restructuring; expression tokens unsupported →
# re-pin) and EXECUTED against a mock `gh` on PATH whose response bodies are
# the committed fixtures in tests/fixtures/workflow_jq_contracts/release_ship/
# (provenance: capture_manifest_release_ship.json). The workflow script is
# never copied into this file; the mock replaces the network, not the code.
#
# Run: no network, deterministic. (bash + jq + python3/PyYAML — same dep set.)
# ════════════════════════════════════════════════════════════════════════════

REL_YML="$ROOT/.github/workflows/release-ship.yml"
REL_FIX="$FIX/release_ship"
[ -f "$REL_YML" ] || config_error "missing $REL_YML"
[ -f "$REL_FIX/capture_manifest_release_ship.json" ] || config_error "missing $REL_FIX/capture_manifest_release_ship.json (fixture provenance SSOT)"
for rel_fixture in rel_releases_p1_2026-11-02.json rel_releases_two_page_p1.json \
                   rel_releases_two_page_p2.json rel_releases_nonarray_doc.json \
                   rel_releases_empty_stream.json rel_releases_empty_array.json; do
  [ -f "$REL_FIX/$rel_fixture" ] || config_error "missing release-ship fixture $rel_fixture"
done

# ── 6a. extraction — freeze run block + single-line jq programs (fail-closed)
REL_EXTRACT="$(python3 - "$REL_YML" <<'PYEOF'
import re, sys, yaml

with open(sys.argv[1], encoding="utf-8") as fh:
    doc = yaml.safe_load(fh)
jobs = doc.get("jobs") if isinstance(doc, dict) else None
if not isinstance(jobs, dict):
    print("CONFIG-ERROR no jobs map in %s" % sys.argv[1], file=sys.stderr)
    sys.exit(2)

freeze_hits = []   # (where, run scalar of the id=freeze step)
anchor_lines = []  # (where, run scalar) for per-line anchored programs
for jname, job in jobs.items():
    steps = job.get("steps") if isinstance(job, dict) else None
    if not isinstance(steps, list):
        continue
    for i, step in enumerate(steps):
        if not isinstance(step, dict) or not isinstance(step.get("run"), str):
            continue
        where = "%s:%s" % (jname, step.get("name") or ("step#%d" % i))
        anchor_lines.append((where, step["run"]))
        if step.get("id") == "freeze":
            freeze_hits.append((where, step["run"]))

ANCHORS = {
    "REL_N_SAME":   r"""^[ \t]*n_same="\$\(printf '%s' "\$RELEASES" \| jq -s --arg v "\$VERSION_NORM" '([^']+)'\)"$""",
    "REL_TAG_ENUM": r"""^[ \t]*done < <\(printf '%s' "\$RELEASES" \| jq -r '([^']+)'\)$""",
}
for key in sorted(ANCHORS):
    rx = re.compile(ANCHORS[key])
    hits = []
    for where, body in anchor_lines:
        for line in body.splitlines():
            m = rx.match(line)
            if m:
                hits.append((where, m.group(1)))
    if len(hits) == 0:
        print("CONFIG-ERROR anchor %r not found in %s — workflow restructured; re-pin the contract test" % (key, sys.argv[1]), file=sys.stderr)
        sys.exit(2)
    if len(hits) > 1:
        print("CONFIG-ERROR anchor %r matched %d lines — ambiguous; re-pin" % (key, len(hits)), file=sys.stderr)
        sys.exit(2)
    print("%s\t%s" % (key, hits[0][1]))

if len(freeze_hits) == 0:
    print("CONFIG-ERROR no step with id=freeze carrying a run scalar in %s — workflow restructured; re-pin" % sys.argv[1], file=sys.stderr)
    sys.exit(2)
if len(freeze_hits) > 1:
    print("CONFIG-ERROR %d steps carry id=freeze — ambiguous; re-pin" % len(freeze_hits), file=sys.stderr)
    sys.exit(2)
frun = freeze_hits[0][1]
if "${{" in frun:
    print("CONFIG-ERROR freeze run block carries expression tokens — transport unsupported; re-pin", file=sys.stderr)
    sys.exit(2)
sys.stdout.write("BEGIN-FREEZE-RUN\n")
sys.stdout.write(frun)
PYEOF
)" || config_error "release-ship extraction failed (see CONFIG-ERROR above)"

REL_PROGS_TEXT="${REL_EXTRACT%%$'\n'BEGIN-FREEZE-RUN*}"
REL_FREEZE_RUN="${REL_EXTRACT#*$'\n'BEGIN-FREEZE-RUN$'\n'}"
[ -n "$REL_FREEZE_RUN" ] || config_error "freeze run block extracted empty — sentinel missing from extraction output"
declare -A REL_PROG
while IFS=$'\t' read -r rk rv; do REL_PROG[$rk]="$rv"; done <<<"$REL_PROGS_TEXT"
[ "${#REL_PROG[@]}" -eq 2 ] || config_error "expected 2 release-ship jq programs (⑥ count / ⑦ enum), got ${#REL_PROG[@]}"

REL_RUN_FILE="$(mktemp)"; printf '%s' "$REL_FREEZE_RUN" > "$REL_RUN_FILE"
bash -n "$REL_RUN_FILE" || fail "extracted release-ship freeze run block fails bash -n — live workflow shell regression"
echo "== release-ship group: extracted live freeze run block + 2 jq programs (⑥ count / ⑦ enum) =="

REL_P1="$REL_FIX/rel_releases_two_page_p1.json"
REL_P2="$REL_FIX/rel_releases_two_page_p2.json"
REL_EMPTY_STREAM="$REL_FIX/rel_releases_empty_stream.json"
REL_EMPTY_ARR="$REL_FIX/rel_releases_empty_array.json"
REL_NONARRAY="$REL_FIX/rel_releases_nonarray_doc.json"
SHA_TARGET="aaaaaaa1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
SHA_OTHER="bbbbbbb2bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
SHA_TAGOID="ccccccc3cccccccccccccccccccccccccccccccc"

# ── 6b. parsing contract — extracted live programs × committed fixtures ────
n_nomatch="$(cat "$REL_P1" "$REL_P2" | jq -s --arg v "v0.5.7" "${REL_PROG[REL_N_SAME]}")"
[ "$n_nomatch" = "0" ] || fail "⑥ program on the concatenated two-page stream (no match): got '$n_nomatch' want single-line '0' (gh --paginate multi-document contract)"
n_match="$(cat "$REL_P1" "$REL_P2" | jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}")"
[ "$n_match" = "1" ] || fail "⑥ program on the concatenated two-page stream (match in page 2): got '$n_match' want '1' — flattening lost the page-2 row"
n_empty_stream="$(jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}" < "$REL_EMPTY_STREAM")"
[ "$n_empty_stream" = "0" ] || fail "⑥ program on a zero-byte stream: got '$n_empty_stream' want '0' (empty input must be length 0, proceed)"
n_empty_arr="$(jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}" < "$REL_EMPTY_ARR")"
[ "$n_empty_arr" = "0" ] || fail "⑥ program on an empty array: got '$n_empty_arr' want '0'"
rc=0
jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}" < "$REL_NONARRAY" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "⑥ program on a non-array document exited 0 — non-array input must fail-closed via jq error"
echo "PASS release-ship ⑥ count contract: two-page stream v0.5.7→0 / v0.5.6→1 (single-line); empty stream & empty array→0; non-array document fail-closed"

enum="$(cat "$REL_P1" "$REL_P2" | jq -r "${REL_PROG[REL_TAG_ENUM]}")"
[ "$(printf '%s\n' "$enum" | wc -l)" = "3" ] || fail "⑦ enumeration on the two-page stream: want 3 tag rows across both documents, got: $enum"
printf '%s\n' "$enum" | head -1 | grep -qx "v0.5.4" || fail "⑦ enumeration lost page-1 rows"
printf '%s\n' "$enum" | tail -1 | grep -qx "v0.5.6" || fail "⑦ enumeration lost page-2 rows"
echo "PASS release-ship ⑦ enumeration contract: per-document iteration yields all 3 tag rows across the two-page stream (shape-consistent with the ⑥ input)"

# negative control — the PRE-FIX ⑥ program must keep producing the killing
# multi-line count on the concatenated stream; sanitizing the fixtures into a
# single merged document makes this control fail (same discipline as §4).
old_out="$(cat "$REL_P1" "$REL_P2" | jq --arg v "v0.5.7" '[.[] | select(.tag_name == $v)] | length' 2>/dev/null)"
[ "$(printf '%s\n' "$old_out" | wc -l)" = "2" ] || fail "pre-fix ⑥ negative control: want a 2-line per-document count on the concatenated stream, got '$old_out' — killing shape sanitized into a mock?"
echo "PASS release-ship negative control: pre-fix ⑥ program emits a 2-line count on the concatenated stream (killing shape retained)"

# ── 6c. semantics — the LIVE freeze run block executed against mock gh ──────
REL_MOCKBIN="$(mktemp -d)"
REL_TMP="$(mktemp -d)"
trap 'rm -rf "$REL_MOCKBIN" "$REL_TMP"' EXIT

cat > "$REL_MOCKBIN/gh" <<'MOCKGH'
#!/usr/bin/env bash
# Test double for `gh api`: dispatches on the REST path; per-scenario state in
# $MOCK_STATE_DIR. Bodies are emitted verbatim from the committed fixtures;
# error paths emit gh-shaped "HTTP <code>" text with rc 1 — the workflow
# captures 2>&1, so either stream lands in the captured variable (same as the
# real gh). Unmocked endpoints exit 97 loudly — the harness treats rc-97 as a
# fixture bug, never a scenario verdict.
set -u
[ -n "${MOCK_STATE_DIR:-}" ] || { echo "mock-gh: MOCK_STATE_DIR unset" >&2; exit 97; }
paginate=0 path="" prev=""
for a in "$@"; do
  [ "$prev" = "--paginate" ] && paginate=1
  case "$a" in
    api) ;;
    repos/*) path="$a" ;;
  esac
  prev="$a"
done
[ -n "$path" ] || { echo "mock-gh: no repos/ path in args: $*" >&2; exit 97; }
ok() { cat "$1"; exit 0; }
httpfail() { echo "gh: Not Found (HTTP $1)"; exit 1; }
case "$path" in
  */git/ref/heads/main)
    ok "$MOCK_STATE_DIR/main_ref.json" ;;
  */git/ref/tags/*)
    if [ -f "$MOCK_STATE_DIR/http500_tag_ref" ]; then httpfail 500; fi
    tag="${path##*/git/ref/tags/}"
    if [ -f "$MOCK_STATE_DIR/ref_tag_${tag}.json" ]; then
      ok "$MOCK_STATE_DIR/ref_tag_${tag}.json"
    fi
    httpfail 404 ;;
  */git/tags/*)
    oid="${path##*/git/tags/}"
    if [ -f "$MOCK_STATE_DIR/tagobj_${oid}.json" ]; then
      ok "$MOCK_STATE_DIR/tagobj_${oid}.json"
    fi
    httpfail 404 ;;
  */releases)
    if [ "$paginate" -eq 1 ]; then
      cat "$MOCK_STATE_DIR/releases_p1.json"
      if [ -f "$MOCK_STATE_DIR/releases_p2.json" ]; then
        cat "$MOCK_STATE_DIR/releases_p2.json"
      fi
      exit 0
    fi
    echo "mock-gh: non-paginated releases GET not wired (fail-closed)" >&2
    exit 97 ;;
  *)
    echo "mock-gh: unmocked endpoint: $path" >&2
    exit 97 ;;
esac
MOCKGH
chmod +x "$REL_MOCKBIN/gh"

rel_ref_json() { # <type: commit|tag> <sha> → GET /git/ref/tags body (refs REST schema)
  printf '{"ref":"refs/tags/fixture","object":{"sha":"%s","type":"%s"}}' "$2" "$1"
}
rel_tagobj_json() { # <tag_oid> <peeled_commit_sha> → GET /git/tags body (annotated peel)
  printf '{"sha":"%s","tag":"fixture","object":{"sha":"%s","type":"commit"}}' "$1" "$2"
}
rel_make_state() { # <releases_p1_file> [releases_p2_file] → echoes scenario state dir
  local d
  d="$(mktemp -d "$REL_TMP/state.XXXXXX")"
  rel_ref_json commit "$SHA_TARGET" > "$d/main_ref.json"
  cat "$1" > "$d/releases_p1.json"
  if [ $# -ge 2 ]; then cat "$2" > "$d/releases_p2.json"; fi
  printf '%s' "$d"
}
rel_run_freeze() { # <state_dir> <version> <target_sha> → FREEZE_RC / FREEZE_LOG / GOUT
  FREEZE_RC=0
  GOUT="$(mktemp "$REL_TMP/out.XXXXXX")"
  FREEZE_LOG="$(mktemp "$REL_TMP/log.XXXXXX")"
  RUN_REF=refs/heads/main RUN_SHA="$3" TARGET_RAW="$3" VERSION_RAW="$2" \
    GITHUB_REPOSITORY="Archright/Axiom" GH_TOKEN="fixture-token" \
    GITHUB_OUTPUT="$GOUT" MOCK_STATE_DIR="$1" PATH="$REL_MOCKBIN:$PATH" \
    bash "$REL_RUN_FILE" >"$FREEZE_LOG" 2>&1 || FREEZE_RC=$?
}
rel_expect_output() { # <gout> <exact-line>...
  local f="$1" kv
  shift
  for kv in "$@"; do
    grep -qx "$kv" "$f" || fail "GITHUB_OUTPUT missing '$kv' (got: $(tr '\n' ';' < "$f"))"
  done
}

# h1 — fresh proceed over a populated single-array page, tag absent
d="$(rel_make_state "$REL_P1")"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -eq 0 ] || fail "fresh scenario rc=$FREEZE_RC — tag absent + no matching release must proceed: $(cat "$FREEZE_LOG")"
rel_expect_output "$GOUT" "freeze_verdict=fresh" "frozen_sha=$SHA_TARGET" "version_norm=v0.5.6"
grep -q "no existing tag v0.5.6" "$FREEZE_LOG" || fail "fresh scenario log missing 'no existing tag v0.5.6'"
echo "PASS release-ship semantics: tag absent + populated release list → proceed, freeze_verdict=fresh + frozen_sha/version_norm bound"

# h2 — concatenated two-page stream WITHOUT the version → proceed (P1 fix)
d="$(rel_make_state "$REL_P1" "$REL_P2")"
rel_run_freeze "$d" "v0.5.7" "$SHA_TARGET"
[ "$FREEZE_RC" -eq 0 ] || fail "multi-doc proceed scenario rc=$FREEZE_RC — the pre-fix false already-exists FAIL regressed (concatenated pages must proceed): $(cat "$FREEZE_LOG")"
rel_expect_output "$GOUT" "freeze_verdict=fresh"
echo "PASS release-ship semantics: concatenated two-page stream WITHOUT the version → proceed (false-FAIL closed)"

# h3 — matching release inside page 2 → ⑥ already-exists FAIL preserved
d="$(rel_make_state "$REL_P1" "$REL_P2")"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -ne 0 ] || fail "⑥ match scenario rc=0 — an existing release with tag_name=v0.5.6 must FAIL"
grep -q "already exists" "$FREEZE_LOG" || fail "⑥ match scenario log missing 'already exists'"
echo "PASS release-ship semantics: matching release in page 2 → ⑥ already-exists FAIL preserved"

# h4/h5 — empty stream and empty array boundaries → proceed
d="$(rel_make_state "$REL_EMPTY_STREAM")"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -eq 0 ] || fail "empty-stream scenario rc=$FREEZE_RC — zero-byte releases output must proceed: $(cat "$FREEZE_LOG")"
rel_expect_output "$GOUT" "freeze_verdict=fresh"
d="$(rel_make_state "$REL_EMPTY_ARR")"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -eq 0 ] || fail "empty-array scenario rc=$FREEZE_RC — [] releases output must proceed: $(cat "$FREEZE_LOG")"
rel_expect_output "$GOUT" "freeze_verdict=fresh"
echo "PASS release-ship semantics: empty stream / empty array → proceed (length 0)"

# h6 — non-array document in the stream → fail-closed (jq error propagates)
d="$(rel_make_state "$REL_NONARRAY")"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -ne 0 ] || fail "non-array scenario rc=0 — a non-array document in the releases stream must fail-closed"
grep -q "non-array document" "$FREEZE_LOG" || fail "non-array scenario log missing the jq error text 'non-array document'"
echo "PASS release-ship semantics: non-array document in the stream → fail-closed (jq error propagated)"

# h7 — NO-OP: lightweight tag at the identical SHA
d="$(rel_make_state "$REL_P1")"
rel_ref_json commit "$SHA_TARGET" > "$d/ref_tag_v0.5.6.json"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -eq 0 ] || fail "NO-OP lightweight scenario rc=$FREEZE_RC — same tag+same SHA must be a NO-OP success: $(cat "$FREEZE_LOG")"
rel_expect_output "$GOUT" "freeze_verdict=noop" "frozen_sha=$SHA_TARGET" "version_norm=v0.5.6"
grep -q "⑤ NO-OP" "$FREEZE_LOG" || fail "NO-OP lightweight scenario log missing '⑤ NO-OP'"
echo "PASS release-ship semantics: lightweight tag at identical SHA → NO-OP success (verdict=noop, sha/version bound)"

# h8 — NO-OP: annotated tag peeling to the identical SHA (⑦-identical peel)
d="$(rel_make_state "$REL_P1")"
rel_ref_json tag "$SHA_TAGOID" > "$d/ref_tag_v0.5.6.json"
rel_tagobj_json "$SHA_TAGOID" "$SHA_TARGET" > "$d/tagobj_${SHA_TAGOID}.json"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -eq 0 ] || fail "NO-OP annotated scenario rc=$FREEZE_RC — annotated tag peeling to the target must NO-OP: $(cat "$FREEZE_LOG")"
rel_expect_output "$GOUT" "freeze_verdict=noop" "frozen_sha=$SHA_TARGET"
echo "PASS release-ship semantics: annotated tag peeling to identical SHA → NO-OP success (peel logic identical to ⑦)"

# h9 — NO-OP skips ⑥⑦: re-dispatch after a completed publish (tag@SHA AND a
# release with the same tag_name exist) must succeed — ⑥ would FAIL if it ran
d="$(rel_make_state "$REL_P1" "$REL_P2")"
rel_ref_json tag "$SHA_TAGOID" > "$d/ref_tag_v0.5.6.json"
rel_tagobj_json "$SHA_TAGOID" "$SHA_TARGET" > "$d/tagobj_${SHA_TAGOID}.json"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -eq 0 ] || fail "NO-OP skip-⑥ scenario rc=$FREEZE_RC — re-dispatch of a shipped pair (tag@SHA + release exists) must NO-OP: $(cat "$FREEZE_LOG")"
rel_expect_output "$GOUT" "freeze_verdict=noop"
if grep -q "already exists" "$FREEZE_LOG"; then
  fail "NO-OP skip-⑥ scenario: the ⑥ already-exists path executed during a NO-OP — ⑥⑦ were not skipped"
fi
echo "PASS release-ship semantics: NO-OP skips ⑥⑦ — an existing release for the same shipped pair does not fail the re-dispatch"

# h10/h11 — tag at a DIFFERENT SHA (lightweight + annotated peel) → explicit
# FAIL. THE boundary: tag existence alone is NEVER success (clobber 금지).
d="$(rel_make_state "$REL_P1")"
rel_ref_json commit "$SHA_OTHER" > "$d/ref_tag_v0.5.6.json"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -ne 0 ] || fail "different-SHA lightweight scenario rc=0 — tag existence ALONE must never be success (clobber boundary)"
grep -q "exists at different SHA" "$FREEZE_LOG" || fail "different-SHA lightweight log missing 'exists at different SHA'"
grep -q "clobber" "$FREEZE_LOG" || fail "different-SHA lightweight log missing the clobber-forbidden marker"
d="$(rel_make_state "$REL_P1")"
rel_ref_json tag "$SHA_TAGOID" > "$d/ref_tag_v0.5.6.json"
rel_tagobj_json "$SHA_TAGOID" "$SHA_OTHER" > "$d/tagobj_${SHA_TAGOID}.json"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -ne 0 ] || fail "different-SHA annotated scenario rc=0 — peel to a different commit must FAIL, not succeed"
grep -q "exists at different SHA" "$FREEZE_LOG" || fail "different-SHA annotated log missing 'exists at different SHA'"
echo "PASS release-ship semantics: tag at a DIFFERENT SHA (lightweight + annotated peel) → explicit FAIL — existence alone is never success"

# h12 — ⑦ SHA uniqueness preserved: a DIFFERENT tag peeling to the target FAILs
d="$(rel_make_state "$REL_P1")"
rel_ref_json commit "$SHA_TARGET" > "$d/ref_tag_v0.5.5.json"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -ne 0 ] || fail "⑦ uniqueness scenario rc=0 — another tag peeling to the target must FAIL (same SHA, different version STOP)"
grep -q "SHA uniqueness violated" "$FREEZE_LOG" || fail "⑦ uniqueness scenario log missing 'SHA uniqueness violated'"
echo "PASS release-ship semantics: ⑦ SHA uniqueness preserved — a different tag peeling to the target still FAILs"

# h13 — unclear tag-ref lookup (HTTP 500) → fail-closed
d="$(rel_make_state "$REL_P1")"
: > "$d/http500_tag_ref"
rel_run_freeze "$d" "v0.5.6" "$SHA_TARGET"
[ "$FREEZE_RC" -ne 0 ] || fail "⑤ inconclusive scenario rc=0 — HTTP 500 on the tag ref lookup must fail-closed"
grep -q "inconclusive" "$FREEZE_LOG" || fail "⑤ inconclusive scenario log missing 'inconclusive'"
echo "PASS release-ship semantics: tag ref lookup HTTP 500 → fail-closed inconclusive FAIL"

echo "release-ship freeze idempotency group: PASS — parsing contracts 4/4 + enumeration + negative control, live-script semantics 9/9 (NO-OP boundary: existence alone is never success)"

echo "test_workflow_jq_contracts: PASS — canary Q16 8/8 assertions, router Q17 2 fixtures (13 rows golden-exact), negative controls Q16/Q17 2/2, router Q19 fetch-fallback (gate 4 + block 5 cases + pre-fix 3), probe :220/:238 gates 8 cases + pre-fix 2, release-ship freeze idempotency (parsing 4+enum+control, live-script semantics 9)"

# ════════════════════════════════════════════════════════════════════════════
# 8. Q-P1 form-agnostic `gh api --paginate` contract (2026-11-02) — STRICT
#    APPEND group. Sections 1-7 and the release-ship group above are NOT
#    rewritten or renumbered; this group is appended at end-of-file so
#    parallel contract work cannot collide. Consequence: the pre-existing
#    overall summary echo above enumerates only the groups above it — the
#    script EXIT CODE is the single overall verdict (any failure here still
#    exits non-zero under set -euo pipefail).
#
#    Contract closed (docs/spec/gh_api_paginate_output_quirks.md Q-P1
#    closure): the consumer accepts BOTH valid `--paginate` output shapes
#      ① page-merged single array (measured, gh 2.102.0, top-level-array
#         endpoints — UNDOCUMENTED; Q19 measured 210 tags / 3 pages → 1 doc)
#      ② concatenated per-page documents (documented: cli/cli
#         pkg/cmd/api/api.go `gh api` Long help, Context7 /cli/cli
#         2026-11-02: "Each page is a separate JSON array or object.")
#    with byte-identical verdicts, and fails closed on every other shape. A
#    gh version pin is REJECTED as the remedy (a pin is avoidance, not a fix:
#    it trades shape drift for staleness + install cost). The ⑥/⑦ programs
#    under test are the LIVE extraction from the release-ship group's section
#    6a above (in scope — no re-extraction, no workflow text copied here; a
#    workflow revert or relocation fails closed before this group runs).
#    Fixtures + provenance: release_ship/capture_manifest_qp1_forms.json.
# ════════════════════════════════════════════════════════════════════════════

REL_MERGED_MP="$REL_FIX/rel_releases_merged_multipage_form.json"
REL_GARBAGE="$REL_FIX/rel_releases_garbage_stream.txt"
REL_QP1_MANIFEST="$REL_FIX/capture_manifest_qp1_forms.json"
[ -f "$REL_MERGED_MP" ] || config_error "missing $REL_MERGED_MP (Q-P1 page-merged single-array form)"
[ -f "$REL_GARBAGE" ] || config_error "missing $REL_GARBAGE (Q-P1 truncated-JSON negative control)"
[ -f "$REL_QP1_MANIFEST" ] || config_error "missing $REL_QP1_MANIFEST (Q-P1 fixture provenance SSOT)"

# 8a. ⑥ count — merged single-array form → goldens, byte-identical to the
#     documented two-document form (same logical content → same verdict).
n_mp_nomatch="$(jq -s --arg v "v0.5.7" "${REL_PROG[REL_N_SAME]}" < "$REL_MERGED_MP")"
n_tp_nomatch="$(cat "$REL_P1" "$REL_P2" | jq -s --arg v "v0.5.7" "${REL_PROG[REL_N_SAME]}")"
[ "$n_mp_nomatch" = "0" ] || fail "⑥ on the page-merged single-array form (no match): got '$n_mp_nomatch' want '0'"
[ "$n_mp_nomatch" = "$n_tp_nomatch" ] || fail "⑥ cross-form verdict mismatch (no match): merged form '$n_mp_nomatch' vs documented two-document form '$n_tp_nomatch' — the form-agnostic contract requires byte-identical verdicts"
n_mp_match="$(jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}" < "$REL_MERGED_MP")"
n_tp_match="$(cat "$REL_P1" "$REL_P2" | jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}")"
[ "$n_mp_match" = "1" ] || fail "⑥ on the page-merged single-array form (match): got '$n_mp_match' want '1' — flattening lost a merged-form row"
[ "$n_mp_match" = "$n_tp_match" ] || fail "⑥ cross-form verdict mismatch (match): merged form '$n_mp_match' vs two-document form '$n_tp_match'"
echo "PASS Q-P1 ⑥ count: merged single-array form → 0/1, byte-identical to the documented two-document form (cross-form equivalence)"

# 8b. ⑦ enumeration — same rows, same order, byte-identical across forms.
enum_mp="$(jq -r "${REL_PROG[REL_TAG_ENUM]}" < "$REL_MERGED_MP")"
enum_tp="$(cat "$REL_P1" "$REL_P2" | jq -r "${REL_PROG[REL_TAG_ENUM]}")"
[ "$enum_mp" = "$enum_tp" ] || fail "⑦ cross-form enumeration mismatch — merged form vs documented two-document form must yield identical rows in identical order"
[ "$(printf '%s\n' "$enum_mp" | wc -l)" = "3" ] || fail "⑦ enumeration on the merged form: want 3 rows, got: $enum_mp"
echo "PASS Q-P1 ⑦ enumeration: merged form rows byte-identical to the two-document form (3 rows, same order)"

# 8c. measured form — the verbatim live capture (0 releases → ONE empty array
#     document, gh 2.102.0) counts 0.
n_measured="$(jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}" < "$REL_FIX/rel_releases_p1_2026-11-02.json")"
[ "$n_measured" = "0" ] || fail "⑥ on the measured live capture: got '$n_measured' want '0'"
echo "PASS Q-P1 measured form: verbatim gh 2.102.0 capture (single empty array document) → 0"

# 8d. negative controls — every non-(array documents) shape fails closed, and
#     the pre-fix program's silent dependency on the MERGED form stays
#     observable (if the merged fixture loses a row, this control screams).
rc=0; jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}" < "$REL_NONARRAY" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "Q-P1 negative control: non-array document exited 0 — must fail closed"
rc=0; jq -s --arg v "v0.5.6" "${REL_PROG[REL_N_SAME]}" < "$REL_GARBAGE" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "Q-P1 negative control: truncated-JSON stream exited 0 — parse failure must fail closed"
old_mp="$(cat "$REL_MERGED_MP" | jq --arg v "v0.5.6" '[.[] | select(.tag_name == $v)] | length' 2>/dev/null)"
[ "$old_mp" = "1" ] || fail "Q-P1 pre-fix dependency control: on the merged single-array form the pre-fix ⑥ program must still print the single-line '1' it silently relied on — got '$old_mp' (merged fixture sanitized/lost a row?)"
echo "PASS Q-P1 negative controls: non-array doc + truncated JSON → fail-closed; pre-fix program's merged-form dependency (single-line '1') retained"

echo "Q-P1 form-agnostic paginate contract group: PASS — ⑥ cross-form goldens (0/1 × merged/two-document) + ⑦ cross-form equivalence + measured form + negative controls 2 + pre-fix dependency control 1"
