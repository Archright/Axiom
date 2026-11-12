# ACCEPTANCE — frozen acceptance run: generic Nim sidecar adapter end-to-end

> **Run date**: 2026-10-19 · **Freeze**: [FREEZE.md](./FREEZE.md) (written BEFORE the first judged execution) · **Integrity**: [INTEGRITY.md](./INTEGRITY.md)
> **Command under judgment**: `AXIOM_STATE_DIR=<exp>/state_dN AXIOM_PROVE_VAULT_DIR=<exp>/vault_dN bin/ax prove --project /tmp/sidecar_probe/nim-stew --target "stew/base36.nim::decodedLength"` (COLD each leg; scope lock seeded into `<state>/data/` from the COMMITTED `data/verification_scope.lock`)
> **Build identity**: HEAD `00bb8334c312736922a3a41fb4033b6da755eb1d` (PR #938 merge) · `bin/ax` sha256 `79b580e41ce73d1922d77c47e719c3044248ddcb4b9a000fa67290072b5334c0` · Nim 2.2.10 · Z3 4.13.3 · tracked tree clean at freeze and at close (only this untracked experiment dir added)

## 1. Verdict table (frozen judgments of FREEZE.md §6, measured)

| frozen question | measured | verdict |
|---|---|---|
| defect replay agreed? | `[ce-replay] decodedLength_sidecar_defect — replay agreed; BUG_FOUND payload assembled (13 records)` (d1 stderr line 26; d2 line 26 identical) · node `stew/base36.nim::decodedLength — failed` · `runOutcome.verdict=FAIL`, `gateVerdict=FAIL` · **exit 1** (VERIFICATION_FAILURE) | **YES** |
| control unproven (UNSAT guard)? | control carrier present and routed (see §3); NO counterexample, NO SAT: `decodedLength_sidecar_control` absent from all 3 IR-pipeline FAIL rows, vault row `certZ3Candidate` (no `certRed`), canonical leg `[dual-declined] … decodedLength_sidecar_control` (completeness evidence not measured for this subject — Lean KAA lean-only), IR summary Total 6 / **Pass 3** / Fail 3 with control among Pass | **YES** |
| unsupported rejected? | `nim r tests/unit/test_sidecar_binding.nim` → **exit 0, 42 [OK] / 0 [FAILED]**; grammar-outside rejections and hash-mismatch rejections all pass (§4 quotes) | **YES** |
| integrity identical? | pre/post full-file manifests byte-identical (95 files, manifest sha256 `685717450622a8010fea8839e73d9e26c83da9c7190f6c2fcc2f86d4209ba290` both ends), rev unchanged, porcelain clean both ends ([INTEGRITY.md](./INTEGRITY.md)) | **YES** |
| determinism match? | `canonicalRunDigest` d1 == d2 == `29db1e362ad17adb15a76b90bfad89f0d8043e0ed8b6f12f55f486f5b7241ccf` — **MATCH**; see §5 for the full byte-equality set | **MATCH** |

**Judgment (frozen table): defect observed end-to-end → PASS.** None of the FAIL/INCOMPLETE rows triggered: no adapter-only verdict (a real replay of the subject's own body disagreed and carried the BUG_FOUND payload), no control SAT, no grammar/hash-mismatch acceptance, no subject digest change.

## 2. Defect leg — machine record (d1; d2 byte-agrees)

- Command exit: **1** (both legs).
- Sidecar routing: `sidecar carriers synthesized (hash-bound adoption 8e9564842090…): decodedLength_sidecar_defect [length == 3 -> result == 2] + decodedLength_sidecar_control [length == 2 -> result == 1] obligations=3/3 eligible=true/true source=stew/base36.nim`
- `[ce-replay]` line **verbatim**: `[INFO] ir_pipeline_runner: [ce-replay] decodedLength_sidecar_defect — replay agreed; BUG_FOUND payload assembled (13 records)`
- Claim row (`stew/base36.nim::decodedLength`): `claimId=addd0c19eb219c4df03c602952cdd307df5f29252f08144a99e810ec212afc40` · `claimOutcome=clDisproved` · `evidenceId=c615690c1ad7e46f04c438f280329564d5eefff65ec633e2702ddd2bba492867` · `obligationId=obl:d2c44f569ef61e349a915582c4237b1b747df4d30a4701712178655bdd5bc44e` · `specificationId=658d70abf67cc16a172dbd4ed5574a4e8129313d846c65b8015322a94ac69675`
- Counterexample payload — all **13 records** verbatim (identical bytes in d1 and d2):
  1. `input.length=3`
  2. `propertyViolated=(= (bvsdiv (bvmul length #x00000000000000B3) #x0000000000000115) #x0000000000000002)` — `((3*179) div 277) == 2` is false (3·179 div 277 = 1)
  3. `replay.verdict=rvAgree` (`propertyHolds == false` — the replayed call observed `1`)
  4. `replay.exitCode=0`
  5. `replay.subjectGitRef=1853f20bdfeda61331a0b7e02f7aace0e88a0dfe`
  6. `replay.treeMerkle=25a296cdcdbb3ed8017edebc42be2f245b610f12`
  7. `replay.moduleSha256=b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8`
  8. `replay.moduleSha256AfterRun=b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8`
  9. `replay.porcelainClean=true`
  10. `replay.nimVersion=Nim Compiler Version 2.2.10 [Linux: amd64]`
  11. `replay.nimHash=d955005687bea4d3ca6c5813792789987405343a1e8b8c0a8b3a22b9c23936cf`
  12. `replay.stdlibHash=`
  13. `replay.hostPlatform=linux-amd64`
- Replay call shape: `decodedLength(Base36Types, 3)` (frozen pinned carrier token; unit test `harness rendering emits the pinned call form decodedLength(Base36Types, 3)` [OK]).
- stdout of both legs: 0 bytes (report projected to state logs + stderr; captured as `runs/d1_stdout.json`, `runs/d2_stdout.json`).
- Logs: `runs/d1_stderr.log`, `runs/d2_stderr.log` (byte-identical except the d1/d2 vault path string on the phase-13 line); state dirs `state_d1/`, `state_d2/`, vaults `vault_d1/`, `vault_d2/` (gitignored).

## 3. Control leg — in-run control evidence (recorded per FREEZE §5 fallback)

`--target` cannot isolate the control carrier alone: the sidecar routing synthesizes BOTH carriers under the single governed `decodedLength` hit (contract §4 D4; the defect carrier is wave-faced under the examined symbol, the control rides its own name). Isolation was NOT attempted; the in-run control evidence is:

- Routing: control carrier present, eligible — `…+ decodedLength_sidecar_control [length == 2 -> result == 1] obligations=3/3 eligible=true/true`.
- Canonical leg: `[WARN] ir_pipeline_runner: [dual-declined] decodedLength_sidecar_control — completeness evidence not measured for this subject (Lean KAA remains lean-only)` → falls to the BMC lane.
- BMC lane: control is in the IR batch (6 results) and is NOT among the 3 FAIL rows (`calcDynamicTimeoutCore`, `safeSpeedupRatioCore`, `decodedLength`) — i.e. **no counterexample** for `length == 2 → result == 1`; a control SAT would have surfaced exactly like the defect leg (payload + FAIL row) and would have triggered the frozen FAIL row.
- Vault manifest row (both vaults): `{"modulePath":"stew/base36.nim","functionName":"decodedLength_sidecar_control","status":"certZ3Candidate","solverMethod":"smNone",…}` — no `certRed`.
- Evidence CAS for the control carrier (`state_d1/.axiom/cache/evidence/50c572441fa2eedc7ebfcc0e8febc832351817cff32030306d3098475445f64f.json`) is byte-identical across d1/d2.

**Injection guard held: control UNSAT (unproven, as expected).**

## 4. Unsupported leg — grammar-outside + hash-mismatch mechanical rejections

`nim r tests/unit/test_sidecar_binding.nim` → exit 0, `42 [OK] / 0 [FAILED]` (tail preserved at `runs/unsupported_tests.log`; suite report ends `sidecar binding tests done (state dir: /tmp/ax_sidecar_test_state)`). Quoted rows:

Grammar-outside (closed grammar `nim-sidecar-expr-v1`):
```
[OK] fail-closed: a grammar-outside proposition is rejected (no '*')        (loader stage-i)
[OK] fail-closed: multiplication is outside the grammar
[OK] fail-closed: comparisons beyond '==' are outside the grammar
[OK] fail-closed: a single '=' is outside the grammar
[OK] fail-closed: an unknown identifier is outside the grammar
[OK] fail-closed: integer literal overflow is outside the grammar
[OK] fail-closed: trailing input after the equality is outside the grammar
```

Hash-bound adoption + subject pin (loader stage-ii):
```
[OK] the adoption record hash-binds the loaded proposition content
[OK] fail-closed: a non-explicit origin is rejected
[OK] fail-closed: mutating a proposition clause invalidates the adoption
[OK] fail-closed: mutating ruleVersion invalidates the adoption
[OK] fail-closed: a foreign grammarVersion is rejected
[OK] fail-closed: a missing adoption object is rejected
[OK] fail-closed: a mutated adoptedSpecHash is rejected
[OK] fail-closed: a blob mismatch rejects the subject tree
```

Intentional loader/pipeline probes exercised by the suite (mechanical, real `runIrPipelineWithCas`): `the adopted defect instance is refuted — or fails closed` [OK] and `the counterexample payload carries the four BUG_FOUND elements — or fails closed` [OK]; the probe replay additionally demonstrated the fail-closed replay guard on a drifted fixture: `[ce-replay] decodedLength_sidecar_defect — replay rvUnavailable:subject tree drifted during replay (hash/porcelain mismatch); fail-closed cvUnresolved` (the `— or fails closed` acceptance arm).

## 5. Determinism — d1 vs d2 (independent cold state dirs)

| projection | d1 | d2 | match |
|---|---|---|---|
| `canonicalRunDigest` | `29db1e362ad17adb15a76b90bfad89f0d8043e0ed8b6f12f55f486f5b7241ccf` | same | **MATCH** |
| `runAccountingDigest` | `982beeb9085ae2cddeb810b0f9dff937e45f6e1f53b494a3a14cb953a3eb1dfb` | same | MATCH |
| `runOutcomeDigest` | `d9b254d4d834cea34e2aed3c4e3986e5308d0588f648fc102c24e60ab2a354e9` | same | MATCH |
| claim maps (all 4 rows incl. specIds, outcomes, 13-record payload) | — | — | byte-equal |
| evidence CAS (`50c57244…`, `5573116c…`, `e986cf60…`) | — | — | byte-identical |
| stderr log | — | — | byte-identical except vault path on phase-13 line |
| vault manifest | — | — | equal except `lastVerifiedAt` (wall-clock operational artifact) |
| exit code | 1 | 1 | MATCH |

Interpretation caveat (recorded honestly): these three digest values are also exactly the values recorded for the 2026-10-10 C_out slice's J1/J2 runs (`docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md` 결정론 표) — the digest projection covers RUN ACCOUNTING SHAPE (waves/terminals/counts), not the payload bytes. Within THIS freeze the required comparison is d1↔d2 (MATCH, with payload-level byte equality independently established via claim maps + CAS above); the cross-experiment equality is a property of the shape-level projection, not evidence that two different payloads share identity.

## 6. 5-kind success table (skeleton — discovery kind appended later)

| kind | status | evidence |
|---|---|---|
| defect | **BIFURCATED** — SAT→P4→replay disagreement→BUG_FOUND payload, exit 1 | §2 (13 records, rvAgree, payload identical across cold runs) |
| control | **GUARD HELD** — UNSAT, no counterexample | §3 |
| unsupported | **REJECTED** — grammar-outside + hash-mismatch fail-closed (42/42) | §4 |
| integrity | **IDENTICAL** — 95/95 files, pre==post | [INTEGRITY.md](./INTEGRITY.md) |
| discovery (blind agents) | **APPENDED LATER** — frozen prompt/tool-scope/known-answers in [FREEZE.md](./FREEZE.md) §4; outputs will be appended below as `## APPENDED BLIND OUTPUTS` when their runs land; K1 overlap disclosure applies | (pending) |

## 7. Deviations from the frozen procedure (reported as-is)

1. **`bin/ax scope lock` regen is not byte-idempotent**: running it reordered `kernel_symbols` in the tracked `data/verification_scope.lock` (same 40-symbol set; observed and immediately `git restore`d — no tracked file remains modified). Seeding therefore used the COMMITTED lock bytes copied into `<state>/data/verification_scope.lock` (the path the engine resolves first under `AXIOM_STATE_DIR`, `axiom_engine.nim:3747-3753`). Recorded in FREEZE §1/§7.
2. **stdout empty on both prove legs** (report lives in state logs + stderr) — capture files preserved empty for completeness.
3. No other deviations; all frozen expectations in FREEZE §5 were met.

## 8. Artifact index

| artifact | path |
|---|---|
| freeze record | `experiments/sidecar-adoption-e2e/FREEZE.md` |
| integrity record | `experiments/sidecar-adoption-e2e/INTEGRITY.md` |
| d1/d2 stderr + stdout | `runs/d1_stderr.log`, `runs/d2_stderr.log`, `runs/d1_stdout.json`, `runs/d2_stdout.json` |
| unit-suite log | `runs/unsupported_tests.log` |
| subject manifests (pre/post) | `runs/subject_tree_pre.sha256`, `runs/subject_tree_post.sha256` |
| state/vault dirs (gitignored) | `state_d1/`, `state_d2/`, `vault_d1/`, `vault_d2/` |
| state projections | `state_dN/logs/ax_proof_state.json` (canonicalRunDigest), `state_dN/logs/ax_prove_trajectory.jsonl` (claim rows + payload), `state_dN/logs/z3_telemetry.jsonl`, `vault_dN/manifest.json` |
| evidence CAS (byte-identical d1/d2) | `state_dN/.axiom/cache/evidence/{50c57244…,5573116c…,e986cf60…}.json` |

## Blind discovery results (frozen protocol: FREEZE §4)

Two zero-context agents (A1, A2) executed the frozen prompt (FREEZE §4.1) under the frozen tool scope (§4.2 — read-only nim-stew clone @`1853f20b…`; no access to Axiom sources, spec overlays, prior C_out evidence, this experiment dir, or any prior base36 defect report) and reported independently. Their session task outputs are preserved **VERBATIM** in this record — copied byte-identical from the session logs (sha256 pinned below), nothing edited.

### Raw outputs (verbatim copies, sha256-pinned)

| agent | record | sha256 |
|---|---|---|
| A1 | `discovery/agentA1_raw.md` | `c8389df5ea817942072b15af9c506b603ed9180617f5b44eab12e1c1c0d9aac6` |
| A2 | `discovery/agentA2_raw.md` | `19133648f8609476d295b0f9e547f7c0336cbaea8d19a7a265cf8a2cb37547eb` |

### A1 — HIT

- A1 independently located **`stew/base36.nim::decodedLength`** (its strongest candidate, confidence 0.85) and inferred the proposition **`result == (length + 4)`** — closed-grammar expressible under `nim-sidecar-expr-v1`.
- Grounding trail (the agent's own citations, verbatim in the raw record): `stew/base58.nim:55-58` — the sibling API with the *identical docstring* implements exactly `result = length + 4`; `stew/base36.nim:134-138` — base36's own `decode` hard-requires `payload.len + 4` output bytes; `tests/test_base36.nim:84-85` — the repo's own test pins `Overrun` at `decsize == 5` for 1 payload char.
- Suspected input: `length = 1` → body returns `(1*179) div 277 = 0` where the law demands 5. A1 additionally disclosed the typedesc-erasure caveat (runtime signature `(int) -> int`) and the zero-caller/dead-API status of the function.
- Secondary candidates in the same raw report (for fidelity, not adopted): two medium-confidence base64 sizing candidates (`base64.decodedLength` pad branch 0.55; `base64.encodedLength` 0.5) — outside the governed module.

### A2 — MISS

- A2 did not locate `decodedLength`. Its three delivered candidates are **low-confidence** endians2/bitops2 propositions (`swapBytesNim(uint16)` ~5%, `swapBytesNim(uint32)` ~2%, `rotateLeft` instantiation-seam), each hand-verified BY THE AGENT ITSELF to likely HOLD — delivered as mechanically checkable propositions for a prover, with low defect confidence. Not defect claims.
- Side finding (grounded but **shape-ineligible**): the documented identity `firstOne(x) == trailingZeros(x) + 1` (`stew/bitops2.nim:327`) is false at `x = 0` by the same file's own specs — `firstOne(0) == 0` (`:325`, test `tests/test_bitops2.nim:26`) while `trailingZeros(0) == bitsof(x)` (`:379`, test `:68`). Both functions fail shape (a) (they call helpers), so it cannot be delivered as a sidecar candidate. Recorded as-is; not a sidecar-eligible defect.

### Discovery-axis scoring

| axis | score | basis |
|---|---|---|
| generalization (grounded candidates from a novel repo) | **2/2** | both agents produced candidates with explicit ground citations (A1: 3 candidates incl. the hit; A2: 3 candidates + 1 side finding) |
| known-answer recovery (K1: `decodedLength` under-estimate) | **1/2** | A1 recovered K1's function AND its law (independent grounding + the `length = 1` witness); A2 did not |

### Known-answer overlap disclosure (disposition)

K1 is a **KNOWN-ANSWER OVERLAP** with the 2026-10-10 C_out slice (`docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md`: `dl(3)=1` vs `outlen=2`) — disclosed at freeze (FREEZE §4.3) and confirmed here: A1's hit re-locates the same function. **Disposition: this experiment re-demonstrates the generic sidecar path** (frozen blind agent → closed-grammar proposition → hash-bound adoption → end-to-end proof) **on the same function; discovery novelty is not claimed.** What is new in this record's chain is the law FORM A1 inferred — `result == (length + 4)`, a general under-estimate law with its own independent grounding and the `length = 1` witness, not the C_out `dl(3)` instance — which became the adopted generation-2 content (below).

## Adoption evolution (per contract §8)

| generation | propositions (defect / control) | adoptedSpecHash | status |
|---|---|---|---|
| 1 | defect `length == 3 -> result == 2`; control `length == 2 -> result == 1` | `8e9564842090127b261c30fdd95db095957ad2628fb5a35e4c4016673441e3be` | **superseded** (retained as history) |
| 2 | defect `length == 1 -> result == (length + 4)`; control unchanged `length == 2 -> result == 1` | `3f55eaa79f3708894a04d62bc7ac32c9e2a8fe84d4f575348318d7290d237ea8` | **current** — adopted verbatim from A1 |

- Recorded per **contract §8** (adoption-evolution amendment of 2026-10-19); landed on main via **PR #943** (merge `a292f0596`; spec commit `d7c053e66` — "feat(spec): adopt blind agent A1's inferred law into SPEC-B36-SIDECAR … superseded record retained"). The acceptance run above (§1–§7) replayed the **generation-1** instance — the observation and the adoption evolution are related but distinct legs, both recorded.
- **Schema finding**: the loader requires a non-empty pre AND post per proposition — an EMPTY pre ("general law, no pre") is NOT schema-expressible. The adopted defect therefore pins the minimal grammar-expressible pre = **the agent's own suspected input** (`length == 1`), which makes the model binding deterministic and pins the replay's exact input `decodedLength(Base36Types, 1)`; the post is adopted VERBATIM.
- Authority unchanged: A1 authored the CONTENT; the authority to verify against it remains the explicit hash-bound adoption act (`config/spec/nim_stew_base36_sidecar.json`, loader-recomputed `specIdentity` = `adoptedSpecHash`); generation-1 is superseded history, not rewritten.

## Final verdict table (bifurcated judgment)

| leg | measured | verdict |
|---|---|---|
| defect | BUG_FOUND observed end-to-end on merged main: SAT → replay disagreement (`rvAgree`) → **13-record payload** → exit 1; payload hash noted — `claimId=addd0c19eb219c4df03c602952cdd307df5f29252f08144a99e810ec212afc40`, `evidenceId=c615690c1ad7e46f04c438f280329564d5eefff65ec633e2702ddd2bba492867` (§2). Run identity: build `00bb8334c…` (PR #938 merge — the main tip at freeze; both cold legs predate the #943 landing) | **BIFURCATED-OBSERVED** — the observation was measured in this run; the defect's re-adoption (generation-2) landed via PR #943 merge `a292f0596` |
| control | injection guard held — control UNSAT: no counterexample, absent from all 3 IR-pipeline FAIL rows, vault row `certZ3Candidate` (no `certRed`), `dual-declined` to the BMC lane (§3) | **HELD** |
| unsupported | 42/42 fail-closed tests `[OK]` / `0 [FAILED]` (grammar-outside + hash-mismatch rejections; `runs/unsupported_tests.log`; §4) | **REJECTED (fail-closed)** |
| Zero-Footprint | 95-file manifests byte-identical pre↔post (manifest sha256 `685717450622a8010fea8839e73d9e26c83da9c7190f6c2fcc2f86d4209ba290`), rev unchanged, porcelain clean at both ends ([INTEGRITY.md](./INTEGRITY.md)) | **INTACT** |
| determinism | cold digest MATCH — `canonicalRunDigest` d1 == d2 == `29db1e362ad17adb15a76b90bfad89f0d8043e0ed8b6f12f55f486f5b7241ccf` (§5) | **MATCH** |
| landing | PR #943 MERGE `a292f0596` on main (blind-agent adoption evolution; PR #938 merge `00bb8334c` = the binding slice this run replayed) | **LANDED** |

### 5-kind success table (closes the §6 skeleton)

| kind | status | evidence |
|---|---|---|
| defect | **BIFURCATED-OBSERVED** — BUG_FOUND measured end-to-end; the adoption evolution (generation-2) landed as a separate PR | §2 + landing row above |
| discovery | **A1-hit / A2-miss** — generalization 2/2; known-answer recovery 1/2 | `## Blind discovery results` + `discovery/agentA{1,2}_raw.md` |
| implementation | **LANDED (#938/#943)** — binding slice #938 (merge `00bb8334c`), blind-agent adoption evolution #943 (merge `a292f0596`) | git history + contract §8 |
| evidence | **PRESERVED** — this record: FREEZE/INTEGRITY/ACCEPTANCE, `runs/` logs, `discovery/` verbatim raw outputs (sha256-pinned) | §8 artifact index + raw-outputs table |
| known-answer overlap | **DISCLOSED** — K1 ↔ 2026-10-10 C_out slice; novelty not claimed | FREEZE §4.3 + `## Blind discovery results` |

This fills the `discovery (blind agents) → APPENDED LATER` cell of §6.
