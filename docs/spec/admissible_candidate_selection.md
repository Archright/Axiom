# Admissible Candidate Selection & Determinism Contract

> SSOT for the candidate-selection pipeline used by `ax prove`: the canonical
> admissibility decision, the deterministic admissible ordering, and the
> `--limit` / internal-ratchet semantics.
>
> Introduced: 2026-08 (v39)
> Authority: AGENTS.md §0.2 (Determinism), §0.9 (anti-theater)

---

## 1. Problem Statement

`ax prove --limit 1` once selected `gate_rules_normalization.nim::normalizedEntries`
whose proof attempt immediately produced `SKIPPED_BY_THEORY` because the function
is not representable in the QF_BV BMC theory. The VKD numerator did not increase
(5 → 5), because `orchestrationSkippedByTheory` is intentionally excluded from the
kernel verified count. The symptom was a *candidate-selection / proof-execution
contract mismatch*, not a VKD arithmetic failure.

This document fixes the contract. It does **not** claim to remove every runtime
theory skip at compile time — some candidates (e.g. `normalizedEntries`) are only
rejected when the IR encoder/CHC bridge runs. Those are a legal, defensive
fallback (`DEFER_TO_RUNTIME`), not an invariant violation.

---

## 2. Core Invariants

```
Selected(c) ⇒ Admissible(c) ⇒ ExecutableProof(c)   (structural goal, per P2)
--limit N ⇒ N deterministic admissible proof attempts (when N exist)
```

Eligibility is judged by exactly one canonical predicate (`assessAdmissibility`),
shared by the candidate selector. No private, drifting eligibility duplicates live
in the solver.

---

## 3. Admissibility Contract (P0)

`src/verification/admissibility.nim` defines a 3-state decision:

| Decision | Meaning | Produced when |
|---|---|---|
| `ADMISSIBLE` | Statically executable-proof candidate | Compile-time `bmcSkippable=false` AND `classifyFunction` → `vtSmtNative` |
| `INELIGIBLE` | Statically unsupported — excluded before ranking/budget | string/float type or `vtNonDecidable` tier or unbounded/unsound loop |
| `DEFER_TO_RUNTIME` | Static cannot finalize → runtime admission decides | structural body with sound loop bound, or other static-unsure shapes |

**Convention (anti-theater):** Only a fully-static *negative* proof earns
`INELIGIBLE`; only a fully-static simple body earns `ADMISSIBLE`. Everything else
is honest runtime deferral. `normalizedEntries` (static-sounding, runtime-failing)
is `DEFER_TO_RUNTIME` — the runtime admission/encode step conclusively rejects it,
so a static oracle never over-promises.

### Selection survival rule (P1)
`isSelectionEligible(o) == (o.decision != INELIGIBLE)`.

- `ADMISSIBLE` and `DEFER_TO_RUNTIME` **both survive** selection.
- `INELIGIBLE` consumes **zero** ranking and **zero** proof budget.
- In `selectProofCandidates`, `INELIGIBLE` entries are dropped before the
  `isKernelScopeMember` admission and before any executor handoff.

### Legacy behavior preserved
`--legacy-uap` bypasses the IR pipeline; the legacy UAP (<code>loop_driver</code>)
performs its own incompatibility handling. This contract governs the canonical
IR-pipeline path.

---

## 4. Deterministic Ordering (P3)

The admissible candidate sequence is already deterministic. This is now declared
an **invariant**, not an accident:

1. `runtimeAxiomRegistry` is a `seq` — insertion (compile) order is stable.
2. `selectRegistryEntries` preserves registry insertion order.
3. Topology `verificationQueue` is sorted by `sortMetricIndices` (multi-key:
   interfaceDistance → complexityScore → topologyScore → couplingScore →
   `sorterNodeIdString`).
4. `DeterministicScheduler` sorts by `(priority ASC, key ASC)` and collects
   results in sorted order.
5. Every tie is broken by `sorterNodeIdString` (the canonical symbol id) — a
   unique, deterministic total-order tiebreak.

**Forbidden sources of nondeterminism** (regression guard): filesystem iteration
order (must be `.sort()`-ed, cf. `nimtry_cli.nim:220`), hash-map iteration order
(must use `seq` for ordering, e.g. `runtimeAxiomRegistry` not `registryLookup`),
parallel discovery order (must be re-sorted on collect), wall-clock timestamps,
and randomness.

**Goal invariant:** identical source snapshot + identical scope lock + identical
certificate state + identical toolchain → identical admissible candidate
sequence.

---

## 5. `--limit` / Internal Ratchet Semantics (P4)

- **User `--limit N`** is the user-facing proof-attempt budget. It is the number
  of admissible candidates fed to the executor (capped also by the verified
  frontier).
- **`computeVkdRequiredLimit`** is an internal *selection-feed* widening: it may
  fetch more registry entries than `cliLimit` so that kernel-scope symbols
  interleaved in registry order are not truncated before the admissibility +
  kernel-scope admission. It is **not** an execution budget.
- `--limit` is deliberately **not** a hard cap on the VKD feed — a ratchet that
  silently truncated kernel symbols would starve the VKD numerator (DECISION-0011).

**Consequence:** `--limit 1` executes at most one admissible proof attempt *when
an admissible candidate exists*; it does **not** guarantee `VKD += 1`, because the
single attempt may be `FAILED`/`UNKNOWN`/`TIMEOUT`, or the top admissibility-
eligible candidate may be `DEFER_TO_RUNTIME` and rejected at runtime.

