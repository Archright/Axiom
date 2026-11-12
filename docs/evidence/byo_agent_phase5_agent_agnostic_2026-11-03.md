# BYO-Agent Phase 5 — Agent-Agnostic 명제 검증·실 에이전트 live 실행 (2026-11-03)

Phase 4(`byo_agent_phase4_customer_deployment_2026-11-03.md`)가 **배포 계층**(외부 저장소 → SHA-핀 Axiom 검증 → upstream 보고)의 무인 수직 슬라이스를 관측한 뒤, 남은 두 축을 관측한 실행 기록: ① **INCAPABLE 2축 상태 모델**(capability/verification 분리 — AI 자율성 보존·Axiom 능력 정직 공개), ② **실제 LLM 에이전트가 고객 CI 안에서 명제를 직접 생성**하는 live 실행. 계약: `docs/spec/byo_agent_proposition_contract.md`.

## 1. 엔진 착지 — 2축 상태 모델 + INCAPABLE (PR #1241 → SHA₁)

PR #1241(merge `56fea85c3c7c968eaa637fd373f8d0e8d3c9f9b3`, 2026-11-03T10:05:36Z). 4-커밋 구조:

| 커밋 | 내용 |
|---|---|
| `be4ef1959` | 제로웨이브 런(eligible=0)에서 `runVerificationWaves`가 `unitEvidence`(JObject)를 구성하지 않아 `appendDisplayAndPersist`의 nil 순회로 SIGSEGV(exit 139) — **생산자 불변식**으로 수정(진입부 `newJObject()` 초기화, 병합부 죽은 lazy-init 제거). unitEvidence는 "항상 JObject, 제로웨이브 = 빈 합집합" |
| `facba0ab9` | selftest 3c fixture를 putUVarint(NOT_EQUIPPED 레인) 타깃으로 교정 — 기존 fixture가 toOpenArray(EQUIPPED)를 스윕해 DISPROVED→exit 1이 나는 것이 Job 3c 실패의 나머지 절반 |
| `f7615d6cf` | pin rotation reanchor(`bin/reanchor_pin --ref HEAD --write`, ref 트리 기반) |
| `5092f2b29` | `architecture_debt.json` 엔진 해시 1엔트리 재기록(`bin/debt_engine --regen-arch`) — 첫 푸시가 push-admissibility Part A에서 차단된 원인 |

**판정 상태 모델(2축)**: 기존 `propositionVerdict` 3값(PROVED/DISPROVED/UNKNOWN — 실제 검증의 결과)을 보존하고, 능력 판정을 별도 축으로 분리했다:

```json
{"id":"prop-varint-rt","capability":{"status":"INCAPABLE","reason":"LANE_NOT_EQUIPPED"},"verification":{"attempted":false,"verdict":null}}
```

- Capability Assessment → Verification 순서: 가능한 경우에만 실제 검증을 수행한다.
- per-unit 독립 처리: 한 명제가 INCAPABLE여도 나머지 명제의 검증을 중단하지 않는다.
- all-INCAPABLE의 exit 0은 **프로그램 실행 성공이지 검증 성공이 아니다**(§8 — "검증 완료된 명제: 0개"의 정직 표시).

