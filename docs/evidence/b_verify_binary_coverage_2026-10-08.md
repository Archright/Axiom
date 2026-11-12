# B Cache Binary Coverage — 4종 ci-compile 바이너리 SourceCoherence 확장 실측 (2026-10-08)

**작업**: Canonical Build Reuse slice 후속 — PR #566 증거 문서 §6의 정직 기록 잔여 해소.
**브랜치**: `fix/b-verify-binary-coverage` (worktree `b-verify-extend`, base = origin/main `83bc2c995`).
**스펙**: `docs/spec/ci_optimization_tcb_judgments.md` §3.3 (probe 커버리지 갱신).

## 1. 잔여 (PR #566 docs/evidence/j3_manifest_anchoring_2026-10-07.md §6 원문)

> **동시 변조 중 bin/ax 이외의 3바이너리만 교체 + manifest 재작성** 케이스는 restore-side에서
> 미검출이다 — bin/ax만 SourceCoherence 자기검증을 갖는다. 완전 커버는 save-side 서명
> (ed25519) 또는 3바이너리의 provenance 임베드 확장이 필요하며 publisher 권한이 요구된다.

## 2. 선택: (a) 임베드 확장 — 선택 근거 (실측 + 구조 근거)

| 판단축 | (a) 임베드 확장 (선택) | (b) save-side ed25519 서명 |
|---|---|---|
| 신뢰 앵커 | 호출자 git 객체 저장소 — **B 키 자체가 파생되는 그 앵커와 동일** (신규 신뢰 루트 0개) | 핀 고정 공개키 + publisher 시크릿 — **새 신뢰 루트** (키 유출·로테이션 런북 TCB 추가) |
| 검증기 위치 | 바이너리 자신(`--check-provenance`) — 기대값은 payload 외부 트리에서 재계산 | restore 측에서 서명 검증 구현 필요 — runner python3 표준 라이브러리엔 ed25519 부재 → 순수 파이썬 구현 반입 또는 payload 바이너리 재사용(순환성 재도입) 딜레마 |
| publisher/스키마 | 무변경 (manifest schema v1 유지, publisher 무터치) | publisher 서명 단계 + manifest v2 필요 |
| 판정 의미 | 불변 — 감지→폐기→cold fallback 동일 계약 | 불변 |
| 기존 검증된 메커니즘 | #566에서 bin/ax로 실측된 probe(OK/stale 감지)를 그대로 확장 | 신규 인프라 |

벤더된 ed25519(`vendor/ed25519`)와 ratchet 서명 도구가 존재하더라도, (b)는 새 신뢰 루트(키)와
새 검증기 TCB를 영구히 추가하는 반면 (a)는 이미 키 파생이 의존하는 git 객체 저장소 앵커로
커버리지를 닫는다. PR 본문에 동일 근거 기록.

## 3. 구현 요약

| 파일 | 변경 |
|---|---|
| `src/core/utils/build_provenance.nim` (신규, 순수 커널) | 정준 지문 알고리즘 SSOT(`hashSourceContents` — hermetic_build 빌드시점 twin과 lock-step) + probe 요청 판별(`--check-provenance`) — I/O 없음(core_purity R1/R2 준수) |
| `src/infrastructure/provenance_probe.nim` (신규, I/O 어댑터) | 런타임 src 재계산(`computeSourceTreeHash` — walk·read는 여기만 수행) + `verifyProvenanceOrFatal`(엄격 자기검증: 정준 자기경로 강제 + 불일치 FATAL exit 1 — 조기 리턴 없음) |
| `src/cli/main.nim` | `computeSourceTreeHash`를 SSOT에 위임 + `--check-provenance` 플래그(`bin/ax`) |
| `src/cli/install_ax_cas.nim` / `src/cli/precompile_gates.nim` / `src/gate/runners/gate_hook.nim` | 플래그 분기만 추가 — 일반 실행 경로(훅·게이트 파이프라인) 무변화, 부작용 0 |
| `.github/actions/setup-axiom-toolchain/action.yml` | probe 스텝: bin/ax 단수 → **4종 전부** `--check-provenance` 실행 (payload 바이너리 누락도 FAIL). 스크립트 해시 변경 → A/B 키 1회 무효화(one-shot cold, 헤더 계약 문서화된 동작) |
| `tests/ci/test_b_cache_anchor.nim` | 13 → 15 시나리오 ((p4) 보조 바이너리 단수 감지, (c2) 잔여 종단간) |
| `docs/spec/ci_optimization_tcb_judgments.md` | §3.3 probe 커버리지 4종 명시 |

