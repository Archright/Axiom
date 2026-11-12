# WP4c Regression Result & Evidence Ladder

**Experiment ID:** act2-wp4c-symbol-syntax-robustness
**Date:** 2026-08-28
**Axiom root:** `.` (HEAD 089251924)
**Subject:** `<workspace>/nim-stew-clean-c75502c` (c75502ceedb5ed2a37b7b5e4744fc71313682859)

**Status:** V2 (crash eliminated) — PASS. V3 (frontier drop) — localized, unfixed (separate WP).

---

## 1. What changed (the only change)

`stopPostfixExportMarker` normalization:
- Fix details in `wp4c-fix.md`.
- The `5/5` existing frontier-target selection suite and the new `9/9` postfix
  export marker matrix pass (verified this WP).

## 2. 8-Stage Evidence Ladder — `getBitsBE`

Command:
```
AXIOM_STATE_DIR=/tmp/wp4c_state bin/ax prove \
  --project <workspace>/nim-stew-clean-c75502c \
  --target 'stew/bitops2.nim::getBitsBE' --limit 1
```
Full log: `wp4c-ladder-getbitsbe.log`

| Stage | Acceptance | Observed | Verdict |
|-------|-----------|----------|---------|
| A1 Discovery | symbol in topology | yes (func + template, both `topologyBoundaryInterface`, droppedFromQueue=false) | PASS |
| A2 Admission (queue) | in verificationQueue | yes (count=2) | PASS |
| A3 Obligation | obligation generated | not reached (symbol excluded from frontier) | **BLOCKED** |
| A4 Planning | planned = 1 | not reached | BLOCKED |
| A5 UAP | request > 0 | not reached | BLOCKED |
| A6 Z3 | solver invocation > 0 | not reached | BLOCKED |
| A7 Lean/KAA | kernel acceptance | not reached | BLOCKED |
| A8 Canonical Result | result produced | not reached for getBitsBE | BLOCKED |

**Previous behavior (WP4-b): crash at/around A4 (planning) by `axiom_engine.nim:719`
range defect.** After the fix the run completes end-to-end (398 lines, exit
without SIGSEGV/RangeDefect), but getBitsBE is excluded from the frontier before
A3. **The crash is eliminated (V2 PASS); the symbol still does not reach
obligation (V3).**

## 3. V3 Localization — exact drop site

Root cause: **duplicate-definition identity collision** — `func getBitsBE`
(subject `stew/bitops2.nim:559`) and `template getBitsBE` (`:599`) share the same
`nodeId = "stew/bitops2.nim::getBitsBE"`.

Chain (all file:line verified against source + live probe):

1. `topology_symbol_scanner.nim:34` — `nodeId = sorterNodeId(modulePath & "::" & functionName)`; same name ⇒ same nodeId for func and template.
2. `topology_engine.nim:37-48` — both added to `nodes` as separate entries; template's `rawCallTargets` includes `getBitsBE` ⇒ `resolveCallTarget` (topology_dependency.nim:23-27) resolves to the func (different idx) ⇒ template `dependencyIds = @["stew/bitops2.nim::getBitsBE"]` (self-reference through the shared nodeId).
3. `verified_frontier.nim:23-25` (`buildNodeIndex`) — `result[nodeId] = idx` in loop; **last writer wins** ⇒ shared nodeId maps to the template (later index).
4. `verified_frontier.nim:84-88` — `nodeIndex.getOrDefault(getBitsBE)` resolves to the **template** node; its `dependencyIds` contains its own nodeId.
5. `verified_frontier.nim:36` (`allDependenciesVerified`) — that self-reference dependency is not in the hydrated `verified` set (empty in cold external run) ⇒ returns false.
6. `verified_frontier.nim:88-89` — `continue` strips getBitsBE from the frontier ⇒ frontier_selection logs "not found in frontier" and falls back to full frontier.

**Exact drop site: `src/core/topology/verified_frontier.nim:88-89`**
(operationally: `allDependenciesVerified` returning false at `:36`).

Frontier selection then falls back to full frontier and ends up running
`stew/base32.nim::decodedLength` which is skipped by theory (tautology) —
the `verified=0/40`, `Error: 5` tail in the log.

## 4. V3 Hypothesis Verdicts

