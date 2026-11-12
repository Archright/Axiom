# gh api --paginate Output-Shape + release-ship Freeze Idempotency Quirks (GitHub CLI REST paging / release freeze contract)

> AGENTS.md §0.5 Quirk Mandate — documented toolchain quirks live in
> `docs/spec/` (AGENTS.md 본문은 FROZEN — §-1; 본 문서가 그 전문이다).
>
> **Discovered**: 2026-11-02 (release-ship freeze 검사 멱등 계약 hardening —
> `work/release-ship-idempotency`; 인접 계약 ADR-0024
> `docs/adr/0024-release-boundary-authority.md`)
> **Class**: external tool behavior — `gh api --paginate`의 출력 형태가 gh
> 버전에 따라 달라지는 문제 + 그 위에 세워진 workflow jq 프로그램의 데이터
> 형태 계약. 인접 문서: `docs/spec/ci_provider_failover_quirks.md` Q16/Q17
> (동일 결함 계급 — "jq 데이터 형태 가정 오류는 bash -n 게이트를 통과한다"),
> `docs/spec/gh_merge_admission_observation_quirks.md` (org audit-log
> `--paginate --jq` 클라이언트 필터 선례).
>
> Tagging: **[measured]** = observed live on the cited command/tool version.
> **[derived]** = judgment derived from the cited observations and documented
> contracts. **[pending-U*]** = open measurement item.

---

## Q-P1 — `gh api --paginate`의 페이지 출력 형태는 gh 버전 의존이다: 단일 병합 배열(신형) 또는 문서 연결 스트림(구형) — 페이지 병합 단일 배열 가정은 jq 다중 문서 오염으로 이어진다 (release-ship freeze ⑥ 결함)

### Symptom

`release-ship.yml` freeze ⑥의 수정 전 프로그램:

```
n_same="$(printf '%s' "$RELEASES" | jq --arg v "$VERSION_NORM" '[.[] | select(.tag_name == $v)] | length')"
```

은 `gh api --paginate repos/…/releases`의 출력이 **항상 단일 JSON 배열 문서**라고
가정한다. gh가 페이지 본문들을 연결(concatenated documents)로 출력하는 빌드에서는
jq가 프로그램을 **문서별로** 평가한다 — `[.[] | select(…)] | length`가 문서마다 한
줄씩 출력되어 `n_same`이 다중 라인("0\n0")으로 오염되고, `[ "$n_same" = "0" ]`가
"too many arguments"로 실패 → `|| fail "⑥ … already exists"`가 발화한다. 결과는
**fail-closed가 아니라 fail-WRONG**이다: 존재하지 않는 release에 대한 거짓
already-exits FAIL로 정상 출하가 차단된다.

### Documented / measured basis

- **[measured 2026-11-02]** 로컬 gh **2.102.0 (2026-09-30)**:
  `gh api --paginate repos/Archright/Axiom/releases` — 단일 페이지(실측 0 release,
  verbatim `[]`)에서 출력은 **하나의 배열 문서**다 (`jq -s length` = 1 문서).
- **[derived]** 다중 페이지 연결 출력은 이 저장소에서 live-capture 불가다
  (release < 1페이지). gh CLI는 역사적으로 페이지 본문을 순차 출력해 왔으며
  페이지 병합 동작은 릴리스에 걸쳐 변경되었다. **정확한 버전 경계는 본 문서에서
  pin하지 않는다**(gh 버전 pin은 별도 판정 사항이며, 파서 수정과 동시 적용
  금지 원칙) — 따라서 계약은 형태 비의존으로 정의된다: 소비자는 두 형태 모두를
  수용해야 한다.
