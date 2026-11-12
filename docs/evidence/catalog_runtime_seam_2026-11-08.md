# 카탈로그 런타임 루트 해석 시임(S2b) 착지 — 기계 검증 증거 (2026-11-08)

> **종류**: 구현(implement) 회전 증거 기록. **판정 권위는 기계 관측이며, 이 문서는 그 기록이다.**
> **Date**: 2026-11-08 · **Branch**: `workstream/catalog-runtime-seam-impl` (base `5e740d7e4` = main @ PR #14 merge)
> **대상**: S2a(PR #14)가 문서화한 카탈로그 런타임 루트 해석 시임의 구현 — `src/cli/external_subject_registry.nim`(레지스트리 specDir 루트) + `src/cli/axiom_engine.nim`(bytesview 오버레이 경로) 두 클로저 멤버의 회전
> **정본 계약**: VS-2 §2.3 root-resolution amendment(2026-11-08) · bytesview §3.1 "Overlay path root resolution (revised 2026-11-08)" · productization §1b(AXIOM_ROOT 최우선 → 바이너리 위치 앵커 워크 → 트리 밖 앵커 미스 = 카탈로그 read fail-closed) · Q-013(root-escape quirk)

---

## §1. 구현 계약 (시임 형태)

루트 해석 순서(정본 그대로): `AXIOM_ROOT` env 최우선 → 미설정 시 **바이너리 위치에서 상향** `.axiom_root`/`axiom.toml` 앵커 탐색(첫 앵커 종료) → **트리 밖 앵커 미스 = 카탈로그 read failure, fail-closed**. 기존 `findRepoRoot`의 레거시 한 단계 상향 폴백은 이 시임이 **상속하지 않는다**(엄격 변형 `findRepoRootStrict`).

구현 형태(const는 런타임 값을 못 담으므로):

| 기존 | 신규 | 비고 |
|---|---|---|
| `const defaultExternalSubjectSpecDir* = repoRootConst() / "config" / "spec"` (external_subject_registry.nim:46) | `findRepoRootStrict`(private, Result) + `resolveExternalSubjectSpecDir*()`(Result 시임) + `defaultExternalSubjectSpecDir*` **template**(문자열 어댑터) | 기본 매개변수 위치(`specDir: string = defaultExternalSubjectSpecDir`)는 **컴파일 불변** — template 확장으로 **호출 시점마다** 런타임 평가. `""` = 앵커 미스 센티널: 조인·walkDir 불가(Q-013), `loadExternalSubjectRegistry`가 첫 문장에서 fail-closed 거부 |
| `const NimLibp2pBytesviewSliceOverlayPath*`(axiom_engine.nim:1761, "compile-time anchor") | `proc nimLibp2pBytesviewSliceOverlayPath*(): Result[string, string]` | loader(`loadNimLibp2pBytesviewSliceOverlayDomain`)·패리티 섀도가 소비; 핀 검증(`verifyLibp2pBytesviewSubjectPin`)은 domain을 소비하므로 서명 불변 |

엔진 내 소비 지점 3곳(`loadBase36CoutOverlayDomain` cout 로더, `coutMandatoryPresence` 에러 메시지)은 동일 시임(`resolveExternalSubjectSpecDir`)을 소비한다. `src/cli/proposition_intake.nim`·`capability_cli.nim` 등 비멤버 소비자는 **미수정**(template 어댑터가 기존 참조를 그대로 컴파일) — A2 (i) 비멤버 production src/ 회전 금지 준수.

**구현 계층 선택(측정)**: strict 해석기 최초 배치 `src/core/utils/repo_root.nim`은 `architecture_invariants.nim:580` proc→func 래칫(`procCount <= 950`, 당시 950 경계) 위반으로 빌드 차단(951번째 proc). stdlib `fileExists`가 `.sideEffect`(`std/files.nim:47`)라 func화 불가(측정: `func` 프로브 컴파일 에러 "can have side effects"). 시임 소유 cli 레이어(external_subject_registry.nim)로 배치 — 스펙 개정문의 "call-site change rather than an engine redesign" 형태 그대로. `repo_root.nim`·기존 `findRepoRoot` 소비자 불변.

## §2. 변경 diff 요약

커밋 `753827a`(+ 이후 핀 회전 커밋): `git diff 5e740d7e`

| 파일 | 내용 |
|---|---|
| `src/cli/external_subject_registry.nim` | +96/−14: `findRepoRootStrict`(AXIOM_ROOT → 엄격 앵커 워크, 레거시 폴백 없음, `parentDir("/")`→`""` CWD 탐침 회피 — 워크가 빈 경로를 탐침하기 전 종료) · `resolveExternalSubjectSpecDir`(Result 시임, "config"/"spec" 조인 단일 정의) · `defaultExternalSubjectSpecDir` template · `loadExternalSubjectRegistry` 빈 specDir fail-closed(재해석으로 정확한 사유 획득) |
| `src/cli/axiom_engine.nim` | +50/−14: bytesview 경로 const→proc(§3.1 계약) · 로더 시임 처리 · cout 로더·mandatory-presence 메시지 시임 처리 |
| `data/nimtry_baseline.json` | 회전 동반(A2): 전체 트리 재앵커 — 4259 위반, 24 fingerprint 갱신(신규 4: exported 54→55, prepareProofRun 357 SLOC, loadExternalSubjectRegistry 68 SLOC, runVerificationWaves 라인 시프트 + 나머지는 두 멤버 파일 내 라인 시프트). **scoped 재동결 불가 측정**: `saveBaselineV2`는 병합 없이 전체 덮어쓰기(nimtry_cli.nim:152) — scoped 재동결은 타 파일 부채 언앵커 |
| `data/debt_ledger.json` | 회전 동반: BUDGET#004 `--sync-budget` 정준 갱신(current 2→0, status closed/FIXED — 투영 0==target 0의 도구 판정) |
| `data/architecture_debt.json` | 회전 동반: `--regen-arch` — axiom_engine.nim canonicalSyntaxHash 재고정 |
| `src/generated/type_registry_metadata.json` | 생성 동반: hermetic 재생성(신규 proc 심볼 등재) |
| `config/trusted_writer_set.json` | 핀 값 회전(멤버십 불변) — §4 |
| `docs/evidence/catalog_runtime_seam_2026-11-08.md` | 본 문서 |

**미변경(범위 규율)**: 나머지 5레인 경로 const(VS-2 PR-1..6 범위) · `repo_root.nim`(`findRepoRoot`·레거시 폴백 포함 전체 불변) · `proposition_intake.nim`·`capability_cli.nim`·테스트 파일 전부 · §-1 동결 파일. `config/spec/*.json` 문서 불변.

## §3. 기계 검증 (구현 후, 2026-11-08)

**V1 — 빌드**: `nimble build` → **exit 0**(bin/ax 12.4MB).
(측정 노트: 재빌드가 `.axiom/cache/build_env.body` 부재로 `build_env.nim`을 갱신하지 않는 경로 — "build_env.nim already present" — 를 밟아 SourceCoherence FATAL(tree≠embedded)이 재현되었다; 캐시 삭제 + `nimble hermetic` 강제 재료화로 `BuildSourceHash = -1431601552256525477`(라이브 트리 해시) 재생성 확인 후 V1 성공. 본 슬라이스 코드 결함이 아니라 오케스트레이션 캐시 경로 관측 기록.)

**V2 — 게이트**:

```
$ make check-arch
✅ No architecture violations        → exit 0
$ make check-debt
  Metric evaluation: 4 PASS, 0 DRIFT
  All debt validation checks passed.  → exit 0
```

기준선 대조(stash 후 원본 main 실측): `bin/nimtry src/` **exit 1**("1 new violations not in baseline", runVerificationWaves@4729) — **main의 check-arch는 본 PR 이전 이미 빨강**(PR #13이 nimtry 베이스라인 재동결 없이 착지, debt_ledger만 live값 2로 갱신 — check-debt만 녹색 유지). 본 회전의 전체 트리 재앵커가 이 사전 존재 빨강을 치유했다(부채는 베이스라인에 앵커된 채 가시 보존 — nimtry v2 프로토콜 설계 동작).

**V3 — 유닛 스위트(exit 코드 실측)**:

```
$ nim r tests/unit/test_libp2p_bytesview_binding.nim   → exit 0
$ nim r tests/unit/obligation_subject_binding_test.nim → exit 0
$ nim r tests/cli/test_proposition_intake.nim          → exit 0 (registry overlayDir shadow-merge 포함)
$ nim r tests/unit/test_lane_dispatch_equipped.nim     → exit 0
```

(사전 존재 실패, 범위 밖: `tests/unit/test_external_subject_registry.nim`은 **원본 main에서도 동일 exit 1** — 낡은 "6 production lanes" 기대치 vs 루트 커밋부터 존재한 7번째 문서 `nim_libp2p_varint_roundtrip.json`. 본 PR은 수정하지 않는다(§2.2 범위 폐쇄). lane_dispatch 스위트가 7-항목 카탈로그를 정상 인식하므로 카탈로그 자체는 정합.)

**V4 — 런타임 시임 실측 3종**(관측 경로 `ax capability --json` — 기본 specDir 경유):

```
(a) AXIOM_ROOT 우선:
$ AXIOM_ROOT=/tmp/s2b_seemtest_root bin/ax capability --json  → exit 0
   entries: 1 · SPEC-B32-REM-RANGE EQUIPPED   (임시 루트의 카탈로그만 — env 최우선 실증)

(b) 미설정 + 트리 내 바이너리(소스 트리 동작 보존):
$ env -u AXIOM_ROOT bin/ax capability --json               → exit 0
   entries: 7 · 6 EQUIPPED + SPEC-LIBP2P-VARINT-RT NOT_EQUIPPED
   (앵커 워크가 컴파일 시점 루트와 동일한 루트 재현 — 기존 동작과 항목 단위 동일)

(c) 트리 밖 바이너리 + 앵커 없음(CWD는 저장소 내부 — Q-013 함정 시나리오):
$ env -u AXIOM_ROOT /tmp/s2b_tree_ext/ax capability --json  → exit 2
   [AXIOM] ax capability: committed catalog unavailable (fail-closed): catalog root
   unresolved (fail-closed): AXIOM_ROOT is unset and no .axiom_root/axiom.toml
   anchor found from "/tmp/s2b_tree_ext" — a tree-external binary must set
   AXIOM_ROOT (productization contract §1b, Q-013)
   (CWD 상대 조인·빈 루트 탐침 없이 즉각 fail-closed)
```

**V5 — 훅**:

```
$ bin/build_all_gates --release   → 82 built, 0 failed (2 accepted-dead skip)
$ bash .githooks/pre-commit       → [PASS] Pre-commit checks passed → exit 0
$ bash .githooks/pre-push         → §4 핀 앵커 검증 통과 → exit 0
```

## §4. TWS 핀 회전 (A2 원자 페어)

소스 커밋(`753827a`) 후:

```
$ bin/reanchor_pin --ref <HEAD OID> --write
→ trusted_writer_set.json blob-sha 재앵커 (멤버십 — 경로 집합 — 불변, 값 회전만)
```

갱신된 핀을 별도 커밋으로 착지 → push(`.githooks/pre-push` Part 5가 `bin/reanchor_pin --ref <OID>` 판정으로 강제 — exit 0 관측). 핀 멤버십 변경(exit 3) 발생 시 중단 보고 예정이었으나 **미발생**.

## §5. 착지

PR: `workstream/catalog-runtime-seam-impl` → main. 생성 직후 `gh pr merge --auto --merge --match-head-commit`(수동 merge 금지 — PR #13 선례: merge_group 판정이 TRUST_SURFACE_MODIFIED로 큐 중단 후 PR-venue required checks green으로 auto-merge 완료 경로). 착지 후 확인(재빌드 + V2/V4 재실행) 결과는 최종 보고서에 기록한다.
