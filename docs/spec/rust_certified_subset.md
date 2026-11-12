# Rust Certified Subset — v1 scope declaration

- **Status**: binding scope declaration for the Rust subject workstream
  (`feat/rust-subject-v1`; §4 adds the `feat/rust-guard-obligation-attempts`
  NON-CERTIFYING guard-obligation attempts — a reporting discipline, not a scope
  extension; `chore/rust-lane-hardening-2026-10-19` adds the §3/§4 replay-confirmed
  observation class — evidence-precise `unknown` reasons, no verdict-space change;
  **v1.4** (`feat/rust-escape-slice`) adds the §1 bool-expression subset — `bool`
  parameters/returns, `Eq`/`Lt`/`And`/`Or`, the measured `Switch` collapse, Bool as
  the Int 0/1 embed `ite(prop,1,0)`, and `rust_ast_wire` version 3).
  Referenced as the Rust scope SSOT by
  `docs/spec/productization_contract.md:11,:15` (§1) and
  `docs/spec/provenance_contract_v3.md:164` (`subjectLanguage: "rust"`).
- **Authority**: rustc (ADR-0030 D1 — `docs/adr/0030-rust-subject-semantic-authority.md`).
  Axiom is a consumer; it does not reimplement Rust semantics.
- **Claim discipline**: this document declares a SCOPE. It is not a capability claim, and it
  does not assert Rust support beyond the rows below.

## 1. v1 subset

| Operation | v1 policy |
|---|---|
| `u8`, `u32`, `bool` | allowed **subject to width representation** (Axiom IR is `irtBitVec64` only — see `src/core/trusted/axiom_ir_types.nim:17`; use width-uniform Int-domain specs with range preconditions) |
| `bool` expressions (**v1.4** — `feat/rust-escape-slice`) | `bool` parameters/returns ADMITTED; binary forms `Eq`, `Lt`, `And`, `Or` (`rwcBinOpEq=1`/`Lt=2`/`And=3`/`Or=4` — `src/verification/rust_ast_wire.nim:128-131`); `if`/`&&`/`||` ADMITTED only through the measured `Switch` collapse (`src/verification/llbc_to_canonical.nim:1066-1100,:1410`); Bool has no IR sort of its own — it is embedded as the Int value `ite(prop,1,0)` (`proofs/IR/RustReferenceExtractor.lean:450-452,:603-610`; `src/cli/rust_lane_cli.nim:177-195`); `rust_ast_wire` version 3 adds tags `rwExpr=0x24`/`rwExprOperand=0x25`/`rwExprBinaryOp=0x26`/`rwExprIte=0x27` (`src/verification/rust_ast_wire.nim:112-116`, version `3` at `:95`). Honest limit: ONLY the measured `Switch` shapes collapse; every other `Switch`/control-flow shape still fails closed (detail below) |
| `u64` (usize on the pinned x86_64 target) | **v1.2 — boundary + discharged-obligation `+`** (`work/u64-add-2026-11-02`): params/returns/constant values of width 64 are ADMITTED over the FULL domain `[0, 2^64−1]` — the IR literal representation is an explicit TWO-PART form: `IRExpr.litVal: int64` keeps the signed domain `[−2^63, 2^63−1]` (canonical signed reading — `src/core/trusted/axiom_ir.nim:90`) and the `irLit` node gains a separate u64-domain representation for `[2^63, 2^64−1]`; a value ≥ 2^63 lives ONLY in the u64-domain representation, never reinterpreted into `litVal`. Wire: the IR binary codec adds tag `0x0F` = `irLitU64` (8 bytes little-endian, direct) and invalidates the legacy `0x01` tag whenever the value's high bit would be set; `rust_ast_wire` moves version 1→2 with an 8-byte domain code (0=signed, 1=unsigned) — old decoders fail closed on both the Nim and the Lean sides. plain `+` on width-64 operands is ADMITTED where the no-overflow obligation is discharged — stated in the equivalent form `lhs+rhs ≤ 18446744073709551615` (≡ `lhs+rhs < 2^64`), discharged through the same obligation channel as u8/u32 and encoded soundly as the 65-bit zero-extend + unsigned `bvule` comparison of the §4 note (admission clause on the plain `+` row below). The discharge's extraction witness (`AddChecked` + `Assert{Overflow}`) holds under the DEFAULT charon flags and the default dev build profile (`charon cargo` builds like `cargo build` — overflow-checks on); release-profile `+` and `wrapping_*` share the `Add(Wrap)` encoding and are INDISTINGUISHABLE, so neither is admitted (rows below). Overflow-REACHABLE inputs remain out-of-subset per §3 (build-profile discretion — unchanged by this row) |
| plain `+` | allowed only where the overflow obligation is discharged (`spOverflowObligationDischarged` — see `docs/spec/semantic_profile_verified_semantics.md:54-56`). On width-64 operands ADMITTED under the same discharge requirement (v1.2 — `work/u64-add-2026-11-02`; u8/u32 policy unchanged): the obligation is stated in the equivalent form `lhs+rhs ≤ 18446744073709551615` (≡ `lhs+rhs < 2^64`) and encoded soundly as a 65-bit zero-extend + unsigned `bvule` comparison against width-accurate constants (`src/core/trusted/private/ir_to_smt_chunk3.nim` — §4 note). The honest limit is unchanged — NO sound BV64-native substitute exists (a wrapped `boAdd` cannot witness the mathematical overflow; `boLe(boAdd(l,r),2^64−1)` passes on wrapped sums — unsound); the 65-bit zero-extend encoding IS the sound substitute. Wraparound/checked semantics for u64 (the `boRem` path per below) remain the declared follow-up — IR literal-domain widening has landed in v1.2, removing the int64-domain wall; the producer's named width-64 wall rejection reason (`src/verification/llbc_to_canonical.nim` — "…unrepresentable in the IR literal domain (int64)…") is PRESERVED in the source for regression tracking, but the width-64 path no longer emits it |
| `wrapping_add` | EXCLUDED from v1 — exclusion reason (v1.2, `work/u64-add-2026-11-02`) is ENCODING INDISTINGUISHABILITY + scope choice, NOT implementability: the extraction witness for checked `+` is `AddChecked` under the DEFAULT charon flags (default dev build profile — overflow-checks on), while release-profile `+` and `wrapping_*` share the `Add(Wrap)` encoding and are INDISTINGUISHABLE — therefore neither is admitted. The `boRem` wraparound path remains feasible (see below — scope choice, not an open impossibility) |
| `checked_add` | EXCLUDED until Result/Option return semantics are modeled (Lean `Certified` has no variant — `proofs/IR/Denotation.lean:124-141`) |
| unsupported arithmetic/flow | UNKNOWN / fail-closed |

