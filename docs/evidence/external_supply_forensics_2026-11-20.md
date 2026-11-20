# External supply forensics — CI acceptance v3 (2026-11-20)

> **Status**: observation only. This document adds no workflow, policy, collector,
> or trust-surface change. It records what the collector reported at
> `2026-11-20T06:27:07Z` and what the failing job logs actually say.
> **Contract**: `docs/spec/ci_acceptance_contract.md` (v3,
> `axiom.ci_acceptance.v3`).
> **Boundary**: `aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356`.
> **Window**: 20, mode `initial`.
> **Report**: `data/ci_optimization/ci_acceptance_2026-11-20/ci_acceptance_report.json`
> (+ `.md`, emitted by the collector; both copied byte-for-byte from the run).
> **Prior snapshot**: `/tmp/acc-final3/ci_acceptance_report.json`,
> `generated_at=2026-11-20T06:10:13Z` (same boundary/window/mode).

## §0. Bottom line

| Question | Answer | Evidence |
|---|---|---|
| Did the old observation gap resolve? | **Yes** — run `44685401811` is now `completed/success` (`updated_at=2026-11-20T06:13:37Z`) | §1.3 |
| Did acceptance reach `observation_complete=true` / `status=FAILED`? | **No** — fresh report is `status=INCOMPLETE`, `observation_complete=false`, exit `2` | §1.1–§1.2 |
| Why? | A **new** gap appeared for run `44687078141` (status `queued` at collection), which is the 28th post-boundary entry and is **outside** the 20-entry window | §1.3 |
| How many entries does the report classify `external_dependency`? | **7** | §2 |
| How many of those have an actual apt/package-supply failure in their logs? | **2** (`44519217624`, `44521587339`) | §3 |
| What do the other 5 show? | artifact retrieval failure (2), `ROT_ALLOWLIST` policy refusal (2), ancestry/history-cap failure (1) | §3.3–§3.7 |
| Why do those 5 carry the supply signature? | The action's own script is echoed into the job log, including the comment `E: Could not get lock /var/lib/dpkg/lock-frontend`; the collector matches raw substrings over the concatenated attempt text | §4 |
| Did any attempt recover? | **No** — all 7 runs have `run_attempt=1` and no re-run | §5.3 |

The acceptance verdict (`accepted=false`) is unchanged either way: the fresh
report fails on `observation_complete=false` and on
`external_dependency_blocked=7`. The forensic correction in §6 changes the
**reason mix**, not the verdict.

## §1. Collection

### §1.1 Command and exit

```console
$ bin/ci_acceptance_collect --repo Archright/Axiom \
    --boundary aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356 \
    --window 20 --mode initial
[ci_acceptance_collect] boundary=aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356
[ci_acceptance_collect] mode=initial status=INCOMPLETE window=20/20 shortfall=0 excluded_before_boundary=16
[ci_acceptance_collect] counts: success=13 legitimate_policy=0 internal_defect=0 (identity=0 soundness=0 projection=0 authority=0) unclassified=0 external_dependency_blocked=7 recovered_degradation=0 cancelled_superseded=0
[ci_acceptance_collect] latency canonical n=20 p50=590.5s mean=609.4s min=387s max=941s
[ci_acceptance_collect] latency legacy n=20 p50=593.5s mean=612.0s
[ci_acceptance_collect] accepted=false predicate_holds=false observation_complete=false
[ci_acceptance_collect] wrote build/ci_acceptance/ci_acceptance_report.json and build/ci_acceptance/ci_acceptance_report.md
EXIT=2
```

The collector wrote to `build/ci_acceptance/` (its default `--out`). The two
files were copied without modification to
`data/ci_optimization/ci_acceptance_2026-11-20/`; the JSON SHA-256 is
`f934a507a20d9692f41262476ee60090ef1ea5b25a3244f45d68135ce5fab958` for both
the source and the copy.

### §1.2 Report fields (fresh)

