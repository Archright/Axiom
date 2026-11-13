# Filesystem Contract V2

Status: NORMATIVE

Revision 2026-11-13 (VS-1 config SSOT migration): `topology.json`, `topology_policy.json`, and `promotion_intent.json` removed from root EXACT_ALLOWED (§2.4) — canonical locations are now `config/topology.json`, `config/topology_policy.json`, `config/promotion_intent.json` (policy/threshold home per §2 role table); root re-entry is denied as clUnknown.

Revision 2026-11-13 (VS-0 root dead-entry removal): lfs_exceptions.json, .env.example, and .envrc.example removed from EXACT_ALLOWED (§2.4).

Revision 2026-11-09 (VS-I publication-integrity gate): `compliance/` registered as an EXACT_ALLOWED tracked content directory (§2.4) — publication policy SSOT home (merge_admission v1.20.0 trustSurface content).

Revision 2026-11-06 (Gate 3 SAL 1.0): `THIRD-PARTY-NOTICES.md` registered as an EXACT_ALLOWED single file; `LICENSES/`·`CLA/` registered as EXACT_ALLOWED tracked content directories (§2.4) — SAL 1.0 publication surface.

Revision 2026-11-09 (VS-I publication-integrity): `compliance/` registered as an EXACT_ALLOWED tracked content directory (§2.4) — the publication gate's policy SSOT zone (license/security/provenance policies, secret-scan baseline, source-origin + license-attribution declarations).

Revision 2026-11-04 (VS-1 root-write-closure PR-1): `ci/`·`experiments/`·`_lto_evidence/` registered as EXACT_ALLOWED tracked content directories (§2.4); `bin/axiom.nim` registered as the §7.1 legacy exception; §6 Enforcement Scope added; `logs/` tracked-status git failure now fail-closed in the validator.

---

## 1. Purpose

This contract defines a closed-by-default classification of every repository-root entry (file or directory). It provides deterministic pass/fail criteria for the `validate_root_manifest` tool and establishes relocation semantics for any migration between classified categories.

---

## 2. Classification Categories

Each root-level entry is assigned exactly one category using the judgment order below. An entry matches only the first matching rule.

### 2.1 REQUIRED

Entry must exist at the repository root. Absence → FAIL.

| Entry | Description |
|---|---|
| `src/` | Source code tree |
| `tests/` | Test suite |
| `tools/` | Tooling and CI scripts |
| `proofs/` | Formal proof artifacts |
| `data/` | Measurements, evidence, baselines |
| `docs/` | Specification and documentation |
| `config/` | Policy, thresholds, waivers |

### 2.2 OPTIONAL

Entry may be absent → PASS. If present, its contents are subject to the contents contracts defined in §7.

| Entry | Description |
|---|---|
| `bin/` | Canonical execution surface + compiled gate binaries |
| `build/` | Generated build state |
| `logs/` | EPHEMERAL — runtime-only; 이 경로의 canonical 승격 금지(승격은 data/·docs/로만) |
| `vendor/` | Vendored third-party dependencies |

### 2.3 FORBIDDEN

Entry must NOT exist at the repository root. Presence → FAIL (unless explicitly listed via `--expected-forbidden` during migration).

**Directories:**

| Entry | Reason |
|---|---|
| `cli/` | Merged into `src/cli/`; root-level CLI dir is legacy |
| `templates/` | Moved to `docs/templates/` (done in migration) |
| `benchmarks/` | Moved to `data/benchmarks/` (SSOT) |
| `trusted/` | Relocated to `data/trusted/` per I2 |
| `tmp/` | Ephemeral; should not be committed |
| `deps/` | Managed by Nim package manager; should not be committed |
| `nimcache/` | Deleted build cache — regeneration is a contract violation |
| `.nimcache/` | Deleted build cache — regeneration is a contract violation |
| `.lake/` | Deleted root-level Lean cache (proofs/.lake is the canonical one) |

**Files:**

