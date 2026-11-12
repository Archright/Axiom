🛡️ GUARDIAN.md: The Sentinel of Integrity

This document is the absolute guideline for safeguarding the system's Integrity, Performance, and **Moat**. All developers (human and AI) must thoroughly understand these principles before writing code, and not a single line of code violating these principles may enter the main branch.

Enforcement: Local quality gates are automatically enforced via prek pre-commit hooks.

---

## § -1. Four-Dimension Mandate (Preamble Override)

**Every code modification** — without exception — MUST satisfy all four dimensions
before it may enter the main branch. This is not a guideline. This is the
constitutional override that governs every other rule in this document.

| Dimension | Question | Violation Indicator |
|-----------|----------|---------------------|
| **Ideal** | Can the violation be made *impossible* at compile time rather than merely detected at commit time? | Post-hoc runtime checks, string/regex matching instead of type-system enforcement |
| **Elegant** | Does the solution use language-native tools (compiler AST, type system, effect system) rather than external heuristics? | Grep, shell pipelines, ad-hoc text parsing for properties the compiler already knows |
| **Fundamental** | Are there zero hardcoded exceptions, whitelists, or rule gaps in the enforcement logic? | Special-cased paths, "except for" comments, configuration that silently bypasses enforcement |
| **Deterministic** | Does identical input (source tree, Nim version, policy file) produce identical output every time, regardless of environment? | File-system ordering dependencies, timestamp-based cache invalidation, non-reproducible hashes |

**Mandatory**: Before proposing any code change, the agent MUST state (at minimum in
the commit message or plan document) how the change satisfies each dimension.
A change that degrades any dimension without a documented GUARDIAN.md amendment
is an integrity violation and must be reverted.

**Prohibition**: "It works" is never sufficient justification. A working change that
degrades a dimension is technical debt, not progress.

---

## § 0. No-Downgrade Policy (Integrity Downgrade Prohibition)

Principle: Prohibits changing existing `func` to `proc` or removing `{.noSideEffect.}` pragma for any reason.

Mandatory: Computation and logic functions must maintain Purity regardless of layer (UI, CLI, Core).

Solution: When IO (terminal width, time, file reading, etc.) is needed, must use Dependency Injection pattern to receive values externally as arguments, preserving `func` integrity.

Prohibition: Lowering design grade (purity) to resolve compilation errors is considered 'integrity abandonment for convenience' and work must stop immediately for architecture redesign.

Example:
```nim
# Prohibited: func → proc change (integrity downgrade)
proc compute(x: int): int =  # Wrong approach
  let width = terminalWidth()  # Introduces side effect
  ...

# Correct: Maintain purity via dependency injection
func compute(x: int; terminalWidth: int): int =  # Correct approach
  # Receives terminalWidth externally to maintain pure function
  ...
```

---

## § 1. 🚫 No Raw Data Entry

Principle: Unvalidated primitive types like string, int, float cannot enter internal logic (Trusted Zone).

Mandatory: All external input must pass through Gateway and be promoted to VerifiedType.

Prohibition: Receiving string as argument and checking if empty inside the function is considered a design failure.

---

## § 2. 🚫 No Defensive Unit Testing

Principle: Prohibits writing tedious unit tests to check "is this value valid?".

Mandatory: Pour that energy into Nim's type system and Dr.Nim contract (`ensures`/`requires`) design. Increasing test code is evidence of poor architecture.

Allowed: Only test Gateway promotion logic and business specification (BDD) compliance.

---

## § 3. 🚫 Forbidden Side-Effects

Principle: All functions aim for **Purity**.

Mandatory: Completely block unexpressed IO, Global State changes, and exception raising through Effect System.

Prohibition: Core logic without `{.raises: [].}` guarantee is not approved. Side effects must be pushed to the outermost Application Layer.

---

## § 4. 🚫 No Runtime Panic

Principle: Programs must not die 'unexpectedly' during execution.

Mandatory: Prohibits patching errors with try-catch. Errors must be handled explicitly as data through `Option[T]` or `Result[T, E]` types.

Mandatory: Resource depletion/IO failure scenarios (network outage, disk full, permission denied, etc.) must be sealed as failure type (E), with Retry/Fallback/termination policies fixed as code contracts.

Goal: Successful compilation should mathematically prove that runtime abnormal termination will not occur.

---

## § 5. 🚫 Complexity Moat Maintenance

