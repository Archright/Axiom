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
# Second invariant (2026-11-23): `.github/workflows/ci-cache-publisher.yml` is the
# ONLY workflow holding `cache-mode: write` (default-branch cache write authority).
# A step in it that executes a WORKSPACE-LOCAL action (`uses: ./...`) inside a job
# whose workspace can hold a dynamically checked-out tree runs CANDIDATE code with
# that write authority - the cache-poisoning surface. Such a job must therefore pin
# `with.ref: ${{ github.event.repository.default_branch }}` and must not re-point the
# workspace with a dynamic `git checkout` in a `run:` block. Rationale + the measured
# pre-change defect (`a-seed` executing the candidate tree's action.yml body, then
# `nimble install` running the candidate's axiom.nimble hooks) is inline at
# `check_publisher_exec_boundary`. This rule rides this gate instead of adding a new
# tool: `.gitignore` bans new `*.sh`/`*.py` files (Language Ban), and this validator
# is already wired into the push-admissibility recipe.
#
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
# Required-context placement rule (2026-11-26) — the deadlock / silent-pass
# pair on a REQUIRED check. Contract: `docs/spec/ci_admission_budget_contract.md`
# §4 R2/R3; the required set is read from `config/policy/merge_admission.json`
# in the BASE tree (this script is the TRUSTED copy; the candidate tree is only
# ever scanned, never asked what is required). R2: a required workflow must not
# carry `paths`, `paths-ignore`, or `branches-ignore` — a skipped workflow
# leaves its checks "Pending", so the requiring PR is blocked from merging. R3:
# a required JOB's `if:` may be only absent, `always()`, `!cancelled()`, or a
# `&&`-conjunction of those — a job skipped by `jobs.<id>.if` reports "Success"
# and does not block merging even as a required check, which is a SILENT pass.
# Scope is the (workflowPath, job) pair from the policy, never the job name
# (`.github/workflows/admission-check.yml` has a callee job of the same name
# that is not the required context) and never the whole workflow
# (`go-critical-rollup` and the attest lanes are sub-jobs and may be
# conditional). Locus, stated rather than faked: allow-list COVERAGE (does a
# present `branches` list still contain the trunk?) is NOT decided here — the
# policy records no trunk, and a second configuration is exactly what R2
# forbids; its failure mode is the same visible Pending deadlock, never a
# silent pass.
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
#   1 — bash syntax error(s), parse-poison violation(s), lane-stderr emission
#      violation(s), publisher exec-boundary violation(s), or required-context
#      placement violation(s) found (fail-closed;
#      exact workflow/job/step + reason printed); --self-test: the broken
#      snippet was NOT caught (gate itself broken)
#   2 — environment/configuration error (missing scan target directory,
#      python3 or PyYAML unavailable, unknown argument, extractor produced no
#      summary, required-context policy missing/unparsable/empty)

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
import glob, json, os, re, subprocess, sys, tempfile

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

def iter_steps(doc):
    if not isinstance(doc, dict) or "jobs" not in doc:
        return
    for jname, job in doc["jobs"].items():
        if not isinstance(job, dict):
            continue
        steps = job.get("steps")
        if not isinstance(steps, list):
            continue
        for i, step in enumerate(steps):
            if not isinstance(step, dict):
                continue
            yield jname, (step.get("name") or ("step#%d" % i)), step


