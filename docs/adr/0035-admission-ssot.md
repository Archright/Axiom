# ADR-0035: required-check SSOT 정합 — 정규 집합 기록 + 생산자 통제 readback + 상시 드리프트 감지

## Status

**Accepted (2026-10-21)** — 아키텍처 결정 기록이며 구현을 수반한다
(`config/policy/merge_admission.json` v1.15.0, `src/cli/merge_cli.nim` 상수
동기, `tools/merge_ruleset_drift_monitor.nim` 정책 파생화, 신규
`.github/workflows/admission-ssot-drift.yml`, 단위 테스트 동반 — 단일 PR).
상위 결정: [ADR-0025](0025-gateway-landing-authority.md) Amendment B(P12 —
GitHub 위임) · [ADR-0027](0027-queue-delegation.md)(병합 권한 위임) ·
[ADR-0032](0032-admission-venue-split.md)(베뉴 분할).

## Context

### 1. 세 곳의 사본이 하나의 사실을 말하면서 서로 어긋나 있었다

required-check 집합이 세 곳에 적혀 있었고 값이 달랐다.

| 위치 | 값 (landing 전) | 성격 |
|---|---|---|
| `config/policy/merge_admission.json` `requiredValidations` | `admission-check` @ 365692388, `bsec-integrity` @ 381835906 | 정책 SSOT |
| `src/cli/merge_cli.nim` `RequiredChecks` / `RequiredWorkflowIds` | `admission-check` / 365692388 | 컴파일 상수 미러 (runtime 소비자 0) |
| `tools/merge_ruleset_drift_monitor.nim` | 정확히 2개 context 하드코딩 (`admission-check`, `bsec-integrity`) | 관측 모니터 |

플랫폼 실측(2026-10-21, main `791dd162e…`)은 **세 개**였다:

```
GET repos/Archright/Axiom/rulesets/20303214
  rules[type=required_status_checks].parameters.required_status_checks =
    [{context: admission-check,    integration_id: 15368},
     {context: bsec-integrity,     integration_id: 15368},
     {context: debt-registry-gate, integration_id: 15368}]
  rules[type=merge_queue].parameters = {merge_method: MERGE,
      grouping_strategy: ALLGREEN, max_entries_to_build: 2,
      max_entries_to_merge: 1, min_entries_to_merge: 1, …}
  rules[type=pull_request].parameters.required_approving_review_count = 0
```

즉 모니터는 **live 3-context에 대해 RED**였고(기대 2 ≠ live 3), 정책 SSOT는
`admission-check`를 Axiom callee(365692388)에 묶은 채로였는데 그 바인딩은
**구조적으로 충족 불가능**했다(§3). `debt-registry-gate`는 어디에도 기록되지
않았다.

### 2. 병합 시점 강제(predicate 재검증)는 하지 않는다 — P12 유지

2026-09-29 커밋 `cf648b2f8` (ADR-0025 Amendment B / P12 GitHub 위임)는
check-runs 수집·ruleset detection·required-workflow verdict 패스를
"플랫폼 보증의 중복 재구현"으로 **삭제**했다. predicate는 required status
check의 존재/통과, workflow 정체성, verdict 증거를 **재파생하지 않는다** —
그것은 병합 시점 GitHub(ruleset + org ruleset의 sha 고정 workflow)의 권한이다.

#### P12 재도입을 막는 4중 벽 (재확인)

1. **토큰 스코프** — 생산자 정체성을 predicate가 확인하려면 check-runs
   (`checks:read`)와 workflow run(`actions:read`)을 읽어야 한다. org 게이트
   job의 권한을 함께 바꿔야 하므로 **controller 회전**이 강제된다(또는
   게이트의 job 권한 확대 — 그 자체가 신뢰 경계 변경).
2. **자기참조 교착** — verdict는 org 게이트의 **자기 run 안에서** 실행된다.
   predicate가 자신의 in-flight run을 생산자로 확인하는 구조는 자기 자신을
   거부할 수 있다(삭제된 구현이 문서화한 사망 경로).
3. **rulesets API 권한** — ruleset을 읽으려면 `Administration:read`가
   필요하다. `GITHUB_TOKEN`은 그 권한을 갖지 못한다(workflow `permissions:` 키
  에 `administration` 항목이 없다). 즉 이 재검증은 별도 credential을
   필요로 한다.
