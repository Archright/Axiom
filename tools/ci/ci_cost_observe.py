#!/usr/bin/env python3
"""CI cost observation — collect / freeze / aggregate (GET-only Reporter).

Contract (WP-B 1단계, 2026-11-02):
  * 3-stage CLI. One observation = one immutable snapshot directory:
        data/ci_cost/<obs_id>/
          collection.log.json   per-request log (endpoint, params, page,
                                http_status, etag, fetched_at_utc, ledger rows
                                range, rate_remaining) — written by collect
          ledger/*.jsonl        canonical extracted rows, one JSON object per
                                line (census ledger convention:
                                data/ci_provider/census_20261101T125932Z/)
          manifest.json         census-style manifest: subject, parameters,
                                window, population, integrity, ledger_sha256
                                (freeze: written once, chmod 0444, never
                                rewritten — re-freeze is refused)
  * collect — gh api GET ONLY (AGENTS.md §2.4 native client, read-only):
      (a) org billing usage  /orgs/<org>/settings/billing/usage?year=&month=&per_page=100
          (explicit page loop, per-page ETag)
      (b) org budgets        /orgs/<org>/settings/billing/budgets
      (c) repo workflow runs /repos/<repo>/actions/runs?created=<6h subwindow>
          — complete pagination per subwindow; a subwindow whose total_count
          exceeds the single-query pagination budget is recursively halved
          (silent-truncation guard, pr_latency_attribution.py precedent);
          total_count alone is NEVER trusted (measured cap artifact: whole-repo
          filtered queries report total_count=2500 exactly regardless of real
          volume).
      (d) per-run jobs       /repos/<repo>/actions/runs/<id>/jobs?per_page=100&filter=all
          — bounded deterministic stride sample over named --jobs-window
          windows (census convention: attempt rows appear as separate rows)
      (e) merged PRs         /repos/<repo>/pulls?state=closed&sort=updated&direction=desc
          filtered by merged_at in window; each merge_commit_sha verified via
          /commits/<sha> parents==2 (landing truth per landing_observe.sh).
      (f) admission latency  delegates to tools/ci/merge_latency_audit.sh
          (--mla-since/--mla-until; that tool is GET-only) — outputs land in
          the snapshot as mla/ci_cost_mla.{runs.jsonl,summary.json}.
    ETag reuse: with --reuse-from PREV_OBS, every request is conditional
    (If-None-Match). A 304 page copies the previous snapshot's ledger rows —
    the previous snapshot body is reused, nothing is re-fetched. A re-query
    whose live values differ is NEVER a determinism violation (accrual / new
    runs); it is recorded as its own new observation id.
  * freeze — validates every ledger row (schema keys, Q18 pollution: any row
    carrying "message" without the endpoint's required keys is a HARD-FAIL),
    computes ledger_sha256, writes manifest.json once (chmod 0444).
  * aggregate — reads ONLY the snapshot (manifest + ledger + mla files).
    Live queries are forbidden by construction. Identical snapshot directory +
    identical parameters => byte-identical output (no wall-clock, no RNG;
    sorted iteration; fixed rounding).
    v2 (TOOL_VERSION 2.0.0, aggregate schema /2): landing counts only
    verified landings to main (base_ref=="main" + 2-parent native MERGE;
    definition in landing.verified_landing_definition — checks-green and
    merge-queue-pass are GitHub merge-admission guarantees this tool does
    not re-adjudicate); stats_block carries p95; waste rows carry
    착지 기여도 / 변경 위험 grades plus the required-5-checks non-target
    footnote in waste.md; waste_coverage block quantifies what share of
    billed usage the waste table covers (B2 representativeness premise);
    --derived-manifest writes a replay manifest recording the tool version
    (TOOL_VERSION + tool sha256) for derived_v2-style replay outputs.
  * Authority: Reporter only (AGENTS.md §2.3). Emits no merge verdict, changes
    no gate; outputs never override GitHub's merge-admission judgment or the
    billing system. Dollar figures from the usage API are ACTUAL billed
    (net/gross amounts as reported); public-rate conversions appear only as
    clearly-labeled estimates (추정 참고치), never as actual cash claims.
    Ubicloud actual cash = UNKNOWN unless a human-owned external input is
    provided (Q7/Q11: no billing/usage API exists — web console only).

Usage:
  python3 tools/ci/ci_cost_observe.py collect --obs-id ci_cost_<UTCcompact> \
      --data-dir data/ci_cost --usage-month 2026-10 \
      --runs-since 2026-10-01T00:00:00Z --runs-until 2026-11-01T00:00:00Z \
      --jobs-window 2026-10-20T00:00:00Z/2026-10-22T00:00:00Z --jobs-max-runs 300 \
      --merged-since 2026-10-01T00:00:00Z --merged-until 2026-11-01T00:00:00Z \
      [--reuse-from data/ci_cost/<prev_obs>] [--mla-since .. --mla-until ..]
  python3 tools/ci/ci_cost_observe.py freeze --obs-id <id> --data-dir data/ci_cost
  python3 tools/ci/ci_cost_observe.py aggregate --obs-id <id> --data-dir data/ci_cost \
      --out data/ci_cost/<id>/aggregate.json [--waste-md docs/evidence/<waste>.md]
  # derived replay (v2): re-aggregate a frozen snapshot into a DERIVED path —
  # a frozen generation's original aggregate.json is never overwritten
  python3 tools/ci/ci_cost_observe.py aggregate --obs-id <id> --data-dir data/ci_cost \
      --out data/ci_cost/<id>/derived_v2/aggregate.json \
      --waste-md data/ci_cost/<id>/derived_v2/waste.md \
      --derived-manifest data/ci_cost/<id>/derived_v2/derived_manifest.json

Exit codes: 0 = stage complete; 1 = hard failure (fail-closed: pollution,
truncation guard, schema violation, API failure); 2 = usage/environment error.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

SCHEMA = "axiom.ci_cost.observe/1"
TOOL = "tools/ci/ci_cost_observe.py"
TOOL_VERSION = "2.0.0"
AGGREGATE_SCHEMA = "axiom.ci_cost.aggregate/2"
DERIVED_SCHEMA = "axiom.ci_cost.derived/1"
PER_PAGE = 100
RUN_WINDOW_HOURS = 6
HALVE_AFTER_PAGES = 10   # every page full at the ~1,000-result cap => halve
HALVE_MAX_DEPTH = 5
RATE_LIMIT_MIN_REMAINING = 400     # pause threshold (shared org budget)
RATE_SLEEP_403_S = 60
RATE_MAX_403_RETRIES = 5
GENERIC_RETRIES = 3

LEDGER_DIRNAME = "ledger"
COLLECTION_LOG = "collection.log.json"
MANIFEST = "manifest.json"

# Ledger families: file name -> expected row keys (Q18 pollution rejection).
LEDGER_FAMILIES = {
    "usage": ("usage", ("date", "product", "sku", "quantity", "organizationName")),
    "budgets": ("budgets", ("budget_product_sku", "budget_amount")),
    "runs": ("runs", ("id", "event", "created_at", "head_sha", "path")),
    "jobs": ("jobs", ("id", "run_id", "started_at", "completed_at", "labels")),
    "merges": ("merges", ("number", "merged_at", "merge_commit_sha")),
    "merge_commits": ("merge_commits", ("sha", "parents")),
}

# Public runner rates (USD/minute) — ESTIMATE ONLY (추정 참고치), never actual
# cash. Same table as tools/ci/pr_latency_attribution.py (repo convention).
RUNNER_RATES = {
    "ubuntu-24.04": 0.006,
    "ubuntu-latest": 0.006,
    "ubuntu-22.04": 0.006,
    "ubuntu-24.04-arm": 0.005,
    "ubuntu-22.04-arm": 0.005,
    "ubuntu-slim": 0.002,
    "windows-latest": 0.010,
    "macos-latest": 0.062,
    "macos-14": 0.062,
}
FALLBACK_LABEL_RATE = None  # Ubicloud rates are provider-private: estimate via
# Ubicloud public billing table (quirks Q7: standard-2 = $0.00125/min) is an
# appendix-only figure; keep the measured-minutes attribution rate-free.

# Required merge-admission checks (branch protection). Check context == job
# name: admission-check.yml:103, bsec-integrity.yml:76 (bare job id),
# debt-registry-gate.yml:1, generation-acceptance.yml:49,
# axiom-operational-slice.yml:12; dependabot-auto-merge.yml:9 lists all five.
# These consume required verification on the main landing path — waste-table
# rows that provide one are NON-TARGETS for waste reduction (change risk high).
REQUIRED_CHECK_CONTEXTS = frozenset((
    "admission-check", "bsec-integrity", "debt-registry-gate",
    "generation-acceptance", "axiom-operational-slice"))
LANDING_CONTRIBUTION_RISK = {
    "required_check": "high",
    "merge_queue": "medium",
    "none": "low",
}


class HardFail(RuntimeError):
    pass


def utcnow_iso() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_to_epoch(value):
    if not value:
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None


def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def q(v, digits=6):
    if v is None:
        return None
    return round(float(v), digits)


def percentile(values, p):
    """Linear interpolation on sorted values, index (n-1)*p (mla/r7 method)."""
    vals = sorted(float(v) for v in values if v is not None)
    if not vals:
        return None
    if len(vals) == 1:
        return vals[0]
    h = (len(vals) - 1) * p
    lo = int(math.floor(h))
    hi = int(math.ceil(h))
    if lo == hi:
        return vals[lo]
    return vals[lo] + (h - lo) * (vals[hi] - vals[lo])


def stats_block(values, digits=3):
    vals = [float(v) for v in values if v is not None]
    if not vals:
        return {"n": 0, "mean": None, "p50": None, "p90": None, "p95": None,
                "min": None, "max": None}
    return {
        "n": len(vals),
        "mean": q(sum(vals) / len(vals), digits),
        "p50": q(percentile(vals, 0.50), digits),
        "p90": q(percentile(vals, 0.90), digits),
        "p95": q(percentile(vals, 0.95), digits),
        "min": q(min(vals), digits),
        "max": q(max(vals), digits),
    }


# ---------------------------------------------------------------------------
# gh api — GET only, single-page, --include parsing (ETag/304/rate remaining)
# ---------------------------------------------------------------------------

class GhApi:
    def __init__(self, verbose=True):
        self.verbose = verbose
        self.requests = 0
        self.rate_min_remaining = None
        self.rate_last = None
        self.rate_403_retries = 0
        self.failures = 0

    def _log(self, msg):
        if self.verbose:
            print("[ci_cost] " + msg, file=sys.stderr)

    def get(self, path, headers=None):
        """One GET. Returns (http_status:int, etag:str|None, body_bytes:bytes,
        rate_remaining:int|None). 304 returns empty body. Fail-closed retries."""
        args = ["gh", "api", path, "--include"]
        for k, v in (headers or {}).items():
            args += ["-H", "%s: %s" % (k, v)]
        attempt = 0
        while True:
            attempt += 1
            self.requests += 1
            proc = subprocess.run(args, capture_output=True, check=False)
            out = proc.stdout.decode("utf-8", errors="replace")
            err = proc.stderr.decode("utf-8", errors="replace")
            status, etag, body, rate = self._parse_include(out)
            if rate is not None:
                self.rate_last = rate
                self.rate_min_remaining = rate if self.rate_min_remaining is None \
                    else min(self.rate_min_remaining, rate)
            if proc.returncode == 0 and status == 200:
                if rate is not None and rate < RATE_LIMIT_MIN_REMAINING:
                    self._log("rate remaining %d < %d — pausing %ds"
                              % (rate, RATE_LIMIT_MIN_REMAINING, RATE_SLEEP_403_S))
                    time.sleep(RATE_SLEEP_403_S)
                return status, etag, body.encode("utf-8") if isinstance(body, str) else body, rate
            if status == 304:
                # Documented gh behavior (see tool header + docs/spec quirks):
                # a conditional GET comes back 304; gh may exit 0 with empty
                # body. Treat as 304 regardless of exit code when the status
                # line is present; without a status line, exit 0 + empty body.
                return 304, etag, b"", rate
            blob = (out + "\n" + err).lower()
            if "rate limit" in blob or "secondary rate" in blob:
                self.rate_403_retries += 1
                if attempt > RATE_MAX_403_RETRIES:
                    self.failures += 1
                    raise HardFail("rate limit persists after %d retries: %s"
                                   % (RATE_MAX_403_RETRIES, path))
                self._log("rate limited — sleeping %ds (attempt %d/%d)"
                          % (RATE_SLEEP_403_S, attempt, RATE_MAX_403_RETRIES))
                time.sleep(RATE_SLEEP_403_S)
                continue
            if proc.returncode != 0 and status is None and "unexpected end of json input" in blob:
                # gh --paginate + If-None-Match 304 quirk shape; we never use
                # --paginate, so reaching this means an empty 200-like body:
                # fail closed.
                self.failures += 1
                raise HardFail("empty response body (unparseable): %s" % path)
            if attempt <= GENERIC_RETRIES:
                time.sleep(2 * attempt)
                continue
            self.failures += 1
            raise HardFail("gh api failed rc=%d status=%s: %s :: %s"
                           % (proc.returncode, status, path, (err or out)[:300]))

    def get_slurp(self, path):
        """Full pagination via gh --paginate --slurp (usage endpoint ignores
        the page parameter — Link-header pagination only; documented quirk).
        Returns the list of page documents. Retries on rate limit."""
        args = ["gh", "api", "--paginate", "--slurp", path]
        attempt = 0
        while True:
            attempt += 1
            self.requests += 1
            proc = subprocess.run(args, capture_output=True, check=False)
            out = proc.stdout.decode("utf-8", errors="replace")
            err = proc.stderr.decode("utf-8", errors="replace")
            if proc.returncode == 0 and out.strip():
                try:
                    doc = json.loads(out)
                except ValueError:
                    self.failures += 1
                    raise HardFail("slurp response unparseable: %s" % path)
                return doc if isinstance(doc, list) else [doc]
            blob = (out + "\n" + err).lower()
            if "rate limit" in blob or "secondary rate" in blob:
                self.rate_403_retries += 1
                if attempt > RATE_MAX_403_RETRIES:
                    self.failures += 1
                    raise HardFail("rate limit persists (slurp): %s" % path)
                self._log("rate limited — sleeping %ds (slurp attempt %d)"
                          % (RATE_SLEEP_403_S, attempt))
                time.sleep(RATE_SLEEP_403_S)
                continue
            if attempt <= GENERIC_RETRIES:
                time.sleep(2 * attempt)
                continue
            self.failures += 1
            raise HardFail("gh api --paginate failed rc=%d: %s :: %s"
                           % (proc.returncode, path, (err or out)[:300]))

    @staticmethod
    def _parse_include(out):
        """Split gh --include output: status line, headers, body."""
        status = None
        etag = None
        rate = None
        body = ""
        sep_idx = -1
        for sep in ("\r\n\r\n", "\n\n"):
            i = out.find(sep)
            if i != -1:
                sep_idx = i
                sep_len = len(sep)
                break
        if sep_idx == -1:
            head, body = out, ""
        else:
            head = out[:sep_idx]
            body = out[sep_idx + sep_len:]
        m = re.search(r"HTTP/[0-9.]+\s+(\d+)", head)
        if m:
            status = int(m.group(1))
        for line in head.splitlines():
            low = line.lower()
            if low.startswith("etag:"):
                etag = line.split(":", 1)[1].strip()
            elif low.startswith("x-ratelimit-remaining:"):
                try:
                    rate = int(line.split(":", 1)[1].strip())
                except ValueError:
                    rate = None
        return status, etag, body, rate


# ---------------------------------------------------------------------------
# collect
# ---------------------------------------------------------------------------

class Collector:
    def __init__(self, obs_dir, org, repo, reuse_obs_dir=None):
        self.obs_dir = obs_dir
        self.ledger_dir = os.path.join(obs_dir, LEDGER_DIRNAME)
        self.org = org
        self.repo = repo
        self.api = GhApi()
        self.entries = []          # collection log entries (append order)
        self.ledger_writers = {}   # family -> [path, handle]
        self._ledger_len = {}      # family -> rows appended so far
        self.reuse_manifest = None
        self.reuse_index = {}
        self.reuse_obs_id = None
        if reuse_obs_dir:
            self.reuse_obs_id = os.path.basename(reuse_obs_dir.rstrip("/"))
            mpath = os.path.join(reuse_obs_dir, MANIFEST)
            if not os.path.exists(mpath):
                raise HardFail("--reuse-from manifest missing: %s" % mpath)
            with open(mpath, "r", encoding="utf-8") as fh:
                self.reuse_manifest = json.load(fh)
            for e in self.reuse_manifest.get("ci_cost_observation", {}).get("collection", []):
                self.reuse_index[e["key"]] = e

    def _log(self, msg):
        print("[ci_cost] " + msg, file=sys.stderr)

    # -- ledger plumbing ----------------------------------------------------
    def ledger_append(self, family, rows):
        """Append rows; returns (ledger_file, row_start, row_end)."""
        if not isinstance(rows, list) or any(not isinstance(r, dict) for r in rows):
            raise HardFail("ledger rows must be a list of dicts (family=%s, "
                           "got %s)" % (family, type(rows).__name__))
        if family not in self.ledger_writers:
            path = os.path.join(self.ledger_dir, "%s.jsonl" % family)
            fh = open(path, "a", encoding="utf-8")
            self.ledger_writers[family] = [path, fh]
        path, fh = self.ledger_writers[family]
        start = self._ledger_len[family]
        end = start
        for row in rows:
            fh.write(json.dumps(row, sort_keys=True, separators=(",", ":"),
                                ensure_ascii=False) + "\n")
            end += 1
        fh.flush()
        self._ledger_len[family] = end
        return os.path.basename(path), start, end

    def _ledger_len_init(self):
        for family in LEDGER_FAMILIES:
            path = os.path.join(self.ledger_dir, "%s.jsonl" % family)
            n = 0
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8") as fh:
                    n = sum(1 for _ in fh)
            self._ledger_len[family] = n

    def _reuse_rows(self, entry):
        """Read the previous snapshot's ledger rows for a 304-reused key."""
        prev_ledger_dir = os.path.join(
            os.path.dirname(self.obs_dir.rstrip("/")), self.reuse_obs_id, LEDGER_DIRNAME)
        path = os.path.join(prev_ledger_dir, entry["ledger_file"])
        rows = []
        with open(path, "r", encoding="utf-8") as fh:
            for i, line in enumerate(fh):
                if entry["row_start"] <= i < entry["row_end"]:
                    rows.append(json.loads(line))
        if len(rows) != entry["row_end"] - entry["row_start"]:
            raise HardFail("reuse rows mismatch for key %s" % entry["key"])
        return rows

    def _reuse_rows_whole_range(self, probe_entry, key_prefix):
        """Reuse rows spanning every previous entry whose key starts with
        key_prefix (page-keyed legacy manifests or a whole-endpoint entry).
        Entries must be contiguous in the previous ledger (fail-closed)."""
        siblings = [e for k, e in sorted(self.reuse_index.items())
                    if k == key_prefix.rstrip(".") or k.startswith(key_prefix)]
        if not siblings:
            raise HardFail("no previous entries to reuse for %s*" % key_prefix)
        ledger_files = {e["ledger_file"] for e in siblings}
        if len(ledger_files) != 1:
            raise HardFail("reuse spans multiple ledger files: %s" % ledger_files)
        start = min(e["row_start"] for e in siblings)
        end = max(e["row_end"] for e in siblings)
        for e in siblings:
            if not (start <= e["row_start"] and e["row_end"] <= end):
                raise HardFail("non-contiguous reuse range for %s*" % key_prefix)
        probe = dict(probe_entry)
        probe["row_start"], probe["row_end"] = start, end
        return self._reuse_rows(probe)

    def _record_whole(self, key, endpoint, params, ledger_family, rows,
                      status, etag, reused_from=None):
        self._record(key, endpoint, params, page=None, ledger_family=ledger_family,
                     rows=rows, status=status, etag=etag, reused_from=reused_from)

    def _record(self, key, endpoint, params, page, ledger_family, rows,
                status, etag, reused_from=None):
        ledger_file, row_start, row_end = self.ledger_append(ledger_family, rows)
        self.entries.append({
            "key": key,
            "endpoint": endpoint,
            "method": "GET",
            "params": params,
            "page": page,
            "http_status": status,
            "etag": etag,
            "fetched_at_utc": utcnow_iso(),
            "ledger_file": ledger_file,
            "row_start": row_start,
            "row_end": row_end,
            "rows": len(rows),
            "reused_from_obs_id": reused_from,
            "rate_limit_remaining": self.api.rate_last,
        })

    # -- endpoint helpers ---------------------------------------------------
    def fetch_page_deferred(self, key, endpoint, params, ledger_family, extract):
        """One conditional GET; returns (rows, status, etag, reused_from)
        WITHOUT recording — the caller decides whether/where to record.
        304 => reuse previous snapshot rows (marked reused_from)."""
        prev = self.reuse_index.get(key)
        headers = {}
        if prev and prev.get("etag"):
            headers["If-None-Match"] = prev["etag"]
        status, etag, _body, _rate = self.api.get(endpoint, headers=headers or None)
        if status == 304:
            if prev is None:
                raise HardFail("304 without a previous snapshot to reuse: %s" % key)
            return self._reuse_rows(prev), 304, prev.get("etag"), self.reuse_obs_id
        doc = json.loads(_body.decode("utf-8")) if _body else None
        if doc is None:
            raise HardFail("empty 200 body: %s" % key)
        return extract(doc), status, etag, None

    def fetch_page(self, key, endpoint, params, ledger_family, extract):
        """One conditional GET for a page; 304 => reuse previous rows."""
        rows, status, etag, reused_from = self.fetch_page_deferred(
            key, endpoint, params, ledger_family, extract)
        self._record(key, endpoint, params, page=None, ledger_family=ledger_family,
                     rows=rows, status=status, etag=etag, reused_from=reused_from)
        return rows

    def collect_usage(self, year, month):
        """Endpoint-month ETag contract.

        QUIRK (measured 2026-11-02): the org billing usage endpoint ignores
        the `page` parameter — page=2 silently returns the first page again
        (runaway guard fired at page 201). Pagination is Link-header only, so
        fresh collection uses `gh api --paginate --slurp` in one invocation.
        ETag reuse is therefore endpoint-month scoped: a conditional probe of
        the base URL decides 304 (reuse the whole month's rows from the
        previous snapshot) vs 200 (fresh full pagination). A page-1-scoped
        etag is sound for CLOSED months; open months must collect fresh.
        """
        key = "usage.%04d-%02d" % (year, month)
        base = "/orgs/%s/settings/billing/usage?year=%d&month=%d&per_page=%d" \
            % (self.org, year, month, PER_PAGE)
        prev = self.reuse_index.get(key)
        headers = {}
        if prev and prev.get("etag"):
            headers["If-None-Match"] = prev["etag"]
        status, etag, _body, _rate = self.api.get(base, headers=headers or None)
        if status == 304:
            if prev is None:
                raise HardFail("304 without a previous snapshot: %s" % key)
            rows = self._reuse_rows_whole_range(prev, "usage.%04d-%02d." % (year, month))
            self._record_whole(key, base, {"year": year, "month": month},
                               "usage", rows, 304, prev.get("etag"),
                               reused_from=self.reuse_obs_id)
            return len(rows)
        if status != 200:
            raise HardFail("usage probe returned %s: %s" % (status, base))
        pages = self.api.get_slurp(base)
        rows = []
        for doc in pages:
            rows.extend(_extract_usage(doc))
        # _record appends contiguously — the single entry spans the month.
        self._record_whole(key, base, {"year": year, "month": month},
                           "usage", rows, 200, etag)
        return len(rows)

    def collect_budgets(self):
        path = "/orgs/%s/settings/billing/budgets" % self.org
        self.fetch_page("budgets", path, {}, "budgets", _extract_budgets)

    def collect_runs(self, since, until):
        since_dt = datetime.fromisoformat(since.replace("Z", "+00:00"))
        until_dt = datetime.fromisoformat(until.replace("Z", "+00:00"))
        windows = []
        cur = since_dt
        while cur < until_dt:
            nxt = min(cur + timedelta(hours=RUN_WINDOW_HOURS), until_dt)
            windows.append((cur, nxt))
            cur = nxt
        total = 0
        for idx, (w_start, w_end) in enumerate(windows):
            total += self._collect_runs_window(idx, w_start, w_end, depth=0)
        return total

    def _collect_runs_window(self, idx, w_start, w_end, depth):
        # Pages are buffered and only recorded after the halving decision —
        # a saturated window (> the ~1,000-result pagination cap) is halved
        # and its buffered pages are DISCARDED, never appended (duplicate-run
        # corruption guard; total_count is never trusted — CQ3).
        w_tag = w_start.strftime("%Y%m%dT%H%MZ")
        s = w_start.strftime("%Y-%m-%dT%H:%M:%SZ")
        e = w_end.strftime("%Y-%m-%dT%H:%M:%SZ")
        base = "/repos/%s/actions/runs?created=%s..%s&per_page=%d" \
            % (self.repo, s, e, PER_PAGE)
        buffered = []
        page = 1
        while True:
            key = "runs.%s.p%03d" % (w_tag, page)
            path = base + "&page=%d" % page
            rows, status, etag, reused_from = self.fetch_page_deferred(
                key, path, {"created": "%s..%s" % (s, e),
                            "per_page": PER_PAGE, "page": page},
                "runs", _extract_runs)
            buffered.append((key, path, {"created": "%s..%s" % (s, e),
                                         "per_page": PER_PAGE, "page": page},
                             rows, status, etag, reused_from))
            if len(rows) < PER_PAGE:
                break
            page += 1
            if page > HALVE_AFTER_PAGES:
                # pagination-cap territory: every page full — the window
                # exceeds the query result budget; halve and drop the buffer.
                if depth >= HALVE_MAX_DEPTH or (w_end - w_start) <= timedelta(minutes=30):
                    raise HardFail(
                        "runs window %s exceeds the pagination budget at max "
                        "halving depth — narrow the window (fail-closed)" % w_tag)
                mid = w_start + (w_end - w_start) / 2
                n1 = self._collect_runs_window(idx, w_start, mid, depth + 1)
                n2 = self._collect_runs_window(idx, mid, w_end, depth + 1)
                return n1 + n2
        for (key, path, params, rows, status, etag, reused_from) in buffered:
            self._record(key, path, params, page=None, ledger_family="runs",
                         rows=rows, status=status, etag=etag,
                         reused_from=reused_from)
        return sum(len(p[3]) for p in buffered)

    def collect_jobs(self, windows, max_runs):
        """Deterministic stride sample from the runs ledger already collected."""
        runs = self._read_ledger_rows("runs")
        selected = []
        for (w_start, w_end) in windows:
            w0 = iso_to_epoch(w_start)
            w1 = iso_to_epoch(w_end)
            in_win = sorted(
                (r for r in runs if r.get("created_at")
                 and w0 <= iso_to_epoch(r["created_at"]) < w1),
                key=lambda r: r["id"])
            if not in_win:
                continue
            stride = max(1, math.ceil(len(in_win) / float(max_runs)))
            picked = in_win[::stride]
            selected.append((w_start, w_end, len(in_win), stride, picked))
        total_rows = 0
        for (w_start, w_end, n_win, stride, picked) in selected:
            w_compact = w_start.replace("-", "").replace(":", "")
            for pos, run in enumerate(picked):
                run_id = run["id"]
                page = 1
                while True:
                    key = "jobs.%s.r%d.p%03d" % (w_compact, run_id, page)
                    path = "/repos/%s/actions/runs/%d/jobs?per_page=%d&filter=all&page=%d" \
                        % (self.repo, run_id, PER_PAGE, page)
                    rows = self.fetch_page(
                        key, path, {"run_id": run_id, "per_page": PER_PAGE,
                                    "filter": "all", "page": page},
                        "jobs", lambda doc: _extract_jobs(doc, run_id))
                    total_rows += len(rows)
                    if len(rows) < PER_PAGE:
                        break
                    page += 1
                    if page > 20:
                        raise HardFail("jobs pagination runaway run %d" % run_id)
        return total_rows

    def _read_ledger_rows(self, family):
        path = os.path.join(self.ledger_dir, "%s.jsonl" % family)
        rows = []
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as fh:
                for line in fh:
                    rows.append(json.loads(line))
        return rows

    def collect_merges(self, since, until):
        page = 1
        merged = 0
        stop = False
        while not stop:
            key = "merges.p%03d" % page
            path = "/repos/%s/pulls?state=closed&sort=updated&direction=desc&per_page=%d&page=%d" \
                % (self.repo, PER_PAGE, page)
            rows = self.fetch_page(key, path,
                                   {"state": "closed", "sort": "updated",
                                    "direction": "desc", "per_page": PER_PAGE,
                                    "page": page},
                                   "merges", _extract_merges)
            for r in rows:
                ma = r.get("merged_at")
                if ma and since <= ma < until:
                    merged += 1
            if rows and all((r.get("updated_at") or "") < since for r in rows):
                stop = True
            if len(rows) < PER_PAGE:
                stop = True
            page += 1
            if page > 100:
                raise HardFail("merges pagination runaway")
        return merged

    def collect_merge_commits(self):
        """Verify every in-window merge_commit_sha (parents==2) — landing truth."""
        merges = [r for r in self._read_ledger_rows("merges") if r.get("merged_at")]
        shas = sorted({r["merge_commit_sha"] for r in merges if r.get("merge_commit_sha")})
        for sha in shas:
            key = "merge_commit.%s" % sha
            path = "/repos/%s/commits/%s" % (self.repo, sha)
            self.fetch_page(key, path, {"sha": sha}, "merge_commits",
                            _extract_merge_commit)
        return len(shas)

    def collect_mla(self, mla_script, since, until):
        out_prefix = os.path.join(self.obs_dir, "mla", "ci_cost_mla")
        os.makedirs(os.path.dirname(out_prefix), exist_ok=True)
        cmd = ["bash", mla_script, "--since", since, "--until", until,
               "--out", out_prefix, "--no-logs"]
        self._log("delegating admission latency to merge_latency_audit.sh "
                  "(--no-logs; regime unknown stratum is recorded fail-closed)")
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            raise HardFail("merge_latency_audit.sh failed rc=%d: %s"
                           % (proc.returncode, (proc.stderr or "")[-500:]))
        return out_prefix

    def write_collection_log(self, params):
        log = {
            "schema": SCHEMA,
            "tool": TOOL,
            "stage": "collect",
            "obs_id": os.path.basename(self.obs_dir.rstrip("/")),
            "collected_at_utc": utcnow_iso(),
            "status": "complete",
            "parameters": params,
            "integrity": {
                "api_requests": self.api.requests,
                "api_failures": self.api.failures,
                "rate_limit_403_retries": self.api.rate_403_retries,
                "rate_limit_min_remaining": self.api.rate_min_remaining,
            },
            "collection": self.entries,
        }
        path = os.path.join(self.obs_dir, COLLECTION_LOG)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(log, fh, indent=2, sort_keys=True, ensure_ascii=False)
            fh.write("\n")
        os.replace(tmp, path)


