# State Ledger Architecture — v27 (WorkspaceState v4) 중앙 집중형 상태 장부

> v27 검증 파이프라인의 **중앙 집중형 State Ledger** 설계에 대한 SSOT. WorkspaceState는 v4로 업그레이드됨 (stagingTreeHash 추가, padding 확장).
> 마이그레이션 문제(반응형 L2 재계산), 바이너리 레이아웃, mmap 보안,
> CRC32 무결성, 그리고 v24→v27 진화 역사를 포함한다.

**Date:** 2026-06-19
**Supersedes:** 기존 L2 자식 프로세스의 반응형 recomputation 패턴

---

## 1. 문제 정의: 반응형 L2 재계산

### 기존 구조 (v26 이전)

Gate orchestrator(부모 프로세스)가 게이트를 실행하면, 각 L2 자식 프로세스는
독립적으로 워크스페이스 상태를 재계산한다:

```
  [BEFORE] 반응형 (Reactive) 모델
  ─────────────────────────────────────────────

  부모 프로세스                      자식 프로세스 (L2 × N)
  ┌─────────────┐                   ┌────────────────────────────┐
  │ gate runner │─── spawn ───────▶ │ dirtyHash = git diff ...   │
  │             │                   │ buildEnvHash = sha256(...) │
  │             │                   │ ruleHash = sha256(...)     │
  │             │                   │ cacheKey = composite(...)  │
  │             │                   │ if cacheKey == cached:     │
  │             │                   │   skip                     │
  │             │                   │ else:                      │
  │             │                   │   execute gate             │
  └─────────────┘                   └────────────────────────────┘

  문제:
  · 53개 자식 각각 독립적으로 `git diff`, `git status` 실행 → O(N) git 호출
  · 동일한 dirtyHash를 53번 계산 (하나만 변경되어도 전부 재계산)
  · 각 자식이 독립적 캐시 키 생성 → 불일차 가능
  · 자식 프로세스 간 워크스페이스 상태 동기화 없음
```

### 핵심 비효율

| 항목 | BEFORE (반응형) | AFTER (선제적) |
|------|-----------------|----------------|
| `git diff --stat` 호출 횟수 | 53 (gate당 1회) | 1 (부모 1회) |
| `git status --porcelain` 호출 횟수 | 53 | 1 |
| `sha256(config.nims + nimble + ...)` 호출 횟수 | 53 | 1 |
| 워크스페이스 상태 일관성 | 보장 불가 (race condition) | 보장 (single source of truth) |
| 캐시 키 불일차 위험 | 높음 | 없음 |

---

## 2. 아키텍처 개요: 부모 → mmap → 자식

### 설계 원칙

v27 State Ledger는 **선제적(proactive)** 모델이다:

1. **부모가 한 번** 워크스페이스 상태를 계산한다 (`dirtyHash`, `buildEnvHash`, `ruleHash`)
2. **부모가 고정 크기 바이너리 파일로** 원자적 쓰기(atomic write) 수행
3. **각 자식은 mmap read-only** 로 접근 → git 서브프로세스 호출 불필요
4. **CRC32 체크섬**으로 무결성 검증

```
  [AFTER] 선제적 (Proactive) 모델
  ─────────────────────────────────────────────

  부모 프로세스                           자식 프로세스 (L2 × N)
  ┌──────────────────────┐               ┌────────────────────────┐
  │ 1. compute dirtyHash │               │ 1. mmap ledgers/       │
  │ 2. compute buildHash │               │    gate.axgl (read-only│
  │ 3. compute ruleHash  │               │ 2. validate magic+CRC  │
  │ 4. fill GateLedger   │               │ 3. read workspace.*    │
  │ 5. atomicWrite file  │── ledger ───▶ │ 4. read gates[i].key   │
  │ 6. fsync + rename    │               │ 5. compare cacheKey    │
  └──────────────────────┘               │ 6. skip or execute     │
                                         └────────────────────────┘

  장점:
  · git 호출 53회 → 1회 (98% 감소)
  · 모든 자식이 동일한 상태 읽음 → 일관성 보장
  · mmap은 OS 페이지 캐시 활용 → zero-copy
  · CRC32로 무결성 보장 → 손상된 파일 접근 차단
```

### 소스 파일

