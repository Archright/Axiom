# Generated Lean Specifications

This directory contains auto-generated Lean 4 specification files produced by
the Nim→Lean IR bridge (`src/verification/nim_to_lean_bridge.nim`).

## Overview

Each `.lean` file in this directory is a complete Lean 4 module generated from
an Axiom Core IR function definition (`IRFuncDef`). The generation pipeline:

1. **IR Input** — An `IRFuncDef` is produced by the Nim AST extractor.
2. **IR→Lean Conversion** — `ir_to_lean.nim` converts the IR to Lean 4 source.
3. **File Emission** — `nim_to_lean_bridge.nim` writes the source to this directory.
4. **Compilation** — The Lean 4 compiler verifies the generated file.

## Files

- `Generated.lean` — Library root module. Do not edit. Required by Lake to discover submodules.
- `*.lean` — Auto-generated Lean 4 modules. Do not edit manually.

## Notes

- Files are regenerated on each `ax prove` run; manual edits will be overwritten.
- Each module imports `Axiom.IR.Types` for shared type definitions.
- Recursive functions include automatic termination strategy selection:
  - Structural descent for list recursion.
  - Numeric descent (`termination_by n` + `decreasing_by omega`) for integer recursion.
  - Fallback to `partial def` with `termination_by sorry` when strategy is unclear.
