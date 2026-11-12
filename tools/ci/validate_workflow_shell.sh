#!/usr/bin/env bash
#
# validate_workflow_shell.sh — workflow `run:` shell-block syntax gate (bash -n).
#
# Invariant: EVERY `run:` block of EVERY .github/workflows/*.yml in this repo
# must pass `bash -n` (syntax-only parse) at the OID being pushed/merged.
# A single broken block (e.g. a missing `fi` → "unexpected end of file") would
# otherwise break the production runner at execution time. This class BROKE
# production twice:
#   * certificate-mint.yml step (2a) — missing `fi` → bash EOF syntax error,
#     proven at gate run 36250541060.
#   * a `cmp` filename bug class — exact filename/argument mismatch surfaced
#     only at execution.
# The gate is fail-closed: ANY syntax error in ANY block → exit 1; a workflow
# with NO run blocks, an unparsable YAML file, or a missing extractor
# dependency is also a failure (exit 2) — never a silent pass.
#
# Design (zero new external binary dependencies, deterministic):
#   * Python3 + yaml.safe_load extracts every `run:` scalar from
#     jobs.*.steps[*].run — the same extraction shape that caught the mint bug
#     (no sed/awk re-implementation: YAML block scalars, quoting and folded
#     forms are handled by the parser, not by regex).
#   * Each block is written to a temp file and checked with `bash -n` — the
#     exact shell the GitHub runner uses (no `shell:` overrides exist in the
#     repo's workflows; the default runner shell is bash → no false-positive
#     class).
#   * `${{ }}` expressions pass `bash -n` (verified empirically: they parse as
#     parameter-expansion-shaped tokens; bash -n never rejects them), so no
#     expression sanitization is needed — unlike actionlint, which must strip
#     `${{ }}` before shellcheck (its docs/checks.md).
#
# Tool-choice rationale — external tools were researched and REJECTED:
#   actionlint (/rhysd/actionlint, Context7 docs: install.md, checks.md) is the
#   canonical mature static checker for workflow files, but it installs as a
#   prebuilt Go binary (`gh release download …_linux_amd64.tar.gz` or a curl
#   download script) and its run-block checking depends on a SEPARATE
#   shellcheck binary. Both are external binary downloads → supply-chain +
#   determinism violation for this repo's hermetic gate suite. The zero-dep
#   python3 + `bash -n` core (bash already present on every runner that
#   executes these blocks) closes the exact observed defect class with no new
#   binaries. If a full workflow linter is ever wanted, actionlint remains the
#   canonical choice (Context7 /rhysd/actionlint, trust 9.7, 3.1k★) — revisit
#   under a separate pinned-binary policy.
#
# Parse-poison rule (2026-10-14) — GitHub rejects a workflow whose `run:`
# scalar carries an expression token AND exceeds the expression-length cap at
# CALL-GRAPH PLANNING time: HTTP 422 "Exceeded max expression length 21000",
# 0 jobs, no check-run, and the workflow registry name falls back to the raw
# file path — a required check never reports and the venue stalls (2026-10-12
# merge-queue outage, PR #780 class). PyYAML AND actionlint both PASS such a
# file, so no existing local tool catches it
# (docs/spec/gh_run_observation_quirks.md Q4; org parse-probe oracle:
# 25,954-char tokenized FAIL vs 26,282-char token-free PASS). Rule: for every
# `run:` scalar (block or plain form), an expression token present AND
# length > 21000 → FAIL with file/job/step and the measured length. Boundary
# note: whether the platform accepts or rejects a scalar of EXACTLY 21,000
# chars is not locally determinable (">" vs ">="); this gate mirrors the
# platform error text and fails on > 21000. The exact boundary is decidable
# only by the org parse-probe dispatch oracle.
#
# Lane-stderr emission rule (2026-10-15) — the merge_group evidence-loss class:
# a workflow that executes parallel lanes with `… > "$d/run.log" 2>&1` redirects
# and NEVER re-emits the per-lane transcript loses the failure stderr entirely —
# the step log then carries only marker/duration rows and a bare exit-1 (C1
# audit, docs/evidence/slice_c_p1_evidence_audit_2026-10-15.md: the reverted
# 4-lane blob 2c94c991418dfd89e665ce4ec3efdcc86ffd2e93 redirected at :1199 and
# never re-emitted; the 5 merge_group runs of 2026-10-14 on that lineage are the
# only PARTIAL-evidence rows in the 2026-10-13→15 failure population). Rule: a
# scanned workflow containing a lane pattern (`go-critical-lanes`, `lane_run`,
# or a `>\s*"?$d/run.log` redirect) MUST also carry BOTH emission markers —
# (a) transcript disclosure: a live `| tee` on the lane invocation (S2 recipe,
# queue-probe f1e600965) or a failure re-emission `cat …run.log` (2555ab966
# recipe), AND (b) an `if: always()` actions/upload-artifact step whose name or
# path covers the lane logs. Lane pattern without markers → FAIL citing the
# prereg condition (docs/evidence/merge_latency_decision_prereg_2026-10-14.md
# §8, amendment 2026-10-15) and the two recipes. Detection is raw-text for the
# lane patterns (the pattern set is textual by definition) and parser-based for
# the upload marker (steps are walked via the same yaml.safe_load tree as the
# run blocks — no regex over step semantics).
#
# Usage:   validate_workflow_shell.sh [--self-test] [--scan-dir <dir>] [--max-report]
#   --scan-dir <dir>  scan <dir>/*.yml instead of .github/workflows (fixture
#                     harness entry; identical rules, identical fail-closed
#                     behavior; relative paths resolve against the repo root)
#   --max-report      measurement mode: emit "MAX:<file>:<len>:<job>:<step>"
#                     per scanned file — the max TOKENIZED run-scalar length
#                     (0 when a file has no tokenized scalar). No bash -n and
#                     no verdict; exit 1 only on unparsable YAML (fail-closed).
# No network. Deterministic: same tree → same verdict. Temp files under
# mktemp -d, removed on exit.
#
# Exit codes:
#   0 — every run: block parsed cleanly and no parse-poison violation (block
#      count printed); --self-test: broken snippet caught AND valid snippet
#      accepted; --max-report: report emitted
#   1 — bash syntax error(s), parse-poison violation(s), or lane-stderr emission
#      violation(s) found (fail-closed;
#      exact workflow/job/step + reason printed); --self-test: the broken
#      snippet was NOT caught (gate itself broken)
#   2 — environment/configuration error (missing scan target directory,
#      python3 or PyYAML unavailable, unknown argument, extractor produced no
#      summary)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

