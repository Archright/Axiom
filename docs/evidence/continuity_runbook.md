# Certification-Continuity Production Runbook

> Machine-checkable operator runbook for the certification-continuity vertical
> slice (contract: `docs/spec/certification_continuity_contract.md`):
> **PR → (local gates + PR review) → subject (base, head) → trusted attest
> (mint + artifact handoff) → admission → ledger publication (single trusted
> writer, post-verdict) → GitHub native MERGE (`ax merge --apply`) → continuity
> → main green**.
>
> **CI=0 (2026-09-20 cutover)**: 원격 CI 워크플로(Hetzner 러너)는 제거되었으므로
> 아래 workflow 기반 경로(`auto_merge.yml`, `merge_continuity.yml`, GHA
> artifact)는 더 이상 실행되지 않는다 — 로컬 게이트 + `ax merge --apply` + 인증서
> 원장이 유일한 경로. 단락은 계약·절차 SSOT로 유지한다.
>
> **Model B (2026-09-11)**: the synthetic-candidate path (materialize M →
> subject(M) → exact-M FF-CAS publication) is superseded by GitHub native
> MERGE landing — Axiom no longer owns candidate construction or publication.
> The certified subject is the merge INPUT state (baseSha, headSha); the
> merge commit itself is constructed by GitHub and verified post-landing by
> the continuity predicate (parent1/parent2/tree digest). The legacy
> materialize/subject/publish sections below are retained as historical
> reference only.
>
> Every command below is the SANCTIONED production path (`bin/ax`, built from
> main). All artifacts are recorded in the evidence bundle
> `docs/evidence/certification_continuity_production_2026-09-10.md` (git add -f;
> `docs/evidence/` is gitignored by repo convention).

## 0. Prerequisites

- `bin/ax` built from **current main** (`make ci-bootstrap`); `GITHUB_TOKEN` set
  (e.g. `GITHUB_TOKEN=$(gh auth token)`); repo `Archright/Axiom` (override:
  `AXIOM_REPO`).
- Toolchain pins: Nim 2.2.10, Lean 4.33.0 (elan), Z3 4.13.3 (checksum-pinned in
  `data/policy/z3_binary_checksums.json`), `proofs/.lake/build/bin/ircheck` built
  (`cd proofs && lake build ircheck`).
- A PR whose head commit contains the certified-subset candidate function.

## 1. Materialize (Phase 1 — deterministic merge candidate chain)

```bash
AXIOM_MAIN_SHA=$(git ls-remote origin main | cut -f1)
GITHUB_TOKEN=$(gh auth token) bin/ax merge materialize --pr <PR> \
  --base "$AXIOM_MAIN_SHA"
```

- Records `merge-materialize` in `.axiom/gate_history.jsonl`: chain tip `M`
  (commit OID), tree OID, entries/dropped counts.
- If base moved since materialization, re-run with the new `AXIOM_MAIN_SHA`.
- Verify: chain tip OID is a descendant of current main and contains exactly the
  PR's commits (`collectChain`).

## 2. Subject (Phase 2 — certification subject of M)

```bash
GITHUB_TOKEN=$(gh auth token) bin/ax merge subject \
  --ref <candidateRef> --pr <PR> --base "$AXIOM_MAIN_SHA"
```

- Prints canonical JSON (`axiom.subject.v1`): `subjectId` (64 hex), binding
  `candidateCommit == M`, `treeDigest`, `baseSha == AXIOM_MAIN_SHA`, provenance.
- Persists append-only to `data/trusted/subjects/<subjectId>.json` (overwrite is
  refused fail-closed).

## 3. Extraction agreement (Phase 3.75 — Tier 2 per-run differential)

```bash
GITHUB_TOKEN=$(gh auth token) bin/ax merge agree \
  --ref <git-ref-of-candidate> --func <funcName> --file <modulePath>
```

