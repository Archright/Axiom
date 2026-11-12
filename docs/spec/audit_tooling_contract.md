# Audit Tooling Contract (dir/doc debt audit subsystem)

> **Status**: RATIFIED — SSOT reference for the deterministic
> `dir/doc` debt audit subsystem.
> 이 문서는 `audit tooling`의 6가지 계약 요소를 구현 그대로 기록한다.
> 새로운 정책을 발명하거나 추천하지 않는다.

## 1. 목적/스코프

`--audit-dir-doc` 하위 명령이 산출하는 결정적 디렉토리·문서 부채 감사의
전반을 담는다. 기준선 증명 파일은 `docs/history/audit_baseline_*.json`이며
스키마는 `audit-baseline/v1`이다.

- 구현: `tools/debt_engine.nim` `cmdAuditDirDoc` (~L1935)
- 기준선 예시: `docs/history/audit_baseline_2026-08-17.json`

## 2. 버전

| 항목 | 값 | 위치 |
|---|---|---|
| engine_version | `audit-projection-v3@2026-08-17` | `tools/debt_engine.nim` `AuditEngineVersion` (L1836) |
| meta 스키마 | `audit-meta/v1` | `src/infrastructure/debt_audit/audit_snapshot.nim` `freezeAuditBundle` (L508) |
| manifest 스키마 | `audit-baseline/v1` | `tools/debt_engine.nim` manifest 작성 (L2195) |

## 3. Rule Catalog

- 원본: `config/audit_rules.json` — `schemaVersion: 1`, `catalogVersion: 1`
- digest: `auditRulesDigest()` (`tools/debt_engine.nim` L1845–1851)
  — rule을 `ruleId:version:domain:severity`로 정렬 후 SHA-256.
  catalog 변경 ⇒ `input_digest` 변경.

## 4. Input Contract

### 4.1 snapshot_id (freeze identity)

`snap:` ‖ SHA-256(canonical(`git_head`, `tracked_tree_digest`,
`untracked_tree_digest`, `freeze_time`)). 규칙 digest·엔진 버전·감사 날짜는
snapshot identity에 포함되지 않는다.

- 구현: `src/infrastructure/debt_audit/audit_snapshot.nim` `freezeAuditBundle` (L495–501)

### 4.2 input_digest

SHA-256 of canonical 6-tuple (정렬된 `key=value` 줄, `\n` 연결):

| 키 | 설명 |
|---|---|
| `repo_state_digest` | SHA-256 of canonical(`files_observations_digest`, `git_head`, `tracked_tree_digest`, `untracked_tree_digest`) |
| `freeze_time` | freeze 시점 UTC ISO 문자열 (재런 시 재사용) |
| `rules_digest` | `auditRulesDigest()` 결과 |
| `engine_semantics_digest` | `audit_engine_inputs.manifest` 파일 내용의 SHA-256 |
| `normative_digest` | `normative.jsonl` 파일 내용의 SHA-256 |
| `toolchain_digest` | 도구 버전·바이너리 해시를 정렬해 산출한 SHA-256 |

- 구현: `tools/debt_engine.nim` input_digest 산출 (L2160–2169)

### 4.3 engine_semantics_digest

`audit_engine_inputs.manifest`는 정확히 `tools/debt_engine.nim`,
`src/core/debt/*.nim`, `config/audit_rules.json`을 나열한다.
**자기 참조 없음** — manifest 자체는 목록에 포함되지 않는다.
manifest 작성 후 그 내용을 해시하여 산출.

- 구현: `tools/debt_engine.nim` `buildEngineSemanticsDigest` (L2092–2113)

### 4.4 run_id 제외

`run_id`는 매 실행마다 생성되는 추적용 타임스탬프로, **어떤 identity hash에도
포함되지 않는다** (L1965–1966).

## 5. Output Contract

### 5.1 4개 정규 산출물 (bundle 내)

| 파일 | 내용 |
|---|---|
| `observations.jsonl` | 결정적 정렬 스캔으로 수집된 관측값 |
| `canonical_findings.jsonl` | 규칙 적용 후 중복 제거·정렬된 발견 |
| `correlated.jsonl` | 규칙과의 상관 관계 결과 |
| `debt_candidates.json` | 후보 DEBT entries |

### 5.2 2개 보고서 digest

| 파일 | 패턴 |
|---|---|
| directory report | `docs/audit/directory_debt_audit_<date>.md` |
| documentation report | `docs/audit/documentation_debt_audit_<date>.md` |

또한 `docs/audit/report_counts.json`이 counts를 기록한다.

### 5.3 counts & projection block

