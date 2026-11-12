# Structural Enforcement Architecture

> Single source of truth for the Axiom structural enforcement system.
> Created as part of the Structural Enforcement Plan v3.

---

## 1. Overview

The Axiom project uses a multi-layered enforcement system to prevent architectural
violations at **compile time**, **build time**, and **CI time**. The goal is to make
structural violations **impossible to ship** — errors are caught as early as possible
in the development pipeline.

The enforcement system is organized into five layers, each with a distinct role:

| Layer | Name | When | Mechanism |
|-------|------|------|-----------|
| 1 | Compile-Time Macro | Compile | Nim AST macro (`staticRead` + `error()`) |
| 2 | Layer Declaration | Compile | Pragmas + path-based inference |
| 3 | Gate Diagnostic | Build / CI | Structured violation reporting |
| 4 | Negative Test Suite | CI | Regression tests that *must* fail |
| 5 | Pre-existing Gates | Build / CI | Existing gate runners in `src/gate/runners/` |

---

## 2. Enforcement Layers

### 2.1 Layer 1: Compile-Time Structural Safety Guard

- **Module**: `src/core/trusted/enforce_structural_safety.nim`
- **Activation**: `-d:axiomStrict` (injects macro globally via `config.nims`)
- **Mechanism**: `macro enforceStructuralSafety*(moduleBody: untyped): untyped` —
  parses the Nim AST of every module at compile time. Zero runtime cost.

**Checks performed** (all at compile time):

| # | Check | Violation → |
|---|-------|-------------|
| 1 | `ref object` must not contain `proc`/`func` fields | Compile error — use closures or method dispatch |
| 2 | `func` must not have `var` parameters | Compile error — use `let` or value types |
| 3 | `core/` must not import `gate/`, `src/cli/`, `verification/`, `frontend/`, `mcp/` | Compile error — use contract/adapter modules |
| 4 | Bare `except:` and `except Exception:` rejected | Compile error — use `except CatchableError:` or specific types |

**Exception hygiene exemptions** (bypass check 4):
- `stdlib_shield` — intentionally catches `Exception` for stdlib interop
- `artifact_manifest` — documented policy exception
- `sharded_log` — documented policy exception

**How it works**: The macro is a passthrough — it inspects the AST but returns it
unchanged. The `when defined(axiomStrict):` guard means the checks only activate
when the flag is set, saving ~1-2s per build when not needed.

### 2.2 Layer 2: Layer Declaration Pragmas

- **Module**: `src/core/trusted/layer_declaration.nim`
- **Pragmas**: Module-level declarations that tag each source file with its architectural layer.
- **Inference**: `inferLayerFromPath(path: string): string` maps file paths to layers.

**Layer pragmas**:

| Pragma | Layer | Source directories |
|--------|-------|--------------------|
| `{.domainLayer.}` | domain | `src/core/` |
| `{.infrastructureLayer.}` | infrastructure | `src/verification/`, `src/engine/`, `src/frontend/`, `src/infrastructure/`, `src/personas/`, `src/generated/` |
| `{.presentationLayer.}` | presentation | `src/cli/`, `src/mcp/`, `src/ui/`, `src/api/` |
| `{.gateLayer.}` | gate | `src/gate/`, `src/policy/` |
| `{.toolLayer.}` | tools | `tools/` |

**Path-based inference** (`inferLayerFromPath`):

```
src/core/                        → domain
src/verification/                → infrastructure
src/engine/                      → infrastructure
src/frontend/                    → infrastructure
src/infrastructure/              → infrastructure
src/personas/                    → infrastructure
src/generated/                   → infrastructure
src/cli/                         → presentation
src/mcp/                         → presentation
src/ui/                          → presentation
src/api/                         → presentation
src/gate/                        → gate
src/policy/                      → gate
tools/                           → tools
(anything else)                  → unknown
```

