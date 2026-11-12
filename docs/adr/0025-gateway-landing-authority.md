# ADR-0025: Gateway 실행 권한을 landing candidate로 이전 — post-merge 재검사 구조적 제거

## Status

**PROPOSED (2026-09-26)** — 계획서 gateway-landing-authority 전환(hellcat-iceman-havok)의
In Scope Phase 0 ADR 기록이다. 본 ADR은 main 변경 정본 행위를 **GitHub native MERGE 하나**로
고정하고(§1 M-B 개정), gateway 실행 권위를 push@main에서 **landing candidate(PR head)의
admission 실행**으로 이전하며, 그 결과 post-merge 재검사(push@main 발화)를 구조적으로
제거한다. DEBT#462/Landing App CAS는 **무변경·무결합**으로 둔다(§1.4). 착지는 본 ADR과
개정 대상 문서(CAS-only 서술 §1.2) 및 `ci/checker.mk`·`derive_checker_closure.nim` 신설,
플랫폼 오케스트레이터(`Archright/.github/admission-gate.yml @SHA`) 등록을 요구하므로
Phase 1~5 스테이징(§12)에 따라 진행하며, bootstrap(구현) PR의 CI 성공은 완료 증거가 아니다.

> **갱신 노트 (2026-10-15 — 원문 보존, 아래 본문은 작성 시점 서술이다)**: 본 ADR이
> 서술하는 조직 ruleset의 **SHA pin 강제**는 24041674 시대에 실현되었다가, sha-bearing
> PUT 500 사건(`docs/evidence/epoch_record_oracle_select_2026-09-30.md` §8.3) 이후
> 2026-09-30/10-01에 ruleset **24233738 `ref: main`(sha-less) 대체**로 무효화되었다
> (`docs/evidence/epoch_record_base_artifact_2026-10-01.md` §2.3). 2026-10-15 기준 핀
> 모드의 정본·승격 절차·S4 재핀(`sha: H₁`)은
> [docs/spec/admission-generation.md](../spec/admission-generation.md)이 단일 SSOT로
> 규정한다 — §2·§5의 "SHA pin" 서술은 그 문서를 통해 해석한다.

## Context

- **오위치 실측**: `docs/evidence/canonical_run_graph.md:73` — push@main 발화의
  runner-pool-acceptance는 "OBSERVATIONAL (착지 후 발화 — 가드 불가)". main에 이미 착지한
  커밋을 재검사하는 실행은 착지 전 게이트가 될 수 없으며, 원인 진단(계획서 §9)은 실행
  권한 미결속 — ADR-0021 선 채택에도 push@main 발화가 남아 canonical_run_graph.md:73에서
  "착지 후 발화 — 가드 불가"로 관측 — 이며, 제어장치는 권한 구조 불변(§2.2-8)이므로
  장치 추가 없이 권한 구조만 정정한다. gateway-shard·identity-gate·
  proof-reconcile은 candidate 검증 주체(§10 Gate A)이며 착지 후 발화지점은 인위적이다.
- **M-B 실측(정본)**: ① AGENTS.md:136 — "PR 랜딩은 GitHub 네이티브 MERGE 커밋(merge commit
  활성화; rebase/squash 비활성화)을 정본 랜딩 메커니즘으로 사용한다" ② `origin/main` 전체
  커밋의 `committer: GitHub`(계획서 §9 근거 실측) ③ Landing App CAS E2E 착지 **0건** —
  DEBT#462 open 상태(`data/debt_registry.json:3761-3774`, `docs/DEBT_REGISTRY.md:178`)의
  "production-path E2E evidence" 미기록과 일치 ④ INV-2 원문 —
  `docs/spec/certification_continuity_contract.md:208` "착지는 GitHub native MERGE commit
  — continuity가 merge-commit shape(parents/tree)로 인증 입력 상속을 검증". 따라서 Landing
  App CAS 경로(`config/app_landing_binding.json:5` 서술, Owner 결정 #11 —
  `docs/spec/repository_surface_contract.md:144-160`, `docs/spec/merge_admission_controller.md:33,:195`)
  는 **운영 실측이 없는 비authoritative 예비(备用) 경로**이며, 본 ADR은 그 서술만 정정한다.
- **GitHub 위임 가능성(①′ 전제)**: main ruleset(id=20303214) 현행 required check =
  `admission-check` 단일 + cross-repo required workflow `landing-integrity`
  (`canonical_run_graph.md:95`); org required workflows 기능으로 타깃 repo PR에 강제 실행되는
  패턴이 이미 실측되어 있다(`canonical_run_graph.md:148-154` — ruleset id 23943917,
  `Archright/.github`@main `.github/workflows/landing-integrity.yml`, org `.github` repo의
  파일 존재 sha 8c016c8e 실측). GitHub가 이미 보장하는 권위(execution identity / freshness /
  approval / MERGE)를 Axiom이 중복 구현하는 것은 authority 중복이며 제거 대상이다.
- **공식 API 문서 실측(①′)**: `strict_required_status_checks_policy` — "This setting will
  not take effect unless at least one status check is enabled". 즉 strict는 status check ≥1
  에서만 작동하며, `required_status_checks=[] + strict=true` 조합은 성립 불가 — freshness가
  소멸하면 `merge(H,B1)` 검증 / `merge(H,B2)` 착지 분리가 발생해 착지 전 4중 등식이 붕괴한다.

## Decision

**Ultimate Purpose:**

> 검증된 candidate만 main에 들어가고, main을 변경하는 주체는 GitHub native MERGE 하나뿐인
> authority graph에서 gateway 실행 권한의 오위치(push@main)만 제거하며, GitHub가 이미
> 보장하는 권위(execution identity / freshness / approval / MERGE)를 Axiom이 중복
> 구현하지 않는다.

**Core Invariant:**

```text
                 GITHUB PLATFORM
                       │
        ┌──────────────┼────────────────┐
        │              │                │
 required workflow   strict        CODEOWNER
   @ exact SHA        freshness      approval
   (execution         (freshness     (approval)
    authority)         authority)
        │              │                │
        └───────┬──────┴────────────────┘
                │
          admission-check GREEN   ← 단일 실행의 verdict (required status context)
                │
     gateway + certificate + identity equality
     (Axiom @SHA reusable: H code/read · B code/write)
                │
          native MERGE            ← 유일한 main 변경
                │
              main
                │
     audit: M.tree == certTree     (착지 후 observation)

post-merge gateway = 0
```

- **required workflow ≠ second test, required status ≠ second test** — 둘 다 동일한
  admission 실행을 보호하는 플랫폼 제어: **execution identity + freshness binding**. CI는
  **한 번만 실행**된다(중복 authority 0이 아니라 2개 플랫폼 제어의 동일 실행 — 계획서 ①′
  최종 정정).
- **M-B:** main 변경 = native MERGE만(§1). **2권위**(§2) · **certificate**(§3) ·
  **write boundary**(§4) · **SHA pin**(§5) · **closure/deriver**(§6) · **rotation**(§7) ·
  **fail-closed**(§8) · **boundary/보호 계층**(§9) · **Gate A**(§10) · **identity
  3계층**(§11) · **스테이징**(§12) · **의무 연쇄**(§13) · **ledger 동시성**(§14).

### §1 M-B 개정 — main 변경 정본 행위 = GitHub native MERGE

1. **정본 선언**: main을 변경할 수 있는 정본 행위는 **GitHub native MERGE 커밋**이다
   (AGENTS.md:136 정본 선언 유지 — AGENTS.md 자체는 §-1 불변, 변경 없음). 실측 정합:
   `origin/main` 전부 committer=GitHub(계획서 §9), Landing App CAS E2E 0건 = DEBT#462 open
   (`data/debt_registry.json:3761-3774`), INV-2 원문 `certification_continuity_contract.md:208`
   도 native MERGE를 전제한다.