SELF_TEST=0
MAX_REPORT=0
SCAN_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --self-test) SELF_TEST=1 ;;
    --max-report) MAX_REPORT=1 ;;
    --scan-dir)
      if [ $# -lt 2 ]; then
        echo "validate_workflow_shell: --scan-dir requires a directory argument (configuration error — fail closed)" >&2
        exit 2
      fi
      SCAN_DIR="$2"
      shift
      ;;
    *)
      echo "validate_workflow_shell: unknown argument '$1' (usage: validate_workflow_shell.sh [--self-test] [--scan-dir <dir>] [--max-report])" >&2
      exit 2
      ;;
  esac
  shift
done

if [ -n "$SCAN_DIR" ]; then
  [ -d "$SCAN_DIR" ] || {
    echo "validate_workflow_shell: --scan-dir '$SCAN_DIR' is not a directory under $ROOT (configuration error — fail closed)" >&2
    exit 2
  }
else
  [ -d .github/workflows ] || {
    echo "validate_workflow_shell: .github/workflows missing under $ROOT (configuration error — fail closed)" >&2
    exit 2
  }
fi
command -v python3 >/dev/null 2>&1 || {
  echo "validate_workflow_shell: python3 not on PATH (configuration error — fail closed)" >&2
  exit 2
}
python3 -c 'import yaml' 2>/dev/null || {
  echo "validate_workflow_shell: python3 yaml (PyYAML) unavailable (configuration error — fail closed)" >&2
  exit 2
}

