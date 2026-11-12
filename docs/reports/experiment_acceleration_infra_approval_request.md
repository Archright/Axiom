# Infra Track 승인 요청서 — CI/Runner 최적화 (S5)

> 상태: **승인 대기** — `AGENTS.md §-1`에 따라 `.github/workflows/ci.yml`은 인간 아키텍트 승인 없이 수정 불가. 본 문서는 승인을 받기 위한 요청서이며, **어떤 ci.yml 변경도 포함하지 않는다** (현재 브랜치의 ci.yml 미수정).

## 1. 배경

실험 가속 로드맵(experiment acceleration)의 최종 단계. 우선순위 원칙(검증된 계획 v4.2):

```
Computation Reduction → Localization → Parallelization → Reuse → Infrastructure
```

S0–S4(선택·실행·재사용)는 본 로드맵의 메인 트랙이며 현재 구현 완료. Infrastructure(S5)는 **같은 계산을 더 싼 인프라에서** 수행하는 계층으로, 메인 트랙과 별도로 승인 시 병행한다.

## 2. 현재 실측 baseline (S0c cost probe + CI 문서)

| 지표 | 값 | 출처 |
|---|---|---|
| canary cold / warm | 18m07s / 10m23s | `docs/spec/self_hosted_ci_migration.md` |
| verify-static | 13m12s–16m18s (cache save 포함) | ci.yml run 로그 |
| verify-integration | 55.4m → 48.6m (dedup 후) | 동일 문서 |
| T_identity(소스트리 해시) | ~103.5ms | `data/benchmarks/identity_cost_probe.json` |
| T_full / T_accelerated | NOT_MEASURED (full 실행 과중; 선택 서브시스템 완성 후 재측정 예정) | 동일 JSON |

→ 알고리즘적 비효율(T_full 全量 실행)을 인프라 개선이 가리지 않도록, **S1의 선택 시스템이 T_accelerated < T_full을 실측으로 확인한 뒤**에야 본 트랙 승격을 요청한다.

## 3. 승인 요청 항목 (제안 — 미적용)

1. **`ci.yml` job 구조 최적화** (ci.yml 수정 필요):
   - verify-static의 toolchain setup(7.67m 중 복원+첫 컴파일)에 대한 캐시 키 개선 — 단 `config.nims` hermetic cache quirk(DEBT#417: `.git/index`를 키에서 제외)와 `AXIOM_CI_PRESERVE_CACHE=1` 기존 동작을 유지하는 범위에서만.
   - verify-integration의 병렬 job 스플릿(독립 단계 분리) — ADR-0003 DAG 병렬 패턴 확장.
   - `selection-report`(S2)를 CI에서 실행해 SemanticInputIdentity/SelectionDigest/PlanDigest 로컬-동일성 기록 (parity 게이트의 CI 측).
2. **self-hosted runner 운영 튜닝** (ci.yml 불필요 — `docs/ci/self_hosted_runner_ops.md` 경로로 승인 없이도 가능한 후보):
   - ephemeral JIT runner 캐시 워밍, 병렬 러너 수 상향.

## 4. 계약 준수 사항 (승인 시에도 불변)

- `AGENTS.md §-1`: ci.yml 수정은 승인 범위 내에서만, import_encapsulation_gate.nim·config.nims importEncapsulation 블록·AGENTS.md 자체는 미수정.
- `DEBT#417`: `.git/index`는 캐시 키에서 제외 유지.
- 결정론: CI에서 생성되는 보고는 semantic input 전용(semantic/incidental 분리, 계약 §3).
- 모든 개선은 실측 before/after(canary cold/warm baseline 대비)로만 승격.

## 5. 승인 절차

1. 인간 아키텍트가 본 요청서 검토.
2. 승인 시: 이 브랜치에서 ci.yml 변경 PR을 별도로 열어 리뷰 (본 작업 브랜치의 ci.yml은 그대로 유지).
3. 미승인 시: S1–S4 결과물(선택·parity·reuse 게이트)은 ci.yml과 무관하게 로컬/스크립트 경로로 계속 유효.
