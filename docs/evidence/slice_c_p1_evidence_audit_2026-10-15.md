# Slice C / P1 — 레인 stderr 증거 감사 (C1) 기록 — 2026-10-15

- **일자**: 2026-10-15
- **성격**: 증거 보존 기록 (90-day 증거 정책) — C1 감사(merge_group admission-gate 실패 런의 증거-존재 감사)의 판정과 근거를 기계 재검증 가능한 형태로 고정한다. 본 문서는 판정 권위를 이동·추가하지 않는다(Reporter — prereg-2026-10-14 서두의 Authority ≠ Adapter 준용).
- **모집단 쿼리 (재현 명령)**: `gh api --paginate "repos/Archright/Axiom/actions/runs?event=merge_group&created>=2026-10-13T00:00:00Z&per_page=100"` → `name=="admission-gate"` ∧ `conclusion=="failure"` 필터. 증거 인용은 각 런의 job 로그(`gh api --allow-escape-sequences repos/Archright/Axiom/actions/jobs/<job_id>/logs`)에서 추출.
- **판정 원천**: P1-Branch-A 작업 지시(2026-10-15, 소유자 전면 허가 계보) + C1 감사 수행 기록.

---

## 1. 모집단 진술 (population statement)

**[2026-10-13T00:00Z → 2026-10-15 감사 시점] merge_group admission-gate 실패 런의 완전 모집단 = 24런** (위 쿼리의 전수 — 추정·표본 아님). 클래스 구성:

| 클래스 | 런 수 | 증거 판정 |
|---|---|---|
| ROT_* (verdict job, `##[error]`+reasonCode JSON) — ROT_NEW_PIN 8 + ROT_ALLOWLIST 7 | 15 | **EXPLICIT** 15/15 |
| ADM_IDENTITY (attest job, `CANDIDATE_MERGE_BASE_UNRESOLVED` ancestry 텍스트) | 3 | **EXPLICIT** 3/3 |
| no-verdict (verdict job, run-level err 원인 텍스트) | 1 | **EXPLICIT** 1/1 |
| 레인 병렬 (reverted 4레인 blob 계보, GO-critical 스텝 실패) | 5 | **PARTIAL** 5/5 |

