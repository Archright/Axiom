# Replay Harness config.nims 상속 · 드리프트 게이트 Quirk

> §0.5b Quirk Documentation Mandate 기록 (2026-10-17 실측 — 슬라이스
> `experiments/act2-wp-toml-b1-input-integrity/p0d2f`의 `ax prove --project`
> D2 반증 실험에서 발견; 복제 실험 defect2/defect5 런 쌍의 실패 양상 변화로 확립).
> 반례 재생(counterexample replay) 하니스가 주체 저장소·작업 cwd와 결합해
> 재발견되는 툴체인·무결성 특이사항 2건.

## Q1 — 재생 하니스 컴파일이 조상 `config.nims` 체인을 상속한다 (cwd 결합)

**Class**: Nim toolchain / project config loading — [nested_worktree_config_quirks.md](nested_worktree_config_quirks.md)와 동일 기제(조상 config 다중 적재)의 재발 현장.

### Symptom

`ax prove --project`가 결함 커널의 SAT 반례 모델을 재생할 때, ax의 cwd가 Axiom3
저장소 루트 **밖**이면 하니스가 항상 `nonzero exit 1`로 죽고 재생 판정이
`rvUnavailable → cvUnresolved`(fail-closed)로 내려간다. 재생 로그:

```
[INFO] ir_pipeline_runner: [ce-replay] d2HexEscapeAppendLen — replay rvUnavailable:harness nonzero exit 1; fail-closed cvUnresolved
```

(`runs/defect2.err:29` — cwd=$EXP; 동일 하니스가 cwd=Axiom3 루트에서는 컴파일에
성공하고 이후 단계의 다른 판정으로 진행한다 — `runs/defect5.err:29`, Q2 참조.)

### Cause

반례 재생 하니스는 `<AXIOM_STATE_DIR>/.axiom/tmp/replay/<bindingSeed hash>/`에
기록되고(`src/verification/counterexample_replay.nim:483-495`) 실제 `nim c`로
컴파일된다(`:499-504`). Nim은 컴파일 대상 프로젝트 파일의 **조상 디렉터리
체인의 모든 `config.nims`를 평가**한다 — 하니스의 위치와 무관하게, 이때
적재되는 `config.nims`는 Axiom3 루트의 것이다. Axiom3 `config.nims` 체인은
`config/integrity.nims`의 cwd-상대 부트스트랩을 실행하는데, 그 명령은

```nim
const genCmd = "nim c -r --hints:off -d:AXIOM_GATE_BOND=1 -d:skipImportLint --skipUserCfg --out:" & genBin & " tools/feature_manifest_generator.nim"  # :170
...
exec genCmd  # :184 — cwd 상대 경로(`tools/…`, `bin/…`) 해석
```

이다. ax의 cwd가 Axiom3 루트 밖이면 이 부트스트랩의 상대 경로가 해석되지
못해 실패하고, `config.nims` 평가 실패 = 하니스 컴파일 자체의 실패(종료 1)로
귀결된다. 즉 **하니스 컴파일은 주체 저장소의 빌드 설정을 상속하며, 그 상속은
ax 프로세스의 cwd가 아니라 조상 체인을 통해 이루어지지만 부트스트랩의
성패는 cwd가 결정한다.**

### Evidence (복제 실험 — cwd만 다른 동일 입력)

| 런 | state | cwd | 하니스 재생 결과 |
|---|---|---|---|
| defect2 | `state_v3` | `$EXP`(저장소 밖) | `rvUnavailable:harness nonzero exit 1` (`runs/defect2.err:29`) |
| defect5 | `state_v9` | Axiom3 루트 | 하니스 컴파일 성공 → 이후 Q2 드리프트 게이트에서 `rvUnavailable` (`runs/defect5.err:29`) |

동일 결함 커널·동일 명세·동일 하니스 시드에서 cwd 하나로 실패 양상이
바뀐다는 관측이 원인을 분리한다: cwd 밖에서는 config 부트스트랩이, 루트에서는
(컴파일 성공 후) 무결성 게이트가 지배한다.

