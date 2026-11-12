# auto_heal 완전 삭제 — 2026-08-08

- 작성일: 2026-08-08
- 목적: 아키텍트가 승인한 계획에 따라 `auto_heal`(엔진 + 게이트 래퍼 + manifest +
  topology + `runDualTrack` + 문서)을 **완전 삭제**한 결정과 근거를 기록한다.
  기록 목적의 참조 문서이며 자동 생성/검증 로직에는 영향 없음.

## 1. 결정 요약

다음 아티팩트들을 **완전 삭제**한다 (2026-08-08):

| 아티팩트 | 상태 | 근거 |
|---|---|---|
| `tools/auto_heal.nim` (엔진) | 삭제 | 빌드 타깃 없음, `bin/auto_heal` 배포 부재 — dead |
| `src/gate/runners/auto_heal.nim` (게이트 래퍼) | 삭제 | tier=2 등록이지만 실행 경로 없음 — dead |
| `src/gate/manifest.d/auto-heal.json` | 삭제 | 위 래퍼의 매니페스트 |
| `src/gate/topology_spec.nim`의 `auto-heal` 엔트리 | 제거 | SSOT에서 삭제 |
| `src/gate/gateway.nim`의 `runDualTrack` | 제거 | default-off dead + 잠재 false-return 버그 |
| `config/gates.json`, `src/gate/config_loader.nim`의 `auto-heal` | 제거 | 설정 항목 정리 |

유지 대상: `runDeferred`(tier-2 deferred) 및 `healing_orchestrator` 모듈은
**보류/별개**로 변경하지 않는다.

## 2. 근거

- `tools/auto_heal.nim`은 어떤 빌드 타깃에도 연결되지 않고 `bin/auto_heal`이
  배포되지 않아 실행 불가능한 dead 코드였다 (DEBT#365 Theater/Dead Gate로 등재됨).
- `src/gate/runners/auto_heal.nim`은 tier=2로 등록되었으나 실행 경로가 없었다.
- `gateway.nim`의 `runDualTrack`(Phase 3.5)은 `AXIOM_DUAL_TRACK=on`일 때만 활성화되는
  default-off dead 코드였고, Track 2가 정상 완료되더라도 마지막 프로시저 본문이
  `return`되지 않는 잠재 false-return(signature `bool`) 버그 가능성을 지녔다.
  이 버그를 정적 유지로 "수리"하는 대신, 사용하지 않는 경로 자체를 완전 제거하는
  결정 ③을 채택했다.
- `Healing Orchestrator`(`healing_orchestrator`)는 `auto_heal` CLI/게이트 경로와
  별개 모듈이므로 유지한다.

## 3. 삭제 프로세스

1. `tools/auto_heal.nim`, `src/gate/runners/auto_heal.nim`,
   `src/gate/manifest.d/auto-heal.json` 삭제.
2. `src/gate/topology_spec.nim`에서 `auto-heal` 엔트리 제거.
3. `bin/build_metadata_generator` 재실행으로 `src/generated/build_metadata.json` 재생성
   (stale 매니페스트 참조 제거, 55→54 manifests).
4. `bin/sync_topology`(최신 소스로 재빌드) 실행으로 생성물 재생성:
   - `src/gate/manifest.d/_index.json` (55→54 entries)
   - `src/generated/manifest_registry.nim`, `gate_registry.nim`
   - `config/gates.manifest.toml`
5. `src/gate/gateway.nim`에서 `runDualTrack` 프로시저와 Phase 3.5 호출부 제거.
6. `config/gates.json`와 `src/gate/config_loader.nim`의 `auto-heal` 항목 제거.
7. `docs/spec/dual_track_promotion.md`에 "완전 삭제됨" 사실 반영.

## 4. 검증 결과

| 검증 항목 | 명령 | 결과 |
|-----------|------|------|
| 파일 삭제 | `ls tools/auto_heal.nim src/gate/runners/auto_heal.nim` | 없음 (PASS) |
| 매니페스트 인덱스 | `grep -c "auto-heal" src/gate/manifest.d/_index.json` | 0 (PASS) |
| 생성물 전수 | `grep -c "auto-heal\|auto_heal" src/generated/gate_registry.nim src/generated/manifest_registry.nim config/gates.manifest.toml` | 0 (PASS) |
| gateway 컴파일 | `nim check --hints:off src/gate/gateway.nim` | exit 0 |
| topology 컴파일 | `nim check --hints:off src/gate/topology_spec.nim` | exit 0 |
| drift | `make check-topology-drift` | exit 0 |

## 5. 불가침 파일 미수정 선언

본 작업은 아래 **불가침 파일**을 일절 수정하지 않았다.

- `config.nims`
- `.github/workflows/ci.yml`
- `AGENTS.md`
- `src/gate/runners/import_encapsulation_gate.nim`

또한 다른 에이전트가 소유한 **타에이전트 파일**도 수정하지 않았다.

- `quality_gate.nim`
- `data/quality_gate_baseline.json`