**v1.4 collapse rules and honest limit (`feat/rust-escape-slice`).** The
measured `Switch` shape admits exactly ONE bool pattern per `Switch` (the
fallback is the other side) and normalizes `ite(cond,true,e) → or(cond,e)`,
`ite(cond,e,false) → and(cond,e)`, `ite(cond,true,false) → cond`
(`iteNormalize` — `src/verification/llbc_to_canonical.nim:1132-1143`). The
`not`-needing shape `ite(cond,false,true)`, integer/enum patterns, a `Switch`
with more than one pattern, `Panic` or any other statement kind inside a
collapsed branch, a `Switch` after a return-place assignment, and a return
place assigned before a non-nil continuation all fail closed
(`src/verification/llbc_to_canonical.nim:1078-1098,:1303-1394`). Measured real
subject (serde_json v1.0.154, charon 0.1.281): `serde_json::read::is_escape`
verified — canonical `or(eq(ch,34), or(eq(ch,92), and(inc, lt(ch,32))))`, IR
`ite(or(...),1,0)`, wire 776 B, INV-4 `eaAgree` digest
`39dacdaedb5f19cd96fdcd989256bb00878bf6f5ba3eb25d5e78f136ebdb0f7c` (recorded as
`irHash` — `experiments/serde-json-escape-slice-2026-11/runs/run1/cert_is_escape.json`);
`is_zero` = `and(eq(a,0), eq(b,0))`, digest
`7a911fce690198b5e0d9522d310bcd30a128ba45b34001ddc9c6f74ae2267013`. The
spec-side grammar (`||`, `&&`, `<`, `==`, `+`, parentheses, `true`/`false`,
non-negative integer literals) types bool explicitly (`sort` + `isProp`), so
`result == (bool expr)` lowers to `irEq(result, ite(prop,1,0))` — the same
embed the body derivation uses (`src/cli/rust_lane_cli.nim:177-195,:373-380`).
The issued certificate's `leanProposition` carries the Bool-as-Int result
directly: `∀ (ch : Int) (including_control_characters : Int), ((0 ≤ ch) ∧ (ch < 256)) →
((0 ≤ including_control_characters) ∧ (including_control_characters < 2)) →
((is_escape ch including_control_characters) = (if (((ch = 34) ∨ (ch = 92)) ∨
((including_control_characters = 1) ∧ (ch < 32))) then 1 else 0))`
(`cert_is_escape.json`).

**Width precondition — TWO conditions with DIFFERENT sources; do not conflate.**
Axiom IR has a single machine-integer representation, `irtBitVec64`
("Machine integer (64-bit, NOT mathematical Int)" — `src/core/trusted/axiom_ir_types.nim:17`).
Subjects of width 8/32 are lifted to BV64, and the subject-width domain is restored by
range preconditions — specs must be stated width-uniformly over the Int domain with those
preconditions, never as claims about 8/32-bit wraparound. The two conditions are:

1. **Type-derived range — `0 ≤ a,b < 256` (for `u8`; `u32`: `0 ≤ v ≤ 2^32−1`).**
   Origin: `aoTypeDerived` (`AssumptionOrigin`, `src/verification/obligation/obligation_types.nim`).
   This is derived MECHANICALLY from the SOURCE-LANGUAGE TYPE's value range. It is NOT
   re-derivable inside Axiom: `IRType` has no `u8` (only `irtBitVec64/Bool/List/String/Enum`
   — `src/core/trusted/axiom_ir.nim:713-752`), so the derivation source (the Rust type) must
   be RECORDED explicitly via the obligation's origin discriminator. The obligation identity
   includes it (`computeObligationId` payload — an assumption changing origin changes the
   obligation identity).
2. **Caller overflow obligation — `a + b < 256`.**
   Origin: `aoCallerObligation`. This is a SEPARATE precondition / caller duty that discharges
   the overflow condition of plain `+` (v1 admits `+` only where this obligation is
   discharged — §3; inputs outside it are out of subset). It is lowered through the existing
   overflow channel (`annotateOverflow` `src/core/trusted/ast_to_ir.nim:1488-1503` →
   `collectOverflowGoals` `src/core/trusted/private/ir_to_smt_chunk3.nim:213-216` → conjunct
   in the negated query), not through the type-range channel. Conflating it with (1) would
   launder a caller duty into a type fact: a type range says nothing about the SUM.

