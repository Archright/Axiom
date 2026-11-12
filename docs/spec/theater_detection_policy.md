# Theater Detection Policy — `check_nim_theater` (Static CI Scanner)

Enforcement tool: `tools/ci/check_nim_theater.nim`, run via `make check-nim-theater`
(equivalently `bin/check_nim_theater --allowlist tools/ci/nim_theater_allowlist.json src/ tests/ tools/`).
Exit code 0 = PASS, 1 = FAIL. This gate is the **formal full-tree theater scanner** for
Nim source under `src/`, `tests/`, and `tools/`.

> **Scope note — other theater enforcement layers (not duplicated here):**
> - `docs/spec/anti_theater_gate.md` — the git-diff **pre-commit** gate
>   (`src/gate/runners/anti_theater_gate.nim`, rules S1/S2/C, added-lines only).
> - `docs/spec/theater_linter.md` — the **compile-time macro** linter
>   (`src/core/audit/theater_linter.nim`, runs during `nim c`).
>
> This document covers only the CI full-tree scanner. The three layers are
> complementary: commit-time diff (anti_theater_gate), compile-time AST macro
> (theater_linter), and full-tree line scan (this scanner).

## 1. The scanner is LINE-BASED, not AST-based

`check_nim_theater` performs **raw line matching**. It reads each file, splits it
into lines, and applies substring/prefix heuristics per rule. It does **not** parse
Nim AST, does not use `parseStmt`, does not resolve symbols, and has no `re`
(regular expression) dependency. Consequences:

- Detection is heuristic, not semantic. A pattern that *looks* like theater is
  flagged even if the compiler would reject or resolve it differently.
- The scanner errs **toward false positives over false negatives** (fail-closed
  posture). Legitimate sites must be explicitly acknowledged (tag or allowlist).
- Claims that the scanner "understands" code structure are incorrect. Any
  analysis relying on semantic understanding must use `theater_linter.nim`
  (compile-time macro) instead.

## 2. Rules (S1–S5)

| Rule | Pattern | Applies to |
| --- | --- | --- |
| S1 | Swallowed failure: `except CatchableError:` + `discard` (same line or next) | all `.nim` |
| S2 | Always-pass: `check true` / `doAssert true` / `assert true` / stub `return true` | all `.nim` |
| S3 | Dead catch: `except:` block whose body is only blank/comment/discard lines | all `.nim` |
| S4 | Critical write discard: `discard <criticalWrite>(...)` | all `.nim` |
| S5 | Unreachable stub: `doAssert false` / `assert false` with "NOT IMPLEMENTED" | `tests/` only |

Critical-write names for S4: `writeFileSafe`, `writeFileOpt`, `writeCertificate`,
`store`, `commit`, `persist`, `appendLog`, `AtomicWrite`, plus `save*` variants
with context (`saveSettings`, `saveConfig`, `saveState`, `saveCertif`, `saveProof`,
`saveData`, `saveCache`).

## 3. Multi-line string literal masking (line-scanner limitation fix)

A pattern that appears **inside a multi-line string literal** (`""" ... """`) is a
string-literal false positive, not theater. Since the scanner is line-based, it
cannot distinguish code from string content by itself.

`scanFile` therefore builds a **string mask** (`buildStringMask`) before running the
rule checkers:

- A `"""` line toggles string state (odd number of non-overlapping `"""` groups
  toggles; a single-line `"""..."""` literal has an even count and does not toggle).
- `"""` inside a `#` comment is **not** a delimiter (line comments are stripped
  before counting).
- Lines lying fully inside a multi-line string are skipped by every rule.
- Delimiter lines themselves are always scanned (conservative: over-detection
  preferred over missed theater).

**Not handled (minimal-change principle):** single-line `"..."` strings are not
masked. A pattern inside a single-line string literal can still false-positive and
must be silenced with a tag or allowlist entry. Escaped quotes (`\"\"\"`) do not
form a `"""` group, so they cannot corrupt the toggle state.

## 4. Allowed conventions (canonical exclusions)

The following are **not** theater and are how legitimately fail-open code is
expressed:

1. **`# axiom:best-effort(<reason>)` comment tag** — the official, documented way
   to declare an *intentional* fail-open (swallowed error, discarded critical
   write, empty catch). The tag must appear on the same line as the pattern or the
   line immediately above it. This is the accepted annotation convention
   (§0.9 fail-open documentation; undocumented fail-open is theater signature #2).
2. **`# fail-closed: silent-by-design(<reason>)` comment tag** — variant used at
   I/O boundaries where silence is by design (cleanup paths, readFile probes).
3. **Intentional `discard` in test code** — tests routinely drop return values in
   setup/teardown (file writes, directory removal, shutdown) because the side
   effect is verified by a *separate assertion* or is best-effort cleanup. This is
   acceptable test isolation, not a disguised stub — provided the test still
   asserts what it claims to verify.
4. **Patterns inside multi-line string literals** — masked as false positives
   (§3). Not real theater.
5. **Compile-time pragmas / metadata** — `{.axiomDebt: ...}`, `{.axiomDecision: ...}`
   pragmas and annotation strings are metadata, not executed logic, and are not
   enforcement targets.

## 5. Allowlist purpose, legitimacy, and risk

`tools/ci/nim_theater_allowlist.json` exists for two reasons:

1. **Grandfathering** — pre-existing patterns from before the S4/S1 rules existed,
   with per-line entries carrying an explicit `reason` and a "new theater still
   gated" note.
2. **Test-scope exception** — historically a whole-directory `tests → S1/S3`
   exception acknowledged the test-isolation convention.

**§0.9 risk:** whole-directory / whole-file `line: 0` exceptions are *blanket
approvals*. They grant that an entire scope is exempt from a rule, so any future
theater entering that scope passes silently — structurally close to a dead gate
or unenforced claim. Policy:

- **Line-level entries (preferred):** a specific `file` + `line` + `rule` that
  grants only that exact line. A new theater on any other line is still caught.
- **Directory-level entries (must carry `rationale`):** only where enumeration is
  infeasible today; each must document its justification and a reduction plan in
  the `rationale` field. See §5.1.
- The **`tests → S1/S3` directory exceptions were removed** (2026-08-05) and
  converted to 29 explicit line-level entries with per-site reasons. New S1/S3
  theater in test code at non-grandfathered lines now fails the gate.

### 5.1 Remaining blanket exceptions

| Entry | Why it remains | Reduction plan |
| --- | --- | --- |
| `src/personas → S1` | legacy persona modules predate the best-effort tag convention | per-line on next personas refactor |
| `src → S3` | documented empty-except I/O boundary convention | enumerate the ~8 grandfathered sites to line entries |
| `tools → S1`, `tools → S3` | tooling code predates the tag convention | per-line on next tooling refactor |

### 5.2 Allowlist JSON schema

```jsonc
{
  "file": "relative/path.nim",   // or directory prefix (blanket exception)
  "line": 0,                      // 0 = whole file/directory for this rule; >0 = exact line
  "rule": "S1",                   // S1..S5
  "reason": "short justification",   // required on every entry
  "rationale": "blanket-exception justification + reduction plan"  // required on line:0 entries
}
```

`rationale` is optional metadata (the loader reads it for documentation; entries
without it are unaffected). Unknown JSON keys are ignored by the loader, so the
schema is forward-compatible.

## 6. How new theater is detected (detection flow)

1. `make check-nim-theater` rebuilds `bin/check_nim_theater` if the scanner source
   changed, then runs it with the allowlist over `src/ tests/ tools/`.
2. Each `.nim` file is read, split into lines, and a string mask is built (§3).
3. Rules S1–S5 run over unmasked lines.
4. Each finding is checked against the allowlist (`isAllowlisted`): a directory
   `line: 0` entry for the rule, or an exact `file`+`line`+`rule` entry, suppresses it.
5. Any remaining finding prints `path:line: [RULE] message`, and the process exits 1.

After the `tests → S1/S3` reduction, a new swallowed failure or empty catch in a
test file **will** be flagged unless it is (a) annotated with
`# axiom:best-effort(reason)` / `# fail-closed: silent-by-design(reason)`, or
(b) explicitly added to the allowlist with a `reason`. This is the intended
fail-closed behavior: silent permission is no longer possible for test code.

## 7. Enforcement boundary

- The scanner is a **guardrail**: it detects the *shape* of theater, not intent.
  An annotated fail-open is accepted because the tag forces an explicit reason
  that is auditable (and, for S4, cross-checked by the Discarded-Write Audit Gate).
- It complements, does not replace, `anti_theater_gate.nim` (commit-time) and
  `theater_linter.nim` (compile-time). All three must stay consistent with AGENTS.md §0.9.