```json
{
  "generated_at": "2026-11-20T06:27:07Z",
  "boundary": "aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356",
  "counts": {
    "success": 13, "legitimate_policy": 0, "internal_defect": 0,
    "unclassified": 0, "external_dependency": 7,
    "recovered_degradation": 0, "cancelled_superseded": 0
  },
  "acceptance": {
    "mode": "initial", "status": "INCOMPLETE",
    "requested_window": 20, "observed_entries": 20, "shortfall": 0,
    "unexpected_internal_defects": 0, "unclassified": 0,
    "external_dependency_blocked": 7, "recovered_degradation": 0,
    "predicate_holds": false, "observation_complete": false,
    "accepted": false
  }
}
```

`acceptance.gaps[0]` is the only gap:

```text
run 44687078141/attempt 1: no artifact/log evidence available
(artifacts: gh api repos/Archright/Axiom/actions/runs/44687078141/attempts/1/artifacts?per_page=100 exited 1: {;
 logs: gh api download repos/Archright/Axiom/actions/runs/44687078141/attempts/1/logs exited 1)
```

### §1.3 Why the expected `FAILED` did not occur

The prior snapshot's gap named `44685401811/attempt 1`. That run is now
finished:

```console
$ gh api repos/Archright/Axiom/actions/runs/44685401811 --jq '...'
44685401811 attempt=1 status=completed conclusion=success created=2026-11-20T06:05:58Z updated=2026-11-20T06:13:37Z
```

The fresh snapshot instead names `44687078141/attempt 1`, which at collection
time was `status=queued`:

```console
$ gh api repos/Archright/Axiom/actions/runs/44687078141 --jq '...'
44687078141 attempt=1 status=queued conclusion=<none> created=2026-11-20T06:20:16Z updated=2026-11-20T06:28:42Z
```

`44687078141` is not in the measured window: the report's `entries` array has
exactly 20 rows, ordered by terminal `run_started_at`, ending at
`44680330023` (PR 244). In the ordered post-boundary entry list (16
pre-boundary entries excluded, per `excluded_before_boundary=16`),
`44685401811` is the 27th entry and `44687078141` is the 28th, so neither can
have a window row; yet the 28th entry's evidence gap is merged into
`acceptance.gaps`.

The collector does this by construction:

- `fetchEvidenceForEntries` iterates **every post-boundary entry**
  (`tools/ci/ci_acceptance_collect.nim:2315-2317`), not only the entries
  selected for the window.
- Evidence errors are accumulated for every failed attempt
  (`:2328-2343`).
- All gap sources (attempt, boundary, authority, replacement, evidence) are
  merged into `acceptance.gaps`, and `observationComplete` is
  `allGaps.len == 0 and observedEntries > 0`
  (`tools/ci/ci_acceptance_collect.nim:2586-2592`).

Consequently, while the live queue has any post-boundary entry outside the
window that is still queued/running, `observation_complete` is false for
`mode=initial` even though the 20 measured entries are fully observable. This
is an observation-window/queue-advance interaction, not a missing report for a
measured entry. No collector change is made here.

The 20 measured entries are identical between the prior and fresh snapshots
(same run IDs, same order, same classifications); only `generated_at` and the
name of the out-of-window gap changed.

## §2. The seven `external_dependency` entries (report fields)

All seven are `classification=external_dependency`,
`subtype=external_supply_unavailable`, `control_outcome=fail_closed`,
`recovered_degradation=false`, `gap=false`, `attempts=run:<id>/attempt:1`.

