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

Evidence artifact에서 vault export set은 **`vault/` 하위 디렉터리**로 고정한다. 그 디렉터리는 다음 basename만 포함한다:

1. `vault-manifest.json` — export의 유일한 정본 manifest(schema v3, §2.4). `certificateSetDigest`도 이 파일에 기록된다(§2.5).
2. 64자 소문자 hex + `.json` — vault certificate 본문. basename의 CAS key는 **본문 자신의 신원 필드**다: UAP certificate는 `irHash`(= `sha256(modulePath & functionName & sourceCode)`), subject-continuity certificate는 `subjectId`(`src/verification/subject_continuity_writer.nim:82-121,271`). lookup은 §2.2a를 따른다.
3. `vault-certificates.txt` — §2.3의 파생 inventory.

`vault/`에 위 3종 외 파일이 존재하거나, 위 3종이 아닌 파일이 export set으로 주장되면 `CERT_INVENTORY_MISMATCH`다. release bundle manifest `manifest.json`, `verify-record.json`, `admission-verdict.json`, trajectory/log 등은 `vault/` **밖**(artifact root)에 두며 vault export set이 **아니다**(§2.1a).

- **단일 정본 원칙**: export의 의미를 결정하는 정본은 `vault-manifest.json` 하나다. `vault-certificates.txt`는 그 파생 inventory이고, `verify-record.json`/`admission-verdict.json`은 `certificateSetDigest`를 **참조**할 뿐 재결정하지 않는다. 동일 사실을 두 파일이 서로 다르게 선언하면 fail-closed다.

### 2.1a — Export set 경계와 소비자 파일

- Export set 판정은 `vault/` 디렉터리 안에서만 수행한다. `vault/` 밖의 파일은 verifier의 inventory 검사 대상이 아니다.
- `ax cert export --out <artifact-root>`는 `<artifact-root>/vault/`를 생성한다. adapter는 export 결과를 가공·재조립하지 않고 업로드만 한다.
- 64자 hex 본문 파일은 정규 파일(regular file)이어야 한다. 심볼릭 링크·디렉터리·중복 basename은 export 대상이 아니며, 존재하면 `CERT_INVENTORY_MISMATCH`다.

### 2.2 E1 — Certificate 본문 export

- `vault-manifest.json`의 모든 entry에 대해, 대응하는 vault certificate 파일이 존재하면 **반드시 export**한다.
- `status ∈ {certGreen, certLeanVerified, certDualVerified, certTypeLevelVerified, certSafetyVerified}`(`isVerifiedCertificateStatus`, `src/core/types/certificate_types.nim:108-113`)인 entry는 certificate 본문이 **필수**다.
- certificate 본문은 canonical vault 파일과 **byte-identical**이어야 한다.
- `certZ3Candidate`는 `isVerifiedCertificateStatus`가 아니다 — 검증 주장이 아니며, 본문이 존재하면 export하되 verified로 해석하지 않는다.
- `certRed`/`certPending`/`certStale` 등도 본문이 존재하면 export한다 — 음성 대조에서 어떤 certificate가 반증되었는지 확인하기 위해서다.

### 2.2a E1a — Identity 기반 lookup (manifest `irHash` ≠ file CAS key)

- **사실(코드 근거)**: staging vault의 `vault-manifest.json` entry `irHash`는 IR pipeline digest(`IrPipelineResult.irDigest`, `src/verification/batch_uap/ir_pipeline_runner.nim:1956` → `src/cli/axiom_engine.nim:752-776`)이고, UAP certificate 파일의 basename은 `sha256(modulePath & functionName & sourceCode)`(`src/verification/batch_uap/loop_driver.nim:1273`; `src/verification/cert_writer.nim:663`)다. **두 값은 서로 다른 해시 공간이며, manifest `irHash`로 본문 파일명을 유도해서는 안 된다.**
- **lookup 규칙(규범적)**: exporter는 각 manifest entry를 `(modulePath, functionName)` **정확 일치**로 본문에 결속한다:
  1. source vault의 body JSON을 읽어 `modulePath`·`functionName`이 entry와 정확히 같은 후보를 수집한다. body에 해당 필드가 없으면 후보가 아니다.
  2. 후보가 정확히 1개면 `certificateFile`에 그 basename을 기록한다.
  3. 후보가 0개면 `certificateFile: null` — verified entry면 `CERT_BODY_MISSING`.
  4. 후보가 2개 이상이면 `CERT_INVENTORY_MISMATCH`(모호한 신원 — 추측 금지).
