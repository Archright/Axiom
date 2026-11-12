# Replay Evidence Admission Policy (G1/G2)

- **Status**: binding admission policy for replay evidence on the Rust lane
  (`feat/replay-evidence-admission`, 2026-10-19). It fixes WHICH execution observations are
  admissible, at which evidence grade, and what each admitted grade may change in reported
  status. It is the SSOT for the two replay-evidence grades consumed by §4 of
  `docs/spec/rust_certified_subset.md` (the replay-confirmed observation class and the
  DECLARED-lane counterexample confirmation): §4 declares the outcome classes; this document
  fixes the ADMISSION conditions behind them.
- **Authority**: rustc (ADR-0030 D1 — `docs/adr/0030-rust-subject-semantic-authority.md`).
  The replay execution is "the confirming observer of the model, never a promotion authority
  by itself; any disagreement or unavailability is fail-closed demotion"
  (`docs/spec/rust_negative_control_norm.md:74-76`).
- **Claim discipline**: this document declares a REPORTING/ADMISSION DISCIPLINE — the rules
  under which replay evidence may be cited in a report classification. It is not a
  capability claim, not a scope extension, and it adds no surface (§8).

## 1. Scope — two grades, nothing else

Replay evidence is an execution observation of the real subject binary. Exactly two
admission grades exist, and nothing else:

| Grade | What is admitted | Status effect | Exit effect |
|---|---|---|---|
| **G1** — profile-scoped overflow observation | "the real subject, compiled and run under the recorded overflow-checking profile, panicked on the exact model input" | status stays `unknown`; the reason becomes evidence-precise (`rust_certified_subset.md` §4 confirmed row) | none — `unknown` is not a failure state and never flips the exit axis |
| **G2** — declared-spec counterexample | "a confirmed in-domain counterexample falsifies a DECLARED specification" | status `failed` | `1` (§7 `verification-failure` — `docs/spec/productization_contract.md:270`) |

Both grades are certificate-free as admission outcomes: G1 never mints a certificate; G2's
`failed` is the contract-reserved falsification status and mints none either. Any
observation that meets neither grade's conditions falls back to the existing honest
fallback classification — status `unknown`, unconfirmed reason — never to a new category.

## 2. The three-question separation

Every replay-evidence decision answers three DIFFERENT questions with different authorities.
Conflating them is the failure mode ("the solver said sat" or "it panicked" being treated as
a verdict) this policy exists to prevent:

| # | Question | Answered by | May it change status? |
|---|---|---|---|
| 1 | POSSIBILITY — "does a concrete in-domain input exist on which the proposition fails?" | the solver: Z3 (pinned 4.13.3, seed 0, rlimit) over the theorem-domain-constrained query | never by itself — "`sat` alone must NOT issue PROPOSITION_DISPROVED" (`docs/spec/rust_negative_control_norm.md:71`) |
| 2 | OBSERVATION — "did the real subject, compiled and run normally, actually exhibit the behavior on that input?" | the replay execution of the real subject — the confirming observer ("compiled and run normally" — `docs/spec/rust_negative_control_norm.md:9-10`) | never by itself — it confirms or demotes a model; it does not promote (`:74-76`) |
| 3 | VERDICT — "what may this evidence be reported as?" | the fixed contract rules only: the closed status vocabulary, the R2 `verified` rule, the R7 scope rule, and the G1/G2 boundaries fixed here | yes — but only along those boundaries |

The verdict question is answered by rules, not by the observer: status values come from the
closed `ProofTerminal` vocabulary (`rust_certified_subset.md` §1 reporting paragraph); the
`verified` family stays certificate-bound (R2 — `docs/spec/productization_contract.md:48-58`,
"`verified`에 vacuous proof가 포함되면 FAIL"); `failed` stays reserved for a DECLARED spec
with a CONFIRMED in-domain counterexample (`docs/spec/rust_negative_control_norm.md:4-5`:
"Negative-control subjects must produce a counterexample confirmable by normal execution
WITHIN the supported subset"); and scope never exceeds what the documents claim (R7 —
`docs/spec/productization_contract.md:109-122`).

