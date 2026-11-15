# Verdict-Input Approvals — 판정 입력은 심판관이 소유한다

상태: **계약(contract).** 강제 지점은 `tools/ci/check_evidence_id_contract.nim`의
`checkGoCriticalInputs`(admission-check.yml `go-critical-lane`의
`[lane] evidenceId contract check` 스텝이 실행)이며, 등재 근거는
`config/policy/merge_admission.json` v1.22.0 `trustSurface`다.
개정: v2(2026-11-15) — checker 내 하드코딩 pin·워크트리 비교에서
**`data/policy/go_critical_input_approvals.json` 승인 테이블·B/M git 트리 비교**로
재구성했다(역사는 git).

## 1. 문제

`go-critical-lane`은 워크스페이스 루트를 **B(main) 트리**로 채우고, 후보 M의
`src/`·매트릭스 테스트 파일·`tests/golden/*.nim`만 오버레이한다
(`.github/workflows/admission-check.yml`, `[lane] Overlay M src/+GO-critical tests`).

실행자 표면(`Makefile`, `config.nims`, `tests/config.nims`, `config/effects.nims`, `nimble.lock`)은
오버레이 전/후 sha256 비교로 불변 강제되지만(`:3849-3852`, `:3873`), **오버레이되는 판정 입력 자체에는
바이트 가드가 없었다.**

