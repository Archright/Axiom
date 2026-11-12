# Debt Registry Schema

**생성일**: 2026-07-29  
**상태**: Active schema extension for theater debt entries from `DEBT#357`.  
**소스**: `data/debt_registry.json`, `data/debt_schema.json`, `src/core/audit/theater_skip.nim`  
**AGENTS.md 참조**: §0.9 Theater Prohibition, §0.9a Theater Debt Registry Schema

---

## 1. Purpose

`data/debt_registry.json` is the canonical JSON registry for Axiom debt entries. The file is a JSON object with:

- `version`: registry version.
- `generatedAt`: UTC generation timestamp.
- `scanner`: origin of the registry update.
- `entries`: array of debt entry objects.

The registry also carries JSON Schema metadata at the top level:

- `$schema`: JSON Schema draft URI.
- `$comment`: human-readable schema note for tools that do not consume formal validation.

---

## 2. Top-level schema

| Field | Type | Required | Description |
|---|---:|---:|---|
| `$schema` | string | Optional | JSON Schema draft URI. Current value: `https://json-schema.org/draft/2020-12/schema`. |
| `$comment` | string | Optional | Schema documentation comment. |
| `version` | integer | Yes | Registry version. |
| `generatedAt` | string | Yes | UTC ISO 8601 timestamp. |
| `scanner` | string | Yes | Registry update source. |
| `entries` | array | Yes | Debt entries. |

---

## 3. Entry schema

Each entry is a JSON object.

| Field | Type | Required | Description |
|---|---:|---:|---|
| `id` | string | Yes | Debt identifier, e.g. `DEBT#357`. |
| `category` | string | Yes | Debt category. Theater entries use `Theater/...`. |
| `title` | string | Optional | Short human-readable title. |
| `impact` | string | Optional | Impact level such as `low`, `medium`, `high`, or `critical`. |
| `severity` | string | Yes | Debt severity. Prefer `critical`, `high`, `medium`, or `low`. |
| `description` | string | Yes | Debt description. Include remediation status, audit links, and any justification. |
| `files` | array[string] | Yes | Affected file paths. Paths may include line ranges, e.g. `src/foo.nim:12-34`. |
| `file` | string | Optional | Single-file alias used by theater skip matching. |
| `source` | string | Yes | Origin of the debt entry. |
| `status` | string | Yes | Lifecycle status, e.g. `open`, `closed`, `accepted`, `deferred`, `in_progress`. |
| `symbol` | string | Theater required | Exact procedure/function/macro signature or artifact symbol. |
| `contentHash` | string | Theater required | `sha256:` digest of the canonical body or exact artifact content. |
| `lineRange` | string | Theater required | Human-readable line range hint. |
| `resolution` | string | Theater required | Freeform per `data/debt_schema.json`; canonical preferred values: `FIXED`, `FALSE_POSITIVE`, `WONT_FIX`, `ORPHANED`. `UNRESOLVED` = honest unresolved state while remediation is in progress (precedent: `DEBT#506`, `DEBT#507`, `DEBT#511`). |
| `lastVerifiedAt` | string | Theater required | UTC ISO 8601 timestamp. |
| `binding` | string | Optional | Binding-type declaration: `nim_pragma` or `registry_disposition`. Absent = legacy `nim_pragma` interpretation — guaranteed by validator behavior (the conditional below only fires when `binding` is present), not by a schema `default` keyword. See §10. |
| `bindingRationale` | string | Conditional | Required iff `binding` = `registry_disposition`. One-line reason plus explicit trace pointers. See §10. |

---

## 4. Theater entry requirements

Theater entries are entries whose `category` starts with `Theater/`.

All theater entries from `DEBT#357` onward MUST include:

- `symbol`
- `contentHash`
- `lineRange`
- `resolution`
- `lastVerifiedAt`

Agents MUST check `data/debt_registry.json` before investigating suspected theater. If a theater entry has matching `file` or `files` path, matching `symbol`, and matching `contentHash`, the agent can treat it as a 0-token skip for that exact finding.

False positives MUST use:

```json
{
  "resolution": "FALSE_POSITIVE",
  "description": "Clear justification for why the suspected theater is not theater."
}
```

---

## 5. Resolution values

