# VS-PERF-ATTR — Warm Prove Attribution & Verified Deduplication

- **Workstream**: `workstream/vs-perf-attr` — `21323a2`(base) → `b2f6452`(Phase A 계측) → `1288cac`(핀) → `fb4012a`(Phase D: sha256sum 위임) → `21a2850`(핀 재앵커)
- **날짜**: 2026-11-16
- **정본 측정 기록**: `/tmp/vs-perf-attr/ci-scope/measurements.json`(Phase A′ B0/B1 A/B·위상표·②③④ 판정)·`/tmp/vs-perf-attr/hash-bench/{report.md,results.json}`(⑤ 귀속·release baseline)·`/tmp/vs-perf-attr/ab/`(Phase D A/B: release 5회·debug 3회·before/after projection)
- **보정 프로토콜 기록**: `/tmp/vs-perf-attr/rebaseline/protocol-log.json` — 드리프트 판정 무효화·B0 수렴 3경로 재현·사건 원장.
- **완료 정의**: 코드 변경이 아니라 **실제 운영 상태** — main 착지 후 재관측된 개선(또는 부정 결과의 수치 고정). 랜딩 증거는 §9 말석 프로토콜에 따라 PR에 영속한다.

---

## §1. 목적과 궁극적 목적

검증 의미론(의미론 필드의 바이트 동일성)·결정론(동일 입력 → 동일 출력)·증거(감사 추적)·무결성(정본 SSOT·digest 정체성)·GitHub 병합 권한(6대 required checks)을 그대로 보존한 채, **동일한 사실을 반복 계산하는 구조적 비용만 제거**한다. "빠른 Axiom"이 아니라 **불필요한 일을 하지 않는 Axiom**.

## §2. 권한 프리플라이트

- **merge 판정 권한 = GitHub**(ruleset·required checks·queue·병합). 랜딩 필수 6대 required checks(워크플로 파일 존재 확인, 2026-11-16):
  - `admission-check` — `.github/workflows/admission-check.yml:107`
  - `bsec-integrity` — `.github/workflows/bsec-integrity.yml:61`
  - `debt-registry-gate` — `.github/workflows/debt-registry-gate.yml:1`
  - `generation-acceptance` — `.github/workflows/generation-acceptance.yml:49`
  - `axiom-operational-slice` — `.github/workflows/axiom-operational-slice.yml:12`
  - `publication-integrity` — `.github/workflows/publication-integrity.yml:1`

  required checks 0건 관측 = UNKNOWN / NOT READY — SUCCESS로 해석하지 않는다(AGENTS.md §2.3). 어댑터·리포터는 authority가 아니다.
- **검증 판정 권한 = Axiom**: `ax prove`의 `GateVerdict`·canonical digest가 유일한 판정 authority.
- **범용 작업의 외부 실행 주체 위임**: 컴파일(`nim c`·`lake build`)·파일 해시(`sha256sum`, GNU coreutils 9.4 — SHA-NI 하드웨어 경로)·프로세스 대기·아티팩트 보관은 외부 실행 주체가 수행한다. 서브프로세스 호출은 GPL 무의무(mere aggregation)이며 재배포 없음.
- **권한 위임 기록(사용자 원문, 2026-11-16)**: "권한이 필요한 부분은 전면 승인한다." — push·PR 생성·GitHub native merge(6대 required checks 전부 success 관측 후) 포함. merge 판정 자체는 GitHub이며 본 슬라이스는 관측만 한다.

## §3. 측정 계약

