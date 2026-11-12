# AOT Pipeline — 사전 컴파일 CAS 파이프라인

**Date:** 2026-07-10
**소스**: `src/core/gate/gate_cas.nim`, `src/cli/precompile_gates.nim`,
        `src/core/gate/transitive_hash.nim`, `src/gate/gateway.nim`
**AGENTS.md 참조**: §0.6 (Static First Enforcement), §1 (아키텍처 v29, v31)

---

## 1. 문제 정의: JIT 컴파일 레이턴시와 프로세스 고착

### 기존 구조 (AOT 파이프라인 이전)

pre-commit hook 실행 시, 게이트가 CAS에 없으면 JIT으로 `nim c`를 실행하여
바이너리를 생성한다:

```
  [BEFORE] JIT-on-miss 모델
  ─────────────────────────────────────────────

  git commit → pre-commit hook
  │
  ├─ Run gate: binary-freshness
  │  ├─ CAS lookup → MISS
  │  ├─ nim c src/gate/runners/binary_freshness_gate.nim  ← JIT 컴파일
  │  │     └─ 18분+ 소요 (대형 모듈 트리)
  │  ├─ Gate execution
  │  └─ Result: PASS/FAIL
  │
  ├─ Run gate: import-encapsulation
  │  ├─ CAS lookup → MISS
  │  ├─ nim c src/gate/runners/import_encapsulation_gate.nim  ← 또 JIT
  │  │     └─ 12분+ 소요
  │  ├─ Gate execution
  │  └─ Result: PASS/FAIL
  │
  └─ ... (게이트당 1회 JIT, 총 N회)

  문제:
  · 게이트당 nim c JIT: 3~18분 (모듈 트리 깊이에 따라)
  · pre-commit hook은 30초 타임아웃 → JIT이면 반드시 타임아웃
  · 타임아웃 후 프로세스 고착: nim c가 cgroup 밖에서 실행될 수 있음
  · 전체 커밋 파이프라인이 JIT 대기로 블록
  · 동일 소스를 반복 컴파일 ( 변경 없어도 매번 JIT )
```

### 핵심 비효율

| 항목 | BEFORE (JIT-on-miss) | AFTER (AOT-first) |
|------|----------------------|--------------------|
| pre-commit hook 시간 | 게이트당 3~18분 (JIT 포함) | ~0ms (CAS hit) |
| nim c 호출 빈도 | 게이트당 1회 (매 커밋) | 선택적 (소스/환경 변경 시만) |
| 커밋 차단 위험 | 높음 (JIT 타임아웃) | 없음 (사전 컴파일 완료) |
| disk 사용 | nimcache 중복 (게이트별) | 공유 nimcache (selective rebuild) |

---

## 2. 아키텍처 개요: CAS Lookup → O(1) Hit 또는 Fail-Fast

### 설계 원칙

1. **CAS 우선 (CAS-First)**: 모든 게이트 실행 전에 CAS에서 바이너리 조회.
2. **Hook/CI 모드 Fail-Fast**: pre-commit·pre-push·CI(gsCI) 스테이지의 훅 실행은
   `allowJit=false` → CAS 미스 = 즉시 실패 (fail-closed). JIT은 수동 CLI 모드(gsManual)만 허용.
3. **Selectively Recompile**: 소스 해시 또는 환경 해시 변경 시에만 해당 게이트 재컴파일.
4. **Precompile Workflow**: `bin/precompile_gates`가 모든 게이트를 사전 컴파일.
5. **Pre-push CAS 프리체크**: gateway.nim `runHookPrePush`가 pre-push 게이트 CAS 미스를
   사전 차단 (pre-commit의 `runHookPreCommit` 프리체크와 동일 정책).

```
  [AFTER] AOT-first 모델
  ─────────────────────────────────────────────

  사전 작업 (precommit 전):
  ┌──────────────────────────────────────────────────┐
  │  bin/precompile_gates                             │
  │  ├─ GateEnvLock fingerprint 계산                   │
  │  ├─ Lock file (.axiom/cache/gate_env.lock) 비교   │
  │  ├─ 환경 변경 → 전체 재컴파일                      │
  │  ├─ 소스 변경 → 선택적 재컴파일                     │
  │  └─ CAS에 바이너리 저장 (.axiom/cache/gates/<key>)│
  └──────────────────────────────────────────────────┘

  실행 시 (pre-commit hook):
  ┌──────────────────────────────────────────────────┐
  │  Run gate: binary-freshness                       │
  │  ├─ CAS lookup → HIT (O(1))                      │
  │  ├─ 바로 실행: .axiom/cache/gates/<key>/binary    │
  │  └─ Result: ~100ms                                │
  │                                                   │
  │  Run gate: import-encapsulation                   │
  │  ├─ CAS lookup → HIT (O(1))                      │
  │  ├─ 바로 실행                                     │
  │  └─ Result: ~50ms                                 │
  │                                                   │
  │  Total: <5초 (전체 게이트)                         │
  └──────────────────────────────────────────────────┘
```

