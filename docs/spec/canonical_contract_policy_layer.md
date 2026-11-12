# Canonical Contract/Policy Layer

> **Status**: Active  
> **Version**: v1.0.0 (Phase A baseline freeze)  
> **SSOT**: `config/policy/contract_layer.schema.json`, `config/policy/policy_layer.schema.json`  
> **Related**: AGENTS.md §0.10 (Decision Binding), §0.9 (Theater Prohibition), docs/spec/decision_binding_framework.md

---

## 목적 (Purpose)

Axiom의 **계약 레이어(Contract Layer)**와 **정책 레이어(Policy Layer)**를 분리하여, 메트릭 결과와 정책 판단을 명확히 구분하는 이중 구조를 정의한다.

- **Contract Layer**: 리포지토리 상태를 관찰하는 불변 스키마 (MetricSpec, ProjectionSpec, Anchor)
- **Policy Layer**: 규칙 정의 → 바인딩 → 결정 분산의 불변 스키마 (Policy, PolicyBinding, DecisionRule)
- **Severity Model**: 메트릭 결과는 `PASS | DRIFT`로 평가자(evaluator)가 결정, 정책 심각도는 `INFO | WARN | ERROR`로 정책(policy)이 독점 결정

이 분리의 핵심 원칙: **평가자는 메트릭 결과만 결정하고, 정책이 심각도를 결정한다**. 이후 WARN→ERROR 에스컬레이션은 평가자를 수정하지 않고 정책만 변경하면 된다.

---

## 이중 구조 다이어그램 (Two-Layer Diagram)

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Canonical Contract Layer (SSOT)                │
│                                                                     │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │
│  │  MetricSpec  │  │  ProjectionSpec  │  │      Anchor          │ │
│  │  - metricId  │  │  - projectionId  │  │  - path              │ │
│  │  - source    │  │  - canonicalState│  │  - symbol            │ │
│  │  - projection│  │  - observations  │  │  - semanticKind      │ │
│  │  - comparison│  │  - version       │  │  - derivedEvidence   │ │
│  │  - version   │  │                    │  │   (lineRange only    │ │
│  └──────────────┘  └──────────────────┘  │    as optional ref)   │ │
│                                          └──────────────────────┘ │
└──────────────────────────┬──────────────────────────────────────────┘
                           │ produces observations
                           ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Canonical Policy Layer                         │
│                                                                     │
│  ┌──────────────┐  ┌──────────────────┐  ┌──────────────────────┐ │
│  │    Policy    │  │  PolicyBinding   │  │    DecisionRule      │ │
│  │  - policyId  │  │  - bindingId     │  │  - decisionId        │ │
│  │  - rule      │  │  - policyRef     │  │  - observationRef    │ │
│  │  - severity  │  │  - subject       │  │  - policyBindingRef  │ │
│  │  - version   │  │  - justification │  │  - disposition       │ │
│  └──────────────┘  │  - owner         │  │  - evidence          │ │
│                    │  - createdAt     │  └──────────────────────┘ │
│                    │  - expires       │                            │
│                    └──────────────────┘                            │
│                                                                     │
│  Severity Model:                                                   │
│  Metric Result: PASS | DRIFT  (evaluator decides)                 │
│  Policy Disposition: INFO | WARN | ERROR  (policy decides)        │
│  Unknown → FAIL-CLOSED (ERROR)                                    │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 요소 테이블 (Element Tables)

### Contract Layer Elements

| Element | Required Fields | Invariant |
|---------|----------------|-----------|
| `MetricSpec` | `metricId`, `source`, `projection`, `comparison`, `normalization`, `version` | 소스 경로와 포맷이 반드시 지정되어야 함. 비교 연산자와 임계값이 반드시 존재. 버전은 세마믹 버전. |
| `ProjectionSpec` | `projectionId`, `canonicalState`, `observations`, `version` | `canonicalState.scope`는 최소 1개 이상의 리포지토리 상대 경로 포함. 관찰 항목은 최소 1개. |
| `Anchor` | `path`, `symbol`, `semanticKind` | **라인 번호는 정체성이 아님** — `derivedEvidence.lineRange`는 선택적 참고 자료일 뿐. `canonicalSyntaxHash`가 정체성의 핵심. |
| `Observation` | `observationId`, `metricId`, `value`, `result`, `timestamp`, `stateHash` | `result`는 반드시 `PASS` 또는 `DRIFT` 중 하나. `observationId`는 결정론적 SHA-256 접두사. |

### Policy Layer Elements

