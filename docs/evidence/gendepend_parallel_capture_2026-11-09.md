# genDepend 병렬 캡처 전환 — 실행 증거 (2026-11-09)

> **종류**: 실행 증거(execution evidence)다. precompile_gates의 매니페스트 직렬
> 재생성 고정 비용(DEBT#522)을 병렬 캡처로 제거한 슬라이스의 명령→관측→exit
> 기록이다. 모든 수치는 아래 명령으로 재현 가능한 기계 관측이며, 관측 환경은
> 기록된 그대로다.
> **브랜치**: `workstream/gendepend-lever` (base: main `b9aba2a`, PR #30 병합 후).
> **구현 파일**: `tools/ci/generate_gate_closure_manifests.sh`(캡처 루프 병렬화),
> `src/cli/precompile_gates.nim`(주석·로그 문자열 "serial" 갱신),
> `docs/spec/nim_gendepend_quirks.md`(실행 계약 갱신),
> `data/debt_registry.json`(DEBT#522 disposition 갱신),
> `data/architecture_debt.json`(regen-arch).
> **측정 환경**: nproc 16, RAM 30GB, Nim 2.2.10(choosenim), Ubuntu Linux,
> 워크트리 `~/.cache/axiom/worktrees/gendepend-lever`.

---

## §1. 임무 배경 (관측)

- PR #30 착지 과정의 범위 밖 관측: precompile_gates가 매 실행마다 54 게이트의
  genDepend 매니페스트를 **직렬 재생성**하며 모드 무관 고정 비용 발생
  (웜 실행 1m07s의 대부분). VS-2b/3 실측
  (docs/evidence/vs2b3_build_verdict_2026-11-09.md §2 e1c: 콜드 `Done in
  64.6s`; VS-T §8: 매니페스트 생성 64–92s/run).
- DEBT#522가 이 비용을 "성능 후속용 데이터"로 등록하면서 후속 옵션으로
  "증분 재생성 / 병렬 캡처"(단, fail-closed 검증 계약 약화 금지)를 명시 예약.

## §2. 코드 조사 (기계 확인)

- `src/cli/precompile_gates.nim:457-499` — `block closureManifestGeneration`:
  매 실행 **무조건 전체 재생성**(VS-T 하드 제약: 읽기 시점 검증은 클로저가
  **늘어난** 경우를 탐지할 수 없어 undercount 재발 방지를 위해 신선성 스탬프
  금지). 생성 실패 = `quit(1)` fail-closed.
- `tools/ci/generate_gate_closure_manifests.sh` (구) 111-141행 — 54 타깃을
  for 루프로 **직렬** `pp_capture_manifest` 호출(타깃당 `nim genDepend`
  프로세스 1회).
- `.githooks/pre-push:220-294` `pp_capture_manifest` — 호출마다 `mktemp -d`
  CWD+nimcache 완전 격리, 모든 변수 local, `.deps` artifact 자체 검증.
- 소비자 `src/core/gate/closure_manifest.nim loadProjectClosure` — 매니페스트
  헤더(SCHEMA/MAIN/NIM_SHA256/NIM_VERSION/FLAGS/CWD_CONTRACT) + 클로저 파일
  존재 + 프로브 결합을 매 읽기마다 전수 검증 → `gate_cas.computeTransitive
  SourceHash` → CAS 키.

## §3. 설계 판정 — 왜 병렬 캡처인가

- **(a) 매니페스트 캐싱 — 기각**: 재사용의 정확성 조건은 캐시 키가 genDepend의
  전 입력(저장소 전체 파일 내용+존재 집합·플래그·툴체인·`when fileExists`
  프로브 대상 전체)을 덮는 것. 이는 VS-T "무조건 재생성" 하드 제약의 재설계,
  즉 상태 전이 의미론 변경(§2.6 위반 소지)이며, 캐싱이 매니페스트 신선성
  의미론을 바꿔야만 성립한다면 그 자체가 분기 보고 사유가 되는 설계다.
  게다가 전제 나무 해싱 비용이 병렬화 이득(수 초)을 상회할 수 있다.
- **(b) 병렬 캡처 — 채택**: 재생성 의미론·authority·fail-closed·출력 바이트를
  전혀 변경하지 않는 순수 wall-clock 최적화. 근거:
  1. **호출별 완전 격리**(이미 계약화된 불변식): 각 `pp_capture_manifest`는
     자체 `mktemp -d` CWD+nimcache, 자체 mktemp 캡처 파일, 자체 매니페스트
     출력 경로(중복 module basename은 생성기가 fail-closed 거부)를 가진다.
     공유 가변 경로 0 — DEBT#457/DEBT#481의 "공유 nimcache·공유 출력 경로"
     충돌 계급이 구조적으로 부재.
  2. **출력은 스케줄링 무관**: 매니페스트 바이트는 (소스 내용, FLAGS 문자열,
     nim 바이너리 sha256 + `nim --version` 출력)의 순함수. VS-T §6 D가 54게이트
     재생성 2회 바이트 동일을 실측한 바 있다(본 슬라이스 §5에서 직렬 기저선
     대비로 재실증).
  3. DEBT#522가 "병렬 캡처"를 명시적 후속 옵션으로 예약(단 fail-closed 계약
     유지 — §6에서 실패 주입으로 관측).
- **§0.6 동시성 준수**: 병렬화는 생성기 bash 스크립트 내부(프로세스 수준,
  I/O-bound 자식 프로세스)이며, Nim 코드의 동시성 표면은 불변. 동시 상한
  `AXIOM_CLOSURE_WORKERS`(기본 8, nproc 상한 — 2vCPU CI 러너는 자동으로 2).

## §4. 구현 계약

`tools/ci/generate_gate_closure_manifests.sh`:

- 캡처 루프 → worker pool(active 카운터 스로틀 + `wait -n` 회수). 각 job은
  격리 캡처 + 매니페스트 원자적 쓰기(tmp→mv) 후 `$WORK_DIR/<idx>.{rc,log}`
  에 판정 기록(팬덤 출력 없음 — 로그 인터리빙 원천 차단).
- 판정 보고는 타깃 순서로 직렬 재생 → **로그 순서 결정론** 유지. job 실패
  메시지는 직렬 계약의 것과 동일 문자열("genDepend closure capture failed
  for $gid ($main) — UNKNOWN, fail-closed" 등)을 보고 시점에 단일 출력.
- rc 파일 부재(강제 종료 등) = UNKNOWN = 전체 실패(fail-closed).
- EXIT trap 확장: `rm -rf "$WORK_DIR"` + 기존 `.dot` belt-and-braces 정리.
- `src/cli/precompile_gates.nim`: 447-449행 주석 "serial genDepend" → 동시
  캡처 계약 서술, 499행 로그 "(serial genDepend)" → "(genDepend)".
  Nim 측 호출 계약(단일 execCmdEx, exit≠0 → quit(1))은 불변.

## §5. 측정 (A/B, 동일 머신·동일 트리)

빌드 레시피: `ci/checker.mk` `ci-compile-precompile-gates` 그대로
(`AXIOM_HERMETIC_BUILDING=1 nim c -d:release -d:axiomNoLto …`).

| 런 | 코드 | 매니페스트 생성 | 웜 총 wall | 관측 |
|---|---|---|---|---|
| 기저선 콜드 | main(`b9aba2a`) | (스냅샷 채취) | 180.1s | 54/54 컴파일, 0 failed, exit 0 |
| 기저선 웜 r2 | main | **109.5s (serial)** | 114.7s | `All gate binaries up to date (54 gates)` |
| 병렬 웜 r1 | 본 슬라이스 | **14.2s** | 17.9s | 동일 up-to-date 판정, exit 0 |
| 병렬 웜 r2(최종본) | 본 슬라이스 | **11.5s** | 15.0s | 동일, exit 0 |

- **매니페스트 생성 109.5s → 11.5s (≈9.5×)**, 웜 실행 총 wall 114.7s → 15.0s.
- **바이트 동일성**: 직렬 기저선 스냅샷(`/tmp/gd_manifest_baseline`, 54파일)과
  병렬 재생성 결과를 `diff -r` → **54/54 바이트 동일**(병렬 r1·r2 두 번 모두).
- **양성 대조**: 스크립트 단독 실행(conflict-marker-gate 1타깃)의 산출
  매니페스트를 캐시 내 본본과 `cmp` → 바이트 동일.
- **worker 엣지**: `AXIOM_CLOSURE_WORKERS=1` → 직렬 등가로 정상 동작;
  무효값 `abc` → 기본 8로 폴백, 정상 동작.
- **키 안정성(종단)**: 웜 실행에서 `All gate binaries up to date (54 gates)`
  — 매니페스트가 병렬로 재생성돼도 54 게이트 CAS 키 전부 불변(매니페스트
  바이트 동일 → Merkle 불변의 필연적 귀결).
- **잔류물**: 실행 후 `git status --porcelain` 변화 없음(스트레이 `.dot` 0건).

## §6. fail-closed 보존 (실패 주입)

타깃 파일에 존재하지 않는 모듈을 import하는 스크래치 타깃(`import
core/does_not_exist_gdtest`, `/tmp` 소재)을 실관문과 섞어 생성기 단독 실행:

```
$ bash tools/ci/generate_gate_closure_manifests.sh $PWD <targets.tsv> <outDir> <FLAGS>
[closure-manifest] conflict-marker-gate -> …/conflict_marker_gate.manifest (96 closure, 0 probe)
[closure-manifest] FAIL: genDepend closure capture failed for gd-failtest-scratch (/tmp/gd_failtest_scratch.nim) — UNKNOWN, fail-closed
EXIT=1
```

- 전체 실행 실패(exit 1) + 직렬 계약과 동일한 단일 FAIL 메시지. 정상 타깃의
  매니페스트는 직렬 버전과 동일하게 부분 기록(직렬도 i번째 실패 시 0..i-1
  매니페스트 잔존) — precompile_gates는 exit≠0이면 재생성 실패로 quit(1).

## §7. 부채·문서 갱신

- `data/debt_registry.json` DEBT#522: status 유지(`open` — nim 바이너리
  sha256 비용 잔류), resolution에 병렬 캡처 반쪽 해소 기록.
- `bin/debt_engine --codegen`: 투영 2종 멱등([skip] — resolution은 투영
  대상 아님 확인). `bin/debt_engine --regen-arch` 후 `--validate`:
  **1598/1598 passed, 0 failed, 3 PASS / 0 DRIFT**. (regen-arch는
  `src/cli/precompile_gates.nim` 정준 해시 갱신 + `src/cli/merge_cli.nim`
  rawContentHash 교정 포함 — 후자는 main에 이미 존재하던 raw 해시 부실값으로,
  파일 바이트는 main과 동일함을 `sha256sum`으로 확인.)
- `docs/spec/nim_gendepend_quirks.md`: 실행 계약의 VS-T 생성기 항 및 Status에
  2026-11-09 동시 캡처 전환 기록.

## §8. 재현 명령

```
AXIOM_HERMETIC_BUILDING=1 nim c -d:release -d:axiomNoLto --hints:off \
  --nimcache:build/nimcache/ci-compile/precompile_gates \
  -o:bin/precompile_gates src/cli/precompile_gates.nim
cp -r .axiom/cache/gate_closure /tmp/manifest_snapshot          # 직렬 기저선(전환 전) 채취
bin/precompile_gates                                            # 웜: "[closure-manifest] generation done in Xs (genDepend)"
diff -r /tmp/manifest_snapshot .axiom/cache/gate_closure        # 54/54 바이트 동일 기대
AXIOM_CLOSURE_WORKERS=2 bash tools/ci/generate_gate_closure_manifests.sh …  # 단독 실행
```

## §9. Follow-up (범위 밖)

- DEBT#522 잔류 반쪽: `loadProjectClosure`의 nim 바이너리 sha256(비릴리즈
  도구에서 ~3.5s/호출, 릴리즈 빌드에서는 훨씬 저렴) — memoization은
  correctness-first 설계로 의도적으로 배제됨.
- 매니페스트 증분 재생성: 본 슬라이스에서 명시적으로 추구하지 않음(§3 (a)
  기각 사유 — 신선성 키 재설계 필요).

## §10. 리베이스 노트 (2026-11-09, base 이동)

본 슬라이스 검증 중 원격 main이 이동했다 — `b9aba2a` → `07de680` (PR #31·#33
착지; #33이 DEBT#521 pre-commit 반쪽을 해소; #32는 docs 증거 1건만 변경 —
소스 무영향). 작업 브랜치를 리베이스했다:

- 충돌 2건: `docs/spec/nim_gendepend_quirks.md`는 main의 DEBT#521 완결
  서술과 본 슬라이스의 병렬 캡처 기록을 병합, `data/debt_registry.json`은
  자동 해소(main의 DEBT#521 완결 + 본 슬라이스의 DEBT#522 disposition
  공존)이다.
- §5 측정은 base `b9aba2a` 트리에서 수행됐다(A/B가 동일 트리 내 전환이므로
  유효성 불변). 리베이스 트리 재검증(기계 관측): `bin/debt_engine --codegen`
  멱등([skip]×2)·`--validate` 1598/1598 green·`bin/precompile_gates` 웜 실행
  **생성 10.4s·`All gate binaries up to date (54 gates)`·재컴파일 0**(§8 절차).
- 회전 핀(`config/trusted_writer_set.json`): 리베이스 트리에서
  `bin/reanchor_pin --ref HEAD` 무드리프트(`pin@HEAD anchors derived(HEAD)`)
  — #31·#33의 변경은 checker closure 밖이라 재회전 불필요했다.
