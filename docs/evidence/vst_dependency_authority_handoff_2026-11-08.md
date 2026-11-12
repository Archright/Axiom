# VS-T 의존성 권한 핸드오프 — 실행 증거 (2026-11-08)

> **종류**: 실행 증거(execution evidence)다. 게이트 CAS 키의 클로저 기반을 휴리스틱 파서(`transitive_hash`)에서 컴파일러 진실(`nim genDepend` 검증 매니페스트)로 전환한 VS-T 수직 슬라이스의 명령→관측→exit 기록이다. 모든 수치는 아래 명령으로 재현 가능한 기계 관측이며, 추정치는 명시적으로 마킹한다.
> **브랜치**: `workstream/vst-dependency-authority` (base: main `5e740d7`).
> **구현 파일**: `tools/ci/generate_gate_closure_manifests.sh`(신규), `src/core/gate/closure_manifest.nim`(신규), `src/core/gate/gate_cas.nim`(공급자 교체), `src/cli/precompile_gates.nim`(매니페스트 생성 단계 삽입).
> **미수정 불변**: `transitive_hash.nim` 본문(waiver 2026-12-31), §-1 동결 파일, predicates/types.nim, 아키텍처 핸들러, VS-1 스탬프/훅 로직 — 전부 원본 유지(§-1 확인: `git diff --stat` 참조).

---

## §1. 설계 (구현 계약)

**신원 체계** — 매니페스트(`.axiom/cache/gate_closure/<module-basename>.manifest`)는 게이트 모듈별 genDepend 진실을 담는 정본 캡처다:

```
SCHEMA=gate-closure-manifest/1
MAIN=<모듈 절대경로>
NIM_SHA256=<nim 바이너리 sha256>
NIM_VERSION=<nim --version 전체 출력, \n 이스케이프>
FLAGS=<genDependProfile(repoRoot) 산출 문자열>
CWD_CONTRACT=mktemp-d-per-run
CLOSURE:<파일 절대경로>     ← genDepend .deps 프로젝트·표준 라이브러리 전체
PROBE:<파일 절대경로>       ← when fileExists 등 정적 미결 프로브 타깃
```

- **생성기** `tools/ci/generate_gate_closure_manifests.sh`: `.githooks/pre-push`를 `PREPUSH_SOURCE_ONLY=1`로 source해 `pp_capture_manifest`을 재사용(재구현 금지 계약). 인자 `<repoRoot> <targetsFile> <outDir> <flags>`. 직렬 genDepend, 원자적 쓰기(tmp→mv), EXIT-trap `.dot` 정리, 모듈 basename 충돌 거부, **캡처 1건 실패 시 exit 1(fail-closed)**.
- **공급자** `src/core/gate/closure_manifest.nim`: `genDependProfile(repoRoot)` = 플래그 문자열 단일 권위(§3). `loadProjectClosure(sourcePath)` = 매니페스트 전체 검증 후 프로젝트 클로저 반환: 스키마, MAIN==절대경로 정규화 일치, CWD_CONTRACT, FLAGS==재계산 프로파일, nim 바이너리 sha256 + `nim --version` 전체 일치, 클로저 파일 전부 존재, 메인 포함, 존재하는 PROBE 파일 결합. 검증 실패·매니페스트 부재 → `@[]`(fail-closed).
- **소비자** `src/core/gate/gate_cas.nim` `computeTransitiveSourceHash(sourcePath, srcRoot)`: 시그니처·효과·`""` 의미 불변. 본문만 교체 — `loadProjectClosure` → 파일별 sha256 → pairwise Merkle(`"\x02"` 도메인 분리자, 스키마 보존). **memoization 완전 삭제**(구 (file, mtime, size) memo는 다른 공급자 세대의 클로저를 재사용할 수 있었다). `transitive_hash` import 제거(본문은 미수정).
- **쓰기 단계** `src/cli/precompile_gates.nim`: 키 계산 전 `block closureManifestGeneration` — **무조건 전체 재생성**(비일관 발견 불가 undercount 방지; correctness-first), 실패 시 `quit(1)`.

## §2. Step 1 — baseline 동결 (main `5e740d7`)

구(휴리스틱) 공급자 상태에서 측정:

