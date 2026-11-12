# Axiom IR `recomputeTyp` / Inline-Pass Mixed-Typing 특이사항

> Inline pass가 스마트 생성자로 재구성한 **구조적 노드만 `typ`이 채워지고**, 역직렬화된 **리프 노드는 `typ == nil`로 남아** 부분적으로 타입된(partially-typed) 혼합 트리가 만들어지는 현상.
> 이 혼합 트리에서 구식 `recomputeTyp`의 `if e.typ != nil: return` 조기 반환이 리프 백필을 건너뛰어, `validateExprTypes`가 `nil`을 보고 모든 비자명 SMT-native 본문이 `vpBmcSkipped`로 떨어지던 근본 원인을 기록합니다 (AGENTS.md §0.5b, session-ses_0346, 2026-08-06).

---

## §1. 증상

- `clampTimeoutMs` 등 커널 심볼의 인증서가 BMC를 수행하지 않고 `vpBmcSkipped`로 끝납니다.
- 비자명(구조적 연산을 포함하는) SMT-native 본문 **16/16** 커널 인증서가 모두 0 — 즉 전혀 검증되지 않았습니다.
- 플래그/직렬화를 우회한 독립 프로브(serialize→deserialize→synthesizeContracts→recomputeTyp→irToSmtScript)는 **통과**하여, 프로브와 파이프라인 간의 분기(divergence)가 버그를 세션 내내 은폐했습니다.

## §2. 근본 원인 체인

1. **`runIrPipelinesFor`** (`src/verification/batch_uap/ir_pipeline_runner.nim:431`)가 모든 엔트리에 대해 `runIrPipeline` 전에 `inlineSmallFunctions(ve.funcDef.body, allFuncDefs)`를 실행.
2. **`ir_inline_pass.nim`** (`src/core/trusted/ir_inline_pass.nim:177,181`)이 `irIf`/`irBinOp` 같은 구조적 노드를 axiom_ir_helpers.nim의 스마트 생성자가 **`typ` 필드를 채우며 재구성**. 그러나 리프(`of irLit, irFloatLit, irVar, irStringLit: return e`, ~210-211)는 **역직렬화된 그대로 반환**.
3. 역직렬화자 **`parseIRExpr`** (`src/core/trusted/axiom_ir.nim:795+`)는 `typ`을 **절대 설정하지 않음** (`irVar`의 `varType`만 설정). → 리프는 `typ == nil` 유지 → **부분적으로 타입된 혼합 트리**.
4. **`irToSmtScript`** (`src/core/trusted/private/ir_to_smt_chunk3.nim:149-155`)가 `recomputeTyp(f.body)` → `elaborateSorts(f.body)` → `validateIrTypes(f)`를 호출.
5. **구식 `recomputeTyp`** (`axiom_ir.nim ~551`)는 `if e.typ != nil: return` — 이미 타입된(인라인된) 루트에서 **즉시 반환**하여 타입이 없는 리프를 백필하지 않음.
6. **`validateExprTypes`** (`axiom_ir.nim ~615`/`619-621`)의 `if e.typ == nil: return false` → `validateIrTypes`가 false → `irToSmtScript`가 `""` 반환 → `smtScript.len == 0` → `vpBmcSkipped` (비자명 SMT-native 본문 전부).
7. **독립 프로브는 통과**: 인라인 패스를 건너뛰어 **전체가 nil 트리** → `recomputeTyp`가 전 구간을 재귀 → 통과. 프로브-파이프라인 분기가 버그를 은폐.

## §3. 왜 프로브가 분기되었나 (Probe Divergence)

| 경로 | 입력 트리 | 구식 recomputeTyp 행동 | 결과 |
|------|-----------|------------------------|------|
| 파이프라인 | 인라인 통과 후 **루트만 타입/DEEP 리프 nil** | 루트에서 `if e.typ != nil: return` | 리프 미백필 → validate 실패 → 빈 SMT |
| 독립 프로브 | 인라인 없음, **전체 nil** | 루트 `typ == nil` → 전체 재귀 | 전 리프 백필 → SMT 생성 성공 |

## §4. 수정 (적용됨)

