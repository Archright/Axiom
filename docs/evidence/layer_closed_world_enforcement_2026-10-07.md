# DEBT#287 Closed-World Layer Enforcement — 실행 증거 (2026-10-07)

Workstream: `feat/layer-closed-world-enforcement`
목적: layer_enforcement_gate의 마지막 fail-open 잔여물(unknown layer 소스 스킵)을 제거한다.
방법: (1) layer universe를 닫아 **현재 트리 판정을 바꾸지 않는 채**(verdict-neutral) 완전 분류를 달성,
(2) 그 후 unknown → FAIL fail-closed 전환, (3) push-admissibility 등록 + 운영 실측.
선행 기록: `docs/evidence/authority_boundary_simplification_2026-10-07.md` follow-up 목록의
"DEBT#287(layer 게이트 unknown-layer fail-open) 수정 — src/gate/** FROZEN" 항목이 본 슬라이스다.

## DEBT#287 생애주기 (in-place 재개 → 재바인딩 → 종결)

1. **재개 (in-place)**: registry 상태 closed → open. 2026-07-28 종결 이후에도 런타임
   잔여물이 생존했음을 기록 — `scanFile`이 `srcLayer == "unknown"` 파일을 통째로
   스킵(fail-open), 실측상 `src/bin/ax.nim`·`src/bin/run_gate.nim` 2파일이 미검사.
2. **contentHash 재바인딩**: `bin/debt_engine --codegen` → `--regen-arch` —
   `data/architecture_debt.json` entry[245](`src/core/trusted/layer_enforcement.nim`)의
   `rawContentHash`/`canonicalSyntaxHash` 2행만 갱신(surgical diff), 구조적 FAIL 해소.
3. **종결**: closed/FIXED, 종결 근거·증거 링크를 description에 이중 기입.
   `--codegen`(투영 2종 재생성) + `--validate`(1394 checks) + `--sync-budget` 전부 통과.

## Phase 1 — verdict-neutral universe 폐쇄

### 규칙 테이블 개편 (LayerRules 12 → 6)

`isAllowedImport`는 레이어 키(`srcLayer == inferLayer(rule.source)`) first-match 매칭이다.
구 테이블 12개 규칙 중 **7개가 도달 불가능**(shadowed)했다:

| 계층 | 살아있는 규칙 | 가려진(shadowed) 규칙 |
|---|---|---|
| infrastructure | `src/verification/` (rule[1]) | `src/engine/`, `src/frontend/`, `src/sieve/`, `src/personas/`, `src/infrastructure/`, `src/generated/` (6개 — 전부 같은 레이어로 추론되어 rule[1]에 흡수) |
| presentation | `src/cli/` (rule[4]) | `src/mcp/` (rule[7]) |

조치: 가려진 6개 infra 규칙 **삭제**(현재 그래프는 이미 rule[1]로 심의되고 있었으므로
판정 불변), `src/mcp/`는 **자체 레이어 "mcp"로 분리해 활성화**(0-flip 실측, 아래).
`inferLayer`에 `src/bin` → presentation 추가. `layer_declaration.nim`의 죽은 중복 매핑
`inferLayerFromPath` + 미사용 `Layer*` 상수 제거(사용처 0건 실측, inferLayer와 이미 불일치).

### naive per-path pairing 기각 (실측)

전체 규칙을 경로 prefix 매칭으로 전환하는 설계를 실측 평가했다: **124 flip**
(그중 실 판정 역전 4건 — `src/personas/legislator.nim:15`, `src/generated/gate_registry.nim:3`,
`src/engine/proof_certificate.nim:23`, `src/infrastructure/external_ir_materializer.nim:27`;
나머지는 rule 미매칭 NO-RULE 경로). import graph 보존 원칙에 따라 레이어 키 매칭 +
레이어당 단일 규칙 설계를 채택했으며, 코드 import는 1줄도 변경하지 않았다.

### verdict-neutral 입증 (apples-to-apples)

