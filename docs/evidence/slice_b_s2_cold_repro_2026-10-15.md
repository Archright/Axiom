# Slice B / S2 — 콜드 툴캐시 relink 경합(ETXTBSY 류) 통제 재현 실험 보고

- **일자**: 2026-10-15
- **수행**: S2 (승인된 Slice B 계획에 따른 통제 재현 실험 — 운영 수정 아님)
- **장소**: `Archright/Axiom` 브랜치 `queue-probe` (branch-local; main 착지·PR 없음, admission 세대 H₁ 무변경)
- **대상 메커니즘**: `config/integrity.nims` `manifestBootstrap`/`certManifestBootstrap`이 매 `nim c`마다 공유 `-o` 경로(`bin/feature_manifest_generator`, `bin/sync_certs`)의 도구를 온디맨드 `nim c -r`로 빌드·실행 — 콜드 툴캐시에서 병렬 레인이 같은 공유 상태(출력 바이너리 + `build/nimcache/debug`)를 동시 재링크·재기록하며 즉사하는 경합. 근거: `data/ci_optimization/parallel_reland_cold_guard_2026-10-13.md` §1-4 (결함 명령 integrity.nims:135/:174, 직렬 웜업 가드 선례 29383cdda:1153-1155).
- **워크플로**: `.github/workflows/probe-merge-queue.yml`에 실험 잡 3종 추가 (기존 probe-capture/probe-judge 무변경). 신규 잡은 push@queue-probe·workflow_dispatch 전용 if 가드 — merge_group·pull_request 큐 프로브와 무결. concurrency 추가 불필요(기존 그룹 키 = event_name+SHA).

---

## 1. 실행 요약

| 시도 | 런 ID | 커밋 | Job A (무가드) | Job B (가드) | Job C (원자성) |
|---|---|---|---|---|---|
| 1 | 38710338905 | caab865d8 | 경합 재현(2/4 레인 즉사, 관측 데이터 완전 기록; 하니스 -e 결함으로 판정 마커 단계만 실패) | 억제 확인(4/4 rc=0; 동일 결함) | ATOMIC_HOLD 성공 |
| 2 | 38711735376 | f1e600965 | **REPRODUCED** rc_all=3 (잡 SUCCESS) | **GUARDED_SUPPRESSED** rc_all=0 (잡 SUCCESS) | **ATOMIC_HOLD** 성공 |

시도 2 기준 실험 잡 4종(capture 포함) 전부 success — 런 전체 conclusion은 `cancelled`로 기록: 기존 측정 잡 probe-judge(전 레포 아티팩트 페이지네이션, 수 분 소요)가 실험 잡 전부 완료 후 취소된 것(실험 결과와 무관한 레거시 잡; 취소 주체는 런 이벤트상 확인 불가 — 본 실험 잡은 취소 전 전부 완료·success 확정).

**판정: reproduced-guarded-suppressed.** 무가드 콜드 4레인에서 매번 다수 레인이 공유 빌드 상태 동시 기록 경합으로 즉사(시도 1: 2/4, 시도 2: 3/4), 직렬 웜업 가드 후 동일 하니스에서 항상 4/4 rc=0. "원인 가설 미확정" 해당 없음 — 2회 CI 시도 + 개발머신 사전 검증 전부 재현.

단, CI에서 관측된 즉사 양상은 개발머신의 ETXTBSY(exec 충돌)가 아니라 **공유 nimcache 동시 기록에 의한 링크 손상**이었다 — 동일 경합 가족(비직렬화된 병렬 `nim c`의 공유 상태 경합)의 형제 실패 모드 (§4).

## 2. 개발머신 사전 검증 (2026-10-15, nim 2.2.10)

§4 레시피(공유 출력 2종 + `~/.cache/nim/{feature_manifest_generator_d,sync_certs_d}` 삭제 + `build/nimcache/debug` 상위집합) 적용 후:

- **unguarded 4레인**: `rc_all=3`, ETXTBSY 류 3건
  - `sh: 1: .../bin/feature_manifest_generator: Permission denied` ×2 (lane 1·3, GEN ~4s)
  - `sh: 1: .../bin/sync_certs: Text file busy` ×1 (lane 2, CERT)
  - `Error: execution of an external program failed` 동반 — 10/13 J4 run1 서명과 동일