def _extract_usage(doc):
    out = []
    for item in doc.get("usageItems") or []:
        out.append({
            "date": item.get("date"),
            "product": item.get("product"),
            "sku": item.get("sku"),
            "quantity": item.get("quantity"),
            "unitType": item.get("unitType"),
            "pricePerUnit": item.get("pricePerUnit"),
            "grossAmount": item.get("grossAmount"),
            "discountAmount": item.get("discountAmount"),
            "netAmount": item.get("netAmount"),
            "organizationName": item.get("organizationName"),
            "repositoryName": item.get("repositoryName"),
        })
    return out


def _extract_budgets(doc):
    out = []
    for b in doc.get("budgets") or []:
        out.append({
            "id": b.get("id"),
            "budget_type": b.get("budget_type"),
            "budget_product_sku": b.get("budget_product_sku"),
            "budget_scope": b.get("budget_scope"),
            "budget_amount": b.get("budget_amount"),
            "prevent_further_usage": b.get("prevent_further_usage"),
            "budget_entity_name": b.get("budget_entity_name"),
            "will_alert": (b.get("budget_alerting") or {}).get("will_alert"),
        })
    return out


def _extract_runs(doc):
    out = []
    for r in doc.get("workflow_runs") or []:
        out.append({
            "id": r.get("id"),
            "name": r.get("name"),
            "event": r.get("event"),
            "status": r.get("status"),
            "conclusion": r.get("conclusion"),
            "run_attempt": r.get("run_attempt"),
            "created_at": r.get("created_at"),
            "run_started_at": r.get("run_started_at"),
            "updated_at": r.get("updated_at"),
            "head_sha": r.get("head_sha"),
            "head_branch": r.get("head_branch"),
            "path": r.get("path"),
        })
    return out


