# WP4-h-2 — Intrinsic Obligation → SMT Lowering Localization

실험 ID: `act2-wp4h2-lowering-localization`
페이즈: ACT-2.3 / WP4-h-2
성격: **read-only** 능력 경계 국소화 (코드 수정 없음, production API 호출 없음)

---

## Question

Anchor #1(`stew/bitops2.nim::getBitsBE`)에서 이미 생성된 intrinsic safety obligation
`okSafetyDiv(resultBits != 0)`를 **canonical SMT proof goal로 결정론적으로 낮출(lower) 수 있는가?**

핵심은 "무엇을 고칠지"가 아니라 **어느 단계에서 lowering이 끊기는지**를 확정하는 것이다.
판정 프레임(사용자 지정):
- **A**: lowering 가능 → 현재 구조적 sieve/SMT adapter가 문제 → generic fix
- **B**: lowering 자체가 의미적으로 불가능 → IR semantic representation capability 문제
- **C**: proposition 자체가 잘못 생성 → intrinsic obligation synthesis 문제

---

## Context

- **Subject (PROJECT_UNDER_TEST)**: nim-stew @ revision `c75502ceedb5ed2a37b7b5e4744fc71313682859`
- **Axiom**: 작업 트리 `.`
- **Configuration**: Axiom 기본 v4 (변경 없음)
- **Toolchain identity**: Nim 2.2.10
- **Probe**: `experiments/act2-wp4h2-lowering/wp4h2_lowering_localization.nim`
  (아래 probe/src 사본, 빌드 바이너리 `/tmp/wp4h2_lowering_bin`)

---

## Scope

- 대상 symbol 2개:
  - Anchor #1 `stew/bitops2.nim::getBitsBE`
  - rank-2 비교 `stew/base36.nim::decodedLength`
- 각 대상에 대해, 동일한 canonical obligation pipeline을 거쳐:
  1. IR materialization
  2. canonical obligation generation (P3, `generateCanonicalObligations`)
  3. production SMT lowering (`irToSmtScript`)
  4. existing non-gating lowerer (`irToSmtWithObligations`)
  5. 생성된 script 또는 script에 끼워진 predicate의 **z3-executability 정적 판별**
  6. canonical predicate → IRExpr 역파싱 시도 (`parseIRExpr`)
- 제외: 전체 nim-stew sweep, Z3 실행, Lean, KAA, TrustCommit, Track B debt, Axiom 코드 수정.

---

## Procedure

read-only probe (`axiomLayer "tools"`, production API 미호출)를 3회 독립 실행하고
byte-identity를 확인했다.

```
nim c -d:release -o:/tmp/wp4h2_lowering_bin experiments/act2-wp4h2-lowering/wp4h2_lowering_localization.nim
for i in 1 2 3:
  /tmp/wp4h2_lowering_bin <subjectRoot> /tmp/wp4h2_out/run$i
md5sum run*/lowering-localization.json   # 3회 동일 확인
```

probe의 측정 funnel:
```
Intrinsic obligation  ->  kind / subject / predicate(canonical form) / derivationRule / provenance
Canonical proposition ->  predicateNonEmpty?
SMT expression        ->  irToSmtScript (production, postConditions-gated)
                          vs irToSmtWithObligations (non-gating, existing)
SMT script            ->  empty / non-empty, per path
                          + 정적 SMT-LIB2 실행성(spurious 연산자 검출)
Canonical→IRExpr      ->  parseIRExpr 역파싱 성공/실패
```

---

## Result

두 대상 모두 **byte-identical 3회 결정론적** (md5 `f75cba8315abac464f3c30d5681bef41`).

### getBitsBE (Anchor #1) — canonical 실행 결과

