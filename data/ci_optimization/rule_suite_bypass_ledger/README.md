# Ruleset bypass ledger

The permanent record of every GitHub ruleset bypass landing on `refs/heads/main`,
plus the tool that maintains it.

## Why this directory exists

GitHub exposes ruleset bypass landings only through
`GET /repos/{owner}/{repo}/rulesets/rule-suites`, and that endpoint accepts
`time_period` no larger than **`month`**. There is no `all` option and no
pagination back beyond the window.

That makes the bypass surface a **rolling 30-day window**:

- a landing is observable through the API for roughly 30 days;
- after that the platform discards it;
- nothing in the repository can reconstruct it.

So the API is a *feed*, not a *source of truth*. The ledger is the source of
truth. A bypass landing that is not copied into `ledger.jsonl` while it is still
inside the window is **destroyed** — not archived, not recoverable, gone.

This is the reason the directory is dated evidence *and* a live append target,
rather than a one-off report.

## Files

| Path | Role |
|---|---|
| `ledger.jsonl` | The ledger. One canonical JSON object per line. Append-only in effect: entries are immutable once written. |
| `raw/bypass_refs_heads_main.json` | The unmodified API response the current entries were derived from. Kept so the ledger can be re-derived and audited without re-querying a window that may have rolled. |
| `tools/ci/rule_suite_bypass_ledger.nim` | Merge (`collect → ledger`) and assert (`ledger → verdict`) tool. |
| `tests/unit/test_rule_suite_bypass_ledger.nim` | Unit tests over the pure core, including the freshness boundaries. |

## Canonical record shape

Schema tag: `axiom.rule-suite-bypass-ledger.v1`.

Exactly ten fields, in exactly this order — this order *is* the byte identity of
a line, and therefore the git diff:

```
id, actor_id, actor_name, before_sha, after_sha, ref, repository_id,
repository_name, pushed_at, result
```

`id`, `actor_id`, `repository_id` are integers; the rest are strings.

API fields outside this set (notably `evaluation_result`) are **dropped, not
guessed**. Dropping is what makes a re-fetch of unchanged data a no-op diff; if
extra fields were carried, every upstream API addition would churn the ledger.

Entries are sorted by `(absolute pushed_at instant, id)`. The instant is parsed
arithmetically from the `±HH:MM` offset rather than through `std/times`, because
`times.parse` is a side effect and would put the timezone database on the
determinism path. `id` breaks ties, so the order is total and re-derivation from
the same inputs always produces the identical byte sequence.

## Merge semantics

`merge` is a set union keyed on the immutable `id`:

- **absent in ledger** → appended.
- **present, identical bytes** → no-op (ordinary re-run; idempotent).
- **present, different bytes** → **exit 2, ledger not written.** A bypass record
  cannot legitimately change after creation, so two bodies for one `id` mean the
  input is corrupt. The tool refuses to pick a winner.
- **empty result** → **exit 2, ledger not written.** An empty ledger is
  indistinguishable from a failed fetch, so writing one would erase the record
  while looking successful.

## Assert semantics

Exit codes: `0` = no finding, `1` = finding, `2` = usage/config/parse error.
A finding is a finding regardless of which check raised it: a direct push, an
elevation-window match, staleness, and a future-dated row all exit `1`.

Three checks, and the distinction between *not run* and *clean* is the whole point:

- **Direct-push detection** compares each `after_sha` against a caller-supplied
  first-parent commit set. Without `--first-parent` the check reports `UNKNOWN`
  and never `0 findings`. It is not fetched internally: `tools/ci/git_access_scan.sh`
  clause 1 forbids unbounded history walks under the depth-1 CI path. An empty
  first-parent file is an error, not a pass.
- **Elevation windows** match `pushed_at` against caller-supplied
  `{"windows":[{"label","start","end"}]}`, inclusive at both ends. Without
  `--windows` the check reports `UNKNOWN`.
- **Freshness** compares the newest recorded `pushed_at` against a
  caller-supplied age limit (`--max-age-days N`) and clock (`--now`). Without
  `--max-age-days` the check reports `UNKNOWN`, never `FRESH`.

All `UNKNOWN` lines are printed unconditionally. A check that did not run must
never be readable as a check that passed.

`--json` emits the same report as a machine-readable projection of the same
struct, so the text and JSON renderers cannot disagree. `freshness`,
`freshnessCheck`, `freshnessAgeDays`, `freshnessMaxAgeDays`,
`freshnessJudgedAtEpoch` and `finding` sit alongside the two existing checks.

### Freshness verdicts

| Verdict | Condition | Exit |
|---|---|---|
| `UNKNOWN` | no `--max-age-days` supplied, or the ledger has no parsable rows | 0 |
| `FRESH` | `floor((now - newest_pushed_at) / 86400) <= N` | 0 |
| `STALE` | age in whole days `> N` | 1 |
| `FUTURE` | newest `pushed_at` is later than `--now` | 1 |

The limit is **inclusive**: a row exactly `N` days old is `FRESH`. Age is
whole days, so a sub-day overshoot of the `N`-day boundary is still `FRESH` —
the discriminating boundary is `N` inclusive / `N+1` exclusive.

