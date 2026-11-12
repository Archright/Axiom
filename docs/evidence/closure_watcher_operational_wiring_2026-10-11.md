# closure-watcher 운영 배선 — P4 R2 (2026-10-11)

## 근거·목적

- docs/evidence/trust_root_reaudit_2026-10-10.md §7.3 + 승인 계획(2026-10-10) S4':
  신뢰 루트 클로저 감시자(closure-watcher)를 상시 운영 상태로 배선한다.
- 본 슬라이스 범위: detect/report 권한 분리, 제어된 드리프트 시험(fixture 주입),
  schedule 슬롯 원장(latency 계약 명시), failure semantics 문서화.
- R2 감시자에게 merge authority는 없다 — 본 문서의 모든 적색 판정은 merge
  admission을 막지 않는다(아래 failure semantics).

## 표면 절차 판정 (pre-check 결과)

- `config/repository_surface.json` 현행 policyVersion **74**, `defaultClass: PRODUCT`,
  해석 순서 PRODUCT → CONTROLLED → FROZEN(first-match).
- `.github/workflows/closure-watcher.yml`은 v73 정책 PR이 **CONTROLLED에 선등록**한
  경로다(파일 헤더의 착지 기록 + 현행 JSON `classes.CONTROLLED` 실재 확인).
- `rules.CONTROLLED.MODIFY = PASS` (repository_surface_contract.md 등급·규칙표).
  **결론: 이미 등록된 파일의 수정은 본문 PR 단독으로 허용된다** — v52~v72의
  "정책 선등록 PR → 본문 PR" 2단 절차는 신설(ADD) 대상이며 본 건(FROZEN glob
  `.github/**` 흡수를 CONTROLLED 등록이 선승)에는 적용되지 않는다.
- 실측: `make check-repository-surface` (base-policy binding = merge-base(origin/main))
  → **PASS** (본문 커밋 후 재실행 결과는 본 PR 체크에 기록).

## 변경 내용 (.github/workflows/closure-watcher.yml, 신설 워크플로 파일 0건)

1. **권한 분리(GitHub 공식 지원 job-level permissions)**
   - 워크플로 기본: `contents: read` 단독(탐지 최소권한).
   - `detect`: 읽기 전용 — deriver 재유도 + 핀 대조(fail-closed).
   - `report`: `needs: [detect]` + `if: failure()` + `permissions: issues: write`
     단독(job-level — 미지정 권한은 전부 none으로 강제되는 완전 대체). 탐지 결과는
     artifact(`closure-drift-findings`, drift 시에만 존재) + `outputs.head_sha`로 전달.
   - `sweep-test-issues`: `needs: [detect, report]` + `if: always()` + `issues: write`
     단독 — 테스트 이슈 정리(아래 참조).
   - 유지: `cron: '17 */6 * * *'`(정각 회피 — 공식 고부하 완화),
     `concurrency: {group: closure-watcher, cancel-in-progress: false}`.
   - follow-up(선택): `queue: max`(최대 100 pending, cancel-in-progress 불요)로
     pending 대체 상실을 완화할 수 있다 — 최소 변경 원칙으로 현행 유지, 원장 실측
     후 별도 슬라이스에서 판단.
2. **제어된 드리프트 시험 — fixture 주입(live config 편집 금지)**
   - `workflow_dispatch` input `drift_test` 또는 repo Actions 변수
     `CLOSURE_WATCHER_DRIFT_TEST=1`로 가동. 적색 런 자체가 시험의 정상 완료다.
   - 합성 입력은 `tests/fixtures/closure_watcher_drift/` 핀·유도 파일로의
     **경로 파라미터 전용**이다(`PIN_FILE`/`DERIVED_FILE` env). `/tmp` 표준 경로로의
     복사도 config/ 접촉도 없다. 대조 코드 경로는 양 모드 동일(입력 경로만 다름).
   - 변수 경로의 존재 이유: **dispatch는 schedule을 증명하지 않는다** — GITHUB_TOKEN
     권한은 이벤트별로 다를 수 있으므로 실 schedule 문맥의 발행·권한 동등성은
     schedule 런으로만 검증된다. 설정 잊음의 실패 모드는 조용한 녹색이 아니라
     반복 적색+마커 이슈라 즉시 가시다(fail-closed).
   - 테스트 이슈 겸리: 제목 마커 `[closure-watcher-test]`. 실드리프트 dedup 검색
     토큰(`closure mismatch`)과 테스트 토큰(`closure-watcher-test`)은 교집합이 없어
     dedup·sweep 상호 오염이 없다. sweep은 **마커가 붙은 열린 이슈만** 닫는
     crash-safe 멱등 작업이다 — 런 중단으로 남은 이슈는 다음 런(모드 무관,
     `if: always()`)의 sweep이 수렴 정리하고, 재실행은 안전하다(open 검색).
3. **failure semantics(워크플로 헤더에 명시)**
   - 탐지 실패·발행 실패 모두 워크플로 적색(탐지 관점 fail-closed). **merge
     admission은 막지 않는다** — required check가 아니다(R2 무권한).
   - 감시자는 정책 SSOT(config/ 핀)을 절대 수정하지 않는다 — 탐지·보고만;
     수복 판단은 부채/오너 authority(reaudit §6.4).
   - cancelled 런은 drift 증거가 아니다(concurrency pending 대체) — 원장 별도 계수.
