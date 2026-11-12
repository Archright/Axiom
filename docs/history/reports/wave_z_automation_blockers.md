# Wave Z Automation Blocker Analysis: `verifyCertificates`
## Why 403-line Nim God Functions Resist Mechanical Refactoring

---

## Blocker 1: 10-Level Nesting Depth (22-space indentation)

### Measurement
| Depth | Spaces | Lines | What lives here |
|-------|--------|-------|-----------------|
| L0 | 2 | 90 | Function body, top-level guards |
| L1 | 4 | 58 | `if`/`for`/`try` blocks |
| L2 | 6 | 65 | Nested conditionals |
| L3 | 8 | 46 | Inner loops |
| L4 | 10 | 20 | Loop body logic |
| L5 | 12 | 2 | Nested structure |
| L6 | 14 | 14 | Invariant synthesis inner |
| L7 | 16 | 29 | CFG/loop header processing |
| L8 | 18 | 42 | Z3/Lean4 cross-validation |
| L9 | 20 | 9 | Audit event JSON construction |
| **L10** | **22** | **1** | `ivMap[k] = %intervalToString(v)` |

### Deepest line (L10, line 902):
```nim
                      ivMap[k] = %intervalToString(v)
```
This is **inside**: proc body → if enableSymbolic → for cert → for headerId → if hasLoops → if invOpt.isSome → if isLayer1 → (block: var ivMap...) → for k,v → assignment.

### Why automation fails
To extract this to a standalone proc, every line must be **re-indented** by subtracting 10 levels × 2 spaces = 20 spaces. A single off-by-one error in indentation causes Nim compiler to reject the entire file. Python scripts cannot reliably compute the correct target indentation because Nim's indentation is **semantic** — it determines block structure.

---

## Blocker 2: Inline Closures Capturing Local Variables

### Closure at line 743 (6 lines, L2 depth):
```nim
invalidateDependents(result.certificates, proc (cert: var FunctionCertificate; dependency: string) =
    if cert.status != certStale:
      markCertificatePendingByDependency(cert, dependency)
)
```

### Closure at line 871 (7 lines, L7 depth):
```nim
let invOpt = synthesizeLoopInvariant(
    cfg, headerId,
    proc(query: string): bool {.closure, gcsafe.} =
      let z3res = z3Provider.prove(...)
      if not z3res.ok:
        return false           # ← returns from CLOSURE, not outer function
      ...
      return output == "unsat",
    candidateInvariants, initiationContext
)
```

### Why automation fails
These are **anonymous functions** passed as parameters. The second closure:
1. Captures `z3Provider` (local variable)
2. Captures `leanProvider` (created conditionally inside the closure)
3. Has `return` statements that exit the **closure**, not the outer function

To extract: requires **closure conversion** — transforming the anonymous function into a named proc with explicit environment parameters. This is a compiler-level transformation, not a text-level refactoring.

---

## Blocker 3: Section Boundary Blur — Interleaved Audit Code

Lines 768-791 show how **audit event emission** is interleaved between gate applications:

```nim
# Section 10: Physical ASI Guard
result.totalTrustedFunctions = countSourceFunctions(graph)
result.missingCertificates = max(0, ...)
if result.totalTrustedFunctions == 0:
    result.blockingFailure = true
    return

# Audit emission (belongs to Section 9's gate, but placed AFTER Section 10)
let auditPath = joinPath(repoRoot, "logs", "audit", "stream.jsonl")
for violation in result.globalInfluenceGate.violations:   # ← references Section 9's gate
    discard appendGlobalInfluenceEvent(...)

# Section 11: Type Integrity Gate
result.typeIntegrityGate = applyTypeIntegrityGate(result.certificates)

# Audit emission again (for Section 11)
for violation in result.typeIntegrityGate.violations:
    discard appendGlobalInfluenceEvent(...)
```

### Why automation fails
Clean extraction requires grouping `applyGate → emitAudit` as a single unit. But `auditPath` is declared **between** Section 10 (ASI guard) and Section 11 (Type gate), and used by both Section 9's audit loop AND Section 11's audit loop. The variable's lifetime spans across 3 conceptual sections. No automated tool can determine the correct scope boundary without semantic understanding.

