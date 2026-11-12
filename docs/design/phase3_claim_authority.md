# Phase 3 — Claim Authority (설계)

> 임의의 Evidence에 대해 고정 Policy 아래 **정확히 하나의** well-defined Claim이 유도되고,
> Certificate·VerifiedSet·VKD·CI는 Claim을 **결정하지 않는다** (소비자일 뿐).

## 1. Claim 경계
```
EvidenceBundle
   ↓
deriveClaim(context, policy)
   ↓
VerifiedClaim
```
Claim은 작게: 원본 보관 안 함, identity 참조만.
```
VerifiedClaim* = object
  subjectId*: string
  outcome*: VerificationOutcomeRef     # PROVED/DISPROVED/UNKNOWN/UNSUPPORTED/NO_SPECIFICATION/BLOCKED/INVALID_EVIDENCE
  assurance*: AssuranceProfile
  specificationId*: SpecID
  semanticProfileId*: string
  obligationId*: string
  evidenceId*: string
  dependencySnapshotId*: string
  policyId*: string
  claimId*: string   # H(subject,outcome,assurance,spec,semantic,obligation,evidence,dependency,policy)

## 2. Outcome — 입력 분류 → 파생 (Precedence 없음)
`EvidenceValidity` + `InputClassification` → `Outcome` (7 mutually-exclusive conditions):
| EvidenceValidity/Input | Outcome |
|---|---|
| INVALID evidence (artifact identity/content mismatch, required provenance corrupt) | **INVALID_EVIDENCE** |
| VALID ∧ a dependency missing/unauthorized | **BLOCKED** |
| VALID ∧ unsupported construct | **UNSUPPORTED** |
| VALID ∧ MINED/LLM spec (no authorized spec) | **NO_SPECIFICATION** |
| VALID ∧ solver inconclusive | **UNKNOWN** |
| VALID ∧ counterexample (Z3 SAT real) | **DISPROVED** |
| VALID ∧ spec authorized ∧ depsSatisfied ∧ obligation ∥ solver proved | **PROVED** |
```
- 각 조건은 별도 predicate (mutually-exclusive — 순위 강제 아님). 단 하나 예외: **INVALID_EVIDENCE는 evidence 손상이라 어느 상태보다 우선** (모순 방지; 또한 MINED→PROVED 레이블 만들지 않음).
- `NOT_ENCODABLE`: 원인이 UNSUPPORTED이면 → UNSUPPORTED, 구현 오류이면 → INVALID_EVIDENCE(내부 오류)로 분류.

## 3. Evidence validity (별도 축)
```
EvidenceValidity* = enum { evValid, evIncomplete, evInvalid }
validateEvidence(bundle): EvidenceValidity
  # invalid: required sourceHash is EMPTY / canonicalSpecIR empty /
  #   smtHash 패턴 불일치(채워진 경우) / provenance required 하이 integrity 어길
```
`validateEvidence`는 deriveClaim의 첫 게이트 — **label과 비교 안 함**(자체 identity).  
**중요**: Evidence validity ≠ Assurance dimension. `provenanceComplete/mined`는 EvidenceFact.

## 4. Assurance — vector (a가에서* 결정)
`AssuranceProfile` 5-dim (사용자 지시 대로):
```
Assurance = { specificationAuthority, translationTrust, solverEvidence, replayability, kernelChecking }
specificationAuthority = isAuthorizedForVerification(spec.origin)   # EXPLICIT/CANONICAL_DERIVED → true; MINED/LLM → false
translationTrust     = supported (trusted-subset)
solverEvidence     = solver produced definite outcome (Z3) / evidence present
replayability        = false (T0) / kernelChecking = false (T2 나중)
```
`provenanceComplete`는 **Assurance에서 제거** → Evidence validity로 이동(이미 EvidenceFact에 있음).
`proofArtifactRequired`는 Assurance가 결정 (schema 필수 아님).

## 5. Spec 권한 부여
- EXPLICIT · CANONICAL_DERIVED → authorized
- MINED/LLM → NOT_AUTHORIZED (LLM은 proposal에서만)

## 6. Dependency 해석
Snapshot = **fact**(directDependencies + sourceScope,정책 없음); derive는 `depsSatisfied`를 계산.

## 7. Evidence sufficiency/contradiction
- MALFORMED evidence (invalid) → INVALID_EVIDENCE
- Valid-material but insufficient → INCONCLUSIVE → UNKNOWN

## 8. Immutability & Identity
- immutable; `claimId=H(...)`; consumer는 읽기만.

## 9. Projection boundary
```
EvidenceBundle → deriveClaim(context,policy) → VerifiedClaim
deriveClaim → (Certificate | VerifiedSet | VKD | CI) : 금지 (후속 단계)
```
Certificate/VerifiedSet/CI는 **이번 커밋에서 무변경**.

## 10. 허용 vs 금지 문구
- OK: "under SemanticProfileV1, with Z3 evidence, derived Claim"
- 금지: certGreen/VerifiedSet/CI/VKD가 claim을 결정 / "formally verified"

---

## Acceptance — 8 테스트
| 입력 (Evidence) | 기대 Outcome |
|---|---|
| 1 authorizedZ3+obligation+spec | **PROVED** |
| 2 counterexample (Z3 sat) | **DISPROVED** |
| 3 no specification (mine) | **NO_SPECIFICATION** |
| 4 unsupported construct | **UNSUPPORTED** |
| 5 dep missing | **BLOCKED** |
| 6 Z3 timeout/unknown | **UNKNOWN** |
| 7 evidence inner contradiction/artifact mismatch | **INVALID_EVIDENCE** |
| 8 MINED spec + Z3 "proved" | **NOT_PROVED (NO_SPECIFICATION 우선)** — 레이블 비판단, MINED는 authorized spec 아님 |

---
구현 경계: EvidenceBundle → deriveClaim → VerifiedClaim 까지만. Certificate/VerifiedSet/Index는 변경 없음.
