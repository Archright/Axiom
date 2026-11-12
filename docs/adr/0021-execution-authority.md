# ADR-0021: Execution Authority ≠ Certificate Authority

> **Historical note (2026-09-18, PR #127)**: 이 ADR이 upstream으로 참조하던 `ci.yml`
> (workflow_run 트리거 소스)은 tombstone 후 삭제되었다(ci.yml retirement).
> 실행 authority 계약 자체와 publication_scope의 job_if_guard 검증은 살아 있다
> (admission_producer.yml의 verify-candidate 경로). 아래 서술 중 ci.yml 실측은
> 삭제 시점 기준으로 과거 기록이다.

## Status

**RATIFIED (2026-09-12).** Supersedes the workflow_dispatch-based candidate
verification entry (`docs/spec/merge_admission_controller.md` §3 Model B
dispatch path — `event ∈ {pull_request, workflow_dispatch}` admissibility for
candidate runs). This ADR **does NOT supersede** Model B's trusted/untrusted
executor boundary — it strengthens it: untrusted code still executes only as
verification SUBJECT data on ephemeral runners, and trusted workflows still
originate from the default branch.

## Context

- **왜 agent가 임의의 VerificationSubject에 대해 새 검증 실행을 발행할 수 있는가?** —
  기존 구조는 `verify-candidate.yml`과 `attest.yml`이 `workflow_dispatch` 트리거를
  소유하여, 실행 발행(execution authority)이 repository 상태 변화와 분리되어 있었다.
  이는 (a) agent가 임의 실행을 발행할 수 있는 권한 경로(I1–I7 루프의 발행 경로),
  (b) agent-triggered verification execution(agent가 유발하는 검증 실행),
  (c) rerun 재발화 시 downstream 재생성(re-fire 경로 — rerun/ENV recovery는
  정상 recovery이며 금지 대상은 agent가 유발하는 검증 실행뿐),
  (d) 인증서 중복 발급 가능성(certificate authority의 소유권 흐림)을 남긴다.
- **핵심 구분**: 검증 실행을 시작할 수 있는 능력(Execution Authority)은 인증서를
  발행할 수 있는 능력(Certificate Authority)과 **다른 authority**다. 전자는
  platform이 소유(트리거 선언), 후자는 attest trusted tier만 소유한다.
- **플랫폼 근거**: self-hosted runner는 untrusted 코드가 runner를 영구적으로
  손상시킬 수 있다("Self-hosted runners … can be persistently compromised by
  untrusted code in a workflow"). untrusted 코드 실행은 evidence 문제가 아니라
  실행 환경 침해 문제다 — workflow_dispatch 제거는 이 보안 속성을 실제로 제거하므로
  pull_request 전환(P1)을 채택한다. `workflow_dispatch` 트리거가 없는 워크플로는
  `gh workflow run`이 플랫폼 수준에서 거부된다(트리거 선언 필요 — 공식).
- **workflow_run 이벤트는 지정 workflow(ci.yml)의 completed에서 발생하며, PR event로
  제한하지 않는다** — trusted downstream의 `if:` 조건(admission clause)이 이 판정을
  수행한다. `publication_scope_gate`의 정적 검증은 **정책 드리프트 방지 장치**이지
  보안 boundary가 아니다(D8).
- **실측**: ci.yml PR run 47개 전수에서 `run.head_sha` = PR head 커밋(merge commit
  아님)이 확정되었다. 합성 merge ref에서 검증이 수행되지만 check-run/check-suite은
  전부 head 커밋에 귀속된다. 따라서 "parent2 유도"는 불가능(구현 불가) — 폐기.

## Decision

### D1. Execution Authority ≠ Certificate Authority

| | Execution Authority | Certificate Authority |
|---|---|---|
| 정의 | 검증 실행을 시작할 수 있는 능력 | 인증서(attestation)를 발행할 수 있는 능력 |
| 소유자 | **repository state 변화**(PR synchronize) + 플랫폼 native rerun. 그 외 원천 없음 | attest trusted tier만 (재유도 체인 통과 시) |
| agent의 권한 | **없음** — dispatch 트리거 제거로 플랫폼이 거부 | 없음 — evidence는 재유도 전까지 무권한 데이터 |
| 실패 유형 | STATIC→subject 변경 / ENV→rerun / DID-NOT-HAPPEN→코드 수정 | 위조/불일치 → fail-closed, authority 발생 없음 |

**trusted workflow가 WHAT may execute를 결정, untrusted subject가 WHAT is being
verified를 공급한다** — 실행 프로그램(workflow+게이트)은 항상 default branch 버전,
subject는 데이터로만 공급된다. Model B의 진짜 핵심인 이 경계를 유지하면서
**dispatch라는 agent 진입 권한만 제거**한다.

### D2. workflow_dispatch triggers removed from verify-candidate.yml and attest.yml

`on: workflow_dispatch`를 `verify-candidate.yml`과 `attest.yml`에서 **삭제**한다.
GitHub 플랫폼 규칙상 `workflow_dispatch` 트리거가 없는 워크플로는 `gh workflow run`
이 원천 거부된다(트리거 선언 필요 — 공식). 이로써 agent의 임의 실행 능력이
플랫폼 수준에서 소멸한다. **새 execution surface가 생성되지 않도록**: 별도
recovery 워크플로(dispatch 1건)를 만들지 않는다 — 회복은 operator 수동 절차
(D9)뿐이다.

### D3. Normal path = workflow_run(ci.yml PR-path success) → verify-candidate → attest

검증 실행은 repository 상태 변화에서만 유도된다:

```
ci.yml (pull_request, run_attempt==1, success)
  → workflow_run → verify-candidate (main checkout, evidence emission 전용)
  → workflow_run → attest (main checkout, trusted tier만)
```

`verify-candidate`의 정상 트리거는 `workflow_run`(ci.yml PR-path success),
`attest`의 트리거는 `workflow_run`(verify-candidate success)이다. `auto_merge →
merge_continuity`의 dispatch는 유지된다(trusted actuator의 platform wiring,
GITHUB_TOKEN, `merge_admission_controller.md` §10 — 계약 §10과 충돌하지 않는다).

### D4. Immutable upstream subject transport invariant

**계약이 선언하는 invariant는 "upstream은 immutable subject identity를 전달해야
한다"는 요구 자체**이며, 전달 메커니즘은 교체 가능한 transport로 명세한다:

- **Subject identity source**: `github.event.workflow_run.head_sha` is the
  immutable commit of the triggering workflow run — the commit the triggering
  run executed (ci.yml PR-path run → the PR head commit).
- **채택 transport (T1)**: subject transport =
  `f(github.event.workflow_run.head_sha)` — a pure function of that value;
  **currently the identity function**. 실측(2026-09-11): ci.yml PR run 47개
  전수 단일 부모 — `run.head_sha` = PR head 커밋, merge commit 아님(검증은
  synthetic merge ref에서 수행되나 check-run/check-suite은 전부 head 커밋에
  귀속). attest가 이 값과 evidence `prHeadSha`를 대조한다.
- **NEVER confuse with the downstream workflow's own `github.sha`**: in the
  `workflow_run` context, `github.sha`/`github.ref` = the last commit on the
  default branch / the default branch — a different value. The two are
  different values and **only `github.event.workflow_run.head_sha` carries
  subject identity**; the downstream's own `github.sha` must never be used as
  the subject.
- **parent2 유도는 구현 불가로 폐기**: `run.head_sha`는 merge commit이 아니므로
  parent2로 head를 유도할 수 없다.
- **금지**: "현재 PR head 재조회"로 identity를 재구성(mutable state 혼입).
  `workflow_run.pull_requests[]`는 PR 닫힘 시 빈 배열(실측: closed PR run은
  `prs:[]`) — 2차 transport로 사용할 수 없다. 대조 채널은 evidence 기록값
  (immutable)만 사용한다.
- subjectId wire(axiom.subject.v2, 6-field) 불변 유지.

### D5. success ≠ evidence — 4-clause admission

verify-candidate가 "X가 S를 검증했다"로 소비되려면 다음 4절을 **전부** 통과해야
한다(하나라도 실패 = fail-closed 거부, success 단독은 evidence가 아님):

1. `event == pull_request` (triggering ci.yml run)
2. `run_attempt == 1` (rerun 재발화 차단 — V-A 실측: readiness_start run
   34557757124의 rerun(attempt 2) 완료 후 auto_merge 신규 run 34560971005 생성.
   rerun은 `workflow_run(completed)`을 재발화하며 payload conclusion은 해당
   attempt 값을 따른다)
3. `conclusion == success`
4. **immutable subject transport valid** (D4 — subject = pure function
   `f(github.event.workflow_run.head_sha)` of the triggering run's immutable
   commit — currently the identity function — + head tree digest 대조)

### D6. Duplicate-subject predicate before mint

동일 subjectId에 대한 인증서는 원장에 **1개만** 존재한다(불변식 INV-13,
`certification_continuity_contract.md` §5). mint 직전(attest 체인에서 `attest()`
호출 직전 — `cert_cli.nim:763` 부근)에 `listLedgerCertIds`(ledger_side_ref.nim)
멤버십 검사로 기존 발급 존재를 확인한다 — ledger가 유일한 durable 소스다.
기존 writer의 로컬 vault 검사(`subject_continuity_writer.nim:259-260`)는 유지하고
이 레지스트리 멤버십 검사를 추가한다(attest.yml §-1 무변경).

### D7. Executor identity re-derived at trusted tier

**executor identity는 evidence가 선언하지 않고 trusted tier가 재유도한다.**
attest bind 스텝 내 RUN_ID 검증 직후: run record(`GET /actions/runs/{id}`) →
head_sha → **contents API**(`GET /contents/.github/workflows/verify-candidate.yml
?ref=<run_head_sha>`)로 blob 유도(트리 API 대안보다 절단 무) → main checkout
blob(`git rev-parse HEAD:...`) 대조 — 불일치면 `EXECUTOR_MISMATCH` fail-closed.
양성 MATCH/음성 MISMATCH 실측 완료(run 34639588702 → 65a3c58f MATCH; 구 커밋
14c6f7762 트리 → 850335eb MISMATCH 검출). repo private이므로 GITHUB_TOKEN 필수.
`run.path` 바인딩(`path == verify-candidate.yml`, `%@*` 접미 방어)과 workflow_id
이중 바인딩도 동일 fetch에서 추가한다. scope 결정은 **발급 시점 게이트**(mint
domain)다: run head blob이 `config/executor_authority.json`의
**TrustedExecutorSet** 멤버십에 있어야 발급이 허용된다 — main checkout의
config에서 trusted 집합을 읽어 멤버십 검사(untrusted PR head의 config는
사용하지 않는다 — trusted state는 항상 default branch 기준).
TrustedExecutorSet = {현재 default-branch blob} ∪ {정책에 grandfather된 전이
blob}; retirement = 집합에서 제거(기존 certificate 소비는 계속 유효, 새 발급만
금지). blob lineage/이력 집합은 기각(보안 이득 0, 복잡도 최대).
**certificate 소비(merge admission Pass 2.96/continuity)는 executor identity를
평가하지 않는다** — executor epoch와 base epoch는 분리 불가(blob이 바뀌는
merge는 base를 전진시키는 merge → STALE_BASE가 이미 epoch 결합을 담당).
setup-axiom-toolchain action blob도 동일 바인딩 포함(trustSurface 등록).

### D8. publication_scope_gate is a policy-drift-prevention device, not a security boundary

`publication_scope_gate`(`config/publication_scope.json` + 정적 파서)는 워크플로
트리거와 permissions의 선언 대비 선언(declared vs declared) 검증을 수행하며,
`workflow_run`은 선언이 아닌 **플랫폼이 생성하는 런타임 사실**이다. PR event 제한
판정은 trusted downstream의 `if:` 절(D5)이 수행한다 — 게이트는 그 정책 문구가
드리프트하지 않도록 강제하는 장치이며, 보안 boundary로 취급하지 않는다.

### D9. Recovery = operator manual procedure (no new workflow surface)

과거 head 재인증/attest 실패 시 회복은 **operator 수동 절차**가 유일한 경로다:
**execution authority는 만들지 않지만 certificate authority를 행사하는
operator-only migration/recovery issuance path**다. 로컬에서
`bin/ax cert attest --ref <sha>` (+ 필요 시 subject-register)를 실행한다.
workflow_dispatch 기반 recovery 워크플로는 만들지 않는다(새 execution surface
생성 금지). D9의 invariant:

| 축 | 값 |
|---|---|
| execution authority | **없음** |
| certificate authority | **있음** — operator key(publicKeyId `9a17da48…`) 발급 전용 |
| issuer | operator |
| subject execution | **없음** — 새 검증 실행을 발행하지 않는다 |
| trusted executor state | **current main only** — attest 체인의 policy/scope/toolchain digest가 checkout root(=current main)에서 재계산·대조(attest.yml:154-167) |
| purpose | migration/recovery only |
| normal production issuance | **금지** — 정상 경로는 D3 workflow_run 체인뿐 |

- `gate_history.jsonl` 기록은 이 절차의 감사(audit) 기록이지 **authority로
  소비되지 않는다** — I-2/§4.4의 "journal은 audit/forensic record"와 정합.
- evidence artifact 7일 만료 후 과거 head: 동일 수동 절차로 재인증(새 실행 표면
  생성 없음).

### D10. Failure classification STATIC / ENV-TRANSIENT / DID-NOT-HAPPEN

실행/인증 실패는 3분류로 구분하고 회복 경로를 계약한다(`docs/spec/ci_admission_contract.md`):

| 분류 | 정의 | 회복 |
|---|---|---|
| STATIC | 코드·정책·워크플로 고정 결함 — rerun으로 해소 불가 | **subject 변경**(code change) — PR head 갱신 또는 코드 수정 |
| ENV-TRANSIENT | 러너/캐시/네트워크/레이트리밋 등 일시 환경. 결함 아님 | **GitHub native rerun 1회 한정**(같은 run/SHA/REF; rerun은 workflow_run을 재발화하므로 downstream은 `run_attempt == 1`로 차단) |
| DID-NOT-HAPPEN | evidence 부재/미생성 — required check가 생성되지 않아 "실행이 없었다" | rerun으로 고칠 수 없음 — **코드 변경이 유일한 회복** |

## Consequences

- **긍정**: agent dispatch 경로 제거(execution authority = repository state
  transition 전용), **agent-triggered verification execution = 0** — no
  agent-reachable mechanism creates a new verification execution; execution
  originates only from repository state transitions and platform-native reruns
  (rerun/ENV recovery는 정상 recovery; V4 주기 실행: PR당 ci 1회 +
  verify-candidate 1회 + attest 1회), rerun 재발화는 `run_attempt==1` 절로 차단
  (D5-2), 인증서 중복 발급 차단(D6).
- **부정(residual)**:
  - docs-only PR 체인 정지 — ci.yml paths-ignore로 run이 없으면 verify-candidate도
    없음. **fail-closed 정합**(체인이 정지된 채 무언가 발급되면 오히려 위험).
    회복 = 사람이 PR을 수동 머지(manual merge), 체인은 다음 상태 변화에서 재개.
  - artifact 7일 만료 후 과거 head 재인증 — 수동 절차(D9) 필요.
  - attest 실패 시(agent dispatch 없는 구조) — operator 수동 절차 + admission
    CHECK_INCOMPLETE fail-closed.
- **롤아웃 순서**: (1) 계약 개정(본 ADR + §3/§4.2 동시 병합), (1a) **TrustedExecutorSet 도입**
  (`config/executor_authority.json` 신설 — Phase 0 = {E1} → transition declaration
  PR #69 head에서 {E1, E2} 선언 → post-merge main = {E1, E2} → PR #70 retirement
  = {E2}; set 변경 = trust-surface change = manual merge/authoritative review),
  (2) verify-candidate 트리거 교체(Phase 1), (3) attest 트리거 교체 + executor
  identity 재유도(Phase 2), (4) duplicate-subject predicate(Phase 3),
  (5) publication_scope gate if: 조건 검증(Phase 3+), (6) ci_admission_contract와
  실패 매핑표(Phase 4 — 본 ADR과 동반).

## References

- GitHub Docs — [Self-hosted runner security](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners): "Self-hosted runners … can be persistently compromised by untrusted code in a workflow"
- GitHub Docs — [Events that trigger workflows](https://docs.github.com/en/actions/writing-workflows/choosing-when-your-workflow-runs/events-that-trigger-workflows): workflow_dispatch 트리거 선언 요건, workflow_run 이벤트 시맨틱("requested만 미발생")
- GitHub Docs — [Re-running workflows and jobs](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-workflow-runs/re-running-workflows-and-jobs): rerun은 같은 run id의 attempt 증가, workflow_run(completed) 재발화
- ADR-0020 [`docs/adr/0020-axiom-queue-semantics-and-executor-boundary.md`](0020-axiom-queue-semantics-and-executor-boundary.md): trusted/untrusted executor boundary(D9), activation boundary
- [`docs/spec/merge_admission_controller.md`](../spec/merge_admission_controller.md): §3 Model B dispatch path(본 ADR이 supersede), §6 trust model, §10 executor seam
- [`docs/spec/certification_continuity_contract.md`](../spec/certification_continuity_contract.md): §4.1/§4.2 Trusted Attestation Boundary, §5 INV-13(본 ADR D6)
- [`docs/spec/ci_admission_contract.md`](../spec/ci_admission_contract.md): 3분류 실패 + 12건 실패 매핑표(Phase 4)
- 실험 데이터: Phase -1(V-A idempotency) 결과 — **pending Phase -1** (아직 수행 안 됨; 완료 시 run URL + `created_at > T0` 필터 데이터로 교체)