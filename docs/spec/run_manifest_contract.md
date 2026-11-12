# Run Manifest Contract (`axiom.run-manifest.v1`)

**Purpose.** The run manifest is a deterministic JOIN of one verification run
(persisted state + certificate + report + exit codes), reduced to one canonical
JSON document whose SHA-256 digest is compared **across environments** (local
workstation, CI runner, fresh clone) for identity.

**Sole producers.** `tools/ci/run_manifest.jq` (the projection) and the Makefile
target `verify-contract-release-e2e-full` (the run joined). No other component may
emit a run manifest; no consumer may extend the field tree.

## §1. Schema

`schemaVersion` = `axiom.run-manifest.v1`; the field tree is exactly what `tools/ci/run_manifest.jq` produces:

```
axiom.run-manifest.v1
├── target        { nodeId, symbol, modulePath }
├── sourceTree    { gitHead, scopeHash, subjectSourceHash }
├── policy        { scopeLockSha256, executionConfigDigest, executionEpoch }
├── certificate   { path, irHash, identityDigest, propositionHash, obligationId,
│                   trustCommitId, status, verificationTier, sha256 }
├── toolchain     { executionBundleFingerprint, toolchainIdentity, platform }
├── verification  { proveExit, certVerifyKernelExit, certVerifyKernelStdout }
└── report        { schemaVersion, verdict, basis, gateVerdict, exit, verified, failedCount,
                    timeoutCount, canonicalDigest, unitOutcome, satisfactionSource }
```

`target` is the single proved unit (`src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers`);
the other groups pin inputs, contract identity, obligation, environment, outcomes, verdict. Names,
order, and defaults (`// ""`, `// 0`) are the jq program's — it is the SSOT.

## §2. Included fields (identity-bearing)

Every included field is a **deterministic function of the run's identity**.

| Group | Fields | Why it is identity |
|---|---|---|
| target | `nodeId`, `symbol`, `modulePath` | which obligation was proved |
| sourceTree | `gitHead`, `scopeHash`, `subjectSourceHash` | the exact input bytes (source + IR translation state) |
| policy | `scopeLockSha256`, `executionConfigDigest`, `executionEpoch` | the contract/policy generation that governed the run |
| certificate | `path`, `irHash`, `identityDigest`, `propositionHash`, `obligationId`, `trustCommitId`, `status`, `verificationTier`, `sha256` | the certificate's own identity and trust binding; `path` is the repo-relative vault path replayed |
| toolchain | `executionBundleFingerprint`, `toolchainIdentity`, `platform` | the execution environment that produced the claim |
| verification | `proveExit`, `certVerifyKernelExit`, `certVerifyKernelStdout` | the proof and kernel-replay outcomes |
| report | `verdict`, `basis`, `gateVerdict`, `exit`, `verified`, `failedCount`, `timeoutCount`, `canonicalDigest`, `unitOutcome`, `satisfactionSource` | the product's own verdict for the run |

## §3. Excluded fields (non-identity)

Each excluded class is a property of the *observation*, not of the *claim*; including any would make the digest environment-dependent.

| Excluded | Reason |
|---|---|
| Timestamps (`timestamp`, `startedAtMs`, `endedAtMs`, `generatedAt`) | wall-clock readings differ per run; not reproducible |
| Run / process ids (`runId`, `processId`) | allocated per execution and per process; meaningless across machines — `executionEpoch` is kept only as a *policy generation* id |
| Absolute / tmp paths (`absolutePath`, `tmpPath`, `sourcePath`, `subjectRoot`, `stateRoot`, `repoRoot`) | physical location differs per clone |
| Cache state (`cacheHit`, `cacheHitCount`) | the warm/cold boundary flips for identical logical input — performance, not identity |
| Wall-clock / telemetry (`wallElapsedMs`, `solverElapsedMs`, `parallelOverheadMs`, `totalWallTimeMs`, `activeNodeCount`, `cpuLoadRatio`, `availableMemoryBytes`) | machine-speed measurement, not a property of the proof |
| Solver internals, randomness, evidence logs | non-deterministic traces; the claim is the certificate, not the search path |
| Timeout bookkeeping (`timedOut`, timeout wall observations) | a timeout is a hang-guard abort, not a verification verdict |