---

## 3. `allowJit` 파라미터 설계

### `compileGateToCas` 시그니처

```nim
proc compileGateToCas*(gateId, entry, sourcePath, nimcacheDir, repoRoot: string;
                       transitiveHash: string = "";
                       allowJit: bool = true): string =
```

### `allowJit` 동작

| `allowJit` | CAS Hit | CAS Miss | 사용 위치 |
|-------------|---------|----------|-----------|
| `true` (기본값) | 기존 바이너리 반환 | JIT `nim c` 실행 → CAS 저장 | `bin/precompile_gates`, 수동 CLI 모드(gsManual) |
| `false` | 기존 바이너리 반환 | `""` 반환 (즉시 실패) | hook/CI 스테이지 (pre-commit, pre-push, gsCI) |

### Hook/CI 모드 통합 (실제 배선)

`allowJit=false`는 훅 실행 시점에서 스테이지로 판별되어 전달된다:

- **`executor.nim` `runSingleGateImpl`** — 훅/CI 스테이지(`gsPreCommit`, `gsPrePush`,
  `gsCI`, `gsAnyCi`)에서는 `allowJit=false`, 수동 CLI 모드(`gsManual`)에서는 `true`:

```nim
# executor.nim (runSingleGateImpl 내 CAS fallback)
let allowJit = (stage == gsManual)
let compiledPath = gate_cas.compileGateToCas(
  gate.id, entry, srcPath, nimcacheDir, repoRoot, allowJit = allowJit)
if compiledPath.len == 0:
  # CAS miss → gate 실행 불가 → precompile 안내
  return GateResult(ok: false, ...)
```

- **`integrity_workflow.nim` `resolveGatePath`** — 이 게이트는 gsCI 전용이므로
  `AXIOM_CI=1` 하에서 `allowJit=false` (사전 컴파일 필수), 로컬 수동 실행은 `true`:

```nim
# integrity_workflow.nim (resolveGatePath 내 CAS miss fallback)
let allowJit = not (getAxiomEnv(evCi) == "1")
let compiledPath = compileGateToCas(
  gateId, entry, absSource, nimcacheDir, REPO_ROOT, allowJit = allowJit)
```

- **gateway.nim pre-push 프리체크** — `runHookPrePush`가 `countMissingCasBinaries`로
  pre-push 게이트 CAS 미스를 사전 차단:

```nim
# gateway.nim (runHookPrePush 내)
let missingPushGates = countMissingCasBinaries(repoRoot, gsPrePush)
if missingPushGates > 0:
  logError("gateway", "[AOT] Run: bin/precompile_gates")
  quit(1)
```

### 설계 근거

- **pre-commit/pre-push/CI hook은 30초 타임아웃**. nim c JIT은 최소 3분.
- JIT을 허용하면 hook이 반드시 타임아웃 → 프로세스 고착 위험.
- AOT-first 모델에서는 `bin/precompile_gates`를 별도로 실행하여 모든 바이너리를 준비.
- hook은 "이미 준비된 바이너리를 실행"하는 것만 담당.
- 수동 CLI 모드(gsManual)는 개발자가 직접 `bin/axiom-gate`를 호출하는 시나리오로
  JIT 허용이 정상 (사전 컴파일 강제 없음).

---

## 4. Precompile Workflow (`bin/precompile_gates`)

### 실행 흐름

