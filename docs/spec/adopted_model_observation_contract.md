# Adopted-Model + Stamped Replay Observation — general contract (SSOT)

**Status**: Normative reference (v1, 2026-11-20). This document generalizes the shape already
ratified lane-by-lane; it creates no new verdict producer, enum, gate, or execution authority.
**Related**: [direct_proof_boundary.md](direct_proof_boundary.md) (per-construct direct-proof status),
[nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md),
[toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md),
[nim_stew_base36_sidecar_contract.md](nim_stew_base36_sidecar_contract.md),
[jrpc_errcode_class_binding_contract.md](jrpc_errcode_class_binding_contract.md),
[obligation_semantics.md](obligation_semantics.md) §2.1a-4,
[counterexample_replay_adapter.md](counterexample_replay_adapter.md),
[replay_evidence_policy.md](replay_evidence_policy.md), [authority_contract.md](authority_contract.md)

## 1. Scope and lane choice

A subject outside the direct-proof baseline ([direct_proof_boundary.md](direct_proof_boundary.md) §2-§3)
has no emitted denotation, so no direct theorem about its body can exist in this pipeline. This
document defines the only alternative shape Axiom currently uses for such a subject: an
**adopted model** checked by the solver, plus a **stamped replay observation** of the original
symbol. It does not reclassify any construct in [direct_proof_boundary.md](direct_proof_boundary.md),
and it does not widen the certified subset.

Lane choice is ordered, not preferential:

1. If an IR arm and a non-empty Lean denotation exist, the direct-proof path is the only path
   that can move a construct to **directly provable**; promotion requires all four conditions in
   [direct_proof_boundary.md](direct_proof_boundary.md) §6.
2. If the symbol's pure body is materializable, the carried-body attach mode is preferred over a
   constructed model — the model then IS the original body, and no model↔original gap is
   introduced ([nim_stew_base36_sidecar_contract.md](nim_stew_base36_sidecar_contract.md) §4
   D2, §5).
3. Only when the symbol has no materializable pure body (a template, an unsupported declaration
   kind, a stream-coupled gate, or a boundary construct) may the constructed-model +
   replay-observation lane be used.

The adopted-model lane is not a substitute for a direct proof, and it is not a weaker spelling of
one. Its claim is exactly the two propositions in §3.

## 2. Subject-suitability criteria (decision rule)

A subject is eligible for this lane only when all six criteria hold. Any miss means the subject is
outside Axiom's current claim surface — not refuted, and not silently accepted.

1. **Read-only, byte-exactly pinned subject.** The subject tree is never written (Zero-Footprint),
   and the governing module's bytes must hash to the pinned `blobSha256` at the pinned commit/tree.
   A pin mismatch blocks the run (fail-closed) —
   [nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md) §3.1
   (`verifyLibp2pBytesviewSubjectPin`), [toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md)
   §2, [nim_stew_base36_sidecar_contract.md](nim_stew_base36_sidecar_contract.md) §2.
2. **No materializable pure body.** The subject symbol is a template
   ([nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md) §3), a
   stream-coupled or unsupported declaration kind
   ([toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md) §2), or another
   construct outside the certified extraction subset. If a pure body is materializable, criterion
   §1's second lane choice applies instead.
3. **Explicit, hash-bound adoption.** The proposition lives in an Axiom-owned overlay or sidecar
   with `soExplicit` origin, and the loader recomputes the proposition's identity and compares it
   byte-exactly with the adoption record —
   [nim_stew_base36_sidecar_contract.md](nim_stew_base36_sidecar_contract.md) §2,
   [jrpc_errcode_class_binding_contract.md](jrpc_errcode_class_binding_contract.md) §2.
   Adoption authority is an explicit human architect act recorded in the adopted artifact; a hash
   match, a PR head, or an agent is not adoption authority —
   [jrpc_errcode_class_binding_contract.md](jrpc_errcode_class_binding_contract.md) §2.1.
4. **Constructed carriers, not extraction claims.** When the model is constructed, the EA
   (extraction-agreement) slots must be empty and the constructed-model binding digests must be
   canonical; a filled EA leg is a fabricated measurement and is rejected —
   [obligation_semantics.md](obligation_semantics.md) §2.1a-4.
