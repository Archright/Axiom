# S1A 원인 분리 단계 A — lane-0 실행 레짐 귀속·정책-합법 레버 종결 (2026-10-18)

> **종류**: 측정 기록 (원인 분리 단계 A — 종결 기록). **질문**: s1a judgment-CAS lane-0 실행 시간의 지배 인자 귀속 — (1) 호스트·레짐 인과성, (2) 정책-합법 속도 레버의 존재, (3) 분할 병렬화의 자격.
> **권위**: 전 수치는 runs/jobs/logs API GET 관측값과 기존 러너 로그 헤더 추출이다 — **신규 실행 0건, 기존 로그만 소비**. merge-admission 판정 권위는 GitHub이며 본 기록은 Reporter다. 커널 계약 카운트의 권위는 `src/verification/judgment_cas.nim` 커니컬 상수(probeCount==14, kernelAcceptCount==17)와 [test_judgment_cas_contract.md](../spec/test_judgment_cas_contract.md)다. 레버 금지 축의 권위는 [ci_pareto_baseline.json](../../data/ci_pareto_baseline.json) SCOPE AMENDMENT v11과 [ADR-0029](../adr/0029-ci-generation-execution-epoch-and-reuse-verdict-binding.md)다.

## 1. 표본 — lane-0 잡 전수 36건 (2026-10-16T07:35Z–2026-10-18T02:23Z)

기존 로그만 소비한 전수 관측: 36 lane-0 jobs = **35 EXECUTED + 1 REUSED**. REUSED 1건(job 117302777523, run 39000589841)은 §6 부수 발견으로 분리하며 실행 밴드 통계에서 제외한다(실행 단계 미형성).

## 2. 판정 1 — 인과성: **VM_REGIME_SUPPORT**

실행 시간 분산의 소재는 작업이 아니라 **호스트(VM 레짐)**다.

- **레짐 상수**: ImageVersion `ubuntu24-20261012.334.1` 36/36, arch `x86_64` 36/36, nproc 2 36/36. VM 인스턴스는 36/36 **신규**(러너 인스턴스 ID 전부 상이) — 같은 라벨 안에서의 배치는 복권이다.
- **A-restore 반정렬, 교차 0건**: 이중 양상 ~50s(n=16, 49.6–54.0) vs ~28s(n=19, 24.7–32.3), 경계 32.3→49.6 사이 관측 0건. compute class와 **교차 0**: io-slow = 6L+10M+0H, io-fast = 0L+2M+16H+1X — **공동 관측 가능한 호스트 클래스 2개가 반상관한다**(io-slow 호스트 → L/M 밴드, io-fast 호스트 → H/X 밴드).
- **커널 단가가 밴드를 추적**: 단가 4.3–9.4s, 밴드 중앙값비 **1:1.51:1.92**(L 4.32–4.98 / M 7.03–8.18 / H 9.09–9.39 / X 9.15), r(dur,unit)=**0.980**, r(dur,kspan)=**0.999**, r(unit,a-rest)=**−0.830**.
- **작업 상수**: 14개 [OK] 위치 동일, ACCEPT 17 동일(커니컬 kernelAcceptCount==17), Lean 4.33.0 고정(admission-check.yml:443) — 분산의 작업 측 기여 없음.
- **밴드 내 배치 복권**: 동일 라벨·동일 작업에서 밴드가 갈린다 — 배치는 잡이 통제할 수 없는 GitHub 측 할당이다.
- **X 이상치 399.3s**(job 117375940207, run 39025539585) = **런 내부 noisy-neighbor 전이**: 단가는 H 밴드(9.15)인데 런 중반 간격 프로파일이 9.1s → 28.8/14.4s로 이동 — 런 단위가 아니라 런 도중 호스트 경합이 변한다.

## 3. 상 조성 — 실행 지배 (decomposition 기록 재확인)

| 상 | 점유 | 절대 범위 |
|---|---|---|
| compile+pre | 12–16% | 28.5–52.9s |
| **kernel span** | **83–88%** | 133.3–350.0s (17 × `lake env lean` 스폰) |
| post | ≈0 | ~0s |

실행 지배 — [post_a_d3_decomposition_2026-10-17.md](post_a_d3_decomposition_2026-10-17.md)가 자리 매김한 MG wall 내부(67.3%) 지배 구조와 정합.

## 4. 판정 2 — 레버: **NONE_POLICY_LEGAL**

정책-합법 속도 레버는 존재하지 않는다. 축별 기각:

1. **라벨 내 선택 기제 없음** — 36/36 상이 VM: 배치는 GitHub 측 복권이고 합법적 핀 수단이 없다.
2. **ubuntu-24.04-arm** — arch→a_fp 전파로 캐시 계통 전체 churn(action.yml:291–293 — a_fp가 b_key에 결속, :293이 a-key 출력) + [ADR-0029](../adr/0029-ci-generation-execution-epoch-and-reuse-verdict-binding.md) 실행-epoch 축. **속도 근거 없음**.
3. **ubuntu-slim** — 1-vCPU 컨테이너 "not suitable for heavyweight CI", Lean 툴링 부재([hardware_smoke_static.md](hardware_smoke_static.md)).
4. **대형 러너** — SCOPE AMENDMENT v11 금지([ci_pareto_baseline.json](../../data/ci_pareto_baseline.json): "large runners forbidden"). 개정되더라도 분당 과금 + 배치 지연을 **총 MG wall** 기준으로 평가해야 한다(이중 지표 규칙 — 잡 벽시계 단독 판정 금지).
5. **잡 내 웜 공급** — 가치 2–5s뿐(관측 b-rest 0.2–4.1s).

