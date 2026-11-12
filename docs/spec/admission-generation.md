# Admission Generation — 승격 불변 경계 (단일 SSOT)

**Status**: Normative contract (v1, 2026-10-15 — Slice A: ruleset SHA pinning의 운영 수용 본문)
**Created**: 2026-10-15
**Related**: AGENTS.md §2.3(merge-admission 관측 계약), §2.5(CI Self-Bootstrap Bottleneck), [docs/agents/ci_epoch_cutover.md](../agents/ci_epoch_cutover.md), [docs/spec/github_ruleset_api_quirks.md](github_ruleset_api_quirks.md), [docs/spec/merge_admission_controller.md](merge_admission_controller.md), [docs/agents/merge_admission_observation.md](../agents/merge_admission_observation.md), [docs/spec/merge_authority_integrity.md](merge_authority_integrity.md), `config/policy/merge_admission.json`(trustSurface SSOT), [docs/evidence/admission_generation_freeze_2026-10-15.md](../evidence/admission_generation_freeze_2026-10-15.md)(동결 기록), DEBT#473
**동결 기록**: H₀/H₁ 자격 증거·핀 스냅샷·채널 실측의 시점 기록은 [docs/evidence/admission_generation_freeze_2026-10-15.md](../evidence/admission_generation_freeze_2026-10-15.md)가 담는다. 본 문서는 그 위의 **규범**만 담는다.

---

## 1. 목적 / 범위

> **2026-10-17 상수 갱신**: org ruleset ID 24233738 → **25218071**(2026-10-16T04:51Z ID 교체)·컨트롤러 경로 `admission-gate.yml` → **`admission-gate-v2.yml`**. 절차·계약 본문은 불변. 배경: [generation_promotion_hnew_2026-10-17.md](../evidence/generation_promotion_hnew_2026-10-17.md)

이 문서는 Archright/Axiom의 merge-admission **실행 경계 세대(admission generation)**의 정의·동결·승격 절차에 대한 **단일 SSOT**다.

- **권위 선언**: merge-admission의 enforcement authority는 GitHub다(AGENTS.md §2.3 — org ruleset 2종 + required status check + merge queue). 본 문서는 그 권위를 재구현하지 않으며, org ruleset **25218071(axiom-admission-gate)**·**23943917(landing-integrity)**이 강제하는 required workflow — 조직 저장소 `Archright/.github`의 `.github/workflows/admission-gate-v2.yml`·`landing-integrity.yml` — 의 **세대 경계**(무엇이 불변이고, 무엇이 승격 가능하며, 어떤 절차로 승격되는가)를 규정한다.
- **단방향 구조**: 본 문서가 세대 경계를 정의하고, 컨트롤러 저장소 `Archright/.github/.github/workflows/admission-gate-v2.yml` 헤더 주석(H₁ 기준)이 본 문서를 참조한다. 본 문서는 컨트롤러 파일 내용을 복제하지 않는다.
- **참조 전용 계층**(중복 서술 금지 — 발견 시 각 정본이 자기 계약을 유지한다): epoch cutover 일반 절차는 [ci_epoch_cutover.md](../agents/ci_epoch_cutover.md)(AGENTS.md §2.5 실행 프로토콜), ruleset 쓰기 API의 관측 행동·HARD RULE은 [github_ruleset_api_quirks.md](github_ruleset_api_quirks.md), admission 술어 계약은 [merge_admission_controller.md](merge_admission_controller.md), 런 관측 계약은 [merge_admission_observation.md](../agents/merge_admission_observation.md)가 각각 담는다.
- **범위 밖**: §9 Out of Scope. 잔여 가변 표면의 제거 작업, admission 술어·관측 계약의 개정, S4 실행 자체는 본 문서의 범위가 아니다.

---

## 2. 불변 실행 경계 (전수조사 — 2026-10-15, H₁ 기준)

### 2.1 전 `uses:` 참조와 판정

