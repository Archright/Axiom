# CI Critical Path Manifest — 2026-08-25

> 구조적 결정: WP1 (thin projection, docs-only). 새 분석 프레임워크 없음.
> 정적 DAG 스펙/별도 duration JSON/도구 코드 **없음**.
> 실측값의 단일 출처 = `docs/audit/ci_latency_decomposition_2026-08-24.md` (§17.1),
> 랜딩 SSOT = `docs/audit/ci_latency_current_state_2026-08-25.md`.
> 여기 나오는 숫자는 위 실측 문서에서 동결되었으며, 다른 hand-authored 숫자 소스는 만들지 않는다.

---

## 1. 확정된 실측 증거 (raw evidence)

`verify-integration` job 내부, 실측 wall-clock (초). 출처: `docs/audit/ci_latency_decomposition_2026-08-24.md:790-811` (§17.1).

- **verify-contract (G1/G2/G4/G6/G7) ≈ 633s** ← **criticalPathMaxContainer**
  - **G1 mutation oracle ≈ 249s** ← **largestActionableLeaf** (NEXT TARGET)
  - G6+G4 (OCL/proof) ≈ 191s
  - G2 promotion semantics ≈ 134s
  - G7 proof-universe-lock-gate ≈ 59s
- CI-parity unit tests ≈ 558s (nimble cold rebuild ~156s 지배) — BACKLOG
- Release build + baseline (G3/G7) ≈ 150s
- verify-all ≈ 106s
- Release E2E (G7) ≈ 8.2s

원문 결론(§17.1, line 811): "verify-contract의 지배 비용은 G1(249s)과 G6+G4(191s)이며, 이후 latency 최적화의 1순위 대상."

G7 추가 세부(동일 문서 §28.2, line 2043): G7 warm wall ≈ 56–59s, 부모 in-process CPU ≈ 92%, 그중 IR/UAP 계열 ≈ 48s.
→ 사용자 보고의 최적화 전 baseline(55–59s)과 일치.

---

## 2. G7 상태 고정

G7 = **DONE**. 더 이상 최적화 대상이 아니다.

- 근거: commit `d8e310283` (2026-08-25) — IR CAS-keyed same-run memoization (IR computation 2→1 패스).
- 보고된 효과: ~55–59s → ~34.93s (실측값이 repo 내부에 없는 점에 유의 — 커밋의 소스 변경이 결정적 근거).
- G7은 critical node(`verify-contract`) 내부의 **최소** 서브스테이지(59s / 633s ≈ 9%).
  실질적이지만 작은 개선 → 추가 파지 금지 (§8, §7: one iteration = one bottleneck).

---

## 3. Manifest

### 3.1 노드 스키마 (최소 필드 — 사용자 피드백 §1)

`duration, earliestStart, latestStart, slack, onCriticalPath, criticalPathContribution, status, actionable`

- `slack == 0` ⇒ `onCriticalPath` (계산 단순, duration과 기여도 혼동 금지).
- `criticalPathContribution` = critical path에 기여하는 drag. on-critical이면 = duration, off-critical이면 0.
- `repeatability`(stdev)는 **이번 WP에서 제외** — WP2의 variance baseline 측정 때 도입.

### 3.2 구조 필드 (구분 필수 — 사용자 피드백 §3)

| 필드 | 값 |
|---|---|
| `criticalPathMaxContainer` | **verify-contract** (≈633s) — container, 수정 대상 아님 |
| `largestActionableLeaf` | **G1 mutation oracle** (≈249s) — 실제 수정 대상 |

> ⚠️ 다음 WP에서 "verify-contract를 최적화"가 아니라 "verify-contract 내부의 G1 mutation oracle"을
> 최적화한다는 점을 명시적으로 고정한다.

### 3.3 노드 상세 (verify-contract 내 서브스테이지 — 순차 critical chain)

