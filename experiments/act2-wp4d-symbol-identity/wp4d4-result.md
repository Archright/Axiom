# WP4-d-4 Result: getBitsBE Frontier Admission Re-Run

**Date:** 2026-08-28
**Experiment ID:** act2-wp4d-symbol-identity
**Subject:** nim-stew@c75502c (immutable)
**Axiom revision:** 089251924 (HEAD, with WP4-d-1/2/3 changes)
**Binary:** `./bin/ax` (already-built)

---

## Question

Does `stew/bitops2.nim::getBitsBE` now enter the verification frontier (stage A4/planning) after the WP4-d-1/2 changes, or is it still blocked by the V3 duplicate func+template nodeId self-dependency?

---

## Current Frontier Status for getBitsBE

### WP4-c (baseline, before WP4-d):
```
[INFO] frontier_selection: --target=stew/bitops2.nim::getBitsBE not found in frontier — using full frontier
```
getBitsBE was **excluded** from the verified frontier. `allDependenciesVerified` returned false for the template entry because the template's self-referencing dependency (same nodeId as func) was not in the verified set.

### WP4-d (after WP4-d-1/2/3):
```
[INFO] axiom_engine: --target filter: 1 node(s) match 'stew/bitops2.nim::getBitsBE'
[INFO] axiom_engine: frontier eligibility gate: excluded 504 non-proof-candidate candidate(s); eligible=1
```
**No `not found in frontier` line appears.** getBitsBE IS in the frontier now. It proceeds to the IR pipeline:
```
[INFO] ir_pipeline_runner: [classify] getBitsBE → vtStructural (complex body operations)
[WARN] ir_pipeline_runner: [TheaterGuard] getBitsBE — obligation generated but adapter produced empty SMT script
[INFO] loop_driver: IR pipeline skip: getBitsBE status=psSkip provenance=not_verifiable:illFormed
```

---

## Which Stage It Now Reaches (A1–A8)

| Stage | Status | Evidence |
|-------|--------|----------|
| A1: Topology analysis | ✅ Reached | `topology: 86 files, 931 candidates` |
| A2: Frontier selection | ✅ Reached | `--target filter: 1 node(s) match`; no `not found in frontier` |
| A3: IR extraction/classification | ✅ Reached | `getBitsBE → vtStructural (complex body operations)` |
| A4: Planning (SMT solving) | ❌ Skipped | `psSkip provenance=not_verifiable:illFormed` — SMT adapter produced empty script |
| A5–A8: Proof stages | ❌ Not reached | Skipped at A4 |

**getBitsBE enters the verification frontier (A2) and reaches A3 (IR classification), but does NOT reach A4/planning.** It is skipped as `illFormed` because the SMT adapter cannot handle the type (`type not BMC-representable or loop bound unresolved`).

---

## Whether WP4-d-1/2 Changes Removed the False Self-Dependency

### WP4-d-1 (definitionFingerprint): Does NOT fix the V3 blocker

- Added `definitionFingerprint: string` field to `TopologySymbol`, `SorterNode`, `CachedTopologySymbol`
- Fingerprint = `sha256Hex(modulePath || "||" || functionName || "||" || signatureText)`
- **`nodeId` is unchanged** — still `modulePath::functionName` for both func and template
- `buildNodeIndex` in `verified_frontier.nim:23-25` still maps shared nodeId to the last entry (template)
- The `definitionFingerprint` is an additive metadata field; it is NOT used in frontier admission logic
- **This change alone does not fix the duplicate func+template nodeId collision**

### WP4-d-2 (resolveCallTarget → ResolutionResult): IS the V3 blocker fix

**This is the causal fix.** The old `resolveCallTarget` returned `int` (-1 or index). When the template's body referenced `getBitsBE`, it resolved to the func entry (index 180) because `resolveCallTarget` picks the first same-module candidate. Since `180 != 183` (template's own index), the self-reference check `resolvedIdx != idx` passed, and the dependency `symbols[180].nodeId` = `"stew/bitops2.nim::getBitsBE"` was added to the template's `dependencyIds`.

The new `resolveCallTarget` returns `ResolutionResult` with `rrUnique`/`rrAmbiguous`/`rrUnresolved`. When func+template share the same name in the same module, `resolveCallTarget` returns `rrAmbiguous` (candidates.len == 2). The `topology_engine.nim:45-47` check `res.kind == rrUnique` fails for `rrAmbiguous`, so **no dependency edge is added**. The template's `dependencyIds` is now empty, and `allDependenciesVerified` returns true.

**File:line evidence:**
- `src/core/topology/topology_dependency.nim:12-38` — `ResolutionResult` type and `resolveCallTarget` returning `rrAmbiguous` for same-module func+template pairs
- `src/core/topology/topology_engine.nim:45-47` — `if res.kind == rrUnique and res.resolvedIdx != idx` (only unique resolutions add dependency edges)
- `src/core/topology/verified_frontier.nim:88-89` — `allDependenciesVerified` now passes because template has no self-referencing dependency

### WP4-d-3 (subjectMode): Not relevant to V3 blocker

- Added `subjectMode: bool = false` parameter to `computeVerifiedFrontier`
- When `subjectMode=true`, kernel-scope/exempt gates are skipped
- This affects admission of kernel symbols in external subject mode, not the duplicate nodeId issue

---

## Classification

**getBitsBE frontier admission: FIXED (V3 blocker removed)**
- getBitsBE is now in the verification frontier (unlike WP4-c where it was excluded)
- It reaches A3 (IR classification) and generates an obligation

**getBitsBE A4/planning: NOT YET REACHED**
- It is skipped as `illFormed` at the SMT adapter stage
- This is a separate issue from the V3 blocker — the SMT adapter cannot handle the `type[SomeUnsignedInt]` generic parameter in the func signature

**Overall classification: Incomplete**
- The V3 blocker (false self-dependency from duplicate func+template nodeId) is resolved
- But getBitsBE cannot be fully verified because the SMT adapter produces an empty script for its type

---

## What the Evidence Does and Does NOT Establish

### Does establish:
- The WP4-d-2 `resolveCallTarget` → `ResolutionResult` change prevents the template from getting a self-referencing dependency edge when func+template share the same name in the same module
- getBitsBE is now admitted to the verification frontier (A2) and reaches IR classification (A3)
- The false self-dependency that blocked getBitsBE in WP4-c is removed

### Does NOT establish:
- That getBitsBE can be fully verified (it's skipped as `illFormed` at A4)
- That the `definitionFingerprint` (WP4-d-1) fixes the V3 blocker (it doesn't — it's additive metadata)
- That all other func+template pairs with shared nodeIds are also fixed (the `rrAmbiguous` path is general and should apply to all such pairs)
- That the `illFormed` skip at A4 is a permanent limitation vs. a fixable SMT adapter issue

---

## Recommended Next Step

1. **Investigate the `illFormed` skip for getBitsBE** — the SMT adapter produces an empty script for `vtStructural` classification with generic `type[SomeUnsignedInt]` parameter. This may be fixable in the IR-to-SMT adapter (`ir_pipeline_runner.nim` / `TheaterGuard`).
2. **Run the full frontier (no `--target`)** to confirm all other func+template pairs with shared nodeIds are also now admitted to the frontier.
3. **Add a unit test** for the `rrAmbiguous` path in `resolveCallTarget` to prevent regression of the V3 blocker fix.
