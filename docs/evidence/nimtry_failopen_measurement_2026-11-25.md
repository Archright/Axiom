# `nimtry_violations` fail-open measurement — `debt_engine --validate` Part D

> **Status**: Measurement/evidence document. **No production code change** — `tools/debt_engine.nim` unmodified. This document is the decision input for the follow-up fix PR.
> **Created**: 2026-11-25
> **Measured at**: 2026-11-25T05:13Z–05:40Z (UTC)
> **Base**: `57f2067b58560d39236ce34f1e14f45d662652f0` (`origin/main`, PR #478 merge). Local worktree `ci/vsb-nimtry-failopen-measurement`.
> **Worktree**: `/home/wintr/wt-vsb` (`git worktree add`, isolated from the main clone's uncommitted work).
> **Re-verified at `bc6e2edd`** (`origin/main`, 2026-11-26): both load-bearing findings still hold. Every line citation below is anchored to the measured SHA `57f2067b` and has drifted since; the two checked against `bc6e2edd` are noted here, and one cited region changed semantically. See §9.

## §0. Verdict summary

| Question | Verdict | Deciding evidence |
|---|---|---|
| ① Path by which the branch is reached | `--validate` (and `--close`) — **`--converge` does not exist** | §1 |
| ② Behaviour when `evalNimtryViolations()` is absent | No exception. Prints `[skip]`, then **returns the sentinel `-1`** | §2 |
| ③ Reached from a CI required context? | **Yes** — the `bin/debt_engine --validate` step of `debt-registry-gate` | §3 |
| ④ Local reproduction | **Success** — `[warn] nimtry_violations: evaluator error` + exit 0 | §4 |
| ⑤ Is it safe to make fail-closed? | **No — as things stand it makes the gate permanently red** | §5 |

**VERDICT — in the `debt-registry-gate` required context `nimtry_violations` is fail-open: YES.**

However, the hypothesis "silently skipped on every single CI run" is **only partially true**. `bin/nimtry`
**is in fact built just 2 seconds later** in the same job (§3.3). That is, nimtry is not *structurally*
absent from that job — it is provisioned **later than `--validate`**. This distinction changes the conclusion
of §5: the cost of the fix is not a "provisioning decision" but a **step-order decision**.

---

## §1. ① The subcommand the branch is reached from

### §1.1 `--converge` does not exist

```console
$ cd /home/wintr/wt-vsb && grep -n "converge" tools/debt_engine.nim
1475:    echo "  \u274c " & $driftCount & " metric(s) not converged (DRIFT or no committed ledger record)" &
```

The only match is the phrase ("not converged"). There is no `--converge` subcommand.

### §1.2 Actual dispatch (main, `tools/debt_engine.nim:3759-3778`)

```nim
proc main() {.raises: [CatchableError].} =
  let args = commandLineParams()
  if args.len == 0 or args[0] == "--help":
    usage()
    quit(0)
  case args[0]
  of "--codegen": cmdCodegen()
  of "--validate": cmdValidate()
  ...
  of "--sync-budget": cmdSyncBudget(args.len > 1 and args[1] == "--dry-run")
  of "--close": cmdClose(args[1 .. ^1])
```

### §1.3 The function wrapping the branch is `runValidateCore`

`tools/debt_engine.nim:1459-1461` — quoted:

```nim
1456:         else:
1457:           echo "  [skip] " & metricName & ": no evaluator registered (source: none — plan needed)"
1458:           continue
1459:         if liveValue < 0:
1460:           echo "  [warn] " & metricName & ": evaluator error"
1461:           continue
1462:         if ledgerCurrent < 0:
```

`continue` increments neither `passCount` nor `driftCount`. So this metric leaves no trace in either the
`370/370 PASS` or the `3 PASS, 0 DRIFT` aggregate (§4.2).

The enclosing proc is at `tools/debt_engine.nim:1341`:

```nim
1341: proc runValidateCore(): ValidateOutcome {.raises: [CatchableError].} =
```

There are only three `runValidateCore` call sites:

```console
$ grep -n "runValidateCore" tools/debt_engine.nim
1341:proc runValidateCore(): ValidateOutcome {.raises: [CatchableError].} =
1616:  let outcome = runValidateCore()
2125:  if runValidateCore() != voPass:          # --close [close/1] pre-check
2199:    let verdict = runValidateCore()        # --close [close/5] post-check
```

| Caller | subcommand | Used in CI |
|---|---|---|
| `cmdValidate` (`:1613`) | **`--validate`** | **Yes** (§3) |
| `cmdClose` (`:2125`, `:2199`) | `--close` | No (local mutation only) |

### §1.4 `--sync-budget` does not pass through this branch — it already has a separate fail-closed path

`cmdSyncBudget` → `syncBudgetCore` does its own skip accounting and fails closed at `:2031`:

```nim
2031:    echo "  Sync INCOMPLETE: " & $res.skipped.len & " of " & $res.recordsProcessed &
2032:      " BUDGET record(s) unmeasured (evaluator error or no evaluator registered)."
```

This is the path DEBT#543 (`data/debt_registry.json`, status `closed`) already fixed. That fix covered
**`--sync-budget` only**; the identical class in `--validate` remained (§5.1).

---

## §2. ② Behaviour of `evalNimtryViolations()` when it is absent

`tools/debt_engine.nim:1702-1736`. It returns early via `fileExists` **before** shelling out:

```nim
1702: proc evalNimtryViolations(): int {.raises: [CatchableError].} =
...
1713:   ## Unmeasured (binary or sidecar absent) → -1, so the ledger keeps its last
1714:   ## verified value instead of a fabricated one (DEBT#543 fail-closed).
1715:   let tool = "bin/nimtry"
1716:   if not fileExists(tool):
1717:     echo "  [skip] nimtry_violations: evaluator binary unavailable (" & tool & ")"
1718:     return -1
1719:   let livePath = "data/nimtry_live_count.json"
...
1728:   removeFile(livePath)
1729:   discard execCmdEx(tool & " src/")   # refreshes the live-count sidecar
1730:   if not fileExists(livePath):
1731:     echo "  [skip] nimtry_violations: live-count sidecar unavailable (" & livePath & ")"
1732:     return -1
1733:   try:
1734:     result = parseJson(readFile(livePath)){"total_violations"}.getInt(-1)
1735:   except CatchableError:
1736:     result = -1
```

**Sentinel value: `-1`.** All three paths give `-1` — (a) binary absent, (b) sidecar absent, (c) sidecar
parse failure. It **does not throw** and does not `raise` (`{.raises: [CatchableError].}` is used only for
`removeFile`).

That is, `-1` is a **value designed to mean "unmeasurable"**. The docstring states that intent:

```nim
1729:  ## Unmeasured (binary or sidecar absent) → -1, so the ledger keeps its last
1730:  ## verified value instead of a fabricated one (DEBT#543 fail-closed).
```

There is no need to remove `-1`. **The sentinel itself is correct.** The defect lies in *how `-1` is
disposed of*: `--sync-budget` promotes `-1` to INCOMPLETE (`:2031`), while `--validate` discards it with
`continue` (`:1461`).

### §2.1 Sibling evaluators share the same fail-open contract

| evaluator | when absent | location |
|---|---|---|
| `evalNimtryViolations` | `-1` | `:1720-1722` |
| `evalLayerViolations` | `-1` | `:1676-1681` |
| `evalEffectViolations` | `-1` | `:1793-1804` |
| `evalImportLintViolations` | `-1` (but `tools/` always exists in CI → effectively unreachable) | `:1767-1770` |

So the defect is not specific to `nimtry_violations` but a **disposition rule common to all 4 evaluators**.

---

## §3. ③ Reaching it from a CI required context

### §3.1 `debt-registry-gate` is a required validation

`config/policy/merge_admission.json` `requiredValidations`:

```json
{
  "workflowPath": ".github/workflows/debt-registry-gate.yml",
  "job": "debt-registry-gate",
  "acceptableConclusion": "success",
  "workflowIdObservation": { "value": 414023986, "observedAt": "2026-11-11T01:01:50Z" }
}
```

### §3.2 Workflow steps (`.github/workflows/debt-registry-gate.yml:45-48`)

```yaml
45:      - name: Build canonical debt validator
46:        run: make bin/debt_engine
47:      - name: Enforce Theater registry contract (unconditional)
48:        run: bin/debt_engine --validate
```

`:48` executes exactly the branch from §1.3. The "(unconditional)" in this step's name is the irony — the
step runs unconditionally, but one metric inside it is unconditionally skipped.

### §3.3 The workflow itself already wrote this fact down

`.github/workflows/debt-registry-gate.yml:24-31`:

```yaml
24:          # nim scope — this job's toolchain uses are `make bin/debt_engine`
25:          # + `bin/debt_engine --validate`, `make check-nim-theater`
...
28:          # binding, VS-2). The gate is compiled -d:release so the reduction
29:          # ratchet cannot downgrade to WARN, and runs without bin/nimtry,
30:          # so its nimtry active-violation metric reports "unmeasured" here
31:          # while marker binding is enforced unconditionally.
```

"reports 'unmeasured'" is an **optimistic description**. In reality it is not "unmeasured" — nothing is
reported at all: the aggregate (`1879 total, 1879 passed, 0 failed` / `3 PASS, 0 DRIFT`) contains no
`unmeasured` entry. The observed fact is "not reported" (§4.2).

### §3.4 Direct measurement: the log of a real merge_group run (the strongest evidence)

```console
$ gh run view 45553393942 --log | grep "Enforce Theater registry contract" \
    | sed -E 's/^[^\t]+\t[^\t]+\t[0-9T:.Z-]+ ?//' | sed -n '/Part D:/,/Part D.1:/p'
=== Part D: Budget metric evaluation ===
  ✅ import_lint_violations PASS (projection=0 == ledger 0)
  [skip] layer_violations: evaluator binary unavailable (bin/layer_enforcement_gate)
  [warn] layer_violations: evaluator error
  [skip] effect_violations: evaluator binary unavailable (bin/effect_contract_projection)
  [warn] effect_violations: evaluator error
  [skip] nimtry_violations: evaluator binary unavailable (bin/nimtry)
  [warn] nimtry_violations: evaluator error
  ✅ debt_registry_open PASS (projection=40 == ledger 40)
  ✅ debt_registry_closed PASS (projection=261 == ledger 261)

=== Part D.1: Policy disposition resolution ===
```

Run metadata: `conclusion=success`, `event=merge_group`,
`headSha=963c8ae8a0c8be4bf709073ac61349ed67a208ed`, `createdAt=2026-11-25T05:24:49Z`,
`https://github.com/Archright/Axiom/actions/runs/45553393942`.

The summary line is quoted as well:

```console
$ gh run view 45553393942 --log | grep "Metric evaluation"
...Z   Metric evaluation: 3 PASS, 0 DRIFT
```

**Three of six metrics were skipped, yet the aggregate is "3 PASS, 0 DRIFT".** The three skipped ones do not
exist as far as the wording goes. The `[warn]` lines do remain, so it is **not entirely silent**, but they
have no effect whatsoever on the verdict (exit code) — if nobody reads the log, nobody knows.

### §3.5 Key correction: `bin/nimtry` really is built in that job — but **after** `--validate`

The hypothesis ("nimtry is NEVER provisioned in that job") is **false**. A later step of the same run,
`Build bidirectional debt binding gate`, pulls in `nimtry-measure` and compiles `bin/nimtry`:

```console
$ gh run view 45553393942 --log | grep -E "\-o:bin/nimtry|Part D: Budget"
Enforce Theater registry contract (unconditional)  2026-11-25T05:25:19.7125400Z  === Part D: Budget metric evaluation ===
Build bidirectional debt binding gate             2026-11-25T05:25:21.8209887Z  nim c ... -d:release -o:bin/nimtry src/gate/nimtry.nim
Build bidirectional debt binding gate             2026-11-25T05:25:30.8525201Z  [nimtry-baseline-check] OK: 4375 fingerprints, version 2
Build bidirectional debt binding gate             2026-11-25T05:25:33.5499437Z  [nimtry-measure] sidecar produced; ...
```

**`--validate` 05:25:19.712 → nimtry build 05:25:21.821. Gap about 2.1 seconds.**

The root cause is the missing dependency at `Makefile:277-278`:

```make
274: DEBT_AUDIT_SRCS := tools/debt_engine.nim $(wildcard src/core/debt/*.nim) \
275:                    $(wildcard src/infrastructure/debt_audit/*.nim)
276:
277: bin/debt_engine: $(DEBT_AUDIT_SRCS)
278: 	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<
```

`bin/debt_engine` does not carry the evaluator binaries as prerequisites. `bin/debt_integrity_gate`, by
contrast, carries `| nimtry-measure` as an order-only prerequisite (`Makefile:292-295`).
So **two different provisioning contracts coexist inside the same job**.

CI step order (measured):

```console
$ gh run view 45553393942 --log | cut -f2 | uniq
Set up job
Run actions/checkout@...
Run ./.github/actions/setup-axiom-toolchain
Ensure Draft 2020-12 validator
Build canonical debt validator
Enforce Theater registry contract (unconditional)      ← --validate: nimtry absent
Theater five-field negative fixture
Enforce Nim theater static scan (unconditional)
Build bidirectional debt binding gate                  ← bin/nimtry created here
Enforce bidirectional debt registry↔code binding (unconditional)
...
```

`bin/` is gitignored and therefore not part of a clone — the fact that `bin/nimtry` exists in the local main
clone (1,504,536 bytes, Nov 23 10:49) proves nothing about CI:

```console
$ git check-ignore -v bin/nimtry
.gitignore:288:bin/nimtry	bin/nimtry
$ git ls-files bin/nimtry
              # (empty output = untracked)
$ head -2 .gitignore
bin/*
!bin/.gitkeep
```

---

## §4. ④ Local reproduction

### §4.1 Build (using the repository's documented path)

```console
$ cd /home/wintr/wt-vsb && make bin/debt_engine
nim c --hints:off --skipParentCfg --skipProjCfg --path:$HOME/.choosenim/toolchains/nim-2.2.10 \
  --path:. --path:src --path:tools --nimcache:build/nimcache/tools -o:bin/debt_engine tools/debt_engine.nim
real	0m6.331s

$ make bin/nimtry        # Makefile:202-203, -d:release
nim c ... -d:release -o:bin/nimtry src/gate/nimtry.nim
real	0m8.496s
```

`bin/nimtry` is built as a **Makefile target**, not by `nimble` (`Makefile:202`).
`src/gate/nimtry.nim` is the entry point.

### §4.2 Reproduction A — rename nimtry (equivalent to removing it) and run `--validate`

```console
$ cd /home/wintr/wt-vsb && mv bin/nimtry /tmp/nimtry.saved
$ ./bin/debt_engine --validate; echo "VALIDATE EXIT=$?"
=== Part D: Budget metric evaluation ===
  ✅ import_lint_violations PASS (projection=0 == ledger 0)
  [skip] layer_violations: evaluator binary unavailable (bin/layer_enforcement_gate)
  [warn] layer_violations: evaluator error
  [skip] effect_violations: evaluator binary unavailable (bin/effect_contract_projection)
  [warn] effect_violations: evaluator error
  [skip] nimtry_violations: evaluator binary unavailable (bin/nimtry)
  [warn] nimtry_violations: evaluator error
  ✅ debt_registry_open PASS (projection=40 == ledger 40)
  ✅ debt_registry_closed PASS (projection=261 == ledger 261)

=== Part D.1: Policy disposition resolution ===
  Checks: 1879 total, 1879 passed, 0 failed
  Metric evaluation: 3 PASS, 0 DRIFT
  All debt validation checks passed.
VALIDATE EXIT=0
```

**Key measurement**: even with `bin/nimtry` absent the result is **exit 0**.
`nimtry_violations` **disappears** from the aggregate (`3 PASS` out of 6).

**Why the rename method was chosen**: it touches neither `tools/debt_engine.nim` nor the data being
evaluated. `mv` is an atomic operation within one filesystem, and restoring with `mv` is byte-for-byte
identical. There is no flag or environment-variable bypass — the evaluator checks the **relative path**
`bin/nimtry` directly with `fileExists` (`:1719-1720`), so PATH manipulation cannot reproduce this.

### §4.3 Reproduction B — with nimtry present (control)

```console
$ cd /home/wintr/wt-vsb && mv /tmp/nimtry.saved bin/nimtry
$ ./bin/debt_engine --validate; echo "EXIT=$?"
=== Part D: Budget metric evaluation ===
  ✅ import_lint_violations PASS (projection=0 == ledger 0)
  ...
  ✅ nimtry_violations PASS (projection=4371 == ledger 4371)
  ✅ debt_registry_open PASS (projection=40 == ledger 40)
  ✅ debt_registry_closed PASS (projection=261 == ledger 261)
  Metric evaluation: 4 PASS, 0 DRIFT
EXIT=0
```

**The only difference between A and B is `3 PASS` vs `4 PASS`.** The exit code is 0 in both cases — that is,
the presence or absence of nimtry **does not change the verdict**.

### §4.4 Reproduction C — confirm that DRIFT really produces exit 1 (measuring the cost of fail-closed)

Temporarily change `nimtry_violations.current` in `data/debt_ledger.json` from `4371 → 1`:

```console
$ ./bin/debt_engine --validate; echo "EXIT=$?"
=== Part D: Budget metric evaluation ===
  ...
  ⚠️  nimtry_violations DRIFT (projection=4371 vs ledger 1)
  ✅ debt_registry_open PASS (projection=40 == ledger 40)
  ✅ debt_registry_closed PASS (projection=261 == ledger 261)
  ❌ 1 metric(s) not converged (DRIFT or no committed ledger record) — run: bin/debt_engine --sync-budget
  Metric evaluation: 3 PASS, 1 DRIFT
  Validation FAILED (ERROR disposition or fail-closed condition).
EXIT=1
VALIDATE EXIT=1
```

Restore:

```console
$ git checkout -- data/debt_ledger.json && git status --short data/debt_ledger.json
              # (empty output = restored)
```

**This measurement is the basis for the cost calculation in §5**: `driftCount > 0` → `hasErrorDisposition = true`
(`:1474-1477`) → `voErrorDisposition` (`:1609`) → `quit(1)` (`:1621-1624`).
Therefore promoting a skip to DRIFT means **exit 1 immediately**.

### §4.5 Reproduction D — the asymmetry with `--sync-budget` (same defect class, different disposition)

```console
$ cd /home/wintr/wt-vsb && mv bin/nimtry /tmp/nimtry.saved
$ ./bin/debt_engine --sync-budget --dry-run; echo "SYNC EXIT=$?"
  [DRY-RUN] No changes detected — fully synced.
  Sync INCOMPLETE: 3 of 6 BUDGET record(s) unmeasured (evaluator error or no evaluator registered).
  Unmeasured records keep their last verified value; exiting 1 (fail-closed).
  Build the missing evaluator dependencies (see [skip]/[warn] lines above) and re-run.
SYNC EXIT=1
$ mv /tmp/nimtry.saved bin/nimtry
```

| subcommand | when nimtry is absent | exit |
|---|---|---|
| `--sync-budget` | `Sync INCOMPLETE: 3 of 6 ... unmeasured` | **1** |
| `--validate` | `[warn] ... evaluator error` (ignored) | **0** |

Same `-1` sentinel, same evaluator, **opposite disposition**. `--validate` fell outside the scope of the
DEBT#543 fix.

---

## §5. ⑤ Is fail-closed safe — not a "free lane" but a **provisioning order decision**

### §5.1 Edit authority is a free lane (the edit itself is unrestricted)

| target | surface class | trust-surface manifest | verdict |
|---|---|---|---|
| `tools/debt_engine.nim` | **CONTROLLED** | **not included** | editable |
| `Makefile` | CONTROLLED | not included | editable |
| `.github/workflows/debt-registry-gate.yml` | — | **included** (`:13`) | break-glass required to edit |
| `config/policy/trust_surface_manifest.json` | — | **included** (`:20`) | self-referential |

Basis:

```console
$ grep -n "debt_engine" config/policy/trust_surface_manifest.json
              # (empty output = NOT in manifest)
$ python3 -c '...'   # result of walking the classes
CONTROLLED -> tools/debt_engine.nim
CONTROLLED -> Makefile
```

The `rules` in `config/repository_surface.json`:

```json
"PRODUCT":    { "ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS" },
"CONTROLLED": { "ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS" },
"FROZEN":     { "ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL" }
```
(`"defaultClass": "PRODUCT"`, `"resolutionOrder": ["PRODUCT","CONTROLLED","FROZEN"]`)

`CONTROLLED` has MODIFY `PASS`, the same as `PRODUCT`. By surface classification it genuinely is **free to
edit**. But under §0.9 (theater prohibition) and §2.6 (change invariant protocol) a **semantic change** is a
separate review matter.

### §5.2 The semantic conclusion: **making it fail-closed as things stand turns the gate permanently red**

`bin/nimtry` is **absent** at `--validate` time and is **created 2 seconds later** in the same job (§3.5).
So the moment `continue` becomes `inc driftCount`:

- `driftCount >= 1` (`nimtry_violations`, and `layer_violations` / `effect_violations` are equally absent)
- → `hasErrorDisposition = true` (`:1474-1477`)
- → `voErrorDisposition` → `quit(1)` (`:1621-1624`)
- → **the required check `debt-registry-gate` fails on every PR** → the merge queue is blocked entirely

`layer_violations` (`bin/layer_enforcement_gate`) and `effect_violations`
(`bin/effect_contract_projection`) are not built in that job either, so at minimum **3 metrics** go red at
the same time. That is, this change does not make the gate "more accurate" — it **kills the gate**.

§4.4 pinned this causation down by measurement — a single DRIFT produces exactly exit 1.

### §5.3 So the remaining options (not implemented — decision items)

| option | content | cost | risk |
|---|---|---|---|
| **A** | Add the evaluator binaries to `bin/debt_engine`'s prerequisites (`Makefile`) | low (2-second build, toolchain already present) | none — it only moves forward a binary already built inside the job |
| **B** | Move the `--validate` step **after** the `bin/nimtry` build | low (YAML step order) | **edits a trust-surface file** → break-glass lane required |
| **C** | Introduce a "this metric is required" declaration in `--validate` (required/optional per evaluator) | medium | a new contract — §0.12 requires a product-contract basis |
| **D** | Add an escape hatch such as `--allow-unmeasured` to `--validate` | medium | **theater risk** (§0.9) — once used permanently, it disables the gate |

Option A best satisfies §0.2 (Ideal/Elegant/Fundamental): with no new contract and no new flag, it applies
the `| nimtry-measure` pattern that `bin/debt_integrity_gate` **already uses** to `bin/debt_engine` in the
same way. That is "no exceptions", and the provisioning contract becomes one.

**The trap in option B**: the workflow is in the trust-surface manifest, so merely changing step order takes
it out of `admission-check`'s independent verification and requires break-glass. Option A, by contrast,
touches only the `Makefile` (not in the manifest), so it is a **normal lane**. This asymmetry is the decisive
reason to prefer option A.

### §5.4 What the follow-up PR must decide together

1. **Which metrics are required?** All 4 evaluators, or only `nimtry_violations`?
   `import_lint_violations` scans only `tools/`, so it is always measurable in CI — it differs in character
   from the other 3.
2. **Will "unmeasurable" (`-1`) and "actual DRIFT" (`!= ledger`) be reported separately?** The current
   aggregate is a 2-tuple, `N PASS, M DRIFT`, so there is no slot that expresses "unmeasurable". Making it
   fail-closed requires at minimum a third counter (`UNMEASURED`) — otherwise "unmeasurable" is disguised as
   "DRIFT" (the mirror image of this defect).
3. **Will the `--close` path be fixed as well?** `cmdClose` calls `runValidateCore` twice, before and after
   (`:2125`, `:2199`). Once fail-closed, **`--close` becomes impossible** in a checkout without nimtry. The
   impact on the local workflow needs a separate judgement.
4. **Will the DEBT#543 regression test be extended?** `tests/unit/test_debt_engine_sync_budget.nim` covers
   only `--sync-budget`. There is no case pinning the same class in `--validate`.

---

## §6. Reproduction commands (copy-paste)

Via WSL (run from Git Bash):

```bash
wsl.exe -e bash -lc 'cd /home/wintr/develop/Axiom && git worktree add /home/wintr/wt-vsb -b ci/vsb-nimtry-failopen-measurement origin/main'
wsl.exe -e bash -lc 'cd /home/wintr/develop/Axiom && cp bin/ax bin/build_all_gates bin/nim_check_gate /home/wintr/wt-vsb/bin/'
wsl.exe -e bash -lc 'cd /home/wintr/wt-vsb && make bin/debt_engine && make bin/nimtry'

# Reproduction A: remove nimtry
wsl.exe -e bash -lc 'cd /home/wintr/wt-vsb && mv bin/nimtry /tmp/nimtry.saved && ./bin/debt_engine --validate; echo "EXIT=$?"'

# Reproduction B: control
wsl.exe -e bash -lc 'cd /home/wintr/wt-vsb && mv /tmp/nimtry.saved bin/nimtry && ./bin/debt_engine --validate'

# Reproduction D: --sync-budget asymmetry
wsl.exe -e bash -lc 'cd /home/wintr/wt-vsb && mv bin/nimtry /tmp/nimtry.saved && ./bin/debt_engine --sync-budget --dry-run; echo "EXIT=$?"; mv /tmp/nimtry.saved bin/nimtry'

# CI measurement (§3.4, §3.5)
GH="/c/Program Files/GitHub CLI/gh.exe"
"$GH" run view 45553393942 --log | grep -E "Part D:|nimtry_violations|-o:bin/nimtry"
```

---

## §7. Measurement environment and limits

- **Measured SHA**: `57f2067b58560d39236ce34f1e14f45d662652f0` (`origin/main`, 2026-11-25 04:50:37Z).
- **Local binaries**: both `bin/debt_engine` and `bin/nimtry` were built fresh for this measurement.
  The main clone's `bin/nimtry` (1,504,536 bytes, Nov 23) was **not used**.
- **Side artifacts**: `data/nimtry_live_count.json` (gitignore `:422`) was produced by reproduction B.
  It is evidence that `--validate` really did run nimtry, and it is not a commit target.
- **Restoration check**: `data/debt_ledger.json` was restored with `git checkout --` and `git status` is
  clean. `tools/debt_engine.nim` is **unmodified**.
- **Limits**: the CI log sample is a single `merge_group` run (`45553393942`). The code path (§1) and the
  workflow definition (§3.2) are decisive, so a larger sample would not change the verdict. The fact that
  "nimtry is built after `--validate`", however, rests on that run's step order, and the step order is
  fixed in the workflow file, so it is reproducible.

---

## §8. One-line conclusion

`nimtry_violations` is **fail-open (YES)** in the required `debt-registry-gate` — nimtry's absence flows
`-1` sentinel → `continue` → `3 PASS, 0 DRIFT` → **exit 0** and leaves no trace in the verdict.
But `bin/nimtry` is not *structurally absent* from that job — it is **built 2.1 seconds after `--validate`** —
so the fix is not a change that "makes the gate permanently red" but one that **aligns the provisioning
order**: option A, touching only the `Makefile`, is a normal lane, and only once an UNMEASURED disposition is
introduced into `--validate` alongside it does fail-closed actually mean anything.

---

## §9. Re-verification against current `main`

Checked on 2026-11-26 against `origin/main` = `bc6e2edd757679722e9d44bf8392a642c63145d6` (merged
2026-11-25). Nothing measured at `57f2067b` was re-run or altered; this section records only what still
holds and what moved.

- **Finding 1 — the fail-open branch still exists, unchanged in substance.** `tools/debt_engine.nim:1460-1462`
  still reads `if liveValue < 0:` / `echo "  [warn] " & metricName & ": evaluator error"` / `continue`,
  inside `runValidateCore` now at `:1342`. At the measured SHA `57f2067b` this was `:1459-1461` — a pure
  line shift. The `--sync-budget` fail-closed path also still exists (now `:2067-2072`).
- **Finding 2 — the provisioning order still holds, unchanged.** `.github/workflows/debt-registry-gate.yml`
  is byte-identical between `57f2067b` and `bc6e2edd`, so the citations to it in §3.2 and §3.3 remain exact
  line-for-line. It still runs `bin/debt_engine --validate` at step `:48`, and `bin/nimtry` is still produced
  only later, by `Build bidirectional debt binding gate` at step `:54` (`make bin/debt_integrity_gate`, which
  carries `| nimtry-measure` → `bin/nimtry`; now `Makefile:333-335`, was `:292-295`). The §3.5 correction —
  nimtry is built *after* `--validate` — therefore still holds.
- **One cited region did change semantically.** `evalNimtryViolations` gained a `nimtryBaselineProvider()`
  precondition between the two SHAs (issue #462). At `bc6e2edd` the sentinel `-1` has **four** paths, not the
  three enumerated in §2: binary absent (`:1748-1750`), `data/nimtry_baseline.json` absent or not v2-loadable
  (`:1751-1755`), sidecar absent (`:1767-1769`), parse failure (`:1770-1773`). The docstring quoted in §2 was
  revised accordingly (`:1743-1746`). This strengthens rather than weakens the thesis — the new path is
  itself fail-closed on the evaluator side and still lands on the same `-1` → `continue` disposition — but
  §2's "three paths" enumeration and its quoted docstring describe `57f2067b`, not `bc6e2edd`.
- **Line citations throughout are anchored to `57f2067b`.** `tools/debt_engine.nim` and the `Makefile` both
  changed between the two SHAs, so numbers such as `:2031` (`--sync-budget` fail-closed, now `:2067-2072`),
  `:1613` (`cmdValidate`, now `:1614`), `:2125` / `:2199` (`cmdClose` calls, now `:2162` / `:2236`), and
  `Makefile:277-278` (now `:314-318`) resolve at the measured SHA, not at current `main`.