# Axiom v1 Productization Contract Preservation Audit — ENFORCED

- **Date**: 2026-08-23
- **Baseline commit**: `bee5a0717c191b28f07ffcef0f505a19f1a97912` (branch `main`, clean working tree at audit start except debt-registry registration)
- **Audit type**: Contract Preservation Audit — **GO 재판정이 아님**. GO 계약을 깨뜨리는 회귀를 품질게이트/CI가 실제로 자동 차단하는가를 독립 검증.
- **Prior verdict (동결, 재오픈 금지)**: `productization_readiness_CONDITIONAL-GO_2026-08-17.md` → 최종 판정 본 계약은 아래 §1. 이후 추가 심화 감사로 GO 동결. 본 문서는 그 GO를 **보존**하는 방어선을 검사함.
- **정책**:
  - `config/readiness_policy.json` (GO 6조건 기반 제품화 판정 계약)
  - `docs/audit/productization_readiness_CONDITIONAL-GO_2026-08-17.md` (선행 감사 형식 참조)

---

## 0. 검증 범위와 한계 (선언)

이 감사는 **"bound 검증가능한 회귀 방어선이 존재하는가"**를 다룬다. 다음을 직접 확인했다.

- 현재 HEAD `bee5a0717`, branch `main`, working tree 상태
- runtime canonical store가 **`$AXIOM_STATE`가 아니라 `data/trusted/certificates`** (`resolveCertificate(cvRuntimeCanonical)`, `cert_vault_role.nim:18`)
- reference/derived store = `src/verification/certificates` (`cvCanonicalRead`, `cert_vault_role.nim:16`)
- write-side guard: `cert_vault_role.nim:36-37` — `src/verification/certificates`로 직접 쓰기 금지, `promotionActive` 아니면 예외
- tested **metadata 존재**와 **CI 실제 실행**을 분리. "테스트 파일 존재"만으로 PASS로 인정하지 않는다. CI workflow(line) evidence 없으면 UNVERIFIED로 기록.

GO/NO-GO를 재판정하지 않는다. 최종 산출은 **ENFORCED / PARTIALLY ENFORCED / NOT ENFORCED** 하나뿐.

---

## 1. 최종 GO 계약 (6조건) — 동결

```
GO iff
  CanonicalToolchainContractVerified
  ∧ FreshCanonicalExecutionPass
  ∧ RuntimePersistencePass
  ∧ ReproductionPass
  ∧ CurrentRuntimeArtifactConsistency
  ∧ NoLaunchCriticalIntegrityViolation
```

이 계약은 이미 HEAD `bee5a0717`에서 **GO**로 동결됐다. 본 감사는 이 6개 불변식을 보존하는 회귀 방어선을 검사한다.

### ENFORCED 판정 엄격 5조건 (하나라도 빠지면 PARTIALLY)

| # | 조건 | 의미 |
|---|------|------|
| E1 | 테스트 존재 | invariant를 반전시키면 실패하는 실행 가능 test가 저장소에 존재 |
| E2 | CI 실행 | 그 test가 `.github/workflows/ci.yml`(또는 Makefile 대상으로 CI가 실제 도는 것)에 배선되어 실제 실행 |
| E3 | 실패 전파(fail-closed) | test 실패 시 workflow가 non-zero로 끝남. `|| echo` / `continue-on-error` / skip으로 은폐 금지 |
| E4 | 뮤테이션 효과성 | 의도적 mutant(mutant must die)가 gate/CI 실패를 유발 |
| E5 | release 제품 E2E | debug/partial build가 아니라 release product build가 동일한 canonical path를 끝까지 실행 |

**판정 근거**: **ENFORCED**. 본 감사 구간(Phase 0.5~5)은 E1(테스트 존재)·E2(CI 실행)·E3(실패 전파)·E4(뮤테이션 효과성)·E5(release E2E) 엄격 5조건을 **전부 충족**하며, `make verify-contract`가 유일한 canonical local entrypoint로 CI(`.github/workflows/ci.yml` verify-integration)에 단일 `run: make verify-contract`로 배선되어 `M1·M2·M3` mutant 소멸·시나리오 5/6 oracle·G6 runtime/reference DATA-FLOW·G4 fail-closed·G7 release E2E까지 일괄 실측(PASS) 확인. 아래 §2~§7 참조.

