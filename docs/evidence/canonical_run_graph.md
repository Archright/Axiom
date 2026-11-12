# Canonical Run Graph — CI/merge Authority Census (P0)

> P0 deliverable (CI-pareto). 선행 조사(서브에이전트 리포트 + Owner 검증)의 FACT를
> 스폿 검증 후 문서화한 권위 센서스. 본 문서는 **권위(누가 무엇을 생산/소비하는가)의
> 문서화**이며 §2.2 작업 범위(CI 최적화)의 근거 — **머지 판정 의미론은 변경하지 않는다**
> (아래 §E).
> 모든 file:line은 2026-09-25 working tree 기준. `UNKNOWN` 표기 = 판정 보류/미확인.

## A. Canonical run graph (trigger → workflow → job → evidence → authority consumer)

레전드: 각 엣지는 `AUTHORITATIVE`(머지 허용 판정에 직접 기여) /
`OBSERVATIONAL`(머지 권위 변화 없음) / `DEAD`(배선 없음).

> **ADR-0027 (2026-09-29)**: 아티팩트·웹후크 키 명명 `admission-check-{PR}`은
> ADR-0027 P2에 따라 `admission-check-<candidate head>-<run_attempt>`(아티팩트
> identity = candidate identity + attempt binding)로 개정된다 — 기존 {PR}
> 계약은 명시 개정으로 de-contractualize하며, 본 그래프는 그 계약 상태를
> 반영한다. (P2 개정 2026-10-04: 초판의 attempt 미포함 명명은 debt464 §9(ii)
> trusted-name 계층을 무력화 — suffix는 identity 성분.)

```text
[PR push/retrigger]
  └─▶ pull_request(main) — admission-check (AUTHORITATIVE, required check)
        ├─ job build-base-artifacts (B-built verifier — Gate A)
        │    └─ evidence: base-built bin/ax + install_ax_cas + ircheck +
        │                 manifest.txt(recipe_id, build_sha=B)
        │                 (admission-check.yml:89-177, checkout B :100-104)
        ├─ job admission-check (B-built executor만 실행, H = _candidate/ data-only)
        │    ├─ Lake build smoke (fail-closed)                 :114-131
        │    ├─ artifact manifest 검증 (build_sha==B)          :229-248
        │    ├─ cert subject-register (로컬, 무 network)        :373-399
        │    ├─ cert attest --witness-only → witness.json+
        │    │    witness.sha256 (kernel chain a-f, H-derived
        │    │    data, B-built ax)                             :413-439
        │    ├─ D6 ledger-list (파일: 449-461)                  :449-461
        │    ├─ scope+baseline integrity (B-built)              :468-477
        │    ├─ ax merge --dry-run → admission-verdict.log
        │    │    + gate_history.jsonl tail (OBSERVATION 기록 —
        │    │    admission claim 아님)                         :489-506
        │    └─ upload admission-check-{candidate head}-{run_attempt} artifact
        │         (witness + verdict observation) — ADR-0027 P2 개정
        │         (2026-10-04): 아티팩트 identity = candidate identity
        │         + attempt binding; 기존 {PR} 계약은 명시 개정으로
        │         de-contractualize                              :508-519
        └─ checks API POST "landing-trigger" Check Run (external_id
             admission-check-{candidate head} — App webhook contract
             key; ADR-0027 P2 개정 — 기존 {PR} 키 명시 개정)      :537-566
             → 소비: out-of-repo Landing App glue (webhook bridge)
                  → landing_cli.nim (landing_cli.nim:37-44; bridge 상태
                  = config/app_landing_binding.json:8 PENDING — §D2)
             └─▶ certificate-mint (workflow_run, completed)
                  [AUTHORITATIVE — sole ledger writer]
                    ├─ activation guard (event/conclusion/path) :107-117
                    ├─ checkout B + TrustedWriterSet@B + workflow
                    │    blob@B + PR identity (B/H/base.ref)     :217-325
                    ├─ make ci-bootstrap (B에서 재빌드)          :227-231
                    ├─ artifact retrieval (run-scoped, 이름,
                    │    witness sha, provenance (iv))           :341-392
                    ├─ re-verify witness + attest --sign
                    │    (B-built ax; certificate (B,H) 검증)    :404-429
                    ├─ D6 ledger-list 발행 차단 (fail-closed)    :436-451
                    └─ ax cert ledger-append (FF-CAS → axiom/
                         certificates side-ref + provenance
                         commit metadata)                        :460-475
                  └─▶ evidence: certificate(B,H) in cert ledger
                       └─ 소비: Landing CAS — src/cli/landing_cli.nim
                            certificates Ed25519 검증 → CreateCommit
                            → updateRefs(refs/heads/main,
                              beforeOid=B, afterOid=M, no force)
                            (landing_cli.nim:15-35; cert verify 참조
                            :19-21, step 3-4 :26-30, step 5 :31-32)
                             └─▶ main = M (state transition)
```

