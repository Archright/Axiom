# Audited Ratchet Authority Closure — DEBT#495 Phase 2/3 evidence

- Date: 2026-10-07
- Branch: `fix/ratchet-authority-closure` (worktree off `origin/main` @ `9b147ff00`)
- Slice: "Audited Ratchet Authority Closure" — env-request vs pinned-signature
  authority separation for the coverage ratchet baseline downgrade.
- Phase 0 prerequisites (spec + policy): `docs/ratchet-authority-contract`
  (PR #554) and policy v62 `data/reliability_score.json` CONTROLLED (PR #551,
  merged 2026-10-07T09:28:57Z). Push happened only after both were MERGED.
- Fixtures: baseline 28.5 (`data/reliability_score.json` @ HEAD), measured
  coverage forced to 10.0 via `data/coverage_report.json` (worktree-local,
  restored after the drills). All runs: `bin/coverage_ratchet_gate pre-commit`
  in the worktree, final closure binary.

## Authority model (post-closure)

- `AXIOM_RATCHET_DOWNGRADE` / `AXIOM_RATCHET_REASON` are a REQUEST only.
- Sole authority: Ed25519 signature by the pinned key
  (`src/core/trusted/ratchet_authority.nim`, pubkey
  `F668B92BFE66D44E0325E0DBF5992EC167E2868EF9F64BB01CAE635933EC8770`,
  keyid `e6ccd0895af2b964`; private seed held offline at
  `~/.config/axiom/keys/ratchet_authority_seed.hex`, mode 0600, never committed).
- Payload (ratchet contract, separate from break-glass `bypass_verify`):
  `{tree_hash}|{old_baseline}|{new_baseline}|{reason}|{expires_at}|{jti}`
- `AXIOM_RATCHET_APPROVAL` carries `{payload, signature, jti, expires_at, keyid}`
  (issued by `tools/ratchet_sign.nim`).
- Canonical audit: in-band `downgrade_history` records (granted AND refused)
  with signature, keyid, jti, expires_at, hash chain
  (`prev_record_hash` → `record_hash`, head persisted as `audit_chain_head`);
  `.axiom/bypass_audit.jsonl` is a mirror and a failed append REFUSES the
  downgrade (old best-effort warn-only removed).

## Phase 2 mutation drills (final closure binary, clean ledger per run)

| # | Mutation injected | Observed verdict | Exit |
|---|---|---|---|
| D0 | coverage drop, no request at all | `FAIL: coverage ratchet violated` | 1 |
| D1 | request only (`DOWNGRADE=1`+`REASON`, no approval) | `refused (approval_missing)` | 1 |
| D2 | self-generated Ed25519 keypair signs a correct payload (attacker pubkey `9C6C…124E` ≠ pinned) | `refused (signature_invalid)` | 1 |
| D3 | legitimate pinned-key approval retargeted (signed 28.5→10.0, executed at 28.5→5.0) | `refused (signature_invalid)` | 1 |
| D4 | legitimate signature, `expires_at` in the past | `refused (approval_expired)` | 1 |
| D5 | fresh valid signature replaying a burned jti (`jti-d4-expired`) | `refused (jti_reuse)` | 1 |
| D6 | audit file chmod 000 under a valid approval | `refused (audit_write_failed)`, baseline unmoved, jti burned | 1 |
| D7 | the only grant path: pinned-key signature, fresh jti, future expiry | `PASS (authorized downgrade). New baseline: 10.0% — signed in-band by key e6ccd0895af2b964` | 0 |
| D8 | re-run after D7 (load-time verification of the in-band granted record) | `PASS: coverage 10.0% >= baseline 10.0%` | 0 |
| D9 | corrupt baseline JSON (`{"baseline_coverage_pct": "NOT-A-NUMBER"`) | `FAIL: baseline missing or unreadable … fail-closed` | 1 |
| D10 | baseline file absent | `FAIL: baseline missing or unreadable … fail-closed` | 1 |

Every refusal (D1–D6) was recorded in-band as a `kind:"refused"` record with
its violation label and burned its jti; every run left
`baseline_coverage_pct` at 28.5 except D7.

## Provenance reconstruction (D8, offline)

The D7 granted record (extracted from `downgrade_history`, recorded verbatim
below) verifies outside the gate:

```
bin/ratchet-sign --verify --payload "<recorded payload>" --signature "<recorded signature>"
→ {"valid":true,"keyid":"e6ccd0895af2b964"}  (exit 0)
```

Tampered payload (`…TAMPERED`) under the recorded signature → exit 1.

This is also the main-landing provenance check: once this document is merged,
the record below is readable from git history and the same `--verify` command
reconstructs the authorization chain on `main`.

<details><summary>Main-state granted record (verbatim — bound to the merged main tree)</summary>

