# CI Epoch Record — ci-provider-router :357 jobs fetch 무보호 파이프라인 폴백 수리 + probe-merge-queue :220/:238 동일 클래스 보호 (2026-11-02)

- **절차 정본**: `docs/agents/ci_epoch_cutover.md`(AGENTS.md §2.5 — 규모 불문
  의무; required check의 workflow_run **제어기** 변경이므로 절차 적용).
  "라우터 fetch 보호 1줄" 판단으로 절차를 축약하지 않았다.
- **대상**: `.github/workflows/ci-provider-router.yml`(:357 fetch 블록 — 수리
  후 :357-:387) + `.github/workflows/probe-merge-queue.yml`(:220 artifacts
  목록 게이트, :255-:280 payload 다운로드 게이트) — surface
  **CONTROLLED**(기존 파일 수정이므로 정책 PR 불필요).
- **원자성**(절차 5단계): 워크플로 2개 파일 수리 + Q19 quirk
  (`docs/spec/ci_provider_failover_quirks.md`) + fixture 3종·capture
  manifest 갱신 + 검증 하니스 확장
  (`tools/ci/test_workflow_jq_contracts.sh`, PR #1169 하니스의 계약 확장) +
  본 기록이 하나의 세대 전환 단위로 단일 PR에 탑재된다.
- **병합 입장 조건**(실판정 2026-11-01·2026-11-02 동일): ruleset 20303214 —
  `required_approving_review_count: 0`, `require_code_owner_review: false`,
  merge queue MERGE/ALLGREEN(max build 2).
- **권한 고지**: push·PR·merge는 본 브랜치에서 수행하지 않는다 — 메인
  스레드가 수행하며, 아래 "착지 후 관측 계약"의 각주 기록도 메인 스레드의
  몫이다.

## 결함 (root cause — 2026-11-02 read-only 전수 감사 특성화)

- `ci-provider-router.yml:357`(수리 전 blob
  `20806d5713c72096fc2acbde5d174f34fd45da80`):
  `JOBS_ALL="$(gh api --paginate "repos/$REPO/actions/runs/$WR_ID/jobs?per_page=100" | jq -sc '[.[].jobs[]]')"`
  — 보호장치 전무(`2>/dev/null`·`|| true`·`if` 래핑 없음), `set -euo
  pipefail` 하에서 **전송 계층 실패 전부가 사망**: HTTP 404(존재하지 않는
  run) → jq exit 5 `Cannot iterate over null`; 403 rate-limit 에러 본문
  유입(Q18: gh api는 4xx 본문을 stdout에 출력) → 동일; gh api 실패 + 빈
  stdout → pipefail 사망. [measured 2026-11-02] `GET
  repos/Archright/Axiom/actions/runs/1/jobs?per_page=100` → stdout
  `{"message":"Not Found","documentation_url":"https://docs.github.com/rest/actions/workflow-jobs#list-jobs-for-a-workflow-run","status":"404"}`,
  stderr `gh: Not Found (HTTP 404)`, exit 1 (gh 2.102.0).
- **봉투 가정 자체는 정확**하다 — `{total_count, jobs[]}`는 실측·공식
  OpenAPI 정합이며 표현식은 변경하지 않았다(아래 수리 계약 5항).
- **사망 시 도달 불도달 집합**(판정 이전 데이터 취득 라인): (2-a) UNKNOWN
  해소, return-acceptance 판정·confirmed/inconclusive write,
  0-step 차단 전환, UNKNOWN 기록, rerun-failed-jobs — Q17 사고와 동일
  계열의 `return_acceptance` 침묵 정체를 **판정 이전** 위치에서 재현.
  상태 의미론 자체는 fail-closed 안전(:357 이전 변수 write 없음 →
  CI_RUNNER_MAP 무변화)이나, 관측은 `::error::` 없는 조용한 step failure다.
- **대비 — 동일 워크플로 내 확립 패턴**: :705(attempt-2 jobs fetch,
  `2>/dev/null … || true` → 실패 시 "job not found — inconclusive" →
  `ROUTING_OK=false` → UNKNOWN 기록 + exit 1), :949(canary jobs fetch,
  `if CJ_RAW="$(…)"` + 기본값 → inconclusive 경로). 같은 fetch가 판정 입력인
  두 위치에는 "실패=UNKNOWN 기록" 폴백이 설계돼 있고 :357만 누락.
  N_JOBS=0(빈 배열) 경로는 :393대(수리 후)에서 우아하게 처리 — 사망은
  fetch/jq 프로세스 실패 시만.
- **동일 클래스 (MINOR)**: `probe-merge-queue.yml` :220
  `BATCH="$(gh api … | jq -c '.artifacts')"` — 에러 본문이 `.artifacts`=null로
  **rc 0으로 통과**한 뒤 하류 URL-picker `.[]`에서 exit 5(무보호 중
  가장 조용한 변형; 하니스 음성 통제로 관측 고정), :238
  `gh api "$URL" > "payloads/$ART_ID.zip"` — 에러 JSON이 .zip에 착지 후
  unzip 모호 사망(Q18 클래스). 둘 다 probe-judge 잡
  (`if: github.event_name != 'merge_group'`) — 필수 경로·라우팅·변수와
  무관, **실패 방향은 현행 fail-closed(빨간 프로브) 유지**가 계약.

## 수리 계약 (6항목 — 감사 정의, 구현 위치는 수리 후 라인)

1. **fetch 실패의 의미 분리** — 판정 데이터가 아닌 별개 의미; 어떤 전환·
   acceptance 확정도 내리지 않음. `return_acceptance`는 현재값 보존
   (기존 `confirmed` 무효화 금지 — §2.6 "재실행은 identity를 불필요하게
   변동시키지 않는다"). 구현: router :381-:386(실패 귀결 블록 — 전환
   write 경로 도달 불가, 변수 접근 없음).
2. **기존 UNKNOWN 기록 의미론 재사용** — result=UNKNOWN + step summary +
   exit 1(:391/:544/:657 패턴과 동일 JSON 형태). 새 상태·새 변수 필드
   도입 없음(§2.6). 구현: router :382(::error::), :385(summary record
   `{router:{event,action:"none",result:"UNKNOWN",reason}}`), :386(exit 1).
3. **exit-code 성공 + 봉투 스키마 검증 후 수용** — `has("jobs")` +
   `has("message")` 오염 탐지(Q18 치료 계약). 구현: router :374(exit-code
   게이트 `JOBS_FETCH_RC`), :378(봉투 게이트
   `length > 0 and all(.[]; type=="object" and has("jobs") and
   (has("message") | not))`), 이유 라벨 `jobs_fetch_failed_rc_<n>` /
   `jobs_envelope_invalid`. probe :231/:232(동일 구조, `has("artifacts")`),
   :263-:280(다운로드 — exit-code 게이트 + PK 서명 + `unzip -t` 무결성,
   통과분만 `mv`로 수용).
4. **스트림 분리** — 판정값(stdout 캡처 변수)과 gh stderr 관측 로그(파일 →
   접두사 부착 후 `>&2`, `|| true`로 잡을 죽이지 않음)의 생명주기 분리
   (Q17 교훈). 구현: router :373(`JOBS_ERR_FILE=${RUNNER_TEMP:-/tmp}`)·
   :383(stderr 관측), probe :230/:234·:264-:266.
5. **endpoint·jq 표현식·재시도 계약 불변** — fetch endpoint 문자열과
   `[.[].jobs[]]` 표현식 미변경; happy path의 JOBS_ALL은 수리 전과
   **byte-identical**(하니스가 run 41298669695 fixture로 단언).
   구현: router :374(endpoint), :387(조립 — 표현식 불변).
6. **라우팅 판정·변수 write 구조 일절 불변** — `runs-on`, :374-:382대(수리
   후) PATCH 2회 재시도 + GET byte-compare, 상태 기계 전부 미변경.

## 세대 전환 10단계 (ci_epoch_cutover.md)

1. **Freeze** — pre-fix 정본 blob SHA(origin/main `ad8f67238` 기준):
   `ci-provider-router.yml` = `20806d5713c72096fc2acbde5d174f34fd45da80`,
   `probe-merge-queue.yml` =
   `3e69a9974bcc75c18dd68aeefef5f6f0b726c2de`.
   CI_RUNNER_MAP freeze 시점 상태([measured] GET 2026-11-02T00:25Z):
   `mode=ghec, state=GHEC_ACTIVE, generation=15,
   return_acceptance=confirmed, return_acceptance_run_id=41366115516,
   last_transition_at=2026-11-02T00:15:44Z,
   last_transition_reason=GHEC_RETURN_CONFIRMED, fallback_provider=ubicloud`
   (updated_at 2026-11-02T00:15:52Z).
2. **Record** — 본 PR HEAD(수리: router fetch 블록 :357-:387, probe
   :220-:237·:255-:280 + Q19 quirk + fixture/하니스 확장 + 본 기록; PR
   merge 시 기록). post-fix blob SHA(작업 트리, `git hash-object`):
   `ci-provider-router.yml` = `bade111632c28567ea28b7fc305265ed6c82d313`,
   `probe-merge-queue.yml` =
   `f9f24aceed8b16fdde5b939959885935f0a1750c`.
3. **Tombstone** — N/A: retirement 없음(무보호 파이프라인의 보호 래핑,
   endpoint·표현식·상태 전이·권한 의미론 유지).
4. **New Epoch** — 보호된 판정 입력 취득 v2: 취득 → exit-code 게이트 →
   봉투 스키마 게이트 → 조립의 3단 분리. 실패 귀결은 기존 UNKNOWN 기록
   의미론 단일 계약. probe 다운로드는 수용 전 PK 서명 + `unzip -t` 검증
   추가(수용 파일은 `payloads/*.zip.partial` → 검증 후 `mv`).
5. **Atomic Binding** — workflow 2개 + Q19 + fixture/manifest + 하니스 +
   본 기록 = 단일 PR·단일 merge.
6. **Local/Targeted Verification** — 아래 표, 관측 완료. 하니스는 수리 후
   라인에서 **추출한 라이브 블록을 샌드박스에서 실행**하며, 실패 주입은
   테스트 소유 gh shim(호출 로그로 "변수 write 0건"까지 단언), 주입 본문은
   커밋된 fixture다. 실행 중 하니스가 probe 봉투 게이트의 초안 결함(slurp
   배열에 `type=="object"`를 평가해 verbatim 봉투를 항상 거절)을 잡아
   수정했다 — 추출-실행 검증의 실효성 관측.
7. **Short Validation** — 라우터·probe 모두 dispatch가 아닌 이벤트
   트리거이므로 로컬 재현(fixture × 라이브 블록 실행)이 생산 전 검증의
   실질이다. 병합 후 첫 실제 발화가 운영 검증을 수행한다(9단계).
8. **Canonical Cutover** — 본 PR의 merge queue 통과 + native MERGE(main).
   required-check identity/trust 의미론 무변경(수리는 판정 이전 취득 경로의
   실패 의미 분리이며 라우팅·상태 전이 로직은 불변).
9. **Production Acceptance** — **착지 후 관측 계약(메인 스레드 수행)**:
   (a) 본 PR merge_group의 required run 완료 → 라우터 workflow_run 발화 →
   수리된 :357-:387 통과 → 기존 판정 경로로 복귀, (b) 발화 후 CI_RUNNER_MAP
   GET이 freeze 상태와 동일 의미론(mode=ghec, state=GHEC_ACTIVE,
   return_acceptance=confirmed 유지 — fetch 실패가 confirmed를 무효화하지
   않음)을 보존하는지 확인, (c) 관측 결과를 본 문서 말미 각주로 기록.
   라우터 발화에서 fetch 실패(404/403)가 실측되면 ::error:: 라인 +
   `reason:"jobs_fetch_failed_rc_*"`|`"jobs_envelope_invalid"` summary
   record + exit 1 + 변수 무변화가 수리의 운영 증거다.
10. **Rollback** — 단일 revert PR(router+probe 워크플로 2개 파일). rollback
    상태는 결함 상태(무보호 fetch = 조용한 step failure, 변수 무변화의
    fail-closed)로 복귀하며 안전하다. fixture·하니스·Q19·본 기록은 유지된다
    (음성 통제 5e/6/7이 수리 전 형태를 계속 고정).

## 로컬 검증 (2026-11-02 관측 완료)

| 검증 | 명령 | 관측 결과 |
|---|---|---|
| jq 데이터 계약(확장) | `make test-workflow-jq-contracts` | **PASS** — 추출 21 프로그램 + 3 라이브 블록; canary Q16 8/8, router Q17 골든 byte-exact 2 fixtures, Q19 봉투 게이트 4(수용/404/403/빈), router Q19 happy **byte-identical**(run 41298669695, 22 jobs) + 폴백 4 케이스(404 실측/403 조립/빈 stdout/오염 rc0 → 전부 exit 1 + UNKNOWN record + **변수 write 0건**), 수리 전 음성 통제 3(:357 exit 5×2, 빈 stdout rc 1) + probe :220 happy byte-identical + 게이트 3 + 음성 통제(BATCH=null rc0 → 하류 exit 5) + probe :238 수용 1/거절 3/음성 통제 1 |
| workflow shell 문법 | `make check-workflow-shell-syntax` | **PASS** — run blocks checked=230 failures=0 lane-guard violations=0 |
| parse-poison | `make test-workflow-poison-lint` | **PASS** — tokenized-max-overall=15289(<21000), sweep 0 violations over 25 workflows |
| lane-stderr 가드 | `make test-workflow-lane-guard` | **PASS** — fixture matrix 2/2, authenticity, sweep 0 violations |

## fixture 출처 (capture_manifest.json이 SSOT)

- `err404_jobs_run_not_found.json` — **verbatim 실측**(2026-11-02, gh
  2.102.0, `GET repos/Archright/Axiom/actions/runs/1/jobs?per_page=100` →
  HTTP 404; GET-only 1회).
- `err403_rate_limit_composed.json` — **공식 스키마 조립**(실제 rate limit
  유발은 금지되어 미캡처): 403/429 + `x-ratelimit-remaining: 0` 계약은
  Context7(/github/docs)
  `content/rest/using-the-rest-api/rate-limits-for-the-rest-api.md`·
  `troubleshooting-the-rest-api.md`(2026-11-02 인용); 본문 스키마
  `{message, documentation_url, status}`는 상기 실측 404 본문 + Q18의
  2026-11-01 incident 실측 본문(`{"message":"API rate limit exceeded…",
  "status":"403"}`)에 근거. IP는 RFC 5737 문서용 주소(192.0.2.10).
- `artifacts_envelope_page1_perpage1.json` — **verbatim 실측**(2026-11-02,
  `GET …/actions/artifacts?per_page=1`, 1 row, total_count=9864).
- 세션 rate limit 소비: 핵심 GET 4회(404·artifacts·rate_limit 확인 2회) +
  Q19 실측을 위한 한정 paginate 읽기(releases 1p, cli/cli tags 3p,
  run 41298669695 jobs 2p). 이전 시도한 artifacts 전수 paginate(197페이지
  예상)는 페이싱 위해를 피해 **중도 중단**(read-only, 2차 한도 미발화 —
  이후 모든 호출 성공으로 확인).

## gh 버전 고정 여부 (실측)

- 저장소 툴체인은 **Nim 2.2.10·Lean만 고정**하며 gh는 고정하지 않는다 —
  `config/`·`docs/agents/operations.md`에 gh 버전 핀 존재하지 않음(전수
  확인 2026-11-02). 러너 이미지(axiom-control)의 gh는 이미지 갱신에
  따라 float하며, 라우터 toolchain 게이트(:187-:194)는 존재만 검증하고
  버전을 관측 출력으로 남긴다.
- 로컬 실측 환경: `gh version 2.102.0 (2026-09-30)`. Q19의 페이지 결합
  실측·404 본문 실측은 모두 이 버전 기준 — **gh 버전 갱신 시 Q19 재검증이
  최우선**이다(release-ship.yml:151의 배열 병합 의존 포함; release-ship.yml
  자체는 본 수리에서 변경 없음).

## 실행 순서 (운영)

1. 본 PR 병합(merge queue — 현재 활성 공급자 GHEC에서 실행).
2. 본 PR merge_group의 required run 완료 → 라우터 workflow_run 발화(수리된
   취득 경로) → 기존 판정·write 경로로 복귀.
3. 메인 스레드가 9단계 관측 계약(라우터 발화 성공 + CI_RUNNER_MAP GET
   의미론 불변)을 수행하고 본 문서 말미 각주로 종결한다.

---

## 말미 각주 — Production Acceptance 관측 종결 (메인 스레드, 2026-11-02)

9단계 (a)–(c) 관측 결과:

- **(a) 라우터 발화·수리 경로 production 통과**: PR #1183 native MERGE
  `940ae0f7bd65cb9d387c1d26e5921399f90f6877`(2026-11-02T00:52:20Z, merge
  queue). merge_group 8개 런(admission-gate·axiom-operational-slice·
  bsec-integrity·debt-registry-gate·generation-acceptance·landing-integrity·
  observer-manifest-consistency·probe-merge-queue) 전부 success
  (group_head=940ae0f7bd). MERGE 후 head_sha=940ae0f7bd 귀속 런 89개
  전부 완료(미완료 0) — 이 중 **ci-provider-router 14회 발화 전부
  success**(수리된 :357–:387 취득 경로 통과, 기존 판정·write 경로 복귀).
  fetch 실패 ::error::/UNKNOWN 폴백은 관측되지 않았다(happy path — 실패
  경로의 운영 증거 계약은 하니스 Q19가 실측 fixture로 고정).
- **(b) CI_RUNNER_MAP GET 의미론 불변**: `mode=ghec`, `state=GHEC_ACTIVE`,
  `return_acceptance=confirmed`(하드닝 코드 경유 재확정 — run
  41369623705, `last_transition_at=2026-11-02T00:56:23Z`),
  `last_trial_result=success`, `generation=15`. confirmed가 보존·재기록됐다
  (단일 writer = 기존 Router, 수동 변경 0건).
- **(c) 본 각주로 종결**. L4 보조 관측: `landing_observe.sh --main
  940ae0f7bd…` → OBSERVED_SUCCESS(bound push run 41369468499, attempt 1,
  artifact gitHead=940ae0f7bd 귀속, verdict=PASS tier=dual-verified).

종결 선언: fetch-fallback hardening의 구현 → 로컬 검증 → PR → merge queue
native MERGE → canonical main 실행 → 운영 acceptance(라우터 발화 + 변수
의미론)가 전부 관측 증거로 확정됐다. Rollback(9단계 계약)은 발동하지
않았다.
