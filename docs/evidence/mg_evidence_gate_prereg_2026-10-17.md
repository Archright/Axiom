# MG 착지 판정 증거 게이트 사전등록 — REUSED-on-merge_group 차단 + SSOT 서브젝트 집합 동등성 (2026-10-17)

> **종류**: 구현 사전등록 (§2.5 CI Epoch Cutover 동반) — 계보: `docs/evidence/rotation_allowlist_g2_prereg_2026-10-16.md`, `docs/evidence/serial_chain_dag_prereg_2026-10-17.md`. 본 문서는 판정을 만들지 않는다(Reporter) — merge-admission 권위는 기존 정본(`docs/spec/admission_generation.md`, ADR-0025/0027/0032, ruleset 20303214)에 그대로 있다.
> **세대**: 구세대 blob `f2ad3b03b357fdf30976d4e2cbaf6b0927de8830`(REUSED-on-MG 허용) → 신세대 blob `1c9848a74b4767faa696138c2985d267d73f65ac`(REUSED-on-MG 차단 + 집합 동등성 시행). 세대 기록: [ci_epoch_record_mg_evidence_gate_2026-10-17.md](ci_epoch_record_mg_evidence_gate_2026-10-17.md).
> **측정 원문(술어 실측)**: admission callee 안에서 `GITHUB_EVENT_NAME`은 **호출자의 이벤트를 상속**한다 — MG 런 38983713057 → `[venue] venue=landing` 로그, PR 런 38990620435 / 38983249224 → `venue=preflight` 로그 (모두 2026-10-17 관측, `gh run view --log`).

---

## 1. 목적 (4대 불변 · Vertical Slice)

merge_group 착지 런의 Judgment CAS가 원장 재사용(REUSED)으로 GO-critical 테스트를 건너뛰는 것을 차단하고, 착지가 **새로운 실행의 증거** 위에서만 성립하게 한다. Vertical Slice: 착지 판정 1건의 증거 사슬(실행 강제 → decision 파일 basis 증명 → SSOT 집합 동등성 → attest fail-closed 소비)만을 건드린다 — 라인 매트릭스·mint·verdict 구조는 무변경.

4대 불변에 대한 공헌:

| 불변 | 본 변경의 기여 |
|---|---|
| correctness | 착지 런은 jExecuted 강제로 4개 GO-critical 테스트를 **실제 실행**한다 — 재사용 판정이 착지를 대신할 수 없다 |
| integrity | decision 파일이 착지 venue에서 `basis=EXECUTED`임을 **증명 의무**로 강제 — 강제 술어가 callee에 닿지 않으면(세대 왜곡) fail-closed |
| reproducibility | 서브젝트 SSOT(`ax cert judgment-subjects`)와 실제 산출 decision 파일의 **집합 동등성** — 누락·잔존 파일 모두 fail-closed |
| determinism | 술어는 `github.event_name == 'merge_group'` 단일 조건(보조 벨트는 Nim 계층 동일 조건) — 동일 입력 → 동일 판정 |

## 2. 범위

- **Nim 계층(선행 착지, 본 브랜치 커밋 48a33ede4)**: `src/verification/judgment_cas.nim` 강제 실행 단락회로(주 트리거 `AXIOM_JUDGMENT_CAS_FORCE_EXECUTED=1`, 보조 벨트 `GITHUB_EVENT_NAME=merge_group` — 원장 consult 이전 jExecuted) + `ax cert judgment-subjects [--json]` SSOT 투영 CLI.
- **본 yml 배선**: (a) `[lane] Judgment CAS plan` step env에 `AXIOM_JUDGMENT_CAS_FORCE_EXECUTED: ${{ github.event_name == 'merge_group' && '1' || '' }}`; (b) armed-attest 레코드 루프 확장 — 기존 레코드 존재 FAIL-CLOSED 검사를 **약화 없이** SSOT 집합 동등성(expected: B-built `ax cert judgment-subjects` 1줄/서브젝트, observed: decision 파일 `jq -r '.subject // "s1a"'` sort -u — 개수 동등 + comm 공집합)과 merge_group 한정 전 decision 파일 `"basis":"EXECUTED"` 강제로 확장.
- **범위 밖**: Archright/.github org 핀 회전(별도 후속 단계), ruleset 변경, 음성 대조 PR, AGENTS.md / import_encapsulation_gate.nim (§-1 불변).

## 3. 검증 계약

### 3.1 단위 (tests/unit/test_judgment_cas.nim G11 — 커밋 48a33ede4, 로컬 green)

