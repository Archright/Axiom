# Terminal Outcome Acceptance — publisher lane identity 재범위화 (executed-subject anchor)

> Vertical Slice 실행 증거 — **ADR-0025 Amendment D**: `ci-cache-publisher.yml` lane
> identity 게이트를 executed-subject anchor로 재범위화(앞선 freshness/ahead-invariant
> 판정 제거 — 착지 가능성은 GitHub ruleset/merge queue 권한으로 위임).
> 정본: `docs/adr/0025-gateway-landing-authority.md` Amendment D ·
> `docs/spec/github_delegation_residuals.md` R10 재판정 ·
> `docs/evidence/epoch_record_memo_reanchor_2026-10-08.md` · body PR **#594**(merge `9d3bfdef7`).
> 실측: 2026-10-08, 실제 merge-queue 경유 머지 사이클 3건(#598 · #603 · #604) 전량 REST 관측.

## 1. Terminal Outcome (판정 기준)

> stale/behind PR이 포함된 실제 머지 사이클에서 — (1) mg-페이즈 **동일 lane identity**
> B-cache HIT(정확 키 + digest 검증) 실현 ∧ (2) 동일 build identity의 콜드 컴파일
> 이벤트 = 사이클당 1회 ∧ (3) not-landable류 publish-skip 0건 ∧ (4) publisher 계산 0건 ∧
> (5) G가 네이티브 MERGE(2-parent)로 main에 착지 ∧ (6) 그 G에 대한 L1/L2/L3 증거 유효.

## 2. 판정: **PASS** — 측정 사이클 = PR #604 (2026-10-08 10:07–10:36Z)

측정 대상 PR #604(`docs/judgment-cas-contract`, head `49e921f6e2bb98729d232c66d41a9a3dc1eb659b`,
parent `1ba6c359e`)는 main(`ab7b7270f`)에 뒤처진 **stale/behind PR** — `tree(H) =
42b18327615b0d87b2b0622efc308e10d01b0d37` ≠ lane 실행 주제 `tree(M) =
0abb24f3d269b0e91828d497bce4ce3eaa874b7c`. **구 게이트(`tree(build) != tree(head)`)
였다면 `[publish-skip] not landable as tested`로 시딩 자체가 생략됐을 R10 클래스.**

### 2.1 완결 계측 사슬 (run·job ID 실측)

| 시각 (UTC) | 관측 | 실측 |
|---|---|---|
| 10:20:02 | PR lane 빌드 (run `37761368078`, job `113262891951`) | `b-identity=0abb24f3…` → `Cache not found` → **콜드 컴파일 (이 identity의 유일한 콜드)** |
| 10:20:04 | PR publisher (run `37762743982`, `RUN_ID: 37761368078`) | `Cache saved with key: axiom-b-0abb24f3d269b0e91828d497bce4ce3eaa874b7c-c91dcb6e…` — **시딩 성공** |
| 10:20:12 | publisher verdict | `[publish] guard=true trees=true verify=true key=axiom-b-0abb24f3…` (executed-subject anchor 통과: `head ∈ parents(build)`) |
| 10:21:55 | **mg lane 소비** (run `37762856609` = merge_group@`9d36342a0`, job `113263630996`) | `b-identity=0abb24f3… b-key=axiom-b-0abb24f3…-c91dcb6e…` — **PR publisher 키와 바이트 동일** |
| 10:22:24 | mg lane 복원 | **`Cache hit for: axiom-b-0abb24f3d269b0e91828d497bce4ce3eaa874b7c-c91dcb6e…`** |
| 10:22:26 | 소비자 검증 | **`AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified, identity=0abb24f3d269 re-derived from trusted inputs (tree+recipe+a_fp), key exact-hit`** |
| 10:37:16 | mg publisher (run `37764512991`, `RUN_ID: 37762856609`) | `[publish-skip] lane key exists — save withheld (single-flight): axiom-b-0abb24f3…` (dedup = 시딩 성공 신호) |
| 10:36:15 | L3 착지 | `landing_observe.sh 604` → **VERDICT: TERMINAL_SUCCESS** — MERGED, oid `9d36342a096c9c63fba5c75c76497a001fdc1e58`, `mergeCommit.parents=2`, graphql↔rest=consistent |

**R10 고정 증거**: 시딩과 소비의 b-key는 완전히 바이트 동일
(`axiom-b-0abb24f3d269b0e91828d497bce4ce3eaa874b7c-c91dcb6ef276e409dec2b7f3c03d54e3ba2f9aa0d2ca5b480f176864ab277340`)
— 소비 키는 publisher의 checkout-전환 keygen(레시피 해시를 build 트리에서 계산) 덕분에
프로듀서와 **바이트 동일**. 동일 identity의 콜드 컴파일 = **1회** (10:20:02 PR lane뿐;
mg lane은 HIT → cold 0).

