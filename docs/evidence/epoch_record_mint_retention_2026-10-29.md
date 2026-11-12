# CI Epoch Record — mint callee retention cutover (epoch N+7): Freeze / Record / Tombstone / Atomic Binding Update

> **성격**: AGENTS.md §2.5(CI Epoch Cutover Protocol) 단계 1–5 기록 — **FREEZE / RECORD / TOMBSTONE / ATOMIC BINDING UPDATE**. 변경 = org 컨트롤러(`Archright/.github`)의 mint callee 핀을 `certificate-mint.yml@9aaee76f` → `@d117ae8e2`로 회전. callee 측 실질 변경은 `subject-certificate` 전송 아티팩트의 **`retention-days: 30 → 3`** 하나다.
> **작성일**: 2026-10-29.
> **정본 절차**: [admission-generation §4.1 경로 (a)](../spec/admission-generation.md) (controller-side pin promotion) + §4.3(사후 ruleset 재핀 의무). 선례 구조: [epoch_record_storage_retention_2026-10-10.md](epoch_record_storage_retention_2026-10-10.md).
> **왜 이 변경인가 (측정 근거, 2026-10-29)**: live Actions artifact **8,816개 / 7.00 GB** 중 `subject-certificate-*`가 **905개 / 3,324.8 MB (44.4%)**. 2026-10 누적 사용량 **37,234 GB-h** 대비 포함 풀 **37,200 GB-h**(50 GB-월) → 100.09% 소진으로 upload 하드 블록 → `admission-check` red → merge 차단. 초과분 실비용은 약 **$0.011**(GB-h 단가 `0.00033602`)이지만, 보존 정책이 없으면 재축적은 구조적으로 반복된다.

---

## 1. FREEZE (AGENTS.md §2.5 단계 1)

