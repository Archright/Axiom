# Judgment CAS Phase 2–3 — 측정·분석 등록 (Registrations R1–R4)

> **Status**: 등록 문서 — 코드 무변경. Phase 2–3 슬라이스(측정 근거 문서화 + 가용성·격리 등록)의
> 발견·분석 등록을 담는다.
> **정본**: `docs/spec/test_judgment_cas_contract.md` · 측정 근거
> `docs/spec/judgment_cas_payload_measurement_basis.md` · 권한 원칙 `docs/agents/task-process.md`
> §2.2-8 (AGENTS.md §2.2 정본의 이동 보존 전문).
> **측정 커밋**: origin/main `6767884e7` (2026-10-09). **작성일**: 2026-10-09.
> **측정 에이전트**: Kimi Code 서브에이전트 (2026-10-09).

---

## R1 — s1a 런타임 바이모달(~230s vs ~310s): 측정 과제 등록

**관측된 사실 (원 계산 경로 — 런 로그·선행 증거문서 인용)**:

| 런 | s1a 스텝 벽시계 | 출처 |
|---|---|---|
| PR-run #606 사이클 | 309.2 s · 310.0 s | `docs/evidence/test_judgment_cas_s1a_phase3_2026-10-09.md` §1-① (#604 실측 재인용) |
| PR-run 37794843057 | 177.2 s | 상동 §2 |
| MG-run 37796749342 | 232.1 s | 상동 §2 |
| PR-run 37811664465 (#611 세대) | **310.5 s** (16:54:42→16:59:53Z) | 상동 §5 |

벽시계 분포가 약 177–232s 대역과 309–310s 대역으로 분리되어 관측된다(셋 중
PR-run/MG-run 구분과 상관하지 않음 — PR-run에 양쪽 대역이 모두 존재). 선행 문서는 이를
"warm cache 변동"으로만 표기했다.

**등록 내용**: 원인 분석은 본 등록의 범위 밖이다(의미 분석 아님 — 분석 소진). 다음을
**측정 과제**로 등록한다:

- **측정 목표**: s1a `make test-fast-one` 스텝 내부의 단계별 벽시계 분해(컴파일 단계 vs
  Lean 커널 17회 실행 vs 스위트 부분)를 런 로그에서 기계 추출 가능하게 하고, 대역 분리가
  어느 단계에서 발생하는지 관측으로 판정한다.
- **측정 프로토콜**: EXECUTED 런 n≥6(PR/MG·cache 유무 축 교차)에서 런 로그 zip의 s1a
  스텝 타임스탬프를 단계별로 추출·표 작성. 분해 경계는 컴파일 시작→종료, 첫 커널 호출→
  마지막 ACCEPT 관측으로 정의한다.
- **판정 규칙**: 단계별 중앙값 차가 측정 잡음(동일 대역 반복 측정의 산포)을 초과하는
  단계를 보고한다. 단계 귀속이 확정될 때까지 원인 가설을 문서에 기술하지 않는다.
- **소유**: jcas workstream 후속 측정 슬라이스.

**금지**: 본 등록만으로 "원인은 X" 주장 금지 (측정 선행). 극장 아님 — 관측값 전부가
런 ID와 함께 기록되어 있다.

## R2 — MINT_JUDGAPPEND 실패(transport/validation): 권한 분석 등록 (§2.2-8)

**기계 관측 전문** (런 로그 zip, merge-queue 런 `37864249747` — PR #622 1차 큐 시도,
후보 `c11ae60c1`, 2026-10-09T00:31:38Z):

```
[ERROR] evidence_cli: ledger-append: evidence_ledger.appendEvidence: evidence key
fe06f08d51c158d90af1210b157c5054056290fa40fae80217f2c9836a593801 already present with
DIFFERENT payload bytes (payloadSha256 mismatch — identity-derivation anomaly, fail-closed,
not re-appended)
MINT_JUDGAPPEND: FAIL — judgment ledger-append failed (transport/validation) (fail-closed)
```

**관측 소재 정확화**: #611 사이클 자체의 양 런(PR-run `37811664465`, MG-run
`37813905412`)의 MINT_JUDGAPPEND는 **OK**(append exactly-once: 1 / idempotent no-op: 0)였다
(`test_judgment_cas_s1a_phase3_2026-10-09.md` §5 원문). 본 등록이 분석하는 실패 이벤트의
기계 근거는 위 런 `37864249747`이며, 동일 사건은
`test_judgment_cas_3subject_phase3_2026-10-09.md` §3.1에 관측으로, 동 문서 후속 3에
"등록은 인가 필요" 조건부로 이미 기록되어 있다 — 본 등록이 그 인가 아래 §2.2-8 권한
분석을 완성한다.