두 번째 경로 (OBSERVATIONAL/DEAD):

```text
[PR push] ─▶ repository-surface (pull_request, main) — OBSERVATIONAL
              (헤더 "required check 아님; merge authority 변경 없음"
               repository_surface.yml:1-8; 판정은 base policy 바인딩
               :55-56, :70-73) — 동일 ratchet을 로컬 pre-push가 강제
               (Makefile:356, :367-373 → push-admissibility :348-358)
[workflow_dispatch / workflow_call (release-ship L2 위임, ADR-0024)]
  └─▶ runner-pool-acceptance — OBSERVATIONAL (요청·디스패치 발화 — 착지 후 자동 발화 없음)
        ├─ select (GitHub-hosted control plane, mode 판정)      :59-60
        ├─ gateway-shard ×8 (Lake smoke :220-238; ci-compile
        │   :240-242; ci-bootstrap-cheap :416-422; partition audit
        │   union==86 /*testcase 이름 집합*/ :424-425;
        │   gateway 실행 :427-429; executed record+upload :435-453)
        ├─ gateway-identity-gate (union==86, 쌍별 배타 — fail-closed,
        │   junit 집합 검증)                                    :489-507
        └─ proof-reconcile (Decision Record ↔ executed 재확인)   :509-514+
[DEAD — 배선 없음]
  * tools/ci_shadow_runner.sh           — 참조 없음 (자기 자신만; 본문 :2,13)
  * tools/nightly_runner.nim CI hook   — "CI (gate-nightly)" 문구(dangling:
    Makefile에 gate-nightly 타겟 없음) (nightly_runner.nim:3-6;
    실존 타겟 = 로컬 make nightly, Makefile:946-947)
  * tools/ci/local_ci_gates.nim        — 로컬 진단 CLI (본문 :1;
    docs/design/p0_recovery_plan.md:7; CI 어디에서도 참조 없음)
```

> **push@main 트리거 폐기 (2026-09-29)**: 위 두 번째 경로의 push@main 발화는
> ADR-0025 Amendment B + PR #348(`7ccd62389`)로 **제거** — main 착지 = 순수 GitHub
> 네이티브 ref 이동, 머지 이벤트의 Actions 실행 = 0 (실증: `docs/spec/
> github_delegation_residuals.md` §4 E1 — PR #348 머지(03:08Z) 후 push@main 신규
> run 0건). B-캐시 씨딩은 `workflow_run` 트리거의 `ci-cache-publisher`로
> 이관(단일 씨딩 writer — ADR-0025 Amendment B §2); 남는 발화 =
> `workflow_dispatch`(수동) · `workflow_call`(release-ship L2 위임, ADR-0024) —
> 착지 후 자동 발화는 없다.

## B. TCB component set

