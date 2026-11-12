# GitHub Actions Run Observation Quirks

> §0.5b Quirk Documentation Mandate 기록 (2026-10-08 실측 — Axiom CI 메모 재앵커
> 슬라이스 측정 활동에서 발견; Q5·Q6는 2026-10-09 merge 큐 교착 해소 서사에서 추가,
> Q8은 2026-10-13 org ruleset required-workflow 런의 `gh run view` 404 실측에서 추가,
> Q9·Q10은 2026-10-13 Stage 2 cutover 실행 기록(재arm 사이클·org 게이트 merge_group
> 런)에서 추가).
> 검증 도구가 GitHub 실행 계층을 관측·판정할 때 재발견되는 플랫폼·CLI 특이사항.

## Q1 — `workflow_run.head_sha`는 PR head이지 실행 주제가 아니다

`pull_request` 트리거 런에서 `github.event.workflow_run.head_sha` (= run object의
`head_sha`)는 **PR head H**다. 그러나 그 런의 lane이 실제로 빌드·체크아웃하는
주제는 **합성 병합 커밋 M**(`target_sha` = merge ref 팁, manifest `build_sha`)이다.

- behind(stale) PR에서 `tree(H) != tree(M)` — base 기여분이 merge 결과에 포함되기 때문.
- 실측(2026-10-08): run `37755662845` head_sha `8ae68ca81`(=H) vs lane 빌드 주제
  tree `7a49353e…`(=M) — 상이. run `37743598870` head `7dac5debb`(=H) vs `0de7eb78…`(=M) — 상이.

**함정**: `tree(manifest build_sha) == tree(run.head_sha)` 같은 "트리 등식"은
**PR staleness 프록시**이지 정체성 검사가 아니다 — behind PR에서 정직한 실행까지
거부한다(R10 ahead-invariant의 근본 원인). 실행 주제 정체성 결속은
`head_sha ∈ parents(build_sha)`(합성 병합의 parent) 형태로 해야 한다 —
ADR-0025 Amendment D의 executed-subject anchor.

## Q2 — merge-queue speculative stacking: 그룹의 base ≠ main

merge queue는 후속 항목을 **앞선 항목의 그룹 커밋 위에** speculative하게 쌓는다:
`G_n = merge(G_{n-1}, H_n)`. 대기 중인 다른 큐 항목이 있으면 `G^1 ≠ main` —

- 실측(2026-10-08): PR #603의 merge ref = `merge(aeb0dcaaa, 8ae68ca81)`(tree
  `7a49353e…`)인데 그룹 커밋 `ab7b7270f` = `merge(1ba6c359e, 8ae68ca81)`(tree
  `85616c53…`) — `1ba6c359e`는 앞선 항목 #602의 speculative 그룹 커밋.
- **함정**: PR-페이즈 lane 메모(tree(merge(main, H)))가 mg-페이즈(tree(G))에서
  소비되려면 **단일 큐 항목 + 게이트 창 동안 base 불변**이 필요하다. stacking 시
  두 identity는 본질적으로 다르다(class A — 정당한 재계산, 중복 아님).

## Q3 — `gh api …/actions/jobs/{id}/logs`의 ANSI escape 거부

CI 런 로그는 raw ANSI SGR 시퀀스를 포함한다. `gh`는 이를 파일/파이프로 출력하려면
**거부**한다: `the response contains terminal escape sequences; pass
--allow-escape-sequences to output it anyway`. `gh run view --log`는 출력하되
`^[[36;1m` 계열 이스케이프가 그대로 혼입된다.

```bash
gh api --allow-escape-sequences ".../actions/jobs/<id>/logs" 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E "AXIOM_CACHE|Cache hit"
```

파일로 저장할 때는 `--allow-escape-sequences` 필수 — 미지정 시 **빈 파일 + 실패**가
남아 로그 부재를 도구 오류로 오인하기 쉽다.

## Q4 — `run:` 블록의 `\${{` 는 이스케이프가 아니다: 표현식 보간이 셸보다 먼저 일어난다

(2026-10-09 실측 — venue split preflight prepare leg, run `37883196224` job `113667745181`)

GitHub Actions는 `run:` 블록의 텍스트를 **셸에 전달하기 전에** `${{ }}` 표현식을
보간한다. 백슬래시는 이 보간을 막지 못한다:

```yaml
run: grep -q "subject-certificate-\${{ inputs.runAttempt }}" "$WF"   # 의도: 문자열 리터럴
# 셸이 받는 실제 명령: grep -q "subject-certificate-\1" "$WF"
# → GNU grep "부적절한 후방 참조" (exit 2) — 어떤 파일 내용과도 매칭 불가
```

운영 영향: 패턴이 붕괴한 grep은 **무조건 실패**한다 — fail-closed 스텝이면 모든
PR의 해당 leg가 red로 닫히고(본 사례: mint-prepare preflight leg), 실행 본문은
핀에 고정돼 있어 **fix가 자기 자신을 게이트할 수 없는 Gate A 교착**이 성립한다.

해결(문자 `${{` 를 패턴에 담을 때): 보간 토큰 `${{` 자체를 텍스트에 만들지 않는
이스케이프를 사용한다 — `grep -qE 'subject-certificate-\$\{\{[[:space:]]*inputs\.runAttempt'`
(`\$`, `\{` 는 셸 단일 인용 + grep -E에서 각각 문자 `$`, `{` 로 복원되고, 원문에는
연속된 `${{` 토큰이 없어 보간 대상이 되지 않는다). 대안: `$` + `{{` 문자열 결합.

**주석 포함 블록 전체가 보간 대상이다**: 위 토큰을 `run:` 블록의 **주석**에 예시로
적기만 해도 동일하게 보간이 시도되어 **워크플로 파싱 실패(0-job dispatch failure)**가
난다(2026-10-09 실측 — 본 Q4 문서화 커밋의 주석이 원인, required workflow가
dispatch 단계에서 jobs 0개로 실패). 주석에도 토큰을 쓰지 말고 서술어로 대체한다.

