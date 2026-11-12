# FROZEN acceptance run — generic Nim sidecar adapter end-to-end (SPEC-B36-SIDECAR)

> **Status**: FROZEN before the first judged execution. This file records the identity,
> pins, frozen prompt/known-answers, expected outcomes, and the judgment table for the
> sidecar-adoption end-to-end acceptance run on current `main`. No run output may alter
> these records; deviations are reported as-is in `ACCEPTANCE.md`.
> **Created**: 2026-10-19 (run day)
> **Contract**: [docs/spec/nim_stew_base36_sidecar_contract.md](../../docs/spec/nim_stew_base36_sidecar_contract.md)
> **Related precedent**: [nim_stew_base36_cout_slice_2026-10-10.md](../../docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md) (C_out authority + attach precedent)

## 1. Build identity (Axiom side)

| item | value |
|---|---|
| branch | `main` (after `git checkout main && git pull`) |
| HEAD commit | `00bb8334c312736922a3a41fb4033b6da755eb1d` — `Merge pull request #938 from Archright/followup/sidecar-adoption-binding` (2026-10-19 07:17:35 +0000) |
| `bin/ax` sha256 | `79b580e41ce73d1922d77c47e719c3044248ddcb4b9a000fa67290072b5334c0` (sha16 `79b580e41ce73d19`) |
| build cmd | `make build` (Nim 2.2.10, `-d:allowMissingZ3` compile flag per Makefile; z3 linked at runtime) |
| Nim | Nim Compiler Version 2.2.10 [Linux: amd64] |
| Z3 | Z3 version 4.13.3 - 64 bit |
| tracked tree | `git status --porcelain` EMPTY at freeze (the `bin/ax scope lock` regen was attempted once, reordered `kernel_symbols` only (same 40-set), and was `git restore`d — the committed `data/verification_scope.lock` bytes are used for state-dir seeding instead; no tracked file is modified in this run) |

## 2. Subject pin (Zero-Footprint — READ-ONLY)

| item | value |
|---|---|
| repo | `status-im/nim-stew` (stew 0.5.0) |
| commit | `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` |
| governed module | `stew/base36.nim` |
| module blob sha256 | `b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8` |
| governed symbol | `decodedLength` (`func decodedLength*(btype: typedesc[Base36Types], length: int): int`, body `(length * 179) div 277`) |
| clone used | `/tmp/sidecar_probe/nim-stew` — write-verified (`chmod`-denied tree: dirs `r-xr-xr-x`, files `r--r--r--`; probe `touch` → EACCES), porcelain-clean, pin re-verified at freeze |
| write protection | tree is read-only for the WHOLE run; any write attempt = integrity FAIL |

## 3. Sidecar pin

| item | value |
|---|---|
| file | `config/spec/nim_stew_base36_sidecar.json` |
| file sha256 | `cfe56be4737cabcd975798f7dd8de951ecf106244e0b46ad9957bff176226baf` |
| contract doc | `docs/spec/nim_stew_base36_sidecar_contract.md` |
| contract doc sha256 | `fed2a4b40a289ffff7a9c5bde6a2b5c149248ab0673390e863b4c16c0b23a69e` |
| specId | `SPEC-B36-SIDECAR` |
| ruleId / ruleVersion | `external:stew/base36/sidecar-adoption` / `1.0.0` |
| specOrigin | `soExplicit` (pinned by `explicitSpecFromOverlay`; any other origin fails closed) |
| grammar version | `nim-sidecar-expr-v1` (closed grammar: `+`, `==`, parens, `result`/value-param idents, non-negative int literals only) |
| adoptedSpecHash | `8e9564842090127b261c30fdd95db095957ad2628fb5a35e4c4016673441e3be` (loader recomputes SpecID over loaded `canonicalSpecIR` ∪ {origin, ruleVersion} and fails closed on mismatch) |
| canonicalSpecIR | `["length == 3", "result == 2", "length == 2", "result == 1"]` |
| propositions | defect `pre length == 3, post result == 2`; control `pre length == 2, post result == 1` |
| subject pin inside adoption | `commit 1853f20b…`, `blobSha256 b8a42a6a…` (hash-bound, fail-closed) |

## 4. Frozen blind-agent protocol (agents run SEPARATELY; outputs appended later)

The acceptance run itself is NOT the blind leg. The frozen prompt/template below is
pinned here BEFORE any blind agent output exists; blind outputs will be APPENDED to
this record when their runs land (section marker `## APPENDED BLIND OUTPUTS` in
`ACCEPTANCE.md`). Nothing in this run may be edited after an append.

### 4.1 Frozen prompt template (verbatim — no substitution permitted)

```
You are given a Nim module from the nim-stew library at commit
1853f20bdfeda61331a0b7e02f7aace0e88a0dfe (file stew/base36.nim).

Task: review the module and report any functional defect you can find, with:
1. the exact symbol and input that triggers it,
2. the observed vs expected value,
3. a minimal reproducing input, and
4. a severity label (info/warning/critical).

You may read any file in the provided module directory and run the module's
own test suite. You must not modify any file. Report only defects you can
demonstrate with a concrete input; do not speculate about style or API design.
```

### 4.2 Frozen tool scope

- READ access to the subject module directory only (the module, its siblings, and its test suite).
- MAY compile/run the module's own `nimble test` or a scratch harness OUTSIDE the subject tree (Zero-Footprint: no writes into the subject tree).
- NO access to Axiom sources, spec overlays, prior C_out evidence, this experiment dir, or any prior defect report on base36.
- NO internet access; no package installs beyond the pinned Nim 2.2.10 toolchain.

