# Axiom_Enterprise Dependency Health Report

**Generated:** 2026-05-26  
**Project:** Axiom_Enterprise v0.3.6  
**Nim:** 2.2.10 (latest stable)  
**Nimble:** 0.14.2

---

## Summary

| Metric | Value |
|--------|-------|
| Total declared deps | 3 (nim, malebolgia, checksums) |
| Undeclared but used | 1 (fusion) |
| Total installed (pkgs2) | 24 packages |
| Axiom-relevant | 4 packages |
| Lock file exists | Yes (nimble.lock, v2) |
| Lock file in sync | Partially (missing fusion) |
| `nimble check` result | PASSED |
| Outdated deps | 0 |
| Version conflicts | None |
| Security issues | None known |

---

## Dependency Details

### 1. nim

| Field | Value |
|-------|-------|
| **Status** | Declared (requires) |
| **Constraint** | `>= 2.0.0` |
| **Installed** | **2.2.10** (via choosenim toolchain) |
| **Latest Available** | **2.2.10** |
| **Verdict** | LATEST STABLE - OK |
| **Notes** | Nim 2.0.8 also installed in pkgs2 (probably for CI compatibility testing) |

### 2. malebolgia (https://github.com/Araq/malebolgia)

| Field | Value |
|-------|-------|
| **Status** | Declared (requires `>= 1.0.0`) |
| **Installed** | **1.3.2** (git commit ab17bef) |
| **Latest Available** | **1.3.2** |
| **Verdict** | LATEST - OK |
| **Actual Usage** | **NOT imported anywhere in the codebase** |
| **Recommendation** | Consider removing from requires if unused; or add `import malebolgia` if needed |

### 3. checksums (https://github.com/nim-lang/checksums)

| Field | Value |
|-------|-------|
| **Status** | Declared (requires `>= 0.2.0`) |
| **Installed** | **0.2.2** (git commit 0845c73) |
| **Latest Available** | **0.2.2** |
| **Verdict** | LATEST - OK |
| **Actual Usage** | **NOT imported anywhere in the codebase** |
| **Recommendation** | Consider removing from requires if unused |

### 4. fusion (https://github.com/nim-lang/fusion)

| Field | Value |
|-------|-------|
| **Status** | **UNDECLARED** |
| **Installed** | **1.2** (git commit 0b0a027) |
| **Latest Available** | **1.2** |
| **Verdict** | LATEST - OK, but MISSING from requires |
| **Actual Usage** | `import fusion/matching` in `src/gate/rule_patterns.nim` |
| **Recommendation** | **MUST ADD** `requires "fusion >= 1.0.0"` to axiom.nimble |

---

## Transitive Dependencies (Not Used by Axiom)

The following packages are installed in `~/.nimble/pkgs2/` but are NOT imported or used by this project. They likely belong to other projects on this system (e.g., Nimbus/status-im ecosystem):

| Package | Version | License |
|---------|---------|---------|
| bearssl | 0.2.5 | ? |
| chronicles | 0.10.3 | ? |
| chronos | 4.0.4 | ? |
| faststreams | 0.3.0 | ? |
| httputils | 0.3.0 | ? |
| json_rpc | 0.5.0 | ? |
| json_serialization | 0.2.9 | ? |
| nimcrypto | 0.6.2 | ? |
| regex | 0.26.1 | ? |
| results | 0.5.1 | ? |
| serialization | 0.2.6 | ? |
| stew | 0.2.0 | ? |
| stint | 0.8.1 | ? |
| testutils | 0.5.3 | ? |
| unicodedb | 0.13.2 | ? |
| unittest2 | 0.2.4 | ? |
| websock | 0.2.0 | ? |
| with | 0.5.0 | ? |
| zlib | 0.1.0 | ? |

These 19 packages are NOT in Axiom's nimble.paths or build path, so they don't affect the project.

---

## Lock File Analysis

**File:** `nimble.lock`  
**Format:** v2  
**Content:** Locks nim, malebolgia, checksums with VCS revisions and SHA1 checksums  
**Issue:** Does NOT include fusion (undeclared dependency)  
**Modification:** May 22, 2026 (precedes last axiom.nimble edit on May 25)  

---

## Build Configuration (config.nims)

| Flag | Value |
|------|-------|
| threads | on |
| mm | orc |
| warningAsError | UnusedImport |
| path | `$projectDir/src`, `src`, compiler root |

---

## Recommendations

1. **HIGH PRIORITY:** Add `requires "fusion >= 1.0.0"` to axiom.nimble -- fusion/matching is actively imported and used in `src/gate/rule_patterns.nim`
2. **MEDIUM PRIORITY:** Run `nimble lock` after adding fusion to update nimble.lock
3. **LOW PRIORITY:** Investigate whether malebolgia and checksums are actually needed -- they are declared as dependencies but never imported anywhere in src/ or tests/
4. **INFO:** All declared dependencies are at their latest available versions -- no updates needed
5. **INFO:** No version conflicts detected across the dependency tree
6. **INFO:** No known security advisories for any of the used dependencies
