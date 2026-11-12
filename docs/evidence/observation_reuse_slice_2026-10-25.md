# 관측 재사용 슬라이스 — L4 canonical-main 수용 리더의 상태 계약과 호출 예산 (2026-10-25)

> **종류**: 구현·관측 기록 (implementation + observation record).
> **권위**: 본 문서는 기록이다. 병합·착지 판정의 권위는 GitHub ruleset·필수 검사·merge queue이고, 실행 결과의 권위는 해당 실행(run id + attempt)이다. 본 문서와 그 도구는 **어댑터**이며 어떤 판정도 대체하지 않는다(AGENTS.md §2.3, Authority ≠ Adapter).
> **수치 표기 규약**: §4의 모든 값은 명령으로 재도출할 수 있다(§6). 재도출하지 못한 값은 넣지 않았다.

---

## 1. 주장 (Claim)

1. **canonical main의 수용 증거를 "다시 계산하지 않고 읽는" 경로가 존재한다.** `tools/ci/landing_observe.sh --main <sha>`는 push 이벤트의 기존 워크플로 런을 찾아 그 런의 기존 아티팩트(`axiom-operational-slice-evidence`)를 읽고, 매니페스트 digest와 대상 커밋 결속을 검증한 뒤 판정을 낸다. **새 워크플로·새 매니페스트 스키마·새 서비스는 추가하지 않았다** — 워크플로는 이미 push마다 이 아티팩트를 올리고 있고, 이 도구는 그것을 소비할 뿐이다.
2. **상태마다 종료 코드가 정확히 하나다**(§3.4). 기존 L1/L2/L3 코드 0/1/2/3의 의미는 바뀌지 않았고, 4=STALE·5=NOT_RUN이 추가되었다. 하나의 코드가 두 의미를 갖는 상태(2=PENDING ∧ 2=입력오류 같은 충돌)는 존재하지 않는다.
3. **관측 불가는 성공으로 승격되지 않는다.** 아티팩트 없음·만료·digest 불일치·대상 커밋 불일치·쿼리 실패는 각각 UNKNOWN/STALE로 끝나며 exit 0을 반환하지 않는다. 이 성질은 12개 픽스처 케이스로 고정했고, 그 테스트는 `make test-unit` **및** 필수 검사 워크플로(`axiom-operational-slice`)에서 실행된다.
4. **호출 예산이 실측으로 고정되었다**: 콜드 3회 + 아카이브 전송 1회, 웜 캐시 2회, `--offline` 0회(§4.2). 이전 계획의 "0~2회" 목표는 실제 엔드포인트 구성과 맞지 않았고, 실측에 맞춰 정정했다.

## 2. 범위와 방법 (Scope & Method)

- **범위**: (a) L4 리더의 상태 계약·결속 검증·캐시 키, (b) 그 계약을 고정하는 오프라인 테스트와 CI 배선, (c) 실측 호출 예산.
- **범위 밖**: 판정 의미(무엇이 올바른 수용인가)의 변경, 워크플로 판정 로직, closure 파생 캐시, 다른 저장소·다른 명령의 비용.
- **방법**: 실제 GitHub 리소스를 REST로 1회씩 관측하고, 상태 전이는 stub `gh` + 픽스처 아티팩트로 네트워크 없이 재현했다. 저장소 트리는 읽기 전용이며, 도구는 어떤 GitHub 쓰기 경로도 갖지 않는다.

## 3. 계약 (Contracts)

### 3.1 세 실행은 같은 SHA가 아니다 (P0-1)

PR head 실행, merge_group 실행, canonical main push 실행은 **서로 다른 실행**이다. merge_group의 SHA는 합성 merge commit이고, main push의 SHA는 랜딩된 merge commit이다. 따라서 L4의 정체성은 "SHA가 같다"가 아니라 **결속된 실행 식별자**다:

- 주체(subject) = `--main <sha>`로 받은 main 커밋
- 실행(execution) = `(run_id, run_attempt, event=push, workflow=axiom-operational-slice.yml)`
- 증거(artifact) = `(artifact_id, name)`

판정은 이 셋의 **결속**으로만 성립한다: 런의 `head_sha` == 주체, 아티팩트의 `run_id` == 실행, 매니페스트의 `sourceTree.gitHead` == 주체. 하나라도 어긋나면 STALE이다.

### 3.2 매니페스트는 오염시키지 않는다

`axiom.run-manifest.v1`은 타임스탬프·런 id·경로를 의도적으로 배제한다(`tools/ci/run_manifest.jq:20-21` — "they are not identity"). 그래서 실행 메타데이터는 매니페스트에 넣지 않고, **아티팩트 밖 관측 봉투**(`axiom.observation.v1`, 캐시 디렉터리의 `meta.json`)에 둔다. 매니페스트는 있는 그대로 읽는다.

