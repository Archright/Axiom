# Certificate v3 Provenance Contract (Ratified)

> **상태**: Ratified — Phase 1 R4 contract ratification (2026-08-18).
> 이 문서는 Axiom v3 certificate의 정체성·출처(provenance)·정체성 다이제스트 계산 규칙을 정의한다.
> certificate JSON 스키마는 `schemaVersion: "axiom.certificate.v3"`로 고정되며, 스키마 변경은 반드시 schemaVersion bump를 동반한다.

---

## §1. Certificate v3 JSON Schema

```jsonc
{
  "schemaVersion": "axiom.certificate.v3",
  "claim": { "type": "verification", "status": "<tierToStatusString>", "modulePath": "…", "functionName": "…" },
  "subjectLanguage": "nim",  // deferred — 미구현, schemaVersion bump 세대에서 확정 (§2 필드 표, §7)
  "attestation": { "authority": "axiom", "policyVersion": "axiom.certificate.v3", "claimDigest": "sha256:…", "journalRef": "<trustCommitId>" },
  "inputHash": "sha256:…",
  "toolchainIdentity": { "axiomVersion": "<ax --version 실측>", "nim": "2.2.10", "z3": "4.13.3", "lean": "4.33.0" },
  "solverInvocation": { "engine": "z3|lean|none", "version": "…", "strategy": "…", "mode": "…" },
  "solverInputDigest": "sha256:…",
  "solverResultDigest": "sha256:…",
  "proofDigest": null,
  "identityDigest": "sha256:…",
  "provenance": { "journalCommitId": "<tcId>", "certificateDigest": "sha256:…" }
}
```

---

## §2. Field Table

| 필드 | 필수 | 파생/소스 | 예시 | identityDigest 포함 |
|---|---|---|---|---|
| `schemaVersion` | Y | 고정 문자열 `"axiom.certificate.v3"` | `"axiom.certificate.v3"` | Y |
| `claim` | Y | 검증 결과의 타입·상태·대상 | `{"type":"verification","status":"certGreen","modulePath":"…","functionName":"…"}` | Y |
| `subjectLanguage` | deferred | subject 언어 선언: `nim` \| `rust` (Rust는 `docs/spec/rust_certified_subset.md` 선언 subset 한정) — **deferred**: 코드 미구현·identity 키(`canonicalV3FieldKeys` 13개) 미편입 상태의 선기재를 정정; schemaVersion bump 세대에서 확정 (§7) | `"nim"` | N (미편입) |
| `attestation` | Y | authority, policyVersion, claimDigest, journalRef | `{"authority":"axiom","policyVersion":"axiom.certificate.v3","claimDigest":"sha256:…","journalRef":"<trustCommitId>"}` | Y |
| `inputHash` | Y | derivation rule §3(a) 에 따라 산출 | `"sha256:ab12…"` | Y |
| `toolchainIdentity` | Y | 실측 런타임 값 (§3(c) 참조) | `{"axiomVersion":"v0.6.0","nim":"2.2.10","z3":"4.13.3","lean":"4.33.0"}` | Y |
| `solverInvocation` | Y | solver 엔진·버전·전략·모드 | `{"engine":"z3","version":"4.13.3","strategy":"default","mode":"sat"}` | Y |
| `solverInputDigest` | Y | solver 입력의 SHA-256 (§3(b) 참조) | `"sha256:cd34…"` | Y |
| `solverResultDigest` | Y | solver 결과의 SHA-256 (§3(b) 참조) | `"sha256:ef56…"` | Y |
| `proofDigest` | O | 실증 artifact 파이프라인이 존재하지 않음 — null 유지 | `null` | Y (null 포함) |
| `identityDigest` | Y (구조적) | identityFields를 `"\n"`으로 결합 후 `computeCertificateIdentity` | `"sha256:…"` | — (자기 자신) |
| `provenance` | Y | journalCommitId + certificateDigest | `{"journalCommitId":"<tcId>","certificateDigest":"sha256:…"}` | Y |

**필수 필드**: `schemaVersion`, `claim`, `attestation`, `inputHash`, `toolchainIdentity`, `solverInvocation`, `solverInputDigest`, `solverResultDigest`, `identityDigest` (구조적), `provenance` — 총 10개. (`subjectLanguage`는 deferred — 위 필드 표 및 §7.)

