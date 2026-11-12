# Intentional Architecture Patterns

> 자동 기술부채 감사에서 "의도적 설계"로 분류된 패턴들의 기록입니다.
> 에이전트가 이 파일을 참조하여 false positive debt로 보고하지 않도록 합니다.

---

## 1. `except Exception` — I/O 경계 (2건)

Nim stdlib의 일부 함수는 `CatchableError`가 아닌 `Exception`을 raise로 선언합니다.
이 경우 `except Exception`은 **유일하게 합법적인 패턴**이며, 수정 불필요합니다.

| File | Line | Reason |
|------|------|--------|
| `src/core/trusted/stdlib_shield.nim` | 31 | `parseXml` isolation — converts to `XmlParseError` (CatchableError subtype) |
| `src/core/trusted/stdlib_shield.nim` | 44 | `moveFile` isolation — converts to `FileMoveError` (CatchableError subtype) |

**AGENTS.md 참조**: §0.6 (Static First Enforcement), docs/spec/nim_effect_system_quirks.md

---

## 2. Entry Point 모듈 (33개)

`isMainModule` 또는 `proc main`을 포함하며, `import`되지 않고 독립적으로 컴파일됩니다.
이는 **의도적 구조**입니다 — 각 모듈은 `bin/` 또는 `nimble build`를 통해 독립 실행됩니다.

주요 entry points:
- `src/cli/main.nim` — CLI 진입점
- `src/mcp/server.nim` — MCP 서버
- `src/gate/runners/*.nim` — 개별 게이트 러너 (19개)
- `src/gate/nimtry/nimtry_cli.nim` — nimtry CLI

---

## 3. Test-Only 모듈 (7개)

`src/`에서 import되지 않지만 `tests/`에서 import됩니다.
AGENTS.md §0.7 (Business-Only Test Scope)에 따라 **비즈니스 시나리오 테스트를 위해 유지**됩니다.

| Module | Test Importers |
|--------|---------------|
| `src/gate/tag_parser.nim` | 3 |
| `src/core/provider_interface.nim` | 1 |
| `src/verification/verification_facade.nim` | 1 |
| `src/verification/ecosystem_linkage.nim` | 1 |
| `src/ui/ax_tui_reporter.nim` | 1 |
| `src/gate/semaphore.nim` | 1 |
| `src/gate/gate_utils.nim` | 1 |

---

## 4. Include 파일 패턴 (60개)

Nim의 `include` 문으로 부모 파일에 포함되는 파일들입니다.
`import`로 검색하면 orphan으로 보이지만, 실제로는 부모 파일의 일부로 컴파일됩니다.

패턴: `*_parts/*.nim`, `*_part1.nim`, `*_part2.nim` 등

---

## 5. Deprecated 함수 (2개)

`{.deprecated.}` pragma가 태깅되어 컴파일 시 경고를 생성합니다.

| File | Function | Replacement |
|------|----------|-------------|
| `src/verification/lean_skeleton.nim` | `buildLeanSkeleton` | `buildUniversalLeanSource` |
| `src/verification/lean_skeleton.nim` | `buildLeanSignaturePrefix` | `buildUniversalLeanSource` |

---

## 7. Gate Runner 모듈 (19개)

`src/gate/runners/` 하위의 각 모듈은 독립적인 gate binary로 컴파일됩니다.
`import`되지 않는 것은 **정상** — `gate_hook.nim`이 `startProcess`로 실행합니다.

---

*Last updated: 2026-06-05*

## 8. Composition Root / Registry Pattern

DIP(Dependency Inversion Principle)를 구현하기 위해 Domain 모듈은 인터페이스(예: `PersonaDispatchFn`, `PersonaBridge`)만 정의하고, 구체 구현체는 별도의 Composition Root 모듈에서 배선(wiring)합니다.

### 8.1 의도

- `src/core/` (Domain)이 `src/verification/` 또는 `src/personas/` (Infrastructure)를 직접 import하는 것을 방지.
- 런타임/컴파일타임 레지스트리, IoC 컨테이너, 팩토리 클로저 등으로 구현.

### 8.2 필수 규칙: 명시적 Import 의존성

Nim 컴파일러는 모듈 의존성 그래프에 따라 컴파일하며, 매크로/프라그마/레지스트리 순회 코드는 컴파일 시점에 평가됩니다. **Composition Root 모듈은 반드시 배선할 대상 모듈을 직접 import해야 합니다.**

**올바른 예시** (~~persona_bridge_init.nim~~ [DELETED]):
```nim
import verification/leanstral_gateway
import verification/unified_trajectory
# ... (다른 verification/* 모듈)
proc initPersonaBridge*(): PersonaBridge = ...
```

**잘못된 예시** (가상):
```nim
# ❌ leanstral_gateway 등이 import되지 않은 상태에서 레지스트리 순회
import some_registry
autoWireStages()   # 레지스트리가 비어 있을 수 있음
```

### 8.3 Context7 근거

- Nim Manual: 모듈 의존성은 `compiler/deps.nim`, `compiler/modulegraphs.nim`, `compiler/pipelines.nim`에 의해 관리되며 의존성 그래프 순서로 컴파일됨.
- Nim Manual: 매크로와 `static` 블록은 컴파일 시점에 평가됨.

### 8.4 검증

- `src/core/orchestration/pipeline_dispatch.nim` — `personas/*` 직접 import
- ~~persona_bridge_init.nim~~ [DELETED] — `verification/*` 직접 import

### 8.5 정책

- Composition Root 파일은 `architecture_policy.lock`의 `[module_roles]` 또는 `[composition_roots]`에 등록.
- `nimtry` / `import_encapsulation_gate`는 Composition Root가 배선 대상을 import하지 않으면 경고.
- See also: `docs/history/reports/architecture_claim_review_2026_06_13.md`