| Element | Required Fields | Invariant |
|---------|----------------|-----------|
| `Policy` | `policyId`, `rule`, `severity`, `description`, `version` | `severity`는 반드시 `INFO`, `WARN`, `ERROR` 중 하나. 규칙 타입은 열거형으로 제한. |
| `PolicyBinding` | `bindingId`, `policyRef`, `subject`, `justification`, `owner`, `createdAt` | `subject`는 반드시 `anchor` 또는 `metric` 타입 중 하나. `expires`가 null이면 영구 유효. |
| `DecisionRule` | `decisionId`, `observationRef`, `policyBindingRef`, `disposition`, `evidence` | `disposition`은 정책이 결정. `evidence.inputHashes`는 재현에 필요한 최소 입력 집합. |
| `EvidenceEnvelope` | `envelopeId`, `decisionId`, `inputs`, `output`, `integrity` | `inputs`는 최소 입력 집합. `integrity.digest`는 전체 엔벨로프의 SHA-256. |

---

## 불변 조건 (Invariants)

| # | Invariant | Enforcement |
|---|-----------|-------------|
| I1 | **Policy/Binding은 관찰(Observation)을 생성하지 않는다** | `PolicyBinding`은 `subject`만 참조하고, `Observation`은 `ProjectionSpec`에 의해 독립적으로 생성됨. |
| I2 | **관찰(Observation)은 정책(Policy)을 수정하지 않는다** | `Observation.result`는 `PASS|DRIFT`만 산출. `Policy.severity`는 `Observation`과 독립적. |
| I3 | **결정(Decision)은 (Observation × PolicyBinding)으로 재현 가능** | `decisionId`는 `observationId + bindingId + timestamp`의 결정론적 해시. `evidence.reproducibleFrom`에 최소 입력 집합 명시. |
| I4 | **증거(Evidence) = 결정 재현에 필요한 최소 입력 집합 (해시 포함)** | `evidence.inputHashes`에 observation, policyBinding, repositoryState 해시만 포함. 추가 입력은 금지. |
| I5 | **알 수 없는 스키마 버전 → FAIL-CLOSED** | 버전 미지원 시 `ERROR` disposition 반환. 경로 없이 즉시 실패. |

---

## 심각도 모델 (Severity Model)

### 메트릭 결과 (Evaluator-Decided)

| Result | Meaning |
|--------|---------|
| `PASS` | 메트릭 값이 임계값 내에 있음 |
| `DRIFT` | 메트릭 값이 임계값을 벗어남 |

### 정책 판단 (Policy-Decided)

| Disposition | Meaning | Fail-Closed Behavior |
|-------------|---------|---------------------|
| `INFO` | 정보적 알림, 차단 없음 | 로깅만 수행 |
| `WARN` | 경고, 커밋 허용되지만 기록 | 경고 출력, 빌드 성공 |
| `ERROR` | 오류, 커밋 차단 | 빌드 실패 |
| 미지원/미지정 | **FAIL-CLOSED** | `ERROR`로 처리 |

**규칙**: 평가자는 메트릭 결과(`PASS|DRIFT`)만 결정한다. 심각도는 정책이 독점적으로 결정한다. WARN→ERROR 에스컬레이션이 필요할 때는 평가자를 수정하지 않고 정책만 변경한다.

---

## JSON 예제 (JSON Examples)

### BUDGET#005 예제: DRIFT 결과 + INFO 판단

```json
{
  "observation": {
    "observationId": "obs_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
    "metricId": "DEBT_REGISTRY_OPEN",
    "value": 7,
    "result": "DRIFT",
    "timestamp": "2026-08-16T06:00:00Z",
    "stateHash": "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
  },
  "policy": {
    "policyId": "BUDGET_POLICY",
    "rule": "BUDGET_LIMIT",
    "severity": "INFO",
    "description": "Budget limit policy: open debt count exceeding threshold triggers INFO-level advisory."
  },
  "decision": {
    "decisionId": "dec_f1e2d3c4b5a6f7e8d9c0b1a2f3e4d5c6b7a8f9e0d1c2b3a4f5e6d7c8b9a0f1e2",
    "observationRef": "obs_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
    "policyBindingRef": "BIND-BUDG005",
    "disposition": "INFO",
    "evidence": {
      "inputHashes": {
        "observation": "sha256:a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
        "policyBinding": "sha256:b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2c3",
        "repositoryState": "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
      },
      "reproducibleFrom": [
        "obs_a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2",
        "BIND-BUDG005",
        "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
      ]
    }
  }
}
```

### Allowlist Anchor 예제