스크립트 해시 변경으로 **A/B 키 전면 1회 무효화(one-shot cold)** 예상 — 헤더 계약의 문서화된 동작.

## 4. 실측 (실바이너리 + 실커밋 트리)

환경: worktree 커밋 `bb310fd48` (트리 `ba2988501298cc670d4b2ace1ed15d90a72c9c07`),
4바이너리 = `make -f ci/checker.mk ci-compile -j4` 산물 (exit 0),
복제 클론의 git 객체 저장소에서 action.yml의 **실제 스텝 본문을 원문 추출해 실행**.

### 4.1 정상 복원 — false-positive 0

```
AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified, identity=ba2988501298 ...
b-verify-ok=true
AXIOM_CACHE_B_PROBE: OK — restored bin/ax ... == trusted tree ba2988501298
AXIOM_CACHE_B_PROBE: OK — restored bin/gate_hook ... == trusted tree ba2988501298
AXIOM_CACHE_B_PROBE: OK — restored bin/precompile_gates ... == trusted tree ba2988501298
AXIOM_CACHE_B_PROBE: OK — restored bin/install_ax_cas ... == trusted tree ba2988501298
→ 폐기 없음, bin/ 4종 보존
```

### 4.2 잔여 시나리오 — 보조 바이너리 단독 교체 + manifest 재작성 → 감지 → cold fallback

main 클론(구 트리에서 빌드된 stale `bin/gate_hook`, sha256 `afea3173…`)으로 교체 +
manifest `files{}`를 그에 맞게 재작성(잔여가 가정한 정확한 공격):

```
AXIOM_CACHE_B_VERIFY: RESULT OK — 4/4 entries digest-verified ...   ← digest 레이어 자기일관 통과(잔여 사실 재현)
b-verify-ok=true
AXIOM_CACHE_B_PROBE: OK — restored bin/ax ...
AXIOM_CACHE_B_PROBE: FAIL — restored bin/gate_hook provenance != trusted tree ba2988501298
  (SourceCoherence FATAL: binary was not built from the key's tree — simultaneous payload+manifest contamination detected)
AXIOM_CACHE_B_PROBE: OK — restored bin/precompile_gates ...
AXIOM_CACHE_B_PROBE: OK — restored bin/install_ax_cas ...
AXIOM_CACHE_B_PROBE: DISCARDED — native build runs (fail-closed ...)
→ bin/ 4종 + B 캐시 경로 전부 소멸 확인 (cold fallback)
```

직전 세계( bin/ax만 probe)에서는 이 시나리오가 통과했을 것이다 — 4종 커버리지로 닫힘.

### 4.3 계약 테스트 + 판정 + 회귀

- `tests/ci/test_b_cache_anchor.nim` **15/15 PASS** — 기존 13 시나리오 전부 유지 + (p4)/(c2) 신규.
  (c2)는 digest 레이어의 자기일관 통과 사실과 probe 감지를 한 시나리오에서 종단 고정.
- `bin/tcb_judgments selftest` **12/12 PASS**, `--judgment cache-manifest` **exit 0 PASS**
  ("semantic provenance probe present? PASS (report-only)").
- `make test-unit` 전체 회귀 + `make verify-contract-release-e2e-full` G7 — 아래 §6 실측값.

## 5. CI 건전성 근거 (정상 경로에서의 임베드 신선도)

`ci-compile`은 `AXIOM_HERMETIC_BUILDING=1`로 config.nims의 hermetic 갱신 블록을 스킵한다
(재귀 방지). 따라서 임베드 신선도는 **bootstrap → compile 순서 불변식**이 보장한다:
gate run은 checkout 트리 X에서 `ci-bootstrap`(시드가 당시 live BuildSourceHash 주입 —
bootstrap 로그 `[coherence] build_env.nim seed guard: injected live BuildSourceHash` 실측)
→ `ci-compile`(같은 트리) → 임베드 == hash(X) == probe 재계산. 키의 트리 == 빌드 트리는
publisher의 `cache-build-source = manifest build_sha` 파생과 동일하게 성립(오탐 구조적 부재).
로컬 워크트리에서 bootstrap 후 src 편집 시 임베드가 지연되는 것은 bin/ax의 기존
SourceCoherence 계약과 동일한 fail-closed 동작이다.

## 6. 운영 실측 (착지 상태)