### 8.6 `axiomEffect` Custom Pragma — Compile-Time Effect Annotation

Phase 1 of Self-Enforcing Architecture introduces `{.axiomEffect: Pure.}` and `{.axiomEffect: IoEffect.}` as first-class Nim custom pragmas, replacing the legacy comment-based `@axiom-effect` convention.

**Definition** (`src/core/trusted/axiom_pragmas.nim`):
```nim
type
  AxiomEffectKind* = enum Pure, IoEffect

axiomEffect* {.pragma.}
```

**nimtry queries using `axiomEffect`**:

| Query | Behavior | Violation |
|-------|----------|-----------|
| `effect-pragma-consistency` | Errors when `func` declares `IoEffect` or `proc` declares `Pure` | Contradicts Nim effect system: `func` implies no I/O; `proc` without `IoEffect` when it has I/O is incomplete |
| `effect-transitive-io` | Warns when a `proc` reaches I/O transitively (call-graph BFS) but lacks `IoEffect` | Incomplete effect contract — caller cannot distinguish I/O boundary procs from pure computation procs |

**nimtry detection mechanism**: `extractPragmasV4` traverses `nkPragma` AST nodes to find `axiomEffect` pragmas. Combined with call-graph BFS from `architecture_policy.lock` `[effect_hints]`, nimtry validates both explicit annotations and transitive reachability.

**`@axiom-effect` comment fallback**: Comment-based hints (`# @axiom-effect: IoEffect`) are retained only as a heuristic fallback for `split_by_effects.sh` [deleted] (see §11 of nim_effect_system_quirks.md).

### 8.7 `compositionRootGuard` — AST-Aware Import Completeness Check

`compositionRootGuard` is a compile-time macro that verifies Composition Root modules (§8.2) import all modules they wire. It uses `tokenizeImports`, a syntax-aware text scanner (imports are parsed in the limited compile-time macro context, not via PNode/compiler AST — see registry_macro.nim).

**`tokenizeImports` capabilities**:
- Aliases: `import foo as bar`
- Selective imports: `from X import Y, Z`
- Multi-line bracket imports: `import [\n  mod1,\n  mod2,\n]`
- Commented-out imports skipped: `# import dead_module`

**Limitations**:
- `declared()` checks **caller scope only** — it cannot verify whether a symbol exists in an imported module's public API. It only confirms the symbol is syntactically available at the call site.
- `compositionRootGuard` verifies **completeness** (all expected imports are present) but not **correctness** (whether the wiring logic is semantically correct).
- Multi-module Composition Roots may require multiple `compositionRootGuard` invocations if they span separate files.

### 8.8 Known Limitations

| Feature | Limitation | Mitigation |
|---------|-----------|------------|
| Multi-line imports | `tokenizeImports` handles bracket syntax but deeply nested pragmas may not parse | Manual review for edge cases |
| Aliases | `from X import Y as Z` — the alias is tokenized but `declared()` cannot trace through it | Accept: alias scope is caller-local |
| `{.effects.}` pragma | Outputs **exception effects only** (raises tracking), not side-effect analysis (`noSideEffect`/`func`) | Use `axiomEffect` pragma + nimtry `effect-transitive-io` for side-effect classification |
| `declared()` | Does not check imported module API surface — only caller's top-level scope | `compositionRootGuard` verifies import presence, not symbol resolution |
| `staticRead` | Compile-time file read; file changes require recompilation | Acceptable for `architecture_policy.lock` — policy changes are intentional |

### 8.9 Pre-Existing Fix: `persona_bridge_init.nim` Broken Import

During Phase 1, `compositionRootGuard` was applied to [DELETED] `persona_bridge_init.nim`. The guard detected a pre-existing broken import:

```nim
# ❌ BEFORE: import verification/universal_pipeline_core  # module does not exist
```

`verification/universal_pipeline_core` was a dead import — the module was never created (likely a planned but unimplemented abstraction). The wiring code `syncRecoveredSourceToModule` that depended on it was also non-functional.

**Fix applied**:
1. Removed the broken import
2. Replaced `syncRecoveredSourceToModule` wiring with a default no-op placeholder
3. Added comment noting the placeholder status pending proper implementation

This is not a Phase 1 regression — it was a latent build-breaking defect masked by the fact that `persona_bridge_init.nim` is a Composition Root that is only compiled when specific code paths are active.

### 8.10 Historical Example: Tree-sitter FFI Module Decomposition (Pre-Purge)

~~tree_sitter_ffi.nim~~ (deleted during tree-sitter purge) was previously refactored from a single monolithic FFI module into a cohesive package under `src/core/parsers/tree_sitter/`:

| Module | Responsibility | Exported Functions |
|--------|---------------|-------------------|
| `types.nim` | Distinct handle types, `OwnedTree` ARC owner, `isNil`/`raw`/`wrap` helpers | ≤ 12 |
| `bindings.nim` | Parser lifecycle and language grammar wrappers | 5 |
| `node.nim` | Tree/node access wrappers | 9 |
| `cache.nim` | Hash-based parse cache with ARC lifecycle | 2 |
| `nodes.nim` | High-level node inspection utilities | 3 |
| `tree_sitter_ffi.nim` | Forwarding stub; sole public entry point | 0 |

**Historical note**: This decomposition preceded the tree-sitter-to-compiler/parser migration. All tree-sitter FFI modules were subsequently removed. The pattern remains documented as a reference for FFI module decomposition best practices. Post-purge, AST parsing uses Nim compiler parser in-process — no external FFI, no C-side memory management, no ARC ownership rules for TSTree.

---

*Last updated: 2026-06-13*
