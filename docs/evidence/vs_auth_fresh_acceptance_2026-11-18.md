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

**§2.3. PR-B (#159) 위임 — trust-surface rotation pin 포함**

- 대상: PR #159 (branch `vs/auth-fresh`). `config/trusted_writer_set.json`의
  `trustedCheckerTreeClosure`(rotation pin) 갱신을 포함하므로 **trust-surface PR**이다 —
  리베이스로 이동한 checker closure blob 5건을 H2(`rotation_pin_anchor_check`)가 요구한다.
- 승인: §2.1의 동일 원문(2026-11-18, per-PR·시점명시)이 본 PR의 착지에도 적용된다.
  기록자 ≠ 승인자, agent는 실행자다.
- 정상 경로 예측: App `admission-check`는 `mismatch:config/trusted_writer_set.json`으로
  거부될 것으로 예측된다(관측값은 §5.2에 기록). 예측은 승인을 대체하지 않는다.
- 레인: 동일 3단계 break-glass. `--auto` 없음(MUST-T1), queue 0 확인 후 실행(M2),
  복원 후 RESTORE_IDENTICAL readback. 실행 전 신규 헤드에서 required Actions contexts를
  관측한다.

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

### §5.2 PR-B (#159) break-glass 착지 — 관측값

- **PR**: `#159` (https://github.com/Archright/Axiom/pull/159), head
  `705f3080fc504110d05c25695dac8e0c01731119`, base `ad96ed2aacda2674543c408573e7687ccf8a7cd9`.
- **정상 경로 기계 관측 (App `admission-check`, `axiom-admission-verifier` 5795152)**:
  `failure` (started 02:11:33Z, completed 02:14:27Z), output summary 원문:
  `venue=pull_request` / `evaluated_commit=705f308…` /
  `run=44220703054 attempt=1 conclusion=failure` /
  `trust_surface=FAIL — mismatch:config/trusted_writer_set.json (total 1)` /
  `reasons=run_head_mismatch | conclusion=failure |
  trust_surface:mismatch:config/trusted_writer_set.json (total 1)` /
  `ledger=not-required(preflight venue)`.
  — rotation pin 갱신을 포함한 trust-surface PR이므로 설계상 예상된 거부다(§2.3 예측 일치).
- **required Actions contexts 6개**: 전량 `pass`. 전체 rollup: `pass 34 / skipping 13 /
  fail 1`(fail 1 = 위 App check).
- **PR-venue 관측 run** `44221416590` (event `pull_request`, conclusion `success`):
  artifact `fresh-prove-observation` — verdict `UNKNOWN`, `exitCode=3`,
  `checkConclusion=neutral`, subject `705f308…`(tree `1fc5a4c9…`),
  `canonicalEvidenceDigest=234ed29ba440936250ebfd427da06f0a85bd5db928688ea88eabd4e945c51df5`,
  counts `{units 5, required 5, proved 2, refuted 0, unknown 3, outOfScope 0}`,
  coverage `17/40`, `closureComplete=false`,
  reasons `pending-contested, unsatisfied-without-refutation-witness, closure-incomplete,
  vda-not-pass, scope-coverage-incomplete`, `prove_exit=1`, `report_exit=1`,
  `fresh=true`, `authoritative=false`, reuseBypass 4경로
  (`vault-verified-set, vault-spec-priming, certificate-hydration, summary-cache`).
- **merge queue 관측 (M2)**: 착지 전 `#157 AWAITING_CHECKS` + `#160 UNMERGEABLE` 2건 →
  02:27:45Z `#157` merged(`223339b`), `#160` `merge_conflict`로 제거 → entry 0 확인 후 착지.
- **첫 착지 시도 거부(정직 기록)**: 02:27:59Z `REFUSE: PR not MERGEABLE` —
  `#157` 병합으로 base가 `ad96ed2`→`223339b`로 이동한 직후의 mergeability 재계산 창.
  **bypass는 활성화되지 않았다**(trap 이전 단계, exit 13).
- **Pre-snapshot**: raw SHA-256
  `60198954222c6f1a55c54bc862c6387c569db58e71a5b19547a5e07676c2032b`
  (`bypass_actors: []`, rules 5, contexts 7). §5.1 복원 후 raw SHA와 동일 — 창 사이 무변경.
- **bypass 활성화**: `OrganizationAdmin` / `pull_request`, `2026-11-18T02:29:09.658Z`.
  readback: `bypass_actors` length 1.
- **native merge**: `PUT /repos/Archright/Axiom/pulls/159/merge` (`merge_method=merge`,
  `sha=705f308…`) → `merged=true`, merge commit
  `b41b56840a1c88683f7264d1de541a1553fb36dd`, `mergedAt=2026-11-18T02:29:12Z`.
- **복원**: `2026-11-18T02:29:14.780Z`, `RESTORE_IDENTICAL=YES`, post readback
  `bypass_actors=[]`, contexts 7. raw post SHA-256 `5554c6a6…`는 `updated_at` 등
  휘발 필드로 상이(§5.1과 동일한 정직 기록). 창 길이 **약 5.1s**.
- **M7 정직 기록**: 동일 identity의 ruleset GET/PUT Mutator 창. actor attribution =
  운영자(`wintrover`), executor = agent under explicit per-PR delegation (MUST-T2a (4)).
- **착지 후**: main tip = `b41b56840a1c88683f7264d1de541a1553fb36dd`,
  `config/repository_surface.json` policyVersion `103` 유지.

### §5.3 canonical main 관측 (`fresh-prove-observation`, event `push:main`) — 관측값

- **run**: `44223601864` (https://github.com/Archright/Axiom/actions/runs/44223601864),
  event `push`, branch `main`, head `b41b56840a1c88683f7264d1de541a1553fb36dd`,
  conclusion `success` (created 02:29:15Z, updated 02:32:17Z).
- **artifact** `fresh-prove-observation` → `fresh-verdict.json`:
  - verdict **`UNKNOWN`**, `checkConclusion=neutral`, `exitCode=3`,
    `fresh=true`, `authoritative=false`, `satisfiedByReused=0`.
  - subject.sha `b41b56840a1c88683f7264d1de541a1553fb36dd` — **PR #159 merge commit과 일치**.
    subject.tree `736bc9e18ead4d14f02c1fadbeea70210a3e53a6`.
  - `canonicalEvidenceDigest=28f21741b6bf14ef3d5e8be864fb015ff1dfcc3e5ba1ed072294b152381869e5`.
  - `scope.lockDigest=140fd7004e088aeda054801ab797ef0d036d4901f33c51adb3cf36c348012788`
    — PR-venue(`705f308`)와 동일. scope lock은 subject 간 안정적이다.
  - counts `{units 5, required 5, proved 2, refuted 0, unknown 3, outOfScope 0}`,
    coverage `17/40`, `closureComplete=false` (4/23).
  - provenance `{runId 44223601864, attempt 1, runUrl …, runner "GitHub Actions 1000005899",
    generatedAt 02:32:13Z}` — canonicalEvidence에는 포함되지 않는다(§5.3 검증 항목).
  - `prove_exit.txt=1`, `report_exit.txt=1`.
  - reuseBypass 4경로 전량: `vault-verified-set, vault-spec-priming,
    certificate-hydration, summary-cache`.
- **관측 검증 스크립트 12개 항목 전부 PASS**: verdict / exitCode / checkConclusion /
  fresh 선언·실행 / authoritative=false / satisfiedByReused=0 / subject SHA 결속 /
  provenance runId / contract / reuseBypass 4경로 / canonicalEvidence 내 실행 provenance 부재.
- **정직 기록 (green ≠ proof success)**: 이 run의 `conclusion=success`는 "관측이 수행되고
  정직하게 보고되었다"는 뜻이며 **증명 성공이 아니다**. verdict가 `UNKNOWN`인 이유는
  DEBT#547(ckIfStmt 미지원)·closure 미완(4/23)·coverage 17/40이다. UNKNOWN/neutral을
  green 성공으로 과장하지 않는다.
- **canonical digest 비비교(정직 기록)**: main digest `28f21741…`와 PR-venue digest
  `234ed29b…`는 subject tree가 다르므로 동일해야 하는 대상이 아니다(#159 head tree
  `1fc5a4c9…` → #157 병합 후 `736bc9e1…`). 동일 입력 2회 실행의 digest 동일성은 로컬
  unit test(`tests/unit/test_fresh_prove_verdict.nim` — digest A/B·순열 불변 13 cases)로
  검증되었으나, CI 상시 강제는 phase_x10 follow-up이다.
- **동일 commit push:main 부수 run**: `trusted-writer-set` `success`,
  `dynamic Push on main` `success`,
  `axiom-operational-slice` `44223601879`(`readiness-verdict` 포함) `success`.
- **acceptance 판정**: `구현 → 검증 → PR → merge → canonical main 실행 → 관측`의 전 구간이
  실제 run/artifact 값으로 종결되었다. 기존 병합 권한(ruleset `27097366`, contexts 7,
  `bypass_actors=[]`)은 착지 후 readback으로 동일하게 복원되었다(§5.2).