**Width-64 domain precondition — full range (v1.2, `work/u64-add-2026-11-02`).** The
renderer's width-64 type-derived precondition moves from LOWER-BOUND-ONLY (the v1.1
boundary admission, where `2^64−1` was unrepresentable in the int64 IR literal domain)
to the FULL range `0 ≤ x ≤ 2^64−1`. The renderer and its documented twin change
identically: `src/verification/rust_obligation_render.nim` and
`src/verification/rust_extraction_agreement.nim`. Certificates issued under the v1.1
boundary row remain valid AS ISSUED (issued under the then-current contract);
re-issuance renders the full-range theorem — the width-64 claim is the subject domain
itself, not a stronger quantification.

**Reporting a discharge gap (conditional guarantee).** The verdict space is closed
(`ProofTerminal` — `src/verification/obligation/obligation_types.nim`); no conditional verdict
value exists or is added. Where a proposition holds only under assumptions that were ASSUMED
rather than discharged, the outcome carries it as report metadata:
`ObligationOutcome.conditionalGuarantee` + `ObligationOutcome.undischargedAssumptions`
(set via `withConditionalGuarantee`). An undischarged `a + b < 256` therefore reports as
"NOT verified, conditional on [a + b < 256]" instead of an unlabeled failure — the
conditionality is visible without widening the verdict space.

**This is a SCOPE CHOICE, not an implementability claim.** `wrapping_add` is not declared
unimplementable: the `boRem(boAdd(a,b),256)` path is feasible today — `boAdd`
(`src/core/trusted/axiom_ir.nim:33`) and `boRem` (`:37`) are both certified forms
(`proofs/IR/Denotation.lean:127,:131`), so the u8 wraparound is expressible as a remainder by
256 over the range-restricted domain. The `boRemU` alternative
(`src/core/trusted/axiom_ir.nim:38`) needs renderer/Certified extension first — it has no
`Certified` variant (`proofs/IR/Denotation.lean:124-141`). v1 excludes wrapping arithmetic to
land a minimal coherent slice; inclusion is a follow-up extension, not an open impossibility.

## 2. Declaration mechanism — three layers, mirroring the Nim case