# -- Required-context placement rules (2026-11-26, contract §4 R2/R3) -------
# Contract: `docs/spec/ci_admission_budget_contract.md` §4. Authority for the
# required set: `config/policy/merge_admission.json`, read from ROOT — that is
# the BASE tree, because bsec-integrity runs the TRUSTED copy of this file and
# points it at the candidate tree. The candidate never supplies its own
# required set (that would be self-certification).
#
# Two platform semantics make a required check stop being a gate, and neither
# is a silent local failure — they are documented GitHub behaviour:
#   R2  a required WORKFLOW skipped by a trigger filter (`paths`,
#       `paths-ignore`, `branches-ignore`) leaves its checks in "Pending", so
#       a PR requiring them is blocked from merging (deadlock, not a pass).
#       https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs
#   R3  a required JOB skipped by `jobs.<id>.if` reports its status as
#       "Success" and does not block merging — a SILENT pass on a required
#       check, which is strictly worse than a deadlock.
#       https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions
# R3 therefore admits exactly: absent, `always()`, `!cancelled()`, or a
# `&&`-conjunction of those. Venue selection belongs INSIDE the job via
# `github.event_name`, never in the job's `if:`.
#
# Scope is the REQUIRED JOB, keyed by (workflowPath, job) — not by job name and
# not by the whole workflow. Keying by name would false-fail
# `.github/workflows/admission-check.yml`, whose callee job `admission-check`
# is not the required context (the context is published by
# `admission-gate-v2.yml`); `go-critical-rollup` and the attest lanes are
# sub-jobs of a required workflow and are legitimately conditional.
#
# Locus (what this rule does NOT decide, stated instead of faked): the
# allow-list COVERAGE question — whether a present `pull_request.branches` /
# `merge_group.branches` list still contains the trunk — needs a trunk
# authority that does not exist in the policy (no `trunk` field; R2 forbids
# introducing a second configuration). It is review-enforced only, and its
# failure mode is the same visible Pending deadlock as R2, never a silent
# pass. `paths`/`paths-ignore`/`branches-ignore` have no legitimate use on a
# required workflow at all, so those are banned unconditionally.
POLICY_PATH = os.path.join(root, "config", "policy", "merge_admission.json")
MERGE_VENUES = ("pull_request", "pull_request_target", "merge_group")
BANNED_FILTERS = ("paths", "paths-ignore", "branches-ignore")
ADMISSIBLE_IF_ATOMS = ("always()", "!cancelled()")


def load_required_pairs():
    """Required (workflowPath, job) pairs from the BASE policy. Fail closed."""
    try:
        with open(POLICY_PATH, encoding="utf-8") as fh:
            pol = json.load(fh)
    except (OSError, ValueError) as e:
        print("validate_workflow_shell: required-context policy unreadable (%s: %s) — "
              "configuration error, fail closed" % (POLICY_PATH, e), file=sys.stderr)
        sys.exit(2)
    pairs = []
    for e in (pol.get("requiredValidations") or []):
        wp, job = e.get("workflowPath"), e.get("job")
        if isinstance(wp, str) and isinstance(job, str):
            pairs.append((wp, job))
    det = pol.get("requiredWorkflowDetection") or {}
    if isinstance(det.get("workflowPath"), str) and isinstance(det.get("verdictJob"), str):
        pairs.append((det["workflowPath"], det["verdictJob"]))
    if not pairs:
        # "missing does not equal valid empty" — an empty required set would
        # make every rule below vacuous.
        print("validate_workflow_shell: required-context policy declares no required "
              "(workflowPath, job) pairs (%s) — configuration error, fail closed"
              % POLICY_PATH, file=sys.stderr)
        sys.exit(2)
    return pairs


def policy_key(rel, scan_dir):
    """Map a scanned file to its policy workflowPath."""
    if scan_dir:
        return ".github/workflows/" + os.path.basename(rel)
    return rel.replace(os.sep, "/")


def _strip_parens(s):
    while s.startswith("(") and s.endswith(")"):
        depth = 0
        balanced = True
        for i, ch in enumerate(s):
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0 and i != len(s) - 1:
                    balanced = False
                    break
        if not balanced:
            break
        s = s[1:-1].strip()
    return s


def admissible_if(cond):
    """R3: (ok, normalized) for a required job's `if:` value."""
    if cond is None:
        return True, "absent"
    if cond is True:
        return True, "true"
    if not isinstance(cond, str):
        return False, repr(cond)
    s = cond.strip()
    while s.startswith("${{") and s.endswith("}}"):
        s = s[3:-2].strip()
    if not s:
        return False, cond
    atoms = [a.strip() for a in s.split("&&")]
    for a in atoms:
        if _strip_parens(a) not in ADMISSIBLE_IF_ATOMS:
            return False, cond
    return True, cond


