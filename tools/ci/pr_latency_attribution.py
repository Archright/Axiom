#!/usr/bin/env python3
"""PR-to-main latency attribution (read-only Reporter).

Contract: docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md (measurement
contract v2). This tool is a Reporter, not an authority: it never changes GitHub
merge authority, required checks, rulesets, or any gate. It performs only GET
(REST) and query (GraphQL) calls through the native `gh` CLI (AGENTS.md §2.4).

Two measurement layers:
  * wall_partition  — non-overlapping intervals covering [createdAt, mergedAt];
                      sum(partition) + unattributed == TOT (±2 s).
  * diagnostic_overlays — review_wait, CI coverage, incident overlay, author
                      after CI; may overlap and are NEVER summed into TOT.

Canonical outputs are explicit (--json-out / --md-out / --jsonl-out); there is
no implicit <prefix>.summary.json path.

Usage:
  python3 tools/ci/pr_latency_attribution.py --self-test
  python3 tools/ci/pr_latency_attribution.py \
    --repo Archright/Axiom --since 2026-07-21 --until 2026-10-19 --max-prs 5000 \
    --json-out data/ci_optimization/pr_to_main_attribution_2026-10-19.json \
    --md-out docs/evidence/pr_to_main_attribution_2026-10-19.md \
    --jsonl-out data/ci_optimization/pr_to_main_attribution_2026-10-19.prs.jsonl

Re-arm verdicts (merge-queue-rearm.yml structured job-log lines, `^{"rearm":`)
are ingested additively under `rearm_ingest` (bounded by --max-rearm-runs);
existing keys and sections are unchanged.
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
import tempfile
import time
from datetime import datetime, timezone
from typing import Any, Dict, Iterable, List, Optional, Sequence, Tuple
from urllib.parse import quote

SCHEMA_VERSION = "axiom.pr-to-main-attribution.v1"
SLO_MG_TARGET_S = 480.0
HUMAN_IDLE_THRESHOLD_S = 1800.0

# Official Actions runner rates (USD/minute), used only for ESTIMATES.
RUNNER_RATES = {
    "ubuntu-24.04": 0.006,
    "ubuntu-latest": 0.006,
    "ubuntu-22.04": 0.006,
    "ubuntu-24.04-arm": 0.005,
    "ubuntu-22.04-arm": 0.005,
    "ubuntu-slim": 0.002,
    "windows-latest": 0.010,
    "windows-24.04": 0.010,
    "macos-latest": 0.062,
    "macos-14": 0.062,
}

PARTITION_LABELS = [
    "pre_ci",
    "pr_head_ci",
    "pr_head_idle",
    "pre_enqueue_gap",
    "queue_wait",
    "mg_ci",
    "between_cycle_gap",
    "merge_tail",
    "unattributed",
]

INCIDENT_CLASSES = [
    "merged_normal",
    "dequeued_failed_checks",
    "dequeued_merge_conflict",
    "dequeued_manual",
    "dequeued_invalidated",
    "dequeued_other",
    "stale_base",
    "venue_red",
    "review_blocked",
    "runner_infra",
    "red_retry",
    "human_idle",
    "closed_unmerged",
    "unknown",
]

PR_QUERY = """
query {
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      number
      createdAt
      mergedAt
      closedAt
      isDraft
      baseRefName
      headRefOid
      mergeCommit { oid }
      commits(first: 100%s) {
        pageInfo { hasNextPage endCursor }
        nodes { commit { oid committedDate authoredDate } }
      }
      reviews(first: 100%s) {
        pageInfo { hasNextPage endCursor }
        nodes { state submittedAt author { login } }
      }
      timelineItems(first: 100%s, itemTypes: [ADDED_TO_MERGE_QUEUE_EVENT, REMOVED_FROM_MERGE_QUEUE_EVENT, MERGED_EVENT, REVIEW_REQUESTED_EVENT, REVIEW_REQUEST_REMOVED_EVENT, READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT, REVIEW_DISMISSED_EVENT, BASE_REF_CHANGED_EVENT, HEAD_REF_FORCE_PUSHED_EVENT]) {
        pageInfo { hasNextPage endCursor }
        nodes {
          __typename
          ... on AddedToMergeQueueEvent { createdAt }
          ... on RemovedFromMergeQueueEvent { createdAt reason }
          ... on MergedEvent { createdAt }
          ... on ReviewRequestedEvent { createdAt }
          ... on ReviewRequestRemovedEvent { createdAt }
          ... on ReadyForReviewEvent { createdAt }
          ... on ConvertToDraftEvent { createdAt }
          ... on ReviewDismissedEvent { createdAt }
          ... on BaseRefChangedEvent { createdAt currentRefName previousRefName }
          ... on HeadRefForcePushedEvent { createdAt beforeCommit { oid } afterCommit { oid } }
        }
      }
    }
  }
}
"""

CONNECTION_QUERIES = {
    "commits": """
query {
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      commits(first: 100, after: %s) {
        pageInfo { hasNextPage endCursor }
        nodes { commit { oid committedDate authoredDate } }
      }
    }
  }
}
""",
    "reviews": """
query {
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      reviews(first: 100, after: %s) {
        pageInfo { hasNextPage endCursor }
        nodes { state submittedAt author { login } }
      }
    }
  }
}
""",
    "timelineItems": """
