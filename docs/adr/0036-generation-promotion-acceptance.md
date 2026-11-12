# ADR-0036: Generation Promotion Acceptance (GPA) v1 — 새 세대의 승격 전 판정 게이트

## Status

**Proposed (2026-10-22)** — 아키텍처 결정 기록이며 구현을 수반한다
(`.github/workflows/generation-acceptance.yml`,
`config/policy/merge_admission.json` v1.16.0, `src/cli/merge_cli.nim` 상수
동기, `tools/promotion/validate_manifest.sh`, 단위 테스트 동반 — 단일 PR).
상위 결정: [ADR-0025](0025-gateway-landing-authority.md) Amendment B(P12 —
GitHub 위임) · [ADR-0027](0027-queue-delegation.md)(병합 권한 위임) ·
[ADR-0032](0032-admission-venue-split.md)(베뉴 분할) ·
[ADR-0035](0035-admission-ssot.md)(required-check SSOT 정합).

## Context

### 1. "첫 production 실행 = 첫 테스트" 구조

현재 Axiom의 새 검증·정책 세대는 **착지(=production 실행)한 뒤에야** 자신의
정합성이 관측된다. 승격 전 검증 슬롯이 없다. 그 결과:

- 결함이 있는 세대가 live 권한을 얻은 **뒤에야** 관측된다(448건 중 pre-merge
  예방 0건 — v5 증거 계약의 실측).
- 탐지 신호는 대개 **사람이 읽어야** 하는 issue다. 그 사이 세대는 이미
  병합되어 있다.
- "이 세대가 정말 적합한가"를 **기계**가 판정하는 수단이 없다 — 적합성
  판정은 전부 사람이 하거나, 착지 후 사후 관측으로 대체된다.

GPA는 이 구조를 바꾼다. **승격 전에**, 신뢰된 판정기가 후보 세대의
적합성을 기계 판정하고, 승인된 정확한 SHA만 승격하며, 승격 이후의 실제 운영
상태까지 증거로 연결한다.

### 2. 왜 지금 필요한가 — required check 집합은 이미 확장되고 있다

[ADR-0035](0035-admission-ssot.md)가 정규 required-check 집합을 live
ruleset 20303214와 맞췄다(3-context). GPA v1은 여기에 **4번째 context**를
추가한다. 그 순간부터 "required 집합에 새 항목을 추가하는 것" 자체가
안전 민감한 행위가 된다 — 새 항목을 추가하는 PR이 그 항목을 *자기 자신이
만들어 낸다*는 모순이 있기 때문이다. 그 모순을 깨는 유일한 정직한 해법은
**신뢰된 Driver가 후보를 데이터로 검증하는 것**이다.

### 3. 플랫폼이 강제하지 못하는 것 (MUST 목록)

| # | 사실 | 근거 |
|---|---|---|
| MUST#1 | merge queue는 merge_group head에서 required check를 평가한다. 최종 병합 권한 = GitHub. | events 문서 / ADR-0027 |
| MUST#2 | schedule은 지연·드랍 가능하고 default branch 최신 커밋에서 실행된다 → cron만으로는 "미발화"를 감지할 수 없다. | GitHub schedule 문서 |
| MUST#3 | skipped job은 Success로 보고된다 → required check job은 **절대 skip 없이** 항상 실 verdict를 보고해야 한다. | GitHub Actions 문서 |
| MUST#4 | required check 이름은 workflow/event 격리가 없다. integration_id는 App 단위다. | rulesets API |
| MUST#5 | `file_path_restriction` push rule + bypass_actors로 워크플로 파일 변경이 통제된다(라이브 실측). | repo ruleset 23967915 |
| MUST#6 | pull_request_target은 base 권한으로 후보 코드를 실행한다 → GPA는 후보를 권한 상승 환경에서 실행하지 않는다. | GitHub 보안 문서 |
| MUST#7 | **pull_request 실행은 PR의 merge commit에 있는 워크플로 파일을 실행하고, 기본 checkout도 그 merge commit이다.** → 신뢰 코드는 명시적으로 base ref에서 체크아웃해야 한다. | pull_request_target 보안 문서: "it runs the workflow file from the **merge commit of the pull request**… actions/checkout … checks out the pull request's merge commit" |
| MUST#8 | org ruleset 조회·bypass_actors는 Administration org write 권한이 필요하다 → GPA job의 토큰으로 직접 보장 불가. | REST GET /orgs/{org}/rulesets 문서 |
| MUST#9 | **merge_group head ≠ PR head** (큐의 임시 merge 커밋) → 승격 증거의 SHA 관계는 이 차이를 가정하면 안 된다. | events 문서 + repo v1.10.0 정책 실측("merge_group.base_sha == parents(G)[0]") |