4. **latency 계약(GitHub는 schedule 지연 SLA가 없다 — 공식 문서)**
   - 슬롯 = cron UTC 격자. OUR contract: 슬롯+60분 내 시작 = on-time, 초과 = late,
     슬롯+6h(1주기) 내 무관측 = missed 확정. +6h 근거: 관측 최대 지연 5.5h.
   - 원장 수집: `tools/ci/closure_watcher_slot_ledger.py`(신설 — cron 슬롯 열거,
     `event=schedule` 전 기간 페이지네이션 질의, 최신-슬롯-≤-시작 귀속, hollow
     판정 = 녹색이지만 detect-class 잡이 success 아님, designed skip은 정보성 별도
     계수). 필터 질의 1,000건 상한 근접 시 창 분할 경고.
5. **quirk Q4 준수**: run: 블록 전체(주석 포함)에 보간 토큰 0건 — 동적 값은
   env/with/if/outputs 매핑(식 컨텍스트)으로만 주입. 실측:
   `tools/ci/validate_workflow_shell.sh` PASS(본 파일 run 블록 6개 포함 전수 bash -n).

## 초기 슬롯 원장 (등록 시점 2026-10-09T21:20:30Z .. 수집 2026-10-11T09:21Z — 창 진행 중)

원본: `closure_watcher_slot_ledger_initial_2026-10-11.{json,md}` (동일 디렉터리).

| metric | 값 |
|---|---|
| expected_slots | 6 |
| observed_slots | 4 |
| on_time (≤+60분) | 1 |
| late | 3 |
| missed | 1 |
| pending (결손 컷오프 미도래) | 1 |
| cancelled | 0 |
| hollow (녹색이나 detect 미실행) | 0 |
| unattributed | 0 |

- **missed 1건**(2026-10-10T06:17Z): 관측 런이 전혀 없다 — dropped schedule은 런
  기록을 남기지 않으므로 부재만이 증거다. **late 3건**(최대 +334.8분): GitHub는
  schedule 지연 SLA가 없으며 고부하 시 수 시간 지연이 관측됐다 — 위 latency 계약의
  직접 근거다. hollow 0건: 녹색 3건 모두 detect-class 잡이 실제 실행·성공.
  정보성: 구정의 녹색 런은 `if: failure()` 발행 스텝이 by-design으로 skipped다
  (스텝 단위 스킵 — 잡 스킵 아님, hollow 아님).
- **판정: 창 진행 중(window in progress)** — rule of three에 따라 "0 missed"를
  95% 신뢰로 주장하려면 N ≥ 60 슬롯(4슬롯/일 × **15일**)이 필요하다. 현재 6슬롯은
  증명이 아니라 관측 개시 기록이다. 14일 원장(W=56 슬롯)은 2026-10-24 경 수집
  예정이며, 그 때도 N<60이면 규칙상 신뢰 주장을 보류한다.
- 참고(기존 런의 유의미한 적색): 2026-10-10T12:17Z 슬롯 런(38052214094)은 **실제
  드리프트 실측**으로 적색이 됐고 추적 이슈 #701이 자동 발행됐다(동 런의
  `if: failure()` 스텝, schedule 문맥 GITHUB_TOKEN 로그 블록 = Contents: read /
  Issues: write). 이슈는 2026-10-10T21:28Z 종결됐다. 구정의(schedule 레벨
  issues: write)에서의 발행 성공 실측이며, 본 슬라이스는 이를 job-level 분리로
  재검증한다(아래 검증 계획).

## 검증 계획과 상태 (본 PR 시점)

| 검증 | 방법 | 상태 |
|---|---|---|
| 합성 입력 탐지 로직 | 로컬 dry-run: fixture 대조 → exit 1, pin-only=0 / derived-only=1, findings 파일 생성 | **PASS(실측)** |
| run 블록 셸 문법 | `tools/ci/validate_workflow_shell.sh` 전수 bash -n (본 파일 6블록 포함) | **PASS(실측)** |
| Q4 보간 토큰 | 파서 기반 검사: run: 블록 내 토큰 0건 | **PASS(실측)** |
| YAML 파싱 | python yaml.safe_load + 잡/권한 구조 단언 | **PASS(실측)** |
| 발행 경로(dispatch 문맥) | 브랜치 dispatch drift_test=true → 적색 런 + `[closure-watcher-test]` 이슈 생성 + 동일 런 sweep 종결 | PR 런으로 보강(아래 기록) |
| 발행 경로(schedule 문맥)·권한 동등성 | 변수 `CLOSURE_WATCHER_DRIFT_TEST=1` 설정 → 다음 실 슬롯 런이 fixture 탐지+발행+sweep → 런 로그의 잡별 GITHUB_TOKEN 권한 블록을 dispatch 런과 대조 → 변수 해제 | 착지 후 수행(addendum 증거) |
| 녹색 분리 경로(착지 후 main) | dispatch(드리프트 없음) → detect success / report by-design skip / sweep no-op | 착지 후 수행(addendum 증거) |

권한 동등성 판정 방법: GitHub 런 로그는 잡별 유효 GITHUB_TOKEN 권한 블록을
출력한다 — detect(Contents: read, Issues: write 부재)와 report/sweep(Issues:
write, contents: 없음)의 블록을 **schedule 런과 dispatch 런에서 각각 추출해
동일성을 대조**한다(quirk Q3: 로그 API는 `--allow-escape-sequences` 필요).

## 남는 것 (정직한 잔여 목록)

1. 14일 슬롯 원장(W=56) + N≥60 규칙 충족까지의 신뢰 주장 보류 — 장기 관측 과제.
2. schedule-문맥 발행·권한 동등성 실측은 다음 실 슬롯에서만 가능 — 최대 관측
   지연 5.5h를 고려하면 최장 ~12h 대기가 필요할 수 있다(결과는 addendum).
3. `queue: max` 채택 여부 — 원장 실측 후 별도 슬라이스.