- `bin/precompile_gates` (구 바이너리): **54/54 컴파일, 78.9s** → `.axiom/cache/gate_env.lock` + `.axiom/cache/gates/` 54개 구키.
- per-gate 테이블: `build/vst_baseline_table.json` — 54행 `[gate_id, old_closure_hash16, old_cfg_hash16, old_closure_hash_full, binary_sha256]`.
- cfgHash 전체: `2127f750231f4a04ad44d110448ce84ea2d4c7ebb2241e32cc41edca1c6752c9` — 독립 재현 54/54 접두사 일치(구성: config.nims sha + axiom.nimble sha + "2.2.10" + linux + amd64 + linux-amd64 + `nim --version` 1행 + `sha256("no-lib")` — 이 호스트의 stdlib probe 경로 `nimExe.parentDir/lib/system.nim` 부재로 no-lib 분기).
- 재실행 관측: `All gate binaries up to date (54 gates)` — 정상 래칫.

## §3. Step 2 — 파일럿 (production-external, layer_enforcement_gate)

파일럿 도구(`build/vst_pilot.py`, `build/vst_oldhash.nim`, `build/vst_oldclosure.nim`, `build/vst_casres*.nim` — 빌드 산출물, 비커밋):

| 항목 | 구 휴리스틱 | 신규 genDepend 진실 |
|---|---|---|
| 클로저 프로젝트 파일 수 | **26** | **35 + 2 live probe** (`src/generated/build_env.nim`, `import_rules_static.nim`) |
| 미결속 파일 (델타) | — | `axiom_pragmas` include 4편(types/vm_helpers/macros/procs) + `scope_version` + `best_effort` + `gate_context` + `tools/shared/canonical_ast` + probe 2 |
| layer-enforcement 키(절대경로 폼) | `535bba66a5b3ab14…` | `fee31c9c10ee8980…` |
| 매니페스트 결정성 | — | **2회 생성 바이트 동일** (142라인) |

**결함 데모(파일럿 단계)**: `src/core/trusted/axiom_pragmas_types.nim` 1행 추가 → 구 키 `535bba66…` **불변** (파일이 구 클로저에 없음) vs 신규 키 `fee31c9c10ee8980 → 7050b7f2ade627e8` (변경). 편집 복원 확인. — 이것이 본 슬라이스가 수정하는 stale-binary 재사용 위험의 직접 입증이다.

**캡처 비용**: ~1.23s/게이트(직렬 genDepend, 콜드).

## §4. 실행 계약 등가성 (genDependProfile)

최종 프로파일(정본: `src/core/gate/closure_manifest.nim:genDependProfile`):

```
--hints:off --skipParentCfg --skipProjCfg --skipUserCfg --skipCfg --threads:on --mm:arc
--path:<root> --path:<root>/src --path:<root>/tests/gateway --path:<root>/src/shared_types --path:<root>/tools
--path:<nimRoot>          (nimExe.parentDir² 에 compiler/ 있을 때만)
--path:<pkgs2 5종>         (checksums, ed25519, fusion, malebolgia, nimcrypto — 각 이름 첫 sorted 매치)
-d:release -d:ThreadPoolSize=14
```

플래그 진화(관측된 실패→수정):
- `--skipCfg`만으로 nimble 해석 실패(`cannot open file: checksums/sha2`) → pkgs2 명시적 path 필수.
- `--threads:on` 누락 시 malebolgia `Thread` 미선언 에러(gateway-test에서 관측).
- `--mm:arc`는 `config/effects.nims:16`과 일치(순수 등가성; 유일한 gcOrc 분기는 GC_fullCollect 호출뿐, import 게이팅 없음).

**`when defined` 스윕(등가성 증거)**: 252개 프로젝트 클로저 파일 통합 — release/ThreadPoolSize 외 조건 심볼 9개(allowMissingLayer, amd64, axiomAudit, axiomDebug, axiomStrict, gcOrc, linux, posix, windows). 실컴파일 전용 define(axiomNimcacheConfigured, AXIOM_ENFORCE_GATE_PRAGMAS, axiomProjectPath, ssl)은 프로젝트 클로저 파일에 **0회 등장** → 분기 영향 없음 증명. 나머지는 플랫폼 define(동일) 또는 양측 미정의.

## §5. 컷오버 (coherent generation, §2.5)

### run2 (첫 전체 전환 — 구플래그)

