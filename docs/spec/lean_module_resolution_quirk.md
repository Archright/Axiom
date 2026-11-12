# Lean 4 모듈 해상 및 runFrontend 특이사항

> Lean 4 CLI(`lean --run`)와 Lake의 모듈 해상 메커니즘 차이, 그리고
> `Elab.runFrontend` 메모리 누적 특성을 기록합니다 (AGENTS.md §0.5b).

---

## §1. `-R/--root`는 import 해상과 무관하다

- `lean -R proofs --run script.lean file.lean`에서 `-R`은 **입력 파일의 모듈명 계산에만** 사용됩니다.
- import 해상은 `LEAN_PATH`(olean 디렉터리) + 내장 `lib/lean`만 사용합니다 (`Path.lean:106-108`).
- **plain `lean`은 소스 파일을 import로 해상하지 않습니다** — `import X.Y`는 반드시 `X/Y.olean`을 요구합니다.
- `-L/--leanpath`, `-S/--src` 플래그는 Lean 4.29.0에 존재하지 않습니다.
- **결론**: 프로젝트 모듈(`import GateInvariants.GateData`)을 해상하려면 `lake build`로 olean을 생성하고
  `LEAN_PATH=proofs/.lake/build/lib/lean`을 설정해야 합니다. `-R proofs`만으로는 부족합니다.

## §2. runFrontend 메모리 누적 (OOM 원인)

- `Elab.runFrontend`는 호출마다 **신선한 빈 Environment**에서 시작하며, 매 호출마다 `import Lean`의
  전체 stdlib olean을 **재로드·재역직렬화**합니다 (`Environment.lean:2131`). 모듈 캐시가 없습니다.
- GC는 증분적이라 RSS가 호출 횟수에 비례해 단조 증가합니다 → 단일 프로세스에서 모든 `.lean`을
  순차 처리하면 CI 워커에서 OOM(Error 137)이 발생합니다.
- **해결**: 파일당 별도 `lean --run` 프로세스 (per-file isolation) — OS가 프로세스 종료 시 힙을
  결정론적으로 회수합니다.

## §3. mutual inductive sizeOf와 termination

- `IRExpr`/`CaseBranch`가 `mutual` 블록으로 정의되면, `List CaseBranch` 원소의 `.body` 필드에 대한
  재귀는 자동 structural recursion이 추론되지 않습니다 (`sizeOf cb.body < sizeOf (s.case_ bs d)` 실패).
- `termination_by e => sizeOf e` + `decreasing_by`에서 `simp_wf` 후 남는 goal은
  `List.sizeOf_lt_of_mem`(멤버십) + 필드 감소 체인으로 증명해야 합니다.
- `List.foldr`/`flatMap`의 람다 내부 재귀는 멤버십 가정(`cb ∈ bs`)을 termination goal에 제공하지
  않으므로, `List.attach`(Subtype) 또는 명시적 `cb :: rest` 패턴 재귀를 사용해야 합니다.

## §4. lean_lib 기본 빌드 타겟

- Lake에서 `@[default_target]`이 없는 `lean_lib`은 `lake build`(기본 타겟)에 **포함되지 않습니다**.
- 여러 lib을 기본 빌드에 포함하려면 각각 `@[default_target]`을 붙여야 합니다.
- `srcDir := "."` + `roots := #[`X]`는 `X.lean`(루트 파일)을 요구하며, 하위 모듈은 `X/` 디렉터리.
- `Glob.submodules `X`는 `X/` 디렉터리의 모든 모듈을 빌드 대상에 포함합니다.

## §5. 스캐너 극장 수정 (2026-08-06)

- `proofs/check_vacuity.lean:8`의 `| return 0`은 `Elab.runFrontend` 실패(import 해상 실패 등)를
  **PASS로 삼키던 극장**이었습니다 (§0.9 시그니처 #2). CI 로그에서 `error: unknown module prefix`
  직후 `PASS:`가 출력되던 것이 실증입니다.
- 수정: runFrontend가 `none`을 반환하거나 예외를 던지면 stderr에
  `VACUITY [elaboration-failed] <file>` 출력 + violation 1로 카운트 → exit 1.
- 이 수정으로 `proofs/IR/TranslatorEquivalence.lean`(termination 미해결), `LeanWorker.lean`
  (`partial` 필요), `ShmFFI.lean`(생성 구조체 필드 누락) 등 **선존 깨진 증명 파일이 즉시 감지**되었고
  각각 수정됨.

## §6. ir_def.nim array 생성

- `defineIR` 매크로의 `array[16, byte]` 타입: Nim 필드가 매크로 body에서 `nnkCall`로 파싱되어
  기존 `nnkCommand`만 처리하던 로직이 **모든 필드를 무시**했습니다.
- Lean 4는 `Array α n`(길이 파라미터)이 없으므로 `array[N, T]` → `Fin N → T` (함수 타입)로 생성.
- `Fin N → T`는 `Repr`/`BEq` deriving이 불가 → array 필드를 가진 struct는 deriving 생략.
- Nim 쪽 packed object는 `type Name {.packed.} = object`가 `nnkTypeDef(PragmaExpr(name, pragma),
  Empty, ObjectTy(Empty, Empty, RecList))` 형태여야 함 — TypeSection으로 감싸야 함.

## §7. 영향 범위 (2026-08-06 수정)

| 파일 | 수정 |
|------|------|
| `Makefile` | `check-vacuity-simple`: `lake build` + `LEAN_PATH` + per-file 루프 + 제외 목록 |
| `proofs/check_vacuity.lean` | fail-closed (elaboration 실패 → exit 1) |
| `proofs/lakefile.lean` | `@[default_target]` 3개 lib + Generated srcDir/roots 수정 |
| `proofs/Generated/SharedIRHeader.lean` | `padding : Fin 16 → UInt8` 재생성 |
| `proofs/IR/TranslatorEquivalence.lean` | termination_by/decreasing_by + optFold 제거 |
| `proofs/IR/LeanWorker.lean` | `partial` (daemon 루프) |
| `proofs/IR/ShmFFI.lean` | readUInt8LE 정의 + status/padding 필드 수정 |
| `src/core/trusted/ir_def.nim` | nodeToTypeText/typeTextToNode/nimToLeanType array → Fin |

## §8. 회귀 방지 체크

- `make check-vacuity-simple` → 전체 PASS + exit 0 (3회 결정론).
- fresh `.lake` 상태(CI checkout)에서도 동일 결과.
- 의도된 실패(`import Nonexistent.Module`)는 exit 1로 감지.
