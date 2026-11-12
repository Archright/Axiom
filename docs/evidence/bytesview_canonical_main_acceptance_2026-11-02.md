# bytesview 정본 증거 파이프라인 — canonical main acceptance (2026-11-02)

PR-1(#1173, merge 커밋 `2e1083ed8`) 랜딩 후, 병합된 main에서 전체 수직 슬라이스 시나리오를 재실행한 기계 관측 기록.

## 실행 환경

- 대상: 병합 main `2e1083ed8` (격리 worktree `/tmp/ax-main-acc`, 병합 후 폐기)
- 빌드: `make build` exit 0 (74s) — SourceCoherence 임베디드 해시 갱신 포함
- state: `AXIOM_STATE_DIR=/tmp/axB_state` (scope lock은 `ax scope lock` 재생성본을 state dir에 시드 — 이전 세션과 동일한 표준 준비 절차)
- 주체: `<workspace>/nim-libp2p` @ `a130a7f32219909bdcda14b7f1e64d0804fc832c`

## 관측 결과

### 1. prove — 명제 반증 재현

```
AXIOM_STATE_DIR=/tmp/axB_state AXIOM_PROVE_VAULT_DIR=/tmp/axB_vault \
  timeout 500 ./bin/ax prove --project …/nim-libp2p \
  --target "libp2p/utils/bytesview.nim::toOpenArray"
→ exit 1
[INFO] ir_pipeline_runner: [ce-replay] bvSliceLenActual — replay agreed;
       PROPOSITION_DISPROVED payload assembled (13 records)
```

display v3 (`ax_proof_state.json`):

| 필드 | 값 |
|---|---|
| propositionVerdict | `DISPROVED` |
| requirementSourceStatus | `unrecorded` |
| bugAttribution | `BUG_SUSPECTED` |
| adoptedSpecRef | SPEC-LIBP2P-BV-SLICE (`nim_libp2p_bytesview_slice.json`) |
| groundsRefs | Nim stdlib `toOpenArray` INCLUSIVE semantics + 공식 문서 예제 `s.toOpenArray(1, 3) == [1,2,3]` |

findingEvidence:

- machineVerdict `FAIL`·machineEstablished true·claimOutcome clDisproved·rowStatus failed
- 반례 13레코드: `input.e=4`, `propertyViolated=(= result e)`, `replay.verdict=rvAgree`, `replay.exitCode=0`, `replay.subjectGitRef=a130a7f3…`, `replay.moduleSha256=b205c969…`(실행 전후 동일), `replay.porcelainClean=true`, `replay.nimVersion=Nim 2.2.10`
- subjectCommit `a130a7f32219909bdcda14b7f1e64d0804fc832c`·subjectBlob `b205c969…`

### 2. report — 기존 #3364 DUPLICATE 연결

```
AXIOM_STATE_DIR=/tmp/axB_state ./bin/ax report --upstream \
  --state-file /tmp/axB_state/logs/ax_proof_state.json --json
→ exit 0
status: DUPLICATE · "duplicate of ledger-recorded submission"
issue: {number: 3364, url: https://github.com/iftech/nim-libp2p/issues/3364}
requestedRepository: status-im/nim-libp2p → resolvedRepository: iftech/nim-libp2p
```

### 3. receipt 불변 (재실행 멱등)

| 필드 | 값 (PR-1 랜딩 시점과 동일) |
|---|---|
| findingKey | `48a9935e9fb76d6346afc6bca56b5fb2d8921fd55a02052371069d5ee69e4a1f` |
| evidenceDigest | `de01eb46b7f80183a8149ad44d72ed91b460fd9eee2bc0695432846ba1243f94` |
| submittedAt | `2026-10-31T16:23:47Z` (#3364 실제 생성 시각과 일치) |
| legacyFingerprints | `38647549ce…` (구 지문 이전 보존) |
| attempts | 12 → 14 (acceptance 실행 2회 시도 기록 — resolve-repository·verify-ledger-submission) |

### 4. 외부 저장소 무변경

- nim-libp2p `git status --porcelain` = 0건
- HEAD `a130a7f3` 유지, bytesview 모듈 sha256 `b205c969…e961e5ee` 실행 전후·랜딩 전후 불변
- GitHub #3364: open, 댓글 1건(우리 재현 코드) — 신규 이슈 0건

## 판정

Terminal acceptance 기준 전부 충족:

- 동일 반례가 동일 결함(findingKey)으로 재인식되고,
- 정확히 `BUG_SUSPECTED`(DISPROVED/unrecorded)로 판정되며,
- 기존 #3364에 DUPLICATE로 연결되고,
- 재실행해도 findingKey·evidenceDigest·issue 연결이 불변한다.

메인테이너의 수용·수정은 외부 프로젝트 소유자의 권한으로 완료 조건이 아니다.