현행 세대 H₁에서 도달 가능한 **전체** `uses:` 참조(조립자 2파일 + 피호출 3워크플로 + 복합 액션 1개, 각 핀 SHA에서 직접 판독)는 아래와 같다. 전수 판독 명령과 원문은 동결 기록 §2·§6에 있다.

| 참조 대상 | 핀 | 판정 |
|---|---|---|
| `Archright/Axiom/.github/workflows/admission-check.yml` | `dc527994c987cad9d7d83f1dc27650d0c15eb63e` | 커밋 SHA 핀 ✓ |
| `Archright/Axiom/.github/workflows/certificate-mint.yml` | `aa051134359ee37e50bf30bcc58187c58aa6fe3a` | 커밋 SHA 핀 ✓ |
| `Archright/Axiom/.github/workflows/runner-pool-acceptance.yml` | `ba773d0631b5757525b16d8fd62e220492e98e76` | 커밋 SHA 핀 ✓ |
| `Archright/Axiom/.github/actions/setup-axiom-toolchain` | `ba773d0631b5757525b16d8fd62e220492e98e76` | 커밋 SHA 핀 ✓ (runner-pool과 동일 커밋) |
| `actions/checkout` (컨트롤러 admission-gate·Axiom 피호출 3종) | `11d5960a326750d5838078e36cf38b85af677262` | 커밋 SHA 핀 ✓ |
| `actions/checkout` (컨트롤러 landing-integrity) | `3d3c42e5aac5ba805825da76410c181273ba90b1` | 커밋 SHA 핀 ✓ |
| `actions/upload-artifact` | `ea165f8d65b6e75b540449e92b4886f43607fa02` | 커밋 SHA 핀 ✓ |
| `actions/download-artifact` | `d3f86a106a0bac45b974a628896c90dbdf5c8093` | 커밋 SHA 핀 ✓ |
| `actions/cache/restore`·`actions/cache/save` (setup-axiom-toolchain action.yml :322·:388·:925) | `0057852bfaa89a56745cba8c7296529d2fc39830` | 커밋 SHA 핀 ✓ |
| `./.github/actions/setup-axiom-toolchain` (Axiom 피호출 워크플로 내부) | `./` 상대 | **구조적으로 불변** — 같은 커밋의 저장소 내부 참조, 외부 이동 불가 ✓ |
| `docker://` 참조 | — | **0건** ✓ |

**판정: uses-graph는 완전 SHA-closed다.** 세대 H₁에서 실행되는 모든 외부 코드는 커밋 SHA로 고정되어 있고, 조립자(assembler) 자신은 조직 ruleset이 참조하는 대상으로서 §5의 전환으로 SHA 고정에 편입된다.

### 2.2 잔여 가변 표면 (4종 — 후속 슬라이스 위임)

아래 4종은 **세대 경계 밖의 가변 표면**이다. SHA 핀 체계가 닫지 않는 나머지이며, 각각 후속 슬라이스의 소관이다. 본 문서는 이를 **면제하지 않는다** — 기록하고 위임만 한다.

| # | 표면 | 위치 (H₁ 실측) | 위임 |
|---|---|---|---|
| 1 | 툴체인 원격 fetch의 무결성(hash) 검증 부재 | `setup-axiom-toolchain/action.yml` — choosenim `init.sh` 파이프(~L760), elan(L815), z3(L841), jq(L868), apt(L556); `runner-pool-acceptance.yml`:240-241 inline choosenim; `admission-check.yml`:520-521·762-763 jq/curl | 툴체인 해시 검증 슬라이스 |
| 2 | `vars.CI_RUNNER_MAP` 가변 변수 | org variables | runner-map 정적화 슬라이스 |
| 3 | `landing-integrity.yml` runner 라벨 `ubuntu-latest` | L71·L164·L342 | runner 라벨 핀 슬라이스 |
| 4 | anchor-resolve의 live main tip read | 설계상 의도됨(by design — 이벤트 동결 앵커 체계와의 관계는 [merge_admission_controller.md](merge_admission_controller.md) §8 참조) | 유지 관측 대상 |

---

## 3. 세대 정의 (H₀ → H_new)