MUST#7은 이 ADR의 **중심 설계 근거**다. §3(a)에서 다룬다.

## Decision

### (a) 궁극 목적과 4개의 독립 보장

GPA의 궁극 목적은 단 하나다.

> **새 검증·정책/방어 세대가 운영 권한을 얻기 전에, 신뢰된 판정기(Acceptance
> Driver)가 그 세대의 적합성을 검증하고, 승인된 정확한 SHA만 승격하며, 승격
> 이후의 실제 운영 상태까지 증거로 연결한다.**

여기서 4개의 보장은 서로 독립이며, 각각 다른 실패 모드를 다룬다.

| 보장 | 무엇을 막는가 | GPA의 성격 | 판정 주체 |
|---|---|---|---|
| **PREVENT** | 결함 후보의 승격 + live 불변(규칙셋·핀) | 착지 **전** 기계 판정 | Driver(베이스) |
| **DETECT** | 운영 불일치(드리프트) → 운영자 수신 신호 | 착지 **후** 사후 관측 | 상시 드리프트 감지(기존) + manifest readback |
| **RECOVER** | 자격 없는 자동 복구 | 자동 복구를 하지 않고 **정직한 비활성 선언**을 남긴다 | 운영자 runbook |
| **SUSTAIN** | 차세대 변경에도 동일 절차 미적용 | 두 번째·세 번째 승격이 **같은 프로토콜**로 반복된다 | GPA 자체(프로토콜의 재사용) |

**RECOVER의 정의가 중요하다.** GPA는 "문제가 생기면 스스로 고친다"를 하지
않는다. 자동 복구가 불가능한 경우(GPA 자기 파손, 라이브 강제 집합의
불일치)에는 **비활성을 명시하고 수동 runbook을 따른다.** 성공 위장은
극장이며(AGENTS.md §0.9), 발견된 극장은 부채로 등록한다.

### (b) 상태 기계: CANDIDATE → ACCEPTED → LANDED → ACTIVE

각 상태는 **기계 검사**로만 판정한다. "사람이 아는 것"은 판정 근거가
아니다.

| 상태 | 진입 조건 | 기계 검사 | 실패의 의미 |
|---|---|---|---|
| **CANDIDATE** | 후보 head SHA가 서버에서 확정됨 | (1) 서버 유래 변경 파일 목록 획득(PR files API / compare API)(2) 로컬 diff witness로 목록 완전성 교차 검증(3) execution surface 교집합 계산 | 후보를 **관측할 수 없다** → `REJECTED:DIFF_UNAVAILABLE`. "관측 불가"는 "일치"가 아니다. |
| **ACCEPTED** | GPA verdict = ACCEPTED | (1) check-run `generation-acceptance`이 후보 SHA에 존재(2) conclusion=success(3) merge_group run이면 run.head_sha가 큐의 임시 커밋 | L1~L4 중 하나가 거부했거나, 판정 기록이 빠졌다. → 각 거부 코드 참조. **ACCEPTED는 "승격 가능"이라는 뜻이지 "승격되었다"가 아니다.** |
| **LANDED** | 후보가 main에 merge됨 | (1) PR.merge_commit_sha 존재(2) manifest.mergeSha == PR.merge_commit_sha(3) acceptanceRun.event == merge_group && head_sha == 그 임시 커밋 | mergeSha ≠ 실제 mergeCommit → **승격 완료로 선언할 수 없다**(기록과 실측의 불일치). |
| **ACTIVE** | 착지된 세대가 실제로 운영 중 | (1) productionRun.head_sha == mergeSha(2) main 실행이 success(3) ruleset readback의 expected == actual(operator-promotion-adapter provenance) | readback 불일치 → **운영 상태가 선언된 것과 다르다**. STOP + 복구(rotation) 경로. |

`REJECTED`는 사다리의 상태가 아니라 **거부 결과**다. 후보는 그 자리에서
멈춘다(승격되지 않는다). 다음 코드 어휘를 **사전 정의**한다 — 새 코드는
문서 갱신 없이 추가하지 않는다.

