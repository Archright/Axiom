# 결정론적 Evidence DAG 계약 (Verification DAG Contract)

> **종류**: 계약 사양 (Contract SSOT). v1 CI Optimization Audit(2026-08-31)과 4차 피드백 검증을 거쳐 확정된 아키텍처 계약.
> **작성일**: 2026-08-31.
> **상태 (CI=0)**: 이 계약의 대상인 CI 최적화 프로그램은 CI=0 cutover(2026-09-20)로 종료 —
> GitHub Actions 워크플로·러너 인프라 제거. evidence-DAG 모델/계약 선언은 보존된 설계 기록이며,
> 실행 substrate(GitHub Actions)는 더 이상 존재하지 않는다.
> **근거**: CI Optimization Audit(gh-run 실측 9 runs, job 로그 검증) · 외부 공식문서 검증(GitHub Actions, Bazel, Turborepo, Nix, TUF, in-toto — Context7, 2026-08-31) · 코드베이스 실증 6종(공유 state, 기존 원시형, merge-boundary, identity closure, host-global state, terminal accounting).
> **상위 정렬**: P2 Work Unit 모델·불변식·skip 사다리(원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제 — 보존된 ADR-0017이 P2 참조본) — 본 계약은 P2를 **대체하지 않고 위에 적층**한다(§13).
> **§-1 주의**: 본 계약의 Phase 2 이상(`.github/workflows/ci.yml` 구조 변경)은 human architect의 명시적 승인이 필요했다. 본 문서는 Phase 0 산출물이며, 이 자체는 어떤 구현도 승인하지 않는다. (ci.yml은 CI=0 cutover로 삭제됨)

---

## 1. 목적·범위

Axiom CI의 authoritative object를 "CI job의 통과 여부"가 아닌 **VerificationKey로 식별되는 immutable Evidence와 그 dependency DAG**로 전환하는 것을 확정된 설계 방향으로 채택한다. GitHub Actions는 이후 verification DAG를 실행하는 worker/transport substrate이다.

- **범위**: 내부 검증 엔지니어링 역량 (운영자/CI 도구). v1 제품 표면을 확장하지 않는다(P2 §1.2와 동일 판단 기준, `docs/spec/productization_contract.md:21`).
- **비목표**: 제로베이스 planner/CAS 신규 구축, job 내부 병렬화(`AXIOM_PROVE_WORKERS`, z3_pool SIGSEGV root-fix 전), GHA cache를 결과 저장소로 사용.

## 2. 정의 — Authoritative Object의 사슬

```
Source → Input Closure → Verification Node → Immutable Evidence
       → Evidence Dependency DAG → Admission
```

- **Immutable Evidence**: 특정 NodeIdentity에 귀속된, 내용 해시로 식별되는 검증 결과. CI run과 독립적으로 존재한다.
- **Evidence DAG**: Evidence 간의 실제 데이터 의존 그래프. `needs`/workflow 토폴로지와 **동일하지 않다** — job 토폴로지는 substrate의 편의 사상일 뿐이다.
- **Admission**: "이 commit에 대해 필요한 evidence가 모두 존재하고, 결정론적으로 유효하며, Merge-Boundary Protocol에 binding되어 있는가?"의 최종 판정. `docs/agents/operations.md` Merge-Boundary Protocol의 4계층에서 **PR checks 계층의 목표 상태**이다.

## 3. NodeIdentity와 VerificationKey

**NodeIdentity는 4-tuple이다. CI job이 아니며, `bin/ax` 해시 단독도 아니다.**

```
NodeIdentity = ( NodeInputClosureDigest,     -- transitive import closure + 선언 입력
                 NodeExecutorDigest,          -- node별 실행기 구성 (자체 빌드 binary + 사전 빌드물 + shell 논리)
                 NodeConfigDigest,            -- computeBuildEnvHash/envHash 계열
                 NodeEvidenceContract )       -- 선언 산출물·evidence 스키마 계약
```