```
  bin/precompile_gates
  │
  ├─ 1. GateEnvLock fingerprint 계산
  │     ├─ nimVersion, nimHash, hostOS, hostCPU
  │     ├─ kernelVersion, stdlibHash
  │     ├─ configNimsHash, nimbleHash
  │     └─ gateSourceHashes (gateId → SHA-256)
  │
  ├─ 2. Lock file (.axiom/cache/gate_env.lock) 로드
  │
  ├─ 3. 환경 변경 감지 (envFingerprintChanged)
  │     ├─ nim 버전/해시 변경 → forceAll = true
  │     ├─ config.nims 변경 → forceAll = true
  │     └─ 환경 동일 → 소스 변경만 추적
  │
  ├─ 4. 소스 변경 감지 (findChangedGateIds)
  │     ├─ gateSourceHashes 비교
  │     └─ 변경된 gateId만 gatesToCompile에 추가
  │
  ├─ 5. CAS 바이너리 존재 확인 (resolveCasBinaryPath)
  │     ├─ CAS hit → cached 카운트 증가, 스킵
  │     └─ CAS miss → compileGateToCas (JIT 허용)
  │
  └─ 6. Lock file 업데이트 (항상 저장)
```

### 선택적 재컴파일

환경이 변경되지 않은 경우, 소스 해시가 변경된 게이트만 재컴파일한다:

```nim
if envFingerprintChanged(old, currentFingerprint):
  # 환경 변경: 전체 재컴파일
  forceAll = true
else:
  let changedIds = findChangedGateIds(old, currentFingerprint)
  if changedIds.len == 0:
    # 변경 없음: 즉시 종료
    quit(0)
  # 변경된 게이트만 재컴파일
  for cg in compilableGates:
    if cg.gateId in changedIds:
      gatesToCompile.add(cg)
```

---

## 5. GateEnvLock Fingerprinting (12-Field)

### Lock 타입 정의

```nim
type
  GateEnvLock = object
    nimVersion: string          ## 첫 번째 줄: `nim --version`
    nimHash: string             ## nim 바이너리의 SHA-256
    hostOS: string              ## Nim hostOS 상수
    hostCPU: string             ## Nim hostCPU 상수
    kernelVersion: string       ## `uname -r` 출력
    stdlibHash: string          ## nim/lib/system.nim의 SHA-256
    configNimsHash: string      ## config.nims의 SHA-256
    nimbleHash: string          ## axiom.nimble의 SHA-256
    gateSourceHashes: seq[(string, string)]  ## gateId → 소스 SHA-256
    createdAt: string           ## ISO 8601 타임스탬프
    gateCount: int              ## 매니페스트의 전체 게이트 수
```

### 필드별 무결성 보장

| 필드 | 변경 시 동작 | 보장 대상 |
|------|-------------|-----------|
| `nimVersion` | 전체 재컴파일 | Nim 언어 호환성 |
| `nimHash` | 전체 재컴파일 | 컴파일러 코드 생성 변경 감지 |
| `hostOS` | 전체 재컴파일 | OS별 조건부 컴파일 (`when defined(posix)`) |
| `hostCPU` | 전체 재컴파일 | 아키텍처별 코드 생성 |
| `kernelVersion` | 전체 재컴파일 | syscall ABI 변경 |
| `stdlibHash` | 전체 재컴파일 | 표준 라이브러리 변경 |
| `configNimsHash` | 전체 재컴파일 | 프로젝트 빌드 설정 변경 |
| `nimbleHash` | 전체 재컴파일 | 의존성 변경 |
| `gateSourceHashes` | 해당 gate만 | 소스 파일 변경 |
| `gateCount` | 전체 재컴파일 | 매니페스트 변경 |

### Lock 파일 경로

```
.axiom/cache/gate_env.lock
```

### Lock 파일 예시

```json
{
  "nimVersion": "Nim Compiler Version 2.2.10",
  "nimHash": "a1b2c3d4e5f6...",
  "hostOS": "linux",
  "hostCPU": "amd64",
  "kernelVersion": "6.5.0-generic",
  "stdlibHash": "f6e5d4c3b2a1...",
  "configNimsHash": "1a2b3c4d5e6f...",
  "nimbleHash": "6f7e8d9c0b1a...",
  "gateSourceHashes": {
    "binary-freshness": "aa11bb22cc33...",
    "import-encapsulation": "dd44ee55ff66..."
  },
  "createdAt": "2026-07-10T06:00:00Z",
  "gateCount": 56
}
```

---

## 6. Selective Recompilation (소스 해시 기반)

### 해시 체계

