# WP3-c Follow-up — Forensic / Clean-Subject / Axiom-State Separation

> EXPERIMENT-ONLY / not canonical execution path / not production API.
> Follow-up to WP3-c: instead of force-cleaning the polluted nim-stew working tree, split the
> historical pollution (forensic evidence), the clean subject (immutable input), and the Axiom
> runtime state (Axiom-owned) into three distinct roles. No subject tree was mutated; no commit made.

## 1. The three-role separation principle

Axiom's mutation boundary should be:

- **Forensic copy** — preserves past pollution byte-for-byte, never deleted, never reinterpreted, hash-pinned.
- **Clean subject fixture** — re-derived deterministically from the canonical Git revision; used for M1 runs.
- **Axiom state** — all mutable runtime artifacts, owned by `stateRoot` (`AXIOM_STATE_DIR`).

So: `historical evidence ≠ current subject ≠ Axiom execution state`.

## 2. Forensic copy (preserved, not deleted)

The polluted nim-stew working tree held one untracked residual:

- `nim-stew/data/trusted/journal/3ab50cc271cdc3166d6ad39c9b34f7a01a2c0626fdd08cfecdb33107135c2aad.json`
  - kind `tcVerifiedProof`, solverInvocation `proof-universe-lock:v33` — a prior WP's ExternalSubject
    journal-routing defect (the class fixed by WP3-b `commitVerification(run,result)` + routing).
  - file sha256 `519aca4c70e1c78846be6ace6c7798643a15d4aa113c6d73fec0e266f15394e9`

Preserved read-only at:
`experiments/act2-wp3c-historical-trust-debt/forensic/nim-stew-data/trusted/journal/...`
with `experiments/act2-wp3c-historical-trust-debt/forensic/forensic_manifest.json`
(hash-pinned; policy: never delete, never reinterpret; NEVER used as an M1 fixture).

The **original polluted directory was left in place** (no `rm -rf data`). It is the forensic origin.

## 3. Clean subject fixture

- New clean clone: `<workspace>/nim-stew-clean-c75502c`
- `git clone https://github.com/status-im/nim-stew.git` → `git checkout c75502ceedb5ed2a37b7b5e4744fc71313682859`
- `git rev-parse HEAD` = `c75502ceedb5ed2a37b7b5e4744fc71313682859` (matches intended revision)
- working tree **empty** at creation; **data/ absent** after all runs.

SourceIdentity (canonical input):
- GitRevision: `c75502ceedb5ed2a37b7b5e4744fc71313682859`
- SubjectFileSet (clean): 86 files (topology-reported), sourceRoot `…/nim-stew-clean-c75502c`
- sourceFingerprint (this experiment's pin):
  - `stew/base36.nim` sha256 `b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8`
  - sorted `stew/*.nim` aggregate sha256 `812bcc0b9ed8695ae536c6a58e83575dc318ebabecb9d61fe64425ca8968fa58`

## 4. encode experiment (clean fixture only)

Command (per WP3-b §4.2, external subject with explicit state):
```bash
cd /tmp && AXIOM_ROOT=…/Axiom AXIOM_STATE_DIR=/tmp/wp3fo_state_{a,b} timeout 300 \
  …/Axiom/bin/ax prove --project …/nim-stew-clean-c75502c \
  --target "stew/base36.nim::encode" --limit 1
```

### Run A / Run B (determinism)

- target filter: **1 node matches** `stew/base36.nim::encode` (exact target)
- `frontier eligibility gate: excluded 326 non-proof-candidate candidate(s); eligible=0`
- `verifying 0 nodes (primed=0)`; `verifiedRatio=0.0000, verified=0/41`
- `[AXIOM TRUST] proof_universe VerifiedProof commit skipped: no kernel-tier verified nodes (verifiedNodes=0)`
- Log diff RunA vs RunB: **identical except the physical `state_a`/`state_b` path** (byte count 3113 = 3113)
- journal count in both states: **6806 → 6806** (no addition)

### Subject immutability (clean fixture)

`git -C nim-stew-clean-c75502c status --porcelain` = **empty after Run A and Run B**; no `data/` created.
Axiom-owned artifacts routed entirely to `AXIOM_STATE_DIR`; the clean subject stayed read-only.

## 5. Honest conclusion: clean fixture does not change eligibility outcome

The encode run reproduces the exact blocker observed for `decodedLength` in WP2/WP3:
- `--target` selects the node (exact 1 match), but the **frontier eligibility gate** drops it
  (`eligible=0`), so `planned=0` and Z3/Lean are not reached.
- This is independent of the fixture: a clean, byte-stable subject yields the same result as the
  polluted one. The core blocker is upstream of target ordering — in the topology/eligibility gate —
  and is **not** a pollution problem.

Therefore this WP2/WP3 eligibility blocker is a **separate, open issue** (frontier eligibility semantic),
not resolved by the separation. It is documented, not hidden, and not bypassed.

## 6. Separation realized

| Role | Location | Status | Used for M1 |
|---|---|---|---|
| Forensic copy | `experiments/…/wp3c/forensic/nim-stew-data/` | read-only, hash-pinned | NO |
| Clean subject | `…/nim-stew-clean-c75502c` | immutable (status empty) | YES |
| Axiom state | `AXIOM_STATE_DIR` (e.g. `/tmp/wp3fo_state_*`) | Axiom-owned | runtime |

## 7. Registration / classification

- Classification: **InfrastructureSeparation** (hygiene architecture), not a proof outcome.
- `encode` target match (E1) = PASS; Z3/Lean reach (V1) = **FAIL** — `frontier eligibility gate` blocker,
  pre-existing, unrelated to fixture cleanliness.
- Open issue: eligibility gate semantics must treat an explicit external subject target as a
  verification candidate (future WP, per WP1 §4 taxonomy — not bypassed here).

## 8. Artifacts

- `experiments/act2-wp3c-historical-trust-debt/forensic/forensic_manifest.json`
- `experiments/act2-wp3c-historical-trust-debt/forensic/nim-stew-data/…/3ab50cc2…json`
- `/tmp/wp3fo_runA.log`, `/tmp/wp3fo_runB.log`
- `/tmp/wp3fo_state_a` , `/tmp/wp3fo_state_b` (Axiom states, 6806 journal each)
- clean clone `<workspace>/nim-stew-clean-c75502c` (immutable)

No `git commit` was made.
