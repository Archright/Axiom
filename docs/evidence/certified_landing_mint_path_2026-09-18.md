# Certified landing — pre-merge certificate mint path evidence (2026-09-18)

## Scope

PR #116이 복원한 canonical authority(bind/continuity/accept)의 첫 landing
H=`bd26bdbb7605cba4344fce4e3802028cdecbc9d3`은 continuity에서 fail-closed로
정지했다(ledger에 headSha==parent2인 cert 부재). 본 문서는 그 원인과
합법적 해소 경로(ADR-0021 §D9 operator procedure)의 실행 근거를 기록한다.

## 관측 사실 (run/SHA 단위, 모두 재관측 가능)

1. canonical run `35241535571` (event=push, headSha=bd26bdbb…):
   bind=success, continuity=failure, accept=skipped.
2. continuity 실패 지점: `.github/workflows/merge_continuity.yml:86-164` —
   ledger `refs/heads/axiom/certificates` 역순 ≤20 append 탐색에서
   `headSha==parent2(62222d3f3…)` 미발견 → fail-closed.
3. ledger tip append `e97bd597…`의 cert blob `59399cb5….json`:
   `headSha=524811848…` (PR #102 시대, 과거 policyDigest).
4. 현재 main의 `policyDigest=b613e035…`(merge_admission.json)은
   기존 어떤 ledger cert와도 불일치 — 사전 제작 cert는 영구 무용.
   continuity predicate 7-8(continuity_check.nim:164-167)이 정책/스코프
   digest까지 exact 비교하므로 fresh mint가 유일 경로.

## 권한 구조 (핵심 질문에 대한 답)

- 과거 tip cert(524811848) = `github-actions[bot]`, archived `auto_merge.yml`
  (유일 contents:write 홀더, ADR-0022 §D5 TrustedWriterSet)에서 post-verdict
  `ax cert ledger-append`. attest.yml = mint-only(contents:read).
- 이전 7개 append = 운영자(wintrover)의 로컬 `ax cert ledger-append`
  (부트스트랩 역사).
- clean-slate 커밋 `fa069d610`이 attest/verify-candidate/auto_merge 3개
  워크플로를 삭제 → CI 자동 mint 체인 부재.
- 현재 살아있는 경로는 ADR-0021 §D9 operator procedure뿐:
  `ax cert subject-register → attest(Ed25519, 결정론 seed key,
  publicKeyId=sha256:9a17da…) → ledger-append(GitHub REST git-data,
  FF PATCH force=false)`. 커널 재실행 stage (a)~(g)을 통과해야 mint됨
  (attestation_orchestrator.nim:419-436).

## 이 Slice의 역할

- candidate PR의 H²에 대해 admission PASS 후, merge 이전에
  D9 operator가 `(baseSha=H¹, headSha=H²)` 쌍바인딩 cert를 fresh mint하고
  ledger에 append한다.
- 이후 native MERGE → push(main) → canonical bind → continuity → accept의
  전체 연쇄가 관측되면 DEBT#462(개방)의 종결 상태가 된다.

## 추적 부채

- DEBT#462 (open): canonical landing이 ledger cert 발행과 인과 결합되지 않은
  공백. 본 문서는 그 해소 관측의 기록지다.
- IR obligation-lowering 회귀(`4b55dec1e` 이후 body-binding 결손,
  safeSpeedupRatioCore/proximityScore psFail)는 별도 Slice 대상 — 본 문서는
  기계적으로 비치명임만 기록(PR #114 통과 run 35128877634에서 동일 패턴
  success 확인).
