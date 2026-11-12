# Lean Sorry Gate — Fail-Closed Verification

> Status: Implemented (P3a)
> Applies to: `src/core/judge/lean_replay.nim`, `src/verification/lean_lsp_compiler.nim`,
> `src/personas/judge.nim`, `src/verification/certificate_verifier.nim`
> Precedent: [DEBT#296](../DEBT_REGISTRY.md) — `vacuityProven from substring match` was theater;
> this gate closes the remaining gap by making **proof-dependency honesty** a hard gate.

## 1. Problem

Lean 4's kernel accepts a proof that compiles, but a proof may still be **vacuous or
fake** when it silently depends on `sorryAx` (the axiom emitted by the `sorry` placeholder)
or on arbitrary user-defined axioms. Compilation success (`exitCode == 0`) does **not**
guarantee that the proof term is honest.

Previously:

- `runLeanReplay` returned `isValid = true` on any successful compile, ignoring the
  `#print axioms` output it was already collecting.
- `runLeanCompiler` treated `verified = (exitCode == 0)` — a `sorry`-filled proof passed.
- The Judge's Leanstral shortcut hardcoded `leanKernelVerified: true`.
- Pure-Lean kernel certs were deep-verified without recording or checking their axiom
  dependencies.

All four were theater signatures (§0.9): the appearance of verification without its
substance. This gate makes them fail-closed.

## 2. Fail-Closed Sorry Gate

The gate is **fail-closed**: absence of proof (missing axioms section, missing/empty
`axiomsUsed`, rejected axiom) yields `isValid = false` / `verified = false` /
`dvcLeanNotVerified` — never an implicit success. A legitimate proof must *prove* its
honesty by the absence of any banned axiom.

## 3. `#print axioms` Mechanism

`runLeanReplay` already appends a `#print axioms <theoremName>` command to the temporary
Lean source (DEBT#002, "Force `#print axioms` to expose proof dependencies"). On a clean
compile the command emits, on stdout:

```
'my_clean_proof' does not depend on any axioms
```

or, when the proof depends on axioms:

```
'my_sorry_proof' depends on axioms: [sorryAx]
'my_classical_proof' depends on axioms: [propext, Classical.choice, Quot.sound]
```

`parsePrintedAxioms` (in `lean_replay.nim`) parses the bracketed, comma-separated name
list. The section is considered **present** only when a `depends on axioms` line is found.

### 3.1 Only enforce when the section is present

If the compiler output contains **no** `#print axioms` dependency line, the strict
allowlist check is not applied (the command was not emitted, or the theorem could not be
named). This is a deliberate, narrow fail-open: it never admits a *present* sorry, it only
skips the check when the audit trail is absent. A missing section is itself a red flag
(see §6).

## 4. Allowlist

A replay / pure-Lean cert may depend on **only** the following built-in Lean axioms:

| Axiom | Purpose |
|-------|---------|
| `Classical.choice` | Choice / excluded-middle taste |
| `Quot.sound` | Quotient soundness |
| `propext` | Propositional extensionality |
| `funext` | Functional extensionality |

These are the transitive, kernel-provided axioms that legitimate applicable proofs
(`decide`, `omega`, recursion via theorems) depend on — verified empirically against
Lean 4.29 (`#print axioms` output). Any **other** named axiom in the printed list is
rejected.

`sorryAx` / `Lean.sorryAx` are always rejected by exact-name match.

The allowlist is mirrored in:

- `lean_replay.nim` → `leanBuiltinAxiomAllowlist`
- `certificate_verifier.nim` → `leanCertBuiltinAxiomAllowlist`
- `ax_vacuity_check.lean` → `builtinAxiomAllowlist` (the Lean-side linter)

## 5. Enforcement Points

### 5.1 `runLeanReplay` (src/core/judge/lean_replay.nim)

In the `exitCode == 0` success branch, before returning `ok(...)`:

```nim
let (axiomSectionPresent, printedAxioms) = parsePrintedAxioms(output)
let replayIsValid = sorryGateValid(axiomSectionPresent, printedAxioms)
ok(LeanReplayResult(isValid: replayIsValid, ...))
```

The replay still returns `ok(...)` but with `isValid = false` when the sorry gate rejects
— callers that consume `isValid` (notably the Judge) now inherit the fail-closed verdict.

### 5.2 `runLeanCompiler` (src/verification/lean_lsp_compiler.nim)

`verified` requires `exitCode == 0` **and** the combined output to contain none of:
`declaration uses 'sorry'`, `sorryAx`, `Lean.sorryAx` (case-insensitive).

```nim
if exitCode == 0:
  let lowerOutput = combinedOutput.toLowerAscii()
  result.verified = not ("declaration uses 'sorry'" in lowerOutput or
                         "sorryax" in lowerOutput or "lean.sorryax" in lowerOutput)
```

### 5.3 Judge Leanstral shortcut (src/personas/judge.nim)

`leanKernelVerified` is **derived** from `runLeanReplay`'s verdict instead of being
hardcoded:

```nim
let leanKernelVerified = leanReplayResult.get().isValid
```

### 5.4 Pure-Lean kernel cert deep-verification (src/verification/certificate_verifier.nim)

When a kernel cert is verified purely by Lean (`solverMeta.leanCompilerVerified == true`
**and** `smtlib2` empty), `isDeepVerified` now requires:

1. a **recorded, non-empty** `axiomsUsed` array field; and
2. that array contains **no** `sorryAx` / `Lean.sorryAx`; and
3. that every axiom is on the allowlist (§4).

Otherwise it returns `dvcLeanNotVerified`.

Z3-based kernel certs (`leanCompilerVerified == false`, non-empty `smtlib2`, e.g.
`clampTimeoutMs`, `proximityScore`) are **untouched** and remain `dvcSuccess` — the branch
is gated on `leanVerified && smtlib2.len == 0`, so they never enter it.

## 6. Registry / Audit Honesty

A consequence of the fail-closed design: an existing pure-Lean kernel cert **without** a
recorded `axiomsUsed` field now fails deep verification. This is intentional — such certs
have no auditable proof-dependency trail and must be re-issued with the field. Regress
only by adding a genuine `axiomsUsed` list, never by weakening the gate.

## 7. Relation to DEBT#296

DEBT#296 documented `vacuityProven = verified AND source contains "ax_vacuity_check"` —
a substring check that granted vacuity-proof simply by mentioning the linter. Its
remediation shipped the Lean-side `ax_vacuity_check` tactic and fail-closed phases. This
gate extends the same principle to the **replay / compiler / cert** layers: proof
dependencies must be inspected from the compiler's own `#print axioms` output, not inferred
from substring heuristics, and any `sorry` dependency is rejected fail-closed.
