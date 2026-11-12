# Undocumented Architectural Decision Records

> 9 previously undocumented decisions discovered during D-003 audit (2026-06-05).

---

## D-003-1: True k-Induction Engine Replacing 1-Induction

**Date**: 2026-03-23

**Context**: Original BMC engine used simple 1-step induction (base + step for k=1), which could not verify properties requiring multi-step reasoning (e.g., loop invariants that hold only after N iterations). CEGAR counterexamples sometimes required deeper induction to prove safety.

**Decision**: Implement full k-induction with k-step base case and k-step step case encoding (Sheeran et al. 2000, Algorithm 4 + Eén & Sörensson 2004). Base case proves invariant holds for states 0..k; step case assumes invariant for k consecutive states and proves it at the next. Both must be UNSAT for inductive proof.

**Consequences**: Stronger verification — properties unreachable by 1-induction can now be proven. Higher solver cost per attempt (k SMT variables instead of 2). Integrated into universal_pipeline as CEGAR fallback: CEGAR counterexample → k-induction → BMC witness.

**Source files**: `src/core/solver/induction.nim`, `docs/spec/bmc_core.md`, `src/verification/universal_pipeline.nim`

---

## D-003-2: Meta-Verification Layer for Proof Pipeline

**Date**: 2026-06-05

**Context**: The 4-layer proof pipeline (SWAT/BMC → Detective/CEGAR → Scribe/Legistral → Judge/Lean) lacked self-audit mechanisms. Three critical risks were identified: (1) LLM-generated Lean tactics could diverge silently, (2) proof budget was static regardless of code complexity, (3) refactoring patterns had no formal safety guarantees.

**Decision**: Implement a Meta-Verification Layer with three components: (1) `tactic_backtrack.nim` — Goal-Context Snapshot Protocol with disk-backed LRU snapshots and global reset triggers, (2) `pattern_guard.nim` — AST-level precondition validation for 6 certified refactoring patterns, (3) `certified_patterns/` — CompCert-style Lean 4 proofs for all 6 patterns. Adaptive gas allocation via Complexity Entropy replaces static budgets.

**Consequences**: LLM tactic divergence is detected and rolled back. Refactoring patterns are formally verified in Lean before application. Proof budget scales with structural complexity. 6 certified patterns serve as reusable, proven building blocks.

**Source files**: `src/core/pattern_guard.nim`, `src/verification/lean_lsp_proof_search.nim`, `src/core/proof_budget.nim`, `certified_patterns/*.lean`, `src/personas/legislator_feedback.nim`

---

## D-003-3: Subjective Logic (SL) Replacing Dempster-Shafer Theory (DST) in Sieve

**Date**: 2026-06-05

**Context**: Pre-Sieve evidence synthesis originally used Dempster-Shafer Theory (DST) for combining rule opinions. DST's normalization rule (Dempster's rule) produces counterintuitive results when evidence strongly conflicts — high-conflict evidence can amplify rather than dampen. DST also has exponential complexity for N>2 frames.

**Decision**: Replace DST with Jøsang's Subjective Logic (SL). Each rule produces a `BinomialOpinion` (b, d, u, a) where b+d+u=1. Same-proposition rules fuse via Cumulative Fusion (eq. 4.96); future multi-frame evidence uses Binomial Product (AND) / Comultiplication (OR). ε-padding with relative-ratio preservation prevents dogmatic Case II.

