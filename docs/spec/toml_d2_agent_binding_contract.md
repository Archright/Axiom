# nim-toml-serialization string-control-gate binding (toml d2-agent) — Product Contract

> **Status**: Committed product contract — the adopted agent-spec slice (`followup/d2-agent-vertical`)
> **Created**: 2026-10-17
> **AGENTS.md reference**: §0.12 (product contract precedes), §0.9 (theater prohibition), §0.3 (trust boundary), §0.2a (legislator LLM-only — not engaged here: the spec content is the p0d2g agent chain's adopted work product, not a legislator invariant), §4 (GUARDIAN)
> **Related**: [nim_stew_base32_rem_binding_contract.md](./nim_stew_base32_rem_binding_contract.md) (overlay/identity/carrier precedent), [nim_stew_base36_cout_contract.md](./nim_stew_base36_cout_contract.md) (C_out authority precedent), [authority_contract.md](./authority_contract.md), [obligation_semantics.md](./obligation_semantics.md)
> **Spec registry**: `SPEC-TOML-D2-AGENT` — binding overlay `config/spec/toml_d2_agent_spec.json` (soExplicit); adopted spec content `experiments/act2-wp-toml-b1-input-integrity/p0d2g/AGENT_SPEC.md`

---

## 1. Scope and spec identity

**Subject**: `toml_serialization/lexer.nim` of an **unmodified** clone of status-im/nim-toml-serialization @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (READ-ONLY; `git -C <subject> status --porcelain` must remain empty at all times — Zero-Footprint Integrity). Subject pin: module blob sha256 `19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d` at the pin; governed symbols `scanString` (dispatcher, :607), `scanSingleLineString` (:565), `scanMultiLineString` (:468); grounding lines `75, 554, 588`.

**Adopted claim (S2)** — a set-membership theorem over one raw byte value `c` inside a basic string:

```
S2:  ∀ c ∈ D:  reject(c) = forbid(c)

D          = { c | (c ≥ 1) ∧ (c ≤ 255) ∧ (c ≠ 10) ∧ (c ≠ 13) ∧ (c ≠ 34) ∧ (c ≠ 92) }
forbid(c)  = (c ≤ 8) ∨ (c ≥ 10 ∧ c ≤ 31) ∨ (c = 127)
reject(c)  = (c = 8) ∨ (c = 16) ∨ (c = 31) ∨ (c = 127)   [defect carrier]
```

**Hard constraint, as in the predecessor bindings**: the binding closes with EXISTING machinery — no new verifier, no new verdict authority, no new merge authority, no new gate. The overlay follows the C_out authority pattern exactly (`explicitSpecFromOverlay` pins `soExplicit`, fail-closed on anything else; a PRESENT file with parse/shape failure blocks `ax prove`). **Presence amendment (2026-10-17, two-PR landing)**: unlike the three predecessors, the overlay's presence is OPTIONAL at the `prepareProofRun` call site — an absent file logs an explicit inert-binding line and the run proceeds. Reason: ADR-0025 Amendment F landing discipline — the overlay is a NON-closure companion (`config/spec/**`) and cannot land atomically with the closure-member engine changes, so the binding rides two sequential PRs (engine rotation PR first, this spec/records PR second). The loader itself is unchanged: present-but-malformed stays fail-closed.

**Subject-pin enforcement amendment (2026-10-23)**: the subject pin is a REAL check. The loader-validated `subject.blobSha256` is carried into the domain and verified at run time against the governed module's actual bytes under the run's subject root (`verifyTomlD2AgentSubjectPin`, the sidecar and nim-libp2p lanes' pattern): a tree that presents `toml_serialization/lexer.nim` with any other content fails the run fail-closed ("the claim was not adopted for these bytes"), and a tree without the governed module keeps the binding inert (the routing gate could never match it either). The lane's historical format-only 64-hex validation is retired.

**specOrigin = soExplicit justification**: the claim's content is agent-authored (§6), so it has NO in-band authority in the subject tree or from any upstream document; the only origin that authorizes verification of an out-of-tree claim is an explicit Axiom-owned adoption. The overlay is the single legitimate home of the claim, and the adoption act is user-approved (§6).

## 2. The two carriers and their grounding

Unlike the three predecessor overlays, the carriers are **CONSTRUCTED IR**: the original gates are stream-coupled (`lex.next` advances state) and are deliberately not carried as bodies. Each carrier is a bool-valued predicate over one BitVec64 byte variable (boolean results are native to the IR — `irTypeBool`, comparisons, `and`/`or`; the claim post is a Bool equality and is concretely evaluable on the observed raise-boolean).

**Defect carrier `d2StringGateReject`** — the code's actual single-line gate, machine-extracted from the subject bytes:

```nim
lexer.nim:587-589 (inside scanSingleLineString, :565):
    if next in {CR, LF, EOF}:
      raiseTomlErr(lex, errUnterminatedString)
    if ord(next) in {8, 16, 31, 127}:
      raiseInvalidChar(lex, next)
```

Body: `(c == 8) or (c == 16) or (c == 31) or (c == 127)` — the four-member equality gate, exactly the set literal at :588. **SAT expected**: every forbid member outside `{8,16,31,127}` (e.g. c = 7) refutes it.

**Control carrier `d2CommentGateReject`** — the repository's own correctness set:

```nim
lexer.nim:75:
  invalidCommentChar = {'\x00'..'\x08', '\x0A'..'\x1F', '\x7F'}
```

Body: forbid exactly — set-equal to the adopted forbid on D. **UNSAT expected**; a control SAT would indict the spec injection itself, not the subject. The control's use-site is `lexer.nim:224` (`elif next in invalidCommentChar:` inside `nonws`, :200).

**Differential design**: defect SAT + control UNSAT together prove a **set-gap defect** (members `{1..7, 11, 12, 14, 15, 17..30}` within D), not a blanket gate failure. The carriers' `carriers` overlay block records the per-carrier grounding symbol (`scanSingleLineString` / `nonws`) and lines (`588` / `75`); the derivation digest folds `d2-gate-model-v1|rule=<ruleId>|grounding=<module>:<lines>` into the §2.1a parse-bound components.

## 3. Model↔original correspondence — evidence and limits

**What is evidence-backed** (AGENT_SPEC.md §5/§9/§10, all citations byte-verified against the pin):
- `:588` is the ONLY control-char decision inside the `scanSingleLineString` loop; `:583-586` are the structural exits (delimiter, CR/LF/EOF) outside the gate — this is a static-reading argument, not a formal proof.
- The UTF-8 validator accepts 0x00–0x1F wholesale (`private/utf8_validate.nim:17-18`), so decode's success/failure on `k = "a⟨c⟩b"` is decided exactly by `:588`.
- The public API path `parseValue` `of '"'` (`:1805-1811`) reaches the gate directly via `scanString` → `scanSingleLineString` — the replay observation is one `Toml.decode` call away.
- c=0 (NUL) is excluded from D: `EOF* = '\0'` (`:72`) makes NUL an **accidental** rejection path via :586, not a gate member.

**What is NOT formally verified** (deliberately): the correspondence itself. The solver verifies the **ADOPTED MODEL**; the replay observes the **ORIGINAL decoder**. Nothing in the pipeline claims that the IR carrier IS the subject's body — the §2.1a extraction differential measures `EA_UNSUPPORTED` on the generic gate procs (verified 2026-10-17: `unsupported AST node (ckVarTy)`), the legs record that honest unmeasurability, the canonical seal declines with that sealError, and the BMC lane decides the model. No certificate attests an extraction that did not happen.

**Auxiliary, not primary**: the multi-line gate `lexer.nim:554` (`if ord(next) in {16, 31, 127}:` inside `scanMultiLineString`, :468) is the same defect family with a smaller reject set (missing 8); it grounds the auxiliary counterexample `k = """a\x08b"""` but is not a separate carrier in this slice.

## 4. Synthesis contract (D1–D4)

`synthesizeTomlD2AgentCandidate` (`src/cli/axiom_engine.nim`) synthesizes the carrier pair per governed hit, following the C_out D1–D4 pattern:

1. **D1 (load)**: `config/spec/toml_d2_agent_spec.json` read through `explicitSpecFromOverlay` — origin pinned to `soExplicit`; required ownership/provenance/subject-pin/carrier-grounding blocks validated fail-closed; canonicalSpecIR must state EXACTLY nine clauses (two domain bounds, four structural exclusions, the forbid definition, the defect gate definition, the control definition) and the control clause must be **set-equal to the forbid clause** (the spec-injection guard). Presence-optional in `prepareProofRun` (see the presence amendment in §2 — absent = logged inert, present-malformed = fail-closed); the routing branch is last and gated on the subject module path, so it is inert for every other subject tree.
2. **D2 (construct)**: both carriers are built directly in IR from the parsed overlay (no subject materialization): defect body = the four-member equality gate; control body = forbid; preconditions = the domain conjuncts (OPEN obligation over c, so the SAT model binds c and the exact-input gate, P4 pre-revalidation, and the replay can fire — 닫힌 명제 금지).
3. **D3 (claim shape)**: postcondition = `result == forbid(c)` β-spliced to the carrier body exactly once (fail-closed splice count + free-variable guard): the defect claim is `gate(c) == forbid(c)`, the control claim degenerates to `forbid(c) == forbid(c)`. `translationLossFree`/`propositionRegionLossFree`/`bindingUniverseComplete` are the constructed carrier's own honest bits (nothing was translated); the renderers and solver re-decide downstream, fail-closed.
4. **D4 (route)**: `overlayDeclaresD2AgentSubject` gates on `modulePath == toml_serialization/lexer.nim and fnName ∈ {scanString, scanSingleLineString, scanMultiLineString}`. One carrier pair per subject module per run (dedupe on both carrier names). The eligible DEFECT carrier is wave-faced under the examined symbol (the disproof attributes to the frontier node); the CONTROL carrier rides under its own name — its UNSAT is the differential's spec-injection guard.

Candidate names are the binding's kernel names `d2StringGateReject` / `d2CommentGateReject` — never subject symbols.

## 5. Replay binding — the ORIGINAL code decides

A confirmed disproof (BMC lane: SAT model → P4 → cvConfirmed → vsDisproved) is replayed against the ORIGINAL decoder through its public API. The synthesis stamps the harness template (with the `<module>` import slot fixed to the subject's public API module, `toml_serialization`) into the entry's parse-bound components; the replay adapter (Authority = 0, `counterexample_replay.nim`) renders the model's exact byte into the `<lit>` slot:

```nim
import toml_serialization
var observedReject = false
try:
  discard Toml.decode("k = \"a" & chr(<lit>) & "b\"", TomlValueRef)
except TomlError:
  observedReject = true
echo "AXIOM_REPLAY_BEGIN"
echo $observedReject
echo "AXIOM_REPLAY_END"
```

The echoed value is the ORIGINAL code's `reject(c)` observation: `true` iff the decoder RAISES on a document embedding the raw byte `chr(c)`. The replay postcondition is `result == forbid(c)` over that observation (derived fail-closed from the spliced claim's spec side), so **the observation — not the model — decides the agreement**: c=7 → observed `false` (accept), forbid(7) = `true` → propertyHolds = false → rvAgree; a gate member (c=16) → observed `true` = forbid(16) → property holds → rvDisagree (the anti-theater direction). Scratch-verified against the pristine subject (2026-10-17): c=7 → `false`, c=8 → `true`, c=9 (tab) → `false` — the AGENT_SPEC predictions exactly.

Subject integrity folds (exact commit, tree Merkle, module sha256 pre/post, porcelain check, GateEnvLock triple) are unchanged — the replay never writes into the subject tree.

## 6. Adoption provenance

- **Content authorship**: the blind-discovery + spec-inference agent chain (`p0d2g/discovery/agentA_raw.md`, `agentB_raw.md` — preserved verbatim; synthesis into `p0d2g/AGENT_SPEC.md`). **No human authored the content; this contract claims no human authorship of it.**
- **Authority for verifying against it**: explicit adoption — the user-approved slice plan plus this committed contract and overlay. The overlay's `claimOwnership.provenance` records the same split (content = agent chain; authority = adoption), and the validator requires those fields to be present (fail-closed).
- **Adoption record**: `experiments/act2-wp-toml-b1-input-integrity/p0d2g/FORMAL_EXPERIMENT.md` (committed with this contract).

## 7. Non-claims

- NOT a claim that the pipeline extracted or verified the original gate bodies (EA unmeasured on the generic gate procs — the canonical seal declines honestly; the BMC lane decides the adopted model).
- NOT a memory-safety claim.
- NOT a claim about key names, comments, multi-line newline rules, escape-sequence validity, or multi-byte UTF-8 behavior (AGENT_SPEC §9-1 scope).
- NOT a primary claim about the multi-line gate (:554) — auxiliary counterexample family only.
- NOT a claim that nim-toml-serialization was modified or annotated in-tree (Zero-Footprint).
- NOT a re-derivation of the TOML v1.1.0 compliance text — forbid's provenance is the compliance claim (`README.md:65`) plus the repository's own comment set (`:75`), per AGENT_SPEC §9-2.
- NOT a claim that the replay validates the model↔original correspondence in general — the replay observes ONE documented input family (`k = "a⟨c⟩b"`) on the pinned subject state.
