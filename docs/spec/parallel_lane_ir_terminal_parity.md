# Parallel-Lane IR Terminal Parity (VS-1)

- Status: Adopted contract (Phase 1, unit scope)
- Authority: `src/verification/batch_uap/loop_driver.nim` (sequential reference), `src/verification/batch_uap/loop_depth_scheduler.nim` (parallel mirror)
- Test: `tests/unit/batch_uap_orchestrator_test.nim` — "VS-1 non-blocked IR disproof terminal" suite

## Contract

**IR-adjudicated claims have lane-independent node verdicts.** A claim-scoped IR
pipeline verdict (`IrPipelineResult.verification.status == vsDisproved`, the
P4 finalizer's cvConfirmed promotion) is a FINAL adjudication of the claim: the
node's terminal status, exit accounting, and certificate outcome must not
depend on which lane (sequential `loop_driver` / threaded parallel
`loop_depth_scheduler`) executes the node.

### The disproof terminal

- Sequential: `stage2Budget` consumes the claim-scoped result
  (`scopedIrResultForNode`) and issues the vsDisproved terminal
  (`verified=false`, `osrNone`); the driver maps it to
  `orchestrationProofFailed` with evidence label `"UAP failed"`. No cert, no
  uapResult, no summary.
- Parallel: the worker applies the SAME shared admission rule
  (`stages.decidePreSieveNode`) at its stage-5, then consumes the SAME
  claim-scoped terminal for admitted (`psndProceed`) nodes BEFORE budget,
  spacer, and UAP (stages 6-9). `disprovedNodes` membership — derived
  deterministically in `loop_driver` from the same claim-scoped lookup — is
  the only IR payload the worker needs. Blocked nodes whose disproof carves
  them out of a fatal pre-sieve block (`psndDisproofTerminal`) emit the
  identical report.

Invariant: a non-blocked `vsDisproved` node is `orchestrationProofFailed` on
both lanes. The parallel lane must never advance a refuted claim into the
solver region (where it could return `orchestrationVerified` with a
certificate while `failedCount` stays 0 → exit 0; the sequential lane exits 1).

### P6 attempt accounting

Unchanged semantics, lane-independent: a node whose obligations were
dispatched toward a proof-resolution path counts them as attempted
(`preSieveAttemptsObligations` — every decision except `psndPreSieved`). The
parallel merge keys the accounting to the merged decision projected from the
node report, mirroring the sequential driver's pre-early-exit accounting. The
`disproofCarveOut` result field (written, never read — duplicated semantic
state) was removed; the report status is the single carrier of the terminal
verdict.

### Certificate label parity

The parallel merge applies the SAME promotion-label reclassification the
sequential driver applies after a certificate write: a verified-labeled node
whose persisted certificate carries status `certNoObligation`
(`tierFromResults` vtNone — no verification obligation, nothing promoted) is
relabeled `orchestrationNoObligation` BEFORE the progress label, log line, and
report row are emitted (`reclassifyCertNoObligation`). Fail-closed: only an
observed `certNoObligation` reclassifies; a failed write or unreadable cert
keeps the incoming label. Other promotion branches (semantic-evidence gating,
canonical promotion) remain sequential-driver-owned; the parallel lane keeps
its best-effort persist semantics (DEBT#415) — mirroring those is out of VS-1
scope.

## Acceptance (unit scope)

- `AXIOM_PROVE_WORKERS=1|2` runs of the fixture (workers=2 run twice,
  order-independent) agree on: per-node status, evidence label, canonical
  `failedCount` projection, P6 attempted/generated/target counts, absence of
  uap results and certificates for the refuted nodes.
- The fixture is Z3-independent BY CONSTRUCTION: the terminal is consumed
  before the only solver-reaching stages, and the fixture sources are
  rejected by `isArithmeticFunction` so the type-directed stage returns
  before its solver leg on both lanes. Validated additionally by process
  observation (execve audit: zero z3 children during the test binary).
- Integration equivalence of the two lanes with real Z3 in the loop is a
  Phase 2.1 (Z3 exclusive lease) follow-up and is NOT claimed here.
