# ADR-0020: Axiom Queue Semantics and Executor Boundary

## Status

**SUPERSEDED (2026-09-10, Verdict B).** The speculative candidate queue,
executor adapter boundary, and Axiom-owned serial landing semantics defined
here are **removed** — ratified Verdict B adopts GitHub native MERGE commit as
the canonical landing mechanism with no custom queue/orchestrator
(`docs/spec/certification_continuity_contract.md` Model B revision).
the queue store + orchestrator modules,
and the `refs/queue/*` machinery are deleted. The admission core
(`MergeAdmissible`, trust surface, snapshot discipline) survives in
`src/cli/merge_cli.nim` and `docs/spec/merge_admission_controller.md`. The
sections below are historical rationale, retained for the audit trail.

## Context

- **용량 실증 (run 33365379055, 2026-08-31)**: direct push `cf44fb6eb`로 촉발된 CI에서 2대의 runner가 서로 다른 job을 실제로 동시 실행함이 확인되었다(verify-integration ∥ verify-coverage-guard, 06:55:58–06:59:15Z, 3m17s overlap). 풀 용량은 N = 호스트 수(호스트당 runner 1개, `jit_supervisor.sh`의 `wait_runner_idle` 직렬 순환).
- **랜딩은 직렬이다**: rebase-only 정책 + Merge Admission Controller(v8)가 HEAD/base를 재확인하며 착륙 순서를 강제한다. 그러나 **랜딩 직렬화는 검증 계산의 직렬화를 요구하지 않는다** — 두 문제는 서로 다른 병목이다.
- **스테일 문제**: A가 먼저 랜드해 X+A가 되면, X에 대해 검증된 B의 녹색 결과는 무효가 된다. 이 낭비는 B가 `X+A(+B)`를 **투기적으로** 검증하는 구조로 제거된다. GitHub 공식 merge queue가 merge_group 임시 브랜치(gh-readonly-queue)로 구현하는 것과 동일한 알고리즘이며, predecessor 실패 시 하류를 재생성하는 시맨틱도 문서화되어 있다([Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)).
- **v8의 제약**: `merge_admission_controller.md:34`는 "controller/event bus/**queue**/database/distributed lock 도입 금지, GitHub가 event delivery와 scheduling을 소유"를 선언했다. 본 ADR은 queue 항목만 개정한다(event bus·database·분산 lock 금지 유지 — queue는 로컬 결정론 state journal이지 서비스가 아니다).
- **핵심 구분**: "검증을 순차적으로 하는 것"과 "검증 대상 커밋의 논리적 순서를 구성하는 것"은 분리된다. **Validation is parallel. State transition (landing) is serial.**
- **용량-정확성 직교**: runner 수(현재 2)는 correctness와 무관하다. capacity는 측정 후 확장하며 선구매하지 않는다(`docs/spec/self_hosted_ci_migration.md` RSC retention trigger 준용).

## Decision

### D1. Queue semantics 소유 (v8 :34 개정)

Axiom은 **ordered queue, speculative prefix chain, epoch, predecessor tracking, suffix invalidation**을 소유한다. 주 경로는 ordered prefix chain(H1=X+A, H2=X+A+B, …)이며, invalidated/replaced candidate를 포함한 전체 상태공간을 **Speculative Candidate Graph**라 한다. Queue 상태는 로컬 결정론 journal(`data/merge_queue/`, TrustCommit 패턴 준용: atomicWrite + replay, orphan fail-closed)이다. Event bus, database, 분산 lock은 계속 금지.

### D2. Queue semantics ≠ execution policy

`speculativeDepth`는 **policy**(`config/policy/merge_admission.json`)이다. Enqueue 시 dispatch되는 것은 **eligible speculative frontier**(depth 내 prefix)뿐이며, depth 밖 항목은 `qesQueued` queue-state로만 존재한다. depth 변경은 correctness에 영향을 주지 않는다 — landing 판정 입력은 evidence + identity + current HEAD 뿐이고(`MergeAdmissible` 순수 predicate), `reusable(U)` 불변식에 depth는 없다. GitHub merge queue의 Build concurrency(1~100) 설정이 동일 분리의 네이티브 선례다.

### D3. Validation = parallel, Landing = serial