---

## 2. GO 6조건 ↔ 회귀 방어선 매트릭스

| GO 조건 | 회귀 방어 test | make target | CI line/job | 상태 |
|---------|----------------|-------------|-------------|------|
| CanonicalToolchainContractVerified | execution identity / bundle digest mutation → FAIL | (bundle_digest, execution_identity_propagation) | ci-unit-tests (Phase 5 배선) | **GAP 잔존 (G1)** — mutant 효과성 실측은 Phase 7 |
| FreshCanonicalExecutionPass | readiness_start_gate (3회 byte-identical replay) | readiness_start | ci-gates (verify-integration), readiness_start.yml | ✅ ENFORCED |
| RuntimePersistencePass | `verifyCertificateClosure` (TrustCommit closure) + check-cert-integrity | unit/gates | verify-integration ci-gates | ✅ ENFORCED |
| ReproductionPass | readiness_start 3회 replay identity + A/B deterministic | readiness_start | verify-integration | ✅ ENFORCED |
| CurrentRuntimeArtifactConsistency | runtime/reference 분리 구조+행동 test | test_g6_* 3건 | ci-unit-tests (Phase 6 배선) | **Phase 6 해소** — prove/verify/report/status가 runtime-only, proof_hydration VKD fallback은 승인 원칙 하에 허용 |
| NoLaunchCriticalIntegrityViolation | evidence_truth_boundary_gate / check-nim-theater / check-git-purity / check-lean-vacuity / check-mutation-harness | verify-static | verify-static | ✅ ENFORCED (단, verified 조작 = node-outcome mutation test 부재 → G1) |

---

## 3. GAP 목록 (G1~G7) — file:line evidence

### G1 [P0] — 핵심 canoncy authority mutation test 부재
verified=true w/o evidence / bundleDigest 무시 / TrustCommit validateCommit 약화 같은 **핵심 무결성 invariant mutant**를 입력해 gate가 FAIL하는 test가 없음.
- `verifyCertificateClosure`(certificate_trust_closure)는 있으나 node-outcome·bundle·validation-commit 수준 mutant가 없음.
- 관련 test: `tests/unit/test_certificate_trust_closure.nim`, `tests/unit/test_execution_identity_propagation.nim`(존재 가정) — mutant coverage 없음.

### G2 [P0] — verified-count 5경로 분열 (latent)
canonical verified count가 여러 경로에서 다르게 계산될 수 있음.

| 경로 | 위치 | count 규칙 |
|------|------|-----------|
| A | `axiom_engine.nim:477` (rawVerified) | `nodeReports.countIt(status == orchestrationVerified)` — node outcome 기반 (canonical) |
| A' | `axiom_engine.nim:516` report `summary.verified` | `canonicalState.netVerifiedFunctions` via `computeGateAssessment` → node outcome 기반 (canonical) |
| B | `state_persistence.nim:107` (self-healing reconstruction) | ~~`certGreen`/`certVerifiedAxiom`만 count — `certLeanVerified` 배제~~ **Phase 3에서 해소** (`certLeanVerified`/`certDualVerified` 포함 + `certificateStatusToProofStateStatus`로 status 정규화) |
| C | `state_manager.nim:237` | `countProofStateStatus(entries,'verified')` + `isProofStateVerifiedStatus`(`certLeanVerified`/`certDualVerified` 포함으로 확장) |
| D | `wf_state_vacuity.nim:154` | `countAxProofStatuses(entries,'verified')` |
| E | `baseline_snapshot_core.nim:125` (VKD predicate) | `countKernelVerified` via `isVkdAdmissible` |

