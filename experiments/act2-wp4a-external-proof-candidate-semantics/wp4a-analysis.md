# WP4-a Phase A Analysis — External Proof Candidate Semantics

## Experiment Metadata

- **EXPERIMENT_ID**: `act2-wp4a-external-proof-candidate-semantics`
- **SUBJECT**: nim-stew@c75502c (`stew/base36.nim` sha256=b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8)
- **AXIOM_REVISION**: Axiom repo at `.`
- **AXIOM_CONFIGURATION**: Standalone compilation from `/tmp` with `-p` import paths; `axiomLayer "tools"`
- **TOOLCHAIN_ID**: Nim 2.2.10, `nim c` from `/tmp`
- **VERIFICATION_SCOPE**: 3 symbols — `encode`, `decodedLength`, `normalizeMaxWorkers` (reference AxiomSupport)
- **PROBE**: `wp4a_probe.nim` (experiment-only, not canonical execution path)

---

## 1. Predicate Vector Table (3 Symbols, Machine-Readable)

| Field | encode | decodedLength | referenceAxiomSupport |
|---|---|---|---|
| **registryMembership** | false | false* | N/A (fallback) |
| **irAvailable** | true | true | N/A |
| **obligationGenerated** | false | true | N/A |
| **obligationCount** | 0 | 1 | N/A |
| **obligationKind[]** | [] | [okSafetyDiv] | N/A |
| **assessAdmissibilityDecision** | DEFER_TO_RUNTIME | ADMISSIBLE | N/A |
| **assessAdmissibilityReason** | ireNone | ireNone | N/A |
| **assessAdmissibilityDetail** | structural body — runtime admission decides | simple SMT-native body — statically executable | N/A |
| **inVerifiedFragment** | false | true | N/A |
| **finalEligibilityClass** | elNoObligation | elProofCandidate | elProofCandidate |
| **exclusionReason** | registry pre-emption: isFrontierSelectionEligible returns false because symbol is absent from runtimeAxiomRegistry; classifyCandidateEligibility and assessAdmissibility are never reached | registry pre-emption (same root cause; decodedLength would be eligible if registered) | Registry empty in standalone compilation; WP3-verified reference symbol |
| **isExternal** | true | true | false (Axiom self) |

\* `decodedLength` is hardcoded in `axiom_engine.nim:998-1000` with `origin=soExternalSubject` in a normal Axiom build, but the registry is empty in standalone compilation mode.

### Machine-readable JSON excerpt (from `wp4a-probe.json`)

The full predicate vector is in `wp4a-probe.json` under `predicateVector`. Key values:

- `encode.finalEligibilityClass` = `"elNoObligation"`
- `decodedLength.finalEligibilityClass` = `"elProofCandidate"`
- `referenceAxiomSupport.eligibilityClass` = `"elProofCandidate"`

---

## 2. Registry Field Inventory (11 Fields × Supply Source)

| Field | Supply Source | encode_fillable | decodedLength_fillable |
|---|---|---|---|
| `name` | registry-only | false | true |
| `irSerialized` | registry-only | false | true |
| `smtSource` | registry-only | false | true |
| `leanSource` | registry-only | false | true |
| `sourcePath` | registry-only | false | true |
| `isKernel` | registry-only | false | true |
| `irHash` | registry-only | false | true |
| `effectKind` | registry-only | false | true |
| `bmcSkippable` | registry-only | false | true |
| `origin` | registry-only | false | true |
| `expectedObligation` | registry-only | false | true |

**Key finding**: All 11 fields of `RuntimeAxiomEntry` are supplyable only from the compile-time registry. For external subjects, none of these fields can be reconstructed from the subject source alone — they require the registry entry. The `irSerialized` field is the most critical: without it, `classifyCandidateEligibility` cannot deserialize the IR and the entire eligibility pipeline is unreachable.