| 측정 | 결과 |
|---|---|
| 구 바이너리(main 클론) vs 신 바이너리, 동일 트리 `--report-only` | **바이트 동일** (`PASS — no layer violations in 1581 files`), diff-empty |
| 동일 트리 정의 | 워크트리에 헤르메틱 시드가 생성한 `src/generated/build_env.nim` 포함 동일 상태에서 상호 실행 |
| mcp 활성화 liveness | 합성 샌드박스 `src/mcp/edge.nim → import cli/something`: 구 바이너리 PASS(규칙 죽음=theater), 신 바이너리 **BLOCK** (`LAYER VIOLATION … from mcp`) |
| static_analyzer verdict-neutral | 동일 바이너리를 pristine origin/main 트리 vs 본 트리에 실행 — 21,281행 리포트 **동일** (차이는 `durationMs` 타이밍 필드뿐). rc=1은 main 원래 판정으로 본 변경과 무관 |
| 닫힌 우주 구성 (신 바이너리 `--json`) | domain 666 · infrastructure 334 · gate 206 · presentation 87 · mcp 4 · tools 284 = **1,581 파일, unknown 0**, 에지 8,728 |

## Phase 2 — fail-closed 전환

- `scanFile`의 unknown 스킵 제거: unclassified 파일은 `vkUnknownLayer` 위반
  (`LAYER VIOLATION: <file> — unclassified layer (fail-closed, DEBT#287)`) → strict exit 1.
- `--json` 모드 추가: 고정 키 순서 수작업 직렬화(std/json 객체 필드는 해시 순서라 불결정),
  verdict/fileCount/edgeCount/layerCounts/violations. `--report-only` 출력은 **바이트 불변**
  유지(`tools/debt_engine.nim` `evalLayerViolations`의 `N layer violation(s)` 파싱 계약 보존).
- 파일 열거 정렬 → 동일 입력 → 동일 출력(결정론).
- `/trusted/` 스캔 면제는 유지(문서화된 면제 — trusted는 전 계층 import가 합법).

## 배선 (게이트 등록)

- `Makefile`: `bin/layer_enforcement_gate` 빌드 규칙(4 소스 의존: runner + layer_rules +
  layer_enforcement + layer_declaration) + `check-layer-enforcement` + `check-layer-negative`.
- `GATES_STATIC` 12→14, `PUSH_ADMISSIBILITY_GATES` 12→14 (thin target 레시피에 2줄 추가,
  `AXIOM_ROOT="$(CURDIR)"`로 스냅샷 OID 트리를 스캔 — getAppDir 기반 root 해석의 스냅샷
  편차 제거).
- `check-push-admissibility-integrity` → PASS (14게이트 ⊆ 알려진 유니버스).
- `.githooks/pre-push` Part 4: pair 목록 + `bin/layer_enforcement_gate` symlink 추가.
  staleness는 Part 3이 동일 바이너리를 `layer_rules.nim`/runner 기준으로 재빌드하므로
  Part 4 identity check이 그 신선도를 상속 (bash -n 통과).
- 정책 선행 착지 확인: #523·#525 MERGED (2026-10-07T01:00/01:03Z) + 정책 v59 (#526)
  MERGED — base-policy v59에서 본 PR이 건드리는 3경로(`Makefile`·`.githooks/pre-push`·
  `src/gate/runners/layer_enforcement_gate.nim`)는 모두 CONTROLLED 재등록 상태.
  리베이스 후 실측: `make check-repository-surface` → **PASS (rc=0, add 3 / modify 10 /
  delete 0)** — FROZEN 위반 0건, 자문 검사도 green으로 push.

## 부정 fixture (liveness 하니스)

`tests/negative/layer_gate/{unknown_layer,forbidden_import}/src/...` 샌드박스 2종 +
`make check-layer-negative`:

| fixture | 기대 | 실측 |
|---|---|---|
| `unknown_layer/src/mystery/orphan.nim` | 결정론 FAIL | rc=1, `unclassified layer (fail-closed, DEBT#287)` 출력, 2회 실행 동일 |
| `forbidden_import/src/core/bad_boundary.nim` (`import mcp/tools`) | 결정론 FAIL | rc=1, `imports 'mcp/tools' (unknown from domain)` 출력, 2회 실행 동일 |

positive 경로는 본 트리에서 `check-layer-enforcement` PASS(1581 파일). PASS 시 fail-open
회귀로 간주해 하니스가 FAIL시킨다(죽은 게이트 방지, §0.9).

## nimtry 재앵커 (v18 선례)

신규 fingerprint 4건 실측 → 3건은 코드로 정정(func 전환 2건, `ViolationKind`→
`LayerViolationKind` SSOT 중복 해소, 미사용 헬페이지 인라인), 잔여 1건
(`solid-ocp` 9 case branches — JSON 이스케이프·이중 포맷 렌더링의 본질적 case)은
`bin/nimtry --update-baseline src/`로 재앵커(v2 fingerprint 프로토콜, 4095 freeze).
이후 `--sync-budget`로 `nimtry_violations` current 재수렴, `--validate`/`check-debt` green.

