# Evidence CAS provenance nondeterminism — `bin/gate_hook` fail-closed incident (2026-10-06)

## What this record is

Incident record for the second Evidence CAS activation defect: record-level
artifact **provenance collection** was fail-closed over build artifacts whose
presence is runner-cache dependent, so the SAME tree + policy sometimes
produced a valid evidence record and sometimes an internal error — a
determinism violation (§0.2) that blocked every docs-only PR landing between
07:26Z and the fix. Machine evidence throughout; fix = #502
(`fix/evidence-cas-identity-determinism` @ `e0b9b18d0`).

## Timeline (all UTC, 2026-10-06)

| time | event |
|---|---|
| 07:12:59 | #498 pull_request attest **passes**: `AXIOM_EVIDENCE_CAS: MISS — produced + stored record e27a51c7e470` (workspace had the binary) |
| 07:26:47 | #498 merge_group attest **fails**: `cert_cli: attest --witness-only: FAILED — atInternalError: evidence CAS enabled: evidence_cas: file not found (fail-closed): bin/gate_hook` (run `37428943334`) |
| 07:32:59 | run `37428943334` admission-gate → **failure** (attest → mint-prepare/mint-publish/verdict cascade) |
| 07:33:24 | `github-merge-queue[bot]` **auto-dequeues** #498 (documented platform behavior) |
| 07:35:09 | #499 pull_request attest **fails identically** (run `37429923064`) — same tree shape, different workspace state |
| 09:48:18 | fix lands as **#502** — merge commit `22ae6bd3ce4c4f2f39b2a27fde514d09cb043f2c` (branch `fix/evidence-cas-identity-determinism`, head `e0b9b18d0`) |

## Root cause (proof-first, file:line)

Execution map of `ax cert attest --witness-only` (`src/cli/cert_cli.nim:828`
`runWitnessOnlyCli`):

1. `planEvidenceCas` → `planEvidenceCasWithTransport`
   (`attestation_orchestrator.nim:364`) → `collectEvidenceKeyInputs`
   (`evidence_cas.nim:499`) → `collectVerifierIdentityInputs` (:464) →
   `collectArtifactDigests` (:449) → fail-closed err at `evidence_cas.nim:348`
   — the incident site.
2. `ArtifactInputPaths` declared **6 build artifacts** including
   `("gate_hook", "bin/gate_hook")` (:109) — all untracked binaries existing
   only in built workspaces; presence depends on the B-cache payload
   (`ci-cache-publisher.yml:19-22` ships `bin/ax`, `install_ax_cas`,
   `ircheck`, manifest, nimcache — **deliberately NOT gate_hook /
   precompile_gates**, the J3 note) and `fail-on-cache-miss: false` restores.

Proof findings that sized the fix:

- **The evidence key never consumed artifact digests.** `verifierIdentityWire`
  (:243-250) hashes treeOID(B) + recipeDigest + nimPin + leanPin + z3Pin +
  policy/scope digests only. The failing digests are record-level provenance
  ("NOT identity" — `attestation_orchestrator.nim:333`, `evidence_ledger.nim:85`).
- **Exactly one member is executed by the witness path**: `ircheck`
  (`proofs/.lake/build/bin/ircheck`), resolved and executed by
  `extraction_agreement` at stage (b) on every fresh (casOff/casMiss)
  verification; its absence already fails stage (b) independently.
  `bin/gate_hook` executes only on the `ax gate run` pre-commit path
  (`gate_cli.nim:82-90`). HITs execute neither (:697-702) — so provenance
  collection was killing would-be-HIT runs the identity says are reusable.
- Semantic contradiction on record: `cas_index.nim:433` treats the same
  missing file as a deterministic empty-hash contribution.

## Fix (#502)

- Provenance set shrinks to the executed member:
  `ExecutedArtifactPaths = [("ircheck", "proofs/.lake/build/bin/ircheck")]`,
  fail-closed per member (`fileDigestHex` untouched).
- `verifierIdentityWire` / `EvidenceKeyScheme` **byte-identical (v1)** — no
  key-space change; previously minted 6-member records remain valid
  (`validateVerifierArtifactDigests` is name-agnostic; empty object explicitly
  valid, `evidence_ledger.nim:114`).
- Tests: T6 determinism (same inputs → same key + same successful casMiss
  plan with and without the 5 build-only binaries present — the exact
  incident workspace shape), T7 (missing ircheck → fail-closed).

## Related org-side incident (cross-reference)

Independently of the provenance defect, the runner cache `axiom-b-…` was
evicted at 07:25Z while `ci-cache-publisher.yml` remained its single writer
(no re-seeding path), killing every job2 attest until the callee pins were
rolled back to the NO-FIRE generation (org PR #55, merged 09:02:58Z). #502
removed the structural cause on the Axiom side (provenance → executed-member
reduction), and the pins were re-rotated to `22ae6bd3…` (org PR #56, merged
10:07:00Z). Consequence for this record: #502's own merge_group validation
(run `37444016474`, 09:35:30→09:47:52, 12m22s) ran on the NO-FIRE generation
(rotated-away pins), so armed-generation re-validation is a separate
observation — the first post-#56 queue round, not this incident's close-out.

## Lessons

1. Fail-closed collection of PROVENANCE must still respect the materialization
   contract of its environment: a fail-closed read of a file the environment
   does not ship is not soundness, it is nondeterminism.
2. Provenance records what the verification actually executed; identity
   remains the semantic binding. The two were conflated by one shared
   collector.
3. Any collector input whose presence is not contract-guaranteed by the
   environment that runs the collector is a determinism defect, regardless of
   how sound the hash chain looks.