`recomputeTyp` (`src/core/trusted/axiom_ir.nim:551`)가 이제 **현재 노드에 `typ`이 이미 설정되어 있어도 항상 자식으로 재귀**합니다.

- 자기 대입(self-assignment)은 멱등(idempotent) — `irLit`/`irFloatLit`/`irStringLit`은 같은 값으로 재설정.
- `irVar` 케이스는 `if e.varType != nil` 가드로 보호 — `varType == nil`이면 `typ`을 덮어쓰지 않음.
- 이로써 혼합(부분 타입) 트리에서도 리프가 반드시 백필됩니다.

## §5. 영향 모듈

| 모듈 | 위치 | 역할 |
|------|------|------|
| `src/verification/batch_uap/ir_pipeline_runner.nim` | `:431` | 엔트리마다 `inlineSmallFunctions` 실행 → 혼합 트리 생성 지점 |
| `src/core/trusted/ir_inline_pass.nim` | `:177,181` | 구조적 노드 재구성(스마트 생성자), 리프는 그대로 반환 |
| `src/core/trusted/axiom_ir.nim` | `:795+` (parseIRExpr), `:551` (recomputeTyp), `:619-621` (validateExprTypes) | 역직렬화·타입 백필·유효성 검사 |
| `src/core/trusted/private/ir_to_smt_chunk3.nim` | `:149-155` | `recomputeTyp` → `elaborateSorts` → `validateIrTypes` 호출, 빈 SMT 반환 |
| `src/core/trusted/axiom_ir_helpers.nim` | 스마트 생성자 | 구조적 노드의 `typ` 필드 설정 |

## §6. 방지 지침 (Prevention)

1. **스마트 생성자로 트리를 재구성하는 모든 패스(pass)는 리프 타입을 백필하거나, 패스 후 반드시 `recomputeTyp`를 실행**해야 합니다. 구조적 노드만 타입하고 리프는 그대로 두면 혼합 트리가 생성됩니다.
2. **`recomputeTyp`류의 백필 함수는 "이미 타입되었다면 반환"하는 최적화 조기 반환을 피해야 합니다.** 노드 수준 최적화는 **트리 전체가 균일하게 타입되었을 때만** 안전합니다. 혼합 트리에서는 리프 백필이 누락됩니다.
3. **`validateIrTypes`는 본문(body)만 검사하고 선행/후행 조건(pre/postconditions)은 검사하지 않습니다.** 검사 범위를 넓히거나, 검증 진입점마다 백필이 보장되었는지 확인하세요.
4. **독립 프로브가 파이프라인을 대체하지 못하게 하세요.** 프로브가 엔드투엔드 파이프라인(특히 인라인 패스)을 건너뛰면, 프로브-파이프라인 분기가 실제 버그를 은폐합니다. 프로브는 반드시 실제 파이프라인 경로를 재현해야 의미가 있습니다.
5. **`ref object` 공유 리프 의미론을 주의하세요.** `IRExpr`는 `ref object`(`axiom_ir.nim:108`)이므로 `var funcDef = ve.funcDef`는 얕은 복사이며 인라인 패스가 엔트리 간에 리프 참조를 공유합니다. 한 엔트리의 변이가 다른 엔트리에 전파될 수 있습니다.

---

## §7. Follow-up: QF_BV uninterpreted-function violation (second bottleneck)

> recomputeTyp 수정 이후 발견된 **두 번째 병목**. 이제 SMT가 생성되지만 Z3가 `QF_BV` 논리에서 **비-0-항(uninterpreted, 0-arity 이상) 함수 기호**를 금지한다는 제약 때문에 스크립트 전체를 거부했습니다. (AGENTS.md §0.5b, session-ses_0346, 2026-08-06)

### §7.1 증상

- `recomputeTyp` 수정 후, 커널 심볼 `clampTimeoutMs`의 인증서가 `vpBmcSkipped`에서 **`psFail`/`vpNone`** 으로 바뀌었습니다 — 즉 이제 BMC가 실행되지만 **실패**합니다.
- `z3ExecPersistent`가 반환한 에러 텍스트:
  - `(error "line 34 column 57: logic does not support uninterpreted functions")`
  - `(error "... unknown constant clamptimeoutms ...")`
- 결과: `z3Sat=false`, provenance `vpNone`, `success=false`.

