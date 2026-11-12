# Effect Coverage Policy

**Created**: 2026-06-13
**Authority**: AGENTS.md §0.6 (Static First Enforcement)
**Enforcement**: `tests/gateway/effect_isolation_feature_test.nim`

## Purpose

Verifies that BoundaryExtractor correctly classifies functions by their I/O behavior:
- **bcComplete**: Pure functions with no I/O — fully verifiable
- **bcPartialHavoc**: Functions with I/O (writeFile, execCmd, etc.) — partial verification with `external_io_isolated` assumption
- **bcIncompleteIO**: External I/O beyond detection — skip Z3 entirely
- **bcTrivialDiscard**: Only trivial assertions — no semantic value

## Test Strategy

### Unit Tests (Gateway)
- `tests/gateway/effect_isolation_feature_test.nim`: Direct `extractBoundaries` calls with const source strings
- No CLI execution required — deterministic, fast

### Property-Based Tests (Future)
- `tests/generated_pbt/boundary_extractor_pbt.nim`: Random source patterns → classification consistency
- Uses `pbt_gate.nim` infrastructure

## BoundaryExtractor API

```nim
proc extractBoundaries*(nodeId, fileContext: string): BoundaryExtractionResult {.raises: [].}
```

- `nodeId`: Function identifier (e.g., `"module::functionName"`)
- `fileContext`: Source code string to analyze (NOT a file path)
- Returns: `BoundaryExtractionResult` with `completeness`, `smtParts`, `leanParts`

## References
- `src/core/boundary/boundary_extractor_part1.nim`: Main implementation
- `src/core/boundary/boundary_extraction_types.nim`: Type definitions
- `tests/features/effect_isolation.feature`: BDD specification
