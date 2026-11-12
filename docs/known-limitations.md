# Known Limitations

This file records known limitations in Axiom's verification system.
Agents load this file at session start per AGENTS.md §2.1.

## Format

Each entry must include:
- **ID**: Unique identifier (LIM-YYYY-MM-DD-NNN)
- **Date**: When the limitation was discovered
- **Component**: Which component is affected
- **Description**: What the limitation is
- **Workaround**: Known workaround (if any)
- **Status**: active / resolved / by-design

## Entries

- **LIM-2026-06-17-001** *(resolved 2026-06-24 → purged 2026-XX-XX)*: tree-sitter Nim grammar dependency removed. Replaced by Nim compiler parser (in-process). Vendored C sources (`vendor/tree-sitter-nim/`), `tree_sitter_path.nim`, `tree_sitter_bridge.nim`, and all `core/parsers/tree_sitter/*` modules deleted. AST parsing now uses `compiler/parser` directly — zero external dependencies, zero FFI, zero shared libraries.

- **LIM-2026-07-06-001** *(2026-07-06)*: `classifyTypeLevel` layer 2 is conservative — only passes functions where `preConditions.len > 0` AND passes all 5 filters (non-recursive, no complex nodes, etc.). Functions with complex IR patterns (irLoop, irCall to non-builtins) are routed to Z3 BMC fallback even if they have contracts. **Component**: `src/sieve/trivial_lean_router.nim`, `src/core/trusted/ir_to_lean.nim` §2. **Workaround**: None — this is by design to avoid Lean kernel rejection of ill-typed refined definitions. **Status**: active.

- **LIM-2026-07-06-002** *(2026-07-06)*: `inlineSmallFunctions` only inlines functions with body ≤ 10 IR nodes. Larger functions remain as UF (uninterpreted function) declarations. Single-level only — no nested inlining of inlined functions. **Component**: `src/core/trusted/ir_inline_pass.nim`. **Workaround**: Functions with body > 10 nodes are verified via Z3 BMC with UF abstraction. **Status**: active.

- **LIM-2026-07-06-003** *(2026-07-06)*: `hasWhitelistedDecreasePattern` recognizes only 3 structural patterns (tail, drop 1, init) and 1 numeric pattern (n − 1). Other legitimate decrease patterns (e.g., `n / 2`, `length − 2`, custom list operations) require explicit Lean termination proof. **Component**: `src/core/trusted/ir_to_lean.nim`. **Workaround**: Functions with non-standard decrease patterns fall back to `partial def` with `termination_by sorry`. **Status**: active.

- **LIM-2026-07-06-004** *(2026-07-06)*: Contract synthesis generates guards for `boDiv`/`boRem` (division-by-zero) and `irCall("[]")`/`irCall("substr")` (index-out-of-bounds) only. Other potential division/index patterns (e.g., custom accessor functions, `nth` calls, slice operations) are not covered. **Component**: `src/core/trusted/axiom_ir.nim` (contract synthesis). **Workaround**: Manually add pre-conditions for unguarded operations. **Status**: active.

---

- **LIM-2026-07-06-001**:
  - **Date**: 2026-07-06
  - **Component**: `src/sieve/trivial_lean_router.nim` — `classifyTypeLevel` layer 2
  - **Description**: `classifyTypeLevel` layer 2 is conservative — only routes functions to the Lean path when `preConditions.len > 0` AND the function passes all 5 filters (non-recursive, no complex IR nodes, no external calls, no loops, no non-linear patterns). Functions with complex IR patterns (`irLoop`, `irCall` to non-builtins) are routed to Z3 BMC fallback even if they have contracts. This is by design to prevent unsound Lean proofs, but it reduces Lean coverage on contract-bearing functions that use loops or external calls.
  - **Defense-in-depth update (2026-07-08)**: `hasUnsupportedType` now properly rejects `irtFloat` types in addition to the previous filter criteria. This adds compile-time defense-in-depth for float functions that cannot be encoded in the Lean path, ensuring they are routed to Z3 BMC (which has Z3 Reals fallback) rather than reaching the Lean kernel with unsupported types.
  - **Workaround**: None — these functions are handled correctly by the Z3 BMC fallback path. If Lean coverage is needed, refactor the function to eliminate loops/external calls, or extend the filter criteria after validating soundness.
  - **Status**: by-design

