# VS-IR-PRECOMPUTE-SCOPE — fetch widening ≠ execution budget (2026-11-21)

> 범위: phase-10 IR precompute가 VKD ratchet pool 전체를 executor에 넘기던 것을
> 요청 키(＋JRPC carrier) 교집합으로 제한한 변경의 동등성·성능 측정과
> canonical main 착지 후 재관측.
> 기록자 ≠ 승인자: 작성자는 agent, 승인자는 사용자(wintrover)다.
> 이 문서는 측정·관측만 기록한다. 판정 계약의 정의는 `docs/spec/productization_contract.md`가 소유한다.
> **이 수치는 로컬 16 CPU 호스트의 측정이며 CI Merge Queue SLO 측정값이 아니다.**

## §0. 착지 경위 — ROT_ALLOWLIST 실측과 착지 분해

최초 단일 PR(#306, head `75769ad`)의 merge_group verdict(run `44883641559`)는
`mergeAborted / ROT_ALLOWLIST`로 fail-closed했다. 후보 delta가 trusted checker closure를
변경(ROTATION)하면 **모든** changed path가 allowlist 안이어야 하는데(ADR-0025 A2),
`tests/unit/ir_precompute_scope_test.nim`(신규)과 `data/debt_reduction_baseline.json`이
allowlist 밖이었다. trust surface(`src/cli/merge_cli.nim`)를 건드리지 않고 해소하기 위해
다음으로 분해했다.

| 단계 | PR | 변경 | 경로 분류 |
|---|---|---|---|
| A | #316 | `data/debt_reduction_baseline.json` 4374→4381 (count-only) | closure 밖 → NORMAL |
| B | #306 (재구성) | 소스 2파일 + 생성 메타데이터 + baseline/arch hash + closure pin 재앵커 | 전부 allowlist 안 → ROTATION |
| C | #320 | 회귀 테스트 + `TESTS_FAST_UNIT` 등록 (merge `48ea64f`) | closure 밖 → NORMAL |
| D | 본 문서 | evidence | closure 밖 → NORMAL |

## §1. 기준점과 환경

| 항목 | 실측값 | 명령 |
|---|---|---|
| 변경 전 main | `f68ca0f` | `git log -1` |
| PR-A merge commit | `974f4af` (PR #316) | `gh pr view 316 --json mergeCommit` |
| PR-B merge commit | `4ea334d` (PR #306) | `gh pr view 306 --json mergeCommit` |
| PR-C merge commit | `48ea64f` (PR #320) | `gh pr view 320 --json mergeCommit` |
| 호스트 | 16 CPU / 30 GiB / Linux 6.17.0-42-generic x86_64 | `nproc`, `free -g`, `uname -srm` |
| Nim | 2.2.10 | `nim --version` |
| 실행 모드 | release (`make build` 기본) | `bin/ax --version` |

## §2. 변경 인벤토리

| 파일 | 변경 |
|---|---|
| `src/cli/axiom_engine.nim` | phase-10: `selectProofCandidates` pool은 그대로 두고, 요청 노드 `(modulePath, functionName)` ∪ JRPC `errclassResultKey`(P1..P13) 키 집합과의 결정론적 교집합만 `irCtx.entries`로 전달. 로그에 `pool/requests/required/executed` 기록 |
| `src/verification/batch_uap/loop_driver.nim` | pure `func scopeIrEntriesToRequiredKeys(entries, requiredKeys, cwd)` — pool 순서 보존, raw/normalized 두 키 규칙 수용. `normalizeScopeModulePathAt(rawPath, cwd)`로 정규화 규칙을 순수 함수로 분리하고 기존 `normalizeScopeModulePath`는 IO 래퍼로 유지. `preComputedIrProvided`로 "미제공(None)"과 "제공됐고 0건(Some(@[]))"을 구분 |
| `tests/unit/ir_precompute_scope_test.nim` | 7 tests (순서 보존, 0건, identity, absolute→normalized, 외부 경로 fail-closed, raw 매칭, provided-empty 배선 가드) — 후속 PR |
| `data/nimtry_baseline.json` / `data/debt_reduction_baseline.json` | 래칫 재앵커 4381 (main live = main 선언 = 4381; 이 슬라이스의 순증 0) |
| `data/architecture_debt.json` | `bin/debt_engine --regen-arch` (2 entries) |
| `config/trusted_checker_closure.json` | `bin/reanchor_pin` (④ new anchor) |

## §3. 동등성 (동일 트리, 두 바이너리 A/B)

교차 5쌍(`normalizeMaxWorkers`, `safeSpeedupRatioCore`)에서 다음이 **완전 동일**했다.

| 표면 | 결과 |
|---|---|
| `nodeReports` (verdict 포함) | 동일 — normalize=verified, safe=failed 양쪽 |
| `metrics` | 동일 |
| `certificates` | 동일 |
| exit code | 동일 (0 / 1) |

`report --canonical-digest`는 각 바이너리 내 5회 동일(결정론). 두 바이너리 간에는 다르며,
원인은 `executionIdentity.verifierBuildId`(빌드 identity 회전), 타이밍 필드,
run-scoped 실행 회계(`executionStats.eligibleTargets` 4→1, `unitEvidenceRefs` 3키)뿐이다.
이는 `canonical_projection.nim`의 volatile 목록이 실행 회계를 제외하지 않기 때문이며,
"실행 범위 변경이 digest를 이동시킨다"는 별도 결정 사안이다(이 슬라이스는 결정하지 않음).

JRPC 경로: `tests/unit/test_jrpc_errclass_binding.nim` 55/55 OK — P1..P13 carrier가
교집합에서 누락되지 않음을 확인.

## §4. 성능

### 4.1 착지 전 A/B (동일 working tree, 교차 5쌍, warm)

명령: `AXIOM_CI=1 <bin> prove --target <T>` (base = main f68ca0f release 빌드,
new = 변경 브랜치 release 빌드). 원본: `build/tmp/vs-ir-scope/summary.txt`, 각 실행의
`.traj.jsonl`(`ir-thread window completed`).

| 타깃 | wall 중앙값 (base → new) | IR 창 중앙값 (base → new) | exit |
|---|---|---|---|
| normalizeMaxWorkers | 5,153 → **2,802 ms** | 3,196 → **872 ms** | 0 / 0 |
| safeSpeedupRatioCore | 4,856 → **2,382 ms** | 3,028 → **524 ms** | 1 / 1 |

`topology scan`/`graph hydration`는 불변(중앙값 478–526 / 170–174 ms).
base 로그는 `IR extraction — 4/231 entries (limit=1)`, new 로그는
`pool=4/231 requests=1 required=1 executed=1 (limit=1)`.

### 4.2 main 착지 후 재관측 (`4ea334d`)

명령: `make build` → `AXIOM_CI=1 bin/ax prove --target <T>`. 원본: `build/tmp/vs-ir-scope-accept/`.

| 항목 | 실측값 |
|---|---|
| `make build` | exit 0, `✅ Build successful` |
| `bin/ax --check-provenance` | `OK — embedded BuildSourceHash == live src tree (vs1-tree-hash/1:-6394464270943497635)` |
| normalizeMaxWorkers ×4 | exit 0/0/0/0, wall 3,919 / 2,932 / 2,831 / 3,436 ms (첫 실행 cold) |
| normalize IR 창 ×3 | 825 / 848 / 835 ms |
| safeSpeedupRatioCore ×1 | exit 1 (기존과 동일), wall 2,526 ms, IR 창 539 ms |
| phase-10 로그 | `pool=4/231 requests=1 required=1 executed=1 (limit=1)` |
| `report --canonical-digest` ×2 | 동일 — `2656f65571a627aeb8523994d4e278447a46d7f15e7e3b07a47b7d6beba46330` |
| `report --json` | `nodeReports: 1` — `src/core/orchestrator/orchestrator_api.nim::normalizeMaxWorkers` → `verified` |

main 기준 IR 창은 착지 전 A/B의 new 값(872/524 ms)과 같은 대역이며, base(3,196/3,028 ms) 대비
약 3.8×/5.6× 단축이다. 절대 wall 값은 호스트 부하에 따라 변동한다(R8: 성능은 판정 입력이 아니다).

## §5. 한계

- 이 측정은 로컬 호스트의 단일 워크로드 2종이며, VKD 분자·분모는 변경 전후 모두 불변이다.
- `executionStats`/`unitEvidenceRefs`가 canonical projection에 포함되므로, 실행 범위를
  바꾸는 최적화는 `report --canonical-digest`를 이동시킨다. 판정 표면(verdict/tier/VKD)은 불변.
- 래칫 cap 4381은 위반 해소가 아니라 **선언=실측 재앵커**다(감축은 별도 작업).
- JRPC carrier 경로는 unit(55/55)로 닫았으며, 실제 JRPC lane `prove` 실행 증거는 이 슬라이스에 포함하지 않았다.

## §6. Release 전환의 의미 검증 (컴파일러·계약 대조)

release 기본 전환이 "검사 제거"를 뜻하는지 pinned toolchain과 계약 문서로 대조했다.

| 질문 | 근거 | 결과 |
|---|---|---|
| `-d:release`가 bounds/range/overflow/assert를 끄는가? | `compiler/commands.nim:525-537` (nim 2.2.10), `config/nim.cfg:86-94` | **아니오.** release는 `optStackTrace`/`optLineTrace`/`optLineDir`만 제외하고 `optOptimizeSpeed`를 켠다. `optBoundsCheck`/`optRangeCheck`/`optOverflowCheck`/`optAssert`는 **유지**된다. 그 제거는 `-d:danger`(또는 `-d:quick`) 전용이다. |
| Axiom에서 사라지는 계약 검사는 무엇인가? | `src/core/contracts/spec_binding_macro.nim:107,115,180,188` | `requires`/`ensures` DbC가 `when not defined(release)`로 컴파일 아웃된다. 모듈 docstring(:8)이 "non-release 빌드 전용, production zero cost"를 명시한 **의도된 개발용 진단**이다. 판정은 이 런타임 DbC가 아니라 증명 파이프라인이 낸다. |
| `except Defect` 처리(8곳)는 release에서 유효한가? | `config.nims:47-49` `switch("panics","on")` + `lib/system/excpt.nim:487-491` | **유효하지 않다.** panics:on에서 Defect는 `reportUnhandledError` 후 `rawQuit(1)`이라 `try/except`가 잡지 못한다(`src/cli/main.nim:112` 포함 8곳 모두). |
| 그때 exit code는? | probe: `nim c --panics:on` + out-of-bounds → `unhandled exception ... [IndexDefect]`, **exit 1**; `--panics:off` → catch → exit 2 | 계약(`docs/spec/productization_contract.md` §v1 CLI Exit-State)의 `1`=VERIFICATION_FAILURE, `2`=INTERNAL_ERROR와 대조하면 **crash가 `1`(fail-closed 상태)로 오분류**된다. 거짓 PASS를 만들 수는 없으나 `internal-error` 상태의 식별은 상실된다. 계약 문서의 해당 행은 "139(SIGSEGV), CLI 경계 핸들러 없음"으로 **현재 코드와 불일치**(OPEN-ITEM)다. |

이 항목은 이 슬라이스에서 변경하지 않았다 — `config.nims`와 `main.nim`은 trust surface이며
수정은 VerifierBuildId·RecipeDigest 회전을 동반한다(§2.6 authority/invariant protocol).