Principle: Advanced techniques introduced for performance and integrity are not simplified on grounds of being "hard to understand". Code size increase for structural clarity is allowed.

Mandatory: Nim's macros, metaprogramming, and custom kernel optimizations are our core assets. Reject Python-style thinking that sacrifices performance and security for readability.

Moat: Code that's hard to analyze is security; performance that cannot be imitated is competitiveness.

---

## § 6. 🔍 Macro Expansion Audit

Content: When AI writes Nim metaprogramming (macros), compilation may succeed but the actual generated code (AST) may break differently from intent.

Mandatory: When modifying complex macros, must verify `nim c --expandMacro:<function_name>` results and revalidate that intended logic was generated.

Mandatory: Macros for `Result` handling or type inference assistance are allowed, but must prove at compile time that expansion results don't break `func`/`{.noSideEffect.}` contracts. Macros generating effectful calls, hidden `proc` downgrades, or template-style bypass paths are immediately rejected.

---

## § 7. 🧬 Macro-driven Promotion (VerifiedType Creation Automation)

Content: Manually accumulating distinct type/gateway logic for VerifiedType promotion destroys consistency and stability.

Mandatory: Promotion logic from primitive types to domain types uses standard macros (e.g., `makeGateway`) to maintain consistency. Manual repetitive coding is prohibited.

---

## § 8. 📸 External Contract Snapshot (API Version Snapshot)

Content: Defensive line for responding to external service API changes.

Mandatory: Keep external service API response samples in `tests/snapshots` and compare against current types/decoders during gateway testing.

---

## § 9. 🧯 Unsafe/FFI Quarantine

Content: Nim's FFI area (`importc`, `ptr` manipulation, etc.) is a lawless zone not protected by the type system, where mistakes immediately lead to segmentation faults.

Mandatory: Prohibits direct `importc`/`ptr` manipulation in business logic (Trusted Zone). FFI must be isolated in dedicated Wrapper modules, exposing only safe interfaces based on VerifiedType/Result internally.

---

## § 10. ⚙️ Core No-Raises Contract (Core {.raises: [].} Enforcement)

Content: Merely declaring "don't throw exceptions" is insufficient; the compiler must mechanically seal them.

Mandatory: Core domain logic (gateway promotion, VerifiedType creation/validation, contract verification) requires `{.raises: [].}` enforcement. If exception possibility remains, build failure is correct; failures are promoted to Option/Result and handled as data.

---

## § 11. 🧨 Core NoSideEffect Default & Deterministic Destruction

Principle: Core modules must "by default" be pure zones without exceptions and side effects.

Mandatory: All core modules declare `{.push raises: [].}` and `{.push noSideEffect.}` as module-scope defaults.

Mandatory: All function declarations expressing pure computation use only `func`. `proc` is not allowed as a default choice in core/verification paths because it can bypass purity proof.

Mandatory: `template` usage as a **computation substitute** is prohibited because per-call-site code expansion weakens contract tracking and effect boundary analysis. Computation logic must be sealed in `func` and pass compiler effect checks directly.

Exception: Result-error-propagation templates (e.g., `??`) that strictly expand to the inline `if r.isErr(): return err(r.error); r.get()` pattern are permitted. Such templates introduce no new side effects, no hidden control flow beyond what the equivalent handwritten code already contains, and pass Dr.Nim effect checks identically.

Mandatory: Minimize Heap allocation and prefer structures guaranteeing ORC-based deterministic destruction (value-type centered, predictable destruction timing through ownership/lifetime).

Prohibition: Designs using `ref object`/unbounded growth `seq`/implicit heap ownership in core modules that destabilize destruction timing are not approved. Unavoidable heap ownership/side effects/exceptions must be pushed to the outermost Application Layer, flowing only Result/Option and VerifiedType to the core.

Prohibition: Designs bypassing effect checks with `proc`, `template` (excluding permitted Result-propagation templates per the exception above), `let x = proc (...) =`, `let x = template (...) =` in pure function positions are absolutely not approved.

Mandatory (Mass Conversion Audit): Batch `proc → func` conversion — whether by script, IDE refactoring, or any automated tooling — is prohibited without per-function side-effect verification. `func` implicitly carries `{.noSideEffect.}`, meaning any function performing physical IO (`readFile`, `writeFile`, `fileExists`, `dirExists`, `walkDir`, `moveFile`), network calls, time acquisition (`now`, `utc`, `getTime`), mutable global state mutation, or process execution (`execCmdEx`) **cannot** be declared `func`; the compiler will reject it. Before any mass conversion, the operator must audit each candidate and retain `proc` for all physically impure functions. Reverting a physically impure function to `proc` is not a purity downgrade; it is preserving a truthful contract. The only permitted `func → proc` reversal is for Nim compiler false positives resolvable via the constructor pattern per §15.

