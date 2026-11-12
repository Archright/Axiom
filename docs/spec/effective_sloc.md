# EffectiveSLOC Contract

## Version

- Algorithm version: `EffectiveSlocAlgorithmVersion` — defined in `src/core/sloc_policy.nim`
- Policy version: `EffectiveSlocPolicyVersion` — defined in `src/core/sloc_policy.nim`
- The engine (`src/core/ast_kernel.nim`) references these constants; no version string is hardcoded in source or docs.

## Definition

```
EffectiveSLOC = number of distinct source lines containing
                at least one effective source-origin syntax unit
```

- **parent aggregate span is not used** — only source-origin effective unit line intervals are collected and unioned.
- **"PNode span" is not the unit** — effective source-origin span excludes synthetic/source-less nodes.

## Policy Matrix

| construct | 처리 |
|---|---|
| ordinary code | 포함 |
| comments | 제외 |
| doc comments | **제외** — doc comments are documentation artifacts that do not contribute to program logic; consistent with the general comment-exclusion policy |
| blank lines | 제외 |
| multiline string | **포함** — the source lines containing a string literal are effective source lines; the literal is a source construct that affects program behavior |
| escape `\n` inside a single-line string literal | **포함(확장)** — the span engine extends a string literal's span by `strVal.splitLines().len` (`ast_kernel.extractEffectiveSourceSpans`, DECISION-0003), so a one-physical-line literal whose VALUE embeds `\n` (e.g. `smtScript & "\n(get-model)"`) counts the value's phantom lines as effective SLOC. Workaround used by anchored procs: split the concatenation (`smtScript & '\n' & "(get-model)"`) — a char literal is not inflated |
| pragma | **포함** — pragmas have compilation/runtime effects and are part of the program's behavior specification |
| synthetic/source-less node | 제외 |
| macro source span | **포함** — macro definitions are source code that affects compilation behavior |
| nested comment | 제외 |

## Span Extractor Principle

Entry point: `parseSourceToPNode*(source): Result[PNode, string]` (fail-closed) converts raw source to PNode, then `extractEffectiveSourceSpans*` traverses the PNode tree and collects line intervals `(startLine, endLine)` from **individual effective source-origin syntax units**:

1. Walk the PNode tree recursively.
2. For each node, determine if it is an **effective source-origin unit**:
   - Has valid source info (`info.line > 0`).
   - Is not synthetic/compiler-generated (`nkEmpty`, `nkHiddenCallConv`, `nkHiddenStdConv`, `nkHiddenSubConv`, `nkHiddenAddr`, `nkHiddenDeref`, `nkHiddenTryStmt`).
   - Is not a comment (`nkCommentStmt`).
3. For each effective unit, compute its line interval as `(info.line, maxLineAmongSourceDescendants)`.
4. Collect all intervals into a `seq[(int, int)]`.
5. **Parent aggregate spans are not used as a single interval** — each effective unit contributes its own interval.

## Union Principle

`effectiveSlocFromSpans*` computes the distinct line cardinality from a collection of line intervals:

1. Sort intervals by start line.
2. Merge overlapping/adjacent intervals.
3. Sum the length of each merged interval (`end - start + 1`).
4. Return the total count of distinct lines.

This ensures that overlapping spans from nested AST nodes do not inflate the count.

## Source SLOC vs Effective SLOC

- **Source SLOC** (`sourceSloc*`): Counts **all** syntactic branch lines across every branch of conditional compilation (`when`) and control flow (`if`/`case`). Equivalent to `effectiveSlocFromSpans(extractEffectiveSourceSpans(node))`. Ignores context — every branch contributes.
- **Effective SLOC** (`effectiveSloc*`): Counts only the **selected/active branch** lines under a given `WhenContext`. Context determines which `when` branches are active; unknown conditions produce `Unknown`. Equivalent to `effectiveSlocFromSpans(extractEffectiveSourceSpansCtx(node, ctx).get)`.
- **Context 없으면 Unknown 또는 Result 전파**: Without a `WhenContext`, `effectiveSloc` cannot resolve `when` branch selection and returns `err(urMissingSemanticContext)`. Source SLOC is the context-free fallback.

## WhenEvaluator 3-Tier

The `when` condition evaluator operates in three tiers:

| Tier | Function | Description |
|------|----------|-------------|
| Tier1 | `evalWhenConditionAST*(n: PNode): Option[bool]` | Pure constant expression: `nkTrueLit`, `nkFalseLit`, `nkInfix` with `==`/`!=` on integer literals. No context needed. |
| Tier2 | `evalWhenConditionCtx*(n: PNode; ctx: WhenContext): Option[bool]` | Declarative `WhenContext` lookup: `defined(X)` resolved against `knownDefined`/`knownUndefined` sets. No compiler semantic modules. |
| Tier3 | `evalWhen*(n: PNode; ctx: WhenContext): WhenCondition` | Combined: Tier1 first, then Tier2, then `whenUnknown`. |

**PrimaryBranch fallback is abolished.** Unknown is a first-class result — it is never silently treated as `false` or suppressed.

## DefineContext 3-State

`DefineContext` has three mutually exclusive states for any identifier `X`:

| State | Membership | `defined(X)` result |
|-------|-----------|-------------------|
| `knownDefined` | `X ∈ knownDefined` | `true` |
| `knownUndefined` | `X ∈ knownUndefined` | `false` |
| Neither | `X ∉ knownDefined` and `X ∉ knownUndefined` | **Unknown** — never assumed `false` |

**"defined(x)가 context에 없으면 False로 간주하지 않는다."** — `defined(x)` with no membership in either set must return `None` (Unknown), not `some(false)`.