- **CAS self-consistency**: export되는 본문의 CAS key(`irHash` 또는 subject-continuity의 `subjectId`)는 basename에서 `.json`을 뗀 값과 일치해야 한다. 불일치 → `CERT_INVENTORY_MISMATCH`.
- **identity binding**: export된 본문의 `(modulePath, functionName)`은 entry와 일치해야 한다. 불일치 → `CERT_INVENTORY_MISMATCH`.
- `certificateFile`은 export projection의 명시적 필드다 — verifier는 파일명에서 신원을 역추론하지 않고 이 필드로 본문을 찾는다.
- runtime manifest의 `irHash` 필드 자체를 고치는 것은 이 계약의 범위가 아니다(§5.2 open decision). exporter는 위 lookup으로 결속하고, `certificateFile`에 실제 basename을 기록한다.

### 2.3 E2 — Inventory exact match

- `vault-certificates.txt`는 export set의 모든 basename을 **정렬된** 1줄 1파일로 나열한다.
- `vault-certificates.txt`의 행 집합 == export set의 basename 집합(exact match, 중복 없음).
- inventory는 **destination에 복사된 뒤** 생성한다 — source vault listing을 복사하지 않는다.
- `vault-manifest.json`도 export set의 멤버이므로 inventory에 포함된다. release `manifest.json`은 포함되지 않는다.
- 실패 시 `CERT_INVENTORY_MISMATCH`(§3).

### 2.4 E3 — Manifest export projection

`vault-manifest.json`은 runtime manifest의 **export projection**이다. top-level shape은 다음과 같다(schema `axiom.admission.vault-manifest.v3`):

```json
{
  "schema": "axiom.admission.vault-manifest.v3",
  "version": 3,
  "certificateSetDigest": "<64 hex>",
  "entries": [ ... ]
}
```

기존 6필드는 보존하고, 각 entry에 다음 필드를 추가한다:

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

Export producer는 다음 canonical JSON의 SHA-256을 `certificateSetDigest`로 기록한다. 이 digest가 기록되는 정본 위치는 `vault-manifest.json`의 top-level 필드다 — 다른 파일은 이 값을 참조만 한다.

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

계산 규칙(전부 규범적):

1. **해시 대상**: certificate 본문은 파싱 후 재직렬화하지 않고 **원본 bytes 그대로** SHA-256 한다(`sha256Hex(rawBytes)`).
2. **canonicalization**: digest 입력은 위 객체를 `canonicalJsonString`(`src/verification/canonical_json.nim`)으로 직렬화한 bytes다. 키는 canonical 정렬(RFC 8785), 추가 공백·trailing newline 없음.
3. **정렬**: `certificates`는 `file` basename의 byte 순서 오름차순으로 정렬한다. 정렬은 실행 순서·locale·파일시스템 순회 순서와 무관해야 한다.
4. **파일명**: `file`은 64자 소문자 hex + `.json`이며, **본문 자신의 CAS key**(UAP: body `irHash`, subject-continuity: body `subjectId`)와 일치해야 한다. manifest entry의 `irHash`와의 일치는 요구하지 않는다 — 두 값은 서로 다른 해시 공간이다(§2.2a). 중복 `file` 또는 규약 위반 basename은 `CERT_INVENTORY_MISMATCH`다.
5. **digest 입력 제외**: `certificateSetDigest` 자기 자신(자기 참조 금지), `vault-manifest.json`, `vault-certificates.txt`, `verify-record.json`, `admission-verdict.json`, GitHub artifact digest/attestation, 생성 시각·실행 ID 등 비결정 메타데이터. 이 필드들은 digest 대상이 아니다.
6. **포함**: `sha256`, `recomputedStatus`, `theoremIdentity`, `axiomObservation`은 포함한다 — status/관측이 바뀌면 digest가 바뀐다.
7. **추가·누락**: manifest가 참조하는 본문이 없거나(`CERT_BODY_MISSING`), 참조되지 않는 본문이 `vault/`에 있거나(`CERT_INVENTORY_MISMATCH`), symlink·비정규 파일이면 digest 검증 이전에 fail-closed다.
8. **결정론**: 동일 bytes 집합 → OS·실행 순서와 무관하게 동일 digest. exporter는 동일 입력 2회 실행에서 동일 digest를 내야 한다(M5, exporter determinism).