- **guarded 4레인** (직렬 웜업 rc=0/0 후): `rc_all=0`, 0건 — §4 after 재현

## 3. CI 실행 결과 (ubuntu-24.04, 신규 러너 — 콜드 자동)

### Job A — cold-repro-unguarded

**시도 2 (런 38711735376, 판정 마커 정상 출력):**
```
COLD_REPRO_VERDICT REPRODUCED rc_all=3 etxtbsy_hits=0   (LD_FAIL_HITS=14)
COLLECT lane=1 gen_rc=1 cert_rc=0
COLLECT lane=2 gen_rc=0 cert_rc=0
COLLECT lane=3 gen_rc=1 cert_rc=0
COLLECT lane=4 gen_rc=1 cert_rc=0
```
3/4 레인이 GEN 링크 단계(~34s, 기동 09:18:14 → 사망 09:18:48)에서 즉사, 실패 원문:
```
(.text+0x1b): undefined reference to `main'
/usr/bin/ld: @mfeature_manifest_generator.nim.c:(.text+0xd811): undefined reference to `safeMoveFile__safe95move_u6'
/usr/bin/ld: .../bin/feature_manifest_generator: hidden symbol ... isn't defined
/usr/bin/ld: final link failed: bad value
collect2: error: ld returned 1 exit status
Error: execution of an external program failed: 'gcc -o .../bin/feature_manifest_generator ...'
```

**시도 1 (런 38710338905, 동일 서명 — 2/4 레인 사망):** lane 1·3 GEN 링크 즉사(09:07:29, 개시 후 ~15.5s), lane 2·4 생존 rc=0/0.

### Job B — cold-repro-guarded

**시도 2 (판정 마커 정상 출력):**
```
WARMUP gen_rc=0 cert_rc=0 gen_ms=8970 cert_ms=2867
COLLECT lane=1..4 gen_rc=0 cert_rc=0  (4/4)
COLD_REPRO_VERDICT GUARDED_SUPPRESSED rc_all=0 etxtbsy_hits=0   (LD_FAIL_HITS=0)
```
직렬 웜업은 j4-cold-guard 선례(29383cdda:1153-1155)와 플래그 단위 동일 명령 — 레인 부트스트랩이 히트할 정확히 같은 캐시를 웜업. 4/4 레인 `ensured fresh`(웜 캐시 히트), 재빌드 행 0, ETXTBSY·링크 실패 0건. 시도 1도 동일 결과(warmup gen_ms=5684 cert_ms=3398, 4/4 rc=0).

### Job C — partial-cache-atomicity

v76 원자 공개 패턴(PID 유일 tmp + 같은 디렉터리 mv=rename(2)) 공개자 2 + naive 2-청크 직접 기록 1, 루프 리더가 전체 파일 sha256 대조:

| 시도 | atomic reads | atomic 위반 | naive reads | naive 부분 관측 | 판정 |
|---|---|---|---|---|---|
| 1 | 1,220 | **0** | 1,017 | **460 (45.2%)** | ATOMIC_HOLD |
| 2 | 1,310 | **0** | 1,092 | **532 (48.7%)** | ATOMIC_HOLD |

- 원자 패턴 위반 0 (2회 반복) — v76 전제(partial-cache 비소비) 입증. naive 패턴은 ~45-49%의 리드에서 절단 상태 관측 — 비원자성 시연.

### 하니스 결함 (시도 1에서 발견 → 시도 2에서 수정)

GitHub run 블록 기본 셸은 `bash -e`: (1) 레인의 `nim | tee` 파이프라인 실패가 서브셸 즉사로 이어져 실패 레인의 rc 파일이 기록되지 않음(단, 실패 원문은 라이브 tee로 전사 — 10/14 교훈 "레인 stderr 소실"은 재발하지 않았다), (2) record 단계의 `grep -c` 무매치(rc=1) 파이프라인이 스텝을 죽여 `COLD_REPRO_VERDICT` 마커가 미출력. 시도 2(f1e600965)에서 if/else rc 캡처 + awk 단일 패스 카운트 + ld/nimcache 실패 클래스 카운터(ldfail)로 수정 — 두 판정 마커 모두 정상 출력 확인.

