# Artifact Determinism — Contract Taxonomy & Type Boundary

## 1. Contract Taxonomy

Five **distinct** contracts govern artifact determinism. They are **never** merged into a single "hermetic" blob or a single "hash." SourceTreeHash and ArtifactDigest are separate values with different computation locations, different adjudicators, and different violation language.

| Contract | Definition | Computation Location | Adjudicator | Violation Language |
|---|---|---|---|---|
| **SourceCoherence** | The running binary embeds a build identity (`BuildSourceHash`) that matches the live source snapshot (`SourceTreeHash`). | `src/core/utils/build_provenance.nim:sourceTreeDigest` (pure fingerprint kernel, formula `vs1-tree-hash/1` — §3.3); `src/infrastructure/source_identity_cache.nim:computeSourceTreeDigestUncached` (runtime gather, fail-closed read — raises on unreadable file, does not FATAL itself); `src/cli/main.nim:checkAndSelfBootstrap` (adjudicator — FATAL `quit(1)` on mismatch; may use the acceleration cache for per-file digests only); `tools/hermetic_build.nim:computeDeterministicSourceHash` (build-time, same kernel) | Runtime FATAL exit (in `checkAndSelfBootstrap` only) | `[FATAL] Engine source/source mismatch (SourceCoherence FAIL)` — `checkAndSelfBootstrap` in `src/cli/main.nim:82` |
| **ArtifactIdentity** | The binary is a canonical artifact for a specific (source snapshot + toolchain + build policy). `ArtifactDigest` = SHA-256 of binary content. | `tools/ci/d3_substrate_measure.sh` compare phase (`sha256sum bin/ax`); CAS content-addressing | CAS / digest comparison | `ArtifactDigest(build(root=A)) ≠ ArtifactDigest(build(root=B))` for identical logical source — relocation invariance failure |
| **RelocationInvariance** | Identical logical input physically relocated to a different root must yield identical `ArtifactDigest`. This is a **property** of `ArtifactIdentity`, not a separate contract. | `tools/ci/d3_substrate_measure.sh` compare — relocation determination (added in PR-2) | D3 fixture regression assertion | `ArtifactDigest(build(root=A)) ≠ ArtifactDigest(build(root=B))` where A ≠ B are different physical roots |
| **MutationClosure** | Build tools write **only** to their declared output set. No writes outside the declared output set. | V2 static verification + regression list (see §3) | V2 static verification + regression list | A build tool writes to a path outside its declared output set |
| **DeclaredInputClosure** | Hashes and builds read **only** within the declared input set (`src/**/*.nim` excluding `generated/`). Read failures are **never** silently skipped (fail-closed). | `src/cli/main.nim:computeSourceTreeHash` (PR-1 fail-closed); `tools/hermetic_build.nim:computeDeterministicSourceHash` (build-time) | Integrated canonical hash (PR-1 unified) | A read failure is silently skipped (`except: discard`), or a read occurs outside the declared input set |

### 1.1 Explicit Prohibitions

- **SourceTreeHash ≠ ArtifactDigest.** These are different values computed at different times by different procs. `SourceTreeHash` is a hash of source file contents; `ArtifactDigest` is a hash of the binary blob. Treating them as a single "hash" is a contract violation.
- **Two closures are not one "hermetic."** `MutationClosure` (write direction) and `DeclaredInputClosure` (read direction) are separate contracts with separate evidence and separate adjudicators. Collapsing them into a single "hermetic" claim obscures which direction was violated.

### 1.2 Contract Computation Locations — Precise File:Symbol References

| Contract | File:Symbol |
|---|---|
| SourceCoherence | `src/core/utils/build_provenance.nim:sourceTreeDigest` (pure kernel, formula `vs1-tree-hash/1`) |
| SourceCoherence | `src/infrastructure/source_identity_cache.nim:computeSourceTreeDigestUncached` (runtime, fail-closed) |
| SourceCoherence | `src/infrastructure/source_identity_cache.nim:computeSourceTreeDigestCached` (bootstrap acceleration; per-file digests only, never evidence) |
| SourceCoherence | `tools/hermetic_build.nim:computeDeterministicSourceHash` (build-time, same kernel) |
| SourceCoherence | `src/cli/main.nim:checkAndSelfBootstrap` (adjudicator — FATAL exit on mismatch) |
| ArtifactIdentity | `tools/ci/d3_substrate_measure.sh` compare phase — `sha256sum bin/ax` (CAS/digest) |
| RelocationInvariance | `tools/ci/d3_substrate_measure.sh` compare phase — relocation determination (PR-2) |
| MutationClosure | V2 static verification; regression list in `tools/ci/d3_substrate_measure.sh` write inventory |
| DeclaredInputClosure | `src/infrastructure/source_identity_cache.nim:computeSourceTreeDigestUncached` (fail-closed read); `tools/hermetic_build.nim:computeDeterministicSourceHash` (build-time) |

