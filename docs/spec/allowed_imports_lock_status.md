# `src/allowed_imports.lock` — Authority Status Settlement

**일자**: 2026-10-11
**검증 커밋**: `5af2afd6e` (브랜치 `feat/rl14-4-execution-authority`)
**작업**: RL-14.4 workstream — S4 (SSOT 주장 정리)
**규칙 근거**: AGENTS.md §0.5c / §0.9a (무음 패치 금지), `docs/agents/architecture.md` (Immutable Policy Artifacts — `docs/agents/*.md` 읽기 전용)

---

## 1. 판정 (Settled Verdict)

**판정: (b) retired-but-unrecorded — 이미 은퇴했으나 기록되지 않은 좀비 아티팩트.**

`src/allowed_imports.lock`은 (a) canonical이 아니다. 폐쇄 임포트 행렬의 정본은
`src/core/trusted/layer_rules.nim`(레이어 방향, `src/core/trusted/layer_enforcement.nim`이 소비)과
`src/gate/architecture_policy.lock`(모듈 롤/화이트리스트 정책)이며, 이 파일을 의미론적으로
읽는 라이브 소비자는 존재하지 않는다. 2026-07-25 자동시정 캠페인이 2026-06 스캔의
"Create or remove" 권고를 '글자 그대로'(파일 부재 해소)만 이행하며 소비자 없이 재생성한
것이다. 컨텐츠는 현행 헌법(RL-14.4)과 정면 모순된다.

**시행 조치 (본 세션)**: `constitutional_rules.lock:1` 선례를 적용해 파일 헤더를
Deprecated 선언으로 교체하고 정본 후계자를 명명했다. 파일은 기존 참조 해소를 위해
본문째로 보존한다(삭제하지 않음). 판정 근거는 아래 §2–§5.

---

## 2. 증거 테이블 (커밋 `5af2afd6e` 기준 재검증)

| 위치 (현행) | 주장 | 실제 | 판정 |
|---|---|---|---|
| `src/allowed_imports.lock:1` | "Allowed Imports Matrix — **SSOT** Layer Access Control" | 자기 선언. 이를 뒷받침하는 ADR·waiver·debt 레지스트리 기록 0건 (`docs/adr/`, `config/decision_binding.waiver.*`, `data/debt_registry.json` grep → 0 히트) | FALSE (self-declaration) |
| `src/allowed_imports.lock:4` | "Violations are enforced by **import_encapsulation_gate.nim** at runtime." | `src/gate/runners/import_encapsulation_gate.nim`은 허브 우회 스캐너이며 `allowed_imports` 참조 0건 — lock을 읽지 않는다 | FALSE |
| `docs/agents/core_rules.md:363` | 행렬이 "`src/allowed_imports.lock`에 SSOT로 인코딩"되며 "`make check-imports`"와 "`layer-enforcement-gate`"가 강제 | `make check-imports`는 실존(Makefile:129)하나 `tools/check_imports_ast.nim:23`의 스캔 대상은 `ForbiddenPaths = ["tools/", "kimi-sdk/"]`뿐 — lock을 읽지 않는다. `src/gate/runners/layer_enforcement_gate.nim`은 `core/trusted/layer_enforcement`(LayerRules)를 소비한다 | FALSE (SSOT 부분) |
| `docs/agents/core_rules.md:385` | "Role Registry: `src/allowed_imports.lock` owns `@module-role` entries" | 파일에 `@module-role` 0건. 롤은 `src/gate/architecture_policy.lock` `[module_roles]`(47행)으로 이관됨 — `docs/history/2026_05_refactoring.md:1520-1521` | FALSE |
| `docs/agents/core_rules.md:386` | "Policy Validator: `src/gate/runners/policy_validator.nim` ensures `allowed_imports.lock` format compliance" | `policy_validator.nim:36`는 `AllowedImportsPath = ".config/nimtry/allowed_imports.lock"`을 검사 — **다른 파일**(외부 의존성 allowlist, 같은 basename). `src/allowed_imports.lock`은 검사 대상 아님 | FALSE |
| `docs/agents/core_rules.md:391` | "exceptions are explicit `@module-role` policy entries **in `src/allowed_imports.lock`**" | 동일 — 파일에 `@module-role` 없음 | FALSE |
| `src/core/gate/gate_resolver.nim:18-19` | "importable from both the gate layer and the presentation layer per allowed_imports.lock" | 죽은 규범 참조(주석). 본 세션에서 `src/core/trusted/layer_rules.nim` 지칭으로 수정 — 로직 변경 없음 | FIXED (주석만) |