---

## 6. Runtime Theory Skip (P6 forward note)

A `SKIPPED_BY_THEORY` **after** a candidate has been handed to the proof executor
would be an internal invariant violation. In the current pipeline:

- `INELIGIBLE` (static) → rejected before selection. **Legitimate.**
- `DEFER_TO_RUNTIME` → handed to executor, conclusively rejected by runtime
  admission/encode. **Legitimate** (this is where `normalizedEntries` lands).
- A skip emitted by the executor for a candidate that passed both static and
  runtime admission → **would be** an invariant violation (future `P6`
  enforcement).

Full `P6` formalization (making post-admission theory skips impossible) is a
follow-up; this document intentionally does **not** over-claim compile-time
removal today.

## 6b. P6 Status — Runtime rejection taxonomy (empirical finding)

Measurement of the current kernel scope (v9.18) reveals the operative bottleneck
is **not** candidate admissibility — it is `no-property`/`no-obligation`:

| Gate | Result for kernel scope | Contribution to VKD |
|---|---|---|
| Static `INELIGIBLE` | removed before ranking (P0/P1) | none |
| `ADMISSIBLE` (vtSmtNative) | selected, but many lack a postcondition | none if `rkNoProperty` |
| `no_obligation` / `rkNoProperty` | honest vacuous skip (`loop_driver.nim:276-286`) | none (by design) |
| `rkNotEncodable` / `rkUnsupportedTheory` | runtime ineligibility (`loop_driver.nim:287-293`) → `SKIPPED_BY_THEORY` | none |

**Empirical finding:** `baseline.json` `certificatesByTier.none` lists
`proximityScore`, `clampTimeoutMs`, `normalizeMaxWorkers`, `safeSpeedupRatioCore`,
`calcDynamicTimeoutCore` — all `vtSmtNative` (ADMISSIBLE) yet absent from the
numerator. They are skipped with `rkNoProperty` because they carry **no
postcondition** (`cross-validation skipped — no postconditions`). They are not
theory-ineligible; they are *obligation-absent*.

**Consequence for VKD 5→6:** raising the numerator is blocked at
**spec/contract synthesis**, not at candidate selection. A kernel symbol
contributes to VKD only when it (a) is ADMISSIBLE **and** (b) has an obligation
to prove. The P6 "interaction remove ALL theory skips" framing must therefore be
narrowed:

- `no_obligation` / `rkNoProperty` → legitimate `RUNTIME_INELIGIBLE` (vacuous),
  never demoted to an invariant violation.
- `rkNotEncodable`/`rkUnsupportedTheory` for a candidate that passed static
  admission (`ADMISSIBLE`, non-loop, non-string/float) → **would be** an internal
  invariant violation (P0 static oracle over-promised).
- The real next work item is postcondition synthesis for ADMISSIBLE kernel
  symbols, not theory-skip elimination.

## 6c. Kernel-scope VKD suitability finding (v9.18-P6b)

A second, more precise scan (beyond the `certificatesByTier.none` tier) enumerates
the full candidate universe `KernelScope ∩ ¬Exempt ∩ ¬Verified` and reveals **18**
unverified kernel symbols. Yet the verified frontier admitted exactly one
(`normalizedEntries`). Repro with the classifier + certificate audit shows the
remaining 17 are excluded not by postcondition absence but by **structural
suitability**, so the earlier "postcondition absence is the sole bottleneck"
framing was incomplete:

| root cause | examples | disposition |
|---|---|---|
| state-mutating / object-shaped signature (`var report`, `SorterNodeId`, `OrchestrationReport`) | `addNodeExecutionStat`, `addNodeReport`, `addDepthExecutionStat` | not CHC/SMT-encodable (CASE 2) |
| composite return type outside QF_BV (`JsonNode`, `seq[string]`) | `axiomSpecToJsonNode`, `normalizedEntries` | not faithfully encodable / no numeric contract |
| already `certGreen` (duplicate of the existing 5) | `normalizeMaxWorkers`, `proximityScore`, `clampTimeoutMs`, `calcDynamicTimeoutCore`, `safeSpeedupRatioCore` | verified — excluded from frontier |
| dependency-gate (unverified transitive dep) | several | frontier excludes until deps verified |

The kernel scope is dominated by state-mutation and object-manipulation helpers,
not by pure numeric contracts. `postcondition` addition alone therefore cannot
raise `VKD` 5 → 6; the operative bottleneck is **kernel-scope composition** (a
scarcity of proof-suitable pure-numeric members). Resolution is tracked as a
separate follow-up (spec/contract synthesis over pure-numeric members, or
growing the kernel scope with genuinely provable pure functions), **not** by
synthesizing arbitrary postconditions over `seq[string]` normalizers — that
would be metric gaming (§0.9).

---

## 7. Verification

1. **Eligibility:** unsupported-type / unbounded-loop → `INELIGIBLE` (not
   selectable); `vtSmtNative` → `ADMISSIBLE`; structural-sound → `DEFER_TO_RUNTIME`.
2. **Limit:** `--limit 1` → at most one admissible attempt.
3. **Skip:** `INELIGIBLE` consumes zero budget.
4. **Determinism:** repeated identical runs yield identical candidate sequences.
5. **Negative regression:** `normalizedEntries` is no longer the first *top*
   selectable candidate.
6. **VKD:** if the single admissible attempt lands in
   `orchestrationVerified`/`InductiveValid`, the numerator increases by one.