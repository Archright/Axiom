# 빌드 공급 단일 프로비저닝 설계 — J4/DEBT#457 직렬 가정 결함 가족의 계약 승격 (2026-10-15)

> **Status**: 설계 제안 (DESIGN ONLY — 구현 코드 0건, 소스 변경 0건). 본 문서는
> `docs/design/` 소속의 **비번호 설계문서**다 — `docs/adr/`의 번호 매긴 ADR(현행
> 0001–0034)과 다른 등급이며, **ADR 승격 여부는 소유자 판정 사항**이다.
>
> **관련**: DEBT#457(`data/debt_registry.json`, CI/Pipeline Health, FIXED),
> DEBT#481(bin/ax 시드, CLOSED 2026-10-07), DEBT#417(hermetic env-hash identity),
> J4 판정 기록(`data/ci_optimization/parallel_reland_2026-10-13.j4.md`),
> PR #826→#829(4-lane 병렬화와 그 원자적 리버트), PR #830(j4-cold-guard 잔여 봉쇄).
> 인용 man 페이지: man-pages 6.19 (man7.org, 2026-10-15 열람).

---

## 1. 문제·근거

### 1.1 매 `nim c` 무조건 재링크 (공급 경로 1)

`config/integrity.nims:154-218`의 두 부트스트랩 블록은 **모든** `nim c` 호출에서
공유 출력 경로를 재링크한다. `nim`에는 바이너리 신선도 스킵이 없다 —
Makefile:622-624: *"nim relinks on every `nim c`, there is no binary freshness skip"*.

- `manifestBootstrap` (config/integrity.nims:162-189): `bin/feature_manifest_generator`
  (`genBin` :169, `genCmd` :170)을 `nim c -r`로 재링크·실행. FANOUT 분기(:171-181)는
  `AXIOM_VERIFY_CONTRACT_FANOUT` 설정 시에만 읽기전용 소비.
- `certManifestBootstrap` (:199-218): `bin/sync_certs` (`certBin` :208,
  `certEnsureCmd` :209)를 동일하게 재링크. FANOUT 분기(:210-216).

### 1.2 MISS 게이트 공유 경로 빌드 3종 (공급 경로 2)

`config.nims` `hermeticPreBuild`는 조건부 재링크 3건을 품는다 (config.nims:527-569):

- `bin/sync_topology` (:527-546) — spec 소스가 바이너리보다 새우면 mtime MISS 재빌드 (:531-544).
- `bin/hermetic_build` (:552-559) — envHash MISS 시 재빌드 (:552-557).
- `bin/decision_binding_checker` (:562-569) — 부재 시 재빌드 (:564-566).

이들은 env-hash 스탬프를 고정 tmp 경로 `mv`로 게시한다 (:585-586; 2026-10-11 4-way
병렬 하니스 경합 관측 후 `$$`-PID 유니크로 완화 — :573-584). 완화는 그 한 경로에만
적용됐고, 바이너리 출력 경로의 경합은 그대로다.

### 1.3 J4 실측: 동시 재링크 → ETXTBSY

`data/ci_optimization/parallel_reland_2026-10-13.j4.md` §1차 수집 실패 관측(:49-64):
4레인 병렬 수집 run1에서 s1a·d2g 즉사(rc_all=2). 원인 — 툴캐시 콜드 시 4레인이
`bin/feature_manifest_generator`를 **동시 재링크** → linker가 실행 중/링크 중
바이너리를 O_TRUNC 쓰기 open → ETXTBSY(Permission denied). run0·run2는 통과한
**간헐 경합**이며, 하니스에 직렬 웜업(ensure 1회)을 넣어 5회 재수집 PASS(§처분
:62-64). J4는 같은 결함을 *"DEBT#457(verify-contract fan-out의 build-once→freeze)·
AB §2.2 hermetic 스탬프와 같은 직렬 가정 결함 가족"*으로 명명한다(:56-58).

### 1.4 형제 결함: 10-07 mv 경합

`tools/build_all_gates.nim:84-96`: `hermeticPreBuild`가 고정 tmp 경로
`.axiom/cache/.hermetic_env_hash.tmp`에 쓰고 `mv`하는 동안, 병렬 워커 하나의 `mv`가
다른 워커의 writeFile과 mv 사이 tmp를 삭제 → `FAILED: mv ... [OSError]`.
**observed 2026-10-07**(:91) — 실패 집합이 실행마다 달랐다(run1: anti_theater/
debt_integrity/hermetic_test, run2: lean_z3_consensus/nim_check_runner). 같은 가족의
형제 결함으로, 승격된 계약이 이를 통폐입한다.