| 컴포넌트 | 역할 | 근거 |
|---|---|---|
| GitHub merge enforcement (required checks / ruleset) | 플랫폼 차원의 required-check·branch 보호: main ruleset(id=20303214)의 요구 체크 = `admission-check`(권위 workflow와 일치, 유령 체크 제거 확인 2026-09-25) + cross-repo required workflow `landing-integrity`(Archright/.github 소유, §D1) — 사람 native merge 경로 | gh api rulesets 실측 2026-09-25; ghec_ruleset_p1c_bypass_2026-09-24.md:66-69 (이력) |
| Landing CAS (landing_cli.nim updateRefs) | 상태 전이 유일 액추에이터 — beforeOid=B → afterOid=M, no force. 생성/소비 트리 소유권 격리(인용 :7-17) | landing_cli.nim:15-35; ghec_ruleset §7.3-7.4 |
| Certificate ledger (axiom/certificates side-ref) | cert(B,H) FF-CAS ledger = admission evidence(소비) | certificate-mint.yml:460-475; landing_cli.nim:19-21 |
| Admission evaluator (MergeAdmissible) | 순수 판정 함수(Pass 2.5/2.6 = BINDING_MISMATCH, 2.96 = NO_CERT, fail-closed) | merge_cli.nim:282; :360-380, :424-438 |
| Ephemeral execution isolation (ADR-0023 A2 platform contract) | 1 VM=1 job, 잡 격리 신규 VM, 제공자만 GHEC 전환 — 신뢰 규칙 불변 | docs/adr/0023-…:344-364 (A2; :356-361) |
| actions/cache transport + exact-key semantics | B-layer 캐시 전달(가속 — evidence 아님 주석); exact-key 바인딩 | admission-check.yml:106-109, :199-202; certificate-mint.yml:222-225; runner-pool-acceptance.yml:207-211 |

## C. Duplicate candidates (D1..D9) — P0: 식별만, 판정은 P3

| # | 중복 연산 (file:line) | 같은 연산? | 같은 증거? | 같은 권위 소비자? | 제거 시 신뢰 의무? | 판정 |
|---|---|---|---|---|---|---|
| D1 | admission `make ci-bootstrap` (:136-151, `:139`) vs mint `make ci-bootstrap` (:227-231) — 동일 B | O | O (동일 B, 동일 레시피 — 별개 아티팩트) | O (둘 다 Gate A 검증 경로의 bin/ax) | **해소** — C5/C1 계약 개정 (epoch N+5, 2026-09-29, 승격 PR 동반): mint prepare 자체빌드 폐기 → admission lane build-base-artifacts(B-결속 바이트, build_sha==B + per-file sha256) 소비. single build site 1개; [X]1~5 검증 경로 불변 (ADR-0026 §3 개정문) | resolved (N+5) |
| D2 | admission `attest --witness-only` (:413-439) vs mint re-verify + `attest --sign` (:404-429) | O | O (동일 witness 커널 체인) | O (cert 증명체인) | X — **의도된 재검증**(권위 레이어 격리의 핵심. 제거 = TrustedWriterSet 의미 붕괴) | pending (제거 권장 안 함) |
| D3 | D6 ledger-list 2회: admission :449-461 (idempotency) vs mint :436-451 (발행 차단) | X | X | X | X (admission 쪽은 재실행 안전성; mint 쪽이 발행 차단) | pending |
| D4 | `ax merge --dry-run`(admission :489-506) vs `--apply`/`ax landing` (사후) | X | X | X (dry-run = 관측 기록) | X — stale-eval guard(merge_cli.nim:1437-1443)는 apply/landing 경로에만 의미 | pending |
| D5 | Lake smoke: admission :114-131 vs runner-pool :220-238 — 동일 코드 복붙 | O | O | X (admission은 Gate A 검증 경로, runner-pool은 착지 후 스모크) | O (admission 쪽만 권위 검증 경로 — 합병 시 smoke 위치 변경 불가) | pending |
| D6 | `ci-bootstrap-cheap` 시퀀스: admission :468-477 vs runner-pool :416-422 | O (동일 시퀀스 주석 :463-467) | O | X (admission = 검증 경로, runner-pool = 착지 후) | O | pending |
| D7 | repository-surface ratchet: 원격 workflow (:55-73) vs 로컬 pre-push (Makefile:356, :367-373) | O (동일 base-policy × diff 판정) | O | X (원격 = 관측, 로컬 = 강제의 유일 기계 경계) | O (로컬 유지 필수) | pending |
| D8 | gateway 86-test suite: v*/full mode vs push@main selected subset (runner-pool :25-30, :309, :424-425) — 인접 커밋 연속 full 실행이 같은 집합 재계산 | O | O | X (각각 독립 계약 — tag = full, push@main = select 판정) | O | pending |
| D9 | `attest --witness-only`(admission) vs `attest --sign`(mint) — 동일 B-built 커널 체인 | O | O | O (cert (B,H) 증명체인) | X — **D2와 동일한 의도ed 재검증** — 레이어 격리 필수 요소 | pending (제거 권장 안 함) |

