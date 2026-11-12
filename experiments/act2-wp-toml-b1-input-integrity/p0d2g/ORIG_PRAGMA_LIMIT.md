# P0-D2-G — ORIG_PRAGMA_LIMIT: 원본 함수 직접 명세 부착의 한계 관측

Experiment: `act2-wp-toml-b1-input-integrity/p0d2g` · Date: 2026-10-17
바이너리: `bin/ax` v0.3.7 (사본 `/tmp/p0d2g_d_ax`) · 주체: `nim-toml-serialization @ 4aa8e2223649fc0837c490a4acfca7b8b1e756f9`

**목적**: 채택된 에이전트 추론 명세 S2(`AGENT_SPEC.md` §4)를 **원본 주체 함수 헤더에 직접** 부착해 실행하고, 어느 단계가·왜 이 연결을 거부하는지 관측한다. 이 문서는 관측 전용 기록이다 — 수정·해법 없음. 원본 소스 클론(`<workspace>/nim-toml-serialization`)은 건드리지 않았고, 모든 변형은 `env_orig/subject` 클론에서 수행했다.

---

## 1. 대상 원본 프로시저 (게이트 소속, 실측)

두 게이트는 서로 다른 프로시저 안에 있으며 **시그니처는 동일 형태**다 (`toml_serialization/lexer.nim`, pristine sha256 `19d69eed84f74c51fa1784b2e71a4525abc8d2b8aa854c567565d2d603133f4d` — 스펙 §5 기재값과 일치):

| 게이트 | 프로시저 | 선언(원본 라인) |
|---|---|---|
| `:554` (멀티라인, `{16, 31, 127}`) | `scanMultiLineString` | 468 |
| `:588` (단일행, `{8, 16, 31, 127}`) | `scanSingleLineString` | 565 |

```nim
proc scanMultiLineString[T](lex: var TomlLexer, res: var T, kind: static[StringType]) {.raises: [IOError, TomlError].} =
proc scanSingleLineString[T](lex: var TomlLexer, res: var T, kind: static[StringType]) {.raises: [IOError, TomlError].} =
```

- 제네릭 `[T]` (string 또는 TomlVoid로 한정하는 `{.fatal.}` 가드 포함), `static` 매개변수, 반환 없음(`proc`), 부수효과 `raises: [IOError, TomlError]`.
- **시그니처 바인딩 불일치(잠재 병목)**: S2 프라그마의 `c`와 `result`는 이 시그니처의 어떤 이름과도 대응하지 않는다. 실제 문자는 루프 내부 지역변수 `next`(char)이고 결과는 예외 발생 여부다. 이 불일치는 관측 설계의 일부로서 남겨 두었다(§4).

## 2. 변형 패치 (variant_orig.patch, 1531 바이트)

- `git clone` 원본 클론 → `env_orig/subject`, 핀 체크아웃, `rev-parse` 검증(`4aa8e2223649fc0837c490a4acfca7b8b1e756f9`).
- 유일한 변경: 두 프로시저 헤더의 기존 프라그마 블록 앞에 스펙 프라그마 삽입(파일당 2줄, 그 외 무변경):

```diff
-proc scanSingleLineString[T](lex: var TomlLexer, res: var T, kind: static[StringType]) {.raises: [IOError, TomlError].} =
+proc scanSingleLineString[T](lex: var TomlLexer, res: var T, kind: static[StringType]) {.axiom: [pre: (c >= 1 and c <= 255 and c != 10 and c != 13 and c != 34 and c != 92), post: (result == ((c <= 8) or (c >= 10 and c <= 31) or (c == 127)))], raises: [IOError, TomlError].} =
```

(`scanMultiLineString` 동일 형태. 재생 단계 도달이 없어 컴파일 적합성은 검증 대상이 아니었다 — materializer가 raw AST에서 프라그마를 읽는다는 파이프라인 설계에 따름.)

## 3. 실행 관측치 (verbatim)

### 3.1 본 실행 — 프라그마 부착 원본 대상 `scanSingleLineString`

`AXIOM_STATE_DIR=state_orig AXIOM_PROVE_VAULT_DIR=vault_orig ax prove --project env_orig/subject --target 'toml_serialization/lexer.nim::scanSingleLineString'` → **exit 2** (0.7초, 솔버 미도달).