| 코드 | 단계 | 의미 |
|---|---|---|
| `NO_SURFACE_DELTA` | fast-path | 후보가 execution surface를 건드리지 않았다 → 전체 검증 부적용(ACCEPTED). |
| `YAML_PARSE` | L1 | 후보의 변경된 workflow/action YAML이 파싱되지 않는다(실행 가능 결함). |
| `POLICY_RULESET_MISMATCH` | L2 | 후보의 정책/상수가 live ruleset과 어긋난다(강제 집합의 축소·변형). |
| `RULESET_UNAVAILABLE` | L2 | live ruleset을 읽지 못했다(관측 불가 → fail-closed, degraded mode 금지). |
| `UNPROMOTED_PIN` | L3 | 승격 정합성이 깨졌다(epoch pin ≠ TWS sha ≠ admission-check.yml blob). |
| `SELF_TEST_FAILED` | L4 | Driver(또는 격리 실행된 후보 모니터)가 known-bad fixture를 통과했다(판정 로직이 결함을 못 잡는다). |
| `TOOLCHAIN_UNAVAILABLE` | 전 단계 | 판정에 필요한 도구/모듈을 사용할 수 없다(검증 불가 → fail-closed). |
| `DIFF_UNAVAILABLE` | surface | 서버 유래 변경 파일 목록을 취득하지 못했다(잘림 포함). |
| `INCOMPLETE` | 최종 결론 | 어떤 단계도 결과를 기록하지 않았다 — **생략은 성공으로 읽히지 않는다**. |

### (c) Driver / Candidate 분리 — 왜, 그리고 어떤 사실이 근거인가

**원칙.** 판정 로직(L1~L4)·fixture·판정 기준은 **전부 base ref에서 체크아웃한
Driver 트리**에서 온다. 후보는 `path: candidate`의 **데이터**로만 존재하며
**실행되지 않는다**(후보 실행 코드가 필요해지는 경우에만 §3(c-ii)의 격리
절차를 거친다).

