# Bug Attribution Grounds File — record schema (v1)

> **Status**: Committed record schema — `data/bug_attribution/<SPEC-ID>.json`의 fail-closed 검증 계약 (T2 record layer)
> **Created**: 2026-10-10
> **AGENTS.md 참조**: §0.5 (문서 우선), §0.9 (극장 금지), §2.6 (변경 불변조건), §0.11 (어휘)
> **Terminology**: [bug_verdict_glossary.md](./bug_verdict_glossary.md) §2.2 (공용 4요소) · §2.4a (Bug Confirmed) · §2.4b (우선순위) · §2.4c (requirementSourceStatus)
> **Validator (pure)**: `src/core/trusted/bug_attribution_grounds.nim` — `validateGroundsFile` / `validateClaimOwnership` / `computeRecordDigest`

---

## 1. 성격 — 기록 계층, 표시 라벨 없음 (HARD RULE)

grounds 파일은 upstream 귀속 판정의 **근거 기록(canonical record)**이다. 표시 라벨("Bug Confirmed" / "Bug Suspected" / "Axiom-Defined Rule Violated")은 **저장하지 않는다** — 라벨은 투영 계층이 기록 필드로부터 **유도**하는 것이며(§2.4b 우선순위), 기계 상태 ↔ 기록 필드의 교차 유도는 금지된다(glossary §2.4c). 닫힌 키 집합(closed key set)이 저장된 라벨을 검증 오류로 거부한다.

## 2. 스키마 (`bug-attribution-grounds-v1`, 닫힌 키 집합)

| 키 | 형 | 의미 |
|---|---|---|
| `schema` | string 상수 | `"bug-attribution-grounds-v1"` |
| `specId` | string | 인용하는 spec overlay의 `specId`와 일치해야 한다 |
| `subjectCommit` | 40-hex | 주체 커밋 OID — 인용 spec의 `subject.commit` 핀과 정확히 일치해야 한다 (필드 동등 비교; `subject.repository`는 서술형 문자열이므로 결속 근거가 아니다) |
| `moduleSha256` | 64-hex | 주체 모듈 blob 해시 — 인용 spec의 `subject.blobSha256`와 일치해야 한다 |
| `requirementSourceStatus` | 닫힌 집합 | `recordedBinding \| recordedDisclaiming \| unrecorded \| unknown` (glossary §2.4c — 제4값 `unknown` = 출처 판정 미완료, 잠정 상태; 2026-10-31 추가) |
| `requirementSourceRefs` | ≥1 non-empty string | 요구 출처 기록의 위치(예: 계약 §7 docstring-"estimated" 기록) |
| `anomaly.observationQuartet` | 공용 4요소 | glossary §2.2의 **단일 정의**를 그대로 운반: `exactCommit`(`subjectCommit`와 일치) · `exactInput`(비어 있지 않은 객체) · `violationStatement` · `reproduction` |
| `anomaly.observationQuartet.reproduction` | 닫힌 키 | `observedOutput`(비어 있지 않은 객체) · `replayCommand` · `toolchain` · `hostPlatform` · `source`(독립 외부 출처 — pipeline verdict는 출처가 아니다, §2.4b ②) |
| `confirmation.grounds.{E1,E2,E3}` | `{present, refs[, reproduction]}` | Bug Confirmed 근거 범주(glossary §2.4a, 비망록적). **present:true ⇒ refs 비어 있지 않음 ∧ reproduction 사분위 완비**; **present:false ⇒ refs 공백 ∧ reproduction 블록 없음** |
| `corroboration.{machineRef, note}` | 객체 | M 계약 계층 기계 기록 참조(`specId`=`specId` 일치, `verdict`, `replayVerdict`) + "corroboration ONLY" 비고 — 보강은 C-carried 재현 요건을 **결코** 충족하지 않는다(glossary §2.4a) |
| `recordDigest` | 64-hex | 아래 §3의 정준 직렬화 digest |

그 외의 어떤 키도 허용되지 않는다 — 검증 오류(fail closed).

## 3. recordDigest 산출 방법 (결정론)

```
recordDigest = sha256_hex( pretty(parseJson(fileBytes)) 에서
                           최상위 "recordDigest" 멤버를 삭제한 뒤
                           std/json pretty(2-space indent) 직렬화 + trailing LF 1개 )
```

- Nim 구현: `computeRecordDigest(node)` (`src/core/trusted/bug_attribution_grounds.nim`) — `parseJson($node)` 심복사 후 `delete("recordDigest")`, `pretty` 출력에 `"\n"`을 붙여 `sha256Hex`.
- digest는 자기 자신을 덮지 않는다(비순환). 검증기는 동일 계산과의 일치를 강제한다(불일치 → fail closed).

## 4. 검증 표면 (fail-closed)

`validateGroundsFile(grounds, spec)`의 거부 사유: 루트 비객체 · 미기대 키(라벨 저장 포함) · schema 상수 불일치 · `specId`/`subjectCommit`/`moduleSha256` 교차 불일치 · 미지 `requirementSourceStatus` · 4요소 결측 · `groundsValidation: E# present:true` with 재현 결측 · `groundsValidation: E# present:false` with refs/재현 존재 · corroboration 미표기 · digest 불일치.

`validateClaimOwnership(specNode)`의 거부 사유: 블록 결측 · 미기대 키 · owner가 `{axiom-defined-rule, software-requirement}` 밖 · `contract`가 `docs/spec/` 밖 또는 overlay의 `contract` 필드와 모순 · `adoptionRef` 공백.

이 모듈은 판정 값을 생산하지 않고 게이트·required check를 만들지 않는다(glossary §1 HARD RULE) — 오직 기록을 거부한다.
