# ADR-0032: Admission venue 분리 — PR은 즉시 preflight, MG 착지 자격만 정본

## Status

**Accepted (2026-10-09)** — 아키텍처 결정 기록이며 구현을 수반한다 (워크플로 2종 +
`src/cli/merge_cli.nim` + TWS/epoch-manifest 핀 회전 — 단일 커밋, 아래 §Decision (d)).
`docs/adr/0027-queue-delegation.md`가 merge_group 실행 경로를 도입했으나 두 venue가
**동일한 full 검증**을 실행하는 구조를 그대로 두었고, 본 ADR이 그 축을 분리한다.

## Context

필수 체크 `admission-check`는 조직 게이트(Archright/.github `admission-gate.yml`)의
workflow_call@SHA로 5개 leg — attest, mint-prepare, mint-publish, verdict, gateway —
를 PR과 merge_group 양쪽에서 **동일하게** 실행한다. 그 결과:

- 불량 PR도 B-tree 빌드 + GO-critical 커널 E2E + D9 스테이징 + witness 서명 + full
  mint 체인을 전부 통과해야 red가 난다. MG 슬롯(~10–15분)을 불량 후보가 점유한다.
- PR의 verdict leg는 `certRequired=true`(`src/cli/merge_cli.nim:96` const)를 평가하는데,
  인증서는 같은 run의 mint가 발행하므로 PR 경로에 cert 없이 통과하는 분기가
  **전무**했다 — venue 구분이 CLI 계약에도 없었다.

GitHub은 merge-admission의 착지 enforcement 권한이며(ADR-0025 §1, AGENTS.md §2.3),
필수 체크는 ruleset에서 **하나의 이름**(`admission-check`)으로 요구된다. 체크 이름을
둘로 나누면 ruleset 개정(org 저장소)과 required-check 재등록이 선행돼야 하므로,
착지 enforcement 표면은 그대로 두고 **callee 내부의 스텝 분기**만으로 venue를
분리한다(github context는 caller 상속 — `admission-check.yml`이 이미
`github.event_name`을 소비하는 것과 동일 근거).

## Decision

**(a) 착지 자격의 유일 정본 = merge_group verdict.** merge_group venue의
`admission-check` verdict leg — same-run `subject-certificate-<attempt>` 소비 +
`ax merge --dry-run --json`(certRequired 평가) — 가 착지 자격의 정본 판정이다.
PR venue의 결과는 착지 자격이 아니다.

**(b) PR venue = 즉시 신속 preflight (예산 4분).** pull_request 이벤트에서 각 leg는
정적/구조 검사만 수행한다 — attest leg: B/H identity 재유도 + TWS/policy 정적 대조,
verdict leg: policy/structure 정적 대조, mint 양 leg: 구조 정적 대조. B-tree 빌드,
GO-critical 커널 E2E, D9 스테이징, witness 서명, full mint 체인은 PR에서 실행하지
**않는다** — 이것이 의도다(오버엔지니어링 금지, §0.12). 모든 preflight leg는 실제
검사를 수행한 뒤 명시적 `PREFLIGHT PASS —` 라인을 출력한다. 검사 실패 = exit 1 =
red(항상 통과 분기 없음, §0.9).

**(c) certRequired의 venue 분리 — CLI는 opt-in 플래그로만.** 정본 기본값은 불변:
`CertRequired = true`(fail-closed). PR preflight만 인증서를 요구하지 않으며, 이는
`ax merge --preflight` **명시적 opt-in**으로만 도달한다. `--preflight`는 `--apply`와
조합이 **거부**되며(실제 병합 행위는 언제나 정본 인증서 요구), preflight 판정 결과는
출력에 **비정원(non-canonical)** 임을 명시한다. 판정 위치 단일화 보존 — 착지 자격
판정은 verdict가 유일하고, preflight는 자격 판정이 아니다.

**(d) 세대 전환 — 핀 원자 페어.** `admission-check.yml` blob 변경이므로 A2 원자 페어
(`config/trusted_writer_set.json` `trustedAdmissionWorkflowSha`)와 epoch manifest
`productionExecutionPin`을 **동일 커밋**에서 회전한다(landing-integrity ATOMICITY,
`certificate-mint.yml` (2a)가 @B 대조). `certificate-mint.yml`은 TWS 핀 대상이
아니므로 회전 대상이 아니다. 착지(merge) 시점에 단일 세대로 전환되며, 활성 실행
경계의 혼합 세대는 존재하지 않는다(AGENTS.md §2.5). freeze 태그:
`ci-frozen-2026-10-09-venue-split`.