**§2.2-8 다섯 단계**:

1. **실행 권한 식별**: judgment 원장 append의 실행 권한은 단일 — mint publish job의
   privileged tier(`contents:write`)가 `bin/ax` evidence_cli `ledger-append` →
   `evidence_ledger.appendEvidence`를 호출하는 유일 경로다 (계약 §7-2 "mint 단일 append";
   생산 attest 런은 발행만 하고 원장에 쓰지 않는다, 소비 attest는 read-only).
2. **경쟁 권한 식별**: append 채널의 경쟁 권한은 없다. 그러나 **같은 클로저 키에 대한
   payload 내용 결정권에는 경쟁이 존재한다**: 선행 랜딩 런(#617, `f1c207d64`, 00:10Z)이
   키 `fe06f08d51c1…`로 자기 런의 레코드를 먼저 저장했고, 본 큐 시도 런이 동일 키에
   **자기 런이 재유도한 payload 바이트**(수신 영수증 다이제스트 등 런 스코프 성분 포함)를
   append하려 했다.
3. **정본 확립**: 정본은 `appendEvidence`의 exactly-once 가드다 — identity(키 단독)로
   동일 레코드를 판별하고, 키 동일 + 바이트 불일치를 "identity-derivation anomaly"로
   fail-closed 거부한다. 이 가드가 쓴 거절이 맞다: 키는 9성분 클로저(결정론)인데 payload는
   런 스코프 성분을 포함해 재생성 시 바이트가 달라진다 — same-key/different-payload를
   조용히 수용하는 것은 원장 무결성 파괴다. **실패 이벤트는 가드의 정상 동작**이며, FAIL
   라인의 "(transport/validation)"은 스텝의 포괄 분류일 뿐 실체는 validation-side 거절이다
   (네트워크·권한 장애 아님 — 같은 런에서 SL-15 MINT_EVAPPEND 경로는 정상 동작).
4. **불필요한 권한 제거**: 제거 대상 이중 권한 없음 (단일 라이터 불변 유지). 문제는 권한
   중복이 아니라 **identity(key)와 payload 결정성의 불일치**다 — 권한 조작으로 풀 문제가
   아니다.
5. **retry 판정**: **retry 추가 금지** — 동일 클로저 키의 payload 재생성은 결정적이므로
   스텝 내 retry는 같은 거절을 반복할 뿐이고(성공 불가능 retry), 실패를 삼키면 극장이 된다.
   실제 치유는 merge queue 자체의 재시도로 관측되었다: 후보 `0a71410e5`(런 `37864847071`)
   REUSED 전환 → 후보 `6767884e7`(런 `37865330190`) 랜딩 성공 — in-step retry가 아니라
   큐 반복이 유일한 회복 경로이며 이미 충분했다.

**원인 기록 (불변식 서술)**: `EvidenceKey = H(JudgmentClosure)`에서 클로저는 런 스코프
성분을 배제하지만, 레코드 payload는 그렇지 않다(런별 수신 영수증 다이제스트). 따라서
"동일 클로저의 두 번째 EXECUTED 런"은 항상 same-key/different-payload가 되어 exactly-once
가드에 fail-closed 한다. 기제 개선 후보(단일 후속 슬라이스): evidence_ledger identity에서
런 스코프 payload 성분의 분리 — R3과 별개의 슬라이스 후보로, 본 등록은 권한 분석까지만
수행한다.

**재현**:
```bash
gh api repos/Archright/Axiom/actions/runs/37864249747/logs > /tmp/r2.zip && unzip /tmp/r2.zip -d /tmp/r2
grep -n "MINT_JUDGAPPEND\|already present" "/tmp/r2/3_mint-publish _ publish.txt"
```

## R3 — B-cache 키 변경: 단일 슬라이스 후보 등록 (안전 전제 명시)

**현 상태 (기계 인용)**: B-layer 키 유도는
`.github/actions/setup-axiom-toolchain/action.yml:201-213` — `b_identity` =
`cache-build-source`의 **tree OID 전체**, `b_key = "axiom-b-${b_identity}-${recipe_hash}${a_fp}"`.
트리 OID는 모든 docs 바이트를 포함하므로, docs-only main 커밋마다 B 세대가 전진해 모든
후속 PR이 false-MISS 재빌드를 강요받는다 (컴파일 입력이 바뀌지 않아도).

**후보 변경 (단일 슬라이스)**: `b_identity`를 "컴파일 성공 술어 입력의 소화(digest)"로
교체 — 키가 컴파일 성공/바이트에 실제로 참여하는 문서 입력만 흡수하도록 한다:

| 키 입력 | 근거 (컴파일 참여 방식) |
|---|---|
| `docs/spec/spec_registry.json` **바이트** | `src/core/contracts/spec_runtime.nim:5` `staticRead` → `CompiledSpecHash` (`:14`) |
| `docs/spec/three_tier_contract_architecture.md` (3-tier SPEC) | `src/core/contracts/spec_binding_macro.nim:46` `staticRead` → 컴파일 시점 셀 매칭(`SpecDocContent`) |
| `AGENTS.md` · `docs/agents/architecture.md` · `docs/agents/rules_workflow.md` **비공백성** | `config/integrity.nims:15-20` — `staticRead(...).len == 0`면 `quit(1)` (컴파일 성공 술어; 바이트 각인 아님) |
| `recipe_hash` + `a_fp` | 기존 유지 (`action.yml:211-212`) |

**안전 전제 (이 전제가 깨지면 후보 기각)**:

1. **항상-리빌드 유지**: 키 미스 시 네이티브 빌드가 발화하는 경로는 그대로다 — 키 변경은
   false-MISS 제거일 뿐, 미스→재빌드 의무와 exact-key 원칙(restore-keys 금지)을 약화시키지
   않는다.
2. **키≠verdict (J3)**: 캐시는 acceleration, never evidence — B restore 시의 지문
   재유도 검증(`action.yml` b-verify 스텝: buildSha/recipe/a_fp를 payload 밖 신뢰 입력에서
   재유도 + payload 파일 매니페스트 SHA-256 전수 대조)과 B_PROBE 소스해시 소견이 유지되는
   한, 키는 판정을 대체하지 않는다. 판정은 항상 재계산된다.
3. **identity 단위 일괄 전환 (§2.5)**: `b_identity` 교체는 keygen·`build/.axiom-b-fingerprint.json`
   의 `buildSha`·b-verify의 `EXPECT_BUILD_SHA`·B_PROBE의 신뢰 트리 소재 재유도 4점이
   동일 세대 전환으로 함께 움직여야 한다 — 키만 바꾸면 재유도 기대값 불일치로 전 payload가
   기각되어 안전하지만( fail-closed), 의도한 가속도 사라진다. in-place 혼합 금지.
4. **문서 바이트 중 컴파일 참여분은 소화된다**: 위 표의 staticRead 입력 바이트가 키에
   들어가므로, 컴파일 산출을 바꾸는 문서 변경은 키 전진을 유발한다 — "docs 무시"가 아니다.

**실증 인용 (CI 자연실험 — docs는 바이트 각인이 아니라 성공 술어 게이트다)**:
docs-only PR #613 사이클 런 `37816610651`(2026-10-08T17:30Z, branch
`docs/judgment-cas-s1a-pin-rotation`) — PR 자신의 docs 바이트는 빌드 입력에서 완전히
불참함이 관측되었다:

```
AXIOM_CACHE_KEYGEN: b-identity=c00e7da049e9… b-key=axiom-b-c00e7da049e9…-c91dcb6e…ba2f9aa0…
AXIOM_CACHE_B_VERIFY: entry OK — bin/ax sha256=2005e86748004683        (4/4 entries digest-verified)
AXIOM_CACHE_B_PROBE: OK — restored bin/ax embedded BuildSourceHash == trusted tree c00e7da049e9
```

B 엔트리는 **base 트리**(`c00e7da0…`)에서 유도되어 exact-hit했고, 복원된 `bin/ax`는
PR의 docs 변경과 무관하게 소스 정합성 소견을 통과했다. 보조 근거: `BuildSourceHash`는
`src/` 전수 커밋 해시일 뿐이다(`tools/hermetic_build.nim:849-890` —
`walkDirRec(srcDir)`, docs 불포함). 즉 컴파일 입장에서 docs는 (a) `config/integrity.nims`
비공백 게이트와 (b) 한정 staticRead 입력(spec 2종)으로만 존재하며, 나머지 docs 바이트는
컴파일 산출과 무관하다 — 현재 tree-OID 키는 이 무관성을 반영하지 않는다(과잉 무효화).
비고: `src/policy/embedded_agents_docs.nim:12-14`는 AGENTS.md 등을 `staticRead` 상수로
가지나 임포터가 관측되지 않는(미배선) 표면이다 — 후보 슬라이스는 배선 상태를 재관측하고,
배선될 경우 해당 파일 바이트도 키 입력으로 승격해야 한다.