- D1 danger flag: mint B-빌드 제거 시 **증거 등가(end-to-end)**가 깨지면 안 됨 —
  아티팩트 프로비넌스(manifest, build_sha==B) + TrustedWriterSet(단일 라이터) 무결성을
  유지해야 P3 판정 가능. 근거: admission-check.yml:136-151, :229-248;
  certificate-mint.yml:227-231, :259-325; config/trusted_writer_set.json
  (ghec_ruleset_p1c_bypass_2026-09-24.md:90-92).

## D. UNKNOWN adjudication

**적용 규칙**: `UNKNOWN → 실제 상태 전이(state transition)에 영향? YES → P0 blocker
(진행 전 해결 필수) / NO → observational 또는 out-of-scope (근거 기록)`.

### D1. Ghost required check (production main ruleset id=20303214) — **LIVE 실측으로 해소 (2026-09-25)**

- **최초 발견**: `required_status_checks("ci/circleci: verify-static", integration_id 302869)`
  더는 존재하지 않는 CircleCI 유령 체크. 근거: ghec_ruleset_p1c_bypass_2026-09-24.md §4
  (:57-69 no-op probe 차단 실측, ruleset 생성 2026-08-03, bypass_actors []).
- **LIVE 갱신 (2026-09-25, `gh api repos/Archright/Axiom/rulesets/20303214` 실측)**:
  - `required_status_checks = [{context: "admission-check", integration_id: 15368}]`
    (= GitHub Actions) — **유령 CircleCI 체크는 제거됨**. ruleset `updated_at
    2026-09-24T23:20:45+09:00`.
  - 현재 요구 체크 `admission-check` = 권위 증거 생산자 workflow와 **정확히 일치**
    (admission-check.yml, job `admission-check`) — GitHub-native merge enforcement가
    권위 그래프와 정렬됨.
  - `bypass_actors = []` (App bypass 없음), rules: deletion / non_fast_forward /
    pull_request / required_status_checks.
  - **실증**: ruleset 갱신 후 2026-09-25에 PR #231, #232, #233 **3건 성공 병합**
    (`Merge pull request #23x` — native merge 경로 관측) → human native merge 경로의
    유령 체크 차단은 **종료**.
- **판정 갱신**: `실제 state transition에 영향?` → **NO (차단 해소 확인)** —
  최초 P0 blocker 판정은 09-24 기록에 근거한 것이었고, 09-25 live 실측으로 해소.
  잔여 위험: ruleset은 여전히 bypass 없음 → App CAS 경로가 ruleset enforcement를
  받는지 여부는 App 통과 실측으로만 확인 가능 (P6 acceptance에서 확인).
- **신규 발견 → 정정 (2026-09-25): `landing-integrity` ruleset(id=23943917)은
  cross-repo required workflow, 파일 부재 아님**
  - ruleset `workflows` 규칙: `Archright/.github(repository_id 1182157951)@main`의
    `.github/workflows/landing-integrity.yml` — **조직 `.github` 저장소에 파일 존재**
    (sha 8c016c8e, 12,333 bytes, gh api contents 실측). Archright/Axiom(id `<legacy-repo>`)
    로컬 트리에 없는 이유 = GitHub **required workflows** 기능으로 조직 저장소의
    워크플로를 본 repo PR에 강제 실행하기 때문.
  - **실제 실행·성공 실측**: run 36088742926 등 (pull_request, 2026-09-24~25 다수),
    4 job `merge-admission-sanity` / `trusted-writer-set-pairing` /
    `trust-surface-codeowners` / `landing-trigger` 전부 success — PR #231–#233 병합과 병존.
  - 판정 규칙 적용: `state transition 영향?` → **YES**(ruleset이 요구하는 병합 게이트
    구성요소) **단 현재 정상 실행 → non-blocking**. 즉 "지연 함정"이 아니라 **권위
    경계의 정상 구성요소** — TCB의 GitHub merge enforcement 항목이 커버 (B섹션).
  - 모니터링: 워크플로가 조직 저장소 소유이므로 변경 시 본 repo 병합 게이트가 바뀜
    (cross-repo drift) → D3에 모니터링 항목으로 기록.