**재발 (2026-10-12 실측 — 실행 블록 본문 신규 토큰)**: PR #780(merge `3d64a7afa`,
blob `e9fbebb21`)이 admission-check.yml verdict leg의 `run:` 본문에 신규 보간 토큰
`CD_TESTED="${{ github.sha }}"`를 추가하자, org 핀 회전(09:42:56Z, `21c450c05`) 후
첫 배치(10:38:01Z run `38237548129`)부터 **모든 merge_group 배치가 0-job
(`total_count: 0`, conclusion=failure, check-run 미생성)으로 dispatch 실패**했다.
독립 서명: GitHub 워크플로 레지스트리가 certificate-mint·runner-pool-acceptance는
`name:` 키로 등록하는 반면, 파싱이 깨진 admission-check는 **name이 파일 경로로
fallback**됐다(Actions API `GET /actions/workflows`). PyYAML·actionlint 모두 통과하므로
로컬 정적 검증으로는 탐지 불가능하다 — 이 파일에서 run 본문 신규 `${{ }}` 토큰은
ADR-0033 §E no-new-tokens 계약대로 **항상 스텝 `env:` 매핑으로 운반**한다.

**정체 확정 (2026-10-13 실측 — 파스 독 정본 오라클)**: 위 0-job 교착의 잔여 독은
"토큰의 존재" 자체가 아니라 **보간 토큰을 보유한 `run:` 스칼라에 적용되는
21,000자 표현식 길이 한도**다 — 단일 `${{ }}` 토큰의 길이가 아니다.

- **적용 조건은 토큰 보유 여부**: 토큰이 하나라도 있으면 스칼라 전체가
  표현식으로 취급되어 21,000자 상한을 받는다. 토큰 없는 스칼라는 일반
  문자열로 취급되어 상한에서 면제된다 — **26,282자 토큰 0건 스칼라 PASS** vs
  **25,954자 토큰 보유 스칼라 FAIL**(동일 오라클 실측; 세대별 admission-predicate
  스칼라는 22fe84 19,340자+토큰 PASS / 4acfc682 25,766자 FAIL / ec54a744
  25,955자 FAIL). 길이가 아니라 토큰 보유가 적용 조건이다.
- **에러 서명**: `(Line: N, Col: 14): Exceeded max expression length 21000` —
  GitHub 파서가 호출 그래프 계획 단계에서 HTTP 422로 거부하며 **run 자체가
  생성되지 않는다(0-job, 체크런 미생성)**. 워크플로 레지스트리 `name:`이
  파일 경로로 fallback되는 위의 독립 서명과 함께 관측된다.
- **판정 근거(정본 오라클)**: org 리포 `parse-probe` 워크플로 dispatch 판정 —
  control PASS run `38272241691` / 후보2(토큰 0건) PASS run `38273175092` /
  후보1·대조군은 422 거부(run 미생성). 오라클 구성과 4군 실측 전문은
  [docs/evidence/admission_parse_poison_oracle_2026-10-13.md] 참조.
- **우회 원칙(확정)**: run 본문의 모든 이벤트 소득 값을 스텝 `env:` 매핑으로
  운반해 **run 본문 보간 토큰을 0건으로 유지**한다(ADR-0033 §E env-carry
  패턴). env 매핑의 토큰은 run 스칼라 한도와 무관하다. 0-job 실패 run은
  rerun 불가(HTTP 403)이므로 재판정에는 새 이벤트가 필요하다.
- **로컬 정적 룰 (2026-10-14)**: `tools/ci/validate_workflow_shell.sh`에 파스
  독 룰 추가 — 토큰 보유 `run:` 스칼라(블록·플레인 불문) 길이 **> 21,000** →
  FAIL(파일/잡/스텝/측정 길이 출력; 기존 bash -n 레그 불변, zero-dep 유지,
  YAML 파스 오류 fail-closed 유지). **잔여 불명(residual unknown)**: 스칼라
  길이가 정확히 21,000일 때 플랫폼이 수용/거부 어느 쪽인지는 로컬 판정 불가 —
  룰은 플랫폼 에러 문구("Exceeded max expression length 21000")를 좇아
  `> 21000`으로 구현했다. 21,000/21,001 경계 확정의 유일 인접 오라클은 org
  `parse-probe` dispatch다. 셀프테스트(5-피처 판정 행렬 + false-positive
  sweep): `make test-workflow-poison-lint`. PR-venue 배선 설계(이 세대 구현
  금지 — §2.5 epoch cutover 별도 세대):
  docs/design/workflow_parse_poison_lint_wiring_design_2026-10-14.md

## Q5 — `gh run rerun`은 원 attempt의 이벤트 SHA/ref로 체인 정의를 재생한다 — 리포 이후의 핀 회전은 반영되지 않는다

