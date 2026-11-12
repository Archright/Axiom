# ADR-0034: Evidence CAS v2 바인딩 단일 정의 — record.evidenceDigest 운반 + 소비자 비교-전용

## Status

**Accepted (2026-10-13)** — 아키텍처 결정 기록이며 구현을 수반한다
(`src/verification/evidence_ledger.nim` 레코드 코덱 + `src/verification/attestation_orchestrator.nim`
`buildEvidenceCasRecord` 3-파라미터화 + `.github/workflows/certificate-mint.yml` P7b
비교-전용 재작성 — 단일 PR, §Decision (e)). 상위 사건: 2026-10-13 MINT_EVAPPEND
전체 랜딩 차단 인시던트.

## Context

v2 세대(`axiom.attestation.evidence.v2`, `attestation_orchestrator.nim` EvidenceScheme)에서
번들 다이제스트의 권위는 **단일 정의**다: `evidenceBundleDigest(AttestationInputs)` =
sha256 over 정규 7-멤버 `evidenceBundleWire` (funcSource, funcName, leanSource, smtlib2,
toolchainIdentity, llbcDigest, rustToolchainIdentity). 증인(witness)은 같은 권위 함수의
값을 `.semantic.evidenceDigest`에 실어 나른다(`attestation_witness.nim` — 생성 시
`evidenceBundleDigest`, 검증 시 재계산 대조).

그러나 certificate-mint.yml P7b는 이 단일 정의를 **셸에서 복제**하고 있었다: 레코드
payload의 4-멤버 jq 프로젝션을 다시 해시해 증인 digest와 비교. v2가 번들을 7-멤버로
넓히면서 이 복제 정의는 구조적으로 어긋났고(4-멤버 해시 ≠ 7-멤버 해시), #803 자체
랜딩 당시에는 B-빌드 구바이너리가 그것을 가렸다가 2026-10-13 08:58Z부터 모든
merge-queue 랜딩을 차단했다(런 38372935908·38375124648 —
`sha256(bundle wire) '6fa5af61…' != witness evidenceDigest '91b2ec52…'`).

근본 원인은 버그 한 줄이 아니라 **구조**다: 소비자가 digest를 "다시 유도(re-derive)"
할 수 있으면 멤버 집합이 바뀔 때마다 유도 지점이 전부 따라가야 하고, 하나라도
남으면 위장 정합(또는 위장 불일치)이 된다.

## Decision

**(a) 바인딩 계약 — record가 digest를 운반한다.** `EvidenceCasRecord`는
`evidenceDigest` 필드(64-hex, 필수)를 가진다. 권위 = 각 프로듀서의 **자기 단일 정의**:

- 어텔스테이션 증거 레코드: `buildEvidenceCasRecord(plan, payload, evidence)`가
  **모듈 내부에서** `evidenceBundleDigest(evidence)`를 계산해 운반한다 — 호출자는
  임의 digest 문자열을 주입할 수 없고(Condition C — injection-proof), payload에서
  유도되지 않으며, 증인에서 복사되지도 않는다(Condition A).
- 자기완결 레코드(judgment 프로젝션 = `judgmentProjectionDigest(payload)`,
  extraction job = payload 내용 해시): payload 그 자체가 증거 객체이므로 그 자신의
  내용 digest가 바인딩 digest다.

`makeEvidenceRecord`는 64-hex 서식만 검증(형식 강제), 값을 다시 유도하지 않는다.
`payloadSha256`은 계속 payload에서 파생(입력 불가) — 두 digest는 서로 다른 객체에
묶인다(번들 와이어 vs payload 바이트; 비혼동 테스트로 고정).

**(b) 소비자는 비교만 한다 — 유도 금지.** P7b는 `record.evidenceDigest`를 읽어
(결손 → fail-closed, 비-64-hex → fail-closed) 증인 `.semantic.evidenceDigest`와
**문자열 비교**만 한다. 4-멤버 프로젝션 재해시(`proj_sha`)는 삭제된다. payload
와이어(8-멤버 normalizedEvidenceWire)의 결속은 `payloadSha256` + `proj==w_proj`가
그대로 담당한다 — 멤버 집합이 미래에 번들 와이어만 바꾸면 소비자 수정 없이
자동으로 덮인다(비교 대상 양쪽이 같은 권위 함수의 출력이므로).