### 3.3 캐시 키는 세 식별자다 (P0-3)

```
.cache/obs/<run_id>/<run_attempt>/<artifact_id>/
```

`run_id`만으로는 재실행(attempt)을 구분하지 못하고, `run_attempt`가 빠지면 서로 다른 시도의 증거가 섞인다. 완료된 런의 아티팩트는 불변이므로 두 번째 읽기는 다운로드 호출 0회다. 다만 **`--offline`은 최신성 주장이 아니다** — 캐시만 읽고 그 사실을 출력에 명시한다. 캐시가 변조되었거나 다른 커밋에 결속되어 있으면 STALE이다.

### 3.4 종료 코드 — 상태당 하나 (P0-4)

| 코드 | 상태 | 의미 |
|---|---|---|
| 0 | `OBSERVED_SUCCESS` | 결속된 push 런이 success ∧ 아티팩트가 주체에 결속 ∧ digest 일치 |
| 1 | `OBSERVED_FAILURE` | 결속된 push 런의 conclusion ≠ success |
| 2 | `UNKNOWN` | 입력 계약 위반 · 쿼리 실패 · 아티팩트 부재 · 불완전 목록 (fail-closed) |
| 3 | `PENDING` | 결속된 push 런이 아직 completed 아님 |
| 4 | `STALE` | 만료된 아티팩트 · digest 불일치 · 다른 커밋에 결속 · 변조된 캐시 |
| 5 | `NOT_RUN` | 해당 커밋에 push 런이 존재하지 않음 — **NOT_RUN은 성공이 아니다** |

0/1/2/3은 L1/L2/L3 경로의 기존 의미이며 변경되지 않았다(`landing_observe.sh:55-56`).

### 3.5 검색 범위는 워크플로다 (P1)

저장소 전체 런 목록에서 SHA로 고르면 같은 커밋의 다른 워크플로를 집을 수 있다. L4는 **워크플로 스코프 엔드포인트**로만 조회한다:

```
/repos/{owner}/{repo}/actions/workflows/axiom-operational-slice.yml/runs?head_sha=<sha>&event=push
```

## 4. 관측 (Observation)

### 4.1 실네트워크 L4 — canonical main `4a036781c7cade891157077d3202b6f6fb7a7284`

| 지표 | 값 | 출처 |
|---|---|---|
| 판정 | `OBSERVED_SUCCESS` (exit 0) | `tools/ci/landing_observe.sh --main 4a036781… --stats` |
| 결속된 런 | `run_id=40142705334`, `attempt=1`, `event=push`, `conclusion=success` | 같은 출력 `[RUN]` 행 |
| 런의 head_sha | `4a036781c7cade891157077d3202b6f6fb7a7284` (= 주체) | 같은 출력 |
| 아티팩트 | `id=12579741286`, `name=axiom-operational-slice-evidence`, `expired=false` | 같은 출력 `[ARTIFACT]` 행 |
| 매니페스트 결속 | `sourceTree.gitHead = 4a036781…`, digest 일치 | 같은 출력 `[MANIFEST]` 행 + `verify_manifest_dir` |
| 매니페스트 판정 | `verdict=PASS`, `certificate.verificationTier=dual-verified` | 같은 출력 `[MANIFEST]` 행 |
| 바이너리 | `binary.sha256=1605522f02ae50b3994f3eb8504ad26747e98b350bd85ef90543748e3cc568a3` | 같은 출력 |
| 엔진 빌드 | `engineBuild=unmeasured` | 같은 출력 — 이 트리에서 측정되지 않음(아래 §5.4) |

### 4.2 실측 호출 예산 (같은 주체·같은 캐시)

| 경로 | API 호출 | 아카이브 전송 | 관측된 `API_CALLS` |
|---|---|---|---|
| 콜드(캐시 없음) | 3 (런 조회 · 아티팩트 목록 · zip 해석) | 1 (302 이후 바이트) | `3` |
| 웜(캐시 적중) | 2 (런 조회 · 아티팩트 목록) | 0 | `2` |
| `--offline` | 0 | 0 | `0` |

출처: `--stats`가 stderr로 출력하는 값을 그대로 읽었다. 카운터는 **파일**에 기록한다 — 각 호출이 `$( … )` 서브셸에서 실행되므로 셸 변수 증가는 부모로 돌아오지 않는다(초기 구현이 `API_CALLS: 1`을 보고한 실제 결함이었고, 이 방식으로 고쳤다).

### 4.3 계약 고정 테스트 (네트워크 0)

`tests/ci/test_landing_observe_acceptance.nim` — 12 케이스 전부 통과(`nim c -r`, 실측 출력):

