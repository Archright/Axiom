# Axiom Productization Start Readiness — H1 Fresh Evaluation (2026-08-18)

> Subject: commit `0124e86161e123f30f22a5e9f10b0a52b0ebb480` (H1) + fresh evidence R1~R8
> Evaluator: `tools/readiness_evaluator.nim` (pure decision core; verdict is not manually promoted)
> Policy: `config/readiness_policy.json` (H1)
> Decision artifact: `data/readiness/decision.2026-08-18.r4.json`

---

## Verdict

**CONDITIONAL GO**

## One-line Decision

H1에서 핵심 제품 경로(`ax prove` → canonical result(인증서 v3) → provenance artifact → report)가 실제로 실행·결정적으로 닫혀 있고, evaluator가 8건의 fresh evidence를 모두 유효하게 수용해 R1~R6·R8=PASS, 유일하게 R7(비-critical VKD 0.0/23)만 FAIL로 판정했으므로, **VKD 개선을 첫 vertical slice의 조건으로 하고 제품화를 시작**해도 된다.

## Governance State

```text
PRODUCTIZATION ENTRY:     CONDITIONAL GO
READINESS EVALUATOR:      CONDITIONAL GO  (conditions: ["R7=FAIL"])
B4 recovery:              완료 (B4-A prove crash 수리 / B4-B legacy 19건 archive + v3 신규 생성 / B4-C commit path 정상)
bypass 사용:              없음
```

---

## Evaluator Trace (재현 가능)

```bash
./bin/readiness_eval \
  --policy config/readiness_policy.json \
  --evidence-dir data/readiness/evidence \
  --repo-head 0124e86161e123f30f22a5e9f10b0a52b0ebb480 \
  --tree-digest sha256:0d216005648ec1ef3e192a4ca2a0abc8369e9bcf \
  --working-tree-clean true \
  --toolchain-nim 2.2.10 --toolchain-z3 4.13.3 --toolchain-lean 4.29.0 \
  --eval-time <ISO> --out data/readiness/decision.2026-08-18.r4.json
```

- bundle files: 8 valid, 0 invalid
- invariantStates: R1 PASS / R2 PASS / R3 PASS / R4 PASS / R5 PASS / R6 PASS / R7 FAIL / R8 PASS
- verdict: `CONDITIONAL GO`, conditions: `["R7=FAIL"]`
- policyHash `1d08729c…`, bundleDigest `fa7c6452…`, decisionDigest `0bcb25bd…`

## Evidence

| ID | Status | Evidence (H1 fresh) | Impact |
| -- | ------ | ------------------- | ------ |
| R1 | PASS | `ax prove` exit 0 × 3 runs, no crash/SIGSEGV ('sons' access / literal-node 접근 경로 수리됨), `[VERIFIED]`+cert 작성; surface: `ax prove`/`ax report` 존재, 도큐된 contract 명령(document·bridge) | WORK ITEM: `ax status` 미구현 |
| R2 | PASS | engine capability real: normalizeMaxWorkers → [VERIFIED], Proof Summary 21/5/1/15, negative control(미존재 target fallback) 기록, IR FAIL(firstBoolCore psFail)은 요약에 노출되고 은폐 안 됨; dual evidence(certGreen) hard-gate enforced | WORK ITEM: 폴백 검증 수준 문서화 |
| R3 | PASS | canonical certificate가 두 독립 runs에서 sha256 동일(`ef5d34a3…`), identityDigest 재현; canonicalInputHash(e46bbe…), configHash(scope hash `491751ab…` 3회 동일), solverIdentity z3_4.13.3, cachePolicy `.axiom/proof_cache` deterministic salted key, canonicalExecutionFingerprint `dea851d3…` | WORK | report는 warm-state 결정·cross-state 상태포함 — 보고서 projection 계약 필요 |
| R4 | PASS | v3 certificate 10필드: claim/attestation/inputHash/toolchainIdentity/solverInvocation/solverInputDigest/solverResultDigest/provenance{journalCommitId, certificateDigest}/identityDigest/schemaVersion — 전원 존재·비어있지 않음; journalCommitId `3b39f97c…` → `data/trusted/journal/` 존재 | PASS(성과) |
| R5 | PASS | exit codes: success 0(observed)/verification-failure 1(observed at report)/invalid-input 1(observed, unknown-option)/internal 2(contract), mutual distinct; JSON schema `axiom.report.v1`; help surface는 `ax help` | WORK: invalid-input 코드가 계약 3과 drift — 정렬 필요 |
| R6 | PASS | `git status` before/after 스냅샷 diff empty; runtime output은 전부 gitignored(build/, .cache/) + /tmp | INSTALL |
| R7 | FAIL | measured VKD = 0/23 = 0.0 (baseline SSOT `data/baseline.json`); claimed/emitted: vkd↔vkd (sub-promotion 없음) → rate 이하로 FAIL | **CONDITION** (비-critical) |
| R8 | PASS | vertical slice 단계별: input_canonical(신규 CanonicalInput type 정의 대상), cli_entry(실행 가능), deterministic(실행 가능, semantic line 실제로 동일), verification(실행 가능), canonical_result(실행), artifact(형, v3 cert 실재), report(부분 실행 — exit 1 상태에서 partial JSON) / assessment GO_feasible | WORK: input_canonical 구현 |

