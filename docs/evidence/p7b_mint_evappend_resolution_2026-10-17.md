# P7b MINT_EVAPPEND 잔여 UNKNOWN 해소 — #814 (2026-10-17)

> **종류**: 정적 분석 + 보존 아티팩트 실증 기록. **대상**: `mg_venue_divergence_forensics_2026-10-17.md` §3.4의 잔여 UNKNOWN(#814 merge_group 3회 P7b 실패, PR green·트리 동일).
> **판정**: 근본 원인은 **복제 다이제스트 정의 버그** — AttestationInputs v2 와이어 확장(4→7멤버) 직후, 소비자가 4멤버 jq 투영을 재유도해 권위(7멤버 정규 와이어)와 비교했다. venue 의존 필드 아님. MG-only 발현은 P7b가 landing venue 전용 실행이라는 순수 비대칭. 트리거는 수정 커밋 `026eaafc6`(=#815 head, 당일 직접 머지)로 제거됐다(ADR-0034 "all-landing blockage"의 일부).

## 1. 코드 경로 (file:line)

- 검사점: `certificate-mint.yml` publish 잡 P7b(SL-15) — `if: scope_sl15=='true' && venue=='landing'`(현행 :2219-2220) — **PR venue는 P7b 미실행**(ADR-0032).
- 실패 당시 소비자: `jq -S -c '{funcSource, funcName, leanSource, smtlib2}'`(4멤버) sha256 vs witness `.semantic.evidenceDigest` — 오류 원문과 글자 단위 일치.
- 권위: `evidenceBundleDigest` = **7멤버** `{funcSource, funcName, leanSource, smtlib2, toolchainIdentity, llbcDigest, rustToolchainIdentity}`의 RFC 8785 sha256 (`src/verification/attestation_orchestrator.nim:179-198`). 현행 P7b는 비교-전용(레코드 운반 `evidenceDigest` == witness, :2328-2337).

## 2. 기제 판정

| 가설 | 판정 |
|---|---|
| 복제 다이제스트 정의(4 vs 7멤버) | **확정** — `fd10b05f4`(v2 확장, PR #803 10-13 07:25Z 착지) → 08:58Z부터 신선 B빌드 노출(ADR 인용 pr-806/pr-810 런 — #814와 같은 큐 베이스 `ba773d06`) → #814 큐 3회(13:02–13:09Z, 그룹 커밋 전부 merge(ba773d06, 7d131271)로 수정 미포함) 동일 결정론적 mismatch |
| prHeadSha/subject-identity 불일치(포렌식 가설) | **반증** — provenance는 digest 외. 3런 witness digest `91b2ec52…` 전부 동일(그룹 커밋·runId 상이에도) |
| base sha 변동 | 반증(digest 미해시 + 양 venue 동일 B) |
| run/attempt 피닝·스테일 아티팩트 | 반증(P7b는 동일 런 exactly-one+expired=false 조회) |

## 3. 실증 (보존 아티팩트로 재현 — run 38401843972 외 2런 생존)

- `payloadSha256==sha256(payload)` ✓, `proj==w_proj` ✓ — 변조·유출 없음
- `sha256(4멤버)=6fa5af61909f…` ≠ witness `91b2ec522c76…` — **실패 원문 재현(ADR-0034 인용 12-hex와 동일)**
- **7멤버 재계산 == witness MATCH** — witness가 단일 정의의 출력임 확증
- run1 vs run3: evidenceKey·payloadSha256·witness digest 동일 — identity 안정

## 4. 재발 감시 시그니처

- grep(mint-publish/publish P7b): `MINT_EVAPPEND: FAIL` · `binding broken`(현행 비교 실패) · **`sha256(bundle wire) != witness` — 현행 코드에서 발생 불가, 관측 시 026eaafc6 퇴행** · `old-format record`(세대 절반 절단) · `expected exactly one artifact named 'evidence-record-`
- 아티팩트(당일 확보 — admission-verdict 3일 보존): evidence-record.json(`evidenceDigest` 존재·일치?), witness.json(`.semantic.evidenceDigest`, `.provenance.*`), 런 id·attempt·head_branch(큐 브랜치가 base 인코딩)
- 판별식: 4멤버≠witness ∧ 7멤버==witness → 소비자 버그 재유입; 7멤버도 ≠ → 실 semantic divergence(툴체인/llbc 핀 이동)

## 5. 귀결

venue 결함 없음(포렌식 판정 유지·강화) — **수정 대상 없음, 재발 감시 등록으로 종결.** 전 과정 읽기 전용(`/tmp/p7b_verify/`).