- Runs the Nim canonical extractor AND the independent Lean reference extractor
  (`proofs/IR/ReferenceExtractor.lean` via `ircheck extract`); verdict
  `eaAgree` requires **byte-equal serialized IR** (both digests recorded).
- `EA_UNSUPPORTED` is fail-closed: the function/module must stay inside the
  certified-subset wire set (`src/verification/ast_wire.nim`). Modules
  containing out-of-subset constructs (strings, case, try/except, …) cannot
  certify ANY function in them — place certifiable functions in subset-only
  modules.

## 4. Evidence bundle (untrusted-tier verification record)

`data/trusted/evidence/<subjectId>.json` (schema `axiom.attestation.evidence.v1`):

| field | value | source |
|---|---|---|
| `schemaVersion` | `axiom.attestation.evidence.v1` | fixed |
| `subjectId` | from step 2 | `data/trusted/subjects/` |
| `prNumber` / `prHeadSha` | PR number / head SHA | GitHub |
| `chainEntries` / `chainDropped` | from step 1 journal | `.axiom/gate_history.jsonl` |
| `funcSource` / `funcPath` / `funcName` | EXACT module source at the candidate tree | `git show <head>:<path>` |
| `leanSource` | real Lean artifact (typechecks; axioms ⊆ INV-6 allowlist) | operator-derived from the function, verified by kernel re-execution |
| `smtlib2` | real SMT-LIB2 query (fresh z3 → **unsat**) | operator-derived from the function, verified by kernel re-execution |
| `policyDigest` | `sha256sum config/policy/merge_admission.json` | file bytes |
| `scopeDigest` | `sha256sum data/verification_scope.lock` | file bytes |
| `envDigest` | sha256 of the documented env identity wire | evidence bundle |
| `toolchainIdentity` | `nim-<v>\|lean-<v>\|z3-<v>` (pinned D2 identity) | `pinnedToolchainIdentity()` |

Nothing is fabricated: every re-executed input must be the actual artifact, and
the attestation chain RE-EXECUTES all of it.

## 5. Attest (Phase 4 — trusted Verify(E,M) chain)

```bash
GITHUB_TOKEN=$(gh auth token) bin/ax cert attest --ref <candidateRef> --pr <PR>
```

Chain stages (fail-closed, in order — each verdict recorded):
a. subject match (store reload, exact equality)
b. extraction agreement (`eaAgree` required)
c. kernel re-execution (fresh `lake env lean` typecheck + INV-6 axiom allowlist
   on `leanSource`; fresh checksum-pinned z3 on `smtlib2` → unsat)
d. policy digest == current file bytes
e. toolchain identity == pinned D2 identity
f. scope digest == current scope lock
g. mint (ALL PASS) → subject-continuity certificate (Ed25519-attested,
   journal-bound) at `data/trusted/certificates/<subjectId>.json`

Exit 0 ONLY at `atPassed` + certificate mint + journal record. **The attest
tier does NOT append the ledger** (ADR-0022 §4/D5 — attest holds
`contents: read`; the minted certificate leaves the tier as an immutable
artifact named `subject-certificate-<headSha>` — 원래 GitHub Actions
artifact였으나 CI=0 cutover, 2026-09-20 이후 로컬 mint 경로 유지), and the
journal records the delegation note
(`ledgerNote: publication delegated to the single trusted admission writer`).

## 6. Ledger publication (Phase 4 — side-ref ledger, INV-8)

**Production writer (exactly one — ADR-0022 §4/D5)**: `auto_merge.yml` — the
only `contents: write` holder. Publication is its POST-VERDICT commit
operation: after the admission verdict is mergeGo, it appends the certificate
artifact to the ledger and only then executes the native merge.
(CI=0 cutover, 2026-09-20로 workflow writer는 소멸 — 로컬 `ax merge --apply` +
D9 operator 경로가 production 경로.)

**Bootstrap/recovery writer**: the D9 operator credential, outside the
production path:

```bash
GITHUB_TOKEN=$(gh auth token) bin/ax cert ledger-append <certPath>
```