## 3. G1 — profile-scoped overflow observation (status stays `unknown`)

G1 admits the replay-confirmed guard-violation observation class: the real subject, replayed
under the pinned overflow-checking profile (`-C overflow-checks=on -C debug-assertions=on` —
`RustReplayProfileFlags`, `src/verification/rust_replay_adapter.nim:226`), panicking on the
exact solver model input. Admission requires ALL FIVE conditions.

| # | Condition | Contract grounding (verbatim where quoted) |
|---|---|---|
| (i) | **AddChecked-derived goal (structural witness).** The attempted obligation derives structurally from the LLBC `AddChecked` + `Assert{Overflow, Panic}` lowering; the producer admits the `Assert` only inside the `AddChecked` collapse and rejects a non-`AddChecked` BinaryOp / standalone non-Overflow `Assert` out-of-grammar (`src/verification/llbc_to_canonical.nim`) | "guard goals derive only from `AddChecked` nodes, and a checks-off extraction lowers plain `Add` and is rejected out-of-grammar — a confirmed observation is only ever about a checked build" (`rust_certified_subset.md` §4) |
| (ii) | **Exact-input Z3 model.** A concrete model within the theorem domain (range preconditions asserted), carried to replay as input literals | "the payload fires only on a P4-promoted disproof WITH a concrete solver model AND replay agreement" (`docs/spec/rust_negative_control_norm.md:71`) |
| (iii) | **Single `BuildInvocation` compile — executed == recorded.** The replayed binary comes from ONE build invocation, and admission checks the PAIR: the invocation that was executed against the invocation identity recorded on the replay record (`compileProfile` — `rust_replay_adapter.nim:157`, set `:675`; measured rustc fingerprint — `:634-640`) — never a promise about either | "replay uses the MEASURED ambient rustc, whose fingerprint (version / binary hash / channel / profile) is recorded on the replay record" (`rust_certified_subset.md` §4; recording, not equality — §5 below) |
| (iv) | **Attribution-safe model.** The per-goal query is CONSTRAINED: it asserts the sibling guard goals, and a concrete sibling evaluation is checked as defense-in-depth (§3.2), so the model is attributable to THIS goal, not to the goal family | "The counterexample must be a real input on which the real subject … really violates the claimed specification" (`docs/spec/rust_negative_control_norm.md:9-10`) — the violation must be THIS goal's, not a sibling's |
| (v) | **The subject's own observed panic with the checked-add report text.** Replay outcome `rroPanicked` (`rust_replay_adapter.nim:140`) AND the checked-add overflow marker in the panic evidence — "attempt to add with overflow" (matched as the `"attempt to add with overflow"` report marker — `src/verification/rust_rust_pipeline.nim:379`). See §3.1: the text is an IMPLEMENTATION OBSERVATION SIGNAL; the semantic guarantee is the MUST-panic rule | "with debug assertions enabled, implementations MUST insert dynamic checks that panic on overflow" (The Rust Reference, "Behavior not considered unsafe — Integer overflow"; [RFC 560] — overflow is a program error, not UB) |

Any unmet condition — compile failure, replay unavailable, non-panic outcome, model absent,
attribution constraint unsatisfiable, marker absent — falls back to the EXISTING honest
fallback reason (the unconfirmed class of `rust_certified_subset.md` §4). Status stays
`unknown`; no certificate; no JSON/status/exit change. No new reason vocabulary is created.

### 3.1 The overflow marker is an IMPLEMENTATION OBSERVATION SIGNAL — not a contract guarantee

The normative guarantee binding the replay profile is message-independent: when overflow
checks are enabled, the implementation MUST insert dynamic checks that panic on overflow
(The Rust Reference, "Behavior not considered unsafe — Integer overflow";
[RFC 560 — Integer overflow semantics]). The exact report text "attempt to add with
overflow" is NOT part of that guarantee: the official documentation presents the message as
example output, and release notes record panic-message format changes across releases. G1
therefore uses the marker only as a signal that the observed panic is the checked-add
overflow class (defense against panics from unrelated causes — abort, a different
assertion, an out-of-contract exit) and never as a stable contract surface. No admission
rule may depend on the marker's exact format surviving toolchain updates; its absence
demotes the observation to the unconfirmed class (fail-closed).