`runs/orig_pragma.err` 전문(타겟 프로시저 언급 라인 포함 — `unsupported decl kind`/`lossy`/`binding` 라인은 **없음**, 도달하지 않았음):

```
[INFO] axiom_engine: analyzing topology...
[INFO] topology_cli: topology: 31 files, 31 changed, sourceRoot=.../p0d2g/env_orig/subject
[INFO] axiom_engine: topology: 31 files, 344 candidates
[INFO] frontier_selection: --target=toml_serialization/lexer.nim::scanSingleLineString not found in frontier — canonical target: NotFound (fail-closed, empty selection)
[ERROR] action_interpreter_cli: [ERROR] --target toml_serialization/lexer.nim::scanSingleLineString resolved to no frontier nodes (NotFound or Ambiguous). Canonical targets require exactly one match; 0 matches = NotFound, >1 = Ambiguous. Refuse to run an implicit full-frontier verification on a canonical target.
```

(`runs/orig_pragma.out`은 빈 파일.)

**결정적 정밀 관측** — 대상은 인덱스에는 존재한다. 본 실행이 남긴 `state_orig/.axiom/cache/topology_merkle.json`의 기록:

```json
{"modulePath": "toml_serialization/lexer.nim", "functionName": "scanSingleLineString",
 "nodeType": "proc", "nodeIdStr": "toml_serialization/lexer.nim::scanSingleLineString",
 "declarationLine": 565, "exported": false, "hasAxiomImpl": false,
 "rawCallTargets": ["post:", "or", "isnot", "stringDelimiter", "UTF8Validator",
  "raiseTomlErr", "ord", "raiseInvalidChar", "valid", "clear", "scanEscapeChar", "push", "add"]}
```

(`scanMultiLineString`도 동일 — declarationLine 468, `hasAxiomImpl: false`, rawCallTargets에 `"post:"` 포함.)

이것이 말해 주는 것:
1. **프라그마는 raw AST까지는 읽혔다** — 페이로드의 `post:` 토큰이 `rawCallTargets`로 새어 나온 것은 CST가 프라그마 식을 파싱했고, 파이프라인이 그것에 부여한 의미가 "호출 후보" 수준이라는 증거다. 프라그마는 의무(obligation)로 변환되지 않았다.
2. **`hasAxiomImpl: false`** — 구현 플래그는 `axiomImpl`이라는 **다른 프라그마 이름**에서만 셋된다(`src/core/topology/topology_engine.nim:309`, `hasPragmaNamedP(fnNode, "axiomImpl")`). IR 전환 진입점 역시 `{.axiom, axiomImpl.}` 쌍을 전제한다(`src/core/trusted/ast_to_ir.nim:1502`). 즉 파이프라인의 AST 마커 어휘와 스펙 프라그마 어휘(`axiom: [pre/post]`)는 역할이 분리되어 있다.

### 3.2 대조 실행 — 프라그마 없는 leaf 원본 `stringDelimiter` (같은 파일)

`--target 'toml_serialization/lexer.nim::stringDelimiter'` → **exit 2**. `runs/orig_pragma_ctrldelim.err`의 결정 라인:

```
[INFO] axiom_engine: external candidate excluded: stringDelimiter eligibility=elNoObligation rejection=ogr.no-applicable obligations=0 nonTrivial=0 source=toml_serialization/lexer.nim
[ERROR] action_interpreter_cli: [ERROR] --target toml_serialization/lexer.nim::stringDelimiter resolved to no frontier nodes (NotFound or Ambiguous). ...
```

의존성 0짜리 원본 함수는 **사전-자격(pre-eligibility) 프론티어에는 진입**하지만, 의무가 없어(`ogr.no-applicable`, obligations=0) 자격 게이트에서 탈락한다.

### 3.3 if-갭 재검증 프로브 (`/tmp/d2if_probe`, 단일 파일 주체)

`probe.nim` = `func p*(c: int): int {.axiom: [pre: (c >= 0), post: (result == (if c < 1: 0 else: 1))].} = 0`, `--target 'probe.nim::p'` → **exit 2**. `runs/if_probe.err` 결정 라인:

```
[INFO] axiom_engine: external candidate unsupported decl kind: p in probe.nim reason=axiom spec expression has no IR translation (translator marked loss); the explicit spec cannot be ingested for this symbol
[ERROR] action_interpreter_cli: [ERROR] --target probe.nim::p resolved to no frontier nodes (NotFound or Ambiguous). ...
```

**판정: if-표현식 스펙은 v0.3.7에서도 여전히 lossy 거부다.** 원인 코드 확인: spec 적하 경로 `ingestExplicitSpec`이 lossy를 보면 `moUnsupportedDeclKind` + 상기 reason으로 fail-closed한다(`src/infrastructure/external_ir_materializer.nim:449-453`). p0d2f에서 기록된 Canon 프론트엔드 if-손실(`toCanonKind`에 nkElifExpr/nkElseExpr 부재)은 **현행 바이너리에도 그대로 유효**하다.

### 3.4 양성 대조 — 같은 리그, if 없는 스펙

`/tmp/d2if_probe_ctl`: `post: (result == (c - c))`로만 바꾼 동일 구성 → **exit 0**. `runs/if_probe_ctl.err`:

```
[INFO] axiom_engine: --target filter: 1 node(s) match 'probe.nim::p'
[INFO] ir_pipeline_runner: [classify] p → vtSmtNative (simple bitvec/bool operations)
[INFO] ir_pipeline_runner: type-level candidate 'p' but no LSP — routed to standard SMT pipeline
[WARN] loop_driver: [LEAN ERROR] p: canonicalLeanKernelCheck: exit code 1: ... (Lean 변수 미사용 경고)
[INFO] loop_driver:   [1/1] probe.nim::p — orchestrationNotVerifiable
```

if만 없으면 같은 리그의 스펙이 materializer→분류→SMT→Lean 커널 검사까지 전진한다(최종 상태는 `certZ3Candidate`/`orchestrationNotVerifiable` — 승격 조건 미충족이지만, 이는 솔버 단계의 결과이지 자격 거부가 아니다). 즉 3.3의 거부는 리그 문제가 아니라 if-표현식 자체에 대한 것이다.

## 4. 분류 — 무엇이 원본 직접 연결을 막는가

관측 증거가 가리키는 차단은 **한 단계가 아니라 세 겹의 직렬 게이트**다. 본 실행은 첫 게이트에서, 대조는 둘째 게이트에서 각각 막혔고, 셋째 게이트의 내용은 코드 정독 + 3.3 프로브로 확정했다.

| # | 게이트 | 위치 | 원본 함수에게 내리는 판정 | 증거 |
|---|---|---|---|---|
| 1 | **프론티어 편입(의존성 폐쇄)** | `src/core/topology/verified_frontier.nim:40` `computeVerifiedFrontier` — 모든 `dependencyIds`가 검증 완료 집합에 있어야 편입 | `scanSingleLineString`/`scanMultiLineString`는 `stringDelimiter`·`UTF8Validator`·`raiseTomlErr`·`scanEscapeChar`·`raiseInvalidChar` 등 의존이 있고 빈 볼트에서 그 의존은 영원히 "검증됨"이 될 수 없음 → **프론티어 미편입 → NotFound 거부** | 3.1 (`not found in frontier`), merkle 캐시의 rawCallTargets |
| 2 | **자격 게이트(의무 존재)** | `src/cli/axiom_engine.nim:2842` `isEligible` → `classifyExternalCandidate`(:2149) → census 분류 | 의존 없는 leaf 원본은 편입하지만 의무 0건(`ogr.no-applicable`)으로 탈락. 의무의 공급원은 (a) Axiom 커널 레지스트리, (b) 오버레이가 선언한 주체 (`overlayDeclaresSubject` 등)뿐 — **주체 함수 헤더의 스펙 프라그마는 의무 공급원이 아니다** | 3.2 (`ogr.no-applicable obligations=0`) |
| 3 | **스펙 적하(손실 없는 번역)** | `src/infrastructure/external_ir_materializer.nim:449` — pre/post를 Canon→IR 번역, lossy면 fail-closed | (도달 시) `c`/`result`가 시그니처에 없는 바인딩 불일치와 if-표현식 손실이 여기서 걸린다. if-손실은 재확인됨(3.3). 참고로 `pre`의 비교 연쇄는 if 없는 형태라 3.3의 `pre: (c >= 0)`는 lossy가 아니었다 — 손실 판정은 post의 if에서 났다 | 3.3/3.4, materializer 소스 |