query {
  repository(owner: "%s", name: "%s") {
    pullRequest(number: %d) {
      timelineItems(first: 100, after: %s, itemTypes: [ADDED_TO_MERGE_QUEUE_EVENT, REMOVED_FROM_MERGE_QUEUE_EVENT, MERGED_EVENT, REVIEW_REQUESTED_EVENT, REVIEW_REQUEST_REMOVED_EVENT, READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT, REVIEW_DISMISSED_EVENT, BASE_REF_CHANGED_EVENT, HEAD_REF_FORCE_PUSHED_EVENT]) {
        pageInfo { hasNextPage endCursor }
        nodes {
          __typename
          ... on AddedToMergeQueueEvent { createdAt }
          ... on RemovedFromMergeQueueEvent { createdAt reason }
          ... on MergedEvent { createdAt }
          ... on ReviewRequestedEvent { createdAt }
          ... on ReviewRequestRemovedEvent { createdAt }
          ... on ReadyForReviewEvent { createdAt }
          ... on ConvertToDraftEvent { createdAt }
          ... on ReviewDismissedEvent { createdAt }
          ... on BaseRefChangedEvent { createdAt currentRefName previousRefName }
          ... on HeadRefForcePushedEvent { createdAt beforeCommit { oid } afterCommit { oid } }
        }
      }
    }
  }
}
""",
}


# ---------------------------------------------------------------------------
# Time / interval helpers
# ---------------------------------------------------------------------------

def iso_to_epoch(value: Optional[str]) -> Optional[float]:
    if not value:
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None


def epoch_to_iso(value: Optional[float]) -> Optional[str]:
    if value is None:
        return None
    return datetime.fromtimestamp(value, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def merge_intervals(intervals: Iterable[Tuple[float, float]]) -> List[Tuple[float, float]]:
    items = sorted((float(s), float(e)) for s, e in intervals if e is not None and s is not None and e > s)
    out: List[List[float]] = []
    for start, end in items:
        if out and start <= out[-1][1]:
            out[-1][1] = max(out[-1][1], end)
        else:
            out.append([start, end])
    return [(s, e) for s, e in out]


def union_duration(intervals: Iterable[Tuple[float, float]]) -> float:
    return sum(e - s for s, e in merge_intervals(intervals))


def clip_intervals(intervals: Iterable[Tuple[float, float]], start: float, end: float) -> List[Tuple[float, float]]:
    out = []
    for s, e in intervals:
        cs, ce = max(s, start), min(e, end)
        if ce > cs:
            out.append((cs, ce))
    return merge_intervals(out)


def r7(values: Sequence[float], p: float) -> Optional[float]:
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


def summarize(values: Sequence[Optional[float]]) -> Dict[str, Any]:
    vals = [float(v) for v in values if v is not None]
    if not vals:
        return {"n": 0, "p50": None, "p95": None, "mean": None, "min": None, "max": None}
    return {
        "n": len(vals),
        "p50": round(r7(vals, 0.50), 3),
        "p95": round(r7(vals, 0.95), 3),
        "mean": round(sum(vals) / len(vals), 3),
        "min": round(min(vals), 3),
        "max": round(max(vals), 3),
    }


def total_seconds(segments: Sequence[Tuple[str, float, float]]) -> Dict[str, float]:
    out: Dict[str, float] = {label: 0.0 for label in PARTITION_LABELS}
    for label, start, end in segments:
        out[label] = out.get(label, 0.0) + max(0.0, end - start)
    return out


# ---------------------------------------------------------------------------
# Partition builder (pure, deterministic, self-testable)
# ---------------------------------------------------------------------------

def build_partition(
    created: float,
    merged: float,
    pr_ci: Sequence[Tuple[float, float]],
    mg_cycles: Dict[int, Sequence[Tuple[float, float]]],
    adds: Sequence[float],
) -> List[Tuple[str, float, float]]:
    """Cover [created, merged] exactly with labelled, non-overlapping segments.

    Phase model: [created, add_0) is the PR-head phase; each [add_i, add_{i+1})
    (or [add_last, merged)) is a queue cycle. Within the PR-head phase, CI union
    is `pr_head_ci`; the first gap is `pre_ci`, later gaps `pr_head_idle`, and
    the trailing gap `pre_enqueue_gap`. Within a cycle, the pre-run gap is
    `queue_wait`, the run union is `mg_ci`, and the trailing gap is
    `between_cycle_gap` (non-final) or `merge_tail` (final). Any residue is
    `unattributed` (fail-closed, never silently dropped).
    """
    segments: List[Tuple[str, float, float]] = []
    adds_sorted = sorted(float(a) for a in adds if created <= float(a) <= merged)

    if not adds_sorted:
        phases = [("pr_head", created, merged, [])]
    else:
        phases = [("pr_head", created, adds_sorted[0], [])]
        for idx, add_ts in enumerate(adds_sorted):
            end = adds_sorted[idx + 1] if idx + 1 < len(adds_sorted) else merged
            if end > add_ts:
                phases.append(("cycle_%d" % idx, add_ts, end, list(mg_cycles.get(idx, []))))

    last_phase_index = len(phases) - 1
    for phase_index, (kind, start, end, mg_ivs) in enumerate(phases):
        if end <= start:
            continue
        if kind == "pr_head":
            cis = clip_intervals(pr_ci, start, end)
            cursor = start
            seen_ci = False
            for s, e in cis:
                if s > cursor:
                    label = "pr_head_idle" if seen_ci else "pre_ci"
                    segments.append((label, cursor, s))
                segments.append(("pr_head_ci", s, e))
                cursor = e
                seen_ci = True
            if cursor < end:
                segments.append(("pre_enqueue_gap" if seen_ci else "pre_ci", cursor, end))
        else:
            cis = clip_intervals(mg_ivs, start, end)
            cursor = start
            for s, e in cis:
                if s > cursor:
                    segments.append(("queue_wait", cursor, s))
                segments.append(("mg_ci", s, e))
                cursor = e
            if cursor < end:
                label = "merge_tail" if phase_index == last_phase_index else "between_cycle_gap"
                segments.append((label, cursor, end))

    covered = sum(max(0.0, e - s) for _, s, e in segments)
    residue = (merged - created) - covered
    if residue > 1e-6:
        segments.append(("unattributed", merged - residue, merged))
    return segments


# ---------------------------------------------------------------------------
# GitHub client (GET/query only, cached)
# ---------------------------------------------------------------------------

class GhError(RuntimeError):
    pass


class GhClient:
    def __init__(self, repo: str, cache_dir: Optional[str] = None, verbose: bool = False):
        self.repo = repo
        self.owner, self.name = repo.split("/", 1)
        self.cache_dir = cache_dir
        self.verbose = verbose
        self._memory: Dict[str, Any] = {}
        if cache_dir:
            os.makedirs(cache_dir, exist_ok=True)

    def _log(self, msg: str) -> None:
        if self.verbose:
            print("[gh] " + msg, file=sys.stderr)

    def _cache_path(self, key: str) -> str:
        digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
        return os.path.join(self.cache_dir or "", digest + ".json")

    def _run(self, args: Sequence[str], cache_key: str) -> Any:
        if cache_key in self._memory:
            return self._memory[cache_key]
        if self.cache_dir:
            path = self._cache_path(cache_key)
            if os.path.exists(path):
                try:
                    with open(path, "r", encoding="utf-8") as fh:
                        data = json.load(fh)
                    self._memory[cache_key] = data
                    return data
                except Exception:
                    pass
        last_err = None
        for attempt in range(4):
            try:
                proc = subprocess.run(
                    list(args), capture_output=True, text=True, check=False
                )
                if proc.returncode == 0:
                    text = proc.stdout.strip()
                    data = json.loads(text) if text else None
                    self._memory[cache_key] = data
                    if self.cache_dir:
                        with open(self._cache_path(cache_key), "w", encoding="utf-8") as fh:
                            json.dump(data, fh)
                    return data
                err = (proc.stderr or proc.stdout or "").strip()
                last_err = err
                if "rate limit" in err.lower() or "secondary rate" in err.lower():
                    self._log("rate limited; sleeping 60s (attempt %d)" % (attempt + 1))
                    time.sleep(60)
                    continue
                raise GhError(err[:800])
            except GhError:
                raise
            except Exception as exc:  # pragma: no cover - transport
                last_err = str(exc)
                time.sleep(2 + attempt * 2)
        raise GhError(str(last_err))

    def rest(self, path: str, paginate: bool = False) -> Any:
        args = ["gh", "api", path]
        if paginate:
            args += ["--paginate", "--slurp"]
        return self._run(args, "rest:" + path + (":paginated" if paginate else ""))

    def graphql(self, query: str) -> Any:
        args = ["gh", "api", "graphql", "-f", "query=" + query]
        return self._run(args, "graphql:" + hashlib.sha256(query.encode()).hexdigest())

    # -- REST ------------------------------------------------------------
    def list_closed_prs(self, since: float, until: float, max_prs: int) -> Dict[str, Any]:
        page = 1
        collected: List[Dict[str, Any]] = []
        cap_hit = False
        exhausted = False
        page_cap_hit = False
        while True:
            path = (
                "repos/%s/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=%d"
                % (self.repo, page)
            )
            batch = self.rest(path) or []
            if not isinstance(batch, list) or not batch:
                exhausted = True
                break
            for pr in batch:
                collected.append(pr)
                if len(collected) >= max_prs:
                    cap_hit = True
                    break
            if cap_hit:
                break
            if len(batch) < 100:
                exhausted = True
                break
            page += 1
            if page > 500:
                page_cap_hit = True
                break
        merged = []
        unmerged = []
        for pr in collected:
            merged_at = iso_to_epoch(pr.get("merged_at"))
            closed_at = iso_to_epoch(pr.get("closed_at"))
            if merged_at is not None and since <= merged_at <= until:
                merged.append(pr)
            elif merged_at is None and closed_at is not None and since <= closed_at <= until:
                unmerged.append(pr)
        return {
            "merged": merged,
            "closed_unmerged": unmerged,
            "collected": len(collected),
            "cohort_complete": bool(exhausted and not cap_hit and not page_cap_hit),
            "partial_reason": None if (exhausted and not cap_hit and not page_cap_hit) else (
                "max_prs_cap_reached" if cap_hit else (
                    "page_cap_reached" if page_cap_hit else "enumeration_incomplete"
                )
            ),
        }

    def list_runs(self, event: Optional[str], since: float, until: float, workflow: Optional[str] = None) -> List[Dict[str, Any]]:
        """Enumerate runs without the API's 1,000-result pagination cap.

        The runs endpoint caps paginated results; a 90-day ``created=>=`` query
        silently returns only the newest 1,000 runs. Fetch day-sized slices and
        recursively halve any slice whose ``total_count`` exceeds what pagination
        returned. Deterministic; deduped by run id. ``workflow`` scopes the
        enumeration to a single workflow file, in which case ``event`` is an
        optional additional filter.
        """
        base = (
            "repos/%s/actions/workflows/%s/runs" % (self.repo, workflow)
            if workflow else "repos/%s/actions/runs" % self.repo
        )
        runs: List[Dict[str, Any]] = []
        seen = set()

        def fetch(start: float, end: float, depth: int = 0) -> List[Dict[str, Any]]:
            filters = ["per_page=100", "created=%s..%s" % (
                quote(epoch_to_iso(start), safe=""),
                quote(epoch_to_iso(end), safe=""),
            )]
            if event:
                filters.insert(0, "event=%s" % event)
            path = base + "?" + "&".join(filters)
            data = self.rest(path, paginate=True)
            pages = data if isinstance(data, list) else [data]
            got: List[Dict[str, Any]] = []
            total = None
            for page in pages:
                if isinstance(page, dict):
                    if total is None:
                        total = page.get("total_count")
                    got.extend(page.get("workflow_runs", []) or [])
            if depth < 5 and total is not None and total > len(got):
                mid = (start + end) / 2.0
                if start < mid < end:
                    return fetch(start, mid, depth + 1) + fetch(mid, end, depth + 1)
            return got

        cursor = since
        while cursor < until:
            end = min(cursor + 86400.0, until)
            for run in fetch(cursor, end):
                rid = run.get("id")
                if rid in seen:
                    continue
                seen.add(rid)
                created = iso_to_epoch(run.get("created_at"))
                if created is not None and since <= created <= until:
                    runs.append(run)
            cursor = end
        return runs

    def jobs(self, run_id: int, attempt: Optional[int] = None) -> List[Dict[str, Any]]:
        if attempt:
            path = "repos/%s/actions/runs/%d/attempts/%d/jobs?per_page=100" % (self.repo, run_id, attempt)
        else:
            path = "repos/%s/actions/runs/%d/jobs?per_page=100" % (self.repo, run_id)
        data = self.rest(path, paginate=True)
        pages = data if isinstance(data, list) else [data]
        out: List[Dict[str, Any]] = []
        for page in pages:
            if isinstance(page, dict):
                out.extend(page.get("jobs", []) or [])
        return out

    def attempt(self, run_id: int, attempt: int) -> Dict[str, Any]:
        return self.rest(
            "repos/%s/actions/runs/%d/attempts/%d" % (self.repo, run_id, attempt)
        ) or {}

    def run_log(self, run_id: int) -> Dict[str, Any]:
        """Fetch one run's full log text via `gh run view --log` (GET only).

        Returns {"available": bool, "text": str, "reason": Optional[str]}.
        Missing/expired/unreadable logs are cached as unavailable (they do not
        heal) and never raise; the caller records an unknown instead.
        """
        key = "runlog:%d" % run_id
        if key in self._memory:
            return self._memory[key]
        if self.cache_dir:
            path = self._cache_path(key)
            if os.path.exists(path):
                try:
                    with open(path, "r", encoding="utf-8") as fh:
                        data = json.load(fh)
                    self._memory[key] = data
                    return data
                except Exception:
                    pass
        args = ["gh", "run", "view", str(run_id), "-R", self.repo, "--log"]
        data: Optional[Dict[str, Any]] = None
        last_err = ""
        for _ in range(3):
            proc = subprocess.run(list(args), capture_output=True, text=True, check=False)
            if proc.returncode == 0:
                data = {"available": True, "text": proc.stdout, "reason": None}
                break
            last_err = (proc.stderr or proc.stdout or "").strip()
            if "rate limit" in last_err.lower() or "secondary rate" in last_err.lower():
                self._log("rate limited fetching log for run %d; sleeping 60s" % run_id)
                time.sleep(60)
                continue
            break
        if data is None:
            data = {"available": False, "text": "", "reason": (last_err or "gh run view failed")[:300]}
        self._memory[key] = data
        if self.cache_dir:
            with open(self._cache_path(key), "w", encoding="utf-8") as fh:
                json.dump(data, fh)
        return data

    def billing_usage(self, year: int, month: int) -> Dict[str, Any]:
        try:
            return self.rest(
                "orgs/%s/settings/billing/usage?year=%d&month=%d" % (self.owner, year, month)
            ) or {}
        except GhError as exc:
            return {"available": False, "reason": str(exc)[:300]}

    # -- GraphQL ---------------------------------------------------------
    def fetch_pr(self, number: int) -> Dict[str, Any]:
        cursor_args = ("", "", "")
        query = PR_QUERY % (self.owner, self.name, number, *cursor_args)
        data = self.graphql(query)
        pr = (data or {}).get("data", {}).get("repository", {}).get("pullRequest")
        if not pr:
            raise GhError("PR #%d not found" % number)

        for field in ("commits", "reviews", "timelineItems"):
            nodes = list((pr.get(field) or {}).get("nodes") or [])
            page_info = (pr.get(field) or {}).get("pageInfo") or {}
            pages = 0
            while page_info.get("hasNextPage") and pages < 10:
                cursor = json.dumps(page_info.get("endCursor"))
                q = CONNECTION_QUERIES[field] % (self.owner, self.name, number, cursor)
                extra = self.graphql(q)
                conn = (((extra or {}).get("data", {}).get("repository", {}) or {})
                        .get("pullRequest", {}) or {}).get(field, {})
                nodes.extend(list(conn.get("nodes") or []))
                page_info = conn.get("pageInfo") or {}
                pages += 1
            pr[field] = {"nodes": nodes, "pageInfo": {"hasNextPage": False}}
        return pr


# ---------------------------------------------------------------------------
# Run indexing and per-PR analysis
# ---------------------------------------------------------------------------

def run_interval(run: Dict[str, Any]) -> Optional[Tuple[float, float]]:
    start = iso_to_epoch(run.get("run_started_at")) or iso_to_epoch(run.get("created_at"))
    end = iso_to_epoch(run.get("updated_at"))
    if start is None or end is None or end <= start:
        return None
    return (start, end)


def run_label(run: Dict[str, Any]) -> str:
    labels = []
    for job in run.get("labels") or []:
        if isinstance(job, dict):
            labels.append(job.get("name"))
        else:
            labels.append(str(job))
    return ",".join(x for x in labels if x) or "unknown"


def parse_group_members(head_branch: Optional[str]) -> List[int]:
    if not head_branch:
        return []
    return sorted({int(x) for x in re.findall(r"pr-(\d+)-", head_branch)})


def index_runs(runs: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    by_sha: Dict[str, List[Dict[str, Any]]] = {}
    mg_by_pr: Dict[int, List[Dict[str, Any]]] = {}
    by_branch: Dict[str, List[Dict[str, Any]]] = {}
    for run in runs:
        event = run.get("event")
        if event == "pull_request":
            sha = run.get("head_sha")
            if sha:
                by_sha.setdefault(sha, []).append(run)
        elif event == "merge_group":
            branch = run.get("head_branch") or ""
            by_branch.setdefault(branch, []).append(run)
            for pr_number in parse_group_members(branch):
                mg_by_pr.setdefault(pr_number, []).append(run)
    return {"by_sha": by_sha, "mg_by_pr": mg_by_pr, "by_branch": by_branch}


def pr_head_runs(pr: Dict[str, Any], index: Dict[str, Any], created: float, merged: float) -> List[Dict[str, Any]]:
    shas = {c.get("commit", {}).get("oid") for c in (pr.get("commits") or {}).get("nodes", [])}
    shas = {s for s in shas if s}
    seen = {}
    for sha in shas:
        for run in index["by_sha"].get(sha, []):
            seen[run.get("id")] = run
    # Fallback: runs whose pull_requests field names this PR (docs warn it is not authoritative)
    number = pr.get("number")
    for run in index.get("all_pull_request_runs", []):
        for ref in run.get("pull_requests") or []:
            if ref.get("number") == number:
                seen.setdefault(run.get("id"), run)
    runs = []
    for run in seen.values():
        iv = run_interval(run)
        if iv and iv[0] <= merged and iv[1] >= created:
            runs.append(run)
    return sorted(runs, key=lambda r: (r.get("created_at") or "", r.get("id") or 0))


def pr_mg_runs(pr_number: int, index: Dict[str, Any], created: float, merged: float) -> List[Dict[str, Any]]:
    runs = []
    for run in index["mg_by_pr"].get(pr_number, []):
        iv = run_interval(run)
        if iv and iv[0] <= merged + 300 and iv[1] >= created - 300:
            runs.append(run)
    return sorted(runs, key=lambda r: (r.get("created_at") or "", r.get("id") or 0))


def queue_events(pr: Dict[str, Any]) -> Dict[str, Any]:
    adds: List[float] = []
    removals: List[Dict[str, Any]] = []
    ready: Optional[float] = None
    review_requested: Optional[float] = None
    base_changes: List[float] = []
    force_pushes: List[Dict[str, Any]] = []
    for node in (pr.get("timelineItems") or {}).get("nodes", []) or []:
        kind = node.get("__typename")
        ts = iso_to_epoch(node.get("createdAt"))
        if kind == "AddedToMergeQueueEvent" and ts is not None:
            adds.append(ts)
        elif kind == "RemovedFromMergeQueueEvent" and ts is not None:
            removals.append({"ts": ts, "reason": node.get("reason")})
        elif kind == "ReadyForReviewEvent" and ts is not None and ready is None:
            ready = ts
        elif kind == "ReviewRequestedEvent" and ts is not None and review_requested is None:
            review_requested = ts
        elif kind == "BaseRefChangedEvent" and ts is not None:
            base_changes.append(ts)
        elif kind == "HeadRefForcePushedEvent" and ts is not None:
            force_pushes.append({"ts": ts, "before": (node.get("beforeCommit") or {}).get("oid"),
                                 "after": (node.get("afterCommit") or {}).get("oid")})
    adds = sorted(adds)
    removals = sorted(removals, key=lambda r: r["ts"])
    return {
        "adds": adds,
        "removals": removals,
        "ready": ready,
        "review_requested": review_requested,
        "base_changes": sorted(base_changes),
        "force_pushes": force_pushes,
    }


def cycle_intervals(mg_runs: Sequence[Dict[str, Any]], adds: Sequence[float], merged: float) -> Dict[int, List[Tuple[float, float]]]:
    out: Dict[int, List[Tuple[float, float]]] = {}
    for idx, add_ts in enumerate(adds):
        end = adds[idx + 1] if idx + 1 < len(adds) else merged
        ivs = []
        for run in mg_runs:
            iv = run_interval(run)
            if iv and iv[0] >= add_ts - 1 and iv[0] < end:
                ivs.append((max(iv[0], add_ts), min(iv[1], end)))
        out[idx] = merge_intervals(ivs)
    return out


def classify_incidents(
    pr: Dict[str, Any],
    events: Dict[str, Any],
    segments: Sequence[Tuple[float, float]],
    mg_runs: Sequence[Dict[str, Any]],
    merged: Optional[float],
    created: float,
    reviews: Sequence[Dict[str, Any]],
    annotation_lookup: Optional[Any] = None,
) -> Dict[str, Any]:
    classes: Dict[str, List[Tuple[float, float]]] = {}
    evidence: List[Dict[str, Any]] = []

    def add(cls: str, start: Optional[float], end: Optional[float], note: str,
            reason_code: Optional[str] = None) -> None:
        if start is None or end is None or end <= start:
            return
        classes.setdefault(cls, []).append((start, end))
        item = {"class": cls, "start": epoch_to_iso(start), "end": epoch_to_iso(end), "note": note}
        if reason_code:
            item["reason_code"] = reason_code
        evidence.append(item)

    if merged is None:
        closed = iso_to_epoch(pr.get("closedAt"))
        add("closed_unmerged", created, closed or created, "PR closed without merge")
        return {"primary": "closed_unmerged", "all_classes": ["closed_unmerged"],
                "intervals": {k: [[epoch_to_iso(s), epoch_to_iso(e)] for s, e in v] for k, v in classes.items()},
                "evidence": evidence}

    # Queue removals that are not the successful merge. Deduplicate duplicate
    # removals (same timestamp+reason) so intervals are not double-counted.
    seen_removals = set()
    for removal in sorted(events["removals"], key=lambda r: r["ts"]):
        reason = (removal.get("reason") or "").lower()
        if reason == "merged":
            continue
        dedupe_key = (round(float(removal["ts"]), 3), reason)
        if dedupe_key in seen_removals:
            continue
        seen_removals.add(dedupe_key)
        start = removal["ts"]
        later_adds = [a for a in events["adds"] if a > start]
        end = later_adds[0] if later_adds else merged
        if end is None or end <= start:
            end = merged
        failed_runs = []
        for run in mg_runs:
            iv = run_interval(run)
            if not iv:
                continue
            if iv[0] <= start + 5 and iv[1] >= start - 1800 and run.get("conclusion") in ("failure", "timed_out", "cancelled"):
                failed_runs.append(run)
        if any(start <= ts <= end for ts in events["base_changes"]):
            add("stale_base", start, end, "base ref changed during queue dwell")
        if failed_runs:
            codes = []
            if annotation_lookup:
                for run in failed_runs:
                    code = annotation_lookup(run)
                    if code:
                        codes.append(code)
            reason_code = codes[0] if codes else None
            add("venue_red", start, end,
                "failed merge_group run before removal: %s%s" % (
                    ",".join(str(r.get("id")) for r in failed_runs),
                    "; reason_codes=" + ",".join(sorted(set(codes))) if codes else ""),
                reason_code=reason_code)
        elif reason == "failed_checks":
            add("dequeued_failed_checks", start, end, "dequeue reason=failed_checks")
        elif reason == "merge_conflict":
            add("dequeued_merge_conflict", start, end, "dequeue reason=merge_conflict")
        elif reason == "manual":
            add("dequeued_manual", start, end, "dequeue reason=manual")
        elif reason == "invalidated":
            add("dequeued_invalidated", start, end, "dequeue reason=invalidated")
        elif reason:
            add("dequeued_other", start, end, "dequeue reason=%s" % reason)
        else:
            add("unknown", start, end, "dequeue reason unavailable")

    # Red retries
    for run in mg_runs + list(pr.get("_pr_head_runs", [])):
        if int(run.get("run_attempt") or 1) > 1:
            start = iso_to_epoch(run.get("created_at"))
            end = iso_to_epoch(run.get("updated_at"))
            add("red_retry", start, end, "run_attempt=%s run=%s" % (run.get("run_attempt"), run.get("id")))

    # Human idle: long non-CI gaps
    for label, start, end in segments:
        if label in ("pre_ci", "pr_head_idle", "pre_enqueue_gap") and (end - start) >= HUMAN_IDLE_THRESHOLD_S:
            add("human_idle", start, end, "no CI/queue event for >= %ds (%s)" % (int(HUMAN_IDLE_THRESHOLD_S), label))

    # Review blocked
    for review in reviews:
        if (review.get("state") or "").upper() == "CHANGES_REQUESTED":
            ts = iso_to_epoch(review.get("submittedAt"))
            add("review_blocked", ts, merged, "CHANGES_REQUESTED review")

    if not classes:
        add("merged_normal", created, merged, "no incident evidence")
    primary = max(classes.items(), key=lambda kv: sum(e - s for s, e in kv[1]))[0]
    return {
        "primary": primary,
        "all_classes": sorted(classes.keys()),
        "intervals": {k: [[epoch_to_iso(s), epoch_to_iso(e)] for s, e in v] for k, v in classes.items()},
        "evidence": evidence,
    }


def cost_for_run(run: Dict[str, Any], jobs: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    minutes = 0.0
    labels = set()
    for job in jobs:
        start = iso_to_epoch(job.get("started_at"))
        end = iso_to_epoch(job.get("completed_at"))
        if start is not None and end is not None and end > start:
            minutes += (end - start) / 60.0
        for label in job.get("labels") or []:
            labels.add(label if isinstance(label, str) else str(label))
    rate = None
    for label in sorted(labels):
        if label in RUNNER_RATES:
            rate = RUNNER_RATES[label]
            break
    estimate = None if rate is None else round(minutes * rate, 6)
    return {
        "job_minutes": round(minutes, 3),
        "runner_labels": sorted(labels),
        "rate_usd_per_minute": rate,
        "estimate_usd": estimate,
        "basis": "estimate" if estimate is not None else "unknown",
    }


# ---------------------------------------------------------------------------
# Re-arm verdict ingestion (merge-queue-rearm.yml structured job-log lines)
# ---------------------------------------------------------------------------

REARM_WORKFLOW = "merge-queue-rearm.yml"
REARM_LINE_PREFIX = '{"rearm":'
REARM_CLASSES = ("TRANSIENT", "PERMANENT", "UNKNOWN")
REARM_ACTIONS = ("arm", "no-arm")
REARM_LOG_TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z\s+")
REARM_HEAD_RE = re.compile(r"^[0-9a-f]{6,40}$")


def extract_rearm_lines(text: str) -> List[str]:
    """Return only structured rearm verdict lines from a run log.

    `gh run view --log` renders each raw log line as `<job>\\t<step>\\t<line>`
    and the runner prefixes raw lines with `<ISO timestamp> ` (optionally after
    a BOM). A line qualifies only if the content after those transport prefixes
    starts with `{"rearm":` — prose is never matched.
    """
    out: List[str] = []
    for raw in text.splitlines():
        payload = raw
        parts = raw.split("\t")
        if len(parts) >= 3:
            payload = "\t".join(parts[2:])
        payload = payload.strip().lstrip("\ufeff")
        payload = REARM_LOG_TS_RE.sub("", payload, count=1)
        if payload.startswith(REARM_LINE_PREFIX):
            out.append(payload)
    return out


def parse_rearm_verdict(line: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Parse one structured verdict line; returns (None, reason) on any doubt.

    Fail-closed: a malformed, incomplete, or out-of-enum line is never reported
    as an `arm` — it becomes a recorded unknown instead.
    """
    try:
        doc = json.loads(line)
    except ValueError:
        return None, "malformed_json"
    if not isinstance(doc, dict) or not isinstance(doc.get("rearm"), dict):
        return None, "missing_rearm_object"
    body = doc["rearm"]
    pr = body.get("pr")
    if isinstance(pr, str):
        try:
            pr = int(pr)
        except ValueError:
            pr = None
    if isinstance(pr, bool) or not isinstance(pr, int) or pr <= 0:
        return None, "invalid_pr"
    head = body.get("head")
    if not isinstance(head, str) or not REARM_HEAD_RE.match(head.lower()):
        return None, "invalid_head"
    cls = body.get("class")
    if cls not in REARM_CLASSES:
        return None, "invalid_class"
    action = body.get("action")
    if action not in REARM_ACTIONS:
        return None, "invalid_action"
    reason = body.get("reason")
    budget = body.get("budget")
    return {
        "pr": pr,
        "head": head.lower(),
        "class": cls,
        "action": action,
        "reason": reason if isinstance(reason, str) else None,
        "budget": budget if isinstance(budget, str) else None,
        "evidence": body.get("evidence"),
    }, None


