# Nim genDepend Artifact Quirks (Nim 2.2.10)

> AGENTS.md §0.5 Quirk Mandate — 발견 2026-11-05 (VS-1 pre-push content-identity
> 전환 작업; 2026-11-06 pre-commit nim_check_gate 전환에서 5번 항 추가).
> 도구체인: Nim 2.2.10 (choosenim, Linux/amd64), graphviz 미설치.
> 본 문서는 관측된 툴체인 행동의 기록이며, `.githooks/pre-push` Part 4와
> `.githooks/pre-commit` Part 1의 content-identity 판정이 의존하는 실행 계약을
> 규정한다.

**Discovered**: 2026-11-05 (1-4) · 2026-11-06 (5) · 2026-11-08 (6-8, VS-T 의존성 권한 핸드오프)
**Class**: nim genDepend artifact 생성 · CWD/경로 해석

## Symptom

`nim genDepend`를 freshness 판정의 closure 진리 원천으로 쓰려면 여덟 가지
툴체인 행동이 문서화된 시맨틱과 다르게 관측된다:

1. **exit≠0이어도 `.deps`는 완전 생성된다.** graphviz의 `dot` 미설치 환경에서
   genDepend는 exit 1로 종료하면서도 `<module>.deps`(의존 파일 목록)을
   먼저 완전히 기록한다. 이때 `<module>.dot`도 기록된다(실패하는 것은
   graphviz 렌더 단계다).
2. **`.deps`의 기록 위치는 `--nimcache` 값이다.** `--nimcache:X`가 주어지면
   `.deps`는 CWD가 아니라 `X/<module>.deps`에 기록된다. `--nimcache`를 주지
   않으면 CWD에 기록된다. 존재하지 않는 nimcache 디렉터리를 지정하면
   `.deps` 생성 자체가 IOError로 실패한다(artifact 0바이트, exit≠0).
3. **`.dot`의 기록 위치는 주 모듈의 디렉터리다.** CWD·`--nimcache`와 무관하게
   `<main module>.dot`은 항상 주 모듈 `.nim` 파일 옆에 기록된다 — 저장소
   안에 미추적 파일을 남겨 F5 오염 검사(`git status --porcelain` before/after
   비교)를 깨뜨린다.
4. **`when fileExists("<상대경로>")`는 컴파일러 프로세스의 CWD 기준으로
   평가된다.** genDepend를 임시 디렉터리에서 실행하면 저장소 루트 기준
   상대경로 프로브(`src/generated/build_env.nim`,
   `src/generated/import_rules_static.nim`)는 전부 거짓으로 평가되어,
   존재 분기의 import(생성물 2종)가 `.deps` closure에서 빠진다.
5. **config.nims를 로드하는 genDepend는 임시 CWD에서 artifact를 전혀 만들지
   못한다.** `--skipParentCfg --skipProjCfg` 없이(= 조상 config.nims 탐색이
   살아 있는 채) genDepend를 임시 디렉터리에서 실행하면, config.nims의
   hermetic 계열 블록이 임시 CWD 기준 상대경로로 실행되어 컴파일러가 조기
   quit한다 — 1번과 달리 `.deps`·`.dot` **전부 미생성**인 완전 실패다.
   build_all_gates의 게이트 빌드는 config.nims 로드를 전제하므로(repo-root
   CWD 실행), 임시 CWD에서 동일한 import 해석을 얻으려면 config 로드를
   끄고(`--skipParentCfg --skipProjCfg`) 그 경로 세트를 루트 재앵커 절대경로
   `--path`로 명시해야 한다.
