# Judgment CAS payload 순수화 — R2 기제 수리 근거 (관측 프로토콜)

> Slice: "Judgment CAS payload purity" — R2(`MINT_JUDGAPPEND`
> same-key/different-payload fail-closed)의 근본 수리 착지 기록.
> 계약: `docs/spec/test_judgment_cas_contract.md` §4 v1.0.2 · 주제 SSOT:
> `src/verification/judgment_cas.nim` · 원인 등록:
> `docs/evidence/jcas_phase23_registrations_2026-10-09.md` §R2 · 측정 근거
> 갱신: `docs/spec/judgment_cas_payload_measurement_basis.md` §2.3.
> 수리 커밋: `570a14598` (브랜치 `fix/judgment-payload-purity`, PR #642).
> **작성일**: 2026-10-09.

## 1. 배경 — R2 관측 (등록 전문 요약)

merge-queue 런 `37864249747` (2026-10-09T00:31:38Z)에서 원장 exactly-once 가드가
거절했다 (키 `fe06f08d51c158d90af1210b157c5054056290fa40fae80217f2c9836a593801`):

```
evidence key fe06f08d51c1… already present with DIFFERENT payload bytes
(payloadSha256 mismatch — identity-derivation anomaly, fail-closed, not re-appended)
```

§R2 권한 분석의 결론: 키는 9성분 클로저(결정론)인데 payload는 런 스코프 성분을
포함해 재생성 시 바이트가 달라진다. 가드의 거절은 정상 동작이며, 결함은 payload
결정성의 균열 그 자체다. §R2는 당시 런 스코프 성분 후보를 "수신 영수증 다이제스트"
로 기술했으나, 본 수리의 원장 실측(§2)은 실제 원인 성분이 **`cle.evidenceId`**임을
확정했다.

## 2. 원인 실측 — 원장 카디널리티 (관측 방법 + 결과)

**관측 방법** (read-only; 원장 ref `refs/heads/axiom/evidence-cas`를 로컬 관측 ref로
fetch해 blob을 파싱 — 원장·워크스페이스 무변경):

```bash
git fetch origin 'refs/heads/axiom/evidence-cas:refs/axiom-observe/evidence-cas'
git ls-tree -r --name-only refs/axiom-observe/evidence-cas          # 239 records
git show refs/axiom-observe/evidence-cas:<evidenceKey>.json
```

**모집단**: judgment payload(`schemaVersion: axiom.judgment.cas.v1`) 20건 —
전부 s1a형(cle·acceptsByTheorem 보유). `storedAtUtc` 구간
2026-10-08T17:02:47Z → 2026-10-09T05:56:48Z.

| 성분 | 상이값 수 / 20 | 판정 |
|---|---|---|
| `cle.evidenceId` | **20 / 20** | **런 스코프 — 원인 성분** |
| payload 전체 바이트 | 20 / 20 | evidenceId에 종속해 전부 상이 |
| `evidenceKey`(원장 키) | 20 / 20 | ※ 아래 §2.1 참조 |
| `cle.cleCanonicalKaaJson` | 2 | 툴체인 세대 상관 불변 |
| `cle.cleKaaDigest` | 2 | 〃 |
| `cle.cleToolchainFingerprint` | 2 | 〃 |
| `fold.kaaIdentity` | 2 | 〃 |
| `fold.leanSourceHash` | 1 | 클로저 순수 |
| `executionEpoch` | 2 | 툴체인 세대 상관(클로저 유도값) |
| `verdict` | 1 | 클로저 순수 |
| `kernelAcceptCount` / `probeCount` | 1 (17 / 14) | 정준 카운트 불변 |

### 2.1 전이 경계 — 커밋 해시의 흡수 경로

`cle.evidenceId = H(boundId | propositionHash | leanSourceHash | kaaDigest |
toolchainFingerprint | executionContractDigest)`에서 boundId는 §2.1a 주체 바인딩의
`subjectGitRef`를 흡수하고, `subjectGitRef = measureSubjectGitRef`
(`canonical_verification.nim`) = `git rev-parse HEAD` = **체크아웃 커밋 해시**다.
따라서 같은 tested tree(같은 클로저 ⇒ 같은 키)를 재검증하는 두 런 — 브랜치 헤드 런과
merge-queue 머지 커밋 런 — 이 커밋만 다름으로써 서로 다른 payload 바이트를 유도했다.
§2 표의 키 20/20 상이는 세대마다 커밋이 전진한 결과다: 키의 9성분은 커밋을 참조하지
않아(커밋 비참여 — 계약 §4 ③) 동일 트리 재검증 시 키는 동일하며, 실제 R2 실패 이벤트
(`fe06f08d51c1…`)가 그 충돌이다. 원장에 키 중복이 없는 것은 exactly-once 가드가
두 번째 append를 모두 거절했기 때문이다(거절 = 저장 안 됨).

**나머지 3주체**(proof_integrity·d2_golden·d2_persist)는 wire 검사상 런 스코프
성분이 처음부터 없었다(실측 원장에도 해당 형태 레코드 없음) — 본 수리는 s1a의
`cle.evidenceId`만 제거하고, 4주체 전부를 exact field-set으로 고정해(§3) 재유입을
차단한다.

## 3. 수리 — identity≠payload 분리 + 세대 전환

`570a14598` (4 파일). 원칙: **payload는 클로저의 순수 함수다 — 같은 클로저 ⇒ 같은
키 + 같은 payload 바이트.**

1. `src/verification/judgment_cas.nim`
   - `cle.evidenceId` 제거 — `judgmentEvidenceWire`(직렬화), `JudgmentCleIdentity`
     (캡처 타입), `validateS1aJudgmentPayloadNode` 검증기에서 동시 제거. §2.1a 바인딩
     자체는 비개정 — 커밋은 identity(키)에 계속 참여한다(계약 §4 ③ 구조 유지).
   - `JudgmentKeyScheme` v1→v2 (`axiom.judgment.cas.key.v2`) — 스킴 문자열이 키 유도에
     참여하므로 구세대(v1) 레코드 20건과 same-key 충돌이 원천 불가능. v1 레코드는
     원장의 불변 이력으로 남는다(validator dispatch는 payload 자신의 `schemaVersion`으로
     분기 — v2만 수용, 구세대 재검증 시도는 fail-closed).
   - `JudgmentPayloadSchema` v1→v2 (`axiom.judgment.cas.v2`) — payload 자기 서술 세대 표기.
   - 신설 `exactFieldSet` 헬퍼 — 4주체 검증기 전부가 **정준 필드 집합 exact 강제**로
     전환(s1a top-level+fold+cle, d2_golden top+receipt+chain, proof_integrity·d2_persist
     top). 알 수 없는 필드 = corrupt(fail-closed) — 런 스코프 성분의 재유입을 구조적으로
     차단.
2. `tests/unit/test_s1a_lean_golden.nim` — 캡처에서 `evidenceId` 제거(와이어 정합).
3. `tests/unit/test_judgment_cas.nim` — fixture·위반 케이스 갱신, G2/G8 extra-field
   거절 확장, **G10 신설**(§4.1).
4. `docs/spec/judgment_cas_payload_measurement_basis.md` §2.3 — 착지 갱신.

## 4. 검증 실측 (드릴 전문)

### 4.1 G10 — payload purity 드릴 (`test_judgment_cas.nim`)

release 빌드(`nim c -d:release -o:build/axjcas_r tests/unit/test_judgment_cas.nim`)
실행, 스위트 전체 PASS. G10 단정 전문(14/14):

```
G10 — payload purity (the exactly-once ledger accepts a re-derived judgment)
  [PASS] the closure collects twice
  [PASS] same closure ⇒ same judgment key
  [PASS] the closure validates clean
  [PASS] both armed flushes write
  [PASS] same closure ⇒ byte-identical payload (flush twice, same bytes)
  [PASS] the flushed bytes re-validate byte-identically
  [PASS] record #1 builds from flush #1
  [PASS] record #1 appends fresh
  [PASS] record #2 builds from flush #2
  [PASS] the same closure's second run is an idempotent no-op (same key + same payload bytes)
  [PASS] same key + different payload bytes is still refused (guard intact)
  [PASS] the changed closure collects
  [PASS] a changed closure derives a different key
  [PASS] a changed closure → jExecuted (the original execution runs)
```

새 불변식의 3축이 실측됐다: (a) 같은 클로저 2회 flush → **바이트 동일**;
(b) 원장 exactly-once에 같은 (키, payload) 2회 append → **idempotent no-op**
(R2 실패가 재현되지 않음); (c) 같은 키 + 다른 바이트 변조 → **계속 거절**
("DIFFERENT payload bytes" — 가드 무력화 없음). 폐쇄 변경(hex40(302)) → 다른 키 →
jExecuted(정당 재실행)도 유지.

### 4.2 s1a golden — release 실커널 드릴

`nim c -d:release -o:build/axs1a_r tests/unit/test_s1a_lean_golden.nim && ./build/axs1a_r`
→ exit=0, 전 단정 PASS(실제 Lean 4.33 커널 판정 포함).
`[SKIPPED] judgment CAS flush — the canonical judgment set (armed: emit; unarmed: pass)`
— 드릴 환경에 evidence path env가 없는 unarmed 모드라 flush 무장 테스트는 skip이
정상이다(armed flush는 G10이 로컬 CAS 백엔드로 전면 실측).

### 4.3 G7 — canonical 게이트

`make verify-contract` → **PASS** (병렬 fan-out 4 subtarget 전부 exit=0:
`[PASS] g2` · `[PASS] g1` · `[PASS] g6g4` · `[PASS] g7`). g7
(`verify-contract-release-e2e-consume`)은 소비 아티팩트 부재로 문서화된 폴백
e2e prove 경로를 실행해 `logs/ax_proof_state.json`을 직접 시드·소비했다.

### 4.4 canonical-digest determinism

`./bin/ax report --canonical-digest` 2회 실행 → 출력 **완전 동일** (diff 공집합):

```
b69cac7dc426d796ad161fb3fd3ce54a369bf01de9714f95c5360aec6648716c
```

## 5. 착지 불변식 (서술)

- **payload 순수성**: s1a judgment payload의 모든 성분(fold, CLE 클로저 순수 성분,
  정준 카운트, verdict, executionEpoch)은 클로저의 순수 함수다. 같은 클로저 ⇒
  같은 키 + 같은 payload 바이트 (G10 b/a 실측).
- **exactly-once 가드 불변**: identity(키)와 payload 불일치 거절은 유지된다 —
  same key + different bytes는 계속 fail-closed다 (G10 d 실측).
- **세대 단조**: 키 스킴·payload 스키마는 v2로 전환됐고, v1 레코드는 불변 이력이다 —
  재검증 충돌·재검증 오인(REUSED 오판) 없이 새 세대로 재실행된다.
- **재유입 차단**: 4주체 payload 검증기는 exact field-set을 강제한다 — 미래의
  런 스코프 성분 추가는 위반으로 거절된다 (G2/G8 확장 실측).

## 버전

| 버전 | 일시 (KST) | 내용 |
|---|---|---|
| v1.0.0 | 2026-10-09 | 원인 실측(원장 카디널리티 20건), 수리 내용, G10/s1a/G7/canonical-digest 드릴 전문 착지 |
