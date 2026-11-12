# CI Epoch Record — ci-cache-publisher job-level pre-filter (2026-10-25)

> **§2.5 CI Epoch Cutover, 단계 1–8 기록.** 단계 9(Production Acceptance)는 착지 후 실 API 관측으로 §9에 기입되었다(2026-10-25, 항목 4는 pre-existing collector 상한으로 부분 충족 — §11 F1). 정본 규칙: `AGENTS.md` §2.5 / `docs/agents/ci_epoch_cutover.md`. 형식 선행 기록: `docs/evidence/ci_epoch_record_2026-10-12.md`.
>
> 본 기록이 소유한 구현 물건: `.github/workflows/ci-cache-publisher.yml`(job-level pre-filter) + `tools/ci/e4e5_collect.sh`(pre-filter 계수·세대 스캔) + 본 기록. **PR-2는 프로토콜 단계가 아니다** — 단계 9(Production Acceptance)의 **착지 후 append 자리**와 `data/e4e5/landing_boundaries/` write-once 기록(`data/e4e5/README.md:18`)을 채우는 후속 절차다. 선례: `docs/evidence/epoch_record_storage_retention_2026-10-10.md:145-147`(단계 9 착지 후 append), `docs/evidence/s2-cutover-runbook-2026-10-13.md:198-199`(append-only). 단계 1–8은 재개정하지 않는다.

## 1. Freeze (단계 1)

