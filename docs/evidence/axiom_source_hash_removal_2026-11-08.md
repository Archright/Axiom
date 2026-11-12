# AxiomSourceHash 검증자 제거 — 기계 검증 증거 (2026-11-08)

> **종류**: 제거(removal) 증거 기록. **판정 권위는 기계 관측이며, 이 문서는 그 기록이다.**
> **Date**: 2026-11-08 · **Branch**: `workstream/axiom-source-hash-removal` (base `bf9fe5eda` = main @ PR #10 merge)
> **대상**: 사(dead) AxiomSourceHash stale-binary 검증자 — 주입 경로(config.nims) + 런타임 검사 블록(gate_hook.nim) + `GateRunnerSourcePaths`
> **경위**: 본 슬라이스는 최초 clean-origin 마이그레이션 이전 lineage(`174a999d7`, 구 PR #1289 merge)에서 준비·검증되었고, GitHub 저장소가 2026-11-06 clean-origin 재생성(신규 PR #1–#5, "VS-4/VS-5B clean-origin verification")된 뒤 새 main(`bf9fe5eda`)에 동일 변경을 재적용했다. 두 base의 `config.nims`·`src/gate/runners/gate_hook.nim`은 **바이트 동일**(측정)이므로 제거 diff·검증은 양쪽에 동등하게 유효하다.

---

## §1. 판정 근거 (사전 조사 — 제거 정당성)

조사 결론(2026-11-08, 본 슬라이스 착수 전 확정): **AxiomSourceHash 검증자는 사(dead) 코드다.**

1. **주입 경로 단일·수동**: 전 저장소에서 `-d:AxiomSourceHash=`의 유일한 주입 지점은 `config.nims:184`의 수동 nim 태스크 `buildGateRunners`다. 자동 호출자는 0건 — 실제 빌드 경로 전부(ci/checker.mk:524 `ci-compile-gate-hook`, `tools/build_all_gates.nim:278-291`, Makefile 패턴, `.githooks/*`, `.github/workflows/*`, `config.nims` `buildGatesFromManifest`)이 이 define 없이 컴파일하므로 검사 블록은 컴파일 아웃된다. 제거 전 라이브 `bin/gate_hook` 문자열 관측: "STALE BINARY DETECTED" 0회.
2. **구조적으로 자기파괴**: 주입측 `computeSourceHash`(config.nims)는 정확히 5개 파일(gate_hook, orchestrator_hook, gate_utils, git, types)의 sha256sum 체인(320-hex)을 계산한다. 반면 검사측 `GateRunnerSourcePaths`는 **8개 파일**(상기 5개 + orchestrator/hook/context.nim, orchestrator/hook/executor.nim, gate_list.nim)이며, 내용 연접 후 `std/hashes` 64-bit `hash()`를 적용해 320-hex 주입값과 비교한다 — **수학적으로 절대 같을 수 없다**(값이 주입되어도 즉시 위양). 즉 이 검사는 한 번도 "정상 통과" 상태를 가진 적이 없다.
3. **도달성 이중 차단**: `--check-provenance` 모드는 `staleBinaryCheck` 이전에 조기 종료한다(gate_hook.nim:107-110, 제거 전 기준). CI의 모든 gate_hook 호출은 provenance 모드다. 스테이지 실행 호출자는 2026-09-16 은퇴(DEBT#498).
4. **소비자 부재**: `AxiomSourceHash` 값의 소비자는 `logError` 출력 자체뿐이다.
5. **역사적 정합성**: 도입은 2026-07-11 `ec5732585`("replace mtime-based AxiomCompileTime with content-addressed fingerprint"). 그 의도(빌드 산출물 신선도의 콘텐츠 정체성)는 VS-1(PR #1284/#1289, pre-commit nim_check_gate 콘텐츠 정체성)이 정상적으로 완수했으므로, 제거는 도입 의도와 역사적으로 일관된다.

## §2. 제거 diff 요약

`git diff bf9fe5eda` (본 슬라이스, 코드 2파일 순수 삭제 48줄; 구 lineage `174a999d7` 대비 diff와 바이트 동일 — 두 base의 대상 파일이 동일하므로):

| 파일 | 제거 내용 |
|---|---|
| `config.nims` | `buildGateRunners` 태스크 gate_hook 분기의 주입 arm 4줄: `let sourceHash = computeSourceHash("")`, `" -d:AxiomSourceHash=" & sourceHash &`, 주입을 설명하는 주석 2줄. **live 빌드 의미는 보존**(`-d:release -d:useMalloc --nimcache:build/nimcache/gate_hook -o:` 그대로) |
| `src/gate/runners/gate_hook.nim` | `const AxiomSourceHash* {.strdefine.}` + 문서 주석(8줄), `const GateRunnerSourcePaths: array[8, string]`(10줄), `when isMainModule` 내 `block staleBinaryCheck` 런타임 검사(23줄), 그리고 이 검사가 유일 소비자였던 `import std/hashes`(1줄) |

**미변경 (범위 규율)**: `computeSourceHash` 잔여 사용 2곳(buildGateRunners per-runner freshness 해시 ~:173, "binary_checksums" 저장 블록 ~:196-208), `AxiomCompileTime`(별개의 live 메커니즘, gate_self_check.nim이 소비), transitive_hash.nim, gate_cas.nim, precompile_gates, Makefile 빌드 의미, .githooks. §-1 동결 파일(import_encapsulation 블록, import_encapsulation_gate.nim) 미접촉 — config.nims는 buildGateRunners 태스크 영역만 수정.

**파일 통제 확인**: config.nims·gate_hook.nim 모두 `config/repository_surface.json` CONTROLLED(MODIFY=PASS; `tools/surface_guard.nim:188` resolveClass — PRODUCT→CONTROLLED→FROZEN 순서 최초 일치 우선, gate_hook.nim의 정확 경로 CONTROLLED 항목이 `src/gate/**` FROZEN glob에 우선). 일반 PR 경로로 착지 가능 — policy-PR 불필요.

## §3. 기계 검증 (제거 후, 2026-11-08)

**V1 — CI 동일 명령 재빌드** (`ci/checker.mk:524` 패턴):

```
$ AXIOM_HERMETIC_BUILDING=1 nim c --hints:off \
    --nimcache:build/nimcache/ci-compile/gate_hook \
    -o:bin/gate_hook src/gate/runners/gate_hook.nim
→ 빌드 성공(exit 0). 빌드 중 [integrity] merkle root 일치
  (expected == actual: 62f0c2f4… — §-1 수호 4파일 무결 유지 확인)
```

**V2 — 바이너리 문자열 0-발생**:

```
$ strings bin/gate_hook | grep -c 'STALE BINARY DETECTED'
0
$ strings bin/gate_hook | grep -c 'AxiomSourceHash'
0
```

**V3 — CI provenance 모드 호출**(checker.mk `ci-skip-gate-hook` / workflows 관측 경로와 동일):

```
$ bin/gate_hook --check-provenance
[INFO] gate_hook: [OK] gate_hook provenance self-check: embedded BuildSourceHash == live src tree (-6559787877230166793)
→ exit 0
```

**V4 — 저장소 잔여 참조 grep**(코드·빌드 경로 기대 0):

```
$ grep -rln "AxiomSourceHash" . | grep -v "^./.git/"
./data/debt_registry.json                                  (본 슬라이스 DEBT#517-519 등록 — 제거된 메커니즘 기술)
./docs/DEBT_REGISTRY.md                                    (레지스트리 투영)
./docs/evidence/prepush_content_identity_acceptance_2026-11-06.md  (기존 역사 증거 문서)
```

코드·config·빌드·훅·워크플로 경로의 참조: **0건**.

**V5 — 부채 레지스트리 정합성**(Required Check `debt-registry-gate`가 실행하는 것과 동일):

```
$ bin/debt_engine --validate
Checks: 1573 total, 1573 passed, 0 failed
$ python3 tests/ci/test_debt_schema_theater_rule.py
PASS: Theater five-field + binding-type fixtures all green; real registry is clean
```

기준선 대조: 본 슬라이스 diff 적용 전 clean base(`bf9fe5eda`)에서 `--validate` 1555/1555/0 실패 — 신규 실패 0건(체크 수 증가는 신규 엔트리 3건이 추가한 체크). 구 lineage(`174a999d7`) 기준선 1549/1549 → 적용 후 1567/1567로 동일하게 0 실패를 확인했다(마이그레이션 전 검증).

**V6 — 게이트 판정 불변(결정론)**: 제거는 define이 없던 모든 실제 빌드 경로의 컴파일 결과를 변경하지 않는다(검사 블록은 원래 컴파일 아웃). 재빌드 gate_hook의 provenance 판정(V3)은 제거 전과 동일하게 OK/exit 0 — 게이트 verdict 무변화. 정준 빌더·게이트 수트(구 lineage에서 실행): `bin/build_all_gates --release` 82/82 빌드 성공·0 실패(2건 accepted-dead skip — DEBT#491/492 레지스트리 판정); pre-commit 파이프라인(nim check gate PASS, anti_theater PASS, layer_enforcement 1617파일 PASS); pre-push 7-게이트 content-identity 수트 PASS. 모듈 import 소비자: `tests/gateway/gate_hook_feature_test.nim` 12/12 OK(양쪽 lineage에서 동일).

**V7 — 착지 후 확인(post-merge)**: main MERGE 커밋에서 동일 재빌드 + V2/V3 재실행 — 최종 보고서에 결과 기록.

## §4. Follow-up 부채 등록 (본 슬라이스에서 수리하지 않음)

`data/debt_registry.json`에 등록(`binding: registry_disposition` + 근거, `source: axiom_source_hash_removal_investigation_2026-11-08`). 번호는 clean-origin 신규 lineage가 DEBT#516(GPA NO_SURFACE_DELTA fail-open, PR #7)을 이미 점유하므로 **DEBT#517부터** 부여했다(구 lineage 검증 시에는 잠정 DEBT#516-518로 등록했었다).

| ID | 내용 |
|---|---|
| **DEBT#517** | `computeSourceHash`가 path 인자를 무시 — buildGateRunners가 6개 러너 전부에 동일한 전역 5-파일 소스 해시를 저장하므로 per-runner "✓ Up-to-date" 신선도 판정이 러너 자체 소스가 아닌 파일들로 결정됨(5-파일 집합 밖 러너 소스 변경 → stale 바이너리가 fresh로 판정, fail-open) |
| **DEBT#518** | `.axiom/cache/binary_checksums.json`이 라인별로 명명된 바이너리의 체크섬이 아니라 전역 5-파일 **소스** 해시를 저장 — 파일명·포맷·echo가 주장하는 "binary checksums" 보장을 계산한 적이 없음(`docs/spec/gorge_inventory.md` G1이 원 의도 `sha256sum <bin>`를 문서화). 소비자 0건으로 잠복 결함 |
| **DEBT#519** | config.nims 주석 4건이 구현과 모순: :107-108 "std/hashes + readFile, zero external shell"(실제 `gorge("sha256sum …")`), :112 "matches config/integrity.nims merkle"(실제 무관한 4-파일+최종-sha 체인), :197 "std/hashes FarmHash, no external shell"(동일 허위), 구 :180 "7개 러너"(실제 5파일 — 이 주석은 사 주입 arm과 함께 본 슬라이스에서 삭제, 감사 완전성 기록). 주석 수정은 follow-up |

부속 갱신(정준 도구 산출): `data/architecture_debt.json` gate_hook.nim canonicalSyntaxHash·rawContentHash 재고정(`bin/debt_engine --regen-arch`), `docs/DEBT_REGISTRY.md`·`src/generated/debt_constants.nim` 투영 재생성(`--codegen`), `data/debt_ledger.json` BUDGET#005 open-count 동기화(`--sync-budget`).

## §5. 착지

PR: `workstream/axiom-source-hash-removal` → main. Required Checks 전 green 확인 후 merge queue 경유 GitHub 네이티브 MERGE. 착지 후 V7(main 재빌드 + 재검증) 결과는 본 문서를 소유한 세션의 최종 보고서에 기록한다.
