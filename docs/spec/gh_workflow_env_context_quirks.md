# gh_workflow_env_context_quirks — workflow 등록 시점 스키마 위반의 증상과 원인

> 기록 계약: AGENTS.md §0.5 Quirk Mandate. 실측: 2026-10-21 (feat/gpa-v1,
> PR #1024, GPA generation-acceptance.yml 등록 실패 사건).

## Q1 — `jobs.<job_id>.env`는 runner context를 허용하지 않는다

**사실**: workflow 스키마상 job-level `env:`의 허용 expression context는
`github`·`needs`·`strategy`·`matrix`·`vars`·`inputs` 등이며 **`runner`는
포함되지 않는다**(`jobs.<job_id>.environment.url`과 달리). job-level
env에 `${{ runner.* }}`를 쓰면 **워크플로 실행이 아니라 등록 자체가
실패한다** — 어떤 이벤트에서도 발화하지 않는다.

**실측 사례**: `RESULTS_DIR: ${{ runner.temp }}/gpa-results`를 job-level
env에 둔 generation-acceptance.yml — `pull_request`·`merge_group`
트리거가 선언돼 있었음에도 PR에 어떤 실행도 생성되지 않았고, 대신
브랜치 push마다 아래 Q2의 스텁 실행이 기록됐다.

**수정 패턴**: 경로가 step 어디서든 필요하면 첫 step이
`$GITHUB_ENV`로 내보낸다:

```yaml
- name: "[init] ..."
  run: |
    echo "RESULTS_DIR=$RUNNER_TEMP/<sub>" >> "$GITHUB_ENV"
    RESULTS_DIR="$RUNNER_TEMP/<sub>"
    mkdir -p "$RESULTS_DIR"
```

`$RUNNER_TEMP`는 셸 환경 변수로 모든 run step에서 사용 가능하다.
step-level `env:`에서는 runner context가 허용되므로 단일 step 용도면
그곳에 두어도 된다.

## Q2 — 등록 실패의 관측 가능한 증상: event=push 스텁 실행 + "workflow file issue"

**사실**: 등록 시점 스키마 위반은 **job이 없는 `push` 이벤트 실행**으로
나타난다 — `conclusion=failure`, "This run likely failed because of a
workflow file issue" 페이지, **로그 없음**(`--log-failed` → "log not
found", jobs API → 빈 목록). 브랜치 push마다 하나씩 기록된다.
선언된 트리거(`pull_request` 등)의 실행이 전혀 없는 것이 차동 신호다.

**실측**: Archright/Axiom runs 39665581936·39666127446·39668420147
(feat/gpa-v1, 2026-10-21) — 전부 event=push, 무로그 failure. Q1 수정
커밋 이후 pull_request 실행이 정상 생성됨으로 원인-증상 관계 확정.

**진단 절차** (관측 → 판정):
1. `gh run list --branch <b>` — 선언 트리거 실행 부재 + push 스텁 존재 확인
2. 스텁 실행 로그 시도 → 무로그면 등록 실패로 판정
3. 파일의 job-level env/기타 키별 허용 context 대조로 위반 지점 특정
4. 로컬 `yaml.safe_load`는 이 위반을 잡지 못한다 — 문법은 유효하기 때문.
   스키마 검증은 플랫폼만 수행한다.

## 교훈

"workflow 파일이 문법상 유효"와 "트리거에 등록됨"은 다른 판정이다.
로컬 yaml 검증을 통과해도 등록이 실패할 수 있으며, 그 실패는 스텁
실행으로만 관측된다 — 조용한 무발화(죽은 게이트)와 구분하는 유일한
신호가 Q2의 증상이다. required check로 등록된 workflow라면 이 상태는
"check 미보고 = fail-closed 큐 블록"으로 이어진다 (GPA 실패주입
acceptance 분리 (d)와 동일한 현상).