## API

| Symbol | Signature | Description |
|--------|-----------|-------------|
| `sourceSloc*` | `(node: PNode): int` | Source SLOC — all branches, context-free. |
| `effectiveSloc*` | `(node: PNode; ctx: WhenContext): Result[int, UnknownReason]` | Effective SLOC — active branches only. Returns `err` on unknown condition. |
| `extractEffectiveSourceSpans*` | `(node: PNode): seq[(int, int)]` | Source-oriented span extraction — all branches. |
| `extractEffectiveSourceSpansCtx*` | `(node: PNode; ctx: WhenContext): Result[seq[(int, int)], UnknownReason]` | Context-aware span extraction — active branches only. |

- **-1 sentinel is forbidden.** All error signaling uses `Result[T, UnknownReason]`.
- `UnknownReason` values: `urMissingSemanticContext`, `urUnsupportedExpr`, `urTypeDependent`, `urMacroDependent`.

## case 7 Ratification

**case 7** (nested comment excluded from count): The proc declaration line is counted because the ratified SLOC specification counts executable/declaration source spans. A `proc` declaration line carries executable/declaration semantics even when its body contains only comments. Expected: `sourceSloc` = 2 (proc declaration + body statement), not 1.

## Hash Identity Naming

Hash identity constants use the following naming convention to distinguish literal categories:

| Name | Purpose |
|------|---------|
| `HistoricalSourceSha256` | SHA-256 of the historical source text |
| `FixtureSha256` | SHA-256 of test fixture source |
| `ImplementationSha256` | SHA-256 of implementation source |

The literal `sha256:` prefix in hash strings distinguishes hash identity from other string values.

## §D. Policy Registry Schema (`data/sloc_policy_registry.json`)

The policy registry is the SSOT for SLOC governance rules. It declares the policy version, algorithm version, and the set of semantic rules that govern how SLOC is computed.

**Schema fields**:

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | int | Registry schema version (currently 1) |
| `policy_version` | string | Must match `EffectiveSlocPolicyVersion` from `src/core/sloc_policy.nim` |
| `algorithm_version` | string | Must match `EffectiveSlocAlgorithmVersion` from `src/core/sloc_policy.nim` |
| `rules` | array | Ordered list of policy rule objects |

Each rule object:

| Field | Type | Description |
|-------|------|-------------|
| `rule_id` | string | Unique rule identifier (e.g. `SLOC-PROC-DECL`) |
| `semantic_category` | string | `declaration`, `comment`, `when`, `when-context`, `when-unknown` |
| `applicability` | string | `source-bearing` or `when-bearing` |
| `evaluation_mode` | string | `sourceSloc` or `effectiveSloc` |
| `unknown_behavior` | string | `not-applicable` or `governance-failure-unless-ratified` |
| `description` | string | Human-readable rule description |

The registry contains exactly 5 rules: `SLOC-PROC-DECL`, `SLOC-COMMENT-EXCLUDED`, `SLOC-WHEN-TIER1`, `SLOC-WHEN-CONTEXT`, `SLOC-WHEN-UNKNOWN`.

## §E. Evidence Schema (`tests/sloc/evidence/evidence_schema.json`)

Each evidence record is a ratified observation from `sourceSlocOf` or `effectiveSlocOf`.

**Schema fields**:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Evidence record ID (`ev-NNN`) |
| `fixture_raw_sha256` | string | SHA-256 of the raw fixture source string bytes |
| `metric` | string | `sourceSloc` or `effectiveSloc` |
| `context` | null or object | `null` for sourceSloc; `{"defines":{"known":[...],"unknown":[...]}}` for effectiveSloc with WhenContext |
| `expected_result` | int or object | Ratified expected value (int for success; `{"error":"..."}` for effectiveSloc Err) |
| `observed_facts` | array[string] | Observations from golden_helpers: span intervals, branch selections, or error reasons |
| `policy_refs` | array[string] | Policy rule IDs from registry that govern this record |
| `ratified_policy_version` | string | Must be `"effective-sloc-policy-v1"` |
| `ratified_at` | string | ISO 8601 date of ratification (`YYYY-MM-DD`) |

## §F. Context Schema (`WhenContext` / `DefineContext`)

The `WhenContext` object carries the declarative context for `when` branch selection:

```nim
type
  DefineContext* = object
    knownDefined*:   HashSet[string]
    knownUndefined*: HashSet[string]

  WhenContext* = object
    defines*:         DefineContext
    targetOS*:        Option[string]
    targetCPU*:       Option[string]
    compileOptions*:  HashSet[string]
```

**3-state resolution** for `defined(X)`:
- `X ∈ knownDefined` → `some(true)` (KnownDefined)
- `X ∈ knownUndefined` → `some(false)` (KnownUndefined)
- `X ∉ either set` → `none(bool)` (Unknown — never assumed false)

In evidence records, `context` is `null` for sourceSloc metrics, and `{"defines":{"known":[...],"unknown":[...]}}` for effectiveSloc metrics that use WhenContext.

## §G. Result Schema (`sourceSloc` / `effectiveSloc` return types)

| Metric | Return type | Description |
|--------|-------------|-------------|
| `sourceSloc` | `int` | Count of distinct source lines with effective source-origin units. Always succeeds. |
| `effectiveSloc` | `Result[int, UnknownReason]` | Count of distinct source lines in active branches only. Returns `err(urMissingSemanticContext)` when `when` condition cannot be resolved. |

`UnknownReason` values: `urMissingSemanticContext`, `urUnsupportedExpr`, `urTypeDependent`, `urMacroDependent`. The `-1` sentinel is forbidden; all errors use `Result[T, UnknownReason]`.