Layer declarations serve as metadata for macro-based validation and documentation.
They enable the layer_enforcement macro (when present) to validate imports against
declared layer membership.

### 2.3 Layer 3: Gate Diagnostic (Reporting)

- **Module**: `src/gate/gate_types_impl.nim`
- **Activation**: Always available (no flag required).
- **Purpose**: Structured violation representation and formatting across all gates.

**Types**:

```nim
type
  Severity* = enum
    seInfo      ## Informational — no action required
    seWarning   ## Warning — action recommended
    seError     ## Error — must be fixed
    seCritical  ## Critical — blocks CI

  RuleId* = enum
    riImportEncapsulation  ## Import encapsulation boundary
    riLayerViolation       ## Architectural layer violation
    riCycleDetected        ## Import graph cycle
    riEffectMissing        ## Missing {.axiomEffect.} pragma
    riDebtExpired          ## Debt item past target date
    riImportLint           ## tools/ or core/ import lint
    riSrPViolation         ## Single Responsibility Principle
    riTopologyDrift        ## topology.lock drift
    riEchoViolation        ## echo() in production code
    riIoLeakage            ## Uncontrolled I/O in core/
    riDebtBudget           ## Debt budget exceeded

  GateViolation* = object
    file*: string        ## Source file path
    line*: int           ## Line number
    column*: int         ## Column (0 if unknown)
    rule*: RuleId        ## Rule identifier
    severity*: Severity  ## Severity level
    message*: string     ## Human-readable description
    remediation*: string ## Path to remediation docs
```

**Output format**:

```
Error: [LayerViolation] at src/cli/foo.nim:42
  cli imports gate/pipeline_orchestrator
  See docs/agents/rules_workflow.md for remediation.
```

**API**:

| Proc | Purpose |
|------|---------|
| `formatViolation(v: GateViolation): string` | Format a single violation |
| `formatGateReport(gateName, violations, mode): string` | Format a complete gate report |
| `makeViolation(file, line, rule, message, severity, remediation): GateViolation` | Convenience constructor |

**Default remediation links**:

| Constant | Path |
|----------|------|
| `DefaultRemediation` | `docs/agents/rules_workflow.md` |
| `ArchitectureRemediation` | `docs/agents/architecture.md` |
| `ConstitutionRemediation` | `docs/agents/constitution_details.md` |

### 2.4 Layer 4: Negative Test Suite (Regression)

- **Module**: `tests/architecture/test_structural_enforcement.nim` (planned)
- **Purpose**: Tests that **must fail** — verifying that violations are correctly caught.
- **Mode**: Fail-soft in dev mode (`-d:axiomDevMode` → warn), hard block in release mode.

**Test categories**:

| Test | What it verifies |
|------|-----------------|
| Delta-zero | No new violations beyond baseline |
| Debt budget | Violation counts within budget |
| Snapshot isolation | No unexpected structural changes |

Negative tests are the regression safety net — they ensure that when a gate catches
a violation today, it will continue to catch it tomorrow.

### 2.5 Layer 5: Pre-existing Gates

These gates already exist in `src/gate/runners/` and form the backbone of
structural enforcement. They run as part of the CI gate pipeline.

| Gate | Runner | Scope |
|------|--------|-------|
| Import Encapsulation | `import_encapsulation_gate.nim` | Hub module encapsulation — `hubMapping` controls which modules can import which core sub-modules |
| DAG Enforcement | `dag_enforcement_gate.nim` | Core import graph acyclicity — prevents circular dependencies |
| Dependency Rules | `dependency_rules_gate.nim` | Layer-based allowlist + Dependency Inversion Principle enforcement |
| Topology Policy | `topology_policy_gate.nim` | `topology.lock` drift detection — ensures declared topology matches actual |
| Structural Safety | `structural_safety_gate.nim` / `structural_safety_gate_runner.nim` | Wraps `enforceStructuralSafety` macro output into gate report format |
| NimTry Gate | `nimtry_gate.nim` | Counts bare `try:` without typed except — debt tracking |
| Validate Effect Hints | `validate_effect_hints_gate.nim` | Ensures `{.axiomEffect.}` pragmas are present on all `proc` definitions |
| Debt Blocker | `debt_blocker_gate.nim` | Blocks merge when debt budget is exceeded |
| Debt CT | `debt_ct_gate.nim` | Compile-time debt counting |
| Language Ban | `language_ban_gate.nim` | Enforces Nim-only source policy (no Python/Shell) |
| Core Invariant | `core_invariant_gate.nim` | Validates core/ invariants |
| AST Integrity | `ast_integrity_gate.nim` | AST-level integrity checks |