| 구성 요소 | 경로 |
|-----------|------|
| Ledger 타입 정의 | `src/core/gate/state_ledger_types.nim` |
| 해시 타입 (`HashValue`, `fnv1a`) | `src/core/gate/hash_types.nim` |
| mmap + 원자적 쓰기 (AxiomLedgerCap=56 용량 상한 사용) | `src/core/gate/state_ledger.nim` |
| AxiomTotalGates (라이브 게이트 수, TopologySpec.len=53) | `src/gate/gate_contract.nim` |
| IoBoundary 프라그마 | `src/core/trusted/axiom_pragmas.nim` |

---

## 3. 바이너리 레이아웃

### 전체 구조 (7,400 bytes)

```
  GateLedger — 7,400 bytes (2 pages — 4,096 bytes + 3,304 bytes)
  ═══════════════════════════════════════════════════════════════

  Offset    Size     Field
  ────────  ───────  ──────────────────────────────────────────
  0x0000    64 B     LedgerHeader
  0x0040    160 B    WorkspaceState
  0x00E0    7,168 B  GateStateEntry × 56 (용량) / 53 (라이브)
  0x1CE0    4 B      checksum (CRC32)
  0x1CE4    4 B      padding (alignment)
  ────────  ───────  ──────────────────────────────────────────
  Total:    7,400 B
```

### LedgerHeader (64 bytes)

```
  LedgerHeader — 64 bytes, fields ordered to avoid alignment gaps
  ┌──────────────────────────────────────────────────────────────┐
  │ [0x00] magic:        uint32    0x4158474C ("AXGL")          │
  │ [0x04] version:      uint16    4 (layout version, v4)      │
  │ [0x06] headerSize:   uint16    64 (self-describing)          │
  │ [0x08] totalSize:    int64     7400 (total file size)       │
  │ [0x10] epoch:        uint32    cache epoch                   │
  │ [0x14] gateCount:    uint16    number of gate entries        │
  │ [0x16] stagedCount:  uint16    staged files at creation     │
  │ [0x18] padding:      uint8×40  zero-filled (reserved)       │
  └──────────────────────────────────────────────────────────────┘
```

### WorkspaceState (160 bytes)

```
  WorkspaceState — 160 bytes, the Single Source of Truth
  ┌──────────────────────────────────────────────────────────────┐
  │ [0x00] dirtyHash:       HashValue    32 bytes (SHA-256)     │
  │        → SHA-256(git diff --stat ++ git status --porcelain) │
  │ [0x20] ruleHash:        HashValue    32 bytes (SHA-256)     │
  │        → SHA-256(config.nims ++ architecture_debt.json)     │
  │ [0x40] buildEnvHash:    HashValue    32 bytes (SHA-256)     │
  │        → SHA-256(config.nims + nimble + debt + NimVer + ..)│
  │ [0x60] stagingTreeHash: HashValue    32 bytes (SHA-256)     │
  │        → SHA-256(git write-tree output)                     │
  │ [0x80] timestamp:       int64        Unix epoch seconds      │
  │ [0x88] baseCommit:      uint8×20     Git SHA-1 (raw bytes)  │
  │ [0x9C] stage:           uint8        LedgerStage enum value │
  │ [0x9D] mode:            uint8        GateRunMode (0=incr/1=exc)│
  │ [0x9E] padding:         uint8×2      alignment              │
  └──────────────────────────────────────────────────────────────┘
```

### GateStateEntry (128 bytes × 56 용량)

```
  GateStateEntry — 128 bytes per gate, indexed by gate registry order
  ┌──────────────────────────────────────────────────────────────┐
  │ [0x00] cacheKey:       HashValue    32 bytes                │
  │ [0x20] lastTimestamp:  int64        8 bytes (Unix epoch)    │
  │ [0x28] deferredAt:     int64        8 bytes (0 = not deffered)│
  │ [0x30] gateIdHash:     uint32       FNV-1a of gate ID str   │
  │ [0x34] execTimeMs:     int32        execution time (ms)     │
  │ [0x38] result:         uint8        LedgerGateResult enum    │
  │ [0x39] tier:           uint8        1=L1 meta, 2=L2 funct.  │
  │ [0x3A] deferredStage:  uint8        Stage that deferred     │
  │ [0x3B] reserved:       uint8×69     zero-filled (reserved)  │
  └──────────────────────────────────────────────────────────────┘

  gateIdHash = FNV-1a("gate-name") → 53 라이브 게이트에서 충돌 없음
  (용량 AxiomLedgerCap=56 슬롯, 2^32 / 53 ≈ 8천만 대 1 충돌 확률 — 충분히 안전)
```