`FUTURE` is its own verdict rather than a negative age. A negative age
trivially satisfies `age <= N`, so folding it into `FRESH` would let a
hand-edited or clock-skewed row attest freshness indefinitely. It is a finding
because neither freshness nor staleness can be attested from a record whose
clock disagrees with ours. Decide it, do not skip it.

An empty ledger is `UNKNOWN`, not `STALE`: there is no age to measure, and
`STALE` would invent a measurement. (`merge` already refuses to write an empty
ledger; this is the read side declining to guess.)

## Collecting the feed

The tool does not call the network. Collect first, then merge:

```bash
gh api "repos/Archright/Axiom/rulesets/rule-suites?time_period=month" \
  > raw/bypass_refs_heads_main.json

./bin/rule_suite_bypass_ledger merge \
  --raw raw/bypass_refs_heads_main.json \
  --ledger ledger.jsonl
```

`merge` writes in place by default (`--ledger`); `--out` writes elsewhere.

## Staleness is now detectable — collection still is not automatic

**What is now detectable.** `assert --max-age-days N` makes rot audible. Run it
in the audit path and a ledger whose newest row is older than `N` days exits
`1` with `freshness: STALE (age=<d>d, limit=<N>d)` in the text and
`"freshness": "STALE"` in the JSON. Before this, a ledger nobody had updated for
months reported a clean `PASS` over its own stale contents — a stale zero that
was indistinguishable from "no bypasses". That specific fail-open shape
(AGENTS.md §0.9) is closed.

**What is still not automatic, stated plainly.**

1. **The collector does not run itself.** Freshness detects that the ledger is
   old *once someone runs `assert`*; it cannot run `merge` for you. Collection
   remains **operator-run**: somebody must still run the two commands above and
   land the result.
2. **Detection is only as good as its invocation.** Nothing in this repository
   calls `assert --max-age-days` on a schedule yet — the tool is not wired into
   a Makefile target or a workflow. Until it is, the check is available but not
   enforced, and a check nobody runs is still a silent rot.
3. **`assert` still cannot see landings outside the API window.** If the ledger
   is stale by more than 30 days, the landings it missed are already destroyed
   by the platform. Freshness tells you that you lost evidence; it cannot
   recover it.
4. **No commit-back path exists.** `grep -rn "git push\|git commit"
   .github/workflows/` returns **zero** hits, and exactly **one** workflow holds
   `contents: write` (`certificate-mint.yml`), passing the `TrustedWriterSet`
   gate. Adding a second writer to commit the ledger back would violate the
   writer-set invariant — an architecture change that is **not** part of this
   change and must not be simulated by one.

Making collection automatic requires a workflow with `contents: write` admitted
into the writer set. Wiring `assert --max-age-days` into an existing lane is the
smaller, separate step that would at least make rot fail loudly; it is not done
here because it is not this change's scope.

## Evidence of the underlying behaviour

The bypass surface is not hypothetical. `docs/evidence/ruleset_bypass_scope_probe_2026-11-18/`
records a controlled probe establishing that:

- `bypass_actors` **does** apply to the native REST-merge venue (T2-2: PR #169
  merged as `3f870f61` with a failing required check);
- it **does not** apply to merge-queue-created merge groups (T2-3a PR #173 and
  T2-4 PR #174 removed by `github-merge-queue[bot]`; T2-3b PR #173 → `3f0e0d21`
  was the green control);
- probe rulesets `27523561` / `27523562` were deleted after the run.

## Verification performed

- **Idempotence on real data.** Two consecutive merges of the 26-entry feed
  produce byte-identical output (`diff` clean). This is the tool's core promise.
- **Record completeness.** All 26 real entries carry all ten fields, correctly
  typed, no extras, `pushed_at` uniformly 25 chars, ids unique.
- **`assert` both ways.** With a real first-parent set: `PASS`, exit 0. Without:
  `UNKNOWN` for both checks, exit 0. With a deliberately starved first-parent
  set: `FINDING`, exit 1 — proving the check discriminates rather than always
  passing.
- **Elevation windows** match exactly the three 2026-11-21 landings inside the
  declared interval, and exit 1.
- **Freshness discriminates.** Against the tracked ledger (newest row
  `2026-11-24T19:58:18+09:00`) with `--max-age-days 2` and the real clock:
  `FRESH (age=0d, limit=2d)`, exit 0. With the newest row mutated backwards five
  days in a scratch copy: `STALE (age=3d, limit=2d)`, exit **1**. Restoring the
  row restores `FRESH` — the verdict tracks the data, not a constant.
- **Freshness boundaries are exact.** With `--now` pinned: exactly `N` days
  after the newest row → `FRESH (age=2d, limit=2d)`, exit 0; exactly `N+1` days
  → `STALE (age=3d, limit=2d)`, exit 1; `--now` one hour *before* the newest row
  → `FUTURE`, exit 1.
- **Nine negative cases** each exit 2: conflicting bytes for one id, empty merge,
  malformed windows document, empty first-parent file, malformed ledger line,
  missing argument, no subcommand, non-array raw input. The two fail-closed cases
  were also checked to write no output file. `--max-age-days 0`, `-1`, `abc`, a
  bare `--max-age-days`, and a malformed `--now` each exit 2 as well.
- **Non-vacuity of the tests.** Two mutations of the tool (disabling conflict
  detection; removing the sort) each make the suite fail. The suite is not
  merely green.
- `check_nim_theater` and `core_purity_gate` both pass on the new files.
