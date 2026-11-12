# Terminal Outcome Acceptance — orphan 시드 위생: quota 위생을 GitHub Actions cache eviction에 위임 (Follow-up #3 폐쇄)

> Vertical Slice 결정 기록 — `docs/evidence/memo_reanchor_acceptance_2026-10-08.md` §5
> Follow-up #3 ("orphan 시드 위생: 소비 불가 예정 키의 시딩 억제 또는 만료 정책 — quota
> 한정 개선")의 authority-first 폐쇄. 정본: `docs/spec/github_delegation_residuals.md`
> §1 위임 목록 신규 항목 + §2 **R11** · 원인 문서: `docs/spec/gh_run_observation_quirks.md`
> Q2 (merge-queue speculative stacking). 실측: 2026-10-08T15:00–15:10Z, `gh` CLI 네이티브
> 인증(**읽기 전용** — 파일시스템·환경변수 자격증명 탐색 0건), 공식 문서 실사
> (Context7 `/actions/cache` + docs.github.com + cli.github.com). 확정된 권한 분리:
> **Axiom=검증/증거, Cache=저장/복원, GitHub=merge 판정 + 캐시 수명(lifecycle)**.

## 1. Authority 분석 — 대안 3건 판정 (금지 2 · 위임 1)

| 대안 | 판정 | 근거 |
|---|---|---|
| ① 소비 불가 예정 키의 **시딩 억제** | **금지** | 시딩 시점에 "소비 가능성"을 예측하는 것 = merge-eligibility(착지 가능성) 판정을 캐시 계층에 재도입하는 것 — PR #594가 제거한 권위 누수(`tree(build)==tree(head)` publish-skip)와 **동형**. 착지 가능성 판정 권위는 GitHub ruleset/merge queue에 있고(ADR-0025 Amendment D — R10 재판정), 캐시 계층의 권위는 저장/복원뿐이다 |
| ② **자체 만료 정책** (스케줄러 · `gh cache delete` 루틴 · 자체 TTL 로직) | **금지** | GitHub가 이미 제공하는 cache eviction(§2 (a)–(c))의 재구현 = **중복 control**. 산출물당 생성 authority 1개 원칙(AGENTS.md §2.6)과 동일 이론 — 만료 authority는 플랫폼에 존재하며, 추가·경쟁시키지 않는다. §2 (d) 실사로 "플랫폼에 만료 제어가 없어서 우리가 만든다"는 변명도 성립하지 않음이 확정됐다(엔트리별 TTL은 애초에 부재 — 자체 만료는 부재를 채우는 게 아니라 eviction을 복제하는 것) |
| ③ quota 위생을 **GitHub Actions cache eviction 정책에 위임** + 잔여를 bounded로 문서화 | **채택** | 유일 해법. 새 제어장치·새 워크플로·새 키 스킴·새 게이트·러너 스크립트 **0**. 위임 전제는 §2 공식 문서 실사로 확증 — 반박 0건(§2.2) |

## 2. 공식 문서 실사 (COMPULSORY — 인용표)

