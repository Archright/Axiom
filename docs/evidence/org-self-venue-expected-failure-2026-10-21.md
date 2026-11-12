# org self-venue 예상 실패 기록 — 2026-10-21 (P1: 비권위적 실패로 수용)

> **Status**: 관측 기록 (결정 문서가 아님). 근거 결정: [ADR-0035 §4](../adr/0035-admission-ssot.md) §4
> ("org self-venue = P1 — 비권위적 실패로 문서화·수용").

## 1. 관측 대상

org 저장소 `Archright/.github`의 워크플로 `.github/workflows/admission-gate-v2.yml`가
**자기 저장소 안에서** 자기 자신을 실행할 때(PR 이벤트) — 즉 org 게이트가
**자기 venue에서** Axiom 게이트를 호출하려는 형태.

## 2. 실측 (2026-10-21)

```
GET repos/Archright/.github/actions/workflows/admission-gate-v2.yml/runs?per_page=100
  → total 25, conclusion=failure 25, success 0, skipped 0

GET repos/Archright/.github/actions/runs/<id>/jobs   (예: 39551173894)
  → total_count = 0   (job이 하나도 생성되지 않음)

gh run view 39551173894 --repo Archright/.github
  → "This run likely failed because of a workflow file issue."
```

UI에 표시되는 오류는 워크플로 파일 파싱 단계의 진단이다(verbatim, Actions
워크플로 페이지):

> Invalid workflow file: `.github/workflows/admission-gate-v2.yml` — error parsing called workflow
> `Archright/Axiom/.github/workflows/admission-check.yml@7e0caa62…`: workflow was not found.

(위 verbatim 문구는 2026-10-21 진단 시 Actions 워크플로 페이지에서 확인한
것이다. REST로는 0-job run의 워크플로 파일 단계 오류가 노출되지 않아
check-suite/check-run annotations 엔드포인트가 404를 반환한다 — 기계로
재현 가능한 것은 **25/25 실패 + 0 jobs**이며, 인과 해석은 아래 §3의 공식 규칙
+ 저장소 가시성 실측이 지지한다.)

## 3. 인과 (구조적 사실)

| 사실 | 실측 |
|---|---|
| 호출자(org 저장소) 가시성 | `Archright/.github` = **public** (`private: false`) |
| callee(Axiom 저장소) 가시성 | `Archright/Axiom` = **private** (`private: true`) |
| 호출 형태 | `uses: Archright/Axiom/.github/workflows/admission-check.yml@7e0caa62…` (공개 → 비공개 reusable workflow 호출) |

GitHub 공식 규칙: **공개 저장소의 워크플로는 공개 reusable workflow만 호출할 수
있다**(호출자·called 중 하나라도 비공개면 호출 단계 자체가 실패하며 job은
생성되지 않는다 — 무관한 단계는 0개가 시작된다). 권한 상향으로 이 제약을
해결할 수 없다(공개→비공개 호출은 권한이 아니라 가시성 문제).

## 4. Axiom 게이트는 영향받지 않는다 (무영향)

ruleset 25218071(`axiom-admission-gate`, org 소유)의 `workflows` 룰은
sha 고정된 워크플로를 **Axiom 저장소의 private 컨텍스트에서** 실행한다:

```
{path: .github/workflows/admission-gate-v2.yml,
 repository_id: 1182157951, sha: c1752d7ebbcff1d01d82c922a5f97d5b86622880}
```

→ Axiom 저장소 안의 merge_group run은 정상 실행·판정된다(2026-10-21 실측:
merge_group head `5011d9d3…`의 `verdict / admission-check` = success,
`bsec-integrity` = success, `debt-registry-gate` = success). org 저장소
self-venue의 실패는 **Axiom의 병합 게이트와 무관한 별개 venue**다.

## 5. 왜 "수용"인가 (inert, 비권위적)

- 실패 venue는 ** Axiom의 merge_group 베뉴가 아니다** — Axiom의 랜딩 경로에
  영향을 주지 않는다(§4).
- 이 venue가 빨갛다는 사실 자체는 **진단 신호로는 유용**하지만(공개 호출 →
  비공개 callee 구조는 실측으로 확정), Axiom의 **권한**을 더하거나 **병합
  가능성을 바꾸지 않는다**.
- 설령 접근이 가능해져도(가시성 변경), 이 venue는 별도 실패 축을 가진다
  (`CI_RUNNER_MAP` 미설정, B-tree 경로 등) — 즉 **빨간 채로 남을 가능성이
  높다**. 이 때문에 이 venue의 통과/실패를 Axiom의 준비도 신호로 삼으면
  **비권위적 실패를 권위적 신호로 오독**하는 구조가 된다(AGENTS.md §0.9
  극장 금지의 대면).

## 6. 조치

- **조치 없음** (결정 #4: P1 — 비권위적 실패로 문서화·수용). Axiom 저장소의
  어떤 게이트·정책·판정도 이 venue의 결과에 의존하지 않는다.
- org 저장소의 해당 venue는 org 소유 자산이며, Axiom 저장소의 CI/게이트
  스코프 밖이다(Out of Scope — 계획 §6 P2/P3/P4).
- 본 기록은 ADR-0035 §4의 근거 문서이며, `RotationAllowlistExtra`에
  회전 동반 경로로 열거되어 있다(회전 PR이 동반 증거 문서를、结构적으로
  거부하지 않도록).
