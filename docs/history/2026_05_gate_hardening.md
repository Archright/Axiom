# 2026-05 Quality Gate Hardening Wave

## Summary

Eliminated all "warning-only" and "grace period" loopholes in the Axiom quality gate system. Every SRP, DIP, DRY, SoC, and SSOT violation is now an immediate, hard-blocking `error` at pre-commit time. Manual checklists have been converted to mechanical rules enforced by static analysis.

## Changes

### 1. Source-Level Gate (`bin/architecture_gate`)

**New rules added to `src/gate/architecture_guard.nim`:**

- **SRP — Domain Prefix Mechanical Limit (Rule 5b)**
  - Any non-facade/non-catalog module importing from ≥ 3 distinct domain prefixes is blocked immediately.
  - Exemptions: `import-facade`, `srp-catalog` modules (registered in `src/allowed_imports.lock`).
  - `std` library imports are excluded from the count.

- **DIP — Domain → Infrastructure Import Ban (Rule 3 extension)**
  - All `src/core/` → `src/verification/` imports are now hard-fail, not just solver-backend imports.
  - The existing live violation (`src/core/contract_extractor.nim` importing `verification/ast_extractor`) was resolved by splitting into:
    - `src/core/contract_smtlib2.nim` (pure SMT-LIB2 emission)
    - `src/verification/contract_source_extractor.nim` (AST-based source extraction)

- **DRY — Function-Body Fingerprint Clone Detection (Rule 9)**
  - Exported functions across different modules sharing an identical normalized body fingerprint are blocked.
  - False-positive guards:
    - Minimum complexity: AST depth ≥ 4 or token count ≥ 20.
    - Boilerplate whitelist: Result error-propagation, nil guards, simple getters, constructor patterns.

- **SoC/SSOT — Constitutional Linter (Rule 0)**
  - New lock file: `src/gate/constitutional_rules.lock`
  - Mechanical enforcement of module-boundary rules from `architecture-principles/SKILL.md`:
    - `analyzer.nim` must not contain gate logic
    - `gate_rules.nim` must not contain report rendering
    - `reporter.nim` must not contain AST extraction
    - Direct `cert.status=` / `cert.reason=` assignments outside `certificate_manager.nim` are blocked

### 2. Certificate-Level Gate (`gate_rules_architecture.nim`)

Severity escalation: all former `agWarning` violations are now `agBlocking`:

| Check | Former Severity | New Severity |
|-------|----------------|--------------|
| `applyLowCohesionCheck` (SRP) | `agWarning` | `agBlocking` |
| `applyDryCheck` (DRY) | `agWarning` | `agBlocking` |
| `applyDirectConcreteDependencyCheck` (DIP) | `agWarning` | `agBlocking` |
| `applyResourceFanoutCheck` (SoC) | `agWarning` | `agBlocking` |
| `applyCallDepthCheck` (SoC) | `agWarning` | `agBlocking` |
| `applyInterfaceUsageCheck` (ISP) | `agWarning` | `agBlocking` |

### 3. ASI Hard Gate

- `scripts/gates/asi_hard_gate.nim` converted from **warning-only** to **hard-fail**.
- Any ASI value below `1.0000` now exits with code 1 and blocks push.

### 4. GUARDIAN.md Penalty Table Update

| Violation | Former Penalty | New Penalty |
|-----------|---------------|-------------|
| DRY duplicate fingerprint | Warning / 1 sprint | **Blocking / Immediate pre-commit failure** |
| DIP concrete dependency | Warning / ASI 0.05 | **Blocking / Immediate pre-commit failure** |
| SRP high cohesion | Warning / 3rd occurrence | **Blocking / Immediate pre-commit failure on first occurrence** |

### 5. Documentation Updates

- `architecture-principles/SKILL.md` updated to mark checklist items as "mechanically enforced by `bin/architecture_gate` — agent need not verify manually."

## Live Tech Debt Snapshot

As of the hardening commit, `bin/architecture_gate` reports **40 existing SRP import-prefix violations** in the codebase. These are pre-existing architectural debt, not regressions introduced by the gate changes. They must be resolved incrementally; the gate blocks **new** violations in staged files immediately.

Key debt clusters:
- `src/cli/commands/heal*.nim` — orchestration files importing many sibling command modules
- `src/verification/analyzer.nim` — analysis facade importing 10 distinct verification subdomains
- `src/core/global_symbol_graph.nim`, `src/core/proof_universe_lock.nim` — large cross-cutting state modules

## Atomic Re-Convergence Requirement

Because the cert-gate escalation turns every former `agWarning` into `agBlocking`, the commit that lands these hardened gates **must** be bundled with:

```bash
./bin/ax prove --force --clean-all
```

This regenerates the entire certificate vault under the new blocking rules. If any certificate still triggers a former-warning-now-blocking violation, it indicates live tech debt that must be fixed before the commit lands.

## Files Modified

- `src/gate/architecture_guard.nim`
- `src/gate/constitutional_rules.lock` (new)
- `src/verification/gate_rules_architecture.nim`
- `scripts/gates/asi_hard_gate.nim`
- `src/core/contract_extractor.nim` (deleted)
- `src/core/contract_smtlib2.nim` (new)
- `src/verification/contract_source_extractor.nim` (new)
- `src/cli/commands/recertify_lean.nim`
- `tests/unit/contract_extractor_test.nim`
- `tests/unit/test_type_purity.nim`
- `GUARDIAN.md`
- `.agents/skills/architecture-principles/SKILL.md`
- `docs/history/2026_05_gate_hardening.md` (this file)