1. **Fail-closed codec boundary.** Nim precedent: `src/verification/ast_wire.nim` serializes
   only the supported kinds (wire-kind table, `:18-58`) and returns `aweUnsupported`
   (`aweUnsupportedKind`, `:79-83`) for every other kind — including the lossy shapes the
   canonical extractor itself degrades (`:60-68`, `:379-380`) — so "an unsupported node aborts
   the differential" instead of being silently wired. The Rust path MUST carry the equivalent
   boundary: a codec that fails closed on every kind/operation outside §1, recording the
   offending kind, never guessing. **Implemented (feat/rust-subject-v1) — the declaration
   mechanism's implementation site is these four artifacts:**
   - `src/core/trusted/rust_canonical.nim` — the shared canonical (`RustCanonical`), a NEW
     artifact class (neither CanonNode nor LLBC): closed v1 grammar MEASURED on the real
     charon 0.1.281 probe (`axiom_rust_probe`: `add_u8`, `add_u8_mutant`, `is_zero`) —
     straight-line statements `StorageLive` / `StorageDead` / `Assign` / `Return` / `Panic`,
     rvalues `Use` / `BinaryOp` (top-level forms `AddChecked` and `Eq` ONLY — plain `+` is
     `AddChecked` in the measured lowering) / `Expr` (v1.4 — the collapsed bool-expression
     tree, whose nested forms are `Eq`/`Lt`/`And`/`Or`),
     operands `Copy` / `Move` / `Const` (the measured serializer
     spelling of the constant operand). The measured lowering of overflow-checked `+` also
     emits an `Assert` (overflow-flag check with `on_failure: Panic`): it is admitted ONLY as
     the middle step of the `AddChecked` collapse performed by the producer
     (`llbc_to_canonical.nim` — tuple assign → assert → Field-0 extraction becomes ONE
     `rrvAddChecked` statement plus the `failureMode` tool-layer fact), NEVER standalone.
     Every other node kind is REJECTED fail-closed — with the v1.4 exception that
     `Switch` is collapsed for the measured bool-expression shapes (`is_zero`'s
     `a == 0 && b == 0` becomes `and(eq(a,0), eq(b,0))`; `is_escape`'s disjunction
     becomes `or(eq(ch,34), or(eq(ch,92), and(inc, lt(ch,32))))`), while every other
     `Switch`/control-flow shape remains out of subset (§1 v1.4 honest limit);
     measured rejections still include `SwitchInt`, `Call`, `Loop`; so are signed/wider integer types,
     generic/unsafe/variadic/non-Rust-ABI declarations and `has_errors` extractions.
     explicit `widthBits` + `signedness` on integer types (accepted set: int/8/unsigned,
     int/32/unsigned, bool/1/unsigned — nothing else validates); an explicit operation-form tag
     (`rrvAddChecked` vs `rrvBinaryOp`); a `failureMode` field that is a TOOL-LAYER observation
     (rustc/Charon, this build profile — ADR-0030 D2, `fsObserved` cap), NOT a program-meaning
     claim; module path + source identity + function/param identifiers and types.
     `validateRustCanonical` rejects every shape outside the closed set.
   - `src/verification/rust_ast_wire.nim` — the fail-closed wire codec (serializer AND
     deserializer, round-trip complete): unknown node tag / out-of-domain enum code →
     `rweUnsupportedKind`; type outside the closed set → `rweUnsupportedType`; bounds/count/
     trailing-byte violations → `rweMalformed` — rejected, never skipped.
   - `src/verification/rust_extraction_agreement.nim` — the INV-4 dual derivation over the
     shared canonical/wire (shared input allowed, per the Nim-path precedent): leg 1 =
     `rustCanonicalToIr` (Nim derivation of Axiom IR), leg 2 = the same wire decoded by
     `proofs/IR/RustReferenceExtractor.lean`. It REUSES the existing `ea*` verdict vocabulary
     (no new enum/gate/authority); `eaAgree` requires byte-equal serialized IR — anything
     else is fail-closed, no seal.
   - `proofs/IR/RustReferenceExtractor.lean` — the independent Lean reference extractor
     (hand-written from `IR/AxiomIRExpr.lean` with its OWN wire decoder and IR encoder,
     INV-4 independence header mirroring `proofs/IR/ReferenceExtractor.lean:5-26`; not a
     lean4lean-style derivation).
   `src/verification/llbc_to_canonical.nim` — the rustc→LLBC→canonical PRODUCER (IMPLEMENTED,
   feat/rust-subject-v1): parses the real charon 0.1.281 LLBC JSON (probe `axiom_rust_probe`),
   resolves document-order type/constant interning, collapses the measured checked-add lowering
   (tuple Assign → overflow Assert with on_failure Panic → Field-0 extraction) into ONE
   `rrvAddChecked` statement plus the `failureMode` tool-layer fact, and rejects everything
   outside the closed grammar with a naming reason (`rceUnsupportedGrammar` → `eaUnsupported`
   downstream / `rceMalformed` for structural violations) — nothing silently dropped
   (`llbcAllToCanonical` reports every declaration). Tests:
   `tests/unit/test_llbc_to_canonical.nim`.
   **Target addressing update (2026-11-02, `work/impl-identity-2026-11-02`) — the
   DEBT#510 closure.** The producer's target resolution is now
   structured-name-first: `llbcFunctionToCanonical` binds the decl whose
   STRUCTURED name (`llbcFunDeclNamePaths` — the enumeration SSOT consumed by
   the lane CLI) equals the requested name EXACTLY; a bare last-segment name
   selects a decl ONLY when exactly ONE fun_decl in the document carries it,
   and TWO OR MORE is an explicit `rceMalformed` Ambiguous rejection that
   names every candidate — the first document-order last-segment match is
   never taken silently (the lane's execution no longer re-derives a bare
   last segment either: the selected candidate's structured name flows
   verbatim into `rustSubjectOutcome` / `rustGuardObligationAttempt` /
   `rustSubjectIssuance`). Inherent-impl methods are ADDRESSABLE: the
   measured `Impl{Ty{kind:"InherentImplBlock", skip_binder:<type ref>}}` name
   path element resolves its owner through the dedicated `item_names` owner
   map (Q11 — the general intern table conflates trait-space and layout ids)
   into the owner's nominal Adt path, so the structured name is
   `<owner nominal path>::<method>` (measured:
   `axiom_impl_probe::m1::Dog::speak`, fixture
   `tests/fixtures/rust/axiom_impl_probe/`); the CANONICAL keeps the decl's
   measured module (`modulePath`) and method name — the owner is the match
   key's disambiguator, not a new canonical field. Honest limits, fail-closed:
   trait impl blocks (any non-`InherentImplBlock` kind), impl elements
   outside the measured penultimate position, and scalar/primitive owners
   (`core::num::<impl u8>::…` — no nominal path) are UNADDRESSABLE by
   structured name (enumeration skips them; no invented spelling), and their
   bodies remain out-of-subset regardless (an `&self` method first fails the
   monomorphic gate on its anonymous region generic — the first measured
   honest reason — before param decoding names `Ref`; `Adt`/`Call` rejections
   unchanged — semantic admission is the ③ follow-up, not this slice).
   **Status update (2026-10-14, `feat/rust-lane-live-cli`)** — the LIVE WIRING now exists:
   `ax prove --project <cargo-root>` branches to the Rust lane (`src/cli/rust_lane_cli.nim`),
   which runs the PINNED charon (`src/verification/charon_runner.nim` — identity gate
   `charon version` ↔ `PinnedCharonPinCommit`/`PinnedCharonVersion`, fail-closed `cr*`),
   re-extracts LLBC every run (the committed fixture LLBC is test-only input, never a CLI
   substitute), and drives `rustSubjectIssuance` unchanged; a live run has minted a real v3
   certificate for `add_u8` with the ExtractionJobRecord landed in the EvidenceCas ledger.
   The first in-repo fixture is committed (`tests/fixtures/rust/axiom_rust_probe/` — crate
   byte-identical to the measured probe, LLBC regenerated byte-identical 3×, regeneration
   command recorded in its README), and `vks_rust` declares 2 targets (below). The
   `AxiomTrustBoundary` rows (`src/core/trusted/trust_boundary.nim:80-91`) remain
   `exists: false` — the register flip is the §10.7 axis-3 human-approval step, NOT an
   automatic consequence of the live run.
