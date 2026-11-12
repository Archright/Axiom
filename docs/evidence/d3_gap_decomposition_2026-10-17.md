# D3 잔여 갭 분해 — post-Lever-B 8 PR (#880–#887) (2026-10-17)

> **종류**: 측정 기록. **질문**: S3 재판정(`go_matrix_s3_readjud_post_leverb_2026-10-17.md`)의 잔여 갭(D3 중앙값 1389s vs 목표 ≤1256s = 133s)은 어디에 있나.
> **정의**: 동결 공식(prereg §4.1) — D1=생성→첫 green, D2/D2′=AME/ADQ→바운드 MG 런, D3=mergedAt−생성. 항등식 `preQ+queue-wait+MG-wall+tail = D3`가 8/8에서 정확 성립(교차검증: 각 merge commit의 committer date == ADQ 시각).

## 1. 성분 표 (초)

| PR | D1 | preQ | D2′ | queue-wait | MG wall | tail | D3 |
|---|---:|---:|---:|---:|---:|---:|---:|
| #880 | 588 | 598 | 19 | 19 | 947 | 25 | 1589 |
| #881 | 315 | 327 | 19 | 19 | 1019 | 24 | 1389 |
| #882 | 302 | 331 | 19 | 19 | 1000 | 27 | 1377 |
| #883 | 572 | 597 | 20 | 20 | 752 | 27 | 1396 |
| #884 | 373 | 411 | 7 | 7 | 902 | 26 | 1346 |
| #885 | 491 | 532 | 18 | 18 | 716 | 26 | 1292 |
| #886 | 567 | 569 | 19 | 19 | 951 | 25 | 1564 |
| #887 | 383 | 438 | 18 | 18 | 734 | 24 | **1214** |

평균 기준 분해: preQ 475.4s(34.1%) + queue-wait 17.4(1.2%) + **MG wall 877.6(62.9%)** + tail 25.5(1.8%).

## 2. 갭 귀속 (−133s 필요, 랭킹)

1. **MG 레인-후 직렬 꼬리 — 중앙값 291s(254–331)**: 레인 완료 후 attest 소비자(~118)→mint-prepare(~35)→mint-publish(~49)→verdict(~43)→롤업(3–5) 5단계 완전 직렬 — **레인이 같은 sha에서 방금 증명한 것의 재검증**. 이 단일 성분이 갭 전체보다 크다.
2. **bootstrap(job1) 콜드 편차 — 웜 70–113s(3/8) vs 콜드 223–297s(5/8)**: 웜 보편화 시 MG wall −123~−166s.
3. **preQ/D1 — 485s**: PR head에서도 동일 직렬 사슬 서명(mint→verdict→rollup ≈ +160s). 제품 구조 변경으로만 절감.
4. **큐 픽업(D2′ 18–20s)·tail(25.5s)**: GitHub 고정 역학 — 회수 불가, **큐 파라미터 레버는 소진**.

**결론**: 갭은 ~전부 MG wall 내부에 있고 (1) 직렬 사슬 재구성(ADR-0032급 — D1의 쌍둥이 사본 ~160s도 동시 절감 → D3 ≈1050–1135s) 또는 (2) 웜 보편화(→~1243s) 중 하나로 닫힌다. **자연 실험**: #887(웜 bootstrap+짧은 꼬리)은 D3 **1214s — 목표 이내**.

## 3. 정정 (이전 프레임)

"레인 시딩 지연" 문자적 해석 기각 — 레인 시작 오프셋(+73~300s)은 `needs: build-base-artifacts` 대기. 실제 콜드는 **bootstrap 아티팩트 상태**(B-시드 소비)다(publisher lane 시딩 결손 후속과 동일 지점).

## 4. 재현

```bash
gh api repos/Archright/Axiom/issues/<N>/timeline --paginate   # AME/ADQ 이벤트
gh api repos/Archright/Axiom/commits/<head>/check-runs         # D1
gh api "/repos/Archright/Axiom/actions/runs?event=merge_group&per_page=100"  # MG wall (head_sha==mergeCommit 바인딩)
```