### 체크섬 + 패딩 (8 bytes)

```
  ┌──────────────────────────────────────────────────────────────┐
  │ [0x1CE0] checksum:  uint32   CRC32 of bytes [0x00..0x1CDF] │
  │ [0x1CE4] padding:   uint8×4  zero-filled (8-byte alignment) │
  └──────────────────────────────────────────────────────────────┘
```

---

## 4. 데이터 흐름도

### Phase 1: 부모가 Ledger 작성

```
  부모 프로세스 (Gate Orchestrator)
  ┌─────────────────────────────────────────────────┐
  │                                                 │
  │  1. git diff --stat ──────────────┐             │
  │  2. git status --porcelain ───────┤             │
  │                                   ▼             │
  │                        SHA-256 concat           │
  │                        → dirtyHash              │
  │                                                 │
  │  3. config.nims + nimble.lock + ...             │
  │                        → buildEnvHash           │
  │                                                 │
  │  4. config.nims + architecture_debt.json        │
  │                        → ruleHash               │
  │                                                 │
  │  5. git rev-parse HEAD                          │
  │                        → baseCommit[20]         │
  │                                                 │
  │  6. For each gate (i = 0..52):                  │
  │     ├─ compositeHash(dirtyHash, gateId, tier)   │
  │     │        → gates[i].cacheKey                │
  │     ├─ lookup previous run → lastTimestamp      │
  │     └─ result = lgrUnknown (initial)            │
  │                                                 │
  │  7. CRC32(bytes[0..0x1CDF]) → checksum         │
  │                                                 │
  │  8. atomicWrite:                                │
  │     ├─ write to ledgers/.tmp.axgl               │
  │     ├─ fsync(fd)                                │
  │     └─ rename(.tmp.axgl → gate.axgl)           │
  └─────────────────────────────────────────────────┘
```

### Phase 2: 자식이 Ledger 읽기

```
  자식 프로세스 (L2 Gate Runner)
  ┌─────────────────────────────────────────────────┐
  │                                                 │
  │  1. mmap("ledgers/gate.axgl",                   │
  │          PROT_READ, MAP_PRIVATE)                │
  │                                                 │
  │  2. Validate:                                   │
  │     ├─ header.magic == 0x4158474C?              │
  │     ├─ header.version == 4?                     │
  │   ├─ header.totalSize == 7400?                │
  │   └─ CRC32(bytes[0..0x1CDF]) == checksum?    │
  │                                                 │
  │  3. Read workspace state:                       │
  │     ├─ dirtyHash  ← workspace.dirtyHash         │
  │     ├─ buildHash  ← workspace.buildEnvHash      │
  │     └─ ruleHash   ← workspace.ruleHash          │
  │                                                 │
  │  4. Find my gate entry:                         │
  │     ├─ myHash = fnv1a("my-gate-id")             │
  │     └─ entry = findGateEntry(ledger, myHash)    │
  │                                                 │
  │  5. Compare:                                    │
  │     ├─ entry.cacheKey == myCachedKey?           │
  │     │   → YES: skip (cache hit)                 │
  │     │   → NO:  execute gate                     │
  │     └─ entry.result == lgrSkip?                 │
  │         → skip (parent determined unaffected)   │
  └─────────────────────────────────────────────────┘
```

---

## 5. 결정론 보장 (Determinism Guarantee)

### 보장 테이블

| 보장 항목 | 메커니즘 | 검증 방법 |
|-----------|---------|-----------|
| **동일 입력 → 동일 dirtyHash** | `git diff --stat` + `git status --porcelain`은 동일 워크스페이스에서 결정론적 | `fnv1a` 해시 검증 |
| **동일 빌드 환경 → 동일 buildEnvHash** | `config.nims` + `nimble.lock` + `NimVersion` 등 고정 입력 | 정적 입력 검증 |
| **동일 규칙 → 동일 ruleHash** | `config.nims` + `architecture_debt.json` 고정 입력 | 정적 입력 검증 |
| **동일 게이트 ID → 동일 FNV-1a** | `fnv1a`는 결정론적 (같은 입력 → 같은 출력) | `hash_types.nim` `func` |
| **동일 layout → 동일 sizeof** | 컴파일 타임 `static assert`로 크기 검증 | `state_ledger_types.nim` |
| **CRC32 무결성** | 쓰기 시 계산, 읽기 시 검증 | 손상된 파일 접근 차단 |
| **원자적 쓰기** | `atomicWrite` (write-tmp + fsync + rename) | 깨진 Ledger 방지 |
| **read-only mmap** | `PROT_READ` + `MAP_PRIVATE` | 자식이 Ledger를 변경 불가 |

