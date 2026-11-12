# Hermetic Enforcement Roadmap

**Created**: 2026-06-20
**Status**: Phase 1 Complete (gorge("grep") eliminated)
**Policy**: AGENTS.md §0.5b Quirk Documentation Mandate

## Problem Statement

Nim's `gorge()` executes external processes at compile time. This creates:
1. **Non-determinism**: External tools may not be installed, or have different versions
2. **Platform dependency**: `grep`, `find`, `stat` behave differently on Linux/macOS/Windows
3. **Supply chain risk**: External tool output is not validated by the Nim compiler
4. **Hermeticity violation**: Build depends on external state beyond the compiler

## Current Status

| Area | Status | Notes |
|------|--------|-------|
| config.nims pending guard | ✅ Hermetic | `parseJson(readFile(...))` replaces `gorge("grep")` |
| config.nims manifest hash | ⚠️ Partial | `secureHashFile` for content, `stat -c %Y` for freshness (Linux-only) |
| config.nims import boundary | ⚠️ Known | `gorge("grep -rn 'import " & pattern & "'")` — text parser in config.nims |
| axiom_pragmas.nim sentinel | ⚠️ Known | `gorge("cat " & sentinelPath)` — reads sentinel file content |
| gate_memo.nim kernel version | ⚠️ Known | `gorge("uname -r")` — OS version for cache key |

## Roadmap

### Phase 1: High-Value Elimination (COMPLETE)
- [x] Pending guard → `parseJson(readFile(...))`
- [x] `import_scanner.nim` — Nim-native import parser (func only)
- [x] `feature_manifest_generator.nim` — `computeSourceHash()` with SHA-256
- [x] `pending_feature_guard.nim` — simplified sentinel

### Phase 2: Manifest Staleness (Planned Q3 2026)
Replace `stat -c %Y` with Nim-native `getFileInfo(path).lastWriteTime`:
```nim
import std/os
let mtime = getFileInfo("data/feature_manifest.json").lastWriteTime.toUnix()
```
Eliminates Linux-specific `stat` call.

### Phase 3: Import Boundary Scanner (Planned Q3 2026)
Replace `gorge("grep -rn 'import " & pattern & "'")` in config.nims with:
```nim
when not defined(AXIOM_SKIP_IMPORT_SCAN):
  for dir in sourceDirs:
    for entry in walkDirRec(dir):
      if entry.endsWith(".nim"):
        let content = readFile(entry)
        for forbidden in forbiddenPatterns:
          if hasForbiddenImport(content, @[forbidden]):
            {.error: "Forbidden import detected: " & forbidden.}
```
**Blocker**: Compile-time `walkDirRec` performance (may need caching).

### Phase 4: Sentinel File Reading (Planned Q3 2026)
Replace `gorge("cat " & sentinelPath)` in axiom_pragmas.nim with `staticRead`:
```nim
const sentinelContent = staticRead(projectRoot / "data" / "axiom_sentinel.txt")
```
**Note**: `staticRead` requires the file to exist at compile time. If the sentinel is generated dynamically, keep `gorge` with a `test -f` guard.

### Phase 5: OS Version Detection (Planned Q4 2026)
Replace `gorge("uname -r")` with compile-time host detection:
```nim
const hostOS = when defined(linux): "linux"
               elif defined(macosx): "darwin"
               elif defined(windows): "windows"
               else: "unknown"
```
For kernel version specifically, this is less critical — it's used for cache key generation only.

## Enforcement

### nimtry hermetic_guard
- Location: `tools/nimtry/hermetic_guard.nim`
- Scans: `config.nims` + `src/` directories
- Patterns: `gorge("grep")`, `gorge("find")`, `gorge("stat")`, `gorge("wc")`, `gorge("cut")`, `gorge("awk")`, `gorge("sed")`, `gorge("sort")`
- Run: `nim c -r tools/nimtry/hermetic_guard.nim`

### CI Integration (Planned)
```yaml
# .github/workflows/hermetic-check.yml
- name: Hermetic Enforcement
  run: nim c -r tools/nimtry/hermetic_guard.nim
```

## Exceptions

The following `gorge()` usages are **intentionally kept**:
1. `gorge("test -f ...")` — Bootstrap existence check (no alternative in NimScript)
~~2. `gorge("echo $AXIOM_PARSING_IMPORTS")`~~ — **Eliminated (WS3)**. Replaced by `-d:AxiomParsingImports` compile-time define and `defined()` check in config.nims.
