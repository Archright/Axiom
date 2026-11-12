# P0-D2-G — 정형검증 실험 기록 (채택 에이전트 명세 S2의 결함 차동 + 원본 코드 재생 바인딩)

Experiment: `act2-wp-toml-b1-input-integrity/p0d2g` · Date: 2026-10-17
명세: `AGENT_SPEC.md` (에이전트 체인 1차 저작물 — 본 기록은 이를 채택·검증한 기록이다) · 재현: `replay_agent.sh`
증거: `evidence/` (큐리이티드 스냅샷 + `SHA256SUMS` 대응 보증; 원본 raw는 gitignored `runs/`·`state_*/`·`vault_*/`·`env*/`에 보존)
바인딩: `config/spec/toml_d2_agent_spec.json` (SPEC-TOML-D2-AGENT) · `docs/spec/toml_d2_agent_binding_contract.md` — 랜딩 커밋 `efc90940d`
파이프라인 갭 기록: `PIPELINE_GAP_P4_BOOL_BINDING.md` · 원본 직접 부착 한계: `ORIG_PRAGMA_LIMIT.md`

## FACT SHEET

### Question

블라인드 발견 → 명세 추론 → 채택 → 파이프라인 주입으로 이어지는 에이전트 수직 슬라이스가,
**인간이 결함을 알려 주지 않은 상태**에서 실제 결함(문자열 내부 제어문자 수용)을 발견하고,
채택된 명세 S2 하에서 **결함 대상은 반례로 반증**하며 **대조 커널은 증명**하는가?
(terminal outcome: `DISPROVED` 승격 + 원본 코드 재생까지 — 본 슬라이스의 관측 범위와 미관측은
아래 Classification·Non-Conclusions에 명시한다.)

### Context

| 항목 | 값 |
|---|---|
| subject | status-im/nim-toml-serialization @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (읽기전용 pristine 클론 `env_p/subject`, 전·후 `git status --porcelain` 비어있음 — 드리프트 게이트 통과) |
| 결함 | `lexer.nim:588` 단일행 문자열 게이트 `{8,16,31,127}` vs README v1.1.0 부합 주장(`README.md:65`)이 요구하는 forbid — 멀티라인 `:554`는 `{16,31,127}`로 추가 축소 |
| Axiom | 본 브랜치 `followup/d2-agent-vertical`, 바인딩 커밋 `efc90940d` (+1,885행), `bin/ax` v0.3.7 |
| 툴체인 | Nim 2.2.10 [Linux: amd64] · z3 4.13.3 · Lean 4.33.0 (`state_e1/logs/ax_proof_state.json` `executionIdentity.toolchainIdentity`) |
| 명세 | S2 — `D = 1..255 ∖ {10,13,34,92}`, `forbid(c) = (c≤8) ∨ (10≤c≤31) ∨ (c=127)`, 캐리어 2개 (`AGENT_SPEC.md` §4·§5) |

### Scope

채택된 S2의 캐리어 2개만 — `d2StringGateReject`(결함 게이트 추출)·`d2CommentGateReject`
(저장소 자신의 정합 집합 추출, forbid와 집합동일). 키·주석 경로, 멀티라인 줄바꿈 규칙,
이스케이프 유효성, 다중바이트 UTF-8, 후보 2~11(writeKey 미인용 등)은 **범위 밖**
(`AGENT_SPEC.md` §1 채점표 판정 참조).

### Procedure (6단계 — Phase A~E)

1. **Phase A 발견(블라인드 2대)** — 결함 힌트 0개 프롬프트의 제로-컨텍스트 독립 분석 2회.
   원문 verbatim 보존: `discovery/agentA_raw.md` (sha256 `e3b20c9d6293c249…b6e5c9`),
   `discovery/agentB_raw.md` (`0b329a4498eabe6f…35f12`). 기정담(\xHH 디코드 의미론)은
   **양측 모두 미발견**, 진짜 후보 7+7건 중 3건 수렴. 선정(문자열 제어문자 게이트 수용,
   A3+B3)은 **추론 에이전트**가 했다(오케스트레이터 아님).