The same volatile class is excluded by the canonical projection rule of `docs/spec/productization_contract.md` §6, so the manifest digest and `ax report --canonical-digest` agree on "the same result".

## §4. Digest

The digest is **SHA-256 over the canonical serialization of the manifest JSON**:
`jq -S -c -j` — keys sorted, compact (no whitespace), **no trailing newline** — so the
hashed bytes are exactly the content of `logs/run-manifest.json`. It is computed as
`sha256sum logs/run-manifest.json` and stored in `logs/run-manifest.sha256` (bare hex
digest, one line). Sorted, newline-free serialization makes the digest stable against
key ordering and trailing whitespace; any change to any included field changes it.

## §5. Equality semantics

**Equal digest ⟹** the two runs have the same: (1) source bytes (`gitHead`,
`scopeHash`, `subjectSourceHash`); (2) symbol and proposition (`target.nodeId`,
`certificate.propositionHash`); (3) contract/policy identity
(`policy.scopeLockSha256`, `executionConfigDigest`); (4) certificate identity
(`certificate.identityDigest`, `irHash`, `obligationId`); (5) verify outcome
(`verification.*`); (6) report verdict (`report.verdict`, `gateVerdict`, `exit`,
counts); (7) toolchain (`toolchain.*`).

The converse does **not** hold: an equal digest does not prove the claims are true (§6),
and a difference does not localize the cause — compare the two manifests field by field.
**A toolchain or contract divergence is `NOT_CURRENT` (exit 4), never `PASS`.** A manifest
under a different toolchain identity, scope lock, or policy generation describes a
*different claim*; it must never be reported as PASS by relaxing the equality to a
subset of fields.

## §6. Epistemic limit

**Digest equality is a reproducibility claim, not a correctness claim.** The manifest
proves that two environments produced the *same claim about the same input under the
same contract*; it does not prove the claim is true.

Correctness evidence is separate: the **Lean kernel re-execution** of the SAME
certificate (`ax cert verify --kernel`, driven by
`make verify-contract-release-e2e-full`), the **Z3** solver obligations behind the proof,
and the **negative control** (known-bad fixtures that must be rejected) — see
`docs/spec/productization_contract.md` §6 and §7. Never let a digest comparison stand
in for a correctness argument.

## §7. Comparison protocol

Three environments, one producer: `make verify-contract-release-e2e-full` runs in
all three; the manifest and its digest are the comparable outputs.

- **Local (worktree):** `make build` → `make verify-contract-release-e2e-full` →
  the manifest emission step of `.github/workflows/axiom-operational-slice.yml`
  (`jq -n -S -c -j -f tools/ci/run_manifest.jq`) → `sha256sum logs/run-manifest.json`.
- **CI:** the same target in the job `axiom-operational-slice`; manifest + digest
  are uploaded as artifact `axiom-operational-slice-evidence` (with the report,
  report exit code, certificate path, kernel stdout, `logs/ax_proof_state.json`).
- **Fresh clone (cold replay):** the `tools/ci/cold_replay_acceptance.sh` pattern
  — a clean `git worktree` at the same commit with a **fresh** `AXIOM_STATE_DIR` /
  `AXIOM_PROVE_VAULT_DIR`, the scope lock seeded from the repo (recorded byte
  equality by sha256), then the identical producer sequence; compare
  `sha256sum logs/run-manifest.json` against the reference environment.

Cross-check, for a report-level comparison: `bin/ax report --canonical-digest` must
agree with the manifest's `report.canonicalDigest` field; a divergence is a producer defect.