### 1.5 직렬 가정 결함 가족과 현재 상태

| 항목 | 위치 | 상태 |
|---|---|---|
| DEBT#457 | verify-contract fan-out 공유 바이너리 경합 | FIXED (PR #39, build-once→freeze→fan-out, 사례별 env 분기) |
| DEBT#481 | fan-out 공유 build/nimcache + bin/ax 작성자 | CLOSED 2026-10-07 (bin/ax 직렬 시드 확장) |
| J4 run1 | 4레인 동시 재링크 ETXTBSY | 하니스 웜업으로 회피 (근본 미봉쇄) |
| 10-07 mv 경합 | 고정 tmp mv | `$$`-PID 완화 (config.nims:585-586) |

4-lane consumer는 PR #829가 원자적으로 리버트했으나(2026-10-14 MERGED) **공급측
결함은 잔존**한다. PR #830(j4-cold-guard)은 잔여 봉쇄를 hermetic 도구로 확장하지만
`nim c`의 무조건 재링크 기본 경로는 그대로다 — 로컬 동시 빌드(서로 다른 터미널의
`make test-fast` × 2, worktree 병렬 작업)와 미래 병렬 재도입 시 동일 결함이 재노출된다.

## 2. 불변식

**(α) 단일 기관 직렬 프로비저닝** — 공유 도구 바이너리마다 정확히 하나의 생성
기관(provisioner)이 존재하며, 그 기관만 직렬로 쓴다. 산출물당 생성 authority는
하나라는 발권 불변조건(AGENTS.md §2.6)의 빌드 공급 계층 적용이다.

**(β) 읽기전용 소비, fail-closed** — 기관의 프로비저닝 완료 후 모든 소비자는
바이너리를 읽기전용으로 실행한다. 바이너리가 없거나 신선도 판정에 실패하면
소비자는 quit(1)로 실패한다 — 절대 자체 재링크로 자가 치유하지 않는다.
(config/integrity.nims:177-179의 FANOUT fail-closed가 이미 이 형태다.)

**승격의 의미**: DEBT#457 패턴은 현재 `AXIOM_VERIFY_CONTRACT_FANOUT=1`일 때만
발동하는 **사례별 env 분기**다. 승격은 (i) 읽기전용 소비를 조건 없는 **기본
계약**으로 만들고, (ii) 1회 직렬 프로비저닝을 명시적 기관 단계(Makefile:629-636
`verify-contract-artifacts`, tools/build_all_gates.nim:201-243
`prebuildSharedArtifacts`의 일반화)로 만들며, (iii) 무조건 재링크 분기
(:182-189, :217-218)를 제거 대상으로 분류한다. 불변식 위반 = 작업 실패
(fail-open 경로·조용한 재컴파일 복구 금지 — AGENTS.md §0.9).

## 3. 원자성: 고유 경로 빌드 → rename(2) 게시

**메커니즘**: 기관은 프로비저닝 시 고유 경로(예: `build/bootstrap/<pid>-<tool>/`)에서
`nim c`를 수행하고, 완성 바이너리를 같은 파일시스템 안 최종 공유 경로로
`rename(2)`한다. 고유 경로이므로 어떤 두 기관 인스턴스도 같은 inode를 쓰지 않는다.

**ETXTBSY는 쓰기 open에만 적용된다.** man7 open(2)/creat(2) ERRORS:
*"ETXTBSY — path refers to an executable image which is currently being executed
and write access was requested."* 그리고 creat(2)는
`open(O_CREAT|O_WRONLY|O_TRUNC)`와 동등하다(같은 페이지 creat() 절) — 즉 J4의
실패는 linker가 공유 경로의 실행 중 이미지를 O_TRUNC로 쓰기 open하려다 받은
오류다. 반면 읽기 open과 exec에는 이 오류가 없다 — 여러 프로세스가 같은
바이너리를 동시 exec하는 것은 언제나 합법이다. 문제는 **누가 쓰는가**뿐이다.

**rename(2) 목적지 원자 치환은 실행 중 이미지와 공존한다.** man7 rename(2):
*"If newpath already exists, it will be atomically replaced, so that there is no
point at which another process attempting to access newpath will find it missing."*
그리고 *"Open file descriptors for oldpath are also unaffected."* — 즉 rename은
디렉터리 엔트리(dentry)만 교체하고 옛 inode는 최후 참조까지 유지된다. 실행 중
프로그램의 텍스트 매핑은 그 옛 inode를 가리키며, inode 교체는 실행 매핑을
건드리지 않는다(unlink(2)의 실행 중 파일 규칙과 동일 원리). 관측자는 항상
"완전한 옛 바이너리" 또는 "완전한 새 바이너리" 중 하나만 본다 — 부분 링크
상태는 게시 경로에 절대 노출되지 않는다.