- Appends the certificate to `refs/heads/axiom/certificates` (FF-only append;
  commit message `axiom: certificate ledger append <certId>`); records the
  ledger tip SHA (the `ledgerTip` in the attestation journal).
- Fail-closed: no token or push failure → non-zero exit, nothing appended.

## 7. Admission dry-run (Phase 5 — certificate-continuity admission)

```bash
AXIOM_MAIN_SHA=$(git ls-remote origin main | cut -f1)
GITHUB_TOKEN=$(gh auth token) bin/ax merge --dry-run <PR> [--cert <certPath>]
```

- Legacy admission: required check-runs vs head SHA, change-graph facts, cert
  continuity pass (old path was additive until the §-1-pending cutover;
  check-runs/PR CI는 CI=0 cutover, 2026-09-20로 소멸).
- **Certificate source (ADR-0022 §4/D5, mint/publication split)**:
  `--cert <certPath>` consumes the attestation tier's artifact handoff —
  identical boundary verification (Ed25519 attestation + headSha binding) to
  the ledger scan; without it the side-ref ledger is scanned (bootstrap/
  recovery source). `NO_CERT` = no valid certificate for the evaluated head
  from EITHER source. The ledger publication is NOT an admission
  prerequisite — it is the single trusted writer's post-verdict commit.
- If check-runs are incomplete the verdict records `deny` — that was expected
  when the dry-run races the PR CI (CI=0 cutover 2026-09-20 이후 check-runs
  부재 시 deny 유지). The PUBLICATION path is cert-gated (contract
  §4.3) — admission dry-run and publication are distinct gate surfaces.

## 8. Publish (Phase 5 — exact-object FF-CAS, INV-2)

```bash
GITHUB_TOKEN=$(gh auth token) bin/ax merge publish --cert <certPath> --pr <PR>
```

1. cert re-verify (structural closure + kernel re-execution) → `CERT_INVALID` on
   any failure
2. policy/scope digest equality → `POLICY_MISMATCH` / `SCOPE_MISMATCH`
3. fetch origin main == `cert.baseSha` → `STALE_BASE` otherwise (re-materialize
   + re-attest onto current main)
4. re-materialize candidate from CURRENT main; tip must reproduce
   `cert.candidateCommit` → `SUBJECT_MISMATCH` otherwise (single-construction
   rule); side-ref ledger must hold the SAME certificate (`NO_CERT` /
   `CERT_INVALID`)
5. `publishM`: `git push origin <M>:refs/heads/main` — NON-FORCE; git refuses
   non-FF → `pubMainMoved`/`STALE_BASE`; post-push `ls-remote` must equal M
   → `pubPublished` (main SHA == M at the object level)
6. PR auto-close (REST), merge-publish journal record.

## 9. Continuity (Phase 5b — cheap post-merge identity check, I-2)

```bash
GITHUB_TOKEN=$(gh auth token) bin/ax cert continuity \
  --main <observed main SHA> --cert <ledger certificate path>
```

- `ccPassed` = observed main tip == certified M OID AND certificate valid
  (structural closure + Ed25519). It is an identity statement, NOT a fresh
  verification verdict — full-L2 backstop stays with nightly + attest chain.
- `github workflow run merge_continuity.yml` (retired 2026-09-18 — the
  reusable workflow was deleted; CI=0 cutover 2026-09-20로 워크플로 경로 자체가
  소멸), or the local `tools/ci/run_landing_continuity.sh` — `ccMismatch`/
  `ccNoCert`/`ccError` fail visibly.

## 10. Verification re-runs (machine-checkable)

- Everything is re-verifiable: re-run the exact commands above; every digest
  (policy/scope/evidence/tree/main) is byte-compared, every chain stage
  re-executed fresh. Journal SSOT: `.axiom/gate_history.jsonl` (gitignored by
  policy) — the evidence bundle must capture its records at run time.