Machine authority: `data/debt_schema.json` defines `resolution` as **freeform** — `debt_engine --validate` enforces only presence (non-empty string), not an enum. The table below lists the **canonical recommended values**, not the machine allowlist. `UNRESOLVED` marks an honest unresolved state while remediation is in progress (precedent: `DEBT#506`, `DEBT#507`, `DEBT#511`).

| Value | Meaning |
|---|---|
| `FIXED` | The theater pattern was corrected and verified. |
| `FALSE_POSITIVE` | The suspected theater did not violate the theater prohibition. Must include clear justification. |
| `WONT_FIX` | The theater pattern remains known and is not fixed in this registry revision. It must remain an open debt item and be addressed by a separate remediation action. |
| `ORPHANED` | The artifact is unused, unreachable, or otherwise orphaned. |
| `UNRESOLVED` | Remediation not yet complete — the finding remains an honest open issue, not a satisfied debt. |

---

## 6. `contentHash` rules

`contentHash` is always a `sha256:` digest.

For procedure/function/macro bodies:

1. Select the canonical body named by `symbol`.
2. Hash the declaration line through the final body line.
3. Trim leading and trailing whitespace before hashing.
4. Store the digest as `sha256:<hex>`.

For non-procedure artifacts, such as manifest or documentation entries:

1. Use the exact artifact content, or the exact line/line-range content named by `lineRange`.
2. Store the resulting digest as `sha256:<hex>`.

---

## 7. `lineRange` rules

`lineRange` is a human-readable hint, not a machine parser. It SHOULD:

- Use relative paths when possible.
- Use `path:start-end` ranges.
- Separate multiple ranges with `;`.
- Keep the range stable across small edits when possible.

Example:

```json
{
  "id": "DEBT#357",
  "category": "Theater/Always-Pass",
  "symbol": "runVerificationPipeline*(ir: AxiomIRNode): bool",
  "contentHash": "sha256:f07be477c8eb14fb72290ebe2e0edf3eae50da7c38cf82d27d3aa90bbb131c8a",
  "lineRange": "src/core/verifier/lean_repl_bridge.nim:46-69; src/verification/lean_repl_bridge.nim:346-358",
  "resolution": "WONT_FIX",
  "lastVerifiedAt": "2026-07-29T00:00:00Z"
}
```

---

## 8. Validation checklist

Before adding or editing a theater entry, agents MUST verify:

1. The entry category starts with `Theater/`.
2. `symbol`, `contentHash`, `lineRange`, `resolution`, and `lastVerifiedAt` are present.
3. `contentHash` starts with `sha256:` and has 64 hex characters after the prefix.
4. `resolution` is present and non-empty (freeform per `data/debt_schema.json`; prefer canonical values from §5).
5. `lastVerifiedAt` is an UTC ISO 8601 timestamp.
6. False positives include a clear justification.

---

## 9. Fact → Authority Map (부채 사실별 단일 권위)

부채 서브시스템의 모든 사실(fact)은 정확히 하나의 권위(authority)를 가진다 — 그 사실을 결정하는 단일 작성자만이 값을 변경할 수 있다. 파생 뷰(projection, count, report, cache)는 사실이 아니며 아무것도 결정하지 않는다.

`docs/DEBT_REGISTRY.md`와 `src/generated/debt_constants.nim`은 `debt_engine` codegen이 `data/debt_registry.json`에서 생성하는 projection이다 — [debt_projection_contract.md](debt_projection_contract.md) §1: "The two projections are **materialized views**, not sources of truth". projection 편집은 사실을 변경하지 않으며 수동 편집은 금지된다.

| Fact | Authority (단일) | Notes |
|---|---|---|
| debt 의도 — open/closed/deferred, severity, resolution 결정 | `data/debt_registry.json` (SSOT) | 권위 선언 및 sink 집합: [adr/0029-debt-projection-writer-authority.md](adr/0029-debt-projection-writer-authority.md). 정본 mutation device = `tools/debt_engine.nim`. |
| registry 구조 — field shapes/types/allowlist | `data/debt_schema.json` | enforced by `debt_engine --validate` |
| 측정값 — budget metric current/target/baseline | `data/debt_ledger.json` | owner: `tools/sync_budget.nim` (`LedgerPath`; baseline은 observations로부터 reconcile) |
| 관측 이력 — metric observation event trace | `data/debt/metric_observations.journal` | owner: `tools/sync_budget.nim` (`ObservationsJournalPath`, append-only) |
| evidence semantics — 증거 의미론 | `docs/spec/evidence_calculus.md` | Evidence Calculus contract |
| 코드 현재 상태 — what the source actually is | Git (repository tree) | — |
| 변경 이력 — who changed what, when | Git history | — |
| build closure 사실 — gate result가 의존하는 것 | compiler/build graph (`computeCompositeLockHash`, transitive import closure) | `src/core/gate/gate_memo.nim`, `src/core/gate/transitive_hash.nim` |