The `origin` field (`AxiomEntryOrigin = soAxiomSupport | soExternalSubject`) is the only field that distinguishes Axiom self-symbols from external subjects, but it is never consulted by `assessAdmissibility` or `inVerifiedFragmentV1` (both are origin-agnostic).

---

## 3. Graph-IR vs Canonical-IR Determination

**Determination: B**

| Aspect | Detail |
|---|---|
| **Graph builder** | `src/core/symbol_graph/global_symbol_graph_builder_part2.nim` lines 242-248 |
| **What graph stores** | `{qualifiedName, kind, modulePath, astNode: nil, visibility}` per symbol node |
| **What graph does NOT store** | `irSerialized`, `body`, `params`, `retType`, `preConditions`, `postConditions` — `astNode` is explicitly `nil`(line 246) |
| **Canonical IR pipeline** | `parseStringAST` → `pnodeToCanon` (`src/core/trusted/pnode_to_canon.nim:120`) → `axiomBodyCanon` (`src/core/trusted/ast_to_ir.nim:1249`) → `convertFuncDefCanon` (`src/core/trusted/ast_to_ir.nim:1199`) → `serializeIRFuncDef` (`src/core/trusted/axiom_ir.nim:304`) |
| **Divergence point** | Graph builder extracts symbol metadata from AST and stops; canonical IR pipeline continues through CanonNode → IRFuncDef conversion |
| **Semantic equivalence** | Both pipelines use the same AST as input, but graph builder never produces IR |

**Evidence**: The graph JSON at `/tmp/wp3fo_state_a/logs/global_symbol_graph.json` contains 623 symbols, each with only `{qualifiedName, kind, modulePath, visibility}`. The `encode` symbol is present as `{qualifiedName: "base36.encode", kind: "skProc", modulePath: "stew/base36.nim", visibility: "public"}` but carries no IR. The canonical IR for `encode` was successfully reproduced by the probe via the `parseStringAST → pnodeToCanon → axiomBodyCanon → convertFuncDefCanon` path.

---

## 4. "만약 encode가 registry에 등록됐다면" — Final Eligibility Class

If `encode` were registered in `runtimeAxiomRegistry` with `origin=soExternalSubject`:

1. **registryMembership**: true
2. **isFrontierSelectionEligible("encode")**: would return the result of `classifyCandidateEligibility(entry, funcDef) == elProofCandidate`
3. **classifyCandidateEligibility result**: `elNoObligation` (because `generateCanonicalObligations(encode_ir, defaultScopePolicy())` returns `ogrNoApplicableObligation` — encode is a pure function with no division guards, index guards, loop bounds, preconditions, or postconditions)
4. **Final eligibility class**: `elNoObligation` — NOT `elProofCandidate`

**Conclusion**: Even if `encode` were registered in the registry, it would NOT be a proof candidate. The reason is not the registry pre-emption but the obligation generation result: `encode` produces zero obligations, which maps to `elNoObligation`. The registry pre-emption is a separate, earlier blocker that prevents even reaching this determination.

The `decodedLength` symbol, by contrast, produces 1 `okSafetyDiv` obligation and is classified as `elProofCandidate` when its IR is processed through the same pipeline.

---

## 5. Exclusion Root Cause

**Registry pre-emption**: `isFrontierSelectionEligible` (`candidate_eligibility.nim:82-100`) performs a linear scan of `runtimeAxiomRegistry`; if the symbol name is absent, it returns `false` immediately, preventing `classifyCandidateEligibility` and `assessAdmissibility` from ever being reached. This is a registry-level gate, not a semantic ineligibility — the external subject's IR is well-formed and processable, but the registry lookup fails before the eligibility pipeline can evaluate it.

---

## 6. Next Step Dependencies (Phase B Entry)

**Phase B is viable** if the following conditions are met:

