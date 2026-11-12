# Identity Algebra Determinism Boundary (C8)

## Guarantee (C8)

Given the same inputs, Axiom produces identical deterministic artifacts:

```
same SemanticModel
  + same EncodingConfig
  + same CompilerSchemaVersion
    → same Canonical CHC bytes
      → same Canonical CHC fingerprint
```

This guarantee holds end-to-end through the identity algebra pipeline:
`semantic_identity` → `canonical_identity` → `evidence_identity`.

## Exclusion

**Same CHC → same Z3 certificate bytes is NOT guaranteed.**
Timeouts in the Z3 solver pool are non-deterministic; worst-case different
sat/unsat results can occur for identical CHC inputs. See
`docs/spec/z3_pool_determinism.md` for the full non-determinism analysis.

## Classification

Axiom is a **deterministic artifact compiler**, NOT a deterministic Z3
certificate generator. The determinism contract covers the identity algebra
pipeline (canonicalization + fingerprinting) only; Z3 solver interaction is
explicitly excluded.