- [x] `make test-unit` 전체 green — **EXIT=0** (`test_b_cache_anchor` 15/15 [OK] 포함, 최종 suite "44 passed, 0 failed")
- [x] `make verify-contract-release-e2e-full` **G7 PASS** — `INFO: G7 pass (tier=z3-verified status=not_verifiable)` + `✅ verify-contract-release-e2e-full PASSED`, EXIT=0
- [x] `bin/ax report --canonical-digest` ×2 동일 — `076fc511272321d39a09f8b2cb5a7e74d485b537f4155686c70cd128c2b2e64b` ×2 일치
- [x] `bin/build_all_gates --release` 풀은 신규 worktree에서 per-gate nim argv 오류
  ("arguments can only be given if the '--run' option is selected")로 전건 실패 —
  동일 명령 단독 컴파일(`nim c -d:release -o:bin/X src/gate/runners/X.nim`)은 전부 성공.
  훅 필요 게이트(nim_check_gate·anti_theater·layer_enforcement)는 개별 빌드로 해결.
  pre-commit 게이트 전부 PASS로 커밋 완료(`--no-verify` 미사용). 풀 오류 자체는 본 슬라이스
  범위 밖(별도 추적 권고).
- [x] pre-existing 관찰(변경 없음, 추적 전용): `data/axiom_manifest.json` 봉인
  invariant_hash `7ab49541…` vs `src/core/trusted/architecture_invariants.nim` 실측
  `ea74a2f5…` 불일치 — main 클론과 동일 상태(origin/main 83bc2c995)로 본 슬라이스 이전부터
  존재. hermetic_build는 warning-only로 통과(DEBT 등록: verifyInvariantHash warning-only).
- [x] `ci-cache-publisher.yml` 터치 없음 / `--no-verify` 미사용

## 7. 잔여 위험 (정직 기록)

- `proofs/.lake/build/bin/ircheck`(Lean 산물, base seed manifest 5번째 엔트리)는 Nim
  SourceCoherence 임베드가 불가해 probe 미커버 — 기존과 동이하게 base seed manifest digest +
  실행시점 게이트 판정으로 전이 구속. Lean 측 직교 검증은 §0.9b 독립 언어 트랙 소관.
- `--check-provenance` 임베드는 컴파일시각 생성 상수이므로 "빌드 제어 가능한 공격자가
  자기 바이너리에 신뢰 트리 해시를 새겨 넣는" 것은 원리적으로 가능(#566 probe와 동일 한계).
  해당 공격자의 엔트리는 자기 트리의 키에만 착지한다(키-트리 바인딩) — cross-tree 전이는
  차단된다. 이 클래스의 완전 봉쇄는 (b) 서명 트랙의 존재 이유이며, 본 슬라이스는 #566 §6이
  지목한 잔여 클래스(페이로드 단독 조작)를 닫는다.
- exp-* 네임스페이스는 probe SKIP(기존 계약 유지) — digest + identity 결합으로만 운용.

## 8. CI 실측 부록 — core purity 회귀와 계층 분리 재측정 (2026-10-08)

PR #577 첫 admission run(run 37712175975)에서 `attest / admission-check`의 core
purity gate가 본 슬라이스 신규 모듈의 I/O를 새 위반으로 fail-closed 했다:
`src/core/utils/build_provenance.nim`의 `readFile`(1건)·`stderr.writeLine`(2건) —
R1/R2는 소스 레벨 면제가 없고 승인은 베이스라인 앵커뿐이며, CI는 B(main) 트리의
베이스라인으로 H 트리를 심판하므로 PR 내 베이스라인 갱신으로는 닫히지 않는다
(mint-prepare·mint-publish의 실패는 이로 인한 아티팩트 부재 연쇄).

**조치**: 계층 분리 — 순수 커널(`src/core/utils/build_provenance.nim`:
`hashSourceContents` 지문 알고리즘 + probe 요청 판별, I/O 0)과 I/O 어댑터
(`src/infrastructure/provenance_probe.nim`: walk·read·FATAL 리포트).

**재측정 (동일 커밋 트리, 2026-10-08)**:
- core purity ratchet: **PASS** — 위반 254 → 251(src/core 신규 기여 0,
  main 수준과 동일), regression 0
- 해시 바이트 동등성 3중 일치: hermetic_build 빌드시점 twin 재생성값 ==
  런타임 어댑터+커널 재계산 == 독립 twin 재현 구현값
  (`-7106739920358411256`) → 분리가 지문 의미를 보존함을 입증
- `--check-provenance` 4종 전부 **EXIT=0 OK** (bin/ax, bin/gate_hook,
  bin/precompile_gates, bin/install_ax_cas)
- tests/ci/test_b_cache_anchor.nim **15/15 OK**((p4) 보조 바이너리 감지 포함),
  tests/unit/main_test.nim **EXIT=0**
