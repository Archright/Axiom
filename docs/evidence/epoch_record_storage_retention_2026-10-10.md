# CI Epoch Record — storage retention cutover (retention-days 3 + AXIOM_ARTIFACT_RECORD + A2 pin 회전): Freeze / Record / Tombstone

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–3 + 5 — **FREEZE / RECORD / TOMBSTONE / ATOMIC BINDING UPDATE** 기록 문서. 변경 = 4개 무제한 hot-path artifact upload site에 명시적 `retention-days: 3` + 각 upload 뒤 `AXIOM_ARTIFACT_RECORD v1` 이력 step 추가, 그리고 **A2 원자 핀 단위**(admission-check.yml blob + 쌍 핀 동일 커밋 회전).
> **작성일**: 2026-10-10.
> **작업 브랜치**: `feat/storage-retention-policy` — 핀 단위 커밋 **`4554c48f308c8ec0c4f560afcce0cc3da29bbf1b`**(short 표기 `4554c48f3`). freeze 대상 = **`4554c48f3^` = `d9a3e7ed61fad1912d97bcc5c607250a3ad010fd`**(origin/main HEAD, "Merge pull request #704").
> **기록 관례**: `docs/evidence/epoch_record_base_artifact_2026-10-01.md`(정본 구조 템플릿 — Freeze/Record/Tombstone/검증/수용) 선례 준용.
> **왜 이 변경인가 (측정 근거, 2026-10-10)**: live Actions artifact storage가 **98.85 GB** — 포함 풀 50 GB 대비 **197.7%**. enterprise `actions` budget이 `amount: 0` + `prevent_further_usage: true`라 quota 소진 시 upload가 **하드 블록** → required check `admission-check` 실패 → merge 차단. 비상 정리로 58.74 GB(1,351 artifacts) 회수 → 41.17 GB(82.3%), 그러나 **~12 GB/day 재적체**. 본 변경이 내구 해법이다(4개 무제한 upload site에 명시적 retention).

---

## 1. FREEZE (AGENTS.md §2.5 단계 1)

| 항목 | 값 |
|---|---|
| freeze tag | **`ci-epoch-pre-storage-retention-2026-10-10`** (annotated) |
| 태그 타입 | annotated — `git cat-file -t` = `tag` |
| tag message | `FREEZE: CI state before storage-retention epoch (retention-days 3 + AXIOM_ARTIFACT_RECORD + A2 pin rotation)` |
| freeze 대상 | **`4554c48f3^` = `d9a3e7ed61fad1912d97bcc5c607250a3ad010fd`** — 핀 단위 커밋 `4554c48f3`의 부모, 즉 변경 전 상태 |
| 실측 검증 | `git rev-parse ci-epoch-pre-storage-retention-2026-10-10^{}` = `d9a3e7ed61fad1912d97bcc5c607250a3ad010fd` — **일치 ✓** (2026-10-10 실측) |
| push | **브랜치와 함께 push** (`git push origin ci-epoch-pre-storage-retention-2026-10-10 feat/storage-retention-policy`) — 본 기록이 정하는 push 방식 |
| immutable baseline | §2.5에 따라 **삭제·재작성 금지** — rollback 기준(§9) |

---

## 2. RECORD (AGENTS.md §2.5 단계 2)

### 2.1 blob sha 전후 (content-addressed — `git rev-parse <commit>:<path>` 실측, 2026-10-10)

| 파일 | 변경 전 (@freeze `d9a3e7ed6`) | 변경 후 (@`4554c48f3`) |
|---|---|---|
| `.github/workflows/admission-check.yml` | **`cdafd17ba767704c0571cf53f2b7c8f765557ea7`** | **`55f34314d21041c009333a17c68b65badc18f8a4`** |
| `.github/workflows/runner-pool-acceptance.yml` | `3a9e6e75cdaeeecff336db0e13227d9d61455a16` | `afac7914e5054ffcf7cb93cd4149cb309d797536` (비핀 엔진 — 핀 대상 아님) |

### 2.2 쌍 핀 전후 + trust-source binding (A2 atomic pair)

