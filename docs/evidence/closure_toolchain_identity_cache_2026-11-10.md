# 클로저 툴체인 정체성 프로세스-수명 캐시 — 실행 증거 (2026-11-10)

> **종류**: 실행 증거(execution evidence)다. DEBT#522 잔여 반쪽 — `loadProjectClosure`
> 호출마다 ~9.2MB nim 바이너리를 sha256 해싱하는 비용(비릴리즈 도구에서 ~3.2–3.4s/호출,
> 릴리즈에서 ~59ms/호출)을 프로세스-수명 정체성 캐시로 제거한 슬라이스의
> 명령→관측→exit 기록이다. 모든 수치는 아래 명령으로 재현 가능한 기계 관측이며,
> 관측 환경은 기록된 그대로다.
> **브랜치**: `workstream/closure-toolchain-hash` (base: main `5f3595a`, PR #59).
> **구현 파일**: `src/core/gate/closure_manifest.nim`(정체성 캐시 — 유일한 소스 변경),
> `data/debt_registry.json`(DEBT#522 disposition), `data/architecture_debt.json`
> (regen-arch), 본 증거 문서.
> **측정 환경**: nproc 16, RAM 30GB, Nim 2.2.10(choosenim, 바이너리 9,619,904B,
> mtime 2026-08-26 — 측정 기간 내 불변), Ubuntu Linux, 워크트리
> `~/.cache/axiom/worktrees/closure-toolchain-hash`.

---

## §1. 임무 배경 (관측)

- DEBT#522 resolution(PARTIAL 2026-11-09, ζ PR #34)이 잔여로 남긴 항목:
  "~3.5s nim-binary sha256 per loadProjectClosure call in non-release tools
  (no memoization by design)". ζ 문서 §9가 이를 Follow-up으로 예약.
- ζ #34 착지 후 warm precompile이 15s 수준으로 단축되면서 클로저 신원 해싱의
  상대 비중이 상승 — 본 슬라이스 관측(main `5f3595a`): warm precompile 전체 wall
  14.8s 중 클로저 신원(해시+`nim --version` exec)이 **~3.3s(≈23%)**.

## §2. 코드 조사 (기계 확인)

- `src/core/gate/closure_manifest.nim:252–274`(구) — 툴체인 신원 검증이 매 호출마다
  ① `readFileOpt(nimExe)`(9.2MB 판독, debug 7ms) ② `sha256Hex`(debug 3192ms /
  release 59ms) ③ `execCmdEx("nim --version")`(2ms)를 반복 계산. 신원 **비교**는
  매니페스트 헤더(NIM_SHA256/NIM_VERSION) 대 라이브 툴체인 — 검증 자체는 매 읽기
  수행된다(per-read revalidation, `docs/spec/verification_dag_contract.md` §5).
- **호출 빈도(프로세스당, strace -f -e execve 기계 관측)**:
  - `bin/precompile_gates`(-d:release, checker.mk ci-compile-precompile-gates):
    fingerprint 루프가 게이트당 1회 `computeTransitiveSourceHash` →
    **54회/프로세스**(`nim --version` exec 57 = 신원 54 + 생성기 1 + 지문 1;
    genDepend 54는 생성기 스크립트 소관).
  - `bin/gate_hook`(checker.mk가 `-d:release` **없이** 컴파일 = 비릴리즈 도구):
    stage 진입 시 바이너리 자체 transitiveHash 1회 + CI AOT preflight는
    stage-scope·진입파일 존재 게이트만(manifest.d 관측: pre-commit 4 + pre-push 1,
    그 중 진입 파일 존재 = nim-check 1개) → 클린 트리 관측 **1회/프로세스**.
    변경 범위가 있는 실행에서는 memo(resolveGateHash)·executor가 게이트당 추가
    호출(각 호출 debug ~3.2s).
  - `bin/install_ax_cas`(비릴리즈): gate_cas를 `resolveCasDir` 전달용으로만 import
    (사전 계산 srcHash 소비) — 신원 해싱 경로 아님.
- **probe 도구가 비릴리즈인 이유**: checker.mk의 부트스트랩 4종 중 gate_hook·
  install_ax_cas 레시피에 `-d:release`가 없다(역사적 컴파일 시간·디버그 우선 선택 —
  checker.mk 주석은 precompile_gates만 release 필요성을 명시). 측정 probe
  (build/d522_probe*)도 동일 조건(debug)로 빌드해 이 비용 계급을 재현했다.
  sha256은 `checksums/sha2` 순수 Nim 구현(`core/crypto/hash_kernel.nim`)이라
  debug 최적화 부재 시 ~2.9MB/s로 급감한다.

## §3. 설계 판정 — 왜 프로세스-수명 정체성 캐시인가

- **"no memoization by design"의 실제 설계 근거(문서 조사)**:
  - `src/core/gate/gate_cas.nim:72–76` — VS-T "No memoization (VS-T
    correctness-first)"의 금지 대상은 **클로저 재계산**: "the closure is
    recomputed on every call from live manifest + file content; the retired
    (file, mtime, size) memo could have served closures computed under a
    different provider or manifest generation." 즉 매니페스트·클로저 결과의
    memo화 금지다. VS-T 증거 §1 소비자 계약도 "memoization 완전 삭제"의 대상을
    구 (file, mtime, size) memo로 특정한다.
  - VS-T §8 "성능 최적화 금지"는 **당시 슬라이스 범위 제약**(correctness-first
    트레이드오프 기록)이며, DEBT#522 자체가 "성능 후속용 데이터"로 후속을 예약.
  - registry·spec 전수 검색(교체/replaced/mid-execution/process lifetime 등)에서
    **"nim 바이너리가 프로세스 실행 중 교체될 수 있다"고 요구하는 위협 모델 문서는
    존재하지 않는다**. 반면 프로세스-수명 툴체인 캐시는 이미 승인된 패턴이다:
    `src/core/gate/gate_memo.nim` `ensureBuildEnvPartsComputed`/`computeToolchainSalt`이
    `nim --version` 출력·stdlib 해시를 threadvar로 "compute once at first call,
    cache in thread-local storage for the process lifetime" 캐시한다(§0.6 준수
    주석 포함).
