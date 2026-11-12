# ADR-0033: SL-02 derived-closure 소비자 결속 — L1 식별자 결속 + L2 집합 완전성

## Status

**Accepted (2026-10-10)** — 아키텍처 결정 기록이며 구현을 수반한다
(`.github/workflows/admission-check.yml` verdict 스텝 + TWS/epoch-manifest 핀 회전 +
`src/gate/slice_catalog.nim` SL-02 승격 — 단일 커밋, §Decision (e)).
`src/cli/merge_cli.nim`은 수정하지 않는다(병렬 workstream #653 충돌 회피 — 소비자
검증은 워크플로 verdict 스텝에서 수행된다; git 객체 접근의 자연 위치).
상위 계획: SL-02 derived-closure 세대 복구 Phase 1-b(승인 계획서 2026-10-10).
**2026-10-10 병합 개정**: #667 회전 정합(H=주체 head·pin@H 소스) 흡수 — §(b)/(c)
재앵커(candidateHeadSha G→주체 head G²), in-place 폴백 pin-H를 `git show H:TWS`로.

## Context

checker 폐쇄 3중 등식(set(H) == set(B) == set(pin@B), `merge_cli.nim:496`)의 회전
입력은 same-run `derived-closure` 아티팩트로 공급된다. 그러나 소비자가 아티팩트를
**검증 없이** verdict에 넘겨왔다 — 기존 검사는 3파일 존재 여부(all-or-none)뿐이며:

- **L0 공결손 구멍(실측)**: 생산자가 derived-H와 pin-H를 함께 결손·위조하면
  ④(new anchor: set(pin@H) == set(H))가 "둘 다 결손/위조"라 하더라도 자기일치로
  참이 되어 rqRotation이 승인될 수 있다. L1+L2가 봉합하는 유일 벡터.