---

## § 12. 📊 NoNonAlignedOutput (Unaligned Output Prohibition)

Principle: All CLI table format output must include auto-alignment logic considering terminal width.

Mandatory:
- Apply Fixed Width column alignment for table format data output.
- Use `strutils.alignLeft` or `alignRight` to uniformly adjust whitespace.
- Terminal width must not be obtained internally but injected as arguments to maintain `func` integrity.
- Use Unicode box drawing characters (┌, ─, │ etc.) to ensure visual consistency.

Mandatory: Section headers must display item count in parentheses (e.g., "CRITICAL (3)", "WARNING (2)", "VERIFIED (5)").

Mandatory: Auxiliary information (state file paths, usage instructions, etc.) must be distinguished with Dim color (ANSI escape `\x1b[2m`) to clarify visual hierarchy.

Prohibition: Crude table borders using only ASCII characters (+, -, |) are prohibited. Unicode box drawing characters must be used.

Prohibition: Directly calling `terminalWidth()` inside rendering functions to cause side effects is prohibited. Pure functions must receive `termWidth: int` parameter externally.

Example:
```nim
# Prohibited: Direct terminalWidth call inside func
func renderTuiReport(report: AxProofReport): seq[string] =
  let width = terminalWidth()  # Side effect!
  ...

# Correct: termWidth parameter injection
func renderTuiReport(report: AxProofReport; termWidth: int): seq[string] =
  let config = createLayoutConfig(termWidth)  # Maintain pure function
  ...
```

---

## § 13. 🚫 No Ad-Hoc / Statistical / Non-Deterministic Architecture

Principle: Architecture based on ad-hoc inference, statistical inference, probabilistic judgment, or non-deterministic algorithms is absolutely prohibited.

Mandatory: Only deterministic contracts guaranteeing identical output for identical input are permitted. All core logic, verification paths, and gateway promotion must be mathematically reproducible.

Exception: External AI model calls (LLM API, etc.) are the sole exception to this rule.

Mandatory: AI model calls must be treated as quarantine boundaries equivalent to FFI, and their outputs must pass through explicit Gateway verification and promotion procedures before entering the Trusted Zone.

Prohibition: Using non-deterministic or probabilistic logic—such as randomized algorithms, statistical thresholds, ad-hoc tuning without reproducible contracts, or any architecture where identical inputs may yield different outputs—in core verification, gateway promotion, or business logic is strictly forbidden.

---

## § 14. 🏛️ Architecture Red Lines

These red lines extend §0–13 into architectural policy. Violations are enforced by the ASI hard gate and the architecture gate.

### SSOT Red Lines
- **RL-14.1**: Direct assignment `cert.status = ...` or `cert.reason = ...` outside `certificate_manager.nim` is an integrity violation. All certificate mutations MUST flow through `certificate_manager.setCertificateStatus()` or `certificate_manager.markCertificateInvalid()`.
- **RL-14.2**: Duplicate type definitions across `reporter.nim`, `session_parser.nim`, and `universal_pipeline_core.nim` are prohibited. `domain_types.nim` is the SSOT.
- **RL-14.3**: `logs/global_symbol_graph.json` is the SSOT for graph hash. Any divergence between `rebuild_assets` output and `verify-certificates` reading triggers `global-graph-stale` demotion.
- **RL-14.12**: `data/universe_merkle.lock` is a deterministic snapshot of the integrity universe and is **Git-ignored / untracked** (a derived artifact, not source). The **sole authority to write it to disk** is a canonical run: `ax vkd sync` or `ax prove --update-lock`. Normal `ax prove` / any `--limit` run computes and validates the Merkle lock in-memory but **never persists it**. The gate runner `proof_universe_lock_gate` writes its bounded-prove progress checkpoint to a **separate** path (`data/universe_merkle_gate_checkpoint.json`), never to the canonical lock. `commitUniverseIntegrityAndLock` enforces a runtime caller whitelist (`AuthorizedLockCaller = "ax_prove_core"`); any invocation from an unauthorized caller triggers immediate process termination with `[CONSTITUTIONAL VIOLATION]`.

