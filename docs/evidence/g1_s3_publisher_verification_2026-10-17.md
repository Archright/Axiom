# G1 S3 검증 — ci-cache-publisher post-Lever-B 신뢰성 판정 (2026-10-17)

> **종류**: 실행 증거 (관측 기록). **질문**: `g1_completion_2026-10-16.md`가 "S3 auto-pending on next code PR"로 남긴 G1 S3(공급→재사용 자동 성립)이 실제로 성립했는가.
> **권위**: 런/잡/스텝·캐시 상태 = GitHub Actions API (GET 전용). 본 기록은 Reporter다.
> **판정**: **PASS — G1 S3 성립.** 발화 신뢰성 7/7(100%, 완결 후 +2~4s), B-캐시 실저장 3회(`Cache saved with key` 로그), job1 웜 exact-hit 재사용 2회 직접 관측.

## 1. 발화 상관 (post-Lever-B gate 완결 → publisher)

| gate run | PR | 완결(UTC) | publisher run | lag | 결과 |
|---|---|---|---|---|---|
| 38867729895 | #880 | 07:46:57Z | 38869397558 | +3s | 미시딩 — 구가드 창(`[publish-skip] run path … != admission-gate.yml`, G1 §3.1 예고된 1차 발견) |
| 38871419937 | #881 | 08:22:52Z | 38873301060 | +2s | 미시딩 — 동일 구가드 창(가드 수정 착지 08:23:16Z의 24초 전) |
| 38874492382 | #882 | 08:50:10Z | 38876343879 | +3s | **저장** `axiom-b-f5c61aab…` @08:51:22 |
| 38885317769 | #883 | 10:21:44Z | 38886720208 | +3s | 보류(정상) — base-lookup HIT |
| 38885912015 | #884 | 10:29:31Z | 38887577496 | +4s | **저장** `axiom-b-165f9b70…` @10:30:38 |
| 38891209338 | #885 | 11:14:54Z | 38892512998 | +2s | 보류(정상) — base-lookup HIT |
| 38913175446 | #886 | 14:22:55Z | 38915302589 | +3s | **저장** `axiom-b-5a0418c9…` @14:24:45 |

동일 머지 사이클의 타 워크플로 완결발화 19건은 path-guard가 전부 올바르게 `[publish-skip]` 거부(위임 계약 준수). **사실 정정**: publisher 가드 수정(`5c19afd10`)의 착지는 **PR #881 merged 08:23:16Z** — 07:19:10Z는 cutover 기록 커밋(`a5ba9673`, PR #880) 시각이다. gate1·2의 미시딩 2건은 이 창이며 G1 문서가 이미 정확히 기록했다.

## 2. job1 웜/콜드 — "설계된 톱니" 메커니즘 확정

job1(`attest / build-base-artifacts`) 소요: 244→281→267→**66(웜)**→219→**66(웜)**→293s. 로그 증거: 콜드 = `Cache not found` → S5 COLD BUILD, 웜 = `Cache hit`·`exact-hit=true`. **메커니즘**: job1의 b-key는 한 세대 뒤(base=직전 착지)를 소비하므로, 직전 PR이 컴파일 입력을 바꾸면(#883, #885) 정확히 1회 콜드 → publisher가 +2분 내 동일 클로저 키 시딩 → 다음 동일-클로저 런 웜(관측 2/2). A(툴체인)캐시는 7/7 HIT. **S3 자동 성립 사례**: 08:51 저장→10:09 exact-hit 웜, 10:30 저장→11:03 exact-hit 웜, 14:24 저장→소비 대기.

## 3. 캐시 상태 (366엔트리 전수)

총량 10,384,950,271B = **상한(10GiB)의 96.7%** (R11/R12 — LRU+7일 퇴거, 시점 비보장). 계열: axiom-a 355 / axiom-b 11(post-Lever-B 신규 3, 전부 현행 레시피 세대 25846005). **위생 이상(권고)**: `axiom-a-rt-*`가 **동일 키 351중복 ≈ 4.56GiB = 상한의 47%** — 압박의 주원인. B-path가 아니며 즉각 위험은 없으나(퇴거 임박) 감사 후속 권고.

## 4. 잔여 결함 (치명 없음 — 후속 과제 등록)

1. **Lane(head-tree) 시딩 post-fix 0/5** — 레인 페이로드에 `proofs/.lake/build/bin/ircheck` 결손 → fail-closed skip → 코드 PR 직후 1회 콜드 유지(§2 톱니의 원인). DEBT#502 계승 후속. J3 가속 결손일 뿐 correctness 무관.
2. **Guard 일시 API 오류 시 red** — run 38884201325(guard curl 502, 1/92). required check 아님 — 장식적 노이즈.
3. **path-guard 갱신 전파 지연** — main 착지 후 실행면이 구버전을 ~18분 실행(플랫폼 quirk).

## 5. 재현

```bash
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100" --jq '.workflow_runs[] | select(.name|test("admission-gate")) | [.id,.conclusion,.created_at,.updated_at]'
gh api "/repos/Archright/Axiom/actions/workflows/ci-cache-publisher.yml/runs?per_page=50" --jq '.workflow_runs[] | [.id,.event,.conclusion,.created_at]'
gh api "/repos/Archright/Axiom/actions/cache?per_page=100" --jq '[.actions_caches[] | .key] | group_by(.) | map({key: .[0], n: length}) | sort_by(-.n) | .[:3]'
```