`src/` 전역에서 `allowed_imports` 문자열을 참조하는 파일은 4개뿐이며, 모두 의미론적
소비자가 아니다: `mcp_tool_usage_gate.nim`(.config/nimtry 존재·비어있음 검사),
`policy_validator.nim`(.config/nimtry 검사), `topology/manifest.nim`(무관한 JSON 키),
`gate_resolver.nim`(주석 — 수정됨).

---

## 3. 연혁 (Timeline)

| 시점 | 커밋/문서 | 사건 |
|---|---|---|
| 2026-05 | `0226319b7` | 초기 버전 존재 |
| 2026-05 | `docs/history/2026_05_refactoring.md:1520-1521` | `constitutional_rules.lock` 폐기와 함께 **module roles를 `src/allowed_imports.lock`에서 `architecture_policy.lock`으로 이관** — 은퇴의 실질 시점 |
| 2026-06-08 | `d3606a6a2` | domain sharding 캠페인에서 파일 **삭제** (`--diff-filter=D` 확인) |
| 2026-06-12 | `docs/evidence/verifications/full_debt_scan_2026_06_12.md:181,234` | 스캔 결과 "S3: allowed_imports.lock Missing" / "P2·S3: **Create or remove**" |
| 2026-07-25 | `2f8edba6d` | 3-phase auto-remediation 캠페인이 **소비자 없이 재생성**(+40행) — 권고의 'create' 글자만 이행. 이때 1·4행의 허위 SSOT/enforcement 주장이 (재)도입됨 |

---

## 4. 컨텐츠 모순 (RL-14.4와의 정면 충돌)

`src/allowed_imports.lock:6-7`(재생성 시점 기준):

```toml
[core]
allow = ["core", "engine", "gate", "infra", "verification"]
```

`docs/agents/core_rules.md:231` — **RL-14.4**: "`src/core/` importing `src/verification/`,
`src/cli/`, `src/mcp/`, `src/ui/`, or `src/gate/` is an immediate revert offense."

즉 이 행렬은 core→gate, core→verification을 허용하며, 현행 헌법이 즉시 되돌리기
위반으로 규정하는 방향을 허가한다. 또한 섹션명(`[infrastructure]`)과 허용 대상명
(`"infra"`)이 불일치하는 등 내부 정합성도 없다. 어느 게이트도 이 파일을 파싱하지
않으므로 이 모순이 오류로 포착될 경로가 없었다 (극장 — AGENTS.md §0.9).

---

## 5. 소비자 분석

- **의미론적 파서: 0개.** `src/`, `tools/`, `.githooks/`, `Makefile`, `config/` 어디에도
  `src/allowed_imports.lock`을 읽는 코드가 없다.
- **구조적 리더 1개**: `tests/integration/test_policy_validator_cli.nim:66-85` —
  TOML 유사 섹션 형태만 검사(주석 외 모든 행이 `[section]` 또는 `key = value`인지).
  의미를 검사하지 않으며, Deprecated 헤더 교체 후에도 통과한다.
- `tests/features/policy_validator.feature:11`이 `"src/allowed_imports.lock"`을 지칭하나
  대상 게이트가 실제로 검사하는 것은 `.config/nimtry/allowed_imports.lock`이다 (별개 파일,
  본 정리 범위 밖 — follow-up).

---

## 6. `docs/agents/core_rules.md` 교정 초안 (제안 — 본 문서는 읽기 전용 SSOT이므로 직접 수정하지 않음)