- **LIM-2026-07-06-002**:
  - **Date**: 2026-07-06
  - **Component**: `src/core/trusted/ir_inline_pass.nim` — `inlineSmallFunctions`
  - **Description**: `inlineSmallFunctions` previously only inlined functions with body ≤ 10 IR nodes. Larger functions remained as UF (uninterpreted function) declarations. Inlining was single-level only — no nested inlining of already-inlined functions. This limited Lean's ability to reason about function composition chains.
  - **Extension (2026-07-23)**: `inlineSmallFunctions` now uses `adaptiveInlineBudget` with depth ≤ 3 and cumulative nodes ≤ 50. Functions whose call tree exceeds depth 3 or 50 total nodes are automatically handled via abstraction contract fallback — unsound inlining is never performed.
  - **Workaround**: For functions that would benefit from inlining but exceed the threshold, decompose them into smaller helper functions (each ≤ 50 cumulative nodes). Alternatively, provide explicit Lean lemmas for the UF-declared functions.
  - **Status**: extended

- **LIM-2026-07-06-003**:
  - **Date**: 2026-07-06
  - **Component**: `src/core/trusted/private/ir_to_lean_termination.nim` — `hasSmtDecreasingMeasure`
  - **Description**: `hasWhitelistedDecreasePattern` originally recognized only 3 structural patterns (`tail`, `drop 1`, `init`) and 1 numeric pattern (`n - 1`) as valid termination decreases. Other legitimate decrease patterns (e.g., `n / 2`, `length - 2`, `list.drop k`) were not recognized and required explicit Lean proof annotations.
  - **Extension (2026-07-23)**: Added `hasSmtDecreasingMeasure` — a conservative SMT-level extension that accepts patterns provably decreasing at the SMT level (v_next < v_curr AND v ≥ 0). Simple structural pattern matching is no longer the sole acceptance criterion.
  - **Workaround**: Functions with decrease patterns that cannot be SMT-proven (e.g., non-linear arithmetic) fall back to `partial def` with `termination_by sorry`. Add explicit `{.lean: "termination_by ...".}` annotations where SMT-level proof is insufficient.
  - **Status**: extended

- **LIM-2026-07-06-004**:
  - **Date**: 2026-07-06
  - **Component**: `src/core/trusted/contract_synthesis.nim` — contract synthesis
  - **Description**: Contract synthesis previously generated division-by-zero and bounds guards for `boDiv`/`boRem` binary operations and `irCall("[]")`/`irCall("substr")` index operations only. Other potential division/index patterns (e.g., custom accessor functions, `nth` calls, `mapGet`, or user-defined indexing operators) were not covered and did not receive automatic guards.
  - **Extension (2026-07-23)**: Added `verifyInductiveInvariant` — a 1-step BMC self-verification check (I AND T IMPLIES I') that blocks false-positive contract synthesis. Contracts that do not satisfy the inductive step are rejected at synthesis time.
  - **Workaround**: For custom accessor patterns still unguarded, add manual preconditions: `require idx < len(myArray)` before calling `myArray.nth(idx)`. Extend the guard synthesizer to cover additional patterns as they are identified in real-world codebases.
  - **Status**: extended

- **LIM-2026-07-23-001** *(resolved 2026-07-23)*: IR canonicalization — Alpha renaming and commutative operand sorting ensure deterministic hash generation. Soundness guard: SMT-LIB2 generation uses original (non-canonical) IR. **Component**: `src/core/trusted/axiom_ir.nim`. **Status**: resolved.

- **LIM-2026-07-08-001**:
  - **Date**: 2026-07-08
  - **Component**: `src/core/trusted/ast_to_ir.nim` — `convertType`
  - **Description**: IR type erasure has been fixed — `convertType` no longer silently collapses unsupported types to `irtBitVec64`. Previously, `else: irTypeBitVec64()` was used as a catch-all fallback, silently converting `string`, `float`, `JsonNode`, and all custom types to `irtBitVec64`. This caused `isBmcSkippable` guards to never trigger (dead code), Z3 BMC to produce semantically meaningless formulas (everything was BV64), and 213 IR functions to be `certRed` with `z3-unknown`. Now `convertType` uses exhaustive matching with `error()` for unsupported types, emitting `AXIOM_IR_TYPE_UNSUPPORTED` compile errors.
  - **Workaround**: None needed — the fix is backward-compatible. Functions with previously-erased types will now produce explicit compile errors instead of silently incorrect BMC results.
  - **Status**: resolved