def _extract_jobs(doc, run_id):
    out = []
    for j in doc.get("jobs") or []:
        out.append({
            "id": j.get("id"),
            "run_id": run_id,
            "name": j.get("name"),
            "status": j.get("status"),
            "conclusion": j.get("conclusion"),
            "runner_id": j.get("runner_id"),
            "runner_group_id": j.get("runner_group_id"),
            "runner_group_name": j.get("runner_group_name"),
            "labels": j.get("labels") or [],
            "started_at": j.get("started_at"),
            "completed_at": j.get("completed_at"),
            "steps_count": len(j.get("steps") or []),
        })
    return out


def _extract_merges(doc):
    out = []
    for p in doc if isinstance(doc, list) else []:
        out.append({
            "number": p.get("number"),
            "state": p.get("state"),
            "created_at": p.get("created_at"),
            "updated_at": p.get("updated_at"),
            "merged_at": p.get("merged_at"),
            "closed_at": p.get("closed_at"),
            "merge_commit_sha": p.get("merge_commit_sha"),
            "head_sha": (p.get("head") or {}).get("sha"),
            "base_ref": (p.get("base") or {}).get("ref"),
        })
    return out


def _extract_merge_commit(doc):
    return [{
        "sha": doc.get("sha"),
        "parents": [p.get("sha") for p in doc.get("parents") or []],
    }]


