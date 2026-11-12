# EF CAS per-worktree 격리 실증 + 무결성 관측 분리 — 실행 증거 (2026-11-09)

> **종류**: 실행 증거(execution evidence)다. CAS 게이트 캐시의 per-worktree 물리 격리(E-3)와 캐시 무결성(누락·변조, 별개 속성)에 대한 원시 관측 패키지를 정식 증거로 착지하는 문서다. 모든 판정은 기계 관측이며, 각 수치의 출처(원시 기록)를 명시한다. 관측되지 않은 것을 검증됨으로 주장하지 않는다(§0.9 극장 금지).
> **원시 기록**: `~/.cache/axiom/ef-lab/` — `timing.txt`(실행별 wall·rc·시각), `a-run1|a-run2|b-run1|b-run2|b-run3-missing|b-run4-tamper.out`(precompile 전체 출력), `a|b-keys.txt`(casKey 집합), `a|b-digests.txt`·`joined.txt`·`digest-verdict.txt`(digest 행렬), `a|b-mtimes-*.txt`(HIT 판정 mtime 스냅숏), `missing-*.txt`·`tamper-*.txt`(무결성 관측 digest·size·mtime), `path-embedding.txt`(경로 삽입 물증), `compare_digests.sh`(비교 하네스). 저장소 외부 로컬 경로(재검증 가능 유일 원본).
> **관측 기반**: main `9c5de9e` (2026-11-09, PR #33 merge — 본 관측 착지 시점 main tip). 관측 워크트리 `ef-wt-a`·`ef-wt-b`는 **동일 커밋 detached 체크아웃, 절대경로만 상이**. 본 관측 이후 PR #34(ζ gendepend-lever)가 main에 합류(`0f863e9`)하여 §11에서 동일 실험을 재실행·재확증했다(격리 판정 불변).
> **관측 환경**: nproc 16, Nim 2.2.10(choosenim), Ubuntu Linux, gcc 13.x. 실험 종료 후 두 워크트리는 `git worktree remove`로 정리(원시 기록만 잔존). main 저장소의 기존 `.axiom/cache/gates/`(169엔트리)는 미접촉 — 실험은 전용 워크트리에서만 수행.
> **브랜치**: `workstream/ef-cas-isolation` (base: main `07de680`). 본 슬라이스는 **문서 1종 + 부채 레지스트리 연계만 — 게이트 소스·빌드 레시피 0변경, F 코드 0변경**(Owner 판정 2026-11-09, §7).

---

## §1. 방법 (재현 하네스)

- 실험 대상은 두 개의 **동일 커밋·상이 절대경로** 체크아웃: `git worktree add --detach ~/.cache/axiom/worktrees/ef-wt-a $SHA` · `ef-wt-b` 동일(`9c5de9e`).
- `bin/`의 게이트 도구 바이너리는 git 비추적 로컬 산출물이다(`git ls-files bin/` = `axiom.nim` 1파일). 따라서 각 워크트리에서 **현행 main 레시피 그대로** 도구를 먼저 빌드한다: `make -f ci/checker.mk ci-compile-precompile-gates` (checker.mk:539 — `AXIOM_HERMETIC_BUILDING=1 nim c -d:release -d:axiomNoLto --nimcache:build/nimcache/ci-compile/precompile_gates -o:bin/precompile_gates src/cli/precompile_gates.nim`; γ §10과 동일 방법론, 레시피 변경 0건). 도구 빌드 rc=0(A·B).
- 이후 각 워크트리에서 `./bin/precompile_gates`를 실행하고 관측한다. 모든 런의 wall은 `date +%s.%N` 차, rc·출력은 그대로 파일 보관.
- **HIT(캐시 재사용) 판정 방법을 명시한다** — 세 독립 신호가 일치할 때 HIT로 판정했다: (a) 도구 출력 라인(`All gate binaries up to date (54 gates)` + `Nothing to compile`, 컴파일 진행 라인 부재), (b) `.axiom/cache/gates/*/binary` 54개의 **mtime이 재실행 전후 불변**(`find -printf %T@` 스냅숏 diff), (c) wall 구성이 매니페스트 재생성(~65s) 스케일이고 컴파일 루프(`Done in … compiled`) 부재.

## §2. E-3 관측 행렬 — 교차 워크트리 격리 (코드 불변)

| # | 관측 항목 | 결과 | 원시 기록 |
|---|---|---|---|
| 1 | A 첫 실행 | MISS→빌드: `No lock file found -- compiling all gates` → `Done in 49.5s: 54 compiled, 0 cached, 0 failed`, wall 117.67s(매니페스트 64.7s + 컴파일 49.5s + 오버헤드) | `a-run1.out` |
| 1' | B 첫 실행 | MISS→빌드: 동일 구조, `Done in 48.7s: 54 compiled, 0 cached, 0 failed`, wall 118.07s(매니페스트 66.0s + 48.7s) | `b-run1.out` |
| 2 | casKey 집합 동일성 | `ls .axiom/cache/gates \| sort` A·B **54키 완전 동일**(diff 빈 출력) — 키 계산이 체크아웃 경로를 포함하지 않음(under-keying) | `a-keys.txt`·`b-keys.txt` |
| 3 | 공통 casKey digest 비교 | **same=50 / diff=4** — `hotspot-gate`·`integrity-test`·`integrity-workflow`·`readiness-start-gate`의 binary SHA-256이 A/B 상이, 나머지 50개 바이트 동일 | `joined.txt`·`digest-verdict.txt` |
| 4 | 자연 HIT(A·B 각 재실행) | `All gate binaries up to date (54 gates)` + `Nothing to compile`, rc=0, wall 68.34s/69.92s, **54 binary mtime 전부 불변**(A·B 양측) | `a-run2.out`·`b-run2.out`·`a|b-mtimes-*.txt` |
| 5 | 교차 조회 부재 | 코드 사실(§5: 모든 조회 경로가 repoRoot 하위) + 관측 종합: **A의 캐시가 54키 완전 충전인 상태에서 B 첫 실행이 54 compiled / 0 cached** — B는 A의 바이너리를 가져오지 않고 전량 자체 빌드했다. B가 A의 바이너리를 가져왔다면 digest가 동일했을 것이다(§3의 50개가 그 증거 구조) | `b-run1.out` |

**관측 3의 4게이트 digest 발췌**(`joined.txt`, 형식: casKey A-digest B-digest):

```
DIFF  hotspot-gate-2b4e43a4510839b1-2127f750231f4a04   A=c08760db…7e544be  B=4331898a…4260c91f
DIFF  integrity-test-57c53022a702799e-2127f750231f4a04  A=bde1f0a5…4666283  B=423cf7eb…390b0187
DIFF  integrity-workflow-112490e1acac397b-…             A=4900b5e4…f284251ce  B=ee11f902…038d6c2c0
DIFF  readiness-start-gate-6850ea1d0464023e-…           A=45fb9947…c8b08c97  B=01645beb…3dc8ae963
TOTAL=54  same=50  diff=4
```

**판정 (E-3)**: 동일 커밋·상이 절대경로의 두 체크아웃이 (a) 동일한 casKey 집합을 계산하며(관측 2 — under-keying 재확증, γ §8), (b) 각자 자체 캐시에 자체 빌드하며(관측 1·1'), (c) 상대방 캐시를 조회하지 않는다(관측 5). **CAS 공유 범위 = 워크트리 내부는 관측된 물리 사실이다.** 4/54 상이 digest는 B가 자체 빌드했음의 물증이자 동시에 키↔이진 정체성의 과소 표현(§6)이다.

## §3. 4게이트 경로 삽입의 기전 — 이진 레벨 정밀화 (γ §8 심화)

관측 3의 4게이트는 모두 "체크아웃 절대경로가 최종 바이너리 바이트에 도달한" 게이트지만, 그 양상이 **두 류**로 관측됐다(`path-embedding.txt`):

**류 1 — 평문 경로 삽입(NIM_STRLIT)**: 최종 바이너리에 워크트리 절대경로가 평문으로 존재.
- `integrity-workflow`: 각 6건(A·B 동수). 예(A): `@/workspace/.cache/axiom/worktrees/ef-wt-a/.axiom/debug_mode_on`, `@…/ef-wt-a/.axiom/gate_history.jsonl` 등. 소스 근거: `const REPO_ROOT* = repoRootConst()` → `DEBUG_MARKER`·`HISTORY_PATH` 상수(src/gate/runners/integrity_workflow.nim:41-43) — 컴파일 타임에 절대경로가 문자열 리터럴로 굽는다. γ §4의 .c 본문 NIM_STRLIT 6건과 최종 바이너리 strings 수가 정확히 일치.
- `readiness-start-gate`: 각 1건 — `@/…/worktrees/ef-wt-a/src/gate/runners/readiness_start_gate.nim`. 소스 근거: `currentSourcePath()` 기반 루트 해석(readiness_start_gate.nim:59). γ §4의 1건과 일치.

**류 2 — 평문 없는 경로 유도 심볼 맹글 해시**: 평문 경로는 없으나 경로에서 유도된 해시가 심볼명에 들어감.
- `hotspot-gate`: 18,266바이트 상이(영역: `.note.gnu.build-id` 945-964, `.rodata` 3B, `.symtab`/`.strtab` 대역). A 전용 심볼 `NTIv2__9b1Ue0BjrbFo9cef1rpMch9aQ_` ↔ B 전용 `NTIv2__oXPiFs3wQbu9bBfEexZHB2g_`(동일 오프셋 대응). Build ID 상이(`98d97225…` vs `178c72b0…` — 산출 차이의 결과로 연쇄 반영).
- `integrity-test`: 4,680바이트 상이 + **크기 차이**(A 88,184B vs B 88,176B — 해시 문자열 길이 차 반영). A 전용/B 전용 NTIv2 심볼은 hotspot-gate와 동일 쌍(`NTIv2__9b1Ue0…` / `NTIv2__oXPiF…`) — 두 게이트 클로저가 공유하는 멤버의 type-descriptor(v2) 맹글 해시가 경로 유도로 판단된다.
- `NTIv2__*`는 Nim type-info(v2) 심볼이며 맹글 해시에 모듈 경로가 유입된다. 평문은 없지만 바이트 원인은 경로다.

**대조군(결정론 확인)**: 나머지 50게이트는 **바이트 완전 동일** — 동일 입력·동일 도구Chain·상이 경로에서도 경로가 산출물에 유입되지 않으면 산출은 결정론적이다. 따라서 4게이트 차이의 유일 설명 변수는 체크아웃 절대경로다(γ §6.1의 직렬 vs -j4 산출 동일 관측과 정합).

**γ §8 대비 정리**: γ는 4게이트의 원인을 §4 층2(본문 NIM_STRLIT 절대경로)로 돌렸다. 본 관측은 이진 레벨에서 이를 정밀화한다 — 층2 평문은 정확히 2개(integrity-workflow 6건·readiness-start-gate 1건, γ §4의 .c 관측 수치와 일치)이고, 나머지 2개(hotspot-gate·integrity-test)는 평문 없는 경로 유도 심볼 해시(류 2)다. **under-keying 판정(동일 키·상이 바이너리 4/54)은 불변** — 어느 류든 경로가 바이트에 도달하면 키는 이진 정체성을 과소 표현한다.

## §4. 무결성 관측 — 격리와 **별개 속성** (분리 기록)

> 격리 증명(§2: 캐시가 워크트리 내부에 물리적으로 닫혀 있다)과 무결성 검증(캐시 산출물의 저장 후 변조·누락에 대한 판정)은 **서로 다른 속성**이다. 본 절은 후자를 별도로 관측·기록한다. 폐기 가능한 `ef-wt-b`에서 수행.

### 4.1 누락(MISS) — fail-closed 관측

경로 불포함 게이트(동일 digest 50개 중) `anti-theater-gate`의 `binary`를 삭제 후 재실행:

```
[INFO]  [precompile] All gate binaries up to date (54 gates)
[WARN]  [precompile] CAS binary missing for anti-theater-gate -- rebuilding from source hash
[INFO]  [54/54] … [1/1] anti-theater-gate... OK
[ERROR] [precompile] Done in 4.1s: 1 compiled, 0 cached, 0 failed    (wall 74.89s = 매니페스트 65s대 + 재빌드 4.1s)
```

- 재빌드된 binary SHA-256 = `408061b6e2629449…75b26f` — **삭제 전 digest와 바이트 동일**(`missing-before.txt` == `missing-after.txt`). 누락은 감지되고(WARN) 재빌드되며(결정론 복원), 조용한 스킵 경로는 없다. **fail-closed 관측 근거**: 코드상 누락은 `fileExists` 실패 → MISS(`gate_cas.nim:244-248` allowJit=false 경로) 또는 락 경로의 재빌드 분기(`precompile_gates.nim:546-551` — `resolveCasBinaryPathWithHash`가 ""를 반환하면 `gatesToCompile`에 재추가).

### 4.2 변조(TAMPER) — 관측된 그대로

경로 불포함 게이트 `asset-hygiene-gate`의 `binary`에 16바이트 append(`TAMPER-APPEND-EF`) 후 재실행:

| 시점 | digest(SHA-256) | size | mtime(unix) |
|---|---|---|---|
| 변조 전 | `6ee53600d1ab5c36…7ce4a20` | 194,160 | 1794183448(최초 빌드) |
| append 직후 | `66d22e81d90e7c4a…9ac3d283` | 194,176 | 1794183939(append 시각) |
| **재실행 후** | `66d22e81d90e7c4a…9ac3d283` **(불변)** | 194,176 | **1794183939(불변 — 재작성 없음)** |

```
[INFO] [precompile] All gate binaries up to date (54 gates)
[INFO] [precompile] Nothing to compile     (rc=0, wall 69.40s — 컴파일 루프 0)
```

- **관측된 동작: 변조 미검출 — 재컴파일 없이 변조 바이너리가 그대로 재사용 판정된다.** 코드상 원인: 재사용 판정이 `fileExists` 기반이며(`gate_cas.nim:241-242` `compileGateToCas`, `:180` `resolveCasBinaryPathWithHash`, `:202` `resolveCasBinaryPath`; 락 경로 `precompile_gates.nim:546-551`) 저장 시점에 digest를 기록·비교하는 경로가 없다(`getBinaryHash`:156-166는 존재하는 바이너리의 해시를 계산하는 API일 뿐, HIT 판정에 사용되지 않는다).
- 이 관측은 예상(코드 예측)과 일치했다. 격리(§2)가 성립해도 무결성 검증은 별개 속성임이 분리 관측으로 확정된다.
- **위협 모델 한정**: 현재 위협은 성립하지 않는다 — 캐시 디렉터리가 워크트리 내부(로컬 단일-작성자 신뢰 경계)에 있고, 빌드 직후 산출물이 외부 개입 없이 저장되는 한 저장 후 변조는 시나리오 밖이다. 위험이 성립하는 조건(공유 캐시·다중 작성자·외부 변조 도입)과 함께 **조건부 부채 DEBT#524로 등록한다**(§9).

## §5. 코드 인용 — 격리·무결성의 구조 사실 (전부 현행 main `9c5de9e`)

`src/core/gate/gate_cas.nim`:
- `CasDirName`(:17) = `"gates"` — 캐시 최종 구성요소.
- `computeCasKey`(:112-127) — `<gateId>-<srcHash[:16]>-<cfgHash[:16]>` (+선택 transitive). **입력에 체크아웃 경로 없음** — 관측 2(동일 키 집합)의 코드 근거. cfgHash는 `computeBuildEnvHash`(gate_memo.nim:231 — Nim 해시·config.nims·axiom.nimble 등 환경 지문)로, 역시 경로 불포함.
- `resolveCasDir`(:140-146) — `<repoRoot>/.axiom/cache/gates/<casKey>`. **repoRoot 하위 경로만 구성** — 교차 워크트리 조회 경로 부재의 코드 근거.
- `getBinaryHash`(:156-166) — `<repoRoot>/.axiom/cache/gates/<casKey>/binary`의 SHA-256. 조회 범위가 repoRoot 하위로 한정.
- HIT = `fileExists`(:180 `resolveCasBinaryPathWithHash`, :202 `resolveCasBinaryPath`, :241-242 `compileGateToCas` "Skip compilation if CAS binary already exists") — **내용 검증 없이 존재만으로 재사용 판정**(§4.2 관측의 코드 근거).
- 누락 MISS(:244-248) — `allowJit=false` 시 `CAS MISS … Run: bin/precompile_gates` 오류 안내 후 `""` 반환(게이트 실행 경로의 fail-closed).
- no-key fail-closed(:99-106) — 클로저 미해결 시 `""`(키 없음 → 컴파일/실행), 약한 키로의 대체 금지(DEBT#449/#450).
- 원자적 rename(:275-277) — `binary.tmp` → `binary`(safeMoveFile; `precompile_gates.nim:337-339`의 컴파일 루프 동일).

`src/cli/precompile_gates.nim`:
- `findRepoRoot`(:34-42) — `getAppDir()` 앵커 탐색, 미발견 시 `""` → `quit(1)` fail-closed. 각 워크트리가 자기 루트를 해석한다.
- `LockCacheDir = ".axiom" / "cache"`(:21)·`PrecompileNimcacheBase`(:22) — 워크트리 상대 경로.
- 병렬 컴파일 사전 HIT 점검(:293-296) — `resolveCasBinaryPathWithHash` 결과가 있으면 `cached`로 스킵(fileExists 기반).
- 게이트별 nimcache 격리(:299) — `repoRoot / PrecompileNimcacheBase / job.gate.gateId`.
- 누락 재빌드 분기(:546-551) — 락은 최신인데 CAS binary가 없으면 `CAS binary missing … rebuilding from source hash`(§4.1 관측의 코드 근거).

**관측 종합(관측 5)**: 위 전부가 repoRoot 하위 경로만 참조하며, 체크아웃 경로를 키·조회 어느 쪽에도 사용하지 않는다. B의 첫 실행(54 compiled / 0 cached, A 캐시 충전 상태)은 이 코드 사실의 실증이다.

## §6. 키 유효 범위 계약 — "CAS 키는 워크트리 네임스페이스 내부에서만 유효"

본 관측이 확정하는 계약:

1. **키 성분**: gateId + 클로저 Merkle 루트(소스 내용만) + buildEnvHash(도구Chain·config 환경 지문). 체크아웃 절대경로 불포함(§2 관측 2).
2. **키의 유효 범위**: 키는 그것을 계산한 워크트리의 물리 캐시 디렉터리(`<worktree>/.axiom/cache/gates/`) 네임스페이스 내부에서만 유효하다. §2의 격리 관측 5항목이 이 범위의 물리적 성립을 실증한다.
3. **동일 키·상이 digest 상존의 의미**: 이는 버그가 아니라 **키 유효 범위의 경계 표현**이다. 키의 내용 주소성은 소스 클로저에 대해서만 성립하고, 이진 산출물 정체성은 경로 의존(§3의 2류). 4게이트의 상이 digest는 범위 **내부에서는 무해하다**(그 키로 그 워크트리가 빌드한 산출물이 그 디렉터리에 있을 뿐, 허위 재사용 경로가 없다 — γ §8 "현재 영향: 없음" 재확증).
4. **범위 밖 조회의 의미**: 만약 워크트리 밖(공유 캐시 등)에서 동일 키를 조회하면 §3의 상이 바이너리 중 어느 하나를 **키가 구분하지 못하는 채** 얻는다 — 허위 재사용. 이것이 크로스워크트리 공유 도입 전 under-keying 해소가 선행되어야 하는 이유다(γ §8·§12-2, DEBT#523).

**DEBT#523 재개 조건(공유 캐시 설계 개시의 3전제)**: ① 경로 포함 바이너리의 정체성 구분(이진 자체 콘텐츠 주소화 또는 경로 스크럽 빌드 — 단 §10의 GCC 근거 참조) ② 공유 캐시 쓰기·읽기 권한 정의(단일 작성자·읽기 전용 소비 등 신뢰 경계 명문화) ③ 캐시 키 ↔ 아티팩트 정체성 일치 검증(stored-digest 비교 — §4.2의 변조 미검출 관측과 직결, DEBT#524).

## §7. Owner 판정 trace

- **2026-11-09 Owner 판정**: "CAS 공유 범위는 현재 워크트리 내부로 한정한다." E(본 실증 관측) 승인, F(신규 병렬화) **기각**.
- 최초 판정 문서의 '권고' 표현은 이 최종 판정으로 **확정**된다: γ(vs2b3 §12-2)의 "크로스워크트리 CAS 공유 설계 시 §8 under-keying 해소 선행"은 향후 검토 권고였으나, 본 판정으로 공유 범위가 워크트리 내부로 **정책 고정**된다(재개는 §6의 3전제 충족 시에만).
- 본 슬라이스는 이 판정을 이행한다: 게이트 소스·빌드 레시피 0변경, F 코드 0변경 — 관측(§2·§4) + 문서(본 문서) + 부채 연계(§9)만.

## §8. 판정 문서 UNKNOWN 정정 6항

| # | 항목 | 정정(본 관측 기준) |
|---|---|---|
| 1 | V1 per-worktree 물리 격리 | **관측 사실로 확정** — 본 문서 §2 관측 행렬(동일 커밋 2체크아웃: B 자체 54 빌드·교차 조회 부재·HIT는 자기 캐시에서만). 코드 사실 §5. |
| 2 | V3 4게이트 경로 삽입 원인 | γ §8의 "층2 NIM_STRLIT"을 이진 레벨에서 2류로 **정밀화**(§3): 평문 NIM_STRLIT 2게이트(integrity-workflow 6건·readiness-start 1건) + 평문 없는 경로 유도 NTIv2 심볼 해시 2게이트(hotspot·integrity-test). under-keying 결론(4/54) 불변. |
| 3 | F MUST 안전한 쓰기(F 재검토 시) | DEBT#457의 해소 패턴이 규범적 선례: **build-once→freeze→fan-out**(레지스트리 기록 "Fixed in PR #39", 신계보 재작성 전 PR) + **게이트별 nimcache**(`precompile_gates.nim:22` PrecompileNimcacheBase, `:299` per-gate dir). 병렬화의 공유 산출물 쓰기 충돌(ETXTBSY) 구조 해법의 기존 실현. F는 기각되어 이는 조건부 참고(재개 시 MUST). |
| 4 | gateway-binaries 트리거 | 현행 main(`9c5de9e`) 정적 계약 관측: `runner-pool-acceptance.yml`은 **push@main 트리거 없음**(workflow_dispatch + workflow_call만 — ADR-0025 Amendment B "머지 이벤트에는 이 워크플로를 포함 아무것도 발화하지 않으며"). B1 hoist(candidate-build-arm, :889-903 "Compile candidate (arm, 1회)")는 release-ship L2(workflow_dispatch→workflow_call force_full)·SL-09 승격 조건에서 아키텍처당 1회 실행. 따라서 **"저빈도"도 "push@main마다 1회"도 정적 계약으로 단정할 수 없다** — 실행 빈도는 런타임 관측(executed_jobs 출력) 소관. ※원 판정의 "저빈도" 서술과 계획 단계의 "push@main마다" 서술을 모두 현행 계약 관측으로 정정한다. |
| 5 | V6 조건부 부채 등록 | **완료** — DEBT#524를 본 PR에서 등록(§9): fileExists 기반 재사용 판정의 저장 후 변조 미검출(§4.2 관측), hazard는 공유·다중 작성자·외부 변조 도입 시에만 성립. |
| 6 | F-2 근거 보존 | **보존** — F 기각 후에도 공유 캐시 설계의 근거(under-keying 해소 선행: γ §12-2 → 본 문서 §6 3전제)는 DEBT#523 trace·재개 조건으로 보존. F 자체의 병렬화 근거(γ §6: 8워커 64.6s, w8==w16 산출 동일)는 측정 기록으로 유지. |

## §9. 부채 연계

- **DEBT#523 (trace 연장, 신규 번호 아님)**: `bindingRationale`에 본 문서 trace 추가 + 최상위 `scanner`에 심화 기록(γ §9 패턴). 재개 조건 3건(§6 ①②③)이 #523의 재개 계약으로 명문화된다. under-keying 구조 제약 자체는 이미 #523이 완전 등록 — 중복 등록 금지(§0.9a·γ §9).
- **DEBT#524 (신규, 조건부)**: CAS 게이트 바이너리 재사용 판정이 `fileExists` 기반 — 저장 후 변조 미검(§4.2 관측). hazard는 캐시 디렉터리가 외부에서 변조되거나 공유·다중 작성자가 도입되는 경우에만 성립(현행 로컬 단일-작성자 신뢰 경계에서는 요구 아님). 재개 조건: 크로스워크트리/공유 캐시 도입 또는 캐시 무결성 검증 요구 시 stored-digest 비교 도입. #523과 #524는 속성이 다르다 — #523은 키↔이진 정체성(격리·공유 전제), #524는 저장 후 산출물 무결성(판정 기반). 분리 등록이 중복이 아닌 이유다.
- **투영 동기화**: #524 등록으로 open 카운트가 변동 — `bin/debt_engine --codegen`(markdown·constants 재생성) + `--sync-budget`(ledger BUDGET#005/006) 후 `bin/debt_engine --validate` EXIT=0 확인(기록: §11).
- 검증 기록: `bin/debt_engine --validate` 결과는 PR 본문·§11에 기록.

## §10. 공식 문서 근거 (Context7 재확인, 2026-11-09)

인용은 mcp__context7__query-docs로 원문을 재확인해 확보했다(Nim `/nim-lang/nim` devel · GCC GNU onlinedocs).

- **Nim doc/ic.md — "Shared compile-time counters"**: "``CacheCounter`` state cannot live in the memory of a single ``nim m`` process: **sibling modules are compiled by separate, possibly parallel processes** and would allocate from the same initial state (#26201). Instead the counters are stored in ``<nimcache>/ic.counters``, **guarded by the OS file lock ``ic.counters.lock``**." — IC(nimcache) 락의 설계 범위는 **단일 빌드 내 형제 모듈(병렬 프로세스)**이다. 독립 빌드 간 nimcache 공유를 보증하는 계약이 아니다. 같은 문서: "The file survives across builds … **a clean build need not reproduce the values of an incremental one.**" — clean≠incremental 재현 경고(증분 상태가 산출물에 유입될 수 있음의 상류 문서화). 또한 testament --ic: "Each also gets a **private nimcache**; without one they would share a cache and thrash it." — 공유 시 thrash 사례.
- **Nim doc/nimc.md — "Generated C code directory"**: "The `--nimcache` switch can be used to change the ``nimcache`` directory." / doc/advopt.txt: "`--nimcache:PATH` set the path used for generated files". — 게이트별 nimcache(`precompile_gates.nim:22,299`)·CI_COMPILE_NIMCACHE(checker.mk:29)가 사용하는 공식 스위치.
- **GCC(GNU onlinedocs, Overall Options) — `-ffile-prefix-map=old=new`**: "When compiling files residing in directory old, **record any references to them in the result of the compilation** as if the files resided in directory new instead. … equivalent to specifying all the individual `-f*-prefix-map` options." — 개별 옵션은 `-fmacro-prefix-map`(`__FILE__`·`__BASE_FILE__`·`__builtin_FILE()` 매크로 확록 재작성), `-fdebug-prefix-map`(디버깅 정보), `-fprofile-prefix-map`(프로파일 데이터). 즉 "references"는 **컴파일러가 기록하는 매크로·디버그·프로파일 참조**를 뜻하며, **소스 문자열 리터럴(NIM_STRLIT)로 굽는 경로는 재작성 대상이 아니다**. §3 류 1(평문)에는 이 스위치가 무력하고, 류 2(심볼 맹글 해시)는 애초에 prefix-map의 범위 밖이다. — 경로 스크럽 빌드는 under-keying 해소의 **충분 수단이 아니다**(γ §5 sc4 관측: BASEDIRS 정규화로도 히트율 1.49%와 정합).

## §11. 검증·수렴 기록

- **debt_engine 검증**: #524 등록 + 투영 재생성(`--codegen` 255엔트리/open 54 → constants·markdown 재생성, `--sync-budget` BUDGET#005 53→54) 후 `bin/debt_engine --validate` — **Checks: 1604 total, 1604 passed, 0 failed, EXIT=0**(2026-11-09 관측, 로그 `~/.cache/axiom/ef-lab/debt-validate-worktree-premerge.log`; #524 등록 전 기준선 1598에서 +6 — 신규 엔트리 검증 6건 추가와 정합).
- **수렴 확인(PR 전, 2026-11-09)**: 관측 기반 `9c5de9e` → origin/main `07de680`(PR #32 η merge — `docs/evidence/vs2b3_build_verdict_2026-11-09.md` 1파일만 변경, 게이트 무관). `git diff --name-only 9c5de9e..origin/main -- src/gate src/core/gate src/cli/precompile_gates.nim config/ bin/` = **빈 집합 → "convergence: unchanged (pre-PR check)"**.
- **수렴 확인(merge 시점, 2026-11-09)**: PR #34(ζ gendepend-lever)가 본 관측 후 main에 합류(`0f863e9`) — 게이트 관련 변경 3종(`src/cli/precompile_gates.nim`·`tools/ci/generate_gate_closure_manifests.sh`·`config/trusted_writer_set.json`; 매니페스트 캡처 병렬화+핀 로테이션). **"convergence: changed (at merge-time check)" → 지침에 따라 E-3을 `0f863e9`에서 재실행했다**(`ef-wt-a2`·`ef-wt-b2` 동일 커밋 detached, 원시 기록 `a2-*`·`b2-*`·`digest-verdict2.txt`·`path-embedding2.txt`):
  - 첫 실행 A/B: 각각 `No lock file → 54 compiled, 0 cached, 0 failed`(wall 67.42s/71.36s — 자체 MISS→빌드) ✓
  - casKey 집합: 54키 A/B **완전 동일** ✓
  - digest 행렬: **same=50 / diff=4, 동일 4게이트**(hotspot·integrity-test·integrity-workflow·readiness-start) ✓
  - 자연 HIT: `All gate binaries up to date` + `Nothing to compile`, 54 binary mtime 불변(A·B) ✓
  - 교차 조회 부재: B 자체 전량 빌드 ✓
  - 차이 관측: 매니페스트 생성 `serial genDepend 64.7/66.0s` → **병렬 9.5/12.1s**(PR #34 성능 반영 — "serial" 라벨 소멸). 3게이트의 casKey **값**이 이동(hotspot `2b4e43a4…`→`7cd05a35…`, integrity-test·integrity-workflow 동일 패턴; readiness-start-gate 불변 `6850ea1d…`) — #34의 캡처 변경이 클로저 산출에 반영된 것. 키 값은 캡처 세대 의존이나 **워크트리 간 동일성·격리 판정은 불변**(본 판정의 대상).
  - **결론: E-3 판정(per-worktree 격리)은 `0f863e9`에서 재확증 — 격리는 ζ의 매니페스트 병렬화에 영향받지 않는다.**
- **merge 후 최종 재확인**: η·ζ 이후 추가 게이트 merge는 본 문서 관측 밖 — 상위 에이전트가 동일 절차(§12)로 수행한다.

**원시 기록 보존 이동**(2026-11-09): §11 debt_engine 검증 로그는 실행 시점에 휘발성 `/tmp/ef-debt-validate.log`(rebase 전)·`/tmp/ef-debt-validate2.log`(rebase 후 재겅증, 동일 1604/1604)에 기록되었으나, 2026-11-09에 영구 보존 위치 `~/.cache/axiom/ef-lab/`으로 cp 이동했다(이동 후 관측: `debt-validate-worktree-premerge.log` 8,842B·`-postrebase.log` 8,854B 실재 확인 — 본 절의 경로 인용은 보존 위치 기준).

## §12. 재현 명령

```bash
# E-3: 동일 커밋 2체크아웃 격리 관측 (§11 merge 시점 재실행은 SHA=0f863e9035f7533409c252bdf703313e14d0050b로 동일 절차)
SHA=9c5de9edd449ea273d7a85ffbeace0d0cfa72bcd
git worktree add --detach ~/.cache/axiom/worktrees/ef-wt-a $SHA
git worktree add --detach ~/.cache/axiom/worktrees/ef-wt-b $SHA
for wt in ef-wt-a ef-wt-b; do
  (cd ~/.cache/axiom/worktrees/$wt && make -f ci/checker.mk ci-compile-precompile-gates \
    && ./bin/precompile_gates)   # 첫 실행: "No lock file" → 54 compiled
  (cd ~/.cache/axiom/worktrees/$wt && ./bin/precompile_gates)  # 재실행: HIT 관측
done
bash ~/.cache/axiom/ef-lab/compare_digests.sh   # casKey 집합 동일성 + digest 행렬(50 same/4 diff)

# 무결성(누락): binary 삭제 → 재실행 → "CAS binary missing … rebuilding" + digest 복원 확인
# 무결성(변조): binary에 byte append → 재실행 → "Nothing to compile" + 변조 digest 유지 확인
#   (원시 출력·digest 기록: ~/.cache/axiom/ef-lab/{b-run3-missing,b-run4-tamper}.out, tamper-*.txt)

# 실험 정리
git worktree remove --force ~/.cache/axiom/worktrees/ef-wt-a
git worktree remove --force ~/.cache/axiom/worktrees/ef-wt-b
```

## §13. Follow-up (범위 밖)

1. ~~PR #34(ζ) merge 시 E-3 최종 재확인~~ **완료(§11 merge 시점 재실행으로 흡수)** — `0f863e9`에서 관측 행렬 전 항목 재확증(격리 불변, 매니페스트 생성 병렬화 9.5-12.1s만 변화). 이후 추가 게이트 merge 시 동일 절차(§12)로 재확인(상위 에이전트).
2. 공유 캐시 재검토 시 §6의 3전제 + DEBT#524 재개 조건(stored-digest 비교)을 함께 충족할 것.
3. §3 류 2(NTIv2 경로 유도 해시)의 정확한 맹글 규칙(Nim 컴파일러 내부)은 상류 구현 세부 — 본 문서는 이진 관측 사실로 기록했다.