## 범위 정직화 — closed universe의 실제 경계

- **닫힌 것**: `src/`·`tools/`의 모든 `.nim` 파일(소스 측)이 6개 등록 레이어 중 정확히
  하나로 분류되고, 각 레이어는 도달 가능한 규칙을 정확히 하나 가진다. unknown 소스는 FAIL.
- **blind spot (미닫힘, 문서화된 면제/외부)**:
  1. `src/**/trusted/**` — 스캔 면제(전 계층 import 합법, 기존 계약).
  2. 단일행 slash-form `import`/`from`만 파싱 — multi-line import, 비-slash 형제 import,
     `include`, 매크로 생성 import는 미검사.
  3. `std/`·nimble 외부 패키지 타깃은 레이어 우주 밖(규칙 prefix 목록으로만 심의).
  4. `tests/`·`experiments/`·`bin/` 소스는 스캔 제외(게이트 스캔 루트는 src/tools 고정).
  5. 위반 메시지의 `targetLayer` 표시는 내부 타깃에 "unknown"으로 나옴(모듈 경로에 src/
     prefix 부재 — 표시 전용 한계, 심의 영향 없음).
  6. root 해석은 `AXIOM_ROOT` env를 신뢰(문서화된 env 계약 — 스냅샷/샌드박스 주입에 사용).

## 착지 전 실측 요약 (워크트리, 커밋 기준)

| 항목 | 관측 |
|---|---|
| verdict-neutral | 구/신 바이너리 `--report-only` 바이트 동일 (1581 파일) |
| mcp liveness | 합성 간선 구 PASS → 신 BLOCK |
| fail-closed liveness | 부정 fixture 2종 rc=1 결정론 |
| push-admissibility | `check-push-admissibility-integrity` PASS, thin target 14게이트 |
| debt | `--codegen`/`--validate`(1394 checks)/`--sync-budget`/`make check-debt` 전부 PASS, DEBT#287 closed |
| check-arch | PASS (재앵커 후) |
| static_analyzer | verdict-neutral (리포트 동일) |
| 컴파일 타임 | `nimble build` 실측은 후속 증거 PR에 기록 |

## main 병합 후 운영 실측 (acceptance record, 선례: #517)

병합: PR #528 → main MERGE 커밋 `0599f2a7ca6d68f6f8e13fc6a4e6e59a7bde6a7e`
(merge queue — 큐 ref `admission-gate` success 후 GitHub 병합, mergedAt 2026-10-07T02:01:55Z).
측정 환경: 병합 SHA pristine worktree (메인 클론 무변경), 게이트 바이너리를 병합 트리
소스에서 재빌드(`-d:danger`).

| 항목 | 명령 | 관측 |
|---|---|---|
| (a) positive | `bin/layer_enforcement_gate --report-only` (병합 트리 재빌드 본) | **PASS — no layer violations in 1581 files**, rc=0 |
| (a2) verdict-neutral 재입증 | merge-base 바이너리(`4337a17fd` 빌드)를 `AXIOM_ROOT=<병합 트리>`로 동일 트리 실행 후 diff | **바이트 동일** — 병합 후에도 판정 불변 |
| (b) 부정 fixture | `AXIOM_ROOT=tests/negative/layer_gate/{unknown_layer,forbidden_import}` + `--strict` | rc=1 ×2 결정론 — `unclassified layer (fail-closed, DEBT#287)` / `imports 'mcp/tools' (unknown from domain)` |
| (c) 등록 무결성 | `make check-push-admissibility-integrity` | rc=0 — 14게이트 ⊆ 알려진 유니버스 (layer 2게이트 포함) |
| (d) 결정론 | `--json` 2회 바이트 비교 | 동일; `fileCount 1581 / edgeCount 8728`, layerCounts {domain 666, gate 206, infrastructure 334, mcp 4, presentation 87, tools 284}, violations [] |
| (e) debt 정합 | `bin/debt_engine --validate` + registry 조회 | rc=0, DEBT#287 `closed/FIXED`, `tools/debt_engine.nim`의 `layer violation(s)` 파싱 계약 3처 유지 |
| 컴파일 타임 | `time nimble build` (병합 트리, cold) | rc=0 — wall **2:35.97**, user 266.26s, maxRSS ~992MB |

## follow-up (범위 밖, 기록용)

- multi-line/비-slash import 파싱 확장, destination(타깃) 측 완전 분류.
- `solid-ocp` 앵커 1건의 구조적 해소 여부는 별도 판단 과제.