### 결정론적 해시 체인

```
  dirtyHash = SHA-256(
    git diff --stat HEAD  ++       ← 워크스페이스 변경 내용
    git status --porcelain         ← staged/untracked 파일 목록
  )

  buildEnvHash = SHA-256(
    config.nims          ++        ← 빌드 설정
    nimble.lock          ++        ← 의존성 고정
    architecture_debt.json ++      ← 아키텍처 부채
    NimVersion           ++        ← 컴파일러 버전
    ...
  )

  ruleHash = SHA-256(
    config.nims          ++        ← 규칙 소스
    architecture_debt.json         ← 규칙 정의
  )

  cacheKey = compositeHash(
    dirtyHash,                     ← 워크스페이스 상태
    gateIdHash,                    ← 게이트 식별자
    buildEnvHash,                  ← 빌드 환경
    tier                           ← 게이트 티어
  )
```

---

## 6. mmap 보안

### 읽기 전용 매핑

```nim
# 자식 프로세스에서 Ledger에 접근하는 패턴
# (importc 바인딩은 state_ledger.nim에 통합)

const PROT_READ  = 1.cint
const MAP_PRIVATE = 0x02.cint

proc mmap(addr: pointer, length: csize_t, prot: cint,
          flags: cint, fd: cint, offset: Off): pointer {.
          importc: "mmap", header: "<sys/mman.h>".}

proc munmap(addr: pointer, length: csize_t): cint {.
          importc: "munmap", header: "<sys/mman.h>".}

# mmap 읽기 전용 매핑
let mapped = mmap(nil, LedgerTotalSize, PROT_READ, MAP_PRIVATE, fd, 0)
let ledger = cast[ptr GateLedger](mapped)
```

### 보안 계층

| 계층 | 메커니즘 | 목적 |
|------|---------|------|
| **OS 수준** | `PROT_READ` + `MAP_PRIVATE` | 자식 프로세스가 Ledger를 쓰거나 다른 프로세스에 영향 불가 |
| **매직 검증** | `header.magic == 0x4158474C` | 유효하지 않은 파일 접근 차단 |
| **버전 검증** | `header.version == LedgerVersion` | 레이아웃 불일치 조기 탐지 |
| **크기 검증** | `header.totalSize == LedgerTotalSize` | 손상된 파일 조기 탐지 |
| **CRC32 무결성** | `checksum == CRC32(bytes[0..0x1CDF])` | 비트 플립/부분 쓰기 탐지 |
| **원자적 쓰기** | `atomicWrite` (write-tmp → fsync → rename) | Ledger를 읽는 동안 불완전한 파일 노출 방지 |

### 유효성 검증 순서

```
  Ledger 검증 순서 (자식 프로세스)
  ─────────────────────────────────────

  1. mmap(fd, LedgerTotalSize, PROT_READ, MAP_PRIVATE, ...)
  2. cast[ptr GateLedger](mapped)
  3. if header.magic != 0x4158474C:     → REJECT (잘못된 파일)
  4. if header.version != 4:            → REJECT (버전 불일치)
  5. if header.totalSize != 7400:       → REJECT (크기 불일치)
  6. if CRC32(bytes[0..0x1CDF]) != checksum:
                                        → REJECT (무결성 실패)
  7. OK: Ledger 사용
```

---

## 7. 하위 호환성

### 환경 변수 폴백

`AXIOM_STATE_LEDGER_PATH` 환경 변수가 설정된 경우, 해당 경로의 Ledger 파일을
우선 사용한다. 미설정 시 기본 경로 `ledgers/gate.axgl`을 사용한다.

```
  폴백 순서:
  ──────────
  1. AXIOM_STATE_LEDGER_PATH (환경 변수)
  2. ${AXIOM_WORKSPACE}/ledgers/gate.axgl (기본 경로)
  3. Ledger 파일이 없으면 → 반응형 모드로 폴백 (v26 이전 동작)
```

### 버전 호환

| `LedgerVersion` | 호환성 |
|-----------------|--------|
| 4 | v27 현재 버전 (WorkspaceState v4, 56 용량 / 53 라이브 gates). 부모-자식 간 동일 바이너리에서만 호환 |
| future > 4 | `LedgerVersion` 불일치 시 자식은 자동으로 반응형 폴백 |

