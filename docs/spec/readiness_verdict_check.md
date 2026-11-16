# Readiness Verdict Check (`readiness-verdict`)

> Status: 이 PR로 도입(DEBT#537 청산). `readiness-verdict` 잡(`.github/workflows/axiom-operational-slice.yml`)은 R1–R8 증거 → evaluator → 판정 → exit 사슬을 **7번째 required check**로 만드는 병합 허가 검증이다.
> 이 문서는 그 잡이 **무엇을 증명하고 무엇을 증명하지 않는지**, identity chain, verdict→exit 매핑, activation 순서의 SSOT다. 판정 대수·증거 envelope·policy의 의미는 [productization_contract.md](productization_contract.md)(§2–§5, §9)가 여전히 SSOT이며, 본 문서는 CI 검증 표면만을 정의한다.
> **People investigate and interpret evidence; the verdict is decided by a pure function, never by a human.**

---

## §1. 목적 — 4단계 신뢰 경로

| 단계 | 주체 | 근거 |
|---|---|---|
| **Identity Authority** | GitHub merge-group SHA(`GITHUB_SHA`) | GitHub 공식 문서: `merge_group` 이벤트의 `GITHUB_SHA`는 merge group의 병합 커밋 SHA다(`pull_request`에서는 PR merge-ref 커밋, `push` main에서는 push된 커밋). GitHub가 부여한 신원만이 판정의 정본 신원이다 — 잡은 이를 단언하고(§4) 자체 신원을 발명하지 않는다. |
| **Evidence Producer** | 기존 도구 재사용 + 수집기 | 운영 슬라이스 잡(`axiom-operational-slice`)이 산출한 증거 산출물(run-manifest, R3 측정, E2E 상태)을 **재사용**하고, 수집기 `tools/ci/readiness_collect_ci.nim`가 관측을 R1–R8 envelope(§4 스키마)로 정규화한다. Producer는 판정을 내리지 않는다. |
| **Decision Authority** | `Decide` 순수 함수 | `src/core/utils/decision_algebra.nim`의 `func Decide`(`{.raises: [].}`, 시계·파일시스템·환경·네트워크 무결). evaluator `tools/readiness_evaluator.nim`가 관찰→상태 규칙(§2)을 적용해 `Decide`에 후보를 넘긴다. 동일 (candidate, evidence, contract) → 동일 판정. |
| **Enforcement** | GitHub ruleset / merge queue | 판정의 집행은 required check로서 ruleset이 수행한다(ADR-0037 위임 모델: GitHub enforces, Axiom records identity). 잡은 exit 코드로만 말한다. |
| **Replay** | 제3자 | §6의 재현 절차 — 동일 증거 + 동일 환경에서 동일 판정·digest. |
| **Ledger** | debt_engine | DEBT#537 청산 기록(부채 레지스트리 — 스킵=Success 함정으로 NO-GO가 조용히 병합되던 갭의 폐쇄). |

신뢰는 한 주체에 집중되지 않는다: 신원은 GitHub, 증거는 재사용된 운영 산출물, 판정은 순수 함수, 집행은 ruleset, 검증은 제3자 재현 — 각 단계는 직전 단계의 산출물만 소비한다.

---

## §2. 검증 역할 — 무엇을 증명하고 무엇을 증명하지 않는가

| 검증 | 증명하는 것 | 증명하지 않는 것 |
|---|---|---|
| **PR-1 자기 CI 녹색**(본 잡의 자기 실행) | 운영 스모크 테스트: 파이프라인이 실제로 실행되어 판정을 산출한다 — 증거 다운로드→수집→게이트→exit 경로가 살아 있고, 필요 산출물(decision json, evidence artifact)이 실존한다. | 판정의 정확성·증거의 진위. 자기 실행은 "기계가 돈다"의 증명이지 "기계가 옳다"의 증명이 아니다. |
| **3^8 속성테스트**(`tests/readiness/readiness_policy_test.nim`) | 판정 대수 성질: 8개 불변식 × 3상태(PASS/FAIL/UNKNOWN)의 전 조합(6561)에서 `Decide`가 결정표(productization §3)를 만족한다 — UNKNOWN의 PASS 승격 금지, critical/비critical 구분, 조건 목록의 기계 생성. | 실증거의 충실성(입력이 정당한가는 아래 수집기 테스트와 재현의 소관). |
| **골든**(`tests/readiness/fixtures/synthetic_bundle.json` → `data/golden/readiness/decision.golden.json`) | 기지 입력 일치: 고정 bundle에 대한 판정(verdict·conditions·invariantStates·decisionDigest)이 기록된 골든과 일치한다. | 미래 입력에 대한 동작(그것은 속성테스트·policy의 영역). |
| **수집기 독립 테스트**(`tests/ci/test_readiness_collect_independence.nim`) | 관측→증거 충실성: artifact 부재 → UNKNOWN(fail-closed), 다른 SHA의 증거 → 거부, 업스트림 실패 → 성공 위조 금지. 수집기가 관측을 재해석하거나 성공을 날조하지 않음을 기계 단언한다. | 게이트·판정 알고리즘 자체. |
| **제3자 재현**(§6) | 재현 가능성: 동일 증거 + 동일 AXIOM_CI 환경에서 동일 verdict·decisionDigest. | 증거가 실제 제품 상태를 반영한다는 것(관측 충실성은 수집기 테스트의 소관). |

부속: `tests/readiness/readiness_r8_sequence_test.nim`(R8 prepare 순서 기계 검증), `tests/unit/test_readiness_outcome_test.nim`(관찰상태 vs 결과 분류 — UNKNOWN/NOT_RUN이 확정 FAIL과 혼동되지 않음), `tests/ci/test_readiness_verdict_mapping.nim`(verdict→exit 매핑 단언).

---

## §3. verdict → exit 매핑

| 판정(`READINESS_VERDICT`) | 게이트 exit | check-run 결론 | 병합 |
|---|---|---|---|
| `GO` | 0 | success | 허용 |
| `CONDITIONAL GO` | 0(조건은 `::warning::` annotation으로 공개) | success | 허용(조건 공개 하에 — 아래 정의) |
| `NO-GO` | 1 | failure | 거부 |
| `UNKNOWN` | 1 | failure | 거부(fail-closed) |
| 증거 신원 불일치(`READINESS_IDENTITY_MISMATCH`) | 1 | failure | 거부 |

- 게이트의 exit 코드가 잡의 판정이다 — 잡은 후처리 없이 그 exit를 check-run 결론으로 노출한다(exit 1 = red).
- 조건이 있을 때 annotation은 스킵되지 않는다: 비침묵(non-silent)이 계약이다(productization §3 — conditions는 상태에서 자동 생성되며 사람 입력이 아니다).

**CONDITIONAL GO 정의**: CONDITIONAL GO는 명시된 비중요 조건을 공개한 상태에서 병합을 허용하는 판정이다. 그 조건이 병합 권한의 추가 제한을 의미하는 경우에는 별도의 기계적 집행 조건을 적용한다. 현재 조건(R7 범위 정직성, VKD<0.5)은 추가 병합 제한을 수반하지 않는다.

(R7 근거: `ruleR7` — 비critical 불변식. 측정 커버리지가 policy `r7.vkdMinThreshold`(기본 0.5) 미만이면 R7=FAIL → CONDITIONAL GO의 조건; 반면 scope 과잉 청구(verified emitter scope ∉ claimed scope)는 R1/R2 FAIL로 **승격**되어 NO-GO가 된다 — 조건이 병합 권한을 침해하는 경우는 판정 자체가 거부로 바뀐다.)

---

## §4. Identity Chain

판정은 "이 트리의 제품 상태"에 대해서만 유효하다. 잡은 다음 사슬을 기계 단언한다:

1. **GITHUB_SHA = merge group SHA** — identity authority(§1). 잡은 GitHub가 부여한 신원을 소비할 뿐이다.
2. **`HEAD == $GITHUB_SHA` 단언** — checkout이 identity authority의 트리 그 자체임을 확인한다. 불일치 → exit 1.
3. **treeDigest** — `git ls-tree -r HEAD`의 SHA-256(**커밋된** 트리; derived 경로 기록에 영향받지 않는다). 게이트 실행 시 `AXIOM_CI_TREE_DIGEST`로 전달된다.
4. **증거 repoIdentity 스탬프 = env authority** — 수집기가 stamp한 증거의 `repoIdentity`(head·treeDigest)는 잡 환경(=`AXIOM_CI_REPO_HEAD=$GITHUB_SHA` + `AXIOM_CI_TREE_DIGEST`)이 권위다. 게이트가 증거의 `repoIdentity`와 env를 대조하여 불일치 시 `READINESS_IDENTITY_MISMATCH`로 exit 1한다 — 증거가 스스로 주장하는 신원은 권위가 아니다.
5. **실행 바이너리 결속** — `bin/ax --check-provenance`(SourceCoherence: 내장 BuildSourceHash vs live tree 재계산) + `sha256sum bin/ax` vs run-manifest `.binary.sha256` 대조. run-manifest는 증거를 산출한 E2E 잡의 verifier 바이너리 증명이다.
   - **복원(웜) 레인**: B-layer exact-hit에서 복원된 bin/ax는 게시된 바이트 — producer 잡도 S5 재컴파일을 건너뛴 경우 동일 바이트를 실행했으므로 byte 대조가 성립한다.
   - **콜드 레인**: 재컴파일(`make ci-compile`) 시 바이트 동일성은 빌드 시스템이 보장하지 않는다([setup-axiom-toolchain action 계약](../../.github/actions/setup-axiom-toolchain/action.yml): per-TREE, never per-byte — 동일 트리 재빌드는 바이트가 다를 수 있다). 콜드 레인은 의미 결속으로 대체한다: `--check-provenance`가 산출하는 live tree hash == run-manifest `.sourceTree.buildSourceHash`(같은 트리에서 도출된 BuildSourceHash는 결정적이다). producer 잡이 B-hit에서 재컴파일(S5 discard)한 드문 경우 복원 바이너리와 manifest 바이트가 어긋나 잡이 red가 될 수 있다 — 그 red는 "이 잡이 byte 결속을 증명할 수 없다"는 정직한 실패다.
6. **판정 전 트리 불변 dirty check** — `git status --porcelain`에서 선언된 derived 경로(`data/readiness/evidence`, `logs`, `build`, `bin`, `.axiom`, `proofs`, `src/generated`)만 제외한 출력이 비어야 한다. 판정 입력 트리가 HEAD와 불변임을 단언한다.

**스킵=Success 함정 방어**(required check의 구조적 전제): 잡 헤더 `needs: [axiom-operational-slice]` + `if: !cancelled()` — producer 실패 후에도 판정을 계산한다(증거는 producer의 `if: always()` 업로드가 보존; artifact 부재는 다운로드 실패로 잡을 red로 만든다). path 필터 없음(워크플로 `on:`은 pull_request + merge_group + push main + workflow_dispatch 그대로). 잡 수준 `name:` 키 금지 — **job id가 check-run context다**(`readiness-verdict`). 스텝 `if:`는 업로드의 `always()`뿐이다. 스킵된 required check는 success로 보고되므로, 어떤 조건으로도 스킵되는 잡은 이 계약 전체를 무효화한다.

---

## §5. trustSurface 부트스트랩

판정 도구 4종 — `tools/readiness_evaluator.nim`, `src/gate/runners/readiness_start_gate.nim`, `config/readiness_policy.json`, `tools/ci/readiness_collect_ci.nim` — 의 trustSurface([config/policy/merge_admission.json](../../config/policy/merge_admission.json)) 등재는 **본 PR 착지 이후** 효력을 갖는다(등재 시점부터 이 파일들을 바꾸는 PR은 자동 병합이 거부된다).

본 PR 자신은 그 등재의 혜택을 받을 수 없다 — 스스로를 판정하는 도구를 스스로 승인하는 순환을 만들 수 없기 때문이다. 대신 base 정책의 **기존 항목** — `.github/workflows/axiom-operational-slice.yml`(workflow), `config/policy/merge_admission.json`, `src/cli/merge_cli.nim` — 이 이미 trustSurface에 있으므로, 본 PR은 rotation lane(수동 병합)으로 착지한다(ADR-0037의 operational-slice 착지와 동일 패턴: `TRUST_SURFACE_MODIFIED` → 수동 병합).

초기 신뢰의 근거는 사전 위임 승인 기록 + 리뷰다 — 부채 청구(DEBT#537: NO-GO 상태가 조용히 병합되던 스킵=Success 갭)의 해결 위임과, 이 문서가 정의하는 기계 검증 표면에 대한 인간 검토. 착지 후 첫 rotation부터는 trustSurface가 자동으로 이 표면을 보호한다.

---

## §6. 제3자 재현 절차

1. `gh run download <run-id> -n readiness-verdict-evidence` — artifact 루트가 repo 루트이므로 `data/readiness/evidence/*.json`, `build/readiness_start_decision.json`, `logs/run-manifest.json`, `logs/r3_relocation.json`, `logs/r3_relocation.sha256`가 원래 경로 그대로 복원된다.
2. 동일 커밋 체크아웃: `git checkout <GITHUB_SHA>`(run 페이지에서 확인) 후 트리 불변 단언(§4.6).
3. 게이트를 동일 증거 + 동일 AXIOM_CI 환경으로 재실행:
   ```
   AXIOM_CI=1 AXIOM_CI_PRESERVE_CACHE=1 \
     AXIOM_CI_REPO_HEAD=<GITHUB_SHA> \
     AXIOM_CI_TREE_DIGEST="$(printf '%s' "$(git ls-tree -r HEAD)" | sha256sum | cut -d' ' -f1)" \
     ./bin/readiness_start_gate
   ```
4. 비교: `verdict`, `conditions`, `invariantStates`, `decisionDigest`(및 결정적 보조 필드 `policyHash`, `bundleDigest`). 불일치 = 재현 실패(판정 도구가 비결정적이거나 증거가 변조됨).

**decisionDigest의 실제 정의**(구현 대조 — `src/core/utils/decision_algebra.nim` `Decide` + `canonicalSha256`):

- `decisionDigest = SHA-256(canonicalJson(payload))`, `payload = {verdict, conditions, invariantStates}` — canonicalJson은 **키 정렬·compact·whitespace 없음**의 정규화다.
- 즉 digest는 **판정 의미에 영향 주는 필드만** 포함한다: verdict, conditions, invariantStates(R1–R8 상태).
- **비결정적 메타데이터는 포함되지 않는다**: `collection.generatedAt`/`freshUntil`(증거 envelope의 §4 스키마)과 `evaluationTime`은 validity 축에만 존재한다(`evaluationTime <= freshUntil` 검사) — 시간은 verdict의 직접 입력이 아니다(productization §4). 따라서 재판정 시점과 무관하게 동일 증거 → 동일 decisionDigest여야 하며, 이것이 비교 대상으로 정당하다.
- `policyHash` = canonicalSha256(policy), `bundleDigest` = canonicalSha256(invariants bundle) — 모두 결정적이므로 재현 비교에 포함해도 좋다.

**재현의 validity 축과 evaluationTime 기록**: 게이트는 평가시점을 `now()`로 잡고, decision 기록(`build/readiness_start_decision.json`, evaluator가 직접 기록)은 그 **평가시점을 `evaluationTime` 필드로 함께 남긴다**(additive — decisionDigest preimage는 불변). 따라서 재현자는 (1) `freshUntil` 경과 전 재판정: 위 절차 3의 `--eval-time` 대신 decision 기록의 `evaluationTime` 값을 전달해 동일 verdict·decisionDigest를 재계산한다. (2) 시간 경과 후: stale-evidence 거부(exit 1)가 정상 동작이다(판정은 시간에 유효범위가 있다).

---

## §7. Activation 순서

ADR-0037 패턴(operator-PUT-first)을 따른다 — 워크플로 착지와 ruleset 등록은 별개 단계다:

1. **PR-A(본 워크플로) 착지** — `readiness-verdict` 잡이 pull_request/merge_group/push main에서 실행된다(이 시점에는 아직 required가 아니다 — 잡의 자기 실행이 스텝·인터페이스를 검증한다).
2. **운영자 ruleset PUT** — ruleset에 `readiness-verdict` context를 7번째 required check로 추가한다. ruleset 측 context 수의 정본은 PUT 시점의 ruleset이므로, 그 시점에 [config/policy/merge_admission.json](../../config/policy/merge_admission.json) `requiredValidations` + [src/cli/merge_cli.nim](../../src/cli/merge_cli.nim)의 이중 결속을 동반해야 한다(ADR-0037 §6 — 편측 업데이트는 drift monitor leg 1을 red로 만든다).
3. **드리프트 창 폐쇄** — ruleset과 정책 미러의 드리프트 창을 PUT과 **같은 UTC 일 내**에 닫는다. 폐쇄 기록은 activation manifest(`data/promotions/` 패턴, 예: `data/promotions/axiom-operational-slice-activation/manifest.json`)에 남긴다 — ruleset에만 존재하는 required context는 관측 불가능한 집행이 되고, 미러에만 존재하는 항목은 죽은 선언이 되므로 창이 하루를 넘으면 안 된다.

필요 시 음성 대조(negative control)를 activation 계약의 일부로 수행한다(ADR-0037 §4 선례): 위조 판정 입력이 잡을 red로 만들고 병합을 차단하는지를 한 PR로 측정한다.

---

## 참조

- 워크플로: [.github/workflows/axiom-operational-slice.yml](../../.github/workflows/axiom-operational-slice.yml) — `readiness-verdict` 잡(스텝·주석이 이 문서의 운영 정의다)
- 판정 의미 SSOT: [productization_contract.md](productization_contract.md) — §2 불변식 레지스트리, §3 결정표, §4 증거 envelope, §9 evaluator 인터페이스
- 의사결정 대수: `src/core/utils/decision_algebra.nim`(`Decide`, `canonicalSha256`)
- 게이트: `src/gate/runners/readiness_start_gate.nim` · 수집기: `tools/ci/readiness_collect_ci.nim` · policy: [config/readiness_policy.json](../../config/readiness_policy.json)
- 테스트: `tests/readiness/readiness_policy_test.nim`(3^8 + 골든) · `tests/readiness/readiness_r8_sequence_test.nim` · `tests/unit/test_readiness_outcome_test.nim` · `tests/ci/test_readiness_verdict_mapping.nim` · `tests/ci/test_readiness_collect_independence.nim`
- ADR-0037(required check 착지·activation 패턴) · ADR-0025 Amendment B(B-layer 단일 기록자 — §4 웜/콜드 레인의 근거) · [run_manifest_contract.md](run_manifest_contract.md)
- 부채: `data/debt_registry.json` DEBT#537
