#!/usr/bin/env python3
"""closure-watcher schedule slot ledger — expected vs observed cron-slot accounting.

Contracts (documented in .github/workflows/closure-watcher.yml header):
  - slot       = nominal UTC firing time of the cron grid
  - on-time    = observed run started <= slot + ON_TIME_MINUTES (default 60)
  - late       = observed run started later than that (GitHub defines NO latency SLA;
                 this tolerance is OUR contract)
  - missed     = no observed run attributed to the slot and now > slot + MISSED_CUTOFF_HOURS
                 (a dropped schedule leaves NO run record — absence is the only evidence;
                 cutoff = one cron period covers the largest observed delay, 5.5h)
  - pending    = slot whose missed-cutoff window is still open (honest non-claim)
  - cancelled  = observed runs with conclusion=cancelled (concurrency pending replacement;
                 NOT drift evidence)
  - hollow     = run concluded success while its detect-class job did not conclude
                 success (skipped detection behind a green conclusion). Designed skips
                 (report job after green detect, if:failure() publish step on green) are
                 expected and listed separately.

Attribution policy: a schedule run belongs to the latest slot <= its run_started_at.
GitHub delays scheduled runs under load but never fires them early, so attribution is
unambiguous; raw start times are always recorded so any mapping dispute is auditable.

Miss-cause census (all-events): the runs query is NOT event-filtered — every
closure-watcher run of every event (schedule, workflow_dispatch, workflow_run)
in the window is collected, so a missed slot's cause class is judged against the
FULL concurrency-group record, not just schedule runs. Emitted cause classes:
  - pending-replacement   a run record with conclusion=cancelled exists inside
                          the slot window (default concurrency: a new pending
                          run cancels the previous pending one — the replaced
                          run leaves a cancelled record; queue: max would
                          mitigate THIS class)
  - no-record-high-load-drop
                          no run record of any event inside the slot window —
                          the scheduled firing was dropped by GitHub under
                          load ("some queued jobs may be dropped",
                          docs.github.com; no SLA). No concurrency setting
                          prevents this class; mitigation is off-hour cron +
                          longitudinal ledger observation.
Every run found inside a missed slot's window is also recorded verbatim in the
slot's competing_entries (id/event/created_at/run_started_at/conclusion) and the
last schedule run before the slot in last_run_before_slot (group-idle evidence),
so any cause judgment stays auditable from the raw records.

Rule of three: claiming "0 misses" at 95% confidence needs N >= 60 slots
(4 slots/day -> 15 days). Exact binomial one-sided 95% upper for 0 misses is
p_UB = 1 - 0.05**(1/N): N=56 (14 days) -> ~5.21% > 5% (FAILS the criterion);
N=60 -> ~4.87% <= 5% (passes). The completion condition is therefore a 15-day
window (60 slots), not 14. Below the threshold, the ledger is a
window-in-progress, not a proof.

Usage:
  python3 tools/ci/closure_watcher_slot_ledger.py \
      --repo Archright/Axiom --registered-after 2026-10-09T21:20:30Z \
      --out-json /tmp/ledger.json --out-md /tmp/ledger.md
"""

import argparse
import datetime as dt
import json
import subprocess
import sys

UTC = dt.timezone.utc
DETECT_JOB_NAMES = {"detect", "watch-closure-drift"}


def parse_iso(text):
    return dt.datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(UTC)


def fmt_iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_cron_fixed_minute_step_hour(expr):
    """Supports '<m> */<h> * * *' (the closure-watcher grid). Anything else: fail-closed."""
    fields = expr.split()
    if len(fields) != 5:
        raise SystemExit(f"unsupported cron expression (need 5 fields): {expr!r}")
    minute_f, hour_f = fields[0], fields[1]
    if minute_f == "*" or not minute_f.isdigit():
        raise SystemExit(f"unsupported cron minute field: {minute_f!r}")
    if not hour_f.startswith("*/") or not hour_f[2:].isdigit():
        raise SystemExit(f"unsupported cron hour field (want */H): {hour_f!r}")
    return int(minute_f), int(hour_f[2:])


