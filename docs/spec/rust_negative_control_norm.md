# Rust Negative-Control Subject Norm

- **Status**: binding norm for Rust negative-control subjects (`feat/rust-subject-v1`).
- **NORM**: **Negative-control subjects must produce a counterexample confirmable by normal
  execution WITHIN the supported subset.**

A negative control that dies outside the supported subset (`docs/spec/rust_certified_subset.md`)
proves nothing about the pipeline's disproof machinery — it only proves the codec can reject
input. The counterexample must be a real input on which the real subject, compiled and run
normally, really violates the claimed specification.

## 1. The norm is already the established practice (Nim precedents)

| Fixture | What it pins |
|---|---|
| `tests/negative/base36_mutant_subject/stew/base36.nim` | The seeded mutation (removing the `+ 1` rounding increment, `:19-20`) stays IN-SUBSET — mul/div arithmetic only. The mutant lives inside this repo while the real upstream tree stays read-only (`:13-16`), and "the same pipeline that proves the golden pair … must DISPROVE this subject" (`:10-12`). |
| `tests/negative/false_post.nim` | Body identical to the positive subject (`x`, `:14`); ONLY the postcondition is false (`result + 1 == x`, `:12`) and the Lean kernel genuinely rejects it (`:5-7`). The falsity is a real input-level contradiction, not an unsupported construct. |
| `tests/negative/rem_body.nim` | An OUT-OF-DOMAIN claim (negative-dividend `mod` range, `:9-11`) is a SEPARATE fail-closed category — `lean_kernel_rejected`, never `Verified` (`:11-12`). It is an honesty fixture, not a counterexample fixture. |

The three fixtures separate three things this norm keeps separate: an in-subset mutation
(counterexample class), a falsified post over an identical body (the recommended shape), and an
out-of-domain claim (fail-closed — UNKNOWN-class, never reported as a bug).

## 2. Pattern selection for the v1 Rust add subject

Reference positive: `fn add(a: u8, b: u8) -> u8 { a + b }` under the v1 subset
(`u8` width-lift + range preconditions; plain `+` with the discharged no-overflow obligation).

### RECOMMENDED — `false_post` style

Body identical to positive `a + b`, postcondition falsified (the
`tests/negative/false_post.nim` shape). The mutation touches only the claim, so the overflow
profile is IDENTICAL to the positive subject — one `u8` add, the same discharged
no-overflow obligation — and any counterexample the solver produces is in-domain by
construction. Nothing new is added to the exercised subset surface.

### ACCEPTABLE — `a + b + 1` mutant

The u8-differentiating class is `a + b = 255` (256 input pairs): there the real 8-bit add
overflows, and per the Rust Reference that behavior is not language-fixed
(`docs/spec/rust_certified_subset.md` §3). In Axiom's encoding this class never reaches the
solver:

- inputs lift to BV64 and the range preconditions enter as `(assert …)`, so the solver model
  contains only in-domain points — out-of-domain overflow cannot enter the model;
- the signed 64-bit `no_overflow_add` / `no_underflow_add` goals
  (`src/core/trusted/private/ir_to_smt_chunk3.nim:33-34`, emitted `:51`) discharge trivially
  since `(a+b)+1 ≤ 256 ≪ 2^63`.

The mutant therefore dies from a clean IN-DOMAIN post violation at `(0, 0)`:
`add(0,0) = 1 ≠ 0` — reproducible by real Rust execution under any build profile, since no
overflow occurs at that input. The counterexample does not depend on the implementation
discretion the semanticCaveats describes.

### NOT RECOMMENDED

- **Choice A — `if a == 0 && b == 0 { 1 } else { a + b }`.** Expressible today (`irIf` at
  `src/core/trusted/axiom_ir.nim:72`; `boEq`/`boAnd` in `BinOpKind`, `:50-52`; `Certified`
  `eq`/`and_`/`ite` at `proofs/IR/Denotation.lean:137-138,:141`) but it adds a control-flow
  dependency to the negative subject for no gain — the falsity is already total without it.
  Subset surface stays minimal.
- **Choice B — narrow the precondition (`a + b + 1 < 256`)**. Shrinks assurance by deleting
  the 256 legitimate domain points `a + b = 255` from the claimed domain. A negative control
  must not purchase its counterexample by amputating the positive domain.

## 3. Acceptance — 3-way split

| Class | Gate |
|---|---|
| positive | proof succeeds + KAA — `KernelAcceptanceAttestation`, the only kernel-acceptance authority (`src/verification/obligation/kernel_acceptance_authority.nim:7-18`; unique path: actual canonical Lean execution → opaque receipt → `bindReceipt` → KAA; fake records/models/Z3 evidence cannot produce one, `:13-18`) |
| negative | CONCRETE counterexample reproducible by real Rust execution. `sat` alone must NOT issue PROPOSITION_DISPROVED — the existing fail-closed gate at `src/verification/batch_uap/ir_pipeline_runner.nim:1450-1458` must be honored: replay disagreement/unavailability demotes the disproof to `cvUnresolved` (`makeInconclusive`, `:1452`), carrying the model but no PROPOSITION_DISPROVED payload; the payload fires only on a P4-promoted disproof WITH a concrete solver model AND replay agreement (`:1439-1449`; PROPOSITION_DISPROVED quartet per `docs/spec/bug_verdict_glossary.md:39-49`) |
| out-of-scope | UNKNOWN (fail-closed) — never a verdict, never a bug |

The Rust replay adapter must satisfy the same authority rule the Nim gate already fixes: the
replay execution is the confirming observer of the model, never a promotion authority by
itself; any disagreement or unavailability is fail-closed demotion.

## References

- `tests/negative/base36_mutant_subject/stew/base36.nim:10-16,:19-20` — in-subset mutation
  precedent
- `tests/negative/false_post.nim:5-7,:12,:14` — identical body, false post (recommended shape)
- `tests/negative/rem_body.nim:9-12` — out-of-domain claim as a separate fail-closed category
- `src/core/trusted/private/ir_to_smt_chunk3.nim:33-34,:51` — signed 64-bit
  `no_overflow_add`/`no_underflow_add` goals
- `src/core/trusted/axiom_ir.nim:50-52,:72` — `boEq`/`boAnd`; `irIf`
- `proofs/IR/Denotation.lean:124-141` — `Certified` forms incl. `eq`/`and_`/`ite`
- `src/verification/batch_uap/ir_pipeline_runner.nim:1439-1458` — P4-promoted disproof + replay
  agreement gate; fail-closed `cvUnresolved` demotion
- `docs/spec/bug_verdict_glossary.md:39-49,78-82` — PROPOSITION_DISPROVED definition + shared quartet
  (fail-closed)
- `src/verification/obligation/kernel_acceptance_authority.nim:7-18,:56` — KAA unique-path
  authority
- `docs/spec/rust_certified_subset.md` — supported subset the counterexample must stay within
- `docs/adr/0030-rust-subject-semantic-authority.md` — authority and evidence-ceiling context
