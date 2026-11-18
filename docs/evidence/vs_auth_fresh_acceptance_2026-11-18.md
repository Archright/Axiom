# VS-AUTH-FRESH 수용 증거 — Fresh full-scope prove 관측 (2026-11-18)

> 본 문서는 `docs/agents/rules_workflow.md` §2.8 MUST-T2a(2026-11-04 비준)의
> per-PR·시점명시 위임 기록 패턴을 따른다 — **병합 명령 실행 전에 커밋된다.**
> 기록자 ≠ 승인자: 작성자는 agent(wintrover의 대리 실행자)다.

## §1. 범위

- **궁극적 목적**: 과거 검증 결과나 캐시가 현재 소스에 대한 새로운 검증을 대신하지 못하게 한다.
- **PR-A (#155, 본 PR)**: `config/repository_surface.json` policyVersion v102→v103 —
  `.github/workflows/fresh-prove-observation.yml`을 CONTROLLED + `frozenExceptions`에 선등록.
  이 파일은 App trust surface(`config/policy/trust_surface_manifest.json`) 경로 자신이므로
  정상 PR 레인에서는 App `admission-check`를 받을 수 없다(§3 기계 관측).
- **PR-B (후속, 본 PR 비포함)**: 관측 워크플로 본문 + `docs/spec/fresh_prove_contract.md` +
  `--fresh` 우회/verdict 투영. PR-B는 trust surface를 변경하지 않는다(신규 워크플로 파일은
  manifest 경로가 아니며, base v103의 CONTROLLED 등록으로 FROZEN ADD가 PASS한다).
- **Out of scope**: #547(ckIfStmt), #551(IR 경계), #549(required 승격), vdVerified,
  phase_x10, Outage, DEBT#552. 증명 의미론은 변경하지 않는다.

## §2. MUST-T2a 위임 기록 (Pre-Merge Delegation Record)

**§2.1. 승인 원문 (사용자 = 인간 아키텍트 wintrover, 본 세션 대화, 2026-11-18 KST)**

- "목표는 코드 작성 완료가 아니라 실제 운영 상태다."
- "`구현 → 검증 → PR → merge → canonical main/production 실행 → acceptance`를 실제 명령과
  관측 가능한 증거로 끝까지 확인하라. 선언, PR 생성, 로컬 테스트, 부분 CI 성공은 완료가 아니다."
- "권한이 필요한 부분은 전면 허가한다." / "권한이 필요한 부분은 전면 승인한다." (반복 명시)

위 원문은 본 PR(#155)의 착지 단계에 대한 per-PR·시점명시 위임의 근거다. MUST-T2a (1)의
blanket 무효 조항과 충돌하지 않도록, 본 세션 작업 = "VS-AUTH-FRESH를 terminal outcome까지"가
위임의 실체다. 착지의 실제 승인 주체는 사용자(wintrover)이며 agent는 실행자일 뿐, 자가
승인하지 않았다(MUST-T2a (4) honest executor record).

**§2.2. 위임 대상과 시점**

- 대상: PR #155 (head `2dfc314`, base `983e836`) — 단, 본 기록 커밋 후의 신규 헤드가 착지 대상이다.
- 레인: manual one-shot only. `--auto` arming 없음(MUST-T1, `autoMergeRequest=null` 확인).
- 실행자: agent under explicit per-PR delegation from wintrover. 운영자의 인증된 `gh auth`
  세션에서 실행되며 actor attribution은 운영자다(MUST-T2a (2)).

## §3. 정상 경로 폐쇄의 기계 관측 (trust-surface PR)

- live ruleset `27097366`(`main`, active, `bypass_actors: []`)의 required contexts 7개 중
  `admission-check`의 producer는 App `5795152`(`axiom-admission-verifier`)다(§4 readback).
- PR #155 head `2dfc314`에서 App check-run 판정:
  `trust_surface=FAIL — mismatch:config/repository_surface.json (total 1)`,
  `reasons=trust_surface:mismatch:config/repository_surface.json (total 1)`.
- `config/policy/trust_surface_manifest.json`의 `purpose` 원문: "A PR that alters any listed
  path cannot receive the independent verifier's admission-check; such changes require the
  audited break-glass lane and an explicit epoch rotation."
- 동일 클래스의 선례: PR #153(policy v102, `config/repository_surface.json` + `tools/surface_guard.nim`
  변경)도 App `admission-check` FAILURE 상태에서 아키텍트가 착지했다(merge `983e836`,
  mergedBy `wintrover`). 본 PR-A의 policyVersion v103 상승이 그 "explicit epoch rotation"이다.

판정: 본 PR은 설계상 App 승인을 받을 수 없으며, 정상 merge queue 경로는 폐쇄되어 있다.
따라서 저장소가 문서화한 audited break-glass lane(ADR-0041 §6, E1 §2.2 / VS-I §2.2 3단계)으로
착지한다.

## §4. 실행 절차 선언 (3단계 break-glass, RESTORE_IDENTICAL)

**실행 전제(기계 관측)**: (1) 본 기록 커밋 push 후 신규 헤드에서 required Actions contexts 6개
전량 SUCCESS 관측(App `admission-check`는 §3의 설계상 FAILURE) (2) merge queue entry 0·
`gh-readonly-queue/*` 브랜치 0 (3) `autoMergeRequest=null` (zero arming).

1. **Pre-snapshot**: `GET /repos/Archright/Axiom/rulesets/27097366` 전체 본문 보존.
   본 문서 작성 시점 스냅샷 SHA-256 = `6b03a83f14a5eb837ea567a1e232e1918aab39686fdbcca3e7c7229c7a1d9b35`
   (`bypass_actors: []`, 5 rules, 7 contexts).
2. **bypass 활성화**: `PUT`으로 live 본문 그대로 + `bypass_actors: [{actor_type:
   OrganizationAdmin, bypass_mode: pull_request}]` — required status checks·merge_queue
   파라미터 원문 보존.
3. **native merge**: `PUT /repos/Archright/Axiom/pulls/155/merge` (`merge_method=merge`,
   `sha=<기록 커밋 후 헤드 40자>`) — GitHub-native MERGE 커밋.
4. **복원**: bypass 제거 PUT(무결 원문 복귀) 직후 `GET`으로 pre-snapshot과 **바이트 동일**
   검증(RESTORE_IDENTICAL). timestamps·readback을 본 문서에 기록한다.

M7(진단 순수성) 정직 기록: 본 세션의 동일 identity가 ruleset을 GET/PUT한다 — Tier 1 분리
불가 상태. 본 기록이 선언된 Mutator 창이며, 명령→응답 전 과정을 본 문서에 남긴다.

## §5. 착지 후 기록 (post-merge readback)

### §5.1 PR-A (#155) break-glass 착지 — 관측값

- **정상 경로 기계 관측 (신규 헤드 `e38b198`)**:
  - App `admission-check` (`axiom-admission-verifier`, 5795152): `failure`
    (started 01:42:11Z, completed 01:49:07Z) — `trust_surface=FAIL —
    mismatch:config/repository_surface.json (total 1)`, `ledger=not-required(preflight venue)`.
  - required Actions contexts 6개: `bsec-integrity`, `debt-registry-gate`,
    `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`,
    `readiness-verdict` — 전량 `pass` (전체 rollup: pass 32 / skipping 14 / fail 1).
  - `autoMergeRequest=null`. merge queue: 01:51Z `#158`·`#152` 2건 AWAITING_CHECKS →
    01:56:12Z `0` 관측 후 착지(M2 준수).
- **첫 시도 거부(정직 기록)**: 01:56:14Z 착지 스크립트가 `PR not MERGEABLE`로 거부 —
  직전 두 PR 병합으로 base가 이동한 뒤의 mergeability 재계산 창. **bypass는 활성화되지
  않았다**(trap 이전 단계).
- **Pre-snapshot**: `6b03a83f14a5eb837ea567a1e232e1918aab39686fdbcca3e7c7229c7a1d9b35`
  (`bypass_actors: []`, rules 5, required contexts 7).
- **bypass 활성화**: `OrganizationAdmin` / `pull_request`, `2026-11-18T01:56:42.384Z`.
  readback: `bypass_actors` length 1.
- **native merge**: `PUT /repos/Archright/Axiom/pulls/155/merge` (`merge_method=merge`,
  `sha=e38b198…`) → `merged=true`, merge commit
  `ad96ed2aacda2674543c408573e7687ccf8a7cd9`, `2026-11-18T01:56:46.623Z`.
- **복원**: `2026-11-18T01:56:47.292Z`, `RESTORE_IDENTICAL=YES` (정규화 본문 byte 동일;
  raw post SHA-256 `60198954…`는 `updated_at` 등 휘발 필드로 상이 — 정직 기록).
  post readback `bypass_actors=[]`, contexts 7. 창 길이 **약 4.9s**.
- **M7 정직 기록**: 동일 identity가 ruleset GET/PUT을 수행한 선언된 Mutator 창.
  actor attribution = 운영자(`wintrover`), executor = agent under explicit per-PR delegation.
- **착지 후**: main tip = `ad96ed2`, `config/repository_surface.json` policyVersion `103`.

### §5.2–§5.3 (PR-B 및 canonical main 관측)

PR-B 착지 값과 canonical main `fresh-prove-observation` run/artifact/digest는 후속
docs 전용 커밋(PR-C)에서 append한다 — 선언과 관측을 분리하되 동일 문서 계보를 유지한다.