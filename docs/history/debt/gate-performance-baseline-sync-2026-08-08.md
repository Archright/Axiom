# Gate Performance Baseline Sync (`gate_performance_baseline.json`)

- 작성일: 2026-08-08
- 목적: `data/gate_performance_baseline.json`에 존재하지만 SSOT(`src/gate/topology_spec.nim`)에 없는
  **8개 키**에 대해 각각 참조 재확인 후 판정(병합됨 / 사용중 / 제거)을 기록한다.
- 성격: 기록 목적의 참조 문서. 자동 생성/검증 로직에는 영향 없음.

## 1. 결론 요약

8개 키 전부에 대해 `src/`·`tools/`·`config/`에서 실제 참조를 확인하였다. **완전 유령(참조 0건)인 키는 없으며,
따라서 제거 대상도 없다.** 세부 분류:

| 키 | 참조 여부 | 판정 | 처리 | 근거(참조 위치) |
|----|-----------|------|------|------------------|
| `debt-blocker` | 있음 | 병합됨 (merged) | **유지** | `src/gate/runners/debt_integrity_gate.nim:2` 헤더 "Merged from debt-blocker + ..." |
| `debt-reduction-gate` | 있음 | 사용중 (in-use) | **유지** | 헤더 주석(병합 기록, `debt_integrity_gate.nim:2,10,24,245`) + 실제 인프로세스 등록(`pipeline_orchestrator.nim:106`) + 로깅(`in_process_gates.nim:273`) |
| `magic-number-sniffer` | 있음 | 병합됨 (merged) | **유지** | `asset_hygiene_gate.nim:20`, `tools/static_analyzer.nim:5,278` — 헤더 "Merged from magic-number-sniffer" |
| `memory-policy-gate` | 있음 | 사용중 (in-use) | **유지** | `in_process_gates.nim:459` (`logError`), `data/golden/memory-policy-gate.json` 존재 |
| `quality-gate-marker` | 있음 | 사용중 (in-use) | **유지** | `gate_dsl_v2.nim:77`, `tools/ci/self_heal_agent.nim:11` |
| `nimtry` | 있음 | 사용중 (in-use) | **유지** | 인프로세스 등록(`pipeline_orchestrator.nim:116`) + 전용 모듈 `src/gate/nimtry/` + `tools/nimtry/*` |
| `architecture-config-gate` | 있음 | 사용중 (in-use) | **유지** | 러너 `src/gate/runners/architecture_config_gate.nim` (`registerGate`, :271) + `self_heal_agent.nim:12` + `static_analyzer.nim:4` |
| `context-size-guard` | 있음 | 사용중 (in-use) | **유지** | 러너 `src/gate/runners/context_size_guard.nim` (`registerGate`, :71) |

> **제거된 키: 없음.** 완전 유령(어디에도 참조 없음)인 키가 하나도 없어 제거 대상이 발생하지 않았다.
> 따라서 `data/gate_performance_baseline.json`은 수정하지 않는다.

## 2. 참조 확인 명령별 상세 (grep 결과)

명령: `grep -rl "<key>" src/ tools/ config/ --include="*.nim" --include="*.json" | grep -v gate_performance_baseline`

- **debt-blocker** → `src/gate/runners/debt_integrity_gate.nim` (헤더 주석, 병합 기록)
- **debt-reduction-gate** → `debt_integrity_gate.nim`(병합 헤더) + `in_process_gates.nim` + `pipeline_orchestrator.nim`(인프로세스 등록)
- **magic-number-sniffer** → `asset_hygiene_gate.nim` + `tools/static_analyzer.nim` (병합 헤더)
- **memory-policy-gate** → `in_process_gates.nim`
- **quality-gate-marker** → `gate_dsl_v2.nim`, `tools/ci/self_heal_agent.nim`
- **nimtry** → 다수 (`pipeline_orchestrator.nim`, `in_process_gates.nim`, `src/gate/nimtry/*`, `tools/nimtry/*`, 러너 다수)
- **architecture-config-gate** → `architecture_config_gate.nim`, `self_heal_agent.nim`, `static_analyzer.nim`
- **context-size-guard** → `context_size_guard.nim`

## 3. 소비자 영향 분석

`gate_performance_baseline.json`의 소비자는 **벌크 순회(bulk iteration)** 방식이라 키 수/존재 여부와 무관하다.

- `src/core/telemetry/gate_telemetry.nim:166` — `for gateId, spec in baseline:` 로 전체 키를 순회. 특정 키 하드코딩 없음.
- `tools/ci/self_heal_agent.nim:112` — `identifyCandidates(baselinePath)`로 후보 탐색 (벌크).

즉, 키를 추가/제거해도 소비자 동작에 영향이 없다. 이번 판정은 제거 없음이므로 동작 변화도 없다.

## 4. 현재 상태 검증 (yjson/grep 결과 기록)

| 검증 항목 | 명령 | 기대값 | 실제 값 | 판정 |
|-----------|------|--------|---------|------|
| JSON 유효성 | `python3 -m json.tool data/gate_performance_baseline.json > /dev/null` | exit 0 | exit 0 | PASS |
| 총 키 수 | 위 JSON 로드 | 26 | **26** | PASS (수정 없음) |
| 키별 존재 | `json.load` 후 8개 키 조회 | present | 전부 present=True | PASS |
| 소비자 벌크 순회 | `grep -n "gate_performance_baseline" src/ tools/ --include="*.nim"` | 정상 | `gate_telemetry.nim:155,157` + `self_heal_agent.nim:111` | PASS |
| 유령 키 여부 | 8개 키 모두 참조 확인 | 전부 참조 존재 | 0건 유령 | PASS |

## 5. 판정 근거 요약

- **병합됨 (merged, 유지)**: `debt-blocker`, `magic-number-sniffer` — 소스코드 주석에 "Merged from ..."으로
  기록되어 내려오는 레거시 이름. 삭제 대상이 아니라 병합 사실을 기록하는 키로 유지한다.
- **사용중 (in-use, 유지)**: `debt-reduction-gate`, `memory-policy-gate`, `quality-gate-marker`, `nimtry`,
  `architecture-config-gate`, `context-size-guard` — 실제 러너/인프로세스 등록/DSL 마커/self-heal 목록에서 참조된다.
- **제거 (remove)**: 없음.

## 6. 불가침 파일 미수정 선언

본 작업은 문서(`docs/history/debt/gate-performance-baseline-sync-2026-08-08.md`) **단일 파일만 신규 생성**하였다.
제거 대상 키가 없어 `data/gate_performance_baseline.json`은 물론이고 다음 불가침 파일은 일절 수정하지 않았다.

- `config.nims`
- `.github/workflows/ci.yml`
- `AGENTS.md`
- `src/gate/runners/import_encapsulation_gate.nim`
- `data/quality_gate_baseline.json` (다른 에이전트 소유)
- 그 외 소스 코드 / SSOT(`topology_spec.nim`)

git commit은 수행하지 않았다.
