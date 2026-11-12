# Phase C0 — Canonical Rebuild Baseline Acceptance

- Executed at: 2026-08-21T14:2xZ
- Baseline commit: `b24b3ab9779082080b92373ac9f86ff461ad95dc`
  (`fix(build): C0 canonical rebuild baseline`, parent `2004fcd31`)
- Method: real fresh clone at `/tmp/c03_fresh_clone` (clean tree, HEAD verified),
  canonical build + toolchain resolution + canonical execution.

## Results

| Step | Result | Evidence |
|---|---|---|
| Fresh clone, clean tree | PASS | `git status --porcelain` = 0 |
| lean-toolchain ×2 pin | PASS | both `leanprover/lean4:v4.33.0` |
| `lake env lean --version` | PASS | Lean 4.33.0 (elan toolchain d8b18978) |
| Canonical Nim build | PASS | `nim c -d:release src/cli/main.nim` exit 0 |
| bin/ax digest | recorded | `9bca5ff6aa44163b…84a5ad` |
| Canonical execution | PASS (engine ran end-to-end) | RC=2, see below |

C0.1 closure commits: `certificate_attestation.nim` (new) +
working versions of `certificate_types.nim`, `stage_08_reporter.nim`,
`verification_types.nim` — all required by the committed build closure.

## RC=2 decomposition (important)

The engine itself judged `clampTimeoutMs` **VACUOUS** ("cannot build negative
mutation") and attempted to persist `certNoObligation`. Persistence FAILED CLOSED:
the canonical slot `7e5a975f…json` is occupied by the **committed stale
certificate** (certZ3Verified, lean 4.29.0, empty leanProposition) whose canonical
identity differs for the same irHash. Fail-closed persistence behavior is CORRECT.

However the final report printed `verified=1/40 … [VERIFIED]` — produced by
hydrating the committed stale vault, not by fresh verification.

## NEW launch-critical finding (input to D1/C1)

**Polluted historical certificates are committed under
`src/verification/certificates/` and contaminate every fresh clone**: a clean
checkout ships a false `certZ3Verified` artifact which the engine hydrates and
reports as verified=1/40 even when its own fresh judgment is VACUOUS /
certNoObligation.

Required remediation (owner: next phase, needs explicit decision since these are
committed evidence artifacts):
1. Purge/reclassify stale `certZ3Verified` certificates from the tracked vault.
2. Hydration path must never count persisted statuses that fail current
   `isVerifiedCertificateStatus` semantics (Phase B already excludes
   certZ3Verified — verify the report counter path uses it).
3. Until done, R6 (runtime/evidence isolation) and R8 remain FAIL on any clone.

## Verdict

**C0 = PASS** (clean checkout + committed toolchain + canonical build/execution).
Carry-forward blockers recorded above; they gate D1/D2, not C0 completion.

---

# C0.4 Completion Addendum (2026-08-22)

Historical certificate purge/reclassification + hydration closure: DONE.

Commits:
- `7c6641b19` — vault reclassification (4× certZ3Verified → certZ3Candidate,
  attestations preserved, reason=reclassified:migration, no re-validation) +
  hydration closure (isVerifiedCertificateStatus excludes certZ3Verified;
  proof_state_builder/certificate_verifier/baseline_snapshot_core demoted).
- `097942dc5` — closed the residual second authority path: loop_driver derived
  isProven from provenLayer (solver success) instead of Lean kernel acceptance;
  cache-hit/type-directed/Z3-only paths demoted to orchestrationProofFailed.

Clean-clone acceptance at 7c6641b19+fix (/tmp/c04_verify):
- fresh `ax prove --target clampTimeoutMs` → **verified=0/40**, honest
  VACUOUS/FAILED for the target; persist fail-closed against identity conflict.
- invariant now enforced end-to-end:
  certZ3Verified/provenLayer-solver-success → verified : FORBIDDEN
- unit tests green (evidence_truth_boundary 30/30, authority, calculus,
  batch_uap_orchestrator).

Known carry-forward: orchestrator_vault still persists historical
orchestrationVerified statuses written before this fix (data migration,
tracked for D1); claimsDir claim-authoritative hydration branch bypasses
certificate status checks and needs D1 negative coverage.

**C0 = CLOSED. Next: C1 Identity / Execution Closure.**
