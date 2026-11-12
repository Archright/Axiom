# GitHub 위임 잔여 위협 (github_delegation_residuals)

**Status**: Normative — §0.5 잔여/fail-open 기록. 대응 결정: **ADR-0025 Amendment B (2026-09-29)**.

**범위**: GitHub 플랫폼이 이미 보장하는 사실을 재구현하던 코드(DiD 계층)를 제거하고 플랫폼
TCB로 수용한 뒤 남는 잔여 위협과, `workflow_run` 단일 씨딩 writer의 실패 모드를 기록한다.
전제: **캐시는 가속일 뿐 증거가 아니며 판정 입력도 아니다**(J3 —
`docs/spec/ci_optimization_tcb_judgments.md:19`).

## 1. 위임 목록 (제거된 Axiom 재구현 → 플랫폼 보장)

| 제거된 재구현 (심볼) | 위임 대상 (GitHub 보장) |
|---|---|
| `STALE_BASE` Pass 0 = **Axiom decision input으로 복원** (2026-10-03, freshness 단일 판정 — `MergeAdmissible(V, mainSha)` 실제 소비; merge 시점 집행은 여전히 ruleset `strict_required_status_checks_policy`) · **2026-10-05 개정(ADR-0027 P4)**: 판정 앵커가 살아있는 PR API `base.sha`에서 **이벤트 고정** base(`AXIOM_MAIN_SHA` = `pr.base.sha \|\| merge_group.base_sha`)로 이동 → 큐 경로에서 Axiom 측 deny는 큐 자신의 권위 base에 대한 항등식이 되어 그 경로에서 사라지고(오탐 제거: ~247분 낭비 실측), deny 자체는 declared main ≠ 기록 앵커·앵커 부재 호출자에서 그대로 발동한다. PR 경로의 "실행 중 base 이동" deny는 워크플로 identity 재파생 + GitHub strict required-check 무효화가 계속 담당한다 · `MAIN_MOVED` A3 프리플라이트 (`src/cli/landing_cli.nim`) | ruleset `strict_required_status_checks_policy` — 병합 시점 stale base 차단 |
| `requiredWorkflowEvidenceOutcome` + `RW_RUN_MISSING/RW_RUN_FAILED/RW_VERDICT_*` + `observationSkip` 기계 (`src/cli/merge_cli.nim`) | required check `admission-check`의 job 결론 = 진본 판정 |
| 체크 증거 수집(M2) · workflow-id 이중 결속(M3) · `rulesetAdmissionRequirementOk`(M5) · stale 재조회(M12) (`src/cli/merge_cli.nim`) | ruleset required_status_checks의 expected-source(App integration_id=15368) + merge API `sha` 핀 |
| HMAC-SHA256 Phase 4b + git note (`src/gate/gateway.nim`, `src/infrastructure/sync_signing.nim`) | GitHub 네이티브 커밋 서명 검증 · GitHub 생성 머지 커밋 |
| `buildMergeCommitMessage` (`src/cli/merge_cli.nim`) | GitHub 기본 머지 커밋 메시지(서버 측 생성) |
| `landing-trigger` Check Run POST (`.github/workflows/admission-check.yml`) | workflow job 결론 = required check 보고 (제2 상태 채널 0) |
| orphan 시드 위생 — 소비 불가 예정 키의 시딩 억제·자체 만료(스케줄러 · `gh cache delete` 루틴 · 자체 TTL) (재구현 금지 판정 — 구현 0건 유지, 2026-10-08; 판정 전문 `docs/evidence/orphan_seed_quota_delegation_2026-10-08.md`) | GitHub Actions cache eviction — 총량 상한(기본 10GB) 초과 시 last-access 오름차순 삭제 + 7일 미접근 엔트리 제거 (docs.github.com, *Dependency caching reference* "Usage limits and eviction policy") |

위 목록의 심볼명이 `docs/` 외에서 0건인 것이 E4(기계 판정)의 통과 조건이다 — 본 문서의 존재가
그 rg 결과의 docs 허용 근거다.

## 2. 잔여 위협

