# Certificate Evidence Chain — Operational Acceptance (Axiom #188)

- **상태**: ACCEPTED — 이 기록 자체는 문서 PR로 착지하며, 인용된 모든 판정은 병합된 워크플로·릴리스의 실제 GitHub run에서 관측됐다.
- **날짜**: 2026-11-20
- **범위**: Axiom 엔진의 certificate evidence export → GitHub artifact provenance → 소비 저장소의 admission guard → targeted negative control. 그리고 #119 경계 문서의 required CI 강제(#249).
- **완료 정의**: 코드 병합이나 PR 생성이 아니라, **보호된 소비 저장소의 실제 admission run과 negative control run에서 관측된 상태**다.

---

## §1. 궁극적 목적

Axiom이 "이 명제는 검증됐다"고 주장할 때, 제3자가 **무엇을 어떤 입력·도구·관측으로 검사했는지 재구성하고 반박할 수 있어야** 한다. 이 슬라이스는 그 주장과 증거의 일치를 시스템이 강제하도록 만든다:

- 주장(`status: certGreen`)이 아니라 **인증서 본문과 재계산된 tier**에서 판정을 도출한다.
- 증거 생산자(Axiom 엔진)와 전달자(GitHub workflow)를 분리하고, 전달자는 의미를 결정하지 않는다.
- 증거 누락·불일치·관측 부재는 **성공으로 승격되지 않는다**.
- 증명할 수 없는 구문은 **UNKNOWN/명시적 제외**로 남고, VERIFIED로 위장되지 않는다.

---

## §2. 착지한 체인 (실측)

| 단계 | 무엇 | 증거 |
|---|---|---|
| 계약 | export 입력·출력·digest·실패 조건 문서화 | PR #234, merge `f7d73fd8053f92a445348e8218ea35ef2198a93d` |
| 엔진 | `ax cert export` + `ax cert verify-export --closure --project` (engine tier 권위 재사용) | PR #237, merge `f8b35619dc5fafb2ab99dd7726745d9c8114e736` |
| producer adapter | axiom-cli reusable workflow가 엔진 export를 업로드하고 `actions/attest@v4`(3권한)로 provenance 결속 | `Archright/axiom-cli#1`, merge `a5fbfbb9cbee5530bb0916057fe46f967ce039e2` |
| release | v0.6.6 immutable 릴리스(빌드·검증·attest·publish) | release-ship run `44686531196` success; `v0.6.6` published `06:23:23Z`, immutable |
| consumer | nim-json-rpc admission에 `certificate-evidence` guard 추가, v0.6.6 고정 | `Archright/nim-json-rpc#4`, merge `5e676378660ea76f635ed3db9a7398dff251272b` |
| acceptance record | canonical master run + negative control 기록 | `Archright/nim-json-rpc#5`, merge `35a0c09e5430ef9722e3df5bc010eb6394b69a95` |
| 경계 강제 | direct proof boundary 전 행을 테스트로 옮기고 required CI에 연결 | Axiom PR #249, merge `ce643c1f6dc880ad412cfcd1c7e30c348de94940` |

---

## §3. acceptance 관측

### 3.1 G0 권위 재실행 (producer 단독)

두 개의 독립 실행 leg가 같은 인증서 집합을 export했다:

- `certificateSetDigest` = `f5694f1abca06cd2fbd0c46ae7a56cf79ac627c9d5c67a74915a7d4cfbf59e66`
- leg A == leg B, `certificateCount = 1`, `ax cert verify-export` 양쪽 PASS

### 3.2 첫 live consumer run

`Archright/nim-json-rpc` PR #4, run `44689066001` (head `6b133cb`, conclusion `success`):

- `certificate-evidence` job success
- 두 leg digest 동일: `0957d64f5044ec4140b73b990f22f46e3af24c910b0962ab19985988ebd9c863`
- artifact digests: A `sha256:189dacf7923db8533809d3d3fd54c8d546980df90f1f8896569ad5a69c64ddde`, B `sha256:daa26d437c7a6aa64c2f7affc1540d0bed8df1f85541bbfbe00f48f51ca49f7c`
- guards: `CERTIFICATE_EVIDENCE`, `CERTIFICATE_INTEGRITY`, `ARTIFACT_PROVENANCE`, `LEG_DIGEST_EQUALITY` 모두 PASS

### 3.3 canonical master admission run

PR #5의 `pull_request` subject(base `5e676378660ea76f635ed3db9a7398dff251272b`), run `44690942294` (head `c3eb84fa67b975ffeb50f5ae31845f6aefd705fc`, conclusion `success`, required checks 포함 29개 success):