2. **Phase B 명세 추론** — `AGENT_SPEC.md` (sha256 `f9c8f2d3ef47fdc5…21a91d`): S2 작성,
   상속 인용 전수 대조로 **인용 정정 4건** 기록(§11). 컴파일·실행 없는 정적 저작.
3. **채택** — 오버레이 `config/spec/toml_d2_agent_spec.json` (soExplicit, 에이전트 체인
   출처 블록 + 채택 행위 = 사용자 승인 슬라이스 플랜 + 커밋된 계약
   `docs/spec/toml_d2_agent_binding_contract.md`).
4. **원본 직접 연결 한계(Phase D)** — 스펙 프라그마의 원본 헤더 직접 부착은 **직렬 3게이트**
   (프론티어 의존성 폐쇄 NotFound → 의무 공급원 부재 `ogr.no-applicable` → 스펙 적하
   lossy)에서 fail-closed 차단됨을 관측: `ORIG_PRAGMA_LIMIT.md` + `variant_orig.patch`
   (1531B). if-표현식 스펙은 v0.3.7에서도 lossy 거부 재확인(3.3/3.4 프로브).
5. **Phase C 엔진 바인딩** — 커밋 `efc90940d` (+1,885행): 오버레이 로더·검증기(9절 문법,
   대조≡forbid 집합동일 강제), 2-캐리어 신디사이저(bool-native IR), 모듈 경로 게이트
   라우팅, 원본 코드 재생 바인딩(하니스 템플릿
   `Toml.decode("k = \"a" & chr(<c>) & "b\"", TomlValueRef)`, 관측 raise를 reject bool로
   투영), 유닛 테스트 31/31 (`tests/unit/test_toml_d2_agent_binding.nim`).
6. **Phase E 검증** — pristine 주체 재구성 후 결함 런(state_e1)·콜드 재실행(state_e3)·
   standalone control 거부(state_e2). 커맨드: `AXIOM_STATE_DIR=state_e1
   AXIOM_PROVE_VAULT_DIR=vault_e_defect bin/ax prove --project env_p/subject
   --target 'toml_serialization/lexer.nim::scanString'` (cwd=Axiom3 루트, scope lock
   시드). 전체 재현은 `replay_agent.sh`가 담당한다.

### Result (모두 기계 관측)

1. **오버레이 신디시스** (`runs/e_defect.err:4` — 채택 명세가 파이프라인에 실제 주입된 관측):

   ```
   [INFO] axiom_engine: toml d2-agent overlay carriers synthesized: d2StringGateReject (gate d2StringGateReject=@[8, 16, 31, 127]) + d2CommentGateReject (forbid 8/10/31/127) domain=1<=c<=255 exclusions=4 obligations=7/7 eligible=true/true source=toml_serialization/lexer.nim
   ```

   의무 7건, 양 캐리어 모두 eligible — fail-closed 수용 게이트의 정상 통과.
   canonical seal은 EA 미측정(ckVarTy)으로 `sealError` 쇠퇴하고 BMC 레인이 채택 모델을
   결정했다(계약 §3 — 빈 EA 레그는 정직한 미측정).

