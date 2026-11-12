# nim-stew base36 proposition sidecar with hash-bound adoption — Product Contract

> **Status**: Committed product contract — the generic sidecar adapter slice (`followup/sidecar-adoption-binding`); **amended 2026-10-19** by the adoption evolution — blind agent A1's inferred law as the defect proposition, superseding the first adoption's instance (§8; `followup/sidecar-adopt-agent-proposition`)
> **Created**: 2026-10-19
> **AGENTS.md reference**: §0.12 (product contract precedes), §0.9 (theater prohibition), §0.3 (trust boundary), §0.2a (legislator LLM-only — not engaged here: the proposition content is the workstream's adopted instance pin, not a legislator invariant), §4 (GUARDIAN)
> **Related**: [nim_stew_base36_cout_contract.md](./nim_stew_base36_cout_contract.md) (C_out authority + attach precedent), [toml_d2_agent_binding_contract.md](./toml_d2_agent_binding_contract.md) (adoption provenance precedent + its audited gap), [authority_contract.md](./authority_contract.md), [obligation_semantics.md](./obligation_semantics.md)
> **Spec registry**: `SPEC-B36-SIDECAR` — sidecar `config/spec/nim_stew_base36_sidecar.json` (soExplicit)

---

## 1. Scope and spec identity

**Subject**: `stew/base36.nim` of **status-im/nim-stew**, pinned byte-exactly: module blob sha256 `b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8` at commit `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` — byte-identical between the upstream clone and the nimble pkgs2 `stew-0.5.0` store (both measured 2026-10-19). Governed symbol: `decodedLength` (`func decodedLength*(btype: typedesc[Base36Types], length: int): int`, body `(length * 179) div 277`). The subject tree is READ-ONLY at all times (Zero-Footprint Integrity).

**Adopted propositions** (closed grammar, one defect + one control instance over the ORIGINAL body):

```
defect:   length == 1  →  result == (length + 4)   (SAT expected — decodedLength(1) = 0 ≠ 5; the blind agent A1's law pinned at its suspected input — §8)
control:  length == 2  →  result == 1              (UNSAT expected — decodedLength(2) = 1; unchanged injection guard)
```

Superseded first-adoption defect (retained verbatim, no longer governing): `length == 3 → result == 2` — see §8.

**Hard constraint, as in the predecessor bindings**: the binding closes with EXISTING machinery — no new verifier, no new verdict authority, no new merge authority, no new gate. The sidecar follows the C_out authority pattern exactly (`explicitSpecFromOverlay` pins `soExplicit`, fail-closed on anything else). Presence is OPTIONAL at the `prepareProofRun` call site (Amendment F two-PR landing discipline — `config/spec/**` is a non-closure companion); a PRESENT-but-unreadable or rejected file blocks `ax prove`.

**specOrigin = soExplicit justification**: identical to the predecessor overlays — an out-of-tree claim over a READ-ONLY subject has no in-band authority; the only origin that authorizes verifying against it is an explicit Axiom-owned adoption. The sidecar JSON is the single legitimate home of the proposition.

## 2. Hash-bound adoption (the d2 lane's audited gap, closed)

"**Adoption = adoption (not authorship)**" ([toml_d2_agent_binding_contract.md](./toml_d2_agent_binding_contract.md) §1/§6) was documented for the d2 lane but never mechanically enforced: `explicitSpecFromOverlay` never compared any spec hash to an adoption record, `SpecID = H(sorted canonicalSpecIR | origin | ruleVersion)` (`src/core/trusted/specification_artifact.nim:45-48`) was computed but never checked, `adoptionRef` was only a non-empty string, and the subject `blobSha256` was only format-checked. This sidecar lane makes adoption BINDING, mechanically, in two loader stages (`validateSidecarOverlayNode`):

1. **Stage (i) — shape + grammar**: the authority path (`soExplicit` pin, `ruleId`/`ruleVersion`, non-empty `canonicalSpecIR`), the prose blocks (description, semanticCaveats, nonClaims), the adoption record's presence and format (hash = 64-hex, commit = 40-hex, blob = 64-hex, grammar pin), and the closed-grammar parse of every proposition clause (§3). All fail-closed.
2. **Stage (ii) — hash binding**: the loader RECOMPUTES the specification artifact's identity from the loaded proposition content — `specIdentity` over the loaded `canonicalSpecIR`, `soExplicit`, and `ruleVersion` — and compares it BYTE-EXACTLY with `adoption.adoptedSpecHash`. Mismatch ⇒ fail-closed error "**adoption does not bind the current proposition content**". Any post-adoption mutation of a clause, the ruleId, or the ruleVersion changes the identity and invalidates the adoption mechanically. (The identity is order-insensitive by the SpecID contract — content-as-set.)

**Adoption record fields** (`config/spec/nim_stew_base36_sidecar.json` → `adoption`): `adoptedSpecHash` (the SpecID of the exact proposition content), `adopter`, `adoptedAt` (date), `basis` (text refs), `grammarVersion` (pinned to `nim-sidecar-expr-v1` — this engine refuses any other grammar), subject pin `{source, module, symbol, commit, blobSha256}`, and `provenance` (the agent-authored chain; **content ≠ authority** — the authority is the adoption act: this committed, hash-bound record). The value parameter the propositions bind is declared document-level (`valueParam: "length"`) and is itself enforced at synthesis (§4).

## 3. The closed grammar — `nim-sidecar-expr-v1`

Pre AND post expressions share ONE closed grammar, sidecar-owned in `axiom_engine.nim` (`parseSidecarClosedExpr`), the same grammar family as the rust lane's `parseClosedSpecPost`:

```
expr     := additive ( "==" additive )?
additive := primary ( "+" primary )*
primary  := ident | NON_NEG_INT | "(" additive ")"
ident    := "result" | <declared valueParam>
```

- Operators: `+`, `==`, parentheses. **Closed**: no `*`, no `-`, no comparisons beyond `==`, no calls, no negative literals, no type tokens (idents start `[a-z_]`). Integer literals are non-negative int64 with overflow rejection. Anything else fails closed with a message naming the sidecar clause and the grammar version.
- IR family: `result`/value-param idents → `irVar` (BV64 at parse; the value param is RETYPED to the subject's real parameter type at synthesis), `+` → `irAdd`, `==` → `irEq`, literals → `irLit`.
- **Versioning**: `adoption.grammarVersion` must equal `nim-sidecar-expr-v1`. A document pinned to another grammar names a different contract and is rejected — a new grammar must ship with a new engine version (fail-closed both directions).

The frozen unsupported example: `result == length * 2` → parser rejection (trailing input after the equality — `*` is outside the grammar), the UNSUPPORTED path, never a crash.

## 4. Synthesis contract (D1–D4) — the C_out attach pattern

`synthesizeNimSidecarCandidates` (`src/cli/axiom_engine.nim`), per governed hit:

1. **D1 (load)**: the two-stage check of §2. Presence-optional at the call site; routing gated on the adoption's EXACT module+symbol key (`overlayDeclaresSidecarSubject`) — inert for every other subject tree.
2. **D2 (attach — original body carried)**: the subject symbol is materialized through the subject-scoped resolver (`materializeExternalIR`) and the carrier CARRIES the materialized body UNCHANGED as its own body — the C_out attach pattern. Scope guards (fail-closed): recursive body, let-bindings outside the pure-expression scope, a body that does not reference exactly one value parameter, and a value parameter whose NAME differs from the sidecar's declared `valueParam` ("the adoption does not bind this signature"). This last guard is part of the adoption semantics: a signature change is a content change the record does not pin.
3. **D3 (proposition)**: preconditions = the adopted pre (retyped); postcondition = the adopted post with `result` β-spliced onto a fresh clone of the original body — EXACTLY once (fail-closed splice count) — plus the free-variable guard (nothing beyond the value parameter). The carrier's formal list is the MODEL's variable set: exactly the one referenced value parameter. The original signature's remaining formals (the typedesc discriminator) are not value parameters — the solver cannot bind them, and the replay's exact-input gate requires every formal to carry a model binding (a retained formal demotes every replay fail-closed; measured 2026-10-19). The original signature stays pinned by the adoption's subject blob; the typedesc formal renders in the replay call as the MEASURED carrier token (§5). Carrier completeness bits mirror the C_out carrier: `translationLossFree`/`propositionRegionLossFree` = true (the carried region IS the original body, materialized whole under the scope guards), `bindingUniverseComplete`/`lossOutsideBindingRegions` carried from the materialization; the renderers and solver re-decide downstream, fail-closed. The entry declares `expectedObligation = true` (pre AND post are present) — a zero-obligation outcome is a scope mismatch, never a silent no-op.
4. **D4 (route + census)**: one carrier per proposition — `<symbol>_sidecar_defect` (wave-faced under the EXAMINED symbol; the disproof attributes to the frontier node) and `<symbol>_sidecar_control` (rides under its own name; its UNSAT is the differential's injection guard). Each carrier's parse bound is the §2.1a single-origin claim-carrier measurement (`measureClaimCarrierParseBoundComponents`: ONE EA leg on the original symbol + the deterministic derivation digest folding `nim-sidecar-expr-v1|rule=<ruleId>|kind=<kind>` + the measured typedesc carrier token).

**Routing precedence**: the sidecar arm precedes the C_out arm. Both govern the same frozen symbol (`stew/base36.nim` `decodedLength`); the sidecar's hash-bound adoption is the binding that mechanically pins BOTH the proposition content AND the subject bytes, so when its sidecar is present and validates, the adopted propositions govern the symbol. (Documented consequence: with the sidecar committed, the C_out carrier is superseded at the routing gate for this symbol; C_out synthesis remains fully exercised at the unit level.)

## 5. Model↔original correspondence — STRONGER than the d2 carriers

Unlike the d2 lane's CONSTRUCTED carriers, the model here IS the original function body: the solver decides the subject's own arithmetic over the β-spliced claim, and the replay observes the same body through the subject's real symbol. There is no adopted-model/original-code gap to bridge by evidence: the carrier body is a structural clone of the materialized original (same bytes → same IR translation pipeline).

**Replay form** (S6 single-origin shape, unchanged machinery): the measured typedesc token renders the call as

```nim
decodedLength(Base36Types, <length>)
```

`btype: typedesc[Base36Types]` is a static discriminator, NOT a value parameter: it never appears as an `irVar`, the propositions bind only `length`, and the replay adapter composes `outer(<carrier>, <valueLit>)` = `decodedLength(Base36Types, 1)` under the current generation (the same C_out replay call shape; generation 1 pinned `decodedLength(Base36Types, 3)`). Subject integrity folds (exact commit, tree Merkle, module sha256 pre/post, porcelain check, GateEnvLock triple) are unchanged — the replay never writes into the subject tree.

## 6. Replay expectations (frozen per adoption generation)

- **Defect** (`length == 1 → result == (length + 4)`, current generation): solver SAT (model binds length=1), P4-promoted, replay calls `decodedLength(Base36Types, 1)` → observed `0` → the claim `0 == (1 + 4)` fails concretely → `propertyHolds == false` → `rvAgree` → PROPOSITION_DISPROVED payload (exact commit + `input.length=1` + `propertyViolated=` SMT projection of `((1*179) div 277) == (1 + 4)` + `replay.verdict=rvAgree`). The payload refutes the ADOPTED LAW at the pinned instance — the same bifurcation shape as the first generation (superseded: model bound length=3, observed `1`, claim `1 == 2`).
- **Control** (`length == 2 → result == 1`): solver UNSAT — the injection guard. A control SAT would indict the spec injection, not the subject (rides the same z3 machinery; exercised by the frozen experiment, not re-run in unit tests).

## 7. Non-claims

- NOT a claim that `decodedLength` is incorrect, or that the inferred law `result == (length + 4)` is correct, for any input outside the pinned defect instance (`length == 1`); the propositions are INSTANCE obligations, not a universal theorem. The first generation's instance (`length == 3 → result == 2`, hash `8e9564842090…`) is superseded history (§8), not a co-governing proposition.
- NOT an LLM/mined spec: `specOrigin` is pinned `soExplicit` by `explicitSpecFromOverlay`; any other declared origin fails closed.
- NOT a claim that the sizing docstring promised exactness — `decodedLength` is documented as an estimate; the defect instance is a measurement of where the estimate breaks, not an upstream-contract violation.
- NOT a memory-safety claim; NOT about `encodedLength`, `decode`, or any other base36 symbol.
- NOT a claim that nim-stew was modified or annotated in-tree (Zero-Footprint).
- NOT a claim that authorship confers authority — the proposition content's provenance is the agent/workstream chain; the authority is the adoption act (hash-bound record + this contract).
- NOT a replay validation of the sizing formula in general — the replay observes ONE pinned input per case on the pinned subject bytes.

## 8. Adoption evolution — amendment of 2026-10-19 (blind agent A1's own proposition adopted)

**What changed.** The DEFECT proposition was re-adopted from a different source: the committed sidecar now carries the law independently inferred by a frozen blind-discovery agent, superseding the first adoption's C_out-pinned instance. The CONTROL proposition, the subject pin (module bytes, commit `1853f20b…`, blob `b8a42a6a…`), `ruleId`, `ruleVersion` (`1.0.0`), `specOrigin` (`soExplicit`), and the grammar pin (`nim-sidecar-expr-v1`) are UNCHANGED. History is retained, not rewritten — this section IS the record of the supersession.

**Source — the frozen blind-discovery run** (`experiments/sidecar-adoption-e2e/FREEZE.md` protocol; two zero-context agents on the READ-ONLY nim-stew clone @`1853f20b`, no access to Axiom sources, overlays, or prior base36 evidence):

- **Agent A1** independently located `stew/base36.nim::decodedLength` and inferred the proposition **`result == (length + 4)`** — closed-grammar expressible, grounded in `stew/base58.nim:55-58` (identical docstring `length + 4`), `stew/base36.nim:134-138` (decode requirement `payload.len + 4`), `tests/test_base36.nim:84-85`; suspected input `length = 1` → returns 0 where the law demands 5.
- Agent A2 missed this function (delivered low-confidence endians2 candidates) — recorded as-is.

**Schema finding (empty pre is NOT allowed).** The loader requires a non-empty pre AND post per proposition (`validateSidecarOverlayNode`: "the <kind> proposition needs non-empty pre and post", `src/cli/axiom_engine.nim`). The "general law with no pre" shape is therefore NOT schema-expressible; the adopted defect carries the MINIMAL grammar-expressible pre — the agent's own suspected input `length == 1` — so the model binding is deterministic and the replay's exact-input path is pinned (`decodedLength(Base36Types, 1)`). The post is adopted VERBATIM.

**Hash chain (recomputed, never hand-hashed).**

| generation | propositions (defect / control) | specIdentity (= `adoptedSpecHash`) |
|---|---|---|
| 1 (superseded) | defect `length == 3 → result == 2`; control `length == 2 → result == 1` | `8e9564842090127b261c30fdd95db095957ad2628fb5a35e4c4016673441e3be` |
| 2 (current) | defect `length == 1 → result == (length + 4)`; control `length == 2 → result == 1` (unchanged) | `3f55eaa79f3708894a04d62bc7ac32c9e2a8fe84d4f575348318d7290d237ea8` |

The generation-2 hash was computed through the SAME trusted code path the loader enforces — `explicitSpecFromOverlay` + `specIdentity` (`src/core/trusted/specification_artifact.nim:45-48`, `SpecID = H(sorted canonicalSpecIR | origin | ruleVersion)`) — by a `nim r` snippet importing the trusted module, cross-checked against the loader's own stage-(ii) mismatch diagnostic ("the loaded proposition computes …") and an independent sha256 of the identical identity string; all three agree byte-exactly. Generation-1's superseded hash is retained above and inside the new adoption record's `provenance` — the record shows its own evolution. The loader's stage-(ii) check makes the supersession self-enforcing: any content still pinning generation-1's hash now fails closed with "adoption does not bind the current proposition content".

**Authority unchanged.** Adoption = authority, still: agent A1 authored the CONTENT; the authority to verify the subject against it is the explicit adoption act — this committed, hash-bound record (§2). The first adoption's basis (the C_out slice ground truth) remains in the git history of this file and of `config/spec/nim_stew_base36_sidecar.json`.
