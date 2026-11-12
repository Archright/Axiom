# ACT 2.3 — First External Kernel Proof Attempt: Anchor #1 `getBitsBE`

## Question

Can Axiom drive the single deterministic Anchor #1 — `stew/bitops2.nim::getBitsBE`
from the external subject `nim-stew-clean-c75502c` — from external-source
ingress through obligation generation to kernel acceptance (Z3 → Lean → KAA →
TrustCommit)?

Explicit contract for this attempt: **no anchor switching.** Whatever the result,
it is preserved; the first failing stage is recorded as the next WP boundary.

## Context

- Project under test: `nim-stew` (immutable, `nim-stew-clean-c75502c`)
- Axiom: local repo `.../Axiom`, Nim, default configuration (no contract injection)
- Toolchain: Nim 2.2.10; Z3 4.13.3 (`<user-home>/.local/bin/z3`); Lean 4.29.0
  (`<user-home>/.elan/bin/lean`); LLM API key configured
- Experiment id: `act2-wp4h1-intrinsic-safety` (Anchor #1 proof attempt)
- Anchor: `bitops2::getBitsBE` — intrinsic symbolic division obligation
  `denom = resultBits ≠ 0`, dependency surface 1, `vtStructural`, no postcondition

## Scope

Exactly one target symbol; exactly one run configuration. No contract injection.
No weakening of acceptance criteria, no bypass of sieve/kernel gates.

## Procedure

```sh
export AXIOM_STATE_DIR=/tmp/axanchor/state
bin/ax scope lock          # seed deterministic kernel scope (kernel_total=40)
bin/ax prove --project <workspace>/nim-stew-clean-c75502c \
             --target 'stew/bitops2.nim::getBitsBE' --limit 1
```

Canonical target form `module::function` used to keep the frontier filter based on
exact matches and avoid the full-frontier fallback.

## Result (canonical, machine-observed — full log preserved)

`EXIT=0` (product command completes; result is a classification, not an exception):

| Stage | Success predicate | Observed | Verdict |
|---|---|---|---|
| Discovery | exact 1 match | `--target filter: 1 node(s) match 'stew/bitops2.nim::getBitsBE'` | ✅ |
| Admission | external candidate admitted | `frontier eligibility gate: eligible=1` | ✅ |
| Obligation | ≥1 real obligation | `[TheaterGuard] getBitsBE — obligation generated`; inventory `obligationCount:1`, kind `okSafetyDiv` | ✅ |
| Planning / IR | ≥1 planned node / IR available | `IR extraction — 6/229`; `[ir-cas] MISS func=getBitsBE`; `materialized: moMaterialized` | ✅ (pre-sieved) |
| UAP | request emitted | `Verification-Gate: UAP produced 0 results (requests=1)` | ⚠️ emitted, 0 results |
| Z3 | invocation + valid result | **not reached** — empty SMT script → `solverMethod=smNone` | ❌ |
| Lean | kernel acceptance | not reached | ❌ |
| KAA | accepted evidence | not reached | ❌ |
| Canonical | deterministic result | `status=psSkip provenance=not_verifiable:illFormed` | ✅ (deterministic HardReject) |
| Trust | trustCommit verified | not reached | ❌ |

Final classification: **`erGuardHardReject`** →
`Failed to parse source: Failed to parse Nim source` →
`StructuralAST: rejected (counterexample)`.

Pipeline summary: `Total: 6, Pass: 5, Fail: 0, Skip: 1, Error: 0` — the single
skip is `getBitsBE`. `verifiedRatio=0.0000, verified=0/40`.

## Evidence

- `proof-attempt/getBitsBE_anchor_run.log` — full 60-line product log (this report
  quotes lines 4, 5, 20, 26, 39, 58–59).
- `proof-attempt/manifest.json` — vault manifest (6 entries synced; getBitsBE absent
  from proven set).
- `canonical/anchor.json` — inventory proof the obligation truly generated:
  `obligationCount:1`, `obligationKinds:["okSafetyDiv"]`, `vacuousSignal:false`.

## Classification

`Unsupported` / `ExecutionTerminated` (hard reject) — **not** `Verified`.
Precisely: the obligation was generated and the function classified `vtStructural`,
but the SMT adapter produced an **empty script**, so no Z3/Lean/KAA stage could run.

## Interpretation

This is the first, precisely-localized external-proof capability boundary:

1. **Obligation is real, non-vacuous** (TheaterGuard confirms generation;
   `vacuousSignal:false`). The intrinsic division safety obligation is produced.

2. **SMT adapter yields empty script** for an obligation-only (precondition) target
   with no postcondition. This matches the vacuous guard in the IR→SMT chunk:
   without postconditions the SMT script stays empty, so Z3 is never invoked
   (`smNone`). For an *intrinsic safety* (precondition) goal this means the current
   product cannot turn "division denominator ≠ 0" into an SMT query — **exactly the
   user's §6 forecast: "obligation exists → SMT 생성 불가 → 그게 바로 다음 capability
   WP."**

3. **Structural sieve hard-rejects the function** (`erGuardHardReject`,
   `Failed to parse Nim source`) — `getBitsBE`'s `openArray[byte]`, `HSlice`,
   and `typedesc[SomeUnsignedInt]` signature is not a parseable/AST-representable
   proof candidate in the sieve. This is a second, independent boundary at the
   structural-admission layer, and the reason the target cannot even be
   cross-validated.

These are **capability boundaries**, not hidden bugs and not subject defects.
The category is deliberately kept distinct from a false `Verified` and from a
"the project is broken" claim.

## Non-Conclusions

- No kernel proof was produced; nothing here claims `getBitsBE` is verified.
- The hard reject of the *signature/parsing* is not proof the division obligation
  is unprovable in principle — it is evidence the current external-ingress
  structural sieve cannot yet ingest this symbol shape.
- "5 Pass" refers to Axiom's own kernel symbols incidentally in the same topology
  run; it does **not** mean the external anchor passed.
- The vacuous cross-validation skip (`no postconditions`) is a known interaction,
  not a successful check.

## Attribution Comparison (diagnostic, not an anchor switch)

To localize which boundary actually blocks, a single diagnostic comparison was run
on the rank-2 candidate `stew/base36.nim::decodedLength` (normal `proc`, dep-0,
division denominator a literal `277`). This is an explicit attribution experiment
to separate independent causes — the primary anchor is unchanged. Result differs
sharply:

| factor | `getBitsBE` (anchor) | `base36::decodedLength` (diagnostic) |
|---|---|---|
| classify | `vtStructural` | `vtSmtNative` |
| structural ingest | **`erGuardHardReject` / "Failed to parse Nim source"** | ✅ parses (no reject) |
| SMT script | TheaterGuard: empty | (n/a) |
| verification gate | skip `not_verifiable:illFormed` | **"skipped by theory"** |
| cross-validation | vacuous (no postcondition) | vacuous (no postcondition) |
| verifiedRatio | 0.0000 | 0.0000 |

**Two independent boundaries are now empirically separated:**
1. `getBitsBE` — blocked at the **structural ingress/sieve** (`openArray[byte]`,
   `HSlice`, `typedesc[SomeUnsignedInt]` signature is not parseable by the sieve).
2. `base36::decodedLength` — ingests cleanly as `vtSmtNative` but is **"skipped by
   theory"** and vacuous: with only an intrinsic (precondition) division obligation
   and no postcondition, no Z3 BMC query is produced.

Both confirm the core §6 forecast: an intrinsic safety obligation is generated, but
the product does not yet turn it into an executable SMT/kernel goal. Evidence:
`proof-attempt/decodedLength_attribution_run.log` (Run A), `getBitsBE_anchor_run_B.log`
(determinism: canonical key lines byte-identical to Run A).

## Next Experiment

Immediate boundary to close, one variable at a time:

- **WP boundary candidate A (adapter):** enable an intrinsic-safety SMT goal for a
  division-denominator obligation in the absence of a postcondition — i.e., produce a
  non-empty SMT query whose validity is checked at the obligation site. This is the
  minimal change that would let an intrinsic obligation reach Z3.
- **WP boundary candidate B (ingress):** determine why the structural sieve cannot
  parse `getBitsBE` (`Failed to parse Nim source`) and whether simpler-intrinsic
  anchors (e.g. `base36::decodedLength`, division denom literal but shaped like a
  normal `proc`) clear the sieve — measured as a *comparison*, not an anchor switch
  for this run.

Either result is a valid WP answer. Do not report success until kernel acceptance
is actually observed.
