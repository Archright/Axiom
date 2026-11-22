# axiom-admission-verifier 운영 계약 (App `5795152`)

> **정본 경계**: 이 문서는 **운영 계약**만 정의한다 — identity, 판정 입력, 관측 명령, 소유권, 잔여. 병합 권위는 repo ruleset `27097366`이고, 검증 대상 목록의 정본은 `config/policy/trust_surface_manifest.json`, producer 정책의 정본은 `config/policy/merge_admission.json`, 결정 정본은 [docs/adr/0041-free-authority-migration.md](../adr/0041-free-authority-migration.md)다. 이 문서는 그 계약을 재정의하지 않는다.

## 1. Identity

| 항목 | 값 |
|---|---|
| slug | `axiom-admission-verifier` |
| App id | `5795152` |
| ruleset expected source | `admission-check` → integration_id `5795152` (나머지 6 context는 `15368`) |
| 설치 저장소 | `Archright/Axiom` (repository id `1454952493`) |
| 소스 공개 위치 | 없음 — 공개 org 저장소에 App 소스가 없다 |

## 2. 이벤트와 권한

| 이벤트 | 용도 |
|---|---|
| `merge_group` | 큐가 만든 그룹 커밋 `G`를 판정하고 `G`에 `admission-check`를 발행 |
| `workflow_run` | `.github/workflows/admission-gate-v2.yml` 런 완료를 판정 입력으로 소비 |

권한(최소 집합):

- `actions: read` — 검증 대상 run 객체·아티팩트 조회
- `checks: write` — `admission-check` Check Run 발행
- `contents: write` — 원장(`refs/heads/axiom/certificates`) append 전용
- `merge_queues: read` — 큐 엔트리·그룹 상태 조회
- `metadata: read` — 저장소 identity
- `statuses: write` — commit status 채널

`contents: write`의 실제 상태(2026-11-18 실측): **원장 writer는 아직 `github-actions[bot]`이다** — 원장 head `8c42fcb`의 `author=github-actions[bot]`, `committer=GitHub`, `verified=true`. App은 `contents: write`를 보유하지만 원장에 쓴 기록이 없다. 따라서 "원장 기록을 독립 App으로 이전했다"는 서술은 **철회**한다. 현재 원장 쓰기는 `certificate-mint.yml`의 `publish` 잡(이 워크플로의 유일한 job-level `contents: write`)이 수행하고, `prepare`는 `contents: read`다. writer 이전은 App 소스 확장 이후의 계획 항목이며, 그때까지 이 문서는 "App이 원장을 쓴다"고 주장하지 않는다.

## 3. 판정 입력과 발행

1. **manifest는 `B_mg`에서 읽는다 — `G`에서는 절대 읽지 않는다.** `config/policy/trust_surface_manifest.json`의 `readFrom` 필드가 이 불변식을 선언한다(`B_mg (merge_group.base_sha), never from G`). 목적은 PR이 검증 목록 자체를 축소하지 못하게 하는 것이다.
2. **manifest의 모든 blob 경로를 비교한다** (2026-11-20 기준 18개: actions 1 · workflows 9 · config 6 · tests 1 · tools 1): 각 경로에 대해 `blob(G) == blob(B_mg)`. 정본은 `config/policy/trust_surface_manifest.json`의 `paths`이며 **개수를 하드코딩하지 않는다** — 경로 추가·삭제는 manifest diff로만 일어나고, 그 자체가 trust surface다. 불일치는 경로명과 개수를 사유로 보고한다.
3. **원장 결속을 확인한다**: subject-continuity 원장이 `(base, pr_head)`에 결속된 항목을 정확히 1개 얻었는지 본다.
4. **`admission-check`를 PR head와 `G` 양쪽에 발행한다** — PR-venue는 preflight, `G`는 merge-admission 판정이다. 판정 조건(워크플로 path, 이벤트 venue, `head_sha`, `conclusion`)은 ADR-0041 §1의 네 조건을 그대로 따른다.

### 3.1 판정 대상 결속 (verdict-subject binding) — HARD

`One execution → One immutable execution identity → One corresponding check-run → One subject-bound verdict → One terminal state`. 검증 실행의 신원은 생성 시 결정하고 결과 발행이 끝날 때까지 변경하지 않는다.

실행 신원 = `(repository_id, workflow_id, run_id, run_attempt, venue, head_sha)`. `venue ∈ {pull_request, merge_group}`이며 Actions run의 `event`와 같다.

