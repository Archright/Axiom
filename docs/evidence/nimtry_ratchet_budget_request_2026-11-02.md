# nimtry ratchet 유지 · 기존 부채 감축 예산 — 인간 결정 요청서 (2026-11-02)

> **종류**: 인간 결정 요청서 (decision request). **이 문서는 결정을 대리하지 않는다.**
> 본 문서는 계약·정책·게이트 변경이 아니다 — `docs/evidence/` 기록 문서이며, 어떤 게이트도
> 본 문서를 소비하지 않는다. 사실·관측치·선택지의 나열만을 담는다(결정 유도 서술 없음).
> **Date**: 2026-11-02 · **Branch**: `docs/nimtry-budget-request` (worktree off `origin/main` @ `7975f3ebe`)
> **Scope**: 본 문서 1건 — `data/`·코드·게이트·레지스트리 수정 0건.
> **결정 권한**: D1·D2·D3 모두 **인간(제품·아키텍처 책임자) 전용**.
> **DEBT#512와의 관계**: 독립 산출물 — 병행 작성 중인 DEBT#512 결정 요청 문서를 전제하지 않고
> 대체하지도 않는다(§7).

---

## §0. 배경 — 재앵커(PR #1181)와 본 문서의 관계

- PR #1181(GitHub native MERGE `7975f3ebe`)의 커밋 `90604006e`는 측정 드리프트의 **재앵커**를
  수행했다 (커밋 본문 원문 기준):
  - `data/nimtry_baseline.json`: `bin/nimtry src/ --update-baseline` — total_violations
    **4222 → 4263** (순증 +41; 그중 **22건은 신규 SAFETY-language-ban test fixture** —
    PR #1178/#1179가 착지시킨 `.nimble`/`.rs`/`.llbc`/`.jsonl` fixture)
  - `data/debt_reduction_baseline.json`: `bin/debt_integrity_gate --update-baseline` —
    nimtry_violation_count / nimtry_active_violations **4092 → 4263**
  - `data/architecture_debt.json`: `bin/debt_engine --regen-arch` — canonicalSyntaxHash
    불일치 4건(entry [26][36][382][417]) 재계산 → WARN 0
- **재앵커는 감축이 아니다** (§6). 총량 4222→4263은 측정치의 정본 정합화이며 어떤 위반도
  해소하지 않았다.
- 재앵커의 부효과로 **STALE 10건이 노출**됐다: 이전에는 debt_integrity_gate Step 2(카운트
  불일치)가 fail-fast로 먼저 중단해 Step 5(마커 바인딩 검사)를 가렸다. 커밋 본문: *"was masked
  because Step 2 aborted first"* — 당시 open 29건으로 관측됐고, 이후 PR #1180이 DEBT#512를
  추가해 현재 open 30건이다.

## §1. 요청하는 결정 (3건 — 각각 독립)

| ID | 결정 | 질문 |
|---|---|---|
| **D1** | ratchet 정책 유지 확인 | nimtry baseline cap **4263 고정 + 신규 위반 증가 금지(ratchet)** 을 정책으로서 유지하는가 |
| **D2** | 감축 예산 | 기존 4,249건(active, 2026-11-02 실측) 감축의 **옵션·목표 수치·시점**을 무엇으로 할 것인가 |
| **D3** | STALE 10건 처리 | 증거 기반 close vs registration-class 예외 설계 vs 보류 — 어느 경로로 갈 것인가 |

세 결정은 서로를 전제하지 않는다. 선택지의 사실 근거는 §2(D1)·§3–4(D2)·§5(D3)에 있다.

## §2. D1 — ratchet 현행 메커니즘 (측정된 사실)

**메커니즘**: `data/nimtry_baseline.json`(version 2, total_violations 4263, warning 3879 /
error 384)은 위반 **SHA256 지문 집합**이다. `bin/nimtry src/`는 baseline에 없는 신규 지문이
관측되면 exit 1로 실패하며, `make check-arch`(Makefile:214–234)는 이 exit code를 그대로
게이트 판정으로 사용한다. 커밋 본문이 기록한 직전 상태의 실패 형태: `"FAIL 22 new violations"`
→ 재앵커 후 `"PASS — 4249 violations (debt anchored)"` exit 0.

**2026-11-02 실측** (worktree @ `7975f3ebe`, `bin/nimtry src/` — `make check-arch`와 동일
호출): exit 0 —

```
[ERROR] nimtry_cli: [nimtry] PASS — 4249 violations (debt anchored) (errors: 370, warnings: 3879, 14 resolved)
```

baseline(4263) 대비 **14건이 anchor 후 자연 해소**된 상태로 관측됐다(전부 error 등급:
384→370). 게이트는 해소분을 감축으로 처리하지 않고 "resolved"로만 표기하며 baseline을
자동 갱신하지 않는다.

**ratchet의 강제 지점 (측정)**:

| 경계 | check-arch(nimtry) 포함 여부 | 근거 |
|---|---|---|
| `make check-arch` / GATES_STATIC / `local-ci` / `verify-all` | **포함** | Makefile:39, 127, 134, 214 |
| pre-push PUSH_ADMISSIBILITY_GATES | **미포함** | Makefile:61 (14개 게이트 목록에 없음) |
| GitHub required 5 checks (admission-check, bsec-integrity, debt-registry-gate, generation-acceptance, axiom-operational-slice) | **미포함** | `ci-provider-router.yml:75–79` |

즉 현재 ratchet의 기계적 강제는 **로컬 make 경계**에 있고, push-admissibility와 CI required
경계에는 없다. (참고 사실: `bin/debt_integrity_gate`의 nimtry 카운트 검사(Step 2)도 별도
바이너리로, PUSH_ADMISSIBILITY_GATES에 없다 — 푸시 경계의 `check-debt`는 `bin/debt_engine
--validate`를 실행한다, Makefile:237–240.)

**baseline 갱신 경로**: `bin/nimtry src/ --update-baseline`(`src/gate/nimtry/nimtry_cli.nim:333`) —
일반 커밋으로 착지된다. 본 문서 작성 시점에 확인된 바, nimtry baseline에는 coverage ratchet의
Ed25519 서명 권한(`docs/evidence/ratchet_authority_closure_2026-10-07.md`)과 같은 서명 권한
메커니즘은 존재하지 않는다. 최근 갱신 이력: 2026-10-21 anchor(4222) → 2026-11-02 재앵커(4263).

**요청 사항 (D1)**: cap 4263 고정 + 신규 위반 금지를 **정책으로서 유지**할지의 확인.
- 유지 시 필요한 조치: 없다 — 게이트는 이미 그렇게 동작한다. 이 결정은 동작 변경이 아니라
  기존 동작의 정책 확정을 묻는 요청이다.
- 변경(완화·강화) 시: 그 형태(예: 갱신 권한 절차 도입 여부, 강제 지점 확대 여부)의 정의는
  인간 소관이며 본 문서는 선택지를 제시하지 않는다.

## §3. D2 — 감축 대상 군집의 측정된 분포 (baseline @ `7975f3ebe`)

총 4,263건 = warning 3,879(91.0%) + error 384(9.0%). 고유 파일 850개.

**규칙(class)별 상위** (`data/nimtry_baseline.json` 전수 집계):

| detail class | 건수 | 비율 |
|---|---|---|
| purity-new-code-must-be-func | 1,531 | 35.9% |
| effect-transitive-io | 700 | 16.4% |
| soc-surface-area (imports/exports/SLOC 초과) | 571 | 13.4% |
| safety-proc-purity | 443 | 10.4% |
| enforce-proc-purity | 181 | 4.2% |
| solid-ocp | 174 | 4.1% |
| feature-cardinality | 166 | 3.9% |
| effect-triple-annotation | 146 | 3.4% |
| ssot-type-duplication | 83 | 1.9% |
| safety-forbidden-patterns | 58 | 1.4% |
| 나머지 전체 (HYGIENE·FEATURE·SAFETY·SECURITY 등) | 210 | 4.9% |

**파일 집중도**: 위반 ≥10건인 파일은 **117개**로 **2,220건(52.1%)** 을 차지한다. 1건뿐인
파일은 299개다. 최상위 파일: `src/infrastructure/debt_audit/audit_rules.nim` 58,
`src/core/debt/debt_events.nim` 46, `src/core/contracts/z3_extraction.nim` 40,
`src/gate/gateway.nim` 37, `src/verification/obligation/canonical_verification.nim` 36,
`src/gate/quality_gate.nim` 36. (파일 필드가 빈 프로젝트 수준 규칙이 166건 있다.)

**참고 사실 — 정합성 해소 전례(감축 아님)**: `90604006e`는 architecture_debt canonicalSyntaxHash
드리프트 4건을 `bin/debt_engine --regen-arch` 정준 재계산으로 수 분 내에 WARN 0으로 정합화했다.
이는 "측정 드리프트" 클래스의 해소 경로다 — 정합화이지 위반 감축이 아니므로 D2 예산 산정에서
제외한다(§6).

## §4. D2 — 감축 예산안 옵션 (선택·조합·목표 수치·시점은 인간)

아래 수치는 "해소 시 총량 감소분"의 산술이며 달성 보장이 아니다. 옵션 간 배타성 없음.

### 옵션 A — fixture 언어-밴 클래스 (SAFETY-language-ban 36건, 전부 error)

- **성격**: 대상 전체가 Nim 소스가 아닌 파일이다. 확장자 분포(측정): `.nimble` 14, `.rs` 6,
  `.llbc` 4, `.yml` 7, `.jsonl` 2, `.py` 1, `.txt` 1, dir-level 1. 재앵커 신규 22건은
  float_acceptance nimble fixture 14 · rust probe fixture 6(`.llbc` 2 + `.rs` 4) · workflow
  jq contract `.jsonl` 2 (PR #1178/#1179 기원, `90604006e` 본문).
- **가능한 경로 (사실 나열)**: (i) 스캐너 대상 정책 변경 — `src/gate/nimtry/**` 코드 변경을
  수반하며 해당 표면은 push-admissibility의 FROZEN 분류 대상이다(인간 승인 절차 필요);
  (ii) fixture 파일의 위치·형식·확장자 변경 — `tests/` 측 변경; (iii) 현상 유지.
- **노력·위험 (측정된 것만)**: (i)는 정책 지점 1곳 + 재측정이나 동결 표면 절차 수반;
  (ii)는 fixture 경로에 의존하는 consumer의 존재 여부를 본 문서에서 측정하지 않았다.
- **감축 수치 후보**: −36 (총량의 0.8%; error 384 중 9.4%).

### 옵션 B — 기계적 어노테이션·소규모 패턴 군집

- **구성 (측정)**: effect-triple-annotation 146 + enforce-proc-purity 181 = **327(7.7%)**;
  소규모: HYGIENE-when-isMainModule 29, SAFETY-no-main-module-in-src 21, SAFETY-bare-except 15,
  SAFETY-include-guard 9, SAFETY-no-try-in-no-raise 6, SAFETY-hardcoded-home 4,
  EFFECT-pragma-consistency 4, SECURITY-weak-hash 2, SAFETY-duplicate-import 1,
  SAFETY-unsafe-parse 1 (소규모 합 92).
- **성격**: 함수 단위 pragma/어노테이션 보강 또는 국소 패턴 치환이 지배적인 클래스 — 항목당
  변경 단위가 작다.
- **제약 (사실)**: purity/func 관련 변환에는 GUARDIAN §11의 Mass Conversion Audit가 적용된다 —
  per-function 부작용 감사 없는 일괄 변환은 금지되며, 물리적 부작용 보유 함수의 func 전환은
  계약 위반이다(진입 난이도가 항목 수에 비해 균일하지 않은 이유).
- **감축 수치 후보**: −29 (HYGIENE 1종) / −146 (triple-annotation) / −327 (어노테이션 2종 합) /
  −92 (소규모 SAFETY·HYGIENE 합) — 조합은 인간.

### 옵션 C — 파일 집중 군집 (구조 리팩터링)

- **측정**: ≥10건 파일 117개 = 2,220건(52.1%). 최상위 6개 파일만 253건(§3 표).
- **성격**: 모듈 분할·표면 축소형 — 위반 밀도 상위 파일의 구조 개선이 수반되는 클래스.
- **제약 (사실)**: 동작 변경 리스크와 레이어 경계(RL-14.x) 회귀 리스크가 존재한다. AGENTS.md
  §2.2-9(기회적 리팩터링 금지)·§0.12(제품 계약 정당화)에 따라 이 클래스의 감축 작업은 계약과
  연결된 범위에서만 착지 가능한 구조다. 파일별 공수는 본 문서가 측정하지 않았다.
- **감축 수치 후보 (산술 상한)**: top-1 −58(1.4%) / top-6 −253(5.9%) / top-117 −2,220(52.1%).

**선택 절차**: 인간이 옵션·목표 수치·시점을 결정한다. 결정의 기록 위치·형식도 인간이 정한다.
본 문서는 어느 옵션도 권고하지 않는다.

## §5. D3 — debt_integrity_gate STALE 10건 (측정 사실 + 처리 옵션)

**측정** (2026-11-02, `bin/debt_integrity_gate`, worktree @ `7975f3ebe`): **exit 1** —

```
[INFO] nimtry — Active Violations: 4249 / Historical Baseline Cap: 4263
[INFO] Registry: 243 entries (30 open, 0 accepted)
[INFO] Code: 23 {.axiomDebt.} markers found
[ERROR] STALE: … is open in registry but has no {.axiomDebt.} marker  × 10
[ERROR] 10 stale debt(s) — FAIL
```

WARN 라인은 0건이다(재앵커로 WARN 4종은 소실). 실패 사유는 STALE 10건뿐이다.

**STALE 10건 명세** (레지스트리 조회, 전부 `status: open`):

| ID | category (요약) | source | files (요약) |
|---|---|---|---|
| DEBT-CI#003 | CI/Pipeline Health | storage-retention-workstream-G1 (2026-10-10) | `.github/workflows/runner-pool-acceptance.yml` |
| DEBT#432 | CI Enforcement / Test Wiring | productization_contract_preservation_audit (2026-08-23) | `Makefile` |
| DEBT#472 | Verification Semantics | n7_runtime_investigation (2026-10-01) | `.github/workflows/certificate-mint.yml` |
| DEBT#496 | Verification Semantics / IR Translation | void-discard investigation (2026-10-08) | `src/core/trusted/*` 외 5파일 |
| DEBT#504 | Verification Semantics / Authority Split | authority-split sweep (2026-10-12) | `src/verification/*` 외 5파일 |
| DEBT#505 | Architecture / Replay-Lane Partition | nimtry dry-duplicates anchoring (2026-10-13) | `src/verification/*` 2파일 |
| DEBT#506 | Theater/Unenforced Claim | theater_audit (2026-10-23) | `Makefile`, `.github/workflows/*` |
| DEBT#507 | Verification Semantics / Exit-Code Fail-Open | theater_audit (2026-10-23) | `Makefile`, `src/core/utils/*`, `src/cli/*` |
| DEBT#509 | Theater/Fail-Open | theater_audit (2026-10-27) | `ci/checker.mk`, `Makefile`, `config.nims`, `src/cli/*`, `src/core/crypto/*` |
| DEBT#512 | Architecture / SSOT | audit (2026-11-01, PR #1180) | `src/gate/runners/debt_integrity_gate.nim`, `data/debt_schema.json` |

**구조적 사실**: 10건 중 6건(DEBT-CI#003, #432, #472, #506, #507, #509)과 #512의 파일 표면은
`Makefile`·`ci/checker.mk`·`.github/**`·`src/gate/**` 등 push-admissibility가 동결·보호로
분류하는 표면과 겹친다(`90604006e` 본문의 FROZEN 목록; `human_scanner_audit_handoff_2026-11-02.md`
§7에는 `src/gate/**`에 대한 3줄 변경조차 거부된 전례가 기록돼 있다). "코드에 마커를 추가"하는
경로는 이 표면들에서 절차적으로 제약된다.

**처리 옵션 (둘 다 `data/debt_registry.json` + 게이트 층 소관 — 본 슬라이스에서는 수정하지
않음, 이 문서의 범위 밖)**:

- **옵션 A — 증거 기반 close**: 각 항목의 서술 내용이 `7975f3ebe` 기준으로 여전히 성립하는지
  항목별 검증 후, 해소가 확인된 항목만 resolution 근거와 함께 close한다. 게이트 시맨틱 변경이
  없다. 본 문서는 개별 항목의 검증을 수행하지 않았다 — 각 항목의 검증 비용·결과는 미측정이다.
- **옵션 B — registration-class 예외 설계**: 마커 바인딩이 구조적으로 성립하지 않는 등록
  클래스(예: CI-워크플로 부채, 동결 표면 SSOT 부채)를 레지스트리 스키마와 게이트 시맨틱에
  명시적으로 정의한다. 게이트 시맨틱 변경을 수반하며 AGENTS.md §2.5(CI self-bootstrap)·§2.6
  (변경 불변조건 프로토콜)의 적용 대상이다.
- **옵션 C — 혼합/보류**: A와 B의 항목별 혼합, 또는 현상 유지도 선택지다.

**강제 지점 사실**: STALE 10건의 exit 1은 CI required 경계와 무관하다. CI의 debt-registry-gate는
`bin/debt_engine --validate`를 실행하지(`.github/workflows/debt-registry-gate.yml`) `bin/debt_integrity_gate`를
실행하지 않는다 — PR #1180·#1181이 STALE 존재 하에도 랜딩된 구조적 이유다. 즉 D3는 로컬/수동
실행 경계의 신호에 대한 결정이다.

## §6. 분리 원칙 (요구사항 3)

1. **'신규 위반 통제(ratchet)'와 '기존 부채 감축(예산)'은 별개 결정이다** — 하나가 다른 것을
   대신하지 않는다.
   - D1(ratchet 확정)만으로 감축 의무가 발생하지 않는다.
   - D2(감축 예산 승인)만으로 신규 위반 허용이 발생하지 않는다.
2. **재앵커는 현황 정합화이지 감축이 아니다**: `90604006e`는 측정치를 4263으로 갱신한 것이며
   위반을 하나도 해소하지 않았다. 이후 D2의 질문은 "4,263(측정상 4,249) 중 얼마를, 어떤
   순서로, 어떤 위험 수용 하에"이다.
3. baseline 갱신(`--update-baseline`)과 감축(위반 해소)의 구분에도 동일 원칙이 적용된다 —
   갱신은 정합화 절차이며 감축 성과로 계수되지 않는다.

## §7. 결정 권한·절차 (요구사항 5)

- **결정 권한**: D1·D2·D3의 권한은 **인간(제품·아키텍처 책임자) 전용**이다. 에이전트·자동화는
  이 결정을 대리할 수 없다.
- **본 문서의 지위**: 계약·정책 변경이 아니다. `docs/evidence/`의 기록 문서이며 어떤 게이트도
  소비하지 않는다. 결정 착지에 필요한 계약·정책·게이트·레지스트리 변경은 **별도 변경집**으로
  수행된다 — 본 문서는 그 변경집을 예고하지 않는다.
- **DEBT#512와의 독립성**: 본 문서는 DEBT#512 결정 요청 문서(병행 작성)와 독립 산출물이다.
  §5의 표에 DEBT#512가 포함된 것은 STALE 10건의 측정 사실 나열일 뿐이며, DEBT#512의 개별
  결정을 본 문서의 D3가 대체하지 않는다.
- **결정 기록**: 방법(본 문서 갱신, 별도 결정 문서, 이슈 등)과 시점은 인간이 정한다.

## §8. 실측 기록 (Completion Evidence — command → observation → exit)

측정 환경: 격리 worktree @ `7975f3ebe`(origin/main), 바이너리 3종 모두
worktree 내 재빌드(Nim 2.2.10). 측정 일시 2026-11-02.

| # | 명령 | 관측 | exit |
|---|---|---|---|
| 1 | `bin/nimtry src/` (= `make check-arch`의 본체, Makefile:217) | `PASS — 4249 violations (debt anchored) (errors: 370, warnings: 3879, 14 resolved)` | **0** |
| 2 | `bin/debt_integrity_gate` | nimtry Active 4249 / Cap 4263 정렬, WARN 0건, Registry 243 (30 open, 0 accepted), Code 23 markers, **STALE 10건 ERROR** → `10 stale debt(s) — FAIL` | **1** |
| 3 | `bin/debt_engine --validate` (= CI debt-registry-gate와 동일 명령) | `Checks: 1531 total, 1531 passed, 0 failed`, `Metric evaluation: 3 PASS, 1 DRIFT`(nimtry_violations projection=0 vs ledger 1), `All debt validation checks passed` | **0** |

비고 (3번): PR #1181 커밋 본문의 기록은 "1532/1532 PASS, metric 6 PASS / 0 DRIFT"다. 본 실측의
1531 checks·1 DRIFT 차이는 로컬에서 evaluator 바이너리 미빌드에 따른 환경 차로 관측됐다
(`layer_violations: evaluator error`, `effect_violations: evaluator binary unavailable
(bin/effect_contract_projection)` 노트). DRIFT 항목은 advisory이며(`Makefile:464–465` — "Part D
budget metrics are advisory (DRIFT never affects the exit code)") 두 실행 모두 exit 0으로
동일 판정이다.

STALE 10건 재확인 목록(§5 표와 동일): DEBT-CI#003, DEBT#432, DEBT#472, DEBT#496, DEBT#504,
DEBT#505, DEBT#506, DEBT#507, DEBT#509, DEBT#512.