---

## 2. PhysicalPath / LogicalPath Type Boundary

### 2.1 Type Definitions

Two distinct types are introduced in `src/core/utils/path_identity.nim`:

```nim
## PhysicalPath — absolute, environment-dependent filesystem path.
## Used for runtime file access (read/write/stat).
type PhysicalPath* = distinct string

## LogicalPath — repo-relative, relocation-invariant path.
## Used for identity/contract computations that must be
## independent of the physical checkout location.
type LogicalPath* = distinct string
```

### 2.2 Single Conversion Boundary

```nim
## Convert PhysicalPath → LogicalPath.
## This is the ONLY place PhysicalPath is converted to LogicalPath.
## logicalSourcePath() is an implementation name, NOT a contract.
## Pure func — root is resolved at the callsite to keep toLogical
## free of runtime I/O (no findRepoRoot() inside the function body).
func toLogical*(pp: PhysicalPath; root: string): LogicalPath {.raises: []} =
  let s = string(pp)
  if root.len > 0 and s.startsWith(root):
    let relative = s.substr(root.len)
    LogicalPath(relative.strip(chars = {'/'}))
  else:
    LogicalPath(s)
```

### 2.3 Type-Level Protection Rules

1. **Identity/contract computations accept only `LogicalPath`** — compile-time enforced via distinct types. Functions that compute `SourceTreeHash`, `ArtifactDigest`, or closure digests must accept `LogicalPath` parameters.
2. **Runtime file access uses `PhysicalPath`** — `readFile`, `walkDirRec`, `fileExists`, etc. operate on `PhysicalPath`.
3. **No reverse leak** — `LogicalPath` must not escape into ambient filesystem access. There is no `toPhysical(LogicalPath)` function. If a filesystem operation needs a physical path, the caller must supply a `PhysicalPath` explicitly.

### 2.4 Const-Context Deferral (Known PhysicalPath-Leak Locations)

The following trusted-layer const-context sites **cannot** be wrapped in `LogicalPath` because `currentSourcePath()` and `instantiationInfo(-1, true).filename` return `string` in const/macro/template expansion contexts, and wrapping them would break const evaluation, macro expansion, and cascade into widely-imported public APIs. These are documented as known PhysicalPath-leak locations per plan §2's ownership list.

| File | Line(s) | Site | Reason for Deferral |
|---|---|---|---|
| `src/core/trusted/layer_enforcement.nim` | 27 | `const srcPath = currentSourcePath()` | Const context — `currentSourcePath()` returns `string`, cannot be wrapped in distinct type at compile time |
| `src/core/trusted/layer_enforcement.nim` | 158 | `const srcPath = instantiationInfo(-1, true).filename` | Const context in macro — same limitation |
| `src/core/trusted/layer_enforcement.nim` | 193, 199 | `instantiationInfo(-1, true).filename` in `enforceLayer` macro | Macro expansion — return type is `string`, wrapping would break macro contract |
| `src/core/trusted/architecture_invariants.nim` | 34 | `currentSourcePath().parentDir() / "architecture_invariants.nim"` in `const InvariantSourceHash` | Const context — `staticRead` requires `string` argument |
| `src/core/trusted/architecture_invariants.nim` | 173 | `executeAntiSlackingScan(currentSourcePath())` in template | Template expansion — `currentSourcePath()` returns `string` |
| `src/core/trusted/axiom_pragmas_macros.nim` | 280 | `instantiationInfo(-1, true).filename` in `axiomLayerGuard` macro | Macro expansion |
| `src/core/trusted/axiom_pragmas_macros.nim` | 345, 365, 371, 419, 592, 595, 597 | `instantiationInfo(-1, true).filename` / `currentSourcePath()` in macros/templates | Macro/template expansion — all return `string` |
| `src/core/feature_manifest_guard.nim` | 16 | `parentDir(parentDir(parentDir(currentSourcePath())))` in `const projectRoot` | Const context — `currentSourcePath()` returns `string` |
| `src/core/verified_axioms/verified_axioms_catalog_part1.nim` | 18 | `currentSourcePath().parentDir().parentDir().parentDir().parentDir()` in `const dataPath` | Const context — same limitation |
| `src/verification/obligation/canonical_verification.nim` | 76 | `staticRead(currentSourcePath().parentDir()...)` in `const LeanToolchainFile` | Const context — `staticRead` requires `string` |
| `src/cli/version.nim` | 10 | `currentSourcePath().parentDir().parentDir().parentDir()` in `const nimbleContent` | Const context — `staticRead` requires `string` |