6. **config 로드를 끄면 config이 제공하던 해석·스위치가 전부 회수된다**
   (5번의 일반화; 2026-11-08 VS-T 실측 3양상). `--skipParentCfg
   --skipProjCfg --skipUserCfg --skipCfg` 상태의 genDepend는:
   (a) **nimble 패키지 경로를 유실한다** — config.nims 경유 nimble 해석이
   사라져 `cannot open file: checksums/sha2` 식으로 import 해석이 실패한다.
   임시 CWD 계약(1·5번)이 이 하중을 만든다: config을 껐으니 pkgs2 재앵커가
   사라진다. → `--path:<pkgs2 5종>`(checksums, ed25519, fusion, malebolgia,
   nimcrypto) 명시로 보완.
   (b) **`threads`가 off로 돌아간다** — config.nims의 `switch("threads")`
   부재로 malebolgia가 `Thread` 미선언으로 해석 실패한다(gateway-test에서
   관측). → `--threads:on` 명시.
   (c) **`mm`가 기본값으로 돌아간다** — config.nims의 `switch("mm", "arc")`
   부재. → `--mm:arc` 명시. 등가성: 유일한 `gcOrc` 분기는 GC_fullCollect
   호출뿐이고 import 게이팅이 없어 프로젝트 closure 분기에 영향 0(252파일
   `when defined` 전수 스윕 + `--mm:arc` 전후 키 동일 관측).

## Measured evidence (2026-11-05)

- `nim genDepend … /repo/tools/ci/doc_path_validator.nim`(임시 CWD, 2회 반복):
  exit=1, stderr `gendepend: Graphviz's tool dot is required,see
  https://graphviz.org/download for downloading`, `.deps`는 120행(프로젝트
  3 + stdlib 117) 완전 생성. 2회 실행 결과는 **바이트 동일**(결정론 확인).
- `--nimcache:<존재하지 않는 디렉터리>` 지정 시 `tools/debt_engine.nim`:
  exit=1, `Error: unhandled exception: cannot open:
  <nimcache>/debt_engine.deps [IOError]` — `.deps` 미생성.
- `--nimcache:<임시 디렉터리>`로 리다이렉트하면 `.deps`는 임시 디렉터리에
  생성되고, **nimcache 리다이렉트 유무와 무관하게 `.deps` 내용은 동일**
  (doc_path_validator 2회 cmp 동일). genDepend는 코드생성을 수행하지 않아
  nimcache에 다른 산출물을 남기지 않는다.
- 격리 실험(`/tmp` 소유 모듈, CWD·nimcache·모듈 디렉터리 3곳 분리):
  `.deps`는 nimcache에, **`.dot`은 주 모듈 디렉터리에** 각각 기록 —
  3번 퀴크의 실측. 저장소 모듈 대상 genDepend 6회(임시 CWD·nimcache 포함
  여부 혼합) 전부 주 모듈 옆에 `.dot`을 남겼다(미추적 · git status 오염).
- `src/gate/runners/layer_enforcement_gate.nim` genDepend(임시 CWD):
  `.deps` 146행(프로젝트 34)에 `src/generated/*` 0행 포함 — 4번 퀴크의
  실측. 실측 프로젝트 closure는 배경 조사(H 보고서, 수동 스캐너)의
  보수적 분석과 정확히 일치(debt_engine 50, proof_unit 45, reconcile 5,
  epoch 5, theater 2, doc 3).
- 7개 게이트 전부 genDepend로 closure 획득 성공(임시 CWD + 임시 nimcache).
- `nim genDepend -d:release <절대경로 src/gate/runners/nim_check_gate.nim>`(임시
  CWD, config 로드 생략 없음): exit=1, `.deps`·`.dot` 0건(0.9s) — 5번 퀴크의
  실측. 같은 대상에 `--skipParentCfg --skipProjCfg --path:<루트>
  --path:<루트>/src --path:<루트>/tools -d:release`: `.deps` 174행(프로젝트 48 +
  nimble checksums·malebolgia 4 + stdlib 122) 완전 생성, 2회 실행 바이트 동일.
  `-d:release`는 closure 내 조건부(`when defined(release)` 등)를 실빌드와 동일
  분기로 가져간다 — config.nims가 release 빌드에 추가하는 define
  (AXIOM_ENFORCE_GATE_PRAGMAS·axiomProjectPath 등)은 closure 조건부 import의
  게이트가 아님(해당 `when defined` 전수 확인).