```
bin/precompile_gates → EXIT=0, wall 6m17s
[closure-manifest] OK — 54 manifest(s) generated (serial genDepend)   (83.9s)
[precompile] 54 gates have compilable source entries
[precompile] 52 gate(s) changed source -- selective recompile
[precompile] Done in 57.0s: 52 compiled, 0 cached, 0 failed
```

### run3 (최종 플래그 `--mm:arc` 추가 후 — 매니페스트 전체 재생성)

```
bin/precompile_gates → EXIT=0, wall 330.2s
[closure-manifest] OK — 54 manifest(s) generated (serial genDepend)   (92.0s)
[precompile] 54 gates have compilable source entries
[precompile] 3 gate(s) changed source -- selective recompile
[precompile] Done in 6.7s: 3 compiled, 0 cached, 0 failed
```

run3에서 3개만 재컴파일된 사유(기계 확인): `src/core/gate/closure_manifest.nim`(`--mm:arc` 추가 편집)가 클로저에 포함된 게이트 = `binary-freshness-gate`, `cli-build`, `integrity-workflow` — `grep -l` 3/54 정확 일치. 나머지 51개는 `--mm:arc` 전·후 해시 동일(프로젝트 클로저는 플래그 무관; 플래그는 표준 라이브러리 클로저만 축소 173→171 등).

### HIT/MISS 집계 (baseline vs 최종 lock)

```
python3 비교 (build/vst_baseline_table.json 54행 vs .axiom/cache/gate_env.lock 54항목)
HIT : 2  ['conflict-marker-gate', 'hotspot-coverage-gate']
MISS: 52
CAS binaries missing at new keys: NONE (all 54 present)
```

**HIT 2건의 완전한 기계적 해명** (결함 아님):
- 두 게이트의 genDepend **프로젝트** 클로저 = `{main, src/core/trusted/layer_declaration.nim}` 단 2파일 (매니페스트 CLOSURE 98/111라인 중 나머지는 전부 표준 라이브러리 — 필터됨). `grep '^CLOSURE:' … | grep -v toolchains` 로 관측.
- 구 휴리스틱도 이 2게이트에선 동일 파일 집합 산출 → 동일 merkle → 동일 해시. 즉 휴리스틱이 **우연히 정확했던** 유일한 2게이트다. 두 게이트가 프로브 0개인 것과 일관(프로브 모듈 미임포트).
- `conflict-marker-gate` 해시 `e4fc8d7b77173eb8…` — `build/vst_oldhash`(구)와 신규 lock 양쪽 동일 관측.
- 선택적 재컴파일 논리(`findChangedGateIds`)가 해시 불변 게이트를 스킵 → "52 compiled"의 정체. **누락 아님.**

MISS 52건의 사유: 클로저 파일 수 증가(미결속 8종 + probe 2 포함) — §3 파일럿과 동일 원인의 전체 확장.

### Test B 엔드투엔드 (runB1 — 편집 상태 전체 스윕)

`axiom_pragmas_types.nim` 1행 추가 상태에서 실전 precompile:

```
bin/precompile_gates → EXIT=0, wall 308.0s
[closure-manifest] OK — 54 manifest(s) generated (serial genDepend)   (67.2s, 웜캐시)
[precompile] 51 gate(s) changed source -- selective recompile
[precompile] Done in 44.9s: 51 compiled, 0 cached, 0 failed
```

**51의 기계 확인**: `grep -l 'CLOSURE:.*/axiom_pragmas_types.nim$' .axiom/cache/gate_closure/*.manifest | wc -l` → **51** — 클로저에 해당 파일을 둔 게이트 수와 재컴파일 수 정확 일치. 편집 상태 CAS 관측: `layer-enforcement-gate-69034387af08d19f-…` 신규 키에 binary 존재(재빌드; 구키 binary 재사용 아님).

### Test B 복원 (runB2 — 캐시 재사용 관측)

```
bin/precompile_gates → EXIT=0, wall 298.7s
[precompile] 51 gate(s) changed source -- selective recompile
[precompile] Done in 0.0s: 0 compiled, 51 cached, 0 failed
```

복원된 소스 → 해시 원복 → 원 키의 기존 binary가 51/51 **cached**로 재사용 — content-addressed 재사용의 정상 동작(불필요 재컴파일 0).

### 최종 스윕 (run4 — fail-open 수정 반영)