### SoC Red Lines
- **RL-14.4**: `src/core/` importing `src/verification/`, `src/cli/`, `src/mcp/`, `src/ui/`, or `src/gate/` is an immediate revert offense. Layer direction is Presentation → Infrastructure → Domain, with Presentation → Gate allowed only for CLI gate commands.
- **RL-14.5**: `analyzer.nim` must not contain gate logic. `gate_rules.nim` must not contain report rendering. `reporter.nim` must not contain AST extraction.

### OCP Red Lines
- **RL-14.6**: Adding a new verification gate by patching `analyzer.nim` or `gate_rules.nim` loops is prohibited. Use `gate_registry.registerGate()`.
- **RL-14.7**: Hardcoding `if engine == "z3": ... elif engine == "lean": ...` in core logic is prohibited. Use injected `ProverInterface`.

### DRY Red Lines
- **RL-14.8**: Duplicating the prove/heal orchestration loop in both `commands/heal.nim` and `commands/prove.nim` is prohibited. Extract shared logic to `src/core/`.
- **RL-14.9**: Two functions from different modules sharing identical compact-whitespace fingerprints must be extracted to a shared module within one sprint.

### DIP Red Lines
- **RL-14.10**: `src/core/` modules must never call `z3ExecPersistent` or `runLeanCompiler` directly. They receive a `ProverInterface` closure or `SolverBridgeResult`.

### SRP Red Lines
- **RL-14.11**: A function referencing resources from ≥3 distinct domain prefixes triggers `srp-low-cohesion`. The fix is module splitting, not gate suppression.

### nimtry Red Lines
- **RL-14.13**: Canonical computation (e.g., `verified / total`) outside the owner module (`metrics.nim`) is an SSOT violation. Detected by `nimtry ssot-taint` query.
- **RL-14.14**: Interface implementation without explicit `{.implements: InterfaceName.}` pragma is not verified for LSP contract compliance. Detected by `nimtry solid-lsp` query.
- **RL-14.15**: Module LCOM > 0.7 or TCC < 0.3 triggers SRP warning. Detected by `nimtry solid-srp` query.

### Penalty Table
| Violation | Penalty | Enforcement |
|-----------|---------|-------------|
| SSOT cross-module write | `0.20` per resource | ASI blocking |
| SoC layer inversion | Immediate revert | Build failure |
| OCP direct patch | Procedure gate rejection | prek block |
| DRY duplicate fingerprint | Blocking | Immediate pre-commit failure |
| DIP concrete dependency | Blocking | Immediate pre-commit failure |
| SRP high cohesion | Blocking | Immediate pre-commit failure on first occurrence |

---

## § 15. 🚫 Persistent Pool Disabling Anti-Pattern

`shouldUsePersistentZ3` is not a tunable optimization flag; it is a **hard-wired orchestration invariant**. Disabling the pool (e.g., hardcoding `return false` or bypassing `z3ExecPersistent`) **breaks deterministic parallelism** because `runParallelDepth` relies on reusable Z3 workers.

If a POSIX `hasData` deadlock or similar I/O bug is observed, the **only permitted fix** is to replace the broken polling primitive with a correct non-blocking equivalent, not to disable the pool. Any commit that alters `shouldUsePersistentZ3`'s return value or bypasses `z3ExecPersistent` without a BDD scenario in `tests/features/z3_timeout_guard.feature` is treated as an architectural integrity violation.

---

## § 16. 🚫 Pool Disabling Prohibition (Extended)

The persistent Z3 pool reads solver stdout through non-blocking `readData` chunks guarded by `hasData` polling instead of blocking `readLine`, eliminating readline deadlock when a process dies mid-output. The persistent pool is **architecturally mandatory** for parallel throughput; it must never be disabled as a workaround for I/O bugs. The correct response to a `hasData` deadlock is to fix the polling primitive, not to fall back to per-process spawning.

---

🏛️ Guardian's Judgment Criteria

Can the bug be caught at compile time? -> If so, don't write test code; fix the type.

Does this logic cause side effects? -> If so, express it in Effect System and isolate it.

Has the data passed through the Gateway? -> If not, don't use types with Verified prefix.

"We don't protect code; we protect the 'laws of physics' we declare."

---

## § 15b. 🧬 Constructor Over Mutation (Avoid noSideEffect False Positives)