- **[derived]** 이 결함은 bash -n 셸 문법 게이트(
  `tools/ci/validate_workflow_shell.sh`)로 검출 불가다 — 셸 구문은 유효하고 jq가
  런타임에 데이터 형태에 따라 다르게 평가한다. Q16/Q17과 동일 결함 계급
  (`docs/spec/ci_provider_failover_quirks.md`: "shell syntax validation never
  inspects the DATA STRUCTURE jq consumes").

### 계약 — 형태 비의존 소비자 (release-ship freeze ⑥, 수정 후)

```
jq -s --arg v "$VERSION_NORM" 'if (map(select(type != "array")) | length) > 0
  then error("releases response: non-array document in gh --paginate output — fail-closed")
  else ([.[] | .[] | select(.tag_name == $v)] | length) end'
```

- `jq -s`가 전체 입력 문서를 slurp한다 — 단일 배열이든 문서 연결 스트림이든
  동일하게 문서 배열이 된다.
- 모든 문서가 배열이어야 한다 — 비-배열 문서(예: 에러 envelope)는 `error()`로
  jq exit 5 → `set -e` 하에서 스텝 실패 = **fail-closed**(거짓 진행 없음).
- flatten 후 `tag_name` 일치 개수를 센다 — 출력은 항상 단일 라인 숫자.
- 빈 입력(0바이트)도 안전 — slurp 누적이 비어 길이 0 (`[measured 2026-11-02]`
  로컬 jq-1.7: `printf '' | jq -s length` → `0`).
- 인접 문서(`[][[]]`, 개행 없는 연결)도 jq 스트림 파서로 동일 처리된다
  (`[measured 2026-11-02]`).
- ⑦ 열거(`jq -r '.[].tag_name'`)는 문서별 반복이라 연결 스트림에서도 이미
  안전하다 — 두 프로그램이 같은 `$RELEASES`를 소비한다.
- **[pending-U1]** 실제 다중 페이지 리포지토리에서 gh 빌드별 출력 형태 전수
  측정(버전 경계 확정) — 본 hardening은 그 측정과 무관하게 형태 비의존 계약으로
  닫혀 있다.

### Enforcement

`tools/ci/test_workflow_jq_contracts.sh` release-ship group(6a/6b/6c) — 라이브
YAML에서 프로그램 추출(anti-drift) × 커밋된 fixture
(`tests/fixtures/workflow_jq_contracts/release_ship/`, provenance:
`capture_manifest_release_ship.json`). 음성 통제: 수정 전 프로그램이 다중 문서
스트림에서 다중 라인 카운트를 출력함을 재검증 — fixture가 단일 문서로 위생화되면
FAIL. [measured 2026-11-02] 전 케이스 PASS.

### 판정 종결 — 형태 무관 수용으로 근본 해결, 버전 pin 불필요 (Q-P1 closure, 2026-11-02)

**판정**: gh 버전 pin은 **기각**한다. pin은 파라미터가 아니라 회피다 — 형태 drift
위험을 staleness와 설치 비용으로 치환할 뿐이다. 근본 해결은 소비 지점의 **형태
무관(form-agnostic) 정규화**다: 관측된 병합 단일 배열(①)과 공식 문서의 별개
문서 연결(②)을 **모두** 수용하고, 그 외 형태는 fail-closed 거부. 이는 "동일
입력(유효한 두 형태) → 동일 판정"을 보장하는 결정론적 계약이며, 대상 지점
(구 release-ship :151 → 현재 :182/:184)의 수리는 PR #1184로 이미 착지돼 있다.

**공식 출력 계약 (Context7 인용 — `/cli/cli`, `pkg/cmd/api/api.go` `gh api`
Long help, trunk, 2026-11-02 검색)**:

> "In `--paginate` mode, all pages of results will sequentially be requested
> until there are no more pages of results. **Each page is a separate JSON
> array or object.** Pass `--slurp` to wrap all pages of JSON arrays or
> objects into an outer JSON array."

- 별개 문서 연결(②)이 **문서화된 형태**다. 소비자 측 `jq -s` slurp는 공식
  `--slurp` 옵션과 동일한 정규화의 클라이언트 측 구현이다(`--jq`와 `--slurp`는
  상호 배타 — api.go — 따라 raw 스트림 수신자는 자체 slurp가 필요하다).
- 구현 계약(같은 소스): `--jq` 필터는 페이지 루프 안에서 **페이지별**
  responseBody에 적용된다(processResponse; 소스 TODO "reuse parsed query
  across pagination invocations"가 페이지별 평가를 확인). 따라서
  `--jq '.[] | …'` 열거 소비는 페이지 문서 경계에 면역이다.
- 병합 단일 배열(①)은 문서화되지 않은 실측 동작이다(gh 2.102.0; Q19 실측:
  `repos/cli/cli/tags` 210 tags/3페이지 → 문서 1개) — 위 계약 문구와
  불일치하며, 이 불일치가 pin 논쟁의 원인이었다. 소비자가 양 형태를 수용하면
  불일치는 무해해진다 — **pin 불필요의 근거**.

**전수 감사 (2026-11-02, origin/main 291cb2f08 기준, `.github/workflows` 내
`gh api --paginate` 전체)**:

| 사용처 | endpoint 형태 | 현재 처리 | 분류 |
|---|---|---|---|
| release-ship.yml :182/:184 (구 :151) | 최상위 배열 (releases) | ⑥ `jq -s` slurp + 전 문서 배열 검증 + flatten (PR #1184); ⑦ 문서별 열거 | **보호됨** — 본 판정의 대상 지점, 수리 이미 착지 |
| ci-provider-router.yml :374 | 봉투 객체 (jobs) | Q19 exit-code 게이트 + 봉투 스키마 게이트 (`all(.[]; type=="object" and has("jobs") and not has("message"))` — 문서 수 무관) | **보호됨** (PR #1183) |
| ci-provider-router.yml :735 | 봉투 객체 (attempts/2/jobs) | `jq -sc '[.[].jobs[]]'` slurp+flatten (문서 수 무관); 실패·빈값 → 기존 inconclusive 의미론 (거짓 증거 없음) | 이상 없음 |
| ci-provider-router.yml :920 | 봉투 객체 (workflow_runs) | `jq -rs` flatten; 실패·빈값 → `::error::` + UNKNOWN 기록 fail-closed | 이상 없음 |
| ci-provider-router.yml :979 | 봉투 객체 (jobs) | `jq -sc` flatten + if 가드; 실패 시 `[]` 유지 → `length > 0` 요구 판별식상 not-proven (보수) | 이상 없음 |
| generation-acceptance.yml :146 | 최상위 배열 (pulls files) | `--jq '.[].filename'` 페이지별 필터(위 구현 계약 — 형태 면역) + rc 게이트 reject + 로컬 diff 완전성 증인 2층 | 이상 없음 |

probe-merge-queue.yml :220/:238은 `--paginate` 미사용(Q19 게이트, 단일 응답) —
paginate 형태 범위 밖. `.github/` 밖 `tools/` 오프라인 증거 수집 스크립트
(`--slurp`: pr_latency_attribution, `--jq` 페이지별 필터: go_critical_parallel_
extraction/e4e5_collect/merge_latency_audit/golive_detect, rc 게이트 raw 취득:
closure_watcher_slot_ledger)는 merge-admission 판정 소비자가 아니므로 범위 밖
(이상 없음). **새 수리 대상(형태 가정 + 검증 부재) 지점: 0건** — 취약 유일
지점은 이미 수리돼 있다.

**Enforcement (추가)**: `tools/ci/test_workflow_jq_contracts.sh` **Q-P1 group
(section 8, strict append)** — ① 병합 단일 배열 fixture
(`rel_releases_merged_multipage_form.json` = `jq -s 'add'` 합성, provenance:
`capture_manifest_qp1_forms.json`)과 ② 공식 문서 형태(two-page fixtures)의
⑥/⑦ 출력이 **byte-identical**인 교차 형태 등가 골든 + 실측 캡처(`[]` → 0) +
음성 통제(비-배열 문서·절단 JSON → fail-closed; 구 프로그램의 병합 형태 의존
단일 라인 '1' 보존 통제). 기존 release-ship group(6a/6b/6c)과 Q19 group은
불변(순수 append). [measured 2026-11-02] 전 케이스 PASS.

**[pending-U1] 불변**: 버전 경계 전수 측정은 여전히 열려 있다. 단, 계약이 형태
비의존이라 어떤 경계에서도 판정이 흔들리지 않는다 — 측정은 정보 가치만 가진다.

---

## Q-P2 — release-ship freeze ⑤ 멱등 계약: tag 존재는 곧 FAIL이 아니다 — 판정표와 NO-OP 배선

### 배경

수정 전 ⑤는 `GET /git/ref/tags/{version}` rc==0를 무조건 FAIL로 처리했다. 이미
출하된 (version, SHA) 쌍의 재디스패치(예: publish 성공 후 관측 누락으로 재실행)는
영구히 실패하는 유일 경로였다 — 멱등성 결여는 실질적으로 "재디스패치 금지"를
뜻한다.

### 판정표 (계약 — [derived], 2026-11-02 hardening에서 도입; 전 케이스 계약 테스트 고정)

| 조건 | 판정 |
|---|---|
| 동일 tag + 동일 SHA (annotated면 `/git/tags/{oid}` peel 후 비교 — ⑦·publish peel 단언과 동일 논리; lightweight는 `.object.sha` 자체) | **NO-OP 성공** — `freeze_verdict=noop` + `frozen_sha` + `version_norm`을 `$GITHUB_OUTPUT`에 출력, 명시 로그 `FREEZE: ⑤ NO-OP — …`, ⑥⑦ 생략, freeze 정상 종료 |
| 동일 tag + 다른 SHA | **명시 FAIL** — `⑤ tag … exists at different SHA … != target … — 덮어쓰기 없음 (clobber 금지)` |
| tag 부재 (HTTP 404) | **진행** — 기존 경로 (⑥⑦ 실행) |
| 불명확 (rc≠0 ∧ HTTP≠404, 5xx/네트워크/미판별) | **fail-closed FAIL** — 기존 경로 |
| ⑥: `tag_name == version`인 release 존재 | **FAIL** (유지) — 불명확한 중복은 fail-closed |
| ⑦: 다른 기존 release tag가 target으로 peel | **FAIL** (유지) — 동일 SHA·다른 version STOP |
| **경계**: tag 존재 "그 자체"는 절대 성공이 아니다 | 다른 SHA면 NO-OP가 아니라 FAIL이다 (위 2행) |

NO-OP 시 ⑥⑦을 생략하는 이유: 동일 tag+동일 SHA가 확인되면 해당 (version, SHA)는
이미 출하된 상태다 — 이 시점의 release 목록 전수(⑥)는 불명확한 중복 판정(실패
유발)만 남는다. 유일성은 그대로 유지된다: **동일 SHA·다른 version은 ⑦이 STOP**,
**동일 version·다른 SHA는 ⑤가 FAIL**, publish 단계의 git ref 원자 충돌(422,
ADR-0024 2중 유일성 메커니즘 2)은 불변이다. ADR-0024와 모순 없음 — NO-OP은
(version, SHA) 쌍이 정확히 일치하는 재디스패치에만 적용된다.

### NO-OP 배선 (최소 — 단일 지점)

freeze가 `freeze_verdict` 출력(fresh|noop)을 내면, **verify-metadata 잡의 `if:`에
`needs.freeze.outputs.freeze_verdict != 'noop'` 절 하나**가 유일한 배선이다:
verify-metadata가 skip되면 GitHub needs-success 체인에 의해 full-l2 →
assert-l2-scope → verify-binary → publish가 **연쇄 skip**된다 — 재빌드·아티팩트
재업로드·중복 발행이 없다. validation_only 경로는 불변이다(freeze 미실행 → outputs
공백 → `'' != 'noop'` 참). 새 잡·새 시스템 추가 없음.

### 경계 주의 (의도된 동작)

NO-OP은 "tag가 target과 동일 commit을 가리킨다"는 관측만으로 "이미 출하 완료"를
판정한다. tag만 존재하고 release 객체가 없는 상태(수동 tag push 등)에서는 NO-OP가
출하를 대체하지 않는다 — 이 상태는 release-ship 밖의 정합성 문제이며, ADR-0024의
v* tag 생성 권위 모델(App-only)에서 수동 tag push 자체가 폐기된 경로다
(`docs/adr/0024-release-boundary-authority.md`).

### Enforcement

`tools/ci/test_workflow_jq_contracts.sh` release-ship group(6a/6b/6c) — 라이브 freeze 스텝 스크립트를
release-ship.yml에서 추출해 mock `gh`(PATH 주입, 응답 본문 = 커밋된 fixture)로
실행한다. NO-OP·다른 SHA FAIL·부재 진행·불명확 fail-closed·NO-OP 시 ⑥⑦ 생략까지
전 케이스 고정. [measured 2026-11-02] 전 케이스 PASS.
