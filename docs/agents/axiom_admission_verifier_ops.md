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

`contents: write`가 있는 이유는 쓰기 경계 분리다: `merge_group` 실행 영역을 `contents: read`로 격리하고 원장 기록을 독립 App으로 이전했다 — 근거와 실측은 [docs/evidence/free_authority_migration_phase0_proof.md](../evidence/free_authority_migration_phase0_proof.md) §1.2, §4다.

## 3. 판정 입력과 발행

1. **manifest는 `B_mg`에서 읽는다 — `G`에서는 절대 읽지 않는다.** `config/policy/trust_surface_manifest.json`의 `readFrom` 필드가 이 불변식을 선언한다(`B_mg (merge_group.base_sha), never from G`). 목적은 PR이 검증 목록 자체를 축소하지 못하게 하는 것이다.
2. **15개 blob 경로를 비교한다**: 각 경로에 대해 `blob(G) == blob(B_mg)`. 불일치는 경로명과 개수를 사유로 보고한다.
3. **원장 결속을 확인한다**: subject-continuity 원장이 `(base, pr_head)`에 결속된 항목을 정확히 1개 얻었는지 본다.
4. **`admission-check`를 PR head와 `G` 양쪽에 발행한다** — PR-venue는 preflight, `G`는 merge-admission 판정이다. 판정 조건(워크플로 path, 이벤트 venue, `head_sha`, `conclusion`)은 ADR-0041 §1의 네 조건을 그대로 따른다.

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

## 5. 관측 명령

| 목적 | 명령 |
|---|---|
| PR-head checks | `gh pr checks <N> --watch` |
| `G`의 check-runs | `gh api repos/Archright/Axiom/commits/<G>/check-runs?per_page=100` |
| run 완료 추적 | `gh run watch <RUN_ID> --exit-status --interval 30` |

`gh pr checks --watch`는 merge-queue 단계를 추적하지 않는다(PR-head checks 종료 시 exit). 큐 진입 후에는 `G`의 check-runs를 직접 조회한다 — quirk 정본: [docs/spec/gh_automerge_merge_queue_quirks.md](../spec/gh_automerge_merge_queue_quirks.md).

## 6. 소유권과 에스컬레이션

- **소유자**: `Archright` 조직 오너(단일 maintainer). App 등록·권한·웹훅·설치 갱신은 이 계정 권한이다.
- **이 저장소에서 재배포하지 않는다**: App 소스는 공개 org 저장소에 없다. 이 저장소의 어떤 스크립트·게이트도 App을 생성·수정·재설치하지 않으며, 그런 경로를 추가하지 않는다.
- **에스컬레이션 순서**: (i) `G`의 check-runs를 조회해 발행 여부 확인 → (ii) 발행 없음 = App 가용성 문제 → 오너 보고 → (iii) 발행 있음 + `failure` = 검증 실패 → PR 수정. 재큐잉·우회로 통과시키지 않는다.

## 7. 잔여 (계획 항목)

- **App은 외부 서비스다**: 가용성, 권한 변경, 웹훅 전달, 설치 상태는 이 저장소 밖이다. 이 저장소가 보장하는 것은 "결론이 없으면 병합되지 않는다"(§4)뿐이며, 그 보장의 대가는 최대 120분의 지연이다.
- 이 App 계약은 다음 잔여를 닫지 않는다: 같은 저장소 PR이 쓰기 잡을 추가하는 경로(§1.2/§11.4), 나머지 6 contexts의 producer가 Actions `15368`인 표면([docs/evidence/free_authority_migration_phase0_proof.md](../evidence/free_authority_migration_phase0_proof.md) §12.4). 둘 다 계획 항목이다.