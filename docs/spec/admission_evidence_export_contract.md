# Admission Evidence Export Contract — Certificate Body · Inventory · Tier Binding

> **Status**: Proposed (2026-11-20) — docs-first 계약. 본 문서는 #188의 artifact 실측을 근거로 admission/verify evidence bundle이 **검증 상태를 주장하는 entry의 certificate 본문과 그 결속 정보를 export**하도록 요구한다. 구현(engine exporter·소비자 워크플로)은 별도 변경이며, 본 문서는 그 acceptance criteria와 fail-closed 경계를 정의한다.
> **Created**: 2026-11-20
> **AGENTS.md reference**: §0.5 (문서 우선), §0.9 (극장 금지 — status 문자열을 증거로 대체하지 않는다), §0.12 (제품 계약 선행 — 구현 전 terminal outcome 정의), §2.2 (범위는 닫힌다 — 소비자 저장소 수정은 별도), §2.6 (변경 불변조건 — authority·state transition·failure semantics·proof)
> **Related**: [verification_density.md](verification_density.md) (Green/tier 계약), [cert_lifecycle_contracts.md](cert_lifecycle_contracts.md) (vault lifecycle), [external_verification_campaign_contract.md](external_verification_campaign_contract.md) (§5 evidence artifact·§7 내구성), [proof_required_admission_contract.md](proof_required_admission_contract.md) (vault certificate binding), [direct_proof_boundary.md](direct_proof_boundary.md), [adopted_model_observation_contract.md](adopted_model_observation_contract.md) (#119), [issue #188](https://github.com/Archright/Axiom/issues/188)

---

## 0. 문제 정의 — 관측된 결손

2026-11-18 run `44253688052`(Archright/nim-json-rpc, PR #2) artifact를 직접 판독한 결과:

| artifact | 관측 |
|---|---|
| `ax-verify-evidence-propositions-B/vault-manifest.json` | 17 entries; entry 필드는 정확히 `{modulePath, functionName, status, solverMethod, lastVerifiedAt, irHash}` 6개. status 분포: `certGreen` 13, `certRed` 3, `certZ3Candidate` 1 |
| `ax-verify-evidence-propositions-B/vault-certificates.txt` | `389a744384f1b465393b00d8dacb93b3d660603e948507ff3857db640195b771.json` + `manifest.json` 2줄 |
| 실제 B artifact 파일 | `389a7443…json` certificate 본문 **부재**. `manifest.json`은 release bundle manifest(547 bytes)이며 vault manifest가 아니다. vault manifest는 `vault-manifest.json`으로 존재 |
| `mutation-contrast-evidence/vault-certificates.txt` | `manifest.json` 1줄; certificate 본문 0건 |
| `mutation-contrast-evidence/vault-manifest.json` | 17 entries; `certGreen` 11, `certRed` 5, `certZ3Candidate` 1 |
| `admission-verdict/admission-verdict.json` | `acceptance_class: "proof"`, `evidence_tier: "verified"` 선언. certificate digest/theorem/axiom 필드 없음 |
| `ax-verify-evidence-propositions-B/verify-record.json` | `prove_exit`·`canonical_digest`·`engine_build_id`·`verdict_summary`·`zero_footprint_ok`·`runner_image`·subject/axiom/toolchain/tree/state digest 필드. certificate 결속 필드 없음 |

**원인 (관측된 생산자 행동)**:

1. 소비자 워크플로가 vault 디렉터리의 `manifest.json`만 `vault-manifest.json`으로 복사하고, `find "$vault" -maxdepth 1 -name '*.json' -printf '%f\n'`로 inventory를 만든다. inventory는 **source vault**의 파일명이며 destination에 업로드된 파일 집합이 아니다 — 그래서 목록과 artifact가 불일치한다.
2. vault certificate 본문은 export 단계에서 복사되지 않는다.
3. manifest entry 스키마에 certificate 신원·theorem·axiom 관측 필드가 없다.
4. `admission-verdict.json`/`verify-record.json`이 certificate 집합에 결속되지 않은 채 `evidence_tier=verified`를 선언한다.

**귀결**: 외부 검증자는 `status: "certGreen"` 문자열을 신뢰해야 한다. 엔진 자체는 status 문자열을 신뢰하지 않고 certificate 본문에서 tier를 재도출한다 — `src/verification/analyzer/stage_02_fingerprint.nim:74-79`(certGreen 주장 시 `certificateEvidenceFromJson → tierFromEvidence → tierToCertStatus`), `src/verification/cert_promotion.nim:425`(과장된 certGreen을 `certZ3Candidate`로 재분류). 그 본문이 bundle 밖에 있으므로 독립 재검증이 불가능하다. status 문자열은 증거가 아니다(§0.9).

---

## 1. 범위와 권위

### 1.1 범위

본 계약은 admission/verify workflow가 업로드하는 **evidence artifact의 vault 부분**과 그 결속 필드를 정의한다:

- vault manifest (`vault-manifest.json`)
- vault certificate 본문 (`<irHash>.json`)
- vault inventory (`vault-certificates.txt`)
- admission verdict / verify record의 certificate 결속 필드

### 1.2 범위 밖

- certificate 서명 스키마·witness wire 변경(`src/verification/attestation_witness.nim`, [certification_continuity_contract.md](certification_continuity_contract.md)) — 별도 open decision.
- 소비자 저장소(Archright/nim-json-rpc 워크플로)의 구현 변경 — 별도 PR.
- 공개 어댑터(`Archright/axiom-cli`의 `.github/workflows/ax-verify.yml`) 구현 변경 — 별도 PR.
- certificate 재민트·policy digest 회전 — 구현 PR의 절차.
- vault certificate의 내용(무엇을 증명했는가)의 변경.

### 1.3 권위

- certificate status/tier의 **유일한 판정 권위**는 certificate 본문을 읽는 기존 엔진 투영이다: `certificateEvidenceFromJson` → `tierFromEvidence` → `tierToCertStatus`(`src/verification/analyzer/stage_02_fingerprint.nim:74-79`, `:122-125`). 본 계약은 새 tier authority를 만들지 않는다.
- 본 계약의 `recomputedStatus`는 그 투영의 **export 시점 기록**이며, 새 판정이 아니다.
- export/consumer는 status 문자열을 tier의 근거로 사용할 수 없다.

---

## 2. 정규 export 집합

### 2.1 정의 — Vault export set

Artifact 디렉터리에서 다음 basename을 가진 파일의 집합:

1. `vault-manifest.json`
2. 64자 소문자 hex + `.json` — vault certificate 본문(basename = irHash, `src/verification/vault_manifest.nim`의 content-address 규약).

release bundle manifest `manifest.json`, `verify-record.json`, `admission-verdict.json`, trajectory/log 등은 vault export set이 **아니다**.

### 2.2 E1 — Certificate 본문 export

- `vault-manifest.json`의 모든 entry에 대해, 대응하는 vault certificate 파일이 존재하면 **반드시 export**한다.
- `status ∈ {certGreen, certLeanVerified, certDualVerified, certTypeLevelVerified, certSafetyVerified}`(`isVerifiedCertificateStatus`, `src/core/types/certificate_types.nim:108-113`)인 entry는 certificate 본문이 **필수**다.
- certificate 본문은 canonical vault 파일과 **byte-identical**이어야 한다.
- `certZ3Candidate`는 `isVerifiedCertificateStatus`가 아니다 — 검증 주장이 아니며, 본문이 존재하면 export하되 verified로 해석하지 않는다.
- `certRed`/`certPending`/`certStale` 등도 본문이 존재하면 export한다 — 음성 대조에서 어떤 certificate가 반증되었는지 확인하기 위해서다.

### 2.3 E2 — Inventory exact match

- `vault-certificates.txt`는 export set의 모든 basename을 **정렬된** 1줄 1파일로 나열한다.
- `vault-certificates.txt`의 행 집합 == export set의 basename 집합(exact match, 중복 없음).
- inventory는 **destination에 복사된 뒤** 생성한다 — source vault listing을 복사하지 않는다.
- `vault-manifest.json`도 export set의 멤버이므로 inventory에 포함된다. release `manifest.json`은 포함되지 않는다.
- 실패 시 `CERT_INVENTORY_MISMATCH`(§3).

### 2.4 E3 — Manifest export projection

`vault-manifest.json`은 runtime manifest의 **export projection**이다. 기존 6필드는 보존하고, 각 entry에 다음 필드를 추가한다(schema `version: 3`):

| 필드 | 정의 |
|---|---|
| `certificateFile` | export된 certificate basename 또는 `null` |
| `certificateSha256` | export된 certificate 파일 바이트의 SHA-256; `certificateFile == null`이면 `null` |
| `recomputedStatus` | certificate 본문에 대한 기존 엔진 투영 결과 `tierToCertStatus(tierFromEvidence(certificateEvidenceFromJson(cert)))`; 본문이 없으면 `null`. verified entry에서 `status`와 **일치해야 한다** |
| `theoremIdentity` | kernel re-execution이 `#print axioms`로 관측한 선언 이름. 현행 엔진은 `firstDeclaredName(leanSource)`(`src/verification/kernel_reexecution.nim:159-174`); `leanSource`가 없는 Z3-only certificate는 `null`. 명시적 관측 대상이 기록되면 그 값이 우선한다 |
| `axiomObservation` | `{"status": "observed"|"not-observed"|"not-applicable", "names": [ ... ]|null}`. `observed`: `#print axioms` 결과를 파싱함(`names`는 관측 union, 빈 배열 = kernel-pure). `not-observed`: 관측 기록 없음(legacy mint 또는 재실행 미보존). `not-applicable`: `leanSource` 없음(Z3-only); `names: null` |

- runtime `vault_manifest.nim`의 `ManifestEntry`·TrustCommit claim·signed certificate bytes는 이 계약으로 변경하지 않는다. E3는 **export projection에만** 적용된다 — certificate identity(`evidenceDigest`/`subjectId`/`identityDigest`)를 보존하기 위한 결정이다.
- `contentHash`/`fingerprint` 등 runtime manifest에 이미 있는 필드는 보존한다.

### 2.5 E4 — Certificate set digest

Export producer는 다음 canonical JSON의 SHA-256을 `certificateSetDigest`로 기록한다:

```json
{
  "schema": "axiom.admission.cert-set.v1",
  "certificates": [
    {"file": "<basename>", "sha256": "<hex>", "modulePath": "...", "functionName": "...",
     "status": "...", "recomputedStatus": "...", "theoremIdentity": "..."|null,
     "axiomObservation": "observed"|"not-observed"|"not-applicable"}
  ]
}
```

- `certificates`는 `file` 기준 정렬, 키 정렬 canonical JSON(기존 canonical projection / RFC 8785).
- `vault-manifest.json`과 `vault-certificates.txt`는 이 digest에 포함하지 않는다 — digest는 certificate 본문 집합만 결속한다.
- 동일 export set → 동일 digest(deterministic).

### 2.6 E5 — Verdict/record 결속

- `verify-record.json`은 `certificate_set_digest`와 `certificate_bodies_present`(bool)를 기록한다.
- `admission-verdict.json`은 `certificate_set_digest`와 `guards.CERTIFICATE_EVIDENCE`(`PASS|FAIL`)를 기록한다.
- `evidence_tier = "verified"`는 다음 전부가 성립할 때만 허용된다:
  1. 모든 verified-status entry에 certificate 본문이 존재한다.
  2. inventory exact match(E2).
  3. 각 verified entry의 `recomputedStatus == status`.
  4. 각 Lean-dependent verified entry의 `axiomObservation.status == "observed"`.
  5. `certificate_set_digest`가 verdict/record에 결속되어 있다.
- 하나라도 불성립 → `evidence_tier`는 `verified`가 아니다(fail-closed). 기존 verdict 어휘를 재사용하며 새 enum을 만들지 않는다.

---

## 3. 실패 의미 (fail-closed)

reasonCode/journal strings(새 enum 아님 — 기존 `reasonCode: string` 관례):

| code | 조건 | 결과 |
|---|---|---|
| `CERT_BODY_MISSING` | verified-status entry의 `certificateFile`이 null이거나 파일 부재 | `CERTIFICATE_EVIDENCE=FAIL` |
| `CERT_INVENTORY_MISMATCH` | inventory ≠ export set | FAIL |
| `CERT_DIGEST_MISMATCH` | 파일 SHA-256 ≠ `certificateSha256` | FAIL |
| `CERT_STATUS_MISMATCH` | `recomputedStatus` ≠ `status` | FAIL |
| `AXIOM_OBSERVATION_MISSING` | Lean-dependent verified entry의 `axiomObservation.status` ≠ `observed` | FAIL |
| `CERT_SET_DIGEST_ABSENT` | verdict/record에 `certificateSetDigest` 없음 | FAIL |

- FAIL은 `evidence_tier=verified`를 금지한다. `acceptance_class=proof`도 함께 금지한다 — proof 등급은 certificate 본문 결속을 전제한다.
- legacy export(v2 manifest, 본문 없음)는 **소급 재분류하지 않는다**: 기존 artifact는 historical record이며, 새 계약의 `verified` 주장 근거가 될 수 없다. 새 run부터 적용한다.
- `ax cert verify --kernel`의 기존 판정(구조·서명·정책 digest)은 변경하지 않는다. 본 계약은 export 결속만 추가한다.

---

## 4. 검증 가능한 주장의 경계 (Non-claims)

이 계약이 **하는 주장**:

- verified 상태를 주장하는 entry에 대해 certificate 본문이 artifact 안에 존재하고, 그 digest·status projection·theorem identity·axiom observation 상태가 manifest와 verdict에 결속된다.
- 외부 검증자는 export된 `leanSource`/`smtlib2`와 pinned toolchain identity를 사용해 `#print axioms`/Z3를 **독립 재실행**할 수 있다.

이 계약이 **하지 않는 주장**:

- export만으로 certificate의 서명·정책 digest·toolchain identity가 유효함을 증명하지 않는다 — 기존 `ax cert verify`/`cert_integrity_gate`의 판정이 필요하다.
- `recomputedStatus`는 certificate 본문 내부 필드(`solverMeta.leanCompilerVerified`, `z3Executed`)의 일관성 투영이며, 커널 재실행의 증거가 아니다. 독립 재실행은 별도 단계다.
- `axiomObservation=observed`의 `names`는 **mint 시점**의 관측 기록이며, export 시점의 재실행 결과가 아니다(재실행을 기록하면 `source` 필드로 구분한다).
- witness/signed subject certificate의 export는 본 계약이 아니다(open decision).
- 소비자 저장소의 admission workflow가 본 계약을 준수한다는 주장은 별도 PR의 기계 검증으로만 성립한다.

---

## 5. 구현 상태와 Open decisions

### 5.1 현재 상태 (2026-11-20)

| 항목 | 상태 |
|---|---|
| E1 certificate 본문 export | 미구현 — 소비자 워크플로가 manifest만 복사 |
| E2 inventory exact match | 미구현 — source listing 사용 |
| E3 manifest projection | 미구현 — 6필드 |
| E4 certificateSetDigest | 미구현 |
| E5 verdict/record 결속 | 미구현 — `evidence_tier=verified`가 결속 없이 선언됨 |
| kernel observation 보존 | 미구현 — `reexecuteLean`이 `AxiomPrintObservation`을 버리고 `KernelVerdict`만 반환(`src/verification/kernel_reexecution.nim:448-494`) |
| witness wire | 불변(open decision) |

### 5.2 Open decisions (별도 결정 필요)

1. **Export producer 위치**: engine CLI(`ax cert export`/`ax prove --export`) vs 소비자 워크플로 스크립트. 본 계약은 producer를 규정하지 않고 산출물만 규정한다.
2. **Manifest projection vs runtime manifest**: E3는 export projection을 규정한다. runtime `vault_manifest.nim`의 스키마를 v3로 올릴지는 별도 결정 — TrustCommit claim digest와 closure 재봉인을 수반한다.
3. **Axiom observation 보존 경로**: (a) mint 시 `AxiomPrintObservation`을 sidecar record로 저장(signed wire 불변), (b) certificate schema에 추가(continuity contract 개정 필요), (c) export 시 재실행(toolchain 필요·비용). 본 계약은 (a)를 선호하되 결정하지 않는다.
4. **Witness/signed subject certificate export**: admission evidence에 포함할지, 별도 artifact로 분리할지.
5. **Theorem identity 정의**: `firstDeclaredName`은 첫 선언만 관측한다. 다중 theorem/보조 정의의 관측 집합을 어떻게 정의할지.
6. **Legacy artifact 처리**: 기존 run의 `evidence_tier=verified`를 historical로만 인정할지, 재분류할지.
7. **소비자 저장소 적용**: nim-json-rpc 워크플로 수정 PR의 소유권·일정.

---

## 6. 외부 공식 문서 대조 (§0.5)

- GitHub Actions — [Store and share data with workflow artifacts](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/store-and-share-data): artifact는 workflow run 간 데이터 공유 단위이며, **업로드된 파일 집합**이 곧 전달 집합이다 — inventory는 destination 기준이어야 한다.
- GitHub Actions — [Uploading build and test artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data): `upload-artifact`는 지정한 path의 파일을 업로드한다 — source vault listing과 destination 업로드 집합이 다를 수 있음의 근거.
- Lean Reference — [`#print axioms`](https://lean-lang.org/doc/reference/latest/): 선언의 axiom 의존성을 출력한다 — `axiomObservation` 정의의 근거.
- RFC 8785 (JSON Canonicalization Scheme): canonical JSON — 기존 프로젝트의 canonical projection과 동일 계약.
- SLSA v1.0 — [Verifying artifacts](https://slsa.dev/spec/v1.0/verifying-artifacts): "Verify that statement's subject matches the digest of the artifact" — certificate set digest 결속의 근거.

---

## 7. Acceptance criteria (구현 PR)

1. Export producer가 E1–E5를 만족하는 artifact를 생성한다.
2. `vault-certificates.txt`와 실제 export set의 exact match를 검사하는 기계 가드가 있다(inventory mismatch → verdict FAIL).
3. verified entry의 `recomputedStatus`가 기존 엔진 투영과 일치한다(재구현 금지 — 동일 함수 호출).
4. `evidence_tier=verified` + `acceptance_class=proof`가 `certificateSetDigest` 없이 선언될 수 없다.
5. 동일 export set → 동일 `certificateSetDigest`(determinism test).
6. 테스트: (a) cert 본문 누락 → FAIL, (b) inventory 불일치 → FAIL, (c) status 불일치 → FAIL, (d) axiom observation 누락 → FAIL, (e) 정상 export → PASS + digest 결속. legacy v2 artifact는 FAIL이 아니라 "`verified` 주장 불가"로 분류한다.