> **구분**: 본 digest는 **의미 결속**(어떤 인증서가 어떤 status·관측으로 한 집합을 구성하는가)이다. GitHub artifact digest는 **바이트 전달**의 SHA-256이고, attestation은 둘을 predicate로 연결한다(§2.7). 의미 digest와 바이트 digest를 같은 값으로 취급하지 않는다.

### 2.6 E5 — Verdict/record 결속

- `vault-manifest.json`(정본)이 `certificateSetDigest`를 기록한다(§2.5).
- `verify-record.json`은 `certificate_set_digest`와 `certificate_bodies_present`(bool)를 기록한다 — 정본 값을 **참조**하며 재계산하지 않는다.
- `admission-verdict.json`은 `certificate_set_digest`와 `guards.CERTIFICATE_EVIDENCE`, `guards.CERTIFICATE_INTEGRITY`(`PASS|FAIL`)를 기록한다.
- `evidence_tier = "verified"`는 다음 전부가 성립할 때만 허용된다:
  1. 모든 verified-status entry에 certificate 본문이 존재한다.
  2. inventory exact match(E2).
  3. 각 verified entry의 `recomputedStatus == status`.
  4. 각 Lean-dependent verified entry의 `axiomObservation.status == "observed"`.
  5. `certificate_set_digest`가 정본과 verdict/record에서 동일하다.
  6. `CERTIFICATE_INTEGRITY`가 PASS다: producer job에서 engine closure(`verifyCertificateClosure` — identityDigest 재계산, journal binding, replay input/equality, attestation consistency)가 verified entry 전체에 대해 PASS로 기록되고, 그 결과가 `certificate_set_digest`/artifact attestation에 결속되어 있다. 소비자는 closure를 재실행하지 않으며(주권 없음: journal 부재), 기록된 PASS의 **결속**만 검사한다 — 본 guard는 기존 검증을 대체하지 않는다.
- 하나라도 불성립 → `evidence_tier`는 `verified`가 아니다(fail-closed). 기존 verdict 어휘를 재사용하며 새 enum을 만들지 않는다.
- **주의(비주장)**: `certificate_attestation`의 Ed25519 키는 공개 상수 seed에서 유도된다(`AttestationDomainSeed`) — 서명은 consistency anchor이지 비밀 기반 authenticity가 아니다. authenticity의 authority는 pinned workflow + GitHub artifact attestation + release attestation이며, certificate 서명 검증을 그 대체물로 주장하지 않는다.

### 2.6a 집계 규칙 (admission VERIFIED)

- 집계 단위는 **admission이 검증 대상으로 선언한 명제 집합**이다. verified status(`isVerifiedCertificateStatus`)를 주장하는 entry만 집계 대상이다.
- `certRed`/`certZ3Candidate`/`certPending`/`certStale` 등 verified가 아닌 entry는 "증거가 필요한 명제"가 아니다 — 이들이 있다는 사실만으로 `evidence_tier`가 FAIL이 되지는 않는다(단, 그 본문이 있으면 export·digest 대상이다).
- 선언된 verified 명제 중 **하나라도** 요건을 잃으면 전체 admission은 `verified`를 주장할 수 없다(전칭). 부분 성공을 verified로 승격하지 않는다.
- 두 leg(A/B)가 서로 다른 certificate 집합을 검증했다면 digest 일치 요구는 성립하지 않는다 — leg별 digest는 각 leg의 집합에 대해 계산되고, 일치 요구는 "두 leg가 같은 입력·같은 명제 집합을 검증했다"는 전제 위에서만 적용된다(§2.8a).

