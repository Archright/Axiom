# D0 — Evidence Provenance Adjudication (clampTimeoutMs verified=1/40 vs 0/40)

- Adjudicated at: 2026-08-21T13:25Z
- Adjudication baseline (canonical HEAD): `2004fcd319d88178c7a9dfca48222e0318207d0c`
- Working tree at adjudication time: **112 dirty entries — isolated from the verdict** (see §Isolation)
- Method: observation only. No code changes, no replay implementation, no golden fixture,
  no hydration/migration/evaluator changes.

## Contradiction under adjudication

| Witness | Result |
|---|---|
| Historical | `./bin/ax prove --target clampTimeoutMs` → RC=0, `[VERIFIED]`, verified=1/40 |
| Fresh | `./bin/ax prove --target clampTimeoutMs` → RC=1, verified=0/40, clampTimeoutMs = Z3_CANDIDATE_ONLY / certZ3Candidate |

## Historical Witness

- artifact: `data/readiness/golden/positive/golden_clampTimeoutMs_v3_cert.json`
  (sha256 = `6e6a8902ae0a05bce0ba371ed99c43d3c66cf5365f0a787e96c8aed1b576ec34`),
  byte-identical to persisted `src/verification/certificates/7e5a975faec166f9bb49678a84dcd1d3c59dc30a3ab9cdb7883abfc778083f01.json`
- producer: pre-Phase-B cert writer (`axiom.certificate.v3`, Ed25519-attested,
  axiomVersion v0.3.7) — emitted `status=certZ3Verified`, `reason=z3-verified`
- binary: not recorded (digest absent from R8.json); built before Phase B authority work
- source: claimed repoHead `186c05d89` with `"workingTreeClean": true` —
  **claim contradicted by evidence**: `src/infrastructure/certificate_attestation.nim`,
  which HEAD-era `cert_writer.nim` imports, has never been committed
  (`git ls-tree HEAD -- <path>` empty; file created 2026-08-20 19:45 KST,
  ~3h before evidence collection). The historical run necessarily executed from a dirty tree.
- toolchain: nim 2.2.10, z3 4.13.3, lean **4.29.0** (recorded in cert toolchainIdentity)
- executionContract: `ax prove --target clampTimeoutMs`; solverInvocation
  `{engine: z3, mode: none, strategy: none}` — note **mode=none yet certificate issued**
- cacheState: not recorded
- Lean/Z3 artifacts: real Z3 input present (smtlib2, 2060 bytes, unsat);
  **`leanProposition` = "" (empty)** — no Lean proposition, no kernel ACCEPT witness.
  `kernel: true` field is asserted, not evidenced.

## Fresh Witness

- artifact: `build/certificates/manifest.json` entry for clampTimeoutMs —
  `status=certZ3Candidate`, `solverMethod=smNone`,
  lastVerifiedAt 2026-08-21T13:21:31Z; canonical vault certificates NOT rewritten
  (all mtimes 2026-08-20)
- producer: current cert writer + Phase B authorities (post-618606c2b):
  Z3-only reclassified to candidate, excluded from verified count
- binary: `bin/ax` sha256 `11cb5b65d231838062a5635d99c8cc0b2238c02504010ab5c7d81622626d39e6`
  (mtime 2026-08-21 22:20 KST; self-rebuilt during the run)
- source: **dirty working tree at 2004fcd31** (see Isolation) — a clean-checkout build of
  2004fcd31 is IMPOSSIBLE: `cert_writer.nim@HEAD` imports untracked
  `infrastructure/certificate_attestation.nim` → clean worktree build fails
  (`cannot open file`). This is a launch-critical finding in itself.
- toolchain: nim 2.2.10, z3 4.13.3; `lake env lean` = 4.33.0 — but ONLY because the
  working-tree `lean-toolchain` files are dirty: **HEAD declares 4.29.0 in both**
  `lean-toolchain` and `proofs/lean-toolchain`. The "P0-Pin 4.33.0" state is uncommitted.
- executionContract: `ax prove --target clampTimeoutMs`, cwd = repo root
- cacheState: hermetic cache HIT during builds; auto-rebuild triggered
  (`Source changed. Auto-rebuilding...`) on first invocation
- Lean/Z3 artifacts: Z3 candidate path only; no Lean kernel ACCEPT witness

## Axis-by-axis identity

| # | Axis | Historical | Fresh | Same? |
|---|---|---|---|---|
| 1 | Binary identity | unrecorded | 11cb5b65… (dirty-built) | UNKNOWN/N |
| 2 | Source identity | 186c05d89, "clean" claim FALSE | 2004fcd31 + 112 dirty | N |
| 3 | Toolchain identity | lean 4.29.0 recorded | lean 4.33.0 (dirty pin); HEAD pins 4.29.0 | N (recorded) |
| 4 | Execution contract | same argv shape | same argv shape | Y (approx) |
| 5 | Cached state | unrecorded | hermetic HIT + self-rebuild | UNKNOWN |
| 6 | Persisted artifact | 7e5a975f cert (6e6a8902…) still in vault | manifest entry certZ3Candidate | N |
| 7 | Certificate producer | pre-Phase-B writer (promotes Z3-only→certZ3Verified) | post-Phase-B writer (candidate-only) | **N — decisive** |
| 8 | Lean/Z3 artifacts | real Z3 unsat; leanProposition="" | Z3 candidate only; no Lean ACCEPT | Z3-ish; Lean: neither |

## Verdict

**A. HISTORICAL_STALE**

The historical `verified=1/40` was produced by a different, retired producer whose
semantics promoted Z3-only evidence (`mode=none`, empty `leanProposition`) into
`certZ3Verified` and counted it as verified. The target source
(`orchestrator_topology_worker.nim::clampTimeoutMs`) is unchanged between the two
witnesses; the producer code is not (930 insertions across src/verification between
186c05d89..2004fcd31). The contradiction is fully explained by producer semantics
change plus unverifiable historical environment ("workingTreeClean": true is false;
binary digest unrecorded). NONDETERMINISM is ruled out at this resolution: each
witness's result is consistent with its own producer's rules.

### Secondary findings (launch-critical, independent of the verdict)

1. **HEAD 2004fcd31 does not build from a clean checkout** — required module
   `src/infrastructure/certificate_attestation.nim` is untracked. Every product
   binary to date was built from a dirty tree. Canonical-baseline rebuildability
   (R1 precondition) is currently UNMET.
2. **Lean 4.33.0 pin exists only as a dirty working-tree change**; both committed
   lean-toolchain files say 4.29.0.
3. The historical R8 evidence record's `"workingTreeClean": true` field is factually
   wrong — readiness evidence provenance hygiene needs the Phase C identity closure.

## R8 implication

**Lean kernel ACCEPT witness: NO** (both witnesses).

Historical `certZ3Verified` carried an empty `leanProposition` — it never was a Lean
kernel acceptance. Fresh run classifies the same Z3 evidence as candidate-only.
No genuine kernel-backed VERIFIED transaction exists at this baseline.

## Isolation statement

All verdicts above were drawn from: git object store (commits 186c05d89, 618606c2b,
2004fcd31), tracked persisted artifacts, and one fresh execution of the existing
binary. The 112-entry dirty working tree was treated as untrusted legacy state; it
was fingerprinted (count + key files) but no adjudication conclusion depends on any
uncommitted file's *intended* content — only on the demonstrable fact that the
product binary and toolchain pin depend on it.
