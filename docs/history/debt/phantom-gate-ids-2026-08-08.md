# Phantom Gate IDs Cleanup (P3)

- 작성일: 2026-08-08
- 목적: 아키텍트가 승인한 P3 "SSOT 미등록 게이트 고아/판 ID 정리"에 따라
  고아 코드(`memory-policy-gate`)의 삭제와 판 ID(`quality-gate-marker`, `sentinel`) 제거 결정을 기록한다.
  기록 목적의 참조 문서이며 자동 생성/검증 로직에는 영향 없음.

## 1. memory-policy-gate — 고아 코드 삭제 (dead code 제거)

`runMemoryPolicyInProcess`(`src/gate/in_process_gates.nim:439`)는 정의만 존재하고 어디서도 참조되지 않는
고아 코드였다.

- 배선 경로 없음 — `registerDefaultInProcessGates`(`pipeline_orchestrator.nim:92-119`) 등록 목록에 없음.
- 러너 파일 없음 — `data/golden/memory-policy-gate.json` golden 파일 외에 코드/매니페스트 참조 없음.
- 아키텍트 결정: **삭제(옵션 c)**. wiring 경로가 없으므로 SSOT 등록 대신 dead 코드 삭제가 결정론적.

### 1.1 삭제 대상

`src/gate/in_process_gates.nim`에서 memory-policy 전용 상수/함수/proc 전체를 제거:

| 심볼 | 종류 | 삭제 |
|------|------|------|
| `MemPolAgmdPath` | const | 삭제 |
| `MemPolCompetingSsotFiles` | const | 삭제 |
| `parseMemoryPolicyMarkers` | func | 삭제 |
| `runMemoryPolicyInProcess` | proc | 삭제 |

삭제 후 해당 심볼들이 참조하던 imports(`std/[strutils, tables, json, os, sequtils]`), `readFile`,
`fileExists`, `CatchableError`, `logError`, `ProjectMap`은 **다른 게이트(그 외 인프로세스 게이트,
`runNimtryGateInProcess`)에서 계속 사용**되므로 유지한다. shared 심볼이기에 추가 정리 없음.

### 1.2 golden 파일 처리

`data/golden/memory-policy-gate.json` — 게이트 자체가 삭제되므로 golden 파일도 함께 삭제한다.
golden 참조 코드(grep 기준)는 위 게이트 proc 내부뿐이며 별도 참조가 없어 안전하게 제거된다.
(golden-data integrity gate는 `data/golden/` 디렉터리를 순회하는 generic 로직이므로 잔여 파일 개수에 민감하지 않음)

### 1.3 SSOT 등록하지 않음

wiring 경로가 없으므로 SSOT(`topology_spec.nim`)에 등록하지 않는다. 삭제가 정답.

## 2. quality-gate-marker / sentinel — 판(phantom) ID 제거

`CriticalGateIds`에 존재하나 SSOT(`topology_spec.nim`), 매니페스트, 게이트 레지스트리, 러너가 전혀 없는
판 ID를 제거했다.

### 2.1 gate_dsl_v2.nim `CriticalGateIds` (L74-80)

| ID | SSOT/매니페스트/러너 | 처리 |
|----|---------------------|------|
| `gate-self-check` | SSOT 등록(`topology_spec.nim:251`) | 유지 |
| `sentinel` | 없음 (판 ID) | **제거** |
| `quality-gate-marker` | 없음 (판 ID) | **제거** |
| `unstaged-guard` | SSOT 등록(`topology_spec.nim:669`) | 유지 |
| `integrity-workflow` | SSOT 등록(`topology_spec.nim:378`) | 유지 |

`sentinel`은 grep 결과 `gate_dsl_v2.nim:76`에서만 등장하며 SSOT/매니페스트/러너가 전혀 없어 판 ID로 판정,
함께 제거한다. `gcHigh` 주석("Never auto-disable (gate-self-check, sentinel, etc.)")의 `sentinel`
언급은 단순 예시 주석으로 남겨 두었다(문서적 참조로 무해).

### 2.2 self_heal_agent.nim `CriticalGateIds` (L10-13)

`quality-gate-marker`(판 ID)만 제거. 나머지(`gate-self-check`, `unstaged-guard`,
`integrity-workflow`, `architecture-config-gate`)는 SSOT(`topology_spec.nim`)에 등록된 실게이트이므로 유지.

### 2.3 Aspect/Sentinel 타입 신규 도입 없음

타입 미존재 + 억제할 경고 없음 → 단순 판 ID 정리가 정답이다. 신규 타입/프레임워크를 도입하지 않는다.

## 3. 검증 결과 (문서 작성 시점)

| 검증 항목 | 명령 | 기대값 | 실제 | 판정 |
|-----------|------|--------|------|------|
| in_process_gates nim check | `nim check --hints:off src/gate/in_process_gates.nim` | exit 0 | exit 0 | PASS |
| gate_dsl_v2 nim check | `nim check --hints:off src/gate/gate_dsl_v2.nim` | exit 0 | exit 0 | PASS |
| self_heal_agent nim check | `nim check --hints:off tools/ci/self_heal_agent.nim` | exit 0 | exit 0 | PASS |
| 고아 심볼 잔존 | `grep -rn "runMemoryPolicy\|memory-policy-gate" src/ tools/ --include="*.nim" --include="*.json"` | 0건 | 0건 (문서 제외) | PASS |
| 판 ID 제거 | `grep -rn "quality-gate-marker" src/gate/gate_dsl_v2.nim tools/ci/self_heal_agent.nim` | 0건 | 0건 | PASS |

비고:

- `src/generated/type_registry_metadata.json`에 `runMemoryPolicyInProcess` 엔트리가 남아 있으나,
  이는 `hermetic_build.nim`이 생성하는 **자동 생성 파일**이므로 직접 수정하지 않는다.
  다음 빌드 시 idempotent regeneration으로 자동 제거된다.
- golden 파일(`data/golden/memory-policy-gate.json`)은 삭제했다.

## 4. 불가침 / 타 에이전트 파일 미수정 선언

본 PATCH는 소스 2개(`in_process_gates.nim`, `gate_dsl_v2.nim`, `self_heal_agent.nim`),
golden 1개(삭제), 문서 1개(신규)만 다루었다. 아래 파일은 일절 수정하지 않았다.

- `config.nims`
- `.github/workflows/ci.yml`
- `AGENTS.md`
- `src/gate/runners/import_encapsulation_gate.nim`
- `src/gate/orchestrator/hook/executor.nim` (다른 에이전트 runDeferred 이행 중)
- `src/core/gate/state_ledger.nim` (다른 에이전트 runDeferred 이행 중)
- `src/gate/topology_spec.nim` (SSOT — 미수정)