2. **Scope lock — `vks_rust`.** The Nim kernel universe is machine-declared in
   `data/verification_scope.lock` (schema v3: `kernel_symbols` / `kernel_exempt_symbols` /
   `vksTotal`). The Rust counterpart `vks_rust` declares the Rust scope denominator under the
   same discipline; no Rust claim may cite a denominator that no lock declares. It is now
   DECLARED in the same lock, additively (schema stays v3 — consumers ignore unknown keys):
   `rust_targets` (array of objects, each with `commit` (40/64-char lowercase hex
   commit-or-tree), `module`, `symbol`, `signatureHash` (sha256 hex), `specRef` (non-empty),
   `conditions` (non-empty string array)) and `vksRust` (integer). Enforcement
   (`src/core/trusted/axiom_pragmas_procs.nim` `validateRustScopeSection` /
   `buildRustScopeJson`; `src/cli/scope_cli.nim`):
   - every `rust_targets` entry must be present and well-formed; a missing `specRef`,
     malformed `commit`/`signatureHash`, or a duplicate `(module, symbol)` pair fails closed;
   - the DECLARED `vksRust` integer is cross-checked against the count derived from the
     entries themselves (two independently derived values — not a tautology); a mismatch
     fails closed (lock regeneration refused, consistency check FAIL);
   - `vks_rust` is NOT added to the Nim `vksTotal` (`docs/spec/verification_density.md:168-169`)
     — the two denominators stay separate, and the Nim `vksTotal == kernelTotal − exempt`
     invariant is untouched;
   - until Rust targets are declared the lock honestly carries `rust_targets: []`,
     `vksRust: 0` (an empty denominator machine-checks "no Rust claims").
   **Re-attestation (decided): ACCEPTED, no epoch field.** `computeScopeHash`
   (`src/cli/scope_cli.nim`) includes the lock bytes, so previously recorded scopeDigests
   break with this schema extension and every consumer re-attests via the normal
   `ax scope lock` → attestation flow. A separate epoch marker was rejected: the lock bytes
   are already the freshness channel inside `computeScopeHash`, and a second epoch field
   would duplicate that semantic state.
3. **Contract prose.** `docs/spec/productization_contract.md` §1 names "(ii) 선언된 Rust
   certified subset ([docs/spec/rust_certified_subset.md] 선언 범위 한정 — 전체 Rust 지원
   주장이 아니다)" (`:11`, `:15`) — the declared subset is contract surface; everything else
   is a non-claim. `docs/spec/provenance_contract_v3.md:36,:164` carries the matching
   certificate field (`subjectLanguage: "rust"`, schemaVersion bump required).

## 3. semanticCaveats

**Rust integer overflow behavior is NOT fixed by Rust semantics** (debug=panic, release=wrap
at implementation discretion — see The Rust Reference,
[Behavior not considered unsafe — Integer overflow](https://doc.rust-lang.org/reference/behavior-not-considered-unsafe.html):
debug-assertion builds must insert dynamic checks that panic on overflow; other builds "may
result in panics or silently wrapped values on overflow, at the implementation's discretion",
with wrapping builds following two's complement conventions). Which behavior a given binary
exhibits on an overflow is a build-profile choice, not a language constant.

**Consequence — inputs that overflow are OUTSIDE the v1 subset: their semantics are not
determined.** The v1 policy therefore admits plain `+` only under the discharged no-overflow
obligation (`docs/spec/semantic_profile_verified_semantics.md:54-56`): overflow reachability
is excluded in the verified domain, and neither checked-panic nor wrap is claimed beyond it.
This is the same coincidence-domain discipline already applied to Nim division/modulo
(`docs/spec/semantic_profile_verified_semantics.md:10-16`) — claim exactly the domain where
semantics are determined and verified; fail closed outside it.

**Observation, not semantics (§4 confirmed class).** The replay-confirmed guard-violation
observation class declared in §4 is a PROFILE-BOUND observation of the real subject under
the RECORDED overflow-checking profile: it records what that checked build did on that
input, not a determination of language semantics — which behavior an overflow produces
remains a build-profile choice (above). The out-of-subset status of overflow-reaching
inputs per this §3 is preserved unchanged; a confirmed observation never widens the
verified domain and never converts overflow inputs into determined semantics.

## 4. Declaration-free guard-obligation attempts (non-certifying)

**Scope.** For symbols NOT declared in `rust_targets`,
the lane may attempt mechanically-derived guard obligations (per `AddChecked` node:
`lhs + rhs < 2^width` over the type-derived ranges — §1 condition (1)). This section declares
a REPORTING DISCIPLINE, not a claim: it is not a capability claim and does not assert Rust
support beyond the rows of §1 (mirroring the header's claim discipline).

**Status principle (binding): `verified` remains contractually bound to certificate
issuance.** The contract rows are untouched — `docs/spec/productization_contract.md:20` (§1
"Verification semantics": the `verified` family is produced only by the fixed rules) and R2
(`:48,:50` — a vacuous `verified` is FAIL). The lane emits `verified` only with `certPath` +
`irHash` (`src/cli/rust_lane_cli.nim:649-652`). A proven guard obligation for an UNDECLARED
symbol is therefore NEVER reported as `verified`: it reports status `unknown` with the
obligation-layer fact in the reason string — "guard obligation discharged (proved: …; kernel
receipt, sorry-free); non-claiming — no certificate (undeclared)". This is the same honesty
the Nim external-subject precedent already fixed (external runs report `verified=0/41` —
`experiments/act2-wp3-exact-external-proof-outcome/wp3b-result.md:127`, read as honest
non-verification, not ingress failure — `act2-wp3-exact-external-proof-outcome/wp3-result.md:114`)
and the closed-verdict-space
rule already fixed in §1's reporting paragraph above (`ProofTerminal` — no verdict value is
added). `failed` remains RESERVED for a DECLARED spec with a CONFIRMED in-domain
counterexample — the negative-control norm (`docs/spec/rust_negative_control_norm.md:4-6`;
three-way split `:66-76`; the counterexample must be profile-independent, `:50-52`). A
replay-confirmed derived-guard violation (table below) is an OBSERVATION of the real
subject under the recorded overflow-checking profile — non-claiming, certificate-free —
never a declared-spec failure: status stays `unknown` and only the reason becomes
evidence-precise.

**Admission policy (cross-reference).** The two replay-evidence grades behind the outcome
classes below — the replay-confirmed observation (G1: profile-scoped, status stays
`unknown`) and the DECLARED-lane confirmed counterexample (G2: `failed`, exit 1) — are
governed by the evidence-grade admission contract `docs/spec/replay_evidence_policy.md`
(three-question separation; the five G1 admission conditions incl. the attribution rule and
the marker-as-implementation-signal rule; the binding G2 wording — G2 admission does NOT
require the G1 profile-witness condition, and where a replayed observation is
profile-affected, its scope is the recorded execution environment; `pinnedChannel` stays
`""` — identities are measured and recorded, never required equal).

**Outcome classification (closed).**

| status + reason class | meaning |
|---|---|
| `unknown` — "guard obligation discharged (proved …)" | Lean kernel accepted the guard theorem, `scanSorryMarkers` clean (`src/verification/obligation/canonical_verification.nim:653`); no certificate, no claim |
| `unknown` — "goal declined; candidate counterexample … — confirmation unavailable (overflow-discretion class)" | kernel declined; Z3 (pinned 4.13.3, seed 0, rlimit) produced an in-type-range candidate model; confirmation (panic-observation semantics + extraction↔replay profile binding) LANDED 2026-10-19 — the confirmed row below applies when replay observes the overflow panic; otherwise this fallback stays live (§3: overflow inputs have implementation-discretion semantics) |
| `unknown` — "guard goal '…' VIOLATED — declined by kernel; counterexample confirmed by replay under the recorded overflow-checking profile (…; extraction witness AddChecked; overflow-class observation, out-of-subset per §3 — profile-bound, not language semantics); model script digest <hex>; not a declared-spec failure; no certificate" | kernel declined AND replay confirmation SUCCEEDED on the real subject: exact-input Z3 model → input literals → replay under the pinned overflow-checking profile → `rroPanicked` outcome AND the "attempt to add with overflow" marker in the panic evidence (profile, toolchain disclosure and fallback conditions below); status stays `unknown` — no certificate, no claim |
| `unknown` — "unproven" | kernel declined, Z3 unsat (goal true but unproven — no verified claim) |
| `unknown` — "no derivable guard obligation" | zero mechanical goals (e.g. no arithmetic) |
| `unknown` — "out-of-subset grammar" | unchanged fail-closed classification |
| `failed` (DECLARED lane only) — "counterexample CONFIRMED …" | Z3 model → rustc replay `rvDisagree` (`replayConfirmedRustDisproof` — `src/verification/rust_replay_adapter.nim:775`) |

**Replay profile & toolchain disclosure (confirmed class).** The replay profile is PINNED —
`-C overflow-checks=on -C debug-assertions=on` (`RustReplayProfileFlags` —
`src/verification/rust_replay_adapter.nim:226`): explicit flags remove the emergent default
chain (rustc book, codegen options: `overflow-checks` defaults to `debug-assertions`;
`debug-assertions` defaults to `opt-level == 0`). The extraction-side witness is the LLBC
`AddChecked` + `Assert{Overflow, Panic}` lowering: guard goals derive only from `AddChecked`
nodes, and a checks-off extraction lowers plain `Add` and is rejected out-of-grammar — a
confirmed observation is only ever about a checked build. Confirmation requires the full
chain — exact-input Z3 model → input literals → replay of the real subject → `rroPanicked`
outcome AND the overflow marker ("attempt to add with overflow") in the panic evidence; compile failures,
non-git subjects and non-panic outcomes fall back to the unconfirmed class above.
TOOLCHAIN DISCLOSURE: extraction runs under charon's pinned nightly (0.1.281 @
`7980165…`, driving nightly-2026-09-17 — `src/verification/extraction_provenance.nim:68-73`);
replay uses the MEASURED ambient rustc, whose fingerprint (version / binary hash / channel /
profile) is recorded on the replay record
(`src/verification/rust_replay_adapter.nim:634-640`). The confirmed scope is therefore the
PROFILE level; toolchain-identity EQUALITY is NOT claimed — the difference is recorded and
disclosed, never assumed away (quirks Q1/Q5 — `docs/spec/rust_toolchain_quirks.md:21,:218`).

