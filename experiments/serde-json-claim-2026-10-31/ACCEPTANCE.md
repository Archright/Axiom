# ACCEPTANCE — serde_json claim campaign, run 4 (§9 amendment → d1 → cold d2)

- EXPERIMENT_ID: serde-json-claim-2026-10-31
- Written: 2026-10-31, run 4, branch `docs/serde-json-claim-2026-10-31` (Axiom4). This file records **observed facts only** — machine outputs are verbatim, never summarized or paraphrased; no inference beyond the pre-registered §8/§9 mappings is made. Governing documents: FREEZE.md §0–§8 (untouched) + §9 Amendment 1 (pre-registered BEFORE d1; see ⑥ for the mtime-order proof).
- Rules held this run: no `src/` modification; no commit; subject writes limited to the §7/§9 lock place→verify→remove protocol; sibling clones untouched; `GITHUB_TOKEN` procured only via `gh auth token` (value never printed); machine `reason` outputs recorded verbatim.

## ① Runs

Common: CWD = Axiom4 root; `EXP=experiments/serde-json-claim-2026-10-31`; `JSON=<workspace>/json`; subject HEAD `8c535a260ce561eaab4111aafc29038eb9f77ff3`; `bin/ax` provenance `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-1171924972364171515)` exit 0 (re-run at run-4 start).

Pre-run gates:

| step | command | exit | note |
|---|---|---|---|
| preflight (before any file creation) | `nim c -r src/gate/runners/agent_preflight.nim` | 0 | 15.80 s; verbatim tail: `[decision-binding] WARN: 47 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached` + `[INFO] logger: [SUCCESS] Agent Pre-flight Guard: Workspace 무결성 검증 통과.`; binary emitted to `bin/agent_preflight_A582EAC6E18303E12F6F43882981A98FE267F480` (project config redirect) |
| gh token presence | `gh auth token` (existence check only) | 0 | non-empty, value not printed |

d1 (declared target + token, `state_d1`/`vault_d1` — fresh):

```
find $JSON -path '*/.git' -prune -o -type f -print | sort | xargs sha256sum > $EXP/runs/d1/subject_manifest_pre.sha256   # 93 files
mkdir -p $EXP/state_d1/data $EXP/vault_d1
jq --slurpfile e $EXP/inputs/verification_scope.rust_targets.json '.rust_targets += [$e[0]] | .vksRust = 3' data/verification_scope.lock > $EXP/state_d1/data/verification_scope.lock
cp $EXP/inputs/Cargo.lock $JSON/Cargo.lock && sha256sum $JSON/Cargo.lock
AXIOM_STATE_DIR=$PWD/$EXP/state_d1 AXIOM_PROVE_VAULT_DIR=$PWD/$EXP/vault_d1 CARGO_NET_OFFLINE=true GITHUB_TOKEN=$(gh auth token) bin/ax prove --project $JSON --target 'serde_json::error::parse_line_col' > $EXP/runs/d1/stdout.log 2>&1
sha256sum $JSON/Cargo.lock && rm $JSON/Cargo.lock
find $JSON -path '*/.git' -prune -o -type f -print | sort | xargs sha256sum > $EXP/runs/d1/subject_manifest_post.sha256
```

- d1 exit code: **0**; wall 13.241 s (start 1793446239.155085945 → end 1793446252.396510343)
- state lock jq verification: `{"n": 3, "vksRust": 3, "dupPairs": 0, "badHashes": []}`; symbols `axiom_rust_probe::add_u8`, `axiom_rust_probe::add_u8_mutant`, `serde_json::error::parse_line_col`; baseline 2 entries jq -S diff vs `data/verification_scope.lock` → empty (byte-untouched semantics preserved); `state_d1/data/verification_scope.lock` sha256 `0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e`

d2 (cold: fresh `state_d2`/`vault_d2`, no reuse of d1 artifacts; identical command otherwise):

