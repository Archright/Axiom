# Registry Migration Checklist (Phase 5)

> Addresses DEBT#267 (Registry Hygiene)
> Durable checklist for Phase-5 registry migrations to ensure SSOT consistency.

## Phase 5 — Registry Migration Steps

Run these steps in order **after any migration** to `data/debt_registry.json` (add, remove, reclassify, or renumber entries):

### Step 1: Regenerate derived artifacts

```bash
# debt_codegen regenerates:
#   - src/generated/debt_constants.nim  (compile-time constants + doAssert gate)
#   - docs/DEBT_REGISTRY.md            (human-readable markdown)
nim c -r tools/debt_codegen.nim
```

Exit code must be 0. Verify the output: check that `docs/DEBT_REGISTRY.md` header counts match the registry.

### Step 2: Verify cross-file synchronization

```bash
# check_debt_sync validates consistency across:
#   - data/debt_registry.json
#   - data/architecture_debt.json
#   - data/debt_ledger.json
#   - docs/DEBT_REGISTRY.md
nim c -o:bin/check_debt_sync tools/check_debt_sync.nim && bin/check_debt_sync
```

Exit code must be 0 (all 6 check groups pass). Any failure blocks migration.

### Step 3: Verify the SSOT

Compare open/closed counts between `data/debt_registry.json` and `docs/DEBT_REGISTRY.md`:

```bash
# Count entries in JSON registry
python3 -c "
import json
reg = json.load(open('data/debt_registry.json'))
entries = reg['entries']
open_c = sum(1 for e in entries if not ('closed' in e['status'].lower() or 'exemption' in e['status'].lower()))
total = len(entries)
print(f'SSOT: total={total}, open={open_c}, closed={total-open_c}')
"
```

Then verify the markdown header reports the same numbers.

### Step 4: Compile-time gate check

Build the project and confirm the `debt_constants.nim` `doAssert` gate passes:

```bash
nim c src/cli/main.nim 2>&1 | grep -i 'debt\|critical\|threshold\|doAssert'
```

No `doAssert` failure output must appear.

### Step 5: Commit and record

1. Stage all changed files (registry + generated + docs)
2. Check diff: `git diff --cached --stat`
3. Commit with message referencing DEBT#267:
   ```
   DEBT#267: Phase 5 registry migration — <summary of changes>
   ```
4. Use `axiom-gate commit` (not raw `git commit`)

## Recovery

If any step fails:

1. **Step 1 fails**: revert registry changes — the codegen tool found invalid data
2. **Step 2 fails**: identify which check group failed and fix the root cause (likely a cross-file mismatch)
3. **Step 3 fails**: the markdown header is stale — re-run Step 1 (debt_codegen always regenerates from SSOT)
4. **Step 4 fails**: open critical debt exceeds `DebtCriticalThreshold` — resolve critical items or adjust threshold via `-d:DebtCriticalThreshold=N`
