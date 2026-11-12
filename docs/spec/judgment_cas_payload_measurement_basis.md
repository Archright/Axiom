# Judgment CAS payload 정준 카운트 — 측정 근거 (Measurement Basis)

> **Status**: 측정 근거 문서 — 코드 상수의 사후 문서화 (SL-15 사후 문서화 선례 준용; 코드·상수 무변경).
> **정본 계약**: `docs/spec/test_judgment_cas_contract.md` (§4 9성분 closure, §5 REUSED 5조건, §7 non-signature).
> **상수 SSOT**: `src/verification/judgment_cas.nim` (커밋 `6767884e7` 기준 라인 인용).
> **작성일**: 2026-10-09. **측정 커밋**: origin/main `6767884e7111c94164a6981e0e5bb4370e984e03` (PR #622 병합).
> **등록 문서**: 발견·분석 등록은 `docs/evidence/jcas_phase23_registrations_2026-10-09.md` (R1–R4).

---

## 1. 목적과 범위

4주체(`s1a` · `proof_integrity` · `d2_golden` · `d2_persist`) payload 계약 상수는 현재
**코드 상수 + 코드 주석으로만 존재**한다. 본 문서는 각 수치의 **측정 출처**(어느 테스트 파일의
어느 호출부가 그 수를 산출하는가, 어떤 단정이 그 수를 계약으로 고정하는가, CI에서 어떤 관측이
그 수와 합치하는가)를 호출부 단위로 문서화한다.

- **이 문서가 하는 것**: 상수 값의 측정 근거 열거. 수치 자체의 개정이 아니다.
- **이 문서가 하지 않는 것**: 코드·상수·테스트 변경. 수치 불일치가 발견되면 본 문서는 그것을
  기록하고 등록 문서에 후속 항목으로 올린다 (R4 — `test_d2_golden.nim` 카운터).
- **측정 근거의 성격**: 상수는 *측정의 핀*이다 — "a run with any other count is not the
  canonical judgment" (`judgment_cas.nim:143-144`). 즉 수치는 재량이 아니라, 테스트 스위트의
  실제 반복 구조(census)에서 산출된 관측값이며, flush 단정 + parse-side fail-closed 이중으로
  재검증된다.

## 2. s1a — `kernelAcceptCount = 17` · `probeCount = 14` · `acceptsByTheorem = [3,2,1,11]`

**상수**: `judgment_cas.nim:140` (17), `:145` (14), `:159` ([3,2,1,11], 정렬 순서
`identityPostcondition_post` · `mulDivRoundtrip_post` · `normalizeMaxWorkers_post` ·
`subPostcondition_post`).

**측정 출처**: `tests/unit/test_s1a_lean_golden.nim`의 커널 호출 census.
커널 실행 경로는 정확히 2종이다:

1. **직접 호출** — 테스트가 `canonicalLeanKernelCheck`를 직접 호출: **3회**
   (`test_s1a_lean_golden.nim:145` · `:163` · `:223`).
2. **체인 프로브** — `execGolden` → `executeCanonicalVerification` → 내부
   `runKernelCheck`(`canonical_verification.nim:1415`, 함수 내 정확히 1회) →
   `canonicalLeanKernelCheck`: **14회** (아래 §2.2 표).

17 = 3 + 14. 모든 경로는 같은 `canonicalLeanKernelCheck`(실제 Lean 4.33 `lake env lean`)
을 통과하므로 17개 ACCEPT fact의 정리 identity는 영수증의
`receiptTheoremIdentity`로 관측된다.

### 2.1 커널 반복 의미 매핑 표 — 17회 각 호출의 담당 의무

"쌍(pair)"은 **반복이 정의상 요구되는 단정**이다: 같은 입력 ≥2회 실행이어야만
식별 동일성(결정론·지문·투영 안정성)을 단정할 수 있고, splice 저항은 서로 다른 두
진실 실행이 있어야만 교차 조립을 시도할 수 있다.

| # | 호출부 (test_s1a_lean_golden.nim) | 정리 identity | 담당 의무 | 쌍 요건 |
|---|---|---|---|---|
| D1 | `:145` (직접) | `normalizeMaxWorkers_post` | 렌더러 산출물(`def`+I6 정리)의 커널 수용 — 영수증 4필드(64-hex: executableDigest/inputIdentity/artifactIdentity + 정리 identity) 단정 | — |
| D2 | `:163` (직접) | `mulDivRoundtrip_post` | boMul/boDiv Certified-subset 하강(`*`, 고정 제수 `/`)의 커널 수용 | — |
| D3 | `:223` (직접) | `identityPostcondition_post` | identity fixture(`fun x => x`)의 직접 커널 수용 | — |
| P1 | `:178` (sub 체인) | `subPostcondition_post` | 전체 체인 양성 통제: `vdVerified` · 6-fold identity(input/ir/obligation/leanSource/kaa/artifact) · `toolchainIdentity` 형상. **첫 sub 실행 = 판정 증거 fold+CLE 캡처 지점** (`:91-105`) | — |
| P2 | `:203` (mulDiv 체인) | `mulDivRoundtrip_post` | mul body end-to-end 양성 통제 (`sealError == ""`) | — |
| P3 | `:226` (identity 체인) | `identityPostcondition_post` | identity end-to-end (`vdVerified`) | — |
| P4 | `:232` (sub 체인) | `subPostcondition_post` | **결정론 쌍 (a)** — P5와 동일 입력 2회 실행으로 irHash/obligationHash/leanSourceHash/kaaIdentity/artifactIdentity 동일 단정 (`:244-248`) | ≥2회 정의 |
| P5 | `:237` (sub 체인) | `subPostcondition_post` | 결정론 쌍 (b) — 위 참조 | ≥2회 정의 |
| P6 | `:253` (sub 체인) | `subPostcondition_post` | **지문 쌍 (a)** — P7과 동일 입력 2회 실행으로 `cleToolchainFingerprint` 동일 단정 (`:267`) | ≥2회 정의 |
| P7 | `:258` (sub 체인) | `subPostcondition_post` | 지문 쌍 (b) — 위 참조 | ≥2회 정의 |
| P8 | `:276` (sub 체인) | `subPostcondition_post` | 구상수 거부: 구(舊) 하드코딩 공식 `sha256("nim-2.2.10|lean-4.33.0|lake env lean|120000")` ≠ 측정 번들 digest (`:273-283`) | — |
| P9 | `:297` (sub 체인) | `subPostcondition_post` | CLE 내부 해시 결속 독립 재계산(propositionHash/leanSourceHash/kaaDigest) + KAA sorry-free (`:306-311`) | — |
| P10 | `:314` (sub 체인) | `subPostcondition_post` | `evidenceId = H(6성분)` 재계산 + obligationId↔propositionHash 해시 공간 분리 (`:320-327`) | — |
| P11 | `:330` (sub 체인) | `subPostcondition_post` | **KAA 투영 쌍 (a)** — P12와 동일 입력 2회 실행으로 `cleCanonicalKaaJson`/`cleKaaDigest`/`evidenceId` 안정 단정 (`:339-341`) | ≥2회 정의 |
| P12 | `:333` (sub 체인) | `subPostcondition_post` | KAA 투영 쌍 (b) — 위 참조 | ≥2회 정의 |
| P13 | `:353` (sub 체인) | `subPostcondition_post` | **splice 쌍 (A측)** — 진실 실행 A; P14(진실 실행 B)와의 교차 조립 거부 단정의 한쪽 (`:380-400`) | 서로 다른 2회 정의 |
| P14 | `:357` (identity 체인) | `identityPostcondition_post` | **splice 쌍 (B측)** — (a) B-source×A-KAA 거부, (b) A-source×B-KAA 거부; KAA↔source hash binding(`receiptArtifactIdentity == sha256(source)`)이 splice 장벽 | 서로 다른 2회 정의 |

**계약 유도 검증**: 정리별 집계는 `CanonicalAcceptsByTheorem`와 정확히 합치한다 —
`identityPostcondition_post` 3 = D3 + P3 + P14 (1 직접 + 2 체인) · `mulDivRoundtrip_post` 2 =
D2 + P2 (1 + 1) · `normalizeMaxWorkers_post` 1 = D1 (0 체인, 직접만) ·
`subPostcondition_post` 11 = P1,P4–P13 (모두 체인). 합 = 3+2+1+11 = 17.

**계약 고정 장치**:
- flush 단정 (`test_s1a_lean_golden.nim:413-418`): `accepts.len == CanonicalKernelAcceptCount`
  ∧ `facts.acceptsByTheorem == CanonicalAcceptsByTheorem` ∧ `judgmentProbeCount ==
  CanonicalProbeCount` ∧ fold/CLE 캡처 완료.
- parse-side fail-closed (`judgment_cas.nim:795-820`): payload의
  kernelAcceptCount/probeCount/acceptsByTheorem 불일치·미지 정리 = 기록 거부.
- CI 라이브 관측: PR-run `37811664465`(#611 세대, 2026-10-08T17:04:03Z)
  `MINT_JUDGAPPEND: OK — judgment record appended (key b5b10096965b, append exactly-once: 1)`
  — 17-fact 집합이 통과한 레코드의 실제 원장 편입.

### 2.2 probe 14회 목적 열거

`probeCount`의 측정 단위는 `execGolden` 호출부이다 (`:85-106` — 성공 체인 프로브마다
`judgmentProbeCount` 1 증가). 14회의 목적 분할:

| 목적 | 횟수 | 호출부 | 단정 내용 |
|---|---|---|---|
| 전체 체인 양성 통제 (주제별 1회씩) | 3 | P1(sub) · P2(mulDiv) · P3(identity) | 주제별로 체인이 `vdVerified`에 도달 |
| sub-determinism | 2 | P4 · P5 | 동일 입력 2회 → 5성분 identity 동일 |
| toolchain-fingerprint determinism | 2 | P6 · P7 | 동일 입력 2회 → 측정 번들 지문 동일 |
| old-constant negative | 1 | P8 | 구상수 지문과 측정 지문 불일치 |
| canonical-evidence 결속 | 1 | P9 | CLE 3해시 독립 재계산 + KAA sorry-free |
| evidenceId 재계산 | 1 | P10 | H(6성분) 공식 + 해시 공간 분리 |
| KAA-projection determinism | 2 | P11 · P12 | 동일 입력 2회 → KAA 투영/ digest/evidenceId 안정 |
| splice resistance | 2 | P13 · P14 | 서로 다른 두 진실 실행의 교차 조립 거부 |
| **합계** | **14** | | = `CanonicalProbeCount` |

**측정 근거 정합성 비고 (주석 정정 기록 — 코드 미변경)**:
`judgment_cas.nim:146-149` 주석의 범주 나열("…2 sub-determinism + 4
toolchain-fingerprint + 1 old-constant + …")은 그대로 합산하면 16이 되어 상수 14와
산술적으로 정합하지 않다. 위 표의 호출부 census가 측정 분할이며, 상수 14와
`[3,2,1,11]`이 정규 계약값이다 (flush 단정이 매 실행 강제). 주석의 "4
toolchain-fingerprint"는 실측 2회(결정론 쌍)로 본 문서가 정정 기록한다 — 본 슬라이스는
코드 무변경이므로 주석은 그대로 남고 본 절이 근거를 대체한다.

### 2.3 관측 provenance 제외 성격

payload는 관측 provenance(observedAt, kernel stdout, run ids)를 배제한다
(`judgment_cas.nim` — "a record is a fact, not a run"). 따라서 17/14/[3,2,1,11]은
런 간 불변이다.

**착지 갱신 (2026-10-09, R2 기제 개선 — payload 순수화)**: §R2에 등록된 "payload
바이트 전체는 런 스코프 성분을 포함할 수 있어" 균열은 수리되었다. 원인 성분은 s1a
payload의 `cle.evidenceId`였다 — CLE 바인딩(boundId)이 §2.1a `subjectGitRef`
(체크아웃 HEAD **커밋** 해시)을 전이 흡수해, 같은 클로저(같은 tested tree)의 두 런이
커밋만 다름(브랜치 헤드 vs merge-queue 머지 커밋)으로써 다른 payload 바이트를
생성했다(원장 실측: s1a 레코드 20건에서 evidenceId 20/20 상이, 나머지 CLE·fold
성분은 세대 상관 불변). 수리: `cle.evidenceId`를 payload·캡처 타입에서 제거(§2.1a
자체는 비개정 — 계약 §4 v1.0.2 ③ "run HEAD = identity 비참여"의 구조적 강제),
validator가 정준 필드 집합을 **exact** 강제해 런 스코프 성분의 재유입을 차단,
`JudgmentKeyScheme`/`JudgmentPayloadSchema`를 v2로 세대 전환해 구세대(v1) 레코드와의
same-key 충돌을 원천 배제한다. payload는 이제 클로저의 순수 함수다 — 같은 클로저 ⇒
같은 키 + 같은 payload 바이트 (드릴: `test_judgment_cas.nim` G10).

## 3. proof_integrity — `ProofIntegrityCheckpointCount = 12` (커널 0회)

**상수**: `judgment_cas.nim:212` (12), `:222-234` (체크포인트 이름 정렬 배열),
`:236-259` (정렬 판정 배열).

**측정 출처**: `tests/unit/proof_integrity_test.nim`의 술어 배터리 — `jcap(name,
verdict)` 캡처 지점 **12곳** (`:93` · `:105` · `:117` · `:126` · `:136` · `:140` ·
`:156` · `:170` · `:183` · `:198` · `:210` · `:222`). 순수 술어 배터리로 **커널 실행
0회** — 판정은 `isVkdAdmissible`/`isDeepVerified`/`symbolInKernelScope`/admission 판정의
관측값이다.

| # | 체크포인트 | 캡처 지점 | 관측 대상 술어 | 정준 판정 |
|---|---|---|---|---|
| 1 | `admissionAdmit` | `:156` | admission 판정 | `varAdmit` |
| 2 | `admissionExemptIsScopeInconsistency` | `:170` | admission 판정 | `varScopeInconsistency` |
| 3 | `admissionNoObligationRejects` | `:183` | admission 판정 | `varReject` |
| 4 | `emptyScopeDegradedMode` | `:126` | `isDeepVerified` (빈 scope — Set Membership skip) | `dvcSuccess` |
| 5 | `freshCertAccepts` | `:222` | `isDeepVerified` (fresh cert) | `dvcSuccess` |
| 6 | `kernelScopeSymbolInDenominator` | `:136` | `symbolInKernelScope` | `true` |
| 7 | `kernelScopeSymbolOutOfDenominator` | `:140` | `symbolInKernelScope` | `false` |
| 8 | `kernelSymbolInDenominator` | `:93` | `isDeepVerified` (kernel cert, in-scope) | `dvcSuccess` |
| 9 | `kernelSymbolNotInDenominator` | `:105` | `isDeepVerified` (kernel cert, out-of-scope) | `dvcNotInKernelScope` |
| 10 | `nonKernelMemberNotChecked` | `:117` | `isDeepVerified` (non-kernel — 3-stage 보존) | `dvcSuccess` |
| 11 | `renewedCertAccepts` | `:210` | `isDeepVerified` (renewed cert) | `dvcSuccess` |
| 12 | `staleCertSourceHashMismatch` | `:198` | `isDeepVerified` (stale source hash) | `dvcNotCurrent` |

**계약 고정 장치**:
- flush 단정 (`proof_integrity_test.nim:252-260`): `judgmentCheckpoints.len == 12` ∧
  정렬 이름 전수 매칭 → `checkpointVerdicts` 구성.
- parse-side fail-closed (`judgment_cas.nim:897-913`): `checkpointCount == 12` ∧
  canonical 이름→판정 맵 exact-set ∧ 비canonical 체크포인트 거부.
- CI 실측: 3subject phase3 증거문서 §1-⑤ (PR-run `37863183512` 22.1s / MG-run
  `37865330190` 계열 39.4s, exit 0 — 12 체크포인트 캡처 관측).
- 라이브 레코드: 아직 없음 — mint P7c-x(PR #626)가 3주체 ledger append 배선이며
  세대 전환 전까지 3종은 무장 실험(flush skip)으로만 실행된다 (§R4 상호참조).

## 4. d2_golden — `D2GoldenKernelRunCount = 14` (커널 14회)

**상수**: `judgment_cas.nim:214-216` — "Stage 1 ×4, Stage 2 ×2, Stage 3 ×2, Stage 4
chain ×5, golden summary ×1".

**측정 출처**: `tests/unit/test_d2_golden.nim`의 커널 sink census — `jCanonical()`
래퍼(`:70-86`, 호출마다 `judgmentKernelRunCount` 증가 `:72`) 13회 + 1회 직접 호출:

| Stage | 횟수 | 호출부 (test_d2_golden.nim) | 담당 의무 |
|---|---|---|---|
| Stage 1 (실제 커널 체크, `:92` suite) | 4 | `:96` · `:108` · `:122` · `:123` | 진짜 theorem의 커널 수용 / 영수증 필드 비공백 / **isGolden 선택자 결정론 쌍**(동일 소스 2회 → 동일 영수증 `:117-123`) |
| Stage 2 (Receipt→KAA, `:133` suite) | 2 | `:136` · `:146` | `bindReceipt`로 KAA 생성 / KAA 불투명성(accessor 경유 접근) |
| Stage 3 (KAA→vdVerified, `:155` suite) | 2 | `:158` · `:168` | clean KAA 평가 / **판정이 evaluate() 산출이지 하드코딩 아님** |
| Stage 4 (C1 identity closure, `:185` suite) | 5 | `:211` · `:231` · `:255` · `:285` · `:334`(직접) | ArtifactIdentity=H(artifact) · ExecutionIdentity=H(3성분) · KAAIdentity=H(투영) · DecisionIdentity=H(2성분) · CanonicalResultIdentity=H(2성분) + **5성분 결정론 체인 재유도** |
| Golden summary (`:363` suite) | 1 | `:377` | Stage 1–4 재주행 + 5-fold C1 chain 캡처(`jcapChain`) + 전 필드 64-hex 단정 |
| **합계** | **14** | | = `D2GoldenKernelRunCount` |

**정합성 비고 (발견 — 등록 R4)**: 14회 중 13회만 `jCanonical` 카운터를 경유한다.
`:334`(Stage 4 "all 5 C1 identities form a deterministic closure chain")는 래퍼 없이
직접 `canonicalLeanKernelCheck(artifact).get()`을 호출해 카운터 미증가 → 무장 로컬/CI
실행(플러시 skip)에서는 관측 불가하나, **무장(armed) 플러시**(`:455`)는
`judgmentKernelRunCount == 14`를 단정하므로 13 ≠ 14로 FAIL한다. 지금까지의 CI 실행은
구세대 핀(s1a-only evidence env)이라 3종이 모두 무장 실행이었으므로 이 결함은
잠복 상태이며, mint P7c-x(PR #626) 세대 전환에서 첫 발화가 예상된다. 전문·재현:
등록 문서 R4.

**계약 고정 장치**: parse-side fail-closed (`judgment_cas.nim:939-940`:
`kernelRunCount != 14` 거부; `:1227`: 관측 run 수 != 14 거부) — flush가 쓴 카운트와
attest가 재유도한 카운트 양쪽이 14를 강제.

## 5. d2_persist — `D2PersistKernelRunCount = 1` + 루프 체크포인트 7

**상수**: `judgment_cas.nim:217-218` (커널 1회), `:261-269` (writer→reader 루프
체크포인트 7개 정렬 배열).

**측정 출처**: `tests/unit/test_d2_persist.nim`의 main() 흐름 — Stage 1에서 커널
**1회** (`:47` `canonicalLeanKernelCheck(D2GoldenSource)`, `:52`
`inc judgmentKernelRunCount`), Stage 2–5는 바인딩/평가/실제 `cert_writer` 경유 영구
저장/무결성 재판정(커널 재실행 없음). 루프 체크포인트 7개는 `:151-152`에서
`CanonicalD2PersistLoopCheckpoints` 이름별로 **관측값**을 매핑하고 `:161`
`jcapLoop`로 캡처한다:

| # | 체크포인트 | 관측 대상 (test_d2_persist.nim `:151-152` case) | 정준 판정 |
|---|---|---|---|
| 1 | `evidenceLeanVerified` | `evidence.leanVerified` | true |
| 2 | `kernelFlagFromKaa` | KAA 경유 `kernelVal` | true |
| 3 | `leanCompilerVerified` | `leanCompilerVerified` | true |
| 4 | `statusCertLeanVerified` | `statusVal == "certLeanVerified"` | true |
| 5 | `statusConsistentWithEvidence` | `statusConsistentWithEvidence(certNode)` | true |
| 6 | `tierLeanVerified` | `tierVal == "lean-verified"` | true |
| 7 | `writerPersisted` | `writeCertificateFromUapResult` 성공 | true |

**계약 고정 장치**: parse-side fail-closed (`judgment_cas.nim:986-987`:
`kernelRunCount != 1` 거부; `:995-1003`: 7 체크포인트 중 하나라도 false/누락이면
"an unverified loop checkpoint is never a reusable judgment" 거부). flush
(`test_d2_persist.nim:172-186`): 무장 시 캡처 부재·재파싱 불일치 = FATAL.

## 6. 재유도 명령 (측정 근거의 기계 검증)

```bash
# s1a — 커널 호출 census (17 = 3 직접 + 14 체인)
grep -n "canonicalLeanKernelCheck(" tests/unit/test_s1a_lean_golden.nim        # 3 직접
grep -cn "execGolden(" tests/unit/test_s1a_lean_golden.nim                     # 15 (14 호출 + 1 정의)
grep -n "runKernelCheck" src/verification/obligation/canonical_verification.nim # :1415 단일 호출부
grep -n "CanonicalAcceptsByTheorem\|CanonicalKernelAcceptCount\|CanonicalProbeCount" src/verification/judgment_cas.nim

# proof_integrity — 12 캡처 지점
grep -c "jcap(" tests/unit/proof_integrity_test.nim                            # 13 (12 캡처 + 1 proc 정의)
grep -n "ProofIntegrityCheckpointCount" src/verification/judgment_cas.nim      # :212 · :897

# d2_golden — 14 실행 / 13 카운터 (R4)
grep -n "jCanonical()\|canonicalLeanKernelCheck(\|inc judgmentKernelRunCount" tests/unit/test_d2_golden.nim

# d2_persist — 1 실행 + 7 루프 체크포인트
grep -n "canonicalLeanKernelCheck\|inc judgmentKernelRunCount\|CanonicalD2PersistLoopCheckpoints" tests/unit/test_d2_persist.nim
grep -n "D2PersistKernelRunCount\|D2GoldenKernelRunCount" src/verification/judgment_cas.nim

# 스위트 실측 (플러시 무장 경로 제외 — unarmed)
make test-fast-one T=tests/unit/test_s1a_lean_golden.nim   # 17 ACCEPT / 14 probe 강제 경로
make test-fast-one T=tests/unit/proof_integrity_test.nim
make test-fast-one T=tests/unit/test_d2_golden.nim
make test-fast-one T=tests/unit/test_d2_persist.nim
```

## 7. 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-10-09 | 4주체 정준 카운트 측정 근거 초안 — s1a 17회 커널 의미 매핑 표 + probe 14회 목적 열거(주석 산술 불일치 정정 기록), proof_integrity 12 체크포인트, d2_golden 14 실행(+R4 카운터 불일치 발견), d2_persist 1+7. 등록: `docs/evidence/jcas_phase23_registrations_2026-10-09.md` |