**직렬 레짐(serial-regime) 증거-부재 실패 = 0** — 직렬 레짐의 19런 전부(ROT_* 15 + ADM_IDENTITY 3 + no-verdict 1)가 스텝 로그에 명시적 실패 원문(##[error] + reasonCode/cause 텍스트)을 남겼다. **stderr 소실 패턴은 리버트된 4레인 blob 계보의 5런(2026-10-14)에만 존재**하며, 이 5런이 모집단의 유일한 PARTIAL 행이다.

> **C1 헤드라인 카운트("15") 정산**: 작업 지시가 인용한 "15 total"은 아래 둘 중 하나의 부분집합 독해와 정합이다 — (a) ROT_* 런 수(정확히 15), 또는 (b) 10-13 ROT_* 10런 + 10-14 레인 PARTIAL 5런. 어느 독해든 본 감사의 실질 판정(직렬 레짐 증거-부재 = 0, stderr 소실은 4레인 blob 레짐에 국한)은 불변이며, 완전 모집단(24런)에서 오히려 **강화**된다(19/19 EXPLICIT — 부분집합 독해의 12/12보다 넓은 근거).

## 2. 런별 증거 표 (per-run evidence table)

런 ID 오름차순. "실패 job → 스텝"은 conclusion=failure job과 그 안의 실패 스텝. 증거 인용은 verdict/attest job 로그의 `##[error]` 행 원문(발췌).

| 런 ID | 일시 (UTC) | PR | 클래스 | 실패 job → 스텝 | 로그 증거 | 판정 |
|---|---|---|---|---|---|---|
| 38413029467 | 10-13T14:24 | #812 | ROT_NEW_PIN | verdict → Admission predicate | `##[error]admission verdict NOT-ADMIT (reasonCode=ROT_NEW_PIN) — evidence: admission-verdict artifact` | EXPLICIT |
| 38417766698 | 10-13T14:56 | #812 | ROT_NEW_PIN | verdict → Admission predicate | 동일 reasonCode JSON | EXPLICIT |
| 38420037284 | 10-13T15:12 | #812 | ROT_NEW_PIN | verdict → Admission predicate | 동일 reasonCode JSON | EXPLICIT |
| 38423046544 | 10-13T15:33 | #812 | ROT_ALLOWLIST | verdict → Admission predicate | `reasonCode=ROT_ALLOWLIST` | EXPLICIT |
| 38423994360 | 10-13T15:39 | #813 | ADM_IDENTITY | attest → Re-derive admission identity | `##[error]ADM_IDENTITY FAIL — CANDIDATE_MERGE_BASE_UNRESOLVED: ancestry(a7e473340…, a69bfcd1d…) unresolved after 8x64-commit deepening (history cap reached — fail-closed)` | EXPLICIT |
| 38425709733 | 10-13T15:52 | #813 | ROT_ALLOWLIST | verdict → Admission predicate | `reasonCode=ROT_ALLOWLIST` | EXPLICIT |
| 38426015908 | 10-13T15:54 | #812 | ADM_IDENTITY | attest → Re-derive admission identity | `ancestry(c593ec2c4…, 578745aab…) unresolved after 8x64-commit deepening` | EXPLICIT |
| 38427196116 | 10-13T16:02 | #812 | ROT_ALLOWLIST | verdict → Admission predicate | `reasonCode=ROT_ALLOWLIST` | EXPLICIT |
| 38429600788 | 10-13T16:19 | #816 | ROT_NEW_PIN | verdict → Admission predicate | `reasonCode=ROT_NEW_PIN` | EXPLICIT |
| 38437141491 | 10-13T17:15 | #812 | ROT_ALLOWLIST | verdict → Admission predicate | `reasonCode=ROT_ALLOWLIST` | EXPLICIT |
| 38441204758 | 10-13T17:45 | #812 | ROT_ALLOWLIST | verdict → Admission predicate | `reasonCode=ROT_ALLOWLIST` | EXPLICIT |
| 38442389109 | 10-13T17:54 | #820 | ADM_IDENTITY (stale-head) | attest → Re-derive admission identity | `##[error]ADM_IDENTITY FAIL — CANDIDATE_MERGE_BASE_UNRESOLVED: ancestry(68a61ade7…, 2d0dfc2be…) unresolved after 8x64-commit deepening (history cap reached — fail-closed)` | EXPLICIT |
| 38460545380 | 10-13T20:09 | #813 | ROT_ALLOWLIST | verdict → Admission predicate | `reasonCode=ROT_ALLOWLIST` | EXPLICIT |
| 38513610557 | 10-14T04:52 | #827 | ROT_NEW_PIN | verdict → Admission predicate | `reasonCode=ROT_NEW_PIN` | EXPLICIT |
| 38517895366 | 10-14T05:40 | #827 | ROT_NEW_PIN | verdict → Admission predicate | `reasonCode=ROT_NEW_PIN` | EXPLICIT |
| 38521798256 | 10-14T06:22 | #827 | ROT_NEW_PIN | verdict → Admission predicate | `reasonCode=ROT_NEW_PIN` | EXPLICIT |
| 38524327637 | 10-14T06:47 | #827 | ROT_ALLOWLIST | verdict → Admission predicate | `reasonCode=ROT_ALLOWLIST` | EXPLICIT |
| 38578920996 | 10-14T14:15 | #828 | 레인 병렬 (4레인 blob) | attest → GO-critical admission tests | 마커·`LANE … duration_ms` 행만 재출력, 레인 원문 부재, `##[error]Process completed with exit code 1.` | **PARTIAL** |
| 38580760673 | 10-14T14:28 | #828 | 레인 병렬 (4레인 blob) | attest → GO-critical admission tests | 상동 (shape 동일 검증) | **PARTIAL** |
| 38583637985 | 10-14T14:47 | #828 | 레인 병렬 (4레인 blob) | attest → GO-critical admission tests | 상동 | **PARTIAL** |
| 38587538612 | 10-14T15:14 | #828 | 레인 병렬 (4레인 blob) | attest → GO-critical admission tests | 상동 | **PARTIAL** |
| 38595964298 | 10-14T16:11 | #829 | 레인 병렬 (4레인 blob) | attest → GO-critical admission tests | 상동 | **PARTIAL** |
| 38676808805 | 10-15T03:32 | #838 | ROT_NEW_PIN | verdict → Admission predicate | `reasonCode=ROT_NEW_PIN` | EXPLICIT |
| 38680184078 | 10-15T04:11 | #838 | no-verdict | verdict → Admission predicate | `##[error]admission evaluation FAILED (fail-closed) — stderr:` + cause 체인 (로그 :956–976) → `##[error]admission evaluation failed without a verdict JSON (run-level err)` (:977) | EXPLICIT |

## 3. 직렬 vs 레인 blob 인용 (defect-class lineage)

- **직렬 레짐 (정상 — 라이브 출력)**: `dc527994c987cad9d7d83f1dc27650d0c15eb63e`의 admission-check.yml — GO 테스트가 `if make test-fast-one T="$t"; then`으로 **직접 실행**되어 테스트 stdout/stderr가 스텝 로그에 라이브로 도달한다(:1143 루프 개시 ~ :1175 실행 행). 이 레짐의 실패는 원문이 로그에 남는다(§2 EXPLICIT 19런).
- **레인 blob (결함 — 리다이렉트 후 미재출력)**: `2c94c991418dfd89e665ce4ec3efdcc86ffd2e93`의 admission-check.yml — `LANE_ROOT=/tmp/go-critical-lanes`(:1163), `lane_run()`(:1181), `> "$d/run.log" 2>&1 || rc=$?`(:1199) 이후 재출력은 `cat "$d/markers"`(:1276)와 duration/status 행뿐이고, status 파일 부재 시 `FAIL — (lane produced no status file)`로 종료(:1284) — **run.log 원문은 어디에도 재출력되지 않는다**. 실측: 2026-10-14 5런(§2 PARTIAL) 전부 마커·duration 행만 남기고 `##[error]Process completed with exit code 1.`로 종료(대표 런 38578920996 attest 로그 :1106 리다이렉트·:1241-1250 duration 행·:1252 종료).
- **봉쇄**: 리버트 커밋 `a937f27f62e3fdb8b0d3bda19b95c9d943b4c5a2`("revert(ci): atomically revert GO-critical 4-lane parallelization (PR #826) — pre-registered recovery") — 현재 main은 레인 패턴 부재(프로덕션 런 38720403835, 2026-10-15T10:27Z, LANE=0 직렬, success).

## 4. 판정 (verdict)

1. **증거 갭은 휴면 병렬 레짐에 국한된다** — 직렬 레짐 19/19 EXPLICIT, 레인 blob 계보 5/5 PARTIAL. PARTIAL의 원인은 도구 결함이 아니라 4레인 blob의 워크플로 셰이프(리다이렉트 후 미재출력)다.
2. **P1(레인 stderr 방출)은 이번에 승격되지 않고 prereg 필수 조건으로 흡수된다** — `docs/evidence/merge_latency_decision_prereg_2026-10-14.md` §8 개정(2026-10-15, append-only) + 기계 집행: `tools/ci/validate_workflow_shell.sh` 레인-stderr 가드(레인 패턴 보유 워크플로가 전사 공개·always 업로드 마커 없으면 FAIL; 셀프테스트 `make test-workflow-lane-guard`). 리버트 blob은 이 가드의 회귀 오라클이다(가드가 2c94c9914를 FAIL로, 2555ab966을 PASS로 판정하는 것을 커밋된 피처·역사 blob 정합성 검사로 시험한다).
3. **NOT_ADMIT_UNPARSED cause-class는 분류 정책이지 증거 갭이 아니다** — verdict 미보존 런(38680184078)도 원인 텍스트(로그 :956–978)를 로그에 남긴다. 미파싱 런을 NOT_ADMIT_UNPARSED로 분류하는 것은 판정 어휘 정책의 선택이며, 로그 증거의 부재와 구별된다(§2 EXPLICIT 판정의 근거).
4. **프로덕션 등급 방출 패턴은 main에 없고 fix/go-critical-cold-race-residual에 존재한다** — 재출력 + always 업로드 레시피 `2555ab966e35e8a5023c28e87c1836b1744bd7a9`(동 브랜치, "[check] Upload GO-critical lane logs (forensics — always)" 스텝), 라이브 tee 레시피 Slice B S2 `f1e600965`(queue-probe). 향후 재병렬화 PR은 이 레시피를 따르고 prereg §8 가드를 통과해야 승격된다.

## 5. GET-only 재현

```bash
gh api --paginate "repos/Archright/Axiom/actions/runs?event=merge_group&created>=2026-10-13T00:00:00Z&per_page=100" \
  --jq '.workflow_runs[] | select(.name=="admission-gate" and .conclusion=="failure") | "\(.id) \(.created_at) \(.head_branch)"'   # §2 모집단
gh api repos/Archright/Axiom/actions/runs/38578920996/jobs --jq '.jobs[] | select(.conclusion=="failure") | .id'   # attest job → 로그에서 리다이렉트·duration 행·exit-1 확인
git show 2c94c991418dfd89e665ce4ec3efdcc86ffd2e93:.github/workflows/admission-check.yml | sed -n '1163p;1181p;1199p;1276p;1284p'   # 레인 blob 결함 셰이프
git show dc527994c987cad9d7d83f1dc27650d0c15eb63e:.github/workflows/admission-check.yml | sed -n '1143p;1175p'                     # 직렬 라이브 출력
bash tools/ci/validate_workflow_shell.sh --self-test && make test-workflow-lane-guard                                              # 가드 오라클
```