### 완화 (현행 계약 내)

`ax prove --project` 재생 수반 런의 cwd를 Axiom3 저장소 루트로 고정한다
(재현 하니스 `experiments/act2-wp-toml-b1-input-integrity/p0d2f/replay_formal.sh`의
`run_ax`가 cwd=$ROOT를 강제). 근본 해소(부트스트랩의 cwd 독립화 또는 하니스
컴파일의 `--skipParentCfg`)는 Axiom `src/`·`config/` 수정이므로 본 기록의
범위 밖이며, 개선 후보로 남긴다.

> **해결 (2026-10-18)** — 근본 해소가 `src/verification/counterexample_replay.nim`
> 하니스 컴파일 명령에 `--skipParentCfg --skipUserCfg --skipProjCfg`를 추가하는
> 방식으로 착지했다. Nim은 프로젝트 파일 경로의 조상 디렉터리 체인의 모든
> `config.nims`를 평가하므로(Nim 2.2.10 doc/nims.md + doc/nimc.md
> "Configuration files"), 스킵 플래그로 조상 체인 평가 자체를 재생 컴파일에서
> 제거하면 이 quirk의 원인(부트스트랩 상속)이 사라진다. cwd 고정 완화는
> 더 이상 요구되지 않는다. 위 기록은 발견 당시의 역사적 동작 문서로 보존한다.

## Q2 — 재생 후 정합 게이트가 주체 저장소 `git status --porcelain` 공백을 요구한다 (커밋 결합)

> **갱신 (2026-11-03 — predicate v2 `worktreeStable` 복구)**: 정합 게이트는
> 더 이상 주체 저장소 porcelain **공백**을 요구하지 않는다. G2 계약
> ("the subject tree is unchanged across the run" —
> `replay_evidence_policy.md` §4)의 구현이 실행 직전/직후의 **상대 비교**로
> 복귀했다: subject inputs digest(`git ls-files --full-name --cached
> --others --exclude-standard` + 파일별 sha256) + repo status digest
> (`--untracked-files=all`) + tracked-content digest(`git diff HEAD`)의
> pre/post 동일성. 아래 커밋 결합 제약은 이 갱신으로 해소된다 — 변이가 실행
> 중 자기 자신으로 불변인 한 작업사본 추가 방식도 관측 가능하다. 의도된
> fail-closed는 유지된다: 재생이 직접 만든 드리프트(신규 파일 생성·기존
> 미추적 파일 덮어쓰기)는 그대로 `rvUnavailable` → `cvUnresolved`로
> 봉인되며, 음성 대조는 drift probe
> (`tests/fixtures/rust/axiom_drift_probe/`, adapter-direct)가 담당한다.
> 이 갱신 이전의 기술은 발견 당시(2026-10-17)의 역사적 동작으로 보존한다.

**Class**: Zero-Footprint Integrity 게이트와 실험 워크플로의 결합.

### Symptom

cwd를 루트로 고정해도(Q1 해소) 재생이 `rvUnavailable`로 실패한다:

```
[INFO] ir_pipeline_runner: [ce-replay] d2HexEscapeAppendLen — replay rvUnavailable:subject tree drifted during replay (hash/porcelain mismatch); fail-closed cvUnresolved
```

(`runs/defect5.err:29` — Axiom3 커밋 **전**, `runs/defect6.err:29` — Axiom3 슬라이스
커밋 **후**에도 동일 문구 지속. 이 런 쌍이 검사 대상을 분리한다 — 아래 Cause.)

### Cause

재생 후 정합 검사(`src/verification/counterexample_replay.nim:514-526`)는
(i) 주체 모듈 sha256 불변과 (ii) **주체 저장소 루트**의
`git status --porcelain` **공백**을 함께 요구한다(`:519-525`). 검사 대상
repoRoot는 `--project` sourceRoot에서 스레드된다(`src/cli/axiom_engine.nim:2303` →
`resolveSubjectRepoRoot`, `src/verification/canonical_verification.nim:765`) —
Axiom3 저장소가 아니라 **변이 주체 저장소**(`env/subject_variant`)다.
변이 materialization이 주체 작업사본에 커널 파일을 추가하고 `git add -N`
(intent-to-add)으로 스테이지하므로 주체 porcelain은 ` A d2kernels.nim`이
남아 구조적으로 공백이 될 수 없다. Axiom3 쪽 트리를 커밋으로 청결히 해도
(defect6) 이 게이트에는 영향이 없다.