**`subjectLanguage` 신설 노트 (Rust subject 확장)**: 값은 `nim` \| `rust` 둘 중 하나다. **현재 상태는 deferred다** — 구현·identity 편입 없이 본 문서(draft commit f26b7482e)가 required로 선기재한 것을 정정한 것으로, 확정은 schemaVersion bump 세대에서 이뤄진다(§7). 스키마 변경이므로 **반드시 schemaVersion bump를 동반한다**(본 문서 헤더 규칙) — bump 세대에서 identity 입력(`canonicalV3FieldKeys`)으로의 편입도 함께 확정한다. "conditional guarantee" 같은 신규 보장 필드는 이 변경으로 도입하지 않는다(§7 참조).

**필수 필드는 null/빈 값이 될 수 없다.** `provenance`의 소스(`journalCommitId`)가 누락되면 해당 certificate는 정식(canonical)으로 승격되지 않으며, 아카이브된다.

---

## §3. Derivation Rules

### (a) `inputHash` 계산

```
inputHash := "sha256:" & sha256Hex(join(["modulePath", modulePath, "functionName", functionName, "sourceHash", sourceHash, "irHash", irHash], "\x1f"))
```

- 필드 순서는 고정됨 (변경 불가; 변경 시 schemaVersion bump 필요).
- 구분자 `\x1f` (Unit Separator, ASCII 31) — 경로/16진수에 절대 등장하지 않음.
- UTF-8 바이트 기준, 소문자 16진수, `"sha256:"` 접두사.
- 규칙 변경은 반드시 schemaVersion bump를 동반한다.

### (b) Solver Input/Result Digest

- **z3 경로**: `solverInputDigest = sha256(smtlib2)`, `solverResultDigest = sha256(z3 solver stdout)` (`.z3out` 기준).
- **lean 경로**: `solverInputDigest = sha256(leanProposition)`, `solverResultDigest = sha256(lean result)`.
- `proofDigest = null` — solver result는 proof가 아니다. 증명 artifact 파이프라인은 현재 존재하지 않는다 (검증된 저장소 사실).

### (c) `identityDigest` 계산

```
identityDigest = identityFields.join("\n") → computeCertificateIdentity
```

- **identity projection 입력 필드셋은 `canonicalV3FieldKeys` 13개** (단일 SSOT, `src/verification/certificate_identity.nim:32-36`):
  ```
  [schemaVersion, modulePath, functionName, sourceHash, irHash,
   leanProposition, solverStatus, status, winningStrategy,
   inputHash, solverInputDigest, solverResultDigest, evidenceId]
  ```
- 이 13개는 certificate JSON의 최상위 필드(`schemaVersion`, `inputHash`, `solverInputDigest`, `solverResultDigest`, `evidenceId`; `status`는 `claim.status` 경유)와 내부 필드(`claim`의 `modulePath`·`functionName`·`sourceHash`·`irHash`·`leanProposition`, `solverInvocation`의 `solverStatus`·`status`·`winningStrategy`)를 플랫하게 전개한 것이다. (문서 §2의 "필수 필드 10개"는 최상위 구조 필드 목록이고, identity 입력은 이 13개 플랫 projection이다 — 서로 다른 두 관점.)
- 감사/일시적 필드(`issuedAt`, `identityDigest` 자신)는 identity digest 입력에서 제외된다.
- 단일 구현 재사용: `compV3Identity` → `computeCertificateIdentity` (`src/verification/certificate_identity.nim:38-47`). Writer(추가), verifier(`v3IdentityFromJson`), promotion 모두 이 하나를 통과한다. 중복 정의 금지(AGENTS.md §1).

### (d) `toolchainIdentity` 소스

- **소스 of truth = 실제 런타임 실측값**.
- `axiomVersion`은 반드시 `ax --version` 출력과 일치해야 한다 (현재 v0.6.0; 정본 상수: `src/core/release/version_derive.nim`의 `axiomVersion` — `axiom.nimble`의 `version`에서 compile-time 파생. `src/cli/version.nim`은 이 상수를 재노출만 한다).
- `nim`, `z3`, `lean` 버전도 실측값으로 기록한다.

---

## §4. R4 Corpus Scope

R4는 **정식 assurance corpus**만을 평가 대상으로 한다:

- **정식 corpus** = 평가 시점 기준 `src/verification/certificates/` 아래의 **모든 v3 certificate**.
- 증거는 반드시 `corpusScope {path, count, entries}`를 기록해야 한다.
- **레거시/역사적 certificate**(아카이브됨, provenance 재구성 불가)는 scope 밖이며, R4 평가를 방해해서는 안 된다.

---

## §5. Evidence Identity: Subject ≠ Collector

- evidence의 `repoIdentity.head` = **주체(subject) 커밋 H1** (측정 상태).
- collector 커밋 H2는 증거를 저장하는 커밋이다.
- 평가자는 명시적 주체 정체성(`--repo-head H1 --tree-digest <tree(H1)>`)으로 호출된다.
- 평가자 스키마는 변경되지 않는다.

