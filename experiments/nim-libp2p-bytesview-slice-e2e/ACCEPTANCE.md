# ACCEPTANCE — nim-libp2p `BytesView.toOpenArray` slice-length defect (SPEC-LIBP2P-BV-SLICE)

> **Status**: MEASURED — the frozen expectations and the known facts were filled in at freeze; the
> canonical d1/d2 run results below are extracted from the captured run artifacts (§8).
> **Created**: 2026-10-22 (skeleton) · **Run date**: 2026-10-22 (d1 20:51:19–20:51:28 KST · d2 20:51:29–20:51:36 KST)
> **Freeze**: [FREEZE.md](./FREEZE.md) (written BEFORE the first judged execution) · **Integrity**: [INTEGRITY.md](./INTEGRITY.md)
> **Command under judgment**: `AXIOM_STATE_DIR=<exp>/state_dN AXIOM_PROVE_VAULT_DIR=<exp>/vault_dN bin/ax prove --project <subject-abs> --target "libp2p/utils/bytesview.nim::toOpenArray"` (COLD each leg; scope lock seeded into `<state>/data/` from the COMMITTED `data/verification_scope.lock`)
> **Build identity**: HEAD `801a12be69f7f82f6792e31ccc5757cbc7a48364` (PR #1043 merge — native 2-parent MERGE, parents `6e45b7167` + `efde23cc4`; branch candidate `caa678c23dc9b2cbef6cbc7d65edcd49bdec8d5f`, base `0b2564b270d305ff497b129bfc84d06ba66fef3c`) · `bin/ax` sha256 `750986c54feb8ed93e425c484d61660a7c6619353fc0daf602247c831fc3cc18` · Nim 2.2.10 · Lean 4.33.0 · Z3 4.13.3
> **Subject**: `status-im/nim-libp2p` @ `a130a7f32219909bdcda14b7f1e64d0804fc832c` (tree `ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841`), module `libp2p/utils/bytesview.nim` blob sha256 `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee`
> **Discovery chain**: [`discovery/INDEX.md`](./discovery/INDEX.md) — 15 verbatim session records (sha256-pinned)

## 1. Verdict table (frozen judgments of FREEZE §6, measured)

| frozen question | measured | verdict |
|---|---|---|
| defect replay agreed? | `[ce-replay] bvSliceLenActual — replay agreed; BUG_FOUND payload assembled (13 records)` (d1 stderr line 32; d2 line 32 byte-identical) · node `libp2p/utils/bytesview.nim::toOpenArray — failed` · `runOutcome.verdict=FAIL`, `gateVerdict=FAIL` · **exit 1** (VERIFICATION_FAILURE) | **YES** |
| control unproven (UNSAT guard)? | control carrier present and routed (see §3); NO counterexample, NO SAT: `bvSliceLenControl` absent from all 4 IR-pipeline FAIL rows and present among the 2 **Pass** rows, vault row `certZ3Candidate` (no `certRed`) | **YES** |
| template not swallowed by the pre-sieve? | the node is `failed`, **not** `pre-sieved` — `statusCounts.failed=1`, `statusCounts.pre_sieved=0`, node report `status: failed`; the P4 disproof carve-out (`loop_driver.nim`, commit `6da2f8792`) is in the run's build | **YES** |
| subject untouched? | pre/post full-file manifests byte-identical (641 files, manifest sha256 `85c39af3dd8f1c06da29ca39aab2ffce78b6dfcf685c849448da22f6f3163bd4` both ends), HEAD/tree unchanged, porcelain clean both ends ([INTEGRITY.md](./INTEGRITY.md)) | **YES** |
| determinism match? | `canonicalRunDigest` d1 == d2 == `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590` — **MATCH**; see §5 for the full byte-equality set | **MATCH** |

**Judgment (frozen table): defect observed end-to-end → PASS.** None of the FAIL/INCOMPLETE rows triggered: no adapter-only verdict (the stamped harness was compiled against the subject's own template and the **observation** disagreed with the adopted law), no control SAT, no template swallow (the node is `failed`, not `pre-sieved`), no subject digest change.

## 2. Defect leg — machine record (d1; d2 byte-agrees)

- Command exit: **1** (both legs) — captured at run time; the preserved artifacts carry the verdict that produced it (`runOutcome.verdict=FAIL` + `summary.failedCount=1` ⇒ `cli_outcome.nim` → `VERIFICATION_FAILURE`).
- Lane routing: `[INFO] axiom_engine: nim-libp2p bytesview slice carriers synthesized: bvSliceLenActual (model (bvsub e:BitVec 64 1)) + bvSliceLenControl (model (bvadd e:BitVec 64 1)) domain=1<=e<=5 obligations=3/3 eligible=true/true source=libp2p/utils/bytesview.nim` (d1 stderr line 5; d2 identical).
- `[ce-replay]` line **verbatim**: `[INFO] ir_pipeline_runner: [ce-replay] bvSliceLenActual — replay agreed; BUG_FOUND payload assembled (13 records)` — confirmed from the run: the engine printed exactly this line in **both** legs (d1/d2 stderr line 32, byte-identical); the printed carrier `bvSliceLenActual` is the synthesizer's `funcDef.name`.
- Claim row (`libp2p/utils/bytesview.nim::toOpenArray`): `claimId=fd6286fef96b33aa56a15176a292a8f3bd5d545cf37df149a918b0a9678eee79` · `claimOutcome=clDisproved` · `evidenceId=c615690c1ad7e46f04c438f280329564d5eefff65ec633e2702ddd2bba492867` · `obligationId=obl:d2c44f569ef61e349a915582c4237b1b747df4d30a4701712178655bdd5bc44e` · `specificationId=697f2bda4207b53db8ef36f2d8fa088877d0e9c74956718ce795d2b8631c1a4f` · `counterExample` = the 13-record payload below.
- Payload location: `reportJson["unitEvidenceRefs"]["libp2p/utils/bytesview.nim::toOpenArray"]["counterExample"]` (the trajectory's claim map — the canonical home of the payload; there is **no** certificate file carrying a `counterExample` in the Nim lane).
- Counterexample payload — all **13 records** verbatim (identical bytes in d1 and d2):
  1. `input.e=4` — the concrete witness the solver bound (in the domain `1..5`; at `e = 4` the model's length is 3 while the law demands 4)
  2. `propertyViolated=(= result e)` — the SMT projection of the spliced claim `result == e` with `result := e - 1`
  3. `replay.verdict=rvAgree` (`propertyHolds == false` — the replayed call observed the template's actual length)
  4. `replay.exitCode=0`
  5. `replay.subjectGitRef=a130a7f32219909bdcda14b7f1e64d0804fc832c`
  6. `replay.treeMerkle=ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841`
  7. `replay.moduleSha256=b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee`
  8. `replay.moduleSha256AfterRun=b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee`
  9. `replay.porcelainClean=true`
  10. `replay.nimVersion=Nim Compiler Version 2.2.10 [Linux: amd64]`
  11. `replay.nimHash=d955005687bea4d3ca6c5813792789987405343a1e8b8c0a8b3a22b9c23936cf`
  12. `replay.stdlibHash=`
  13. `replay.hostPlatform=linux-amd64`
- Replay call shape: `bv.toOpenArray(1, 4)` on `BytesView.init(@[byte 1, 2, 3, 4, 5, 6])` (rpos = 0) — the stamped harness imports `libp2p/utils/bytesview` and the template's symbols bind from the defining module, so the observed arithmetic is the **subject's own**, not a re-implementation. The observation (3), not the model, decides the agreement.
- stdout of both legs: 0 bytes — the report projected to the state logs + stderr (the sidecar precedent's shape); this slice preserved no stdout file, so the empty stdout is asserted by the capture layout (every console line of both legs is in the stderr logs) and not by a preserved empty artifact.
- Logs: `runs/d1_stderr.log`, `runs/d2_stderr.log`; state dirs `state_d1/`, `state_d2/`, vaults `vault_d1/`, `vault_d2/` (gitignored).

## 3. Control leg — in-run control evidence (recorded per FREEZE §5 fallback)

`--target` cannot isolate the control carrier alone: the lane synthesizes BOTH carriers under the single governed `toOpenArray` hit (contract §3.1 — the defect carrier is wave-faced under the examined symbol, the control rides its own name). Isolation was NOT attempted; the in-run control evidence is:

- Routing: control carrier present, eligible — `+ bvSliceLenControl (model (bvadd e:BitVec 64 1)) domain=1<=e<=5 obligations=3/3 eligible=true/true source=libp2p/utils/bytesview.nim` (the same synthesis line as the defect carrier, d1/d2 stderr line 5).
- Canonical leg: `[WARN] ir_pipeline_runner: [canonical-declined] bvSliceLenControl — evidence=inconclusive sealError=subject binding: parse-bound components unmeasured at the selection boundary (pnodeV2/extraction agreement: EA_INTERNAL_ERROR: func 'toOpenArray' not found in source)` → falls through to the BMC lane (the freeze's fall-through branch; the sidecar precedent's `[dual-declined]` form is the other arm of the same fallback).
- BMC lane: control is in the IR batch (Total 6) and is NOT among the 4 FAIL rows (`calcDynamicTimeoutCore`, `safeSpeedupRatioCore`, `proximityScore`, `toOpenArray`) — it is among the 2 **Pass** rows, and the control's claim row carries **no** `counterExample` (`claimOutcome=clProved`, `claimId=60749817637dc2488ba31013ce2e5182b515d99808b63a89eefb332ac92b3b81`, `specificationId=ca654ecfc38d6cfac0431f1208268922d1dc5d0f329c60bb1649c12ccb08d542`) — i.e. **no counterexample** for `bvSliceLenControl(e) == bvSliceLenLaw0(e)` (the model `e + 1` equals the law `e + 1` for every `e`); a control SAT would have surfaced exactly like the defect leg (payload + FAIL row) and would have triggered the frozen FAIL row.
- Vault manifest row (both vaults): `{"modulePath":"libp2p/utils/bytesview.nim","functionName":"bvSliceLenControl","status":"certZ3Candidate","solverMethod":"smCLI","irHash":"9ce83016bc32b7a0ff4701ddeb04df4982b7cce8f293c569f935d05cccdda2b4",…}` — **no** `certRed`.
- Evidence CAS for the control carrier: `state_d1/.axiom/cache/evidence/def77a7695c4ccd3ba4ff2081fdc6dd19c09b89da9696371ce1757f2c7c8c572.{json,binding.json,strict-gen}` — the IR-pipeline CAS key of the control carrier (stderr: `[ir-cas] MISS func=bvSliceLenControl key=def77a769…`); byte-identical across d1/d2 (all 10 CAS files of the two legs compare equal).

**Injection guard held: control UNSAT (unproven, as expected).** The control is a **solver-level injection guard, not a subject observation** — the subject is never executed for it (the subject is compiled and run only on a P4-promoted, replay-confirmed disproof).

## 4. Unsupported leg — mechanical rejections (unit suites)

The two unit suites were re-executed in the canonical run's build (`801a12be6` — the commit the runs executed) to capture the tails; the run itself preserved no unit-suite log file (§7, deviation 3).

Suites green in the run's build — re-measured in the canonical build `801a12be6` (which contains the branch candidate `caa678c23`):

| suite | file | cases | measured |
|---|---|---|---|
| bytesview slice binding | `tests/unit/test_libp2p_bytesview_binding.nim` | 4 suites / 37 cases | **37 [OK] / 0 [FAILED]** — loader/fail-closed (17) · pin (6) · synthesis (10) · replay (4); the replay suite compiles the stamped harness against a byte-exact pinned copy of the subject module and observes the template's real length where the law demands more (`rvAgree`), plus a counterfactual twin subject (`rvDisagree`) |
| P4 disproof carve-out | `tests/unit/batch_uap_orchestrator_test.nim` | 2 suites / 6 cases (2 new) | **6 [OK] / 0 [FAILED]** — a fatally blocked node *without* a scoped disproof stays `orchestrationPreSievedUnverifiable`; *with* a scoped `vsDisproved` it reports `orchestrationProofFailed` |

Captured tails (exit 0 for both; `nim c --hints:off --nimcache:/tmp/ax_bv_nc -o:/tmp/ax_bv_binding_test tests/unit/test_libp2p_bytesview_binding.nim` · `nim c --hints:off --nimcache:/tmp/ax_orch_nc -o:/tmp/ax_orch_test tests/unit/batch_uap_orchestrator_test.nim`):

```
[Suite] bytesview slice replay — the ORIGINAL template's length decides
  [OK] compositeReplayShape is empty for the stamped binding (template owns the harness)
  [OK] dry-run: the observed length is evaluated against the adopted law concretely
  [OK] end-to-end: replay against the ORIGINAL template — e = 3 agrees
  [OK] end-to-end: the observation decides — a law-satisfying subject disagrees
bytesview slice binding tests done (state dir: /tmp/ax_libp2p_bv_test_state)
```

```
[Suite] BatchUapOrchestrator — P4 disproof carve-out
  … pre-flight / PBT registry / IR-pipeline log …
  [INFO] loop_driver:   [1/1] src/axiom_test_blocked_template.nim::axiomTestBlockedTemplate — pre-sieved
  [WARN] loop_driver: Verification-Gate: UAP produced 0 results (requests=1)
  [OK] fatally blocked node without a scoped disproof reports pre-sieved
  … pre-flight / PBT registry / IR-pipeline log …
  [ERROR] loop_driver:   [1/1] src/axiom_test_blocked_template.nim::axiomTestBlockedTemplate — failed
  [WARN] loop_driver: Verification-Gate: UAP produced 0 results (requests=1)
  [OK] fatally blocked node with a scoped vsDisproved result reports failed
```

(intervening pipeline log lines elided with `…`)

## 5. Determinism — d1 vs d2 (independent cold state dirs)

| projection | d1 | d2 | match |
|---|---|---|---|
| `canonicalRunDigest` | `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590` | same | **MATCH** |
| `runAccountingDigest` | `a8b56f0a9be3645377ce3a8e8d1e5129ba268d8c308f7eefa3d676e94367899d` | same | MATCH |
| `runOutcomeDigest` | `d9b254d4d834cea34e2aed3c4e3986e5308d0588f648fc102c24e60ab2a354e9` | same | MATCH |
| claim map (the `unitEvidenceRefs` row + the 13-record payload) | — | — | byte-equal (the same 13 records, the same `claimId`/`evidenceId`/`obligationId`/`specificationId`) |
| evidence CAS (`<state>/.axiom/cache/evidence/*.json`) | 10 files | 10 files | byte-identical (`diff -r` between the two legs reports no difference) |
| stderr log | — | — | byte-identical except the vault path on the phase-13 line (`diff` = 1 line: `vault_d1/manifest.json` vs `vault_d2/manifest.json`) |
| vault manifest | 6 rows | 6 rows | equal except `lastVerifiedAt` (wall-clock operational artifact); all six `irHash` values identical |
| exit code | 1 | 1 | MATCH |

Interpretation caveat (recorded honestly, carried over from FREEZE §8.1): the three digest values cover **run-accounting SHAPE** (waves/terminals/counts), **not** the payload bytes — the same shape-level values also appear in the 2026-10-10 C_out slice and the 2026-10-19 sidecar slice. Within THIS freeze the required comparison is d1↔d2 (MATCH, with payload-level byte equality established independently via the claim map + evidence CAS above); the cross-experiment equality is a property of the shape-level projection, not evidence that two different payloads share identity.

## 6. 5-kind success table

| kind | status | evidence |
|---|---|---|
| defect | **BIFURCATED** — SAT→P4→replay agreement→BUG_FOUND payload, exit 1 | §2 (13 records, `rvAgree`, payload identical across cold runs) |
| control | **GUARD HELD** — UNSAT, no counterexample, no subject execution | §3 |
| unsupported | **REJECTED** — fail-closed unit suites green (37 [OK] / 0 [FAILED] · 6 [OK] / 0 [FAILED]) | §4 |
| integrity | **IDENTICAL** — 641/641 files, pre==post | [INTEGRITY.md](./INTEGRITY.md) |
| discovery | **PRESERVED** — 15 verbatim investigation-chain records, sha256-pinned (not blind agents: this slice's rule was externally established and explicitly adopted) | [`discovery/INDEX.md`](./discovery/INDEX.md) |

## 7. Deviations from the frozen procedure (reported as-is)

1. **The frozen full-tree manifest copies were not preserved.** FREEZE §7 steps 1 and 5 planned `runs/subject_tree_pre.sha256` / `runs/subject_tree_post.sha256`; the run preserved only the pins `subject_pins_pre.txt` / `subject_pins_post.txt` (HEAD, tree, module content sha256 — byte-identical, sha256 `fdbf8db3…95ff` at both ends). The manifest was re-derived from the unchanged tree with the frozen command: **641 entries**, manifest-file sha256 `85c39af3…3bd4`, the same value at both ends — no subject file was added, removed or rewritten inside the run window (the newest mtime in the tree is 2026-10-22 14:20:19; 0 files newer than 20:00). [INTEGRITY.md](./INTEGRITY.md) records the derivation.
2. **The subject clone's mode-bit write-protection did not hold.** FREEZE §2 expected dirs `r-xr-xr-x` / files `r--r--r--` with a `touch` probe → EACCES; the clone carries `0775`/`0664` (owner-writable) and no `chmod` occurred inside the run window (`ctime` 2026-10-22 16:34 < the 20:51 run), so no probe was made — it would have written. The Zero-Footprint verdict therefore rests on the measured pins, the empty porcelain at both ends, the tree mtime census and the in-run fold `replay.moduleSha256 == replay.moduleSha256AfterRun`, **not** on the mode bits. The run wrote nothing into the subject (the replay harness is compiled out of tree).
3. **The unit-suite legs preserved no log file.** Both suites were re-executed in the canonical build `801a12be6` on 2026-10-22 to capture the tails recorded in §4 — 37 [OK] / 0 [FAILED] and 6 [OK] / 0 [FAILED], exit 0 for both.
4. **stdout was captured to stderr only.** No stdout artifact was preserved for either leg (the sidecar precedent preserved empty stdout files), so the empty stdout is asserted by the capture layout — every console line of both legs is in the stderr logs.
5. No other deviations; all other frozen expectations in FREEZE §5 were met.

## 8. Artifact index

| artifact | path |
|---|---|
| freeze record | `experiments/nim-libp2p-bytesview-slice-e2e/FREEZE.md` |
| integrity record | `experiments/nim-libp2p-bytesview-slice-e2e/INTEGRITY.md` |
| d1/d2 stderr logs (committed evidence) | `runs/d1_stderr.log`, `runs/d2_stderr.log` — byte-identical except the phase-13 vault path |
| subject pins (pre/post) | `subject_pins_pre.txt`, `subject_pins_post.txt` — byte-identical (sha256 `fdbf8db3…95ff`) |
| state/vault dirs (gitignored) | `state_d1/`, `state_d2/`, `vault_d1/`, `vault_d2/` |
| state projections | `state_dN/logs/ax_proof_state.json` (`canonicalRunDigest`), `state_dN/logs/ax_prove_trajectory.jsonl` (claim rows + payload), `state_dN/logs/z3_telemetry.jsonl`, `vault_dN/manifest.json` |
| evidence CAS (byte-identical d1/d2) | `state_dN/.axiom/cache/evidence/*.json` (10 files/leg) |
| discovery chain | `discovery/01..15_*.md` + `discovery/INDEX.md` (sha256-pinned) |
| evidence doc (PR-B) | `docs/evidence/nim_libp2p_bytesview_slice_2026-10-22.md` |
| **not preserved** (see §7) | the stdout captures, the unit-suite logs and the full-tree manifest copies — the run kept the stderr logs and the pins only |

## 9. Landing record (PR-A) — observed facts

Landing facts are **observations of GitHub** (the merge authority), not inferences. They are
recorded here so the acceptance record is anchored to the exact main commit the canonical d1/d2
runs executed.

| fact | value |
|---|---|
| PR | #1043 — `followup/libp2p-bytesview-slice` → `main` (https://github.com/Archright/Axiom/pull/1043) |
| state | **MERGED** |
| merged at | 2026-10-22T09:58:24Z |
| merge commit | `801a12be69f7f82f6792e31ccc5757cbc7a48364` — a **native 2-parent MERGE** (parents `6e45b7167` + `efde23cc4`), not a squash or rebase |
| required checks | **5/5 PASS** — `admission-check` · `axiom-operational-slice` (8m47s) · `bsec-integrity` · `debt-registry-gate` · `generation-acceptance` |
| merge queue | admission-gate group run `39757132531` — success |
| landing observation | **TERMINAL_SUCCESS** |
| `AXIOM_REVISION` for the runs | the merged main commit `801a12be6` — containing `98b8b7069` (contract) → `7d8856dd5` (feature) → `6da2f8792` (P4 carve-out fix) → `caa678c23` (rotation) → `efde23cc4` (policy-mirror sync) |
| branch base | `0b2564b270d305ff497b129bfc84d06ba66fef3c` — `origin/main` at branch creation (`Merge pull request #1040 from Archright/feat/operational-slice`) |

### 9.1 The mid-flight L2 episode (recorded as observed)

The landing was not a single straight pass; one episode occurred mid-flight and is recorded here
in full rather than smoothed over.

| phase | observation |
|---|---|
| trigger | the first `generation-acceptance` run **REJECTED:POLICY_RULESET_MISMATCH** |
| cause | `main` had landed **PR #1042** (policy mirror **v1.17.0** — adding the 5th required check `axiom-operational-slice`) *after* our branch was cut, so the branch's ruleset no longer matched the one the check enforced |
| resolution | gated merge commit **`efde23cc40`** — `sync: merge main 6e45b7167 — policy mirror v1.17.0 (axiom-operational-slice 5th required check)` — brought the policy mirror onto the branch |
| re-verification (H2) | **re-verified**: TWS pin == derived, **880 members** |
| re-arm | auto-merge re-armed at the new head |
| outcome | the landing then proceeded to `801a12be6` with required checks 5/5 PASS and landing observed TERMINAL_SUCCESS (§9) |

This episode is a **landing-process** event. It does not alter any frozen expectation in
`FREEZE.md`, and it is not a deviation from the frozen *run* procedure in §7 above — the
deviation list in §7 remains reserved for the run itself.

## Discovery chain (investigation record — NOT a blind-agent leg)

This slice's rule was **not** discovered by a blind agent leg: the law's justification (Nim's official
inclusive `toOpenArray` semantics, `lib/system.nim:2982-2996`; the production call sites
`libp2p/protocols/secure/noise.nim:314,333`; the sibling `data` template's inclusive idiom) was
established by external investigation and then adopted by an explicit, user-approved act. The
investigation chain is preserved verbatim — 15 session records, sha256-pinned, nothing edited —
under [`discovery/`](./discovery/INDEX.md):

| # | agent | what it established |
|---|---|---|
| 01 | `agent-i3wikkui` | the read-only nim-libp2p survey; C2 (the `toOpenArray` length algebra) among contradiction candidates C1–C10; the pure-module set; the Nim 2.2.10 pin |
| 02 | `agent-n217p23j` | the `ax prove` mechanical model — the external-subject lane, Lean/Z3 legs, scope mechanism, determinism projections |
| 03 | `agent-gnppig6z` | prior art + product contract: the 5 existing `soExplicit` overlays, the §10 Act 2 external-subject authority, VKD non-inclusion |
| 04 | `agent-qls909lj` | the C2 fact re-verification: the body, the two `b=0` production call sites, the inclusive-intent evidence, the git history (same-commit test snapshot) |
| 05 | `agent-neih9viz` | the stamped-harness feasibility (template ⇒ stamped path only), the 14-touchpoint wiring checklist, the `AXIOM_STATE_DIR` seeding requirements |
| 06 | `agent-g9ct01sk` | the landing path: ruleset, merge queue, the two-PR discipline, permission boundaries |
| 07 | `agent-dmil9xkr` | the three-tool contract: `derive_checker_closure` / `axiom-gate commit` / `debt_engine` (commit-first → derive → pin; the `git add -u` sweep) |
| 08 | `agent-kn4koshi` | PR #938 / #911 / #912 / #947 archaeology: the 3-commit rotation sequence and the exact TWS diff shape |
| 09 | `agent-dy61wesc` | the control-leg semantics: no non-defect leg ever executes the subject; the control is a solver-level injection guard |
| 10 | `agent-x5whbl7w` | the `bin/ax` build identity: the 4-step build, `SourceCoherence`, `engineBuild` admissibility |
| 11 | `agent-vyq7cmx2` | Stage A — the overlay + contract files; the sha256 typo correction; the `b=1` algebra correction |
| 12 | `agent-3qsjhlfa` | Stage B — the +736 wiring and the 37-case unit suite |
| 13 | `agent-2x15fwme` | the exit-0 root cause: the template ⇒ fatal pre-sieve swallowed `vsDisproved`; the payload persisted in `unitEvidenceRefs` |
| 14 | `agent-2onqm98u` | the P4 disproof carve-out fix and its 2 new orchestrator cases |
| 15 | `agent-nqjowmqi` | the staging/hash re-verification: the `git add -u` sweep, the `perf_latest.json` trap, the two pin kinds, the d2 format-only pin |

## Final verdict table (bifurcated judgment)

| leg | measured | verdict |
|---|---|---|
| defect | 13-record BUG_FOUND payload on the pinned subject bytes (`input.e=4`, `rvAgree` — observed length 3 where the law demands 4) → node `failed`, exit 1 | **BIFURCATED-OBSERVED** |
| control | control UNSAT — absent from all 4 IR-pipeline FAIL rows, among the 2 Pass rows, no `counterExample`, vault row `certZ3Candidate` (no `certRed`) | **HELD** |
| unit suites | 37 [OK] / 0 [FAILED] (binding) + 6 [OK] / 0 [FAILED] (carve-out), exit 0 for both | **GREEN** |
| Zero-Footprint | 641-file manifest byte-identical pre↔post (sha256 `85c39af3…3bd4`), pins byte-identical, porcelain clean at both ends, no subject file written inside the run window ([INTEGRITY.md](./INTEGRITY.md)) | **INTACT** |
| determinism | `canonicalRunDigest` d1 == d2 == `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590`; claim map + 13 records and the 10 CAS files byte-identical (§5) | **MATCH** |
| landing | PR #1043 — merge commit `801a12be69f7f82f6792e31ccc5757cbc7a48364` (native 2-parent MERGE: `6e45b7167` + `efde23cc4`), merged 2026-10-22T09:58:24Z; required checks 5/5 PASS; merge-queue admission-gate group run `39757132531` success; landing observed TERMINAL_SUCCESS | **LANDED** — see §9 |
