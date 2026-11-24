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
| `tests/unit/test_rule_suite_bypass_ledger.nim` | Unit tests over the pure core. |

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

Two checks, and the distinction between *not run* and *clean* is the whole point:

- **Direct-push detection** compares each `after_sha` against a caller-supplied
  first-parent commit set. Without `--first-parent` the check reports `UNKNOWN`
  and never `0 findings`. It is not fetched internally: `tools/ci/git_access_scan.sh`
  clause 1 forbids unbounded history walks under the depth-1 CI path. An empty
  first-parent file is an error, not a pass.
- **Elevation windows** match `pushed_at` against caller-supplied
  `{"windows":[{"label","start","end"}]}`, inclusive at both ends. Without
  `--windows` the check reports `UNKNOWN`.

Both `UNKNOWN` lines are printed unconditionally. A check that did not run must
never be readable as a check that passed.

`--json` emits the same report as a machine-readable projection of the same
struct, so the text and JSON renderers cannot disagree.

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

## UNRESOLVED: nothing collects this automatically

**There is no CI path that commits the ledger back to the repository.** This is a
known, deliberate gap, not an oversight to be glossed over:

- `grep -rn "git push\|git commit" .github/workflows/` returns **zero** hits.
- Exactly **one** workflow holds `contents: write` (`certificate-mint.yml`), and
  it passes the `TrustedWriterSet` gate. Adding a second writer to commit the
  ledger would violate the writer-set invariant.

The consequences, stated plainly:

1. Collection is **operator-run**. Somebody must run the two commands above and
   land the result.
2. If nobody does, the ledger **silently rots**: new bypass landings are never
   recorded, and once their 30-day residency expires they are unrecoverable.
   Nothing will fail, because there is nothing to fail — absence of evidence
   looks exactly like absence of bypasses.
3. `assert` cannot detect the staleness. It judges the ledger it is given. A
   ledger last updated months ago reports `PASS` over its own stale contents.

The tool accepts `--out` specifically so a future collector with write authority
can write outside the tracked path; that is why `--out` exists and is not
speculation about a commit-back step that cannot be built today.

Making collection automatic requires a workflow with `contents: write` that is
admitted into the writer set — an architecture change that is **not** part of
this change and must not be simulated by one.

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
- **Nine negative cases** each exit 2: conflicting bytes for one id, empty merge,
  malformed windows document, empty first-parent file, malformed ledger line,
  missing argument, no subcommand, non-array raw input. The two fail-closed cases
  were also checked to write no output file.
- **Non-vacuity of the tests.** Two mutations of the tool (disabling conflict
  detection; removing the sort) each make the suite fail. The suite is not
  merely green.
- `check_nim_theater` and `core_purity_gate` both pass on the new files.