## 5. 판정 3 — 분할 이관: **CONTRACT_REVISION_REQUIRED** (assessment only)

- s1a는 **하나의 판정 단위로 카운트-결속**되어 있다: 커니컬 카운트(kernelAcceptCount==17 ∧ probeCount==14 — judgment_cas.nim:901·:836), 단일 플러시(judgment_cas.nim:403–433 — `JudgmentClosure`, 타입이 곧 계약), judgment-CAS 계약([test_judgment_cas_contract.md](../spec/test_judgment_cas_contract.md) §4), DEBT#432(G5 GO-핵심 테스트 CI 배선 — 동결 Makefile 표면 계층).
- 따라서 분할은 **기계적 절차가 아니라 ContractRevision 슬라이스**다.
- 구조적으로는 병렬화 가능하다(벽시계 ≈ H-밴드 절반, lane-2 샤드가 자연적) — 그러나 분할이 줄이는 것은 **중앙값이지 분산 비율이 아니다**.

## 6. 종결 경로 — **경로 3: 정직한 종결 (HONEST_CLOSE_NO_LEGAL_LEVER)**

- 합법 레버 부재 → 증거와 제약을 기록하고 종결한다(본 기록 + 쌍생 JSON이 그 산출물이다).
- 소유자 판정 요청은 **대형 러너 개정이 실제로 검토될 때만** — 그때 비용/편익과 이중 지표(총 MG wall) 규칙을 함께 평가한다(§4-4).
- 권장 다음 슬라이스 = **분할 ContractRevision 설계**(§5).
- **부수 발견 등록**: REUSED-despite-FORCE_EXECUTED 1/36 — job 117302777523, run 39000589841. admission-check.yml:2696(`AXIOM_JUDGMENT_CAS_FORCE_EXECUTED` — merge_group에서 '1' 강제)과 :2809 대역 basis=REUSED 스킵 배선이 계약과 어긋나 REUSED가 통과됐다. 본 슬라이스 범위 밖 — **별도 슬라이스로 이관**.

## 7. 정직 한계

- 기존 로그만의 관측(신규 실행 0건) — 2일 단일 창, n=36.
- REUSED 1건은 실행 밴드 통계 제외(§1) — io-fast 클래스 소속(30.3s)까지만 관측.
- 백분율·타이밍은 로그 타임스탬프 해상도(±1s)다.
- A-restore 클래스 경계(49.6 vs 32.3)는 관측 간격이며 기제 규명(io 계측)은 본 기록 범위 밖이다.
- 본 기록은 측정·종결 기록이지 새 권위·계약·SLO를 세우지 않는다(Reporter).

## 8. 판정 (verdict)

**VM_REGIME_SUPPORT · NONE_POLICY_LEGAL · CONTRACT_REVISION_REQUIRED · HONEST_CLOSE_NO_LEGAL_LEVER** — 인과성은 VM 레짐(A-restore 반정렬 0교차·커널 단가 밴드 추적 1:1.51:1.92), 정책-합법 레버 없음(경로 3 종결), 분할은 ContractRevision 이관. 부수: FORCE_EXECUTED 위반 REUSED 1/36. 기계 판독 쌍생 기록: `data/ci_optimization/s1a_stage_a_2026-10-18.json`.

## 9. 재현

```bash
# 1) 표본 runs → jobs 전수 (예: 창 내 run — 36건 전수는 동일 절차)
gh api "repos/Archright/Axiom/actions/runs/39000589841/jobs?per_page=100" \
  --jq '.jobs[] | [.id,.runner_name,.started_at,.completed_at,.conclusion] | @tsv'

# 2) 잡 로그 + 헤더 추출 (image/arch/nproc/VM 인스턴스 — 36건 전부 동일 grep)
gh api repos/Archright/Axiom/actions/jobs/<job_id>/logs > <job_id>.log
grep -m1 '\[go-lane\] lane=0' <job_id>.log   # runner=<VM inst> image=ubuntu24-20261012.334.1 arch=x86_64 nproc=2
grep -m1 'Image Release' <job_id>.log        # ubuntu24/20261012.334

# 3) A-restore 타이밍 (start-action display 라인쌍 간격)
grep 'A-layer restore' <job_id>.log

# 4) 커널 단가·스폰·[OK] 위치
grep -c 'lake env lean' <job_id>.log
grep -c '\[OK\]' <job_id>.log

# 5) 부수 발견 — REUSED-despite-FORCE_EXECUTED
gh api repos/Archright/Axiom/actions/runs/39000589841/jobs --jq '.jobs[] | [.id,.conclusion]'
grep -m1 '"basis":"REUSED"' <AXIOM_JUDGMENT_CAS_DECISION_PATH 산출 JSON>
```