def resolve_rearm_arms(
    verdicts: Sequence[Dict[str, Any]],
    queue_events_by_pr: Dict[int, Dict[str, Any]],
    pr_heads_by_pr: Dict[int, Sequence[str]],
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Bind arm verdicts to their PR's first queue add after the arm (pure).

    Latency = first AddedToMergeQueueEvent at or after the rearm job completion
    minus that completion time. Verdicts whose PR timeline is unavailable,
    whose head is not a head of the PR, or with no queue add after the arm are
    unresolvable, never fabricated. `no-arm` verdicts never yield a sample.
    """
    resolved: List[Dict[str, Any]] = []
    unresolvable: List[Dict[str, Any]] = []
    for verdict in verdicts:
        if verdict.get("action") != "arm":
            continue
        row = {"run_id": verdict.get("run_id"), "pr": verdict.get("pr"), "head": verdict.get("head")}
        arm_ts = verdict.get("arm_completed_at_epoch")
        if arm_ts is None:
            unresolvable.append({**row, "reason": "arm_completed_at_unavailable"})
            continue
        events = queue_events_by_pr.get(verdict.get("pr"))
        if events is None:
            unresolvable.append({**row, "reason": "pr_timeline_unavailable"})
            continue
        heads = pr_heads_by_pr.get(verdict.get("pr")) or []
        if not any(h and str(h).lower().startswith(verdict["head"]) for h in heads):
            unresolvable.append({**row, "reason": "verdict_head_not_a_pr_head"})
            continue
        adds_after = [a for a in events["adds"] if a >= arm_ts]
        if not adds_after:
            unresolvable.append({**row, "reason": "no_merge_queue_add_after_arm"})
            continue
        resolved.append({
            **row,
            "arm_completed_at": epoch_to_iso(arm_ts),
            "enqueue_add_at": epoch_to_iso(adds_after[0]),
            "arm_to_enqueue_s": round(adds_after[0] - arm_ts, 3),
        })
    return resolved, unresolvable


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

def analyze(
    client: GhClient,
    since: float,
    until: float,
    max_prs: int,
    sample: Optional[int] = None,
    verbose: bool = False,
    max_rearm_runs: int = 200,
) -> Dict[str, Any]:
    cohort = client.list_closed_prs(since, until, max_prs)
    merged_prs = cohort["merged"]
    if sample:
        merged_prs = merged_prs[:sample]
    closed_unmerged = cohort["closed_unmerged"]

    runs_pr = client.list_runs("pull_request", since, until)
    runs_mg = client.list_runs("merge_group", since, until)
    all_runs = runs_pr + runs_mg
    history_times = [iso_to_epoch(r.get("created_at")) for r in all_runs if r.get("created_at")]
    history_start = min(history_times) if history_times else None
    history_end = max(history_times) if history_times else None
    index = index_runs(all_runs)
    index["all_pull_request_runs"] = runs_pr

    pr_records: List[Dict[str, Any]] = []
    shared_runs: Dict[int, Dict[str, Any]] = {}
    unknowns: List[Dict[str, Any]] = []
    annotation_cache: Dict[Any, Optional[str]] = {}
    queue_events_by_pr: Dict[int, Dict[str, Any]] = {}
    pr_heads_by_pr: Dict[int, List[str]] = {}

    def annotation_lookup(run: Dict[str, Any]) -> Optional[str]:
        """Return the stable NOT_ADMIT_* reason code for a failed MG run, if any."""
        rid = run.get("id")
        if rid in annotation_cache:
            return annotation_cache[rid]
        code = None
        sha = run.get("head_sha")
        if sha:
            try:
                checks = client.rest("repos/%s/commits/%s/check-runs?per_page=100" % (client.repo, sha)) or {}
                for cr in checks.get("check_runs", []) or []:
                    if cr.get("conclusion") not in ("failure", "timed_out", "cancelled"):
                        continue
                    anns = client.rest(
                        "repos/%s/check-runs/%s/annotations?per_page=100" % (client.repo, cr.get("id"))
                    ) or []
                    blob = " ".join(
                        "%s %s %s" % (a.get("title") or "", a.get("message") or "", a.get("raw_details") or "")
                        for a in (anns if isinstance(anns, list) else [])
                    )
                    match = re.search(r"NOT_ADMIT_[A-Z0-9_]+", blob)
                    if match:
                        code = match.group(0)
                        break
            except GhError:
                code = None
        annotation_cache[rid] = code
        return code

    def minimal_record(pr: Dict[str, Any], created: float, merged: float, reason: str) -> Dict[str, Any]:
        """Cheap data-incomplete record: no GraphQL/timeline/jobs calls.

        The REST PR list already carries created_at/merged_at; when neither a
        PR-head run nor a merge-group run exists, fetching the full timeline
        cannot produce attribution. This keeps the audit cohort complete while
        avoiding hundreds of wasted API calls.
        """
        number = pr.get("number")
        tot = merged - created
        partition = {label: 0.0 for label in PARTITION_LABELS}
        partition["unattributed"] = round(tot, 3)
        return {
            "number": number,
            "title": pr.get("title"),
            "created_at": epoch_to_iso(created),
            "merged_at": epoch_to_iso(merged),
            "data_complete": False,
            "unknown_reason": reason,
            "tot_s": round(tot, 3),
            "tot_commit_date_s": None,
            "tot_ready_s": round(tot, 3),
            "push_time_basis": "unknown",
            "partition_s": partition,
            "partition_identity": {
                "sum_s": round(sum(partition.values()), 3),
                "tot_s": round(tot, 3),
                "delta_s": round(sum(partition.values()) - tot, 3),
                "ok": abs(sum(partition.values()) - tot) <= 2.0,
            },
            "overlays_s": {
                "review_wait": None,
                "review_advisory": True,
                "ci_coverage_union": 0.0,
                "incident_overlay": 0.0,
                "author_after_ci": 0.0,
            },
            "incident": {
                "primary": "unknown",
                "all_classes": ["unknown"],
                "intervals": {},
                "evidence": [{"class": "unknown", "note": reason}],
            },
            "queue": {"cycles": 0, "adds": [], "removals": []},
            "runs": {"pr_head": [], "merge_group": []},
            "cost": {
                "estimate_usd": None,
                "basis": "unknown",
                "allocation": "equal_split_among_known_group_members",
                "pr_head_job_minutes": 0.0,
            },
            "force_pushes": [],
        }

    for pos, pr in enumerate(merged_prs):
        number = pr.get("number")
        if verbose:
            print("[analyze] PR #%s (%d/%d)" % (number, pos + 1, len(merged_prs)), file=sys.stderr)
        head_sha = (pr.get("head") or {}).get("sha")
        has_pr_run = bool(head_sha and head_sha in index["by_sha"])
        has_mg_run = bool(index["mg_by_pr"].get(int(number)))
        if not has_pr_run and not has_mg_run:
            created = iso_to_epoch(pr.get("created_at"))
            merged = iso_to_epoch(pr.get("merged_at"))
            if created is None or merged is None or merged <= created:
                unknowns.append({"pr": number, "stage": "frame", "reason": "createdAt/mergedAt unavailable"})
                continue
            reason = "outside_run_history" if (history_start is not None and merged < history_start) else "no_run_for_head_sha"
            pr_records.append(minimal_record(pr, created, merged, reason))
            continue
        try:
            detail = client.fetch_pr(int(number))
        except GhError as exc:
            unknowns.append({"pr": number, "stage": "graphql_pr", "reason": str(exc)[:300]})
            continue
        created = iso_to_epoch(detail.get("createdAt"))
        merged = iso_to_epoch(detail.get("mergedAt"))
        if created is None or merged is None or merged <= created:
            unknowns.append({"pr": number, "stage": "frame", "reason": "createdAt/mergedAt unavailable"})
            continue
        events = queue_events(detail)
        mg_runs = pr_mg_runs(int(number), index, created, merged)
        head_runs = pr_head_runs(detail, index, created, merged)
        detail["_pr_head_runs"] = head_runs
        queue_events_by_pr[int(number)] = events
        pr_heads_by_pr[int(number)] = sorted({
            oid for oid in [detail.get("headRefOid")]
            + [c.get("commit", {}).get("oid") for c in (detail.get("commits") or {}).get("nodes", [])]
            if oid
        })
        pr_ci = [iv for iv in (run_interval(r) for r in head_runs) if iv]
        mg_cycles = cycle_intervals(mg_runs, events["adds"], merged)
        mg_ci_all = [iv for ivs in mg_cycles.values() for iv in ivs]
        has_pr_ci = bool(head_runs)
        has_mg = bool(mg_runs)
        has_admission = any("admission" in (r.get("name") or "") for r in mg_runs)
        has_queue = bool(events["adds"] or events["removals"])
        if has_pr_ci or has_mg:
            segments = build_partition(created, merged, pr_ci, mg_cycles, events["adds"])
        else:
            segments = [("unattributed", created, merged)]
        if not has_pr_ci and not has_mg:
            data_complete = False
            if history_start is not None and merged < history_start:
                unknown_reason = "outside_run_history"
            else:
                unknown_reason = "no_run_for_head_sha"
        elif not has_pr_ci:
            data_complete = False
            unknown_reason = "pr_head_ci_run_missing"
        elif has_queue and not has_admission:
            data_complete = False
            unknown_reason = "admission_gate_run_missing"
        else:
            data_complete = True
            unknown_reason = None
        totals = total_seconds(segments)
        tot = merged - created

        reviews = (detail.get("reviews") or {}).get("nodes", []) or []
        review_times = [iso_to_epoch(r.get("submittedAt")) for r in reviews if iso_to_epoch(r.get("submittedAt"))]
        review_start = events["ready"] or (min(s for s, _ in pr_ci) if pr_ci else created)
        review_wait = (min(review_times) - review_start) if review_times else None
        ci_union = union_duration(pr_ci + mg_ci_all)
        if has_pr_ci or has_mg:
            incidents = classify_incidents(
                detail, events, segments, mg_runs, merged, created, reviews,
                annotation_lookup=annotation_lookup,
            )
        else:
            incidents = {
                "primary": "unknown",
                "all_classes": ["unknown"],
                "intervals": {},
                "evidence": [{"class": "unknown", "note": "no CI/queue events; attribution unavailable"}],
            }
        incident_ivs = []
        for cls, ivs in incidents.get("intervals", {}).items():
            if cls == "merged_normal":
                continue
            for pair in ivs:
                a, b = iso_to_epoch(pair[0]), iso_to_epoch(pair[1])
                if a is not None and b is not None:
                    incident_ivs.append((a, b))
        incident_overlay = union_duration(incident_ivs)

        commit_dates = sorted(
            t for t in (iso_to_epoch(c.get("commit", {}).get("committedDate"))
                        for c in (detail.get("commits") or {}).get("nodes", []) or []) if t
        )
        author_after_ci = 0.0
        if commit_dates and pr_ci:
            for ci_end in [e for _, e in merge_intervals(pr_ci)]:
                after = [t for t in commit_dates if t > ci_end]
                if after:
                    author_after_ci += max(0.0, min(after) - ci_end)

        pr_head_cost = {"job_minutes": 0.0, "estimate_usd": 0.0, "basis": "estimate"}
        for run in head_runs:
            jobs = client.jobs(int(run["id"]), int(run.get("run_attempt") or 1))
            c = cost_for_run(run, jobs)
            pr_head_cost["job_minutes"] += c["job_minutes"]
            if c["estimate_usd"] is None:
                pr_head_cost["basis"] = "unknown"
            else:
                pr_head_cost["estimate_usd"] += c["estimate_usd"]
        mg_cost_share = 0.0
        mg_cost_unknown = False
        for run in mg_runs:
            run_id = int(run["id"])
            if run_id not in shared_runs:
                jobs = client.jobs(run_id, int(run.get("run_attempt") or 1))
                c = cost_for_run(run, jobs)
                members = parse_group_members(run.get("head_branch")) or [int(number)]
                shared_runs[run_id] = {
                    "run_id": run_id,
                    "event": run.get("event"),
                    "name": run.get("name"),
                    "head_branch": run.get("head_branch"),
                    "group_members": members,
                    "conclusion": run.get("conclusion"),
                    "run_attempt": run.get("run_attempt"),
                    **c,
                }
            entry = shared_runs[run_id]
            if entry.get("estimate_usd") is None:
                mg_cost_unknown = True
            else:
                mg_cost_share += entry["estimate_usd"] / max(1, len(entry["group_members"]))
        pr_cost_basis = "unknown" if (pr_head_cost["basis"] == "unknown" or mg_cost_unknown) else "estimate"
        pr_cost = {
            "estimate_usd": None if pr_cost_basis == "unknown" else round(pr_head_cost["estimate_usd"] + mg_cost_share, 6),
            "basis": pr_cost_basis,
            "allocation": "equal_split_among_known_group_members",
            "pr_head_job_minutes": round(pr_head_cost["job_minutes"], 3),
        }

        rec = {
            "number": number,
            "title": pr.get("title"),
            "created_at": epoch_to_iso(created),
            "merged_at": epoch_to_iso(merged),
            "data_complete": data_complete,
            "unknown_reason": unknown_reason,
            "tot_s": round(tot, 3),
            "tot_commit_date_s": round(merged - commit_dates[-1], 3) if commit_dates else None,
            "tot_ready_s": round(merged - (events["ready"] or created), 3),
            "push_time_basis": "committed_date" if commit_dates else "unknown",
            "partition_s": {k: round(v, 3) for k, v in totals.items()},
            "partition_identity": {
                "sum_s": round(sum(totals.values()), 3),
                "tot_s": round(tot, 3),
                "delta_s": round(sum(totals.values()) - tot, 3),
                "ok": abs(sum(totals.values()) - tot) <= 2.0,
            },
            "overlays_s": {
                "review_wait": None if review_wait is None else round(review_wait, 3),
                "review_advisory": not review_times,
                "ci_coverage_union": round(ci_union, 3),
                "incident_overlay": round(incident_overlay, 3),
                "author_after_ci": round(author_after_ci, 3),
            },
            "incident": incidents,
            "queue": {
                "cycles": len(events["adds"]),
                "adds": [epoch_to_iso(t) for t in events["adds"]],
                "removals": [{"ts": epoch_to_iso(r["ts"]), "reason": r.get("reason")} for r in events["removals"]],
            },
            "runs": {
                "pr_head": [r.get("id") for r in head_runs],
                "merge_group": [r.get("id") for r in mg_runs],
            },
            "cost": pr_cost,
            "force_pushes": events["force_pushes"],
        }
        pr_records.append(rec)

    # Closed-unmerged census
    unmerged_records = []
    for pr in closed_unmerged:
        created = iso_to_epoch(pr.get("created_at"))
        closed = iso_to_epoch(pr.get("closed_at"))
        unmerged_records.append({
            "number": pr.get("number"),
            "created_at": pr.get("created_at"),
            "closed_at": pr.get("closed_at"),
            "tot_s": round(closed - created, 3) if created and closed else None,
            "incident_class": "closed_unmerged",
        })

    # Re-arm verdict ingestion (read-only; structured `^{"rearm":` lines only).
    # Verdicts are bound to their PR via the timeline already fetched above;
    # arm→enqueue latency reuses queue_events()/pr_mg_runs() data, never new
    # GraphQL. Anything unparseable/unresolvable is recorded, never an arm.
    rearm_runs = client.list_runs(None, since, until, workflow=REARM_WORKFLOW)
    rearm_runs.sort(key=lambda r: (r.get("created_at") or "", r.get("id") or 0))
    rearm_runs_in_window = len(rearm_runs)
    rearm_truncated = False
    if rearm_runs_in_window > max_rearm_runs:
        rearm_runs = rearm_runs[-max_rearm_runs:]
        rearm_truncated = True
    rearm_records: List[Dict[str, Any]] = []
    for run in rearm_runs:
        run_id = run.get("id")
        entry: Dict[str, Any] = {
            "run_id": run_id,
            "run_name": run.get("display_title") or run.get("name"),
            "event": run.get("event"),
            "conclusion": run.get("conclusion"),
            "run_attempt": run.get("run_attempt"),
            "run_created_at": run.get("created_at"),
            "run_updated_at": run.get("updated_at"),
        }
        log = client.run_log(int(run_id))
        if not log.get("available"):
            entry.update({"status": "unknown", "unknown_reason": "log_unavailable",
                          "log_reason": log.get("reason")})
            rearm_records.append(entry)
            continue
        verdict_lines = extract_rearm_lines(log.get("text") or "")
        if not verdict_lines:
            entry.update({"status": "unknown", "unknown_reason": "no_rearm_line"})
            rearm_records.append(entry)
            continue
        verdict, err = parse_rearm_verdict(verdict_lines[-1])
        if verdict is None:
            entry.update({"status": "unknown", "unknown_reason": err,
                          "line_snippet": verdict_lines[-1][:200]})
            rearm_records.append(entry)
            continue
        entry.update({"status": "ok", "rearm": {**verdict, "run_id": run_id}})
        rearm_records.append(entry)

    for entry in rearm_records:
        verdict = entry.get("rearm")
        if verdict is None or verdict.get("action") != "arm":
            continue
        arm_ts = None
        basis = None
        try:
            jobs = client.jobs(int(entry["run_id"]), int(entry.get("run_attempt") or 1))
        except GhError:
            jobs = []
        named = [j for j in jobs if (j.get("name") or "") == "rearm"]
        job = named[0] if named else (jobs[0] if len(jobs) == 1 else None)
        if job is not None and iso_to_epoch(job.get("completed_at")) is not None:
            arm_ts = iso_to_epoch(job.get("completed_at"))
            basis = "job_completed_at"
        elif iso_to_epoch(entry.get("run_updated_at")) is not None:
            arm_ts = iso_to_epoch(entry.get("run_updated_at"))
            basis = "run_updated_at"
        verdict["arm_completed_at_epoch"] = arm_ts
        verdict["arm_completed_at"] = epoch_to_iso(arm_ts)
        verdict["arm_completed_at_basis"] = basis

    arm_verdicts = [e["rearm"] for e in rearm_records
                    if e.get("status") == "ok" and e["rearm"].get("action") == "arm"]
    rearm_resolved, rearm_latency_unresolved = resolve_rearm_arms(
        arm_verdicts, queue_events_by_pr, pr_heads_by_pr)
    resolved_by_run = {r["run_id"]: r for r in rearm_resolved}
    unresolved_by_run: Dict[Any, Dict[str, Any]] = {}
    for row in rearm_latency_unresolved:
        unresolved_by_run.setdefault(row.get("run_id"), row)
    for entry in rearm_records:
        verdict = entry.get("rearm")
        if verdict is None or verdict.get("action") != "arm":
            continue
        if entry["run_id"] in resolved_by_run:
            verdict.update(resolved_by_run[entry["run_id"]])
        else:
            verdict["unresolved_reason"] = unresolved_by_run.get(entry["run_id"], {}).get("reason")

    parsed_entries = [e for e in rearm_records if e.get("status") == "ok"]
    rearm_class_counts = {cls: 0 for cls in REARM_CLASSES}
    rearm_action_counts = {act: 0 for act in REARM_ACTIONS}
    rearm_budget_counts: Dict[str, int] = {}
    rearm_reason_counts: Dict[str, int] = {}
    for entry in parsed_entries:
        verdict = entry["rearm"]
        rearm_class_counts[verdict["class"]] += 1
        rearm_action_counts[verdict["action"]] += 1
        budget_key = verdict.get("budget") or "unknown"
        rearm_budget_counts[budget_key] = rearm_budget_counts.get(budget_key, 0) + 1
        reason_key = verdict.get("reason") or "unknown"
        rearm_reason_counts[reason_key] = rearm_reason_counts.get(reason_key, 0) + 1
    rearm_latencies = [r["arm_to_enqueue_s"] for r in rearm_resolved]
    rearm_unresolvable: List[Dict[str, Any]] = []
    for entry in rearm_records:
        if entry.get("status") != "ok":
            rearm_unresolvable.append({
                "run_id": entry.get("run_id"), "pr": None, "head": None,
                "kind": "log" if entry.get("unknown_reason") == "log_unavailable" else "verdict_parse",
                "reason": entry.get("unknown_reason"),
            })
        elif entry["rearm"].get("action") == "arm" and entry["rearm"].get("unresolved_reason"):
            rearm_unresolvable.append({
                "run_id": entry.get("run_id"),
                "pr": entry["rearm"].get("pr"),
                "head": entry["rearm"].get("head"),
                "kind": "latency",
                "reason": entry["rearm"]["unresolved_reason"],
            })
    rearm_by_pr: Dict[int, List[Dict[str, Any]]] = {}
    for entry in parsed_entries:
        rearm_by_pr.setdefault(int(entry["rearm"]["pr"]), []).append(entry)
    for rec in pr_records:
        entries = rearm_by_pr.get(int(rec["number"]))
        if entries:
            rec["rearm"] = {"incidents": entries}
    rearm_ingest = {
        "workflow": REARM_WORKFLOW,
        "max_rearm_runs": max_rearm_runs,
        "runs_in_window": rearm_runs_in_window,
        "runs_processed": len(rearm_records),
        "runs_truncated": rearm_truncated,
        "logs_unavailable": sum(1 for e in rearm_records if e.get("unknown_reason") == "log_unavailable"),
        "verdicts_parsed": len(parsed_entries),
        "counts_by_class": rearm_class_counts,
        "counts_by_action": rearm_action_counts,
        "budget_histogram": dict(sorted(rearm_budget_counts.items(), key=lambda kv: -kv[1])),
        "reason_histogram": dict(sorted(rearm_reason_counts.items(), key=lambda kv: -kv[1])),
        "arms_total": rearm_action_counts["arm"],
        "arms_with_latency": len(rearm_latencies),
        "arm_to_enqueue_s": summarize(rearm_latencies),
        "unresolvable": rearm_unresolvable,
        "incidents": rearm_records,
    }

    # Aggregates
    tot_values = [r["tot_s"] for r in pr_records]
    data_complete_records = [r for r in pr_records if r.get("data_complete")]
    data_complete_tot = [r["tot_s"] for r in data_complete_records]
    partition_stats = {
        label: summarize([r["partition_s"].get(label, 0.0) for r in data_complete_records])
        for label in PARTITION_LABELS
    }
    partition_stats_all = {
        label: summarize([r["partition_s"].get(label, 0.0) for r in pr_records])
        for label in PARTITION_LABELS
    }
    overlay_stats = {
        key: summarize([r["overlays_s"].get(key) for r in data_complete_records])
        for key in ("review_wait", "ci_coverage_union", "incident_overlay", "author_after_ci")
    }
    incident_counts: Dict[str, int] = {}
    for rec in pr_records:
        for cls in rec["incident"].get("all_classes", []):
            incident_counts[cls] = incident_counts.get(cls, 0) + 1
    dc_total_sum = sum(data_complete_tot) or 0.0
    incident_contribution: Dict[str, Any] = {}
    for cls in INCIDENT_CLASSES:
        recs = [r for r in data_complete_records if cls in r["incident"].get("all_classes", [])]
        if not recs:
            continue
        vals = [r["tot_s"] for r in recs]
        incident_contribution[cls] = {
            **summarize(vals),
            "share_of_data_complete_tot_pct": round(sum(vals) / dc_total_sum * 100.0, 2) if dc_total_sum else None,
            "prs": [r["number"] for r in recs],
        }

    identity_ok = all(r["partition_identity"]["ok"] for r in pr_records) if pr_records else False
    max_delta = max((abs(r["partition_identity"]["delta_s"]) for r in pr_records), default=None)

    # SLO-MG job ranking (cohort MG runs only; bounded API calls)
    cohort_mg_ids = {rid for rec in pr_records for rid in rec["runs"]["merge_group"]}
    cohort_mg_runs = [run for run in runs_mg if run.get("id") in cohort_mg_ids]
    job_totals: Dict[str, Dict[str, float]] = {}
    mg_walls = []
    mg_attempt_walls = []
    mg_total_elapsed = []
    for run in cohort_mg_runs:
        name = run.get("name") or ""
        if "admission" not in name:
            continue
        wall = run_interval(run)
        if wall:
            mg_walls.append(wall[1] - wall[0])
        attempt_no = int(run.get("run_attempt") or 1)
        jobs = client.jobs(int(run["id"]), attempt_no)
        attempt_union = union_duration(
            (iso_to_epoch(j.get("started_at")), iso_to_epoch(j.get("completed_at")))
            for j in jobs
            if j.get("started_at") and j.get("completed_at")
        )
        mg_attempt_walls.append(attempt_union)
        first = client.attempt(int(run["id"]), 1)
        first_start = iso_to_epoch(first.get("created_at")) or iso_to_epoch(first.get("run_started_at"))
        last = client.attempt(int(run["id"]), attempt_no)
        last_end = iso_to_epoch(last.get("updated_at"))
        if first_start and last_end:
            mg_total_elapsed.append(last_end - first_start)
        for job in jobs:
            jname = job.get("name") or "unknown"
            s, e = iso_to_epoch(job.get("started_at")), iso_to_epoch(job.get("completed_at"))
            bucket = job_totals.setdefault(jname, {"sum_s": 0.0, "count": 0, "durations": []})
            if s and e and e > s:
                bucket["sum_s"] += e - s
                bucket["count"] += 1
                bucket["durations"].append(e - s)
    job_ranking = sorted(
        (
            {
                "job": k,
                "sum_s": round(v["sum_s"], 3),
                "count": v["count"],
                "mean_s": round(v["sum_s"] / v["count"], 3) if v["count"] else None,
                "p50_s": round(r7(v["durations"], 0.50), 3) if v["durations"] else None,
                "p95_s": round(r7(v["durations"], 0.95), 3) if v["durations"] else None,
            }
            for k, v in job_totals.items()
        ),
        key=lambda x: -x["sum_s"],
    )[:12]

    # Counterfactual: cap each partition label at its cohort p50
    counterfactual = []
    base_p95 = r7(data_complete_tot, 0.95)
    for label in PARTITION_LABELS:
        cap = partition_stats[label]["p50"]
        if cap is None:
            continue
        adjusted = []
        for rec in data_complete_records:
            dur = rec["partition_s"].get(label, 0.0)
            adjusted.append(rec["tot_s"] - max(0.0, dur - cap))
        new_p95 = r7(adjusted, 0.95)
        counterfactual.append({
            "segment": label,
            "cap_s": cap,
            "p95_before_s": None if base_p95 is None else round(base_p95, 3),
            "p95_after_s": None if new_p95 is None else round(new_p95, 3),
            "p95_delta_s": None if (base_p95 is None or new_p95 is None) else round(new_p95 - base_p95, 3),
        })
    counterfactual.sort(key=lambda x: (x["p95_delta_s"] if x["p95_delta_s"] is not None else 0.0))

    # Incident-excluded diagnostic (data-complete cohort only)
    normal = [r for r in data_complete_records if r["incident"].get("primary") == "merged_normal"]

    # Top 5% slowest (data-complete primary; full cohort retained for audit)
    top_n = max(1, int(math.ceil(len(data_complete_records) * 0.05))) if data_complete_records else 0
    top = sorted(data_complete_records, key=lambda r: -r["tot_s"])[:top_n]
    top_all = sorted(pr_records, key=lambda r: -r["tot_s"])[:top_n]

    # Judgments
    mg_stats = summarize(mg_walls)
    top_segment = max(
        (label for label in PARTITION_LABELS if partition_stats[label]["p95"] is not None),
        key=lambda label: partition_stats[label]["p95"],
        default=None,
    )
    selected_cf = counterfactual[0] if counterfactual else None
    slo_mg = {
        "target_s": SLO_MG_TARGET_S,
        "latest_attempt_wall": mg_stats,
        "attempt_wall": summarize(mg_attempt_walls),
        "total_elapsed_with_retries": summarize(mg_total_elapsed),
        "target_met_at_p50": (mg_stats["p50"] is not None and mg_stats["p50"] <= SLO_MG_TARGET_S),
        "target_met_at_p95": (mg_stats["p95"] is not None and mg_stats["p95"] <= SLO_MG_TARGET_S),
        "job_ranking": job_ranking,
        "selected_lever": ("recurring MG job: %s" % job_ranking[0]["job"]) if job_ranking else "unknown",
        "status": "recurring_cost_dominant" if (mg_stats["p50"] or 0) > SLO_MG_TARGET_S else "target_met_or_unmeasured",
    }
    slo_pr = {
        "basis": "data_complete_cohort",
        "tot": summarize(tot_values),
        "tot_data_complete": summarize(data_complete_tot),
        "normal_path_tot": summarize([r["tot_s"] for r in normal]),
        "top_segment_by_p95": top_segment,
        "top_segment_p95_s": partition_stats.get(top_segment, {}).get("p95") if top_segment else None,
        "counterfactual_best": selected_cf,
        "status": "p95_dominated_by_" + (selected_cf["segment"] if selected_cf else "unknown"),
    }
    exec_reasons = []
    if selected_cf:
        seg = selected_cf["segment"]
        if seg == "mg_ci":
            exec_reasons = ["runner/hardware or lane-topology change", "may require policy/budget approval", "workflow change triggers CI epoch cutover"]
            status = "requires_policy_or_budget"
        elif seg in ("queue_wait", "between_cycle_gap", "merge_tail"):
            exec_reasons = ["queue/incident robustness workstream", "no workflow trust-surface change required for observation"]
            status = "executable"
        elif seg in ("pr_head_ci",):
            exec_reasons = ["PR-head CI cost reduction", "workflow change triggers CI epoch cutover"]
            status = "requires_policy"
        elif seg in ("pre_ci", "pr_head_idle", "pre_enqueue_gap"):
            exec_reasons = ["author/automation idle time", "human workflow policy decision"]
            status = "requires_policy"
        else:
            status = "unknown"
    else:
        status = "unknown"
    judgments = {
        "slo_mg": slo_mg,
        "slo_pr": slo_pr,
        "operational_executability": {
            "status": status,
            "reasons": exec_reasons,
            "authority": ["GitHub (merge authority)", "human architect (policy/budget)", "repo maintainers (workflow changes)"],
            "tool_is_reporter_only": True,
        },
    }

    billing = {}
    for year, month in sorted({(datetime.fromtimestamp(until, tz=timezone.utc).year,
                                 datetime.fromtimestamp(until, tz=timezone.utc).month)}):
        usage = client.billing_usage(year, month)
        items = usage.get("usageItems", []) if isinstance(usage, dict) else []
        by_sku = {}
        for item in items:
            if item.get("repositoryName") != client.name:
                continue
            sku = item.get("sku") or "unknown"
            bucket = by_sku.setdefault(sku, {
                "quantity": 0.0,
                "unitType": item.get("unitType"),
                "gross_usd": 0.0,
                "discount_usd": 0.0,
                "net_usd": 0.0,
            })
            bucket["quantity"] += float(item.get("quantity") or 0.0)
            bucket["gross_usd"] += float(item.get("grossAmount") or 0.0)
            bucket["discount_usd"] += float(item.get("discountAmount") or 0.0)
            bucket["net_usd"] += float(item.get("netAmount") or 0.0)
        billing["%d-%02d" % (year, month)] = {
            "available": isinstance(usage, dict) and "usageItems" in usage,
            "by_sku": by_sku,
        }
    cost_basis = "estimate" if any(r["cost"]["basis"] == "estimate" for r in pr_records) else "unknown"
    cost = {
        "cost_basis": cost_basis,
        "billing_basis": "org_billing_usage_aggregate",
        "billing_usage": billing,
        "actual_billed_cost": {
            "per_pr": "unknown",
            "reason": "GitHub billing usage API exposes only repo x SKU x day aggregates; no per-run/per-PR billed cost.",
        },
        "shared_ci_runs": sorted(shared_runs.values(), key=lambda r: -r["run_id"]),
        "pr_estimates": [
            {"number": r["number"], **r["cost"]} for r in pr_records
        ],
        "allocation_rule": "equal split among known merge-group members; UNKNOWN never recorded as 0",
    }

    caveats = [
        "TOT is created_at -> merged_at; it includes author/pre-CI time by definition.",
        "TOT(commit-date) uses the last commit committer date and is an ESTIMATE, not push time.",
        "TOT(push) is unavailable for arbitrary merged PRs: the events feed is limited to 300 events / 30 days and GraphQL has no ordinary-push timeline item.",
        "review_wait is advisory under the 0-approval ruleset and is never summed into TOT.",
        "diagnostic_overlays may overlap wall_partition and are not additive.",
        "Queue internal state durations are not preserved by GitHub; only bounds are reported.",
        "Dequeue reason is an opaque GraphQL string; REST timeline omits it.",
        "Cost is an estimate or UNKNOWN; no per-PR billed cost exists.",
        "PRs with no CI/queue events are data_complete=false and recorded as unknown/unattributed; full-cohort TOT includes them, data-complete TOT is the lever-selection basis.",
        "Actions runs/checks/statuses retention defaults to 90 days from 2026-10-01; older data may be unavailable.",
        "Re-arm verdicts come only from structured %s job-log lines (`^\\{\"rearm\":`), capped at the newest --max-rearm-runs runs; logs expired under Actions retention are recorded unknowns, and absent/unparseable verdicts are never reported as arm." % REARM_WORKFLOW,
    ]

    return {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo": client.repo,
        "window": {
            "since": epoch_to_iso(since),
            "until": epoch_to_iso(until),
            "max_prs": max_prs,
            "sample": sample,
        },
        "cohort": {
            "closed_total": cohort["collected"],
            "merged": len(pr_records),
            "closed_unmerged": len(unmerged_records),
            "data_complete": len(data_complete_records),
            "data_incomplete": len(pr_records) - len(data_complete_records),
            "run_history_start": epoch_to_iso(history_start),
            "run_history_end": epoch_to_iso(history_end),
            "cohort_complete": cohort["cohort_complete"],
            "partial_reason": cohort["partial_reason"],
            "sample_sufficient": len(data_complete_records) >= 60,
        },
        "metrics": {
            "tot": summarize(tot_values),
            "tot_data_complete": summarize(data_complete_tot),
            "tot_commit_date": summarize([r["tot_commit_date_s"] for r in pr_records]),
            "tot_ready": summarize([r["tot_ready_s"] for r in pr_records]),
            "tot_push": {
                "available": False,
                "reason": "events feed limited to 300 events / 30 days; GraphQL has no ordinary-push timeline item; Commit.pushedDate is null",
            },
            "slo_mg": {
                "latest_attempt_wall": slo_mg["latest_attempt_wall"],
                "attempt_wall": slo_mg["attempt_wall"],
                "total_elapsed_with_retries": slo_mg["total_elapsed_with_retries"],
            },
            "slo_pr": {
                "p50": summarize(tot_values)["p50"],
                "p95": summarize(tot_values)["p95"],
                "data_complete_p50": summarize(data_complete_tot)["p50"],
                "data_complete_p95": summarize(data_complete_tot)["p95"],
                "target": None,
            },
        },
        "wall_partition": {
            "labels": PARTITION_LABELS,
            "stats": partition_stats,
            "stats_all": partition_stats_all,
            "basis": "data_complete cohort for primary stats; stats_all includes data-incomplete PRs",
            "identity": {
                "all_ok": identity_ok,
                "max_abs_delta_s": max_delta,
                "tolerance_s": 2.0,
            },
        },
        "diagnostic_overlays": {
            "note": "may overlap; never summed into TOT",
            "stats": overlay_stats,
        },
        "incidents": {
            "counts": incident_counts,
            "contribution": incident_contribution,
            "census": [
                {"number": r["number"], "primary": r["incident"].get("primary"),
                 "all_classes": r["incident"].get("all_classes"), "intervals": r["incident"].get("intervals"),
                 "evidence": r["incident"].get("evidence")}
                for r in pr_records
            ],
            "closed_unmerged": unmerged_records,
        },
        "top_p95_contributors": top,
        "top_p95_contributors_all": top_all,
        "counterfactual": counterfactual,
        "cost": cost,
        "judgments": judgments,
        "unknowns": unknowns,
        "caveats": caveats,
        "prs": pr_records,
        "rearm_ingest": rearm_ingest,
    }


# ---------------------------------------------------------------------------
# Markdown report
# ---------------------------------------------------------------------------

def fmt_s(value: Optional[float]) -> str:
    if value is None:
        return "UNKNOWN"
    return "%.1fs (%.1fm)" % (value, value / 60.0)


def render_markdown(result: Dict[str, Any]) -> str:
    cohort = result["cohort"]
    metrics = result["metrics"]
    judgments = result["judgments"]
    lines: List[str] = []
    lines.append("# PR-to-main Latency Attribution — %s" % result["generatedAt"].split("T")[0])
    lines.append("")
    lines.append("> **권위**: Reporter only. GitHub merge authority(ruleset·required checks·merge queue·MERGE)를 대체하지 않는다. "
                 "이 보고서는 admission 판정 입력이 아니며 어떤 gate도 소비하지 않는다.")
    lines.append("> **계약**: `docs/evidence/pr_to_main_attribution_prereg_2026-10-19.md` (measurement contract v2).")
    lines.append("")
    lines.append("## 1. Cohort")
    lines.append("")
    lines.append("| 항목 | 값 |")
    lines.append("|---|---|")
    lines.append("| repo | `%s` |" % result["repo"])
    lines.append("| window | %s → %s |" % (result["window"]["since"], result["window"]["until"]))
    lines.append("| closed PRs collected | %d |" % cohort["closed_total"])
    lines.append("| merged (primary) | %d |" % cohort["merged"])
    lines.append("| data-complete (CI/queue evidence) | %d |" % cohort["data_complete"])
    lines.append("| data-incomplete (UNKNOWN attribution) | %d |" % cohort["data_incomplete"])
    lines.append("| closed-unmerged (census) | %d |" % cohort["closed_unmerged"])
    lines.append("| cohort_complete | %s |" % str(cohort["cohort_complete"]).lower())
    lines.append("| sample_sufficient (n>=60) | %s |" % str(cohort["sample_sufficient"]).lower())
    lines.append("")
    if not cohort["cohort_complete"]:
        lines.append("**WARNING**: cohort incomplete (`%s`). p95-based lever selection is limited." % cohort["partial_reason"])
        lines.append("")

    lines.append("## 2. Metrics")
    lines.append("")
    lines.append("| metric | p50 | p95 | n |")
    lines.append("|---|---:|---:|---:|")
    for key, label in (("tot", "TOT full cohort"), ("tot_data_complete", "TOT data-complete cohort"),
                       ("tot_commit_date", "TOT(commit-date, ESTIMATE)"),
                       ("tot_ready", "TOT(ready→merged)")):
        stats = metrics[key]
        lines.append("| %s | %s | %s | %d |" % (label, fmt_s(stats["p50"]), fmt_s(stats["p95"]), stats["n"]))
    lines.append("| SLO-MG latest-attempt wall | %s | %s | %d |" % (
        fmt_s(metrics["slo_mg"]["latest_attempt_wall"]["p50"]),
        fmt_s(metrics["slo_mg"]["latest_attempt_wall"]["p95"]),
        metrics["slo_mg"]["latest_attempt_wall"]["n"]))
    lines.append("")
    lines.append("Full-cohort TOT includes data-incomplete PRs (no CI/queue events); lever selection uses the data-complete cohort.")
    lines.append("")
    lines.append("`TOT(push)` is unavailable: `%s`." % metrics["tot_push"]["reason"])
    lines.append("")

    lines.append("## 3. Wall partition (data-complete cohort; non-overlapping; sum == TOT)")
    lines.append("")
    lines.append("| segment | p50 | p95 | total | share of data-complete TOT p50 |")
    lines.append("|---|---:|---:|---:|---:|")
    tot_p50 = metrics["tot_data_complete"]["p50"] or 0.0
    for label in result["wall_partition"]["labels"]:
        stats = result["wall_partition"]["stats"][label]
        share = (stats["p50"] / tot_p50 * 100.0) if (tot_p50 and stats["p50"] is not None) else 0.0
        lines.append("| `%s` | %s | %s | %s | %.1f%% |" % (
            label, fmt_s(stats["p50"]), fmt_s(stats["p95"]), fmt_s(stats["mean"]), share))
    identity = result["wall_partition"]["identity"]
    lines.append("")
    lines.append("Identity: all_ok=`%s`, max |delta| = %s, tolerance = %.1fs." % (
        str(identity["all_ok"]).lower(),
        "UNKNOWN" if identity["max_abs_delta_s"] is None else "%.3fs" % identity["max_abs_delta_s"],
        identity["tolerance_s"]))
    lines.append("")

    lines.append("## 4. Diagnostic overlays (may overlap; never summed)")
    lines.append("")
    lines.append("| overlay | p50 | p95 | total |")
    lines.append("|---|---:|---:|---:|")
    for key, stats in result["diagnostic_overlays"]["stats"].items():
        lines.append("| `%s` | %s | %s | %s |" % (
            key, fmt_s(stats["p50"]), fmt_s(stats["p95"]), fmt_s(stats["mean"])))
    lines.append("")
    review_advisory = all(r["overlays_s"].get("review_advisory") for r in result["prs"]) if result["prs"] else True
    lines.append("`review_wait` is advisory=%s under the 0-approval ruleset; it is not a blocking segment."
                 % str(review_advisory).lower())
    lines.append("")

    lines.append("## 5. Incidents")
    lines.append("")
    lines.append("| class | count | TOT sum | p50 | p95 | share of data-complete TOT |")
    lines.append("|---|---:|---:|---:|---:|---:|")
    for cls, count in sorted(result["incidents"]["counts"].items(), key=lambda kv: -kv[1]):
        c = result["incidents"].get("contribution", {}).get(cls, {})
        share = c.get("share_of_data_complete_tot_pct")
        lines.append("| `%s` | %d | %s | %s | %s | %s |" % (
            cls, count, fmt_s(c.get("mean")), fmt_s(c.get("p50")), fmt_s(c.get("p95")),
            "UNKNOWN" if share is None else "%.1f%%" % share))
    lines.append("")
    lines.append("`mean` is the per-incident mean TOT; the share column is the sum of affected data-complete PR TOT over the cohort TOT.")
    lines.append("")

    lines.append("## 6. Top p95 contributors")
    lines.append("")
    lines.append("| PR | TOT | primary incident | pre_ci | pr_head_ci | queue_wait | mg_ci | merge_tail |")
    lines.append("|---:|---:|---|---:|---:|---:|---:|---:|")
    for rec in result["top_p95_contributors"]:
        p = rec["partition_s"]
        lines.append("| #%s | %s | `%s` | %s | %s | %s | %s | %s |" % (
            rec["number"], fmt_s(rec["tot_s"]), rec["incident"].get("primary"),
            fmt_s(p.get("pre_ci")), fmt_s(p.get("pr_head_ci")), fmt_s(p.get("queue_wait")),
            fmt_s(p.get("mg_ci")), fmt_s(p.get("merge_tail"))))
    lines.append("")

    lines.append("## 7. Counterfactual (cap each segment at cohort p50)")
    lines.append("")
    lines.append("| segment | cap | p95 before | p95 after | delta |")
    lines.append("|---|---:|---:|---:|---:|")
    for row in result["counterfactual"]:
        lines.append("| `%s` | %s | %s | %s | %s |" % (
            row["segment"], fmt_s(row["cap_s"]), fmt_s(row["p95_before_s"]),
            fmt_s(row["p95_after_s"]), fmt_s(row["p95_delta_s"])))
    lines.append("")
    lines.append("Counterfactual is a sensitivity analysis, not a causal claim.")
    lines.append("")

    lines.append("## 8. Cost")
    lines.append("")
    lines.append("`actual_billed_cost.per_pr = UNKNOWN` — %s" % result["cost"]["actual_billed_cost"]["reason"])
    lines.append("")
    lines.append("| shared merge_group run | members | job minutes | estimate USD | basis |")
    lines.append("|---|---|---:|---:|---|")
    for run in result["cost"]["shared_ci_runs"][:20]:
        lines.append("| %s | %s | %.1f | %s | %s |" % (
            run["run_id"], ",".join(str(m) for m in run["group_members"]),
            run["job_minutes"], run["estimate_usd"], run["basis"]))
    lines.append("")

    lines.append("## 9. Judgments (independent)")
    lines.append("")
    sm = judgments["slo_mg"]
    sp = judgments["slo_pr"]
    oe = judgments["operational_executability"]
    lines.append("### 9.1 SLO-MG — recurring merge-group verification cost")
    lines.append("")
    lines.append("- target p95: %.0fs; latest-attempt p50/p95: %s / %s" % (
        sm["target_s"], fmt_s(sm["latest_attempt_wall"]["p50"]), fmt_s(sm["latest_attempt_wall"]["p95"])))
    lines.append("- status: `%s`; selected lever: %s" % (sm["status"], sm["selected_lever"]))
    lines.append("")
    lines.append("| job | sum | n | mean | p50 | p95 |")
    lines.append("|---|---:|---:|---:|---:|---:|")
    for j in sm["job_ranking"][:8]:
        lines.append("| `%s` | %.0fs | %d | %s | %s | %s |" % (
            j["job"], j["sum_s"], j["count"], fmt_s(j.get("mean_s")),
            fmt_s(j.get("p50_s")), fmt_s(j.get("p95_s"))))
    lines.append("")
    lines.append("### 9.2 SLO-PR — data-complete TOT p95 contributor")
    lines.append("")
    lines.append("- TOT full cohort p50/p95: %s / %s" % (fmt_s(sp["tot"]["p50"]), fmt_s(sp["tot"]["p95"])))
    lines.append("- TOT data-complete p50/p95: %s / %s" % (
        fmt_s(sp["tot_data_complete"]["p50"]), fmt_s(sp["tot_data_complete"]["p95"])))
    lines.append("- normal-path TOT p50/p95: %s / %s" % (
        fmt_s(sp["normal_path_tot"]["p50"]), fmt_s(sp["normal_path_tot"]["p95"])))
    lines.append("- top segment by p95: `%s` (%s)" % (sp["top_segment_by_p95"], fmt_s(sp["top_segment_p95_s"])))
    if sp["counterfactual_best"]:
        cf = sp["counterfactual_best"]
        lines.append("- best counterfactual: cap `%s` at %s → p95 delta %s" % (
            cf["segment"], fmt_s(cf["cap_s"]), fmt_s(cf["p95_delta_s"])))
    lines.append("")
    lines.append("### 9.3 Operational executability")
    lines.append("")
    lines.append("- status: `%s`" % oe["status"])
    for reason in oe["reasons"]:
        lines.append("- %s" % reason)
    lines.append("")

    lines.append("## 10. UNKNOWN / caveats")
    lines.append("")
    for item in result["caveats"]:
        lines.append("- %s" % item)
    if result["unknowns"]:
        lines.append("")
        lines.append("| PR | stage | reason |")
        lines.append("|---:|---|---|")
        for item in result["unknowns"]:
            lines.append("| #%s | %s | %s |" % (item.get("pr"), item.get("stage"), item.get("reason")))
    lines.append("")

    rearm = result["rearm_ingest"]
    rearm_cls = rearm["counts_by_class"]
    rearm_act = rearm["counts_by_action"]
    lines.append("## 11. Re-arm verdicts (`%s`)" % rearm["workflow"])
    lines.append("")
    lines.append("> 구조화된 잡 로그 라인(`^\\{\"rearm\":`)만 파싱한다. 로그 부재·파싱 실패·바인딩 실패 판정은 절대 `arm`으로 보고하지 않는다 (fail-closed).")
    lines.append("")
    lines.append("| 항목 | 값 |")
    lines.append("|---|---|")
    lines.append("| runs in window | %d (processed %d, cap %d%s) |" % (
        rearm["runs_in_window"], rearm["runs_processed"], rearm["max_rearm_runs"],
        ", truncated to newest" if rearm["runs_truncated"] else ""))
    lines.append("| logs unavailable | %d |" % rearm["logs_unavailable"])
    lines.append("| verdicts parsed | %d |" % rearm["verdicts_parsed"])
    lines.append("| class TRANSIENT / PERMANENT / UNKNOWN | %d / %d / %d |" % (
        rearm_cls["TRANSIENT"], rearm_cls["PERMANENT"], rearm_cls["UNKNOWN"]))
    lines.append("| action arm / no-arm | %d / %d |" % (rearm_act["arm"], rearm_act["no-arm"]))
    lines.append("| arms with resolvable enqueue latency | %d / %d |" % (
        rearm["arms_with_latency"], rearm["arms_total"]))
    lines.append("| arm→enqueue p50 / p95 | %s / %s (n=%d) |" % (
        fmt_s(rearm["arm_to_enqueue_s"]["p50"]), fmt_s(rearm["arm_to_enqueue_s"]["p95"]),
        rearm["arm_to_enqueue_s"]["n"]))
    lines.append("")
    top_reasons = list(rearm["reason_histogram"].items())[:8]
    if top_reasons:
        lines.append("Reason histogram (top %d):" % len(top_reasons))
        lines.append("")
        lines.append("| reason | count |")
        lines.append("|---|---:|")
        for reason, count in top_reasons:
            lines.append("| %s | %d |" % (str(reason).replace("|", "\\|")[:160], count))
        lines.append("")
    if rearm["unresolvable"]:
        lines.append("| run | PR | kind | reason |")
        lines.append("|---:|---:|---|---|")
        for row in rearm["unresolvable"][:20]:
            lines.append("| %s | %s | %s | %s |" % (
                row.get("run_id"), row.get("pr"), row.get("kind"),
                str(row.get("reason")).replace("|", "\\|")[:120]))
        if len(rearm["unresolvable"]) > 20:
            lines.append("")
            lines.append("(%d more unresolvable verdicts omitted)" % (len(rearm["unresolvable"]) - 20))
        lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

def _assert(cond: bool, msg: str, failures: List[str]) -> None:
    if not cond:
        failures.append(msg)


def self_test() -> int:
    failures: List[str] = []
    base = 1_700_000_000.0

    # 1. Author gap
    segs = build_partition(base, base + 1830, [(base + 600, base + 900)], {0: [(base + 1200, base + 1800)]}, [base + 1200])
    t = total_seconds(segs)
    _assert(t["pre_ci"] == 600, "author gap: pre_ci", failures)
    _assert(t["pr_head_ci"] == 300, "author gap: pr_head_ci", failures)
    _assert(t["pre_enqueue_gap"] == 300, "author gap: pre_enqueue_gap", failures)
    _assert(t["mg_ci"] == 600, "author gap: mg_ci", failures)
    _assert(t["merge_tail"] == 30, "author gap: merge_tail", failures)
    _assert(abs(sum(t.values()) - 1830) < 1e-6, "author gap: identity", failures)

    # 2. Failed_checks dequeue -> re-enqueue
    segs = build_partition(
        base, base + 310,
        [],
        {0: [(base, base + 100)], 1: [(base + 200, base + 300)]},
        [base, base + 200],
    )
    t = total_seconds(segs)
    _assert(t["mg_ci"] == 200, "dequeue: mg_ci", failures)
    _assert(t["between_cycle_gap"] == 100, "dequeue: between_cycle_gap", failures)
    _assert(t["merge_tail"] == 10, "dequeue: merge_tail", failures)
    _assert(abs(sum(t.values()) - 310) < 1e-6, "dequeue: identity", failures)

    # 3. Review/CI overlap: overlays are not summed
    segs = build_partition(base, base + 1000, [(base + 100, base + 500)], {}, [])
    t = total_seconds(segs)
    _assert(t["pr_head_ci"] == 400, "overlap: pr_head_ci", failures)
    _assert(abs(sum(t.values()) - 1000) < 1e-6, "overlap: identity", failures)
    _assert("review_wait" not in t, "overlap: overlay must not be a partition label", failures)
    _assert(sum(t.values()) == 1000, "overlap: overlay must not be added to partition", failures)

    # 4. Red retry classification
    pr = {"number": 1, "closedAt": None}
    events = {"adds": [], "removals": [], "ready": None, "review_requested": None, "base_changes": [], "force_pushes": []}
    mg = [{"id": 7, "run_attempt": 2, "created_at": epoch_to_iso(base), "updated_at": epoch_to_iso(base + 100),
           "run_started_at": epoch_to_iso(base), "conclusion": "success"}]
    inc = classify_incidents(pr, events, [("mg_ci", base, base + 100)], mg, base + 100, base, [])
    _assert("red_retry" in inc["all_classes"], "red retry: class", failures)

    # 5. Force-push head union (two SHAs)
    run_a = {"id": 1, "event": "pull_request", "head_sha": "a", "created_at": epoch_to_iso(base),
             "run_started_at": epoch_to_iso(base), "updated_at": epoch_to_iso(base + 100)}
    run_b = {"id": 2, "event": "pull_request", "head_sha": "b", "created_at": epoch_to_iso(base + 200),
             "run_started_at": epoch_to_iso(base + 200), "updated_at": epoch_to_iso(base + 300)}
    idx = index_runs([run_a, run_b])
    pr = {"number": 1, "commits": {"nodes": [{"commit": {"oid": "a"}}, {"commit": {"oid": "b"}}]}}
    got = pr_head_runs(pr, idx, base, base + 400)
    _assert(len(got) == 2, "force push: both runs", failures)

    # 6. Multi-PR group cost: shared run recorded once, equal split
    members = parse_group_members("gh-readonly-queue/main/pr-11-abc")
    _assert(members == [11], "group parse single", failures)
    members = parse_group_members("gh-readonly-queue/main/pr-11-abc-pr-12-def")
    _assert(members == [11, 12], "group parse multi", failures)

    # 7. Percentile R-7
    _assert(abs(r7([1, 2, 3, 4, 5], 0.5) - 3.0) < 1e-9, "r7 p50", failures)
    _assert(abs(r7([1, 2, 3, 4, 5], 0.95) - 4.8) < 1e-9, "r7 p95", failures)

    # 8. Missing timestamps -> unattributed, never dropped
    segs = build_partition(base, base + 10, [], {}, [])
    t = total_seconds(segs)
    _assert(abs(sum(t.values()) - 10) < 1e-6, "missing: identity", failures)

    # 9. Re-arm verdict extraction + parsing (valid TRANSIENT/arm line)
    rearm_line = ('{"rearm":{"pr":1084,"head":"29777700c923","class":"TRANSIENT",'
                  '"reason":"transient runner failure","budget":"available","action":"arm",'
                  '"evidence":{"job":"rearm","step":"arm","line":"armed"}}}')
    log_text = (
        "rearm\tSet up job\t\ufeff2026-10-24T12:37:55.1497622Z Current runner version: '2.338.0'\n"
        "rearm\tcontext\t2026-10-24T12:37:54.0000000Z [rearm] context OK prose\n"
        "rearm\tarm\t2026-10-24T12:38:04.1000000Z " + rearm_line + "\n"
    )
    got_lines = extract_rearm_lines(log_text)
    _assert(got_lines == [rearm_line], "rearm: extract from gh --log format", failures)
    verdict, err = parse_rearm_verdict(got_lines[-1])
    _assert(err is None and verdict is not None, "rearm: valid line parses", failures)
    _assert(verdict is not None and verdict["class"] == "TRANSIENT" and verdict["action"] == "arm"
            and verdict["pr"] == 1084 and verdict["head"] == "29777700c923",
            "rearm: valid line fields", failures)

    # 10. Malformed/out-of-enum verdict lines yield unknown, never arm
    for bad_line, expected_reason in (
        ('{"rearm":{"pr":1084,"head":"29777700c923","class":"TRANSIENT"', "malformed_json"),
        ('{"rearm":{"pr":1084,"head":"29777700c923","class":"TRANSIENT","action":"ARM","reason":"x"}}', "invalid_action"),
        ('{"rearm":{"pr":"abc","head":"29777700c923","class":"TRANSIENT","action":"arm","reason":"x"}}', "invalid_pr"),
        ('{"rearm":"shape"}', "missing_rearm_object"),
    ):
        bad_verdict, bad_err = parse_rearm_verdict(bad_line)
        _assert(bad_verdict is None and bad_err == expected_reason,
                "rearm: malformed line -> unknown (%s)" % bad_err, failures)

    # 11. no-arm verdicts never produce latency samples; arm binding is head-checked
    events_11 = {"adds": [base + 600.0]}
    heads_11 = ["29777700c923ffff"]
    no_arm = {"run_id": 1, "pr": 10, "head": "29777700c923", "class": "TRANSIENT",
              "action": "no-arm", "arm_completed_at_epoch": base + 300.0}
    arm_ok = {"run_id": 2, "pr": 10, "head": "29777700c923", "class": "TRANSIENT",
              "action": "arm", "arm_completed_at_epoch": base + 300.0}
    resolved, unresolved = resolve_rearm_arms([no_arm], {10: events_11}, {10: heads_11})
    _assert(resolved == [] and unresolved == [], "rearm: no-arm never yields latency", failures)
    resolved, unresolved = resolve_rearm_arms([arm_ok], {10: events_11}, {10: heads_11})
    _assert(len(resolved) == 1 and resolved[0]["arm_to_enqueue_s"] == 300.0,
            "rearm: arm latency resolves", failures)
    resolved, unresolved = resolve_rearm_arms(
        [dict(arm_ok, head="000000000000")], {10: events_11}, {10: heads_11})
    _assert(resolved == [] and len(unresolved) == 1
            and unresolved[0]["reason"] == "verdict_head_not_a_pr_head",
            "rearm: head mismatch unresolvable", failures)

    if failures:
        print("SELF-TEST FAIL")
        for f in failures:
            print("  - " + f)
        return 1
    print("SELF-TEST PASS (11/11)")
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="PR-to-main latency attribution (read-only Reporter).")
    parser.add_argument("--repo", default="Archright/Axiom")
    parser.add_argument("--since", help="ISO8601 window start (inclusive)")
    parser.add_argument("--until", help="ISO8601 window end (inclusive)")
    parser.add_argument("--max-prs", type=int, default=5000)
    parser.add_argument("--max-rearm-runs", type=int, default=200,
                        help="cap on merge-queue-rearm.yml runs ingested (newest kept)")
    parser.add_argument("--sample", type=int, default=None, help="smoke: limit merged PRs")
    parser.add_argument("--json-out")
    parser.add_argument("--md-out")
    parser.add_argument("--jsonl-out")
    parser.add_argument("--cache-dir")
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()

    if not args.since or not args.until:
        parser.error("--since and --until are required unless --self-test")
    since = iso_to_epoch(args.since)
    until = iso_to_epoch(args.until)
    if since is None or until is None or until <= since:
        parser.error("invalid --since/--until")

    client = GhClient(args.repo, cache_dir=args.cache_dir, verbose=args.verbose)
    result = analyze(client, since, until, args.max_prs, sample=args.sample, verbose=args.verbose,
                     max_rearm_runs=args.max_rearm_runs)

    if args.json_out:
        os.makedirs(os.path.dirname(os.path.abspath(args.json_out)) or ".", exist_ok=True)
        with open(args.json_out, "w", encoding="utf-8") as fh:
            json.dump(result, fh, ensure_ascii=False, indent=2, sort_keys=False)
            fh.write("\n")
        print("wrote %s" % args.json_out, file=sys.stderr)
    if args.md_out:
        os.makedirs(os.path.dirname(os.path.abspath(args.md_out)) or ".", exist_ok=True)
        with open(args.md_out, "w", encoding="utf-8") as fh:
            fh.write(render_markdown(result))
        print("wrote %s" % args.md_out, file=sys.stderr)
    if args.jsonl_out:
        os.makedirs(os.path.dirname(os.path.abspath(args.jsonl_out)) or ".", exist_ok=True)
        with open(args.jsonl_out, "w", encoding="utf-8") as fh:
            for rec in result["prs"]:
                fh.write(json.dumps(rec, ensure_ascii=False, sort_keys=True) + "\n")
        print("wrote %s" % args.jsonl_out, file=sys.stderr)
    if not (args.json_out or args.md_out or args.jsonl_out):
        json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
