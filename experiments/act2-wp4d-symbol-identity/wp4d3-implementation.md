# WP4-d-3 — 6-dimension shadow digest harness (구현 기록)

EXPERIMENT_ID=act2-wp4d-symbol-identity
SUB_TASK=WP4-d-3
DATE=2026-08-28

## 목적

M1 replay 결정론(A/B/C 경로/CWD 불변)을 증명하기 위해, 서로 다른
실행 위치에서 생성된 검증 artifact 집합을 **canonical digest 6차원**으로
비교하는 경량 harness 를 구축한다. 기존 `ax shadow compare` 는
byte-equality 만 수행해 경로 차이에 취약하므로, 이를 보완한다.

## 사전 조사 (agent-89, 파일/라인 근거 확보)

| 차원 | 상태 | 파일:라인 |
|------|------|-----------|
| 1. verified-set digest | 없음 → 신규 | verified_set.nim:50 popcount 만 존재 |
| 2. planned queue digest | 없음 → 신규 | topology_engine.nim:77 verificationQueue |
| 3. obligation list digest | 개별 ID만 → 목록 신규 | obligation_types.nim:214 computeObligationId |
| 4. solver run digest | 개별 replayKey만 → 목록 신규 | solver_invocation.nim:22 replayKey |
| 5. dependency-graph digest | 없음 → 신규 | import_graph.nim / topology_engine.nim:45 |
| 6. canonicalProjectionHash | **이미 존재 + CLI 노출** | canonical_projection.nim:73, report_cli.nim:325 |

확정: `canonicalProjectionHash` 는 존재, `ax report --canonical-digest`
CLI 노출. 나머지 5개 차원의 **목록/그래프 단위** digest 는 전부 신규 구축.
기존 `ax shadow compare` (shadow_cli.nim:29) 는 byte-equality 뿐이라
6차원 canonical 기준으로 아무것도 커버하지 못함.

## 구현

### src/core/utils/shadow_digests.nim (신규, pure 함수 7개)
- `projectionDigest(state: JsonNode)` — canonicalProjectionHash 재사용
- `plannedQueueDigest(analysis)` — verificationQueue 를 sorterNodeIdString 정렬 → sha256
- `dependencyGraphDigest(analysis)` — state.nodes 의 (nodeId|deps) 쌍 정렬 직렬화 → sha256
- `obligationListDigest(ids: seq[string])` — 정렬 → sha256
- `solverRunDigest(replayKeys: seq[string])` — 정렬 → sha256
- `verifiedSetDigest(verified)` — VerifiedSet 비트셋 word 직렬화 → sha256
  (VerifiedSet 은 seq[uint64] 비트셋; digestBits() 로 word 를 얻어 정렬 직렬화.
  nodeId 복원은 InternPoolSnapshot 이 필요한데 pure func 내 불가 → 비트셋 word
  직렬화로 대체. **비트셋 의미론 불변.**)
- `sixDimensionFingerprint(a..f)` — 6개 digest 정렬 결합 → sha256 (순서 비의존)

### src/cli/shadow_cli.nim (확장)
- `ax shadow digest <analysisJson> <proofStateJson>`
  → 분석 JSON(verificationQueue/state.nodes/obligationIds/solverReplayKeys/verifiedSetBits)
  + proof state JSON 을 읽어 6차원 + fingerprint 출력
- `ax shadow compare-digests <a.json> <b.json>`
  → 두 digest-집합 JSON 을 읽어 6차원 + fingerprint 각각이 같은지 PASS/FAIL 판정
  (digest 단위 비교, raw byte 비교 아님)
- 기존 `ax shadow compare`(byte-equality) 는 **그대로 보존** (zero-drift)
- 디스패치: action_interpreter_cli.nim:101 가 runShadowCli 호출 → main.nim 수정 불필요

### tests/unit/shadow_digests_test.nim (신규, 9개 케이스 모두 PASS)
1. plannedQueueDigest 결정론
2. dependencyGraphDigest 결정론
3. obligationListDigest 순서 비의존 ([a,b]==[b,a])
4. solverRunDigest 순서 비의존
5. 빈 입력 크래시 없음
6. sixDimensionFingerprint 순서 비의존
7. projectionDigest volatile strip + object key 정렬
8. projectionDigest 다른 내용 → 다른 digest
9. verifiedSetDigest 결정론

## 검증 결과

- 유닛테스트: `AXIOM_CI_PRESERVE_CACHE=1 nim c -r --hints:off -o:/tmp/opencode/ax-sd tests/unit/shadow_digests_test.nim`
  → **9 / 9 PASS** (첫 실행에서 projectionDigest 테스트의 잘못된 배열순서 가정으로 1개 FAIL
  → canonicalProjectionHash 는 배열 원소 순서를 보존하는 것이 의도된 동작임을 확인하고
  테스트 기대 수정 → PASS; refactor 후 재실행에도 9/9 유지)
- `make build` → **✅ Build successful** (bin/ax 갱신). CLI 런타임 검증:
  - `ax shadow digest <analysis> <proofState>` → 6차원 digest + fingerprint 출력, exit 0
  - `ax shadow compare-digests` 동일 집합 → 7개 차원 전부 PASS, exit 0
  - `ax shadow compare-digests` 한 차원(verifiedSet)만 다른 집합 →
    해당 차원 + fingerprint 만 FAIL, 나머지 PASS, exit 1 (차원 수준 국지화 동작)
  - 기존 `ax shadow compare`(byte-equality) identical/different 각각 exit 0/1
  - 기존 `ax shadow run` dry-run exit 0
  - → 기존 shadow_cli 동작 **zero-drift 유지**, 신규 서브커맨드 동작 확인
- 빌드 과정에서 수정한 회귀 (private 필드 접근 제거):
  - 원안 `parseVerifiedSet` 이 VerifiedSet 의 private `bits` 필드에 접근해 컴파일 실패
    (verified_set.nim:15-17 는 export 하지 않음)
  - `shadow_digests.nim` 에 순수 헬퍼 `verifiedSetBitsDigest(words: seq[uint64])` 추가,
    `verifiedSetDigest` 가 이를 재사용하도록 재구성
  - `shadow_cli.nim` 은 JSON 배열 → `seq[uint64]` 로만 파싱(`parseVerifiedSetBits`)하고
    private 필드에 닿지 않음. 또 `core/types/results` import 추가로
    `safeParseJsonFile(...).isErr()` 해석, `parseBiggestUInt` ValueError 를 try/except 로
    quarantine 하여 `{.raises: [].}` 유지.

## 실측 정리

canonicalProjectionHash 의 특성:
- 객체 키는 **정렬** (sortedCanonicalJson, canonical_projection.nim:50)
- 배열 원소 순서는 **보존** (배열은 순서 의미론)
- volatile(타이밍/런타임 관측) 키 재귀 제거 (stripVolatile, :32)
- 즉 canonical projection 은 "타이밍 불변 + 키 정렬 + 배열 순서 보존" 이다.
  M1 비교 시 검증 큐/obligation/solver 목록의 순서는 별도 digest 함수에서
  정렬로 순서 비의존화함.

## 남은 것
- WP4-d-4(getBitsBE 8-stage replay) 에서 분석 JSON/state JSON 을 두 경로에서
  생성해 `ax shadow compare-digests` 로 비교하는 end-to-end 검증이 WPA 의 목표.