### 2.7 — Artifact 전달 계층 (GitHub 위임)과 그 경계

- **바이트 무결성·출처**: `upload-artifact`의 `artifact-digest`(업로드된 artifact archive의 SHA-256)와 GitHub artifact API의 `digest`는 전달 계층의 권위다. Axiom은 이를 재구현하지 않는다.
- **출처 증명**: `actions/attest@v4` custom predicate(`predicate-type: https://github.com/Archright/Axiom/attestation/certificate-set/v1`)로 subject digest(artifact archive)와 predicate(`certificateSetDigest`, schema, vault inventory digest)를 결속한다. 요구 권한: `id-token: write`, `attestations: write`, `artifact-metadata: write`(공식 README Usage). **이중 cap**: reusable workflow의 called job도 자기 `permissions:`에 세 권한을 선언해야 하고(선언하지 않으면 caller가 더 줘도 cap), caller job도 동일 권한을 부여해야 한다. `contents: read`는 유지한다.
- **acceptance 분리**: (i) 소비된 CLI 배포물의 정당성(기존 release attestation)과 (ii) 실제 admission evidence artifact의 생성 출처(이 attestation)는 별개다. (ii)는 다운로드한 **archive bytes**에 대해 검증한다 — 압축 해제 디렉터리와 archive digest를 비교하지 않는다.
- **비대체**: attestation은 의미 검증이 아니다. 올바른 서명이 붙은 악성 certificate body도 의미 검증(§2.5/§2.6)에서는 FAIL이다. provenance는 `guards.ARTIFACT_PROVENANCE ∈ {PASS, NOT_CLAIMED}`로 별도 기록하며, 의미 tier(`CERTIFICATE_EVIDENCE`)와 결합하지 않는다. `acceptance_class=proof`는 provenance PASS를 요구하고, 불가 시 NOT_CLAIMED로 강등해 문서화한다(조용한 통과 금지).

### 2.8 — CLI 계약 (producer/verifier)

- `ax cert export --vault <dir> --out <artifact-root> [--json]`
  - `--vault` 기본값: `$AXIOM_STATE_DIR/build/certificates`. 출력: `<artifact-root>/vault/`.
  - `vault-manifest.json`(schema v3 + `certificateSetDigest`), byte-identical 본문, `vault-certificates.txt`를 쓴다.
  - exit: 0 성공, 1 export 위반(E1–E5), 2 usage/IO. `<artifact-root>/vault/`가 이미 존재하고 비어있지 않으면 exit 1(잔여 파일 혼입 금지 — 결정론).
  - `--json` stdout: `{"schema":"axiom.cert-export.v1","verdict":"PASS","certificateSetDigest":"<64hex>","certificateCount":N,"diagnostics":[]}`.
- `ax cert verify-export --bundle <artifact-root>/vault [--closure --project <subject>] [--json]`
  - 본문을 다시 읽어 tier/status를 재계산하고 §3.1 순서로 검증한다. export projection 값을 신뢰하지 않는다.
  - `--closure`: producer job 전용. journal이 있는 환경에서 verified entry 전체에 `verifyCertificateClosure`를 실행하고 그 결과를 `CERTIFICATE_INTEGRITY`로 기록한다(§3.1-5). journal이 없거나 closure 입력이 불완전하면 exit 2 — PASS로 강등하지 않는다. 소비자는 이 모드를 실행하지 않고 기록된 결속만 검사한다(§2.6-6).
  - exit: 0 PASS, 1 FAIL, 2 usage/IO/closure 불가.
  - `--json` stdout: `{"schema":"axiom.cert-verify-export.v1","verdict":"PASS|FAIL","reasonCode":null|"<code>","codes":[],"certificateSetDigest":"<64hex>","certificateBodiesPresent":true|false,"entryCount":N,"closure":"executed"|"not-claimed"}`.
  - producer adapter는 실행 결과를 `<artifact-root>/cert-export-verification.json`(schema `axiom.cert-export-verification.v1`, `--json` 출력 + `verdict`/`reasonCode`)에 기록한다. 이 파일은 **비정본 실행 결과**이며, 소비자는 자신이 직접 재실행한 결과를 사용한다(§2.1 단일 정본).
  - 두 명령은 vault의 canonical 파일을 수정하지 않는다(read-only).
  - tier/status 판정은 기존 엔진 함수(`certificateEvidenceFromJson → tierFromEvidence → tierToCertStatus`)를 재사용한다 — 소비자 측 재구현 금지.