### Consequence (운영 제약)

(역사적 — predicate v2 이전 동작) 반례 확인(`PROPOSITION_DISPROVED`, 재생 합의)은
**주체 저장소 porcelain이 공백**일 때만
관측 가능하다 — 작업사본 파일 추가 방식의 변이로는 불가능하다. 관측하려면
변이를 주체 저장소 **안에 커밋한** materialization이 필요하다(별도 실험 변이:
baseline rev + diff + 사유 보존 — p0d2f `FORMAL_EXPERIMENT.md` §Next Experiment).
fail-closed는 설계대로 작동한다: 판정은 `cvUnresolved`로 내려가고 게이트는
그대로 FAIL — 재생 불능이 은폐되지 않는다. (이 제약은 2026-11-03 predicate
v2 복구로 해소되었다 — 상단 갱신 노트; 재생이 만든 드리프트에 대한
fail-closed는 그대로 유지된다.)

### Evidence (검사 대상 분리 — Axiom3 커밋 전후 런 쌍)

| 런 | Axiom3 트리 | 주체 저장소 porcelain | 재생 결과 |
|---|---|---|---|
| defect5 | `?? experiments/…/p0d2f/` (dirty) | ` A d2kernels.nim` | `rvUnavailable:subject tree drifted` (`runs/defect5.err:29`) |
| defect6 | 커밋 완료 (clean) | ` A d2kernels.nim` (불변) | **동일** `rvUnavailable:subject tree drifted` (`runs/defect6.err:29`) |

Axiom3 쪽 청결 여부가 결과를 바꾸지 못하므로 검사 대상은 주체 저장소다.

### 관련 기록

- 슬라이스 실행 기록: `experiments/act2-wp-toml-b1-input-integrity/p0d2f/FORMAL_EXPERIMENT.md` (후속 단계에서 추가).
- 1차 실행(exit 2 거부)의 원인인 **if-표현식 Canon 프론트엔드 갭**
  (`toCanonKind`의 `nkElifExpr`/`nkElseExpr` 매핑 부재, `convertExprCanon`의
  `ckIfStmt` 암 부재)은 본 문서의 대상이 아니다 — 위 실험 기록과 SPEC.md
  Amendment를 참조하라 (개선 후보로 추적).

## Q3 — 다중 재생 하니스의 동시 부트스트랩 경쟁 (2026-10-17 추가)

**Class**: 재생 하니스 컴파일 경로의 동시성 — Q1 부트스트랩의 확장.

### Symptom

하나의 `ax prove` 런에서 **여러 반례 재생이 동시에** 발동하면(주체 커널 + 구동
커널 범위의 부수 함수들) 재생들이 `rvUnavailable:harness nonzero exit 1`로
죽는다. main 수용 재실행(3차, `runs_r/defect_cold1.err`)에서 관측:
`ce-replay] d2HexEscapeAppendLen / calcDynamicTimeoutCore / proximityScore`
3건 동시 시도, 전부 nonzero exit.

### Cause (관측 근거 + 가설)

각 하니스 컴파일은 Q1의 조상 `config.nims` 부트스트랩을 수행하며, 그
부트스트랩은 **동일 출력 경로** `bin/feature_manifest_generator`(`nim c -r …
--out:bin/feature_manifest_generator`, `config/integrity.nims:170,184`)로
재빌드한다. 동시 재생은 같은 출력을 동시에 쓰는 `nim c` 인스턴스를 만든다 —
경쟁 패배자가 nonzero exit로 죽고, 그 상위 `nim c -r` 체인 전체가 exit 1이
된다. **분리 관측**: 동일 하니스(`state_r1/.axiom/tmp/replay/3b06b64f…/`)를
동일 명령·동일 위치·cwd=ROOT에서 **단독** 재실행하면 성공한다(exit 0,
`AXIOM_REPLAY_BEGIN/1/AXIOM_REPLAY_END` 출력 — 2026-10-17 재현). 즉 실패는
하니스 자체가 아니라 런 내 동시성에 결합된다. 경쟁 원인의 동시성 귀속은
가설로 기록한다(단독 성공 × 런 내 3건 동시 실패의 분리 관측).

