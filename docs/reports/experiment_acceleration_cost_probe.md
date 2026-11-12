# 실험: 가속화 비용 프로브 (S0c Cost Probe)

> **목적**: 선택(subselection) 이전의 네 가지 비용 지표와 Selected/Universe 비율을 측정하여, 향후 S1 선택 서브시스템 도입 시 비용 감소 효과의 기준선(baseline)을 확보한다.
> **일자**: 2026-09-05
> **도구**: `tools/benchmark_cost_probe.nim` → `data/benchmarks/identity_cost_probe.json`

---

## 1. 측정 항목 의미 (계약)

| 지표 | 의미 |
|---|---|
| **T_identity** | 선택(subselection) 이전에 수행되는 현재 존재하는 다이제스트 계산의 벽시계 비용. 실재 저장소(source tree lock file, 합성 그래프)에 대한 실제 측정값. |
| **T_selection** | 오늘날 존재하는 가장 가까운 유사 항목 — `selectFrontierNodes` (frontier_selection.nim)를 유계 입력에 대해 측정. "T_selection_baseline (frontier-based, pre-S1)"로 레이블됨. |
| **T_full** | 기존 CLI를 통한 유계 전체 universe 검증 실행의 벽시계 비용. |
| **T_accelerated** | 동일한 유계 실행이지만 가장 작은 대상 범위(`--target <one symbol>`)로 제한. "T_accelerated_baseline (pre-S1: --target filter, not yet pruned selection)"로 레이블됨. |
| **Selected/Universe 비율** | `verification_scope.lock`의 VKS(비면제 커널 심볼 23개) / kernel_total(40) = 0.575. |

---

## 2. 실행 방법

```bash
# 도구 컴파일 체크
nim check --hints:off tools/benchmark_cost_probe.nim

# 실행 (nim c -r)
nim c -r --hints:off tools/benchmark_cost_probe.nim

# 또는 Makefile target
make bench-cost-probe
```

출력: `data/benchmarks/identity_cost_probe.json`

---

## 3. 결과 표

| metric | valueMs | valueUs | label | 상태 |
|---|---|---|---|---|
| T_identity_source_tree_hash | 103.849 | 103499 | computeSourceTreeHash over src/ | ✅ 측정됨 |
| T_identity_canonical_scope_digest | 1.728 | 1728 | canonicalScopeDigest over verification_scope.lock | ✅ 측정됨 |
| T_identity_combineHashes_10 | 0.079 | 79 | combineHashes on 10 parts | ✅ 측정됨 |
| T_identity_combineHashes_100 | 0.570 | 570 | combineHashes on 100 parts | ✅ 측정됨 |
| T_identity_combineHashes_1000 | 5.624 | 5624 | combineHashes on 1000 parts | ✅ 측정됨 |
| T_selection | 0.046 | 46 | T_selection_baseline (frontier-based, pre-S1) | ✅ 측정됨 |
| T_identity_dependency_graph_digest | — | — | dependencyGraphDigest on synthetic graph | ⏸️ NOT_MEASURED |
| T_full | — | — | Full bounded verification run (--limit 5, --smt-timeout 4000) | ⏸️ NOT_MEASURED |
| T_accelerated | — | — | T_accelerated_baseline (pre-S1: --target filter) | ⏸️ NOT_MEASURED |

### Selected/Universe 비율

- **selected**: 23 (VKS, verification_scope.lock의 kernel_total에서 면제 심볼 17개를 제외한 비면제 심볼)
- **universe**: 40 (kernel_total)
- **value**: 0.575
- **방법론**: VKS 수(23) ÷ kernel_total(40). verification_scope.lock에서 직접 계산.

---

## 4. NOT_MEASURED 사유

| 항목 | 사유 | 이후 실행 명령 |
|---|---|---|
| T_identity_dependency_graph_digest | `dependencyGraphDigest`는 `TopologyAnalysis`를 필요로 하며, 이는 `topology_engine`, `canonical_projection` 등 전이적 링크 의존성을 가짐. 단독 도구 스크립트 컨텍스트에서 링크 불가. | 전체 프로젝트 빌드의 일부로 실행: `nim c -r --hints:off -d:release -o:bin/benchmark_cost_probe tools/benchmark_cost_probe.nim` |
| T_full | `ax prove --limit 5 --smt-timeout 4000`는 SMT 솔버 호출로 인해 30초 타임아웃 초과. | `bin/ax prove --limit 5 --smt-timeout 4000` |
| T_accelerated | `--target`으로 지정한 심볼이 현재 frontier에 없어 NotFound 반환. `--target` 필터가 작동하려면 S1 선택 서브시스템의 pruned selection이 필요. | `bin/ax prove --limit 5 --smt-timeout 4000 --target <symbol>` |

---

## 5. 메서드로지 주의사항

- **의미론적 입력 모델 준수**: JSON에 절대 경로, 호스트명, PID, mtime 등 부수적 환경 상태를 포함하지 않음. repo-상대 경로와 툴체인 식별자만 사용.
- **결정론적 키 순서**: JSON 키는 가능한 한 정렬된 순서로 유지.
- **실제 측정만 기록**: T_full/T_accelerated는 가짜 숫자가 아닌 NOT_MEASURED로 기록.
- **T_selection은 pre-S1**: 현재 존재하는 `--target` 필터 기반 frontier 선택을 측정. S1에서 도입될 pruned selection과는 다름.

---

## 6. G3 단일 환경 비용 측정 (2026-09-05)

단일 환경에서 한 번의 측정 세트를 수행한 상세한 결과는 별도 문서를 참고하라:

- **문서**: `docs/reports/experiment_acceleration_measurements_G3.md`
- **측정 데이터**: `data/benchmarks/experiment_acceleration_measurements.json`
- **주요 발견**: 
  - T_accelerated (43943ms) < T_full (52196ms) → TRUE (가속화 경로가 빠름)
  - 하지만 K=0 (선택된 단위 없음)이므로 실제 범위 축소 효과보다는 캐싱 및 실행 순서의 영향을 받을 수 있음
  - 선택 엔진이 빈 의존성 그래프에서는 선택을 수행할 수 없음 (selected=0/23)

> **참고**: G3 측정은 단일 환경에서 한 번의 측정 세트만을 수행하였으며, 재현성 검증이나 통계적 유의성을 위한 다중 측정은 포함되지 않는다. 이 측정은 탐색적 목적으로 수행되었으며, 최종적인 성능 결론은 더 엄격한 벤치마크 프로토콜 하에서 내릴 필요가 있다.