| run_id | PR | subtype | control_outcome | attempts | evidence reference (report) |
|---|---:|---|---|---|---|
| `44519217624` | 211 | `external_supply_unavailable` | `fail_closed` | `44519217624:1` | `run:44519217624/attempt:1/log:logs/10_attest _ admission-check.txt` |
| `44521587339` | 211 | `external_supply_unavailable` | `fail_closed` | `44521587339:1` | `run:44521587339/attempt:1/log:logs/12_attest _ go-critical-lane (1).txt` |
| `44662615542` | 227 | `external_supply_unavailable` | `fail_closed` | `44662615542:1` | `run:44662615542/attempt:1/log:logs/11_mint-prepare _ prepare.txt` |
| `44663622984` | 227 | `external_supply_unavailable` | `fail_closed` | `44663622984:1` | `run:44663622984/attempt:1/log:logs/10_mint-prepare _ prepare.txt` |
| `44668581737` | 227 | `external_supply_unavailable` | `fail_closed` | `44668581737:1` | `run:44668581737/attempt:1/log:logs/11_attest _ admission-check.txt` |
| `44669070505` | 234 | `external_supply_unavailable` | `fail_closed` | `44669070505:1` | `run:44669070505/attempt:1/log:logs/10_attest _ admission-check.txt` |
| `44675885492` | 233 | `external_supply_unavailable` | `fail_closed` | `44675885492:1` | `run:44675885492/attempt:1/log:logs/12_attest _ admission-check.txt` |

Every run has `event=merge_group`, `run_attempt=1`, and
`conclusion=failure`. Run heads and queue bases:

| run_id | head | base |
|---|---|---|
| `44519217624` | `2ff9f58a8c9d97eeb8bcd25b1333dd9ec4f7fa34` | `aa0f78a8…` |
| `44521587339` | `807f38d9fec0e9747a53a5d8de7db843935e97ca` | `aa0f78a8…` |
| `44662615542` | `e1a06f5ddc7891044905929e28ef3cffa3b65d97` | `cd7b1dea…` |
| `44663622984` | `d49e955895d83290976958189979167053e1956b` | `cd7b1dea…` |
| `44668581737` | `4673ba558b8bad43b47dd5fb2a1d4df2ea39aef9` | `abcc12c6…` |
| `44669070505` | `aba55ca12b84e1add3069bc99339734195a9c1fd` | `4673ba55…` |
| `44675885492` | `c8bd3c54ceeeffc7c44a853186f47ead9b58c4a6` | `cbd87b4a…` |

**Note on the evidence pointer.** `findEvidence`
(`tools/ci/ci_acceptance_collect.nim:751-763`) returns the first artifact/log
file that contains a signature substring. It is not necessarily the file of the
step that failed. In the five non-apt cases the pointer is an auxiliary job's
log or a downstream job's log; the supply signature comes from the echoed
script, not the failing step. In `44521587339` the pointer is a downstream
cascade job, not the first failing setup step.

## §3. Per-entry failing job, step, and exact line

Logs were fetched with:

```console
$ gh api repos/Archright/Axiom/actions/runs/<run_id>/attempts/1/logs > run-<id>.zip
$ gh api repos/Archright/Axiom/actions/runs/<run_id>/jobs?per_page=100&filter=latest > jobs-<id>.json
```

Failing jobs/steps below are the first failing step per the jobs API; quoted
lines are verbatim log output (epoch timestamps retained).

### §3.1 `44519217624` — PR 211 — **true apt/libpcre3**

- First failing job: `verdict / admission-check` (job `135547025260`).
- First failing step: `[check] Install libpcre3 (bin/ax dlopen dependency — landing verdict)`.
- Exact output:

```text
2026-11-19T12:04:59.9966540Z E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable [IP: 52.15.107.13 80]
2026-11-19T12:04:59.9967280Z E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
2026-11-19T12:07:11.3020928Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble/InRelease  503  Service Unavailable [IP: 52.15.159.198 80]
2026-11-19T12:07:43.6787479Z E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable [IP: 3.129.149.36 80]
2026-11-19T12:07:43.6811570Z ##[error]Process completed with exit code 100.
```

- The failing command is the workflow's inline install
  (`.github/workflows/admission-check.yml:889-902`):

```bash
sudo apt-get install -y -qq libpcre3 \
  || { sudo apt-get update -qq && sudo apt-get install -y -qq libpcre3; }
```

  It has one retry variant (update + install) and **no** pinned-asset or
  mirror tier. The second attempt is the `12:07:43` failure.
- Supply source: `security.ubuntu.com` / `apt-mirrors.txt` (Ubuntu package
  mirror), package `libpcre3_8.39-15build1_amd64.deb`.