```
  GateEnvLock                              gate_cas.nim
  ┌───────────────────────┐               ┌────────────────────────────┐
  │ gateSourceHashes:     │               │ computeSourceHash:         │
  │   foo: SHA-256(src)   │── 비교 ──────▶│   SHA-256(소스 파일)       │
  │   bar: SHA-256(src)   │               │                            │
  │   baz: SHA-256(src)   │               │ computeTransitiveSourceHash│
  └───────────────────────┘               │   Merkle root (전체 의존성)│
                                          └────────────────────────────┘
```

### 3단계 해시

1. **단일 파일 해시** (`computeSourceHash`): 게이트 러너 `.nim` 파일만의 SHA-256
2. **전이적 해시** (`computeTransitiveSourceHash`): `import`된 모든 모듈의 Merkle tree root
3. **CAS 키 해시**: 소스 해시 + 설정 해시 + (전이적 해시) → CAS 키 생성

### 전이적 의존성 해싱 (transitive_hash.nim)

```
  binary_freshness_gate.nim
    ├─ import core/results          → SHA-256(core/results.nim)
    ├─ import core/trusted/...      → SHA-256(...)
    └─ Merkle root = SHA-256(
         SHA-256(self) || SHA-256(dep1) || SHA-256(dep2) || ...
       )
```

- `import`/`from` 구문을 DFS로 파싱
- 순환 참조(cycle) 감지 포함
- 표준 라이브러리(`std/`, `system`)는 제외

### 재컴파일 트리거 조건

| 조건 | 결과 |
|------|------|
| `config.nims` 변경 | **전체** 게이트 재컴파일 |
| `axiom.nimble` 변경 | **전체** 게이트 재컴파일 |
| Nim 버전 업그레이드 | **전체** 게이트 재컴파일 |
| 게이트 소스 파일 변경 | **해당** 게이트만 재컴파일 |
| 게이트 소스 + 의존성 변경 | **해당** 게이트만 재컴파일 (전이적 해시) |
| 변경 없음 | 재컴파일 없음 (즉시 종료) |

---

## 7. CAS Key 형식

### 기본 키

```
{gateId}-{srcHash[:16]}-{cfgHash[:16]}
```

### 전이적 해시 포함 키

```
{gateId}-{srcHash[:16]}-{cfgHash[:16]}-{tHash[:16]}
```

### 키 생성 로직

```nim
proc computeCasKey*(gateId, sourceHash: string; repoRoot: string;
                    transitiveHash: string = ""): string =
  let cfgHash = computeBuildEnvHash(repoRoot)
  let srcShort = sourceHash[0 ..< min(16, sourceHash.len)]
  let cfgShort = cfgHash[0 ..< min(16, cfgHash.len)]
  if transitiveHash.len > 0:
    let tShort = transitiveHash[0 ..< min(16, transitiveHash.len)]
    gateId & "-" & srcShort & "-" & cfgShort & "-" & tShort
  else:
    gateId & "-" & srcShort & "-" & cfgShort
```

### 예시

```
binary-freshness-a1b2c3d4e5f6g7h8-f6e5d4c3b2a10987

binary-freshness-a1b2c3d4e5f6g7h8-f6e5d4c3b2a10987-1a2b3c4d5e6f7890
```

### CAS 디렉토리 구조

```
.axiom/cache/gates/
├── binary-freshness-a1b2c3d4e5f6g7h8-f6e5d4c3b2a10987/
│   └── binary              ← 컴파일된 바이너리
├── import-encapsulation-b2c3d4e5f6g7h8i9-e5d4c3b2a1098765/
│   └── binary
└── ...
```

---

## 8. Gateway 통합 (Auto-Precompile on CAS Miss)

### Hook/CI 모드 동작

gateway.nim의 pre-commit/pre-push hook 경로는 CAS 프리체크 먼저 수행한다:

```
  pre-commit / pre-push hook
  │
  ├─ countMissingCasBinaries(repoRoot, stage)  ← 스테이지별 CAS 프리체크
  │  ├─ MISS 존재 → logError("Run `bin/precompile_gates` first") + quit(1)
  │  └─ 전부 HIT  → 진행
  │
  ├─ Run gate (allowJit=false)
  │  ├─ CAS lookup → HIT: 바로 실행
  │  └─ CAS lookup → MISS:
  │     ├─ logError("[CAS-MISS] Run `bin/precompile_gates` first")
  │     └─ return false (hook 실패)
  │
  └─ 사용자에게 안내:
     "Run `bin/precompile_gates` to precompile gate binaries"
```