2. **결함 차동 — 한 런 안의 SAT 반증 + 증명 공존** (state_e1, exit 1):
   - BMC 레인이 `scanString`에 실반례Witness c=24(갭 멤버)를 바인딩한 SAT 도달
     (`[ERROR] loop_driver: IR pipeline FAIL: scanString status=psFail
     provenance=solverMethod=smBMC,provenance=pkNone`, `runs/e_defect.err:42`).
   - claimOutcome 궤적(`state_e1/logs/ax_prove_trajectory.jsonl` skReport
     `unitEvidenceRefs`) — **결함 대상은 clDisproved, 대조 커널은 clProved**:

     ```
     toml_serialization/lexer.nim::scanString          → "claimOutcome": "clDisproved"  (claimId 707105aaeac78e6a…afa3dd)
     toml_serialization/lexer.nim::d2CommentGateReject → "claimOutcome": "clProved"     (claimId b36f8be708d4408e…f620b5)
     ```

   - 볼트 매니페스트(`vault_e_defect/manifest.json`): `scanString` 행 **certRed**
     (irHash `5c05274c86885add…b70fae75`), `d2CommentGateReject` 행 **certZ3Candidate**
     (irHash `cf15872b80c0c6bf…fd457c2`) — GateVerdict FAIL
     (`canonical run accounting: contestedCount=0 ∨ unsatisfiedCount=1 ⇒
     GateVerdict=FAIL`, `runs/e_defect.err:72`), `[Depth 1/1] Checking:
     lexer.nim::scanString... [FAILED]` (`runs/e_defect.err:73`).
   - collateral 2건(결함 레그가 스캔한 Axiom 자체 코드의 Q3 재발 — 결함 타깃과 무관한
     ce-replay 실패): `calcDynamicTimeoutCore — replay rvUnavailable:harness nonzero
     exit 1`(`:14`), `proximityScore — replay rvUnavailable:model does not bind
     parameter 'nodeCount'`(`:24`). p0d2f의 Q3와 동일한 제너릭 재생 병목이다.

3. **standalone control 거부** (`runs/e_control.err`, state_e2, exit 2):
   `--target 'toml_serialization/lexer.nim::d2CommentGateReject'`는
   `not found in frontier — canonical target: NotFound (fail-closed, empty selection)`.
   대조 커널은 census 주소 가능(candidate)이지만 프론티어 편입 의존성 폐쇄를 통과하지
   못해 단독 타깃 실행은 구조적으로 거부된다 — 대조 판정은 결함 런과 **같은 런 안에서**
   관측하는 것이 유일한 경로이며, 실제로 2번 항이 그렇게 달성됐다.

4. **콜드 결정론** (state_e3, exit 1): 재실행의 `canonicalRunDigest`는 1차와 **MATCH** —

   ```
   3516fcfcb4d891f99caed95d55405e29a8032371b5ba73028dee03e598cced6a   (state_e1 == state_e3)
   ```

   claimId·irHash 전부 동일, `e_defect.err`↔`e_defect2.err` diff는 vault 경로 1행뿐
   (하니스·판정 바이트 동일). `replay_harness_config_quirks.md` Q1(cwd=$ROOT)·Q2
   (porcelain)은 모두 시드로 회피했다.

5. **재생·승격 미관측 (P-F1 — 제너릭 파이프라인 갭)**: BMC SAT(c=24 실Witness)에도
   `[ce-replay]`가 `scanString`에 발행되지 않고 `counterexample = null`로 유지됐다.
   근원은 `src/verification/counterexample_validator.nim:74-79` — P4 재검증
   `preconditionSmt`가 bool 타입 initExpr를 **조건**으로 assert한다(C20 one-state
   모델의 `result` 바인딩은 본문 `gate(c)`가 되고, 이는 결함Witness(`gate=false ∧
   forbid=true`)를 정확히 배제) → `cvSpurious`(`:131-132`) → candidate 보존 →
   `vsDisproved` 미도달 → 재생 트리거(`ir_pipeline_runner.nim:1439-1441`) 미발화.
   bool-반환 캐리어는 이 경로로는 **승격 불능**이다(선행 캐리어는 전부 산술 — 비bool
   등식 분기라 한 번도 안 맞은 경로). BMC 모델은 c=24를 정확히 바인딩했다(모델 캡처는
   정상). 근원 커밋은 `05055aab5`(2026-10-08, 제너릭) — `efc90940d`는
   `counterexample_validator.nim`을 만지지 않았다. 수정 스케치(C20 one-state
   판별자: `resultStateName=some("result")` + identity 전이 → index-aligned bool
   initExpr를 등식으로)는 `PIPELINE_GAP_P4_BOOL_BINDING.md`에 문서화. **본 슬라이스에서
   수정하지 않았다** — 우리 실험을 통과시키려 제너릭 검증자를 고치는 것은 patch-to-pass이고,
   파이프라인의 cvSpurious 보존은 fail-closed 설계대로 동작하는 것이다.
   captured P4 스크립트(`PIPELINE_GAP_P4_BOOL_BINDING.md` 인용):

   ```smt2
   (declare-fun state ((_ BitVec 64) Bool) Bool)
   (declare-const c (_ BitVec 64))
   (declare-const result Bool)
   (assert (and (= c c) (or (or (or (= c #x0000000000000008) (= c #x0000000000000010)) (= c #x000000000000001F)) (= c #x000000000000007F))))
   (assert (not (= (or (or (or (= c #x0000000000000008) (= c #x0000000000000010)) (= c #x000000000000001F)) (= c #x000000000000007F)) (or (or (bvsle c #x0000000000000008) (and (bvsge c #x000000000000000A) (bvsle c #x000000000000001F))) (= c #x000000000000007F)))))
   (check-sat)
   ```

   이 script는 본문(`gate(c)`)을 전건으로 assert해 결함Witness를 배제한다 — 첫 assert가
   이미 `(= c 8∨16∨31∨127)`을 강제하므로 c=7·24 같은 갭 멤버는 모델에서 제거된다.

