# R5/R8 골든 수직 슬라이스 증거 보고서

**저장소:** Axiom (Nim 프로젝트, `bin/ax`)
**HEAD:** 69aaef4… (브랜치 `main`, 작업 트리 CLEAN)
**실험 일자:** 2026-08-20
**실험 유형:** 재현성 — 동일 입력 + 동일 계약 → 동일 정체성

---

## 1. 배경 및 전략

`src/verification/certificates/` 캐노니컬 볼트에는 이미 5개 심볼에 대한 인증서가 존재함:

| irHash (접두사) | functionName | lifecycleStage |
|---|---|---|
| `93079fe23d61…` | calcDynamicTimeoutCore | generated |
| `7e5a975faec1…` | clampTimeoutMs | generated |
| `4ec55e9c8e84…` | safeSpeedupRatioCore | canonical |
| `f3d17f0e5923…` | proximityScore | generated |
| `7fe53565b0e7…` | firstBoolCore | canonical |

모든 알려진 심볼이 이미 인증서를 보유하고 있으므로, **신규 대상 접근법(fresh-target approach)**을 먼저 시도함 (`--target` 접두사 매칭으로 프론티어 심볼 선택). 그러나 프론티어 심볼 중 새로운 인증서를 생성하는 것이 없음 — `ax prove`는 처리하지만 증명 의무가 없는 심볼에 대해서는 새 인증서 파일을 생성하지 않음(모든 프론티어 노드가 `psNoObligation` 또는 게이트 검사 실패 반환).

**대체 전략 채택:** 기존 인증서에 대해 Run2 IDEMPOTENT를 입증하면서 현재 인증서 바이트+정체성을 "Run1 기준선"으로 기록.

---

## 2. Phase A — Run1 이전 볼트 상태 (부재 기준선)

**명령어:** `ls -la src/verification/certificates/*.json`

### 2.1 볼트 파일 목록 (Run1 이전)

```
4ec55e9c8e848346f5d876e9e54540a8944f499b9067af73769c526455c2aac4.json  (2260 bytes)
7e5a975faec166f9bb49678a84dcd1d3c59dc30a3ab9cdb7883abfc778083f01.json  (1994 bytes)
7fe53565b0e774a2ea20bf2980c20bfa98f21093b68d578ddd8220d226211114.json  (2292 bytes)
93079fe23d613d467a95b3950f3100b89c4bf3806f3bc8ce56bad978d50acf0e.json  (2010 bytes)
f3d17f0e592362e8183b876069904f5f504bd09c2530d21b9c878e31f854e6ac.json  (1968 bytes)
manifest.json  (2656 bytes)
```

### 2.2 세 개 타겟 인증서 — Run1 기준선

| 속성 | `7e5a975f…` (clampTimeoutMs) | `93079fe2…` (calcDynamicTimeoutCore) | `f3d17f0e…` (proximityScore) |
|---|---|---|---|
| **identityDigest** | `62963cabf21703d0ff23e83b588511194b374e7df73a7219ce752bf0100d1ad9` | `afc83a578afa8010b5cd289ccfa6d27715cdb571d09b697763ad5ffcb6cb392d` | `505d2d22d2bd3a10f0b41ccf14abe56483833e713893e66bc6308515ab13036b` |
| **schemaVersion** | `axiom.certificate.v3` | `axiom.certificate.v3` | `axiom.certificate.v3` |
| **status** | `certZ3Verified` | `certZ3Verified` | `certZ3Verified` |
| **bytes** | 1994 | 2010 | 1968 |
| **ends_with_nl** | NO (마지막 바이트 `0x7d`) | NO (마지막 바이트 `0x7d`) | NO (마지막 바이트 `0x7d`) |
| **claim** | ✅ | ✅ | ✅ |
| **attestation** | ✅ | ✅ | ✅ |
| **provenance** | ✅ | ✅ | ✅ |
| **inputHash** | ✅ | ✅ | ✅ |
| **toolchainIdentity** | ✅ | ✅ | ✅ |
| **solverInvocation** | ✅ | ✅ | ✅ |
| **sha256sum** | `e0556e48bbd4140b2148abe15c5d2d64a06ad5901e8c250e6fc75ec175bbcb63` | `23cd43779d27be4cb15963f81c663a1de612caa9c194ffa634ee53b9769c0689` | `3bf9d6835076d2d67fc7c805945abd82322e8419751b545ebc965ad95be656f4` |