**RENAME_EXCHANGE**: renameat2(2)의 `RENAME_EXCHANGE`(*"Atomically exchange
oldpath and newpath. Both pathnames must exist"*)는 게시와 옛 버전 회수를 단일
연산으로 수행할 수 있게 한다. 본 설계의 필수 요건은 아니며(교체만으로 충분),
버전 회수 원자성이 필요해질 때의 확장점으로만 언급한다(Linux 전용, POSIX 외).

**"마지막 쓰기자 동일" 논증은 보조다.** 결정론적 빌드(동일 입력 → 동일 바이너리
sha, §6-d) 가정 하에서는 두 프로비저너가 게시하는 내용이 동일하므로
last-writer-wins도 내용 중립이다 — config.nims:582-584가 env-hash 스탬프에 대해
*"last-writer-wins is content-neutral because the value is identical across
racers"*라고 이미 논증한 것과 같은 구조다. 그러나 본 설계에서 이 논증은
필불계약이 아니라 이중 안전장치다: 고유 경로+rename은 경합 자체를 구조적으로
제거하며(쓰기 open이 공유 inode를 향하지 않음), ETXTBSY는 애초 open 단계에서
터지므로 내용 동일성만으로는 제거되지 않는다. 조정이 불필요한 이유는
"내용이 같아서"가 아니라 "공유 쓰기 대상이 존재하지 않아서"다.

## 4. 대안 비교

| 대안 | 기제 | 실패 모드 | 판정 |
|---|---|---|---|
| (a) rename 게시 (본 설계) | 고유 경로 빌드 → rename(2) | 동일 입력 비결정성 시 내용 분기 가능 — 단 일관 완성 바이너리는 보장 | **채택** |
| (b) flock(2) 락 | 공유 경로 쓰기 전 LOCK_EX | 아래 상세 — 부분 쓰기 노출·의미론 함정 잔존 | **기각** |
| (c) 존재 스탬프만 검사 | fileExists → 있으면 스킵 | 스테일 재링크가 J4의 실재 실패 — 존재 검사로 불충분 | **기각** |
| (d) per-consumer 복제 | 각 워커가 자기 --out에 빌드 | 안전하나 N배 컴파일·디스크 | **보류**(폴백) |

**(b) flock(2) 상세** (man7 flock, man-pages 6.19): (i) *"flock() places advisory
locks only"* — 락을 무시하는 프로세스(락 미인식 nim c)에 대해 강제력 0. (ii)
*"flock() does not detect deadlock"* — 직렬화 대기 그래프에 교착 판정 부재.
(iii) NFS 의미론: *"Up to Linux 2.6.11, flock() does not lock files over NFS
(i.e., the scope of locks was limited to the local system)"*, CIFS는 5.4까지 미전파
+ 5.5부터는 강제 의미론으로 변질 — 환경별 의미 비일관. (iv) **강제 중단 시**:
flock은 fd 기반이라 프로세스 사망 시 해제되지만(자동 해제는 장점), 역으로
*"Release of a lock when a file descriptor is closed is not sequenced after all
observable effects of close(2)"* — 잠금 규율을 완벽히 지켜도 close→execve 창에서
*"a subsequent execve(2) of that file fails with ETXTBSY"*가 man 페이지 자신이
기술하는 실재 동작이다. 결정적으로 (v) 락은 **쓰기자 간 상호배제일 뿐** 공유
경로에 직접 쓰는 구조를 유지하므로, 락을 안 잡은 소비자의 부분 링크 바이너리
실행 노출과 O_TRUNC 절반-바이너리 창이 구조적으로 잔존한다. 흔히 병행되는
O_EXCL lockfile 변주는 SIGKILL 시 stale lockfile을 남겨 영구 직렬화 정지를
일으킨다 — J4가 관측한 "재실행하면 된다"류 간헐성을 정지성 결함으로 격상.

**(c) 존재 스탬프**: J4 run1의 실패는 바이너리 부재가 아니라 **스테일 재링크**
였다(툴캐시 콜드 + 소스 변경). 존재만으로는 신선도를 판정할 수 없고, 누가
스탬프를 갱신하는지(기관 소유)도 규정하지 못한다 — 스탬프 검사는 (α)(β)의
하위 절차일 뿐 독립 대안이 아니다.

**(d) per-consumer 복제**: 기능적으로 안전(공유 경로 쓰기 부재)이나 컴파일 N배,
디스크 N배. DEBT#457이 4레인 fan-out에서 얻은 "1회 빌드 → 4회 소비"의 정반대.
게시 디렉터리 장애 시의 명시적 폴백으로만 보류한다.

## 5. 범위: 경로별 현재 재링크 지점

| 경로 | 재링크 지점 (현재) | 게이트 조건 |
|---|---|---|
| local `nim c` (모든 것의 밑바닥) | config/integrity.nims:184,189 (bin/feature_manifest_generator), :218 (bin/sync_certs) | 무조건 (FANOUT 미설정 시) |
| hermeticPreBuild | config.nims:544 (bin/sync_topology, mtime MISS), :557 (bin/hermetic_build, envHash MISS), :566 (bin/decision_binding_checker, 부재) | MISS/부재 |
| local pre-commit (.githooks/pre-commit) | 바이너리 직접 빌드 없음 — staged `.nim`에 nim check (:56-60 부분) | — |
| local pre-push (.githooks/pre-push) | :9-14 (bin/gate_tier_integrity 부재 시 빌드), :32-38 (bin/layer_enforcement_gate stale 재빌드), :69-83 (**7-바이너리 요구**: debt_engine, check_nim_theater, doc_path_validator, proof_unit_consistency_gate, proof_reconcile_gate, epoch_transaction_gate, layer_enforcement_gate — 부재·stale 시 FAIL) | 부재/스테일 fail-closed |
| make ci-compile / ci-bootstrap | ci/checker.mk:36-40 (products/gate-hook/precompile-gates/ax), per-product nimcache :23-29 — `AXIOM_HERMETIC_BUILDING=1`로 hermeticPreBuild 스킵 | 제품별 독립 nimcache |
| 워크플로 레인 (미래 병렬 재도입) | runner-pool-acceptance.yml:844 (`AXIOM_PROVE_WORKERS: "1"` 고정 — J4 문서의 :360 인용은 행 드리프트). PR #826 4-lane은 #829가 리버트, #830이 j4-cold-guard 확장 | 레인 병렬 시 §1.3 재노출 |
| build_all_gates | tools/build_all_gates.nim:201-221 (prebuildSharedArtifacts), :223-241 (prebuildHermeticBootstrap) — **이미 기관 역할**, fan-out 자식은 FanoutEnvVar(:63)·HermeticBuildingEnvVar(:97)로 읽기전용 | 선(先)기관 후(後)fan-out |

각 경로가 본 계약으로 전환되면: 재링크 지점은 기관 단계 1회 호출로 수렴하고,
소비 지점은 전부 fail-closed 읽기전용 실행이 된다.

## 6. 검증 계획 (구현 시 기계적 판정 기준)

- **(a) 동시 실행**: ≥4 동시 `nim c` × **perturbed reps** — 5회 중 4회 이상 변조
  (CPU 부하·레인 순서 역전·경로 변조). J4 판정 준거(parallel_reland J4 §수집
  설계: 5회 중 4회 변조 = 순수 연속 실행 제외)를 그대로 적용. 판정: ETXTBSY 0건,
  rc_all=0, 부분 바이너리 sha 노출 0건.
- **(b) 중단 내성**: 기관 프로비저닝 중 SIGKILL → 최종 공유 경로 검사: 옛 완성
  바이너리(그대로) 또는 부재 중 하나 — 고유 경로+rename이므로 부분 산출물은
  구조적으로 노출 불가. 검증은 이를 관측으로 입증한다(강제 종료 후 sha 비교 +
  다음 기관이 정상 게시).
- **(c) 권한·소유권**: 게시 후 바이너리를 읽기전용 모드(예: 0444+실행비트 유지,
  디렉터리는 기관만 쓰기)로 강제 → 비기관 쓰기 시도가 fail-closed로 거부되는지
  관측. 기관 목록이 단일함(1개 진입점)을 스캐너로 검증.
- **(d) 재현성**: 동일 입력(동일 소스·동일 플래그) → 동일 바이너리 sha256 —
  §3의 보조 논증 전입력. 반복 프로비저닝 간 sha 일치를 판정. 불일치 시(도구가
  비결정 요소 포함 시) 원자성 계약은 유지되지만 "내용 중립" 논증은 철회하고
  게시 순서가 곧 정본이 됨을 문서화.
- **(e) 회귀**: 직렬 경로 성능 무손실 — 웜 상태(신선한 바이너리 존재)에서
  소비자의 기관 경유 스킵이 현재 HIT 경로와 동등한 시간인지 측정(±임계),
  콜드 상태에서는 기관 1회 빌드 총시간이 기존 단독 빌드와 동등함을 비교.

## 7. 마이그레이션 (단계적 전환 + 롤백)

| 단계 | 내용 | 롤백 |
|---|---|---|
| 0. 계약 기본값 | 본 문서 합의. 불변식 (α)(β)를 경로 채택의 판정 기준으로 선포 | 문서 폐기 (부작용 0) |
| 1. 경로별 채택 | config/integrity.nims 2 바이너리부터: FANOUT 분기(:171-181, :210-216)를 조건 없는 기본 경로로 승격, 무조건 재링크 분기(:182-189, :217-218)를 기관 호출+fail-closed로 치환. 기관은 Makefile:629-636·build_all_gates.nim:201-243의 일반화 | 분기별 git revert — 기존 코드가 revert 단위로 보존됨 |
| 2. 확장 | config.nims 3종 MISS 도구(:527-569)와 env-hash 스탬프(:585-586)를 bootstrap 게시 디렉터리 경유로 통합 | 단계 1 유지한 채 2만 revert |
| 3. 구 재링크 코드 제거 | 무조건 재링크 경로·고정 tmp mv 제거. AGENTS.md §2.5 — 활성 실행 경계의 in-place 부분 수정 금지, **일관된 세대 전환**으로 착지 (단계 1·2의 채택 상태를 한 세대로 묶어 전환) | 세대 전체 재전환 |

**DEBT#457 폐기 조건** — registry 제거(또는 SUPERSEDED 표기)에는 다음이 모두
입증되어야 한다: (i) 공유 도구 무조건 재링크 코드 경로 제거(스캐너 grep 0건 —
`genCmd`/`certEnsureCmd` 류 무조건 빌드와 그 env 분기), (ii) §6-(a) 동시성 검증
≥4 perturbed reps 통과 기록이 `data/` 증거로 존재, (iii) §6-(b)~(e) 판정 기록,
(iv) debt_integrity_gate + 인간 감사가 폐기를 승인. 미충족 시 DEBT#457은
"FIXED(사례별)"로 남고, 승격 계약은 별도 추적으로 관리된다.

## 8. 미결정 사항 (구현 전 결정 필요)

1. **게시 디렉터리 위치·만료 정책**: `build/bootstrap/` vs `.axiom/bootstrap/` —
   `build/`는 nimcache·B-cache 페이로드와 결합되어 있다(ci/checker.mk:23-29).
   만료는 content-hash 대 mtime 중 무엇으로 판정하는가: 현재 이중 규범
   (feature_manifest=content-hash, config/integrity.nims:155; sync_topology=mtime,
   config.nims:533)의 통일 여부.
2. **env-hash MISS 도구의 env 불변성 보장**: `bin/hermetic_build`는 envHash MISS에서만
   빌드되므로(config.nims:552-557), 프로비저닝된 바이너리가 envHash 입력과
   동기임을 누가 보장하는가 — DEBT#417 이후 identity는 빌드 입력 콘텐츠의 순수
   함수지만, 기관-소비자 사이의 해시↔바이너리 대응 검증 절차를 정의해야 한다.
3. **다중 worktree 간 공유 여부**: worktree별 bin/ 독립(현행) vs 공유 bootstrap
   캐시 — 교차 worktree 쓰기는 I1 workstream 격리(AGENTS.md §2.7)와 충돌 소지.
   본 설계는 worktree 로컬 기관을 기본으로 하되, 공유 캐시는 미결로 남긴다.
4. **읽기전용 모드와 `nim c -r`**: 게시 후 권한 축소(§6-(c))가 기관 자체의
   재프로비저닝(rename 교체)과 소비자의 exec에 미치는 영향 검증 — 디렉터리 쓰기
   권한만으로 rename이 가능함을 환경별로 확인(스티키 비트 디렉터리 제약 포함,
   rename(2) EPERM 항).
5. **기관 진입점의 위상**: `make verify-contract-artifacts`(Makefile:629)와
   `build_all_gates`(tools/build_all_gates.nim:201)의 이원화를 단일 기관 CLI로
   통폐입할지 — authority 중복 방지(§2 (α)) 관점에서 통합이 방향이지만, 기존
   소비자 호환 기간 설계가 필요하다.