Principle: When Nim's `func` checker falsely flags `result.ok = false` / `result.err = value` as side effects, use the **constructor expression** pattern instead. This preserves `func` purity without downgrading to `proc`.

Mandatory: In `func` bodies, construct `Result` error values via constructor syntax:
```nim
# ❌ Prohibited: Field mutation (triggers noSideEffect false positive)
func mapErr[T, E](r: Result[T, E]; mapper: proc(e: E): E {.raises: [], noSideEffect.}): Result[T, E] =
  if r.isErr():
    result.ok = false      # Nim flags this as side effect
    result.err = mapper(r.error)

# ✅ Correct: Constructor expression (pure, no false positive)
func mapErr*[T, E](r: Result[T, E]; mapper: proc(e: E): E {.raises: [], noSideEffect.}): Result[T, E] =
  if r.isErr():
    Result[T, E](ok: false, err: mapper(r.error))  # Pure constructor
  else:
    r
```

Rationale: `Result[T,E](ok: false, err: value)` is a pure value constructor — it allocates nothing, mutates nothing external, and returns a new value. Nim's effect system correctly classifies this as `noSideEffect`. Field mutation (`result.ok = false`) on a variant object discriminator is conservatively flagged despite being semantically equivalent.

Mandatory: When `func` compilation fails with "can have side effects" on `result` field writes, reach for the constructor pattern first. Never downgrade `func` to `proc` to silence the error.

Prohibition: `func → proc` conversion to work around `noSideEffect` false positives is not approved when the constructor pattern can resolve it.

---
## § 17. 🧠 False Positive Recording Mandate

Principle: Agent-driven investigations (audits, tech-debt scans, architecture checks) inevitably produce false positives — items that appear to be violations but are confirmed as correct upon deeper investigation. Without a deterministic recording mechanism, every new agent session re-investigates the same false positives, wasting resources and eroding trust in automated analysis.

