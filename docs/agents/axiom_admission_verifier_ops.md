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
2. **manifest의 모든 blob 경로를 비교한다** (2026-11-18 기준 17개: actions 1 · workflows 9 · config 6 · tools 1): 각 경로에 대해 `blob(G) == blob(B_mg)`. 정본은 `config/policy/trust_surface_manifest.json`의 `paths`이며 **개수를 하드코딩하지 않는다** — 경로 추가·삭제는 manifest diff로만 일어나고, 그 자체가 trust surface다. 불일치는 경로명과 개수를 사유로 보고한다.
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
- **head 이동 시 `run_head_mismatch`(2026-11-17 PR #142 실측)**: App은 `workflow_run` 완료 시점의 **현재 PR head**와 그 run의 `head_sha`를 비교한다. run이 완료되기 전에 head가 이동하면, 완료된 run은 현재 head와 불일치하므로 App은 **현재 head에 `failure`를 발행**한다(`reasons=run_head_mismatch`). 이는 fail-closed로서 올바르다. 다만 이동 후의 head에서 새 run이 성공해도 **이전 failure 체크를 자동으로 대체하지 않는다** — 새 run의 완료가 별도 체크로 발행되지 않는 한 required check는 failure로 남는다. 운영 규칙: (i) admission run이 in-flight인 동안 head를 이동시키지 않는다; (ii) 이동이 발생하면 새 head에서 run을 완료시켜 새 체크 발행을 받는다; (iii) 어떤 경우에도 bypass로 통과시키지 않는다.

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
- **Free에는 원장 쓰기 행위자를 귀속시키는 권위 기록이 없다**: org audit-log API는 Free에서 404(Enterprise Cloud 전용)이고, `git.push` 이벤트는 7일 보존·export 전용이며 `ref`·`integration_id` 필드가 없다. commit author/committer는 호출자가 지정하는 문자열이다. 따라서 writer 보장은 "App이 썼다"가 아니라 "ruleset이 수정되지 않은 한 App만 쓸 수 있다"로만 성립한다.
- **ruleset 편집 권한은 예방이 아니라 탐지 대상이다**: repo admin은 `Administration: write`로 ruleset `27097366`을 편집·비활성화할 수 있다. 이 계약은 그 사실을 숨기지 않는다.
- **원장 append 멱등성 결함 2건**: `appendCertificate`(`src/verification/ledger_side_ref.nim:508`)는 **첫 시도에 중복 검사를 하지 않고**(재시도 경로만 `ledgerHasCertAtTip` `:493` 사용), 워크플로는 `bin/ax cert ledger-list` 실패를 "부재"로 간주하고 append로 넘어간다(`.github/workflows/certificate-mint.yml:2263`). `run_attempt`는 원장 키가 아니다(키 = `subjectId`).
- **`ax cert ledger-append` 경로에 서명 검증이 없다**: `src/verification/ledger_side_ref.nim` 전체에 ed25519/서명 검증 호출이 존재하지 않는다(2026-11-18 grep). 첫 발급 시 forged `certificate.json`이 원장에 들어갈 수 있으며, 원장의 신뢰는 전적으로 writer identity에 의존한다.
- **`prepare`는 여전히 artifact 바이너리를 실행한다**: `admission-check-base-artifacts`의 `bin/ax`·`ircheck`를 워크스페이스에 설치해 `cert attest --sign`에 사용한다. 해당 잡은 `contents: read`라 write 탈취는 아니지만, SL-22가 닫은 것과 같은 공급 계열의 결함이다(별도 debt).
- 이 App 계약은 다음 잔여를 닫지 않는다: 같은 저장소 PR이 쓰기 잡을 추가하는 경로(§1.2/§11.4), 나머지 6 contexts의 producer가 Actions `15368`인 표면([docs/evidence/free_authority_migration_phase0_proof.md](../evidence/free_authority_migration_phase0_proof.md) §12.4). 둘 다 계획 항목이다.