- `certificate-evidence` job success
- 두 leg digest 동일: `f326af6710e9d6591bf74d34d0748ea202da17209781dae657055d3423020ca5`
- artifact digests: A `sha256:b10c713d9c7070fd0fae44ac615635be2e02e69d17e17e8d510a2f9316d5a78b`, B `sha256:9d479375bb312e4b0aafe5f433cac3e9bf4c55581c28985acb7f22e5f7a809f5`
- 같은 digest가 두 번의 독립 leg 실행에서 재현됨

### 3.4 targeted negative control (canonical run 기준)

`ax-evidence-negative-control.yml`, run `44695314036`, base run `44690942294`, verdict `PASS`:

| 변조 | 기대 reasonCode | 관측 reasonCode | exit |
|---|---|---|---|
| body-removal | `CERT_BODY_MISSING` | `CERT_BODY_MISSING` | 1 |
| status-tamper | `CERT_STATUS_MISMATCH` | `CERT_STATUS_MISMATCH` | 1 |
| digest-tamper | `CERT_SET_DIGEST_MISMATCH` | `CERT_SET_DIGEST_MISMATCH` | 1 |
| observation-loss | `AXIOM_OBSERVATION_MISSING` | `AXIOM_OBSERVATION_MISSING` | 1 |

각 복사본은 **하나의 속성만** 깨뜨리고 나머지 무결성 계층은 일관되게 유지한다. 따라서 위 reasonCode는 일반 digest 오류가 아니라 의도한 안전장치가 실제로 작동했다는 증거다. 동일한 4종은 첫 live run(`44689066001`)을 base로 한 run `44690841561`에서도 4/4 PASS였다.

### 3.5 #119 경계 강제 (별도 workstream)

- `docs/spec/direct_proof_boundary.md`의 규범적 행 전체를 `tests/trusted/test_direct_proof_boundary.nim`(581줄)로 옮겼다.
- `Makefile`: `verify-contract-release-e2e-full: verify-proof-boundary` — required `axiom-operational-slice`가 실행하는 target의 선행 조건.
- canonical main(`ce643c1`)의 `axiom-operational-slice` run `44691614592` success, 로그에서 `=== [verify-proof-boundary] direct proof boundary conformance ===` … `✅ verify-proof-boundary PASSED` 확인.
- #119는 `2026-11-20T02:02:42Z` CLOSED 상태이며, #249는 그 계약을 **자동 집행**으로 전환한 후속 작업이다. #119를 재오픈하지 않는다.

---

## §4. reproduce

```bash
# canonical admission run
gh run view 44690942294 -R Archright/nim-json-rpc

# negative control (same base)
gh workflow run ax-evidence-negative-control.yml -R Archright/nim-json-rpc \
  --ref master -f run_id=44690942294

# #119 boundary enforcement on canonical main
gh run view 44691614592 --log | grep -E "verify-proof-boundary|direct proof boundary"
```

---

## §5. Non-claims (명시적 경계)

- `verify-export`는 **같은 엔진의 tier 권위를 재사용**한다. exporter와 verifier가 같은 구현 버그를 공유하면 둘 다 PASS할 수 있다. 독립 의미 재구현이 아니다.
- GitHub attestation은 **artifact provenance**를 증명하며, certificate body의 의미적 진실을 증명하지 않는다.
- digest 동일성은 **하나의 run·하나의 subject 안**에서 주장된다. 서로 다른 subject commit 간 digest 동일성을 주장하지 않는다.
- 기록된 digest는 문서 갱신 전 head의 run에 속한다. 문서 커밋 자체의 run은 새 subject이므로 digest가 달라질 수 있다.
- `--sign` 경로의 provenance 공백(#253), Rust lane의 export portability(#247), attestation 없는 Lean 인증서의 replay 결속(#246)은 이 슬라이스의 범위가 아니며 별도 workstream이다.
- #119의 강제는 **선언된 subset의 준수**를 검사한다. 인증 가능 범위 자체를 확장하지 않는다.

---

## §6. 남은 위험 (Follow-up, 이 acceptance에 포함되지 않음)

| 이슈 | 왜 이 슬라이스로 닫히지 않는가 |
|---|---|
| #253 | `--sign`은 관측을 재실행하지 않으므로 자기일관 위조와 실제 관측을 구별하지 못한다. 신뢰 모델 선택이 필요하다. |
| #246 | attestation 없는 인증서의 정리·source 교체 replay 결속은 PR #238 계열에서 다뤄진다. |
| #247 | Rust lane vault가 exporter가 요구하는 manifest/inventory를 쓰지 않는다. 생산 경로 수정이 필요하다. |
| #256 | admission verifier가 이전 run 완료를 현재 head에 결속할 수 있는 경합. |
| Rust coverage (#219/#224/#226/#228/#229) | 인증 가능 범위·성능·assurance 표기의 제품 계약 문제다. |