- **워크로드**: `AXIOM_CI=1 ./bin/ax prove --target normalizeMaxWorkers` — `make verify-contract-release-e2e-full`(Makefile:942, G7-full)의 prove 단계로, CI가 기계 검증하는 유일한 prove 워크로드.
- **대상 빌드**: B0 = 순정(`main 21323a2` 정확 재현, provenance 일치 확인). B1 = 계측 트리(`b2f6452`). Phase D A/B after = `21a2850`(위임 구현). release 빌드는 CI 정본 레시피(`ci/checker.mk` ci-compile-ax: `AXIOM_HERMETIC_BUILDING=1 nim c -d:release --hints:off --nimcache:build/nimcache/ci-compile/ax -o:bin/ax src/cli/main.nim`).
- **툴체인**: Nim 2.2.10(핀)·GNU coreutils 9.4·AMD Ryzen 9 5900HS(16T, Zen 3, SHA-NI)·30Gi RAM.
- **프로토콜**: 런타임 상태 리셋 → 웜업 1회 **버림** → 웜 캐시에서 실측(release 5회·debug 3회). 대표값 **median**(min은 보조). `/usr/bin/time -v`; run별 `./bin/ax report --canonical-digest`·stdout/stderr·`git status --porcelain` 체크. before/after는 백투백(동일 부하 창·동일 기계).
- **CAVEAT (debug vs release)**: B0/B1은 debug 빌드(Makefile:364 preflight 패턴과 동일 형태). CI 정본은 release. debug 수치는 상대 비교(A/B 오버헤드·귀속)에 유효; release 수치는 §7·§7.5의 hash-bench·Phase D A/B가 담당.
- **선행 무효화**: 구 전체 스코프 웜 baseline(29.68s)은 EA 미실행 replay 분포로 **측정 전제로 무효**(`rebaseline/protocol-log.json`). 방법론 규칙: **실패 실행(exit≠0)의 wall·digest·trajectory는 측정 증거로 사용하지 않는다**(부록 A).

## §4. 결과 — B0/B1 A/B (debug 빌드, 웜 캐시, 각 5회)

출처: `/tmp/vs-perf-attr/ci-scope/measurements.json` (원시 `ci-scope/b0/`·`ci-scope/b1/`).

| 항목 | B0 (순정) | B1 (계측) |
|---|---|---|
| wall 5회 (s) | 75.43 / 75.56 / 75.40 / 75.01 / 74.95 | 76.32 / 76.19 / 76.62 / 75.85 / 75.68 |
| **median (s)** | **75.40** | **76.19** |
| exit 5회 | 전부 0 | 전부 0 |
| canonical digest | `f4b3553e…` ×5 동일 | `6fea2b2f…` ×5 동일 + salvage 3회 동일 |

- **계측 오버헤드**: +0.79s(+1.05%). stdout+stderr가 **18회·2바이너리에서 바이트 동일** — 계측은 출력 바이트를 0 추가한다.
- **digest 차이의 완전 귀속**: B0→B1 projection diff의 10개 leaf 전부 identity/timing 필드(verifierBuildId·monotonic 타임스탬프·elapsedMs). 의미론 필드(verdict·nodeReports·evidenceLog·solverStatus·summary·census·eligibility)는 바이트 동일 → 계측은 진단 데이터이며 검증 의미를 변경하지 않는다(A/B 실증; 사용자 요구 "계측 시간은 검증 판정에 입력되지 않는다"의 기계 확인).

## §5. 결과 — B1 위상표 (debug, median ms)

| 위상 | B1 median | min |
|---|---|---|
| topology | 10893 | 10872 |
| prepare | 11686 | 11646 |
| ir_thread_window | 7722 | 7687 |
| waves | 50648 | 50337 |
| pipeline | 50495 | 50183 |
| canonical_run_accounting | 4813 | 4802 |
| graph_hydration | 8297 | 8251 |

파생: **main-thread pre-IR serial ≈ pipeline − ir_thread_window ≈ 42,773ms** — 후보 ⑤의 `ircheckWorkerBinaryDigest`(119MB debug ircheck 바이너리 in-process sha256)가 이 창을 지배(§7).

## §6. 후보 판정 — ② vault 재파싱 · ③ 그래프 이중 해시 · ④ IR 스레드 창

출처: measurements.json `exclusive_234` (코드 계약은 저장소 읽기 검증).

- **② vault reparse/rehydrate — NOT MATERIAL**: exclusive **2ms**/실행. B0 run-to-run stdev(244ms)의 1/122.
- **③ graph double-hash — NOT MATERIAL (구조적으로도 중복 아님)**: graph-merkle-hash와 lock-recompute는 `commitUniverseIntegrityAndLock`(`src/verification/proof_universe_commit.nim:284-308`) 내 상이한 순차 계산. 웜 경로는 5회 전부 `canSkipRematerialization` 스킵 → commit 0ms.
- **④ IR thread window 7722ms — 중복 아님 (실작업)**: parse-bound 성분은 IR 워커 스폰 전 메인 스레드에서 측정되어(`ir_pipeline_runner.nim:1769-1772`) 파이프라인이 소비할 사전 계산 IR을 공급한다.
- **결론 (②③④)**: **"No material redundant cost identified"** — 부정 결과로 수치 고정. Phase D의 제거 대상이 아니다.