### 레지스트리에서 gateCount 결정

`LedgerHeader.gateCount`는 런타임에 `AxiomLedgerCap` (컴파일 타임 용량 상수,
`static_project_matrix.nim`에서 정의, 56)으로 채워진 게이트 슬롯 수와 일치한다.
`state_ledger.nim`은 `gateCount = min(gateEntries.len, AxiomLedgerCap)`로 설정한다.
라이브 게이트 수(`AxiomTotalGates`)는 `TopologySpec.len = 53`이며 `gate_contract.nim`에서
정의되어 게이트 등록에 사용된다. 불일치 시 Ledger는 무효로 처리된다.

---

## 8. 진화 역사

### v24 → v27 아키텍처 진화

| 버전 | 특징 | 한계 |
|------|------|------|
| **v24** | BSS 세그먼트 기반 PipelineContext | 프로세스 간 상태 공유 불가 |
| **v25** | 템플릿 기반 게이트 상태 관리 | 정적 layout, 확장성 제한 |
| **v26** | Static Project Matrix: BSS singleton + compile-time PageSize | 단일 프로세스 내에서만 결정론적 |
| **v27** | **State Ledger**: 크로스 프로세스 mmap 기반 상태 공유 | 현재: 최대 56 게이트 (용량) / 53 라이브 |
| **v27-v4** | **WorkspaceState v4**: stagingTreeHash 추가, padding 확장 (128→160 bytes) | 총 Ledger 크기 7,368→7,400 bytes |

### 각 버전의 핵심 혁신

```
  v24: BSS 세그먼트
  ├─ .bss에 PipelineContext 할당 (GC 프레셔 제거)
  ├─ OS 수준 demand paging 활용
  └─ 한계: 프로세스 간 공유 불가

  v25: 템플릿 기반
  ├─ 게이트 상태를 템플릿으로 관리
  ├─ 게이트 레지스트리 통합
  └─ 한계: 런타임 layout, 정적 검증 부족

  v26: Static Project Matrix
  ├─ compile-time PageSize (sysconf 제거)
  ├─ copy/sink guard (BSS 보호)
  ├─ Branchless DFA (상태 전이)
  ├─ StatusMask monoid (O(1) 집계)
  └─ 한계: 각 자식이 독립적 상태 재계산

  v27: State Ledger
  ├─ 부모-자식 mmap 기반 상태 공유
  ├─ CRC32 무결성 보장
  ├─ 원자적 쓰기 (race condition 제거)
  ├─ git 호출 53회 → 1회 (98% 감소)
  └─ 반응형 → 선제적 전환

  v27-v4: WorkspaceState v4
  ├─ stagingTreeHash 필드 추가 (CAS 격리 워크스페이스 지원)
  ├─ deferredAt + deferredStage 필드 GateStateEntry에 추가 (v3)
  └─ GateStateEntry padding 재계산: reserved 78→69 bytes
```

### 설계 의사 결정 기록

| 결정 | 근거 | 대안 |
|------|------|------|
| 고정 크기 7,400 bytes | mmap 페이지 정렬 + sizeof 검증 (56 용량 / 53 라이브 gates) | 가변 길이 (복잡성 증가) |
| CRC32 (uint32) | 빠름, 7KB 파일에 충분 | SHA-256 (과도한 오버헤드) |
| FNV-1a (uint32) | gateId 식별에 O(1) 충돌-free | 정수 인덱스 (게이트 재ordering 취약) |
| `PROT_READ` + `MAP_PRIVATE` | 자식이 Ledger 변경 불가 | `PROT_READ` only (동일 보안) |
| `AXIOM_STATE_LEDGER_PATH` 폴백 | 환경별 경로 커스터마이징 지원 | 고정 경로 (유연성 부족) |
| `ptr GateLedger` 접근 | mmap 기반 직접 포인터 접근 | 복사 기반 (오버헤드) |

---

## Appendix A: 타입 정의 요약