- `config/repository_surface.json`: `defaultClass = PRODUCT`, `rules.PRODUCT.MODIFY = PASS`.
  GO-critical 테스트와 golden 픽스처는 열거되어 있지 않다.
  (`knownBlindSpots` v51: "unregistered paths are ordinary code … the boundary is closed by
  enumeration, not by default".)
- B-owned attest payload validator는 **결과 형태**를 고정한다(`17 ACCEPT / 14 probe / [3,2,1,11]`).
  단언(assertion)의 존재는 고정하지 않는다.
- `expected exactly 1`(`:4126`)은 실행된 테스트 **개수**만 센다.

따라서 후보는 `check` 한 줄을 삭제하고 lane을 green으로 통과시킬 수 있었다.
가장 직접적인 실례: `tests/unit/test_s1a_lean_golden.nim:221`의
`check r.verdict == vdVerified`는 최종 VERDICT를 단언하는 유일한 지점이며
(payload의 `verdict` 멤버는 상수 `KERNEL_ACCEPT_ALL`이다), 이 줄을 지우고
`evaluate(...)`를 비VERIFIED로 회귀시키면 end-to-end green이 된다.
s1a에는 proof_integrity가 가진 checkpoint→verdict 맵 백스톱(`judgment_cas.nim:1109-1116`)이 없다.

## 2. 계약

**판정 입력은 심판관(B)이 소유한다. 후보 바이트는 승인 blob으로만 유입된다.**

대상 경로는 레인이 실제로 M 바이트로 실행하는 판정 입력 **그대로**다:
`matrix.tests` 4종(`tests/unit/test_s1a_lean_golden.nim`,
`tests/unit/proof_integrity_test.nim`, `tests/unit/test_d2_golden.nim`,
`tests/unit/test_d2_persist.nim`) + `tests/golden/*.nim` 최상위 글롭
(오버레이의 비재귀 glob과 동일 — 하위 디렉터리·비-.nim은 B 바이트로 실행되므로 범위 밖).

각 경로에 대해 checker는 **양쪽 git 트리에서 blob을 측정**한다:

1. B blob = 워크스페이스 체크아웃의 `HEAD` 트리(`git ls-tree HEAD`).
   오버레이는 워킹트리만 바꾸므로 HEAD는 B 커밋 그대로다.
2. M blob = `_candidate` 체크아웃의 `HEAD` 트리(`git -C _candidate ls-tree HEAD`).
3. 같으면 통과. 다르면 **M blob이 그 경로의 승인 집합에 있을 때만** 통과.
4. M에만 있는 추가 파일은 승인 집합에 없으면 FAIL. **B에만 있는 삭제는 무조건 FAIL**
   (삭제도 판정 입력 변경이다 — 오버레이가 B 바이트를 남기고 실행하더라도,
   후보가 그 입력을 철회했다는 사실 자체가 판정 변경이다).

승인 집합은 `data/policy/go_critical_input_approvals.json`(`schema:
go-critical-input-approvals/v1`)이 지닌다. 경로별 `approvedBlobs`는 다중 허용 —
staged landing 창(구·신 blob 병존)이다. 빈 집합은 "B 바이트로 고정"(모든 발산 FAIL)이다.

불일치는 다음 코드로 fail-closed 한다.

| 코드 | 의미 |
|---|---|
| `GO_TEST_HASH_UNAPPROVED(<path>)` | 미승인 수정·미승인 추가·삭제 (승인 집합으로도 허용 불가) |
| `GO_TEST_TABLE_MALFORMED` | 테이블이 권위로 기능할 수 없음 (부재·해석 불가·스키마 드리프트·범위 밖 경로·oid 비정상·경로 중복) 및 B/M git 상태 해석 불가 |

검사는 **컴파일보다 먼저, GO-critical 테스트보다 먼저** 실행된다. 같은 스텝의
`make test-fast-one T=tools/ci/check_evidence_id_contract.nim`이 checker의 `main()`을 먼저 지나고,
그 스텝 자체가 GO 테스트 스텝보다 앞선다. 실패는 `exit 1` → 스텝 실패 → lane 실패 →
required check `admission-check` 실패 → 큐 eject다.

가드는 `GITHUB_ACTIONS=true`이고 이벤트가 `merge_group` 또는 `workflow_call`일 때만 armed다.
그 밖(로컬 실행·`pull_request` venue)에서는 inert이며, 이는 후보가 조작할 수 있는 값이 아니다.
판정 의미론은 checker의 self-check 배터리(매 레인 실행, EXECUTED always)와
`tests/ci/test_go_critical_input_approvals.nim`(단위 테스트)에 4케이스로 고정된다:
동일 blob 통과 / 미승인 변경 FAIL / 승인된 변경 통과 / 추가·삭제 FAIL.

### 2.1 가드가 보는 것 — 두 git 트리

비교 대상은 워크스페이스(=오버레이 후 실행될 바이트)가 아니라 **B와 M의 트리 객체**다.
워킹트리가 오버레이로 오염되어도, `git status`가 아닌 `ls-tree`로 두 HEAD를 직접 읽는다:

- 오버레이는 `cp -f`만 수행하고 **삭제(`rm`)를 하지 않는다.** v1은 이를 "삭제는 무시되고
  B 바이트로 판정된다"고 읽었지만, v2는 트리 비교로 **삭제 자체를 FAIL**한다 —
  후보가 판정 입력을 철회한 것은 어떤 경로로도 승인 없이 통과할 수 없다.
- 후보의 **추가**(M 트리에만 있는 `tests/golden/*.nim`)는 목록에 들어오므로
  승인 집합 없이는 FAIL이다. **이름변경**은 (신규 경로 = 미승인 추가) + (구 경로 = 삭제)로 FAIL한다.
- 하위 디렉터리(`tests/golden/base36_subject/`)와 비-.nim 파일은 오버레이·가드 범위 모두 밖 —
  B 바이트로 실행된다.
- 해시 원시 함수(`sha256Hex`)는 오버레이된 후보 `src/`의 것이므로 쓰지 않는다.
  비교의 양변 모두 git이 계산한다 — 판정되는 트리가 심판관의 해시를 공급할 수 없다.

## 3. 권한 구조 — 자기승인 불가

lane은 **B의 checker 바이트**로 실행되고 테이블도 **B의 HEAD git 객체**에서 읽는다.
후보가 같은 PR에서 테이블을 고쳐도, 그 후보를 판정하는 실행은 구 세대의 테이블을 본다.
**테스트 변경 + 테이블 변경을 한 PR에 몰아넣으면 자기 merge_group 실행에서 FAIL한다.**

따라서 정당한 판정 입력 변경은 **3단계 staged landing**이다. 각 단계는 직전 세대
테이블로 자기 PASS한다:

1. **PR-A**: 새 blob을 기존 blob과 **함께** 등록한다(테스트는 불변 → B==M → 통과).
2. **PR-B**: 테스트 바이트를 변경한다(B의 테이블이 이미 새 blob을 승인 → 통과).
3. **PR-C**: 구 blob을 승인 집합에서 폐기한다(테스트는 B==M → 통과).

`tools/ci/check_evidence_id_contract.nim`은 `trustSurface`에 등재되어 있고
`/data/policy/`는 CODEOWNERS로 `@Archright/architect`에 결속되어 있다.
즉 모든 단계는 운영자 리뷰 대상이며, checker 수정 단계는 자동 병합 거부
(운영자 수동 병합)다 — 승인은 항상 사람의 명시적 행사다.

## 4. 해시가 증명하는 것 / 증명하지 않는 것

blob 승인은 **승인된 바이트가 그대로 사용되었다**는 사실만 증명한다.
그 테스트가 충분히 강한지는 증명하지 않는다. blob-identity 승인은 바이트 단위
정확성을 강제하므로 단언 감소(weakning)도 반드시 새 blob 승인을 요구한다
(v1의 `obligations` 하한을 대체한다 — 바이트가 다르면 승인 없이는 통과 불가).
강도에 대한 통제는 다음 세 가지이며, 어느 것도 기계적 증명이 아니다.

1. blob-identity 승인 — 승인된 바이트 외 어떤 변형도 거부.
2. 3단계 staged landing + 운영자 병합 — 승인 diff가 항상 사람 눈에 노출된다.
3. positive/negative control — 승인 갱신은 정상 입력 PASS와 의도적 위반 FAIL을 함께 관측한다.

**후속(별도 슬라이스)**: s1a에 proof_integrity 수준의 B-owned verdict-map 백스톱을 추가하는
판정 강도 개선. 본 계약은 그 작업의 선행 조건이지 대체물이 아니다.

## 5. 회전 비용

checker는 워크플로 YAML이 아니라 **B 체크아웃의 바이트**로 실행된다.
테이블은 `data/policy/` 아래 PRODUCT 클래스이며 `src/verification/evidence_cas.nim`의
`PolicyDigestInputPaths` 5파일(`config/` 아래) 밖이다. 따라서 이 가드는
callee 핀 회전(`Archright/.github` org workflow SHA pin), org ruleset 재핀,
epoch cutover, EvidenceKey 회전 중 **어느 것도 요구하지 않는다**.
다음 merge_group부터 유효하다.

## 6. 비목표

- 검사 범위 축소·테스트 교체·임계값 변경 (판정 의미론 변경은 별도 승인 사안)
- `src/` 고정 — 후보가 `src/`를 바꾸는 것은 정상이며, 그것을 판정하는 것이 이 게이트의 목적이다
- 증거 재사용 확장(Judgment CAS) — "the plan never invents a reuse" 불변
- 양 lane 간 배터리 공유 — per-lane `EXECUTED always` 계약 불변

## 7. 관련 정본

- `data/policy/go_critical_input_approvals.json` — 승인 테이블(본 계약의 데이터 SSOT)
- `tools/ci/check_evidence_id_contract.nim` — 강제 지점(`checkGoCriticalInputs`,
  판정 함수 `judgeGoCriticalInput`/`parseApprovalTable`/`parseLsTree`)
- `tests/ci/test_go_critical_input_approvals.nim` — 4케이스 단위 테스트
- `.github/workflows/admission-check.yml` — 오버레이·배터리·GO 테스트 스텝
- `config/repository_surface.json` — 표면 분류(PRODUCT/CONTROLLED/FROZEN), base-policy 바인딩
- `config/policy/merge_admission.json` — `trustSurface`(v1.22.0 등재)
- `src/verification/judgment_cas.nim` — 판정 상수(17/14/[3,2,1,11])와 attest payload 검증
- `src/verification/evidence_cas.nim` — `PolicyDigestInputPaths`(회전 0 근거)
- `docs/design/admission_gate_performance_cutover_design_2026-11-13.md` — Tier 1/2/3 분류