또 하나의 어휘 불일치가 게이트 2의 상류에 있다: 파이프라인이 주체 AST에서 구현 인지 플래그를 세우는 프라그마 이름은 `axiomImpl`이고(`topology_engine.nim:309`), 스펙 프라그마(`axiom: [pre/post]`)의 페이로드는 의무가 아니라 호출 후보 토큰(`"post:"`)으로만 관측된다(3.1). **스펙 프라그마를 원본 헤더에 붙이는 것만으로는 어느 게이트에도 '의무'로 등록되지 않는다.**

시그니처 바인딩 불일치(`c`/`result` 부재)에 관하면: 이것이 실재하는 잠재 병목임은 분명하지만(명세 변수가 원본 시그니처에 없고, 실제 검사 대상은 루프 지역변수 `next: char`, 판정 결과는 예외 발생), **본 관측에서는 도달조차 하지 못했다** — 게이트 1이 먼저 막았다. 즉 "직접 부착"은 바인딩 문제를 진단받기 전에 구조적으로 차단된다.

## 5. 시사점 — 베스포크 오버레이 경로의 존재 이유

p0d2f가 채택한 경로 — 주체 트리 **루트에 새 커널 모듈을 추가**(`d2kernels.nim`, "this file is the ONLY delta from the baseline tree")하고 그 `func`에 스펙 프라그마를 붙이며, 컴파일용 `template axiom*(val: untyped = "") {.pragma.}` shim을 곁들이고, 오버레이가 그 심볼을 주체로 선언하는 구성 — 은 우회가 아니라 **위 세 게이트를 각각 통과하는 유일한 구성**이었다는 것이 본 관측으로 정립된다:

1. 커널 `func`는 의존 0(리프) → 게이트 1 통과(3.2가 보여 주듯 리프는 편입한다).
2. 오버레이 선언 → 게이트 2의 의무 공급원 확보(`p0d2f/env2/subject_variant/d2kernels.nim`의 구성 + `axiom_engine.nim:2854-2880`의 오버레이 분기).
3. if 없는 비교/div 스펙 → 게이트 3 통과(p0d2f SPEC.md 개정 + 본 문서 3.4).

반대로 원본 함수에 스펙을 직접 붙이는 길은 게이트 1(비-리프)·게이트 2(비-오버레이)에서 막히며, 막힌 지점조차 "명세-원본 바인딩" 진단이 아니라 **프론티어/자격 구조의 fail-closed 거부**로 표출된다. 원본 코드와 형식 명세 사이의 이 연결 단절이 바로 베스포크 오버레이(추출 커널) 경로가 존재하는 구조적 이유다.

## 6. 산출물·범위

| 산출물 | 경로 |
|---|---|
| 변형 클론(핀 고정) | `p0d2g/env_orig/subject/` (@4aa8e22, lexer.nim 2행 수정) |
| 패치 | `p0d2g/variant_orig.patch` (1531 B) |
| 본 실행 로그 | `p0d2g/runs/orig_pragma.{out,err,exit}` (exit 2) |
| leaf 대조 로그 | `p0d2g/runs/orig_pragma_ctrldelim.{out,err,exit}` (exit 2) |
| if-프로브 로그 | `p0d2g/runs/if_probe.{out,err,exit}` (exit 2) |
| 양성 대조 로그 | `p0d2g/runs/if_probe_ctl.{out,err,exit}` (exit 0) |
| 상태/볼트 | `p0d2g/state_orig/`, `p0d2g/vault_orig/`, `p0d2g/state_probe/`, `p0d2g/vault_probe/` |

범위 준수: 원본 클론 미변경, `src/`·p0d2f·`AGENT_SPEC.md`·discovery 무변경, `make build` 미실행, 커밋 없음. 재생(솔버/반례) 단계에는 도달하지 않았다 — 게이트 1이 그 상류에서 실행을 거부했기 때문이며, 이 자체가 본 슬라이스의 관측 결과다.