Mandatory: Every false positive identified during any investigation MUST be recorded in agent memory (`tech-debt/false-positives`) before the session ends. The record MUST include:
- **File** and line reference
- **What was flagged** (the initial finding)
- **Investigation result** (why it's not a real issue)
- **Verdict** (NO ACTION NEEDED / DOCUMENTATION GAP / ACCEPTABLE DESIGN)
- **Date** of confirmation

Format: File-system SSOT at `docs/false-positives.md` (version-controlled, the definitive record). Agents load this file via `ReadFile` at session start per AGENTS.md §2.1. Symmetric file `docs/known-limitations.md` records items blocked by genuine constraints. Template:

```markdown
## FP-NNN: <descriptive title>

- **File**: `<path>:<line>`
- **What was flagged**: <initial agent finding>
- **Investigation result**: <definitive conclusion after deep analysis>
- **Verdict**: <one of: NO ACTION NEEDED | DOCUMENTATION GAP | ACCEPTABLE DESIGN>
- **Date**: YYYY-MM-DD
```

Rationale: Agent sessions are stateless. Without persisted false-positive records, each new agent receives the same raw findings and repeats the same investigation — a deterministic waste. The false-positive registry is the SSOT that breaks this cycle. It is the SSOT defense against investigation entropy.

Prohibition: Recommending or implementing code changes based on a previously-recorded false positive without first reading `tech-debt/false-positives` memory is a procedural violation. Agents MUST load false-positive records before acting on audit findings.

Enforcement: The procedure gate (`scripts/gates/procedure_gate.nim`) may be extended in a future wave to verify that new audit-derived commits did not re-investigate known false positives. Until then, enforcement is by agent discipline and code review.

## §18 Layer Architecture (v0.4.0)

### Purpose
Define the four architectural layers of Axiom, their import permissions, and the enforcement mechanism. This codifies the SoC principle from AGENTS.md §1.3 into a mechanically-enforceable structure.

### Layer Definitions

| Layer | Directories | Role | Max Side Effects |
|-------|-------------|------|------------------|
| **Domain** | `src/core/` | Pure calculation, types, proof logic, BMC, k-induction | Zero — `{.noSideEffect.}`, `{.raises: [].}` |
| **Infrastructure** | `src/verification/`, `src/engine/`, `src/frontend/`, `src/infrastructure/`, `src/personas/` | File I/O, external process management, Lean LSP, Z3 gateway, AST extraction, validation, git ops | OS-level side effects permitted (filesystem, process, network) |
| **Presentation** | `src/cli/`, `src/mcp/`, `src/ui/`, `src/api/`, `src/api.nim` | Human/machine interface, CLI output, JSON serialization, TUI, MCP protocol, public API facade | I/O permitted (stdout, stderr, stdin, HTTP) |
| **Gate** | `src/gate/` | Pre-commit enforcement, static analysis, architecture violation detection | Read-only filesystem access only — no mutation |

### Import Adjacency Matrix

The matrix below defines ALLOWED import directions. Any import NOT explicitly listed as ALLOWED is DENIED. The matrix is encoded in `src/core/trusted/layer_rules.nim` (consumed by `src/core/trusted/layer_enforcement.nim`) and enforced by `make check-imports` (`tools/check_imports_ast.nim`, AST-based forbidden-path scan) and by the `layer-enforcement-gate` (`src/gate/runners/layer_enforcement_gate.nim` → `bin/layer_enforcement_gate --strict`) in `.githooks/pre-commit`. `src/allowed_imports.lock` is deprecated and non-normative (see `docs/spec/allowed_imports_lock_status.md`).

```
Domain → Domain          : ALLOWED  (intra-layer cohesion)
Domain → Infrastructure  : DENIED   (Domain purity — no side effects)
Domain → Presentation    : DENIED   (Domain purity — no UI coupling)
Infrastructure → Domain  : ALLOWED  (infrastructure consumes domain types)
Infrastructure → Infrastructure : ALLOWED (intra-layer utility)
Infrastructure → Presentation    : DENIED  (infrastructure unaware of UI)
Presentation → Infrastructure    : ALLOWED (CLI calls verification)
Presentation → Domain            : ALLOWED (CLI reads domain types)
Presentation → Presentation      : ALLOWED (intra-layer refactoring)
Presentation → Gate              : ALLOWED (CLI gate command invokes gate framework)
Gate → Domain            : ALLOWED  (gate analyzes all layers)
Gate → Infrastructure    : ALLOWED
Gate → Presentation      : ALLOWED
Gate → Gate              : ALLOWED  (intra-layer gate orchestration)
```

### Enforcement

- **Pre-commit**: `make check-imports` (`tools/check_imports_ast.nim`) plus `bin/layer_enforcement_gate --strict` (from `.githooks/pre-commit`) validate all `import` statements against this matrix.
- **Role Registry**: `src/gate/architecture_policy.lock` owns module-role policy entries (`[module_roles]` section) for cohesive public API catalogs and import facades. Unregistered modules still use the default SRP/import-count limits. (`src/allowed_imports.lock` is deprecated and non-normative — see `docs/spec/allowed_imports_lock_status.md`.)
- **Policy Validator**: the source `src/gate/runners/policy_validator.nim` ensures format compliance (deterministic format, deduplication, sorting) for `src/verification/.physically_impure_modules` and the external dependency allowlist `.config/nimtry/allowed_imports.lock` — a different file from the deprecated `src/allowed_imports.lock`. It must be built before use (e.g., `nim c -o:bin/policy_validator src/gate/runners/policy_validator.nim`); the `bin/policy_validator` binary is not built by a Makefile target.
- **Violation Consequence**: Commit blocked. No bypass except `AXIOM_EMERGENCY_NO_VERIFY=1`.

### Grandfathered Exceptions (v0.4.1)

There are no active Domain → Infrastructure grandfathered imports. Cohesive-module and import-facade exceptions are explicit policy entries in `src/gate/architecture_policy.lock`; they do not permit forbidden layer direction.
| `core/logic/pipeline_fingerprint_engine.nim` | `translator/universal_mapper`, `verification/pipeline_core_types` | Same as above | v0.5.0 |
| `core/contract_extractor.nim` | `verification/ast_extractor` | AST extraction utility | v0.5.0: move AST types to Domain |
| `core/integrity_ledger.nim` | `verification/vault_index` | Vault index types | v0.5.0: move vault types to Domain |

### Grandfathered Exceptions (RL-14.4 core→verification/gate) — Provisional (→ v0.5.0 transition)

RL-14.4 remains an absolute revert offense for NEW imports. The closed set below is the ONLY grandfathered core→verification / core→gate crossing set, per architect decision `docs/history/debt/rl14-4-crossing-decision-2026-10-11.md`. Each exception is scoped per **(source file, import target)** pair — a whitelisted file MUST NOT gain new verification|gate imports (DEBT#495). Adding to this table requires the full Amendment Authority procedure; the set may only shrink before the exit date. This table is a documented transition, NOT an enforcement bypass.

| Source | Normalized import target | Rationale | Expires |
|---|---|---|---|
| `core/application/persona_context_init.nim` | `verification/composition/leanstral_registry`, `scan_registry`, `bmc_registry`, `cegar_registry`, `healing_registry` | ADR-014 (Accepted) — composition root | v0.5.0 |
| `core/boundary/verification_interface.nim` | `verification/abstract_provider_types`, `verification/pipeline_state_types`, `verification/solver/fixedpoint_types`, `verification/unified_trajectory_types` | type-only facade (DEBT#483) | 2026-12-12 |
| `core/orchestration/pipeline_dispatch.nim` | `verification/pipeline_effect` | orchestration wiring | 2026-12-12 |
| `core/orchestration/pipeline_types.nim` | `verification/pipeline_effect` | shared effect types | 2026-12-12 |
| `core/judge/lean_replay.nim` | `verification/lean_lsp_compiler`, `verification/obligation/lean_kernel_boundary` | — | 2026-12-12 |
| `core/proof/proof_vacuity_gate.nim` | `verification/solver/z3_pool` | + RL-14.10 separate disposition required | 2026-12-12 |
| `core/symbol_graph/lean_symbol_integration.nim` | `verification/lean_lsp_protocol` | — | 2026-12-12 |
| `core/trusted/compile_time_manifest.nim` | `gate/manifest_schema_validator` | — | 2026-12-12 |
| `core/trusted/ir_to_lean.nim` | `verification/obligation/obligation_ir` | — | 2026-12-12 |
| `core/trusted/ir_to_smt.nim` | `verification/obligation/obligation_ir` | unused-import candidate — deletion review | next review |
| `core/trusted/layer_enforcement.nim` | `gate/gate_consts` | rewiring review | next review |
| `core/trusted/private/canonical_chc_compiler.nim` | `verification/obligation/obligation_ir` | — | 2026-12-12 |
| `core/trusted/private/ir_loop_to_horn.nim` | `verification/obligation/obligation_ir` | — | 2026-12-12 |
| `core/verifier/lean_repl_bridge.nim` | `verification/lean_repl_bridge` | — | 2026-12-12 |
| `core/gate/gate_to_smt.nim` | `verification/solver/z3_pool` | + RL-14.10 separate disposition required | 2026-12-12 |

15 source files, 23 pairs in total. Review date: 2026-12-12 (synchronized with `src/gate/architecture_policy.lock` Expires).

Enforcement: the machine-readable allowlist lives in `src/gate/architecture_policy.lock` (per-import-target). `src/core/trusted/layer_rules.nim` remains the layer-direction SSOT and consumes the allowlist as a parameter — it MUST NOT read `src/gate/**` directly (`docs/agents/architecture.md:88`: "Domain never imports Infrastructure, Presentation, or Gate").

### Amendment Authority

This layer architecture may be amended only via GUARDIAN.md amendment procedure: written proposal → architecture gate validation → pre-commit approval → merge to `main` and `core` simultaneously. No agent may unilaterally alter layer boundaries.

---

## §19 Incremental Principle (Gate Execution Context Separation)

**Mandate**: Quality gates MUST operate under an explicitly declared execution mode. The caller determines scope; the callee MUST NOT expand it.

| Mode | Enum Value | Scope | Caller |
|------|-----------|-------|--------|
| Incremental | `grmIncremental` | Changed files ONLY | pre-commit hook |
| Exhaustive | `grmExhaustive` | Full `src/` + `tests/gateway/` | pre-push, CI, `ax gate run --full-tree` |

**Red Line**: A gate implementation that receives a non-empty `files` argument and then appends dynamically discovered files (e.g., `collectGatewayTests`) is an **immediate revert offense**. This violates:
- **SRP**: the gate expands its own scope beyond the caller's intent
- **Determinism**: identical `files` input no longer produces identical execution scope
- **Fundamental**: hardcoded exception ("Always check test entrypoints")

**Enforcement**:
1. `GateRunMode` enum is the ONLY valid execution context discriminator.
2. `pre-commit` stage maps to `grmIncremental` unconditionally.
3. `pre-push` / `gsManual` stage maps to `grmExhaustive`.
4. Gate binaries (`bin/nim_check_gate`, `bin/gateway_test_gate`) receive mode as CLI argument; there is no default.