## §7. 후보 ⑤ — EA ircheck binary digest: 귀속 확정

**코드 계약**(`src/verification/obligation/canonical_verification.nim:1021-1045`): `ircheckWorkerBinaryDigest` — ~119MB ircheck 바이너리의 in-process sha256, 프로세스당 1회(stat-identity 메모). `measured_digests.nim:106-176` — read-then-restat 안정성·racy-window 재검증·fail-closed(`""`).

**구현체 규명(hash-bench Step 1)**: `checksums/sha2`는 100% 순수 Nim·**바이트 단위 버퍼링**(`shaUpdate`가 octet마다 복사)·SHA-NI 없음. debug(-O0+런타임 체크)에서 119MB = **45,005.6ms**(2.66MB/s), release(-O3) = **618.1ms**(193.5MB/s) — 72.8× 격차. 모든 프로브 digest 동일(`1d0bb732…53374d`).

**대안 관측**: `sha256sum`(GNU 9.4, SHA-NI 하드웨어 경로) 동일 파일 = **0.09s** — release 순수 Nim 대비 6.9×, debug 대비 ~500×. digest 동일.

**release 운영 baseline(CI 정본, 5회)**: steady median **6.16s**(전부 exit 0·porcelain clean·stdout empty). steady digest `6fea2b2f…` = B1 debug digest와 동일 — **canonical digest는 bin/ax 바이너리 정체성·빌드 모드에 무불변**(release가 동일 검증 결과를 재현). 위상: pre-IR serial 1334ms = in-process 해시 738ms(55%) + ircheck 서브프로세스 111ms(8%) + 잔여 485ms — **해시가 최대 단일 성분**.

**76s의 정체 = debug 빌드의 해시 인플레이션**: 개발 preflight(Makefile:364)는 `-d:release` 없이 `nim c`로 빌드 → 119MB 해시가 45s로 인플레이션되어 웜 prove가 75-76s가 됨. CI는 release(6.16s). 낡은 주석 "~60 s"(EA digest 1회 비용)는 debug 기준으론 대략 정확했으나 release 기준으론 부정확 — Phase D 커밋이 주석을 진실로 교정했다.

**정정 기록(측정 무결성)**: 초기 "release 0.6s로 반증됐다"는 통보는 **오판**이었다 — 당시 `bench_dgr`이라 명명된 벤치가 실제로는 `-d:danger` 빌드였고, 정본 release(-d:release)는 618ms·debug는 45.0s. 벤치 라벨과 실제 컴파일 플래그 일치가 측정 무결성의 전제라는 교훈을 본 슬라이스가 채택한다(모든 수치는 빌드 명령 원문과 함께 기록).

## §7.5. Phase D — 구현과 A/B 결과

**변경(`fb4012a`)**: `measured_digests.nim`의 `readStableAndStoreMemo`에 **크기 게이트 위임** — `> MaxInlineProbeBytes`(1MiB)인 파일의 digest를 `/usr/bin/sha256sum` 서브프로세스(argv 리스트, `execCmdEx` 아님 — 셸 평가 회피)로 계산. 도구 부재·실행 실패 시 in-process로 강등(best-effort 주석). 기존 안정성 계약 유지: stat→측정→restat 일치 확인·racy-window 재검증·fail-closed(`""`)·memo 키(stat identity). **신규 의존성 없음·신규 영속 캐시 없음·검증 권한 변경 없음** — "Axiom은 판정을, OS 도구는 해시 계산을 소유한다"(사용자 원칙 ① 위임 표의 구현).

**값 동일성(기계 증명)**: memo 테스트 18/18 — 시나리오 "1.1MB(>1MiB)가 위임 경로를 타고 `digest == sha256Hex(payload)` 직접 단언"·"워커 바이트 변경 시 digest 변경"·"EA 2호출 동일 digest" 포함. toolchain fingerprint 테스트 15/15.

**A/B — release(CI 정본, 5회, 백투백)**:

| 항목 | before(구현 전, 22:29-22:37) | after(`21a2850`, 23:03-23:04) |
|---|---|---|
| wall 5회 (s) | 6.24 / 6.19 / 6.13 / 6.13 (+warmup 6.85 버림) | 5.07 / 5.05 / 5.08 / 5.12 / 5.09 |
| **median (s)** | **6.16** (steady 2-5) | **5.08** |
| exit | 5/5 = 0 | 5/5 = 0 (warmup 포함 6/6) |
| canonical digest | `6fea2b2f…` ×4 steady | `449b27bc…` **×5 동일** |
| porcelain | 비어 있음 ×5 | **비어 있음 ×5** (Zero-Footprint) |

**개선: -1.08s(-17.5%)** — after stdev 0.026s 대비 ~41σ, B0 stdev(244ms)·release steady spread(±55ms) 대비 유의미.

**A/B — debug(개발 preflight 형상, 3회)**: B1 median **76.19s** → after **24.75s**(25.11/24.71/24.75) = **-51.4s(-67.5%)**. digest `449b27bc…` ×3 동일 = release after digest와 동일(빌드 모드 무불변 재확).

**위상 귀속(동일 추출 스크립트, run5 대 run5)**:

| 위상 (ms) | release before | release after | Δ | debug before | debug after | Δ |
|---|---|---|---|---|---|---|
| prepare | 1000 | 952 | -48 | 11646 | 11544 | -102 |
| topology | 808 | 774 | -34 | 10872 | 10786 | -86 |
| ir_thread_window | 3113 | 2886 | -227 | 7702 | 3017 | **-4685** |
| waves | 4476 | 3582 | **-894** | 50337 | 4239 | **-46098** |
| pipeline | 4445 | 3551 | -894 | 50183 | 4087 | -46096 |
| accounting | 163 | 86 | -77 | 4810 | 150 | **-4660** |
| graph_hydration | 285 | 281 | -4 | 8251 | 8205 | -46 |
| **pre-IR serial** (pipeline−ir_thread) | **1332** | **665** | **-667** | 42481 | 1070 | -41411 |
| **wall median (s)** | **6.16** | **5.08** | **-1.08** | **76.19** | **24.75** | **-51.4** |

귀속 해설: release pre-IR serial -667ms ≈ 119MB in-process sha256 738ms → sha256sum 90ms(§7 성분 분해와 정합). debug waves/pipeline -46.1s = 동일 해시의 debug 인플레이션(45.0s) 제거. debug ir_thread -4.7s·accounting -4.7s = 13MB `~/.elan/bin/lake`의 in-process 해시 2건(debug ~5s/건)이 위임으로 전환. prepare/topology/graph의 작은 Δ(-4~-102ms)은 측정 분산 범위. 위상은 병렬(ir_thread 스레드)이라 명목 합(-1.28s)이 wall 개선(-1.08s)을 약간 초과 — 중첩 감안 정합.

**위임 실증(execve 관측, strace -f -s 4096 -e trace=execve)**:

```
$ AXIOM_CI=1 strace -f -s 4096 -e trace=execve ./bin/ax prove --target normalizeMaxWorkers
exit=0
$ grep 'execve.*sha256sum' strace-execve3.txt   # 대상 경로 3건
$HOME/바탕화면/develop/Axiom2/proofs/.lake/build/bin/ircheck
$HOME/.elan/bin/lake
$HOME/.elan/bin/lake
$ git status --porcelain   # 관측 실행 후
(빈 출력)
```

**의미 보존(projection diff, before/after report JSON)**: diff 24줄(12쌍) 전부 타이밍/정체성/카운트 필드(startedAtMs·endedAtMs·elapsedMs·timestamp·totalWallTimeMs·parallelOverheadMs·verifierBuildId·activeNodeCount·symbolCount). 의미론 필드(verdict·nodeReports·evidenceLog·solverStatus·summary·census)는 **바이트 동일**. `symbolCount 16042→16043`(+1)의 귀속: Phase D 신규 proc `delegatedFileDigest`가 그래프 재스캔에 반영(`grep -c delegatedFileDigest logs/global_symbol_graph.json` = 1) — 검증 대상 소스 자체의 변경분이며 판정 의미와 무관. digest `6fea2b2f…`→`449b27bc…`는 소스 정체성 이동분으로 완전 귀속(§4와 동일 구조).

## §8. 발견 등록 (발견≠권한, 본 슬라이스에서 수정하지 않음)

