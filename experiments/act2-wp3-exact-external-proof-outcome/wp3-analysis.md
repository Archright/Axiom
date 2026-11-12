# WP3-a — Exact External Proof Outcome — Analysis

EXPERIMENT_ID: `act2-wp3-exact-external-proof-outcome`
PROJECT_UNDER_TEST: `nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859`
AXIOM_REVISION: fresh binary build from working tree (`bin/ax`) at AXIOM_STATE_DIR seed
PARENT_MILESTONE: WP2 ingress fix (global_symbol_graph export-marker fix) 적용됨
SCOPE: `stew/base36.nim::decodedLength` 단일 external symbol의 exact-proof-outcome 확정

> 이 문서는 code 수정 없는 분석 보고서다. WP3-a에서는 Z3/Lean 실행 결과를
> 신뢰 가능한 taxonomy로 확정하는 것이 목표이며, 어떤 코드도 변경하지 않는다.

---

## Question

`stew/base36.nim::decodedLength` 하나를 exact-qualified `--target`으로 실행했을 때,
실제 Z3/Lean 결과(outcome)는 정확히 무엇이며, 그 결과는 어떤 taxonomy로 분류되는가?

WP3-a는 "검증 성공 여부"가 아니라 "**외부 subject symbol의 실제 proof outcome을
신뢰 가능한 결과 분류로 정직하게 확정**"하는 것을 목표로 한다.

---

## Context

- **Subject revision**: `nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859` (변경 없음, immutable)
- **Axiom**: `.` working tree에서 빌드된 fresh `bin/ax`
- **실행 명령**:
  ```
  cd nim-stew && AXIOM_STATE_DIR=/tmp/wp3a_state \
    timeout 300 ./bin/ax \
    prove --project . --target "stew/base36.nim::decodedLength" --limit 1
  ```
- **State seed**: `AXIOM_STATE_DIR=/tmp/wp3a_state` (Axiom repo `data/` 복사 — verification_scope.lock 등 포함)
- **결과 로그**: `/tmp/wp3a_run.log` (exit=2)
- **실행 환경**: Linux, Nim toolchain (ax 바이너리 실행)

---

## Procedure

1. baseline 상태 확인 (`nim-stew git status --porcelain` → `?? data/` untracked, 트랙된 파일 무변경).
2. 위 exact-qualified 명령으로 실행.
3. 로그 전 구간을 evidence로 추적: topology → `--target` → frontier eligibility → IR extraction → classify → tautology gate → UAP gate → Z3 → persist → proof_universe commit.
4. 각 단계의 정확한 `file:line` 근거를 수집.
5. 결과를 AGENTS.md §14 Reporting Contract에 따라 문서화.

---

## Current Runtime Path (actual, evidence-based)

실행 로그 `/tmp/wp3a_run.log`를 따라간 실제 canonical path:

```
ax prove --project . --target "stew/base36.nim::decodedLength" --limit 1
  │
  ├─ analyzeTopology → topology: 86 files, 931 candidates
  ├─ --target filter: 1 node(s) match 'stew/base36.nim::decodedLength'   (E1 PASS)
  ├─ frontier eligibility gate: excluded 325 non-proof-candidate; eligible=1
  ├─ phase-10 IR extraction: 6/230 entries (limit=1)
  │     └─ decodedLength → vtSmtNative (simple bitvec/bool operations)
  ├─ T3 Tautology Check → REJECT  [ir_pipeline_runner.nim:858-878]
  │     └─ checkInvariantVacuity(preConditions) → tcTautology  [ax_tautology.nim:43-50]
  ├─ IR pipeline FAIL: decodedLength status=psError (solverMethod=smNone, pkNone)
  ├─ loop_driver: Verification-Gate: UAP produced 0 results (requests=1)
  ├─ PERSIST FAIL: 1 promotable certificate(s) failed canonical promotion
  ├─ done: verifiedRatio=0.0000, verified=0/41
  └─ [AXIOM TRUST] proof_universe commit recorded: 3ab50cc...
        └─ ⚠ subject CWD에 tcVerifiedProof journal 작성  (BLOCKER, 아래 §Root Cause 3)
```

**핵심 사실**: 실제로 호출된 obligation extraction은 IR pipeline을 통해
`decodedLength`에 대해 정확히 **1개의 유일한 auto-derived obligation**(div-by-zero guard)을
생성했지만, 이것이 **tautology(공리적)**로 판정되어 T3 gate에서 reject되었다.

---

## Root Cause Analysis

### Root Cause 1 — decodedLength의 유일한 obligation은 공리적(tautological)이다

`stew/base36.nim:57-60`:
```nim
func decodedLength*(btype: typedesc[Base36Types], length: int): int =
  return (length * 179) div 277
```

- 유일한 division operator는 `div 277` (상수 divisor).
- `synthesizeContracts` (`src/core/trusted/contract_synthesis.nim:306-313`)가
  `collectDivisionGuards`를 preConditions에 추가 → `277 != 0` = **항상 참(tautology)**.