관측(selftest head `5092f2b29`): run [41611754462](https://github.com/Archright/Axiom/actions/runs/41611754462) 전 Job green — Job 3c는 "exit 0 ∧ reportable units 0 ∧ rollup persist(INCAPABLE 2건)"를 기계 관측. base 이동(#1240·#1242 랜딩)으로 mint-prepare A0 fail-closed 발생 → `gh pr update-branch`(GitHub 네이티브 병합 `51c0f4b30`) 후 재발화 run [41613152993](https://github.com/Archright/Axiom/actions/runs/41613152993) 전 green.

## 2. 고객 베뉴 착지 — 핀 갱신·재활성화·incapable 사전검증

- 고객 저장소 `Archright/byoa-customer` 워크플로의 `uses:`/`axiom-ref:` 핀을 `dd31ca68…` → `56fea85c…`(SHA₁)로 갱신, push `6af9715`(미푸시였던 `124f83f` 동반 착지).
- 재활성화: `PUT /repos/Archright/Axiom/actions/permissions/access -f access_level=organization`(§2.4 — `gh auth token | gh secret set` 파이프로 `AXIOM_READ_TOKEN`·`SUBJECT_REPORT_TOKEN` 프로비저닝).
- **incapable 사전검증(모델 호출 없음)**: run [41617645516](https://github.com/Archright/byoa-customer/actions/runs/41617645516) 전 Job success — SHA₁ cross-repo 재사용 workflow 경로·시크릿·2축 엔진이 고객 베뉴에서 실증. state artifact 실측:

| 필드 | 실측값 |
|---|---|
| `canonicalRunDigest` | `1b0455cc95f8668ff90e30abe839143dd3e8030a5ab2b29a6a0c8e1936789603` |
| rollup | `prop-varint-rt` INCAPABLE{LANE_NOT_EQUIPPED} + `prop-claim-form` INCAPABLE{UNSUPPORTED_LOGIC} — `verification.attempted=false`, `verdict=null` |
| units | 0 (exit 0 — §8: 실행 성공≠검증 성공) |
| proposals 문서 sha256 | `f55dbf25439eca08cfcee0a975808a81ec4bf436a2effabed7b41aad80f79baf`(evidence 사본·Job1 artifact 사본 일치) |

## 3. 재현성 — incapable 4-tuple

재현성 증거는 `canonicalRunDigest` 단일가 아니라 **4-tuple 일치**로 관측한다(proposals 문서 SHA-256 · subject 커밋 · Axiom 커밋 · canonicalRunDigest — digest는 명제 문서 전체를 직렬화하지 않으므로).

| 실행 | 환경 | canonicalRunDigest |
|---|---|---|
| CI | byoa-customer run `41617645516`(SHA₁ 핀) | `1b0455cc…789603` |
| d1 | 로컬(`/tmp/axiom-56fea85c` 빌드, 신규 state) | `1b0455cc…789603` |
| d2 | 로컬(독립 신규 state) | `1b0455cc…789603` |

- d1·d2 모두 `EXIT=0`, state는 jq 정규화 후 **완전 동일**(STATE-IDENTICAL).
- 4-tuple 전 일치: proposals `f55dbf25…` · subject `a130a7f32219909bdcda14b7f1e64d0804fc832c` · axiom `56fea85c…` · digest `1b0455cc…`.

## 4. live 경로 선행검증 — 발견·수정된 결함 3건 (실행 전 차단)

live 실행 전 공식 문서 대조·로컬 실증으로 잠복 결함 3건을 발견·수정했다. **핀 모드 4종(main/empty/mismatch/incapable)은 kimi를 실행하지 않으므로 live 경로에서만 발현**하는 결함들이었다.

1. **`-p`+`--auto` 플래그 충돌**: kimi-command 공식 문서 플래그 충돌 규칙("non-interactive 모드는 기본 auto 권한 정책") + 로컬 실증 `error: Cannot combine --prompt with --auto.`(exit 1) → 워크플로에서 `--auto` 제거(push `9bb5542`). `-p` 모드는 도구 호출을 이미 auto 권한 정책으로 처리하므로 동작 불변.
2. **공급자 배선**: 실제 키는 surplus(OpenAI 호환 `https://api.surplusintelligence.ai/v1`, 모델 `glm-5.3`) 소유 — `KIMI_MODEL_PROVIDER_TYPE`·`KIMI_MODEL_BASE_URL`·`KIMI_MODEL_CAPABILITIES`(thinking,tool_use) env 합성 provider 배선 추가(push `2987783`). 공식 문서상 `KIMI_MODEL_*` family는 config.toml·login 없이 메모리에서 임시 provider를 합성하는 유일한 shell 자격증명 채널 — fresh `KIMI_CODE_HOME` CI 시나리오와 정확히 일치(더미키 401·실키 스모크 테스트로 실증: 인증·Write 도구 호출·stream-json 출력).
3. **`reasoning_effort` 400**: 1차 live run에서 실모델 조사 도중 `provider.api_error: 400 'reasoning_effort' must be one of: 'low', 'high', 'max'`. 로컬 로깅 프록시를 경유한 직접 관측으로 원인 확정: **env 합성 모델은 support_efforts를 선언하지 않아, 2번째 요청부터 클라이언트가 기본 effort `medium`을 reasoning_effort로 전송**하고 surplus가 이를 거부(첫 요청은 effort 미전송 — 단순 스모크 테스트가 통과한 것은 이 때문 + 백엔드 검증 편차). `KIMI_MODEL_THINKING_EFFORT`는 kimi 프로토콜 전용이라 openai 합성 provider에 미적용(핀 시도 후 동일 실패로 실증). 수정: run-scoped `KIMI_CODE_HOME`에 `[thinking] effort = "high"` config을 작성(push `e79a6ed`) — 프록시 관측으로 **전 요청이 'high'를 전송**함을 확인. 'high'는 공급자 허용집합 내 값이므로 백엔드 검증 무관하게 결정적으로 안전하다.

`AGENT_API_KEY`는 Job 1에만 주입되며 Job 2(재사용 workflow)에는 `AXIOM_READ_TOKEN`·`SUBJECT_REPORT_TOKEN`만 전달 — A11(시크릿 비전달)은 YAML 구조로 성립.

## 5. live 실행 — 실제 에이전트가 명제를 생성한다

1차 run [41627241907](https://github.com/Archright/byoa-customer/actions/runs/41627241907)(dispatch `2987783`, 2026-11-03T11:24Z): Job 1에서 glm-5.3이 **실제 조사를 수행**했다(로그 관측: 고정 커밋 `a130a7f3…` 확인·`subject` 트리 clean 확인·bytesview.nim·사용처·git 히스토리 조사·`len = e - 2b + 1` 법칙 도출·`agent-version.txt` 자기 식별) — 이 관측 자체가 A1(실모델 호출)·A12(Zero-Footprint)의 실패 시점까지 증거다. 조사 도중 §4-3의 reasoning_effort 400으로 실패, Job 2 skip.

2차 run [41631860444](https://github.com/Archright/byoa-customer/actions/runs/41631860444)(dispatch `e79a6ed`, 2026-11-03): 전 Job SUCCESS — **A1–A13 전 항목 관측**. Job 1에서 glm-5.3이 브리핑(Agent Briefing·카탈로그)만으로 **사전 준비된 명제 없이** 명제 5개를 자생 생성했다: 1 lane `SPEC-LIBP2P-BV-SLICE` + 4 claim `forall_implication`(공통 target `libp2p/utils/bytesview.nim::toOpenArray`). Job 2(SHA₁ 핀 재사용 workflow)에서 `ax prove --proposals`가 5-유닛을 처리했다: rollup **1 DISPROVED + 4 INCAPABLE{UNSUPPORTED_LOGIC}** — 한 명제의 판정이 나머지 유닛 처리를 중단하지 않는 per-unit 독립 처리(§1 2축 모델의 live 실증) → lane 유닛의 DISPROVED가 BUG_SUSPECTED로 승격. `ax report --upstream`은 기존 #3364와의 중복을 판정해 **DUPLICATE #3364**로 종결했다(신규 이슈 미생성 — 중복 검사 계약의 정상 동작; receipt `48a9935e…`v2 + `38647549…`legacy 2종 발급). live 생성 명제의 재현성은 §3과 동일 절차로 관측: CI 관측 4-tuple의 proposals 문서를 고정 입력으로 로컬 d1'/d2'(신규 state 각각)에서 재실행 — §9 요약 표 및 A10 참조.

## 6. Acceptance 관측 (A1–A13)

| # | 항목 | 관측 |
|---|---|---|
| A1 | 실제 AI 실행 | 1차 run 로그: 실모델 다중 턴 조사 관측. 2차: run `41631860444` SUCCESS — 모델 호출·다중 턴 조사·명제 작성 완주 |
| A2 | 명제 생성(사전 부재 → 생성) | CI 시작 시 `out/proposals.json` 부재 pre-condition + 에이전트 생성 post-condition. 2차: Job 1 artifact에서 5-유닛 문서 생성 관측(sha256 `f7e9090c…`) |
| A3 | 출처 기록 | `agent-version.txt`(실측 2.4.1)·`agent-run.jsonl`(stream-json) artifact. 2차: 2 artifact 업로드·다운로드 관측 |
| A4 | 계약 적합성 | 2차: 5-유닛(1 lane `SPEC-LIBP2P-BV-SLICE` + 4 claim `forall_implication`, 공통 target `bytesview.nim::toOpenArray`) 계약 검증 통과 → `ax prove` 진입 |
| A5 | 대상 일치 | 1차 로그: 에이전트가 `a130a7f3…` 확인. 2차: `github.repository` 권위값·체크아웃 `a130a7f32219909bdcda14b7f1e64d0804fc832c` 일치 관측 |
| A6 | 정형검증(실제 ax prove) | 2차: SHA₁ 핀 재사용 workflow에서 실제 `ax prove --proposals` 실행(EXIT=1 — in-contract DISPROVED) |
| A7 | 판정 DISPROVED → BUG_SUSPECTED | 2차: rollup 1 DISPROVED + 4 INCAPABLE{UNSUPPORTED_LOGIC} → lane 유닛 DISPROVED가 BUG_SUSPECTED 승격 관측 |
| A8 | 보고(Issue URL/DUPLICATE) | 2차: `ax report --upstream` → #3364 DUPLICATE 판정 관측(신규 이슈 미생성 — 중복 계약 정상 동작) |
| A9 | 증거(receipt artifact) | 2차: receipt artifact 관측 — `48a9935e…`(v2) + `38647549…`(legacy) |
| A10 | 결정론(4-tuple d1'/d2' 일치) | 2차: CI = d1' = d2' — proposals `f7e9090c…`/subject `a130a7f3…`/axiom `56fea85c…`/digest `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590`, EXIT=1, 타이밍 필드 제외 state 동일 |
| A11 | 시크릿 비전달 | YAML 구조(Job 2 secrets 2종만) + Job 2 로그 grep: 2차 run 전체 로그에서 시크릿명(`AGENT_API_KEY`) 0건 |
| A12 | Zero-Footprint | 1차: subject clean 확인 관측. 2차: subject 트리 clean — 고객 소스 바이트 변경 0 |
| A13 | 무인 실행 | dispatch 후 개입 0회: 2차 run `41631860444` dispatch 완료 후 종료까지 인간 개입 0회(§4-3 수정 `e79a6ed`은 1차 실패 관측 후·2차 실행 전 착지) |

## 7. 정직 기록 (Non-claims)

- **live 실증과 고정명제 재현성은 별개다**: §5의 live 에이전트 실행은 "고객이 선택한 실제 LLM이 CI 안에서 명제를 직접 생성·제출할 수 있다"를 입증한다. §3·A10의 d1/d2는 "고정된 명제 입력에 대한 Axiom 검증 경로의 재현성"을 입증한다. AI가 매번 동일한 명제를 생성한다는 주장은 하지 않는다(필요도 없다 — 제출된 명제가 고정되는 순간부터 결정론이 적용된다).
- **실행 성공 ≠ 검증 성공**: all-INCAPABLE·incapable 모드의 exit 0은 능력 판정 절차의 정상 완료이지, 저장소가 안전하다는 뜻이 아니다(Job 3c·run 41617645516 관측).
- **공급자 비편향**: surplus/glm-5.3은 고객(실험자)이 선택한 참조 구현일 뿐, Axiom이 해당 공급자를 공식 지원한다는 뜻이 아니다. 공통 계약(Proposition Contract)이 실제 AI 클라이언트를 수용함을 입증하는 실험이다.
- **오류 사례도 증거로 기록**: §4의 결함 3건은 live 경로의 실측 실패·수정이며, "선언이 아닌 관측" 원칙에 따라 그대로 남긴다.

## 8. 종결 후 원복·잔여 상태

관측 종료 후 즉시 원복(Probe B 절차 — 실험 상태를 영구 구성으로 남기지 않는다):

| 항목 | 조치 | 관측(기계 확인) |
|---|---|---|
| Axiom actions access | `access_level=none` | 재조회 `access_level=none` 관측(`gh api repos/Archright/Axiom/actions/permissions/access`) |
| byoa-customer secrets | 3종 삭제(`AXIOM_READ_TOKEN`·`SUBJECT_REPORT_TOKEN`·`AGENT_API_KEY`) | 삭제 후 목록 재조회 빈 집합(0건) 관측 |

잔여(별도 권한·시간 조건 — 본 Phase 범위 외): ① Axiom 공개 전환(임의 외부 호출자 개방) — 사용자 정책 결정. ② 실제 제3자 고객 온보딩 — 별도 실험. ③ 2026-12-01 무인 폴백 실계약 관측 — 미래 사건 대기.

## 9. 완료 증거 (요약 표)

| 항목 | 값 |
|---|---|
| Axiom SHA₁ | `56fea85c3c7c968eaa637fd373f8d0e8d3c9f9b3`(PR #1241 merge) |
| 고객 저장소 | `Archright/byoa-customer`(private org) — `e79a6ed` |
| 주체 핀 | `iftech/nim-libp2p` @ `a130a7f32219909bdcda14b7f1e64d0804fc832c` |
| 에이전트 | kimi-code CLI 2.4.1(headless `-p`) → surplus `glm-5.3`(OpenAI 호환) |
| selftest | `41611754462`·`41613152993`(전 green, Job 3c 포함) |
| incapable 사전검증 | `41617645516` 전 green — rollup 2 INCAPABLE, units 0, exit 0 |
| incapable 4-tuple | `f55dbf25…`/`a130a7f3…`/`56fea85c…`/`1b0455cc…` — CI·d1·d2 일치(d1=d2 state identical) |
| live 1차 | `41627241907` — 실모델 조사 관측 후 reasoning_effort 400 실패(§4-3) |
| live 2차 | `41631860444` 전 SUCCESS — 5-유닛 자생 생성(1 lane + 4 claim), rollup 1 DISPROVED + 4 INCAPABLE{UNSUPPORTED_LOGIC}, BUG_SUSPECTED → DUPLICATE #3364 |
| live 4-tuple | `f7e9090c…`/`a130a7f3…`/`56fea85c…`/`29418089…` — CI·d1'·d2' 일치(EXIT=1, 타이밍 필드 제외 state 동일) |
| 원복 | actions access `none` 복원·시크릿 3종 삭제 후 0건 확인 — 고객 저장소 배선 커밋 `9bb5542`→`2987783`→`e79a6ed`(§4 결함 수정 이력) 잔존 |
