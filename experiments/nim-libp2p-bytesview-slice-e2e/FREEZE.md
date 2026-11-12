# FROZEN acceptance run — nim-libp2p `BytesView.toOpenArray` slice-length (SPEC-LIBP2P-BV-SLICE)

> **Status**: FROZEN before the first judged execution. This file records the identity,
> pins, expected outcomes, and the judgment table for the libp2p bytesview slice end-to-end
> acceptance run. No run output may alter these records; deviations are reported as-is in
> `ACCEPTANCE.md`.
> **Created**: 2026-10-22 (freeze date; run day = **2026-10-22** — the canonical d1/d2 legs ran 20:51:19–20:51:36 KST)
> **Contract**: [docs/spec/nim_libp2p_bytesview_slice_contract.md](../../../docs/spec/nim_libp2p_bytesview_slice_contract.md) (committed on branch `followup/libp2p-bytesview-slice`, commit `98b8b7069`)
> **Overlay**: `config/spec/nim_libp2p_bytesview_slice.json` — `SPEC-LIBP2P-BV-SLICE`, `soExplicit`
> **Related precedent**: [nim_stew_base36_cout_slice_2026-10-10.md](../../../docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md) (C_out authority + attach precedent) · [sidecar-adoption-e2e](../sidecar-adoption-e2e/ACCEPTANCE.md) (external-subject lane precedent)
> **Discovery chain**: [`discovery/INDEX.md`](./discovery/INDEX.md) — 15 verbatim session records, sha256-pinned

## 1. Build identity (Axiom side)