(2026-10-09 실측 — merge 큐 교착 해소 서사, PR #624 run `37872835631`)

공식 문서(docs.github.com, *Re-running workflows and jobs*): 재실행은 **원 이벤트의
`GITHUB_SHA`·`GITHUB_REF`를 그대로 사용**한다. 재사용 워크플로(`uses:`) 참조는
전체 재실행 시 "지정된 참조의" 워크플로를 쓰지만, 그 참조(SHA 핀 포함)는 **원
이벤트 시점에 선택된 워크플로 파일 버전 안에 박혀 있다** — 즉 rerun은 원 attempt
시점의 체인 정의 전체(callee 핀 회전 포함)를 재생하며, 그 사이 착지한 체인 수정을
소비하지 못한다.

실측 attempts(REST `GET /actions/runs/{id}/attempts/{n}`, 3회 모두 동일 head):

| attempt | 생성 (UTC) | 종료 | head | 결과 |
|---|---|---|---|---|
| 1 | 02:04:41 | 02:17:50 | `e7992fa87` | failure |
| 2 | 03:17:36 | 03:17:37 | `e7992fa87` | startup_failure (jobs 0개) |
| 3 | 03:18:14 | 03:34:28 | `e7992fa87` | failure |

이 창(02:04→03:34)을 포함해 그날 오전에 체인 세대는 양쪽에서 연속 이동했다 —
main 착지 `#621/#625/#631`(venue-split #625로 B가 `cbb8c0db`→`faae54125` 전진)와
org 핀 로테이션(armed 세대 `6767884e7`, Archright/.github#78/#79/#80 02:03–02:04Z)
및 그 롤백(Archright/.github#92 → `cbb8c0db`; issue #632 서사, PR #624 감사 코멘트
issuecomment 2026-10-09T04:34:59Z 참조). 그러나 attempt 2·3 rerun은 head 고정
때문에 수정 세대를 소비하지 못했다. 녹색은 **신규 트리거**에서만 나왔다: 빈 커밋
`e1a2a89b` push → run `37884478517`(attempt 1, 04:33:59Z SUCCESS).

선례(동일 의미론, 2026-10-06): `docs/evidence/evidence_cas_rearm_observation_2026-10-06.md`
— "`gh run rerun` re-uses the original refs … the only sound re-admission path was a
fresh synchronize run: an empty retrigger commit". 큐 컨텍스트 보충:
`docs/evidence/merge_admission_observation_blindspot_incident_2026-10-06.md` —
merge_group 런의 rerun은 죽은 `gh-readonly-queue` 브랜치 위 재실행일 뿐
재-enqueue가 아니다(`docs/agents/merge_admission_observation.md` 부록 3항의 재진입
경로 참조).

**판정 규칙**: 체인 수정(org 핀 회전·롤백, callee 본문 수정)의 반영을 검증하는 데
`gh run rerun`은 **무효**다. 유효한 경로는 identity-changing 신규 트리거뿐이다 —
빈 커밋 push(synchronize), close/reopen, `gh pr merge --auto` 재진입(Q6). rerun의
녹색·적색은 어느 쪽이든 세대 판정의 근거가 아니다.

## Q6 — merge-queue 재진입 자가치유: 뜨거운 main 아래 각출→재진입이 반복되며 통과가 지연된다

(2026-10-09 실측 — 세대 전이 창, `docs/evidence/jcas_phase1_observation_run_index.md`
§4–§7; 공식 문서: *Merging a pull request with a merge queue*)

공식 문서(docs.github.com, *Merging a pull request with a merge queue*): 큐 검사
실패·병합 요건 상실 시 PR은 큐에서 **제거**된다(제거 사유 목록: merge group CI
실패, CI 결과 타임아웃, 사용자 제거, 보호 규칙 실패). 재추가는 사용자 행위 또는
`gh pr merge`(auto-merge)뿐이다. `gh run rerun`은 재추가가 아니다(Q5 +
`merge_admission_observation.md` 부록).

이것이 뜨거운 main 아래에서 **루프**로 조립된다 — Q2의 speculative stacking이
각 재진입마다 새 그룹을 만들기 때문:

1. merge_group 실패(세대 결함·Q4/Q4a 파싱 실패·identity fail-closed) → GitHub가
   PR을 큐에서 제거(실측 2026-10-06: `github-merge-queue[bot]` dequeue, 단
   `mergeStateStatus`는 `CLEAN` 유지 — blindspot 문서의 마스킹 서명).
2. 재진입(`gh pr merge --auto` 또는 close/reopen) → **현재 팁 위의 새 speculative
   그룹**(Q2). 그런데 PR-venue 재검증 identity는 분기 시점 base에 동결돼 있다 —
   base가 이미 전진했으면 fail-closed 정상 판정으로 또 적색(run `37881146122`:
   `ADM_IDENTITY: FAIL — PR base.sha faae54125 != B cbb8c0db (base moved during
   admission?)`; run A⁻ `37878074796`: reopen은 base.sha를 갱신하지 않음 —
   synchronize로만 전진).
3. base가 계속 전진하는 동안(`cbb8c0db`→`faae54125`→`f68049cd9`→`f29444027`→
   `bf6c72058`, 04:22–05:34Z 5회 연속 착지) 각 항목은 1→2를 반복하고, 통과는
   세대가 고정되는 정적 창에서야 나온다(#629 `bb7f2639e`, #633 `7769bb8db`).

**함정**: 이 반복은 실패 누적이 아니라 **지연 신호**다. 각 재진입은
identity-changing progress이므로 WAIT의 정당한 근거지만(`merge_admission_observation.md`
WAIT 행), 루프를 끊는 행위는 재시도(rerun)가 아니라 (a) 체인 수정 착지 + (b) 그
세대 위의 신규 트리거다(Q5). 관측 도구는 재진입 횟수를 실패 판정 근거로 쓰지 말고,
`mergeQueueEntry` 상태 전이와 그룹 커밋 identity만 기록한다.

## Q7 — `workflow_dispatch` boolean input은 `github.event.inputs`에서 문자열이다: `== true` 비교는 항상 거짓

(2026-10-11 실측 — closure-watcher drift-test dispatch, run `38130258653`)

`on.workflow_dispatch.inputs.<name>`을 `type: boolean`으로 선언하면 UI는 체크박스를
주지만, 이벤트 페이로드의 `github.event.inputs.<name>`은 **문자열** `"true"`/`"false"`로
들어온다. GitHub 표현식의 `==`는 타입 간 강제가 없으므로:

```yaml
env:
  # "true" == true → 항상 false — 스위치가 조용히 발화하지 않는다
  MODE: ${{ github.event_name == 'workflow_dispatch' && github.event.inputs.drift_test == true }}
  # 옳은 형태 1: 형식화 inputs 컨텍스트(진짜 boolean — workflow_dispatch·workflow_call에서 유효)
  MODE: ${{ github.event_name == 'workflow_dispatch' && inputs.drift_test == true }}
  # 옳은 형태 2: 문자열과 비교
  MODE: ${{ github.event.inputs.drift_test == 'true' }}
```

운영 영향: 조건부 시험 스위치(fixture 주입·카나리 모드)가 **발화를 생략하고 정상
경로를 조용히 녹색으로 통과**시킨다 — "시험이 녹색"과 "시험이 아예 안 돌았음"이
런 결론만으로 구별되지 않는 극장 형태의 오판을 낳는다(§0.9). 실측에서도
drift-test dispatch가 fixture를 건너뛰고 실측 대조(녹색)로 끝났고, 적색이어야 할
시험이 녹색인 역설로 발견됐다.

**판정 규칙**: 형식화 비교가 필요한 곳에서는 `inputs` 컨텍스트를 쓰거나 문자열과
비교한다. 그리고 시험 스위치에는 **역방향 계약**(예: "drift-test dispatch의 정상
완료는 적색 런이다 — 녹색이면 스위치 실패")을 문서화해 조용한 녹색을 시험 실패로
취급하게 만든다(closure-watcher.yml 헤더 전례).

## Q8 — org ruleset required-workflow 런: `gh run view <id>`는 workflow_id 후속 조회 404로 전체 실패한다 — 판정은 REST 폴백으로

(2026-10-12 복구 관측 phase S4에서 재조우, 2026-10-13 전수 실측 확정 — gh 2.102.0 (2026-09-30)).
동일 class의 최초 등록은 `docs/spec/gh_org_required_workflow_run_quirks.md`다(2026-09-30
기록, 2026-10-08 merge_group 재검증 — 본 Q8은 그 위에 놓이는 재측정이며 상호 대체가 아니다).

`gh run view <run-id>`는 런 자체를 REST로 성공적으로 가져온 뒤 run 객체의
`workflow_id`로 `GET /repos/{owner}/{repo}/actions/workflows/{workflow_id}`를
**무조건 후속 호출**하고, 그 응답이 404면 **런이 존재함에도 전체 명령을 실패로
끝낸다** — 에러는 REST 경로임을 직접 드러낸다:

```
gh run view 38292865993 --repo Archright/Axiom --json databaseId,status 2>&1
# failed to get run: HTTP 404: Not Found (https://api.github.com/repos/Archright/Axiom/actions/workflows/367727531)
gh api repos/Archright/Axiom/actions/runs/38292865993 --jq '.id,.status,.event' 2>&1
# 38292865993 / completed / merge_group   ← 동일 런을 REST는 정상 반환
```

트리거 조건은 **event 유형이 아니라 workflow_id의 관측 repo 내 비가시성**이다.
Archright org ruleset 2개(`axiom-admission-gate` 24233738, `landing-integrity`
23943917 — `rules[].type: workflows`, 소스 `Archright/.github`(repo_id 1182157951)의
`admission-gate.yml`·`landing-integrity.yml` @ `main`)이 required workflow를 강제하면,
그 파생 런의 workflow_id(실측 `367727531`, `366145793`)는 강제 대상 repo(Axiom)와
소스 repo(.github의 admission-gate는 `367694978` — **별개 ID**) 어디의
`GET /actions/workflows` 목록에도 노출되지 않는다. 2026-10-13 전수 실측(총 29런):

| 런 (Axiom) | workflow | event | `gh run view` |
|---|---|---|---|
| 38292865993·38290933145·38289641939·38279215308 (success), 38286110903·38288401507 (failure) | admission-gate | merge_group | **404** (`workflows/367727531`) |
| 38292865524·38290932614 (success) | landing-integrity | merge_group | **404** (`workflows/366145793`) |
| 38292865555·38290932632 probe-merge-queue, 38292865560·38290932637 bsec-integrity, 38292865435·38290932640·38289641517 observer-manifest-consistency | (Axiom 로컬) | merge_group | 정상 |
| 38294496562·38292706293·38290766590 | trusted-writer-set | push | 정상 |
| .github 16런 — 38272241691·38273175092 parse-probe dispatch, 38258089021 push, 38284601172·38282600278·38274458410·38272739065 등 pull_request, 38273156725 push | (.github 로컬) | 혼합 | 전부 정상 |

merge_group에서 최초 관측됐지만 동일 merge_group의 로컬 workflow 런은 정상 —
conclusion(success/failure)과도 무관하다. `gh run view --job <jobid>`도 run resolve
후 동일 workflow 조회에서 실패하고(실측 job `114956867011`), workflow 스코프 목록
(`gh run list --workflow 367727531`)은 `HTTP 404: workflow 367727531 not found on
the default branch`로 실패한다. 반면 전역 `gh run list`는 정상이며 해당 런의
workflow 칼럼만 빈칸으로 나온다(아래 근인 — 목록 경로의 404 흡수).

근본 원인(gh 2.102.0 `pkg/cmd/run/shared/shared.go` 코드 확인): `GetRun`은 run을
REST로 가져온 뒤 `GetWorkflow(workflow_id)`를 후속 호출하고 그 에러를 그대로
반환한다. 목록 경로(`GetRuns` → `preloadWorkflowNames`)는 동일 404를 "likely a
organization or enterprise ruleset workflow"로 간주해 workflowName을 빈칸 처리한다
(소스 주석 명시). 즉 upstream에서는 목록 쪽만 수정됐다(cli/cli#10660 merged;
#10686은 duplicate로 닫힘) — `run view`는 cli/cli#9228(open)로 **여전히 미수정**이며
최신 릴리스 2.102.0에서 재현된다. GitHub 플랫폼 측: required-workflows 레거시 API는
2024-01부터 deprecated 응답("creating required workflows is only available with
repository rulesets")을 돌리고 ruleset 파라미터는 소스 path+ref만 담는다.
**UNKNOWN**: run의 workflow_id가 규칙 상 어떤 내부 레코드인지, 그 404가 권한 거부의
변형인지 레코드 미노출인지는 공개 API로 구별 불가하다(admin:org 토큰에서도 404 —
gh 소스 주석은 전자에 기운다). 어느 쪽이든 아래 판정 규칙은 동일하다.

우회(실측 검증): 런 조회·판정은 REST를 직접 쓴다.

```bash
gh api "repos/{owner}/{repo}/actions/runs/{id}" --jq '{id,status,conclusion,event,name}'
gh api "repos/{owner}/{repo}/actions/runs/{id}/jobs" --jq '.jobs[] | {id,name,conclusion}'
```

**판정 규칙**: `gh run view`의 실패 메시지 URL이 `/actions/workflows/{id}` 404면
그것은 **런 부재가 아니라 org ruleset required-workflow 런의 서명**이다 — 관측
도구는 이를 런 미존재로 판정하지 말고 REST
`gh api repos/{o}/{r}/actions/runs/{id}`로 런 존재·상태·결론을 재확정한 뒤 판정한다.
런 존재 판정의 권위는 REST 응답이고, `gh run view`의 404는 판정 근거가 아니다.
merge_group 큐 페이즈의 권위 관측 경로는 자매 문서의 어댑터
(`tools/ci/landing_observe.sh` — GraphQL `mergeQueueEntry` + REST 이벤트 필터)를
따른다(`gh pr checks`는 PR head에만 결속되어 큐 페이즈를 관측하지 못한다).

## Q9 — PR auto-merge 필드는 liveness 신호가 아니다 — live 큐 entry에서도 계속 null로 판독된다

(2026-10-13 실측 — PR #805 재arm 사이클, Stage 2 cutover 실행 기록)

GraphQL `autoMergeRequest`와 REST `auto_merge`는 **auto-merge가 활성인 동안에도
null로 판독될 수 있다**. PR #805에서 재arm된 큐 entry의 전 수명(관측 개시
07:18Z → 병합 07:58:53Z 후) 동안 **모든 관측 시점에서 null**이었는데, 같은
구간에 auto-merge 활성 이벤트는 존재한다 — `auto_merge_enabled`가
06:40:16Z(최초 arm)와 07:17:05Z(재arm)에 기록됐고, entry는 live로
merge_group 실행·병합까지 진행했다.

**함정**: "auto-merge가 살아있는가"의 관측을 `autoMergeRequest != null`로
구성하면 살아있는 entry를 죽은 것으로 오판한다. dequeue→auto-merge 소멸
전제조건(`docs/agents/merge_admission_observation.md` 부록 (b))을 이 필드에
결속시키면 guard는 항상 참이 되어 아무것도 증명하지 못한다.

**판정 규칙**: 큐 liveness·큐 부재 판정의 권위 신호는 GraphQL
`mergeQueueEntry` / `isInMergeQueue`(L2-R 권위-per-fact 표)와 merge_group
run 발견(부록 (a) 어댑터)다. `autoMergeRequest`/`auto_merge`는 상태의
증거로 쓰지 않는다.

## Q10 — needs 롤업의 전이적 skip 전파: 조건부 skip이 기본 조건 job까지 끌어내린다

(2026-10-13 실측 — org 게이트 Stage 2 수용 merge_group 런; 수정 =
Archright/.github PR #197)

merge_group 런에서 **PR 전용 job**(`anchor-resolve` — pull_request 이벤트
전용 조건)이 skip되면, 그 skip이 needs 롤업을 타고 **전이 전파**된다.
실측 서명: `anchor-resolve` skip → `closure-deriver`는 **success로
완료**(명시 조건) → 그러나 유일한 기본 조건 job `gateway`
(needs=[closure-deriver], 명시 `if` 없음)가 **skip**됐다 — closure-deriver의
성공에도 불구하고다. 기본 조건(암묵 `success()`)의 판정이 직접 needs의
conclusion만으로 계산되지 않고 전이 needs의 skip을 롤업한다는 것이 본
실측의 요지다.

**결과**: gateway 산출물의 downstream artifact 소비자(`mint-publish`)가
입력 부재로 **fail closed** — Stage 2 첫 수용 시도가 이 서명으로 실패했다
(run 38359095521, MINT_PUB_TREE; 수정 전 동일 서명 6회 연속 실패).

**수정 패턴**: 형제 중 조건부 skip 가능 job이 하나라도 있으면 기본 조건
job에 명시 조건을 단다 — `if: !cancelled() && needs.<dep>.result ==
'success'`. 수정 후(org PR #197) 4회 연속 success: 38362314715 ·
38362315846 · 38363875338 · 38364154110.

**판정 규칙**: merge_group에서 PR 전용 job의 skip은 정상이지만, skip의
롤업 범위는 워크플로 저자의 책임이다 — 조건부 skip 가능 job을 needs로
참조하는 모든 기본 조건 job은 명시 `if`를 요구하며, "job skip"과 그
산출물 소비자의 fail closed를 다른 판정으로 구별해 기록한다.

## Q11 — check-runs 목록 응답의 `annotations_url`은 null이다: 단일 객체 GET에서만 채워진다

**증상**: `GET /repos/{owner}/{repo}/commits/{sha}/check-runs`의 각 check-run
객체는 `annotations_url`이 항상 `null`로 반환된다. 같은 객체를
`GET /repos/{owner}/{repo}/check-runs/{id}`로 단독 조회하면 값이 채워진다.

**측정**(2026-10-14, merge-queue-rearm 분류기 fixture 작업 중):
`commits/a7e47334…/check-runs` 목록에서 `verdict / admission-check`
(id 115393671740)의 `annotations_url` = `null`, 직접 조회 및 표준 URL
`repos/Archright/Axiom/check-runs/115393671740/annotations` 호출은 정상
응답(3 annotations). 동일 현상이 5개 후보 커밋(9fc37cc8·23a958c0·a7e47334·
4aba37de·8dcb1e9e)의 24건 목록 응답 전부에서 재현.

**판정 규칙**: 목록 응답에서 annotation을 읽어야 할 때는 check-run 객체의
`id`로 표준 URL `repos/{owner}/{repo}/check-runs/{id}/annotations`를
구성한다. `null`을 "annotation 없음"으로 해석하지 않는다 — 그 해석은
분류기(ADR-0027 Amendment D)에서 UNKNOWN 오판정을 낸다. provenance는
객체 동일성(id·name·ref)으로 유지된다.

## Q12 — `dequeued` 활동은 이탈 사유를 운반하지 않는다: 수동 dequeue에서도 발화하며 분류(condition 6)가 유일한 판별자다

**증상**: `pull_request_target: [dequeued]` 트리거는 queued PR이 큐에서
빠지기만 하면 발화한다. 이벤트 페이로드에는 "게이트 실패 자동 제거"와
"운영자 수동 제거"를 구별하는 사유 필드가 없다 — dequeue 사유는 API로
관측 불가한 문서화된 플랫폼 한계다(ADR-0027 Amendment D 구현 관례 2).
따라서 GraphQL `dequeuePullRequest`에 의한 수동 제거도
merge-queue-rearm 워크플로를 깨운다.

**판별**(merge-queue-rearm 설계 — 2026-10-14 음성 제어 캐너리 검증):
발화 자체는 재arm 근거가 아니며, 분류 스텝이 판별자다. 수동 제거
시나리오에서 최신 merge_group 런은 (a) green으로 완료 → "green MG +
manual dequeue = intentional removal"로 skip되거나, (b) 취소·미완료 →
conclusion 부재로 "UNKNOWN — fail closed" skip된다. 어느 쪽도
allowlist annotation 없이는 재arm되지 않는다. `no-auto-rearm` 라벨은
수동 의도의 조기 차단 표식일 뿐, 분류의 대체가 아니다.

**판정 규칙**: dequeued 발화는 조사 개시 조건이지 재arm 승인이 아니다.
재arm 여부는 verdict / admission-check check-run의 annotation
allowlist 분류로만 결정하며, 수동 제거 가능성을 이유로 로그
스크래핑·부가 신호를 도입하지 않는다.

## Q13 — `gh pr merge --auto`는 이미 MERGED인 PR에서 exit 0으로 단락(short-circuit)한다: 성공 분기는 REARMED 선언 전에 PR state를 재검증해야 한다

**증상**: `gh pr merge <N> --auto …`는 대상 PR이 이미 MERGED 상태여도
오류를 내지 않고 exit 0으로 반환한다(단락 회로). arm 명령의 exit code만으로는
"재arm이 실제로 일어났는가"를 판정할 수 없다 — 이미 머지된 PR에서도 성공
(REARMED) 분기가 실행된다. 그 성공 분기가 분류 문맥 변수(REARM_G·
REARM_CLASS)를 기본값 없이 참조하면 `set -u` 환경에서 unbound variable으로
충돌한다.

**측정**(2026-10-14, Stage 3-A 검증): 이미 머지된 PR에 대한 arm 시도가
exit 0으로 단락되어 성공 분기에 진입, `REARM_G: unbound variable` 충돌로
런이 실패하는 것이 runs `38441478070`·`38441389675`·`38437138807`·
`38437686785`·`38443907599`에서 관측되었다 (verbatim:
`/home/runner/work/_temp/<id>.sh: line 3: REARM_G: unbound variable` →
`Process completed with exit code 1.`).

**판정 규칙**: arm 명령 직전에 PR state를 재조회하고(`gh pr view <N> --json
state`) OPEN이 아니면 "SKIPPED: PR state changed before arm"으로 fail-safe
no-arm한다. REARMED 선언은 state 재검증 통과 이후에만 도달할 수 있으며,
분기 문맥 변수는 모두 `${VAR:-}` 기본 참조로 쓴다. exit 0을 "arm 성공"의
증거로 취급하지 않는다.

## Q14 — `pull-requests: write` GITHUB_TOKEN도 `enablePullRequestAutoMerge`는 거부된다: 재arm의 유일한 변형 행위는 권한 결정 전까지 불활성이다

**증상**: merge-queue-rearm 워크플로의 GITHUB_TOKEN(`permissions:
pull-requests: write`)으로 `gh pr merge <N> --auto …`를 발행하면 GitHub이
auto-merge 활성화를 거부한다 — verbatim 오류:
`GraphQL: Resource not accessible by integration (enablePullRequestAutoMerge)`.
이 저장소에서 auto-merge 활성화는 GITHUB_TOKEN 권한 세트로 수행 불가능하다.

**측정**(2026-10-14, Stage 3-A 검증): runs `38440666593`·`38441126650`에서
동일 거부가 재현되었다. 발행은 워크플로의 설계된 fail-safe 오류 분기
("SKIPPED: arm command failed — verbatim error below (fail-safe no-arm, no
escalation)")로 귀결되며 어떤 변형도 일어나지 않는다.

**판정 규칙**: 재arm의 유일한 변형 행위는 현재 불활성(inert)이다 — 모든
긍정 조건을 통과해도 SKIPPED(fail-safe no-arm)로 끝난다. 이는 ADR-0027
Amendment D의 경계(자동 자격 증명 승격 없음)에 따른 것으로, arm
authority(PAT·GitHub App 전환 등)에 대한 운영자 결정이 내려지기 전까지
워크플로 측에서 권한을 넓히지 않는다. 오류 분기의 verbatim 전파와
no-escalation 원칙은 변경하지 않는다.

## Q15 — `persist-credentials: false` 체크아웃은 `origin` fetch에 인증 헤더가 없다: git은 "could not read Username"로 죽는다

**증상**: `actions/checkout`으로 후보 트리(`_candidate/`)를
`persist-credentials: false`로 프로비저닝하면 그 저장소의 로컬 config에는
`http.https://github.com/.extraheader`가 존재하지 않는다. 그 저장소에서
`git fetch origin <sha>`를 실행하면 git은 인증 정보를 찾지 못하고
프롬프트를 시도한 뒤, runner의 비대화형 환경에서 다음 오류로 죽는다:
`fatal: could not read Username for 'https://github.com': No such device or address`.
체크아웃 단계는 성공하지만(자격 증명이 필요 없으므로) 그 저장소에서 나가는
첫 `origin` fetch가 실패한다 — 즉 "체크아웃은 되는데 fetch가 안 된다"는
분리된 실패 클래스다.

**측정**(2026-10-21): Axiom run `39429432875`, job `118650919196`, step
`[check] Re-derive admission identity (B/H/treeOID — fail-closed)` — 커밋
`793c5af7e9b9bc933b5bb1aa405f0e5c7a552578` 부터 새 PR/merge-group 전부가 이
단계에서 `ADM_IDENTITY`로 실패했다(레인 미실행). 원인 = 해당 단계의
`git -C "$GITHUB_WORKSPACE/_candidate" fetch … origin` 5곳(merge-SHA,
subject-head, base-B, subject, `--deepen=64` history deepen)이 자격 증명 없이
`origin`을 향했다. 워크스페이스 루트의 B 체크아웃은 기본값
(`persist-credentials: true`)이라 config에 `extraheader`가 남아 있으므로,
**같은 워크스페이스 안의 다른 체크아웃**은 영향받지 않는다 — 실패는 후보
저장소로 국한된다.

**판정 규칙**: 후보 체크아웃의 `persist-credentials: false`는 후보 저장소의
자격 증명 부재를 보장하는 불변식이므로 유지한다(완화 금지). 인증은 B
워크스페이스 체크아웃의 config에 남은 `http.https://github.com/.extraheader`를
**일회성(ephemeral) `-c` 설정**으로 주입해 운반한다:
`git -C "$repo" -c "http.https://github.com/.extraheader=$hdr" fetch …`.
`$hdr`는 `git config --get`으로 읽기만 하고 — (1) 후보 저장소의 config에
기록하지 않고, (2) stdout/stderr로 출력하지 않고, (3) `-c` 로 해당 fetch
프로세스에만 적용된다. 헤더가 비어 있으면(인증 헤더 없는 체크아웃) plain
fetch로 진행하여 기존과 동일한 실패 모드를 유지한다 — fail-closed는 그대로다.

## Q16 — `GET /actions/runs?event=merge_group` 목록은 실존 런을 누락할 수 있다: 전수 판정은 창 분할 스윕 + 경계 런의 단일 GET 교차검증으로

**증상**: 목록 엔드포인트의 `event=merge_group` 필터는 전 페이지 순회
(`gh api --paginate`, per_page=100)에서도 실존하는 merge_group 런을 반환하지
않을 수 있다. `created` 쿼리 파라미터에 전체 타임스탬프를 전달해도 목록
경계가 요청값과 불일치한다 — 요청 컷오프 `>2026-10-21T16:40:44Z`의 실제
절단점은 ~21:02Z에서 관측됐다(16:55~20:39Z 런 4건이 전 페이지에서 부재).

**문서화된 상한(공식 문서 확인, 2026-11-01) — 과거 누락의 원인 확정이 아니다**: GitHub REST 문서 — "List workflow
runs for a repository"
(https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository)는
**"This endpoint will return up to 1,000 results for each search when using
the following parameters: actor, branch, check_suite_id, created, event,
head_sha, status."** — `event`와 `created`가 모두 포함된다. 상한 초과 시
초과 page는 오류가 아니라 `{"total_count":0,"workflow_runs":[]}` **빈
응답**으로 끝나므로 `gh --paginate`는 이를 완결로 오판하고 조용히 멈춘다.
관측된 사실은 여전히 "목록 부재 ≠ 런 부재"며, 10-31의 경계 4런 누락은 이
상한(필터 적용 후 작동)으로 설명 가능한 정합 서명이다. 다만 당시 목록
응답이 보존되지 않아 그 누락의 실제 원인이 이 상한이었는지는 확정되지
않았으며, 미확정으로 기록한다.

**측정**(2026-10-31): v5 판정 CAS 재사용 측정 창 폐쇄 스윕 — 런
`39639158902`(PR #1021)·`39657167861`(#1022)·`39661104154`(#1023)·
`39672117787`(#1024)이 목록 응답에 0회 관측. 단일 런 GET
(`GET /repos/{owner}/{repo}/actions/runs/{id}`)은 4건 전부
`name=admission-gate, event=merge_group, conclusion=success`를 반환했다.

**재현·회피(2026-11-01 직접 실측)**:

- `event=merge_group&per_page=100` `--paginate`는 정확히 **1,000건** 수집 후
  종료한다(page 11이 `total_count:0` 빈 응답; 빈 page의 total_count는 1
  page의 것과도 불일치 — silent truncation 서명).
- 상한은 **필터 뒤에** 적용된다: `created=>2026-10-21T00:00:00Z` 필터에서
  `total_count` 1280 vs `--paginate` 실수집 1000.
- **회피 절차(reproducer)**: (1) `created` 타임스탬프 창으로 분할해 **각
  질의 `total_count < 1000`**이 되도록 한다(`= 1000`이면 상한 포화 가능성이
  남아 추가 결과가 있을 수 있다 — 창을 더 세분화한다) — 실측:
  `created=2026-10-21T00:00:00Z..2026-10-25T00:00:00Z` → `total_count` 704,
  전 건 회수. (2) 창 간 결과를 **run id로 중복 제거**해 합산한다. (3)
  누락이 의심되는 런(경계 런 등 개별 ID를 아는 런)은 **단일 런 GET으로
  개별 검증**한다 — 실측: 위 창 분할 스윕에서 경계 4런 전부 재관측됐다.
- `--paginate`의 정상 종료를 **전수 완결(completeness)의 근거로 쓰지
  않는다** — 상한 하에서는 정상 종료가 조용한 절단을 숨긴다.

**함정**: 목록 스윕을 "전수 관측"의 근거로 단독 사용하면 목록 누락이 관측
누락으로 전파된다 — 모집단·P95·착지 판정이 조용히 줄어든다. 측정
사전등록의 재현 명령이 목록 형태이므로 재현자도 같은 함정에 빠진다.

**판정 규칙**: 관측 창 경계·전수성 주장은 (a) **total_count < 1000 창으로
분할한 목록 스윕 + run id 중복 제거** + (b) 경계·누락 의심 런의 단일 GET
교차검증으로만 확정한다. 런 ID를 이미 알고 있다면 단일 GET이
권위다. `--paginate` 완결·단일 질의 `total_count` 단독은 전수성의 근거가
아니다. 기록: `docs/evidence/judgment_key_v5_adjudication_2026-10-31.md`
§8·§12·`data/ci_optimization/judgment_key_v5_adjudication_2026-10-31.json`
(`observationWindow.scope`·`boundaryCandidates`·`reproduction`).

## Q17 — jobs-API `labels`는 문자열 배열이다: 관측 jq가 `.name`으로 인덱싱하면 판정 전에 exit 5로 사망한다 (정본 등록: 자매 문서 Q16)

(참조 전용 등록 2026-11-02 — 이 결함 class의 측정·문서 근거·수리의 단일 SSOT는
[ci_provider_failover_quirks.md](ci_provider_failover_quirks.md) **Q16**(canary M6
labels 게이트 결함)이 운반한다. 본 항목은 런 관측 경로에서의 발견 가능성을 위한
포인터이며 내용을 복제하지 않는다.)

**증상**: 런 관측 판정이 jobs API
(`GET /repos/{owner}/{repo}/actions/runs/{id}/jobs` — Q8의 REST 폴백 판정
명령과 동일 엔드포인트)의 `labels`를 `{name}` 객체 배열로 기대하는 순간, 이
엔드포인트의 `labels`는 문서상 `array of string`이므로
`jq: error … Cannot index string with string "name"` → exit 5로 사망한다.
사망이 판정 산출 이전에 일어나므로 실패 job은 conclusion=failure만 남는 진단
불가 실패가 된다(의미론은 자매 문서 Q16).

**판정 규칙**: jobs 기반 런 관측 jq에서 `labels`는 문자열 배열로 취급한다.
exit 5(`Cannot index string with "name"`)는 판정 결과가 아니라 관측 코드의
결함 서명이다. canary 실측(run 41261811139 / job 124716440849)·수정식
(`[.labels[]? | (.name? // .)]`)·수리(PR #1160, 2026-11-01)의 전문은 자매
문서 Q16이 단일 SSOT로 담는다.

## Q18 — jobs-API 공식 문서의 응답 예시 스키마는 `created_at`을 누락한다: 실측 응답에는 존재한다 (2026-11-03, unknown_closure F-1 등록)

**증상**: `GET /repos/{owner}/{repo}/actions/runs/{id}/jobs`의 공식 REST 문서
(docs.github.com/en/rest/actions/workflow-jobs) 응답 예시에는 잡 필드로
`created_at`이 실려 있지 않다. 문서 스키마만 믿고 "러닝 잡의 생성 시각은 관측
불가"라고 판정하면, 실제 API 응답에는 `created_at`이 존재하므로 관측 설계를
불필요하게 포기하게 된다.

**실측(2026-11-03, census 코호트 jobs 재조회 120런 · 실행 잡 340)**: 전 읡 응답에
`created_at` 존재 — `created→started` 갭 med 3s [2,39] 측정 가능. 재조회 무결성
(census 정본 대비 missing 0·extra 0·started_at 불일치 0)로 필드 신뢰성 확정.

**판정 규칙**: jobs 관측은 실측 응답 스키마를 정본으로 삼고, 문서 예시 스키마는
보증 목록으로 취급하지 않는다 — 문서에 없는 필드가 응답에 없다고 결정하기 전에
반드시 실측 응답 1건을 뜯어본다(Q8의 "문서 예시 ≠ 응답 전체" 원칙의 잡 필드판).
단 `created→started` 갭의 내부 분해(동시성 큐 대기 vs 러너 배정·VM 프로비저닝)는
여전히 API 미노출 — 갭 측정 가능이 성분 분해 가능을 의미하지 않는다.

## Q19 — check-runs 목록의 per_page 미지정 호출은 서버 기본 30건으로 조용히 절단한다: 200 성공 응답이 완결이 아니다 (2026-11-03, l3_go_prereg Track 1 F-4 등록)

**증상**: `GET /repos/{owner}/{repo}/commits/{ref}/check-runs`(및
`GET /repos/{owner}/{repo}/check-suites/{id}/check-runs`)를 `per_page` 없이 호출하면
서버 기본 30건이 적용된다. `total_count`가 30을 넘는 커밋에서 **응답은 200 성공이지만
목록이 절단**되며 오류·경고 표시가 없다 — `check_runs` 배열만 소비하는 관측·판정 코드는
나머지를 조용히 누락하고, required check 완료 판정을 절단된 첫 페이지로 오판할 수 있다.
Q16(목록 1,000건 상한)·Q11(check-runs 응답 필드)과 같은 "성공 응답 ≠ 완결" 계열이지만,
본 항목은 `--paginate` 미사용 **단일 호출의 기본 페이지 크기** 문제다.

**공식 문서 근거(DOCUMENTED, 2026-11-04 검증)**:
- REST check-runs 레퍼런스(두 엔드포인트 동일) — `per_page (integer) — The number of
  results per page (max 100). Default: 30`
  (https://docs.github.com/en/rest/checks/runs).
- REST 페이지네이션 가이드 — "For most endpoints, the maximum value of `per_page` is
  100. If you specify a value greater than the maximum, GitHub does not return an
  error. Instead, the value is automatically reduced to the maximum… you may receive
  fewer results than you expect without any indication" · 완결 판정은 Link 헤더 종주로
  (https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api).
  "기본 30"의 보편 문장은 없으며 엔드포인트별 레퍼런스에 개별 문서화된다.
- Actions 목록 3종(`actions/runs`·`actions/runs/{id}/jobs`·`actions/workflows/{id}/runs`)도
  동일 "max 100. Default: 30" + 필터 파라미터 사용 시 1,000건 상한(= Q16)
  (https://docs.github.com/en/rest/actions/workflow-runs ·
  https://docs.github.com/en/rest/actions/workflow-jobs).
- `gh api`는 `per_page`를 주입하지 않고 서버 기본값을 통과한다(gh 2.102.0 실측: 무지정
  호출 30건 반환). `--paginate`는 Link 헤더 순회로 전 페이지를 수집한다
  (https://cli.github.com/manual/gh_api — 매뉴얼은 `--paginate`만 문서화, 미주입·서버
  기본값 통과는 OBSERVED).

**실측**(2026-11-03, PR #1250 head `8c74275e4a0508ff2ebbc1988debb9637eb80532`
RequiredChecksGreenAt 산출 중): `commits/8c74275e4…/check-runs`(per_page 무지정) →
`total_count: 36`, `check_runs` 배열 30건 — 6건이 첫 페이지에 부재. `?per_page=100`
재질의로 36건 전수 회수 후 required 5-context 최댓값(2026-11-03T13:28:48Z)을 확정했다.
관측 계약(prereg §10:181)은 `per_page=100`을 이미 명시했으나, 무지정 호출의 기본값
절단을 관측·등록한다 — 계약 회피와 quirk 문서화는 별개다(Q18 "문서 예시 ≠ 실측 응답"의
정직 기록 톤과 동일 구조).

**판정 규칙**: 관측·판정 도구의 모든 REST 목록 조회는 (1) `per_page=100` 명시,
(2) Link 헤더/`gh api --paginate` 종주(다음 페이지가 없을 때까지), (3) **완결 판정은
응답 성공이 아니라 `total_count`와 수집 건수의 대조**로 한다 — `total_count` > 수집
건수면 절단으로 판정(fail closed). Actions runs류 필터 질의는 Q16의 1,000건 상한 창
분할을 병행한다. GraphQL은 connection마다 `first`/`last`(1–100) 명시가 **의무**이며
미지정은 기본값이 아니라 `MISSING_PAGINATION_BOUNDARIES` 오류다
(https://docs.github.com/en/graphql/guides/using-pagination-in-the-graphql-api —
GraphQL check-runs 경로는 `Commit.checkRuns`가 아니라 `Commit.checkSuites →
CheckSuite.checkRuns`다: `Commit.checkRuns` 필드는 현행 스키마에 없음). check-runs
목록의 결과 정렬은 공식 문서에 보증이 없으므로(NOT_DOCUMENTED) 순서 가정 없이
`id`·`completed_at` 값으로 판정한다. 커밋된 도구 선례:
`tools/merge_ruleset_drift_monitor.nim:755`는 이미 `check-runs?per_page=100` +
total_count 불완전 감지(:654)를 구현한다.