집행 상태: registry 구조(schema structure)는 `debt_engine --validate`가 집행하며, registry/ledger/journal 간 disjointness와 live-file 존재 검증도 동일 경계에서 집행된다 (W6/W7). 이 표는 그 계약의 기술(description)이다.

---

## 10. Binding type (바인딩 유형 계약)

STALE 클래스 부채(레지스트리에는 open인데 `{.axiomDebt.}` 마커가 src/에 없는 항목) 중 상당수는 마커가 **구조적으로 불가능한 매체**(workflow YAML, Makefile, FROZEN 서피스)이거나 **의도적 무마커 등록**(ADR-0029 §5 승인 표면, §0.9 등록 규율)이다. `binding` 필드는 이 두 클래스를 마커 부재의 *우연*이 아니라 *선언된 처분*으로 기계적으로 구분한다.

### 10.1 허용값과 부재 해석 (검증기 동작 + 산문 이중 명시)

| `binding` 값 | 의미 | 검증기 동작 |
|---|---|---|
| (키 부재) | 레거시 관례 — `{.axiomDebt.}` 님 프라그마 바인딩으로 해석 | 조건부 발동 안 함 → 부가 요구 0 → valid |
| `nim_pragma` | 명시적 마커 바인딩 선언 | valid |
| `registry_disposition` | 레지스트리 엔트리 자체가 바인딩 매체 | `bindingRationale` 필수 (조건부) → 없으면 invalid |
| 그 외 전부 (`comment_marker` 포함) | — | enum 위반 → invalid |

**부재 해석의 근거는 산문이 아니라 검증기 동작이다.** `data/debt_schema.json`의 `allOf` 조건부는 `required: ["binding"]`을 `if` 안에 두므로, `binding`이 없으면 then-브랜치(`bindingRationale` 요구)가 아예 평가되지 않는다. 스키마 `default` 키워드는 사용하지 않는다 — 기존 레코드 234건은 필드를 추가하지 않아도 valid 상태가 유지된다(양성 시험: tests/ci/test_debt_schema_theater_rule.py의 레거시 무-binding fixture).

### 10.2 `bindingRationale` 내용 규칙과 추적 지시 요건

`registry_disposition`인 엔트리의 `bindingRationale`은 다음을 한 줄로 담아야 한다:

1. **한 줄 이유** — 왜 이 엔트리가 마커 없이 레지스트리에 바인딩되는가 (비-Nim 매체 / FROZEN 서피스 / ADR 승인 표면 / §0.9 등록 명령 등).
2. **추적 지시** — 같은 엔트리의 `resolution`/`source` 필드를 명시하고, 해당 시 외부 문서 경로 + 항목 ID (예: `docs/adr/0029-debt-projection-writer-authority.md` ADR-0029, `docs/adr/0038-debt-status-vocabulary-decision-request.md` ADR-0038, DEBT#466-470 사유 참조).

형식 강제(기계): `minLength: 1` + `\S` 패턴 — 공백-only rationale는 invalid. `comment_marker`는 **예약값**으로, 등장 시 enum 위반 → FAIL.

### 10.3 정직 범위 선언 (Honest Scope)

본 계약이 완료하는 것은 문서화된 처분을 참조하는 바인딩 선언의 **기계적 형식 검증**이지, 처분의 의미적 정당성 자동 입증이 **아니다**. `bindingRationale`의 존재·비공백·추적 지시 형식은 `bin/debt_engine --validate`가 검증하지만, rationale이 서술한 처분 자체(예: "이 매체에는 마커가 불가능하다")의 진위는 여전히 인간 검토와 해당 문서의 권위에 의존한다. STALE FAIL 자체는 FROZEN 게이트(`bin/debt_integrity_gate`)가 그대로 보고한다 — 본 계약은 그 FAIL을 해소하거나 마스킹하지 않는다.

---