def check_required_rules(doc, key, required_pairs):
    """R2/R3 violations for one scanned file (empty = the rules hold)."""
    jobs_required = sorted({job for wp, job in required_pairs if wp == key})
    if not jobs_required:
        return []
    if not isinstance(doc, dict):
        return ["required workflow is not a YAML mapping - the placement rules are "
                "undecidable (fail closed)"]
    out = []
    jobs = doc.get("jobs")
    if not isinstance(jobs, dict):
        return ["required workflow declares no `jobs` mapping - no required context "
                "can ever report"]
    on = doc.get("on", doc.get(True))
    if on is None:
        out.append("required workflow declares no `on:` triggers - its required context "
                   "can never report")
    elif isinstance(on, dict):
        for venue in MERGE_VENUES:
            cfg = on.get(venue)
            if not isinstance(cfg, dict):
                continue
            for key_name in BANNED_FILTERS:
                if key_name in cfg:
                    out.append(
                        "`%s.%s` on a REQUIRED workflow: a skipped workflow leaves its "
                        "checks in \"Pending\", so every PR requiring this context is "
                        "blocked from merging. A required workflow must not be filterable "
                        "away from a merge candidate; select the venue INSIDE the job from "
                        "`github.event_name` instead" % (venue, key_name))
    for job in jobs_required:
        jd = jobs.get(job)
        if not isinstance(jd, dict):
            out.append("required job `%s` is absent from this workflow - the required "
                       "context can never report (the queue stalls; it does not pass)" % job)
            continue
        ok, why = admissible_if(jd.get("if"))
        if not ok:
            out.append(
                "required job `%s` carries `if: %s`: a job skipped by `jobs.<id>.if` "
                "reports its status as \"Success\" and does not block merging, even as a "
                "required check. Admissible values are exactly: absent, `always()`, "
                "`!cancelled()`, or a `&&`-conjunction of those - decide the venue inside "
                "the job from `github.event_name`, never by skipping it" % (job, why))
    return out


# -- Publisher execution-boundary rule (2026-11-23) -----------------------
# `.github/workflows/ci-cache-publisher.yml` holds `cache-mode: write` (the only
# default-branch cache writer). Any step there that executes a WORKSPACE-LOCAL
# action (`uses: ./...`) inside a job whose workspace can hold a dynamically
# checked-out tree runs CANDIDATE code with default-branch write authority:
# the cache-poisoning surface. Invariant: such a job must pin
# `with.ref: ${{ github.event.repository.default_branch }}` and must not
# `git checkout` a dynamic ref inside a `run:` block.
# Measured 2026-11-23: the pre-change `a-seed` step ran
# `uses: ./.github/actions/setup-axiom-toolchain` right after
# `checkout(ref: steps.trees.outputs.head_sha)`, so the executed body was the
# candidate's `action.yml`, and an A-miss ran `nimble install`, executing the
# candidate's `axiom.nimble` NimScript hooks with cache write authority.
PUBLISHER_WF = "ci-cache-publisher.yml"
DEFAULT_BRANCH_REF = "${{ github.event.repository.default_branch }}"
DYNAMIC_REF_MARKERS = (
    "steps.",
    "github.event.workflow_run.",
    "github.event.pull_request.",
    "github.head_ref",
    "github.ref_name",
    "github.sha",
)
# A `uses:` is provenance-pinned only when it is a 40-hex commit sha. Anything
# else (a tag, a branch, `main`, `refs/pull/<n>/merge`, or a `${{ }}`
# expression) can be re-pointed after review, so the reviewed bytes are not
# the executed bytes. `./`-relative actions are handled by the checkout rule
# below instead, because their provenance is the checked-out tree.
SHA_PIN_RE = re.compile(r"^[^@]+@[0-9a-f]{40}$")
# Workspace re-point commands that can change the bytes a `uses: ./...` runs.
# `git -C <path>` and `git --git-dir` prefixes are matched so the bypass forms
# measured on 2026-11-23 (`git -C . checkout`, `git switch --detach`,
# `git worktree add`, `git reset --hard`) are all covered.
REPOINT_RE = re.compile(
    r"\bgit\b[^|;&]*\b(checkout|switch|worktree|reset|read-tree|restore)\b")


