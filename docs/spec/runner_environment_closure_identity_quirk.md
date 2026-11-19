# Runner Environment Enters the Judgment Closure — the executor must pin it, never inherit it

**Discovered**: 2026-11-18/19, 40 merge_group admission runs. Seven of the fourteen
failures were the same terminal error — `[check] Attest witness-only` refusing with
`decision file key <A> != freshly re-derived <B>` — on candidates whose subject tree
never changed.

**Quirk.** The judgment closure binds the **process environment of the executor**,
not only the subject. Two closure components read the ambient environment of
whichever process derives the key:

| component | source | predicate |
|---|---|---|
| ⑥ `envSnapshot` | `src/verification/judgment_cas.nim:577-603` | raw text of `PATH`, `TMPDIR`, `AXIOM_LEAN_CMD`, `AXIOM_IRCHECK_CMD`, `AXIOM_STATE_DIR`, `cwd` |
| ⑨ `executionConfig` | `src/verification/accounting/execution_context.nim:52-70` | canonicalized `AXIOM_LEAN_CMD`, `PATH`, `TMPDIR` |

Nothing else enters: `ImageOS`, `ImageVersion`, `RUNNER_*`, `GITHUB_*` are **not**
closure inputs. `cwd` is `getCurrentDir()` — for a step that never `cd`s, that is
`$GITHUB_WORKSPACE`, which is identical on every hosted runner.

GitHub-hosted runner images of different generations ship different base `PATH`
values. The plan stage and the attest stage run as **separate jobs**, so they can be
scheduled onto different image generations inside a single run:

```
run 44406900746:  job A provisioned under image 20261103.629
                  job B provisioned under image 20261111.635
                  -> component ⑥/⑨ differ -> K_plan != K_attest
```

Observed mapping (4 of 4 cases, direction reversing when the two jobs swapped
generations, which rules out a systematic job difference):

```
20261111.*  ->  key 5b65...
20261116.*  ->  key bc55...
```

The failure reproduces deterministically: runs `44406900746` and `44404601016`
produced the identical key pair `b9e1bb0c8321 != ba05d5cfe9fe`.

**Consequence.** Fail-closed behaves correctly — the attest stage refuses a decision
whose key it cannot re-derive. But the refusal is an **availability** defect, not a
soundness one: the same subject was judged twice under two different executor
identities. Re-running the workflow cannot fix it; nothing about the candidate
changed. The closure semantics were never wrong. The workflow simply never fixed the
environment the contract observes.

**Rule.**

1. **The executor pins the environment the closure binds.** Every block that derives
   or re-derives a judgment key must set `PATH`, `TMPDIR` and clear `AXIOM_LEAN_CMD`,
   `AXIOM_IRCHECK_CMD`, `AXIOM_STATE_DIR` to a constant before invoking `ax`. The
   pinned `PATH` is exactly the directories `setup-axiom-toolchain` exports for
   `provision-scope: full` on x86_64 — `$HOME/.local/bin`, `$HOME/.elan/bin`,
   `$HOME/.nimble/bin` (appended last-to-first, so `.local/bin` has priority) —
   followed by the FHS set:

   ```bash
   export PATH="$HOME/.local/bin:$HOME/.elan/bin:$HOME/.nimble/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
   export TMPDIR=""
   unset AXIOM_LEAN_CMD AXIOM_IRCHECK_CMD AXIOM_STATE_DIR
   ```

   The image-only directories (`/opt/pipx_bin`, `~/.cargo/bin`,
   `/usr/local/.ghcup/bin`, `~/.dotnet/tools`, `/snap/bin`) carry no tool these
   blocks invoke, so dropping them changes nothing the closure is asked to model.

2. **Do not remove `PATH`/`TMPDIR`/`cwd` from the closure to make two environments
   agree.** The closure is over the observed environment by contract; dropping an
   input would move the key scheme, not repair it. The single permitted direction is
   to make the observation deterministic.

3. **`cwd` is a closure input.** Two steps that derive the same key must run with the
   same working directory. The admission blocks never `cd`, so both sides observe
   `$GITHUB_WORKSPACE`; a step that changed directory before deriving would fork the
   key. The same applies to a different checkout root (`_candidate/`): the H tree is
   a *data* path and must never be the executor's `cwd` when a closure is derived.

4. **Cache correctness is not closure identity.** A restored toolchain cache can make
   two jobs fast; it does not make their environments equal. The pin is what makes
   them equal.

**Fix**: PR #199 (`1eaede8`) — the pin inserted at the three blocks that derive or
re-derive a key (`[lane] Judgment CAS plan`, `[check] Attest witness-only`,
`[lane] GO-critical admission tests`), plus the callee-ref rotation so
`admission-gate-v2.yml` actually calls the pinned `admission-check.yml` commit.

**Cross-references**: `docs/spec/canonical_execution_semantics.md` (the ⑨ contract),
`docs/spec/execution_accounting_contract.md` (⑨'s consumer),
`docs/spec/admission_workspace_pollution_quirk.md` (the sibling rule: landing gates
judge trees, never the executor CWD).