| 원천 | 권위 범위 |
|---|---|
| `external_id` | 특정 run·attempt를 가리키는 **상관관계 식별자**. 실행 신원 전체가 아니다(`workflow_id`·`venue` 미포함) |
| `GET /repos/{owner}/{repo}/actions/runs/{run_id}` | `workflow_id`·`run_attempt`·`event`·`head_sha`·`updated_at`의 **실행 사실 원천** |
| `GET .../commits/{sha}/check-runs` | `head_sha`·`app.id`·`external_id`·`status`·`conclusion`의 **판정 기록 원천** |
| `output.summary` | 위 기록과의 **일관성 검증 자료** — 권위가 아니다 |

GitHub는 `external_id`를 어떤 run과도 대조하지 않는다("A reference for the run on the integrator's system"이 정의의 전부다) — 실행 신원 대조는 위 두 API로만 성립한다.

금지되는 전이:

1. 실행 결과를 그 실행의 `head_sha`가 아닌 SHA에 발행한다.
2. 완료 대상을 "현재 PR head의 열린 check-run"으로 해소한다.
3. head 이동 후 superseded 실행을 새 head에서 재해석한다.

필수 전이:

1. superseded 실행은 자기 SHA에서만 비성공 종결한다(App이 설정할 수 있는 종결 상태는 `cancelled`이고, `stale`은 GitHub가 14일 경과 후 부여한다).
2. 새 head의 실행은 자기 SHA에 자기 결과를 발행한다.
3. 동일 `run_id#attempt`의 처리는 멱등이며, 완료 판정은 역전되지 않는다.

현재 PR head는 **그 실행이 아직 유효한지(인증서 발급 가능 여부)** 판단에만 쓰고, 이미 생성된 check-run의 소유자를 바꾸는 데 쓰지 않는다.

Acceptance:

1. head=A로 run A를 시작한다.
2. A0의 PR API 재조회 전에 head를 B로 이동한다.
3. A0는 A 인증서 발급을 거부하고, App은 A의 check-run만 비성공 종결하며, B에는 아무것도 발행하지 않는다.
4. B 자신의 run이 성공하면 App은 B의 check-run에 `success`를 발행한다.
5. A의 완료 이벤트를 지연·중복 전달해도 B의 `success`가 역전되지 않는다.
6. ruleset이 B를 정상 병합한다.

merge_group Acceptance (`G` = the group commit the queue creates):

1. While `G1`'s admission-gate run is in-flight, the queue rebuilds the entry into `G2`.
2. `G1`'s `admission-check` becomes terminal only on `G1` — it is not resolved by `G2`'s check-run.
3. `G2` receives its own verdict from its own run's result.
4. Delayed or duplicated delivery of `G1`'s completion event does not invert `G2`'s verdict.

In both venues the judged subject is the single SHA the check-run was published on, never "the currently open check-run".

check-run summary의 형태:

```text
trust_surface=PASS — 15 paths match base <B_mg short>
ledger=PASS — 1 entry bound to (base, pr_head)
run=<RUN_ID> attempt=<N> conclusion=success
```

## 4. fail-closed 의미론

- **결론 미보고는 성공이 아니다.** ruleset의 `check_response_timeout_minutes: 120`이 지나면 GitHub는 결론을 보고하지 않은 required check를 **실패로 간주**하고 큐 엔트리를 제거한다(removal reason: "Timed out awaiting a successful CI result based off the configured timeout setting").
  - <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets> — "After this much time has elapsed, checks that have not reported a conclusion will be assumed to have failed"
  - <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue> — "Choose how long the queue should wait for a response from CI before assuming that checks have failed"
