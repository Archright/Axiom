# ADR-0027: 후보 인증 위임 — GitHub Merge Queue

## Status

**PROPOSED (2026-09-29)** — GitHub Merge Queue 채택(계획: cert(G) 후보 인증 —
candidate-certification)의 Phase 0 ADR 기록이다. 본 ADR은 착지 authority의
**플랫폼 큐 위임**을 결정·기록하고, 그 확정 조건을 **Phase 0 측정(α/β)**에
결속한다. 측정 완료 전 "착지 형상 확정" 선언 금지 — 본문의 형상 서술은 전부
측정 의존 선언이다. **번호 정정 공지**: 계획 문서·`.github/workflows/admission-check.yml`
주석의 "ADR-0026" 지정(후보 인증 위임)은 `docs/adr/0026-execution-authority-unification.md`
(2026-09-27 착지, 실행 authority 단일화)가 선점하여 **본 ADR이 0027로 착지**한다 —
해당 참조의 정합 갱신은 후속 작업이다(본 ADR은 무수정 대상 파일을 건드리지 않는다).

## Context

- **결정 배경**: main 변경 정본 행위는 AGENTS.md:136의 "GitHub 네이티브 MERGE 커밋"
  단일 선언이며, GitHub가 이미 보장하는 권위(execution identity / freshness /
  approval / MERGE — ADR-0025 §2)를 Axiom이 중복 구현하지 않는다. 본 ADR은
  **후보 무결성 판정(candidate integrity verdict)**과 **착지(landing) 권위**를
  명시적으로 분리하고, 후자를 플랫폼 Merge Queue에 위임한다.
- **현행 플랫폼 실측 (2026-09-29)**:
  - main ruleset id=20303214: `target=branch`, 조건 = `~DEFAULT_BRANCH` 단독 —
    required check `admission-check`(integration 15368) 정확히 1개,
    `strict_required_status_checks_policy=true`, `allowed_merge_methods=["merge"]`,
    `bypass_actors=[]` (`gh api repos/Archright/Axiom/rulesets/20303214`).
  - 조직(org) ruleset id=24041674가 조직 게이트(admission-gate workflow_call@SHA)를
    고정한다(ADR-0025 §2·§5 — execution authority).
    > **갱신 노트 (2026-10-15 — 원문 보존)**: ruleset 24041674는 sha-bearing PUT 500
    > 사건(`docs/evidence/epoch_record_oracle_select_2026-09-30.md` §8.3) 이후
    > 24233738 `ref: main`(sha-less)으로 대체되어 소멸했다
    > (`docs/evidence/epoch_record_base_artifact_2026-10-01.md` §2.3). 현행 핀 모드와
    > 승격 절차의 정본은 [docs/spec/admission-generation.md](../spec/admission-generation.md)다.
  - push ruleset `execution-surface-create`(23967915): `.github/workflows/**/*`·
    `.github/actions/**/*` 경로 제한(bypass = OrganizationAdmin + Integration
    29110·4879411).
  - **probe 이력 실측**: `probe-merge-queue.yml`(4b56ad4fc에서 삭제)의 과거 11회
    런은 **전수 artifact-download 단계에서 실패**해 judge가 1회도 실행되지
    않았다(`PROBE_VERDICT` 부재 — 측정 0건). 측정 경로 자체가 미검증이었던 것이
    본 ADR의 Phase 0(측정)을 선행 조건으로 두는 직접 근거다.
  - **기존 artifact 명명 실측**: production artifact `admission-check-<PR 번호>`
    (예: `admission-check-308` — 2026-09-29 API 실측). P2는 이를
    candidate-head 기반으로 명시 개정한다.
- **supersession 대상 실측 (본 ADR이 폐기/개정하는 조항, 각 라인 검증됨)**:
  - `docs/spec/merge_admission_controller.md:31-33` — "Scope boundary" —
    "**native merge queue pole은 폐기**(never landed)"(:33).
  - `docs/spec/merge_admission_controller.md:195` — "백엔드 최종 형태(Owner 결정
    #11, 2026-09-24) ... **native merge queue pole은 폐기**".
  - `docs/spec/repository_surface_contract.md:144-160` — Owner 결정 #11 —
    "merge queue가 소거 대상이므로(본 결정)"(:147-148) + ":159-160 — Owner 결정
    #10이 등록한 측정 전용 merge-queue probe 워크플로는 merge-queue 소거를
    전제하므로 **retire를 승인**한다".
  - `docs/spec/repository_surface_contract.md:195-196` — Owner 결정 #13(2) —
    "merge authority는 현행 유지 — 로컬 게이트 + L2 + native MERGE. CI를 merge
    authority로 격상하지 않는다."
  - `docs/spec/certification_continuity_contract.md` §10.6 (:449-462) — Owner
    결정 #11에 따른 계약 개정문 — "merge queue 자체는 소거 대상이다"(:461) ·
    "**§8.2 `:274` 주석 supersede** — 'merge result 보장은 merge queue 외 불가'는
    CAS 랜딩 경로로 대체"(:458-460).
  - `docs/adr/0025-gateway-landing-authority.md` Amendment A(2026-09-28)
    불변식 4·6·7(:493, :495-496) — "strict freshness 하 verified_B ==
    current_main_tip" · "parents(M) = [B, H]" · "tree(M) == certTree".

## Decision

**Ultimate Purpose:**

> **certTree == mergeTree == landedTree.** Axiom = **후보 무결성 판정
> (candidate integrity verdict)**만 담당하고, 플랫폼(GitHub Merge Queue) =
> **큐잉·순서·후보 구성·착지**(queueing / ordering / candidate construction /
> landing)를 담당한다 — **권위 분할(authority split)**.