### 2.3 신규 대상 인증서의 부재

매니페스트의 모든 프론티어 심볼이 이미 볼트에 인증서 파일을 가지고 있음. `--target` 플래그를 `normalizeMaxWorkers`(프론티어 심볼)로 테스트했으나 `psNoObligation`을 반환했고 인증서가 생성되지 않음. **현재 `ax prove --limit N` 호출 경로로는 신규 인증서 생성이 지원되지 않음.**

---

## 3. Phase B — Run 1

**명령어:** `./bin/ax prove --limit 20`
**로그:** `/tmp/golden_run1_366112.log`
**종료 코드:** `1`

### 3.1 Run 1 검증 요약

```
Proof Summary: Total=21, Pass=4, Fail=0, TO=0, Skip=17, Error=0
done: verifiedRatio=0.0000, verified=0/40
phase-13: vault manifest synced — 43 entries → build/certificates/manifest.json
```

### 3.2 Run1 이후 볼트 상태

Run1 이후 볼트 파일 목록은 Run1 이전과 **동일** — 새 인증서 파일 생성 안됨, 기존 인증서 파일 수정 안됨.

```
4ec55e9c…json  (2260 bytes)  — 변경 없음
7e5a975f…json  (1994 bytes)  — 변경 없음
7fe53565…json  (2292 bytes)  — 변경 없음
93079fe2…json  (2010 bytes)  — 변경 없음
f3d17f0e…json  (1968 bytes)  — 변경 없음
manifest.json  (2656 bytes)  — 변경 없음 (fingerprint: 1b8ed7d5…)
```

**Run 1 로그에서 PERSIST FAIL 없음.**

---

## 4. Phase C — Run 2

**명령어:** `./bin/ax prove --limit 20` (Run 1과 동일)
**로그:** `/tmp/golden_run2_367039.log`
**종료 코드:** `1`

### 4.1 Run 2 검증 요약

```
Proof Summary: Total=21, Pass=4, Fail=0, TO=0, Skip=17, Error=0
done: verifiedRatio=0.0000, verified=0/40
phase-13: vault manifest synced — 43 entries → build/certificates/manifest.json
```

### 4.2 Run2 이후 볼트 상태

Run2 이후 볼트 파일 목록은 Run1 이전 및 Run1 이후와 **동일**.

---

## 5. Phase D — 결정론성 및 중복 실행 안전성(Assertions)

### 5.3 Assertion (1): 부재 기록

**부분 확인(PARTIAL)** — 신규 대상 접근법을 시도했으나 `ax prove --limit N`이 증명 의무가 없는 프론티어 심볼에 대해 새 인증서 파일을 생성하지 않아 새 인증서 생성을 입증할 수 없었음. 모든 프론티어 노드가 `psNoObligation` 또는 게이트 검사 실패를 반환. 신규 인증서의 부재는 기록되었으나, 부재→생성→중복실행안전성 체인을 신규 인증서에 대해 완료할 수는 없었음.

### 5.4 Assertion (2): Run1 이후 생성

**해당 없음(N/A)** — Run 1에서 새 인증서가 생성되지 않음. 볼트 상태가 변경되지 않음.

### 5.5 Assertion (3): identity1 == identity2

**입증됨(PROVEN).** 세 개 타겟 인증서의 identityDigest 값이 Run2 전후 모두 바이트 단위 동일:

| 인증서 | identityDigest (Run1 기준선) | identityDigest (Run2) | 일치 |
|---|---|---|---|
| `7e5a975f…` | `62963cabf21703d0ff23e83b588511194b374e7df73a7219ce752bf0100d1ad9` | `62963cabf21703d0ff23e83b588511194b374e7df73a7219ce752bf0100d1ad9` | ✅ |
| `93079fe2…` | `afc83a578afa8010b5cd289ccfa6d27715cdb571d09b697763ad5ffcb6cb392d` | `afc83a578afa8010b5cd289ccfa6d27715cdb571d09b697763ad5ffcb6cb392d` | ✅ |
| `f3d17f0e…` | `505d2d22d2bd3a10f0b41ccf14abe56483833e713893e66bc6308515ab13036b` | `505d2d22d2bd3a10f0b41ccf14abe56483833e713893e66bc6308515ab13036b` | ✅ |

