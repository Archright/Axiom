# Declarative Effect Isolation — Quirks and Design Decisions

## Overview

The `{.axiomIoBoundary.}` pragma provides a file-level declaration that all procs
in the module may perform I/O. This short-circuits nimtry PURITY checks and
annotation_hygiene_gate scanning for the entire file.

## Motivation

Previously, each I/O-performing proc required individual annotation:
- `{.axiomEffect: IoEffect.}` on the proc signature
- `{.axiomIoHint: "reason".}` inside the proc body
- `import core/trusted/axiom_pragmas` in the file header

For files where ALL procs are I/O boundaries (CLI entry points, MCP handlers,
gate runners), this created annotation noise without adding signal.

## Design Decision: Comment-Based vs Compile-Time Pragma

**Chosen approach**: Text-based scan for `axiomIoBoundary` string.

**Why not a compile-time template?** The template exists in `axiom_pragmas.nim`:
```nim
template axiomIoBoundary*() =
  discard
```

But nimtry's PURITY query (`checkPurityNewCodeMustBeFunc` in `purity_queries.nim`)
uses `readFileSafe()` text scanning, not AST analysis. The text scan checks for
the string `"axiomIoBoundary"` in the file content. This means:

1. The comment `# axiomIoBoundary` is sufficient (no import needed)
2. The template invocation `axiomIoBoundary()` also works (import needed)
3. Both approaches are valid — the text scan doesn't distinguish

**Recommended usage**: Add `# axiomIoBoundary` as a comment after `{.push raises: [].}`.
This requires no import and is purely declarative.

## Quirk: Import Visibility Within `{.push raises: [].}`

**CRITICAL**: Moving `import core/trusted/axiom_pragmas` from inside the
`{.push raises: [].}` block to outside it BREAKS custom pragmas like
`{.axiomEffect: IoEffect.}` and `{.axiomGcsafe.}`.

These pragmas are defined as `{.pragma.}` templates in `axiom_pragmas.nim`.
Nim requires the pragma definition to be visible at the point of use.
When the import is outside the `{.push raises: [].}` block but the pragma
usage is inside, the compiler reports `invalid pragma: axiomEffect: IoEffect`.

**Rule**: NEVER move `import core/trusted/axiom_pragmas` outside the
`{.push raises: [].}` block. Use the comment-based `# axiomIoBoundary`
approach instead.

## Interaction with Existing Mechanisms

| Mechanism | Scope | axiomIoBoundary Interaction |
|-----------|-------|----------------------------|
| `isIoModuleOrHint()` in io_module_registry.nim | Path-based | Independent — both can coexist |
| `{.axiomEffect: IoEffect.}` | Per-proc | Still valid — axiomIoBoundary is file-level |
| `axiomIoHint()` | Per-proc | Still valid — provides human-readable reason |
| `effectHintModules` in io_module_registry.nim | const Table | Cannot add dynamically — axiomIoBoundary bypasses this |
| annotation_hygiene_gate.py | File scan | Skips files with axiomIoBoundary |
| nimtry PURITY-new-code-must-be-func | Text scan | Skips files with axiomIoBoundary |

## Gotcha: nimtry Binary Build

The nimtry binary is built from the forwarding stub `src/gate/nimtry.nim`, which
re-exports the unified architecture CLI in `src/gate/nimtry/nimtry_cli.nim`
(see the `bin/nimtry` target in `Makefile`). The former standalone
`nimtry_gate.nim` runner under `src/gate/runners/` was **removed** — do not
reference it.

Build command:
```bash
nim c -o:bin/nimtry src/gate/nimtry.nim
```

## Baseline Impact

Adding `# axiomIoBoundary` to files reduces the nimtry PURITY violation count.
After applying to all I/O boundary files: 1129 → 431 violations (62% reduction).

The baseline must be updated after changes:
```bash
# Rebuild nimtry
nim c -o:bin/nimtry src/gate/nimtry.nim
rm -f .nimcache/nimtry/*.json
# Run nimtry and update baseline
bin/nimtry --json > /tmp/nimtry_new.json
# Update data/nimtry_baseline.json manually
```