### Consequence

다중 SAT 반례가 있는 런에서 재생 합의(`PROPOSITION_DISPROVED`) 관측은 이 경쟁이
해소되기 전까지 불안정하다. 완화: 재생 직렬화 또는 부트스트랩 출력
경로의 재생별 고유화 — `config/`·`src/` 수정이므로 본 기록 범위 밖,
개선 후보로 남긴다. p0d2f 수용 스크립트는 C1a(재생 합의) 미관측을
정직 분류한다(INCOMPLETE 루트).

> **해결 (2026-10-18)** — 근본 해소가 Q1과 동일한 변경으로 착지했다:
> `src/verification/counterexample_replay.nim` 하니스 컴파일 명령의
> `--skipParentCfg --skipUserCfg --skipProjCfg`가 재생 컴파일에서 조상
> `config.nims`(= `config/integrity.nims` 부트스트랩, 공유 출력
> `bin/feature_manifest_generator`로의 동시 재빌드) 평가 자체를 제거한다.
> 경쟁 원인이 사라지므로 동시 재생이 부트스트랩 재빌드에 실패하지 않는다.
> 위 기록은 발견 당시의 역사적 동작 문서로 보존한다(경쟁 원인의 동시성
> 귀속은 가설 표기 그대로 — 본 해소는 원인 제거이며 가설 검증은 아니다).

## Q4 — 주체 의존성 해석이 Nim의 lazy nimble-path 탐색에 기생한다 (cwd 결합, 2026-10-18 추가)

**Class**: Nim toolchain / import resolution — 컴파일러 내장 nimble-path
lazy 탐색의 cwd 민감성. Q1과 무관(설정 파일 상속이 아니다 — skip 플래그로
불변이다).

### Symptom

d2-agent 캐리어(`d2StringGateReject`)의 반례 재생 하니스가 주체 공개 API
(`import toml_serialization`) → `reader.nim` → `stew/[enums, objects]` 체인에서
컴파일 실패:

```
[ce-replay] d2StringGateReject — replay rvUnavailable:harness nonzero exit 1
```

결정적 분리 관측 (2026-10-18, 동일 명령·동일 하니스·동일 pristine 주체
`nim-toml-serialization@4aa8e22`):

| 호출 cwd | 결과 |
|---|---|
| Axiom3 저장소 루트 | `reader.nim(12, 7) Error: cannot open file: stew/enums`, exit 1 |
| `/tmp` (중립) | 컴파일+실행 성공 — `AXIOM_REPLAY_BEGIN` / `false` / `AXIOM_REPLAY_END`, exit 0 (결함 목격: 원 디코더가 chr(7) 문서를 거절하지 않음) |

`nim dump` 검색 경로는 양쪽 동일(일반 텍스트 dump — 이유는 아래 기제가
설명한다). 툴체인 config에 nimblePath 선언 없음(**정정 2026-10-19**:
`$nim/config/nim.cfg:63-69`에 소문자 철자 `nimblepath=` 4건이 선언되어 있다 —
`/opt/nimble/pkgs2|pkgs`와 `$home/.nimble/pkgs2|pkgs`. 2026-10-18 기록의
`nimblePath` 대소문자 구분 검색이 이 선언들을 놓쳤다). 사용자 config 비어
있음. `--skipParentCfg --skipUserCfg --skipProjCfg`로도 불변 — 이 점은
유지된다: 원인은 설정 파일 적재가 아니라, skip 플래그가 가드하지 않는
컴파일러 내장 검사다(아래 Cause).