### 4.3 Hidden known-answer list (held by the experiment, not disclosed to blind agents)

| # | known answer | source |
|---|---|---|
| K1 | `decodedLength` UNDER-ESTIMATES: for `length == 3` the true encoded size is 2 bytes but the function returns 1 (counterexample witness `decode("kzz")` → outlen 2, dl 1) | **KNOWN-ANSWER OVERLAP** — the 2026-10-10 C_out slice measured the identical defect (`docs/evidence/nim_stew_base36_cout_slice_2026-10-10.md`: `dl(3)=1` vs `outlen=2`) |
| K2 | `decodedLength(2)` returns 1 and is correct (control instance; `decode("k0")` 1 byte) | same slice, control arm |
| K3 | Grammar-outside proposition forms (`*`, `-`, `<`, calls, negative literals) are REJECTED by the sidecar loader, never parsed | `tests/unit/test_sidecar_binding.nim` (42 tests) |

**Disclosure (recorded at freeze)**: K1 is a KNOWN-ANSWER OVERLAP with the
2026-10-10 C_out slice — the same defect instance was already measured and
committed to this repository's evidence history. Blind agents are not given
this record (tool scope §4.2 excludes it), but any overlap found by a blind
agent is NOT independent discovery relative to the project's own history; it
is a reproduction of K1. This disclosure exists so the appended blind outputs
are scored with correct provenance. Non-overlap (a defect K1–K3 do not cover)
would be genuinely new evidence.

## 5. Expected outcomes (frozen before execution)

| leg | expected machine observation |
|---|---|
| defect run (`ax prove --project /tmp/sidecar_probe/nim-stew --target "stew/base36.nim::decodedLength"`, fresh state_d1/vault_d1) | sidecar overlay accepted; BOTH carriers synthesized (`decodedLength_sidecar_defect` wave-faced under the examined symbol + `decodedLength_sidecar_control` under its own name); defect solver SAT (model binds length=3) → P4 `cvConfirmed` → `vsDisproved` → replay calls `decodedLength(Base36Types, 3)`, observes `1`, claim `1 == 2` fails → `propertyHolds == false`, `replay.verdict=rvAgree` → BUG_FOUND payload (`[ce-replay] … BUG_FOUND payload assembled`) → node `failed` → exit 1 |
| cold rerun (state_d2/vault_d2, same command) | identical canonical projections; `canonicalRunDigest` (state logs) EQUAL to run d1 |
| control (in-run; both carriers synthesize under the single governed decodedLength hit) | control carrier solver **UNSAT** (injection guard) — recorded from trajectory/manifest rows of the same run; `--target` isolation of the control carrier alone is NOT assumed |
| unsupported | `nim r tests/unit/test_sidecar_binding.nim` — grammar-outside rejection tests PASS (loader fail-closed); hash-mismatch adoption tests PASS (fail-closed on `adoptedSpecHash` mismatch) |
| subject integrity | full-file sha256 manifest of the clone identical pre↔post (byte-for-byte); `git rev-parse` unchanged; porcelain clean at both ends |
| determinism | `canonicalRunDigest` d1 == d2 (MATCH) |

## 6. Judgment table (frozen before execution)

| observation | verdict |
|---|---|
| defect observed end-to-end (SAT → replay disagreement → BUG_FOUND payload, exit 1, subject untouched) | **PASS** |
| adapter-only: sidecar loads/synthesizes but no replayed subject execution behind the verdict (no `[ce-replay]` agreement on a real call) | **INCOMPLETE** |
| control false-positive: control carrier SAT (injection guard fails) | **FAIL** |
| unsupported confirmed: grammar-outside or hash-mismatch proposition content accepted by the loader | **FAIL** |
| digest change: any byte of the subject clone differs pre↔post (or pin/blob sha mismatch) | **FAIL** |

## 7. Frozen execution procedure (the command sequence is part of the freeze)

1. Pre manifest: `cd /tmp/sidecar_probe/nim-stew && find . -path ./.git -prune -o -type f -print | sort | xargs sha256sum > /tmp/subject_tree_pre.sha256`; record `git rev-parse HEAD`, `git status --porcelain`, and the manifest file's own sha256.
2. Defect leg d1: `mkdir -p <exp>/state_d1/data && cp data/verification_scope.lock <exp>/state_d1/data/` (scope-lock seeding from the COMMITTED file — the regen path is not byte-idempotent, see §1), then `AXIOM_STATE_DIR=<exp>/state_d1 AXIOM_PROVE_VAULT_DIR=<exp>/vault_d1 bin/ax prove --project /tmp/sidecar_probe/nim-stew --target "stew/base36.nim::decodedLength"`; capture stdout/stderr/exit.
3. Defect leg d2 (COLD): fresh `state_d2`/`vault_d2`, seeded the same way, identical command.
4. Control evidence: extracted from the SAME runs' trajectory/manifest rows (control carrier under its own name).
5. Unsupported leg: `nim r tests/unit/test_sidecar_binding.nim`; quote grammar-outside + hash-mismatch rejection test names/results.
6. Post manifest: same as step 1 → `/tmp/subject_tree_post.sha256`; byte compare; `INTEGRITY.md`.
7. Determinism: compare `canonicalRunDigest` d1 vs d2.
8. `ACCEPTANCE.md` verdict; logs preserved under `runs/`; `state*/`, `vault*/`, `runs*/` gitignored by the experiment-local `.gitignore`.
