# WP4-g — Canonical Reference Vault Reconciliation (`ax cert reconcile`)

EXPERIMENT_ID: act2-wp4g-cert-reconcile
PARENT: act2-wp4d-symbol-identity (WP4-d complete)
SUBJECT: nim-stew@c75502ceedb5ed2a37b7b5e4744fc71313682859
STATUS: 설계안 (plan only — 구현 대상)

## Question

`src/verification/certificates/` (reference vault) 에 결정론적 재생성 경로가
없는가? 만약 없다면, `ax cert reconcile` CLI 원시(primitive)를 추가하여
reference vault 를 current canonical evidence 로부터 결정론적으로
materialize 하는가?

## 배경 (verified facts)

- reference vault 에 .json 을 쓰는 유일한 코드 경로는
  `reissueReference` (src/verification/cert_promotion.nim:546) — status
  재분류만 수행, sourceHash/irHash 재계산 없음.
- `ax vkd sync` (src/cli/vkd_sync_cli.nim:31) 은 runtime canonical/transient
  에만 기록 (src/cli/axiom_engine.nim:643, cvRuntimeCanonical); orphan step
  은 비파괴적 (vkd_sync_cli.nim:83-93).
- `promoteToCanonical` (cert_promotion.nim:211) 은 data/trusted/certificates/
  (cvRuntimeCanonical) 만 대상.
- `tools/rebuild_assets.nim:42` 의 `writeCertificates` 는 transient만
  대상 (cert_builder.nim:46-47, "DIRECT CANONICAL WRITE FORBIDDEN" guard).
- 문서화된 SOP (docs/ci/self_hosted_runner_ops.md:326-345) 가
  `ax vkd sync` → `git add src/verification/certificates/*.json` 를 명시하지만
  sync 가 reference vault 에 쓰지 않으므로 SOP 는 aspirational.
- concrete blocker: `src/verification/certificates/f3d17f0e...` (topology_dependency.nim::proximityScore,
  certZ3Candidate, stale) — WP4-d 편집 후 module fingerprint 무효화.
  동일 함수의 신규 인증서: `build/certificates/891b6dae...` (sourceHash 현재 일치, z3-verified).
  `reissueReference` 는 certZ3Candidate 상태에서 no-op (statusConsistentWithEvidence 만족).

## 설계 (architect-ratified)

Reference vault = deterministic materialized view of current canonical evidence.
`AUTHORITATIVE` (source, proof obligations, execution evidence, toolchain identity,
solver/kernel results) 로부터 `DERIVED` (reference certificates, VKD baseline,
reports, indexes) 를 생성. 불변식: ReferenceVault == Materialize(CurrentCanonicalEvidence).
결정론적 재생성 가능: Ed25519 signing 은 RFC 8032 에 따라 결정론적
(src/infrastructure/certificate_attestation.nim:239), cert-writing 경로에
wall-clock timestamp 없음, RFC 8785 canonical JSON
(canonicalCertificateString), content-derived 해시만 사용.

### `ax cert reconcile` CLI 원시

- `--check`: 현재 canonical evidence 로부터 expected reference projection 을
  결정론적으로 계산, tracked vault 와 diff, ADDED/UPDATED/REMOVED/UNCHANGED
  보고, drift 시 nonzero exit, 파일 절대 변경하지 않음.
- `--apply`: 동일 알고리즘 + atomic materialization
  (1. evidence 수집 2. evidence 검증 3. expected vault 계산 4. diff 계산
  5. temporary vault 작성 6. fsync/validate 7. atomic replace
  8. re-read 9. digest equality 확인 → 성공 시에만 완료).

### Promotion predicate (reference vault 진입 필수)

sourceHash == currentSourceHash AND evidence 구조적 유효 AND
proof/evidence provenance present AND solver/kernel invocation이 claimed status에 유효 AND
toolchain identity 기록 AND certificate schema canonical (RFC 8785) AND
obligation이 현재 proof universe에 속해 있음.

### Removal semantics

"human이 삭제할 대상을 결정"하는 것이 아닌, algorithm이 현재 canonical evidence
projection 하에서 존재할 수 없는 tracked artifact만 제거 (결정론적 materialization,
파괴적 정리가 아님 — ADR-0012의 vkd sync non-destructive 원칙과 일관).

### 재사용 building blocks (중복 금지)

- `writeCertificates` (src/verification/cert_builder.nim:43, destructiveClean param)
- `cleanOrphanCertificates` (src/verification/cert_writer.nim:588 — non-expected-irHash
  *.json 제거, isProvenanceProtected 제외; f3d17f0e는 보호되지 않음)
- `setPromotionActive`/`clearPromotionActive` (cert_promotion.nim:131)
- `resolveCertificate(cvCanonicalRead)` (cert_vault_role.nim:23)
- CLI wiring: src/cli/cert_cli.nim (기존 reissue-reference subcommand 패턴 따름)

