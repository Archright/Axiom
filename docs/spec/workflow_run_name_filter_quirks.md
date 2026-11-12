# `workflow_run` Name-Filter Registration-Generation Quirks

> AGENTS.md §0.5 Quirk Mandate 기록 — GitHub Actions 플랫폼 quirk(언어·툴체인
> 외부). B3 착지(PR #1213, merge `8c46c4ea8a635dc468248470732e1084c08863a7`,
> 2026-11-02T07:57:49Z)가 `.github/workflows/ci-cache-publisher.yml`의
> `on.workflow_run.workflows` 필터를 이름 화이트리스트로 축소하면서 그 전제가
> 된 실측 사실을 문서화한다. 선정 근거:
> `docs/evidence/ci_cost_b2_selection_b4_prereg_2026-11-02.md` §3.

## Q1 — `workflows:` 필터는 이름 매칭이며, 이름 해석은 현재 등록 세대에 의존한다

**Class**: GitHub Actions 플랫폼 — `workflow_run` 트리거 × org ruleset
required workflow(소스 `Archright/.github`, ruleset `workflows` 룰)

### 사실

`on.workflow_run.workflows:`는 workflow의 **이름**(name)으로 매칭한다 —
파일 path가 아니다. 이름 해석 대상은 그 시점에 **등록된 required workflow
세대**다. org ruleset 주입 필수 워크플로의 YAML은 Archright/.github이
소유하므로, 등록 세대가 바뀌면(파일 rename·ruleset path 필드 갱신·재등록)
같은 트리거 파일이 **다른 이름 세계**에서 해석될 수 있다 — repo 측 파일은
바이트 불변이어도 매칭 결과가 세대에 따라 달라진다.

등록 세대의 identity 단위는 ruleset `WorkflowFileReference`의
`(repository_id, path)` 쌍이다(2026-10-12→10-16 실측 사건의 조사 가설이자
회복 수단 — 아래 Q2). 이름 필터 소비자는 이 쌍이 발화시키는 run의 기록
identity(`name`, `path`)에 간접 의존한다.

### 실측 근거

- 현재 등록 세대의 게이트 완료 run 기록 identity: `name='admission-gate'`,
  `path='.github/workflows/admission-gate-v2.yml'` (run 39893960477 판독,
  2026-11-02). 파일은 Archright/.github 소유 — `path`는 ruleset이 가리키는
  소스 경로이지 Axiom repo 내 파일이 아니다.
- 이름 매칭의 현재 유효성 라이브 실측: `ci-provider-router.yml`(동일 이름
  화이트리스트 — `admission-gate` 포함 5종을 failover 권위로 상용)의 router
  run **41404148309** guard가 게이트 런 **41403237625**(merge_group) 완료의
  workflow_run 이벤트 수신을 기록(2026-11-02). 두 이름-필터 소비자
  (router, publisher)가 같은 플랫폼 사실에 의존한다.

## Q2 — 실측 사건(2026-10-12→10-16): 세대 드리프트의 실패 방향은 낭비가 아니라 침묵이다

2026-10-12 ruleset-required 전환 창에서 required workflow의 이벤트
바인딩(`(repository_id+path)` 단위 가설)이 사멸했다:

- **증상**: 게이트 완료 후 publisher·router의 workflow_run 발화 0건 —
  핀 회전(10-15T20:10Z) 이후 미전달 이벤트 160+건, 대상 게이트 런
  38842738723·38846646087·38847179520.
- **회복 시도 중 실패한 경로(G1 실험, 2026-10-16)**: 멱등 PUT 재등록
  (readback diff 빈 파일·`updated_at` 무갱신 = 서버 완전 no-op)과 룰
  제거→재등록(새 `updated_at` 발급) 양쪽 모두 구독 재부착에 실패.
  양성 대조로 발화 회로 자체는 생존 확인(observation.yml 완료 → publisher
  ~2s 내 발화) — 소실은 게이트 바인딩에 국한.
- **회복**: `admission-gate.yml` → `admission-gate-v2.yml` rename + ruleset
  path 필드 갱신 = **새 `(repository_id+path)` 쌍 발급**(G1 권장 후속 ②;
  2026-10-16). 이후 이름 해석 회복 — 2026-11-02 라이브 재확인(Q1 실측).
  현재 게이트 path가 `-v2.yml`인 역사적 이유가 이 rename이다.
- **실패 방향 규율**: 이 사건의 장애 형태는 과잉 발화(낭비)가 아니라
  **침묵(0발화)**이다. 트리거 소비자 입장에서 이름 해석이 깨지면 발화 0 =
  시딩 공백 = 성능 저하(fail-open)이지 red 아니다(게이트·병합 권위와
  무관). 탐지는 기능 계약(시딩 소비 지표 급락)으로 하고, 복구는 트리거 폭
  후퇴 수정 PR로 한다(B2 §4.5 기능 계약·§5.3 롤백 유형 4).
