# effect_contract_projection.md

# Effect Contract Projection — Specification

## 1. Subject Universe

**Scope**: `src/core/**/*.nim` — all `.nim` files recursively under `src/core/`.

**Subjects**: Canonical `proc` and `func` declarations only.

**Excluded types** (not subjects, not counted):
- `template` declarations
- `macro` declarations
- `iterator` declarations
- `converter` declarations
- `type` declarations
- Declarations inside template/macro/iterator/converter bodies (macro-generated)

**Declaration identity**: `(path, symbol, kind)` where:
- `path`: relative path from repo root (e.g., `src/core/types/results.nim`)
- `symbol`: extracted function/procedure name (without export marker `*`)
- `kind`: `"proc"` or `"func"`

## 2. Effective Effect Environment — Five Rules

A declaration is **COMPLIANT** iff the effective effect environment at its declaration point carries an explicit `raises` contract. Otherwise it is a **VIOLATION**.

### Rule 1: Declaration-Local Inline Raises Pragma

The declaration's header/adjacent pragma block (`{.raises: [...].}`) belongs to THIS declaration regardless of blank lines or comments between them. Parse by declaration header token sequence, NOT line distance.

**Accepted forms**:
```nim
proc foo() {.raises: [].} =           # Same-line pragma
proc foo()                            # Multi-line header
{.raises: [].} =                      # Pragma on next line
proc foo(                             # Multi-line params + pragma
  x: int,
  y: string
): bool {.raises: [IOError].} =       # Pragma after return type
```

**Parsing algorithm**: From the declaration keyword line, scan forward until hitting:
- A new top-level declaration (`proc`, `func`, `template`, `macro`, `iterator`, `converter`, `type`)
- A line starting with `=` (body start)
- A blank line (if no pragma found yet)

Within this region, look for `{.raises:` pragmas. The LAST one wins (Rule 3).

### Rule 2: File-Scope Push/Pop Nesting

File-scope `{.push raises: [...].}` / `{.pop.}` / `{.pop raises: [...]}` nesting determines compliance for declarations declared while depth > 0.

**Tracking rules**:
- `{.push raises` (anywhere in line) → increment `raisesPushDepth`
- `{.pop raises` (and depth > 0) → decrement `raisesPushDepth`
- `{.pop.}` (and depth > 0) → decrement `raisesPushDepth`

A declaration is compliant if `raisesPushDepth > 0` at the point of declaration.

**Example**:
```nim
{.push raises: [].}                    # depth = 1

proc foo(): int = discard              # COMPLIANT (depth > 0)
proc bar(): int = discard              # COMPLIANT (depth > 0)

{.pop.}                                # depth = 0

proc baz(): int = discard              # VIOLATION (depth = 0, no inline pragma)
```

### Rule 3: Multiple Raises Declarations — Last Wins

If multiple `{.raises: ...}` pragmas appear in a single declaration's header region, the LAST one determines compliance.

### Rule 4: When/Branch Selection — Count All

The projection performs NO branch selection. Every source-visible eligible declaration is counted regardless of `when`, `when defined()`, `elif`, or `else` conditions. This ensures configuration-independence and deterministic output across platforms/defines.

**Example**:
```nim
when defined(linux):
  proc linuxProc(): int {.raises: [].} = discard   # COUNTED as compliant

when defined(windows):
  proc winProc(): int = discard                     # COUNTED as violation

else:
  proc otherProc(): int {.raises: [].} = discard    # COUNTED as compliant
```

All three declarations are counted. The `when` condition is not evaluated.

### Rule 5: Include Files

Statements from `include` directives are projected as they appear in the including file's source. Declarations from included snippets are attributed to the INCLUDING file by their source text.

**Implementation decision**: When encountering an `include` statement, the scanner resolves the include target path relative to the including file's directory, then falls back to the project root. The included file is read and scanned for declarations, which are attributed to the including file's path.

**Rationale**: In Nim, `include` performs textual inclusion — declarations in the included file are effectively part of the including file's source. Attributing them to the including file preserves the correct scope context for push/pop tracking.

## 3. Eligibility

Only `proc` and `func` declarations are subjects. All other declaration kinds (`template`, `macro`, `iterator`, `converter`, `type`) are excluded from the subject universe entirely.

Declarations inside template/macro/iterator/converter bodies are excluded because they are macro-generated — they do not exist as independent subjects in the compiled code.

## 4. Configuration Independence

The projection is fully configuration-independent:
- No compiler flags affect the output
- No `when`/`defined()` evaluation occurs
- No platform-specific behavior
- Output is deterministic: same input → byte-identical JSON

## 5. Output Schema

```json
{
  "declarations": <int>,
  "violations": <int>,
  "eligible": [<sorted symbol names>],
  "violations_list": [
    {"path": "<relative path>", "symbol": "<name>", "kind": "proc|func"},
    ...
  ]
}
```

- `declarations`: total count of eligible declarations
- `violations`: count of declarations lacking an explicit raises contract
- `eligible`: sorted array of all declaration symbol names
- `violations_list`: sorted array of violation details (by path, then symbol, then kind)

## 6. Golden Comparison Rubric

The legacy-vs-new comparison tool (`tools/effect_contract_golden.nim`) uses the following allowed-diff rubric:

**Expected flips** (exit 0):
1. **Legacy false positive**: Legacy 8-line scan found a `{.raises:` pragma in a nearby declaration's header and incorrectly attributed it to this declaration. New projection correctly identifies it as belonging to a different declaration.
2. **Legacy false negative**: A declaration has an inline raises pragma but is more than 8 lines away from the declaration line (multi-line header with many parameters). Legacy scan missed it; new projection finds it.
3. **Push-scope coverage**: A declaration is inside a `{.push raises: [].}` scope. Legacy correctly handles this, but edge cases with nested push/pop may differ.

**Allowed flip rate**: ≤ 20% of total declarations. If flips exceed this threshold, the comparison exits with code 1, indicating significant divergence that requires investigation.

## 7. Measurement Change = ContractRevision

This projection replaces the legacy 8-line heuristic with AST-semantic source-text parsing. The change is tracked as CONTRACT-0002 (parent: CONTRACT-0001) in `config/policy/contract_revisions.json`.