---

## 3. Rule Registry

All enforcement rules are defined as **Nim `const`** in `src/gate/gate_consts.nim`.
This is the single source of truth for rule definitions — gates read these constants
at compile time.

### 3.1 ImportLintRules — REMOVED (dead code)

~~ImportLintRules was a dead const array[2, LayerRule] that nobody enforced.~~
~~`layer_enforcement.nim` uses `LayerRules`; `check_imports_ast.nim` and~~
~~`import_lint.nim` used their own hardcoded lists.~~

**Removed in cleanup**: The `ImportLintRules` const was deleted from
`src/core/trusted/layer_rules.nim`. The authoritative SSOT is `LayerRules`
(12-entry array). No gate runner consumes ImportLintRules.

### 3.2 LayerRules (12 rules)

Architectural layer enforcement — defines the dependency DAG:

```
          tools/
            │
            ▼
      ┌─── core/ ◄─── (domain layer, no upward imports)
      │     │
      │     ▼
      │  verification/    engine/    gate/  ←── infrastructure + gate layers
      │     │                │          │
      └─────┴────────────────┴──────────┘
                    │
                    ▼
               src/cli/  src/mcp/  api/            ←── presentation layer (top of DAG)
```

| Rule | Source | Allowed | Forbidden |
|------|--------|---------|-----------|
| core/ | `src/core/` | core/ | src/cli/, gate/, engine/, frontend/, mcp/ |
| verification/ | `src/verification/` | core/, verification/, gate/, infrastructure/, src/cli/selection_state | mcp/ |
| engine/ | `src/engine/` | core/, engine/ | src/cli/, mcp/, gate/, verification/ |
| gate/ | `src/gate/` | core/, gate/, infrastructure/, shared_types/, src/cli/cli_types, verification/canonical_json | mcp/, engine/, verification/ |
| cli/ | `src/cli/` | core/, verification/, engine/, gate/, infrastructure/, cli/, ui/ | — (top layer) |
| tools/ | `tools/` | shared_types/, core/, src/cli/shared/, verification/lean_repl_bridge, verification/router, verification/symbolic_test_synth, engine/profiler, gate/gate_types, gate/topology_spec, gate/framework/topology_types | gate/, engine/, verification/ |
| frontend/ | `src/frontend/` | core/, frontend/ | src/cli/, mcp/, gate/, verification/, engine/ |
| mcp/ | `src/mcp/` | core/, verification/, infrastructure/, mcp/, personas/ | src/cli/, gate/ |
| sieve/ | `src/sieve/` | core/, verification/, sieve/, infrastructure/ | src/cli/, gate/, engine/, mcp/ |
| personas/ | `src/personas/` | core/, personas/ | src/cli/, gate/, verification/, engine/, mcp/ |
| infrastructure/ | `src/infrastructure/` | core/, infrastructure/ | src/cli/, gate/, verification/, engine/, mcp/ |
| generated/ | `src/generated/` | core/, generated/, std/ | src/cli/, gate/, verification/, engine/, mcp/ |

**Key design decision**: `gate/` has a **narrow allowlist** rather than the full
`core/` — it may only import `core/types/`, `core/parsers/`, `core/solver/`,
`core/json/`, and `core/trusted/`. This keeps the gate layer decoupled from domain
logic.

