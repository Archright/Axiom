# 병렬화 착지 잠금 교체 사전등록 — E3 조기 종결 경로 규정 (2026-10-14)

> **종류**: 사전등록 문서 (decision pre-registration) — GO-critical 4레인 병렬화 착지를 가로막는 E3 착지 잠금(구 prereg §7 / prereg-2026-10-13 §1)을 **본 문서가 정식으로 교체**한다. 착지 이후의 판정 규칙(δ-게이트·C2·성분 판정·종결 상태)은 prereg-2026-10-13에서 **변경 없이 승계**된다 (no-peeking — 운영 관측 개시 이전 고정).
> **규율 원천**: `docs/evidence/merge_latency_decision_prereg_2026-10-12.md` §7 · `docs/evidence/merge_latency_decision_prereg_2026-10-13.md` §1·§3–5(승계 대상) · `docs/evidence/e3_measurement_contract_2026-10-11.md` §5.6(교체 대상 조항의 원전) · `docs/evidence/e3_amendment_a2_2026-10-11.md` A2.3.4(per-모드 민감도) · `data/e4e5/ledger.json`(카운터).
> **고정성**: 본 문서가 main에 착지하는 순간 아래 규칙은 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다(선대 문서와 동일 규율).
> **권위**: 본 문서는 Reporter다 — 병합 판정 권위(GitHub ruleset·required checks·merge queue)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3). 본 문서의 병합은 어떤 판정 권위도 이동·추가·약화시키지 않는다.
> **소유자 승인**: 2026-10-14 사용자 전면 허가("권한이 필요한 부분은 전면 허가한다"). 본 문서는 그 결정의 정식 기록이며, 관측 개시 전 확정을 문서 커밋·PR·시각으로 추적 가능하게 한다. 표현상 이것은 "E3를 면제한 것"이 아니라 **"E3의 조기 종결 경로를 규정한 신규 사전등록 계약으로 기존 계약을 대체한 것"**이다 — 정책 변경 자체는 문제가 아니나, 정책 변경을 이미 수행한 실험의 통계적 확증으로 오인하게 만들어서는 안 된다.

---

## 1. 교체 범위 (정확히 무엇을, 어디까지)

**교체(해소)되는 조항 — 착지 잠금 하나만**:
- 구 prereg(2026-10-12) §7 "착지 트리거" — E3 단일 확증 추출 완료 전 병합 금지.
- prereg(2026-10-13) §1 "E3 착지 잠금 유지" — 상동 재고정.

**승계(불변)되는 규칙 — 전부**:
- prereg-2026-10-13 §2(AFTER 표본 정의)·§3(δ 관측 채널·해석 조항)·§4(채택 관문·C2 카운트)·§5(합격 밴드·종결 상태)·§6(동률·UNKNOWN)·(d) 부작용·복구·운영 조항 — 본 문서는 이를 **유리하게도 불리하게도 변경하지 않는다**.
- E3 계약·A2의 나머지 조항(표본 기계·카운터·창 규칙)은 창 닫힘(2026-11-10T02:52:14Z)까지 그대로 운영된다.

**본 문서의 범위**: GO-critical 4레인 병렬화(`ci/go-critical-parallel-reland-1014`)의 **단일 착지 실험에 한정된 잠금 교체**다 — 범용 정책 변경(예: 향후 모든 측정 계약의 조기 종결 허용)이 아니다.

## 2. 교체 사유 (기계적 사실)

