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

The gate is **fail-closed**: absence of proof (missing/empty `axiomsUsed`, rejected axiom)
yields `isValid = false` / `verified = false` / `dvcLeanNotVerified` — never an implicit
success. A legitimate proof must *prove* its honesty by the absence of any banned axiom. The
one narrow exception is the legacy replay behavior of §3.1 (an absent `#print axioms`
section, not a present sorry); capsule flows disable that exception and require the
observation (see §3.2).

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
named). This is a deliberate, narrow **legacy, non-capsule** fail-open: it never admits a
*present* sorry, it only skips the check when the audit trail is absent. A missing section
is itself a red flag (see §6).

**Capsule flows are fail-closed here.** In the evidence capsule contract
([evidence_capsule_contract.md](evidence_capsule_contract.md) §2.1), an absent
`#print axioms` observation is missing evidence: the claim is `UNKNOWN`/`FAIL`, never
`PASS`. This legacy fail-open must not be reused as the capsule rule.

### 3.2 `#print axioms` is an observation; `leanchecker` is the replay step

`#print axioms` is an **observation** of the compiled theorem's dependency list: it is not
itself a proof, and a matching list is not a second kernel check. The capsule
`proofValidity` axis therefore requires both:

1. the `#print axioms` observation matches the canonical primitive allowlist (§4); and
2. `leanchecker <Module>` replays the produced `.olean` through the same Lean kernel in a
   fresh process and accepts the theorem.

Plain `leanchecker` is the **mandatory** gate. `--fresh` (full import-closure replay) is an
**opt-in deep mode**, not a default: on Lean 4.33.0 an `Init`-importing artifact costs
69–98 s and a `Std` artifact ~130 s, exceeding the 120 s re-execution budget and turning
valid artifacts into fail-closed rejections. When the toolchain is digest-pinned, `--fresh`
adds no second trust root; it only re-validates imported oleans that the pin already assumes.

The checker binary must be pinned by path **and** SHA-256. A checker resolved from `PATH` or
an environment override (`AXIOM_LEANCHECKER_CMD`) is not a gate: `/bin/true` satisfies it.

`leanchecker` is not a second, independent kernel. It replays the `.olean` declarations
through the pinned Lean kernel; it is an independent *process* replay, not an independent
*checker implementation*. A checker pass establishes no more than kernel acceptance of the
replayed artifact. Both steps are required by
[evidence_capsule_contract.md](evidence_capsule_contract.md) §2.1; neither replaces the other.

**`#print axioms` is forgeable producer output.** A source comment containing `#print axioms`
suppresses the appender, and `run_cmd` / `#eval` runs at compile time and can print a fake
`does not depend on any axioms` line for a `sorry` proof; a decoy theorem earlier in the file
can absorb the observation. The observation is therefore bound to the explicitly requested
declaration (never “the first theorem/def”), the `.olean` must replay through the kernel, and
`run_cmd` / `#eval` / `debug.skipKernelTC` are rejected in capsule flows. `#print axioms` is
blind to `debug.skipKernelTC`; `leanchecker` is the step that catches it.

## 4. Primitive axiom allowlist

The canonical **primitive** allowlist is exactly three Lean primitives:

| Primitive axiom | Purpose |
|-------|---------|
| `Classical.choice` | Choice / excluded-middle taste |
| `Quot.sound` | Quotient soundness |
| `propext` | Propositional extensionality |

These are the only primitive axioms a legitimate applicable proof (`decide`, `omega`,
recursion via theorems) may depend on. Verified on Lean 4.33.0: the kernel's primitive
axioms are `propext`, `Classical.choice`, `Quot.sound`; any **other** named *axiom* in the
printed list is rejected.

**`funext` is a theorem alias, not a primitive axiom.** On Lean 4.33.0,
`#print axioms funext` prints `[Quot.sound]` — `funext` is a theorem whose dependency is
`Quot.sound`. It is not an allowlist member and must not be accepted by a primitive-axiom
check. If a producer-side list still carries `funext`, label it **"theorem alias, not a
primitive axiom"** and remove it from the primitive-axiom set; accepting it as an axiom is a
classification error. A theorem that uses functional extensionality is admissible through its
actual printed dependency (`Quot.sound`), not through a `funext` spelling.

`sorryAx` / `Lean.sorryAx` are always rejected by exact-name match.

The primitive allowlist is intended to be mirrored in:

- `lean_replay.nim` → `leanBuiltinAxiomAllowlist`
- `certificate_verifier.nim` → `leanCertBuiltinAxiomAllowlist`
- `ax_vacuity_check.lean` → `builtinAxiomAllowlist` (the Lean-side linter)

**Implementation status (docs-only amendment, 2026-11-20)**: the current code mirrors still
carry a four-element array whose fourth entry is `funext`
(`lean_replay.nim:138-139`, `certificate_verifier.nim:25-26`,
`ax_vacuity_check.lean:35-40`). That is a legacy classification: under this contract `funext`
is a theorem alias, not a primitive axiom, and the primitive-axiom check is the three-element
set above. Aligning the code mirrors is a separate code-change phase; this document does not
claim the code has already been changed. Until then, the presence of `funext` in an allowlist
is redundant at best (a theorem's printed dependency is `Quot.sound`) and must not be cited as
evidence for accepting `funext` as a primitive axiom.

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
3. that every printed name is on the **primitive** allowlist (§4); `funext` is not a
   primitive spelling and is not accepted by this check.

Otherwise it returns `dvcLeanNotVerified`.

Z3-based kernel certs (`leanCompilerVerified == false`, non-empty `smtlib2`, e.g.
`clampTimeoutMs`, `proximityScore`) are **untouched** and remain `dvcSuccess` — the branch
is gated on `leanVerified && smtlib2.len == 0`, so they never enter it.

## 6. Registry / Audit Honesty

A consequence of the fail-closed design: an existing pure-Lean kernel cert **without** a
recorded `axiomsUsed` field now fails deep verification. This is intentional — such certs
have no auditable proof-dependency trail and must be re-issued with the field. Regress
only by adding a genuine `axiomsUsed` list, never by weakening the gate.

The same principle governs capsule flows: an absent `#print axioms` observation is not the
legacy §3.1 skip. It is missing evidence, so `proofValidity` is `UNKNOWN`/`FAIL`
([evidence_capsule_contract.md](evidence_capsule_contract.md) §2.1).

## 7. Relation to DEBT#296

DEBT#296 documented `vacuityProven = verified AND source contains "ax_vacuity_check"` —
a substring check that granted vacuity-proof simply by mentioning the linter. Its
remediation shipped the Lean-side `ax_vacuity_check` tactic and fail-closed phases. This
gate extends the same principle to the **replay / compiler / cert** layers: proof
dependencies must be inspected from the compiler's own `#print axioms` output, not inferred
from substring heuristics, and any `sorry` dependency is rejected fail-closed.