### stale_cert_gate UX follow-up

stale 감지 시 "run 'ax vkd sync'" 메시지 대신
"run 'ax cert reconcile --apply'" + canonical replacement hash 를 출력
(gate는 절대 mutate하지 않음, 결정론적 remediation을 가리킴).

### CI 역할

push CI: `ax cert reconcile --check` (checker); local dev: `--apply`
(generator/checker 분리, VKD SOP과 동일 원칙).

### Regression tests

(a) reconcile --check on clean vault → exit 0; (b) stale-cert fixture →
--check reports REMOVE+ADD, exit nonzero, files untouched; (c) --apply →
gate-green, byte-deterministic (apply twice → identical digests);
(d) no-op on already-reconciled vault.

### Immediate unblock step

현재 blocked commit을 해제: `ax cert reconcile --apply` 로 proximityScore
경우 처리 (ADD 891b6daee, REMOVE f3d17f0e), stale_cert_gate 재실행,
그 후 staged WP3–WP4d commit을 reconcile primitive 포함 동일 PR로 진행.

### Out of scope

- fingerprint granularity change (module-level → function-level): 현재 module-level
  정책 유지; 후속 WP에서만 정밀도 조정 가능 (불변식 "certificate valid iff
  certificate input identity == current canonical input identity" 유지).
- C0.4 legacy amnesty: 없음.
- `--no-verify`: 없음.
- manual rm/cp of tracked certs: FORBIDDEN.
- `ax vkd sync` 가 reference vault 를 쓰도록 변경: 없음 (VKD는 projection/metric
  layer로 유지).

### Phases

Phase 0: spec amendment (docs/spec/cert_lifecycle_contracts.md §7 — 별도 agent
담당, 본 WP 에서는 참조만). Phase 1: reconcile core (--check). Phase 2: --apply
atomic materialization. Phase 3: gate UX + CI wiring. Phase 4: blocked Act 2
commit unblock via reconcile. Phase 5: regression suite.

## 수용 기준 (Acceptance Criteria)

1. `ax cert reconcile --check` 가 reference vault drift 를 ADDED/UPDATED/REMOVED/UNCHANGED
   로 보고, drift 시 exit nonzero, 파일 미변경.
2. `ax cert reconcile --apply` 가 atomic materialization 완료 후 digest equality
   검증 성공.
3. stale_cert_gate 가 stale cert 탐지 시 "ax cert reconcile --apply" + replacement
   hash 를 remediation 메시지로 출력.
4. CI push 단계에서 `--check` 만 실행; `--apply` 는 local dev 전용.
5. proximityScore stale case (--apply) 후 stale_cert_gate 통과.
6. regression suite (a)–(d) 전부 PASS.
7. reference vault 의 모든 cert 이 promotion predicate 를 통과.

## Non-Conclusions

- 이 WP 는 C0.4 reclassification 정책 자체를 검증하지 않는다.
- fingerprint granularity (module-level)를 변경하지 않는다.
- `ax vkd sync` 가 reference vault 에 쓰도록 만들지 않는다.
- `reissueReference` 의 status reclassification semantics 를 변경하지 않는다.
- "no failure observed" 가 곧 "proof" 가 아님 (vacuity 규칙 §6 유지).

## Evidence

- src/verification/cert_promotion.nim (reissueReference, promoteToCanonical)
- src/cli/vkd_sync_cli.nim (sync prove + orphan step)
- src/cli/axiom_engine.nim (cvRuntimeCanonical 사용)
- src/verification/cert_builder.nim (writeCertificates, DIRECT CANONICAL WRITE FORBIDDEN guard)
- src/verification/cert_writer.nim (cleanOrphanCertificates)
- src/core/trusted/provenance_guard.nim (isProvenanceProtected 판정)
- src/core/identity/axiom_identity.nim (computeStableSourceFingerprint)
- tools/stale_cert_gate.nim (stale remediation 메시지)
- src/cli/cert_cli.nim (reissue-reference subcommand 패턴)
- docs/ci/self_hosted_runner_ops.md:326-345 (aspirational SOP)
- src/verification/certificates/f3d17f0e... (stale cert fixture)
- build/certificates/891b6dae... (fresh replacement cert)

## Non-Claim

이 WP 는 reference vault 의 결정론적 재생성 경로를 설계하고 구현하는 것이
목적이다. C0.4 reclassification 정책의 정당성, fingerprint granularity 변경의
필요성, 또는 `ax vkd sync` 의 projection 역할을 변경하는 것은 다루지 않는다.

## Next

Phase 1 (--check core) 구현 시작. Phase 0 spec amendment 은 별도 agent 에게
위임. Blocked commit unblock (Phase 4) 은 --apply 구현 완료 후 즉시 실행.