1. **Registry pre-emption bypass**: A mechanism to register external subjects in `runtimeAxiomRegistry` (e.g., `registerAxiom("encode", irStr, ..., origin=soExternalSubject)`) would allow `encode` to reach the eligibility pipeline. The probe has demonstrated that `encode`'s IR is processable and `assessAdmissibility` returns `DEFER_TO_RUNTIME` (not `INELIGIBLE`), so the pipeline would not reject it on admissibility grounds.

2. **Obligation generation for encode**: Even with registry registration, `encode` would remain `elNoObligation` (zero obligations). To become `elProofCandidate`, `encode` would need obligations in the `VerifiedFragmentAllowlist` (`{okContractPre, okContractPost, okSafetyDiv, okSafetyIndex, okSafetyLoopBound}`). This requires either: (a) adding contract annotations to `encode`, or (b) modifying `extractObligationCandidates` to detect safety targets in `encode`'s body.

3. **decodedLength is already a valid proof candidate**: The probe confirmed `decodedLength` is `elProofCandidate` with `okSafetyDiv` obligation and `ADMISSIBLE` admissibility. Phase B could proceed with `decodedLength` as the working example.

**Phase B recommended path**: Bypass registry pre-emption for external subjects → re-run eligibility pipeline → confirm `decodedLength` reaches proof execution → investigate `encode`'s zero-obligation status as a separate concern.

---

## 7. Probe and Output Files

| File | Path |
|---|---|
| Probe source | `experiments/act2-wp4a-external-proof-candidate-semantics/wp4a_probe.nim` |
| Probe output (JSON) | `experiments/act2-wp4a-external-proof-candidate-semantics/wp4a-probe.json` |
| Analysis document | `experiments/act2-wp4a-external-proof-candidate-semantics/wp4a-analysis.md` |
| Compiled binary (for reference) | `/tmp/wp4a_probe` |

---

## 8. 본검증 (Independent Product-Run Verification)

probe는 standalone 컴파일로 실행되어 product의 compile-time registry를 채우지
못했다(registry empty). 이는 probe의 일부 필드(registryMembership, reference
AxiomSupport 선정, registry field inventory)가 측정이 아닌 하드코딩/fallback에
의존했다는 뜻이다. 따라서 실제 제품 실행(`bin/ax prove`)으로 핵심 결론을
재확인했다.

실행: `bin/ax prove --project <clean subject> --target encode --limit 1`
(clean subject = nim-stew-clean-c75502c, AXIOM_STATE_DIR=/tmp/wp4a_verify_state)

제품 로그 (단말 출력 원문):

```
[INFO] axiom_engine: --target filter: 4 node(s) match 'encode'
[INFO] axiom_engine: frontier eligibility gate: excluded 326 non-proof-candidate candidate(s); eligible=0
[INFO] loop_driver: verifying 0 nodes (primed=0)...
[INFO] loop_driver: Verification-Gate: 0 UAP requests — UAP execution skipped
[INFO] axiom_engine: done: verifiedRatio=0.0000, verified=0/41
```

확정 사항:
- 제품 path에서 encode는 **eligible=0**으로 탈락 (Z3/Lean 미도달, 0 UAP).
- `--target encode`는 substring 매칭으로 **4개 노드**와 매칭 — canonical
  exact-qualified identity(`stew/base36.nim::encode`) 원칙과는 다르며,
  exact-1-match 원칙상 ambiguous 대상. (WP3 규칙 E1의 후속 관찰)
- probe의 핵심 계산(encode = `elNoObligation`, decodedLength =
  `elProofCandidate`)은 합성 entry로 실제 classifier를 호출해 재생산한
  것이므로, registry empty와 무관하게 유효하다.

---

## 9. Non-Conclusions

- The empty registry in standalone compilation is a known limitation of the probe environment, not a defect in the probe logic. In a normal Axiom build context (where `axiom_engine.nim` calls `generateAxiomInit()`), the registry would be populated and `decodedLength` would show `registryMembership: true`.
- The `elNoObligation` classification for `encode` is a semantic result of the obligation generator, not a probe artifact. The probe faithfully reproduces the canonical IR and runs the official `generateCanonicalObligations` pipeline.
- The `DEFER_TO_RUNTIME` admissibility for `encode` means the static analyzer cannot fully discharge it (structural body with loop), but this does not make it `INELIGIBLE` — it would proceed to runtime admission if it had obligations.