**(e) 5-leg DAG·집계 불변.** leg 생략(DAG 수준 분기)·job skip 금지 — 5개 leg 전부
유지되고, 미인식 이벤트에서 venue 스텝은 exit 1로 fail-closed다. ALLGREEN + 1:1
불변 유지(HEADGREEN 금지 — 그룹>1에서 (B, H_PR) 인증 subject가 부분 인증이 된다,
ADR-0027 α). MG의 모든 스텝·아티팩트 이름·attempt suffix는 바이트 수준 불변.

**형상 불변식과 설정 감시의 층 구분(ADR-0025 Amendment E, 2026-10-12)**: 형상
불변식(1:1)은 구조 층 — α-shape · PR identity · 후보 트리 동등성
(`M == tree(G)`) — 으로 강제하고, merge queue 설정값 감시
(`max_entries_to_build` = 동시 빌드 throttle · `max_entries_to_merge` = 병합
배치 · `grouping_strategy` = ALLGREEN)는 별개 층이다. 설정값은 감시 대상이지
형상 강제 수단이 아니며, 두 층을 동일 경계로 서술하지 않는다
(`docs/agents/rules_workflow.md:132` "Never describe both as the same boundary"
— ADR-0025 Amendment E 제7항).

**(f) 실패 의미와 감사 관측.** preflight 실패는 **워크플로만** red로 만든다 — required
check의 fail-closed 유지이며 착지 자격 판정의 변화가 아니다. "preflight 성공 ≠ 착지
증거"는 **비정원**이다. 감사 관측 방법:

1. 각 preflight leg 로그의 `PREFLIGHT PASS —` 라인 — 실제 수행된 검사 목록을 명명
   한다(빈 분기 극장의 기계 관측점, §0.9).
2. 착지 자격의 유일 저널 = MG verdict가 남기는 `.axiom/gate_history.jsonl`
   merge-admission 기록 + required check conclusion.
3. venue는 GitHub run object의 `event` 필드(`pull_request` vs `merge_group`)로
   사후 관측된다 — callee가 자기 판정 라인에 venue를 명시하므로 로그 단독으로도
   재구성 가능하다.

## Consequences

- **불량 PR은 preflight에서 즉시 red** — MG 슬롯 점유 제거. 정적 검사에서 잡히지
  않는 결함(컴파일 오류, 커널 E2E 실패)은 MG에서 처음 발견된다: 이 격차는 (b)의
  명시적 수용이며, MG가 그 결함의 정본 발견 지점이다.
- **PR 경로는 bin/ax를 빌드·실행하지 않는다** — PR에서 `ax merge` 판정 자체가 없다.
  이는 "PR도 admission 판정을 받아야 한다"는 해석을 폐기하는 것이 아니라, PR 판정의
  권위가 MG verdict로 이전됨을 선언하는 것이다.
- **조직 게이트 파일은 본 ADR 범위 밖이다** — callee 내부 분기만으로 발효되며,
  org 저장소 핀 회전(변경된 admission-check blob으로의 Dependabot/수동 범프)은
  착지 후 Phase 2 후속 작업이다. 회전 전 조직 게이트는 구(舊) blob SHA 핀을 계속
  소비한다 — org 게이트가 이 파일을 workflow_call@SHA로 실행하므로, 회전 전
  PR/MG 실행은 여전히 구 세대 정의로 실행된다(혼합 아님 — §2.5 세대 원칙 준수).
- **재검토 조건**: PR preflight에서 MG-only 결함의 발견률이 유의미해지면 PR 예산
  내 compile smoke 추가를 재검토한다 — 이는 (b)의 예산 절차이지 정본 판정의
  확장이 아니다.

## References

- `docs/adr/0027-queue-delegation.md` — merge_group 실행 경로·α subject identity.
- `docs/adr/0025-gateway-landing-authority.md` §1 — GitHub native MERGE = 착지
  mutation 정본 행위; verdict = 자격 판정.
- `docs/adr/0022-*` §D5-3 — same-run `--cert` handoff(MG verdict의 인증서 원천).
- `src/cli/merge_cli.nim:96` `CertRequired` const + `:701-706` Pass 2.96 NO_CERT —
  정본 기본값 불변의 코드 앵커.
- `data/debt_registry.json:4148` — 암묵 skip으로 required check 무효 success가 된
  반례 선례(venue 분기에서 명시적 판정 라인이 필수인 이유).
- AGENTS.md §0.9(극장 금지)·§0.12(제품 계약 선행)·§2.3(merge-admission 관측
  계약)·§2.5(CI 세대 전환).
