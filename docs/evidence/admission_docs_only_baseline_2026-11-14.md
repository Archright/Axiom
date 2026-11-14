# docs-only 기준선 — admission 비용의 고정부와 변동부

작성 2026-11-14. 목적: **변경 내용과 무관한 고정비**와 **변동을 만드는 레그**를 분리 측정한다.
동일한 실행 계약(merge queue `admission-gate`)의 두 표본을 사용하며, 두 후보 모두 **파일 1개,
문서 전용** 변경이다. 즉 판정 대상의 계산량은 사실상 0이다.

## 1. 표본

| PR | 변경 | merge_group run | 첫 job 시작 | 마지막 job 종료 | job span |
|---|---|---|---|---|---|
| #38 | `docs/evidence/*.md` 1개 | `43544331406` | 02:05:33Z | 02:10:25Z | **292s** |
| #39 | `docs/spec/*.md` 1개 | `43545650051` | 02:19:29Z | 02:27:49Z | **500s** |

같은 종류의 변경에서 **+208s** 차이가 난다. 차이는 후보의 내용이 아니라 실행 호스트에서 발생한다.

## 2. 레그 분해 (상대 시각, 초)

`#38` (빠른 호스트):

```
  0  closure-deriver              54
  1  attest/build-base-artifacts  57
 57  gateway/select               43
 60  attest/go-critical-lane (0)  103
 61  attest/go-critical-lane (1)  110
174  attest/admission-check        55
232  mint-prepare/prepare          22
257  mint-publish/publish          29
289  admission-check                3
```

`#39` (느린 호스트):

```
  2  closure-deriver              48
  2  attest/build-base-artifacts  52
 53  gateway/select               51
 56  attest/admission-independents 91
 57  attest/go-critical-lane (0)  305
 57  attest/go-critical-lane (1)  227
364  attest/admission-check        53
420  mint-prepare/prepare          24
447  mint-publish/publish          47
497  admission-check                3
```

두 lane은 **병렬**이므로 임계경로는 `build-base-artifacts → max(lane 0, lane 1) →
attest/admission-check → mint 체인 → admission-check`이다.

## 3. 고정부 / 변동부

| 구간 | #38 | #39 | 성격 |
|---|---|---|---|
| `attest/build-base-artifacts` | 57s | 52s | 고정 — 후보와 무관한 실행자 산출물 |
| `attest/go-critical-lane (0)` | **103s** | **305s** | **변동 — s1a full-chain** |
| `attest/go-critical-lane (1)` | 110s | 227s | 변동 — d2/proof_integrity |
| `attest/admission-check` (aggregate) | 55s | 53s | 고정 |
| `mint-prepare/prepare` + `mint-publish/publish` | 51s | 71s | 고정 — 판정 후 직렬 증서 발행 |
| `admission-check` (최종) | 3s | 3s | 고정 |
| **고정부 소계** | **166s** | **179s** | 후보와 무관 |

- **변동의 거의 전부가 lane 0이다**: `+202s` (103 → 305). 전체 차이 `+208s`와 사실상 같다.
- 느린 호스트에서 lane 0 하나가 job span의 **61%**다.
- 고정부는 166–179s로 안정적이며, 어떤 후보를 넣어도 사라지지 않는다.

## 4. 이 기준선이 말하는 것

1. **SLO 480s는 후보의 복잡도가 아니라 lane 0의 호스트 운에 의해 결정된다.** 문서 1개짜리
   변경도 느린 호스트에서 502s로 SLO를 초과했다(측정). 반대로 빠른 호스트에서는 394s다.
2. **따라서 의미 있는 최적화는 lane 0(과 lane 1)의 고정 계산을 줄이는 것 하나뿐이다.**
   `build-base-artifacts`·aggregate attest·mint 체인은 후보와 무관한 필수 고정비다.
3. **투영(미측정)**: lane 0의 s1a full-chain은 subject별 첫 EA 측정 3회를 포함하고,
   각각 `ircheck extract` subprocess + 미메모 바이너리 digest다
   (`admission_leg_runtime_profile_2026-11-14.md` §3.3). EA 비용이 3회 중 2회분만 제거되어도
   느린 호스트 lane 0은 `305 → ~165s`로 투영되고, 총 span은 `~500 → ~360s`가 되어
   SLO 안에 들어온다. **이 투영은 측정이 아니다** — CI 러너에서 `ircheck` cold/warm 시간을
   직접 재는 것이 착수 전제다.

## 5. 재현 명령

```bash
# 표본 선택 (merge_group, admission-gate)
gh api "repos/Archright/Axiom/actions/runs?event=merge_group&per_page=40" \
  --jq '.workflow_runs[] | select(.name=="admission-gate") | "\(.id) \(.created_at) \(.head_branch)"'

# 레그 분해
gh api "repos/Archright/Axiom/actions/runs/<RUN_ID>/jobs?per_page=100" \
  --jq '.jobs[] | "\(.started_at)\t\(.completed_at)\t\(.name)"'

# 그룹 종료 시각 (job span 경계)
gh api "repos/Archright/Axiom/actions/runs/<RUN_ID>" --jq '{created_at,updated_at}'
```

## 6. 한계

- 표본 2건이다. 호스트 등급 변동의 분포를 확정하려면 반복 표본이 필요하다.
- `updated_at`과 마지막 job 종료 사이의 간격이 표본마다 다르다(#38 ~102s, #39 ~2s).
  그래서 총 시간은 `created_at → updated_at`이 아니라 **job span**으로 비교했다.
- 두 표본은 서로 다른 base(`fd62db26` / `6379f12f`)를 사용한다. 두 base의 차이는 문서 1건이다.