`closure_manifest.nim`의 fail-open 수정(§6 부정 테스트 참조)으로 클로저에 이 파일을 둔 3게이트(§5 run3과 동일 3종)의 키가 다시 이동. 수정 코드로 재컴파일한 `bin/precompile_gates`로 최종 스윕:

```
bin/precompile_gates (fail-open 수정 반영 재빌드) → EXIT=0, wall 277.7s
[closure-manifest] OK — 54 manifest(s) generated (serial genDepend)   (64.5s)
[precompile] 3 gate(s) changed source -- selective recompile
[precompile] Done in 6.0s: 3 compiled, 0 cached, 0 failed     (binary-freshness-gate, cli-build, integrity-workflow)
```

**최종 상태 집계 (기계 관측)**:

```
baseline 54 / 최종 lock 54 / HIT 2 / MISS 52
CAS binaries missing at final keys: NONE (54/54 present)
프로브: layer-enforcement-gate hash=fee31c9c10ee8980, binary 존재
```

**Test D 재확장(수정 후)**: run4 재생성 매니페스트 vs 수정 전 스냅샷 `diff -r` → **54/54 바이트 동일** — 검증 경화는 생성 결정성·산출물에 무영향.

**키 이동 사슬 요약**(정상·기계 관측): baseline(구) → run2 전환 52 MISS → run3 `--mm:arc` 하드닝 3 MISS → run4 fail-open 수정 3 MISS(동일 3게이트). 각 단계 사유가 소스 변경 추적으로 정확히 환원된다.

## §6. 운영 검증 A–D + 부정 fail-closed

**A. per-gate baseline 테이블** — §2 완료 (`build/vst_baseline_table.json`, 54행).

**B. missing-file tracking (결함 데모, 엔드투엔드)** — §5 runB1/runB2 참조. 핵심 관측(프로브, `build/vst_probe`):

```
$ ./build/vst_probe $PWD layer-enforcement-gate src/gate/runners/layer_enforcement_gate.nim   # 편집 전
hash=fee31c9c10ee8980
cas=…/layer-enforcement-gate-fee31c9c10ee8980-2127f750231f4a04/binary
$ echo "# vst-test-b-relevant" >> src/core/trusted/axiom_pragmas_types.nim
$ ./build/vst_probe …   # 편집 후 — 신규 공급자
hash=69034387af08d19f            ← 변경 (relevant change ⇒ key change)
cas=REFUSED(no-key-or-no-binary) ← CAS 재사용 거부 (stale binary 재사용 불가)
$ ./build/vst_oldhash src/gate/runners/layer_enforcement_gate.nim src   # 같은 편집, 구 공급자
535bba66a5b3ab14…                ← 불변 (결함: 구 공급자는 이 파일을 클로저에 포함하지 않음)
```

**C. bidirectional (양방향성)**:
- relevant ⇒ key change: B에서 관측 (fee31c9c → 69034387). + run3의 자연 관측 — `closure_manifest.nim` 1행 편집이 정확히 클로저 포함 3게이트 키만 변경(§5).
- irrelevant ⇒ NO key change: 클로저 밖 tracked 파일 편집 관측 —

```
$ echo "# vst-test-c-irrelevant" >> src/gate/runners/hotspot_gate.nim   # layer-enforcement 클로저 밖 (grep 0확인)
$ ./build/vst_probe … layer-enforcement-gate …
hash=fee31c9c10ee8980     ← 편집 전/후/복원 3회 모두 동일
```

**D. determinism (결정성)**:
- **매니페스트**: runB2 직전 스냅샷(`/tmp/vst_manifest_snapshot`)과 runB2가 무조건 재생성한 매니페스트를 `diff -r` → **54/54 바이트 동일** (동일 입력 2회 생성).
- **키**: 동일 소스 상태에서 반복 probe 관측 — `fee31c9c10ee8980` (§5 run3 → §6 C → 복원 후 재관측, 전부 동일).
- fail-open 수정 후에도 생성 로직은 불변(검증만 경화) — run4 재생성 매니페스트도 수정 전 스냅샷과 54/54 바이트 동일(§5).

**부정 fail-closed (격리 fixture)** — 매니페스트 부재 케이스(스크래치 모듈, 프로덕션 게이트 세트 밖):

