# Canonical Verification Query Identity 설계안 (Phase B)

## 1. 동기 (Motivation)

`verification-auditor`의 verdict가 pure function이 아니어서 (git log, binary staleness, baseSha 무검증, env), 같은 commit이라도 substrate에 따라 결과가 갈린다.

캐시/재사용/incremental은 Verification Identity가 완전히 결정되어야만 sound하다.

이 문서는 설계안이며, 본 Phase에서는 문서만 작성한다 (코드 구현 금지).

## 2. 핵심 모델 — 검증을 순수 함수로

```
VerificationResult = F(BaseSnapshot, HeadSnapshot, DeclarationSet, EvaluationIdentity, Toolchain, Policy, DerivedEffects, AuthorizationSet)
```

- 실행 환경(local/CI/self-hosted)은 transport일 뿐, F는 결정론적 순수 함수.
- local PASS / CI FAIL 이 나오면 "환경 차이"가 아니라 "결정론 불변식 붕괴"로 취급.

## 3. QueryID 정의 (B-2)

```
QueryID = CanonicalEncode(
    BaseSnapshot, HeadSnapshot, DeclarationSet,
    EvaluationIdentity, Toolchain, Policy,
    DerivedEffects, AuthorizationSet
)
```

- canonical serialization (RFC 8785 JCS 기준) 사용.
- QueryID는 절대 untracked/git state/env/clock/binary mtime을 포함하지 않음.

| Component | 포함 | 제외 |
|---|---|---|
| BaseSnapshot | provenance 있는 관찰(baseSha) | git log --grep |
| HeadSnapshot | provenance 있는 관찰(headSha) | shallow depth |
| DeclarationSet | typed/mutable transition declaration | commit hash identity |
| EvaluationIdentity | schema/tool revision | binary hash(별도 취급) |
| Toolchain | Nim/Lean/deps 버전 | 파일 존재 여부 |
| Policy | VerificationPolicy snapshots | 전역 mutable state |
| DerivedEffects | closed-world enum | wildcard |
| AuthorizationSet | 서명 검증된 승인 | bypass policy 혼용 |

## 4. Dependency DAG (B-3)

각 QueryID component가 어떤 다른 component에 의존하는지 명시. 예:

```
BaseSnapshot ──┐
HeadSnapshot ──┤
DeclarationSet─┼─> QueryID ──> VerificationResult
Policy ────────┤       │
Toolchain ─────┘       └──> Obligation closure ──> per-obligation verdict
```

- per-obligation verdict는 전역(정책/도구체인/승인)에 의존하므로 obligation-level 재사용은 unsound임을 명시 (B-2에서 검증된 사실: VerificationPolicy, toolchainIdentity, debt Authorization).
- 캐시가 허용되는 최소 단위는 QueryID 전체가 동일할 때뿐임을 강조.

## 5. Result-shape (B-4)

검증 결과를 observation과 proof로 분리:

- PASS artifact = 재사용 가능한 증명(proof-like) — 동일 QueryID에서만.
- FAIL = diagnostic observation (환경/구성/불완전 substrate 때문일 수 있음) — 증명이 아님. FAIL은 기본적으로 재실행.

결과 스키마 예:

```
VerificationResult {
  queryId: string
  verdict: PASS | FAIL
  obligations: [{ id, kind, verdict, reason }]
  baseSnapshot, headSnapshot
  declared: [...], derived: [...]
  evaluationIdentity, toolchainIdentity, policyDigest
  classificationDrift: [...]   // unexpected addition/removal/reclassification
}
```

## 6. Artifact identity (B-5)

검증 산출물(proof/CAS/snapshot)을 identity-keyed immutable artifact로 모델링:

```
ArtifactID = SHA256(canonical(검증 입력 + verdict + provenance))
```

- commit SHA는 identity가 아니라 ref pointer일 뿐. same commit + 다른 config/toolchain = 다른 artifact.
- binary identity는 hash 검증(file 존재만 아님) 필요.

## 7. Incremental 실행 (B-6) — 설계만, 구현 아님

```
change → canonical snapshot → semantic diff → affected obligations → exact verdict
```

- 초기 단계는 memoization 없이 "영향받은 obligation만 재평가" 후 gate verdict 재구성.
- 이 설계는 이후 Phase에서 구현하며, 본 Phase에서 어떤 코드도 만들지 않는다.

## 8. 결정 사항 / 열린 질문

- 채택: PASS만 재사용 후보, FAIL은 재실행, QueryID 전역 결정 후에만 캐시.
- 열린 질문: BaseSnapshot provenance 저장 위치, DeclarationSet 전송 형식의 정식화.

## 9. 이 문서의 범위 제한

- Phase B는 설계 문서만. 코드/테스트/ci.yml/Makefile/gate 수정 없음.
- PR #27 9파일, PR #28 16파일, shadow dirty 3파일 무접촉.

Design owner: Phase B / Date: 2026-09-02