def check_publisher_exec_boundary(doc, rel):
    """Return a list of violation messages (empty = invariant holds)."""
    if os.path.basename(rel) != PUBLISHER_WF:
        return []
    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        return ["`jobs` mapping absent - the exec-boundary invariant is undecidable "
                "(fail closed)"]
    out = []
    for jname, job in doc["jobs"].items():
        steps = [s for _, _, s in iter_steps({"jobs": {jname: job}})]
        # Rule D: every non-`./` action must be pinned to a 40-hex commit sha.
        # A tag or branch can be re-pointed after review, so the reviewed bytes
        # are not the executed bytes; `@refs/pull/<n>/merge` would even execute
        # candidate code inside this write-capable workflow. Job-level
        # `uses:` (reusable workflows) is checked too: iter_steps only walks
        # `steps`, so it would otherwise be invisible.
        job_uses = job.get("uses")
        if isinstance(job_uses, str):
            if not job_uses.startswith("./") and not SHA_PIN_RE.match(job_uses):
                out.append("job `%s` calls a reusable workflow at a non-sha ref "
                           "`%s` - a mutable ref can execute unreviewed code with "
                           "default-branch cache write authority" % (jname, job_uses))
        for s in steps:
            u = str(s.get("uses", ""))
            if u and not u.startswith("./") and not SHA_PIN_RE.match(u):
                out.append("job `%s` uses `%s` - not pinned to a 40-hex commit sha, "
                           "so the executed bytes are not the reviewed bytes "
                           "(fail closed)" % (jname, u))
        local = [s for s in steps if str(s.get("uses", "")).startswith("./")]
        if not local:
            continue
        refs = []
        for s in steps:
            if str(s.get("uses", "")).startswith("actions/checkout@"):
                with_ = s.get("with")
                ref = (with_ or {}).get("ref") if isinstance(with_, dict) else None
                refs.append(None if ref is None else str(ref))
        dyn = [r for r in refs if r is not None
               and any(m in r for m in DYNAMIC_REF_MARKERS)]
        if dyn:
            out.append("job `%s` executes `uses: ./...` (local action) while checking out "
                       "a candidate/dynamic ref %s - candidate code would run with "
                       "default-branch cache write authority" % (jname, dyn))
        if DEFAULT_BRANCH_REF not in refs:
            out.append("job `%s` executes `uses: ./...` but no checkout pins "
                       "`with.ref: %s` (refs=%s) - the executed body's provenance is "
                       "not the default branch" % (jname, DEFAULT_BRANCH_REF, refs))
        for s in steps:
            body = s.get("run")
            if not isinstance(body, str):
                continue
            for line in body.splitlines():
                st = line.strip()
                if st.startswith("#"):
                    continue
                # Rule C, widened: any workspace re-point command that can change
                # the bytes a `uses: ./...` will execute. The literal `git checkout`
                # form alone was bypassable via `git -C . checkout`,
                # `git switch --detach`, `git worktree add`, `git reset --hard`.
                if REPOINT_RE.search(st) and ("$" in st or "`" in st):
                    out.append("job `%s` executes `uses: ./...` and also re-points the "
                               "workspace with a dynamic workspace command (%s) - bypass "
                               "path around the fixed-ref rule" % (jname, st[:120]))
    return out


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
policy_fails = 0
REQUIRED_PAIRS = load_required_pairs()
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
        for msg in check_required_rules(doc, policy_key(rel, scan_dir), REQUIRED_PAIRS):
            policy_fails += 1
            print("FAIL:%s:<required-context-rules>" % rel)
            print("  " + msg)
        for msg in check_publisher_exec_boundary(doc, rel):
            fails += 1
            print("FAIL:%s:<publisher-exec-boundary>" % rel)
            print("  " + msg)
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
print("SUMMARY: run blocks checked=%d failures=%d lane-guard violations=%d "
      "required-context violations=%d"
      % (total, fails, guard_fails, policy_fails))
