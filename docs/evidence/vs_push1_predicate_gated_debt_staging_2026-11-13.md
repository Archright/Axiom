# VS-PUSH-1: Predicate-Gated Debt Evaluator Staging & VS-LEAN-1 Pre-Gate Verdict (2026-11-13)

- **Workstream**: `workstream/vs-push-1-predicate-gated-debt-staging`
- **Base**: `main @ 9ab4feb` (post-PR #24 native MERGE)
- **Authority**: `Makefile` (`push-admissibility` / `push-admissibility-debt-prereqs`), GNU Make recipe execution semantics (GNU Make Manual §4.2, §4.3, §5.3).

---

## §1. VS-PUSH-1 설계 반박 검증 및 계약 확정

| 설계 주장 | 검증 판정 | 근거 (`file:line` + 공식 문서) |
|---|---|---|
| "Predicate 오류·알 수 없는 응답 시 `exit 2`로 실패 종료해야 한다" | **반박 (기각 → 현행 `error → RUN` 유지)** | `Makefile:494-526`의 Python 스크립트는 모든 내부 오류(`die()`, `git merge-base`/`diff` 실패, JSON 예외)에서 `sys.exit(1)`을 반환하며, 셸의 `if printf ... \| python3 -; then :; else ...; fi` 가드는 python3 기동 실패(exit 127)를 포함한 모든 비-0 종료 코드를 `else`(RUN) 분기로 수렴시킨다. `exit 2`는 ① debt 내용을 평가하지 않은 채 push를 차단해 진단 정보를 잃고, ② GNU Make 자체의 recipe 실패 코드(`Error 2`)와 충돌하며, ③ 일시적 git 오류 시에도 게이트 실행 대신 push를 불필요하게 차단한다. 안전성(fail-closed)은 동급이고 진단·가용성에서 현행 `error → RUN`이 지배적이다. |
| "`BUILD_FAILED` 별도 상태 계약을 신설해야 한다" | **반박 (기각)** | `.githooks/pre-push:779-812`(F5)가 게이트 실패·원본 트리 오염·성공 3경로 전부에서 `git worktree remove --force "$SNAP"` + `rm -rf` + `git worktree prune --expire now`를 수행하므로, 부분 빌드 스냅숏이 다음 푸시로 잔류할 상태 저장소가 없다. |
| "SKIP이면 스냅숏 게이트 전체를 종료한다" | **반박 (건전성 범위 교정)** | `Makefile:475-485`의 SKIP predicate는 **오직 `debt_engine`의 실입력집합**(`data/architecture_debt.json`, open/deferred `debt_registry.json` `files[]`, 고정 9개 정책/원장 파일)과의 서로소(disjointness)만 증명한다. `check-repository-surface`는 브랜치 diff 전체가 입력이고 `check-determinism`은 호스트 툴체인이 입력이므로 이 predicate로 건전하게 SKIP할 수 없다. 따라서 건전한 변경은 `push-admissibility:` 타깃 헤더의 무조건 선행조건 `bin/effect_contract_projection bin/nimtry`만 RUN 전용 sub-target `push-admissibility-debt-prereqs`로 이동하고, 나머지 스냅숏 게이트는 SKIP 푸시에서도 그대로 실행하는 것이다. |
| "`set -e`와 명령 치환 결합으로 셸이 조기 종료될 수 있다" | **수용·정밀화 (`if` 가드 유지)** | 현행 `push-admissibility` 레시피에는 `set -e`가 없으나, GNU Make 공식 문서(§5.3 Recipe Execution / Errors in Recipes)에 따라 각 레시피 라인은 별도 서브셸로 실행되고 비-0 종료 시 즉시 룰이 중단된다. 본 구현은 명령 치환 변수 할당을 도입하지 않고 현행 단일 논리 라인 `if ... | python3 -; then :; else $(MAKE) --no-print-directory push-admissibility-debt-prereqs && bin/debt_engine --validate; fi` 가드를 그대로 유지해 조기 종료 경로를 원천 배제했다. 또한 `debt_engine`(`tools/debt_engine.nim`)은 `stdin`을 읽지 않고 자체 상수 경로를 직접 `readFile`하므로 predicate 부분 출력의 재사용 경로가 존재하지 않는다. |

---

## §2. 핵심 변경

1. **`Makefile` (`push-admissibility-debt-prereqs` 분리)**:
   - `push-admissibility:` 타깃 선언부에서 `bin/effect_contract_projection bin/nimtry` 선행조건을 제거.
   - `push-admissibility-debt-prereqs: bin/effect_contract_projection bin/nimtry` sub-target을 신설하고, `push-admissibility` 레시피의 `else`(RUN 및 fail-safe 오류) 분기에서 `$(MAKE) --no-print-directory push-admissibility-debt-prereqs && bin/debt_engine --validate`로 조건부 스테이징 후 검증을 실행.
2. **`docs/spec/push_admissibility_stale_binary_quirk.md`**:
   - §0.5 Quirk 문서의 `push-admissibility` 타깃 선행조건 서술을 현행 구조(`push-admissibility-debt-prereqs` 분리)와 일치하도록 갱신.

---

## §3. 기계 검증 증거

### 3.1 조합 테스트 6케이스 (GNU Make 실측)

| 케이스 | 입력 조건 | 관측 동작 (`trace.log`) | 종료 코드 | 판정 |
|---|---|---|---|---|
| ① 정상 SKIP | predicate `sys.exit(0)` | `START → DOWNSTREAM_GATE_RUN → ALL_GREEN` (`BUILD_EFFECT`/`BUILD_NIMTRY`/`DEBT_ENGINE` **0회**) | `0` | PASS |
| ② 정상 RUN | predicate `sys.exit(1)` | `START → BUILD_EFFECT → BUILD_NIMTRY → PREREQ_STAGED → DEBT_ENGINE_RUN:--validate → DOWNSTREAM_GATE_RUN → ALL_GREEN` | `0` | PASS |
| ③ 내부 판정 오류 | predicate `raise RuntimeError("boom")` | `error → RUN` 폴백 작동, 케이스 ②와 동일 경로 실행 | `0` | PASS |
| ④ 기동 실패 (exit 127) | `PYTHON_BIN=/nonexistent/python3` | `error → RUN` 폴백 작동, 케이스 ②와 동일 경로 실행 | `0` | PASS |
| ⑤ sub-make 빌드 실패 | RUN + `bin/effect_contract_projection` 빌드 `exit 1` | `START → BUILD_EFFECT → SIMULATED_BUILD_FAIL` (`&&` 단락으로 `DEBT_ENGINE` 및 하위 게이트 **미실행**) | `2` (FAIL 전파) | PASS |
| ⑥ 하위 게이트 실패 | SKIP + 하위 게이트 `exit 1` | `START → DOWNSTREAM_GATE_RUN` 후 즉시 중단 | `2` (FAIL 전파) | PASS |

### 3.2 SKIP 스냅숏 수용 기준 4항목 (3회 반복 실측, detached worktree @ `9ab4feb`)

- 격리 측정된 `bin/effect_contract_projection + bin/nimtry` 콜드 스냅숏 빌드 비용: **5.26s** (`nim c` 2회, CC 139).
- SKIP 스냅숏 `make -C "$SNAP" push-admissibility` 3회 연속 실측:
  - **Iter 1**: `wall=74.41s | effect_built=0 nimtry_built=0 | nim_c=4 | skip_msg=1 | pass_msg=1`
  - **Iter 2**: `wall=73.23s | effect_built=0 nimtry_built=0 | nim_c=4 | skip_msg=1 | pass_msg=1`
  - **Iter 3**: `wall=83.89s | effect_built=0 nimtry_built=0 | nim_c=4 | skip_msg=1 | pass_msg=1`
- 수용 기준 대조:
  1. **debt 전용 빌드 2종 실행 횟수 = 0**: 3회 모두 `$SNAP/bin/effect_contract_projection` 및 `$SNAP/bin/nimtry` 미생성(`0`), 빌드 로그 내 두 타깃 컴파일 `0`회.
  2. **스냅숏 컴파일 횟수 2회 감소**: `nimtry`·`effect_contract_projection` 2회 제거 확인.
  3. **전체 스냅숏 게이트 실행 유지**: `check-nim-theater`, `doc-path-validator`, `check-proof-unit-consistency`, `check-proof-unit-reconcile`, `check-epoch-transaction`, `check-determinism`, `check-repository-surface`, `check-git-access`, `check-monitor-purity`, `check-workflow-shell-syntax`, `check-layer-enforcement`, `check-layer-negative`, `validate-root-layout` 전수 실행 및 `PASS: ... green (snapshot)` 확인.
  4. **무결성 게이트**: `make check-push-admissibility-integrity` PASS.

---

## §4. VS-LEAN-1 사전 관문 실측 판정: **REJECT (기각)**

4-Slice 계획의 Slice 4 사전 관문("`ax prove`의 추가 Lean 프로세스가 실제 시간에 기여하는 바를 실측하여 마이그레이션 비용을 정당화하지 못하면 슬라이스를 기각한다")을 실측으로 판정했다.

### 4.1 프로세스 기동 비중 실측 (3회 중앙값, `normalizeMaxWorkers` 265B 정리)

| 실행 항목 | `lake env lean --threads=1` | bare `lean --threads=1` |
|---|---|---|
| (a) `canonicalLeanKernelCheck` 단독 (`lean_kernel_boundary.nim:417`) | **306.7 ms** | 258.2 ms |
| (b) `captureKernelAxioms` (`#print axioms` probe, `:490-507`) 단독 | **306.3 ms** | 256.7 ms |
| (c) 단일 프로세스 통합 (정리 + `#print axioms`) | **306.8 ms** | — |
| 순수 기동 비용 (`#check Nat`) | 287.9 ms (93.9%) | 241.2 ms |

- **정리 1건당 절감 $\Delta = (a + b) - c = 306.2\text{ ms}$** (613.0 ms → 306.8 ms).
- `ax prove` warm 전체 실행 시간 중앙값 **6.49 s**(`logs/ax_prove_trajectory.jsonl` 7회 실측; 토폴로지·심볼그래프·IR 고정 비용 ~6.2 s 지배) 대비 $\Delta$ 비중 = **4.72%**.
- VKS 23개 커널 전체 재증명 시 총 절감 $\Sigma \Delta = 23 \times 0.3062\text{ s} = \mathbf{7.04\text{ s}}$.
- 인증서 검증 경로(`ax cert verify --kernel` / `reexecuteLean`)는 이미 단일 프로세스(`kernel_reexecution.nim:277-284`)이므로 검증 시점 절감은 **0 ms**다.

### 4.2 Receipt vNext 마이그레이션 비용 ($C_{\text{migration}}$)

- `receiptArtifactIdentity == leanSourceHash` 불변식에 결속된 핵심 신뢰 경계 파일 **9개**(`canonical_verification.nim`, `judgment_cas.nim`, `kernel_acceptance_authority.nim`, `lean_kernel_boundary.nim`, `cert_writer.nim`, `kernel_reexecution.nim`, `certificate_verifier.nim`, `lean_evidence.nim`, `cert_cli.nim` — 총 ~7,500 라인 중 불변식 직접 결속 77 라인) + 골든 테스트 **4개**(`test_s1a_lean_golden`, `test_d2_golden`, `test_judgment_cas`, `test_evidence_truth_boundary`) + Dual-Read/New-Write 영구 분기 복잡도.
- **판정**: $\Sigma \Delta = 7.04\text{ s}$(유닛당 306.2 ms, prove wall의 4.72%)는 9개 핵심 신뢰 경계 파일의 Receipt 계약 변경 및 Dual-Read 유지 비용을 정당화하지 못하므로, 승인된 계획의 관문 규칙에 따라 **VS-LEAN-1을 공식 기각(REJECT)**하고 4-Slice 중 코드/상태 변경은 3-Slice(VS-DEBT-1, VS-PUSH-1, VS-VKD-1)로 종결한다.