def enumerate_slots(cron, start, end, registered_after):
    minute, hour_step = parse_cron_fixed_minute_step_hour(cron)
    day = start.astimezone(UTC).date()
    end_date = end.astimezone(UTC).date()
    slots = []
    while day <= end_date:
        for hour in range(24):
            if hour % hour_step != 0:
                continue
            slot = dt.datetime(day.year, day.month, day.day, hour, minute, tzinfo=UTC)
            if slot >= start and slot < end:
                if registered_after is not None and slot <= registered_after:
                    continue
                slots.append(slot)
        day += dt.timedelta(days=1)
    return slots


def gh_api(path, paginate=False):
    cmd = ["gh", "api"]
    if paginate:
        cmd.append("--paginate")
    cmd.append(path)
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"gh api failed for {path}: {proc.stderr.strip()}")
    return proc.stdout


def fetch_runs(repo, workflow, start, end):
    """All-events census: every run of the workflow in the created window.

    The created-range filter keeps each query narrow (per_window slice below);
    the 1,000-result cap on filtered run lists is watched and warned about.
    """
    created = f"{start.astimezone(UTC).date()}..{end.astimezone(UTC).date()}"
    path = (f"repos/{repo}/actions/workflows/{workflow}/runs"
            f"?created={created}&per_page=100")
    raw = gh_api(path, paginate=True)
    runs = []
    for line in raw.splitlines():
        if not line.strip():
            continue
        page = json.loads(line)
        total = page.get("total_count", 0)
        if total > 900:
            print(f"WARNING: {total} filtered results approach the 1,000-result "
                  f"search cap — split the window into smaller slices.", file=sys.stderr)
        runs.extend(page.get("workflow_runs", []))
    return runs


def fetch_run_jobs(repo, run_id):
    raw = gh_api(f"repos/{repo}/actions/runs/{run_id}/jobs?per_page=100")
    return json.loads(raw).get("jobs", [])