2. **CAS-only 서술만 개정**: Landing App CAS를 "main 변경 권위"처럼 서술한 3곳 —
   `config/app_landing_binding.json:5`("The ONLY authority that mutates refs/heads/main
   via the updateRefs CAS path"), `docs/spec/repository_surface_contract.md` Owner 결정 #11
   (:144-160 — "runtime mutation authority = Landing App"), `docs/spec/merge_admission_controller.md:33,:195`
   (Owner 결정 #11 기록) — 을 "CAS-only"(비authoritative 备用) 서술로 정정한다. 정본 랜딩
   경로의 변경은 없다.
3. **B결속**: §4의 "main 직접 mutation = 불가"는 M-B(§1)에 결속된다 — Axiom mint·CLI는
   main 직접 변경 코드 경로를 가지지 않으며, main 변경은 플랫폼 native MERGE(required
   workflow + strict + CODEOWNER approval 하)에만 존재한다.
4. **DEBT#462 무관심·무결합**: DEBT#462(open 상태 유지)와 Landing App CAS는 **본 ADR의
   개정 범위가 아니다** — 상태·설계·도입 일정을 건드리지 않고, 서술 정정 외 결합을 만들지
   않는다. 개정되는 것은 M-B 문구의 현실화뿐이다(계획서 Out of Scope).

### §2 ①′ 2권위 정의 — execution authority / freshness authority

동일 단일 실행에 대한 2개 플랫폼 제어이며, **중복이 아니다**:

| 권위 | 플랫폼 장치 | 의미 | 소유/고정 |
|---|---|---|---|
| **execution authority** | org ruleset `type: workflows` — required workflow(§5 SHA pin) | **무슨 검증 프로그램을 실행할지·정의를 누가 고정하는지** | `Archright/.github/admission-gate.yml` @<40-hex>(플랫폼 SHA) → Axiom reusable @<40-hex>(Axiom SHA) |
| **freshness authority** | required status check `admission-check` + `strict_required_status_checks_policy: true` | **그 검증 결과가 최신 base에 유효한지** — base가 B1→B2로 진행된 PR은 merge 차단(계획서 [3] 실측 대상) | GitHub ruleset(strict) — Axiom이 재구현하지 않음 |

- **필수 조합**: API 문서 실측상 strict는 status check ≥1에서만 작동 —
  `required_status_checks = ["admission-check"]` **1개 유지** + `strict=true`를 함께 설정한다.
  0으로 만들지 않는다(0+strict 성립 불가 → freshness 소멸). 2건 이상도 금지(단일화 —
  `admission-check` verdict job이 단일 required status context를 생산).
- **CI 단일 실행**: required workflow는 별도의 두 번째 검증이 아니라 admission 실행 자체의
  플랫폼 강제이며, verdict job `admission-check`가 그 실행의 required status context를
  생산한다(§8a).
- **Axiom merge_cli 재정의**(①′): `findRunsForHead`(`src/cli/merge_cli.nim:566`)로 required
  workflow run을 포섭하고 — `repository_id/path/sha` identity의 workflow run이
  `head_sha == H`에 success + verdict output 조건 충족(계획서 Phase 2) — verdict 조건 확인
  후 **freshness는 GitHub strict에 위임**한다. `RequiredChecks`/`RequiredWorkflowIds`
  (`merge_cli.nim:59-79`)는 admission-check 단일로 정합 유지. freshness를 Axiom 코드로
  재구현하지 않는다(계획서 Out of Scope — 중복 authority 아님을 인지하고 위임 유지).

### §3 ② certificate 의미 — certificate ∈ admission predicate, ≠ authority

- `certificate`는 **admission predicate의 필수 증거**(필요조건)이다. certificate는
  authority가 아니다 — certificate가 main을 변경하는 권위를 가지지 않는다.
- **체인**: `gateway evidence + certificate + identity equality → verdict GREEN → GitHub
  authorization to merge`. 실제 merge 권위 = GitHub ruleset(required workflow + strict +
  CODEOWNER) 위의 **native MERGE** 하나다.
- **착지 전 발급**: mint는 verdict GREEN 이전 DAG(admission-check 포함)에 포함되어 착지
  전에 ledger(`refs/heads/axiom/certificates`)에 cert(H)를 추가한다 — 착지 후 발급이 아니다.
  certificate-mint.yml은 `workflow_run` 후행 트리거를 제거하고 orchestrator caller
  context(§4)의 workflow_call 전용으로 재정의한다(구멍 15 반영 — certificate가 landing
  admission 밖에 있던 원인 제거).

### §4 ③ write boundary 계약 — TrustedWriterSet 의미 고정

`contents: write`는 **path-level capability가 아니다**(GitHub 토큰 권한은 저장소 단위).
따라서 "ledger only"는 token scope가 아니라 **계약**이다:

```text
mint job = B-pinned code만 실행
         + H는 data-only input
         + write destination = ledger(refs/heads/axiom/certificates) 한정
         + main 직접 mutation = 불가 (M-B: main 변경 = native MERGE만)
```

- 보장원(계약의 enforcement — token이 아니라 구조+검증):
  **(a)** mint가 실행하는 코드는 B-pinned(§5 Axiom SHA) 코드이며 CODEOWNERS @architect(§13)의
  review 대상 — 임의 PR head 코드는 mint job에서 실행되지 않는다;
  **(b)** H는 data-only input — H tree는 검사 대상(읽기)이며 mint 판정 경로에 실행 주체로
  들어오지 않는다;
  **(c)** M-B 결속(§1.3) — main 직접 mutation 경로 자체가 코드에 존재하지 않음.
- TrustedWriterSet(`config/trusted_writer_set.json:2-26` — contents:write 워크플로 전수
  검증, `tools/ci/verify_trusted_writer_set.sh`)의 의미를 위 4행으로 고정하고,
  certificate-mint.yml의 activation guard = orchestrator inputs(runId/runAttempt/head==H)
  + API 재검증으로 구현한다(계획서 Phase 2).
- **만족 증거**(계획서 [5]): mint 경로의 `refs/heads/main`/`updateRef` 코드 0건 + gateway
  job = read, mint job = write의 job 경계 실측.

### §5 SHA pin 원칙 — 2층 고정, mutable 참조 금지

- 전 workflow 참조는 `@<40-hex>`만 사용한다 — `@main`/branch/tag 참조는 0건(계획서 [8]
  grep 실측 대상). Axiom 내 `.github/workflows/*.yml`의 전 `uses:` 및 org
  `admission-gate.yml`의 전 `uses:`가 대상.
- org ruleset `type: workflows` 규칙의 **`sha` 필드**로 required workflow 정의를 고정한다
  (landing-integrity 패턴 — `canonical_run_graph.md:148-154`; ruleset에 sha 필드를 실어
  타깃 PR이 workflow 정의를 제거/변경할 수 없게 한다).
- **2층 고정** (변이 구분):
  - **Platform SHA** — orchestrator `Archright/.github/.github/workflows/admission-gate.yml`
    @<40-hex>(조직 `.github` repo — Axiom 파티션 밖, §9);
  - **Axiom SHA** — `admission-check.yml`·`certificate-mint.yml`·`runner-pool-acceptance.yml`
    등 reusable workflow @<40-hex>(Axiom repo). orchestrator가 Axiom SHA를 참조하므로
    회전은 양쪽 갱신이 필요하다(§7).

### §6 C2 — closure와 deriver의 역할 구분

> trustedCheckerClosure는 **실행 closure**(H에서 실제 실행되는 코드)이며,
> `derive_checker_closure`는 **별도의 derivation authority**(B에서 H tree를 분석하는
> trusted code, 실행 위치 = B, 분석 대상 = H)지만 **변경 시 동일한 ROTATION 절차를 요구한다**.

- 파일 분리는 불필요하다 — 둘 다 **pin 대상**이며 동일한 **rotation lifecycle**(§7)에
  묶인다. closure pin(`config/trusted_writer_set.json`의
  `trustedCheckerTreeClosure` — `{path: {mode,type,sha}}`, `git ls-tree` 산출; contents
  API `.sha` 금지)과 deriver 소스는 별개 객체이지만, 어느 한쪽이 바뀌어도 ROTATION으로만
  갱신된다.
- deriver 신규 파일: `tools/ci/derive_checker_closure.nim`(계획서 Phase 3 — 기계 도출
  `derived(H)==(B)==pin`, 미해소 → fail-closed §8b).

### §7 rotation lifecycle — 신뢰 교체 절차 하나

- 신뢰 교체(closure pin·deriver·Tier C 실행 코드·orchestrator SHA)는 **하나의 절차**다:
  1. **in-PR closure pin 원자 갱신** — ROTATION PR이 `old pin == derived(B)`(genesis 1회
     허용) ∧ `new pin == derived(H)`를 기계 판정으로 만족하고, subject Δ=0, changed ⊆
     allowlist(§13 3분류), CODEOWNER @architect 승인을 통과;
  2. **orchestrator SHA 회전** — architect의 `Archright/.github` PR로
     `admission-gate.yml`의 `uses:`/ruleset `sha`를 새 Axiom SHA로 갱신(Platform SHA 회전).
- **시스템 증설 금지**: 이 이상으로 구조를 늘리면 신뢰 계층을 Axiom 안으로 되돌리는 것
  (계획서 Out of Scope — "rotation 시스템 확장 금지"). SHA/closure 교체 lifecycle 절차
  하나가 유일한 갱신 경로다.
- **genesis 규칙**: 최초 pin 부재 시 **1회** 초기화만 허용(genesis — `old pin` 부재 상태에서
  `new pin == derived(H)`로 pin 설치), 이후 pin 부재는 무조건 fail-closed(red → merge 차단).
  genesis는 NORMAL·ROTATION 결정(§13)과 무관하게 1회 한정이다.

### §8 fail-closed 계약 2종

**(a) verdict job fail-closed**: verdict job(`admission-check`)은 `if: ${{ always() }}` +
`needs.*.result != 'success' → exit ≠ 0` FAILURE로 구현한다(GitHub 문서화 패턴 —
dependencies가 skip되면 `needs`는 자동 success를 얻어 merge를 막지 않으므로, 항상 실행되는
verdict가 각 dependency의 **실제 결과**를 개별 검사한다). skipped required check가 Success
처리되어 병합이 통과되는 허점(fail-open)은 이로써 차단된다. `always()`는 실행 순서를 흉내내는
장치가 아니라 **fail-closed 장치**다 — 순서 보장은 `needs` DAG와 mtime 기반 관측(계획서 [2])
으로 실측한다. polling/sleep은 금지(순서를 시간으로 추정하는 수단).
- verdict 평가 내용: admission predicate(gateway evidence + certificate + identity equality
  + NORMAL/ROTATION 자격 §13) — B-built `ax merge_cli Pass`(판정부는 B-pinned, §10).
- **U1 (2026-09-27 기록 — 실행 authority 단일화 계획 Phase 0)**: 자격(qualification)
  판정 위치 = **verdict job 단일**(계획서 L118 원안 — 실행 authority 단일화 계획
  black-hawk-carnage-rogue Phase 1 U1 이행). admission 쪽 `ax merge --dry-run`
  (`docs/evidence/canonical_run_graph.md` D4 — dry-run = 관측 기록)은 **관측 전용**으로
  재분류하며, 자격 판정은 verdict job에 일원화한다(단일 writer — Amendment A1).

**(b) deriver fail-closed**: `derive_checker_closure`는 정적 해석 가능한 의존성만 follow하고,
**미해소 의존성**(변수 경로·생성 바이너리·eval·PATH 등) 발견 시 **exit ≠ 0**(red) — "놓치면
인증을 거부"한다. 찾지 못해도 통과하는 "최대한 많이 찾는 도구"는 금지(찾지 못하면 인증 거부이지
pass가 아니다). `run:`·recipe 전수 파싱(`ci/checker.mk` recipe-walk + recipe identity —
판정 toolchain의 실행 열거를 closure에 포함, §10).

### §9 Trust Boundary 2층 + 보호 계층

**Tier C(실행 closure — "무엇을 실행하고 어떻게 판정하는가", 변경 = ROTATION §7):**

- `ci/checker.mk`(신규 — repository_surface.json CONTROLLED 등록 필수, 미등록 시 FROZEN
  default에 의해 ADD FAIL), `tools/ci/derive_checker_closure.nim`(신규, §6),
  `tools/ci/impact_closure_selector.nim`, `tools/ci/proof_reconcile_gate.nim`,
  `tests/gateway/all_gateway_runner.nim`, `nimble.lock`, recipe identity
  (`config.nims`·`config/effects.nims`·`src/gate`의 `config.nims`) + recipe-walk 확정 게이트
  소스의 judge 판정분.
- **workflow YAML은 Axiom closure 밖** — Axiom의 `.github/workflows/*.yml`은 플랫폼 SHA
  소관(§5 — org ruleset이 정의를 고정, orchestrator 회전 시 architect PR)이므로 closure
  members에 포함하지 않는다. **closure 팽창 금지**: H 실행 코드(판정에 개입할 수 있는
  코드)만 Tier C이며, 그 밖의 추가는 계획서 및 본 ADR 개정을 요구한다.

**Tier S(subject — "무엇을 검사하는가", 정규 PR):** `src/`·feature tests 등 정규 PR 변경
범위. subject 변경은 정상(candidate 방식)이고, Tier C 변경은 rotation이다. Tier P =
known_failing(`known_failing_gateway.txt` — CODEOWNERS @architect + witness/cert digest
결속, 계획서 Phase 3 3분류).

**보호 3층:** 1층 = 플랫폼 SHA(ruleset required workflow 고정) → 2층 = closure+deriver
(pin 3중 등식 + fail-closed) → 3층 = rotation(§7 절차). 구조 증설은 §7 금지.

### §10 Gate A 범위 — 판정 toolchain과 subject의 격리

- **판정 toolchain은 B-pinned** — verdict·mint·closure 판정에 실행되는 코드는 항상
  base(B) 버전(`ax merge_cli`·`ci/checker.mk`·deriver — §9 Tier C). **H는 데이터 전용
  input**이다(검사 대상이지 실행 주체가 아님).
- **gateway = 주체 검증**: gateway-shard·gateway-identity-gate·proof-reconcile은 candidate
  실행의 정당성(선택 범위·실행 기록·junit 집합 == 커밋된 landing 정책 집합
  `config/policy/landing_required_gateway_tests.json`(LG-001..014) — `ls` 파생 금지, plan
  Phase 3 재계층화로 과거 `union==86` 집합 계약은 역사적·Decision Record↔executed
  재확인 — `canonical_run_graph.md:75-81`)을 검증한다. 그 **산출물은 데이터로만 소비**된다
  (판정부가 재실행하지 않고 evidence/executed 기록으로 소비).
- **execution correctness ≠ checker correctness**: ROTATION PR의 green은 실행 가능성(새
  checker가 실제 실행되어 통과함)만 증명하며, checker의 올바름은 architect trust root
  (§0.9b Triple-Closure — 뮤테이션 하니스 → `static_gate_scanner.nim` 감사 → 직교 언어
  검증)의 영역이다. green이 checker 정당성을 증명한다고 주장하지 않는다.

### §11 identity 3계층

| 계층 | 판정 | 성격 |
|---|---|---|
| `testedTree == mergeTree == certTree` | verdict job의 착지 전 3중 등식(gateway `testedTreeDigest` → mergeTree 사전 검증 → witness → mint provenance 재검증 후 `certTree` 서명, INV-1/C1 +1) | **게이트 요소** — 불일치 = merge 차단 |
| `strict`(+required status `admission-check`) | GitHub ruleset | **stale 방지** — base 진행 시 BEHIND/BLOCKED(계획서 [3]) |
| `M.tree == certTree` | 착지 후 `git rev-parse M^{tree}` 대조 | **audit observation** — 게이트가 아님; 사후 관찰이 착지를 막지 않으며 불일치는 감사 경보 |

착지 전 게이트는 3중 등식 + strict로 닫혀 있고, 착지 후 관찰은 판정에 재진입하지 않는다.

### §12 스테이징 — 3단계 + ruleset 감지식 merge_cli

1. **PR-1(순수 추가적 구현 PR)**: `workflow_call` 트리거 추가(admission-check·certificate-mint·
   runner-pool reusable 전환), deriver·`ci/checker.mk`·closure pin·본 ADR 도입.
   `pull_request` 기존 경로와 기존 오케스트레이터 유지 — **자기차단 금지**(기존 경로가
   계속 통과해야 bootstrap이 성립).
2. **org 등록**: `Archright/.github/admission-gate.yml` 생성(SHA pin) + org ruleset
   `type: workflows` 등록(sha 필드) + probe(타깃 PR 제거 불가·job 권한 격리·ledger-only 동작).
3. **전환 PR**: ruleset 강제(required_status_checks=["admission-check"] 단일 + strict=true) +
   `merge_cli` 규칙 감지식 재정의 + 기존 pull_request 오케스트레이터·`workflow_run` mint
   제거(post-merge gateway 0 — 계획서 [7]).
- **merge_cli는 ruleset 감지식**: admission-gate required workflow 규칙이 있으면 새 모드
  (required workflow run 검증), 없으면 legacy(현행 경로 유지). **API error는 fail-closed**
  (감지 불능 = 거부), **규칙 부재는 legacy**(저장소에 강제가 없으면 현행 의미 유지). 이후
  probe PR(NORMAL — Tier S만, Δ≠∅) → freshness 실증 → rotation 실증(계획서 Phase 5 4-6).

### §13 의무 연쇄 — A1.2bis · A1.7 · J1–J4 · 3분류

- **A1.2bis(신설 개정)**: ADR-0017 Amendment A1.2(:129-134 — main 착지 `provenRequired(Δ)`
  만 실행)를 개정해, push@main의 runner-pool 실행을 **캐시 권한만**(`ci-bootstrap` + B-캐시
  save — `runner-pool-acceptance.yml:268,:291` 게이트 무변경, J3 soundness 유지)으로
  재분류하고, `provenRequired(Δ)` 선택(UNCERTAIN → full)은 **candidate(PR/선택 event)로만**
  이동한다. push@main의 select 판정 경로(`runner-pool-acceptance.yml:30,:48,:73`)는 caller
  event 판정으로 대체된다. main 착지 검증 의무 자체는 candidate 측 admission이 승계한다.
- **A1.7 체인**: ADR-0017 A1.7(:189-198) 정합 개정 대상목록에 본 개정(A1.2bis)이 추가되며,
  `docs/spec/incremental_ci_tiers_scheduling.md`·ADR-0019의 main 착지 행을 candidate
  admission 경로로 정합 갱신한다(본 ADR과 동시 번들 계획서 Phase 0/2).
- **J1–J4 의무 유지**: `docs/spec/ci_optimization_tcb_judgments.md:17-20` — J1 semantic
  parity·J2 evidence equivalence·J3 cache soundness·J4 worker determinism; VALID =
  J1∧J2∧J3∧J4 전부 PASS(:228-231). push@main 재분류는 J3에 결속되고(캐시 save는 증거가
  아니며 실행-의미론 입력도 아님 — :19), candidate 전환으로 생기는 실행 경로 변경은 J1/J2
  판정 대상이다.
- **3분류: Tier C / Tier P(known_failing) / Tier S(subject)** — C·P 변경 = ROTATION·
  승인 대상, S = 정규 PR. **closure 멤버 추가·제거 자체가 승인 대상**이다(Tier C 각 파일은
  CODEOWNERS @architect — 계획서 Phase 0; 멤버 변경 = rotation PR 필수).

### §14 ledger 동시성 계약

concurrent mint의 직렬화는 **기존 ledger writer 메커니즘에 위임**한다(새 trust authority
를 만들지 않는다). **감사 완료(2026-09-26)**: append는 REST Git Data API의
fast-forward-only CAS(`ledger_side_ref.nim:401-402`, `PATCH refs/heads/axiom/certificates`
`force:false`)로 **안전성 확보** — 동시 경합 시 422 원자 거부로 lost update·중복 엔트리
0건. 단 **liveness = LIVENESS-DEFECT**: 재시도 루프 0회였으므로 경합 패배 mint가
즉시 실패하고 재발화 없이 `certRequired`로 PR이 차단된다. 계약: **bounded
retry-on-conflict**(≤4회, conflict 상황만 재시도 — blob은 RFC-8785 결정론이라 멱등,
tip 재读后 재검증 포함, 소진 시 fail-closed)를 기존 `appendCertificate` 내부에 구현한다.
동일 토큰·동일 TrustedWriterSet·동일 REST 표면 — 새 trust authority 0건, `force:false`
불변식 유지. (`tests/verification/test_attestation.nim` concurrency 케이스로 검증.)

## Consequences

**긍정:** main 변경 주체가 native MERGE 하나로 단일화되고(M-B 실측과 정본 선언 정합),
gateway 실행이 candidate admission에 결속되어 post-merge 재검사가 구조적으로 제거된다.
execution identity(required workflow @SHA)와 freshness(strict)를 GitHub가 강제하므로
Axiom이 중복 구현할 authority가 없다(중복 authority 0건 — 하지만 2권위는 동일 실행의 서로
다른 플랫폼 제어이며 "중복"이 아니다). mint가 admission DAG에 포함되어 certificate가 착지
전 발급되고 predicate의 필수 증거로 소비된다. write boundary는 token이 아닌 계약(B-pinned
code + H data-only + M-B)으로 보장된다.

**부정(residual):** Landing App CAS는 정본 경로가 아니게 서술만 정정되고 운영 실측은
없는 상태로 유지(DEBT#462 무결합). strict는 GitHub 플랫폼에 위임되므로 Axiom 측
fail-closed 실측(계획서 [3]) 전까지 freshness 차단은 관측 대상이다. org ruleset·조직
`.github` repo 설정은 agent가 아닌 architect 절차(Phase 1 org 작업)를 요구한다.
`always()` verdict는 성공/실패 양방향 관측(계획서 [2])으로만 실증 가능.

## 잔여 한계 (Residual Limits)

- **계획서 실증 의존**: 4중 등식·freshness 차단(BEHIND/BLOCKED)·post-merge gateway
  0·mutable ref 0은 착지 후 운영 실측(계획서 Completion Evidence [0]-[9]) 전까지
  주장이 아닌 예정 계약이다. 본 ADR의 green = 구현 PR의 CI 성공은 bootstrap이며
  완료 증거가 아니다.
- **platform SHA 회전 인간 의존**: orchestrator/ruleset 갱신은 architect PR 절차이므로
  rotation 원자성의 플랫폼 측은 GitHub 기능에 위임된다(Axiom이 강제하지 않음).
- **범위 밖 (계획서 Out of Scope)**: DEBT#462/Landing App CAS 도입, rotation 시스템 확장,
  closure 팽창, Layer 0/Layer 1 축소, B-캐시 writer 제거·캐시 키 재설계(J3), PR 측 B-빌드
  3회 중복, J3 circularity 선행 FAIL, 릴리즈 full L2(M-E), landing-integrity·측정 평면,
  freshness의 Axiom 재구현. AGENTS.md·`src/gate/runners/import_encapsulation_gate.nim`·
  `config.nims`(§-1)는 불변.

## Amendment A1 (2026-09-27): §3 certificate·발행 authority 보강 — 실행 authority 단일화 계획 Phase 0

> 실행 authority 단일화 계획(black-hawk-carnage-rogue, rev.7)의 Phase 0 ADR 연동이다.
> 본 amendment는 §3(certificate 의미)·§14(ledger 동시성)의 해석을 보강한다 — 본문을
> 다시 쓰지 않으며, append로만 남는다. 근거 = 계획서 "배경(실측 + 반박 판정)"·"D6
> 원자성 규칙(3분기 reconciliation)"·"설계 원칙(ADR-0026 — 규칙 1–10 + 6문항)".

1. **prepare(발급)는 gateway 무관**: mint의 `prepare` cert 발급은 gateway 결과와
   독립적으로 진행된다 — 선행 조건 = admission 완료(`needs: [admission]`) + admission
   lane B-결속 바이트 소비 (C5/C1 계약 개정 2026-09-29 — write-tier 자체 빌드 계약
   예외 C1 폐기, `docs/adr/0026-execution-authority-unification.md` §3 개정문;
   D1행 해소 `docs/evidence/canonical_run_graph.md:106`).
   gateway와 병렬이며, 발급 authority = single build site(admission lane) 1개(계획서 [B1]).
2. **publish(ledger append) = gateway+prepare 시간·데이터 이중 결속 후 발행**:
   `needs: [prepare, gateway]` — **시간 인과**(보조): append 타임스탬프 ≥
   max(gateway, prepare).completed; **데이터 인과**(핵심 — 같은 후보의 성공임 증명):
   (a) gateway run.headSha == cert.headSha ∧ (b) gateway canonical tree identity ==
   re-derived cert.certTree ∧ (c) gateway conclusion == success. (b)는 "digest가
   같다"가 아니라 **동일 canonical identity 검증**이며 — 기본 해 = tree-identity
   라인의 canonical tree SHA(`testedTreeDigest` — `IDENTITY: OK … tested tree ==
   merge candidate tree` 실측 계열) — semantic domain 확정은 Phase 2 구현의 선행
   게이트다(확정 전 (b) 구현 금지, 계획서 위험 ⑤). append provenance = {cert_sha256,
   gateway run_id, gateway headSha, gateway tree identity, conclusion=success,
   field-binding 통과}.
3. **CAS 3분기 reconciliation**: publish append — 성공 → 엔트리 1 / 실패 → 재조회
   → record 재계산 정당성(§14 유지) 성립 → PASS(0) / 불성립 → FAIL-CLOSED —
   재시도 루프 내부의 reconciliation이며, §14의 bounded retry-on-conflict(≤4회·
   conflict 상황만)·`force:false` 불변을 유지한다(소진 시 fail-closed).
4. **cert ≠ landable**: certificate는 bounded 증거((B, H, evidence)에 대한 서명)이자
   **subject-certification authority**일 뿐 — 착지 가능 객체(landable)가 아니다.
   착지 authority = native MERGE 단일(§1 M-B 유지) — cert 발행 여부는 착지 여부를
   결정하지 않는다(반박 C1~C6·cert authority 판정).
5. **verdict append 폐기**: verdict·post-verdict의 ledger append는 **발행(publish)
   단일 writer 위반**으로 폐기한다 — verdict는 판정과 required status context 생산
   (§8a)만 담당하고, 원장 append는 publish 단일 경로만 존재한다(계획서 [B1]
   "ledger record → authority = publish 단독 · append exactly-once").
6. **실측 앵커 (bounded historical record)**: side-ref 원장(2026-09-27 측정 —
   ledger tip `7b2cd8363`, 기준 origin/main `8e027c065`) **104건 중 12건 미착지
   subject cert** — cert 발행(104건)이 착지(92건)를 보장하지 않음의 실측. 원장은
   append-only이므로 수치는 계속 증가하며, 이 값은 측정 시점의 bounded record다.

## Amendment A2 (2026-09-27): §13 회전 allowlist 자기모순 해소 — minimal consistent set 확정

> Agent-A 발견(PR #295 — 2026-09-27 STOP-BLOCKED)에 근거한 개정이다. §13 3분류의
> 회전 allowlist가 active 게이트(landing-integrity ATOMICITY · check-debt · 회전
> 테스트 동반)와 자기모순을 이뤄 회전 PR이 **구조적으로(by construction)** 통과
> 불가능함을 확인하고, allowlist를 최소 정합 집합으로 개정한다. 본문을 다시
> 쓰지 않으며, append로만 남는다.

1. **자기모순 3단계 (실측 인용)**:

   - **① ATOMICITY (org workflow)**: `Archright/.github/.github/workflows/
     landing-integrity.yml` Job 2 —
     "if head modifies either file, both must be in the PR diff (else fail-closed)"
     (`.github/workflows/admission-check.yml`의 blob sha가
     `trusted_writer_set.json`의 `trustedAdmissionWorkflowSha`와 일치해야 하며,
     tws ↔ admission-check.yml은 **동반 수정 강제** 페어). 회전 pin
     `trustedCheckerTreeClosure`는 `config/trusted_writer_set.json` **내부**
     (:42)에 있으므로 **모든 회전 PR은 tws를 건드리고 → `admission-check.yml`
     동반이 필수**가 된다.
   - **② 현행 allowlist (§13)**: `closure pin@B keys ∪ docs/adr/** ∪
     config/trusted_writer_set.json`(구현: `src/cli/merge_cli.nim`
     `rotationAllowlistOk` :758-768, `RotationPinBPath` :122, `RotationAdrGlob`
     :124 — pin keys는 비-YAML closure members만이며 워크플로 경로를 포함하지
     않는다). `admission-check.yml`·`certificate-mint.yml`·회전 동반
     데이터·회전 테스트는 pin keys에도 docs/adr/**에도 **없다** → 허용 불가.
   - **③ 결론**: active 게이트 아래 회전 PR은 `allowlistOk=false →
     ROT_ALLOWLIST → qualification NONE → verdict FAIL`이 **성립불능** —
     실측: 게이트 활성화 이후 회전-class PR 착지 **0건**(Agent-A 검증) +
     PR #295(2026-09-27) STOP-BLOCKED(verdict 로그
     `allowlistOk:false, changed:[9 files]` — admission-gate 런 36306636538).
     추가 순환: closure 멤버 코드 변경은 check-debt 게이트가
     `data/architecture_debt.json` 재생성을 강제하고(GATES_FAST), 회전 테스트가
     자연 동반되는데 이들도 allowlist 밖 → 동일 교착.

2. **개정 — 회전 변경 허용 집합 (minimal consistent set)**:

   ```
   rotated 변경 허용 집합 = closure pin@B keys (== trustedCheckerTreeClosure)
     ∪ docs/adr/**
     ∪ config/trusted_writer_set.json (pin 자체)
     ∪ 신뢰 워크플로 페어: .github/workflows/admission-check.yml,
        .github/workflows/certificate-mint.yml
        (근거: landing-integrity ATOMICITY가 admission-check.yml을 pin 페어로
         강제 — 현 allowlist와의 자기모순 해소; 이 둘은 gate의 판정·발행 배선이며
         SHA-pin(callee)·ATOMICITY·trustedAdmissionWorkflowSha 쌍으로 이미 보호)
     ∪ 회전 동반 데이터: data/architecture_debt.json, data/nimtry_baseline.json,
        data/quality_gate_baseline.json (2026-10-14 추가 — quality-gate checker의
        Static-First 래칫 baseline; 멤버 파일 정직 개선 + scoped 재동결
        (--files --update-baseline)이 클로저 회전과 자기 baseline을 동반 —
        nimtry_baseline과 동일 mandatory-companion급, nimtry_evaporate §3.0-9 선례)
        (근거: check-debt가 closure 코드 변경에 arch anchor 동반을 강제 —
         없으면 push 자체가 불가능한 순환 모순)
     ∪ 회전 동반 테스트: tests/cli/test_merge_cli.nim,
        tests/verification/test_attestation.nim
   ```

3. **해석 확정**:

   - **(i) NON-member production `src/` 변경은 여전히 allowlist 밖** — 회전으로
     흘러들어오지 못한다(기존 의도 유지: 회전은 기존 closure pin의 갱신·문서화
     경로이며 허용 집합이 범위 팽창 수단이 아니다).
   - **(ii) allowlist는 closure 변경(closureEqual=false)이 실제 발생한
     ROTATION 경로에서만 평가**된다 — NORMAL 경로(closureEqual=true)에서는
     vacuous-true(`adjudicateRotation` :784-791 — ①② 미평가). 즉 NORMAL PR의
     정상 변경(예: `certificate-mint.yml` 구현 변경이 closure에 영향 없는 경우)은
     이 allowlist의 영향을 받지 않는다. **(Amendment D, 2026-10-10: ①②만
     vacuous로 유지 — ④(pin anchor)는 NORMAL을 포함한 전 경로에서 사실로
     평가되며 그 거부는 Pass 2.75가 단일 소유한다.)**
   - **(iii) 다른 companion path 추가**는 향후 회전 실측 시 동일한 개정 경로
     (본 amendment 스타일)로만 한다 — 이번 목록은 실측된 교착 3종(ATOMICITY
     페어 · check-debt · 회전 테스트)에 한정한 최소 집합이다.
   - **(iv) 코드 동반 변경 필요**: 본 amendment는 ADR 텍스트 개정이며, 코드 측
     `src/cli/merge_cli.nim` `rotationAllowlistOk`(:758-768)는 현재 pin@B
     keys ∪ docs/adr/** ∪ pin 파일만 허용한다 — **개정 목록과 불일치하므로
     상기 6개 경로를 추가하는 코드 확장이 후속으로 필요하다**(이 문서 착지만으로
     회전 게이트가 열리지 않음). 코드 변경은 본 ADR 개정 경로로 판정되며,
     코드 목록이 ADR 목록과 정합될 때까지 회전 PR은 여전히 fail-closed다.

## Amendment A (2026-09-28): M-B 재봉합 — GitHub native MERGE 단일 authority · thin actuator (plan rev.7 trust-layer-isolation Phase 0)

> trust-layer-isolation 계획(rev.7) Phase 0의 ADR 연동이다. §1 M-B를 재봉합
> 하고 착지 실행 경계를 **단일 native-merge PUT의 얇은 actuator**로 축소한다.
> 본문은 다시 쓰지 않으며 append로만 남는다. 근거 = 계획서 Phase 0 (ADR-0025
> Amendment (M-B 재봉합 8불변), 얇은 actuator, 4보강 A1–A4, E1–E3).

**1. M-B 재봉합 — 8불변** (§1 M-B를 이 8개로 재확정한다):

```text
1. Landing App은 main ref를 변경하지 않는다
2. Axiom verdict는 merge eligibility만 판정한다
3. required check는 정확히 하나다
4. strict freshness 하 verified_B == current_main_tip
5. merge strategy = merge commit
6. parents(M) = [B, H]
7. tree(M) == certTree
8. MERGE 이후 landing qualification/proof를 재실행하지 않는다.
   post-merge workflow는 continuity/audit observation만 수행하며
   landing authority나 acceptance authority가 아니다.
```

- 불변식 1 실행: `src/cli/landing_cli.nim`의 CAS 경로 전부 제거 —
  `updateRefs`/`beforeOid`/`fetchGitHubMergeTree`/`createCasCommit`/
  `createTempRefAt`(및 GraphQL read `resolveMainRefIdentity`·temp-ref
  DELETE) 0건 (E1 (a)-(c)). `config/app_landing_binding.json`·Landing App
  자산은 **standby/non-authoritative** 서술로만 정정 (DEBT#462 무결합 —
  계획서 Out of Scope 유지).
- 불변식 2·3·4: verdict job `admission-check` 단일 required check — Axiom
  verdict는 eligibility만 판정(GitHub required-check acceptance semantics는
  플랫폼 소유 — R13b), freshness는 GitHub strict에 위임.
- 불변식 5-7: 단일 actuation `PUT /pulls/{n}/merge` (merge_method=merge) —
  H ⊇ B (compare "ahead") + main tip == B 하에서 parents(M)==[B,H] ∧
  tree(M)==tree(H)==certTree가 기계적으로 성립. behind/identical/diverged는
  fail-closed abort (로컬 merge-tree 구성 금지 — E1 (c)).
- 불변식 8: post-merge Pass 7/8(merge-commit shape · verifyContinuity)은
  **관찰**일 뿐 — 재실행 qualification/proof 없음, fail-visible backstop (A4).

**2. 얇은 actuator — merge API `sha` = head pin only, base CAS 없음**:

- `PUT /repos/{o}/{r}/pulls/{n}/merge` body = `{merge_method: "merge",
  sha: <headSha>}` — `sha`는 **HEAD PIN ONLY**. merge API에는 base
  compare-and-swap이 **없다** (과거 CAS 전제였던 beforeOid=⊥).
- base 결속 실질 보장 = **A1**(비-bypass actuator identity) + **ruleset
  strict**(merge 평가 시점 enforcement). A3(`cert.baseSha == main tip`
  preflight, `fetchMainTipOid` + `compareStatus`)는 **관측**이며 원자적
  freshness guarantee가 아니다 — 관측과 평가 사이 main 이동은 GitHub
  strict가 merge 시점에 차단한다 (계획서 Phase 0 "merge API `sha` = head
  pin only").
- 자기 소유 merge authority = 0 (E1 (d)): self-ref mutation·local
  merge-tree·local CAS 전부 부재 — `src/cli/merge_cli.nim`의
  `performMerge`가 유일 actuation (`runMergeCli`/`runMergeActuatorCli`/
  `runLandingFlow` 3개 호출부는 전부 이 한 proc으로 수렴).

**3. A1 — actuator identity**:

- 불변식: **`landing actuator identity ∉ effective bypass actors`**.
- 현행: merge 호출은 `GITHUB_TOKEN`(env, ruleset 적용 identity) 사용 —
  Landing App installation token·`config/app_landing_binding.json` 미사용
  (CLI가 이 파일을 읽지 않음). bypass actors 실측: production main ruleset
  (id=20303214) `bypass_actors = []` (`docs/evidence/canonical_run_graph.md`
  D1) — 현재 충족. bypass membership 판정은 플랫폼 소유이므로 Axiom 코드가
  재구현하지 않으며, E3 실측(`bypass_actors` 재확인)·A2 사전실측으로만
  결속한다.

**4. A2 — 사전 ruleset 실측 fail-closed (R14)**:

- merge PUT **이전에** live rulesets(`GET /repos/{o}/{r}/rulesets`,
  `fetchRulesets`)를 읽고 다음을 실측하지 못하면 abort (fail-closed):
  `required_status_checks[]`에 `context == "admission-check"` ∧
  `strict_required_status_checks_policy == true` ∧
  `integration_id == canonical source integration` (**15368** — GitHub
  Actions app id; production ruleset live 실측값,
  `canonical_run_graph.md:133`).
- **integration_id는 필수 조건** (R14): entry에 integration_id 미설정 =
  E3 FAIL — Axiom 측 해석 검사만으로 source binding을 성립시키지 않는다.
- 구현: `merge_cli.rulesetAdmissionRequirementOk` (순수 판정) —
  `runMergeActuatorCli`·`runMergeCli`·`landing_cli.runLandingFlow`의 PUT
  직전에 호출, 불충족 = `RULESET_UNBOUND`/`A2_UNBOUND` (abort).
- canonical integration id는 `merge_cli.CanonicalCheckIntegrationId`
  상수(15368)로 결속 — `RequiredChecks`/`RequiredWorkflowIds`와 동일한
  code-side SSOT 미러 패턴이며, 정책 SSOT(`merge_admission.json` v1.9.0
  서술)와 이 ADR에 동일 값을 이중 기재한다. config 필드 신설은
  `proof_unit_consistency_gate` (f.3)류 Tier C cross-invariant 확장을
  요구하므로 Phase 0 범위 밖 — 상수+SSOT 이중 기재를 정합 경로로 채택.

**5. A4 — post-merge continuity audit 유지**:

- `resolveMergeShapeApi(L)` + `verifyContinuity(L, cert)` (Pass 7/8) —
  관찰일 뿐 authority 아님 (불변식 8). 불일치 = fail-visible (journal
  `CC_ERROR`/`LANDED_OBSERVATION_MISMATCH` 기록 후 비-zero 종료), 착지는
  이미 발생했으므로 landing 판정에 재진입하지 않는다.

## 연쇄 갱신 문서 (동시 번들 — 계획서 Phase 0/2)

- Amendment A (2026-09-28, 본 절) 코드 결속: `src/cli/landing_cli.nim`
  (CAS 경로 제거 · thin actuator), `src/cli/merge_cli.nim`
  (`performMerge` 복원 · A2 `rulesetAdmissionRequirementOk` ·
  `CanonicalCheckIntegrationId=15368` · rotation allowlist 확장),
  `config/policy/merge_admission.json`(v1.9.0 — native MERGE 서술 전환),
  `config/app_landing_binding.json`(standby/non-authoritative 서술 전환)

- `docs/spec/merge_admission_controller.md` — :33,:195 Owner 결정 #11 서술을 CAS-only로
  정정, §11 착지(계약 자연 수렴 — native MERGE) 문구 정합
- `config/app_landing_binding.json:5` — CAS-only 서술 정정
- `docs/spec/repository_surface_contract.md` — Owner 결정 #11(:144-160) 문구 정정 + 신규
  결정 기록(#17 — 본 ADR)
- ADR-0017 — A1.2bis 개정 추가 · A1.7(:189-198) 대상목록 갱신
- ADR-0019 · `docs/spec/incremental_ci_tiers_scheduling.md` — main 착지 행을 candidate
  admission 경로로 정합 (A1.7 체인)
- `docs/evidence/canonical_run_graph.md` — :73 push@main 발화 행을 "캐시 권한만"으로 갱신,
  required workflow(admission-gate) 행 추가
- `docs/spec/ci_optimization_tcb_judgments.md` — 본 ADR 참조 추가(J3 결속 · candidate
  전환 J1/J2 대상 명시)
- 신규 — `ci/checker.mk`·`tools/ci/derive_checker_closure.nim`(Tier C 실행 코드),
  config/trusted_writer_set.json `trustedCheckerTreeClosure` pin(ROTATION 절차로 갱신)
- 담당 등록(메인 에이전트): `config/repository_surface.json` CONTROLLED —
  `"ci/checker.mk"`, `"tools/ci/derive_checker_closure.nim"`,
  `"docs/adr/0025-gateway-landing-authority.md"`(FROZEN default = 미등록 시 ADD FAIL)

## Amendment B (2026-09-29): A1.2bis push@main 캐시 권한 폐기 — workflow_run 단일 씨딩 writer · tree-OID 키 결속

> CI 정본화 계획(① pre/post 중복 계산 제거 · ② 머지 후 CI 최소화 · ③ GitHub 중복 재구현
> 제거) 승인에 근거한 개정. A1.2bis(:306-311)의 "push@main = 캐시 권한만" 구조를
> **트리거 자체 폐기**까지 진행한다.

1. **push@main 트리거 폐기**: `runner-pool-acceptance.yml`의 `push: branches:[main]`과
   ci-bootstrap의 push 전용 컴파일·B-save·save-side 지문 manifest 단계를 제거한다 — 머지
   이벤트의 Actions 실행 = 0(착지 = 순수 GitHub 네이티브 ref 이동).
2. **단일 씨딩 writer 이관**: B-cache write 권한은 `workflow_run` 트리거
   `ci-cache-publisher`로 이관한다(trigger = admission-gate run completion, job-level
   `cache-mode: write`). 퍼블리셔 검증 체인(run path 결속 · conclusion success · fork 제외 ·
   tree OID를 run object에서 도출 · 아티팩트 manifest sha256 대조)을 통과한 **가속 산출물만
   재발행**하며 계산·판정·테스트 0 — J3(캐시 = 가속, 증거 아님) 유지.
3. **tree-OID 키 결속**: B-cache identity를 commit-SHA → tree-OID로 결속한다(동일 트리 = 동일
   키 — M6 결정성과 정합; synthetic merge ↔ landed merge 간 false MISS 소거 = 중복 재컴파일
   제거의 근본 원인 철폐).
4. **잔여 위협·실패 모드**: `docs/spec/github_delegation_residuals.md`에 기록(§0.5). Phase 0
   linchpin 실증(workflow_run이 admission-gate 완료에 발화하는가) 실패 시 push@main
   재발행 fallback(계산 0 · 초 단위 I/O 1)으로 회귀한다 — 결정 권한은 본 amendment.

## Amendment C (2026-09-30): landingFloor 비준 공백 · EMPTY 모순 해소 · mint [B2](c) 3-way identity 재조정 메모 · selector B-pin 잔존 신뢰 경계 (PR-B epoch cutover 문서 트랙)

> 계획 "검증 비용 = 증명 필요 집합"(3-PR, 본 worktree = PR-B)의 문서 트랙 개정. Epoch 기록:
> `docs/evidence/epoch_record_oracle_select_2026-09-30.md`(Freeze `ci-frozen-2026-09-30` / Record / Tombstone — §2.5 단계 1–3).

### §C.1 floor 면제 비준 기록 — 비준 의사결정 0건 + 표면 모순 해소

1. **비준 공백**: `landingFloor=true`(`tools/ci/impact_closure_selector.nim:1414` — 병렬 편집 중 라인 이동 가능)에 대한 비준 의사결정은 **0건**이다 — 2026-09-30 grep 실측: `landingFloor` 토큰은 오직 `tools/ci/impact_closure_selector.nim`에만 출현하며 `docs/adr/*`·`config/decision_binding.waiver.*` 0 hits. 이 하드코딩은 계획(Phase 2)과 N+6 SL-10 런 실측(`landingPolicyFloor=true` — `docs/evidence/canonical_run_graph.md:314`)으로만 존재했고, 정식 비준 기록(ADR 문단·waiver 항목)이 없었다. 본 절이 그 사실을 명시적으로 기록한다.
2. **표면 모순 (EMPTY 의미 상반)**: 동일 "EMPTY" 조건에 대해 — `ci/checker.mk:191,:204-205`("Junit 없음(junit_files=0, EMPTY 모드 포함) = 전 항목 not-executed → FAIL — 착지 집합은 스코프 선택기와 무관하게 실행되어야 한다", EMPTY=FAIL·fail-closed) vs `.github/workflows/runner-pool-acceptance.yml:661-666`("mode=none / selected-W8-미포함: shard 0개 실행 → identity-gate는 통과 처리 (EXPECTED_GATEWAY_TESTS='EMPTY')", EMPTY=PASS·fail-open).
3. **해소**: **"영향-공집합 후보는 floor 면제"** — 검증된 oracle evidence(`derivedEmpty=true`, `axiom/oracle-evidence/v1`)로 영향-공집합이 증명된 후보만 floor에서 면제되고, 그 외 candidate는 floor(무조건 착지-잡 실행)가 유지된다. 두 게이트 표면의 관찰 조건이 분리되어 모순이 해소된다(ADR-0017 Amendment A2.4).
4. **SL-09 승격 전 선행 조건**: 조건부식 교체 후 **SL-09 승격**(scope_sl09 게이트 — gateway-shard×8·gateway-identity-gate·proof-reconcile 발화 복원) 전에 두 표면의 EMPTY 의미를 단일화(정합)해야 한다 — DEBT#470으로 등재.

### §C.2 mint [B2](c) 3-way identity 재조정 메모 (SL-0713/SL-09 승격 전 조건)

- **현황**: `testedTree == mergeTree == certTree`(본 ADR :282 — INV-1/C1; `src/cli/cert_cli.nim:1113`) — mint-publish [B2](c)는 candidate마다 certificate 발행을 요구한다(certRequired — selector 주석: "mint-publish [B2](c) fail-closed rejects it"). 현행 floor(`landingPolicyFloor=true`)는 "모든 candidate에서 gateway lane 실행·cert 존재"를 무조건 보장하여 [B2](c) 결속을 유지했다.
- **재조정 필요**: PR-B의 조건부식(`lgPolicyNonEmpty ∧ ¬oracleDerivedEmpty`) 전환 후, derivedEmpty 경로(mode=none, docs-only) candidate는 착지-잡을 실행하지 않는다 — mint-publish [B2](c)가 mode=none candidate에 대해 **어떻게 유지되는지**(① 증명 필요 집합 ∋ docs-only candidate의 cert 발행 경로 유지 여부, ② floor 면제 candidate의 cert 면제 근거, ③ 3-way identity 등식의 mode=none 대응)를 **SL-0713/SL-09 승격 전에 재조정 메모로 확정**해야 한다. **3문항 확정 완료 — §C.5(2026-10-01, SL-0713 epoch N+7 승격 트랜잭션 동봉)**. 3-way identity 등식 자체는 무변경 유지(변경 시 별도 ADR).

### §C.3 잔존 신뢰 경계 등록 — selector 후보-트리 빌드 (B-pin 범위 밖)

- selector(`tools/ci/impact_closure_selector.nim`)는 select job에서 **런타임에 후보 트리(candidate checkout)로부터 컴파일**된다. `trustedCheckerTreeClosure`(본 ADR §6)가 소스 blob을 B-pin하나(selector blob `cc85db420…`), **binary의 생성 주체는 후보 트리**이다. "오라클·게이트 바이너리를 B(base sha) 전체 trusted tree에서 컴파일"하는 3-PR 계획에서 **selector 자체의 B-pin은 범위 밖 유보**로 등록한다(DEBT#467).
- **fail-open 아님 명시**: selector는 결정 보조(decision envelope — oracleEvidence 소비·검증만, 자기참조 금지 — ADR-0017 A2.1)이며, 검증 verdict authority가 아니다.

### §C.4 연결 (계획 Phase 3 항목 (0))

- Freeze/Record/Tombstone: `docs/evidence/epoch_record_oracle_select_2026-09-30.md` §1–3 — freeze tag `ci-frozen-2026-09-30`(annotated → `56a7ab1ef`), record(runner-pool blob `1c342f0a…` · pin `fa576733…` 일치), tombstone(landingFloor=true 종료 선언 — 우회·면제·required-check 제거 아님).
- DEBT#466(b+ Known-branch witness) · DEBT#467–470 · ADR-0017 Amendment A2 · C15 부록 D(`docs/spec/canonical_execution_semantics.md`) · tiers Amendment(`docs/spec/incremental_ci_tiers_scheduling.md`).

### §C.5 mint [B2](c) 3-way identity 재조정 메모 — 확정 (2026-10-01, SL-0713 승격 선행 해소)

> §C.2 자리표시의 3문항 확정. 기록 위치 근거: `docs/evidence/epoch_record_oracle_select_2026-09-30.md:55`("mint [B2](c) 재조정 메모: ADR-0025 Amendment C §(5)"). 3-way identity 등식(`testedTree == mergeTree == certTree`, :282 — INV-1/C1) 자체는 무변경 — 아래는 등식이 mode=none candidate에서 **어떻게 유지되는지**의 대응 확정.

1. **① 증명 필요 집합 ∋ docs-only candidate의 cert 발행 경로 — 확정(유지)**: `certRequired`(`config/policy/merge_admission.json` v1.6.0)는 mode와 무관하게 **모든 candidate**에 적용된다 — `MergeAdmissible` Pass 2.96은 `certRequired`에서 NO_CERT(missing ≠ valid empty)를 판정하며(`src/cli/merge_cli.nim:717,:1184,:1200,:1656`) mode=none 면제는 landingFloor(착지-잡 실행 의무)에만 적용된다(selector `landingFloor = lgPolicyNonEmpty ∧ ¬oracleDerivedEmpty` — `tools/ci/impact_closure_selector.nim:1542`). docs-only(derivedEmpty) candidate도 증명 필요 집합에 잔존하고 mint 체인(prepare → publish — org admission-gate caller가 stage별 1회 호출, publish는 prepare+gateway 완료 후 DAG)이 candidate마다 발화한다 — verdict K 체인 `admission ∧ mint-prepare ∧ mint-publish ∧ gateway` 4-leg 전부 유지(epoch_record_oracle_select:54 · canonical_run_graph.md:328 실측).
2. **② 면제 근거 — floor 면제만, cert 면제 없음**: floor 면제의 유일한 근거 = 검증된 independent oracle evidence(`axiom/oracle-evidence/v1` — 5축 전부 deltaAbsent/unchanged → `derivedEmpty=true`, `derivationDigest == sha256(정본 문서 minus derivationDigest)`; ADR-0017 Amendment A2 비준 2026-09-30; selector `loadOracleEvidence` 검증 실패 = exit 2 full 폴백 — mode=none 불발행, fail-closed). 면제 범위 = **gateway lane 실행 의무(착지-잡)뿐** — certificate 의무는 어떤 경로로도 면제되지 않는다(certRequired 무조건; Pass 2.96 mode 무관). 실측 근거: CE#17 mode=none envelope(`decision.json = mode=none ∧ ciBootstrap=false ∧ landingPolicyFloor=false ∧ derivedEmpty=true` — epoch_record_oracle_select:162).
3. **③ 3-way identity 등식의 mode=none 대응 — 확정(등식 유지 · lane 결론 leg 재해석)**: mode=none candidate에서 등식의 세 고리는 mode 무관하게 **같은 subject에서 파생**된다 — (a) `testedTree` = select job의 `tested-tree-digest`(`HEAD^{tree}` — runner-pool-acceptance.yml:209 "mode(both/none)와 무관한 invocation identity", scope_sl10 게이트 발화 — 실측: mode=none 런 36770241367도 `tested-tree-digest` 산출), (b) `mergeTree` = tree(github.sha) by-object 재유도(P5), (c) `certTree` = 동일 subject(B, G) 서명. **[B2](c) lane conclusion leg의 mode=none 대응**: lane의 판정 job = `gateway / select`(candidate마다 실행 — mode=none도 exit 0 정상 판정). 실측(런 **36770241367** — S #409, mode=none 풀 사이클): `gateway / select=success` · `gateway / ci-bootstrap=skipped` · `gateway / gateway-shard=skipped` · `gateway / candidate-build-arm=skipped` · `gateway / gateway-identity-gate=skipped` · `gateway / proof-reconcile=skipped` — **select가 내린 mode=none 판정의 착지-잡은 jobs API에 conclusion=skipped로 materialize**한다(상태: completed/결론 skipped). skipped lane job = mode=none 판정의 **기대 결과**이지 lane 실패 아님. **엔진 시행**: certificate-mint.yml (P6)이 이 대응으로 갱신(2026-10-01, SL-0713 승격 PR 동봉 — G2b path 1 승격 클레임): (i) lane 존재(≥1) ∧ (ii) `gateway / select == success` ∧ (iii) lane job 전부 conclusion ∈ {success, skipped} ∧ (iv) skipped 존재 시 — B-tree epoch manifest `notYetImplementedSlices ∋ SL-09`(미승격 slice 잡) **또는** ci-select-decision envelope `mode == "none"` **기계 검증 필수** — 부재/불일치 = fail-closed. 비-mode=none candidate의 skipped·실패·부재는 전부 차단(검사 약화 아님 — §C.1 해소와 정합). SL-09 승격 후에는 (iv)의 SL-09 항이 사라지고 mode=none 항만 남는다.
4. **C11 실증 의무**: 위 대응은 승격 후 mode=none candidate 1건의 verdict K 체인 성공으로 운영 실측 확정한다(docs-only acceptance PR — 본 메모의 최초 실소비자). 실패 시 fail-closed(발행 차단 → NO_CERT 착지 차단)로 표면화되며, freeze epoch(`ci-frozen-2026-09-30`)로 롤백 판정한다 — 묵시적 회귀 없음.

## Amendment D (2026-10-08): publisher lane identity 게이트 재범위화 — freshness는 플랫폼 권한으로 위임, executed-subject identity만 유지 (R10 재판정 · 결정 바인딩)

**결정**: `ci-cache-publisher.yml` lane 검증 게이트의 `tree(manifest build_sha) ==
tree(run.head_sha)` 등식을 **실행 주제 identity 결속**으로 재범위화한다. 이 Amendment가
`docs/spec/github_delegation_residuals.md` R10 제거 조건의 "별도 결정 바인딩"이다.

- **제거되는 판정**: "content identity not landable as tested"(ahead invariant — PR
  최신성·착지 가능성 판정). 이는 GitHub ruleset(`strict_required_status_checks_policy`)
  + merge queue의 권한이며, 메모 계층이 이를 재구현하는 것은 authority leakage였다
  (권한 경계: "각 계층이 자기 권한 밖의 의미론을 제거". 선례 — `merge_cli.nim`
  "PROVENANCE only, not a freshness decision", `landing_cli.nim` "tip==B observation
  removed — platform delegation").
- **유지되는 판정 (크로스-트리 오염 방어 — 무력화 금지)**: manifest build_sha가 이 run이
  실제로 빌드한 주제임을 GitHub 사실로 결속한다 — merge_group: `build_sha ==
  run.head_sha`(큐 커밋 G) / pull_request: `run.head_sha ∈ parents(build_sha)`(합성
  병합 커밋). 트리 OID content-addressing · run object 앵커 · per-file sha256 ·
  소비자 P2-3(a) identity 재유도 + provenance probe는 전부 불변.
- **키 바이트 동일성 보장 전이**: 종전은 트리 등식이 checkout(head_sha)의 레시피/script
  파일과 build_sha 트리의 동일성을 암묵 보장했다 — 재범위화 이후에는 keygen 전에
  build_sha 트리로 detach checkout해 보장한다(base 경로의 "switch checkout to build
  tree"와 동일 패턴).
- **전제조건 충족**: R10 제거 조건이던 P2-3(a) manifest 앵커링이 2026-10-07 착지
  (`docs/spec/ci_optimization_tcb_judgments.md` §3.3 구현 상태 — `tools/ci/tcb_judgments.nim`
  cache-manifest CIRCULAR 판정 소멸). 본 Amendment가 그 결정 바인딩이다.
- **효과**: R10의 ahead-invariant 분류 해소 — stale PR 사이클에서 PR-phase lane
  identity가 merge_group phase에서 2회째 콜드로 재계산되던 클래스 제거
  (census `docs/evidence/ci_structural_duplicate_census_2026-09-30.md` §5.1 #4).
  잔여: R5(교차 타이밍)·R9(c)(a_fp 이미지 롤)·J3 바닥(HIT에서도 남는 warm 재컴파일 —
  S5 build-skip은 별도 슬라이스) 불변.
- **CI Epoch Cutover**: freeze `ci-frozen-2026-10-08` + record
  `docs/evidence/epoch_record_memo_reanchor_2026-10-08.md` (publisher 전용 변경 —
  3파일 pin 유닛·org callee 회전 불요: publisher는 workflow_call callee도 required
  check도 아님).

## References

- 계획서: gateway-landing-authority 전환(hellcat-iceman-havok) — ①′·②·③ 문구 원문 인용,
  Core Invariant, Terminal Outcome, Phase 0-5, Completion Evidence [0]-[9]
- AGENTS.md §2(:136 — native MERGE 정본 선언) · §0.9b(Triple-Closure) · §-1
- GitHub 공식 문서 — required workflows(org `workflows` ruleset, sha 필드),
  [Branch protection API](https://docs.github.com/en/rest/branches/branch-protection)
  `strict_required_status_checks_policy`("This setting will not take effect unless at
  least one status check is enabled" — ①′ 공식 근거), status check skip → success,
  `jobs.<job>.if`/`needs` 결과 검사 패턴
- ADR-0017 Amendment A1.2(:129-134) · A1.7(:189-198); ADR-0021(execution authority —
  D1 "repository state 변화 + 플랫폼 native rerun"와 정합, D5/D9 유지);
  ADR-0022 §4(TrustedWriterSet, `config/trusted_writer_set.json:2-26`); ADR-0019(main 착지
  행 정합 대상)
- `docs/evidence/canonical_run_graph.md:73`(착지 후 발화 — 가드 불가), :95(main ruleset
  id 20303214 · required check admission-check), :148-154(required workflow
  landing-integrity 패턴 실측)
- `data/debt_registry.json:3761-3774`(DEBT#462 — open), `docs/DEBT_REGISTRY.md:178`
- `docs/spec/certification_continuity_contract.md:208`(INV-2 — native MERGE 원문)
- `docs/spec/ci_optimization_tcb_judgments.md:17-20,:228-231`(J1-J4)
- `src/cli/merge_cli.nim:59-79,:566`(RequiredChecks/RequiredWorkflowIds/findRunsForHead)
- `config/repository_surface.json:41-124,:142-146`(CONTROLLED 등록 — FROZEN default)
- Amendment C(2026-09-30) 추가 — `docs/evidence/epoch_record_oracle_select_2026-09-30.md`(Freeze/Record/Tombstone),
  `docs/adr/0017-incremental-verification-engine.md` Amendment A2(2026-09-30 — oracle-evidence 계약),
  `tools/ci/impact_closure_selector.nim:1414`(landingFloor — 병렬 편집 중) 및 selector working diff(oracleEvidence 소비 구현),
  `docs/evidence/canonical_run_graph.md:314`(landingPolicyFloor=true 실측),
  `data/debt_registry.json` DEBT#466(b+)·#467·#468·#469·#470

---

## Amendment D (2026-10-10): ④ pin-anchor의 전 경로 평가 — 단일 정책 거부(Pass 2.75)

**배경(실측)**: NORMAL 조기 반환(closureEqual=true)이 ①–④를 vacuous-true로
강제하여, pin@H 내용만 변조한 PR(트리 불변)이 NORMAL/GO로 착지했다
(`tests/cli/test_merge_cli.nim` S1-C/D 앵커 — 구동작 고정 테스트가 실증).
이는 "모든 착지에서 pin@H == derived(H)" 불변식의 예외 경로였다.

**개정**:
1. `adjudicateRotation`은 ④를 **모든 경로에서 사실로 계산**하고, 실패 시
   reasonCode/reason을 **주석**한다(단일 선택 지점 — genesis면
   ROT_GENESIS_INVALID, 아니면 ROT_NEW_PIN). ①③ 사다리가 먼저 덮어쓰므로
   기록된 사유는 항상 사다리 선택(①→③→④)이다. ④는 이 함수에서 **거부하지
   않는다** — `qualification`은 **주제 분류**(rqNormal/rqRotation)이며 판정이
   아니다.
2. **Pass 2.75(H2)**가 `MergeAdmissible`에서 trust-surface 라우팅 **앞**에
   놓여 ④ 실패(mismatch 또는 키 부재)를 사다리 선택 코드 verbatim으로
   거부한다 — ④ 불일치의 **유일 정책 거부 지점**. 수동 병합 경로는
   "사람 의식 + 기계 검사"로 조건화된다(검증 입력 부재 = 상위 fail-closed,
   ROT_UNSPECIFIED/exit 1 — `proof_required_admission_contract.md` §3 동기
   개정).
3. **H1+H2는 동일 세대 필수** — ④ 분기 제거만으로는 ROTATION+④-fail이
   rqRotation으로 통과한다.
4. **판정 식별자**: dry-run JSON이 `judge.source`(SHA-256 — `hash_kernel.
   sha256Hex` 단일 권위; NIST: 신규 신뢰 증거에 SHA-1 부적합)를 기록한다.
   증명 범위는 **판정 코드 소스의 결정론적 지문 + 코드↔이진 결속**이며,
   run↔verdict 결속은 잡 로그 봉투, "엔진 전체 신원"은 주장하지 않는다.
   (버전 상수 drift 부류 기각 — staticRead 바이트 파생.)

**사다리 ④ 분기 제거의 의미**: rqNone은 ①③ 전용이 된다. ④ 실패의 거부는
전부 Pass 2.75에서 발생하며, 4클래스 배타 계약(정책 거부 @H2 / 정책 거부
@사다리·패스 / 상위 fail-closed / 정책 라우트 exit-0)이
`src/cli/merge_cli.nim` docstring의 정본이다.

## Amendment E (2026-10-12): 불변식 3 개정 — main required status checks 2-컨텍스트 모델(`admission-check` + `bsec-integrity`) — D2 verdict protocol 기록 무결성 검사 도입 (결정 바인딩, AGENTS.md §0.10)

> 결정 바인딩 개정이다(AGENTS.md §0.10 — 변경은 커밋된 결정/정책에 구속된다).
> 결정 권한 = operator/decision owner 승인(2026-10-12). 본문(Amendment A
> 8불변 포함)을 다시 쓰지 않으며 append로만 남는다. 본 amendment는 **결정
> 문서 leg**다 — 워크플로·ruleset 변경이 이미 발생했다는 주장이 아니며,
> S0→S1 전환 실행(및 transition-sequenced `config/policy/merge_admission.json`
> 회전)은 후속 단계다.

**1. 불변식 3 개정** (Amendment A 8불변 #3(:494)과 그 해설(:510-512)):

```text
[개정 전] 3. required check는 정확히 하나다
[개정 후] 3. main ruleset(id=20303214)의 required status checks는
             정확히 2개 컨텍스트다 — "admission-check"와
             "bsec-integrity".
             admission-check PASS = merge eligibility(trust-boundary
             verdict) — 불변식 2의 유일한 판정 표면.
             bsec-integrity  PASS = 기록 무결성(record integrity)
             ONLY — 결코 verdict GO가 아니다(never a verdict GO).
             심의 대상 = D2 verdict protocol의 기록 삼중 등식
             derived == recorded == ledger heads.
```

- **의미 비대칭이 핵심이다**: GitHub required-check 강제는 두 컨텍스트를
  대칭적으로 차단하지만, 두 컨텍스트의 **의미는 비대칭**이다 —
  `bsec-integrity` PASS는 착지 가능성(eligibility) GO를 의미하지 않고
  오직 기록 등식의 성립만 의미한다.
- **불변식 2 무변경**: "Axiom verdict는 merge eligibility만 판정한다"
  (:493)는 유지된다. 본 개정은 verdict job의 의미를 넓히지 않는다 — 별개
  불변식을 별개 컨텍스트로 **분리 표면화**할 뿐이다.

**2. 근거 — 서로 다른 2개의 불변식**:

- 기록 무결성(D2 verdict protocol — derived == recorded == ledger heads)은
  불변식 2와 **별개의 불변식**이다. 이를 `admission-check` verdict job에
  접어 넣으면(fold) (a) 하나의 job이 2개 불변식을 소유해 GitHub 표면에서
  "기록 불일치 실패"와 "자격 판정 NO"의 실패 의미론이 구별 불가능해지고,
  (b) verdict job의 의미가 eligibility 너머로 확장되어 **불변식 2의 정신을
  위반**한다. fold 금지 — 분리가 원칙이다.

**3. 전이 상태 모델 (S0 / Sf / S1)**:

| 상태 | main required status checks | 성격 |
|---|---|---|
| **S0** | `admission-check` 단일 | 현행 운영 상태(본 amendment 기준일 라이브 상태) |
| **Sf** | `admission-check` + merge-freeze ruleset | **임시 전환 상태** — S1 cutover 작업 창 전용 |
| **S1** | `admission-check` + `bsec-integrity`(정확히 2개) | **최종 정책** — 본 개정의 목표 상태 |

- **S1이 최종 정책이다. Sf는 임시 전환 상태**이며 그 자체가 목표가 아니다.
- **Sf 고유 규칙**: (i) 예외 범위 = freeze ruleset의 좁은(narrow)
  bypass_actors로 통과하는 **사전 승인된 단일 전환 PR 정확히 1건**;
  (ii) Sf 동안 허용되는 PR = 그 사전 승인된 전환 PR만; (iii) 롤백 조건 =
  전환 단계 중 하나라도 검증에 실패하면 → freeze ruleset을 제거하고
  ruleset 20303214를 **무변경**으로 남겨 S0으로 복귀한다(부분 상태 혼합·
  묵시적 재시도 금지).
- freeze ruleset은 20303214를 수정하지 않는 **별도 ruleset**이며,
  20303214의 `bypass_actors=[]` 불변은 S0·S1에서 유지된다.

**4. cutover 실행 불변식**:

- **단일 API 표면**: 전환은 end-to-end로 **정확히 하나의** API 표면만
  사용한다 — GraphQL `updateRepositoryRuleset`(Relay ID) 또는 REST PUT
  (numeric id) 중 하나 — **혼용 금지**.
- **사전/사후 스냅샷 증명**: pre/post ruleset 스냅샷이 "의도한 규칙만
  정확히 변경되었고 나머지 전체 규칙·bypass 설정은 보존되었다"를 증명해야
  한다 — 스냅샷 없는 cutover는 검증 실패로 간주한다(§3 롤백 조건 발동).
- **모니터 정합**: `tools/merge_ruleset_drift_monitor.nim` 기대치는 본
  개정과 동일 결정 번들에서 S1 exact-two 집합으로 회전된다. cutover 전까지
  라이브 S0 ruleset에 대한 DRIFT(exit 1)는 **기대된 fail-closed 신호**다 —
  라이브 상태에 맞춰 기대치를 약화하는 것(극장)은 금지된다.

**5. supersession 범위 (본문 재작성 없이)**:

- 개정: Amendment A 8불변 #3(:494) + 그 해설("불변식 2·3·4" 문단, :510-512),
  §2 "필수 조합"의 "2건 이상도 금지" 절(:122-123).
- 무변경: 불변식 2(merge eligibility 전용 판정), 불변식 1·4-8, 20303214
  `bypass_actors=[]`, AGENTS.md:136 native MERGE 정본, strict→큐 무효화
  위임 경과(ADR-0027 P5).

**6. 정합 회전 대상(후속 — 본 amendment는 코드를 바꾸지 않는다)**:
`src/cli/merge_cli.nim`(`RequiredChecks`·`rulesetAdmissionRequirementOk`·
`CanonicalCheckIntegrationId` — 단일 컨텍스트 실측 판정),
`config/policy/merge_admission.json`(transition-sequenced), ADR-0027 단일
required check 조항(동일 결정 — ADR-0027 Amendment A(2026-10-12) 참조).

---

## Amendment F (2026-10-12): merge admission 분류식을 candidate-delta로 교체 — closureChange 등식 · ③ 전 경로 승격 · 후보 트리 동등성 게이트

> closure-candidate-delta workstream(S0)의 결정을 정식 개정으로 기록한다. §11
> identity 3계층과 §13 의무 연쇄의 어휘(①–⑤)는 유지하되 분류 등식만 교체한다 —
> 본문을 다시 쓰지 않으며, append로만 남는다. 근거 = S1 stale-base 오분류 실측
> (`docs/evidence/s1-stale-base-repro-2026-10-12.md` — 기준선 드리프트가
> closure-neutral PR을 ROT_ALLOWLIST로 오분류), 재현 조건 선결 계약
> `docs/spec/certification_continuity_contract.md` §11(RATIFIED 2026-10-12),
> `docs/agents/rules_workflow.md:132`("Never describe both as the same
> boundary").

1. **분류 정의 변경**: `closureEqual = (derivedH == derivedB) and (derivedB ==
   pinBSet)`(`src/cli/merge_cli.nim:647`)을 **폐기**하고
   `closureChange = (derived(M) != derived(B))`로 교체한다. M := B 위에 이 PR
   변경을 적용한 후보 트리 — `git merge-tree --write-tree B H`(재유도)와
   `tree(G)`(GitHub 실제 후보, `MERGE_TREE_OID` = `tree(github.sha)` 객체 해석 —
   `admission-check.yml:1291`)의 **동등성이 기계 검증된** 트리다. 분류는 "이 PR이
   폐쇄를 바꾸는가"만 묻는다 — 기준선 드리프트(PR 분기 후 base가 먼저 회전한
   소급 차이)는 분류에 개입하지 않는다.
2. **③의 전 경로 승격**: `pin@B == derived(B)`를 분류와 무관한 사실로 **모든
   경로**(NORMAL 포함)에서 평가하고, 단일 정책 거부 지점에서 `ROT_OLD_PIN`으로
   거부한다 — Amendment D(2026-10-10, :723)가 ④에 시행한 "전 경로 사실 평가 +
   단일 거부 지점" 패턴의 ③ 적용이다. stale-base-pin 거부(S1' 계약)는 유지된다.
3. **실패 우선순위 고정**: ①입력·identity(α-shape · PR 재유도 · 후보 트리
   동등성) → ②③(ROT_OLD_PIN) → ③④(Pass 2.75) → ④ delta 분류 →
   ⑤allowlist(ROT_ALLOWLIST). 사다리 선택 저널은 기존 계약(①→③→④ verbatim)을
   승계한다.
4. **후보 동등성 검사(게이트 요소)**: `M == MERGE_TREE_OID` — 불일치 ·
   merge-tree exit 1(충돌, INV-11) · exit ≥2(오류 — driver 부재 128 실증 포함) ·
   출력 파싱 불가 시 **UNSPECIFIED fail-closed**(정상 간주 금지 — GVP-3). 저널
   코드는 `CANDIDATE_TREE_MISMATCH` 류를 쓰며 **`ROT_` 접두는 금지**다 —
   `ROT_`는 closure subject class(rqNormal/rqRotation) 전용 어휘이다. G의
   closure를 분류에 직접 쓰지 않는다 — G는 검증 비교 대상일 뿐이다.
5. **E1(c)/(d) 해석 확정**: Amendment A의 E1(c) "로컬 merge-tree 구성 금지"(:516)·
   E1(d) "자기 소유 merge authority = 0 — local merge-tree·local CAS 부재"
   (:531-534) 불변은 **actuation과 후보 구성**(착지 행위 · merge commit
   materialization · public ref 이동)으로의 사용을 금지하는 것이며, **재유도
   검증 오라클**로서의 `git merge-tree --write-tree` 사용(read-only in-core —
   작업 트리·index·ref에 기록 없음, git-merge-tree(1))은 허용된다. 선례:
   `certificate-mint.yml:828-853`(3b merge-candidate tree by-object 재유도
   대조), ADR-0027:214-218(β probe — `tree(L)==tree(G)`),
   `docs/adr/0020-axiom-queue-semantics-and-executor-boundary.md` v10 개정
   (2026-09-09 — `merge-tree --write-tree` in-core 단일 승인 호출 경로). 이것이
   "주체 앵커링 재도입"이 아님은 `docs/adr/0033-sl02-consumer-binding.md:43-48`과
   정합이다 — G는 검증 전용 비교 대상이며 closure 등식의 주체 anchor는 H로
   유지된다(ADR-0033 동반 문단).
6. **재현 조건(선결)**: 핀 계약은
   `docs/spec/certification_continuity_contract.md` §11("Git merge-tree 버전·
   구성 핀", RATIFIED 2026-10-12)이 정본이다 — 기능 하한 `git >= 2.40.0`, 재현
   기준 `2.43.0`, 상한 미고정(merge 기계 진화에 따른 `derived(M)` 발산은 §11.0
   1차 방어인 등식이 흡수한다). history 획득은 재현 가능 절차로 한다 — shallow
   판정 → 명시적 deepen → 이력 불충분 시 fail-closed(빈 결과·정상 변환 금지).
   1차 방어(등식)와 2차 조건(버전 핀)의 구분(§11.0)을 수용하며 권위 치환은
   금지다(GVP-4).
7. **형상 vs 설정의 구분**: 그룹 1:1 형상 불변식(ADR-0032 (e) — ALLGREEN + 1:1)은
   **구조 층** — α-shape · PR identity · 후보 트리 동등성 — 으로 강제한다.
   merge queue 설정값(`max_entries_to_build` = 동시 빌드 throttle,
   `max_entries_to_merge` = 병합 배치, `grouping_strategy` = ALLGREEN)은 **감시
   대상일 뿐 형상 강제 수단이 아니다** — `docs/agents/rules_workflow.md:132`
   "Never describe both as the same boundary" 준수(ADR-0032 동반 문단).

**§11 identity 3계층 준용(신규 행)** — 아래는 §11(:278-286)의 계층 구분을
확장하는 것이며 기존 행을 수정하지 않는다:

| 계층 | 판정 | 성격 |
|---|---|---|
| 후보 트리 동등성 `M == tree(G)` | `git merge-tree --write-tree B H` 재유도 결과와 `tree(github.sha)`(`MERGE_TREE_OID`)의 착지 전 대조 | **게이트 요소** — 불일치·충돌·오류 = UNSPECIFIED merge 차단(위 4항); 불일치는 분류 입력 부적격이며 `ROT_` 코드가 아니다 |

기존 행 1(`testedTree == mergeTree == certTree`)의 `mergeTree` 사전 검증과의
차이: 행 1은 witness 기록 트리와 `tree(github.sha)`(G = github.sha 대상) 객체
해석의 대조로 **certificate identity 연쇄**의 일부이며 분류 입력을 구성하지
않는다. 신규 행은 로컬 재유도 M이 GitHub 실제 후보 트리와 동일함을 검증해
**분류 입력 `derived(M)`의 적격성**을 세운다. `M.tree == certTree`(audit
observation)과의 성격 구분은 §11 원문 그대로다 — 착지 후 관찰은 판정에
재진입하지 않는다.

**코드 동반 변경(명시 — 본 개정은 ADR 텍스트만으로 발효하지 않는다)**:

- `src/cli/merge_cli.nim` — 판정식 교체(:647 closureEqual → closureChange) ·
  ③ 재홈(전 경로 사실 평가 + 단일 `ROT_OLD_PIN` 거부 지점) · 실패 우선순위
  재배선(위 3항).
- `tests/cli/test_merge_cli.nim` — 회귀 7종 + S1 characterization FLIP
  (`S2 FLIP:` 마커 반전 — :820 이후 suite).
- `.github/workflows/admission-check.yml` — 후보 동등성 검사(`M ==
  MERGE_TREE_OID`) · fetch 계약(명시적 deepen · shallow fail-closed). blob
  변경이므로 **A2 원자 페어 회전 필수** — `config/trusted_writer_set.json`
  `trustedAdmissionWorkflowSha` + epoch manifest `productionExecutionPin`을
  동일 커밋에서 회전한다(Amendment A2 · ADR-0032 (d) · ADR-0033 (e) 동일
  패턴).
- deriver 3번째 각 — `tools/ci/derive_checker_closure.nim`에 `--ref M` 실행
  대상 추가(H·B에 이은 제3 도출 — `derived(M)` 산출).

**승인 기록(슬롯)**: 본 Amendment F는 **초안(DRAFT, 2026-10-12)** 상태다 —
최종 승인은 인간 아키텍트의 몫이다. 승인자: (미승인 — @architect 승인 대기) ·
승인 일시: (미기입).
## Amendment A3 (2026-10-12): A2 회전 동반 집합 확장 — candidate-delta 회전의 필수 동반 파일 9경로 (same fix class, 결정 바인딩)

> 근거: merge_group 판정 2026-10-12 — ROT_ALLOWLIST 실측(PR #780, 후보 동등성 candidate-delta
> 회전). A2(2026-09-27)와 A2 확장(2026-10-10, PR #699)이 확정한 원칙 그대로다: **회전 PR이
> 반드시 동반하는 파일을 allowlist가 배제하면 회전 자체가 착지 불가**해진다 — trust를 넓히는
> 것이 아니라 그 회전의 필수 동반을 정합 집합에 수록하는 것이다. 본문을 다시 쓰지 않으며,
> append로만 남는다.

1. **개정**: `RotationAllowlistExtra`에 다음 9경로를 A2 회전 동반으로 수록한다 —
   `tests/ci/test_sl02_consumer_binding.nim`(5파일 계약 회귀 — derived-M 필수가 되는 회전의
   계약 테스트), `tests/ci/test_derive_checker_closure.nim`(제3 도출 각 `--tree` 회귀),
   `docs/spec/certification_continuity_contract.md`(§11 git merge-tree 버전·구성 핀 — 회전
   재현 조건), `docs/spec/github_delegation_residuals.md`(파라미터 역할 표 — 설정 감시 ≠
   형상 강제), stale-base 재현 증거 문서(동반 회전과 함께 착지하는 evidence 기록),
   `tools/ci/git_access_scan.sh`(clause-3 제한적 ancestry 계약 — depth-1 게이트 본문),
   `tools/merge_ruleset_drift_monitor.nim` + `tests/unit/test_merge_ruleset_drift_monitor.nim`
   (ALLGREEN 정책 기대), `data/debt_ledger.json`(예산 원장 실측 정합).
2. **범위 한정**: NON-member production `src/` 변경은 여전히 allowlist 밖이다 (A2 (i) 유지).
   위 9경로는 전부 회전 기계의 테스트·계약·증거 또는 회전 게이트가 읽는 원장 데이터다 —
   production source가 아니다.
3. **코드 동반 변경**: `src/cli/merge_cli.nim`의 `RotationAllowlistExtra` 갱신(본 개정과
   동일 PR에서 착지), `data/architecture_debt.json` contentHash 재계산, 회전의 정식
   `trustedCheckerTreeClosure` 재앵커(파생 폐쇄와의 ④ 일치 — ADR-0025 §7 절차).

**승인 기록(슬롯)**: 본 Amendment A3는 PR 착지가 곧 승인이다(결정 바인딩, AGENTS.md §0.10).

---

*작성일: 2026-09-26. PROPOSED — 계획서 Phase 0 ADR 기록. §1.2 서술 정정은 본 ADR과 동시
번들, Phase 1~5 실증(착지 전 4중 등식·freshness·rotation) 완료 전 "post-merge gateway 0
확정" 선언 금지.*

## Amendment A5 (2026-10-14) — A2 회전 동반 집합 확장: verified-subject lane adapter 클래스 2경로 수록 (A2 (i) 유한 개정, 결정 바인딩)

> 근거: 사전등록 `docs/evidence/rotation_allowlist_a5_prereg_2026-10-14.md` + rust-lane-live-cli 회전 실측(클로저 멤버 `src/cli/axiom_engine.nim`·`src/verification/extraction_provenance.nim` 변경). A2(2026-09-27)·A3(2026-10-12)·A4(2026-10-13)가 확정한 "회전의 필수 동반을 allowlist가 배제하면 회전 자체가 착지 불가" 원칙과 A2 (iii)의 개정 경로(A3/A4 동일 스타일)를 따른다. 본문을 다시 쓰지 않으며, append로만 남는다.

1. **개정 (A2 (i) 유한 개정 — 신설 클래스)**: 다음 3조건을 **전부** 만족하는 production `src/` 파일을 **검증 대상 레인 어댑터(verified-subject lane adapter) 클래스**로 정의하고, 이 클래스에 한해 A2 (i)의 "NON-member production `src/` allowlist 밖"을 개정한다:
   (α) **동일 회전 내 클로저 편입** — 본 회전과 같은 커밋에서 `trustedCheckerTreeClosure` 멤버로 편입되어 pin@H 키가 된다(비멤버 src의 회전 편승이 아니라 회전 자체가 산출하는 새 멤버의 필수 동반이다);
   (β) **판정 위임** — 새로운 판정·인증·발급·게이트·권위 어휘를 도입하지 않고 검증 판단을 기존 커널 체인에 위임한다(디스패치·수송·ingress 한정);
   (γ) **열거형 한정** — 본 amendment에 열거된 경로만 수록하며 glob·접두 확장은 없고, 미수록 경로는 fail-closed다(테스트가 고정).
   이 클래스 밖(클로저 멤버로 편입되지 않는 production `src/`)에서는 A2 (i)가 원문 그대로 유지된다.

2. **수록 경로 (16경로)**: `data/verification_scope.lock`, `docs/evidence/rotation_allowlist_a5_prereg_2026-10-14.md`, `docs/spec/rust_certified_subset.md`, `docs/spec/rust_toolchain_quirks.md`, `src/cli/rust_lane_cli.nim`, `src/verification/charon_runner.nim`, `tests/fixtures/rust/axiom_rust_probe/{Cargo.lock, Cargo.toml, README.md, axiom.specs.json, axiom_rust_probe.llbc, src/lib.rs}`, `tests/gateway/rust_lane_cli_acceptance_test.nim`, `tests/gateway/rust_subject_provenance_issuance_test.nim`, `tests/gateway/rust_subject_three_cases_test.nim`, `tests/unit/test_charon_runner.nim`. — 이 중 (α)–(γ) 신설 클래스는 2경로(`src/cli/rust_lane_cli.nim`, `src/verification/charon_runner.nim`)뿐이며, 나머지 14경로는 기존 클래스(회전 동반 데이터·계약·증거·테스트·fixture, A2/A3/A4 선례)다.

3. **파일별 사실 근거 (아키텍트 기계 검증 가능)**:
   - `src/verification/charon_runner.nim` — `axiomLayer "infrastructure"`(:2); imports 5개 — `std/[os,strutils]`, `core/axiom_pragmas`, `infrastructure/process_utils`, `verification/extraction_provenance`(핀 상수 SSOT), `verification/verification_subject`(`isHexOfLen`) — 판정부 import 0; 노출 심볼 5개 전부 외부 charon 바이너리의 핀 신원 게이트·구동(`parseCharonVersionLine`:109, `charonPinVerdict`:127, `probeCharonVersion`:186, `runPinnedCharonCargo`:215)이고 predicate/attestation/issuance/verdict 어휘 0건, 실패 전면 fail-closed(`cr*` :64). 판정 위임 입증: 발급 체인은 기존 `rust_rust_pipeline.rustSubjectIssuance`(main :369)가 소유. 본 파일은 INV-9의 "no ax prove surface" 클래스가 **아니라**(본 회전의 producer 단계) 본 amendment (α)–(γ) 클래스로만 정당화된다.
   - `src/cli/rust_lane_cli.nim` — `axiomLayer "presentation"`(:2); 자기 문서 :16-18 "OWNS no verification logic, no verdict vocabulary, no gate and no authority"; 등록 = 단일 디스패치(`src/cli/axiom_engine.nim` `--project` + `Cargo.toml` 분기 — 부재·비-cargo 진입 0, 동작 변경 0); 판정·발급·exit 규칙 전부 기존 소비(`rustSubjectIssuance`, `extraction_agreement` ea* 어휘, `wf_runners.axProofShortcutExitCode`); 자체 구현은 스코프 락 fail-closed 로드(:266-290)·LLBC 이름 열거(:119-146)·닫힌 spec 디코드(기존 IR 생성자만, :217-243)·block-stage→보고 상태 투영(:342-361)뿐이다.

4. **범위 한정**: A2 (i)는 유지된다 — (α)를 만족하지 않는 production `src/`는 여전히 allowlist 밖이다. `docs/evidence/**`·`tests/**`·`data/**`는 glob하지 않고 열거 16경로만 수록한다 — 미수록 경로 fail-closed(테스트 고정).

5. **코드 동반 변경**: `src/cli/merge_cli.nim` `RotationAllowlistExtra` 갱신(본 개정과 동일 PR 착지 — trust surface, MUST-T2 수동 arm 대상), `data/architecture_debt.json` contentHash 재계산, 회전의 정식 `trustedCheckerTreeClosure` 재앵커(④ 일치 — ADR-0025 §7).

**승인 기록(슬롯)**: 본 Amendment A5는 A2 (i)를 유한 개정하므로 A3/A4의 "PR 착지 = 승인" 관행과 달리 명시 승인을 요구한다. 승인자: wintrover (소유자) · 승인 일시: 2026-10-14 · 승인 근거: 사전 승인 대화(세션 명시 승인 — "승인·전체 진행") + 결속 dry-run 증거(exit 0, mergeGo/GO, ROTATION, allowlistOk·anchorOk·judge 결속).