# ---------------------------------------------------------------------------
# freeze
# ---------------------------------------------------------------------------

def cmd_freeze(args):
    obs_dir = os.path.join(args.data_dir, args.obs_id)
    mpath = os.path.join(obs_dir, MANIFEST)
    if os.path.exists(mpath):
        raise HardFail("manifest already exists — snapshot is immutable, "
                       "re-freeze refused: %s" % mpath)
    log_path = os.path.join(obs_dir, COLLECTION_LOG)
    if not os.path.exists(log_path):
        raise HardFail("collection log missing (incomplete collect?): %s" % log_path)
    with open(log_path, "r", encoding="utf-8") as fh:
        log = json.load(fh)
    if log.get("status") != "complete":
        raise HardFail("collection log status != complete")
    entries = log["collection"]
    if not entries:
        raise HardFail("collection log has no requests")

    ledger_sha = {}
    population = {}
    for family, (_, required) in sorted(LEDGER_FAMILIES.items()):
        path = os.path.join(obs_dir, LEDGER_DIRNAME, "%s.jsonl" % family)
        rows_n = 0
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as fh:
                for i, line in enumerate(fh):
                    line = line.strip()
                    if not line:
                        raise HardFail("blank ledger line %s:%d" % (family, i))
                    row = json.loads(line)
                    if not isinstance(row, dict):
                        raise HardFail("non-object ledger row %s:%d" % (family, i))
                    if "message" in row and not all(k in row for k in required):
                        # Q18: gh api error bodies must never enter the ledger
                        raise HardFail("Q18 pollution: error JSON row at %s:%d :: %s"
                                       % (family, i, str(row)[:200]))
                    missing = [k for k in required if k not in row]
                    if missing:
                        raise HardFail("schema violation at %s:%d missing=%s"
                                       % (family, i, missing))
                    rows_n += 1
            ledger_sha[os.path.basename(path)] = sha256_file(path)
        population[family] = rows_n
    if population["usage"] == 0:
        raise HardFail("no usage rows — refusing to freeze an empty snapshot")

    # per-entry row-range validation
    ledger_lens = {f: population[f] for f in LEDGER_FAMILIES}
    for e in entries:
        fam_file = e["ledger_file"]
        family = fam_file.split(".")[0]
        if e["row_end"] > ledger_lens[family] or e["row_start"] > e["row_end"]:
            raise HardFail("row range invalid for key %s" % e["key"])

    mla_files = {}
    mla_dir = os.path.join(obs_dir, "mla")
    if os.path.isdir(mla_dir):
        for name in sorted(os.listdir(mla_dir)):
            if name.endswith(".jsonl") or name.endswith(".json"):
                mla_files["mla/" + name] = sha256_file(os.path.join(mla_dir, name))

    manifest = {
        "ci_cost_observation": {
            "schema": SCHEMA,
            "tool": TOOL,
            "stage": "freeze",
            "obs_id": args.obs_id,
            "subject": "CI cost observation (billing usage + runs/jobs + landing)",
            "repository": args.repo,
            "frozen_at_utc": utcnow_iso(),
            "parameters": log["parameters"],
            "collected_at_utc": log["collected_at_utc"],
            "integrity": {
                **log["integrity"],
                "etag_304_pages": sum(1 for e in entries if e["http_status"] == 304),
                "etag_304_reused_from": sorted({
                    e["reused_from_obs_id"] for e in entries
                    if e.get("reused_from_obs_id")}),
                "pages_complete": True,
                "validation": "per-row schema keys + Q18 message-pollution rejection",
            },
            "population": population,
            "mla_files": mla_files,
            "ledger_sha256": ledger_sha,
            "collection": entries,
        },
    }
    tmp = mpath + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, mpath)
    os.chmod(mpath, 0o444)
    for name in os.listdir(os.path.join(obs_dir, LEDGER_DIRNAME)):
        os.chmod(os.path.join(obs_dir, LEDGER_DIRNAME, name), 0o444)
    print("[ci_cost] frozen: %s (usage=%d runs=%d jobs=%d merges=%d "
          "merge_commits=%d 304_pages=%d)"
          % (args.obs_id, population["usage"], population["runs"],
             population["jobs"], population["merges"],
             population["merge_commits"],
             manifest["ci_cost_observation"]["integrity"]["etag_304_pages"]))
    return 0


