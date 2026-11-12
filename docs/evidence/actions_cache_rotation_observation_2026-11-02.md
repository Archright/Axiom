# GitHub Actions 캐시 키 회전 관측 — 판정: 문서화된 정상 동작 (2026-11-02)

> **종류**: 관측 보고서(판정 포함). GitHub Actions 캐시 엔트리의 "회전"(키 교체·엔트리
> 증가)이 이상 징후인지를 읽기 전용 관측으로 판정한 문서다. **캐시
> 삭제(DELETE)·정책 변경·코드·워크플로·게이트·핀·도구 변경 0건** — 기존 동작의
> 기록이며 신규 변경을 도입하지 않는다.
> **관측 규율**: 모든 관측은 GET-only·`gh` 네이티브 인증(AGENTS.md §2.4)이다. 캐시
> 목록 전수·워크플로 런 목록·워크플로 원문(raw)만 조회했고, 키 공식 검산은 로컬
> 결정적 재계산(sha256sum — materialize한 트리 2종, 임시 파일은 /tmp 한정·사용 후
> 제거)으로 수행했다(부록 B).
> **증거 규율**: §1이 모든 주장을 **기계 확인 / 추정·부분 일치 / UNKNOWN** 3단으로
> 분류하고 본문에도 단위 라벨을 병기한다. **측정 사실(§2–§4)과 원인 판정(§6)은
> 분리 기록한다.**
> **Date**: 2026-11-02 · **Branch**: docs-only PR(`docs/evidence/` 착지 — 관측 종결 문서 5건 동반: 본 문서·mint tail 분해(`node24_mint_tail_decomposition_2026-11-02.md`)·SLO 상태 스냅샷(`slo_status_snapshot_2026-11-02.md`)·교차-venue 종결(`cross_venue_b_reuse_closure_2026-11-02.md`)·판정창 사전등록(`slo_judgment_window_prereg_2026-11-02.md`)) · **Scope**: 본 문서
> 1건(`docs/evidence/*.md`) — 코드·워크플로·게이트·핀·도구 변경 0건. docs-only
> 비행 → trust surface 아님(정상 merge queue 경로).
> **권위**: 본 문서는 Reporter다 — GitHub merge authority(required checks·merge
> queue·MERGE commit)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> 어떤 게이트도 본 문서의 값을 소비하지 않는다.
> **관측 창**: 2026-10-27 ~ 2026-11-02T09:53Z(캐시·런 스냅샷 기준 시각
> 2026-11-02T09:53Z) · **베이스**: `origin/main =
> 4c19fa9b6a98a0ec71085729e0b40c3e174f6a35`(작성 시점 판독값) · **판정자**: 본
> 관측 세션(명령→관측 기록은 부록 B).

---

## §0. 판정 요약

**판정: (i) 문서화된 정상 동작(verified normal behavior) — 이상 징후 아님.**

키 회전은 GitHub 공식 캐시 규칙(exact-match save-skip·branch 스코프·10GiB/LRU·
7일 미접근 축출 — §5)과 저장소 자체 키 공식(`.github/actions/setup-axiom-toolchain/action.yml`
keygen step — A키 script_hash·B키 내용 주소화, §3)이 유도하는 결과다. 회전의 모든
성분(identity·recipe·script_hash·a_fp)을 특정 커밋·특정 런까지 추적했으며, 설명
없이 변한 성분은 0건이다. 비정상 신호는 발견되지 않았다.

---

## §1. 증거 수준 분류 (기계 확인 / 추정·부분 일치 / UNKNOWN)

