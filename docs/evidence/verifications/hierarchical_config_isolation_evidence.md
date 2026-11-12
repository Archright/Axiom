# Hierarchical Configuration Isolation — Verification Evidence

## Date: 2026-07-07
## Author: Guard Domain Inversion v3

## 1. Problem Statement

### 1.1 v1: Environment Variable Bypass (AXIOM_GATE_BOND)
- POSIX shell dependency (`AXIOM_GATE_BOND=1 nim c ...`)
- Non-deterministic: shell state affects compilation
- SoS breach: manual hardcoding required for each binary
- Removed in v9.5 (REMOVED in v10 — replaced by projectDir()-based structural guard)

### 1.2 v11: Path-Based Blacklist (projectDir() string matching)
- `projectDir()` returns CWD-dependent values
- String matching (`startsWith`) depends on filesystem runtime state
- Fail-Open: new domains bypass guard by default
- Violates deterministic reproduction principle

### 1.3 v2 (rejected): Compiler Flag (-d:AxiomBootstrap)
- Artificial backdoor flag exposed in compilation layer
- Depends on build orchestrator to inject flag correctly
- Global configuration pollution: root config.nims interferes with all builds

## 2. Solution: Hierarchical Configuration Isolation

### 2.1 Principle
Nim compiler processes config files hierarchically:
```
$parentDir/config.nims → $projectDir/config.nims → $project.nims
```

By placing guards in domain-specific directories, the guard activates ONLY when compiling files in that domain.

### 2.2 Implementation
| File | Scope | Content |
|------|-------|---------|
| `src/gate/config.nims` | Gate domain only | bin/main check + hooks verification |
| `tests/config.nims` | Test domain only | bin/main check |
| `config/integrity.nims` | Project-wide | Policy artifacts, merkle root, build constraints |

### 2.3 Compilation Flow
```
nim c src/cli/main.nim → root config only → NO guard → success (bootstrap possible)
nim c src/gate/runners/X.nim → root config + src/gate/config.nims → guard active → requires bin/main
nim c tests/X.nim → root config + tests/config.nims → guard active → requires bin/main
```

## 3. Context7 Verification

| Nim Feature | Status | Source |
|-------------|--------|--------|
| Hierarchical config lookup | ✅ Official | nims.md |
| `$parentDir/config.nims` auto-apply | ✅ Official | nimc.md |
| `thisDir()` = current .nims directory | ✅ Official | NimScript stdlib |
| `static:` block with `fileExists` | ✅ Official | NimScript stdlib |

## 4. Design Principles Achieved

| Principle | v1 | v11 | v2 | **v3** |
|-----------|-----|------|-----|--------|
| Deterministic | ❌ Shell state | ❌ CWD | ✅ | ✅ |
| Fail-Safe | ❌ Fail-Open | ❌ Fail-Open | ✅ | ✅ |
| SoC | ❌ Global pollution | ❌ Global pollution | ❌ Artificial flag | ✅ Domain isolation |
| Bypass flags | AXIOM_GATE_BOND (REMOVED in v10 — replaced by projectDir()-based structural guard) | projectDir() | -d:AxiomBootstrap | **None** |
| Path parsing | env vars | startsWith | None | **None** (thisDir() is file-location fixed) |

## 5. Bootstrap Paradox Resolution

The bootstrap paradox ("binary must exist to compile itself") is structurally eliminated:
- Core engine (`src/cli/main.nim`) compiles without any guard
- Gate runners (`src/gate/runners/*.nim`) require `bin/main` to exist
- Test suites (`tests/*.nim`) require `bin/main` to exist
- No artificial bypass flags, no environment variables, no path parsing