- E3 §5.6 고정 n: n_B=12 ∧ n_C=30. 스냅샷 `data/e4e5/ledger.json`(collected_at 2026-10-13T03:44:47Z): **n_b_candidate=53(초과 달성) / n_c_candidate=0(0/30)** — 계약 병합(`ad43e67fa`) 이후 관측 53런 전건이 carrier HIT(carrier_miss_observations=0)이었다.
- C-arm 표본은 자연 랜딩 트래픽의 키 로테이션으로만 재생되는데(E3 §5.5) 현재 CAS 동작상 MISS 런이 발생하지 않으므로, 창 닫힘 전 n_C=30 도달은 **구조적으로 불가능**하다.
- 캐리어를 강제로 MISS 상태로 만들어 표본을 채우는 행위는 측정 대상 시스템 자체를 변경하는 **2중 처치 오염**이며, 그렇게 얻은 런을 유효 확증 표본으로 취급하지 않는다(구 prereg §7의 금지 취지 유지).
- 잔존 경로는 둘뿐이었다: (i) 2026-11-10 창 닫힘 underpowered 종결까지 4주 대기 — 그 사이 모든 착지가 직렬 비용(소비 job 552.0s/EXECUTED 런)을 지속 부담, (ii) **새 날짜 사전등록 계약에 의한 정식 교체** — 선대 문서의 개정 조항("변경은 새 날짜의 사전등록 문서로만")이 명시한 유일한 변경 메커니즘. 소유자는 (ii)를 선택했다.
- 절차 적법성: 본 문서는 docs-only 커밋이며 구 잠금의 적용 대상이 아니다(구 prereg §7·prereg-13 (d)5 — "본 문서·데이터·도구 커밋은 docs/data/tools-only 무오엘").

## 3. 선행 증거의 지위 (비확증 명시)

아래는 **관측 전 등록된 선행 증거이며, C-arm 확증 표본이 없는 비확증(non-confirmatory) 결과다** — 본 착지는 "underpowered, non-confirmatory" 상태에서 수행됨을 명시한다(E3 §5.6(b) 어휘 준용):

- 등록 기대 절감 E[Δc] = **−189s** > 문턱 135.0s(`attest_job_decomposition_2026-10-12.md` §5 L1).
- 국소 A/B: S2 웜 직렬 513.0s → P 병렬 307.7s(−205.3s), 콜드 −263.9s, 게이트 4/4 PASS, 판정 바이트 동일(`go_critical_parallel_ab_proof_2026-10-11.md` — **main 부재, 본 착지 PR에 동반 착지**; 국소 관측이며 게이트 표본 아님).
- dryrun 3-arm: 직렬 웜 552s → 병렬 322s, δ 사전준위 ≈ 0(`data/ci_optimization/dryrun_3arm_2026-10-13.md`).
- 운영 기준(before): `confirm_2026-10-12_R1` — 소비 job **552.0s**(sd 90.0, n=5; 런 ID 38194556640·38196395802·38199481287·38199696633·38200410801).

## 4. 착지 이후 판정 — 3층 어휘로 승계 (변경 없음)

- **운영 판정(δ-gate)**: prereg-13 §4.1 전체 그대로 — δ≤55s 결정적 채택 / (55,65] 동일 `head_sha` 재관측 2회(`gh run rerun`, attempt 기록) / δ>65s 미채택→REVERTED / 전면보류 H>126.4s·L>239.0s / 노출창 T_exp=24h·K_exp=10·2위 강제 revert. **채택은 운영 상태 유지 판정일 뿐 통계적 확증이 아니다.**
- **기계 확증(C2·성분)**: prereg-13 §2.4·§4.2·§5.1 그대로 — C2 지속 창 `[T_land, min(20 지불 런, 14일)]` 종료 시 단일 분석(중간 추출 금지), 지불 런 n≥8 ∧ 코호트×층≥2 ∧ min(G)≥3, 판정 (a) 절감>max(1s, 1.5×max(sd_base, sd_after)) ∧ (b) delta_L<0 ∧ delta_H<0, before=`confirm_2026-10-12_R1` 등록치.
- **통계 확증(E3 Δ̂)**: 본 교체로 E3 C-arm은 병렬 착지 시점부터 오염되어 **underpowered·non-confirmatory로 종결 예정**. 착지 이후 런은 A2.3.4에 따라 실행 모드(직렬/병렬)를 런별 기록하고 per-모드 민감도로 보고한다(멤버십·n 규칙 불변).