| # | 시나리오 | 기대 |
|---|---|---|
| 1 | 두 트리거 모두 부재 | 게이트 OFF (현행 동작 보존) |
| 2 | 명시 강제 env만 (`"1"`) | 게이트 ON |
| 3 | 벨트만 (`merge_group`) | 게이트 ON (callee에서 LIVE — §술어 실측) |
| 4 | 벨트에 `pull_request` | 게이트 OFF (PR venue 재사용 유지) |
| 5 | 명시 `0` + `workflow_call` | 게이트 OFF (벨트는 merge_group만) |
| 6 | SSOT 투영 | `{"subjects":["s1a","proof_integrity","d2_golden","d2_persist"]}` 정확한 정준 바이트·SSOT 순 |
| + | 클로저 유도 (번역 가능 시): 게이트 + 유효 현세대 재사용 레코드 → jExecuted (재사용 억제 — 레코드 부재가 아님), 확장 서브젝트 4종 동일 | G11 클로저 유도 케이스 |

### 3.2 라이브 (회전 후 — 본 PR의 merge_queue 관측 계약)

| 관측 | 기대 | 실패 시 |
|---|---|---|
| PR preflight 런 (본 PR) | 레인 강제 env = `''` → venue=preflight, REUSED 보존, attest 집합 동등성 step은 REUSED basis 허용 로그 | 게이트 조기 실패 = 배선 결함 — 병합 보류 |
| merge_group 런 (큐) | 강제 env = `'1'` → 전 decision `basis=EXECUTED`, 집합 동등성 PASS, MG aggregate `admission-check` SUCCESS | RED = 즉시 보고·자체 병합 금지·org 회전 금지 |
| `referenced_workflows` | MG 런의 admission-check.yml sha는 **구핀 64f78ab7d…**(org가 아직 구핀 참조 — 신세대는 org 회전 후 활성화, §4) | 불일치 = 활성화 순간 정의 위반 — 보고 후 중단 |

### 3.3 yml 정적 검증 (착지 전 기계 검증, 본 커밋에서 수행)

`make test-workflow-poison-lint` PASS(토큰 14049 < 21k) · pyyaml 파스 PASS · 편집 run 블록 `bash -n` PASS.

## 4. 착지 순서

1. **구핀으로 자기 검증**: 본 PR의 런은 org 캘리가 아직 구핀 blob(f2ad3b03)을 참조하므로 **구세대 판정기로 자기 검증**된다 — 신세대 배선은 main 병합 후 첫 MG 런(구핀 캘리 + 신세대 H 트리 yml)에서 최초다. 이 비대칭은 ADR-0025 Amendment F 원자 회전의 구조적 성질이며 결함이 아니다.
2. **org 회전(별도 후속 단계 — 본 작업 밖)**: Archright/.github 캘리 핀을 NEWBLOB으로 회전.
3. **활성화 순간의 정의**: (i) MG 런의 `referenced_workflows` admission-check sha == NEWBLOB **그리고** (ii) 그 런의 집계 `admission-check` SUCCESS. 두 조건이 처음 동시 성립하는 런이 신세대의 첫 활성 착지다.

## 5. 롤백

freeze 태그 `ci-freeze-mg-evidence-gate-20261017`(= c9cca2655, 워크플로 blob f2ad3b03 == 핀)에서의 원자 revert: cutover 커밋 revert(yml + 두 핀이 한 커밋에 결속 — 부분 상태 혼합 없음) + 필요 시 org 핀을 f2ad3b03으로 재회전. Nim 커밋 48a33ede4는 단락회로가 env 부재 시 무동작(단위 시나리오 1)이므로 revert 대상에서 분리 가능하나, 세대 일관성을 위해 동반 revert를 기본으로 한다.

## 6. 잔여 (open register — §0.9)

1. **적색 런 append 뉘앙스 — out-of-scope**: 착지 런이 ledger append 후 RED로 끝나는 경우의 exactly-once 원장 상태 미세문제는 본 세대의 범위 밖이다. follow-up 권고: 별도 관측 프로브로 수습 여부 판정.
2. **G10(e) 기존 결함 (수정하지 않음 — 정직 기록)**: `tests/unit/test_judgment_cas.nim` G10(e) changed-tree 드릴은 "변경 트리"로 HEAD~1 트리를 쓴다. HEAD↔HEAD~1 간 변화가 클로저 멤버 경로 밖(예: docs 전용 커밋)이면 클로저·키가 불변 → `k3 != k1`과 후속 jExecuted 기대 2건이 실패한다(docs-only 팁 키 동일 — 원본 트리에서 소스 변화가 있는 조합은 재현 통과). 본 세대는 이 드릴을 만지지 않는다; 큐 스위트가 test_judgment_cas.nim을 돌려 이 2건이 보이면 **보고하고 중단**한다(테스트 강제 그린 금지). follow-up 권고: 인공 클로저-상이 트리 합성으로 드릴을 환경 독립화.
3. **셸 fixture 하네스 — deferred**: armed-attest 확장 셸의 실행 하니스(_decision 파일 fixture → step 본문 재실행_)는 본 세대에서 deferred다. 착지 전 보장은 poison-lint + `bash -n` + YAML 파스 + 라이브 MG 관측(§3.2)이 담당한다. follow-up 권고: `tests/ci` 셸 fixture 하네스.