| 측정 | 값 |
|---|---|
| IR available | `true` |
| ogr kind | `ogrGenerated` |
| canonical obligation | `okSafetyDiv` / `resultBits ≠ 0` / `uoNot(boEq(lit(0),var(resultBits)))` |
| predicate non-empty | `true` (symbolic, living var) |
| preConditions before/after synth | 0 / 1 |
| postConditions before/after synth | 0 / 0 |
| **production SMT (`irToSmtScript`)** | **len 0 → empty** |
| non-gating (`irToSmtWithObligations`) | len 104 → non-empty |
| script 내용 | `(set-logic QF_BV)\n(set-option :rlimit 30000000)\n(assert uoNot(boEq(lit(0),var(resultBits))))\n(check-sat)` |
| **script z3실행성** | **`false`** — `uoNot/boEq/lit(/var(` 그대로 끼워짐 |
| canonical→IRExpr 역파싱(`parseIRExpr`) | **실패** (`reverseParsed=false`, `consumedPrefix=""`) |

### decodedLength (rank-2) — 동일 패턴

동일 observation. predicate `uoNot(boEq(lit(0),var(unknown)))`, subject `unknown ≠ 0`.

---

## Evidence

- Canonical artifact: `experiments/act2-wp4h2-lowering/canonical/lowering-localization.json`
- 결정론성: `runs_v4/run{1,2,3}/lowering-localization.json` (3회 byte-identical)
- Probe source: `experiments/act2-wp4h2-lowering/probe/src/wp4h2_lowering_localization.nim`

### 코드 경로 확정 (probe 외 보조 근거)

1. **empty SMT 직접 원인** — `src/core/trusted/private/ir_to_smt_chunk3.nim:257`
   `if f.postConditions.len == 0: return ""` — production `irToSmtScript`가 postConditions만 보고 분기.
   `getBitsBE`는 postConditions==0이므로 항상 empty.
2. **disconnect** — `src/verification/batch_uap/ir_pipeline_runner.nim:931`
   production은 `irToSmtScript(funcDef, ...)`만 호출. P3의 `ogr`(canonical obligation)은 이 호출에 **전달되지 않음**.
3. **TheaterGuard** — `ir_pipeline_runner.nim:939`
   `if smtScript.len == 0 and ogr.kind == ogrGenerated` → `rkObligationIllFormed`로 fail-closed.
   production의 empty-SMT는 이 경로에서 정확히 감지됨 (의도된 보호, 숨기지 않음).
4. **dangling lowerer** — `ir_to_smt_chunk3.nim:287` `irToSmtWithObligations*` 존재,
   production call site **0개** (전 소스 grep: 정의 1, 호출 0). orphaned.
5. **두 직렬화 체계 불일치** —
   - `serializeIRExpr`/`parseIRExpr`(axiom_ir.nim): 문법 `L(`, `V(name:T)`, `LET(`, `IF(`, `CASE(`.
   - `canonicalizePredicate`(obligation_types.nim): 문법 `uoNot(`, `boEq(`, `lit(`, `var(`.
   - canonical obligation의 `predicate` 문자열은 **후자**이고, **전자로 역파싱 불가능** (probe 실증).
   따라서 canonical predicate를 IRExpr로 되돌리는 경로 + `irExprToSmt` 파이프가 **현재 소프트웨어에 존재하지 않음**.

---

## Classification

**`A2-script-pocketed-but-not-z3-executable-no-term-lowering`**
(canonical 분류 코드의 정밀 하위; 사용자 프레임 A/B/C 관점에서 아래 Interpretation 참조)

이것은 기존 3분류(A/B/C)가 놓친 제4의 경계 지점이다:
- script 문자열 자체는 **non-empty**로 나오지만,
- 그 안의 predicate는 **canonical 내부 표기**이며, **z3가 해석 불가능한 형태**로 끼워진다.
- 즉 "lowering이 존재한다"고 말하기 어렵고, "script 껍데기만 만들어졌다"가 정확하다.

---

## Interpretation

**사용자 A/B/C 프레임으로의 정밀 매핑:**

- **C 아님**: proposition은 잘 형성됨(non-empty, symbolic, living var `resultBits`).
  intrinsic obligation synthesis는 성공. derivationRule `obs:division`, provenance 정상.