| 항목 | 공식 문장 (원문) | 출처 URL | 판정 |
|---|---|---|---|
| (a) 저장소 총량 상한 | "By default, the limit is 10 GB per repository, but this limit can be increased by enterprise owners, organization owners, or repository administrators." | [Dependency caching reference — Usage limits and eviction policy](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) | 위임 전제 성립 |
| (a') 상한 설정 실측 | REST `GET /repos/Archright/Axiom/actions/cache/storage-limit` → `{"max_cache_size_gb":10}` (2026-10-08 실측 — 기본값, 증가 설정 없음) | [REST API endpoints for GitHub Actions cache](https://docs.github.com/en/rest/actions/cache) | 성립 |
| (b) 상한 초과 시 eviction 규칙 | "Once a repository has reached its maximum cache storage, the cache eviction policy will create space by deleting the caches **in order of last access date, from oldest to most recent**." / "If you exceed the limit, GitHub will save the new cache but will begin evicting caches until the total size is less than the repository limit." | [Dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) | 성립 — last-access LRU 삭제 보장 존재 |
| (c) 미사용 캐시 제거 기간 | "GitHub will remove any cache entries that have not been accessed in over 7 days." / actions/cache README: "Caches that are not accessed within the last week will also be evicted." | [Dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) + [actions/cache README](https://github.com/actions/cache) | 성립 — 제거 창(7일)이 **접근 기반**: 무접근 orphan은 최대 7일 내 제거 |
| (c') 접근이 창을 갱신하는가 | 공식 문장은 제거 조건을 "have not been **accessed** in over 7 days"로, eviction 순서를 "last access date"로 정의한다. `last_accessed_at` 필드가 REST/CLI에 존재하고(`--sort last_accessed_at`이 기본 정렬) 실측상 접근 시 갱신된다(§3.3 대조 — 소비된 키는 created ≠ last_accessed, 무접근 키는 created == last_accessed) | [Dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) + [gh cache list 매뉴얼](https://cli.github.com/manual/gh_cache_list) | 성립 (문장 이상 도입 없음 — 정의된 대로 "접근 기반"까지만 기록) |
| (d) 엔트리별 TTL/만료 네이티브 지원 | **부재**. actions/cache 전체 입력 = `path, key, restore-keys, upload-chunk-size, enableCrossOsArchive, fail-on-cache-miss, lookup-only` (+폐기 예정 `save-always`) — TTL/만료 입력 없음. REST 엔드포인트 세트 = usage · list · delete(key/id) · retention-limit · storage-limit — **만료를 지정하는 캐시 생성 엔드포인트 없음**(캐시 생성은 러너 cache 서비스 경로뿐) | [actions/cache action.yml](https://github.com/actions/cache/blob/main/action.yml) + [REST API endpoints for GitHub Actions cache](https://docs.github.com/en/rest/actions/cache) | 성립 — 엔트리별 만료 제어는 플랫폼에 존재하지 않음 → 대안 ②는 "결핍 보완"이 아니라 "eviction 복제"임이 확정 |
| (e) `gh cache` CLI | 하위 명령 = `list`, `delete` (실측 `gh cache --help`); `list` JSON 필드 = `createdAt, id, key, lastAccessedAt, ref, sizeInBytes, version`, 기본 정렬 `last_accessed_at` | [gh cache list 매뉴얼](https://cli.github.com/manual/gh_cache_list) | 성립 — 관측은 CLI/REST로 충분, 만료 집행 수단은 플랫폼 전용 |
| (f) 캐시 접근 범위(브랜치 격리) | "Workflow runs can restore caches created in either the current branch or the default branch (usually main). If a workflow run is triggered for a pull request, it can also restore caches created in the base branch, including base branches of forked repositories." / "When a cache is created by a workflow run triggered on a pull request, the cache is created for the merge ref (refs/pull/.../merge). Because of this, the cache will have a limited scope and can only be restored by re-runs of the pull request." / "A cache created for a branch in a workflow run can be accessed and restored from another workflow run for the same repository and branch." | [Dependency caching reference — Restrictions for accessing a cache](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching) | 성립 — 본 저장소 실측(C3)과 정합 (§2.1) |

### 2.1 (f)와 본 저장소 실측의 정합

- publisher는 `workflow_run` 트리거 런이며, 그 시드 키들은 실측상 `ref: refs/heads/main`
  스코프에 기록된다(§3.2 orphan 2건 모두 main 스코프). 공식 규칙상 default-branch 스코프
  캐시는 같은 저장소/브랜치의 다른 런이 복원할 수 있으므로, mg lane이 publisher 키를
  exact-hit 소비한 실측(acceptance memo §2.1 C3: `Cache hit for: axiom-b-0abb24f3…` +
  `AXIOM_CACHE_B_VERIFY: RESULT OK — key exact-hit`)과 **정합** — 반증(역 사례):
  publisher가 `pull_request` 트리거였다면 캐시는 merge-ref 스코프로 기록되어 "can only
  be restored by re-runs of the pull request"(공식 문장)에 갇혀 mg lane 소비는
  성립하지 않는다. 즉 **default-branch 스코프 기록이 이 exact-hit의 문서적 설명**이다.
- merge-queue 브랜치 스코프 캐시도 목록에서 실측 관측됨
  (`refs/heads/gh-readonly-queue/main/pr-567-…` — 2026-10-08 전체 덤프).
- 공식 문서는 merge-queue lane의 캐시 scope를 별도 문장으로 정의하지 않는다 — **미정의
  표면**이지 문서↔동작 불일치가 아니다(§4.2 quirk 등록 요건 불충족).
- 플랫폼은 speculative stacking으로 생긴 무소비 키를 **억제하는 수단을 제공하지 않는다** —
  수명 관리는 eviction(총량 LRU + 7일)뿐. 이것이 위임 대상 그 자체다.

### 2.2 위임 전제 반박 검토 (fail-closed 요건)

- 반박 후보: "eviction 보장 부재" → 실사 결과 **반박 불성립**: 총량 상한 + last-access LRU +
  7일 미접근 제거가 모두 공식 문서로 보장된다((a)–(c)).
- 잔여로 남는 것 (보장 부재가 아니라 **유계 조건**): ① eviction은 저장 트리거 시점 집행
  ("If you exceed the limit, GitHub **will save the new cache** but will begin evicting…")이므로
  스냅샷 시점 총량이 상한 근처에 상주할 수 있다(§3.1 실측 10,504,847,430바이트 vs
  `max_cache_size_gb=10`) — **제거 시점·즉시성 SLA는 없다**(잔여 R12) ② 문서는 "GB"의
  밑수(십진/이진)를 정의하지 않는다 — 수치 해석의 유계이지 동작 불일치가 아니다 ③ "The
  cache eviction process may cause cache thrashing, where caches are created and deleted
  at a high frequency."(원문) — LRU 순환 압력은 플랫폼이 문서화한 성질로, 위임 시에도
  그대로 수용된다 ④ quota 초과는 **저장 실패를 유발하지 않는다**(save 후 evict) — 저장
  실패 모드는 rate-limit(200 uploads/min)·low-trust read-only·budget뿐이며, publisher는
  전부 `continue-on-error` + `[publish-fail] J3 fail-open` 정직화 로그
  (`ci-cache-publisher.yml:245,641,647`)로 방어된다.
- **bounded의 정의 (Red Team 교차 확인 교정 — 2026-10-08)**: 본 위임의 "bounded"는
  **두 상한의 합**으로만 서술된다 — (1) 무소비 7일 제거 ∧ (2) 용량 상한(기본 10GB,
  초과 시 LRU evict). "7일 내 사라진다"가 아니라 "7일 경과 엔트리는 제거 대상이 된다"까지가
  문장의 정확한 경계다 — 제거 시점 단정 금지(잔여 R12), 캡 증액 시 시간 상한만 잔존(잔여
  R13), `gh-readonly-queue/*` 스코프는 공식 명시 부재(잔여 R14).

## 3. 실측 (2026-10-08T15:00–15:10Z — 읽기 전용, gh CLI 네이티브 인증)

### 3.1 총량·분포

| 측정 | 값 | 명령 |
|---|---|---|
| 총 엔트리 | **130** | `gh api repos/Archright/Axiom/actions/caches?per_page=100 --jq .total_count` |
| 총 크기 | **10,504,847,430 bytes** (≈9.78 GiB) | `gh api repos/Archright/Axiom/actions/cache/usage` → `active_caches_size_in_bytes` / `active_caches_count: 130` |
| 구성 상한 | **`max_cache_size_gb: 10`** | `gh api repos/Archright/Axiom/actions/cache/storage-limit` |
| `axiom-a-` 접두사 | **83엔트리 / 7,651,931,955 B** (≈7.13 GiB) | 전체 덤프(2페이지) 집계 |
| `axiom-b-` 접두사 | **47엔트리 / 2,852,915,475 B** (≈2.66 GiB) | 동상 |
| 기타 접두사 | 0엔트리 | 동상 |

### 3.2 알려진 orphan 2건 (acceptance memo §3 잔여 실측 대상)

| 키 앞자리 | 원 PR | 크기 | created | last_accessed | ref |
|---|---|---|---|---|---|
| `0de7eb78` | #598 (C1) | **51,215,698 B** (48.84 MiB) | 2026-10-08T07:44:42.984941Z | **== created (접근 0)** | refs/heads/main |
| `7a49353e` | #603 (C2) | **51,323,577 B** (48.94 MiB) | 2026-10-08T09:34:35.895888Z | **== created (접근 0)** | refs/heads/main |

명령: `gh cache list --key axiom-b-0de7eb78 --json …` / `gh cache list --key axiom-b-7a49353e
--json …` — 각 **1엔트리** 존재 확증. `lastAccessedAt == createdAt` = 생성 후 소비 0 —
원인은 merge-queue speculative stacking(그룹 base ≠ main, Q2)으로 소비자 부재.

### 3.3 무접근 클래스 전체 (같은 클래스의 규모)

- `last_accessed_at == created_at` 엔트리: **19건 / 4,289,768,783 B (≈4.00 GiB — 총량의 ≈41%)**
  — `axiom-a-` 3건 / 3,231,809,921 B (≈3.01 GiB), `axiom-b-` 16건 / 1,057,958,862 B (≈0.99 GiB).
- 대조(접근이 창을 갱신하는 실측): 소비된 최신 키는 접근 갱신이 관측된다 — 예:
  `axiom-b-3e2ce831…` created 11:51:37Z → last_accessed 15:02:02Z,
  `axiom-a-Linux-8497f84b…ddc40ad6…` created 02:36:43Z → last_accessed 15:01:06Z.
- 판정: 무접근 클래스는 eviction 순서상 **최선두**(last access가 가장 오래됨 — 공식 규칙
  "in order of last access date, from oldest to most recent")이며, 두 상한(7일 미접근
  제거 ∧ 총량 초과 LRU)의 회수 대상이 된다 — **회수 시점은 플랫폼이 보장하지 않는다**
  (잔여 R12; bounded는 상한의 합이지 SLA가 아니다). orphan `0de7eb78`·`7a49353e`의
  회수도 이 경로로 수행되며, Axiom 측 개입(삭제 루틴·스케줄러)은 불필요하고 금지된다.
  참고(실측 소비 주기): 정상 경로의 시드→소비는 **2분 20초**(acceptance memo §2.1 —
  10:20:04 시드 → 10:22:24 HIT)로 7일 창의 약 1/4,320이다 — 무접근 상태로 남는 것은
  stacking(Q2)으로 소비자가 소멸한 경우에 한한다.

## 4. 판정

### 4.1 Follow-up #3 폐쇄

> **폐쇄**: "orphan 시드 위생: 소비 불가 예정 키의 시딩 억제 또는 만료 정책 — quota 한정
> 개선" — 제안된 두 수단(억제·자체 만료)은 모두 권위 누수/중복 control로 **금지** 확정(§1),
> quota 위생은 **GitHub Actions cache eviction에 위임**(§2 전 항목 성립, 반박 0건), 잔여는
> **bounded quota 낭비**로 `docs/spec/github_delegation_residuals.md` **R11**에 수용 기록.
> 정확성 무관(J3 — 캐시는 가속일 뿐 증거 아님; 판정 입력 0). 새 제어장치·워크플로·키
> 스킴·게이트·러너 스크립트 추가 **0**.

**보안 경계 (Red Team 교차 확인 — 2026-10-08)**: 본 위임은 cache-poisoning 방어를
대체하지 않는다 — **LRU eviction은 오염 방어가 아니다**(마지막 접근 순 정리일 뿐).
오염 방어는 기존 계층이 흡수한다: R3(`cache-mode: write` 옵트인 경고 + 트리 OID
content-addressing + 단일 최소 publisher) ∧ J3 §3.3 semantic provenance probe
(`git archive` 신뢰 트리 materialize + 복원 바이너리 4종 SourceCoherence 재실행 —
`ci_optimization_tcb_judgments.md:181`). 위임이 제거하는 것은 수명 관리(eviction)
의 중복 재구현뿐이다.

### 4.2 quirk 등록 없음 (근거 기록)

`docs/spec/gh_run_observation_quirks.md` Q4 후보 심사 결과 **등록 0건** — 문서↔실제 동작
불일치가 없다((a)–(f) 전 항목 정합). 남는 것은 (i) "GB" 밑수 미문서화, (ii) merge-queue lane
scope 미정의, (iii) usage 엔드포인트 ~5분 갱신 지연(문서 명시 사항) — 전부 **미정의/문서
명시 범위**이지 불일치가 아니므로 §0.5b 등록 요건 불충족. 관측 자체는 본 문서 §2.1–2.2에
기록했다.

## 5. 재현 명령

```bash
gh api repos/Archright/Axiom/actions/cache/usage
gh api repos/Archright/Axiom/actions/cache/storage-limit
gh api "repos/Archright/Axiom/actions/caches?per_page=100" --jq '.total_count'
gh cache list --key axiom-b-0de7eb78 --json key,sizeInBytes,createdAt,lastAccessedAt,ref
gh cache list --key axiom-b-7a49353e --json key,sizeInBytes,createdAt,lastAccessedAt,ref
```