## 7. 동반 등록 (rotation companion registration — 2026-10-17)

> **등록 근거**: 큐 판정 실측 — MG run 38997388474 `mergeAborted`, reasonCode `ROT_NEW_PIN`("pin anchor invalid: line-set(pin@H) != set(derived H) — the pin must anchor exactly H") + `{"closureChange":true,"allowlistOk":false,...}`. 원인 2개: (i) 클로저 멤버 2개(`src/cli/cert_cli.nim`, `src/verification/judgment_cas.nim`)의 blob이 48a33ede4에서 변경됐는데 핀 재앵커가 없어 ④ 등식이 깨짐, (ii) 비멤버 동반 4경로가 회전 허용목록 밖. 본 절은 그 해소 등록이며, 형식 계보는 `docs/evidence/rotation_allowlist_g2_prereg_2026-10-16.md`다.

### 7.1 핀 재앵커 (④ — 302ffb72b, PR #827 "pin@H == derived H (876==876)" 선례)

`config/trusted_writer_set.json` `trustedCheckerTreeClosure` — 유도값(`bin/derive_checker_closure --ref H`) 기준 재앵커, 추측 해시 금지:

| 멤버 | 구핀 blob | 신핀 blob |
|---|---|---|
| `src/cli/cert_cli.nim` | `3ba05c680e6bb21d30c0ef3ab750242f2f11f1f9` | `fcdbae2516508d1d2b633782cd21f16d1aec7124` |
| `src/verification/judgment_cas.nim` | `2255ff1fd22d5bec2d242f1d08f1ca05acbb3364` | `85771a78a53a96ad00073dfc493d4b6d1fd4a9b4` |
| `src/cli/merge_cli.nim` | `4519a59320c2a290b03b16a9f8582dff0bef2345` | 본 커밋 blob(§7.2 확장에 따른 재앵커 — 단일 최종 앵커 패스) |

커밋 후 `pin@H == derived(H)` 등식을 기계 검증한다(멤버십 876==876, 라인 집합 완전 일치). **두 입시 핀(`trustedAdmissionWorkflowSha` + `productionExecutionPin` = `1c9848a7…`)은 불변** — "두 값 외 변경 없음" 훈련 유지.

### 7.2 동반 4경로 (① — A4(PR #826)·INV-9(3c9cffd0d)와 동일 fix class)

`src/cli/merge_cli.nim` `RotationAllowlistExtra` 열거형 확장(4경로 — 열거형만, glob 없음(A4 규율); 비멤버 production src/는 계속 밖(A2 (i))):

1. `tests/unit/test_judgment_cas.nim` — 회전 멤버(`judgment_cas.nim`·`cert_cli.nim`)의 단위 계약(테스트 동반 — `tests/cli/test_merge_cli.nim`·`tests/ci/test_derive_checker_closure.nim` 동일 클래스).
2. `docs/evidence/mg_evidence_gate_prereg_2026-10-17.md` — 본 문서(회전 사전등록 동반 — `rotation_allowlist_a5_prereg_2026-10-14.md` 동일 클래스).
3. `docs/evidence/ci_epoch_record_mg_evidence_gate_2026-10-17.md` — §2.5 세대 기록(증거 동반 — `s1-stale-base-repro-2026-10-12.md` 동일 클래스).
4. `data/benchmarks/perf_latest.json` — L2 게이트가 읽는 성능 baseline(PR #861 동반 선례).

**등록 효력(정직 기록)**: 판정기는 B 체크아웃 빌드 바이너리로 이 열거형을 소비하므로, 본 등록은 **다음 세대부터** 이 4경로의 회전 분류를 해소한다(#826의 등록이 자기 판정에 쓰일 수 없었던 것과 동일한 구조). 본 PR 자신의 착지 경로는 trust-surface 수동 병합 경로다 — 변경 경로 중 `admission-check.yml`·`trusted_writer_set.json`·`merge_cli.nim`이 `config/policy/merge_admission.json` `trustSurface` 멤버 → ④ 재앵커가 Pass 2.75(단일 ④ 거부점)를 통과하면 `TRUST_SURFACE_MODIFIED`(dryRunExit 0 — 수동 병합 경로 표식)가 예상된다(전례 PR #856, 2026-10-15 큐 착지 검증). 현재 실측 ROT_NEW_PIN은 바로 그 전제의 ④ 거부다.