```
$ ./build/vst_probe $PWD scratch-probe build/vst_probe_main.nim    (import core/results; manifest 없음)
[INFO] hub: manifest missing/unreadable … no closure (fail-closed; run bin/precompile_gates)
[INFO] hub: axiom: transitive closure unresolved for scratch-probe — no CAS key, forcing compile (DEBT#449/#450)
hash=EMPTY(fail-closed)
cas=REFUSED(no-key-or-no-binary)
```

→ **매니페스트 부재를 cache HIT로 취재하는 경로는 존재하지 않는다.**

FLAGS 불일치 fail-closed(실전 관측 + 통제 위조): `--mm:arc` 프로파일 추가 직후(구플래그 매니페스트 상태) `manifest FLAGS profile mismatch … no closure (fail-closed; regenerate manifests)` 관측; 위조 `FLAGS=--hints:on…` 편집에도 `hash=EMPTY` + `cas=REFUSED` 관측 후 원복.

### 위조 매니페스트 fail-closed — 구현 결함 1건 발견·수정 (정직 기록)

**발견**: 최초 부정 테스트에서 위조 `NIM_SHA256`에 `hash=1d1543ab14e3c093`(비빈!)이 관측됐다 — fail-open이었다. 원인: `loadProjectClosure`가 클로저 루프에서 `result`에 파일을 적립한 **뒤**의 검증 실패(툴체인 신원·프로브 라인 등)가 `result`를 비우지 않은 채 `return`해 부분 클로저(프로브 2파일 제외 37파일 merkle)가 새어나갔다. 루프 내 4개 return(`relative closure line` 등)도 동일 구조 위험이었다.
**수정**: 전수 검증 통과 시에만 지역 `files`를 `result`에 단일 할당하는 구조로 재작성(모든 실패 return은 `@[]` 그대로).
**재시험(수정 후 관측)**:

```
위조 NIM_SHA256 → [INFO] toolchain identity mismatch … no closure (fail-closed)
                   hash=EMPTY(fail-closed)  cas=REFUSED(no-key-or-no-binary)
위조 FLAGS      → hash=EMPTY(fail-closed)  cas=REFUSED(no-key-or-no-binary)
원복            → hash=fee31c9c10ee8980   cas=…/layer-enforcement-gate-fee31c9c10ee8980-…/binary
매니페스트 부재(회귀) → hash=EMPTY cas=REFUSED 유지
```

→ 부정 테스트가 커밋 전 실제 결함을 잡은 사례다(§0.9 극장 금지의 실행). 매니페스트 부재·위조 모두 cache HIT 경로가 존재하지 않는다.

## §7. 구 공급자에서 발견된 결함 (본 슬라이스 범위 밖 사유 기록)

1. **path-form 분열(구 공급자)**: 구 merkle 입력이 메인 모듈 경로 형식에 민감 — precompile(상대경로 메인, 키 `c8168652…`) vs gate_hook AOT 가드·executor(절대경로, `535bba66…`)가 **서로 다른 키**를 써 hook 측은 항상 MISS. 신규 공급자는 절대경로 정규화로 해소(§5 HIT/MISS의 모든 키가 양측 동일 경로 기반). — 신규 공급자가 수정했으므로 부채 아님(본 문서가 기록).
2. **gate_hook AOT 가드 확장자 공백(미수정, FROZEN)**: `src/gate/runners/gate_hook.nim:399` `repoRoot / g.entry` — entry 54개 중 **40개가 `.nim` 확장자 없음** → `fileExists` 거짓 → CAS-miss 프리플라이트가 최대 14개만 실제 검사. `src/gate/**`는 §-1 동결 → 부채 등록(§9).

## §8. 비용 데이터 (성능 최적화 금지 — 기록만)

| 항목 | 관측치 |
|---|---|
| 매니페스트 직렬 재생성 (54게이트) | 83.9s(run2) / 92.0s(run3) / 67.2s(runB1, 웜 캐시) |
| 전체 precompile wall | 78.9s(구 baseline) → 6m17s(run2) → 330s(run3) |
| 선택적 재컴파일 | 57.0s(52게이트) / 6.7s(3게이트) |
| 파일럿 캡처 | ~1.23s/게이트 (콜드) |
| 프로브(비릴리즈 도구) | hash+CAS resolve 1회 ~5–10s (nim 바이너리 sha256 포함) |
| precompile 무조건 재생성 비용 | 매 실행 +67–92s (correctness-first 트레이드오프 — §1) |

