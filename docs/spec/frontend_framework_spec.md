# Language Frontend Framework — Specification

> DEBT#188 — Last updated: 2026-06-05

## Purpose

The frontend framework provides a **language-agnostic abstraction** for parsing source code into
Axiom-IR and injecting verification guards back into the source. Adding a new language requires
implementing only two methods: `parseToIR` and `injectGuardFromIR`.

Per AGENTS.md §1.1: the framework follows the Layered Architecture where Presentation
(frontend) never imports Infrastructure — it operates purely on `AxiomIrNode` domain types.

## Module Map

| File | Responsibility |
|------|---------------|
| `frontend_interface.nim` | **Abstract base type** `LanguageFrontend` with virtual methods. Zero concrete implementations. |
| `nim/nim_frontend.nim` | Nim language frontend — delegates to `parseNimToIR` and `weaveGuards`. |
| `nim/weaver.nim` | **Source-code injector** — physically embeds Axiom-IR contracts into Nim source as `doAssert` statements and effect pragmas. Idempotent via `# AxiomGuard:<hash>` markers. |

## Key Types

| Type | Module | Description |
|------|--------|-------------|
| `LanguageFrontend` | `frontend_interface` | `{.acyclic.}` ref object base. Method dispatch only, no fields. |
| `AxiomIrNode` | `core/axiom_ir` | Language-neutral IR: function name, invariants (pre/post/loop), effect constraints, parameters |
| `InvariantScope` | `core/axiom_ir` | Enum: `invPre`, `invPost`, `invLoop` |
| `EffectKind` | `core/axiom_ir` | Enum: `effNoSideEffect`, `effPure`, `effIO`, `effNetwork`, `effFileSystem`, `effUnknown` |

## Entry Points (Virtual Methods)

| Method | Description | Default |
|--------|-------------|---------|
| `parseToIR(lf, sourceCode, modulePath) → AxiomIrNode` | Parse source into language-neutral IR | `discard` (abstract) |
| `injectGuardFromIR(lf, ir, guardKind, sourceCode) → string` | Generate verification guard block from IR | `defaultInjectGuard` (plain-text contract) |
| `languageName(lf) → string` | Return language identifier | `""` |
| `canHandle(lf, extension) → bool` | Check if frontend handles this file extension | `false` |

## Nim Frontend Implementation

**`NimFrontend`** overrides all four methods:
- `parseToIR` → delegates to `parseNimToIR` (Nim compiler parser-based AST parsing)
- `injectGuardFromIR` → if `sourceCode` is provided, uses `weaveGuards` for physical injection; otherwise falls back to `defaultInjectGuard`
- `languageName` → `"nim"`
- `canHandle` → matches `.nim` extension

## Weaver (Source Injection)

The weaver performs **idempotent source-level injection** of Axiom-IR contracts:

| Function | Description |
|----------|-------------|
| `weaveGuards(source, ir) → string` | Main entry: strip old guards → inject invariant guards → inject effect pragmas |
| `stripAllGuardBlocks(source) → string` | Remove all `AxiomGuard..EndAxiomGuard` blocks. Handles corrupted (missing end marker) blocks gracefully. |
| `injectInvariantGuards(source, ir) → string` | Insert `doAssert` statements at function body start for pre/post/loop invariants |
| `injectEffectPragmas(source, ir) → string` | Insert `{.noSideEffect.}` / `{.tags: [ReadIOEffect].}` pragmas into proc signatures |
| `buildGuardMarker(kind, payload) → string` | Generate `# AxiomGuard:<fnv1a_hash> (<kind>)` marker for idempotency |
| `findProcHeaderLine(source, name) → int` | Locate proc/func declaration line by name |
| `findProcBodyStartLine(source, headerLine) → int` | Hardened body-start detection: tracks parenthesis depth, skips strings/comments, matches `=` at depth 0 |

## Integration Points

- **`core/axiom_ir`** — `AxiomIrNode` definition, `toLeanContract()` serialization
- **`translator/universal_mapper`** — AST JSON → `UniversalTranslation` (parallel path)
- **`verification/universal_pipeline`** — Pipeline uses frontend to parse source before verification
- **`sieve/ast_inspector`** — Nim compiler AST query infrastructure for AST navigation
- **`core/parsers/compiler/parser`** — Nim compiler parser bindings for source analysis

## Key Contracts

1. **Effect boundary**: `frontend_interface.nim` methods are all `{.raises: [].}`. `LanguageFrontend` is `{.acyclic.}`.
2. **Idempotency**: Weaving is safe to re-run — `stripAllGuardBlocks` removes prior injections before re-applying.
3. **Deterministic hash**: FNV-1a 64-bit for guard markers — no external dependencies, no raises.
4. **Extension-agnostic**: `canHandle` method enables runtime language selection without switch statements.
5. **DIP compliance**: Pipeline interacts through abstract `LanguageFrontend` interface; concrete frontends are injected.

## Adding a New Language

1. Create `src/frontend/<lang>/<lang>_frontend.nim` inheriting from `LanguageFrontend`.
2. Implement `parseToIR` using a language-specific parser integration (compiler API or external parser).
3. Optionally implement `injectGuardFromIR` for source-level guard injection.
4. Register in the frontend factory (if applicable).
5. Add parser integration to `src/frontend/<lang>/`.

## Known Limitations

- **Nim-only concrete implementation**: Only Nim frontend exists. Rust, Go, C++ are not yet supported.
- **Weaver is Nim-specific**: Guard injection patterns (pragmas, doAssert) are Nim syntax. Other languages need their own injection logic.
- **No incremental parsing**: `parseToIR` re-parses the entire source on each invocation.