- loop 없음, array/string index op 없음, return type은 plain `int`(BV64) →
  overflow/result-range obligation이 **자동 생성되지 않는다** (product limitation).
- 따라서 유일하게 생성된 obligation이 공리적이어서 `checkInvariantVacuity`가
  `tcTautology`를 반환한다 (`src/verification/ax_tautology.nim:43-50`).

### Root Cause 2 — T3 gate가 파이프라인을 조기 종료시켜 Z3/Lean 미도달

`src/verification/batch_uap/ir_pipeline_runner.nim:858-878`:
```nim
# ── T3: Tautology Check ──────────────────────────────────────────────
if funcDef.preConditions.len > 0:
  let tautResult = checkInvariantVacuity(funcDef.preConditions)
  if tautResult == tcTautology:
    logWarn(... "[tautology] ... invariant is tautological — REJECT")
    return IrPipelineResult(
      ...
      verification: vrt.makeInconclusive(vrt.rkNoProperty),
      success: false,
      ...
    )
```

이 `return`은 `runIrPipeline` 전체를 조기 종료시켜 이후 T5, BMC, CHC, SMT 단계에
**도달하지 못한다**. 로그에서 `solverMethod=smNone`, `provenance=pkNone`으로 확인 —
Z3 verification SMT가 발행되지 않았다. `Verification-Gate: UAP produced 0 results (requests=1)`
(`loop_driver.nim:1217`)가 이를 받는다.

### Root Cause 3 — trust journal routing defect (BLOCKER)

`src/verification/proof_universe_commit.nim:235`:
```nim
let commitRes = commitVerification(currentDir, tc)   # currentDir = subject CWD
```

- `commitVerification` (`src/core/trusted/trust_commit.nim:332-349`)는
  `journalDir(baseDir) = baseDir / "data" / "trusted" / "journal"`에 쓴다.
- **현재 실행은 subject CWD(`nim-stew`)를 baseDir으로 사용**하므로
  `nim-stew/data/trusted/journal/3ab50cc....json`이 생성됨 — **subject 오염** (E7 FAIL).
- contrast: `commitCertificateVerification` (`trust_commit.nim:222-233`)는
  `repoRootForPath(baseDir)`로 routing하는데, `commitVerification`은 그러지 **않는다**.
- WP2가 graph I/O routing(F2)은 수정했지만 이 line-235 hook은 수정하지 않았다.
- semantic 오류: vacuous 결과인데 `kind=tcVerifiedProof` claim을 기록함.
  (`3ab50cc*.json`: `"kind":"tcVerifiedProof"`, `"solverInvocation":"proof-universe-lock:v33"`, graphSnapshot 623 symbols)
  → 이는 evidence integrity(AGENTS.md §8)와 subject immutability(§2) 위반.

> **BLOCKER로 분류** — 별도 work-package 필요. 이번 WP3-a에서는 코드 수정을 하지 않고 분석만 기록한다.

---

## Findings 요약 (3개 분리)

1. **(a) decodedLength vacuous** — 정당한 taxonomy. 상수-divisor로 인해 유일한 auto-derived obligation이
   공리적이라 Z3/Lean에 진입하지 못한다. **코드 수정 불필요** — subject의 특성.
2. **(b) trust journal routing defect** — **BLOCKER**. `proof_universe_commit.nim:235`가 subject CWD를 사용하고,
   `commitVerification`이 `repoRootForPath`로 routing하지 않아 subject가 오염됨. 별도 work-package 필요.
3. **(c) --target exact-qualified 동작** — E1 PASS. `--target "stew/base36.nim::decodedLength"`이 정확히 1 node만
   match하는 것을 확인. 이는 positive finding.

---

## 결론 (조심스러운 표현)

> External subject symbol이 verification universe에 올바르게 admission되었다
> (`--target` exact filter, frontier eligibility, obligation 생성).
> 그러나 선택된 golden symbol은 상수-divisor로 인해 유일한 auto-derived obligation이
> 공리적(tautological)이어서, Z3/Lean 검증은 **정당한 Vacuous 분류**로 종료되었다.
> Z3/Lean outcome은 존재하지 않는다(미도달).

---

## Next Experiment (제안 — 실행 아님)

- 대상: `stew/base36.nim::encode` (loop/conditional 존재 → non-vacuous obligation 가능).
- 명령: `cd nim-stew && AXIOM_STATE_DIR=... ax prove --project . --target "stew/base36.nim::encode" --limit 1`
- 전제: **trust journal routing BLOCKER가 먼저 해결되어야** subject가 오염되지 않는다.
- golden-symbol 교체 금지는 *같은 실험 내* swap 제한이지, *다른 실험에서 다른 symbol 선택*은 허용
  (다른 실험 목적이므로).