### 2.2 교차 사이클 재사용 보너스 (census "A lane → B base" 패턴, MISS→HIT)

#603 사이클의 **mg lane identity `85616c53…`**(= tree(`ab7b7270f`), 09:38:38 콜드 1회,
09:54:27 시딩)를 **#603 사이클의 mg base 빌드가 10:21:50에 소비**:
`Cache hit for: axiom-b-85616c53…` + `AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 …
identity=85616c538895 … key exact-hit` — census §5.1 #5·#6이 MISS로 기록한 교차
패턴이 이제 HIT를 낸다.

## 3. 사이클 전량 실측 매트릭스

| 사이클 | PR (head) | stale? (tree(H) ≠ tree(M)) | PR-lane 시딩 (verify=) | mg 소비 | 콜드/identity | not-landable skip |
|---|---|---|---|---|---|---|
| C1 | #598 `7dac5debb` (mint 주석) | ✓ `f33d3af8` ≠ `0de7eb78` | `0de7eb78…` seeded | mode=none(댓글 전용 → derivedEmpty) → lane 부재 + base 이동 | 1 | **0** |
| C2 | #603 `8ae68ca81` (R3-② 문구) | ✓ `cde9ef75` ≠ `7a49353e` | `7a49353e…` seeded | `85616c53…` 요청(큐 stacking → class A 상이 identity) → MISS | 1 | **0** |
| C3 | #604 `49e921f6e` (judgment CAS) | ✓ `42b18327` ≠ `0abb24f3` | `0abb24f3…` seeded | **`0abb24f3…` HIT + digest OK** | **1** | **0** |

- **구 게이트 skip 증거**: C1–C3 전부 `tree(H) != tree(M)` — 구 등식 게이트의 skip
  조건에서 **시딩이 성공**했다(3건 모두 `verify=true` + `Cache saved`). C3에서만
  소비까지 동일 identity로 이어졌다.
- **not-landable류 publish-skip = 0**: publisher 4건(`37757495355`·`37759778850`·
  `37762743982`·`37764512991`) 전량 `grep -c "not landable"` = **0**.
- **publisher 계산 0**: verdict는 publish/skip 라인만 — 빌드·판정·테스트 0회.
- **잔여(정직 기록)**: C1의 `0de7eb78`, C2의 `7a49353e` 시드는 소비자 부재/큐
  base 이동으로 미소비 orphan — bounded quota 낭비(J3 fail-open), 정확성 무관.
  원인 = merge-queue speculative stacking(그룹 base ≠ main; `docs/spec/gh_run_observation_quirks.md` Q2).

## 4. Completion Evidence 대응 (계획 지표 → 실측)

| # | 계획 지표 | 실측 |
|---|---|---|
| 1 | 동일 identity 앵커 — PR publisher와 mg gate b-key 바이트 동일 | C3: `axiom-b-0abb24f3…-c91dcb6e…` 양측 완전 일치 ✓ |
| 2 | mg-페이즈 B-cache HIT (stale PR의 lane identity) | C3 job `113263630996`: `Cache hit for: axiom-b-0abb24f3…` ✓ |
| 3 | 동일 identity당 콜드 컴파일 = 사이클당 1회 | `0abb24f3` cold 1 (10:20:02) + HIT 1 (10:22:24) ✓ |
| 4 | eligibility-skip 0 / dedup-skip ≥0 / publish-fail 0 | not-landable 0건, `key exists` dedup 3건(성공 신호), publish-fail 0 ✓ |
| 5 | publisher 계산 0 (publish/skip만) | 4 runs verdict 라인만 ✓ |
| 6 | G native MERGE 2-parent 착지 | `9d36342a0` parents=2, MERGED 10:36:15Z ✓ |
| 7 | L1/L2/L3 증거 유효 | admission-check SUCCESS(run `37762856609`) + mint-publish SUCCESS + `landing_observe.sh 604` TERMINAL_SUCCESS(graphql↔rest 일치) ✓ |

부가: A-계층 교차 런 재사용 `Cache hit for: axiom-a-Linux-8497f84b…` (mg lane 10:21:55).

## 5. Follow-up (범위 밖 — 본 슬라이스 미착지)

1. **S5 build-skip** (HIT에서도 남는 warm 재컴파일 ~86–102s) — J3 계약상 별도 슬라이스.
2. **Slice 2**: `1 identity = 1 computation` 자동 enforcement(동일 identity 2회 cold = 기계 판정 위반).
3. **orphan 시드 위생** (§3 잔여): 소비 불가 예정 키의 시딩 억제 또는 만료 정책 — quota 한정 개선.
4. quirk 문서화: `docs/spec/gh_run_observation_quirks.md` (본 수사에서 발견된 3건 — §0.5b 의무 충족).