Candidate 검증은 병렬 dispatch된다. Landing은 직렬이며 착륙 시마다: dequeue → PR head 재확인(기존 `STALE_EVALUATION` 경로) → run↔identity 바인딩 검증(D6) → evidence 재수집 → `MergeAdmissible`(candidate 확장 레코드, currentMain) → `performMerge`(rebase + expected_head_sha) → **`tree(candidate) == tree(landed)` 재유도 대조** → 불일치 시 fail-closed. Predecessor 실패 시 **dispatch된 범위만** invalidation하고 prefix를 재구성한다(GitHub merge queue의 하류 재생성 시맨틱과 동일).

### D4. Candidate identity — 3층 분리 (`src/core/types/candidate_identity.nim`)

- `CandidateStateIdentity = {treeDigest}` — WHAT (repository state)
- `CandidateProvenance = {baseCommit, orderedChanges, repositoryIdentity}` — WHERE FROM
- `VerificationContextIdentity = {policyDigest, toolchainDigest, verificationContractDigest}` — UNDER WHAT CONTRACT
- `CandidateEvidenceDigest = H(state | provenance | context)` — hash-of-parts 정례(`identity.nim:212-217`)

**epoch와 depth는 content identity에 절대 포함되지 않는다**(`cache_policy.md:24-26` — epoch는 namespace; `reusable(U)` §4.2에 epoch·depth·baseCommit 없음). baseCommit이 Provenance에 속하는 것은 검증-결과 재사용 의미론상 정확하며, `BaseRunIdentity`의 baseCommit 포함(certification eligibility 결정)과 충돌하지 않는다 — 서로 다른 결정을 지배하는 별개 identity 계층이다. 후보 content 동일 → 같은 `CandidateStateIdentity` → verification 재사용; provenance·context 변경 → admission 재평가.

### D5. Logical Candidate ≠ Materialization — 선언은 신뢰가 아니다

Provider가 만든 ref/commit(`MaterializedCandidate = {candidateRef, candidateCommit, declaredTreeDigest, provenance}`)은 **선언(claim)**이다. 사용 전에 `declaredTreeDigest == resolvedTreeDigest`를 **독립 읽기 경로**(다른 코드 경로 + 다른 데이터 소스 — 예: `GET /commits/{sha}` → `commit.tree.sha`)로 재유도해 대조한다. 동일 API 재호출은 비독립이며 금지된다. 불일치 시 fail-closed(`MATERIALIZATION_MISMATCH`) + `Theater/MaterializationMismatch` debt 등록(§0.9 always-pass 금지). 정례: `runner_pool_digest.sh`(선언) vs `jit_supervisor.sh:96-117`(측정, 불일치 exit 1).

### D6. Run ↔ identity 강한 바인딩

"run R이 성공했다"만으로는 불충분 — "run R이 정확히 identity I에 대한 것이었다"를 검증한다. I/O 경계(collectAdmissionFacts 내, `MergeAdmissible` 외부 — 순수성 유지)에서: (a) `run.head_sha` == candidate commit, (b) `GET /commits/{run.head_sha}.tree.sha == candidateTreeDigest`(핵심 독립 재유도), (c) dispatch inputs 대조(우선 API `inputs` 조회, 구현 시점 확인; 불가 시 trusted echo + (b) 교차검증), (d) workflow_id + path 이중 바인딩. 실패 → `BINDING_MISMATCH` fail-closed. 바인딩 결과는 `logMergeAdmission`의 `binding` 서브오브젝트로 기록된다.

### D7. Executor boundary — provider 교체 가능

추상 이벤트 `CandidateDispatched` → adapter 번역. GitHub adapter가 첫 구현(workflow_dispatch, MVP; activation boundary — workflow 파일이 main에 착륙한 후에만 dispatch 가능). GitLab/Local executor는 committed customer contract 발생 시 착수(§0.12). v8의 "GitHub-native 시 actuator 제거" 서술은 "backend 교체, seam·predicate 유지"로 개정된다.

### D8. Repository adapter — git semantics 재구현 금지

Candidate 생성은 repository provider의 역할이다(GitHub merge queue가 임시 merge-group 브랜치를 생성하듯). Axiom core는 git merge/rebase 알고리즘을 구현하지 않고, `CandidateConstructionResult = {candidateRef, candidateCommit, candidateTreeDigest, provenance}`를 소비한다. the candidate provider layer (removed 2026-09-10).