---

## Blocker 4: 5 Early-Return Paths from Different Depths

| # | Line | Depth | Condition |
|---|------|-------|-----------|
| 1 | ~604 | L0 | `certDir` doesn't exist → `return` |
| 2 | ~774 | L0 | `totalTrustedFunctions == 0` → `return` |
| 3 | ~877 | L7 | `z3res.ok == false` → `return false` (closure) |
| 4 | ~880 | L7 | Lean fallback result → `return` (closure) |
| 5 | ~882 | L7 | `output == "unsat"` → `return` (closure) |

### Why automation fails
Returns 3-5 are **inside an inline closure** at depth L7. The `return` exits the closure, not `verifyCertificates`. To extract the symbolic analysis section, the tool must:
1. Detect that these `return`s belong to a closure, not the function
2. Preserve closure semantics during extraction
3. Handle the fact that `z3Provider` is defined **outside** the closure but **used inside** it

---

## Blocker 5: State Object Mutation Across All Sections

The function operates on shared mutable state without clear ownership boundaries:

| Variable | Type | Mutated by sections |
|----------|------|---------------------|
| `result` | `var VerificationReportSummary` | 1,2,3,4,5,6,7,8,9,10,11,12,13,14 |
| `idx` | `var VaultIndex` | 1,2,4,14 |
| `graph` | `var GlobalSymbolGraph` | 2,9 |
| `currentGraphHash` | `var string` | 4,9 |

### Why automation fails
Extracting a section to a standalone proc requires deciding which `var` parameters to pass. But sections **interleave** their mutations. For example, Section 10 (`result.totalTrustedFunctions`) runs between Section 9's gate application and Section 9's audit emission. If you extract Section 9 as a standalone function, it either:
- Includes Section 10 (breaking domain boundaries), or
- Has incomplete state (missing the ASI guard's side effect)

---

## Blocker 6: Nim's Indentation-Semantic Coupling

Unlike Python (which also uses indentation), Nim's indentation is **not optional** and cannot be bypassed with braces. Additionally:

1. **No `pass`/`...` placeholder**: Empty blocks must be at least valid syntax
2. **`result` variable is implicit**: `result` inside a proc refers to the return value; inside a nested proc, it refers to the nested proc's return. Extracting code to a standalone proc changes what `result` refers to.
3. **`{.raises: [].}` effect system**: The original function has effect annotations. Extracted code must maintain compatible effect annotations or the compiler rejects it.

### Concrete example of `result` ambiguity
```nim
# Original (inside verifyCertificates):
for i in 0 ..< result.certificates.len:   # ← result is VerificationReportSummary
    ...
    result.certificates[i] = cert

# If extracted to standalone proc:
proc hydrateAll(result: var VerificationReportSummary) =
    for i in 0 ..< result.certificates.len:   # ← result is NOW the proc's return value
        ...                                    #     which shadows the parameter!
```

Nim would flag this as a name collision between the implicit `result` and the parameter named `result`.

---

## What Made the 7 Successful Refactorings Different

| Property | Successful (×7) | Failed (verifyCertificates) |
|----------|-----------------|----------------------------|
| Max nesting depth | 3 | 10 |
| Lines extracted | 5–60 | 403 |
| Inline closures | 0 | 2 |
| Early returns | 0 | 5 |
| Cross-section state | Single shared var | 4 interleaved vars |
| Section boundaries | Comment-delimited | Interleaved audit code |

The 7 successful refactorings all targeted **leaf functions** or **self-contained blocks** at shallow nesting depths with clear boundaries and no closures. `verifyCertificates` is the polar opposite on every metric.

---

## Required: Manual Refactoring with Nim-Aware Tooling

To safely refactor `verifyCertificates`, the following capabilities are needed:

1. **AST-level extraction** — a tool that understands Nim's AST, not text-level pattern matching
2. **Closure conversion** — ability to lift inline closures to named procs with explicit capture lists
3. **Effect propagation** — automatically compute `{.raises.}` and `{.noSideEffect.}` for extracted functions
4. **`result` renaming** — detect and resolve name collisions between implicit `result` and explicit parameters

These are **compiler-level transformations**. They exceed what text-based or regex-based tools can safely perform.
