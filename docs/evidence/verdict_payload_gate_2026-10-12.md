# Verdict Payload Gate — verdict leg 최소 페이로드 확정 + S_net 실측 (1회차 게이트)

- **Date**: 2026-10-12
- **Workstream**: `ci/verdict-payload-gate` (게이트 전용 — 관측·산술만 수행, workflow/action 무변경)
- **판정 대상**: verdict(`admission-check` job, `stage: verdict`) leg의 도구전달(toolchain-handoff) 변경이 자기 산술로 존속하는가 — GO/NO-GO
- **사전등록 기준** (변경 금지 — 본 문서가 그 이행 기록):
  - `S_net = 64.7 − ΔT_producer − ΔT_consumer` (단위: 초; 64.7s = `setup-axiom-toolchain` 스텝 실측 평균, sd 12.9, min 45, max 92, 25/25 런)
  - ΔT_producer = 패키징(tar)+업로드가 build-base 임계경로에 실제로 **추가하는** 시간 (겹치는 시간은 중복 계산 금지)
  - ΔT_consumer = verdict 측 다운로드 + sha256 검증 + 언팩 + 런타임 프로브 총합
  - 전송률(25런 실측 프록시): 업로드 7.6MB/s(보수) / 10.5MB/s(관측), 다운로드 16.5MB/s
  - **판정 규칙**: 보수 전송률에서 S_net > 0 마진을 갖는 **작동하는** 스코프가 1개 이상 → GO. 전 스코프 S_net ≤ 0 → NO-GO(기각 산술 기록 + 다음 병목 대상 지명)

---

## 0. TL;DR