**(c) 세대 절단 소비자 체크리스트.** `evidenceBundleWire` 멤버를 변경하는 PR은
**같은 일관 세대(coherent generation)** 안에서 다음을 전부 갱신해야 한다
(AGENTS §2.5):

1. 레코드 코덱 (`src/verification/evidence_ledger.nim` — 필드 집합/검증)
2. P7b 소비자 (`.github/workflows/certificate-mint.yml` — **비교 의미가 바뀔 때만**;
   멤버 변경은 (b)에 의해 자동 피복)
3. 셸 프로젝션 — 존재하는 한 (`proj` 4-멤버 `jq` 프로젝션을 넓힐 경우에만)
4. 와이어를 단언하는 테스트 (`tests/verification/test_attestation_evidence_cas.nim`
   T3 wire-definition 등)
5. 본 ADR

**(d) fail-closed 행렬.** P7b와 레코드 파서 양쪽에서:

| 상태 | P7b (mint) | `evidenceRecordFromJson` (ax) |
|---|---|---|
| `evidenceDigest` 필드 결손 (구세대 레코드) | fail — "evidence record evidenceDigest missing (old-format record — fail-closed)" | err — "missing or empty field 'evidenceDigest' (fail-closed)" |
| 비-64-hex | fail — "record evidenceDigest '<v>' not 64-hex" | err — "evidenceDigest must be 64 lowercase hex chars (fail-closed)" |
| record ≠ witness digest | fail — "evidence record evidenceDigest '<12hex>' != witness evidenceDigest '<12hex>' (binding broken — single-definition, fail-closed)" | (증인 대조는 mint 관할 — 파서는 형식만) |

구세대(필드 없는) 레코드는 파스 단계에서 거부된다 — ledger 재판정·재제공·재어펜드
그 어떤 경로로도 되살아나지 않는 세대 절단 백스톱. 절단 이전에 이미 적재된 레코드는
읽기 시 fail-closed된다(마이그레이션은 본 ADR 범위 밖).

**(e) Condition A/B/C 테스트 의무.** 본 결정의 회귀 고정:

- **Condition A** (단일 정의·비혼동): `test_attestation_evidence_cas.nim` T3 —
  `record.evidenceDigest == evidenceBundleDigest(evidence) == subject.evidenceDigest`
  (증인 동일 입력 등식) + `record.evidenceDigest != sha256(payload)` (양쪽 모두
  계산해 불일치 단언).
- **Condition B** (구세대 거부 백스톱): `test_attestation_evidence_cas.nim` T3
  (evidenceDigest 제거 레코드 → 파스 err) + `test_evidence_ledger.nim` E7
  (결손/비-64-hex 거부, 라운드트립).
- **Condition C** (주입 불가): `buildEvidenceCasRecord`는 digest 파라미터가
  없다 — 서명 자체가 계약(`attestation_orchestrator.nim`); T2 HIT 재결합 레코드의
  `evidenceDigest == evidenceBundleDigest(evidence)`가 소비자 등식을 고정.
- **와이어 정의**: T3 — 모듈 자신의 `canonicalJsonString` 규칙으로 독립 구성한
  정규 7-멤버 JSON의 sha256 == `evidenceBundleDigest(inputs)` ==
  `record.evidenceDigest`.

## Known-stale (deferred)

- `src/gate/slice_catalog.nim:263-264` 주석은 여전히 구 바인딩("bundle-wire ==
  witness semantic.evidenceDigest" 재유도형 서술)을 기술한다. 회전 허용 목록 밖이라
  본 PR에서 수정하지 않았다 — 후속 workstream 과제로 여기에 추적된다.
- `docs/spec/nim_concept_and_constructor_quirks.md` §3의 예시 호출
  (`buildEvidenceCasRecord(cas, payload)`)은 ok()/err() 템플릿 quirk 예증용 발췌로
  새 3-파라미터 서명을 반영하지 않는다(예시의 요지는 Result 생성자 quirk — 서명
  아님). 참조 갱신은 문서 세대 절단 시 일괄 처리.
