Investigation complete. All five tasks verified with code and command evidence.

## (a) STAGING VERDICT — YES, a modified tracked file IS swept in

`src/gate/gateway.nim`:
- `:142-151` `stageFiles` → per named file: `runGit("add " & quoteShell(f))` — individual `git add`, nothing else.
- `:342` `discard runGit("add -u")` — **unconditional, after `stageFiles`, no pathspec** → stages every modified/deleted **tracked** file in the whole repo.
- `:153-158` `hasStagedChanges` — read-only (`git diff --cached --name-only`).
- `:450` `runGit("commit --no-verify -m …")` — no pathspec → commits the whole index.

Isolated `/tmp` scratch-repo proof (repo deleted afterwards):

```
status before:  M tracked_a.nim  M tracked_b.nim  ?? untracked_new.nim
after git add tracked_a.nim:  M  tracked_a.nim   M tracked_b.nim   ?? untracked_new.nim
after git add -u:             M  tracked_a.nim   M  tracked_b.nim  ?? untracked_new.nim
git diff --cached --name-only -> tracked_a.nim, tracked_b.nim
```

(a) named files added individually ✔ (b) `add -u` sweeps all dirty tracked files ✔ (c) untracked never swept unless named ✔.
**Answer: YES** — a modified tracked `src/cli/axiom_engine.nim` is included in that commit even if it is not named on the command line.

## (b) GATE-SIDE-EFFECT VERDICT — the 3-commit sequence is NOT safe as written

`Makefile:977-979` `test:` → `Makefile:981-984` `perf-check:` → `nim c -r tools/perf_measure.nim latest` → writes **`data/benchmarks/perf_latest.json`** (`tools/perf_measure.nim:22,136,152`).

That path is **tracked** (`git ls-files data/benchmarks/` lists it) and **not ignored** (`git check-ignore` exit 1), and its content changes on every run: `provenance.generatedAt` = `format(now().utc, …)` (`perf_measure.nim:128`) plus `provenance.commit` = HEAD (`:152`). It is already stale: pinned `ecb0fe8d…` vs HEAD `0b2564b27…`.

Safe (ignored/untracked): `build/` (`.gitignore:27`), `.nimcache/` (`:249`), `logs/*` (`:95`), `.axiom/*` — `git ls-files build .nimcache logs` returns empty.

Also tracked: `data/feature_manifest.json` — written **and `git add`ed** by `src/gate/runners/gate_hook.nim:341-342`, but only when a `.feature` file is in the staged set. The four pre-commit-lane gates (`topology_spec.nim` `skPreCommit` at `:21`, `:413`, `:482`, `:633`) write nothing; `unstaged-guard` is `skManual` (`topology_spec.nim:696`) so it does not block a dirty `data/` file.

**Ordering is the trap**: the sweep at `:342` (Phase 2) runs **before** `make test` (Phase 2c, `:359`). So commit 1 is clean, but commit 1's gate run leaves `data/benchmarks/perf_latest.json` dirty in the worktree — commit 2's `:342` sweep then pulls that churn into commit 2, and commit 3 sweeps it again (different blob each time). Pollution is **silent** (no scope gate in the pre-commit lane; `trust-commit-scope` is `skManual`).

Mitigation to bake in: `git restore data/benchmarks/perf_latest.json` after each gated commit (before the next), and confirm `git status --porcelain` shows no modified tracked file before each commit.

## (c) TWO PIN KINDS — measured (nim-libp2p)

| kind | value |
|---|---|
| content sha256 | `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` ✔ matches expected |
| git blob OID | `621e111d53fd07b4e2eeeb2410a1cd6c05719159` (different 40-hex) |
| HEAD commit | `a130a7f32219909bdcda14b7f1e64d0804fc832c` |
| HEAD tree | `ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841` ✔ matches expected |

`git rev-parse --show-object-format` → `sha1`; `git hash-object libp2p/utils/bytesview.nim` → `621e111d…` (same as the blob OID, so both pins address the same bytes). git OID ≠ content sha256 → **two separate pin kinds must be recorded**. The new overlay already does this: `subject.commit` = `a130a7f32…` + `subject.blobSha256` = `b205c969…`, and states the distinction in `semanticCaveats` (line 50).

## (d) d2 OVERLAY PIN — INFORMATIONAL (format-only), no content enforcement

`validateD2SubjectPin` (`src/cli/axiom_engine.nim:1518-1542`) requires `repository`/`commit`/`sourceLines` non-empty and `blobSha256` to be 64-hex (`:1538-1541`). It **never reads the subject file and never hashes it**; the returned tuple doesn't even carry the blob. The repo says so itself:
- `:2184-2185` — “The REAL subject-pin check (the d2 lane only format-checks the blob digest)”
- `:4162-4165` — “The sidecar's subject pin is a REAL check (unlike the d2 lane's format-only blob check)”

The enforcing pattern (sidecar lane) `verifySidecarSubjectPin` `:2181-2208`: `readFile(moduleAbs)` → `sha256Hex(bytes)` → compare to `domain.adoption.subject.blobSha256`, fail-closed; call site `:4166-4175`. A reusable pure classifier exists too: `classifySubjectScope` (`src/cli/verdict_display.nim:186-197`) requires `probe.commit == pinnedCommit` **and** `probe.blob == pinnedBlob` for `scopeVerifiedMatch` — but it is applied in the bug-attribution lane (`axiom_engine.nim:2266-2269`), **not** in the d2 loader. `bug_attribution_grounds.nim:213-218` only cross-checks two records (`grounds.moduleSha256` vs `spec.subject.blobSha256`), not the subject tree.

⇒ **A libp2p overlay loader cloned from the d2 pattern gets no pin enforcement for free** — it must add an explicit `readFile`+`sha256Hex` comparison (sidecar style) or reuse `classifySubjectScope` + `probeSubjectIdentity`.

Two verified side notes: (1) `loadTomlD2AgentOverlayDomain` `:1624-1635` ends with `validateTomlD2AgentOverlayNode(nodeOpt.get)` as the proc's last expression, and Nim's implicit last-expression return makes it the return value — I confirmed this empirically with Nim 2.2.10 and the project's own `Result` (`src/core/types/results.nim`, default `ok=false`), so shape/pin-format errors *do* propagate; the gap is content only. (2) The new libp2p overlay has 4 `canonicalSpecIR` clauses while the d2 validator demands exactly 9 (`:1656-1659`), so a separate loader is genuinely required.

## (e) REPO STATE

- **Axiom** — branch `followup/libp2p-bytesview-slice`, HEAD `0b2564b270d305ff497b129bfc84d06ba66fef3c` (== `origin/main`, 0 commits ahead, tracking `origin/main`). HEAD moved during the session from the `16ca2ea0e` in your brief to this newer main tip. **Not clean**: one untracked file appeared mid-investigation — `?? config/spec/nim_libp2p_bytesview_slice.json` (the new 61-line overlay). No tracked file is modified.
- **nim-libp2p** — clean; `a130a7f32 refactor(transport): retry recoverable accept failures internally (#3313)`.

No repository was mutated; both `/tmp` scratch repos were removed.