### 2.8a — Leg 결정론 acceptance (측정 전 주장 금지)

- **정의**: 동일 subject·동일 propositions로 독립 `ax prove` 실행 2회 → 각각 export → 두 bundle의 `certificateSetDigest` 비교.
- 이는 exporter determinism(M5: 동일 export set → 동일 digest)과 **다른** 주장인 producer determinism이다. certificate body는 byte-identical 복사이므로, 두 실행이 다른 body bytes를 만들면 digest는 달라진다.
- **proxy 증거(2026-11-18 run `44253688052`)**: A/B는 서로 다른 runner에서 완전 독립 실행되며(`ax-verify.yml:150`, `:475-476`), 공유 state가 없다. 그럼에도 `verify-record.json`은 바이트 동일, vault entry 5-tuple set은 17개 전부 동일, 차이는 manifest의 `lastVerifiedAt`(digest 입력에서 제외)뿐이었다. certificate body는 아직 export되지 않아 **직접 측정된 적은 없다** — G0가 최초 측정이다.
- G0 실측이 성공하면 "leg 간 digest 일치"를 acceptance로 주장할 수 있다.
- 실측이 실패하면 다음 중 하나를 **명시적으로 결정**한 뒤 계약을 개정한다: (a) body의 비결정 필드를 식별해 digest 입력을 결정론 투영으로 개정, (b) leg digest 일치 요구를 철회하고 leg별 self-consistency + leg 간 semantic projection 일치로 acceptance를 재정의. **측정 전에는 어느 쪽도 주장하지 않는다.**

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
| `CERT_SET_DIGEST_ABSENT` | 정본 manifest 또는 verdict/record에 `certificateSetDigest` 없음 | FAIL |
| `CERT_SET_DIGEST_MISMATCH` | 재계산 `certificateSetDigest` ≠ manifest/verdict/record 기록값 | FAIL |
| `CERT_INTEGRITY_FAILED` | producer job의 engine closure(identity/journal/replay/attestation consistency)가 verified entry에서 FAIL 또는 결과 미결속 | `CERTIFICATE_INTEGRITY=FAIL` |

### 3.1 검증 순서와 reasonCode 우선순위 (규범적)

Negative control이 "무언가 실패했다"가 아니라 **의도한 안전장치가 작동했다**는 증거가 되려면, 실패 코드가 결정론적이어야 한다. verifier는 다음 순서로 검사하고, **첫 실패 코드만** `reasonCode`로 기록하되 아래 우선순위를 따른다(낮은 번호가 우선):

| 우선 | 검사 | code |
|---|---|---|
| 1 | export set 파일 집합 == manifest 참조 집합(누락·추가·중복·비정규 파일) | `CERT_INVENTORY_MISMATCH` |
| 2 | verified-status entry의 본문 존재 여부 | `CERT_BODY_MISSING` |
| 3 | 본문 bytes SHA-256 == `certificateSha256` | `CERT_DIGEST_MISMATCH` |
| 4 | `tierToCertStatus(tierFromEvidence(certificateEvidenceFromJson(body)))` == `recomputedStatus` == manifest `status` | `CERT_STATUS_MISMATCH` |
| 5 | verified entry의 engine closure 결과(`CERTIFICATE_INTEGRITY`)가 PASS로 결속 | `CERT_INTEGRITY_FAILED` |
| 6 | Lean-dependent verified entry `axiomObservation.status == "observed"` | `AXIOM_OBSERVATION_MISSING` |
| 7 | `certificateSetDigest` 존재 및 재계산 일치 | `CERT_SET_DIGEST_ABSENT` / `CERT_SET_DIGEST_MISMATCH` |