```nim
# src/core/gate/state_ledger_types.nim

const
  LedgerMagic*     = 0x4158474C'u32   # "AXGL"
  LedgerVersion*   = 4'u16
  LedgerHeaderSize* = 64
  LedgerWorkspaceSize* = 160
  LedgerGateEntrySize* = 128
  LedgerTotalSize* = 7400             # 64 + 160 + (AxiomLedgerCap=56 × 128) + 4 + 4

type
  LedgerStage* = enum
    lsPreCommit = 0'u8
    lsPrePush = 1'u8
    lsManual = 2'u8
    lsCi = 3'u8

  LedgerGateResult* = enum
    lgrUnknown = 0'u8
    lgrPass = 1'u8
    lgrFail = 2'u8
    lgrSkip = 3'u8
    lgrDeferred = 4'u8
```

---

## Appendix B: 빌드 플래그

| 플래그 | 기본값 | 용도 |
|--------|--------|------|
| `-d:AXIOM_STATE_LEDGER_PATH=/path` | (기본: `ledgers/gate.axgl`) | Ledger 파일 경로 오버라이드 |
| `` | (unset) | 게이트 바인드 검증 스킵 (CI 전용) |

---

## Appendix C: 컴파일 타임 검증

`state_ledger_types.nim`은 다음 `static assert`로 레이아웃 무결성을 검증한다:

```nim
static:
  assert sizeof(LedgerHeader) == LedgerHeaderSize,
    "LedgerHeader size mismatch"
  assert sizeof(WorkspaceState) == LedgerWorkspaceSize,
    "WorkspaceState size mismatch"
  assert sizeof(GateStateEntry) == LedgerGateEntrySize,
    "GateStateEntry size mismatch"
```

이 검증은 컴파일 시에 타입 크기가 명시된 상수와 정확히 일치하는지 확인한다.
레이아웃이 변경되면 컴파일이 실패하여, 런타임의 조용한 메모리 오류를 방지한다.

---

## 9. Atomic Write (v3 Fix)

### Before (vulnerable)

```nim
# state_ledger.nim — BEFORE v3 fix
discard posixUnlink(cstring(path))
discard posixRename(cstring(tmpPath), cstring(path))
```

**Gap:** Between `unlink()` and `rename()`, if the process is killed (SIGKILL, OOM, power loss), **both files are missing**,

```
  Process killed in this window
  ───┬──────────────────────────┬───
     │  unlink(old)             │  rename(tmp → old)
     │  ← old is gone ──────── │  ← tmp renamed to old
     │  BUT tmp not yet renamed │
     ▼                          ▼
  ┌──────────┐           ┌──────────┐
  │ old: GONE│           │ old: GONE│ ← old was unlinked
  │ tmp: OK  │           │ tmp: GONE│ ← but rename didn't complete
  └──────────┘           └──────────┘
  Result: NO LEDGER FILE EXISTS
```

### After (atomic — POSIX rename overwrite)

```nim
# state_ledger.nim — v3 fix
discard posixRename(cstring(tmpPath), cstring(path))
```

POSIX `rename()` atomically overwrites the destination. **No gap exists.**

```
  rename(tmp → old)
  ───┬──────────────┬───
     │  atomic step  │
     ▼              ▼
  ┌──────────┐  ┌──────────┐
  │ tmp: GONE│  │ old: NEW │ ← atomic swap
  │ old: OLD │  │ tmp: GONE│
  └──────────┘  └──────────┘
  Result: LEDGER FILE ALWAYS EXISTS (old or new, never missing)
```

### POSIX Guarantee

Reference: POSIX.1-2017 `rename()` specification:

> "If the old argument points to the pathname of a file that is not a directory, the new argument shall not point to the pathname of a directory. If the link named by the new argument exists, it is removed and old renamed to new."

This means `rename(tmpPath, path)` atomically:
1. Removes the existing `path` (if any)
2. Links `tmpPath` as `path`

There is **no window** where neither file exists.

### Impact

| Scenario | Before (unlink + rename) | After (rename only) |
|----------|--------------------------|---------------------|
| Process killed before unlink | tmp exists, old exists | tmp exists, old exists |
| Process killed after unlink, before rename | **BOTH MISSING** | Impossible |
| Process killed during rename | tmp exists, old may exist | OS guarantees atomicity |
| Normal completion | old = new | old = new |

---
## Appendix D: Limit Propagation (v32)

The `--limit` flag now correctly propagates to the IR pipeline via the Task-Injected Pipeline pattern:
- **Before**: `runAllIrPipelines()` ignored `--limit`, processing all 214 registry entries
- **After**: `selectEntriesFor(requests)` maps only the bounded frontier to registry entries

This affects the `dirtyHash` computation — fewer IR pipeline runs means faster pipeline completion.