- Downstream: the next step emitted the correct fail-closed guard
  (`[check] FAIL: the admission predicate (MergeAdmissible) was SKIPPED …`).
- Control: `fail_closed`. Recovery: none (attempt 1 only).

### §3.2 `44521587339` — PR 211 — **true apt/libpcre3**

- First failing job: `attest / build-base-artifacts` (job `135551293518`).
- First failing step: `Run ./.github/actions/setup-axiom-toolchain`.
- Exact output:

```text
2026-11-19T12:13:03.0486172Z E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable [IP: 3.129.149.36 80]
2026-11-19T12:13:03.0486878Z E: Unable to fetch some archives, maybe run apt-get update or try with --fix-missing?
2026-11-19T12:14:25.1928485Z W: Failed to fetch mirror+file:/etc/apt/apt-mirrors.txt/dists/noble/InRelease  503  Service Unavailable [IP: 52.15.158.54 80]
2026-11-19T12:15:20.0624195Z E: Failed to fetch https://security.ubuntu.com/ubuntu/pool/universe/p/pcre3/libpcre3_8.39-15build1_amd64.deb  503  Service Unavailable [IP: 52.15.159.198 80]
2026-11-19T12:15:20.0649408Z ##[error]Process completed with exit code 100.
```

- The script echoed in **this run's** log is the older two-line form, not the
  current tiered supply ladder (tier 0–4):

```text
sudo apt-get -o DPkg::Lock::Timeout=300 install -y -qq libpcre3 \
  || { sudo apt-get update -qq && sudo apt-get install -y -qq libpcre3; }
```

  So at this head there was no tier-2 pinned asset and no tier-3 mirror list.
- Supply source: same Ubuntu mirror/package as §3.1.
- The other failing jobs in this run are the same supply outage or its
  cascades: `admission-independents` and `go-critical-lane (0)` also failed in
  setup; `mint-publish` hit the same `libpcre3` 503 at `12:21:48` and
  `12:24:04` (`2_mint-publish _ publish.txt:765-774`, exit 100);
  `go-critical-rollup`, `admission-check`, `mint-prepare`, and `verdict` failed
  on needs-gates or missing upstream artifacts.
- Control: `fail_closed`. Recovery: none (attempt 1 only).

### §3.3 `44662615542` — PR 227 — **not a supply failure**

- First failing job: `attest / admission-independents` (job `136044528647`).
- First failing step: `[check] Core purity gate (B-built judge on _candidate tree)`.
- Exact output:

```text
[core_purity] FAIL: 1 core purity regression(s).
  symbol_graph/global_symbol_graph_builder_part2.nim:420: io_primitive — unapproved I/O primitive: startProcess( (observed 1, anchored 0)
[core-purity] FAIL — candidate tree carries a new unapproved core side effect (fail-closed)
```

- A downstream failure, and the file named by the report's evidence pointer, is
  `mint-prepare / prepare` (job `136045517276`), step
  `(3) Artifact retrieval — run-scoped API + trusted-name + witness sha + provenance check`:

```text
MINT_ART: FAIL — expected exactly one artifact named 'admission-check-e1a06f5ddc7891044905929e28ef3cffa3b65d97-1', found 0 (fail-closed)
##[error]Process completed with exit code 1.
```

- There is **no** `E: Failed to fetch` and no apt/dpkg output from this run.
- The collector's evidence pointer is `11_mint-prepare _ prepare.txt`, whose
  line 876 is the echoed action comment:

```text
# 대기한다(관측: run 2026-10-27 `E: Could not get lock /var/lib/dpkg/lock-frontend`).
```

  The same file contains `libpcre3` in the echoed script. That is the entire
  basis for the supply match (§4).
- Source: other — core-purity gate regression → missing `admission-check-…`
  artifact → artifact-retrieval refusal. Not apt, choosenim, elan, or z3.
- Recovery: none (attempt 1 only).

### §3.4 `44663622984` — PR 227 — **not a supply failure**

- First failing job: `attest / admission-independents` (job `136048044314`).
- First failing step: `[check] Core purity gate (B-built judge on _candidate tree)`.
- Exact output:

```text
[core_purity] FAIL: 1 core purity regression(s).
  symbol_graph/global_symbol_graph_builder_part2.nim:420: io_primitive — unapproved I/O primitive: startProcess( (observed 1, anchored 0)
[core-purity] FAIL — candidate tree carries a new unapproved core side effect (fail-closed)
```

- Terminal downstream failure in `mint-prepare / prepare` (job `136049453817`):

```text
MINT_ART: FAIL — expected exactly one artifact named 'admission-check-d49e955895d83290976958189979167053e1956b-1', found 0 (fail-closed)
##[error]Process completed with exit code 1.
```

- No actual apt/dpkg output. The evidence file
  `10_mint-prepare _ prepare.txt` carries the same echoed
  `E: Could not get lock /var/lib/dpkg/lock-frontend` comment and `libpcre3`
  script text.
- Source: other (same core-purity → artifact-retrieval chain as §3.3).
- Recovery: none.

### §3.5 `44668581737` — PR 227 — **not a supply failure**

- First failing job: `verdict / admission-check` (job `136067018028`).
- First failing step: `[check] Admission predicate evaluation (MergeAdmissible verdict → check conclusion)`.
- Exact output (`logs/2_verdict _ admission-check.txt:1023`):

```text
##[error]admission verdict NOT-ADMIT (reasonCode=ROT_ALLOWLIST) — evidence: admission-verdict artifact
##[error]Process completed with exit code 1.
```

- `ROT_ALLOWLIST` is a pre-registered `legitimate_policy` signature
  (contract §4.2), not a supply signature.
- The evidence pointer is `11_attest _ admission-check.txt`, an auxiliary job
  whose verdict array ends with `"reasonCode": "OK"`. Its line 836 is the
  echoed lock comment; that file supplies the literal external signature.
- Source: other — policy refusal (rotation companion path outside the
  allowlist). Recovery: none.

### §3.6 `44669070505` — PR 234 — **not a supply failure**

- First failing job: `verdict / admission-check` (job `136068440624`).
- First failing steps: `[check] Admission predicate evaluation …` and
  `[check] Upload verdict log …`.
- Exact output (`logs/2_verdict _ admission-check.txt:997`):

```text
[check] FAIL: CANDIDATE_MERGE_BASE_UNRESOLVED: ancestry(4673ba558b8bad43b47dd5fb2a1d4df2ea39aef9, 5ac0c742984a6bc7b4199ab4244bfab65959b46b) unresolved after 8x64-commit deepening (history cap reached — fail-closed) (run-level err — fail-closed)
##[error]Process completed with exit code 1.
```

- No actual apt/dpkg output. The evidence pointer
  `10_attest _ admission-check.txt` line 755 is the echoed lock comment.
- Source: other — ancestry/merge-base observation capped at the history
  deepening limit. This is not one of the contract's pre-registered
  `internal_defect` signatures and not a supply signature (§4.4).
- Recovery: none.

### §3.7 `44675885492` — PR 233 — **not a supply failure**

- First failing job: `verdict / admission-check` (job `136089742773`).
- First failing step: `[check] Admission predicate evaluation …`.
- Exact output (`logs/1_verdict _ admission-check.txt:1091`):

```text
##[error]admission verdict NOT-ADMIT (reasonCode=ROT_ALLOWLIST) — evidence: admission-verdict artifact
##[error]Process completed with exit code 1.
```

- Source: other — same policy refusal as §3.5. The evidence pointer
  `12_attest _ admission-check.txt` line 838 is the echoed lock comment.
- Recovery: none.

## §4. Why five entries carry a supply signature without a supply failure

The contract (§4.8) defines the class as a **root cause**:

> "An attempt is `external_dependency` / `external_supply_unavailable` only
> when its evidence carries **both** a supply signature and a
> package-manager context marker."

The collector implements the two-marker rule literally:

```nim
# tools/ci/ci_acceptance_collect.nim:644-649
func hasExternalSupplySignature*(text: string): bool =
  result = containsAny(text, ExternalSupplySignatures) and
    containsAny(text, PackageContextMarkers)
```

