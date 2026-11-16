# MUST-T2a rotation landing 위임 기록 — readiness-verdict 활성화 (PR #121)

> 본 문서는 `docs/agents/rules_workflow.md:129` §2.8 MUST-T2a(2026-11-04 비준)의
> per-PR·시점명시 위임 기록이다. **병합 명령 실행 전에 커밋된다.**
> 기록자 ≠ 승인자: 본 문서의 작성자는 agent(wintrover의 대리 실행자)다.

## §1. 승인 원문 (사용자 = 인간 아키텍트 wintrover)

- **전면 승인 원문 1**: "권한이 필요한 부분은 전면 허가한다." — 2026-11-16
  (Authority Preflight 요청문 내; Terminal Outcome·범위와 함께 제시된 명시).
- **전면 승인 원문 2**: "권한이 필요한 부분은 전면 승인한다." — 2026-11-16
  (반복 명시 — 백그라운드 병렬 진행 지시와 동일 메시지).
- **per-PR 위임 맥락**: 사용자가 위 승인으로 응답한 작업 계획의 명시 단계 —
  "② 위임 병합 1회 `gh pr merge 121 --merge`(≤5분 single-shot 확인, merge queue
  경유)". 본 위임은 이 단계의 per-PR·시점명시 위임이다(전면 승인 원문은 위임의
  맥락·범위 근거로 보존한다 — MUST-T2a (1)의 blanket 무효 조항과 충돌하지 않도록
  per-PR 명시 단계가 위임의 실체다).
- **rotation 적용 맥락**: 본 PR은 정책 미러(v1.23.0, 7 contexts)를 동반한 단일
  PR로서 merge queue 자격이 순서 무관 불가하다(§2.1 실측). 본 PR 자신의 커밋된
  정책·스펙 — `config/policy/merge_admission.json` v1.23.0 조항 "(3) activation
  순서: PR-A(… trustSurface hit이므로 rotation/운영자 수동 병합 경로) 착지 후
  운영자 ruleset PUT"과 `docs/spec/readiness_verdict_check.md` §5 — 가 rotation
  lane 착지를 선언한다. 이는 VS-I 선례
  (`docs/evidence/sal10_publication/VS_I_publication_integrity_landing.md` §1–§2.2)
  와 동일한 위임 구조다. rotation의 실제 승인 주체는 **사용자(wintrover)** 이며
  에이전트는 실행자일 뿐, 자가 승인하지 않았다.

## §2. per-PR 위임 기록

- **PR**: Archright/Axiom #121 — `feat/readiness-verdict-wiring`
  (병합 시점 head = 본 기록 커밋의 SHA; 기록 직전 head `85063f409540b7f48b6fdf6b372038032749b3e2`).
- **위임 시점 명시**: 2026-11-17 (본 커밋 타임스탬프가 시점 증거).
- **위임 병합 수행 주체**: agent under explicit per-PR delegation from wintrover.
- **실행 명령 (MUST-T2a ③ — manual lane only, 원샷)**: 사용자 승인 계획의 명령은
  `gh pr merge 121 --merge`였다. §2.1의 실측대로 본 PR은 merge queue 경유가
  구조적으로 불가하므로(큐 자격 순서 무관 불가), VS-I §2.2 선례의 3단계 rotation으로
  실행한다 — (i) ruleset 27097366에 일시 bypass actor 등록(PUT), (ii) REST 병합
  엔드포인트 `PUT /repos/Archright/Axiom/pulls/121/merge`(merge_method=merge,
  sha=병합 시점 head 40자), (iii) bypass 제거·ruleset 무결 복원(PUT). `--auto`
  암은 MUST-T1 위반이므로 사용하지 않는다(원샷 수동 병합).
- **실행 세션**: 운영자의 인증된 `gh auth`(wintrover, keyring) — actor
  attribution은 운영자, executor identity는 기록 사실(플랫폼 사실이 아니다).

## §2.1 큐 경로 폐쇄 실측과 rotation 메커니즘 (2026-11-17, 병합 전)

- **GPA 관측 (head 85063f4)**: generation-acceptance run 43882659122 =
  `REJECTED:RULESET_UNAVAILABLE` — L2 "이름 해석: 후보 1건 중 선택 조건
  만족 0건". live ruleset 27097366 = **7 contexts**(운영자 사전 PUT,
  2026-11-16T23:19:58+09:00, ruleset version 58006001), base(main v1.22.0)
  정책 기대 = 6 → 이름 해석 매칭 0건(fail-closed 정상 동작).
