# VS-2 Design Specification — External-Subject Binding Registry

**Deliverable**: `REGISTRY_SPEC.md` (this file — the only artifact of VS-2's design phase).
**Worktree**: `/tmp/axwt_vs2`, branch `design/vs2-registry`, base `origin/main` = `1c5c51666a1aaefbbe6a556f2f579eabff4c5c59` (verified: `git rev-parse HEAD` == `git rev-parse origin/main`).
**Subject under design**: `src/cli/axiom_engine.nim` (5,381 lines, verified `wc -l`), the six external-subject binding lanes and their hard-coded dispatch.

**Verification status of the audit anchors**: every `file:line` cited below was re-read in this worktree and matches the audited footprint. Three tiny corrections: `probeSubjectIdentity` starts at line 2709 (the C_out path read the audit dated "~2717" is the `readJsonFile(Base36CoutOverlayPath)` at 2717); `buildBugVerdictDisplayJson` starts at 2737 (C_out path read at 2750); the comment header "Fifth … overlay" is duplicated (bv at 1809, sidecar at 2304) — both die in this migration. The `verifyTomlD2AgentSubjectPin` docstring at 2274-2275 still claims the lane "only format-checks" the blob while the code (2276-2298) performs the real byte-hash check — stale comment, removed by the pin-merge.

**Constitutional anchors honored**: §0.12 (product contract precedes implementation — this document is the committed contract for the slice); §2.5 (CI self-bootstrap — every per-lane PR is a coherent-generation rotation with its TWS/epoch-manifest pin re-anchor, per ADR-0032/0033 `TWS/epoch-manifest` pin-rotation discipline, `src/cli/merge_cli.nim:284` names `config/policy/epoch_manifest.json` as one leg of the pin-atomicity triple); §0.9 (no theater — the registry must not become a gate that "looks generic" while a hidden per-lane if-chain remains; §7 specifies structural, not cosmetic, evidence); §0.11 (lexicon: "lane" = one external-subject binding overlay; "carrier" = a synthesized constructed-IR symbol; "capability" = the taxonomy discriminator below).

---

## 0. Verified footprint (the six lanes, post-audit)

| # | Lane | Capability | Path/consts | Domain type | Loader | Pure validator | Membership | Synthesizer | Routing | Pin |
|---|------|-----------|-------------|-------------|--------|----------------|-----------|-------------|---------|-----|
| 1 | base36 sizing (β-composition) | β-composition | `axiom_engine.nim:860-868` | 872-885 | 951-1011 | inline in loader | 1013-1016 | 3562-3748 | — | — |
| 2 | base32 rem (term-splice) | term-splice | 1033-1040 | 1042-1052 | 1095-1152 | inline | 1154-1158 | 3750-3972 | — | — |
| 3 | base36 C_out (body-carry) | body-carry | 1179-1186 | 1188-1201 | 1233-1243 | 1226-1231 fwd + 1245-1313 | 1315-1320 | 3974-4132 | — | — |
| 4 | toml d2-agent (constructed-gate) | constructed-gate | 1349-1380 (incl. harness template 1364-1380) | 1491-1518 | 1627-1638 | 1620-1625 fwd + 1640-1742 | 1744-1755 | 2983-3162 | 1757-1775 | 2270-2298 |
| 5 | nim-libp2p bytesview (arithmetic-law) | arithmetic-law | 1838-1876 (incl. harness template 1865-1876) | 1947-1975 | 2085-2098 | 2079-2083 fwd + 2100-2199 | 2201-2211 | 3164-3343 | 2213-2238 | 2240-2268 |
| 6 | nim sidecar (hash-bound adoption) | body-carry | 2332-2340 | 2342-2391 | 2585-2598 | 2578-2583 fwd + 2600-2678 | 2399-2404 | 3345-3560 | — | 2680-2707 |

Shared machinery (verified, stays put unless noted):
- Dispatch: unconditional loader calls `axiom_engine.nim:4796-4907`; the 6-arm semantic chain in the `isEligible` closure **4944-5026** (registry-hit 4947, sidecar 4963, C_out 4972, sizing 4981, rem 4990, d2 5002, bv 5015, fallback `classifyExternalCandidate` 5025); target routing 5039-5098 (d2 canonical 5040-5058, bv canonical 5059-5080, bv **bare** 5081-5097).
- `PreparedRun` overlay fields 4582-4604; `classifyExternalCandidate` 4134-4171.
- Free-var guard `collectFreeNames` 2856-2898; β-splice `substituteParamUse` 2904-2975 + `cloneIRExpr` 2977-2981 — **shared, stay**.
- Completeness-evidence dual-write block, byte-identical ×6: 3080-3084 (d2), 3264-3268 (bv), 3491-3495 (sidecar), 3699-3704 (sizing), 3923-3927 (rem), 4082-4086 (C_out).
- Replay harness stamps: d2 3101-3105, bv 3285-3289 (`parseBound.replayHarnessTemplate = <template>.replace(ReplayModulePlaceholder, domain.importModule)`); placeholder consts `src/verification/counterexample_replay.nim:151` (`<module>`) and `:155` (`<lit>`); renderer consumes `SubjectParseBoundComponents.replayHarnessTemplate` (`src/verification/obligation/canonical_verification.nim:1108`) at `counterexample_replay.nim:1174/1303/1322`.
- parseBound 3-shape correspondence gate `canonical_verification.nim:1434-1444` (claim-carrier-single-origin 1372-1393 / composite 1395-1416 / single-symbol 1418-1432); measurement procs `measureParseBoundComponents` 1151, `measureCompositeParseBoundComponents` 1216, `measureClaimCarrierParseBoundComponents` 1258; flags at 1081/1083; census classifier `classifyCandidateForCensus` `src/verification/obligation/candidate_eligibility.nim:458`.
- SpecID: `SpecificationArtifact.specIdentity` `src/core/trusted/specification_artifact.nim:45-49` — `sha256Hex(sorted(canonicalSpecIR).join("|") & "|" & $ord(origin) & "|" & ruleVersion)`; `explicitSpecFromOverlay` pins `specOrigin = soExplicit` fail-closed (same file, ~68+).
- C_out-only direct consumers: `probeSubjectIdentity` 2709-2735 (path read 2717), `buildBugVerdictDisplayJson` 2737-2853 (path read 2750).
- Lane-external: `sidecarCarrierName` 2393-2397, d2 IR builders 1777-1803, bv body grammar 1878-1945.

Regression assets (verified): `tests/unit/test_toml_d2_agent_binding.nim` (634 L), `tests/unit/test_sidecar_binding.nim` (639 L), `tests/unit/test_libp2p_bytesview_binding.nim` (648 L), `tests/unit/test_base36_cout_binding.nim` (412 L), `tests/cli/test_base36_composite_golden.nim` (152 L, golden Lean render), `tests/unit/test_base36_contract_policy.nim` (sizing S0/I4/I5), `tests/unit/obligation_subject_binding_test.nim` (486 L, binding-mode shapes). **base32 rem has no test anywhere** (`grep -rln "Base32Rem" tests/` → empty) — evidence gap, closed by PR-5 step 1. Suite invocation precondition (operations.md Trap 4): suites that exercise the extraction-agreement leg (`eaAgreed` assertions) require `(cd proofs && lake build ircheck)` in the tree under test, or `AXIOM_IRCHECK_CMD=<repo>/proofs/.lake/build/bin/ircheck`; absent ircheck they fail closed (sentinel -2) and read as `eaAgreed=false` — environment, not engine verdict. Run suites as `nim r tests/unit/<suite>.nim` (binary beside source; a binary living outside the repo escapes `findRepoRoot` to a CWD-relative `""` root — `docs/spec/nim_2_2_10_stdlib_quirks.md` Q-013).

`config/spec/` contains exactly the six overlays: `base36_sizing_relational_spec.json`, `nim_stew_base32_rem_spec.json`, `nim_stew_base36_cout_spec.json`, `toml_d2_agent_spec.json`, `nim_libp2p_bytesview_slice.json`, `nim_stew_base36_sidecar.json`.

---

## 1. Schema v2 JSON contract

One envelope per spec document under `config/spec/*.json`. Design constraint that shapes everything below: **the SpecID must not move.** `specIdentity` hashes exactly `sorted(canonicalSpecIR) | ord(specOrigin) | ruleVersion` (`specification_artifact.nim:45-49`). The v2 envelope is therefore *additive*: `canonicalSpecIR`, `specOrigin`, `ruleVersion` stay byte-identical to today, every legacy field keeps its name and value, and the six new envelope fields are additive keys the legacy validators never read. Consequence: a v2-migrated document still validates under the pre-migration engine (forward-run safety for the two-PR landing windows), and the sidecar's `adoption.adoptedSpecHash` (recomputed against the same three fields at `axiom_engine.nim:2666-2671`) still matches byte-for-byte after migration.

### 1.1 Field set

```jsonc
{
  // ── shared block (1:1 with today; byte-identical values) ──
  "specId": "string",                    // provenance label; NOT the SpecID (SpecID is computed, specIdentity)
  "specOrigin": "soExplicit",            // pinned fail-closed by explicitSpecFromOverlay
  "ruleId": "string",                    // binding-identity input for derivation digests; NEVER dispatched on (audit: ruleId exists but is never dispatched on — preserved)
  "ruleVersion": "string",               // SpecID input
  "contract": "docs/spec/<contract>.md",
  "description": "string",
  "canonicalSpecIR": ["clause", ...],    // SpecID carrier; lane grammars validate count+shape (§3)
  "semanticCaveats": ["string", ...],
  "nonClaims": ["string", ...],
  "subject": { "repository": "...", "module": "stew/base36.nim", "symbols": ["..."],
               "sourceLines": "...",
               "commit": "40-hex",       // required where the lane pins exact-commit (cout/d2/bv; sidecar pins it inside adoption.subject)
               "blobSha256": "64-hex" },
  // lane payload — exactly one of the five capability payloads (§3); legacy field names unchanged:
  //   constructed-gate: carriers[] + claimOwnership
  //   arithmetic-law:   carriers[] + claimOwnership
  //   body-carry:       claimConstant + canonicalDecisionVector (C_out) | adoption{} + valueParam + propositions[] (sidecar)
  //   term-splice:      (canonicalSpecIR only)
  //   β-composition:    theorem + certificateIdentity (present today, unread by engine — carried verbatim, still unread)

  // ── v2 envelope (additive; new keys) ──
  "capability": "constructed-gate | arithmetic-law | body-carry | term-splice | beta-composition",
  "presencePolicy": "mandatory | optional",
  "precedence": 10,                       // integer; lower = earlier in the dispatch cascade
  "constructedIrTargets": {               // present iff the lane synthesizes constructed-IR carriers addressable by --target
    "symbols": ["d2StringGateReject", "d2CommentGateReject"],
    "allowBare": false                    // true ⇒ a bare (non- module::) target name routes to this spec's module
  },
  "replay": {                             // present iff the lane stamps a replay harness (d2, bv in v2)
    "templateId": "d2-gate-reject-v1",    // key into the ENGINE-OWNED template registry — never template source
    "importModule": "toml_serialization", // materialized derivation; loader recomputes and cross-checks (§1.6)
    "observation": {
      "kind": "raise-bool",               // closed enum, §1.5
      "slots": ["<module>", "<lit>"]      // declared instance of the fixed vocabulary, §1.6
    }
  }
}
```

### 1.2 `capability` — the discriminator (5 kinds, closed)

| value | lane today | what it owns |
|---|---|---|
| `constructed-gate` | toml d2-agent | constructed-IR defect/control carriers over one variable; control≡forbid set-equality guard (engine-enforced today at 1713-1719); exactly-9 positional clauses (1659) |
| `arithmetic-law` | nim-libp2p bytesview | named-def law-as-data over a closed arithmetic body grammar `<v>`, `<v> ± <INT>` (1898-1923); exactly-6 positional clauses (2123) |
| `body-carry` | base36 C_out, nim sidecar | materialized ORIGINAL body carried into a synthesized carrier; single-origin claim-carrier parse-bound; result-slot β-splice |
| `term-splice` | base32 rem | claim bound onto the body's own `<param> mod <divisor>` term; exactly-3 positional clauses (1121-1123) |
| `beta-composition` | base36 sizing | β-composition of two materialized bodies into one relational composite; exactly the three sizing clauses (998-1000); pinned overflow goals (§6) |

An unknown `capability` value is a load error (§2.3) — it names a claim this engine version cannot state, the same fail-closed posture as `SidecarGrammarV1` (`axiom_engine.nim:2336-2340`).

### 1.3 `presencePolicy`

| value | lanes | absence | present-but-unreadable / malformed / rejected shape |
|---|---|---|---|
| `mandatory` | sizing, rem, cout | **blocks the run** (`axiom_engine.nim:4796-4810`: "base36 sizing binding overlay unavailable (fail-closed)") | blocks the run |
| `optional` | d2, sidecar, bv | explicitly-logged **inert binding** (4820-4823, 4853-4856, 4884-4887 — ADR-0025 Amendment F two-PR landing) | blocks the run |

This asymmetry is deliberate (audit risk) and is *data* in v2, but the two behaviors stay hard-coded in the one loader — the JSON chooses between them, it cannot invent a third.

### 1.4 `precedence`

Integer; the registry dispatches ascending. Assigned to reproduce the current chain order exactly (`axiom_engine.nim:4963/4972/4981/4990/5002/5015`):

| lane | precedence | load-bearing relations |
|---|---|---|
| sidecar | 10 | sidecar < cout, sidecar < sizing — all three govern `stew/base36.nim::decodedLength`; the hash-bound adoption must win when present (comment 4952-4958) |
| cout | 20 | cout < sizing — the C_out carrier would be unreachable if the sizing composite branch captured the hit first (comment 4959-4962) |
| sizing | 30 | — |
| rem | 40 | disjoint module; distinct value suffices |
| d2 | 50 | disjoint module; last-two placement preserved |
| bv | 60 | disjoint module; last placement preserved |

Tie rule: two entries with **equal precedence whose governed (module, symbol) sets intersect** = ambiguous subject matching ⇒ registry load fails (§2.3). Equal precedence with disjoint subjects is permitted (order between them is then immaterial and pinned by path order for determinism). The three `decodedLength` governors have distinct precedences, so today's cascade — including the fall-through-on-`err` behavior (`if synth.isOk(): return synth.value` at 4967-4968 etc.: `ok(false)` returns immediately, `err` falls to the next arm) — is reproduced by iterating ascending precedence and keeping exactly that return protocol.

### 1.5 `replay.observation` — the CLOSED observation grammar (v2)

**Allowed kinds, this milestone (exactly three):**

| kind | semantics | engine template | lanes |
|---|---|---|---|
| `raise-bool` | `try: discard <module-expr>(...)` / `except: observedReject = true`; echoes `true` iff the original raised | `d2-gate-reject-v1` (today's `D2AgentReplayHarnessTemplate`, `axiom_engine.nim:1364-1372`) | d2 |
| `single-call-int` | echoes the integer result of ONE call through the subject's public API | `bv-slice-len-v1` (today's `BvSliceLenReplayHarnessTemplate`, 1865-1869) | bv |
| `single-call-bool` | echoes the bool result of ONE call (no exception coupling) | `single-call-bool-v1` (added this milestone; exercised by the P0-1 test overlay; **no production lane declares it in v2**) | (test overlay) |

**FUTURE, explicitly NOT in v2**: `write-read-roundtrip` (observe a stateful write→read pair). It is named here so the enum's growth path is deliberate; a v2 document declaring it gets an explicit load error (§1.6 UNKNOWN rule). No v2 renderer accepts it.

**Fixed slot vocabulary — exactly three tokens, position-constrained:**

| slot | allowed positions | rendered |
|---|---|---|
| `<module>` | exactly once, in the leading `import` line | stamped at synthesis from `replay.importModule` (today: 3101-3105, 3285-3289) |
| `<lit>` | exactly once, inside the observed call's argument position | rendered at replay time from the solver model byte/int (today: `counterexample_replay.nim:1322`) |
| `<expr>` | **no position in v2** — reserved vocabulary for the VS-3 `write-read-roundtrip` kind | a v2 template containing `<expr>` is a registry load error |

**UNKNOWN / anti-injection rules (HARD):**
1. A spec names a `templateId`; it never carries harness SOURCE. The template body lives only in the engine-owned template registry — the new `external_subject_registry.nim` module (§2.1), its placeholder tokens keyed to `counterexample_replay.nim:148-159`'s consts (`ReplayBeginMarker`/`ReplayModulePlaceholder`/`ReplayValuePlaceholder`), which the renderer continues to own. Unknown `templateId` → explicit `UNKNOWN` load error.
2. Unknown `observation.kind`, unknown slot token, wrong slot count/position (validated structurally at load: `<module>` prefix of line 1; `<lit>` occurs exactly once thereafter) → explicit error whose message is `unknown observation kind "<kind>"` / `illegal slot "<tok>"` — never a fallback, never a best-effort render.
3. Values rendered into slots are solver-model integers rendered via Nim's `$` (int) — there is no path by which spec text reaches the harness source. This is today's property (`.replace` of fixed consts), made structural by removing per-lane templates from the lane adapters into the closed registry.

### 1.6 `replay.importModule` cross-check

Today the import module is *derived*, not stated: d2 = subject module's parent directory (1722-1727), bv = module path without extension (2179-2186). v2 states the value AND keeps the derivation: the loader recomputes the derivation from `subject.module` and fails closed on mismatch. Rationale: the derivation is a semantic invariant ("the replay imports the module that actually exposes the governed symbol"); stating it makes the document self-describing, recomputing it keeps the statement honest.

### 1.7 Migrated examples (one per existing lane; JSON skeletons)

**(a) base36 sizing — β-composition, mandatory, precedence 30** (`config/spec/base36_sizing_relational_spec.json`):

```jsonc
{
  "specId": "SPEC-B36-SIZING-RELATIONAL", "specOrigin": "soExplicit",
  "ruleId": "external:stew/base36/sizing-relational", "ruleVersion": "1.0.0",
  "contract": "docs/spec/base36_sizing_binding_contract.md",
  "description": "…unchanged…", "semanticCaveats": ["…unchanged…"], "nonClaims": ["…unchanged…"],
  "subject": { "repository": "status-im/nim-stew", "module": "stew/base36.nim",
               "symbols": ["decodedLength", "encodedLength"], "sourceLines": "…" },
  "canonicalSpecIR": ["0 <= n", "n <= 1000000", "decodedLength(encodedLength(n)) == n"],
  "theorem": "…carried verbatim (unread, as today)…",
  "certificateIdentity": "…carried verbatim (unread, as today)…",
  "claimOwnership": { "…unchanged…" },
  "capability": "beta-composition",
  "presencePolicy": "mandatory",
  "precedence": 30
}
```

**(b) base32 rem — term-splice, mandatory, precedence 40** (`config/spec/nim_stew_base32_rem_spec.json`):

```jsonc
{
  "specId": "…", "specOrigin": "soExplicit", "ruleId": "…", "ruleVersion": "1.0.0",
  "contract": "docs/spec/nim_stew_base32_rem_binding_contract.md",
  "description": "…", "semanticCaveats": ["…"], "nonClaims": ["…"],
  "subject": { "repository": "…", "module": "stew/base32.nim", "symbols": ["decodedLength"], "sourceLines": "…" },
  "canonicalSpecIR": ["0 <= length", "length mod 8 >= 0", "length mod 8 <= 7"],
  "theorem": "…", "certificateIdentity": "…", "claimOwnership": { "…" },
  "capability": "term-splice",
  "presencePolicy": "mandatory",
  "precedence": 40
}
```

**(c) base36 C_out — body-carry, mandatory, precedence 20** (`config/spec/nim_stew_base36_cout_spec.json`):

```jsonc
{
  "specId": "…", "specOrigin": "soExplicit", "ruleId": "…", "ruleVersion": "1.0.0",
  "contract": "docs/spec/nim_stew_base36_cout_contract.md",
  "description": "…", "semanticCaveats": ["…"], "nonClaims": ["…"],
  "subject": { "repository": "…", "module": "stew/base36.nim", "symbols": ["decodedLength"],
               "sourceLines": "…", "commit": "1853f20b…", "blobSha256": "b8a42a6a…" },
  "canonicalSpecIR": ["3 <= L", "L <= 3", "decodedLength(L) >= 2"],
  "claimConstant": { "K": 2 },
  "canonicalDecisionVector": { "input": "kzz", "L": 3 },
  "theorem": "…", "certificateIdentity": "…", "claimOwnership": { "…" },
  "capability": "body-carry",
  "presencePolicy": "mandatory",
  "precedence": 20
}
```

**(d) toml d2-agent — constructed-gate, optional, precedence 50, constructed targets, raise-bool replay** (`config/spec/toml_d2_agent_spec.json`):

```jsonc
{
  "specId": "…", "specOrigin": "soExplicit", "ruleId": "…", "ruleVersion": "1.0.0",
  "contract": "docs/spec/toml_d2_agent_binding_contract.md",
  "description": "…", "semanticCaveats": ["…"], "nonClaims": ["…"],
  "subject": { "repository": "…", "module": "toml_serialization/lexer.nim", "symbols": ["…"],
               "sourceLines": "…", "commit": "…", "blobSha256": "…" },
  "canonicalSpecIR": [ /* exactly 9 clauses, order-binding, unchanged */ ],
  "carriers": [ { "name": "d2StringGateReject", "kind": "defect",  "groundingSymbol": "…", "groundingLines": "…", "grounding": "…" },
                { "name": "d2CommentGateReject", "kind": "control", "groundingSymbol": "…", "groundingLines": "…", "grounding": "…" } ],
  "claimOwnership": { "…" },
  "capability": "constructed-gate",
  "presencePolicy": "optional",
  "precedence": 50,
  "constructedIrTargets": { "symbols": ["d2StringGateReject", "d2CommentGateReject"], "allowBare": false },
  "replay": { "templateId": "d2-gate-reject-v1", "importModule": "toml_serialization",
              "observation": { "kind": "raise-bool", "slots": ["<module>", "<lit>"] } }
}
```

**(e) nim-libp2p bytesview — arithmetic-law, optional, precedence 60, bare targets allowed, single-call-int replay** (`config/spec/nim_libp2p_bytesview_slice.json`):

```jsonc
{
  "specId": "…", "specOrigin": "soExplicit", "ruleId": "…", "ruleVersion": "1.0.0",
  "contract": "docs/spec/nim_libp2p_bytesview_slice_contract.md",
  "description": "…", "semanticCaveats": ["…"], "nonClaims": ["…"],
  "subject": { "repository": "…", "module": "libp2p/utils/bytesview.nim", "symbols": ["toOpenArray"],
               "sourceLines": "…", "commit": "…", "blobSha256": "…" },
  "canonicalSpecIR": [ /* exactly 6 clauses: 2 bounds + bvSliceLenLaw1/bvSliceLenActual/bvSliceLenLaw0/bvSliceLenControl defs */ ],
  "carriers": [ { "name": "bvSliceLenActual", "kind": "defect",  "…": "…" },
                { "name": "bvSliceLenControl", "kind": "control", "…": "…" } ],
  "claimOwnership": { "…" },
  "capability": "arithmetic-law",
  "presencePolicy": "optional",
  "precedence": 60,
  "constructedIrTargets": { "symbols": ["bvSliceLenActual", "bvSliceLenControl"], "allowBare": true },
  "replay": { "templateId": "bv-slice-len-v1", "importModule": "libp2p/utils/bytesview",
              "observation": { "kind": "single-call-int", "slots": ["<module>", "<lit>"] } }
}
```

**(f) nim sidecar — body-carry, optional, precedence 10, hash-bound adoption (SpecID stays byte-stable)** (`config/spec/nim_stew_base36_sidecar.json`):

```jsonc
{
  "specId": "SPEC-B36-SIDECAR", "specOrigin": "soExplicit",
  "ruleId": "external:stew/base36/sidecar-adoption", "ruleVersion": "1.0.0",   // ⚠ SpecID input — NEVER bump casually
  "contract": "docs/spec/nim_stew_base36_sidecar_contract.md",
  "description": "…unchanged…", "semanticCaveats": ["…unchanged…"], "nonClaims": ["…unchanged…"],
  "valueParam": "length",
  "canonicalSpecIR": ["length == 1", "result == (length + 4)", "length == 2", "result == 1"],  // ⚠ byte-identical
  "propositions": [ { "kind": "defect",  "pre": "length == 1", "post": "result == (length + 4)" },
                    { "kind": "control", "pre": "length == 2", "post": "result == 1" } ],
  "adoption": { "adoptedSpecHash": "3f55eaa7…", "adopter": "…", "adoptedAt": "2026-10-19",
                "basis": "…", "grammarVersion": "nim-sidecar-expr-v1",
                "subject": { "source": "…", "module": "stew/base36.nim", "symbol": "decodedLength",
                             "commit": "1853f20b…", "blobSha256": "b8a42a6a…" },
                "provenance": "…unchanged verbatim…" },
  "capability": "body-carry",
  "presencePolicy": "optional",
  "precedence": 10
}
```

Migration check for (f): `specIdentity` depends only on `sorted(canonicalSpecIR) | ord(soExplicit) | ruleVersion` — all three unchanged ⇒ `adoptedSpecHash` still validates at `axiom_engine.nim:2666-2671`. The migration PR asserts this by running the unchanged `test_sidecar_binding.nim` against the migrated file.

---

## 2. Registry & generic engine

**Module policy: minimal moves.** One new module owns the registry surface; everything else stays in `axiom_engine.nim` in its current sections. The synthesizers' *shared middle* (dedupe → evidence dual-write → census classify → wave rename → tri-state) is factored into one core proc *inside* `axiom_engine.nim`; the five capability-specific heads (clause grammars, materialization strategy) become the adapters (§3). Nothing in `src/verification/` changes except zero lines — the parse-bound 3-shape gate (`canonical_verification.nim:1434-1444`) is consumed as-is.

### 2.1 Module layout

| unit | gets | loses |
|---|---|---|
| `src/cli/external_subject_registry.nim` (NEW, ~400 L) | `RegistryEntry`, `ExternalSubjectRegistry`, capability enum, presence enum, observation enum, `loadExternalSubjectRegistry`, `verifySubjectBlobPin`, the closed replay-template registry (the two template consts move here from `axiom_engine.nim:1364-1380, 1865-1876`), envelope validation, precedence/ambiguity rules | — |
| `src/cli/axiom_engine.nim` | six adapters (`axiom_engine.nim` §3, replacing the six loader/validator/synthesizer regions in place), the synthesis core (§2.2, `publishExternalCandidate`), one dispatch loop (§2.7) | six path consts, six loader procs, six membership procs, three pin procs, duplicated validators, 6-arm chain, routing arms, 6 evidence tails |
| `src/core/trusted/specification_artifact.nim` | unchanged (`explicitSpecFromOverlay`, `specIdentity` consumed as-is) | — |
| `src/verification/obligation/canonical_verification.nim` | unchanged (`SubjectParseBoundComponents`, 3-shape gate, measure procs consumed as-is) | — |
| `src/verification/counterexample_replay.nim` | unchanged (renderer consumed as-is; template registry keys must match its placeholder consts 148-159) | — |
| `src/cli/merge_cli.nim`, `config/policy/epoch_manifest.json` | TWS/epoch pin rotation per landing PR (§2.5 discipline; not code change) | — |

### 2.2 Types and exact signatures

```nim
# ── src/cli/external_subject_registry.nim ──
type ExternalSubjectCapability* = enum
  capConstructedGate = "constructed-gate"
  capArithmeticLaw   = "arithmetic-law"
  capBodyCarry       = "body-carry"
  capTermSplice      = "term-splice"
  capBetaComposition = "beta-composition"

type PresencePolicy* = enum
  ppMandatory = "mandatory"
  ppOptional  = "optional"

type ReplayObservationKind* = enum
  obsRaiseBool      = "raise-bool"
  obsSingleCallInt  = "single-call-int"
  obsSingleCallBool = "single-call-bool"   # v2: test-overlay only

type ReplaySpec* = object
  templateId*: string                  # closed registry key; source never travels in JSON
  importModule*: string                # stated + recomputed + cross-checked (§1.6)
  observation*: ReplayObservationKind
  slots*: seq[string]                  # validated against the fixed vocabulary + positions

type ConstructedTargets* = object
  symbols*: seq[string]
  allowBare*: bool

type RegistryEntry* = object
  specRelPath*: string                 # normalized relative path under config/spec (identity for logs/evidence)
  specId*: string                      # document label
  ruleId*: string                      # carried; never dispatched on (preserves today's semantics)
  precedence*: int
  presence*: PresencePolicy
  capability*: ExternalSubjectCapability
  constructed*: Option[ConstructedTargets]
  replay*: Option[ReplaySpec]
  raw*: JsonNode                       # the full document; adapters validate their payload from THIS node only (no second semantic source)

type ExternalSubjectRegistry* = object
  entries*: seq[RegistryEntry]         # sorted by (precedence, specRelPath) — total, deterministic order

proc loadExternalSubjectRegistry*(specDir: string): Result[ExternalSubjectRegistry, string]
  {.raises: [], axiomDecision, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

proc entryFor*(reg: ExternalSubjectRegistry; capability: ExternalSubjectCapability): Option[RegistryEntry]
  {.raises: [].}
  ## Direct-consumer accessor (probeSubjectIdentity / buildBugVerdictDisplayJson §2.8).

proc replayTemplate*(templateId: string): Result[string, string] {.raises: [].}
  ## The closed template registry: "d2-gate-reject-v1", "bv-slice-len-v1", "single-call-bool-v1".
  ## Unknown id → err("UNKNOWN replay templateId ...") — never synthesized text.

proc verifySubjectBlobPin*(lane: string; moduleRelPath, expectedBlobSha256,
    subjectRoot: string): Result[bool, string] {.raises: [], axiomDecision,
    axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
  ## ONE pin-verify replacing verifyLibp2pBytesviewSubjectPin (2240-2268),
  ## verifyTomlD2AgentSubjectPin (2270-2298), verifySidecarSubjectPin (2680-2707).
  ## Body = the common logic those three already share verbatim:
  ##   module absent under subjectRoot → ok(false)  (binding inert on trees it does not govern)
  ##   unreadable                      → err(...)   (fail-closed)
  ##   sha256Hex(bytes) != expected    → err("... blob mismatch ... not adopted for these bytes")
  ##   else                            → ok(true)
  ## `lane` feeds only the error-message prefix ("toml d2-agent subject pin: ..."),
  ## preserving today's diagnostic specificity.
```

```nim
# ── src/cli/axiom_engine.nim — the synthesis core ──
type WaveRename* = enum
  wrSole        ## sizing/rem/cout: the single eligible entry rides the examined symbol's name
                ## (sizing 3728-3731, cout 4109-4113; rem same shape)
  wrDefectOnly  ## d2/sidecar/bv: DEFECT entry rides examinedFn; CONTROL rides its own name
                ## (d2 3126-3139, sidecar 3532-3543) — the differential's injection guard
                ## must stay addressable under the carrier name

proc publishExternalCandidate*(census: var ExternalCandidateCensus;
    candidateName, examinedFn, modulePath, subjectRepoRoot, sourceContent: string;
    composite: IRFuncDef; parseBound: SubjectParseBoundComponents;
    waveRename: WaveRename): Result[bool, string]
  {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
  ## The deduped tail of all six synthesizers, in the exact current order:
  ##   1. irDigest = computeDeterministicCasKey(serializeIRFuncDef(composite))
  ##   2. CompletenessEvidence{translationLossFree .. sourceBindingCount: composite.params.len,
  ##      irBindingCount: collectLetNames(body).len + composite.params.len}
  ##   3. saveEvidenceArtifact(irDigest, ev)                    (today ×6: 3080/3264/3491/3699/3923/4082)
  ##   4. discard saveCompletenessEvidenceDual(irDigest, composite,
  ##        measureCompletenessSourceCapture(...), ev)          (today ×6: 3083/3267/3494/3702/3926/4085)
  ##   5. record = classifyCandidateForCensus(entry, composite) ; census.records.add(record)
  ##   6. wave-facing rename per `waveRename` ; census.eligible.add(...)
  ##   7. logInfo accepted/excluded lines (field order preserved)
  ##   8. return ok(record.censusEligible)
  ## Dedupe is NOT here — it is adapter-owned (§3), because each lane's dedupe key and
  ## its ok(false)-on-duplicate semantics are capability-specific today and must not drift.
```

Capability adapter vtable (adapters live in `axiom_engine.nim`; the vtable type in the registry module):

```nim
type CapabilityPayload* = ref object
  ## Adapter-owned parsed projection. Keeps today's six domain objects UNCHANGED
  ## (minimal move): Base36OverlayDomain, Base32RemOverlayDomain,
  ## Base36CoutOverlayDomain, TomlD2AgentOverlayDomain,
  ## NimLibp2pBytesviewSliceDomain, SidecarDomain — one is populated per capability.
  case kind*: ExternalSubjectCapability
  of capConstructedGate: d2*: TomlD2AgentOverlayDomain
  of capArithmeticLaw:   bv*: NimLibp2pBytesviewSliceDomain
  of capBodyCarry:       cout*: Base36CoutOverlayDomain
                       sidecar*: SidecarDomain
  of capTermSplice:      rem*: Base32RemOverlayDomain
  of capBetaComposition: sizing*: Base36OverlayDomain

type CapabilityAdapter* = object
  capability*: ExternalSubjectCapability
  validate*: proc(node: JsonNode): Result[CapabilityPayload, string] {.raises: [].}
    ## The lane's pure validator, verbatim (today: validateTomlD2AgentOverlayNode 1640-1742,
    ## validateNimLibp2pBytesviewSliceOverlayNode 2100-2199, validateSidecarOverlayNode 2600-2678,
    ## validateCoutOverlayNode 1245-1313, and the loaders' inline validation 951-1011 / 1095-1152).
    ## Includes explicitSpecFromOverlay — the soExplicit pin stays inside each adapter.
  declares*: proc(payload: CapabilityPayload; fnName, modulePath: string): bool {.raises: [].}
    ## The membership predicate, verbatim (today: overlayDeclaresSubject 1013-1016,
    ## overlayDeclaresRemSubject 1154-1158, overlayDeclaresCoutSubject 1315-1320,
    ## overlayDeclaresD2AgentSubject 1744-1755 — carrier names included,
    ## overlayDeclaresLibp2pBytesviewSubject 2201-2211, overlayDeclaresSidecarSubject 2399-2404).
  routeTarget*: proc(payload: CapabilityPayload; target: string):
    tuple[routed: bool; fnName, modulePath: string] {.raises: [].}
    ## Constructed-target routing, verbatim (d2AgentCarrierTargetRouting 1757-1775 — canonical only;
    ## libp2pBytesviewCarrierTargetRouting 2213-2238 — canonical + bare). Lanes without
    ## constructedIrTargets get a `nil`-equivalent never-routing stub.
  synthesize*: proc(fnName, modulePath: string; payload: CapabilityPayload;
    resolver: ModuleContentResolver; census: var ExternalCandidateCensus;
    subjectRepoRoot: string): Result[bool, string]
    {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}
    ## The lane's capability-specific head; its tail is a publishExternalCandidate call.

const capabilityAdapters*: array[5, CapabilityAdapter]  # indexed by ExternalSubjectCapability
```

### 2.3 `loadExternalSubjectRegistry` — determinism and rejection rules

1. Enumerate `specDir` children matching `*.json`, **sorted by normalized relative path** (normalize: forward slashes, no `./`); the enumeration result is byte-stable across runs and platforms. Non-JSON files in the directory are ignored (config/spec holds only the six today; proven by `ls`).
2. For each file, in path order: parse JSON (failure ⇒ err with path), then envelope-validate:
   - `capability` ∈ the 5-kind enum, else `err("UNKNOWN capability ...")`.
   - `presencePolicy` ∈ {mandatory, optional}, else err.
   - `precedence` is a JSON integer ≥ 0, else err.
   - `explicitSpecFromOverlay` runs at envelope level, before adapter payload validation, and its `soExplicit` pin failure rejects the document exactly as every loader does today (951-1011 etc. all funnel through it).
   - **duplicate `specId`** ⇒ err naming both paths.
   - **ambiguous subject matching**: the entry's governed `(module, symbol)` set is computed from the payload (for `body-carry`: C_out `symbol` / sidecar `adoption.subject.module+symbol`; others: `subject.module` + `symbols`/`symbol`). Two entries with **equal precedence and intersecting governed sets** ⇒ err at load — this is the machine-checked version of the audit's "same module+symbol governed by two same-precedence overlays".
   - **malformed pins**: for entries whose capability payload declares `subject.blobSha256` (constructed-gate, arithmetic-law, body-carry) the 64-hex format check runs at load (today inside the validators, e.g. 1541-1545); the BYTE-verify stays deferred to run time (§2.4), because it is subject-root-scoped, not document-scoped.
   - **replay envelope** (§1.5-1.6): `templateId` resolves in the closed registry; `observation.kind` ∈ enum; slot list == the kind's declared positions; `importModule` == the recomputed derivation from `subject.module`; `constructedIrTargets.symbols` == the carrier names the payload's grammar requires (d2: 1597/1607 name-equality; bv: 2056/2065) — all mismatch ⇒ err.
3. Then, still in path order, run the capability adapter's `validate` on the raw node. A present-but-invalid document is an err **regardless of presencePolicy** (fail-closed, matching 4824-4826 / 4857-4859 / 4888-4890). Absence is evaluated per `presencePolicy`: a mandatory entry whose file is missing ⇒ err; an optional one ⇒ the entry is marked inert and the loader logs the exact inert line text used today (4821-4823 wording preserved).
4. Return `ExternalSubjectRegistry` sorted by `(precedence, specRelPath)`. The sort key pair is total ⇒ **same input directory ⇒ identical registry** (AGENTS.md §0.2 Deterministic).

`prepareProofRun` calls it once, at the top of the D1 block (replacing 4796-4907):

```nim
let regRes = loadExternalSubjectRegistry(repoRootConst() / "config" / "spec")
if regRes.isErr():
  return err("external subject registry unavailable (fail-closed): " & regRes.error)
prepared.subjectRegistry = regRes.value   # replaces the six prepared.*Overlay Option fields (4582-4604)
prepared.inertBindings = ...              # optional-absent specRelPaths, for the inert log lines
```

(For PR-0's dual-path period the six fields stay and BOTH paths load; see §5.)

**Root-resolution amendment (2026-11-08, docs-first per AGENTS.md §0.5)**: the production call site's `specDir` root — the `repoRootConst() / "config" / "spec"` join in the example above and in §4's seam paragraph — follows the **runtime root resolution** contract: `AXIOM_ROOT` env first, else the `findRepoRoot` anchor walk from the binary location (`.axiom_root`/`axiom.toml`, first anchor terminates; a tree-external anchor miss is a catalog read failure, fail-closed), per `docs/spec/productization_contract.md` §1b, `docs/spec/nim_effect_system_quirks.md` §12, and Q-013 (`docs/spec/nim_2_2_10_stdlib_quirks.md`). The loader seam itself (specDir as a parameter — the one design allowance) is unchanged: the seam is what makes the root-resolution swap a call-site change rather than an engine redesign. Source-tree behavior is preserved (AXIOM_ROOT unset + binary in the tree ⇒ the anchor walk reproduces the root the compile-time `repoRootConst()` baked in; today that join is the `defaultExternalSubjectSpecDir` const, `src/cli/external_subject_registry.nim:46`). Implementation lands in the follow-up rotation PR (closure-member files: `docs/guides/closure-fence-note.md`, `docs/evidence/rotation_preflight_prereg_2026-10-20.md`) — this note documents the contract ahead of it.

### 2.4 Pin verification — one proc, same call protocol

At dispatch-prep time (where 4835, 4866, 4898 sit today), for every loaded optional-capability entry whose governed module exists under this run's `sourceRoot`:

```nim
let pin = verifySubjectBlobPin(entry.specRelPath, governedModule, governedBlob, sourceRoot)
if pin.isErr(): return err(entry.specRelPath & " subject pin rejected (fail-closed): " & pin.error)
if pin.get: keep entry active
else:       logInfo(... "governed module not present under this subject root — binding inert: " & governedModule)
```

Semantics are byte-for-byte the three procs being deleted: absent module ⇒ inert ok(false); unreadable ⇒ err; hash mismatch ⇒ err with the measured-vs-pinned message (2262-2267, 2292-2297, 2701-2706). Mandatory lanes run no pin (they never had one — sizing/rem rely on the fail-closed loader; cout's blob is consumed by the §2.8 display path, unchanged).

### 2.5 Coherent-generation note (§2.5 CI discipline)

Each PR that moves a lane is an engine-rotation generation: it lands the code+registry flip and the TWS/epoch-manifest pin rotation **as one coherent generation** (`src/cli/merge_cli.nim:284` names `config/policy/epoch_manifest.json`; ADR-0032/0033 pin-rotation ritual). No PR mixes a half-flipped dispatch (some arms registry, some chain) with a stale pin. PR-0's dual-path period is the single sanctioned coexistence window because both paths decide identically and PR-0 changes no observable behavior (§5).

### 2.6 parseBound 3-shape preservation (non-conflation, HARD)

The registry touches nothing here — it only must not *collapse* the modes. Verified mapping, adapter → measurement → seal gate:

| adapter | parseBound producer | flags set | seal gate (`canonical_verification.nim:1434-1444`) |
|---|---|---|---|
| beta-composition (sizing) | `measureCompositeParseBoundComponents` (engine calls it at 3715-3716) | `synthesizedComposite=true`, ea2 leg | `validateCompositeLegs` 1395-1416 — BOTH legs agreed, distinct originals |
| body-carry (cout, sidecar) | `measureClaimCarrierParseBoundComponents` (cout 4099-4104, sidecar 3519-3522) | `synthesizedComposite=true, claimCarrierSingleOrigin=true` | `validateClaimCarrierLegs` 1372-1393 — ONE leg, ea2 MUST be empty |
| term-splice (rem) | `measureClaimCarrierParseBoundComponents` (single original, derivation digest `SidecarGrammarV1`-style rule string) | same single-origin | same |
| constructed-gate (d2) / arithmetic-law (bv) | `measureClaimCarrierParseBoundComponents` + `replayHarnessTemplate` stamp (3101-3105, 3285-3289) | single-origin + template | same + bespoke-harness replay path (`counterexample_replay.nim:1174/1303`) |

`obligation_subject_binding_test.nim` (486 L) asserts the three shapes; it is in EVERY flip PR's evidence list. The registry entry carries no binding-mode field on purpose: the mode is derivable from the capability (table above) and stating it twice would invite drift (AGENTS.md §1 — no duplicated semantic state).

### 2.7 The single dispatch site

`isEligible` stays a closure at the same site (4944) but becomes:

```nim
let isEligible = proc(fnName, modulePath: string): bool {.raises: [].} =
  if isRegistryEligible(fnName):          # kernel-registry hit keeps its precedence (4947)
    return true
  for entry in prepared.subjectRegistry.activeEntries:   # ascending (precedence, specRelPath)
    let adapter = capabilityAdapters[ord(entry.capability)]
    let payload = prepared.payloadOf(entry)              # pre-validated in PR-0..; Option
    if payload.isSome and adapter.declares(payload.get, fnName, modulePath):
      let synth = adapter.synthesize(fnName, modulePath, payload.get,
        subjectResolver, prepared.census, sourceRoot)
      if synth.isOk():
        return synth.value        # ok(true) and ok(false) BOTH return — exactly today's protocol
      logWarn("axiom_engine", entry.specRelPath &
        " candidate synthesis unavailable: " & synth.error &
        " — examined symbol falls back to its own census record")
  classifyExternalCandidate(fnName, modulePath, subjectResolver, prepared.census, sourceRoot)
```

This preserves the three load-bearing behaviors verbatim: (i) precedence order (§1.4); (ii) `ok(false)` terminates, `err` falls through (4967-4968 protocol); (iii) the final `classifyExternalCandidate` fallback (5025-5026). Target routing (5040-5097) becomes one loop over entries whose `constructed` is some: canonical first pass, then the bare pass for `allowBare` entries only, preserving today's fail-closed asymmetry — a bare target that routes must synthesize or the run errors (5095-5097), while a canonical target that fails routing synthesis keeps the refusal (5056-5058, 5078-5080).

### 2.8 The two C_out-only direct consumers

`probeSubjectIdentity` (2709-2735) and `buildBugVerdictDisplayJson` (2737-2853) read `Base36CoutOverlayPath` directly (2717, 2750) and, in the display case, re-load the domain (`loadBase36CoutOverlayDomain()` at 2760). After PR-4 (cout flip) they take the registry: `prepared`-scoped `entryFor(reg, capBodyCarry)` → the C_out payload; the raw-node reads (`overlay{"subject"}{"commit"}` etc. at 2759-2766) read `entry.raw` — same JSON, one authority, no second file read. Their fail-soft posture (no overlay ⇒ nil block / probeOk=false, never fabricated — 2748-2749, 2714-2715) is untouched. This kills the last per-lane path-const consumer; the cout path const is deleted with the other five.

---

## 3. Five capability adapters

Each adapter = the lane's *capability-specific head*. Inputs are the parsed payload (§2.2) plus the examined `(fnName, modulePath)` and the subject resolver. Outputs are the same tri-state the synthesizers return today (`ok(true)` eligible / `ok(false)` recorded-and-excluded / `err` fallback), producing census records via `publishExternalCandidate`. The **deletion list** at the end of this section is exhaustive and is the checklist §7 verifies structurally.

### 3.1 `constructed-gate` adapter (toml d2-agent)

- **Inputs**: 9 positional clauses (1659-1712): two domain bounds (parseLowerDomainClause/parseUpperDomainClause — shared, move to the registry module's clause kit), four `<v> != <INT>` exclusions (parseD2ExclusionClause 1382-1393), the forbid disjunction (parseD2ForbidOperandCounts 1415-1458), the defect gate (parseD2GateClause 1460-1489), the control re-stating forbid (control≡forbid set-equality enforced at 1713-1719). Plus `carriers[]` grounding (validateD2Carriers shape), `claimOwnership` (validateD2Ownership 1547-1567).
- **Outputs**: two constructed-IR carriers via `d2ForbidPredicate`/`d2GatePredicate`/`d2DomainPreconditions` (1777-1803) and the `makeCarrier` closure body (3023-3106); derivation digest rule string `"d2-gate-model-v1|rule=" & ruleId & "|grounding=" & modulePath & ":" & groundingLines` (3095-3096); stamped `replayHarnessTemplate` (raise-bool, `<module>` replaced at synthesis 3101-3105).
- **Capability-owned (stays in the adapter)**: the clause grammar (all parseD2* procs); the exactly-9 clause count; carrier name consts `D2AgentDefectCarrierName`/`D2AgentControlCarrierName` (1353-1362) as the payload's required names; the control≡forbij set-equality guard; the byte-domain distinctness checks (1682-1685, 1702-1705); dedupe key = "either carrier name already recorded for this module" (3005-3012) ⇒ `ok(false)`; `wrDefectOnly` wave rename (3126-3139).
- **Deletion**: path const 1349-1351; harness template const 1364-1380 (→ template registry); loader 1627-1638; forward decl 1620-1625; `validateD2SubjectPin` 1520-1545 + `validateD2Ownership` 1547-1567 + `validateD2Carriers` 1569-1618 (the subject-pin/ownership halves fold into the shared kit, §3.7); membership 1744-1755; routing 1757-1775; pin proc 2270-2298; synthesizer 2983-3162; chain arm 5002-5010; routing arm 5040-5058.

### 3.2 `arithmetic-law` adapter (nim-libp2p bytesview)

- **Inputs**: 6 positional clauses (2123-2139): two bounds + four named defs parsed by `parseBvNamedDefClause` (1925-1945) with bodies restricted to the closed arithmetic grammar `parseBvArithBody` (1898-1923: `<v>`, `<v> + <INT>`, `<v> - <INT>`, one optional paren pair via `stripBvOuterParens` 1878-1896). Required def names = the four consts (1842-1864).
- **Outputs**: defect/control carriers over `domain.defectModel/defectLaw/controlModel/controlLaw` (parsed at 2168-2176); derivation digest + stamped single-call-int harness (3285-3289); law name consts stay adapter-owned (names are binding identities; bodies stay data — the design comment at 1828-1831 is preserved).
- **Capability-owned**: the body grammar (rejects any other shape — an overlay stating a different model states a different claim, 1899-1904); the four-name completeness requirement (2172-2176); dedupe key (both carrier names, 3305-3312 analogue); `wrDefectOnly`; **bare-target routing** (`allowBare: true`, 2225-2230) — the only lane that accepts a bare carrier name.
- **Deletion**: path const 1838-1840; harness template 1865-1876 (→ registry); loader 2085-2098; forward decl 2079-2083; `validateBvSubjectPin` 1977-2004 + `validateBvOwnership` 2006-2026 + `validateBvCarriers` 2028-2077 (≈199 duplicated lines vs d2's trio — the dedupe payoff); membership 2201-2211; routing 2213-2238; pin proc 2240-2268; synthesizer 3164-3343; chain arm 5015-5024; routing arms 5059-5097 (both the canonical-refusal and bare-fail-closed arms — the loop in §2.7 replaces them with the same two behaviors).

### 3.3 `body-carry` adapter (base36 C_out + nim sidecar — one adapter, two payloads)

The two lanes share the materialization spine and differ in payload; the adapter is split at exactly that joint:

- **Shared spine (the dedupe)**: materialize ORIGINAL body (`materializeExternalIR`, `moMaterialized` check); single-value-param extraction (today duplicated ×4: sizing 3613-3620, rem 3785-3792, sidecar 3391-3399, cout 4017-4025 — becomes one `extractSingleReferencedParam(fd: IRFuncDef): Option[string]`); the let-binding rejection (sidecar 3385-3386, cout 4012-4013); result-slot β-splice with the exact-once guard (`splices == 1`, the 3658-3672 pattern generalized from sizing's two-goal form); single-origin parse-bound measurement (§2.6); `wrSole`/`wrDefectOnly` publication.
- **C_out payload**: exactly-3 clauses (1264-1266): `<low> <= <v>`, `<v> <= <high>`, `<fn>(<v>) >= <K>` (parseCoutClaimClause 1203-1224); the K cross-check `claimConstant.K == clause K` (1291-1294); the decision-vector consistency `canonicalDecisionVector.L == domain pin upper` (1298-1308); empty-domain-pin rejection (1277-1278); the OPEN-over-L rendering (never a closed proposition — contract §2, comment 1174-1177); claim symbol ∈ subject.symbols (1286-1287). Dedupe key = `Base36CoutCandidateName` (183-186 analogue 1183-1186); `wrSole`.
- **sidecar payload**: two-stage check stays intact — (i) adoption record shape (validateSidecarAdoption 2529-2576), `grammarVersion == nim-sidecar-expr-v1` pin (2336-2340, 2547-2550), propositions exactly defect+control (2622-2651), `canonicalSpecIR == [defect.pre, defect.post, control.pre, control.post]` one-content rule (2656-2660); (ii) SpecID recompute vs `adoptedSpecHash` (2666-2671). Closed-grammar lexer (2406-2527) stays adapter-owned. `wrDefectOnly`.
- **Deletion**: path consts 1179-1181, 2332-2334; `SidecarGrammarV1` const moves with the adapter (kept verbatim); loaders 1233-1243, 2585-2598; forward decls 1226-1231, 2578-2583; membership 1315-1320, 2399-2404; pin proc 2680-2707; synthesizers 3974-4132, 3345-3560; chain arms 4972-4980, 4963-4971; `overlayDeclares*`; **and the direct-read rewiring of 2717/2750 → registry (§2.8)**.

### 3.4 `term-splice` adapter (base32 rem)

- **Inputs**: exactly-3 clauses (1121-1123): `0 <= <dividend>` (parseRemLowerClause 1054-1065), `<v> mod <d> >= 0` (1083-1093), `<v> mod <d> <= <d-1>` (1067-1081) — with the one-divisor agreement rule (1128-1142).
- **Outputs**: the ORIGINAL body materialized UNCHANGED (3755-3759 docstring), claim bound onto the body's own `boRem` term located by the deterministic pre-order walk `findRemTerm` (3800-3860), with the free-var purity guard (3862-3866: matched term's free names == exactly the value param).
- **Capability-owned (the asymmetry that must NOT be over-accepted by a generic parser)**: **let-bindings are ALLOWED** in the subject body (3796-3798: "Let-bindings do NOT disqualify the subject here — unlike the β-splice overlay, no binding is moved or rewritten") — the one lane that permits them; first-match determinism of the term walk; bound == divisor-1 structural rule; `wrSole`.
- **Deletion**: path const 1033-1035; loader 1095-1152; membership 1154-1158; synthesizer 3750-3972; chain arm 4990-4998. (No pin proc, no routing — it never had them.)

### 3.5 `beta-composition` adapter (base36 sizing)

- **Inputs**: exactly-3 clauses (998-1000): `0 <= n` (937-949), `n <= <bound>` (923-935), `<outer>(<inner>(n)) == n` (899-921) with one-variable agreement (1004-1005) and roundtrip symbols ∈ subject.symbols (1006-1007).
- **Outputs**: the composite `roundtrip_dec_enc` (866-868) = β-composition of the two materialized bodies (3632-3644), preconditions = domain bounds (3648-3650), postcondition = roundtrip-eq + TWO overflow goals β-spliced to the result slot **exactly once each** (`rSplices != 1 or oSplices != 1` fail-closed, 3670-3672), composite parse-bound via `measureCompositeParseBoundComponents` (3715-3716), `wrSole`.
- **Capability-owned — including the pinned overflow goals**: the literals `179`, `277`, `9223372036854775807` (3658-3674) REMAIN ENGINE-SIDE adapter constants (decision + rationale in §6, item 8). Scope guards: no let-bindings in EITHER body (3606-3608), no recursion (3609-3610), inner value param must be bound by the composite parameter list (3629-3631), unbound-name guard on the composite body (3637-3641), translation/binding-completeness conjunctions (3680-3687).
- **Deletion**: path const 860-861 (`Base36SizingCompositeName` 866-868 moves with the adapter); loader 951-1011; membership 1013-1016; synthesizer 3562-3748; chain arm 4981-4989.

### 3.6 Shared clause kit (moved once, used by adapters)

`isIdentLike` 887-891, `isIntLiteral` 893-897, `parseLowerDomainClause` 937-949, `parseUpperDomainClause` 923-935 — today used across lanes (sizing/rem/cout/d2/bv); they move to the registry module as the shared clause kit. The lane-specific parsers (roundtrip, rem, cout-claim, d2*, bv*, sidecar lexer) do NOT move there — they stay in their adapters, so a generic parser can never over-accept a lane's clauses (audit risk: "capability-specific clause grammars must NOT be over-accepted").

### 3.7 Shared subject-pin/ownership validation kit

The d2/bv trios are ~199 duplicated lines; the sidecar's adoption validator covers the same fields under `adoption.*`. The kit: `validateSubjectPinObject(subject: JsonNode): Result[tuple[modulePath: string; symbols: seq[string]; blobSha256: string], string]` (union of 1520-1545 / 1977-2004 — identical logic) and `validateOwnershipObject(node): Result[void, string]` (1547-1567 ≡ 2006-2026). Carrier-list validation (1569-1618 ≡ 2028-2077) is parameterized by the required carrier name pair (the only difference between the d2 and bv copies is which consts the name-equality errors cite). The sidecar keeps its own `validateSidecarAdoption` — its subject pin lives under `adoption.subject` with a 40-hex commit rule (2558-2560) stricter than the kit's; collapsing it into the kit would loosen a check (forbidden — §0.9).

### 3.8 Master deletion list (engine, cumulative at PR-6)

| category | lines |
|---|---|
| 6 path consts | 860-861, 1033-1035, 1179-1181, 1349-1351, 1838-1840, 2332-2334 |
| 2 replay template consts | 1364-1380, 1865-1876 (→ closed template registry) |
| 6 loaders | 951-1011, 1095-1152, 1233-1243, 1627-1638, 2085-2098, 2585-2598 (+ forward decls 1226-1231, 1620-1625, 2079-2083, 2578-2583) |
| 6 membership procs | 1013-1016, 1154-1158, 1315-1320, 1744-1755, 2201-2211, 2399-2404 |
| 2 routing procs | 1757-1775, 2213-2238 |
| 3 pin procs | 2240-2268, 2270-2298, 2680-2707 |
| duplicated validator trios | 1520-1618, 1977-2077 |
| 6 synthesizers | 2983-3162, 3164-3343, 3345-3560, 3562-3748, 3750-3972, 3974-4132 |
| 6 evidence tails | 3080-3084, 3264-3268, 3491-3495, 3699-3704, 3923-3927, 4082-4086 (→ one in `publishExternalCandidate`) |
| 6-arm chain | the body of 4944-5026 (site remains, body becomes the §2.7 loop) |
| routing arms | 5040-5097 |
| `PreparedRun` per-lane fields | 4582-4604 (→ one `subjectRegistry` field + payload cache) |

Net: ≈2,775 lines of per-lane engine code reduce to 5 adapter heads (clause grammars + capability guards, the part that is genuinely lane-specific) + ~400 L registry module + ~80 L synthesis core. The per-lane `PreparedRun` fields (4582-4604) disappear; they are read only inside `axiom_engine.nim` (verified: no test or other module names them). The six domain types remain defined in `axiom_engine.nim` and are consumed by the lane suites through the adapter procs — see the test-coupling note above §3: public proc names are preserved precisely so those consumers are untouched.


> **Test-coupling note (verified, shapes §4-§5)**: all four lane suites import `src/cli/axiom_engine` directly (`test_toml_d2_agent_binding.nim:35`, `test_sidecar_binding.nim:41`, `test_libp2p_bytesview_binding.nim:38`, `test_base36_cout_binding.nim:38`) and call the pure validators + synthesizers through it; they also pin concrete values (`importModule == "toml_serialization"` at test_toml:76, `"libp2p/utils/bytesview"` at test_libp2p:110; template import lines at test_toml:443, test_libp2p:487, and cout's `import subject_mod` at test_cout:327). Consequence: the adapters keep every public proc name inside `axiom_engine.nim`, so **the four suites compile and pass UNMODIFIED in their flip PRs** — they are the semantic-equivalence proof, not collateral to rewrite. Only symbols genuinely relocated to `external_subject_registry.nim` (the closed template registry, the envelope types) get one added import line in the affected tests, in the PR that moves them.

---

## 4. Test overlay (P0-1) — internal fixture, zero engine source changes

**Purpose**: prove the registry + one capability adapter end-to-end (load → validate → synthesize → wave entry) on a fixture, before any production lane flips. It is NOT a real defect adoption: no `config/spec/` file is added or modified, no governed subject tree is touched, no adoption record is created, and no harness is executed (the replay is asserted as a stamped string, not run).

**Deliverables (all new files; engine source diff = 0 in this PR)**:

| file | content |
|---|---|
| `tests/fixtures/spec_overlays/fixture_gate_subject.nim` | fixture subject module: one `proc gateAccept(c: int): bool` whose body is a four-member equality gate over `{2, 9, 11, 127}`-shaped values (structurally isomorphic to the d2 defect gate — NOT a copy of any governed subject, no repository/commit/blob of a real tree) |
| `tests/fixtures/spec_overlays/constructed_gate_fixture.json` | a v2 envelope document, capability `constructed-gate`, `presencePolicy: "optional"`, `precedence: 50`, `constructedIrTargets {symbols: [fixtureGateReject, fixtureControlReject], allowBare: false}`, `replay {templateId: "single-call-bool-v1", importModule: "fixture_gate_subject", observation: {kind: "single-call-bool", slots: ["<module>", "<lit>"]}}`, `canonicalSpecIR` = exactly the 9 positional clauses the d2 grammar requires, with fixture carrier names and grounding pointing at `fixture_gate_subject.nim` lines |
| `tests/unit/test_external_subject_registry_overlay.nim` | the assertions below |

**Loader seam (the one design allowance that makes zero-engine-change possible)**: `loadExternalSubjectRegistry(specDir: string)` takes the directory as a parameter — the production call site passes `repoRootConst() / "config" / "spec"`, the test passes `tests/fixtures/spec_overlays/`. No engine hook, no env var, no build flag. Likewise the synthesizers already take `(fnName, modulePath, resolver, domain, census, subjectRepoRoot)` (signatures at 2983-2987 etc.), so the test drives synthesis directly with a local `ModuleContentResolver` over the fixture module bytes.

**Assertions** (the test file's contract):

1. **Load**: `loadExternalSubjectRegistry("tests/fixtures/spec_overlays")` → 1 active entry; `capability == capConstructedGate`; `presence == ppOptional`; `precedence == 50`; `specRelPath == "constructed_gate_fixture.json"`; entries sorted key holds.
2. **Envelope rejections (each → err, message names the rule)**: duplicate `specId` (second fixture file variant); unknown `capability`; unknown `observation.kind` ("write-read-roundtrip" → `UNKNOWN`, §1.5 future-kind rule); `<expr>` appearing in `replay.slots` (reserved vocabulary — load error, §1.5; plus a registry self-test asserting no registered template body contains `<expr>`); `replay.templateId` not in the closed registry; `importModule` ≠ recomputed derivation; `constructedIrTargets.symbols` ≠ payload carrier names; equal-precedence fixture pair with overlapping subject sets.
3. **Adapter validation (pure)**: `validate` accepts the fixture; mutated copies reject with the d2-grammar rules verbatim — wrong clause count (≠9), non-set-equal control (1713-1719 rule), duplicate defect carrier (1600-1601 rule), exclusion duplicates (1682-1685 rule), bad 64-hex blob (1541-1544 rule).
4. **Synthesize → census**: over the fixture module bytes: `census.records` gains exactly 2 records (`fixtureGateReject`, `fixtureControlReject`); `parseBound.claimCarrierSingleOrigin == true`; `parseBound.replayHarnessTemplate` starts with `import fixture_gate_subject` and still contains exactly one `<lit>`; `parseBound.synthesisDerivationDigest` is 64-hex.
5. **Tri-state**: defect eligible + control eligible ⇒ return `ok(true)`; a fixture variant whose grounding symbol is absent from the module bytes ⇒ `err` (module bytes available, EA leg unmeasurable); a variant with the gate body carrying a let-binding ⇒ adapter-level rejection ⇒ `err` falls back (no census records added — the fallback protocol).
6. **Wave entry (rename asymmetry)**: `census.eligible` contains the defect entry with `entry.name == examinedFn` and the control entry under `fixtureControlReject` (`wrDefectOnly`, §2.2).
7. **Determinism**: two loads of the fixture dir produce identical `specIdentity`-relevant projections and identical entry ordering.
8. **NOT-an-adoption guard**: the fixture document carries NO `adoption` object and NO real `subject.repository/commit`; the test asserts the registry does not require them for `constructed-gate` (capability-scoped payload rules), documenting that the fixture is a grammar exercise, not a claim about any real subject.

**Explicitly out of scope for P0-1**: harness execution (`nim c -r` of the stamped template), solver/BMC runs, any `config/spec/**` change, any change to `prepareProofRun`. The wave-loop leg is exercised at the census/`eligible` boundary — the same boundary `census.eligible` feeds `WaveInputs.externalCandidates` (4186) — without running waves.

---

## 5. Migration sequence — per-lane PRs, each with its own TWS re-anchor

Every PR below is a **coherent generation** (§2.5): engine rotation + spec/records + TWS/epoch-manifest pin rotation land together; branch from `origin/main` current at branch time; merge only via GitHub (merge authority, AGENTS.md §2). Optional lanes stay two-PR-safe: at every point in the sequence, a run against a tree whose governed modules are absent behaves exactly as today (inert lines), and a run against governed trees exercises either the old arm or the new adapter — never both for the same lane.

| PR | content | flips | regression proof of semantic equivalence | TWS re-anchor |
|---|---|---|---|---|
| **PR-0** | registry core (`external_subject_registry.nim`): types, loader, closed template registry, `verifySubjectBlobPin`, clause kit, adapter vtable, `publishExternalCandidate` core. Envelope added to ALL SIX `config/spec/*.json` (additive keys only; §1.7). **Dual path**: `prepareProofRun` loads the registry AND keeps the six legacy loads/dispatch; a shadow comparator logs `registry-decision == chain-decision` per examined gate hit (parity log only — no behavior change). P0-1 test overlay (§4) lands here. | none | full unit suite unchanged-green; new overlay test green; parity log empty-diff across the repo's own `ax prove` runs in CI | pin rotation (config changed ⇒ generation bump) |
| **PR-1** | **bv (arithmetic-law)** flip: adapter `validate/declares/routeTarget/synthesize` installed (procs keep names `validateNimLibp2pBytesviewSliceOverlayNode`, `synthesizeNimLibp2pBytesviewSliceCandidate`, now adapter-backed); chain arm + both routing arms deleted for bv; `loadNimLibp2pBytesviewSliceOverlayDomain` deleted; pin trio member 2240-2268 deleted; `PreparedRun.libp2pSliceOverlay` removed | bv | `test_libp2p_bytesview_binding.nim` (648 L, unmodified — incl. importModule 110, template 487, pin-rejection and bare-routing cases); `obligation_subject_binding_test.nim` (486 L); parity log for bv hits = zero mismatches; golden: `tests/cli/test_base36_composite_golden.nim` untouched-green (guards the unaffected sizing lane during rotation) | pin rotation |
| **PR-2** | **d2 (constructed-gate)** flip (same shape as PR-1: adapter-backed procs, arm+routing deletion, `loadTomlD2AgentOverlayDomain` deleted, pin 2270-2298 deleted, `d2AgentOverlay` field removed) | d2 | `test_toml_d2_agent_binding.nim` (634 L, unmodified — clause grammar, control≡forbid, template 443, target routing); `test_d2_golden.nim` + `test_d2_persist.nim`; `obligation_subject_binding_test.nim`; parity log for d2 hits | pin rotation |
| **PR-3** | **sidecar (body-carry/sidecar payload)** flip: two-stage validator + SpecID recompute move behind the adapter unchanged; pin 2680-2707 deleted; chain arm 4963-4971 deleted; `sidecarOverlay` field removed. **SpecID byte-stability asserted here**: `specIdentity` of the migrated `nim_stew_base36_sidecar.json` == `adoption.adoptedSpecHash` (`3f55eaa7…`) | sidecar | `test_sidecar_binding.nim` (639 L, unmodified — incl. the adoption-mutation-fails-closed cases); `obligation_subject_binding_test.nim`; parity log for sidecar hits | pin rotation |
| **PR-4** | **cout (body-carry/C_out payload)** flip: validator 1245-1313 adapter-backed; synthesizer 3974-4132 → adapter; **`probeSubjectIdentity`/`buildBugVerdictDisplayJson` rewired to the registry (§2.8)**; chain arm 4972-4980 deleted; `coutOverlay` field removed; `Base36CoutOverlayPath` const deleted — the LAST per-lane path const consumer | cout | `test_base36_cout_binding.nim` (412 L, unmodified); `test_base36_contract_policy.nim`; bug-verdict display tests (scope-table cases — commit/blob unmet ⇒ nil block preserved); `obligation_subject_binding_test.nim`; parity log for cout hits | pin rotation |
| **PR-5** | **rem (term-splice)** flip — **step 1 adds the missing evidence FIRST**: `tests/unit/test_base32_rem_binding.nim` (modeled on `test_base36_cout_binding.nim`: pure clause validation (exactly-3, one-divisor, bound==d-1), synthesizer over fixture module bytes incl. the let-binding-ALLOWED scope case and the free-var purity rejection, `wrSole` wave entry). Step 2 flips the lane. The same suite proves the legacy lane (pre-flip commit) and the adapter (post-flip commit) — the evidence gap never spans the rotation | rem | new `test_base32_rem_binding.nim` (both sides of the flip); `obligation_subject_binding_test.nim`; parity log for rem hits | pin rotation |
| **PR-6** | **sizing (β-composition)** flip — last, because it is the mandatory lane and the parity-log confidence must be maximal before its fail-closed loader is replaced: loader 951-1011 → envelope+adapter; synthesizer 3562-3748 → adapter (overflow-goal constants move INTO the adapter body verbatim, §6.8); chain arm 4981-4989 deleted; `overlay` field removed; **the 6-arm chain is now fully gone** — `isEligible` is the §2.7 loop alone; the dual-path comparator is deleted | sizing | `tests/cli/test_base36_composite_golden.nim` (152 L — the golden Lean render of the composite is byte-identical); `test_base36_contract_policy.nim` (S0/I4/I5); `obligation_subject_binding_test.nim`; full parity-log history reviewed clean | pin rotation (final generation: registry-only) |

**Final state (end of PR-6)**: `axiom_engine.nim` contains exactly one external-subject dispatch site (the §2.7 loop), zero per-lane consts/loaders/membership/pin/synthesizer procs, zero per-lane `PreparedRun` fields; `config/spec/*.json` are six v2 documents loaded through one deterministic loader with declared `presencePolicy`/`precedence`. New lanes = one JSON document + one adapter registration — no dispatch edit.

Rollback posture: each PR reverts independently (lane returns to its chain arm; PR-0's envelope keys are inert to pre-registry loaders).

---

## 6. Semantic preservation checklist (machine-checkable items)

1. **SpecID byte-stability** — `specIdentity` inputs (`sorted canonicalSpecIR | ord(origin) | ruleVersion`, `specification_artifact.nim:45-49`) unchanged in all six migrated documents; sidecar additionally hash-bound to `adoptedSpecHash` (loader re-check 2666-2671 keeps running, adapter-owned). Evidence: PR-3 assertion + all four suites' adoption-mutation cases green on migrated files.
2. **Presence policies** — mandatory {sizing, rem, cout}: absence blocks with today's message shape (4796-4810); optional {d2, sidecar, bv}: absence logs the inert line (4821-4823 wording), present-but-invalid blocks (4824-4826). The policy is data; the two behaviors are not (§1.3). Evidence: registry unit tests + one absent-file run per policy in PR evidence.
3. **Precedence** — 10/20/30/40/50/60 reproduces 4963→5015; the `ok(false)`-returns / `err`-falls-through protocol is preserved (4967-4968 pattern in §2.7); equal-precedence overlap rejected at load. Evidence: registry ordering unit test + parity logs across all governed trees in CI.
4. **Clause grammars** — every positional/shape rule survives verbatim in its adapter: sizing exactly-3 (998-1000), rem exactly-3 + one-divisor (1121-1142), cout exactly-3 + K cross-check (1264-1294), d2 exactly-9 + control≡forbid (1659-1719), bv exactly-6 + closed arith body (2123-2156), sidecar one-content rule (2656-2660). Lane parsers stay lane-owned (§3.6) — no generic parser over-accepts. Evidence: the four suites + new rem suite, unmodified.
5. **Rename asymmetry** — `wrDefectOnly` (d2/sidecar/bv: defect rides examinedFn, control its own name — 3126-3139, 3532-3543) vs `wrSole` (sizing/cout/rem) encoded in `publishExternalCandidate`; asserted in §4.6 and by the lane suites' eligible-name cases.
6. **Binding-mode shapes** — parseBound 3-shape gate untouched (`canonical_verification.nim:1434-1444`); mapping §2.6 holds; single-origin carriers keep the derivation-digest rule strings (3103 `d2-gate-model-v1|...`, sidecar `SidecarGrammarV1 & "|rule=" ...` at 3519-3522, cout `"result-splice-v1|rule="` at 4101-4103) — digest inputs unchanged ⇒ sealed-artifact identities unchanged. `obligation_subject_binding_test.nim` green in every PR.
7. **Two-PR landing discipline** — optional-lane flips remain non-closure companions: a flip PR lands engine+records together per Amendment F; absence stays inert throughout; no window where a governed tree sees a half-lane. PR boundaries in §5 are the schedule; §2.5 is the invariant.
8. **Sizing constants decision** — the overflow-goal literals `179` (decode multiplier), `277` (encode divisor), `9223372036854775807` (int64 high, 3658-3674) **stay compile-time adapter constants** in v2, NOT JSON data. Rationale: (a) they are the claim's derivation identity — the composite postcondition's spliced goals are part of what `measureCompositeParseBoundComponents` + the derivation digest bind, and moving them to data would rotate every sealed sizing artifact without a semantic change; (b) they mirror the SMT-side goal shape and `Denotation.lean:384-416` (comment 3651-3657) — they are engine mathematics, not subject observation (contrast cout's `K=2`, which IS an external observation and stays data, pinned by the 1291-1294 cross-check); (c) promotion to spec data remains possible in VS-3 behind a `ruleVersion` bump, which is the honest cost of rotating a SpecID. The exact-once splice guards (`rSplices != 1 or oSplices != 1`, 3670-3672) move with them, unchanged.
9. **Zero-footprint / authority** — subjects stay READ-ONLY; `explicitSpecFromOverlay`'s soExplicit pin runs per document at registry load; the registry adds no authority surface (it is a loader, not a gate — merge/verify authority unchanged, §2.3 of merge-observation contract).

---

## 7. Acceptance evidence commands — per PR

Conventions: run from the repo root of the PR's worktree; `bin/ax` must exist (`nimble build`, tests/config.nims enforces). Per-test runner is `nim c -r tests/<path>.nim` (the repo's existing invocation pattern — no Makefile target per lane test exists, verified). `<BASE>` = the PR's merge-base with `origin/main`.

**Common gate (every PR):**

```bash
nimble build && make check-arch && make check-debt          # pinned-toolchain build + nimtry + debt sync
nim c -r tests/unit/obligation_subject_binding_test.nim     # binding-mode shapes: exit 0
git diff --stat $(git merge-base HEAD origin/main) -- config/spec/   # envelope-only, additive
```

**PR-0 (registry core + envelope + overlay test):**

```bash
nim c -r tests/unit/test_external_subject_registry_overlay.nim      # exit 0 (all §4 assertions)
for t in toml_d2_agent sidecar libp2p_bytesview base36_cout; do nim c -r tests/unit/test_${t}_binding.nim; done   # exit 0 each (legacy path untouched)
nim c -r tests/cli/test_base36_composite_golden.nim                 # exit 0
# parity evidence: one ax prove run over a tree with governed modules present
bin/ax prove --target 'stew/base36.nim::decodedLength' 2>&1 | tee /tmp/parity0.log
grep -c 'registry-decision == chain-decision' /tmp/parity0.log      # ≥ 1 hit per examined gate hit; 0 mismatch lines:
! grep -q 'registry-decision != chain-decision' /tmp/parity0.log
# envelope inertness under the OLD engine semantics: legacy loaders ignore new keys
python3 - <<'EOF'
import json
for f in ['base36_sizing_relational_spec','nim_stew_base32_rem_spec','nim_stew_base36_cout_spec',
          'toml_d2_agent_spec','nim_libp2p_bytesview_slice','nim_stew_base36_sidecar']:
    d=json.load(open(f'config/spec/{f}.json'))
    assert d['specOrigin']=='soExplicit'
print('envelope: 6/6 explicit, canonicalSpecIR untouched')
EOF
```

**PR-1 (bv) / PR-2 (d2) / PR-3 (sidecar) / PR-4 (cout) — one template, lane substituted:**

```bash
# LANE ∈ {libp2p_bytesview, toml_d2_agent, sidecar, base36_cout}; CAP ∈ {bv, d2, sidecar, cout}
nim c -r tests/unit/test_${LANE}_binding.nim                        # exit 0, file UNMODIFIED vs base:
git diff <BASE> -- tests/unit/test_${LANE}_binding.nim              # empty diff
nim c -r tests/unit/obligation_subject_binding_test.nim             # exit 0
bin/ax prove --target '<governed.module>::<governed.symbol>' 2>&1 | tee /tmp/parity_${CAP}.log
! grep -q 'registry-decision != chain-decision' /tmp/parity_${CAP}.log
grep -E "accepted|excluded" /tmp/parity_${CAP}.log | grep -E "candidate|carrier"   # accepted/excluded log lines, field order preserved
# sidecar only (PR-3): SpecID byte-stability
python3 - <<'EOF'
import json,hashlib
d=json.load(open('config/spec/nim_stew_base36_sidecar.json'))
ir='|'.join(sorted(d['canonicalSpecIR']))+'|'+'0'+'|'+d['ruleVersion']   # ord(soExplicit)==0 (SpecOrigin enum: soExplicit, soCanonicalDerived, soMined — specification_artifact.nim:26-31)
assert hashlib.sha256(ir.encode()).hexdigest()==d['adoption']['adoptedSpecHash'], 'SpecID moved!'
print('sidecar SpecID stable:', d['adoption']['adoptedSpecHash'][:12])
EOF
```

(PR-3 additionally: `nim c -r tests/unit/test_sidecar_binding.nim` includes the hash-mismatch/mutation cases; PR-4 additionally: the bug-verdict display suite for the §2.8 rewiring — `nim c -r tests/unit/test_bug_verdict_display.nim` if present at PR time, else the display cases inside `test_base36_cout_binding.nim`, plus one run with an unmet commit pin asserting the block stays absent — never Unknown.)

**PR-5 (rem) — evidence-first:**

```bash
# step-1 commit (pre-flip): the NEW suite proves the LEGACY lane
nim c -r tests/unit/test_base32_rem_binding.nim                     # exit 0 against legacy loader/synthesizer
# step-2 commit (flip): the SAME suite, UNMODIFIED, proves the adapter
git diff <BASE>..HEAD -- tests/unit/test_base32_rem_binding.nim     # no diff between step-1 and step-2 commits
nim c -r tests/unit/test_base32_rem_binding.nim                     # exit 0 against registry path
```

**PR-6 (sizing) + final structural state:**

```bash
nim c -r tests/cli/test_base36_composite_golden.nim                 # exit 0 — golden Lean render byte-identical
git diff <BASE> -- tests/cli/test_base36_composite_golden.nim       # empty
nim c -r tests/unit/test_base36_contract_policy.nim                 # exit 0 (S0/I4/I5)
bin/ax prove --target 'stew/base36.nim::decodedLength' 2>&1 | tee /tmp/parity_sizing.log
! grep -q 'registry-decision != chain-decision' /tmp/parity_sizing.log
```

**Structural verification — per-lane code GONE (cumulative; run at PR-6, and per-lane at each flip):** these are structure checks (single dispatch site, symbol counts, const absence), not name greps alone — each has an expected count and a negative control:

```bash
# 1. The 6-arm chain is gone: the eligibility closure contains the registry loop and nothing else.
awk '/let isEligible = proc/,/^  # Apply --target/' src/cli/axiom_engine.nim > /tmp/elig.nim
grep -c 'prepared.subjectRegistry.activeEntries' /tmp/elig.nim      # == 1 (the single dispatch site)
grep -cE 'overlayDeclares(Sidecar|Cout|Rem|D2Agent|Libp2pBytesview)Subject|synthesize(Base36|Base32|TomlD2|NimSidecar|NimLibp2p)' /tmp/elig.nim   # == 0

# 2. No per-lane loaders / membership / routing / pin procs remain (name-level negatives; zero tolerance):
grep -cE '^proc (loadBase36OverlayDomain|loadBase32RemOverlayDomain|loadBase36CoutOverlayDomain|loadTomlD2AgentOverlayDomain|loadNimLibp2pBytesviewSliceOverlayDomain|loadNimSidecarOverlayDomain)' src/cli/axiom_engine.nim    # == 0
grep -cE '^func overlayDeclares' src/cli/axiom_engine.nim           # == 0
grep -cE '^func (d2AgentCarrierTargetRouting|libp2pBytesviewCarrierTargetRouting)' src/cli/axiom_engine.nim   # == 0
grep -cE '^proc verify(Libp2pBytesview|TomlD2Agent|Sidecar)SubjectPin' src/cli/axiom_engine.nim                # == 0

# 3. No per-lane path consts remain; exactly ONE spec-dir anchor exists:
grep -cE 'repoRootConst\(\) / "config" / "spec" / "[a-z0-9_]+\.json"' src/cli/axiom_engine.nim   # == 0
grep -c '"config" / "spec"' src/cli/external_subject_registry.nim src/cli/axiom_engine.nim       # registry module owns the dir join; engine call site == 1

# 4. The registry loader is invoked exactly once (prepareProofRun); dispatch has one consumer:
grep -c 'loadExternalSubjectRegistry(' src/cli/axiom_engine.nim     # == 1
# 5. Evidence tails deduped: the dual-write call appears once, inside publishExternalCandidate:
grep -c 'saveCompletenessEvidenceDual' src/cli/axiom_engine.nim     # == 1
# 6. PreparedRun per-lane fields gone:
grep -cE 'overlay\*: Option\[|remOverlay\*|coutOverlay\*|d2AgentOverlay\*|sidecarOverlay\*|libp2pSliceOverlay\*' src/cli/axiom_engine.nim   # == 0
# 7. Negative control for the greps above (they CAN detect presence): at <BASE> each count matches the audit
#    (6 loaders, 6 membership, 2 routing, 3 pins, 6 tails) — run once on the base commit to prove the greps bite:
git stash list | grep -q . || true   # (no-op guard) — the base-commit run is recorded in the PR description
# 8. Full local CI after the final generation:
make local-ci                                                       # exit 0
```

A flip PR is admissible only when (a) its lane's count in check 2 is already 0, (b) checks 1/4/5 hold monotonic progress (check 1's dispatch-site count becomes 1 at PR-6 — until then the legacy chain remains the deciding path beside the shadow loader; check 4 is 1 from PR-0 onward — one registry load, never per-lane fan-out; check 5 decreases 6 → 1 across PR-1..PR-6), and (c) the parity log shows zero mismatch lines. "완료" claims ride these observations, not the absence of compile errors (AGENTS.md §2.2).

---

## 8. Out of scope (named, not promised)

- `write-read-roundtrip` observation kind and the `<expr>` slot (VS-3).
- Promoting sizing's overflow goals (§6.8) or any SpecID-rotating field move to JSON.
- Lane expansion (new subjects/capabilities) — the registry makes it additive, this spec adds none.
- Any change to `src/verification/` seal/replay machinery, to kernel-registry eligibility (`isRegistryEligible` 837-849 keeps its precedence over the registry loop), or to merge/CI authority surfaces.