**직접 실측(본 슬라이스, 2026-10-09)**: docs-only 트리(`6767884e7` + 본 문서 2종,
커밋 `4a28fa2b4`)에서의 `bin/ax report --canonical-digest` =
`354f811c25467787988a349053e5aab578d9c42b675fe34abc16bb0db9af4731` — merge 트리
`6767884e7`에서 측정된 값(`test_judgment_cas_3subject_phase3_2026-10-09.md` §1-⑥)과
**동일**. docs-only 델타가 컴파일 산출을 바꾸지 않음의 최근접 실측이며, 동일 트리 OID를
키로 쓰는 현재 B 캐시는 이 실측에서 재빌드 없이 재사용 가능했을 산출물을 재빌드한다.

**소유/착지 경로**: 단일 슬라이스(코드+워크플로 변경 — 본 문서 슬라이스 밖), §2.5 일관
세대 전환으로 착지.

## R4 — d2_golden 무장 플러시 카운트 불일치(13 vs 14): 잠복 결함 발견 등록

**발견 (측정 근거 문서 §4 동시 기록)**: `tests/unit/test_d2_golden.nim`의 커널 실행은
14회이지만, 그중 13회만 `jCanonical` 카운터(`:72` `inc judgmentKernelRunCount`)를
경유한다 — Stage 4 체인 테스트의 `:334`가 래퍼 없이 직접
`canonicalLeanKernelCheck(artifact).get()`을 호출한다. 무장(armed) 플러시(`:455`)는
`check judgmentKernelRunCount == D2GoldenKernelRunCount` 즉 `13 == 14`를 요구하므로,
**무장 실행에서는 플러시가 FAIL하고 d2_golden 어드미션이 fail-closed로 적색 전환된다**.