| 항목 | 값 |
|---|---|
| frozen previous pin | **`9aaee76f09748837ecf0c04779b8d2bdbc9a71c3`** (2026-10-16) |
| freeze 대상 (Axiom) | `d117ae8e2`의 부모 계보 = `63060d042078fbe434bf42d2611485cd43ca72d7` (PR #1116 착지점) |
| freeze 대상 (컨트롤러) | `bcfc1bbdea3bf143080c5d314966faf28b74ffd1` (PR #248 착지점) |
| immutable baseline 규칙 | frozen pin은 삭제·재작성하지 않는다 — rollback 기준(§8) |
| 태그 | 본 cutover는 태그 대신 **두 커밋 SHA + blob SHA**를 immutable 기준으로 쓴다(핀 승격은 Axiom 토폴로지 변경이 아니므로 workflow 세대 태그 대상이 아니다) |

## 2. RECORD (단계 2)

### 2.1 blob sha 전후 (content-addressed, 실측)

| 파일 | 변경 전 | 변경 후 |
|---|---|---|
| Axiom `.github/workflows/certificate-mint.yml` | `7452b9be3614f8008f0cd4eb0cb49a4a9aabee8e` (@`9aaee76f`) | `479f9b5b5a22a92c292f60f790e54d45a423ea5e` (@`d117ae8e2`) |
| 컨트롤러 `.github/workflows/admission-gate-v2.yml` | `b4444b0073125ed2aa98a52e5496e256a60c9b86` (@`bcfc1bbde`) | `7dce93112abd7607125f69997b671e2dfe9a1b6e` (@`58a2c546`) |

### 2.2 callee diff (전체)

`git diff 9aaee76f d117ae8e2 -- .github/workflows/certificate-mint.yml` = **4 insertions, 1 deletion**:

```diff
-          retention-days: 30
+          # 전송용 아티팩트 — 소비자는 전부 동일 run 내부(mint publish P1/P3,
+          # verdict --cert). durable 증거는 side-ref ledger(axiom/certificates).
+          # 3일 = 실행 상한 120분의 36배.
+          retention-days: 3
```

입력 계약(`stage`/`runId`/`runAttempt`/`headSha`/`baseSha`/`prNumber`), writer 권한(publish 단일 `contents: write`), required-check identity, 증거 본문 — **전부 무변경**.

### 2.3 trust-source binding (PREPARED, 실측 2026-10-29)

| 항목 | 값 | 일치 |
|---|---|---|
| `config/policy/epoch_manifest.json` `productionExecutionPin` | `83260f72a8e47645f30618fc426bc1fd7561587f` | ✓ |
| `config/trusted_writer_set.json` `trustedAdmissionWorkflowSha` | `83260f72a8e47645f30618fc426bc1fd7561587f` | ✓ |
| `admission-check.yml` blob @`d117ae8e2` | `83260f72a8e47645f30618fc426bc1fd7561587f` | ✓ |

본 cutover는 `admission-check.yml`을 건드리지 않으므로 TWS/manifest 쌍 회전은 **불요**하다 — 3-way 일치가 그대로 유지된다.

## 3. ARTIFACT / AUTHORITY BINDING

| 요소 | 상태 |
|---|---|
| 정본 증거 | `axiom/certificates` side-ref ledger (무변경) |
| 전송 아티팩트 | `subject-certificate-<run_attempt>` — **retention만 3일로 축소** |
| 소비자 | 전부 동일 run 내부 — `mint publish` P1/P3(`bin_ax_sha256` pin 소비), `verdict --cert` |
| 소비 시간 | 첫 merge_group에서 생성 10:22:18Z → publish 다운로드 완료 10:25:48Z 및 verdict fetch 완료 10:25:39Z. 큐 대기·재실행을 포함한 전체 상한은 미증명 |
| 30일 보존 잔여 | witness/verdict/judgment/admission-verdict 등 **접촉 없음** (2026-10-10 epoch의 4개 site 정책 불변) |

## 4. TOMBSTONE (단계 3)

폐기되는 동작: **`subject-certificate` 아티팩트가 30일 보존을 상속하던 상태.** 폐기 범위는 `certificate-mint.yml`의 전송 업로드 **정확히 1개 site**이며, 다른 업로드의 30일 보존은 변경하지 않는다. 이 tombstone은 required-check 우회·trust gate 비활성·검증 면제를 의미하지 않는다.

## 5. ATOMIC BINDING UPDATE (단계 5)

하나의 논리적 cutover 단위로 결속된 3개 착지:

| # | 위치 | 단위 | SHA / 값 |
|---|---|---|---|
| 1 | Axiom | PR #1117 `retention-days: 30 → 3` + ADR-0033 정합 | merge_group `d117ae8e2230906d4517a890d6b01e8b3c1e8c03` (2026-10-29T08:12:20Z merged) |
| 2 | 컨트롤러 | PR #249 callee 핀 회전 (2 occurrences) | merge commit `58a2c54666f25c8f9ebb96a8229eacaad01ad978` |
| 3 | org ruleset | 25218071 · 23943917 `workflows[].sha` 재핀 | 양쪽 `58a2c546…`, `enforcement: active`, `bypass_actors: []` |

## 6. 검증 (단계 6–8)

### 6.1 게이트 판정 (기계, waiver 없음)

- `pin-promotion-gate (DEBT#473)`: run `40843502824` **attempt 2 = SUCCESS**
- attempt 1 = FAILURE, 원인은 판정이 아니라 **자격 증명**: `curl: (22) … error: 401` → `PIN_PROMOTION: FAIL — cannot read epoch_manifest.json @main`
  - `AXIOM_READONLY_TOKEN`(Actions 시크릿, 최초 등록 2026-10-12)을 2026-10-29T08:52:44Z 재발급한 후 attempt 2가 통과했다. 첫 시도의 401은 관측됐지만 토큰 만료가 10-16 이후 전체 정체의 유일한 원인이었는지는 이 증거만으로 확정하지 않는다.
  - 우회 변수(`vars.AXIOM_PIN_ALLOWLIST`)는 사용하지 않았다(2026-10-21 제거된 경로)

### 6.2 PREPARED / PINNED

- PREPARED: §2.3의 3-way 일치(manifest == TWS == blob) 충족
- PINNED: 변경된 핀 커밋 `d117ae8e2`의 `admission-check.yml` blob == `83260f72…` → 성립

### 6.3 ruleset readback (byte-consistency)

PUT `orgs/Archright/rulesets/{25218071,23943917}` → GET 재판독. `sha` 외 모든 필드(`conditions`·`rules`·`bypass_actors`·`enforcement`)가 **byte-identical**임을 diff로 확인. 재핀 이전 25218071은 `7fffee318…`(#248 착지 후 재핀 누락 — **기존 드리프트**)였고 본 cutover가 이를 함께 해소했다.

### 6.4 수용 전 관측 (negative evidence — 핀이 실제 원인이었음을 입증)

핀 승격 **전**에 착지한 run의 아티팩트:

```
subject-certificate-1 (created 2026-10-29T08:05:27Z): ttl = 29 days, 23:59:55
→ RESULT: FAIL retention: 1 of 1 sampled artifacts outside [71h,73h]
```

Axiom main의 `retention-days: 3`이 존재하는데도 30일이 적용된 사실이, **컨트롤러 핀이 실행 경로의 실제 값**임을 직접 증명한다.

## 7. 수용 (단계 9) — 첫 운영 표본 PASS, 전체 수용 미완료 (2026-10-29T10:39Z 관측)

판정 근거는 아래 두 관측이며, 둘 다 **실제 merge_group 실행**에서 얻었다.

### 7.1 착지 사실

| 항목 | 값 |
|---|---|
| PR | #1118 `MERGED` at `2026-10-29T10:29:30Z` |
| main | `644fb9a22a2679ac56b5cb8c6db283fce277d064` |
| merge_group head | `644fb9a22a2679ac56b5cb8c6db283fce277d064` |
| merge_group admission-gate run | `40853901193` — `merge_group` / `completed` / `success` |
| merge_queue enqueue | `2026-10-29T09:58:50Z` (position 1, `AWAITING_CHECKS` → landed) |

### 7.2 필수 5종 (merge_group 권위)

merge_group 이벤트로 생성된 워크플로 런과 해당 체크런이 모두 success다. 체크런 이름과 워크플로 이름이 1:1이 아닌 경우(`admission-check`는 `admission-gate` 워크플로가 발행)가 있으므로, 판정은 **이름→워크플로 매핑 후 merge_group 런 결론**으로 한다.

```
OK  admission-check          workflow admission-gate=success             check-runs completed/success
OK  bsec-integrity           workflow bsec-integrity=success              check-runs completed/success
OK  debt-registry-gate       workflow debt-registry-gate=success          check-runs completed/success
OK  generation-acceptance    workflow generation-acceptance=success       check-runs completed/success
OK  axiom-operational-slice  workflow axiom-operational-slice=success     check-runs completed/success
```

착지 후 `push` 이벤트가 같은 SHA에 **새 체크런(in_progress)** 을 만들 수 있다. 이는 병합 심사 결과가 아니므로 판정에서 배제하고, 심사 권위는 merge_group 런에 둔다.

### 7.3 보존 관측 (핵심 판별자)

```
subject-certificate-1  artifact_id=12888869864  run_id=40853901193
                       created 2026-10-29T10:22:18Z  expires 2026-11-01T10:22:13Z
                       ttl = 71h 59m 55s  (retention-days: 3)

bash .cache/ax_storage/ax_storage_verify.sh post-landing --since 2026-10-29T09:58:50Z
  sample_size=1  violations=0
  RESULT: PASS
```

대조(핀 승격 전, §6.4): 같은 `subject-certificate-1` 계열이 30일을 선언했다. 승격 후 첫 mint가 **3일**을 선언했으므로, 컨트롤러 핀이 실행 경로의 실제 값이라는 명제가 양방향으로 확인됐다.

이번 mint 전 조회한 보존 분포(negative control): `subject-certificate` 899개 중 `~720h`=893, `2160h`=6, **`~72h`=0**. 이는 해당 조회 범위의 관측이며 전체 과거 이력의 증명은 아니다. 위 아티팩트는 merge_group 실행 중 생성됐고 PR의 main 착지보다 앞선다.

### 7.4 저장 사용량 전망

```
30-day integral of observed live bytes with no new inflow: 1,203.0 GB-h = 3.234% of 37,200 GB-h
monthly_total (2026-10): 37,242.885 GB-h  →  net 42.885 GB-h  ≈ $0.0144
packages rows: none
```

엔터프라이즈 `actions` 예산은 `budget_amount=1` / `prevent_further_usage=true`이며 실지출은 그 1.4% 수준이다. 경보 회귀(`will_alert=false`)는 `budget_alerting.will_alert=true`, `alert_recipients=["wintrover"]`로 복구했고 예산 금액·하드스톱은 변경하지 않았다.

### 7.5 완료 주장의 경계

- 성립: 보존 컷오버가 **실제 운영 merge_group에서** 3일을 선언하며, 필수 5종이 그 위에서 통과했다.
- 성립: 당시 관측된 기존 아티팩트만 만료까지 적분하고 신규 유입을 0으로 두면 3.234%다. 조직 조회 범위에 Packages 행이 없다는 사실만 확인했으며, 전체 청구 풀의 Packages 사용량은 별도 확인이 필요하다.
- 미성립: 신규 유입과 다른 청구 대상 사용량을 포함한 월간 사용률 25% 이하 및 두 번째 서로 다른 post-cutover merge_group의 관측. 첫 표본만으로 전체 수용을 주장하지 않는다.
- 미성립: 3일이 모든 대기·재실행 경로의 생성→소비 시간을 덮는다는 보장. GitHub의 `jobs.<job_id>.timeout-minutes`는 개별 잡에 적용되며, [self-hosted 잡은 최대 24시간 대기](https://docs.github.com/en/actions/reference/limits), [재실행은 최초 실행 후 30일까지 가능](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs)하다. 만료 이후 재실행의 허용 범위와 실패 처리 계약을 확인해야 한다.
- 미성립(주장하지 않음): 저장 쿼터 소진이 병합 가용성을 **절대** 차단하지 못한다는 보장. 본 변경은 체류 시간을 줄여 재발 위험을 낮추는 것이지, 저장 매체와 병합 권한의 결합을 제거한 것이 아니다. 그 분리는 별도 설계다.

## 8. ROLLBACK

| 상태 | 행위 |
|---|---|
| 핀 승격 결함 | 컨트롤러 PR revert → 핀 `9aaee76f` 복귀(30일). Axiom 측 `retention-days: 3`은 그 상태에서 **미사용**이므로 무해 |
| ruleset 재핀 실패/불일치 | 양 ruleset을 §6.3의 이전 값으로 원복 — 25218071 = `7fffee318…`, 23943917 = `bcfc1bbde…` (같은 PUT 경로 + readback) |
| 판정 불가 | 원복을 선언하지 않고 조사한다. `enforcement`는 어느 경우에도 `active`를 유지해 병합 공백을 만들지 않는다 |
| 금지 | 게이트 우회(waiver 변수·ruleset bypass actor 추가)로 핀을 통과시키는 것 |

## 9. 잔여 / 후속

- **예산 경보**: §7.4의 재설정 및 API readback으로 복구를 확인했다. 실제 알림 전달 여부는 별도 미확인이다.
- **핀 만료 재발 방지**: `AXIOM_READONLY_TOKEN`의 만료일을 운영 캘린더에 등록한다. 게이트의 401과 재발급 후 성공은 관측했으나 과거 전체 정체 기간의 원인을 단독으로 확정하지 않는다.
- **두 번째 운영 표본**: 서로 다른 post-cutover merge_group head에 대해 5종과 해당 실행의 72시간 아티팩트를 검증한다.
- 저장 사용량의 지속 관측: 신규 유입과 청구 범위를 포함해 월간 GB-h가 25% 이하인지 별도로 측정한다.