`containsAny` is a raw substring scan (`:581-586`). The scanned `text` is the
concatenation of every downloaded artifact and log file for the attempt
(`attemptText`, `:765-771`); no line filtering, ANSI stripping, or
"program output only" restriction is applied.

The repository's toolchain action is a composite action whose `run:` script
GitHub echoes into the job log before executing it. The echoed script includes
this comment (`.github/actions/setup-axiom-toolchain/action.yml:762-764`):

```bash
# ... DPkg::Lock::Timeout — unattended-upgrades가
# lock-frontend를 잡고 있는 동안 즉시 exit 100으로 죽지 않고 최대 300초
# 대기한다(관측: run 2026-10-27 `E: Could not get lock /var/lib/dpkg/lock-frontend`).
```

That comment contains the exact supply signature
`Could not get lock /var/lib/dpkg/lock-frontend`; the same echoed block
contains `libpcre3` as the package context marker. The five logs therefore
satisfy `hasExternalSupplySignature` even though the job never ran a failing
`apt-get`:

| run_id | evidence file | echoed signature line | actual supply output |
|---|---|---|---|
| `44662615542` | `11_mint-prepare _ prepare.txt` | `:876` | none |
| `44663622984` | `10_mint-prepare _ prepare.txt` | `:960` | none |
| `44668581737` | `11_attest _ admission-check.txt` | `:836` | none |
| `44669070505` | `10_attest _ admission-check.txt` | `:755` | none |
| `44675885492` | `12_attest _ admission-check.txt` | `:838` | none |

For contrast, the two true failures have actual timestamped program output
(`E: Failed to fetch …`, `##[error]Process completed with exit code 100`) in
`1_verdict _ admission-check.txt:233-242` (run `44519217624`) and
`23_attest _ build-base-artifacts.txt:730-739` (run `44521587339`).

This is a literal-signature false positive, not an apt outage. The report's
`subtype=external_supply_unavailable` and `control_outcome=fail_closed` fields
for those five entries describe the matched text, not the executed command.
No collector or contract change is made in this PR; the finding is recorded
for the contract/collector owner.

## §5. Retry / fallback inventory (origin/main, read-only)

### §5.1 Toolchain action

Read from `origin/main` with
`git show origin/main:.github/actions/setup-axiom-toolchain/action.yml`
(1,261 lines). The file was not edited.

| Supply | Mechanism | Location | Bounded retry? | Alternate source? |
|---|---|---|---|---|
| `libpcre3` | tier 0 `ldconfig` fast path | `action.yml:695-699` | n/a | n/a |
| `libpcre3` | tier 1 apt version-pinned (`libpcre3=2:8.39-15build1`) | `action.yml:765-769` | one `apt-get update` + install retry | no |
| `libpcre3` | tier 2 pinned GitHub release asset, sha256 + package identity checked | `action.yml:722-726`, `:770-771` | no loop; single `curl --max-time 60` | GitHub release |
| `libpcre3` | tier 3 ordered official mirrors (`de/fr/us.archive.ubuntu.com`), isolated apt view, signed, digest pinned | `action.yml:732-758`, `:772-773` | sequential 3 mirrors | 3 mirrors |
| `libpcre3` | tier 4 explicit failure (`external_dependency: libpcre3 unavailable …`) | `action.yml:774-776` | n/a | no |
| choosenim | `curl --retry 4 --retry-all-errors --retry-delay 2 --retry-max-time 5` | `action.yml:991-993` (arm64 tarball), `:1006-1008` (x86_64 init.sh) | 4 | no |
| elan | same curl retry recipe for `elan-init.sh` | `action.yml:1071-1073` | 4 | no |
| z3 | `curl --retry 4 --retry-all-errors --retry-delay 2` (no time cap) | `action.yml:1113-1114` | 4 | no |
| jq | `curl --retry 4 --retry-all-errors --retry-delay 2` | `action.yml:1147-1148` | 4 | no |
| cache | exact-key restore only; `restore-keys` forbidden; non-exact restore discarded → cold install | `action.yml:101-103` | n/a | cold fallback |