| Hypothesis | Verdict | Evidence |
|-----------|---------|----------|
| H1 not in verificationQueue | REJECTED | queue has getBitsBE count=2 |
| H2 allDependenciesVerified false | **CONFIRMED** | template self-ref dep not in verified set |
| H3 already in verified set | REJECTED | verified set empty |
| H4 kernel-scope gate | REJECTED | external mode passes subjectMode=true; gate skipped (verified_frontier.nim:78-82) |

## 5. Is V3 the WP4-b blocker or new?

**New, distinct blocker.** The WP4-b blocker was external-symbol syntax /
target-selection robustness (the crash fixed in this WP). V3 is a
**dependency-interning / duplicate-definition identity** problem: func+template
collide on one `nodeId`, `buildNodeIndex` collapses them to the template, and the
template's self-referential dependency fails the deps-verified gate. Ownership:
**Axiom semantic / Axiom integration** — the subject legitimately declares a
`func` and a `template` with the same exported name (valid Nim).

## 6. Control — `encodedLength` (zero-drift)

Command: `--target stew/base36.nim::encodedLength --limit 1`
Log: `wp4c-ladder-encodedLength.log`

Observed: exact 1 node match → eligible → `vtSmtNative` → invariant tautological
REJECT → `[1/1] skipped by theory` → `verified=0/40`. Behaviorally identical to
the WP4-b-reported outcome ⇒ the fix does not drift the previously-working
symbol. (No pre-fix self-run digest baseline exists in this experiment, so
self-run zero-drift is established here by fix-blast-radius analysis + this
control; see §7.)

## 7. Phase E — subject immutability & zero-drift

### Subject immutability — PASS
- `git -C nim-stew-clean-c75502c status --porcelain` → only untracked
  `.axiom/` (Axiom runtime cache `git_file_list.json`), **zero tracked changes**.
- `git diff --name-only` / `git diff --cached --name-only` → empty.
- Content fingerprint at HEAD c75502c:
  `9ca3ff08f3c43cc5552cbbb91e143a2ffbfe49c7f597924899d4d5e01259adc3`
- The subject source (`stew/bitops2.nim` etc.) is byte-identical to the pinned
  revision; no subject mutation occurred across the WP4-b/c runs.

### Self-run zero-drift — analytical + control
- The fix alters behavior **only** for a frontier name ending in `*`: it strips
  exactly one trailing char (old code stripped two, and mis-handled lone `"*"`).
  For names without a trailing `*` (the vast majority, incl. all identifier
  symbols) the returned value is unchanged ⇒ no eligibility drift.
- The only names for which old≠new are those ending in `*` where stripping one
  char is the correct canonical normalization (mirrors `ir_pipeline_runner.nim:1122`).
- Control run (§6) reproduces the WP4-b outcome for the previously-working
  symbol, supporting zero-drift.
- **Caveat (stated, not papered over):** no pre-fix self-run digest was captured
  in this experiment, so a strict digest-identical self-run comparison was not
  possible here. The zero-drift claim rests on (a) narrow blast radius and
  (b) the encodedLength control. A dedicated self-run digest comparison is a
  suggested follow-up if digest-level certainty is required.

## 8. Taxonomy Summary

- Fixed/eliminated: **external-symbol syntax / target-selection robustness** crash
  (`axiom_engine.nim:719` slicing) — V2.
- Remaining, localized: **duplicate-definition identity** drop at
  `verified_frontier.nim:88-89` — V3, separate WP.
- No `Verified` reached; no `Verified` claimed.

## 9. Provenance / Artifacts

- `wp4c-fix.md`
- `wp4c-v3-frontier-localization.md`
- `wp4c-ladder-getbitsbe.log`, `wp4c-ladder-encodedLength.log`
- probes: `wp4c_boundary_probe.nim`, `wp4c_topology_probe.nim`,
  `wp4c_frontier_localizer.nim`
- regression suite: `tests/unit/postfix_export_marker_test.nim` (9/9 PASS)

These probe/log files are **experiment-only**, not part of the canonical
execution path, and not a production API.

## 10. Protected invariants — all untouched

`verification_scope.lock`, trust journal, VKD, certificate schema,
`baseline.json`, `config.nims`, `import_encapsulation_gate.nim`, CI, gate,
and nim-stew. **No git commits made.**
