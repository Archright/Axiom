# WP4-g 권한 감사 (Authority Audit) — WP4-g0

> **실험 ID**: `act2-wp4g-cert-reconcile`
> **본 문서 역할**: WP4-g 설계의 결정론적 projection 계약과 증거 수집의 권한 경계를 기록한다.
> 모든 수치는 측정 결과를 그대로 기록한 것이며, 해석은 별도의 해석 섹션에서 수행한다.

---

## 1. 결과 계약 (Result Contract) — failable projection 함수

```
F(Journal, SourceSnapshot) → Result<CanonicalReferenceProjection, ProjectionError>
```

| `irHash`별 current variant 수 | 반환 값 |
|---|---|
| 0 | `NoCurrentEvidence` |
| 1 | deterministic projection (`bytes`) |
| \>1 | `Ambiguous` |

이 함수는 **부분 함수(partial function)**이다. `>1` variant는 "나쁜 데이터"가 아니라, 현재 계약 하에서 함수 값이 **정의되지 않은 상태**이다. 즉, `Journal`과 `SourceSnapshot`이 잘못된 것이 아니라, 해당 `irHash`에 대해 현재 계약이 단일 결정론적 투영을 보장하지 못하는 입력 영역에 해당한다. `Ambiguous`는 오류가 아니라 **계약의 미정의 영역**이며, 이를 "bad data → error"로 처리하면 안 된다. 대신 `ProjectionError.Ambiguous`로 명시적으로 실패를 보고하고, 상위 정책(Open Issue #1의 `SelectionPolicy`)이 이를 어떻게 처리할지를 결정해야 한다.

---

## 2. 무순서 증거 집합 세마틱스 (Unordered Evidence-Set Semantics)

기존 설계의 parent-chain fold는 **폐기**되었다. 각 journal record는 독립적인 root이며, 시간/순서 필드가 존재하지 않는다. `replayJournal`의 순서는 commitId-lexical 정렬이다 (`trust_commit.nim:399`). 이는 해시 아티팩트이지 의미론적 순서가 아니다.

따라서 증거 수집은 다음 순서를 따른다:

1. journal 레코드를 결정론적으로 열거 (`trust_commit.nim:371` `listCommitIds` → commitId-lexical)
2. 각 레코드를 **독립적으로** 검증
3. 독립 검증 결과를 모아 **canonical evidence set** 구축

**순서는 의미론적 의존성이 아니다**. 레코드 A가 레코드 B보다 먼저 열거되든 나중에 열거되든, 동일한 `Journal` + `SourceSnapshot` 쌍에 대해 동일한 `CanonicalReferenceProjection`이 산출되어야 한다. 이는 `computeStableSourceFingerprint` (`core/proof/source_fingerprint.nim:13`)와 `canonicalCertificateString` (`verification/canonical_certificate_payload.nim:45`)가 순서에 무관하게 결정론적이어야 한다는 것과 동일한 원칙이다.

---

## 3. 내부 데이터 구조 — Variant Set (스키마 한계를 숨기지 않음)

```
R* = { irHash → variants: Set[(certificateIdentity, bytes)] }
SelectionPolicy = RejectMultiple   # variants.size > 1 → AMBIGUOUS
```

`SelectionPolicy`는 **플러그 가능**하다. 현재는 `RejectMultiple`이 기본값이며, `variants.size > 1`이면 즉시 `AMBIGUOUS`로 판정한다. 향후 Open Issue #1이 해결되면 `MultiProjection`(다중 투영 병합)이나 `StrongestEvidence`(최강 증거 선택)로 교체할 수 있으며, 이는 핵심 증거 수집 로직을 재작성하지 않고 `SelectionPolicy` 인터페이스만 교체하면 된다.

`R*`의 구조는 `irHash`에서 `(certificateIdentity, bytes)` 쌍의 집합으로 매핑된다. `certificateIdentity`는 인증서의 정체성을 식별하는 값이며, `bytes`는 인증서의 바이트 표현이다. 동일 `irHash`에 동일 `certificateIdentity`가 중복 등장할 수 있는지는 별도의 스키마 한계이며, 현재 계약에서는 이를 허용하지 않는다.

---

## 4. 순수성 — Case U 완전 제거

기존 vault는 **입력이 아니다**. Case U(기존 vault에 의존하는 경로)는 완전히 제거되었다.

검증 테스트 세 가지:

- (a) **비어 있는 vault** (`loadManifest` (`verification/vault_manifest.nim:41`) 반환 빈 manifest)
- (b) **R1 초기 vault** (기존 reference vault 상태)
- (c) **R2 초기 vault** (R1과 다른 기존 reference vault 상태)

동일한 `Journal` + `SourceSnapshot`에 대해 위 세 경우 모두 동일한 `--check` 출력을 산출해야 한다. vault의 내용이 projection 결과에 영향을 주면 안 된다. `F(Journal, SourceSnapshot)`은 vault를 읽지 않고 오직 journal과 source snapshot만으로 결정론적으로 투영을 계산한다.

---

## 5. 전체 vault 원자 트랜잭션 (Whole-Vault Transaction)

모든 정의가 해석 가능(resolvable)하고, 모든 검증이 통과하며, 모호함(ambiguity)이 없을 때에만 적용(apply)한다. **부분 적용은 없다**.

교체는 단일 `renameat2(RENAME_EXCHANGE)` 시스템 콜로 수행한다. 이는 네임스페이스 전환을 원자적으로 만든다.

- **Crash durability claim 없음**: `renameat2` 자체가 crash-safe를 보장하지 않는다. 플랫폼이 `renameat2`를 지원하지 않거나 실패하면 **fail-closed**이다.
- **비원자적 폴백 없음**: `RENAME_EXCHANGE`가 실패하거나 지원되지 않는 플랫폼에서 비원자적 복사/삭제 폴백을 제공하지 않는다.

---

## 6. 재구성 레시피 (Reconstruction Recipe) — 이미 증명됨

다음 순서로 재구성하면 `verifyCertificateClosure` (`certificate_verifier.nim:207`) 통과만 산출된다:

1. `parse(record.claim)` — 정규화 (stray `trustCommitId`, `provenance`, `attestation` 제거)
2. `trustCommitId` 추가
3. `provenance` 추가
4. Ed25519 결정론적 재서명 — 상수 seed (`signCertificatePayload` (`certificate_attestation.nim:239`), `verifyCertificateAttestation` (`certificate_attestation.nim:254`))
   - **주의**: 상수 seed의 custody는 Open Issue #3이다.
5. RFC 8785 canonical bytes 직렬화 (`canonicalCertificateString` (`verification/canonical_certificate_payload.nim:45`))
6. `verifyCertificateClosure` (`certificate_verifier.nim:207`)로 재검증 → PASS만 허용

이 레시피는 이미 증명된 바이며, 동일한 입력에 대해 항상 동일한 인증서를 산출한다.

---

## 7. 측정 표 (실측 데이터 — 그대로 기록)

| definition | records | closure필터 후 variant | 판정 |
|---|---|---|---|
| safeSpeedupRatioCore | 6 | 3 | AMBIGUOUS |
| clampTimeoutMs | 11 | 4 | AMBIGUOUS |
| firstBoolCore | 5 | 3 | AMBIGUOUS |
| calcDynamicTimeoutCore | 7 | 3 | AMBIGUOUS |
| normalizeMaxWorkers | 8 | 2 | AMBIGUOUS |
| proximityScore 신규(891b6daee) | 1 | 1 | REPLACE 가능 |

**측정 조건**: 동일 journal + 동일 source snapshot에 대해 `F(Journal, SourceSnapshot)`을 적용한 결과.

---

## 8. Run-Residue 발견

현재 reference vault의 6개 인증서 중 **5개는 run-residue**이다. 이는 journal의 결정론적 투영이 아니다.

`ReferenceVault == Materialize(CurrentCanonicalEvidence)`는 5/6에 대해 실제로 실현된 적이 없다.

**Run-residue의 의미**: 이 인증서들은 build/run의 부수 효과(side-effect)로 발행된 것이지, journal reconciliation을 통해 결정론적으로 도출된 것이 아니다. 즉, 어떤 실행이 이루어지는 동안 `signCertificatePayload` (`certificate_attestation.nim:239`)가 호출되어 인증서가 생성되었지만, 해당 인증서가 journal의 결정론적 projection과 일치하는지는 검증되지 않았다. 이들은 `reissueReference` (`cert_promotion.nim:546`)를 통해 기존 vault에 기록된 것으로 보인다.

6개 중 유일하게 결정론적 투영과 일치하는 것은 `proximityScore` 신규 인증서(`891b6daee`)이며, 이 하나만이 `REPLACE` 가능하다.

---

## 9. 4개 Open Issue

### #1 — Vault cardinality / selection semantics (CRITICAL — unblock 전 반드시 해결)

다중 인증서 projection vs 단일 선택 규칙 vs canonical run 지정. 최소 비준화 요건:

- **tier comparability**: Lean ↔ Z3 ↔ NoObligation 순서
- **동일 tier 내 tie-break** 규칙
- **다른 identityDigest 처리** 방법

이 이슈가 해결되기 전까지 `SelectionPolicy`를 `RejectMultiple` 외의 것으로 교체하거나, "latest" / "strongest" 선택 의미론을 발명해서는 안 된다 (§7.10 금지 목록 참조).

### #2 — runId / run identity 부재

journal 레코드에 runId 또는 run identity 필드가 없다. 동일 source에 대해 서로 다른 run에서 생성된 증거를 구별할 수 없다. 이로 인해 "어떤 run의 증거를 materialize할 것인가"에 대한 결정이 불가능하다.

### #3 — Constant-seed signing key custody (재현성 vs 시크릿 키 보안)

결정론적 재서명을 위한 상수 seed의 custody가 결정되지 않았다. 재현성을 위해 상수 seed가 필요하지만, 시크릿 키 보안과 충돌한다. 이 이슈가 해결되기 전까지는 재구성 레시피의 4단계(Ed25519 결정론적 재서명)가 "결정론적이지만 custody가 불확실한" 서명을 산출한다.

### #4 — Archive namespace (보호 / 역사적 분리)

archived(역사적) 인증서와 current 인증서의 네임스페이스 분리가 결정되지 않았다. 현재 vault에 archived cert이 혼재하면 `F(Journal, SourceSnapshot)`의 결정론성에 영향을 줄 수 있다.

---

> **참고**: 위 4개 Open Issue는 본 문서의 범위 밖에서 해결되어야 하며, 본 감사 문서에서 resolution을 시도하지 않는다.
