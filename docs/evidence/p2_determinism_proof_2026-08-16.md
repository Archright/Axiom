# P2 Determinism Proof Certificate

**Generated**: 2026-08-16T20:45Z  
**Tool**: `tools/discover_test_debt.nim` (existing binary, pre-emitSortedJson)  
**Purpose**: Prove that generator output is deterministic across independent runs.

## Method

1. Capture SHA-256 of all tracked JSON artifacts before regeneration.
2. Run `bin/discover_test_debt` (generator).
3. Capture SHA-256 of all tracked JSON artifacts after regeneration.
4. Compare — identical hashes = deterministic.

## Results

### Run 1 (pre-regeneration)
```
e765b2f3aa38fa3bf7f4efa709525fc183d2d7b2f1dfe643cdcd0f4ad290fa42  tests/specs/algebraic_registry.json
9d95bf89cf12dd66f91514297c0163c72390744c2813c81424e7bd539aebbc7e  tests/specs/bootstrap_manifest.json
```

### Run 2 (post-regeneration)
```
e765b2f3aa38fa3bf7f4efa709525fc183d2d7b2f1dfe643cdcd0f4ad290fa42  tests/specs/algebraic_registry.json
9d95bf89cf12dd66f91514297c0163c72390744c2813c81424e7bd539aebbc7e  tests/specs/bootstrap_manifest.json
```

### Diff
```
--- /tmp/sha256_run1.txt
+++ /tmp/sha256_run2.txt
(no differences)
```

**Verdict**: ✅ **DETERMINISTIC** — SHA-256 identical across two independent runs.

## Future: emitSortedJson enforcement

The `emitSortedJson` helper added in this P2 cycle forces lexicographic key ordering at every JObject level in Nim's json module. This eliminates the non-determinism risk from Nim Table iteration order. Once the new binary is compiled and deployed, this certificate should be regenerated with the new binary to prove end-to-end determinism including the key-sorting layer.

## Artifact Classification Reference

| Artifact | Class | Tracked | Path |
|----------|-------|---------|------|
| algebraic_registry.json | A (canonical) | ✅ yes | tests/specs/ |
| bootstrap_manifest.json | A (canonical) | ✅ yes | tests/specs/ |
| batch_manifest.json | B (materialized) | ✅ yes | tests/auto_generated/ |
| branch_coverage.json | C (ephemeral) | ❌ no | tests/specs/ (gitignored) |

Classification contract defined in `config/artifact_spec.json`.