**근거(MUST#7).** pull_request 이벤트는 **PR의 merge commit에 있는 워크플로
파일**을 실행한다. GitHub 공식 문서(pull_request_target 보안 문서)는 이를
"it runs the workflow file from the **merge commit of the pull request** …
actions/checkout … checks out the pull request's merge commit"로 명시한다.
즉 기본 동작에서는 (i) 실행되는 워크플로 파일이 후보가 쓴 파일이고,
(ii) 체크아웃된 트리도 후보가 쓴 트리이다. **자기 판정**(candidate judges
itself)이 구조적으로 성립한다 — 후보가 GPA 워크플로를 조작하면 그 조작된
판정기가 그 조작을 검사한다. 이건 검증이 아니라 theater다.

**따라서.** Driver는 `ref: ${{ github.event.merge_group.base_sha ||
github.event.pull_request.base.sha }}`로 **명시적으로 base**를 체크아웃하고,
후보는 `ref: ${{ github.event.merge_group.head_sha ||
github.event.pull_request.head.sha }}`로 별도 경로(`path: candidate`)에
체크아웃한다. workflow_dispatch(수동 재검증)에서는 `github.sha`와 그 첫
부모를 쓴다.

**거부.** GPA 워크플로 자체는 trustSurface(§3-f)에 등재되어 push rule로도,
자동 병합 거부 경로로도 통제된다. 후보가 GPA 워크플로를 바꾸는 경로는
**운영자 rotation 경로뿐**이며, 그 경로에서도 Driver 분리는 유효하다
(후보가 신뢰 트리를 바꿀 수 없으므로).

**(c-i) L2의 candidate 값 주입 방법 — 드리프트 도구의 실제 인터페이스.**
`tools/merge_ruleset_drift_monitor.nim`은 기대 집합을 **정책 SSOT에서
파생**한다(hardcode 없음). 그래서 "후보가 착지 후 live가 될 값"으로
판정하려면 **비교 입력만 교체**하면 된다. 도구가 실제로 지원하는 CLI는
`--policy-file` / `--merge-cli-source` / `--ruleset-file` / `--repo` /
`--ruleset-id` / `--observe-sha` / `--allow-unavailable-ruleset` 이며, GPA는
**base 트리에서 빌드한** 도구에 다음을 넘긴다.

```
bin/gpa_drift_monitor \
  --policy-file candidate/config/policy/merge_admission.json \
  --merge-cli-source candidate/src/cli/merge_cli.nim \
  --ruleset-file <live ruleset JSON>
```

→ 기대 집합은 **후보의 정책에서** 파생되고(leg 1: 후보 정책 ⇔ 후보 상수),
live ruleset과의 대조는 **live 상태에 대해** 수행된다(leg 2). 인자 지원이
없어 정책/상수 파일을 임시 디렉터리에 복사해 경로를 오버라이드하는 우회
설계는 **필요하지 않다** — 도구가 이미 그 인자를 노출한다.

**(c-ii) 후보 실행 코드의 격리.** GPA v1에서 후보 트리의 코드를 실행하는
경로는 하나뿐이다 — 후보가 `tools/merge_ruleset_drift_monitor.nim`을
변경했을 때의 L4-iso. 그 실행은 **별도 무권한 step**에서 일어난다:
`GH_TOKEN`/`GITHUB_TOKEN`/`ACTIONS_RUNTIME_TOKEN` 미설정, repo write 권한
없음, 그 **출력은 Driver(베이스)가 판정한다**(출력이 판정이 아니다).
이 원칙은 GPA가 확장될 때에도 유지된다.

**격리 step의 빌드 위치는 워크스페이스 밖이다.** `candidate/`는
워크스페이스(= Driver 트리) 안에 있으므로 그 조상 체인에 Driver 트리의
`config.nims`가 들어간다. Nim은 **조상의 config.nims를 모두** 로드하므로
두 개의 `src/`가 이중 등록되어 어떤 타깃도 빌드할 수 없다
([docs/spec/nested_worktree_config_quirks.md](../spec/nested_worktree_config_quirks.md)).
따라서 L4-iso는 후보 트리를 `runner.temp`(조상에 `config.nims`가 없는
경로)에 worktree로 다시 materialize해 그곳에서 빌드한다 — 격리는
credential뿐 아니라 **빌드 환경의 결정성**까지 포함한다.

### (d) 증거 3-티어 — GPA가 실제로 보장하는 범위

| 티어 | 대상 | 증거 원천 | GPA의 권한 |
|---|---|---|---|
| **GPA 직접** | repo ruleset 20303214, 정책 파일, epoch/TWS/blob 정합 | job의 GITHUB_TOKEN | job `permissions:`에 administration 항목이 없어도 repo ruleset은 읽힌다(실측 2026-10-21, drift run 39603184495 — ruleset drift 4/4 PASS) |
| **operator-adapter** | org rulesets 25218071/23943917 pin, bypass actors, promotion manifest의 readback | org-admin `gh` (운영자) | **GPA는 조회 불가**(MUST#8). provenance `operator-promotion-adapter`를 명시해 **소비만** 한다 |
| **UNKNOWN** | 위 두 경로로 확보 못한 값 | — | manifest에 UNKNOWN으로 기록 → **승격 완료 선언 불가 조건** |

**원칙.** GPA가 읽지 못한 값은 UNKNOWN이다. 관측 불가값을 "검증됨"으로
기록하는 것은 theater다. operator-adapter 증거는 provenance를 명시해
소비한다 — "누가·어떤 경로로 읽었는지"가 붙지 않은 readback은 증거가
아니다.

### (e) L1~L4 — 판정 단계와 fast-path

**fast-path.** 변경 경로가 **execution surface**와 교집합이 없으면 verdict
`NO_SURFACE_DELTA`로 즉시 ACCEPTED한다. execution surface는

> `merge_admission.json`의 `trustSurface` ∪ `.github/workflows/**` ∪
> `.github/actions/**` ∪ `config/policy/**` ∪ `dynamic/**`

다. (trustSurface는 **베이스 트리**의 값을 쓴다 — Driver의 기준.) fast-path는
"검증 대상이 없다"는 **명시적 결론**이며, 검증을 생략한 것이 아니다.

| 단계 | 판정 | 거부 코드 |
|---|---|---|
| **L1 정적** | 후보의 변경된 workflow/action YAML을 `yaml.safe_load`로 파싱 | `YAML_PARSE` |
| **L2 정책 3-leg** | base 빌드 드리프트 도구로 후보 정책 ⇔ 후보 상수 ⇔ live ruleset 대조 | `POLICY_RULESET_MISMATCH`, `RULESET_UNAVAILABLE` |
| **L3 승격 정합** | `epoch_manifest.productionExecutionPin` == `trusted_writer_set.trustedAdmissionWorkflowSha` == 후보 트리 `admission-check.yml`의 git blob SHA | `UNPROMOTED_PIN` |
| **L4 자기 시험** | 후보 SHA에서 결정론 유도한 known-bad fixture를 Driver의 L2 로직이 **반드시 거부**하고 known-good은 통과 | `SELF_TEST_FAILED` |

**L2의 요구 집합 변경 규칙.** 후보가 요구 집합을 live ruleset과 어긋나게
바꾸면(추가·삭제·변형 무관) `POLICY_RULESET_MISMATCH`다. **단 하나의 예외**:
후보가 **자기 자신의 context(`generation-acceptance`) 하나만** 추가하고,
라이브 강제 집합이 **축소되지 않을 때**(베이스 집합 ⊆ live 집합)는
`PROMOTION_PENDING`로 명시 기록한다. 그 예외가 필요한 이유는 §3(g)의
부트스트랩 조항과 같다 — **필요한 ruleset PUT이 착지 뒤에 오는 경로**에서
후보 PR이 먼저 존재해야 하기 때문이다. 이 예외는 "안전성이 낮아지지 않는
방향"(강제 집합의 축소 부재)만 허용하며, 그 밖의 추가·삭제는 모두 거부한다.

**L4의 fixture 결정론.** 변조 대상 context는 후보 SHA의 마지막 nibble를
기준으로 `index = 16#nibble mod N`로 결정한다. 고정 fixture는 공격자가 미리
맞출 수 있으므로, fixture 선택을 후보 SHA의 함수로 만들어 특수화 공격을
저항한다. fixture의 **내용**(기준 정책)은 Driver(베이스) 트리에서 온다 —
판정 로직 자체를 시험하는 것이지 후보의 정책을 시험하는 게 아니다. 기준선은
합성 ruleset fixture(베이스 정책의 기대 집합을 그대로 담은 JSON)다 — live
상태는 L2의 몫이고, L4는 **판정 로직이 결함을 구분하는지**를 본다.
known-good은 반드시 통과해야 하고(정상 입력을 거부하는 판정 로직도 결함이
다), known-bad은 반드시 거부되어야 한다.

**L3의 "변경 없으면" 처리.** 승격 권한 파일(`admission-check.yml`,
`epoch_manifest.json`, `trusted_writer_set.json`)을 후보가 바꾸지 않았으면
후보 트리의 값은 베이스의 값과 동일하므로, 후보 트리에서 검사한 결과가 곧
"베이스 값 정합성" 검사가 된다. 후보 트리 기준 검사는 이 경우를 엄밀히
포함하면서 동시에 "후보가 핀을 깨지 않았다"를 함께 보장한다.

### (f) Manifest 스키마와 관계 검증 5항

manifest는 `data/promotions/<id>/manifest.json`에 산출한다. **스키마
검사(필수 필드 존재·형식)와 관계 검증을 분리된 함수로** 수행한다
(`tools/promotion/validate_manifest.sh`).

```jsonc
{
  "schemaVersion": 1,
  "repository": "Archright/Axiom",
  "promotionId": "<id>",
  "candidateSha": "<PR head SHA>",
  "candidatePr": 1234,
  "mergeSha": "<PR mergeCommit oid>",
  "acceptanceRun": {
    "id": 123456789,
    "workflow": "generation-acceptance",
    "event": "merge_group",
    "conclusion": "success",
    "headSha": "<merge_group 임시 커밋 — PR head와 다르다>"
  },
  "rulesetReadback": {
    "provenance": "operator-promotion-adapter",
    "fetchedAt": "<ISO-8601>",
    "expected": [ { "context": "...", "integration_id": 15368 } ],
    "actual":   [ { "context": "...", "integration_id": 15368 } ],
    "equal": true
  },
  "productionRun": {
    "id": 987654321,
    "workflow": "<착지된 세대의 production 워크플로>",
    "event": "push",
    "headSha": "<= mergeSha>"
  }
}
```

관계 검증 5항(모두 `gh` 실측 + `jq` — 선언값과 실측값의 대조):

1. **acceptanceRun** — 저장소가 Axiom이고, 워크플로가 `generation-acceptance`이며,
   `event == merge_group`, `conclusion == success`, 그리고 기록된 `headSha`가
   API 실측 run의 `head_sha`와 같다. **merge_group head는 PR head와 다르다**
   (MUST#9) — 이 차이를 가정하지 않고, 각자 별개의 관계로 검증한다.
2. **candidateSha == PR head SHA** — 후보 PR의 head SHA를 PR API로 실측해
   대조한다.
3. **rulesetReadback** — provenance이 `operator-promotion-adapter`이고,
   `fetchedAt`·`expected`·`actual`·`equal`가 모두 존재하며(빈 값·UNKNOWN
   금지), `expected == actual`이다(배열은 정렬 후 원소 단위 비교).
4. **productionRun.head_sha == mergeSha** — 착지된 세대의 main 실행이
   mergeSha에서 실행되었는지.
5. **mergeSha == PR.merge_commit_sha** — 기록된 merge 커밋이 실제 merge 커밋인지.

**UNKNOWN 금지.** manifest의 어느 문자열 값이든 `UNKNOWN`/`TBD`/빈 문자열이면
검증은 즉시 실패한다 — "아직 모른다"는 "성공"의 근거가 아니다.

**결정론.** 같은 입력 → 같은 출력. 배열 비교는 정렬 후 비교하고, 시간·무작위
값을 출력하지 않는다.

### (g) 부트스트랩 조항 — GPA v1은 어떻게 착지하는가

**GPA v1 자체는 현행 v5.1 세대의 회전 경로로 착지한다.** 즉 GPA를 다루는
PR은 일반적인 신뢰 표면 PR이 아니라 **운영자 rotation 경로**를 탄다. 그
경로가 이미 강제되고 있는 근거:

- `config/policy/merge_admission.json`의 `trustSurface`는
  `.github/workflows/**` 변경을 **자동 병합에서 거부**한다(차단 → 운영자
  수동 병합). GPA 워크플로의 신규는 이 표면에 해당한다.
- repo ruleset의 push rule `file_path_restriction` + bypass_actors(MUST#5)가
  워크플로 파일 변경을 통제한다. 후보 PR은 이 push rule에 걸리므로, GPA
  워크플로를 바꾸는 경로는 운영자 bypass뿐이다.
- 두 표면 모두에서 **auto-merge는 거부**되고, 그 거부 자체가 "이 변경은
  사람이 봐야 한다"는 신호다.

**이 부트스트랩 조항이 명시하는 것**: (1) GPA v1이 자기 자신의 승격
acceptance를 요구하는 것은 순환이 아니다 — GPA v1의 요구 집합 변경은
§3(e)의 `PROMOTION_PENDING` 예외로 처리되며, **lib의 강제 집합이 축소되지
않는 방향**의 예외다. (2) GPA v1의 첫 두 관측(자기 PR → docs-only probe
PR)은 fast-path green을 먼저 확인하고, 그 다음에야 유일성 검증을 통과한
뒤 ruleset PUT을 수행하고, PUT 후 readback 일치를 확인하고, 마지막으로
manifest의 관계 검증을 통과시킨다. **ruleset PUT은 착지 뒤**다(플랫폼
강제 집합에 새 항목을 넣는 것은 그 항목을 강제할 워크플로가 존재하고
검증된 뒤에야 안전하다).

### (h) 실패 주입 acceptance의 분리

"GPA가 잡아야 하는 결함"과 "GPA가 스스로 부서지는 경우"는 **기대 결과가
다르다**. 한 종류의 기대로 둘을 검사하면 안 된다.

| 주입 | 기대 결과 | 도달 경로 | 판정 |
|---|---|---|---|
| 후보 workflow yaml 파손 | GPA 정상 실행 → RED + `REJECTED:YAML_PARSE` | 후보 PR | PREVENT |
| 정책↔ruleset 불일치 / epoch 정합성 파괴 | GPA 정상 실행 → RED + `REJECTED:POLICY_RULESET_MISMATCH` / `REJECTED:UNPROMOTED_PIN` | 후보 PR | PREVENT |
| **GPA 자기 yaml 파손** | GPA check 자체가 **미보고** → required check 미충족 = **fail-closed 병합 블록**(queue `check_response_timeout` 120min). GPA의 REJECTED 로그를 **기대하지 않는다.** | 운영자 rotation 경로만 (후보는 push rule 차단) | RECOVER(정직한 비활성) |
| 공통 | 주입 전후 live ruleset·pin readback가 **바이트 동일** | — | PREVENT의 불변성 |

GPA 자기 파손에서 "GPA가 스스로 REJECTED를 낸다"는 기대는 **WRONG
EXPECTATION**이다 — 그 경우 GPA는 실행조차 못 한다. 기대되는 관측은
"check-run 부재"이며, 그 결과는 병합 불가(fail-closed)다. 이 구분을
ADR에 명시하는 이유: 통상적인 "게이트가 빨간 job을 낸다"라는 기대를 적용하면
자기 파손을 **놓친다**(기대 불일치로 오독하면 "고장"으로 보일 뿐 "안전 정지"
로 보이지 않는다).

### (i) 유일성 사전 검증 — required 등록의 전제

required check 이름에는 **workflow/event 격리가 없다**(MUST#4). 따라서
`generation-acceptance`이라는 context를 **유일한 생산자**가 내야 한다.
다음 검사를 **통과한 뒤에** required 등록이 가능하다("유일 producer" 선언은
이 검증 이후에만 한다).

```bash
# (1) 최근 main의 check-run에 같은 context가 없는가
gh api /repos/Archright/Axiom/commits/main/check-runs --jq '.check_runs[].name' \
  | grep -Fx 'generation-acceptance' && echo "CONFLICT" || echo "absent"
# (2) 저장소의 모든 워크플로에 같은 job 이름이 없는가
grep -rn "generation-acceptance" .github/workflows/ .github/actions/ dynamic/ || true
# (3) 동등한 이름의 다른 생산자가 없는가
gh api /repos/Archright/Axiom/actions/workflows --jq '.[].name' | grep -i 'generation' || true
```

**같은 이름의 다른 생산자가 발견되면 등록하지 않는다** — 유일성이 깨진 상태
에서 required check로 등록하면, 그 이름으로 병합을 통과시킬 수 있는 주체가
둘이 되어 MUST#4의 공백(앱 내부 same-name 스푸프)이 그대로 열린다. 그 경우
해결 경로는 이름 변경이다(등록 후 이름 변경은 더 비싸다).

### (j) 명시적으로 수용하는 위험

**(j-1) 같은 App 내 same-name은 플랫폼이 차단할 수 없다.** ruleset의
`required_status_checks`는 App 단위(`integration_id`) 통제만 있고, App 내부
같은 이름의 job은 구분하지 않는다. 따라서 PR이 스스로 같은 이름의 워크플로를
정의해 그 context를 만족시킬 수 있다(플랫폼 수준). Axiom 측의 대응은
**정책 SSOT의 정체성 바인딩**(`requiredValidations[].workflowPath` +
`workflowId` + `job`)이며, 이는 **판정 참조용 기록**이지 병합 시점 재검증이
아니다(P12 유지). 이 잔여는 [ADR-0035](0035-admission-ssot.md) §3이 이미
기록한 것과 **동일 클래스**이며, v1.15.0의 P12 기록과 일치한다. GPA
v1.16.0의 `generation-acceptance` 항목은 `workflowId`가 placeholder(null)
이므로 **현재는 이 바인딩조차 미등록**이다 — 착지 후 재등록이 선행되어야
정체성 기록이 완성된다.

**(j-2) bypass 2 integration 내부자 위험.** push rule의 bypass_actors에
Integration 2개(29110·4879411)가 존재한다(라이브 실측). 이들의 신원은
baseline 조사에서 확정해 기록해야 하며(현재 UNKNOWN), 그 계정들은 워크플로
파일 변경 경로를 우회할 수 있다. 이 위험은 GPA가 **줄이는 것이 아니라
기록하는 것**이다 — bypass는 워크플로 변경 그 자체를 막지 못한다. GPA는
bypass로 착지한 변경에 대해서도 **acceptance를 수행**한다(후보가 base ref
분리를 우회할 수 없으므로).

**(j-3) `dynamic/dependabot/*` 경로.** 해당 경로의 생성 주체·범위는
baseline 조사에서 확정되지 않았다(UNKNOWN). execution surface에 `dynamic/**`
를 포함시키는 이유가 이것이다 — 경로의 주체를 알지 못하되, 그 경로가
실행 표면일 가능성을 배제할 수 없으므로 교집합 검사에 포함한다. 경로
주체가 확정되면 이 포함은 재검토 대상이다.

**(j-4) live ruleset 드리프트가 GPA를 전부 막는다.** L2는 후보의 정책과
live ruleset을 대조한다. live ruleset이 후보와 무관하게 드리프트한 상태
(예: 사람이 required check를 하나 제거)라면 GPA는 **모든 신뢰 표면 PR을
거부**한다. 이는 fail-closed의 의도된 결과다(부분 판정을 GREEN으로
위장하지 않는다)이며, 운영자 조치(규칙셋 복구)가 필요하다. 이 사실은
ADR에 명시한다 — "GPA는 드리프트 상태에서 조용히 통과하지 않는다".

### (k) P12 경계 — GPA는 병합 판정을 재구현하지 않는다

GPA는 **판정만 생산한다**. 병합 가능 여부를 강제하거나, GitHub의 규칙셋
판정을 재현하지 않는다. 그 경계를 넘으려면(check-runs 수집·생산자 재검증·
predicate 재작성) ADR-0025 Amendment B의 4중 벽(토큰 스코프 / 자기참조
교착 / rulesets API 권한 / 커밋된 결정의 역행)을 다시 부딪히며, 결정
바인딩(AGENTS.md §0.10) 위반이 된다. 강제(merge decision)는 **GitHub의
몫**이고, GPA는 그 결정에 필요한 **증거를 생산하는 수단**이다.

## Consequences

- **PREVENT**: 신뢰 표면 PR이 병합 전에 기계 판정을 통과해야 한다(필요조건).
  결함 후보는 `REJECTED:<코드>`와 함께 멈춘다.
- **판정은 격리된다**: 후보의 코드는 실행되지 않는다(격리 step 예외).
  후보가 self-judge할 수 없다(MUST#7의 구조적 배제).
- **신규 required context가 4번째로 추가된다**(ruleset 20303214). GPA는
  그 context의 **자기 등록**이며, 등록은 유일성 사전 검증(§3-i) 이후
  운영자 action이다.
- **정책 SSOT가 v1.16.0으로 올라간다**: `requiredValidations`에
  `generation-acceptance` 항목(workflowId placeholder)이 추가되고,
  `trustSurface`에 해당 워크플로 경로가 추가된다. `src/cli/merge_cli.nim`
  의 `RequiredChecks`는 4개 이름으로, `RequiredWorkflowIds`는 **아직 2개**
  (placeholder 상태 — 착지 후 재등록 커밋에서 함께 추가된다). 두 선언이
  어긋나면 드리프트 도구가 RED로 판정한다(fail-closed).
- **`docs/adr/**`는 회전 allowlist에 이미 포함**되어 있고, 본 회전의
  동반 2경로(신규 워크플로·manifest 검증 스크립트)는
  `RotationAllowlistExtra`에 열거형으로 추가했다(A4 규율 — glob 없음).
- **비용**: L2/L4는 base 트리의 드리프트 도구를 빌드하므로 툴체인 비용이
  든다. 이는 **execution surface를 건드리는 PR에서만** 발생한다
  (fast-path는 비용 0).
- **자기 참조의 정직성**: GPA가 요구 집합에 자신을 추가하는 것은 순환이
  아니다(§3-g). 순환이 생기는 유일한 지점은 **workflowId 재등록**이며,
  그 미등록 상태는 명시적으로 placeholder로 남아 있다(숨기지 않는다).

## Out of Scope

- GitHub 병합 판정의 재구현(P12) · predicate 내 check-runs 수집·생산자
  재검증(ADR-0025 Amendment B의 4중 벽).
- org ruleset의 bypass actor 관리 · org ruleset 재핀(Administration org
  write 필요 — 운영자 영역).
- 진단 App 등록(인간 게이트) · App 프로비저닝(rearm).
- `schedule` 기반 누락 감지의 자동화 — cron은 자기 미발화를 감지할 수 없다
  (MUST#2). 두 번째 승격(closure-watcher freshness watchdog)에서 다룬다.
- 규칙셋 변경 자체 — GPA는 **판정**하고 운영자가 **변경**한다.
- v5/v5.1 증거 계약·A/B/C/D 재검증 · 부채 정리.

## Follow-up (착지 후, 순서 고정)

1. **유일성 사전 검증**(§3-i) 통과 확인 — 통과 전에는 required 등록 금지.
2. **workflowId 재등록**: `gh api /repos/Archright/Axiom/actions/workflows`
   로 `.github/workflows/generation-acceptance.yml`의 id를 확인하고,
   `config/policy/merge_admission.json`의 `requiredValidations` 항목과
   `src/cli/merge_cli.nim`의 `RequiredWorkflowIds`에 **같은 커밋에서**
   기입한다(v1.7.0 "re-registration post-push" 관례). policy는 v1.16.1로
   올라간다. **양쪽만 바뀌면 드리프트 도구가 RED로 판정한다.**
3. **ruleset PUT**(4번째 required context, integration_id 15368) →
   readback 일치 확인 → operator-adapter provenance로 manifest 기록.
4. **manifest 관계 검증** 통과(`tools/promotion/validate_manifest.sh`).
5. 두 번째 승격(closure-watcher freshness watchdog)으로 **SUSTAIN** 실증.
6. `docs/agents/task-process.md`에 GPA 포인터 추가, `data/promotions/` 산출
   디렉터리 확립.

## 참조

- [ADR-0025](0025-gateway-landing-authority.md) — 병합 권한 위임(P12).
- [ADR-0027](0027-queue-delegation.md) — merge queue 위임.
- [ADR-0032](0032-admission-venue-split.md) — 베뉴 분할(PR / merge_group).
- [ADR-0035](0035-admission-ssot.md) — required-check SSOT 정합, 3-leg 드리프트.
- [ADR-0022](0022-admission-artifact-authority.md) — TrustedWriterSet(승격 핀의 근거).
- `config/policy/merge_admission.json` — 정책 SSOT(v1.16.0).
- `.github/workflows/generation-acceptance.yml` — GPA v1 구현.
- `tools/promotion/validate_manifest.sh` — 승격 manifest 관계 검증.