def classify(repo, slots, runs, on_time_minutes, missed_cutoff_hours, include_jobs):
    now = dt.datetime.now(UTC)
    slot_rows = []
    unattributed = []
    used_run_ids = set()
    cancelled = 0
    hollow = []
    skipped_job_total = 0
    run_details = {}

    schedule_runs = [r for r in runs if r.get("event") == "schedule"]
    non_schedule_runs = [r for r in runs if r.get("event") != "schedule"]

    for run in schedule_runs:
        started = parse_iso(run.get("run_started_at") or run.get("created_at"))
        prior = [s for s in slots if s <= started]
        if not prior:
            unattributed.append(run)
            continue
        slot = prior[-1]
        used_run_ids.add(run["id"])
        run_details.setdefault(slot, []).append(run)
        if run.get("conclusion") == "cancelled":
            cancelled += 1

    def run_sort_key(r):
        return parse_iso(r.get("run_started_at") or r["created_at"])

    for slot in slots:
        entries = run_details.get(slot, [])
        if not entries:
            state = "pending" if now < slot + dt.timedelta(hours=missed_cutoff_hours) else "missed"
            row = {"slot": fmt_iso(slot), "state": state}
            if state == "missed":
                window_end = slot + dt.timedelta(hours=missed_cutoff_hours)
                in_window = [
                    r for r in runs
                    if (slot <= parse_iso(r["created_at"]) < window_end
                        or (r.get("run_started_at")
                            and slot <= parse_iso(r["run_started_at"]) < window_end))
                ]
                # Default concurrency: a replaced pending run leaves a cancelled
                # record. A cancelled record inside the window is the ONLY
                # pending-replacement signature; absence of any record at all
                # (with the group idle) is the documented high-load drop class.
                if any(r.get("conclusion") == "cancelled" for r in in_window):
                    cause = "pending-replacement"
                else:
                    cause = "no-record-high-load-drop"
                prior_runs = [r for r in schedule_runs if run_sort_key(r) <= slot]
                last_before = max(prior_runs, key=run_sort_key) if prior_runs else None
                row["cause_class"] = cause
                row["competing_entries"] = [
                    {"id": r["id"], "event": r.get("event"),
                     "created_at": r.get("created_at"),
                     "run_started_at": r.get("run_started_at"),
                     "status": r.get("status"), "conclusion": r.get("conclusion")}
                    for r in sorted(in_window, key=run_sort_key)
                ]
                if last_before is not None:
                    row["last_run_before_slot"] = {
                        "id": last_before["id"],
                        "run_started_at": last_before.get("run_started_at"),
                        "updated_at": last_before.get("updated_at"),
                        "conclusion": last_before.get("conclusion"),
                        "completed_before_slot": (
                            last_before.get("updated_at") is not None
                            and parse_iso(last_before["updated_at"]) <= slot),
                    }
            slot_rows.append(row)
            continue
        primary = min(entries, key=run_sort_key)
        started = parse_iso(primary.get("run_started_at") or primary["created_at"])
        delay_min = round((started - slot).total_seconds() / 60.0, 1)
        if delay_min <= on_time_minutes:
            state = "on_time"
        else:
            state = "late"
        conclusion = primary.get("conclusion")
        row = {
            "slot": fmt_iso(slot),
            "state": state,
            "run_id": primary["id"],
            "started_at": fmt_iso(started),
            "delay_minutes": delay_min,
            "conclusion": conclusion,
            "extra_runs": [r["id"] for r in entries if r["id"] != primary["id"]],
        }
        if conclusion == "cancelled":
            row["state"] = "cancelled"
        elif conclusion == "success" and include_jobs:
            jobs = fetch_run_jobs(repo, primary["id"])
            skipped_jobs = [j for j in jobs if j.get("conclusion") == "skipped"]
            detect_ok = any(
                j.get("conclusion") == "success" and j.get("name") in DETECT_JOB_NAMES
                for j in jobs
            )
            skipped_job_total += len(skipped_jobs)
            if not jobs or not detect_ok:
                row["state"] = "hollow"
                hollow.append(row["run_id"])
            row["jobs_total"] = len(jobs)
            row["jobs_skipped"] = len(skipped_jobs)
        elif conclusion == "failure" and include_jobs:
            jobs = fetch_run_jobs(repo, primary["id"])
            row["jobs_total"] = len(jobs)
            row["jobs_skipped"] = sum(1 for j in jobs if j.get("conclusion") == "skipped")
        slot_rows.append(row)

    return slot_rows, unattributed, cancelled, hollow, skipped_job_total, non_schedule_runs


