# 2026-03 Changelog
> **Note (2026-05-25):** CONTEXT.md was merged into AGENTS.md §0-§1. References to "CONTEXT.md" below refer to the pre-merge structure. See AGENTS.md for current SSOT.

## 2026-03-23
- Core officially adopted BMC-based symbolic solver and general k-induction framework.
- CLI promoted solver execution path to standard entry point.
- Verification unified Nim→Lean metadata bridge, Lean LSP-based dynamic proof search, Proof Vault warm-start, refinement feedback/apply-refinement, certificate gate, and dependency invalidation into a single pipeline.

## 2026-03-24
- UAP was first introduced with resilient quality gate, and unified Z3 result parser and verify path.
- Verification established self-evolution loop, ghost update PoC, induction proof chain, Lean 4 operational semantics/termination formalization, and axiom→theorem promotion path.

## 2026-03-25
- Verification strengthened theorem promotion replay pipeline and strict specification/memory invariant policy, and integrated relational predicate and unsat-core parsing into Axiom v1 integrity refinement loop.
- UAP reflected integrity hardening.
- CLI/operational path reflected architecture gate rule separation, GitHub Actions workflow renaming, and Lean LSP termination/certificate fingerprint consistency reinforcement.

## 2026-03-26
- Core introduced Bottom-up Sorter, Vault Manager, Axiom Orchestration Loop to establish stale axiom blocking and vault-based promotion path.
- Verification/operational path completed orchestration-centric refactoring, ASI 1.0000, and encoding consistency correction.

## 2026-03-27
- Core added dependency-aware parallel execution, barrier synchronization, resource-aware timeout, and transitive cache profiling.
- Verification introduced tiered timeout, self-healing diagnostics engine, topology-aware verification diagnostics, and trusted base binary proof auditor.

## 2026-03-28
- CLI reflected TTY-only Pure Nim progress bar for `ax topo`/`ax prove`, alias normalization, shortcut UX recovery, and certificate suite restoration.
- CLI flow reorganized to scan-centric path replacing `ax topo` with `ax scan`.

## 2026-03-29
- CLI stabilized `ax report` default proof state loading and shortcut output routing.
- UAP/verification reflected `SemanticEqualityPayload` Enum datatype SMT path connection, semantic proof workflow introduction, proof detailed state persistence, and stale dependency reproving handling reinforcement.

## 2026-03-30
- Verification stabilized `lean` re-certification verification, and fixed `proofDependencies`·`minimalProofPath` in semantic proof artifacts to enforce leaving only MemorySafety lemma-based minimal replay path.
- UAP extended to serialize SMT `sat` counter-example report and engine-limited `unverifiable` verdict into `soundnessNote`·`verificationVerdictReport`.
- Operational gate strengthens to block commits without additional evidence in `Context7 evidence: /org/project - query summary` format in `CONTEXT.md` when `src/`, `semantic_proofs/`, Lean/Nim toolchain files are changed.
- Context7 evidence must remain directly in the commit's staged diff, and agents must explicitly record Context7 library ID when exploring open source documentation.