sys.exit(1 if (fails or guard_fails or policy_fails) else 0)
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

# required-context placement rules round-trip (contract §4 R2/R3, 2026-11-26):
# a required workflow carrying a banned trigger filter, and a required job
# carrying a disjunctive `if:`, must both FAIL with the
# <required-context-rules> attribution; the admissible `if:` forms and a
# non-required file with the same banned filter must PASS. The fixture carries
# the unquoted `on:` key so the PyYAML boolean-key quirk (YAML 1.1: `on` →
# True) is exercised, not bypassed.
TEMPLATE = (
    "name: fixture\n"
    "on:\n"
    "  pull_request:\n"
    "  merge_group:\n"
    "    types: [checks_requested]\n"
    "jobs:\n"
    "  bsec-integrity:\n"
    "    runs-on: ubuntu-latest\n"
    "%s"
    "    steps:\n"
    "      - name: noop\n"
    "        run: echo ok\n"
)
FILTER_CASE = (
    "name: fixture\n"
    "on:\n"
    "  pull_request:\n"
    "    paths:\n"
    "      - 'docs/**'\n"
    "  merge_group:\n"
    "    types: [checks_requested]\n"
    "    branches-ignore:\n"
    "      - main\n"
    "jobs:\n"
    "  bsec-integrity:\n"
    "    runs-on: ubuntu-latest\n"
    "    steps:\n"
    "      - name: noop\n"
    "        run: echo ok\n"
)
cases = [
    ("r2_paths+branches-ignore", "bsec-integrity.yml", FILTER_CASE, True,
     ("pull_request.paths", "merge_group.branches-ignore")),
    ("r3_venue_disjunction", "bsec-integrity.yml",
     TEMPLATE % "    if: '${{ github.event_name == \"pull_request\" }}'\n", True, ("if:",)),
    ("r3_stage_conjunction", "bsec-integrity.yml",
     TEMPLATE % "    if: '${{ always() && inputs.stage == \"attest\" }}'\n", True, ("if:",)),
    ("r3_absent", "bsec-integrity.yml", TEMPLATE % "", False, ()),
    ("r3_not_cancelled", "bsec-integrity.yml",
     TEMPLATE % "    if: '${{ !cancelled() }}'\n", False, ()),
    ("r3_conjunction_admissible", "bsec-integrity.yml",
     TEMPLATE % "    if: '${{ always() && !cancelled() }}'\n", False, ()),
    ("r3_bare_always", "bsec-integrity.yml",
     TEMPLATE % "    if: 'always()'\n", False, ()),
    ("scope_non_required_file", "unrelated.yml", FILTER_CASE, False, ()),
]
for label, fname, body, expect_fail, needles in cases:
    with tempfile.TemporaryDirectory(prefix="wfshchk-selftest-req-") as td:
        with open(os.path.join(td, fname), "w", encoding="utf-8") as fh:
            fh.write(body)
        r = subprocess.run(["bash", script, "--scan-dir", td],
                           capture_output=True, text=True)
        out = r.stdout + r.stderr
        caught = "<required-context-rules>" in out
        missing = [n for n in needles if n not in out]
        ok = (caught == expect_fail) and not missing and \
            ((r.returncode != 0) == expect_fail)
        print("self-test required-context %-28s expect_fail=%-5s caught=%-5s rc=%d -> %s"
              % (label, expect_fail, caught, r.returncode, "OK" if ok else "BROKEN"))
        if not ok:
            if missing:
                print("  missing attribution: %s" % ", ".join(missing))
            print(out)
            sys.exit(1)

print("self-test: PASS")
sys.exit(0)
PYEOF
}

if [ "$SELF_TEST" -eq 1 ]; then
  echo "== validate_workflow_shell: self-test =="
  if self_test; then
    echo "validate_workflow_shell: SELF-TEST PASS — broken snippet caught, valid snippet accepted, lane-guard negative FAILs with guard attribution / positive passes, required-context matrix (R2 filters + R3 job-if) FAILs on violation and PASSes on every admissible form"
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