| Entry | Reason |
|---|---|
| `debug_real.nims` | Debug-only compiler flag file |
| `deferred_migration.json` | Migration tracking artifact |
| `proof_universe.lock` | Legacy duplicate universe lock — canonical은 `data/universe_merkle.lock` (ADR-001 · docs/agents/core_rules.md RL-14.12 sole authority) — 이중 방어(re-life 정상 git topology 제외 + 회귀 탐지) |

**Pattern:**

| Pattern | Rule |
|---|---|
| `.env*` (except `.env.<env>` where env ∈ {production, development, staging, test, local}) | Explicitly forbidden — environment-specific dotenv files must use the `<env>` suffix pattern |

### 2.4 EXACT_ALLOWED

Entry exists at the root → PASS (no further content inspection).

**Single files:**

| Entry |
|---|
| `AGENTS.md` |
| `README.md` |
| `LICENSE` |
| `THIRD-PARTY-NOTICES.md` |
| `Makefile` |
| `axiom.nimble` |
| `config.nims` |
| `nimble.lock` |
| `axiom.lock` |
| `axiom.toml` |
| `topology.lock` |
| `flake.nix` |
| `lakefile.toml` |
| `lake-manifest.json` |
| `lean-toolchain` |
| `Dockerfile.build` |

**Dot / toolchain files:**

| Entry |
|---|
| `.axiom_root` |
| `.gitignore` |
| `.gitattributes` |
| `.editorconfig` |
| `.dockerignore` |
| `.cursorrules` |
| `.envrc` |

**Dot / toolchain directories:**

| Entry |
|---|
| `.githooks/` |
| `.github/` |
| `.config/` |
| `.opencode/` |

**VCS / runtime state directories (EXACT_ALLOWED):**

| Entry | Rationale |
|---|---|
| `.git/` | VCS-internal — always outside the contract |
| `.axiom/` | CLI runtime state (untracked) |
| `.cache/` | Tool cache (untracked) |

**Tracked content directories (EXACT_ALLOWED):** Presence → PASS (no contents contract — tracked content zones, distinct from the generated/ephemeral OPTIONAL zone).

| Entry | Rationale |
|---|---|
| `ci/` | CI checker definitions (Tier C closure member — `ci/checker.mk`) |
| `compliance/` | Publication gate policy SSOT (VS-I: license/security/provenance policies, secret baseline, origin + attribution declarations) |
| `LICENSES/` | Third-party license full texts (SAL 1.0 publication surface — `THIRD-PARTY-NOTICES.md` counterparts) |
| `CLA/` | Contributor License Agreements (individual/entity — external contribution gate) |
| `experiments/` | Tracked experiment records |
| `_lto_evidence/` | Tracked LTO measurement evidence |
| `compliance/` | Publication-integrity policy SSOT (license/security/provenance policy, secret-scan baseline, per-path origin + attribution declarations — VS-I, merge_admission v1.20.0 trustSurface content) |

**Ignored root entries (EXACT_ALLOWED):** These files may exist at root but are not tracked as part of the contract surface. Their presence → PASS.

| Entry |
|---|
| `config.json` |
| `nimble.paths` |
| `opencode.json` |

### 2.5 PATTERN_ALLOWED

Entry matches a defined pattern → PASS.

| Pattern | Allowed values |
|---|---|
| `.env.<env>` | `env` ∈ {production, development, staging, test, local} |

Any other `.env*` file (e.g., `.env`, `.env.secret`) falls through to FORBIDDEN (§2.3).

---

## 3. Judgment Order

Classification proceeds in this fixed order. The first matching rule determines the category:

```
EXACT_ALLOWED → PATTERN_ALLOWED → FORBIDDEN → OPTIONAL → REQUIRED → UNKNOWN
```

---

## 4. Final Verdict Logic