counts: `observations` / `findings` / `review_queue` / `new_debts` (DEBT#418+).
각 보고서의 `## Audit Projection` 블록은 finding count / omission / source를
기록한다 (`audit_projection.nim` L41–45).

### 5.4 재런 identity

재런의 바이트 비교 대상은 4개 정규 파일 + `input_digest` 동일성이다.

- 구현: `tools/debt_engine.nim` `--rerun` 분기 (L2250–2277)

## 6. Self-Exclusion Policy

| 대상 | 제외 방식 |
|---|---|
| bundle dir (`tmp/audit_20260817/`) | `excludedPrefixes`에 포함; snapshot·walk에서 제외 |
| `docs/audit/` | `excludedPrefixes`에 포함; 관측·스캔에서 제외 |
| 엔진 출력 → 자기 입력 | 엔진 출력물이 다시 input으로 피드되지 않음 |
| `docs/history/audit_baseline_*` | VERIFY-09에서 attestation 파일로 간주하여 mutation 허용 (L2808–2811) |

- 구현: `tools/debt_engine.nim` `excluded` (L1946), `writePreSnapshot` (L279–317)

## 7. Determinism Invariant

**같은 Input Bundle + 같은 Rule/Engine/Normative/Toolchain → 같은 canonical
findings.**

- `freeze_time`은 재런 시 재사용 (clock 재호출 없음, L1953–1962).
- `--rerun` 모드는 4개 정규 파일을 byte-compare하고 `input_digest`를 비교한다.
- 불일치 시 `quit(1)`으로 비제로 종료.

- 구현: 재런 분기 (L2250–2277), VERIFY-08 (L2715–2747)

## 8. Annotation Non-Authority

`review_annotations.jsonl`은 **증거**일 뿐이며 canonical 산출물에 영향을
주지 않는다.

- **VERIFY-03a** (정적 스캔): 엔진 소스에서 `review_annotations` 사용이
  `fileExists` 존재 확인 패턴 안에만 국한되는지 검사 (L2415–2466).
- **VERIFY-03b** (실제 삭제 테스트): `review_annotations.jsonl`을 임시 제거 후
  `--rerun` 실행, 4개 정규 파일이 byte-identical인지 확인 (L2468–2513).

## 9. Mutation Boundary & CLI

### 9.1 CLI

| 플래그 | 동작 |
|---|---|
| `--audit-dir-doc` | 전체 실행 (registry dry-run) |
| `--audit-dir-doc --apply` | bundle + `docs/audit` 투영만 작성; registry에 DEBT#418+ entries 추가 |
| `--audit-dir-doc --rerun` | freeze 재사용, 재평가, 바이트 비교 |
| `--audit-dir-doc --project-only` | 기존 bundle에서 보고서만 재렌더 |

### 9.2 Mutation boundary

`--audit-dir-doc`는 bundle과 `docs/audit` 투영을 제외하고는 비변경적이다.
registry 변경은 `--apply`를 통해서만 발생한다 (L2281–2321).

### 9.3 Pre-snapshot enforcement (VERIFY-09)

`writePreSnapshot`은 감사 시작 시 `.pre_snapshot.json`에 worktree의
(path, size, mtime) 테이블을 기록한다. VERIFY-09는 이 스냅샷과 현재
worktree를 diff하여, 승인된 집합({`.git/`, bundle dir, `docs/audit/`}) 밖의
추가·삭제·변경을 탐지한다.

- 구현: `src/infrastructure/debt_audit/audit_snapshot.nim` `writePreSnapshot` (L279–317),
  `tools/debt_engine.nim` VERIFY-09 (L2749–2842)

## 10. Ratification Pipeline

### 10.1 VERIFY-01..09

| 검증 | 내용 |
|---|---|
| VERIFY-01 | `input_digest` 재계산 → manifest와 일치 |
| VERIFY-02 | 4개 정규 파일 digest → manifest와 일치 |
| VERIFY-03a | `review_annotations` 사용이 존재 확인으로만 국한 (정적 스캔) |
| VERIFY-03b | annotation 삭제 후 재런 → canonical outputs byte-identical |
| VERIFY-04 | new_debts의 affected_paths ⊆ finding paths (set inclusion) |
| VERIFY-05 | report coverage: 모든 finding이 보고서에 표현됨 (omission=0) |
| VERIFY-06 | registry files[] ⊆ canonical_findings paths |
| VERIFY-07 | `--validate` in-process 실행, passed==total |
| VERIFY-08 | 기존 rerun/ 하위 디렉토리와 4개 정규 파일 byte-identical |
| VERIFY-09 | worktree vs pre-snapshot diff, 승인된 집합 밖 mutation 없음 |

- 구현: `tools/debt_engine.nim` `cmdBaselineVerify` (L2844–2880),
  개별 verify 프로시저 (L2327–2842)

### 10.2 RATIFIED status

`bin/debt_engine --ratify` performs in-process 10-check verification
(VERIFY-01..09, no external log parsing) and writes the attestation
(`baseline_manifest.json` / `docs/history/audit_baseline_*.json`) with
`"status": "RATIFIED"` only on full pass.

Required prior steps:
- `--audit-dir-doc` (produces the bundle with manifest.json)
- `--audit-dir-doc --rerun` (produces the `rerun/` subdir required by `--ratify`)

### 10.3 Lineage check

`bin/debt_engine --lineage-check` is the native subcommand that computes
three cardinalities per debt entry (affected_paths, finding_rows,
evidence_rows) for DEBT#418/419/420 and performs set-based cardinality
verification.
