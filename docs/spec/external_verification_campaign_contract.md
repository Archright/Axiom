# 외부검증 캠페인 계약 (S4/S5) — External Verification Campaign Contract

> **Status**: Committed campaign contract — S4(외부검증 실행)/S5(증거·판정) 캠페인의 식별자·결과 분류·재현성·Zero-Footprint·공개 실행 어댑터·증거 내구성 규칙. 구현에 앞선 문서 선행(AGENTS.md §0.5).
> **Created**: 2026-11-09
> **AGENTS.md reference**: §0.12 (제품 계약 선행 — 본 계약이 승인 계획 Phase 0), §0.9 (극장 금지 — 판정 없는 green·부분 rerun 승격 금지), §0.9b (Triple-Closure), §0.3 (신뢰 경계 — 워크플로 env 권위), §2.5 (coherent generation — 부분 rerun 금지의 원리), §2.3 (merge-admission authority는 GitHub), §4 (GUARDIAN)
> **Related**: [productization_contract.md](./productization_contract.md) (§1b 배포·재현성 결속·exit 5-state·§6 canonical projection), [byo_agent_proposition_contract.md](./byo_agent_proposition_contract.md) (§5 신뢰 경계·§7 Zero-Footprint·§9 2-Job·§10 접근성), [bug_verdict_glossary.md](./bug_verdict_glossary.md) (§2.2 판정 어휘 무신규 원칙), [verifier_build_identity.md](./verifier_build_identity.md) (engineBuildId 64-hex/unmeasured·cert_reconcile fail-closed), [nim_libp2p_bytesview_slice_contract.md](./nim_libp2p_bytesview_slice_contract.md) (§4 out-of-tree replay·§6 7조건 수용 선례), [nim_libp2p_ci_runs_audit_2026-11-09.md](../evidence/nim_libp2p_ci_runs_audit_2026-11-09.md) (§8 이력 분류의 관측 정본)
> **캠페인 승인 근거**: 승인된 계획 Phase 0 — 본 문서는 그 산출물이다(계약이 구현보다 선행한다, §0.12).

---

## §1. 캠페인 매니페스트 — 7 식별자

캠페인은 **식별자 7개**로 자신을 고정한다. 식별자는 캠페인의 **논리적 입력 정체성**이며, 한 캠페인 안에서는 불변이어야 한다(불일치 관측 = §2 `INPUT_MISMATCH`).

| 식별자 | 정의 | 스키마 | 첫 캠페인 고정값 |
|---|---|---|---|
| `PROJECT_UNDER_TEST` | 검증 대상 프로젝트의 정본 저장소 slug(owner/repo) — 포크가 아니라 검증 대상 그 자체 | `owner/repo`(공개 GitHub slug) | `iftech/nim-libp2p` |
| `PROJECT_REVISION` | 검증 대상 저장소의 고정 커밋 | 40-hex 전체 SHA | `a130a7f32219909bdcda14b7f1e64d0804fc832c` |
| `AXIOM_REVISION` | 검증에 사용하는 Axiom 제품 정체성 — 정본은 axiom-cli **Release manifest**(버전·원본 소스 커밋·빌드 SHA·바이너리 sha256, productization §1b) | release 태그(=`axiom.nimble` 버전) + manifest가 부여하는 source commit/binary sha256 결속 | `v0.6.0` |
| `AXIOM_CONFIGURATION` | 실행 구성 — 결정론에 영향을 주는 실행 인자·환경 고정 | 구성 요소를 나열한 문자열(아래 예시) | `axiom-cli:v0.6.0; AXIOM_PROVE_WORKERS=1; replay-dep-pins=byo-agent-4pins; exit-digest:cmp` |
| `TOOLCHAIN_IDENTITY` | 검증 실행 툴체인의 고정 버전 triple | `Nim <ver>/Z3 <ver>/Lean <ver>`(제품 계약 런타임 툴체인, productization §1b — 직접 핀 다운로드, **choosenim 불사용**) | `Nim 2.2.10/Z3 4.13.3/Lean 4.33.0` |
| `VERIFICATION_SCOPE` | 이 캠페인이 검증하는 명제 범위 — 커밋된 spec 레지스트리 식별자 | spec registry id(bytesview 슬라이스 계약의 Spec registry 참조) | `SPEC-LIBP2P-BV-SLICE` |
| `EXPERIMENT_ID` | 캠페인 실험 식별자(증거 문서·관측 기록의 결속 키) | `-`·영숫자로 구성된 실험 id | `external-verification-campaign-001` |