| Condition | Result |
|---|---|
| Any REQUIRED entry missing | FAIL |
| Any FORBIDDEN entry present (not in `--expected-forbidden`) | FAIL |
| Any UNKNOWN entry present | FAIL |
| All OPTIONAL entries absent | PASS |
| OPTIONAL entry present | Contents contract check (§7) |
| EXACT_ALLOWED or PATTERN_ALLOWED entry present | PASS |

Exit codes: `0` = PASS, `1` = violation.

---

## 5. Invariants

### I1 — Closed-by-Default

> Filesystem Contract V2 is closed-by-default: every repository-root entry must be explicitly classified as required, optional, allowed, forbidden, or explicitly pattern-allowed. Any unclassified root entry is a contract violation.

### I2 — Relocation Neutrality

> Path relocation MUST preserve lifecycle, canonicality, and VCS-tracking semantics unless the migration explicitly declares a semantic change.

Example: `trusted/` ignored → `data/trusted/` ignored. Lifecycle hooks, VCS tracking mode, and access patterns must remain equivalent after relocation.

---

## 6. Enforcement Scope

The verdict of this contract is an **admission gate**, not a filesystem permission system.

**What admission paths guarantee.** The admission paths — push-admissibility, required CI checks, and the merge queue — guarantee only that a FAIL verdict **blocks entry into an approved state** (a push, a green required check, a merge). They do NOT physically prevent local writes: a developer clone may materialize untracked FORBIDDEN/UNKNOWN root entries at any time; the contract's answer is that such a state is not admissible, not that it cannot exist.

**Push-admission visibility boundary.** Push-admission executes in an OID snapshot — `.githooks/pre-push` creates it with `git worktree add --detach <SNAP> <OID>` (pre-push:189) and runs `make -C <SNAP> push-admissibility` (pre-push:212) — so **untracked local files are invisible** to it: the snapshot contains exactly the pushed tree's tracked entries. A FORBIDDEN/UNKNOWN entry that exists only untracked-local fails `validate-root-layout` in the live clone and any clean checkout, but never fails push-admission for the pushed OID.

**The sole CWD-judgment exception** is `gate_tier_integrity` at pre-push:14, which judges the live working tree (the dirty tracked-file vector) before any snapshot is created.

**Consequence.** Live-clone cleanliness is enforced where it is observable — `validate-root-layout` runs in the local verify surfaces (GATES_FAST) and fails on any live untracked FORBIDDEN/UNKNOWN entry — while admission verdicts bind only to the tracked content of the OIDs they judge.

---

## 7. OPTIONAL Contents Contracts

When an OPTIONAL entry is present, its contents are inspected against these rules. Violations → FAIL.

### 7.1 `bin/` — Canonical Execution Surface

**Allowed categories (in priority order):**

1. **Canonical surface names**: `ax`, `run_gate`, `axiom-gate`
2. **Hash-suffix binaries**: `<base>_<HEX≥8>` — e.g., `all_gateway_runner_30E4111AC69224A015CED3B9CADA98FD66CC383B`
3. **ELF executables**: Any dynamically linked ELF binary without a forbidden extension
4. **Other ELF binaries**: Any ELF executable that does not match a forbidden name pattern

**Legacy exception (grandfathered):** `bin/axiom.nim` — tracked Nim source stub (compile-time gate stub detection, NOT ELF), grandfathered under I2; tracked before the contents contract and not relocated in this revision.

**Unclassified materialization**: any file that is NOT one of the above (not canonical surface, not hash-suffix, not ELF, not a grandfathered legacy exception) → FAIL. The `bin/` directory is single-depth: subdirectories → FAIL.

**Prohibited:**

- Shebang/text scripts (files starting with `#!`)
- Source extensions: `.nim`, `.nims`, `.c`, `.py`, `.sh`
- Secret-classified names: `.env*`, `*.pem`, `*.key`, `id_rsa*`
- Nested subdirectories (single directory depth only)

### 7.2 `build/` — Generated Build State

Generated-build-state zone. Arbitrary internal structure is allowed.

**Prohibited:**

- Secret files: `.env*`, `*.pem`, `*.key`, `id_rsa*`

