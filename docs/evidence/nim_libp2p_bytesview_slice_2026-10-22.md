# nim-libp2p `BytesView.toOpenArray` Slice-Length Defect — Execution Evidence Record

> **Status**: MEASURED — execution evidence record for SPEC-LIBP2P-BV-SLICE (the canonical d1/d2
> runs landed on 2026-10-22, after PR-A; every value below is extracted from the captured run
> artifacts indexed in `experiments/nim-libp2p-bytesview-slice-e2e/ACCEPTANCE.md` §8).
> **Created**: 2026-10-22
> **Product contract**: [docs/spec/nim_libp2p_bytesview_slice_contract.md](../../docs/spec/nim_libp2p_bytesview_slice_contract.md) (`SPEC-LIBP2P-BV-SLICE`, committed `98b8b7069` on `followup/libp2p-bytesview-slice`)
> **Overlay**: `config/spec/nim_libp2p_bytesview_slice.json` (`specOrigin: soExplicit`, rule `external:libp2p/bytesview/slice-length-law` v`1.0.0`)
> **Axiom revision**: PR-A (code) — branch candidate `caa678c23dc9b2cbef6cbc7d65edcd49bdec8d5f` (`rotation: re-anchor trustedCheckerTreeClosure for the libp2p bytesview slice (6da2f8792)`) ← `6da2f8792` (P4 disproof carve-out) ← `7d8856dd5` (engine wiring + unit test) ← `98b8b7069` (contract + overlay), base `0b2564b270d305ff497b129bfc84d06ba66fef3c` (this was `origin/main` at branch creation). **Landing**: PR #1043, merged 2026-10-22T09:58:24Z, merge commit `801a12be69f7f82f6792e31ccc5757cbc7a48364` — a **GitHub native MERGE commit** (2 parents: `6e45b7167` + `efde23cc4`); required checks 5/5 PASS (`admission-check`, `axiom-operational-slice`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`); merge-queue admission-gate group run `39757132531` success; landing observed TERMINAL_SUCCESS. The runs' `AXIOM_REVISION` is the merged main commit `801a12be6`, containing `98b8b7069` (contract) → `7d8856dd5` (feature) → `6da2f8792` (P4 carve-out fix) → `caa678c23` (rotation) → `efde23cc4` (policy-mirror sync). PR-B (this document + the experiment records) lands after the canonical runs.
> **Related precedent**: [nim_stew_base36_cout_slice_2026-10-10.md](./nim_stew_base36_cout_slice_2026-10-10.md) (C_out authority + attach precedent) · `experiments/sidecar-adoption-e2e/{ACCEPTANCE,FREEZE,INTEGRITY}.md` (external-subject lane precedent) · `experiments/nim-libp2p-bytesview-slice-e2e/` (this slice's freeze/acceptance/integrity records)

## Identity header (workspace charter §1)

| key | value |
|---|---|
| `PROJECT_UNDER_TEST` | `status-im/nim-libp2p` (local READ-ONLY clone `<workspace>/nim-libp2p`; origin `iftech/nim-libp2p`, a fork of `status-im/nim-libp2p`) |
| `PROJECT_REVISION` | commit `a130a7f32219909bdcda14b7f1e64d0804fc832c` · tree `ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841` · governed module `libp2p/utils/bytesview.nim` sha256 `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` (git blob OID `621e111d53fd07b4e2eeeb2410a1cd6c05719159` — a different hash kind, recorded separately) |
| `AXIOM_REVISION` | the merged main commit `801a12be69f7f82f6792e31ccc5757cbc7a48364` (PR #1043) — containing `6da2f8792` (P4 disproof carve-out) + rotation `caa678c23dc9b2cbef6cbc7d65edcd49bdec8d5f` + policy-mirror sync `efde23cc40c32af69491e77bdebc6b35b2628ea7`; the 2-parent MERGE parents are `6e45b7167` + `efde23cc4` |
| `AXIOM_CONFIGURATION` | external-subject mode, d2-agent carrier lane (constructed-IR carriers + stamped replay harness) |
| `TOOLCHAIN_IDENTITY` | Nim 2.2.10 / Lean 4.33.0 / Z3 4.13.3 |
| `VERIFICATION_SCOPE` | `SPEC-LIBP2P-BV-SLICE` — single proposition pair (defect carrier `bvSliceLenActual` + control carrier `bvSliceLenControl`) over one model parameter `e` in the domain `1 <= e <= 5` |
| `EXPERIMENT_ID` | `nim-libp2p-bytesview-slice-e2e` |

## Question

Does the adopted slice-length proposition for `libp2p/utils/bytesview.nim::toOpenArray` hold end-to-end
through Axiom's `ax prove` external-subject lane — i.e. does the **defect carrier** produce a
P4-promoted, replay-confirmed disproof (BUG_FOUND payload, exit 1) while the **control carrier**
stays UNSAT, and is that observation reproducible across two cold state dirs with the subject tree
untouched?

## Context

- **Subject**: `status-im/nim-libp2p` @ `a130a7f32` — READ-ONLY clone (Zero-Footprint Integrity); the subject tree is never written to by the run and the replay harness is compiled OUT OF TREE.
- **Axiom configuration**: external-subject mode (`--project` + `AXIOM_STATE_DIR`, fail-closed without it), d2-agent carrier lane.
- **Toolchain**: Nim 2.2.10, Lean 4.33.0, Z3 4.13.3.
- **The subject code** (`libp2p/utils/bytesview.nim:18-19`):

  ```nim
  template toOpenArray*(v: BytesView, b, e: int): openArray[byte] =
    v.data.toOpenArray(v.rpos + b, v.rpos + e - b)
  ```

  `data` is a `seq[byte]` and the system `toOpenArray(x, first, last)` is **INCLUSIVE**
  (`lib/system.nim:2982-2996`, official example `s.toOpenArray(1, 3) == [1, 2, 3]` — three
  elements from a `(1, 3)` request). The template therefore materializes the inclusive interval
  `[rpos + b, rpos + e - b]`, of length `e - 2b + 1`, while the inclusive view-relative law is
  `e - b + 1`. At `b = 1` the actual length is `e - 1` — exactly **one element short** of the law
  for every `e` in the domain.
- **Production call sites** (`libp2p/protocols/secure/noise.nim:314,333`): both call the very
  template under adjudication with `b = 0`, into 32-byte destinations (`Curve25519Key`,
  `libp2p/crypto/curve25519.nim:24`) — under a half-open reading the second call would hand
  `rsLen - 1` bytes to a `rsLen`-byte destination. Both sites are exercised by
  `tests/libp2p/protocols/test_noise.nim`.
- **The repo's only `b > 0` witness is not an independent oracle**
  (`tests/libp2p/utils/test_bytesview.nim:14,19`): the template and both assertions were introduced
  by the **same commit** `aa1c33ffe92ff259c432d51612524179e8f767e3` (2025-07-07, vladopajic) — a
  behavior snapshot, not an adjudication of intent.
- **Experiment ID**: `nim-libp2p-bytesview-slice-e2e`; freeze in
  `experiments/nim-libp2p-bytesview-slice-e2e/FREEZE.md`, verdict in `…/ACCEPTANCE.md`, integrity in
  `…/INTEGRITY.md`, investigation chain in `…/discovery/`.

### Landing record (PR-A) — observed facts

Landing facts below are **observations of GitHub** (the merge authority) and of the local object
graph; none is inferred.

| fact | value |
|---|---|
| PR | #1043 — `followup/libp2p-bytesview-slice` → `main` |
| state / merged at | **MERGED** / 2026-10-22T09:58:24Z |
| merge commit | `801a12be69f7f82f6792e31ccc5757cbc7a48364` — a **native 2-parent MERGE** (parents `6e45b7167` + `efde23cc4`), not a squash or rebase |
| required checks | **5/5 PASS** — `admission-check` · `axiom-operational-slice` (8m47s) · `bsec-integrity` · `debt-registry-gate` · `generation-acceptance` |
| merge queue | admission-gate group run `39757132531` — success |
| landing observation | **TERMINAL_SUCCESS** |
| branch base | `0b2564b270d305ff497b129bfc84d06ba66fef3c` — `origin/main` at branch creation |

**The mid-flight L2 episode.** The landing was not a straight pass. The first
`generation-acceptance` run **REJECTED:POLICY_RULESET_MISMATCH**, because `main` had landed
**PR #1042** (policy mirror **v1.17.0**, adding the 5th required check `axiom-operational-slice`)
*after* our branch was cut — so the branch's ruleset no longer matched the one the check
enforced. It was resolved by the gated merge commit **`efde23cc40`**
(`sync: merge main 6e45b7167 — policy mirror v1.17.0 (axiom-operational-slice 5th required
check)`), after which **H2 was re-verified** (TWS pin == derived, **880 members**) and
auto-merge was re-armed at the new head. The landing then proceeded to `801a12be6` with
required checks 5/5 PASS and landing observed TERMINAL_SUCCESS. This is a landing-process event;
it changed no frozen expectation and is not a deviation from the frozen *run* procedure.

## Scope

**In scope**

- The single governed module `libp2p/utils/bytesview.nim` at the pinned commit, and the single
  governed symbol `toOpenArray` (a **template**).
- The defect carrier `bvSliceLenActual` (b pinned at 1, model `e - 1`, adopted law `bvSliceLenLaw1(e) == e`)
  and the control carrier `bvSliceLenControl` (b pinned at 0, model `e + 1`, adopted law `bvSliceLenLaw0(e) == (e + 1)`).
- The model parameter `e` over the domain `1 <= e <= 5` (bound to the replay fixture
  `BytesView.init(@[byte 1, 2, 3, 4, 5, 6])`, `rpos = 0`).
- The adopted law **as data** in the overlay's `canonicalSpecIR` (6 clauses, closed grammar).

**Explicitly out of scope**

- Any `(b, e)` outside the pinned carriers (b is fixed per carrier; e is inside `1..5`).
- The subject's `b = 0` runtime behavior as a *claim* — the control is a solver-level injection
  guard, and the subject is never executed for it.
- Any extraction/verification of the original template body — the carriers are CONSTRUCTED IR; the
  subject's connection to the verdict is the stamped replay harness observation alone.
- Protocol-level correctness of nim-libp2p (the rule here is the **Nim language semantics** of the
  inclusive slice convention, not a libp2p protocol rule).
- Any change to the subject repository (the fix decision belongs to the subject's maintainers).

## Procedure

The frozen command sequence, executed verbatim (FREEZE.md §7): pre-manifest + pins of the subject clone → cold leg **d1** (scope lock seeded from the COMMITTED `data/verification_scope.lock` into `<state>/data/`) → cold leg **d2** (fresh state/vault, identical command) → control evidence extracted from the SAME runs' trajectory/manifest rows → unit-suite legs → post-manifest + pins → determinism comparison (the three canonical digests **plus** the payload-level claim map and evidence CAS) → this acceptance record. The captured leg logs are `runs/d1_stderr.log` / `runs/d2_stderr.log`; the pins are `subject_pins_pre.txt` / `subject_pins_post.txt`; the state/vault projections and the evidence CAS live under the gitignored `state_dN/`, `vault_dN/`.

```
AXIOM_STATE_DIR=<exp>/state_d1 AXIOM_PROVE_VAULT_DIR=<exp>/vault_d1 \
  bin/ax prove --project <workspace>/nim-libp2p \
    --target "libp2p/utils/bytesview.nim::toOpenArray"
```

1. Pre manifest of the subject tree (sha256 over every file, `.git` pruned) + `git rev-parse HEAD`,
   `git rev-parse HEAD^{tree}`, `git status --porcelain`.
2. Defect leg **d1** (cold `state_d1`/`vault_d1`, scope lock seeded from the COMMITTED
   `data/verification_scope.lock`), then **d2** (cold again, identical command).
3. Control evidence extracted from the SAME runs' trajectory/manifest rows.
4. Unit-suite legs (`tests/unit/test_libp2p_bytesview_binding.nim`,
   `tests/unit/batch_uap_orchestrator_test.nim`).
5. Post manifest → byte compare → `INTEGRITY.md`.
6. Determinism: `canonicalRunDigest` d1 vs d2 **plus** the payload-level projections (claim map +
   evidence CAS).

## Result

The canonical machine-observed result: the defect carrier `bvSliceLenActual` was synthesized under the
governed `toOpenArray` hit, the solver query came back SAT with the model binding `e = 4`, the
replay-confirmed disproof reached the node terminal, the stamped harness — compiled **out of tree**
against the subject's own `libp2p/utils/bytesview.nim` — observed the template's real length (**3**)
where the adopted law demands **4**, so the replay agreed (`rvAgree`) and the 13-record BUG_FOUND
payload was assembled; the node terminated `failed` and the process exited **1**
(VERIFICATION_FAILURE). The control carrier `bvSliceLenControl` stayed **UNSAT** in the same batch
(no counterexample, no subject execution). The subject tree was byte-identical pre↔post.

| stage | observation |
|---|---|
| overlay adoption | `config/spec/nim_libp2p_bytesview_slice.json` loaded through the `soExplicit` path; the domain `1 <= e <= 5`, the two carrier models and the four law/defect definitions validated (6 clauses, closed grammar); the subject pin verified against the module bytes under the subject root (sha256 `b205c969…e5ee`); a present-but-malformed overlay fails closed |
| synthesis | both carriers synthesized — `bvSliceLenActual` (model `(bvsub e:BitVec 64 1)`) + `bvSliceLenControl` (model `(bvadd e:BitVec 64 1)`), `domain=1<=e<=5`, `obligations=3/3`, `eligible=true/true`, `source=libp2p/utils/bytesview.nim` (d1/d2 stderr line 5) |
| solver | defect **SAT** — the model bound `e = 4` (`input.e=4`); control **UNSAT** — no counterexample, the control's claim row is `clProved` and carries no `counterExample` |
| P4 promotion | the replay-confirmed disproof reached the node terminal (the P4 carve-out in `loop_driver.nim` keeps a replay-confirmed disproof out of the fatal pre-sieve branch; without it the node would have terminated `pre-sieved` and the exit rule would never have seen the failure) → claim row `clDisproved`, node report `failed` |
| replay | `[INFO] ir_pipeline_runner: [ce-replay] bvSliceLenActual — replay agreed; BUG_FOUND payload assembled (13 records)` — the stamped harness observed length **3** where the law demands **4** (`rvAgree`) |
| payload | 13 records — `input.e=4` · `propertyViolated=(= result e)` · `replay.verdict=rvAgree` · `replay.exitCode=0` · `replay.subjectGitRef=a130a7f32…` · `replay.treeMerkle=ec4a0c7e…` · `replay.moduleSha256 == replay.moduleSha256AfterRun == b205c969…e5ee` · `replay.porcelainClean=true` · `replay.nimVersion=Nim Compiler Version 2.2.10 [Linux: amd64]` · `replay.nimHash=d955005687bea4d3ca6c5813792789987405343a1e8b8c0a8b3a22b9c23936cf` · `replay.stdlibHash=` (empty) · `replay.hostPlatform=linux-amd64` |
| claim | `claimOutcome=clDisproved` · `claimId=fd6286fef96b33aa56a15176a292a8f3bd5d545cf37df149a918b0a9678eee79` · `evidenceId=c615690c1ad7e46f04c438f280329564d5eefff65ec633e2702ddd2bba492867` · `obligationId=obl:d2c44f569ef61e349a915582c4237b1b747df4d30a4701712178655bdd5bc44e` · `specificationId=697f2bda4207b53db8ef36f2d8fa088877d0e9c74956718ce795d2b8631c1a4f` |
| manifest rows | `toOpenArray` → `certRed` (solverMethod `smCLI`, irHash `7f3aa1aed6224ab6f8681ab9167beefdbcc0a6f9ffa13f6e3ed361cf1424b2e8`) · `bvSliceLenControl` → `certZ3Candidate` (solverMethod `smCLI`, irHash `9ce83016bc32b7a0ff4701ddeb04df4982b7cce8f293c569f935d05cccdda2b4`, **no** `certRed`) |
| node terminal | `libp2p/utils/bytesview.nim::toOpenArray — failed` (node report `status: failed`, `assuranceTier: unknown`; `statusCounts.failed=1`, `statusCounts.pre_sieved=0` — not a pre-sieve swallow) |
| summary | `summary.failedCount = 1` · `runOutcome.verdict = FAIL` · `gateVerdict = FAIL` · `executionComplete = true` · `runAccounting.proofFailedCount = 1` |
| process exit | exit 1 (VERIFICATION_FAILURE) |

### Determinism (independent cold state dirs)

| projection | d1 | d2 | equal |
|---|---|---|---|
| `canonicalRunDigest` | `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590` | same | **equal** |
| `runAccountingDigest` | `a8b56f0a9be3645377ce3a8e8d1e5129ba268d8c308f7eefa3d676e94367899d` | same | **equal** |
| `runOutcomeDigest` | `d9b254d4d834cea34e2aed3c4e3986e5308d0588f648fc102c24e60ab2a354e9` | same | **equal** |
| claim map + 13-record payload | the same 13 records, the same `claimId`/`evidenceId`/`obligationId`/`specificationId` | same | **byte-equal** |
| evidence CAS | 10 files/leg — the same names and the same digests | same | **byte-identical** |
| exit | 1 | 1 | **equal** |

Scope caveat: the three digests cover **run-accounting shape** (waves/terminals/counts), not payload
bytes; payload identity is established separately by the claim map + CAS comparison. Determinism is
claimed for the **same fixed environment** only (same toolchain, same nimble store, same binary,
same subject tree).

## Evidence

- **Subject fixation** — re-measurable with the commands in `INTEGRITY.md`; the pins are the
  `PROJECT_REVISION` row of the identity header.
- **The adopted claim** — `config/spec/nim_libp2p_bytesview_slice.json`
  (`canonicalSpecIR`, 6 clauses) + `docs/spec/nim_libp2p_bytesview_slice_contract.md` §§1–3.
- **The judgment execution** — `bin/ax prove --project <subject> --target "libp2p/utils/bytesview.nim::toOpenArray"`;
  stderr `[ce-replay] …` line; `ax_proof_state.json` `nodeReports`/`summary`/`runOutcome`;
  `ax_prove_trajectory.jsonl` claim rows (`unitEvidenceRefs`).
- **The payload** — the 13-record `counterExample` in the trajectory claim map (the canonical home
  of the payload in the Nim lane) + the vault manifest rows.
- **The investigation chain** — `experiments/nim-libp2p-bytesview-slice-e2e/discovery/` (15 verbatim
  session records, sha256-pinned in `discovery/INDEX.md`).
- **The engine change** — `src/cli/axiom_engine.nim` (+736, commit `7d8856dd5`) and the P4 disproof
  carve-out in `src/verification/batch_uap/loop_driver.nim` (commit `6da2f8792`).
- **The landing** — PR #1043 → merge commit `801a12be69f7f82f6792e31ccc5757cbc7a48364` (native
  2-parent MERGE, parents `6e45b7167` + `efde23cc4`); required checks 5/5 PASS; merge-queue
  admission-gate group run `39757132531` success; landing observed TERMINAL_SUCCESS. The mid-flight
  `REJECTED:POLICY_RULESET_MISMATCH` episode and its `efde23cc4` resolution are recorded in the
  landing record above.
- **The unit suites** — `tests/unit/test_libp2p_bytesview_binding.nim` (4 suites / 37 cases),
  `tests/unit/batch_uap_orchestrator_test.nim` (2 new carve-out cases).

## 3-axis separation

| axis | value | authority |
|---|---|---|
| subject verdict | **BUG_FOUND** for the adopted claim — the inclusive law is violated at b = 1: the observed length is **3** where the law demands **4** (`rvAgree`, 13-record payload) | this record (the payload + the adopted overlay) |
| process exit | **1** (`VERIFICATION_FAILURE`) | `cli_outcome.nim` — a single mapping (`failedCount > 0`) |
| PR merge OID | PR-A (code) = `801a12be69f7f82f6792e31ccc5757cbc7a48364` (PR #1043, merged 2026-10-22T09:58:24Z, native 2-parent MERGE, 5/5 required checks PASS, landing observed TERMINAL_SUCCESS) · PR-B (this record) = **not yet assigned** — the merge OID is minted by GitHub at merge time and this record is written **before** the PR-B merge, so no OID exists to cite; the branch tip at writing is `801a12be6` + this record's commits; merge authority is GitHub | GitHub |

## Classification

`Verified` — the enforcement record of a committed product contract's acceptance criteria
(`SPEC-LIBP2P-BV-SLICE`, `docs/spec/nim_libp2p_bytesview_slice_contract.md`): the frozen judgment
table's PASS row is machine-observed (verdict, 13-record payload, determinism digests, exit code,
Zero-Footprint), and the subject-level BUG_FOUND is carried by the payload — not asserted by this
record.

## Interpretation

What the evidence establishes:

- The adopted slice-length law is **disproved** at `b = 1` under the pinned subject bytes, and the
  disproof is **replay-confirmed on the ORIGINAL template** — the observation, not the model,
  decided the agreement.
- The control stayed UNSAT ⇒ the spec injection (β-splice, precondition binding, body marshaling)
  was wired correctly; a control SAT would have indicted the injection, not the subject.
- The subject tree was untouched (Zero-Footprint intact) and the observation reproduced across two
  cold state dirs in the same fixed environment.

## Non-Conclusions

- **NOT a claim about arbitrary `(b, e)`** — the carriers fix `b` (1 for the defect, 0 for the
  control) and bound `e` to `1..5`.
- **NOT a claim about the subject's `b = 0` runtime behavior** — the control is a solver-level
  injection guard; the subject is never executed for it.
- **NOT a claim that the pipeline extracted or verified the original template body** — the carriers
  are CONSTRUCTED IR; the subject connection is the stamped replay harness observation only.
- **NOT a general theorem about `BytesView.toOpenArray`** — it is not a statement about
  nim-libp2p's overall correctness, safety, or memory safety.
- **NOT a claim that nim-libp2p was modified or annotated in-tree** (Zero-Footprint) — the fix
  decision belongs to the subject's maintainers.
- **NOT a fully-autonomous proposition discovery** — the rule's justification was established by
  external investigation and adopted by an explicit, user-approved act; the content was authored by
  the investigation agent chain, and **authorship confers no authority**.
- **NOT a claim that the replay validates the general law** — it observes ONE pinned instance on
  the pinned subject bytes.

## Next Experiment

The smallest useful next experiment: **the upstream notification** (candidate 1 below) — the defect is
in a READ-ONLY external subject, so the fix decision belongs to `status-im/nim-libp2p`'s
maintainers, and this record is the reproducible evidence for that report. It requires no Axiom-side
change and no new contract on the Axiom side. Candidates 2 and 3 each require a committed contract
amendment before execution (AGENTS.md §0.12) and are therefore not the next experiment.

Candidates (each requires a committed contract amendment before execution, per AGENTS.md §0.12):

1. **Upstream notification** — the defect is in a READ-ONLY external subject; the maintainers of
   `status-im/nim-libp2p` decide whether to fix `toOpenArray`. This record is the reproducible
   evidence for that report; no Axiom-side action follows without a new contract.
2. **The `b = 2` instance** — the current defect carrier pins `b = 1` (the single-parameter replay
   contract forbids binding two indices). A `b = 2` carrier would need the same narrowing treatment
   and a new overlay generation; it is not a claim of this record.
3. **The parallel batch path** — the P4 disproof carve-out is implemented only in the sequential
   per-depth node loop; the parallel path (`AXIOM_PROVE_WORKERS > 1`) carries no `irResultMap`, so
   the equivalent contract would require plumbing the IR results into that context (a separate
   change, out of this slice's scope).