The tiered supply ladder (tier 0–4) was introduced **after** the 2026-11-19 incident; its
comment names the two runs (`action.yml:673-675`):

```text
# Supply ladder (2026-11-19: merge-group runs 44519217624 / 44521587339
# lost security.ubuntu.com to HTTP 503 → apt exit 100 → the admission
# predicate could not run on 8 jobs at once).
```

It was not present at the two incident heads: run `44521587339`'s echoed
script shows only the apt/update variant (§3.2).

### §5.2 Verdict lane

The failing `[check] Install libpcre3 …` step in run `44519217624` is not the
toolchain action; it is an inline step in
`.github/workflows/admission-check.yml:889-902`, with only the apt direct
install and the update+install retry (`:899-900`). It has no tier-2/3
fallback.

### §5.3 Recovery

- Every one of the seven runs has `run_attempt=1`; `attempt_ids` contains only
  `<run_id>:1`. There is no re-run attempt to recover.
- No entry is `recovered_degradation`: no entry has a supply-signature attempt
  followed by a terminal `success`/`legitimate_policy` for the **same entry**.
- Recovery happened only at the PR/candidate level, as new entries with new
  heads:
  - PR 211: `44542633420` (head `69d2dce0`) → `success`.
  - PR 227: `44674123967` (head `e3667780`) → `success`.
  - PR 234: `44669827441` (head `f7d73fd8`) → `success`.
  - PR 233: the window entry `44675885492` failed; no later PR-233 entry is in
    this 20-entry window.
- The supply outage itself was transient: the runs after
  `2026-11-19T12:24Z` in the window have no actual `E: Failed to fetch` line.

## §6. Classification and acceptance impact

### §6.1 Forensic classification

| run_id | report class | log-supported class | supply source | recoverable / terminal |
|---|---|---|---|---|
| `44519217624` | `external_dependency` | `external_dependency` | apt / `libpcre3` (security.ubuntu.com 503) | outage transient; **entry terminal** (attempt 1, failure) |
| `44521587339` | `external_dependency` | `external_dependency` | apt / `libpcre3` (security.ubuntu.com 503) | outage transient; **entry terminal** |
| `44662615542` | `external_dependency` | `unclassified` (§4.4: no pre-registered signature; core-purity → missing artifact) | other (artifact retrieval) | **entry terminal** |
| `44663622984` | `external_dependency` | `unclassified` (same) | other (artifact retrieval) | **entry terminal** |
| `44668581737` | `external_dependency` | `legitimate_policy` (`ROT_ALLOWLIST`, §4.2) | other (policy refusal) | accepted-by-policy; **entry terminal** |
| `44669070505` | `external_dependency` | `unclassified` (§4.4: no pre-registered signature; ancestry history cap) | other (ancestry observation) | **entry terminal** |
| `44675885492` | `external_dependency` | `legitimate_policy` (`ROT_ALLOWLIST`, §4.2) | other (policy refusal) | accepted-by-policy; **entry terminal** |

### §6.2 Counts under the contract's own tables

If the five non-supply entries are read by their actual terminal evidence
(not by the echoed comment), the count changes as follows:

| count | report | log-supported reading |
|---|---:|---:|
| `success` | 13 | 13 |
| `legitimate_policy` | 0 | 2 (`44668581737`, `44675885492`) |
| `unclassified` | 0 | 3 (`44662615542`, `44663622984`, `44669070505`) |
| `external_dependency_blocked` | 7 | 2 (`44519217624`, `44521587339`) |
| `unexpected_internal_defects` | 0 | 0 |

The acceptance predicate still fails: `unclassified=3` and
`external_dependency_blocked=2` are both non-zero, and
`observation_complete=false` (out-of-window gap). The status remains
`INCOMPLETE`, not `ACCEPTED`/`FAILED`.

The important correction is qualitative: the window does **not** contain seven
unrecovered OS package-supply outages. It contains two apt outages (same
2026-11-19 Ubuntu mirror incident) and five entries whose failures are a
core-purity/artifact-retrieval chain, an ancestry history cap, and two
`ROT_ALLOWLIST` policy refusals.