### 3.2 Attribution rule (condition (iv), binding)

The model-to-goal attribution is G1's anti-masquerade rule. The Z3 query for guard goal `g`
must assert the sibling guard goals as constraints (per-goal constrained query), and the
pipeline must evaluate the concrete sibling defenses as defense-in-depth, before a produced
model may be attributed to `g`. Rationale: the guard goals of one symbol form a FAMILY —
they share the extraction, the profile, and the input space — so an unconstrained per-goal
query can return a point that satisfies `g` only by violating a DIFFERENT guard; replaying
such a point would fabricate a "confirmed violation of `g`" out of a sibling's
counterexample. A model that fails the sibling evaluation is inadmissible for `g` (fallback,
§3).

## 4. G2 — declared-spec counterexample (status `failed`, exit 1)

G2 is the EXISTING confirmed-counterexample admission (`replayConfirmedRustDisproof` —
`src/verification/rust_replay_adapter.nim:775`): a DECLARED spec (a `rust_targets` entry)
with a CONFIRMED in-domain counterexample reports `failed` and exits `1`
(`docs/spec/productization_contract.md:270` — `verification-failure` = `1`, "Verification
claims not established"). Its conditions are exactly the existing ones — none added, none
removed:

| Condition | Contract grounding |
|---|---|
| theorem-domain-constrained model (in-domain by construction — range preconditions asserted; overflow inputs stay outside the verified domain, `rust_certified_subset.md` §3) | "Negative-control subjects must produce a counterexample confirmable by normal execution WITHIN the supported subset." (`docs/spec/rust_negative_control_norm.md:4-5`) |
| replay verdict `rvAgree` — the replayed subject behaves as the model predicts; `rvDisagree`/`rvUnavailable` demote fail-closed (`src/verification/rust_replay_adapter.nim:19`) | "`sat` alone must NOT issue PROPOSITION_DISPROVED … replay disagreement/unavailability demotes the disproof to `cvUnresolved` … carrying the model but no PROPOSITION_DISPROVED payload" (`docs/spec/rust_negative_control_norm.md:71`) |
| worktree stability — the subject tree is unchanged across the run, measured as RELATIVE pre/post equality (`worktreeStable` — `rust_replay_adapter.nim`, pre-captured in `bindRustSubjectIntegrity`, re-measured + enforced in `confirmRustPostRunIntegrity`): (a) the subject module sha256, (b) the subject-inputs digest (`git ls-files --full-name --cached --others --exclude-standard` over the discovered subject project root; per-file sha256, relpath-sorted, whole-digest sha256), (c) the repo status digest (`git status --porcelain --untracked-files=all` output hash), (d) the tracked-content digest (`git diff HEAD --no-color --no-renames --no-ext-diff` output hash) — each captured BEFORE anything runs and re-measured after; pre-existing worktree noise (a stale build stamp, untracked files) is present on BOTH sides of the comparison and can never break the seal | Zero-Footprint Integrity: the observation must be of the subject as hashed |

Condition count is unchanged — three rows, none added, none removed: this
row PRECISES the implementation definition of the existing
"unchanged across the run" condition (predicate v2, restored 2026-11-03).
It is a redefinition of what counts as drift (run-relative, as this policy
always stated), NOT a path exemption — every path stays inside the measured
footprint and nothing is ignored.

**Wording rule (binding).** G2 must NOT be described as "profile-independent". The sentence
"reproducible by real Rust execution under any build profile, since no overflow occurs at
that input" (`docs/spec/rust_negative_control_norm.md:51-52`) describes the RECOMMENDED
in-domain negative shape (`a + b + 1` at `(0,0)`), where no overflow exists at the
counterexample input — it is a property of that shape, not of G2 admission. The binding G2
wording is:

> G2 admission does NOT require the G1 profile-witness condition; where a replayed
> observation is profile-affected, its scope is the recorded execution environment.

What G2 requires is in-domainness and replay agreement — not build-profile invariance of
the observation. Where the falsifying behavior IS profile-affected, the confirmed scope is
the recorded execution environment, exactly as in G1.

## 5. Identity is MEASURED AND RECORDED — never required to be EQUAL (pinnedChannel decision)

Neither contract contains a replay↔extraction toolchain-identity clause:

- R2 (`docs/spec/productization_contract.md:48-58`) governs result semantics — no identity
  equality requirement;
- R7 (`:109-122`) governs scope honesty — no identity equality requirement;
- §7 (`:259-296`) fixes the CLI exit-state contract — no identity equality requirement;
- §5's mismatch rule (`:195`, "toolchain identity 불일치 → invalid.") is a READINESS-ENVELOPE
  rule: it invalidates a readiness evidence bundle whose evaluation context is internally
  inconsistent. It is not a replay-admission clause and imposes no extraction↔replay
  equality.

The duty on both sides is therefore RECORDING, not EQUALITY:

| Side | Measured + recorded identity | Anchor |
|---|---|---|
| extraction | charon pin `0.1.281` @ `7980165…` (`PinnedCharonVersion` / `PinnedCharonPinCommit`); LLBC options / rustc args recorded provenance (`extractionContract`); measured `rustcFingerprint` | `src/verification/extraction_provenance.nim:68-73,:91-105` — `ExtractionJobRecord` is "RECORDED provenance … it never adjudicates trust by itself" |
| replay | measured rustc fingerprint (version / binary hash / channel / profile) + compile profile | `src/verification/rust_replay_adapter.nim:634-640`, `:157`, `:675` |

**Decision: `pinnedChannel` remains `""` (the default — `rust_replay_adapter.nim:97`).** No
contract requires the replay toolchain to equal the extraction toolchain or to satisfy a
declared channel pin; the identity fields exist so the DIFFERENCE is disclosed, never
assumed away (`docs/spec/rust_toolchain_quirks.md:21,:218` — Q1/Q5). Accordingly, no
admission rule in this policy may claim toolchain equality or semantic equivalence across
toolchains. The confirmed scope of a G1 observation is the PROFILE level (the pinned
`-C overflow-checks=on -C debug-assertions=on` flags); cross-toolchain behavior differences
are recorded facts, not admission conditions.

## 6. Determinism vs validity (INV-10)

The two axes stay separate:

- **Determinism** is an engineering pin, not a guarantee: Z3 determinism = binary checksum ·
  seed 0 · rlimit, and a re-execution verdict mismatch is fail-closed ("Z3 결정론은 공학
  고정(바이너리 체크섬·seed 0·rlimit)이지 보장이 아님 — 재실행 verdict 불일치 시 fail-closed"
  — INV-10, `docs/spec/certification_continuity_contract.md:260`).
- **Validity** of an admitted observation is defined by the G1/G2 conditions alone — NOT by
  cross-run byte-stability of models or panic text. Model literals and panic text remain
  LOG-ONLY (INV-10: models are uncontracted); reason strings carry only the classification
  prefix, the profile flags, the fixed phrase set, and the model SCRIPT digest; cross-run
  comparison uses the §6 key-exclusion projection
  (`docs/spec/productization_contract.md:199-221`), with reason strings compared by
  classification prefix + script digest — never byte-for-byte
  (`rust_certified_subset.md` §4 determinism discipline, unchanged).

An observation is not "less valid" because a fresh solver run would produce different model
bytes; it is inadmissible only when a G1/G2 condition is unmet.

## 7. No self-witness probe binary

This design contains NO separately-compiled self-witness probe. The subject's OWN observed
overflow panic is the profile witness once attribution is constrained (§3.2). A separate
probe binary compiled under the same flags would witness only that SOME binary panics under
those flags — it could not witness anything about the observed subject, and the
negative-control norm requires the real subject ("the real subject, compiled and run
normally" — `docs/spec/rust_negative_control_norm.md:9-10`). Adding a probe would be
theater (§0.9), not strengthening.

## 8. No new surface

This policy is reporting/admission discipline ONLY. Explicit non-goals — each of which
would require an explicit contract revision (§0.12) if attempted:

- no new JSON fields (report schema stays `axiom.report.v1` —
  `docs/spec/productization_contract.md:255`);
- no new certificate types (G1 mints none; G2's `failed` mints none);
- no new status values (the vocabulary stays the closed set; G1 stays `unknown`, G2 stays
  `failed`);
- no exit-code change (G1's `unknown` never flips the exit axis; G2's `failed` exits `1`
  per the existing §7 table — `docs/spec/productization_contract.md:270,:282`).

The only admissible carrier of G1 evidence is the already-existing reason-string channel of
`rust_certified_subset.md` §4 (classification prefix + script digest).

## References

- `docs/spec/rust_negative_control_norm.md:4-10` — the negative-control norm: counterexample
  confirmable by normal execution, on the real subject, within the supported subset (§2, §4)
- `docs/spec/rust_negative_control_norm.md:51-52` — "under any build profile" scope: the
  RECOMMENDED in-domain shape (no overflow at the counterexample input) — the sentence G2's
  wording rule bounds (§4)
- `docs/spec/rust_negative_control_norm.md:71-76` — concrete model + replay agreement gate,
  `sat`-alone prohibition, fail-closed demotion; the replay execution as confirming observer,
  never promotion authority (§2, §3, §4)
- `docs/spec/productization_contract.md:48-58` — R2 result semantics (no replay↔extraction
  identity clause) (§2, §5)
- `docs/spec/productization_contract.md:109-122` — R7 scope/coverage honesty (no identity
  clause) (§2, §5)
- `docs/spec/productization_contract.md:259-296` — §7 v1 CLI Exit-State Contract (5-state
  model; `failed` → `1`; no identity clause) (§1, §5, §8)
- `docs/spec/productization_contract.md:195` — §5 toolchain-identity mismatch rule —
  readiness-envelope-only (§5)
- `docs/spec/productization_contract.md:199-221` — §6 canonical projection (cross-run
  comparison basis) (§6)
- `docs/spec/certification_continuity_contract.md:260` — INV-10: Z3 determinism is an
  engineering pin, not a guarantee (§6)
- `docs/spec/rust_certified_subset.md` §3/§4 — overflow discretion; the confirmed observation
  class, replay profile & toolchain disclosure, determinism discipline (the consumer of this
  policy)
- `docs/spec/rust_toolchain_quirks.md:21,:218` — Q1/Q5: measured-identity disclosure, not
  equality (§5)
- `docs/adr/0030-rust-subject-semantic-authority.md` — authority (D1), fact status (D2)
- `src/verification/rust_replay_adapter.nim:19,:100,:143,:160,:182,:238,:722,:823,:905`
  — replay verdict vocabulary (`rvAgree`/`rvDisagree`/`rvUnavailable`), `pinnedChannel`
  default `""`, `rroPanicked`, `compileProfile`, the `RustReplayRecord`
  worktree-stability folds (`worktreeStable` + `subjectInputsPre/Post` +
  `repoFootprintPre/Post` — pre-capture in `bindRustSubjectIntegrity`,
  re-measure + enforcement in `confirmRustPostRunIntegrity`, emitted by
  `rustReplayRecordPayload`), `RustReplayProfileFlags`, recorded rustc
  fingerprint, worktree-stability (predicate v2) check/enforcement,
  `replayConfirmedRustDisproof`
- `src/verification/rust_rust_pipeline.nim:373-379` — overflow marker check
  (`evidence.contains("attempt to add with overflow")` —
  `guardPanicIsAttributedAdd`) (§3 (v), §3.1)
- `src/verification/extraction_provenance.nim:68-73,:91-105` — charon pin +
  `ExtractionJobRecord` recorded provenance (§5)
- `src/verification/llbc_to_canonical.nim` — the producer admitting the `AddChecked` collapse
  only; non-`AddChecked` BinaryOp / standalone non-Overflow `Assert` rejected (§3 (i))
- The Rust Reference — "Behavior not considered unsafe — Integer overflow"; and
  [RFC 560 — Integer overflow semantics](https://rust-lang.github.io/rfcs/0560-integer-overflow.html)
  — checks enabled ⇒ MUST panic; overflow is a program error, not UB (the semantic
  guarantee; the message text is implementation output) (§3 (v), §3.1)