```
[OK] NOT_RUN (exit 5) when no push run exists for the commit
[OK] PENDING (exit 3) while the bound push run is still running
[OK] OBSERVED_FAILURE (exit 1) when the bound push run failed
[OK] STALE (exit 4) when the artifact has expired
[OK] UNKNOWN (exit 2) when the run carries no such artifact
[OK] STALE (exit 4) when the manifest is bound to a different commit
[OK] OBSERVED_SUCCESS (exit 0) on a cold cache, 3 API calls
[OK] warm cache reuses the immutable artifact, 2 API calls
[OK] --offline reuses the cache with 0 API calls, never a freshness claim
[OK] --offline without a cached observation is UNKNOWN, never success
[OK] a malformed sha fails closed
[OK] --main and a PR number are mutually exclusive
```

픽스처는 stub `gh`(PATH 선두) + 실제 업로드 형태의 zip(매니페스트 + 선언 digest)이다. 실 GitHub 상태·실 런에 의존하지 않으므로 만료·재실행에도 흔들리지 않는다.

### 4.4 변경 규모

```
 .github/workflows/axiom-operational-slice.yml |  17 ++
 Makefile                                      |   1 +
 tools/ci/landing_observe.sh                   | 255 +++++++++++++++++++--
 tests/ci/test_landing_observe_acceptance.nim  | 190 (신규)
```

## 5. 이 문서가 주장하지 않는 것 (Non-claims)

1. **이 도구는 권위가 아니다.** exit 0은 "GitHub가 이 커밋을 수용했다"는 뜻이 아니라 "결속된 push 런과 그 아티팩트가 그 커밋에 대해 성공을 기록하고 있고, digest·결속 검증을 통과했다"는 뜻이다. 착지 판정 권위는 merge commit + org 게이트에 그대로 있다.
2. **다른 커밋에 대한 주장이 아니다.** `--main <sha>`의 판정은 그 SHA 하나에만 적용된다. 같은 저장소의 다른 커밋·다른 워크플로·다른 브랜치로 일반화되지 않는다.
3. **`--offline`은 최신성 주장이 아니다.** 과거 관측을 재사용한다는 사실을 출력에 명시한다. 상태가 바뀌었는지 확인하려면 온라인 경로로 다시 관측해야 한다.
4. **`engineBuild=unmeasured`는 결함이 아니다.** 이 트리에서 `VerifierBuildId`가 측정되지 않아 워크플로가 그대로 기록한 값이다(`.github/workflows/axiom-operational-slice.yml`의 provenance 스텝: 측정 불가 시 `unmeasured`로 기록). L4는 아티팩트를 읽기만 하고 이 값을 바꾸지 않는다.
5. **closure 파생 캐시는 이 슬라이스에 없다.** `derive_checker_closure`의 비용(약 5.9초, 그 대부분이 경로당 `git show` spawn)은 별도 후속이다 — H2 판정은 여전히 authoritative 경로에서 계산된다.
6. **`make test-unit`의 나머지 항목은 여전히 CI에서 실행되지 않는다.** 이 슬라이스가 CI에 배선한 것은 이 테스트 하나다. 나머지를 같은 방식으로 승격할지는 별도 결정이다.
7. **비용 절감률을 주장하지 않는다.** 이 문서가 실측으로 고정한 것은 "같은 사실을 다시 사지 않는 경로의 존재와 그 단가(3/2/0)"이며, 저장소 전체 착지 시간이 몇 % 줄었다는 주장은 별도 표본이 필요하다.

## 6. 재현 명령 (Reproduction)

```bash
# (1) 실네트워크 L4 — canonical main 수용 아티팩트 읽기 (호출 수 포함)
tools/ci/landing_observe.sh --main 4a036781c7cade891157077d3202b6f6fb7a7284 --stats; echo "exit=$?"

# (2) 같은 주체 재관측 (웜 캐시: API_CALLS 2)
tools/ci/landing_observe.sh --main 4a036781c7cade891157077d3202b6f6fb7a7284 --stats

# (3) 캐시만 읽기 (API_CALLS 0, 최신성 주장 아님)
tools/ci/landing_observe.sh --main 4a036781c7cade891157077d3202b6f6fb7a7284 --offline --stats

# (4) 결속된 런을 직접 확인 (도구와 독립)
gh api "repos/Archright/Axiom/actions/workflows/axiom-operational-slice.yml/runs?head_sha=4a036781c7cade891157077d3202b6f6fb7a7284&event=push" \
  --jq '.total_count, (.workflow_runs[] | {id,run_attempt,status,conclusion,head_sha})'

# (5) 계약 고정 테스트 (네트워크 0)
nim c -r tests/ci/test_landing_observe_acceptance.nim
```

기대: (1) `VERDICT: OBSERVED_SUCCESS` / exit 0 / `API_CALLS: 3`, (2) `API_CALLS: 2`, (3) `API_CALLS: 0`, (4) `total_count=1` 그리고 `status=completed, conclusion=success`, (5) 12 `[OK]`.