**Determinism discipline.** Z3 model VALUES are never byte-asserted across runs (INV-10 —
Z3 determinism is an engineering pin (binary checksum · seed 0 · rlimit), not a guarantee;
`docs/spec/certification_continuity_contract.md:260`); the confirmed class extends the same
rule — model literals and panic text are LOG-ONLY (INV-10: models are uncontracted) and
never enter reason strings. Reason strings carry only the goal text, the profile flags, the
fixed phrase set, and the model SCRIPT digest; attempt identity is carried by the Z3 script
digest; cross-run comparisons use the §6 key-exclusion projection
(`docs/spec/productization_contract.md:199-221`): `timestamp`/`ts` excluded, `certPath`
compared as basename only, and reason strings compared by their classification prefix above
(the confirmed class included — classification prefix + script digest) — never byte-for-byte.

**SMT encoding note.** Guard goals run on the width-uniform IR: parameters are
`(_ BitVec 64)` (`irTypeToSmt` — `src/core/trusted/private/ir_to_smt_chunk2.nim:7-16`;
u8/u32 lifted per §1 — no 8/32-bit sort exists in `IRType`), so `bvadd` cannot wrap under
the range preconditions (u8: `a + b ≤ 509 ≪ 2^64`) and the goal expresses the mathematical
sum. Comparisons emit `bvslt` (the signed comparison policy —
`src/core/logic/smt_logic.nim:17-18`), which agrees with the unsigned reading under the
non-negative type-derived ranges.