---

## §6. Canonical Serialization Policy (Ratified 2026-08-20)

Certificate artifact의 **바이트 표현은 정확히 하나**여야 한다 — semantic identity가 같으면 byte identity도 같아야 제품의 "같은 입력 → 같은 인증서 정체성"이 성립한다.

### (a) 단일 canonical serializer

- Certificate를 JSON 바이트로 만드는 코드는 저장소에 **단 하나**만 존재한다:
  - `canonicalCertificateBytes` / `canonicalCertificateString` (`src/verification/canonical_certificate_payload.nim`)
  - 구현: `src/verification/canonical_json.nim` (RFC 8785 JCS)
- certificate generator(`cert_writer`), promotion(`cert_promotion`), idempotency 비교, golden/reproducibility — 전부 이 하나를 통과해야 한다.
- 저장소 어디에도 `json.pretty()`/`%*` 직렬화를 certificate(또는 promotion) 바이트로 주입하는 경로가 있어서는 안 된다.

### (b) JCS 계약 (RFC 8785)

- UTF-8, LF, no BOM, no trailing whitespace, **no trailing newline** (파일 마지막 바이트는 `}` 등 본문).
- object key는 UTF-16 code unit 기준 정렬, array 순서 보존.
- 숫자는 ES6 정규화(`4.50` → `4.5`, 지수부 정규화 등).
- string 이스케이프는 RFC 8785 규칙.
- key/값의 지시적(insignificant) 공백 제거.

### (c) byte identity = semantic identity (C3)

```
canonicalBytes(payload1) == canonicalBytes(payload2)  ⟺  payload1 ≡ payload2 (semantic)
```

- 같은 payload → 반드시 같은 byte (결정론).
- 서로 다른 payload → 반드시 다른 byte (충돌 방지, 단위 테스트로 검증됨: `tests/verification/test_canonical_certificate_serialization.nim`).

### (d) Promotion은 byte 비교가 아닌 identity 비교 (C4)

- Promotion의 idempotency 판정은 raw 파일 바이트 비교가 아니라 `sameCanonicalIdentity` (canonical identity 비교)를 쓴다:
  - 기존 artifact 바이트가 trailing newline 등 모양만 다르고 semantic identity가 같으면 **같은 certificate** → IDEMPOTENT SUCCESS.
  - 다만 최종 vault에 기록되는 바이트는 항상 단일 canonical serializer 산출물 하나.
- 이 규칙은 "semantic identity ≠ byte identity"인 레거시 artifact도 제품 성공 상태로 간주하는 것이 아니라, **canonical identity가 같고 그 identity로 재승격되는 경우만** 허용한다 (C4 "same canonical identity → repeated promotion = success/no-op").

### (e) Golden Canonicalization Test

- `tests/verification/test_canonical_certificate_serialization.nim`:
  - trailing newline 유/무 변형이 canonicalize/identity/bytes에서 동일해야 한다 (A vs A+`\n`).
  - field ordering, number formatting, omission, array ordering drift를 잡는 golden vector.
- 이 테스트만으로 향후 serialization drift를 조기 포착한다.

---

## §7. Subject Language & 결합 채널 (Rust subject 노트)

- **`subjectLanguage` 신설**: certificate가 검증하는 subject의 언어 선언. 값은 `nim` \| `rust` 둘 중 하나. **현재 상태는 deferred다** — 코드 미구현·identity 키(`canonicalV3FieldKeys` 13개) 미편입이므로, 확정은 schemaVersion bump 세대에서 이뤄진다(§2 필드 표). 스키마 변경이므로 **반드시 schemaVersion bump를 동반한다**(본 문서 헤더 규칙). Rust subject의 범위 선언은 `docs/spec/rust_certified_subset.md`가 담당한다 — 전체 Rust 지원을 의미하지 않는다.
- **"conditional guarantee" 명명 필드는 도입하지 않는다** — breaking change로 별도 비준 대상이다. 조건부성(conditional-ness)은 이미 전이적으로 결합되어 있다: `obligationId`(`canonicalAssumptions` 포함) → `evidenceId` → `identityDigest`. 또한 `leanProposition`이 discharged hypotheses를 텍스트로 운반한다. 이 결합을 신규 필드로 재표현하는 것은 중복 의미 상태다.
- **도구 신뢰 채널**: rustc→LLBC 보존 같은 tool trust는 `toolchainFingerprint`([docs/spec/productization_contract.md] §10.2) → `evidenceId` 경로로 결속된다. `assumptions`는 프로그램 전치조건(program preconditions) 전용 채널이며 도구 신뢰를 운반하지 않는다 — 혼용 금지.