# ---------------------------------------------------------------------------
# aggregate
# ---------------------------------------------------------------------------

def _read_manifest(obs_dir):
    mpath = os.path.join(obs_dir, MANIFEST)
    if not os.path.exists(mpath):
        raise HardFail("snapshot not frozen (manifest missing): %s" % mpath)
    with open(mpath, "r", encoding="utf-8") as fh:
        return json.load(fh)["ci_cost_observation"]


def _read_ledger(obs_dir, family):
    path = os.path.join(obs_dir, LEDGER_DIRNAME, "%s.jsonl" % family)
    rows = []
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as fh:
            for line in fh:
                rows.append(json.loads(line))
    return rows


def aggregate(obs_dir):
    man = _read_manifest(obs_dir)
    params = man["parameters"]
    usage = _read_ledger(obs_dir, "usage")
    budgets = _read_ledger(obs_dir, "budgets")
    runs = _read_ledger(obs_dir, "runs")
    jobs = _read_ledger(obs_dir, "jobs")
    merges = _read_ledger(obs_dir, "merges")
    merge_commits = _read_ledger(obs_dir, "merge_commits")

    repo_name = params.get("repo", "Archright/Axiom").split("/", 1)[1]

    # (1)(2)(3) billing: month × sku × repository, Axiom-filtered ------------
    months = {}
    # 조직 레벨 고정비 행(seats 등)은 repositoryName이 빈 문자열로 온다(CQ4) —
    # repo 소비 필터에 걸리지 않도록 별도 버킷으로 가로챈다(고정비 별도 계약).
    fixed_org = {}
    for row in sorted(usage, key=lambda r: (r.get("date") or "", r.get("sku") or "")):
        if row.get("repositoryName") != repo_name:
            if not row.get("repositoryName") and (
                    (row.get("unitType") or "") == "UserMonths"
                    or row.get("sku") == "Enterprise Cloud"):
                osku = row.get("sku") or "unknown"
                f = fixed_org.setdefault(osku, {"quantity": 0.0,
                                                "unitType": row.get("unitType"),
                                                "gross_usd": 0.0, "net_usd": 0.0})
                f["quantity"] += float(row.get("quantity") or 0.0)
                f["gross_usd"] += float(row.get("grossAmount") or 0.0)
                f["net_usd"] += float(row.get("netAmount") or 0.0)
            continue
        month = (row.get("date") or "")[:7]
        sku = row.get("sku") or "unknown"
        bucket = months.setdefault(month, {})
        sku_b = bucket.setdefault(sku, {
            "quantity": 0.0, "unitType": row.get("unitType"),
            "gross_usd": 0.0, "discount_usd": 0.0, "net_usd": 0.0,
            "by_day": {}})
        sku_b["quantity"] += float(row.get("quantity") or 0.0)
        sku_b["gross_usd"] += float(row.get("grossAmount") or 0.0)
        sku_b["discount_usd"] += float(row.get("discountAmount") or 0.0)
        sku_b["net_usd"] += float(row.get("netAmount") or 0.0)
        day = (row.get("date") or "")[:10]
        d = sku_b["by_day"].setdefault(day, {"quantity": 0.0, "gross_usd": 0.0,
                                             "net_usd": 0.0})
        d["quantity"] += float(row.get("quantity") or 0.0)
        d["gross_usd"] += float(row.get("grossAmount") or 0.0)
        d["net_usd"] += float(row.get("netAmount") or 0.0)
    ghec = {"by_month": {}, "net_total_usd": 0.0, "gross_total_usd": 0.0}
    fixed = {}
    for month in sorted(months):
        mb = {}
        for sku in sorted(months[month]):
            b = months[month][sku]
            entry = {
                "quantity": q(b["quantity"], 4), "unitType": b["unitType"],
                "gross_usd": q(b["gross_usd"]), "discount_usd": q(b["discount_usd"]),
                "net_usd": q(b["net_usd"]),
                "by_day": {d: {"quantity": q(v["quantity"], 4),
                               "gross_usd": q(v["gross_usd"]),
                               "net_usd": q(v["net_usd"])}
                           for d, v in sorted(b["by_day"].items())},
            }
            mb[sku] = entry
            ghec["net_total_usd"] = round(ghec["net_total_usd"] + entry["net_usd"], 6)
            ghec["gross_total_usd"] = round(ghec["gross_total_usd"] + entry["gross_usd"], 6)
            if sku in ("Enterprise Cloud",) or (b["unitType"] or "") == "UserMonths":
                fixed.setdefault(sku, {"quantity": 0.0, "unitType": b["unitType"],
                                       "gross_usd": 0.0, "net_usd": 0.0})
                fixed[sku]["quantity"] = round(fixed[sku]["quantity"] + entry["quantity"], 4)
                fixed[sku]["gross_usd"] = round(fixed[sku]["gross_usd"] + entry["gross_usd"], 6)
                fixed[sku]["net_usd"] = round(fixed[sku]["net_usd"] + entry["net_usd"], 6)
        ghec["by_month"][month] = mb
    for osku, f in sorted(fixed_org.items()):
        e = fixed.setdefault(osku, {"quantity": 0.0, "unitType": f["unitType"],
                                    "gross_usd": 0.0, "net_usd": 0.0})
        e["quantity"] = round(e["quantity"] + f["quantity"], 4)
        e["gross_usd"] = round(e["gross_usd"] + f["gross_usd"], 6)
        e["net_usd"] = round(e["net_usd"] + f["net_usd"], 6)
    # actions minutes by sku (runner consumption vs fixed cost separation)
    actions_minutes = {m: {s: b["quantity"] for s, b in sorted(months[m].items())
                           if (b["unitType"] or "") == "Minutes"}
                       for m in sorted(months)}

    # (4) runs: events, workflows, wait/run split, duplication --------------
    by_event = {}
    by_workflow = {}
    wait_run = {}
    for r in sorted(runs, key=lambda r: (r["id"] if r.get("id") is not None else 0)):
        ev = r.get("event") or "unknown"
        wf = (r.get("path") or "unknown").replace(".github/workflows/", "")
        by_event[ev] = by_event.get(ev, 0) + 1
        wfb = by_workflow.setdefault(wf, {"runs": 0, "by_event": {}})
        wfb["runs"] += 1
        wfb["by_event"][ev] = wfb["by_event"].get(ev, 0) + 1
        c = iso_to_epoch(r.get("created_at"))
        s = iso_to_epoch(r.get("run_started_at"))
        u = iso_to_epoch(r.get("updated_at"))
        if c is not None and s is not None and u is not None:
            wr = wait_run.setdefault(ev, {"wait_s": [], "run_s": [], "failure": 0,
                                          "cancelled": 0, "n": 0})
            wr["wait_s"].append(max(0.0, s - c))
            wr["run_s"].append(max(0.0, u - s))
            wr["n"] += 1
            if r.get("conclusion") == "failure":
                wr["failure"] += 1
            elif r.get("conclusion") == "cancelled":
                wr["cancelled"] += 1
    dup = {}
    wf_dup_runs = {}
    run_wf = {}
    for r in runs:
        wf = (r.get("path") or "unknown").replace(".github/workflows/", "")
        run_wf[r["id"]] = wf
    for r in runs:
        k = (r.get("head_sha") or "", r.get("event") or "")
        dup[k] = dup.get(k, 0) + 1
    dup_groups = {k: v for k, v in dup.items() if k[0] and v > 1}
    dup_runs = sum(dup_groups.values())
    dup_keys = set(dup_groups)
    for r in runs:
        k = (r.get("head_sha") or "", r.get("event") or "")
        if k in dup_keys:
            wf = run_wf.get(r["id"], "unknown")
            wf_dup_runs[wf] = wf_dup_runs.get(wf, 0) + 1
    dup_by_event = {}
    for (sha, ev), v in sorted(dup_groups.items()):
        dup_by_event[ev] = dup_by_event.get(ev, 0) + v

    # jobs: runner attribution (GHEC=0 vs fallback≠0 vs null) ---------------
    job_cov_runs = sorted({j["run_id"] for j in jobs})
    run_sha_by_id = {r["id"]: r for r in runs}
    cov = {
        "runs_total_in_snapshot": len(runs),
        "runs_with_jobs_fetched": len(job_cov_runs),
        "coverage_note": "bounded deterministic stride sample (--jobs-window/--jobs-max-runs); "
                         "attribution ratios are measured over the covered subset only",
    }
    runner = {"ghec_group0": {"jobs": 0, "minutes": 0.0},
              "fallback_nonzero": {"jobs": 0, "minutes": 0.0},
              "unassigned_null": {"jobs": 0, "minutes": 0.0},
              "by_group": {}}
    wf_minutes = {}
    for j in sorted(jobs, key=lambda j: (j["id"] if j.get("id") is not None else 0)):
        s = iso_to_epoch(j.get("started_at"))
        e = iso_to_epoch(j.get("completed_at"))
        mins = max(0.0, (e - s) / 60.0) if s and e and e > s else 0.0
        gid = j.get("runner_group_id")
        gname = j.get("runner_group_name") or ""
        if gid == 0 and gname in ("", "GitHub Actions"):
            b = runner["ghec_group0"]
        elif gid is None:
            b = runner["unassigned_null"]
        else:
            b = runner["fallback_nonzero"]
        b["jobs"] += 1
        b["minutes"] = round(b["minutes"] + mins, 4)
        gb = runner["by_group"].setdefault("group_%s_%s" % (gid, gname or "none"),
                                           {"jobs": 0, "minutes": 0.0})
        gb["jobs"] += 1
        gb["minutes"] = round(gb["minutes"] + mins, 4)
        run = run_sha_by_id.get(j.get("run_id"))
        if run:
            wf = (run.get("path") or "unknown").replace(".github/workflows/", "")
            wmb = wf_minutes.setdefault(wf, {"job_minutes": 0.0, "jobs": 0,
                                             "ghec_est_usd": 0.0,
                                             "ghec_minutes": 0.0,
                                             "fallback_minutes": 0.0})
            wmb["job_minutes"] = round(wmb["job_minutes"] + mins, 4)
            wmb["jobs"] += 1
            # 달러 환산(추정 참고치)은 GHEC 라벨 잡에만 적용한다 — fallback
            # (Ubicloud) 잡은 공개 단가 환산 없이 분만 기록한다(실제 청구
            # UNKNOWN 계약; Q7/Q11).
            rate = None
            for lb in sorted(j.get("labels") or []):
                if lb in RUNNER_RATES:
                    rate = RUNNER_RATES[lb]
                    break
            if gid == 0 and gname in ("", "GitHub Actions"):
                wmb["ghec_minutes"] = round(wmb["ghec_minutes"] + mins, 4)
                if rate is not None:
                    wmb["ghec_est_usd"] = round(wmb["ghec_est_usd"] + mins * rate, 4)
            elif gid is not None:
                wmb["fallback_minutes"] = round(wmb["fallback_minutes"] + mins, 4)

    # (5) landing — 검증 통과 착지 (verified landing) --------------------------
    # 정의: required 5 checks green + merge queue 통과 + 2-parent GitHub
    # native MERGE 커밋. 도구 조작화는 base_ref=="main"(merge queue 유일
    # 착지 브랜치) 필터 + parents==2 MERGE 커밋 검증이며, checks green·
    # queue 통과는 GitHub merge-admission authority(AGENTS.md §2.3)의
    # 보장을 전제로 한다 — 본 도구는 이를 재판정하지 않는다
    # (Authority ≠ Adapter).
    w_since = params.get("merged_since")
    w_until = params.get("merged_until")
    merged_window_all = [
        m for m in merges
        if m.get("merged_at")
        and (not w_since or m["merged_at"] >= w_since)
        and (not w_until or m["merged_at"] < w_until)]
    merged_window = [m for m in merged_window_all
                     if (m.get("base_ref") or "") == "main"]
    verified = {c["sha"]: c for c in merge_commits}
    window_shas = sorted({m["merge_commit_sha"] for m in merged_window
                          if m.get("merge_commit_sha")})
    verified2 = [s for s in window_shas
                 if s in verified and len(verified[s].get("parents") or []) == 2]
    window_shas_all = sorted({m["merge_commit_sha"] for m in merged_window_all
                              if m.get("merge_commit_sha")})
    verified2_all = [s for s in window_shas_all
                     if s in verified
                     and len(verified[s].get("parents") or []) == 2]
    base_ref_dist = {}
    for m in merged_window_all:
        b = m.get("base_ref") or "null"
        base_ref_dist[b] = base_ref_dist.get(b, 0) + 1
    landing = {
        "window": {"since": w_since, "until": w_until},
        "verified_landing_definition": "검증 통과 착지 = (1) required 5 checks "
                                       "green + (2) merge queue 통과 + (3) "
                                       "2-parent GitHub native MERGE 커밋. "
                                       "(1)(2)는 GitHub merge-admission "
                                       "authority의 보장을 전제로 하며 본 도구는 "
                                       "재판정하지 않는다; 도구 조작화는 "
                                       "base_ref==main + parents==2 검증이다",
        "landing_basis": "base_ref==main — 이 착지 수가 C_landing/G_landing의 "
                         "정본 분모다",
        "merged_prs_in_snapshot": len(merged_window),
        "merged_prs_in_snapshot_all_refs": len(merged_window_all),
        "base_ref_distribution": dict(sorted(base_ref_dist.items())),
        "merge_commits_in_window": len(window_shas),
        "merge_commits_verified_total": len(verified),
        "verified_parents2": len(verified2),
        "landing_count": len(verified2),
        "unfiltered_verified2_count": len(verified2_all),
        "note": "landing truth = GitHub MERGE commit with 2 parents "
                "(landing_observe.sh contract) + base_ref==main filter; "
                "commits outside the merged window are excluded from the "
                "count; unfiltered_verified2_count는 v1 무필터 기준의 비정본 "
                "참고값이다",
        "unverified_shas": sorted(set(window_shas) - set(verified2)),
    }

    # (6) admission latency from mla snapshot files ---------------------------
    admission = {"source": None}
    mla_runs_path = os.path.join(obs_dir, "mla", "ci_cost_mla.runs.jsonl")
    if os.path.exists(mla_runs_path):
        mla_rows = []
        with open(mla_runs_path, "r", encoding="utf-8") as fh:
            for line in fh:
                mla_rows.append(json.loads(line))
        concl = {}
        regimes = {}
        classes = {}
        wall, dur, gaps, resid, wait_part = [], [], [], [], []
        for r in sorted(mla_rows, key=lambda r: r.get("run_id") or 0):
            c = r.get("conclusion") or "null"
            concl[c] = concl.get(c, 0) + 1
            g = r.get("regime") or "unknown"
            regimes[g] = regimes.get(g, 0) + 1
            cl = r.get("classification") or "UNKNOWN_LOG"
            classes[cl] = classes.get(cl, 0) + 1
            w_v = r.get("wall_s")
            d_v = r.get("dur_sum_s")
            g_v = r.get("gaps_sum_s")
            rs_v = r.get("residual_s")
            if w_v is not None:
                wall.append(float(w_v))
            if d_v is not None:
                dur.append(float(d_v))
            if g_v is not None:
                gaps.append(float(g_v))
            if rs_v is not None:
                resid.append(float(rs_v))
            if w_v is not None and d_v is not None:
                wait_part.append(float(w_v) - float(d_v))
        admission = {
            "source": "tools/ci/merge_latency_audit.sh (merge_group admission-gate runs; "
                      "window in snapshot parameters)",
            "percentile_method": "linear interpolation, index (n-1)*p (mla §stats contract)",
            "wall_run_wait_split": "wall = updated_at − run_started_at; run part = dur_sum "
                                   "(executed-job union); wait part = gaps_sum + residual",
            "n": len(mla_rows),
            "conclusions": concl,
            "regimes": regimes,
            "classifications": classes,
            "wall_s": stats_block(wall),
            "dur_sum_s": stats_block(dur),
            "gaps_sum_s": stats_block(gaps),
            "residual_s": stats_block(resid),
            "wait_part_s": stats_block(wait_part),
        }

    event_latency = {}
    for ev in sorted(wait_run):
        wr = wait_run[ev]
        event_latency[ev] = {
            "n": wr["n"],
            "wait_s": stats_block(wr["wait_s"]),
            "run_s": stats_block(wr["run_s"]),
            "failure": wr["failure"],
            "cancelled": wr["cancelled"],
        }

    # waste candidates --------------------------------------------------------
    rates_note = "추정 참고치 — public per-minute rates; 실제 청구 아님 (usage API gross/net가 실측)"
    # required-check 제공 워크플로 판정: (a) path stem이 required context와
    # 동일하거나 (b) 표본 jobs 원장에서 해당 워크플로의 job 이름이 required
    # context다. (b)는 과거 워크플로 파일명과 check context가 다른 경우도
    # 잡는다(실측: admission-gate-v2.yml의 job 이름 = "admission-check").
    wf_required_ctx = {}
    for j in jobs:
        jn = j.get("name")
        if jn in REQUIRED_CHECK_CONTEXTS:
            r = run_sha_by_id.get(j.get("run_id")) or {}
            stem = (r.get("path") or "unknown").replace(".github/workflows/", "")
            wf_required_ctx.setdefault(stem, set()).add(jn)
    waste = []
    for wf in sorted(by_workflow):
        info = by_workflow[wf]
        jm = wf_minutes.get(wf, {}).get("job_minutes", 0.0)
        est = None
        if wf_minutes.get(wf):
            est = q(wf_minutes[wf]["ghec_est_usd"])  # GHEC 라벨 잡 한계 (추정 참고치)
        stem = wf[:-4] if wf.endswith(".yml") else wf
        if stem in REQUIRED_CHECK_CONTEXTS or wf_required_ctx.get(wf):
            lc = "required_check"
        elif info["by_event"].get("merge_group", 0):
            lc = "merge_queue"
        else:
            lc = "none"
        waste.append({
            "workflow": wf,
            "runs": info["runs"],
            "by_event": dict(sorted(info["by_event"].items())),
            "merge_group_runs": info["by_event"].get("merge_group", 0),
            "measured_job_minutes_subset": q(jm, 3),
            "measured_ghec_minutes_subset": q(wf_minutes.get(wf, {}).get("ghec_minutes", 0.0), 3),
            "measured_fallback_minutes_subset": q(wf_minutes.get(wf, {}).get("fallback_minutes", 0.0), 3),
            "est_usd_ghec_subset": est,
            "dup_runs_share_pct": q(
                100.0 * wf_dup_runs.get(wf, 0) / info["runs"], 2)
            if info["runs"] else None,
            "required_check_contexts": sorted(
                wf_required_ctx.get(wf)
                or ({stem} if stem in REQUIRED_CHECK_CONTEXTS else set())),
            "landing_contribution": lc,
            "change_risk": LANDING_CONTRIBUTION_RISK[lc],
        })
    waste.sort(key=lambda w: (-(w["measured_job_minutes_subset"] or 0.0), w["workflow"]))
    waste = waste[:25]

    landing_count = landing["landing_count"]
    ghec_net = ghec["net_total_usd"]
    ghec_gross = ghec["gross_total_usd"]

    # waste coverage — waste 표가 전체 사용량의 몇 %를 관측하는가.
    # B2 낭비 후보 대표성 판단의 전제다: 표 est 합계(≪ billing gross)가
    # 전체를 대변하지 않음을 수치로 고정하고, 미커버 잔여의 실체를
    # 달러·분·run 축으로 분해한다.
    bill_minutes_total = 0.0
    runner_sku_gross = 0.0
    for m in months:
        for s, b in months[m].items():
            if (b["unitType"] or "") == "Minutes":
                bill_minutes_total += b["quantity"]
                runner_sku_gross += b["gross_usd"]
    waste_est_sum = sum(w["est_usd_ghec_subset"] or 0.0 for w in waste)
    waste_min_sum = sum(w["measured_job_minutes_subset"] or 0.0 for w in waste)
    waste_ghec_min_sum = sum(w["measured_ghec_minutes_subset"] or 0.0
                             for w in waste)
    sampled_min_all = sum(runner[k]["minutes"] for k in
                          ("ghec_group0", "fallback_nonzero", "unassigned_null"))
    non_ghec_min = (runner["fallback_nonzero"]["minutes"]
                    + runner["unassigned_null"]["minutes"])
    cov_pct = (lambda num, den: q(100.0 * num / den, 4) if den else None)
    waste_coverage = {
        "purpose": "waste 표의 전체 사용량 커버리지 — B2 낭비 후보 대표성 판단의 "
                   "전제. 표 est 합계가 billing gross를 대변하지 않음을 수치로 "
                   "고정하고 미커버 잔여의 실체를 분해한다",
        "usd": {
            "waste_table_est_usd_sum": q(waste_est_sum, 4),
            "billing_gross_usd": ghec_gross,
            "coverage_pct": cov_pct(waste_est_sum, ghec_gross),
            "basis_note": "분자 = GHEC 라벨 잡 × 공개 단가의 jobs-표본 추정 "
                          "참고치, 분모 = usage API 실측 gross(스토리지·LFS 등 "
                          "비러너 SKU 포함) — 성격이 다른 두 값의 하한 비교이며 "
                          "청구 대사(reconciliation)가 아니다",
        },
        "minutes": {
            "billing_actions_minutes_by_sku_by_month": actions_minutes,
            "billing_actions_minutes_total": q(bill_minutes_total, 4),
            "waste_table_measured_minutes_sum": q(waste_min_sum, 3),
            "waste_table_measured_ghec_minutes_sum": q(waste_ghec_min_sum, 3),
            "coverage_pct_waste_table_ghec_of_billing": cov_pct(
                waste_ghec_min_sum, bill_minutes_total),
            "sampled_all_workflows_minutes": q(sampled_min_all, 3),
            "coverage_pct_sampled_all_of_billing": cov_pct(
                sampled_min_all, bill_minutes_total),
            "basis_note": "표본 분은 jobs stride 표본 창 내에서만 측정되며 "
                          "fallback(Ubicloud) 분을 포함한다 — billing Actions 분"
                          "(GHEC 청구)과의 비교는 표본 커버리지 지표다",
        },
        "jobs_sample": {
            "runs_in_snapshot": len(runs),
            "runs_with_jobs_fetched": len(job_cov_runs),
            "jobs_rows": len(jobs),
            "sampled_runs_share_pct": cov_pct(len(job_cov_runs), len(runs)),
            "sampling": "bounded deterministic stride sample "
                        "(--jobs-window × --jobs-max-runs)",
            "jobs_windows": params.get("jobs_windows"),
        },
        "uncovered_remainder": {
            "runs_without_jobs_sample": {
                "runs": len(runs) - len(job_cov_runs),
                "share_pct": cov_pct(len(runs) - len(job_cov_runs), len(runs)),
                "why": "jobs 원장은 표본 창 내 run만 수집 — 미표본 run의 실행 "
                       "분은 billing에는 포함되지만 waste 표 분모 밖이다",
            },
            "workflows_outside_top_table": {
                "workflows_measured_total": len(wf_minutes),
                "workflows_in_table": len(waste),
                "minutes_outside_table": q(max(0.0, sampled_min_all - waste_min_sum), 3),
                "why": "waste 표는 측정 분 상위 25개 워크플로로 절단된다",
            },
            "non_runner_billing_usd": {
                "gross_usd": q(max(0.0, ghec_gross - runner_sku_gross)),
                "why": "스토리지·Git LFS bandwidth 등 비러너 청구 성분 — 러너 "
                       "분 기반 waste 표와 별개의 billing 성분이다",
            },
            "non_ghec_runner_minutes": {
                "minutes": q(non_ghec_min, 3),
                "why": "fallback(Ubicloud 등) 러너 분 — actual cash "
                       "UNKNOWN(Q7/Q11)으로 달러 환산 불가, 분만 기록된다",
            },
            "org_fixed_costs": "좌석·Enterprise Cloud 등 고정비는 "
                               "economic_indicators.fixed_cost — 변동비 "
                               "커버리지 집계 밖",
        },
    }

    economic = {
        "ghec_net_cash_usd": ghec_net,
        "ghec_gross_consumption_usd": ghec_gross,
        "ubicloud_actual_cash_usd": "UNKNOWN — 인간 소유 외부 입력 미제공 (Ubicloud billing API 부재, Q7/Q11; 실제 청구로만 기록)",
        "C_landing_usd_per_landing": (q(ghec_net / landing_count)
                                      if landing_count else None),
        "G_landing_usd_per_landing": (q(ghec_gross / landing_count)
                                      if landing_count else None),
        "fixed_cost": fixed,
        "notes": [
            "C_landing = (GHEC net + Ubicloud actual) ÷ 착지 수; Ubicloud actual이 UNKNOWN이면 GHEC-only 하한으로 표기된다",
            "착지 분모는 검증 통과 착지(base_ref==main + 2-parent MERGE, 도구 "
            "v2 필터)로 한정된다 — landing.verified_landing_definition 참조",
            "고정비(좌석 등)는 실행량 무관 항목으로 별도 표기한다",
            rates_note,
        ],
    }

    return {
        "schema": AGGREGATE_SCHEMA,
        "tool": TOOL,
        "tool_version": TOOL_VERSION,
        "observation_id": man["obs_id"],
        "snapshot": {
            "obs_id": man["obs_id"],
            "frozen_at_utc": man["frozen_at_utc"],
            "collected_at_utc": man["collected_at_utc"],
            "population": man["population"],
            "ledger_sha256": man["ledger_sha256"],
        },
        "parameters": params,
        "integrity": man["integrity"],
        "ghec_billing": ghec,
        "actions_minutes_by_sku_by_month": actions_minutes,
        "fixed_cost_usd": fixed,
        "runs_summary": {
            "total": len(runs),
            "by_event": dict(sorted(by_event.items())),
            "dup_rerun": {
                "definition": "동일 head_sha+event 로 2회 이상 실행된 런 (재실행·재트리거 중복)",
                "duplicate_groups": len(dup_groups),
                "duplicate_runs": dup_runs,
                "share_pct": q(100.0 * dup_runs / len(runs), 2) if runs else None,
                "duplicate_runs_by_event": dict(sorted(dup_by_event.items())),
            },
            "wait_run_split_by_event": event_latency,
            "workflows": {wf: by_workflow[wf] for wf in sorted(by_workflow)},
        },
        "runner_attribution": {
            "coverage": cov,
            **{k: v for k, v in sorted(runner.items())},
            "per_workflow_measured_minutes": {
                wf: wf_minutes[wf] for wf in sorted(wf_minutes)},
        },
        "landing": landing,
        "admission_latency": admission,
        "economic_indicators": economic,
        "waste_candidates": waste,
        "waste_coverage": waste_coverage,
        "determinism_note": "동일 snapshot 디렉터리 + 동일 파라미터로 본 집계를 재실행하면 "
                            "출력 JSON은 byte-identical이다(집계 중 라이브 조회 없음). "
                            "라이브 재조회 결과가 달라지는 것(적립·신규 run)은 결정론 위반이 아니며 "
                            "새 관측ID로 별도 기록한다.",
    }


