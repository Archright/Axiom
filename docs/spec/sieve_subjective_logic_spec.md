# Sieve Subjective Logic Engine — Specification

> DEBT#182 — Last updated: 2026-06-05

## Purpose

The Sieve subsystem is a **Pre-Sieve evidence synthesis engine** that evaluates source code complexity
risk before it enters the verification pipeline. It uses Jøsang's Subjective Logic theory to
probabilistically combine evidence from heterogeneous sources into a single fused opinion, then
produces a block/warn/pass verdict.

**Key invariant**: All rules are pure functions (`func`, `{.raises: [].}`). AST parsing is performed
once at `SieveContext` construction time (I/O boundary), and rules operate on the cached `XmlNode`.

## Module Map

| File | Responsibility |
|------|---------------|
| `subjective_logic.nim` | Core math: `BinomialOpinion`, fusion operators, probability projection. All `func`, zero heap. |
| `sieve_types.nim` | Type definitions: `SieveContext`, `RuleResult`, `SieveVerdict`, `ConflictIntensity`, `SieveRule` proc type. |
| `sieve_rules.nim` | Three pure rule implementations: topology, AST, unsat-core. XML AST helper utilities. |
| `sieve_engine.nim` | Orchestration: `applyPreSieve()` runs rules, `fuseAll()`, conflict detection, threshold evaluation. |
| `sieve_bridge.nim` | Z3 unsat-core → `BinomialOpinion` mapping. Deterministic token-boundary matching. |
| `ast_inspector.nim` | Unified single-pass AST DFS for structural risk detection (loops, recursion, non-linear ops, quantifiers). |

## Key Types

```
BinomialOpinion = object     # Jøsang opinion tuple
  b, d, u, a: float          # belief, disbelief, uncertainty, base rate
                               # Constraint: b + d + u = 1.0

SieveContext = object         # Input to rules
  sourceCode, nodeId, functionName, modulePath: ...
  topology: TopologyNodeMetric
  unsatCoreVars: seq[string]
  astCache: Option[XmlNode]   # Parsed once at construction

RuleResult = object           # Single rule output
  source: SieveSourceKind     # rsTopology | rsAstAnalysis | rsUnsatCore
  opinion: BinomialOpinion
  verdict: "linear" | "nonlinear" | "recursive"

SieveVerdict = object         # Final fused output
  blocked: bool               # E >= 0.50
  combinedOpinion: BinomialOpinion
  probabilityScore: float     # E = b + a·u
  conflictDetected: bool
  conflicts: seq[ConflictIntensity]
```

## Mathematical Foundation

| Operation | Jøsang Ref | Use Case |
|-----------|-----------|----------|
| `cumulativeFusion(x, y)` | Eq. 4.96 | Same-proposition, independent observers (fuse rule opinions) |
| `binomialAnd(x, y)` | Eq. 4.6 | Different-frame conjunction |
| `binomialOr(x, y)` | De Morgan | Different-frame disjunction |
| `binomialNot(x)` | — | Negation |
| `probabilityProjection(ω)` | — | E = b + a·u (expected danger probability) |
| `padOpinion(ω)` | — | ε-padding to prevent dogmatic Case II (u < ε) |

## Entry Points

### `applyPreSieve(ctx: SieveContext, rules): SieveVerdict`
1. Run each rule → collect `RuleResult` opinions
2. `fuseAll(opinions)` via cumulative fusion
3. `detectConflicts()` — pairwise safe-vs-danger detection
4. Threshold: `E >= 0.50` → blocked, `E >= 0.30` → warning

### `buildSieveContext(sourceCode, nodeId, topology, ...): SieveContext`
I/O boundary proc: parses source into `XmlNode` cache via Nim compiler parser.

### `inspectAstNodeSafe(sourceCode, funcName, unsatVars): AstInspectionResult`
Safe AST inspector wrapper used by other subsystems (returns empty result on parse failure).

## Default Rules

1. **`evaluateTopology`** — nesting depth > 4 or branch count > 20 → high danger belief
2. **`evaluateAst`** — recursion (b=0.95), loops (b=0.85), non-linear ops detected in cached AST
3. **`evaluateUnsatCore`** — delegates to `sieve_bridge.mapUnsatCoreToOpinion()` for Z3 artifact mapping

## Integration Points

- **`src/core/topology_engine`** — provides `TopologyNodeMetric` for rule 1
- **`src/core/parsers/compiler/parser`** — Nim compiler AST parsing at context construction
- **Verification pipeline** — Sieve verdict gates entry into UAP (Universal Acceptance Pipeline)
- **Refactoring engine** — non-linear/recursive verdicts inform template selection

## Known Limitations

- **Base rate default**: All rules use fixed base rate `a = 0.3`–`0.5`; no adaptive base rate calibration.
- **AST cache scope**: `SieveContext` caches one function's AST; cross-function analysis requires separate contexts.
- **Conflict intensity**: Uses `min(danger.d, safe.b)` — a simplification; no weighted conflict resolution.
- **Thresholds are constants**: `blockThreshold = 0.50`, `warningThreshold = 0.30` — not configurable per-project.