- **in-place 폴백 정체 버그(실측, e54de52e4)**: 아티팩트 부재 폴백이 H를
  `git rev-parse HEAD`로 유도하는데, verdict 스테이지의 워크스페이스 체크아웃은
  **B**(base.sha ref)이므로 HEAD == B — B의 closure를 H의 것으로 미표기하는
  false closureEqual(가짜 NORMAL)을 만든다. 이벤트에서 유도된 **주체 head**로
  정정된다(§Decision (c); #667 병합으로 MG 경로는 run head parent2=G² 앵커).
- **집합 완전성 부재**: admission lane에는 기대 집합 == 실제 집합의 검증이 없었다.
  유일 실현 선례는 reconcile lane(`proof_reconcile_gate` — deriver 재실행 digest와
  oracle `executionClosure.digest` 교차검증)이며, 이를 verdict 스텝에 연결한다.

## Decision

**(a) 아티팩트 전달 = METHOD.** cross-runner 채널로서의 same-run 아티팩트
(`derived-closure`)는 전달 방식(METHOD)이지 권위(authority)가 아니다(§2.3
Authority ≠ Adapter). 판정 권위는 여전히 `ax merge` verdict(3중 등식)이며, 본 ADR의
L1/L2는 그 **입력 게이트**다 — 새 검증기·새 게이트 아님(기존 체커 확장).

**(b) identity 필드 계약(계획 A 확정).** 아티팩트 4번째 필수 멤버 `identity.json`:
`candidateHeadSha`(40hex — 파생 ref H), `baseSha`(40hex — 파생 ref B),
`pinHeadBlobSha`(40hex — `git blob sha of trusted_writer_set.json@candidateHeadSha`),
`runAttempt`(int). **pin@B는 넣지 않는다** — 소비자가 B 워크스페이스에서 직접 읽는
현행 단일 경로 유지(이중 경로 금지). **주체 head 앵커(#667 회전 정합 병합 개정 —
구판: `candidateHeadSha` = G)**: `candidateHeadSha` = 주체 head
(pull_request.head.sha; merge_group에서는 event G의 parent2 재유도 = G²,
ADR-0027 α). 생산자 도출 ref와 소비자 전 부위(L1 blob oid·L2 재유도·ls-tree)가
동일 ref를 말해야 하고, G의 시험-머지 트리는 closure 멤버를 건드리는 PR에서
set(H)·set(B) 어느 쪽도 아니므로 G 앵커링은 MG 등식을 항상 거짓으로 만든다.

**후보 동등성 검사에서의 G 비교 — 주체 앵커링 아님(ADR-0025 Amendment E,
2026-10-12)**: 후보 동등성 검사에서 G 트리(`tree(github.sha)`)를 비교 대상으로
쓰는 것은 주체 앵커링의 재도입이 아니다 — G는 검증 전용 비교 대상이며 closure
등식의 주체 anchor는 H로 유지된다. 위 (b)가 금지하는 G 앵커링은 "생산자 도출
ref와 소비자 전 부위가 말하는 identity ref"의 치환(등식 **주체**의 변경)이고,
candidate-delta 분류의 `M == tree(G)` 대조는 로컬 재유도 결과의 적격성을 세우는
**검증 비교**로 층이 다르다 — G의 closure를 등식 주체나 분류 입력으로 쓰지
않는 한 본 절 불변식과 충돌하지 않는다(ADR-0025 Amendment E 제4·5항).

**(c) L1 — 식별자 결속(MUST, run-level err fail-closed).** ① 40-hex 형식 +
runAttempt 숫자 ② 이벤트 대조: `candidateHeadSha == 주체 head`(pull_request의
head sha; merge_group에서는 event G의 parent2 재유도 — env 경유 공급, run 본문
무신규 토큰 Q4 계약), `baseSha == ...base.sha || merge_group.base_sha`
byte-equal ③ `pinHeadBlobSha == git rev-parse "$H:config/trusted_writer_set.json"`
(blob oid — 워크플로 git 객체 접근 선례) ④ `runAttempt == github.run_attempt`.
불일치·누락·형식 오류 = 파싱 실패와 동일한 run-level err(never a verdict).
동반 정정: in-place 폴백의 H 유도를 이벤트에서 유도된 주체 head로 하고 H 객체를
identity-step 선례의 bounded by-object fetch로 확보한다(MG에서 subject 객체는
체크아웃에 부재 — #667 정합의 depth-50 bounded fetch).

**(d) L2 — 집합 완전성 + blob 대조(MUST, run-level err fail-closed).**
① **deriver 재실행 digest 등식**: 같은 런에서 B-고정 deriver
(`tools/ci/derive_checker_closure.nim`)를 `--ref H`/`--ref B`로 재실행,
`LC_ALL=C sort | sha256sum`(바이트정렬 라인 join("\n"), 후행 개행 정규화 제거 —
`proof_reconcile_gate` executionClosure 정준화와 동일) == 아티팩트 파일 digest.
과잉 멤버를 포함한 모든 집합 차이를 탐지한다. ② **멤버별 대조**: derived-H.txt 각
라인 `<mode> <type> <sha>\t<path>`가 `git ls-tree -r "$H"` 엔트리와 정확히 일치
(멤버십 + blob). **한계 명시**: 구조 검사는 존재 라인의 결속만 검증 — 파일에서
누락된 멤버, 그리고 "유효한 트리 엔트리인 과잉 멤버"는 ①의 digest 등식만 탐지한다.
③ derived-B.txt 동일 digest 등식. **빈 아티팩트 위장 금지**: 0바이트 멤버는
all-or-none 단계에서 즉시 run-level err(빈 재유도 digest와 일치하는 공허 통과 차단).

**(e) 세대 전환 — 핀 원자 삼중(G2a).** `admission-check.yml` blob
`f2b7548470d6a67588e53bc166a94d616dc972be`로 `config/trusted_writer_set.json`
`trustedAdmissionWorkflowSha` + epoch manifest `productionExecutionPin`을 동일
커밋에서 회전하고, SL-02를 manifest implementedSlices로 승격한다(카탈로그-매니페스트
원자 페어, `epoch_transaction_gate` 3-layer). 조직 ruleset 핀 회전(Archright/.github)은
§2.5 계약상 착지 시 짝 행위다.

**(f) 결정론성 계약 F1–F9 (deriver 재실행의 신뢰 근거 — "모든 결과 영향 입력 고정").**
- **F1 (import closure)**: 프로젝트 4파일 정확히 — deriver + layer_declaration +
  axiom_pragmas_lite + effect_bridge. nimble 의존 0.
- **F2 (워킹 트리 역유입 부재)**: B-workspace + `--path:src` +
  `--skipParentCfg/--skipProjCfg`(runner-pool deriver 컴파일 레시피 verbatim) —
  nim cwd-우선 규칙상 프로젝트 import가 워킹 트리를 읽을 경로가 구조적으로 없다.
- **F3 (매크로 경계)**: 4파일의 CT 표면은 `std/macros` AST 조작뿐 —
  `staticRead`/`gorge`/`getEnv` 0건(전수 실측, 승인 계획서).
- **F4 (툴체인)**: composite(`setup-axiom-toolchain`) 핀(nim 2.2.10/lean/z3/jq) +
  지문 + 프로브 3층 경유 — deriver 컴파일도 동일 경로.
- **F5 (deriver 버전 고정)**: B 내용 어드레싱으로 자동 성립(비순환 — 앵커는 GitHub
  기판, mint가 `toolCommit==B`를 독립 재검증).
- **F6 (digest 정규화)**: 단일 정준화 — 바이트정렬 라인 join("\n"), 후행 개행 제거
  (생산·소비·reconcile 3자 동일).
- **F7 (이벤트 동결)**: H/B는 이벤트 페이로드 필드에서만 유도(워크스페이스 HEAD·
  가변 ref 금지 — (c)의 정정 취지; MG parent2 재유도는 event G의 함수 — 이벤트
  고정 유지).
- **F8 (run 스코프)**: same-run 아티팩트 + runAttempt 등식 — 타 런 재사용 구조적 부재.
- **F9 (무고정 잔여 — 무고정을 무고정으로 나열, 극장 방지)**: ① 이미지 유틸
  (jq/sha256sum/sort/git 버전 — runner 이미지 좌우) ② 사용자 cfg
  (`--skipUserCfg` 미전달 — `$nim/config`·`~/.config/nim` 좌우) ③ 컴파일러 바이너리
  지문(핀 버전 불일치 시 지문 대조 없음). 해소 전 재유도 등식은 "동일 nim 2.2.10 +
  동일 B/H" 전제로만 성립한다(잔여 리스크 수용·기록).

**(g) bypass 재사용 금지.** 본 L1/L2를 통과한 아티팩트를 다른 런·다른 ref·다른
attempt에서 재사용하는 경로를 만들지 않는다. identity 필드 등식이 매 런 재검증을
강제하며, `overwrite`·삭제 경로는 도입하지 않는다(생산자 DAG는 org 측 소관 —
needs 배선 포함, 본 ADR 소비자 측 한정).

## Consequences

- T5(공결손 — derived-H+pin-H 동시 결손/위조) 벡터 봉합: 부분 공급 = all-or-none
  run-level err, 완전 결손 = in-place 진실 유도, 위조 = L2① digest 불일치 — 어느
  경로도 rqRotation 위장에 도달하지 않는다("완전성 입증"의 기계적 트리거는 부정
  테스트 T1–T6 전건 통과 후에만 선언된다 — tests/ci/test_sl02_consumer_binding.nim).
- SL-02 승격으로 `scope_sl02`가 활성화되어 다운로드 스텝이 발화한다 — 생산자(org
  closure-deriver job) 재배치가 선행/동반되지 않으면 in-place 폴백이 입력을 공급한다
  (동일 권위, 동일 검증).
- merge_cli.nim 판정 논리·Pass 2.97 계약 불변.
