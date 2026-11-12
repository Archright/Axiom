# ADR: Throttled Self-Healing Pipeline

## 1. Context
The existing Axiom verification pipeline simply reported verification failure to users or agents when bugs were detected (SMT `sat` counterexample derivation, etc.). In this case, agents struggled to immediately find correct Invariant hints to resolve counterexamples within limited contexts, making them prone to infinite modification loops or meaningless invariant attempts.

## 2. Decision
- **Deterministic Dual Verification**: Introduce a dual verification pipeline combining SMT-based sat/unsat-core analysis and Lean 4 logical consistency verification through The Judge persona.
- **Smart Search & Generic Hint Extractor**: Instead of hardcoded values or magic strings, dynamically scan `// @axiom-hint` comments in source code or related documents (Context7) to synthesize context-semantic hints.
- **Throttled Limit**: To prevent infinite resource consumption and guarantee determinism in the autonomous recovery process, introduce `ax heal --limit <N>` command to strictly limit retry counts.
- **Semantic Control**: Synthesized hints are recorded in the proof state and reflected in ASI (Axiom Safety Index) score updates only after passing through The Judge logic.

## 3. Consequences
- Completed a "Self-Healing Loop" where AI can safely synthesize mathematical grounds and remediation hints based on SMT unsat-core without user intervention on failure.
- While maintaining `func`-level side effect control rules, file system I/O and hint recording were separated into explicit Executor tier, not violating architecture rules.
- Hardcoded dependencies were eliminated, enabling universal invariant verification for multiple open-source projects (e.g., `bitcoin`).

## 4. Evidence Log (Related Commits)
- `ce2d1c9b` refactor(core): implement Generic Hint Extractor and remove hardcoded values
- `be3987a2` feat(cli): implement throttled self-healing pipeline with Smart Search and The Judge
- `988a86f5` feat: implement throttled self-healing pipeline