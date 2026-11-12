# closure-watcher 운영 배선 addendum — main 관측·시험 실측 (2026-10-11)

선행: `closure_watcher_operational_wiring_2026-10-11.md` (PR #731, merge commit
`a517058f`). 본 문서는 착지 후 main에서의 기계적 관측 기록이다. 후속 수정 PR:
#734 (merge commit `2eb0509a`).

## 1. 착지 직후 결함 발견과 수정 (PR #734)

- main에서 첫 drift-test dispatch(run **38130258653**)가 적색이어야 할 시험을
  fixture 없이 실측 대조(녹색)로 통과시켰다 — 시험 스위치 무발화의 조용한 녹색.
- 원인: workflow_dispatch 페이로드의 `github.event.inputs.drift_test`는
  `type: boolean`과 무관하게 문자열이고 표현식 `==`는 타입 강제가 없어
  `("true" == true)`는 항상 거짓. → quirks **Q7**로 문서화
  (docs/spec/gh_run_observation_quirks.md) + 형식화 `inputs` 컨텍스트로 수정
  (PR #734, commit 150e7152c) + 역방향 계약 명시("drift-test dispatch의 정상
  완료는 적색 런이다").

## 2. 녹색 분리 경로 (main dispatch, run 38130079957 — conclusion success)

| 잡 | 결론 | 의미 |
|---|---|---|
| detect | success | deriver 재유도·핀 대조(실측 감시 경로) |
| report | **skipped (by design)** | `if: failure()` — 녹색 탐지에서 발행 없음 |
| sweep-test-issues | success (no-op) | 마커 이슈 0건 — 멱등 no-op |

잡별 GITHUB_TOKEN 권한 블록(런 로그 실측, quirk Q3의
`--allow-escape-sequences` 경유):
- detect: `Contents: read` + `Metadata: read` — **Issues: write 부재**
- sweep-test-issues: `Issues: write` + `Metadata: read` — **Contents 부재**

→ 최소권한 분리가 실제 토큰에서 집행됨을 확인.

## 3. 합성 드리프트 발행 경로 — dispatch 문맥 (run 38131967208, Q7 수정 후)

| 잡 | 결론 | 의미 |
|---|---|---|
| (런) | **failure — 적색이 시험의 정상 완료** | 역방향 계약 충족 |
| detect | failure | fixture 주입 확인(MODE JUDGMENT 라인) + 의도 불일치 탐지 fail-closed |
| report | success | 추적 이슈 발행 성공 |
| sweep-test-issues | success | 동일 런 내 마커 이슈 종결(self-cleaning) |

- 테스트 이슈: **#735** `[closure-watcher-test] synthetic drift publish-path
  probe (run 38131967208)` — created 2026-10-11T10:27:02Z → closed
  2026-10-11T10:27:13Z(수명 11초, 동일 런 sweep).
- report 잡 권한 블록: `Issues: write` + `Metadata: read` 단독 — job-level
  permissions의 완전 대체 의미론(미지정 권한 none) 실측.
- sweep crash-safety: open-마커 검색 기반 종결이라 재실행 멱등 — 이미 종결된
  #735는 재대상이 되지 않는다(관측: 종결 후 open 마커 이슈 0건 수렴).

## 4. schedule 문맥 권한 동등성 — 변수 프로브 **완료 (실측 확정)**

방법: repo Actions 변수 `CLOSURE_WATCHER_DRIFT_TEST=1` 설정(2026-10-11T10:26Z,
read-back 확인) → 다음 실 슬롯의 schedule 런이 fixture 탐지·발행·sweep을 수행 →
런 로그의 잡별 권한 블록을 dispatch 런과 대조 → 변수 해제.

**관측 결과**: 12:17Z 슬롯은 **12:48:35Z**에 발화(+31.6분 — on-time 계약 이내,
GitHub 무 SLA의 지연 분포 내). 실 schedule 런 **38140682632**:

| 잡 | 결론 | 의미 |
|---|---|---|
| (런) | **failure — 적색이 프로브의 정상 완료** | schedule 문맥에서도 역방향 계약 성립 |
| detect | failure | fixture 모드 발화(변수 경로) + 의도 불일치 탐지 fail-closed |
| report | **success** | **schedule 이벤트에서 이슈 발행 성공** |
| sweep-test-issues | success | 마커 이슈 동일 런 종결(self-cleaning) |

- 테스트 이슈: **#739** `[closure-watcher-test]` — created 2026-10-11T12:48:53Z →
  closed 12:49:03Z(수명 10초, 동일 런 sweep).
- **권한 동등성 판정 — schedule ↔ workflow_dispatch, 런 로그 실측 일치**:

| 잡 | dispatch 문맥(런 38131967208) | schedule 문맥(런 38140682632) | 일치 |
|---|---|---|---|
| detect | Contents: read + Metadata: read | Contents: read + Metadata: read | ✓ (Issues: write 양쪽 모두 부재) |
| report | Issues: write + Metadata: read | Issues: write + Metadata: read | ✓ (Contents 양쪽 모두 부재) |
| sweep | Issues: write + Metadata: read | Issues: write + Metadata: read | ✓ |

- 프로브 변수는 관측 후 **해제**(2026-10-11T12:5xZ, 잔여 변수 = CI_RUNNER_MAP만
  read-back 확인) — 정상 상태 복원. 재프로브는 변수 1행 설정으로 언제든 반복
  가능하다(문서화된 절차).

## 5. 슬롯 원장 갱신 (수집 2026-10-11T13:0xZ — 프로브 런 포함 최종)

원본: `closure_watcher_slot_ledger_addendum_2026-10-11.{json,md}` (동일 디렉터리).
수집 창: 등록 2026-10-09T21:20:30Z .. 13:0xZ.

| metric | 값 |
|---|---|
| expected_slots | 7 |
| observed_slots | 5 |
| on_time (≤+60분) | 2 (12:17Z 슬롯 = 프로브 런 38140682632, +31.6분 포함) |
| late | 3 (최대 +334.8분) |
| missed | **2** (10-10 06:17Z, 10-11 06:17Z — 런 기록 전무, 부재만이 증거) |
| pending | 0 |
| cancelled | 0 |
| hollow (녹색이나 detect 미실행) | 0 |
| unattributed | 0 |

- 결손 2건은 모두 **런 기록이 전혀 없는 슬롯**이다 — dropped schedule은 부재만이
  증거다. 지연 분포(13.6/31.6/205.9/328.3/334.8분)는 GitHub 무 SLA 아래에서
  +60분 on-time 계약과 +6h 결손 컷오프의 실측 근거다.
- 정보성: 구정의 녹색 런의 skipped **스텝**(`if: failure()` 발행 스텝)과 신정의
  녹색 런의 skipped **report 잡**(`if: failure()`)은 by-design이다 — 녹색에서의
  이들 스킵은 hollow가 아니다(원장의 hollow는 detect-class 잡이 success가 아닌
  녹색만 계수). 녹색 런의 skipped **detect-class 잡**은 0건.
- 신뢰 한계: rule of three — "0 missed"의 95% 신뢰 주장은 N≥60 슬롯(4슬롯/일 ×
  **15일**)을 요구한다. 현재 7슬롯·결손 2건은 창 진행 중(window in progress)의
  관측 개시 기록이지 신뢰 진술이 아니다. 14일 원장(W=56) 목표 수집 시점은
  2026-10-24 경이다.

## 6. 운영 판정 요약

- **OPERATIONAL (지금부터)**: 6시간 주기 실측 감시(detect, contents: read 단독),
  드리프트 적색화 + 추적 이슈 자동 발행(report, issues: write 단독) + 마커 테스트
  이슈 자동 정리(sweep, 멱등) — **dispatch와 schedule 양 문맥에서 모두 기계적으로
  관측됐다**(§2·§3·§4). merge admission에 대한 무권한은 변함없다(적색 = 관측
  신호, 머지 비차단). 본 감시자는 config/ 정책 SSOT을 수정하지 않는다.
- **LONGITUDINAL (남는 것)**: (1) 14일 원장(W=56 슬롯) 완성 — 2026-10-24 경
  재수집, (2) N≥60 슬롯(15일) 도달 전까지 "0 missed" 신뢰 주장 보류(현재 7슬롯,
  결손 2건), (3) 지연·결손 장기 분포 축적 — `queue: max` 채택 판단은 이 데이터가
  모인 뒤 별도 슬라이스에서.