4. **커밋된 아키텍처 결정의 역행** — ADR-0025 Amendment B가 "플랫폼이 이미
   수행하는 기능을 재구현하지 말라"를 근거로 **삭제**한 경로를 되살리는 것은
   결정의 역행이다(결정 바인딩 — AGENTS.md §0.10).

따라서 본 ADR은 **판정을 바꾸지 않는다**. 판정·강제는 플랫폼에 남고, Axiom
쪽이 하는 것은 (i) 진실을 한 곳에 기록하고 (ii) 드리프트를 상시 감지하는
것이다.

### 3. 생산자 정체성 readback — 정직한 의미로 기록한다

관찰 대상: merge_group head SHA `5011d9d3a0e11e765b23652219682dd7b3ed2357`
(PR #1010의 merge_group run). check-run의 `details_url` → run → `workflow_id`
경로로 역추적했다(check-run 객체 자체에는 `workflow_id` 필드가 없다).

| required context | check-run의 run | run.workflow_id | run.path | producer |
|---|---|---|---|---|
| `admission-check` | 39581030837 | **386419787** | `.github/workflows/admission-gate-v2.yml` | **org 주입** (repo `Archright/.github`, repository_id 1182157951) |
| `bsec-integrity` | 39581030621 | **381835906** | `.github/workflows/bsec-integrity.yml` | repo-native |
| `debt-registry-gate` | 39581030653 | **389486255** | `.github/workflows/debt-registry-gate.yml` | repo-native |

세 check-run 모두 `app.id = 15368` / `app.slug = "github-actions"`.

**`admission-check`의 생산자 함정.** Axiom 저장소의 `.github/workflows/admission-check.yml`
는 workflow id **365692388**이고(org ruleset이 sha `7e0caa62…`로 고정 호출하는
callee), 이 callee는 org 게이트의 run **안에서** 실행되며 `attest / …`,
`verdict / …` job만 낸다 — **`admission-check`라는 이름의 check-run을 스스로
내지 않는다**. 이름이 `admission-check`인 check-run을 내는 것은 org 저장소의
워크플로이고, 그 run의 `workflow_id`는 386419787이다(주목: org 저장소의
`GET /repos/Archright/.github/actions/workflows`는 admission-gate-v2.yml을
**386400432**로 열거한다 — 386419787은 ruleset이 sha 고정하는 그 revision의
id이며 이 경로로는 주소 지정 불가). 따라서 정책 SSOT의
`admission-check` → 365692388 바인딩은 **어떤 check-run도 충족할 수 없는
바인딩**이었다.

**강한 통제(워크플로 수준 핀).** org ruleset 25218071(`axiom-admission-gate`)의
`workflows` 룰:

```
{path: .github/workflows/admission-gate-v2.yml,
 repository_id: 1182157951, sha: c1752d7ebbcff1d01d82c922a5f97d5b86622880}
```

→ PR이 같은 이름의 check를 위조해도 이 sha 고정 required workflow를 만족하지
못하므로 **병합이 차단된다**. 이름 + `integration_id` 매칭에 더해 워크플로
수준 생산자 핀이 얹힌다. 이 강도는 Axiom 측의 재검증 없이 성립한다.

**약한 통제(앱 수준) + Axiom 측 정체성 미러.** `bsec-integrity` /
`debt-registry-gate`의 `integration_id 15368`은 **앱 수준 통제**다(GitHub
Actions 앱이 아닌 producer는 그 context를 만족할 수 없다). 그러나 앱 내부
동일 이름 위조(PR 자체가 같은 job 이름의 workflow를 정의)는 플랫폼이 막지
않는다. 이 잔여 간극은 **Axiom 측 정체성 결속**이 닫는다 — 정책 SSOT의
`requiredValidations` 항목(path + workflowId + job)이 그 기록이다. v1.12.0가
`bsec-integrity`에 대해 한 것과 **동일 클래스**이며, 본 변경은
`debt-registry-gate`로 그 폐합을 대칭으로 완성한다. 이 결속은 **판정
참조용 기록**이지 병합 시점 재검증이 아니다(P12 유지).

### 4. org self-venue는 비권위적 실패다 (P1)

org 저장소(`Archright/.github`, public)에서 Axiom(private)의 reusable
workflow를 직접 부르면 **public → private 호출은 불가**다(공개 호출자는 공개
reusable workflow만 호출 가능). 실측: org 저장소의 `admission-gate-v2.yml`
run **25건 전부 failure, 0 jobs**(2026-10-21 기준 전량). Axiom 게이트는
무영향이다 — ruleset 25218071은 sha 고정된 워크플로를 **Axiom의 private
컨텍스트**에서 실행한다(오늘의 merge_group run으로 실증). 정식 기록:
[docs/evidence/org-self-venue-expected-failure-2026-10-21.md](../evidence/org-self-venue-expected-failure-2026-10-21.md).

## Decision

### (a) 정규 required-check 집합 = live 3

`admission-check`, `bsec-integrity`, `debt-registry-gate`. **정본은
`config/policy/merge_admission.json`**(기계 판독 정규 SSOT)이며, 이 ADR은
근거 문서다. 두 개의 사본(컴파일 상수, 모니터 기대 집합)이 정본을 복제하지
않는다 — 모니터는 정본에서 **파생**하고, 상수는 정본과 **대조**된다.

### (b) `requiredValidations`에서 `admission-check` 항목을 제거한다

`requiredWorkflowDetection`(org repositoryId 1182157951 + path
`admission-gate-v2.yml` + verdictJob `admission-check`)이 `admission-check`
context의 **정확한 생산자 기록**으로 이미 존재하므로 정본 기록이 중복되지
않고, §3에서 보인 충족 불가능 바인딩(365692388)만 제거된다. 남는
`requiredValidations` 2건은 **repo-native producer의 정체성 미러**다
(bsec-integrity@381835906, debt-registry-gate@389486255).

`requiredValidations`가 비지 않는다는 불변식은 유지된다(f.1 게이트: 각
`workflowPath`는 저장소 루트에 실재해야 한다 — 두 파일 모두 존재).

### (c) `src/cli/merge_cli.nim` 상수는 파생 미러로 동기

`RequiredChecks` = 3개 이름, `RequiredWorkflowIds` = repo-native 2건
(381835906, 389486255). `admission-check`의 **context** 생산자는 repo
workflowId로 표현할 수 없으므로(org 주입) 상수에 넣지 않고, 주석으로
`requiredWorkflowDetection`를 가리킨다(callee = 365692388임을 명시).
runtime 소비자는 여전히 0이며(f.3 게이트의 non-empty 불변식만 유지), 이
상수는 **선언**이지 집행이 아니다.

### (d) 드리프트 감지 ≠ 병합 시점 강제

`tools/merge_ruleset_drift_monitor.nim`은 **사후 관측**이다. 병합을 막지
않고 GitHub 상태를 바꾸지 않는다(GET 전용 — monitor purity 게이트 대상).
병합 차단은 플랫폼이 수행한다: repo ruleset 20303214의 required status
checks(3-context + `integration_id 15368`)와 org ruleset 25218071의 sha 고정
required workflow. 감지기가 강제로 변하지 않는다 — 강제는 플랫폼의 몫이다.

### (e) 상시 드리프트 감지 (신규 `.github/workflows/admission-ssot-drift.yml`)

`schedule`(매일 04:37 UTC — 정각 회피) + `workflow_dispatch`. 드리프트가
있으면 job이 **RED로 실패**한다(관측 신호). **required check가 아니다** —
required 집합은 그대로 3개다. 감지기는 **3변 대조**한다:

| leg | 비교 | credential |
|---|---|---|
| 1 | 정책 ↔ 컴파일 상수 (`RequiredChecks` / `RequiredWorkflowIds`) | 불필요(정적) |
| 2 | 정책 ↔ live ruleset 20303214 | `Administration:read` 필요 |
| 3 | 정책 ↔ live producer (관찰 SHA의 check-runs 생산 App) | `checks:read` 필요 |

credential 2단 계약(명시적, 조용한 폴백 없음): 진단 App 시크릿이 등록된
경우(diagnostic-authority.yml과 동일 패턴으로 job 안에서 installation token
민팅)에는 더 제한된 credential로 leg 2까지 판정한다. 진단 App은 **아직
등록되지 않았다**(GitHub API로 App을 만들 수 없다 — 인간 등록 게이트,
docs/spec/diagnostic_execution_delegation.md §2). 그 경우 job 자신의
`GITHUB_TOKEN`을 쓴다. **실측 정정(2026-10-21, 첫 dispatch run
39603184495)**: 이 토큰은 **repository ruleset을 실제로 읽을 수 있다**
(모니터 출력 `ruleset drift: 4/4 expectations hold`, credential-source =
`GH_TOKEN (pre-set in the environment)`) → tier 2에서도 **3개 leg이 모두
판정된다**. ruleset 읽기가 실패하면 모니터가 그 leg을 `NOT PERFORMED`로
명시 보고한다(degraded mode — 조용한 생략 금지, 부분 판정을 전체 GREEN으로
위장하지 않는다).

### (f) 회전 동반 (rotation companion)

`src/cli/merge_cli.nim`은 `trustedCheckerTreeClosure`의 멤버다
(`config/trusted_writer_set.json`, 879 멤버). 유도 line-set이
`<mode> <type> <sha>\t<path>`(= blob sha 포함) 형식이므로 멤버 **내용**을
바꾸면 derived(H) ≠ pin@H가 되어 Pass 2.75가 `ROT_NEW_PIN`으로 거부한다.
따라서 같은 PR에서 `config/trusted_writer_set.json`의 해당 sha를 재앵커
한다(`RotationPinBPath`는 이미 회전 allowlist에 있음). 동반 경로 4건
(`config/policy/merge_admission.json`, `docs/adr/0035-admission-ssot.md`,
`.github/workflows/admission-ssot-drift.yml`,
`docs/evidence/org-self-venue-expected-failure-2026-10-21.md`)은
`RotationAllowlistExtra`에 열거한다 — 열거형만, glob 없음(A4 규율), 비멤버
production `src/`는 계속 밖(A2 (i)).

## Consequences

- **required-check 집합이 3개로 확정**되고, 그 사실은 정책 SSOT 한 곳에
  기록된다. `debt-registry-gate`가 이제 정책에 존재한다(신규 trustSurface
  항목 포함 — v1.12의 bsec 스푸프 폐합과 대칭).
- 모니터가 live 상태에 대해 **GREEN**이 되었다(기존엔 하드코딩 2-context로
  RED). 기대 집합이 정책에서 파생되므로 앞으로 정책이 바뀌면 모니터는 자동으로
  새 기대 집합을 따른다(하드코딩 drift는 구조적으로 불가능).
- **`admission-check`의生产者 통제는 org ruleset 25218071의 sha 핀에 의존**한다.
  Axiom 측 재검증을 넣지 않았으므로(4중 벽), 그 룰이 해제되면 **Axiom은 즉각
  감지하지 못한다** — 대신 org 룰 자체의 변경은 org 저장소에서 별도 게이트
  대상이다. 이 잔여는 명시적으로 기록한다.
- 상시 감지는 **관측**이며 강제가 아니다. 감지기가 빨간 job을 내도 병합은
  막히지 않는다(막는 것은 required check와 ruleset).
- 진단 App이 등록되기 전까지 tier 2(작업 GITHUB_TOKEN)로 동작하며, **실측
  기준 leg 2도 판정된다**(ruleset readback 4/4 PASS). 등록은 인간 게이트이며
  본 변경의 범위 밖이다.
- **첫 dispatch run의 측정(2026-10-21, run 39603184495)** — leg 1 2/2 PASS,
  leg 2 **4/4 PASS**(작업 GITHUB_TOKEN으로 ruleset readback 성립), leg 3
  2/3 — `admission-check` check-run이 관찰 SHA에 없음. 원인: 관찰 대상이
  **진행 중**인 merge_group run의 head_sha였고(그 run의 check-run이 아직
  생성되지 않음) monitor의 fail-closed 규칙(`missing != clean`)이 정직하게
  red를 낸 것이다 — 감지기 결함이 아니라 **관찰 대상 선택 결함**이었다.
  정정: 착지 **완료·성공**한 merge_group run의 head_sha(= main의 merge
  commit)만 관찰한다(후속 PR).

## Out of Scope

- predicate 내 check-runs 수집·생산자 재검증(P12 반전) — 4중 벽.
- required-check 집합의 변경(3개 → 그 외). 본 ADR은 집합을 **기록**할 뿐
  새 required check를 추가하지 않는다(신규 드리프트 워크플로는 required
  check가 아니다).
- 진단 App 등록(인간 게이트) · org ruleset 25218071 재핀(P2 회전).
- org self-venue의 해결(비권위적 실패로 수용 — §4).