def render_waste_md(agg):
    lines = []
    lines.append("| workflow | runs | merge_group | 측정 job 분 (표본) | GHEC 분 | "
                 "fallback 분 | 달러 환산(추정 참고치, GHEC 한계) | 중복 재실행 "
                 "비율(%) | 착지 기여도 | 변경 위험 |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---|---|")
    for w in agg["waste_candidates"]:
        lines.append("| `%s` | %d | %d | %s | %s | %s | %s | %s | %s | %s |" % (
            w["workflow"], w["runs"], w["merge_group_runs"],
            w["measured_job_minutes_subset"],
            w["measured_ghec_minutes_subset"],
            w["measured_fallback_minutes_subset"],
            "—" if w["est_usd_ghec_subset"] is None else w["est_usd_ghec_subset"],
            "—" if w["dup_runs_share_pct"] is None else w["dup_runs_share_pct"],
            w["landing_contribution"],
            w["change_risk"]))
    lines.append("")
    lines.append("- 측정 job 분은 jobs 표본 커버리지(--jobs-window stride 표본) 내의 값이다: %s"
                 % agg["runner_attribution"]["coverage"]["coverage_note"])
    lines.append("- 달러 환산은 GHEC 라벨 잡 한계의 추정 참고치(public 단가, pr_latency_attribution RUNNER_RATES 표)이며 "
                 "실제 청구가 아니다. fallback(Ubicloud) 잡은 달러 미환산(실제 청구 UNKNOWN, Q7/Q11). "
                 "실측 청구는 usage API gross/net 합계(ghec_billing)가 권위다.")
    lines.append("- **컬럼 정의 — 착지 기여도**: main 착지 경로 소비 형태의 등급. "
                 "`required_check` = 필수 5 checks 컨텍스트 제공(merge queue·main 착지 "
                 "게이트 직접 소비 — 판정: workflow path stem == required context, 또는 "
                 "표본 jobs 원장에서 해당 워크플로 job 이름이 required context) · "
                 "`merge_queue` = merge_group 런 존재(merge queue admission 체인 소비) · "
                 "`none` = main 착지 경로 기여 없음.")
    lines.append("- **컬럼 정의 — 변경 위험**: 이 표를 근거로 워크플로를 감축·변경할 때의 "
                 "위험 등급. `high` = 착지 기여도 `required_check`(필수 검증 의미 변경 "
                 "위험) · `medium` = `merge_queue`(착지 경로 관측 의미 변경 위험) · "
                 "`low` = 그 외. FROZEN 경계 여부 등 snapshot 밖 판단은 본 등급에 "
                 "반영되지 않는다(snapshot-only 관측 한계).")
    req_rows = [w for w in agg["waste_candidates"]
                if w["landing_contribution"] == "required_check"]
    if req_rows:
        prov = ", ".join(
            "`%s`→%s" % (w["workflow"], "+".join(w["required_check_contexts"]))
            for w in req_rows)
    else:
        prov = "(이 표 범위 내 required_check 제공 워크플로 없음)"
    lines.append("- **필수 5 checks 비대상 각주**: admission-check · bsec-integrity · "
                 "debt-registry-gate · generation-acceptance · "
                 "axiom-operational-slice는 병합 보증(merge admission)의 필수 검증을 "
                 "소비한다 — 이 컨텍스트를 제공하는 워크플로(착지 기여도 `required_check`, "
                 "변경 위험 `high` 행)는 낭비 최적화 **비대상**이다. 현재 표의 해당 "
                 "워크플로: %s. 표 달러 합계의 낙관 해석 전에 이 행들의 소비는 "
                 "감축 불가능한 필수 비용으로 분리해야 한다." % prov)
    wc = agg.get("waste_coverage") or {}
    if wc:
        usd = wc.get("usd") or {}
        lines.append("- **커버리지**: 이 표 est 합계 $%s는 billing gross $%s의 %s%%이다"
                     " — 미커버 잔여의 분해는 aggregate JSON `waste_coverage` 블록 참조"
                     " (B2 낭비 후보 대표성 판단의 전제)."
                     % (usd.get("waste_table_est_usd_sum"),
                        usd.get("billing_gross_usd"),
                        usd.get("coverage_pct")))
    return "\n".join(lines) + "\n"