- **선행 조건**: 1–3은 서로 다른 계층이다. 본문을 삭제한 negative control은 "inventory를 계약에 맞게 갱신"한 상태에서 수행해야 2번(`CERT_BODY_MISSING`)이 관측된다. inventory를 갱신하지 않으면 1번이 먼저 발화한다 — 이는 결함이 아니라 우선순위 계약이다.
- **digest 계층 분리**: axiom observation 제거 negative control은 관측 필드를 제거한 뒤 **manifest의 하위 digest(entry `sha256`, `certificateSetDigest`)를 재계산**해야 6번이 관측된다. 그렇게 하지 않으면 3/7번이 먼저 발화한다.
- **closure 계층**: `CERT_INTEGRITY_FAILED`는 producer job에서 `verify-export --closure`(journal 존재)가 수행한 결과다. 소비자/제3자는 journal이 없으므로 closure를 재실행하지 않고, 결과의 결속만 검사한다(§2.6-6).
- verifier는 모든 실패 코드를 `codes[]`에 수집할 수 있으나, `reasonCode`(단일)는 위 우선순위의 첫 항목이다. `CERTIFICATE_EVIDENCE=FAIL`은 코드 목록 유무와 무관하게 성립한다.

- FAIL은 `evidence_tier=verified`를 금지한다. `acceptance_class=proof`도 함께 금지한다 — proof 등급은 certificate 본문 결속을 전제한다.
- legacy export(v2 manifest, 본문 없음)는 **소급 재분류하지 않는다**: 기존 artifact는 historical record이며, 새 계약의 `verified` 주장 근거가 될 수 없다. 새 run부터 적용한다.
- `ax cert verify --kernel`의 기존 판정(구조·identity·journal 결속·replay·attestation consistency)은 변경하지 않는다. 본 계약은 export 결속만 추가한다.

---

## 4. 검증 가능한 주장의 경계 (Non-claims)

이 계약이 **하는 주장**:

- verified 상태를 주장하는 entry에 대해 certificate 본문이 artifact 안에 존재하고, 그 digest·status projection·theorem identity·axiom observation 상태가 manifest와 verdict에 결속된다.
- 외부 검증자는 export된 `leanSource`/`smtlib2`와 pinned toolchain identity를 사용해 `#print axioms`/Z3를 **독립 재실행**할 수 있다.

이 계약이 **하지 않는 주장**:

- **certificate 서명은 authenticity 권위가 아니다**: `certificate_attestation`의 Ed25519 키는 공개 상수 seed(`AttestationDomainSeed`)에서 유도되며 코드 주석도 "consistency anchor, not a secret-based authenticator"라고 명시한다(`src/infrastructure/certificate_attestation.nim:184-196`). 서명은 payload 변조 검출용이지 발행자 신원 증명이 아니다. authenticity는 pinned workflow + GitHub artifact/release attestation이 담당한다.
- export만으로 certificate identity/journal/replay/toolchain identity가 유효함을 증명하지 않는다 — engine closure(`verifyCertificateClosure`)의 판정이 필요하고, 그것은 journal이 있는 producer job에서만 실행된다. 소비자는 그 결과의 결속만 검사한다.
- `ax cert verify-export`는 기존 `ax cert verify`/`cert_integrity_gate`를 **대체하지 않는다**. 소비자 guard는 `CERTIFICATE_EVIDENCE`(E1–E5) + `CERTIFICATE_INTEGRITY`(closure 결과 결속)의 병렬 계층이다.
- verifier는 exporter와 **동일 엔진 함수·동일 릴리즈**를 재사용한다 — 독립 재구현 검증이 아니다. 보장하는 것은 "생산자 메모리 상태를 신뢰하지 않고 공개 본문에서 tier를 재계산하며, 제3자가 동일 pinned 바이너리로 재실행·반증할 수 있다"는 local replay-bound 범위다.
- 소비자가 verifier의 `PASS` 문자열만 읽고 파일·subject·engine·artifact digest에 결속하지 않으면 극장이다(§0.9). PR C2의 소비자는 attested `ax` 릴리즈 번들을 내려받아 `verify-export`를 직접 재실행해야 한다.
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