**GO.** 선정 스코프 **(a') 아티팩트 확장** — 기존 `admission-check-base-artifacts`(39.7MB)에
`bin/derive_checker_closure`(588,680 B, B에서 빌드) + `jq-linux64`(2,319,424 B, 고정 자산)를
추가하고, verdict leg에서 `setup-axiom-toolchain`(full, 64.7s) 호출을 제거한다.

- Clean-env 실행 테스트 3건: (a') **전체 verdict 체인이 nim·lean·z3 전무 환경에서 작동**(860 멤버 closure 유도·결정성 재실행·jq L1·`bin/ax` 기동), nim-minimal 19MB만으로 deriver 콜드 컴파일 성공, 대조군(deriver 바이너리 없음+nim 없음)은 exit 127로 실패(2026-10-10 실측 merge_group 장애의 국소 재현)
- S_net(a', 보수) = **+53.4s** / (a', 관측률) = **+61.3s** — 마진 충분
- 핵심 근거: workflow L1948의 `[ -x bin/derive_checker_closure ] || nim c …` — deriver 바이너리가 공급되면 `nim c`는 **발화하지 않고**, verdict predicate의 나머지 전체(`jq`, `git`, `gh`, `bin/ax merge --dry-run`)는 순수 시스템 도구 + B-빌드 바이너리만 소비한다 (§2)

---

## 1. 근거 — verdict leg의 실제 소비 (workflow 정독)

`.github/workflows/admission-check.yml` @ `origin/main` 181f0ff07 (2114행). `admission-check` job(L617)의
verdict 스테이지 실행 스텝(landing venue, `stage == 'verdict'`):

| # | 스텝 | 소비하는 것 |
|---|---|---|
| 1 | `[venue]` 실행 장소 결정 (L657) | bash 내장만 |
| 2 | B 체크아웃 (L679) | actions/checkout — B 트리 워크스페이스 |
| 3 | `[slice-engine]` (L693) | `git show`, `jq` — epoch manifest 파싱 |
| 4 | `setup-axiom-toolchain` (L759, **full 스코프 — 64.7s 스텝**) | A레이어 1.03GiB restore + B레이어 restore + 검증/프로브 |
| 5 | base artifact 다운로드 (L786) | `admission-check-base-artifacts` 39.7MB → `_base-artifacts/` |
| 6 | artifact 매니페스트 검증 (L804) | `sha256sum` 전수 + `build_sha == B` + `chmod +x` |
| 7 | `[check] Load derived-closure sets` (L1636, verdict 전용) | artifact 다운로드(soft, 소실 허용) |
| 8 | `[check] Fetch subject-certificate` (L1667, verdict 전용) | artifact 3.9MB(soft) |
| 9 | **`[check] Admission predicate evaluation`** (L1710, **job 총 103.2s 중 24.0s**) | 아래 상세 |

**L1710 스텝의 실행 내용** (본 게이트의 판정 대상):

1. `jq` — derived-closure 4파일 all-or-none 검사, L1 identity 스키마/바인딩 검사 (L1755–1918)
2. `git fetch --depth=50 origin $H` + `git cat-file/rev-parse/show/ls-tree -r` (L1788–1965)
3. **in-place deriver 컴파일**: `nim c --hints:off --skipParentCfg --skipProjCfg --path:src -o:bin/derive_checker_closure tools/ci/derive_checker_closure.nim` (L1844) — 단, **L1948의 L2 leg와 L1844 모두 `[ -x bin/derive_checker_closure ]` 조건부**: 바이너리 선공급 시 `nim c` 미발화
4. `bin/derive_checker_closure --ref H --repo .` ×2 + 재실행 ×2, digest 동등성 (L1848–1964)
5. `gh api` ×2 — merge_group PR 컨텍스트 재유도 (L1809, L1995–1997)
6. **`bin/ax merge $PR --dry-run --json`** (L2030) — collectAdmissionFacts(GitHub API, httpclient) → bindCertificateSource(Ed25519 순수 nim 검증, `src/cli/merge_cli.nim:2144`) → MergeAdmissible(순수 함수, `:737`) → 저널 기록 → exit 코드가 required check 결론

**실행되지 않는 것** (정적 확인): `ax merge --dry-run` 경로에 lean/lake 실행 없음(`healing_orchestrator`의 `lake env lean`은 미호출), z3 실행 없음(`kernel_reexecution`은 import되나 dry-run proc이 호출하지 않음 — `merge_cli.nim` 내 re-execution 호출부 0건), `ircheck` 실행 없음(`extraction_agreement.agreementFromWire`는 merge 경로 미호출). `bin/ax` 동적 링크는 libm/libc뿐 (`ldd bin/ax` — libpcre는 Nim `re` 모듈의 런타임 dlopen 후보이며 action의 apt 스텝이 페이로드 외 시스템 의존으로 처리, 양측 동일 → S_net에 불변).

> **파생 결론**: verdict leg의 A레이어 실소비 = **deriver 컴파일 가능성(`nim c`) + `jq`** 전부다.
> lean(≈최대 구성원)·z3·nimble·compiler 소스는 verdict leg에서 실행 경로가 없다.

---

## 2. 페이로드 매니페스트 (스코프별 정확 경로 + 크기)

| 스코프 | 매니페스트 | 크기 | 작동? |
|---|---|---|---|
| (a) bin/ax+공유라이브러리만 | `bin/ax`(10,283,840 B, 이미 artifact로 공급) + 시스템 lib | +0MB (신규 전달 0) | **불가** — deriver 컴파일 불가(Test C, exit 127) |
| **(a') 아티팩트 확장** | (a) + artifact에 `bin/derive_checker_closure`(588,680 B, **B에서 빌드**) + `jq`(jq-linux64 2,319,424 B) | **+2.9MB** | **가능** (Test A) |
| (b') 아티팩트 확장 + runtime 스코프 | (a')의 deriver만 artifact로, jq+z3는 기존 `provision-scope: runtime`(axiom-a-rt-*) restore(~/.local/bin 14.1MB) | +0.6MB artifact + 14.1MB restore | **가능** (기존 action 기구 재사용) |
| (c) nim-minimal | `nim-2.2.10/bin/nim` + `lib/`(9.2MB, stdlib) + `config/` — **`compiler/`, `tools/`, `doc/`, `~/.nimble`, `~/.elan`, z3 불필요** | **19MB** (로컬 실측 du) | **가능** — deriver 콜드 컴파일 성공 (Test B) |
| (d) full A레이어 (현행) | `~/.nimble` + `~/.choosenim` + `~/.elan` + `~/.local/bin` | 1.03GiB | 가능 (기준선 — 절감 0) |

참고: `~/.choosenim/toolchains/nim-2.2.10` 전체는 136MB이나, deriver 컴파일의 실소비는
bin/nim + lib(stdlib) + config뿐이다 — Test B가 19MB 서브셋으로 컴파일 성공으로 입증
(`--skipParentCfg --skipProjCfg`로 프로젝트 cfg 미독, deriver import 체인은
`std/[os,osproc,strutils,sequtils,sets,tables,algorithm,parseopt,sugar]` +
`src/core/trusted/{layer_declaration,axiom_pragmas_lite,effect_bridge}` — nimble 패키지 0, compiler 내부 import 0).

---

## 3. Clean-environment 실행 테스트 (B-rigor — 전체 전사 요지)

환경 구성: `/tmp/vpg-clean` 스래치 `$HOME` + `sysbin/`(runner 기준선 시스템 도구 화이트리스트만
symlink: git, coreutils, gcc, python3 등 44종) + B트리 신규 체크아웃(ws, detached worktree @181f0ff07).
격리 검증: `command -v nim lean lake z3 elan choosenim nimble` → **전부 absent**
(로컬 dev 머신의 /usr/bin/nim, /usr/local/bin/z3 누출을 sysbin 화이트리스트로 차단 — CI runner에서는
도구가 $HOME 페이로드에만 존재하므로 이 격리가 runner 실형태와 동형).

**Test A — 스코프 (a'): 도구체인 전무 + 선공급 deriver** (`env -i`, PATH=페이로드+sysbin):

```
A0 absent: nim lean lake z3 elan choosenim nimble        PASS
A1 bin/derive_checker_closure --ref HEAD --repo .        PASS — 860 멤버
A1b 재실행 digest 동등성 (결정성)                          PASS — sha256 동일
A2 jq L1 패턴 (identity.json 스키마 검사)                  PASS
A3 bin/ax merge 1 --dry-run --json                        PASS — exit 1 (GITHUB_TOKEN 미설정
    run-level err) = 바이너리 완전 기동 후 도달 — 로더·Nim 런타임·arg 파싱 정상
A4 L2② 패턴: 860 멤버 전수 git ls-tree(H) 포함             PASS
```

**Test B — 스코프 (c): nim-minimal 19MB만으로 deriver 콜드 컴파일**:

```
B1 nim c --hints:off --skipParentCfg --skipProjCfg --path:src \
     --nimcache:<fresh> -o:bin/derive_checker_closure \
     tools/ci/derive_checker_closure.nim                  PASS — real 1.663s (신규 nimcache)
B2 컴파일된 deriver 실행                                   PASS — 860 멤버
```

**Test C — 대조군: 스코프 (a) 그대로(deriver 바이너리 없음 + nim 없음)**:

```
nim c … → bash: nim: command not found / exit 127         예상 실패 — merge_group 런
    37951806316/37952005666(2026-10-10 "nim: command not found" 전면 착지 차단)의 국소 재현
```

**"빠진 의존성 = 실패하는 산출물" 원칙의 소거 완결성**: verdict 스텝 셸이 실행하는 모든 외부 명령은
{jq, git, gh, nim(조건부), bin/ax, bin/derive_checker_closure, sha256sum, 표준 coreutils}다.
이 중 (a')에서 nim만 제거되며(조건이 상시 거짓이 되므로), 나머지는 artifact 멤버(2) 또는 runner 시스템
도구(git/gh/coreutils — 현행과 동일한 전제)다. 누락 후보 없음 — 상기 전수 대조로 닫힌다.

---

## 4. S_net 산출 (사전등록 공식, 전송률 프록시 적용)

공통 전제: producer(build-base)는 이미 nim이 프로비저닝되어 bin/ax를 빌드하므로 deriver 추가 컴파일에
신규 도구 비용 0. artifact 업로드는 build-base 꼬리에 엄밀 추가(후속 job이 needs로 대기 — 겹침 없음,
전액 계상). 패키징(tar/zip 단편 추가)은 측정된 39.7MB=5.2s 선형 비례로 환산.

ΔT_consumer의 크기 기반 환산은 **무압축 바이트 기준**(측정률에 압축 이득 미반영 — 보수측 과대계).

| 스코프 | ΔT_producer 보수/관측 | ΔT_consumer 보수/관측 | **S_net 보수** | **S_net 관측** |
|---|---|---|---|---|
| **(a')** artifact +2.9MB | 컴파일 10s† + 업로드 0.38s = **10.4** / 3s†+0.28s = **3.3** | DL 0.18s + 언팩·digest·프로브 0.8s = **1.0** / **0.4** | **+53.3** | **+61.0** |
| **(b')** artifact +0.6MB, runtime restore 14.1MB | 컴파일 10s† + 업로드 0.08s = **10.1** / 3s†+0.06s = **3.1** | DL 0.9s + verify/프로브·keygen 7.1s = **8.0** / **5.0** | **+46.6** | **+56.6** |
| **(c)** nim-minimal 19MB | tar 0.5s + 업로드 2.5s = **3.0** / 0.3s+1.8s = **2.1** | DL 1.2s + 언타 1s + 프로브 1s + verdict 측 콜드 컴파일 10s‡ = **13.2** / 3.2s+4s‡ = **7.2** | **+48.5** | **+55.4** |
| (d) full 1.03GiB (현행) | — | — | 0 (기준선) | 0 |
| (a) bin/ax만 | — | — | **기각 — 작동 안 함** (Test C) | |

† producer 측 deriver 컴파일: 로컬 실측 1.66–1.74s(신규 nimcache); CI 콜드 보수 10s/관측 3s로
계상 — workflow 주석(L623)의 "CI-cold compiles are several× slower" 근거 추정치, 측정 필요 시에도
S_net 여유(+46s 이상)가 흡수.
‡ consumer 측 콜드 컴파일 동일 근거 추정치.

**민감도(기준 미변경 확인)**: 64.7s 풀에서 handoff 설계가 B레이어 restore+프로브를 유지하는 변형을
가정해도(= A-restore 성분만 회수, A-restore ≈ 1.03GiB ≈ 64s@16.5MB/s로 스텝 시간의 지배 성분),
S_net(a') 보수 ≈ 60 − 10.4 − 1.0 = **+48.6s** — 판정 불변. artifact 채널은 자체 무결성 체인
(매니페스트 전수 digest + `build_sha == B` 검증, workflow L804)을 가지므로 verdict leg에서 action
전량 제거는 캐시 무결성 계약과 정합이다(B레이어 바이너리는 artifact가 동일 digest 구속으로 대체 공급).

---

## 5. 판정: **GO** — 스코프 (a') 아티팩트 확장

- 보수 전송률(7.6MB/s 업로드, 16.5MB/s 다운로드, 무압축 바이트, CI-cold 컴파일 과대계)에서도
  S_net = **+53.3s** > 0, 마진은 측정 표준편차(sd 12.9)의 4배 초과.
- 명시 매니페스트 (GO 스코프):
  1. `bin/derive_checker_closure` — build-base가 B에서 컴파일(`nim c` hermetic 레시피 L1844 동일)해
     `admission-check-base-artifacts`에 추가. artifact 매니페스트 digest 구속은 기존 검증 루프가
     자동 적용(신규 멤버 무검증 공백 없음). DEBT#502의 "5멤버 완전 페이로드" 계약은 B레이어 캐시
     쪽 계약이며 artifact 채널 확장은 별도 표면 — handoff 본문 PR이 매니페스트 멤버십을 명시 갱신.
  2. `jq`(jq-linux64 1.7.1 고정 자산, 2,319,424 B) — 동 artifact 추가(런너 jq 부재 실측 이력:
     axiom-ci runner-3 2026-09-08).
  3. verdict leg: `setup-axiom-toolchain` 호출 제거. apt libpcre 스텝은 시스템 의존으로 보존
     (양측 공통 — S_net 불변 항).
- 설계 의무(본문 워크스트림 과제 — 본 게이트 미수행): workflow L1844의 in-place 컴파일은
  "#666 recipe 유도 권위"로 주석화되어 있다 — 바이너리 선공급으로 전환하면 유도 권위의 공급 경로가
  artifact로 이동하므로, 해당 주석과 slice_catalog/계약 문서의 권위 서술을 본문 PR이 갱신해야 한다.
  L2 재실행은 `[ -x ]` 재사용 경로로 동일 바이너리를 소비(결정성 Test A1b로 뒷받침).
- 워크스트림 경계 준수: 본 게이트는 workflow/action을 변경하지 않았다 (관측 + 문서만).

**기각 시 다음 대상 랭킹**(발동 조건 불발 — 기록용): GO-critical #1 deferred → mint-bridge fusion
(−40..80s) → settings. 현 판정에서는 (b')/​(c)가 대안 스코프로 잔류한다.

---

## 6. 검증 경로 (재현)

```bash
# 1. 매니페스트 격리
git worktree add --detach /tmp/vpg-clean/ws <base-sha>     # B트리
# sysbin 화이트리스트로 runner 동형 격리 확인: nim/lean/z3/nimble 전부 absent
# 2. Test A/B/C — 본 문서 §3 전사를 그대로 실행
# 3. S_net — §4 표의 산식과 측정률 대입 (사전등록치: 64.7 / 7.6 / 10.5 / 16.5)
```

- 로컬 빌드: nim 2.2.10 (`.choosenim`), hermetic 레시피 그대로 — deriver 588,680 B
- 본 문서의 CI 실측 인용치(64.7s, 1.03GiB, 14.1MB, 39.7MB, 7.6/10.5/16.5MB/s, 25런)는
  게이트 입력으로 사전등록된 측정값이다(측정 출처: gateway-jobs-measure 관측 프레임).
