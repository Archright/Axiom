# BestEffort Migration Guide

## Objective
Migrate 21 `# axiom:best-effort` comments to `{.bestEffort("""reason""").}` pragma manually.

## Pragma Syntax Rule: Always use triple-quotes (`"""..."""`) for reasons containing quotes or commas

When a reason string contains quotes, commas, or other special characters, use triple-quote syntax to avoid pragma parser errors:

**Example with special characters:**
```nim
# Before
# axiom:best-effort(git not available — safe fallback to "unknown", audit record still written)

# After
proc myProc() {.bestEffort("""git not available — safe fallback to "unknown", audit record still written""").} = ...
```

**Standard syntax (no special characters):**
```nim
# Before
# axiom:best-effort(temp file cleanup)

# After
proc myProc() {.bestEffort("temp file cleanup").} = ...
```

## Steps
1. **Find target files**:
   ```bash
   cd .
   grep -r "axiom:best-effort" src/ | cut -d: -f1 | sort -u
   ```

2. **For each file**:
   - Locate the `# axiom:best-effort(...)` comment
   - Find the containing `proc`/`func` definition
   - Add `{.bestEffort("""reason""").}` pragma to the proc/func signature
   - Remove the original `# axiom:best-effort` comment after migration

3. **Pragma placement**:
   - **No existing pragma**: Add `{.bestEffort("""reason""").}` before `=`
   - **Existing pragma block**: Insert `bestEffort("""reason""")` inside `{. ... .}`

4. **Example**:
   ```nim
   # Before
   # axiom:best-effort(git not available — safe fallback)
   proc myProc() = ...
   
   # After
   proc myProc() {.bestEffort("""git not available — safe fallback""").} = ...
   ```

5. **Verify compilation** (replace the example placeholder path below with the migrated file):
   ```bash
   nim check <path/to/migrated/file.nim>
   ```

## Files to Migrate (21 comments in 11 files)
1. `src/gate/runners/anti_theater_gate.nim` (2 comments)
2. `src/infrastructure/bypass_audit.nim` (1 comment)
3. `src/infrastructure/cache_gc.nim` (2 comments)
4. `src/infrastructure/gate_signing/axiom_prove.nim` (1 comment)
5. `src/core/trusted/stdlib_shield.nim` (1 comment)
6. `src/core/trusted/architecture_invariants.nim` (2 comments)
7. `src/core/judge/smart_search.nim` (3 comments)
8. `src/core/audit/hotspot_analyzer.nim` (4 comments)
9. `src/core/audit/governance_engine.nim` (2 comments)
10. `src/core/topology/import_graph.nim` (1 comment)
11. `src/cli/precompile_gates.nim` (2 comments)

## Notes
- Remove the original `# axiom:best-effort` comment after adding pragma
- Ensure reason string is at least 5 characters
- Use triple-quotes (`"""..."""`) if reason contains quotes or commas
- Test compilation after each file
