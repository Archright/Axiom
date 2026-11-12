# Debt Registry GC Policy

## Overview

Debt registry garbage collection removes entries whose tracked source target no
longer exists in the repository. The registry remains the single source of truth
for debt metadata, while `tools/debt_gc.nim` verifies that each concrete file and
symbol reference still points to live source.

## What orphaned entries are

An orphaned debt registry entry is a registry row whose tracked source target is
missing:

- the referenced file path does not exist; or
- the referenced symbol does not exist in the referenced file.

Entries that do not declare a concrete file or symbol are kept. This preserves
legacy or issue-level debt records that describe repository state without pointing
to a single source symbol.

## How GC works

`tools/debt_gc.nim` loads `data/debt_registry.json` and scans every entry. It
accepts the current `files` field used by the registry, plus `file` for older
single-file entries. Entries with `files` omitted but a `lineRange` are also
scanned. For symbol tracking, it accepts `symbol`, `symbols`, and the legacy
`declName` field.

File references may be plain paths or line-range references such as
`src/core/foo.nim:10-20`; GC checks the path and ignores the line suffix.

For each concrete file/symbol pair, the tool performs two checks:

1. `fileExists(path)` confirms the file path exists in the current workspace.
2. The tool reads the file and checks that the symbol appears as an identifier
   boundary, so substring matches do not count as valid references.

If a file or symbol is missing, the entry is reported as orphaned.

### Dry-run mode

```sh
nim c -r tools/debt_gc.nim --dry-run
```

Dry-run mode is a check. It prints orphaned entries and exits with status `1`
when any orphaned entries are found. CI uses this mode so stale debt entries fail
the build and remind developers to clean them up.

### Wrapper

`bin/debt_gc_check` runs the same dry-run check by default:

```sh
bin/debt_gc_check
```

Pass `--remove-orphaned` to the wrapper when you want it to remove orphaned
entries instead of only checking.

### Removal mode

```sh
nim c -r tools/debt_gc.nim --remove-orphaned
```

Removal mode writes a new `data/debt_registry.json` with orphaned entries removed.
It also refreshes `generatedAt`.

## Manual usage

Run GC manually when:

- a source file or symbol is deleted during a refactor;
- a debt entry was created against a removed module;
- a false-positive entry should be retired;
- CI reports orphaned debt registry entries.

Recommended workflow:

```sh
nim c -r tools/debt_gc.nim --dry-run
nim c -r tools/debt_gc.nim --remove-orphaned
git diff -- data/debt_registry.json
```

The dry-run output is the audit trail for deciding whether to remove entries.