| 권위 | 소유 | 근거 |
|---|---|---|
| 후보 무결성 판정(candidate integrity verdict) | Axiom — `admission-check` verdict(단일 required check) | AGENTS.md:136 · ADR-0025 §1 M-B |
| 큐잉·순서(queueing / ordering) | GitHub Merge Queue(플랫폼) | 본 ADR |
| 후보 구성(candidate construction) | GitHub Merge Queue(temporary branch/merge group) | 본 ADR · merge_admission_controller.md §2b(구성자 = repository provider) |
| 착지(landing) | GitHub native MERGE — **큐 경유 포함** | AGENTS.md:136 · 본 ADR |
| execution identity / freshness | GitHub ruleset(required workflow @SHA · strict / 큐 무효화 의미론 — R2 문서화) | ADR-0025 §2 · 본 ADR P3 |

### Supersedes(정확 개정 대상 — 라인 단위)

1. **`docs/spec/merge_admission_controller.md:31-33, :195`** — "native merge queue
   pole은 폐기" 선언을 **폐기**한다: 네이티브 큐(Merge Queue)는 위임 대상이 된다.
   **커스텀 큐 금지는 유지**한다(§2b의 "Axiom이 `data/merge_queue/` 로컬 저널로
   queue semantics를 소유"하는 경로는 플랫폼 큐 채택 후 중복 authority —
   후속 단계에서 폐기/무효 서술 정리 대상).