- **DEBT#547 (F-1) — 전체 스코프 fresh prove의 결정론적 실패**: 순정 B0이 fresh·lake 재빌드·신규클론 등가 3경로 전부 exit 1 — `safeSpeedupRatioCore` sealError `EA_UNSUPPORTED: unsupported AST node (ckIfStmt) outside the certified-subset wire set` → `unsatisfiedCount=1` → GateVerdict FAIL. EA_UNSUPPORTED는 skip이 아니라 FAIL(`attestation_orchestrator.nim:370, 676`). 사유 코드: `src/verification/extraction_agreement.nim:72`.
- **DEBT#548 (F-2) — CI 스코프 exit 0의 웜 캐시 취약성**: exit 0는 파괴 가능한 웜 상태에 의존하며 자가 회복 경로 없음(소스 변경 1회로 무효화 — 계측 시 EA 재측정이 F-1로 실패). 웜 상태 재수립은 웜업 런으로 관측됐으나(release run1의 cold-recovery 자가 회복 사례) 정책화되지 않음.
- **DEBT#549 — CI 커버리지 갭**: CI(Makefile:942)는 단일 타깃 normalizeMaxWorkers만 검증 — fresh 전체 스코프 prove 경로는 미커버(F-1이 CI에서 관측되지 않는 이유).
- 등록: `data/debt_registry.json`(contentHash = 첫 files 파일 전체 sha256; `debt_engine --codegen`·`--sync-budget`(BUDGET#005 34→37)·`--validate`·`ax debt sync --check`·`debt_integrity_gate` 순차 통과).

## §9. 랜딩 증거

- **커밋**: `b2f6452`(계측)·`1288cac`(핀)·`fb4012a`(Phase D)·`21a2850`(핀 재앵커) + 본 증거 문서·DEBT#547-549 등록 커밋 — `workstream/vs-perf-attr`.
- **로컬 Phase E 게이트**: §10(아래)에 명령·결과 기록.
- **PR·merge·main 재실행**: PR 번호·6대 required checks 전부 success 관측·GitHub native merge SHA·main에서의 재측정(개선 재관측 ± 분산)은 **PR(#<N>)에 코멘트로 영속**한다(본 문서의 사후 개정은 별도 슬라이스). 선언·PR 생성·부분 CI 성공은 완료가 아니다 — 6대 checks 0건 관측 = UNKNOWN.

## §10. Phase E — 로컬 게이트 관측 기록

관측 트리: `workstream/vs-perf-attr @ 21a2850` + 본 커밋의 미커밋 등록물(레지스트리·증거문서).
전부 실제 명령·exit 코드 관측(2026-11-17, 로컬 웜 journal 상태).

| 게이트 | 명령 | 결과 |
|---|---|---|
| debt codegen | `bin/debt_engine --codegen` | PASS — 280→281 entries(DEBT#550), P1=complete |
| debt sync-budget | `bin/debt_engine --sync-budget` | PASS — "0 record(s) updated"(멱등) |
| debt validate | `bin/debt_engine --validate` | **PASS — 1759/1759** (550 등록 전 280 entries 시 1753/1753; 교차커버리지 §5/6 포함) |
| ax debt sync --check | `bin/ax debt sync --check` | exit 1 — **선존 red**(status drift 36 = 선존 32 + DEBT#547-550; hash drift 108은 선존 그대로, 547-550은 hash-drift에 없음=contentHash 유효) |
| debt integrity gate | `bin/debt_integrity_gate` | PASS — "All 38 open debts have code markers"(18 marker-bound + 20 registry_disposition-bound, 23 `{.axiomDebt.}` markers) |
| fast tests | `make test-fast` | FAIL exit 2 — 1차: 루트 `.nimcache` 잔류(gitignored, mtime 2026-11-14, 선존)가 validate-root-layout 차단 → 삭제 후 재실행: 유닛 3 실패(ut28/44/52) — **전부 귀속 완료, 아래 참조(본 슬라이스 무관 실증)** |
| static verify | `make local-verify-static` | FAIL exit 2 — check-arch: nimtry "1 new ERROR violations not in baseline"(`src/infrastructure/provenance_probe.nim` LCOM=0.667 > 0.6) — **브랜치 베이스 21323a2 worktree에서 동일 재현 = main 선존**; 선행 서브게이트 전부 PASS(validate-root-layout 32개 검증기 테스트 포함) |
| perf regression | `make perf-check` | **PASS** — LeanKernelVerification 0.0% change |
| verify-contract | `make verify-contract` | **PASS** (236s) |
| G7-full | `make verify-contract-release-e2e-full` | **PASS** (72s) — cert verify PASS(kernel re-execution, tier=dual-verified) |
| provenance | `./bin/ax --check-provenance` | **PASS** — embedded BuildSourceHash == live src tree |
| git purity | `make check-git-purity` | FAIL — 의도된 미커밋 등록물 존재(커밋 직전 상태); 커밋 후 재실행으로 종결 |
| CI admission 미러 | `make test-fast-one` × 4 (GO-CRITICAL: s1a_lean_golden·proof_integrity·d2_golden·d2_persist) | **4/4 PASS** (25s·12s·16s·12s) — required checks가 실제 실행하는 유닛 세트 |

### §10.1. test-fast 유닛 3 실패의 기계적 귀속 (전부 "본 슬라이스 무관" 실증)

- **ut28 `test_vkd_determinism`** — DEBT#550 등록으로 종결. 인과 사슬(전부 실측):
  1. 파일 단위 바이섹트: HEAD 실패 / measured_digests 단독 원복→통과 / type_registry_metadata 단독 원복→실패 / canonical_verification(주석만) 단독 원복→통과. (a)·(c)의 통과는 src 바이트 변화→BuildSourceHash 불일치→engineBuild "unmeasured"→양측 0의 **퇴화 일치**임을 프로브로 확인(고침이 아님). (b) 유지 실패 = src/generated이 BuildSourceHash 매니페스트에서 제외됨과 정합.
  2. 4호출 in-process 프로브: direct×2=1 → report=0 → direct=1(호출 간 상태 오염 없음 — report 호출 자체의 차이).
  3. 판별 프로브: `findRepoRoot()` = **빈 문자열**(/tmp 바이너리+repo CWD에서 워크업이 `""` 도달, `fileExists("" / ".axiom_root")`가 CWD 상대 매치). `getCanonicalVkdMetrics("")`→admission 0 vs `(cwd)`→1.
  4. 결정론: 4/4 동일 실패(각 0.42s — 타이밍·racy 무관).
  5. 선존성: `git diff 21323a2..21a2850 -- src/core/utils/repo_root.nim` = 빈(diff 무관) + 베이스 21323a2 클린 worktree(journal 없음)에서 **PASS**. CI 체크아웃도 journal 없음(gitignored) → 양측 0 → 통과 — 6대 required checks에 영향 없음. 발화 조건 = "웜 journal(A/B prove가 기록) × findRepoRoot("") 선존 결함".
- **ut44 `test_bug_verdict_projection` / ut52 `test_rust_guard_attempt`** — 베이스 21323a2 클린 worktree(CI 등가 상태)에서 각 9·6 실패 = **main 선존**. 실패 집합이 런타임 상태(journal subjects)에 따라 변동(상태 의존 설계). CI admission 세트(GO-CRITICAL 4종)에 포함되지 않음. main은 이후 ut44를 인라인 fixture로 재작성(subject excision) — 병합 후 재판정.
- **step7 check-arch** — 베이스에서 동일 실패(provenance_probe LCOM) = main 선존. required checks는 check-arch를 실행하지 않음(debt-registry-gate는 bin/nimtry 없이 debt_integrity_gate만 실행 — workflow 주석 명시).

### §10.2. 원시 산출물 소실 사건 (정직 기록)

- 2026-11-17 01:0x경 `/tmp/vs-perf-attr/` 하위 원시 아티파트 대량 소실(ci-scope·hash-bench·ab·drift-forensics·before-report.json 포함; 원인 미확정 — 타 세션의 /tmp 정리 후보). 잔존 phase-e·context7-landing은 `~/.vs-perf-attr-backup/`에 백업 완료.
- **수치는 본 문서 §4-§7·세션 wire.jsonl에 기록 보존**; 원시 바이트 재현 불가. 재측정 프로토콜: §3 계약(동일 커밋·툴체인·캐시 조건, 5회 median)으로 before/after 재구축 가능 — 병합 트리에서의 재측정은 §9 계약에 따라 PR 코멘트에 영속.

### §10.3. origin/main 병합 후 재검증 (2026-11-17 02:2x-02:3x, merge `7cf3d83`)

- **병합 범위**: origin/main 17커밋(PR #121 readiness 7th required check·#117 T3·#116 C3·#115 VS-3·#114 subject-excision 포함). 충돌 2건: `config/trusted_writer_set.json`(axiom_engine 핀 — 병합 union blob `4b68f6e6…`로 재앵커, merge_cli 핀은 main 값 취득; **890핀 전수 대조 후 전부 일치**)·`data/architecture_debt.json`(`--regen-arch`로 axiom_engine+merge_cli 재계산). 공식 검증: `bin/reanchor_pin --ref HEAD` = **OK no-drift**.
- **GO-CRITICAL(병합 트리) 4/4 PASS**: s1a·proof_integrity·d2_golden·d2_persist 전부 exit=0.
- **ut44 재판정: exit=0** — main의 subject-excision 재작성(`959b70b`)이 base 선존 실패를 해소. §10.1의 "병합 후 재판정" 완결: 사전 귀속(선존) 유지 + main에서 수리 확인.
- **ut52 재판정: exit=2** — 신규 tri suite 2단언 실패(L376 `not rec.attempted`·L379)+`/tmp/opencode/ax-one` 외부 프로그램 실행 실패(타 세션 소유 바이너리 — 비-허메틱 /tmp 의존). base 선존(6실패)과 동일 계열·admission 세트 외·본 슬라이스 변경 무관(measured_digests/canonical_verification은 rust guard 경로 무관).
- **부수 관측**: `test_sidecar_binding`(main이 병합에서 수정, 6 단언 실패 — sidecar 로딩 `loaded.isOk()`)·ut28(DEBT#550, 웜 journal 상태) — required checks admission 세트 외. 정직 기록으로 남기고 수정하지 않음(발견≠권한).
- **debt 게이트(병합 트리) PASS**: codegen P1=complete·sync-budget 0 updates·validate 전건·debt_integrity_gate 38 open 전체 마커 바인딩.
- **A/B 재측정(병합 트리, §3 계약 — CI 정본 레시피 재빌드 `ci/checker.mk` ci-compile-ax)**: warmup 5.88s 버림 → 5회 **5.13/5.14/5.17/5.22/5.16s, median 5.17s** · exit 0×5 · `git status --porcelain` 비어 있음×5 · digest `3a57e7b5…`×5 동일. vs baseline 6.16s = **-0.99s(-16.1%)** — 개선은 병합 트리에서 유지. pre-merge after(5.08s) 대비 +0.09s·digest `449b27bc…`→`3a57e7b5…` 이동은 main 병합분의 소스 정체성 이동(axiom_engine 등 재작성)으로 귀속 — §4·§7.5와 동일 구조(digest는 소스 정체성 추적). release에서 debug 인플레이션 레인은 본 재측정 범위 외(§7.5 참조).

## 부록 A — 측정 사건 기록 (방법론 교훈)

- **드리프트(판정 무효화)**: 최초 계측 시도가 EA 재측정을 트리거해 웜 상태 파괴 → 5회 전부 exit 1 — **실패 실행은 측정 증거로 무효**, 전량 폐기·포렌식 보존(`/tmp/vs-perf-attr/drift-forensics/`).
- **CI 스코프 incident(출력 경로 버그)**: `sed` 경로 치환 미매치로 B1 run 1-3이 B0 원시 파일을 덮어씀 → 감지·중단·salvage·전량 redo 백투백으로 회복. salvage B1 출력이 B0 pass-1 출력과 바이트 동일 — "계측 무출력"의 교차 확인.
- **bench 라벨 사고**: "release 0.6s 반증" 오판(§7 정정 기록) — `-d:danger`로 명명 오류. 빌드 명령 원문과 함께 기록하는 계약으로 재발 방지.
- **혼란 인자**: 타 kimi 세션 + Chrome 부하 — 백투백 창으로 완화. A/B after 실측(23:03-23:04)은 baseline(22:29-22:37)과 동일 세션·수십 분 간격.
- **원시 데이터 보존**: 원래 repo 밖 `/tmp/vs-perf-attr/`(Zero-Footprint 계약) — 이후 §10.2의 소실 사건 발생. 본 문서는 수용 증거만 저장소에 남긴다.
