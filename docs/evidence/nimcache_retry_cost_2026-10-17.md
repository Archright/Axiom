# nimcache fold-back 물질성 측정 — MG 재시도 콜드 비용 NEGLIGIBLE, defer 권고 (2026-10-17)

> **종류**: 결정 입력 증거 (decision input). 본 문서의 목적은 **nimcache fold-back(실패 시 nimcache 환류) 구현 여부 판단의 입력 증거**를 제공하는 것이다 — 구현·계획·승인이 아니다. 구현 결정 권위는 아키텍트에게 있다(§6).
> **측정 원문**: 2026-10-17 조사 로그(세션 태스크 `agent-81amuyj8`, "nimcache fold-back 물질성 조사 — 최종 보고"). 본 문서는 그 로그의 전사·형식화이며 새 측정을 수행하지 않는다. 수치는 전부 로그가 기재한 런 ID·런 로그·JSON 관측값이며, §2.4의 명령으로 산출 경로를 재현한다.
> **계보** (저장소 루트 기준 경로): `docs/evidence/post_a_d3_decomposition_2026-10-17.md` + `data/ci_optimization/post_a_d3_2026-10-17.json` (D3 성분·bootstrap 상태) · `docs/evidence/go_matrix_parallelization_prereg_2026-10-16.md` §4.1 G-B (동결 공식) · `docs/evidence/mg_red_forensics_2026-10-14.md` §(c) (fold-back이 겨냥한 구 워크플로 결함 정의) · `data/merge_latency/g2matrix_d4_lanes.tsv` (레인별 duration_ms 계열).
> **권위**: 본 문서는 Reporter/decision-input이다 — merge-admission 권위는 GitHub(org ruleset·merge queue·native MERGE 커밋), defer 확정 권위는 아키텍트(§6 요청 대기).

## 1. D3 정의·목표·상태 (retry 포함 여부 포함)