- **당시 완화와 그 잔여**: 10-15에 publisher 트리거를 `['*',
  '!ci-cache-publisher']`로 폭 완화해 침묵을 우회했다(이름 필터 포기).
  부작용으로 비게이트 완료 발화가 publisher 런 8,762건 중 ~71.4%를 점유
  (31일 실측 — `ci_epoch_record_2026-10-25-publisher-job-if.md` 부록 A).
  B3(#1213)는 이름 해석 회복을 라이브 재확인한 뒤 이 폭을 다시 좁힌 것이며,
  그 전제의 취약성이 본 문서의 존재 이유다.

## Q3 — B3(#1213) 설계: 화이트리스트 + 부존재 이름 예비항

PR #1213이 채택한 형태(`.github/workflows/ci-cache-publisher.yml`):

```yaml
on:
  workflow_run:
    workflows: ['admission-gate', 'admission-gate-v2']
    types: [completed]
```

- 제1항 `admission-gate` = 현재 등록 세대의 run 이름(Q1 실측).
- 제2항 `admission-gate-v2` = **존재하지 않는 이름의 드리프트 예비항** —
  문서상 존재하지 않는 이름 항은 매칭에 영향이 없다. 미래 세대 전환이
  등록 이름을 이 항과 일치시키면 수정 없이 흡수한다(예비항의 의도).
- 자기-연쇄(publisher 완료 → publisher 재발화)는 화이트리스트에 publisher
  이름이 없어 구조적으로 배제된다(구 `!ci-cache-publisher` 위생 항 소멸).
- **게시 판정 authority는 이름 항이 아니라 in-job guard다**: guard가 API로
  트리거 run의 `path`(`.github/workflows/admission-gate-v2.yml`, `@ref`
  suffix 허용 — `ci_provider_failover_quirks.md` Q-series의 path 규율)를
  읽어 fail-closed 판정한다. 이름 항은 넓은 그물이고, path guard가
  최종 authority다 — 세대 드리프트로 이름 그물이 빈 경우의 최악은 발화
  부재(침묵)이지 오판 발화가 아니다.
- 이중 예비 항에도 불구하고 남는 잔여: 등록 세대가 제1·2항 어느 이름과도
  다른 세 번째 이름으로 전환되면 발화 0이 된다 — 이는 Q2의 실험 실패 행
  (아키텍처 대안 승격)과 동일한 탐지·복구 경로를 따른다.

## Q4 — 관측 비대칭: 트리거 측 증명은 guard 값으로 한다

org-hosted 게이트 런은 repo runs API로 열거 불가하다
(`gh_org_required_workflow_run_quirks.md` — workflow_id가 repo 스코프 밖,
`gh run view` 404 class). 따라서 "게이트 완료가 publisher를 발화시켰는가"
의 트리거 측 증명은 런 목록 대신 다음으로 한다:

1. **publisher 런 존재·빈도**: publisher는 in-repo workflow이므로
   `gh run list --workflow ci-cache-publisher.yml` 정상 열거 가능.
2. **게이트 귀속 판정**: publisher publish 잡의 guard 로그(`guard=true`,
   `[publish-skip] run path '…' != …`)가 트리거 run의 path를 API로 재판정한
   값 — 이것이 게이트 귀속의 기록 증거다.
3. **트리거 이벤트 수신의 간접 증명**: 동일 이름 필터를 상용하는 router의
   guard 로그(Q1 실측) — 두 소비자가 같은 플랫폼 사실에 의존하므로 수신
   가능성의 교차 근거가 된다.

양성 페어링(게이트 완료 1건 → publisher 런 1건)의 최초 관측 기록:
`data/e4e5/landing_boundaries/2026-11-02T075749Z-publisher-trigger-whitelist.json`
(B3 착지 경계 기록 — `first_post_change_merge_group_run`).

## 판정 규칙 (요약)

1. `workflow_run.workflows` 이름 항을 작성·수정할 때는 **현재 등록 세대의
   run 이름을 라이브 판독**해 근거로 남긴다(파일 경로를 쓰지 않는다).
2. 이름 해석 의존 변경의 실패 방향은 침묵이다 — 발화 0을 "조용한 정상"으로
   넘기지 않고 기능 계약(B4류 시딩 소비 지표)으로 탐지한다.
3. 등록 세대 전환(rename·재등록)은 같은 repo 파일의 매칭 결과를 바꾼다 —
   세대 전환 기록에는 이름 필터 소비자(publisher·router 등)의 재검증
   항목을 반드시 포함한다.
4. 트리거 측 증명이 필요하면 guard 값·소비자 로그로 한다(Q4) — org 게이트
   런의 목록 열거 시도는 404 class(Q4에서 참조 문서)로 실패한다.