### 5.2 결정과 Open decisions

1. **Export producer — 결정됨 (2026-11-20)**: producer는 **engine CLI `ax cert export`**다(소비자 워크플로 스크립트가 아니다). 근거: tier/status 판정 권위가 엔진에 있고, adapter는 전달만 한다(M3, §1.3). `ax prove --export`는 채택하지 않는다(prove와 export의 책임 분리).
2. **Manifest projection vs runtime manifest**: E3는 export projection을 규정한다. runtime `vault_manifest.nim`의 스키마를 v3로 올리는 것은 별도 결정 — TrustCommit claim digest와 closure 재봉인을 수반한다. export projection은 runtime manifest를 **읽기만** 한다.
3. **Axiom observation 보존 경로 — 결정 전 실측 필요**: (a) mint 시 `AxiomPrintObservation`을 sidecar record로 저장(signed wire 불변), (b) certificate schema에 추가(continuity contract 개정), (c) export 시 재실행. **중요**: sidecar는 "관측이 생성되었으나 중간 함수가 버린 경우"만 복구한다. 관측 생성 경로 자체가 없는 실행(다수 `evidence: none` branch, parallel lane)은 sidecar로 해결할 수 없다 — G0에서 `leanSource`/`kernel`/`solverMeta` 필드로 두 상황을 판별하고, 미생성 경로는 observation 수집 구현 또는 VERIFIED 거부로 분기한다. 없는 데이터를 전달 계층에서 복구하지 않는다.
4. **Witness/signed subject certificate export**: admission evidence에 포함할지, 별도 artifact로 분리할지.
5. **Theorem identity 정의**: `firstDeclaredName`은 첫 선언만 관측한다. 다중 theorem/보조 정의의 관측 집합을 어떻게 정의할지.
6. **Legacy artifact 처리**: 기존 run의 `evidence_tier=verified`를 historical로만 인정하고 새 run부터 적용한다(소급 재분류하지 않는다).
7. **소비자 저장소 적용**: nim-json-rpc 워크플로 수정 PR(PR C2)의 일정. negative-control workflow는 **artifact 생산 저장소(nim-json-rpc)**에 둔다 — axiom-cli는 reusable adapter/verifier만 제공한다.

---

## 6. 외부 공식 문서 대조 (§0.5)

