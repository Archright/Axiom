# Verifier Build Identity (`engineBuild`) — SSOT

**Status**: Normative contract (v1, 2026-10-20 — documents the merged behavior of PR #961, `feat/operational-strict-closure`, landed at commit `7ac99157ffed5f5725a0573bb213f310628900df`)
**Created**: 2026-10-20
**Related**: [docs/spec/strict_completeness_binding.md](strict_completeness_binding.md) (companion strict-evidence SSOT), [docs/spec/productization_contract.md](productization_contract.md), [docs/spec/obligation_semantics.md](obligation_semantics.md) §2.1a

**Source SSOT (code)**: this document describes code; the code is authoritative on any divergence.

- Pure composition (the ONE formula): `src/core/trusted/verifier_build_identity.nim` (`computeVerifierBuildId`, `VerifierBuildIdScheme`)
- Manifest recipe + generator: `tools/hermetic_build.nim` (`computeVerifierBuildManifest`, `measuredVerifierBuildId`, `generateBuildEnvContent`, `materializeBuildEnv`, `computeDeterministicSourceHash`)
- Admissibility cross-check + writer/pin composition: `src/verification/attestation_orchestrator.nim` (`verifierEngineBuildId`, `admissibleVerifierBuildId`, `verifierToolchainIdentityJson`)
- Live-line preservation + seed guard: `config.nims`
- Journal admission pin: `src/verification/cert_reconcile.nim` (`currentJournalToolchainPin`, `toolchainIdentityMatchesPin`)

---

## 1. Purpose

`engineBuild` in a certificate `toolchainIdentity` must identify the **VERIFIER BUILD
INPUTS**, not the repository state: the repo commit (`BuildEnvGitHash`) churns on docs-only
and topic-vs-merge commits that change nothing the verifier compiled. The identity is
therefore a canonical SHA-256 digest over the measured build-input manifest, generated into
`src/generated/build_env.nim` as `VerifierBuildId` and consumed at admission time through a
fail-closed cross-check against the live source tree.

---

## 2. Recipe input set (exact)

`computeVerifierBuildManifest()` (`tools/hermetic_build.nim`) collects
`(repo-relative path, sha256 of file bytes)` records for exactly:

1. every `src/**/*.nim` file EXCLUDING any path containing `/generated/` (generated code is
   an OUTPUT of the build, not an input);
2. `config.nims` (compiler flags), `config/effects.nims` (effect checking),
   `src/gate/config.nims` (gate flags);
3. `Makefile` (the documented build recipe);
4. `axiom.nimble` + `axiom.lock` (the dependency pins);
5. `proofs/lean-toolchain` (the compile-time Lean pin constant — the file elan resolves;
   see §7).

Docs, tests, journal/baseline data and git metadata are NOT build inputs and are excluded: a
docs-only commit keeps the identity; a verifier source change moves it. If ANY input is
unreadable or a required fixed input (the item-2..5 list) is missing, manifest collection
aborts and returns an empty manifest — which `computeVerifierBuildId` maps to `""` (§3), and
the materializer refuses to write an empty identity (§6). An empty manifest never yields a
plausible identity.

---

## 3. Chained sha256 composition

`computeVerifierBuildId(records)` (`src/core/trusted/verifier_build_identity.nim`) is the
single formula shared by the generator and the tests:

```
scheme   = "axiom-verifier-build-v1"            # VerifierBuildIdScheme
records' = records sorted by relPath            # order-invariant
lines    = [relPath & "\x1f" & sha256Hex(file bytes) for (relPath, _) in records']
id       = sha256Hex(scheme & "\n" & join(lines, "\n"))
```

- Deterministic regardless of caller order (records are sorted by path first).
- Content- and path-sensitive: changing any file's bytes or any record's path moves the id
  (pinned by fixture tests in `tests/unit/test_verifier_build_identity.nim`).
- Empty input → `""` (fail-closed).

### 3.1 `VerifierBuildSourceHash` and `BuildSourceHash`

`generateBuildEnvContent()` emits two additional constants, both computed as
`computeDeterministicSourceHash(projectRoot / "src")`:

- `BuildSourceHash` — the live source-tree hash, re-filled at every compile by `config.nims`
  (`computeSourceTreeHash("src")`, the NimScript twin of the pure kernel
  `src/core/utils/build_provenance.nim:sourceTreeDigest`) over the same `.nim` file set;
- `VerifierBuildSourceHash` — the source-tree hash the `VerifierBuildId` was measured FOR.

**Formula `vs1-tree-hash/1`** (SSOT: `src/core/utils/build_provenance.nim`):

```text
fileDigest(p) = $hash(bytes(p))
treeDigest    = "vs1-tree-hash/1:" & $hash(
                  "vs1-tree-hash/1\n" & Σ_{p sorted by relPath} relPath(p) & "\0" & fileDigest(p) & "\n")
```

The formula id is both folded into the digested stream and prefixed onto the value, so a
`vs1-tree-hash/1:`-prefixed digest is never conflated with the retired concatenation-era
decimal value in any persisted copy (`build_env.nim`, run manifests, B-probe output). Paths
are bound into the digest, removing the old file-boundary ambiguity
(`"ab"+"c" ≡ "a"+"bc"`). Value semantics change on this upgrade: any artifact or journal
recorded under the old formula fails the `VerifierBuildSourceHash == BuildSourceHash`
admission cross-check and is dropped/re-proven (`cert_reconcile.nim`), never silently
accepted.

The digest primitive is Nim's `system.hash` on purpose: `config.nims` runs in the NimScript
VM where `std/sha1|sha2` do not compile, and the VM and compiled `$hash` agree
byte-for-byte (pinned by `tests/unit/source_identity_cache_test.nim`, measured 2026-11-12).
Per the Nim standard library, a hash value is required to be equal whenever the hashed
values compare equal ([std/hashes](https://nim-lang.github.io/Nim/hashes.html)); the same
input bytes under the same pinned compiler produce the same value. Hash stability ACROSS
Nim versions is not guaranteed by Nim — it is not claimed here either; the repo pins the
toolchain (Nim 2.2.10), so generator and compile-time fill agree within the pinned
generation.

The runtime bootstrap check (`checkAndSelfBootstrap`) may reuse per-file digests from the
`vs1-tree-hash/1` acceleration cache
(`src/infrastructure/source_identity_cache.nim`, `docs/spec/artifact_determinism.md` §3.3);
the tree digest itself is always recomposed from the live walk and the cache is never
evidence for the verdict.

### 3.2 The cross-check

`admissibleVerifierBuildId(id, idSourceHash, liveSourceHash)` — pure, exported for the
negative-control test — admits the measured id ONLY when:

1. `id` is a canonical 64-char lowercase-hex digest, AND
2. `idSourceHash` (`VerifierBuildSourceHash`) is non-empty AND equals `liveSourceHash`
   (`BuildSourceHash`, the live compiled value).

Any other value is the literal string `"unmeasured"` — never a stale-but-plausible identity.

`verifierEngineBuildId()` guards the whole chain with `when declared(...)` over
`VerifierBuildId`, `VerifierBuildSourceHash` and `BuildSourceHash`: missing constants →
`"unmeasured"`.

---

## 4. config.nims preservation

The NimScript VM cannot compute the sha256 build manifest, so the live values are measured by
`bin/hermetic_build` and must survive `config.nims`' body-cache restore:

- When restoring `src/generated/build_env.nim` from the cached body
  (`.axiom/cache/build_env.body`), `config.nims` preserves the previous
  `build_env.nim`'s `VerifierBuildId*` and `VerifierBuildSourceHash*` lines verbatim,
  replacing the placeholder lines in the restored body. The cross-check (§3.2) then rejects a
  stale id as `"unmeasured"`.
- The body cache itself never carries a numeric `VerifierBuildSourceHash`/`BuildSourceHash`
  or a stale `VerifierBuildId` (they are replaced by placeholders when the body is cached);
  a body that still carries a numeric hash is stale and is refused (coherence guard), falling
  back to the `.default` template without ever writing a stale VALUE.
- The `BuildSourceHash` seed guard fills the live source-tree hash when
  `build_env.nim` carries the empty or placeholder form (fresh-checkout bootstrap);
  a non-empty hash is never touched — `bin/hermetic_build` remains the SSOT writer of
  `VerifierBuildId`.

---

## 5. Fail-closed values ("unmeasured")

Every failure mode collapses to `"unmeasured"`, and `toolchainIdentityMatchesPin` NEVER
matches it (an explicit guard rejects the pin itself being `"unmeasured"` — without that
guard a claim literally carrying `"unmeasured"` would compare equal to an `"unmeasured"` pin,
self-consistent theater):

| Failure mode | Result |
|---|---|
| `build_env.nim` missing any of the three constants | `"unmeasured"` |
| Placeholder value (e.g. `__AXIOM_VERIFIER_BUILD_ID__`) left in the generated file | `"unmeasured"` (non-canonical hex) |
| Id not 64-char lowercase hex | `"unmeasured"` |
| `VerifierBuildSourceHash` empty (never measured) | `"unmeasured"` |
| `VerifierBuildSourceHash != BuildSourceHash` (tree changed after measurement) | `"unmeasured"` |
| Manifest unmeasurable at generation/materialization time | materializer refuses to write an empty id (coherence FAIL) instead of emitting a blank engine identity |

Because `toolchainIdentityMatchesPin` iterates every key of the pin JSON
(`{"nim", "lean", "z3", "engineBuild"}`), a claim produced before this cutover (no
`engineBuild` key) or under a different verifier build drops — fail-closed; the kernels are
re-proved on cutover.

---

## 6. Required regeneration order

After any change to a verifier build input (§2):

1. Run `bin/hermetic_build` (the generator) — it recomputes the manifest, freezes the fresh
   `VerifierBuildId` + `VerifierBuildSourceHash` into `src/generated/build_env.nim`, and
   refreshes the body cache (placeholders for the measured values).
   The `--materialize` fast path performs the live substitutions from the cached body and
   likewise refuses an empty measured identity.
2. Then `nim c` (the normal compile) — `config.nims` re-fills `BuildSourceHash` from the live
   tree while preserving the two verifier-identity lines.

A plain `nim c` after an edit WITHOUT `bin/hermetic_build` is the designed negative case: the
preserved `VerifierBuildSourceHash` no longer equals the live `BuildSourceHash`, the engine
identity measures `"unmeasured"`, and no certificate can be emitted under the old engine
identity (the journal admission pin drops such claims).

---

## 7. What the identity does NOT claim

- **Not a repo commit.** `VerifierBuildId` is deliberately NOT `BuildEnvGitHash`: a docs-only
  commit or a topic-vs-merge tree change must NOT move the engine identity, and a repo commit
  does not identify what the verifier binary was compiled from.
- **Not a product version.** The `axiomVersion` product label (e.g. `v0.3.7`, writer-only)
  is NOT a pin component: `toolchainIdentityMatchesPin` iterates the pin keys only, so adding
  it to a claim does not affect admission.
- **Not the toolchain binaries.** The compiling Nim version, the repo Lean pin
  (`lean-toolchain`, `leanprover/lean4:v4.33.0` — the file elan uses to select the toolchain,
  [elan](https://github.com/leanprover/elan)) and the hermetic Z3 build-env version are
  SEPARATE pin keys (`nim`, `lean`, `z3`); `engineBuild` names only the verifier's own build
  inputs. The `lean` pin key is the pinned repo version constant
  (`PinnedLeanToolchainVersion`, the `lean-toolchain` SSOT's version), not a measurement of
  installed binaries.
- **Not proof of user intent.** A stable engine identity says the same verifier build
  produced the evidence; it says nothing about whether the obligations express what a human
  intended to verify.
- **Not broad Rust/AST coverage.** The identity covers the Nim verifier's build inputs only.
  It does not widen the certified extraction subset, and the Rust extraction binding in
  `axiom.attestation.evidence.v2` (`llbcDigest`, `rustToolchainIdentity`) carries its own
  measured identity — `engineBuild` is not that identity.
- **No cache authority.** `src/generated/build_env.nim` is a generated cache of measured
  values; admission re-derives admissibility from the live tree at every run
  (`verifierEngineBuildId`), and the TrustCommit journal — not any generated constant —
  remains the authoritative record of claims.
- **No certificate-file authority.** `engineBuild` participates in a claim's
  `toolchainIdentity`; the canonical cert files are materialized projections. Claims are
  admitted from the journal snapshot with the CURRENT pin; the vault file is never the
  identity authority.

## 8. Run-level observation surface — the execution identity envelope

`engineBuild` is observable for **every verdict class**, not only runs that produce
per-node certificate files (`orchestrationVerified` writes a certificate; a DISPROVED
subject writes none — §0.9: a red verdict must still be attributable to the verifier
build that produced it).

The single run-level surface is the **execution identity envelope** persisted in
`ax_proof_state.json` (`executionIdentity`): `captureReuseVerificationContext`
(`src/verification/accounting/execution_context.nim`, the ONE measurement site) records
`verifierBuildId = verifierEngineBuildId()` alongside the bundle fingerprint, config digest,
D2 toolchain identity, and execution epoch. Read-time re-validation
(`revalidateRestoredStateIdentity`) binds a restored state to the CURRENT verifier build:
an empty or `"unmeasured"` current value, or any mismatch with the recorded value, leaves
the state unestablished (fail-closed, both directions — an `"unmeasured"` recorded value can
never self-match, mirroring the pin-matching guard of §5).

Consumers that need the run's verifier build identity (the external verification campaign's
vacuous guard, `external_verification_campaign_contract.md` §3.4(a)·§139) read
`executionIdentity.verifierBuildId` from the proof state and apply the admissibility check
themselves: 64-char lowercase hex — anything else is `"unmeasured"` and the run is
`VACUOUS_BLOCKED`, never a green interpretation. The envelope does not enter
`canonicalRunDigest` (the digest covers verdict accounting only), so adding the observation
surface changes no digest semantics.

External behavior cited in this document: GitHub's merge queue merges the queued group only
once the checks required by the branch protections pass
([Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)),
which is why a stale-but-plausible engine identity must be inadmissible rather than merely
warned about: VKD evidence admitted under a wrong `engineBuild` would surface to merge
admission as a green check produced by a different verifier than the one the pin names.
Nim's hash-value contract (equal values hash equally) is cited from
[std/hashes](https://nim-lang.github.io/Nim/hashes.html); the Lean toolchain selection
behavior (`lean-toolchain` file overrides the active toolchain per directory) is cited from
the elan documentation ([elan](https://github.com/leanprover/elan)).
