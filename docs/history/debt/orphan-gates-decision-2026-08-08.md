# Orphan Gates Decision (PATCH-7)

- 작성일: 2026-08-08
- 목적: 아키텍트가 승인한 PATCH-7에 따라 미배선 orphan 게이트(`debt_scan_gate`, `architecture_config_gate`)의
  분류 방침과 Q1/Q2(중복 해석) 판정을 기록한다. 기록 목적의 참조 문서이며 자동 생성/검증 로직에는 영향 없음.
- 선행 문서: [helper_ssot_classification_2026-08-08.md](../helper_ssot_classification_2026-08-08.md)

## 1. 결정 요약

아키텍트는 PATCH-7을 승인하였다. `debt_scan_gate`/`architecture_config_gate`는 **옵션 (a) 헬퍼 유지**로 확정된다.

- SSOT `helper_registry`(`src/gate/helper_spec.nim`)에 헬퍼로 등록 유지.
- 게이트 파이프라인 디스패치에는 **배선하지 않음**(미배선 상태 유지).
- 호출 경로는 Makefile `audit` 타겟(`Makefile` audit 섹션)에서의 직접 실행뿐이다.

즉 두 게이트는 독립 실행 가능한 헬퍼 러너로 분류되며, 표준 게이트 워크플로의 일부로 간주되지 않는다.

## 2. 근거

- 두 게이트는 `registerGate("debt-scan-gate", run)`(`debt_scan_gate.nim:246`) 및
  `registerGate("architecture-config-gate", run)`(`architecture_config_gate.nim:271`)을 보유하지만,
  게이트 파이프라인 디스패치(매니페스트-기반 게이트 워크플로)에는 배선되지 않았다.
- SSOT 등록(옵션 (b))은 `AxiomLedgerCap=56`(`src/core/gate/static_project_matrix.nim:20`)의
  레지스터 슬롯 여유가 있으나, 실제 검증 로직이 게이트 워크플로와 통합되었다는 증거가 없어
  현재 단계에서는 헬퍼로 분류한다.
- 이미 `src/gate/helper_spec.nim`의 HelperModules에 등록되어 Check 6 정산이 완료된 상태이며,
  manifest-consistency gate는 green을 유지한다.

## 3. Q1/Q2 결정 (keep-both)

아키텍트 승인으로 **둘 다 유지**(keep-both)한다. 두 항목 모두 기존에 SSOT(`topology_spec.nim`)에 등록되어 있다.

- **Q1 — conflict-marker 중복**: `conflict_marker_gate.nim`(독립 실행)과
  `runConflictMarkerInProcess`(`in_process_gates.nim:325`, 인프로세스)는 서로 다른 실행 경로로
  각각 유지한다. SSOT `topology_spec.nim:130`에 등록 유지.
- **Q2 — hotspot-coverage vs hotspot-gate**: `hotspot-coverage-gate`와 `hotspot-gate`는
  각각 별도의 책임을 지니므로 둘 다 유지한다. SSOT `topology_spec.nim`에 등록 유지.

## 4. 향후 승격 조건 (옵션 (b))

헬퍼에서 SSOT 등록 게이트(옵션 (b))로 승격하려면 아래 조건이 충족되어야 한다.

1. 게이트 파이프라인 디스패치 실제 배선 — 디스패치 개념 증명(증거) 필요.
2. `AxiomLedgerCap` 슬롯 여유 재확인 — 승격 순간 사용 중인 레지스터 슬롯 수가
   `AxiomLedgerCap=56`을 초과하지 않는지 확인.
3. 승격 시 `registerGate` 배선 + SSOT(`topology_spec.nim`) 등록 + Check 6 재정산으로
   manifest-consistency gate green 재확인.

## 5. 현재 상태 검증 (grep 결과 기록)

아래는 이 문서 작성 시점에 실행한 검증 결과이다.

| 검증 항목 | 명령 | 기대값 | 실제 값 | 판정 |
|-----------|------|--------|---------|------|
| SSOT 헬퍼 등록 | `grep -c "debt_scan_gate\|architecture_config_gate" src/gate/helper_spec.nim` | 2 | **2** (16, 20행) | PASS |
| SSOT 토폴로지 등록 | `grep -c "conflict-marker-gate\|hotspot-coverage-gate" src/gate/topology_spec.nim` | 2 | **3 (라인 매치)** — 실제 등록 2 (130행 `conflict-marker-gate`, 341행 `hotspot-coverage-gate`) + 335행 주석 참조 | PASS(등록 2) |
| Makefile 호출 경로 | `grep -n "debt_scan_gate" Makefile` | 283 (audit) | **287행** (`audit` 타겟 범위 내 `$(NIM) c -r src/gate/runners/debt_scan_gate.nim`) | PASS |

비고:

- `grep -c`는 **매치된 라인 수**를 세므로, `topology_spec.nim`의 경우 335행의 주석
  (`# NOTE: hotspot-coverage-gate (...)`)까지 포함되어 3이지만, 실제 SSOT 등록(엔트리)은
  `conflict-marker-gate`(130행)와 `hotspot-coverage-gate`(341행) 2개이다.
- Makefile에서 `audit:` 타겟 헤더는 283행, 실제 `debt_scan_gate.nim` 호출은 해당 타겟 본문의 287행이다.
- 그 외 배경 검증: `registerGate`는 `debt_scan_gate.nim:246`, `architecture_config_gate.nim:271`에 존재.

## 6. 불가침 파일 미수정 선언

본 PATCH는 문서(`docs/history/debt/orphan-gates-decision-2026-08-08.md`) **단일 파일만 신규 생성**하였으며,
아래 불가침 파일은 일절 수정하지 않았다.

- `config.nims`
- `.github/workflows/ci.yml`
- `AGENTS.md`
- `src/gate/runners/import_encapsulation_gate.nim`
- 그 외 소스 코드 / SSOT(`topology_spec.nim`, `helper_spec.nim`) / 매니페스트 / 레지스트리