2. **`docs/spec/repository_surface_contract.md:144-160`(Owner 결정 #11)** —
   "merge queue 소거 대상"(:147-148)을 **"위임 대상"**으로 개정하고, ":159-160
   probe retire 승인"을 갱신해 **probe 재도입을 허용**한다(측정 전용 —
   decision #10이 등록한 표면 경로 복원).
3. **`docs/spec/repository_surface_contract.md:195-196`(Owner 결정 #13(2))** —
   merge authority 집합(로컬 게이트 + L2 + native MERGE)에 **"플랫폼 큐 경유
   네이티브 MERGE"**를 추가한다. "CI를 merge authority로 격상하지 않는다"는
   불변 유지(플랫폼 큐의 착지는 CI 승격이 아니라 플랫폼 착지 경로).
4. **`docs/spec/certification_continuity_contract.md` §10.6(:449-462)** —
   **되돌림**: "merge queue 자체는 소거 대상"(:461)을 큐 위임 경로로 되돌리고,
   ":458-460 supersede"의 "CAS 랜딩 경로로 대체" 서술 중 merge-queue 저지
   부분을 해제한다. §2 "증명하는 것" 불변·INV-1/INV-8/INV-10/INV-12 불변 —
   착지 메커니즘 서술만 변경하며 인증 문장을 축소하지 않는다(§10.6 자체 규칙).
5. **`docs/adr/0025` Amendment A 불변식 4·6·7(:493, :495-496) 재서술** — 플랫폼
   큐 착지는 strict의 "base == verified_B" 의미론을 **큐 무효화 의미론**으로
   이동시키고(P3·R2), 착지 커밋의 parents 모양을 사전 고정할 수 없다:

   ```text
   [측정 의존 선언 — 필수]
   불변식 4 (freshness): strict freshness(verified_B == current_main_tip)는
     플랫폼 큐 경로에서 '큐 그룹 구성 시점 base + 큐의 무효화(stale group
     폐기)' 의미론으로 이동한다 — 정확한 fresh 정의는 Phase 0 측정 결과에
     결속되고, 측정(α/β/γ) 판정 후 확정한다.
   불변식 6 (parents): 'parents(M) = [B, H]'는 큐 경로에서 사전 선언하지
     않는다 — 착지 커밋의 parents 형상은 Phase 0 측정이 결정한다
     (α = parents(L)==[B, H_PR]; β = parent2(L)==G ∧ tree(L)==tree(G);
     γ = 그 외). γ 판정 시 즉시 STOP·재의결(본 ADR 확정 보류).
   불변식 7 (tree): 'tree(M) == certTree'는 유지하되, M이 큐 착지 커밋 L인
     경우 'tree(L) == tree(G) == certTree'의 성립 조건을 측정으로 확정한다.
   ```

   **착지 형태(parents(L)=[B,G] 류)를 사전 선언하는 문장은 본 ADR에 두지
   않는다** — 형상은 오직 Phase 0 측정(α/β/γ 판정)에 의해서만 확정된다.

### Policies adopted(다른 에이전트의 PR이 인용하는 정본 문구)

- **(P1)** merge_group에서는 PR 번호를 `head_ref`에서 파싱하지 않는다 — 공식
  페이로드 스키마가 head_ref 문자열 형식을 보장하지 않으므로 비계약이며,
  prNumber는 설계된 honest 값 **0**을 사용한다(`src/verification/
  verification_subject.nim` "0 = no PR context").
  - 인용 정정(검증 위치): "0 = no PR context" 문구의 정본 위치 =
    `src/verification/attestation_orchestrator.nim:155` · `src/verification/
    attestation_witness.nim:61`; `verification_subject.nim:159-160`은
    "prNumber must be non-negative (fail-closed)". `verification_subject.nim:57`
    — "bookkeeping only — NOT in identity wire"와 정합.
- **(P2)** artifact identity = candidate identity + attempt binding: 이름은
  `admission-check-<candidate head>-<run_attempt>`, candidate head 표현식
  `github.event.pull_request.head.sha || github.event.merge_group.head_sha ||
  github.sha`, mint의 want_name은 `inputs.headSha-<runAttempt>`로 미러 — 기존
  `admission-check-<PR>` 계약은 **명시 개정으로만 비계약화한다**
  (기존 계약 실측: `admission-check-308` 류 명명이 현행 production 계약 —
  본 ADR이 그 명시 개정이다).
  **개정 (2026-10-04)**: 초판 P2의 `admission-check-<candidate head>`는
  run_attempt를 이름에 담지 않아 debt464 §9(ii) trusted-name 계층을
  무력화했다 — 같은 run_id 아래 attempt마다 동명 아티팩트가 누적되어
  MINT_ART exactly-one이 fail-closed로 실패한다(실측 run 37179209673
  attempt=2: found 2 → `subject-certificate-2` found 0 cascade).
  `run_attempt` suffix를 복원해 3계층 attempt binding(run-scoped API +
  trusted-name + manifest)을 재성립한다. 이 suffix는 장식이 아니라
  **identity 성분**이다 — 제거는 다시 명시 개정으로만 가능하다.
- **(P3)** SL-05(`ax merge <N> --dry-run`)는 merge_group에서 **scoped skip** —
  scope 결정: queue 경로의 admission = required check verdict이며 trust-surface는
  멤버 PR-이벤트 개별 검사와 runner-pool Δ가 대체한다. (freshness 제공자는
  strict에서 **큐 무효화 의미론**으로 이동, R2 문서화.)
- **(P4) freshness 앵커는 이벤트 고정 base다 — 살아있는 PR API `base.sha`는 판정
  입력이 아니다** (2026-10-05). 판정 기준 base(`AXIOM_MAIN_SHA` =
  `github.event.pull_request.base.sha || github.event.merge_group.base_sha`)와
  인증서 construction base(mint step의 `base_sha`)는 **같은 값**이며, 이 값이
  유일한 앵커다. merge_group에서 큐가 base를 전진시키면 `pulls/N` 스냅샷은 뒤처져
  살아있는 값을 앵커로 쓰면 **다른 PR이 하나 착지할 때마다 큐의 모든 PR이
  STALE_BASE로 오탐**된다(2026-10-04 실측: ~247분 낭비).
  - **결과(숨기지 않는다)**: 큐 경로에서 Axiom 측 freshness deny는 **큐 자신의 권위
    base에 대한 항등식**이 되어 그 경로에서 사라진다. `merge_group.base_sha ==
    parents(G)[0]`는 실측 확정(2026-10-04, 4런 + 큐 증거) — 그 값이 큐가 실제로
    테스트한 그룹의 권위 base다.
  - **deny는 제거되지 않는다**: `MergeAdmissible`는 그대로 유지되며 (a) declared
    main ≠ 기록 앵커(기준이 옮겨간 뒤의 재검증) 와 (b) 앵커 없이 predicate에
    도달한 모든 호출자에서 발동한다. `BASE_UNRECORDED`는 CLI 경로에서 도달
    불가능해졌고(`AXIOM_MAIN_SHA` 미설정 시 수집 전에 fail-closed) fail-closed
    분기는 그대로 보존된다.
  - **PR 경로**: 실행 중 base가 움직이면 deny는 워크플로 레벨의 identity 재파생
    (`admission-check.yml` mint step `base_sha == B` fail-closed)과 GitHub strict
    required-check 무효화가 담당한다 — Axiom predicate는 그 창을 대신하지 않는다.
  - **원장 키 정합**: actuator의 `loadLedgerCertFor`는 (baseSha, headSha) **PAIR**
    키로 인증서를 찾는다. 앵커를 mint의 `base_sha`와 같은 값으로 고정했으므로 이
    키는 앵커와 어긋나지 않으며, Pass 2.96이 `cert.baseSha == V.baseSha`를
    강제해 어긋남을 **병합 이전**에 deny로 만든다(DEBT#482 해결).
- **(P5) freshness authority singularity — strict는 freshness 역할에서 은퇴한다**
  (2026-10-05, operator 승인). main 착지 경로의 freshness 집행은 **GitHub
  merge-queue 무효화 의미론 단일 체계**다 — 연쇄 speculative merge_group이
  후보를 최신 main 위 첫 그룹으로 재구성하고(`merge_group.base_sha ==
  parents(G)[0]`, P4 실측), stale 그룹은 큐가 폐기한다. ADR-0025 §2의
  **"필수 조합"**(`required_status_checks = ["admission-check"]` 1개 유지 +
  `strict=true`)은 **부분 supersede**다 — 단일 required check 조항은 **불변
  유지**하고, `strict=true` 조항은 **은퇴**한다: `strict=false`가 본 ADR 착지
  직후의 라이브 플랫폼 상태가 된다. Axiom은 **admission authority에만 머문다** —
  Pass 0(STALE_BASE)는 모든 CI 경로에서 **provenance identity**이지 freshness
  판정이 아니다(P4·DEBT#485 정합).
  - **근거**: N-way 동시 workstream은 **실제 착지 prefix**에 대해 검증되어야
    하고, 큐는 이를 구성으로 제공한다. strict는 같은 보장을 위해 사람의
    update-branch 재조정 단계를 추가해 큐의 보장을 복제한다 — GitHub 공식
    문서는 merge queue가 "the Require branches to be up to date before
    merging branch protection"과 동일한 이점을 제공한다고(provides the same
    benefits) 선언한다.
  - **경계**: 본 항은 ruleset 개정이 아니라 정책 결정의 기록이다 —
    `strict=false` 라이브 전환은 operator merge authorization(2026-10-05)으로
    본 ADR 착지 직후 수행되며, 결정 일시는 `github_delegation_residuals.md`
    R2에 기록된다.

### Invariants kept(불변 유지)

- required check는 정확히 **1개** `admission-check`(integration 15368 — main
  ruleset 실측값, A2/R14 정합).
- `bypass_actors=[]` 유지(착지는 ruleset 적용 identity로만).
- **MERGE 전용** 착지 — rebase/squash 비활성화 유지(AGENTS.md:136).
- **커스텀 큐/orchestrator 금지 유지**(본 ADR의 위임 = 플랫폼 큐로의 위임이지
  Axiom 자체 큐의 도입이 아니다).
- AGENTS.md:136 native MERGE 정본 선언은 **불변**(AGENTS.md 자체 무수정 — §-1).
- Axiom = candidate integrity verdict only — 후보 구성·착지에 Axiom 코드 경로를
  만들지 않는다(§0.3 신뢰 경계 유지).

### Phase 0 측정 계획(본 ADR의 확정 조건 — 진행 중)

- scratch 규칙셋(`queue-probe` ref 스코프)에 `merge_queue` 규칙(merge_method
  MERGE · min/max_entries_to_merge 1/1 · max_entries_to_build 2 ·
  check_response_timeout_minutes 60) + required_status_checks(probe 워크플로
  check) + pull_request(merge 전용)를 설치한다 — main에는 merge_queue를
  활성화하지 않는다.
- `probe-merge-queue.yml` 복원(4b56ad4fc^에서 복구 + artifact-download 결함
  수정 + push 스코프 queue-probe): merge_group 페이로드(merge_group.head_sha ·
  head_ref 원문 · base_sha · base_ref · head_commit.tree_id · GITHUB_SHA ·
  GITHUB_REF)를 `merge-group-payload-<sha>` 아티팩트 + job summary에 기록하고,
  착지 후 judge가 L을 맞대어 `PROBE_VERDICT`를 낸다(질의 4종: L==G ·
  parent1(L)==B · parent2(L)==G · tree(L)==tree(G) + parents(L) 목록).
- 측정 ≥2회(순차 PR). 판정: **α** = parents(L)==[B, H_PR](H_PR = PR head);
  **β** = parent2(L)==G ∧ tree(L)==tree(G); **γ** = 그 외 — γ 판정 시
  **즉시 STOP·재의결**(본 ADR 확정 보류, 결과 보고).

## Consequences

**긍정:** 후보 인증(verdict)과 착지 큐잉이 분리되어 Axiom의 authority는
"무엇이 유효한 후보인가"에 집중되고, 순서·후보 구성·착지는 플랫폼 결제된
기능에 위임된다. Alpha/베타 형상이 실측되면 불변식 6/7의 큐 경로 의미론이
기계 증거로 확정된다.

**부정(residual):** 플랫폼 큐의 착지 커밋 형상은 GitHub 비공개 구현 의존 —
측정 전 사전 선언 금지(불변식 6 재서술). strict freshness의 큐 경로 의미론은
R2 문서화 의무(후속). `admission-check.yml` 주석의 "ADR-0026" 참조는 번호
정합 갱신 대상(후속 — 본 ADR 범위 밖). main ruleset에는 merge_queue를
활성화하지 않는다(Phase 0은 queue-probe 스코프 한정).

## 잔여 한계 (Residual Limits)

- **계획서 실증 의존**: α/β/γ 측정·프로브 실행·큐 무효화 의미론 실측 전까지
  본 ADR의 형상 서술은 예정 계약이며 확정 아님(γ = 재의결).
- **운영 전환 범위 밖**: main ruleset merge_queue 활성화, org gate/`.github`
  개정, admission-check.yml 실측 대응 구현(SL-05 scoped skip 배선, mint
  want_name 미러), `merge_cli`/`landing_cli` 큐 경로 수용, R2 잔여 위협 기록 —
  모두 본 ADR 착지 후 Phase 1+.
- **불변 (본 ADR 범위 밖)**: AGENTS.md · `config.nims` importEncapsulation ·
  `src/gate/runners/import_encapsulation_gate.nim`(§-1) 무수정.

## References

- 계획: cert(G) 후보 인증 — GitHub Merge Queue 채택(Phase 0: 기록 → 표면 등록 →
  probe 복원 → scratch 측정 → 증거)
- AGENTS.md:136(§2 — native MERGE 정본 선언) · §0.3(신뢰 경계) · §-1(수정 제한)
- main ruleset 20303214(required check `admission-check` 단일 + strict +
  `allowed_merge_methods:["merge"]` + `bypass_actors=[]` — 2026-09-29 API 실측)
- org ruleset 24041674(org gate pin) · push ruleset 23967915(execution-surface-create)
- `docs/spec/merge_admission_controller.md:31-33,:195`(native merge queue pole 폐기
  선언 — superseded)
- `docs/spec/repository_surface_contract.md:144-160,#11,:195-196,#13(2)`(소거
  대상·probe retire·merge authority 집합 — superseded)
- `docs/spec/certification_continuity_contract.md:449-462`(§10.6 — 되돌림 대상)
- `docs/adr/0025-gateway-landing-authority.md:493,:495-496`(Amendment A 불변식
  4/6/7 — 측정 의존 재서술)
- `docs/adr/0026-execution-authority-unification.md`(번호 선점 — "ADR-0026" 지정
  정합 갱신 대상)
- `src/verification/attestation_orchestrator.nim:155` · `src/verification/
  attestation_witness.nim:61` · `src/verification/verification_subject.nim:57,159-160`
  (prNumber honest-0 · identity wire 밖)
- `.github/workflows/admission-check.yml:55-56,:73-84,:115`(P1/P2/P3 선언 위치 —
  "ADR-0026" 참조, 번호 정합 후속)
- `config/repository_surface.json` v29(docs/adr/0027-queue-delegation.md CONTROLLED
  등록 — 2단계 정책 PR, e41241b7c 착지) — probe-merge-queue.yml·증거 문서·측정
  마커 경로 등록은 v30 정책 PR(2단계)
- `docs/spec/gh_org_required_workflow_run_quirks.md`(org-workflow 런 관측 — PR
  checks 경로)
- GitHub 공식 문서 — merge queue rules(available rules for rulesets) ·
  merge_group webhook payload(head_sha/base_sha/head_ref/base_ref/head_commit)

## Amendment A (2026-10-12): 단일 required check 조항 개정 — ADR-0025 Amendment E(2026-10-12) 정합 노트

> 결정 바인딩 개정(AGENTS.md §0.10)이다. 결정 권한 = operator/decision
> owner 승인(2026-10-12). 본문을 다시 쓰지 않으며 append로만 남는다.
> 개정의 의미·근거·전이 상태 모델의 SSOT는 **ADR-0025 Amendment E
> (2026-10-12)**다 — 본 절은 본 ADR의 단일 required check 조항을 그 개정과
> 정합시키는 지시 노트다.

- **개정 대상 본문 조항(4곳)**: Context의 "required check
  `admission-check`(integration 15368) 정확히 1개"(:23), Decision 권위
  표의 "`admission-check` verdict(단일 required check)"(:69), P5의
  "단일 required check 조항은 **불변 유지**"(:174-177), Invariants kept의
  "required check는 정확히 **1개** `admission-check`"(:193-194).
- **개정 내용**: 위 조항들의 "정확히 1개/단일" 서술은 2026-10-12부터
  superseded다 — main ruleset(id=20303214)의 required status checks는
  정확히 **2개** 컨텍스트(`admission-check` — merge eligibility /
  trust-boundary verdict, `bsec-integrity` — D2 verdict protocol 기록
  무결성: derived == recorded == ledger heads)로 개정된다.
- **의미 비대칭 유지**: `bsec-integrity` PASS = 기록 무결성 ONLY — 결코
  verdict GO가 아니다(never a verdict GO). 본 ADR의 권위 분할(Axiom =
  candidate integrity verdict만)은 무변경이며, 기록 무결성 검사는 verdict를
  확장하는 folding이 아니라 별개 컨텍스트의 추가다.
- **무변경**: Invariants kept의 나머지 전부 — `bypass_actors=[]`
  (20303214), MERGE 전용 착지, 커스텀 큐/orchestrator 금지, AGENTS.md:136
  native MERGE 정본. 전이 상태 모델(S0/Sf/S1)·cutover 실행 불변식·모니터
  기대치 회전은 ADR-0025 Amendment E §3-4에 기록된다.

## Amendment B (2026-10-13): PR venue 사전검사 앵커 — 실행별 단일 확정 B*

> 결정 바인딩 개정(AGENTS.md §0.10)이다. 결정 권한 = 승인된 CI-recovery
> 계획 Stage 2(operator 승인, 2026-10-13; 단일 앵커 B* + failure-code
> 관측 가능성). 본문을 다시 쓰지 않으며 append로만 남는다.

- **PR venue 앵커 재정의**: PR venue(pull_request)의 사전검사
  (preflight·candidate 준비) 앵커는 **실행별(run-scoped) 단일 확정 B*** —
  오케스트레이터(admission-gate `anchor-resolve`)가 dispatch 전에 live
  main ref tip을 **한 번** 해석하여 workflow_call 입력 `baseSha`로
  전달한 값이다. callee(admission-check.yml)는 PR venue에서 이 입력을
  **최우선** 소비하고, 미전달 호출자에 대해 이벤트 페이로드 폴백을
  유지한다(하위 호환 — 평가 결과 동일).
- **판정 아님**: B*는 **candidate 준비 전용**이다 — 착지 판정(landing
  judgment) 입력이 아니다. 착지 신선도 계약은 무변경: GitHub
  strict_required_status_checks_policy + merge-queue invalidation이
  병합 시점에 재결속한다(본문 P4-2, v1.10.0 정합).
- **merge_group venue 무변경**: 큐 경로 앵커는 **이벤트 동결 group
  base**(merge_group.base_sha == parents(G)[0]) 그대로다 — P4 준수,
  MG 코드 경로는 이 개정으로 평가 결과가 변하지 않는다(빈 입력은
  falsy → 기존 페이로드 항으로 수렴).
- **P4 근거 영향 없음**: P4가 live pulls/N base.sha를 앵커에서
  배제한 근거(큐가 base를 밀면 PR API 스냅샷이 뒤처져 오탐 — ~247분
  낭비 실측, 2026-10-04)는 그대로 유효하다. B*는 pulls/N base.sha가
  아니라 **해석 시점의 live main ref**를 한 번 읽는 별개 경로다 —
  오탐 원인(실행 중 base 이동 추격)을 재도입하지 않는다.
- **잔여 창(residual window) 처리**: B* 해석 이후 main이 진행하는
  창은 fail-closed로 남는다 — identity 등식(head.sha == H ∧
  base.ref == main ∧ B* 공급 시 B == B*)과 GitHub strict-check
  invalidation이 차단하며, 문서화된 복구 사이클(retry)로 치유된다.
  이를 위해 종전 PR-API `base.sha == B` 등식은 제거된다 — B와
  스냅샷이 양쪽 모두 stale일 때 그 등식은 아무것도 증명하지 못했다
  (defeatable). pulls/N base.sha는 비입력(non-input)으로 저널 기록만
  남긴다.
- **관측 가능성 (판정 의미 무변경)**: identity-step fail과 verdict
  NOT-ADMIT 경로가 안정 코드 어휘(ADM_IDENTITY · CANDIDATE_* ·
  ANCHOR_INPUT_MISMATCH · NOT_ADMIT_<reasonCode>)의 `::error`
  애노테이션을 추가로 방출하고, verdict-log 아티팩트 업로드가
  `always()`로 실행된다(NOT-ADMIT 증거 보존 — 종전에는 GO-only라
  증거 상실). exit 계약·GO 조건·권위 분할은 불변이다.

## Amendment C (2026-10-13): 재arm 전용 자동화 경로 허용 조건

> 결정 바인딩 개정(AGENTS.md §0.10)이다. 결정 권한 = 승인된 CI-recovery
> 계획 Stage 3(operator 승인, 2026-10-13). 본문을 다시 쓰지 않으며
> append로만 남는다. Invariants kept의 **커스텀 큐/orchestrator 금지**는
> 불변이며, 본 개정은 그 금지를 해석적으로 우회하지 않는 좁은 자동화
> 하나를 조건부로 허용하는 기록이다.

- **허용되는 유일 행위**: dequeue된 PR의 **auto-merge 재arm** — 워크플로가
  수행하는 동작은 `gh pr merge <N> --auto --match-head-commit <head>` 또는
  GraphQL `enablePullRequestAutoMerge(expectedHeadOid:)` 정확히 하나여야
  한다. 큐잉·순서·후보 구성·착지의 권위는 플랫폼 큐에 그대로 있고(본문
  권위 분할 불변), 이것은 플랫폼 primitive의 재호출이지 큐 의미론의
  소유가 아니다.
- **적용 조건(전부 충족)**: (1) 큐에서 제거(dequeue)된 PR, (2)
  non-trust-surface — `config/policy/merge_admission.json`의
  `trustSurface` 열거로 기계 판정하며 trust-surface PR은 MUST-T1
  (docs/agents/rules_workflow.md)에 따라 본 자동화 대상에서 **배제**된다,
  (3) admission 런의 **기계 판독 failure code**로 분류된 **TRANSIENT**
  실패 — 근거 표면은 안정 코드 어휘의 annotations뿐이고 **로그
  스크래핑 금지**, (4) UNKNOWN·분류 불가 실패는 자동 재시도하지 않는다
  (fail closed).
- **재시도 상한(무한 후퇴 종결)**: 상한 카운터 키 = (PR, head SHA,
  base/candidate SHA, 실패 분류). 카운트는 워크플로 자신의 **불변 run
  이력**에서만 산출하며, 키별 concurrency group으로 직렬화한다. 상한
  도달 시 자동화는 종료되고 operator 개입만 남는다.
- **관측 계층 아님(경계 재확인)**: 본 자동화는 관측 계층
  (docs/agents/merge_admission_observation.md — monitor zero-write
  불변식)에 편입되지 않는다 — 별도 워크플로 파일이며, 관측 명령
  인벤토리·purity 스캔 표면과 결합하지 않는다.
- **초기 arm은 operator 전용으로 불변**: 본 개정이 허용하는 것은
  **재arm뿐**이다. 최초 arm은 Auto-Merge Default Policy
  (docs/agents/rules_workflow.md — operator가 GitHub primitive로 arm,
  정상 경로 인간 명령 1회; MUST-T3) 그대로며, Stage 3 계획이 이 경계에
  부여한 P27 번호의 정본 기록은 본 항이다.
- **의존 플랫폼 사실(문서화)**: merge-queue activity types
  (`dequeued`/`enqueued`), `gh pr merge --auto` +
  `--match-head-commit`, GITHUB_TOKEN 재귀 비발생(워크플로가 발급한
  GITHUB_TOKEN으로 만든 push·이벤트는 다른 워크플로를 트리거하지 않음).
- **의존 플랫폼 사실(미문서 — 실측)과 전제조건**: dequeue 시 auto-merge
  소멸(2026-10-12/13 #787·#805 실측 —
  docs/agents/merge_admission_observation.md 부록 (b))이므로 re-arm
  전제조건에 큐 부재 검증 guard를 둔다. **단(2026-10-13 실측 정정)**:
  PR #805의 재arm live 큐 entry 전 수명에서 GraphQL `autoMergeRequest` /
  REST `auto_merge`는 **null로 판독됐다**(병합 후까지 매 관측 null —
  `docs/spec/gh_run_observation_quirks.md` Q9). autoMergeRequest 필드는
  신뢰할 수 있는 관측 신호가 아니므로, re-arm 전제조건의 큐 부재 검증은
  GraphQL `mergeQueueEntry` / `isInMergeQueue`로 수행해야 하며
  autoMergeRequest 필드의 null은 근거가 아니다.

## Amendment D (2026-10-14): Stage 3-B 종결 + slice_catalog 드리프트 수용 + 재arm 구현 관례

> 결정 바인딩 개정(AGENTS.md §0.10)이다. 결정 권한 = 승인된 Stage 3-A/3-B
> 착지 계획(사용자 4차 판정, 2026-10-14). 본문을 다시 쓰지 않으며 append로만
> 남는다. Amendment C가 허용한 재arm 경로의 종결 판정과 구현 관례,
> slice_catalog 드리프트 수용 결정을 하나의 개정으로 기록한다.

- **Stage 3-B 종결 — Amendment C 이외의 자동화 없음**: 재arm 경로(Amendment
  C)를 넘어서는 자동화는 도입하지 않는다. 수동 복구 사이클(operator가 dequeue
  사유를 판독·수정·재push·재arm하는 절차)을 유지한다. 재의결 기준(그대로
  인용): **"게이트 결함을 제외한 경합 계열 사례가 2개 연속 월에 각각 5건 이상
  발생할 때만 재의결한다"**. 측정 근거 = C3 30일 서베이(경합 사례 164건,
  transient 18.9%, Stage 2 이후 0건).
- **slice_catalog 드리프트 수용(옵션 ③)**: slice_catalog 드리프트는
  ADR-0034 §Known-stale에 기록된 바를 교차 참조한다(중복 기술하지 않음 —
  인용만이 본 개정의 방식). 로컬 드래프트는 폐기되며 착지하지 않는다.
- **구현 관례 1 — run-name 키 인코딩(신규 관례, 선행 선례 없음)**:
  merge-queue-rearm.yml의 run-name은 실행 시작 시점에 확정 가능한 정적 접두
  (pr번호 + head SHA)만 새겨 실행 구분을 보장하고, candidate SHA(G)와 실패
  분류는 스텝 로그로 남긴다. run-name은 실행 후 변경 불가이므로 상한 카운터의
  키 매칭은 자기 run 이력의 display_title 접두 포함
  (`rearm pr<N> h<sha12>`)으로 수행한다 — 이는 완전 키 (PR, head, G, 분류)의
  보수적 과대근사이며(같은 PR+head의 다른 G 시도를 함께 셈), 절대 과소계산하지
  않는다(재arm이 더 일찍 닫히는 방향만).
- **구현 관례 2 — 마커 프로토콜**: `no-auto-rearm`(수동 dequeue 의도 표식 —
  워크플로가 절대 재arm하지 않음)·`rearm-exhausted`(동일 key 재arm 상한 2
  도달 — operator 개입 필요) 라벨이 사용자 의사 표면이다. dequeue 사유는
  API로 관측 불가(문서화된 플랫폼 한계)이므로 라벨이 유일한 의도 전달
  수단이다.
- **구현 관례 3 — 분류 allowlist**: NOT_ADMIT_BINDING_MISMATCH ·
  NOT_ADMIT_STALE_BASE · ADM_IDENTITY · CANDIDATE_MERGE_BASE_UNRESOLVED의
  4코드만 재arm 후보다(보수적 초기 집합). NO_CERT/re-attest 계열과 전
  ROT_*/TRUST_SURFACE 클래스는 제외된다. 무제목(플랫폼 경고) annotation은
  분류 코드를 운반하지 않으므로 allowlist 판정에서 무시되되, 안정 코드가
  하나도 없으면 UNKNOWN으로 no-arm한다. 근거 표면은 verdict /
  admission-check check-run 객체의 annotations뿐이고 로그 스크래핑은
  금지다. quirk: `/commits/{G}/check-runs` 목록 응답의 `annotations_url`은
  null로 온다 — 표준 URL을 같은 check-run 객체의 id로 구성해 사용한다
  (객체 동일성 불변 — `docs/spec/gh_run_observation_quirks.md` Q11).
- **구현 관례 4 — API 질의 실패 = no-arm**: 분류·상한·큐·라벨·trustSurface
  질의가 실패하면 재arm하지 않고 `SKIPPED: <사유>`로 종료한다(fail closed).
  워크플로는 실행 자체를 실패 처리하지 않는다 — REARMED 또는 SKIPPED 로그만
  남는다. (단, Amendment E의 예산 소진 경로는 예외다 — 명시적 실패 종결.)

## Amendment E (2026-10-15): 결정적 TRANSIENT 분류 + 사용자 확정 재시도 예산(총 2회/PR head) + `checks: read` 근본 결함 수정

> 결정 바인딩 개정(AGENTS.md §0.10)이다. 결정 권한 = 사용자 결정(2026-10-15 —
> 재시도 예산 총 2회/PR head 사용자 확정) + 승인된 Slice B 계획 S1(같은 날 —
> S1 = 본 개정 + `merge-queue-rearm.yml` 하드닝, S3 = dry-run 채널 실측
> 검증). 본문을 다시 쓰지 않으며 append로만 남는다. Amendment C의 재arm 경로
> 조건과 Amendment D의 구현 관례 중 본 개정이 명시하는 항목을 개정한다.

- **근본 결함(root cause, 2026-10-15 검증)**: `merge-queue-rearm.yml`의
  permissions 블록에 `checks: read`가 결여되어
  `repos/$REPO/commits/$G/check-runs`가 GITHUB_TOKEN으로 403을 반환했고,
  stderr가 `2>/dev/null`로 흡수되어 모든 실행이 fail-safe no-arm으로
  수렴했다 — 재arm 메커니즘 전체가 no-op이었다(2026-10-14~15 표본 7/7).
  수정: `checks: read` 추가 + 모든 API 오류를 가시 stderr로 기록(오류 흡수
  금지). fail-safe no-arm 의미론 자체는 유지된다(오류 시 arm 없음).
- **재시도 예산(사용자 확정, 2026-10-15)**: PR head당 총 검증 시도 ≤ 2회
  (최초 1회 + 자동 재arm 1회). 논리 키 = (repository, PR 번호, PR head
  SHA). **Amendment D 구현 관례 1의 run-name/display_title run-history
  카운터는 본 개정으로 superseded**이며, 강제 수단은 내구 PR 라벨
  `rearmed@<head12>`다 — arm 성공 직후에만 설정한다. 동일 head에서 재차
  dequeue되어 이 라벨이 이미 존재하면 예산 소진으로 판정한다:
  `rearm-exhausted` 라벨을 추가/확보하고, 구조화 요약을 출력하며, **잡을
  실패 처리**한다(명시적 종결 실패 — success로 위장하지 않는다; Amendment D
  구현 관례 4의 "워크플로는 실행 자체를 실패 처리하지 않는다" 원칙은 이
  경로 한정으로 superseded). arm이 실패하면 라벨을 설정하지 않는다
  (fail-safe — 미소진 예산 보존).
- **TRANSIENT 열거(폐쇄 집합 — 본 개정 이후 확장 금지)**: 재arm 후보는
  다음 중 **명시적 증거 앵커**가 일치할 때만다 —
  - **(a) ETXTBSY / cold toolcache relink**: 오류 텍스트 `ETXTBSY` ·
    `Text file busy` · `Permission denied`(POSIX errno 26 계열)가 공유
    relink 도구(`bin/feature_manifest_generator` · `bin/sync_certs` ·
    `bin/sync_topology` · `bin/hermetic_build` ·
    `bin/decision_binding_checker`) 또는 `make test-fast-one` 레인
    부트스트랩과 연관된 단계/잡의 이름 또는 로그에서 관측될 것.
    **서명 완성(2026-10-15, S2 실험 38710338905·38711735376)**: 동일
    고정 클래스 (a)의 CI 러너 발현이 공유 nimcache `.o` 동시 기록 링크
    손상임이 입증됨 — `undefined reference to` · `final link failed` ·
    `collect2: error` 서명을 클래스 (a) 앵커에 포함한다(신규 클래스가
    아니라 같은 콜드-병렬 relink 경합의 형제 발현; 직렬 웜업 가드가 두
    모드 모두 억제 — S2 보고서 참조).
  - **(b) artifact/JSON GET 다운로드 실패**: artifact 다운로드 단계의 HTTP
    5xx/429 또는 curl 전송 오류(exit 7/28/35/56).
    **[2026-10-15 계약 정렬(후기 부기)**: 본문의 "429"는 구현 브리프 오류로
    확정된 서술이다 — 사용자 고정 열거(5xx·503·transport)에 429는 불포함이며
    PR #849(머지 `1393366db`)로 구현에서 제거되었다. 429는 현재
    UNKNOWN→DEFAULT-NO-ARM. 재편입은 명시적 정책 개정(사용자 결정) 필요.**
  - **(c) check-runs/annotations 질의 인프라 실패**: `gh api` 호출 자체의
    403/5xx — `checks: read` 수정 후에는 발화하지 않아야 하나 계열로
    유지한다.
  증거 표면 = (i) 대상 실패 leg의 check-run annotation **메시지 본문**,
  (ii) jobs API의 단계 결론·이름, (iii)
  `actions/jobs/<id>/logs` grep. **어떤 앵커도 일치하지 않으면 UNKNOWN →
  no-arm이다(DEFAULT-NO-ARM)**: 'failure' 결론, 결측 check, NOT_ADMIT_*
  타이틀 단독은 결코 TRANSIENT를 함의하지 않는다. 커스텀 타이틀(예:
  NOT_ADMIT_UNPARSED)만으로는 불충분하며 메시지 본문을 검사해야 한다.
- **타이틀 allowlist 유지**: NOT_ADMIT_BINDING_MISMATCH ·
  NOT_ADMIT_STALE_BASE · ADM_IDENTITY · CANDIDATE_MERGE_BASE_UNRESOLVED는
  종전대로 annotation-title로 TRANSIENT 분류한다(Amendment D 구현 관례 3의
  보수 초기 집합 유지). ROT_*/TRUST_SURFACE*/NO_CERT*/MUST_* 계열 타이틀은
  **PERMANENT**로 분류한다(no-arm).
- **구조화 요약 계약**: 모든 종결 경로는 단일 행 JSON
  `{"rearm":{pr,head,class,reason,budget,action,evidence{job,step,line}}}`을
  잡 로그(`^\{"rearm"` grep 가능)와 `$GITHUB_STEP_SUMMARY`에 출력한다.
- **검증 채널**: workflow_dispatch 입력 `dry_run`(기본 false) + 선택
  `run_id`로 완료된 런(run_id 미지정 시 해당 pr의 최근 merge_group 런)의
  **전체 분류 파이프라인**을 검증한다 — arm도 라벨 쓰기도 없다. 이 채널이
  Slice B S3의 통제된 검증 게이트다.
- **참조**: 승인된 Slice B 계획(사용자 승인, 2026-10-15) — S1(본 개정 +
  워크플로 하드닝)·S3(dry-run 실측 검증); 계획·실행 증거 문서는 S3 착지 시
  `docs/evidence/`에 기록된다. 근본 결함 실측(7/7 no-op 표본)은 같은 날
  사용자 검증 기록에 근거한다.

---

*작성일: 2026-09-29. PROPOSED — Phase 0 측정(α/β) 완료 전 "착지 형상 확정" 선언
금지. γ 판정 시 본 ADR은 재의결 대상이다.*