### D2. out-of-repo webhook bridge (landing-trigger Check Run → App glue)

- 상태: `config/app_landing_binding.json:8` `"webhook_secret_ref": "PENDING"`
  (주석 :11-13 "fill with the secret-name reference used by the out-of-repo webhook
  bridge (never the secret value)"). landing_cli.nim:76, :134에서 파싱.
- bridge 소비자/계약: Check Run POST(admission-check.yml:537-566) → App `check_run`
  webhook(completed) → App glue가 `ax landing` 인보크 (landing_cli.nim:37-44 "webhook
  bridge = deployment checklist item, NOT part of this repo").
- 판정: **YES → cert 생성 권한 → merge 흐름 결정**(값 PENDING이면 현 배포에서 App
  webhook 발화가 비활성). 단 bridge 자체는 out-of-repo 조항(:41-42) → **저장소 내에서
  해결 불가, Owner/배포 소유** → **P0 blocker로 표기하되 진행 차단은 배포 소유 경로에
  한정**. 근거: app_landing_binding.json:8, :11-13; landing_cli.nim:37-44, :76, :134.

### D3. 기타 UNKNOWN (판정 보류 — pending으로만 기록)

| UNKNOWN | 근거 | 상태 |
|---|---|---|
| cert-level cross-arch 정책 (ADR 없음) | repo에 `cross-arch` 문구 없음(2026-09-25 Grep) — 관련 ADR 미존재 | pending |
| W9 lake build duration NaN | 작업 정의 FACT (기록) — 실측 파일 미확인 | pending |
| 현재 live wall-clock / cache-hit 미측정 | 작업 정의 FACT (기록) — 실측 기록 없음 | pending |
| `docs/spec/self_hosted_ci_migration.md` 없음 | AGENTS.md:334 링크 존재(파일 부재) — 깨진 참조 | pending |
| `landing-integrity` ruleset(id=23943917) = cross-repo required workflow (`Archright/.github` 소유) | gh api 실측 2026-09-25: 조직 저장소에 파일 존재·4 job 정상 실행·PR #231–#233 병합 병존 → 현재 non-blocking. **변경 시 병합 게이트가 바뀌는 cross-repo drift 주의** | pending (모니터링) |

## E. Explicit note

> **Census is documentation of authority; it does not change merge judgment
> semantics (§2.2 scope: authorization unchanged).** 본 문서는 CI 최적화(P3) 판단의
> 근거 자료이며, RequiredChecks/RequiredWorkflowIds/CertRequired
> (merge_cli.nim:58-79) 또는 허용/차단 판정 로직을 변경하지 않는다.

## H. Epoch N+5 acceptance — SL-04 certificate validity (fresh-B vehicle)

> Vehicle PR (docs-only, fresh B = N+5 main merge sha) — org gate run 측정 템플릿.
> 실측 완료 후 이 섹션을 갱신한다 (N+4 §G 패턴; §G는 N+4 vehicle PR #328 소관).

- run id: **36458519698** (1차 — K 재핀 전: mint-prepare@badbf620c 구엔진, C5 미발화) + **TBD** (2차 — K 재핀 후: mint-prepare@6edfd7a50 C5 LIVE) — wall-clock **TBD**
- **1차 실측 (36458519698, 17:29:47Z→17:39:03Z, wall 9m16s)**: J = admission callee 2 job
  (build-base-artifacts 3m28s + admission-check 1m58s) + mint-prepare prepare 3m21s +
  **mint-publish publish 8s FAILURE** + verdict failure — 구 엔진 job 0건.
  `[slice-engine] epoch=N+5 implemented=["SL-08","SL-01","SL-03","SL-04","SL-12"]
  sl04=fire sl0713=NO-FIRE` (publish) — 게이트 정상 발화 실측. (P0) skipped (sl0713
  NO-FIRE ✓) · (P1) `MINT_PUB_ART: OK — [X]1` ✓ · (P2) `MINT_PUB_DIGEST: OK — [X]2` ✓
  · **(P3) FAIL: `cp: cannot create regular file .../bin/ax: No such file or
  directory`** — publish job은 checkout이 없어 `$GITHUB_WORKSPACE/bin/` 부재 (N+4
  prepare (5) ENOENT와 동일 클래스의 선존 결함, K 최초 발화로 표면화) → (P4)~(P7) skip
  cascade → verdict red.
- **1차 prepare는 구엔진(badbf620c)**: K mint-prepare 래퍼가 N+4 sha 고정 — C5 소비
  경로 미발화 확인. K 재핀 PR(#20) 후 2차 런에서 C5 실발화 측정.
- **2차 실측 (36460660854, 17:47:44Z→17:52:45Z, wall ~5m01s, K 재핀 후 — C5 LIVE)**:
  admission callee 2 job pass (3m32s + 1m1s) + **mint-prepare prepare 18s FAILURE** +
  mint-publish skipped → verdict red. prepare 스텝: (0)~(3b) 전부 OK → **(6)
  `[mint] Consume admission B-built bin/ax` SUCCESS — `MINT_BASEART: OK — admission
  B-built bin/ax consumed (id=10988191168, build_sha==B, per-file sha256 pinned)`
  (C5 소비 경로 실발화 ✓)** → **(4) FAIL: `attest --sign` witness 거부**.
- **2차 (4) 실패 근인 (소스 실측)**: `attest --sign` stage-(b) 추출 합의가
  `runReferenceExtractorOnWire`로 **ircheck 참조 추출기 실행을 요구**
  (extraction_agreement.nim:176-180 — worker = `<root>/proofs/.lake/build/bin/ircheck`).
  C5 consume이 bin/ax만 설치 (ircheck 미소비) → worker 부재(exitCode -2) →
  extraction agreement FAIL → witness rejected (fail-closed). 구 엔진 자체빌드는
  ircheck를 함께 생산 — **C5 개정의 소비 범위 누락 = 개정 결함** (admission lane의
  artifact에는 ircheck 포함 — admission-check.yml:262-264; manifest 전량 sha256
  검증은 통과, 배치만 누락).
- **1·2차 공통 — publish P3 선존 결함**: `cp ... "$GITHUB_WORKSPACE/bin/ax"` —
  checkout 없는 publish job의 workspace `bin/` 부재 (N+4 prepare (5) ENOENT와 동일
  클래스 #300/#310 선례). P3는 SL-04 미배정 스텝.
- **블로커 (G2b 실측)**: 두 수정 모두 certificate-mint.yml 변경 —
  `epoch_transaction_gate --diff origin/main HEAD` EXIT 1 (`changed outside
  promotion scope` — fix-only PR 실측 neg-n5-fixonly). 승격 없는 엔진 수정은 착지
  불가: C5 ircheck 소비 수정 + P3 mkdir은 SL-0713 승격 동반 또는 게이트 개정
  (아키텍트) 필요.
- **복구 A (K 롤백, 2026-09-29)**: org ruleset 24041674 sha → `d305de4f` (K = N+4
  shape 재복원, mint-prepare@badbf620c · mint-publish 래퍼 제거 · verdict
  [admission, mint-prepare]) — repo 병합 차단 해소 런을 아래에 실측. N+5는 미완·
  전이 상태 (SL-04 implemented — 복구 E의 publish 재발화 전까지 publish 미실행).
- verdict: **1·2차 모두 red** (1차: publish P3 ENOENT → 2차: prepare (4) ircheck
  부재) — **K 재핀 후 repo 병합 차단 상태** (모든 PR의 mint-prepare가 N+5 엔진으로
  (4) 실패 → verdict fail-closed — 최우선 블로커).
- J 집합: **K DAG — admission callee 2 job + mint-prepare callee job(publish skip) +
  mint-publish callee job(prepare skip) + verdict** — **구 엔진 job 0건**
  (closure-deriver / gateway / tree-identity 전무)
- admission callee slice-engine 로그: **TBD** (기대: `epoch=N+5
  implemented=["SL-08","SL-01","SL-03","SL-04","SL-12"] sl08=fire sl01=fire
  sl02=NO-FIRE sl03=fire sl05=NO-FIRE`)
- mint callee prepare slice-engine: **TBD** (기대: `epoch=N+5 ... sl12=fire`)
- mint callee publish slice-engine: **TBD** (기대: `epoch=N+5 ... sl04=fire
  sl0713=NO-FIRE`)
- prepare semantic 실발화: (0) activation · (1) B/H 유도 · **[mint] Consume
  admission B-built bin/ax (C5 개정 — build_sha==B + per-file sha256 pin
  MINT_BASEART: OK)** · (4) witness 검증+서명 · (5) cert artifact + bin/ax
  staging · (5b) subject-certificate upload — **TBD**
- publish semantic 실발화: (P1) `MINT_PUB_ART: OK — artifact identity [X]1` ·
  (P2) `MINT_PUB_DIGEST: OK — file digest [X]2` · (P3) `MINT_PUB_AX: OK` ·
  (P4) `MINT_PUB_BIND: OK — field binding [X]3` — **TBD**; (P0)/(P5)/(P6)/(P7)
  **skipped** (scope_sl0713 NO-FIRE 실측)
- **✅ 최종 acceptance PASS (run 36475587814, fresh B = 7c6d3e48b, K @92f02510 —
  wall 8m17s: 19:55:31Z → 20:03:48Z)**: J = admission callee 2 job
  (build-base-artifacts 4m12s + admission-check 1m46s) + mint-prepare prepare
  58s + **mint-publish publish 58s** + verdict 4s — 구 엔진 job 0건 (전 job
  success, mint-publish/prepare·mint-prepare/publish는 stage guard skip)
- slice-engine 실발화: prepare `epoch=N+5 implemented=[...SL-04...] sl12=fire` ·
  publish `... sl04=fire sl0713=NO-FIRE`
- **C5 소비 경로 (prepare)**: `MINT_BASEART: OK — admission B-built bin/ax +
  ircheck consumed (id=10993567299, build_sha==B, per-file sha256 pinned)` →
  `MINT_VERIFY: OK — witness verified + normalized; certificate binds (B, H) +
  certTree` (attest --sign PASS — ircheck·libpcre3 패리티 실증) → `MINT_CERTART:
  OK` → `Artifact subject-certificate-1 uploaded (ID 10993567299)`
- **[X] 실발화 (publish)**: (P0) skipped · (P1) `MINT_PUB_ART: OK — [X]1` ·
  (P2) `MINT_PUB_DIGEST: OK — file digest [X]2; build_sha==B` · (P3)
  `MINT_PUB_AX: OK — B-built bin/ax pinned (build_sha==B, sha256==manifest)` ·
  (P4) `MINT_PUB_BIND: OK — field binding [X]3; (a) run head_sha==H==cert.headSha`
  · (P5)/(P6)/(P7) **skipped** (sl0713 NO-FIRE 실측)
- verdict: `[verdict] OK — admission ∧ mint-prepare ∧ mint-publish callee
  succeeded` → required check `admission-check` **green** (strict) — **N+5
  SL-04 certificate validity acceptance PASS**
- K 불변: org admission-gate blob @main==@K (ruleset 24041674 sha 이력: `3a9c11a` →
  `3a0c4e9c` (#20) → `d305de4f` (복구 A 롤백) → `7e091cd1` (복구 D forward) —
  enforcement active / bypass [] 전 구간 불변)
  재핀 — enforcement active / bypass [] 불변); repo required check 이름
  `admission-check` 불변

## I. Epoch N+6 acceptance — SL-10 gateway decision identity (fresh-B vehicle)

> Vehicle PR (docs-only, fresh B = N+6 main merge sha a927f907d) — org gate run 측정
> 템플릿. 실측 완료 후 이 섹션을 갱신한다 (N+5 §H 패턴; §I는 본 vehicle PR 소관).
> K = admission ∧ mint-prepare ∧ mint-publish ∧ gateway (4-needs verdict, org PR #26).

- run id: **36495330895** — wall-clock **7m41s** (22:57:03Z → 23:04:44Z, concurrency 해소 후 최종)
- **✅ acceptance PASS**: select `sl10=fire sl09=NO-FIRE` 결정론적 실발화 (B3
  해소 — #340/#341) + SL-09 귀속 잡 3종 **skip (미발화 — #342 scope_sl09
  게이트: gateway-shard ×8·gateway-identity-gate·proof-reconcile 전부
  SKIPPED, 가동 job 없음)** — I-3 보완 실증
- **J 집합 (K DAG 8 job + verdict)**: admission callee 2 job (build-base-artifacts +
  admission-check) + mint-prepare callee prepare + mint-publish callee publish +
  **gateway callee (select + gateway-identity-gate + proof-reconcile — docs-only Δ:
  mode/scope에 따라 ci-bootstrap·candidate-build-arm·gateway-shard×8 skip 또는 부분
  실행) + verdict** — 구 엔진 job 0건 (closure-deriver/tree-identity 전무)
- slice-engine 실발화: runner-pool select `epoch=N+6 implemented=["SL-08","SL-01",
  "SL-03","SL-04","SL-12","SL-10"] sl10=fire sl09=NO-FIRE` · admission `sl08=fire
  sl01=fire sl02=NO-FIRE sl03=fire sl05=NO-FIRE` (기존 행렬 유지) · mint prepare
  `sl12=fire` · mint publish `sl04=fire sl0713=NO-FIRE` (notYet NO-FIRE 유지)
- **SL-10 semantic 실발화**: (a) `TESTED-TREE: testedTreeDigest=f18783aed064...`
  + tested-tree-digest upload · (b) `Run selector` decision envelope:
  `mode=selected ciBootstrap=true gatewayTestScope=ALL shards=[0..7]
  landingPolicyFloor=true` + decisionHash + ci-select-decision upload
  (`Plan status: VALID (certainty: CERTAIN)`) · (c) identity-gate/proof-reconcile은
  SL-09 귀속 — N+6에서는 scope_sl09 게이트로 **미발화 (skip)** — SL-09 승격 PR에서
  발화 복원 예정
- verdict: `[verdict] OK — admission ∧ mint-prepare ∧ mint-publish ∧ gateway callee
  succeeded` (RESULT_GATEWAY: success) → required check `admission-check` **green**
  (strict) — **N+6 SL-10 gateway decision identity acceptance PASS**
- J 집합 (K DAG 8 job + verdict): admission callee 2 (build-base-artifacts 4m8s +
  admission-check 1m12s) + mint-prepare prepare 1m1s + mint-publish publish 1m0s +
  gateway callee 3 (select 54s + ci-bootstrap 3m50s + candidate-build-arm 4m2s —
  shard 8-leg·identity-gate·proof-reconcile **skip**) + verdict 3s — 구 엔진 job
  0건 (closure-deriver/tree-identity 전무)
- K 불변: org admission-gate blob @main==@K — ruleset 24041674 sha 이력:
  `92f02510` (N+5) → `cd5aca0` (PR #26 — gateway 래퍼 4-needs) → `92f02510`
  (복구 롤백 — B3 해소 체인 중) → `3b93d11` (PR #27 — K forward 2 @c84b2cbb) →
  `cde1fcb` (PR #28 — K forward 3 @9021a9a0c, SL-09 게이트) — enforcement
  active / bypass [] 전 구간 불변; repo required check `admission-check` 불변

<!-- claim-proportional vehicle Δ (PR-C) — docs-only acceptance probe: select가
     mode=none을 B-전체트리 오라클 oracle-evidence(5축 deltaAbsent)로 정당화하는지
     관측하기 위한 단독 Δ. 2026-09-30. -->

<!-- claim-proportional vehicle Δ #2 (재관측) — callee pin 회전
     (.github #37 gateway@48cb16ab2) + ruleset 24233738(ref@main) 이후
     새 execution path의 실사용 확인용 단독 Δ. 2026-09-30. -->