6. **pristine 무결성**: `env_p/subject` @4aa8e22, lexer.nim sha256
   `19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d`(스펙 §5 전승값과
   일치), 런 전·후 porcelain 비어있음 — 드리프트 게이트 통과.

### Evidence

`evidence/` — 큐리이티드 스냅샷(`README.md`가 run↔state/target 대응을 운반,
`SHA256SUMS`가 파일 대응을 보증): 결함 런 원본(`runs/e_defect.{err,exit}`·
`e_defect2.{err,exit}`·`e_control.{err,exit}`)·보존된 재생 하니스
(`e_replay_harness_c0.nim`)·state_e1 로그 3건(proof state·trajectory·z3 텔레메트리)·
state_e3 proof state·`vault_e_defect/manifest.json`(vault_e_control은 빈 디렉터리 —
standalone control이 런 전에 거부됨을 그 자체로 증명)·`variant_orig.patch`·
`ORIG_PRAGMA_LIMIT.md`·`PIPELINE_GAP_P4_BOOL_BINDING.md`. **원본은 이동시키지 않았다** —
모든 원시 산출물은 슬라이스 gitignored `runs/`·`state_*/`·`vault_*/`·`env*/`에 그대로
남으며, 전체 런의 재생성은 `replay_agent.sh`가 담당한다. `AGENT_SPEC.md`와 `discovery/`
원문 2건은 바인딩 커밋 `efc90940d`에서 이미 커밋되어 있다(중복 수록하지 않는다).

### Classification — 4축 (기계 관측)

| 축 | 판정 | 근거 |
|---|---|---|
| 발견 | **PARTIAL** | 진짜 후보 7+7건(3수렴)을 블라인드로 발견 — 그러나 기정담(\xHH 디코드 의미론)은 양측 모두 미발견. 발견 축 점수는 기록된 값이며 본 기록이 재도출하지 않는다 |
| 명세생성 | **OBSERVED** | S2 fail-closed 수용: 의무 7건, 양 캐리어 eligible(오버레이 신디시스 INFO 라인), 근거 주해 + 인용 정정 4건(`AGENT_SPEC.md` §11) |
| 검증정확성 | **OBSERVED** | 한 런 안의 차동(clDisproved SAT + clProved) + 콜드 결정론 MATCH(digest `3516fcfc…`) |
| 증거신뢰성 | **PARTIAL** | 재생·BUG_FOUND 미관측 — 근원 문서화(`PIPELINE_GAP_P4_BOOL_BINDING.md`); 결정론·pristine 드리프트 0·UNKNOWN-as-success 없음은 충족 |