**Deferred approach:** These sites remain `PhysicalPath`-typed (i.e., `string`). The `toLogical` boundary and `LogicalPath` type are established for future use. When a const-context site is refactored to a runtime context (e.g., a `proc` instead of a `const`), it should be converted to `LogicalPath` at that time.

### 2.5 Known PhysicalPath-Leak Registry

The following files contain `PhysicalPath`-typed values that have not yet been converted to `LogicalPath`. This list is the PR-2 honesty record about what remains deferred:

- `src/core/trusted/layer_enforcement.nim` — const-context `currentSourcePath()` / `instantiationInfo` embeddings
- `src/core/trusted/architecture_invariants.nim` — const-context `currentSourcePath()` embedding + template `currentSourcePath()` usage
- `src/core/trusted/axiom_pragmas_macros.nim` — macro/template `instantiationInfo(-1, true).filename` and `currentSourcePath()` embeddings
- `src/core/feature_manifest_guard.nim` — const-context `currentSourcePath()` embedding
- `src/core/verified_axioms/verified_axioms_catalog_part1.nim` — const-context `currentSourcePath()` embedding
- `src/verification/obligation/canonical_verification.nim` — const-context `currentSourcePath()` embedding
- `src/cli/version.nim` — const-context `currentSourcePath()` embedding

---

## 3. Closure Evidence & Regression Lists

### 3.1 MutationClosure (Write Direction)

**Definition:** Build tools write **only** to their declared output set. No writes outside the declared output set.

**V2 Evidence (from PR-2 static verification):**

The build pipeline writes **only** under `src/generated/`. No `.nim` file outside `src/generated/` is written by the build process. The write inventory is:

| Write Target | Tool | Declared? |
|---|---|---|
| `src/generated/build_env.nim` | `bin/hermetic_build --materialize` | Yes — hermetic build output |
| `src/generated/type_registry_metadata.json` | `bin/sync_topology` | Yes — topology sync output |
| `src/generated/*.nim` | `bin/install_ax_cas` (CAS materialization) | Yes — CAS content-addressable store output |

**Regression List:** Any new write target outside `src/generated/` is a `MutationClosure` violation and must be registered as debt. The regression check in `tools/ci/d3_substrate_measure.sh` (side-effect closure hash) catches unexpected side effects but does not explicitly enumerate write targets — a dedicated write-inventory gate is planned for PR-3.

### 3.2 DeclaredInputClosure (Read Direction)

**Definition:** Hashes and builds read **only** within the declared input set (`src/**/*.nim` excluding `src/generated/`). Read failures are **never** silently skipped (fail-closed).

**Evidence:**

- `src/core/utils/build_provenance.nim:sourceTreeDigest` — the pure fingerprint kernel (formula `vs1-tree-hash/1`, §3.3): sorts by relative path, binds each path into the digest, and recomposes the tree digest from the caller's live path set.
- `src/infrastructure/source_identity_cache.nim:computeSourceTreeDigestUncached` — the runtime gather+read (fail-closed): walks `src/` recursively, includes only `.nim` files excluding `/generated/`, and raises on any unreadable file. No `except: discard` — read failures are `SourceCoherence FAIL`.
- `tools/hermetic_build.nim:computeDeterministicSourceHash` (build-time): same walk, same kernel (`hashSourceContents`). Note: this proc still uses `except CatchableError: stderr.writeLine(...)` (fail-open for read warnings) — this is a known gap documented as DEBT#454. The canonical SourceCoherence adjudication uses the fail-closed runtime path.
- `src/infrastructure/source_identity_cache.nim:computeSourceTreeDigestCached` — the runtime bootstrap acceleration path (used by `checkAndSelfBootstrap` only): may reuse per-file digests under an unchanged kernel stat identity, but the tree digest is always recomposed from the live walk and the cache is never evidence (§3.3).
- The integrated canonical hash's read set is the declared set: `src/**/*.nim` excluding `src/generated/`.

**Read Failures:** Fail-closed in `computeSourceTreeDigestUncached` / `readAndDigestStable` (raises). Read failures in `computeDeterministicSourceHash` (hermetic_build.nim) are warn-and-skip (fail-open for the hermetic build tool itself, but the canonical SourceCoherence check uses the fail-closed path).

**`staticExec`/env/cwd-dependent reads:** Any read that depends on `staticExec`, environment variables, or CWD must be declared in the input set or forbidden. Currently, no such reads exist in the hash computation path.

### 3.3 SourceTreeHash Formula (`vs1-tree-hash/1`) and the Acceleration Cache

**Formula** (SSOT: `src/core/utils/build_provenance.nim`; twins: `tools/hermetic_build.nim`, `config.nims`):