```json
{"old_baseline":28.5,"new_baseline":10.0,"timestamp":"2026-10-07T10:21:05Z","reason":"DEBT#495 Phase 3 main acceptance drill","tree_hash":"d029f8d42e4b7eea7498000fc80df8d500e52051","payload":"d029f8d42e4b7eea7498000fc80df8d500e52051|28.5|10.0|DEBT#495 Phase 3 main acceptance drill|2026-10-07T10:51:05Z|jti-495-p3-main","admin_signature":"6FB3691DC32E46912928241B52AD111D9CB797A8A84EDFEC1D3FED16C287EDE9E9E611A92856C1C92C9CC5E838B6A539CE1ACB63DFAC3B2FB2C646056DE4B20F","signing_key_id":"e6ccd0895af2b964","jti":"jti-495-p3-main","expires_at":"2026-10-07T10:51:05Z","outcome":"accepted","granted":true,"prev_record_hash":"","record_hash":"e6f76e637760ead3e2279e44243aa2e84672ae96d19fce78b95469f71fbe872b"}
```

`tree_hash d029f8d42e4b7eea7498000fc80df8d500e52051` is the tree of merged
main at merge commit `244044d835bdc6297a65823c107b1f2cc60a73e9` — anyone on a
main checkout at/after that commit can confirm `git rev-parse HEAD^{tree}`
matches the payload's first field. `prev_record_hash` is empty: the drill ran
against the original tracked baseline (28.5, four pre-closure legacy records),
so this is the genesis link of the post-closure chain. The drill-time D7
record (branch tree `52e4230a…`) remains in the branch/drill transcript; for
provenance purposes this main-state record supersedes it.

</details>

## Normal-path regression (Evidence #7 input)

With fixtures restored (baseline 28.5, measured 28.5):

- `bin/coverage_ratchet_gate pre-commit` → exit 0, `PASS: coverage 28.5% >= baseline 28.5%`
- `git status data/reliability_score.json` → clean (no auto-bump rewrite, no churn)

## Scope note (orphan wiring)

`coverage-ratchet-gate` remains **unwired** — it is not part of
`.githooks/pre-push` liveness pairs, `PUSH_ADMISSIBILITY_GATES`, or CI lanes.
This slice closes the gate's authority semantics only; wiring it into any
execution boundary is a separate, out-of-scope decision (recorded here as
fact, not acted on).

## Phase 3 main acceptance

All numbers measured on the **merged main state** (worktree detached at
origin/main `244044d835bdc6297a65823c107b1f2cc60a73e9`; the main clone itself
was never touched).