## 5. 종결 상태 매핑 (prereg-13 §5.4 승계 + 침묵 확정)

ACCEPTED / ACTIVE_UNPROVEN / REVERTED 정의는 prereg-13 §5.4 그대로다. 특히: **C2 미확증(지불 관측<8, §5.1 미충족, TOT 미달) → ACTIVE_UNPROVEN**(병렬 세대 운영 유지 + "개선 입증" 주장 금지 + `UNPROVEN` 동결 어휘) — REVERTED가 아니다. REVERTED는 §4.1 경로(미채택·전면보류·노출창 revert 강제)만 트리거한다.

### 5.1 침묵 확정 — revert 수송 경로·실행 주체 (prereg-13 (d)3이 남긴 침묵 봉인)

- REVERTED 이행 수단: **단일 원자 revert 커밋**(workflow+Makefile+config.nims+TWS+manifest 5파일 — 부분 복원 금지)을 **표준 PR → GitHub merge queue 경로**로 착지한다. main 직접 push 금지.
- 실행 주체: 착지 세션(소유자 권한 위임 하). revert 대상 5파일에 `merge_cli.nim`이 없으므로 trust-surface 수동 머지(MUST-T2)는 비적용 — 일반 자동 착지 경로를 따른다.
- 종결 조건은 prereg-13 §5.4 그대로: 원자 revert 커밋 + org 핀 구 blob 재회전 **둘 다** 완료 + golive_detect 재관측 구세대 확인(2-저장소 완료만 종결).
- δ 밴드 ((55,65]) 재관측의 `gh run rerun` 2회 실행 주체: 착지 세션(소유자 권한 위임 하) — attempt 번호 ledger 기록(prereg-13 §3.1).

### 5.2 침묵 확정 — ACTIVE_UNPROVEN 후속 (규칙 부재 봉인)

- ACTIVE_UNPROVEN 종결 시: 병렬 세대 운영 유지 + "개선 입증" 주장 금지 + `UNPROVEN` 동결 어휘(`data/readiness/independent_policy.json:11`). 후속 재측정은 **새 날짜 사전등록 문서로만** 예약 가능하며, 본 문서는 후속 일정을 스스로 정하지 않는다(소유자 결정 대기).

## 6. 등록 링크·카운터 스냅샷 (착지 시 재기록 의무)

- **구현(차량 재등록)**: `ci/go-critical-parallel-reland-1014` @ `be7d201fe`(본 문서 시점 OID — **PR 시점 재기록**). prereg-13 §7이 등록한 구 reland `400d6304b`는 main 대비 83커밋 낙후 + TWS 클로저 불일치로 폐기하며, -1014는 동일 변경의 최신 재배치 + 자기일관 핀 회전 차량이다.
- `workflow_blob_sha.new`: 착지 PR 시점 최종 트리에서 재계산·재기록(착지 PR 본문에 기록 — prereg-13 §1 "main 추가 전진 시 재계산" 조항 이행).
- ledger 스냅샷: 본 문서는 등록 시점 값(n_b=53 / n_c=0, collected_at 2026-10-13T03:44:47Z)을 인용하며, 착지 PR 시점 재스캔 값을 PR 본문에 병기한다.
- 근거 문서 `go_critical_parallel_ab_proof_2026-10-11.md`는 본 착지 PR에 동반 착지된다(§3).

## 7. 검증 가능성 (GET-only 재현)

```bash
gh pr view <병렬화 PR> --json state,mergedAt,mergeCommit    # 착지·T_land
tools/ci/golive_detect.sh --since <T_land> --tws-sha <신 TWS> --out data/merge_latency/golive_parallel
tools/ci/merge_latency_audit.sh --runs @data/merge_latency/golive_parallel.post_golive.ids \
  --out data/merge_latency/parallel_AFTER --boundary-note "smoke=<first_post_run_id> excluded; prereg 2026-10-13 + supersession 2026-10-14"
tools/ci/go_critical_parallel_extraction.sh runs <t_go_live> <out>   # δ 1차값 = LANE 행
gh pr list -R Archright/Axiom --state merged --limit 100 --json number,createdAt,mergedAt  # TOT
```

