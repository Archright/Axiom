# CAS Writer/Reader Identity Consistency — READY (2026-08-31)

> **종류**: point-in-time audit (Phase 1-2 checkpoint 실증 기록). 계약 근거: `docs/spec/verification_dag_contract.md` §3/§4/§5/§11/§14.
> **판정**: READY — 현재 tree 기준, CAS writer와 실제 executor reader가 동일 canonical identity를 사용함을 실측으로 증명.
> **전제**: `bin/axiom-gate`(16:05 빌드)와 `bin/precompile_gates`(HEAD의 gate_cas.nim 변경 이전 빌드)를 현재 tree 소스로 재빌드한 후 실험. 구 바이너리 기준 판정 아님.

## 실제 executor 경로

- `src/gate/orchestrator/hook/executor.nim` (repo 내 유일한 executor.nim)
- 체인: `hooks/pre-commit` → `bin/axiom-gate hook pre-commit` (`src/gate/gateway.nim:1013`) → single-gate (`gateway.nim:679`) → `runSingleGateImpl` (`orchestrator/hook/executor.nim:141`) → `gate_cas.resolveCasBinaryPath` → `computeTransitiveSourceHash` → `computeCasKey`
- CAS reader 전수: `orchestrator/hook/executor.nim:141`, `gateway.nim:507`(AOT fail-close 카운터), `runners/gate_hook.nim:404`, `runners/integrity_workflow.nim:134` — 전부 동일 resolution 함수. `resolveCasBinaryPathWithHash`의 `buildEnvHash` 파라미터는 dead param (`gate_cas.nim:141-149`에서 미사용).

## 실험 결과 (대상: env-gate, entry src/gate/runners/env_runner)

| 단계 | 실측 |
|---|---|
| writer key (clean CAS + precompile) | `env-gate-058bd56154014afb-96f9fcc598714e00` |
| reader key (writer 실행 전 독립 계산) | `env-gate-058bd56154014afb-96f9fcc598714e00` |
| writer_key == reader_key | TRUE (문자열 일치) |
| CAS lookup | HIT — reader가 writer artifact 경로 반환, executor가 재컴파일 없이 실행 (binary mtime 불변) |
| mutation (env_gate.nim 1파일) | key → `env-gate-5e8e79b2796c68ae-96f9fcc598714e00` 변경, writer 실행 전 lookup MISS(재사용 금지), writer 새 artifact 생성 후 reader 동일 key HIT·실행 |
| revert | key 원래 값 복원 + 원본 artifact 재사용 (writer `cached` 0 compiled, reader lookup HIT, binary 무손상) |
| unresolved (closure 강제 실패) | TRANSITIVE_HASH="" → READER_KEY="" → lookup MISS, 런타임 fail-closed 로그("forcing compile", DEBT#449/#450), AOT fail-close로 hook exit 1 (commit 차단) |

## Artifact Freshness Requirement (blocker 아님)

- `source revision X → writer X, reader X` 보장. `writer X / reader X-1` 금지.
- 2026-08-31 실측: `bin/axiom-gate`가 identity 전환 커밋(35757cfd, 2026-08-31 16:09) 이전 빌드로 남아 있었음 — 배포/CI는 writer·reader를 동일 소스 리비전에서 재빌드해야 한다.
- 향후 Evidence DAG의 NodeExecutorDigest(`verification_dag_contract.md` §3)이 이 요구를 identity 수준에서 구조화한다.

## 부수 관찰 (결함 아님, minor)

- `src/cli/precompile_gates.nim:489-498`: lock 존재 + 일부 게이트만 변경 시 미변경 게이트의 CAS-missing을 보완하지 않고 exit 0. 재실행/lock 삭제로 자가 치유되며 reader fail-close가 미컴파일을 잡아냄.
- daemon keying은 본 판정 범위에서 분리됨(실험 시 daemon 미기동).
- 실험 잔재 정리 완료: git tree clean, CAS는 현재 tree 기준 재생성 상태.