- **변경 전** (`git show 4554c48f3^:config/trusted_writer_set.json`·`…/epoch_manifest.json` 직접 읽음, 2026-10-10 실측):
  - `config/trusted_writer_set.json:41` `"trustedAdmissionWorkflowSha": "cdafd17ba767704c0571cf53f2b7c8f765557ea7"`
  - `config/policy/epoch_manifest.json:9` `"productionExecutionPin": "cdafd17ba767704c0571cf53f2b7c8f765557ea7"`
  - freeze blob(`cdafd17ba767…`)과 **3-way 일치 ✓** (핀 == freeze blob — manifest 실행 핀 == TWS blob 핀 == 실체)
- **변경 후** (`4554c48f3` 커밋 상태 실측):
  - `trustedAdmissionWorkflowSha`(:41) = **`55f34314d21041c009333a17c68b65badc18f8a4`**
  - `productionExecutionPin`(:9) = **동일 값**
  - admission-check.yml blob(`55f34314d210…`)과 **3-way 일치 ✓** — §6 검증 #1·#3으로 기계 재확인
- **trust-source binding**: ADR-0022 §4–5의 blob-addressed 핀(`trustedAdmissionWorkflowSha` = `git hash-object` 값)과 ADR-0025 Amendment A2의 원자 페어(TWS + manifest pin이 admission-check.yml과 **동일 diff**에서 회전). 본 변경은 그 정본 경로의 정규 회전이다 — `trustedCheckerTreeClosure` **무변경**(구성원 무변경), certificate-mint 단일 writer **무변경**(§6 #1 출력).

---

## 3. ARTIFACT / AUTHORITY BINDING (단계 2 계속)

### 3.1 변경된 4개 upload site (모두 `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` # v4)

| # | 파일:행 | step name | step id | artifact name | 부여 retention |
|---|---|---|---|---|---|
| 1 | `admission-check.yml:511-513` | `[build] Upload base-built artifacts` | `upload-base-artifacts` | `admission-check-base-artifacts` | `retention-days: 3` (:513) |
| 2 | `admission-check.yml:582-586` | `[build] Upload base-tree nimcache (B-cache carrier — J3 acceleration)` | `upload-base-nimcache` | `admission-check-base-nimcache` | `retention-days: 3` (:586) |
| 3 | `runner-pool-acceptance.yml:665-670` | `Upload bootstrap artifacts` | `upload-bootstrap-artifacts` | `ci-bootstrap-artifacts` | `retention-days: 3` (:670) |
| 4 | `runner-pool-acceptance.yml:768-773` | `Upload candidate-arm64 (shard 소비용 — 단일 authority 산출물)` | `upload-candidate-arm64` | `candidate-arm64` | `retention-days: 3` (:773) |

**권위 불변**: writer·소비자·required check(`admission-check` @ workflowId) 전부 무변경 — 변경은 **보존 기간 파라미터와 이력 기록 step**뿐이다. witness/verdict/mint 계열 artifact는 기존 `retention-days: 30`(admission-check.yml:1531·1559·2029·2064, runner-pool-acceptance.yml:231) 그대로 — **접촉 없음**.

### 3.2 AXIOM_ARTIFACT_RECORD v1 스키마 (4 site 각각의 upload 직후 step)

- 위치: `admission-check.yml:545`·`:591`, `runner-pool-acceptance.yml:683`·`:792`.
- 단일 greppable 라인, stdout + `$GITHUB_STEP_SUMMARY` 동시 출력:

```
AXIOM_ARTIFACT_RECORD v1 name=<artifact> run_id=<run_id> run_attempt=<attempt> artifact_id=<id> digest=<digest> requested_retention_days=3 expected_retention_days=${{ github.retention_days }} metadata_status=partial
```

- `expected_retention_days`는 `${{ github.retention_days }}` (비어 있으면 `unknown`). `metadata_status=partial`에서 시작해 best-effort REST enrichment(`observed_expires_at`/`size_in_bytes`/`created_at`)를 시도하며, 실패 시 `metadata_status=degraded`로 **loud degrade** — `{.bestEffort.}` 마커 부착(anti_theater_gate C-rule 허용: sanctioned fail-open = loud runtime log + inline reason), **절대 job을 실패시키지 않는다**.
- record step은 upload step 자신의 artifact-id output에 게이트 — artifact가 존재할 때만 발화. **GitHub은 만료된 artifact를 API에서 숨기므로, 만료 후 이력은 이 run-log record가 유일한 남는 증거다** (이것이 record step의 존재 이유).

---

## 4. TOMBSTONE (AGENTS.md §2.5 단계 3)

**폐기되는 동작**: 위 4개 upload site의 **암묵적 90일 기본 보존(implicit 90-day default retention)** — 명시적 `retention-days`가 없던 upload는 repo/org 전역 기본 설정(90일)을 상속했다. 본 변경으로 그 4개 site는 명시적 `retention-days: 3`로 대체되며, **"이 4 site에서 90일 기본 상속"이라는 동작은 여기서 명시적으로 종료(폐기)된다**. 전역 기본 설정 자체(`days: 90`)는 **변경하지 않는다**(§7·§8 — run log의 90일 horizon 유지). 폐기 범위는 정확히 §3.1 표의 4 site뿐이다.

5점 형식(프로토콜 요구 — §0.9b/§2.5 불변식 확인):

1. 본 Tombstone은 **게이트 우회(break-glass)가 아니다** — required check(`admission-check`)·org gate·verdict 체인 무변경.
2. 본 Tombstone은 **면제(waiver)가 아니다** — `config/decision_binding.waiver.*` 등록 없음(2026-10-10 기준 본 변경 관련 면제 0건).
3. 본 Tombstone은 **required-check 제거가 아니다** — `admission-check` required status 유지.
4. 본 Tombstone은 **검증 면제를 의미하지 않는다** — 빌드/검증 계약 전부 그대로; 폐기되는 것은 4 site artifact의 보존 기간(90일→3일)과 그 이력 보증 방식(API 노출 → run-log record, §3.2)뿐이다.
5. Tombstone은 역사적 폐기 기록이며 실행·검증 권한을 갖지 않는다(§2.5 Mandatory Invariants) — 준용.

---

## 5. ATOMIC BINDING UPDATE (AGENTS.md §2.5 단계 5 — A2 pin unit)

- **커밋**: `4554c48f308c8ec0c4f560afcce0cc3da29bbf1b` (short `4554c48f3`) — 4파일(+82/−2): `admission-check.yml`·`runner-pool-acceptance.yml`·`config/trusted_writer_set.json`·`config/policy/epoch_manifest.json`. 워크플로 변경과 **쌍 핀 2건이 정확히 하나의 커밋**으로 전진 — 부분 갱신 상태 없음.
- **계약 인용 ①**: `.github/workflows/admission-check.yml:112-116` — "ADR-0025 Amendment A2 동반 (2026-09-27): … tws의 trustedAdmissionWorkflowSha는 이 파일 blob sha와 **동일 diff**에서 갱신된다 (**landing-integrity ATOMICITY**). 본 파일의 blob 변경은 A2 회전 동반 허용 집합에 속한다 (A2 최소 정합 집합)." (ATOMICITY 문구 :115)
- **계약 인용 ②**: `tools/ci/epoch_transaction_gate.nim` 헤더 **G2a**(:29 "G2a — PINNED engine (admission-check.yml, the pin's blob target)") — 핀 엔진 변경 시 `{TWS record, manifest pin VALUE}` 동일 커밋 전진 필수. `make check-epoch-transaction` 판정 대상.
- 본 기록 문서는 **같은 브랜치의 별도 제2 커밋**으로 착지한다 — 기록은 문서이지 A2 핀 단위의 구성원이 아니며, 핀 단위 커밋의 원자성을 희석하지 않는다.

---

## 6. VERIFICATION (단계 6 Local/Targeted — 2026-10-10 실측, 브랜치 `feat/storage-retention-policy` @ `4554c48f3`)

| # | 명령 | 기대 | 실측 (2026-10-10) |
|---|---|---|---|
| 1 | `bash tools/ci/verify_trusted_writer_set.sh` | PASS — TWS == admission blob | **✓ exit 0**: `OK — certificate-mint.yml is the declared trusted writer` · `OK — admission-check.yml@55f34314d21041c009333a17c68b65badc18f8a4 == trustedAdmissionWorkflowSha` · `PASS — contents:write holders == TrustedWriterSet = { .github/workflows/certificate-mint.yml@55f34314d21041c009333a17c68b65badc18f8a4 }` |
| 2 | `nim c -r tests/ci/test_admission_check_stages.nim` | 전부 OK | **✓ 10/10 OK, exit 0** (stage required input, attest/verdict dispatch, witness edge, artifact identity·attempt scoping, base payload overwrite 계약 포함) |
| 3 | `nim c -r tests/ci/test_admission_venue_split.nim` — "A2 pin pairing stays atomic (3-way)" suite | 3-way 일치 | **✓**: `[OK] git blob(HEAD admission-check.yml) == TWS trustedAdmissionWorkflowSha == epoch manifest pin` + 단일 writer/epoch id 2건 [OK] — suite 전체는 23 OK / **2 FAILED**이며 그 2건은 **본 변경 이전부터 존재하는 red**(§8·§11 — 기계 확인: `admission-verdict` upload는 `4554c48f3^`에도 존재(9회 매치), landing conjunct 수도 전후 동일(25 == 25)) |
| 4 | `git rev-parse ci-epoch-pre-storage-retention-2026-10-10^{}` | `d9a3e7ed6…` | **✓** (§1) |
| 5 | 쌍 핀 등식 (전후 각각) | 3-way 일치 | **✓ 전후 모두** — freeze: blob==TWS:41==manifest:9 = `cdafd17ba767…`; HEAD: `55f34314d210…` (§2.2) |

**측정 정당화 — retry latency (91일 / 7,188 runs 실측, 2026-10-10)**:

| 항목 | 값 |
|---|---|
| 관측 기간 / run 수 | 91 days / 7,188 runs |
| re-run 수 | 85 |
| 최대 retry 지연 | **8.55 h** |
| 1일 초과 retry | **0건** |
| 선언 retry 지원 창 | **3일** — §7 참조 (운영 리스크 수준, 보장 경계 아님) |

즉 실측 retry 수요는 3일 창을 한 번도 닿지 않았고(최대 8.55 h), 90일 기본 보존은 이 워크로드에서 사용되지 않는 87일분의 저장 비용(~12 GB/day 적체의 주성분)이었다. 비상 정리 실측: **98.85 GB(197.7%) → 58.74 GB 회수(1,351 artifacts) → 41.17 GB(82.3%)** — 재적체 ~12 GB/day.

---

## 7. DECLARED WINDOW — 3일 retry 지원 창 (연산 리스크 수준)

- **3일 = 선언된 retry 지원 창(declared retry-support window)**이지 **보장된 경계(guaranteed boundary)가 아니다**. 플랫폼은 re-run을 30일간 허용하며 이를 금지할 수 없다 — 창 밖 re-run은 **fail-closed로 정직하게 실패한다**: 만료된 artifact red(expired-artifact red). 이 실패는 위장되지 않고, §3.2의 run-log record가 "무엇이 만료되었는가"의 추적 증거를 남긴다.
- 창 수치의 근거는 §6의 retry latency 실측(85 re-runs, max 8.55 h, zero > 1 day)이다. 창을 초과하는 retry 수요가 관측되면 이 기록을 개정해 창을 재산정한다 — 조용히 기본값으로 되돌리지 않는다.

---

## 8. M8/M9 note — history horizon

- **H_M8 (history horizon) = 90일 = `max(62, days_effective)`** — repo/org 전역 retention 설정(`days: 90`)이 그대로 유지되므로 **run log의 90일 horizon은 무변경**이다(§4 — 전역 설정 의도적 무접촉).
- **H_M8/M9 값의 출처 (귀속 정정, 2026-10-11)**: 이 판본은 H_M8/M9가 org gate 계약(org `admission-gate` 이력 요구, `admission-gate-history`)에서 왔다고 기술했으나 이는 **오귀속**이다 — 정정한다. 실제 도출은 **본 workstream의 Phase 0 시나리오 분석**이다: SC-1 billing 비교 = 62일, SC-2 forensics / SC-3 audit = 90일(= 실효 retention `days`), 따라서 `H_M8 = max(62, days_effective) = 90`. 이 시나리오 분석은 in-repo 문서로 남아 있지 않으며(2026-10-11 기준 `H_M8`/`SC-1`/`SC-2`/`SC-3` 전수 검색 — 본 기록 §8이 유일한 언급), `4554c48f3` 커밋 메시지가 H_M8과 전역 설정의 연결만을 보존한다.
- **SSOT 공백 (follow-up)**: `H_M8`/`M9` 술어의 정본 위치(SSOT)는 in-repo에 없다(src/docs/tools 전수 검색 확인, 2026-10-11). 정본 위치는 추후 별도 결정 과제다(후보: `docs/spec/` — certification-continuity 계약 인접). 본 기록은 새 SSOT 파일을 임의로 만들지 않는다.
- **run(run log 자체)의 삭제는 M9 predicate에 의해 게이트된다** — artifact retention(`retention-days: 3`)은 artifact blob의 보존 기간이며 run 기록 삭제와는 다른 층이다. 본 변경은 artifact 층만 축소하고 run log 층(90일)은 건드리지 않는다.

---

## 9. Rollback reference

- rollback 기준 = freeze tag **`ci-epoch-pre-storage-retention-2026-10-10`** (`d9a3e7ed61fad1912d97bcc5c607250a3ad010fd`, immutable — 삭제 금지).
- 재-핀 복원 대상(변경 전 = freeze 값): `trustedAdmissionWorkflowSha`/`productionExecutionPin` → `cdafd17ba767704c0571cf53f2b7c8f765557ea7`; admission-check.yml blob → `cdafd17ba767…`; runner-pool-acceptance.yml blob → `3a9e6e75cdae…`. rollback은 §5의 원자 단위(4파일)로 수행한다 — 부분 복원 금지.

---

## 10. Production Acceptance (단계 9 — 착지 후 코디네이터 append 자리)

**미기입 — 착지 후 append**: 본 PR은 `trustSurface` 구성원(`admission-check.yml`·`runner-pool-acceptance.yml`·`config/trusted_writer_set.json`)을 터치하므로 **auto-merge 거부 → 수동 native-MERGE** 경로다. 착지 후 기입 필드: repo PR 번호·merge commit SHA·org callee 회전(§11 후속)·재관측 런 1건(AXIOM_ARTIFACT_RECORD 라인 4 site 발화 + `retention-days` 실효 확인). 판정 명령은 `epoch_record_base_artifact_2026-10-01.md` §8의 L1/L2/L3 귀속 블록 준용.

---

## 11. KNOWN FOLLOW-UPS (본 변경에서 흡수하지 않음 — 범위 폐쇄, AGENTS.md §2.2)

1. **`test_admission_venue_split` 선존재 red 2건** — 본 변경 이전부터 존재(§6 #3 기계 확인: `admission-verdict-*` upload는 `4554c48f3^`에 이미 존재, landing conjunct 수 전후 동일): (a) landing-gate count pin 21 vs 24 관측 — 신규 landing 게드 step 개정 시 카운트 핀 동시 개정 누락 건; (b) freeze-tag artifact surface — `admission-verdict-*` upload가 `ci-frozen-2026-10-09-venue-split` 이후 착지했으나 freeze amendment 없음. **두 red 모두 본 diff 전후 byte-identical** — 본 PR이 고치지 않는다.
2. **REST enrichment 403** — `actions: read` 권한이 현재 GITHUB_TOKEN에 없어 enrichment가 403 → `metadata_status=degraded` loud degrade가 기대 동작. 권한 부여 시 자동으로 `observed_expires_at` 등이 채워진다 — 본 PR에서 권한을 넓히지 않는다.
3. **org callee pin 회전** — `Archright/.github` `admission-gate.yml`의 repo callee 핀이 본 변경 신규 blob을 가리키도록 하는 회전은 **merge 후 별도 step**이다(선례: `epoch_record_base_artifact_2026-10-01.md` §7 — 회전 미착지는 repo 병합을 막지 않는다).

---

## DEBT 등록 요약

**신규 DEBT 등록 없음** — 명시적 근거: ① 동작 의미 변경은 보존 기간 파라미터(문서화된 측정 정당화 §6)뿐, verdict·게이트 체인 무변경 ② fail-open 경로는 `{.bestEffort.}` 마커 + loud runtime log + inline reason의 문서화된 형태(§0.9 fail-open 조건 충족 — 극장 아님) ③ 추적 마커 제거 없음 ④ quirk 신규 없음. Theater/마스킹 행위 추가 없음.

---

## 부록: 본 기록에 사용된 실측 명령 요약 (2026-10-10, 전부 read-only)

`git branch --show-current` / `git log --oneline -3` / `git show --stat 4554c48f3` / `git rev-parse 4554c48f3^` / `git tag -a …` + `git rev-parse <tag>{}` / `git show 4554c48f3^:{config/trusted_writer_set.json,config/policy/epoch_manifest.json}`(변경 전 핀) / `git rev-parse {4554c48f3^,4554c48f3}:{.github/workflows/admission-check.yml,.github/workflows/runner-pool-acceptance.yml}`(blob 전후) / `git show 4554c48f3 -- <workflow>`(4 site diff) / `bash tools/ci/verify_trusted_writer_set.sh`(PASS, exit 0) / `nim c -r tests/ci/test_admission_check_stages.nim`(10/10 OK) / `nim c -r tests/ci/test_admission_venue_split.nim`(23 OK / 2 FAILED — 선존재 red) / `git show 4554c48f3^:.github/workflows/admission-check.yml | grep -c admission-verdict`(=9 — 선존재 확인) / landing conjunct 카운트 전후 비교(25 == 25). 커밋·푸시·PR 생성은 본 기록 작성 에이전트가 수행하며, 병합은 수행하지 않는다(수동 병합 = 인간 소관).

---

## AMENDMENT (post-landing — 2026-10-11, append-only)

> 본 섹션은 착지 후 추가다. 위 본문(§1–§11·부록)은 작성 시점(2026-10-10, 리베이스 이전 상태)의 역사 기록으로 그대로 보존되며, 본문이 인용하는 `4554c48f3`·pin `55f34314d…`·freeze `cdafd17b…`는 아래의 최종 착지 값들로 대체된다.

### A. 리베이스 2회와 최종 착지 (기계 재확인, 2026-10-11)

- **Axiom merge commit**: `574c7ca1a2d7214fc041b3a9a6efa1415a3c48c4` — `Merge pull request #710`(parents `709cc44c2` × `5da05ec81`).
- **1차 재베이스** — `ebffaf422`(=#711 merge) 위로 재앵커. 이 시점 admission-check.yml blob은 `63935d8d…`였다.
- **2차 재베이스** — 큐 대기 중 `8c0e591b9`(=#713 merge)가 선착지하여 재차 재앵커. 최종 착지 커밋은 `49fa7a41c`(ci)·`5da05ec81`(본 기록)로 확정되었다(부모 `8c0e591b9`). 본문 §5·§6 등이 인용하는 `4554c48f3`는 원본 브랜치 커밋이며 최종 착지 커밋이 아니다.
- **5번째 upload site(재베이스에서 확장)** — 1차 재베이스(위 ①) 시점에 main에 착지해 있던 **folded nimcache(job2) upload site**(`[check] Upload folded nimcache — B-cache carrier`, attest venue 조건부)가 커버에 추가되어 `retention-days: 3`이 부여되었다. 본문 §3.1의 "변경된 4개 upload site"는 최종 **5개 site**가 된다. 단, §3.2의 `AXIOM_ARTIFACT_RECORD` step은 4개 그대로다(5번째 site는 retention 마킹만).
- **최종 5 site**: `admission-check.yml` :513(`admission-check-base-artifacts`)·:586(`admission-check-base-nimcache`, job1)·:1107(folded nimcache, job2) + `runner-pool-acceptance.yml` :670(`ci-bootstrap-artifacts`)·:773(`candidate-arm64`).

### B. 3-way 핀 등식 (최종)

`git rev-parse 574c7ca1a:.github/workflows/admission-check.yml` = `config/trusted_writer_set.json:41` `trustedAdmissionWorkflowSha` = `config/policy/epoch_manifest.json:9` `productionExecutionPin` = **`aa7ee1235c44d699211c29f7641095610e21365f`** — 3-way 일치 ✓(2026-10-11 실측). `runner-pool-acceptance.yml` blob `afac7914e…`는 전 단계 동일(비핀 엔진 — §2.1 각주 유지).

### C. org callee 회전 (§11.3 follow-up 완료 — effect-precondition)

- `Archright/.github` `admission-gate.yml`의 repo callee 핀이 최종 merge commit으로 회전 완료: :314(`admission-check.yml`)·:450(`runner-pool-acceptance.yml`)·:525(`admission-check.yml`) → `@574c7ca1a…`. Dependabot PR **#150**(admission-check bump, merge `c11579d2`, 2026-10-10T17:08:13Z)·**#151**(runner-pool bump, merge `954ef9f0`, 2026-10-10T17:08:38Z)로 착지.
- §10의 착지 후 기입 필드 중 본 amendment가 대신 기입한 것: merge commit SHA(위 A)·org callee 회전(본 C). **재관측 런 1건**(AXIOM_ARTIFACT_RECORD 발화 + `retention-days` 실효 확인)은 본 amendment 범위 밖이며 코디네이터 append 과제로 남는다.