## Measured evidence (2026-11-09, Part 1) — pre-commit user-cfg 유입 전후 실측 (DEBT#521 완결)

- 대상: `.githooks/pre-commit` Part 1(nim_check_gate freshness)의 캡처 — 프로덕션
  `pp_capture_manifest` 계약 + `NCG_GENFLAGS` 자체 구성(수정 전 리터럴 그대로).
  매니페스트 = nim_check_gate genDepend 클로저 ∪ 전 러너 ∪ 빌더 소스(250행).
  실험 형상: 임시 HOME에 pkgs2를 심링크해 프로덕션 nimble 해석을 미러 — 이 캡처는
  pkgs2 경로를 플래그로 명시하지 않으므로(아래 잔류 관측 (a)) $HOME/.nimble
  자동탐색에 의존하고, .nimble 없는 임시 HOME에서는 기준조차
  `cannot open file: checksums/sha2`로 UNKNOWN이 된다(형상 통제의 이유).
- 수정 전(NCG_GENFLAGS `--skipUserCfg` 부재) 차등:
  - 유저 cfg `--threads:off`: malebolgia.nim(110,32) `undeclared identifier:
    'Thread'`(6b 퀴크 — 클로저가 malebolgia를 포함) → `.deps` 미생성 → 캡처
    **UNKNOWN** → pre-commit FAIL. pre-push 관측(매니페스트 시프트)보다 강한
    파괴 양상: 유저 cfg가 커밋 자체를 차단하는 벡터.
  - 유저 cfg `--define:windows`: typedthreads.nim(187,25) `undeclared
    identifier: 'pthread_join'` → `.deps` 미생성 → 캡처 **UNKNOWN**(커밋 차단).
  - 유저 cfg 보스 스위치: `Error: invalid command line option:
    '--definitelyBogusSwitchNoExist'`(에러에 임시 HOME cfg 경로 명시) — cfg
    로딩 직접 실증, 캡처 UNKNOWN.
  - 대조군: 유저 cfg `--mm:orc` → 불변(6c 재확인). 기준 매니페스트 2회 바이트
    동일(결정론, sha256 61cc6aadd23a6081…).
- 수정 후(`NCG_GENFLAGS`에 `--skipUserCfg` 1개 토큰 추가): 유저 cfg 4개 변이
  (threads:off·define:windows·mm:orc·보스 스위치) 전부 캡처 rc=0 + 매니페스트
  전부 기준과 **바이트 동일**(동일 sha256). cfg-free 환경에서 수정 전후 매니페스트
  바이트 동일(부수 효과 0). FLAGS 문자열 변화로 INPUT_IDENTITY는 갱신 — 기존
  체크아웃-로컬 스탬프(vs1-gate-stamp/1)는 다음 .nim 스테이징 커밋에서 불일치로
  fail-closed되고, 정준 재빌드(`bin/build_all_gates --release`) 후 mtime
  부트스트랩이 identity+sha를 재결속한다(일회성 재스탬프 — PR #28의 첫 push
  관측과 동일 계급).

## Measured evidence (2026-11-09, Part 4a) — pre-push user-cfg 유입 전후 실측 (DEBT#521)