### 3.3 DebtBudgets (4 metrics)

Debt reduction targets with weekly decay:

| Metric | Baseline | Weekly Reduction | Target Date |
|--------|----------|------------------|-------------|
| `import_lint_violations` | 36 | 5.0% | 2026-08-01 |
| `layer_violations` | 8 | 5.0% | 2026-08-01 |
| `effect_violations` | 80 | 5.0% | 2026-09-01 |
| `nimtry_violations` | 704 | 5.0% | 2026-12-01 |

**Total baseline**: 828 violations across 4 categories.
**Mechanism**: Each week, the allowed count drops by 5%. The `debt_blocker_gate`
fails CI when actual counts exceed the budget.

### 3.4 Legacy Baseline

`data/debt_reduction_baseline.json` tracks additional metrics from the earlier
debt reduction system:

```json
{
  "metrics": {
    "forwarding_stubs": 38,
    "isMainModule_in_core": 0,
    "nimtry_violation_count": 2293,
    "stale_generated_pbt_files": 0
  }
}
```

---

## 4. Dev vs CI Mode

The enforcement system operates in different modes depending on the environment:

| Mode | Flag | Behavior |
|------|------|----------|
| **Dev** | `-d:axiomDevMode` | Fast lint only, debt violations produce warnings (soft-fail) |
| **CI** | *(default)* | Full enforcement — all gates run, debt violations produce errors (hard block) |
| **Release** | `-d:release` | Full enforcement + debt hard block + additional release gates |
| **Strict** | `-d:axiomStrict` | Enables `enforceStructuralSafety` macro (adds ~1-2s build time) |

**Mode combinations**:

- **Local development**: `-d:axiomDevMode` — fast iteration, warnings only
- **Pre-commit / CI**: No flags — full enforcement, errors block merge
- **Release builds**: `-d:release -d:axiomStrict` — maximum enforcement

---

## 5. Data Flow

```
Source code (.nim files)
        │
        ▼
┌──────────────────────────────────────────┐
│  config.nims: switch("import",           │
│    "src/core/trusted/enforce_structural_safety") │
│  → injects macro into every module       │
└──────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────┐
│  Compile Time (-d:axiomStrict)           │
│  enforceStructuralSafety macro           │
│  ├─ Check 1: ref object proc fields      │
│  ├─ Check 2: func var parameters         │
│  ├─ Check 3: core/ import boundaries     │
│  └─ Check 4: exception hygiene           │
│  → error() blocks compilation            │
└──────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────┐
│  Gate Pipeline (CI)                      │
│  ├─ import_encapsulation_gate            │
│  │   reads gate_consts.nim hubMapping    │
│  ├─ dag_enforcement_gate                 │
│  │   checks import graph acyclicity      │
│  ├─ dependency_rules_gate                │
│  │   reads gate_consts.nim LayerRules    │
│  ├─ topology_policy_gate                 │
│  │   checks topology.lock drift          │
│  ├─ structural_safety_gate               │
│  │   wraps macro output into report      │
│  ├─ debt_blocker_gate                    │
│  │   reads gate_consts.nim DebtBudgets   │
│  └─ validate_effect_hints_gate           │
│      checks {.axiomEffect.} on procs     │
│                                          │
│  All violations → gate_diagnostic.nim    │
│  → formatted GateViolation objects       │
│  → CI pass/fail decision                 │
└──────────────────────────────────────────┘
        │
        ▼
┌──────────────────────────────────────────┐
│  Negative Tests (tests/architecture/)    │
│  ├─ Must-fail tests validate gates       │
│  ├─ Debt budget regression tests         │
│  └─ Snapshot isolation tests             │
└──────────────────────────────────────────┘
```

---

## 6. Adding a New Enforcement Rule

### 6.1 Adding a Layer Rule