| Node | duration | slack | onCriticalPath | criticalPathContribution | status | actionable |
|---|---|---|---|---|---|---|
| G1 mutation oracle | ~249s | 0 | YES | ~249s | **NOT STARTED** | **YES** ← NEXT TARGET |
| G6+G4 (OCL/proof) | ~191s | 0 | YES | ~191s | BACKLOG | NO |
| G2 promotion semantics | ~134s | 0 | YES | ~134s | BACKLOG | NO |
| G7 proof-universe-lock-gate | ~59s | 0 | YES | ~59s | **DONE** | NO |

- `criticalPathMaxContainer` verify-contract `onCriticalPath=YES`, `status=COMPOSITE`.
- 위 4개는 `verify-contract` 내부에서 **순차 실행**되어 633s로 합산 → 각각 slack=0, on-critical.
  (전체 CI job DAG의 earliestStart/latestStart 포함 slack 전역 계산은 재현 도구가 필요하며,
  이 docs-only WP에서는 수행하지 않음 — 위 slack은 container 내부 순차 chain 기준.)

---

## 4. 기대 트리 (다음 세션 에이전트가 프로파일링부터 다시 시작하지 않도록)

```
CI wall / critical path
└─ verify-contract                       ~633s   (container, critical=YES, COMPOSITE)
   ├─ G1 mutation oracle                 ~249s   ← NEXT TARGET (NOT STARTED, actionable=YES)
   ├─ G6+G4 (OCL/proof)                  ~191s   (BACKLOG)
   ├─ G2 promotion semantics             ~134s   (BACKLOG)
   └─ G7 proof-universe-lock-gate          ~59s   (DONE)
```

---

## 5. Canonical data flow (drift 방지)

```
gate_history / CI logs  (raw evidence; 여기선 audit 문서 §17.1 실측)
        ↓  (thin projection — 당장은 수동 동결, 도구화는 필요 시)
CI Critical Path Manifest  ← 유일한 새 authoritative 출력
```

- 사람이 유지하는 두 번째 authoritative source(`ci_step_durations.json` 등)를 만들지 않는다.
- 숫자 출처: §17.1 실측 문서(단일). 여기 매니페스트에서 상세 프로비넌스를 유지한다.

---

## 6. Definition of Done (이번 WP)

- [x] 실측 증거 동결 (verify-contract=최대 container, G1=largest actionable leaf 재현)
- [x] `criticalPathMaxContainer`(verify-contract) ≠ `largestActionableLeaf`(G1) 분리
- [x] status: G7=DONE, G1=NOT STARTED, G6+G4/G2=BACKLOG 고정
- [x] 코드 최적화 없음 — WP는 매니페스트 동결로 종료
- [ ] 기존 gate/검증 회귀 없음 (본 문서는 docs-only, 코드 변경 없음)
- [ ] 신규 의존성 없음

---

## 7. 백로그 (다음 WP, 이번 범위 아님)

**WP2 = G1 mutation oracle optimization.** 여기서 처음 코드 수정이 들어감.

- 목표: "G1을 빠르게"가 아니라 — **249초 중 실제 critical-path wall을 만드는 비용을 측정하고,
  그중 가장 큰 결정론적 중복 연산을 제거한다.**
- 실측 힌트(동일 문서 line 995/1149): G1 harness(`tools/invariant_mutation_harness.sh`)가
  oracle `tests/unit/test_invariant_mutation_oracle.nim`을 `nim c -r`로 **6~7회** 재컴파일·재실행 →
  순수 compile+run ~69s. mutation-scoped 재컴파일은 이미 Nim 네이티브로 동작(line 1619)하나,
  oracle 재컴파일은 mutation마다 불가피(line 1612). WP2에서 결정론적 중복(예: mutation-independent
  상수 컴파일)만 제거 대상.
- 진행은 OptimizationTarget→Baseline Evidence→…→Verification→Updated Manifest contract로.
- G1 완료 후 재현 가능한 업데이트로 매니페스트를 갱신(다음 manifest 갱신 시점).