def summarize(slot_rows):
    counts = {}
    for row in slot_rows:
        counts[row["state"]] = counts.get(row["state"], 0) + 1
    return counts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="Archright/Axiom")
    ap.add_argument("--workflow", default="closure-watcher.yml")
    ap.add_argument("--cron", default="17 */6 * * *")
    ap.add_argument("--days", type=int, default=15,
                    help="ISO UTC window length in days; default 15 = 60 slots "
                         "(the N>=60 completion condition)")
    ap.add_argument("--window-start", default=None, help="ISO UTC; default: now - days")
    ap.add_argument("--window-end", default=None, help="ISO UTC; default: now")
    ap.add_argument("--registered-after", default=None,
                    help="ISO UTC; schedule slots at/before this instant are excluded "
                         "(workflow registration time)")
    ap.add_argument("--on-time-minutes", type=int, default=60)
    ap.add_argument("--missed-cutoff-hours", type=int, default=6)
    ap.add_argument("--no-jobs", action="store_true",
                    help="skip per-run job queries (no hollow detection)")
    ap.add_argument("--out-json", default=None)
    ap.add_argument("--out-md", default=None)
    args = ap.parse_args()

    end = parse_iso(args.window_end) if args.window_end else dt.datetime.now(UTC)
    start = parse_iso(args.window_start) if args.window_start else end - dt.timedelta(days=args.days)
    registered_after = parse_iso(args.registered_after) if args.registered_after else None

    slots = enumerate_slots(args.cron, start, end, registered_after)
    runs = fetch_runs(args.repo, args.workflow, start, end)
    runs = [r for r in runs if start <= parse_iso(r["created_at"]) < end]

    slot_rows, unattributed, cancelled, hollow, skipped_jobs, non_schedule_runs = classify(
        args.repo, slots, runs, args.on_time_minutes, args.missed_cutoff_hours,
        include_jobs=not args.no_jobs)

    counts = summarize(slot_rows)
    expected = len(slot_rows)
    observed = sum(1 for r in slot_rows if "run_id" in r)
    miss_causes = {}
    for row in slot_rows:
        if row["state"] == "missed":
            cause = row.get("cause_class", "unclassified")
            miss_causes[cause] = miss_causes.get(cause, 0) + 1
    ledger = {
        "repo": args.repo,
        "workflow": args.workflow,
        "cron": args.cron,
        "window": {"start": fmt_iso(start), "end": fmt_iso(end)},
        "registered_after": fmt_iso(registered_after) if registered_after else None,
        "on_time_minutes": args.on_time_minutes,
        "missed_cutoff_hours": args.missed_cutoff_hours,
        "summary": {
            "expected_slots": expected,
            "observed_slots": observed,
            "on_time": counts.get("on_time", 0),
            "late": counts.get("late", 0),
            "missed": counts.get("missed", 0),
            "pending": counts.get("pending", 0),
            "cancelled": counts.get("cancelled", 0),
            "hollow": counts.get("hollow", 0),
            "runs_cancelled": cancelled,
            "skipped_jobs_in_green_runs": skipped_jobs,
            "unattributed_runs": len(unattributed),
            "miss_causes": miss_causes,
        },
        "slots": slot_rows,
        "non_schedule_runs": [
            {"id": r["id"], "event": r.get("event"), "created_at": r.get("created_at"),
             "run_started_at": r.get("run_started_at"),
             "status": r.get("status"), "conclusion": r.get("conclusion")}
            for r in non_schedule_runs
        ],
        "unattributed_runs": [
            {"id": r["id"], "created_at": r["created_at"]} for r in unattributed
        ],
        "confidence_note": "rule of three: 0-miss claim at 95% confidence requires "
                           "N >= 60 slots (15 days at 4 slots/day); below that this "
                           "ledger is a window-in-progress, not a proof",
    }

    if args.out_json:
        with open(args.out_json, "w", encoding="utf-8") as fh:
            json.dump(ledger, fh, ensure_ascii=False, indent=2)
    if args.out_md:
        with open(args.out_md, "w", encoding="utf-8") as fh:
            fh.write(md_table(ledger))
    print(json.dumps(ledger["summary"], ensure_ascii=False, indent=2))


def md_table(ledger):
    lines = []
    s = ledger["summary"]
    lines.append(f"# closure-watcher slot ledger — {ledger['window']['start']} .. {ledger['window']['end']}")
    lines.append("")
    lines.append("| metric | value |")
    lines.append("|---|---|")
    for key in ("expected_slots", "observed_slots", "on_time", "late", "missed",
                "pending", "cancelled", "hollow", "runs_cancelled",
                "skipped_jobs_in_green_runs", "unattributed_runs"):
        lines.append(f"| {key} | {s[key]} |")
    lines.append(f"| miss_causes | {json.dumps(s.get('miss_causes', {}), sort_keys=True)} |")
    lines.append("")
    lines.append("| slot (UTC) | state | cause | run | started (UTC) | delay (min) | conclusion |")
    lines.append("|---|---|---|---|---|---|---|")
    for row in ledger["slots"]:
        lines.append("| {slot} | {state} | {cause} | {run} | {started} | {delay} | {concl} |".format(
            slot=row["slot"], state=row["state"],
            cause=row.get("cause_class", "-"),
            run=row.get("run_id", "-"),
            started=row.get("started_at", "-"), delay=row.get("delay_minutes", "-"),
            concl=row.get("conclusion", "-")))
    lines.append("")
    lines.append(f"NOTE: {ledger['confidence_note']}")
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    main()