## 4. 해석 — 실패 모드 분류

동일 근본 원인(콜드 상태에서 비직렬화된 병렬 `nim c`의 공유 빌드 상태 경합)이 환경별로 두 양상으로 발현:

1. **ETXTBSY 류 (개발머신, 10/13 J4 관측)**: 공유 `-o` 바이너리의 동시 재링크/실행 충돌 — `Permission denied`/`Text file busy`로 `sh`가 즉사.
2. **공유 nimcache 링크 손상 (CI 신규 러너, 2회 모두)**: 4레인이 config.nims:13-20이 배정한 동일 `build/nimcache/debug`에 같은 이름의 `.o`를 동시 기록 → 링커가 다른 레인이 재기록 중인 `.o`(`@mfeature_manifest_generator.nim.c.o` — `main` 정의 담당)을 읽어 `undefined reference to main`/`final link failed: bad value`로 즉사.

두 양상 모두 레인 즉사라는 제품 관점 결과가 동일하다 — 10/14 "lane deaths 27-64s"의 상위 메커니즘(콜드+병렬에서 공유 빌드 상태 경합으로 레인 즉사)은 실재하며, 직렬 웜업 가드가 두 양상 모두를 제거한다. CI에서 ETXTBSY 텍스트 자체가 나오지 않은 것은 링크 단계(공유 nimcache)가 exec 단계(공유 바이너리)보다 경합 창이 넓어 먼저 맞기 때문으로 해석된다(4코어 러너에서 4개 컴파일이 수 초 내 동시에 링크 진입).

기록 경계: 본 실험은 통제 재현이다. 10/14 실제 실패 5런의 클래스별 재분류와 j4 병렬 레짐 재현 시의 실발화 여부는 본 보고서 범위 밖(후속 관측 과제).

## 5. 판정 (per plan)

- **verdict: reproduced-guarded-suppressed**
  - 무가드 콜드 4레인: 재현 — CI 2회(2/4, 3/4 레인 즉사) + 개발머신(rc_all=3, ETXTBSY 류)
  - 가드(직렬 웜업) 적용: 억제 — CI 2회 모두 4/4 rc=0, 실패 0건
- 측정 전용 잡 의미 준수: 관측 결과(REPRODUCED/GUARDED_SUPPRESSED)에서도 잡 성공, 하니스 인프라 오류에서만 실패. 원자 패턴 위반(v76 전제 반증) 시에만 Job C가 실패 — 2회 모두 ATOMIC_HOLD.

## 6. 위임·경계 준수

- main 미접촉, PR 없음, merge 없음, Archright/.github 조직 파일 무변경 — 변경은 queue-probe 브랜치의 `.github/workflows/probe-merge-queue.yml` 단일 파일 2커밋.
- push 시 원격 푸시 룰셋이 "File path is restricted — .github/workflows/probe-merge-queue.yml" 1건 비차단 통지(시도 1 푸시; 레퍼런스 갱신은 승인 22e1d2667..caab865d8) — 기록 목적 보존.
- 아티팩트(런별, 30일): `cold-repro-unguarded-logs`, `cold-repro-guarded-logs`, `partial-cache-atomicity-logs`.
- 로컬 게이트: pre-commit(anti_theater PASS, layer_enforcement PASS — 브랜치 소스 게이트 재빌드 후), pre-push(6종 게이트 바이너리 브랜치 소스 재빌드 후 통과), `make check-workflow-shell-syntax` PASS(110 blocks, failures=0), run 블록 bash -n 전수 PASS.

## 7. 브랜치 diff 요약 (queue-probe: 22e1d2667 → f1e600965)

- `caab865d8` — probe-merge-queue.yml +386행 (헤더 실험 문서화 + Job A/B/C 추가)
- `f1e600965` — 동 파일 +42/-18행 (bash -e 내성: 레인 if/else rc 캡처, awk 카운트, ldfail 카운터)
- 기존 probe-capture/probe-judge 잡과 `on:` 트리거: 무변경 (push@queue-probe 트리거는 기존 존재 — 신규 워크플로 활성화 아님)
- 기타 브랜치 파일: 무변경 (로컬 게이트 바이너리 재빌드는 untracked bin/에 한함)