- **정의**: D3 = mergedAt − PR 생성시각 (종단 착지 지연). 동결 공식: `preQ + queue-wait + MG-wall + tail = D3` — 사전등록 `go_matrix_parallelization_prereg_2026-10-16.md` §4.1 G-B verbatim(한 글자 변경 없음).
- **목표**: 1256s. **상태: TARGET_MET_CLEAN_SAMPLE** — 깨끗한 n=4 중앙값 **1006s**(910·991·1021·1038, 4/4 목표 이내), n=5 중앙값 1021s. 근거: `docs/evidence/post_a_d3_decomposition_2026-10-17.md` + `data/ci_optimization/post_a_d3_2026-10-17.json` (PR #904에서 main 착지).
- **retry 포함 여부: 정성적으로는 예.** D3 문서는 #895R을 outlier-red-retry로 분리 보고하며 red 1회 비용 **+2958s**를 명시 기록하고, 감소 경로를 "red 예방(콘텐츠 사전 검증) — 큐·컨트롤러 아님"으로 지목한다. 다만 +2958s를 컴파일-프렙/테스트 성분으로 분해하지는 않았고, 웜 편향 한계(콜드 만연 시 MG wall +100~200s 과소 추정)를 정직 한계로 남긴다 — 본 문서 §2가 그 잔여 질문(콜드 비용의 물질성)을 닫는다.

## 2. 표본과 계산 (재현 가능 형태)

### 2.1 red 빈도 (2026-10-15 00:00Z ~ 10-17, MG 전수)

- MG 착지 그룹 **~66개** 중 파이프라인 실패 **3건** — #838 2회(10-15 03:32·04:11Z, **G2 매트릭스 이전**), #895 1회(10-17 03:04Z).
- **G2 매트릭스 활성(2026-10-16 07:31Z) 이후: 1/26 ≈ 3.8%** (red 1건 = #895).
- 3건 모두 파이프라인 전체(build→레인→attest→mint-publish)가 **성공한 뒤 끝의 verdict predicate 단계만 실패** — 레인 사망 0건. #901은 negative control로 예정대로 큐에 편성되지 않았다(CLOSED unmerged 확인).

### 2.2 실패 1건당 콜드 비용 (n=1, 중앙값 산출 불가) — #895

- 1차 시도(런 38997388474): 레인은 실행됨 — lane-0 s1a `duration_ms=330835`(330.8s), lane-1 123s, run wall ~715s. **이 연산은 낭비가 아니다**(아래 §3 정정 기록).
- 실제로 남는 콜드 프리미엄: **bootstrap 콜드 281s vs 웜 69–101s → +180~210s, 1회**(281−101=180, 281−69=212; 로그 표기 +180~210s). **n=1 한계 명시** — 1건 표본이라 중앙값·분산 산출 불가.

### 2.3 기대 이득 계산식

```
기대 이득 = 콜드 프리미엄 × red율 = 200s × (1/26) ≈ 7.7s/착지
비중     = 7.7s / D3 중앙값 1006s ≈ 0.8%
```

(프리미엄 범위 180~210s를 대입하면 6.9~8.1s/착지 — 결론 불변.)

### 2.4 산출 경로 재현 명령

```bash
# (1) G2 활성 이후 merge_group failure 런 수 → 1 (38997388474)
gh api 'repos/Archright/Axiom/actions/runs?event=merge_group&created=2026-10-16T07:31:00Z..2026-10-17T23:59:59Z' --paginate \
  --jq '[.workflow_runs[] | select(.conclusion=="failure") | .id] | length'

# (2) 같은 창의 착지 수 → 26 (red율 1/26)
gh pr list -R Archright/Axiom --state merged --limit 100 --json number,mergedAt \
  --jq '[.[] | select(.mergedAt >= "2026-10-16T07:31:00Z")] | length'

# (3) 콜드 프리미엄 성분 — bootstrap 상태별 소요(초): 웜 80/69/101(+skip 0) vs 콜드 281 → +180~210s
jq -r '.perPR[] | [.pr, .bootstrapCiBootstrap.state, .bootstrapCiBootstrap.s] | @tsv' \
  data/ci_optimization/post_a_d3_2026-10-17.json

# (4) 1차 시도(실패 런) 레인 duration_ms — lane-0 s1a = 330835 (330.8s)
gh run view 38997388474 -R Archright/Axiom --log | grep -oE 'duration_ms=[0-9]+'

# (5) 재시도 REUSED 스킵 + MG wall 494s (런 created_at→updated_at)
gh run view 39000589841 -R Archright/Axiom --log | grep -E 'AXIOM_JUDGMENT_CAS'
gh api repos/Archright/Axiom/actions/runs/39000589841 --jq '[.created_at,.updated_at] | @tsv'

# (6) 기대 이득 산출 → 7.692s, 0.765%
python3 -c 'print(200*(1/26), 200*(1/26)/1006*100)'
```

- **계열 SSOT 주의**: retry 비용 계열의 정본 위치는 `data/merge_latency/`다(`g2matrix_d4_lanes.tsv` 레인별 duration_ms; `g2matrix_post_leverb_readjud_2026-10-17.json` — D4-composite 중앙값 380.8s·D3 중앙값 1389s, Candidate A 이전 창). `data/benchmarks/perf_latest.json`·`perf_baseline.json`은 LeanKernelVerification 단일 마이크로벤치(warm, min-of-5, 302.7ms; budget 2s)만 담으며 retry 비용의 SSOT가 아니다.

## 3. 결함 비재현 증거

fold-back이 겨냥한 결함은 10-14 포렌식 §(c)의 정의다(원문):

> 테스트 nimcache 캐시 키는 base sha 기반이며 base 키는 "이전에 어떤 주체도 씨딩하지 않아 구조적으로 항상 콜드"다 … GO 스텝 실패 시 **success-only fold-back 업로드(`admission-check.yml:1349-1358`)가 스킵되므로 재시도도 끝내 콜드로 남는다** — 콜드 경합 확률을 누적하는 구조다.
> — `docs/evidence/mg_red_forensics_2026-10-14.md` §(c)

이것은 **구 워크플로 기준**이며, v2에서는 재현되지 않는다(조사 로그 실측):

1. **실패 시도조차 fold 업로드를 성공시킨다** — 실패 런 38997388474의 attest/admission-check job에서 "Merge carrier·Merge lane-0/1·Upload folded nimcache **전부 success**(03:14:22Z)".
2. **레인 test-supply는 양쪽 시도 모두 웜 317 entries** — "base 키 구조적 항상 콜드" 전제는 J3 carrier로 이미 완화됨.
3. **fold-back 실험 PR #830은 10-14에 이미 CLOSED unmerged**로 종료된 역사(forensics §(d) 당시 "open — 재범위 대기 중" 표기 이후 종결).

**정정 기록 (조사 로그 §(f) — 1차/재시도 귀속 교정)**: #895의 1차 시도 레인은 **EXECUTED 실행**(330.8s)이었고, **REUSED 스킵은 재시도**(39000589841, `AXIOM_JUDGMENT_CAS: REUSED — record 83d452929bde`, 테스트 ~0초)에서 일어났다. 재시도 MG wall **494s = 표본 최단**(clean 중앙값 667.5s보다 빠름) — 즉 **1차 실행이 재시도의 레인을 선불**해 재시도가 오히려 가장 빨랐다. 캐시 무관 부담만 남는다: **D3 +2958s의 ≈94%는 절차/인지 시간**(재푸시 왕복 23.4분 ≈ 1404s + 재-AME 6분 = 360s 등 재푸시→재큐→재-green 왕복)이지 캐시가 아니다 — 산식: ≈94% = 1 − (콜드 프리미엄 ~180s)/(+2958s).

**정직 노트 (결론 방어)**: #895 착지(10-17 04:03) 이후 MG venue의 판정재사용은 차단됐다(`AXIOM_JUDGMENT_CAS: EXECUTED — force-execution gate` 실측, 런 39011781572 — s1a 265.3s EXECUTED). 따라서 차기 red 재시도는 레인을 강제 실행한다. 그러나 레인 **컴파일 공급은 여전히 웜 carrier(317 entries)**로 충당되고, s1a 자체 편차(218–361s)가 콜드-프렙 절감 상한보다 크다 — 판정은 변하지 않는다.

## 4. 판정

**NEGLIGIBLE — defer 권고.**

1. **기대 이득 ≈ 7.7s/착지 = D3 중앙값의 0.8%** (200s × 1/26, §2.3).
2. **결함 비재현** — fold-back이 겨냥한 "success-only fold 스킵"은 구 워크플로 기준이며 v2에서는 실패 시도조차 fold 업로드가 success이고 공급이 웜이다(§3).
3. **복잡도 추가 대비 근거 약함** — 실패 경로에 조건부 업로드·키 관리를 얹을 관측된 수익이 없다.

이는 문제 무시가 아니라 **"관측된 이득이 작을 때 구현을 보류한다"는 명시적 결정**이다 — 사용자 기준("성능 이득을 측정하기 전에 운영 경계를 변경하지 않는다")을 그대로 충족하며, 재평가 조건을 §5에 사전 등록해 봉인 아닌 유보로 남긴다.

## 5. 재평가 트리거 (사전 등록)

아래 중 하나가 관측되면 defer를 재평가하고, 그때 **success-gated vs fold-back 비교 실험을 사전등록**한다(§2 수치가 전제):

1. **red율 > 착지 10회당 1회** (현 1/26 ≈ 3.8% 대비 악화);
2. **세대 회전 직후 첫 MG가 콜드 레인(`entries=0`)으로 red** — 10-14형 J4 패턴 재발;
3. **MG 재시도에서 콜드 레인 실행 관측** — §3 정직 노트의 force-execution gate로 재시도 강제 실행이 구조적으로 가능해졌으므로, 이 표면은 실제 관측점이다.

## 6. 결정 요청

아키텍트에게 다음을 **확정 승인**해 달라:

- nimcache fold-back(실패 nimcache 환류) 구현을 **defer(보류)** 함 — 근거 §2(기대 이득 0.8%)·§3(결함 비재현)·§4(NEGLIGIBLE).
- 보류 상태에서 현행 v2 웜 공급 경로(J3 carrier)를 유지하고, §5 트리거 발생 시에만 §5의 사전등록 실험으로 복안한다.

본 문서는 입력 증거다 — 승인은 아키텍트 판정으로 하며, 본 문서 자체는 구현을 시작하지 않는다.