| item | value |
|---|---|
| branch | `main` (PR-A — the code PR — **landed**; PR #1043, merged 2026-10-22T09:58:24Z) |
| HEAD commit | `801a12be69f7f82f6792e31ccc5757cbc7a48364` — PR #1043 merge, a **GitHub native MERGE commit, 2 parents** (`6e45b7167` + `efde23cc4`); required checks 5/5 PASS; merge-queue admission-gate group run `39757132531` success; landing observed TERMINAL_SUCCESS |
| `AXIOM_REVISION` (the runs' revision) | the merged main commit `801a12be6`, containing `98b8b7069` (contract) → `7d8856dd5` (feature) → `6da2f8792` (P4 carve-out fix) → `caa678c23` (rotation) → `efde23cc4` (policy-mirror sync) |
| branch candidate (pre-merge) | `caa678c23dc9b2cbef6cbc7d65edcd49bdec8d5f` — `rotation: re-anchor trustedCheckerTreeClosure for the libp2p bytesview slice (6da2f8792)` |
| commit chain (candidate) | `caa678c23` (rotation) ← `6da2f8792` (P4 disproof carve-out) ← `7d8856dd5` (engine wiring + unit test) ← `98b8b7069` (contract + overlay) ← base `0b2564b270d305ff497b129bfc84d06ba66fef3c` |
| base pin | `0b2564b270d305ff497b129bfc84d06ba66fef3c` — `Merge pull request #1040 from Archright/feat/operational-slice` (this was `origin/main` at branch creation) |
| `bin/ax` sha256 | `750986c54feb8ed93e425c484d61660a7c6619353fc0daf602247c831fc3cc18` (`sha256sum bin/ax` on the run binary) |
| build cmd | the 4-step hermetic sequence, from the canonical main `801a12be6`: `bin/hermetic_build --materialize` → `nim c -d:release --hints:off -o:bin/ax src/cli/main.nim` → `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-5903230338753693627)` |
| Nim | Nim Compiler Version 2.2.10 [Linux: amd64] |
| Lean | Lean 4.33.0 (`leanprover/lean4:v4.33.0`) |
| Z3 | Z3 version 4.13.3 - 64 bit |
| SourceCoherence | `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK` (embedded `BuildSourceHash` == live `src/**/*.nim` tree hash). A stale binary **cannot** produce a proof — it exits 1 at startup. |
| engineBuild | certificate `toolchainIdentity.engineBuild` must be a 64-hex id (**not** `"unmeasured"`); `"unmeasured"` ⇒ the certificate is not admissible (`cert_reconcile.nim` fails closed). |
| tracked tree | `git status --porcelain` EMPTY at freeze — measured on the canonical main `801a12be6`: the tracked tree is clean (`git status --porcelain --untracked-files=no` EMPTY); the only entries are this experiment's own untracked records |

## 2. Subject pin (Zero-Footprint — READ-ONLY)

| item | value |
|---|---|
| repo | `status-im/nim-libp2p` — local READ-ONLY clone `<workspace>/nim-libp2p`; origin `iftech/nim-libp2p`, a fork of `status-im/nim-libp2p` |
| commit | `a130a7f32219909bdcda14b7f1e64d0804fc832c` |
| tree | `ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841` |
| governed module | `libp2p/utils/bytesview.nim` (22 lines, zero imports) |
| module blob sha256 | `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` |
| git blob OID | `621e111d53fd07b4e2eeeb2410a1cd6c05719159` — a **different hash kind** (SHA-1 over the repo object graph); recorded separately from the content sha256 |
| governed symbol | `toOpenArray` — a **template** (`:18-19`), not a materializable `func` |
| template body | `v.data.toOpenArray(v.rpos + b, v.rpos + e - b)` → inclusive interval `[rpos+b, rpos+e-b]`, length `e - 2b + 1` |
| clone used | `<workspace>/nim-libp2p` — the run's own `sourceRoot=` (d1/d2 stderr line 3). **The mode-bit write-protection expected at freeze was NOT in force for this slice**: the clone carries `0775`/`0664` (owner-writable) and no `chmod` occurred inside the run window (`ctime` 2026-10-22 16:34 < the 20:51 run), so no `touch` probe was made — it would have written. The Zero-Footprint claim rests on the measured pins, the empty porcelain, the tree mtime census and the in-run fold instead ([INTEGRITY.md](./INTEGRITY.md); ACCEPTANCE.md §7). |
| write protection | the tree is READ-ONLY for the WHOLE run (expected; the mode-bit enforcement did not hold for this slice — see `clone used` above and ACCEPTANCE.md §7); any write attempt = integrity FAIL |
| porcelain | `git -C <subject> status --porcelain` must be EMPTY at every stage (pre-run, at replay time, post-run) — measured **empty** pre-run, at replay time (`replay.porcelainClean=true`) and post-run |

## 3. Spec overlay pin (Axiom-owned; Zero-Footprint; repo-root anchored)

| item | value |
|---|---|
| file | `config/spec/nim_libp2p_bytesview_slice.json` |
| file sha256 | `7de9cd3a1de3c0027e0e6542a8b029982492dfae084381e5b40d956fc890e293` (`sha256sum config/spec/nim_libp2p_bytesview_slice.json` as committed) |
| specId | `SPEC-LIBP2P-BV-SLICE` |
| ruleId / ruleVersion | `external:libp2p/bytesview/slice-length-law` / `1.0.0` |
| specOrigin | `soExplicit` (pinned by `explicitSpecFromOverlay`; any other origin fails closed) |
| subject pin inside the overlay | `commit a130a7f32…`, `blobSha256 b205c969…`, `module libp2p/utils/bytesview.nim`, `symbols ["toOpenArray"]`, `sourceLines "18-19"` |
| canonicalSpecIR (6 clauses) | `1 <= e` · `e <= 5` · `bvSliceLenLaw1(e) == e` · `bvSliceLenActual(e) == (e - 1)` · `bvSliceLenLaw0(e) == (e + 1)` · `bvSliceLenControl(e) == (e + 1)` |
| clause grammar | **CLOSED**: a definition body is `<var>`, `<var> + <INT>` or `<var> - <INT>` (optionally one parenthesis pair); a clause count other than the six above is rejected fail-closed |
| carriers | defect `bvSliceLenActual` (b pinned at 1, model `e-1`) · control `bvSliceLenControl` (b pinned at 0, model `e+1`) — both **CONSTRUCTED IR** (the subject is a template) |
| law authority | the law **bodies** are DATA in `canonicalSpecIR`; the engine hardcodes no law content (only the carrier/law NAMES are binding identities) |

## 4. Engine lane pin

| item | value |
|---|---|
| lane | bytesview slice lane in `src/cli/axiom_engine.nim` (+736 lines, commit `7d8856dd5`) |
| overlay path const | `NimLibp2pBytesviewSliceOverlayPath*` = `repoRootConst() / "config" / "spec" / "nim_libp2p_bytesview_slice.json"` |
| carrier / law names | `bvSliceLenActual` · `bvSliceLenControl` · `bvSliceLenLaw1` · `bvSliceLenLaw0` |
| loader / validator | `loadNimLibp2pBytesviewSliceOverlayDomain()` · `validateNimLibp2pBytesviewSliceOverlayNode()` — presence-**optional** (absent ⇒ explicit inert line), present-but-malformed ⇒ fail-closed `err(...)` |
| subject pin check | `verifyLibp2pBytesviewSubjectPin()` — a **REAL** check: the governed module's bytes under the run's subject root must hash to `subject.blobSha256` (the d2 lane only format-checks the digest) |
| eligibility | `overlayDeclaresLibp2pBytesviewSubject()` — module path + subject symbol **or** a constructed carrier name; inert for every other subject tree |
| target routing | `libp2pBytesviewCarrierTargetRouting()` — canonical `--target libp2p/utils/bytesview.nim::toOpenArray` (canonical) or the bare carrier name |
| synthesizer | `synthesizeNimLibp2pBytesviewSliceCandidate()` — one model parameter `e`; body = the overlay's model; pre = the domain conjuncts; the claim `model == law` is β-spliced onto the `result` slot exactly once (free-variable guard fail-closed) |
| replay harness | `BvSliceLenReplayHarnessTemplate*` — stamped harness importing `libp2p/utils/bytesview` and echoing `$(bv.toOpenArray(1, <lit>).len)` between the `AXIOM_REPLAY_BEGIN` / `AXIOM_REPLAY_END` markers; compiled OUT OF TREE (scratch nimcache + outdir) |
| P4 carve-out fix | `src/verification/batch_uap/loop_driver.nim` (commit `6da2f8792`) — a fatal pre-sieve block must not swallow a P4-promoted, replay-confirmed disproof; `if cached.blocked and not disproofCarveOut:` |

## 5. Expected outcomes (frozen before execution)

| leg | expected machine observation |
|---|---|
| defect run (`bin/ax prove --project <subject-abs> --target "libp2p/utils/bytesview.nim::toOpenArray"`, fresh `state_d1`/`vault_d1`) | overlay accepted; **BOTH** carriers synthesized (defect `bvSliceLenActual` wave-faced under the examined symbol `toOpenArray`, control `bvSliceLenControl` under its own name); defect solver SAT (model binds one `e` in `1..5`) → P4 `cvConfirmed` → `vsDisproved` → replay compiles the stamped harness OUT OF TREE, observes the ORIGINAL template's length, `propertyHolds == false` → `replay.verdict=rvAgree` → BUG_FOUND payload → node `failed` → **exit 1** |
| `[ce-replay]` stderr line | `[INFO] ir_pipeline_runner: [ce-replay] bvSliceLenActual — replay agreed; BUG_FOUND payload assembled (13 records)` — **verified in the run**: the engine printed exactly this line in both legs (d1/d2 stderr line 32, byte-identical); the printed carrier `bvSliceLenActual` is the synthesizer's `funcDef.name` |
| payload (13 records) | `input.e=<lit>` · `propertyViolated=<SMT>` · `replay.verdict=rvAgree` · `replay.exitCode=0` · `replay.subjectGitRef=a130a7f32219909bdcda14b7f1e64d0804fc832c` · `replay.treeMerkle=ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841` · `replay.moduleSha256=b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` · `replay.moduleSha256AfterRun=` (equal to the above) · `replay.porcelainClean=true` · `replay.nimVersion=Nim Compiler Version 2.2.10 [Linux: amd64]` · `replay.nimHash=<sha>` · `replay.stdlibHash=` · `replay.hostPlatform=linux-amd64` |
| trajectory claim row | `unitEvidenceRefs["libp2p/utils/bytesview.nim::toOpenArray"].claimOutcome = clDisproved` with the **13-record** `counterExample` payload (the payload's canonical home: `axiom_engine.nim` → `reportJson["unitEvidenceRefs"]`; the trajectory's claim map carries it) |
| manifest rows | `toOpenArray` ⇒ `certRed` (psFail) · `bvSliceLenControl` ⇒ `certZ3Candidate` (**no** `certRed`) |
| summary / exit | `summary.failedCount = 1` · `runOutcome.verdict = FAIL` · `gateVerdict = FAIL` · process exit **1** (`cli_outcome.nim` — `VERIFICATION_FAILURE`: ≥1 failed node) |
| cold rerun (fresh `state_d2`/`vault_d2`, identical command) | identical canonical projections; `canonicalRunDigest` (state logs) EQUAL to run d1 **and** payload-level byte equality (claim map + evidence CAS) |
| control (in-run; both carriers synthesize under the single governed `toOpenArray` hit) | control carrier solver **UNSAT** (injection guard) — read from the trajectory/manifest rows of the same run; `--target` isolation of the control carrier alone is NOT assumed |
| control leg semantics | the control is a **solver-level injection guard**, NOT a subject observation — the subject is **never executed** for it (the subject is compiled and run only on a P4-promoted disproof) |
| subject integrity | full-file sha256 manifest of the subject clone identical pre↔post (byte-for-byte); `git rev-parse HEAD` / `HEAD^{tree}` unchanged; porcelain empty at both ends |
| determinism | `canonicalRunDigest` d1 == d2 (MATCH) — with the honest scope caveat in §8 |

## 6. Judgment table (frozen before execution)

| observation | verdict |
|---|---|
| defect observed end-to-end (SAT → replay agreement → BUG_FOUND payload, exit 1, subject untouched) | **PASS** |
| adapter-only: the lane loads/synthesizes but no replayed subject execution behind the verdict | **INCOMPLETE** |
| control false-positive: control carrier SAT (injection guard fails) | **FAIL** |
| template swallow: the node terminates `PRE-SIEVED` instead of `failed` (the defect is invisible to the exit rule) | **FAIL** |
| digest change: any byte of the subject clone differs pre↔post (or pin/blob sha mismatch) | **FAIL** |

## 7. Frozen execution procedure (the command sequence is part of the freeze)

1. Pre manifest: `cd <subject> && find . -path ./.git -prune -o -type f -print | sort | xargs sha256sum > <exp>/runs/subject_tree_pre.sha256`; record `git rev-parse HEAD`, `git rev-parse HEAD^{tree}`, `git status --porcelain`, and the manifest file's own sha256.
2. Defect leg d1: `mkdir -p <exp>/state_d1/data && cp data/verification_scope.lock <exp>/state_d1/data/` (the engine resolves the scope lock under `AXIOM_STATE_DIR` first — `AXIOM_STATE_DIR` is **mandatory** with `--project`, fail-closed), then `AXIOM_STATE_DIR=<exp>/state_d1 AXIOM_PROVE_VAULT_DIR=<exp>/vault_d1 bin/ax prove --project <subject-abs> --target "libp2p/utils/bytesview.nim::toOpenArray"`; capture stdout/stderr/exit.
3. Defect leg d2 (COLD): fresh `state_d2`/`vault_d2`, seeded the same way, identical command.
4. Control evidence: extracted from the SAME runs' trajectory/manifest rows (control carrier under its own name).
5. Post manifest: same as step 1 → `runs/subject_tree_post.sha256`; byte compare; `INTEGRITY.md`.
6. Determinism: compare `canonicalRunDigest` d1 vs d2 **and** the payload-level projections (claim map + evidence CAS).
7. `ACCEPTANCE.md` verdict; logs preserved under `runs/`.

## 8. Honesty caveats (recorded at freeze — apply to every verdict below)

1. **The digest covers run-accounting SHAPE, not payload bytes.** `canonicalRunDigest` /
   `runAccountingDigest` / `runOutcomeDigest` are `sha256Hex(canonicalSerialize(runResult))` over
   waves/terminals/counts. They are byte-identical for the 2026-10-10 C_out slice, the
   2026-10-19 sidecar slice and any other run of the same shape. A digest MATCH therefore
   establishes **shape** equality, never payload identity.
2. **Payload-level equality is established separately**, through the trajectory claim map
   (`unitEvidenceRefs[…].counterExample`) and the evidence CAS files (`<state>/.axiom/cache/evidence/*.json`)
   compared byte-for-byte between d1 and d2. This comparison is part of the frozen procedure
   (§7 step 6), not an optional extra.
3. **Determinism scope = the same FIXED environment.** Both cold runs use the same pinned Nim
   2.2.10 toolchain, the same local nimble `pkgs2` store, the same `bin/ax` bytes, the same
   subject tree, and the same environment. Nothing here claims cross-machine, cross-toolchain or
   cross-subject determinism.
4. **The solver verifies the ADOPTED MODEL, not the subject.** The carriers are CONSTRUCTED IR;
   the subject's connection to the verdict is the stamped replay harness observation only
   (the same model↔original gap the d2 lane documents).
5. **The control is a solver-level injection guard.** Its UNSAT is an affirmative solver result
   about the injected model + pre/post; it is not a subject observation, and the subject is never
   executed for it.
6. **The claim is not an autonomous discovery.** The law's justification (Nim's official inclusive
   `toOpenArray` semantics + the production call-site requirements) was established by external
   investigation and adopted by an explicit, user-approved act. The content was authored by the
   investigation agent chain; **authorship confers no authority**.