- **(a) 프로세스-수명 툴체인 해시 캐시 — 채택**: 신원 **다이제스트 계산**만 1회/프로세스.
  매니페스트 헤더 비교는 매 읽기 수행(검증 의미론 불변). VS-T 무조건-재생성 제약·
  fail-closed·매니페스트 바이트에 무영향(§5). 프로세스 내nim 경로 변화(PATH 변경)는
  캐시 무효→재계산.
- **(b) probe 도구의 release 전환 — 기각**: 게이트 훅의 빌드 모드는 B-fingerprint·
  provenance 공급망(checker.mk S5, admission-check.yml)에 결속된 변경이라 블래스트
  반경이 크고, release여도 호출당 59ms×N의 구조적 재해시는 잔존한다(54회=3.2s).
- **(c) (size, mtime, sha) 복합 무결성 검사 — 기각(약화)**: mtime은 `touch -r`로
  내용 교체 후 보존 가능하며 TOCTOU 창이 생긴다 — 신원 검증의 약화이므로 채택
  불가. sha256 전체 해싱을 유지하되 계산 횟수만 줄인다(무결성 강도 불변).
- **Ratchet 952 제약(기계 확인)**: `src/core/trusted/architecture_invariants.nim`
  proc→func 래칫(procCount ≤ 952)이 VS-T가 추가한 정확히 2개 I/O proc을 명시하고
  "single-use I/O helpers are inlined at their call site"을 관례로 기술한다. 따라서
  캐시 로직은 신규 proc 없이 `loadProjectClosure`에 **인라인**했다(모듈 proc 표면
  불변 — 모듈 docstring의 "exactly two I/O-boundary procs" 서술도 그대로 참).

## §4. 구현 계약

`src/core/gate/closure_manifest.nim`:

- 모듈 수준 `ToolchainIdentity` object + `cachedToolchainIdentity` threadvar
  (gate_memo 관용구와 동일한 스레드-로컬 — 교차 스레드 공유 가변 상태 0, §0.6).
  필드: `nimExe`(해시를 계산한 해결 경로), `sha256`(바이너리 바이트 해시),
  `versionEscaped`(`nim --version` 전체 출력, \n 이스케이프+strip), `valid`.
- `loadProjectClosure` 신원 블록: 캐시 유효·경로 일치 → **비교만** 수행(sha/버전 대
  매니페스트 헤더 — 매 읽기). 미스/경로 변화 → ①②③ 재계산 후 캐시 적립.
  **실패한 계산은 캐시하지 않는다**(신원 불명은 매 호출 fail-closed 유지).
- 캐시가 저장하는 것은 **라이브 툴체인 다이제스트**이지 매니페스트 판정이 아니다:
  위조 매니페스트는 캐시 프라임 후에도 매 읽기 비교에서 거부된다(§6 관측).