`docs/agents/*.md`는 읽기 전용 정책 SSOT(`docs/agents/architecture.md` "Immutable Policy
Artifacts")이므로, 아래 교체 문안은 승인된 개정 경로로 반영해야 한다.

### 363행 (현행 → 교체)

현행:
> The matrix below defines ALLOWED import directions. Any import NOT explicitly listed as ALLOWED is DENIED. The matrix is encoded as the SSOT in `src/allowed_imports.lock` and enforced by `make check-imports` (`tools/check_imports_ast.nim`, AST-based) and by the `layer-enforcement-gate` (`src/gate/runners/layer_enforcement_gate.nim` → `bin/layer_enforcement_gate --strict`) in `.githooks/pre-commit`.

제안 교체:
> The matrix below defines ALLOWED import directions. Any import NOT explicitly listed as ALLOWED is DENIED. The matrix is encoded in `src/core/trusted/layer_rules.nim` (consumed by `src/core/trusted/layer_enforcement.nim`) and enforced by `make check-imports` (`tools/check_imports_ast.nim`, AST-based forbidden-path scan) and by the `layer-enforcement-gate` (`src/gate/runners/layer_enforcement_gate.nim` → `bin/layer_enforcement_gate --strict`) in `.githooks/pre-commit`. `src/allowed_imports.lock` is deprecated and non-normative (see `docs/spec/allowed_imports_lock_status.md`).

### 385행 (현행 → 교체)

현행:
> - **Role Registry**: `src/allowed_imports.lock` owns `@module-role` entries for cohesive public API catalogs and import facades. Unregistered modules still use the default SRP/import-count limits.

제안 교체:
> - **Role Registry**: `src/gate/architecture_policy.lock` owns module-role policy entries (`[module_roles]` section) for cohesive public API catalogs and import facades. Unregistered modules still use the default SRP/import-count limits. (`src/allowed_imports.lock` is deprecated and non-normative — see `docs/spec/allowed_imports_lock_status.md`.)

### 386행 (현행 → 교체)

현행:
> - **Policy Validator**: the source `src/gate/runners/policy_validator.nim` ensures `allowed_imports.lock` format compliance (deterministic format, deduplication, sorting). It must be built before use (e.g., `nim c -o:bin/policy_validator src/gate/runners/policy_validator.nim`); the `bin/policy_validator` binary is not built by a Makefile target.

제안 교체:
> - **Policy Validator**: the source `src/gate/runners/policy_validator.nim` ensures format compliance (deterministic format, deduplication, sorting) for `src/verification/.physically_impure_modules` and the external dependency allowlist `.config/nimtry/allowed_imports.lock` — a different file from the deprecated `src/allowed_imports.lock`. It must be built before use (e.g., `nim c -o:bin/policy_validator src/gate/runners/policy_validator.nim`); the `bin/policy_validator` binary is not built by a Makefile target.

### 391행 (현행 → 교체)

현행:
> There are no active Domain → Infrastructure grandfathered imports. Cohesive-module and import-facade exceptions are explicit `@module-role` policy entries in `src/allowed_imports.lock`; they do not permit forbidden layer direction.

제안 교체:
> There are no active Domain → Infrastructure grandfathered imports. Cohesive-module and import-facade exceptions are explicit policy entries in `src/gate/architecture_policy.lock`; they do not permit forbidden layer direction.

---

## 7. 후속 조치 (본 작업 범위 밖)

1. **M-40 (폐쇄 임포트 행렬) 구현** — 명시적 follow-up. 본 정리는 이를 해결했다고
   주장하지 않는다. Deprecated 선언은 허위 SSOT 주장을 제거할 뿐, 폐쇄 행렬의 부재를
   남긴다.
2. **debt 등록** — 본 정리(좀비 SSOT 자칭 + 무음 재생성)는 §0.9a상
   `data/debt_registry.json` 등록 대상이나, `bin/debt_engine`에는 항목 추가
   서브커맨드가 없다(§8). 상위 세션의 등록 대기.
3. `docs/agents/core_rules.md` 교정 반영 (위 §6 초안, 승인 경유).
4. `tests/features/policy_validator.feature:11`의 `src/allowed_imports.lock` 지칭은
   실제 검사 대상(`.config/nimtry/allowed_imports.lock`)으로 정정 필요 — tests 트랙 소관.

---

## 8. debt_engine 등록 불가 기록

`bin/debt_engine --help` (2026-10-11 기준) 서브커맨드: `--codegen`, `--validate`,
`--validate-metrics`, `--regen-arch`, `--prune`, `--sync-budget`, `--audit-dir-doc`,
`--baseline-verify`, `--lineage-check`, `--ratify`. **항목을 추가하는 서브커맨드는
존재하지 않는다.** ADR-0029 단일 기록자 원칙상 JSON 수동 편집은 금지되므로, 등록은
`debt_engine`에 add 서브커맨드가 제공된 후 상위 세션이 수행해야 한다. 등록 시 필요
최소 정보: `files: ["src/allowed_imports.lock:1-4", "src/core/gate/gate_resolver.nim:18-19"]`,
`category: Theater/` 접두 권장, `source` 근거 문서 = 본 문서.