### 수직 슬라이스 관측 상태 (슬라이스 verdict)

**발견 → 추론 → 채택 → 검증 관측. DISPROVED 승격·원본 재생 미관측.**
본 슬라이스는 에이전트 체인이 제로 컨텍스트에서 실결함을 후보화하고(SAT 반례 c=24로
기계 반증될 명세로 성립), 그 명세가 fail-closed 채택·파이프라인 주입·차동 판정까지
관측됐음을 증명한다. 그러나 terminal outcome인 `vsDisproved` 승격과 원본 코드 재생
(`[ce-replay]` + BUG_FOUND)은 P4 bool-binding 파이프라인 갭으로 **미관측**이다 —
미관측의 근원은 제너릭 검증자 코드(`counterexample_validator.nim`)에 있고 바인딩 쪽이
아니므로, 본 슬라이스는 그 갭을 기록으로 닫는다. ACCEPTANCE 최종 판정은
`replay_agent.sh`가 내며, 현재 관측 하의 예상 종료는
`ACCEPTANCE: INCOMPLETE (replay/promotion unavailable — P4 bool-binding pipeline gap,
see PIPELINE_GAP_P4_BOOL_BINDING.md)`이다. 본 문서는 그 판정을 대신하지 않는다.

### Interpretation

- **채택 명세의 판별력 실증**: 동일 S2에서 결함 게이트 추출 커널만 SAT로 반증되고
  forbid 집합동일 대조 커널은 증명 — 음성 대조군이 명세 주입·파이프라인의 결함을
  배제한다(대조에서 SAT가 나왔다면 주체가 아니라 주입의 결함이다).
- **원본 직접 부착의 구조적 한계 확정**: 스펙 프라그마의 원본 헤더 부착은 의무로
  등록되지 않는다 — 프론티어 의존성 폐쇄·자격(의무 공급원)·적하(lossy) 3직렬 게이트가
  차단하며, 이것이 베스포크 추출 커널 + 오버레이 경로의 존재 이유다(`ORIG_PRAGMA_LIMIT.md`).
- **bool 캐리어 승격 경로의 부재 확정**: BMC SAT→모델→P4→vsDisproved→재생 체인은
  bool 반환 캐리어에서 끊긴다 — "스펙이 false라 하는데 true를 반환" 결함형(판단 술어
  claim)은 전부 이 경로를 지나며, 선행 슬라이스의 산술 캐리어는 등식 분기를 타므로
  갭이 이제 처음 노출됐다.
- 커널↔원본 대응은 정적 판독 근거(루프 구조·UTF-8 테이블·주석 집합)로 뒷받침되나
  **정형 검증 아니다** — 원본 `scanString`의 직접 추출·검증은 이루어지지 않았다.

### Non-Conclusions

- **모델↔원본 대응은 근거 기반이지 형식 증명이 아니다** — SAT/UNSAT의 대상은 채택
  모델(추출 커널)이지 원본 `scanString` 함수가 아니다.
- **발견의 완전성은 주장되지 않는다** — 2대 블라인드의 후보 풀에서 기정담이 빠졌고,
  "더 있는 결함의 부재"를 어떤 관측도 담보하지 않는다.
- **커널 형태가 아닌 carrier는 채택 모델이다** — `d2StringGateReject`는 원본 코드의
  복제가 아니라 S2가 선언한 결함 게이트의 인증 모델이며, 원본과의 등가는 정적 판독
  근거까지만 확보됐다.
- 대조 커널의 clProved는 "lexer.nim 전체(또는 주석 경로)의 정확성 증명"으로 확대
  금지다 — 담보는 "S2 forbid와 집합동일한 모델이 D 전체에서 forbid를 만족한다"까지만이다.
- 재생·BUG_FOUND 미관측을 "원본 코드가 옳다"는 방향으로 읽는 것은 금지된다 —
  BMC 반례(c=24)는 실재하는 결함Witness이며, 미관측은 파이프라인 승격 경로의 갭이다.