- 불변식 보존: VS-T 무조건-재생성(precompile_gates `closureManifestGeneration`
  블록 무수정)·fail-closed 단일-할당 구조·매니페스트 스키마·플래그·프로브 결합
  전부 무변경. 게이트 CAS 키 구성요소는 소스 클로저 내용만 — 본 변경이 클로저에
  포함되는 게이트(binary-freshness-gate·cli-build·integrity-workflow, VS-T §5
  run3 관측과 동일 3종)의 키만 이동(정상·소스 변경 추적으로 환원).

## §5. 측정 (A/B, 동일 머신·동일 워크트리·동일 캐시 상태)

probe: `build/d522_probe.nim`(성분 분해 + N회 per-call 타이밍 + 트랜스해시 출력).
빌드: `AXIOM_HERMETIC_BUILDING=1 nim c [-d:release] --hints:off --skipUserCfg:on`.

| 항목 | main 코드 | 본 슬라이스 | 개선 |
|---|---|---|---|
| nim 바이너리 sha256 단독 (debug) | 3192.1ms | (1회만) | — |
| loadProjectClosure 1회 (debug) | 3167.5ms | 1회째 3164.8ms·2회째 4.4ms | — |
| **54-호출 루프 (debug, layer-enforcement-gate)** | **186,266.3ms (3449.4ms/호출)** | **3,388.7ms** | **55.0×** |
| **54-호출 루프 (release)** | **3150.3ms (58.3ms/호출)** | **121.0ms (2.2ms/호출)** | **26.0×** |
| warm precompile wall (인터리브 3회, 중앙값) | 14.6s | 11.3s | **−3.3s (−23%)** |
| 트랜스해시 (동일 트리·동일 매니페스트) | `8ffcc6b41787b079…4fba606` | `8ffcc6b41787b079…4fba606` | **동일** |
| 매니페스트 54개 (재생성 diff -r) | — | **54/54 바이트 동일**(main 코드 재생성 대비·본 슬라이스 코드 재생성 대비 양측) | 동일 |

- warm precompile 교차 관측: main 클론(main 코드) 14.8s ↔ 워크트리(본 슬라이스)
  10.9–11.9s — 워크트리 내 main-코드 빌드 13.2s와의 동일-트리 A/B가 위 표의
  근거(트리·경로 효과 제거).