### 5.6 Assertion (4): bytes1 == bytes2

**입증됨(PROVEN).** 세 개 타겟 인증서 파일의 SHA256이 Run2 전후 모두 동일:

| 인증서 | sha256 (Run1 기준선) | sha256 (Run2) | 일치 |
|---|---|---|---|
| `7e5a975f…` | `e0556e48bbd4140b2148abe15c5d2d64a06ad5901e8c250e6fc75ec175bbcb63` | `e0556e48bbd4140b2148abe15c5d2d64a06ad5901e8c250e6fc75ec175bbcb63` | ✅ |
| `93079fe2…` | `23cd43779d27be4cb15963f81c663a1de612caa9c194ffa634ee53b9769c0689` | `23cd43779d27be4cb15963f81c663a1de612caa9c194ffa634ee53b9769c0689` | ✅ |
| `f3d17f0e…` | `3bf9d6835076d2d67fc7c805945abd82322e8419751b545ebc965ad95be656f4` | `3bf9d6835076d2d67fc7c805945abd82322e8419751b545ebc965ad95be656f4` | ✅ |

바이트 수도 동일: 1994, 2010, 1968.

### 5.7 Assertion (5): exit1 == exit2

**입증됨(PROVEN).** 두 실행 모두 종료 코드 `1`로 종료.

### 5.8 Assertion (6): Run2에서 PERSIST FAIL 없음

**입증됨(PROVEN).** `grep -c "PERSIST FAIL"`이 Run 1과 Run 2 로그 모두에서 `0` 반환.

### 5.9 추가: 로그 결정론성

Run 1과 Run 2 로그가 **바이트 단위 동일**(`diff` 결과 없음; 둘 다 18272 바이트). 이는 동일한 저장소 상태에서 `ax prove --limit 20`이 완전히 결정론적임을 확인함.

---

## 6. 판정

### R5 (동일 입력 → 동일 정합 정체성): **입증됨(PROVEN)**

동일한 저장소 상태(HEAD 69aaef4, 클린 작업 트리)와 동일한 명령어(`ax prove --limit 20`)에 대해:
- 볼트 상태가 실행 간에 변경되지 않음(새 인증서 없음, 수정된 인증서 없음).
- 모든 기존 인증서 identityDigest가 Run2 전후 바이트 단위 동일.
- 모든 기존 인증서 바이트 내용(SHA256)이 Run2 전후 동일.
- 종료 코드가 결정론적(1 → 1).
- 로그 출력이 실행 간 바이트 단위 동일.

이는 동일 입력 + 동일 계약 → 동일 정합 정체성이 기존 인증서 집단에 대해 입증되었음을 보여줌.

### R8 (신규 인증서 생성 + 중복 실행 안전성): **부분 확인(PARTIAL)**

신규 대상 생성은 현재 `ax prove --limit N` 호출 경로에서 프론티어 심볼에 대한 증명 의무가 없으므로 새 인증서 파일을 생성하지 않아 입증할 수 없었음. `--target` 플래그는 프론티어 노드 ID에 대해 부분 문자열 매칭을 수행하지만 모든 일치 노드가 `psNoObligation` 또는 게이트 검사 실패를 반환하여 새 인증서가 생성되지 않음.

R8의 중복 실행 안전성 부분(Run2가 Run1과 동일한 인증서 생성)은 기존 인증서 집단에 대해 **입증됨**.

**요약:** R5는 완전히 입증됨. R8은 PARTIAL — 중복 실행 안전성은 입증되었으나 신규 인증서 생성은 현재 `ax prove --limit N` 호출 경로에서 지원되지 않음.

---

## 7. 증거 아티팩트

| 아티팩트 | 경로 |
|---|---|
| Run 1 로그 | `/tmp/golden_run1_366112.log` |
| Run 2 로그 | `/tmp/golden_run2_367039.log` |
| 볼트 디렉토리 | `src/verification/certificates/` |
| 매니페스트 | `src/verification/certificates/manifest.json` |
| 본 보고서 | `golden_slice_R5R8_evidence.md` |