- 문서·툴체인 확인: 공식 문서 nimc.md cfg 순서(전역 $nim/config/nim.cfg +
  /etc/nim/nim.cfg → 사용자 $XDG_CONFIG_HOME·$HOME/.config/nim/nim.cfg → 부모
  디렉터리 → 프로젝트; "Command-line settings have priority over
  configuration file settings")과 Nim 2.2.10 `nim --fullhelp`의
  `--skipCfg`/`--skipUserCfg`/`--skipParentCfg`/`--skipProjCfg` 정의가 일치.
  genDepend가 유저 cfg를 로드함은 임시 HOME(`$HOME/.config/nim/nim.cfg`에
  미존재 스위치 기입)에서 `Error: invalid command line option:
  '--definitelyBogusSwitchNoExist'`로 직접 관측 — cfg 로딩은 명령 무관.
- 수정 전(pre-push 캡처 플래그 = NIM_TOOL_FLAGS, `--skipUserCfg` 부재) 차등
  (doc_path_validator·debt_engine, 프로덕션 pp_capture_manifest 계약 사용):
  - 유저 cfg `--threads:off`: 두 게이트 매니페스트 모두 시프트
    (doc_path_validator 120→113행, debt_engine 191→185행 —
    `std/typedthreads`·`std/private/{syslocks,threadtypes}`·
    `system/{channels_builtin,threadimpl,threadlocalstorage}` 등 스레드
    계열 7행 탈락). 유효 캡처 상태의 클로저 시프트 = identity가 사용자
    환경의 함수가 됨.
  - 유저 cfg `--define:windows`: `typedthreads.nim(187,25) undeclared
    identifier: 'pthread_join'` 의미 오류 → `.deps` 미생성 → 캡처
    UNKNOWN(fail-closed) — 유저 cfg가 push를 차단하는 벡터.
  - 대조군: 유저 cfg `--mm:orc` → 불변(6c 재확인). 유저 cfg `--path`
    섀도(가짜 `std/osproc.nim`·`src/core/trusted/layer_declaration.nim`) →
    불변(커맨드라인 `--path` 우선). 기준 매니페스트 2회 바이트 동일(결정론).
- 수정 후(`pp_canonical_flags`가 `--skipUserCfg` 1개 추가): 유저 cfg 4개
  변이(threads:off·define:windows·mm:orc·보스 스위치)에서 캡처 전부 rc=0 +
  매니페스트 전부 기준과 바이트 동일. cfg-free 환경에서 수정 전후 매니페스트
  동일(부수 효과 0). INPUT_IDENTITY는 플래그 문자열 변화로 갱신 — 스탬프
  전량 재생성이 첫 push에서 자연 발생(vs1-gate-stamp/1, 체크아웃-로컬).
- 잔류 관측: (a) Nim 2.2.10은 `$HOME/.nimble/pkgs`를 자동 검색 경로에
  추가한다(임시 HOME의 fakepkg가 `import fakemod`로 해석됨). 훅 프로파일은
  이를 끄지 않는다 — 정준 재빌드(NIM_TOOL_FLAGS)도 끄지 않으므로 캡처가
  실빌드 해석을 미러링하고, 검색에서 이기면 해당 파일 내용이 CLOSUE sha256
  으로 결속된다(2.2.10 advopt의 스위치명은 `--noNimblePath`/
  `--clearNimblePath` — `--skipNimblePath`는 존재하지 않는다). (b)
  /etc/nim/nim.cfg(기계-로컬, stock 배포본은 경로 중립)도 전역 cfg 계열
  잔류다 — $nim/config/nim.cfg와 달리 identity에 해시 결속되지 않지만,
  유입 시 실빌드와 캡처가 동일하게 이동하고 내용이 클로저 해시로 결속된다
  (TOOLCHAIN_CFG 결속과 같은 설계 계급).

## Cause

- genDepend 파이프라인은 `.deps` 기록 → `.dot` 기록 → graphviz `dot` 렌더
  순서로 진행되며, 마지막 단계의 외부 도구 부재가 전체 exit status를
  오염시킨다. artifact 완전성과 exit status가 무관하다는 뜻이기도 하다.
- Nim 컴파일러는 산출물 임시 위치를 `--nimcache` 옵션에서 일괄 해석하며,
  genDepend의 `.deps`도 이 규칙을 따른다.
- `when fileExists(…)`는 VM이 컴파일러 CWD를 기준으로 경로를 해석한다.
  make 빌드(저장소 루트 CWD)와 genDepend(임시 CWD)의 분기 결과가 달라지는
  것이 이 퀴크의 실질적 함의다.
- config.nims는 주 모듈의 조상 디렉터리에서 발견·실행되며(CWD 무관),
  그 NimScript 본체가 다루는 상대경로는 컴파일러 CWD 기준으로 해석된다.
  임시 CWD에서 실행되면 hermetic 계열 블록이 존재하지 않는 경로를 향해
  작동해 조기 quit한다 — 5번 퀴크의 원인이자, "config 로드를 끄고 경로를
  명시한다"가 임시 CWD 캡처의 유일한 안전 경로인 이유다.

## Execution contract (pre-push Part 4a가 따르는 계약)

- genDepend는 **반드시 `mktemp -d` 임시 디렉터리를 CWD와 `--nimcache` 양쪽으로**
  실행한다 — `.deps`(및 다른 nimcache 산출물)가 저장소 밖에만 남고, 종료 시
  `rm -rf`로 정리한다.
- **`.dot` 정리 계약**: `.dot`은 주 모듈 옆(저장소 안)에 기록되므로, 실행
  전후 존재 비교로 "이번 실행이 새로 만든 경우에만" 삭제한다. 실행 전부터
  존재하던 파일은 남긴다(소유 아님 — 단, 미추적 파일 재기록은
  `git status --porcelain` 문자열을 바꾸지 않으므로 F5에 무해하다).
- **exit status는 판정에 쓰지 않는다**(`|| true`). 대신 artifact 자체를
  검증한다: `.deps` 존재·비었지 않음·주 모듈 절대경로 포함·전 행이
  readable한 절대경로 파일. 검증 실패는 UNKNOWN으로 취급해 fail-closed
  (재빌드도 closure를 얻지 못하면 FAIL — §0.9 극장 금지).
- 4번 퀴크(`when fileExists`의 CWD 해석)는 **조건부 존재 프로브**로 보완한다:
  closure 파일들에서 `when fileExists("<경로>")` 인자를 grep해 프로브 목록을
  만들고, 그 경로의 존재+sha256을 input identity에 결속한다. genDepend의
  closure가 생성물 분기를 담지 못해도, 생성물 내용 변화·부재→생성 전이가
  identity 불일치 → 재빌드 → closure 갱신으로 이어진다.
- genDepend에 넘기는 플래그는 Makefile `NIM_TOOL_FLAGS`를 `make -pn`으로
  추출해 저장소 루트 기준 절대경로로 정규화한 값이며, 실행 시에만
  `--nimcache`를 임시 디렉터리로 리다이렉트한다(위 실측: `.deps` 내용에
  영향 없음). 정규화 플래그 문자열 자체가 identity의 결속 항목이다.
  2026-11-09부터 pre-push Part 4a는 이 값에 `--skipUserCfg`를 덧붙인다
  (`pp_canonical_flags` — 유저 cfg는 기록되지 않는 기계-로컬 입력이며
  아래 2026-11-09 실측처럼 클로저를 시프트하거나 캡처를 UNKNOWN으로
  만든다; DEBT#521 pre-push 반쪽 해소). 전역 툴체인 cfg($nim/config/
  nim.cfg)는 건너뛰지 않는다 — 정준 재빌드가 그것을 로드하고
  pp_identity_compute가 그 sha256을 identity에 결속한다(TOOLCHAIN_CFG 항).
- **pre-commit Part 1(nim_check_gate freshness)이 따르는 계약**: 이 게이트의
  정준 재빌드는 `bin/build_all_gates --release`(Makefile 타깃 부재)이며
  config.nims 로드를 전제한다. 캡처 플래그는 따라서 NIM_TOOL_FLAGS 대신
  `--skipParentCfg --skipProjCfg --skipUserCfg` + 루트 재앵커
  `--path:<루트>`·`--path:<루트>/src`·`--path:<루트>/tools` + `-d:release`(빌더의
  release 플래그 — 5번 퀴크의 계약)이고, 이 문자열과 빌더 소스 sha256이 identity에
  결속된다. 2026-11-09부터 `--skipUserCfg`가 추가된다(`NCG_GENFLAGS` — 캡처
  호출·identity 결속·스탬프 META에 동일 문자열로 흐르는 단일 구성점; 유저 cfg는
  기록되지 않는 기계-로컬 입력이며 아래 2026-11-09 Part 1 실측처럼 이 캡처를
  UNKNOWN으로 만들어 커밋을 차단한다; DEBT#521 pre-commit Part 1 해소 — pre-push
  Part 4a의 pp_canonical_flags 결정과 동일 계급: 전역 툴체인 cfg는 건너뛰지
  않고 pc_identity가 sha256을 결속).
- **VS-T 게이트 클로저 매니페스트 생성기(2026-11-08)가 따르는 계약**:
  `tools/ci/generate_gate_closure_manifests.sh`(precompile_gates가 키 계산 전
  무조건 호출)는 위 계약에 6번 퀴크 보완을 더한 완전 하드닝 프로파일을 쓴다 —
  `--skipParentCfg --skipProjCfg --skipUserCfg --skipCfg` + 루트 재앵커
  `--path` 5종 + nimRoot + pkgs2 5종 + `--threads:on` + `--mm:arc` +
  `-d:release -d:ThreadPoolSize=14`. 프로파일 문자열의 단일 권위는
  `src/core/gate/closure_manifest.nim:genDependProfile`이며 매니페스트 헤더
  `FLAGS=`와 읽기 시 재계산값의 일치가 검증된다(불일치 → fail-closed 재생성).
  훅 캡처의 user-cfg 미스킵은 DEBT#521로 등록되어 있었다 — 2026-11-09에
  Part 4a(pre-push)가 `--skipUserCfg`로, 같은 날 Part 1(pre-commit,
  NCG_GENFLAGS 자체 구성)이 `--skipUserCfg`로 해소하여 DEBT#521은
  완결(closed)되었다(위 두 2026-11-09 실측). 2026-11-09부터 생성기의
  54회 캡처는 **동시 실행**된다(DEBT#522 직렬 재생성 비용 해소,
  docs/evidence/gendepend_parallel_capture_2026-11-09.md): 격리 불변식(호출별
  mktemp CWD+nimcache·출력 경로 유일성·중복 basename 거부)이 이미 갖춰져
  있어 공유 가변 경로가 없고, 매니페스트 바이트는 (소스·플래그·툴체인)의
  순함수라 스케줄링 무관이다(동시 실행 전후 54/54 바이트 동일 실측).
  동시 상한은 `AXIOM_CLOSURE_WORKERS`(기본 8, nproc 상한). 캡처 1건 실패는
  여전히 전체 실행 실패(exit 1, fail-closed, 실패 주입으로 관측)다.

## Status

2026-11-05 기준 미완결 퀴크는 없다 — 네 행동 모두 위 계약으로 흡수되어
`.githooks/pre-push` Part 4a(VS-1 content-identity 판정)가 소비 중이다.
2026-11-06에 5번 항이 추가되었고 pre-commit Part 1이 같은 계약 체계로
소비한다. genDepend의 closure 결정론·artifact 완전성은 본 머신에서 2회
바이트 동일로 실측했으나, 다른 머신·툴체인 버전에서 재관측 시 이 문서를
갱신한다. 2026-11-08에 6번 항(3양상)이 추가되었고 VS-T 게이트 클로저
매니페스트 생성기(`tools/ci/generate_gate_closure_manifests.sh`)가 완전
하드닝 프로파일로 소비한다 — 54게이트 전체 재생성의 2회 바이트 동일
실측(runB2·run4, docs/evidence/vst_dependency_authority_handoff_2026-11-08.md
§6 D). 2026-11-09에 pre-push Part 4a 캡처 프로파일이 `--skipUserCfg`로
강화되었다(DEBT#521 pre-push 반쪽 해소, 위 2026-11-09 전후 실측), 같은 날
pre-commit Part 1(`NCG_GENFLAGS`)도 `--skipUserCfg`로 강화되어 DEBT#521은
완결되었다(위 2026-11-09, Part 1 전후 실측 — 등록은 closed, resolution에 전·후
관측 기록). 같은 날 생성기 캡처가 동시 실행으로 전환되었다(DEBT#522 직렬
재생성 비용 해소 — 실행 계약 갱신은 위 VS-T 생성기 항, 실측은
docs/evidence/gendepend_parallel_capture_2026-11-09.md).
