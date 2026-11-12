# DEBT#464 — Certificate Mint Authority 설계 v12 (2026-09-18)

> **Status**: **확정 구조 — v12** (2026-09-18, Phase 0 개정 · docs-only PR). 구현 0건,
> 권한 부여 0건.
>
> 1판(PR #125)은 5개 질문(Q1–Q5)의 후보·트레이드오프·권고를 architect review에
> 제출하는 설계 검토 초안이었다. 본 개정은 그 검토 결과를 **확정 구조(v12)**로
> 기록한다 — trust boundary 확장의 값(2계층 분리, M/B/H 유도, identity 분리 등)이
> 결정되었으며, 구현 코드·workflow YAML·권한 부여 실행은 S4 Phase 1에서 수행된다.
>
> **관련**: DEBT#464(`data/debt_registry.json:3793`),
> ADR-0021 §D6/D9(`docs/adr/0021-execution-authority.md`),
> ADR-0022 §D5/D6(`docs/adr/0022-admission-artifact-authority.md`),
> [`certified_landing_mint_path_2026-09-18.md`](../evidence/certified_landing_mint_path_2026-09-18.md)

---

## 0. 확정 요약 (v12)

```
witness (비권한 admission tier — 실행 원천 = B 완전 고정)
  └─> unsigned witness bundle (data 원 = H checkout — 실행·빌드 0)
certificate-mint.yml (publisher — workflow_run privilege boundary, untrusted computation 0)
  └─> verify / normalize → canonical certificate representation 재구성 → sign → publish
      (witness 바이트를 그대로 sign하지 않음 — 항상 trusted tool이 재구성한
       canonical representation을 서명)
```

**핵심 결정 12항**:

1. **2계층 확정**: witness(비권한, unsigned witness bundle) / publisher(정규화→서명→발행).
   검증은 unprivileged tier, publication만 privileged tier — privileged tier는 어떤
   untrusted computation도 하지 않는다.
2. **M/B/H L0 merge-shape 유도식 (v2 개정)**: `M = M_PR`(PR API
   `merge_commit_sha`), `B = PR.base.sha`, `H = PR.head.sha`. 1판(v8)의
   "`workflow_run.head_sha` == merge commit" 주장은 **실증 반박** — 본 repo run
   `35414954344`·`35369567925`에서 `head_sha`는 **PR head H와 동일**했다.
   따라서 M은 run API `pull_requests[]`(정확히 1) → `GET /pulls/{N}` →
   `merge_commit_sha`(M_PR)로만 유도하며, `GET /commits/{M_PR}`의 2-parent
   구조(parent1==B, parent2==H)로 merge shape을 강제 검증한다. **M source
   고정**: `github.sha`·`workflow_run.head_sha` 모두 M으로 사용 금지.
3. **identity 분리**: certificate semantic identity = (B, H) + 기존 attest binding
   필드(스키마 무변) / provenance = M·run_id·run_attempt·artifact identity·witness
   digest. **cert 표현에 runId/runAttempt/M 미포함** — 동일 (B,H) 재실행 시
   representation이 변해 canonical identity가 깨지는 것을 차단.
4. **witness 실행 원천 = 완전 B 고정 — 범위 = Axiom-controlled computation**
   (repo 제공 executable implementation 전부: bin/ax·assembler·
   setup-axiom-toolchain composite action). Runner OS·GitHub platform 행위는
   **외부 TCB로 수용**(재구현·재검증하지 않음). H는 secondary path의 data 원.
5. **publisher 파이프라인**: `untrusted witness → verify/normalize → canonical
   certificate representation 재구성 → sign → publish`. 변조·비정형 witness는
   검증/정규화에서 fail-closed.
6. **publisher activation guard 3조건**(모두 성립해야 후속 진행, 하나라도 불성립 시
   즉시 fail-closed): `workflow_run.event == pull_request` ∧
   `conclusion == success` ∧ `path == admission_producer.yml`. `workflows:` 트리거
   필터는 이름 기반이라 동명 위workflow를 허용하므로 activation은 반드시 **path**로
   재확인.
7. **admission identity 튜플**: actual = `(workflow_id, path, workflow_file_blob_sha
   @M)` ↔ expected = `(trusted_path, trustedAdmissionWorkflowSha) @B`. **notation
   고정**: workflow_id = `github.event.workflow_run.workflow_id`(workflow **정의**
   identity), run_id = `github.event.workflow_run.id`(**run instance** identity) —
   혼동 금지. **비교 anchor는 B만**(현재 main SHA 비교 없음).
8. **PR identity = GitHub PR API (trusted source, v2)**: run API `pull_requests[]`
   개수 == 1(0·다수 fail-closed) → `GET /pulls/{N}` → `H = PR.head.sha`, `B =
   PR.base.sha`, `PR.base.ref == "main"` → `M_PR = PR.merge_commit_sha` →
   `GET /commits/{M_PR}` 2-parent(parent1==B, parent2==H). **`commits/{M}/pulls`
   호출 전면 삭제**(중복 재구성 + synthetic-merge PR-연관은 플랫폼 변수 — v2 §6).
   용어 분리: **M_PR** = PR API merge commit, **M_WITNESS** =
   witness.provenance.mergeSha — 대조는 `M_WITNESS == M_PR`(불일치 fail-closed,
   새 admission 필요). **base 이동 race 실측**(#125): GitHub는 base 이동 시
   PR.base.sha를 현재 tip으로 갱신 — `base.sha==B` 실패 = fail-closed 정확 동작.
9. **artifact attempt binding 3계층**: (i) run-scoped API `GET runs/{run_id}/artifacts`
   + (ii) trusted-name `witness-{run_attempt}` + (iii) manifest(내부 run_id·
   run_attempt·M·H·PR 대조). 셋 중 하나라도 불일치 → fail-closed.
10. **signature ≠ authority 명시**: 서명 = identity·변조 방지(공개 상수 키
    `AttestationDomainSeed="axiom-attestation-v1-sha256"`,
    `src/infrastructure/certificate_attestation.nim:185` — **secret 아님**). 실제
    mint authority = `refs/heads/axiom/certificates` **publication 권한**(append-only
    ledger + FF-CAS force=false) — 그 권한을 소유한 workflow(= certificate-mint.yml
    단일)가 곧 authority.
11. **publisher permissions 3-scope 최소화 (v2)**: top-level `contents: write` +
    `actions: read` + `pull-requests: read` **외 0건** — `checks: read` 삭제
    (3-scope, **/checks 호출 0건**). top-level에 `contents: write`가 있어야
    `tools/ci/verify_trusted_writer_set.sh`(top-level 블록만 스캔)가 이 workflow를
    TrustedWriterSet 유일 멤버로 관측한다. job-level도 동일 3-scope 명시.
    `pull-requests: read`는 PR API를 trusted source로 고정했으므로 명시 선언.
    **P0**: certificate-mint는 org runner group **axiom-publisher**
    (workflow-restricted: certificate-mint.yml@refs/heads/main)에서 실행 —
    runner는 반드시 **ephemeral/JIT**(job당 등록 → 종료 후 deregister)이어야 하며
    **영구 특권 runner 금지** — 기존 jit_supervisor 도구로 강제, 신규 runner
    manager 없음.
12. **기존 attest 전체 경로는 D9 수동 ceremony용으로 유지**; 신규 서브명령 2개
    (`--witness-only`: 커널만 — 서명·journal·네트워크 0 / `--sign`: 검증→정규화→
    서명→journal)는 **Phase 1 구현 예정**.

**원칙(v12)**: 검증은 unprivileged tier, publication만 privileged tier.
privileged tier는 어떤 untrusted computation도 하지 않는다.

---

## 1. 배경 — 문제의 실체

DEBT#464의 핵심 관측은 **CI 자동 mint 체인이 삭제된 뒤, certificate mint가
운영자 기억(memory)에 의존하게 되었다**는 것이다. 자동화된 production writer가
없어 candidate PR마다 ADR-0021 §D9 operator 수동 절차(로컬
`bin/ax cert subject-register → attest → ledger-append`)를 사람이 수행해야 하며,
잊거나 잘못된 시점에 수행하면 canonical continuity가 `CC_NO_CERT`로
fail-closed 정지한다(실측: landing `bd26bdbb7`).

### 1.1 역사 — mint chain의 소멸

- clean-slate 커밋 `fa069d610`이 **attest.yml, verify-candidate, auto_merge.yml**
  3개 워크플로를 삭제했다.
- 이 중 auto_merge.yml은 **유일한 contents:write 홀더**이자
  post-verdict ledger-append(publication) 수행자였다
  (`docs/evidence/certified_landing_mint_path_2026-09-18.md:26-28`).
- attest.yml은 mint-only(contents:read)였고, attest 체인의 자동 mint 성공 = 0건
  (전부 D9 수동) — ADR-0022 §D5가 contents:write 보유를 {auto_merge.yml} 단일로
  수렴시킨 휴면 권한면 정리와 동일한 근거.
- 삭제 결과: **CI 어디에도 mint producer가 없다**(현행 `.github/workflows/` 6건
  전수: admission_producer / canonical-main / merge_continuity / ci /
  n8_canary / autoscaling_canary — top-level `contents: write` = 0건).

### 1.2 현재 살아있는 mint 경로 (유일)

ADR-0021 §D9 operator procedure — 로컬에서 결정론 seed key(Ed25519,
publicKeyId `sha256:9a17da48…`)로 커널 재실행 stage (a)~(g)을 통과해야 mint됨
(`attestation_orchestrator.nim:419-436`). D9는 **migration/recovery 전용**이며
**정상 production issuance 금지**를 선언한다(`0021-execution-authority.md:163-180`).
즉 현행 상태는 "정상 경로의 mint authority가 아무도 없음 + 유일 경로는
production 금지인 operator 절차"라는 모순적 결여 상태다.

### 1.3 권한 구조의 현황 (실측)

| 대상 | 현재 상태 |
|---|---|
| certificate mint producer | **없음** — CI 6개 워크플로 전수 확인 |
| publication writer | **없음** — 수동 `bin/ax cert ledger-append`(operator)만 존재 |
| `config/trusted_writer_set.json` | `{auto_merge.yml@659bf35215d457875a7ee506ef7be4b318c61f5a}` **선언 유지** — 파일은 삭제됨 |
| `tools/ci/verify_trusted_writer_set.sh` | **현재 통과 불가** — 실행 결과 `VIOLATION` + exit 1(실측, 2026-09-18) |
| canonical-main accept | R(H) CAS append — job-level `contents: write`(top-level은 read), GITHUB_TOKEN만 |
| admission_producer | PR 전용 verify* — top-level `contents: read` |

### 1.4 참고 사실 — R(H) 미달성은 mint authority 부재뿐

관측 run `35318589721`(main=`4593a6f2e`)에서 bind 전체 PASS, continuity가
`CC_NO_CERT`로 fail-closed, accept skipped — `R(4593a6f2e)`가 canonical-
acceptances tip에 없다. 양성 대조: **PR #118/#119**는 head cert가 존재해
full chain(bind → continuity → accept)까지 성공했고, tip `35ccf7f3`(refs/heads/
axiom/canonical-acceptances)에 R 2건이 기록되어 있다. 즉 accept 체인·bind
술어는 정상이고, **부재 원인은 전부 mint authority가 없다는 것 하나**다.

GitHub native rerun은 **원래 event의 commit SHA·ref를 유지**한다(공식 문서 —
Actions rerun은 같은 run id의 attempt 증가, workflow_run(completed) 재발화는
`run_attempt==1` 절로 차단). 따라서 mint가 생긴 뒤 rerun으로
`R(4593a6f2e)`에 도달하는 경로는 **S4(구현) slice의 terminal evidence**로
예약되어 있고, 본 설계 범위가 아니다.

---

## 2. v12 확정 구조 — 2계층 (witness → publisher)

### 2.1 2계층 확정

| tier | 역할 | 권한 | 실행 원천 | untrusted computation |
|---|---|---|---|---|
| **witness** (비권한 admission tier) | 커널 a–f 실행 → unsigned witness bundle + provenance 기록 | `contents: read` | **완전 B 고정** (H = data 원만) | 예 — 그러나 B-고정 도구의 결정론적 실행 |
| **publisher** `certificate-mint.yml` | 검증/정규화 → canonical cert 재구성 → 서명 → ledger-append | `contents: write` + `actions: read` + `checks: read` + `pull-requests: read` | checkout B 1회 (H ref 절대 아님) | **0건** |

### 2.2 아키텍처 다이어그램 (v12 확정)

```
PR H ──> admission_producer (비권한, contents:read)
              │ 기존 5 validations — 기존 trust surface 그대로 (건드리지 않음)
              │ + witness job(신규, 실행 원천 = 완전 B 고정 — 범위는 Axiom-controlled
              │   computation):
              │   (tool, workspace primary) B checkout = M.parent1
              │     → uses ./.github/actions/setup-axiom-toolchain  ← B checkout에서 해석
              │     → B dir에서 make ci-bootstrap (bin/ax — B에서 빌드)
              │     → assembler(신설 script, B 소스)가 H data 경로만 읽어 D9 evidence 조립
              │   (data, secondary path) H checkout = M.parent2 — data 원으로만 사용
              │     H tree에서 make/gate/lake/빌드·스크립트 실행 0
              │   → ax cert attest --witness-only (B-빌드 ax; 커널 a–f는 B toolchain binary가
              │      evidence 내 leanSource/smtlib2를 data로 실행)
              │   witness 기록: semantic 입력(evidence·binding digest) +
              │     provenance(M, B=toolCommit, H, PR, run_id, run_attempt, artifact identity)
              │   → unsigned witness bundle → upload-artifact@v4
              │   artifact name = "witness-{run_attempt}" (결정론적, attempt 포함)
              │   manifest: run_id·run_attempt·M·H·PR·witness digest
              ▼
        certificate-mint.yml (workflow_run: [admission-producer]·completed, branches 필터 미사용)
              │ job-level permissions 3-scope: contents:write + actions:read
              │   + pull-requests:read (checks:read 삭제 — /checks 호출 0건)
              │   runner group: axiom-publisher (ephemeral/JIT — 영구 특권 runner 금지)
              │ checkout은 B 1회(bin/ax + policy/scope digest + set@B 읽기) — H ref 절대 아님
              │ untrusted/proof computation 실행 0건
              │ (0) activation guard: event==pull_request ∧ conclusion==success
              │     ∧ path==admission_producer.yml — 불성립 시 즉시 fail-closed
              │ (1) runObj = GET /actions/runs/{RUN_ID} (pull_requests[]==1 → N,
              │     head_sha==H 교차확인) → PR = GET /pulls/{N}
              │     → H=PR.head.sha, B=PR.base.sha, base.ref==main
              │     → M_PR = PR.merge_commit_sha → GET /commits/{M_PR}
              │     → parents 2개(parent1==B, parent2==H)
              │ (2a) admission identity 튜플: (workflow_id, path, blob_sha@M)
              │     ↔ (trusted_path, trustedAdmissionWorkflowSha)@B — main SHA 비교 없음
              │ (2b) PR identity 재확인: GET /pulls/{N} — head.sha==H ∧ base.sha==B
              │     ∧ base.ref==main (commits/{M}/pulls 경로 전면 삭제)
              │ (2c) provenance 대조 — PR + H + B + run_id + run_attempt:
              │     M 유도값·PR API값 == witness 기록값, 전부 일치 — 불일치 fail-closed
              │ (3) artifact retrieval — attempt binding 3계층:
              │      (i)  run-scoped API: GET runs/{run_id}/artifacts — run_id 스코프 내
              │      (ii) trusted-name: "witness-{attempt}" 일치 (attempt 포함)
              │      (iii) manifest: 내부 run_id·run_attempt·M·H·PR == (2b)(2c) 대조값
              │ (4) witness 검증(toolCommit==B 등) → 정규화: B-빌드 trusted ax가 witness
              │     데이터로부터 canonical certificate representation 재구성
              │     (witness 바이트 그대로 sign하지 않음, runId/runAttempt/M 미포함)
              │ (5) D6: ledger-list 중복 → fail-closed
              │ (6) sign — canonical cert JSON(semantic identity만) 대상
              │ (7) ledger-append (FF-CAS) + provenance 기록(ledger commit 메타데이터:
              │     M·run_id·run_attempt·artifact identity·witness digest)
              ▼
        axiom/certificates ──> native merge ──> canonical-main ──> R(H)
```

### 2.3 publisher 파이프라인

`untrusted witness → verify/normalize → canonical certificate representation 재구성
→ sign → publish`. 서명 대상은 항상 trusted tool이 재구성한 canonical
representation; 변조·비정형 witness는 검증/정규화에서 fail-closed. `--sign`은
"attest에서 커널(a–f)과 네트워크(D6)만 제외한 나머지(검증→정규화→cert
조립→서명→journal)"로 구현된다(v12 §11).

### 2.4 witness 실행 원천 = 완전 B 고정 — 범위 = Axiom-controlled computation

B pinning 대상은 **Axiom이 통제하는 computation** — repo 제공 executable
implementation 전부(bin/ax, assembler, `setup-axiom-toolchain` composite action과
toolchain 설치 절차). workspace primary checkout = B이므로 전부 B에서 해석·빌드.
**Runner OS·GitHub platform 행위는 외부 platform TCB로 수용**(재구현·재검증하지
않음). H는 secondary path의 data 원.

- (base,H) identity = 기존 계약: continuity는 `cert.baseSha==parent1` +
  `headSha==parent2`(`src/verification/continuity_check.nim:107`) — M/B/H 유도·PR
  base 검증과 동일 shape.
- artifact v4 immutable + run-id 다운로드 = Context7 공식 확인. upstream
  artifact는 **untrusted data**(GitHub 공식 경고) → publisher는 검증 대상 데이터로
  소비. attest 중복=fail-closed, subject-register만 유사-idempotent(실측) → D6는
  publisher 측.

---

## 3. merge-shape 정의 — M/B/H 유도식 (v2 개정)

```
runObj = GET /actions/runs/{RUN_ID}   # RUN_ID = workflow_run.id
  └─ pull_requests[] == 1 → N          # 0·다수 → fail-closed
PR = GET /pulls/{N}
  ├─ B = PR.base.sha                  # base side — admission이 실행된 canonical base
  ├─ H = PR.head.sha                  # PR head side — certificate의 귀속 대상
  └─ PR.base.ref == "main"
M_PR = PR.merge_commit_sha            # merge commit M
GET /commits/{M_PR}
  ├─ parents[0] == B                  # base side
  └─ parents[1] == H                  # head side
```

**"head_sha == merge commit" 주장 실증 반박 (v2)**: 본 repo의 run
`35414954344`·`35369567925`에서 `workflow_run.head_sha`는 **merge commit이
아니라 PR head commit**과 동일함을 실측 — v8의 "head_sha == merge commit M"
정정은 사실 오류였고, `M = workflow_run.head_sha` 유도식은 잘못된 M을
산출한다. v2에서는 M을 오직 PR API의 `merge_commit_sha`(M_PR)에서 유도하고,
2-parent 구조(parent1==B, parent2==H)로 merge shape을 강제 검증한다.

**M source 고정 (v2)**: M은 **오직 PR API의 `merge_commit_sha`**에서만 취득.
`github.sha`는 publisher에서 M으로 **사용 금지**, `workflow_run.head_sha`도
M source로 사용 금지(그 값은 H). E-B에서 `github.sha` 사용 0건을 grep으로
확인한다.

---

## 4. identity 분리 — semantic identity ≠ provenance

```
certificate semantic identity  = (B, H) + 기존 attest binding 필드
                                 (baseSha·headSha·headTreeDigest·policyDigest·
                                  scopeDigest·evidenceDigest·envDigest·
                                  toolchainIdentity·prNumber — 스키마 무변)
provenance (귀속·추적 전용)      = M, run_id, run_attempt, artifact identity,
                                 witness digest
```

- **certificate에 runId/runAttempt/M을 넣지 않는다** — semantic identity는 "무엇이
  증명됐는가"만, "어떤 실행이 만들었는가"는 provenance가 담당. 동일 (B,H) 재실행
  시 provenance만 변함 — cert representation은 실행에 무관하게 동일. runId/
  runAttempt를 cert에 넣으면 동일 (B,H) 재실행 시 representation이 변해 canonical
  identity가 깨진다.
- **E-A 동등성 모순 제거**: full attest와 witness→sign의 동일 canonical cert JSON
  golden은 cert 표현에 실행 정보가 없으므로 모순 없이 성립. provenance는
  witness(무서명 bundle)와 ledger commit 메타데이터(cert JSON 외부)에만 존재.
- provenance의 신뢰는 서명이 아니라 **publisher의 검증 체인**((2b)+(2c)+(3))이
  제공.

---

## 5. publisher activation guard — 3조건

publisher job의 첫 단계 — 아래 3조건이 **모두** 성립해야 후속 검증 진행,
하나라도 불성립 시 즉시 fail-closed:

```
workflow_run.event       == pull_request            # admission은 PR 실행만 mint 유발
workflow_run.conclusion  == success                 # 실패·취소 run은 mint 유발 불가
workflow_run.path        == admission_producer.yml  # path-level 일치 (워크플로 이름이 아닌 파일 경로)
```

- `workflows:` 트리거 필터는 **이름 기반**이라 동명 위workflow를 허용하므로,
  activation은 반드시 **path**로 재확인 — 이것이 (2a)의 blob sha 대조와 함께
  위workflow 차단의 첫 경계.

---

## 6. PR identity — GitHub PR API = trusted source (v2 개정)

**M source 개정 (실증)**: v8의 "`workflow_run.head_sha` = merge commit" 주장은
**실증적으로 반박됨** — 본 repo의 run `35414954344`·`35369567925`에서
`workflow_run.head_sha`는 **PR head commit과 동일**(merge commit이 아님)하다.
따라서 v8의 mbh 유도식(`M = workflow_run.head_sha`, `B = M.parent1`,
`H = M.parent2`)은 **잘못된 M을 산출**한다(원래 목적은 M=merge ref를 얻는 것).
이를 대체하는 v2 체인(단일 구현 — `commits/{M}/pulls` 호출 **전면 삭제**):

```
RUN_ID = github.event.workflow_run.id
runObj  = GET /actions/runs/{RUN_ID}        # actions: read 필요 — 부여됨
  ├─ runObj.event == "pull_request" ∧ conclusion == "success"
  │    ∧ path == ".github/workflows/admission_producer.yml"   (재확인)
  ├─ runObj.pull_requests[] 개수 == 1        # 0·다수 → fail-closed (명확한 이유 출력)
  └─ runObj.head_sha == H                    # head_sha가 PR head임을 교차 확인
N = runObj.pull_requests[0].number
PR = GET /pulls/{N}                          # trusted source — 유일한 경로
  ├─ H = PR.head.sha
  ├─ B = PR.base.sha
  └─ PR.base.ref == "main"                   # base 이동/비main → fail-closed
M_PR = PR.merge_commit_sha
GET /commits/{M_PR}
  ├─ parents 개수 == 2                       # merge shape (아니면 fail-closed)
  ├─ parents[0] == B                         # base side
  └─ parents[1] == H                         # head side
```

- **용어 분리**: PR API가 알려주는 merge commit을 **M_PR**이라 명명하고,
  witness가 `provenance.mergeSha`에 기록한 값을 **M_WITNESS**라 명명한다.
  artifact 대조는 **M_WITNESS == M_PR** 을 요구 — 불일치 시 fail-closed
  ("새 admission 필요" — M이 갱신되었으면 재admission 뒤 재mint).
- **`commits/{M}/pulls` 삭제 근거**: (a) merge commit M의 pulls 역조회는
  "1판 검증(commits/{M}/pulls) + fallback(workflow_run.pull_requests)"의
  **중복 재구성**이었고, (b) synthetic-merge commit에 대한 PR 연관
  (`commits/{M}/pulls`가 PR을 되돌려주는지)은 **플랫폼 종속 변수** — 두 경로
  병행 유지는 trust surface를 넓힌다. v2에서는 **단일 구현**: run API의
  `pull_requests[]`(run에 공식 연결된 PR) → `GET /pulls/{N}` 만 사용한다.
- witness가 기록한 PR number는 **참조 대조용**일 뿐 identity source가 아님 —
  GitHub PR API가 유일한 trusted source이며, witness 기록값과 API 결과가
  불일치해도 fail-closed.
- **`pull-requests: read` + `actions: read`를 permissions에 명시** — run API
  (actions)와 PR API(pull-requests)를 trusted source로 고정했으므로 필요
  permission을 선언한다.
- provenance 5요소 대조(2c)의 PR 항목은 이 API 결과로 확정.

**base 이동 race 실측 (부수 발견, 유지)**: #125 probe에서 `base.sha(4593a6f2) ≠
M.parent1(d39d056d6)`이 관측됨 — GitHub는 base가 이동하면 PR의 base.sha를
**현재 base tip**으로 갱신한다(#125의 checks가 #124 착지와 race). 따라서
`base.sha==B` 검증이 실패하면 "admission 도중 base가 이동했다"는 의미이며,
**fail-closed가 정확한 동작**(strict branch protection 하에 그 PR은 어차피
재검증 필요 — branch update → 새 M → 재admission). 이는 certificate
identity=(admission 당시 base, H) 고정 원칙과 일치하는 설계된 결과다.
v2에서도 동일하게 `PR.base.ref == "main"` 불일치 시 fail-closed.

---

## 7. admission identity 튜플 — notation 고정

**notation·source 고정** — `workflow_id`와 `run_id`는 서로 다른 개체이며 source를
명확히 구분한다:

```
workflow_id  = github.event.workflow_run.workflow_id  # workflow **정의** identity (GET /actions/workflows/{path}의 object id와 동일 개체)
run_id       = github.event.workflow_run.id           # **run instance** identity — workflow_id와 절대 혼동 금지
```

```
actual   = (workflow_id, path, workflow_file_blob_sha @M)   # workflow_run event가 지목한 실행 실체
expected = (trusted_path, trustedAdmissionWorkflowSha) @B   # trusted_writer_set.json@B
대조: actual.path == expected.trusted_path ∧ actual.blob_sha@M == expected.sha@B
      ∧ actual.workflow_id == GET /actions/workflows/{expected.trusted_path} 의 id
→ 하나라도 불일치 시 fail-closed
```

- **현재 main의 SHA와는 비교하지 않음** — 비교 anchor는 오직 B.
- 실행된 workflow file은 M 시점의 blob(contents API, `refs/pull/{N}/merge` 또는
  commit M의 tree)로 취득 — PR이 admission workflow를 변조했거나 동명 위workflow를
  심었으면 blob sha 불일치로 차단.

---

## 8. artifact attempt binding — 3계층

artifact retrieval 시 attempt 오인·타 run artifact 수신 차단. 셋 중 하나라도
불일치 → fail-closed:

```
(i)   run-scoped API: GET runs/{run_id}/artifacts        — run_id 스코프 내에서만 조회
(ii)  trusted-name:   "witness-{run_attempt}" 일치       — attempt 포함 결정론적 이름
(iii) manifest:       내부 run_id·run_attempt·M·H·PR == (2b)(2c) 대조값
```

---

## 9. signature ≠ authority — 서명키 = 공개 상수 (판정 근거)

**선결 질문 실측 판정 — "Ed25519 private key는 어디서 오는가?"**:

- **키 = 소스 하드코딩 공개 상수, secret 아님**: `AttestationDomainSeed* =
  "axiom-attestation-v1-sha256"` (`src/infrastructure/certificate_attestation.nim:185`,
  주석 "PUBLIC by design" `:23`). `keyPairForAttestation() = createKeypair(sha256(seed))`
  (`:223-226`), 공개키도 상수(`:192-193`), 검증은 상수 literal만(`:281`).
  env/secret 경로 0건. **python(pynacl) 독립 재유도로 실제 유도 공개키 == 코드
  상수(`7e37ae83…`) 일치 증명 통과 (2026-09-18)**.
- **signature ≠ authority**: 서명은 certificate의 identity·변조 방지(재계산 일치
  증명)일 뿐. **실제 mint authority = certificate ref(`refs/heads/axiom/certificates`)
  publication 권한** — append-only ledger + FF-CAS(force=false,
  `src/verification/ledger_side_ref.nim:348-397`)를 소유한 workflow가 곧
  authority이며, 본 설계에서는 그것이 `certificate-mint.yml` 하나뿐임을 기존
  TrustedWriterSet 동등성 게이트로 강제한다.
- D6 중복 fail-closed(`src/cli/cert_cli.nim:737-742, 770-786`) = authority의 거부
  규칙 → publisher 측 실행.

---

## 10. publisher permissions — top-level 3-scope (v2 개정)

**v2 현실**: `tools/ci/verify_trusted_writer_set.sh`는 **top-level 권한 블록만**
스캔한다(ADR-0022 §4 exact equality — 관측되는 contents:write 보유자가 선언된
trusted writer와 정확히 일치해야 함). 따라서 publisher workflow의
`contents: write`는 **top-level에 선언**되어야 한다(이 파일이 TrustedWriterSet의
유일 멤버이기 때문). 이전 v12의 "job-level write + top-level read-only" 구상은
게이트의 top-level 스캔과 충돌하므로 **폐기**.

permissions (top-level, publisher job 동일 3-scope) — 외 0건:

```
permissions:
  contents: write     # ledger-append (publication) — top-level 필수 (게이트 스캔)
  actions: read       # run API / artifact 다운로드 (actions: read 부여됨)
  # checks: read      # 삭제 — 3-scope 최소화 (zero /checks calls)
  pull-requests: read # PR API trusted source (v2 §6)
```

- **3-scope 최소화**: `checks: read`는 삭제 — 전체 workflow에서 `/checks` 호출
  **0건**이며 불필요한 scope를 유지하지 않는다.

**P0 — runner 격리(ephemeral/JIT 필수)**: certificate-mint는 org runner group
**axiom-publisher**에서 실행한다. runner group은 **workflow-restricted**
(certificate-mint.yml@refs/heads/main만 허용)이며, runner는 반드시
**ephemeral/JIT**여야 한다 — **job당 1회 등록 → 종료 후 deregister**.
**영구 특권 runner(항상 실행, contents: write 권한 workflow에 재사용)는 금지**.
이 제약은 기존 `jit_supervisor` 도구로 강제하며(신규 runner manager 없음)
P0 우선순위로 이행한다.

---

## 11. CLI 서브명령 분리 — Phase 1 구현 예정

현행 `ax cert attest`는 커널 a–f + 서명 g + D6(네트워크) + journal을 단일
프로세스로 수행한다(`attestation_orchestrator.nim:419-436`) — unsigned witness·
sign-only 표면 부재. Phase 1에서 아래 서브명령 2개를 신설한다:

```
ax cert attest --witness-only   # 커널 a–f → unsigned witness + provenance 기록
                                # 서명·journal·네트워크 0
ax cert attest --sign <witness> # 검증 → 정규화 → canonical cert 재구성 → 서명 → journal
                                # 커널·네트워크 0, cert 표현에 runId/runAttempt/M 미포함
```

- **기존 attest 전체 경로는 D9 수동 ceremony용으로 유지**한다.
- publication은 기존 `ledger-append` 재사용(`cert_cli.nim:823-853`).

---

## 12. Trust boundary 확장 — 확정 요약 (v12)

본 문서가 승인받은 trust boundary 확장은 정확히 아래 값이다:

> **"certificate mint + ledger publication"의 production authority를 D9 operator에서
> publisher(`certificate-mint.yml`, workflow_run privilege boundary)로 이전한다.**
> - witness tier = 비권한(contents:read), 실행 원천 = 완전 B 고정 — 범위 =
>   Axiom-controlled computation(H = data 원)
> - publisher tier = untrusted computation 0건 — activation guard(§5) · admission
>   identity 튜플(§7) · PR identity(§6) · artifact attempt binding(§8) · D6 중복
>   reject 이후 정규화→서명→FF-CAS append
> - certificate semantic identity = (B,H) + 기존 attest binding 필드(스키마 무변);
>   provenance(M·run_id·run_attempt·artifact identity) = ledger commit 메타데이터
> - 서명 = 공개 상수 키로 하는 identity·변조 방지 — signature ≠ authority;
>   authority = refs/heads/axiom/certificates publication 권한(Certificate-mint.yml
>   단일 writer, TrustedWriterSet 동등성 게이트로 강제)
> - D9 operator = bootstrap/recovery 전용 재분류 유지(production 발급 금지)
> - publisher permissions = top-level `contents: write` + `actions: read` +
>   `pull-requests: read` 외 0건 (`checks: read` 삭제 — 3-scope 최소화, §10);
>   runner group axiom-publisher (ephemeral/JIT 필수, 영구 특권 runner 금지)

권한 부여 실행(workflow 작성·permissions 변경·TrustedWriterSet 재정의)은 S4
**Phase 1**에서 수행한다.

---

## 13. 1판 질문의 해소 대응

1판(PR #125)의 5개 질문·Open Questions에 대한 v12 확정은 아래와 같다:

| 1판 항목 | v12 확정 |
|---|---|
| Q1 mint authority | **확정**: publisher(`certificate-mint.yml`) 단일 — C1b 채택. D9 = bootstrap/recovery 전용 유지 |
| Q2 mint precondition | **확정**: admission PASS(5 checks, activation guard §5) + witness 커널 실행(비권한 tier) — publisher의 untrusted computation 0으로 구현 |
| Q3 subject attribution | **확정 (v2)**: PR head H(= PR.head.sha). v8의 "head_sha==H 가정 오류" 주장은 실증 반박 — 본 repo run 35414954344·35369567925에서 workflow_run.head_sha == PR head H (merge commit 아님) |
| Q4 publication writer | **확정**: publisher 겸임(C4a) — FF-CAS force:false, ledger 단일 durable source |
| Q5 duplicate/invalid-H | **확정**: D6 duplicate-subject predicate 이식(C5a) |
| OQ1 contents:write 부여 | **확정 (v2)**: top-level `contents: write` + `actions: read` + `pull-requests: read` 3-scope — verify_trusted_writer_set.sh가 top-level 블록만 스캔하므로 contents:write는 top-level 필수, `checks: read` 삭제(§10) |
| OQ2 mint job 위치·트리거 | **확정**: 별도 `certificate-mint.yml`, `workflow_run: [admission-producer]·completed`, branches 필터 미사용(§5 guard) |
| OQ3 attest 커널 재실행 예산 | **해소**: 커널 실행은 witness tier로 이동(비권한) — publisher 예산은 정규화·서명·발행뿐 |
| OQ4 TrustedWriterSet 재정의 | **Phase 1**: `trustedWriterWorkflow` → certificate-mint.yml, `trustedAdmissionWorkflowSha` → admission_producer.yml blob sha(착지 후 실측, atomic) — set@B anchor |
| OQ5 orchestration | **확정**: publisher 파이프라인(§2.3)이 mint→append→(native merge) 순서를 단일 실행으로 소유 |

---

## 14. 참조

- DEBT#464 — `data/debt_registry.json:3793-3805` (fix direction 전문)
- ADR-0021 — `docs/adr/0021-execution-authority.md` §D3(새 실행 표면 금지),
  §D4(subject transport, parent2 유도 불가), §D6(duplicate-subject),
  §D9(operator manual procedure — production 발급 금지)
- ADR-0022 — `docs/adr/0022-admission-artifact-authority.md` §D5(TrustedWriterSet
  단일 writer), §D6(admittedLanding/INV-13), §D8(canonical-main bind→continuity
  →accept — accept가 R(H) append 주체) + v12 정합 갱신(2026-09-18)
- 실측 — `docs/evidence/certified_landing_mint_path_2026-09-18.md` (수동 mint
  경로, ledger tip cert, DEBT#462/#465 추적 부채)
- 현재 상태 실측(2026-09-18) — `config/trusted_writer_set.json`(auto_merge.yml
  선언 유지), `tools/ci/verify_trusted_writer_set.sh`(실행 시 VIOLATION + exit 1),
  `.github/workflows/canonical-main.yml`(job-level contents:write + R(H) accept),
  `.github/workflows/admission_producer.yml`(top-level read, mint 부재)
- 서명키 실측 — `src/infrastructure/certificate_attestation.nim:23,185,192-193,223-226,281`
  (+ python(pynacl) 독립 재유도 일치 증명, 2026-09-18)
- GitHub Docs — Actions rerun은 같은 run id의 attempt 증가, 원 commit SHA·ref
  유지; workflow_run(completed) 재발화; upload-artifact v4 immutable
- 계획 SSOT — `spectre-wolverine-jessica-cruz.md` (S4 plan v12, Phase 0–2,
  Terminal Outcome, Completion Evidence E-A~E-D)

---

## 부록 A. witness evidence의 CI 생성 (plan v13 — self-reference paradox 해결)

**운영 블로커 (실측, run 35422180818, PR #137)**: witness job이
`assemble_d9: FAIL — expected exactly 1 subject record for head H, found 0`
로 실패. 원인 = **git self-reference paradox**: 커밋은 자기 자신의 hash를
바인딩하는 레코드를 tree 안에 담을 수 없다. 수동 ceremony가 성공한 것은
레코드가 커밋 **밖**(local vault)에서 생성된 뒤 무관한 PR로 커밋되었기 때문
(실증: subject `152607ea…`는 headSha `a1f525f9…`를 바인딩하지만 커밋
`a1f525f9`의 tree에는 그 레코드가 없다). 착지된 전사(transcription)가
바인딩 방향을 반대로 옮겼다 — candidate tree에서 레코드를 찾는 구조가
성립할 수 없다.

**정정된 설계 (plan v13, 사용자 수정 문구: "기존 D9 evidence schema → 기계적으로 생성 →
witness artifact, schema는 변경하지 않고 producer만 자동화")**:

1. **main-pinned evidence draft** — `data/certification/evidence-draft.json`:
   CONTENT 필드만(leanSource·smtlib2·funcSource·funcPath·funcName·
   toolchainIdentity), head-specific 바인딩 0건. ceremony 레코드
   `152607ea…`에서 기계 추출(byte-equal 검증 완료 — funcSource는 여전히
   `src/verification/continuity_probe.nim`과 일치, policy/scope digest도 B=main과
   일치). draft는 `data/trusted/` 밖 — kernel 소비 레코드가 아니다.
2. **CI-시간 바인딩 충전** (`tools/ci/assemble_d9_evidence.sh` 재작성):
   draft + H tree(자료만) → 완전한 evidence record(schema
   `axiom.attestation.evidence.v1` **불변**)를 B workspace에 생성:
   prNumber·prHeadSha(=H)·policyDigest(sha256 B `config/policy/merge_admission.json`)·
   scopeDigest(sha256 B `data/verification_scope.lock`)·envDigest(아래)·
   toolchainIdentity(draft)·subjectId placeholder(64-hex 0, register 후 재작성).
   fail-closed: draft 부재·funcSource≠`git show H:funcPath`·digest 계산 불가 → exit≠0.
3. **subject-register** — `ax cert subject-register --base B --head-tree <H
   tree OID (git -C _candidate rev-parse HEAD^{tree}) --pr N --evidence <staged>`:
   subjectId를 6-필드 wire(baseSha·prHeadSha·headTreeDigest·policyDigest·
   scopeDigest·evidenceDigest)에서 **재유도**(artifact의 subjectId 불신), append-only
   저장. 이후 staged evidence의 subjectId를 등록된 값으로 재작성 —
   `evidenceBundleWire`는 4-필드(funcSource·funcName·leanSource·smtlib2)만
   해시하므로 subjectId 재작성은 evidenceDigest를 불안정하게 만들지 않는다.
4. **attest --witness-only** — 기존 체인(a–f) 그대로, ref=H. stage-a는 저장소
   subject reload + evidence.subjectId==store.subjectId 요구 — 위 fill이 정확히
   이 보장을 만든다.
5. **mint 인터페이스 불변** — witness schema·provenance 필드(M/B/H/PR/run_id/
   run_attempt)·artifact name(`witness-{run_attempt}`)·manifest 필드(runId·
   runAttempt·mergeSha·toolCommit·prHeadSha·prNumber·witnessDigest) 모두
   그대로 — certificate-mint.yml은 변경하지 않는다. 로컬 검증: 생성 witness에
   `attest --sign` 통과(certificate 재구성 OK).

**self-reference 해소의 본질**: draft는 head와 무관한 content만 보유, head
바인딩(subjectId·headSha·tree digest)은 **커밋 밖 CI 실행에서** 만들어짐 → "커밋이
자기 hash를 담는다"는 순환 불가. evidenceBundleWire가 4-필드만 해시하는 사실(§0.6,
`:146`)이 이를 가능하게 한다 — head/schema/digest 필드는 digest 대상이 아니다.

**envDigest 기록 결정**: attest 체인 어디서도 envDigest를 재유도·비교하지 않는다
(64-hex 형식 검증 + stage-b 이후 certificate로 운반만, runbook §4 "env identity
wire"). deriving function이 코드에 없으므로 CI는 **결정론적 identity digest**를
기록한다: `sha256Hex("axiom-attestation-env-v1|" + toolchainIdentity)`. 값은
pinned toolchain에 대해 안정적이며, draft의 toolchainIdentity가 비정형이면
fail-closed.

**적용 상태 (실측, 2026-09-19)**: bootstrap 착지 = PR #138 (native merge,
main `8c997fd52`, admission run 35424566586). required 5 checks 전부 green;
witness job은 설계대로 fail-closed red(`draft missing from B`) — 이 착지가
draft를 main에 최초로 심는 bootstrap이기 때문. main에 draft 존재
(blob `66aa159e…`) + `trustedAdmissionWorkflowSha` `04796ed9…` ==
main의 admission-producer.yml blob 정합. **이후 candidate부터 본 부록의
CI witness generation path가 첫 실전으로 발동되며, admission success가
certificate-mint를 발화시킨다.**

**첫 witness full generation 실측 (2026-09-19)**: PR #139 admission run
35427369581 — ircheck 수정(`lake build ircheck` 명시 + binary-existence
fail-closed) 후 witness 전 단계(assemble → register → fill → attest
--witness-only → manifest → upload) 최초 완주. mint run 35428347127은
activation guard까지 통과한 최초 실발화였으나 publisher host의 jq 결측으로
step (1) fail-closed(jq는 bootstrap_runner.sh DEPS 누락 — host에 수동 설치,
`bootstrap_runner.sh` 보완은 별도 항목).

**mint (2a) blob@M 결함 실측 확정 + 수정 (PR #140 착지)**: runs
35428347127/35429914714/35433068452 — `blob@M 654147c8… != pin 2d6ab701…`
3회 반복. 원인 = `blob_resp="$(curl …)"` 명령 치환의 trailing-newline 제거
(개행 포함 hash `2d6ab701…` == pin / 개행 제거 hash `654147c8…` — 로컬
재현으로 확정). 수정(4f0626780): curl을 temp 파일로 받아 `git hash-object`
직접 소비. **workflow_run은 기본 브랜치(main)의 workflow 코드로 실행되므로
수정 설치 자체가 bootstrap이며, 다음 candidate가 첫 mint 고객이다.**

**mint (2a) workflow-id crosscheck 결함 + 수정 (PR #141 착지)**: run
35434811432 — blob@M 검증(개행-보존)은 통과했으나
`GET /actions/workflows/{repo-path}` 404. GitHub의 Get-a-workflow
엔드포인트는 **파일명**만 받음(로컬 재현: `admission_producer.yml` → 200,
definition id `359582573` == event 값). 수정(d356cc202): 파일명 추출 후
호출. run 35436263608로 수정 설치 전 bootstrap red 재확인 → 본 PR
(#141) 착지로 두 결함 수정 모두 main 상주. **다음 candidate가 결함 없는
mint의 첫 고객이다.**