5. **Stamped observation is constructible.** A harness can call the ORIGINAL symbol (import,
   include splice, or the lane's documented call form), and the observation is a concrete value
   delimited by the replay protocol —
   [nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md) §4,
   [toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md) §5,
   [jrpc_errcode_class_binding_contract.md](jrpc_errcode_class_binding_contract.md) §6.
6. **Control carrier exists and is expected UNSAT.** The control is a solver-level injection guard,
   not a subject observation; a control SAT indicts the spec injection and fails the run closed —
   [nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md) §5,
   [toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md) §2,
   [nim_stew_base36_sidecar_contract.md](nim_stew_base36_sidecar_contract.md) §6.

## 3. The two claims and the standard non-claims

Every lane in this shape carries two distinct propositions over the same subject, claim, and input
set, bound by one canonical manifest when the lane defines one —
[jrpc_errcode_class_binding_contract.md](jrpc_errcode_class_binding_contract.md) §1.1:

- **(i) `Model ⊨ Specification_subset`** — the adopted model satisfies the adopted specification
  subset. This is a model-consistency claim; it is not a claim about the original implementation's
  execution meaning. The solver or kernel checks this proposition.
- **(ii) `∀x ∈ I, Observe(Source, x) = Expected(Model, x)`** — on the pinned original symbol, each
  input in the finite, enumerated set `I` produces the model's expected value. This is a finite
  observation, not a universal theorem over the input space.

Neither claim implies the other. `Model ⊨ Specification_subset` does not imply the observations;
an observation match does not imply the model or the specification. **Hash identity ≠ model
correctness ≠ theorem truth** — a byte-exact adoption hash proves content identity only
([jrpc_errcode_class_binding_contract.md](jrpc_errcode_class_binding_contract.md) §1.1).

The honest limit is common to all lanes: **the solver verifies the ADOPTED MODEL, not the
subject**; the subject's connection to a verdict is the stamped replay harness observation alone
([nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md) §3;
[toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md) §3).

Standard non-claims (every lane contract in this shape must carry all applicable bullets; lane
additions are allowed, omissions are not):

- NOT a claim that the pipeline extracted, translated, or verified the original body — the model is
  CONSTRUCTED IR (or, for the carried-body mode, the body is carried without an extraction claim);
  the subject connection is the stamped replay observation only.
- NOT a universal theorem. The claim is limited to the pinned carriers, the enumerated input set,
  and the pinned domain.
- NOT a memory-safety, race-safety, or whole-module correctness claim.
- NOT a modification of the subject — Zero-Footprint; the replay never writes into the subject
  tree.
- NOT a claim that authorship or a hash confers authority — authority is the explicit adoption act
  recorded in the adopted artifact.
- NOT a serialized `PROVED` verdict where the engine structurally cannot serialize one; the
  absence of a counterexample is not a positive theorem.
- NOT a re-derivation of the upstream specification text; the specification provenance and the
  adoption record are separate from this contract.

## 4. Observation fail-closed conditions

The observation is admissible only when all of the following hold. Any failure demotes the
outcome — it never produces a disproof or a proof.

| # | Condition | Required behavior | Authority |
|---|---|---|---|
| 1 | Overlay/sidecar present but malformed (shape, grammar, hash binding) | Block the run; absent is the only inert state | [toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md) §2; [nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md) §3.1 |
| 2 | Subject pin mismatch (commit/tree/module sha256) | Block the run | [toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md) §2; [nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md) §3.1 |
| 3 | Control carrier SAT | Fail the run closed; the indictment is the spec injection, not the subject | [nim_libp2p_bytesview_slice_contract.md](nim_libp2p_bytesview_slice_contract.md) §5; [toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md) §2 |
| 4 | Solver model does not bind every subject parameter | `rvUnavailable` (partial models are never replayed with default-filled inputs) | [counterexample_replay_adapter.md](counterexample_replay_adapter.md) §3.0 |
| 5 | Replay disagrees with the model, or is unavailable | Demote to inconclusive; never emit `PROPOSITION_DISPROVED` | [counterexample_replay_adapter.md](counterexample_replay_adapter.md) §1, §3.6 |
| 6 | Subject bytes or worktree identity drift across the run | `rvUnavailable` | [counterexample_replay_adapter.md](counterexample_replay_adapter.md) §3.5 |
| 7 | Concrete evaluation hits an operation outside the certified subset | `none` (fail-closed), never a manufactured refutation | [counterexample_replay_adapter.md](counterexample_replay_adapter.md) §3.5-§3.6 |
| 8 | Harness stamp is incomplete or ambiguous (`<lit>` count ≠ 1, unresolved slots) | Reject the synthesized harness | [jrpc_errcode_class_binding_contract.md](jrpc_errcode_class_binding_contract.md) §6; [toml_d2_agent_binding_contract.md](toml_d2_agent_binding_contract.md) §5 |
| 9 | Self-witness probe substitutes for the real subject | Forbidden; the observation must come from the pinned original symbol | [replay_evidence_policy.md](replay_evidence_policy.md) §7 |

A confirmed disproof is a quartet — subject, input, violation, replay — whose replay verdict is
`rvAgree`; a missing field or a `rvDisagree`/`rvUnavailable` replay is not a valid counterexample
([jrpc_errcode_class_binding_contract.md](jrpc_errcode_class_binding_contract.md) §5.1,
[bug_verdict_glossary.md](bug_verdict_glossary.md) §2.2).

## 5. Tradeoff against the direct-proof path

| | Direct proof | Adopted model + stamped observation |
|---|---|---|
| What is proved | The emitted Lean denotation of the subject body, kernel-checked | The adopted model (`Model ⊨ Specification_subset`) plus a finite observation of the original symbol |
| Coverage | Only constructs with an IR arm and a non-empty denotation | Symbols with no materializable pure body, or outside the extraction subset |
| Subject connection | The subject body is the proof's subject (up to the documented denotation relation) | Only the stamped replay observation; no extraction claim |
| Universal claim | The proposition over the certified subset | Never universal: pinned carriers, enumerated inputs, pinned domain |
| Cost / TCB | IR arm + denotation + obligation + kernel; no adoption record or harness | Adoption record + overlay/sidecar + two carriers + harness compilation + subject pin; the model↔original gap remains |
| Failure mode | Fail-closed when the construct is outside the subset | Fail-closed on adoption/pin/control/replay; an observation mismatch is inconclusive, not a proof |

Choosing the adopted-model lane never relaxes the direct-proof boundary; choosing the direct-proof
lane is mandatory whenever its four promotion conditions are met
([direct_proof_boundary.md](direct_proof_boundary.md) §6).

## 6. Changing this contract

- Adding a lane to this shape requires the six criteria in §2 and the observation conditions in §4;
  a lane that cannot satisfy them is a direct-proof-boundary question, not an adopted-model lane.
- Moving a construct into the direct-proof path is a contract amendment under
  [direct_proof_boundary.md](direct_proof_boundary.md) §6, not a documentation cleanup.
- This document creates no execution authority, no verdict vocabulary, and no new gate. The
  verdict producers and the replay adapter remain the authorities cited above
  ([authority_contract.md](authority_contract.md)).