| 항목 | 값 |
|---|---|
| freeze tag | `ci-epoch-pre-publisher-job-if-2026-10-25` (annotated) — **생성·push 완료** |
| tag object OID | `287d051a2e56868ff00b0280165758773efdc5be` |
| frozen commit | `ed832e9a7e8901f69c0f42f6513fa581eea4965d` (`origin/main`, 2026-10-24T20:07:49Z, PR #1099) |
| workstream branch | `ci/publisher-job-if-2026-10-25` (`origin/main`에서 분기) |
| 로컬 main | `bb8eca2ee` — 19 커밋 뒤처짐, **mutation 없음**(§2.1) |

## 2. Record (단계 2)

### 2.1 변경 대상 workflow blob

| 항목 | 값 |
|---|---|
| path | `.github/workflows/ci-cache-publisher.yml` |
| blob SHA (frozen/old) | `3171660d731fdd4305503dcf4509d76a9182a00f` |
| blob SHA (new) | `e388bf4a61bfdb508362f1aaf64bb716e7c03882` |
| surface class | CONTROLLED (`config/repository_surface.json:227`; MODIFY PASS) |
| 권한 | `permissions: contents: read, actions: read` — **불변** |
| required check 여부 | **아님** (ruleset 20303214 5-context에 없음; `config/policy/merge_admission.json` trustSurface 밖) |
| trigger | `workflow_run: workflows ['*','!ci-cache-publisher'], types [completed]` — **불변** |
| concurrency | `ci-cache-publisher-single-flight`, `cancel-in-progress: false` — **불변** |

### 2.2 불변 trust binding

| 항목 | 관측값 (freeze 시점) | 변경 |
|---|---|---|
| ruleset | `20303214` (main), required 5: `admission-check`·`bsec-integrity`·`debt-registry-gate`·`generation-acceptance`·`axiom-operational-slice`; `strict=false`; `required_approving_review_count=0` | 없음 |
| merge queue | MERGE method, ALLGREEN, max_entries_to_build 2, merge 1, `bypass_actors: []`, `current_user_can_bypass: never` | 없음 |
| trusted-writer-set | `contents:write` workflow 집합 == `certificate-mint.yml` | 없음 |
| repository surface policy | `policyVersion 89` — **bump 없음**(파일 FROZEN, 무접촉) | 없음 |
| cache key identity / `ciGeneration` | 불변 (본 변경은 key·reuse·verdict identity를 건드리지 않는다) | 없음 |

## 3. Tombstone (단계 3)

- **Superseded**: "성공 conclusion의 모든 타 workflow 완료마다 `publish` 잡에 러너를 할당하고, in-job guard가 API 조회 후 path 게이트에서 skip" — 이 실행 경로는 종료되었다.
- **존속(권한)**: in-job guard(`:197-231`)는 게시 판정 authority로 **그대로 유지**된다. pre-filter는 conservative selector이며 권한이 아니다.
- **존속(계측)**: `skip-report`는 비성공 conclusion에서 path와 무관하게 계속 발화한다 — E4/E5의 UNKNOWN-seed 의미를 보존하기 위한 의도적 비대칭.
- tombstone은 required-check 우회·trust gate 비활성화·authority 제거를 의미하지 않는다.

## 4. New Epoch (단계 4)

### 4.1 변경 (2곳)

```yaml
publish.if: ${{ github.event.workflow_run.conclusion == 'success' && (github.event.workflow_run.path == '.github/workflows/admission-gate-v2.yml' || startsWith(github.event.workflow_run.path, '.github/workflows/admission-gate-v2.yml@')) }}
skip-report.if: ${{ github.event.workflow_run.conclusion != 'success' }}   # 불변
```

### 4.2 왜 술어가 이 형태인가 (Q6)

`docs/spec/ci_provider_failover_quirks.md:216-243`는 `workflow_run.path`가 `@ref` suffix를 가질 수 있고 "raw path도 bare path도 exact-match 금지"라고 규정한다. 위 술어는 `strip(@ref) == bare`와 **case-sensitive 모델에서 모든 입력에 대해 동치**다.

GitHub 표현식의 `==`/`startsWith`는 **대소문자를 무시**한다(공식 expressions 문서). 따라서 pre-filter는 byte-exact identity가 아니라 **conservative selector(admission superset)** 다. 대소문자 변형은 pre-filter를 통과할 수 있으나, 대소문자를 구분하는 in-job guard(`[ "$RPATH" != ... ]`)가 최종 게시를 거부한다 — 즉 widening은 "러너 1회 낭비"로 귀결되고 잘못된 게시로 이어지지 않는다.

공식 근거(2026-10-25 확인):

- `jobs.<job_id>.if`는 `github` 컨텍스트와 전체 함수 어휘(`startsWith` 포함)를 사용할 수 있다 — contexts reference "Context availability" 표.
- **"The if check is processed by GitHub Actions, and the job is only sent to the runner if the result is true."** — 즉 false 조건의 job은 러너 할당 자체가 발생하지 않는다. 이것이 본 변경의 절감 메커니즘이다.
- `path`가 payload에 없으면 nonexistent property → `''`로 평가되어 두 arm 모두 false(fail-closed). `startsWith(null, …)`도 null → `''` 캐스팅으로 false. 즉 경로 부재 시 게시하지 않는다 — 변경 전 in-job guard와 동일한 결과이며, 차이는 러너를 쓰지 않는다는 것뿐이다.

### 4.3 왜 `skip-report.if`를 건드리지 않는가

`publish.if`에만 path 조건이 있으므로 job 상태 조합이 다음처럼 **모호하지 않게** 된다.

| triggering conclusion | path | publish | skip-report | 의미 |
|---|---|---|---|---|
| success | gate | 실행 | skipped | 정상 게시 경로 |
| success | 비게이트/미인식 | skipped | skipped | **pre-filter됨** (러너 0) |
| 비성공 | 무엇이든 | skipped | 실행 | 기존 UNKNOWN-seed 경로 (불변) |

`publish`=skipped **and** `skip-report`=skipped ⇔ "성공 conclusion + 경로 미인식"이다. 비성공이면 path와 무관하게 `skip-report`가 반드시 실행되므로, **비성공 완료의 UNKNOWN-seed 의미는 바이트 동일**하다.

## 5. Atomic Binding Update (단계 5)

| 파일 | 역할 |
|---|---|
| `.github/workflows/ci-cache-publisher.yml` | 실행 pre-filter |
| `tools/ci/e4e5_collect.sh` | pre-filter 계수 + 게이트 path 양 세대 스캔 + Q6 정규화 |
| `docs/evidence/ci_epoch_record_2026-10-25-publisher-job-if.md` | 본 기록 |

- 결속하지 않은 것: ruleset·required checks·surface policy·cache key·`ciGeneration`. trust binding 변경이 없으므로 부분 갱신 상태가 존재하지 않는다.

## 6. Local / Targeted Verification (단계 6)

| # | 명령 | 결과 |
|---|---|---|
| 1 | `bash -n tools/ci/e4e5_collect.sh` | exit 0 |
| 2 | PyYAML parse + trigger/predicate assertions | PASS — trigger `['*','!ci-cache-publisher']`, `publish.if`에 `startsWith(bare+'@')`, `skip-report.if`에 `path` 없음 |
| 3 | 술어 등가성 6케이스 (bare / `@main` / `@refs/heads/main` / empty / 다른 파일 / `.bak`) | case-sensitive 모델 전건 일치; empty·다른 파일·`.bak` = false (fail-closed) |
| 4 | 대소문자 변형 `.GITHUB/WORKFLOWS/...` | `pred_ci=true` — 문서화된 widening, guard가 거부 |
| 5 | `jq` path 정규화 필터 (suffix `@main` 매칭, `.bak` 비매칭) | 기대값 1 |
| 6 | two-skipped jobs fixture → `classified=prefiltered` | PASS |
| 7 | `make check-workflow-shell-syntax` | PASS — 225 run-block, 0 failures |
| 8 | `make check-repository-surface` | PASS — changeCount 3 (add 1 / modify 2), policyVersion 89, FROZEN 접촉 없음 |
| 9 | pre-push 15-gate pipeline (`git push`) | PASS — `[PASS] Pre-push checks passed`; ruleset bypass는 `.github/workflows/**` 변경에 대한 OrgAdmin 경로(예상됨) |

### 6.1 Collector 변경 요약

- `scan_target`: `.path | split("@")[0] | endswith($suffix)` — Q6 정규화(두 스캔 공통).
- gate 스캔: `GATE_PATH=admission-gate-v2.yml` + `GATE_PATH_LEGACY=admission-gate.yml` 양 세대 동시 스캔. 수집 창(2026-10-11T02:52:14Z~2026-11-10T02:52:14Z) 내부에 2026-10-16 rename이 있어 한 세대만 스캔하면 창의 한쪽이 누락된다. 선례: `tools/ci/merge_latency_audit.sh:108-114`.
- ledger: `counts.prefiltered_observations`, `targets.admission_gate.paths`(양 세대), notes 1줄. `seed_observations`·`UNKNOWN-seed` 의미 불변.
- `e4e5_classify.sh`는 `targets`/`runs_seen`을 읽지 않으므로(코드 확인) 새 key는 additive다.

## 7. Short Validation (단계 7)

- PR-1의 required checks 5종.
- **한계**: `workflow_run`은 default branch의 workflow 파일로 실행된다(공식 events 문서). 따라서 pre-filter 동작은 PR에서 관측 불가하고, PR 단계는 "무회귀 + 단위 증명"까지다. 실제 동작 증명은 §9뿐이다.

## 8. Canonical Cutover (단계 8)

| 항목 | 값 |
|---|---|
| PR-1 | [#1100](https://github.com/Archright/Axiom/pull/1100) |
| merge commit OID | `4a036781c7cade891157077d3202b6f6fb7a7284` |
| T_land | `2026-10-24T23:25:52Z` |
| merge 경로 | merge queue → native MERGE. `gh pr merge 1100 --auto --merge --match-head-commit aeec3c184…` → queue entry #1 `AWAITING_CHECKS` → MERGED. `parent2 == aeec3c184` (INV-1), 배포 blob `e388bf4a…` == 로컬 검증본 |
| write-once 경계 기록 | `data/e4e5/landing_boundaries/2026-10-24T232552Z-publisher-job-if.json` |

## 9. Production Acceptance (단계 9) — **accepted 2026-10-25 (관측값 기입)**

merge 후 다음이 **모두** 관측되어야 Terminal Outcome이 충족된다. 각 항목의 관측값은 T_land(`2026-10-24T23:25:52Z`) 이후 실 API 조회 결과다.

1. **비게이트 성공 완료 → 러너 미할당** — 관측: `40143155146`, `40143466434`, `40143507441` 모두 `publish=skipped runner_id=null`, `skip-report=skipped runner_id=null`. 첫 post-change 런 `40142746039`(23:26:28Z)도 run conclusion `skipped`. → **충족**
2. **게이트 완료 → 게시 경로 보존** — 관측: `40143484986`(23:37:20Z) `publish` success(runner 4853), 로그에 `[publish] guard=true trees=true verify=true key=axiom-b-…`, `[publish] lane-save: outcome=success`, `[publish] base-save: outcome=skipped`(single-flight hit — 정상 의미). 마지막 옛 경로 런 `40142681942`(23:25:30Z)도 `guard=true` + `base-guard=true`. → **충족**
3. **병합 권위 불변** — 관측: ruleset 20303214 required contexts = `admission-check`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice` (5종, 변경 없음). PR #1100의 required checks 5종 green 후 merge queue → MERGED. → **충족**
4. **측정 호환성** — collector의 **정확한 분류 술어**를 실제 post-merge 런 3건에 그대로 적용: 전건 `skip-report=skipped ∧ publish=skipped` → `prefiltered` 분기 성립. 별도로 완결된 2일 창 패스(2026-10-11T02:52:14Z→10-13T02:52:14Z)가 수정된 collector로 ledger를 정상 산출했다 — gate runs 193 / publisher runs 155 / `consumer_observations` 53 / `seed_observations` 155 / `prefiltered_observations` 0 (창이 변경 전이므로 기대값 0, 새 key additive 확인). **전체 창 패스는 기존 결함으로 차단**: 마지막 날 `event=workflow_run total_count=1445 > 1000` 슬라이스 상한 → HARD-FAIL(무음 절단 방지). 런 수는 본 변경으로 증가하지 않으므로 pre-existing이며, adaptive slice 분할은 Follow-up으로 등록한다(§11 F1).
5. **성공한 gate가 publish 없이 종료되면 그것은 캐시 성능 저하가 아니라 Terminal Outcome 실패다** — 로그 조회 오류와 실제 게시 누락을 구별하고, 실제 누락이면 즉시 rollback한다. 2회 연속 실패를 기다리지 않는다. (본 기준은 **이 기록에서 신규 채택·사전 등록**한 것이며, `ci_epoch_cutover.md` 단계 10에 존재하는 기존 수치 임계값이 아니다. 선례: `docs/evidence/g1_cache_supply_experiment_2026-10-16.md:33-40`의 사전 판정표.) → **위반 관측 없음**

## 10. Rollback (단계 10)

- rollback = revert PR을 merge queue로 착지.
- frozen tag `ci-epoch-pre-publisher-job-if-2026-10-25`(`ed832e9a7`)가 immutable baseline.
- rollback은 cache key·verdict identity에 영향을 주지 않는다.

## 11. Follow-up (범위 밖 — 등록만, 본 변경의 완료 조건 아님)

| # | 항목 | 근거 |
|---|---|---|
| F1 | collector 슬라이스 상한: `event=workflow_run` 1일 1,445건 > 1,000 → HARD-FAIL. adaptive slice split 필요 | §9-4. 런 수는 본 변경과 무관 — pre-existing |
| F2 | 7일 B-cache 적중률 모니터: 기존 78.6%(11/14) 기준, base-key advance·대상 게이트 실행 수를 함께 기록 | 표본 14가 작음 |
| F3 | `data/e4e5/ledger.json` 추적 파일 갱신: 수용 패스는 `/tmp`로 수행해 저장소를 오염시키지 않았다. F1 해소 후 정규 패스로 갱신 | write-once 경계 기록은 ledger를 개정하지 않는다 |

## 부록 A — 비용·모집단 실측 (감사 결과)

| 항목 | 값 | 비고 |
|---|---|---|
| publisher 런 (31일) | 4,908 / 2,016.7 wall-min | wall은 finalize lag를 포함해 runner-occupancy를 ~2× 과대평가 |
| runner-occupancy | ~950–1,000 job-min/31일 | 단일 job 런 기준 job 시간이 실제 점유 |
| 비게이트 완료 | ~3,502 (71.4%) | gate 완료 2,004 = 1,898 `admission-gate` + 106 legacy-path |
| 취소된 publisher 런 | 606 (12.3%) | 단일-flight pending supersession — 본 변경과 무관한 기존 손실 |
| B-cache hit | 11/14 = 78.6% | miss 3건은 모두 새 base-key 세대의 첫 소비자 |
| 비게이트 1건당 job 시간 | ~5.5s (중앙값) | pre-filter가 제거하는 대상 |

본 변경이 제거하는 것은 **성공한 비게이트 완료**의 러너 점유다. 실패한 비게이트 완료의 `skip-report`(3–5s)는 계측 불변식을 위해 유지한다.