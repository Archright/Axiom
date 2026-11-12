# VS-2b/3 빌드 검증 판정 — 실행 증거 (2026-11-09)

> **종류**: 실행 증거(execution evidence)다. 빌드 캐시·증분 정확성(VS-2b)과 병렬화 레버(VS-3)에 대한 측정 에이전트의 원시 관측 패키지를 정식 증거로 착지하는 문서다. 모든 수치는 기계 관측이며, 각 숫자의 출처(원시 기록 파일)를 명시한다. 재현 불가한 수치는 명시적으로 마킹한다(§0.9 극장 금지).
> **원시 기록**: `~/.cache/axiom/vs23-lab/` — `e*.out`(실행 출력+요약), `e*.cc.log`(gcc 호출 타임스탬프+명령행), `run_timed.sh`/`run_timed_sccache.sh`(측정 하네스), `*-digests.txt`(산출 digest). 저장소 외부 로컬 경로(재검증 가능 유일 원본).
> **측정 기반**: main `5e740d7` (2026-11-08). 근거: (1) 측정창 2026-11-08 14:19–15:59 KST 당시 main tip = `5e740d7`(PR #14, 03:35 UTC 머지; 다음 머지 #19는 17:27 KST), (2) 측정 기록의 54 게이트 목록이 `5e740d7` 매니페스트와 완전 일치(`git show 5e740d7:src/gate/manifest.d/_index.json` 대조), (3) precompile 출력에 클로저 매니페스트 단계가 없음 = VS-T(`#21`, 20:15 KST 착지) 이전 표면.
> **측정 환경**: nproc 16, Nim 2.2.10(choosenim), Ubuntu Linux. 측정 워크트리 `vs23-measurement`(wt1)·`vs23-measurement-2`(wt2) — 동일 커밋 체크아웃, 측정 종료 후 삭제됨(원시 기록만 잔존).
> **브랜치**: `workstream/vs23-evidence` (base: main `8bb71bf`, 2026-11-09 재rebase — 최초 커밋 base는 구계보 `2c48285`이며 신계보 `7f5d66a` → `8bb71bf`(PR #28 착지 반영)로 재착지; 관측 사실의 기반은 §측정 기반·§10 표기 그대로). 본 슬라이스는 **문서 + 부채 연계만** — 소스 수정 0건.

---

## §1. 측정 방법 (재현 하네스)

- `run_timed.sh <label> <workdir> <cmd…>`: PATH 선두에 gcc/cc 카운팅 shim(`~/.cache/axiom/vs23-lab/shim/gcc` — gcc 호출마다 `epoch\targs`를 로그, 실제 gcc exec)을 두고 명령을 실행, wall(초, `date +%s.%N` 차), exit 코드, gcc 분류를 `.out` 말미 `--- summary ---`에 기록.
- **CC 정의**: gcc `-c` 호출 수(컴파일). probe = `-dumpversion`, link = 그 외. 본 문서의 CC는 원시 `.cc.log` 재계수 값이다:
  `awk -F'\t' '{n=split($2,a," "); if (a[1]=="-c") c++} END {print c+0}' <label>.cc.log`
- **정직 기록**: e1a·e1b-bagtool의 `.out` 요약은 초기 스크립트 버전(컴파일 집계 버그 — compiles=0/blank)으로 작성됐다. 위 재계수로 본문 수치는 모두 원시 로그에서 직접 계산했다(e1a: 937).
- `run_timed_sccache.sh`: 동일 구조 + sccache 래퍼(`sccache-shim/`) + 실행 후 `sccache --show-stats` 캡처.
- 링크 지속시간 산출: 마지막 gcc(링크)의 `.cc.log` 타임스탬프 → 런 종료(헤더 date + wall)까지의 차. ax는 LTO 링크가 마지막 gcc 호출이므로 이 계산이 유효하다.

## §2. 콜드 빌드 (wt1, 캐시 전면 비움)

| 런 | cmd | exit | wall | CC(−c) | probe/link | 비고 |
|---|---|---|---|---|---|---|
| e1a | `make -f ci/checker.mk ci-bootstrap` | 0 | **144.27s** | **937** | 5/5 | ci-compile 4종(-j4) + setup-hooks + CAS/훅/베이스라인 |
| e1b | `./bin/build_all_gates --release` | 0 | **117.08s** | **2704** | 83/83 | 발견 84(76 runners + 8 tools/ci), accepted-dead 2 스킵(§0.9a) → **82 컴파일** |
| e1c | `./bin/precompile_gates` | 0 | **73.30s** | **1961** | 54/54 | 54/54 게이트 CAS 적재, `Done in 64.6s: 54 compiled, 0 cached, 0 failed` |

- e1c 프리루프 오버헤드 = 73.30 − 64.6 = **8.7s**(매니페스트 로드·키 계산·잠금 등 컴파일 루프 밖).
- e1b 직전 사전 단계: `make bin/feature_manifest_generator …`류 사전 빌드 25.28s(e1b-bagtool, CC 재계수 대상 로그 보관).

## §3. 웜 빌드 — 증분 정확성 (wt1)

| 런 | 관측 | exit |
|---|---|---|
| e2b precompile r1/r2/r3 | wall **8.71/8.68/8.60s**, **CC 0** — `All gate binaries up to date (54 gates)` | 0 |
| e2a ci-compile r1(부분 웜업) | 125.32s, CC 39 | 0 |
| e2a ci-compile r2(정상상태) | **148.66s, CC 0** | 0 |
| e2c mtime-touch 후 ci-compile-ax | **126.37s, CC 0** — 거짓 stale 없음 | 0 |
| e2e 무효 편집(생성 C 무변화) 후 | 122.46s, **CC 0** | 0 |
| e2e 유효 편집(1파일) 후 | 119.55s, **CC 1** — 정확히 해당 모듈만 재컴파일 | 0 |
| e2e 편집 복원 | 117.08s, CC 1(되돌린 .c 재컴파일) 후 재-안정 | 0 |
| e2f digest 안정성(반복 실행) | 128.36s, CC 0, 산출 digest 불변 | 0 |

**판정 (VS-2b 증분 정확성)**: mtime-touch → CC 0, 무효 편집 → CC 0, 유효 1파일 편집 → CC 1. Nim은 .nim.c **바이트**를 비교해 재컴파일을 판정하며(시간 기준 거짓 stale 없음), 증분 재컴파일은 정확하다. 이 관측은 §5의 sccache 판정(바이트 비교 = 경로 민감) 및 §8의 under-keying 원인과 동일 근거에서 나온다.

**정상상태 wall의 구조 (CC 0인데 125–149s)**:
- e2d ax 단독 웜 빌드: wall **123.03s** = 프론트엔드 ≈21.3s(프로브→링크 시작) + **LTO 링크 ≈101.7s**(링크 시작→종료). 링크가 단독 wall의 **~83%**.
- e2c 동일 구조(프론트엔드 ≈22.0s + 링크 ≈104.4s). e2a-r2(직렬 4종): 프론트엔드 합계 ≈31.2s(4종 probe→link 간격 합) + ax LTO 링크 ≈112.0s.
- 부하 의존: e-vs3-ax-lto16-r2(부하 23.76)에서 ax 프론트엔드만 48.8s로 신축 — 웜 wall 125–149s의 변동은 프론트엔드·링크 양쪽의 부하 신축이다.
- 측정 에이전트의 판정 분해치 "프론트엔드 ~99s + LTO 링크 ~103s"는 -j4·고부하 조건에서의 누적(aggregate) 관점 값이다. 직렬 무부하 관측값은 위 추출치(합계 31s / 링크 102–112s)이며, 어느 관점에서든 **LTO 링크가 지배 항**이라는 판정은 불변.

## §4. 크로스워크트리 캐시 — 재사용 0의 구조 원인

| 런 | 구성 | wall | CC | 재사용 |
|---|---|---|---|---|
| e3a | wt2 자체 nimcache 콜드 ci-compile(동일 입력 2번째 워크트리) | 179.13s | **918** | **0** |
| e3b | wt2가 wt1의 nimcache 공유(`CI_COMPILE_NIMCACHE`) | 139.00s | **870** | **≈0**(사실상 전량 재컴파일) |

**3층 구조 원인** — 워크트리 절대경로가 빌드 산출물 바이트에 들어가는 경로(현재 main `2c48285` 산출물에서 실물 확인):

1. **.c 헤더의 gcc 명령행 절대경로** (보편): nim 생성 .c 헤더의 `/* Command for C compiler: */` 주석에 `-I`, `-o` 등 절대경로가 박힌다. 예(본 저장소 빌드 캐시, `build/nimcache_precompile/anti-theater-gate/@manti_theater_gate.nim.c:3-7`): `-I'/workspace/…/src/gate/runners' -o '/workspace/…/@m….nim.c.o'`. 워크트리가 다르면 .c 바이트가 달라지고, §3에서 관측한 Nim의 **바이트 비교**가 항상 stale로 판정 → 재컴파일. 이것이 e3a/e3b에서 stdlib을 포함한 사실상 전 모듈이 재컴파일되는 직접 원인.
2. **.c 본문 NIM_STRLIT 문자열의 절대경로** (일부 모듈): 컴파일 타임에 굽는 문자열 리터럴에 절대경로가 남는다. 실물 관측(현재 main): `integrity-workflow` `.c` 본문 6건(`"…/Axiom"`, `"…/Axiom/.axiom/debug_mode_on"`, `"…/Axiom/.axiom/gate_history.jsonl"` 등 NIM_STRLIT), `readiness-start-gate` `.c` 본문 1건(소스 풀패스). **최종 바이너리 바이트까지 도달하는 층**이다(§8).
3. **.o(LTO IR)의 .c 경로** (보편): `.o` 내 LTO 메타데이터가 .c 절대경로를 포함(`strings` 관측: `…/build/nimcache_precompile/…/@m….nim.c`). 대부분의 게이트(50/54)는 최종 링크 이미지에 이 경로가 반영되지 않으나, 산출물 무결성 관점에서 경로 의존 입력이다.

## §5. sccache 판정 — **REJECT**

| 런 | 구성 | 히트율 | wall | 비고 |
|---|---|---|---|---|
| sc1 | wt2 콜드(캐시 비움) | 0/870 (0.00%) | 132.00s | 기준 |
| sc2 | wt2 웜(동일 워크트리 재빌드) | **870/870 (100.00%)** | 126.26s | 동일 워크트리에서는 완전 히트 |
| sc3 | wt1에서(교차 워크트리) | **20/870 (2.30%)** | 180.09s | **wall은 부하 오염(재실행 런) — 판정에는 히트율만 사용** |
| sc4 | wt1 + BASEDIRS 재구성(ax만) | **10/669 (1.49%)** | 154.42s | sccache base-directory 정규화 시도 |

- sc2 부기(측정 에이전트 관측, 원시 기록 미보관): 100% 히트 산출이 무-sccache 빌드 digest(`f163d6b4…`, §6 serial-digests)와 바이트 동일, `SOURCE_DATE_EPOCH` 불요 — 히트 경로 산출 보존 위생 확인.
- sc4의 1.49%: BASEDIRS로 명령행·경로 정규화를 시도해도 §4의 층2(본문 문자열의 절대경로)은 컴파일러가 바이너리에 심는 내용이라 캐시 레이어에서 무력 — **구조적 차단**.
- **절감 상한 계산**: 직렬 콜드 전체 149.00s 중 C 컴파일 총시간 = **17.15s**(870컴파일 × 평균 19.7ms; `.cc.log` 연속 호출 간격의 컴파일 귀속 합 — 원시 로그에서 재계산 가능). -j4에서는 4레인 분산+프론트엔드/링크와 중첩되어 임계경로 기여는 이보다 작다(판정 계산치 ≈2.7s, wall 대비 ~2%).
- **판정**: 교차 워크트리 히트율 2.30%(구조적), BASEDIRS로도 1.49%, 절감 상한 ~2% — **sccache 도입 REJECT**.

## §6. VS-3 병렬화 레버

### 6.1 make -j4 (ci-compile)

- 직렬(wt2 콜드): **149.00s** / `-j4`(wt2 콜드): **129.05s** → **−13.4%**
- 산출 동일성: 4종 바이너리 SHA-256 직렬 vs -j4 **완전 동일** (`serial-digests.txt` == `j4-digests.txt`):
  `c385b13c…` install_ax_cas · `1522301f…` gate_hook · `029586b4…` precompile_gates · `f163d6b4…` ax

### 6.2 precompile_gates 워커 수 (`AXIOM_PRECOMPILE_WORKERS`, wt2 콜드)

| 워커 | 컴파일 루프(`Done in`) | wall | CC |
|---|---|---|---|
| 1 | **272.5s** | 281.14s | 1961 |
| 8 | 70.3s | 79.79s | 1961 |
| 16 | 59.9s | 68.70s | 1961 |
| 기본(미지정) | 64.6s | 73.30s | 1961 |

- 산출 동일성: CAS 바이너리 digest 스냅숏 **w8 == w16 (54/54 완전 동일)**; CC도 전 구성 1961으로 동일.
- **판정**: 16워커가 8대비 이득 ≈10s(부하 의존), 직렬 대비 8워커 ≈4.3배 — **기본값 8이 근최적**.

### 6.3 LTO 링크 레버 (`--passL:-flto=N`, wt1, 웜 nimcache)

| 구성 | wall | 링크 지속(§1 산출) |
|---|---|---|
| 기본 `-flto=2`(paired) | **127.81s** | ≈108.1s |
| `-flto=16` (r2, 페어 부하) | **105.03s** | ≈56.2s |
| `-flto=16` (r1, 저부하) | **53.48s** | ≈33.8s |

- 실행 형태: `make -f ci/checker.mk ci-compile-ax NIM="nim --passL:-flto=16"`(원시 기록의 `env NIM=nim --passL:-flto=16 …`은 `$*` 기록에서 인용 부호가 벗겨진 것 — make가 NIM 변수로 확장, 런 출력 9행에서 `nim --passL:-flto=16 c` 확인).
- 산출 digest: 측정 에이전트 관측 `-flto=2`/`-flto=16` 산출 동일(`2fa57b00…`) — **워커 수만 제어하고 partitioning=balanced라 결정론 유지**. 착지 시점 재검증: §10.
- **판정**: LTO 워커 수는 링크 지배 구간(§3)을 2배 가까이 단축 — 유효 레버. 다만 산출 digest 동일성 재확인이 전제(§10).

### 6.4 주변 비용

- **genDepend(pre-push 훅 7쌍)**: 훅 `GATE_PAIRS`는 정확히 7쌍(`.githooks/pre-push` — debt_engine, check_nim_theater, doc_path_validator, proof_unit_consistency_gate, proof_reconcile_gate, epoch_transaction_gate, layer_enforcement_gate). 콜드 캡처 **9.50s**(측정; 각 캡처는 임시 nimcache라 구조상 항상 콜드), 유효 스탬프면 캡처 0회(≈0). 착지 시점 재측정: §10.
- **push 스냅숏**: `make bin/nimtry bin/effect_contract_projection` 콜드 **6.80s / CC 139**(직렬).
- **공유 nimcache 동시 빌드**: 관측 **5/6 FAIL** — DEBT#457(병렬 서브타깃의 공유 생성물 충돌) 패턴 재확인. 재현: §10.
- **debug vs release 도구 해싱**: nim 바이너리(9,619,904B = 9.18MiB) SHA-256 — debug 컴파일 도구 **3.15–7.1s** vs release **47–49ms**(64–150×). 착지 시점 재측정: §10. 매니페스트 생성기는 이 해시를 스크립트당 1회 계산해 54개 매니페스트에 동일 기록(`tools/ci/generate_gate_closure_manifests.sh:68`).

## §7. 판정 정정 (구 주장 → 실측)

| 구 주장 | 실측 정정 |
|---|---|
| "54게이트 ≈50s 직렬" | 직렬 컴파일 루프 **272.5s**(w1, `Done in`), 8워커 64.6s(§6.2) |
| "genDepend 65–69s" | 훅 7쌍 **9.5s**(§6.4). 65–69s는 **54개 매니페스트 전체 생성** 규모 — VS-T 증거 §8(64.5–92s)와 정합. 규모 혼동이었음 |
| "per-gate 3.2s×54" | **런당 1회 3.2s**(debug 도구 기준; release 47–49ms). 생성기는 nim 해시를 스크립트당 1회(§6.4) |
| AXIOM_CI_PRESERVE_CACHE (캐시 보존 목적) | 역사 사실 — 루트 `config.nims`에서 reader가 없는 **no-op**(DEBT#417 해결 기록). `src/gate/config.nims:11-14`의 잔존 참조는 게이트 부트스트랩 가드용(별개 목적) |

## §8. 신규 위험 — CAS under-keying 4/54 (별도 절)

**관측**(원시 기록 `wt1-cas-digests.txt` 55항목 vs `w8/w16-cas-digests.txt` 54항목, 동일 커밋 `5e740d7`의 두 워크트리 CAS 스냅숏 diff):

- 54개 매니페스트 게이트 전부가 **동일한 CAS 키**(디렉터리명 = 게이트ID-클로저해시16-cfg해시16)를 가졌는데, **4개 게이트의 바이너리 digest가 워크트리 간 상이**: `hotspot-gate`, `integrity-test`, `integrity-workflow`, `readiness-start-gate`.
- 나머지 **50개는 바이트 동일**.
- wt1에만 존재하는 `axiom-cli-952ba60e92ae5626-…` 항목은 54 매니페스트 밖 — `install_ax_cas`가 ax 바이너리를 CAS에 등록한 것(`src/cli/install_ax_cas.nim:34,90`).

**원인**: §4의 3층 구조 중 **층2(본문 NIM_STRLIT 절대경로)** — 클로저 CAS 키는 소스 내용만 해싱하므로 동일 소스 = 동일 키인데, 일부 게이트 바이너리는 워크트리 경로를 바이트에 포함해 **키가 이진 정체성을 과소 표현(under-keying)**한다.

**현재 영향**: 없음(무해) — CAS가 per-worktree(`.axiom/cache`)라 허위 재사용 경로가 존재하지 않는다.

**제약**: 크로스워크트리 CAS 공유를 도입하기 **전에는 해소가 필수**다(동일 키·상이 바이너리의 허위 재사용 가능). → 부채 연계 §9. DEBT#523(2026-11-08, 구조 제약 등록)의 증거 심화다.

## §9. 부채 연계 (기존 DEBT#523 — 신규 번호 미등록)

under-keying 구조 제약은 이미 **DEBT#523**(2026-11-08 등록, source `vst_dependency_authority_handoff_2026-11-08`)으로 등록되어 있다 — VS-T 핸드오프가 본 측정 에이전트의 관측을 받아 "클로저 CAS 키의 이원성: 4/54 게이트 바이너리가 체크아웃 경로를 포함, per-worktree CAS라 무해, 크로스워크트리 공유 전 재검토 제약"(`data/debt_registry.json`, file `src/core/gate/gate_cas.nim`)으로 정식 등록했다. 제약과 원인(경로 삽입)이 한 항목에 이미 담겨 있으므로 **신규 부채 번호(DEBT#524)를 만들지 않는다** — 동일 제약의 이중 등록은 중복 의미 상태다. 대신 본 문서 착지와 함께:

- #523 `bindingRationale`의 trace를 본 문서로 연장(메커니즘 §4 · 정량 §8 · 재검증 §10).
- 레지스트리 `scanner` 필드에 심화 기록(2026-11-09, 사유 포함) 추가.

검증: `bin/debt_engine --validate` green (EXIT=0) — 관측 기록 §10 말미.

## §10. 착지 시점 재검증 (2026-11-09, base `2c48285`)

본 문서 착지 시점에 현재 main에서 재측정한 항목(측정 기반이 `5e740d7`이므로 판정의 현행 유효성 확인):

- **genDepend 훅 7쌍**: `PREPUSH_SOURCE_ONLY=1 source .githooks/pre-push` 후 7쌍 `pp_capture_manifest` 연속 실행 → **8.90s / 8.92s**(2회) — 측정치 9.50s와 동일 규모.
- **sha256(nim 9.18MiB)**: debug 도구 **3.17–3.28s** / release 도구 **0.05s**(52–65×) — 측정치(3.15–7.1s / 47–49ms, 64–150×)와 동일 규모. 상한 7.1s는 부하 조건.
- **3층 구조 실물**: §4의 인용(헤더 명령행·본문 NIM_STRLIT·.o 경로)은 모두 base `2c48285` 빌드 캐시에서 직접 관측한 것이다.

**재검증 실행 결과**(2026-11-09 01:20–01:31 KST, 원시 로그 `~/.cache/axiom/vs23-lab/vs23_bg_tests.log`, 스크립트 `~/.cache/axiom/vs23-lab/vs23_bg_tests.sh`):

- **공유 nimcache 동시 빌드(§6.4 재현)**: 신계보 `origin/main df378f6` detached 워크트리에서 6개 동시 `ci-compile`(nimcache 1개 공유) → **5/6 FAIL 재현**(rc=2, 링크 오류; 생존 1개 rc=0 146s) — DEBT#457 패턴이 재작성 후 main에서도 현행 유효.
- **LTO 결정론(§6.3 전제 충족)**: 증거 워크트리(base `2c48285`) 웜 nimcache에서 기본 `-flto=2`와 `-flto=16` 재빌드 → ax SHA **동일**(`1bea82ccbeafef4f…d2ce`) — 워커 수 제어는 산출을 바꾸지 않음.
- **under-keying 현행 재현(§8 보조 관측)**: 증거 워크트리(`2c48285`)에서 `ci-compile-precompile-gates` 빌드 rc=0 + `./bin/precompile_gates` 54/54 OK → 워크트리 CAS 54키를 main 저장소 CAS(`/workspace/Axiom/.axiom/cache/gates`, 역사 축적 169항목, 최종 기록 11-08 15:31 KST)와 키별 대조: **키 교차 3개** — 2개 바이트 동일(`conflict-marker-gate-e4fc…`, `hotspot-coverage-gate-250b…`), **1개 동일 키·상이 digest**: `readiness-start-gate-6850ea1d0464023e-2127f750231f4a04`(워크트리 `638f84fb…` vs main 저장소 `9c59ba0c…`). 나머지 51키는 main CAS에 대응 키 없음(커밋 간 클로저해시 변동 — 동일 커밋 통제 비교가 아니므로 §8의 4/54가 원본 계측이고, 본 관측은 착지 시점·상이 디렉터리에서 현상이 소멸하지 않았음을 확인하는 보조 관측이다).
- **부채 레지스트리 검증(§9 변경 후)**: `bin/debt_engine --validate` → **Checks: 1598 total, 1598 passed, 0 failed, EXIT=0**(2026-11-09 관측; #523 trace 연장은 투영 계약 밖 필드라 markdown·constants·ledger 동기화 불필요).

**원시 기록 보존 이동**(2026-11-09): §10 재검증의 원시 로그·스크립트는 실행 시점에 휘발성 `/tmp/vs23_bg_tests.log`·`/tmp/vs23_bg_tests.sh`에 기록되었으나, 2026-11-09에 영구 보존 위치 `~/.cache/axiom/vs23-lab/`으로 cp 이동했다(이동 후 관측: log 1,083B·sh 3,454B 실재 확인 — 본 절의 경로 인용은 보존 위치 기준).

## §11. 재현 명령

```
# 원시 요약 재계수 (e1a 예)
awk -F'\t' '{n=split($2,a," "); if (a[1]=="-c") c++} END {print c+0}' ~/.cache/axiom/vs23-lab/e1a-cibootstrap-cold-r1.cc.log

# wall/exit/CC 요약은 각 e*.out 말미 --- summary --- 블록
# sccache 통계는 각 sc*.out 말미 --- sccache stats --- 블록

# precompile 워커 스케일 (산출 동일성: .axiom/cache/gates/*/binary sha256 비교)
env AXIOM_PRECOMPILE_WORKERS=1 ./bin/precompile_gates    # "Done in 272.5s"

# LTO 레버 (산출 digest 비교)
make -f ci/checker.mk ci-compile-ax
make -f ci/checker.mk ci-compile-ax NIM="nim --passL:-flto=16"

# genDepend 7쌍 타이밍
PREPUSH_SOURCE_ONLY=1 bash -c 'source .githooks/pre-push; PP_FLAGS="$(pp_canonical_flags)";
  for pair in "${GATE_PAIRS[@]}"; do pp_capture_manifest "$(pwd)/${pair##*:}" "$PP_FLAGS" "$(mktemp)"; done'

# under-keying 재현 (동일 커밋 2워크트리 CAS 비교)
#  각 워크트리: ./bin/precompile_gates 후 sha256 .axiom/cache/gates/*/binary — 키(디렉터리명)별 대조
```

## §12. Follow-up (범위 밖)

1. LTO 링크 레버(-flto=16) 적용 검토 — 링크가 웜 빌드 wall의 ~83%(§3). 산출 digest 동일성(§6.3/§10)이 전제.
2. 크로스워크트리 CAS 공유 설계 시 §8 under-keying 해소 선행(바이너리 자체 콘텐츠 주소화 또는 경로 스크럽 빌드).
3. CI ci-compile의 4종 중 3종이 debug 빌드(`checker.mk:519-527`) — §6.4의 debug/release 해싱 격차와 같은 구조(도구 디버그 페널티) 원칙 기록.