1. Define the `LayerRule` in `src/core/trusted/layer_rules.nim` → `LayerRules` const array (SSOT)
2. Update `hubMapping` in `src/gate/gate_consts.nim` for any new path prefixes
3. The rule is automatically picked up by `dependency_rules_gate` at CI time
4. Update the layer table in this document (§3.2)

### 6.2 Adding a Debt Budget

1. Define the `DebtBudget` in `src/gate/gate_consts.nim` → `DebtBudgets` const array
2. The rule is automatically picked up by `debt_blocker_gate` at CI time
3. Update the debt table in this document (§3.3)

### 6.3 Adding a New Gate

1. Create the gate runner in `src/gate/runners/`
2. Register it in `src/gate/manifest.d/` (create a per-gate JSON file and add to `_index.json`)
3. Use `gate_diagnostic.nim` types for consistent violation reporting
4. Add negative tests in `tests/architecture/`

---

## 7. Remediation Links

| Violation Type | Documentation |
|----------------|---------------|
| Import Encapsulation | [docs/agents/rules_workflow.md](../agents/rules_workflow.md) |
| Layer Violation | [docs/agents/architecture.md](../agents/architecture.md) |
| Import Boundary (core/) | [docs/agents/constitution_details.md §0.6](../agents/constitution_details.md) |
| Effect Missing | [docs/spec/nim_effect_system_quirks.md](nim_effect_system_quirks.md) |
| Exception Hygiene | [docs/spec/nim_effect_system_quirks.md](nim_effect_system_quirks.md) |
| Debt Budget | [docs/DEBT_REGISTRY.md](../DEBT_REGISTRY.md) |
| DAG Cycle | [docs/agents/rules_workflow.md](../agents/rules_workflow.md) |
| Topology Drift | [docs/agents/architecture.md](../agents/architecture.md) |
| Ref Object proc fields | [docs/agents/core_rules.md](../agents/core_rules.md) |
| Language Ban | [docs/agents/architecture.md](../agents/architecture.md) |

---

## 8. Module Dependency Map

```
gate_consts.nim ──────────────────── Rule definitions (hubMapping, InternalPaths)
layer_rules.nim ──────────────────── LayerRule types & LayerRules SSOT
       │
       ├──► dependency_rules_gate.nim      (uses LayerRules from layer_rules.nim)
       ├──► debt_blocker_gate.nim          (uses DebtBudgets)
       └──► structural_safety_gate.nim     (reads macro output)

gate_diagnostic.nim ─────────────── Reporting types (SSoT)
       │
       ├──► All gate runners               (use GateViolation, formatViolation)
       └──► unified_gate_runner.nim        (aggregates reports)

layer_declaration.nim ────────────── Layer metadata
       │
       └──► layer_enforcement.nim          (validates imports per declared layer)

enforce_structural_safety.nim ────── Compile-time macro
       │
       ├──► config.nims                   (injects macro globally)
       └──► Every .nim module              (receives macro via import)
```

---

## 9. Design Principles

1. **Compile-time prevention over runtime detection**: Violations are caught by
   macros that produce `error()`, making them impossible to ship.
2. **Single Source of Truth**: All rule definitions live in `gate_consts.nim`.
   All reporting types live in `gate_diagnostic.nim`.
3. **Fail-soft in dev, hard block in CI**: Developers get fast feedback without
   being blocked; CI enforces the full policy.
4. **Debt is tracked, not ignored**: Baseline counts are set, budgets decay weekly,
   and the blocker gate prevents regression.
5. **Negative tests are required**: Every gate must have tests that verify it
   catches violations — a gate that doesn't fail on violations is worse than no gate.
6. **No hardcoded exceptions**: Rule definitions are data-driven (`const` arrays),
   not scattered across gate logic.

---

## 10. History

| Date | Version | Change |
|------|---------|--------|
| 2026-06-28 | v1 | Initial creation — Structural Enforcement Plan v3 |
