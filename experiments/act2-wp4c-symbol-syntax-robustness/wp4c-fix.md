# WP4c Fix — Generic Postfix Export-Marker Normalization

**Experiment ID:** act2-wp4c-symbol-syntax-robustness
**Date:** 2026-08-28
**Axiom root:** `.` (HEAD 089251924)
**Subject:** `<workspace>/nim-stew-clean-c75502c` (c75502ceedb5ed2a37b7b5e4744fc71313682859)

---

## 1. Question

During WP4-b, running an external symbol whose exported name carries a postfix
`*` export marker (`getBitsBE*`, and specifically a backtick operator like
`` `*`* ``) crashed `axiom_engine.nim` with a range defect. Does a **generic**,
minimal fix to the export-marker stripping logic eliminate the crash without
changing semantics for ordinary identifiers?

## 2. Root Cause (confirmed in WP4-b / WP4-c)

`src/cli/axiom_engine.nim:715-719` (the `isEligible` closure) contained:

```nim
if bare.endsWith("*"):
  bare = bare[0 ..< bare.len - 2]
```

Two defects:

1. **Off-by-one / two-char strip.** A Nim postfix export marker is a *single*
   trailing `*`, so `"name*"` should become `"name"`. The code stripped two
   characters (`bare.len - 2`), producing `"nam"` for `"name*"` — a wrong bare
   name that can yield a registry / target mismatch.
2. **Range defect on `"*"`.** When the symbol name is exactly `"*"` (e.g. the
   multiplication operator `func \`*\`*(...)`), `bare.len == 1` so the slice
   `[0 ..< -1]` is an empty-but-valid range in Nim (not a crash), but for an
   *empty* name the slice `[0 ..< -2]` raises. More importantly the logic tried
   to strip an export marker from a lone operator name that is *not* an export
   marker. The fatal crash observed was the range defect in this path.

Canonical anchoring for the correct semantics already exists elsewhere in the
codebase:

- `src/verification/batch_uap/ir_pipeline_runner.nim:1122`:
  ```nim
  if bareName.len > 1 and bareName[^1] == '*' ... hasKey(bareName[0..^2])
  ```
  Guard on `len > 1` + strip **exactly one** trailing char.

## 3. The Fix (2 files, minimal)

### 3.1 New guarded helper — `src/cli/frontier_selection.nim`

Exported canonical helper (added to `frontier_selection.nim`, `{.raises: [], inline.}`):

```nim
proc stripPostfixExportMarker*(fnName: string): string {.raises: [], inline.} =
  ## Remove a single trailing Nim postfix export marker `*`.
  ## A lone `"*"` (operator name, not a marker) and an empty name are left
  ## unchanged. Mirrors ir_pipeline_runner.nim:1122 (guard + exactly one char).
  if fnName.len > 1 and fnName.endsWith("*"):
    fnName[0 ..^ 2]
  else:
    fnName
```

`[0 ..^ 2]` is the inclusive upper-bound form of `[0 .. len-1]`, safe for
`"name*"` → `"name"`; the `len > 1` guard keeps `"*"` and `""` unchanged and
crash-free.

### 3.2 Use it — `src/cli/axiom_engine.nim:715-719`

Replaced the buggy in-place two-char strip with the guarded helper:

```nim
let bare = stripPostfixExportMarker(fnName)
```

The `runtimeAxiomRegistry` / `materializeExternalIR` matching that follows is
unchanged; only the name-fed into matching is normalized correctly.

**No nim-stew-specific condition, no per-repo special case.** The fix is a
generic robustness correction to postfix export-marker normalization and applies
to every external (and internal) subject.

## 4. Files Changed

| File | Change |
|------|--------|
| `src/cli/frontier_selection.nim` | added `stripPostfixExportMarker*` helper (+ `import infrastructure/logging_facade` where needed) |
| `src/cli/axiom_engine.nim` | `isEligible` uses `stripPostfixExportMarker` |

No changes to: `verification_scope.lock`, trust journal, VKD, certificate schema,
`baseline.json`, `config.nims`, CI, gate, or **nim-stew**.

## 5. Verification

### 5.1 Regression matrix — `tests/unit/postfix_export_marker_test.nim` (9/9 PASS)

| Input | Expected | Result |
|-------|----------|--------|
| `"name"` | unchanged | OK |
| `"name*"` | `"name"` | OK |
| `"name**"` (two markers) | `"name*"` (exactly one removed) | OK |
| `` "`+`*" `` | `"`+`"` (operator only) | OK |
| `` "`*`" `` (operator name, no marker) | unchanged | OK |
| `"*"` lone | unchanged, no crash | OK |
| `""` empty | unchanged, no crash | OK |
| full-frontier eligibility with lone `'*'` | survives, no crash | OK |
| explicitly-targeted `'*'` | unchanged, safely excluded | OK |

### 5.2 Existing suite — `tests/unit/frontier_target_selection_test.nim` (5/5 PASS)

### 5.3 External runs (fixed binary)

- `--target stew/bitops2.nim::getBitsBE` → **crash eliminated (V2)**. Exit was a
  crash (`getBitsBE` operator-syntax path); now completes full 398-line run, no
  SIGSEGV / RangeDefect. Final: `verified=0/40`, target not in frontier (see V3
  localization — distinct blocker).
  Log: `wp4c-ladder-getbitsbe.log`.
- `--target stew/base36.nim::encodedLength` (control) → exact 1 node match,
  eligible, `vtSmtNative`, invariant tautological REJECT, `[1/1] skipped by
  theory`, `verified=0/40` — behaviorally identical to the WP4-b-reported outcome
  (zero-drift for the previously-working symbol).
  Log: `wp4c-ladder-encodedLength.log`.

## 6. Taxonomy

The `getBitsBE` defect fixed here is an **external-symbol syntax / target-selection
robustness** defect (`axiom_engine.nim` slicing). The crash is **eliminated**.

A **separate** blocker (V3) — getBitsBE absent from the frontier — is a
dependency-interning / duplicate-definition identity issue in the topology
layer, localized in `wp4c-v3-frontier-localization.md`. It is **not** fixed by
this change and is out of scope for the syntax-robustness WP.

## 7. No "Verified" Claim

This WP did not reach Z3/Lean/KAA or canonical `Verified`. It establishes only
that exported identifiers and exported operators are handled safely at the
frontier-eligibility boundary after the generic fix. No `Verified` result is
claimed anywhere in this experiment.

## 8. Protected-Invariant Compliance

- `verification_scope.lock`: untouched
- trust journal / VKD / certificate schema / `baseline.json`: untouched
- `config.nims` / CI / gate / `import_encapsulation_gate.nim`: untouched
- nim-stew (subject): immutable, no changes
- git: **no commits made**