- GitHub Actions — [Store and share data with workflow artifacts](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/store-and-share-data): artifact는 workflow run 간 데이터 공유 단위이며, **업로드된 파일 집합**이 곧 전달 집합이다 — inventory는 destination 기준이어야 한다.
- GitHub Actions — [Uploading build and test artifacts](https://docs.github.com/en/actions/tutorials/store-and-share-data): `upload-artifact`는 지정한 path의 파일을 업로드한다 — source vault listing과 destination 업로드 집합이 다를 수 있음의 근거.
- GitHub Actions — [`actions/upload-artifact` README](https://github.com/actions/upload-artifact#outputs): `artifact-digest` = 업로드된 artifact archive의 SHA-256 — 바이트 무결성 권위의 근거. (현재 major v7.)
- GitHub Actions — [`actions/attest` README](https://github.com/actions/attest): custom predicate(`predicate-type`/`predicate-path`), `bundle-path` output, 그리고 Usage가 요구하는 권한 `id-token: write` + `attestations: write` + `artifact-metadata: write` — §2.7 위임의 근거.
- GitHub Docs — [Use artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations): attestation은 subject digest와 predicate를 Sigstore bundle로 결속한다 — 의미 digest와 바이트 digest를 연결하는 계층의 근거.
- Lean Reference — [`#print axioms`](https://lean-lang.org/doc/reference/latest/): 선언의 axiom 의존성을 출력한다 — `axiomObservation` 정의의 근거.
- RFC 8785 (JSON Canonicalization Scheme): canonical JSON — 기존 프로젝트의 canonical projection과 동일 계약.
- SLSA v1.0 — [Verifying artifacts](https://slsa.dev/spec/v1.0/verifying-artifacts): "Verify that statement's subject matches the digest of the artifact" — certificate set digest 결속의 근거.

---

## 7. Acceptance criteria (구현 PR)

1. Export producer가 E1–E5를 만족하는 artifact를 생성한다.
2. `vault-certificates.txt`와 실제 export set의 exact match를 검사하는 기계 가드가 있다(inventory mismatch → verdict FAIL).
3. verified entry의 `recomputedStatus`가 기존 엔진 투영과 일치한다(재구현 금지 — 동일 함수 호출).
4. `evidence_tier=verified` + `acceptance_class=proof`가 `certificateSetDigest` 없이 선언될 수 없다.
5. 동일 export set → 동일 `certificateSetDigest`(exporter determinism test).
6. **Targeted negative controls**: 각 조작은 **검증하려는 속성 하나만** 깨뜨리고 나머지 무결성 계층은 일관되게 유지한다. 각 테스트는 exit 1 + **정확한 reasonCode**(§3.1 우선순위)를 단언한다:
   - 본문 누락: manifest 참조는 유지하고 파일만 제거 → `CERT_BODY_MISSING`.
   - inventory 불일치: manifest에 없는 파일 추가(또는 목록 변조) → `CERT_INVENTORY_MISMATCH`.
   - status 변조: body의 status만 변경하고 entry `sha256`·`certificateSetDigest` 재계산 → `CERT_STATUS_MISMATCH`.
   - digest 변조: `certificateSetDigest`만 변경 → `CERT_SET_DIGEST_MISMATCH`.
   - axiom 관측 누락: body에서 관측 필드 제거 후 의존 digest 재계산 → `AXIOM_OBSERVATION_MISSING`.
   - closure 실패: journal/identity 결속을 깬 fixture → `CERT_INTEGRITY_FAILED`(closure 모드).
   - lookup 모호성: 같은 `(modulePath, functionName)`의 본문 2개 → `CERT_INVENTORY_MISMATCH`; identity 불일치 본문 → `CERT_INVENTORY_MISMATCH`; CAS self-consistency 위반 basename → `CERT_INVENTORY_MISMATCH`.
   - **lookup 비회귀(정상)**: manifest entry `irHash`와 본문 basename이 달라도 `(modulePath, functionName)`이 일치하면 PASS (§2.2a).
7. **정상 대조**: 정상 export → `verify-export` exit 0, 모든 digest/결속 PASS, 동일 fixture 2회 → 동일 `certificateSetDigest`.
8. legacy v2 artifact(본문 없음)는 FAIL이 아니라 "`verified` 주장 불가"로 분류한다.
9. **Artifact 전달 계층**: 업로드 archive의 SHA-256 == artifact API digest == attestation subject digest, predicate의 `certificateSetDigest` == 정본 manifest 값. 검증은 archive bytes 대상이며 압축 해제 디렉터리와 비교하지 않는다.
10. **관측 상태 판별**: `not-observed`(관측 유실)와 `not-applicable`(Z3-only)를 구분하고, 관측 생성 경로가 없는 verified entry는 `not-observed`로 기록되어 FAIL한다(fail-closed).
11. **leg 결정론**: §2.8a의 실측(독립 prove 2회 → export digest 비교) 결과가 PASS일 때만 leg digest 일치를 주장한다. 실패 시 계약 개정 없이 완료를 주장하지 않는다.