**고객 실행 저장소**(캠페인이 실제로 실행되는 GitHub 저장소)는 식별자가 **아니다**: `Archright/nim-libp2p`. 이는 §5 어댑터가 호출되는 물리적 위치일 뿐이며, 검증 대상(`PROJECT_UNDER_TEST`/`PROJECT_REVISION`)과는 별개다(byo-agent §5 신뢰 경계: 검증 대상 신원은 워크플로 env가 선언한다).

**실행 메타데이터는 식별자와 별도로 관리한다**(식별자 = 논리적 입력 정체성, 메타데이터 = 관측된 실행 사실):

- `github.run_id` / `github.run_attempt` — §6 재실행 규칙의 관측 대상
- 러너 이미지 **관측치** — ImageOS·ImageVersion 등, 러너 env에서 실측한 값(선언 아님)
- 호출 workflow SHA — caller가 `uses:`로 핀한 전체 SHA
- 고객 실행 저장소 slug — 위 정의

메타데이터는 캠페인 증거(§7)에 기록되지만, 캠페인 정체성을 바꾸지 않는다. 메타데이터 불일치가 결과 분류에 들어가는 경로는 §2 `ENVIRONMENT_MISMATCH`(환경 관측)와 §3(실행 환경 동일성)뿐이다.

**예시 — 캠페인 매니페스트 JSON**(증거 문서·`verify-record.json`이 운반하는 형태):

```json
{
  "schemaVersion": "axiom.campaign.v1",
  "identifiers": {
    "PROJECT_UNDER_TEST": "iftech/nim-libp2p",
    "PROJECT_REVISION": "a130a7f32219909bdcda14b7f1e64d0804fc832c",
    "AXIOM_REVISION": "v0.6.0",
    "AXIOM_CONFIGURATION": "axiom-cli:v0.6.0; AXIOM_PROVE_WORKERS=1; replay-dep-pins=byo-agent-4pins; exit-digest:cmp",
    "TOOLCHAIN_IDENTITY": "Nim 2.2.10/Z3 4.13.3/Lean 4.33.0",
    "VERIFICATION_SCOPE": "SPEC-LIBP2P-BV-SLICE",
    "EXPERIMENT_ID": "external-verification-campaign-001"
  },
  "executionMetadata": {
    "customerExecutionRepository": "Archright/nim-libp2p",
    "runId": null, "runAttempt": null,
    "runnerImage": null, "callerWorkflowSha": null
  }
}
```

`schemaVersion: axiom.campaign.v1`은 문서 계약 식별자일 뿐 — 새 판정 enum·producer를 만들지 않는다(§2 HARD RULE).

## §2. 결과 분류 — 전사·fail-closed (HARD RULE)

캠페인의 결과는 **기존 어휘만으로** 분류한다. 캠페인 클래스는 다음 기존 판정 표면 위의 **읽기 전용 투영**이며, 새 enum·새 producer·새 판정 값을 만들지 않는다(bug_verdict_glossary §1 HARD RULE과 동일 성격 — docs-only 계약):

- **CLI exit 0–4** — productization §338-377 v1 CLI Exit-State Contract(5-state: 0 VERIFIED · 1 VERIFICATION_FAILED · 2 INTERNAL_ERROR · 3 INVALID_INPUT · 4 NOT_CURRENT; uncaught signal = out-of-contract failure, 5-state 밖)
- **`propositionVerdict`** 3값 — `DISPROVED | NOT_DISPROVED | UNKNOWN`(bug_verdict_glossary §2.2)
- **`statusCounts` 9키** — `verified, inductive_valid, failed, skipped, timeout, blocked, vacuous, pre_sieved, reused`(`src/cli/wf_render.nim`)
- **`OrchestrationNodeStatus` 10값** — `orchestrationVerified, orchestrationInductiveValid, orchestrationProofFailed, orchestrationTimedOut, orchestrationBlocked, orchestrationVacuousContradiction, orchestrationPreSievedUnverifiable, orchestrationSkippedByTheory, orchestrationNotVerifiable, orchestrationNoObligation`(`src/core/orchestrator/orchestrator_report_types.nim:8-18`)

**캠페인 결과 클래스(11개, 폐쇄 집합)**:

| 클래스 | 의미 | 진입 조건(기존 어휘 관측) |
|---|---|---|
| `PROVED_REPRODUCIBLE` | 두 job 모두 검증 완료·명제 부정 안 됨이 재현됨 | 두 job exit `0` ∧ `propositionVerdict = NOT_DISPROVED` ∧ `statusCounts.verified > 0`, §3 재현성·§4 Zero-Footprint·vacuous 가드 전부 성립 |
| `DISPROVED_REPRODUCIBLE` | 두 job 모두 확정 반증이 재현됨 | 두 job exit `1`(VERIFICATION_FAILURE — 확정 disproof는 결과이지 오류가 아니다) ∧ `propositionVerdict = DISPROVED`, §3·§4·가드 전부 성립 |
| `REFUSAL_REPRODUCIBLE` | 두 job 모두 동일한 정직한 거절이 재현됨(검증 주장 없음) | 두 job이 사유 폐쇄 집합 기반 동일 거절로 종료(exit `3` INPUT_REJECTED 4종 사유 동일, 또는 INCAPABLE 사유 동일·`attempted=false` rollup 동일) — **판정 없는 green 아님**: 결과는 "거절이 재현됐다"이지 주체 안전성이 아니다 |
| `DETERMINISM_MISMATCH` | 같은 입력·같은 환경에서 판정 회계가 다름 | §3 4-tuple 동일 ∧ 환경 동일인데 `canonicalRunDigest` `cmp` 불일치 또는 payload verdict/claim 행 불등가 |
| `ZERO_FOOTPRINT_VIOLATION` | 주체 트리가 오염됨 | §4 tree hash pre/post 불일치, porcelain 비공백, state가 주체 트리 내부에 기록됨 중 하나 |
| `VACUOUS_BLOCKED` | 판정 없는 green — 캠페인이 그린을 주장할 자격이 없음 | vacuous 가드(§3) 실패: `engineBuildId == "unmeasured"`(64-hex 아님) 또는 판정 행 부재(verdict 행 0개, `verified=0` green — byo-agent §8 첫 selftest 결함 선례·DEBT#513) |
| `ENVIRONMENT_MISMATCH` | 두 job의 실행 환경 관측이 다름 | §3 실행 환경 동일성(러너 이미지 관측치·도구체인 버전 관측) 불일치 |
| `INPUT_MISMATCH` | 캠페인 입력 정체성이 결속되지 않음 | §3 4-tuple 불일치(proposals sha256·subjectCommit·axiomCommit), 매니페스트 식별자와 관측된 입력의 불일치, `subject.*` 클레임-워크플로 env 불일치(SUBJECT_MISMATCH, byo-agent §5·§6) |
| `EXECUTION_FAILURE` | 검증이 실행 자체에 실패함 | 5-state 밖 신호(signal=139 등 out-of-contract failure), 워크플로 인프라 실패로 state 미영속 — exit 2(INTERNAL_ERROR 관측) 포함 |
| `CONTRADICTION` | 관측 조합이 분류표상 모순 | 예: exit `0`인데 `DISPROVED` 판정 행 존재, 동일 digest인데 verdict 행 불일치, exit `1`인데 failed 노드·timeout 노드 전부 0이면서 verified 0 — 어느 클래스의 진입 조건도 정합으로 성립하지 않는 조합 |
| `UNCLASSIFIED` | 위 어느 조합에도 해당하지 않는 관측 | 분류 잔여(fail-closed) — 조사 대상이지 성공 해석 금지 |

**원칙 (HARD RULE)**:

1. **전사(totality)**: 모든 관측 조합은 정확히 하나의 클래스로 분류된다. 분류는 표의 진입 조건을 우선순위(불일치·오염·가드 실패 계열 → 실행 실패 → 재현 성공 계열 → `CONTRADICTION`/`UNCLASSIFIED` 순)로 평가해 첫 정합 하나만 취한다. 두 클래스가 동시에 성립하는 관측은 그 자체로 분류표 모순이며 `CONTRADICTION`으로 기록한다.
2. **미인식·모순 = 성공 해석 금지**: `UNCLASSIFIED`·`CONTRADICTION`은 어떤 긍정 표현(“사실상 통과”, “재현으로 보아 성공”)으로도 승격되지 않는다(§0.9 극장 금지).
3. **캠페인 수용(그린)은 `PROVED_REPRODUCIBLE`·`DISPROVED_REPRODUCIBLE`·`REFUSAL_REPRODUCIBLE` 세 클래스뿐이다.** 나머지 8개는 전부 캠페인 실패이며, `DETERMINISM_MISMATCH`·`VACUOUS_BLOCKED`·`CONTRADICTION`·`UNCLASSIFIED`는 원인 조사 후 **새 캠페인 디스패치**(§6)로만 재시도한다.

exit 축과 캠페인 클래스 축은 다르다: exit `1`(VERIFICATION_FAILURE)은 확정 disproof라 **정상 캠페인 결과**다(bytesview §6 수용 조항 1의 선례 — “결함은 확정 disproof이지 패스가 아니다”). 반대로 exit `0`은 “런 완료”일 뿐 전명제 증명이 아니므로(byo-agent §8 — 프로그램 실행 성공 ≠ 검증 성공), `PROVED_REPRODUCIBLE`은 판정 행·가드가 함께 성립할 때만 취한다.

## §3. 재현성 비교 의미론 — 같은 run의 독립 2 job

캠페인의 재현성 단위는 **같은 workflow run 안의 독립 2 job**이다. 각 job은 신선한 VM(별도 러너, 콜드 스토어)에서 동일 절차로 프로비저닝·실행된다 — 로컬 A/B 2회 실행 선례(bytesview §6 조항 5 “Two cold runs agree”, productization §1b “동일 입력 2회 실행”)의 CI 경로 버전.

재현성 판정은 다음 전부가 성립할 때 통과다:

1. **4-tuple 결속 동일**: (proposals sha256 · subject 커밋 · axiom 커밋 · canonicalRunDigest)가 두 job에서 동일 — productization §1b 재현성 결속 (a)의 관측 계약이 그대로 캠페인의 정본이다.
2. **canonicalRunDigest `cmp`**: 두 job이 산출한 canonicalRunDigest를 기계 비교(`cmp`)해 바이트 동일. 단, canonicalRunDigest는 **판정 회계만 해시**한다(productization §1b:46 — “canonicalRunDigest는 판정 회계(runAccounting+executionEvidence+runOutcome)만 해시 — dep·툴체인·proposals 바이트를 직접 결속하지 않는다”). 그러므로 digest 동일만으로 재현성을 주장하지 않고 아래 3–5를 함께 관측한다.
3. **payload 등가**: verdict 행·claim 행이 의미상 등가(§239–243의 semantic equality 정의 — raw byte equality 아님). 정규화·volatile 제외 규칙은 **productization §239–243이 정본이며 본 계약은 새 정의를 만들지 않는다**: 최상위 `runtimeMeta` 전체·트리 전체 volatile 키 재귀 제외·객체 키 정렬 직렬화·단일 구현 `core/utils/canonical_projection.nim::canonicalProjectionHash`.
4. **vacuous 가드**: (a) `engineBuildId`가 64-hex 소문자 canonical digest여야 한다 — 리터럴 `"unmeasured"`인 경우 캠페인은 `VACUOUS_BLOCKED`(verifier_build_identity — `admissibleVerifierBuildId`는 64-char lowercase-hex만 admissible로 인정, 그 외는 결코 stale-but-plausible identity가 아니라 "unmeasured"; cert_reconcile의 journal admission pin은 동일 fail-closed 설계다). (b) 판정 행이 존재해야 한다 — verdict 행 0개의 green은 판정 없는 green이므로 `VACUOUS_BLOCKED`.
5. **실행 환경 동일성**: 두 러너의 **실제 관측치**를 비교한다 — 러너 env에서 실측한 `ImageOS`·`ImageVersion`, "Set up job" 단계 로그에 기록된 이미지 정보, 도구체인 버전 관측(`nim --version`·`z3 --version`·Lean/elan 버전 출력)이 전부 동일해야 한다. 어느 하나라도 불일치면 `ENVIRONMENT_MISMATCH`(§2) — 실패 취급, 재현성 통과 아님.

4-tuple 불일치·환경 관측 불일치·digest 불일치는 각각 §2의 `INPUT_MISMATCH`·`ENVIRONMENT_MISMATCH`·`DETERMINISM_MISMATCH`로 분류된다(분류 우선순위는 §2 원칙 1).

## §4. Zero-Footprint — 주체 트리 불변 (HARD RULE)

캠페인의 모든 job은 주체(under-test) 저장소에 대해 다음을 유지한다(bytesview §1 "READ-ONLY subject"·byo-agent §7과 동일 계약):

- **주체 tree hash 불변**: job 시작·종료 시점의 `git -C <subject> rev-parse HEAD^{tree}`가 동일해야 한다(pre/post 관측 기록).
- **porcelain 상시 공백**: `git -C <subject> status --porcelain`이 실행 전·중(replay 후)·후 전 시점에서 공백이어야 한다 — 주체 트리에 어떤 파일도 쓰지 않는다.
- **state는 주체 밖**: `AXIOM_STATE_DIR=$RUNNER_TEMP`(러너 휘발 경로)로 고정 — 주체 트리 내부에 state가 기록되면 `ZERO_FOOTPRINT_VIOLATION`.
- **replay OUT-OF-TREE**: 재생(replay) 컴파일은 주체 트리 밖 scratch 경로(nimcache·outdir)에서 수행한다 — bytesview §4의 out-of-tree 재생 설계와 §6 수용 조항들(주체 핀 pre/post 동일·모듈 sha256 불변·`worktreeStable==true`·2 콜드 런 동의·동일 고정 환경의 7조건)이 선례다.

위 관측 전부는 `verify-record.json`(§5)에 기계 판독 형태로 기록되며, 증거 문서(§7)에 요약된다.

## §5. 공개 실행 어댑터 계약 — `ax-verify.yml`

**위치**: `Archright/axiom-cli`(공개 배포 저장소, productization §1b binary distribution)의 `.github/workflows/ax-verify.yml`.

**근거(접근성)**: Axiom(Archright/Axiom)은 private 저장소이므로, Axiom 소유 reusable workflow는 공개 caller가 해석할 수 없다 — byo-agent §10의 실증 경계: 비조직 caller는 "Unable to resolve action…"으로 실패하고, 공개 fork caller의 `uses:` 참조는 **422 "workflow was not found"**로 거부되었으며(2026-11-03 fork 실증), org access level(`organization`)은 private caller만 허용한다. 캠페인은 고객 실행 저장소에서 임의 공개 상태로 재현 가능해야 하므로(S4 외부검증), 어댑터의 소유지는 **공개 dist인 axiom-cli**여야 한다.

**인터페이스 — inputs**:

| input | 스키마 | 비고 |
|---|---|---|
| `axiom-version` | axiom-cli release 태그 | 정본은 Release manifest(§1 `AXIOM_REVISION`) — 소스 커밋·binary sha256 결속은 manifest가 부여 |
| `subject-repository` | `owner/repo` | 워크플로 env로 엔진에 선언되는 권위 값(byo-agent §5) |
| `subject-commit` | 40-hex 전체 SHA | 이외 형식은 fail-closed 거절 |
| `proposals-artifact` | artifact명 | caller Job이 업로드한 명제 문서 artifact |
| `proposals-path` | artifact 내 상대경로 | 기본 `proposals.json` |
| `replay-dep-pins` | `owner/repo <40-hex>` 행들 | **기본 = byo-agent 4핀**(`status-im/nim-serialization b5473564e80a4908cf6c5a038e4c4a6ca7de2223` · `status-im/nim-faststreams 059bc2f52546ac14b583639c33372c14b1d46fa3` · `status-im/nim-stew 4382b18f04b3c43c8409bfcd6b62063773b2bbaa` · `arnetheduck/nim-results df8113dda4c2d74d460a8fa98252b0b771bf1f27`) |
| `run-label` | 라벨 문자열 | 증거 artifact 명명에 사용(§아래) |
| `proposals-inline` | 인라인 명제 JSON | **스모크 용도** — artifact 없이 어댑터 자체 점검(아래 dispatch 전용) |

**인터페이스 — outputs**: `prove-exit` · `canonical-digest` · `engine-build-id` · `verdict-summary` · `zero-footprint-ok` · `runner-image`(§1 실행 메타데이터의 관측치 투영 — ImageOS·ImageVersion·도구체인 버전 관측 포함).

**증거 산출물**: artifact명 = `ax-verify-evidence-<proposals-artifact>-<run-label>`. 내용물은 원본 증거(로그·state·report JSON)와 **기계 판독용 `verify-record.json`**(§1 매니페스트 식별자 7 + 실행 메타데이터 + §2 분류에 필요한 관측: exit·digest·verdict 행·claim 행 요약·engineBuildId·Zero-Footprint 관측·환경 관측치 전부)이다.

**caller 계약 (HARD RULE)**:

- `permissions: contents: read` 명시 — 증거 업로드 외 쓰기 권한 없음, **시크릿 0**(AXIOM_READ_TOKEN 불필요 — axiom-cli는 공개)
- 러너 `ubuntu-24.04` 고정(러너 이미지 관측은 §3-5로 비교)
- `AXIOM_PROVE_WORKERS=1` 고정(productization §1b 재현성 결속 (a)의 항목)
- 호출은 `uses: Archright/axiom-cli/.github/workflows/ax-verify.yml@<전체 40-hex SHA>` 핀 — 모든 rerun 경로(전체 rerun·부분 rerun 모두)는 **같은 run이 처음 생성될 때의 workflow 정의 SHA로 수렴**하므로(GitHub rerun은 원본 커밋의 정의를 재실행한다), 캠페인의 2 job은 동일 어댑터 세대에서 실행된다(§2.5 coherent generation 정신).
- `workflow_dispatch` 겸용: 발행 직후 공개 dist에서 자체 스모크(`proposals-inline`) — 첫 실행이 증거가 아니라 배관 점검임을 run 기록으로 구분(§6 run_attempt 관측).

**어댑터는 판정을 만들지 않는다**: exit 전이·분류 투영·증거 기록만 수행하며, 판정 권위는 기존 exit 5-state·verdict 어휘·`projectRunOutcome` 단일 규칙(productization §338-377)에 그대로 있다(§2, AGENTS.md §0.3 신뢰 경계).

## §6. 재실행 규칙 — 부분 rerun 승격 금지 (HARD RULE)

- **부분 rerun(re-run failed jobs)의 결과는 캠페인 승격 대상이 아니다**: 부분 rerun은 원 run의 job 세대와 재시도 job 세대를 **혼합**한 상태를 만들 수 있으므로(AGENTS.md §2.5 — 활성 실행 경계의 in-place 부분 수정 금지와 같은 원리), 캠페인의 비교 단위(같은 run의 독립 2 job)가 깨진다.
- **캠페인이 실패하면 새 디스패치(새 run)로 재시도한다** — 새 run은 새 run_id를 가지며, 그 run 안에서 다시 독립 2 job이 실행된다.
- `github.run_id`·`github.run_attempt`는 각 관측에 기록된다(§1 실행 메타데이터): rerun이 발생했다는 사실 자체는 관측 사실로 남고, rerun된 시도의 결과는 승격에 쓰이지 않는다. 어떤 run이 rerun을 포함했는지는 증거 문서에 명시된다(포함 시 그 run 전체의 승격 불가).

## §7. 증거 내구성 — 90일 한계와 git 영속 기록

- **Actions artifact·로그는 기본 90일 보존 후 소멸한다**(GitHub 기본 retention) — 캠페인의 원본 증거 묶음은 이 한계를 명시적으로 전제한다.
- 캠페인 종결 시 **증거 문서를 `docs/evidence/`에 착지**해 다음을 git 영속 기록으로 남긴다: canonicalRunDigest·핵심 판정(verdict 행 요약·exit)·§1 식별자 7개 전부·실행 메타데이터(run_id·run_attempt·러너 이미지 관측치·호출 workflow SHA·고객 실행 저장소)·run 링크(Actions URL). 문서 스타일은 s2c 관측 문서 관례를 따른다(관측 계약·환경 표·기계 관측 표·판정·Non-Conclusions·착지).
- **원본 증거 묶음의 Release/저장소 보존은 선택 조항이다** — 첫 슬라이스 범위 밖이며, 필요 시 별도 계약 개정으로만 착지한다(§0.12 — 범위 확장은 계약 명시 개정으로).

## §8. "기존 6건" 이력 분류 — 정식 S4 증거 아님

2026-11-08 13:32–14:57Z에 Archright/nim-libp2p에서 실행된 nim-libp2p 런 6건은 **업스트림 상속 daily scheduled CI**(Nimbus soak·Nimbus test·Daily test all (latest dependencies)·Daily interop·Daily runnableExamples·Nimbus fleet(workflow_run, skipped))이지 **Axiom 실행이 아니다** — 관측 정본: [nim_libp2p_ci_runs_audit_2026-11-09.md](../evidence/nim_libp2p_ci_runs_audit_2026-11-09.md).

- 저장소의 Axiom 워크플로 실행 횟수는 **0회**다(관측: Actions 총 100런 전수에 Axiom/BYO 워크플로 없음; 유일 흔적은 2026-11-03의 `byo-agent-verify.yml` 추가 커밋 → 6분 뒤 revert, 실행 0회·dispatch 전용).
- 따라서 "기존 6건"에 대해 **정식 S4 증거로 승격할 대상이 없다** — 해당 런들은 캠페인 이력·진단 자료로만 보존한다. 이전 실행("사전실험")을 근거로 캠페인 성공을 전제하는 어떤 주장도 만들지 않는다(§0.9 — 관측되지 않은 것을 근거로 한 통과 표기 금지).