**SMT encoding note — width-64 overflow obligations (v1.2, `work/u64-add-2026-11-02`).**
The signed policy above does NOT extend to width-64 overflow obligations (the discharged
no-overflow goal of the §1 plain `+` row, and any width-64 goal the same overflow channel
emits). At p ≥ 2^63 a signed reading falsifies the premises, so a signed encoding risks
VACUOUS emission — a §0.9 theater hazard; the goals therefore encode unsigned comparison
DIRECTLY (repo precedent for substituting unsigned comparison where the domain is
unsigned: the `bvsle`→`bvule` substitution in
`src/core/trusted/private/ir_loop_to_horn.nim:138-139`). A BV64-native comparison is
UNSOUND and is not a substitute: a wrapped `boAdd` cannot witness the mathematical
overflow (`boLe(boAdd(l,r),2^64−1)` passes on wrapped sums). The sound encoding is a
65-BIT ZERO-EXTEND of both operands followed by an unsigned `bvule` against
width-accurate constants — `2^64−1` = `(_ bv18446744073709551615 65)` and
`2^64` = `(_ bv18446744073709551616 65)` (the equivalent forms `lhs+rhs ≤ 2^64−1` and
`lhs+rhs < 2^64`). The constants MUST be decimal `bv` literals: SMT-LIB hex literal
width is 4× the hex-digit count, so NO hex notation exists for a 65-bit value (17 hex
digits = 68 bits = 2^65−1 — a sort mismatch). Implementation site:
`src/core/trusted/private/ir_to_smt_chunk3.nim` (width-64 branch of the
overflow-obligation encoding — lands in `work/u64-add-2026-11-02`).

**SMT encoding note — `boLtU` unsigned comparison operator (v1.3, `work/boltu-unsigned-ir-op-2026-11-02`).**
The unsigned comparison operator `boLtU` (enum appended after `boEq` — wire ordinal 16,
append-only) carries producer-resident unsigned semantics: it lowers `bvult` (SMT),
`BitVec.ult` (Lean BitVec renderer), and unsigned bit-pattern comparison (replay). Its
denotation is the Int mathematical order ON the u64 domain `[0, 2^64)` — on that domain the
Int order and the unsigned bit order coincide (the `proofs/IR/Denotation.lean` bridge
theorem). The domain premise is secured by the EXISTING type-derived machinery (§1
Condition 1, origin aoTypeDerived — `src/verification/rust_obligation_render.nim` attaches
`0 ≤ p ∧ p ≤ 18446744073709551615` to every width-64 parameter): a `boLtU` claim whose
operands do not carry the u64-domain range premises is OUT of the certified subset. Width
pinning: the pinned x86_64 target (SemanticProfileV1 `x86_64|64|64` — Nim `uint` is 64-bit
there); any other target requires a SemanticProfileV1 revision. Producers: `ast_to_ir`
emits `boLtU` for `<` only when BOTH operand types are determinately unsigned (uint-family
parameters by original source type, unsigned literals by AST node kind); mixed or
unresolvable operands keep `boLt` (status quo). The text IR parser recognizes `boLtU`. NOT
applied to: loop `idx < end`, `contract_synthesis` `idx < len(S)`, DSL `<` (Int-domain
mathematical order), the `containsU64Lit` width-64 overflow channel (unchanged, separate
contract), and mechanically derived range premises (those keep `boLt` — sound under their
own domain premises). Kernel-cleanliness (measured 2026-11-02, lean 4.33.0): `BitVec.ult`
in the raw-BitVec emission form closes under `bv_decide` with `#print axioms` =
`[propext]` ⊆ the INV-6 allowlist. Fallback guard: an Int-domain fallback for `BitVec.ult`
is permitted ONLY with a Lean-kernel-verified equivalence
`BitVec.ult(a,b) ↔ toInt_U(a) < toInt_U(b)`; without it the slice stays BLOCKED, never
silently switched.

**U2 (§0.12 checklist) judgment record.** ① Contract: no new public surface, metric,
artifact, or claim — status vocabulary, JSON schema, exit rule, and certificate gate are all
unchanged; the only delta is reason-string content and proof attempts for symbols already
listed in the report. ② Customer need: arbitrary-repo response parity. ③ Vertical slice:
end-to-end `ax prove --project` → honest verdicts. ④ Minimal scope: no grammar/cert/claim
change. ⑤ Acceptance: gateway tests + fresh-external-crate determinism run. Judgment: NOT a
`ContractRevision` — `verified` semantics are untouched, the exact hazard R2/R7 police
(`docs/spec/productization_contract.md:48-50`,`:109`). Escalation path: if the architect
classifies the failed-on-confirmed-counterexample projection as SEMANTIC (`CleanupSemantics`
— `docs/spec/change_governance_contract.md:32`, §3.1 `:43-51`), a
`config/decision_binding.waiver.toml` entry is required before landing.

## References

- `src/core/trusted/axiom_ir_types.nim:17` — `irtBitVec64` is the only machine-integer IR type
- `docs/spec/semantic_profile_verified_semantics.md:54-56` — overflow discharge invariant
- `docs/spec/semantic_profile_verified_semantics.md:10-16` — coincidence-domain precedent
- `proofs/IR/Denotation.lean:124-141` — `Certified` forms (no Result/Option, no wrapping
  variant)
- `src/core/trusted/axiom_ir.nim:33,:37,:38` — `boAdd` / `boRem` / `boRemU`
- `src/core/trusted/axiom_ir.nim:90` — `IRExpr.litVal: int64`, the signed literal domain
  `[−2^63, 2^63−1]`; the u64-domain literal representation `[2^63, 2^64−1]` (IR codec tag
  `0x0F` = `irLitU64`; `rust_ast_wire` version 1→2 domain code 0=signed, 1=unsigned) lands
  in `work/u64-add-2026-11-02` (§1)
- `src/core/trusted/private/ir_to_smt_chunk3.nim` — width-64 overflow-obligation encoding:
  65-bit zero-extend + unsigned `bvule` against width-accurate decimal `bv` constants (no
  line anchor — the width-64 branch lands in `work/u64-add-2026-11-02`; the existing
  `:213-216` `collectOverflowGoals` anchor above consumes the goal shape-invariantly) (§1, §4)
