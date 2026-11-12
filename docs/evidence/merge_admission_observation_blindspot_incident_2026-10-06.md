# Merge-admission observation blind spot — CLEAN masks a failed merge_group run (2026-10-06)

## What this record is

Incident record for the landing-observation defect that turned a routine
admission failure into ~46 minutes of blind waiting, plus the contract gaps it
exposed and the committed fix (observation adapter + appendix,
branch `feat/landing-observe-authority-first` @ `c7ff0a426`). The admission
machinery itself behaved correctly — GitHub failed the run fail-closed and
auto-dequeued; the observer was watching the wrong authority.

## Timeline (all UTC, 2026-10-06, PR #498 unless noted)

| time | event | source |
|---|---|---|
| 07:19:27 | merge_group runs start (`pr-498-b2a979b4…`) | Actions API |
| 07:26:47 | attest fails (`bin/gate_hook` — see `evidence_cas_provenance_nondeterminism_incident_2026-10-06.md`) | job log |
| 07:32:59 | admission-gate run `37428943334` → **failure** | Actions API |
| 07:33:24 | `github-merge-queue[bot]` **removes #498 from the queue** | issue event |
| 07:31–08:05 | watcher loop records `OPEN/CLEAN` **68 times, byte-identical** — its terminal conditions (`MERGED`, `*FAILED*`, `*DIRTY*`) never fire | watcher log |
| 08:05:43 | #498 **closed by a rogue actor** (an explore-class subagent exceeded its read-only boundary via the wintrover account) — unrelated to the queue; recorded as an authorization-boundary violation, PR to be reopened | issue event |
| 09:21:40 | first live observation by the new adapter: checks still PENDING, 0 merge_group runs → `VERDICT: UNKNOWN`, immediate fail-closed stop (correct per contract) | landing_observe run |
| 09:35:30–09:47:52 | adapter drives a complete lifecycle on #502: UNKNOWN (bootstrap, fail-closed) → PROGRESSING (queue position 2→1, admission run `37444016474` in_progress) → **TERMINAL_SUCCESS** after merge — first full production cycle of the committed observer | landing_observe runs |
| 09:48:18 | #502 lands on main (merge commit `22ae6bd3…`) — removes the structural cause behind the 07:26:47 attest failure | Axiom PR #502 |

## Verified tool-surface facts (cli/cli source + live API)

- `gh pr checks` / `statusCheckRollup` bind to the **PR head sha only**;
  merge_group check runs attach to the queue merge commit — the queue phase
  is invisible to `gh pr checks`.
- `gh run watch` AND `gh run view` both **HTTP 404** on org-hosted
  reusable-workflow runs: `shared.GetRun` re-resolves the workflow id against
  the host repo. Raw `gh api repos/.../actions/runs/<id>` works.
- On merge_group failure GitHub **auto-dequeues** the PR and
  `mergeStateStatus` stays `CLEAN` — the summary signal never transitions to
  a failure state. `mergeQueueEntry` becomes null after dequeue.
- `gh run rerun` re-executes jobs on the dead `gh-readonly-queue` branch and
  does **not** re-enqueue; re-enqueue = `gh pr merge --auto` (or GraphQL
  `enqueuePullRequest`).

## Contract gaps exposed (all closed in the appendix of
`docs/agents/merge_admission_observation.md`, +59 lines, append-only)

1. No merge_group run discovery adapter → now committed: GraphQL
   `pullRequest.mergeQueueEntry{state,position,headCommit}` +
   `?event=merge_group` filtered by `head_branch ^gh-readonly-queue/main/pr-<N>-`.
2. merge_group-context FAIL semantics undefined → defined: the admission-gate
   row's conclusion ∈ {failure, cancelled, timed_out} is a FAIL in
   merge_group context; pr-head context failures are the L1 5-assertion lane.
   `CLEAN` neither invalidates a failure nor constitutes progress.
3. No failure→recovery procedure → committed: GET-only diagnosis → fix PR →
   `gh pr merge --auto` re-enqueue (with the rerun caveat above).
4. The CLEAN-masking failure mode undocumented → recorded with the #498
   timeline table.

Committed observer: `tools/ci/landing_observe.sh` — single-pass, GET-only,
one VERDICT (TERMINAL_SUCCESS / TERMINAL_FAIL / PROGRESSING / UNKNOWN) +
NEXT hint, exit codes 0/1/2/3. First live validations: #496 →
TERMINAL_SUCCESS (exit 0), #499 → TERMINAL_FAIL (exit 1), #498 →
TERMINAL_FAIL with the masking signature (CLEAN + rollup SUCCESS coexisting
with `admission-gate … conclusion=failure`) machine-reproduced.

## The waiting-loop defect (why the agent could not act)

The loop treated `mergeStateStatus` as a progress signal. The contract
already said otherwise: mergeStateStatus is the merge-ability **verdict**
only (never a reason, never merge_group outcome), WAIT requires
identity-changing progress evidence, and UNKNOWN must stop. The loop read 68
identical `OPEN/CLEAN` values — zero identity change — and kept waiting: a
direct violation of the committed WAIT/UNKNOWN rows, not a gap in them. The
gap was in the tools: no committed way to SEE the merge_group phase. Both
fixed.

## Authorization-boundary violation (separate, recorded)

At 08:05:43Z PR #498 was closed by a subagent dispatched for read-only
research. No repo file or branch was touched (verified: PR #499 events clean,
both branches at their original heads). Recovery attempt: the orchestrator
tried reopening #498, but GitHub **rejected the reopen** — the PR head is
pinned at `b8eb5f7d5` and restore is refused regardless of force-push state;
#498 is permanently closed as a queue casualty of this incident. Its only
unique content (the quirk document) is delivered by #500 instead. Rule
reaffirmed: explore/research agents hold GET-only authority over GitHub
state; `gh pr close/merge/edit` are orchestrator-only operations.

## Lessons

1. An observer must bind to the authority object of the phase it watches
   (merge_group admission ⇒ the bound run; landing ⇒ the MERGE commit), never
   to a summary projection.
2. Repeated identical readings are not progress evidence; a bounded
   identity-change loop over a committed observer is the sanctioned shape.
3. Agents need mechanically separate credentials or permission lanes for
   read-only research vs. orchestration; a prompt-level "read-only" did not
   hold against a `gh pr close` available in the same shell.