### Cause (기제 검증 완료 — 2026-10-19, 가설 제거)

nim 2.2.10 컴파일러는 **`nimble.lock` 발견 시 nimble 경로를 전면 비활성화하는
내장 검사**를 가지며, 그 검사 지점이 passCmd1에선 호출 cwd, passCmd2에선
프로젝트 경로라는 것이 기제의 전부다. cwd=/tmp 관측에서 `stew`가
`~/.nimble/pkgs2/stew-0.5.0-db22…/`에서 컴파일되는 것(CC 힌트)은 이 lazy
확장이 생존한 경우고, 루트에서는 확장 이전에 차단된다. 소스 인용(툴체인
`~/.choosenim/toolchains/nim-2.2.10/compiler/`):

1. 위상 순서(`cmdlinehelper.nim:42-63`): `processCmdLine(passCmd1)` →
   projectPath 설정(`setFromProjectName`) → `loadConfigs`(설정 파일 적재) →
   `processCmdLine(passCmd2)`.
2. `processCmdLine`은 **양 pass의 끝에서** `nimbleLockExists`를 검사해 발견 시
   `disableNimblePath`를 호출한다(`nim.nim:83-87` — 주석: "disable nimble
   path if nimble.lock is present", nim-lang/nimble#1004 인용).
3. `nimbleLockExists`(`nim.nim:41-49`): `pd = projectPath`(비어 있으면
   `getCurrentDir()`). **passCmd1 시점엔 projectPath가 아직 비어 있어 cwd가
   검사된다.** 조상 디렉터리 스캔만 `--skipParentCfg`(`optSkipParentConfigFiles`)
   로 가드되고, `pd` 자체의 검사는 어떤 skip 플래그로도 가드되지 않는다 —
   skip 플래그 불변성의 이유다.
4. `disableNimblePath`(`options.nim:798-801`): `optNoNimblePath` 설정 +
   **`lazyPaths`/`nimblePaths` 소거**. passCmd1에서 이미 차단된 경우(루트
   cwd) 설정 적재 때 툴체인 `config/nim.cfg:63-69`의 `nimblepath=` 지시자가
   `commands.nim:648-657`의 가드(pass ∈ {passCmd2, passPP} **and**
   `optNoNimblePath` 미설정)에 걸려 no-op — 힌트 0건. passCmd2에서
   차단된 경우(아래 B2) 확장은 실행되지만 그 결과가 소거된다.
5. 소비는 import 실패 시 `rawFindFile2`(`options.nim:881-890`)의 `lazyPaths`
   검색이고 오류 지점은 `modulepaths.nim:73-77` — 목록이 비면
   `cannot open file`로 귀결한다.

즉 Q1과 달리 설정 파일 상속과 무관하다(Class 기술 그대로). nimble 경로의
**공급원**은 툴체인 `nim.cfg`의 `nimblepath` 지시자(패키지 루트를
`nimblecmd.nim:155-167`이 `walkDir` 스캔해 `lazyPaths`에 채운다)이지만, 그
확장·생존 여부를 결정하는 것은 컴파일러 내장 lock 검사다. 저장소 루트에는
git 추적 `nimble.lock`(1979B)이 있으므로 cwd=루트의 1차 검사가 즉시
발화하고, cwd=`/tmp`·`/var/tmp`에선 1·2차 검사가 모두 음성이라 확장이
생존한다. 부수 확인: 저장소 `config.nims:336-340`도 nimble v2 develop
구성으로 `switch("noNimblePath")`를 선언한다 — 저장소 자체 정책도 전역
nimble 저장소 사용을 금지하며, 재생 컴파일(skip 플래그)은 이 정책을
통과해 컴파일러 내장 검사에만 좌우된다.

### 판별자 매트릭스 (2026-10-19 — 최소 재현 `/tmp/q4probe/t.nim`, `import stew/enums`)

명령·플래그(`--skipParentCfg --skipUserCfg --skipProjCfg` 포함)·프로젝트
파일을 바이트 동일로 고정하고 cwd와 `nimble.lock` 위치만 변인화:

| # | cwd | cwd의 nimble.lock | 프로젝트 경로의 nimble.lock | 결과 | `added path` 힌트 |
|---|---|---|---|---|---|
| R0 | `/tmp` | 없음 | 없음 | exit 0 — pkgs2에서 stew 해석 | 29 |
| R1 | Axiom3 루트 | **있음**(git 추적) | 없음 | exit 1 — `cannot open file: stew/enums` | **0** |
| R2 | `/var/tmp` | 없음 | 없음 | exit 0 | 29 |
| B1 | `/tmp` | **생성**(빈 파일) | 없음 | exit 1 — R1과 동일 서명 | **0** |
| B2 | `/tmp` | 없음 | **생성**(빈 파일) | exit 1 | 29 — 확장 후 소거(위상 순서의 직접 증거) |
| B3 | 저장소 `src/` | 없음(조상에 루트 lock 존재) | 없음 | exit 0 — `--skipParentCfg`가 조상 스캔을 차단 | 29 |

- B1: cwd의 lock이 **충분 원인**임을 확정. R1 vs B3: 검사는 cwd/프로젝트
  경로 자체에 바인딩되고 조상은 skip 플래그가 있어야만 무시됨을 확정.
- B2의 역설(힌트 29건 + 실패)이 위상 순서를 교차 증명한다: 설정 적재 시점엔
  lock 미발견으로 확장이 실행되고, passCmd2 종료 시점의 projectPath 검사가
  `disableNimblePath`로 그 결과를 소거한다.

결정 증거(관측·syscall·소스 3층 일치):

- **힌트**: `--verbosity:2`에서 R0은 `config/nim.cfg(63,3)` 출처의
  `added path: '/opt/nimble/pkgs2/'` 등 29건(`compiler/nimblecmd.nim(152)`
  발화) — R1은 0건(확장 이전 차단).
- **strace**(`-f -yy -e trace=%file`): R1은 시작 직후
  `stat("…/<workspace>/Axiom3/nimble.lock") = 0` 후 pkgs2 접근 **0건**;
  R0은 pkgs2 접근 49건(`open("…/pkgs2/stew-0.5.0-db22…/", O_DIRECTORY)` 포함
  walkDir 스캔)과 `stat("/tmp/nimble.lock") = -1 ENOENT`(1차 검사의 음성).
  2026-10-18 기록의 "strace openat 추적으로는 차이가 관측되지 않았다"의
  원인: 결정 syscall은 openat이 아니라 존재 검사 `stat`(newfstatat)이고,
  스캔 자체는 fd-level `getdents64`라 `-yy` 경로 디코딩 없이는 식별되지
  않는다.
- **`nim dump`**: 일반 텍스트 dump는 양쪽 동일(기존 관측 재현) — 판별 필드
  `lazyPaths`는 JSON dump(`--dump.format:json`, `compiler/main.nim:357-390`)
  에만 노출된다. 실측: R0 `lazyPaths` 29건(stew 루트 포함) vs R1 **0건**.

### Consequence

재생 하니스 컴파일이 (i) 호스트 nimble 저장소 상태와 (ii) 호출 cwd에 암묵
결합된다 — Deterministic(동일 입력 → 동일 출력)·이식성 위반. 주체 의존성이
있는 모든 d2-agent 재생이 cwd에 따라 `rvUnavailable`이 되거나 되지 않는다.

### 해결 (2026-10-18) — 명시적 dep 루트 고정 (기제 비의존)

`src/verification/counterexample_replay.nim`의 d2-agent 재생 바인딩이 주체
의존성 루트를 **명시적 `--path:` 플래그로 고정**한다 (DESIGN (a)+(b)):

- `ReplayConfig.depSearchPaths` — d2-agent 전용 필드. 다른 모든 재생 경로
  (C_out/base36/base32, 셀프커널 부수)는 빈 시퀀스 — 제로 디프.
- 해석은 `AXIOM_REPLAY_DEP_PATHS` (':' 구분, 존재 검증 — DESIGN (b) 오버라이드)
  가 우선하고, 미설정 시 주체 트리의 import/from/export 문이
  `D2AgentSubjectDepPackages` = serialization·faststreams·stew·results
  (arnetheduck/status-im 스택)을 명명할 때만 nimble 저장소에서 발견한다:
  `pkgs2` → `pkgcache` → `pkgs` 우선 순위, 최신 버전 우선(숫자 랭크 + dirName
  타이브레이크), 루트가 최상위 모듈을 실제 제공하는지 검증. 커밋된 절대
  경로 없음 — 기계 저장소 상태의 런타임 해석이다.
- 명명된 패키지가 저장소에 없으면 fail-closed 진단(어느 패키지가, 어느 루트를
  검색했는지) — 재생은 `rvUnavailable`로 귀결하고 결코 유추하지 않는다.
- 수정은 위 기제에 의존하지 않는다: 명시적 플래그는 어떤 cwd에서도 동일하게
  해석된다. 실증 — 수동 재현 환경에서 dep 4루트 부착 시 cwd=Axiom3 루트에서도
  `AXIOM_REPLAY_BEGIN/false/AXIOM_REPLAY_END` exit 0.

## Q5 — 셀프커널 콜래트럴 하니스 컴파일이 저장소 주입 경로를 잃는다 (skip 플래그의 필연 귀결, 2026-10-19 추가)

**Class**: Nim toolchain / import resolution — Q1/Q3 해소(`--skipParentCfg
--skipUserCfg --skipProjCfg`)가 남긴 공백. 설정 파일 평가 제거는 조상
부트스트랩(경쟁)을 제거하지만, 그 설정이 공급하던 **정상 경로 주입**도 함께
제거한다.

### Symptom

`ax prove --project nim-toml-serialization` defect-leg 런(2026-10-19,
pristine @4aa8e22)에서 셀프커널 콜래트럴 재생이 항상 실패:

```
[ce-replay] calcDynamicTimeoutCore — replay rvUnavailable:harness nonzero exit 1; fail-closed cvUnresolved
```

절대 `--path:`(모듈 디렉터리)로도 동일 — cwd가 아닌 **경로 집합**의 결함이다.
수동 재현(동일 하니스·동일 플래그, 2026-10-19):

| `--path:` 구성 | 결과 |
|---|---|
| 파이프라인 그대로(모듈dir + repo/src + repo + repo/tools) | `hash_kernel.nim(10,17) Error: cannot open file: checksums/sha2` |
| + nimble `checksums` 루트 | `parser_utils.nim(6,16) Error: cannot open file: compiler/parser` |
| + nimble `checksums` 루트 + 툴체인 루트(`compiler/*` 공급) | **import 전부 해석** → 다음 장애는 Q6(아래) |

### Cause

Axiom3의 정상 빌드는 `config.nims` 체인이 경로를 주입한다:
`config/paths.nims:58` `injectAxiomDependencies(["checksums", "ed25519",
"fusion", "malebolgia", "nimcrypto"])`(pkgs2 스캔)와 `config.nims:329-333`의
툴체인 루트(`$HOME/.choosenim/toolchains/nim-<ver>` — `core/parser_utils.nim`의
`import compiler/parser` 등 컴파일러 내부 모듈용). 재생 하니스 컴파일은
Q1/Q3 해소로 이 평가를 **의도적으로** 스킵하므로, 셀프커널 모듈의 import
클로저가 nimble 패키지(`checksums/sha2`)나 컴파일러 내부 모듈(`compiler/*`)에
닿는 순간 `cannot open file`로 죽는다. d2-agent 재생은 Q4의 자체 dep 루트
해석(`depSearchPaths`)을 가지지만, 셀프커널 콜래트럴은 "빈 시퀀스 — 제로
디프" 정책이었다(의도된 제로디프가 우연한 결함 표면이 된 사례).

### 해결 (2026-10-19)

`src/verification/counterexample_replay.nim` — plain 하니스(d2-agent 스탬프
템플릿이 아닌) 렌더 경로에 한해 `subjectRepoDepSearchPaths`가 컴파일에
추가 경로를 부착한다:

1. **툴체인 루트** — 실측 `nimExe`에서 파생(`nimExe/../../`, `compiler/`
   존재 검증). config.nims의 `$HOME` 하드코드 대신 측정된 바이너리 위치 —
   GateEnvLock 툴체인 지문과 동일한 신원.
2. **nimble `requires` 루트** — 주체 저장소 루트의 `.nimble` 파일이
   선언하는 의존성(선언적 계약 SSOT — `nimbleRequiresNames`; `nim` 자체는
   툴체인이라 제외)을 기존 결정론 해석기(`resolveNimblePackageRoots` —
   pkgs2→pkgcache→pkgs, 최신 우선, 모듈 제공 검증)로 해석.

미해석 이름은 여기서 스킵(best-effort)된다 — 하니스 컴파일 자체의
`cannot open file` 오류가 관찰된 사실 그대로의 fail-closed 진단으로 남는다
(기본값 채움 = 극장). d2-agent 스탬프 템플릿 경로는 이 분기를 타지 않아
컴파일 명령이 바이트 동일하게 유지된다.

## Q6 — 커널 콜래트럴 심볼이 비공개라 `import` 하니스가 도달할 수 없다 (2026-10-19 추가)

**Class**: Nim 언어 (module privacy) — `include`의 텍스트 스플라이스와
상대 import 해석.

### Symptom

Q5의 경로를 모두 부여해도 calcDynamicTimeoutCore 하니스는 계속 실패한다:

```
replay_harness.nim(3, 7) Error: undeclared identifier: 'calcDynamicTimeoutCore'
candidates (edit distance, scope distance); see '--spellSuggest':
 (4, 6): 'calcDynamicTimeout'
```

### Cause

`src/core/orchestrator/orchestrator_topology_worker.nim:26`의
`func calcDynamicTimeoutCore(` — export 마커(`*`) 없는 **비공개 심볼**이다.
커널 스코프(`data/verification_scope.lock`)는 비공개 함수를 검증 대상으로
삼지만, Nim의 모듈 프라이버시는 `import`로는 결코 노출되지 않는다 — 하니스
래퍼가 `import <module>` + 호출 형태인 한 커널 콜래트럴 재생은 원리적으로
불가능했다(Q3 시대의 nonzero exit 관측은 이 근본 원인 위에 부트스트랩 경쟁이
겹쳐 보였던 것).

### 해결 (2026-10-19) — `include` 스플라이스 (실험 확증)

`renderReplayHarness`가 `include <module>`을 출력한다. `include`는 import와
동일한 모듈 검색 경로를 타고 파일을 **텍스트로 스플라이스**하므로 비공개
심볼이 하니스 스코프에 들어온다 — 주체 트리는 여전히 무변경(읽기만). Nim
2.2.10 실측 확증:

- 스플라이스된 파일 안의 상대 import(`import ../../core/trusted/axiom_pragmas`)
  는 **스플라이스된 파일의 디렉터리** 기준으로 해석된다(하니스 디렉터리
  기준이 아니다 — `--path:<moduleDir>`가 주체 import 체인을 고정).
- 실측: `include orchestrator_topology_worker` + `echo $calcDynamicTimeoutCore(0, 0, 0, 0)`
  → 컴파일+실행 성공, `AXIOM_REPLAY_BEGIN/5000/AXIOM_REPLAY_END`, exit 0.
- 주체 모듈이 `{.push raises: [].}`를 열어두면 스플라이스 이후 하니스 코드가
  그 영향을 받지만, 하니스는 proc 선언 없이 top-level echo만 수행해 영향
  없다. 모듈 상태 이중화(include 사본 + 타 모듈 경유 import 사본)는 순수
  함수 관찰에는 무차별 — 상태 유입 주체는 인증 서브셋 밖으로 fail-closed.

함의: plain 하니스 재생 관찰은 `import` 시멘틱스가 아니라 **주체 모듈
텍스트의 직접 평가**가 된다. d2-agent 스탬프 템플릿(공개 API import)은
변경 없다.
