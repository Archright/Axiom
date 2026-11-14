# admission 레그 실행시간 프로파일 — 실측 분해와 후보 상한 (2026-11-14)

> **종류**: 실측 증거. `docs/design/admission_gate_performance_cutover_design_2026-11-13.md` Tier 3의
> Phase B 산출물. **로컬 측정은 후보 스크리닝 전용**이며, 운영 판정은 merge_group 실행 관측으로 한다.
> **정책**: 90일 실행기록 보존 한계 — 런 ID·로그 발췌·판정의 정본 보존소는 본 문서다.

## 1. 측정 대상

동일 워크플로(`admission-gate`, `Archright/.github@c021c338` callee)의 merge_group 실행 2건.
두 실행 모두 GO-critical 테스트 집합이 동일하고(매트릭스 불변), 후보 diff는 테스트를 건드리지 않는다.

| | Run A | Run B |
|---|---|---|
| merge_group run | `43529537636` (PR #34) | `43542716164` (PR #36) |
| base (B) | `4073514` | `162fea0` |
| merge group SHA (M) | `162fea0` | `2dd4967` |
| lane 0 runner | `GitHub Actions 1000054630` (ubuntu-24.04) | `GitHub Actions 1000054709` (ubuntu-24.04) |
| `TEST_SUPPLY_N` | 0 | 237 |
| 전체 실행 (01:46:01→55:02 / 01:48:03→54:33) | **541s** | **390s** |

## 2. 단계별 실측

| 단계 | Run A | Run B | 비 |
|---|---|---|---|
| `attest / build-base-artifacts` | 56s | 43s | 1.30 |
| lane 0 전체 | **320s** | **181s** | 1.77 |
| ├ toolchain setup | 42s | 36s | 1.17 |
| ├ **계약 확인** (`evidenceId contract check`) | **100s** | **51s** | 1.96 |
| └ **GO-critical tests** (s1a) | **150s** | **77s** | 1.95 |
| lane 1 전체 | 232s | 230s | 1.01 |
| ├ 계약 확인 | 99s | **99s** | 1.00 |
| └ GO-critical tests (proof_integrity·d2_golden·d2_persist) | 67s | 68s | 0.99 |
| `attest / admission-check` | 62s | 55s | 1.13 |
| `verdict / admission-check` | 24s | 26s | 0.92 |
| `mint-publish / publish` | 56s | 40s | 1.40 |

### 2.1 계약 확인(100s)의 내부 분해 — 로그 마커 기준

| 구간 | Run A (lane 0) | Run B (lane 0) |
|---|---|---|
| checker compile + `--self-check` | 39.5s | 21.1s |
| probe compile | 14.6s | 7.7s |
| probe 실행 (`EXECUTED` → `PASS`) | 45.9s | 22.7s |
| 합 | 100.0s | 51.5s |

### 2.2 s1a(150s)의 내부 분해 — `duration_ms` + `[OK]` 타임스탬프

| 구간 | Run A | Run B |
|---|---|---|
| `make test-fast-one` 시작 → 첫 `[Suite]` | 18.5s (compile) | 9.7s (compile) |
| `executeCanonicalVerification` 픽스처 1 | **40.1s** | **19.9s** |
| `executeCanonicalVerification` 픽스처 2 | **40.1s** | **20.0s** |
| `executeCanonicalVerification` 픽스처 3 | **40.3s** | **20.3s** |
| rendering + direct kernel tests (3건) | 5.1s | 2.7s |
| 나머지 10건 (결정론·splice·CAS) | 6.4s | 4.4s |
| 합 (`duration_ms`) | 150 617ms | 77 405ms |

**직접 커널 호출은 느리지 않다.** `canonicalLeanKernelCheck`를 직접 부르는 테스트
(`genuine Lean 4.33 kernel ACCEPTS the generated theorem`)는 **0.28s / 0.21s**였다.
따라서 full-chain의 20–40s는 Lean 커널 비용이 아니다.

## 3. 발견

### 3.1 지배 변수는 코드가 아니라 러너 인스턴스다

같은 실행 안에서 lane 0과 lane 1은 **동일한 계약 확인 스텝**을 실행한다. Run B에서
lane 0은 51s, lane 1은 99s였다 — 같은 캐시 상태(`B` 동일)에서 **2배**다. Run A에서는 둘 다 100s/99s였다.
lane 1은 두 실행에 걸쳐 99s/99s, 67s/68s로 **안정**적이고, lane 0만 100→51, 150→77로 변했다.

즉 관측된 2배 차이는 캐시나 코드 변경이 아니라 **호스트 할당 변동**이다. 같은 테스트 집합으로
541s(초과)와 390s(이내)가 나왔고, 480s SLO의 준수 여부가 러너 배정에 좌우된다.

**귀결**: n=2 이하의 비교로 30s(≈10%) 개선을 판별할 수 없다. Phase C의 "실측 ≥30s/배치" 기준은
이 표본 설계로는 검증 불가이며, 판정에는 동일 호스트 등급의 반복 표본(중앙값, n≥10 권장)이 필요하다.

### 3.2 warm nimcache의 컴파일 절감은 관측되지 않았다

Run B는 `TEST_SUPPLY_N=237`(B-layer가 `build/nimcache/test`를 복원)이었고 Run A는 0이었다.
그런데 호스트 변동비(1.96×)로 정규화하면 s1a compile은 `18.5 / 1.96 = 9.4s` 기대 대비 **9.7s 실측** —
**절감 0**이다. `make test-fast-one`은 nimcache가 있어도 상위 모듈 재컴파일·링크 비용을 그대로 낸다.

### 3.3 full-chain 20–40s의 구성 (정적 귀속 완료)

3개 느린 테스트는 `executeCanonicalVerification`의 서로 다른 비용이 아니라 **정확히 3번의
"subject별 첫 `goldenBound(path,name)`"**이다(`tests/unit/test_s1a_lean_golden.nim:71-80`의
process-lifetime cache). 이후 probe는 모두 캐시 히트로 ~1s다. 테스트 1건의 40.1s는:

```
40.1s ≈ 0.7–1.1s  executeCanonicalVerification chain 자체 (warm)
      + ~39s      첫 goldenBound → measureParseBoundComponents → measureExtractionAgreement
                  → runExtractionAgreement → runReferenceExtractorOnWire
                  = `ircheck extract --ast <wire> --out <ir>` subprocess (60s timeout)
                  + 미메모 ircheck 바이너리 전문 sha256 (canonical_verification.nim:1054-1058)
```

산술 검산: 150.6s − 18.5s compile = 132.1s runtime, 3 × 40.1 = 120.3s, 잔여 ~11.8s는
11개 캐시 히트 probe(~1s) + 직접 커널 체크 3건 + suite setup ~15건.

전수 추적(transitive spawn/scan inventory) 결과:

- `executeCanonicalVerification` **내부**에서 1s를 넘는 구간은 없다. `canonicalLeanKernelCheck`
  직접 측정 0.28s/0.21s, `captureKernelAxioms`는 같은 소스를 `#print axioms`만 붙여 Lean을
  **재실행**하지만 같은 sub-second 등급이다.
- spawn/scan은 전부 계수됐다: git `rev-parse` 2회/chain(+setup materialize 2회), `lake env lean`
  2회/chain(커널 + axiom probe), `ircheck extract` 1회/subject, 그리고 per-process 1회 메모되는
  digest들. whole-tree 스캔 없음, 네트워크·`lake build` 없음(`packages: []`).
- 유일하게 스케일이 맞는 후보는 **EA 차분의 `ircheck` subprocess**다. `ircheck`는 Lean 런타임
  링크 exe(`proofs/lakefile.lean:35-38`, `import Lean`)로 cold 시 libleanshared 로드가 지배하고,
  저장소 자체의 역사 관측("+38/+38/+45/+43s cold verification step")과 형태가 일치한다.

**정직한 한계**: "ircheck ≈ 39s in CI"는 소거법 + 역사적 측정 일치에 의한 추론이며 직접 수치가
아니다(이 체크아웃에는 `proofs/.lake` 빌드가 없어 실행 불가). 5분짜리 판별 측정은 CI 러너에서
`time proofs/.lake/build/bin/ircheck extract --ast <wire> --out /tmp/x.bin`을 cold/warm으로
재는 것이다. 그 측정 전까지 C4의 절감량은 **상한 추정**이다.

## 4. 후보별 실측 상한과 판정 정체성 영향

| # | 후보 | 실측 상한 | 판정 정체성 | 판정 |
|---|---|---|---|---|
| C1 | full-chain의 axiom probe를 kernel check에 병합 (동일 소스 2회 실행 → 1회) | chain 시간의 **50%** — Run A 기준 s1a 60s, Run B 기준 30s | **변경됨**. KAA identity는 `ArtifactIdentity`·`KernelAcceptanceFact`를 포함하고(`kernel_acceptance_authority.nim` KAA identity 절), `proofDigest`는 receipt observation 원문이다. 병합은 증거 세대를 1회 flip한다 | **NO-GO (현 MUST)** — "증거 동일성" 위반. 의미 동등성은 증명 가능하나 **별도 epoch 승인**이 선행 조건 |
| C2 | B-layer가 `build/nimcache/test`를 공급 (warm compile) | 정규화 후 **0s** (§3.2) | 변경 없음 | **NO-GO** — 절감 증거 없음 |
| C3 | checker compile과 probe compile 병합 (probe가 `runSelfCheck`를 흡수) | **14.6s / 7.7s** (30s 미만) | 변경 없음 (probe는 pin 대상 → 2단계 pin 갱신 필요) | **NO-GO** — 임계값 미달 |
| C4 | subject별 EA 측정 1회 메모 + ircheck digest를 `measuredBinaryDigest` 경로로 | **상한 3×39s ≈ 117s** (s1a 전체), 보수적 2×39s ≈ 78s | **변경 없음** — 동일 bytes의 동일 sha256, 메모는 결정론적 값의 재사용 | **GO 후보** — CI 직접 측정(ircheck cold/warm)로 상한 확정 후 착수 |

## 5. 판정

1. **Phase C는 착수하지 않는다.** 현재 측정이 지지하는 identity-보존 후보 중 30s/배치를 넘는 것이 없다.
   이것은 실패가 아니라 계획이 예정한 정당한 종결이다(계획 §Phase C: "통과 후보가 없으면 NO-GO로 종결").
2. **Tier 3의 구조적 발견**: merge_group 시간의 지배 변수는 러너 인스턴스(2배)다. 코드 최적화로
   SLO를 안정화하려면 느린 호스트 기준(541s)에서 60s 이상을 줄여야 한다. 그 상한을 가진 후보는
   C1(증거 epoch 필요)과 C4(identity-보존, 상한 117s)다.
3. **C4가 다음 슬라이스의 첫 후보**다 — 세 가지 변형 모두 판정 정체성을 바꾸지 않는다:
   (i) ircheck digest를 `measuredBinaryDigest`로 라우팅(동일 bytes → 동일 sha256),
   (ii) EA 측정을 `(contentSha, funcName)`당 1회 메모(기존 parse memo와 동형, 결정론적 값 재사용),
   (iii) suite 전 Lean 런타임 예열(코드 변경 0).
   선행 조건은 §3.3의 CI 직접 측정(ircheck cold/warm)으로 상한을 확정하는 것이며, 그 측정은
   본 슬라이스의 권한 안에 있다. C1은 증거 세대 전환 승인이, SLO 운영 계약 강제는 러너 등급·동시성
   정책 결정이 선행되어야 하므로 별도 승인 대상이다.

## 6. 재현 명령

```bash
# 단계 타이밍 (merge_group run)
gh api repos/Archright/Axiom/actions/runs/<run-id>/jobs?per_page=100 \
  --jq '.jobs[] | "\(.name)\t\(.started_at)\t\(.completed_at)"'

# s1a 내부 분해
gh api repos/Archright/Axiom/actions/jobs/<lane0-job-id>/logs --allow-escape-sequences \
  | grep -E '\[Suite\]|\[OK\]|LANE lane=0'
```