- 같은 입력·실행기라도 **선언된 산출물/evidence 계약이 다르면 다른 node**이다.
- `VerificationKey(N) = H(NodeIdentity, UpstreamEvidenceClosure)` — 소비하는 상위 evidence manifest digest들을 포함한다.
- **closure 완전성 계약이 identity에 선행한다**(Nix derivation 모델: identity = inputSrcs+inputDrvs 완전 closure의 해시). closure 정의는 §4의 resolution 경로가 규정한다.
- **현실 정합**: 기존 키는 자기 파일+config-surface만 커버한다(`src/core/gate/gate_cas.nim:48-63`, `src/cli/precompile_gates.nim:213-227`) — `src/core/**` 변경 시 무효화가 전무한 **stale-gate-binary hazard**(DEBT#446이 동형 한계 문서화). `computeTransitiveHash`(src/core/gate/transitive_hash.nim:290-318) 프리미티브가 존재하며 본 계약은 이것의 기본 경로 연결을 규정한다(Phase 1).
- executor는 node마다 다르다(예: verify-contract = bin/purity_check + 10개 테스트 binary + bin/ax; ci-gates = bin/gate_hook + 3개 gate runner; test-gateway = 자체 컴파일 binary) — 단일 binary 해시로 전체 node identity를 대표하는 것은 금지이다.
- **`ciGeneration`은 NodeIdentity 성분이 아니다**: `.github/workflows/` 토폴로지 세대(AGENTS.md §2.5 cutover 생성물 — `docs/agents/ci_epoch_cutover.md`)의 번호를 VerificationKey·NodeIdentity·evidence manifest digest에 결합하는 것은 금지한다 — 컷오버 세대 번호가 cache key나 verdict identity에 스며들 수 없어야 한다. 실행 의미론 축의 `executionEpoch`은 정반대 성질(identity 성분)이므로 두 명칭을 구분해 쓴다 — 정본: `execution_accounting_contract.md` §15.4.

## 4. ClosureResolution — typed failure

**identity 계산 결과 자체는 2-상태 타입이다. empty string은 의미론적 sentinel로 계약화하지 않는다.**

```
ClosureResolution = Resolved(digest) | Unresolved(reason)
```

- `Resolved(digest)` → VerificationKey 계산 가능 → lookup/reuse 허용.
- `Unresolved(reason)` → VerificationKey 없음 → lookup/reuse 금지 → **반드시 실행**.
- **"정상 계산 후 cache miss"(A)와 "키 계산 불가"(B)는 계약 수준에서 항상 구별된다.** 현재 구현은 이 둘을 ""로 수렴시킨다 — gate_cas.nim에서 ""는 최소 6개 서로 다른 의미(파일 부재 :24, 폴백 :35-42, 입력 불충분 :54, CAS miss :88/:102/:130/:300)로 오버로드되어 있다. 구현의 empty-string 오버로드는 **구현 세부**이며 계약이 아니다.
- **전환 규칙**: Phase 1에서는 ""→CAS miss→재컴파일을 안전한 과도기 경로로 허용하되, Unresolved는 반드시 **reason과 함께 기록**되어 Resolved-miss와 데이터 수준에서 구별 가능해야 한다. 그렇지 않으면 Phase 5/6의 reuse 계층 확장 시 상태 재구별이 불가능해진다.

## 5. Fail-closed reuse

- `Unresolved`인 node는 skip/재사용 불가 — 항상 실행한다. 이것이 fail-closed reuse의 정확한 구현이다(Bazel 원칙: "키에 모든 필드를 해시하라, 빼놓으면 나중에 값비싼 디버깅을 낳는다").
- **캐시는 재사용이지 재현이 아니다(reuse ≠ reproduction)**: cache hit은 선행 결과의 재사용이며 그 실행 경로에서 fresh execution이 발생하지 않는다. reuse가 **authoritative**가 되는 조건은 현재 문맥에 대해 **per-read 재검증**된 경우뿐이다(5조건 + fail-closed). 이 용어 구분의 정본 정의는 `execution_accounting_contract.md` §15.0·§15.3이며, 본 계약은 이를 재진술하지 않고 evidence/admission 계층에 적용만 한다.
- **negative half는 유지된다**: 캐시는 가속일 뿐 **증거가 아니며 판정 입력도 아니다**(J3 — `docs/spec/github_delegation_residuals.md:7`). 이는 "캐시가 실행-의미론 입력이 아니다"는 주장이 **아니다** — 캐시가 검증 의미론을 바꿀 수 있는 경로가 판정 대상이다(`ci_optimization_tcb_judgments.md` §3.1).
- **금지된 패턴(기존 결함)**: `computeTransitiveSourceHash`(gate_cas.nim:31-42)의 single-file 강등 폴백("Falls back to single-file hash on any error (graceful degradation)")과 `computeCompositeLockHash`(src/core/gate/gate_memo.nim:263)의 empty transitiveHash 무음 수용 — 둘 다 "불완전한 키로 재사용"을 허용하는 unsound 경로이다. Phase 1에서 제거 대상이며, debt registry에 등록 후 수정한다(자동 침묵 수정 금지).

## 6. Terminal Accounting — 최종 Admission invariant

**`ExpectedNodes == AccountedNodes`는 logger 기능이 아니라 최종 Admission invariant이다.**

```
NodeResult = ExecutedSuccess(evidence)
           | ExecutedFailure(reason, evidence?)
           | NotExecuted(reason)
```

- Admission은 기대 node universe에 대해 ExpectedNodes == AccountedNodes를 필수 검사로 수행한다. 누락 증거는 NotExecuted로 분류되며 **admission FAIL**이다 — in-toto 표준 모델(기대 subject의 attestation 부재 → reject)을 따른다.
- 기존 `.axiom/gate_history.jsonl` 스키마(`src/gate/utils/gate_run_logger.nim:36-58`: pass/fail/skip/timeout/cached + RunSummary 카운트)는 **descriptive**하며 완전성 강제가 없다. 스키마 확장(NodeResult 필드)은 **transport**일 뿐이며, 불변식 자체는 admission predicate(`src/cli/merge_cli.nim:94-135` `MergeAdmissible` 확장)에 존재한다.
- 선언: "Generated = TerminallyAccounted"(WP4-k)라는 기존 선례는 리포에서 확인되지 않았다(grep 0건). 본 원칙은 본 계약에서 신설되며, 가장 가까운 기존 패턴은 readiness_evaluator의 `classifyOutcome`(NOT_RUN/UNKNOWN → UNRESOLVED fail-closed, `tools/readiness_evaluator.nim:676-684`)이다.

## 7. Node vs Execution Group

- **Node** = 독립적으로 evidence를 산출하고 admission 판정이 가능한 실행 단위.
- **Execution Group** = 실제 데이터 의존 때문에 하나의 스케줄 단위로 묶인 node 집합. `verify-contract → verify-contract-release-e2e`(내부 의존: `logs/ax_proof_state.json`)는 group이며, **별도 workspace로 분해하지 않는다**(shared-state hazard, `Makefile:302`).
- group도 node별 evidence를 남겨 이후 개별 frontier 대상화를 유지한다.

## 8. Validity ≠ Freshness

- **Validity** = content/identity 대조. verification 결과의 유효성은 시간 경과가 아니라 identity 일치로 판정한다(올바른 기존 선례: `tools/stale_cert_gate.nim` — sourceHash content 대조).
- **Freshness** = liveness/정책 레이어(TUF 모델: `expires`는 메타데이터 liveness 정책, 내용 유효성은 해시 대조). `defaultFreshnessDays: 30`(`config/readiness_policy.json:280-282`)은 정책 파라미터로 유지하되 verification 유효성 조건이 아니다.
- **기존 결함(해소 대상)**: `tools/readiness_evaluator.nim:280` — 만료가 evidence invalid → UNKNOWN → 임계 invariant NO-GO로 흐른다(주석 "time only affects validity, never the verdict directly"와 실제 데이터 흐름 상반). Phase 4에서 정책 레이어로 격리한다.
- 어떤 gate도 **시간 경과를 verification 결과의 pass/fail 조건으로 추가하는 것을 금지**한다.

## 9. 병렬화 안전성 3계층

DAG 병렬화의 안전성 선언은 다음 3계층 증명 위에서만 유효하다:

1. **Workspace write-set** — 2026-08-31 실측: 8 target의 write-set 교집합은 2쌍뿐(verify-contract↔e2e-full은 nested, verify-all↔ci-gates는 동일 workspace 한정)이며 GHA job 분리(workspace 격리)로 소멸한다.
2. **Host-global state** — `$HOME/.nimble`, `~/.choosenim`, `~/.elan`, `~/.cache/nim` 등은 host-persistent 공유 상태이며, **flock per-host singleton(`tools/ci/runner/jit_supervisor.sh:67-68`)이 load-bearing invariant**이다(원 근거 `docs/spec/self_hosted_ci_migration.md:154-161`은 CI=0 cutover, 2026-09-20로 삭제 — 러너 인프라 제거로 해당 singleton도 소멸). 유일한 실제 동시성 race는 GitHub-side actions/cache save였으며 cache-key-prefix 분리(`axiom-toolchain` vs `axiom-toolchain-readiness` vs `axiom-canary`)이 좌표 메커니즘이다 — **prefix 분리는 불변식이다** (CI=0 이후 로컬 실행에도 유지).
3. **Network/service** — nimble/choosenim/elan/z3 다운로드·GitHub API(fatal), hetzner metadata(non-fatal) 등 node별 네트워크 의존을 evidence 계약에 기록한다.
4. **경로 소유권** — `~/.axiom/`(`src/cli/gate_admin.nim:23`, host-global)과 `.axiom/`(workspace-local)은 별개 저장소다. 게이트·도구가 어느 쪽에 기록하는지는 node evidence 계약이 명시해야 하며, host-global 기록은 flock singleton(위 2) 하에서만 안전하다. Phase 1의 소유권 정리 대상이다.

## 10. Evidence Manifest 형식

- per-node evidence manifest는 in-toto Statement v1 호환 형식을 채택한다: `subject = {nodeId, digest}`, `predicateType = axiom verification result`, `predicate = {NodeIdentity, conclusion, NodeResult, ClosureResolution 상태, provenance: commit/head/merge-group SHA들, UpstreamEvidenceClosure digests}`.
- 직렬화: RFC 8785 canonical JSON — 기존 `src/verification/canonical_certificate_payload.nim` 단일 직렬화기를 재사용한다. **신규 해시 체계의 신설은 금지**이며 VerificationKey는 §3대로 기존 원시형(scopeHash, envHash, BootstrapImplementationDigest, cert identityDigest 계열)의 조합이다.
- 저장 분리: GHA artifact = run 내 전송/집합 · GHA cache = 가속 전용(evictable) · durable CAS = `.axiom/cache` 확장(gate_cas.nim 재사용). manifest는 `build/`, `.axiom/`, `logs/` 영역에만 기록한다(git-tree purity check 보호; 원 순수성 앵커 `ci.yml:155-168`은 CI=0 cutover, 2026-09-20로 삭제).
- SHA는 provenance 필드일 뿐 identity가 아니다 — commit/head/merge-group SHA는 이벤트마다 달라진다(GHA 공식: pull_request도 merge-simulated SHA, merge_group은 큐 전용 임시 merge commit; 리포 내 SHA 조정 로직은 0줄). **ADR-0027 정합 (2026-09-29)**: 큐 경유 후보 인증의 이벤트 분기 폴백(`pull_request.head.sha || merge_group.head_sha || github.sha` — ADR-0027 P2)은 **소스 선택(source selection)**이다 — 이벤트별 정직한 head 필드를 후보 정체성으로 고르는 것이며 SHA를 유도·변형·조정하지 않는다. merge_group의 head_sha = GitHub의 "큐 전용 임시 merge commit" ref 값이고 그 값 자체가 후보 정체성(prNumber := 0, P1)이므로 "리포 내 SHA 조정 로직은 0줄"은 그대로 성립한다.

## 11. Phase 매핑·적용 순서

| Phase | 내용 | 전제 |
|---|---|---|
| 0 | 본 계약 동결 (문서 전용, 구현 0건) | — |
| 1 | node purity/closure 정리: debt registry 등록(stale-gate-binary hazard, fallback-reuse+"" 오버로드), 폴백 제거+typed resolution 도입(과도기 ""→miss 허용하되 Unresolved reason 기록), NodeExecutorDigest/NodeEvidenceContract 코드화, host-global 안전성 문서화, 인프라 정상화(pool·cache key·.elan) | Phase 0 |
| 2 | 실제 CI DAG 분할 (ci.yml 수정 — architect 승인 하; CI=0 cutover, 2026-09-20로 해당 경로 소멸). Edge = 실제 handoff만. Fan-in 집계 job(W-unit 커버리지) | Phase 0, 1 |
| 3 | Immutable Evidence Contract (§10 manifest) | Phase 2 |
| 4 | Evidence-based Admission Contract (§6 invariant, §8 경계 분리) | Phase 3 |
| 5 | Frontier Reuse — **lookup은 Resolved(digest) node에만 허용** | Phase 4 폐쇄 + 결정론 입증 |
| 6 | 장기 CAS/remote reuse 확장 | Phase 5 결과 |

- **reuse는 admission의 특수 최적화**이지 별개 correctness layer가 아니다 — Phase 4 폐쇄 전 frontier reuse를 착수하지 않는다.
- `src/core/**` 1파일 변경 → 해당 node CAS 무효화 확인, closure 강제 실패 시나리오에서 재실행 + Unresolved(reason) 기록 확인이 Phase 1의 수용기준이다.

## 12. 금지 사항

- ""를 의미론적 sentinel로 계약화 · 불완전한 키로 fallback reuse · **CI 컷오버 세대(`ciGeneration`) 번호를 evidence/admission identity에 결합** · 제로베이스 planner/CAS 구축 · `AXIOM_PROVE_WORKERS>1`(SIGSEGV root-fix 전) · GHA cache를 evidence store로 사용 · ci.yml 무승인 수정(CI=0 cutover로 ci.yml 자체 소멸) · verify-contract↔e2e-full 별도 workspace 분해 · 존재하지 않는 선례("WP4-k") 인용에 근거한 설계 · 시간 기반 validity 조건 신설 · contract freeze 이전의 구현 착수.

## 13. 기존 문서와의 관계 (P2와의 정합)

- **P2의 Work Unit 모델(§2), 불변식(§4: affected/reusable), skip 사다리(§5), ExecutionIdentity(§7.3: `H(InputIdentity + ExecutionContractDigest + BundleFingerprint)`), canary equivalence(§9)는 유지된다.** (원 anchor `docs/spec/incremental_ci_contract.md`는 CI=0 cutover, 2026-09-20로 삭제 — 보존된 ADR-0017이 P2 계약 참조본)
- 본 계약의 차이(적층):
  1. P2의 WorkUnit이 **계산 단위**라면 본 계약의 Node는 **evidence/admission 단위** — NodeEvidenceContract가 추가된다.
  2. P2 §4.2 `reusable(U)`는 계산 재사용 불변식이고, 본 계약은 그 **admission 계층 선결조**(`ExpectedNodes == AccountedNodes`)와 **resolved/unresolved 구별**을 추가한다.
  3. P2 §7.3의 ExecutionIdentity는 InputIdentity+Contract+Bundle의 조합이지만 transitive import closure를 기본 경로에 포함하지 않는다 — 본 계약 §3이 그 갭을 닫는다.
  4. P2 §5.5 BaseRunIdentity의 freshness는 정책 레이어로 격리된다(§8).
- 충돌 시: 본 계약(verification_dag_contract.md)이 evidence/admission semantics의 SSOT이고, P2는 증분 계산 모델의 SSOT이다.

---

## 14. Phase 1-2 Checkpoint (2026-08-31) — 수용기준 실증 및 Artifact Freshness Requirement

> 본 섹션은 Phase 0 동결 본문(§1-§13)을 수정하지 않는 checkpoint 기록이다. §11 Phase 1의 수용기준("`src/core/**` 1파일 변경 → 해당 node CAS 무효화 확인, closure 강제 실패 시나리오에서 재실행 + Unresolved(reason) 기록 확인")이 2026-08-31 E2E 실험으로 실증되었음을 기록한다. 상세 실측값: `docs/audit/cas_identity_consistency_READY_2026-08-31.md`.

**실증 요약**:

- **identity 일치**: writer(`bin/precompile_gates` → `computeCasKey`)와 실제 executor reader(`bin/axiom-gate hook pre-commit` → `src/gate/orchestrator/hook/executor.nim:141` → `gate_cas.resolveCasBinaryPath`)가 동일 key를 독립 계산해 일치함을 실측 (`env-gate-058bd56154014afb-96f9fcc598714e00`). reader는 writer artifact를 재컴파일 없이 실행(lookup HIT, binary mtime 불변).
- **mutation**: dependency 1파일 변경 → transitive closure key 변경 + stale artifact lookup MISS(재사용 금지) → writer 재실행으로 새 artifact 생성 후 reader가 동일 key로 HIT·실행.
- **revert**: 원복 → key 원래 값 복원 + 기존 artifact 재사용(writer `cached` 0 compiled, reader lookup HIT).
- **unresolved**: closure 강제 실패 → key 없음("") + lookup MISS + fail-closed 런타임 로그("forcing compile", DEBT#449/#450) + AOT fail-close로 commit 차단(hook exit 1). §4의 Resolved-miss(A) / Unresolved(B) 구별은 과도기 ""-convergence 위에서 reason 로그로 구별 가능한 상태로 동작 중.

**Artifact Freshness Requirement** (blocker 아님 — migration 시점의 정상 요구사항):

```
source revision X  →  writer X, reader X      (보장)
source revision X  →  writer X, reader X-1    (금지)
```

2026-08-31 실측에서 `bin/axiom-gate`가 identity 전환 커밋(35757cfd) 이전 빌드 상태로 남아 writer(신)/reader(구) divergence 위험이 확인되었다. 배포/CI에서는 writer와 reader를 **동일 소스 리비전에서 재빌드**해야 하며, 서로 다른 리비전의 writer/reader 조합은 허용하지 않는다. 이 요구는 향후 Evidence DAG의 **NodeExecutorDigest**(§3)가 다룰 영역(실행기 구성이 identity에 binding)과 자연스럽게 연결된다 — gate binary의 executor digest가 소스 리비전에 binding되면 writer X / reader X-1은 구조적으로 금지된다.