# ── core check ──────────────────────────────────────────────────────────────
# Extracts every run: block from the scanned *.yml (sorted) with
# yaml.safe_load and (a) enforces the parse-poison rule — a scalar carrying an
# expression token and longer than 21,000 chars FAILs before it can reach a
# planning-time platform rejection — then (b) runs `bash -n` on every other
# block. Emits one PASS:/FAIL: line per block ("workflow:job:step"), FAIL
# lines followed by the reason (rule detail or bash stderr), and a final
# "SUMMARY: run blocks checked=N failures=M" line. Exit: 0 = clean,
# 1 = at least one failure, 2 = environment error. In --max-report mode no
# verdict is issued: one "MAX:<file>:<len>:<job>:<step>" line per file and a
# "SUMMARY: files=N tokenized-max-overall=M" line instead.
# ---------------------------------------------------------------------------
check_workflows() {
  python3 - "$ROOT" "$SCAN_DIR" "$MAX_REPORT" <<'PYEOF'
import glob, os, re, subprocess, sys, tempfile

root, scan_dir, max_report = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
wf_dir = scan_dir if scan_dir else os.path.join(root, ".github", "workflows")
wfs = sorted(glob.glob(os.path.join(wf_dir, "*.yml")))
if not wfs:
    print("validate_workflow_shell: no *.yml found under %s (configuration error — fail closed)" % wf_dir, file=sys.stderr)
    sys.exit(2)

import yaml

# parse-poison constants (docs/spec/gh_run_observation_quirks.md Q4). GitHub
# applies the 21,000-char expression-length cap to a run scalar iff it carries
# an expression token; exceeding the cap is a planning-time HTTP 422 rejection
# with 0 jobs. Whether EXACTLY 21,000 chars passes or fails is not locally
# determinable; the rule mirrors the platform error text and fails on >.
EXPR_TOKEN = "${{"
EXPR_LEN_CAP = 21000

# lane-stderr emission rule (header comment "Lane-stderr emission rule,
# 2026-10-15"; prereg §8 amendment). Lane patterns are textual by definition —
# raw-text over the whole workflow file; the upload marker is structural —
# walked from the parsed step tree.
LANE_PATTERNS = [
    ("go-critical-lanes", None),
    ("lane_run", None),
    (">…$d/run.log redirect", re.compile(r'>\s*"?\$d/run\.log')),
]
# disclosure (a): live tee on the lane invocation — the tee line must name the
# lane (or its run.log); a `| tee` onto GITHUB_STEP_SUMMARY elsewhere in the
# file does not disclose lane output. OR failure re-emission `cat …run.log`.
LANE_HINT_RE = re.compile(r'lane|run\.log', re.IGNORECASE)
TEE_LINE_RE = re.compile(r'\|\s*tee\b')
CAT_RERUN_RE = re.compile(r'\bcat\b[^\n]*run\.log')
UPLOAD_HINTS = ("go-critical-lanes", "run.log", "lane")

def has_lane_pattern(text):
    return [name for name, rx in LANE_PATTERNS
            if (rx.search(text) if rx else name in text)]

def has_transcript_disclosure(text):
    if CAT_RERUN_RE.search(text):
        return True
    return any(TEE_LINE_RE.search(line) and LANE_HINT_RE.search(line)
               for line in text.splitlines())

def has_always_upload(doc):
    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        return False
    for job in doc["jobs"].values():
        if not isinstance(job, dict) or not isinstance(job.get("steps"), list):
            continue
        for step in job["steps"]:
            if not isinstance(step, dict):
                continue
            uses = step.get("uses")
            if not isinstance(uses, str) or "upload-artifact" not in uses:
                continue
            cond = step.get("if")
            if not isinstance(cond, str) or "always()" not in cond:
                continue
            with_ = step.get("with")
            if not isinstance(with_, dict):
                continue
            blob = " ".join(v for v in with_.values() if isinstance(v, str))
            if any(hint in blob for hint in UPLOAD_HINTS):
                return True
    return False

def iter_run_steps(doc):
    if not isinstance(doc, dict) or "jobs" not in doc:
        return
    for jname, job in doc["jobs"].items():
        if not isinstance(job, dict):
            continue
        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        for i, step in enumerate(steps):
            if not isinstance(step, dict) or "run" not in step:
                continue
            yield jname, (step.get("name") or ("step#%d" % i)), step["run"]

fails = 0
if max_report:
    overall = 0
    for wf in wfs:
        rel = os.path.relpath(wf, root)
        try:
            with open(wf, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as e:
            print("FAIL:%s:<unparsable-yaml>" % rel)
            print("  " + str(e).splitlines()[0])
            fails += 1
            continue
        best, best_loc = 0, "-"
        for jname, sname, body in iter_run_steps(doc):
            if isinstance(body, str) and EXPR_TOKEN in body and len(body) > best:
                best, best_loc = len(body), "%s:%s" % (jname, sname)
        overall = max(overall, best)
        print("MAX:%s:%d:%s" % (rel, best, best_loc))
    print("SUMMARY: files=%d tokenized-max-overall=%d" % (len(wfs), overall))
    sys.exit(1 if fails else 0)

total = 0
guard_fails = 0
with tempfile.TemporaryDirectory(prefix="wfshchk-") as td:
    for wf in wfs:
        rel = os.path.relpath(wf, root)
        try:
            with open(wf, encoding="utf-8") as fh:
                text = fh.read()
                doc = yaml.safe_load(text)
        except yaml.YAMLError as e:
            print("FAIL:%s:<unparsable-yaml>" % rel)
            print("  " + str(e).splitlines()[0])
            fails += 1
            continue
        lane_hits = has_lane_pattern(text)
        if lane_hits and not (has_transcript_disclosure(text)
                              and has_always_upload(doc)):
            missing = []
            if not has_transcript_disclosure(text):
                missing.append("transcript disclosure (live '| tee' on the lane "
                               "invocation, or failure re-emission 'cat …run.log' "
                               "into the step log)")
            if not has_always_upload(doc):
                missing.append("always-upload ('if: always()' on an "
                               "actions/upload-artifact step whose name/path "
                               "covers the lane logs)")
            guard_fails += 1
            print("FAIL:%s:<lane-stderr-guard>" % rel)
            print("  lane-stderr guard: lane execution pattern present (%s) but mandatory "
                  "emission marker(s) missing: %s"
                  % (", ".join(lane_hits), "; ".join(missing)))
            print("  Parallel-lane output redirected to a per-lane run.log and never "
                  "re-emitted loses the failure transcript — the 2026-10-13..14 merge_group "
                  "evidence-loss class (reverted 4-lane blob 2c94c991418dfd89e665ce4ec3efdcc86ffd2e93: "
                  "run.log redirect never re-emitted; the 5 merge_group runs of 2026-10-14 on "
                  "that lineage are PARTIAL-evidence rows).")
            print("  MANDATORY prereg promotion condition for any re-parallelization "
                  "(docs/evidence/merge_latency_decision_prereg_2026-10-14.md §8, amendment "
                  "2026-10-15): lane stdout/stderr live-tee'd or re-emitted, AND lane logs "
                  "uploaded under `if: always()`.")
            print("  Recipe: live tee = Slice B S2 (queue-probe f1e600965, `nim … 2>&1 | tee "
                  "\"$d/run.log\"`); re-emission + always-upload = "
                  "2555ab966e35e8a5023c28e87c1836b1744bd7a9 (fix/go-critical-cold-race-residual, "
                  "'[check] Upload GO-critical lane logs (forensics — always)' step).")
        for jname, sname, body in iter_run_steps(doc):
            total += 1
            if not isinstance(body, str):
                print("FAIL:%s:%s:%s" % (rel, jname, sname))
                print("  run: value is not a string (yaml type: %s)" % type(body).__name__)
                fails += 1
                continue
            if EXPR_TOKEN in body and len(body) > EXPR_LEN_CAP:
                fails += 1
                print("FAIL:%s:%s:%s" % (rel, jname, sname))
                print("  parse-poison: tokenized run scalar length=%d exceeds expression cap %d"
                      " (planning-time HTTP 422 'Exceeded max expression length 21000' class:"
                      " 0 jobs, no check-run; docs/spec/gh_run_observation_quirks.md Q4;"
                      " the >%d vs >=%d boundary is decidable only by the org parse-probe oracle)"
                      % (len(body), EXPR_LEN_CAP, EXPR_LEN_CAP, EXPR_LEN_CAP))
                continue
            p = os.path.join(td, "block_%d.sh" % total)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(body)
                if body and not body.endswith("\n"):
                    fh.write("\n")
            r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
            if r.returncode != 0:
                fails += 1
                print("FAIL:%s:%s:%s" % (rel, jname, sname))
                for line in r.stderr.splitlines():
                    print("  " + line)
            else:
                print("PASS:%s:%s:%s" % (rel, jname, sname))
print("SUMMARY: run blocks checked=%d failures=%d lane-guard violations=%d"
      % (total, fails, guard_fails))
sys.exit(1 if (fails or guard_fails) else 0)
PYEOF
}

# ── self-test ───────────────────────────────────────────────────────────────
# Feeds a deliberately broken block (`if true; then` with no `fi` — the exact
# mint defect class) and a valid block through the same python/bash pipeline.
# The gate must FAIL on the broken one and PASS on the valid one.
# ---------------------------------------------------------------------------
self_test() {
  python3 - "$SCRIPT_DIR/validate_workflow_shell.sh" <<'PYEOF'
import os, subprocess, sys, tempfile
cases = [
    ("if true; then", True),      # missing fi → bash EOF syntax error (mint class)
    ("echo ok\n", False),
]
with tempfile.TemporaryDirectory(prefix="wfshchk-selftest-") as td:
    for i, (body, expect_fail) in enumerate(cases):
        p = "%s/t.sh" % td
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(body)
            if body and not body.endswith("\n"):
                fh.write("\n")
        r = subprocess.run(["bash", "-n", p], capture_output=True, text=True)
        ok = (r.returncode != 0) == expect_fail
        print("self-test case %d (%s): bash -n exit=%d expect_fail=%s -> %s"
              % (i, body.strip().replace("\n", "\\n"), r.returncode, expect_fail,
                 "OK" if ok else "BROKEN"))
        if not ok:
            print("  stderr: " + r.stderr.strip())
            sys.exit(1)

# lane-stderr emission rule round-trip (prereg 2026-10-14 §8, 2026-10-15): the
# same lane workflow WITHOUT emission markers must FAIL with the
# <lane-stderr-guard> attribution, and WITH re-emission + always-upload must
# PASS the whole scan.
script = sys.argv[1]
RUN_BODY = (
    "set -e\n"
    'LANE_ROOT=/tmp/go-critical-lanes\n'
    'lane_run() { local slug="$1"; local d="$LANE_ROOT/$slug"; mkdir -p "$d"; }\n'
    'make test-fast-one T=tests/unit/x.nim > "$d/run.log" 2>&1 || rc=$?\n'
)
neg = (
    "name: lane-guard-negative\n"
    "jobs:\n"
    "  attest:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: go\n"
    "        run: |\n"
    + "".join("          %s\n" % ln for ln in RUN_BODY.splitlines())
)
pos = (
    "name: lane-guard-positive\n"
    "jobs:\n"
    "  attest:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: go\n"
    "        run: |\n"
    + "".join("          %s\n" % ln for ln in RUN_BODY.splitlines())
    + '          if [ "$rc" -ne 0 ] && [ -f "$d/run.log" ]; then cat "$d/run.log"; fi\n'
    "      - name: upload\n"
    "        if: always()\n"
    "        uses: actions/upload-artifact@v4\n"
    "        with:\n"
    "          name: lane-logs\n"
    "          path: /tmp/go-critical-lanes/**\n"
)
with tempfile.TemporaryDirectory(prefix="wfshchk-selftest-lane-") as td:
    for name, body in (("lane_guard_negative.yml", neg),
                       ("lane_guard_positive.yml", pos)):
        with open(os.path.join(td, name), "w", encoding="utf-8") as fh:
            fh.write(body)
    r = subprocess.run(["bash", script, "--scan-dir", td],
                       capture_output=True, text=True)
    out = r.stdout + r.stderr
    import re as _re
    neg_guard = _re.search(r"^FAIL:\S*lane_guard_negative\.yml:<lane-stderr-guard>$",
                           out, _re.M) is not None
    pos_pass = (_re.search(r"^FAIL:\S*lane_guard_positive\.yml:", out, _re.M) is None
                and _re.search(r"^PASS:\S*lane_guard_positive\.yml:", out, _re.M) is not None)
    ok = r.returncode == 1 and neg_guard and pos_pass
    print("self-test lane-guard: negative-guard-FAIL=%s positive-PASS=%s scan-rc=%d -> %s"
          % (neg_guard, pos_pass, r.returncode, "OK" if ok else "BROKEN"))
    if not ok:
        print(out)
        sys.exit(1)

print("self-test: PASS")
sys.exit(0)
PYEOF
}

if [ "$SELF_TEST" -eq 1 ]; then
  echo "== validate_workflow_shell: self-test =="
  if self_test; then
    echo "validate_workflow_shell: SELF-TEST PASS — broken snippet caught, valid snippet accepted, lane-guard negative FAILs with guard attribution / positive passes"
    exit 0
  fi
  echo "validate_workflow_shell: SELF-TEST FAIL — gate did not fail closed on broken snippet" >&2
  exit 1
fi

if [ "$MAX_REPORT" -eq 1 ]; then
  echo "== validate_workflow_shell: tokenized run-scalar max report (measurement mode — no verdict) =="
else
  echo "== validate_workflow_shell: bash -n + parse-poison rule over .github/workflows/*.yml run blocks =="
fi
BODY_OUT="$(check_workflows)" || BODY_RC=$?
BODY_RC="${BODY_RC:-0}"
printf '%s\n' "$BODY_OUT"

SUMMARY="$(printf '%s\n' "$BODY_OUT" | sed -n 's/^SUMMARY: //p')"
if [ -z "$SUMMARY" ]; then
  echo "validate_workflow_shell: extractor produced no summary (configuration error — fail closed)" >&2
  exit 2
fi

if [ "$BODY_RC" -ne 0 ]; then
  echo "validate_workflow_shell: FAIL — $SUMMARY (fail-closed)" >&2
  exit 1
fi
echo "validate_workflow_shell: PASS — $SUMMARY"
exit 0