- checker.mk:521–525의 선례 실측("debug builds spend ~192s/run there, release
  ~3.4s")과 본 측정(182s/3.15s)이 일치 — 기준선 상호 검증.
- **트리 간 해시 차이의 해명**: main 클론의 layer-enforcement-gate 해시
  `fee31c9c10ee8980…`(VS-T §5 역사값과 동일 — 프로브 재현 상호 검증)과 워크트리
  `8ffcc6b4…`의 차이는 라이브 프로브 타깃 `src/generated/build_env.nim`의
  BuildSourceHash 시드가 트리별 재생성으로 분기하기 때문(기계 확인: 두 트리의 해당
  파일 diff). 본 슬라이스 변경과 무관하며, 등가성 판정은 동일-트리 내 양 코드
  버전 해시 동일로 수행한다.

### §5a. 54-호출 루프 debug A/B (동일 워크트리)

- main-코드 debug 프로브: **186,266.3ms** 총(호출당 3449.4ms).
- 본 슬라이스 debug 프로브: **3,388.7ms** 총 — 1회째 3164.8ms(캐시 적립) +
  2회째부터 4.2–4.4ms/호출(비교 잔류: 매니페스트 판독·검증·genDependProfile·
  파일 존재 스윕). **55.0× 감축**. 트랜스해시 양측 동일(`8ffcc6b4…`).
- main 클론에서 관측한 debug 루프 기준선 181,960.8ms(호출당 3369.6ms)와
  워크트리 main-코드 186,266.3ms가 일치 범위(머신 부하 편차 ±3%) — 기준선
  강건성. checker.mk:521–525 선례 실측(~192s)과도 정합.

## §6. fail-closed 보존 (실패 주입, 격리 fixture)

probe: `build/d522_forge.nim`(유효 호출→위조 호출→유효 호출 순서, 동일 프로세스).

| 주입 | 관측 | 판정 |
|---|---|---|
| 매니페스트 부재(신규 워크트리) | `files=0`, `transitive_hash=EMPTY(fail-closed)` | cache HIT 경로 부재 |
| 위조 NIM_SHA256(캐시 프라임 **후**) | `valid_call1=37 → forged_call=0 → valid_call2=37` | **FAIL-CLOSED-PRESERVED** |
| 위조 FLAGS(--hints:on, 프라임 후) | `forged_call=0` | FAIL-CLOSED-PRESERVED |
| **poison 방향**(위조 호출이 첫 호출) | `(0, 37, 0)` — 위조 먼저, 이후 유효 37파일 정상 | 캐시는 매니페스트 판정 아님 |
| 복원(원본 바이트 cmp 동일) | `2`파일 — conflict-marker-gate의 문서화된 클로저 크기(VS-T §5)와 일치 | 원복 확인 |

→ 매니페스트 부재·위조 모두 cache HIT 경로는 존재하지 않는다. 캐시가 저장하는
것은 라이브 툴체인 다이제스트(퓨어 함수)이며, 위조된 헤더는 프라임된 캐시에 대해서도
매 읽기 비교에서 거부된다.

## §7. 부채·문서 갱신

- `data/debt_registry.json` DEBT#522: resolution에 잔여 반쪽 해소 기록,
  status `open` → `closed`(diff 2줄 — 포맷·스키마 필드 불변).
- 드리프트 파이프라인(#521/#524 선례 경로, 기계 관측):
  - `bin/debt_engine --codegen` — 투영 갱신(`docs/DEBT_REGISTRY.md` DEBT#522
    행 Closed·`src/generated/debt_constants.nim` 카운트).
  - `bin/debt_engine --regen-arch` — **0건 갱신**(`data/architecture_debt.json`은
    closure_manifest.nim을 추적하지 않음 — 관측: 해당 파일 언급 0회).
  - `bin/nimtry src/ --diff-baseline` — New 1 / Resolved 1 / Stable 4261:
    유일 드리프트는 `loadProjectClosure spans 97→103 effective SLOC`(인라인
    캐시 +6 SLOC의 직접 귀결) → `--update-baseline` 재앵커(9줄) →
    `bin/nimtry src/` **PASS, rc=0**(debt anchored 4262).
  - `bin/debt_engine --sync-budget` — ledger 2레코드 갱신(open 54→53·
    closed 201→202).
  - `bin/debt_engine --validate` — **1604/1604 passed, 0 failed, 3 PASS /
    0 DRIFT, EXIT=0**.
- 부트스트랩: `bin/build_all_gates --release` — **82/82 빌드, 0 failed**
  (accepted-dead skip 2건은 도구가 사유와 함께 보고). `make check-arch` green.
- 본 문서가 DEBT#522 잔여의 정본 증거가 된다.

## §8. 재현 명령

```
# probe 빌드(debug/release)
AXIOM_HERMETIC_BUILDING=1 nim c --hints:off --skipUserCfg:on \
  --nimcache:build/nimcache_d522/probe_dbg -o:build/d522_probe_dbg build/d522_probe.nim
AXIOM_HERMETIC_BUILDING=1 nim c -d:release --hints:off --skipUserCfg:on \
  --nimcache:build/nimcache_d522/probe_rel -o:build/d522_probe_rel build/d522_probe.nim
./build/d522_probe_rel <repoRoot> <gateSrcAbs> 54   # 성분 분해 + per-call + 트랜스해시

# 매니페스트 결정성(54/54 바이트 동일)
cp -r .axiom/cache/gate_closure /tmp/snap && <precompile 실행> && diff -r /tmp/snap .axiom/cache/gate_closure

# fail-closed 주입(d522_forge)
sed -i 's/^NIM_SHA256=.*/NIM_SHA256=<forged>/' .axiom/cache/gate_closure/<m>.manifest
./build/d522_forge <repoRoot> <validSrc> <forgedSrc>   # (37, 0, 37) 기대
cp <backup> .axiom/cache/gate_closure/<m>.manifest      # 원복

# 빈도 관측
strace -f -e trace=execve -o /tmp/s.txt bin/precompile_gates && grep -c -- '--version' /tmp/s.txt
```

## §9. Follow-up (범위 밖 — 확장 불비)

- 매니페스트 증분 재생성: DEBT#522 PARTIAL 기록부터 명시적으로 비추진(신선성 키
  재설계 필요 — VS-T 무조건-재생성 경직 제약과 충돌). 본 슬라이스도 동일 판정 유지.
- gate_hook·install_ax_cas의 debug 컴파일(빌드 모드)은 본 슬라이스 범위 밖 —
  release 전환은 B-fingerprint·공급망 재검토를 수반하는 별도 판정 사항.