**현재 관측 불가였던 이유 (잠복 기전)**: 3주체의 evidence env는 mint P7c-x(PR #626,
OPEN)와 다음 핀 회전(세대 전환) 이후에만 무장된다. 지금까지의 모든 CI 실행(#622 양 런 포함)은
구세대 핀(s1a-only env)이라 3종이 무장 실행 → 플러시 skip → 결함 미관측. §1-⑤의
"test_d2_golden exit 0" 실측은 무장 경로를 포함하지 않는다.

**등록 내용 (수리 아님 — 본 슬라이스는 docs-only)**:

- **등록 후 착지 갱신 (2026-10-09, 본 PR CI에서 라이브 발화 관측)**: 본 등록의 예측은
  PR #631의 admission 런 `37877100086`(2026-10-09T03:09Z)에서 **그대로 발화**했다 —
  무장 플러시 `test_d2_golden.nim(455): judgmentKernelRunCount was 13 /
  D2GoldenKernelRunCount was 14` FAIL → `1/4 GO-critical admission test(s) failed —
  the admission verdict cannot rest on an unsound verifier (fail-closed)` (하류
  mint/verdict 실패는 cascade). 수리는 타 트랙에서 착지: **PR #630**
  (`fix/jcas-d2gold-counted-chain-sink`, 커밋 `31c29905e` — ":334를 카운터 경유로
  전환" 본 등록의 수리 후보와 동일 단일 라인), main 병합 `cbb8c0db6`. 본 PR은
  origin/main 재베이스로 수리 트리 위에서 재검증된다.
- **수리 후보(착지됨 — #630)**: `:334`를 `jCanonical()` 경유로 교체해 14회 전수가
  카운터에 집계. 상수·payload·워크플로 무변경, s1a 키 와이어 무변경.
- **발화 예상 시점**: PR #626 병합 + 핀 회전(3주체 CAS 마커 라이브화) 이후 최초의
  d2_golden EXECUTED 무장 런. **수리 없이 세대 전환하면 첫 무장 런이 적색으로 실패한다**
  — PR #626 랜딩 전에 수리 슬라이스를 먼저 착지시키거나, 동일 슬라이스에 병행하는 것을
  권고한다. fail-closed이므로 극장은 아니다(무결한 재실행이 강제됨) — 그러나 계획된
  적색 런은 낭비다.
- **판정 명령 + 기계 관측 (무장 로컬 재현 — 2026-10-09 실측 완료)**:
  ```bash
  # 결함 관측(현재 트리): 카운터 증가 지점 1곳 + 래퍼 우회 호출 1곳
  grep -n "inc judgmentKernelRunCount" tests/unit/test_d2_golden.nim          # :72 단일
  grep -n "canonicalLeanKernelCheck(" tests/unit/test_d2_golden.nim           # :73 · :334
  # 무장 플러시 FAIL 재현 (실측 커맨드):
  AXIOM_JUDGMENT_CAS_EVIDENCE_PATH_D2_GOLDEN=/tmp/d2golden_armed_evidence.json \
    nim c -r --hints:off -o:/tmp/opencode/ax-one-d2 tests/unit/test_d2_golden.nim
  ```
  **실측 결과 (본 워크트리, 커밋 `6767884e7` 트리, 2026-10-09)**: flush 테스트 FAILED,
  프로그램 exit 1 —
  ```
  tests/unit/test_d2_golden.nim(455, 35): Check failed: judgmentKernelRunCount == D2GoldenKernelRunCount
      judgmentKernelRunCount was 13
      D2GoldenKernelRunCount was 14
  ```
  14회 커널 실행 자체는 전부 성공(Stage 1–4·Summary 전 [OK]) — 실패는 카운트 단정뿐이다.
  무장 런이 존재하는 순간(세대 전환) 어드미션은 계획적으로 적색이 된다.

## 재현 명령 (본 문서 전체)

```bash
gh api repos/Archright/Axiom/actions/runs/37864249747/logs > /tmp/r2.zip   # R2 원문
gh api repos/Archright/Axiom/actions/runs/37816610651/logs > /tmp/r3.zip   # R3 자연실험
gh pr view 626 --json state,headRefOid                                     # R4 발화 전제 (OPEN, 88cefc2b9)
grep -n "b_identity\|b_key=" .github/actions/setup-axiom-toolchain/action.yml   # R3 현상태 :201-213
sed -n '15,20p' config/integrity.nims                                      # R3 비공백 게이트
grep -n "staticRead" src/core/contracts/spec_runtime.nim src/core/contracts/spec_binding_macro.nim  # R3 컴파일 입력
```

## 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-10-09 | R1 바이모달 측정 과제 · R2 MINT_JUDGAPPEND 권한 분석(§2.2-8, retry 금지 판정) · R3 B-cache 키 단일 슬라이스 후보(안전 전제 4 + 자연실험 인용) · R4 d2_golden 무장 플러시 13≠14 잠복 결함 등록 |