- `src/core/trusted/private/ir_loop_to_horn.nim:138-139` — `bvsle`→`bvule`
  unsigned-projection substitution precedent for the width-64 `bvule` encoding (§4)
- `src/verification/rust_obligation_render.nim` + `src/verification/rust_extraction_agreement.nim`
  — documented twin pair; the width-64 type-derived precondition moves lower-bound-only →
  full range `0 ≤ x ≤ 2^64−1`, both change identically (no line anchor — lands in
  `work/u64-add-2026-11-02`) (§1)
- `src/verification/llbc_to_canonical.nim` — the producer; its named width-64 wall rejection
  reason string is PRESERVED for regression tracking while the width-64 path no longer emits
  it (no line anchor — the path changes in `work/u64-add-2026-11-02`) (§1)
- `src/verification/ast_wire.nim:18-58,:60-68,:79-83,:379-380` — fail-closed codec precedent
- `data/verification_scope.lock` — Nim scope lock, schema v3 + additive `rust_targets` /
  `vksRust` (`vks_rust`) members
- `src/core/trusted/axiom_pragmas_procs.nim` — `validateRustScopeSection` / `buildRustScopeJson`
  (fail-closed Rust declaration validation + canonical emission)
- `src/cli/scope_cli.nim` — lock regeneration / consistency enforcement (`vks_rust` cross-check)
- `src/verification/obligation/obligation_types.nim` — `AssumptionOrigin`
  (`aoTypeDerived` / `aoCallerObligation` / `aoUserDeclared`), `computeObligationId`
  payload, `ObligationOutcome.conditionalGuarantee` / `undischargedAssumptions`
- `docs/spec/verification_density.md:17-19` — Rust enforcement pair named (codec boundary +
  `vks_rust`)
- `docs/spec/productization_contract.md:11,:15` — §1 declared-subset scope
- `docs/spec/provenance_contract_v3.md:36,:164` — `subjectLanguage: "rust"`
- `docs/adr/0030-rust-subject-semantic-authority.md` — authority (D1), fact status (D2),
  assurance ceiling (D3)
- The Rust Reference — "Behavior not considered unsafe — Integer overflow" (external
  normative citation for §3; with debug assertions enabled, implementations MUST insert
  dynamic checks that panic on overflow — the normative basis of the §4 confirmed-class
  replay profile)
- `docs/spec/rust_negative_control_norm.md:4-6,:50-52,:66-76` — negative-control norm:
  `failed` requires a CONFIRMED, profile-independent in-domain counterexample (§4)
- `docs/spec/certification_continuity_contract.md:260` — INV-10: Z3 determinism is an
  engineering pin (binary checksum · seed 0 · rlimit), not a guarantee (§4)
- `docs/spec/productization_contract.md:20,:48-:50,:109,:199-221,:245` — §1 Verification
  semantics / R2 / R7 / §6 canonical projection / §7 CLI contract — all unchanged by §4
- `src/core/trusted/private/ir_to_smt_chunk2.nim:7-16` — `irTypeToSmt` width-uniform
  `(_ BitVec 64)` lowering; no 8/32-bit sort (§4)
- `src/core/logic/smt_logic.nim:17-18` — signed comparison policy (`bvslt`) (§4)
- `src/verification/obligation/canonical_verification.nim:653` — `scanSorryMarkers`
  (sorry-free check behind the discharged classification) (§4)
- `src/verification/rust_replay_adapter.nim:775` — `replayConfirmedRustDisproof`
  (confirmed-counterexample projection, DECLARED lane only) (§4)
- `src/verification/rust_replay_adapter.nim:226-241` — `RustReplayProfileFlags`, the pinned
  replay profile (`-C overflow-checks=on -C debug-assertions=on`) + default-chain rationale;
  `:735` `runRustCounterexampleReplay`, `:140` `rroPanicked`, `:634-640` recorded rustc
  fingerprint (version / binary hash / channel / profile) — the replay entry points and
  recorded identity behind the confirmed class (§4)
- `src/verification/extraction_provenance.nim:68-73` — `PinnedCharonVersion` 0.1.281 /
  `PinnedCharonPinCommit` `7980165…` — the extraction-side toolchain identity disclosed by
  the confirmed class (§4)
- `docs/spec/rust_toolchain_quirks.md:21,:218` — Q1 (ambient toolchain identity is
  environment-dependent) / Q5 (pinned replay profile + `AddChecked` witness + recorded
  compiler-version difference) (§4)
- [The rustc book — Codegen options](https://doc.rust-lang.org/rustc/codegen-options/index.html)
  (`overflow-checks` / `debug-assertions` — the default chain the explicit replay flags
  remove) (§4)
- [RFC 560 — Integer overflow semantics](https://rust-lang.github.io/rfcs/0560-integer-overflow.html)
  (overflow is a program error, not UB; dynamic checks required when debug assertions are
  enabled — historical root of the §4 replay profile and the §3 discretion framing)
- `experiments/act2-wp3-exact-external-proof-outcome/wp3b-result.md:127` — Nim
  external-subject precedent: honest `verified=0/41` (§4 status principle)
- `docs/spec/change_governance_contract.md:32,:43-51` — `CleanupSemantics` axis (§4
  escalation path)
- `docs/spec/replay_evidence_policy.md` — G1/G2 replay-evidence admission contract
  (three-question separation; G1 conditions + attribution rule + marker-as-signal rule;
  G2 wording rule; `pinnedChannel` decision; INV-10 determinism-vs-validity separation;
  no-new-surface) (§4)
