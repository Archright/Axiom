# ADR-0002: PEG Parser Migration

## Status
Accepted

## Context
Axiom needs a reliable, maintainable parser for its domain-specific configuration formats (config.nims variants, topology specs, manifest files). The original hand-written recursive descent parser was fragile — small input changes caused silent misparses with no diagnostic output. Debugging parse failures required instrumenting the source code.

## Decision
Migrate to a PEG (Parsing Expression Grammar) parser library. Define grammar rules declaratively in a separate file, then generate the parser at build time. Error messages report exact token positions and expected alternatives. The grammar file is version-controlled alongside the Nim source.

## Consequences
- Grammar definitions are human-readable and testable independently of the runtime.
- Parse errors include precise location information, reducing debugging time.
- Adding new syntax requires editing the grammar, not imperative parsing logic.
- Build-time code generation adds ~2 seconds to compilation but eliminates parser bugs.
