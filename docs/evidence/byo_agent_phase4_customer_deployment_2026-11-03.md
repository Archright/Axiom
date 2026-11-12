# BYO-Agent Phase 4 — 고객 저장소 배포·종단 관측 (2026-11-03)

Phase 3(`PR #1228`, merge `dd31ca68e`)이 same-repo selftest로 종결한 뒤, **same-repo가 아닌 실제 고객 저장소**에서 `Job 1(고객 에이전트) → Job 2(Axiom reusable workflow) → upstream 보고` 수직 슬라이스를 관측한 실행 기록. 계약: `docs/spec/byo_agent_proposition_contract.md`(본 PR에서 §10 정정).

## 1. 배포 경로 탐색 — 공개 fork는 구조적으로 차단된다

최초 후보는 주체 저장소의 공개 fork(`Archright/nim-libp2p`, 부모 `iftech/nim-libp2p`)에 고객 workflow를 두는 것이었다. 결과:

- workflow push `cfed3871e9`(BYO 검증 workflow, `uses: Archright/Axiom/.github/workflows/byo-agent.yml@dd31ca68e…`) 후 dispatch 시도 → **422 "workflow was not found"**. 러너에서 reusable workflow가 해석되지 않아 dispatch 자체가 거부됨(실행 0회 — 아래 §5 near-miss의 잠복 결함도 함께 차단됨).

이는 우연한 실패가 아니라 플랫폼 계약이다. GitHub 공식 문서(reusable workflow 접근성 표):

| 호출자 저장소 | 접근 가능한 workflow 저장소 |
|---|---|
| `private` | `private`, `internal`, `public` |
| `public` | `public` |

- "The called workflow is stored in a private repository and the settings for that repository allow it to be accessed" — 단, org access 수준의 안내 문구는 **"Access is allowed only from private repositories"**.
- private 저장소의 actions·reusable workflows는 공개 저장소(internal 포함)에서 사용될 수 없다.