## §9. 부채 등록

`data/debt_registry.json`에 4건 등록 (2026-11-08, source `vst_dependency_authority_handoff_2026-11-08`):

| ID | 요지 | 상태 |
|---|---|---|
| DEBT#520 | gate_hook CI AOT 프리플라이트가 `repoRoot / g.entry` 확장자 미해석으로 54개 중 40개 entry를 검사 건너뜀 (FROZEN — §7.2) | open |
| DEBT#521 | pre-push/pre-commit 훅 genDepend 캡처가 user-cfg를 skip하지 않음(머신 국소 클로저 위험; 훈화 프로파일은 §4) | open |
| DEBT#522 | 매니페스트 무조건 직렬 재생성(64–92s/run)·nim 바이너리 sha(~3.5s/호출, 비릴리즈) 비용 — 성능 후속용 데이터 | open |
| DEBT#523 | 클로저 기반 CAS 키의 워크트리 간 이원성: 4/54 게이트 바이너리가 체크아웃 경로를 바이트에 포함(측정 에이전트 관측) — 현재 per-worktree CAS라 허위 재사용 경로 없음; 워크트리 간 CAS 공유 도입 전 구조 제약 | open |

## §10. Follow-up (범위 밖 발견 — 확장 불비)

1. gate_hook AOT 가드 확장자 공백(§7.2, DEBT#520) — FROZEN 해제 후 `resolveGateSourcePath` 재사용으로 수정.
2. pre-push 훅 자체의 genDepend 프로파일 user-cfg 구멍(DEBT#521) — 훅 수정은 본 슬라이스 밖.
3. 성능 후속(DEBT#522): 매니페스트 무조건 재생성의 증분화(정확성 계약 위반 없이), 병렬 캡처 — 비용 데이터는 §8.
4. `unified_gate_runner` 제외: 타깃 세트(`manifest.d` _index)에 애초 없음 — 문서로만 기록.
5. **워크트리 간 바이너리 이원성(DEBT#523)**: 4/54 게이트 바이너리가 체크아웃 경로를 바이트에 포함(측정 에이전트 관측). 클로저 CAS 키는 소스 내용만 해싱하므로 동일 커밋의 두 워크트리가 같은 키·다른 바이너리를 갖는다. 현재 per-worktree CAS(각 워크트리 `.axiom/cache`)라 허위 재사용 경로 없음 — **워크트리 간 CAS 공유를 도입하기 전 반드시 재검토**할 구조 제약.

## §11. 리베이스 노트 (2026-11-08, base 이동)

본 슬라이스 작업 중 원격 main이 이동했다 — PR #15–#17 착지로 base `5e740d7` → `9db1dd512a` (#17 "catalog runtime root resolution seam + TWS rotation"; 사용자가 핀 회전 1회 수행). 작업 브랜치를 리베이스했다:

- 충돌 2건(`data/debt_ledger.json`, `data/nimtry_baseline.json` — 생성물)은 main 측으로 해소 후 드리프트 파이프라인(regen-arch·nimtry baseline·codegen·sync-budget)으로 재생성 → `bin/debt_engine --validate` 1598/1598 green.
- 부채 ID 충돌 없음: main 최대 DEBT#519 그대로 → 본 슬라이스 #520–523 유효 유지.
- **리베이스 트리 재검증 (run6)**: `bin/precompile_gates` EXIT=0 — `All gate binaries up to date (54 gates)`. 사용자 PR의 변경(axiom_engine·external_subject_registry·type_registry_metadata 등)은 게이트 클로저 해시에 무영향 — 54/54 키 안정.
- 리베이스로 커밋 `67de9ae` → `522a3f1` (내용 동일, base만 이동).

## §12. 재현 명령

```
AXIOM_HERMETIC_BUILDING=1 nim c --hints:off --nimcache:build/nimcache_ci/precompile_gates \
  -o:bin/precompile_gates src/cli/precompile_gates.nim
bin/precompile_gates          # 매니페스트 재생성 + 키 계산 + 선택적 재컴파일, EXIT=0이면 성공
python3 …                      # HIT/MISS 집계 (§5 스크립트)
```

## §13. 착지 과정 발견 — 504 인프라 플레이크 + core purity 게이트 위반·수정 (2026-11-08)

### 13.1 merge queue 504 플레이크 (시도 1–4)

큐 검증(merge_group/landing venue)이 4회 연속 **GitHub release-asset 다운로드 게이트웨이 504**로 좌초했다 — 코드와 무관:

- 1차(09:01Z): `attest / build-base-artifacts`의 "Fetch pinned jq 1.7.1" — `curl 504`×4, exit 22 → 아티팩트 미생성 → 8잡 연쇄 실패 → 큐 퇴출.
- 2차(09:13/09:16Z): `gateway / select` choosenim 504 + jq 504.
- 3차(09:26Z~): 동일 조합.
- 4차(09:38Z~): choosenim 통과, jq 504.
- 로컬 프로브 검증(09:41–09:42Z): `jq-linux64`/`jq-linux-amd64` 자산 = 즉시 504 (3/3), `choosenim-0.8.16` 자산 = 302 정상, GitHub API상 자산 state="uploaded" — **jq 릴리스의 자산 서빙 샤드 부분 장애** (GitHub 스테이터스 미선언). 09:46:07Z 로컬 프로브 302 회복 관측.

### 13.2 5차 시도 — 실제 게이트 위반 발견 (flake가 가려던 것)

5차(09:47Z)에서 다운로드가 통과하자 **landing venue 전용 게이트**가 처음 실행됐고, `admission-independents`의 "Core purity gate (B-built judge on _candidate tree)"가 FAIL:

- `gate/closure_manifest.nim:212, 262: io_primitive — readFile( (observed 2, anchored 0)`
- `gate/gate_cas.nim: io_primitive — readFile( (observed 7, anchored 6)`

**원인 분석**: core purity 게이트(`tools/ci/core_purity_gate.nim`)는 src/core의 원시 I/O 원시자(r2)를 baseline 래칫으로 금지하며, 승인은 오직 baseline anchor(아키텍트 등록)뿐이다 — 소스 마커는 면허가 아니다. CI의 judge·baseline은 base(main)에서 온다(헤더 주석: "the judge and its policy come from the base commit, the payload from the head") — PR이 baseline을 넓힐 수 없다. 본 슬라이스의 신규 `readFile` 3건(gate_cas.nim:86 Merkle 파일 해싱 — 본 PR 추가; closure_manifest.nim:212 매니페스트 로드·:262 nim 바이너리 읽기 — 신규 파일)은 미승인이었다. PR(pull_request) venue는 preflight만 실행해 이 게이트가 안 돌았으므로 PR-head 체크 전부 green으로는 발견 불가였다.

### 13.3 수정 — 승인 I/O 경계 경유

아키텍트 승인 경계 `src/core/io/io_utils.nim`(`readFileOpt`, Result 래핑)로 3건 교체:

- `gate_cas.nim` computeTransitiveSourceHash: `readFile(f)` → `readFileOpt(f)` + isErr → "" (동일 fail-closed)
- `closure_manifest.nim` loadProjectClosure: 매니페스트·nim 바이너리 읽기 → `readFileOpt` (동일 실패 시 no-closure 로그·return)
- `core/types/results` 직접 import 추가(Result accessor가 stub 체인에서 re-export되지 않음 — 타 core 파일 관용구와 동일)

동작 불변 관측: 프로브 `hash=fee31c9c10ee8980` ×2회 동일(해당 게이트 클로저는 gate_cas 미포함), `bin/precompile_gates` — 클로저가 gate_cas·closure_manifest을 포함하는 3게이트(binary-freshness-gate·cli-build·integrity-workflow)만 선택적 재컴파일(3 compiled/0 failed), 재실행 시 `All gate binaries up to date (54 gates)` — 키 안정·멱등. `bin/debt_engine --regen-arch`(gate_cas.nim canonical hash 1건 갱신) 후 `--validate` 전 green. `make check-arch` green.

### 13.4 위조 검증 (forge check)

수정 전 코드로 로컬 게이트(`bin/core_purity_gate`, baseline·도구가 main·base·브랜치에서 바이트 동일함을 확인 후 사용)가 CI 실패를 **메시지 단위로 동일 재현**했다(stash → FAIL 2 regression, 동일 파일·행·observed/anchored 수치 → 복원 → PASS). 로컬 판정 ≡ CI 판정.

