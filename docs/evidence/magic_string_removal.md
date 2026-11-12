# ADR: Removal of Magic String Dependencies

## 1. Context
In earlier versions of SMT query generators or special branching logic, "Magic String" methods that depend on target function names or file paths (using `std/strutils.contains`, etc.) were frequently used. These implicit dependencies reduced the transparency of core functions (`func`) and caused unexpected non-deterministic failures when source code structure changed.

## 2. Decision
- Completely remove magic string references for contradiction injection or special behavior control from SMT-LIB query builders and proof request (`AxiomProofRequest`) objects.
- Replace them with explicit `bool` flags (e.g., `AxiomProofRequest.injectContradiction`) so that all branching is determined solely by the object's structural state (Type-safe State).
- Within pure functions (`func`) and `.nosideeffect.` contracts inside `src/core`, use only clearly dependency-injected flags for branching instead of implicit string checks.

## 3. Consequences
- Since branching decisions in the proof pipeline are controlled by explicit fields of `AxiomProofRequest`, outputs can be 100% predicted from input values alone (Mathematical Determinism).
- Promotion of `func` based on the "Zero-Side-Effect" principle became easier, and structural cohesion was secured where internal logic is unaffected even when symbol names in external target repositories change.
- During debugging and test writing (BDD), all scenarios can be covered simply by explicitly setting specific state values.

## 4. Evidence Log (Related Commits)
- `7e5c77a6` refactor(core): remove magic string contradiction injection
- `6412af7c` refactor(core): add explicit contradiction injection to AxiomProofRequest