def cmd_aggregate(args):
    obs_dir = os.path.join(args.data_dir, args.obs_id)
    agg = aggregate(obs_dir)
    out = os.path.abspath(args.out)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(agg, fh, indent=2, sort_keys=True, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, out)
    print("[ci_cost] aggregate: %s" % out)
    wpath = None
    if args.waste_md:
        wpath = os.path.abspath(args.waste_md)
        os.makedirs(os.path.dirname(wpath), exist_ok=True)
        with open(wpath + ".tmp", "w", encoding="utf-8") as fh:
            fh.write(render_waste_md(agg))
        os.replace(wpath + ".tmp", wpath)
        print("[ci_cost] waste table: %s" % wpath)
    if args.derived_manifest:
        dm = {
            "schema": DERIVED_SCHEMA,
            "tool": TOOL,
            "tool_version": TOOL_VERSION,
            "tool_sha256": sha256_file(os.path.abspath(__file__)),
            "aggregate_schema": AGGREGATE_SCHEMA,
            "live_api_calls": 0,
            "replay_note": "freeze된 snapshot 전용 재생(aggregate stage) — "
                           "collect/fetch 경로 없음, 원본 snapshot은 불변",
            "derived_from": {
                "obs_id": args.obs_id,
                "data_dir": args.data_dir,
                "manifest_sha256": sha256_file(os.path.join(obs_dir, MANIFEST)),
                "ledger_sha256": agg["snapshot"]["ledger_sha256"],
                "frozen_at_utc": agg["snapshot"]["frozen_at_utc"],
            },
            "outputs": {
                "aggregate": {"path": args.out, "sha256": sha256_file(out)},
                "waste_md": ({"path": args.waste_md,
                              "sha256": sha256_file(wpath)}
                             if wpath else None),
            },
        }
        dpath = os.path.abspath(args.derived_manifest)
        os.makedirs(os.path.dirname(dpath), exist_ok=True)
        with open(dpath + ".tmp", "w", encoding="utf-8") as fh:
            json.dump(dm, fh, indent=2, sort_keys=True, ensure_ascii=False)
            fh.write("\n")
        os.replace(dpath + ".tmp", dpath)
        print("[ci_cost] derived manifest (tool %s): %s"
              % (TOOL_VERSION, dpath))
    return 0