### Next Experiment (후보)

1. **P4 bool-binding 수정 (Axiom 개선 — 근원 치료)** —
   `counterexample_validator.nim` `preconditionSmt`에 C20 one-state 판별자
   (`resultStateName=some("result")` + identity 전이)를 두고 index-aligned bool
   initExpr를 등식으로 assert. 이후 p0d2g 결함 런을 재실행해 `cvConfirmed →
   vsDisproved → [ce-replay] → BUG_FOUND → DISPROVED 승격` 전 체인을 관측한다
   (`PIPELINE_GAP_P4_BOOL_BINDING.md` fix shape).
2. **주체 커밋 변이 (재생 드리프트 게이트 통과형)** — 원본 클론 안에 변이를 커밋한
   변이 커밋을 materialize해 Q2(주체 porcelain)를 구조적으로 통과시키는 p0d2f 다음
   실험 3의 p0d2g 적용.
3. **발견 프로토콜 개선** — 기정담(\xHH 디코드 의미론) 누락을 잡는 프롬프트/구도
   (예: 런타임 관측 힌트 단계, 후보 수렴 이전의 API-시맨틱 점검 체크리스트) — 발견 축
   PARTIAL의 직접 후속.
4. **if-표현식 프론트엔드 커버리지** — `toCanonKind` nkElifExpr/nkElseExpr 매핑 +
   `convertExprCanon` ckIfStmt 암(p0d2f 다음 실험 1의 재확인 — 본 슬라이스 3.3 프로브가
   v0.3.7에서도 유효함을 재검증).

---

## ACCEPTANCE 상태

최종 판정은 `replay_agent.sh`가 낸다 — 조건 C1(결함 반증: exit 1 ∧ trajectory
clDisproved ∧ manifest certRed)·C2(대조 증명: 같은 런의 d2CommentGateReject
clProved/certZ3Candidate)·C3(콜드 결정론: 런 간 + 기록 digest `3516fcfc…` 고정 비교)·
C4(재생/BUG_FOUND — **P4 bool-binding 갭이 열려 있는 한 미관측이 예상**)·C5(증거
완전성)의 5조건 판정표와 ACCEPTANCE verdict. main 병합 후 실행이 예정되어 있으며,
현재 관측(C4 미관측 — 위 재생·승격 미관측) 하의 예상 종료는
`INCOMPLETE (replay/promotion unavailable — P4 bool-binding pipeline gap)`이다.
본 문서는 그 판정을 대신하지 않는다.

## Addendum — 착지 경로 정정 (2026-10-17)

단일 PR #909은 merge-group admission 게이트에서 **ROT_NEW_PIN**(④ line-set(pin@H) ≠ set(derived H)) +
**allowlistOk:false**(① 비클로저 동반자 경로)로 거부됐다 — 실측: 클로저(876멤버) 변경은 엔진 3파일
(axiom_engine·counterexample_replay·canonical_verification, 전부 핀 멤버)이나 experiments·tests·
config/spec·docs/spec 변경은 ①을 위반. 선례 `62dbeab8b`와 동일 fix class로 **2-PR 분할** 착지:

1. **PR #911 (ROTATION, MERGE d4b2a0e9)**: 엔진 3파일(오버레이 presence-optional화 포함) +
   trusted_writer_set.json 3엔트리 재앵커(deriver 유도 sha; 핀==유도 876==876 실측 MATCH) +
   architecture_debt 재생. 변경 경로 전부 ① 충족(클로저 멤버·핀·allowlisted debt).
2. **본 PR (NORMAL)**: 오버레이·계약(presence 수정안 포함)·실험 기록·단위 테스트 — 클로저 무변경.

계약 문서 §2의 presence 수정안이 이 분할의 근거이며, 원자성은 두 순차 PR로 보존된다(엔진 단독
착지 시점의 main은 오버레이 부재 = 명시 로그 + 불활성 바인딩으로 정상 동작).