```text
fileDigest(p) = $hash(bytes(p))
treeDigest    = "vs1-tree-hash/1:" & $hash(
                  "vs1-tree-hash/1\n" & Σ_{p sorted by relPath} relPath(p) & "\0" & fileDigest(p) & "\n")
```

- Paths are bound into the digest (the retired concatenation formula had file-boundary
  ambiguity: `"ab"+"c" ≡ "a"+"bc"`).
- The formula id is folded into the stream AND prefixed onto the value, so a
  `vs1-tree-hash/1:` digest is structurally distinguishable from any pre-vs1 decimal value
  in every persisted copy. Consumers that compare against the previous formula fail closed
  (`VerifierBuildSourceHash != BuildSourceHash` → `cert_reconcile.nim` drops and re-proves);
  no migration path silently accepts an old-formula value.
- `$hash` is Nim's non-cryptographic `system.hash`. This is an identity/consistency
  primitive within a pinned toolchain, not a collision-resistance claim.

**Acceleration cache** (`src/infrastructure/source_identity_cache.nim`, used ONLY by
`checkAndSelfBootstrap`; the `--check-provenance` probe stays uncached):

| Rule | Behavior |
|---|---|
| Entry key | `(relPath, dev, ino, size, mtime_ns, ctime_ns, mode, kind)` from `lstat` (no symlink follow) |
| Reuse condition | full identity equality AND not racily clean (git racy-git rule: `max(mtime, ctime)` second ≥ cache-write second → rehash once) |
| Tree digest | ALWAYS recomposed from the live walk over per-file digests (`sourceTreeDigest`); the walk set itself is never cached |
| Universe | `walkDirRec` default filter (`pcFile` only) over `src/**/*.nim` excluding `/generated/`; a regular `.nim` file replaced by a symlink leaves the universe and changes the digest |
| Read failure | raise (fail-closed) — no reuse can mask an unreadable file because the mode/ctime identity changes |
| Read/scan race | read → re-`lstat`; mismatch → retry once → raise |
| Cache file trust | regular file, owner = effective UID, not group/other-writable, schema + formula id match; otherwise treated as absent |
| Cache corruption / missing key | recompute (never trusted) |
| Cache write | temp file, mode 0600, POSIX `rename(2)` atomic replace; failure ignored (speed only) |
| Evidence status | never evidence, never a verdict input — the recomposed digest is the verdict input |

**Trust boundary (DEBT#524, Option A).** Same-UID processes are INSIDE the trust boundary.
A same-UID writer can forge the cache, the binary, or the source tree; defending against it
is explicitly NOT claimed by this cache. `tests/unit/source_identity_cache_test.nim` pins
that boundary (a forged entry with exact identity is honored) so any future hardening must
change this spec deliberately rather than silently.

**Go/No-Go.** The cache is adopted only if `bin/ax --version` warm wall time saves ≥5× the
measured run-to-run spread AND warm ≤ 25% of the cold wall time; otherwise the code path is
reverted (evidence: `docs/evidence/vs1_source_identity_acceptance_2026-11-12.md`).

---

## 4. Relocation Invariance Regression — RETIRED (non-goal)

**Status: RETIRED (2026-10-12) — this invariant was never wired and is hereby declared a non-goal.**

The §4 `ArtifactDigest` RelocationInvariance invariant — `ArtifactDigest(build(root=A)) == ArtifactDigest(build(root=B))` over the **binary blob** — was **never wired into any executable enforcement**:

- its measuring script `tools/ci/d3_substrate_measure.sh` was **never committed** (absent from the entire `git log --all` history);
- no gate, readiness rule, or test ever asserted it;
- the only code mention (`tools/ci/tcb_judgments.nim:47-49`) classifies `artifactIdDigest` (`ArtifactDigest`, artifact_determinism.md:10) as a substrate key that is **"reported separately, never a failure"**.

This is **not** a silent swap: the invariant is declared a **non-goal**. If artifact-level relocation invariance is ever revived, it must return under a **separate name** with a **separate gate** — it must not inherit this section's name, identity, or authority.

**Live replacement (different contract, different authority):** the relocation invariant in force is `pathIndependentProjectionEqual` over the **canonical result projection** (productization_contract.md §6/R3: semantic equality — explicitly **NOT** raw artifact byte equality). It is measured by `tools/ci/wp5_relocation_measure.nim` (same logical subject at two physical roots, distinct `AXIOM_STATE_DIR`, cold cache policy) and judged by the readiness evaluator: `false` → R3 FAIL; absent/unmeasured → UNKNOWN (fail-closed).

*(The §1 taxonomy row and §1.2 location row above still name `tools/ci/d3_substrate_measure.sh`; those references describe this same never-committed script and are historical. This section is the authority on its status.)*