## §7. GitHub semantics used (official documentation)

Quotations below are from the cited pages; they support the API/log reading,
not any Axiom-specific claim.

1. **Run attempt endpoint** —
   <https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#get-a-workflow-run-attempt>:
   "Gets a specific workflow run attempt." The `attempt_number` path parameter
   is documented as "The attempt number of the workflow run". This is the
   endpoint the collector uses for each attempt (`attempts/{n}`), rather than
   the list endpoint that returns 404 (contract §2.5).
2. **Run log archive** —
   <https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#download-workflow-run-logs>:
   "Gets a redirect URL to download an archive of log files for a workflow
   run. This link expires after 1 minute." In the observed case the queued run
   (`44687078141`) had no downloadable attempt archive; the collector records
   that as an observation gap rather than a classification.
3. **Jobs list and `filter=latest`** —
   <https://docs.github.com/en/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run>:
   "`latest` returns jobs from the most recent execution of the workflow run.
   `all` returns all jobs for a workflow run, including from old executions of
   the workflow run." The report's job/step rows come from this endpoint with
   `filter=latest`; step objects carry their own `status`/`conclusion`.
4. **Artifact/log retention** —
   <https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts>:
   "By default, GitHub stores build logs and artifacts for 90 days, and this
   retention period can be customized." This bounds how long the forensic
   evidence used above remains fetchable.
5. **Cache key matching** —
   <https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching#cache-hits-and-misses>:
   "When key exactly matches an existing cache, it's called a cache hit, and
   the action restores the cached files to the path directory." The toolchain
   action's own contract goes further and forbids `restore-keys`
   (`action.yml:101-103`), so a non-exact restore is discarded and the cold
   install path runs.
6. **Installing apt packages on hosted Ubuntu runners** —
   <https://docs.github.com/en/actions/how-tos/manage-runners/github-hosted-runners/customize-runners>:
   "Always run `sudo apt-get update` before installing a package. In case the
   `apt` index is stale, this command fetches and re-indexes any available
   packages, which helps prevent package installation failures." The 503s in
   §3.1–§3.2 are upstream mirror responses, not an index-staleness error; the
   update+install retry also failed.

## §8. Reproduction

```console
# 1. Collector (read-only w.r.t. sources; writes build/ci_acceptance/)
bin/ci_acceptance_collect --repo Archright/Axiom \
  --boundary aa0f78a8d2a6a070d1ff42ee3ead7d062c85d356 \
  --window 20 --mode initial
echo $?   # 2

# 2. Report fields
python3 - <<'PY'
import json
d = json.load(open('build/ci_acceptance/ci_acceptance_report.json'))
print(d['generated_at'], d['acceptance']['status'])
print(d['acceptance']['gaps'])
PY

# 3. Jobs and logs for one run
gh api repos/Archright/Axiom/actions/runs/44519217624/jobs?per_page=100\&filter=latest
gh api repos/Archright/Axiom/actions/runs/44519217624/attempts/1/logs > /tmp/run.zip
unzip -p /tmp/run.zip 'logs/1_verdict _ admission-check.txt' | grep -n 'Failed to fetch\|exit code'

# 4. Attempt count
gh api repos/Archright/Axiom/actions/runs/44519217624 --jq '.run_attempt'
```

## §9. Limits and follow-ups

- **Snapshot boundary**: the report is `2026-11-20T06:27:07Z`. The merge queue
  advanced during collection; `44687078141` was `queued` at that time.
- **Not changed here**: the collector, the contract, workflows, `config/**`,
  and `data/trusted/**`. This PR contains only this document and the two
  report files.
- **Follow-up for the contract/collector owner**: the five false-positive
  `external_dependency` classifications (§4) and the out-of-window gap that
  keeps `observation_complete=false` while the queue is live (§1.3). Both are
  observations; neither is silently patched here.
- The fresh report is preserved verbatim so its `generated_at`, `boundary`,
  `window`, `mode`, and `gaps` can be re-read without re-running the collector.