- **R1 — 동명 체크 위조**: 워크플로 단위 결속이 제거되어, 같은 저장소의 다른 워크플로가
  `checks: write`로 동명 체크를 POST할 수 있다. 남는 방어선은 ruleset의 expected-source(App)
  결속이며, 워크플로 자체 편집은 CODEOWNERS/trustSurface(`/.github/` @Archright/architect)로
  보호된다.
- **R2 — ruleset 설정 표류**: `strict`·required check가 설정에서 꺼지면 freshness/판정 보장도
  함께 소멸한다(플랫폼은 설정된 대로만 집행). 탐지는 운영 감사(ruleset API 실측)로만 가능하다.
  **ADR-0027 (2026-09-29) — freshness provider 전환**: 큐 활성화 시 freshness 제공자는
  ruleset `strict`에서 **큐 무효화(queue invalidation) 의미론**으로 이전한다(체크가 stale이면
  큐가 재실행). 현행 라이브 ruleset(20303214)의 `strict_required_status_checks_policy`는
  **`true`**다(2026-10-04 재실측 `gh api repos/Archright/Axiom/rulesets/20303214`). 동일한
  명령이 2026-10-03에는 `false`를 반환했으므로, 이전 판정은 **의도된 표류 기록이 실측 오판
  이었던 것**이다 — 이 정정은 조용한 수정이 아니라 실측 재확정이며, required check의
  freshness 결속은 현재 머지 시점에 집행된다. 표류 위협(R2)과 그 탐지 성질 자체는 **잔존**:
  설정은 언제든 다시 꺼질 수 있고 탐지는 여전히 운영 감사로만 가능하며, Axiom은 판정만 한다
  (GitHub 집행). 잔여 번호는 재배열하지 않았다(R1–R10 유지 — 잔여의 추가·삭제가 없었으므로).
  전환 후 신규 잔여 표면: **큐 규칙/설정 표류(queue rule/config drift)**가 R2의 새 표면이
  된다 — 탐지는 위와 동일하게 운영 감사(큐 규칙·설정 API 실측)로만 가능하다.
  **ADR-0027 P5 (2026-10-05) — strict 은퇴 결정**: `strict_required_status_checks_policy`의
  freshness 역할 은퇴가 결정되었다(operator 승인 — ADR-0027 §P5). main 착지 경로의
  freshness 집행은 큐 무효화 의미론 단일 체계가 되며, 위 표류 기록(2026-10-03 `false` →
  2026-10-04 `true` 재실측)은 역사 기록으로 보존된다. 라이브 상태(`strict=false` 전환)의
  재실측은 본 결정의 수용 증거와 함께 기록된다 — 실측 이전의 상태 선언은 하지 않는다.
  **[실측 기록 — 2026-10-11, 위 "기록된다" 예약의 이행]**: 라이브 ruleset 재실측 결과
  `strict_required_status_checks_policy: false`다(`gh api
  repos/Archright/Axiom/rulesets/20303214` — `enforcement: active`). 동일 관측에서
  `merge_queue` 규칙은 활성(grouping_strategy ALLGREEN · merge_method MERGE ·
  max_entries_to_build 2 · max_entries_to_merge 1 · check_response_timeout_minutes 120)이고,
  required check는 `admission-check`(integration_id 15368) 단일, `bypass_actors=[]` 유지다.
  즉 P5의 라이브 전환은 **착지**했으며, main 착지 경로의 freshness는 **큐 무효화
  의미론**으로 집행된다 — 위 2026-10-04 `true` 독해는 전환 이전의 역사 기록이다.
  R2 잔여 자체(설정은 언제든 다시 꺼질 수 있고 탐지는 운영 감사로만 가능)는 불변. 정본:
  `docs/adr/0027-queue-delegation.md` §P5.
  **merge_queue 파라미터 의미 정정 (2026-10-12 — 범위 분리 작업)**: 라이브
  merge_queue가 운반하는 세 파라미터의 정확한 역할은 다음과 같다.

  | 파라미터 (라이브 값) | 정확한 역할 (공식 정의) | 감시 분류 |
  |---|---|---|
  | `grouping_strategy` (ALLGREEN) | 그룹 내 필수 검사의 적용 방식 — 그룹에 속한 모든 PR의 필수 검사가 GREEN이어야 병합(그룹 단위 일괄 적용; HEADGREEN 금지 — ADR-0032 (e) 정책 층) | **감시 대상** — 병합 정책 드리프트 감시의 핵심 (`merge_ruleset_drift_monitor` 4번째 기대) |
  | `max_entries_to_merge` (1) | 함께 병합할 PR 수 상한("Merge limits do not combine merge_group builds" — GitHub Docs) | 감시 대상 아님 — 형상(1:1)은 설정값이 아니라 구조 층에서 강제 |
  | `max_entries_to_build` (2) | 동시 검사·빌드 수 제한(merge_group webhook throttle) — **그룹 크기 보장이 아니다** | 감시 대상 아님 — 운영 성능 파라미터; 감시 확장은 별도 Follow-up(독립 작업으로 분리) |

  **설정 감시 ≠ 형상 강제**: 드리프트 모니터는 구성 스냅샷·탐지일 뿐 보안 경계가
  아니며(NOT a security boundary — `docs/agents/rules_workflow.md` "Authority
  layering": "Never describe both as the same boundary"), 1:1 형상 강제는
  merge_group 이벤트 부모 관계·PR identity·후보 트리 동등성(구조 층)으로
  이루어진다.
- **R3 — `workflow_run` + `cache-mode: write` cache-poisoning**. 공식 경고(GitHub 문서 원문):
  > "Explicitly declaring `cache-mode: write` or `cache-mode: write-only` reintroduces the
  > risk of cache-poisoning that the default untrusted-trigger read-only permissions are
  > designed to prevent. If a workflow that runs on an untrusted trigger, such as
  > `pull_request_target`, `issue_comment`, or `workflow_run`, declares a write-capable
  > cache-mode, vulnerabilities or untrusted code execution in the workflow could then be
  > used to save a cache. A more privileged workflow that later restores that cache could
  > then execute attacker-controlled content."
  > — docs.github.com, *Dependency caching reference* ("Bypassing the default
  > untrusted-trigger cache restriction")

  완화: ① 키 = **tree OID content-addressing** — 오염된 내용을 정직한 키 아래 기록하려면
  트리 해시 충돌이 필요 ② 키·트리 OID는 **Git Data API 사실**(`git/commits/{build_sha}.tree`)로
 도출하며, manifest 자기 주장 `build_sha`는 **실행 주제 identity**(merge_group: `build_sha ==
  run.head_sha` / pull_request: `run.head_sha ∈ parents(build_sha)` — ADR-0025 Amendment D)로
  결속될 때만 채택 — 미결속 자기 주장은 fail-closed skip ③ 검증 체인(run path · conclusion ·
  fork · manifest per-file sha256) 실패 = **기록 생략**(fail-closed skip, red run 없음 — 가속
  포기만) ④ 단일 최소 publisher — 빌드·판정·테스트 0, 새 권위 없음 ⑤ J3: 저장된 캐시는
  증거가 아니다.
- **R4 — fork PR 미발행**: fork push는 base 저장소에 `workflow_run`을 전달하지 않는다 → fork
  PR 게이트의 트리는 씨딩되지 않음. 콜드만, 정확성 무관.
- **R5 — 교차 타이밍**: 퍼블리셔 완료 전에 다음 PR이 시작되면 그 1회는 콜드 빌드. 정확성
  무관(가속만).
- **R6 — mode=none 게이트**: ci-bootstrap 미실행 → 아티팩트 부재 → 미발행. 다음 PR의 base
  빌드가 콜드일 수 있음(가속만, 정확성 무관).
- **R7 — arm-완료 사이 ruleset `merge_queue` 규칙 제거 → 완료 시점 재평가 하의 직접 머지**:
  Auto-Merge Default Policy(`docs/agents/rules_workflow.md` §2.8 — 2026-10-03 개정: arm
  실행은 GitHub 프리미티브 `gh pr merge <N> --auto`, Axiom in-CLI arm-auto lane은 제거)에서 arm 후
  관리자가 live ruleset에서 `merge_queue` 규칙을 제거하면, GitHub는
  완료 시점의 **현재** ruleset을 재평가하므로 대기열 머지가 예정이던 PR이 직접 머지로 이행될
  수 있다. 이는 R2(ADR-0027)의 큐 규칙/설정 표류 신규 표면의 구체적 사례이며, Axiom 경로의
  fail-open이 아니라 **구성 평면(configuration-plane) 외부 불변식**이다 — arm 전의 구성
  스냅샷·드리프트 탐지는 `merge_ruleset_drift_monitor`가 담당하며(보안 경계 아님), Axiom
  통제 경로와 ruleset 관리자 변경은 동일한 경계로 서술하지 않는다. 완화: 드리프트
  모니터(신규 도구 — 라이브 ruleset vs 기대 구성을 비교하고 `gh pr merge <N> --disable-auto`
  를 제안)가 구성 드리프트를 탐지한다.
- **R8 — gh run watch cannot observe org-workflow runs**: delegated 관측 도구
  (`gh run watch`/`gh run view`)가 교차 저장소 required workflow run에 구조적으로
  실패한다 — run의 `workflow_id`를 대상 저장소의 `actions/workflows/*` 엔드포인트로
  조회하므로 org `.github` 저장소가 소유한 workflow(admission-gate)의 run에서 HTTP 404를
  반환한다(2026-09-30 실측, merge_group run 36667874946). 완화: run-id 기반 REST 폴링
  (`GET /repos/{owner}/{repo}/actions/runs/{run_id}`, ≥30s 간격 — AGENTS.md §2.3
  부트스트랩/예외 패턴, 사고 중 1회 구현·사용). 상세:
  `docs/spec/gh_org_required_workflow_run_quirks.md` (Quirk: `gh run watch`/`gh run view`
  404 on org-required-workflow runs).
- **R9 — base-artifact 시딩 경로 (2026-10-01 추가, census §4/§5.1 대응)**: 퍼블리셔가
  `admission-check-base-artifacts`(게이트 job1의 base.sha 빌드 산출물 — bin/ax ·
  bin/install_ax_cas · ircheck · manifest)를 base-트리 b-key로 재발행하는 새 경로.
  방어: ① **앵커 = 플랫폼 진실만** — pull_request 유형 런은 workflow_run 페이로드의
  `pull_requests[0].base.sha`, merge_group 유형 런은 `git/commits/{head_sha}`의
  parents[0] — manifest `build_sha` 자기 주장과 **정확 일치**일 때만 진행, 불일치 =
  fail-closed skip(크로스-트리 내용 차단 — lane 등식 게이트와 동일 의도) ② per-file
  sha256 대조(전송 무결성) ③ 키 = 소비자와 동일 공식(keygen-only,
  cache-build-source = manifest build_sha == base.sha; checkout을 base 트리로 전환해
  레시피/script 해시를 base 트리에서 계산) ④ 페이로드는 아티팩트 내용 한정 —
  nimcache 미포함 = **부분 온기만** (J3: 캐시는 가속일 뿐 증거 아님 — 정확성 무관).
  남는 위협: (a) base 아티팩트 **자체 부재**(admission-check-base-artifacts 미생성 —
  빌드 전무) 시 base 미발행 — R6과 동일 (콜드만, 정확성 무관). mode=none 사이클
  (ci-bootstrap 없음)도 base가 빌드되면 base 시드는 진행된다(2026-10-01
  fix/ci-publisher-base-guard-decouple — path 게이트 분리; 이전엔 base 경로가 lane
  아티팩트 존재 게이트에 결속되어 mode=none에서 시드 불가였다) (b) **저장 path
  목록·version 정합 계약 (2026-10-01 실측 → fix/ci-publisher-base-save-path)**:
  GitHub actions/cache 공식 — cache version은 cache inputs(compression + **path
  목록**)에서 유도되므로, 시드 저장 시 path 목록이 소비자 b-restore(action.yml
  9행)와 바이트-동일하지 않으면 키가 존재해도 복원 미매칭(`Cache not found` —
  REST에는 키 존재). 실측: T1(lane 9경로) version=c0438c13… 복원 성공 /
  T2(base 4경로) version=6a4c304a… 복원 4회 전부 실패(S·D·F-PR·F-MG). 계약:
  base save path = 소비자와 동일 9행 (c) **이미지 롤
  기간 a_fp 변동 잔존** — 라벨 제거와 무관:
  gcc/glibc 지문이 실질 툴체인 변동(2026-09-29 W1 런 36620566732의 ImageVersion
  드리프트는 라벨만 변하고 gcc/glibc/script는 동일했음 — LABEL_NOISE 실측 114/114,
  census §2-§3; 해당 관측은 "방어가 작동"한 것이 아니라 **라벨-유도 false-MISS**였다)
  (d) 라벨만 포착 가능한 비-gcc/glibc 이미지 드리프트(예: binutils/ld 개정)는
  미측정 표면 — fail-closed 의미론(B-verify digest 불일치 → 폐기 → 네이티브 빌드,
  SourceCoherence FATAL)으로 정확성은 불변, 가용성만 콜드로 회귀. 이 항목이
  a_key 라벨 제거(action.yml, 2026-10-01)의 반론 근거이자 잔여 위협 기록이다.

- **R10 — lane 트리-헤드 등식 게이트의 ahead-invariant 잔여 (2026-10-01 추가, census §3/§5.1
  B(i) 실측 대응)**: 퍼블리셔 lane 페이즈의 트리-헤드 등식 게이트(tree(manifest build_sha) ==
  tree(run head) — ahead-invariant)가 **stale PR 구간**(tree(build) ≠ tree(head))에서
  `[publish-skip]`을 내고, PR 페이즈 콜드였던 lane identity가 merge_group 페이즈에서
  **사이클 내 2회째 콜드**로 재계산될 수 있다 — 가속 소실일 뿐 정확성 무관(J3: 캐시는
  가속일 뿐 증거 아님). 실측 근거(census B군): census 사이클 A — PR-phase 발화
  36703314113 `[publish-skip] tree(build_sha)=c5f999f7… != tree(head_sha)=74ffa295… —
  content identity not landable as tested (ahead invariant absent)` → A·mg lane
  36703362000 동일 b-key `c5f999f7·d807d897·14fc017c` **MISS(콜드 134s)** — census §5.1
  #4 "동일 b-key 재계산 — PR-phase 퍼블리셔 SKIP(§3) + mg-phase 퍼블리셔 fp 불일치가
  원인"(B(i) identity-fixable; 교차 사이클 사례 §5.1 #5·#6 동일 클래스). 성질:
  **bounded**(ahead-invariant 부재 — stale PR 구간 한정) ∧ **fail-closed**(시드 생략일 뿐
  잘못된 내용 기록 0, red run 0, 판정 입력 아님). 제거 조건 = **P2-3(a)급 manifest 앵커링**
  (S5 인접 — ADR-0026 cache-manifest(S5)·tools/ci/tcb_judgments.nim:404 "improvement
  P2-3(a) not yet landed"; 별도 결정 바인딩으로만 제거). **accepted residual**.
  **재판정 (2026-10-08 — ADR-0025 Amendment D 결정 바인딩)**: 제거 전제조건 충족 —
  P2-3(a) manifest 앵커링 착지(2026-10-07, `docs/spec/ci_optimization_tcb_judgments.md`
  §3.3 구현 상태 + `tools/ci/tcb_judgments.nim` CIRCULAR 판정 소멸), 본 기록이 그
  "별도 결정 바인딩"이다. 게이트는 삭제가 아니라 **재범위화**된다: 기준을
  freshness(ahead invariant — "not landable as tested")에서 **executed-subject
  identity**(merge_group: build_sha == run.head_sha / pull_request: run.head_sha ∈
  parents(build_sha))로 이전 — 최신성·착지 가능성 판정은 전량 GitHub ruleset/merge
  queue 권한으로 위임(권한 경계 정상화; 선례: `merge_cli.nim` "PROVENANCE only, not a
  freshness decision"). 크로스-트리 오염 방어(트리 OID content-addressing + run object
  앵커 + per-file sha256 + 소비자 P2-3(a) 재유도·provenance probe)는 전부 유지.
  레시피/script 키 바이트 동일성은 checkout을 build_sha 트리로 전환해 보장(종전은
  트리 등식이 암묵 보장). ahead-invariant 분류 = **해소** — §5.1 #4(사이클 내 2회째
  콜드) 원인 제거. 잔여 R5(교차 타이밍)·R9(c)(a_fp 이미지 롤)는 불변.

- **R11 — orphan 시드의 bounded quota 낭비 (2026-10-08 추가 — acceptance memo §5
  Follow-up #3 폐쇄 대응 · 2026-10-08 Red Team 교차 확인 교정)**: merge-queue
  speculative stacking(Q2, `docs/spec/gh_run_observation_quirks.md`)으로 생성된
  미소비 b-시드가 소비자 부재 상태로 저장소 총량을 점유한다. 실측(2026-10-08T15:09Z,
  `gh cache list` + REST 읽기 전용): 총 130엔트리 / 10,504,847,430바이트(구성 상한
  실측 `max_cache_size_gb=10`), last_accessed == created(무접근) 19엔트리 /
  4,289,768,783바이트 — 알려진 orphan `0de7eb78`(51,215,698B, PR
  #598)·`7a49353e`(51,323,577B, PR #603) 포함. 성질: **bounded — 두 상한의 합으로만
  서술한다**: (1) 무소비 7일 제거("GitHub will remove any cache entries that have
  not been accessed in over 7 days") ∧ (2) 용량 상한(기본 10GB — 초과 시 "will save
  the new cache but will begin evicting caches until the total size is less than
  the repository limit", LRU by last-access). **제거 시점·즉시성 SLA는 플랫폼이
  보장하지 않는다**(R12) — bounded는 "언젠가 반드시 회수되는 상한"이지 "즉시 회수"
  가 아니다. 엔트리별 TTL 네이티브 지원 부재(actions/cache 전체 입력·REST
  엔드포인트 세트에 만료 파라미터 없음). 보충: quota 초과는 **저장 실패를 유발하지
  않는다**(위 원문 — save 후 evict); 저장 실패 모드는 rate-limit(200
  uploads/min)·low-trust read-only·budget뿐이며 publisher는 전부
  `continue-on-error` + `[publish-fail] J3 fail-open` 정직화 로그
  (`ci-cache-publisher.yml:245,641,647`)로 방어된다. **보안 경계**: 본 위임은
  cache-poisoning 방어를 대체하지 않는다 — **LRU는 오염 방어가 아니다**(마지막
  접근 순 정리일 뿐); 오염 방어는 기존 R3(cache-mode: write 옵트인 경고 + 트리 OID
  content-addressing)와 J3 §3.3 semantic provenance probe
  (`ci_optimization_tcb_judgments.md:181`)가 흡수한다. 실측 소비 주기 2분 20초
  (acceptance memo §2.1 — 시드 10:20:04 → mg 소비 10:22:24)는 7일 창의 약
  1/4,320이다. ∧ **fail-closed**(J3 — 캐시는 가속일 뿐 증거 아님: 판정 입력 0,
  정확성 무관). **accepted residual** — 시딩 억제(eligibility 판정의 캐시 계층
  재도입)·자체 만료(플랫폼 eviction 재구현)는 모두 권위 누수로 **금지**; 위임 판정
  전문: `docs/evidence/orphan_seed_quota_delegation_2026-10-08.md`.
- **R12 — eviction 시간표 비보장 (2026-10-08 추가 — Red Team 교차 확인)**: 공식
  문서는 회수 조건(7일 미접근 · 총량 초과 LRU)만 문장으로 정의하고 **제거 시점·
  즉시성을 보장하지 않는다** — eviction은 저장 트리거 시점 집행이므로 상한 근처의
  총량이 스냅샷에 상주할 수 있다(실측: 10,504,847,430바이트 상주 vs
  `max_cache_size_gb=10`). "orphan이 사라졌다" 관측은 플랫폼 판정이며 Axiom은 그
  시점을 예약·단정할 수 없다 — 시점 단정이 필요한 소비 판단이 생기면 그것은 R11
  금지(시딩 억제)로의 회귀다.
- **R13 — 관리자 설정 변동 (2026-10-08 추가 — Red Team 교차 확인)**: 캡 증액
  (storage-limit API — 기본 10GB는 "increased by enterprise owners, organization
  owners, or repository administrators")·retention-limit API 등 캐시 정책 설정은
  관리자 권한으로 변동 가능하며 **Axiom 통제 밖**이다(R2의 캐시 정책판 — 설정은
  언제든 다시 꺼질 수 있다). 캡 증액 시 용량 상한의 회수 기여가 약화되어 **시간
  상한(7일)만 잔존**한다 — bounded 상한이 2개에서 1개로 줄 뿐 소멸하지는 않는다.
  탐지는 운영 감사(storage-limit/retention-limit API 실측)로만 가능하다.
- **R14 — `gh-readonly-queue/*` 브랜치 캐시 스코프의 공식 명시 부재 (2026-10-08
  추가 — Red Team 교차 확인)**: 공식 문서의 캐시 접근 범위 규칙은 현재
  브랜치·기본 브랜치·PR(base/merge-ref)만 문장으로 정의하며 merge-queue 브랜치
  (`gh-readonly-queue/main/pr-N-…`) 스코프의 기록·복원 규칙은 **명시 문장이
  없다** — 본 저장소 실측으로 해당 스코프 캐시의 존재만 확인된 상태
  (`docs/evidence/orphan_seed_quota_delegation_2026-10-08.md` §2.1). 미정의
  표면에서의 소비 성립 여부는 플랫폼 변경에 노출된 가속 전용 사실(J3)로만 취급한다.

## 3. 실패 모드 — Phase 0 linchpin

`workflow_run`이 org required workflow(`.github/workflows/admission-gate.yml`) 완료에
발화하지 않으면(E7 실증 판정) publisher는 `runner-pool-acceptance.yml`의 push@main
재발행 잡으로 회귀한다 — **컴파일 0의 초 단위 I/O**이므로 계산 중복 0은 유지되나 머지
워크플로 실행 0은 달성 불가(플랫폼 제약). 회귀 결정 권한: ADR-0025 Amendment B §4.

## 4. 운영 실증 (2026-09-29 — 실제 운영 상태 관측)

| 증거 | 판정 | 관측 |
|---|---|---|
| E1 머지 실행 0 | PASS | PR #348 merge `7ccd62389` (03:08Z) 후 push@main 신규 run 0건 (최신 push run = 직전 머지 02:55Z) |
| E2 퍼블리셔 발행 | PASS | run 36515773996 전 스텝 success — guard(orchestrator path/fork/artifact) → Git Data API 트리 등식 → cross-run 다운로드 → manifest sha256 → keygen-only → `Cache saved with key: axiom-b-4f5a75f7…` (tree-OID 단위) |
| E6 트리 등식 | PASS | `tree(7ccd62389) = 4f5a75f7eb94638319f9f4007e5cf582a1926dbf` == publisher `b-identity` 완전 일치 (testedTree == mergeTree 실측) |
| Phase 0 E7 | CONFIRMED | linchpin: 게이트 run 완료 → `workflow_run` 발화 (probe run 36510136328); cache-mode: write 수용 |
| E-CANARY callee 핀 상승 | (본 PR의 게이트 런에서 관측) | callee 핀 `9021a9a0` → `2b0663492`(#353/#354) 활성화(org PR #30 + org ruleset 24041674 재핀 `45527f13`) 후 **첫 pull_request 런** — 새 callee(merge_group 바인딩 + α subject (B, G^2))의 PR 경로 byte 등가 + candidate-key 아티팩트 정합 + TWS/pin 3-way가 본 PR의 `admission-check`·`trusted-writer-set-pairing` GREEN으로 실증된다 (§2.5 Short Validation) |

E3(수용 PR의 `b-cache-hit`)은 본 PR의 게이트 런에서 관측 — 본 문서가 그 증거 기록의
수용자이자 산출물이다.