**Consequences**: O(1) fusion per rule (vs DST's exponential). Uncertainty-aware — the `u` mass explicitly captures ignorance. Probability projection E = b + a·u provides a single decision score. Conflict detection via safe-vs-danger opinion pairs replaces DST's normalization artifacts.

**Source files**: `src/sieve/subjective_logic.nim`, `docs/spec/subjective_logic_spec.md`, `src/sieve/sieve_engine.nim`

---

## D-003-4: Pre-Sieve Declarative Pipeline

**Date**: 2026-06-04

**Context**: The proof pipeline (Universal Acceptance Pipeline) executed expensive verification (Z3, Lean) on every node regardless of obvious structural issues. No early-exit mechanism existed for clearly problematic code (e.g., unbounded recursion, non-linear operations with loops).

**Decision**: Implement a Pre-Sieve declarative pipeline as a gate BEFORE UAP execution. Three pure rules (topology analysis, AST analysis, unsat-core correlation) each produce a `BinomialOpinion`. Opinions are fused via Subjective Logic `fuseAll()`. If E ≥ 0.50, the node is blocked; 0.30–0.50 triggers warning. Conflict detection identifies safe-vs-danger disagreements between rules. `SieveContext` is constructed at the I/O boundary (AST parsed once), keeping rules pure.

**Consequences**: Clearly problematic nodes are rejected in microseconds (vs seconds for Z3). Deterministic — same code always produces the same sieve verdict. Integrated into `batch_uap_orchestrator.nim` as a pre-execution interceptor. New enum `orchestrationPreSievedUnverifiable` tracks sieve-blocked nodes.

**Source files**: `src/sieve/sieve_engine.nim`, `src/sieve/sieve_types.nim`, `src/sieve/sieve_rules.nim`, `src/sieve/sieve_bridge.nim`, `src/verification/batch_uap_orchestrator.nim`

---

## D-003-5: Total-Verifier (Data-Schema, Doc-Code Sync, PBT)

**Date**: 2026-06-04

**Context**: Three verification strategies were missing: (1) verified axiom catalog was a 505-line Nim source file with hardcoded entries — fragile and untestable, (2) no mechanism to enforce that source code constraints match documentation, (3) no fuzz testing for core parsing/verification logic.

**Decision**: Implement three strategies: (1) **Data-Schema Validation** — externalize catalog to `data/axiom_catalog.json` (31 entries), validate at compile time via `axiom_catalog_validator.nim` macro (93% code reduction), (2) **Doc-Code Sync** — `@axiom-constraint` annotations bind source conditions to documentation references, validated at compile time by `axiom_contract.nim`, (3) **PBT** — AFL-based fuzz testing for parse safety, hash determinism, and JSON robustness invariants.

**Consequences**: Catalog changes are now JSON edits (no recompilation). Constraint violations are compile-time errors. Adversarial inputs are caught before deployment. Total code reduction: ~470 lines removed from source, replaced by data + compile-time validation.

**Source files**: `src/core/axiom_contract.nim`, `src/core/axiom_catalog_validator.nim`, `data/axiom_catalog.json`, `docs/spec/pbt_policy.md`, `docs/spec/axiom_constraint_spec.md`, `tests/fuzz/fuzz_gate.nim`

---

## D-003-6: axiom_pragmas Compile-Time Enforcement

**Date**: 2026-05-29

**Context**: Architecture rules (no `parseInt`, no weak hashes, `{.acyclic.}` on ref objects) were enforced by post-hoc gate analysis, which caught violations late in the pipeline. Developers could compile and run code with violations, only to be blocked at pre-commit.

**Decision**: Create `src/core/axiom_pragmas.nim` with compile-time macros that enforce architecture rules at compilation. `axiomSafeParse` blocks raw `parseInt`/`parseFloat`, `axiomStrongHash` blocks MD5/SHA1, `axiomAcyclic` warns on ref objects missing `{.acyclic.}`. Unified entry point `axiomEnforceAll()` called by `nimtryCheck()`.

**Consequences**: Violations are caught at `nim c` time, not at gate time. Zero runtime overhead — all enforcement is compile-time macro expansion. Integrates with nimtry's compile-time plugin system. Error messages include fix instructions and AGENTS.md references.

**Source files**: `src/core/axiom_pragmas.nim`, `src/gate/nimtry/plugin/nimtry_plugin.nim`

---

## D-003-7: OrchestrationContext + Orchestrator CEGAR DIP

**Date**: 2026-05-03

**Context**: The orchestrator directly imported CEGAR engine internals, creating a tight coupling between Domain (orchestrator) and Infrastructure (CEGAR). This violated AGENTS.md §1.2 (Domain never imports Infrastructure) and prevented testing the orchestrator with mock CEGAR callbacks.

**Decision**: Introduce `OrchestrationContext` — a DIP injection container holding callbacks (`CegarCallback`, `EncodeSmtlib2Callback`, `ProofLinkageCallback`, `OrchestrationProgressSink`) and configuration (`maxWorkers`, `maxWallClockMs`). Infrastructure passes concrete callbacks at invocation time. Domain defines only the callback signatures via `protocols.nim` concepts (`CegarCallback`, `EncodeSmtlib2Callback`). Validation: `isValid()` rejects incomplete contexts (e.g., `cegarEngine` set but `encodeSmtlib2` nil).

**Consequences**: Orchestrator no longer imports CEGAR/Infrastructure modules directly. Clean Domain→Infrastructure dependency inversion. Testable — inject mock callbacks for unit tests. `defaultOrchestrationContext()` provides safe defaults (CEGAR disabled). Module split: `orchestrator_types` (types), `orchestrator_topology` (dispatch), `orchestrator_vault` (vault), `orchestrator.nim` (execution).

**Source files**: `src/core/orchestrator_types.nim`, `src/core/protocols.nim`, `src/core/orchestrator.nim`, `src/api/verification_loop.nim`

---

## D-003-8: core/gate_evaluators.nim — Breaking gate_registry↔translation_validator

**Date**: 2026-06-05

**Context**: Gate rule functions (`applySemanticIntegrityGate`, etc.) were split between `gate/gate_rules.nim` and `verification/translation_validator.nim`, creating a circular dependency: `gate_registry` → `translation_validator` → `gate_registry`. This prevented clean SoC and made incremental compilation impossible for the gate layer.

**Decision**: Extract all pure gate rule functions into `src/core/gate_evaluators.nim` in the Domain layer. These functions accept domain types only (`FunctionCertificate`, `TranslationValidationResult`) and return `GateDirectiveBundle`. Infrastructure functions referenced via callback types (`ProofLinkageCallback`) — DIP pattern. Domain never imports Infrastructure.

**Consequences**: Circular dependency eliminated. Gate evaluators are pure functions (no I/O, no side effects), fully testable in isolation. `gate_registry` imports `gate_evaluators`; `translation_validator` imports `gate_evaluators` — no cycle. Clear layer boundary: Domain (evaluators) ↔ Infrastructure (validators).

**Source files**: `src/core/gate_evaluators.nim`, `src/core/domain_types.nim`

---

## D-003-9: SieveContext SSOT + Z3 Equivalence Gate

**Date**: 2026-06-05

**Context**: Pre-Sieve rules received partial context (source code + topology), forcing redundant parsing. AST analysis was duplicated across rules. No mechanism existed to verify that AI-synthesized code was semantically equivalent to the original Nim logic.

**Decision**: (1) Expand `SieveContext` to 7 fields as the single source of truth: `sourceCode`, `nodeId`, `functionName`, `modulePath`, `topology`, `unsatCoreVars`, `astCache` (+ `complexityScore`). AST is parsed once at construction time (`buildSieveContext`), cached as `Option[XmlNode]`. (2) Implement `ast_inspector.nim` — single-pass XmlNode DFS classifying loops, recursion, non-linear ops, quantifiers, nested conditionals. (3) Add Z3 structural equivalence gate in `equivalence_checker.nim`: AST→SMT conversion (`extractArithmeticConstraints`), equivalence query builder, Z3 process integration with rollback. (4) `sieve_bridge.nim` provides `toPipelineRequest()` for pipeline integration.

**Consequences**: All sieve rules operate on the same cached context — no redundant parsing. AST inspection is O(n) single-pass. Z3 equivalence gate detects semantic hallucinations (proven-but-wrong) at the sieve stage before expensive Lean verification. `SieveContext` construction is the I/O boundary; all downstream operations remain pure.

**Source files**: `src/sieve/sieve_engine.nim`, `src/sieve/sieve_types.nim`, `src/sieve/ast_inspector.nim`, `src/sieve/sieve_bridge.nim`, `src/core/solver/equivalence_checker.nim`