# ---------------------------------------------------------------------------
# collect CLI
# ---------------------------------------------------------------------------

def parse_window(spec):
    if "/" not in spec:
        raise HardFail("--jobs-window must be SINCE/UNTIL: %s" % spec)
    a, b = spec.split("/", 1)
    for ts in (a, b):
        if not re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", ts):
            raise HardFail("timestamps must be ISO8601 Z form: %s" % spec)
    return a, b


def cmd_collect(args):
    obs_dir = os.path.join(args.data_dir, args.obs_id)
    if os.path.exists(os.path.join(obs_dir, MANIFEST)):
        raise HardFail("obs id already frozen: %s" % obs_dir)
    os.makedirs(os.path.join(obs_dir, LEDGER_DIRNAME), exist_ok=True)
    org, _repo_short = args.repo.split("/", 1)
    reuse = os.path.abspath(args.reuse_from) if args.reuse_from else None
    col = Collector(obs_dir, org, args.repo, reuse_obs_dir=reuse)
    col._ledger_len_init()

    params = {
        "org": org,
        "repo": args.repo,
        "usage_months": args.usage_month,
        "runs_since": args.runs_since,
        "runs_until": args.runs_until,
        "run_subwindow_hours": RUN_WINDOW_HOURS,
        "jobs_windows": [parse_window(w) for w in args.jobs_window],
        "jobs_max_runs": args.jobs_max_runs,
        "merged_since": args.merged_since,
        "merged_until": args.merged_until,
        "reuse_from_obs_id": os.path.basename(reuse) if reuse else None,
        "mla_since": args.mla_since,
        "mla_until": args.mla_until,
    }
    for month in args.usage_month:
        year, mon = month.split("-")
        n = col.collect_usage(int(year), int(mon))
        print("[ci_cost] usage %s: %d rows" % (month, n))
    col.collect_budgets()
    if args.runs_since and args.runs_until:
        n = col.collect_runs(args.runs_since, args.runs_until)
        print("[ci_cost] runs %s..%s: %d rows" % (args.runs_since, args.runs_until, n))
    if params["jobs_windows"]:
        n = col.collect_jobs([parse_window(w) for w in args.jobs_window],
                             args.jobs_max_runs)
        print("[ci_cost] jobs sampled: %d rows" % n)
    if args.merged_since and args.merged_until:
        n = col.collect_merges(args.merged_since, args.merged_until)
        n2 = col.collect_merge_commits()
        print("[ci_cost] merged PRs: %d, merge commits verified: %d" % (n, n2))
    if args.mla_since and args.mla_until:
        script = os.path.join(args.mla_dir, "merge_latency_audit.sh")
        col.collect_mla(script, args.mla_since, args.mla_until)
    col.write_collection_log(params)
    print("[ci_cost] collect complete: %s (requests=%d failures=%d)"
          % (obs_dir, col.api.requests, col.api.failures))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description="CI cost observation (collect/freeze/aggregate)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    pc = sub.add_parser("collect")
    pc.add_argument("--obs-id", required=True)
    pc.add_argument("--data-dir", default="data/ci_cost")
    pc.add_argument("--repo", default="Archright/Axiom")
    pc.add_argument("--usage-month", action="append", required=True,
                    help="YYYY-MM (repeatable)")
    pc.add_argument("--runs-since"); pc.add_argument("--runs-until")
    pc.add_argument("--jobs-window", action="append", default=[],
                    help="SINCE/UNTIL (repeatable)")
    pc.add_argument("--jobs-max-runs", type=int, default=300)
    pc.add_argument("--merged-since"); pc.add_argument("--merged-until")
    pc.add_argument("--mla-since"); pc.add_argument("--mla-until")
    pc.add_argument("--mla-dir", default="tools/ci")
    pc.add_argument("--reuse-from", help="previous obs dir for ETag/304 reuse")
    pc.set_defaults(func=cmd_collect)

    pf = sub.add_parser("freeze")
    pf.add_argument("--obs-id", required=True)
    pf.add_argument("--data-dir", default="data/ci_cost")
    pf.add_argument("--repo", default="Archright/Axiom")
    pf.set_defaults(func=cmd_freeze)

    pa = sub.add_parser("aggregate")
    pa.add_argument("--obs-id", required=True)
    pa.add_argument("--data-dir", default="data/ci_cost")
    pa.add_argument("--out", required=True)
    pa.add_argument("--waste-md")
    pa.add_argument("--derived-manifest",
                    help="write a derived-output manifest recording the tool "
                         "version (TOOL_VERSION + tool sha256) next to the "
                         "replayed aggregate — for derived_v2-style replays")
    pa.set_defaults(func=cmd_aggregate)

    args = ap.parse_args(argv)
    try:
        return args.func(args)
    except HardFail as exc:
        print("[ci_cost] HARD-FAIL: %s" % exc, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