---

*본 문서는 운영 관측(AFTER 표본) 개시 이전에 고정되었다. 결과를 본 뒤의 규칙 변경은 어떤 형태로도 허용되지 않는다.*

---

## §8. 개정 (2026-10-15, append-only amendment) — 레인 stderr 라이브 전사·always 업로드 = 재병렬화 필수 승격 조건 (기계 집행)

> **성격**: 본 섹션은 착지(2026-10-14) 이후 2026-10-15에 추가된 개정이다. 위 §1–§7의 고정 본문은 한 글자도 변경하지 않았다(append-only — 기존 텍스트 무변경). 본 섹션은 기존 규칙을 폐기·완화하지 않으며, **새로운 승격 전제조건을 추가**한다. 근거 권한: 2026-10-15 P1-Branch-A 작업 지시(소유자 전면 허가 계보) + C1 감사 판정(`docs/evidence/slice_c_p1_evidence_audit_2026-10-15.md`).

**조항**: GO-critical 레인 병렬화 및 향후 어떤 형태의 착지-경로 재병렬화(re-parallelization)든, 그 승격(promotion) 조건에 다음을 **필수(MANDATORY)** 조건으로 추가한다:

레인 stdout/stderr는 반드시 스텝 로그에 도달해야 한다 — (i) 레인 호출의 라이브 tee(`nim … 2>&1 | tee "$d/run.log"` 패턴) 또는 (ii) 실패 레인 run.log의 스텝 로그 재출력(`cat "$d/run.log"`) — **그리고** 레인 로그 전체는 `if: always()` 조건의 upload-artifact 스텝으로 항상 업로드되어야 한다. 리다이렉트만 있고 전사·업로드가 없는 4레인 형태는 승격 금지다.

**기계 집행 (문서 조항이 아닌 도구 집행)**: 이 조건은 `tools/ci/validate_workflow_shell.sh`의 **레인-stderr 가드**(2026-10-15 추가)가 기계적으로 집행한다 — 스캔 대상 워크플로에 레인 패턴(`go-critical-lanes` / `lane_run` / `>…$d/run.log` 리다이렉트)이 존재하는데 전사 공개(라이브 tee 또는 `cat …run.log` 재출력) 마커와 `if: always()` upload-artifact(레인 로그 대상) 마커가 없으면 **FAIL**한다. 이 게이트는 bsec-integrity의 무조건 스텝이 소비하므로 merge_group·push 모든 착지 경로에서 OID 스냅샷 기준으로 검사된다. 셀프테스트: `make test-workflow-lane-guard`.

**레시피 (recipe)**: 라이브 tee = Slice B S2(queue-probe `f1e600965`, 2026-10-15 — `nim … | tee` 라이브 파이프라인, `docs/evidence/slice_b_s2_cold_repro_2026-10-15.md`); 재출력 + always 업로드 = `2555ab966e35e8a5023c28e87c1836b1744bd7a9`(브랜치 `fix/go-critical-cold-race-residual`, admission-check.yml "[check] Upload GO-critical lane logs (forensics — always)" 스텝 — **main 미착지**, 해당 브랜치에만 존재).

**위반 계보 (이 조건이 존재하는 이유)**: 2026-10-13 리버트된 4레인 blob(`2c94c991418dfd89e665ce4ec3efdcc86ffd2e93`)은 run.log 리다이렉트(:1199) 후 재출력이 없어, 병렬 레짐에서 실패한 레인의 원문이 merge_group 스텝 로그에서 소실되었다 — 2026-10-14의 5개 merge_group 실패 런이 유일한 PARTIAL 증거 행이다(C1 감사). P1(레인 stderr 방출)은 2026-10-15 시점에 승격되지 않으며, 본 개정의 필수 조건으로 **흡수**된다 — 향후 재병렬화 PR은 본 조건과 가드를 통과해야만 승격된다.