- d2 exit code: **0**; wall 13.008 s (start 1793446379.061531827 → end 1793446392.069070280)
- d2 pre-manifest diff vs d1 pre-manifest → empty; state lock sha256 `0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e` (identical to d1's); jq verification identical (`n:3, vksRust:3`)

Artifact sha256 (runs + state):

| file | sha256 |
|---|---|
| runs/d1/stdout.log | `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d` |
| runs/d1/subject_manifest_pre.sha256 | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| runs/d1/subject_manifest_post.sha256 | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| runs/d1/skreport_payload.json | `0604043fdb7ebc277f54f7cb4505b8e5cdc92d96ddc9b8ce93cebb6dc7472f06` |
| runs/d2/stdout.log | `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d` |
| runs/d2/subject_manifest_pre.sha256 | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| runs/d2/subject_manifest_post.sha256 | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| runs/d2/skreport_payload.json | `edfd70515453e3dda5e8270f0f23ecabfaa6300d14497901d2d322ebb1b2c949` |
| state_d1/logs/ax_prove_trajectory.jsonl | `21a3977d741eebf8f98ccf75a6179c6647ccf0a1548c9ac8c38de134b20f40d9` (1 line) |
| state_d2/logs/ax_prove_trajectory.jsonl | `b53d0d166762dc39204432961bb65b6b44428cd6b6eb527edc22b5342313d77a` (1 line) |
| runs/pre_d1_amendment_timestamps.txt | `bbb48ae273110932ee22c0fed374ec16531a67797327599c44faeed80778cb0b` |

Trajectory envelope verbatim (1 line per run; `extra` = the skReport payload, see ③):

- d1: `{"ts":"2026-10-31T11:30:51.688Z","phase":"skReport","nodeId":"","detail":"rust subject lane completed","elapsedMs":0,"status":"ssStarted"}`
- d2: `{"ts":"2026-10-31T11:33:11.371Z","phase":"skReport","nodeId":"","detail":"rust subject lane completed","elapsedMs":0,"status":"ssStarted"}`

`vault_d1/` and `vault_d2/` are empty (no vault artifacts produced by either run).

## ② Three-axis comparison (d1 vs d2)

| axis | d1 | d2 | verdict |
|---|---|---|---|
| ① exit code | 0 | 0 | **identical** |
| ② Cargo.lock sha256 in==out | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (both in and out) | same, in==out | **identical** |
| ③ canonical skReport payload (`jq -S .extra`) byte-identity | `0604043f…7472f06` | `edfd7051…b1b2c949` | **NOT byte-identical — single-hunk difference, recorded verbatim in ③/⑥** |

Axis-3 exact diff (the only differing lines of the canonical payloads):

```diff
<       "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d1/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/211aa9d180883da9/out/private.rs' (subject-relative POSIX path required)",
>       "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d2/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/8b65d3d27583c0f0/out/private.rs' (subject-relative POSIX path required)",
```

Facts accompanying axis 3 (no masking applied; the masked re-check `state_dN` substitution still differs on the charon-target hash `211aa9d180883da9` vs `8b65d3d27583c0f0`): the payload's only run-varying substrings are the state-dir name and the charon-target build dir hash, both inside `targets[0].reason`. stdout.log is byte-identical across d1/d2 (same sha256, 3 lines). Trajectory envelopes differ only in `ts`. §7's comparison-basis note stated the skReport payload "carries no timestamps or paths" — the observed payload embeds an absolute path in `targets[0].reason`; recorded as an observed fact in ⑥.

## ③ Machine verdicts (verbatim)

stdout — d1 (all 3 lines, byte-identical file also equals d2's):

```
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] done: verified=0/1 failed=0 unknown=1 error=0
```

stdout — d2 (all 3 lines, byte-identical to d1's, sha256 `9ddc5dbc…`):

```
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] done: verified=0/1 failed=0 unknown=1 error=0
```

d1 `targets[0]` verbatim (full skReport payload preserved at runs/d1/skreport_payload.json; schemaVersion `axiom.report.v1`, subjectLane `rust`, charon ok=true pinned==measured `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)`, summary `{"failedCount":0,"statusCounts":{"error":0,"failed":0,"unknown":1,"verified":0},"timeoutCount":0,"verified":0,"verifiedRatio":0.0}`):

```json
{
  "name": "serde_json::error::parse_line_col",
  "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d1/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/211aa9d180883da9/out/private.rs' (subject-relative POSIX path required)",
  "status": "unknown"
}
```

d2 `targets[0]` verbatim:

```json
{
  "name": "serde_json::error::parse_line_col",
  "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d2/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/8b65d3d27583c0f0/out/private.rs' (subject-relative POSIX path required)",
  "status": "unknown"
}
```

Machine facts for ②'s axis-3 context: the charon extraction produced `state_dN/.axiom/rust-lane/1398235db249fc8b/subject.llbc` in both runs; the LLBC `translated.files` table has 151 entries in the probe, d1, and d2 extractions, and in each of them `files[1]` carries an absolute `Local` name under `<run state dir>/.axiom/rust-lane/1398235db249fc8b/charon-target/…/build/serde_json/<hash>/out/private.rs` while `files[0]`, `files[2]`+ are subject-relative (`src/lib.rs`, `src/de.rs`, `src/error.rs`, …). The signature-gate / spec-decode stage produced no output line in either run.

## ④ Subject integrity

| check | observed |
|---|---|
| subject HEAD (end of run 4) | `8c535a260ce561eaab4111aafc29038eb9f77ff3` (== §1/§3 pin) |
| subject `git status --porcelain` | empty |
| subject Cargo.lock at end | absent (`ls`: No such file or directory) |
| d1 find-manifest post vs pre | `diff` empty — **post == pre** (93 files, sha256 of both files `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4`) |
| d2 find-manifest post vs pre | `diff` empty — **post == pre** (identical sha256 as d1's manifests) |
| d2 pre vs d1 pre | `diff` empty |
| Axiom4 `git status --porcelain` (end of run 4) | `?? experiments/serde-json-claim-2026-10-31/` + `?? gh_env.txt` — exactly the two expected untracked paths; no tracked file modified |

## ⑤ Lock protocol (per-run record)

Placed bytes: `$EXP/inputs/Cargo.lock` sha256 `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (== §4 pin).

| run | placed (in) sha256 | after run (out) sha256 | in==out | removed |
|---|---|---|---|---|
| d1 | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` | yes | yes (`rm`; post-manifest confirms absence) |
| d2 | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` | yes | yes |

No `rust_input_contract` lock failure line appeared in either stdout (the lane did not report lockfileDigest drift).

## ⑥ Deviations (complete list)

1. **Declared (§8) — lock placement**: Cargo.lock was placed in the subject for d1 and d2, verified in==out, then removed; subject manifests restored byte-identically (④). The subject is recorded as **"declared deviation, restored"**, not "untouched".
2. **Pre-registered (§9 Amendment 1) — probe exit 3 → proposition re-selection**: probe (run 3) exited 3 INVALID_INPUT(NotFound); the single stdout line is preserved verbatim in FREEZE.md §9.1; mechanical cause measured (2,134 fun_decls / 152 nameable / `is_f64` nameable = 0 / `parse_line_col` full-name matches = 1, lastSegment unique); §8's exit-3 "fix and re-run" row does not cover the unfixable case; C7 re-selected onto `serde_json::error::parse_line_col`. Pre-d1 mtime-order proof: `runs/pre_d1_amendment_timestamps.txt` (sha256 `bbb48ae273110932ee22c0fed374ec16531a67797327599c44faeed80778cb0b`) records FREEZE.md §9 write mtime **2026-10-31 20:28:47 +0900** < `axiom.specs.json` edit mtime **20:29:08** < `inputs/verification_scope.rust_targets.json` replacement mtime **20:29:14** < first d1 command (d1 start epoch 1793446239.155 = 20:30:39 +0900). The §6 tables were not modified (§9 appended only).
3. **Registration template replacement (§9.4)**: `inputs/verification_scope.rust_targets.json` content replaced is_f64→parse_line_col; the is_f64 entry was consumed by no run (target always passed on the command line; the file's content enters only the d1/d2 state locks). `axiom.specs.json` gained `serde_json::error::parse_line_col`, kept is_f64. signatureHash `48c4dc5b55757f7c444e8a6d0bf5fdaadd10f48791a6dea9df39484db7367851` recomputed from the error.rs:494 signature line — match.
4. **Deviation vs §9's NEW expected targets[0].reason (d1/d2)**: §9.2 predicted reason `out-of-subset grammar (fail-closed): <producer reason — predicted: signature Ref input / Adt output>`. Observed (both runs): `producer: LLBC files table pre-validation failed: files[1]: absolute path '…' (subject-relative POSIX path required)` — verbatim in ③. Matched predictions: exit 0; `targets[0].name` = `serde_json::error::parse_line_col`; `status` = `unknown`; `ledger transport armed (live)` line present. Not matched: the reason class. The signature gate / spec decode was never reached (no such output); the producer's files-table pre-validation refused the extraction earlier. Mapping per FREEZE §8/§9: none of the §8 judgment rows covers this observation class (it is not exit-3 INVALID_INPUT, not offline fetch failure, not charon timeout, not lock in≠out, not token refusal; the signature-accepted row also does not apply since no spec decode occurred). Recorded verbatim per §9's honesty rule; terminal adjudication is NOT claimed as the §6/§9-predicted SCOPE_LIMIT_CONFIRMED-on-signature-grounds.
5. **Axis-3 byte difference (d1 vs d2)**: canonical skReport payloads differ in exactly one hunk — the run-specific absolute path inside `targets[0].reason` (state dir name + charon-target hash). Recorded verbatim in ②; per the run-4 brief this is recorded as a deviation following the §8 `lock in≠out` row's discipline (record verbatim; no masking; no retry declared since §8's one-retry rows address offline/timeout, not this class). Related observed fact: §7's note that the skReport payload "carries no timestamps or paths" does not hold for this payload.

## ⑦ Landing record

- PR: **#1149** — state MERGED, mergedAt `2026-10-31T12:22:33Z` (`gh pr view 1149 --json state,mergedAt,mergeCommit`)
- merge commit.oid: `ee87f0a70a8a518e490c74499b5e134ef112ea08` (branch `repro/serde-json-claim-2026-10-31` HEAD == this commit at d3 execution)
- post-landing d3 (canonical reproduction at the pinned merge commit, state_d3/vault_d3, §9.3 command form): **executed 2026-10-31** on branch `repro/serde-json-claim-2026-10-31` (HEAD = merge commit `ee87f0a70a8a518e490c74499b5e134ef112ea08`); fresh `state_d3`/`vault_d3`, per-run lock protocol and find-manifests identical in form to d1/d2.

Observations (machine outputs verbatim):

- d3 exit code: **0**; wall 12.980 s
- stdout — all 3 lines, byte-identical to d1/d2's (sha256 `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d`):

```
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] done: verified=0/1 failed=0 unknown=1 error=0
```

- d3 `targets[0]` verbatim (full skReport payload preserved at runs/d3/skreport_payload.json; schemaVersion `axiom.report.v1`, subjectLane `rust`, charon ok=true pinned==measured `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)`, summary `{"failedCount":0,"statusCounts":{"error":0,"failed":0,"unknown":1,"verified":0},"timeoutCount":0,"verified":0,"verifiedRatio":0.0}`):

```json
{
  "name": "serde_json::error::parse_line_col",
  "reason": "producer: LLBC files table pre-validation failed: files[1]: absolute path '.4/experiments/serde-json-claim-2026-10-31/state_d3/.axiom/rust-lane/1398235db249fc8b/charon-target/x86_64-unknown-linux-gnu/debug/build/serde_json/4bceeb2bfd3e9415/out/private.rs' (subject-relative POSIX path required)",
  "status": "unknown"
}
```

- Three-axis reproduction verdict (FREEZE §7 axes vs d1):

| axis | d3 | verdict |
|---|---|---|
| ① exit code | 0 | **identical** |
| ② Cargo.lock sha256 in==out | `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` (in == out), removed after run | **identical** |
| ③ skReport semantic equality | `targets[0].name` = `serde_json::error::parse_line_col`, `status` = `unknown` — identical; reason same class (files-table pre-validation refusal); the only differing substrings are the run-relative state-dir name `state_d3` and charon-target build hash `4bceeb2bfd3e9415` inside the embedded absolute path — the announced displacement (⑥5) | **semantically identical** |

- State/vault/subject: `state_d3/data/verification_scope.lock` 6,383 B, sha256 `0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e` (identical to d1's/d2's); `state_d3/logs/ax_prove_trajectory.jsonl` present (929 B, 1 line); `vault_d3/` empty (no vault artifacts — same as d1/d2); d3 find-manifests pre == post (`diff` empty, both sha256 `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` — identical to d1/d2's manifests); subject HEAD `8c535a260ce561eaab4111aafc29038eb9f77ff3` unchanged; subject `git status --porcelain` empty; subject Cargo.lock absent at end.

**Canonical reproduction confirmed** — all three axes hold (① exit ② lock in==out ③ skReport semantically identical: name/status identical + reason same class; run-relative path/build-hash displacement inside the reason is the pre-announced normal for this reason class). No new deviation class observed.

d3 artifact sha256:

| file | sha256 |
|---|---|
| runs/d3/stdout.log | `9ddc5dbc7b104135a353c3144f1f466e3d7e10c1db7c6f6126f9c4bce59e298d` |
| runs/d3/subject_manifest_pre.sha256 | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| runs/d3/subject_manifest_post.sha256 | `b49abcb61cb93ebe496229360e648737f6e090c5ff094aa0558fe417715aaac4` |
| runs/d3/skreport_payload.json | `9bc2d1fcedab43e7ef4d75bc2544d92547b653d164122d1dfc44f4366160fa1f` |
| state_d3/logs/ax_prove_trajectory.jsonl | `d82c0e77962d4b4c20fde71514a031a3d0d97f49f686ee2472904b78ae678edc` (1 line) |