## 10. Probe 측정 한계 (정직성 기록)

이 문서의 표 중 **측정이 아닌 하드코딩/fallback**으로 얻은 부분을 명시한다.
AGENTS.md §6(측정/추측) 및 §8(evidence first) 원칙에 따라, 아래 필드는
probe가 runtime에 계산한 것이 아니라 코드에 직접 박혀 있거나 fallback으로
주입된 값이다.

1. **registryMembership** — probe는 standalone 컴파일로 product의
   compile-time registry를 채우지 못해 `runtimeAxiomRegistry`가 비어 있었다.
   따라서 표의 `registryMembership=false`(encode/decodedLength)는 **실행 환경
   한계**이지 제품 사실이 아니다. 실제 제품(bin/ax)에서는
   `axiom_engine.nim:998-1000`의 하드코딩 `registerAxiom("decodedLength",
   origin=soExternalSubject)`와 `generateAxiomInit()`으로 registry가 채워지므로
   decodedLength는 `registryMembership=true`이다. 이 필드는 probe 측정으로
   재현되지 못했다.
2. **referenceAxiomSupport** — `findReferenceAxiomSupport`(wp4a_probe.nim
   :92-124)는 registry가 비면 fallback으로 `normalizeMaxWorkers`를
   `elProofCandidate`로 **하드코딩** 리턴한다(:117-124). 이는 측정이 아닌
   주입값이다. 실제 제품 로그에서는 `normalizeMaxWorkers`가 `[ir-cas] MISS`로
   나타나, registry에서 이 이름이 elProofCandidate로 분류된다는 **제품 측정은
   아직 없다.** 따라서 표의 reference 행은 "WP3에서 verified된 것으로 알려진
   심볼"이라는 가정 기반이며, 이번 실험에서 독립 측정되지 않았다.
3. **registry field inventory** — wp4a_probe.nim:347-359의 inventory
   (`encode_fillable=false`, `decodedLength_fillable=true`)는 전부 **하드코딩**
   값이다. 절대적으로 정확하지 않다: `decodedLength_fillable=true`는
   decodedLength가 하드코딩 registry에 이미 있기 때문이지, external subject
   source에서 11개 필드를 **재구성** 가능해서가 아니다. "external subject의
   필드 재구성 가능성"을 측정한 것이 아니라, "이미 registry에 있느냐"를
   손으로 적은 것이다. 이 inventory는 신뢰할 수 없으며, Phase B에서 external
   entry 구성을 설계할 때 실제 코드로 다시 측정해야 한다.
4. **graph IR vs canonical IR 판정(B)** — wp4a_probe.nim:363-372의
   `determination: "B"`는 하드코딩 문자열이지만, 이는 제가 직접
   `global_symbol_graph_builder_part2.nim:42-45, 243-247, 373-376`에서 확인한
   사실(graph는 `{qualifiedName, kind, modulePath, visibility}`만 저장, IR/body
   미저장)과 **일치**한다. 이 판정은 유효하다.

**핵심: probe에서도 계산으로 확정된 사실.**
- encode(외부): 실제 소스에서 canonical IR 재생산 성공,
  `generateCanonicalObligations` → obligation 0개 → `classifyCandidateEligibility`
  → `elNoObligation` (registry에 있어도 클래스는 elNoObligation).
- decodedLength(외부): 실제 소스 IR 재생산, `okSafetyDiv` 1개, ADMISSIBLE →
  `elProofCandidate`.
- 실제 제품 실행으로도 encode는 eligible=0 (frontier eligibility gate) 재확인.
- A-3 판정 B 는 graph builder 코드 인용과 일치.