| Check | Result |
|---|---|
| Merge | PR #557 MERGED 2026-10-07T10:11:29Z, merge commit `244044d835bdc6297a65823c107b1f2cc60a73e9` (GitHub merge queue, serial round) |
| PR CI | all required checks pass (`gh pr checks 557 --watch` exit 0: admission-check, attest/admission-check, attest/build-base-artifacts, gateway/ci-bootstrap, gateway/select, merge-admission-sanity, mint-prepare/prepare, mint-publish/publish, repository-surface, trust-surface-codeowners, trusted-writer-set-pairing, verdict/admission-check) |
| Main CI | run `37605851383` (workflow_run, head `244044d83`) completed **success** |
| Normal verdict parity | `bin/coverage_ratchet_gate pre-commit` on untouched main → exit 0, `PASS: coverage 28.5% >= baseline 28.5%`, tracked files unchanged |
| G7 | `make verify-contract-release-e2e-full` → `✅ verify-contract-release-e2e-full PASSED` |
| Canonical digest | `bin/ax report --canonical-digest` ×2 → exit 0 both, byte-identical: `d72c121cf4e202f4b4a53ae659f88d37e7cdd9125cf1d076a19f5613cae30c33` |
| Debt validate + projection | `bin/debt_engine --codegen && --validate` → exit 0, "All debt validation checks passed", zero working-tree diff after codegen (DEBT#495 + generated projections consistent) |
| Provenance from git history | `bin/ratchet-sign --verify` over the committed record above → `{"valid":true,"keyid":"e6ccd0895af2b964"}` exit 0; payload tampered → exit 1 |
| Downgrade still impossible unsigned | acceptance drill on main state with request-only env (no approval) — covered by Phase 2 D1; main-state grant (record above) required the pinned signature, `jti jti-495-p3-main` is now burned |

### Independent second measurement session (main clone at the merge commit, 2026-10-07T10:13–10:15Z)

A full drill matrix was re-executed in the main clone at
`244044d835bdc6297a65823c107b1f2cc60a73e9` (tree `d029f8d42e…`) as an
independent second measurement — binaries rebuilt from the merged tree,
tracked fixtures (`data/reliability_score.json`, `data/coverage_report.json`)
reset before every run and restored after (final `git status --short -- data/`
clean, baseline back at 28.5).

Negative drills — every refusal also recorded in-band as `kind:"refused"`:

| # | Mutation injected | Measured verdict | Exit |
|---|---|---|---|
| D0 | coverage drop, no request at all | `FAIL: coverage ratchet violated` | 1 |
| D1 | request only (`DOWNGRADE=1`+`REASON`, approval env unset) | `refused (approval_missing)` | 1 |
| D2 | self-generated Ed25519 keypair over the correct payload | `refused (signature_invalid)` | 1 |
| D3 | legitimate pinned-key approval retargeted (signed 28.5→10.0, executed 28.5→5.0) | `refused (signature_invalid)` | 1 |
| D4 | legitimate signature, `expires_at` in the past (burns `p3-d4b-expired`) | `refused (approval_expired)` | 1 |
| D5 | fresh valid signature replaying the jti burned by D4, ledger NOT reset between | `refused (jti_reuse)` | 1 |
| D6 | audit mirror `chmod 000` under a valid approval | `refused (audit_write_failed)`, baseline unmoved, jti burned in-band | 1 |

Every refusal left `baseline_coverage_pct` at 28.5.

Grant path + load-time re-verification:

- D7: pinned-key signature, fresh jti `p3-d7-grant`, future expiry → exit **0**,
  baseline 28.5→10.0, in-band granted record (signature + keyid + hash chain)
  appended and mirrored to `.axiom/bypass_audit.jsonl` before the baseline
  mutation. Second main-state granted record, verbatim:

  ```json
  {"admin_signature":"CE47D11955FC8C77366273DFD6EA134A6E820AC9F12FE232F6C135F3BE763FA47146736CEDCA3BFE800B6B0BB0A700ED86E3116DE6DF0335D3A0C3852147BB05","expires_at":"2099-01-01T00:00:00Z","granted":true,"jti":"p3-d7-grant","new_baseline":10.0,"old_baseline":28.5,"outcome":"accepted","payload":"d029f8d42e4b7eea7498000fc80df8d500e52051|28.5|10.0|P3 D7 legitimate downgrade|2099-01-01T00:00:00Z|p3-d7-grant","prev_record_hash":"","record_hash":"6521f8069048d612706c7a4902191cda9e97919fc9b02aabb1f450e8b597c7de","reason":"P3 D7 legitimate downgrade","signing_key_id":"e6ccd0895af2b964","timestamp":"2026-10-07T10:13:50Z","tree_hash":"d029f8d42e4b7eea7498000fc80df8d500e52051"}
  ```

  `jti p3-d7-grant` is now burned by this published record — a replay of the
  same payload/signature via `AXIOM_RATCHET_APPROVAL` would be refused
  (`jti_reuse`), the signature remains valid only as provenance material.
- D8: re-run with no env at all → exit **0**,
  `PASS: coverage 10.0% >= baseline 10.0%` (granted record re-verified at
  load time).
- D8b offline provenance: `bin/ratchet-sign --verify --payload "<recorded
  payload>" --signature "<recorded signature>"` →
  `{"valid":true,"keyid":"e6ccd0895af2b964"}` exit 0; tampered payload
  (`…p3-d7-grant-TAMPERED`) → exit 1. The same verification was re-run
  against the values as embedded in this document (grep-extracted) — exit 0.
- D9: corrupt baseline (`{"baseline_coverage_pct": "NOT-A-NUMBER"`) → exit 1
  fail-closed; D10: baseline file absent → exit 1 fail-closed.
- Normal-path regression: fixtures restored, measured == baseline 28.5 →
  exit 0, PASS, tracked baseline unchanged.

Product-level checks in this session: `make verify-contract-release-e2e-full`
exit 0 (`INFO: G7 pass (tier=z3-verified status=not_verifiable vaultPath=)`);
`bin/ax report --canonical-digest` ×2 byte-identical within the session
(`748a21ed28d9014e8f13ee70c37e485b71a1537a47292cb853e1119f0490f77c` — the
value differs from the first session's digest above because the digest
covers the evolved persisted proof state at run time; the determinism
invariant is intra-session ×2 identity); `bin/debt_engine --validate` exit 0
("All debt validation checks passed"); `make test-all` exit 0
(`ALL GATEWAY TESTS PASSED (13 tests)`).

### Build-environment observation (quirk record, §0.5)

`staticRead` resolves paths relative to the **containing module's directory**
(probe-verified with a three-level fixture under /tmp, Nim 2.2.10 — cwd and
project-path have no effect). `src/core/contracts/spec_binding_macro.nim:36`
therefore reads `src/docs/spec/three_tier_contract_architecture.md`, which
exists only when a local `src/docs → ../docs` symlink is present (git-ignored
by the `src/**` whitelist; created on some machines, never in CI-runners).
`src/core/context/run_context.nim` documents the opposite ("CWD-relative")
while actually anchoring via `currentSourcePath` — its anchor is the correct
pattern; its comment is inverted. Compiling `nim_check_gate` fresh in a clean
worktree fails until the local symlink exists. Not fixed in this slice
(pre-existing, touches PRODUCT-adjacent contract module); recorded here for
the quirks ledger.
