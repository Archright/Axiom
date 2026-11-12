# 병렬화 착지·AFTER 판정 사전등록 — GO-critical 4레인 (2026-10-13)

> **종류**: 사전등록 문서 (decision pre-registration) — GO-critical 4레인 병렬화(reland `ci/go-critical-parallel-reland` @ `400d6304b`, #754 `3dd483908`의 재이식)의 **착지 전에** 채택 관문 해석·AFTER 표본·합격 밴드·종결 상태를 숫값과 기계 술어로 고정한다 (no-peeking — 착지·표본 관측 이전 고정).
> **규율 원천**: `docs/evidence/e3_measurement_contract_2026-10-11.md`(E3) §5.6 · `docs/evidence/e3_amendment_a2_2026-10-11.md`(A2) §A2.1–A2.5 · `docs/evidence/merge_latency_decision_prereg_2026-10-12.md`(구 prereg — 본 문서의 선행 형식) · `docs/evidence/attest_job_decomposition_2026-10-12.md` §5–6(L1 등록) · `tools/ci/merge_latency_audit.sh`·`tools/ci/golive_detect.sh`·`tools/ci/go_critical_parallel_extraction.sh`(듀얼 모드 `e65ccdeed`) 헤더 계약 · 등록 베이스라인 `data/merge_latency/baseline_2026-10-11.runs.jsonl` + `confirm_2026-10-12_R1.runs.jsonl`.
> **고정성**: 본 문서가 main에 착지하는 순간 아래 규칙은 **고정**된다. 착지 이후 변경 금지 — 변경은 새 날짜의 사전등록 문서로만 한다(본 문서 개정 금지; 구 prereg:5와 동일 규율).
> **권위**: 런/잡/스텝·핀 식별 = GitHub Actions API(GET), δ 1차값 = 작업 로그 `LANE` 행, 키·재사용 분류 = 등록 하니스. 본 문서와 도구는 Reporter다 — 병합 판정 권위(GitHub)를 대체하지 않는다(Authority ≠ Adapter, AGENTS.md §2.3).
> **소유자 승인**: 2026-10-13 세션 계획 v3 승인(해석 조항 §3.1·§4.2·allowlist §d-6 포함) — 원기록은 세션 계획 문서.

---

## 1. 배경과 경계 — 등록 대상과 식별자

- **변경**: admission-check.yml GO-critical 스텝 4레인 병렬화 + `Makefile` test-fast-one `NC`/`OUT` 파라미터화 + `config.nims` hermetic 스탬프 PID-고유 tmp(§-1 블록 밖) + 3-way 핀 원자 회전 + `trustedCheckerTreeClosure` 재앵커(864==864, `pin@H == derived(H)` 입증 완료 @ `400d6304b`).
- **경계 식별자**(착지 시 기계 기록, `data/e4e5/landing_boundaries/` 레코드 스키마 준용):
  - `T_land` / `merge_commit_oid` = 병렬화 변경의 GitHub MERGE 커밋(A2.3.1 정의 그대로).
  - `workflow_blob_sha.old/.new` = 직렬/병렬 세대 admission-check.yml blob. 착지 시점 신값 = `646ae939648443200843f3bf0ccb05afc945f1a9`(@400d6304b 재계산 — main 추가 전진 시 재계산·재기록).
  - `pins_rotated_in_same_commit` = true 요건(epoch_transaction_gate).
  - `t_go_live` = `golive_detect.sh` 관측 `first_post_run_started_at`(첫 신 blob merge_group 런 시작) — **T_land과 별개**(핀 회전 지연 실측 선례: 2026-10-12 T_land→golive 67m26s, `external_trust_anchor_org_workflow_2026-10-12.md` §2–3).
- **스모크 앵커**: `first_post_run_id`(golive 최초 신세대 런). 모든 AFTER 모집단은 이 런의 `run_started_at` **엄격 초과**(구 prereg §2.1 준용 — 최초 런은 전환 검증이지 성능 표본이 아니다).
- **E3 착지 잠금 유지**: 병렬화 착지(merge)는 E3 단일 확증 추출 완료(고정 n_B=12 ∧ n_C=30 도달, 또는 창 닫힘 2026-11-10T02:52:14Z underpowered 종결 — E3 §5.6) **이후에만** 허용된다(구 prereg §7, 2중 처치 방지 — 본 문서가 이를 재고정한다).

## 2. AFTER 표본 정의 (사전 고정)

1. **모집단**: `event=merge_group` ∧ 런 `path` endswith `admission-gate.yml` ∧ `run_attempt=1` ∧ `run_started_at > t_go_live` ∧ **golive_detect 런별 분류 `post_golive`(`callee_pin_blob_sha == TWS(new)` 등식)** — 타임스탬프는 발견 보조이고 **분류가 권위**다(미분류 `unknown`은 exit 3 fail-closed로 기록·제외 사유 명시, 조용한 탈락 없음).
2. **독립성 키**: 런의 `head_branch`(큐 브랜치명 = PR×병합 베이스 SHA). 같은 키의 두 번째 이후 런은 `dependent_repeat`로 기록되며 N 불가산(구 prereg §2.2).
3. **분류**: A2.1.2 기계 분류(EXECUTED / FULL_REUSE / PARTIAL_REUSE / UNKNOWN_LOG). 레짐: a-restore 40,000ms 마커, 미판별 → H 밴드(A2.2.7 fail-closed). FULL_REUSE는 별도 층 보고·시간 통계 불가산.
4. **N 고정**: C2 지속 창(§4.2)이 닫히는 시점에 **딱 한 번** 분석(단일 분석 — 중간 추출 금지, 포함기준 확인[카운트]은 허용·기록). wall 비교 최소표본: **지불 런 n≥8 ∧ 코호트×층 ≥2 ∧ min(G)≥3**(A2.3.3-iv·A2:104) — 미달 시 §5.4 종결 어휘 적용.
5. **갭 런 처리**: T_land~t_go_live 사이(구세대 callee 실행) 런은 AFTER에 **불가산**, ledger에 제외 사유와 함께 기록(pin-promotion-lag 선례: "첫 post-T_land MG 런은 착지된 워크플로를 실행하지 않았다").

## 3. δ 관측 채널과 A2.2.3 해석 조항

### 3.1 해석 조항 — A2.2.3 "동일 merge 커밋 OID 일치"의 기계 술어 (침묵 확정)

A2.2.3은 "동일 후보 코드(Git merge 커밋 OID 일치) 위의 merge_group 런 2건"을 요구하나 **판독 필드를 규정하지 않는다(A2 전수 확인 — 침묵)**. 본 절이 그 침묵을 기계 술어로 확정한다(소유자 승인 2026-10-13; 원문 수정 아님):

- merge_group 런의 `GITHUB_SHA`는 **큐 그룹 커밋**(GitHub 공식 문서 "SHA of the merge group")이며 main 착지 머지 OID와 문자상 일치하는 일은 구조적으로 없다. 따라서 **"merge 커밋 OID 일치" = 두 관측(런, attempt)의 `head_sha`(그룹 커밋 40-hex) 동등**로 판독한다.
- **밴드 ((55,65]] 재관측 경로**: 동일 `head_sha` 위의 관측 2회 = 플랫폼 네이티브 재실행(`gh run rerun` — 2026-10-06 부록 (c): MG 런 재실행은 동일 커밋에서 실행). attempt 번호를 ledger에 기록한다. warm 술어(`[test-supply] restored entries=N ∧ N>0`)는 재실행에서도 동일 채널로 판독한다.
- **방화벽**: δ-게이트 재관측(attempt≥2 포함)은 §2.2 `dependent_repeat` 규칙에 따라 **AFTER 표본 N에 불가산**한다(채택 관문 관측과 성능 표본의 정의 분리).

### 3.2 δ_obs 관측 채널

- `δ_obs = 병렬 GO-critical 스텝 벽시계 − max(단일 테스트 소요)`(A2.2.1).
- **1차값 = `[admission-tests] LANE <slug> duration_ms=<ms> — <test>` 행**(듀얼 모드 추출기 `go_critical_parallel_extraction.sh`@`e65ccdeed`의 `go_mode=lane`; 직렬 로그는 `serial`로 하위호환 산출). 병렬 로그의 RUN→PASS 타임스탬프는 post-wait 퇴화값이므로 1차값이 아니다(AB 원장 §3–4).
- 결측(`duration_ms=NA`·레인 행 부재)은 `NA` 보고 — 삼킴 금지.

## 4. 채택 기준과 C2 카운트 해석 조항

### 4.1 채택 관문 = A2.2 전체 재인용 (개정 금지)

δ ≤ 55 s 결정적 채택 / (55, 65] 밴드 → §3.1 재관측 2회(밴드 밖 같은 쪽 → 착정, 밴드 내·엇갈림 → 72h 내 미해소 시 미채택) / δ > 65 미채택 → REVERTED로 회복(종국 "미착지") / 전면보류 H > 126.4 s·L > 239.0 s / 카덴스 7일 rolling < 2.2 런/일 연속 2일 → 보류(A2.2.6). (b) 경로(별도 4잡)는 첫 미채택 관측 후 K_mb=5런/T_mb=72h 창 내에서만 재평가(A2.2.4 — 본 착지의 기본 경로 아님). 사후 노출 창: 첫 δ_obs>65 관측부터 T_exp=24h 또는 K_exp=10 지불 런 내 강제 착정, 같은 지속 창 내 두 번째 >65 → **revert 강제**(A2.2.5).

### 4.2 해석 조항 — C2 "20 지불 런" 카운트 대상 (침묵 확정)

A2.5 C2의 지속 창 `[T_land, min(20 지불 런, 14일)]`에서 **"지불 런"의 카운트 대상 = 신세대 지불 런만**으로 판독한다: `golive_detect` 분류 `post_golive` ∧ A2.1.2 `EXECUTED`(FULL_REUSE = 미지불·불가산은 A2:31·DECOMP:173 명문). 근거: (a) 창의 목적은 신세대 노출 봉인이며 δ_obs는 신세대 런에서만 관측 가능, (b) A2 작성(2026-10-11)은 T_land~t_go_live 핀 지연 갭(2026-10-12 발견)을 인지하지 못했다 — 갭 런(구세대)은 §2.5대로 기록·불가산. "지불" = merge_group층 실실행 런(유료 과금 무관, DECOMP:173-176).

## 5. AFTER 합격 밴드 (사전 고정 — 사후 유리 조정 금지)

### 5.1 성분 판정 (기계 문턱 — PREREG-Tier 3)

각 성분(go_step_s·attest 잡 duration·run wall·S2)에 대해: **판정 (a)** = `절감(before − after) > max(1 s, 1.5 × max(sd_base, sd_after))` — sd는 구 prereg §4.1 방식의 합집합 표본 sd(n−1). **판정 (b)** = `delta_L < 0 AND delta_H < 0`(양층 감소). **합격 = (a) ∧ (b)**. before = `confirm_2026-10-12_R1` 등록치. 판정은 RAW 측정과 분리하여 등록 규칙의 기계 적용으로 서술한다("NO judgment — pre-registered decision rule doc not yet landed" → 본 문서 착지 후 판정 허용, golive n=6 선례).

### 5.2 TOT/S1/S2 장부 (코호트·검열 규칙)

- **고정 코호트**: **t_go_live 이후 `created_at`를 가진 PR 전건**(타인 소관 포함). 창 닫힘 = §2.4 C2 종료 시점. (PR created_at 창 앵커는 저장소 최초 — 생존자 편향 방지 목적으로 본 문서가 정의한다.)
- **우측 검열**: 단일 분석 시점에 미병합 PR = `M_RIGHT_CENSORED` 분류로 **기록하되 불가산**(prereg §2.5 "이후 종료 불가산·ledger 누적" 준용). closed-unmerged·재오픈 PR은 기준 기반 제외+사유 기록(E3 §5.4 문형; reopen은 identity를 바꾸는 재트리거 — `canonical_main_slice_close_2026-09-18.md:83` 선례).
- **검열 상한(신설)**: 코호트 중 (censored + 기준 제외) 비율 > **30%** → TOT 판정 = **미입증** — 근거: fail-closed 퇴화 계보(G_min=2 종단 "확증 불가" A2:158, UNKNOWN 1건 라운드 중단 prereg §6). 선택적 누락 금지 — 분모(코호트 전건 수)를 반드시 공개.
- **보고 하한**: TOT 유효 표본 **n ≥ 5**(golive-activation `target: >=5` 선례) — n≥5는 판정 전제 하한이지 검정력 유도값이 아니다; "n=5 샘플의 착시 성분" 경고(`r1_s1a_runtime_bimodal_measurement_2026-10-09.md:83`)를 인용한다. 미달 시 미입증.
- **측정 채널**(canonical_build_reuse §1 준용): TOT = `pulls/{n}` created→merged, S1 = open→`admission-check` check-run 성공 완료, S2 = `issues/{n}/timeline` `added_to_merge_queue`→merged. **TOT(push) 병기**(마지막 push→merged — 작성자 지연 민감도, #561 선례). 재진입(dequeue→re-queue)은 실패 판정 근거로 쓰지 않고 상태 전이만 기록(gh_run_observation_quirks Q6).

### 5.3 판정 어휘 층 구분

본 판정은 **기계 문턱(PREREG-Tier)**이다 — 통계적 유의성(CI 하한·p값) 어휘 사용 금지. 통계적 확증 주장은 E3 Δ̂ 기계(E3-Tier 1/2, 세대-평균 2표본 t·df=G_min−1)에만 존재하며 본 착지 판정과 별개 층이다(동일 "Tier" 번호 혼동 금지 — 표기 `PREREG-Tier`/`E3-Tier`).

### 5.4 종결 상태 (닫힌 집합)

- **ACCEPTED**: §4.1 채택 ∧ C2 지속 창 내 δ_obs≤65 유지 ∧ §5.1 (a)∧(b) 통과.
- **ACTIVE_UNPROVEN**: 채택은 유지되나 성능 미입증 종결 — C2 창 닫힘+지불 관측<8, TOT 검열 상한 초과, TOT n<5, 또는 §5.1 미충족. 병렬 세대는 운영 유지, "개선 입증" 주장 금지, `UNPROVEN` 동결 어휘 준용(`data/readiness/independent_policy.json:11` — 절대 PASS 승격 불가).
- **REVERTED**: §4.1 미채택/전면보류/노출 창 revert 강제 → 원자 revert 커밋 + org 핀 구 blob 재회전 **둘 다** 완료 + golive_detect 재관측 구세대 확인(2-저장소 완료만 종결 — epoch_record_base_artifact:79 계보).

## 6. 동률·UNKNOWN — fail-closed

구 prereg §6과 동일하게 적용한다: 동률(상위 두 성분 점유율 차 <1.0pp) → 변경 없음 보고. UNKNOWN_LOG·regime=unknown 런 1건 관측 or 하니스 하드페일 → 라운드 즉시 중단, 목표 선정·효과 판정 모두 금지, 재개는 새 날짜 사전등록 문서로만.

## 7. 등록 링크 (저장소 SSOT)

- 구현: reland `ci/go-critical-parallel-reland` @ `400d6304b`(로컬 — PR 시점 OID 재기록) — 원조 PR #754 `3dd483908`(CLOSED 미병합, 브랜치 보존)의 재이식.
- 근거 문서: `go_critical_parallel_ab_proof_2026-10-11.md`(국소 A/B — **게이트 표본 아님**, §4 명문) · `go_critical_parallel_decomposition_2026-10-11.md` §9 · A2 · 구 prereg(2026-10-12, 자기 개정 금지) · `attest_job_decomposition_2026-10-12.md` §5–6(L1 등록, E[Δc]=−189s > 문턱 135.0s).
- 도구: `go_critical_parallel_extraction.sh` 듀얼 모드 `e65ccdeed`(직렬 산출 바이트 동일 실측 — 실런 2건+fixture 9/9) · `merge_latency_audit.sh` · `golive_detect.sh`.

## 8. 착지 선행 증거 (등록 시점)

본 문서 등록 시점 AFTER 표본 **N=0**(착지 전 — 표본 부재가 곧 N=0이다). E3 ledger 최종 스캔(2026-10-13 재수집 예정): n_b_candidate=14 / **n_c_candidate=0** (요구 n_C=30). 채택 관문 표본·AFTER 표본 모두 미관측 — 본 문서는 결과를 보지 않고 작성되었다(no-peeking).

## 9. 검증 가능성 (GET-only 재현)

```bash
# 경계·분류
tools/ci/golive_detect.sh --since <T_land> --tws-sha <신 TWS> --out data/merge_latency/golive_parallel
# AFTER 측정·비교 (post_golive.ids만)
tools/ci/merge_latency_audit.sh --runs @data/merge_latency/golive_parallel.post_golive.ids \
  --out data/merge_latency/parallel_AFTER --boundary-note "smoke=<first_post_run_id> excluded; prereg 2026-10-13"
tools/ci/merge_latency_audit.sh --compare \
  data/merge_latency/confirm_2026-10-12_R1.runs.jsonl @data/merge_latency/golive_parallel.post_golive.ids \
  --out data/merge_latency/parallel_AFTER
# δ (LANE 1차)
tools/ci/go_critical_parallel_extraction.sh runs <t_go_live> <out>   # go_mode=lane, go_lane_sum_s
# TOT/S1/S2
gh pr list -R Archright/Axiom --state merged --limit 100 --json number,createdAt,mergedAt
gh api repos/Archright/Axiom/issues/<n>/timeline --jq '[.[]|select(.event=="added_to_merge_queue")|.created_at]'
```

## (d) 부작용·복구·운영 조항

1. **실패 전파 불변**: 레인 rc → wait 누적 `rc_all` ∧ status 파일 합산 `FAILS`(빈 status도 FAILS+1) → 스텝 exit 1 → attest 실패 → admission 실패 → merge 블록(비영 전파 — decomposition §9.3, `400d6304b` 이식 확인).
2. **캐리어 오염 봉인**: 레인별 nimcache(`NC`)·TMPDIR·`-o` 격리 + 직렬 캐시 스테이징 시 레인 서브트리 사전 제외(AB §1; 세대 자기-재귀 팽창 봉쇄).
3. **revert**: 단일 원자 revert 커밋(workflow+Makefile+config.nims+TWS+manifest 5파일 — 부분 복원 금지) + **org 핀 구 blob 재회전**(REVERTED 종결 조건; δ 계약 문서는 침묵 — epoch 기록 선례로 본 문서가 봉인).
4. **org 핀 회전 마감**: 표준(트리거→Dependabot) ≤2h 기대; **48h** 내 회전 PR 미생성·미병합 시 매뉴얼 회전 폴백(AXIOM_PIN_ALLOWLIST 절차, 수동 실측 59s–14m13s); **72h** = daily 3연속 무등장 판정선(org dependabot.yml = daily 06:30 KST·cooldown 0 실측 기반). LANDED/OLD_PIN_ACTIVE 체류 상한.
5. **착지 잠금**: E3 단일 추출 완료 전 GO 소요 영향 착지 금지(§1). 본 문서·데이터·도구 커밋은 docs/data/tools-only 무오엘.
6. **ROTATION allowlist 동반 확장**: 본 착지는 클로저 멤버(config.nims) 변경으로 merge_cli ROTATION 클래스 → 현재 allowlist에 없는 `Makefile`·`docs/evidence/go_critical_parallel_ab_proof_2026-10-11.md`가 동반 변경된다. **열거형 확장**(위 2경로 + 구현 3파일·핀 2파일·본 prereg)을 ADR-0025 Amendment A2/A3 계보의 개정 경로로 등록하여 착지 PR과 함께 승인한다(merge_cli.nim 코드 미러 동반 — trust surface, MUST-T2 수동 머지 대상). 대안(#795식 `--admin` 명시 예외)은 allowlist 확장이 불가할 때만.
7. **AXIOM_PROVE_WORKERS=1 불변** — 레인 병렬은 셸 `&`/wait 수준, config.nims parallelBuild·worker 정책 비접촉(J4 §4.1 비트리거 주석과 함께 TCB 판정 기록에 명시).

---

*본 문서의 규칙은 착지·표본 관측 이전에 고정되었다. 결과를 본 뒤의 규칙 변경은 어떤 형태로도 허용되지 않는다.*
