# rust lane N1 팔로우업 — in-subset 타깃 선언 identity(signatureHash) 변조 대조 관측 (2026-11-04)

> **Status**: Observation evidence record — 문서·증거 산출물만 (`src/` 무수정, 제품 코드 무변경, main worktree 무수정; 모든 실행은 전용 worktree `/tmp/n1_obs_wt`에서 수행; baseline lock·기존 state_*/vault_*/d1–d5 산출물 무수정 — 변조는 state 사본에서만)
> **Created**: 2026-11-04
> **Written at**: branch `work/n1-identity-mismatch-2026-11-04` (worktree `/tmp/n1_obs_wt`), branch base = main `2f9c21693b401fb040991561b820718b9be0046d` (PR #1249 merge)
> **Governing docs**: [serde_json_c7_adjudication_closure_2026-11-03.md](serde_json_c7_adjudication_closure_2026-11-03.md) §5.3 (N1 정직 기록 + 팔로우업 노트 — 본 문서가 그 관측 기반 회답) · [u64-add FREEZE](../../experiments/u64-add-2026-11-02/FREEZE.md) + [u64-add OBSERVATION](../../experiments/u64-add-2026-11-02/OBSERVATION.md) (명령 형식·state 조립·인증서 결정론 선례) · [u64-scalar OBSERVATION](../../experiments/u64-scalar-2026-11-02/OBSERVATION.md) (gitignored `proofs/.lake` provisioning 선례) · `data/verification_scope.lock` (baseline — 무수정, cp 사본만 사용)
> **원칙**: 기계 출력과 오류 문자열은 원문 그대로 인용한다(재작성·요약·번역 없음). 이 문서는 관찰을 기록하며 판정 대상 함수(`u64_add`) 또는 프로젝트에 대한 어떤 참·거짓 주장도 하지 않는다. 역사 문서(C7 폐쇄·FREEZE·ACCEPTANCE)는 무수정 — 참조만 한다.

7-field identity (FREEZE.md §1 형식 준용 — 값은 본 문서 정체성):

- PROJECT_UNDER_TEST: `axiom_u64_probe` (in-repo Rust fixture crate, `tests/fixtures/rust/axiom_u64_probe/`) — N1 팔로우업: **인증 부분집합 내 타깃 `axiom_u64_probe::u64_add`**의 state lock 선언 `signatureHash` 말미 1 hex 변조 시 §6c identity 측정의 명시적 mismatch 거부 발화 여부 대조 관측 (B-run 기준 vs M-run 변조)
- REVISION: fixture 6파일 find-매니페스트 sha256 `6669fc5a668a16e7266010239abf17757aac2712d33aace300e954f42132b8c6` (`src/lib.rs` `5352659d…`, `axiom_u64_probe.llbc` `0d5bb37e…`, `Cargo.lock` `ebeac7d4…` — u64-add FREEZE §1 지문과 동일; 매 런 pre==post, §5.5)
- AXIOM_REVISION: `2f9c21693b401fb040991561b820718b9be0046d` (canonical main = PR #1249 merge; 실행·빌드 브랜치 `work/n1-identity-mismatch-2026-11-04`의 base이자 실행 시점 HEAD)
- CONFIG: `AXIOM_STATE_DIR`/`AXIOM_PROVE_VAULT_DIR` per run (state_b/state_m + vault_b/vault_m); state lock은 baseline의 `cp` 사본 (repo 파일 무수정 — 변조는 state 사본에서만); `AXIOM_CHARON_BIN=<user-home>/.cargo/bin/charon`; `CARGO_NET_OFFLINE=true`; `GITHUB_TOKEN` procured via `gh auth token` (native client, §2.4 — `gh_env.txt` 미접촉); gitignored `proofs/.lake` provisioning via 문서화된 `lake build` (u64-scalar cold 선례); 빌드 스탬프(`src/generated/build_metadata.json`) HEAD 복원 후 porcelain clean 진입 (u64 quirk 선례)
- TOOLCHAIN_ID: Nim 2.2.10; charon **0.1.281** (`798016509139eb51f0d764645f76d068d34ba5f6`) — 양 런 stderr 1행째 pinned==measured 일치(`ok=true`); rustc 1.95.0; Lean 4.33.0 (`lake build` 21 jobs); Z3 4.13.3 (인증서 journal solverVersion)
- SCOPE: B-run(기준) + M-run(변조) 2런 대조 + B-run 최초 시도(proofs 미빌드) 정직 기록 + 선언 `signatureHash`·§6c 강제점 소스 인용(위치 기록 — 판정 아님). **범위 밖**: 제품 판정, `u64_add` 의미 주장, debt 등록, 게이트·정책 변경, serde_json 계열 재실행, 선언-측정 합의 판정의 신규 도입 — 어느 것도 수행하지 않았다
- EXPERIMENT_ID: n1-identity-mismatch-2026-11-04

---

## 1. Question

이 문서가 답하는 질문:

1. C7 §5.3 N1 팔로우업 노트의 질문: producer 입력계약 거부가 발화하지 않는 **in-subset 타깃 계열**에서, state lock의 선언 `signatureHash`를 변조하면 §6c identity 측정의 **명시적 mismatch 거부**(exit·status·reason 원문)가 기계적으로 발화하는가?
2. 발화하지 않는다면, 변조는 어디에 기계적으로 결속되는가 — C7 N1에서 성립한 "변조 결속" 절반은 이 계열에서도 성립하는가?
3. 선언 `signatureHash`의 소비처(강제점)는 소스 어디인가 — 불발화의 구조적 원인을 소스 인용으로 확정할 수 있는가?

## 2. Context

- C7 §5.3 N1(serde_json, 2026-11-03): 변조된 선언 `signatureHash`가 §6c identity 합의 판정에 **도달하지 못했다** — 현 엔진 상태에서 producer 입력계약 거부가 §6c identity 측정 단계보다 먼저 발화. 팔로우업 노트 원문: "명시적 합의-실패 거부 클래스의 관측은 다른 실행 계열(producer 거부가 없는 in-subset 타깃)에서만 가능하다".
- 타깃: `axiom_u64_probe::u64_add` — baseline `data/verification_scope.lock` (rust_targets 6, vksRust 6, sha256 `140fd7004e088aeda054801ab797ef0d036d4901f33c51adb3cf36c348012788`) 등재, 선언 `signatureHash` `717a7d0fa33e1537a5dc5dc59ab439ce85b711e894f03658f34255b16bceec67`. u64-add 선례(2026-11-02, MERGE_SHA `ed9cab36d`)에서 `verified` + 인증서 `8fd2dae5…87` 판정을 받은 동일 타깃이다 — producer·입력계약이 통과하는 계열의 대표로 선정했다(브리프 권장 대상 준용).
- §6c v2: 프로덕션 타임 identity sidecar (`skreport-identity.json`, `<state>/.axiom/rust-lane/<hunk>/`) + payload의 `identityBundleDigest` — payload↔sidecar 결속 구조(C7 §5.3이 다룬 장치와 동일).

## 3. Scope

- **범위 안**: (a) `make build`(worktree bin/ax) + `bin/ax --check-provenance`, (b) B-run(baseline lock cp 사본, §4.3 명령형)과 M-run(선언값 말미 1 hex 변조 사본, §4.4), (c) 매 런 무결성 축(lock in==out, 서브젝트 find-매니페스트 pre==post, trajectory, vault, sidecar), (d) 변조 diff 원문 보존, (e) B-run 최초 시도(§4.2)의 정직 기록, (f) 강제점 소스 인용.
- **범위 밖**: §1 7-field identity SCOPE 참조. 발견 ≠ 권한 — 범위 밖 발견은 §7.1-5의 팔로우업 노트로만 기록한다.

## 4. Procedure

### 4.1 빌드·사전 게이트 (worktree `/tmp/n1_obs_wt`, HEAD `2f9c21693`)

- `make build` → exit 0 (62.7s), `bin/ax` 28,299,000 B, sha256 `527d2dd3fe0fbf9a58febec57a1c378caab8cecebb7134c50718156fec2b8ca8` (git 비추적 로컬 산출물 — 기록 전용; d4 §4.1/d5 §L.2 선례대로 바이트 재현성 지표 아님)
- `bin/ax --check-provenance` → `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (-7275307651492060493)`, exit 0 (d4/d5와 동일 BuildSourceHash)
- 빌드가 트래킹된 `src/generated/build_metadata.json`을 오염 → HEAD 복원(u64-scalar ③ run2 패턴의 선제 적용) 후 porcelain clean — B/M 양 런 모두 clean 상태에서 진입
- 빌드 워닝(기존 상태 관측, d5 §L.6-3 동일): `[decision-binding] WARN: 50 function(s) missing {.axiomDecision.} pragma — escalation threshold 30 days not yet reached`

### 4.2 B-run 최초 시도 (proofs/.lake 미빌드) — 정직 기록

worktree의 `proofs/.lake`는 build 결손이었다(gitignored — u64-scalar cold acceptance가 "gitignored `proofs/.lake` provisioning"을 문서화된 실행 환경의 일부로 규정). 이 상태로 §4.3과 동일 명령을 실행:

- **exit code: 0**; stdout 0바이트; stderr 3행; skReport `targets[0].status="unknown"`, reason 원문:

```
extraction: reference extractor rejected the wire (unsupported construct or malformed bytes): IR/RustReferenceExtractor.lean:74:0: error: unknown module prefix 'IR'

No directory 'IR' or file 'IR.olean' in the search path entries:
/tmp/n1_obs_wt/proofs/.lake/build/lib/lean
<user-home>/.elan/toolchains/leanprover--lean4---v4.33.0/lib/lean
<user-home>/.elan/toolchains/leanprover--lean4---v4.33.0/lib/lean
```

- 분류: **환경 결손(프로비전 미완)** — 판정 대상 현상(선언 identity 변조)이 아니다. fail-closed 관측 자체는 정상 작동이며(추출기 거부 → unknown), C7 §5.1a "fix and re-run, recorded" 선례를 적용한다: 최초 시도 산출물 전량을 `runs/b_attempt1_proofs_not_built`·`state_b_attempt1_proofs_not_built`·`vault_b_attempt1_proofs_not_built`로 보존하고, 문서화된 명령 `lake build`(21 jobs, exit 0 — `IR/AxiomIRExpr.olean` 등 생성 확인)로 프로비전한 뒤 **신선 state_b/vault_b로 재실행**(§4.3)했다. `IR/RustReferenceExtractor.lean:74`의 `import IR.AxiomIRExpr`는 검색경로에 `IR/` 패키지가 존재하면 resolve된다(빌드 후 관측).

### 4.3 B-run 명령형 (기준)

- 상태 조립: `cp data/verification_scope.lock state_b/data/verification_scope.lock` (8,012 B, sha256 `140fd700…`, rust_targets 6, vksRust 6 — 선언==계산 일치, C7 §5.1a형 INVALID_INPUT 없음). 선언값 확인: `u64_add` `signatureHash` = `717a7d0fa33e1537a5dc5dc59ab439ce85b711e894f03658f34255b16bceec67` (baseline 전문과 일치)
- 서브젝트 find-매니페스트 pre 기록 후 실행:

```
AXIOM_STATE_DIR=$PWD/state_b AXIOM_PROVE_VAULT_DIR=$PWD/vault_b \
AXIOM_CHARON_BIN=<user-home>/.cargo/bin/charon CARGO_NET_OFFLINE=true \
GITHUB_TOKEN=$(gh auth token) \
bin/ax prove --project tests/fixtures/rust/axiom_u64_probe --target 'axiom_u64_probe::u64_add' \
> runs/b/stdout.txt 2> runs/b/stderr.txt   (exit·wall 별도 기록)
```

- 실행 후: 매니페스트 post, lock out 해시(in==out 검증), trajectory(`state_b/logs/ax_prove_trajectory.jsonl`) 확보, `phase:"skReport"` 이벤트에서 `jq -S .extra`로 payload 추출.

### 4.4 M-run 명령형 (변조)

- state_m 조립: baseline 사본 생성 후 `u64_add` 항목의 `signatureHash` **말미 1 hex 치환** (`…bceec67` → `…bceec66`; 치환 규모는 C7 N1과 동일한 말미 1 hex). 변조 전후 원문을 `runs/m/mutation_before.txt`·`mutation_after.txt`에 보존. 변조 증명: B lock과의 `jq -S` canonical diff가 정확히 1행 1문자(§5.3). 변조 후 lock sha256 `25e71b5a604958a2123701e6e81ec3835c7c4fd1e15a8f4f114b621ea3cdcd8c` — 여전히 유효 64-hex(형식 검증 통과 형태). vault_m·runs/m 신선.
- §4.3과 **동일 명령·동일 env·동일 인자**로 실행 → §6c identity 측정의 기계 결과(exit·status·reason) 원문 관측.

### 4.5 Cargo.lock 프로토콜 판단 (브리프 §3 항목)

serde_json §8 잠금 프로토콜(임시 배치 → in==out → 제거 → 매니페스트 복귀)은 **미적용**으로 판단했다. 근거: 서브젝트 fixture의 `Cargo.lock`은 repo 추적 파일(`ebeac7d4…`, 의존성 0건)로 상시 존재하며 임시 배치 대상이 아니다 — u64 선례(③ §4·① 선례)도 임시 배치 없이 서브젝트 불변을 find-매니페스트 pre==post로 입증했다. 본 실험도 동일하다(§5.5).

## 5. Result

### 5.1 B-run 관측 (baseline lock cp 사본, 2026-11-04)

- **exit code: 0**; wall 22.694941995s
- **stdout: 0바이트**(빈 파일, sha256 `e3b0c442…` 공파일 해시). 3행 lane 출력은 본 실험의 분리 스트림 캡처에서 **stderr**로 관측됐다(선례 d1–d5는 `2>&1` 결합 캡처라 스트림 귀속을 구분하지 않았다 — §8-2). stderr 1,683 B, sha256 `b8b49d8a3ef6da35291af53c29699698893f7324cab6d49b163c16290a06d479` — `[INFO] ledger_side_ref` 7행(live transport; `refs/heads/axiom/evidence-cas` 대상) + lane 4행:

```
[AXIOM][rust-lane] charon pinned='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' measured='0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)' ok=true
[AXIOM][rust-lane] ledger transport armed (live); repo=Archright/Axiom
[AXIOM][rust-lane] verified: axiom_u64_probe::u64_add → /tmp/n1_obs_wt/experiments/n1-identity-mismatch-2026-11-04/vault_b/8fd2dae5215d11192e40e753a5e917bc4c8504abfedf2328f98fa409f218fc87.json
[AXIOM][rust-lane] done: verified=1/1 failed=0 unknown=0 error=0
```

- **B-run `targets[0]` 원문** (skReport payload 전문 보존: `runs/b/skreport_payload.json`, sha256 `f445024a131ad878275c16aa38da3b3bca22af432b29ba6c1795762d21d0ed3b`; schemaVersion `axiom.report.v1`, subjectLane `rust`, charon ok=true pinned==measured, summary `{"verified":1,"failedCount":0,"timeoutCount":0,"verifiedRatio":1.0,"statusCounts":{"verified":1,"failed":0,"unknown":0,"error":0}}`, `identityBundleDigest` `becdcfeb3b0d26c651ee9158eb4d6298c4aa4ea71c98f57b475c76face0c108f`):

```
name:     axiom_u64_probe::u64_add
status:   verified
reason:   (빈 문자열)
certPath: /tmp/n1_obs_wt/experiments/n1-identity-mismatch-2026-11-04/vault_b/8fd2dae5215d11192e40e753a5e917bc4c8504abfedf2328f98fa409f218fc87.json
irHash:   8fd2dae5215d11192e40e753a5e917bc4c8504abfedf2328f98fa409f218fc87
```

- **인증서** (`runs/b/certificate_8fd2dae5.json`, sha256 `4ca21d36fc9262355db149320a26a9e0b4b0700e6545f57c7456f08ed9f3beb4`): `axiom.certificate.v3`, status `certLeanVerified`, kernel `true`, reason `uap-lean-verified`, irHash `8fd2dae5…87` — **u64-add 선례 인증서와 동일 irHash**(내용 주소화; u64-scalar §3-c "증명 내용의 정체성이 독립 실행에서 안정적으로 재현"의 재관측). vault_b 2파일(인증서 + journal `755eac74…`).
- **§6c sidecar** (`state_b/.axiom/rust-lane/4c16968c0267efe1/skreport-identity.json`, sha256 `bfa86e248c7ecbf5efd0ab59bca5f32b70b1a777a53df7886e804469ce03af65`): `binding.payloadSha256` `85287aa48d80b8b479b279c908aefbec45964ec29d48ad1c0dc2d5158ec55fff`, `scope.rustTargetsSha256` `140fd700…`(=본 런 state lock 파일 sha256), `claim{symbol: axiom_u64_probe::u64_add, specRef: …#axiom_u64_probe::u64_add, postSha256: b90a6aa2b56e48bfe3e713318585b82fa9c57e91aff224aff636ca7f3e3cca67}`, `subject{commit: 2f9c2169…, moduleSha256: 5352659d…, sourceFingerprint: e916e7ad…}`, `toolchain{cargoLockSha256: ebeac7d4…, charon: 0.1.281 (79801650…), rustc: 1.95.0, nim: Nim 2.2.10}`, `rejection: null`

### 5.2 M-run 관측 (선언 signatureHash 말미 변조) — 정직 기록

- 변조: `717a7d0fa33e1537a5dc5dc59ab439ce85b711e894f03658f34255b16bceec67` → 말미 `7`→`6` (변조 후 `…bceec66`). 변조 lock sha256 `25e71b5a…`.
- 기계 결과: **exit code: 0** (wall 22.666244979s) — **명시적 identity-mismatch 거부 라인은 관측되지 않았다.** stdout 0바이트; stderr 1,682 B, sha256 `68bbaf9d9a0b03684f2cfa1066771292a0d00c2d50a808012f1fda019e82de68` (구조는 B-run과 동일 — ledger INFO 행의 elapsed_ms·certPath 헝크만 변동). lane 행 원문:

```
[AXIOM][rust-lane] verified: axiom_u64_probe::u64_add → /tmp/n1_obs_wt/experiments/n1-identity-mismatch-2026-11-04/vault_m/8fd2dae5215d11192e40e753a5e917bc4c8504abfedf2328f98fa409f218fc87.json
[AXIOM][rust-lane] done: verified=1/1 failed=0 unknown=0 error=0
```

- **M-run `targets[0]`**: `status: verified`, `reason: (빈 문자열)`, `irHash: 8fd2dae5…87` (B-run과 동일), `certPath: …/vault_m/8fd2dae5…87.json` — **인증서 발행됨** (vault_m 2파일; 인증서 sha256 `af8dad3b595bba0c9c6a4e361ac9c4e6a25f523c483de786cbb46207f72fe5aa`). payload sha256 `b38331b64f972120465878be4b2ebf90a08b92d2436ffa118b8523110d6722a1`, summary 카운트는 B-run과 동일(verified 1, ratio 1.0), `identityBundleDigest` `3d380c4276023aff969665471d1982569282b55baf465f16a90b056134fa0aed`.
- **정직 기록 (예측과의 불일치)**: 브리프 기대("명시적 identity-mismatch 거부")는 **발화하지 않았다** — 변조된 선언 `signatureHash`로도 런은 `verified` + 인증서 발행에 도달했다. 이 실측 그 자체가 N1 팔로우업의 회답이다(§7.1).

### 5.3 변조 diff 원문 (B lock ↔ M lock, `jq -S` canonical — 유일 차이)

```diff
--- state_b/data/verification_scope.lock (jq -S)
+++ state_m/data/verification_scope.lock (jq -S)
@@ -128 @@
-      "signatureHash": "717a7d0fa33e1537a5dc5dc59ab439ce85b711e894f03658f34255b16bceec67",
+      "signatureHash": "717a7d0fa33e1537a5dc5dc59ab439ce85b711e894f03658f34255b16bceec66",
```

(diff 원문 헝크 `128c128` + 1대1 행 — 커밋 산출물 `runs/m/lock_canonical_diff.txt`)

### 5.4 변조의 기계 결속 — §6c v2 (C7 §5.3과 동일 구조의 sidecar 2필드 차이)

```diff
--- state_b/.axiom/rust-lane/4c16968c0267efe1/skreport-identity.json (jq -S)
+++ state_m/.axiom/rust-lane/4c16968c0267efe1/skreport-identity.json (jq -S)
-    "payloadSha256": "85287aa48d80b8b479b279c908aefbec45964ec29d48ad1c0dc2d5158ec55fff"
+    "payloadSha256": "65881e35d0bc066964d615b2cd187be14b0372059344ba2d17c4326480fa4250"
-      "rustTargetsSha256": "140fd7004e088aeda054801ab797ef0d036d4901f33c51adb3cf36c348012788"
+      "rustTargetsSha256": "25e71b5a604958a2123701e6e81ec3835c7c4fd1e15a8f4f114b621ea3cdcd8c"
```

(`rustTargetsSha256`은 각 런의 state lock 파일 sha256과 동일 — B `140fd700…`, M `25e71b5a…`. skReport payload의 차이는 `identityBundleDigest` `becdcfeb…` → `3d380c42…`와 certPath 헝크뿐이다.) `claim.postSha256` `b90a6aa2…`·`subject`·`toolchain`은 **전필드 동일** — 변조된 선언값은 측정된 claim identity에 어떤 반영도 없었다.

- **인증서 B↔M 대조**: 상이 필드는 실행 정체성 5종뿐 — `journalRef`, `signature`, `canonicalKaa.executionIdentity`, `evidenceId`, `executionContractDigest` (u64-scalar §3-c "실행 우연" 필드군). 의미 코어 동일: irHash `8fd2dae5…87`, `receiptArtifactIdentity` `60f38e61…`, `receiptExecutionContract` `c99e5bed…`, `receiptTheoremIdentity` `u64_add_post`, `observedAxiomSet` `[Quot.sound, propext]`. **변조 전후 선언값(`…c67`/`…c66`)은 어느 인증서에도 미포함**(grep 0건) — 인증서는 선언 `signatureHash`와 무관하게 발행됐다.

### 5.5 무결성 축 (B/M 공통 성립)

| 축 | B-run | M-run |
|---|---|---|
| state lock in==out | `140fd700…` | `25e71b5a…` (변조 상태 보존 — 실행 후 재해시 동일, in==out) |
| 서브젝트 매니페스트 pre==post | `6669fc5a…` (6파일) | `6669fc5a…` (동일) |
| trajectory (`logs/ax_prove_trajectory.jsonl`, 1행) | `159094a9…` | `99a8d34a…` |
| skReport payload | `f445024a…` | `b38331b6…` |
| vault | 2파일 (인증서+journal) | 2파일 (인증서+journal; journal `755eac74…`은 양측 동일 파일명·동일 sha256 `095ebebe…` — claim 내용 주소화) |
| porcelain (런 진입 시) | clean (스탬프 복원 후) | clean |

- baseline lock 본체: main worktree와 worktree 양측 sha256 `140fd700…` 동일, `git diff -- data/verification_scope.lock` 공집합 — **무수정 입증** (변조는 state_m 사본에서만).
- 최초 시도(attempt-1)의 무결성 축: lock in==out, 매니페스트 pre==post도 성립했다(§4.2 원문 보존).

## 6. Evidence

커밋 산출물 (d1–d5 선례 준용 — runs 3파일 + state data/logs 2파일; 인증서 2건과 변조 증명 3종은 u64-add artifact 선례로 추가 — §8-4):

| 파일 | sha256 |
|---|---|
| `runs/b/skreport_payload.json` | `f445024a131ad878275c16aa38da3b3bca22af432b29ba6c1795762d21d0ed3b` |
| `runs/b/subject_manifest_pre.sha256` | `6669fc5a668a16e7266010239abf17757aac2712d33aace300e954f42132b8c6` |
| `runs/b/subject_manifest_post.sha256` | `6669fc5a668a16e7266010239abf17757aac2712d33aace300e954f42132b8c6` |
| `runs/b/certificate_8fd2dae5.json` | `4ca21d36fc9262355db149320a26a9e0b4b0700e6545f57c7456f08ed9f3beb4` |
| `runs/m/skreport_payload.json` | `b38331b64f972120465878be4b2ebf90a08b92d2436ffa118b8523110d6722a1` |
| `runs/m/subject_manifest_pre.sha256` | `6669fc5a668a16e7266010239abf17757aac2712d33aace300e954f42132b8c6` |
| `runs/m/subject_manifest_post.sha256` | `6669fc5a668a16e7266010239abf17757aac2712d33aace300e954f42132b8c6` |
| `runs/m/certificate_8fd2dae5.json` | `af8dad3b595bba0c9c6a4e361ac9c4e6a25f523c483de786cbb46207f72fe5aa` |
| `runs/m/mutation_before.txt` | `0ce0f3a0b026fa38a3b5e1ec00fbfb145dad5fff89468569eca99c5ccd1868b9` |
| `runs/m/mutation_after.txt` | `a66836f6b5bd08224532bae7c3ffed2299014e2500961d1b075219e006d36339` |
| `runs/m/lock_canonical_diff.txt` | `817f88a3f40cc40bf6a46f2ab55ca2ab49f705475daac01ab0e15221ab97f212` |
| `state_b/data/verification_scope.lock` (8,012 B) | `140fd7004e088aeda054801ab797ef0d036d4901f33c51adb3cf36c348012788` |
| `state_b/logs/ax_prove_trajectory.jsonl` (1행) | `159094a94e9d1b030e9e8b5f42c2f6f5a6b6af0ee4d4276134998e2d1a28d5f2` |
| `state_m/data/verification_scope.lock` (8,012 B) | `25e71b5a604958a2123701e6e81ec3835c7c4fd1e15a8f4f114b621ea3cdcd8c` |
| `state_m/logs/ax_prove_trajectory.jsonl` (1행) | `99a8d34adbba307266251bfcae90246ef18ce6a0e180eccc653d578a59568f0c` |

비커밋 디스크 관측치 (d1 관례 — stdout·stderr·exit·wall·sidecar·vault 내부는 디스크에만 존재; 값은 본 문서가 정본 기록):

| 항목 | 값 |
|---|---|
| `runs/b/stdout.txt` | 0 B, sha256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` (공파일) |
| `runs/b/stderr.txt` (1,683 B) | `b8b49d8a3ef6da35291af53c29699698893f7324cab6d49b163c16290a06d479` |
| `runs/b/{exit_code.txt, wall_seconds.txt}` | 0 / 22.694941995s |
| `runs/m/stdout.txt` | 0 B, sha256 `e3b0c442…` (공파일) |
| `runs/m/stderr.txt` (1,682 B) | `68bbaf9d9a0b03684f2cfa1066771292a0d00c2d50a808012f1fda019e82de68` |
| `runs/m/{exit_code.txt, wall_seconds.txt}` | 0 / 22.666244979s |
| sidecar 2건 (`state_{b,m}/.axiom/rust-lane/4c16968c0267efe1/skreport-identity.json`) | `bfa86e248c7ecbf5efd0ab59bca5f32b70b1a777a53df7886e804469ce03af65` / `2e49b4d6a69d4068799ccaf15b4fbb484d1fb0ec221504344e2f08449596e2cf` |
| vault_b 인증서 / journal | `4ca21d36…` / `095ebebe42332d85ba6af6634673f00a6832a69e6104b28953ebbf374bcc479e` |
| vault_m 인증서 / journal | `af8dad3b…` / `095ebebe42332d85ba6af6634673f00a6832a69e6104b28953ebbf374bcc479e` (journal은 B와 동일 sha256) |
| attempt-1 전체 (`runs/state/vault_*_attempt1_proofs_not_built`) | §4.2 원문 보존 (exit 0, unknown, reason 원문 인용) |

## 7. Classification

### 7.1 C7 §5.3 N1 팔로우업 노트에 대한 관측 기반 회답 — 명시적 거부 클래스: **불성립**

1. **질의 재현**: producer 거부가 없는 in-subset 타깃(`u64_add` — producer·입력계약·extraction agreement 모두 통과 계열)에서 선언 `signatureHash` 말미 1 hex 변조 → 동일 명령 재실행. C7 §5.3이 도달하지 못했다고 기록한 지점 이후의 거동을 이번에는 직접 관측했다.
2. **관측**: exit 0 + `verified` 1/1 + **인증서 발행** — 명시적 mismatch 거부 없음(§5.2). C7 §5.3 팔로우업 노트의 함의("in-subset 계열에서 명시적 합의-실패 거부가 관측될 것")는 **기각됐다**. 불발화의 원인은 선발(producer 거부)이 아니라, **prove 경로에 선언 `signatureHash`의 합의 판정 자체가 존재하지 않기 때문**이다.
3. **구조적 원인 (강제점 소스 인용 — 현재 `2f9c21693` 소스, 위치 기록이지 판정 아님)**:
   - 전 저장소 검색: 선언 `signatureHash`의 `src/` 소비처는 `src/core/trusted/axiom_pragmas_procs.nim`의 **형식 검증**뿐이다 — `:167-168` ("signatureHash must be 64-char lowercase hex (sha256)") + `:218-234` canonical 재직렬화 필드. `tools/` 소비 0건. `tests/unit/test_scope_lock_rust.nim`은 이 형식 검증의 시험이다.
   - lane 실행 경로(`src/cli/rust_lane_cli.nim`)는 lock entry에서 `specRef`(`:747`, `:861`)와 `module`(`:759`, `:878`)만 읽는다 — `signatureHash`는 읽지 않는다.
   - §6c v2가 측정하는 claim identity는 `claim.postSha256 = sha256Hex(spec "post" 텍스트)`(`:765-767`)로, lock의 `signatureHash`와는 **별개 수량**이다. 선언값이 identity 번들에 들어오는 경로는 lock 파일 전체 digest(`scope.rustTargetsSha256`, `:511`)뿐이며, 이 결속에는 합의 비교(판정)가 붙지 않는다.
4. **C7 N1 절반 판정의 정정**: C7 §5.3은 "(i) 증명서 미발행·(ii) `unknown` 유지·(iii) 변조 결속"이 성립했다고 기록했다. 본 계열에서는 **(iii)만 성립한다**(§5.4) — (i)(ii)는 producer/unknown 계열의 부산물이지 identity 장치의 보장이 아니었다. 변조된 선언으로도 in-subset 타깃은 `verified` + 인증서에 도달하며, 인증서 본문에 선언값은 어디에도 등장하지 않는다(§5.4).
5. **회답(관측으로 닫음)**: "명시적 identity-mismatch 거부 클래스는 현재 엔진 상태(`2f9c21693`)의 prove 경로에 존재하지 않는다 — 선언 `signatureHash`는 64-hex 형식 검증과 lock 전체 digest 결속까지만 기계적으로 다루어진다." 이것이 C7 §5.3 팔로우업 노트에 대한 기계 관측 기반 회답이다. **팔로우업 노트 (범위 밖 발견, 발견 ≠ 권한)**: 선언값 대비 측정값의 합의 판정 도입 여부, `claim.postSha256`와 선언 `signatureHash`의 관계 정의, `skreport_comparison` 비교기·게이트·정책 계층에서의 취급은 제품 변경 권한이 필요한 사항으로 이 문서에서 수행하지 않는다 — 어느 수정도 하지 않았다.

### 7.2 Non-claims

- **`u64_add`의 정확성·u64 의미에 대한 어떤 참·거짓 주장도 없다** — B/M 양 런의 `verified`는 엔진 자신의 기계 기록 원문 인용일 뿐이며, 본 문서는 그 판정을 검증·보증하지 않는다.
- 본 관측은 serde_json(C7) 계열이나 그 판정에 대한 어떤 주장도 하지 않는다 — 계열·서브젝트가 다르다.
- "identity 장치가 무효"라는 제품 판정이 아니다 — §6c v2 결속·비교기(`skreport_comparison`)·게이트·정책 계층에 대한 판정은 본 문서 범위 밖이다. 본 문서가 확정하는 것은 "prove 시점에 선언 `signatureHash`의 합의 판정이 없다"는 **실행 관측**과 강제점 위치뿐이다.
- 신규 판정값·enum·게이트·정책 변경 0건. `data/debt_registry.json` 등록도 수행하지 않았다(발견 ≠ 권한 — §7.1-5 팔로우업 노트로만).

## 8. Deviations (전수 목록)

1. **B-run 최초 시도 (proofs/.lake 미빌드)** — 환경 결손 관측(§4.2 원문) 후 문서화된 `lake build`(21 jobs, exit 0)로 프로비전(u64-scalar cold 선례)하고 신선 state로 재실행. 최초 시도 산출물 전량 `*_attempt1_proofs_not_built`로 보존. C7 §5.1a "fix and re-run, recorded" 선례 적용.
2. **스트림 캡처 방식** — 본 실험은 stdout/stderr 분리 리다이렉트(선례 d1–d5는 `2>&1` 결합 캡처). 3행 lane 출력이 stderr로 관측됐고 stdout은 0바이트다. 선례 기록("stdout")과의 귀속 차이는 캡처 방식 차이이며, 선례 시점의 실제 스트림 귀속이 어느 쪽이었는지는 본 문서 범위 밖이다 — 엔진 변경 주장 아님.
3. **Cargo.lock §8 프로토콜 미적용** — §4.5 판단 근거(서브젝트 Cargo.lock은 repo 추적·의존성 0건; 임시 배치 불요). 서브젝트 불변은 매니페스트 pre==post로 입증.
4. **인증서 2건·변조 증명 3종 커밋 추가** — d1–d5 runs 3파일 세트에 u64-add artifact 선례(certificate 커밋)를 더한 것이다. M-run의 인증서 발행이 본 실험의 핵심 관측이므로 기계 검증 가능 산출물로 커밋한다(§6 표).
5. **build_metadata.json 스탬프 오염 → HEAD 복원** (u64 quirk 선례의 선제 적용) — 양 런 porcelain clean 진입.
6. **vault journal 내부 디스크 전용** (`vault_*/data/trusted/journal/`) — d1–d5 vault 비커밋 관례 준용. 인증서·trajectory·payload로 관측 재현 가능.