- **순수 A 아님**: 단순히 production gate(`irToSmtScript`의 postConditions==0 return)를 고친다고
  끝나지 않는다. `irToSmtWithObligations`로 routing해도 생성되는 것은
  z3-executable SMT가 **아니다** (`uoNot/boEq/lit/var` raw 삽입).
- **B 방향의 capability 결여가 결정 요인**: canonical predicate를
  **z3-executable SMT-LIB2 term으로 낮추는 변환기**가 소프트웨어에 존재하지 않는다.
  canonical predicate의 표기는 `parseIRExpr`과 호환되지 않아, 기존
  `serializeIRExpr↔parseIRExpr` IR 사이클에도 연결되지 않는다.

**정확한 capability boundary(이 실험의 산출):**

```
okSafetyDiv canonical proposition (orgGenerated, non-empty)   [성공: 워낙 존재]
        ↓
production irToSmtScript                                       [empty: postConditions==0 gate]
        ↓  (만약 이 gate를 제거/우회해도)
irToSmtWithObligations                                          [non-empty-string이지만
                                                                    not z3-executable]
        ↓
canonical predicate → SMT-LIB2 term 변환기                     [부재 ── 결정적 경계]
```

즉 **anchoring 자산(intrinsic safety obligation)은 존재하고, 이를 소비하는
'true SMT term-lowering' 경로가 없어서 executable proof goal에 도달하지 못한다.**

---

## Non-Conclusions

- 본 실험은 **Z3 실행, Lean kernel, KAA, TrustCommit에 도달하지 못했으며 도달 시도하지도 않았다.**
  `Verified`는커녕 `Counterexample`도 없다. 실행 성공 ≠ 증명이 아니다.
- `irToSmtWithObligations`가 non-empty string을 냈다는 것은 **증명이 아니다.**
  그 string은 z3-valid 입력이 아님을 별도 실증했다(정적 스퍼리어스 연산자 검출).
- "canonical predicate→IRExpr 역파싱 경로가 소프트웨어에 없다"는 결론은
  현재 이 트리의 두 직렬화 체계(`serializeIRExpr` vs `canonicalizePredicate`)를
  바탕으로 한 것이며, 향후 다른(in-progress) 변환기가 추가되었으면 재검증해야 한다.
- gate 코드(wp4h2 코드) 수정은 이번 WP에서 하지 않았다(read-only).
- Track B(historical debt, CurrentEvidence 등)는 건드리지 않았다.

---

## Next Experiment

**WP4-h-3 — canonical-predicate → executable SMT-LIB2 term lowering**
(다음 capability WP 후보)

목표: `okSafetyDiv(resultBits != 0)` canonical predicate를
`(not (= (_ bv0 64) resultBits))` 수준의 z3-executable SMT-LIB2로
결정론적으로 낮추고, 이를 production pipeline에 연결한다.

최소 실험 질문:
1. canonical predicate(`uoNot/boEq/lit/var` 표기) → IRExpr 복원 경로를 만들 것인가,
   아니면 obligation 생성 시점의 원본 IRExpr을 `VerificationObligation`에 보존할 것인가?
2. 그 IRExpr을 `irExprToSmt`/BMC lower를 통해 SMT-LIB2로 낮출 때
   `resultBits`의 bit-width/타입이 올바르게 보존되는가?
3. 이후 열린 경로에서 `irToSmtWithObligations`(또는 그 대체)를 pipeline에 wiring해
   TheaterGuard가 더 이상 `rkObligationIllFormed`를 내지 않는가?
   (→ WP4-h-4: SMT→Z3 실행, WP4-h-5: Z3→Lean, WP4-h-6: Lean→KAA→Trust)

주의: 이 변환을 추가할 때 **semantic을 몰래 약화하지 말 것** (AGENTS.md §3).
division guard `resultBits != 0`는 반드시 symbolic input과 연결된 채로 유지되어야 한다.
