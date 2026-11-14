# Verdict-Input Pinning — 판정 입력은 심판관이 소유한다

상태: **계약(contract).** 강제 지점은 `tools/ci/check_evidence_id_contract.nim`의 `checkVerdictInputs`
(admission-check.yml `go-critical-lane`의 `[lane] evidenceId contract check` 스텝이 실행)이며,
등재 근거는 `config/policy/merge_admission.json` v1.22.0 `trustSurface`다.

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

**판정 입력은 심판관(B)이 소유한다. 후보 바이트는 승인된 pin으로만 유입된다.**

`tests/` 하위 추적 파일 중 B blob과 달라진 모든 것 — 수정·삭제·이름변경·신규 추가 — 은
다음을 모두 만족해야 한다.

1. checker 내 `PinnedVerdictInputs`의 항목과 경로가 일치하고,
2. 워크트리 바이트의 git blob oid가 `pin.blobOid`와 같고,
3. 승인된 assertion-site 하한 `pin.obligations`를 밑돌지 않는다.

불일치는 다음 코드로 fail-closed 한다.

| 코드 | 의미 |
|---|---|
| `GO_TEST_BYTES_DIVERGED(<path>)` | 삭제·미등재·바이트 불일치 (삭제와 미등재는 예외 없음) |
| `GO_TEST_OBLIGATIONS_REDUCED(<path>)` | 승인된 바이트가 단언을 잃었다 (obligations < approved) |
| `GO_TEST_PIN_MALFORMED(<path>)` | pin 자체가 불량 (경로 이탈·oid 비정상·하한 ≤ 0) |

검사는 **컴파일보다 먼저, GO-critical 테스트보다 먼저** 실행된다. 같은 스텝의
`make test-fast-one T=tools/ci/check_evidence_id_contract.nim`이 checker의 `main()`을 먼저 지나고,
그 스텝 자체가 GO 테스트 스텝보다 앞선다. 실패는 `exit 1` → 스텝 실패 → lane 실패 →
required check `admission-check` 실패 → 큐 eject다.

가드는 `GITHUB_ACTIONS=true`이고 이벤트가 `merge_group` 또는 `workflow_call`일 때만 armed다.
그 밖(로컬 실행·`pull_request` venue)에서는 inert이며, 이는 후보가 조작할 수 있는 값이 아니다.

### 2.1 가드가 보는 것 — 워크스페이스(B + 오버레이)

이 계약의 주장은 "후보 트리와 B를 비교한다"가 아니라 "**실행될 바이트가 승인된 바이트와 같다**"이다.
그 차이가 실제 오버레이 의미론에서 중요하다(`.github/workflows/admission-check.yml` `:3857-3867`).

- 오버레이는 `cp -f`만 수행하고 **삭제(`rm`)를 하지 않는다.** 후보가 `tests/`에서 파일을 삭제해도
  워크스페이스에는 B의 승인 바이트가 남고, GO 테스트는 그 바이트로 실행된다.
  즉 후보 삭제는 "탐지되어 거부"되는 것이 아니라 **오버레이되지 않아 무시**되며, 판정은 승인 입력으로 계산된다.
- 후보의 **추가**는 워크스페이스에 도달한다(glob 매치 시) → `not pinned` → FAIL.
  **이름변경**은 신규 경로가 미등재로 FAIL하고, 삭제된 경로는 위 규칙에 따라 B 바이트로 남는다.
- 오버레이 glob(`tests/golden/*.nim`)은 재귀가 아니므로 하위 경로의 테스트 픽스처는 오버레이되지 않는다.
  그 파일들은 B 바이트로 실행되므로 역시 구성상 안전하다.
- 가드의 `D`(삭제) 처리는 워크스페이스에서 파일이 실제로 사라진 경우 — 테스트 런타임의 파일 조작,
  또는 향후 오버레이 의미론 변경 — 를 위한 belt-and-braces다.

따라서 "삭제도 잡는다"는 서술은 정확히는 "**삭제된 입력은 실행되지 않는다**"로 읽어야 한다.
어느 경우에도 후보가 승인되지 않은 바이트로 판정을 받는 경로는 없다.

## 3. 권한 구조 — 자기승인 불가

lane은 **B의 checker 바이트**로 실행된다(pin도 B의 것이다).
후보가 같은 PR에서 pin을 고쳐도, 그 후보를 판정하는 실행은 옛 pin을 본다.

따라서 승인된 테스트 변경은 **2단계**다.

1. **PR-A**: `PinnedVerdictInputs`의 `blobOid`/`obligations`만 갱신한다. 테스트는 불변 →
   워크트리 바이트가 B와 같으므로 가드는 통과한다.
2. **PR-B**: 실제 테스트를 변경한다. 이제 B의 pin이 새 바이트를 승인하고 있으므로 통과한다.

`tools/ci/check_evidence_id_contract.nim`은 `trustSurface`에 등재되어 있으므로
PR-A는 `TRUST_SURFACE_MODIFIED` → 자동 병합 거부(운영자 수동 병합)다.
즉 pin 갱신은 항상 사람의 명시적 행사다.

## 4. 해시가 증명하는 것 / 증명하지 않는 것

`blobOid`는 **승인된 바이트가 사용되었다**는 사실만 증명한다. 그 테스트가 충분히 강한지는
증명하지 않는다. 강도에 대한 통제는 다음 세 가지이며, 어느 것도 기계적 증명이 아니다.

1. `obligations` 하한 — 단언 사이트 수의 단조 감소를 차단한다(조용한 삭제 방지).
2. 2단계 + 운영자 수동 병합 — pin 갱신 diff가 항상 사람 눈에 노출된다.
3. positive/negative control — pin 갱신 PR은 정상 입력 PASS와 의도적 위반 FAIL을 함께 제시한다.

**후속(별도 슬라이스)**: s1a에 proof_integrity 수준의 B-owned verdict-map 백스톱을 추가하는
판정 강도 개선. 본 계약은 그 작업의 선행 조건이지 대체물이 아니다.

## 5. 회전 비용

checker는 워크플로 YAML이 아니라 **B 체크아웃의 바이트**로 실행된다.
따라서 이 가드는 callee 핀 회전(`Archright/.github` `@c021c338`), org ruleset 재핀,
epoch cutover를 요구하지 않는다. 다음 merge_group부터 유효하다.

## 6. 비목표

- 검사 범위 축소·테스트 교체·임계값 변경 (판정 의미론 변경은 별도 승인 사안)
- `src/` 고정 — 후보가 `src/`를 바꾸는 것은 정상이며, 그것을 판정하는 것이 이 게이트의 목적이다
- 증거 재사용 확장(Judgment CAS) — "the plan never invents a reuse" 불변
- 양 lane 간 배터리 공유 — per-lane `EXECUTED always` 계약 불변

## 7. 관련 정본

- `.github/workflows/admission-check.yml` — 오버레이·배터리·GO 테스트 스텝
- `config/repository_surface.json` — 표면 분류(PRODUCT/CONTROLLED/FROZEN), base-policy 바인딩
- `config/policy/merge_admission.json` — `trustSurface`(v1.22.0 등재)
- `src/verification/judgment_cas.nim` — 판정 상수(17/14/[3,2,1,11])와 attest payload 검증
- `docs/design/admission_gate_performance_cutover_design_2026-11-13.md` — Tier 1/2/3 분류