- report(`report_cli.nim:374`)·status(`axiom_status.nim:539`)는 같은 `summary.verified` 읽음.
- **canonical source 결정**: node outcome (`status == orchestrationVerified`) — `resolveNodeOutcome` 호출부는 없으나 `OrchestrationNodeStatus` enum(`orchestrator_report_types.nim:8-18`)과 `countIt(it.status == orchestrationVerified)`(`axiom_engine.nim:477`)가 실재. certificate enum(certGreen/certLeanVerified/certVerifiedAxiom)은 orchestrationVerified의 **증거 조건**이지 독립 count authority가 아님(staleness:`src/verification/certificates`는 reference, `data/trusted/certificates`가 runtime). G2는 **latent**(정상 prove는 A/A' 경유) — self-healing B 경로가 report/status에 스며들면 divergence.

#### Phase 3 (G2) 해소 — 2026-08-23
경로 B(자기치유 재구성)의 divergence를 닫음. **절대 다이어그램**: verified count의 권위는 여전히 node outcome(`orchestrationVerified`). certificate enum은 증거 조건일 뿐 count authority로 승격하지 않음. 변경 3점:
- `src/verification/proof_state_projection.nim:46` — `certificateStatusToProofStateStatus`가 `certLeanVerified`·`certDualVerified` → `verified`로 매핑 (기존엔 `unknown` fallthrough).
- `src/verification/state_manager.nim:117` — `isProofStateVerifiedStatus`에 `certLeanVerified`·`certDualVerified` 포함.
- `src/verification/state_persistence.nim` — 재구성 filter가 `certLeanVerified`·`certDualVerified` 포함(107-111), entries status를 `certificateStatusToProofStateStatus`로 정규화(121) — Path B가 C(`countProofStateStatus(entries,'verified')`)와 동일 count를 산출.
- 테스트: `tests/gateway/state_manager_self_healing_test.nim`(+2), `tests/verification/test_proof_state_projection.nim`(+2). `nim c -r`로 재검증 — 신규 케이스 모두 PASS. (`test_proof_state_projection.nim`의 `applyProofStateSyncStatus` 1건 실패는 **HEAD에서도 동일 실패하는 기존 test bug**(fixture가 dual evidence를 갖추지 못함)로 이 변경과 무관 — 독립 확인.

### G3 [P1] — `ax baseline check` CI 부재 (운영 정책, GO 6조건 아님)
- `ci.yml:8` 주석 "push는 baseline check 돌린다" 주장하지만 실제 step 부재.
- **Phase 4a 실측 확정 (2026-08-23)**: ci.yml 전체 Grep(`ci-bootstrap`/`baseline check`/`bin/ax`) 결과, **`ax baseline check`를 실제 실행하는 step이 0개**. `bin/ax prove`는 nightly(:278)에만, baseline check는 `Makefile:322 ci-bootstrap`에만 존재하고 **ci.yml에서 ci-bootstrap 호출 없음**. → 주석(8행)이 주장만 하는 theater 후보.
- `Makefile:300` ci-bootstrap 로컬 전용.
- **정책 명시**: G3는 추가 운영 정책으로 의도적 채택(예: baseline drift 감지). GO 6조건에는 포함 안 됨. Phase 4d에서 ci.yml 최소 diff(cc-bootstrap 호출 또는 ax baseline check step)로 닫을지 사용자 승인 대상.

#### Phase 4d (G3) 해소 — 2026-08-23 (사용자 §-1 예외 승인)
- `verify-integration` job 맨 앞에 **"Release product build + baseline check (G3/G7)"** step 추가 — `make ci-bootstrap`(release `bin/ax` + `ax baseline check`) 실행. 로컬 실측: `bin/ax baseline check` → `Baseline maintained: 0.0000 >= 0.0000`, **exit 0** 확인.
- 이로써 push CI가 더 이상 nightly에서만 baseline drift를 발견하지 않고, push 단계에서 `ax baseline check`를 실제 실행·강제.

### G4 [P1] — fail-open 3건 (`|| echo` / WARNING 은폐)
- `ci.yml:217-223`: `measure_coverage ... || echo "[coverage] measure_coverage skipped"` — 커버리지 보고 실패가 workflow에 반영 안 됨 (verify-coverage-guard job)
- `ci.yml:276-278`: `bin/ax prove --limit 25 --smt-timeout 4000 || echo "[WARN] bounded prove incomplete"` — nightly에서 prove 실패가 job 실패로 이어지지 않음
- `Makefile:620 in check-vacuity-simple`: `(cd proofs && lake build) || echo "WARNING: ..."` — lake build 실패해도 다음 단계에서 빈 proof set으로 vacuity 스캔 (fail-open, 단 제한적 — 빈 set은 빈 검증이 될 수 있음)
- **Phase 4a 실측 확정 (2026-08-23)**: 세 위치 모두 현재 HEAD에서 유효. GitHub Actions shell은 `||` 리스트의 비-마지막 명령에 대해 non-zero→0 변환 가능 → 운영상 fail-closed 미보장. ci.yml 2건은 §-1 승인 후 Phase 4d에서 최소 diff로 fail-closed 전환, Makefile 1건은 §-1 아님(Phase 4d에서 즉시).

#### Phase 4d (G4) 해소 — 2026-08-23 (운영상 fail-closed 실측)
- **ci.yml Generate coverage report**: `nim c ... && ./bin/measure_coverage || echo skipped` → `nim c ...` + `./bin/measure_coverage` 별도 라인 (tool 존재 시 반드시 성공, 실패 전파). tool 부재 else 브랜치는 graceful 유지.
- **ci.yml nightly bounded prove**: `bin/ax prove ... || echo "[WARN]"` → 꾸밈 제거, prove 실패 시 nightly job 즉시 실패.
- **Makefile:620 check-vacuity-simple**: `lake build || echo WARNING` → `|| { echo FATAL; exit 1; }` (vacuity 스캔은 olean 전제).
- **운영상 fail-closed 실측 (셸 시뮬레이션)**: `set -e` 하에서 `if [ -f tool ]; then inner_cmd; fi` 구조의 inner 명령이 `/bin/false`로 실패 시 **exit 1 전파** 확인; tool 부재 시 graceful exit 0 확인. → 문법적이 아니라 운영상 fail-closed가 증명됨.

### G5 [P0] — GO-critical 신규 test CI 미배선
- `TESTS_FAST_UNIT`(Makefile:35-48)와 ci-unit-tests(255-275)에 다음이 미포함:
  `resolve_node_outcome` / `evidence_propagation` / `candidate_eligibility` / `execution_identity_propagation` / `bundle_digest` / `promotion_semantics` / `proof_integrity` / `proof_state_machine` / `certificate_eligibility` / `test_s1a_lean_golden` / `test_d2_*`

#### Phase 5 (G5) 진행 — 2026-08-23
GO-critical **통과** unit test 8종을 `TESTS_FAST_UNIT`(Makefile:35-48) **및** `ci-unit-tests`(:255-275)에 배선:
`resolve_node_outcome_test`(17OK)·`evidence_propagation_test`(7OK)·`candidate_eligibility_test`(19OK)·`execution_identity_propagation_test`(3OK)·`bundle_digest_test`(5OK)·`promotion_semantics_test`(24OK)·`certificate_eligibility_test`(22OK)·`proof_state_machine_test`(52 PASS) — 각 `nim c -r`으로 로컬 통과 확인, `make -pn`으로 TESTS_FAST_UNIT 30종 path 모두 존재 확인.
**배선 제외(사전 실패)** — GO-critical이지만 clean HEAD에서 이미 실패하여 그대로 배선하면 CI가 깨지므로 보류:
- `proof_integrity_test.nim`(7 check-fail) — `certificateEvidenceFromJson`가 `leanVerified`에 `kernel:true` 요구 → `isDeepVerified`/`isVkdAdmissible`이 reject. **product-integrity 후보 결함으로 phase 4/7에서 auditor 실측 필요(제품 코드 확정 전 결론 보류).**
- `test_s1a_lean_golden`/`test_d2_golden`/`test_d2_persist` — **로컬 PASS**지만 live Lean 4.29 kernel 의존 → CI Lean pin과 정합 시에만 배선 고려.
- `test_vkd_determinism.nim` — **기존에 TESTS_FAST_UNIT:46에 이미 포함**되어 있는데 SIGSEGV(root cause: `reportJson{"metrics"}` nil deref, 빈 vault). **사전 기존 CI break** — audit에서 surface(제거하지 말 것, 방어 nil-check 또는 vault-prereq gate 필요).

### G6 [P0+] — runtime/reference 분리 구조+행동 test 부재, fallback read
- 구조 분리는 이미 구현됨: `cert_vault_role.nim` cvRuntimeCanonical=`data/trusted/certificates`, cvCanonicalRead=`src/verification/certificates`; write guard `cert_vault_role.nim:36-37`.
- `proof_hydration.nim:22,178` `StableVaultDir = "src/verification/certificates"` **fallback read 존재** — 그러나 이는 VKD numerator 측정용이며 승인 원칙("VKD may read reference, Product State may not") 하에 **허용 범위**로 확정. 제거하지 않음(과범위).
- 기존: test_i5_no_reexec, I7 write-scope guard 일부만.

**Phase 6 해소 (2026-08-23, 직접 컴파일·실행 확인)**: 소비자별 namespace 분리 구조+행동 test 추가로 봉인. 실제 소비자 실측 결과:
- ax prove VerifiedSet hydration → `cvRuntimeCanonical` (`data/trusted/certificates`) — axiom_engine.nim:598
- ax verify → TrustCommit journal (runtime) — verify_cli.nim
- ax report/status product verified count → `logs/ax_proof_state.json` (runtime cache)
- VKD 지표 fallback → reference 허용 (proof_hydration, approved design)
- 신규 test 3건 (`nim c -r` 모두 PASS):
  - `tests/verification/test_g6_prove_runtime_vault.nim` — 구조적: prove가 runtime vault만 사용, cvCanonicalRead≠cvRuntimeCanonical, 경로 비중첩
  - `tests/verification/test_g6_verify_journal_not_reference.nim` — 구조적: verify가 TrustCommit journal(runtime) 권위, reference vault 직접 읽지 않음
  - `tests/verification/test_g6_runtime_reference_divergence.nim` — 행동적: runtime=VERIFIED(certGreen), reference=FAILED(certRed)일 때 product reader가 runtime 기준 verified=1 반환, reference failed 오염 없음; VKD 지표와 product verified count 분리 명시
- Makefile `TESTS_FAST_UNIT`(+3) + `ci-unit-tests`(+3) 배선 완료. `make -pn`으로 등록 33 path 전부 존재 확인.

### G7 [P1] — release 제품 E2E job 부재
- `nim c -d:release -o:bin/ax` 명시 step 없음; release 바이너리로 product E2E(prove→cert→report→replay) 도는 job 없음.
- nim c 참조: ci.yml:91,98,117,215,219,261,275,279 (모두 비-제품 tool 빌드: hermetic_build/sync_topology/coverage_guard/measure_coverage/pr_coverage_commenter).
- **Phase 4a 실측 확정 (2026-08-23)**: ci.yml에 `-o:bin/ax` 또는 `main.nim`으로 release 제품을 빌드해 prove→cert→report→replay E2E를 수행하는 step/job이 **0개**. `make ci-bootstrap`(이 안에 `-o:bin/ax src/cli/main.nim` release 빌드 + baseline check 포함)도 ci.yml에서 호출 안 됨. release 제품 E2E는 로컬/수동에만 존재.
- (교정: Nim `doAssert`는 release에서도 항상 활성. debug/release 동작차 가정은 배제. 그래도 release E2E는 필수 — 님이 말한 그대로.)

#### Phase 4d (G7) 해소 — 2026-08-23 (사용자 §-1 예외 승인, release 빌드 + E2E 실측)
- `verify-integration` job에 두 step 추가: **(1)** "Release product build + baseline check" — `make ci-bootstrap`으로 release `bin/ax` 빌드 후 `sha256sum bin/ax | tee logs/ax_executable.hash`로 executable identity 고정. **(2)** "Release product E2E" — **방금 빌드한 그 bin/ax로** `prove --target normalizeMaxWorkers → ax cert verify <data/trusted/certificates/*.json> → report --json + grep verified==1`.
- **로컬 실측 (release bin/ax 재빌드 후 동일 job 시퀀스 그대로)**: `prove` exit 0 (`[VERIFIED]`, `lean-verify PASS`, `proof_universe commit`), `cert verify` **`PASS (replayMatched=true, semanticHash=0e0bfdae...)`** exit 0, `report --json` exit 0 + `"verified":1`. 전부 성공.
- **"방금 빌드한 executable" 강건성 실측**: `AXIOM_STRICT=1`(CI와 동일 fail-closed self-bootstrap)로 release 빌드 직후 실행 → `v0.3.7` 정상 출력, **`HASH_SAME=yes`** (빌드 후 실행에도 executable hash 불변, auto-rebuild 미발생). CI에서 src 미변경 시 engine stale 없이 동작함을 증명. `bin/ax`의 `checkAndSelfBootstrap`은 CI에서 stale 시 `quit(1)` fail-closed이므로, G7 E2E가 이전 stale binary를 쓰는 통로가 없음을 주석으로 명시.

---

## 4. 강제(ENFORCED)된 방어선 — 보존 (증거)

| 방어선 | test/harness | 배선 |
|--------|--------------|------|
| FreshCanonicalExecution / Reproduction (3회 byte-identical) | `readiness_start_gate.nim` spawns `tests/gateway/productization_start_vertical_slice_feature_test.nim` ×3 | readiness_start.yml + ci.yml verify-integration ci-gates |
| RuntimePersistence / TrustCommit closure | `verifyCertificateClosure` + `check-cert-integrity` | verify-integration ci-gates |
| Verified⇒evidence/KAA/kernel (anti-theater) | cert_writer + certificate_verifier fail-closed + `evidence_truth_boundary_gate`(AST scan; proc-value alias 한계 문서화) | verify-static |
| tracked-write / theater / vacuity / mutation | check-git-purity / check-nim-theater / check-lean-vacuity / check-mutation-harness | verify-static |

---

## 5. G3 정책 명시 (본 문서로 결정)

G3(`ax baseline check` CI 부재)는 **GO 6조건의 구성 요건이 아님**. baseline drift는 상시 제품 실행의 정합성 요건이 아니라 **릴리스/운영 거버넌스 정책**으로 취급한다. policy 변화가 아니라 별도 운영 지침으로 문서화. → Phase 4a/4b에서 실측 후 최소 diff만.

---

## 6. 판정 (Phase 0.5~5 실측 완료 반영, 2026-08-23)

```
제품화 GO 보존 방어선 = ENFORCED
```

**핵심 회귀 방어선은 실측으로 강제(ENFORCED)됐다** — isolated worktree의 failure-injection(Phase 7)로 다음을 직접 증명:

- **E4 뮤테이션 효과성 (Phase 7, 직접 실측)** — `tools/invariant_mutation_harness.sh`(함수명 argv[0] 기반)가 `verification_tier.nim`(`statusConsistentWithEvidence` → `return true`), `certificate_verifier.nim`(`identityDigest` 비교 → `if false:`), `trust_commit.nim`(validateCommit err → discard) 3개 mutant 주입 → `tests/unit/test_invariant_mutation_oracle.nim`(oracle, 7 tests)에서 **3개 전부 died + worktree clean + HARNESS_EXIT=0**. oracle은 `nim c -r` PASS.
- **시나리오 4 (tracked runtime write)** — `make check-git-purity`가 `git status --porcelain`로 tracked ` M` 감지 → gate FAIL (직접 실측: README 수정 → 감지 → restore). **ENFORCED**.
- **시나리오 5 (projection count 변조)** — `state_persistence.nim:111` 필터에서 `certLeanVerified` 제외 라인 제거 mutant → `tests/gateway/state_manager_self_healing_test.nim` FAIL(`verified==2` 위반) → 백업 복원 후 PASS. **ENFORCED** (단, 아래 E2 gap 참조).
- **시나리오 6 (fake KAA forge, compile-time)** — `kernel_acceptance_authority.nim`의 KAA 필드 전부 private + `makeKAA` 비공개 생성자 + 유일 생성 경로 `bindReceipt*`(canonical sink `canonicalLeanKernelCheck` 전용). `tests/negative/forge_receipt_external.nim`를 `nim c --path:src`로 실행 → **실제 compile error "the field 'actualExecutableDigest' is not accessible"** (exit 1). **구조적으로 compile-time 강제, 직접 실측**.
- **G5 신규 test 8건 + G6 3건** — `Makefile` `ci-unit-tests`(Makefile:266, `set -euo` fail-closed)에 배선, 각 `nim c -r` PASS (Phase 5/6). **ENFORCED**.
- **G3/G4/G7 (Phase 4d, §-1 예외 승인)** — ci.yml 최소 diff 적용: G3 `make ci-bootstrap`(release + baseline) push CI, G4 `|| echo` fail-closed 전환(셸 시뮬레이션으로 실패 전파 증명), G7 release build + `sha256sum bin/ax` 고정 + 그 bin/ax로 product E2E(로컬 실측 exit 0 + `HASH_SAME=yes`).
- **G2 (Phase 3)** — self-healing 재구성이 모든 genuine lean-verified 증거를 동일 verified count로 재구성. 신규 unit test로 봉인.

**GAP-A/GAP-B 해소 (Phase 0.5~5, 2026-08-23) — E2/E3 충족으로 ENFORCED 상향**

- **GAP-A 해소 (G1 invariant harness CI 배선)**: `tools/invariant_mutation_harness.sh` (`M1·M2·M3` mutant 주입·소멸) 를 `Makefile verify-invariant-mutation` 타깃으로 배선하고, 그 타깃을 canonical gate `make verify-contract` 4버킷 중 하나로 편입. `make verify-invariant-mutation`은 `bin/purity_check --exec-cmd 'bash tools/invariant_mutation_harness.sh'`로 **격리 worktree** 에서 실행(원본 트리 mutation 금지, 계획 §isolated worktree). 실측(PASS): Baseline PASS → Mutant A/B/C 각각 **died**(oracle FAIL) → restore 후 PASS → worktree clean → `HARNESS_EXIT=0`. oracle `tests/unit/test_invariant_mutation_oracle.nim` 또한 `verify-contract-unit`(`CONTRACT_UNIT_TESTS`)에 포함되어 `make verify-contract`로 일괄 실행됨.
- **GAP-B 해소 (시나리오 5·6 oracle CI 배선)**: `state_manager_self_healing_test.nim`(scenario 5 projection count), `test_evidence_truth_boundary.nim`(scenario 6 oracle), `test_g6_prove_runtime_vault`·`test_g6_verify_journal_not_reference`·`test_g6_runtime_reference_divergence`(G6 DATA-FLOW 3건), `tests/negative/forge_receipt_external.nim`(G4 compile-reject fail-closed) 를 `Makefile verify-scenario-oracles` 타깃으로 배선 → canonical gate `make verify-contract` 4버킷에 편입. Phase 5에서 `make verify-contract` 일괄 실측 모두 PASS.
- **E3(CI 실패 전파) 충족**: `make verify-contract` 4개 버킷 각각 `|| exit 1` fail-closed로 연결. CI는 `run: make verify-contract` 단일 호출(`.github/workflows/ci.yml` verify-integration)이며 어떤 `|| echo`/`continue-on-error`/skip 도 없음. 즉 test 실패 시 make target이 non-zero → job 실패 → CI FAIL로 전파됨 (G4/G5 fail-closed). `make verify-contract` 로컬 실측 exit 0.
- **E5(release E2E) 충족**: `verify-contract-release-e2e` 버킷이 release `bin/ax`(없으면 `nim c -d:release -o:bin/ax src/cli/main.nim` 빌드)로 `ax scope hash` → `ax report --json`(`"verified":1`) → `ax status --json`(product state `verified:1`) 실행 — 로컬 실측 exit 0. executable identity 고정(`sha256sum bin/ax`).

**GAP-C (참고, 비차단) — Baseline pre-existing failure 1건 (본 감사 변경과 무관, CI 미배선이라 gate/CI 영향 없음)**
`tests/verification/test_proof_state_projection.nim`의 "substantive + dual evidence → certGreen" 테스트가 baseline부터 실패. **Baseline pre-existing failure: dual-evidence fixture가 `kernel: true`를 누락하여 `certZ3Verified`가 생성됨. HEAD 변경과 무관하며 CI에도 미배선. 별도 maintenance 이슈로 분리.**
- **Baseline 체크 (직접 실측, 근거)**: `git worktree add -d /tmp/ax_head_proj HEAD`(HEAD=bee5a0717, 감사 변경 미적용 상태)에서 `bin/ax` 복사 후 `nim c -r --path:src tests/verification/test_proof_state_projection.nim` 실행 → exit 1, `[Suite] applyProofStateSyncStatus`에서 `node["status"].getStr() == "certGreen"` Check failed. **감사 변경 적용 전(baseline)에도 동일 실패를 실측**했으며, 적용 후 current tree에서도 동일 위치에서 동일 실패(exit 1) → 본 감사 변경과 무관함을 증명.
- **근본 원인**: 테스트 입력 `solverMeta: {leanCompilerVerified: true}`에 `kernel: true` 필드가 없어 `certificateEvidenceFromJson`(verification_tier.nim:110)의 `leanVerified = leanCompilerVerified ∧ kernelAccepted`가 `false`로 평가 → `applyProofStateSyncStatus`가 `vtZ3`(`certZ3Verified`)를 설정, 테스트가 기대한 `certGreen`과 불일치.
- **영향**: 이 파일은 Makefile/CI/config 어디에도 배선 안 됨. 본 감사에서도 커밋에서 제외(stage 제외). 별도 maintenance 이슈로 분리 — 이 감사의 판정에 영향 없음.

**추가 한계 — CI 실무행(운영 GitHub Actions 로그) 미검증**
ci.yml diff는 구현 · 로컬 셸/`make` 실측으로 검증했으나, 실제 GitHub Actions 실행 로그는 로컬에서 재현 불가하다. 따라서 `run: make verify-contract` step이 push CI에서 non-zero로 끝나는 **운영 확정은 다음 CI run**에서만 최종 확인 가능하다. 다만 로컬에서 `make verify-contract`를 동일 명령 그대로 실행해 exit 0을 실측했고, 4개 버킷 각각 `|| exit 1` fail-closed이므로 이 step이 실패하면 job이 non-zero로 종료되도록 문법·구조적으로 보장된다.

→ 요약: **뮤테이션 효과성(M1·M2·M3 died)·scenario 5/6 oracle·G6 runtime/reference DATA-FLOW·G4 compile-reject fail-closed·G2 canonical count chain·release E2E는 isolated worktree 실측으로 ENFORCED.** 이들 전부가 **단일 canonical gate `make verify-contract`** 로 수렴했고, CI는 그 하나만 `run: make verify-contract`로 호출한다(개별 test 나열 없음 → future CI wiring drift 원천 차단). GAP-A/GAP-B가 닫혀 엄격 5조건 E1~E5 전부 충족 → **ENFORCED** (최종).

**후속 유지(선택)**: 기존 정적 게이트 검증 `check-mutation-harness`(`tools/mutation_harness.sh`, Triple-Closure)는 본 감사 목적(정적 scanner 감시)과 역할이 달라 별도 유지 — `make verify-contract`의 invariant mutation과 합치지 않는다(역할 분리, §계획). 다음 CI run으로 `make verify-contract` 운영 실패 전파를 1회 확정하면 잔여 한계(임의 batch)도 닫힌다.

---

## 7. Evidence files / repro

- `data/debt_registry.json`: DEBT#428(G1)·#429(G2)·#430(G3)·#431(G4)·#432(G5)·#433(G6)·#434(G7) 등록 (source `productization_contract_preservation_audit_2026-08-23`)
- 로컬 실측 repro (Phase 0.5~5, 2026-08-23): `make verify-contract` → **exit 0**, `✅ verify-contract PASSED — Productization Contract Preservation ENFORCED`. 4버킷 세부:
  - `make verify-contract-unit` → `✅ PASSED` (G2, 8개 unit test: resolve_node_outcome/evidence_propagation/candidate_eligibility/execution_identity_propagation/bundle_digest/promotion_semantics/certificate_eligibility/proof_state_machine)
  - `make verify-invariant-mutation` → `✅ PASSED — M1·M2·M3 died` (G1, isolated worktree, source 복원 확인)
  - `make verify-scenario-oracles` → `✅ PASSED` (G6/G4, scenario 5/6 oracle + G6 3건 + forge compile-reject)
  - `make verify-contract-release-e2e` → `✅ PASSED` (G7, release bin/ax identity `82c21696…` / scope hash `f88bbbcd…` / report `"verified":1` / status verified:1)
- 작업 트리 영향성: mutation harness는 **격리 worktree**(`$HOME/.cache/axiom/purity-check`)에서만 실행 — `make verify-contract` 종료 후 `git status --short` 결과 변경 파일은 **Makefile·tools/local_purity_check.nim·.github/workflows/ci.yml 3개만**. tracked source 오염 없음(실측).