즉 Axiom이 private인 동안 **공개 저장소는 같은 조직 소속이어도 호출자가 될 수 없다**. 본 PR은 이 사실을 계약 §10에 (b')로 정정 반영했다.

fork는 즉시 원상복구했다(관측으로 남긴 것은 API 422 사실뿐):

| 항목 | 복구 후 상태(기계 확인) |
|---|---|
| fork HEAD | `70a64accd5` = Revert "ci(byoa)…" (`cfed3871e9` 원복) |
| fork secrets | 0건(2종 삭제) |
| fork 내 BYO workflow | 제거(revert) — 남은 11개 workflow는 upstream nim-libp2p 원본 |

## 2. 고객 환경 — private 조직 저장소로 적응 착지

- 저장소: `Archright/byoa-customer`(PRIVATE, org) — 모의 고객 환경. 초기 push `0845574`.
- 고객 workflow: `.github/workflows/byo-agent-verify.yml` — `workflow_dispatch` 입력 `mode ∈ {main, empty, mismatch}`:
  - **Job 1(고객 에이전트 역)**: `contents: read`만. 모드별 propositions 문서를 `printf` 한 줄 JSON으로 생성·업로드(artifact `byoa-fork-proposals`). 모델 API 키·에이전트 실행 환경은 고객 영역(§9) — 이 배포는 핀된 문서만 제출한다(A8 정직 기록, §5).
  - **Job 2(Axiom)**: `uses: Archright/Axiom/.github/workflows/byo-agent.yml@dd31ca68ec2aa55762ff5de3b70605f960a565a7` — `permissions: contents: read, issues: write`, `dry-run: mode≠main`, 시크릿 `AXIOM_READ_TOKEN`·`SUBJECT_REPORT_TOKEN` 전달.
- 주체: `iftech/nim-libp2p` @ `a130a7f32219909bdcda14b7f1e64d0804fc832c` (Phase 3과 동일 핀).
- 시크릿 프로비저닝: §2.4 자격증명 권한 — `gh auth token | gh secret set …` 파이프(파일·환경변수·스캔 없음).
- 조직 접근 수준: `PUT /repos/Archright/Axiom/actions/permissions/access -f access_level=organization` 재설정(Probe B 절차, 관측 종료 후 `none` 원복 — §7).

## 3. 배포 결함 1건 발견·수정 (near-miss, 실행 전 차단)

Job 1 run 블록의 `<<'JSON'` heredoc 종결자가 YAML block-scalar strip 후 0열이 아니었다 → bash "here-document delimited by end-of-file" 구문 오류. fork 버전에도 동일 결함이 있었으나 422가 먼저 차단(잠복). 로컬 `bash -n` + 3모드 시뮬레이션으로 검출 후 수정:

- 수정: heredoc 3개 → `printf '%s' '<한 줄 JSON>' > …` (임의 들여쓰기 안전). push `d7fff45`.
- 검증: `bash -n` PASS · main/empty/mismatch 로컬 시뮬 PASS · 검증 정체성 필드(subject·specId·target·source_location) Phase 3 selftest 입력과 byte 일치(차이는 표시용 `explanation`·`agent`뿐 — `canonicalRunDigest` 불참 필드).

## 4. main 모드 종단 관측

run: https://github.com/Archright/byoa-customer/actions/runs/41569152442 (dispatch `d7fff45`, 2026-11-03) — **workflow conclusion `success`**, Job 1 4s · Job 2 5m6s, 전 step green.

§8 exit 전이의 기계 관측(prove step 로그):

```
ax prove exit=1 — in-contract verification completion (§8); workflow continues
```

exit 1(DISPROVED)이 워크플로우 실패로 전환되지 않고 **보고 step까지 진행**했다(계약 §11 A1). Job 2 러너 관측: `GITHUB_TOKEN Permissions — Contents: read, Issues: write`(§9 권한 천장).

artifact `byoa-evidence-byoa-fork-proposals`의 `ax_proof_state.json` 실측:

| 필드 | 실측값 |
|---|---|
| `propositionVerdict` | `DISPROVED` |
| `bugAttribution` | `BUG_SUSPECTED` |
| `adoptedSpecRef.specId` | `SPEC-LIBP2P-BV-SLICE` |
| `targetSymbol` | `libp2p/utils/bytesview.nim::toOpenArray` |
| `canonicalRunDigest` | `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590` |
| `runOutcome.verdict` / `gateVerdict` | `FAIL` / `FAIL` |

prove.log: `bvSliceLenActual — replay agreed; PROPOSITION_DISPROVED payload assembled (13 records)` — 재생 의존성 핀이 외부 러너에서도 해석됨(Phase 3 수정의 이식성 실증). `runOutcome`은 판정 부정 직후의 정직 accounting(`FAIL`)으로 유지되며, 워크플로우 계층의 green은 §8 5-state 계약(판정 없는 green 아님 — 판정이 DISPROVED로 관측됨).

**canonicalRunDigest — 5관측 일치** (핀된 동일 명제·주체 SHA·Axiom SHA에서; 환경 3종 — 로컬·same-repo CI·외부 고객 CI):

| 실행 | 환경 | run |
|---|---|---|
| d1 | 로컬(worktree `aa26cef5c` + `/tmp/byoa-deps` 핀) | — |
| d2 | same-repo selftest CI(head `58c97cfbf`) | Axiom `41564010583` |
| d3 | 증거 기록 CI(head `7ae4622dd`) | Axiom `41564926465` |
| main dispatch(merge `dd31ca68e`) | same-repo main | Axiom `41567249589` |
| **Phase 4** | **외부 고객 저장소 CI(`byoa-customer` `d7fff45`)** | `41569152442` |

표시용 필드(`explanation`·`agent`)는 digest 불참(`canonicalSerialize`는 `runAccounting`+`executionEvidence`+`runOutcome`만 직렬화 — Phase 4 문서의 `explanation`이 Phase 3과 달라도 동일 digest인 것이 이를 분리해 입증).

보고 step(`dry-run=false`) 실측 — `bin/ax report --upstream --state-file … --json`:

```json
{"schemaVersion":"upstream-report-cli-result-v2","dryRun":false,"results":[
 {"targetSymbol":"libp2p/utils/bytesview.nim::toOpenArray",
  "findingKey":"48a9935e9fb76d6346afc6bca56b5fb2d8921fd55a02052371069d5ee69e4a1f",
  "status":"DUPLICATE","detail":"duplicate of ledger-recorded submission",
  "issue":{"number":3364,"url":"https://github.com/iftech/nim-libp2p/issues/3364"},
  "requestedRepository":"status-im/nim-libp2p","resolvedRepository":"iftech/nim-libp2p"}]}
```

- `DUPLICATE` — 2026-11-02 E2E가 등록한 동일 findingKey의 ledger 기록 중복으로 식별, **신규 이슈 미생성**(중복 방지 계약 작동).
- `requestedRepository: status-im → resolvedRepository: iftech` — 저장소 이전(redirect) 해결이 보고 경로에서도 작동.
- receipt 2건(`48a9935e…`·`38647549…`)이 evidence artifact에 포함됨(receipt SSOT §10).

## 5. 음성 테스트 (계약 §11 A2·A4)

두 모드 모두 **워크플로 conclusion `failure`가 기대 결과**다(§8 — exit 3은 fail-closed 실패). 관측:

| 모드 | run | prove step 관측 | 보고 step | 주체 저장소 |
|---|---|---|---|---|
| `empty` | [41570130079](https://github.com/Archright/byoa-customer/actions/runs/41570130079) | `X exit=3` — `[ERROR] NO_PROPOSALS: propositions array is empty — at least one proposition is required` | 스킵(dry-run=true) | 이슈 미생성 |
| `mismatch` | [41570134018](https://github.com/Archright/byoa-customer/actions/runs/41570134018) | `X exit=3` — `[ERROR] SUBJECT_MISMATCH: AXIOM_SUBJECT_COMMIT="a130a7f3…832c" != propositions subject.commit="0000000000000000000000000000000000000001"` | 스킵(dry-run=true) | 이슈 미생성 |

- **A4(빈 명제)**: `propositions: []`가 어떤 PASS 상태로도 표현되지 않고 `NO_PROPOSALS` exit 3으로 거부됨 — "제출된 명제만 검증했다"는 정직성 계약 작동.
- **A2(주체 조작)**: propositions 문서가 주장한 subject.commit과 워크플로 env(`AXIOM_SUBJECT_COMMIT`)의 대조가 정확히 작동 — AI 제출자가 주체 정체성을 조작해도 신뢰 경계(§5)가 원천 차단. 권한 있는 출처는 워크플로 입력(GitHub runner env)이지 제출 문서가 아니다.
- 실패한 run에서도 `Persist proof state`·`Upload evidence artifact` step은 실행되어(관측 가능성 유지) 거부 사유가 artifact에 남는다.
- 주체 저장소 이슈 baseline·사후 동일 관측: 최신 이슈 `#3377`(2026-11-02, upstream 기여자) — 본 실험 3개 run 모두 신규 이슈 미생성(main은 `DUPLICATE`, 음성 2건은 보고 스킵).

## 6. A8 정직 기록

이 배포의 propositions 문서는 Phase 3 E2E에서 실제 LLM이 작성한 것을 **핀**해 사용하며, 이 CI에서 라이브 LLM은 실행되지 않았다. 따라서 본 관측이 입증하는 것은 **배포 계층(외부 저장소 호출→검증→보고)의 무인 작동**이지 "BYO 실 에이전트 CI 내 실행"은 아니다(계약 §11 A8 — 별도 기록).

## 7. 종결 후 원복·잔여 상태

관측 종료 후 즉시 원복(Probe B 절차 — 실험 상태를 영구 구성으로 남기지 않는다):

| 항목 | 조치 | 관측(기계 확인) |
|---|---|---|
| Axiom actions access | `PUT /repos/Archright/Axiom/actions/permissions/access -f access_level=none` | `GET` → `{"access_level":"none"}` |
| byoa-customer secrets | `AXIOM_READ_TOKEN`·`SUBJECT_REPORT_TOKEN` 삭제 | `gh secret list` → 0건 |
| fork 원상복구 | §1 표 참조 | HEAD `70a64accd5`(revert)·secret 0건 |

- **고객 저장소는 dormant 상태로 보존**: workflow 파일·3개 run 관측 기록은 남지만, access가 `none`이므로 재실행 불가 — 재활성화(access 재설정 + 시크릿 재프로비저닝)는 **operator 결정**이다.
- **권한 밖 잔여(별도 사건)**: ① Axiom 공개 전환(임의 외부 저장소 호출자 개방) — 사용자 결정으로 유보(계약 §13). ② BYO 실 에이전트 CI 내 라이브 실행 — A8 별도 기록(§6). ③ 2026-12-01 무인 폴백 실계약 관측 — 기존 계약대로 대기.
- 본 배포가 입증한 것은 **배포 계층의 무인 수직 슬라이스**(외부 저장소 Job 1 → SHA-핀 Axiom 검증 → upstream 보고)이며, 그 이상의 주장(공개 개방·라이브 LLM)은 하지 않는다.

## 8. 완료 증거 (요약 표)

| 항목 | 값 |
|---|---|
| 고객 저장소 | `Archright/byoa-customer`(private org) — `d7fff45` |
| Axiom 핀 | `dd31ca68ec2aa55762ff5de3b70605f960a565a7`(PR #1228 merge) |
| 주체 핀 | `iftech/nim-libp2p` @ `a130a7f32219909bdcda14b7f1e64d0804fc832c` |
| main 모드 run | `41569152442` — SUCCESS · exit 1 §8 전이 관측 |
| 판정 | `DISPROVED`·`BUG_SUSPECTED`(SPEC-LIBP2P-BV-SLICE, bytesview toOpenArray) |
| canonicalRunDigest | `294180890d20a35a46eb17a3b3d50bed8cb651f7bc581b25470532c91c44b590` — **5관측(d1·d2·d3·main·Phase 4) 일치** |
| upstream 보고 | `DUPLICATE` → issue [#3364](https://github.com/iftech/nim-libp2p/issues/3364), 신규 이슈 없음 |
| 음성 empty | `41570130079` — `NO_PROPOSALS` exit 3, 보고 스킵, 이슈 없음 |
| 음성 mismatch | `41570134018` — `SUBJECT_MISMATCH` exit 3, 보고 스킵, 이슈 없음 |
| 종결 원복 | access `none`·시크릿 0건·fork revert(§7) |
| 계약 정정 | §10(b) private 한정 + (b') 신규(공개 호출자 구조적 차단) + §12 참조 추가 |