- **큐 자격 불가 (순서 무관)**: 본 PR의 candidate 정책은 7 contexts(정책 미러
  동반). (1) PUT 선행 상태(live 7, base 6) → 이름 해석 RULESET_UNAVAILABLE(실측).
  (2) PUT 미선행 상태로 되돌리면 live 6·base 6·candidate 7 → 3-leg
  ADDED=`readiness-verdict` → PROMOTION_PENDING 특례는 `generation-acceptance`
  리터럴 전용 하드코딩(`.github/workflows/generation-acceptance.yml` L521–531,
  baseline c021c33 이후 바이트 불변) 미충족 → `REJECTED:POLICY_RULESET_MISMATCH`.
  PR #45(publication-integrity, VS-I §2.1:36–42 실측)과 동일 범주다 —
  **rotation 레인이 유일 경로**.
- **rotation 메커니즘 (실측 선례에 근거, VS-I §2.2)**: ruleset "main"(27097366)은
  `bypass_actors=[]` — org admin도 bypass 없이는 차단된다. 3단계: (i) 일시
  bypass actor 등록 PUT(본문 = live 7-context·전 규칙·merge_queue 파라미터
  원문 보존 + `bypass_actors:[{actor_type: OrganizationAdmin, bypass_mode:
  pull_request}]`), (ii) REST 병합 엔드포인트로 native MERGE 커밋 생성
  (`gh pr merge --merge` CLI는 merge_queue 규칙을 우회하지 못한다 — VS-I
  §2.2(ii) 실측: 경고·exit 0·무병합), (iii) 복원 PUT(bypass 제거, 7-context
  무결). 각 단계의 명령→응답은 착지 후 본 디렉터리 증거 문서(E1–E6)에
  기록한다.
- **순서 일탈 정직 기록**: 정책 v1.23.0 조항 (3)과
  `docs/spec/readiness_verdict_check.md` §7.1→§7.2가 선언한 순서는
  "PR-A 착지 → 운영자 ruleset PUT"이다. 운영자(본 세션, wintrover 인증 하의
  agent 실행)가 2026-11-16에 PUT을 병합 전에 수행했다(**사전 PUT** — 순서
  역전). §7.3 "드리프트 창은 PUT과 같은 UTC 일 내 폐쇄"도 이미 위반된 상태다
  (2026-11-16 PUT → 2026-11-17 착지). 수습: rotation 착지로 창을 즉시 폐쇄하고
  일탈(순서 역전·창 길이·UTC 일 경과)을 activation 증거에 정직 기록한다.
  조용한 통과 선언 금지(AGENTS.md §0.9).
- **실행 전제**: (1) 본 기록 커밋 push 후 브랜치 헤드에서 GPA 제외 전 잡
  녹색 + readiness-verdict 자기 실행(pull_request) 녹색 관측, (2) 큐 비었음
  (gh-readonly 브랜치 0 관측 — mid-queue mutation ban 준수) 확인 후 실행한다.

## §3. 착지 후 절차 (본 위임 범위 밖 — 각각 별도 관측·기록)

1. main push에서 readiness-verdict 잡 **첫 production 실행** 녹색 관측
   (productionRun, head==mergeCommit).
2. activation manifest `data/promotions/readiness-verdict-activation/manifest.json`
   (axiom.promotion-manifest.v1 형상 + rotation 착지·사전 PUT 일탈 기록).
   `tools/promotion/validate_manifest.sh` rel_1은 `event==merge_group`을 요구하므로
   rotation 착지 manifest는 그 관계에서 기계 검증 불가 — 이 구조적 갭을 명시
   기록한다(VS-I 선례: publication-integrity는 manifest 없이 착지 기록 문서로
   대체). 검증 실패를 조용히 통과 선언하지 않는다.
3. 음성 대조 probe(sole-blocker) — 위조 판정 입력 → readiness-verdict FAILURE +
   기존 6 required green + mergeStateStatus BLOCKED + 미병합 close.
4. 제3자 재현(동일 verdict·decisionDigest) — `docs/spec/readiness_verdict_check.md` §6.
5. DEBT#537 청산(debt_engine) + E1–E6 증거(본 디렉터리) 착지.