> **2026-10-17 갱신**: 세대표 확장 — H_v2(태그 `admission-gen-h6-20261016`)를 거쳐 현행 **H_new**(컨트롤러 PR #227)까지. 중간 세대(h2–h5 계열)의 원문 계보는 각 승격 기록 문서가 담는다.

### 3.1 정의

| 세대 | 커밋 (Archright/.github main) | 시각 | 태그 (컨트롤러 원격, annotated) | 내용 |
|---|---|---|---|---|
| **H₀** (직전 세대) | `abe66968dbcb4746f5c79d43341d564422108253` | last controller main commit 2026-10-14T16:17:41Z, 이후 0건; HEAD 일치 | `admission-gen-h0-20261015` | 트러스티파이 전 헤더("sha pin" 허위 서술) 상태의 조립자 |
| **H₁** | `e968b5c0c20b7c63adaad74a235c31392b6ac497` | PR #218 native merge 2026-10-15T05:59:01Z | `admission-gen-h1-20261015` | 헤더 주석 전용 정화(비주석 변경 0줄) + dependabot ignore 4항목 |
| **H_v2** | `5bfc911448a56d3e600aa06552291fb405898a46` | 2026-10-16T06:56:09Z controller HEAD 판독(사전등록 §7) | `admission-gen-h6-20261016` | `admission-gate-v2.yml` 조립자 세대(등록 시점 활성 핀) |
| **H_new** (기록 시점 현행 세대 — 아래 2026-11-01 관측 갱신 노트 참조) | `29094836bc4488280d98c22665470dcb2e54da1a` | PR #227 native merge 2026-10-16T23:52:43Z | — | verdict ∥ publish(publish→verdict 무소비 엣지 제거) — [승격 기록](../evidence/generation_promotion_hnew_2026-10-17.md) |

> **2026-11-01 통화성 관측 (갱신 노트)**: 위 표의 "현행" 표기는 기록 시점(2026-10-17) 값이다. 2026-11-01 org ruleset readback(`gh api orgs/Archright/rulesets/25218071`·`gh api orgs/Archright/rulesets/23943917`)에서 양 ruleset의 활성 `workflows[].sha`는 **`d76caf956000175bbc78f9b25bced842c02992a5`**로 관측되었고, 이는 컨트롤러 `Archright/.github` main HEAD(2026-10-31T07:14:27Z native merge, 컨트롤러 PR #251)와 일치했다. `gh api repos/Archright/.github/compare/29094836bc4488280d98c22665470dcb2e54da1a...d76caf956000175bbc78f9b25bced842c02992a5`는 behind_by=0·ahead_by=44 — H_new 커밋은 활성 핀의 조상으로 관측되었다. 따라서 H_new 행은 당시 승격 기록으로서 유효하나(역사 행 유지), "현행" 판독은 본 관측 시점 기준 활성 핀과 불일치한다. 핀 `d76caf956…` 자체에 대응하는 `generation_promotion_*` 기록 문서는 본 관측 시점에 docs/evidence/에서 관측되지 않았고, §3.2의 3다리 자격 판정도 본 노트에서 수행하지 않았다 — 본 노트는 readback 관측만 기록하며 새 세대의 승격을 선언하지 않는다. 세대 계보 참조(중간 시점 재핀 readback 기록): 컨트롤러 PR #246(2026-10-21, `2bcbcb8c…`) — [v5_generation_acceptance_a_2026-10-21.md](../evidence/v5_generation_acceptance_a_2026-10-21.md).

### 3.2 자격 증거 (3다리)

세대 커밋의 자격은 아래 3다리가 **모두** 성립할 때만 인정된다. 측정 원문은 동결 기록 §1에 있다.

1. **시간 경계**: 후보 커밋이 컨트롤러 main의 마지막 커밋이고, 그 이후 커밋이 0건이며, 원격 HEAD와 일치한다.
2. **실행 증거**: 해당 커밋에서 실행된 최후의 green merge_group 런이 존재한다(H₀: run **38681365187**, 2026-10-15T04:25:19Z).
3. **원자 승격**: 직전 세대에서 현행 세대로의 전이가 단일 native merge 커밋(H₀→H₁: PR #218, pin-promotion-gate pass)으로 착지했다.

### 3.3 태그와 §2.5 Freeze의 관계

세대 태그는 [ci_epoch_cutover.md](../agents/ci_epoch_cutover.md) §2.5 프로토콜의 **단계 1(Freeze) — immutable reference 고정**의 수행이며, `ci-frozen-*` 관례와 동일한 원칙(삭제 금지, 재현 가능한 immutable baseline)이 적용된다. 태그 운용 절차의 재정의는 하지 않는다. **Record**(단계 2)는 동결 기록 문서가, 세대별 특수 사항(§5의 ruleset 재핀)은 본 문서가 담는다.

---

## 4. 승격 절차 (2경로) — DEBT#473 해소 정의

callee 핀과 epoch 승격의 동기화 절차 미정의(DEBT#473, 2026-10-01 실측 — acceptance 차단 창)는 아래 2경로의 정의로 **해소된다**. 두 경로는 **사후 ruleset 재핀 의무(§4.3)**를 공유한다.

### 4.1 경로 (a) — controller-side pin promotion

Axiom callee 변경이 Axiom main에 착지한 후, 컨트롤러 저장소의 PR이 callee 핀을 회전한다.

1. Axiom callee 워크플로 변경이 Axiom main에 착지한다(정상 Axiom 큐 경로).
2. 컨트롤러 저장소(`Archright/.github`)에서 callee 핀 회전 PR을 생성하고 정상 큐 경로로 착지시킨다 — **자기참조 없음**.
3. 착지 후 §4.3의 사후 ruleset 재핀 의무를 **같은 논리적 단위**로 수행한다(§2.5 Atomic Binding Update의 이 세계에서의 수행).

### 4.2 경로 (b) — Axiom trust-surface 변경 (ROT_NEW_PIN 자기참조 잠금)

`config/policy/merge_admission.json`의 `trustSurface`에 열거된 Axiom 측 워크플로(현행: `admission-check.yml`, `certificate-mint.yml`, `runner-pool-acceptance.yml` 등)의 변경은 **자신이 착지되어 생성될 핀을 자신이 등록해야 하는** 자기참조 구조라서, Axiom 큐를 통해서는 **구조적으로 착지 불가**하다. 합법 경로는 둘뿐이다:

- **ROT_ALLOWLIST 사전 등록**: 착지 전에 경로를 열거한 사전등록 문서를 두고 그 경로대로 수행한다.
- **긴급 evaluate 창**: [github_ruleset_api_quirks.md](github_ruleset_api_quirks.md)의 비상 창 HARD RULE(감사 기록 의무·복원 검증 의무·창 최소화)에 따라 수행하고, **사후 감사 문서를 `docs/evidence/`에 남긴다**.

선례: 2026-10-14 병렬 레짐 REUSED 마스킹 착지의 원자 되돌림이 8.3초 evaluate 창으로 수행되었다(§8 계보). 비상 창은 예외 수단이지 절차가 아니다 — 승격의 기본 경로는 (a)다.

추가 선례: 2026-10-20 24초 evaluate 창(PR #965 착지) — repo ruleset `20303214`의 `enforcement`만 `active→disabled`→`active`로 이동했고 복원은 관측되었으나, **감사 기록이 약 1일 뒤에야 생성**되었다(창 종료 시점에 기록해야 한다는 기한 조항이 그때는 없었다). 기록·미이행 공백의 복구: [incident_emergency_disable_window_2026-10-20.md](../evidence/incident_emergency_disable_window_2026-10-20.md).

### 4.3 사후 ruleset 재핀 의무 (HARD RULE)

> **2026-10-17 갱신**: 규칙셋 ID 상수 갱신 — 24233738 → **25218071**(2026-10-16T04:51Z 교체). 재핀 의무 본문은 불변.

S4 전환(§5) 이후, org ruleset의 workflow 규칙은 **컨트롤러 조립자 커밋의 SHA**를 가리킨다. 컨트롤러 main의 HEAD가 전진하는 모든 착지(경로 (a)의 핀 회전 PR 포함)은 **같은 논리적 단위에서** 양 ruleset(25218071·23943917)의 `sha`를 새 컨트롤러 HEAD로 재핀하고 readback으로 검증해야 한다(쓰기 경로·readback 절차는 §5.3–5.5와 동일). 재핀 없이 남은 세대 전환은 불완전 cutover다 — §2.5의 "일부만 갱신된 상태를 허용하지 않는다"의 이 세계에서의 적용이다.

---

## 5. S4 전환 통제 절차 (일회성 cutover — 2026-10-15 수행 예정)

> 본 절은 절차의 **순서·판정·롤백**만 규정한다. ruleset 쓰기 API의 관측 행동(PATCH 404, GraphQL 표면)과 비상 창 HARD RULE은 [github_ruleset_api_quirks.md](github_ruleset_api_quirks.md)가 정본이다. 본 전환은 [ci_epoch_cutover.md](../agents/ci_epoch_cutover.md) §2.5의 **coherent generation 전환**이다 — 활성 경계의 in-place 부분 수정이 아니다.

> **2026-10-17 갱신**: 규칙셋 ID·컨트롤러 경로 상수 갱신(25218071·`admission-gate-v2.yml`). 2026-10-15 S4 수행 시점의 당시 값은 git 이력이 담는다.

**전환 대상**: org ruleset 25218071·23943917의 workflows 규칙을 `ref: main`(가변 — 결함: 컨트롤러 main 전진이 강제 경계를 무음으로 바꾼다)에서 **`sha: H₁`** 고정으로 전환한다.

1. **빈 큐 확인**: Axiom merge queue와 in-flight merge_group이 비어 있음을 관측한다. 비어 있지 않으면 전환을 시작하지 않는다.
2. **dispatch freeze**: repo ruleset **20303214**의 `merge_queue.max_entries_to_build`를 **2→0**으로 바꿔 신규 큐 유입을 동결한다(읽기로 관측).
3. **ruleset 25218071 재핀**: 문서화된 REST 경로 `PUT /orgs/Archright/rulesets/25218071`에 정본 페이로드 — workflows 규칙 `WorkflowFileReference {path: ".github/workflows/admission-gate-v2.yml", repository_id: 1182157951, sha: H₁}`(ref 제거) — 을 적용한다. REST PUT이 실측 불성립 시 폴백은 GraphQL `updateRepositoryRuleset`이다(quirks Q2 — repo·org node_id 공용).
4. **ruleset 23943917 동일 적용**: 같은 경로로 `landing-integrity.yml` 규칙을 `sha: H₁`로 재핀한다. 3과 4 사이에 세계를 관측 가능한 상태로 두지 않는다 — 두 ruleset은 **하나의 논리적 전환 단위**다.
5. **readback byte-consistency**: 양 ruleset을 GET으로 재판독하고, `sha` 필드의 H₁ 설정과 **그 외 모든 규칙·조건·bypass 무변경**을 대조한다. 관측된 readback이 완료 조건이다("했다" 주장 아님 — quirks 복원 검증 의무 준용).
6. **해제**: `max_entries_to_build`를 0→2로 복원하고 readback한다.

### 5.7 롤백 행렬

| 상태 | 행위 |
|---|---|
| **success** | 양 ruleset `sha` == H₁ → 유지. §6의 발산 테스트를 다음 admission 런에서 수행해 런타임 sha 준수를 입증한다. |
| **failure** (PUT/폴백 실패, readback 불일치) | 양 ruleset을 **H₀ 값으로 원복**한다 — §5.3–5.5와 동일한 쓰기 경로 + readback. freeze(0)를 푼 뒤 원인을 조사하고 재시도한다. |
| **unknown** (성공·실패 판정 불가) | **dispatch freeze(0)를 유지**하고 조사한다. 성공을 선언하지 않는다 — 판정 불가 상태의 해제는 ref:main 잔존을 숨긴다. |
| **금지** | **`ref: main` 복원은 금지된다.** 그것은 결함의 재설치다(§7 폐기된 등식 2 참조). H₀ 원복도 ref:main 재진입이 아니라 **당시의 SHA 값 원복**이다. |

**본 PR과의 관계**: 이 docs PR은 S5 수용 차량으로서 **S4 전환이 완료된 후에만** 큐에 진입해 머지된다. 본 PR의 머지 자체가 Slice A의 운영 수용(production acceptance — §2.5 단계 9)이다.

---

## 6. 수용 증거 (4중) — 정의와 인식론적 한계

세대 승격의 수용(acceptance)은 아래 **상호 독립인 4개 채널**이 모두 관측될 때만 성립한다. 단일 채널의 성공은 수용이 아니다(AGENTS.md §2.3).

| 계층 | 채널 | 내용 |
|---|---|---|
| **E1** | run object `referenced_workflows` | 런 오브젝트 필드가 실행에 사용된 callee SHA를 **정확히** 반환한다(실측 — 동결 기록 §6). |
| **E2** | job 로그 `Uses:` 라인 | 러너가 내보낸 `Uses:` 로그 라인이 핀 SHA와 일치한다(실측 — 동결 기록 §6). |
| **E3** | 핀-트리플 지문 | 조립자(컨트롤러) 커밋에는 **직접 채널이 없다**(required-workflow 등록 API는 422-deprecated). 대신 조립자 정체성을 핀-트리플 지문 `{dc527994c…, aa0511343…, ba773d0631…}` + 컨트롤러 git-history 시간 경계로 식별한다. |
| **E4** | 착지 정체성 | required check의 identity(workflow_id + path 이중 결속 — [merge_admission_controller.md](merge_admission_controller.md) §3 참조, 여기서 재정의하지 않는다)와 최종 **GitHub native MERGE 커밋**. merge-admission authority는 GitHub다(AGENTS.md §2.3). |

### 6.1 런타임 sha 준수의 인식론적 한계와 발산 테스트

핀 시점에 `sha == ref == H₁`이므로, **GitHub 런타임이 ref가 아니라 sha 필드를 존중한다는 사실은 첫 세대에서 직접 관측할 수 없다**(두 필드가 같은 커밋을 가리켜 구별 불가). 이 한계의 유일한 닫는 방법이 **발산 테스트(drift-guard divergence test)**다:

- 무해한 컨트롤러 커밋을 main에 착지시킨다(관측 대상 아님의 변경).
- 다음 admission 런의 E1(`referenced_workflows`) 지문이 **불변**임을 관측한다.
- 지문이 불변 ⇒ 실행이 sha 필드에 의해 지배된다(ref가 지배했다면 지문이 전진한다). 지문이 전진 ⇒ sha 준수 불성립 — §5.7 failure 원복 판정.

발산 테스트가 성공하기 전까지 Slice A의 런타임 준수는 "미입증 가설"이지 성과가 아니다.

---

## 7. 폐기된 등식 (설계 근거)

아래 등식들은 본 슬라이스의 검토에서 **기각되었다**. 기록하는 이유: 동일한 등식으로의 후퇴를 방지하기 위해서다.

| 폐기된 등식 | 기각 근거 |
|---|---|
| "외부 저장소에 있으니 외부일 수밖에 없다" | 장소(venue)는 **정책(POLICY) 문제**지 위상(topology) 문제가 아니다. 조직 저장소 배치는 조직 권위의 수행일 뿐, 경계 불변식의 근거가 아니다. |
| "auto-latest는 안전한 업데이트다" | `ref: main` 핀은 컨트롤러 main의 **모든** 전진 — 무관한 편집조차 — 을 강제 경계에 무음으로 반영했다(§8 계보 10/12·10/14의 직접 원인). 가변 참조 = 검증되지 않은 자동 승격. |
| "모든 PR에 같은 절차 = 모든 PR에 같은 비용" | trust-surface PR은 자기참조로 큐를 통과할 수 없다(§4.2). 절차의 통일이 아니라 **경로의 정당화**(사전등록·긴급 창·사후 감사)가 비용을 배분한다. |
| "실패 → 차단이면 충분하고, 회복은 인간의 몫이다" | 10/12 사건에서 차단은 223런·~9h의 구조적 정체를 만들었다. fail-closed와 **회복 절차의 정의**(§5.7 롤백 행렬)는 별개 의무다. |
| "green = verified" | 2026-10-14 REUSED 마스킹: green 판정이 재사용된 증거를 마스킹했다(§8 계보). green은 E1–E4 독립 채널 관측의 한 부분일 뿐이다. |

---

## 8. 사건 계보 (요약)

정확한 측정 원문은 각 기록 문서가 담는다. 여기서는 세대 경계 설계의 직접 원인만 남긴다.

- **2026-10-12 — parse poison**: 루틴한 핀 회전이 21,000 표현식 한도를 초과하는 25,954자 보간 run 스칼라를 조립자에 승격 → 0-job dispatch 실패 223런 → 큐 **~9시간 구조적 봉쇄**. (기록: `docs/evidence/emergency_evaluate_window_2026-10-12.md`, `docs/evidence/admission_parse_poison_oracle_2026-10-13.md`, 설계: `docs/design/workflow_parse_poison_lint_wiring_design_2026-10-14.md`)
- **2026-10-13 — 3세대 1일 회전**: 하루에 3개의 핀 세대가 회전하고 merge_group red가 발생 → 소유자 직접 머지로 해소(감사됨 — `docs/incidents/2026-10-13_pr814_pr815_direct_merge_audit.md`). 회전 빈도 자체가 위험이었다.
- **2026-10-14 — REUSED 마스킹**: 병렬 레짐 착지가 REUSED로 마스킹되어 착지 → 4연속 비결정 merge_group red → 8.3초 evaluate 창으로 원자 되돌림(기록: `docs/evidence/mg_red_forensics_2026-10-14.md`). "green = verified" 등식의 기각 근거(§7).

공통 근본 원인: **가변 참조(`ref: main`) 위에서 강제 경계가 운영되고, 세대 전환의 절차·증거·롤백이 정의되지 않았다**는 것. 본 문서의 §3–§6이 그 정의다.

---

## 9. Out of Scope

본 문서(및 본 PR)가 다루지 **않는** 것 — 범위는 닫혀 있다(AGENTS.md §2.2):

1. **잔여 가변 표면 4종(§2.2)의 제거** — 각 후속 슬라이스의 소관. 본 문서는 기록·위임만 한다.
2. **S4 전환의 실행 자체** — 본 PR 착지 후 별도 수행되며, 실행 증거는 그 시점의 `docs/evidence/` 기록으로 남는다.
3. **ruleset 쓰기 API의 신규 실측** — [github_ruleset_api_quirks.md](github_ruleset_api_quirks.md)의 관측 기록을 여기서 확장하지 않는다(S4 readback 결과는 quirks 문서 개정으로 반영).
4. **admission 술어·관측 계약의 개정** — [merge_admission_controller.md](merge_admission_controller.md)·[merge_admission_observation.md](../agents/merge_admission_observation.md) 소관.
5. **`data/debt_registry.json`의 DEBT#473 status 전환** — 본 문서는 DEBT#473을 **해소하는 정의**(§4)를 제공한다. 레지스트리 status 전환은 projection codegen(`bin/debt_engine --codegen`)·budget ledger 동기화를 수반하는 정본 데이터 mutation으로 **후속 변경**에서 수행된다(본 PR은 docs-only — 레지스트리 폐쇄의 연쇄 변경이 코드 트리(`src/generated/debt_constants.nim`)에 도달하기 때문).
6. **동결 시점 측정 원문** — [docs/evidence/admission_generation_freeze_2026-10-15.md](../evidence/admission_generation_freeze_2026-10-15.md) 소관. 본 문서는 규범만 담는다.