- 따라서 App이 죽었거나 권한이 회수되면 120분 뒤 엔트리는 **탈큐**된다. 성공으로 기본값 처리되는 경로는 없다.
- App 내부 실패(서명 검증 실패, API 오류, 중복 런, 타임아웃)도 `failure` 발행으로 끝난다. `neutral`·미발행으로 통과시키지 않는다.
- **head 이동 시 인증서 발급 거부는 정당하다 — 유지한다**: App은 `workflow_run` 완료 시점의 **현재 PR head**와 그 run의 `head_sha`를 비교하고, 불일치하면 그 run에 대한 인증서 발급을 거부한다(2026-11-17 PR #142 실측, `reasons=run_head_mismatch`). 이 거부는 `.github/workflows/certificate-mint.yml`의 A0 PR-identity leg와 같은 불변식이다 — PR API의 `head.sha`가 `headSha` 입력과 다르면 fail-closed(`:1553`). 이동한 head를 검증 대상으로 인증하지 않는 것 자체가 계약이며, 이 부분은 제거 대상이 아니다.
- **그 거부를 "새 head"의 판정으로 발행하는 것은 계약 위반이다**: 거부는 그 실행의 `head_sha`에 대한 판정이어야 한다. App은 이를 **현재 PR head**에 check-run으로 발행하므로, 평가한 적 없는 주체에 평가 결과를 주장한다 — `evaluated_commit`이 그 run이 건드리지 않은 commit을 가리킨다(§3.1 위반). 실측 payload: `external_id`는 run `44874261646#1`을 지목하는데 `output.summary`는 `run=44873857358`을 지목한다 — 한 check-run의 두 필드가 서로 다른 run을 가리킨다. 그 failure가 새 head에 남는 한, 새 head는 자기 run의 체크 없이는 required check를 만족하지 못한다.
- **기존 "운영 규칙 (i)(ii)(iii)"은 임시 우회책(계약 아님)이다**: (i) admission run이 in-flight인 동안 head를 이동시키지 않는다; (ii) 이동이 발생하면 새 head에서 run을 완료시켜 새 체크 발행을 받는다; (iii) 어떤 경우에도 bypass로 통과시키지 않는다. 이는 App이 수정될 때까지 개발자 측에서 결함을 회피하는 절차이며 **수정(fix)이 아니다** — 이 문서는 이를 계약으로 승격하지 않는다.

## 5. 관측 명령

| 목적 | 명령 |
|---|---|
| PR-head checks | `gh pr checks <N> --watch` |
| `G`의 check-runs | `gh api repos/Archright/Axiom/commits/<G>/check-runs?per_page=100` |
| run 완료 추적 | `gh run watch <RUN_ID> --exit-status --interval 30` |
| verdict attribution check | `bash tools/ci/verdict_attribution_check.sh --repo Archright/Axiom [--venue pull_request\|merge_group] --sha <SHA>` (exit 0 clean / 1 violation / 2 unverifiable). It judges both venues: `pull_request` (default, external_id `v1p|`) and `merge_group` (external_id `v1|`; run identity is resolved from `run=`/`attempt=` in `output.summary` and cross-checked against the Actions Run API). Check-runs of the other venue are excluded and counted separately. The run path is compared after truncating from the first `@` (quirk Q6). |

The `coverage` field reports per-SHA classification and aggregation:

| field | meaning |
|---|---|
| `perSubject[].classification` | `RESOLVED_CLEAN` (exit 0 + eligible runs >= 1) / `RESOLVED_VIOLATION` (exit 1) / `UNRESOLVED` (exit 2: zero eligible runs, or V2-UNRESOLVED/V4-UNVERIFIABLE) |
| `subjects` | number of judged SHAs (the `--sha` set, otherwise the observed SHAs) |
| `resolved` | `RESOLVED_CLEAN` + `RESOLVED_VIOLATION` |
| `unresolved` | `UNRESOLVED` |
| `violations` | number of `RESOLVED_VIOLATION` subjects (not the total number of violation rows) |
| `coverageRatio` | `resolved/(resolved+unresolved)`; `null` when the denominator is 0 |

Coverage never weakens a violation verdict. `PASS` requires `subjects > 0`, `unresolved == 0`, and `violations == 0` — with an `UNRESOLVED` subject and no definite violation the result is `UNVERIFIABLE` (exit 2) instead of `PASS`. A definite violation yields `FAIL` (exit 1), and unresolved subjects do not mask it. There is no path that converts unresolved into pass. One invocation emits only one exit code, so per-SHA attribution is read from per-SHA invocations or from `coverage.perSubject`.

### 5.1 Detector invocation requirements

- **`--sha` must be a full 40-hex (or 64-hex) commit id.** The detector rejects a short SHA before any API call: stderr is `ERROR invalid --sha: <value>` (no JSON is emitted on stdout) and the exit code is `2` (UNRESOLVED). Resolve the full SHA first (for example from `gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100"`), and never truncate a SHA when invoking the detector.
- **In the `merge_group` venue the `external_id` prefix `v1|` does not encode a run id.** Its fields are `v1|<repo_id>|<head_sha>|<base_sha>|<baseline>`; there is no `run=`/`#attempt` segment. Run identity is resolved from `run=`/`attempt=` in the check-run `output.summary` and **MUST be cross-checked against** `GET /repos/{owner}/{repo}/actions/runs/{run_id}` (id, `run_attempt`, `event`, `path`, `head_sha`). `output.summary` is consistency data — **not an authority** for run facts. An absent or unresolvable `run=`/`attempt=` is `V2-UNRESOLVED` and exits `2`; it is never treated as clean.

`gh pr checks --watch`는 merge-queue 단계를 추적하지 않는다(PR-head checks 종료 시 exit). 큐 진입 후에는 `G`의 check-runs를 직접 조회한다 — quirk 정본: [docs/spec/gh_automerge_merge_queue_quirks.md](../spec/gh_automerge_merge_queue_quirks.md).

## 6. 소유권과 에스컬레이션

- **소유자**: `Archright` 조직 오너(단일 maintainer). App 등록·권한·웹훅·설치 갱신은 이 계정 권한이다.
- **이 저장소에서 재배포하지 않는다**: App 소스는 공개 org 저장소에 없다. 이 저장소의 어떤 스크립트·게이트도 App을 생성·수정·재설치하지 않으며, 그런 경로를 추가하지 않는다.
- **에스컬레이션 순서**: (i) `G`의 check-runs를 조회해 발행 여부 확인 → (ii) 발행 없음 = App 가용성 문제 → 오너 보고 → (iii) 발행 있음 + `failure` = 검증 실패 → PR 수정. 재큐잉·우회로 통과시키지 않는다.

## 7. 잔여 (계획 항목)

- **App은 외부 서비스다**: 가용성, 권한 변경, 웹훅 전달, 설치 상태는 이 저장소 밖이다. 이 저장소가 보장하는 것은 "결론이 없으면 병합되지 않는다"(§4)뿐이며, 그 보장의 대가는 최대 120분의 지연이다.
- **Free에는 원장 쓰기 행위자를 귀속시키는 권위 기록이 없다**: org audit-log API는 Free에서 404(Enterprise Cloud 전용)이고, `git.push` 이벤트는 7일 보존·export 전용이며 `ref`·`integration_id` 필드가 없다. commit author/committer는 호출자가 지정하는 문자열이다. 따라서 writer 보장은 "App이 썼다"가 아니라 "ruleset이 수정되지 않은 한 App만 쓸 수 있다"로만 성립한다.
- **ruleset 편집 권한은 예방이 아니라 탐지 대상이다**: repo admin은 `Administration: write`로 ruleset `27097366`을 편집·비활성화할 수 있다. 이 계약은 그 사실을 숨기지 않는다.
- **원장 append 멱등성 결함 2건**: `appendCertificate`(`src/verification/ledger_side_ref.nim:508`)는 **첫 시도에 중복 검사를 하지 않고**(재시도 경로만 `ledgerHasCertAtTip` `:493` 사용), 워크플로는 `bin/ax cert ledger-list` 실패를 "부재"로 간주하고 append로 넘어간다(`.github/workflows/certificate-mint.yml:2263`). `run_attempt`는 원장 키가 아니다(키 = `subjectId`).
- **`ax cert ledger-append` 경로에 서명 검증이 없다**: `src/verification/ledger_side_ref.nim` 전체에 ed25519/서명 검증 호출이 존재하지 않는다(2026-11-18 grep). 첫 발급 시 forged `certificate.json`이 원장에 들어갈 수 있으며, 원장의 신뢰는 전적으로 writer identity에 의존한다.
- **`prepare`는 여전히 artifact 바이너리를 실행한다**: `admission-check-base-artifacts`의 `bin/ax`·`ircheck`를 워크스페이스에 설치해 `cert attest --sign`에 사용한다. 해당 잡은 `contents: read`라 write 탈취는 아니지만, SL-22가 닫은 것과 같은 공급 계열의 결함이다(별도 debt).
- **App의 완료 시점 결속은 미해결 외부 결함이다(#256)**: App은 run 완료 시점의 현재 PR head에 판정을 발행하므로, 그 판정이 실행 주체와 어긋날 수 있다(§3.1 위반, §4 실측). 이 저장소는 §5의 판정 귀속 검사로 이를 관측하고 관측 결과를 기록한다. App 소스도 설치 토큰도 없으므로 **이 저장소는 이 결함을 수리할 수 없다** — 수리는 App 소유자(§6)의 몫이며, §4의 임시 우회책은 수리를 대체하지 않는다.
- **The external App defect is tracked only at issue #256**: it is not registered in `data/debt_registry.json` — that schema has no owner/externalRef field, and adding a second status would duplicate authority.
- **ruleset `27097366` bypass window (2026-11-21, observation record)**: history version `58912954` (2026-11-21T07:58:16Z) had `bypass_actors` = `[{actor_type: OrganizationAdmin, bypass_mode: pull_request}]`, and version `58913011` (07:59:24Z) restored it to `[]`. PR #309 merged inside that window, at 07:58:46Z, with merge commit `858710ae6f590d7dae06646142e79851dda10721`. On the same PR head `41c02cf096a934cbe1d7e94b96e8adbb2feb0ae6`, `admission-check` (App 5795152, check-run `136777708112`) had already completed as `failure` at 07:48:37Z. These values are facts observed through the ruleset history API and the check-runs API; this document does not judge intent.
- 이 App 계약은 다음 잔여를 닫지 않는다: 같은 저장소 PR이 쓰기 잡을 추가하는 경로(§1.2/§11.4), 나머지 6 contexts의 producer가 Actions `15368`인 표면([docs/evidence/free_authority_migration_phase0_proof.md](../evidence/free_authority_migration_phase0_proof.md) §12.4). 둘 다 계획 항목이다.