**(v10 개정, 2026-09-09)**: 본 계약은 certification continuity 아키텍처(v10, `docs/spec/certification_continuity_contract.md`)에 따라 개정된다 — candidate construction은 git 자체의 merge machinery를 호출하는 것으로 충족된다(`merge-tree --write-tree` in-core + `commit-tree`); Axiom core는 여전히 merge 알고리즘을 구현하지 않으며, the materializer module (removed 2026-09-10) was this single approved call path(`merge-tree`/`commit-tree`는 `data/command_policy.json` 차단 목록 밖 — exact-token 강제). Conflicted replay 결과는 publishable object가 아니므로 fail-closed abort. 인증서는 구성된 OID를 binding한다(재유도 비교 금지 — contract INV-3).

### D9. Trust model — Trusted/Untrusted 경계 명문화

| Class | Contents | Treatment |
|---|---|---|
| Trusted | workflow definition(기본 브랜치 출처 — activation boundary), executor/adapter 코드, verification policy | control flow 구동 가능; admission 게이트로 소비 가능 |
| Untrusted (candidate) | repository contents, candidate scripts, Makefile, nimble/build/test code | 검증 **대상 데이터**로 ephemeral runner에서 실행; 결과는 D6 바인딩을 통해서만 소비; 신뢰 상태로 진입 불가 |

v8의 "candidate-branch workflow code는 실행·신뢰 금지"를 build/test tooling까지 확장 명문화한다. Gate/policy 코드 변경은 불필요 — fail-closed 체계가 이미 candidate 코드의 trust-state 진입을 차단하며, 본 항은 문서화 격차 해소다.

### D10. Capacity — correctness와 직교

Runner 수는 정확성과 무관하다. 2 슬롯으로 queue semantics를 완성하고, 실측(queue depth / arrival rate / integration duration / batch failure rate) 후 `self_hosted_ci_migration.md` RSC trigger 조건에 따라 확장한다(CX23 증설 또는 supervisor 다중 인스턴스 개조). 선구매 없음.

## Consequences

- **긍정**: 스테일 재검증 낭비 제거(정상 경로), 랜딩 직렬화와 검증 처리량의 분리, provider 교체 가능성(Zuul/GitHub가 검증한 알고리즘을 채택하되 어느 쪽에도 종속되지 않음), content-addressed 인증서 체계와의 자연스러운 연결.
- **부정(본질적 비용)**: predecessor 실패 시 투기 검증 일부 폐기 — 설계 결함이 아니라 투기적 병렬성의 고유 비용이며 D2의 depth policy로 제어한다.
- **롤아웃 순서 제약**: `verify-candidate.yml`은 activation boundary상 main 착륙 후에만 dispatch 가능 → 워크플로 착륙이 큐 활성화에 선행.
- **계약 개정 필요**: 본 ADR 승인 시 `merge_admission_controller.md` v9(:34 queue 금지 철폐, :48 candidate 모델, :33 executor seam 서술, :58 event 확장, §6 trust 표, §7 reason codes, §10 재프레임)과 `productization_contract.md` §1 carve-out이 함께 병합되어야 한다.

## References

- GitHub Docs — [Managing a merge queue](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue): merge-group 임시 브랜치 생성(=provider의 candidate 생성), 실패 시 하류 재생성, Build concurrency(1~100), merge method rebase 지원
- GitHub Docs — [Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows): merge_group, workflow_dispatch(기본 브랜치 요건)
- 용량 실증: run 33365379055 (`cf44fb6eb`, 2026-08-31) — 2-runner overlap PASS
- 코드베이스 근거: `merge_cli.nim:167`(순수 predicate), `:593-613`(rebase merge + expected_head_sha), `:662-668`(STALE_EVALUATION), `certificate_identity.nim:15-30`(SHA 미포함 identity), `run_identity.nim:34-39`(Semantic/Provenance 분리), `identity.nim:212-217`(hash-of-parts), `cache_policy.md:24-26`(epoch=namespace), `canonical_cache.nim:44-47`(lifecycle enum 정례), `jit_supervisor.sh:96-117`(선언 vs 측정 정례), `trust_commit.nim:399-464`(journal replay), `layer_rules.nim:109-112`(infrastructure 레이어)
- 계획서: "Axiom Admission Engine — Speculative Candidate Graph 구현 계획 (v5)" (2026-08-31 승인)