### §7.2 근본 원인 체인

1. `irToSmtScript` (`src/core/trusted/private/ir_to_smt_chunk3.nim`, 구식 Step 2+Step 5)가 다음을 생성했습니다:
   - `(declare-fun <name> (<param sorts>) <ret sort>)` — **arity > 0 인 비-0-항 함수(uninterpreted function) 기호**.
   - `(assert (= (<name> ...) (<name>_impl ...)))` — 추상 함수와 `_impl` 정의 사이의 **외연적 논리적 동등(extensional equality)**.
   - 이 모든 내용이 `(set-logic QF_BV)` 아래에 위치.
2. SMT-LIB2 `QF_BV` 논리 정의상, **QF_BV는 arity > 0 인 uninterpreted function symbol을 전혀 허용하지 않습니다** — 오직 bitvector 이론 연산자와 **0-항 상수(0-ary constants)** 만 허용합니다.
3. Z3는 이를 강제하므로 스크립트를 거부 → `z3ExecPersistent`가 에러 텍스트를 반환 → `z3Sat=false`, provenance `vpNone`, `success=false`.

> Cross-reference: SMT-LIB2/Z3 근거는 세션 기록 `session-ses_0346.md`를 참조.

### §7.3 왜 프로브가 처음에 오도했나 (Probe Divergence, 유형 2)

- 앞선 §2.7의 프로브와 달리, 여기서는 **독립 프로브가 Z3를 전혀 실행하지 않았습니다** — 프로브는 SMT 스크립트를 생성하기만 했고 `validateIrTypes`/구조적 검사는 Z3를 조회하지 않습니다.
- 프로브와 파이프라인 모두 "생성된 SMT가 구문적으로 유효해 보인다"고 판단했지만, **논리적 적합성(logic conformance)은 Z3 실행 시점에만 드러납니다**. 프로브가 Z3를 거치지 않음으로써 QF_BV 위반이 은폐되었습니다.

### §7.4 수정 (적용됨)

- **추상 `declare-fun` + 외연적 동등을 제거**했습니다.
- 이제 후행 조건(postconditions)을 `define-fun` `_impl`에 대해 **직접** 검사합니다:
  - `(assert (let ((result (<name>_impl <params>))) (not <postConj>)))`
- 이는 **동일한 BMC 의미론**이면서 `QF_BV`에 적합(conformant)합니다.
- 두 변형 모두 `z3 -smt2`로 **UNSAT를 반환함을 실증적으로 확인**했습니다 (동등 BMC 쿼리, 소스 변경 없음).

### §7.5 세 번째 병목 (요약)

- **개별 인증서 영속화(cert persistence) 문제**: IR-batch 결과에 대해 `axiom_engine` Phase 13이 **manifest만 기록하고 `modulePath == ""`** 로 남겨, 심볼별 인증서가 손실/미기록되었습니다.
- **수정**: `modulePath`가 레지스트리 `sourcePath`에서 오는 심볼별 인증서 JSON을 `irHash` 키로 기록하도록 변경. `smtlib2` 증거(deep-verify stage-2 OR-arm)와 `winningStrategy: "ir-bmc-z3"` 포함.

### §7.6 방지 지침 (Prevention)

1. **`QF_BV`(및 일반적으로 SMT-LIB2 논리) 하에서 arity > 0 인 `declare-fun`을 금지하십시오.** uninterpreted function은 `QF_UF*` 계열(예: `QF_UFBV`)에서만 허용됩니다. 필요하면 로직을 `QF_UFBV`로 올리거나, 함수적 추상화를 버리고 `define-fun` `_impl`을 직접 사용하십시오.
2. **logical conformance는 실행 시에만 드러납니다.** SMT 스크립트를 생성하는 프로브는 반드시 실제 Z3 실행까지 포함해야 합니다 — 구문/구조 검사만으로는 논리 제약 위반을 잡지 못합니다 (§7.3).
3. **`z3ExecPersistent`의 에러 텍스트를 성공으로 흡수하지 마십시오.** Z3가 에러를 반환하면 `z3Sat=false`/`vpNone`으로 이어지므로, 스크립트 생성 측에서 QF_BV 위반을 사전에 배제해야 합니다.