| 수준 | 정의 | 해당 주장(§ 참조) |
|---|---|---|
| **기계 확인** | GitHub API GET 응답값 또는 결정적 재계산(sha256sum)이 그대로 보여주는 값 — 해석이 개입하지 않는다 | 캐시 전수 115건·6.71GiB·엔트리별 key/created_at/last_accessed_at/ref(부록 A = API 응답의 전문 투영, §2); 키 문자열 구조 `axiom-b-<클로저 digest 40hex>-<recipe 32hex><a_fp 32hex>`(관측 키 파싱 × action.yml 공식 대조, §3.3); script_hash 재계산 2 트리 일치(7483645e…/c3b6ac31…, §3.2); a_fp 재계산 2 라인지 일치(fec503b1…/fb5edece…, §3.3); **트리 498c5570 클로저 digest 재계산 = `73dfd535e2fe36919e194f6a31b9534aff239811` = 최신 B키 identity 일치(기계 확인됨, §3.3)**; B 12엔트리 = 키 12종 전부 상이·스코프 전부 main(키당 정확히 1엔트리, §2·§4.1); publisher 단일 writer·게이트 완료 트리거(workflow 원문 GET — `ci-cache-publisher.yml:181-184`, §3.1); org 워크플로에 actions/cache step 0건(raw GET, §3.1); 런 상관(런 ID·created_at·conclusion, §4) |
| **추정·부분 일치** | 관측값 + 문서화 규칙의 조합이며 재계산으로 완전히 닫히지 않는 것 | "정체성 3종 × recipe 2종" 가설의 **부분 일치** 분 — recipe "2종"은 A계열 script_hash 구/신 세대 공존에만 성립, B는 12개 distinct(§3.4); 회전 빈도 "2–8회/일 = 랜딩(착지) 구동"(타임라인 상관의 원인 독해, §4.4); 개별 엔트리의 저장 job 1:1 귀속(job 로그 미조회, §6); 구 세대 B키의 예상 축출 시각(문서화 7일 규칙 × 관측 last_accessed의 적용 계산, §5-3) |
| **UNKNOWN** | 관측하지 않아 기록할 수 없는 것 | 엔트리별 "어느 job이 save했는가"의 1:1 귀속(예: 2026-11-02T07:36:51 구-라인지 axiom-a on merge-queue ref pr-1189 = 게이트 base-트리 워크스페이스 가설) — 공식·타이밍·트리 내용이 모두 일치하는 신뢰도 높은 추정이며 판정에 영향 없음(§6); B3 트리거 축소(PR #1213, 2026-11-02T07:49:34Z 착지) 이후 publisher 정상 발화율(관측 창은 축소 후 2시간만 포함, §4.1) |

---

## §2. 측정 — 캐시 전수 나열 (115개, GET only)

출처: `GET /repos/Archright/Axiom/actions/caches?per_page=100` (page 1 = 100건,
page 2 = 15건, `total_count: 115`). [기계 확인]

### 2.1 요약 통계 (2026-11-02T09:53Z 기준)

| 구분 | entries | 크기 |
|---|---|---|
| **전체** | **115** | **6.71 GiB** (저장소 한도 10GiB의 67%) |
| 정체성 axiom-a-full (툴체인 ~1.1–1.2GiB) | 4 | 4.387 GiB |
| 정체성 axiom-a-rt (z3/jq, ~14.1MiB) | 99 | 1.301 GiB |
| 정체성 axiom-b (빌드 산출물, ~91MiB) | 12 | 1.025 GiB |

ref 스코프별: main 14개(3.204GiB) / merge-queue(gh-readonly-queue) 53개(1.845GiB)
/ pr-merge(refs/pull/N/merge) 48개(1.664GiB). [기계 확인]

**서로 다른 키 문자열(distinct key strings)은 16개**: axiom-a-full 2종 +
axiom-a-rt 2종 + axiom-b 12종. 나머지 99개 항목은 동일 키 문자열의 **브랜치
스코프별 복제 항목**이다(§4.3). [기계 확인]

axiom-b 12엔트리는 키 문자열이 12개 전부 서로 다르고 스코프가 전부 main이다 —
**키당 정확히 1엔트리**(신규 키가 main 스코프에 1회 발행되는 형태가 관측값으로
직접 보임; §4.1의 단일 writer·exact-match skip과 정합). [기계 확인]

### 2.2 전수 목록

부록 A에 115건 전체(created_at·last_accessed_at·key·size·ref)를 수록했다(API
응답의 전문 투영).

---

## §3. 측정 — 키 조성(composition) 분석과 재계산 검산

### 3.1 키 생성처 — org 워크플로우가 아니다 [기계 확인]

키 생성처는 **org 저장소 워크플로우가 아니다**. `Archright/.github`의
admission-gate-v2.yml·landing-integrity.yml(workflow_sha 7eaa9624 핀, GET raw로
확인)에는 **actions/cache 사용 step이 전혀 없다**. 캐시 생성은 Axiom 저장소 자체의:

- `.github/actions/setup-axiom-toolchain/action.yml` — keygen step(A키·B키 공식의 SSOT)
- `.github/workflows/ci-cache-publisher.yml` — B 캐시의 **단일 writer**(workflow_run
  트리거 `workflows: ['admission-gate', 'admission-gate-v2'], types: [completed]`
  = **게이트 완료 시 발화** — `ci-cache-publisher.yml:181-184`; action.yml 헤더의
  "ONE-WRITER only" 계약). 신규 키마다 main(default branch) 스코프에 1회 발행한다
  (§2의 "B 12엔트리 = 키 12종·전부 main"이 그 기계 확인된 증거다).
- 그 밖의 setup-axiom-toolchain 호출 워크플로우 — A-layer save는 lock-complete
  런이면 무조건; B는 전 caller가 `cache-save-enabled: 'false'` = restore-only
  reader(`action.yml:99-112`)

에서 일어난다. org 워크플로우는 callee를
`Archright/Axiom/.github/{actions,workflows}/...@498c5570`으로 핀해서 호출한다.

참고: publisher 트리거는 관측 창 중반(2026-11-02T07:49:34Z, PR #1213)에
gate-완료 전용 화이트리스트로 축소 착지됐다(`ci_cost_b2_selection_b4_prereg_2026-11-02.md`
§3.1의 B3 후보). 관측 창 대부분의 발화 통계(§4.1의 424런)는 축소 이전
전-워크플로 완료 연쇄 시절 값이다.

### 3.2 A키 공식 (`setup-axiom-toolchain/action.yml` keygen step)

```
a_key = "axiom-a[-rt]-" + RUNNER_OS + "-" + gcc_fp + "-" + glibc_fp + "-" + script_hash
  gcc_fp      = sha256("gcc --version" 출력)[0:16]
  glibc_fp    = sha256("ldd --version" 첫 줄)[0:16]
  script_hash = (sha256sum(.github/actions/setup-axiom-toolchain/action.yml,
               nimble.lock) | sha256sum)[0:40]                      (action.yml:194)
  접두 "axiom-a-rt-" = provision-scope=runtime (mint job; ~/.local/bin만)
                                                             (action.yml:195-204)
```

**실측 검증(종단)** — 로컬 git에서 두 트리를 materialize해 동일 공식 재계산
[기계 확인]:

| 트리 | 재계산 script_hash | 관측된 키 접미사 |
|---|---|---|
| `8054c2e4` (cutover 이전 main — Merge PR #1212, 06:58:49Z) | `7483645eecae53da48680cf4eea49ee08147da6e` | **일치** (구 라인지) |
| `498c5570` (PR #1189 node24 cutover 착지 트리 — 네이티브 MERGE) | `c3b6ac315024dc1aba8b1b6835c3e013a2c969d4` | **일치** (신 라인지) |

즉 A키의 "recipe 2종" 병존(7483645e… vs c3b6ac31…)은 **action.yml 변경 1건(node24
generation cutover — 전환 커밋 c24e812a3, PR #1189, main 흡수 push
2026-11-02T07:46:01Z; action.yml +3/-3)이 만든 구/신 세대 공존**이다. nimble.lock은
2026-07-23 이후 불변(git log) → script_hash 변동의 유일한 최근 원인은 action.yml이다.
gcc_fp(8497f84b…)/glibc_fp(e881beab…)는 관측 창 내 불변(이미지 롤 없음;
ImageOS/ImageVersion 라벨은 2026-10-01 LABEL_NOISE 실측으로 키에서 제거됨 —
false-MISS 방지, `action.yml:41-53`). [기계 확인]

### 3.3 B키 공식 (같은 keygen step + ci-cache-publisher)

```
b_key = "axiom-b-" + b_identity + "-" + recipe_hash + a_fp
      = "axiom-b-<클로저 digest 40hex>-<recipe 32hex><a_fp 32hex>"
  b_identity  = 컴파일 입력 클로저 digest[0:40] — src/(generated 제외) 전 파일 bytes
                + staticRead 컴파일 입력 17종 bytes + 정책문서 nonempty 술어 3종
                + SPEC 셀 존재 술어 3종 — 전부 git archive(캐시-build-source 트리)에서
                유도                                                   (action.yml:205-292)
  recipe_hash = (sha256sum(Makefile, config.nims, config/effects.nims,
               src/gate/config.nims) | sha256sum)[0:32]
  a_fp        = sha256(a_key)[0:32]  (A 변경은 B를 구조적으로 무효화)
```

**실측 검증(종단)** [기계 확인]:

- a_fp: `sha256("axiom-a-Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4")[0:32]`
  = `fec503b1cd6570e7737ce3968b7e9d62` → 최신 B키 접미사와 **일치**. 구
  라인지(7483645e…) → `fb5edece29a56159aacc860ebed2bf2e` → 구 B키 접미사와 **일치**.
- b_identity: 트리 `498c5570`을 action.yml의 클로저 공식 그대로 로컬 재계산 →
  **`73dfd535e2fe36919e194f6a31b9534aff239811`** → 최신 B키(2026-11-02T07:34:29,
  main)의 identity 성분과 **일치 — 기계 확인됨**.

참고: "8c46c4ea로 식별되는 빌드 입력"(외부 메모)은 merge-queue 커밋 SHA 관점
식별자고, B키가 담는 identity는 그 **트리 내용의 클로저 digest**다(현재 활성 B키 =
73dfd535…, node24 cutover 트리의 digest). 병합 큐의 합성 트리와 네이티브 MERGE
커밋(498c5570 — 큐 dequeue 시점 2026-11-02T07:34:23Z 생성)은 트리 내용이 동일하므로
identity도 동일 값이다. docs-only·워크플로 전용 커밋(PR #1213 등 — 컴파일 클로저
밖)은 클로저가 불변이므로 B키가 전진하지 않는다(설계 주석 명시, `action.yml:69-77`).

### 3.4 "정체성 3종 × recipe 2종" 가설 검증

| 가설 | 실측 | 판정 | 증거 수준 |
|---|---|---|---|
| 정체성 3종 | axiom-a-full / axiom-a-rt / axiom-b 프리픽스 3종 관측 | **일치** | 기계 확인 |
| × recipe 2종 | axiom-a-full 2종(7483645e·c3b6ac31 라인지), axiom-a-rt 2종 — 성립. **그러나 axiom-b는 2종이 아니라 12개 서로 다른 키 문자열**(identity·recipe·a_fp 조합마다 신규) | **부분 일치** — "2종"은 A계열의 script_hash 구/신 세대 공존에만 해당; B는 착지마다 identity가 전진하는 별도 차원 | 부분 일치(§1) |

과거 관측 "6개 키 병존"은 main 스코프의 당시 live 세트(구/신 A 라인지 + B 세대)와
부합하며, 병존 자체는 정상이다(구 키는 즉시 삭제되지 않음 — §5-3 eviction).

---

## §4. 측정 — 회전 타임라인 상관 (cache.created_at × workflow runs)

`GET /repos/Archright/Axiom/actions/runs`(created 필터 창 조회, GET만). 상관
배치 자체는 측정이고, 원인 독해는 §6으로 분리한다.

### 4.1 B키 회전 — writer: ci-cache-publisher (workflow_run → default branch = main 스코프)

| B키 생성(main) | 생성 런(근거) | 내용 |
|---|---|---|
| 2026-11-02T07:34:29 `axiom-b-73dfd535…\|41ae9d00\|fec503b1` | publisher run **41407134662**(created 07:34:09, **success**; head 8054c2e4 = 당시 main HEAD) | node24 cutover 트리의 클로저 digest(네이티브 MERGE 498c5570 = 큐 dequeue 07:34:23Z 생성, 트리 내용 동일 — §3.3) + recipe(41ae9d00) + 신 a_fp. 런 생성 +20s 후 캐시 생성 — 직접 상관 |
| 2026-11-02T04:02:06 `axiom-b-cca0aa7b…\|41ae9d00\|fb5edece` | 동일 publisher 체인 | identity 전진 1회(recipe·a_fp 불변) |
| 2026-11-01T17:43:00 `axiom-b-72855407…\|41ae9d00\|fb5edece` | 동일 publisher 체인 | **recipe 전환**(bf3b65a9→41ae9d00): recipe 파일 4종은 PR #1173 착지(2e1083ed8, 2026-11-01T17:45:51Z)로 변경 — 큐 합성 트리 기준 첫 publisher 사이클(17:43)이 신 recipe로 재키, 착지와 직접 상관 |
| 2026-11-01T21:15/18:36/15:45/15:33/15:31/09:59/09:25 | publisher 각 사이클 | identity 전진 잔여 5회 + recipe 전환 2회(7c8e1b67→dd33cd01 09:59, →bf3b65a9 15:31) + a_fp 전환 1회(09:25 — 같은 분의 A키 전환(구 라인지 최종 세대 7483645e, §4.2)과 동시) |

publisher는 하루 수백 번 발화(관측 창 25h에 424런)하지만 **단일-flight
사전조회(lookup-only)로 동일 키 존재 시 save를 생략**하므로, 실제 신규 B 엔트리는
identity/recipe/a_fp가 바뀔 때만 1회 생성된다(단일 writer 설계 + §5-1의 exact-match
skip 공식 동작). 참고: 이 424런은 트리거가 전-워크플로 완료 연쇄였던 축소 이전
값이다(§3.1 참고 — gate-완료 전용 화이트리스트 축소는 2026-11-02T07:49:34Z 착지).

### 4.2 A키 회전 — writer: main 브랜치에서 setup-axiom-toolchain을 수행하는 런 (A save는 무조건, lock-complete 가드)

| A키 생성 | 생성 런(근거) | 내용 |
|---|---|---|
| 2026-11-02T07:48:02 `axiom-a-Linux-…-c3b6ac31…` (main, 1161.3MiB) | **push 498c5570 (07:46:01)** → axiom-operational-slice push 런 41408413331 (created 07:46:02) | main이 PR #1189(node24 cutover)를 흡수 → 신 script_hash → MISS → 설치 후 save. push +2m — 직접 상관 |
| 2026-11-02T01:03:44 동일 신 라인지 (refs/pull/1189/merge, 1070.9MiB) | PR #1189 게이트 런(merge ref 스코프) | PR 자체에 c24e812a3 포함 → merge ref에서 먼저 신 라인지 |
| 2026-11-01T09:25:06 `axiom-a-Linux-…-7483645e…` (main, 1070.3MiB) | 당일 게이트/슬라이스 체인 | 구 라인지 최종 세대 |

### 4.3 axiom-a-rt 다수 항목 — 회전이 아니라 스코프 복제

99개 rt 항목(47 pr-merge + 52 merge-queue)은 **키 문자열이 라인지별로
동일**(7483645e/c3b6ac31 각 1종). GitHub 캐시는 key+version+**branch**로
스코프되므로(§5-4), PR merge ref와 merge-queue ref마다 별도 엔트리로 재저장된다.
약 18h에 99개(≈130개/일, ≈1.8GiB/일 유입) — 캐시 목록에서 "계속 새 항목이
생기는" 착시의 주체지만 키 회전과는 다른 현상이다. 13.5MiB로 경미하고 7일/LRU
eviction으로 자정리된다. → **branch 스코프 격리 복제 = 정책 준수 동작**(§6-4).

### 4.4 "하루 약 3회" 재검증

main 스코프에서 관측자에게 보이는 "현재 키" 교체(=신규 키 문자열 등장) 횟수
[기계 확인 — 부록 A 집계]:

- 2026-11-01: 신규 B키 8건(성분 기준 — identity 전진 6회·recipe 전환
  3회(dd33cd01·bf3b65a9·41ae9d00)·a_fp 1회; 하나의 신규 키가 복수 성분 전환을
  동반할 수 있다) ≈ **8회**
- 2026-11-02 (00:00–09:53): B 2건(04:02 identity·07:34 identity+a_fp) + A
  script_hash 전환 1건(07:48) = **3회**

→ "약 3회/일"은 관측 창의 머지 빈도에서 **성립하는 수준(2–8회/일)**이며, 회전은
시간 구동이 아니라 **랜딩(착지) 구동**이다: 컴파일 입력을 건드리는 머지가 많으면
회전도 많다. 10-27~10-28에는 2일 1회 수준(머지 적음) — 빈도 자체의 변동은 정상
범위다. [원인 독해 — 판정은 §6]

---

## §5. 공식 문서 근거 (Context7 `/actions/cache`)

1. **exact match 시 save 생략**: restore이 primary key와 동일한 키를 이미 복원했다면
   save post-step은 no-op — "Cache hit occurred on the primary key …, not saving
   cache." (`src/saveImpl.ts`, isExactKeyMatch). → publisher의 lookup-only
   사전조회·단일 writer 설계와 결합해, 같은 키 재발행이 엔트리 홍수를 만들지 않는다.
2. **restore-keys**: key 미스 시 접두 프리폴백 매칭(본 저장소는 A/B 모두
   restore-keys 없이 exact-key only로 운영 — action.yml 주석 명시,
   `action.yml:86-88`).
3. **eviction**: 저장소 캐시 총량 10GiB 한도, 초과 시 **last-accessed 기준 LRU
   축출**, **7일 미접근 캐시도 축출**. → 구 세대 B키 2건(2026-10-27T08:11 물건 —
   최종 접근 10-27T17:27Z / 2026-10-28T09:44 물건 — 최종 접근 10-30T08:02Z)은
   문서화 규칙(최종 접근 +7일)의 적용 계산상 각각 2026-11-03T17:27Z경·
   2026-11-06T08:02Z경 플랫폼이 자동 정리한다 — 별도 조치 불필요(전량 보존 정책과
   충돌 없음: 플랫폼 자정리). [추정·부분 일치 — 문서화 규칙 × 관측 last_accessed의
   적용 계산(§1)]
4. **스코프**: 캐시는 **key + version + branch로 스코프**; 기본 브랜치 캐시는 다른
   브랜치가 소비 가능; fork PR은 read-only. → §4.3의 rt 다수 항목이 문서화된 branch
   isolation의 직접 결과다. version은 path 목록에서 유도되므로 rt(1경로)와
   full(4경로)은 같은 키 문자열이어도 교차 매칭되지 않음(저장소 측 실측 기록:
   T1/T2 version 불일치 복원 실패 사례가 ci-cache-publisher.yml 주석에 문서화).

---

## §6. 판정 (원인 종합 — §2–§4의 측정 사실과 분리)

**(i) 문서화된 정상 동작** — 회전의 모든 성분이 공식 규칙 + 저장소 키 공식으로
설명·검증됨:

1. B키 회전: 키가 내용 주소화(클로저 digest·recipe·a_fp)되어 있어 **컴파일 입력을
   바꾸는 착지마다 새 키**가 발행됨 — 설계 의도(docs-only 커밋은 키 불변)대로 동작.
   실측: 트리 498c5570 클로저 digest 재계산 = 73dfd535… = 최신 B키 identity
   일치 [기계 확인].
2. A키 회전: script_hash 성분이 action.yml+nimble.lock에서 유도되어 **툴체인
   프로비저닝 레시피 변경 시 1회 전환** — 실측: node24 cutover(PR #1189, 전환
   커밋 c24e812a3) 양 트리 재계산 일치(7483645e→c3b6ac31) [기계 확인].
3. 구 키 병존: 회전이 구 키를 파괴하지 않음 — 문서화된 7일/LRU eviction이 정리
   (§5-3의 적용 계산 시각). 정상.
4. axiom-a-rt 다수 항목: 동일 키의 브랜치 스코프 복제 — 문서화된 branch isolation.
   **정책 준수 동작**. 정상.
5. 비정상 후보 전부 기각: 키 성분 중 설명 없이 변한 것 없음(gcc_fp·glibc_fp
   불변, identity·recipe·script_hash 변동은 각각 특정 커밋으로 추적됨).

**UNKNOWN 남는 것**: 개별 엔트리의 "어느 job이 save했는가"의 1:1 귀속(예:
2026-11-02T07:36:51 구-라인지 axiom-a on queue ref pr-1189 = 게이트 base-트리
워크스페이스 가설)은 job 로그 미조회로 추정 단계다 — 다만 공식·타이밍·트리 내용이
모두 일치해 신뢰도 높은 추정이며, 판정에 영향 없다.

---

*본 문서는 읽기 전용 관측의 기록이다 — 캐시·정책·코드에 대한 변경을 도입하지
않으며, GitHub merge authority를 대체하지 않는다. 측정 원본은 부록 A의 API 응답
투영과 부록 B의 GET 명령이며, 본 문서는 그 투영이다.*

---

## 부록 A. 캐시 전수 목록 (115건)

| created_at (UTC) | last_accessed_at | key (접두 축약: a=full/rt, b=axiom-b; identity\|recipe+afp) | MiB | 스코프 |
|---|---|---|---|---|
| 2026-11-02T09:50:27.681350Z | 2026-11-02T09:51:00.252928Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | merge-queue |
| 2026-11-02T09:41:00.670341Z | 2026-11-02T09:41:24.250004Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | merge-queue |
| 2026-11-02T09:34:48.503571Z | 2026-11-02T09:35:20.160401Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | merge-queue |
| 2026-11-02T09:34:40.650760Z | 2026-11-02T09:37:07.239309Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | pr-merge |
| 2026-11-02T09:26:24.547298Z | 2026-11-02T09:27:07.832059Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | pr-merge |
| 2026-11-02T09:18:17.286839Z | 2026-11-02T09:20:17.651514Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | pr-merge |
| 2026-11-02T09:03:59.826437Z | 2026-11-02T09:04:21.809719Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | merge-queue |
| 2026-11-02T08:49:14.025008Z | 2026-11-02T08:50:04.984711Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | pr-merge |
| 2026-11-02T08:46:33.275292Z | 2026-11-02T08:47:04.689682Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | merge-queue |
| 2026-11-02T08:33:09.861778Z | 2026-11-02T08:33:22.603104Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | pr-merge |
| 2026-11-02T07:56:26.741847Z | 2026-11-02T07:56:46.150993Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 13.5 | merge-queue |
| 2026-11-02T07:48:02.135097Z | 2026-11-02T09:52:20.338417Z | a\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 1161.3 | main |
| 2026-11-02T07:47:14.647631Z | 2026-11-02T07:47:26.032282Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T07:44:34.145554Z | 2026-11-02T07:44:58.197015Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T07:36:51.617401Z | 2026-11-02T07:39:40.271558Z | a\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 1189.7 | merge-queue |
| 2026-11-02T07:34:29.934836Z | 2026-11-02T09:53:20.897697Z | b\|73dfd535e2fe36919e194f6a31b9534aff239811-41ae9d00a404ca743cd4050a788817ecfec503b1cd6570e7737ce3968b7e9d62 | 87.6 | main |
| 2026-11-02T07:06:47.334298Z | 2026-11-02T07:07:05.686481Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T07:05:27.187483Z | 2026-11-02T07:05:45.186925Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T06:59:27.349784Z | 2026-11-02T06:59:49.759237Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T06:54:29.063111Z | 2026-11-02T06:54:40.027951Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T06:53:12.921508Z | 2026-11-02T06:53:30.244441Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T06:19:24.820338Z | 2026-11-02T06:19:42.892304Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T06:19:00.100575Z | 2026-11-02T06:19:18.927349Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T06:17:53.263201Z | 2026-11-02T06:18:07.760309Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T06:10:04.706342Z | 2026-11-02T06:10:26.618877Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T06:09:00.095868Z | 2026-11-02T06:09:19.091943Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T05:09:24.926739Z | 2026-11-02T05:09:38.300828Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T04:55:30.242757Z | 2026-11-02T04:59:25.603914Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T04:55:03.680022Z | 2026-11-02T06:46:43.942693Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T04:53:54.311611Z | 2026-11-02T04:54:19.777417Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T04:52:46.973041Z | 2026-11-02T04:53:04.324171Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T04:38:57.819703Z | 2026-11-02T06:55:23.193720Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T04:37:27.171758Z | 2026-11-02T06:37:56.357134Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T04:15:55.406797Z | 2026-11-02T04:16:13.751191Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T04:08:27.856602Z | 2026-11-02T04:08:46.696764Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T04:02:06.074522Z | 2026-11-02T07:48:24.493286Z | b\|cca0aa7b85b22bcaaf0c03614c3b3c8afd9e410a-41ae9d00a404ca743cd4050a788817ecfb5edece29a56159aacc860ebed2bf2e | 87.6 | main |
| 2026-11-02T03:59:16.918386Z | 2026-11-02T03:59:33.790569Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T03:56:55.143747Z | 2026-11-02T04:01:20.554244Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T03:50:26.008146Z | 2026-11-02T03:50:43.298452Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T03:43:01.104443Z | 2026-11-02T03:44:40.201235Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T03:37:35.038762Z | 2026-11-02T03:37:52.923234Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T03:29:36.978695Z | 2026-11-02T03:29:57.898965Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T03:21:33.628476Z | 2026-11-02T03:37:55.431804Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T03:17:53.958137Z | 2026-11-02T03:18:25.841694Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T03:17:46.893935Z | 2026-11-02T03:57:30.070732Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T03:15:49.193528Z | 2026-11-02T03:16:06.694334Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T03:13:15.829212Z | 2026-11-02T03:25:21.879428Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T03:10:46.414061Z | 2026-11-02T03:11:04.598133Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T03:07:06.738416Z | 2026-11-02T03:07:27.148249Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T03:00:43.852344Z | 2026-11-02T03:01:04.086746Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T02:56:47.260639Z | 2026-11-02T02:57:04.027776Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T02:56:10.640451Z | 2026-11-02T02:56:50.256970Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T02:50:15.436864Z | 2026-11-02T02:51:27.688235Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T02:50:14.627356Z | 2026-11-02T02:51:50.591673Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T02:49:32.067845Z | 2026-11-02T02:50:48.012195Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T02:45:24.362659Z | 2026-11-02T02:46:57.768335Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T02:39:23.447635Z | 2026-11-02T02:39:41.676284Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T02:24:49.480052Z | 2026-11-02T02:27:35.925608Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T02:02:20.956142Z | 2026-11-02T02:02:37.496014Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T01:57:20.085681Z | 2026-11-02T01:57:40.529355Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T01:49:16.651088Z | 2026-11-02T01:49:31.550801Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T01:46:36.172036Z | 2026-11-02T01:47:20.495303Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T01:41:03.608883Z | 2026-11-02T01:41:22.271787Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T01:38:03.928268Z | 2026-11-02T01:38:27.663453Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T01:33:11.639160Z | 2026-11-02T01:33:33.406938Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T01:28:07.700852Z | 2026-11-02T01:28:27.056454Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T01:26:35.752185Z | 2026-11-02T01:26:49.162326Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T01:22:34.013068Z | 2026-11-02T01:22:56.381606Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T01:15:13.260444Z | 2026-11-02T01:15:32.797195Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T01:13:39.569479Z | 2026-11-02T01:13:57.347452Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T01:08:10.356442Z | 2026-11-02T01:25:59.713418Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T01:04:47.856825Z | 2026-11-02T07:33:26.406573Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T01:03:44.071126Z | 2026-11-02T07:27:12.643293Z | a\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-c3b6ac315024dc1aba8b1b6835c3e013a2c969d4 | 1070.9 | pr-merge |
| 2026-11-02T01:02:23.098681Z | 2026-11-02T01:02:42.689347Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T00:59:14.603608Z | 2026-11-02T01:00:05.292906Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T00:58:21.082698Z | 2026-11-02T00:58:37.253802Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T00:57:15.861982Z | 2026-11-02T00:58:19.966784Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T00:51:57.848698Z | 2026-11-02T00:52:12.996915Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T00:50:51.626197Z | 2026-11-02T00:51:09.725095Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T00:50:00.492334Z | 2026-11-02T00:50:17.185689Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T00:44:58.234398Z | 2026-11-02T00:45:53.005935Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T00:42:12.263719Z | 2026-11-02T01:14:28.071236Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T00:35:05.426702Z | 2026-11-02T00:36:47.971703Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T00:34:49.993498Z | 2026-11-02T00:35:49.525541Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T00:25:44.739439Z | 2026-11-02T00:26:02.728135Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T00:21:19.663559Z | 2026-11-02T00:21:36.747276Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-02T00:10:02.504367Z | 2026-11-02T00:11:16.850100Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-02T00:06:28.400417Z | 2026-11-02T00:08:58.732447Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T22:41:58.744587Z | 2026-11-01T22:42:19.796583Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-01T22:26:09.493352Z | 2026-11-01T22:27:30.650401Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T22:09:37.236678Z | 2026-11-01T22:09:57.416938Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-01T21:53:10.935606Z | 2026-11-01T21:54:54.823182Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T21:24:42.510799Z | 2026-11-01T21:25:00.730576Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-01T21:15:01.474630Z | 2026-11-02T04:19:07.040032Z | b\|067ba65a6b6e24ab2756af39055a7aba12c48e74-41ae9d00a404ca743cd4050a788817ecfb5edece29a56159aacc860ebed2bf2e | 87.6 | main |
| 2026-11-01T21:09:57.743841Z | 2026-11-01T21:14:10.866465Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T19:45:19.071999Z | 2026-11-01T19:45:39.966396Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-01T19:29:38.193328Z | 2026-11-01T19:30:33.726582Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T19:01:01.096843Z | 2026-11-01T19:01:19.693905Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-01T18:36:21.545571Z | 2026-11-01T21:27:05.483850Z | b\|674668db780ee81526da7024aa46a2c6199d2632-41ae9d00a404ca743cd4050a788817ecfb5edece29a56159aacc860ebed2bf2e | 87.6 | main |
| 2026-11-01T18:31:39.262884Z | 2026-11-01T18:31:56.802754Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-01T18:31:24.020897Z | 2026-11-01T18:44:23.120839Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T18:15:37.475573Z | 2026-11-01T18:16:33.192302Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T17:54:42.986991Z | 2026-11-01T17:55:03.904280Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-01T17:43:00.075187Z | 2026-11-01T19:03:23.385959Z | b\|7285540757f279501b6ae34851fd2ef339722667-41ae9d00a404ca743cd4050a788817ecfb5edece29a56159aacc860ebed2bf2e | 87.5 | main |
| 2026-11-01T17:38:08.954672Z | 2026-11-01T17:42:16.407655Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T16:27:22.942612Z | 2026-11-01T16:27:38.691954Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | merge-queue |
| 2026-11-01T16:12:22.988816Z | 2026-11-01T16:13:31.734535Z | rt\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 13.5 | pr-merge |
| 2026-11-01T15:45:11.938554Z | 2026-11-01T17:57:45.336704Z | b\|558f367dca983deae6eea90e5be5883e065c9080-bf3b65a9883dc93f9287c646b0424a77fb5edece29a56159aacc860ebed2bf2e | 87.3 | main |
| 2026-11-01T15:33:31.984200Z | 2026-11-01T15:33:31.984200Z | b\|558f367dca983deae6eea90e5be5883e065c9080-dd33cd01c84206876dac371e9832261ffb5edece29a56159aacc860ebed2bf2e | 87.3 | main |
| 2026-11-01T15:31:30.476937Z | 2026-11-01T15:46:36.344164Z | b\|3de0c2c6c030a9cdb035868ae4a620151a52a5a8-bf3b65a9883dc93f9287c646b0424a77fb5edece29a56159aacc860ebed2bf2e | 87.2 | main |
| 2026-11-01T09:59:09.569210Z | 2026-11-01T15:46:58.750205Z | b\|3de0c2c6c030a9cdb035868ae4a620151a52a5a8-dd33cd01c84206876dac371e9832261ffb5edece29a56159aacc860ebed2bf2e | 87.2 | main |
| 2026-11-01T09:25:21.663117Z | 2026-11-01T10:13:48.258882Z | b\|f1fd711fbac14a6f405467b9a41a1b99271100dc-7c8e1b67829b9ac5feeeccc7ce0f0fe1fb5edece29a56159aacc860ebed2bf2e | 87.8 | main |
| 2026-11-01T09:25:06.433515Z | 2026-11-02T07:47:29.226912Z | a\|Linux-8497f84b2b8334c4-e881beabc91bfbd3-7483645eecae53da48680cf4eea49ee08147da6e | 1070.3 | main |
| 2026-10-28T09:44:46.593267Z | 2026-10-30T08:02:53.349419Z | b\|0c92d1dd739390becaf58b86b310a4356701458e-7c8e1b67829b9ac5feeeccc7ce0f0fe17a6b36527a048945a9b40d73684582f5 | 87.8 | main |
| 2026-10-27T08:11:03.967093Z | 2026-10-27T17:27:05.470957Z | b\|0c92d1dd739390becaf58b86b310a4356701458e-7c8e1b67829b9ac5feeeccc7ce0f0fe1c7e1ba34580a06b99f1428f9dec34b7e | 87.1 | main |

총 115건 = axiom-a-full 4 · axiom-a-rt 99 · axiom-b 12. rt 99건 중 키 문자열은 라인지 2종뿐(나머지 차이는 스코프/ref).


## 부록 B. 사용 명령 기록 (전부 GET)

```
gh api "repos/Archright/Axiom/actions/caches?per_page=100&page=1"        # 전수 100건
gh api "repos/Archright/Axiom/actions/caches?per_page=100&page=2"        # 잔여 15건 (total_count=115)
gh api -H "Accept: application/vnd.github.raw" \
  "repos/Archright/.github/contents/.github/workflows/admission-gate-v2.yml?ref=7eaa9624"   # → /tmp
gh api -H "Accept: application/vnd.github.raw" \
  "repos/Archright/.github/contents/.github/workflows/landing-integrity.yml?ref=7eaa9624"   # → /tmp
gh api "repos/Archright/Axiom/actions/runs?per_page=100&created=2026-11-01T09:00:00Z..2026-11-02T10:00:00Z"   # (페이지네이션, 이름별 집계)
gh api "repos/Archright/Axiom/actions/runs?per_page=60&created=2026-11-02T07:25:00Z..2026-11-02T07:42:00Z"
gh api "repos/Archright/Axiom/actions/runs?per_page=60&created=2026-11-02T07:38:00Z..2026-11-02T07:52:00Z"
gh api "repos/Archright/Axiom/actions/runs?per_page=60&created=2026-11-02T07:20:00Z..2026-11-02T08:00:00Z"
gh api "repos/Archright/Axiom/actions/runs?per_page=60&created=2026-11-01T09:00:00Z..2026-11-01T10:00:00Z"
Context7: resolve-library-id("actions/cache") → /actions/cache ; query-docs ×2 (save-skip/restore-keys, eviction/scope)
로컬 읽기: .github/workflows/*.yml, .github/actions/setup-axiom-toolchain/action.yml,
  git log/show/archive(498c5570·8054c2e4·c24e812a3 — 검증용 재계산, /tmp에만 임시 파일, 사용 후 삭제)
검산: sha256sum 재계산 — script_hash(2 트리), a_fp(2 라인지), b_identity(트리 498c5570) 전부 관측치와 일치
```

삭제(DELETE)·정책 변경·저장소 수정·git mutation은 일절 수행하지 않았다. /tmp 외 생성 파일 없음(검증용 임시 디렉터리는 사용 후 제거).