- **pre-commit**: `runHookPreCommit` → `countMissingCasBinaries(repoRoot, gsPreCommit)`
  → fail-closed 차단.
- **pre-push**: `runHookPrePush` → `countMissingCasBinaries(repoRoot, gsPrePush)`
  → fail-closed 차단 (pre-push heavy 게이트의 JIT 3~18분 발생 제거).
- 실행 시점 2차 방어: `executor.nim`/`integrity_workflow.nim`의 `allowJit=false`가
  CAS miss를 즉시 실패로 전환.

### 사용자 워크플로우

```bash
# 1. 게이트 사전 컴파일 (한 번만, 또는 소스 변경 시)
bin/precompile_gates

# 2. 커밋/푸시 (pre-commit/pre-push hook이 CAS에서 바로 실행)
git commit -m "feat: ..."
git push

# 3. (또는 자동)
# hook이 CAS miss를 감지하면 에러 메시지 출력
# → 사용자가 bin/precompile_gates 실행 후 재시도
```

---

## 9. CAS 무결성

### Atomic Write

컴파일된 바이너리는 `binary.tmp`에 먼저 쓰고, `fsync` 후 `binary`로 원자적 rename:

```nim
let tmpPath = target & ".tmp"
let fh = open(tmpPath, fmWrite)
fh.write(content)
fh.flushFile()
fh.close()
safeMoveFile(tmpPath, target)
```

### Integrity Check

`verifyCasIntegrity()`가 다음을 검증:

1. **`.recover` 플래그**: Double Fault recovery — manifest + tmp 디렉토리 삭제 → 재빌드
2. **stale tmp 디렉토리**: 이전 컴파일이 크래시된 잔여물 → 자동 정리

---

## 10. Nim Compilation Cache 참고

Nim 자체의 compilation cache (`--nimcache`)와의 관계:

| 항목 | Nim nimcache (`build/nimcache/`) | AOT CAS (`.axiom/cache/gates/`) |
|------|----------------------------------|--------------------------------|
| 내용 | 중간 object 파일 (`.o`, `.c`) | 최종 바이너리 (`binary`) |
| 키 기반 | 소스 파일 + 컴파일러 설정 | gateId + 소스 해시 + 설정 해시 |
| 수명 | 빌드 간 유지 | Lock 파일 기반 선택적 갱신 |
| 용도 | nim c 재컴파일 가속 | hook 실행 시 JIT 없이 바로 실행 |

Nim의 `--nimcache`는 `precompile_gates`가 각 게이트별 고립된 디렉토리
(`build/nimcache_precompile/<gateId>`)를 사용하여, 게이트 간 nimcache 충돌을 방지한다.

---

## 11. 한계점 및 알려진 문제

1. **Lock 파일 수동 관리**: `bin/precompile_gates`를 수동으로 실행해야 한다.
   향후 파일 watcher 연동 또는 `git config` hook으로 자동화 가능.
2. **전이적 해시 오버헤드**: 대형 의존성 트리의 DFS 순회가 느릴 수 있다.
   현재는 게이트 러너의 의존성이 제한적이므로 실질적 문제 없음.
3. **cross-platform nimHash**: nim 바이너리의 SHA-256은 플랫폼별로 다르다.
   CI 빌드 서버와 로컬 환경이 다르면 Lock 파일이 항상 변경됨.
   → 정상 동작: CI 환경에서 자동 재컴파일.

---

## 12. Performance Characteristics (Post-D-Bus Elimination)

### 12.1 Pre-Native Cgroup (systemd-run)

- 82 gate subprocesses × D-Bus IPC per scope creation = ~10 minutes total
- Serial D-Bus message queue contention
- Pre-commit hook timeout

### 12.2 Post-Native Cgroup (sysfs direct writes)

- 82 gate subprocesses × `mkdir` + `writeFile` per gate = O(1) per gate
- Batch cgroup pre-creation: single pass before dispatch
- Dynamic concurrency: `min(cpuCount, 16)` concurrent gates
- Expected total pre-commit time: < 30 seconds

### 12.3 Dynamic Concurrency (v30)

| Parameter | Before | After |
|-----------|--------|-------|
| MaxConcurrentL2 | 6 (hardcoded) | min(cpuCount, 16), min 2 |
| GlobalMaxTokens | 12 (hardcoded) | MaxConcurrentL2 × 2 |
| Cgroup creation | Interleaved per gate | Batch pre-creation |
