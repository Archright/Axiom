# VS-T3 evidenceId 배터리 프로파일링 — 중복 계산 부재, honest-close (2026-11-16)

> **종류**: 조사 종결 기록 (profiling evidence). 목적은 Tier 3 최우선 후보 — lane(0) evidenceId
> 배터리(실측 99s)의 중복 순수 계산 존재 여부를 확인해, 발견 시 C4 선례(PR #59,
> `measureExtractionAgreement`의 114MB SHA-256 반복 → 프로세스 내 memoization, s1a
> 150.6s→56.5s)와 동형의 최소 슬라이스를 착지하는 것이었다. 결론: **C4-동형 중복 계산은
> 부재 — 배터리의 지배 비용은 debug 빌드 sha256 1회(재계산 계약의 정상 수행)다.**
> 억지 memoization은 극장이므로 도입하지 않는다(사용자 원칙: "증명하지 않은 생략을
> 최적화라고 부르지 않는다"). 잔여 절감 레버는 전부 별도 슬라이스·계약 검토 대상으로
> 기록만 한다.

관측: 원격 run 로그 분해(기준선 43399299637, 2026-11-13, head 2f325804 — lane(0) 294s·
lane(1) 184s / 최신 43849381963, 2026-11-16, head 605f9ba — lane(0) 138s·lane(1) 132s) +
코드 분석(양 SHA 대조) + /tmp 격리 마이크로 벤치마크. 저장소 무수정(스크래치 전부
/tmp). 배터리 스텝은 최신 main에서도 `admission-check.yml:4031` — `make test-fast-one`
2건 구조 무변경. `test-fast-one` 레시피(Makefile:1044-1047):
`AXIOM_CI_PRESERVE_CACHE=1 nim c -r --hints:off --nimcache:build/nimcache/test
-o:/tmp/opencode/ax-one T` — **-d:release 없음 = 테스트 바이너리는 debug 빌드**.
nimcache는 B-layer 복원으로 warm(TEST_SUPPLY_N=237/239 관측).

## 1. 99s의 성분 분해 (run 43399299637 lane(0), 로그 라인 근거)

| 구간 | 시간 | 근거 |
|---|---|---|
| (a) hermetic 사전빌드 1회차(**MISS** — 툴 3종 컴파일 포함) | **36.0s** | L1426→L1529(트리해시 `computeSourceTreeHash("src")` 16.1MB·1,448파일 + sync_topology + decision_binding 감사) |
| (a) checker 컴파일+링크+fixture 실행 | 2.1s | L1743→L1755 — fixture는 인메모리 소형 해시 11건(μs급), self-check PASS |
| (b) hermetic 사전빌드 2회차(**HIT**) | **6.9s** | L1756→L1998 — 1회차와 **입력 완전 동일** 재실행 |
| (b) probe 컴파일+링크 | 7.9s | L1998→L1999 |
| (b) **probe 실행(실체 체인)** | **46.0s** | L1999→L2002 |
| 합계 | **99.0s** | 스텝 PASS |

lane(1) 77.3s = 동일 구성(probe 실행 34.0s — 러너 인스턴스 변동, 기존
`docs/evidence/admission_leg_runtime_profile_2026-11-14.md` §3.1과 일치). 최신 run
(43849381963, GO 전부 REUSED)에서도 probe 실행은 lane(0) 34.2s·lane(1) 34.1s로 수렴 —
**probe 실행이 배터리의 구조적 지배 항목**이다.

**요약**: 컴파일(warm) 10.0s(10%) · hermetic 사전빌드 2회 42.9s(43%) · probe 실행 46.0s(47%).

### probe 실행 46s의 귀속 — debug 빌드 sha256 1회

probe(`tests/unit/test_evidence_id_contract_probe.nim`)의 실체 체인:
`measureParseBoundComponents`(probe:68) → `measureExtractionAgreement`
(`canonical_verification.nim:1047`) → **ircheck 바이너리 전문 sha256 정확히 1회**
(119,585,096바이트 — PR #59 착지 후 `ircheckWorkerBinaryDigest`의 프로세스 내 memo
경유). 나머지: `lake env which lean`·`lake env lean --threads=1`·`#print axioms` probe·
`ircheck extract` 1회씩 + git 2회(기존 직접측정: lean 체크 0.28s·extract 0.05s).

| 빌드 | 동일 119,585,096B sha256 | 근거 |
|---|---|---|
| debug(레인 현행) | **44.8-45.3s (2.6MB/s)** | 기존 문서 §3.3 + 본 조사 /tmp 재현 45.24s/43.97s |
| release | **0.678s/0.683s (114MB/s)** | 본 조사 /tmp 재현, digest 동일 |

→ probe 46.0s ≈ digest 1회 ~44s + 잔여 ~2s. 34s 런 = 빠른 호스트의 동일 구성.

## 2. 중복 순수 계산 판정

- **(i) checker 자체(tools/ci/check_evidence_id_contract.nim): 부재.** 대형 입력 반복
  해시 없음 — 인메모리 seed 문자열 sha256 11건(각 서브-KB, μs급). 실행 시간은 무시
  가능(컴파일 2.1s가 전부).
- **(ii) probe 프로세스 내부: C4-동형(대형 반복) 부재.** EA(ircheck 114MB 해시)는
  프로세스당 정확히 1회다 — memo화할 반복이 없다. PR #59의 개선이 "프로세스 내
  3회→1회"였기에 probe(애초에 1회)에는 구조적으로 0 절감이며, PR #59 착지 후에도
  probe 실행이 34.2s로 불변인 것이 관측 확증(605f9ba run 43849381963). 잔여 in-process
  2중 계산(lean/lake digest 2중 호출 — 이미 `measured_digests.nim` 스레드-로컬 memo로
  2회차 히트·원비용도 9KB/14KB 런처 무시 가능 / toolchain fingerprint 3중 — 전부
  memoized 파일 digest 재사용, 잔여 수-KB concat μs / proposition·leanSource 재검증 해시 —
  ~1-2KB μs)은 전부 μs급 — **여기에 memo를 도입하면 극장이다**.
- **(iii) 프로세스 경계의 반복: 존재하나 프로세스 내 memoization 대상 아님.**
  - hermetic 사전빌드가 `nim c`마다 재실행(config.nims:388, `AXIOM_HERMETIC_BUILDING≠1`):
    배터리 내 2회(2회차 6.9s는 1회차와 입력 완전 동일), 이후 GO-critical 각 make마다
    HIT 패스 ~5-7s 추가.
  - ircheck 114MB digest: probe 프로세스 1회 + s1a 프로세스 1회 — 각각이 독립 판정
    프로세스다(프로세스 간 공유는 판정 재계산 계약과 별도 검토 대상).
  - 컴파일 중복(공유 모듈 재컴파일)은 nimcache warm에서 0(checker 2.1s·probe 7.9s =
    최상위 모듈 코드젠+링크 비용).

## 3. 판정과 잔여 레버 (전부 별도 슬라이스 — 본 조사는 기록만)

**판정**: "EXECUTED always"·판정 재계산·증거 키 불변 조건하에 배터리에 자동 적용
가능한 C4-동형 memoization은 **없다** — honest-close.

잔여 절감 레버(우선순위·소요는 실측 근거, 적용 여부는 각각 계약 검토 후 판정):

| 레버 | 예상 효과 | 검토 사항 |
|---|---|---|
| (a) 테스트 레인 release 빌드(-d:release) | digest ~44s→~0.7s — probe·s1a 각 프로세스당(EXECUTED 체제 lane(0) 기준 최대 ~88s) | **레인 전체의 실행 의미 변경**(debug assertion·오버플로 검사 부재화) — 판정 정체성 검토 선행 필수(기존 문서 요구와 동일) |
| (b) 프로세스 간 영속 digest 캐시(stat-identity 키) | probe·s1a·레인 간 digest 공유 | 판정 재계산 계약("cache는 가속 수단, 판정 증거 아님")과의 충돌 검토 — 캐시 HIT가 판정을 대체하지 않는 구조만 허용 |
| (c) hermetic 사전빌드 중복 제거(배터리 내 6.9s + GO make당 5-7s) | ~7-13s/레인 | make·워크플로우 구조 변경 — `nim c`별 fail-closed 신선도 검증 의미 변경 수반 |
| (d) proofs/ 빌드 변경으로 ircheck 크기 축소 | digest·전송 비례 | 별도 제품 슬라이스 |

명시적 배제 재확인: 레인 간 배터리 공유(dedup)는 설계 문서 §3 C2로 명시적 배제
(§0.9 인접 위반, 채택 금지 권고) — 본 조사 대상 아니다.

## 4. 방법론 비고

- 로컬 전체 재현(`make test-fast-one` 2건)은 생략 — 로컬 `proofs/.lake`(ircheck) 미빌드로
  `lake build` 전제가 필요하고 원격 로그 분해가 충분했기 때문. 대신 /tmp 격리 마이크로
  벤치마크(`lake env lean` 소형 정리 0.39s×3, debug·release sha256 45s/0.68s)로 원격
  귀속을 교차 검증했다. 스크래치는 /tmp 한정, 저장소 오염 0.
- 코드 인용은 관측 런 head SHA(2f325804) 기준; 605f9ba에서의 PR #59 착지 차이
  (`ircheckWorkerBinaryDigest`)는 별도 확인 완료.