```json
{
  "anchor": {
    "path": "src/gate/runners/import_encapsulation_gate.nim",
    "symbol": "importEncapsulationGate",
    "semanticKind": "proc",
    "derivedEvidence": {
      "lineRange": "1-121",
      "canonicalSyntaxHash": "nim-pnode-canonical-v2:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
  },
  "policyBinding": {
    "bindingId": "BIND-IMPLT01",
    "policyRef": "IMPORT_ALLOWLIST",
    "subject": { "type": "anchor", "anchor": { "path": "...", "symbol": "...", "semanticKind": "proc" } },
    "justification": "AGENTS.md §-1 — Immutable file: import_encapsulation_gate.nim cannot be modified by agents.",
    "owner": "architect",
    "createdAt": "2026-06-01T00:00:00Z"
  }
}
```

### Evidence Envelope 예제

```json
{
  "evidenceEnvelope": {
    "envelopeId": "env_99887766554433221100ffeeddccbbaa99887766554433221100ffeeddccbbaa",
    "decisionId": "dec_1122334455667788990011223344556677889900112233445566778899001122",
    "inputs": [
      { "id": "obs_debt_count_drift", "hash": "sha256:a1a1...", "type": "observation" },
      { "id": "POLICY-ARCHINV", "hash": "sha256:b2b2...", "type": "policy" },
      { "id": "BIND-ARCHEVT1", "hash": "sha256:c3c3...", "type": "binding" }
    ],
    "output": {
      "disposition": "WARN",
      "reasoning": "Architecture invariant violated: core module imports infrastructure layer directly."
    },
    "integrity": {
      "algorithm": "sha256",
      "digest": "sha256:e5e5..."
    }
  }
}
```

---

## 버전 관리 (Versioning)

### 스키마 버전 규칙

| 변경 유형 | 버전 정책 | 예시 |
|-----------|-----------|------|
| 하위 호환 추가 (필드 추가) | 패치 버전 | `1.0.0` → `1.0.1` |
| 하위 호환 변경 (필드 타입 변경 없음) | 마이너 버전 | `1.0.0` → `1.1.0` |
| 하위 호환 없는 변경 (필드 삭제/타입 변경) | 메이저 버전 | `1.0.0` → `2.0.0` |

### 버전 미지원 시 처리 (Fail-Closed)

```nim
# 의사 코드: 스키마 버전 확인 로직
func evaluateWithSchema(obs: Observation; schemaVersion: string): Decision =
  case schemaVersion
  of "1.0.0":
    # 현재 지원 버전
    result = applyPolicy(obs)
  else:
    # 알 수 없는 버전 → FAIL-CLOSED (ERROR)
    result = Decision(
      disposition: "ERROR",
      evidence: minimalEvidence(obs, "unsupported_schema_version")
    )
```

---

## 향후 마이그레이션 경로 (Future Migration Path)

### 1. 심각도 에스컬레이션 (Severity Escalation without Evaluator Change)

WARN→ERROR 에스컬레이션은 **정책(Policy)만 수정**하면 된다. 평가자(evaluator)는 `PASS|DRIFT` 결과만 산출하므로, 정책 레이어의 `Policy.severity` 필드를 변경하는 것으로 충분하다.

```
Before: Policy(severity: "INFO") → DRIFT → INFO disposition
After:  Policy(severity: "ERROR") → DRIFT → ERROR disposition
```

평가자 코드는 전혀 수정할 필요가 없다.

### 2. Allowlist에서 Anchor로 마이그레이션

기존 allowlist 메커니즘이 파일 경로만 관리하는 경우, `Anchor`로 마이그레이션하여 `symbol` + `semanticKind` + `canonicalSyntaxHash`를 추가한다. `derivedEvidence.lineRange`는 선택적 참고 자료로 유지.

### 3. AST Adapter 경계

`Anchor`의 `canonicalSyntaxHash`는 **PNode canonicalization** (`nim-pnode-canonical-v2`)을 거친 결과이다. AST adapter 경계에서:
- `sourceSloc(node)`로 소스 라인 수 계산 (모든 branch)
- `effectiveSloc(node, ctx)`로 효과적 SLOC 계산 (WhenEvaluator 분류)
- `canonicalizePNode(node)`로 정규 해시 생성 (info/comments/synthetic 제외)

이 경계는 `src/core/identity/`에 위치하며, 계약 레이어와 독립적으로 유지된다.

---

## 기존 아티팩트 참고 (Existing Artifact Note)

`src/gate/policy_schema.json`은 기존 게이트 정책 구성 파일로, **본 계약/정책 레이어와 범위가 다르다**. 기존 파일은 수정하지 않으며, 본 문서에서 정의하는 `config/policy/` 스키마와는 별도로 유지된다.