## Productization Start Blockers

없음 (항목: 핵심 execution path crash 없음 · canonical result artifact 없음 · verification output 부재 · 근본 repro 실패가 현재 H1에서 관찰되지 않음).

## Productization Work Items (vertical slice 순서)

1. **Canonical Input 계약 정의** — `CanonicalInput` type/스키마를 `src/core`에 추가 (R8-001). 현재 `canonicalInput` 길이 0 → slice 최상단을 닫는 첫 품목.
2. **R4 provenance 계약 ratify** — Certificate v3 스키마(19필수 필드)를 `docs/spec/provenance_contract_v3.md`로 고정(이미) + certificate generator와 명시적 바인딩 확인(이미 v3에서 `writeCertificateFromUapResult` 경로 검증 완료).
3. **`ax status` 구현** — primary command로 제품 계약에 필수 (R1 documented gap).
4. **exit-code 정렬** — 계약에서 invalid input=3, 실제 1 → CLI에서 분류 정렬 (R5 INC-001).
5. **report determinism 계약** — report를 canonical certificate의 projection으로 정의(실행 전 상태는 metrics가 아닌 canonical 필드로만), cross-state 비결정을 문서화.
6. **VKD 0.0→ slice 성공 기준 달성** — VKS 23개 중 최소 1~2 대상 canonical dual verification (R7 조건 해소 후 GO 진입 조건).

## Post-Start Debt

- report 애플리케이션(부분 output, exit 1) 안정화 — 첫 slice 이후.
- IR pipeline FAIL 셈플(`firstBoolCore psFail, smNone`) — 검증 coverage 확대는 post-handover.
- Lean 생성 syntax 오류 셈플 — separate from VKD.
- CLI `--help` 플래그 미지원(subcommand) — `ax help`로 문서화된 대안만.
- (정리형) build 아티팩트 (`tmp/`는 마이그레이션에서 삭제됨).
- Exit-code drift(3→1)는 별도. 위로 정리.

## Required First Vertical Slice

```text
input         → (신규) CanonicalInput DSL/JSON 스키마 정의 (Work Item 1)
canonicalization → srcHash 등 identity를 CanonicalInput으로 standard화
prove         → ax prove --input <canonical-input> (기존 배터리 경로 재사용)
canonical result → v3 certificate (identityDigest로 고정, 이미 구현)
artifact      → build/certificates/ + journal 기록 (이미 구현)
report        → ax report → canonical certificate projection (report 작성 조건: certificate 기준으로만)
```

최소 변경량:
- `src/core/…/canonical_input.nim` (new, ~60 line)
- `src/cli` — `ax prove --input` + `ax status` 추가
- CLI exit code 정렬(2군데)
- evidence refresh → evaluator 재평가 → slice gate

## Final Answer

Axiom은 현재 제품화 시동을 걸어도 된다. 핵심 이유는 평가자가 8개의 fresh H1 evidence를 모두 수용하고 R1~R6·R8이 PASS(T7만 비-critical VKD FAIL)를 산출했으며, `ax prove`가 crash 없이 canonical certificate v3를 생성하는 핵심 실행 경로가 존재하기 때문이다.