### 7.3 `logs/` — EPHEMERAL runtime-only

Runtime-only ephemeral log zone. Canonical evidence must never be promoted from this path; promotion is allowed only into `data/` or `docs/`.

**Rules:**

1. No tracked files permitted — `git ls-files logs/` must return empty. An unreadable git result (non-zero exit) is a FAIL (tracked-status UNKNOWN — fail-closed), never a silent skip; absence of `logs/` itself still skips the check (no git call).
2. `.gitignore` must block the `logs/` directory (e.g., `logs/*`).
3. Canonical evidence promotion is allowed only into `data/` or `docs/`; no other path qualifies.

**Prohibited:**

- Secret files: `.env*`, `*.pem`, `*.key`, `id_rsa*`

### 7.4 `vendor/` — Vendored Dependencies

Two-class model:

| Class | Entry | Policy |
|---|---|---|
| **CANONICAL + TRACKED** | `vendor/ed25519/` | Repository-owned source; internal `.git` prohibited |
| **EXTERNAL (PRODUCT_DEPENDENCY)** | `vendor/z3/` | Tree absence permitted; fetch-time version + artifact sha256 authentication required; manual procedure prohibited |

**Prohibited:**

- Secret files: `.env*`, `*.pem`, `*.key`, `id_rsa*`

### 7.5 `data/` — Measurement & Evidence Storage

`data/` is a REQUIRED root entry (§2.1); this subsection documents the contents contract for its ephemeral sub-entry `data/proof_cache/` (absent at rest; generated at runtime).

| Sub-entry | Category | Policy |
|---|---|---|
| `data/proof_cache/` | EPHEMERAL — gitignored, runtime-generated | ALLOWED-as-ignored; never canonical-promoted |

**Rules:**

1. No tracked files permitted — `git ls-files data/proof_cache/` must return empty; `.gitignore` blocks `data/proof_cache/`.
2. Regenerable on demand — deletion is always safe; absence at rest is expected.
3. Canonical promotion is allowed only into `data/` or `docs/`; `data/proof_cache/` is never a canonical-promotion target.

**Prohibited:**

- Secret files: `.env*`, `*.pem`, `*.key`, `id_rsa*`

---

## 8. CLI Usage

```
validate_root_manifest [--root <dir>] [--expected-forbidden <path>...] [--strict]
```

| Flag | Default | Behavior |
|---|---|---|
| `--root <dir>` | cwd | Root directory to validate |
| `--expected-forbidden <path>` | (none) | Repeatable. Allows specific FORBIDDEN entries to exist without causing FAIL. Used during migration intermediate states. Affected entries print "expected (deferred)" instead of FAIL. |
| `--strict` | off | When set, `--expected-forbidden` relaxations are ignored — ALL FORBIDDEN entries FAIL. |

**Output format on FAIL:**

```
FAIL: <path> <category>
...
SUMMARY: N violation(s) found
```

**Output format on PASS:**

```
PASS: filesystem contract validated
```

---

## Appendix A — Migration Baseline Snapshot

Status: HISTORICAL / NON-NORMATIVE

The following snapshot records the repository root state at the time of this contract's introduction. Entries listed here are acknowledged as existing but classified as FORBIDDEN. They are expected to be migrated or removed in subsequent work.

### Existing FORBIDDEN entries (at contract introduction):

| Entry | Type | Status |
|---|---|---|
| `cli/` | Directory | Deferred migration |
| `templates/` | Directory | Deferred migration |
| `benchmarks/` | Directory | Deferred migration |
| `trusted/` | Directory | Deferred migration (→ `data/trusted/`) |
| `tmp/` | Directory | Deferred migration |
| `deps/` | Directory | Deferred migration |
| `debug_real.nims` | File | Deferred removal |
| `deferred_migration.json` | File | Deferred removal |

These entries can be validated with exit 0 using:

```
validate_root_manifest --expected-forbidden cli templates benchmarks trusted tmp deps debug_real.nims deferred_migration.json
```


